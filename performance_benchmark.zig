//! 🚀 Zokio 简化性能基准测试
//!
//! 验证基础性能的简化测试

const std = @import("std");

const ITERATIONS = 10000;

/// 性能测试结果
const BenchmarkResult = struct {
    name: []const u8,
    iterations: u32,
    total_time_ns: i64,
    ops_per_second: f64,
    memory_usage_mb: f64,
};

/// 简化的性能基准测试
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🚀 Zokio 简化性能基准测试开始\n", .{});
    std.debug.print("==================================================\n", .{});

    // 基础内存分配测试
    try benchmarkMemoryAllocation(allocator);

    // 基础计算性能测试
    try benchmarkComputePerformance(allocator);

    // 基础并发测试
    try benchmarkConcurrency(allocator);

    std.debug.print("\n✅ 所有性能基准测试完成！\n", .{});
}

/// 内存分配基准测试
fn benchmarkMemoryAllocation(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧠 内存分配基准测试\n", .{});

    const start_time = std.time.nanoTimestamp();

    // 大量小对象分配测试
    var allocations = std.ArrayList([]u8).init(allocator);
    defer {
        for (allocations.items) |allocation| {
            allocator.free(allocation);
        }
        allocations.deinit();
    }

    for (0..ITERATIONS) |_| {
        const memory = try allocator.alloc(u8, 64);
        try allocations.append(memory);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns: i64 = @intCast(end_time - start_time);

    const result = BenchmarkResult{
        .name = "内存分配",
        .iterations = ITERATIONS,
        .total_time_ns = duration_ns,
        .ops_per_second = @as(f64, @floatFromInt(ITERATIONS)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0),
        .memory_usage_mb = @as(f64, @floatFromInt(ITERATIONS * 64)) / (1024.0 * 1024.0),
    };

    printBenchmarkResult(result);
}

/// 计算性能基准测试
fn benchmarkComputePerformance(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("\n⚡ 计算性能基准测试\n", .{});

    const start_time = std.time.nanoTimestamp();

    var sum: u64 = 0;
    for (0..ITERATIONS) |i| {
        sum += i * i;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns: i64 = @intCast(end_time - start_time);

    const result = BenchmarkResult{
        .name = "计算性能",
        .iterations = ITERATIONS,
        .total_time_ns = duration_ns,
        .ops_per_second = @as(f64, @floatFromInt(ITERATIONS)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0),
        .memory_usage_mb = 0.001, // 估算值
    };

    printBenchmarkResult(result);
    std.debug.print("  ✅ 计算结果: {}\n", .{sum});
}

/// 并发基准测试
fn benchmarkConcurrency(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔄 并发基准测试\n", .{});

    const start_time = std.time.nanoTimestamp();

    // 简单的并发模拟：创建多个线程
    var threads = std.ArrayList(std.Thread).init(allocator);
    defer threads.deinit();

    const thread_count = 4;
    for (0..thread_count) |_| {
        const thread = try std.Thread.spawn(.{}, workerFunction, .{});
        try threads.append(thread);
    }

    // 等待所有线程完成
    for (threads.items) |thread| {
        thread.join();
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns: i64 = @intCast(end_time - start_time);

    const result = BenchmarkResult{
        .name = "并发处理",
        .iterations = thread_count,
        .total_time_ns = duration_ns,
        .ops_per_second = @as(f64, @floatFromInt(thread_count)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0),
        .memory_usage_mb = 0.1, // 估算值
    };

    printBenchmarkResult(result);
}

/// 工作线程函数
fn workerFunction() void {
    var sum: u64 = 0;
    for (0..ITERATIONS / 10) |i| {
        sum += i;
    }
    // 防止编译器优化掉计算
    std.debug.assert(sum > 0);
}

/// 打印基准测试结果
fn printBenchmarkResult(result: BenchmarkResult) void {
    std.debug.print("  📊 {s}:\n", .{result.name});
    std.debug.print("    迭代次数: {}\n", .{result.iterations});
    std.debug.print("    总时间: {d:.2}ms\n", .{@as(f64, @floatFromInt(result.total_time_ns)) / 1_000_000.0});
    std.debug.print("    性能: {d:.0} ops/sec\n", .{result.ops_per_second});
    std.debug.print("    内存使用: {d:.2}MB\n", .{result.memory_usage_mb});
}
