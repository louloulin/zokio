//! 🧪 简化的真实Zokio API测试
//!
//! 测试真实的async_fn、spawn等核心API

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🧪 简化的真实Zokio API测试 ===\n\n", .{});

    // 测试1: 基础async_fn测试
    try testBasicAsyncFn(allocator);

    // 测试2: 基础spawn测试
    try testBasicSpawn(allocator);

    std.debug.print("\n=== ✅ 简化测试完成 ===\n", .{});
}

/// 测试1: 基础async_fn
fn testBasicAsyncFn(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 测试1: 基础async_fn\n", .{});

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
    std.debug.print("  🎉 基础async_fn测试通过\n", .{});
}

/// 测试2: 基础spawn测试
fn testBasicSpawn(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🚀 测试2: 基础spawn测试\n", .{});

    // 创建运行时
    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    try runtime.start();
    defer runtime.stop();

    // 🚀 定义简单的async_fn
    const ComputeTask = zokio.async_fn_with_params(struct {
        fn compute(value: u32) u32 {
            var sum: u32 = 0;
            var i: u32 = 0;
            while (i < value) : (i += 1) {
                sum += i;
            }
            return sum;
        }
    }.compute);

    std.debug.print("  📊 使用spawn创建任务...\n", .{});

    // 创建任务实例
    const task = ComputeTask{ .params = .{ .arg0 = 100 } };

    // 🚀 使用spawn
    var handle = try runtime.spawn(task);

    std.debug.print("  ⏳ 等待任务完成...\n", .{});

    // 等待完成
    const result = try handle.join();

    std.debug.print("  ✅ 任务完成，结果: {}\n", .{result});
    std.debug.print("  🎉 基础spawn测试通过\n", .{});
}
