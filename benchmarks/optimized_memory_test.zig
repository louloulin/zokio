//! 优化内存分配器性能测试
//!
//! 测试真正的对象池实现效果

const std = @import("std");
const zokio = @import("zokio");
const OptimizedAllocator = zokio.memory.OptimizedAllocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 优化内存分配器性能测试 ===\n\n", .{});

    // 测试1: 对象池vs标准分配器对比
    try testObjectPoolVsStandard(base_allocator);

    // 测试2: 对象复用效率测试
    try testObjectReuseEfficiency(base_allocator);

    // 测试3: 高频分配释放压力测试
    try testHighFrequencyAllocFree(base_allocator);

    // 测试4: 与Tokio等效负载测试
    try testTokioEquivalentLoad(base_allocator);

    std.debug.print("\n=== 优化内存分配器测试完成 ===\n", .{});
}

/// 测试对象池vs标准分配器性能对比
fn testObjectPoolVsStandard(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 对象池 vs 标准分配器性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const iterations = 1_000_000; // 100万次分配

    // 测试标准分配器
    std.debug.print("测试标准分配器...\n", .{});
    const std_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64; // 固定64字节
        const memory = try base_allocator.alloc(u8, size);
        defer base_allocator.free(memory);

        // 简单使用
        memory[0] = @as(u8, @intCast(i % 256));
    }

    const std_end = std.time.nanoTimestamp();
    const std_duration = @as(f64, @floatFromInt(std_end - std_start)) / 1_000_000_000.0;
    const std_ops_per_sec = @as(f64, @floatFromInt(iterations)) / std_duration;

    // 测试优化分配器
    std.debug.print("测试优化分配器...\n", .{});
    var opt_allocator = try OptimizedAllocator.init(base_allocator);
    defer opt_allocator.deinit();

    const opt_start = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 64; // 固定64字节
        const memory = try opt_allocator.alloc(size);
        defer opt_allocator.free(memory);

        // 简单使用
        memory[0] = @as(u8, @intCast(i % 256));
    }

    const opt_end = std.time.nanoTimestamp();
    const opt_duration = @as(f64, @floatFromInt(opt_end - opt_start)) / 1_000_000_000.0;
    const opt_ops_per_sec = @as(f64, @floatFromInt(iterations)) / opt_duration;

    // 输出结果
    std.debug.print("\n📊 性能对比结果:\n", .{});
    std.debug.print("  标准分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{std_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{std_duration});

    std.debug.print("  优化分配器:\n", .{});
    std.debug.print("    吞吐量: {d:.0} ops/sec\n", .{opt_ops_per_sec});
    std.debug.print("    耗时: {d:.3} 秒\n", .{opt_duration});

    const improvement = opt_ops_per_sec / std_ops_per_sec;
    std.debug.print("  性能提升: {d:.2}x ", .{improvement});
    if (improvement >= 2.0) {
        std.debug.print("🌟🌟 (显著提升)\n", .{});
    } else if (improvement >= 1.5) {
        std.debug.print("🌟 (明显提升)\n", .{});
    } else if (improvement >= 1.0) {
        std.debug.print("✅ (有所提升)\n", .{});
    } else {
        std.debug.print("⚠️ (性能下降)\n", .{});
    }

    // 获取统计信息
    const stats = opt_allocator.getStats();
    std.debug.print("  对象复用率: {d:.1}%\n", .{stats.reuse_rate * 100.0});
}

/// 测试对象复用效率
fn testObjectReuseEfficiency(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n♻️ 测试2: 对象复用效率测试\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var opt_allocator = try OptimizedAllocator.init(base_allocator);
    defer opt_allocator.deinit();

    const iterations = 100_000;
    const pool_size = 1000; // 保持1000个对象在池中

    std.debug.print("测试对象复用模式...\n", .{});

    // 第一阶段：分配对象但不立即释放
    var allocated_objects = std.ArrayList([]u8).init(base_allocator);
    defer {
        for (allocated_objects.items) |memory| {
            opt_allocator.free(memory);
        }
        allocated_objects.deinit();
    }

    for (0..pool_size) |_| {
        const memory = try opt_allocator.alloc(64);
        try allocated_objects.append(memory);
    }

    // 第二阶段：释放一半对象
    for (0..pool_size / 2) |i| {
        opt_allocator.free(allocated_objects.items[i]);
    }

    // 第三阶段：高频分配释放测试
    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const memory = try opt_allocator.alloc(64);
        memory[0] = @as(u8, @intCast(i % 256));
        opt_allocator.free(memory);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 对象复用效率结果:\n", .{});
    std.debug.print("  高频分配释放: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  耗时: {d:.3} 秒\n", .{duration});

    const stats = opt_allocator.getStats();
    std.debug.print("  最终复用率: {d:.1}%\n", .{stats.reuse_rate * 100.0});
    std.debug.print("  总分配次数: {}\n", .{stats.total_allocated});
    std.debug.print("  总复用次数: {}\n", .{stats.total_reused});

    if (stats.reuse_rate >= 0.9) {
        std.debug.print("  复用效率: 🌟🌟🌟 (优秀)\n", .{});
    } else if (stats.reuse_rate >= 0.7) {
        std.debug.print("  复用效率: 🌟🌟 (良好)\n", .{});
    } else if (stats.reuse_rate >= 0.5) {
        std.debug.print("  复用效率: 🌟 (一般)\n", .{});
    } else {
        std.debug.print("  复用效率: ⚠️ (需要改进)\n", .{});
    }
}

/// 测试高频分配释放压力
fn testHighFrequencyAllocFree(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试3: 高频分配释放压力测试\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var opt_allocator = try OptimizedAllocator.init(base_allocator);
    defer opt_allocator.deinit();

    const iterations = 2_000_000; // 200万次操作
    const sizes = [_]usize{ 8, 16, 32, 64, 128, 256 };

    std.debug.print("执行高频混合大小分配释放...\n", .{});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = sizes[i % sizes.len];
        const memory = try opt_allocator.alloc(size);

        // 模拟实际使用
        @memset(memory, @as(u8, @intCast(i % 256)));

        opt_allocator.free(memory);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 高频压力测试结果:\n", .{});
    std.debug.print("  操作次数: {}\n", .{iterations});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  平均延迟: {d:.2} ns\n", .{(duration * 1_000_000_000.0) / @as(f64, @floatFromInt(iterations))});

    const stats = opt_allocator.getStats();
    std.debug.print("  复用率: {d:.1}%\n", .{stats.reuse_rate * 100.0});

    // 检查是否达到目标
    const target_ops_per_sec = 5_000_000.0; // 5M ops/sec目标
    std.debug.print("  目标达成: {d:.0} / {d:.0} ops/sec ", .{ ops_per_sec, target_ops_per_sec });
    if (ops_per_sec >= target_ops_per_sec) {
        std.debug.print("✅ 目标达成！\n", .{});
    } else {
        const progress = (ops_per_sec / target_ops_per_sec) * 100.0;
        std.debug.print("⚠️ 进度: {d:.1}%\n", .{progress});
    }
}

/// 测试与Tokio等效负载
fn testTokioEquivalentLoad(base_allocator: std.mem.Allocator) !void {
    std.debug.print("\n🦀 测试4: 与Tokio等效负载测试\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var opt_allocator = try OptimizedAllocator.init(base_allocator);
    defer opt_allocator.deinit();

    const iterations = 5000; // 与之前保持一致

    std.debug.print("执行Tokio等效内存分配模式...\n", .{});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 1024 + (i % 4096); // 1KB-5KB
        const memory = try opt_allocator.alloc(size);
        defer opt_allocator.free(memory);

        // 初始化内存
        @memset(memory, 0);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    // 与基准数据对比
    const tokio_baseline = 1_500_000.0; // Tokio基准
    const previous_result = 229_716.0; // 之前的结果
    const tokio_ratio = ops_per_sec / tokio_baseline;
    const improvement_vs_previous = ops_per_sec / previous_result;

    std.debug.print("\n📊 Tokio等效负载测试结果:\n", .{});
    std.debug.print("  当前性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  Tokio基准: {d:.0} ops/sec\n", .{tokio_baseline});
    std.debug.print("  之前结果: {d:.0} ops/sec\n", .{previous_result});

    std.debug.print("\n🔍 性能对比分析:\n", .{});
    std.debug.print("  vs Tokio: {d:.2}x ", .{tokio_ratio});
    if (tokio_ratio >= 3.3) {
        std.debug.print("🌟🌟🌟 (超越目标)\n", .{});
    } else if (tokio_ratio >= 2.0) {
        std.debug.print("🌟🌟 (显著优于Tokio)\n", .{});
    } else if (tokio_ratio >= 1.0) {
        std.debug.print("🌟 (优于Tokio)\n", .{});
    } else {
        std.debug.print("⚠️ (低于Tokio)\n", .{});
    }

    std.debug.print("  vs 之前: {d:.2}x ", .{improvement_vs_previous});
    if (improvement_vs_previous >= 2.0) {
        std.debug.print("🚀 (大幅提升)\n", .{});
    } else if (improvement_vs_previous >= 1.5) {
        std.debug.print("📈 (明显提升)\n", .{});
    } else if (improvement_vs_previous >= 1.0) {
        std.debug.print("✅ (有所提升)\n", .{});
    } else {
        std.debug.print("⚠️ (性能下降)\n", .{});
    }

    const stats = opt_allocator.getStats();
    std.debug.print("  对象复用率: {d:.1}%\n", .{stats.reuse_rate * 100.0});
    std.debug.print("  目标完成度: {d:.1}% (目标: 3.3x Tokio)\n", .{(tokio_ratio / 3.3) * 100.0});
}
