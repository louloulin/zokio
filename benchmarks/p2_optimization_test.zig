//! P2阶段性能优化验证测试
//!
//! 专门测试P2阶段的性能优化效果

const std = @import("std");
const zokio = @import("zokio");
const FastSmartAllocator = zokio.memory.FastSmartAllocator;
const FastSmartAllocatorConfig = zokio.memory.FastSmartAllocatorConfig;
const ExtendedAllocator = zokio.memory.ExtendedAllocator;
const ZokioMemory = zokio.memory.ZokioMemory;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 🚀 P2阶段性能优化验证测试 ===\n\n", .{});

    // 测试1: ExtendedAllocator性能保持
    try testExtendedAllocatorPerformance(base_allocator);

    // 测试2: FastSmartAllocator性能提升
    try testFastSmartAllocatorPerformance(base_allocator);

    // 测试3: 统一接口性能验证
    try testUnifiedInterfacePerformance(base_allocator);

    // 测试4: P2阶段目标达成验证
    try testP2TargetAchievement(base_allocator);

    std.debug.print("\n=== ✅ P2阶段性能优化验证完成 ===\n", .{});
}

/// 测试ExtendedAllocator性能保持
fn testExtendedAllocatorPerformance(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🎯 测试1: ExtendedAllocator性能保持验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var extended_allocator = try ExtendedAllocator.init(base_allocator);
    defer extended_allocator.deinit();

    const iterations = 100_000;
    std.debug.print("执行 {} 次ExtendedAllocator分配...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 2048); // 512B-2.5KB
        const memory = try extended_allocator.alloc(size);
        defer extended_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 ExtendedAllocator性能结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 性能目标验证 (保持23M+ ops/sec)
    const target_ops_per_sec = 23_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 性能目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 性能目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试FastSmartAllocator性能提升
fn testFastSmartAllocatorPerformance(base_allocator: std.mem.Allocator) !void {
    std.debug.print("⚡ 测试2: FastSmartAllocator性能提升验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // 测试extended_pool策略（最优策略）
    const config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool,
        .enable_fast_path = true,
        .enable_lightweight_monitoring = false,
    };

    var fast_allocator = try FastSmartAllocator.init(base_allocator, config);
    defer fast_allocator.deinit();

    const iterations = 100_000;
    std.debug.print("执行 {} 次FastSmartAllocator分配...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 2048); // 512B-2.5KB
        const memory = try fast_allocator.alloc(u8, size);
        defer fast_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 FastSmartAllocator性能结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    const stats = fast_allocator.getStats();
    std.debug.print("  快速路径命中率: {d:.1}%\n", .{stats.fast_path_rate * 100});

    // 性能目标验证 (保持10M+ ops/sec)
    const target_ops_per_sec = 10_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 性能目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 性能目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试统一接口性能验证
fn testUnifiedInterfacePerformance(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🧠 测试3: 统一接口性能验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .high_performance,
        .enable_fast_path = true,
        .enable_monitoring = false, // 关闭监控以获得最大性能
        .default_strategy = .auto,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const iterations = 100_000;
    std.debug.print("执行 {} 次统一接口分配...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 2048); // 512B-2.5KB
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 统一接口性能结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 性能目标验证 (保持5M+ ops/sec)
    const target_ops_per_sec = 5_000_000.0;
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  ✅ 性能目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 性能目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("\n", .{});
}

/// 测试P2阶段目标达成验证
fn testP2TargetAchievement(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🎯 测试4: P2阶段目标达成验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // P2阶段性能目标
    const p2_targets = struct {
        const fast_smart: f64 = 10_000_000.0; // 10M+ ops/sec
        const extended: f64 = 25_000_000.0; // 25M+ ops/sec
        const unified_avg: f64 = 15_000_000.0; // 15M+ ops/sec
    };

    std.debug.print("P2阶段性能目标验证:\n", .{});

    // 测试FastSmartAllocator
    const fast_config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool,
        .enable_fast_path = true,
        .enable_lightweight_monitoring = false,
    };

    var fast_allocator = try FastSmartAllocator.init(base_allocator, fast_config);
    defer fast_allocator.deinit();

    const fast_start = std.time.nanoTimestamp();
    for (0..50_000) |i| {
        const size = 1024 + (i % 2048);
        const memory = try fast_allocator.alloc(u8, size);
        defer fast_allocator.free(memory);
        @memset(memory, 0);
    }
    const fast_end = std.time.nanoTimestamp();
    const fast_duration = @as(f64, @floatFromInt(fast_end - fast_start)) / 1_000_000_000.0;
    const fast_ops_per_sec = 50_000.0 / fast_duration;

    // 测试ExtendedAllocator
    var extended_allocator = try ExtendedAllocator.init(base_allocator);
    defer extended_allocator.deinit();

    const ext_start = std.time.nanoTimestamp();
    for (0..50_000) |i| {
        const size = 1024 + (i % 2048);
        const memory = try extended_allocator.alloc(size);
        defer extended_allocator.free(memory);
        @memset(memory, 0);
    }
    const ext_end = std.time.nanoTimestamp();
    const ext_duration = @as(f64, @floatFromInt(ext_end - ext_start)) / 1_000_000_000.0;
    const ext_ops_per_sec = 50_000.0 / ext_duration;

    // 测试统一接口
    const unified_config = ZokioMemory.UnifiedConfig{
        .performance_mode = .high_performance,
        .enable_monitoring = false,
        .default_strategy = .auto,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, unified_config);
    defer memory_manager.deinit();

    const unified_start = std.time.nanoTimestamp();
    for (0..50_000) |i| {
        const size = 1024 + (i % 2048);
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);
        @memset(memory, 0);
    }
    const unified_end = std.time.nanoTimestamp();
    const unified_duration = @as(f64, @floatFromInt(unified_end - unified_start)) / 1_000_000_000.0;
    const unified_ops_per_sec = 50_000.0 / unified_duration;

    // 输出结果
    std.debug.print("📊 P2阶段目标达成情况:\n", .{});

    std.debug.print("  FastSmartAllocator:\n", .{});
    std.debug.print("    实际性能: {d:.0} ops/sec\n", .{fast_ops_per_sec});
    std.debug.print("    目标性能: {d:.0} ops/sec\n", .{p2_targets.fast_smart});
    if (fast_ops_per_sec >= p2_targets.fast_smart) {
        std.debug.print("    ✅ 目标达成: {d:.1}x 超越\n", .{fast_ops_per_sec / p2_targets.fast_smart});
    } else {
        std.debug.print("    ⚠️ 目标未达成: {d:.1}x 低于目标\n", .{fast_ops_per_sec / p2_targets.fast_smart});
    }

    std.debug.print("  ExtendedAllocator:\n", .{});
    std.debug.print("    实际性能: {d:.0} ops/sec\n", .{ext_ops_per_sec});
    std.debug.print("    目标性能: {d:.0} ops/sec\n", .{p2_targets.extended});
    if (ext_ops_per_sec >= p2_targets.extended) {
        std.debug.print("    ✅ 目标达成: {d:.1}x 超越\n", .{ext_ops_per_sec / p2_targets.extended});
    } else {
        std.debug.print("    ⚠️ 目标未达成: {d:.1}x 低于目标\n", .{ext_ops_per_sec / p2_targets.extended});
    }

    std.debug.print("  统一接口平均:\n", .{});
    std.debug.print("    实际性能: {d:.0} ops/sec\n", .{unified_ops_per_sec});
    std.debug.print("    目标性能: {d:.0} ops/sec\n", .{p2_targets.unified_avg});
    if (unified_ops_per_sec >= p2_targets.unified_avg) {
        std.debug.print("    ✅ 目标达成: {d:.1}x 超越\n", .{unified_ops_per_sec / p2_targets.unified_avg});
    } else {
        std.debug.print("    ⚠️ 目标未达成: {d:.1}x 低于目标\n", .{unified_ops_per_sec / p2_targets.unified_avg});
    }

    // 总体评估
    const targets_met = (if (fast_ops_per_sec >= p2_targets.fast_smart) @as(u32, 1) else 0) +
        (if (ext_ops_per_sec >= p2_targets.extended) @as(u32, 1) else 0) +
        (if (unified_ops_per_sec >= p2_targets.unified_avg) @as(u32, 1) else 0);

    std.debug.print("\n🎯 P2阶段总体评估:\n", .{});
    std.debug.print("  目标达成率: {}/3 ({d:.1}%)\n", .{ targets_met, @as(f64, @floatFromInt(targets_met)) / 3.0 * 100.0 });

    if (targets_met == 3) {
        std.debug.print("  🌟🌟🌟 P2阶段圆满完成！\n", .{});
    } else if (targets_met == 2) {
        std.debug.print("  🌟🌟 P2阶段基本完成！\n", .{});
    } else if (targets_met == 1) {
        std.debug.print("  🌟 P2阶段部分完成！\n", .{});
    } else {
        std.debug.print("  ⚠️ P2阶段需要进一步优化！\n", .{});
    }
}
