//! libxev集成演示
//! 展示如何使用Zokio的libxev I/O驱动进行异步文件操作

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio libxev集成演示 ===\n", .{});

    // 配置使用libxev后端
    const config = zokio.io.IoConfig{
        .prefer_libxev = true,
        .events_capacity = 128,
        .batch_size = 16,
    };

    // 创建I/O驱动
    const DriverType = zokio.io.IoDriver(config);
    var driver = try DriverType.init(allocator);
    defer driver.deinit();

    std.debug.print("I/O驱动初始化成功\n", .{});
    std.debug.print("后端类型: {}\n", .{DriverType.BACKEND_TYPE});
    std.debug.print("支持批量操作: {}\n", .{DriverType.SUPPORTS_BATCH});

    // 显示性能特征
    const perf = DriverType.PERFORMANCE_CHARACTERISTICS;
    std.debug.print("性能特征:\n", .{});
    std.debug.print("  延迟等级: {}\n", .{perf.latency_class});
    std.debug.print("  吞吐量等级: {}\n", .{perf.throughput_class});
    std.debug.print("  CPU效率: {}\n", .{perf.cpu_efficiency});
    std.debug.print("  内存效率: {}\n", .{perf.memory_efficiency});
    std.debug.print("  批量效率: {}\n", .{perf.batch_efficiency});

    // 显示支持的操作
    const ops = DriverType.SUPPORTED_OPERATIONS;
    std.debug.print("支持的操作 ({} 种):\n", .{ops.len});
    for (ops) |op| {
        std.debug.print("  - {}\n", .{op});
    }

    // 创建测试文件
    const test_file_path = "libxev_demo_test.txt";
    const test_data = "Hello from Zokio libxev integration!";

    // 写入测试数据
    {
        const file = try std.fs.cwd().createFile(test_file_path, .{});
        defer file.close();
        try file.writeAll(test_data);
    }
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    std.debug.print("\n=== 异步文件读取演示 ===\n", .{});

    // 打开文件进行异步读取
    const file = try std.fs.cwd().openFile(test_file_path, .{});
    defer file.close();

    // 提交异步读取操作
    var buffer: [1024]u8 = undefined;
    const handle = try driver.submitRead(file.handle, &buffer, 0);

    std.debug.print("异步读取操作已提交，句柄ID: {}\n", .{handle.id});

    // 轮询完成事件
    std.debug.print("轮询I/O完成事件...\n", .{});
    const completed = try driver.poll(1000); // 1秒超时
    std.debug.print("完成的操作数量: {}\n", .{completed});

    // 获取完成结果
    var results: [10]zokio.io.IoResult = undefined;
    const result_count = driver.getCompletions(&results);
    std.debug.print("获取到 {} 个完成结果\n", .{result_count});

    for (0..result_count) |i| {
        const result = results[i];
        std.debug.print("结果 {}: 句柄ID={}, 返回值={}, 完成={}\n", .{ i, result.handle.id, result.result, result.completed });
    }

    std.debug.print("\n=== 批量操作演示 ===\n", .{});

    // 创建批量操作
    var buffers: [3][256]u8 = undefined;
    const operations = [_]zokio.io.IoOperation{
        .{
            .op_type = .read,
            .fd = file.handle,
            .buffer = &buffers[0],
            .offset = 0,
        },
        .{
            .op_type = .read,
            .fd = file.handle,
            .buffer = &buffers[1],
            .offset = 0,
        },
        .{
            .op_type = .read,
            .fd = file.handle,
            .buffer = &buffers[2],
            .offset = 0,
        },
    };

    // 提交批量操作
    const handles = try driver.submitBatch(&operations);
    defer allocator.free(handles);

    std.debug.print("批量操作已提交，句柄数量: {}\n", .{handles.len});
    for (handles, 0..) |batch_handle, i| {
        std.debug.print("  句柄 {}: ID={}\n", .{ i, batch_handle.id });
    }

    // 再次轮询
    const batch_completed = try driver.poll(1000);
    std.debug.print("批量操作完成数量: {}\n", .{batch_completed});

    std.debug.print("\n=== 演示完成 ===\n", .{});
    std.debug.print("libxev集成工作正常！\n", .{});
}
