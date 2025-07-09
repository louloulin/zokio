//! 🚀 Zokio 7.1 无限循环修复验证测试
//!
//! 测试目标：
//! 1. 验证 AsyncEventLoop 不再陷入无限循环
//! 2. 测试事件循环的超时和退出机制
//! 3. 确保任务计数器正确工作
//! 4. 验证 Waker 和 Timer 系统正常运行

const std = @import("std");
const testing = std.testing;

// 导入修复后的模块
const AsyncEventLoop = @import("src/runtime/async_event_loop.zig").AsyncEventLoop;
const future = @import("src/future/future.zig");

test "🚀 Zokio 7.1 AsyncEventLoop 基础创建测试" {
    std.debug.print("\n🚀 测试 AsyncEventLoop 基础创建...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建事件循环
    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 验证初始状态
    try testing.expect(!event_loop.isRunning());
    try testing.expect(!event_loop.hasActiveTasks());

    std.debug.print("✅ AsyncEventLoop 基础创建测试通过！\n", .{});
}

test "🚀 Zokio 7.1 AsyncEventLoop 启动停止测试" {
    std.debug.print("\n🚀 测试 AsyncEventLoop 启动停止...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 测试启动
    std.debug.print("🔄 启动事件循环...\n", .{});
    event_loop.start();

    try testing.expect(event_loop.isRunning());

    // 测试停止
    std.debug.print("🛑 停止事件循环...\n", .{});
    event_loop.stop();

    try testing.expect(!event_loop.isRunning());

    std.debug.print("✅ AsyncEventLoop 启动停止测试通过！\n", .{});
}

test "🚀 Zokio 7.1 AsyncEventLoop runOnce 测试" {
    std.debug.print("\n🚀 测试 AsyncEventLoop runOnce...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 测试单次运行
    const start_time = std.time.nanoTimestamp();
    try event_loop.runOnce();
    const end_time = std.time.nanoTimestamp();

    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    std.debug.print("📊 runOnce 执行时间: {d:.3}ms\n", .{duration_ms});

    // 验证没有陷入无限循环
    try testing.expect(duration_ms < 100.0); // 应该在 100ms 内完成

    std.debug.print("✅ AsyncEventLoop runOnce 测试通过！\n", .{});
}

test "🚀 Zokio 7.1 AsyncEventLoop 无限循环防护测试" {
    std.debug.print("\n🚀 测试 AsyncEventLoop 无限循环防护...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 启动事件循环
    event_loop.start();

    // 测试运行事件循环（应该快速退出，因为没有活跃任务）
    const start_time = std.time.nanoTimestamp();
    
    // 在单独的线程中运行事件循环，避免阻塞测试
    const RunContext = struct {
        event_loop: *AsyncEventLoop,
        completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        
        fn runEventLoop(self: *@This()) void {
            self.event_loop.run() catch {};
            self.completed.store(true, .release);
        }
    };
    
    var run_context = RunContext{ .event_loop = &event_loop };
    
    const thread = try std.Thread.spawn(.{}, RunContext.runEventLoop, .{&run_context});
    defer thread.join();
    
    // 等待最多 5 秒
    var wait_count: u32 = 0;
    while (!run_context.completed.load(.acquire) and wait_count < 50) {
        std.time.sleep(100 * std.time.ns_per_ms); // 100ms
        wait_count += 1;
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    std.debug.print("📊 事件循环运行时间: {d:.3}ms\n", .{duration_ms});
    std.debug.print("📊 等待轮次: {}\n", .{wait_count});
    
    // 验证事件循环正常退出
    try testing.expect(run_context.completed.load(.acquire));
    try testing.expect(duration_ms < 5000.0); // 应该在 5 秒内完成
    
    event_loop.stop();

    std.debug.print("✅ AsyncEventLoop 无限循环防护测试通过！\n", .{});
}

test "🚀 Zokio 7.1 WakerRegistry 基础测试" {
    std.debug.print("\n🚀 测试 WakerRegistry 基础功能...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 测试 wakeReady 方法
    const woken_count = event_loop.waker_registry.wakeReady();
    std.debug.print("📊 唤醒任务数量: {}\n", .{woken_count});

    try testing.expect(woken_count == 0); // 初始状态应该没有任务

    std.debug.print("✅ WakerRegistry 基础测试通过！\n", .{});
}

test "🚀 Zokio 7.1 TimerWheel 基础测试" {
    std.debug.print("\n🚀 测试 TimerWheel 基础功能...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 测试 processExpired 方法
    const expired_count = event_loop.timer_wheel.processExpired();
    std.debug.print("📊 过期定时器数量: {}\n", .{expired_count});

    try testing.expect(expired_count == 0); // 初始状态应该没有定时器

    std.debug.print("✅ TimerWheel 基础测试通过！\n", .{});
}

test "⚡ Zokio 7.1 性能基准测试 - 事件循环创建" {
    std.debug.print("\n⚡ 事件循环创建性能测试...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        var event_loop = try AsyncEventLoop.init(allocator);
        event_loop.deinit();
    }

    const end_time = std.time.nanoTimestamp();
    const total_duration_ns = end_time - start_time;
    const avg_duration_ns = @divTrunc(total_duration_ns, iterations);
    const ops_per_sec = @divTrunc(@as(i128, 1_000_000_000), avg_duration_ns);

    std.debug.print("📊 事件循环创建性能:\n", .{});
    std.debug.print("  迭代次数: {}\n", .{iterations});
    std.debug.print("  总时间: {}ns ({d:.3}ms)\n", .{ total_duration_ns, @as(f64, @floatFromInt(total_duration_ns)) / 1_000_000.0 });
    std.debug.print("  平均每次: {}ns\n", .{avg_duration_ns});
    std.debug.print("  吞吐量: {} ops/sec\n", .{ops_per_sec});

    // 验证性能目标：至少 10K ops/sec
    try testing.expect(ops_per_sec > 10_000);

    std.debug.print("✅ 性能目标达成: {} ops/sec > 10K ops/sec\n", .{ops_per_sec});
}

test "🎯 Zokio 7.1 综合修复验证测试" {
    std.debug.print("\n🎯 综合修复验证测试...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建多个事件循环实例
    const loop_count = 10;
    var event_loops: [loop_count]AsyncEventLoop = undefined;

    const start_time = std.time.nanoTimestamp();

    // 初始化所有事件循环
    for (0..loop_count) |i| {
        event_loops[i] = try AsyncEventLoop.init(allocator);
    }

    // 测试所有事件循环的基础操作
    for (0..loop_count) |i| {
        try testing.expect(!event_loops[i].isRunning());
        try testing.expect(!event_loops[i].hasActiveTasks());
        
        // 测试单次运行
        try event_loops[i].runOnce();
        
        // 测试组件功能
        _ = event_loops[i].waker_registry.wakeReady();
        _ = event_loops[i].timer_wheel.processExpired();
    }

    // 清理所有事件循环
    for (0..loop_count) |i| {
        event_loops[i].deinit();
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    std.debug.print("📊 综合测试结果:\n", .{});
    std.debug.print("  事件循环数量: {}\n", .{loop_count});
    std.debug.print("  总时间: {d:.3}ms\n", .{duration_ms});
    std.debug.print("  平均每个: {d:.3}ms\n", .{duration_ms / @as(f64, @floatFromInt(loop_count))});

    // 验证没有无限循环或性能问题
    try testing.expect(duration_ms < 1000.0); // 应该在 1 秒内完成

    std.debug.print("✅ 综合修复验证测试通过！\n", .{});
}
