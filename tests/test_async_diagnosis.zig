//! 🔍 Zokio 异步机制诊断测试
//! 专门用于诊断await_fn是否真正异步执行

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "诊断await_fn异步执行状态" {
    std.debug.print("\n=== Zokio 异步机制诊断 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 检查运行时初始化
    std.debug.print("1. 检查运行时初始化...\n", .{});

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("   ✅ 运行时初始化成功\n", .{});

    // 2. 检查事件循环状态
    std.debug.print("2. 检查事件循环状态...\n", .{});

    const event_loop_before = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   事件循环 (启动前): {?}\n", .{event_loop_before});

    // 3. 启动运行时
    std.debug.print("3. 启动运行时...\n", .{});

    try runtime.start();
    defer runtime.stop();

    const event_loop_after = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   事件循环 (启动后): {?}\n", .{event_loop_after});

    // 4. 测试await_fn执行模式
    std.debug.print("4. 测试await_fn执行模式...\n", .{});

    const TestFuture = struct {
        value: u32,
        poll_count: u32 = 0,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            self.poll_count += 1;
            std.debug.print("     Future.poll() 调用次数: {}\n", .{self.poll_count});

            if (self.poll_count >= 3) {
                std.debug.print("     Future 完成，返回值: {}\n", .{self.value});
                return .{ .ready = self.value };
            } else {
                std.debug.print("     Future pending，需要等待\n", .{});
                return .pending;
            }
        }
    };

    const test_future = TestFuture{ .value = 42 };

    std.debug.print("   开始await_fn调用...\n", .{});
    const result = zokio.future.await_fn(test_future);
    std.debug.print("   await_fn结果: {}\n", .{result});

    try testing.expect(result == 42);

    // 5. 分析执行模式
    std.debug.print("5. 分析执行模式...\n", .{});

    if (event_loop_after == null) {
        std.debug.print("   ❌ 问题: 事件循环未设置，await_fn使用同步回退模式\n", .{});
        std.debug.print("   🔧 需要修复: 运行时启动时未正确设置事件循环\n", .{});
    } else {
        std.debug.print("   ✅ 事件循环已设置，await_fn应该使用异步模式\n", .{});
    }

    std.debug.print("\n=== 诊断完成 ===\n", .{});
}

test "诊断运行时和事件循环连接" {
    std.debug.print("\n=== 运行时和事件循环连接诊断 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建运行时但不启动
    std.debug.print("1. 创建运行时 (未启动)...\n", .{});

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    const loop1 = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   事件循环 (未启动): {?}\n", .{loop1});

    // 2. 启动运行时
    std.debug.print("2. 启动运行时...\n", .{});

    try runtime.start();

    const loop2 = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   事件循环 (已启动): {?}\n", .{loop2});

    // 3. 手动设置事件循环测试
    std.debug.print("3. 手动设置事件循环测试...\n", .{});

    // 创建一个假的事件循环指针用于测试
    var dummy_loop: u32 = 12345;
    const dummy_ptr = @as(*anyopaque, @ptrCast(&dummy_loop));

    zokio.runtime.setCurrentEventLoop(@ptrCast(@alignCast(dummy_ptr)));

    const loop3 = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   事件循环 (手动设置): {?}\n", .{loop3});

    if (loop3 != null) {
        std.debug.print("   ✅ threadlocal变量工作正常\n", .{});
    } else {
        std.debug.print("   ❌ threadlocal变量有问题\n", .{});
    }

    // 4. 恢复状态
    zokio.runtime.setCurrentEventLoop(null);
    runtime.stop();

    std.debug.print("\n=== 连接诊断完成 ===\n", .{});
}

test "诊断真实异步vs同步性能差异" {
    std.debug.print("\n=== 异步vs同步性能差异诊断 ===\n", .{});

    const TestFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const iterations = 10000;

    // 1. 测试当前模式性能
    std.debug.print("1. 测试当前await_fn性能 ({} 次迭代)...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const future = TestFuture{ .value = i };
        const result = zokio.future.await_fn(future);
        if (result != i) {
            std.debug.print("   ❌ 结果错误: {} != {}\n", .{ result, i });
            return;
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("   总耗时: {d:.3} ms\n", .{duration_ms});
    std.debug.print("   性能: {d:.0} ops/sec\n", .{ops_per_sec});

    // 2. 分析性能特征
    std.debug.print("2. 分析性能特征...\n", .{});

    if (ops_per_sec > 1_000_000) {
        std.debug.print("   📊 高性能 (>1M ops/sec): 可能是同步执行\n", .{});
        std.debug.print("   💡 真正的异步执行通常会有更多开销\n", .{});
    } else {
        std.debug.print("   📊 中等性能 (<1M ops/sec): 可能包含异步开销\n", .{});
    }

    std.debug.print("\n=== 性能诊断完成 ===\n", .{});
}
