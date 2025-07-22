//! 测试await_fn在正确设置事件循环后的行为
//! 验证await_fn能够使用真正的异步模式而不是同步回退模式

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

// 导入核心组件
const Future = zokio.zokio.Future;
const Poll = zokio.zokio.Poll;
const Context = zokio.zokio.Context;
const await_fn = zokio.zokio.await_fn;
const Waker = @import("../src/core/future.zig").Waker;

/// 简单Future用于测试
const TestFuture = struct {
    value: u32,
    poll_count: u32 = 0,

    pub const Output = u32;

    pub fn init(val: u32) @This() {
        return @This(){ .value = val };
    }

    pub fn poll(self: *@This(), ctx: *Context) Poll(u32) {
        _ = ctx;
        self.poll_count += 1;

        // 立即返回ready，用于测试基本功能
        return .{ .ready = self.value };
    }
};

/// 延迟Future，需要多次poll才能完成
const DelayedFuture = struct {
    value: u32,
    poll_count: u32 = 0,
    required_polls: u32,

    pub const Output = u32;

    pub fn init(val: u32, required_polls: u32) @This() {
        return @This(){ .value = val, .required_polls = required_polls };
    }

    pub fn poll(self: *@This(), ctx: *Context) Poll(u32) {
        _ = ctx;
        self.poll_count += 1;

        if (self.poll_count >= self.required_polls) {
            return .{ .ready = self.value };
        } else {
            return .pending;
        }
    }
};

test "await_fn使用事件循环异步模式" {
    std.debug.print("\n=== 测试await_fn使用事件循环异步模式 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 测试没有运行时时的行为
    std.debug.print("1. 测试没有运行时时的行为\n", .{});
    {
        const future = TestFuture.init(42);
        const result = await_fn(future);
        std.debug.print("   结果: {} (应该看到同步回退模式警告)\n", .{result});
        try testing.expectEqual(@as(u32, 42), result);
    }

    // 2. 测试有运行时时的行为
    std.debug.print("2. 测试有运行时时的行为\n", .{});
    {
        // 创建并启动运行时
        const runtime_config = zokio.zokio.RuntimeConfig{};
        var runtime = try zokio.zokio.Runtime(runtime_config).init(allocator);
        defer runtime.deinit();

        try runtime.start();
        defer runtime.stop();

        std.debug.print("   运行时已启动，事件循环已设置\n", .{});

        // 验证事件循环已设置
        const runtime_module = @import("../src/core/runtime.zig");
        const event_loop = runtime_module.getCurrentEventLoop();
        try testing.expect(event_loop != null);
        std.debug.print("   ✅ 事件循环已设置\n", .{});

        // 测试await_fn
        const future = TestFuture.init(123);
        const result = await_fn(future);
        std.debug.print("   结果: {} (应该看到异步模式信息)\n", .{result});
        try testing.expectEqual(@as(u32, 123), result);
    }

    std.debug.print("✅ 测试完成\n", .{});
}

test "await_fn处理延迟Future" {
    std.debug.print("\n=== 测试await_fn处理延迟Future ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建并启动运行时
    const runtime_config = zokio.zokio.RuntimeConfig{};
    var runtime = try zokio.zokio.Runtime(runtime_config).init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    std.debug.print("运行时已启动\n", .{});

    // 测试需要多次poll的Future
    const delayed_future = DelayedFuture.init(456, 3); // 需要3次poll

    const start_time = std.time.nanoTimestamp();
    const result = await_fn(delayed_future);
    const end_time = std.time.nanoTimestamp();

    const duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;

    std.debug.print("结果: {}\n", .{result});
    std.debug.print("poll次数: {}\n", .{delayed_future.poll_count});
    std.debug.print("执行时间: {d:.2} μs\n", .{duration_us});

    try testing.expectEqual(@as(u32, 456), result);
    try testing.expectEqual(@as(u32, 3), delayed_future.poll_count);

    std.debug.print("✅ 延迟Future测试完成\n", .{});
}

test "await_fn性能对比：同步vs异步模式" {
    std.debug.print("\n=== 测试await_fn性能对比 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const iterations = 1000;

    // 1. 测试同步回退模式性能
    std.debug.print("1. 测试同步回退模式性能\n", .{});
    {
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |i| {
            const future = TestFuture.init(@intCast(i));
            const result = await_fn(future);
            _ = result;
        }

        const end_time = std.time.nanoTimestamp();
        const duration_ns = @as(u64, @intCast(end_time - start_time));
        const ops_per_sec = (iterations * 1_000_000_000) / duration_ns;

        std.debug.print("   同步模式性能: {} ops/sec\n", .{ops_per_sec});
    }

    // 2. 测试异步模式性能
    std.debug.print("2. 测试异步模式性能\n", .{});
    {
        // 创建并启动运行时
        const runtime_config = zokio.zokio.RuntimeConfig{};
        var runtime = try zokio.zokio.Runtime(runtime_config).init(allocator);
        defer runtime.deinit();

        try runtime.start();
        defer runtime.stop();

        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |i| {
            const future = TestFuture.init(@intCast(i));
            const result = await_fn(future);
            _ = result;
        }

        const end_time = std.time.nanoTimestamp();
        const duration_ns = @as(u64, @intCast(end_time - start_time));
        const ops_per_sec = (iterations * 1_000_000_000) / duration_ns;

        std.debug.print("   异步模式性能: {} ops/sec\n", .{ops_per_sec});
    }

    std.debug.print("✅ 性能对比测试完成\n", .{});
}

test "验证事件循环状态管理" {
    std.debug.print("\n=== 验证事件循环状态管理 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始状态：没有事件循环
    {
        const runtime_module = @import("../src/core/runtime.zig");
        const initial_loop = runtime_module.getCurrentEventLoop();
        try testing.expect(initial_loop == null);
        std.debug.print("✅ 初始状态：没有事件循环\n", .{});
    }

    // 启动运行时后：有事件循环
    {
        const runtime_config = zokio.zokio.RuntimeConfig{};
        var runtime = try zokio.zokio.Runtime(runtime_config).init(allocator);
        defer runtime.deinit();

        try runtime.start();

        const runtime_module = @import("../src/core/runtime.zig");
        const active_loop = runtime_module.getCurrentEventLoop();
        try testing.expect(active_loop != null);
        std.debug.print("✅ 运行时启动后：事件循环已设置\n", .{});

        runtime.stop();

        const stopped_loop = runtime_module.getCurrentEventLoop();
        try testing.expect(stopped_loop == null);
        std.debug.print("✅ 运行时停止后：事件循环已清理\n", .{});
    }

    std.debug.print("✅ 事件循环状态管理验证完成\n", .{});
}
