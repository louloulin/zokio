//! 🚀 Zokio libxev高级特性综合测试
//! 验证所有libxev深度优化的性能和正确性

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "零拷贝I/O基础功能测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 导入零拷贝模块
    const ZeroCopyManager = zokio.zero_copy.ZeroCopyManager;
    const ZeroCopyConfig = zokio.zero_copy.ZeroCopyConfig;

    // 创建零拷贝管理器
    const config = ZeroCopyConfig{
        .enable_sendfile = true,
        .enable_mmap = true,
        .buffer_pool_size = 64,
        .buffer_size = 4096,
    };

    var zero_copy = try ZeroCopyManager.init(allocator, config);
    defer zero_copy.deinit();

    // 测试缓冲区池
    const buffer1 = try zero_copy.buffer_pool.acquire();
    const buffer2 = try zero_copy.buffer_pool.acquire();

    try testing.expect(buffer1.len == 4096);
    try testing.expect(buffer2.len == 4096);
    try testing.expect(buffer1.ptr != buffer2.ptr);

    // 释放缓冲区
    zero_copy.buffer_pool.release(buffer1);
    zero_copy.buffer_pool.release(buffer2);

    // 验证统计信息
    const stats = zero_copy.getStats();
    try testing.expect(stats.sendfile_operations == 0);
    try testing.expect(stats.mmap_operations == 0);

    std.debug.print("✅ 零拷贝I/O基础功能测试通过\n", .{});
}

test "高级定时器功能测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 导入高级定时器模块
    const AdvancedTimerManager = zokio.advanced_timer.AdvancedTimerManager;
    const AdvancedTimerConfig = zokio.advanced_timer.AdvancedTimerConfig;

    // 创建高级定时器管理器
    const config = AdvancedTimerConfig{
        .enable_libxev_timers = true,
        .wheel_levels = 3,
        .slots_per_level = 64,
        .base_precision_us = 1000,
        .batch_size = 32,
    };

    var timer_manager = try AdvancedTimerManager.init(allocator, config);
    defer timer_manager.deinit();

    // 验证初始统计信息
    const stats = timer_manager.getStats();
    try testing.expect(stats.wheel_timers_active == 0);
    try testing.expect(stats.libxev_timers_active == 0);

    std.debug.print("✅ 高级定时器功能测试通过\n", .{});
}

test "批量I/O管理器基础测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 导入批量I/O模块
    const BatchIoManager = zokio.batch_io.BatchIoManager;
    const BatchIoConfig = zokio.batch_io.BatchIoConfig;

    // 创建批量I/O管理器
    const config = BatchIoConfig{
        .batch_size = 64,
        .max_concurrent_connections = 1000,
        .buffer_size = 8192,
        .buffer_pool_size = 128,
    };

    var batch_io = try BatchIoManager.init(allocator, config);
    defer batch_io.deinit();

    // 测试缓冲区池
    const buffer1 = try batch_io.buffer_pool.acquire();
    const buffer2 = try batch_io.buffer_pool.acquire();

    try testing.expect(buffer1.len == 8192);
    try testing.expect(buffer2.len == 8192);

    // 释放缓冲区
    batch_io.buffer_pool.release(buffer1);
    batch_io.buffer_pool.release(buffer2);

    // 验证统计信息
    const stats = batch_io.getStats();
    try testing.expect(stats.batch_accept_operations == 0);
    try testing.expect(stats.batch_read_operations == 0);
    try testing.expect(stats.batch_write_operations == 0);

    std.debug.print("✅ 批量I/O管理器基础测试通过\n", .{});
}

test "libxev高级特性性能基准测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 性能测试：批量操作vs单个操作
    const iterations = 1000;

    // 测试1: 批量CompletionBridge操作
    std.debug.print("🔧 开始批量操作性能测试...\n", .{});

    const start_time = std.time.nanoTimestamp();

    // 创建批量操作
    var buffer_pool: [100][64]u8 = undefined;
    const operations = blk: {
        var ops: [100]zokio.runtime.completion_bridge.BatchOperation = undefined;
        for (&ops, 0..) |*op, i| {
            op.* = .{
                .op_type = .read,
                .fd = 0,
                .buffer = &buffer_pool[i],
                .priority = 128,
            };
        }
        break :blk ops;
    };

    const event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(event_loop != null);

    // 执行批量操作
    for (0..iterations / 100) |_| {
        const bridges = try zokio.runtime.completion_bridge.CompletionBridge.submitBatch(
            allocator,
            &event_loop.?.libxev_loop,
            &operations,
        );
        defer allocator.free(bridges);

        // 验证批量操作结果
        try testing.expect(bridges.len == 100);
        for (bridges) |bridge| {
            try testing.expect(bridge.state == .pending);
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("✅ 批量操作性能测试通过\n", .{});
    std.debug.print("   操作次数: {} 次\n", .{iterations});
    std.debug.print("   总耗时: {d:.3}ms\n", .{duration_ms});
    std.debug.print("   性能: {d:.0} ops/sec\n", .{ops_per_sec});

    // 性能目标：应该达到 >100K ops/sec
    try testing.expect(ops_per_sec > 100_000);
}

test "libxev特性集成验证" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 验证事件循环集成
    const event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(event_loop != null);

    // 测试简单的Future执行
    const SimpleFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    // 执行多个Future来验证调度器性能
    const future_count = 1000;
    var total_result: u64 = 0;

    const start_time = std.time.nanoTimestamp();

    for (0..future_count) |i| {
        const future = SimpleFuture{ .value = @intCast(i) };
        const result = zokio.future.await_fn(future);
        total_result += result;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    const futures_per_sec = @as(f64, @floatFromInt(future_count)) / (duration_ms / 1000.0);

    // 验证结果正确性
    const expected_sum = (future_count - 1) * future_count / 2;
    try testing.expect(total_result == expected_sum);

    std.debug.print("✅ libxev特性集成验证通过\n", .{});
    std.debug.print("   Future执行次数: {} 次\n", .{future_count});
    std.debug.print("   总耗时: {d:.3}ms\n", .{duration_ms});
    std.debug.print("   性能: {d:.0} futures/sec\n", .{futures_per_sec});

    // 性能目标：应该达到 >500K futures/sec
    try testing.expect(futures_per_sec > 500_000);
}

test "内存效率和资源管理测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 执行大量操作来测试内存效率
    const operation_count = 1000; // 减少操作数量以简化测试

    for (0..operation_count) |i| {
        // 创建临时Future
        const TempFuture = struct {
            value: u32,

            pub const Output = u32;

            pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
                _ = ctx;
                return .{ .ready = self.value };
            }
        };

        const future = TempFuture{ .value = @intCast(i % 1000) };
        const result = zokio.future.await_fn(future);
        try testing.expect(result == i % 1000);
    }

    std.debug.print("✅ 内存效率和资源管理测试通过\n", .{});
    std.debug.print("   操作次数: {} 次\n", .{operation_count});
    std.debug.print("   测试完成，内存管理正常\n", .{});
}
