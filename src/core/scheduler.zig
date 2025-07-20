//! 调度器模块
//!
//! 提供编译时特化的任务调度器，包括工作窃取队列、
//! 多线程调度和负载均衡等功能。

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils/utils.zig");
const platform = @import("../utils/platform.zig");
const future = @import("../core/future.zig");
const memory = @import("../memory/memory.zig");

/// 调度器配置
pub const SchedulerConfig = struct {
    /// 工作线程数量
    worker_threads: ?u32 = null,

    /// 本地队列容量
    queue_capacity: u32 = 256,

    /// 是否启用工作窃取
    enable_work_stealing: bool = true,

    /// 调度策略
    scheduling_strategy: SchedulingStrategy = .local_first,

    /// 窃取批次大小
    steal_batch_size: u32 = 32,

    /// 是否启用统计
    enable_statistics: bool = true,

    /// 是否启用LIFO槽优化
    enable_lifo_slot: bool = true,

    /// 全局队列检查间隔
    global_queue_interval: u32 = 61,

    /// 是否启用NUMA感知
    enable_numa_aware: bool = true,

    /// 工作窃取重试次数
    steal_retry_count: u32 = 3,

    /// 暂停前的自旋次数
    spin_before_park: u32 = 10,

    /// 编译时验证配置
    pub fn validate(comptime self: @This()) void {
        if (self.worker_threads) |threads| {
            if (threads == 0) {
                @compileError("Worker thread count must be greater than 0");
            }
            if (threads > 1024) {
                @compileError("Worker thread count is too large (max 1024)");
            }
        }

        if (!std.math.isPowerOfTwo(self.queue_capacity)) {
            @compileError("Queue capacity must be a power of 2");
        }

        if (self.steal_batch_size > self.queue_capacity / 4) {
            @compileError("Steal batch size too large");
        }

        if (self.global_queue_interval == 0) {
            @compileError("Global queue interval must be greater than 0");
        }

        if (self.spin_before_park > 1000) {
            @compileError("Spin count too large (max 1000)");
        }
    }
};

/// 调度策略
pub const SchedulingStrategy = enum {
    /// 本地优先
    local_first,
    /// 全局优先
    global_first,
    /// 轮询
    round_robin,
};

/// 调度器统计信息
pub const SchedulerStats = struct {
    tasks_executed: u64 = 0,
    steals_attempted: u64 = 0,
    steals_successful: u64 = 0,
    parks: u64 = 0,
    lifo_hits: u64 = 0,
    global_queue_polls: u64 = 0,
    active_workers: u32 = 0,

    /// 计算窃取成功率
    pub fn stealSuccessRate(self: SchedulerStats) f64 {
        if (self.steals_attempted == 0) return 0.0;
        return @as(f64, @floatFromInt(self.steals_successful)) / @as(f64, @floatFromInt(self.steals_attempted));
    }

    /// 计算LIFO命中率
    pub fn lifoHitRate(self: SchedulerStats) f64 {
        if (self.tasks_executed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.lifo_hits)) / @as(f64, @floatFromInt(self.tasks_executed));
    }
};

/// 任务句柄
pub const Task = struct {
    /// 任务ID
    id: future.TaskId,

    /// Future指针
    future_ptr: *anyopaque,

    /// 虚函数表
    vtable: *const TaskVTable,

    /// 队列链接节点
    queue_node: utils.IntrusiveNode(@This()) = .{},

    pub const TaskVTable = struct {
        poll: *const fn (*anyopaque, *future.Context) future.Poll(void),
        drop: *const fn (*anyopaque) void,
    };

    pub fn poll(self: *Task, ctx: *future.Context) future.Poll(void) {
        return self.vtable.poll(self.future_ptr, ctx);
    }

    pub fn deinit(self: *Task) void {
        self.vtable.drop(self.future_ptr);
    }
};

/// 编译时工作窃取队列生成器
pub fn WorkStealingQueue(comptime T: type, comptime capacity: u32) type {
    // 编译时验证容量是2的幂
    comptime {
        if (!std.math.isPowerOfTwo(capacity)) {
            @compileError("Queue capacity must be a power of 2");
        }
    }

    return struct {
        const Self = @This();
        pub const CAPACITY = capacity;
        const MASK = capacity - 1;

        // 使用编译时优化的原子类型
        const AtomicIndex = if (capacity <= 256) utils.Atomic.Value(u8) else utils.Atomic.Value(u16);

        // 缓存行对齐的队列结构
        buffer: [CAPACITY]utils.Atomic.Value(?T) align(platform.PlatformCapabilities.cache_line_size),
        head: AtomicIndex align(platform.PlatformCapabilities.cache_line_size),
        tail: AtomicIndex align(platform.PlatformCapabilities.cache_line_size),

        pub fn init() Self {
            return Self{
                .buffer = [_]utils.Atomic.Value(?T){utils.Atomic.Value(?T).init(null)} ** CAPACITY,
                .head = AtomicIndex.init(0),
                .tail = AtomicIndex.init(0),
            };
        }

        /// 推入任务到队列尾部（只能被拥有者调用）
        pub fn push(self: *Self, item: T) bool {
            const tail = self.tail.load(.monotonic);
            const head = self.head.load(.acquire);

            // 检查队列是否已满
            if (tail -% head >= CAPACITY) {
                return false;
            }

            const index = tail & MASK;
            self.buffer[index].store(item, .unordered);

            // 内存屏障确保写入可见性
            self.tail.store(tail +% 1, .release);
            return true;
        }

        /// 从队列尾部弹出任务（只能被拥有者调用）
        pub fn pop(self: *Self) ?T {
            const tail = self.tail.load(.monotonic);
            const head = self.head.load(.monotonic);

            if (head >= tail) {
                return null; // 队列空
            }

            const new_tail = tail -% 1;
            self.tail.store(new_tail, .monotonic);

            const index = new_tail & MASK;
            const item = self.buffer[index].load(.unordered);

            return item;
        }

        /// 从队列头部窃取任务（可以被其他线程调用）
        pub fn steal(self: *Self) ?T {
            var head = self.head.load(.acquire);

            while (true) {
                const tail = self.tail.load(.acquire);

                if (head >= tail) {
                    return null; // 队列空
                }

                const index = head & MASK;
                const item = self.buffer[index].load(.unordered);

                // 尝试原子更新head
                if (self.head.cmpxchgWeak(head, head +% 1, .acq_rel, .acquire)) |actual| {
                    head = actual;
                } else {
                    return item;
                }
            }
        }

        /// 批量窃取任务
        pub fn stealBatch(self: *Self, buffer: []T, max_count: u32) u32 {
            var stolen: u32 = 0;
            const count = @min(max_count, buffer.len);

            for (0..count) |i| {
                if (self.steal()) |item| {
                    buffer[i] = item;
                    stolen += 1;
                } else {
                    break;
                }
            }

            return stolen;
        }

        /// 获取队列长度（近似值）
        pub fn len(self: *const Self) u32 {
            const tail = self.tail.load(.monotonic);
            const head = self.head.load(.monotonic);
            return tail -% head;
        }

        /// 检查队列是否为空
        pub fn isEmpty(self: *const Self) bool {
            return self.len() == 0;
        }
    };
}

/// 全局注入队列
const GlobalQueue = struct {
    queue: utils.IntrusiveList(Task, "queue_node"),
    mutex: std.Thread.Mutex,

    pub fn init() GlobalQueue {
        return GlobalQueue{
            .queue = utils.IntrusiveList(Task, "queue_node").init(),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn push(self: *GlobalQueue, task: *Task) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.queue.pushBack(task);
    }

    pub fn pop(self: *GlobalQueue) ?*Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.queue.popFront();
    }

    pub fn isEmpty(self: *const GlobalQueue) bool {
        // 注意：这里没有加锁，可能不准确，但用于快速检查
        return self.queue.isEmpty();
    }
};

/// LIFO槽 - 用于减少任务延迟的快速路径
pub const LifoSlot = struct {
    task: utils.Atomic.Value(?*Task),

    pub fn init() LifoSlot {
        return LifoSlot{
            .task = utils.Atomic.Value(?*Task).init(null),
        };
    }

    /// 尝试放入任务到LIFO槽
    pub fn tryPush(self: *LifoSlot, task: *Task) bool {
        return self.task.cmpxchgStrong(null, task, .acq_rel, .acquire) == null;
    }

    /// 尝试从LIFO槽取出任务
    pub fn tryPop(self: *LifoSlot) ?*Task {
        return self.task.swap(null, .acq_rel);
    }

    /// 检查LIFO槽是否为空
    pub fn isEmpty(self: *const LifoSlot) bool {
        return self.task.load(.acquire) == null;
    }
};

/// 工作线程状态
const WorkerState = struct {
    /// 工作线程ID
    id: u32,

    /// LIFO槽
    lifo_slot: LifoSlot,

    /// 本地队列（类型将在编译时确定）
    local_queue: *anyopaque, // 将在运行时设置为正确的队列类型

    /// 全局队列检查计数器
    global_check_counter: u32,

    /// 暂停状态
    is_parked: utils.Atomic.Value(bool),

    /// 条件变量用于暂停/唤醒
    park_mutex: std.Thread.Mutex,
    park_condition: std.Thread.Condition,

    pub fn init(id: u32) WorkerState {
        return WorkerState{
            .id = id,
            .lifo_slot = LifoSlot.init(),
            .local_queue = undefined, // 将在调度器初始化时设置
            .global_check_counter = 0,
            .is_parked = utils.Atomic.Value(bool).init(false),
            .park_mutex = std.Thread.Mutex{},
            .park_condition = std.Thread.Condition{},
        };
    }

    /// 暂停工作线程
    pub fn park(self: *WorkerState) void {
        self.park_mutex.lock();
        defer self.park_mutex.unlock();

        self.is_parked.store(true, .release);
        self.park_condition.wait(&self.park_mutex);
        self.is_parked.store(false, .release);
    }

    /// 唤醒工作线程
    pub fn unpark(self: *WorkerState) void {
        if (self.is_parked.load(.acquire)) {
            self.park_mutex.lock();
            defer self.park_mutex.unlock();
            self.park_condition.signal();
        }
    }
};

/// 工作线程统计
const WorkerStats = struct {
    tasks_executed: utils.Atomic.Value(u64),
    steals_attempted: utils.Atomic.Value(u64),
    steals_successful: utils.Atomic.Value(u64),
    parks: utils.Atomic.Value(u64),
    lifo_hits: utils.Atomic.Value(u64),
    global_queue_polls: utils.Atomic.Value(u64),

    pub fn init() WorkerStats {
        return WorkerStats{
            .tasks_executed = utils.Atomic.Value(u64).init(0),
            .steals_attempted = utils.Atomic.Value(u64).init(0),
            .steals_successful = utils.Atomic.Value(u64).init(0),
            .parks = utils.Atomic.Value(u64).init(0),
            .lifo_hits = utils.Atomic.Value(u64).init(0),
            .global_queue_polls = utils.Atomic.Value(u64).init(0),
        };
    }

    pub fn recordTaskExecution(self: *WorkerStats) void {
        _ = self.tasks_executed.fetchAdd(1, .monotonic);
    }

    pub fn recordStealAttempt(self: *WorkerStats) void {
        _ = self.steals_attempted.fetchAdd(1, .monotonic);
    }

    pub fn recordStealSuccess(self: *WorkerStats) void {
        _ = self.steals_successful.fetchAdd(1, .monotonic);
    }

    pub fn recordPark(self: *WorkerStats) void {
        _ = self.parks.fetchAdd(1, .monotonic);
    }

    pub fn recordLifoHit(self: *WorkerStats) void {
        _ = self.lifo_hits.fetchAdd(1, .monotonic);
    }

    pub fn recordGlobalQueuePoll(self: *WorkerStats) void {
        _ = self.global_queue_polls.fetchAdd(1, .monotonic);
    }
};

/// 编译时调度器生成器
pub fn Scheduler(comptime config: SchedulerConfig) type {
    // 编译时验证配置
    comptime config.validate();

    // 编译时计算最优参数
    const worker_count = comptime config.worker_threads orelse
        @min(platform.PlatformCapabilities.optimal_worker_count, 64);

    return struct {
        const Self = @This();

        // 编译时确定的常量
        pub const WORKER_COUNT = worker_count;
        pub const QUEUE_CAPACITY = config.queue_capacity;

        // 工作线程本地队列
        local_queues: [WORKER_COUNT]WorkStealingQueue(*Task, config.queue_capacity),

        // 工作线程状态
        worker_states: [WORKER_COUNT]WorkerState,

        // 全局注入队列
        global_queue: GlobalQueue,

        // 工作线程统计
        worker_stats: if (config.enable_statistics) [WORKER_COUNT]WorkerStats else void,

        // 轮询计数器
        round_robin_counter: utils.Atomic.Value(u32),

        // 活跃工作线程计数
        active_workers: utils.Atomic.Value(u32),

        pub fn init() Self {
            var self = Self{
                .local_queues = undefined,
                .worker_states = undefined,
                .global_queue = GlobalQueue.init(),
                .worker_stats = if (config.enable_statistics) undefined else {},
                .round_robin_counter = utils.Atomic.Value(u32).init(0),
                .active_workers = utils.Atomic.Value(u32).init(0),
            };

            // 初始化本地队列
            for (&self.local_queues) |*queue| {
                queue.* = WorkStealingQueue(*Task, config.queue_capacity).init();
            }

            // 初始化工作线程状态
            for (&self.worker_states, 0..) |*state, i| {
                state.* = WorkerState.init(@intCast(i));
                state.local_queue = &self.local_queues[i];
            }

            // 初始化统计
            if (config.enable_statistics) {
                for (&self.worker_stats) |*stats| {
                    stats.* = WorkerStats.init();
                }
            }

            return self;
        }

        /// 调度任务
        pub fn schedule(self: *Self, task: *Task) void {
            const strategy = comptime config.scheduling_strategy;

            switch (comptime strategy) {
                .local_first => self.scheduleLocalFirst(task),
                .global_first => self.scheduleGlobalFirst(task),
                .round_robin => self.scheduleRoundRobin(task),
            }

            // 尝试唤醒暂停的工作线程
            self.tryUnparkWorker();
        }

        /// 尝试唤醒暂停的工作线程
        pub fn tryUnparkWorker(self: *Self) void {
            // 简单策略：唤醒第一个找到的暂停线程
            for (&self.worker_states) |*state| {
                if (state.is_parked.load(.acquire)) {
                    state.unpark();
                    break;
                }
            }
        }

        /// 获取调度器统计信息
        pub fn getStats(self: *const Self) SchedulerStats {
            if (!config.enable_statistics) {
                return SchedulerStats{};
            }

            var total_stats = SchedulerStats{};

            for (&self.worker_stats) |*stats| {
                total_stats.tasks_executed += stats.tasks_executed.load(.monotonic);
                total_stats.steals_attempted += stats.steals_attempted.load(.monotonic);
                total_stats.steals_successful += stats.steals_successful.load(.monotonic);
                total_stats.parks += stats.parks.load(.monotonic);
                total_stats.lifo_hits += stats.lifo_hits.load(.monotonic);
                total_stats.global_queue_polls += stats.global_queue_polls.load(.monotonic);
            }

            total_stats.active_workers = self.active_workers.load(.monotonic);

            return total_stats;
        }

        /// 负载均衡 - 将任务从忙碌队列迁移到空闲队列
        pub fn rebalance(self: *Self) void {
            var queue_lengths: [WORKER_COUNT]u32 = undefined;
            var total_tasks: u32 = 0;

            // 收集队列长度信息
            for (0..WORKER_COUNT) |i| {
                queue_lengths[i] = self.local_queues[i].len();
                total_tasks += queue_lengths[i];
            }

            if (total_tasks == 0) return;

            const avg_length = total_tasks / WORKER_COUNT;
            const threshold = avg_length + avg_length / 2; // 150%的平均值

            // 从过载队列迁移任务到空闲队列
            for (0..WORKER_COUNT) |i| {
                if (queue_lengths[i] > threshold) {
                    // 找到最空闲的队列
                    var min_length = queue_lengths[0];
                    var min_index: u32 = 0;

                    for (1..WORKER_COUNT) |j| {
                        if (queue_lengths[j] < min_length) {
                            min_length = queue_lengths[j];
                            min_index = @intCast(j);
                        }
                    }

                    // 迁移一些任务
                    const migrate_count = (queue_lengths[i] - avg_length) / 2;
                    for (0..migrate_count) |_| {
                        if (self.local_queues[i].steal()) |task| {
                            if (!self.local_queues[min_index].push(task)) {
                                // 目标队列满了，放回全局队列
                                self.global_queue.push(task);
                            }
                        } else {
                            break;
                        }
                    }
                }
            }
        }

        /// 本地优先调度
        fn scheduleLocalFirst(self: *Self, task: *Task) void {
            // 尝试放入当前工作线程的LIFO槽（如果启用）
            if (comptime config.enable_lifo_slot) {
                if (getCurrentWorkerId()) |worker_id| {
                    if (self.worker_states[worker_id].lifo_slot.tryPush(task)) {
                        return;
                    }
                }
            }

            // 尝试放入当前工作线程的本地队列
            if (getCurrentWorkerId()) |worker_id| {
                if (self.local_queues[worker_id].push(task)) {
                    return;
                }
            }

            // 放入全局队列
            self.global_queue.push(task);
        }

        /// 全局优先调度
        fn scheduleGlobalFirst(self: *Self, task: *Task) void {
            self.global_queue.push(task);
        }

        /// 轮询调度
        fn scheduleRoundRobin(self: *Self, task: *Task) void {
            const worker_id = self.round_robin_counter.fetchAdd(1, .monotonic) % WORKER_COUNT;

            if (!self.local_queues[worker_id].push(task)) {
                // 本地队列满，放入全局队列
                self.global_queue.push(task);
            }
        }

        /// 工作线程运行循环 - Tokio级别的高性能实现
        pub fn runWorker(self: *Self, worker_id: u32) void {
            if (worker_id >= WORKER_COUNT) return;

            // 设置当前工作线程ID
            setCurrentWorkerId(worker_id);
            defer clearCurrentWorkerId();

            var worker_state = &self.worker_states[worker_id];
            var local_queue = &self.local_queues[worker_id];
            var stats = if (config.enable_statistics) &self.worker_stats[worker_id] else undefined;

            // 增加活跃工作线程计数
            _ = self.active_workers.fetchAdd(1, .monotonic);
            defer _ = self.active_workers.fetchSub(1, .monotonic);

            var spin_count: u32 = 0;

            while (true) {
                // 1. 检查LIFO槽（最高优先级，减少延迟）
                if (comptime config.enable_lifo_slot) {
                    if (worker_state.lifo_slot.tryPop()) |task| {
                        if (config.enable_statistics) {
                            stats.recordLifoHit();
                        }
                        self.executeTask(task, stats);
                        spin_count = 0;
                        continue;
                    }
                }

                // 2. 检查本地队列
                if (local_queue.pop()) |task| {
                    self.executeTask(task, stats);
                    spin_count = 0;
                    continue;
                }

                // 3. 定期检查全局队列（公平性保证）
                worker_state.global_check_counter += 1;
                if (worker_state.global_check_counter % config.global_queue_interval == 0) {
                    if (config.enable_statistics) {
                        stats.recordGlobalQueuePoll();
                    }
                    if (self.global_queue.pop()) |task| {
                        self.executeTask(task, stats);
                        spin_count = 0;
                        continue;
                    }
                }

                // 4. 工作窃取（多轮尝试）
                if (config.enable_work_stealing) {
                    if (self.stealWorkAdvanced(worker_id, stats)) |task| {
                        self.executeTask(task, stats);
                        spin_count = 0;
                        continue;
                    }
                }

                // 5. 暂停策略：先自旋，后暂停
                spin_count += 1;
                if (spin_count < config.spin_before_park) {
                    // 自旋等待
                    std.atomic.spinLoopHint();
                } else {
                    // 暂停等待
                    if (config.enable_statistics) {
                        stats.recordPark();
                    }

                    // 使用条件变量暂停
                    worker_state.park();
                    spin_count = 0;
                }
            }
        }

        /// 高级工作窃取算法 - 多轮尝试，负载感知
        fn stealWorkAdvanced(self: *Self, worker_id: u32, stats: anytype) ?*Task {
            // 多轮窃取尝试
            for (0..config.steal_retry_count) |round| {
                // 第一轮：随机窃取
                if (round == 0) {
                    if (self.stealWorkRandom(worker_id, stats)) |task| {
                        return task;
                    }
                }
                // 第二轮：从最忙的队列窃取
                else if (round == 1) {
                    if (self.stealWorkFromBusiest(worker_id, stats)) |task| {
                        return task;
                    }
                }
                // 第三轮：批量窃取
                else {
                    if (self.stealWorkBatch(worker_id, stats)) |task| {
                        return task;
                    }
                }
            }

            return null;
        }

        /// 随机工作窃取
        fn stealWorkRandom(self: *Self, worker_id: u32, stats: anytype) ?*Task {
            // 使用线程ID作为种子，避免所有线程选择相同目标
            var rng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp() + worker_id));
            const start_index = rng.random().int(u32) % WORKER_COUNT;

            for (0..WORKER_COUNT) |i| {
                const target_id = (start_index + i) % WORKER_COUNT;
                if (target_id == worker_id) continue; // 跳过自己

                if (config.enable_statistics) {
                    stats.recordStealAttempt();
                }

                // 先尝试从LIFO槽窃取
                if (comptime config.enable_lifo_slot) {
                    if (self.worker_states[target_id].lifo_slot.tryPop()) |task| {
                        if (config.enable_statistics) {
                            stats.recordStealSuccess();
                        }
                        return task;
                    }
                }

                // 再从本地队列窃取
                if (self.local_queues[target_id].steal()) |task| {
                    if (config.enable_statistics) {
                        stats.recordStealSuccess();
                    }
                    return task;
                }
            }

            return null;
        }

        /// 从最忙的队列窃取
        fn stealWorkFromBusiest(self: *Self, worker_id: u32, stats: anytype) ?*Task {
            var busiest_id: ?u32 = null;
            var max_length: u32 = 0;

            // 找到最忙的队列
            for (0..WORKER_COUNT) |i| {
                if (i == worker_id) continue;

                const length = self.local_queues[i].len();
                if (length > max_length) {
                    max_length = length;
                    busiest_id = @intCast(i);
                }
            }

            if (busiest_id) |target_id| {
                if (config.enable_statistics) {
                    stats.recordStealAttempt();
                }

                if (self.local_queues[target_id].steal()) |task| {
                    if (config.enable_statistics) {
                        stats.recordStealSuccess();
                    }
                    return task;
                }
            }

            return null;
        }

        /// 批量工作窃取
        fn stealWorkBatch(self: *Self, worker_id: u32, stats: anytype) ?*Task {
            var batch_buffer: [32]*Task = undefined;

            for (0..WORKER_COUNT) |i| {
                if (i == worker_id) continue;

                if (config.enable_statistics) {
                    stats.recordStealAttempt();
                }

                const stolen_count = self.local_queues[i].stealBatch(&batch_buffer, config.steal_batch_size);
                if (stolen_count > 0) {
                    if (config.enable_statistics) {
                        stats.recordStealSuccess();
                    }

                    // 执行第一个任务，其余放入本地队列
                    const first_task = batch_buffer[0];
                    for (1..stolen_count) |j| {
                        _ = self.local_queues[worker_id].push(batch_buffer[j]);
                    }

                    return first_task;
                }
            }

            return null;
        }

        /// 执行任务
        fn executeTask(self: *Self, task: *Task, stats: anytype) void {
            _ = self;

            if (config.enable_statistics) {
                stats.recordTaskExecution();
            }

            // 创建执行上下文
            const waker = future.Waker.noop(); // 简化实现
            var ctx = future.Context.init(waker);
            ctx.task_id = task.id;

            // 执行任务
            const result = task.poll(&ctx);

            switch (result) {
                .ready => {
                    // 任务完成，清理资源
                    task.deinit();
                },
                .pending => {
                    // 任务未完成，重新调度
                    // 在实际实现中，应该由Waker负责重新调度
                },
            }
        }
    };
}

// 线程本地存储
threadlocal var current_worker_id: ?u32 = null;

fn getCurrentWorkerId() ?u32 {
    return current_worker_id;
}

fn setCurrentWorkerId(id: u32) void {
    current_worker_id = id;
}

fn clearCurrentWorkerId() void {
    current_worker_id = null;
}

// 测试
test "工作窃取队列基础功能" {
    const testing = std.testing;

    const TestItem = struct {
        value: u32,
    };

    var queue = WorkStealingQueue(*TestItem, 8).init();

    var item1 = TestItem{ .value = 1 };
    var item2 = TestItem{ .value = 2 };
    var item3 = TestItem{ .value = 3 };

    // 测试推入
    try testing.expect(queue.push(&item1));
    try testing.expect(queue.push(&item2));
    try testing.expect(queue.push(&item3));

    try testing.expectEqual(@as(u32, 3), queue.len());
    try testing.expect(!queue.isEmpty());

    // 测试弹出
    const popped = queue.pop().?;
    try testing.expectEqual(@as(u32, 3), popped.*.value);
    try testing.expectEqual(@as(u32, 2), queue.len());

    // 测试窃取
    const stolen = queue.steal().?;
    try testing.expectEqual(@as(u32, 1), stolen.*.value);
    try testing.expectEqual(@as(u32, 1), queue.len());
}

test "调度器基础功能" {
    const testing = std.testing;

    const config = SchedulerConfig{
        .worker_threads = 2,
        .queue_capacity = 8,
        .steal_batch_size = 2, // 设置合适的批次大小
        .enable_statistics = true,
    };

    var scheduler = Scheduler(config).init();

    // 创建测试任务
    var test_task = Task{
        .id = future.TaskId.generate(),
        .future_ptr = undefined,
        .vtable = undefined,
    };

    // 测试调度
    scheduler.schedule(&test_task);

    // 验证任务被调度到某个队列
    var found = false;
    for (&scheduler.local_queues) |*queue| {
        if (!queue.isEmpty()) {
            found = true;
            break;
        }
    }

    if (!found and !scheduler.global_queue.isEmpty()) {
        found = true;
    }

    try testing.expect(found);
}
