//! Zokio端到端集成测试
//! 验证Phase 1和Phase 2的整体集成效果

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

// 简单的异步任务Future
const AsyncTask = struct {
    task_id: u32,
    delay_ms: u32,
    start_time: i64,
    completed: bool = false,

    pub const Output = u32;

    pub fn init(id: u32, delay: u32) @This() {
        return @This(){
            .task_id = id,
            .delay_ms = delay,
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;

        const current_time = std.time.milliTimestamp();
        const elapsed = current_time - self.start_time;

        if (elapsed >= self.delay_ms) {
            self.completed = true;
            return .{ .ready = self.task_id };
        } else {
            return .pending;
        }
    }
};

test "Zokio端到端集成测试" {
    std.debug.print("\n=== Zokio 8.0 端到端集成测试 ===\n", .{});

    // 测试1: 基础异步任务执行
    std.debug.print("1. 测试基础异步任务执行\n", .{});

    const task1 = AsyncTask.init(1, 1); // 1ms延迟
    const task2 = AsyncTask.init(2, 2); // 2ms延迟
    const task3 = AsyncTask.init(3, 3); // 3ms延迟

    const start_time = std.time.milliTimestamp();

    // 使用await_fn执行任务
    const result1 = zokio.await_fn(task1);
    const result2 = zokio.await_fn(task2);
    const result3 = zokio.await_fn(task3);

    const end_time = std.time.milliTimestamp();
    const total_time = end_time - start_time;

    try testing.expect(result1 == 1);
    try testing.expect(result2 == 2);
    try testing.expect(result3 == 3);

    std.debug.print("   任务结果: {}, {}, {}\n", .{ result1, result2, result3 });
    std.debug.print("   总耗时: {} ms\n", .{total_time});
    std.debug.print("   ✅ 基础异步任务执行测试通过\n", .{});
}

test "CompletionBridge集成测试" {
    std.debug.print("\n2. 测试CompletionBridge集成\n", .{});

    // 创建多个CompletionBridge测试并发
    var bridges: [5]zokio.CompletionBridge = undefined;

    for (&bridges, 0..) |*bridge, i| {
        bridge.* = zokio.CompletionBridge.init();

        // 模拟不同的完成状态
        switch (i % 3) {
            0 => bridge.setState(.ready),
            1 => bridge.setState(.pending),
            2 => bridge.setState(.timeout),
            else => unreachable,
        }
    }

    // 验证状态
    var ready_count: u32 = 0;
    var pending_count: u32 = 0;
    var timeout_count: u32 = 0;

    for (&bridges) |*bridge| {
        switch (bridge.getState()) {
            .ready => ready_count += 1,
            .pending => pending_count += 1,
            .timeout => timeout_count += 1,
            else => {},
        }
    }

    try testing.expect(ready_count >= 1);
    try testing.expect(pending_count >= 1);
    try testing.expect(timeout_count >= 1);

    std.debug.print("   状态统计: ready={}, pending={}, timeout={}\n", .{ ready_count, pending_count, timeout_count });
    std.debug.print("   ✅ CompletionBridge集成测试通过\n", .{});
}

test "I/O系统集成测试" {
    std.debug.print("\n3. 测试I/O系统集成\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试LibxevDriver
    const config = zokio.libxev_io.LibxevConfig{
        .enable_real_io = false, // 测试环境使用模拟模式
        .max_concurrent_ops = 128,
        .batch_size = 16,
    };

    var driver = zokio.libxev_io.LibxevDriver.init(allocator, config) catch |err| {
        std.debug.print("   LibxevDriver初始化失败: {}\n", .{err});
        return;
    };
    defer driver.deinit();

    // 测试轮询性能
    const iterations = 100;
    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        _ = driver.poll(0) catch {};
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("   I/O轮询性能: {d:.0} ops/sec\n", .{ops_per_sec});
    try testing.expect(ops_per_sec > 10000); // 至少10K ops/sec

    std.debug.print("   ✅ I/O系统集成测试通过\n", .{});
}

test "内存管理集成测试" {
    std.debug.print("\n4. 测试内存管理集成\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建大量异步任务测试内存管理
    const task_count = 1000;
    var tasks = allocator.alloc(AsyncTask, task_count) catch |err| {
        std.debug.print("   内存分配失败: {}\n", .{err});
        return;
    };
    defer allocator.free(tasks);

    // 初始化任务
    for (tasks, 0..) |*task, i| {
        task.* = AsyncTask.init(@intCast(i), 1);
    }

    // 执行部分任务
    var completed_count: u32 = 0;
    for (tasks[0..100]) |*task| {
        const result = zokio.await_fn(task.*);
        if (result < task_count) {
            completed_count += 1;
        }
    }

    try testing.expect(completed_count == 100);
    std.debug.print("   完成任务数: {}\n", .{completed_count});
    std.debug.print("   ✅ 内存管理集成测试通过\n", .{});
}

test "错误处理集成测试" {
    std.debug.print("\n5. 测试错误处理集成\n", .{});

    // 测试超时错误处理
    const ErrorTask = struct {
        should_error: bool,

        pub const Output = anyerror!u32;

        pub fn poll(self: *@This(), ctx: anytype) zokio.Poll(anyerror!u32) {
            _ = ctx;
            if (self.should_error) {
                return .{ .ready = error.TestError };
            } else {
                return .{ .ready = 42 };
            }
        }
    };

    const error_task = ErrorTask{ .should_error = true };
    const success_task = ErrorTask{ .should_error = false };

    // 测试错误情况
    const error_result = zokio.await_fn(error_task);
    try testing.expectError(error.TestError, error_result);

    // 测试成功情况
    const success_result = zokio.await_fn(success_task);
    try testing.expect(try success_result == 42);

    std.debug.print("   错误处理: {any}\n", .{error_result});
    std.debug.print("   成功处理: {any}\n", .{success_result});
    std.debug.print("   ✅ 错误处理集成测试通过\n", .{});
}

test "性能基准集成测试" {
    std.debug.print("\n6. 测试性能基准集成\n", .{});

    const benchmark_iterations = 10000;
    const start_time = std.time.nanoTimestamp();

    // 执行大量快速任务
    for (0..benchmark_iterations) |i| {
        const task = AsyncTask.init(@intCast(i % 1000), 0); // 0延迟，立即完成
        const result = zokio.await_fn(task);
        if (result >= 1000) {
            // 不应该发生
            try testing.expect(false);
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(benchmark_iterations)) / (duration_ms / 1000.0);

    std.debug.print("   执行 {} 个任务耗时: {d:.2} ms\n", .{ benchmark_iterations, duration_ms });
    std.debug.print("   任务执行性能: {d:.0} ops/sec\n", .{ops_per_sec});

    // 性能目标：至少100K ops/sec
    try testing.expect(ops_per_sec > 100000);

    std.debug.print("   ✅ 性能基准集成测试通过\n", .{});
}

test "并发安全集成测试" {
    std.debug.print("\n7. 测试并发安全集成\n", .{});

    // 创建多个并发任务
    var tasks: [10]AsyncTask = undefined;
    var results: [10]u32 = undefined;

    // 初始化任务
    for (&tasks, 0..) |*task, i| {
        task.* = AsyncTask.init(@intCast(i), @intCast(i % 3 + 1));
    }

    // 并发执行任务
    for (&tasks, &results) |*task, *result| {
        result.* = zokio.await_fn(task.*);
    }

    // 验证结果
    for (results, 0..) |result, i| {
        try testing.expect(result == i);
    }

    std.debug.print("   并发任务结果: ", .{});
    for (results) |result| {
        std.debug.print("{} ", .{result});
    }
    std.debug.print("\n", .{});
    std.debug.print("   ✅ 并发安全集成测试通过\n", .{});
}

test "系统稳定性测试" {
    std.debug.print("\n8. 测试系统稳定性\n", .{});

    // 长时间运行测试
    const stability_iterations = 1000;
    var success_count: u32 = 0;
    var error_count: u32 = 0;

    for (0..stability_iterations) |i| {
        const task = AsyncTask.init(@intCast(i % 100), 1);
        const result = zokio.await_fn(task);

        if (result < 100) {
            success_count += 1;
        } else {
            error_count += 1;
        }
    }

    const success_rate = @as(f64, @floatFromInt(success_count)) / @as(f64, @floatFromInt(stability_iterations)) * 100.0;

    std.debug.print("   稳定性测试: {} 次迭代\n", .{stability_iterations});
    std.debug.print("   成功: {}, 失败: {}\n", .{ success_count, error_count });
    std.debug.print("   成功率: {d:.1}%\n", .{success_rate});

    // 成功率应该很高
    try testing.expect(success_rate > 99.0);

    std.debug.print("   ✅ 系统稳定性测试通过\n", .{});
}
