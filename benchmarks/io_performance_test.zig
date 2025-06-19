//! I/O系统性能测试
//!
//! 验证当前I/O系统状态，为Phase 1 I/O重构提供基准

const std = @import("std");
const zokio = @import("zokio");
const IoDriver = zokio.io.IoDriver;
const IoConfig = zokio.io.IoConfig;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🔧 I/O系统性能测试 ===\n\n", .{});

    // 测试1: 基础I/O驱动性能
    try testBasicIoPerformance(allocator);

    // 测试2: libxev后端性能
    try testLibxevBackendPerformance(allocator);

    // 测试3: 批量I/O操作性能
    try testBatchIoPerformance(allocator);

    // 测试4: 与目标性能对比
    try testPerformanceTargets(allocator);

    std.debug.print("\n=== 🎉 I/O系统性能测试完成 ===\n", .{});
}

/// 测试基础I/O驱动性能
fn testBasicIoPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 测试1: 基础I/O驱动性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = IoConfig{
        .events_capacity = 1024,
        .enable_real_io = false,
    };

    var driver = try IoDriver(config).init(allocator);
    defer driver.deinit();

    const iterations = 10000;
    var buffer = [_]u8{0} ** 1024;

    std.debug.print("执行 {} 次I/O操作...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        // 模拟读操作
        const handle = try driver.submitRead(0, &buffer, 0);
        _ = handle;

        // 轮询完成
        _ = try driver.poll(0);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 基础I/O性能结果:\n", .{});
    std.debug.print("  迭代次数: {}\n", .{iterations});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} μs\n", .{(duration * 1_000_000.0) / @as(f64, @floatFromInt(iterations))});
    std.debug.print("  后端类型: {any}\n", .{@TypeOf(driver).BACKEND_TYPE});
}

/// 测试libxev后端性能
fn testLibxevBackendPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试2: libxev后端性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = IoConfig{
        .events_capacity = 1024,
        .enable_real_io = false,
    };

    var driver = try IoDriver(config).init(allocator);
    defer driver.deinit();

    const iterations = 5000; // 减少迭代次数，因为libxev可能更复杂
    var buffer = [_]u8{0} ** 1024;

    std.debug.print("执行 {} 次libxev I/O操作...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        // 模拟读操作
        const handle = try driver.submitRead(0, &buffer, 0);
        _ = handle;

        // 轮询完成
        _ = try driver.poll(1); // 1ms超时
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("\n📊 libxev性能结果:\n", .{});
    std.debug.print("  迭代次数: {}\n", .{iterations});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} μs\n", .{(duration * 1_000_000.0) / @as(f64, @floatFromInt(iterations))});
    std.debug.print("  后端类型: {any}\n", .{@TypeOf(driver).BACKEND_TYPE});
    std.debug.print("  支持批量: {}\n", .{@TypeOf(driver).SUPPORTS_BATCH});
}

/// 测试批量I/O操作性能
fn testBatchIoPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n📦 测试3: 批量I/O操作性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = IoConfig{
        .events_capacity = 1024,
        .batch_size = 32,
        .enable_real_io = false,
    };

    var driver = try IoDriver(config).init(allocator);
    defer driver.deinit();

    const batch_size = 32;
    const batch_count = 100;
    var buffer = [_]u8{0} ** 1024;

    // 准备批量操作
    var operations: [batch_size]zokio.io.IoOperation = undefined;
    for (&operations) |*op| {
        op.* = zokio.io.IoOperation{
            .op_type = .read,
            .fd = 0,
            .buffer = &buffer,
            .offset = 0,
        };
    }

    std.debug.print("执行 {} 个批次，每批次 {} 个操作...\n", .{ batch_count, batch_size });

    const start_time = std.time.nanoTimestamp();

    for (0..batch_count) |_| {
        if (@TypeOf(driver).SUPPORTS_BATCH) {
            const handles = try driver.submitBatch(&operations);
            allocator.free(handles);
        } else {
            // 如果不支持批量，逐个提交
            for (operations) |op| {
                const handle = try driver.submitRead(op.fd, op.buffer, op.offset);
                _ = handle;
            }
        }

        // 轮询完成
        _ = try driver.poll(1);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const total_ops = batch_count * batch_size;
    const ops_per_sec = @as(f64, @floatFromInt(total_ops)) / duration;

    std.debug.print("\n📊 批量I/O性能结果:\n", .{});
    std.debug.print("  总操作数: {}\n", .{total_ops});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  批量支持: {}\n", .{@TypeOf(driver).SUPPORTS_BATCH});
}

/// 测试与目标性能对比
fn testPerformanceTargets(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🎯 测试4: 与目标性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // Phase 1 I/O目标：1.2M ops/sec
    const target_performance = 1_200_000.0;

    const config = IoConfig{
        .events_capacity = 2048,
        .batch_size = 64,
        .enable_real_io = false,
    };

    var driver = try IoDriver(config).init(allocator);
    defer driver.deinit();

    const iterations = 10000;
    var buffer = [_]u8{0} ** 1024;

    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const handle = try driver.submitRead(0, &buffer, 0);
        _ = handle;
        _ = try driver.poll(0);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    const vs_target = ops_per_sec / target_performance;

    std.debug.print("\n📊 目标性能对比:\n", .{});
    std.debug.print("  当前性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  目标性能: {d:.0} ops/sec\n", .{target_performance});
    std.debug.print("  完成度: {d:.1}% ", .{vs_target * 100.0});

    if (vs_target >= 1.0) {
        std.debug.print("🌟🌟🌟 (已达标)\n", .{});
    } else if (vs_target >= 0.5) {
        std.debug.print("🌟🌟 (接近目标)\n", .{});
    } else if (vs_target >= 0.2) {
        std.debug.print("🌟 (需要优化)\n", .{});
    } else {
        std.debug.print("⚠️ (需要重构)\n", .{});
    }

    std.debug.print("\n🔍 当前I/O系统状态分析:\n", .{});
    std.debug.print("  后端类型: {any}\n", .{@TypeOf(driver).BACKEND_TYPE});
    std.debug.print("  批量支持: {}\n", .{@TypeOf(driver).SUPPORTS_BATCH});
    std.debug.print("  性能特征: {any}\n", .{@TypeOf(driver).PERFORMANCE_CHARACTERISTICS});

    if (vs_target < 0.5) {
        std.debug.print("\n🚨 需要立即进行I/O系统重构:\n", .{});
        std.debug.print("  1. 完善libxev集成\n", .{});
        std.debug.print("  2. 实现真实异步I/O\n", .{});
        std.debug.print("  3. 优化事件循环\n", .{});
        std.debug.print("  4. 添加批量I/O优化\n", .{});
    }
}
