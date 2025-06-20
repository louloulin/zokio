//! 扩展内存分配器性能测试
//!
//! 专门修复Tokio等效负载测试问题

const std = @import("std");
const zokio = @import("zokio");
const ExtendedAllocator = zokio.memory.ExtendedAllocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 扩展内存分配器性能测试 ===\n\n", .{});

    // 测试1: 覆盖范围验证
    try testCoverageRange(base_allocator);

    // 测试2: Tokio等效负载修复测试
    try testTokioEquivalentLoadFixed(base_allocator);

    // 测试3: 大对象分配性能测试
    try testLargeObjectAllocation(base_allocator);

    // 测试4: 全范围性能对比
    try testFullRangeComparison(base_allocator);

    std.debug.print("\n=== 扩展内存分配器测试完成 ===\n", .{});
}

/// 测试覆盖范围验证
fn testCoverageRange(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔍 测试1: 覆盖范围验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var ext_allocator = try ExtendedAllocator.init(base_allocator);
    defer ext_allocator.deinit();

    const test_sizes = [_]usize{ 8, 64, 256, 512, 1024, 2048, 4096, 8192 };

    std.debug.print("测试各种大小的对象分配...\n", .{});

    for (test_sizes) |size| {
        const memory = try ext_allocator.alloc(size);
        defer ext_allocator.free(memory);

        // 验证内存可用性
        @memset(memory, 0xAA);

        std.debug.print("  {d}B: ✅ 分配成功\n", .{size});
    }

    const stats = ext_allocator.getStats();
    std.debug.print("\n📊 覆盖范围统计:\n", .{});
    std.debug.print("  总池数: {}\n", .{stats.total_pools});
    std.debug.print("  覆盖范围: 8B - 8KB\n", .{});
    std.debug.print("  池覆盖率: {d:.1}%\n", .{stats.pool_coverage * 100.0});
}

/// 测试修复后的Tokio等效负载
fn testTokioEquivalentLoadFixed(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🚀 测试2: Tokio等效负载修复测试\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // 测试标准分配器性能
    std.debug.print("测试标准分配器...\n", .{});
    const std_start = std.time.nanoTimestamp();

    const iterations = 50000; // 增加测试量以获得更准确的结果

    for (0..iterations) |i| {
        const size = 1024 + (i % 4096); // 1KB-5KB
        const memory = try base_allocator.alloc(u8, size);
        defer base_allocator.free(memory);

        // 初始化内存
        @memset(memory, 0);
    }

    const std_end = std.time.nanoTimestamp();
    const std_duration = @as(f64, @floatFromInt(std_end - std_start)) / 1_000_000_000.0;
    const std_ops_per_sec = @as(f64, @floatFromInt(iterations)) / std_duration;

    // 测试扩展分配器性能
    std.debug.print("测试扩展分配器...\n", .{});
    var ext_allocator = try ExtendedAllocator.init(base_allocator);
    defer ext_allocator.deinit();

    const ext_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 1024 + (i % 4096); // 1KB-5KB
        const memory = try ext_allocator.alloc(size);
        defer ext_allocator.free(memory);

        // 初始化内存
        @memset(memory, 0);
    }

    const ext_end = std.time.nanoTimestamp();
    const ext_duration = @as(f64, @floatFromInt(ext_end - ext_start)) / 1_000_000_000.0;
    const ext_ops_per_sec = @as(f64, @floatFromInt(iterations)) / ext_duration;

    // 输出结果
    std.debug.print("\n📊 Tokio等效负载修复结果:\n", .{});
    std.debug.print("  标准分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{std_duration});

    std.debug.print("  扩展分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{ext_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{ext_duration});

    const improvement = ext_ops_per_sec / std_ops_per_sec;
    std.debug.print("  性能提升: {d:.2}x ", .{improvement});
    if (improvement >= 3.0) {
        std.debug.print("🌟🌟🌟 (巨大提升)\n", .{});
    } else if (improvement >= 2.0) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement >= 1.5) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("✅ (有所提升)\n", .{});
    } else {
        std.debug.print("⚠️ (性能下降)\n", .{});
    }

    // 与Tokio基准对比
    const tokio_baseline = 1_500_000.0;
    const tokio_ratio = ext_ops_per_sec / tokio_baseline;

    std.debug.print("\n🦀 与Tokio基准对比:\n", .{});
    std.debug.print("  扩展分配器: {d:.0} ops/sec\n", .{ext_ops_per_sec});
    std.debug.print("  Tokio基准: {d:.0} ops/sec\n", .{tokio_baseline});
    std.debug.print("  性能比: {d:.2}x ", .{tokio_ratio});

    if (tokio_ratio >= 3.3) {
        std.debug.print("🌟🌟🌟 (超越目标)\n", .{});
    } else if (tokio_ratio >= 2.0) {
        std.debug.print("🌟🌟 (显著优于Tokio)\n", .{});
    } else if (tokio_ratio >= 1.0) {
        std.debug.print("🌟 (优于Tokio)\n", .{});
    } else {
        std.debug.print("⚠️ (仍低于Tokio)\n", .{});
    }

    const stats = ext_allocator.getStats();
    std.debug.print("  对象复用率: {d:.1}%\n", .{stats.reuse_rate * 100.0});
    std.debug.print("  目标完成度: {d:.1}% (目标: 3.3x Tokio)\n", .{(tokio_ratio / 3.3) * 100.0});
}

/// 测试大对象分配性能
fn testLargeObjectAllocation(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n📦 测试3: 大对象分配性能测试\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var ext_allocator = try ExtendedAllocator.init(base_allocator);
    defer ext_allocator.deinit();

    const large_sizes = [_]usize{ 512, 1024, 2048, 4096, 8192 };
    const iterations_per_size = 10000;

    std.debug.print("测试不同大小的大对象分配...\n", .{});

    for (large_sizes) |size| {
        const start_time = std.time.nanoTimestamp();

        for (0..iterations_per_size) |i| {
            const memory = try ext_allocator.alloc(size);
            defer ext_allocator.free(memory);

            // 简单使用
            memory[0] = @as(u8, @intCast(i % 256));
            if (memory.len > 1) {
                memory[memory.len - 1] = @as(u8, @intCast((i + 1) % 256));
            }
        }

        const end_time = std.time.nanoTimestamp();
        const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(iterations_per_size)) / duration;

        std.debug.print("  {d}B: {d:.0} ops/sec\n", .{ size, ops_per_sec });
    }

    const stats = ext_allocator.getStats();
    std.debug.print("\n📊 大对象分配统计:\n", .{});
    std.debug.print("  总复用率: {d:.1}%\n", .{stats.reuse_rate * 100.0});
    std.debug.print("  总分配次数: {}\n", .{stats.total_allocated});
    std.debug.print("  总复用次数: {}\n", .{stats.total_reused});
}

/// 测试全范围性能对比
fn testFullRangeComparison(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试4: 全范围性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var ext_allocator = try ExtendedAllocator.init(base_allocator);
    defer ext_allocator.deinit();

    const iterations = 100_000;
    const size_ranges = [_]struct { min: usize, max: usize, name: []const u8 }{
        .{ .min = 8, .max = 256, .name = "小对象" },
        .{ .min = 256, .max = 1024, .name = "中对象" },
        .{ .min = 1024, .max = 8192, .name = "大对象" },
    };

    std.debug.print("测试全范围混合分配...\n", .{});

    for (size_ranges) |range| {
        const start_time = std.time.nanoTimestamp();

        for (0..iterations) |i| {
            const size = range.min + (i % (range.max - range.min));
            const memory = try ext_allocator.alloc(size);
            defer ext_allocator.free(memory);

            // 模拟实际使用
            @memset(memory, @as(u8, @intCast(i % 256)));
        }

        const end_time = std.time.nanoTimestamp();
        const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
        const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

        std.debug.print("  {s} ({d}B-{d}B): {d:.0} ops/sec\n", .{ range.name, range.min, range.max, ops_per_sec });
    }

    // 获取详细统计
    const detailed_stats = ext_allocator.getDetailedStats();

    std.debug.print("\n📊 详细池使用统计:\n", .{});
    for (detailed_stats.pool_stats, 0..) |pool_stat, i| {
        if (pool_stat.allocated + pool_stat.reused > 0) {
            std.debug.print("  池{d} ({d}B): 分配{d} 复用{d} 复用率{d:.1}%\n", .{ i, pool_stat.size, pool_stat.allocated, pool_stat.reused, pool_stat.reuse_rate * 100.0 });
        }
    }

    std.debug.print("  总内存使用: {d:.2} MB\n", .{@as(f64, @floatFromInt(detailed_stats.total_memory_used)) / (1024.0 * 1024.0)});

    const overall_stats = ext_allocator.getStats();
    std.debug.print("  整体复用率: {d:.1}%\n", .{overall_stats.reuse_rate * 100.0});
}
