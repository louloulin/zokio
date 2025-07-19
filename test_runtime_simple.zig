//! 简化的运行时测试，用于诊断HighPerformanceRuntime卡住问题

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    std.debug.print("🔧 开始简化运行时测试...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试1: 使用DefaultRuntime而不是HighPerformanceRuntime
    std.debug.print("1. 测试DefaultRuntime.init()...\n", .{});

    var runtime = zokio.runtime.DefaultRuntime.init(allocator) catch |err| {
        std.debug.print("❌ DefaultRuntime初始化失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    std.debug.print("✅ DefaultRuntime初始化成功\n", .{});

    // 测试2: 启动运行时
    std.debug.print("2. 测试runtime.start()...\n", .{});

    runtime.start() catch |err| {
        std.debug.print("❌ 运行时启动失败: {}\n", .{err});
        return;
    };
    defer runtime.stop();

    std.debug.print("✅ 运行时启动成功\n", .{});

    // 测试3: 验证事件循环
    std.debug.print("3. 验证事件循环设置...\n", .{});

    const current_event_loop = zokio.getCurrentEventLoop();
    if (current_event_loop == null) {
        std.debug.print("❌ 没有设置事件循环\n", .{});
        return;
    }

    std.debug.print("✅ 事件循环已设置\n", .{});

    // 测试4: 简单的await_fn测试
    std.debug.print("4. 测试简单的await_fn...\n", .{});

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

    if (result != 42) {
        std.debug.print("❌ await_fn返回错误结果: {}\n", .{result});
        return;
    }

    std.debug.print("✅ await_fn测试成功，结果: {}\n", .{result});

    std.debug.print("🎉 所有简化运行时测试通过！\n", .{});
}
