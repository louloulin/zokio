//! 高性能智能分配器测试
//!
//! 修复性能问题，验证优化效果

const std = @import("std");
const zokio = @import("zokio");
const FastSmartAllocator = zokio.memory.FastSmartAllocator;
const FastAllocationStrategy = zokio.memory.FastAllocationStrategy;
const FastSmartAllocatorConfig = zokio.memory.FastSmartAllocatorConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== ⚡ 高性能智能分配器测试 ===\n\n", .{});

    // 测试1: 基础性能验证
    try testBasicPerformance(base_allocator);

    // 测试2: 快速路径优化验证
    try testFastPathOptimization(base_allocator);

    // 测试3: 与标准分配器性能对比
    try testPerformanceComparison(base_allocator);

    // 测试4: 不同策略性能对比
    try testStrategyPerformanceComparison(base_allocator);

    // 测试5: Tokio等效负载性能修复验证
    try testTokioEquivalentLoadFixed(base_allocator);

    std.debug.print("\n=== 🎉 高性能智能分配器测试完成 ===\n", .{});
}

/// 测试基础性能验证
fn testBasicPerformance(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 基础性能验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool,
        .enable_fast_path = true,
        .enable_lightweight_monitoring = true,
    };

    var fast_allocator = try FastSmartAllocator.init(base_allocator, config);
    defer fast_allocator.deinit();

    const iterations = 100_000;
    std.debug.print("执行 {} 次分配操作...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64 + (i % 1024); // 64B-1KB
        const memory = try fast_allocator.alloc(u8, size);
        defer fast_allocator.free(memory);

        // 简单使用内存
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 基础性能结果:\n", .{});
    std.debug.print("  迭代次数: {}\n", .{iterations});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    const stats = fast_allocator.getStats();
    std.debug.print("  快速路径命中率: {d:.1}%\n", .{stats.fast_path_rate * 100.0});
    std.debug.print("  当前策略: {any}\n", .{stats.current_strategy});
}

/// 测试快速路径优化验证
fn testFastPathOptimization(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试2: 快速路径优化验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 200_000;

    // 测试快速路径开启
    std.debug.print("测试快速路径开启...\n", .{});
    const fast_config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool,
        .enable_fast_path = true,
        .enable_lightweight_monitoring = false, // 关闭监控减少开销
    };

    var fast_allocator = try FastSmartAllocator.init(base_allocator, fast_config);
    defer fast_allocator.deinit();

    const fast_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 2048); // 512B-2.5KB
        const memory = try fast_allocator.alloc(u8, size);
        defer fast_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const fast_end = std.time.nanoTimestamp();
    const fast_duration = @as(f64, @floatFromInt(fast_end - fast_start)) / 1_000_000_000.0;
    const fast_ops_per_sec = @as(f64, @floatFromInt(iterations)) / fast_duration;

    // 测试快速路径关闭
    std.debug.print("测试快速路径关闭...\n", .{});
    const slow_config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool,
        .enable_fast_path = false,
        .enable_lightweight_monitoring = false,
    };

    var slow_allocator = try FastSmartAllocator.init(base_allocator, slow_config);
    defer slow_allocator.deinit();

    const slow_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 2048); // 512B-2.5KB
        const memory = try slow_allocator.alloc(u8, size);
        defer slow_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const slow_end = std.time.nanoTimestamp();
    const slow_duration = @as(f64, @floatFromInt(slow_end - slow_start)) / 1_000_000_000.0;
    const slow_ops_per_sec = @as(f64, @floatFromInt(iterations)) / slow_duration;

    // 输出对比结果
    std.debug.print("\n📊 快速路径优化对比:\n", .{});
    std.debug.print("  快速路径开启:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{fast_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{fast_duration});

    std.debug.print("  快速路径关闭:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{slow_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{slow_duration});

    const improvement = fast_ops_per_sec / slow_ops_per_sec;
    std.debug.print("  快速路径提升: {d:.2}x ", .{improvement});
    if (improvement >= 1.5) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement >= 1.2) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("✅ (有所提升)\n", .{});
    } else {
        std.debug.print("⚠️ (性能下降)\n", .{});
    }
}

/// 测试与标准分配器性能对比
fn testPerformanceComparison(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚖️ 测试3: 与标准分配器性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 100_000;

    // 测试标准分配器
    std.debug.print("测试标准分配器...\n", .{});
    const std_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64 + (i % 1024);
        const memory = try base_allocator.alloc(u8, size);
        defer base_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const std_end = std.time.nanoTimestamp();
    const std_duration = @as(f64, @floatFromInt(std_end - std_start)) / 1_000_000_000.0;
    const std_ops_per_sec = @as(f64, @floatFromInt(iterations)) / std_duration;

    // 测试高性能智能分配器
    std.debug.print("测试高性能智能分配器...\n", .{});
    const config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool,
        .enable_fast_path = true,
        .enable_lightweight_monitoring = false,
    };

    var fast_allocator = try FastSmartAllocator.init(base_allocator, config);
    defer fast_allocator.deinit();

    const fast_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64 + (i % 1024);
        const memory = try fast_allocator.alloc(u8, size);
        defer fast_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const fast_end = std.time.nanoTimestamp();
    const fast_duration = @as(f64, @floatFromInt(fast_end - fast_start)) / 1_000_000_000.0;
    const fast_ops_per_sec = @as(f64, @floatFromInt(iterations)) / fast_duration;

    // 输出对比结果
    std.debug.print("\n📊 性能对比结果:\n", .{});
    std.debug.print("  标准分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{std_duration});

    std.debug.print("  高性能智能分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{fast_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{fast_duration});

    const improvement = fast_ops_per_sec / std_ops_per_sec;
    std.debug.print("  性能提升: {d:.2}x ", .{improvement});
    if (improvement >= 10.0) {
        std.debug.print("🌟🌟🌟 (巨大提升)\n", .{});
    } else if (improvement >= 3.0) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement >= 1.5) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("✅ (有所提升)\n", .{});
    } else {
        std.debug.print("⚠️ (性能下降)\n", .{});
    }
}

/// 测试不同策略性能对比
fn testStrategyPerformanceComparison(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🎯 测试4: 不同策略性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 50_000;
    const strategies = [_]FastAllocationStrategy{ .object_pool, .extended_pool, .standard };
    const strategy_names = [_][]const u8{ "对象池", "扩展池", "标准" };

    for (strategies, strategy_names) |strategy, name| {
        std.debug.print("测试 {s} 策略...\n", .{name});

        const config = FastSmartAllocatorConfig{
            .default_strategy = strategy,
            .enable_fast_path = true,
            .enable_lightweight_monitoring = false,
        };

        var allocator = try FastSmartAllocator.init(base_allocator, config);
        defer allocator.deinit();

        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |i| {
            const size = 128 + (i % 512); // 128B-640B
            const memory = try allocator.alloc(u8, size);
            defer allocator.free(memory);
            @memset(memory, @as(u8, @intCast(i % 256)));
        }

        const end_time = std.time.nanoTimestamp();
        const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

        std.debug.print("  {s} 策略: {d:.0} ops/sec\n", .{ name, ops_per_sec });
    }
}

/// 测试Tokio等效负载性能修复验证
fn testTokioEquivalentLoadFixed(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🦀 测试5: Tokio等效负载性能修复验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 50_000; // 与之前保持一致

    // 测试标准分配器（基准）
    std.debug.print("测试标准分配器基准...\n", .{});
    const std_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 1024 + (i % 4096); // 1KB-5KB (Tokio等效)
        const memory = try base_allocator.alloc(u8, size);
        defer base_allocator.free(memory);
        @memset(memory, 0);
    }

    const std_end = std.time.nanoTimestamp();
    const std_duration = @as(f64, @floatFromInt(std_end - std_start)) / 1_000_000_000.0;
    const std_ops_per_sec = @as(f64, @floatFromInt(iterations)) / std_duration;

    // 测试高性能智能分配器
    std.debug.print("测试高性能智能分配器...\n", .{});
    const config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool, // 专门针对1KB-5KB优化
        .enable_fast_path = true,
        .enable_lightweight_monitoring = false,
    };

    var fast_allocator = try FastSmartAllocator.init(base_allocator, config);
    defer fast_allocator.deinit();

    const fast_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 1024 + (i % 4096); // 1KB-5KB (Tokio等效)
        const memory = try fast_allocator.alloc(u8, size);
        defer fast_allocator.free(memory);
        @memset(memory, 0);
    }

    const fast_end = std.time.nanoTimestamp();
    const fast_duration = @as(f64, @floatFromInt(fast_end - fast_start)) / 1_000_000_000.0;
    const fast_ops_per_sec = @as(f64, @floatFromInt(iterations)) / fast_duration;

    // 与Tokio基准对比
    const tokio_baseline = 1_500_000.0;
    const std_vs_tokio = std_ops_per_sec / tokio_baseline;
    const fast_vs_tokio = fast_ops_per_sec / tokio_baseline;
    const improvement = fast_ops_per_sec / std_ops_per_sec;

    std.debug.print("\n📊 Tokio等效负载修复验证结果:\n", .{});
    std.debug.print("  标准分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("    vs Tokio: {d:.2}x\n", .{std_vs_tokio});

    std.debug.print("  高性能智能分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{fast_ops_per_sec});
    std.debug.print("    vs Tokio: {d:.2}x\n", .{fast_vs_tokio});

    std.debug.print("  性能修复效果: {d:.2}x ", .{improvement});
    if (improvement >= 10.0) {
        std.debug.print("🌟🌟🌟 (巨大修复)\n", .{});
    } else if (improvement >= 3.0) {
        std.debug.print("🌟🌟 (显著修复)\n", .{});
    } else if (improvement >= 1.5) {
        std.debug.print("🌟 (明显修复)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("✅ (有所修复)\n", .{});
    } else {
        std.debug.print("⚠️ (仍有问题)\n", .{});
    }

    std.debug.print("\n🎯 修复前后对比:\n", .{});
    std.debug.print("  修复前智能分配器: ~189K ops/sec (vs Tokio: 0.13x)\n", .{});
    std.debug.print("  修复后智能分配器: {d:.0} ops/sec (vs Tokio: {d:.2}x)\n", .{ fast_ops_per_sec, fast_vs_tokio });

    const overall_improvement = fast_ops_per_sec / 189_000.0; // 与修复前对比
    std.debug.print("  总体修复效果: {d:.2}x ", .{overall_improvement});
    if (overall_improvement >= 50.0) {
        std.debug.print("🚀🚀🚀 (革命性提升)\n", .{});
    } else if (overall_improvement >= 10.0) {
        std.debug.print("🚀🚀 (巨大提升)\n", .{});
    } else if (overall_improvement >= 3.0) {
        std.debug.print("🚀 (显著提升)\n", .{});
    } else {
        std.debug.print("📈 (有所提升)\n", .{});
    }
}
