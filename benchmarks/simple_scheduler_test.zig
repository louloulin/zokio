//! 🚀 简化的Zokio调度器性能测试
//!
//! 专注于测试工作窃取队列的基础性能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 简化调度器性能测试 ===\n\n", .{});

    // 测试1: 工作窃取队列性能
    try testWorkStealingQueuePerformance(allocator);

    // 测试2: 调度器基础性能
    try testSchedulerBasicPerformance(allocator);

    // 测试3: 与目标性能对比
    try testPerformanceComparison(allocator);

    std.debug.print("\n=== 🎉 简化调度器测试完成 ===\n", .{});
}

/// 测试工作窃取队列性能
fn testWorkStealingQueuePerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 测试1: 工作窃取队列性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const TestItem = struct {
        value: u32,
    };

    const QueueType = zokio.scheduler.WorkStealingQueue(*TestItem, 1024);
    var queue = QueueType.init();

    // 创建测试项目
    const item_count = 100000;
    const items = try allocator.alloc(TestItem, item_count);
    defer allocator.free(items);

    for (items, 0..) |*item, i| {
        item.value = @intCast(i);
    }

    std.debug.print("✅ 工作窃取队列初始化成功\n", .{});
    std.debug.print("  队列容量: {}\n", .{QueueType.CAPACITY});

    // 测试推入性能
    std.debug.print("\n🚀 测试推入性能 ({} 项目)...\n", .{item_count});

    const push_start = std.time.nanoTimestamp();

    var pushed_count: u32 = 0;
    for (items) |*item| {
        if (queue.push(item)) {
            pushed_count += 1;
        } else {
            break; // 队列满了
        }
    }

    const push_end = std.time.nanoTimestamp();
    const push_duration = @as(f64, @floatFromInt(push_end - push_start)) / 1_000_000_000.0;
    const push_ops_per_sec = @as(f64, @floatFromInt(pushed_count)) / push_duration;

    std.debug.print("  推入项目数: {}\n", .{pushed_count});
    std.debug.print("  推入耗时: {d:.3} 秒\n", .{push_duration});
    std.debug.print("  推入吞吐量: {d:.0} ops/sec\n", .{push_ops_per_sec});

    // 测试弹出性能
    std.debug.print("\n🔄 测试弹出性能...\n", .{});

    const pop_start = std.time.nanoTimestamp();

    var popped_count: u32 = 0;
    while (queue.pop() != null) {
        popped_count += 1;
    }

    const pop_end = std.time.nanoTimestamp();
    const pop_duration = @as(f64, @floatFromInt(pop_end - pop_start)) / 1_000_000_000.0;
    const pop_ops_per_sec = @as(f64, @floatFromInt(popped_count)) / pop_duration;

    std.debug.print("  弹出项目数: {}\n", .{popped_count});
    std.debug.print("  弹出耗时: {d:.3} 秒\n", .{pop_duration});
    std.debug.print("  弹出吞吐量: {d:.0} ops/sec\n", .{pop_ops_per_sec});

    // 重新填充队列进行窃取测试
    for (0..@min(items.len, QueueType.CAPACITY)) |i| {
        _ = queue.push(&items[i]);
    }

    // 测试窃取性能
    std.debug.print("\n🏃 测试窃取性能...\n", .{});

    const steal_start = std.time.nanoTimestamp();

    var stolen_count: u32 = 0;
    while (queue.steal() != null) {
        stolen_count += 1;
    }

    const steal_end = std.time.nanoTimestamp();
    const steal_duration = @as(f64, @floatFromInt(steal_end - steal_start)) / 1_000_000_000.0;
    const steal_ops_per_sec = @as(f64, @floatFromInt(stolen_count)) / steal_duration;

    std.debug.print("  窃取项目数: {}\n", .{stolen_count});
    std.debug.print("  窃取耗时: {d:.3} 秒\n", .{steal_duration});
    std.debug.print("  窃取吞吐量: {d:.0} ops/sec\n", .{steal_ops_per_sec});

    std.debug.print("\n📊 工作窃取队列综合性能:\n", .{});
    std.debug.print("  平均吞吐量: {d:.0} ops/sec\n", .{(push_ops_per_sec + pop_ops_per_sec + steal_ops_per_sec) / 3.0});
}

/// 测试调度器基础性能
fn testSchedulerBasicPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔧 测试2: 调度器基础性能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 4,
        .queue_capacity = 256,
        .enable_work_stealing = true,
        .enable_statistics = true,
    };

    const SchedulerType = zokio.scheduler.Scheduler(config);
    var scheduler = SchedulerType.init();

    std.debug.print("✅ 调度器初始化成功\n", .{});
    std.debug.print("  工作线程数: {}\n", .{SchedulerType.WORKER_COUNT});
    std.debug.print("  队列容量: {}\n", .{SchedulerType.QUEUE_CAPACITY});

    // 创建简化的测试任务
    const task_count = 50000; // 减少任务数量
    const tasks = try allocator.alloc(zokio.scheduler.Task, task_count);
    defer allocator.free(tasks);

    // 简化的任务虚函数表
    const SimpleTaskVTable = zokio.scheduler.Task.TaskVTable{
        .poll = simpleTaskPoll,
        .drop = simpleTaskDrop,
    };

    // 初始化任务
    for (tasks, 0..) |*task, i| {
        task.* = zokio.scheduler.Task{
            .id = zokio.future.TaskId.generate(),
            .future_ptr = @ptrFromInt(i),
            .vtable = &SimpleTaskVTable,
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

    std.debug.print("\n📊 调度器基础性能结果:\n", .{});
    std.debug.print("  总任务数: {}\n", .{task_count});
    std.debug.print("  总耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  调度吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  平均延迟: {d:.2} μs\n", .{(duration * 1_000_000.0) / @as(f64, @floatFromInt(task_count))});

    // 获取统计信息
    const stats = scheduler.getStats();
    std.debug.print("\n📊 调度器统计:\n", .{});
    std.debug.print("  任务执行数: {}\n", .{stats.tasks_executed});
    std.debug.print("  窃取尝试数: {}\n", .{stats.steals_attempted});
    std.debug.print("  窃取成功数: {}\n", .{stats.steals_successful});
    if (stats.steals_attempted > 0) {
        std.debug.print("  窃取成功率: {d:.1}%\n", .{stats.stealSuccessRate() * 100.0});
    }
    std.debug.print("  LIFO命中数: {}\n", .{stats.lifo_hits});
    if (stats.tasks_executed > 0) {
        std.debug.print("  LIFO命中率: {d:.1}%\n", .{stats.lifoHitRate() * 100.0});
    }
    std.debug.print("  活跃工作线程: {}\n", .{stats.active_workers});
}

/// 与目标性能对比
fn testPerformanceComparison(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🎯 测试3: 与目标性能对比\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // Phase 1 调度器目标：2M ops/sec
    const target_performance = 2_000_000.0;
    const tokio_baseline = 1_500_000.0; // Tokio基准

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 8,
        .queue_capacity = 512,
        .enable_work_stealing = true,
        .enable_lifo_slot = true,
        .enable_statistics = true,
    };

    const SchedulerType = zokio.scheduler.Scheduler(config);
    var scheduler = SchedulerType.init();

    std.debug.print("✅ 高性能调度器配置\n", .{});
    std.debug.print("  工作线程数: {}\n", .{SchedulerType.WORKER_COUNT});
    std.debug.print("  队列容量: {}\n", .{SchedulerType.QUEUE_CAPACITY});

    // 创建大规模测试任务
    const task_count = 200000; // 20万任务
    const tasks = try allocator.alloc(zokio.scheduler.Task, task_count);
    defer allocator.free(tasks);

    // 简化的任务虚函数表
    const HighPerfTaskVTable = zokio.scheduler.Task.TaskVTable{
        .poll = simpleTaskPoll,
        .drop = simpleTaskDrop,
    };

    // 初始化任务
    for (tasks, 0..) |*task, i| {
        task.* = zokio.scheduler.Task{
            .id = zokio.future.TaskId.generate(),
            .future_ptr = @ptrFromInt(i),
            .vtable = &HighPerfTaskVTable,
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
    if (stats.steals_attempted > 0) {
        std.debug.print("  窃取效率: {d:.1}%\n", .{stats.stealSuccessRate() * 100.0});
    }
    if (stats.tasks_executed > 0) {
        std.debug.print("  LIFO效率: {d:.1}%\n", .{stats.lifoHitRate() * 100.0});
    }
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

// 简化的任务函数
fn simpleTaskPoll(ptr: *anyopaque, ctx: *zokio.future.Context) zokio.future.Poll(void) {
    _ = ptr;
    _ = ctx;
    return .ready; // 简化实现：任务立即完成
}

fn simpleTaskDrop(ptr: *anyopaque) void {
    _ = ptr;
    // 简化实现：无需清理
}
