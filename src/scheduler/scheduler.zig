//! 调度器模块
//!
//! 提供编译时特化的任务调度器，包括工作窃取队列、
//! 多线程调度和负载均衡等功能。

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils/utils.zig");
const platform = @import("../utils/platform.zig");
const future = @import("../future/future.zig");
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

    const TaskVTable = struct {
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
        const CAPACITY = capacity;
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

/// 工作线程统计
const WorkerStats = struct {
    tasks_executed: utils.Atomic.Value(u64),
    steals_attempted: utils.Atomic.Value(u64),
    steals_successful: utils.Atomic.Value(u64),
    parks: utils.Atomic.Value(u64),

    pub fn init() WorkerStats {
        return WorkerStats{
            .tasks_executed = utils.Atomic.Value(u64).init(0),
            .steals_attempted = utils.Atomic.Value(u64).init(0),
            .steals_successful = utils.Atomic.Value(u64).init(0),
            .parks = utils.Atomic.Value(u64).init(0),
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

        // 全局注入队列
        global_queue: GlobalQueue,

        // 工作线程统计
        worker_stats: if (config.enable_statistics) [WORKER_COUNT]WorkerStats else void,

        // 轮询计数器
        round_robin_counter: utils.Atomic.Value(u32),

        pub fn init() Self {
            var self = Self{
                .local_queues = undefined,
                .global_queue = GlobalQueue.init(),
                .worker_stats = if (config.enable_statistics) undefined else {},
                .round_robin_counter = utils.Atomic.Value(u32).init(0),
            };

            // 初始化本地队列
            for (&self.local_queues) |*queue| {
                queue.* = WorkStealingQueue(*Task, config.queue_capacity).init();
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
        }

        /// 本地优先调度
        fn scheduleLocalFirst(self: *Self, task: *Task) void {
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

        /// 工作线程运行循环
        pub fn runWorker(self: *Self, worker_id: u32) void {
            if (worker_id >= WORKER_COUNT) return;

            // 设置当前工作线程ID
            setCurrentWorkerId(worker_id);
            defer clearCurrentWorkerId();

            var local_queue = &self.local_queues[worker_id];
            var stats = if (config.enable_statistics) &self.worker_stats[worker_id] else undefined;

            while (true) {
                // 1. 检查本地队列
                if (local_queue.pop()) |task| {
                    self.executeTask(task, stats);
                    continue;
                }

                // 2. 检查全局队列
                if (self.global_queue.pop()) |task| {
                    self.executeTask(task, stats);
                    continue;
                }

                // 3. 工作窃取
                if (config.enable_work_stealing) {
                    if (self.stealWork(worker_id, stats)) |task| {
                        self.executeTask(task, stats);
                        continue;
                    }
                }

                // 4. 暂停等待
                if (config.enable_statistics) {
                    stats.recordPark();
                }

                // 简单的忙等待，实际实现中应该使用条件变量
                std.time.sleep(1000); // 1微秒
            }
        }

        /// 工作窃取
        fn stealWork(self: *Self, worker_id: u32, stats: anytype) ?*Task {
            // 随机选择窃取目标
            var rng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
            const start_index = rng.random().int(u32) % WORKER_COUNT;

            for (0..WORKER_COUNT) |i| {
                const target_id = (start_index + i) % WORKER_COUNT;
                if (target_id == worker_id) continue; // 跳过自己

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
