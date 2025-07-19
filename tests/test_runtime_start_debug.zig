//! 🔧 逐步诊断DefaultRuntime.start()卡住问题
//! 分步骤验证每个操作

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "逐步诊断DefaultRuntime.start()" {
    std.debug.print("\n=== DefaultRuntime.start()逐步诊断 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 步骤1: 创建运行时
    std.debug.print("步骤1: 创建DefaultRuntime...\n", .{});
    var runtime = zokio.runtime.DefaultRuntime.init(allocator) catch |err| {
        std.debug.print("❌ 步骤1失败: {}\n", .{err});
        return err;
    };
    defer runtime.deinit();
    std.debug.print("✅ 步骤1成功\n", .{});

    // 步骤2: 检查运行状态
    std.debug.print("步骤2: 检查初始运行状态...\n", .{});
    const initial_running = runtime.running.load(.acquire);
    std.debug.print("   初始运行状态: {}\n", .{initial_running});
    try testing.expect(!initial_running);
    std.debug.print("✅ 步骤2成功\n", .{});

    // 步骤3: 检查事件循环状态
    std.debug.print("步骤3: 检查初始事件循环状态...\n", .{});
    const initial_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   初始事件循环: {?}\n", .{initial_loop});
    try testing.expect(initial_loop == null);
    std.debug.print("✅ 步骤3成功\n", .{});

    // 步骤4: 手动测试getOrCreateDefaultEventLoop
    std.debug.print("步骤4: 手动测试getOrCreateDefaultEventLoop...\n", .{});
    const test_loop = zokio.runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ 步骤4失败: {}\n", .{err});
        return err;
    };
    std.debug.print("   测试事件循环: {*}\n", .{test_loop});
    std.debug.print("✅ 步骤4成功\n", .{});

    // 步骤5: 清理测试事件循环
    std.debug.print("步骤5: 清理测试事件循环...\n", .{});
    zokio.runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 步骤5成功\n", .{});

    // 步骤6: 尝试启动运行时（这里可能卡住）
    std.debug.print("步骤6: 尝试启动运行时...\n", .{});
    std.debug.print("   调用runtime.start()...\n", .{});

    // 使用超时机制
    const start_time = std.time.milliTimestamp();
    runtime.start() catch |err| {
        std.debug.print("❌ 步骤6失败: {}\n", .{err});
        return err;
    };
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    std.debug.print("✅ 步骤6成功，耗时: {}ms\n", .{duration});

    // 步骤7: 验证启动后状态
    std.debug.print("步骤7: 验证启动后状态...\n", .{});
    const after_start_running = runtime.running.load(.acquire);
    const after_start_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   启动后运行状态: {}\n", .{after_start_running});
    std.debug.print("   启动后事件循环: {?}\n", .{after_start_loop});

    try testing.expect(after_start_running);
    try testing.expect(after_start_loop != null);
    std.debug.print("✅ 步骤7成功\n", .{});

    // 步骤8: 停止运行时
    std.debug.print("步骤8: 停止运行时...\n", .{});
    runtime.stop();
    const after_stop_running = runtime.running.load(.acquire);
    const after_stop_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   停止后运行状态: {}\n", .{after_stop_running});
    std.debug.print("   停止后事件循环: {?}\n", .{after_stop_loop});
    std.debug.print("✅ 步骤8成功\n", .{});

    std.debug.print("✅ 所有步骤完成，DefaultRuntime.start()工作正常\n", .{});
}

test "测试await_fn在修复后的运行时中的行为" {
    std.debug.print("\n=== await_fn行为测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建并启动运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 验证事件循环已设置
    const event_loop = zokio.runtime.getCurrentEventLoop();
    if (event_loop == null) {
        std.debug.print("❌ 事件循环未设置\n", .{});
        return error.EventLoopNotSet;
    }
    std.debug.print("✅ 事件循环已设置: {*}\n", .{event_loop});

    // 测试简单的Future
    const SimpleFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            std.debug.print("   SimpleFuture.poll() 被调用，值: {}\n", .{self.value});
            return .{ .ready = self.value };
        }
    };

    std.debug.print("测试立即完成的Future:\n", .{});
    const future = SimpleFuture{ .value = 42 };
    const result = zokio.future.await_fn(future);
    std.debug.print("await_fn结果: {}\n", .{result});

    try testing.expect(result == 42);
    std.debug.print("✅ await_fn测试成功\n", .{});
}
