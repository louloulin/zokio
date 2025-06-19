//! 统一接口性能修复验证测试
//!
//! 专门验证统一接口从4.33M ops/sec提升到15M ops/sec的修复效果

const std = @import("std");
const zokio = @import("zokio");
const ZokioMemory = zokio.memory.ZokioMemory;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 🚀 统一接口性能修复验证测试 ===\n\n", .{});

    // 测试1: 高性能模式验证
    try testHighPerformanceMode(base_allocator);

    // 测试2: 平衡模式验证
    try testBalancedMode(base_allocator);

    // 测试3: 监控模式验证
    try testMonitoringMode(base_allocator);

    // 测试4: 性能对比验证
    try testPerformanceComparison(base_allocator);

    // 测试5: 目标达成验证
    try testTargetAchievement(base_allocator);

    std.debug.print("\n=== ✅ 统一接口性能修复验证完成 ===\n", .{});
}

/// 测试高性能模式
fn testHighPerformanceMode(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 高性能模式验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .high_performance, // 🔥 零开销模式
        .enable_monitoring = false,
        .enable_fast_path = true,
        .default_strategy = .auto,
        .small_threshold = 256,
        .large_threshold = 8192,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const iterations = 200_000; // 增加测试强度
    std.debug.print("执行 {} 次高性能模式分配...\n", .{iterations});

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
    std.debug.print("⚖️ 测试2: 平衡模式验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .balanced, // ⚖️ 轻量级监控
        .enable_monitoring = true,
        .enable_fast_path = true,
        .default_strategy = .auto,
        .small_threshold = 256,
        .large_threshold = 8192,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const iterations = 150_000;
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

    const stats = memory_manager.getStats();

    std.debug.print("📊 平衡模式结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});
    std.debug.print("  总分配次数: {}\n", .{stats.total_allocations});
    std.debug.print("  当前内存使用: {d:.2} MB\n", .{@as(f64, @floatFromInt(stats.current_memory_usage)) / (1024 * 1024)});

    // 平衡模式目标：15M+ ops/sec
    const target_ops_per_sec = 15_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 平衡目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 平衡目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试监控模式
fn testMonitoringMode(base_allocator: std.mem.Allocator) !void {
    std.debug.print("📊 测试3: 监控模式验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .monitoring, // 📊 完整监控
        .enable_monitoring = true,
        .enable_fast_path = true,
        .default_strategy = .auto,
        .small_threshold = 256,
        .large_threshold = 8192,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const iterations = 100_000;
    std.debug.print("执行 {} 次监控模式分配...\n", .{iterations});

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

    const stats = memory_manager.getStats();
    const distribution = stats.getAllocatorDistribution();

    std.debug.print("📊 监控模式结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});
    std.debug.print("  平均分配时间: {} ns\n", .{stats.average_allocation_time});
    std.debug.print("  缓存命中率: {d:.1}%\n", .{stats.cache_hit_rate * 100});
    std.debug.print("  分配器分布:\n", .{});
    std.debug.print("    Smart: {d:.1}%\n", .{distribution.smart * 100});
    std.debug.print("    Extended: {d:.1}%\n", .{distribution.extended * 100});
    std.debug.print("    Optimized: {d:.1}%\n", .{distribution.optimized * 100});

    // 监控模式目标：5M+ ops/sec（由于监控开销）
    const target_ops_per_sec = 5_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 监控目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 监控目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试性能对比
fn testPerformanceComparison(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔄 测试4: 性能对比验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 100_000;

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

    // 测试修复前的统一接口（模拟）
    const old_unified_ops_per_sec = 4_330_000.0; // 修复前的性能

    // 测试修复后的统一接口
    std.debug.print("测试修复后的统一接口...\n", .{});
    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .balanced,
        .enable_monitoring = true,
        .default_strategy = .auto,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const new_start = std.time.nanoTimestamp();
    
    for (0..iterations) |i| {
        const size = 512 + (i % 1024);
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }
    
    const new_end = std.time.nanoTimestamp();
    const new_duration = @as(f64, @floatFromInt(new_end - new_start)) / 1_000_000_000.0;
    const new_ops_per_sec = @as(f64, @floatFromInt(iterations)) / new_duration;

    std.debug.print("📊 性能对比结果:\n", .{});
    std.debug.print("  标准分配器: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("  修复前统一接口: {d:.0} ops/sec\n", .{old_unified_ops_per_sec});
    std.debug.print("  修复后统一接口: {d:.0} ops/sec\n", .{new_ops_per_sec});
    
    const improvement_vs_old = new_ops_per_sec / old_unified_ops_per_sec;
    const improvement_vs_std = new_ops_per_sec / std_ops_per_sec;
    
    std.debug.print("  修复效果: {d:.1}x ", .{improvement_vs_old});
    if (improvement_vs_old >= 3.0) {
        std.debug.print("🌟🌟🌟 (巨大提升)\n", .{});
    } else if (improvement_vs_old >= 2.0) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement_vs_old >= 1.5) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else {
        std.debug.print("⚠️ (提升有限)\n", .{});
    }
    
    std.debug.print("  vs 标准分配器: {d:.1}x ", .{improvement_vs_std});
    if (improvement_vs_std >= 1.0) {
        std.debug.print("✅ (超越标准)\n", .{});
    } else {
        std.debug.print("⚠️ (低于标准)\n", .{});
    }

    std.debug.print("\n", .{});
}

/// 测试目标达成验证
fn testTargetAchievement(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🎯 测试5: 目标达成验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const target_ops_per_sec = 15_000_000.0; // 15M ops/sec目标
    
    // 使用最优配置进行测试
    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .high_performance, // 最高性能模式
        .enable_monitoring = false, // 关闭监控以获得最大性能
        .enable_fast_path = true,
        .default_strategy = .auto,
        .small_threshold = 256,
        .large_threshold = 8192,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const iterations = 300_000; // 增加测试强度
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

    std.debug.print("📊 目标达成验证结果:\n", .{});
    std.debug.print("  实际性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  目标性能: {d:.0} ops/sec\n", .{target_ops_per_sec});
    std.debug.print("  达成率: {d:.1}%\n", .{(ops_per_sec / target_ops_per_sec) * 100});
    
    if (ops_per_sec >= target_ops_per_sec) {
        const exceed_ratio = ops_per_sec / target_ops_per_sec;
        std.debug.print("  🎉 目标达成: {d:.1}x 超越目标！\n", .{exceed_ratio});
        
        if (exceed_ratio >= 2.0) {
            std.debug.print("  🚀🚀🚀 性能表现卓越！\n", .{});
        } else if (exceed_ratio >= 1.5) {
            std.debug.print("  🚀🚀 性能表现优秀！\n", .{});
        } else {
            std.debug.print("  🚀 性能表现良好！\n", .{});
        }
    } else {
        const shortfall = target_ops_per_sec / ops_per_sec;
        std.debug.print("  ⚠️ 目标未达成: 还需提升 {d:.1}x\n", .{shortfall});
        
        if (ops_per_sec >= target_ops_per_sec * 0.8) {
            std.debug.print("  📈 接近目标，需要微调\n", .{});
        } else if (ops_per_sec >= target_ops_per_sec * 0.5) {
            std.debug.print("  🔧 需要进一步优化\n", .{});
        } else {
            std.debug.print("  🚨 需要重大改进\n", .{});
        }
    }

    std.debug.print("\n📋 修复总结:\n", .{});
    std.debug.print("  修复前: 4.33M ops/sec (0.3x 低于目标)\n", .{});
    std.debug.print("  修复后: {d:.2}M ops/sec ({d:.1}x 相对目标)\n", .{
        ops_per_sec / 1_000_000.0, 
        ops_per_sec / target_ops_per_sec
    });
    
    const total_improvement = ops_per_sec / 4_330_000.0;
    std.debug.print("  总体提升: {d:.1}x 🚀\n", .{total_improvement});
}
