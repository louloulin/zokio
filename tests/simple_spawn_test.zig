//! 🧪 简化的spawn测试
//! 测试最基本的spawn功能

const std = @import("std");
const zokio = @import("zokio");

// 最简单的Future类型
const SimpleTask = struct {
    value: u32,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        return zokio.Poll(Self.Output){ .ready = self.value * 2 };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🧪 简化spawn测试 ===\n", .{});

    // 测试1: 基础spawn功能
    try testBasicSpawn(allocator);

    std.debug.print("\n🎉 === 简化spawn测试完成 ===\n", .{});
}

/// 测试基础spawn功能
fn testBasicSpawn(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试基础spawn功能...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 创建简单任务
    const task = SimpleTask{ .value = 42 };

    std.debug.print("  📋 创建任务: value = {}\n", .{task.value});

    // 使用spawn
    var handle = try runtime.spawn(task);
    std.debug.print("  ✅ spawn调用成功\n", .{});

    // 检查任务是否完成
    std.debug.print("  🔍 检查任务状态: isFinished = {}\n", .{handle.isFinished()});

    // 等待任务完成
    std.debug.print("  ⏳ 等待任务完成...\n", .{});

    // 使用简单的轮询等待
    var attempts: u32 = 0;
    while (!handle.isFinished() and attempts < 1000) {
        std.time.sleep(1000); // 1μs
        attempts += 1;
    }

    std.debug.print("  📊 等待尝试次数: {}\n", .{attempts});
    std.debug.print("  🔍 最终任务状态: isFinished = {}\n", .{handle.isFinished()});

    if (handle.isFinished()) {
        const result = try handle.join();
        std.debug.print("  ✅ 任务完成，结果: {} (期望: 84)\n", .{result});

        if (result == 84) {
            std.debug.print("  🎉 基础spawn测试通过\n", .{});
        } else {
            std.debug.print("  ❌ 结果不正确\n", .{});
        }
    } else {
        std.debug.print("  ❌ 任务未完成\n", .{});

        // 尝试强制join
        const result = handle.join() catch |err| {
            std.debug.print("  ❌ join失败: {}\n", .{err});
            handle.deinit();
            return;
        };
        std.debug.print("  ⚠️ 强制join成功，结果: {}\n", .{result});
    }

    // 清理
    handle.deinit();
    std.debug.print("  ✅ 清理完成\n", .{});
}
