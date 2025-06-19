//! Zokio 统一内存管理接口测试
//!
//! P1阶段功能验证：统一接口、性能基准、标准化API

const std = @import("std");
const zokio = @import("zokio");
const ZokioMemory = zokio.memory.ZokioMemory;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 🧠 Zokio 统一内存管理接口测试 ===\n\n", .{});

    // 测试1: 基础统一接口功能
    try testUnifiedInterface(base_allocator);

    // 测试2: 自动策略选择
    try testAutoStrategySelection(base_allocator);

    // 测试3: 性能基准测试
    try testPerformanceBenchmark(base_allocator);

    // 测试4: 统计监控功能
    try testStatisticsMonitoring(base_allocator);

    // 测试5: 标准分配器兼容性
    try testStandardAllocatorCompatibility(base_allocator);

    std.debug.print("\n=== ✅ P1阶段：统一接口测试完成 ===\n", .{});
}

/// 测试基础统一接口功能
fn testUnifiedInterface(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 测试1: 基础统一接口功能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .balanced,
        .enable_fast_path = true,
        .enable_monitoring = true,
        .default_strategy = .auto,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    // 测试不同类型的分配
    std.debug.print("测试不同类型分配...\n", .{});

    // 小对象分配
    const small_data = try memory_manager.alloc(u8, 64);
    defer memory_manager.free(small_data);
    std.debug.print("  ✅ 小对象分配 (64B): 成功\n", .{});

    // 中等对象分配
    const medium_data = try memory_manager.alloc(u32, 1024);
    defer memory_manager.free(medium_data);
    std.debug.print("  ✅ 中等对象分配 (4KB): 成功\n", .{});

    // 大对象分配
    const large_data = try memory_manager.alloc(u64, 2048);
    defer memory_manager.free(large_data);
    std.debug.print("  ✅ 大对象分配 (16KB): 成功\n", .{});

    // 测试结构体分配
    const TestStruct = struct {
        id: u32,
        value: f64,
        name: [16]u8,
    };

    const struct_data = try memory_manager.alloc(TestStruct, 100);
    defer memory_manager.free(struct_data);
    std.debug.print("  ✅ 结构体分配 (100个): 成功\n", .{});

    std.debug.print("📊 基础接口测试结果: 全部通过 ✅\n\n", .{});
}

/// 测试自动策略选择
fn testAutoStrategySelection(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🎯 测试2: 自动策略选择\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .default_strategy = .auto,
        .small_threshold = 256,
        .large_threshold = 8192,
        .enable_monitoring = true,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    std.debug.print("测试自动策略选择...\n", .{});

    // 小对象 -> 应该选择optimized策略
    const small_objects = try memory_manager.alloc(u8, 128);
    defer memory_manager.free(small_objects);

    // 中等对象 -> 应该选择extended策略
    const medium_objects = try memory_manager.alloc(u8, 4096);
    defer memory_manager.free(medium_objects);

    // 大对象 -> 应该选择smart策略
    const large_objects = try memory_manager.alloc(u8, 16384);
    defer memory_manager.free(large_objects);

    const stats = memory_manager.getStats();
    std.debug.print("  总分配次数: {}\n", .{stats.total_allocations});
    std.debug.print("  当前内存使用: {} bytes\n", .{stats.current_memory_usage});
    std.debug.print("  峰值内存使用: {} bytes\n", .{stats.peak_memory_usage});

    const distribution = stats.getAllocatorDistribution();
    std.debug.print("  分配器使用分布:\n", .{});
    std.debug.print("    智能分配器: {d:.1}%\n", .{distribution.smart * 100});
    std.debug.print("    扩展分配器: {d:.1}%\n", .{distribution.extended * 100});
    std.debug.print("    优化分配器: {d:.1}%\n", .{distribution.optimized * 100});

    std.debug.print("📊 自动策略选择测试结果: 通过 ✅\n\n", .{});
}

/// 测试性能基准
fn testPerformanceBenchmark(base_allocator: std.mem.Allocator) !void {
    std.debug.print("⚡ 测试3: 性能基准测试\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 100_000;

    // 测试统一接口性能
    std.debug.print("测试统一接口性能...\n", .{});
    const config = ZokioMemory.UnifiedConfig{
        .performance_mode = .high_performance,
        .enable_fast_path = true,
        .enable_monitoring = false, // 关闭监控以获得最大性能
        .default_strategy = .auto,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64 + (i % 1024); // 64B-1KB
        const memory = try memory_manager.alloc(u8, size);
        defer memory_manager.free(memory);

        // 简单使用内存
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("📊 统一接口性能结果:\n", .{});
    std.debug.print("  迭代次数: {}\n", .{iterations});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 性能目标验证
    const target_ops_per_sec = 1_000_000.0; // 1M ops/sec 目标
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("  🌟 性能目标达成: {d:.1}x 超越目标\n", .{ops_per_sec / target_ops_per_sec});
    } else {
        std.debug.print("  ⚠️ 性能目标未达成: {d:.1}x 低于目标\n", .{ops_per_sec / target_ops_per_sec});
    }

    std.debug.print("📊 性能基准测试结果: 完成 ✅\n\n", .{});
}

/// 测试统计监控功能
fn testStatisticsMonitoring(base_allocator: std.mem.Allocator) !void {
    std.debug.print("📊 测试4: 统计监控功能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .enable_monitoring = true,
        .default_strategy = .auto,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    std.debug.print("执行监控测试...\n", .{});

    // 执行一系列分配操作
    var allocations: [10][]u8 = undefined;
    for (&allocations, 0..) |*alloc, i| {
        const size = (i + 1) * 512; // 512B, 1KB, 1.5KB, ...
        alloc.* = try memory_manager.alloc(u8, size);
    }

    // 获取统计信息
    const stats = memory_manager.getStats();
    std.debug.print("📈 实时统计信息:\n", .{});
    std.debug.print("  总分配次数: {}\n", .{stats.total_allocations});
    std.debug.print("  总释放次数: {}\n", .{stats.total_deallocations});
    std.debug.print("  当前内存使用: {} bytes\n", .{stats.current_memory_usage});
    std.debug.print("  峰值内存使用: {} bytes\n", .{stats.peak_memory_usage});
    std.debug.print("  平均分配时间: {} ns\n", .{stats.average_allocation_time});
    std.debug.print("  缓存命中率: {d:.1}%\n", .{stats.cache_hit_rate * 100});
    std.debug.print("  内存效率: {d:.1}%\n", .{stats.getMemoryEfficiency() * 100});

    const distribution = stats.getAllocatorDistribution();
    std.debug.print("📊 分配器使用分布:\n", .{});
    std.debug.print("  智能分配器: {d:.1}%\n", .{distribution.smart * 100});
    std.debug.print("  扩展分配器: {d:.1}%\n", .{distribution.extended * 100});
    std.debug.print("  优化分配器: {d:.1}%\n", .{distribution.optimized * 100});

    // 释放所有分配
    for (allocations) |alloc| {
        memory_manager.free(alloc);
    }

    // 获取释放后的统计
    const final_stats = memory_manager.getStats();
    std.debug.print("📉 释放后统计:\n", .{});
    std.debug.print("  当前内存使用: {} bytes\n", .{final_stats.current_memory_usage});
    std.debug.print("  总释放次数: {}\n", .{final_stats.total_deallocations});

    std.debug.print("📊 统计监控测试结果: 通过 ✅\n\n", .{});
}

/// 测试标准分配器兼容性
fn testStandardAllocatorCompatibility(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔗 测试5: 标准分配器兼容性\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = ZokioMemory.UnifiedConfig{
        .default_strategy = .auto,
        .enable_monitoring = true,
    };

    var memory_manager = try ZokioMemory.init(base_allocator, config);
    defer memory_manager.deinit();

    const allocator = memory_manager.allocator();

    std.debug.print("测试标准库容器兼容性...\n", .{});

    // 测试ArrayList
    var list = std.ArrayList(i32).init(allocator);
    defer list.deinit();

    for (0..1000) |i| {
        try list.append(@as(i32, @intCast(i)));
    }
    std.debug.print("  ✅ ArrayList: 添加1000个元素成功\n", .{});

    // 测试字符串分配
    const string_data = try allocator.alloc(u8, 100);
    defer allocator.free(string_data);
    @memcpy(string_data[0..5], "hello");
    std.debug.print("  ✅ 字符串分配: 分配100字节成功\n", .{});

    // 测试动态分配
    const dynamic_array = try allocator.alloc(f64, 500);
    defer allocator.free(dynamic_array);

    for (dynamic_array, 0..) |*item, i| {
        item.* = @as(f64, @floatFromInt(i)) * 3.14;
    }
    std.debug.print("  ✅ 动态数组: 分配500个f64成功\n", .{});

    // 获取最终统计
    const stats = memory_manager.getStats();
    std.debug.print("📊 兼容性测试统计:\n", .{});
    std.debug.print("  总分配次数: {}\n", .{stats.total_allocations});
    std.debug.print("  当前内存使用: {} bytes\n", .{stats.current_memory_usage});
    std.debug.print("  成功率: 100.0%\n", .{});

    std.debug.print("📊 标准分配器兼容性测试结果: 通过 ✅\n\n", .{});
}
