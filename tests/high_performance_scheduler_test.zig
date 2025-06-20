//! 高性能调度器测试

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "高性能调度器基础功能" {
    _ = testing.allocator; // 暂时不使用

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 4,
        .queue_capacity = 64,
        .steal_batch_size = 8, // 64/4 = 16, 所以8是安全的
        .enable_work_stealing = true,
        .enable_lifo_slot = true,
        .enable_statistics = true,
        .global_queue_interval = 31,
        .steal_retry_count = 3,
        .spin_before_park = 10,
    };

    var scheduler = zokio.scheduler.Scheduler(config).init();

    // 验证编译时常量
    const SchedulerType = @TypeOf(scheduler);
    try testing.expectEqual(@as(u32, 4), SchedulerType.WORKER_COUNT);
    try testing.expectEqual(@as(u32, 64), SchedulerType.QUEUE_CAPACITY);

    // 验证工作线程状态初始化
    for (&scheduler.worker_states, 0..) |*state, i| {
        try testing.expectEqual(@as(u32, @intCast(i)), state.id);
        try testing.expect(state.lifo_slot.isEmpty());
        try testing.expectEqual(false, state.is_parked.load(.acquire));
    }

    // 验证统计功能
    const stats = scheduler.getStats();
    try testing.expectEqual(@as(u64, 0), stats.tasks_executed);
    try testing.expectEqual(@as(u32, 0), stats.active_workers);
}

test "LIFO槽功能测试" {
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

    var lifo_slot = zokio.scheduler.LifoSlot.init();
    try testing.expect(lifo_slot.isEmpty());

    var test_task = TestTask.init(42);

    // 测试推入
    try testing.expect(lifo_slot.tryPush(&test_task.task));
    try testing.expect(!lifo_slot.isEmpty());

    // 测试重复推入失败
    var test_task2 = TestTask.init(43);
    try testing.expect(!lifo_slot.tryPush(&test_task2.task));

    // 测试弹出
    const popped = lifo_slot.tryPop();
    try testing.expect(popped != null);
    try testing.expect(popped.? == &test_task.task);
    try testing.expect(lifo_slot.isEmpty());

    // 测试空弹出
    try testing.expect(lifo_slot.tryPop() == null);
}

test "工作窃取队列批量操作" {
    const TestItem = struct {
        value: u32,
    };

    var queue = zokio.scheduler.WorkStealingQueue(*TestItem, 16).init();

    // 创建测试项
    var items: [8]TestItem = undefined;
    for (&items, 0..) |*item, i| {
        item.value = @intCast(i);
    }

    // 推入多个项
    for (&items) |*item| {
        try testing.expect(queue.push(item));
    }

    try testing.expectEqual(@as(u32, 8), queue.len());

    // 批量窃取
    var batch_buffer: [4]*TestItem = undefined;
    const stolen_count = queue.stealBatch(&batch_buffer, 4);

    try testing.expectEqual(@as(u32, 4), stolen_count);
    try testing.expectEqual(@as(u32, 4), queue.len());

    // 验证窃取的项
    for (0..stolen_count) |i| {
        try testing.expectEqual(@as(u32, @intCast(i)), batch_buffer[i].value);
    }
}

test "调度器统计功能" {
    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 2,
        .steal_batch_size = 32, // 256/4 = 64, 所以32是安全的
        .enable_statistics = true,
    };

    var scheduler = zokio.scheduler.Scheduler(config).init();

    // 初始统计应该为0
    const initial_stats = scheduler.getStats();
    try testing.expectEqual(@as(u64, 0), initial_stats.tasks_executed);
    try testing.expectEqual(0.0, initial_stats.stealSuccessRate());
    try testing.expectEqual(0.0, initial_stats.lifoHitRate());

    // 模拟一些统计数据
    scheduler.worker_stats[0].recordTaskExecution();
    scheduler.worker_stats[0].recordStealAttempt();
    scheduler.worker_stats[0].recordStealSuccess();
    scheduler.worker_stats[0].recordLifoHit();

    const updated_stats = scheduler.getStats();
    try testing.expectEqual(@as(u64, 1), updated_stats.tasks_executed);
    try testing.expectEqual(@as(u64, 1), updated_stats.steals_attempted);
    try testing.expectEqual(@as(u64, 1), updated_stats.steals_successful);
    try testing.expectEqual(@as(u64, 1), updated_stats.lifo_hits);

    try testing.expectEqual(1.0, updated_stats.stealSuccessRate());
    try testing.expectEqual(1.0, updated_stats.lifoHitRate());
}

test "负载均衡功能" {
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

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 4,
        .queue_capacity = 32,
        .steal_batch_size = 4, // 32/4 = 8, 所以4是安全的
    };

    var scheduler = zokio.scheduler.Scheduler(config).init();

    // 创建不平衡的负载：第一个队列有很多任务，其他队列为空
    var tasks: [16]TestTask = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = TestTask.init(@intCast(i));
    }

    // 将所有任务放入第一个队列
    for (&tasks) |*task| {
        try testing.expect(scheduler.local_queues[0].push(&task.task));
    }

    // 验证不平衡状态
    try testing.expectEqual(@as(u32, 16), scheduler.local_queues[0].len());
    for (1..4) |i| {
        try testing.expectEqual(@as(u32, 0), scheduler.local_queues[i].len());
    }

    // 执行负载均衡
    scheduler.rebalance();

    // 验证负载已经分散
    var total_after_rebalance: u32 = 0;
    for (&scheduler.local_queues) |*queue| {
        total_after_rebalance += queue.len();
    }

    // 总任务数应该保持不变（可能有些在全局队列中）
    const global_queue_count: u32 = if (scheduler.global_queue.isEmpty()) 0 else 1; // 简化检查
    total_after_rebalance += global_queue_count;

    // 第一个队列的任务数应该减少
    try testing.expect(scheduler.local_queues[0].len() < 16);
}

test "工作线程暂停和唤醒" {
    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 2,
        .steal_batch_size = 32, // 256/4 = 64, 所以32是安全的
    };

    var scheduler = zokio.scheduler.Scheduler(config).init();

    var worker_state = &scheduler.worker_states[0];

    // 初始状态应该是未暂停
    try testing.expectEqual(false, worker_state.is_parked.load(.acquire));

    // 模拟暂停状态
    worker_state.is_parked.store(true, .release);
    try testing.expectEqual(true, worker_state.is_parked.load(.acquire));

    // 测试唤醒机制
    scheduler.tryUnparkWorker();

    // 注意：实际的unpark会在另一个线程中执行，这里只是测试接口
}

test "编译时配置验证" {
    // 测试有效配置
    const valid_config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 8,
        .queue_capacity = 128,
        .steal_batch_size = 16, // 128/4 = 32, 所以16是安全的
        .global_queue_interval = 31,
        .spin_before_park = 100,
    };

    // 编译时验证应该通过
    comptime valid_config.validate();

    // 创建调度器应该成功
    const scheduler = zokio.scheduler.Scheduler(valid_config).init();
    const SchedulerType = @TypeOf(scheduler);
    try testing.expectEqual(@as(u32, 8), SchedulerType.WORKER_COUNT);
    try testing.expectEqual(@as(u32, 128), SchedulerType.QUEUE_CAPACITY);
}
