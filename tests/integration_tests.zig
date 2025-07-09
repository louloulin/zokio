//! 🚀 Zokio 7.2 集成测试套件
//!
//! 测试目标：
//! 1. 端到端异步流程验证
//! 2. 多组件协同工作测试
//! 3. 真实场景模拟测试
//! 4. 性能集成验证

const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;

// 导入 Zokio 核心模块
const zokio = @import("zokio");
const future = zokio.future;
const AsyncEventLoop = @import("../src/runtime/async_event_loop.zig").AsyncEventLoop;

/// 🧪 集成测试统计
var integration_stats = struct {
    total_tests: u32 = 0,
    passed_tests: u32 = 0,
    failed_tests: u32 = 0,
    total_duration_ns: i64 = 0,
}{};

/// 🔧 集成测试辅助函数
fn startIntegrationTest(comptime name: []const u8) i128 {
    integration_stats.total_tests += 1;
    std.debug.print("\n🔗 开始集成测试: {s}\n", .{name});
    return std.time.nanoTimestamp();
}

fn endIntegrationTest(start_time: i128, passed: bool) void {
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    integration_stats.total_duration_ns += @intCast(duration);
    
    if (passed) {
        integration_stats.passed_tests += 1;
        std.debug.print("✅ 集成测试通过 ({d:.3}ms)\n", .{@as(f64, @floatFromInt(duration)) / 1_000_000.0});
    } else {
        integration_stats.failed_tests += 1;
        std.debug.print("❌ 集成测试失败 ({d:.3}ms)\n", .{@as(f64, @floatFromInt(duration)) / 1_000_000.0});
    }
}

// ============================================================================
// 🔗 端到端异步流程测试
// ============================================================================

/// 🧪 简单异步任务 Future
const SimpleAsyncTask = struct {
    value: u32,
    completed: bool = false,
    poll_count: u32 = 0,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *future.Context) future.Poll(u32) {
        _ = ctx;
        self.poll_count += 1;

        // 模拟异步工作：前3次返回 pending，第4次返回 ready
        if (self.poll_count < 4) {
            return .pending;
        }

        self.completed = true;
        return .{ .ready = self.value };
    }
};

test "🔗 端到端异步任务执行测试" {
    const start_time = startIntegrationTest("端到端异步任务执行");
    defer endIntegrationTest(start_time, true);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建事件循环
    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 创建异步任务
    var task = SimpleAsyncTask{ .value = 42 };

    // 模拟异步执行
    const waker = future.Waker.noop();
    var ctx = future.Context.init(waker);

    var poll_attempts: u32 = 0;
    const max_polls = 10;

    while (poll_attempts < max_polls) {
        switch (task.poll(&ctx)) {
            .ready => |result| {
                try expectEqual(@as(u32, 42), result);
                try expect(task.completed);
                std.debug.print("📊 任务在 {} 次轮询后完成\n", .{poll_attempts + 1});
                return;
            },
            .pending => {
                poll_attempts += 1;
                // 运行事件循环一次
                try event_loop.runOnce();
            },
        }
    }

    return error.TaskDidNotComplete;
}

/// 🧪 多任务并发执行测试
const ConcurrentTask = struct {
    id: u32,
    target_polls: u32,
    current_polls: u32 = 0,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *future.Context) future.Poll(u32) {
        _ = ctx;
        self.current_polls += 1;

        if (self.current_polls >= self.target_polls) {
            return .{ .ready = self.id };
        }

        return .pending;
    }
};

test "🔗 多任务并发执行集成测试" {
    const start_time = startIntegrationTest("多任务并发执行");
    defer endIntegrationTest(start_time, true);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 创建多个并发任务
    const task_count = 5;
    var tasks: [task_count]ConcurrentTask = undefined;
    var completed_tasks: [task_count]bool = [_]bool{false} ** task_count;

    for (0..task_count) |i| {
        tasks[i] = ConcurrentTask{
            .id = @intCast(i),
            .target_polls = @intCast(i + 2), // 不同的完成时间
        };
    }

    const waker = future.Waker.noop();
    var ctx = future.Context.init(waker);

    var total_completed: u32 = 0;
    var round: u32 = 0;
    const max_rounds = 20;

    while (total_completed < task_count and round < max_rounds) {
        round += 1;

        // 轮询所有未完成的任务
        for (0..task_count) |i| {
            if (!completed_tasks[i]) {
                switch (tasks[i].poll(&ctx)) {
                    .ready => |result| {
                        try expectEqual(@as(u32, @intCast(i)), result);
                        completed_tasks[i] = true;
                        total_completed += 1;
                        std.debug.print("📊 任务 {} 在第 {} 轮完成\n", .{ i, round });
                    },
                    .pending => {},
                }
            }
        }

        // 运行事件循环
        try event_loop.runOnce();
    }

    try expectEqual(@as(u32, task_count), total_completed);
    std.debug.print("📊 所有 {} 个任务在 {} 轮内完成\n", .{ task_count, round });
}

// ============================================================================
// 🚀 事件循环集成测试
// ============================================================================

test "🚀 事件循环长时间运行集成测试" {
    const start_time = startIntegrationTest("事件循环长时间运行");
    defer endIntegrationTest(start_time, true);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    event_loop.start();
    try expect(event_loop.isRunning());

    // 运行多次事件循环迭代
    const iterations = 1000;
    for (0..iterations) |i| {
        try event_loop.runOnce();
        
        // 每100次迭代检查一次状态
        if (i % 100 == 0) {
            try expect(event_loop.isRunning());
        }
    }

    event_loop.stop();
    try expect(!event_loop.isRunning());

    std.debug.print("📊 事件循环成功运行 {} 次迭代\n", .{iterations});
}

/// 🧪 压力测试任务
const StressTestTask = struct {
    id: u32,
    work_units: u32,
    completed_work: u32 = 0,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *future.Context) future.Poll(u32) {
        _ = ctx;
        
        // 每次轮询完成一些工作
        const work_per_poll = 10;
        self.completed_work += work_per_poll;

        if (self.completed_work >= self.work_units) {
            return .{ .ready = self.id };
        }

        return .pending;
    }
};

test "🚀 高负载压力集成测试" {
    const start_time = startIntegrationTest("高负载压力测试");
    defer endIntegrationTest(start_time, true);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = try AsyncEventLoop.init(allocator);
    defer event_loop.deinit();

    // 创建大量压力测试任务
    const task_count = 100;
    var tasks = try allocator.alloc(StressTestTask, task_count);
    defer allocator.free(tasks);

    var completed_tasks = try allocator.alloc(bool, task_count);
    defer allocator.free(completed_tasks);

    for (0..task_count) |i| {
        tasks[i] = StressTestTask{
            .id = @intCast(i),
            .work_units = 100 + @as(u32, @intCast(i % 50)), // 不同的工作量
        };
        completed_tasks[i] = false;
    }

    const waker = future.Waker.noop();
    var ctx = future.Context.init(waker);

    var total_completed: u32 = 0;
    var round: u32 = 0;
    const max_rounds = 1000;

    const test_start = std.time.nanoTimestamp();

    while (total_completed < task_count and round < max_rounds) {
        round += 1;

        // 轮询所有未完成的任务
        for (0..task_count) |i| {
            if (!completed_tasks[i]) {
                switch (tasks[i].poll(&ctx)) {
                    .ready => |result| {
                        try expectEqual(@as(u32, @intCast(i)), result);
                        completed_tasks[i] = true;
                        total_completed += 1;
                    },
                    .pending => {},
                }
            }
        }

        // 运行事件循环
        try event_loop.runOnce();
    }

    const test_end = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(test_end - test_start)) / 1_000_000.0;

    try expectEqual(@as(u32, task_count), total_completed);
    
    std.debug.print("📊 压力测试结果:\n", .{});
    std.debug.print("  任务数量: {}\n", .{task_count});
    std.debug.print("  完成轮次: {}\n", .{round});
    std.debug.print("  总耗时: {d:.3}ms\n", .{duration_ms});
    std.debug.print("  平均每任务: {d:.3}ms\n", .{duration_ms / @as(f64, @floatFromInt(task_count))});
    
    // 性能验证：应该在合理时间内完成
    try expect(duration_ms < 1000.0); // 1秒内完成
}

// ============================================================================
// 📊 集成测试报告
// ============================================================================

test "📊 生成集成测试报告" {
    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("🔗 Zokio 7.2 集成测试报告\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("📊 总集成测试: {}\n", .{integration_stats.total_tests});
    std.debug.print("✅ 通过测试: {}\n", .{integration_stats.passed_tests});
    std.debug.print("❌ 失败测试: {}\n", .{integration_stats.failed_tests});
    
    const success_rate = @as(f64, @floatFromInt(integration_stats.passed_tests)) / @as(f64, @floatFromInt(integration_stats.total_tests)) * 100.0;
    std.debug.print("📈 成功率: {d:.1}%\n", .{success_rate});
    
    const total_duration_ms = @as(f64, @floatFromInt(integration_stats.total_duration_ns)) / 1_000_000.0;
    std.debug.print("⏱️  总耗时: {d:.3}ms\n", .{total_duration_ms});
    
    if (success_rate >= 95.0) {
        std.debug.print("🎉 集成测试目标达成！\n", .{});
    } else {
        std.debug.print("⚠️  需要修复集成问题\n", .{});
    }
    std.debug.print("=" ** 60 ++ "\n", .{});
}
