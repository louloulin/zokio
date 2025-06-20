//! 文件监控模块
//!
//! 提供跨平台的文件系统监控功能

const std = @import("std");
const builtin = @import("builtin");

const future = @import("../future/future.zig");
const FsError = @import("mod.zig").FsError;
const WatchConfig = @import("mod.zig").WatchConfig;

const Future = future.Future;
const Poll = future.Poll;
const Context = future.Context;

/// 文件系统事件类型
pub const EventType = enum {
    /// 文件或目录被创建
    created,
    /// 文件或目录被删除
    deleted,
    /// 文件内容被修改
    modified,
    /// 文件或目录被移动/重命名
    moved,
    /// 文件属性被修改
    metadata_changed,
    /// 其他事件
    other,
};

/// 文件系统事件
pub const Event = struct {
    /// 事件类型
    event_type: EventType,
    /// 文件路径
    path: []const u8,
    /// 旧路径（用于移动事件）
    old_path: ?[]const u8 = null,
    /// 事件时间戳
    timestamp: i64,

    const Self = @This();

    /// 检查是否是创建事件
    pub fn isCreated(self: *const Self) bool {
        return self.event_type == .created;
    }

    /// 检查是否是删除事件
    pub fn isDeleted(self: *const Self) bool {
        return self.event_type == .deleted;
    }

    /// 检查是否是修改事件
    pub fn isModified(self: *const Self) bool {
        return self.event_type == .modified;
    }

    /// 检查是否是移动事件
    pub fn isMoved(self: *const Self) bool {
        return self.event_type == .moved;
    }
};

/// 文件监控器
pub const Watcher = struct {
    allocator: std.mem.Allocator,
    config: WatchConfig,
    backend: Backend,
    watched_paths: std.StringHashMap(WatchDescriptor),
    event_buffer: std.ArrayList(Event),

    const Self = @This();

    /// 监控描述符
    const WatchDescriptor = struct {
        path: []const u8,
        recursive: bool,
        fd: i32 = -1,
    };

    /// 平台特定的后端
    const Backend = switch (builtin.os.tag) {
        .linux => LinuxBackend,
        .macos, .freebsd => KqueueBackend,
        .windows => WindowsBackend,
        else => GenericBackend,
    };

    /// 初始化文件监控器
    pub fn init(allocator: std.mem.Allocator, config: WatchConfig) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .backend = try Backend.init(),
            .watched_paths = std.StringHashMap(WatchDescriptor).init(allocator),
            .event_buffer = std.ArrayList(Event).init(allocator),
        };
    }

    /// 清理文件监控器
    pub fn deinit(self: *Self) void {
        // 清理所有监控的路径
        var iterator = self.watched_paths.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.path);
        }
        self.watched_paths.deinit();

        // 清理事件缓冲区
        for (self.event_buffer.items) |event| {
            self.allocator.free(event.path);
            if (event.old_path) |old_path| {
                self.allocator.free(old_path);
            }
        }
        self.event_buffer.deinit();

        self.backend.deinit();
    }

    /// 添加监控路径
    pub fn watch(self: *Self, path: []const u8, recursive: bool) !void {
        // 检查路径是否已经被监控
        if (self.watched_paths.contains(path)) {
            return; // 已经在监控中
        }

        // 复制路径
        const owned_path = try self.allocator.dupe(u8, path);
        const owned_key = try self.allocator.dupe(u8, path);

        // 添加到后端监控
        const fd = try self.backend.addWatch(path, recursive);

        const descriptor = WatchDescriptor{
            .path = owned_path,
            .recursive = recursive,
            .fd = fd,
        };

        try self.watched_paths.put(owned_key, descriptor);
    }

    /// 移除监控路径
    pub fn unwatch(self: *Self, path: []const u8) !void {
        if (self.watched_paths.fetchRemove(path)) |entry| {
            // 从后端移除监控
            try self.backend.removeWatch(entry.value.fd);

            // 清理内存
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.path);
        }
    }

    /// 轮询事件
    pub fn pollEvents(self: *Self) ![]Event {
        // 清空事件缓冲区
        for (self.event_buffer.items) |event| {
            self.allocator.free(event.path);
            if (event.old_path) |old_path| {
                self.allocator.free(old_path);
            }
        }
        self.event_buffer.clearRetainingCapacity();

        // 从后端读取事件
        try self.backend.readEvents(&self.event_buffer, self.allocator);

        return try self.event_buffer.toOwnedSlice();
    }

    /// 异步等待事件
    pub fn waitForEvents(self: *Self) WatchFuture {
        return WatchFuture.init(self);
    }
};

/// 监控Future
pub const WatchFuture = struct {
    watcher: *Watcher,
    events: ?[]Event = null,

    const Self = @This();
    pub const Output = ![]Event;

    pub fn init(watcher: *Watcher) Self {
        return Self{
            .watcher = watcher,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(![]Event) {
        _ = ctx;

        if (self.events == null) {
            self.events = self.watcher.pollEvents() catch |err| {
                return .{ .ready = err };
            };
        }

        if (self.events.?.len > 0) {
            return .{ .ready = self.events.? };
        } else {
            return .pending;
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.events) |events| {
            for (events) |event| {
                self.watcher.allocator.free(event.path);
                if (event.old_path) |old_path| {
                    self.watcher.allocator.free(old_path);
                }
            }
            self.watcher.allocator.free(events);
        }
    }
};

// 平台特定的后端实现

/// Linux inotify 后端
const LinuxBackend = struct {
    inotify_fd: i32,

    const Self = @This();

    pub fn init() !Self {
        const fd = std.c.inotify_init1(std.c.IN.CLOEXEC | std.c.IN.NONBLOCK);
        if (fd < 0) {
            return FsError.IoError;
        }
        return Self{ .inotify_fd = fd };
    }

    pub fn deinit(self: *Self) void {
        _ = std.c.close(self.inotify_fd);
    }

    pub fn addWatch(self: *Self, path: []const u8, recursive: bool) !i32 {
        _ = recursive; // TODO: 实现递归监控

        const mask = std.c.IN.CREATE | std.c.IN.DELETE | std.c.IN.MODIFY | std.c.IN.MOVE;
        const wd = std.c.inotify_add_watch(self.inotify_fd, path.ptr, mask);
        if (wd < 0) {
            return FsError.IoError;
        }
        return wd;
    }

    pub fn removeWatch(self: *Self, wd: i32) !void {
        const result = std.c.inotify_rm_watch(self.inotify_fd, wd);
        if (result < 0) {
            return FsError.IoError;
        }
    }

    pub fn readEvents(self: *Self, event_buffer: *std.ArrayList(Event), allocator: std.mem.Allocator) !void {
        var buffer: [4096]u8 = undefined;
        const bytes_read = std.c.read(self.inotify_fd, &buffer, buffer.len);

        if (bytes_read < 0) {
            const errno = std.c._errno().*;
            if (errno == std.c.E.AGAIN or errno == std.c.E.WOULDBLOCK) {
                return; // 没有事件
            }
            return FsError.IoError;
        }

        // 解析inotify事件
        var offset: usize = 0;
        while (offset < bytes_read) {
            const inotify_event = @as(*const std.c.inotify_event, @ptrCast(@alignCast(&buffer[offset])));
            offset += @sizeOf(std.c.inotify_event) + inotify_event.len;

            // 转换事件类型
            const event_type = if (inotify_event.mask & std.c.IN.CREATE != 0) EventType.created else if (inotify_event.mask & std.c.IN.DELETE != 0) EventType.deleted else if (inotify_event.mask & std.c.IN.MODIFY != 0) EventType.modified else if (inotify_event.mask & std.c.IN.MOVE != 0) EventType.moved else EventType.other;

            // 获取文件名
            const name_ptr = @as([*:0]const u8, @ptrCast(&buffer[@sizeOf(std.c.inotify_event)]));
            const name = std.mem.span(name_ptr);
            const owned_path = try allocator.dupe(u8, name);

            const event = Event{
                .event_type = event_type,
                .path = owned_path,
                .timestamp = std.time.timestamp(),
            };

            try event_buffer.append(event);
        }
    }
};

/// macOS/FreeBSD kqueue 后端
const KqueueBackend = struct {
    kqueue_fd: i32,

    const Self = @This();

    pub fn init() !Self {
        const fd = std.c.kqueue();
        if (fd < 0) {
            return FsError.IoError;
        }
        return Self{ .kqueue_fd = fd };
    }

    pub fn deinit(self: *Self) void {
        _ = std.c.close(self.kqueue_fd);
    }

    pub fn addWatch(self: *Self, path: []const u8, recursive: bool) !i32 {
        _ = self;
        _ = path;
        _ = recursive;
        // TODO: 实现kqueue监控
        return 0;
    }

    pub fn removeWatch(self: *Self, wd: i32) !void {
        _ = self;
        _ = wd;
        // TODO: 实现kqueue监控移除
    }

    pub fn readEvents(self: *Self, event_buffer: *std.ArrayList(Event), allocator: std.mem.Allocator) !void {
        _ = self;
        _ = event_buffer;
        _ = allocator;
        // TODO: 实现kqueue事件读取
    }
};

/// Windows 后端
const WindowsBackend = struct {
    pub fn init() !@This() {
        return @This(){};
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn addWatch(self: *@This(), path: []const u8, recursive: bool) !i32 {
        _ = self;
        _ = path;
        _ = recursive;
        return FsError.NotSupported;
    }

    pub fn removeWatch(self: *@This(), wd: i32) !void {
        _ = self;
        _ = wd;
        return FsError.NotSupported;
    }

    pub fn readEvents(self: *@This(), event_buffer: *std.ArrayList(Event), allocator: std.mem.Allocator) !void {
        _ = self;
        _ = event_buffer;
        _ = allocator;
        return FsError.NotSupported;
    }
};

/// 通用后端（不支持监控）
const GenericBackend = struct {
    pub fn init() !@This() {
        return @This(){};
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn addWatch(self: *@This(), path: []const u8, recursive: bool) !i32 {
        _ = self;
        _ = path;
        _ = recursive;
        return FsError.NotSupported;
    }

    pub fn removeWatch(self: *@This(), wd: i32) !void {
        _ = self;
        _ = wd;
        return FsError.NotSupported;
    }

    pub fn readEvents(self: *@This(), event_buffer: *std.ArrayList(Event), allocator: std.mem.Allocator) !void {
        _ = self;
        _ = event_buffer;
        _ = allocator;
        return FsError.NotSupported;
    }
};

// 测试
test "事件类型检查" {
    const testing = std.testing;

    const event = Event{
        .event_type = .created,
        .path = "test.txt",
        .timestamp = std.time.timestamp(),
    };

    try testing.expect(event.isCreated());
    try testing.expect(!event.isDeleted());
    try testing.expect(!event.isModified());
    try testing.expect(!event.isMoved());
}

test "监控器初始化" {
    const testing = std.testing;

    const config = WatchConfig{};
    var watcher = Watcher.init(testing.allocator, config) catch |err| {
        // 在不支持的平台上跳过测试
        if (err == FsError.NotSupported) {
            return;
        }
        return err;
    };
    defer watcher.deinit();

    // 基本功能测试
    try testing.expect(watcher.watched_paths.count() == 0);
}
