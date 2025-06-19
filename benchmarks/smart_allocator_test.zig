//! 智能统一内存分配器测试
//!
//! 演示智能分配器的自动策略选择和统一接口

const std = @import("std");
const zokio = @import("zokio");
const SmartAllocator = zokio.memory.SmartAllocator;
const AllocationStrategy = zokio.memory.AllocationStrategy;
const SmartAllocatorConfig = zokio.memory.SmartAllocatorConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 🧠 智能统一内存分配器测试 ===\n\n", .{});

    // 测试1: 基础智能分配功能
    try testBasicSmartAllocation(base_allocator);

    // 测试2: 自动策略选择
    try testAutoStrategySelection(base_allocator);

    // 测试3: 统一接口便利性
    try testUnifiedInterface(base_allocator);

    // 测试4: 性能监控和统计
    try testPerformanceMonitoring(base_allocator);

    // 测试5: 与之前分配器对比
    try testComparisonWithPreviousAllocators(base_allocator);

    std.debug.print("\n=== 🎉 智能分配器测试完成 ===\n", .{});
}

/// 测试基础智能分配功能
fn testBasicSmartAllocation(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 基础智能分配功能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = SmartAllocatorConfig{
        .default_strategy = .auto,
        .enable_auto_switching = true,
        .enable_monitoring = true,
        .enable_statistics = true,
    };

    var smart_allocator = try SmartAllocator.init(base_allocator, config);
    defer smart_allocator.deinit();

    std.debug.print("测试不同类型的智能分配...\n", .{});

    // 测试小对象分配
    std.debug.print("  分配小对象 (u8 × 64)...\n", .{});
    const small_memory = try smart_allocator.alloc(u8, 64);
    defer smart_allocator.free(small_memory);
    @memset(small_memory, 0xAA);

    // 测试中等对象分配
    std.debug.print("  分配中等对象 (u32 × 256)...\n", .{});
    const medium_memory = try smart_allocator.alloc(u32, 256);
    defer smart_allocator.free(medium_memory);
    for (medium_memory, 0..) |*item, i| {
        item.* = @as(u32, @intCast(i));
    }

    // 测试大对象分配
    std.debug.print("  分配大对象 (u64 × 1024)...\n", .{});
    const large_memory = try smart_allocator.alloc(u64, 1024);
    defer smart_allocator.free(large_memory);
    for (large_memory, 0..) |*item, i| {
        item.* = @as(u64, @intCast(i * i));
    }

    // 测试结构体分配
    const TestStruct = struct {
        id: u32,
        value: f64,
        name: [16]u8,
    };

    std.debug.print("  分配结构体 (TestStruct × 100)...\n", .{});
    const struct_memory = try smart_allocator.alloc(TestStruct, 100);
    defer smart_allocator.free(struct_memory);
    for (struct_memory, 0..) |*item, i| {
        item.id = @as(u32, @intCast(i));
        item.value = @as(f64, @floatFromInt(i)) * 3.14;
        @memset(&item.name, 0);
    }

    std.debug.print("\n📊 基础分配测试结果:\n", .{});
    const stats = smart_allocator.getAllocationStats();
    std.debug.print("  总分配请求: {}\n", .{stats.total_requests});
    std.debug.print("  成功分配: {}\n", .{stats.successful_allocations});
    std.debug.print("  策略切换次数: {}\n", .{stats.strategy_switches});

    const perf_stats = smart_allocator.getPerformanceStats();
    std.debug.print("  平均分配时间: {} ns\n", .{perf_stats.avg_allocation_time});
}

/// 测试自动策略选择
fn testAutoStrategySelection(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧠 测试2: 自动策略选择\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = SmartAllocatorConfig{
        .default_strategy = .auto,
        .enable_auto_switching = true,
        .auto_switch_config = .{
            .small_object_threshold = 256,
            .large_object_threshold = 8192,
            .high_frequency_threshold = 500.0,
            .switch_cooldown_ms = 100, // 减少冷却时间以便测试
        },
    };

    var smart_allocator = try SmartAllocator.init(base_allocator, config);
    defer smart_allocator.deinit();

    std.debug.print("测试不同场景下的策略选择...\n", .{});

    // 场景1: 高频小对象分配
    std.debug.print("  场景1: 高频小对象分配 (应选择object_pool)...\n", .{});
    var small_objects: [1000][]u8 = undefined;
    for (&small_objects, 0..) |*obj, i| {
        obj.* = try smart_allocator.alloc(u8, 64);
        obj.*[0] = @as(u8, @intCast(i % 256));
    }

    // 延迟一下让策略分析生效
    std.time.sleep(150 * std.time.ns_per_ms);

    for (small_objects) |obj| {
        smart_allocator.free(obj);
    }

    // 场景2: 中等对象分配
    std.debug.print("  场景2: 中等对象分配 (应选择extended_pool)...\n", .{});
    var medium_objects: [100][]u32 = undefined;
    for (&medium_objects, 0..) |*obj, i| {
        obj.* = try smart_allocator.alloc(u32, 512); // 2KB
        obj.*[0] = @as(u32, @intCast(i));
    }

    std.time.sleep(150 * std.time.ns_per_ms);

    for (medium_objects) |obj| {
        smart_allocator.free(obj);
    }

    // 场景3: 大对象分配
    std.debug.print("  场景3: 大对象分配 (应选择standard或arena)...\n", .{});
    var large_objects: [10][]u64 = undefined;
    for (&large_objects, 0..) |*obj, i| {
        obj.* = try smart_allocator.alloc(u64, 2048); // 16KB
        obj.*[0] = @as(u64, @intCast(i * 1000));
    }

    for (large_objects) |obj| {
        smart_allocator.free(obj);
    }

    std.debug.print("\n📊 策略选择测试结果:\n", .{});
    const stats = smart_allocator.getAllocationStats();
    std.debug.print("  总分配请求: {}\n", .{stats.total_requests});
    std.debug.print("  策略切换次数: {}\n", .{stats.strategy_switches});

    const recommended_strategy = smart_allocator.getOptimalStrategyRecommendation();
    std.debug.print("  当前推荐策略: {}\n", .{recommended_strategy});
}

/// 测试统一接口便利性
fn testUnifiedInterface(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔧 测试3: 统一接口便利性\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = SmartAllocatorConfig{
        .default_strategy = .auto,
        .enable_auto_switching = true,
    };

    var smart_allocator = try SmartAllocator.init(base_allocator, config);
    defer smart_allocator.deinit();

    // 获取标准分配器接口
    const allocator = smart_allocator.allocator();

    std.debug.print("使用标准分配器接口进行分配...\n", .{});

    // 使用标准接口分配各种类型
    const u8_memory = try allocator.alloc(u8, 100);
    defer allocator.free(u8_memory);

    const u32_memory = try allocator.alloc(u32, 200);
    defer allocator.free(u32_memory);

    const f64_memory = try allocator.alloc(f64, 50);
    defer allocator.free(f64_memory);

    // 测试与标准库的兼容性
    var array_list = std.ArrayList(i32).init(allocator);
    defer array_list.deinit();

    for (0..1000) |i| {
        try array_list.append(@as(i32, @intCast(i)));
    }

    var hash_map = std.AutoHashMap(u32, []const u8).init(allocator);
    defer hash_map.deinit();

    try hash_map.put(1, "hello");
    try hash_map.put(2, "world");
    try hash_map.put(3, "zokio");

    std.debug.print("\n📊 统一接口测试结果:\n", .{});
    std.debug.print("  ArrayList大小: {}\n", .{array_list.items.len});
    std.debug.print("  HashMap大小: {}\n", .{hash_map.count()});

    const stats = smart_allocator.getAllocationStats();
    std.debug.print("  总分配请求: {}\n", .{stats.total_requests});
    std.debug.print("  成功率: {d:.1}%\n", .{if (stats.total_requests > 0)
        @as(f64, @floatFromInt(stats.successful_allocations)) / @as(f64, @floatFromInt(stats.total_requests)) * 100.0
    else
        0.0});
}

/// 测试性能监控和统计
fn testPerformanceMonitoring(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n📈 测试4: 性能监控和统计\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = SmartAllocatorConfig{
        .default_strategy = .auto,
        .enable_monitoring = true,
        .enable_statistics = true,
    };

    var smart_allocator = try SmartAllocator.init(base_allocator, config);
    defer smart_allocator.deinit();

    std.debug.print("执行性能监控测试...\n", .{});

    const iterations = 10000;
    const start_time = std.time.nanoTimestamp();

    // 执行大量分配操作
    for (0..iterations) |i| {
        const size = 64 + (i % 1024); // 64B-1KB
        const memory = try smart_allocator.alloc(u8, size);
        defer smart_allocator.free(memory);

        // 简单使用内存
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const total_time = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / total_time;

    std.debug.print("\n📊 性能监控结果:\n", .{});
    std.debug.print("  测试迭代次数: {}\n", .{iterations});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{total_time});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    const perf_stats = smart_allocator.getPerformanceStats();
    std.debug.print("  平均分配时间: {} ns\n", .{perf_stats.avg_allocation_time});

    const alloc_stats = smart_allocator.getAllocationStats();
    std.debug.print("  总分配请求: {}\n", .{alloc_stats.total_requests});
    std.debug.print("  成功分配: {}\n", .{alloc_stats.successful_allocations});
    std.debug.print("  策略切换: {}\n", .{alloc_stats.strategy_switches});
}

/// 测试与之前分配器的对比
fn testComparisonWithPreviousAllocators(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚖️ 测试5: 与之前分配器对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 50000;

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

    // 测试智能分配器
    std.debug.print("测试智能分配器...\n", .{});
    const config = SmartAllocatorConfig{
        .default_strategy = .auto,
        .enable_auto_switching = true,
        .enable_monitoring = true,
    };

    var smart_allocator = try SmartAllocator.init(base_allocator, config);
    defer smart_allocator.deinit();

    const smart_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64 + (i % 1024);
        const memory = try smart_allocator.alloc(u8, size);
        defer smart_allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const smart_end = std.time.nanoTimestamp();
    const smart_duration = @as(f64, @floatFromInt(smart_end - smart_start)) / 1_000_000_000.0;
    const smart_ops_per_sec = @as(f64, @floatFromInt(iterations)) / smart_duration;

    // 输出对比结果
    std.debug.print("\n📊 分配器对比结果:\n", .{});
    std.debug.print("  标准分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{std_duration});

    std.debug.print("  智能分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{smart_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{smart_duration});

    const improvement = smart_ops_per_sec / std_ops_per_sec;
    std.debug.print("  性能比: {d:.2}x ", .{improvement});
    if (improvement >= 2.0) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement >= 1.2) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("✅ (有所提升)\n", .{});
    } else {
        std.debug.print("⚠️ (性能下降)\n", .{});
    }

    // 智能分配器的额外统计
    const stats = smart_allocator.getAllocationStats();
    std.debug.print("  智能特性:\n", .{});
    std.debug.print("    策略切换: {}\n", .{stats.strategy_switches});
    std.debug.print("    推荐策略: {}\n", .{smart_allocator.getOptimalStrategyRecommendation()});

    const perf_stats = smart_allocator.getPerformanceStats();
    std.debug.print("    平均延迟: {} ns\n", .{perf_stats.avg_allocation_time});
}
