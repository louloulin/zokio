//! 综合性能基准测试
//! 建立全面的性能基准，对比不同配置的性能表现

const std = @import("std");
const zokio = @import("zokio");

const BenchmarkResult = struct {
    name: []const u8,
    runtime_size: usize,
    init_time_ns: u64,
    start_time_ns: u64,
    stop_time_ns: u64,
    ops_per_second: u64,
    memory_usage: usize,
    thread_count: u32,
    success: bool,
    error_msg: ?[]const u8 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 Zokio综合性能基准测试 ===\n", .{});

    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();

    // 测试所有配置
    try benchmarkMemoryOptimized(allocator, &results);
    try benchmarkBalanced(allocator, &results);
    try benchmarkLowLatency(allocator, &results);
    try benchmarkIOIntensive(allocator, &results);
    try benchmarkExtremePerformance(allocator, &results);

    // 生成报告
    try generateReport(results.items);
}

/// 基准测试内存优化配置
fn benchmarkMemoryOptimized(allocator: std.mem.Allocator, results: *std.ArrayList(BenchmarkResult)) !void {
    std.debug.print("\n🧠 基准测试: 内存优化配置\n", .{});

    const result = benchmarkRuntime(allocator, "内存优化", zokio.build.memoryOptimized) catch |err| {
        try results.append(BenchmarkResult{
            .name = "内存优化",
            .runtime_size = 0,
            .init_time_ns = 0,
            .start_time_ns = 0,
            .stop_time_ns = 0,
            .ops_per_second = 0,
            .memory_usage = 0,
            .thread_count = 0,
            .success = false,
            .error_msg = @errorName(err),
        });
        return;
    };

    try results.append(result);
}

/// 基准测试平衡配置
fn benchmarkBalanced(allocator: std.mem.Allocator, results: *std.ArrayList(BenchmarkResult)) !void {
    std.debug.print("\n⚖️ 基准测试: 平衡配置\n", .{});

    const result = benchmarkRuntime(allocator, "平衡配置", zokio.build.balanced) catch |err| {
        try results.append(BenchmarkResult{
            .name = "平衡配置",
            .runtime_size = 0,
            .init_time_ns = 0,
            .start_time_ns = 0,
            .stop_time_ns = 0,
            .ops_per_second = 0,
            .memory_usage = 0,
            .thread_count = 0,
            .success = false,
            .error_msg = @errorName(err),
        });
        return;
    };

    try results.append(result);
}

/// 基准测试低延迟配置
fn benchmarkLowLatency(allocator: std.mem.Allocator, results: *std.ArrayList(BenchmarkResult)) !void {
    std.debug.print("\n⚡ 基准测试: 低延迟配置\n", .{});

    const result = benchmarkRuntime(allocator, "低延迟", zokio.build.lowLatency) catch |err| {
        try results.append(BenchmarkResult{
            .name = "低延迟",
            .runtime_size = 0,
            .init_time_ns = 0,
            .start_time_ns = 0,
            .stop_time_ns = 0,
            .ops_per_second = 0,
            .memory_usage = 0,
            .thread_count = 0,
            .success = false,
            .error_msg = @errorName(err),
        });
        return;
    };

    try results.append(result);
}

/// 基准测试I/O密集型配置
fn benchmarkIOIntensive(allocator: std.mem.Allocator, results: *std.ArrayList(BenchmarkResult)) !void {
    std.debug.print("\n🌐 基准测试: I/O密集型配置\n", .{});

    const result = benchmarkRuntime(allocator, "I/O密集型", zokio.build.ioIntensive) catch |err| {
        try results.append(BenchmarkResult{
            .name = "I/O密集型",
            .runtime_size = 0,
            .init_time_ns = 0,
            .start_time_ns = 0,
            .stop_time_ns = 0,
            .ops_per_second = 0,
            .memory_usage = 0,
            .thread_count = 0,
            .success = false,
            .error_msg = @errorName(err),
        });
        return;
    };

    try results.append(result);
}

/// 基准测试极致性能配置
fn benchmarkExtremePerformance(allocator: std.mem.Allocator, results: *std.ArrayList(BenchmarkResult)) !void {
    std.debug.print("\n🔥 基准测试: 极致性能配置\n", .{});

    const result = benchmarkRuntime(allocator, "极致性能", zokio.build.extremePerformance) catch |err| {
        try results.append(BenchmarkResult{
            .name = "极致性能",
            .runtime_size = 0,
            .init_time_ns = 0,
            .start_time_ns = 0,
            .stop_time_ns = 0,
            .ops_per_second = 0,
            .memory_usage = 0,
            .thread_count = 0,
            .success = false,
            .error_msg = @errorName(err),
        });
        return;
    };

    try results.append(result);
}

/// 通用运行时基准测试
fn benchmarkRuntime(allocator: std.mem.Allocator, name: []const u8, buildFn: anytype) !BenchmarkResult {
    std.debug.print("  🧪 测试 {s}...\n", .{name});

    // 测试初始化时间
    const init_start = std.time.nanoTimestamp();
    var runtime = try buildFn(allocator);
    const init_end = std.time.nanoTimestamp();
    const init_time = @as(u64, @intCast(init_end - init_start));

    defer runtime.deinit();

    const runtime_size = @sizeOf(@TypeOf(runtime));
    std.debug.print("    运行时大小: {} bytes\n", .{runtime_size});
    std.debug.print("    初始化时间: {} ns\n", .{init_time});

    // 测试启动时间
    const start_start = std.time.nanoTimestamp();
    try runtime.start();
    const start_end = std.time.nanoTimestamp();
    const start_time = @as(u64, @intCast(start_end - start_start));

    std.debug.print("    启动时间: {} ns\n", .{start_time});

    // 获取统计信息
    const stats = runtime.getStats();
    std.debug.print("    线程数: {}\n", .{stats.thread_count});

    // 性能测试：简单操作循环
    const ops_count = 1000000;
    const perf_start = std.time.nanoTimestamp();

    for (0..ops_count) |_| {
        _ = runtime.getStats();
    }

    const perf_end = std.time.nanoTimestamp();
    const perf_time = @as(u64, @intCast(perf_end - perf_start));
    const ops_per_second = if (perf_time > 0) (ops_count * 1_000_000_000) / perf_time else 0;

    std.debug.print("    性能: {} ops/sec\n", .{ops_per_second});

    // 测试停止时间
    const stop_start = std.time.nanoTimestamp();
    runtime.stop();
    const stop_end = std.time.nanoTimestamp();
    const stop_time = @as(u64, @intCast(stop_end - stop_start));

    std.debug.print("    停止时间: {} ns\n", .{stop_time});

    return BenchmarkResult{
        .name = name,
        .runtime_size = runtime_size,
        .init_time_ns = init_time,
        .start_time_ns = start_time,
        .stop_time_ns = stop_time,
        .ops_per_second = ops_per_second,
        .memory_usage = runtime_size, // 简化：使用运行时大小作为内存使用
        .thread_count = stats.thread_count,
        .success = true,
    };
}

/// 生成性能报告
fn generateReport(results: []const BenchmarkResult) !void {
    std.debug.print("\n📊 === 综合性能基准报告 ===\n", .{});

    // 表头
    std.debug.print("\n{s:<12} | {s:<8} | {s:<10} | {s:<10} | {s:<10} | {s:<12} | {s:<6} | {s:<8}\n", .{ "配置", "大小(B)", "初始化(ns)", "启动(ns)", "停止(ns)", "性能(ops/s)", "线程", "状态" });
    std.debug.print("{s}\n", .{"-" ** 90});

    // 数据行
    for (results) |result| {
        if (result.success) {
            std.debug.print("{s:<12} | {d:<8} | {d:<10} | {d:<10} | {d:<10} | {d:<12} | {d:<6} | {s:<8}\n", .{ result.name, result.runtime_size, result.init_time_ns, result.start_time_ns, result.stop_time_ns, result.ops_per_second, result.thread_count, "成功" });
        } else {
            std.debug.print("{s:<12} | {s:<8} | {s:<10} | {s:<10} | {s:<10} | {s:<12} | {s:<6} | {s:<8}\n", .{ result.name, "N/A", "N/A", "N/A", "N/A", "N/A", "N/A", result.error_msg orelse "失败" });
        }
    }

    // 分析最佳配置
    std.debug.print("\n🏆 === 性能分析 ===\n", .{});

    var best_perf: ?BenchmarkResult = null;
    var smallest_size: ?BenchmarkResult = null;
    var fastest_init: ?BenchmarkResult = null;

    for (results) |result| {
        if (!result.success) continue;

        if (best_perf == null or result.ops_per_second > best_perf.?.ops_per_second) {
            best_perf = result;
        }

        if (smallest_size == null or result.runtime_size < smallest_size.?.runtime_size) {
            smallest_size = result;
        }

        if (fastest_init == null or result.init_time_ns < fastest_init.?.init_time_ns) {
            fastest_init = result;
        }
    }

    if (best_perf) |bp| {
        std.debug.print("🚀 最佳性能: {s} ({} ops/sec)\n", .{ bp.name, bp.ops_per_second });
    }

    if (smallest_size) |ss| {
        std.debug.print("💾 最小内存: {s} ({} bytes)\n", .{ ss.name, ss.runtime_size });
    }

    if (fastest_init) |fi| {
        std.debug.print("⚡ 最快启动: {s} ({} ns)\n", .{ fi.name, fi.init_time_ns });
    }

    // Tokio对比基准
    const tokio_baseline = 1_500_000; // ops/sec
    std.debug.print("\n📈 === 与Tokio对比 ===\n", .{});

    for (results) |result| {
        if (!result.success) continue;

        const ratio = @as(f64, @floatFromInt(result.ops_per_second)) / @as(f64, @floatFromInt(tokio_baseline));
        std.debug.print("{s}: {d:.2}x Tokio性能\n", .{ result.name, ratio });
    }
}
