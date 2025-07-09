//! 验证异步文件I/O修复的测试
//! 这是libx2.md中项目1的异步文件I/O重写验证

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");
const libxev = @import("libxev");

// 导入异步文件模块
const AsyncFile = zokio.AsyncFile;

test "异步文件I/O真实性验证" {
    std.debug.print("\n=== 测试异步文件I/O真实性验证 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建libxev事件循环
    var loop = try libxev.Loop.init(.{});
    defer loop.deinit();

    // 创建临时测试文件
    const test_content = "Hello, Zokio Async File I/O!";
    const temp_path = "test_async_file.txt";

    // 写入测试数据
    {
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        try file.writeAll(test_content);
    }

    defer std.fs.cwd().deleteFile(temp_path) catch {};

    std.debug.print("1. 测试异步文件读取\n", .{});

    // 打开异步文件
    var async_file = try AsyncFile.open(allocator, &loop, temp_path, .{});
    defer async_file.close();

    // 准备读取缓冲区
    var buffer: [100]u8 = undefined;

    // 创建异步读取Future
    const read_future = async_file.read(&buffer, 0);

    // 测试读取性能
    const start_time = std.time.nanoTimestamp();
    const bytes_read = zokio.await_fn(read_future);
    const end_time = std.time.nanoTimestamp();

    const duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;

    std.debug.print("   读取字节数: {} (期望: {})\n", .{ bytes_read, test_content.len });
    std.debug.print("   读取内容: {s}\n", .{buffer[0..bytes_read]});
    std.debug.print("   执行时间: {d:.2} μs\n", .{duration_us});

    try testing.expect(bytes_read == test_content.len);
    try testing.expect(std.mem.eql(u8, buffer[0..bytes_read], test_content));

    std.debug.print("   ✅ 异步文件读取测试通过\n", .{});
}

test "异步文件写入验证" {
    std.debug.print("\n2. 测试异步文件写入\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建libxev事件循环
    var loop = try libxev.Loop.init(.{});
    defer loop.deinit();

    const temp_path = "test_async_write.txt";
    defer std.fs.cwd().deleteFile(temp_path) catch {};

    // 创建空文件
    {
        const file = try std.fs.cwd().createFile(temp_path, .{});
        file.close();
    }

    // 打开异步文件
    var async_file = try AsyncFile.open(allocator, &loop, temp_path, .{ .mode = .read_write });
    defer async_file.close();

    // 准备写入数据
    const write_data = "Zokio Async Write Test!";

    // 创建异步写入Future
    const write_future = async_file.write(write_data, 0);

    // 测试写入性能
    const start_time = std.time.nanoTimestamp();
    const bytes_written = zokio.await_fn(write_future);
    const end_time = std.time.nanoTimestamp();

    const duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;

    std.debug.print("   写入字节数: {} (期望: {})\n", .{ bytes_written, write_data.len });
    std.debug.print("   执行时间: {d:.2} μs\n", .{duration_us});

    try testing.expect(bytes_written == write_data.len);

    // 验证写入内容
    var buffer: [100]u8 = undefined;
    const read_future = async_file.read(&buffer, 0);
    const bytes_read = zokio.await_fn(read_future);

    try testing.expect(bytes_read == write_data.len);
    try testing.expect(std.mem.eql(u8, buffer[0..bytes_read], write_data));

    std.debug.print("   ✅ 异步文件写入测试通过\n", .{});
}

test "异步文件I/O性能基准" {
    std.debug.print("\n3. 测试异步文件I/O性能基准\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建libxev事件循环
    var loop = try libxev.Loop.init(.{});
    defer loop.deinit();

    const temp_path = "test_async_perf.txt";
    defer std.fs.cwd().deleteFile(temp_path) catch {};

    // 创建测试文件
    {
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        try file.writeAll("Performance test data for Zokio async file I/O");
    }

    // 打开异步文件
    var async_file = try AsyncFile.open(allocator, &loop, temp_path, .{});
    defer async_file.close();

    // 性能测试：多次读取操作
    const iterations = 100;
    var buffer: [100]u8 = undefined;

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const read_future = async_file.read(&buffer, 0);
        const bytes_read = zokio.await_fn(read_future);
        try testing.expect(bytes_read > 0);
    }

    const end_time = std.time.nanoTimestamp();
    const total_duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;
    const avg_duration_us = total_duration_us / @as(f64, @floatFromInt(iterations));
    const ops_per_sec = 1_000_000.0 / avg_duration_us;

    std.debug.print("   迭代次数: {}\n", .{iterations});
    std.debug.print("   总执行时间: {d:.2} μs\n", .{total_duration_us});
    std.debug.print("   平均执行时间: {d:.3} μs\n", .{avg_duration_us});
    std.debug.print("   吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    // 验证性能目标：应该达到较高的吞吐量
    try testing.expect(ops_per_sec > 10_000); // 至少1万ops/sec

    std.debug.print("   ✅ 性能基准测试通过\n", .{});
}

test "异步文件I/O内存安全" {
    std.debug.print("\n4. 测试异步文件I/O内存安全\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建libxev事件循环
    var loop = try libxev.Loop.init(.{});
    defer loop.deinit();

    const temp_path = "test_async_memory.txt";
    defer std.fs.cwd().deleteFile(temp_path) catch {};

    // 创建测试文件
    {
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        try file.writeAll("Memory safety test");
    }

    // 多次打开和关闭文件
    const iterations = 50;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        var async_file = try AsyncFile.open(allocator, &loop, temp_path, .{});

        var buffer: [50]u8 = undefined;
        const read_future = async_file.read(&buffer, 0);
        const bytes_read = zokio.await_fn(read_future);
        try testing.expect(bytes_read > 0);

        async_file.close();
    }

    // 检查内存泄漏
    const leaked = gpa.detectLeaks();

    std.debug.print("   文件操作次数: {}\n", .{iterations});
    std.debug.print("   内存泄漏检测: {}\n", .{leaked});

    try testing.expect(!leaked);

    std.debug.print("   ✅ 内存安全测试通过\n", .{});
}

test "异步文件状态和同步操作" {
    std.debug.print("\n5. 测试异步文件状态和同步操作\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建libxev事件循环
    var loop = try libxev.Loop.init(.{});
    defer loop.deinit();

    const temp_path = "test_async_stat.txt";
    defer std.fs.cwd().deleteFile(temp_path) catch {};

    // 创建测试文件
    const test_data = "File stat and sync test data";
    {
        const file = try std.fs.cwd().createFile(temp_path, .{});
        defer file.close();
        try file.writeAll(test_data);
    }

    // 打开异步文件
    var async_file = try AsyncFile.open(allocator, &loop, temp_path, .{});
    defer async_file.close();

    // 测试异步文件状态获取
    const stat_future = async_file.stat();
    const file_stat = zokio.await_fn(stat_future);

    std.debug.print("   文件大小: {} bytes\n", .{file_stat.size});
    std.debug.print("   文件类型: {}\n", .{file_stat.kind});

    try testing.expect(file_stat.size == test_data.len);
    try testing.expect(file_stat.kind == .file);

    // 测试异步文件同步
    const sync_future = async_file.sync();
    zokio.await_fn(sync_future);

    std.debug.print("   ✅ 文件状态和同步测试通过\n", .{});
}
