//! Tokio压力测试程序
//!
//! 执行真实的Tokio压测并分析性能数据

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Tokio 压力测试与性能分析 ===\n", .{});

    // 检查Rust环境
    const runner = zokio.bench.tokio_runner.TokioRunner.init(allocator, null);
    const has_rust = checkRustEnvironment();

    if (!has_rust) {
        std.debug.print("❌ 未检测到Rust/Cargo环境\n", .{});
        std.debug.print("请安装Rust: https://rustup.rs/\n", .{});
        std.debug.print("使用基于文献的基准数据进行演示...\n", .{});
        try demonstrateWithLiteratureData(allocator, &runner);
        return;
    }

    std.debug.print("✅ 检测到Rust环境，开始真实Tokio压测\n", .{});

    // 执行压力测试
    try runStressTests(allocator, &runner);
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

/// 运行压力测试
fn runStressTests(allocator: std.mem.Allocator, runner: *const zokio.bench.tokio_runner.TokioRunner) !void {
    std.debug.print("\n🚀 开始Tokio压力测试...\n", .{});

    // 测试配置
    const test_configs = [_]TestConfig{
        TestConfig{ .name = "轻负载", .iterations = 1000, .description = "1K任务" },
        TestConfig{ .name = "中负载", .iterations = 10000, .description = "10K任务" },
        TestConfig{ .name = "重负载", .iterations = 50000, .description = "50K任务" },
        TestConfig{ .name = "极限负载", .iterations = 100000, .description = "100K任务" },
    };

    const test_types = [_]TestType{
        TestType{ .bench_type = .task_scheduling, .name = "任务调度", .description = "spawn大量异步任务" },
        TestType{ .bench_type = .io_operations, .name = "I/O操作", .description = "异步I/O操作" },
        TestType{ .bench_type = .memory_allocation, .name = "内存分配", .description = "异步内存分配" },
    };

    var results = std.ArrayList(StressTestResult).init(allocator);
    defer results.deinit();

    // 执行所有测试组合
    for (test_types) |test_type| {
        std.debug.print("\n📊 测试类型: {s} ({s})\n", .{ test_type.name, test_type.description });

        for (test_configs) |config| {
            std.debug.print("  🔄 {s} - {s}...", .{ config.name, config.description });

            const start_time = std.time.nanoTimestamp();
            const metrics = runner.runBenchmark(test_type.bench_type, config.iterations) catch |err| {
                std.debug.print(" ❌ 失败: {}\n", .{err});
                continue;
            };
            const end_time = std.time.nanoTimestamp();

            const result = StressTestResult{
                .test_type = test_type,
                .config = config,
                .metrics = metrics,
                .wall_time_ns = @as(u64, @intCast(end_time - start_time)),
            };

            try results.append(result);

            std.debug.print(" ✅ 完成\n", .{});
            std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{metrics.throughput_ops_per_sec});
            std.debug.print("    平均延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(metrics.avg_latency_ns)) / 1000.0});
        }
    }

    // 分析结果
    try analyzeResults(allocator, results.items);
}

/// 使用文献数据演示
fn demonstrateWithLiteratureData(allocator: std.mem.Allocator, runner: *const zokio.bench.tokio_runner.TokioRunner) !void {
    std.debug.print("\n📚 使用基于文献的Tokio基准数据演示\n", .{});

    const test_types = [_]zokio.bench.BenchType{
        .task_scheduling,
        .io_operations,
        .memory_allocation,
        .network_operations,
        .filesystem_operations,
        .future_composition,
        .concurrency,
    };

    const type_names = [_][]const u8{
        "任务调度",
        "I/O操作",
        "内存分配",
        "网络操作",
        "文件系统操作",
        "Future组合",
        "并发操作",
    };

    var results = std.ArrayList(LiteratureResult).init(allocator);
    defer results.deinit();

    for (test_types, type_names) |test_type, name| {
        const metrics = runner.getLiteratureBaseline(test_type);
        const result = LiteratureResult{
            .name = name,
            .bench_type = test_type,
            .metrics = metrics,
        };
        try results.append(result);

        std.debug.print("\n📈 {s}:\n", .{name});
        std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{metrics.throughput_ops_per_sec});
        std.debug.print("  平均延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(metrics.avg_latency_ns)) / 1000.0});
        std.debug.print("  P95延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(metrics.p95_latency_ns)) / 1000.0});
        std.debug.print("  P99延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(metrics.p99_latency_ns)) / 1000.0});
    }

    // 生成分析报告
    try generateLiteratureAnalysis(results.items);
}

/// 分析压测结果
fn analyzeResults(allocator: std.mem.Allocator, results: []const StressTestResult) !void {
    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("Tokio 压力测试性能分析报告\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});

    // 按测试类型分组分析
    const test_types = [_]zokio.bench.BenchType{ .task_scheduling, .io_operations, .memory_allocation };
    const type_names = [_][]const u8{ "任务调度", "I/O操作", "内存分配" };

    for (test_types, type_names) |test_type, type_name| {
        std.debug.print("\n📊 {s} 性能分析:\n", .{type_name});

        // 收集该类型的所有结果
        var type_results = std.ArrayList(StressTestResult).init(allocator);
        defer type_results.deinit();

        for (results) |result| {
            if (result.test_type.bench_type == test_type) {
                try type_results.append(result);
            }
        }

        if (type_results.items.len == 0) continue;

        // 分析性能趋势
        try analyzePerformanceTrend(type_results.items, type_name);

        // 分析瓶颈
        try analyzeBottlenecks(type_results.items, type_name);
    }

    // 生成综合建议
    try generateRecommendations(results);
}

/// 分析性能趋势
fn analyzePerformanceTrend(results: []const StressTestResult, type_name: []const u8) !void {
    _ = type_name;
    std.debug.print("  📈 性能趋势分析:\n", .{});

    for (results, 0..) |result, i| {
        const load_factor = @as(f64, @floatFromInt(result.config.iterations)) / 1000.0;
        const efficiency = result.metrics.throughput_ops_per_sec / load_factor;

        std.debug.print("    {s}: {d:.0} ops/sec (效率: {d:.0})\n", .{
            result.config.name,
            result.metrics.throughput_ops_per_sec,
            efficiency,
        });

        if (i > 0) {
            const prev_result = results[i - 1];
            const throughput_change = (result.metrics.throughput_ops_per_sec / prev_result.metrics.throughput_ops_per_sec - 1.0) * 100.0;
            const latency_change = (@as(f64, @floatFromInt(result.metrics.avg_latency_ns)) / @as(f64, @floatFromInt(prev_result.metrics.avg_latency_ns)) - 1.0) * 100.0;

            std.debug.print("      vs {s}: 吞吐量 {s}{d:.1}%, 延迟 {s}{d:.1}%\n", .{
                prev_result.config.name,
                if (throughput_change >= 0) "+" else "",
                throughput_change,
                if (latency_change >= 0) "+" else "",
                latency_change,
            });
        }
    }
}

/// 分析性能瓶颈
fn analyzeBottlenecks(results: []const StressTestResult, type_name: []const u8) !void {
    _ = type_name;
    std.debug.print("  🔍 瓶颈分析:\n", .{});

    // 找到性能下降最严重的点
    var max_degradation: f64 = 0;
    var bottleneck_point: ?StressTestResult = null;

    for (results, 1..) |result, i| {
        if (i >= results.len) break;

        const prev_result = results[i - 1];
        const expected_throughput = prev_result.metrics.throughput_ops_per_sec *
            (@as(f64, @floatFromInt(result.config.iterations)) / @as(f64, @floatFromInt(prev_result.config.iterations)));

        const actual_throughput = result.metrics.throughput_ops_per_sec;
        const degradation = (expected_throughput - actual_throughput) / expected_throughput;

        if (degradation > max_degradation) {
            max_degradation = degradation;
            bottleneck_point = result;
        }
    }

    if (bottleneck_point) |bp| {
        std.debug.print("    ⚠️  主要瓶颈出现在: {s}\n", .{bp.config.name});
        std.debug.print("    性能下降: {d:.1}%\n", .{max_degradation * 100.0});

        // 分析可能的原因
        if (bp.metrics.avg_latency_ns > 10000) { // > 10μs
            std.debug.print("    可能原因: 高延迟 ({d:.2} μs)\n", .{@as(f64, @floatFromInt(bp.metrics.avg_latency_ns)) / 1000.0});
        }

        if (bp.config.iterations > 50000) {
            std.debug.print("    可能原因: 高并发负载超过系统容量\n", .{});
        }
    } else {
        std.debug.print("    ✅ 未发现明显瓶颈，性能扩展良好\n", .{});
    }
}

/// 生成优化建议
fn generateRecommendations(results: []const StressTestResult) !void {
    std.debug.print("\n💡 性能优化建议:\n", .{});

    var total_throughput: f64 = 0;
    var total_latency: u64 = 0;
    var high_latency_count: u32 = 0;

    for (results) |result| {
        total_throughput += result.metrics.throughput_ops_per_sec;
        total_latency += result.metrics.avg_latency_ns;

        if (result.metrics.avg_latency_ns > 5000) { // > 5μs
            high_latency_count += 1;
        }
    }

    const avg_throughput = total_throughput / @as(f64, @floatFromInt(results.len));
    const avg_latency = total_latency / results.len;

    std.debug.print("  📊 整体性能概况:\n", .{});
    std.debug.print("    平均吞吐量: {d:.0} ops/sec\n", .{avg_throughput});
    std.debug.print("    平均延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(avg_latency)) / 1000.0});

    std.debug.print("\n  🎯 优化建议:\n", .{});

    if (avg_throughput < 500_000) {
        std.debug.print("    • 吞吐量较低，考虑优化任务调度器\n", .{});
        std.debug.print("    • 检查是否存在锁竞争\n", .{});
    }

    if (avg_latency > 3000) { // > 3μs
        std.debug.print("    • 平均延迟较高，优化热路径代码\n", .{});
        std.debug.print("    • 考虑减少内存分配\n", .{});
    }

    if (high_latency_count > results.len / 2) {
        std.debug.print("    • 多数测试延迟较高，可能需要架构优化\n", .{});
    }

    std.debug.print("    • 建议在生产环境中进行更长时间的压测\n", .{});
    std.debug.print("    • 监控内存使用和GC压力\n", .{});
}

/// 生成文献数据分析
fn generateLiteratureAnalysis(results: []const LiteratureResult) !void {
    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("Tokio 基准性能数据分析\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});

    // 找出最佳和最差性能
    var best_throughput: f64 = 0;
    var worst_latency: u64 = 0;
    var best_type: []const u8 = "";
    var worst_type: []const u8 = "";

    for (results) |result| {
        if (result.metrics.throughput_ops_per_sec > best_throughput) {
            best_throughput = result.metrics.throughput_ops_per_sec;
            best_type = result.name;
        }

        if (result.metrics.avg_latency_ns > worst_latency) {
            worst_latency = result.metrics.avg_latency_ns;
            worst_type = result.name;
        }
    }

    std.debug.print("🏆 最佳吞吐量: {s} ({d:.0} ops/sec)\n", .{ best_type, best_throughput });
    std.debug.print("⚠️  最高延迟: {s} ({d:.2} μs)\n", .{ worst_type, @as(f64, @floatFromInt(worst_latency)) / 1000.0 });

    std.debug.print("\n📋 性能特征总结:\n", .{});
    std.debug.print("  • Tokio在Future组合方面表现最佳\n", .{});
    std.debug.print("  • 文件系统操作延迟相对较高\n", .{});
    std.debug.print("  • 任务调度性能均衡，适合高并发场景\n", .{});
}

// 数据结构定义
const TestConfig = struct {
    name: []const u8,
    iterations: u32,
    description: []const u8,
};

const TestType = struct {
    bench_type: zokio.bench.BenchType,
    name: []const u8,
    description: []const u8,
};

const StressTestResult = struct {
    test_type: TestType,
    config: TestConfig,
    metrics: zokio.bench.PerformanceMetrics,
    wall_time_ns: u64,
};

const LiteratureResult = struct {
    name: []const u8,
    bench_type: zokio.bench.BenchType,
    metrics: zokio.bench.PerformanceMetrics,
};
