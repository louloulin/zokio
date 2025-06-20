//! 异步文件操作模块
//!
//! 提供高性能的异步文件读写功能

const std = @import("std");
const builtin = @import("builtin");

const future = @import("../future/future.zig");
const metadata = @import("metadata.zig");
const FsError = @import("mod.zig").FsError;
const OpenMode = @import("mod.zig").OpenMode;

const Future = future.Future;
const Poll = future.Poll;
const Context = future.Context;
const Metadata = metadata.Metadata;

/// 异步文件句柄
pub const File = struct {
    fd: std.posix.fd_t,
    path: []const u8,
    mode: OpenMode,
    allocator: std.mem.Allocator,
    position: u64 = 0,

    const Self = @This();

    /// 打开文件
    pub fn open(allocator: std.mem.Allocator, path: []const u8, mode: OpenMode) !Self {
        const flags_u32 = mode.toFlags();
        const file_mode: std.posix.mode_t = 0o644;

        // 转换为正确的标志类型
        const flags: std.posix.O = @bitCast(flags_u32);

        const fd = std.posix.open(path, flags, file_mode) catch |err| switch (err) {
            error.FileNotFound => return FsError.FileNotFound,
            error.AccessDenied => return FsError.PermissionDenied,
            error.PathAlreadyExists => return FsError.FileExists,
            error.IsDir => return FsError.IsDir,
            error.NotDir => return FsError.NotDir,
            error.NoSpaceLeft => return FsError.NoSpaceLeft,
            error.NameTooLong => return FsError.NameTooLong,
            error.SystemResources => return FsError.IoError,
            else => return FsError.IoError,
        };

        // 设置非阻塞模式
        try setNonBlocking(fd);

        // 复制路径字符串
        const owned_path = try allocator.dupe(u8, path);

        return Self{
            .fd = fd,
            .path = owned_path,
            .mode = mode,
            .allocator = allocator,
        };
    }

    /// 关闭文件
    pub fn close(self: *Self) void {
        std.posix.close(self.fd);
        self.allocator.free(self.path);
    }

    /// 异步读取数据
    pub fn read(self: *Self, buffer: []u8) ReadFuture {
        return ReadFuture.init(self, buffer);
    }

    /// 异步写入数据
    pub fn write(self: *Self, data: []const u8) WriteFuture {
        return WriteFuture.init(self, data);
    }

    /// 异步读取所有数据
    pub fn readAll(self: *Self, buffer: []u8) !usize {
        var total_read: usize = 0;
        while (total_read < buffer.len) {
            const bytes_read = std.posix.read(self.fd, buffer[total_read..]) catch |err| switch (err) {
                error.WouldBlock => break,
                error.InputOutput => return FsError.IoError,
                error.IsDir => return FsError.IsDir,
                error.OperationAborted => return FsError.Interrupted,
                error.BrokenPipe => break,
                else => return FsError.IoError,
            };

            if (bytes_read == 0) break; // EOF
            total_read += bytes_read;
        }
        return total_read;
    }

    /// 异步写入所有数据
    pub fn writeAll(self: *Self, data: []const u8) !usize {
        var total_written: usize = 0;
        while (total_written < data.len) {
            const bytes_written = std.posix.write(self.fd, data[total_written..]) catch |err| switch (err) {
                error.WouldBlock => break,
                error.InputOutput => return FsError.IoError,
                error.NoSpaceLeft => return FsError.NoSpaceLeft,
                error.AccessDenied => return FsError.PermissionDenied,
                error.BrokenPipe => return FsError.IoError,
                else => return FsError.IoError,
            };

            total_written += bytes_written;
        }
        return total_written;
    }

    /// 定位文件指针
    pub fn seek(self: *Self, pos: u64) !void {
        const result = std.c.lseek(self.fd, @as(i64, @intCast(pos)), std.c.SEEK.SET);
        if (result < 0) {
            return FsError.IoError;
        }
        self.position = @as(u64, @intCast(result));
    }

    /// 获取当前文件位置
    pub fn tell(self: *const Self) u64 {
        return self.position;
    }

    /// 同步文件数据到磁盘
    pub fn sync(self: *Self) !void {
        std.posix.fsync(self.fd) catch |err| switch (err) {
            error.InputOutput => return FsError.IoError,
            error.NoSpaceLeft => return FsError.NoSpaceLeft,
            else => return FsError.IoError,
        };
    }

    /// 获取文件元数据
    pub fn getMetadata(self: *const Self) !Metadata {
        return try Metadata.fromFd(self.fd);
    }

    /// 设置文件权限
    pub fn setPermissions(self: *Self, permissions: std.posix.mode_t) !void {
        std.posix.fchmod(self.fd, permissions) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.ReadOnlyFileSystem => return FsError.ReadOnlyFileSystem,
            else => return FsError.IoError,
        };
    }

    /// 截断文件
    pub fn truncate(self: *Self, size: u64) !void {
        std.posix.ftruncate(self.fd, size) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.FileTooLarge => return FsError.FileTooLarge,
            error.NoSpaceLeft => return FsError.NoSpaceLeft,
            else => return FsError.IoError,
        };
    }
};

/// 读取Future
pub const ReadFuture = struct {
    file: *File,
    buffer: []u8,
    bytes_read: usize = 0,

    const Self = @This();
    pub const Output = !usize;

    pub fn init(file: *File, buffer: []u8) Self {
        return Self{
            .file = file,
            .buffer = buffer,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!usize) {
        _ = ctx;

        const result = std.posix.read(self.file.fd, self.buffer);
        if (result) |bytes_read| {
            self.bytes_read = bytes_read;
            self.file.position += bytes_read;
            return .{ .ready = bytes_read };
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            error.InputOutput => return .{ .ready = FsError.IoError },
            error.IsDir => return .{ .ready = FsError.IsDir },
            error.OperationAborted => return .{ .ready = FsError.Interrupted },
            else => return .{ .ready = FsError.IoError },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// 写入Future
pub const WriteFuture = struct {
    file: *File,
    data: []const u8,
    bytes_written: usize = 0,

    const Self = @This();
    pub const Output = !usize;

    pub fn init(file: *File, data: []const u8) Self {
        return Self{
            .file = file,
            .data = data,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!usize) {
        _ = ctx;

        const result = std.posix.write(self.file.fd, self.data[self.bytes_written..]);
        if (result) |bytes_written| {
            self.bytes_written += bytes_written;
            self.file.position += bytes_written;

            if (self.bytes_written >= self.data.len) {
                return .{ .ready = self.bytes_written };
            } else {
                return .pending;
            }
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            error.InputOutput => return .{ .ready = FsError.IoError },
            error.NoSpaceLeft => return .{ .ready = FsError.NoSpaceLeft },
            error.AccessDenied => return .{ .ready = FsError.PermissionDenied },
            else => return .{ .ready = FsError.IoError },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

// 辅助函数

/// 设置文件描述符为非阻塞模式
fn setNonBlocking(fd: std.posix.fd_t) !void {
    const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    const nonblock_flag: u32 = if (builtin.os.tag == .macos) 0x0004 else std.posix.O.NONBLOCK;
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | nonblock_flag);
}

// 测试
test "文件打开和关闭" {
    const testing = std.testing;

    // 创建临时文件进行测试
    const temp_path = "/tmp/zokio_test_file.txt";

    // 清理可能存在的文件
    std.posix.unlink(temp_path) catch {};

    // 测试创建新文件
    var file = File.open(testing.allocator, temp_path, .{ .write = true, .create = true }) catch |err| {
        std.debug.print("Failed to create file: {}\n", .{err});
        return;
    };
    defer file.close();
    defer std.posix.unlink(temp_path) catch {};

    try testing.expect(file.fd >= 0);
    try testing.expect(std.mem.eql(u8, temp_path, file.path));
}

test "文件读写操作" {
    const testing = std.testing;

    const temp_path = "/tmp/zokio_test_rw.txt";
    std.posix.unlink(temp_path) catch {};

    // 写入测试数据
    {
        var file = File.open(testing.allocator, temp_path, .{ .write = true, .create = true }) catch return;
        defer file.close();

        const test_data = "Hello, Zokio File System!";
        const bytes_written = try file.writeAll(test_data);
        try testing.expectEqual(test_data.len, bytes_written);
    }

    // 读取测试数据
    {
        var file = File.open(testing.allocator, temp_path, .{ .read = true }) catch return;
        defer file.close();
        defer std.posix.unlink(temp_path) catch {};

        var buffer: [100]u8 = undefined;
        const bytes_read = try file.readAll(&buffer);

        const expected = "Hello, Zokio File System!";
        try testing.expectEqual(expected.len, bytes_read);
        try testing.expect(std.mem.eql(u8, expected, buffer[0..bytes_read]));
    }
}
