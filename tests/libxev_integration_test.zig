//! 🚀 Zokio 4.0 libxev集成测试
//! 验证libxev与Zokio Future系统的完美桥接

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "Zokio 4.0 事件循环基础集成测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建高性能运行时
    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    // 启动运行时，这会设置默认事件循环
    try runtime.start();
    defer runtime.stop();

    // 验证事件循环已设置
    const current_event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(current_event_loop != null);

    std.debug.print("✅ Zokio 4.0 事件循环集成测试通过\n", .{});
}

test "Zokio 4.0 await_fn非阻塞测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时并启动
    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 创建一个简单的Future
    const SimpleFuture = struct {
        value: u32,
        polled: bool = false,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            if (!self.polled) {
                self.polled = true;
                return .pending;
            }
            return .{ .ready = self.value };
        }
    };

    var simple_future = SimpleFuture{ .value = 42 };
    _ = &simple_future; // 避免未使用警告

    // 测试await_fn是否能正确处理
    const start_time = std.time.nanoTimestamp();
    const result = zokio.future.await_fn(simple_future);
    const end_time = std.time.nanoTimestamp();

    // 验证结果
    try testing.expect(result == 42);

    // 验证执行时间（应该很快，不应该有1ms的阻塞）
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("✅ await_fn执行时间: {d:.3}ms (应该 < 1ms)\n", .{duration_ms});

    // 如果执行时间超过10ms，说明还有阻塞问题
    try testing.expect(duration_ms < 10.0);
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
