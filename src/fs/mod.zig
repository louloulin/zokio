//! 文件系统模块
//!
//! 提供高性能的异步文件系统操作支持

const std = @import("std");
const builtin = @import("builtin");

// 导出文件系统相关模块
pub const file = @import("file.zig");
pub const dir = @import("dir.zig");
pub const metadata = @import("metadata.zig");
pub const watch = @import("watch.zig");
pub const mmap = @import("mmap.zig");

// 导出核心类型
pub const File = file.File;
pub const Dir = dir.Dir;
pub const Metadata = metadata.Metadata;
pub const FileType = metadata.FileType;
pub const Permissions = metadata.Permissions;

// 导出文件系统错误类型
pub const FsError = error{
    /// 文件或目录不存在
    FileNotFound,
    /// 权限被拒绝
    PermissionDenied,
    /// 文件已存在
    FileExists,
    /// 不是目录
    NotDir,
    /// 是目录
    IsDir,
    /// 设备上没有空间
    NoSpaceLeft,
    /// 文件名太长
    NameTooLong,
    /// 只读文件系统
    ReadOnlyFileSystem,
    /// 文件系统循环
    FilesystemLoop,
    /// 操作被中断
    Interrupted,
    /// 无效的参数
    InvalidArgument,
    /// I/O错误
    IoError,
    /// 资源暂时不可用
    WouldBlock,
    /// 文件太大
    FileTooLarge,
    /// 设备忙
    DeviceBusy,
    /// 跨设备链接
    CrossDeviceLink,
    /// 目录不为空
    DirNotEmpty,
    /// 文件描述符无效
    BadFileDescriptor,
    /// 操作不支持
    NotSupported,
};

/// 文件打开模式
pub const OpenMode = struct {
    /// 读取权限
    read: bool = false,
    /// 写入权限
    write: bool = false,
    /// 追加模式
    append: bool = false,
    /// 创建文件（如果不存在）
    create: bool = false,
    /// 创建新文件（如果存在则失败）
    create_new: bool = false,
    /// 截断文件
    truncate: bool = false,

    /// 只读模式
    pub const READ_ONLY = OpenMode{ .read = true };
    /// 只写模式
    pub const WRITE_ONLY = OpenMode{ .write = true, .create = true };
    /// 读写模式
    pub const READ_WRITE = OpenMode{ .read = true, .write = true, .create = true };
    /// 追加模式
    pub const APPEND = OpenMode{ .write = true, .append = true, .create = true };

    /// 转换为系统标志
    pub fn toFlags(self: OpenMode) u32 {
        var flags: u32 = 0;

        // 使用平台特定的标志
        if (builtin.os.tag == .macos) {
            if (self.read and self.write) {
                flags |= 0x0002; // O_RDWR
            } else if (self.write) {
                flags |= 0x0001; // O_WRONLY
            } else {
                flags |= 0x0000; // O_RDONLY
            }

            if (self.create) flags |= 0x0200; // O_CREAT
            if (self.create_new) flags |= 0x0200 | 0x0800; // O_CREAT | O_EXCL
            if (self.truncate) flags |= 0x0400; // O_TRUNC
            if (self.append) flags |= 0x0008; // O_APPEND
            flags |= 0x0004; // O_NONBLOCK
        } else {
            // Linux和其他平台
            if (self.read and self.write) {
                flags |= std.posix.O.RDWR;
            } else if (self.write) {
                flags |= std.posix.O.WRONLY;
            } else {
                flags |= std.posix.O.RDONLY;
            }

            if (self.create) flags |= std.posix.O.CREAT;
            if (self.create_new) flags |= std.posix.O.CREAT | std.posix.O.EXCL;
            if (self.truncate) flags |= std.posix.O.TRUNC;
            if (self.append) flags |= std.posix.O.APPEND;
            flags |= std.posix.O.NONBLOCK;
        }

        return flags;
    }
};

/// 文件系统配置
pub const FsConfig = struct {
    /// 默认文件权限
    default_file_mode: u32 = 0o644,
    /// 默认目录权限
    default_dir_mode: u32 = 0o755,
    /// 读取缓冲区大小
    read_buffer_size: u32 = 64 * 1024,
    /// 写入缓冲区大小
    write_buffer_size: u32 = 64 * 1024,
    /// 是否启用直接I/O
    enable_direct_io: bool = false,
    /// 是否启用同步I/O
    enable_sync_io: bool = false,
    /// 文件监控配置
    watch_config: WatchConfig = .{},
    /// 内存映射配置
    mmap_config: MmapConfig = .{},
};

/// 文件监控配置
pub const WatchConfig = struct {
    /// 是否启用递归监控
    recursive: bool = false,
    /// 监控事件缓冲区大小
    event_buffer_size: u32 = 1024,
    /// 监控超时时间（毫秒）
    timeout_ms: u32 = 1000,
};

/// 内存映射配置
pub const MmapConfig = struct {
    /// 页面大小
    page_size: u32 = 4096,
    /// 是否启用预读
    enable_prefault: bool = true,
    /// 是否启用写时复制
    enable_copy_on_write: bool = false,
};

/// 文件系统统计信息
pub const FsStats = struct {
    /// 打开的文件数
    open_files: u64 = 0,
    /// 读取操作数
    read_operations: u64 = 0,
    /// 写入操作数
    write_operations: u64 = 0,
    /// 读取字节数
    bytes_read: u64 = 0,
    /// 写入字节数
    bytes_written: u64 = 0,
    /// 文件系统错误数
    fs_errors: u64 = 0,
    /// 监控的目录数
    watched_directories: u64 = 0,
    /// 内存映射文件数
    mapped_files: u64 = 0,

    /// 获取I/O统计
    pub fn getIoStats(self: *const FsStats) IoStats {
        return IoStats{
            .total_operations = self.read_operations + self.write_operations,
            .read_operations = self.read_operations,
            .write_operations = self.write_operations,
            .total_bytes = self.bytes_read + self.bytes_written,
            .bytes_read = self.bytes_read,
            .bytes_written = self.bytes_written,
        };
    }

    /// 获取错误率
    pub fn getErrorRate(self: *const FsStats) f64 {
        const total_ops = self.read_operations + self.write_operations;
        if (total_ops == 0) return 0.0;
        return @as(f64, @floatFromInt(self.fs_errors)) / @as(f64, @floatFromInt(total_ops));
    }
};

/// I/O统计
pub const IoStats = struct {
    total_operations: u64,
    read_operations: u64,
    write_operations: u64,
    total_bytes: u64,
    bytes_read: u64,
    bytes_written: u64,
};

/// 文件系统管理器
pub const FsManager = struct {
    config: FsConfig,
    stats: FsStats,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 初始化文件系统管理器
    pub fn init(allocator: std.mem.Allocator, config: FsConfig) Self {
        return Self{
            .config = config,
            .stats = FsStats{},
            .allocator = allocator,
        };
    }

    /// 清理文件系统管理器
    pub fn deinit(self: *Self) void {
        _ = self;
        // 清理资源
    }

    /// 获取统计信息
    pub fn getStats(self: *const Self) FsStats {
        return self.stats;
    }

    /// 重置统计信息
    pub fn resetStats(self: *Self) void {
        self.stats = FsStats{};
    }

    /// 更新统计信息
    pub fn updateStats(self: *Self, comptime field: []const u8, delta: u64) void {
        @field(self.stats, field) += delta;
    }

    /// 打开文件
    pub fn openFile(self: *Self, path: []const u8, mode: OpenMode) !File {
        const file_handle = try File.open(self.allocator, path, mode);
        self.updateStats("open_files", 1);
        return file_handle;
    }

    /// 创建目录
    pub fn createDir(self: *Self, path: []const u8) !void {
        try Dir.create(path, self.config.default_dir_mode);
    }

    /// 删除文件
    pub fn removeFile(self: *Self, path: []const u8) !void {
        _ = self;
        try std.posix.unlink(path);
    }

    /// 删除目录
    pub fn removeDir(self: *Self, path: []const u8) !void {
        _ = self;
        try std.posix.rmdir(path);
    }

    /// 获取文件元数据
    pub fn getMetadata(self: *Self, path: []const u8) !Metadata {
        _ = self;
        return try Metadata.fromPath(path);
    }
};

// 便捷函数

/// 异步读取整个文件
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file_handle = try File.open(allocator, path, OpenMode.READ_ONLY);
    defer file_handle.close();

    const file_metadata = try file_handle.getMetadata();
    const file_size = file_metadata.size;

    const contents = try allocator.alloc(u8, file_size);
    _ = try file_handle.readAll(contents);

    return contents;
}

/// 异步写入整个文件
pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    var file_handle = try File.open(allocator, path, OpenMode{ .write = true, .create = true, .truncate = true });
    defer file_handle.close();

    _ = try file_handle.writeAll(data);
}

/// 检查文件是否存在
pub fn exists(path: []const u8) bool {
    std.posix.access(path, std.posix.F_OK) catch return false;
    return true;
}

/// 复制文件
pub fn copyFile(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    const data = try readFile(allocator, src_path);
    defer allocator.free(data);
    try writeFile(allocator, dst_path, data);
}

// 测试
test "文件系统配置默认值" {
    const testing = std.testing;

    const config = FsConfig{};
    try testing.expectEqual(@as(u32, 0o644), config.default_file_mode);
    try testing.expectEqual(@as(u32, 0o755), config.default_dir_mode);
    try testing.expectEqual(@as(u32, 64 * 1024), config.read_buffer_size);
    try testing.expect(!config.enable_direct_io);
}

test "打开模式标志转换" {
    const testing = std.testing;

    const read_only = OpenMode.READ_ONLY;
    const flags = read_only.toFlags();

    // 在macOS上使用硬编码值，在其他平台使用posix标志
    if (builtin.os.tag == .macos) {
        try testing.expect((flags & 0x0004) != 0); // O_NONBLOCK
    } else {
        try testing.expect((flags & std.posix.O.NONBLOCK) != 0);
    }

    const write_mode = OpenMode{ .write = true, .create = true };
    const write_flags = write_mode.toFlags();

    if (builtin.os.tag == .macos) {
        try testing.expect((write_flags & 0x0001) != 0); // O_WRONLY
        try testing.expect((write_flags & 0x0200) != 0); // O_CREAT
    } else {
        try testing.expect((write_flags & std.posix.O.WRONLY) != 0);
        try testing.expect((write_flags & std.posix.O.CREAT) != 0);
    }
}

test "文件系统统计功能" {
    const testing = std.testing;

    var stats = FsStats{};
    stats.read_operations = 100;
    stats.write_operations = 50;
    stats.bytes_read = 1024;
    stats.bytes_written = 512;
    stats.fs_errors = 5;

    const io_stats = stats.getIoStats();
    try testing.expectEqual(@as(u64, 150), io_stats.total_operations);
    try testing.expectEqual(@as(u64, 1536), io_stats.total_bytes);

    const error_rate = stats.getErrorRate();
    try testing.expectEqual(@as(f64, 5.0 / 150.0), error_rate);
}

test "文件系统管理器基础功能" {
    const testing = std.testing;

    const config = FsConfig{};
    var manager = FsManager.init(testing.allocator, config);
    defer manager.deinit();

    // 测试统计更新
    manager.updateStats("read_operations", 10);
    manager.updateStats("bytes_read", 1024);

    const stats = manager.getStats();
    try testing.expectEqual(@as(u64, 10), stats.read_operations);
    try testing.expectEqual(@as(u64, 1024), stats.bytes_read);

    // 测试重置
    manager.resetStats();
    const reset_stats = manager.getStats();
    try testing.expectEqual(@as(u64, 0), reset_stats.read_operations);
    try testing.expectEqual(@as(u64, 0), reset_stats.bytes_read);
}
