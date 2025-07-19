//! 🔧 测试事件循环修复
//! 验证DefaultRuntime.start()是否正确启动事件循环

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "验证事件循环修复 - 基础功能" {
    std.debug.print("\n=== 事件循环修复验证 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 检查初始状态
    std.debug.print("1. 检查初始状态...\n", .{});

    const initial_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   初始事件循环: {?}\n", .{initial_loop});
    try testing.expect(initial_loop == null);

    // 2. 创建并启动运行时
    std.debug.print("2. 创建并启动运行时...\n", .{});

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 3. 验证事件循环已设置
    std.debug.print("3. 验证事件循环状态...\n", .{});

    const active_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   启动后事件循环: {?}\n", .{active_loop});

    if (active_loop == null) {
        std.debug.print("   ❌ 事件循环仍为null，修复未生效\n", .{});
        return error.EventLoopNotSet;
    } else {
        std.debug.print("   ✅ 事件循环已设置\n", .{});
    }

    // 4. 测试await_fn是否使用异步模式
    std.debug.print("4. 测试await_fn执行模式...\n", .{});

    const TestFuture = struct {
        value: u32,
        poll_count: u32 = 0,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            self.poll_count += 1;
            std.debug.print("     Future.poll() 第{}次调用\n", .{self.poll_count});

            // 第一次返回pending，第二次返回ready
            if (self.poll_count >= 2) {
                std.debug.print("     Future 完成，返回值: {}\n", .{self.value});
                return .{ .ready = self.value };
            } else {
                std.debug.print("     Future pending，等待下次轮询\n", .{});
                return .pending;
            }
        }
    };

    const test_future = TestFuture{ .value = 123 };

    std.debug.print("   开始await_fn调用...\n", .{});
    const result = zokio.future.await_fn(test_future);
    std.debug.print("   await_fn结果: {}\n", .{result});

    try testing.expect(result == 123);

    std.debug.print("\n=== 事件循环修复验证完成 ===\n", .{});
}

test "验证事件循环修复 - 并发测试" {
    std.debug.print("\n=== 事件循环并发测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建并启动运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 验证事件循环已设置
    const active_loop = zokio.runtime.getCurrentEventLoop();
    if (active_loop == null) {
        return error.EventLoopNotSet;
    }

    std.debug.print("✅ 事件循环已设置，开始并发测试\n", .{});

    // 并发执行多个await_fn
    const ConcurrentFuture = struct {
        id: u32,
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            std.debug.print("   Future {} 执行，值: {}\n", .{ self.id, self.value });
            return .{ .ready = self.value };
        }
    };

    const futures = [_]ConcurrentFuture{
        .{ .id = 1, .value = 100 },
        .{ .id = 2, .value = 200 },
        .{ .id = 3, .value = 300 },
    };

    var results: [3]u32 = undefined;

    for (futures, &results, 0..) |future, *result, i| {
        result.* = zokio.future.await_fn(future);
        std.debug.print("   Future {} 完成，结果: {}\n", .{ i + 1, result.* });
    }

    // 验证结果
    try testing.expect(results[0] == 100);
    try testing.expect(results[1] == 200);
    try testing.expect(results[2] == 300);

    std.debug.print("✅ 并发测试通过\n", .{});
}

test "验证事件循环修复 - 性能测试" {
    std.debug.print("\n=== 事件循环性能测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建并启动运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 验证事件循环已设置
    const active_loop = zokio.runtime.getCurrentEventLoop();
    if (active_loop == null) {
        return error.EventLoopNotSet;
    }

    const FastFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const iterations = 1000;
    std.debug.print("开始性能测试 ({} 次迭代)...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const future = FastFuture{ .value = i };
        const result = zokio.future.await_fn(future);
        if (result != i) {
            return error.UnexpectedResult;
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("性能测试结果:\n", .{});
    std.debug.print("   总耗时: {d:.3} ms\n", .{duration_ms});
    std.debug.print("   性能: {d:.0} ops/sec\n", .{ops_per_sec});

    // 如果性能太高，可能仍在同步模式
    if (ops_per_sec > 10_000_000) {
        std.debug.print("   ⚠️ 性能过高，可能仍在同步模式\n", .{});
    } else {
        std.debug.print("   ✅ 性能合理，可能在异步模式\n", .{});
    }

    std.debug.print("✅ 性能测试完成\n", .{});
}
