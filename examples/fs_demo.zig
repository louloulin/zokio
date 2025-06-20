//! 文件系统功能演示
//!
//! 展示Zokio的文件系统操作功能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 文件系统功能演示 ===\n", .{});

    // 演示1：基础文件操作
    try demonstrateFileOperations(allocator);

    // 演示2：目录操作
    try demonstrateDirectoryOperations(allocator);

    // 演示3：文件元数据（暂时跳过，需要修复平台兼容性）
    std.debug.print("\n3. 文件元数据演示（跳过 - 平台兼容性问题）\n", .{});

    // 演示4：内存映射文件（暂时跳过，需要修复平台兼容性）
    std.debug.print("\n4. 内存映射文件演示（跳过 - 平台兼容性问题）\n", .{});

    // 演示5：文件系统管理器
    try demonstrateFsManager(allocator);

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

/// 演示基础文件操作
fn demonstrateFileOperations(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 基础文件操作演示\n", .{});

    const test_file = "/tmp/zokio_demo_file.txt";
    const test_data = "Hello, Zokio File System!\nThis is a test file.\n";

    // 清理可能存在的文件
    std.posix.unlink(test_file) catch {};

    // 写入文件
    try zokio.fs.writeFile(allocator, test_file, test_data);
    std.debug.print("   文件写入成功: {s}\n", .{test_file});

    // 检查文件是否存在
    const file_exists = zokio.fs.exists(test_file);
    std.debug.print("   文件存在: {}\n", .{file_exists});

    // 读取文件
    const read_data = try zokio.fs.readFile(allocator, test_file);
    defer allocator.free(read_data);
    std.debug.print("   读取数据长度: {} 字节\n", .{read_data.len});
    std.debug.print("   数据匹配: {}\n", .{std.mem.eql(u8, test_data, read_data)});

    // 复制文件
    const copy_file = "/tmp/zokio_demo_copy.txt";
    try zokio.fs.copyFile(allocator, test_file, copy_file);
    std.debug.print("   文件复制成功: {s}\n", .{copy_file});

    // 使用File API进行更精细的操作
    {
        var file = try zokio.fs.File.open(allocator, test_file, zokio.fs.OpenMode.READ_WRITE);
        defer file.close();

        // 定位到文件末尾
        const metadata = try file.getMetadata();
        try file.seek(metadata.size);

        // 追加数据
        const append_data = "Appended line.\n";
        _ = try file.writeAll(append_data);
        std.debug.print("   追加数据成功\n", .{});

        // 同步到磁盘
        try file.sync();
        std.debug.print("   文件同步完成\n", .{});
    }

    // 清理测试文件
    std.posix.unlink(test_file) catch {};
    std.posix.unlink(copy_file) catch {};
}

/// 演示目录操作
fn demonstrateDirectoryOperations(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. 目录操作演示\n", .{});

    const test_dir = "/tmp/zokio_demo_dir";
    const sub_dir = "/tmp/zokio_demo_dir/subdir";
    const deep_dir = "/tmp/zokio_demo_dir/subdir/deep";

    // 清理可能存在的目录
    zokio.fs.Dir.removeAll(allocator, test_dir) catch {};

    // 创建目录
    try zokio.fs.Dir.create(test_dir, 0o755);
    std.debug.print("   目录创建成功: {s}\n", .{test_dir});

    // 检查目录是否存在
    const dir_exists = zokio.fs.dir.exists(test_dir);
    std.debug.print("   目录存在: {}\n", .{dir_exists});

    // 递归创建目录
    try zokio.fs.Dir.createAll(allocator, deep_dir, 0o755);
    std.debug.print("   递归目录创建成功: {s}\n", .{deep_dir});

    // 在目录中创建一些文件
    const file1 = "/tmp/zokio_demo_dir/file1.txt";
    const file2 = "/tmp/zokio_demo_dir/subdir/file2.txt";
    try zokio.fs.writeFile(allocator, file1, "File 1 content");
    try zokio.fs.writeFile(allocator, file2, "File 2 content");
    std.debug.print("   测试文件创建完成\n", .{});

    // 读取目录内容
    {
        var dir_handle = try zokio.fs.Dir.open(allocator, test_dir);
        defer dir_handle.close();

        const entries = try dir_handle.readEntries();
        defer {
            for (entries) |entry| {
                allocator.free(entry.name);
                allocator.free(entry.path);
            }
            allocator.free(entries);
        }

        std.debug.print("   目录条目数: {}\n", .{entries.len});
        for (entries, 0..) |entry, i| {
            const type_str = switch (entry.file_type) {
                .file => "文件",
                .directory => "目录",
                .symlink => "符号链接",
                else => "其他",
            };
            std.debug.print("   [{}] {s}: {s}\n", .{ i, type_str, entry.name });
        }
    }

    // 检查目录是否为空
    const sub_is_empty = try zokio.fs.dir.isEmpty(allocator, sub_dir);
    std.debug.print("   子目录为空: {}\n", .{sub_is_empty});

    // 递归删除目录
    try zokio.fs.Dir.removeAll(allocator, test_dir);
    std.debug.print("   递归删除完成\n", .{});
}

/// 演示文件元数据
fn demonstrateMetadata(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. 文件元数据演示\n", .{});

    const test_file = "/tmp/zokio_metadata_test.txt";
    const test_data = "Metadata test file content.\n";

    // 创建测试文件
    try zokio.fs.writeFile(allocator, test_file, test_data);
    defer std.posix.unlink(test_file) catch {};

    // 获取文件元数据
    const metadata = try zokio.fs.Metadata.fromPath(test_file);

    std.debug.print("   文件类型: {s}\n", .{@tagName(metadata.file_type)});
    std.debug.print("   文件大小: {} 字节 ({d:.2} KB)\n", .{ metadata.size, @as(f64, @floatFromInt(metadata.size)) / 1024.0 });
    std.debug.print("   是否为文件: {}\n", .{metadata.isFile()});
    std.debug.print("   是否为目录: {}\n", .{metadata.isDir()});
    std.debug.print("   是否为空: {}\n", .{metadata.isEmpty()});

    // 权限信息
    const perms = metadata.permissions;
    std.debug.print("   权限信息:\n", .{});
    std.debug.print("     所有者: r={} w={} x={}\n", .{ perms.owner.read, perms.owner.write, perms.owner.execute });
    std.debug.print("     组: r={} w={} x={}\n", .{ perms.group.read, perms.group.write, perms.group.execute });
    std.debug.print("     其他: r={} w={} x={}\n", .{ perms.other.read, perms.other.write, perms.other.execute });
    std.debug.print("     可读: {}\n", .{perms.isReadable()});
    std.debug.print("     可写: {}\n", .{perms.isWritable()});
    std.debug.print("     可执行: {}\n", .{perms.isExecutable()});

    // 时间信息
    std.debug.print("   时间信息:\n", .{});
    std.debug.print("     创建时间: {}\n", .{metadata.getCreatedSecs()});
    std.debug.print("     修改时间: {}\n", .{metadata.getModifiedSecs()});
    std.debug.print("     访问时间: {}\n", .{metadata.getAccessedSecs()});

    // 系统信息
    std.debug.print("   系统信息:\n", .{});
    std.debug.print("     用户ID: {}\n", .{metadata.uid});
    std.debug.print("     组ID: {}\n", .{metadata.gid});
    std.debug.print("     inode: {}\n", .{metadata.ino});
    std.debug.print("     硬链接数: {}\n", .{metadata.nlink});
    std.debug.print("     块大小: {}\n", .{metadata.blksize});
    std.debug.print("     分配块数: {}\n", .{metadata.blocks});
}

/// 演示内存映射文件
fn demonstrateMemoryMapping(allocator: std.mem.Allocator) !void {
    std.debug.print("\n4. 内存映射文件演示\n", .{});

    const test_file = "/tmp/zokio_mmap_test.txt";
    const test_data = "Memory mapped file test content. This is a longer text to test memory mapping functionality.\n";

    // 创建测试文件
    try zokio.fs.writeFile(allocator, test_file, test_data);
    defer std.posix.unlink(test_file) catch {};

    // 打开文件进行内存映射
    var file = try zokio.fs.File.open(allocator, test_file, zokio.fs.OpenMode.READ_WRITE);
    defer file.close();

    // 创建内存映射
    const config = zokio.fs.MmapConfig{};
    var mmap = zokio.fs.mmap.mapFile(file.fd, zokio.fs.mmap.Protection.READ_WRITE, config) catch |err| {
        std.debug.print("   内存映射失败: {}\n", .{err});
        return;
    };
    defer mmap.unmap() catch {};

    std.debug.print("   内存映射创建成功\n", .{});
    std.debug.print("   映射大小: {} 字节\n", .{mmap.len});
    std.debug.print("   页面大小: {} 字节\n", .{zokio.fs.MmapFile.getPageSize()});

    // 读取映射的内容
    const mapped_content = mmap.asConstSlice();
    std.debug.print("   映射内容长度: {}\n", .{mapped_content.len});
    std.debug.print("   内容匹配: {}\n", .{std.mem.eql(u8, test_data, mapped_content)});

    // 修改映射的内容
    const mapped_slice = mmap.asSlice();
    if (mapped_slice.len > 10) {
        mapped_slice[0] = 'M';
        mapped_slice[1] = 'O';
        mapped_slice[2] = 'D';
        std.debug.print("   内容修改完成\n", .{});
    }

    // 同步到磁盘
    try mmap.sync(false);
    std.debug.print("   同步到磁盘完成\n", .{});

    // 演示匿名内存映射
    var anon_mmap = zokio.fs.mmap.mapAnonymous(4096, zokio.fs.mmap.Protection.READ_WRITE, config) catch |err| {
        std.debug.print("   匿名映射失败: {}\n", .{err});
        return;
    };
    defer anon_mmap.unmap() catch {};

    std.debug.print("   匿名映射创建成功，大小: {} 字节\n", .{anon_mmap.len});

    // 在匿名映射中写入数据
    const anon_slice = anon_mmap.asSlice();
    const anon_data = "Anonymous mapping test";
    @memcpy(anon_slice[0..anon_data.len], anon_data);
    std.debug.print("   匿名映射写入完成\n", .{});
}

/// 演示文件系统管理器
fn demonstrateFsManager(allocator: std.mem.Allocator) !void {
    std.debug.print("\n5. 文件系统管理器演示\n", .{});

    const config = zokio.fs.FsConfig{
        .read_buffer_size = 32 * 1024,
        .write_buffer_size = 32 * 1024,
        .enable_direct_io = false,
    };

    var manager = zokio.fs.FsManager.init(allocator, config);
    defer manager.deinit();

    std.debug.print("   文件系统管理器初始化完成\n", .{});
    std.debug.print("   配置信息:\n", .{});
    std.debug.print("     读缓冲区大小: {} KB\n", .{config.read_buffer_size / 1024});
    std.debug.print("     写缓冲区大小: {} KB\n", .{config.write_buffer_size / 1024});
    std.debug.print("     默认文件权限: 0o{o}\n", .{config.default_file_mode});
    std.debug.print("     默认目录权限: 0o{o}\n", .{config.default_dir_mode});

    // 模拟一些文件系统操作统计
    manager.updateStats("read_operations", 100);
    manager.updateStats("write_operations", 50);
    manager.updateStats("bytes_read", 1024 * 1024);
    manager.updateStats("bytes_written", 512 * 1024);
    manager.updateStats("fs_errors", 3);
    manager.updateStats("open_files", 10);

    const stats = manager.getStats();
    std.debug.print("   统计信息:\n", .{});
    std.debug.print("     打开文件数: {}\n", .{stats.open_files});
    std.debug.print("     读取操作数: {}\n", .{stats.read_operations});
    std.debug.print("     写入操作数: {}\n", .{stats.write_operations});
    std.debug.print("     读取字节数: {} ({d:.2} MB)\n", .{ stats.bytes_read, @as(f64, @floatFromInt(stats.bytes_read)) / (1024.0 * 1024.0) });
    std.debug.print("     写入字节数: {} ({d:.2} MB)\n", .{ stats.bytes_written, @as(f64, @floatFromInt(stats.bytes_written)) / (1024.0 * 1024.0) });
    std.debug.print("     文件系统错误数: {}\n", .{stats.fs_errors});

    const io_stats = stats.getIoStats();
    std.debug.print("   I/O统计:\n", .{});
    std.debug.print("     总操作数: {}\n", .{io_stats.total_operations});
    std.debug.print("     总字节数: {} ({d:.2} MB)\n", .{ io_stats.total_bytes, @as(f64, @floatFromInt(io_stats.total_bytes)) / (1024.0 * 1024.0) });

    const error_rate = stats.getErrorRate();
    std.debug.print("     错误率: {d:.2}%\n", .{error_rate * 100});

    // 重置统计
    manager.resetStats();
    const reset_stats = manager.getStats();
    std.debug.print("   重置后统计:\n", .{});
    std.debug.print("     总操作数: {}\n", .{reset_stats.read_operations + reset_stats.write_operations});
    std.debug.print("     总字节数: {}\n", .{reset_stats.bytes_read + reset_stats.bytes_written});
}
