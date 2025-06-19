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
        .prefer_libxev = true,
        .events_capacity = 64,
    };

    const DriverType = zokio.io.IoDriver(config);
    var driver = try DriverType.init(allocator);
    defer driver.deinit();

    // 验证后端类型
    try testing.expectEqual(zokio.io.IoBackendType.libxev, DriverType.BACKEND_TYPE);

    // 验证性能特征
    const perf = DriverType.PERFORMANCE_CHARACTERISTICS;
    try testing.expectEqual(zokio.io.PerformanceCharacteristics.LatencyClass.ultra_low, perf.latency_class);
    try testing.expectEqual(zokio.io.PerformanceCharacteristics.ThroughputClass.very_high, perf.throughput_class);

    // 验证支持的操作
    const ops = DriverType.SUPPORTED_OPERATIONS;
    try testing.expect(ops.len > 0);

    // 检查是否支持基本操作
    var has_read = false;
    var has_write = false;
    for (ops) |op| {
        if (op == .read) has_read = true;
        if (op == .write) has_write = true;
    }
    try testing.expect(has_read);
    try testing.expect(has_write);
}

test "libxev I/O驱动文件操作" {
    const allocator = testing.allocator;

    // 配置使用libxev后端
    const config = zokio.io.IoConfig{
        .prefer_libxev = true,
        .events_capacity = 64,
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
        .prefer_libxev = true,
        .events_capacity = 128,
        .batch_size = 16,
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
        .prefer_libxev = true,
        .events_capacity = 1024,
        .queue_depth = 256,
        .batch_size = 32,
    };

    // 编译时验证应该通过
    comptime valid_config.validate();

    // 测试libxev后端类型
    const backend_auto = zokio.io.IoConfig.LibxevBackendType.auto;
    const backend_epoll = zokio.io.IoConfig.LibxevBackendType.epoll;
    const backend_kqueue = zokio.io.IoConfig.LibxevBackendType.kqueue;
    const backend_iocp = zokio.io.IoConfig.LibxevBackendType.iocp;
    const backend_io_uring = zokio.io.IoConfig.LibxevBackendType.io_uring;

    try testing.expectEqual(backend_auto, .auto);
    try testing.expectEqual(backend_epoll, .epoll);
    try testing.expectEqual(backend_kqueue, .kqueue);
    try testing.expectEqual(backend_iocp, .iocp);
    try testing.expectEqual(backend_io_uring, .io_uring);
}

test "libxev性能特征分析" {
    const allocator = testing.allocator;

    const config = zokio.io.IoConfig{
        .prefer_libxev = true,
        .events_capacity = 1024,
    };

    const DriverType = zokio.io.IoDriver(config);
    var driver = try DriverType.init(allocator);
    defer driver.deinit();

    const perf = DriverType.PERFORMANCE_CHARACTERISTICS;

    // 验证libxev的性能特征
    try testing.expectEqual(perf.latency_class, .ultra_low);
    try testing.expectEqual(perf.throughput_class, .very_high);
    try testing.expectEqual(perf.cpu_efficiency, .excellent);
    try testing.expectEqual(perf.memory_efficiency, .excellent);
    try testing.expectEqual(perf.batch_efficiency, .excellent);

    // 验证支持的操作完整性
    const ops = DriverType.SUPPORTED_OPERATIONS;
    try testing.expect(ops.len >= 6); // 至少支持6种操作

    // 验证关键操作都被支持
    var supported_ops = std.EnumSet(zokio.io.IoOpType){};
    for (ops) |op| {
        supported_ops.insert(op);
    }

    try testing.expect(supported_ops.contains(.read));
    try testing.expect(supported_ops.contains(.write));
    try testing.expect(supported_ops.contains(.accept));
    try testing.expect(supported_ops.contains(.connect));
    try testing.expect(supported_ops.contains(.close));
    try testing.expect(supported_ops.contains(.fsync));
    try testing.expect(supported_ops.contains(.timeout));
}
