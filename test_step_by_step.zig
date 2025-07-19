//! 逐步诊断测试，找出卡住的具体位置

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    std.debug.print("🔧 开始逐步诊断测试...\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 步骤1: 创建运行时
    std.debug.print("步骤1: 创建DefaultRuntime...\n", .{});

    var runtime = zokio.runtime.DefaultRuntime.init(allocator) catch |err| {
        std.debug.print("❌ 步骤1失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    std.debug.print("✅ 步骤1成功\n", .{});

    // 步骤2: 启动运行时 - 这里可能卡住
    std.debug.print("步骤2: 调用runtime.start()...\n", .{});

    runtime.start() catch |err| {
        std.debug.print("❌ 步骤2失败: {}\n", .{err});
        return;
    };
    defer runtime.stop();

    std.debug.print("✅ 步骤2成功\n", .{});

    // 步骤3: 验证事件循环
    std.debug.print("步骤3: 验证事件循环...\n", .{});

    const current_event_loop = zokio.runtime.getCurrentEventLoop();
    if (current_event_loop == null) {
        std.debug.print("❌ 步骤3失败: 事件循环为null\n", .{});
        return;
    }

    std.debug.print("✅ 步骤3成功\n", .{});

    std.debug.print("🎉 所有步骤都成功！\n", .{});
}
