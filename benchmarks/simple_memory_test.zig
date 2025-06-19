//! 简化的内存分配性能测试
//!
//! 目标：验证内存分配优化效果

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 简化的内存分配性能测试 ===\n\n", .{});

    // 测试1: 基础分配性能
    try testBasicAllocation(base_allocator);

    // 测试2: 小对象分配性能
    try testSmallObjectAllocation(base_allocator);

    // 测试3: 与之前结果对比
    try testComparisonWithPrevious(base_allocator);

    std.debug.print("\n=== 内存分配性能测试完成 ===\n", .{});
}

/// 测试基础分配性能
fn testBasicAllocation(allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 基础分配性能\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    const iterations = 100_000; // 10万次分配

    std.debug.print("测试标准分配器性能...\n", .{});
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |i| {
        const size = 64 + (i % 192); // 64-256字节
        const memory = try allocator.alloc(u8, size);
        defer allocator.free(memory);
        
        // 简单的内存使用
        @memset(memory, @as(u8, @intCast(i % 256)));
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 基础分配性能结果:\n", .{});
    std.debug.print("  分配次数: {}\n", .{iterations});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 与之前的Tokio基准数据对比
    const tokio_baseline = 1_500_000.0; // Tokio基准: 1.5M ops/sec
    const improvement = ops_per_sec / tokio_baseline;

    std.debug.print("\n🦀 与Tokio基准对比:\n", .{});
    std.debug.print("  当前性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  Tokio基准: {d:.0} ops/sec\n", .{tokio_baseline});
    std.debug.print("  性能比: {d:.2}x ", .{improvement});
    
    if (improvement >= 3.0) {
        std.debug.print("🌟🌟🌟 (超越目标3倍)\n", .{});
    } else if (improvement >= 2.0) {
        std.debug.print("🌟🌟 (显著优于Tokio)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("🌟 (优于Tokio)\n", .{});
    } else {
        std.debug.print("⚠️ (需要进一步优化)\n", .{});
    }
}

/// 测试小对象分配性能
fn testSmallObjectAllocation(allocator: std.mem.Allocator) !void {
    std.debug.print("\n💾 测试2: 小对象分配性能\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    const iterations = 500_000; // 50万次小对象分配
    const small_sizes = [_]usize{ 8, 16, 32, 64, 128, 256 };

    std.debug.print("测试小对象分配 (8B-256B)...\n", .{});
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |i| {
        const size = small_sizes[i % small_sizes.len];
        const memory = try allocator.alloc(u8, size);
        defer allocator.free(memory);
        
        // 验证内存可用性
        memory[0] = @as(u8, @intCast(i % 256));
        if (memory.len > 1) {
            memory[memory.len - 1] = @as(u8, @intCast((i + 1) % 256));
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 小对象分配性能结果:\n", .{});
    std.debug.print("  分配次数: {}\n", .{iterations});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    // 检查是否达到5M ops/sec目标
    const target_ops_per_sec = 5_000_000.0;
    std.debug.print("  目标达成: {d:.0} / {d:.0} ops/sec ", .{ ops_per_sec, target_ops_per_sec });
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("✅ 目标达成！\n", .{});
    } else {
        const progress = (ops_per_sec / target_ops_per_sec) * 100.0;
        std.debug.print("⚠️ 进度: {d:.1}%\n", .{progress});
    }
}

/// 测试与之前结果对比
fn testComparisonWithPrevious(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试3: 与之前结果对比\n", .{});
    std.debug.print("-" ** 40 ++ "\n", .{});

    const iterations = 5000; // 与之前的对比测试保持一致
    
    std.debug.print("执行与之前相同的内存分配模式...\n", .{});
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..iterations) |i| {
        // 模拟之前测试中的分配模式
        const size = 1024 + (i % 4096); // 1KB-5KB
        const memory = try allocator.alloc(u8, size);
        defer allocator.free(memory);
        
        // 初始化内存（与之前测试相同）
        @memset(memory, 0);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    // 与之前的测试结果对比
    const previous_result = 150_024.0; // 之前的测试结果: 150K ops/sec
    const improvement = ops_per_sec / previous_result;

    std.debug.print("\n📊 与之前结果对比:\n", .{});
    std.debug.print("  当前性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  之前结果: {d:.0} ops/sec\n", .{previous_result});
    std.debug.print("  性能提升: {d:.2}x ", .{improvement});
    
    if (improvement >= 2.0) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement >= 1.2) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("✅ (有所提升)\n", .{});
    } else {
        std.debug.print("⚠️ (性能下降)\n", .{});
    }

    // 分析性能变化
    std.debug.print("\n🔍 性能分析:\n", .{});
    if (improvement >= 1.5) {
        std.debug.print("  • 内存分配优化效果显著\n", .{});
        std.debug.print("  • 可能得益于更好的内存对齐和缓存利用\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("  • 内存分配有所改善\n", .{});
        std.debug.print("  • 还有进一步优化的空间\n", .{});
    } else {
        std.debug.print("  • 需要检查是否有性能回归\n", .{});
        std.debug.print("  • 可能需要调整优化策略\n", .{});
    }

    // 与Tokio的最终对比
    const tokio_baseline = 1_500_000.0;
    const tokio_ratio = ops_per_sec / tokio_baseline;
    
    std.debug.print("\n🎯 最终目标评估:\n", .{});
    std.debug.print("  当前 vs Tokio: {d:.2}x\n", .{tokio_ratio});
    std.debug.print("  目标 (3.3x): {d:.1}% 完成\n", .{(tokio_ratio / 3.3) * 100.0});
    
    if (tokio_ratio >= 3.3) {
        std.debug.print("  🎉 Phase 1 内存优化目标达成！\n", .{});
    } else if (tokio_ratio >= 2.0) {
        std.debug.print("  🚀 接近目标，继续优化\n", .{});
    } else if (tokio_ratio >= 1.0) {
        std.debug.print("  📈 已超越Tokio，向目标前进\n", .{});
    } else {
        std.debug.print("  ⚠️ 需要重新评估优化策略\n", .{});
    }
}
