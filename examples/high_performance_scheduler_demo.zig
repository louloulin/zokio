//! 高性能调度器演示
//! 展示Zokio的Tokio级别高性能调度器功能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 高性能调度器演示 ===\n", .{});

    // 配置高性能调度器
    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 4,
        .queue_capacity = 256,
        .enable_work_stealing = true,
        .enable_lifo_slot = true,
        .enable_statistics = true,
        .scheduling_strategy = .local_first,
        .steal_batch_size = 32,
        .global_queue_interval = 61,
        .steal_retry_count = 3,
        .spin_before_park = 10,
        .enable_numa_aware = true,
    };

    // 创建调度器
    const SchedulerType = zokio.scheduler.Scheduler(config);
    var scheduler = SchedulerType.init();

    std.debug.print("调度器初始化成功\n", .{});
    std.debug.print("工作线程数量: {}\n", .{SchedulerType.WORKER_COUNT});
    std.debug.print("队列容量: {}\n", .{SchedulerType.QUEUE_CAPACITY});
    std.debug.print("启用LIFO槽: {}\n", .{config.enable_lifo_slot});
    std.debug.print("启用工作窃取: {}\n", .{config.enable_work_stealing});
    std.debug.print("窃取批次大小: {}\n", .{config.steal_batch_size});

    // 显示初始统计
    const initial_stats = scheduler.getStats();
    std.debug.print("\n=== 初始统计信息 ===\n", .{});
    printStats(initial_stats);

    // 测试LIFO槽功能
    std.debug.print("\n=== LIFO槽功能测试 ===\n", .{});
    testLifoSlot();

    // 测试工作窃取队列
    std.debug.print("\n=== 工作窃取队列测试 ===\n", .{});
    try testWorkStealingQueue(allocator);

    // 模拟任务调度
    std.debug.print("\n=== 任务调度演示 ===\n", .{});
    try simulateTaskScheduling(&scheduler, allocator);

    // 测试负载均衡
    std.debug.print("\n=== 负载均衡测试 ===\n", .{});
    testLoadBalancing(&scheduler);

    // 显示最终统计
    const final_stats = scheduler.getStats();
    std.debug.print("\n=== 最终统计信息 ===\n", .{});
    printStats(final_stats);

    std.debug.print("\n=== 演示完成 ===\n", .{});
    std.debug.print("高性能调度器工作正常！\n", .{});
}

fn printStats(stats: zokio.scheduler.SchedulerStats) void {
    std.debug.print("  执行任务数: {}\n", .{stats.tasks_executed});
    std.debug.print("  窃取尝试数: {}\n", .{stats.steals_attempted});
    std.debug.print("  窃取成功数: {}\n", .{stats.steals_successful});
    std.debug.print("  暂停次数: {}\n", .{stats.parks});
    std.debug.print("  LIFO命中数: {}\n", .{stats.lifo_hits});
    std.debug.print("  全局队列轮询数: {}\n", .{stats.global_queue_polls});
    std.debug.print("  活跃工作线程: {}\n", .{stats.active_workers});
    std.debug.print("  窃取成功率: {d:.2}%\n", .{stats.stealSuccessRate() * 100});
    std.debug.print("  LIFO命中率: {d:.2}%\n", .{stats.lifoHitRate() * 100});
}

fn testLifoSlot() void {
    std.debug.print("测试LIFO槽基础功能...\n", .{});

    var lifo_slot = zokio.scheduler.LifoSlot.init();

    // 创建测试任务
    var test_task = zokio.scheduler.Task{
        .id = zokio.future.TaskId.generate(),
        .future_ptr = undefined,
        .vtable = undefined,
    };

    // 测试推入
    const push_success = lifo_slot.tryPush(&test_task);
    std.debug.print("  LIFO槽推入: {}\n", .{push_success});
    std.debug.print("  LIFO槽为空: {}\n", .{lifo_slot.isEmpty()});

    // 测试弹出
    const popped_task = lifo_slot.tryPop();
    std.debug.print("  LIFO槽弹出成功: {}\n", .{popped_task != null});
    std.debug.print("  弹出后为空: {}\n", .{lifo_slot.isEmpty()});
}

fn testWorkStealingQueue(allocator: std.mem.Allocator) !void {
    std.debug.print("测试工作窃取队列...\n", .{});

    const TestItem = struct {
        value: u32,
    };

    var queue = zokio.scheduler.WorkStealingQueue(*TestItem, 16).init();

    // 创建测试项
    const items = try allocator.alloc(TestItem, 8);
    defer allocator.free(items);

    for (items, 0..) |*item, i| {
        item.value = @intCast(i);
    }

    // 推入项目
    var pushed_count: u32 = 0;
    for (items) |*item| {
        if (queue.push(item)) {
            pushed_count += 1;
        }
    }

    std.debug.print("  推入项目数: {}\n", .{pushed_count});
    std.debug.print("  队列长度: {}\n", .{queue.len()});

    // 测试批量窃取
    var batch_buffer: [4]*TestItem = undefined;
    const stolen_count = queue.stealBatch(&batch_buffer, 4);
    std.debug.print("  批量窃取数: {}\n", .{stolen_count});
    std.debug.print("  窃取后队列长度: {}\n", .{queue.len()});

    // 测试单个弹出
    var popped_count: u32 = 0;
    while (queue.pop() != null) {
        popped_count += 1;
    }
    std.debug.print("  弹出项目数: {}\n", .{popped_count});
    std.debug.print("  最终队列为空: {}\n", .{queue.isEmpty()});
}

fn simulateTaskScheduling(scheduler: anytype, allocator: std.mem.Allocator) !void {
    std.debug.print("模拟任务调度...\n", .{});

    const TestTask = struct {
        task: zokio.scheduler.Task,
        value: u32,

        fn init(value: u32) @This() {
            return @This(){
                .task = zokio.scheduler.Task{
                    .id = zokio.future.TaskId.generate(),
                    .future_ptr = undefined,
                    .vtable = undefined,
                },
                .value = value,
            };
        }
    };

    // 创建多个测试任务
    const tasks = try allocator.alloc(TestTask, 10);
    defer allocator.free(tasks);

    for (tasks, 0..) |*task, i| {
        task.* = TestTask.init(@intCast(i));
    }

    // 调度任务
    for (tasks) |*task| {
        scheduler.schedule(&task.task);
    }

    std.debug.print("  调度了 {} 个任务\n", .{tasks.len});

    // 检查任务分布
    var total_queued: u32 = 0;
    for (&scheduler.local_queues, 0..) |*queue, i| {
        const length = queue.len();
        total_queued += length;
        std.debug.print("  工作线程 {} 队列长度: {}\n", .{ i, length });
    }

    const global_empty = scheduler.global_queue.isEmpty();
    std.debug.print("  全局队列为空: {}\n", .{global_empty});
    std.debug.print("  本地队列总任务数: {}\n", .{total_queued});
}

fn testLoadBalancing(scheduler: anytype) void {
    std.debug.print("测试负载均衡...\n", .{});

    // 获取负载均衡前的队列长度
    var lengths_before: [4]u32 = undefined;
    for (&scheduler.local_queues, 0..) |*queue, i| {
        lengths_before[i] = queue.len();
    }

    std.debug.print("  负载均衡前队列长度: [", .{});
    for (lengths_before, 0..) |length, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{}", .{length});
    }
    std.debug.print("]\n", .{});

    // 执行负载均衡
    scheduler.rebalance();

    // 获取负载均衡后的队列长度
    var lengths_after: [4]u32 = undefined;
    for (&scheduler.local_queues, 0..) |*queue, i| {
        lengths_after[i] = queue.len();
    }

    std.debug.print("  负载均衡后队列长度: [", .{});
    for (lengths_after, 0..) |length, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{}", .{length});
    }
    std.debug.print("]\n", .{});

    // 计算负载分布的标准差
    var total_after: u32 = 0;
    for (lengths_after) |length| {
        total_after += length;
    }

    if (total_after > 0) {
        const avg: f32 = @as(f32, @floatFromInt(total_after)) / 4.0;
        var variance: f32 = 0;
        for (lengths_after) |length| {
            const diff = @as(f32, @floatFromInt(length)) - avg;
            variance += diff * diff;
        }
        const std_dev = @sqrt(variance / 4.0);
        std.debug.print("  负载标准差: {d:.2}\n", .{std_dev});
    }
}
