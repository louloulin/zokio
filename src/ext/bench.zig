//! Zokio基准测试模块
//!
//! 整合了原bench目录下的所有基准测试功能：
//! - 基准测试框架
//! - 性能对比工具
//! - 指标收集
//! - 运行器实现

const std = @import("std");

// 重新导出原bench模块的功能
pub const benchmark = @import("../bench/benchmark.zig");
pub const comparison = @import("../bench/comparison.zig");
pub const metrics = @import("../bench/metrics.zig");
pub const profiler = @import("../bench/profiler.zig");
pub const zokio_runner = @import("../bench/zokio_runner.zig");
pub const tokio_runner = @import("../bench/tokio_runner.zig");
pub const optimized_zokio_runner = @import("../bench/optimized_zokio_runner.zig");

// 便捷类型导出
pub const Benchmark = benchmark.Benchmark;
pub const BenchmarkResult = benchmark.BenchmarkResult;
pub const ComparisonResult = comparison.ComparisonResult;
pub const BenchMetrics = metrics.BenchMetrics;
pub const Profiler = profiler.Profiler;

// 便捷函数导出
pub const run = benchmark.run;
pub const compare = comparison.compare;
pub const profile = profiler.profile;
pub const runZokioBench = zokio_runner.run;
pub const runTokioBench = tokio_runner.run;
pub const runOptimizedZokioBench = optimized_zokio_runner.run;

/// 运行完整的基准测试套件
pub fn runFullSuite(allocator: std.mem.Allocator) !void {
    std.log.info("开始运行Zokio基准测试套件...", .{});
    
    // 运行Zokio基准测试
    try runZokioBench(allocator);
    
    // 运行优化版本基准测试
    try runOptimizedZokioBench(allocator);
    
    // 运行对比测试
    try compare(allocator);
    
    std.log.info("基准测试套件完成", .{});
}

/// 快速性能检查
pub fn quickCheck(allocator: std.mem.Allocator) !BenchmarkResult {
    return try benchmark.quickBench(allocator);
}

test "bench module compilation" {
    // 确保基准测试模块能正常编译
    _ = benchmark;
    _ = comparison;
    _ = metrics;
    _ = profiler;
}
