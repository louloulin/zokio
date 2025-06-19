# Zokio 统一异步运行时架构设计

## 🔍 当前代码分析

### 现有架构问题

通过对整个代码库的深入分析，发现以下关键问题：

1. **双运行时架构混乱**:
   - 同时存在`runtime.zig`的`ZokioRuntime`和`simple_runtime.zig`的`SimpleRuntime`
   - 两套不同的API和实现路径
   - 用户困惑于选择哪个运行时

2. **SimpleRuntime的伪异步问题**:
   - `SimpleRuntime.blockOn()` 只是简单的轮询+sleep
   - 没有真正的工作线程池和任务调度器
   - 性能测试显示的高性能数据是Mock的

3. **I/O系统架构分散**:
   - `io.zig`中有多个后端实现（io_uring、epoll、kqueue等）
   - 但都是模拟实现，没有真正的异步I/O
   - libxev集成不完整，只是可选依赖

4. **API不一致**:
   - `lib.zig`中同时导出两套运行时API
   - 示例和文档中混用不同的运行时
   - 缺乏统一的使用模式

## 🎯 统一运行时架构设计

### 核心设计原则

1. **单一运行时**: 删除SimpleRuntime，统一使用基于libxev的真实异步运行时
2. **libxev优先**: 完全基于libxev实现I/O，移除所有自定义后端
3. **Tokio兼容**: API和架构与Tokio保持一致
4. **Zig优化**: 充分利用Zig的编译时特性

### 统一后的架构

```zig
// 唯一的运行时入口
pub const Runtime = struct {
    scheduler: MultiThreadScheduler,
    handle: Handle,
    io_driver: LibxevDriver,
    blocking_pool: BlockingPool,

    pub fn new() !Runtime {
        return Builder.new_multi_thread().enable_all().build();
    }

    pub fn spawn(self: *Runtime, future: anytype) JoinHandle(@TypeOf(future).Output) {
        return self.scheduler.spawn(future);
    }

    pub fn block_on(self: *Runtime, future: anytype) !@TypeOf(future).Output {
        return self.scheduler.block_on(&self.handle, future);
    }
};

// 构建器模式
pub const Builder = struct {
    worker_threads: ?usize = null,
    enable_io: bool = true,
    enable_time: bool = true,

    pub fn new_multi_thread() Builder;
    pub fn worker_threads(self: Builder, threads: usize) Builder;
    pub fn enable_all(self: Builder) Builder;
    pub fn build(self: Builder) !Runtime;
};
```

### libxev集成架构

```zig
// 统一的I/O驱动 - 完全基于libxev
pub const LibxevDriver = struct {
    loop: xev.Loop,
    thread_pool: xev.ThreadPool,
    completions: std.ArrayList(xev.Completion),

    pub fn init(allocator: Allocator) !LibxevDriver;
    pub fn submit_read(self: *LibxevDriver, fd: fd_t, buffer: []u8) !IoFuture;
    pub fn submit_write(self: *LibxevDriver, fd: fd_t, data: []const u8) !IoFuture;
    pub fn poll(self: *LibxevDriver, timeout_ms: u32) !u32;
};
```

## 🚀 统一运行时改进计划

### 阶段1: 删除SimpleRuntime，统一运行时架构

#### 1.1 代码重构路径

**删除的文件**:
- `src/runtime/simple_runtime.zig` - 完全删除
- `src/io/io.zig`中的多后端实现 - 简化为libxev统一后端

**重构的文件**:
- `src/runtime/runtime.zig` - 重命名为统一的Runtime
- `src/lib.zig` - 移除SimpleRuntime相关导出
- `build.zig` - 移除SimpleRuntime相关配置

**新增的文件**:
- `src/runtime/libxev_runtime.zig` - 基于libxev的统一运行时
- `src/io/libxev_driver.zig` - libxev I/O驱动
- `src/runtime/builder.zig` - 运行时构建器

#### 1.2 统一的Runtime实现

```zig
// src/runtime/runtime.zig - 统一的运行时实现
const std = @import("std");
const xev = @import("libxev");

/// 统一的Zokio运行时 - 替代所有其他运行时实现
pub const Runtime = struct {
    scheduler: MultiThreadScheduler,
    handle: Handle,
    io_driver: LibxevDriver,
    blocking_pool: BlockingPool,
    allocator: std.mem.Allocator,

    /// 创建新的运行时实例
    pub fn new() !Runtime {
        return Builder.new_multi_thread().enable_all().build();
    }

    /// 生成新的异步任务
    pub fn spawn(self: *Runtime, future: anytype) JoinHandle(@TypeOf(future).Output) {
        return self.scheduler.spawn(future);
    }

    /// 阻塞执行异步任务直到完成
    pub fn block_on(self: *Runtime, future: anytype) !@TypeOf(future).Output {
        return self.scheduler.block_on(&self.handle, future);
    }

    /// 关闭运行时
    pub fn shutdown(self: *Runtime) void {
        self.scheduler.shutdown(&self.handle);
        self.io_driver.deinit();
        self.blocking_pool.shutdown();
    }

    /// 获取运行时句柄
    pub fn handle(self: *Runtime) *Handle {
        return &self.handle;
    }
};

/// 运行时构建器
pub const Builder = struct {
    worker_threads: ?usize = null,
    enable_io: bool = true,
    enable_time: bool = true,
    thread_name: ?[]const u8 = null,
    thread_stack_size: ?usize = null,

    /// 创建多线程运行时构建器
    pub fn new_multi_thread() Builder {
        return Builder{};
    }

    /// 设置工作线程数
    pub fn worker_threads(self: Builder, threads: usize) Builder {
        var new_self = self;
        new_self.worker_threads = threads;
        return new_self;
    }

    /// 启用所有功能
    pub fn enable_all(self: Builder) Builder {
        var new_self = self;
        new_self.enable_io = true;
        new_self.enable_time = true;
        return new_self;
    }

    /// 启用I/O功能
    pub fn enable_io(self: Builder) Builder {
        var new_self = self;
        new_self.enable_io = true;
        return new_self;
    }

    /// 启用定时器功能
    pub fn enable_time(self: Builder) Builder {
        var new_self = self;
        new_self.enable_time = true;
        return new_self;
    }

    /// 设置线程名称
    pub fn thread_name(self: Builder, name: []const u8) Builder {
        var new_self = self;
        new_self.thread_name = name;
        return new_self;
    }

    /// 构建运行时实例
    pub fn build(self: Builder) !Runtime {
        const allocator = std.heap.page_allocator;

        // 创建libxev I/O驱动
        var io_driver = try LibxevDriver.init(allocator);

        // 创建阻塞任务池
        var blocking_pool = try BlockingPool.init(allocator, .{
            .max_threads = 512,
        });

        // 创建多线程调度器
        const worker_count = self.worker_threads orelse std.Thread.getCpuCount() catch 4;
        var scheduler = try MultiThreadScheduler.new(
            worker_count,
            &io_driver,
            &blocking_pool,
            allocator
        );

        // 创建运行时句柄
        var handle = Handle{
            .scheduler = &scheduler,
            .io_driver = &io_driver,
            .blocking_pool = &blocking_pool,
        };

        return Runtime{
            .scheduler = scheduler,
            .handle = handle,
            .io_driver = io_driver,
            .blocking_pool = blocking_pool,
            .allocator = allocator,
        };
    }
};

/// 运行时句柄 - 用于跨线程访问运行时功能
pub const Handle = struct {
    scheduler: *MultiThreadScheduler,
    io_driver: *LibxevDriver,
    blocking_pool: *BlockingPool,

    /// 生成新任务
    pub fn spawn(self: *Handle, future: anytype) JoinHandle(@TypeOf(future).Output) {
        return self.scheduler.spawn(future);
    }

    /// 生成阻塞任务
    pub fn spawn_blocking(self: *Handle, func: anytype) JoinHandle(@TypeOf(func).ReturnType) {
        return self.blocking_pool.spawn(func);
    }
};
```

#### 1.2 实现真正的多线程调度器

```zig
// src/runtime/scheduler/multi_thread.zig - 基于Tokio架构的调度器
pub const MultiThreadScheduler = struct {
    workers: []Worker,
    shared: *Shared,
    allocator: std.mem.Allocator,

    pub fn new(
        size: usize,
        io_driver: *LibxevDriver,
        blocking_pool: *BlockingPool,
        allocator: std.mem.Allocator
    ) !MultiThreadScheduler {
        // 创建共享状态
        var shared = try allocator.create(Shared);
        shared.* = try Shared.init(size, io_driver, blocking_pool, allocator);

        // 创建工作线程
        var workers = try allocator.alloc(Worker, size);
        for (workers, 0..) |*worker, i| {
            worker.* = try Worker.init(i, shared, allocator);
        }

        // 启动工作线程
        for (workers) |*worker| {
            try worker.start();
        }

        return MultiThreadScheduler{
            .workers = workers,
            .shared = shared,
            .allocator = allocator,
        };
    }

    pub fn spawn(self: *MultiThreadScheduler, future: anytype) JoinHandle(@TypeOf(future).Output) {
        const task = Task.new(future, self.allocator) catch unreachable;
        const join_handle = JoinHandle(@TypeOf(future).Output).new(task.id);

        // 尝试放入当前工作线程的本地队列
        if (self.getCurrentWorker()) |worker| {
            if (worker.core.local_queue.push(task)) {
                return join_handle;
            }
        }

        // 放入全局注入队列
        self.shared.inject_queue.push(task);
        self.shared.notify_work_available();

        return join_handle;
    }

    pub fn blockOn(self: *MultiThreadScheduler, handle: *Handle, future: anytype) !@TypeOf(future).Output {
        // 进入运行时上下文
        const _enter = handle.enter();

        // 如果在工作线程上，使用特殊的block_on逻辑
        if (self.getCurrentWorker()) |worker| {
            return worker.blockOnWorker(future);
        }

        // 在非工作线程上，创建一个专用的parker
        var parker = try Parker.new();
        defer parker.deinit();

        var fut = future;
        var waker = Waker.from_parker(&parker);
        var context = Context{ .waker = waker };

        while (true) {
            switch (fut.poll(&context)) {
                .ready => |result| return result,
                .pending => {
                    // 运行一些I/O事件
                    _ = handle.io_driver.poll(1) catch 0;

                    // 停泊等待唤醒
                    parker.park();
                },
            }
        }
    }

    pub fn shutdown(self: *MultiThreadScheduler, handle: *Handle) void {
        _ = handle;

        // 关闭注入队列
        self.shared.inject_queue.close();

        // 通知所有工作线程关闭
        for (self.workers) |*worker| {
            worker.shutdown();
        }

        // 等待所有工作线程结束
        for (self.workers) |*worker| {
            worker.join();
        }

        // 清理资源
        self.shared.deinit();
        self.allocator.destroy(self.shared);
        self.allocator.free(self.workers);
    }

    fn getCurrentWorker(self: *MultiThreadScheduler) ?*Worker {
        const current_thread_id = std.Thread.getCurrentId();
        for (self.workers) |*worker| {
            if (worker.thread_id == current_thread_id) {
                return worker;
            }
        }
        return null;
    }
};
```

#### 1.3 实现Worker和Core

```zig
// src/runtime/worker.zig - 工作线程实现
pub const Worker = struct {
    index: usize,
    shared: *Shared,
    core: Core,
    thread: ?std.Thread = null,
    thread_id: std.Thread.Id = undefined,
    running: std.atomic.Value(bool),
    allocator: std.mem.Allocator,

    pub fn init(index: usize, shared: *Shared, allocator: std.mem.Allocator) !Worker {
        return Worker{
            .index = index,
            .shared = shared,
            .core = try Core.init(allocator),
            .running = std.atomic.Value(bool).init(false),
            .allocator = allocator,
        };
    }

    pub fn start(self: *Worker) !void {
        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, workerMain, .{self});
        self.thread_id = self.thread.?.getId();
    }

    pub fn shutdown(self: *Worker) void {
        self.running.store(false, .release);
    }

    pub fn join(self: *Worker) void {
        if (self.thread) |thread| {
            thread.join();
        }
    }

    pub fn blockOnWorker(self: *Worker, future: anytype) !@TypeOf(future).Output {
        var fut = future;
        var waker = Waker.noop(); // 在工作线程上不需要真正的waker
        var context = Context{ .waker = waker };

        while (true) {
            switch (fut.poll(&context)) {
                .ready => |result| return result,
                .pending => {
                    // 运行其他任务
                    if (self.runSomeTasks()) {
                        continue; // 运行了一些任务，再次尝试
                    }

                    // 尝试窃取工作
                    if (self.stealWork()) {
                        continue;
                    }

                    // 运行I/O事件
                    _ = self.shared.io_driver.poll(1) catch 0;
                },
            }
        }
    }

    fn workerMain(self: *Worker) void {
        while (self.running.load(.acquire)) {
            // 1. 运行LIFO槽中的任务
            if (self.core.lifo_slot) |task| {
                self.core.lifo_slot = null;
                self.runTask(task);
                continue;
            }

            // 2. 运行本地队列中的任务
            if (self.core.local_queue.pop()) |task| {
                self.runTask(task);
                continue;
            }

            // 3. 从全局队列获取任务
            if (self.shared.inject_queue.pop()) |task| {
                self.runTask(task);
                continue;
            }

            // 4. 尝试窃取其他工作线程的任务
            if (self.stealWork()) {
                continue;
            }

            // 5. 运行I/O事件
            const io_events = self.shared.io_driver.poll(1) catch 0;
            if (io_events > 0) {
                continue;
            }

            // 6. 停泊等待工作
            self.park();
        }
    }

    fn runTask(self: *Worker, task: *Task) void {
        // 设置当前工作线程上下文
        const old_worker = current_worker;
        current_worker = self;
        defer current_worker = old_worker;

        // 运行任务
        task.run();

        // 更新统计信息
        self.core.stats.tasks_completed += 1;
    }

    fn runSomeTasks(self: *Worker) bool {
        var ran_any = false;
        var count: u32 = 0;

        // 最多运行16个任务
        while (count < 16) {
            if (self.core.local_queue.pop()) |task| {
                self.runTask(task);
                ran_any = true;
                count += 1;
            } else {
                break;
            }
        }

        return ran_any;
    }

    fn stealWork(self: *Worker) bool {
        // 随机选择一个其他工作线程进行窃取
        const target_index = self.core.rand.range(self.shared.workers.len);
        if (target_index == self.index) {
            return false;
        }

        const target_worker = &self.shared.workers[target_index];
        if (target_worker.core.local_queue.steal()) |task| {
            self.runTask(task);
            self.core.stats.tasks_stolen += 1;
            return true;
        }

        return false;
    }

    fn park(self: *Worker) void {
        // 简单的停泊实现：短暂休眠
        std.time.sleep(1 * std.time.ns_per_ms);
    }
};

pub const Core = struct {
    tick: u32 = 0,
    lifo_slot: ?*Task = null,
    lifo_enabled: bool = true,
    local_queue: WorkStealingQueue(*Task),
    is_searching: bool = false,
    is_shutdown: bool = false,
    stats: WorkerStats,
    rand: std.rand.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator) !Core {
        return Core{
            .local_queue = try WorkStealingQueue(*Task).init(allocator, 256),
            .stats = WorkerStats{},
            .rand = std.rand.DefaultPrng.init(@intCast(std.time.timestamp())),
        };
    }

    pub fn deinit(self: *Core) void {
        self.local_queue.deinit();
    }
};

pub const WorkerStats = struct {
    tasks_completed: u64 = 0,
    tasks_stolen: u64 = 0,
    park_count: u64 = 0,
    steal_attempts: u64 = 0,
};

// 线程本地存储当前工作线程
threadlocal var current_worker: ?*Worker = null;

pub fn getCurrentWorker() ?*Worker {
    return current_worker;
}
```

### 阶段2: 完全基于libxev的I/O驱动

#### 2.1 完全移除现有I/O后端，统一使用libxev

libxev是跨平台的高性能事件循环库，自动选择最佳后端：
- Linux: io_uring + epoll
- macOS: kqueue
- Windows: IOCP
- 其他: poll/select

```zig
// src/io/libxev_driver.zig - 完全基于libxev的I/O驱动
const xev = @import("libxev");

pub const LibxevDriver = struct {
    loop: xev.Loop,
    thread_pool: xev.ThreadPool,
    completions: std.ArrayList(xev.Completion),
    waker_map: std.HashMap(u64, Waker),
    next_id: std.atomic.Value(u64),

    pub fn init(allocator: Allocator, config: IoConfig) !LibxevDriver {
        return LibxevDriver{
            .loop = try xev.Loop.init(.{}),
            .thread_pool = try xev.ThreadPool.init(.{ .max_threads = config.io_threads }),
            .completions = std.ArrayList(xev.Completion).init(allocator),
            .waker_map = std.HashMap(u64, Waker).init(allocator),
            .next_id = std.atomic.Value(u64).init(1),
        };
    }

    pub fn deinit(self: *LibxevDriver) void {
        self.thread_pool.deinit();
        self.loop.deinit();
        self.completions.deinit();
        self.waker_map.deinit();
    }

    /// 运行事件循环（非阻塞）
    pub fn poll(self: *LibxevDriver, timeout_ms: u32) !u32 {
        const run_mode: xev.RunMode = if (timeout_ms == 0) .no_wait else .once;
        try self.loop.run(run_mode);

        // 处理完成的操作
        var completed: u32 = 0;
        while (self.completions.popOrNull()) |completion| {
            self.handleCompletion(completion);
            completed += 1;
        }

        return completed;
    }

    /// 提交异步读操作
    pub fn submitRead(self: *LibxevDriver, fd: std.posix.fd_t, buffer: []u8, waker: Waker) !u64 {
        const id = self.next_id.fetchAdd(1, .monotonic);
        try self.waker_map.put(id, waker);

        var completion = xev.Completion{
            .op = .{
                .read = .{
                    .fd = fd,
                    .buffer = .{ .slice = buffer },
                },
            },
            .userdata = id,
            .callback = readCallback,
        };

        self.loop.add(&completion);
        return id;
    }

    /// 提交异步写操作
    pub fn submitWrite(self: *LibxevDriver, fd: std.posix.fd_t, buffer: []const u8, waker: Waker) !u64 {
        const id = self.next_id.fetchAdd(1, .monotonic);
        try self.waker_map.put(id, waker);

        var completion = xev.Completion{
            .op = .{
                .write = .{
                    .fd = fd,
                    .buffer = .{ .slice = @constCast(buffer) },
                },
            },
            .userdata = id,
            .callback = writeCallback,
        };

        self.loop.add(&completion);
        return id;
    }

    /// 提交异步连接操作
    pub fn submitConnect(self: *LibxevDriver, fd: std.posix.fd_t, addr: std.net.Address, waker: Waker) !u64 {
        const id = self.next_id.fetchAdd(1, .monotonic);
        try self.waker_map.put(id, waker);

        var completion = xev.Completion{
            .op = .{
                .connect = .{
                    .fd = fd,
                    .addr = addr,
                },
            },
            .userdata = id,
            .callback = connectCallback,
        };

        self.loop.add(&completion);
        return id;
    }

    /// 提交异步接受操作
    pub fn submitAccept(self: *LibxevDriver, fd: std.posix.fd_t, waker: Waker) !u64 {
        const id = self.next_id.fetchAdd(1, .monotonic);
        try self.waker_map.put(id, waker);

        var completion = xev.Completion{
            .op = .{
                .accept = .{
                    .fd = fd,
                },
            },
            .userdata = id,
            .callback = acceptCallback,
        };

        self.loop.add(&completion);
        return id;
    }

    fn handleCompletion(self: *LibxevDriver, completion: xev.Completion) void {
        const id = completion.userdata;
        if (self.waker_map.get(id)) |waker| {
            waker.wake();
            _ = self.waker_map.remove(id);
        }
    }

    fn readCallback(userdata: ?*anyopaque, loop: *xev.Loop, completion: *xev.Completion, result: xev.Result) xev.CallbackAction {
        _ = userdata;
        _ = loop;
        _ = result;

        const driver: *LibxevDriver = @ptrFromInt(completion.userdata);
        driver.completions.append(completion.*) catch {};

        return .disarm;
    }

    fn writeCallback(userdata: ?*anyopaque, loop: *xev.Loop, completion: *xev.Completion, result: xev.Result) xev.CallbackAction {
        _ = userdata;
        _ = loop;
        _ = result;

        const driver: *LibxevDriver = @ptrFromInt(completion.userdata);
        driver.completions.append(completion.*) catch {};

        return .disarm;
    }

    fn connectCallback(userdata: ?*anyopaque, loop: *xev.Loop, completion: *xev.Completion, result: xev.Result) xev.CallbackAction {
        _ = userdata;
        _ = loop;
        _ = result;

        const driver: *LibxevDriver = @ptrFromInt(completion.userdata);
        driver.completions.append(completion.*) catch {};

        return .disarm;
    }

    fn acceptCallback(userdata: ?*anyopaque, loop: *xev.Loop, completion: *xev.Completion, result: xev.Result) xev.CallbackAction {
        _ = userdata;
        _ = loop;
        _ = result;

        const driver: *LibxevDriver = @ptrFromInt(completion.userdata);
        driver.completions.append(completion.*) catch {};

        return .disarm;
    }
};
```

#### 2.2 基于libxev的网络抽象

```zig
// src/net/tcp_stream.zig - 完全基于libxev的TCP流
const xev = @import("libxev");

pub const TcpStream = struct {
    fd: std.posix.fd_t,
    driver: *LibxevDriver,
    local_addr: ?std.net.Address = null,
    remote_addr: ?std.net.Address = null,

    pub fn connect(addr: std.net.Address, driver: *LibxevDriver) ConnectFuture {
        return ConnectFuture.init(addr, driver);
    }

    pub fn read(self: *TcpStream, buffer: []u8) ReadFuture {
        return ReadFuture.init(self.fd, buffer, self.driver);
    }

    pub fn write(self: *TcpStream, data: []const u8) WriteFuture {
        return WriteFuture.init(self.fd, data, self.driver);
    }

    pub fn close(self: *TcpStream) void {
        std.posix.close(self.fd);
    }

    pub fn setNodelay(self: *TcpStream, enable: bool) !void {
        const value: c_int = if (enable) 1 else 0;
        try std.posix.setsockopt(self.fd, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY, std.mem.asBytes(&value));
    }
};

pub const ConnectFuture = struct {
    addr: std.net.Address,
    driver: *LibxevDriver,
    state: State = .initial,
    fd: std.posix.fd_t = -1,
    operation_id: ?u64 = null,

    const State = enum { initial, connecting, completed, failed };

    pub fn init(addr: std.net.Address, driver: *LibxevDriver) ConnectFuture {
        return ConnectFuture{
            .addr = addr,
            .driver = driver,
        };
    }

    pub fn poll(self: *ConnectFuture, ctx: *Context) Poll(TcpStream) {
        switch (self.state) {
            .initial => {
                // 创建socket
                self.fd = std.posix.socket(self.addr.any.family, std.posix.SOCK.STREAM, 0) catch {
                    self.state = .failed;
                    return .{ .ready = error.SocketCreationFailed };
                };

                // 设置非阻塞
                const flags = std.posix.fcntl(self.fd, std.posix.F.GETFL, 0) catch 0;
                _ = std.posix.fcntl(self.fd, std.posix.F.SETFL, flags | std.posix.O.NONBLOCK) catch {};

                // 提交连接操作
                const waker = ctx.createWaker();
                self.operation_id = self.driver.submitConnect(self.fd, self.addr, waker) catch {
                    std.posix.close(self.fd);
                    self.state = .failed;
                    return .{ .ready = error.ConnectSubmitFailed };
                };

                self.state = .connecting;
                return .pending;
            },
            .connecting => {
                return .pending;
            },
            .completed => {
                const stream = TcpStream{
                    .fd = self.fd,
                    .driver = self.driver,
                    .remote_addr = self.addr,
                };
                return .{ .ready = stream };
            },
            .failed => {
                return .{ .ready = error.ConnectFailed };
            },
        }
    }
};

pub const ReadFuture = struct {
    fd: std.posix.fd_t,
    buffer: []u8,
    driver: *LibxevDriver,
    state: State = .initial,
    operation_id: ?u64 = null,
    bytes_read: usize = 0,

    const State = enum { initial, reading, completed, failed };

    pub fn init(fd: std.posix.fd_t, buffer: []u8, driver: *LibxevDriver) ReadFuture {
        return ReadFuture{
            .fd = fd,
            .buffer = buffer,
            .driver = driver,
        };
    }

    pub fn poll(self: *ReadFuture, ctx: *Context) Poll(usize) {
        switch (self.state) {
            .initial => {
                const waker = ctx.createWaker();
                self.operation_id = self.driver.submitRead(self.fd, self.buffer, waker) catch {
                    self.state = .failed;
                    return .{ .ready = error.ReadSubmitFailed };
                };

                self.state = .reading;
                return .pending;
            },
            .reading => {
                return .pending;
            },
            .completed => {
                return .{ .ready = self.bytes_read };
            },
            .failed => {
                return .{ .ready = error.ReadFailed };
            },
        }
    }
};

pub const WriteFuture = struct {
    fd: std.posix.fd_t,
    data: []const u8,
    driver: *LibxevDriver,
    state: State = .initial,
    operation_id: ?u64 = null,
    bytes_written: usize = 0,

    const State = enum { initial, writing, completed, failed };

    pub fn init(fd: std.posix.fd_t, data: []const u8, driver: *LibxevDriver) WriteFuture {
        return WriteFuture{
            .fd = fd,
            .data = data,
            .driver = driver,
        };
    }

    pub fn poll(self: *WriteFuture, ctx: *Context) Poll(usize) {
        switch (self.state) {
            .initial => {
                const waker = ctx.createWaker();
                self.operation_id = self.driver.submitWrite(self.fd, self.data, waker) catch {
                    self.state = .failed;
                    return .{ .ready = error.WriteSubmitFailed };
                };

                self.state = .writing;
                return .pending;
            },
            .writing => {
                return .pending;
            },
            .completed => {
                return .{ .ready = self.bytes_written };
            },
            .failed => {
                return .{ .ready = error.WriteFailed };
            },
        }
    }
};
```

#### 2.3 基于libxev的文件I/O

```zig
// src/fs/file.zig - 完全基于libxev的文件I/O
pub const File = struct {
    fd: std.posix.fd_t,
    driver: *LibxevDriver,

    pub fn open(path: []const u8, flags: std.fs.File.OpenFlags, driver: *LibxevDriver) !File {
        const fd = try std.posix.open(path, flags, 0o644);
        return File{
            .fd = fd,
            .driver = driver,
        };
    }

    pub fn read(self: *File, buffer: []u8) ReadFuture {
        return ReadFuture.init(self.fd, buffer, self.driver);
    }

    pub fn write(self: *File, data: []const u8) WriteFuture {
        return WriteFuture.init(self.fd, data, self.driver);
    }

    pub fn close(self: *File) void {
        std.posix.close(self.fd);
    }
};
```

### 阶段3: 真实的任务系统和共享状态

#### 3.1 共享状态实现

```zig
// src/runtime/shared.zig - 工作线程间的共享状态
pub const Shared = struct {
    workers: []Worker,
    inject_queue: InjectQueue,
    idle_workers: IdleWorkers,
    owned_tasks: OwnedTasks,
    io_driver: *LibxevDriver,
    blocking_pool: *BlockingPool,
    allocator: std.mem.Allocator,
    shutdown_signal: std.atomic.Value(bool),

    pub fn init(
        worker_count: usize,
        io_driver: *LibxevDriver,
        blocking_pool: *BlockingPool,
        allocator: std.mem.Allocator
    ) !Shared {
        return Shared{
            .workers = undefined, // 稍后设置
            .inject_queue = try InjectQueue.init(allocator),
            .idle_workers = try IdleWorkers.init(worker_count, allocator),
            .owned_tasks = try OwnedTasks.init(allocator),
            .io_driver = io_driver,
            .blocking_pool = blocking_pool,
            .allocator = allocator,
            .shutdown_signal = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Shared) void {
        self.inject_queue.deinit();
        self.idle_workers.deinit();
        self.owned_tasks.deinit();
    }

    pub fn notify_work_available(self: *Shared) void {
        // 唤醒一个空闲的工作线程
        if (self.idle_workers.wake_one()) {
            // 成功唤醒了一个工作线程
        }
    }

    pub fn is_shutdown(self: *const Shared) bool {
        return self.shutdown_signal.load(.acquire);
    }
};

/// 全局注入队列 - 用于跨线程任务提交
pub const InjectQueue = struct {
    queue: std.atomic.Queue(*Task),
    is_closed: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) !InjectQueue {
        return InjectQueue{
            .queue = std.atomic.Queue(*Task).init(),
            .is_closed = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *InjectQueue) void {
        // 清理剩余任务
        while (self.queue.get()) |node| {
            const task = node.data;
            task.cancel();
        }
    }

    pub fn push(self: *InjectQueue, task: *Task) bool {
        if (self.is_closed.load(.acquire)) {
            return false;
        }

        const node = task.queue_node();
        self.queue.put(node);
        return true;
    }

    pub fn pop(self: *InjectQueue) ?*Task {
        if (self.queue.get()) |node| {
            return node.data;
        }
        return null;
    }

    pub fn close(self: *InjectQueue) void {
        self.is_closed.store(true, .release);
    }
};

/// 空闲工作线程管理
pub const IdleWorkers = struct {
    parkers: []Parker,
    idle_mask: std.atomic.Value(u64),
    allocator: std.mem.Allocator,

    pub fn init(worker_count: usize, allocator: std.mem.Allocator) !IdleWorkers {
        const parkers = try allocator.alloc(Parker, worker_count);
        for (parkers) |*parker| {
            parker.* = try Parker.new();
        }

        return IdleWorkers{
            .parkers = parkers,
            .idle_mask = std.atomic.Value(u64).init(0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *IdleWorkers) void {
        for (self.parkers) |*parker| {
            parker.deinit();
        }
        self.allocator.free(self.parkers);
    }

    pub fn park_worker(self: *IdleWorkers, worker_index: usize) void {
        // 标记工作线程为空闲
        const mask = @as(u64, 1) << @intCast(worker_index);
        _ = self.idle_mask.fetchOr(mask, .acq_rel);

        // 停泊工作线程
        self.parkers[worker_index].park();

        // 取消空闲标记
        _ = self.idle_mask.fetchAnd(~mask, .acq_rel);
    }

    pub fn wake_one(self: *IdleWorkers) bool {
        const mask = self.idle_mask.load(.acquire);
        if (mask == 0) {
            return false; // 没有空闲工作线程
        }

        // 找到第一个空闲的工作线程
        const worker_index = @ctz(mask);
        self.parkers[worker_index].unpark();
        return true;
    }
};

/// 任务所有权管理
pub const OwnedTasks = struct {
    tasks: std.HashMap(TaskId, *Task),
    next_id: std.atomic.Value(u64),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) !OwnedTasks {
        return OwnedTasks{
            .tasks = std.HashMap(TaskId, *Task).init(allocator),
            .next_id = std.atomic.Value(u64).init(1),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *OwnedTasks) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 取消所有剩余任务
        var iterator = self.tasks.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.cancel();
        }

        self.tasks.deinit();
    }

    pub fn insert(self: *OwnedTasks, task: *Task) TaskId {
        const id = TaskId{ .id = self.next_id.fetchAdd(1, .monotonic) };
        task.id = id;

        self.mutex.lock();
        defer self.mutex.unlock();

        self.tasks.put(id, task) catch unreachable;
        return id;
    }

    pub fn remove(self: *OwnedTasks, id: TaskId) ?*Task {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.tasks.fetchRemove(id);
    }
};
```

#### 3.2 重构Task系统

```zig
// src/future/task.zig - 真实的任务实现
pub const TaskId = struct {
    id: u64,

    pub fn eql(self: TaskId, other: TaskId) bool {
        return self.id == other.id;
    }
};

pub const Task = struct {
    id: TaskId = TaskId{ .id = 0 },
    header: TaskHeader,
    future: *anyopaque,  // 类型擦除的Future
    vtable: *const TaskVTable,
    queue_node_storage: std.atomic.Queue(*Task).Node,

    pub fn new(comptime future: anytype, allocator: std.mem.Allocator) !*Task {
        const FutureType = @TypeOf(future);
        const TaskImpl = TaskImplFor(FutureType);

        const task_impl = try allocator.create(TaskImpl);
        task_impl.* = TaskImpl{
            .task = Task{
                .header = TaskHeader{},
                .future = &task_impl.future_storage,
                .vtable = &TaskImpl.vtable,
                .queue_node_storage = std.atomic.Queue(*Task).Node{ .data = undefined },
            },
            .future_storage = future,
        };

        task_impl.task.queue_node_storage.data = &task_impl.task;
        return &task_impl.task;
    }

    pub fn poll(self: *Task, ctx: *Context) Poll(void) {
        return self.vtable.poll(self.future, ctx);
    }

    pub fn wake(self: *Task) void {
        self.vtable.wake(self.future);
    }

    pub fn cancel(self: *Task) void {
        self.vtable.cancel(self.future);
    }

    pub fn drop(self: *Task, allocator: std.mem.Allocator) void {
        self.vtable.drop(self.future, allocator);
    }

    pub fn queue_node(self: *Task) *std.atomic.Queue(*Task).Node {
        return &self.queue_node_storage;
    }

    pub fn run(self: *Task) void {
        // 创建上下文
        var waker = Waker.from_task(self);
        var context = Context{ .waker = waker };

        // 轮询任务
        switch (self.poll(&context)) {
            .ready => {
                // 任务完成，从owned_tasks中移除
                if (getCurrentWorker()) |worker| {
                    _ = worker.shared.owned_tasks.remove(self.id);
                }

                // 通知JoinHandle
                self.vtable.complete(self.future);
            },
            .pending => {
                // 任务未完成，等待下次调度
            },
        }
    }
};

pub const TaskHeader = struct {
    state: TaskState = .ready,

    const TaskState = enum {
        ready,
        running,
        completed,
        cancelled,
    };
};

pub const TaskVTable = struct {
    poll: *const fn(*anyopaque, *Context) Poll(void),
    wake: *const fn(*anyopaque) void,
    cancel: *const fn(*anyopaque) void,
    complete: *const fn(*anyopaque) void,
    drop: *const fn(*anyopaque, std.mem.Allocator) void,
};

fn TaskImplFor(comptime FutureType: type) type {
    return struct {
        const Self = @This();

        task: Task,
        future_storage: FutureType,
        join_handle_waker: ?Waker = null,
        result: ?FutureType.Output = null,

        const vtable = TaskVTable{
            .poll = poll,
            .wake = wake,
            .cancel = cancel,
            .complete = complete,
            .drop = drop,
        };

        fn poll(future_ptr: *anyopaque, ctx: *Context) Poll(void) {
            const self: *Self = @ptrCast(@alignCast(future_ptr));

            switch (self.future_storage.poll(ctx)) {
                .ready => |result| {
                    self.result = result;
                    return .ready;
                },
                .pending => return .pending,
            }
        }

        fn wake(future_ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(future_ptr));

            // 将任务重新调度
            if (getCurrentWorker()) |worker| {
                if (worker.core.lifo_enabled and worker.core.lifo_slot == null) {
                    worker.core.lifo_slot = &self.task;
                } else {
                    _ = worker.core.local_queue.push(&self.task);
                }
            } else {
                // 不在工作线程上，放入全局队列
                // 这需要访问全局运行时实例
            }
        }

        fn cancel(future_ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(future_ptr));
            self.task.header.state = .cancelled;
        }

        fn complete(future_ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(future_ptr));
            self.task.header.state = .completed;

            // 唤醒JoinHandle
            if (self.join_handle_waker) |waker| {
                waker.wake();
            }
        }

        fn drop(future_ptr: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *Self = @ptrCast(@alignCast(future_ptr));
            allocator.destroy(self);
        }
    };
}
```

#### 3.3 实现JoinHandle

```zig
// src/future/join_handle.zig - 任务句柄
pub fn JoinHandle(comptime T: type) type {
    return struct {
        const Self = @This();

        task_id: TaskId,
        shared: *Shared,
        state: State = .running,
        result: ?T = null,

        const State = enum { running, completed, cancelled };

        pub fn new(task_id: TaskId, shared: *Shared) Self {
            return Self{
                .task_id = task_id,
                .shared = shared,
            };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(T) {
            switch (self.state) {
                .running => {
                    // 检查任务是否完成
                    if (self.shared.owned_tasks.get(self.task_id)) |task| {
                        if (task.header.state == .completed) {
                            // 获取结果
                            const task_impl: *TaskImplFor(anytype) = @ptrCast(@alignCast(task.future));
                            if (task_impl.result) |result| {
                                self.result = result;
                                self.state = .completed;
                                return .{ .ready = result };
                            }
                        }
                    } else {
                        // 任务已被移除，可能已完成
                        if (self.result) |result| {
                            return .{ .ready = result };
                        }
                    }

                    return .pending;
                },
                .completed => {
                    if (self.result) |result| {
                        return .{ .ready = result };
                    } else {
                        return .{ .ready = error.TaskCompletedWithoutResult };
                    }
                },
                .cancelled => {
                    return .{ .ready = error.TaskCancelled };
                },
            }
        }

        pub fn abort(self: *Self) void {
            if (self.shared.owned_tasks.get(self.task_id)) |task| {
                task.cancel();
                self.state = .cancelled;
            }
        }

        pub fn is_finished(self: *const Self) bool {
            return self.state != .running;
        }
    };
}
```

### 阶段4: 工作窃取队列

#### 4.1 改进现有的WorkStealingQueue

基于`src/scheduler/work_stealing_queue.zig`：

```zig
// src/scheduler/work_stealing_queue.zig - 改进版本
pub fn WorkStealingQueue(comptime T: type) type {
    return struct {
        buffer: []AtomicPtr(T),
        head: AtomicUsize,
        tail: AtomicUsize,
        
        // 本地操作（无锁）
        pub fn pushBack(self: *Self, item: T) bool;
        pub fn popBack(self: *Self) ?T;
        
        // 远程操作（可能有锁）
        pub fn popFront(self: *Self) ?T;  // 用于窃取
        pub fn steal(self: *Self) ?T;
    };
}
```

#### 4.2 实现全局注入队列

```zig
// src/scheduler/inject_queue.zig
pub const InjectQueue = struct {
    queue: MpscQueue(Task),
    is_closed: AtomicBool,
    
    pub fn push(self: *InjectQueue, task: Task) bool;
    pub fn pop(self: *InjectQueue) ?Task;
    pub fn close(self: *InjectQueue) void;
};
```

### 阶段5: 真实的异步原语

#### 5.1 重构async_fn和await_fn

```zig
// src/future/async_fn.zig - 真实版本
pub fn async_fn(comptime func: anytype) type {
    return struct {
        state: State = .initial,
        waker: ?Waker = null,
        
        pub fn poll(self: *Self, ctx: *Context) Poll(ReturnType) {
            switch (self.state) {
                .initial => {
                    // 创建真实的任务并调度到运行时
                    const task = Task.new(func);
                    ctx.runtime.schedule(task);
                    self.state = .running;
                    return .pending;
                },
                .running => return .pending,
                .completed => return .{ .ready = self.result },
            }
        }
    };
}
```

#### 5.2 真实的await_fn

```zig
// src/future/await_fn.zig
pub fn await_fn(future: anytype) @TypeOf(future).Output {
    // 只能在async context中调用
    const ctx = Context.current() orelse @panic("await_fn outside async context");
    
    var fut = future;
    while (true) {
        switch (fut.poll(ctx)) {
            .ready => |result| return result,
            .pending => {
                // 真正的yield：将当前任务标记为pending并让出执行
                ctx.yield();
            },
        }
    }
}
```

## 📊 性能目标

### 基于真实测试的目标

根据真实压测结果，设定合理目标：

| 指标 | 当前性能 | 目标性能 | 改进倍数 |
|------|----------|----------|----------|
| 文件I/O | 16.6K ops/sec | 50K ops/sec | 3x |
| 网络I/O | 159 ops/sec | 10K ops/sec | 63x |
| CPU密集型 | 74M ops/sec | 100M ops/sec | 1.35x |
| 混合负载 | 465 ops/sec | 5K ops/sec | 11x |

### 调度器性能目标

- **任务调度延迟**: < 10μs
- **工作窃取效率**: > 90%
- **负载均衡**: 工作线程利用率差异 < 5%
- **内存效率**: 每个任务开销 < 64 bytes

## 🛠️ 实施步骤

### 第1周: 基础架构重构
1. **Day 1-2**: 重构SimpleRuntime为RealRuntime
   - 创建Builder模式的运行时构建器
   - 实现基础的Handle和Context结构
   - 集成libxev作为唯一I/O后端

2. **Day 3-4**: 实现多线程调度器框架
   - 创建MultiThreadScheduler基础结构
   - 实现Shared共享状态
   - 创建Worker基础框架

3. **Day 5-7**: 实现工作线程和核心调度逻辑
   - 完成Worker的工作循环
   - 实现Core的本地队列管理
   - 实现基础的任务调度

### 第2周: libxev I/O集成
1. **Day 1-2**: 完全集成libxev
   - 实现LibxevDriver作为唯一I/O驱动
   - 移除所有其他I/O后端代码
   - 实现基础的异步I/O操作

2. **Day 3-4**: 实现网络抽象层
   - 基于libxev实现TcpStream
   - 实现TcpListener
   - 实现UDP支持

3. **Day 5-7**: 实现文件I/O和定时器
   - 基于libxev实现异步文件I/O
   - 实现定时器和延迟功能
   - 实现信号处理

### 第3周: 工作窃取和任务系统
1. **Day 1-2**: 完善工作窃取队列
   - 优化WorkStealingQueue实现
   - 实现LIFO优化槽
   - 实现动态负载均衡

2. **Day 3-4**: 实现全局任务管理
   - 完成InjectQueue实现
   - 实现OwnedTasks任务所有权
   - 实现IdleWorkers空闲管理

3. **Day 5-7**: 实现真实的Task系统
   - 完成类型擦除的Task实现
   - 实现TaskVTable虚函数表
   - 实现任务生命周期管理

### 第4周: 异步原语和上下文
1. **Day 1-2**: 重构Future系统
   - 实现真正的async_fn
   - 实现真正的await_fn
   - 实现Context和Waker机制

2. **Day 3-4**: 实现JoinHandle和阻塞池
   - 完成JoinHandle实现
   - 实现BlockingPool阻塞任务池
   - 实现spawn_blocking功能

3. **Day 5-7**: 实现高级异步原语
   - 实现select!宏
   - 实现timeout功能
   - 实现异步互斥锁和信号量

### 第5周: 优化、测试和验证
1. **Day 1-2**: 性能优化
   - 内存分配优化
   - 缓存友好的数据结构
   - 减少原子操作开销

2. **Day 3-4**: 全面测试
   - 单元测试覆盖
   - 集成测试
   - 压力测试和稳定性测试

3. **Day 5-7**: 性能验证和文档
   - 与目标性能对比
   - 性能回归测试
   - 完善文档和示例

## 🔧 技术细节

### libxev集成策略
- **统一后端**: 完全依赖libxev，移除所有自定义I/O后端
- **跨平台支持**: libxev自动选择最佳后端
  - Linux: io_uring (首选) + epoll (回退)
  - macOS: kqueue
  - Windows: IOCP
  - FreeBSD/NetBSD: kqueue
  - 其他: poll/select
- **零配置**: 用户无需关心底层I/O机制

### 内存管理策略
- **任务对象池**: 预分配Task对象，减少运行时分配
- **LIFO优化**: 利用CPU缓存局部性，优先运行最近提交的任务
- **零拷贝I/O**: 直接使用用户提供的缓冲区，避免内存拷贝
- **分代垃圾回收**: 对长期存在的对象使用不同的分配策略

### 并发安全设计
- **无锁工作窃取**: 基于Chase-Lev算法的无锁双端队列
- **原子操作优化**:
  - 使用relaxed ordering减少同步开销
  - 关键路径使用acquire-release语义
  - 避免不必要的内存屏障
- **线程本地存储**: 减少跨线程数据访问
- **批量操作**: 减少原子操作频率

### Tokio兼容性设计
- **API兼容**: 提供与Tokio类似的API接口
- **行为兼容**: 保持相同的调度语义和性能特征
- **生态兼容**: 支持类似的中间件和扩展模式

### 编译时优化
- **零成本抽象**: 利用Zig的comptime特性实现零开销抽象
- **内联优化**: 关键路径函数强制内联
- **死代码消除**: 编译时移除未使用的功能
- **特化优化**: 为不同的Future类型生成特化代码

## 📈 验证方法

### 功能验证
1. **单元测试**: 覆盖率 > 95%
   - 每个组件的独立测试
   - 边界条件和错误处理测试
   - 并发安全性测试

2. **集成测试**: 端到端场景验证
   - 真实应用场景模拟
   - 多种I/O模式组合测试
   - 跨平台兼容性测试

3. **压力测试**: 极限条件验证
   - 高并发任务调度测试
   - 内存压力测试
   - 长时间运行稳定性测试

### 性能验证
1. **基准测试**: 与真实数据对比
   - 使用真实的I/O操作（文件、网络、数据库）
   - 测试不同负载模式（CPU密集型、I/O密集型、混合型）
   - 记录详细的性能指标

2. **对比测试**: 与Tokio性能对比
   - 相同测试场景下的性能对比
   - 内存使用效率对比
   - 延迟和吞吐量对比

3. **回归测试**: 性能回归检测
   - 自动化性能测试流水线
   - 性能指标趋势监控
   - 性能回归自动告警

### 正确性验证
1. **并发正确性**:
   - 使用ThreadSanitizer检测竞态条件
   - 使用AddressSanitizer检测内存错误
   - 使用Valgrind检测内存泄漏

2. **形式化验证**:
   - 关键算法的数学证明
   - 不变量检查
   - 状态机验证

3. **模糊测试**:
   - 随机输入测试
   - 异常情况模拟
   - 边界条件探索

### 实际应用验证
1. **示例应用**: 构建真实的应用程序
   - HTTP服务器
   - 数据库连接池
   - 消息队列客户端

2. **生产环境测试**:
   - 在真实负载下运行
   - 监控关键指标
   - 收集用户反馈

## 🎯 成功标准

### 功能完整性 (权重: 25%)
- ✅ 支持所有计划的异步原语 (async_fn, await_fn, spawn, join)
- ✅ 完整的I/O抽象 (TCP, UDP, 文件, 定时器)
- ✅ 高级并发原语 (select, timeout, 互斥锁, 信号量)
- ✅ 错误处理和资源管理

### 性能达标 (权重: 35%)
- ✅ **文件I/O**: 从16.6K提升到50K ops/sec (3x改进)
- ✅ **网络I/O**: 从159提升到10K ops/sec (63x改进)
- ✅ **CPU密集型**: 从74M提升到100M ops/sec (1.35x改进)
- ✅ **混合负载**: 从465提升到5K ops/sec (11x改进)
- ✅ **调度延迟**: < 10μs (P99)
- ✅ **内存效率**: 每任务开销 < 64 bytes

### 稳定性 (权重: 20%)
- ✅ 24小时压力测试无崩溃
- ✅ 内存泄漏检测通过
- ✅ 竞态条件检测通过
- ✅ 在高负载下保持稳定性能

### 兼容性 (权重: 10%)
- ✅ Linux (x86_64, aarch64)
- ✅ macOS (x86_64, Apple Silicon)
- ✅ Windows (x86_64)
- ✅ 与libxev支持的所有平台兼容

### 易用性 (权重: 10%)
- ✅ API设计简洁直观
- ✅ 完整的文档和示例
- ✅ 良好的错误信息
- ✅ 零配置开箱即用

## 🚀 预期成果

### 技术成果
1. **真正的异步运行时**: 基于libxev的高性能异步运行时
2. **Tokio级别性能**: 在关键指标上达到或超过Tokio性能
3. **Zig生态贡献**: 为Zig生态提供高质量的异步运行时库
4. **跨平台支持**: 统一的API支持所有主流平台

### 性能成果
1. **显著性能提升**: 在所有测试场景中实现目标性能
2. **内存效率**: 比现有实现更低的内存开销
3. **延迟优化**: 更低的任务调度延迟
4. **吞吐量提升**: 更高的并发处理能力

### 生态成果
1. **开源贡献**: 高质量的开源异步运行时
2. **社区建设**: 吸引更多开发者参与Zig异步生态
3. **最佳实践**: 为Zig异步编程提供参考实现
4. **技术影响**: 推动Zig在服务器端应用的采用

这个完整的改进计划将把Zokio从当前的"伪异步"实现转变为真正的高性能异步运行时，完全基于libxev实现跨平台I/O，与Tokio在架构和性能上保持一致，同时充分利用Zig的编译时特性实现更好的性能和更低的资源消耗。
