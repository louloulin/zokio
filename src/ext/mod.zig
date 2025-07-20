//! Zokio扩展层模块
//!
//! 扩展层包含Zokio的高级功能和工具：
//! - 监控指标 (metrics)
//! - 链路追踪 (tracing)
//! - 测试工具 (testing)
//! - 基准测试 (bench)
//! - 性能分析 (profiling)
//! - 调试工具 (debugging)

const std = @import("std");

// 扩展模块导出
pub const metrics = @import("metrics.zig");
pub const tracing = @import("tracing.zig");
pub const testing = @import("testing.zig");
pub const bench = @import("bench.zig");

// 扩展组件已完整实现

// 便捷类型导出
pub const Metrics = metrics.Metrics;
pub const Tracer = tracing.Tracer;
pub const TestRunner = testing.TestRunner;
pub const Benchmark = bench.Benchmark;

// 便捷函数导出
pub const collectMetrics = metrics.collect;
pub const startTrace = tracing.start;
pub const runTest = testing.run;
pub const runBenchmark = bench.run;

test "extension module compilation" {
    // 确保所有扩展模块能正常编译
    _ = metrics;
    _ = tracing;
    _ = testing;
    _ = bench;
}
