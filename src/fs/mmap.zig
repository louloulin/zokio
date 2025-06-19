//! 内存映射文件模块
//!
//! 提供高性能的内存映射文件操作

const std = @import("std");
const builtin = @import("builtin");

const FsError = @import("mod.zig").FsError;
const MmapConfig = @import("mod.zig").MmapConfig;

/// 内存映射保护模式
pub const Protection = struct {
    read: bool = false,
    write: bool = false,
    execute: bool = false,

    /// 只读模式
    pub const READ_ONLY = Protection{ .read = true };
    /// 读写模式
    pub const READ_WRITE = Protection{ .read = true, .write = true };
    /// 可执行模式
    pub const EXECUTABLE = Protection{ .read = true, .execute = true };

    /// 转换为系统保护标志
    pub fn toFlags(self: Protection) u32 {
        var flags: u32 = 0;
        if (self.read) flags |= std.posix.PROT.READ;
        if (self.write) flags |= std.posix.PROT.WRITE;
        if (self.execute) flags |= std.posix.PROT.EXEC;
        return flags;
    }
};

/// 内存映射标志
pub const MapFlags = struct {
    shared: bool = false,
    private: bool = true,
    anonymous: bool = false,
    fixed: bool = false,
    populate: bool = false,

    /// 共享映射
    pub const SHARED = MapFlags{ .shared = true, .private = false };
    /// 私有映射
    pub const PRIVATE = MapFlags{ .private = true, .shared = false };
    /// 匿名映射
    pub const ANONYMOUS = MapFlags{ .anonymous = true, .private = true };

    /// 转换为系统映射标志
    pub fn toFlags(self: MapFlags) u32 {
        var flags: u32 = 0;
        
        if (self.shared) flags |= std.posix.MAP.SHARED;
        if (self.private) flags |= std.posix.MAP.PRIVATE;
        if (self.anonymous) flags |= std.posix.MAP.ANONYMOUS;
        if (self.fixed) flags |= std.posix.MAP.FIXED;
        
        // 平台特定标志
        if (builtin.os.tag == .linux and self.populate) {
            flags |= std.posix.MAP.POPULATE;
        }
        
        return flags;
    }
};

/// 内存映射文件
pub const MmapFile = struct {
    ptr: [*]u8,
    len: usize,
    fd: ?std.posix.fd_t,
    protection: Protection,
    flags: MapFlags,
    config: MmapConfig,

    const Self = @This();

    /// 创建文件内存映射
    pub fn fromFile(fd: std.posix.fd_t, offset: u64, length: usize, protection: Protection, flags: MapFlags, config: MmapConfig) !Self {
        const prot_flags = protection.toFlags();
        const map_flags = flags.toFlags();

        const ptr = std.posix.mmap(
            null,
            length,
            prot_flags,
            map_flags,
            fd,
            offset,
        ) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.MemoryMappingNotSupported => return FsError.NotSupported,
            error.ProcessFdQuotaExceeded => return FsError.IoError,
            error.SystemFdQuotaExceeded => return FsError.IoError,
            error.SystemResources => return FsError.IoError,
            else => return FsError.IoError,
        };

        return Self{
            .ptr = @as([*]u8, @ptrCast(ptr)),
            .len = length,
            .fd = fd,
            .protection = protection,
            .flags = flags,
            .config = config,
        };
    }

    /// 创建匿名内存映射
    pub fn anonymous(length: usize, protection: Protection, config: MmapConfig) !Self {
        const flags = MapFlags.ANONYMOUS;
        const prot_flags = protection.toFlags();
        const map_flags = flags.toFlags();

        const ptr = std.posix.mmap(
            null,
            length,
            prot_flags,
            map_flags,
            -1,
            0,
        ) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            error.MemoryMappingNotSupported => return FsError.NotSupported,
            error.ProcessFdQuotaExceeded => return FsError.IoError,
            error.SystemFdQuotaExceeded => return FsError.IoError,
            error.SystemResources => return FsError.IoError,
            else => return FsError.IoError,
        };

        return Self{
            .ptr = @as([*]u8, @ptrCast(ptr)),
            .len = length,
            .fd = null,
            .protection = protection,
            .flags = flags,
            .config = config,
        };
    }

    /// 取消内存映射
    pub fn unmap(self: *Self) !void {
        std.posix.munmap(@as([*]align(std.mem.page_size) u8, @alignCast(self.ptr))[0..self.len]) catch |err| switch (err) {
            else => return FsError.IoError,
        };
    }

    /// 获取映射的内存切片
    pub fn asSlice(self: *const Self) []u8 {
        return self.ptr[0..self.len];
    }

    /// 获取只读内存切片
    pub fn asConstSlice(self: *const Self) []const u8 {
        return self.ptr[0..self.len];
    }

    /// 同步内存到磁盘
    pub fn sync(self: *Self, async_sync: bool) !void {
        const flags: u32 = if (async_sync) std.posix.MS.ASYNC else std.posix.MS.SYNC;
        
        std.posix.msync(@as([*]align(std.mem.page_size) u8, @alignCast(self.ptr))[0..self.len], flags) catch |err| switch (err) {
            error.UnmappedMemory => return FsError.InvalidArgument,
            else => return FsError.IoError,
        };
    }

    /// 建议内存使用模式
    pub fn advise(self: *Self, advice: MemoryAdvice) !void {
        const advice_flag = advice.toFlag();
        
        // 在支持madvise的平台上调用
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            const result = std.c.madvise(@as(*anyopaque, @ptrCast(self.ptr)), self.len, advice_flag);
            if (result != 0) {
                return FsError.IoError;
            }
        }
    }

    /// 锁定内存页面
    pub fn lock(self: *Self) !void {
        std.posix.mlock(@as([*]align(std.mem.page_size) u8, @alignCast(self.ptr))[0..self.len]) catch |err| switch (err) {
            error.MemoryLockingNotSupported => return FsError.NotSupported,
            error.PermissionDenied => return FsError.PermissionDenied,
            error.SystemResources => return FsError.IoError,
            else => return FsError.IoError,
        };
    }

    /// 解锁内存页面
    pub fn unlock(self: *Self) !void {
        std.posix.munlock(@as([*]align(std.mem.page_size) u8, @alignCast(self.ptr))[0..self.len]) catch |err| switch (err) {
            else => return FsError.IoError,
        };
    }

    /// 改变内存保护模式
    pub fn protect(self: *Self, new_protection: Protection) !void {
        const prot_flags = new_protection.toFlags();
        
        std.posix.mprotect(@as([*]align(std.mem.page_size) u8, @alignCast(self.ptr))[0..self.len], prot_flags) catch |err| switch (err) {
            error.AccessDenied => return FsError.PermissionDenied,
            else => return FsError.IoError,
        };
        
        self.protection = new_protection;
    }

    /// 获取页面大小
    pub fn getPageSize() usize {
        return std.mem.page_size;
    }

    /// 对齐到页面边界
    pub fn alignToPage(size: usize) usize {
        const page_size = getPageSize();
        return (size + page_size - 1) & ~(page_size - 1);
    }
};

/// 内存使用建议
pub const MemoryAdvice = enum {
    normal,
    random,
    sequential,
    will_need,
    dont_need,
    dont_fork,
    do_fork,

    /// 转换为系统标志
    pub fn toFlag(self: MemoryAdvice) i32 {
        return switch (self) {
            .normal => if (builtin.os.tag == .linux) std.c.MADV.NORMAL else 0,
            .random => if (builtin.os.tag == .linux) std.c.MADV.RANDOM else 1,
            .sequential => if (builtin.os.tag == .linux) std.c.MADV.SEQUENTIAL else 2,
            .will_need => if (builtin.os.tag == .linux) std.c.MADV.WILLNEED else 3,
            .dont_need => if (builtin.os.tag == .linux) std.c.MADV.DONTNEED else 4,
            .dont_fork => if (builtin.os.tag == .linux) std.c.MADV.DONTFORK else 10,
            .do_fork => if (builtin.os.tag == .linux) std.c.MADV.DOFORK else 11,
        };
    }
};

// 便捷函数

/// 映射整个文件到内存
pub fn mapFile(fd: std.posix.fd_t, protection: Protection, config: MmapConfig) !MmapFile {
    // 获取文件大小
    const stat = try std.posix.fstat(fd);
    const file_size = @as(usize, @intCast(stat.size));
    
    const flags = if (protection.write) MapFlags.SHARED else MapFlags.PRIVATE;
    return try MmapFile.fromFile(fd, 0, file_size, protection, flags, config);
}

/// 创建匿名内存映射
pub fn mapAnonymous(size: usize, protection: Protection, config: MmapConfig) !MmapFile {
    const aligned_size = MmapFile.alignToPage(size);
    return try MmapFile.anonymous(aligned_size, protection, config);
}

// 测试
test "内存映射保护模式" {
    const testing = std.testing;

    const read_only = Protection.READ_ONLY;
    try testing.expect(read_only.read);
    try testing.expect(!read_only.write);
    try testing.expect(!read_only.execute);

    const flags = read_only.toFlags();
    try testing.expect((flags & std.posix.PROT.READ) != 0);
    try testing.expect((flags & std.posix.PROT.WRITE) == 0);
}

test "内存映射标志" {
    const testing = std.testing;

    const shared = MapFlags.SHARED;
    try testing.expect(shared.shared);
    try testing.expect(!shared.private);

    const flags = shared.toFlags();
    try testing.expect((flags & std.posix.MAP.SHARED) != 0);
    try testing.expect((flags & std.posix.MAP.PRIVATE) == 0);
}

test "页面对齐" {
    const testing = std.testing;

    const page_size = MmapFile.getPageSize();
    try testing.expect(page_size > 0);
    try testing.expect((page_size & (page_size - 1)) == 0); // 是2的幂

    const aligned = MmapFile.alignToPage(1000);
    try testing.expect(aligned >= 1000);
    try testing.expect(aligned % page_size == 0);
}

test "匿名内存映射" {
    const testing = std.testing;

    const config = MmapConfig{};
    var mmap = mapAnonymous(4096, Protection.READ_WRITE, config) catch |err| {
        std.debug.print("Failed to create anonymous mapping: {}\n", .{err});
        return;
    };
    defer mmap.unmap() catch {};

    // 测试写入和读取
    const slice = mmap.asSlice();
    slice[0] = 42;
    slice[100] = 84;

    try testing.expectEqual(@as(u8, 42), slice[0]);
    try testing.expectEqual(@as(u8, 84), slice[100]);
}
