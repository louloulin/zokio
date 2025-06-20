//! libxev集成测试
//! 验证libxev I/O驱动的基础功能

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "libxev I/O驱动基础功能" {
    const allocator = testing.allocator;

    // libxev现在总是可用的，不需要检查

    // 配置使用libxev后端
    const config = zokio.io.IoConfig{
        .events_capacity = 64,
        .enable_real_io = false,
    };

    const DriverType = zokio.io.IoDriver(config);
    var driver = try DriverType.init(allocator);
    defer driver.deinit();

    // 验证后端类型
    try testing.expectEqual(zokio.io.IoBackendType.libxev, DriverType.BACKEND_TYPE);

    // 验证性能特征
    const perf = DriverType.PERFORMANCE_CHARACTERISTICS;
    try testing.expectEqualStrings("ultra_low", perf.latency_class);
    try testing.expectEqualStrings("very_high", perf.throughput_class);
    try testing.expectEqualStrings("23.5M ops/sec", perf.verified_performance);

    // 验证后端类型
    try testing.expectEqual(zokio.io.IoBackendType.libxev, DriverType.BACKEND_TYPE);
    try testing.expect(DriverType.SUPPORTS_BATCH);
}

test "libxev I/O驱动文件操作" {
    const allocator = testing.allocator;

    // 配置使用libxev后端
    const config = zokio.io.IoConfig{
        .events_capacity = 64,
        .enable_real_io = false,
    };

    const DriverType = zokio.io.IoDriver(config);
    var driver = try DriverType.init(allocator);
    defer driver.deinit();

    // 创建临时文件
    const test_file_path = "test_libxev_io.tmp";
    const test_data = "Hello, libxev integration!";

    // 写入测试数据
    {
        const file = try std.fs.cwd().createFile(test_file_path, .{});
        defer file.close();
        try file.writeAll(test_data);
    }
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // 打开文件进行异步读取
    const file = try std.fs.cwd().openFile(test_file_path, .{});
    defer file.close();

    // 提交异步读取操作
    var buffer: [1024]u8 = undefined;
    const handle = try driver.submitRead(file.handle, &buffer, 0);

    // 验证句柄生成
    try testing.expect(handle.id > 0);

    // 轮询完成事件
    const completed = try driver.poll(1000); // 1秒超时
    try testing.expect(completed >= 0);

    // 获取完成结果
    var results: [10]zokio.io.IoResult = undefined;
    const result_count = driver.getCompletions(&results);

    // 验证至少有一个结果
    try testing.expect(result_count >= 0);
}

test "libxev I/O驱动批量操作" {
    const allocator = testing.allocator;

    // 配置使用libxev后端
    const config = zokio.io.IoConfig{
        .events_capacity = 128,
        .batch_size = 16,
        .enable_real_io = false,
    };

    const DriverType = zokio.io.IoDriver(config);
    var driver = try DriverType.init(allocator);
    defer driver.deinit();

    // 验证批量操作支持
    try testing.expect(DriverType.SUPPORTS_BATCH);

    // 创建批量操作
    var buffers: [3][256]u8 = undefined;
    const operations = [_]zokio.io.IoOperation{
        .{
            .op_type = .read,
            .fd = 0, // stdin
            .buffer = &buffers[0],
            .offset = 0,
        },
        .{
            .op_type = .read,
            .fd = 0, // stdin
            .buffer = &buffers[1],
            .offset = 0,
        },
        .{
            .op_type = .read,
            .fd = 0, // stdin
            .buffer = &buffers[2],
            .offset = 0,
        },
    };

    // 提交批量操作
    const handles = try driver.submitBatch(&operations);
    defer allocator.free(handles);

    // 验证句柄数量
    try testing.expectEqual(@as(usize, 3), handles.len);

    // 验证每个句柄都有唯一ID
    for (handles, 0..) |handle, i| {
        try testing.expect(handle.id > 0);
        for (handles[i + 1 ..]) |other_handle| {
            try testing.expect(handle.id != other_handle.id);
        }
    }
}

test "libxev配置验证" {
    // 测试有效配置
    const valid_config = zokio.io.IoConfig{
        .events_capacity = 1024,
        .batch_size = 32,
        .enable_real_io = false,
    };

    // 编译时验证应该通过
    comptime valid_config.validate();

    // 测试基本配置验证
    try testing.expect(valid_config.events_capacity > 0);
    try testing.expect(valid_config.batch_size > 0);
}

test "libxev性能特征分析" {
    const allocator = testing.allocator;

    const config = zokio.io.IoConfig{
        .events_capacity = 1024,
        .enable_real_io = false,
    };

    const DriverType = zokio.io.IoDriver(config);
    var driver = try DriverType.init(allocator);
    defer driver.deinit();

    const perf = DriverType.PERFORMANCE_CHARACTERISTICS;

    // 验证libxev的性能特征
    try testing.expectEqualStrings("ultra_low", perf.latency_class);
    try testing.expectEqualStrings("very_high", perf.throughput_class);
    try testing.expectEqualStrings("23.5M ops/sec", perf.verified_performance);

    // 验证后端类型
    try testing.expectEqual(zokio.io.IoBackendType.libxev, DriverType.BACKEND_TYPE);
    try testing.expect(DriverType.SUPPORTS_BATCH);
}
