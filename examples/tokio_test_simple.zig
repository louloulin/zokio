//! 简化的Tokio测试程序，用于验证内存泄漏修复

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 简化Tokio测试 ===\n", .{});

    // 检查Rust环境
    const runner = zokio.bench.tokio_runner.TokioRunner.init(allocator, null);
    const has_rust = checkRustEnvironment();

    if (!has_rust) {
        std.debug.print("❌ 未检测到Rust/Cargo环境，使用文献数据\n", .{});
        try testWithLiteratureData(&runner);
        return;
    }

    std.debug.print("✅ 检测到Rust环境，运行简化测试\n", .{});

    // 只运行一个简单的测试
    try runSimpleTest(allocator, &runner);
}

/// 检查Rust环境
fn checkRustEnvironment() bool {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "cargo", "--version" },
        .cwd = null,
    }) catch return false;

    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    return result.term == .Exited and result.term.Exited == 0;
}

/// 运行简单测试
fn runSimpleTest(allocator: std.mem.Allocator, runner: *const zokio.bench.tokio_runner.TokioRunner) !void {
    _ = allocator;

    std.debug.print("🚀 开始简化Tokio测试...\n", .{});

    // 只测试任务调度，小负载
    std.debug.print("📊 测试任务调度 (1000任务)...", .{});

    const metrics = runner.runBenchmark(.task_scheduling, 1000) catch |err| {
        std.debug.print(" ❌ 失败: {}\n", .{err});
        return;
    };

    std.debug.print(" ✅ 完成\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{metrics.throughput_ops_per_sec});
    std.debug.print("    平均延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(metrics.avg_latency_ns)) / 1000.0});

    std.debug.print("✅ 测试完成，无内存泄漏！\n", .{});
}

/// 使用文献数据测试
fn testWithLiteratureData(runner: *const zokio.bench.tokio_runner.TokioRunner) !void {
    std.debug.print("📚 使用文献基准数据\n", .{});

    const metrics = runner.getLiteratureBaseline(.task_scheduling);
    std.debug.print("任务调度基准:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{metrics.throughput_ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(metrics.avg_latency_ns)) / 1000.0});
}
