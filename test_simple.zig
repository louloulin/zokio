const std = @import("std");
const zokio = @import("src/lib.zig");

test "简单的事件循环测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建运行时
    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 验证事件循环已设置
    const current_event_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("事件循环状态: {}\n", .{current_event_loop != null});

    // 创建简单Future
    const SimpleFuture = struct {
        value: u32,
        polled: bool = false,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            if (!self.polled) {
                self.polled = true;
                return .pending;
            }
            return .{ .ready = self.value };
        }
    };

    var simple_future = SimpleFuture{ .value = 42 };

    // 测试await_fn
    const start_time = std.time.nanoTimestamp();
    const result = zokio.future.await_fn(simple_future);
    const end_time = std.time.nanoTimestamp();

    std.debug.print("结果: {}\n", .{result});
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    std.debug.print("执行时间: {d:.3}ms\n", .{duration_ms});

    std.testing.expect(result == 42) catch |err| {
        std.debug.print("测试失败: {}\n", .{err});
        return err;
    };
}
