//! Zokio 内存分配性能专项测试
//!
//! 目标：验证高性能分配器是否达到5M+ ops/sec的目标

const std = @import("std");
const zokio = @import("zokio");
const ZokioAllocator = zokio.memory.ZokioAllocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== Zokio 内存分配性能专项测试 ===\n\n", .{});

    // 测试1: 基础分配性能对比
    try testBasicAllocationPerformance(base_allocator);

    // 测试2: 小对象分配性能
    try testSmallObjectAllocation(base_allocator);

    // 测试3: 中等对象分配性能
    try testMediumObjectAllocation(base_allocator);

    // 测试4: 混合负载性能测试
    try testMixedWorkloadPerformance(base_allocator);

    // 测试5: 与Tokio对比的等效测试
    try testTokioEquivalentWorkload(base_allocator);

    std.debug.print("\n=== 内存分配性能测试完成 ===\n", .{});
}

/// 测试基础分配性能对比
fn testBasicAllocationPerformance(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 基础分配性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 1_000_000; // 100万次分配

    // 测试标准分配器性能
    std.debug.print("测试标准分配器性能...\n", .{});
    const std_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64 + (i % 192); // 64-256字节
        const memory = try base_allocator.alloc(u8, size);
        defer base_allocator.free(memory);

        // 简单的内存使用
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const std_end = std.time.nanoTimestamp();
    const std_duration = @as(f64, @floatFromInt(std_end - std_start)) / 1_000_000_000.0;
    const std_ops_per_sec = @as(f64, @floatFromInt(iterations)) / std_duration;

    // 测试Zokio高性能分配器
    std.debug.print("测试Zokio高性能分配器...\n", .{});
    var zokio_allocator = try ZokioAllocator.init(base_allocator);
    defer zokio_allocator.deinit();

    const zokio_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64 + (i % 192); // 64-256字节
        const memory = try zokio_allocator.alloc(size, 8);
        defer zokio_allocator.free(memory);

        // 简单的内存使用
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const zokio_end = std.time.nanoTimestamp();
    const zokio_duration = @as(f64, @floatFromInt(zokio_end - zokio_start)) / 1_000_000_000.0;
    const zokio_ops_per_sec = @as(f64, @floatFromInt(iterations)) / zokio_duration;

    // 输出结果
    std.debug.print("\n📊 基础分配性能对比结果:\n", .{});
    std.debug.print("  标准分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{std_duration});

    std.debug.print("  Zokio分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{zokio_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{zokio_duration});

    const improvement = zokio_ops_per_sec / std_ops_per_sec;
    std.debug.print("  性能提升: {d:.2}x ", .{improvement});
    if (improvement >= 1.0) {
        std.debug.print("✅\n", .{});
    } else {
        std.debug.print("❌\n", .{});
    }

    // 检查是否达到目标
    const target_ops_per_sec = 5_000_000.0; // 5M ops/sec目标
    std.debug.print("  目标达成: {d:.0} / {d:.0} ops/sec ", .{ zokio_ops_per_sec, target_ops_per_sec });
    if (zokio_ops_per_sec >= target_ops_per_sec) {
        std.debug.print("✅ 目标达成！\n", .{});
    } else {
        const progress = (zokio_ops_per_sec / target_ops_per_sec) * 100.0;
        std.debug.print("⚠️ 进度: {d:.1}%\n", .{progress});
    }
}

/// 测试小对象分配性能
fn testSmallObjectAllocation(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n💾 测试2: 小对象分配性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var zokio_allocator = try ZokioAllocator.init(base_allocator);
    defer zokio_allocator.deinit();

    const iterations = 2_000_000; // 200万次小对象分配
    const small_sizes = [_]usize{ 8, 16, 32, 64, 128, 256 };

    std.debug.print("测试小对象分配 (8B-256B)...\n", .{});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = small_sizes[i % small_sizes.len];
        const memory = try zokio_allocator.alloc(size, 8);
        defer zokio_allocator.free(memory);

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

    // 获取分配器统计信息
    const stats = zokio_allocator.getStats();
    const total_allocs = stats.total_allocations.load(.monotonic);
    const avg_alloc_time = if (total_allocs > 0)
        stats.total_allocation_time.load(.monotonic) / total_allocs
    else
        0;

    std.debug.print("  总分配次数: {}\n", .{total_allocs});
    std.debug.print("  平均分配时间: {} ns\n", .{avg_alloc_time});
}

/// 测试中等对象分配性能
fn testMediumObjectAllocation(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔧 测试3: 中等对象分配性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var zokio_allocator = try ZokioAllocator.init(base_allocator);
    defer zokio_allocator.deinit();

    const iterations = 500_000; // 50万次中等对象分配
    const medium_sizes = [_]usize{ 512, 1024, 2048, 4096, 8192, 16384 };

    std.debug.print("测试中等对象分配 (512B-16KB)...\n", .{});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = medium_sizes[i % medium_sizes.len];
        const memory = try zokio_allocator.alloc(size, 64);
        defer zokio_allocator.free(memory);

        // 验证内存可用性和对齐
        const addr = @intFromPtr(memory.ptr);
        if (addr % 64 != 0) {
            std.debug.print("警告: 内存未正确对齐到64字节边界\n", .{});
        }

        // 写入测试数据
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 中等对象分配性能结果:\n", .{});
    std.debug.print("  分配次数: {}\n", .{iterations});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});
}

/// 测试混合负载性能
fn testMixedWorkloadPerformance(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试4: 混合负载性能测试\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var zokio_allocator = try ZokioAllocator.init(base_allocator);
    defer zokio_allocator.deinit();

    const iterations = 1_000_000; // 100万次混合分配

    std.debug.print("测试混合负载 (8B-64KB)...\n", .{});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        // 模拟真实应用的混合分配模式
        const size = switch (i % 10) {
            0...6 => 32 + (i % 224), // 70% 小对象 (32-256B)
            7...8 => 512 + (i % 3584), // 20% 中等对象 (512B-4KB)
            9 => 8192 + (i % 57344), // 10% 大对象 (8KB-64KB)
            else => unreachable,
        };

        const memory = try zokio_allocator.alloc(size, 8);
        defer zokio_allocator.free(memory);

        // 模拟实际使用
        if (memory.len >= 4) {
            const value = @as(u32, @intCast(i));
            std.mem.writeInt(u32, memory[0..4], value, .little);
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 混合负载性能结果:\n", .{});
    std.debug.print("  分配次数: {}\n", .{iterations});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});
}

/// 测试与Tokio等效的工作负载
fn testTokioEquivalentWorkload(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🦀 测试5: 与Tokio等效工作负载对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var zokio_allocator = try ZokioAllocator.init(base_allocator);
    defer zokio_allocator.deinit();

    const iterations = 5000; // 与之前的对比测试保持一致

    std.debug.print("执行与Tokio等效的内存分配模式...\n", .{});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        // 模拟Tokio测试中的分配模式
        const size = 1024 + (i % 4096); // 1KB-5KB
        const memory = try zokio_allocator.alloc(size, 8);
        defer zokio_allocator.free(memory);

        // 初始化内存（与Tokio测试相同）
        @memset(memory, 0);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    // 与之前的Tokio基准数据对比
    const tokio_baseline = 1_500_000.0; // Tokio基准: 1.5M ops/sec
    const improvement = ops_per_sec / tokio_baseline;

    std.debug.print("\n📊 与Tokio等效工作负载对比:\n", .{});
    std.debug.print("  Zokio吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
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

    std.debug.print("  目标达成度: {d:.1}% (目标: 3.3x)\n", .{(improvement / 3.3) * 100.0});
}
