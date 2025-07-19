//! 🔧 简单的事件循环修复验证
//! 验证await_fn是否能检测到事件循环

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "简单验证事件循环设置" {
    std.debug.print("\n=== 简单事件循环验证 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 检查初始状态
    const initial_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("初始事件循环: {?}\n", .{initial_loop});
    try testing.expect(initial_loop == null);

    // 2. 创建并启动运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 3. 验证事件循环已设置
    const active_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("启动后事件循环: {?}\n", .{active_loop});

    if (active_loop == null) {
        std.debug.print("❌ 事件循环仍为null\n", .{});
        return error.EventLoopNotSet;
    } else {
        std.debug.print("✅ 事件循环已设置\n", .{});
    }

    // 4. 测试简单的await_fn
    const SimpleFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const future = SimpleFuture{ .value = 42 };

    std.debug.print("开始await_fn调用...\n", .{});
    const result = zokio.future.await_fn(future);
    std.debug.print("await_fn结果: {}\n", .{result});

    try testing.expect(result == 42);

    std.debug.print("✅ 简单验证完成\n", .{});
}

test "验证await_fn日志输出" {
    std.debug.print("\n=== await_fn日志验证 ===\n", .{});

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

    // 测试立即完成的Future
    const ImmediateFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            std.debug.print("ImmediateFuture.poll() 被调用，返回值: {}\n", .{self.value});
            return .{ .ready = self.value };
        }
    };

    // 测试pending的Future
    const PendingFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = self;
            _ = ctx;
            std.debug.print("PendingFuture.poll() 被调用，返回pending\n", .{});
            return .pending;
        }
    };

    std.debug.print("测试立即完成的Future:\n", .{});
    const immediate_future = ImmediateFuture{ .value = 100 };
    const result1 = zokio.future.await_fn(immediate_future);
    try testing.expect(result1 == 100);

    std.debug.print("\n测试pending的Future:\n", .{});
    const pending_future = PendingFuture{ .value = 200 };
    const result2 = zokio.future.await_fn(pending_future);
    try testing.expect(result2 == 200);

    std.debug.print("✅ 日志验证完成\n", .{});
}
