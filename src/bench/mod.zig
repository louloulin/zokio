//! 性能基准测试模块
//!
//! 提供全面的性能基准测试框架，用于对比Tokio性能和识别瓶颈

const std = @import("std");
const builtin = @import("builtin");

// 导出基准测试相关模块
pub const benchmark = @import("benchmark.zig");
pub const metrics = @import("metrics.zig");
pub const profiler = @import("profiler.zig");
pub const comparison = @import("comparison.zig");
pub const tokio_runner = @import("tokio_runner.zig");
pub const zokio_runner = @import("zokio_runner.zig");
pub const optimized_zokio_runner = @import("optimized_zokio_runner.zig");

// 导出核心类型
pub const Benchmark = benchmark.Benchmark;
pub const BenchmarkResult = benchmark.BenchmarkResult;
pub const Metrics = metrics.Metrics;
pub const Profiler = profiler.Profiler;
pub const TokioRunner = tokio_runner.TokioRunner;
pub const ZokioRunner = zokio_runner.ZokioRunner;
pub const OptimizedZokioRunner = optimized_zokio_runner.OptimizedZokioRunner;

/// 基准测试配置
pub const BenchConfig = struct {
    /// 预热迭代次数
    warmup_iterations: u32 = 1000,
    /// 测试迭代次数
    test_iterations: u32 = 10000,
    /// 测试持续时间（毫秒）
    duration_ms: u32 = 5000,
    /// 是否启用详细输出
    verbose: bool = false,
    /// 是否启用性能分析
    enable_profiling: bool = false,
    /// 是否与Tokio对比
    compare_with_tokio: bool = false,
    /// CPU亲和性设置
    cpu_affinity: ?u32 = null,
};

/// 基准测试类型
pub const BenchType = enum {
    /// 任务调度性能
    task_scheduling,
    /// I/O操作性能
    io_operations,
    /// 内存分配性能
    memory_allocation,
    /// 网络操作性能
    network_operations,
    /// 文件系统操作性能
    filesystem_operations,
    /// Future组合性能
    future_composition,
    /// 并发性能
    concurrency,
    /// 延迟测试
    latency,
    /// 吞吐量测试
    throughput,
};

/// 性能指标
pub const PerformanceMetrics = struct {
    /// 操作次数
    operations: u64 = 0,
    /// 总耗时（纳秒）
    total_time_ns: u64 = 0,
    /// 最小延迟（纳秒）
    min_latency_ns: u64 = std.math.maxInt(u64),
    /// 最大延迟（纳秒）
    max_latency_ns: u64 = 0,
    /// 平均延迟（纳秒）
    avg_latency_ns: u64 = 0,
    /// 50%分位延迟（纳秒）
    p50_latency_ns: u64 = 0,
    /// 95%分位延迟（纳秒）
    p95_latency_ns: u64 = 0,
    /// 99%分位延迟（纳秒）
    p99_latency_ns: u64 = 0,
    /// 吞吐量（ops/sec）
    throughput_ops_per_sec: f64 = 0.0,
    /// 内存使用量（字节）
    memory_usage_bytes: u64 = 0,
    /// CPU使用率（百分比）
    cpu_usage_percent: f64 = 0.0,

    const Self = @This();

    /// 计算性能指标
    pub fn calculate(self: *Self, latencies: []const u64) void {
        if (latencies.len == 0) return;

        // 计算基本统计
        var total: u64 = 0;
        for (latencies) |latency| {
            total += latency;
            if (latency < self.min_latency_ns) self.min_latency_ns = latency;
            if (latency > self.max_latency_ns) self.max_latency_ns = latency;
        }

        self.operations = latencies.len;
        self.total_time_ns = total;
        self.avg_latency_ns = total / latencies.len;

        // 计算分位数
        var sorted_latencies = std.ArrayList(u64).init(std.heap.page_allocator);
        defer sorted_latencies.deinit();
        sorted_latencies.appendSlice(latencies) catch return;
        std.mem.sort(u64, sorted_latencies.items, {}, std.sort.asc(u64));

        const len = sorted_latencies.items.len;
        self.p50_latency_ns = sorted_latencies.items[len * 50 / 100];
        self.p95_latency_ns = sorted_latencies.items[len * 95 / 100];
        self.p99_latency_ns = sorted_latencies.items[len * 99 / 100];

        // 计算吞吐量
        if (self.total_time_ns > 0) {
            const seconds = @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000_000.0;
            self.throughput_ops_per_sec = @as(f64, @floatFromInt(self.operations)) / seconds;
        }
    }

    /// 打印性能指标
    pub fn print(self: *const Self, name: []const u8) void {
        std.debug.print("\n=== {s} 性能指标 ===\n", .{name});
        std.debug.print("操作次数: {}\n", .{self.operations});
        std.debug.print("总耗时: {d:.2} ms\n", .{@as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0});
        std.debug.print("平均延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.avg_latency_ns)) / 1_000.0});
        std.debug.print("最小延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.min_latency_ns)) / 1_000.0});
        std.debug.print("最大延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.max_latency_ns)) / 1_000.0});
        std.debug.print("P50延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.p50_latency_ns)) / 1_000.0});
        std.debug.print("P95延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.p95_latency_ns)) / 1_000.0});
        std.debug.print("P99延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.p99_latency_ns)) / 1_000.0});
        std.debug.print("吞吐量: {d:.2} ops/sec\n", .{self.throughput_ops_per_sec});
        if (self.memory_usage_bytes > 0) {
            std.debug.print("内存使用: {d:.2} MB\n", .{@as(f64, @floatFromInt(self.memory_usage_bytes)) / (1024.0 * 1024.0)});
        }
        if (self.cpu_usage_percent > 0) {
            std.debug.print("CPU使用率: {d:.2}%\n", .{self.cpu_usage_percent});
        }
    }

    /// 与目标性能对比
    pub fn compareWithTarget(self: *const Self, target: PerformanceMetrics, name: []const u8) void {
        std.debug.print("\n=== {s} 性能对比 ===\n", .{name});
        
        const throughput_ratio = self.throughput_ops_per_sec / target.throughput_ops_per_sec;
        const latency_ratio = @as(f64, @floatFromInt(target.avg_latency_ns)) / @as(f64, @floatFromInt(self.avg_latency_ns));
        
        std.debug.print("吞吐量对比: {d:.2}x (目标: {d:.2}, 实际: {d:.2})\n", .{
            throughput_ratio, target.throughput_ops_per_sec, self.throughput_ops_per_sec
        });
        std.debug.print("延迟对比: {d:.2}x (目标: {d:.2}μs, 实际: {d:.2}μs)\n", .{
            latency_ratio,
            @as(f64, @floatFromInt(target.avg_latency_ns)) / 1_000.0,
            @as(f64, @floatFromInt(self.avg_latency_ns)) / 1_000.0
        });
        
        if (throughput_ratio >= 1.0) {
            std.debug.print("✅ 吞吐量达标\n", .{});
        } else {
            std.debug.print("❌ 吞吐量未达标\n", .{});
        }
        
        if (latency_ratio >= 1.0) {
            std.debug.print("✅ 延迟达标\n", .{});
        } else {
            std.debug.print("❌ 延迟未达标\n", .{});
        }
    }
};

/// 基准测试管理器
pub const BenchmarkManager = struct {
    config: BenchConfig,
    allocator: std.mem.Allocator,
    results: std.ArrayList(BenchmarkResult),

    const Self = @This();

    /// 初始化基准测试管理器
    pub fn init(allocator: std.mem.Allocator, config: BenchConfig) Self {
        return Self{
            .config = config,
            .allocator = allocator,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }

    /// 清理基准测试管理器
    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    /// 运行基准测试
    pub fn runBenchmark(self: *Self, comptime name: []const u8, bench_type: BenchType, benchmark_fn: anytype) !void {
        std.debug.print("运行基准测试: {s}\n", .{name});

        // 设置CPU亲和性
        if (self.config.cpu_affinity) |cpu| {
            try setCpuAffinity(cpu);
        }

        // 预热
        if (self.config.warmup_iterations > 0) {
            std.debug.print("预热中... ({} 次迭代)\n", .{self.config.warmup_iterations});
            var i: u32 = 0;
            while (i < self.config.warmup_iterations) : (i += 1) {
                _ = benchmark_fn();
            }
        }

        // 收集延迟数据
        var latencies = try self.allocator.alloc(u64, self.config.test_iterations);
        defer self.allocator.free(latencies);

        std.debug.print("测试中... ({} 次迭代)\n", .{self.config.test_iterations});
        
        var i: u32 = 0;
        while (i < self.config.test_iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();
            _ = benchmark_fn();
            const end = std.time.nanoTimestamp();
            latencies[i] = @as(u64, @intCast(end - start));
        }

        // 计算性能指标
        var perf_metrics = PerformanceMetrics{};
        perf_metrics.calculate(latencies);

        // 获取内存使用情况
        perf_metrics.memory_usage_bytes = getCurrentMemoryUsage();

        // 创建基准测试结果
        const result = BenchmarkResult{
            .name = name,
            .bench_type = bench_type,
            .metrics = perf_metrics,
            .timestamp = std.time.timestamp(),
        };

        try self.results.append(result);

        // 打印结果
        perf_metrics.print(name);
    }

    /// 生成性能报告
    pub fn generateReport(self: *const Self) !void {
        std.debug.print("\n" ++ "=" ** 50 ++ "\n", .{});
        std.debug.print("Zokio 性能基准测试报告\n", .{});
        std.debug.print("=" ** 50 ++ "\n", .{});
        std.debug.print("测试时间: {}\n", .{std.time.timestamp()});
        std.debug.print("测试配置:\n", .{});
        std.debug.print("  预热迭代: {}\n", .{self.config.warmup_iterations});
        std.debug.print("  测试迭代: {}\n", .{self.config.test_iterations});
        std.debug.print("  测试持续时间: {}ms\n", .{self.config.duration_ms});
        std.debug.print("\n", .{});

        for (self.results.items) |result| {
            result.metrics.print(result.name);
        }

        // 与目标性能对比
        try self.compareWithTargets();
    }

    /// 与目标性能对比
    fn compareWithTargets(self: *const Self) !void {
        // plan2.md中定义的性能目标
        const targets = struct {
            const file_io = PerformanceMetrics{
                .throughput_ops_per_sec = 50000.0,
                .avg_latency_ns = 20000, // 20μs
            };
            const network_io = PerformanceMetrics{
                .throughput_ops_per_sec = 10000.0,
                .avg_latency_ns = 100000, // 100μs
            };
            const task_scheduling = PerformanceMetrics{
                .avg_latency_ns = 10000, // 10μs
                .throughput_ops_per_sec = 100000.0,
            };
            const memory_allocation = PerformanceMetrics{
                .avg_latency_ns = 100, // 100ns
                .throughput_ops_per_sec = 10000000.0,
            };
        };

        for (self.results.items) |result| {
            switch (result.bench_type) {
                .filesystem_operations => {
                    result.metrics.compareWithTarget(targets.file_io, "文件I/O");
                },
                .network_operations => {
                    result.metrics.compareWithTarget(targets.network_io, "网络I/O");
                },
                .task_scheduling => {
                    result.metrics.compareWithTarget(targets.task_scheduling, "任务调度");
                },
                .memory_allocation => {
                    result.metrics.compareWithTarget(targets.memory_allocation, "内存分配");
                },
                else => {},
            }
        }
    }
};

// 辅助函数

/// 设置CPU亲和性
fn setCpuAffinity(cpu: u32) !void {
    if (builtin.os.tag == .linux) {
        // Linux实现
        _ = cpu;
        // TODO: 实现Linux CPU亲和性设置
    } else if (builtin.os.tag == .macos) {
        // macOS实现
        _ = cpu;
        // TODO: 实现macOS CPU亲和性设置
    }
}

/// 获取当前内存使用量
fn getCurrentMemoryUsage() u64 {
    // 简化实现，返回0
    // TODO: 实现真实的内存使用量获取
    return 0;
}

// 测试
test "性能指标计算" {
    const testing = std.testing;

    var perf_metrics = PerformanceMetrics{};
    const latencies = [_]u64{ 1000, 2000, 3000, 4000, 5000 };

    perf_metrics.calculate(&latencies);

    try testing.expectEqual(@as(u64, 5), perf_metrics.operations);
    try testing.expectEqual(@as(u64, 3000), perf_metrics.avg_latency_ns);
    try testing.expectEqual(@as(u64, 1000), perf_metrics.min_latency_ns);
    try testing.expectEqual(@as(u64, 5000), perf_metrics.max_latency_ns);
    try testing.expectEqual(@as(u64, 3000), perf_metrics.p50_latency_ns);
}

test "基准测试管理器" {
    const testing = std.testing;

    const config = BenchConfig{
        .warmup_iterations = 10,
        .test_iterations = 100,
        .verbose = false,
    };

    var manager = BenchmarkManager.init(testing.allocator, config);
    defer manager.deinit();

    // 简单的测试函数
    const testFn = struct {
        fn run() void {
            // 模拟一些工作
            var i: u32 = 0;
            while (i < 1000) : (i += 1) {
                _ = i * i;
            }
        }
    }.run;

    try manager.runBenchmark("测试基准", .task_scheduling, testFn);
    try testing.expectEqual(@as(usize, 1), manager.results.items.len);
}
