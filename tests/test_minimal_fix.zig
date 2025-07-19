//! 🔧 最小化事件循环修复验证
//! 只验证事件循环是否被正确设置，不调用await_fn

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "最小化验证：事件循环设置" {
    std.debug.print("\n=== 最小化事件循环验证 ===\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 检查初始状态
    const initial_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("初始事件循环: {?}\n", .{initial_loop});
    try testing.expect(initial_loop == null);
    
    // 2. 创建运行时（不启动）
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();
    
    const before_start_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("创建运行时后事件循环: {?}\n", .{before_start_loop});
    try testing.expect(before_start_loop == null);
    
    // 3. 启动运行时
    std.debug.print("启动运行时...\n", .{});
    try runtime.start();
    
    // 4. 验证事件循环已设置
    const after_start_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("启动后事件循环: {?}\n", .{after_start_loop});
    
    if (after_start_loop == null) {
        std.debug.print("❌ 修复失败：事件循环仍为null\n", .{});
        runtime.stop();
        return error.EventLoopNotSet;
    } else {
        std.debug.print("✅ 修复成功：事件循环已设置\n", .{});
    }
    
    // 5. 停止运行时
    std.debug.print("停止运行时...\n", .{});
    runtime.stop();
    
    const after_stop_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("停止后事件循环: {?}\n", .{after_stop_loop});
    
    std.debug.print("✅ 最小化验证完成\n", .{});
}
