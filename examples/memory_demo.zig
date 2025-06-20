//! 高性能内存管理系统演示
//!
//! 展示Zokio的分层内存管理、缓存友好设计和垃圾回收优化功能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 高性能内存管理系统演示 ===\n\n", .{});

    // 演示1：基础内存分配器
    try demonstrateBasicAllocator(allocator);

    // 演示2：对象池功能
    try demonstrateObjectPool();

    // 演示3：分层内存管理
    try demonstrateTieredMemory(allocator);

    // 演示4：缓存友好分配
    try demonstrateCacheFriendlyAllocation(allocator);

    // 演示5：内存统计和监控
    try demonstrateMemoryMetrics(allocator);

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

/// 演示基础内存分配器功能
fn demonstrateBasicAllocator(base_allocator: std.mem.Allocator) !void {
    std.debug.print("1. 基础内存分配器演示\n", .{});

    const config = zokio.memory.MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = true,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
    };

    var allocator = try zokio.memory.MemoryAllocator(config).init(base_allocator);
    defer allocator.deinit();

    // 分配不同大小的内存
    const small_memory = try allocator.alloc(u8, 64);
    defer allocator.free(small_memory);

    const medium_memory = try allocator.alloc(u32, 512);
    defer allocator.free(medium_memory);

    const large_memory = try allocator.alloc(u64, 16384);
    defer allocator.free(large_memory);

    // 获取统计信息
    const stats = allocator.metrics.getStats();
    std.debug.print("   分配次数: {}\n", .{stats.allocation_count});
    std.debug.print("   当前使用: {} 字节\n", .{stats.current_usage});
    std.debug.print("   峰值使用: {} 字节\n", .{stats.peak_usage});
    std.debug.print("   内存效率: {d:.2}%\n", .{stats.getMemoryEfficiency() * 100});

    const distribution = stats.getTierDistribution();
    std.debug.print("   分层分布 - 小: {d:.1}%, 中: {d:.1}%, 大: {d:.1}%\n\n", .{
        distribution.small * 100,
        distribution.medium * 100,
        distribution.large * 100,
    });
}

/// 演示对象池功能
fn demonstrateObjectPool() !void {
    std.debug.print("2. 对象池功能演示\n", .{});

    const TestObject = struct {
        id: u32,
        data: [64]u8,
    };

    var pool = zokio.memory.ObjectPool(TestObject, 100).init();

    // 预热对象池
    pool.warmup(50);
    std.debug.print("   对象池已预热 50 个对象\n", .{});

    // 批量分配对象
    var objects: [20]*TestObject = undefined;
    const acquired = pool.acquireBatch(&objects, 20);
    std.debug.print("   批量分配了 {} 个对象\n", .{acquired});

    // 设置对象数据
    for (objects[0..acquired], 0..) |obj, i| {
        obj.id = @as(u32, @intCast(i));
        @memset(&obj.data, @as(u8, @intCast(i % 256)));
    }

    // 获取统计信息
    const stats = pool.getStats();
    std.debug.print("   总对象数: {}\n", .{stats.total_objects});
    std.debug.print("   已分配: {}\n", .{stats.allocated_objects});
    std.debug.print("   空闲: {}\n", .{stats.free_objects});
    std.debug.print("   内存使用: {} 字节\n", .{stats.memory_usage});
    std.debug.print("   碎片率: {d:.2}%\n", .{stats.fragmentation_ratio * 100});
    std.debug.print("   缓存命中率: {d:.2}%\n", .{stats.cache_hit_ratio * 100});

    // 批量释放对象
    pool.releaseBatch(&objects, acquired);
    std.debug.print("   已释放所有对象\n\n", .{});
}

/// 演示分层内存管理
fn demonstrateTieredMemory(base_allocator: std.mem.Allocator) !void {
    std.debug.print("3. 分层内存管理演示\n", .{});

    // 使用adaptive策略进行演示（tiered_pools可能还不稳定）
    const config = zokio.memory.MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = true,
        .small_pool_size = 128,
        .medium_pool_size = 64,
        .large_pool_threshold = 64 * 1024,
    };

    var allocator = try zokio.memory.MemoryAllocator(config).init(base_allocator);
    defer allocator.deinit();

    // 分配不同层级的内存
    std.debug.print("   分配小对象 (< 1KB)...\n", .{});
    var small_allocations: [10][]u8 = undefined;
    for (&small_allocations, 0..) |*alloc, i| {
        alloc.* = try allocator.alloc(u8, 32 + i * 8);
    }

    std.debug.print("   分配中等对象 (1KB - 64KB)...\n", .{});
    var medium_allocations: [5][]u8 = undefined;
    for (&medium_allocations, 0..) |*alloc, i| {
        alloc.* = try allocator.alloc(u8, 1024 + i * 2048);
    }

    std.debug.print("   分配大对象 (> 64KB)...\n", .{});
    var large_allocations: [2][]u8 = undefined;
    for (&large_allocations, 0..) |*alloc, i| {
        alloc.* = try allocator.alloc(u8, 128 * 1024 + i * 64 * 1024);
    }

    // 获取分层统计
    const stats = allocator.metrics.getStats();
    const distribution = stats.getTierDistribution();
    std.debug.print("   分层分配统计:\n", .{});
    std.debug.print("     小对象: {} 次 ({d:.1}%)\n", .{ stats.small_allocations, distribution.small * 100 });
    std.debug.print("     中等对象: {} 次 ({d:.1}%)\n", .{ stats.medium_allocations, distribution.medium * 100 });
    std.debug.print("     大对象: {} 次 ({d:.1}%)\n", .{ stats.large_allocations, distribution.large * 100 });

    // 释放内存
    for (small_allocations) |alloc| allocator.free(alloc);
    for (medium_allocations) |alloc| allocator.free(alloc);
    for (large_allocations) |alloc| allocator.free(alloc);

    std.debug.print("   所有内存已释放\n\n", .{});
}

/// 演示缓存友好分配
fn demonstrateCacheFriendlyAllocation(base_allocator: std.mem.Allocator) !void {
    std.debug.print("4. 缓存友好分配演示\n", .{});

    // 使用adaptive策略进行演示（cache_friendly可能还不稳定）
    const config = zokio.memory.MemoryConfig{
        .strategy = .adaptive,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
        .enable_false_sharing_prevention = true,
    };

    var allocator = try zokio.memory.MemoryAllocator(config).init(base_allocator);
    defer allocator.deinit();

    // 分配缓存行对齐的内存
    const memory = try allocator.alloc(u8, 256);
    defer allocator.free(memory);

    const addr = @intFromPtr(memory.ptr);
    const cache_line_size = 64; // 假设64字节缓存行
    const is_aligned = (addr % cache_line_size) == 0;

    std.debug.print("   内存地址: 0x{X}\n", .{addr});
    std.debug.print("   缓存行对齐: {}\n", .{if (is_aligned) "是" else "否"});
    std.debug.print("   内存大小: {} 字节\n", .{memory.len});

    // 测试内存访问性能
    const start_time = std.time.nanoTimestamp();

    // 顺序访问内存（缓存友好）
    var sum: u64 = 0;
    for (memory, 0..) |*byte, i| {
        byte.* = @as(u8, @intCast(i % 256));
        sum += byte.*;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;

    std.debug.print("   内存访问时间: {} 纳秒\n", .{duration});
    std.debug.print("   校验和: {}\n", .{sum});
    std.debug.print("   平均每字节访问时间: {d:.2} 纳秒\n\n", .{@as(f64, @floatFromInt(duration)) / @as(f64, @floatFromInt(memory.len))});
}

/// 演示内存统计和监控
fn demonstrateMemoryMetrics(base_allocator: std.mem.Allocator) !void {
    std.debug.print("5. 内存统计和监控演示\n", .{});

    const config = zokio.memory.MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = true,
    };

    var allocator = try zokio.memory.MemoryAllocator(config).init(base_allocator);
    defer allocator.deinit();

    // 进行一系列内存操作
    var allocations: [100][]u8 = undefined;

    std.debug.print("   执行 100 次内存分配...\n", .{});
    for (&allocations, 0..) |*alloc, i| {
        const size = 64 + (i % 10) * 32;
        alloc.* = try allocator.alloc(u8, size);

        // 写入数据
        for (alloc.*, 0..) |*byte, j| {
            byte.* = @as(u8, @intCast((i + j) % 256));
        }
    }

    // 获取详细统计信息
    const stats = allocator.metrics.getStats();

    std.debug.print("   内存统计报告:\n", .{});
    std.debug.print("     总分配量: {} 字节\n", .{stats.total_allocated});
    std.debug.print("     总释放量: {} 字节\n", .{stats.total_deallocated});
    std.debug.print("     当前使用: {} 字节\n", .{stats.current_usage});
    std.debug.print("     峰值使用: {} 字节\n", .{stats.peak_usage});
    std.debug.print("     分配次数: {}\n", .{stats.allocation_count});
    std.debug.print("     释放次数: {}\n", .{stats.deallocation_count});
    std.debug.print("     缓存未命中: {}\n", .{stats.cache_misses});
    std.debug.print("     GC周期: {}\n", .{stats.gc_cycles});
    std.debug.print("     延迟释放: {}\n", .{stats.delayed_frees});

    std.debug.print("   性能指标:\n", .{});
    std.debug.print("     内存效率: {d:.2}%\n", .{stats.getMemoryEfficiency() * 100});
    std.debug.print("     缓存命中率: {d:.2}%\n", .{stats.getCacheHitRatio() * 100});

    // 释放所有内存
    std.debug.print("   释放所有内存...\n", .{});
    for (allocations) |alloc| {
        allocator.free(alloc);
    }

    const final_stats = allocator.metrics.getStats();
    std.debug.print("   最终当前使用: {} 字节\n", .{final_stats.current_usage});
}
