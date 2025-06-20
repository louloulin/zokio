const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 调试Runtime初始化问题 ===\n", .{});

    // 测试1: 最简单的DefaultRuntime初始化
    std.debug.print("1. 测试DefaultRuntime初始化...\n", .{});
    {
        var runtime = zokio.DefaultRuntime.init(allocator) catch |err| {
            std.debug.print("❌ DefaultRuntime初始化失败: {}\n", .{err});
            return;
        };
        defer runtime.deinit();
        std.debug.print("✅ DefaultRuntime初始化成功\n", .{});

        // 测试启动
        runtime.start() catch |err| {
            std.debug.print("❌ DefaultRuntime启动失败: {}\n", .{err});
            return;
        };
        std.debug.print("✅ DefaultRuntime启动成功\n", .{});

        runtime.stop();
        std.debug.print("✅ DefaultRuntime停止成功\n", .{});
    }

    std.debug.print("\n=== 调试完成 ===\n", .{});
}
