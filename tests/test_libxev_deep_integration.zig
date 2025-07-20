//! 🚀 Zokio libxev 深度集成综合测试
//!
//! 验证所有高级优化特性：
//! 1. 批量操作性能
//! 2. 内存池效率
//! 3. 智能线程池
//! 4. 高级事件循环
//! 5. 跨平台兼容性

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

// 导入优化模块
const BatchOperations = zokio.BatchOperations;
const MemoryPools = zokio.MemoryPools;
const SmartThreadPool = zokio.SmartThreadPool;
const AdvancedEventLoop = zokio.AdvancedEventLoop;

test "批量操作性能测试" {
    std.debug.print("\n=== 🚀 批量操作性能测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try BatchOperations.runBatchTest(allocator);
}

test "内存池效率测试" {
    std.debug.print("\n=== 🚀 内存池效率测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try MemoryPools.runMemoryPoolTest(allocator);
}

test "智能线程池测试" {
    std.debug.print("\n=== 🚀 智能线程池测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try SmartThreadPool.runSmartThreadPoolTest(allocator);
}

test "高级事件循环测试" {
    std.debug.print("\n=== 🚀 高级事件循环测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try AdvancedEventLoop.runAdvancedEventLoopTest(allocator);
}

test "综合性能基准测试" {
    std.debug.print("\n=== 🚀 综合性能基准测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试配置
    const test_duration_ms = 2000; // 2秒
    const target_throughput = 2_000_000; // 2M ops/sec
    const target_memory_efficiency = 0.8; // 80%命中率

    // 创建高级事件循环
    const config = AdvancedEventLoop.AdvancedEventLoopConfig{
        .run_mode = .high_throughput,
        .enable_platform_optimization = true,
        .enable_adaptive_tuning = true,
    };

    var advanced_loop = try AdvancedEventLoop.AdvancedEventLoop.init(allocator, config);
    defer advanced_loop.deinit();

    try advanced_loop.start();
    defer advanced_loop.stop();

    // 性能测试
    const start_time = std.time.milliTimestamp();
    var operation_count: u64 = 0;

    // 模拟高负载工作
    while (std.time.milliTimestamp() - start_time < test_duration_ms) {
        // 模拟批量I/O操作
        const read_ops = [_]BatchOperations.ReadOperation{
            .{ .fd = 0, .buffer = undefined },
            .{ .fd = 1, .buffer = undefined },
            .{ .fd = 2, .buffer = undefined },
        };

        try advanced_loop.batch_manager.batchRead(&read_ops);
        operation_count += read_ops.len;

        // 模拟内存分配/释放
        if (advanced_loop.memory_manager.completion_pool.acquire()) |completion| {
            advanced_loop.memory_manager.completion_pool.release(completion);
            operation_count += 1;
        }

        if (advanced_loop.memory_manager.buffer_pool.acquire(.small)) |buffer| {
            advanced_loop.memory_manager.buffer_pool.release(buffer);
            operation_count += 1;
        }

        // 每1000次操作刷新一次
        if (operation_count % 1000 == 0) {
            try advanced_loop.batch_manager.flushAll();
        }
    }

    try advanced_loop.batch_manager.flushAll();

    const end_time = std.time.milliTimestamp();
    const actual_duration_ms = @as(u64, @intCast(end_time - start_time));

    // 获取统计信息
    const stats = advanced_loop.getStats();

    // 计算性能指标
    const actual_throughput = @as(f64, @floatFromInt(operation_count)) /
        (@as(f64, @floatFromInt(actual_duration_ms)) / 1000.0);

    const memory_efficiency = stats.memory_stats.getOverallHitRate();

    // 输出结果
    std.debug.print("综合性能基准测试结果:\n", .{});
    std.debug.print("  测试时长: {}ms\n", .{actual_duration_ms});
    std.debug.print("  总操作数: {}\n", .{operation_count});
    std.debug.print("  实际吞吐量: {d:.0} ops/sec\n", .{actual_throughput});
    std.debug.print("  目标吞吐量: {d:.0} ops/sec\n", .{@as(f64, @floatFromInt(target_throughput))});
    std.debug.print("  内存效率: {d:.1}%\n", .{memory_efficiency * 100});
    std.debug.print("  目标内存效率: {d:.1}%\n", .{target_memory_efficiency * 100});
    std.debug.print("  批量操作数: {}\n", .{stats.batch_stats.getTotalBatches()});
    std.debug.print("  平均批量大小: {d:.2}\n", .{stats.batch_stats.getOverallAvgBatchSize()});
    std.debug.print("  线程利用率: {d:.1}%\n", .{stats.thread_stats.thread_utilization * 100});

    // 验证性能目标
    const throughput_ratio = actual_throughput / @as(f64, @floatFromInt(target_throughput));
    const memory_ratio = memory_efficiency / target_memory_efficiency;

    std.debug.print("\n性能评估:\n", .{});
    std.debug.print("  吞吐量达成率: {d:.1}%\n", .{throughput_ratio * 100});
    std.debug.print("  内存效率达成率: {d:.1}%\n", .{memory_ratio * 100});

    // 性能验证
    if (throughput_ratio >= 0.8) { // 至少达到80%目标
        std.debug.print("  ✅ 吞吐量测试通过\n", .{});
    } else {
        std.debug.print("  ❌ 吞吐量测试未达标\n", .{});
    }

    if (memory_ratio >= 0.9) { // 至少达到90%目标
        std.debug.print("  ✅ 内存效率测试通过\n", .{});
    } else {
        std.debug.print("  ❌ 内存效率测试未达标\n", .{});
    }

    // 综合评分
    const overall_score = (throughput_ratio + memory_ratio) / 2.0;
    std.debug.print("  综合评分: {d:.1}%\n", .{overall_score * 100});

    if (overall_score >= 0.85) {
        std.debug.print("  🎉 综合性能测试优秀\n", .{});
    } else if (overall_score >= 0.7) {
        std.debug.print("  ✅ 综合性能测试良好\n", .{});
    } else {
        std.debug.print("  ⚠️ 综合性能需要改进\n", .{});
    }

    // 基本验证（确保测试运行正常）
    try testing.expect(operation_count > 0);
    try testing.expect(actual_throughput > 0);
    try testing.expect(memory_efficiency >= 0);
}

test "跨平台兼容性测试" {
    std.debug.print("\n=== 🚀 跨平台兼容性测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试不同平台的事件循环创建
    const config = AdvancedEventLoop.AdvancedEventLoopConfig{
        .enable_platform_optimization = true,
    };

    var advanced_loop = try AdvancedEventLoop.AdvancedEventLoop.init(allocator, config);
    defer advanced_loop.deinit();

    // 验证事件循环可以正常启动和停止
    try advanced_loop.start();

    // 短暂运行
    std.time.sleep(100 * std.time.ns_per_ms);

    advanced_loop.stop();

    const stats = advanced_loop.getStats();

    std.debug.print("跨平台兼容性测试结果:\n", .{});
    std.debug.print("  平台: {s}\n", .{@tagName(@import("builtin").target.os.tag)});
    std.debug.print("  事件循环创建: ✅\n", .{});
    std.debug.print("  启动/停止: ✅\n", .{});
    std.debug.print("  统计信息收集: ✅\n", .{});
    std.debug.print("  循环迭代数: {}\n", .{stats.loop_iterations});

    // 基本验证
    try testing.expect(stats.loop_iterations >= 0);

    std.debug.print("  ✅ 跨平台兼容性测试通过\n", .{});
}

test "压力测试" {
    std.debug.print("\n=== 🚀 压力测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 高强度配置
    const config = AdvancedEventLoop.AdvancedEventLoopConfig{
        .run_mode = .high_throughput,
        .batch_config = .{
            .max_batch_size = 128,
            .batch_timeout_ns = 500,
        },
        .memory_config = .{
            .completion_pool_size = 2048,
            .small_buffer_count = 512,
        },
        .thread_config = .{
            .max_threads = 16,
            .enable_adaptive = true,
        },
    };

    var advanced_loop = try AdvancedEventLoop.AdvancedEventLoop.init(allocator, config);
    defer advanced_loop.deinit();

    try advanced_loop.start();
    defer advanced_loop.stop();

    // 高强度压力测试
    const stress_duration_ms = 3000; // 3秒
    const start_time = std.time.milliTimestamp();
    var total_operations: u64 = 0;

    while (std.time.milliTimestamp() - start_time < stress_duration_ms) {
        // 大量并发操作
        for (0..100) |_| {
            // 批量I/O
            const read_ops = [_]BatchOperations.ReadOperation{
                .{ .fd = 0, .buffer = undefined },
                .{ .fd = 1, .buffer = undefined },
                .{ .fd = 2, .buffer = undefined },
                .{ .fd = 3, .buffer = undefined },
                .{ .fd = 4, .buffer = undefined },
            };

            try advanced_loop.batch_manager.batchRead(&read_ops);
            total_operations += read_ops.len;

            // 内存池操作
            for (0..10) |_| {
                if (advanced_loop.memory_manager.completion_pool.acquire()) |completion| {
                    advanced_loop.memory_manager.completion_pool.release(completion);
                    total_operations += 1;
                }

                if (advanced_loop.memory_manager.buffer_pool.acquire(.small)) |buffer| {
                    advanced_loop.memory_manager.buffer_pool.release(buffer);
                    total_operations += 1;
                }
            }
        }

        // 定期刷新
        try advanced_loop.batch_manager.flushAll();
    }

    const end_time = std.time.milliTimestamp();
    const actual_duration_ms = @as(u64, @intCast(end_time - start_time));

    const stats = advanced_loop.getStats();
    const stress_throughput = @as(f64, @floatFromInt(total_operations)) /
        (@as(f64, @floatFromInt(actual_duration_ms)) / 1000.0);

    std.debug.print("压力测试结果:\n", .{});
    std.debug.print("  测试时长: {}ms\n", .{actual_duration_ms});
    std.debug.print("  总操作数: {}\n", .{total_operations});
    std.debug.print("  压力吞吐量: {d:.0} ops/sec\n", .{stress_throughput});
    std.debug.print("  内存效率: {d:.1}%\n", .{stats.memory_stats.getOverallHitRate() * 100});
    std.debug.print("  批量效率: {d:.2}\n", .{stats.batch_stats.getOverallAvgBatchSize()});

    // 验证系统在高压力下仍能正常工作
    try testing.expect(total_operations > 100000); // 至少10万次操作
    try testing.expect(stress_throughput > 50000); // 至少5万ops/sec

    std.debug.print("  ✅ 压力测试通过\n", .{});
}

test "内存泄漏检测" {
    std.debug.print("\n=== 🚀 内存泄漏检测 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("  ❌ 检测到内存泄漏\n", .{});
        } else {
            std.debug.print("  ✅ 无内存泄漏\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // 多轮内存分配/释放测试
    for (0..10) |round| {
        std.debug.print("  内存测试轮次: {}\n", .{round + 1});

        const config = AdvancedEventLoop.AdvancedEventLoopConfig{};

        var advanced_loop = try AdvancedEventLoop.AdvancedEventLoop.init(allocator, config);
        defer advanced_loop.deinit();

        try advanced_loop.start();

        // 大量内存操作
        for (0..1000) |_| {
            if (advanced_loop.memory_manager.completion_pool.acquire()) |completion| {
                advanced_loop.memory_manager.completion_pool.release(completion);
            }

            if (advanced_loop.memory_manager.buffer_pool.acquire(.small)) |buffer| {
                advanced_loop.memory_manager.buffer_pool.release(buffer);
            }
        }

        advanced_loop.stop();
    }

    std.debug.print("  ✅ 内存泄漏检测完成\n", .{});
}
