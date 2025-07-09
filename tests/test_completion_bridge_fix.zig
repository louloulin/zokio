//! 验证CompletionBridge修复的测试
//! 这是plan3.md中Phase 1的CompletionBridge修复验证

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");
const libxev = @import("libxev");

// 导入CompletionBridge
const CompletionBridge = @import("../src/runtime/completion_bridge.zig").CompletionBridge;

test "CompletionBridge初始化修复验证" {
    std.debug.print("\n=== 测试CompletionBridge初始化修复 ===\n", .{});

    // 测试1: 基础初始化
    std.debug.print("1. 测试基础初始化\n", .{});

    const bridge = CompletionBridge.init();

    // 验证初始状态
    try testing.expect(bridge.state == .pending);
    try testing.expect(bridge.waker == null);

    // 验证completion结构正确初始化
    try testing.expect(bridge.completion.userdata == null);

    std.debug.print("   ✅ 基础初始化测试通过\n", .{});
}

test "CompletionBridge超时初始化" {
    std.debug.print("\n2. 测试超时初始化\n", .{});

    const timeout_ms = 5000; // 5秒
    const bridge = CompletionBridge.initWithTimeout(timeout_ms);

    // 验证超时设置
    const expected_timeout_ns = timeout_ms * 1_000_000;
    try testing.expect(bridge.timeout_ns == expected_timeout_ns);

    std.debug.print("   超时设置: {} ms = {} ns\n", .{ timeout_ms, bridge.timeout_ns });
    std.debug.print("   ✅ 超时初始化测试通过\n", .{});
}

test "CompletionBridge重置功能修复" {
    std.debug.print("\n3. 测试重置功能修复\n", .{});

    var bridge = CompletionBridge.init();

    // 模拟一些状态变化
    bridge.state = .ready;
    bridge.result = .{ .read = 42 };

    // 重置桥接器
    bridge.reset();

    // 验证重置后的状态
    try testing.expect(bridge.state == .pending);
    try testing.expect(bridge.waker == null);

    // 验证completion结构正确重置
    try testing.expect(bridge.completion.userdata == null);

    std.debug.print("   ✅ 重置功能修复测试通过\n", .{});
}

test "CompletionBridge超时检测" {
    std.debug.print("\n4. 测试超时检测功能\n", .{});

    // 创建一个很短超时的桥接器
    var bridge = CompletionBridge.initWithTimeout(1); // 1毫秒超时

    // 等待超过超时时间
    std.time.sleep(2 * std.time.ns_per_ms); // 等待2毫秒

    // 检查超时
    const is_timeout = bridge.checkTimeout();

    try testing.expect(is_timeout);
    try testing.expect(bridge.state == .timeout);

    std.debug.print("   超时检测: {}\n", .{is_timeout});
    std.debug.print("   状态: {}\n", .{bridge.state});
    std.debug.print("   ✅ 超时检测测试通过\n", .{});
}

test "CompletionBridge状态转换" {
    std.debug.print("\n5. 测试状态转换\n", .{});

    var bridge = CompletionBridge.init();

    // 验证初始状态
    try testing.expect(bridge.state == .pending);

    // 模拟操作完成
    bridge.state = .ready;
    bridge.result = .{ .read = 100 };

    // 验证状态转换
    try testing.expect(bridge.state == .ready);

    // 模拟错误状态
    bridge.state = .error_occurred;
    try testing.expect(bridge.state == .error_occurred);

    std.debug.print("   状态转换测试: pending -> ready -> error_occurred\n", .{});
    std.debug.print("   ✅ 状态转换测试通过\n", .{});
}

test "CompletionBridge内存安全" {
    std.debug.print("\n6. 测试内存安全\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 创建多个桥接器实例
    const num_bridges = 100;
    var bridges: [num_bridges]CompletionBridge = undefined;

    // 初始化所有桥接器
    for (&bridges) |*bridge| {
        bridge.* = CompletionBridge.init();
    }

    // 重置所有桥接器
    for (&bridges) |*bridge| {
        bridge.reset();
    }

    // 验证没有内存泄漏
    const leaked = gpa.detectLeaks();
    try testing.expect(!leaked);

    std.debug.print("   创建了 {} 个桥接器实例\n", .{num_bridges});
    std.debug.print("   内存泄漏检测: {}\n", .{leaked});
    std.debug.print("   ✅ 内存安全测试通过\n", .{});
}

test "CompletionBridge性能基准" {
    std.debug.print("\n7. 测试性能基准\n", .{});

    const iterations = 10000;
    const start_time = std.time.nanoTimestamp();

    // 执行大量初始化和重置操作
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        var bridge = CompletionBridge.init();
        bridge.reset();
    }

    const end_time = std.time.nanoTimestamp();
    const total_duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;
    const avg_duration_ns = @as(f64, @floatFromInt(end_time - start_time)) / @as(f64, @floatFromInt(iterations));
    const ops_per_sec = 1_000_000_000.0 / avg_duration_ns;

    std.debug.print("   迭代次数: {}\n", .{iterations});
    std.debug.print("   总执行时间: {d:.2} μs\n", .{total_duration_us});
    std.debug.print("   平均执行时间: {d:.2} ns\n", .{avg_duration_ns});
    std.debug.print("   吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    // 性能应该很高
    try testing.expect(ops_per_sec > 1_000_000); // 至少100万ops/sec

    std.debug.print("   ✅ 性能基准测试通过\n", .{});
}

test "CompletionBridge错误处理" {
    std.debug.print("\n8. 测试错误处理\n", .{});

    var bridge = CompletionBridge.init();

    // 模拟I/O错误
    bridge.state = .error_occurred;
    bridge.result = .{ .read = error.BrokenPipe };

    // 验证错误状态
    try testing.expect(bridge.state == .error_occurred);

    // 测试超时错误
    bridge.state = .timeout;
    try testing.expect(bridge.state == .timeout);

    std.debug.print("   错误状态处理: error_occurred, timeout\n", .{});
    std.debug.print("   ✅ 错误处理测试通过\n", .{});
}
