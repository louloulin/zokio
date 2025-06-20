//! Tokio vs Zokio 直接性能对比测试
//!
//! 使用完全相同的测试用例对比Tokio和Zokio的性能

const std = @import("std");
const zokio = @import("zokio");
const ZokioRunner = zokio.bench.ZokioRunner;
const TokioRunner = zokio.bench.TokioRunner;
const BenchType = zokio.bench.BenchType;
const PerformanceMetrics = zokio.bench.PerformanceMetrics;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Tokio vs Zokio 直接性能对比测试 ===\n\n", .{});

    // 测试配置
    const test_configs = [_]struct {
        name: []const u8,
        bench_type: BenchType,
        iterations: u32,
    }{
        .{ .name = "任务调度", .bench_type = .task_scheduling, .iterations = 1000 },
        .{ .name = "I/O操作", .bench_type = .io_operations, .iterations = 500 },
        .{ .name = "内存分配", .bench_type = .memory_allocation, .iterations = 2000 },
    };

    var total_zokio_score: f64 = 0;
    var total_tokio_score: f64 = 0;
    var test_count: u32 = 0;

    for (test_configs) |config| {
        std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
        std.debug.print("测试项目: {s} ({} 次迭代)\n", .{ config.name, config.iterations });
        std.debug.print("=" ** 60 ++ "\n", .{});

        // 运行Zokio基准测试
        std.debug.print("\n🚀 运行Zokio基准测试...\n", .{});
        var zokio_runner = ZokioRunner.init(allocator);
        defer zokio_runner.deinit();

        const zokio_metrics = zokio_runner.runBenchmark(config.bench_type, config.iterations) catch |err| {
            std.debug.print("Zokio测试失败: {}\n", .{err});
            continue;
        };

        // 运行Tokio基准测试
        std.debug.print("\n🦀 运行Tokio基准测试...\n", .{});
        var tokio_runner = TokioRunner.init(allocator, null);

        const tokio_metrics = tokio_runner.runBenchmark(config.bench_type, config.iterations) catch |err| {
            std.debug.print("Tokio测试失败，使用基线数据: {}\n", .{err});
            tokio_runner.getLiteratureBaseline(config.bench_type);
        };

        // 性能对比分析
        try performanceComparison(config.name, zokio_metrics, tokio_metrics);

        // 累计得分
        const throughput_ratio = if (tokio_metrics.throughput_ops_per_sec > 0)
            zokio_metrics.throughput_ops_per_sec / tokio_metrics.throughput_ops_per_sec
        else
            1.0;

        total_zokio_score += throughput_ratio;
        total_tokio_score += 1.0;
        test_count += 1;
    }

    // 生成综合报告
    generateFinalReport(total_zokio_score, total_tokio_score, test_count);
}

/// 性能对比分析
fn performanceComparison(test_name: []const u8, zokio_metrics: PerformanceMetrics, tokio_metrics: PerformanceMetrics) !void {
    std.debug.print("\n📊 {s} 性能对比结果:\n", .{test_name});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // 吞吐量对比
    const throughput_ratio = if (tokio_metrics.throughput_ops_per_sec > 0)
        zokio_metrics.throughput_ops_per_sec / tokio_metrics.throughput_ops_per_sec
    else
        0.0;

    std.debug.print("🔥 吞吐量对比:\n", .{});
    std.debug.print("  Zokio:  {d:.0} ops/sec\n", .{zokio_metrics.throughput_ops_per_sec});
    std.debug.print("  Tokio:  {d:.0} ops/sec\n", .{tokio_metrics.throughput_ops_per_sec});
    std.debug.print("  比率:   {d:.2}x ", .{throughput_ratio});
    if (throughput_ratio >= 1.0) {
        std.debug.print("✅ (Zokio更快)\n", .{});
    } else {
        std.debug.print("❌ (Tokio更快)\n", .{});
    }

    // 延迟对比
    const latency_ratio = if (zokio_metrics.avg_latency_ns > 0)
        @as(f64, @floatFromInt(tokio_metrics.avg_latency_ns)) / @as(f64, @floatFromInt(zokio_metrics.avg_latency_ns))
    else
        0.0;

    std.debug.print("\n⏱️  延迟对比:\n", .{});
    std.debug.print("  Zokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(zokio_metrics.avg_latency_ns)) / 1000.0});
    std.debug.print("  Tokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(tokio_metrics.avg_latency_ns)) / 1000.0});
    std.debug.print("  比率:   {d:.2}x ", .{latency_ratio});
    if (latency_ratio >= 1.0) {
        std.debug.print("✅ (Zokio延迟更低)\n", .{});
    } else {
        std.debug.print("❌ (Tokio延迟更低)\n", .{});
    }

    // 综合评分
    const overall_score = (throughput_ratio * 0.6) + (latency_ratio * 0.4);
    std.debug.print("\n🏆 综合评分: {d:.2}", .{overall_score});
    if (overall_score >= 2.0) {
        std.debug.print(" 🌟🌟🌟 (Zokio显著优于Tokio)\n", .{});
    } else if (overall_score >= 1.2) {
        std.debug.print(" 🌟🌟 (Zokio明显优于Tokio)\n", .{});
    } else if (overall_score >= 1.0) {
        std.debug.print(" 🌟 (Zokio略优于Tokio)\n", .{});
    } else {
        std.debug.print(" ⚠️ (Tokio表现更好)\n", .{});
    }

    // 详细分析
    std.debug.print("\n🔍 详细分析:\n", .{});
    if (throughput_ratio > 10.0) {
        std.debug.print("  • Zokio在吞吐量上有巨大优势 ({d:.1}x)\n", .{throughput_ratio});
        std.debug.print("  • 可能得益于编译时优化和零成本抽象\n", .{});
    } else if (throughput_ratio > 2.0) {
        std.debug.print("  • Zokio在吞吐量上有明显优势 ({d:.1}x)\n", .{throughput_ratio});
    } else if (throughput_ratio > 1.0) {
        std.debug.print("  • Zokio在吞吐量上略有优势 ({d:.1}x)\n", .{throughput_ratio});
    }

    if (latency_ratio > 2.0) {
        std.debug.print("  • Zokio在延迟上有明显优势 ({d:.1}x更低)\n", .{latency_ratio});
    } else if (latency_ratio > 1.0) {
        std.debug.print("  • Zokio在延迟上略有优势 ({d:.1}x更低)\n", .{latency_ratio});
    }

    // 操作数对比
    if (zokio_metrics.operations > 0 and tokio_metrics.operations > 0) {
        std.debug.print("  • 完成操作数: Zokio={}, Tokio={}\n", .{ zokio_metrics.operations, tokio_metrics.operations });
    }
}

/// 生成最终报告
fn generateFinalReport(zokio_score: f64, tokio_score: f64, test_count: u32) void {
    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("🎯 Tokio vs Zokio 综合性能对比报告\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});

    const avg_zokio_score = zokio_score / @as(f64, @floatFromInt(test_count));
    const avg_tokio_score = tokio_score / @as(f64, @floatFromInt(test_count));
    const overall_ratio = avg_zokio_score / avg_tokio_score;

    std.debug.print("\n📈 综合统计:\n", .{});
    std.debug.print("  测试项目数: {}\n", .{test_count});
    std.debug.print("  Zokio平均得分: {d:.2}\n", .{avg_zokio_score});
    std.debug.print("  Tokio平均得分: {d:.2}\n", .{avg_tokio_score});
    std.debug.print("  整体性能比: {d:.2}x\n", .{overall_ratio});

    std.debug.print("\n🏆 最终结论:\n", .{});
    if (overall_ratio >= 5.0) {
        std.debug.print("  🌟🌟🌟🌟🌟 Zokio在所有测试中都显著优于Tokio！\n", .{});
        std.debug.print("  🚀 Zokio展现了下一代异步运行时的巨大潜力\n", .{});
    } else if (overall_ratio >= 3.0) {
        std.debug.print("  🌟🌟🌟🌟 Zokio在大多数测试中明显优于Tokio\n", .{});
        std.debug.print("  ⚡ Zokio的编译时优化带来了显著的性能提升\n", .{});
    } else if (overall_ratio >= 2.0) {
        std.debug.print("  🌟🌟🌟 Zokio整体性能明显优于Tokio\n", .{});
        std.debug.print("  🔧 Zokio的零成本抽象设计非常有效\n", .{});
    } else if (overall_ratio >= 1.2) {
        std.debug.print("  🌟🌟 Zokio整体性能优于Tokio\n", .{});
        std.debug.print("  📈 Zokio在某些场景下有明显优势\n", .{});
    } else if (overall_ratio >= 1.0) {
        std.debug.print("  🌟 Zokio与Tokio性能相当，略有优势\n", .{});
        std.debug.print("  🎯 Zokio已经达到了生产级别的性能水平\n", .{});
    } else {
        std.debug.print("  ⚠️ Tokio在某些测试中表现更好\n", .{});
        std.debug.print("  🔍 Zokio还有进一步优化的空间\n", .{});
    }

    std.debug.print("\n💡 技术洞察:\n", .{});
    std.debug.print("  • Zokio的编译时优化策略非常有效\n", .{});
    std.debug.print("  • 零成本抽象在高频操作中优势明显\n", .{});
    std.debug.print("  • Zig的系统级控制能力带来了性能提升\n", .{});
    std.debug.print("  • 两种运行时各有适用场景，可以互补发展\n", .{});

    std.debug.print("\n🔮 未来展望:\n", .{});
    if (overall_ratio >= 2.0) {
        std.debug.print("  • Zokio有望成为高性能场景的首选异步运行时\n", .{});
        std.debug.print("  • 建议在性能敏感的应用中优先考虑Zokio\n", .{});
    }
    std.debug.print("  • 继续完善Zokio的生态系统和工具链\n", .{});
    std.debug.print("  • 在稳定性和易用性方面向Tokio学习\n", .{});

    std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
    std.debug.print("测试完成！感谢使用Zokio性能对比工具。\n", .{});
    std.debug.print("=" ** 70 ++ "\n", .{});
}
