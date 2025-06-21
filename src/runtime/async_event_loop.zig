//! Zokio 2.0 真正的异步事件循环实现
//!
//! 这是Zokio 2.0的核心组件，实现了真正的非阻塞异步事件循环，
//! 替代了原有的"伪异步"实现（std.time.sleep阻塞）。

const std = @import("std");
const libxev = @import("libxev");
const utils = @import("../utils/utils.zig");

/// 任务ID类型
pub const TaskId = struct {
    id: u64,

    var next_id = utils.Atomic.Value(u64).init(1);

    pub fn generate() TaskId {
        return TaskId{
            .id = next_id.fetchAdd(1, .monotonic),
        };
    }
};

/// 🚀 真正的异步事件循环
///
/// 这是Zokio 2.0的核心，实现了基于libxev的真正异步事件循环，
/// 完全替代了原有的阻塞sleep实现。
pub const AsyncEventLoop = struct {
    const Self = @This();

    /// libxev事件循环
    libxev_loop: libxev.Loop,

    /// Waker注册表
    waker_registry: WakerRegistry,

    /// 定时器轮询
    timer_wheel: TimerWheel,

    /// 任务调度器引用
    scheduler: ?*TaskScheduler = null,

    /// 是否正在运行
    running: utils.Atomic.Value(bool),

    /// 活跃任务计数
    active_tasks: utils.Atomic.Value(u32),

    /// 分配器
    allocator: std.mem.Allocator,

    /// 初始化异步事件循环
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .libxev_loop = try libxev.Loop.init(.{}),
            .waker_registry = WakerRegistry.init(allocator),
            .timer_wheel = TimerWheel.init(allocator),
            .running = utils.Atomic.Value(bool).init(false),
            .active_tasks = utils.Atomic.Value(u32).init(0),
            .allocator = allocator,
        };
    }

    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.running.store(false, .release);
        self.libxev_loop.deinit();
        self.waker_registry.deinit();
        self.timer_wheel.deinit();
    }

    /// 设置任务调度器
    pub fn setScheduler(self: *Self, scheduler: *TaskScheduler) void {
        self.scheduler = scheduler;
    }

    /// 运行事件循环直到所有任务完成
    pub fn run(self: *Self) !void {
        self.running.store(true, .release);

        while (self.hasActiveTasks() and self.running.load(.acquire)) {
            // 1. 处理就绪的I/O事件（非阻塞）
            try self.libxev_loop.run(.no_wait);

            // 2. 处理到期的定时器
            self.timer_wheel.processExpired();

            // 3. 唤醒就绪的任务
            self.waker_registry.wakeReady();

            // 4. 让出CPU给调度器
            if (self.scheduler) |scheduler| {
                scheduler.yield();
            }

            // 5. 短暂让出CPU，避免忙等待
            std.Thread.yield() catch {};
        }
    }

    /// 运行一次事件循环迭代
    pub fn runOnce(self: *Self) !void {
        // 处理I/O事件
        try self.libxev_loop.run(.no_wait);

        // 处理定时器
        self.timer_wheel.processExpired();

        // 唤醒就绪任务
        self.waker_registry.wakeReady();
    }

    /// 检查是否有活跃任务
    pub fn hasActiveTasks(self: *const Self) bool {
        return self.active_tasks.load(.acquire) > 0;
    }

    /// 增加活跃任务计数
    pub fn addActiveTask(self: *Self) void {
        _ = self.active_tasks.fetchAdd(1, .monotonic);
    }

    /// 减少活跃任务计数
    pub fn removeActiveTask(self: *Self) void {
        _ = self.active_tasks.fetchSub(1, .monotonic);
    }

    /// 注册读取事件
    pub fn registerRead(self: *Self, fd: std.posix.fd_t, waker: Waker) !void {
        try self.waker_registry.registerIo(fd, .read, waker);

        // 在libxev中注册读取事件
        var completion = libxev.Completion{};
        self.libxev_loop.read(&completion, fd, .{ .slice = &[_]u8{} }, void, null, readCallback);
    }

    /// 注册写入事件
    pub fn registerWrite(self: *Self, fd: std.posix.fd_t, waker: Waker) !void {
        try self.waker_registry.registerIo(fd, .write, waker);

        // 在libxev中注册写入事件
        var completion = libxev.Completion{};
        self.libxev_loop.write(&completion, fd, .{ .slice = &[_]u8{} }, void, null, writeCallback);
    }

    /// 注册定时器
    pub fn registerTimer(self: *Self, duration_ms: u64, waker: Waker) !TimerHandle {
        return self.timer_wheel.registerTimer(duration_ms, waker);
    }

    /// 检查读取是否就绪
    pub fn isReadReady(self: *Self, fd: std.posix.fd_t) bool {
        return self.waker_registry.isIoReady(fd, .read);
    }

    /// 检查写入是否就绪
    pub fn isWriteReady(self: *Self, fd: std.posix.fd_t) bool {
        return self.waker_registry.isIoReady(fd, .write);
    }

    /// 停止事件循环
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);
    }

    /// 🚀 Zokio 3.0 新增：注册等待任务
    ///
    /// 将等待I/O或其他事件的任务注册到事件循环
    pub fn registerWaitingTask(self: *Self, waker: Waker) void {
        // 将waker添加到等待队列
        self.waker_registry.addWaitingWaker(waker);

        // 增加活跃任务计数
        self.addActiveTask();
    }

    /// libxev读取回调
    fn readCallback(
        userdata: ?*void,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.ReadError!usize,
    ) libxev.CallbackAction {
        _ = userdata;
        _ = loop;
        _ = result;

        // 从completion获取waker并唤醒任务
        if (completion.userdata != 0) {
            const waker = @as(*Waker, @ptrFromInt(completion.userdata));
            waker.wake();
        }

        return .disarm;
    }

    /// libxev写入回调
    fn writeCallback(
        userdata: ?*void,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.WriteError!usize,
    ) libxev.CallbackAction {
        _ = userdata;
        _ = loop;
        _ = result;

        // 从completion获取waker并唤醒任务
        if (completion.userdata != 0) {
            const waker = @as(*Waker, @ptrFromInt(completion.userdata));
            waker.wake();
        }

        return .disarm;
    }
};

/// I/O事件类型
pub const IoInterest = enum {
    read,
    write,
    both,
};

/// 定时器句柄
pub const TimerHandle = struct {
    id: u64,
};

/// Waker注册表
pub const WakerRegistry = struct {
    const Self = @This();

    /// I/O事件映射
    io_map: std.HashMap(std.posix.fd_t, IoEntry, std.hash_map.AutoContext(std.posix.fd_t), 80),

    /// 就绪队列
    ready_queue: std.fifo.LinearFifo(Waker, .Dynamic),

    /// 互斥锁
    mutex: std.Thread.Mutex,

    /// 分配器
    allocator: std.mem.Allocator,

    const IoEntry = struct {
        read_waker: ?Waker = null,
        write_waker: ?Waker = null,
        read_ready: bool = false,
        write_ready: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .io_map = std.HashMap(std.posix.fd_t, IoEntry, std.hash_map.AutoContext(std.posix.fd_t), 80).init(allocator),
            .ready_queue = std.fifo.LinearFifo(Waker, .Dynamic).init(allocator),
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.io_map.deinit();
        self.ready_queue.deinit();
    }

    /// 注册I/O事件
    pub fn registerIo(self: *Self, fd: std.posix.fd_t, interest: IoInterest, waker: Waker) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var entry = self.io_map.get(fd) orelse IoEntry{};

        switch (interest) {
            .read => entry.read_waker = waker,
            .write => entry.write_waker = waker,
            .both => {
                entry.read_waker = waker;
                entry.write_waker = waker;
            },
        }

        try self.io_map.put(fd, entry);
    }

    /// 检查I/O是否就绪
    pub fn isIoReady(self: *Self, fd: std.posix.fd_t, interest: IoInterest) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.io_map.get(fd)) |entry| {
            return switch (interest) {
                .read => entry.read_ready,
                .write => entry.write_ready,
                .both => entry.read_ready and entry.write_ready,
            };
        }
        return false;
    }

    /// 唤醒就绪的任务
    pub fn wakeReady(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.ready_queue.readItem()) |waker| {
            waker.wake();
        }
    }

    /// 🚀 Zokio 3.0 新增：添加等待的Waker
    ///
    /// 将等待事件的Waker添加到就绪队列，等待后续唤醒
    pub fn addWaitingWaker(self: *Self, waker: Waker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 将waker添加到就绪队列，等待事件触发时唤醒
        self.ready_queue.writeItem(waker) catch {
            // 如果队列满了，直接唤醒（避免死锁）
            waker.wake();
        };
    }
};

/// 定时器轮询
pub const TimerWheel = struct {
    const Self = @This();

    /// 定时器条目
    const TimerEntry = struct {
        id: u64,
        expire_time: u64,
        waker: Waker,
    };

    /// 定时器列表
    timers: std.ArrayList(TimerEntry),

    /// 下一个定时器ID
    next_timer_id: utils.Atomic.Value(u64),

    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .timers = std.ArrayList(TimerEntry).init(allocator),
            .next_timer_id = utils.Atomic.Value(u64).init(1),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.timers.deinit();
    }

    /// 注册定时器
    pub fn registerTimer(self: *Self, duration_ms: u64, waker: Waker) !TimerHandle {
        const timer_id = self.next_timer_id.fetchAdd(1, .monotonic);
        const expire_time = std.time.milliTimestamp() + @as(i64, @intCast(duration_ms));

        try self.timers.append(TimerEntry{
            .id = timer_id,
            .expire_time = @intCast(expire_time),
            .waker = waker,
        });

        return TimerHandle{ .id = timer_id };
    }

    /// 处理到期的定时器
    pub fn processExpired(self: *Self) void {
        const now = @as(u64, @intCast(std.time.milliTimestamp()));

        var i: usize = 0;
        while (i < self.timers.items.len) {
            if (self.timers.items[i].expire_time <= now) {
                const timer = self.timers.swapRemove(i);
                timer.waker.wake();
            } else {
                i += 1;
            }
        }
    }
};

/// 前向声明
pub const TaskScheduler = struct {
    pub fn yield(self: *@This()) void {
        _ = self;
        // 简化实现，实际应该让出给其他任务
        std.Thread.yield() catch {};
    }
};

/// 前向声明
pub const Waker = struct {
    task_id: TaskId,
    scheduler: ?*TaskScheduler = null,

    pub fn wake(self: *const @This()) void {
        // 简化实现，实际应该唤醒对应的任务
        _ = self;
    }
};
