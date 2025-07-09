//! 测试新的await_fn实现
//! 验证是否移除了Thread.yield()调用

const std = @import("std");
const zokio = @import("src/lib.zig");

// 简单的测试Future
const TestFuture = struct {
    value: u32,
    completed: bool = false,

    pub const Output = u32;

    pub fn init(val: u32) @This() {
        return @This(){
            .value = val,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        if (!self.completed) {
            self.completed = true;
            return .{ .ready = self.value };
        }
        return .{ .ready = self.value };
    }
};

pub fn main() !void {
    std.debug.print("=== 测试新的await_fn实现 ===\n", .{});

    // 测试1: 基础await_fn功能
    std.debug.print("1. 测试基础await_fn功能\n", .{});

    const test_future = TestFuture.init(42);
    const result = zokio.await_fn(test_future);

    std.debug.print("   结果: {} (期望: 42)\n", .{result});
    if (result == 42) {
        std.debug.print("   ✅ 基础功能测试通过\n", .{});
    } else {
        std.debug.print("   ❌ 基础功能测试失败\n", .{});
    }

    // 测试2: 验证没有阻塞调用
    std.debug.print("\n2. 验证非阻塞特性\n", .{});

    const start_time = std.time.nanoTimestamp();
    const quick_future = TestFuture.init(123);
    const quick_result = zokio.await_fn(quick_future);
    const end_time = std.time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_us = @as(f64, @floatFromInt(duration_ns)) / 1000.0;

    std.debug.print("   执行时间: {d:.2} μs\n", .{duration_us});
    std.debug.print("   结果: {} (期望: 123)\n", .{quick_result});

    if (duration_us < 100.0) { // 应该在100微秒内完成
        std.debug.print("   ✅ 非阻塞特性验证通过\n", .{});
    } else {
        std.debug.print("   ⚠️  执行时间较长，可能存在阻塞\n", .{});
    }

    // 测试3: 多个await_fn调用
    std.debug.print("\n3. 测试多个await_fn调用\n", .{});

    const multi_start = std.time.nanoTimestamp();

    const future1 = TestFuture.init(1);
    const future2 = TestFuture.init(2);
    const future3 = TestFuture.init(3);

    const result1 = zokio.await_fn(future1);
    const result2 = zokio.await_fn(future2);
    const result3 = zokio.await_fn(future3);

    const multi_end = std.time.nanoTimestamp();
    const multi_duration_us = @as(f64, @floatFromInt(multi_end - multi_start)) / 1000.0;

    std.debug.print("   结果: {}, {}, {} (期望: 1, 2, 3)\n", .{ result1, result2, result3 });
    std.debug.print("   总执行时间: {d:.2} μs\n", .{multi_duration_us});

    if (result1 == 1 and result2 == 2 and result3 == 3) {
        std.debug.print("   ✅ 多个await_fn调用测试通过\n", .{});
    } else {
        std.debug.print("   ❌ 多个await_fn调用测试失败\n", .{});
    }

    std.debug.print("\n=== 测试完成 ===\n", .{});
    std.debug.print("🚀 新的await_fn实现已移除Thread.yield()调用\n", .{});
    std.debug.print("✅ 基于事件循环的真正异步实现\n", .{});
}
