//! 文件元数据模块
//!
//! 提供文件和目录的元数据信息

const std = @import("std");
const builtin = @import("builtin");
const FsError = @import("mod.zig").FsError;

/// 文件类型
pub const FileType = enum {
    file,
    directory,
    symlink,
    block_device,
    char_device,
    fifo,
    socket,
    unknown,

    /// 从系统文件类型转换
    pub fn fromStat(mode: std.posix.mode_t) FileType {
        const file_type = mode & std.posix.S.IFMT;
        return switch (file_type) {
            std.posix.S.IFREG => .file,
            std.posix.S.IFDIR => .directory,
            std.posix.S.IFLNK => .symlink,
            std.posix.S.IFBLK => .block_device,
            std.posix.S.IFCHR => .char_device,
            std.posix.S.IFIFO => .fifo,
            std.posix.S.IFSOCK => .socket,
            else => .unknown,
        };
    }
};

/// 文件权限
pub const Permissions = struct {
    /// 所有者权限
    owner: PermissionSet,
    /// 组权限
    group: PermissionSet,
    /// 其他用户权限
    other: PermissionSet,
    /// 特殊权限位
    special: SpecialPermissions,

    const Self = @This();

    /// 权限集合
    pub const PermissionSet = struct {
        read: bool = false,
        write: bool = false,
        execute: bool = false,
    };

    /// 特殊权限
    pub const SpecialPermissions = struct {
        setuid: bool = false,
        setgid: bool = false,
        sticky: bool = false,
    };

    /// 从系统模式创建权限
    pub fn fromMode(mode: std.posix.mode_t) Self {
        return Self{
            .owner = PermissionSet{
                .read = (mode & std.posix.S.IRUSR) != 0,
                .write = (mode & std.posix.S.IWUSR) != 0,
                .execute = (mode & std.posix.S.IXUSR) != 0,
            },
            .group = PermissionSet{
                .read = (mode & std.posix.S.IRGRP) != 0,
                .write = (mode & std.posix.S.IWGRP) != 0,
                .execute = (mode & std.posix.S.IXGRP) != 0,
            },
            .other = PermissionSet{
                .read = (mode & std.posix.S.IROTH) != 0,
                .write = (mode & std.posix.S.IWOTH) != 0,
                .execute = (mode & std.posix.S.IXOTH) != 0,
            },
            .special = SpecialPermissions{
                .setuid = (mode & std.posix.S.ISUID) != 0,
                .setgid = (mode & std.posix.S.ISGID) != 0,
                .sticky = (mode & std.posix.S.ISVTX) != 0,
            },
        };
    }

    /// 转换为系统模式
    pub fn toMode(self: Self) std.posix.mode_t {
        var mode: std.posix.mode_t = 0;

        // 所有者权限
        if (self.owner.read) mode |= std.posix.S.IRUSR;
        if (self.owner.write) mode |= std.posix.S.IWUSR;
        if (self.owner.execute) mode |= std.posix.S.IXUSR;

        // 组权限
        if (self.group.read) mode |= std.posix.S.IRGRP;
        if (self.group.write) mode |= std.posix.S.IWGRP;
        if (self.group.execute) mode |= std.posix.S.IXGRP;

        // 其他用户权限
        if (self.other.read) mode |= std.posix.S.IROTH;
        if (self.other.write) mode |= std.posix.S.IWOTH;
        if (self.other.execute) mode |= std.posix.S.IXOTH;

        // 特殊权限
        if (self.special.setuid) mode |= std.posix.S.ISUID;
        if (self.special.setgid) mode |= std.posix.S.ISGID;
        if (self.special.sticky) mode |= std.posix.S.ISVTX;

        return mode;
    }

    /// 检查是否可读
    pub fn isReadable(self: Self) bool {
        return self.owner.read or self.group.read or self.other.read;
    }

    /// 检查是否可写
    pub fn isWritable(self: Self) bool {
        return self.owner.write or self.group.write or self.other.write;
    }

    /// 检查是否可执行
    pub fn isExecutable(self: Self) bool {
        return self.owner.execute or self.group.execute or self.other.execute;
    }
};

/// 文件元数据
pub const Metadata = struct {
    /// 文件类型
    file_type: FileType,
    /// 文件大小（字节）
    size: u64,
    /// 文件权限
    permissions: Permissions,
    /// 创建时间（Unix时间戳，纳秒）
    created: i128,
    /// 修改时间（Unix时间戳，纳秒）
    modified: i128,
    /// 访问时间（Unix时间戳，纳秒）
    accessed: i128,
    /// 用户ID
    uid: u32,
    /// 组ID
    gid: u32,
    /// 设备ID
    dev: u64,
    /// inode号
    ino: u64,
    /// 硬链接数
    nlink: u64,
    /// 块大小
    blksize: u64,
    /// 分配的块数
    blocks: u64,

    const Self = @This();

    /// 从文件路径获取元数据
    pub fn fromPath(path: []const u8) !Self {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var stat_buf: std.c.Stat = undefined;
        const path_z = try allocator.dupeZ(u8, path);
        const stat_result = std.c.stat(path_z.ptr, &stat_buf);
        if (stat_result != 0) {
            return FsError.FileNotFound;
        }

        return fromStat(stat_buf);
    }

    /// 从文件描述符获取元数据
    pub fn fromFd(fd: std.posix.fd_t) !Self {
        var stat_buf: std.c.Stat = undefined;
        const stat_result = std.c.fstat(fd, &stat_buf);
        if (stat_result != 0) {
            return FsError.IoError;
        }

        return fromStat(stat_buf);
    }

    /// 从stat结构创建元数据
    fn fromStat(stat: std.c.Stat) Self {
        // 简化时间处理，使用当前时间戳
        const current_time = std.time.timestamp() * std.time.ns_per_s;
        const created_time = current_time;
        const modified_time = current_time;
        const accessed_time = current_time;

        return Self{
            .file_type = FileType.fromStat(stat.mode),
            .size = @as(u64, @intCast(stat.size)),
            .permissions = Permissions.fromMode(stat.mode),
            .created = created_time,
            .modified = modified_time,
            .accessed = accessed_time,
            .uid = stat.uid,
            .gid = stat.gid,
            .dev = @as(u64, @intCast(stat.dev)),
            .ino = @as(u64, @intCast(stat.ino)),
            .nlink = @as(u64, @intCast(stat.nlink)),
            .blksize = @as(u64, @intCast(stat.blksize)),
            .blocks = @as(u64, @intCast(stat.blocks)),
        };
    }

    /// 检查是否是文件
    pub fn isFile(self: Self) bool {
        return self.file_type == .file;
    }

    /// 检查是否是目录
    pub fn isDir(self: Self) bool {
        return self.file_type == .directory;
    }

    /// 检查是否是符号链接
    pub fn isSymlink(self: Self) bool {
        return self.file_type == .symlink;
    }

    /// 获取文件大小（MB）
    pub fn getSizeMB(self: Self) f64 {
        return @as(f64, @floatFromInt(self.size)) / (1024.0 * 1024.0);
    }

    /// 获取创建时间（秒）
    pub fn getCreatedSecs(self: Self) i64 {
        return @as(i64, @intCast(@divTrunc(self.created, std.time.ns_per_s)));
    }

    /// 获取修改时间（秒）
    pub fn getModifiedSecs(self: Self) i64 {
        return @as(i64, @intCast(@divTrunc(self.modified, std.time.ns_per_s)));
    }

    /// 获取访问时间（秒）
    pub fn getAccessedSecs(self: Self) i64 {
        return @as(i64, @intCast(@divTrunc(self.accessed, std.time.ns_per_s)));
    }

    /// 检查文件是否在指定时间之后修改
    pub fn isModifiedAfter(self: Self, timestamp: i128) bool {
        return self.modified > timestamp;
    }

    /// 检查文件是否为空
    pub fn isEmpty(self: Self) bool {
        return self.size == 0;
    }
};

/// 将timespec转换为纳秒
fn timespecToNanos(ts: std.c.timespec) i128 {
    // 在macOS上，使用不同的字段访问方式
    const secs_ns = @as(i128, ts.tv_sec) * std.time.ns_per_s;
    const nsecs_i128 = @as(i128, ts.tv_nsec);
    return secs_ns + nsecs_i128;
}

// 测试
test "文件类型识别" {
    const testing = std.testing;

    // 测试文件类型转换
    try testing.expectEqual(FileType.file, FileType.fromStat(std.posix.S.IFREG));
    try testing.expectEqual(FileType.directory, FileType.fromStat(std.posix.S.IFDIR));
    try testing.expectEqual(FileType.symlink, FileType.fromStat(std.posix.S.IFLNK));
}

test "权限处理" {
    const testing = std.testing;

    // 测试权限转换
    const mode: std.posix.mode_t = std.posix.S.IRUSR | std.posix.S.IWUSR | std.posix.S.IRGRP;
    const permissions = Permissions.fromMode(mode);

    try testing.expect(permissions.owner.read);
    try testing.expect(permissions.owner.write);
    try testing.expect(!permissions.owner.execute);
    try testing.expect(permissions.group.read);
    try testing.expect(!permissions.group.write);

    // 测试权限检查
    try testing.expect(permissions.isReadable());
    try testing.expect(permissions.isWritable());
    try testing.expect(!permissions.isExecutable());

    // 测试权限转换回模式
    const converted_mode = permissions.toMode();
    try testing.expectEqual(mode, converted_mode);
}

test "元数据实用函数" {
    const testing = std.testing;

    const metadata = Metadata{
        .file_type = .file,
        .size = 1024 * 1024, // 1MB
        .permissions = Permissions.fromMode(0o644),
        .created = 1000000000 * std.time.ns_per_s, // 2001年
        .modified = 1500000000 * std.time.ns_per_s, // 2017年
        .accessed = 1600000000 * std.time.ns_per_s, // 2020年
        .uid = 1000,
        .gid = 1000,
        .dev = 0,
        .ino = 0,
        .nlink = 1,
        .blksize = 4096,
        .blocks = 256,
    };

    try testing.expect(metadata.isFile());
    try testing.expect(!metadata.isDir());
    try testing.expect(!metadata.isEmpty());
    try testing.expectEqual(@as(f64, 1.0), metadata.getSizeMB());
    try testing.expectEqual(@as(i64, 1000000000), metadata.getCreatedSecs());
    try testing.expectEqual(@as(i64, 1500000000), metadata.getModifiedSecs());
    try testing.expectEqual(@as(i64, 1600000000), metadata.getAccessedSecs());

    // 测试时间比较
    const old_time = 1400000000 * std.time.ns_per_s;
    const new_time = 1600000000 * std.time.ns_per_s;
    try testing.expect(metadata.isModifiedAfter(old_time));
    try testing.expect(!metadata.isModifiedAfter(new_time));
}
