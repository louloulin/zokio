//! 🚀 Zokio 7.0 事件驱动核心测试
//!
//! 测试目标：
//! 1. 验证新的事件驱动 await_fn 实现
//! 2. 测试 EventDrivenRuntime 基础功能
//! 3. 确保没有无限循环问题
//! 4. 验证性能改进

const std = @import("std");
const testing = std.testing;

// 导入新的事件驱动模块
const event_driven_await = @import("src/future/event_driven_await.zig");
const EventDrivenRuntime = @import("src/runtime/event_driven_runtime.zig").EventDrivenRuntime;
const future = @import("src/future/future.zig");
const Poll = future.Poll;

test "🚀 Zokio 7.0 事件驱动 await_fn 基础测试" {
    std.debug.print("\n🚀 测试事件驱动 await_fn 基础功能...\n", .{});

    // 创建立即完成的 Future
    const immediate_future = event_driven_await.createTestFuture(42);
    
    const start_time = std.time.nanoTimestamp();
    const result = event_driven_await.await_fn(immediate_future);
    const end_time = std.time.nanoTimestamp();
    
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    std.debug.print("✅ 立即完成 Future 结果: {}\n", .{result});
    std.debug.print("✅ 执行时间: {d:.3}ms\n", .{duration_ms});
    
    try testing.expect(result == 42);
    try testing.expect(duration_ms < 10.0); // 应该很快完成
    
    std.debug.print("✅ 事件驱动 await_fn 基础测试通过！\n", .{});
}

test "🚀 Zokio 7.0 事件驱动运行时创建测试" {
    std.debug.print("\n🚀 测试事件驱动运行时创建...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建事件驱动运行时
    var runtime = try EventDrivenRuntime.init(allocator);
    defer runtime.deinit();

    // 获取初始统计信息
    const initial_stats = runtime.getStats();
    std.debug.print("📊 初始状态:\n", .{});
    std.debug.print("  活跃任务: {}\n", .{initial_stats.active_tasks});
    std.debug.print("  队列任务: {}\n", .{initial_stats.queued_tasks});
    std.debug.print("  运行状态: {}\n", .{initial_stats.is_running});

    try testing.expect(initial_stats.active_tasks == 0);
    try testing.expect(initial_stats.queued_tasks == 0);
    try testing.expect(!initial_stats.is_running);

    std.debug.print("✅ 事件驱动运行时创建测试通过！\n", .{});
}

test "🚀 Zokio 7.0 事件驱动运行时启动停止测试" {
    std.debug.print("\n🚀 测试事件驱动运行时启动停止...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try EventDrivenRuntime.init(allocator);
    defer runtime.deinit();

    // 测试启动
    std.debug.print("🔄 启动运行时...\n", .{});
    try runtime.start();

    const running_stats = runtime.getStats();
    std.debug.print("📊 运行状态:\n", .{});
    std.debug.print("  运行状态: {}\n", .{running_stats.is_running});

    try testing.expect(running_stats.is_running);

    // 测试停止
    std.debug.print("🛑 停止运行时...\n", .{});
    runtime.stop();

    const stopped_stats = runtime.getStats();
    std.debug.print("📊 停止状态:\n", .{});
    std.debug.print("  运行状态: {}\n", .{stopped_stats.is_running});

    try testing.expect(!stopped_stats.is_running);

    std.debug.print("✅ 事件驱动运行时启动停止测试通过！\n", .{});
}

test "⚡ Zokio 7.0 性能基准测试 - 事件驱动 await_fn" {
    std.debug.print("\n⚡ 事件驱动 await_fn 性能测试...\n", .{});

    const iterations = 10_000;
    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const test_future = event_driven_await.createTestFuture(@intCast(i % 1000));
        const result = event_driven_await.await_fn(test_future);
        try testing.expect(result == i % 1000);
    }

    const end_time = std.time.nanoTimestamp();
    const total_duration_ns = end_time - start_time;
    const avg_duration_ns = @divTrunc(total_duration_ns, iterations);
    const ops_per_sec = @divTrunc(@as(i128, 1_000_000_000), avg_duration_ns);

    std.debug.print("📊 事件驱动 await_fn 性能:\n", .{});
    std.debug.print("  迭代次数: {}\n", .{iterations});
    std.debug.print("  总时间: {}ns ({d:.3}ms)\n", .{ total_duration_ns, @as(f64, @floatFromInt(total_duration_ns)) / 1_000_000.0 });
    std.debug.print("  平均每次: {}ns\n", .{avg_duration_ns});
    std.debug.print("  吞吐量: {} ops/sec\n", .{ops_per_sec});

    // 验证性能目标：至少 100K ops/sec
    try testing.expect(ops_per_sec > 100_000);

    if (ops_per_sec > 1_000_000) {
        std.debug.print("🎯 性能目标达成: {} ops/sec > 1M ops/sec\n", .{ops_per_sec});
    } else {
        std.debug.print("✅ 性能良好: {} ops/sec > 100K ops/sec\n", .{ops_per_sec});
    }

    std.debug.print("✅ 事件驱动 await_fn 性能测试通过！\n", .{});
}

test "🔄 Zokio 7.0 无限循环检测测试" {
    std.debug.print("\n🔄 测试无限循环检测...\n", .{});

    // 创建永远 pending 的 Future
    const PendingFuture = struct {
        pub const Output = u32;
        
        pub fn poll(self: *@This(), ctx: *anyopaque) Poll(u32) {
            _ = self;
            _ = ctx;
            // 永远返回 pending
            return .pending;
        }
    };

    const pending_future = PendingFuture{};

    const start_time = std.time.nanoTimestamp();
    const result = event_driven_await.await_fn(pending_future);
    const end_time = std.time.nanoTimestamp();

    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    std.debug.print("📊 永远 pending Future 测试:\n", .{});
    std.debug.print("  结果: {} (应该是默认值 0)\n", .{result});
    std.debug.print("  执行时间: {d:.3}ms\n", .{duration_ms});

    // 验证没有无限循环
    try testing.expect(duration_ms < 1000.0); // 应该在 1 秒内完成
    try testing.expect(result == 0); // 应该返回默认值

    std.debug.print("✅ 无限循环检测测试通过！\n", .{});
}

test "🎯 Zokio 7.0 综合集成测试" {
    std.debug.print("\n🎯 综合集成测试...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建运行时
    var runtime = try EventDrivenRuntime.init(allocator);
    defer runtime.deinit();

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 测试多个 Future
    const test_count = 100;
    var results: [test_count]u32 = undefined;

    const start_time = std.time.nanoTimestamp();

    for (0..test_count) |i| {
        const test_future = event_driven_await.createTestFuture(@intCast(i));
        results[i] = event_driven_await.await_fn(test_future);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // 验证结果
    for (0..test_count) |i| {
        try testing.expect(results[i] == i);
    }

    std.debug.print("📊 综合集成测试结果:\n", .{});
    std.debug.print("  测试数量: {}\n", .{test_count});
    std.debug.print("  总时间: {d:.3}ms\n", .{duration_ms});
    std.debug.print("  平均每次: {d:.3}ms\n", .{duration_ms / @as(f64, @floatFromInt(test_count))});

    const final_stats = runtime.getStats();
    std.debug.print("📊 最终运行时状态:\n", .{});
    std.debug.print("  活跃任务: {}\n", .{final_stats.active_tasks});
    std.debug.print("  队列任务: {}\n", .{final_stats.queued_tasks});

    try testing.expect(duration_ms < 100.0); // 应该很快完成

    std.debug.print("✅ 综合集成测试通过！\n", .{});
}

/// 🧪 测试辅助函数：创建延迟 Future
fn createDelayedFuture(value: u32, delay_polls: u32) DelayedFuture {
    return DelayedFuture{
        .value = value,
        .delay_polls = delay_polls,
        .poll_count = 0,
    };
}

const DelayedFuture = struct {
    value: u32,
    delay_polls: u32,
    poll_count: u32,

    pub const Output = u32;

    pub fn poll(self: *@This(), ctx: *anyopaque) Poll(u32) {
        _ = ctx;
        self.poll_count += 1;

        if (self.poll_count >= self.delay_polls) {
            return .{ .ready = self.value };
        }

        return .pending;
    }
};
