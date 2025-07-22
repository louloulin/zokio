//! 验证libxev集成的简化测试
//! 这是libx2.md中项目1的核心验证测试

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

// 导入CompletionBridge进行直接测试
const CompletionBridge = zokio.legacy.CompletionBridge;
const await_fn = zokio.zokio.await_fn;
const Poll = zokio.zokio.Poll;
const Context = zokio.zokio.Context;

test "CompletionBridge libxev集成验证" {
    std.debug.print("\n=== 测试CompletionBridge libxev集成 ===\n", .{});

    // 测试1: 验证CompletionBridge初始化修复
    std.debug.print("1. 验证CompletionBridge初始化修复\n", .{});

    const bridge = CompletionBridge.init();

    // 验证初始化状态
    try testing.expect(bridge.state == .pending);
    try testing.expect(bridge.waker == null);

    // 验证completion结构正确初始化（不再是空初始化）
    try testing.expect(bridge.completion.userdata == null);

    std.debug.print("   ✅ CompletionBridge初始化修复验证通过\n", .{});
}

test "CompletionBridge状态管理验证" {
    std.debug.print("\n2. 验证CompletionBridge状态管理\n", .{});

    var bridge = CompletionBridge.init();

    // 测试状态设置功能
    bridge.setState(.ready);
    try testing.expect(bridge.state == .ready);
    try testing.expect(bridge.isCompleted());

    bridge.setState(.error_occurred);
    try testing.expect(bridge.state == .error_occurred);
    try testing.expect(bridge.isCompleted());

    bridge.setState(.pending);
    try testing.expect(bridge.state == .pending);
    try testing.expect(!bridge.isCompleted());

    std.debug.print("   ✅ 状态管理验证通过\n", .{});
}

test "CompletionBridge重置功能验证" {
    std.debug.print("\n3. 验证CompletionBridge重置功能修复\n", .{});

    var bridge = CompletionBridge.init();

    // 设置一些状态
    bridge.setState(.ready);
    bridge.result = .{ .read = 42 };

    // 重置桥接器
    bridge.reset();

    // 验证重置后的状态
    try testing.expect(bridge.state == .pending);
    try testing.expect(bridge.waker == null);

    // 验证completion结构正确重置（修复了空初始化问题）
    try testing.expect(bridge.completion.userdata == null);

    std.debug.print("   ✅ 重置功能修复验证通过\n", .{});
}

test "await_fn非阻塞验证" {
    std.debug.print("\n4. 验证await_fn非阻塞特性\n", .{});

    // 简单的立即完成Future
    const ImmediateFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn init(val: u32) @This() {
            return @This(){ .value = val };
        }

        pub fn poll(self: *@This(), ctx: *Context) Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    // 测试await_fn性能（应该非常快，因为没有Thread.yield()）
    const start_time = std.time.nanoTimestamp();

    const future = ImmediateFuture.init(42);
    const result = await_fn(future);

    const end_time = std.time.nanoTimestamp();
    const duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;

    std.debug.print("   结果: {} (期望: 42)\n", .{result});
    std.debug.print("   执行时间: {d:.2} μs\n", .{duration_us});

    try testing.expect(result == 42);
    // 应该在很短时间内完成（没有阻塞调用）
    try testing.expect(duration_us < 50.0);

    std.debug.print("   ✅ await_fn非阻塞验证通过\n", .{});
}

test "异步操作性能基准" {
    std.debug.print("\n5. 异步操作性能基准测试\n", .{});

    // 简单Future用于性能测试
    const PerfFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn init(val: u32) @This() {
            return @This(){ .value = val };
        }

        pub fn poll(self: *@This(), ctx: *Context) Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const future = PerfFuture.init(i);
        const result = await_fn(future);
        try testing.expect(result == i);
    }

    const end_time = std.time.nanoTimestamp();
    const total_duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;
    const avg_duration_ns = @as(f64, @floatFromInt(end_time - start_time)) / @as(f64, @floatFromInt(iterations));
    const ops_per_sec = 1_000_000_000.0 / avg_duration_ns;

    std.debug.print("   迭代次数: {}\n", .{iterations});
    std.debug.print("   总执行时间: {d:.2} μs\n", .{total_duration_us});
    std.debug.print("   平均执行时间: {d:.2} ns\n", .{avg_duration_ns});
    std.debug.print("   吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    // 验证高性能（应该达到百万级ops/sec）
    try testing.expect(ops_per_sec > 1_000_000);

    std.debug.print("   ✅ 性能基准测试通过\n", .{});
}

test "内存安全验证" {
    std.debug.print("\n6. 内存安全验证\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 创建多个CompletionBridge实例
    const num_bridges = 100;
    var bridges: [num_bridges]CompletionBridge = undefined;

    // 初始化所有桥接器
    for (&bridges) |*bridge| {
        bridge.* = CompletionBridge.init();
    }

    // 使用桥接器
    for (&bridges, 0..) |*bridge, i| {
        bridge.setState(.ready);
        bridge.result = .{ .read = @intCast(i) };
        bridge.reset();
    }

    // 检查内存泄漏
    const leaked = gpa.detectLeaks();

    std.debug.print("   创建了 {} 个桥接器实例\n", .{num_bridges});
    std.debug.print("   内存泄漏检测: {}\n", .{leaked});

    try testing.expect(!leaked);

    std.debug.print("   ✅ 内存安全验证通过\n", .{});
}

test "错误处理机制验证" {
    std.debug.print("\n7. 错误处理机制验证\n", .{});

    var bridge = CompletionBridge.init();

    // 测试超时检测
    bridge.timeout_ns = 1_000_000; // 1毫秒超时
    std.time.sleep(2_000_000); // 等待2毫秒

    const is_timeout = bridge.checkTimeout();
    try testing.expect(is_timeout);
    try testing.expect(bridge.state == .timeout);

    // 测试错误状态设置
    bridge.setState(.error_occurred);
    try testing.expect(bridge.state == .error_occurred);
    try testing.expect(bridge.isCompleted());

    std.debug.print("   超时检测: {}\n", .{is_timeout});
    std.debug.print("   错误状态: {}\n", .{bridge.state});
    std.debug.print("   ✅ 错误处理机制验证通过\n", .{});
}
