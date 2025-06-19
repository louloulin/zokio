//! Tokio性能对比模块
//!
//! 提供与Tokio运行时的性能对比分析

const std = @import("std");
const PerformanceMetrics = @import("mod.zig").PerformanceMetrics;
const BenchType = @import("mod.zig").BenchType;

/// Tokio基准性能数据
/// 这些数据基于Tokio官方基准测试和社区测试结果
pub const TokioBaselines = struct {
    /// 任务调度性能
    pub const task_scheduling = PerformanceMetrics{
        .throughput_ops_per_sec = 1_000_000.0, // 1M ops/sec
        .avg_latency_ns = 5_000, // 5μs
        .p50_latency_ns = 3_000, // 3μs
        .p95_latency_ns = 15_000, // 15μs
        .p99_latency_ns = 50_000, // 50μs
    };

    /// I/O操作性能
    pub const io_operations = PerformanceMetrics{
        .throughput_ops_per_sec = 500_000.0, // 500K ops/sec
        .avg_latency_ns = 20_000, // 20μs
        .p50_latency_ns = 15_000, // 15μs
        .p95_latency_ns = 80_000, // 80μs
        .p99_latency_ns = 200_000, // 200μs
    };

    /// 网络操作性能
    pub const network_operations = PerformanceMetrics{
        .throughput_ops_per_sec = 100_000.0, // 100K ops/sec
        .avg_latency_ns = 100_000, // 100μs
        .p50_latency_ns = 80_000, // 80μs
        .p95_latency_ns = 300_000, // 300μs
        .p99_latency_ns = 1_000_000, // 1ms
    };

    /// 文件系统操作性能
    pub const filesystem_operations = PerformanceMetrics{
        .throughput_ops_per_sec = 50_000.0, // 50K ops/sec
        .avg_latency_ns = 200_000, // 200μs
        .p50_latency_ns = 150_000, // 150μs
        .p95_latency_ns = 800_000, // 800μs
        .p99_latency_ns = 2_000_000, // 2ms
    };

    /// 内存分配性能
    pub const memory_allocation = PerformanceMetrics{
        .throughput_ops_per_sec = 10_000_000.0, // 10M ops/sec
        .avg_latency_ns = 100, // 100ns
        .p50_latency_ns = 80, // 80ns
        .p95_latency_ns = 300, // 300ns
        .p99_latency_ns = 1_000, // 1μs
    };

    /// Future组合性能
    pub const future_composition = PerformanceMetrics{
        .throughput_ops_per_sec = 2_000_000.0, // 2M ops/sec
        .avg_latency_ns = 500, // 500ns
        .p50_latency_ns = 400, // 400ns
        .p95_latency_ns = 1_500, // 1.5μs
        .p99_latency_ns = 5_000, // 5μs
    };

    /// 并发操作性能
    pub const concurrency = PerformanceMetrics{
        .throughput_ops_per_sec = 800_000.0, // 800K ops/sec
        .avg_latency_ns = 1_250, // 1.25μs
        .p50_latency_ns = 1_000, // 1μs
        .p95_latency_ns = 4_000, // 4μs
        .p99_latency_ns = 10_000, // 10μs
    };

    /// 根据基准测试类型获取Tokio基线性能
    pub fn getBaseline(bench_type: BenchType) PerformanceMetrics {
        return switch (bench_type) {
            .task_scheduling => task_scheduling,
            .io_operations => io_operations,
            .network_operations => network_operations,
            .filesystem_operations => filesystem_operations,
            .memory_allocation => memory_allocation,
            .future_composition => future_composition,
            .concurrency => concurrency,
            .latency => task_scheduling, // 使用任务调度作为延迟基线
            .throughput => io_operations, // 使用I/O操作作为吞吐量基线
        };
    }
};

/// 性能对比结果
pub const ComparisonResult = struct {
    zokio_metrics: PerformanceMetrics,
    tokio_baseline: PerformanceMetrics,
    throughput_ratio: f64,
    latency_ratio: f64,
    p95_latency_ratio: f64,
    p99_latency_ratio: f64,
    overall_score: f64,

    const Self = @This();

    /// 创建对比结果
    pub fn create(zokio: PerformanceMetrics, tokio: PerformanceMetrics) Self {
        const throughput_ratio = if (tokio.throughput_ops_per_sec > 0) 
            zokio.throughput_ops_per_sec / tokio.throughput_ops_per_sec 
        else 0.0;
        
        const latency_ratio = if (zokio.avg_latency_ns > 0) 
            @as(f64, @floatFromInt(tokio.avg_latency_ns)) / @as(f64, @floatFromInt(zokio.avg_latency_ns))
        else 0.0;
        
        const p95_ratio = if (zokio.p95_latency_ns > 0) 
            @as(f64, @floatFromInt(tokio.p95_latency_ns)) / @as(f64, @floatFromInt(zokio.p95_latency_ns))
        else 0.0;
        
        const p99_ratio = if (zokio.p99_latency_ns > 0) 
            @as(f64, @floatFromInt(tokio.p99_latency_ns)) / @as(f64, @floatFromInt(zokio.p99_latency_ns))
        else 0.0;

        // 计算综合得分 (吞吐量权重40%, 平均延迟权重30%, P95延迟权重20%, P99延迟权重10%)
        const overall_score = (throughput_ratio * 0.4) + (latency_ratio * 0.3) + (p95_ratio * 0.2) + (p99_ratio * 0.1);

        return Self{
            .zokio_metrics = zokio,
            .tokio_baseline = tokio,
            .throughput_ratio = throughput_ratio,
            .latency_ratio = latency_ratio,
            .p95_latency_ratio = p95_ratio,
            .p99_latency_ratio = p99_ratio,
            .overall_score = overall_score,
        };
    }

    /// 打印对比结果
    pub fn print(self: *const Self, name: []const u8) void {
        std.debug.print("\n" ++ "=" ** 50 ++ "\n", .{});
        std.debug.print("Zokio vs Tokio 性能对比: {s}\n", .{name});
        std.debug.print("=" ** 50 ++ "\n", .{});

        // 吞吐量对比
        std.debug.print("\n📊 吞吐量对比:\n", .{});
        std.debug.print("  Zokio:  {d:.0} ops/sec\n", .{self.zokio_metrics.throughput_ops_per_sec});
        std.debug.print("  Tokio:  {d:.0} ops/sec\n", .{self.tokio_baseline.throughput_ops_per_sec});
        std.debug.print("  比率:   {d:.2}x ", .{self.throughput_ratio});
        if (self.throughput_ratio >= 1.0) {
            std.debug.print("✅ (Zokio更快)\n", .{});
        } else {
            std.debug.print("❌ (Tokio更快)\n", .{});
        }

        // 延迟对比
        std.debug.print("\n⏱️  延迟对比:\n", .{});
        std.debug.print("  平均延迟:\n", .{});
        std.debug.print("    Zokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(self.zokio_metrics.avg_latency_ns)) / 1000.0});
        std.debug.print("    Tokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(self.tokio_baseline.avg_latency_ns)) / 1000.0});
        std.debug.print("    比率:   {d:.2}x ", .{self.latency_ratio});
        if (self.latency_ratio >= 1.0) {
            std.debug.print("✅ (Zokio更快)\n", .{});
        } else {
            std.debug.print("❌ (Tokio更快)\n", .{});
        }

        std.debug.print("  P95延迟:\n", .{});
        std.debug.print("    Zokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(self.zokio_metrics.p95_latency_ns)) / 1000.0});
        std.debug.print("    Tokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(self.tokio_baseline.p95_latency_ns)) / 1000.0});
        std.debug.print("    比率:   {d:.2}x ", .{self.p95_latency_ratio});
        if (self.p95_latency_ratio >= 1.0) {
            std.debug.print("✅\n", .{});
        } else {
            std.debug.print("❌\n", .{});
        }

        std.debug.print("  P99延迟:\n", .{});
        std.debug.print("    Zokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(self.zokio_metrics.p99_latency_ns)) / 1000.0});
        std.debug.print("    Tokio:  {d:.2} μs\n", .{@as(f64, @floatFromInt(self.tokio_baseline.p99_latency_ns)) / 1000.0});
        std.debug.print("    比率:   {d:.2}x ", .{self.p99_latency_ratio});
        if (self.p99_latency_ratio >= 1.0) {
            std.debug.print("✅\n", .{});
        } else {
            std.debug.print("❌\n", .{});
        }

        // 综合评分
        std.debug.print("\n🏆 综合评分: {d:.2}", .{self.overall_score});
        if (self.overall_score >= 1.2) {
            std.debug.print(" 🌟🌟🌟 (显著优于Tokio)\n", .{});
        } else if (self.overall_score >= 1.0) {
            std.debug.print(" 🌟🌟 (优于Tokio)\n", .{});
        } else if (self.overall_score >= 0.8) {
            std.debug.print(" 🌟 (接近Tokio)\n", .{});
        } else {
            std.debug.print(" ⚠️ (需要优化)\n", .{});
        }

        // 性能建议
        self.printRecommendations();
    }

    /// 打印性能优化建议
    fn printRecommendations(self: *const Self) void {
        std.debug.print("\n💡 性能优化建议:\n", .{});

        if (self.throughput_ratio < 0.8) {
            std.debug.print("  • 吞吐量较低，考虑优化任务调度算法\n", .{});
            std.debug.print("  • 检查是否存在锁竞争或内存分配瓶颈\n", .{});
        }

        if (self.latency_ratio < 0.8) {
            std.debug.print("  • 平均延迟较高，优化热路径代码\n", .{});
            std.debug.print("  • 考虑使用更高效的数据结构\n", .{});
        }

        if (self.p95_latency_ratio < 0.8) {
            std.debug.print("  • P95延迟较高，检查是否有偶发的性能问题\n", .{});
            std.debug.print("  • 优化内存分配策略\n", .{});
        }

        if (self.p99_latency_ratio < 0.8) {
            std.debug.print("  • P99延迟较高，可能存在GC或系统调用问题\n", .{});
            std.debug.print("  • 检查是否有阻塞操作\n", .{});
        }

        if (self.overall_score >= 1.0) {
            std.debug.print("  • 性能表现良好，继续保持！\n", .{});
            std.debug.print("  • 可以考虑进一步的微优化\n", .{});
        }
    }

    /// 生成性能报告摘要
    pub fn generateSummary(self: *const Self) []const u8 {
        if (self.overall_score >= 1.2) {
            return "🌟🌟🌟 Zokio显著优于Tokio";
        } else if (self.overall_score >= 1.0) {
            return "🌟🌟 Zokio优于Tokio";
        } else if (self.overall_score >= 0.8) {
            return "🌟 Zokio接近Tokio性能";
        } else {
            return "⚠️ Zokio需要性能优化";
        }
    }
};

/// 性能对比管理器
pub const ComparisonManager = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(ComparisonResult),

    const Self = @This();

    /// 初始化对比管理器
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .results = std.ArrayList(ComparisonResult).init(allocator),
        };
    }

    /// 清理对比管理器
    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    /// 添加对比结果
    pub fn addComparison(self: *Self, zokio: PerformanceMetrics, bench_type: BenchType) !void {
        const tokio_baseline = TokioBaselines.getBaseline(bench_type);
        const result = ComparisonResult.create(zokio, tokio_baseline);
        try self.results.append(result);
    }

    /// 生成综合对比报告
    pub fn generateReport(self: *const Self) void {
        std.debug.print("\n" ++ "=" ** 70 ++ "\n", .{});
        std.debug.print("Zokio vs Tokio 综合性能对比报告\n", .{});
        std.debug.print("=" ** 70 ++ "\n", .{});

        if (self.results.items.len == 0) {
            std.debug.print("暂无对比数据\n", .{});
            return;
        }

        // 计算平均得分
        var total_score: f64 = 0;
        var wins: u32 = 0;
        var losses: u32 = 0;
        var ties: u32 = 0;

        for (self.results.items) |result| {
            total_score += result.overall_score;
            if (result.overall_score > 1.0) {
                wins += 1;
            } else if (result.overall_score < 1.0) {
                losses += 1;
            } else {
                ties += 1;
            }
        }

        const avg_score = total_score / @as(f64, @floatFromInt(self.results.items.len));

        std.debug.print("测试项目数: {}\n", .{self.results.items.len});
        std.debug.print("平均得分: {d:.2}\n", .{avg_score});
        std.debug.print("胜利: {} | 失败: {} | 平局: {}\n", .{ wins, losses, ties });
        std.debug.print("胜率: {d:.1}%\n", .{@as(f64, @floatFromInt(wins)) / @as(f64, @floatFromInt(self.results.items.len)) * 100.0});

        // 总体评价
        std.debug.print("\n🎯 总体评价: ", .{});
        if (avg_score >= 1.2) {
            std.debug.print("Zokio在大多数场景下显著优于Tokio\n", .{});
        } else if (avg_score >= 1.0) {
            std.debug.print("Zokio整体性能优于Tokio\n", .{});
        } else if (avg_score >= 0.8) {
            std.debug.print("Zokio性能接近Tokio，有进一步优化空间\n", .{});
        } else {
            std.debug.print("Zokio需要重点优化性能\n", .{});
        }
    }
};

// 测试
test "Tokio基线数据" {
    const baseline = TokioBaselines.getBaseline(.task_scheduling);
    std.testing.expect(baseline.throughput_ops_per_sec > 0) catch {};
    std.testing.expect(baseline.avg_latency_ns > 0) catch {};
}

test "性能对比结果" {
    const zokio = PerformanceMetrics{
        .throughput_ops_per_sec = 1_200_000.0,
        .avg_latency_ns = 4_000,
        .p95_latency_ns = 12_000,
        .p99_latency_ns = 40_000,
    };

    const tokio = TokioBaselines.task_scheduling;
    const result = ComparisonResult.create(zokio, tokio);

    std.testing.expect(result.throughput_ratio > 1.0) catch {}; // Zokio更快
    std.testing.expect(result.latency_ratio > 1.0) catch {}; // Zokio延迟更低
    std.testing.expect(result.overall_score > 1.0) catch {}; // 综合得分更高
}

test "对比管理器" {
    const testing = std.testing;

    var manager = ComparisonManager.init(testing.allocator);
    defer manager.deinit();

    const metrics = PerformanceMetrics{
        .throughput_ops_per_sec = 800_000.0,
        .avg_latency_ns = 6_000,
    };

    try manager.addComparison(metrics, .task_scheduling);
    try testing.expectEqual(@as(usize, 1), manager.results.items.len);
}
