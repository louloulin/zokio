//! 简化的内存管理系统演示
//!
//! 展示Zokio的高性能内存管理功能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 高性能内存管理系统演示 ===\n", .{});

    // 演示1：基础内存分配器
    try demonstrateBasicAllocator(allocator);

    // 演示2：对象池功能
    try demonstrateObjectPool();

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

/// 演示基础内存分配器功能
fn demonstrateBasicAllocator(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 基础内存分配器演示\n", .{});

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
    std.debug.print("   分层分布 - 小: {d:.1}%, 中: {d:.1}%, 大: {d:.1}%\n", .{
        distribution.small * 100,
        distribution.medium * 100,
        distribution.large * 100,
    });
}

/// 演示对象池功能
fn demonstrateObjectPool() !void {
    std.debug.print("\n2. 对象池功能演示\n", .{});

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
    std.debug.print("   已释放所有对象\n", .{});
}
