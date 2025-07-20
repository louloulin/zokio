//! 时间模块
//!
//! 提供基础的时间相关功能。

const std = @import("std");

/// 时间工具
pub const TimeUtils = struct {
    /// 获取当前时间戳（毫秒）
    pub fn nowMillis() i64 {
        return std.time.milliTimestamp();
    }

    /// 获取当前时间戳（纳秒）
    pub fn nowNanos() i128 {
        return std.time.nanoTimestamp();
    }

    /// 睡眠指定毫秒数
    pub fn sleepMillis(duration_ms: u64) void {
        std.time.sleep(duration_ms * std.time.ns_per_ms);
    }

    /// 睡眠指定纳秒数
    pub fn sleepNanos(duration_ns: u64) void {
        std.time.sleep(duration_ns);
    }

    /// 计算两个时间戳之间的差值（毫秒）
    pub fn diffMillis(start: i64, end: i64) i64 {
        return end - start;
    }

    /// 计算两个时间戳之间的差值（纳秒）
    pub fn diffNanos(start: i128, end: i128) i128 {
        return end - start;
    }

    /// 检查是否超时
    pub fn isTimeout(start_time: i64, timeout_ms: u64) bool {
        const current = nowMillis();
        return (current - start_time) >= @as(i64, @intCast(timeout_ms));
    }
};

/// 简单的计时器
pub const Timer = struct {
    start_time: i128,

    pub fn start() Timer {
        return Timer{
            .start_time = TimeUtils.nowNanos(),
        };
    }

    pub fn elapsedNanos(self: *const Timer) i128 {
        return TimeUtils.nowNanos() - self.start_time;
    }

    pub fn elapsedMillis(self: *const Timer) i128 {
        return @divTrunc(self.elapsedNanos(), std.time.ns_per_ms);
    }

    pub fn elapsedMicros(self: *const Timer) i128 {
        return @divTrunc(self.elapsedNanos(), std.time.ns_per_us);
    }

    pub fn reset(self: *Timer) void {
        self.start_time = TimeUtils.nowNanos();
    }
};

/// 超时检查器
pub const TimeoutChecker = struct {
    start_time: i128,
    timeout_ns: u64,

    pub fn init(timeout_ms: u64) TimeoutChecker {
        return TimeoutChecker{
            .start_time = TimeUtils.nowNanos(),
            .timeout_ns = timeout_ms * std.time.ns_per_ms,
        };
    }

    pub fn isExpired(self: *const TimeoutChecker) bool {
        const elapsed = TimeUtils.nowNanos() - self.start_time;
        return elapsed >= @as(i128, @intCast(self.timeout_ns));
    }

    pub fn remainingNanos(self: *const TimeoutChecker) i128 {
        const elapsed = TimeUtils.nowNanos() - self.start_time;
        const remaining = @as(i128, @intCast(self.timeout_ns)) - elapsed;
        return @max(0, remaining);
    }

    pub fn remainingMillis(self: *const TimeoutChecker) i128 {
        return @divTrunc(self.remainingNanos(), std.time.ns_per_ms);
    }
};

// 测试
test "TimeUtils 基本功能" {
    const testing = std.testing;

    // 测试时间戳获取
    const millis1 = TimeUtils.nowMillis();
    const nanos1 = TimeUtils.nowNanos();

    // 短暂睡眠
    TimeUtils.sleepMillis(1);

    const millis2 = TimeUtils.nowMillis();
    const nanos2 = TimeUtils.nowNanos();

    // 验证时间前进
    try testing.expect(millis2 >= millis1);
    try testing.expect(nanos2 > nanos1);

    // 测试时间差计算
    const diff_millis = TimeUtils.diffMillis(millis1, millis2);
    const diff_nanos = TimeUtils.diffNanos(nanos1, nanos2);

    try testing.expect(diff_millis >= 0);
    try testing.expect(diff_nanos > 0);
}

test "Timer 功能测试" {
    const testing = std.testing;

    var timer = Timer.start();

    // 短暂睡眠
    TimeUtils.sleepMillis(1);

    const elapsed_nanos = timer.elapsedNanos();
    const elapsed_millis = timer.elapsedMillis();

    try testing.expect(elapsed_nanos > 0);
    try testing.expect(elapsed_millis >= 0);

    // 重置计时器
    timer.reset();
    const new_elapsed = timer.elapsedNanos();
    try testing.expect(new_elapsed < elapsed_nanos);
}

test "TimeoutChecker 功能测试" {
    const testing = std.testing;

    var checker = TimeoutChecker.init(10); // 10ms 超时

    // 初始状态不应该超时
    try testing.expect(!checker.isExpired());
    try testing.expect(checker.remainingMillis() > 0);

    // 短暂睡眠后检查
    TimeUtils.sleepMillis(1);

    // 应该还没超时
    try testing.expect(!checker.isExpired());

    // 检查剩余时间
    const remaining = checker.remainingMillis();
    try testing.expect(remaining >= 0);
}
