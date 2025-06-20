//! 目录操作模块
//!
//! 提供异步目录遍历和操作功能

const std = @import("std");
const builtin = @import("builtin");

const future = @import("../future/future.zig");
const metadata = @import("metadata.zig");
const FsError = @import("mod.zig").FsError;

const Future = future.Future;
const Poll = future.Poll;
const Context = future.Context;
const Metadata = metadata.Metadata;
const FileType = metadata.FileType;

/// 目录条目
pub const DirEntry = struct {
    /// 文件名
    name: []const u8,
    /// 文件类型
    file_type: FileType,
    /// 完整路径
    path: []const u8,

    const Self = @This();

    /// 获取元数据
    pub fn getMetadata(self: *const Self) !Metadata {
        return try Metadata.fromPath(self.path);
    }

    /// 检查是否是文件
    pub fn isFile(self: *const Self) bool {
        return self.file_type == .file;
    }

    /// 检查是否是目录
    pub fn isDir(self: *const Self) bool {
        return self.file_type == .directory;
    }

    /// 检查是否是符号链接
    pub fn isSymlink(self: *const Self) bool {
        return self.file_type == .symlink;
    }
};

/// 目录句柄
pub const Dir = struct {
    path: []const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 打开目录
    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Self {
        // 检查路径是否存在且是目录
        var stat_buf: std.c.Stat = undefined;
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        const stat_result = std.c.stat(path_z.ptr, &stat_buf);
        if (stat_result != 0) {
            return FsError.FileNotFound;
        }

        if (!std.c.S.ISDIR(stat_buf.mode)) {
            return FsError.NotDir;
        }

        const owned_path = try allocator.dupe(u8, path);
        return Self{
            .path = owned_path,
            .allocator = allocator,
        };
    }

    /// 关闭目录
    pub fn close(self: *Self) void {
        self.allocator.free(self.path);
    }

    /// 读取目录条目
    pub fn readEntries(self: *Self) ![]DirEntry {
        var entries = std.ArrayList(DirEntry).init(self.allocator);
        defer entries.deinit();

        var dir = std.fs.cwd().openDir(self.path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return FsError.FileNotFound,
            error.AccessDenied => return FsError.PermissionDenied,
            error.NotDir => return FsError.NotDir,
            else => return FsError.IoError,
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            // 构建完整路径
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.path, entry.name });

            // 复制文件名
            const name = try self.allocator.dupe(u8, entry.name);

            const dir_entry = DirEntry{
                .name = name,
                .file_type = switch (entry.kind) {
                    .file => .file,
                    .directory => .directory,
                    .sym_link => .symlink,
                    .block_device => .block_device,
                    .character_device => .char_device,
                    .named_pipe => .fifo,
                    .unix_domain_socket => .socket,
                    else => .unknown,
                },
                .path = full_path,
            };

            try entries.append(dir_entry);
        }

        return try entries.toOwnedSlice();
    }

    /// 异步遍历目录
    pub fn walk(self: *Self, recursive: bool) WalkFuture {
        return WalkFuture.init(self, recursive);
    }

    /// 创建目录
    pub fn create(path: []const u8, mode: std.posix.mode_t) !void {
        std.posix.mkdir(path, mode) catch |err| switch (err) {
            error.PathAlreadyExists => return FsError.FileExists,
            error.AccessDenied => return FsError.PermissionDenied,
            error.FileNotFound => return FsError.FileNotFound,
            error.NotDir => return FsError.NotDir,
            error.NoSpaceLeft => return FsError.NoSpaceLeft,
            error.ReadOnlyFileSystem => return FsError.ReadOnlyFileSystem,
            else => return FsError.IoError,
        };
    }

    /// 递归创建目录
    pub fn createAll(allocator: std.mem.Allocator, path: []const u8, mode: std.posix.mode_t) !void {
        var path_buf = try allocator.dupe(u8, path);
        defer allocator.free(path_buf);

        // 标准化路径
        std.mem.replaceScalar(u8, path_buf, '\\', '/');

        var i: usize = 0;
        while (i < path_buf.len) {
            if (path_buf[i] == '/' and i > 0) {
                path_buf[i] = 0; // 临时终止字符串

                // 尝试创建目录
                create(path_buf[0..i], mode) catch |err| switch (err) {
                    FsError.FileExists => {}, // 目录已存在，继续
                    else => return err,
                };

                path_buf[i] = '/'; // 恢复字符
            }
            i += 1;
        }

        // 创建最终目录
        create(path_buf, mode) catch |err| switch (err) {
            FsError.FileExists => {}, // 目录已存在
            else => return err,
        };
    }

    /// 删除目录
    pub fn remove(path: []const u8) !void {
        std.posix.rmdir(path) catch |err| switch (err) {
            error.FileNotFound => return FsError.FileNotFound,
            error.AccessDenied => return FsError.PermissionDenied,
            error.DirNotEmpty => return FsError.DirNotEmpty,
            error.NotDir => return FsError.NotDir,
            error.FileBusy => return FsError.DeviceBusy,
            else => return FsError.IoError,
        };
    }

    /// 递归删除目录
    pub fn removeAll(allocator: std.mem.Allocator, path: []const u8) !void {
        var dir_handle = Dir.open(allocator, path) catch |err| switch (err) {
            FsError.FileNotFound => return, // 目录不存在，认为删除成功
            else => return err,
        };
        defer dir_handle.close();

        const entries = try dir_handle.readEntries();
        defer {
            for (entries) |entry| {
                allocator.free(entry.name);
                allocator.free(entry.path);
            }
            allocator.free(entries);
        }

        // 递归删除子项
        for (entries) |entry| {
            if (entry.isDir()) {
                try removeAll(allocator, entry.path);
            } else {
                std.posix.unlink(entry.path) catch |err| switch (err) {
                    error.FileNotFound => {}, // 文件已被删除
                    error.AccessDenied => return FsError.PermissionDenied,
                    else => return FsError.IoError,
                };
            }
        }

        // 删除目录本身
        try remove(path);
    }
};

/// 目录遍历Future
pub const WalkFuture = struct {
    dir: *Dir,
    recursive: bool,
    entries: ?[]DirEntry = null,
    current_index: usize = 0,

    const Self = @This();
    pub const Output = ![]DirEntry;

    pub fn init(dir: *Dir, recursive: bool) Self {
        return Self{
            .dir = dir,
            .recursive = recursive,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(![]DirEntry) {
        _ = ctx;

        if (self.entries == null) {
            // 第一次调用，读取目录条目
            self.entries = self.dir.readEntries() catch |err| {
                return .{ .ready = err };
            };
        }

        if (self.recursive) {
            // TODO: 实现递归遍历逻辑
            // 这里需要更复杂的状态管理来处理递归遍历
        }

        return .{ .ready = self.entries.? };
    }

    pub fn deinit(self: *Self) void {
        if (self.entries) |entries| {
            for (entries) |entry| {
                self.dir.allocator.free(entry.name);
                self.dir.allocator.free(entry.path);
            }
            self.dir.allocator.free(entries);
        }
    }
};

// 便捷函数

/// 检查目录是否存在
pub fn exists(path: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stat_buf: std.c.Stat = undefined;
    const path_z = allocator.dupeZ(u8, path) catch return false;
    const stat_result = std.c.stat(path_z.ptr, &stat_buf);
    if (stat_result != 0) return false;
    return std.c.S.ISDIR(stat_buf.mode);
}

/// 检查目录是否为空
pub fn isEmpty(allocator: std.mem.Allocator, path: []const u8) !bool {
    var dir_handle = Dir.open(allocator, path) catch return false;
    defer dir_handle.close();

    const entries = try dir_handle.readEntries();
    defer {
        for (entries) |entry| {
            allocator.free(entry.name);
            allocator.free(entry.path);
        }
        allocator.free(entries);
    }

    return entries.len == 0;
}

// 测试
test "目录创建和删除" {
    const testing = std.testing;

    const test_dir = "/tmp/zokio_test_dir";

    // 清理可能存在的目录
    Dir.removeAll(testing.allocator, test_dir) catch {};

    // 创建目录
    try Dir.create(test_dir, 0o755);
    try testing.expect(exists(test_dir));

    // 检查目录是否为空
    const is_empty = try isEmpty(testing.allocator, test_dir);
    try testing.expect(is_empty);

    // 删除目录
    try Dir.remove(test_dir);
    try testing.expect(!exists(test_dir));
}

test "递归目录操作" {
    const testing = std.testing;

    const base_dir = "/tmp/zokio_test_recursive";
    const sub_dir = "/tmp/zokio_test_recursive/sub/deep";

    // 清理
    Dir.removeAll(testing.allocator, base_dir) catch {};

    // 递归创建目录
    try Dir.createAll(testing.allocator, sub_dir, 0o755);
    try testing.expect(exists(base_dir));
    try testing.expect(exists(sub_dir));

    // 递归删除
    try Dir.removeAll(testing.allocator, base_dir);
    try testing.expect(!exists(base_dir));
}
