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
