//! 同步原语模块
//!
//! 提供基础的同步原语，如互斥锁、信号量等。

const std = @import("std");

/// 简单的原子互斥锁
pub const SimpleMutex = struct {
    locked: std.atomic.Value(bool),

    pub fn init() SimpleMutex {
        return SimpleMutex{
            .locked = std.atomic.Value(bool).init(false),
        };
    }

    pub fn tryLock(self: *SimpleMutex) bool {
        return self.locked.cmpxchgWeak(false, true, .acquire, .monotonic) == null;
    }

    pub fn unlock(self: *SimpleMutex) void {
        self.locked.store(false, .release);
    }
};

/// 简单的原子信号量
pub const SimpleSemaphore = struct {
    permits: std.atomic.Value(u32),

    pub fn init(initial_permits: u32) SimpleSemaphore {
        return SimpleSemaphore{
            .permits = std.atomic.Value(u32).init(initial_permits),
        };
    }

    pub fn tryAcquire(self: *SimpleSemaphore, count: u32) bool {
        var current = self.permits.load(.monotonic);
        while (current >= count) {
            if (self.permits.cmpxchgWeak(current, current - count, .acquire, .monotonic) == null) {
                return true;
            }
            current = self.permits.load(.monotonic);
        }
        return false;
    }

    pub fn release(self: *SimpleSemaphore, count: u32) void {
        _ = self.permits.fetchAdd(count, .release);
    }

    pub fn availablePermits(self: *const SimpleSemaphore) u32 {
        return self.permits.load(.monotonic);
    }
};

/// 原子计数器
pub const AtomicCounter = struct {
    value: std.atomic.Value(u64),

    pub fn init(initial_value: u64) AtomicCounter {
        return AtomicCounter{
            .value = std.atomic.Value(u64).init(initial_value),
        };
    }

    pub fn increment(self: *AtomicCounter) u64 {
        return self.value.fetchAdd(1, .monotonic);
    }

    pub fn decrement(self: *AtomicCounter) u64 {
        return self.value.fetchSub(1, .monotonic);
    }

    pub fn get(self: *const AtomicCounter) u64 {
        return self.value.load(.monotonic);
    }

    pub fn set(self: *AtomicCounter, new_value: u64) void {
        self.value.store(new_value, .monotonic);
    }

    pub fn compareAndSwap(self: *AtomicCounter, expected: u64, new_value: u64) ?u64 {
        return self.value.cmpxchgWeak(expected, new_value, .monotonic, .monotonic);
    }
};

// 测试
test "SimpleMutex 基本功能" {
    const testing = std.testing;

    var mutex = SimpleMutex.init();

    // 测试初始状态
    try testing.expect(mutex.tryLock());

    // 测试重复锁定失败
    try testing.expect(!mutex.tryLock());

    // 测试解锁
    mutex.unlock();
    try testing.expect(mutex.tryLock());

    mutex.unlock();
}

test "SimpleSemaphore 基本功能" {
    const testing = std.testing;

    var semaphore = SimpleSemaphore.init(3);

    // 测试初始状态
    try testing.expectEqual(@as(u32, 3), semaphore.availablePermits());

    // 测试获取许可
    try testing.expect(semaphore.tryAcquire(2));
    try testing.expectEqual(@as(u32, 1), semaphore.availablePermits());

    // 测试获取剩余许可
    try testing.expect(semaphore.tryAcquire(1));
    try testing.expectEqual(@as(u32, 0), semaphore.availablePermits());

    // 测试获取失败
    try testing.expect(!semaphore.tryAcquire(1));

    // 测试释放许可
    semaphore.release(2);
    try testing.expectEqual(@as(u32, 2), semaphore.availablePermits());

    try testing.expect(semaphore.tryAcquire(1));
    try testing.expectEqual(@as(u32, 1), semaphore.availablePermits());
}

test "AtomicCounter 基本功能" {
    const testing = std.testing;

    var counter = AtomicCounter.init(10);

    // 测试初始值
    try testing.expectEqual(@as(u64, 10), counter.get());

    // 测试递增
    const old_value = counter.increment();
    try testing.expectEqual(@as(u64, 10), old_value);
    try testing.expectEqual(@as(u64, 11), counter.get());

    // 测试递减
    const old_value2 = counter.decrement();
    try testing.expectEqual(@as(u64, 11), old_value2);
    try testing.expectEqual(@as(u64, 10), counter.get());

    // 测试设置
    counter.set(42);
    try testing.expectEqual(@as(u64, 42), counter.get());

    // 测试比较和交换
    const result = counter.compareAndSwap(42, 84);
    try testing.expectEqual(@as(?u64, null), result);
    try testing.expectEqual(@as(u64, 84), counter.get());

    // 测试失败的比较和交换
    const result2 = counter.compareAndSwap(42, 168);
    try testing.expectEqual(@as(u64, 84), result2.?);
    try testing.expectEqual(@as(u64, 84), counter.get());
}
