//! Zokio 内存管理模块 V2 性能验证测试
//!
//! P0 优化验证：统一接口零开销重构
//! 目标：从 8.59M ops/sec 提升到 15M+ ops/sec (1.7x 提升)

const std = @import("std");
const zokio = @import("zokio");
const unified_v2 = zokio.memory.unified_v2;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 🚀 Zokio 内存管理 V2 性能验证测试 ===\n\n", .{});

    // 测试1: 超高性能模式验证
    try testUltraFastMode(base_allocator);

    // 测试2: 高性能模式验证
    try testHighPerformanceMode(base_allocator);

    // 测试3: 平衡模式验证
    try testBalancedMode(base_allocator);

    // 测试4: 性能对比验证
    try testPerformanceComparison(base_allocator);

    // 测试5: 目标达成验证
    try testTargetAchievement(base_allocator);

    std.debug.print("\n=== ✅ Zokio 内存管理 V2 性能验证完成 ===\n", .{});
}

/// 测试超高性能模式
fn testUltraFastMode(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 超高性能模式验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = unified_v2.OptimizedConfig{
        .mode = .ultra_fast,
        .small_threshold = 256,
        .large_threshold = 8192,
        .enable_thread_local_cache = true,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
    };

    const ZokioMemoryV2 = unified_v2.ZokioMemoryV2(config);
    var memory_manager = try ZokioMemoryV2.init(base_allocator);
    defer memory_manager.deinit();

    const iterations = 300_000; // 增加测试强度
    std.debug.print("执行 {} 次超高性能模式分配...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 1024); // 512B-1.5KB
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 超高性能模式结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 超高性能模式目标：25M+ ops/sec
    const target_ops_per_sec = 25_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 超高性能目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 超高性能目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试高性能模式
fn testHighPerformanceMode(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔥 测试2: 高性能模式验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = unified_v2.OptimizedConfig{
        .mode = .high_performance,
        .small_threshold = 256,
        .large_threshold = 8192,
        .enable_thread_local_cache = true,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
    };

    const ZokioMemoryV2 = unified_v2.ZokioMemoryV2(config);
    var memory_manager = try ZokioMemoryV2.init(base_allocator);
    defer memory_manager.deinit();

    const iterations = 250_000;
    std.debug.print("执行 {} 次高性能模式分配...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 1024);
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 高性能模式结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 高性能模式目标：20M+ ops/sec
    const target_ops_per_sec = 20_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 高性能目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 高性能目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试平衡模式
fn testBalancedMode(base_allocator: std.mem.Allocator) !void {
    std.debug.print("⚖️ 测试3: 平衡模式验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = unified_v2.OptimizedConfig{
        .mode = .balanced,
        .small_threshold = 256,
        .large_threshold = 8192,
        .enable_thread_local_cache = true,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
    };

    const ZokioMemoryV2 = unified_v2.ZokioMemoryV2(config);
    var memory_manager = try ZokioMemoryV2.init(base_allocator);
    defer memory_manager.deinit();

    const iterations = 200_000;
    std.debug.print("执行 {} 次平衡模式分配...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 1024);
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 平衡模式结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 平衡模式目标：15M+ ops/sec
    const target_ops_per_sec = 15_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 平衡目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 平衡目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试性能对比
fn testPerformanceComparison(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔄 测试4: 性能对比验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 150_000;

    // 测试标准分配器
    std.debug.print("测试标准分配器基准...\n", .{});
    const std_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 1024);
        const memory = try base_allocator.alloc(u8, size);
        defer base_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const std_end = std.time.nanoTimestamp();
    const std_duration = @as(f64, @floatFromInt(std_end - std_start)) / 1_000_000_000.0;
    const std_ops_per_sec = @as(f64, @floatFromInt(iterations)) / std_duration;

    // 测试 V1 统一接口（模拟）
    const v1_unified_ops_per_sec = 8_590_000.0; // V1 的实际性能

    // 测试 V2 超高性能模式
    std.debug.print("测试 V2 超高性能模式...\n", .{});
    const config = unified_v2.OptimizedConfig{
        .mode = .ultra_fast,
        .enable_thread_local_cache = true,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
    };

    const ZokioMemoryV2 = unified_v2.ZokioMemoryV2(config);
    var memory_manager = try ZokioMemoryV2.init(base_allocator);
    defer memory_manager.deinit();

    const v2_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 1024);
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const v2_end = std.time.nanoTimestamp();
    const v2_duration = @as(f64, @floatFromInt(v2_end - v2_start)) / 1_000_000_000.0;
    const v2_ops_per_sec = @as(f64, @floatFromInt(iterations)) / v2_duration;

    std.debug.print("📊 性能对比结果:\n", .{});
    std.debug.print("  标准分配器: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("  V1 统一接口: {d:.0} ops/sec\n", .{v1_unified_ops_per_sec});
    std.debug.print("  V2 超高性能: {d:.0} ops/sec\n", .{v2_ops_per_sec});

    const improvement_vs_v1 = v2_ops_per_sec / v1_unified_ops_per_sec;
    const improvement_vs_std = v2_ops_per_sec / std_ops_per_sec;

    std.debug.print("  V2 vs V1 提升: {d:.1}x ", .{improvement_vs_v1});
    if (improvement_vs_v1 >= 3.0) {
        std.debug.print("🌟🌟🌟 (巨大提升)\n", .{});
    } else if (improvement_vs_v1 >= 2.0) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement_vs_v1 >= 1.5) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else {
        std.debug.print("⚠️ (提升有限)\n", .{});
    }

    std.debug.print("  V2 vs 标准分配器: {d:.1}x ", .{improvement_vs_std});
    if (improvement_vs_std >= 1.0) {
        std.debug.print("✅ (超越标准)\n", .{});
    } else {
        std.debug.print("⚠️ (低于标准)\n", .{});
    }

    std.debug.print("\n", .{});
}

/// 测试目标达成验证
fn testTargetAchievement(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🎯 测试5: P0 目标达成验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const target_ops_per_sec = 15_000_000.0; // P0 阶段目标：15M ops/sec

    // 使用最优配置进行测试
    const config = unified_v2.OptimizedConfig{
        .mode = .ultra_fast, // 最高性能模式
        .small_threshold = 256,
        .large_threshold = 8192,
        .enable_thread_local_cache = true,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
    };

    const ZokioMemoryV2 = unified_v2.ZokioMemoryV2(config);
    var memory_manager = try ZokioMemoryV2.init(base_allocator);
    defer memory_manager.deinit();

    const iterations = 400_000; // 增加测试强度
    std.debug.print("执行 {} 次最优配置分配测试...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 1024);
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 P0 目标达成验证结果:\n", .{});
    std.debug.print("  实际性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  P0 目标: {d:.0} ops/sec\n", .{target_ops_per_sec});
    std.debug.print("  达成率: {d:.1}%\n", .{(ops_per_sec / target_ops_per_sec) * 100});

    if (ops_per_sec >= target_ops_per_sec) {
        const exceed_ratio = ops_per_sec / target_ops_per_sec;
        std.debug.print("  🎉 P0 目标达成: {d:.1}x 超越目标！\n", .{exceed_ratio});

        if (exceed_ratio >= 2.0) {
            std.debug.print("  🚀🚀🚀 性能表现卓越！\n", .{});
        } else if (exceed_ratio >= 1.5) {
            std.debug.print("  🚀🚀 性能表现优秀！\n", .{});
        } else {
            std.debug.print("  🚀 性能表现良好！\n", .{});
        }
    } else {
        const shortfall = target_ops_per_sec / ops_per_sec;
        std.debug.print("  ⚠️ P0 目标未达成: 还需提升 {d:.1}x\n", .{shortfall});

        if (ops_per_sec >= target_ops_per_sec * 0.8) {
            std.debug.print("  📈 接近目标，需要微调\n", .{});
        } else if (ops_per_sec >= target_ops_per_sec * 0.5) {
            std.debug.print("  🔧 需要进一步优化\n", .{});
        } else {
            std.debug.print("  🚨 需要重大改进\n", .{});
        }
    }

    std.debug.print("\n📋 P0 优化总结:\n", .{});
    std.debug.print("  优化前 (V1): 8.59M ops/sec\n", .{});
    std.debug.print("  优化后 (V2): {d:.2}M ops/sec\n", .{ops_per_sec / 1_000_000.0});

    const total_improvement = ops_per_sec / 8_590_000.0;
    std.debug.print("  总体提升: {d:.1}x 🚀\n", .{total_improvement});

    if (total_improvement >= 1.7) {
        std.debug.print("  ✅ P0 优化成功！达到预期 1.7x 提升目标\n", .{});
    } else {
        std.debug.print("  ⚠️ P0 优化需要进一步改进\n", .{});
    }
}
