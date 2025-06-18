//! 异步文件系统操作演示
//!
//! 展示Zokio的异步文件I/O功能，包括文件读写、目录遍历等。

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio异步文件系统演示 ===\n\n", .{});

    // 创建运行时
    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();

    // 启动运行时
    try runtime.start();

    // 运行异步文件操作
    try asyncFileOperations(allocator);

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

fn asyncFileOperations(allocator: std.mem.Allocator) !void {
    std.debug.print("1. 异步文件写入演示\n", .{});

    // 创建测试文件
    const test_content = "Hello, Zokio异步文件系统!\n这是一个测试文件。\n包含多行内容。\n";
    const test_file_path = "test_async_file.txt";

    // 模拟I/O驱动（实际应用中会使用真实的IoDriver）
    var mock_io_driver: u8 = 0;

    // 异步写入文件
    var write_future = zokio.fs.writeFile(test_file_path, test_content, &mock_io_driver) catch |err| {
        std.debug.print("创建写入Future失败: {}\n", .{err});
        return;
    };
    defer write_future.deinit();

    // 模拟轮询写入操作
    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);

    switch (write_future.poll(&ctx)) {
        .ready => std.debug.print("✓ 文件写入完成\n", .{}),
        .pending => std.debug.print("⏳ 文件写入待定\n", .{}),
    }

    std.debug.print("\n2. 异步文件读取演示\n", .{});

    // 异步读取文件
    var read_future = zokio.fs.readFile(allocator, test_file_path, &mock_io_driver) catch |err| {
        std.debug.print("创建读取Future失败: {}\n", .{err});
        return;
    };
    defer read_future.deinit();

    switch (read_future.poll(&ctx)) {
        .ready => |content| {
            std.debug.print("✓ 文件读取完成，内容长度: {} 字节\n", .{content.len});
            std.debug.print("文件内容:\n{s}\n", .{content});
        },
        .pending => std.debug.print("⏳ 文件读取待定\n", .{}),
    }

    std.debug.print("\n3. 文件元数据演示\n", .{});

    // 打开文件并获取元数据
    var file = zokio.fs.AsyncFile.open(test_file_path, zokio.fs.OpenOptions.readOnly(), &mock_io_driver) catch |err| {
        std.debug.print("打开文件失败: {}\n", .{err});
        return;
    };
    defer file.close();

    const metadata = file.metadata() catch |err| {
        std.debug.print("获取元数据失败: {}\n", .{err});
        return;
    };

    std.debug.print("✓ 文件元数据:\n", .{});
    std.debug.print("  大小: {} 字节\n", .{metadata.size});
    std.debug.print("  是文件: {}\n", .{metadata.is_file});
    std.debug.print("  是目录: {}\n", .{metadata.is_dir});
    std.debug.print("  权限: 0o{o}\n", .{metadata.permissions});
    std.debug.print("  修改时间: {}\n", .{metadata.modified_time});

    std.debug.print("\n4. 目录遍历演示\n", .{});

    // 遍历当前目录
    var dir = zokio.fs.AsyncDir.open(".") catch |err| {
        std.debug.print("打开目录失败: {}\n", .{err});
        return;
    };
    defer dir.close();

    std.debug.print("✓ 当前目录内容:\n", .{});
    var entry_count: u32 = 0;

    while (true) {
        var read_entry_future = dir.readEntry();

        switch (read_entry_future.poll(&ctx)) {
            .ready => |maybe_entry| {
                if (maybe_entry) |entry| {
                    const type_str = switch (entry.file_type) {
                        .file => "文件",
                        .directory => "目录",
                        .symlink => "符号链接",
                        .other => "其他",
                    };
                    std.debug.print("  {s}: {s}\n", .{ type_str, entry.name });
                    entry_count += 1;

                    // 限制输出数量
                    if (entry_count >= 10) {
                        std.debug.print("  ... (仅显示前10个条目)\n", .{});
                        break;
                    }
                } else {
                    break; // 目录遍历完成
                }
            },
            .pending => {
                std.debug.print("⏳ 目录读取待定\n", .{});
                break;
            },
        }
    }

    std.debug.print("总共找到 {} 个条目\n", .{entry_count});

    std.debug.print("\n5. 文件操作选项演示\n", .{});

    // 演示不同的打开选项
    const options_examples = [_]struct {
        name: []const u8,
        options: zokio.fs.OpenOptions,
    }{
        .{ .name = "只读", .options = zokio.fs.OpenOptions.readOnly() },
        .{ .name = "只写", .options = zokio.fs.OpenOptions.writeOnly() },
        .{ .name = "读写", .options = zokio.fs.OpenOptions.readWrite() },
        .{ .name = "创建新文件", .options = zokio.fs.OpenOptions.createNew() },
    };

    for (options_examples) |example| {
        std.debug.print("  {s}选项:\n", .{example.name});
        std.debug.print("    读取: {}\n", .{example.options.read});
        std.debug.print("    写入: {}\n", .{example.options.write});
        std.debug.print("    创建: {}\n", .{example.options.create});
        std.debug.print("    截断: {}\n", .{example.options.truncate});
        std.debug.print("    追加: {}\n", .{example.options.append});
        std.debug.print("    独占: {}\n", .{example.options.exclusive});
    }

    std.debug.print("\n6. 异步文件位置读写演示\n", .{});

    // 创建一个较大的测试文件
    const large_content = "0123456789" ** 10; // 100字节
    const large_file_path = "test_large_file.txt";

    var large_file = zokio.fs.AsyncFile.open(large_file_path, zokio.fs.OpenOptions.readWrite(), &mock_io_driver) catch |err| {
        std.debug.print("创建大文件失败: {}\n", .{err});
        return;
    };
    defer large_file.close();

    // 写入数据
    var write_at_future = large_file.write(large_content);
    switch (write_at_future.poll(&ctx)) {
        .ready => |bytes_written| std.debug.print("✓ 写入 {} 字节到文件\n", .{bytes_written}),
        .pending => std.debug.print("⏳ 写入操作待定\n", .{}),
    }

    // 从特定位置读取
    var read_buffer: [20]u8 = undefined;
    var read_at_future = large_file.readAt(&read_buffer, 50); // 从第50字节开始读取

    switch (read_at_future.poll(&ctx)) {
        .ready => |bytes_read| {
            std.debug.print("✓ 从位置50读取 {} 字节: {s}\n", .{ bytes_read, read_buffer[0..bytes_read] });
        },
        .pending => std.debug.print("⏳ 位置读取操作待定\n", .{}),
    }

    // 写入到特定位置
    const insert_data = "INSERT";
    var write_at_pos_future = large_file.writeAt(insert_data, 25); // 在第25字节位置写入

    switch (write_at_pos_future.poll(&ctx)) {
        .ready => |bytes_written| std.debug.print("✓ 在位置25写入 {} 字节\n", .{bytes_written}),
        .pending => std.debug.print("⏳ 位置写入操作待定\n", .{}),
    }

    std.debug.print("\n7. 文件刷新演示\n", .{});

    // 刷新文件缓冲区
    var flush_future = large_file.flush();
    switch (flush_future.poll(&ctx)) {
        .ready => std.debug.print("✓ 文件缓冲区刷新完成\n", .{}),
        .pending => std.debug.print("⏳ 文件刷新操作待定\n", .{}),
    }

    // 清理测试文件
    std.fs.cwd().deleteFile(test_file_path) catch {};
    std.fs.cwd().deleteFile(large_file_path) catch {};

    std.debug.print("\n✓ 异步文件系统演示完成\n", .{});
}
