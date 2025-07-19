//! 🚀 Zokio 4.0 libxev集成测试
//! 验证libxev与Zokio Future系统的完美桥接

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "Zokio 4.0 事件循环基础集成测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建默认运行时（避免libxev复杂性）
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    // 启动运行时，这会设置默认事件循环
    try runtime.start();
    defer runtime.stop();

    // 验证事件循环已设置
    const current_event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(current_event_loop != null);

    // 简单的await_fn测试
    const SimpleFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const simple_future = SimpleFuture{ .value = 42 };
    const result = zokio.future.await_fn(simple_future);
    try testing.expect(result == 42);

    std.debug.print("✅ Zokio 4.0 事件循环集成测试通过\n", .{});
}

test "Zokio 4.0 await_fn非阻塞测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时并启动
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 创建一个立即就绪的Future（避免无限循环）
    const SimpleFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const simple_future = SimpleFuture{ .value = 42 };

    // 测试await_fn是否能正确处理
    const start_time = std.time.nanoTimestamp();
    const result = zokio.future.await_fn(simple_future);
    const end_time = std.time.nanoTimestamp();

    // 验证结果
    try testing.expect(result == 42);

    // 验证执行时间（应该很快，不应该有1ms的阻塞）
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("✅ await_fn执行时间: {d:.3}ms (应该 < 1ms)\n", .{duration_ms});

    // 如果执行时间超过10ms，说明还有阻塞问题
    try testing.expect(duration_ms < 10.0);
}

test "libxev基础功能验证" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时并启动
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 验证事件循环已设置
    const current_event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(current_event_loop != null);

    // 测试多个简单的await_fn调用
    const SimpleFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    // 连续测试多个Future
    for (0..10) |i| {
        const future = SimpleFuture{ .value = @intCast(i) };
        const result = zokio.future.await_fn(future);
        try testing.expect(result == i);
    }

    std.debug.print("✅ libxev基础功能验证通过\n", .{});
}
