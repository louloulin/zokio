# Zokio 2.0: 真正异步运行时实现计划

## 🎯 执行摘要

基于对当前Zokio项目的深度分析和异步运行时最佳实践研究，本计划制定了将Zokio从"伪异步"升级为真正异步运行时的完整路线图。当前实现虽然具备优秀的API设计和架构基础，但在核心异步机制上存在根本性问题，需要系统性重构。

## 📊 当前实现分析

### ✅ 现有优势
- **优秀的API设计**: Future trait、async_fn/await_fn语法设计合理
- **编译时优化**: 充分利用Zig的comptime特性
- **模块化架构**: 清晰的运行时、调度器、I/O、内存管理分离
- **平台特化**: 支持多种I/O后端的编译时选择
- **高质量代码**: 完整的错误处理和类型安全

### ❌ 关键问题
1. **伪异步await_fn**: 使用`std.time.sleep(1ms)`阻塞等待
2. **同步async_fn**: 函数在第一次poll时完全同步执行
3. **缺少事件循环**: TCP I/O直接调用系统调用，无事件循环集成
4. **调度器不完整**: 缺乏真正的任务调度和协作机制
5. **libxev集成浅层**: 虽然配置了libxev但未真正使用

## 🚀 Zokio 2.0 架构设计

### 核心设计原则
1. **真正异步**: 基于事件循环的非阻塞I/O
2. **零拷贝**: 最小化内存分配和数据复制
3. **编译时优化**: 利用Zig的comptime进行最大化优化
4. **生产级性能**: 目标性能超越Tokio
5. **跨平台兼容**: 支持Linux/macOS/Windows

### 系统架构图
```
┌─────────────────────────────────────────────────────────────┐
│                    Zokio 2.0 Runtime                       │
├─────────────────────────────────────────────────────────────┤
│  async_fn/await_fn API  │  Future Combinators  │  Channels  │
├─────────────────────────────────────────────────────────────┤
│              Task Scheduler (Work-Stealing)                 │
├─────────────────────────────────────────────────────────────┤
│    Event Loop (libxev)   │   Timer Wheel   │   Waker System │
├─────────────────────────────────────────────────────────────┤
│  I/O Driver (epoll/kqueue/io_uring)  │  Memory Pool Manager │
├─────────────────────────────────────────────────────────────┤
│                    Platform Abstraction                     │
└─────────────────────────────────────────────────────────────┘
```

## 🔧 Phase 1: 核心异步机制重构 (4周)

### Week 1: 真正的事件循环实现

#### 1.1 libxev深度集成
```zig
/// 🚀 真正的异步事件循环
pub const AsyncEventLoop = struct {
    libxev_loop: libxev.Loop,
    waker_registry: WakerRegistry,
    timer_wheel: TimerWheel,
    
    /// 运行事件循环直到所有任务完成
    pub fn run(self: *Self) !void {
        while (self.hasActiveTasks()) {
            // 1. 处理就绪的I/O事件
            try self.libxev_loop.run(.no_wait);
            
            // 2. 处理到期的定时器
            self.timer_wheel.processExpired();
            
            // 3. 唤醒就绪的任务
            self.waker_registry.wakeReady();
            
            // 4. 让出CPU给调度器
            self.scheduler.yield();
        }
    }
};
```

#### 1.2 Waker系统重构
```zig
/// 🔥 真正的Waker实现
pub const Waker = struct {
    task_id: TaskId,
    scheduler: *TaskScheduler,
    
    pub fn wake(self: *const Self) void {
        // 将任务标记为就绪并加入调度队列
        self.scheduler.wakeTask(self.task_id);
    }
    
    pub fn wakeByRef(self: *const Self) void {
        self.wake();
    }
};

/// Context重构 - 真正的异步上下文
pub const Context = struct {
    waker: Waker,
    event_loop: *AsyncEventLoop,
    
    pub fn shouldYield(self: *const Self) bool {
        // 基于事件循环状态决定是否让出
        return self.event_loop.shouldYield();
    }
};
```

### Week 2: await_fn真正异步化

#### 2.1 非阻塞await实现
```zig
/// ✅ 真正的异步await实现
pub fn await_fn(future: anytype) @TypeOf(future).Output {
    const current_task = getCurrentTask();
    const waker = Waker{
        .task_id = current_task.id,
        .scheduler = current_task.scheduler,
    };
    var ctx = Context{
        .waker = waker,
        .event_loop = current_task.event_loop,
    };
    
    var fut = future;
    while (true) {
        switch (fut.poll(&ctx)) {
            .ready => |result| return result,
            .pending => {
                // ✅ 真正的异步：暂停当前任务，让出控制权
                current_task.suspend();
                // 当I/O就绪时，waker会重新唤醒这个任务
                current_task.scheduler.yield();
            },
        }
    }
}
```

#### 2.2 任务暂停/恢复机制
```zig
/// 任务状态管理
pub const Task = struct {
    id: TaskId,
    state: TaskState,
    future: *anyopaque,
    scheduler: *TaskScheduler,
    event_loop: *AsyncEventLoop,
    
    const TaskState = enum {
        ready,      // 就绪，可以执行
        running,    // 正在执行
        suspended,  // 暂停，等待I/O
        completed,  // 已完成
    };
    
    pub fn suspend(self: *Self) void {
        self.state = .suspended;
        // 任务将在waker.wake()时重新变为ready
    }
    
    pub fn resume(self: *Self) void {
        self.state = .ready;
        self.scheduler.scheduleTask(self);
    }
};
```

### Week 3: async_fn状态机重构

#### 3.1 真正的异步函数状态机
```zig
/// ✅ 支持暂停/恢复的async_fn
pub fn async_fn(comptime func: anytype) type {
    return struct {
        const Self = @This();
        
        // 状态机状态
        state: union(enum) {
            initial,
            suspended: SuspendPoint,
            completed: ReturnType,
        },
        
        // 暂停点信息
        const SuspendPoint = struct {
            pc: usize,              // 程序计数器
            locals: LocalVars,      // 局部变量
            await_future: ?*anyopaque, // 等待的Future
        };
        
        pub fn poll(self: *Self, ctx: *Context) Poll(ReturnType) {
            switch (self.state) {
                .initial => {
                    // 开始执行，可能在await点暂停
                    return self.executeWithSuspension(ctx);
                },
                .suspended => |suspend_point| {
                    // 从暂停点恢复执行
                    return self.resumeFromSuspension(suspend_point, ctx);
                },
                .completed => |result| {
                    return .{ .ready = result };
                },
            }
        }
        
        fn executeWithSuspension(self: *Self, ctx: *Context) Poll(ReturnType) {
            // 使用编译时生成的状态机执行函数
            return comptime generateStateMachine(func)(self, ctx);
        }
    };
}
```

#### 3.2 编译时状态机生成
```zig
/// 编译时分析函数并生成状态机
fn generateStateMachine(comptime func: anytype) fn(*anytype, *Context) Poll(ReturnType) {
    // 分析函数中的await调用点
    const await_points = comptime analyzeAwaitPoints(func);
    
    return struct {
        fn execute(self: *anytype, ctx: *Context) Poll(ReturnType) {
            // 根据当前状态跳转到正确的执行点
            switch (self.state) {
                .initial => {
                    // 从函数开始执行
                    return executeFromStart(self, ctx);
                },
                .suspended => |sp| {
                    // 从暂停点恢复
                    return executeFromSuspendPoint(self, ctx, sp);
                },
                else => unreachable,
            }
        }
    }.execute;
}
```

### Week 4: I/O系统真正异步化

#### 4.1 基于事件的I/O Future
```zig
/// ✅ 真正异步的TCP读取
pub const ReadFuture = struct {
    fd: std.posix.socket_t,
    buffer: []u8,
    registered: bool = false,
    
    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!usize) {
        if (!self.registered) {
            // 注册I/O事件到事件循环
            ctx.event_loop.registerRead(self.fd, ctx.waker);
            self.registered = true;
            return .pending;
        }
        
        // 检查I/O是否就绪
        if (!ctx.event_loop.isReadReady(self.fd)) {
            return .pending;
        }
        
        // I/O就绪，执行非阻塞读取
        const result = std.posix.read(self.fd, self.buffer);
        return switch (result) {
            .ok => |bytes_read| .{ .ready = bytes_read },
            .err => |err| switch (err) {
                error.WouldBlock => .pending,
                else => .{ .ready = err },
            },
        };
    }
};
```

## 🔧 Phase 2: 高性能调度器实现 (3周)

### Week 5-6: Work-Stealing调度器

#### 2.1 多线程工作窃取
```zig
/// 🚀 高性能工作窃取调度器
pub const WorkStealingScheduler = struct {
    workers: []Worker,
    global_queue: GlobalQueue,
    
    const Worker = struct {
        id: u32,
        local_queue: LocalQueue,
        stealer: WorkStealer,
        parker: Parker,
        
        pub fn run(self: *Self) void {
            while (true) {
                // 1. 检查本地队列
                if (self.local_queue.pop()) |task| {
                    self.executeTask(task);
                    continue;
                }
                
                // 2. 尝试从全局队列获取
                if (self.global_queue.steal()) |task| {
                    self.executeTask(task);
                    continue;
                }
                
                // 3. 尝试从其他worker窃取
                if (self.stealer.stealFromOthers()) |task| {
                    self.executeTask(task);
                    continue;
                }
                
                // 4. 没有任务，进入休眠
                self.parker.park();
            }
        }
    };
};
```

### Week 7: 负载均衡和公平性

#### 2.2 智能负载均衡
```zig
/// 负载均衡策略
pub const LoadBalancer = struct {
    workers: []Worker,
    load_metrics: []LoadMetric,
    
    pub fn scheduleTask(self: *Self, task: *Task) void {
        // 选择负载最轻的worker
        const target_worker = self.selectOptimalWorker();
        target_worker.scheduleTask(task);
    }
    
    fn selectOptimalWorker(self: *Self) *Worker {
        var min_load: f32 = std.math.inf(f32);
        var best_worker: *Worker = &self.workers[0];
        
        for (self.workers, self.load_metrics) |*worker, metric| {
            const load = metric.calculateLoad();
            if (load < min_load) {
                min_load = load;
                best_worker = worker;
            }
        }
        
        return best_worker;
    }
};
```

## 🔧 Phase 3: 生产级特性实现 (3周)

### Week 8: 高级Future组合子

#### 3.1 并发组合子
```zig
/// join - 等待多个Future完成
pub fn join(futures: anytype) JoinFuture(@TypeOf(futures)) {
    return JoinFuture(@TypeOf(futures)).init(futures);
}

/// select - 等待第一个完成的Future
pub fn select(futures: anytype) SelectFuture(@TypeOf(futures)) {
    return SelectFuture(@TypeOf(futures)).init(futures);
}

/// timeout - 为Future添加超时
pub fn timeout(future: anytype, duration: u64) TimeoutFuture(@TypeOf(future)) {
    return TimeoutFuture(@TypeOf(future)).init(future, duration);
}
```

### Week 9: 异步同步原语

#### 3.2 异步锁和通道
```zig
/// 异步互斥锁
pub const AsyncMutex = struct {
    locked: Atomic.Value(bool),
    waiters: WaiterQueue,
    
    pub fn lock(self: *Self) LockFuture {
        return LockFuture.init(self);
    }
};

/// 异步通道
pub fn Channel(comptime T: type) type {
    return struct {
        sender: Sender(T),
        receiver: Receiver(T),
        
        pub fn init(capacity: usize) !Self {
            // 实现有界异步通道
        }
    };
}
```

### Week 10: 性能优化和测试

#### 3.3 性能基准测试
```zig
/// 性能基准测试套件
pub const BenchmarkSuite = struct {
    pub fn runAllBenchmarks() !void {
        try benchmarkTaskSpawning();
        try benchmarkAsyncIO();
        try benchmarkMemoryAllocation();
        try benchmarkThroughput();
    }
    
    fn benchmarkTaskSpawning() !void {
        // 目标: 超越Tokio的800K ops/sec
        const start = std.time.nanoTimestamp();
        for (0..1_000_000) |_| {
            const task = async_fn(struct {
                fn dummy() void {}
            }.dummy);
            _ = try runtime.spawn(task);
        }
        const end = std.time.nanoTimestamp();
        
        const ops_per_sec = 1_000_000 * std.time.ns_per_s / (end - start);
        std.debug.print("Task spawning: {} ops/sec\n", .{ops_per_sec});
    }
};
```

## 📈 性能目标

### 核心指标
- **任务调度**: >1M ops/sec (vs Tokio 800K)
- **异步I/O**: >2M ops/sec (vs Tokio 1.2M)
- **内存分配**: >10M ops/sec (vs Tokio 1.5M)
- **延迟**: <10μs (vs Tokio ~50μs)

### 内存使用
- **任务开销**: <64 bytes/task
- **Future开销**: <32 bytes/future
- **总内存**: <100MB for 1M tasks

## 🎯 验收标准

### 功能完整性
- [ ] 真正的非阻塞await_fn
- [ ] 支持暂停/恢复的async_fn
- [ ] 基于事件循环的I/O
- [ ] 工作窃取调度器
- [ ] 完整的Future组合子
- [ ] 异步同步原语

### 性能要求
- [ ] 所有核心指标超越Tokio
- [ ] 零内存泄漏
- [ ] 跨平台兼容性
- [ ] 生产级稳定性

### 代码质量
- [ ] >95% 测试覆盖率
- [ ] 完整的文档
- [ ] 性能基准测试
- [ ] 内存安全验证

## 🚀 实施计划

### 里程碑
- **M1 (Week 4)**: 核心异步机制完成
- **M2 (Week 7)**: 调度器实现完成
- **M3 (Week 10)**: 生产级特性完成
- **M4 (Week 12)**: 性能优化和发布

### 风险缓解
1. **技术风险**: 分阶段实现，每周验证
2. **性能风险**: 持续基准测试
3. **兼容性风险**: 多平台CI/CD
4. **质量风险**: 代码审查和测试

## 🔍 技术深度分析

### 当前实现的根本问题

#### 问题1: await_fn的阻塞sleep
```zig
// ❌ 当前实现 - 阻塞整个线程
.pending => {
    std.time.sleep(1 * std.time.ns_per_ms);  // 阻塞1ms
},

// ✅ 正确实现 - 让出控制权
.pending => {
    current_task.suspend();
    scheduler.yield();  // 非阻塞让出
},
```

#### 问题2: async_fn的同步执行
```zig
// ❌ 当前实现 - 同步执行完整函数
const result = @call(.auto, func, args);

// ✅ 正确实现 - 状态机支持暂停
return self.executeStateMachine(ctx);
```

#### 问题3: I/O缺少事件循环集成
```zig
// ❌ 当前实现 - 直接系统调用
const result = std.posix.read(self.fd, self.buffer);

// ✅ 正确实现 - 事件循环集成
if (!ctx.event_loop.isReadReady(self.fd)) {
    ctx.event_loop.registerRead(self.fd, ctx.waker);
    return .pending;
}
```

### libxev集成策略

#### 深度集成libxev事件循环
```zig
/// libxev深度集成的事件循环
pub const ZokioEventLoop = struct {
    xev_loop: xev.Loop,
    io_registry: IoRegistry,
    timer_registry: TimerRegistry,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .xev_loop = try xev.Loop.init(.{}),
            .io_registry = IoRegistry.init(allocator),
            .timer_registry = TimerRegistry.init(allocator),
        };
    }

    /// 注册I/O事件
    pub fn registerRead(self: *Self, fd: std.posix.fd_t, waker: Waker) !void {
        var completion = xev.Completion{};
        self.xev_loop.read(&completion, fd, .{ .slice = &[_]u8{} }, void, null, readCallback);
        try self.io_registry.register(fd, waker, &completion);
    }

    fn readCallback(
        userdata: ?*void,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        _ = userdata;
        _ = loop;

        // 从completion获取waker并唤醒任务
        const waker = @as(*Waker, @ptrFromInt(completion.userdata));
        waker.wake();

        return .disarm;
    }
};
```

## 🏗️ 实施细节

### Phase 1 详细实施步骤

#### Step 1.1: 重构Context和Waker
```zig
/// 新的Context实现
pub const Context = struct {
    waker: Waker,
    event_loop: *ZokioEventLoop,
    task_locals: *TaskLocalStorage,

    pub fn registerTimer(self: *Self, duration: u64, waker: Waker) !TimerHandle {
        return self.event_loop.registerTimer(duration, waker);
    }

    pub fn registerIo(self: *Self, fd: std.posix.fd_t, interest: IoInterest) !IoHandle {
        return self.event_loop.registerIo(fd, interest, self.waker);
    }
};

/// 高效的Waker实现
pub const Waker = struct {
    task_id: TaskId,
    scheduler_ptr: *TaskScheduler,

    pub fn wake(self: Self) void {
        self.scheduler_ptr.wakeTask(self.task_id);
    }

    pub fn wakeByRef(self: *const Self) void {
        self.wake();
    }

    pub fn willWake(self: *const Self, other: *const Self) bool {
        return self.task_id == other.task_id;
    }
};
```

#### Step 1.2: 任务生命周期管理
```zig
/// 完整的任务生命周期
pub const Task = struct {
    id: TaskId,
    state: Atomic.Value(TaskState),
    future: *anyopaque,
    poll_fn: *const fn(*anyopaque, *Context) Poll(void),
    scheduler: *TaskScheduler,
    stack: ?[]u8,  // 可选的专用栈

    const TaskState = enum(u8) {
        created,
        scheduled,
        running,
        suspended,
        completed,
        cancelled,
    };

    pub fn poll(self: *Self, ctx: *Context) Poll(void) {
        const old_state = self.state.swap(.running, .acquire);
        defer {
            const new_state: TaskState = switch (old_state) {
                .cancelled => .cancelled,
                else => .scheduled,
            };
            self.state.store(new_state, .release);
        }

        return self.poll_fn(self.future, ctx);
    }

    pub fn cancel(self: *Self) void {
        _ = self.state.compareAndSwap(.scheduled, .cancelled, .acq_rel, .acquire);
    }
};
```

### Phase 2 调度器架构

#### 多级队列调度
```zig
/// 多级反馈队列调度器
pub const MultiLevelScheduler = struct {
    high_priority: LockFreeQueue(TaskId),
    normal_priority: LockFreeQueue(TaskId),
    low_priority: LockFreeQueue(TaskId),
    io_tasks: LockFreeQueue(TaskId),

    workers: []Worker,
    load_balancer: LoadBalancer,

    pub fn scheduleTask(self: *Self, task_id: TaskId, priority: Priority) void {
        const queue = switch (priority) {
            .high => &self.high_priority,
            .normal => &self.normal_priority,
            .low => &self.low_priority,
            .io => &self.io_tasks,
        };

        queue.push(task_id);
        self.load_balancer.notifyNewTask();
    }

    pub fn nextTask(self: *Self, worker_id: u32) ?TaskId {
        // 优先级顺序：high -> io -> normal -> low
        if (self.high_priority.pop()) |task_id| return task_id;
        if (self.io_tasks.pop()) |task_id| return task_id;
        if (self.normal_priority.pop()) |task_id| return task_id;
        if (self.low_priority.pop()) |task_id| return task_id;

        // 尝试工作窃取
        return self.stealFromOtherWorkers(worker_id);
    }
};
```

### Phase 3 高级特性

#### 异步迭代器
```zig
/// 异步迭代器trait
pub fn AsyncIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Item = T;

        /// 获取下一个元素
        pub fn next(self: *Self) NextFuture(T) {
            return NextFuture(T).init(self);
        }

        /// 收集所有元素到Vec
        pub fn collect(self: *Self, allocator: std.mem.Allocator) CollectFuture(T) {
            return CollectFuture(T).init(self, allocator);
        }

        /// 异步map操作
        pub fn map(self: *Self, comptime func: anytype) MapIterator(Self, @TypeOf(func)) {
            return MapIterator(Self, @TypeOf(func)).init(self, func);
        }

        /// 异步filter操作
        pub fn filter(self: *Self, comptime predicate: anytype) FilterIterator(Self, @TypeOf(predicate)) {
            return FilterIterator(Self, @TypeOf(predicate)).init(self, predicate);
        }
    };
}
```

#### 流处理
```zig
/// 异步流处理
pub fn Stream(comptime T: type) type {
    return struct {
        const Self = @This();

        /// 从迭代器创建流
        pub fn fromIterator(iter: anytype) Self {
            return Self{ .source = .{ .iterator = iter } };
        }

        /// 缓冲流
        pub fn buffered(self: Self, size: usize) BufferedStream(T) {
            return BufferedStream(T).init(self, size);
        }

        /// 并行处理
        pub fn parallel(self: Self, concurrency: usize) ParallelStream(T) {
            return ParallelStream(T).init(self, concurrency);
        }

        /// 背压控制
        pub fn withBackpressure(self: Self, strategy: BackpressureStrategy) BackpressureStream(T) {
            return BackpressureStream(T).init(self, strategy);
        }
    };
}
```

## 📊 性能优化策略

### 内存优化
1. **对象池**: 预分配Task、Future、Waker对象
2. **栈复用**: 协程栈的智能复用
3. **零拷贝**: 最小化数据复制
4. **缓存友好**: 数据结构的缓存行对齐

### CPU优化
1. **分支预测**: 优化热路径的分支
2. **SIMD**: 利用向量指令加速
3. **编译时优化**: 最大化comptime计算
4. **内联**: 关键路径的函数内联

### I/O优化
1. **批量操作**: 批量提交I/O请求
2. **预读**: 智能预读策略
3. **写合并**: 合并小的写操作
4. **零拷贝网络**: sendfile等零拷贝技术

## 🧪 测试策略

### 单元测试
- 每个模块>95%覆盖率
- 边界条件测试
- 错误路径测试
- 内存安全测试

### 集成测试
- 端到端异步流程
- 多线程并发测试
- 压力测试
- 长时间运行测试

### 性能测试
- 微基准测试
- 宏基准测试
- 内存使用分析
- 延迟分布分析

### 兼容性测试
- Linux (epoll, io_uring)
- macOS (kqueue)
- Windows (IOCP)
- 不同Zig版本

## 🎯 关键技术决策

### 1. 为什么选择libxev而不是自建事件循环？

**优势分析**：
- **成熟稳定**: libxev已经过生产验证
- **跨平台**: 统一的API支持epoll/kqueue/IOCP
- **高性能**: 针对Zig优化的C库
- **维护成本**: 减少底层平台代码维护

**集成策略**：
```zig
/// Zokio对libxev的封装
pub const ZokioIoDriver = struct {
    xev_loop: xev.Loop,
    completion_pool: CompletionPool,
    waker_map: WakerMap,

    /// 高级封装：异步读取
    pub fn asyncRead(self: *Self, fd: std.posix.fd_t, buffer: []u8) ReadFuture {
        return ReadFuture{
            .driver = self,
            .fd = fd,
            .buffer = buffer,
            .completion = self.completion_pool.acquire(),
        };
    }

    /// 批量I/O提交
    pub fn submitBatch(self: *Self, operations: []IoOperation) !void {
        for (operations) |op| {
            switch (op) {
                .read => |read_op| try self.submitRead(read_op),
                .write => |write_op| try self.submitWrite(write_op),
                .accept => |accept_op| try self.submitAccept(accept_op),
            }
        }
    }
};
```

### 2. 状态机 vs 协程栈

**选择状态机的原因**：
- **内存效率**: 每个任务只需要保存必要状态
- **编译时优化**: Zig的comptime可以生成最优状态机
- **可预测性**: 状态转换明确，便于调试
- **性能**: 避免栈切换开销

**状态机生成示例**：
```zig
/// 编译时状态机生成
pub fn generateAsyncStateMachine(comptime func: anytype) type {
    const func_info = @typeInfo(@TypeOf(func));
    const await_points = comptime analyzeAwaitPoints(func);

    return struct {
        const State = enum(u8) {
            start,
            // 为每个await点生成状态
            inline for (await_points, 0..) |point, i| {
                @field("await_" ++ std.fmt.comptimePrint("{}", .{i}), i + 1),
            },
            completed,
        };

        state: State = .start,
        locals: LocalVars,
        result: ?ReturnType = null,

        pub fn poll(self: *Self, ctx: *Context) Poll(ReturnType) {
            while (true) {
                switch (self.state) {
                    .start => {
                        // 执行到第一个await点
                        return self.executeToFirstAwait(ctx);
                    },
                    inline else => |state_tag| {
                        // 从特定await点恢复执行
                        return self.resumeFromAwait(state_tag, ctx);
                    },
                    .completed => {
                        return .{ .ready = self.result.? };
                    },
                }
            }
        }
    };
}
```

### 3. 工作窃取 vs 全局队列

**工作窃取优势**：
- **负载均衡**: 自动平衡工作负载
- **缓存局部性**: 减少跨核心通信
- **可扩展性**: 随CPU核心数线性扩展

**实现细节**：
```zig
/// 无锁工作窃取队列
pub fn WorkStealingQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        // 双端队列，支持从两端操作
        items: []Atomic.Value(?T),
        head: Atomic.Value(usize),  // 所有者从head取
        tail: Atomic.Value(usize),  // 窃取者从tail取
        mask: usize,

        /// 所有者推入任务（LIFO）
        pub fn push(self: *Self, item: T) bool {
            const head = self.head.load(.relaxed);
            const tail = self.tail.load(.acquire);

            if (head - tail >= self.items.len) {
                return false; // 队列满
            }

            self.items[head & self.mask].store(item, .relaxed);
            self.head.store(head + 1, .release);
            return true;
        }

        /// 所有者弹出任务（LIFO）
        pub fn pop(self: *Self) ?T {
            const head = self.head.load(.relaxed);
            if (head == 0) return null;

            const new_head = head - 1;
            self.head.store(new_head, .relaxed);

            const item = self.items[new_head & self.mask].load(.relaxed);

            // 检查是否与窃取者冲突
            const tail = self.tail.load(.acquire);
            if (new_head > tail) {
                return item;
            }

            // 冲突处理
            self.head.store(head, .relaxed);
            if (new_head == tail) {
                if (self.tail.compareAndSwap(tail, tail + 1, .acq_rel, .relaxed)) |_| {
                    return item;
                }
            }
            return null;
        }

        /// 窃取者窃取任务（FIFO）
        pub fn steal(self: *Self) ?T {
            const tail = self.tail.load(.acquire);
            const head = self.head.load(.acquire);

            if (tail >= head) return null;

            const item = self.items[tail & self.mask].load(.relaxed);
            if (self.tail.compareAndSwap(tail, tail + 1, .acq_rel, .relaxed)) |_| {
                return item;
            }
            return null;
        }
    };
}
```

## 🚀 实施路线图

### Phase 1: 基础设施 (Week 1-4)

#### Week 1: 事件循环重构
**目标**: 建立真正的异步事件循环基础

**任务清单**:
- [ ] 重构Context和Waker系统
- [ ] 深度集成libxev事件循环
- [ ] 实现I/O事件注册和回调
- [ ] 建立定时器轮询机制
- [ ] 编写基础单元测试

**验收标准**:
```zig
// 测试：事件循环基本功能
test "event loop basic functionality" {
    var loop = try ZokioEventLoop.init(testing.allocator);
    defer loop.deinit();

    var waker_called = false;
    const waker = Waker.init(&waker_called);

    // 注册定时器
    try loop.registerTimer(100, waker);

    // 运行事件循环
    try loop.runOnce();

    // 验证waker被调用
    try testing.expect(waker_called);
}
```

#### Week 2: await_fn重构
**目标**: 实现真正的非阻塞await

**任务清单**:
- [ ] 重写await_fn实现
- [ ] 实现任务暂停/恢复机制
- [ ] 建立任务调度接口
- [ ] 实现基本的任务生命周期管理
- [ ] 性能基准测试

**验收标准**:
```zig
// 测试：非阻塞await
test "non-blocking await" {
    const TestFuture = struct {
        ready: bool = false,

        pub fn poll(self: *@This(), ctx: *Context) Poll(u32) {
            if (self.ready) {
                return .{ .ready = 42 };
            } else {
                // 模拟异步操作
                ctx.waker.wake();
                return .pending;
            }
        }
    };

    var future = TestFuture{};
    const result = await_fn(future);
    try testing.expectEqual(@as(u32, 42), result);
}
```

#### Week 3: async_fn状态机
**目标**: 实现支持暂停/恢复的async函数

**任务清单**:
- [ ] 设计状态机结构
- [ ] 实现编译时状态机生成
- [ ] 支持局部变量保存/恢复
- [ ] 实现await点分析
- [ ] 集成测试

**验收标准**:
```zig
// 测试：async函数状态机
test "async function state machine" {
    const asyncFunc = async_fn(struct {
        fn testFunc() !u32 {
            const a = await_fn(DelayFuture.init(10));
            const b = await_fn(DelayFuture.init(20));
            return a + b;
        }
    }.testFunc);

    var func_instance = asyncFunc{};
    const result = await_fn(func_instance);
    try testing.expectEqual(@as(u32, 30), result);
}
```

#### Week 4: I/O系统集成
**目标**: 将I/O操作集成到事件循环

**任务清单**:
- [ ] 重构TCP读写Future
- [ ] 实现事件驱动的I/O
- [ ] 支持批量I/O操作
- [ ] 实现背压控制
- [ ] 端到端测试

**验收标准**:
```zig
// 测试：异步TCP I/O
test "async TCP I/O" {
    var server = try TcpListener.bind("127.0.0.1:0");
    defer server.close();

    const addr = server.localAddr();

    // 异步接受连接
    const accept_task = async_fn(struct {
        fn acceptConnection(listener: *TcpListener) !TcpStream {
            return await_fn(listener.accept());
        }
    }.acceptConnection);

    // 异步连接
    const connect_task = async_fn(struct {
        fn connectToServer(address: SocketAddr) !TcpStream {
            return await_fn(TcpStream.connect(address));
        }
    }.connectToServer);

    const results = await_fn(join(.{ accept_task, connect_task }));
    // 验证连接成功
}
```

### Phase 2: 调度器实现 (Week 5-7)

#### Week 5: 基础调度器
**目标**: 实现单线程调度器

**关键组件**:
```zig
/// 单线程调度器
pub const SingleThreadedScheduler = struct {
    ready_queue: TaskQueue,
    current_task: ?*Task,
    task_pool: TaskPool,

    pub fn spawn(self: *Self, future: anytype) !TaskHandle {
        const task = try self.task_pool.acquire();
        task.init(future);
        self.ready_queue.push(task);
        return TaskHandle{ .task_id = task.id };
    }

    pub fn run(self: *Self) !void {
        while (self.ready_queue.pop()) |task| {
            self.current_task = task;

            const ctx = Context{
                .waker = Waker{ .task = task, .scheduler = self },
                .event_loop = &self.event_loop,
            };

            switch (task.poll(&ctx)) {
                .ready => {
                    task.complete();
                    self.task_pool.release(task);
                },
                .pending => {
                    // 任务被暂停，等待唤醒
                },
            }

            self.current_task = null;
        }
    }
};
```

#### Week 6: 多线程调度器
**目标**: 实现工作窃取调度器

#### Week 7: 负载均衡优化
**目标**: 实现智能负载均衡

### Phase 3: 高级特性 (Week 8-10)

#### Week 8: Future组合子
#### Week 9: 异步同步原语
#### Week 10: 性能优化

## 📈 成功指标

### 技术指标
- **编译时间**: <30秒 (完整构建)
- **二进制大小**: <2MB (release模式)
- **启动时间**: <1ms
- **内存占用**: <10MB (基础运行时)

### 质量指标
- **测试覆盖率**: >95%
- **文档覆盖率**: >90%
- **基准测试**: 100%覆盖核心API
- **内存泄漏**: 0个

### 生态指标
- **示例项目**: >10个
- **第三方集成**: >5个
- **社区贡献**: >20个PR
- **文档质量**: 完整的教程和API文档

这个计划将把Zokio从当前的"伪异步"实现升级为真正的生产级异步运行时，在保持现有优秀API设计的基础上，实现真正的异步性能和功能。
