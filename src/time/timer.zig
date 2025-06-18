//! 定时器和时间管理模块
//!
//! 提供高精度定时器、延迟执行、超时控制等时间相关功能。

const std = @import("std");
const future = @import("../future/future.zig");
const utils = @import("../utils/utils.zig");

/// 时间点表示
pub const Instant = struct {
    nanos: u64,

    pub fn now() Instant {
        return Instant{
            .nanos = @intCast(std.time.nanoTimestamp()),
        };
    }

    pub fn add(self: Instant, duration: Duration) Instant {
        return Instant{
            .nanos = self.nanos + duration.nanos,
        };
    }

    pub fn sub(self: Instant, other: Instant) Duration {
        return Duration{
            .nanos = if (self.nanos >= other.nanos) self.nanos - other.nanos else 0,
        };
    }

    pub fn isAfter(self: Instant, other: Instant) bool {
        return self.nanos > other.nanos;
    }

    pub fn isBefore(self: Instant, other: Instant) bool {
        return self.nanos < other.nanos;
    }
};

/// 时间间隔表示
pub const Duration = struct {
    nanos: u64,

    pub fn fromNanos(nanos: u64) Duration {
        return Duration{ .nanos = nanos };
    }

    pub fn fromMicros(micros: u64) Duration {
        return Duration{ .nanos = micros * 1000 };
    }

    pub fn fromMillis(millis: u64) Duration {
        return Duration{ .nanos = millis * 1_000_000 };
    }

    pub fn fromSecs(secs: u64) Duration {
        return Duration{ .nanos = secs * 1_000_000_000 };
    }

    pub fn asNanos(self: Duration) u64 {
        return self.nanos;
    }

    pub fn asMicros(self: Duration) u64 {
        return self.nanos / 1000;
    }

    pub fn asMillis(self: Duration) u64 {
        return self.nanos / 1_000_000;
    }

    pub fn asSecs(self: Duration) u64 {
        return self.nanos / 1_000_000_000;
    }

    pub fn add(self: Duration, other: Duration) Duration {
        return Duration{ .nanos = self.nanos + other.nanos };
    }

    pub fn sub(self: Duration, other: Duration) Duration {
        return Duration{
            .nanos = if (self.nanos >= other.nanos) self.nanos - other.nanos else 0,
        };
    }

    pub fn mul(self: Duration, factor: u64) Duration {
        return Duration{ .nanos = self.nanos * factor };
    }

    pub fn div(self: Duration, divisor: u64) Duration {
        return Duration{ .nanos = self.nanos / divisor };
    }

    pub fn isZero(self: Duration) bool {
        return self.nanos == 0;
    }
};

/// 定时器条目
const TimerEntry = struct {
    deadline: Instant,
    waker: future.Waker,
    node: utils.IntrusiveNode(@This()),
    id: u64,
};

/// 全局定时器轮
pub const TimerWheel = struct {
    entries: utils.IntrusiveList(TimerEntry, "node"),
    next_id: utils.Atomic.Value(u64),
    mutex: std.Thread.Mutex,

    pub fn init() TimerWheel {
        return TimerWheel{
            .entries = utils.IntrusiveList(TimerEntry, "node").init(),
            .next_id = utils.Atomic.Value(u64).init(1),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn addTimer(self: *TimerWheel, deadline: Instant, waker: future.Waker) u64 {
        const id = self.next_id.fetchAdd(1, .monotonic);

        self.mutex.lock();
        defer self.mutex.unlock();

        var entry = TimerEntry{
            .deadline = deadline,
            .waker = waker,
            .node = .{},
            .id = id,
        };

        // 简化实现：直接插入到末尾
        // TODO: 实现按截止时间排序的插入
        self.entries.pushBack(&entry);
        return id;
    }

    pub fn removeTimer(self: *TimerWheel, id: u64) bool {
        _ = self;
        _ = id;
        // TODO: 实现定时器移除功能
        return false;
    }

    pub fn processExpired(self: *TimerWheel) void {
        _ = self;
        // TODO: 实现定时器到期处理
    }

    pub fn nextDeadline(self: *TimerWheel) ?Instant {
        _ = self;
        // TODO: 实现下一个截止时间获取
        return null;
    }
};

/// 全局定时器实例
var global_timer_wheel = TimerWheel.init();

/// 延迟Future
pub const DelayFuture = struct {
    deadline: Instant,
    timer_id: ?u64 = null,

    pub fn init(duration: Duration) DelayFuture {
        return DelayFuture{
            .deadline = Instant.now().add(duration),
        };
    }

    pub fn poll(self: *DelayFuture, ctx: *future.Context) future.Poll(void) {
        const now = Instant.now();

        if (now.isAfter(self.deadline) or now.nanos == self.deadline.nanos) {
            return .{ .ready = {} };
        }

        // 如果还没有注册定时器，则注册
        if (self.timer_id == null) {
            self.timer_id = global_timer_wheel.addTimer(self.deadline, ctx.waker.clone());
        }

        return .pending;
    }

    pub fn deinit(self: *DelayFuture) void {
        if (self.timer_id) |id| {
            _ = global_timer_wheel.removeTimer(id);
        }
    }
};

/// 超时Future包装器
pub fn TimeoutFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        inner_future: *anyopaque, // 指向原始Future的指针
        poll_fn: *const fn (*anyopaque, *future.Context) future.Poll(T),
        delay_future: DelayFuture,
        completed: bool = false,

        pub fn init(inner_future: anytype, timeout_duration: Duration) Self {
            const FutureType = @TypeOf(inner_future);

            return Self{
                .inner_future = @ptrCast(inner_future),
                .poll_fn = struct {
                    fn poll(ptr: *anyopaque, ctx: *future.Context) future.Poll(T) {
                        const typed_future = @as(*FutureType, @ptrCast(@alignCast(ptr)));
                        return typed_future.poll(ctx);
                    }
                }.poll,
                .delay_future = DelayFuture.init(timeout_duration),
            };
        }

        pub fn poll(self: *Self, ctx: *future.Context) future.Poll(union(enum) { value: T, timeout: void }) {
            if (self.completed) {
                return .{ .ready = .timeout };
            }

            // 首先检查原始Future
            switch (self.poll_fn(self.inner_future, ctx)) {
                .ready => |value| {
                    self.completed = true;
                    return .{ .ready = .{ .value = value } };
                },
                .pending => {},
            }

            // 然后检查超时
            switch (self.delay_future.poll(ctx)) {
                .ready => {
                    self.completed = true;
                    return .{ .ready = .timeout };
                },
                .pending => {},
            }

            return .pending;
        }

        pub fn deinit(self: *Self) void {
            self.delay_future.deinit();
        }
    };
}

/// 便利函数：创建延迟Future
pub fn delay(duration: Duration) DelayFuture {
    return DelayFuture.init(duration);
}

/// 便利函数：为Future添加超时
pub fn timeout(comptime T: type, inner_future: anytype, timeout_duration: Duration) TimeoutFuture(T) {
    return TimeoutFuture(T).init(inner_future, timeout_duration);
}

/// 定时器服务，需要在运行时定期调用
pub fn processTimers() void {
    global_timer_wheel.processExpired();
}

/// 获取下一个定时器的截止时间
pub fn getNextTimerDeadline() ?Instant {
    return global_timer_wheel.nextDeadline();
}

// 测试
test "Duration基础操作" {
    const testing = std.testing;

    const d1 = Duration.fromMillis(1000);
    const d2 = Duration.fromSecs(1);

    try testing.expect(d1.nanos == d2.nanos);
    try testing.expect(d1.asMillis() == 1000);
    try testing.expect(d2.asSecs() == 1);

    const d3 = d1.add(d2);
    try testing.expect(d3.asSecs() == 2);
}

test "Instant基础操作" {
    const testing = std.testing;

    const now = Instant.now();
    const later = now.add(Duration.fromMillis(100));

    try testing.expect(later.isAfter(now));
    try testing.expect(now.isBefore(later));

    const diff = later.sub(now);
    try testing.expect(diff.asMillis() == 100);
}

test "DelayFuture基础功能" {
    const testing = std.testing;

    var delay_future = DelayFuture.init(Duration.fromNanos(1)); // 很短的延迟
    defer delay_future.deinit();

    const waker = future.Waker.noop();
    var ctx = future.Context.init(waker);

    // 等待一小段时间
    std.time.sleep(1000); // 1微秒

    const result = delay_future.poll(&ctx);
    try testing.expect(result.isReady());
}
