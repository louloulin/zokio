//! 🧪 最简化的spawn测试
//!
//! 测试最基本的spawn功能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🧪 最简化的spawn测试 ===\n\n", .{});

    // 测试1: 只测试运行时创建
    try testRuntimeCreation(allocator);

    // 测试2: 只测试blockOn
    try testBlockOn(allocator);

    std.debug.print("\n=== ✅ 最简化测试完成 ===\n", .{});
}

/// 测试1: 运行时创建
fn testRuntimeCreation(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 测试1: 运行时创建\n", .{});

    // 创建运行时
    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("  ✅ 运行时创建成功\n", .{});

    try runtime.start();
    std.debug.print("  ✅ 运行时启动成功\n", .{});

    runtime.stop();
    std.debug.print("  ✅ 运行时停止成功\n", .{});

    std.debug.print("  🎉 运行时创建测试通过\n", .{});
}

/// 测试2: blockOn
fn testBlockOn(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔧 测试2: blockOn测试\n", .{});

    // 创建运行时
    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    try runtime.start();
    defer runtime.stop();

    // 🚀 定义简单的async_fn
    const SimpleTask = zokio.async_fn_with_params(struct {
        fn compute(value: u32) u32 {
            return value * 2;
        }
    }.compute);

    std.debug.print("  📊 创建async_fn任务...\n", .{});

    // 创建任务实例
    const task = SimpleTask{ .params = .{ .arg0 = 21 } };

    std.debug.print("  ⏳ 使用blockOn执行任务...\n", .{});

    // 使用blockOn执行
    const result = try runtime.blockOn(task);

    std.debug.print("  ✅ 任务完成，结果: {}\n", .{result});
    
    if (result == 42) {
        std.debug.print("  🎉 blockOn测试通过\n", .{});
    } else {
        std.debug.print("  ❌ blockOn测试失败，期望42，得到{}\n", .{result});
    }
}
