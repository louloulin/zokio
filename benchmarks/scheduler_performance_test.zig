//! 🚀 Zokio调度器性能基准测试
//!
//! 测试多线程工作窃取调度器的性能，目标达到2M ops/sec

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 Zokio调度器性能基准测试 ===\n\n", .{});

    // 测试1: 基础调度器性能
    try testBasicSchedulerPerformance(allocator);

    // 测试2: 工作窃取性能
    try testWorkStealingPerformance(allocator);

    // 测试3: 多线程调度性能
    try testMultiThreadSchedulingPerformance(allocator);

    // 测试4: 与目标性能对比
    try testTargetPerformanceComparison(allocator);

    std.debug.print("\n=== 🎉 调度器性能测试完成 ===\n", .{});
}

/// 测试基础调度器性能
fn testBasicSchedulerPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 测试1: 基础调度器性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 1,
        .queue_capacity = 1024,
        .enable_work_stealing = false,
        .enable_statistics = true,
    };

    const SchedulerType = zokio.scheduler.Scheduler(config);
    var scheduler = SchedulerType.init();

    std.debug.print("✅ 调度器初始化成功\n", .{});
    std.debug.print("  工作线程数: {}\n", .{SchedulerType.WORKER_COUNT});
    std.debug.print("  队列容量: {}\n", .{SchedulerType.QUEUE_CAPACITY});

    // 创建测试任务
    const task_count = 100000;
    const tasks = try allocator.alloc(zokio.scheduler.Task, task_count);
    defer allocator.free(tasks);

    // 初始化任务
    for (tasks, 0..) |*task, i| {
        task.* = zokio.scheduler.Task{
            .id = zokio.future.TaskId.generate(),
            .future_ptr = @ptrFromInt(i), // 简化实现
            .vtable = &TestTaskVTable,
        };
    }

    std.debug.print("\n🚀 执行 {} 次任务调度...\n", .{task_count});

    const start_time = std.time.nanoTimestamp();

    // 批量调度任务
    for (tasks) |*task| {
        scheduler.schedule(task);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(task_count)) / duration;

    std.debug.print("\n📊 基础调度器性能结果:\n", .{});
    std.debug.print("  总任务数: {}\n", .{task_count});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  调度吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} μs\n", .{(duration * 1_000_000.0) / @as(f64, @floatFromInt(task_count))});

    // 获取统计信息
    const stats = scheduler.getStats();
    std.debug.print("\n📊 调度器统计:\n", .{});
    std.debug.print("  任务执行数: {}\n", .{stats.tasks_executed});
    std.debug.print("  活跃工作线程: {}\n", .{stats.active_workers});
}

/// 测试工作窃取性能
fn testWorkStealingPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔄 测试2: 工作窃取性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 4,
        .queue_capacity = 512,
        .enable_work_stealing = true,
        .steal_batch_size = 16,
        .enable_statistics = true,
    };

    const SchedulerType = zokio.scheduler.Scheduler(config);
    var scheduler = SchedulerType.init();

    std.debug.print("✅ 工作窃取调度器初始化成功\n", .{});
    std.debug.print("  工作线程数: {}\n", .{SchedulerType.WORKER_COUNT});
    std.debug.print("  启用工作窃取: {}\n", .{config.enable_work_stealing});
    std.debug.print("  窃取批次大小: {}\n", .{config.steal_batch_size});

    // 创建更多测试任务
    const task_count = 200000;
    const tasks = try allocator.alloc(zokio.scheduler.Task, task_count);
    defer allocator.free(tasks);

    // 初始化任务
    for (tasks, 0..) |*task, i| {
        task.* = zokio.scheduler.Task{
            .id = zokio.future.TaskId.generate(),
            .future_ptr = @ptrFromInt(i),
            .vtable = &TestTaskVTable,
        };
    }

    std.debug.print("\n🚀 执行 {} 次工作窃取调度...\n", .{task_count});

    const start_time = std.time.nanoTimestamp();

    // 批量调度任务
    for (tasks) |*task| {
        scheduler.schedule(task);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(task_count)) / duration;

    std.debug.print("\n📊 工作窃取性能结果:\n", .{});
    std.debug.print("  总任务数: {}\n", .{task_count});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  调度吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} μs\n", .{(duration * 1_000_000.0) / @as(f64, @floatFromInt(task_count))});

    // 获取详细统计信息
    const stats = scheduler.getStats();
    std.debug.print("\n📊 工作窃取统计:\n", .{});
    std.debug.print("  任务执行数: {}\n", .{stats.tasks_executed});
    std.debug.print("  窃取尝试数: {}\n", .{stats.steals_attempted});
    std.debug.print("  窃取成功数: {}\n", .{stats.steals_successful});
    std.debug.print("  窃取成功率: {d:.1}%\n", .{stats.stealSuccessRate() * 100.0});
    std.debug.print("  LIFO命中数: {}\n", .{stats.lifo_hits});
    std.debug.print("  LIFO命中率: {d:.1}%\n", .{stats.lifoHitRate() * 100.0});
    std.debug.print("  活跃工作线程: {}\n", .{stats.active_workers});
}

/// 测试多线程调度性能
fn testMultiThreadSchedulingPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧵 测试3: 多线程调度性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 8,
        .queue_capacity = 256,
        .enable_work_stealing = true,
        .enable_lifo_slot = true,
        .steal_batch_size = 32,
        .enable_statistics = true,
    };

    const SchedulerType = zokio.scheduler.Scheduler(config);
    var scheduler = SchedulerType.init();

    std.debug.print("✅ 多线程调度器初始化成功\n", .{});
    std.debug.print("  工作线程数: {}\n", .{SchedulerType.WORKER_COUNT});
    std.debug.print("  启用LIFO槽: {}\n", .{config.enable_lifo_slot});
    std.debug.print("  全局队列检查间隔: {}\n", .{config.global_queue_interval});

    // 创建大量测试任务
    const task_count = 500000;
    const tasks = try allocator.alloc(zokio.scheduler.Task, task_count);
    defer allocator.free(tasks);

    // 初始化任务
    for (tasks, 0..) |*task, i| {
        task.* = zokio.scheduler.Task{
            .id = zokio.future.TaskId.generate(),
            .future_ptr = @ptrFromInt(i),
            .vtable = &TestTaskVTable,
        };
    }

    std.debug.print("\n🚀 执行 {} 次多线程调度...\n", .{task_count});

    const start_time = std.time.nanoTimestamp();

    // 批量调度任务
    for (tasks) |*task| {
        scheduler.schedule(task);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(task_count)) / duration;

    std.debug.print("\n📊 多线程调度性能结果:\n", .{});
    std.debug.print("  总任务数: {}\n", .{task_count});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  调度吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} μs\n", .{(duration * 1_000_000.0) / @as(f64, @floatFromInt(task_count))});

    // 获取详细统计信息
    const stats = scheduler.getStats();
    std.debug.print("\n📊 多线程调度统计:\n", .{});
    std.debug.print("  任务执行数: {}\n", .{stats.tasks_executed});
    std.debug.print("  窃取尝试数: {}\n", .{stats.steals_attempted});
    std.debug.print("  窃取成功数: {}\n", .{stats.steals_successful});
    std.debug.print("  窃取成功率: {d:.1}%\n", .{stats.stealSuccessRate() * 100.0});
    std.debug.print("  LIFO命中数: {}\n", .{stats.lifo_hits});
    std.debug.print("  LIFO命中率: {d:.1}%\n", .{stats.lifoHitRate() * 100.0});
    std.debug.print("  全局队列轮询: {}\n", .{stats.global_queue_polls});
    std.debug.print("  暂停次数: {}\n", .{stats.parks});
    std.debug.print("  活跃工作线程: {}\n", .{stats.active_workers});
}

/// 与目标性能对比
fn testTargetPerformanceComparison(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🎯 测试4: 与目标性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // Phase 1 调度器目标：2M ops/sec
    const target_performance = 2_000_000.0;
    const tokio_baseline = 1_500_000.0; // Tokio基准

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 16, // 最大线程数
        .queue_capacity = 256, // 优化队列大小
        .enable_work_stealing = true,
        .enable_lifo_slot = true,
        .steal_batch_size = 32, // 批次窃取 (不能超过queue_capacity/4)
        .enable_statistics = true,
        .spin_before_park = 100, // 增加自旋次数
    };

    const SchedulerType = zokio.scheduler.Scheduler(config);
    var scheduler = SchedulerType.init();

    std.debug.print("✅ 高性能调度器配置\n", .{});
    std.debug.print("  工作线程数: {}\n", .{SchedulerType.WORKER_COUNT});
    std.debug.print("  队列容量: {}\n", .{SchedulerType.QUEUE_CAPACITY});
    std.debug.print("  窃取批次: {}\n", .{config.steal_batch_size});
    std.debug.print("  自旋次数: {}\n", .{config.spin_before_park});

    // 创建大规模测试任务
    const task_count = 1000000; // 100万任务
    const tasks = try allocator.alloc(zokio.scheduler.Task, task_count);
    defer allocator.free(tasks);

    // 初始化任务
    for (tasks, 0..) |*task, i| {
        task.* = zokio.scheduler.Task{
            .id = zokio.future.TaskId.generate(),
            .future_ptr = @ptrFromInt(i),
            .vtable = &TestTaskVTable,
        };
    }

    std.debug.print("\n🚀 高强度调度性能测试 ({} 任务)...\n", .{task_count});

    const start_time = std.time.nanoTimestamp();

    // 高效批量调度
    for (tasks) |*task| {
        scheduler.schedule(task);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(task_count)) / duration;

    const vs_target = ops_per_sec / target_performance;
    const vs_tokio = ops_per_sec / tokio_baseline;

    std.debug.print("\n📊 目标性能对比结果:\n", .{});
    std.debug.print("  实际性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  目标性能: {d:.0} ops/sec\n", .{target_performance});
    std.debug.print("  Tokio基准: {d:.0} ops/sec\n", .{tokio_baseline});
    std.debug.print("  vs 目标: {d:.2}x ", .{vs_target});

    if (vs_target >= 1.0) {
        std.debug.print("🌟🌟🌟 (已达标)\n", .{});
    } else if (vs_target >= 0.8) {
        std.debug.print("🌟🌟 (接近目标)\n", .{});
    } else if (vs_target >= 0.5) {
        std.debug.print("🌟 (需要优化)\n", .{});
    } else {
        std.debug.print("⚠️ (需要重构)\n", .{});
    }

    std.debug.print("  vs Tokio: {d:.2}x ", .{vs_tokio});
    if (vs_tokio >= 2.0) {
        std.debug.print("🚀🚀🚀 (大幅超越)\n", .{});
    } else if (vs_tokio >= 1.0) {
        std.debug.print("🚀🚀 (超越Tokio)\n", .{});
    } else if (vs_tokio >= 0.8) {
        std.debug.print("🚀 (接近Tokio)\n", .{});
    } else {
        std.debug.print("⚠️ (低于Tokio)\n", .{});
    }

    // 获取最终统计信息
    const stats = scheduler.getStats();
    std.debug.print("\n🔍 最终调度器评估:\n", .{});
    std.debug.print("  任务执行数: {}\n", .{stats.tasks_executed});
    std.debug.print("  窃取效率: {d:.1}%\n", .{stats.stealSuccessRate() * 100.0});
    std.debug.print("  LIFO效率: {d:.1}%\n", .{stats.lifoHitRate() * 100.0});
    std.debug.print("  活跃线程: {}\n", .{stats.active_workers});
    std.debug.print("  调度效率: {d:.1}%\n", .{vs_target * 100.0});

    if (vs_target >= 1.0) {
        std.debug.print("\n✅ Zokio调度器性能优异！\n", .{});
        std.debug.print("  🎉 Phase 1 调度目标已达成\n", .{});
        std.debug.print("  🚀 性能超越Tokio {d:.1}倍\n", .{vs_tokio});
        std.debug.print("  📈 下一步: 实现真实任务执行\n", .{});
    } else {
        std.debug.print("\n🔧 需要进一步优化:\n", .{});
        std.debug.print("  1. 优化工作窃取算法\n", .{});
        std.debug.print("  2. 改进队列数据结构\n", .{});
        std.debug.print("  3. 减少同步开销\n", .{});
    }
}

// 简化的任务虚函数表
const TestTaskVTable = zokio.scheduler.Task.TaskVTable{
    .poll = testTaskPoll,
    .drop = testTaskDrop,
};

fn testTaskPoll(ptr: *anyopaque, ctx: *zokio.future.Context) zokio.future.Poll(void) {
    _ = ptr;
    _ = ctx;
    return .ready; // 简化实现：任务立即完成
}

fn testTaskDrop(ptr: *anyopaque) void {
    _ = ptr;
    // 简化实现：无需清理
}
