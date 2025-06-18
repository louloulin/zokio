//! 同步原语模块
//!
//! 提供异步环境下的同步原语，如互斥锁、信号量、通道等。

const std = @import("std");
const future = @import("../future/future.zig");
const utils = @import("../utils/utils.zig");

/// 异步互斥锁
pub const AsyncMutex = struct {
    locked: utils.Atomic.Value(bool),
    waiters: utils.IntrusiveList(Waiter, "node"),

    const Waiter = struct {
        waker: future.Waker,
        node: utils.IntrusiveNode(@This()),
    };

    pub fn init() AsyncMutex {
        return AsyncMutex{
            .locked = utils.Atomic.Value(bool).init(false),
            .waiters = utils.IntrusiveList(Waiter, "node").init(),
        };
    }

    pub fn lock(self: *AsyncMutex) LockFuture {
        return LockFuture{ .mutex = self };
    }

    pub fn unlock(self: *AsyncMutex) void {
        self.locked.store(false, .release);

        // 唤醒一个等待者
        if (self.waiters.popFront()) |waiter| {
            waiter.waker.wake();
        }
    }

    const LockFuture = struct {
        mutex: *AsyncMutex,

        pub fn poll(self: *@This(), ctx: *future.Context) future.Poll(void) {
            if (self.mutex.locked.cmpxchgWeak(false, true, .acq_rel, .acquire) == null) {
                return .{ .ready = {} };
            }

            // 添加到等待队列
            var waiter = Waiter{
                .waker = ctx.waker.clone(),
                .node = .{},
            };
            self.mutex.waiters.pushBack(&waiter);

            return .pending;
        }
    };
};

/// 异步信号量
pub const AsyncSemaphore = struct {
    permits: utils.Atomic.Value(u32),
    waiters: utils.IntrusiveList(SemWaiter, "node"),
    mutex: std.Thread.Mutex,

    const SemWaiter = struct {
        waker: future.Waker,
        permits_needed: u32,
        node: utils.IntrusiveNode(@This()),
    };

    pub fn init(initial_permits: u32) AsyncSemaphore {
        return AsyncSemaphore{
            .permits = utils.Atomic.Value(u32).init(initial_permits),
            .waiters = utils.IntrusiveList(SemWaiter, "node").init(),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn acquire(self: *AsyncSemaphore, permits: u32) AcquireFuture {
        return AcquireFuture{
            .semaphore = self,
            .permits_needed = permits,
        };
    }

    pub fn release(self: *AsyncSemaphore, permits: u32) void {
        _ = self.permits.fetchAdd(permits, .acq_rel);

        self.mutex.lock();
        defer self.mutex.unlock();

        // 尝试唤醒等待者
        var current = self.waiters.first;
        while (current) |waiter| {
            const next = waiter.node.next;

            if (self.permits.load(.acquire) >= waiter.permits_needed) {
                if (self.permits.fetchSub(waiter.permits_needed, .acq_rel) >= waiter.permits_needed) {
                    self.waiters.remove(waiter);
                    waiter.waker.wake();
                } else {
                    // 恢复permits
                    _ = self.permits.fetchAdd(waiter.permits_needed, .acq_rel);
                }
            }

            current = next;
        }
    }

    const AcquireFuture = struct {
        semaphore: *AsyncSemaphore,
        permits_needed: u32,

        pub fn poll(self: *@This(), ctx: *future.Context) future.Poll(void) {
            if (self.semaphore.permits.fetchSub(self.permits_needed, .acq_rel) >= self.permits_needed) {
                return .{ .ready = {} };
            }

            // 恢复permits
            _ = self.semaphore.permits.fetchAdd(self.permits_needed, .acq_rel);

            // 添加到等待队列
            self.semaphore.mutex.lock();
            defer self.semaphore.mutex.unlock();

            var waiter = SemWaiter{
                .waker = ctx.waker.clone(),
                .permits_needed = self.permits_needed,
                .node = .{},
            };
            self.semaphore.waiters.pushBack(&waiter);

            return .pending;
        }
    };
};

/// 异步通道 - 单生产者单消费者
pub fn AsyncChannel(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]T,
        head: utils.Atomic.Value(usize),
        tail: utils.Atomic.Value(usize),
        senders_waiting: utils.IntrusiveList(ChannelWaiter, "node"),
        receivers_waiting: utils.IntrusiveList(ChannelWaiter, "node"),
        mutex: std.Thread.Mutex,
        closed: utils.Atomic.Value(bool),

        const ChannelWaiter = struct {
            waker: future.Waker,
            node: utils.IntrusiveNode(@This()),
        };

        pub fn init() Self {
            return Self{
                .buffer = undefined,
                .head = utils.Atomic.Value(usize).init(0),
                .tail = utils.Atomic.Value(usize).init(0),
                .senders_waiting = utils.IntrusiveList(ChannelWaiter, "node").init(),
                .receivers_waiting = utils.IntrusiveList(ChannelWaiter, "node").init(),
                .mutex = std.Thread.Mutex{},
                .closed = utils.Atomic.Value(bool).init(false),
            };
        }

        pub fn send(self: *Self, value: T) SendFuture {
            return SendFuture{
                .channel = self,
                .value = value,
            };
        }

        pub fn receive(self: *Self) ReceiveFuture {
            return ReceiveFuture{ .channel = self };
        }

        pub fn close(self: *Self) void {
            self.closed.store(true, .release);

            self.mutex.lock();
            defer self.mutex.unlock();

            // 唤醒所有等待者
            while (self.senders_waiting.popFront()) |waiter| {
                waiter.waker.wake();
            }
            while (self.receivers_waiting.popFront()) |waiter| {
                waiter.waker.wake();
            }
        }

        fn isFull(self: *const Self) bool {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            return (tail + 1) % capacity == head;
        }

        fn isEmpty(self: *const Self) bool {
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            return head == tail;
        }

        const SendFuture = struct {
            channel: *Self,
            value: T,

            pub fn poll(self: *@This(), ctx: *future.Context) future.Poll(void) {
                if (self.channel.closed.load(.acquire)) {
                    return .{ .ready = {} }; // 通道已关闭
                }

                if (!self.channel.isFull()) {
                    const tail = self.channel.tail.load(.acquire);
                    self.channel.buffer[tail] = self.value;
                    self.channel.tail.store((tail + 1) % capacity, .release);

                    // 唤醒等待的接收者
                    self.channel.mutex.lock();
                    defer self.channel.mutex.unlock();

                    if (self.channel.receivers_waiting.popFront()) |waiter| {
                        waiter.waker.wake();
                    }

                    return .{ .ready = {} };
                }

                // 添加到发送等待队列
                self.channel.mutex.lock();
                defer self.channel.mutex.unlock();

                var waiter = ChannelWaiter{
                    .waker = ctx.waker.clone(),
                    .node = .{},
                };
                self.channel.senders_waiting.pushBack(&waiter);

                return .pending;
            }
        };

        const ReceiveFuture = struct {
            channel: *Self,

            pub fn poll(self: *@This(), ctx: *future.Context) future.Poll(?T) {
                if (!self.channel.isEmpty()) {
                    const head = self.channel.head.load(.acquire);
                    const value = self.channel.buffer[head];
                    self.channel.head.store((head + 1) % capacity, .release);

                    // 唤醒等待的发送者
                    self.channel.mutex.lock();
                    defer self.channel.mutex.unlock();

                    if (self.channel.senders_waiting.popFront()) |waiter| {
                        waiter.waker.wake();
                    }

                    return .{ .ready = value };
                }

                if (self.channel.closed.load(.acquire)) {
                    return .{ .ready = null }; // 通道已关闭且为空
                }

                // 添加到接收等待队列
                self.channel.mutex.lock();
                defer self.channel.mutex.unlock();

                var waiter = ChannelWaiter{
                    .waker = ctx.waker.clone(),
                    .node = .{},
                };
                self.channel.receivers_waiting.pushBack(&waiter);

                return .pending;
            }
        };
    };
}

// 测试
test "异步互斥锁基础功能" {
    const testing = std.testing;

    var mutex = AsyncMutex.init();

    // 测试基本锁定
    var lock_future = mutex.lock();
    const waker = future.Waker.noop();
    var ctx = future.Context.init(waker);

    const result = lock_future.poll(&ctx);
    try testing.expect(result.isReady());

    // 测试解锁
    mutex.unlock();
    try testing.expect(!mutex.locked.load(.acquire));
}
