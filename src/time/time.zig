//! 时间模块
//!
//! 提供异步定时器和时间相关功能。

const std = @import("std");
const future = @import("../future/future.zig");
const utils = @import("../utils/utils.zig");

/// 异步睡眠
pub fn sleep(duration_ms: u64) SleepFuture {
    return SleepFuture{
        .deadline = std.time.milliTimestamp() + @as(i64, @intCast(duration_ms)),
    };
}

/// 睡眠Future
const SleepFuture = struct {
    deadline: i64,

    pub fn poll(self: *@This(), ctx: *future.Context) future.Poll(void) {
        _ = ctx;

        if (std.time.milliTimestamp() >= self.deadline) {
            return .{ .ready = {} };
        }

        return .pending;
    }
};

// 测试
test "异步睡眠基础功能" {
    const testing = std.testing;

    var sleep_future = sleep(1); // 1毫秒
    const waker = future.Waker.noop();
    var ctx = future.Context.init(waker);

    // 第一次轮询应该返回pending
    const result1 = sleep_future.poll(&ctx);
    try testing.expect(result1.isPending());

    // 🚀 Zokio 8.0: 使用异步等待替代sleep阻塞调用
    // 模拟时间流逝，直接设置deadline为过去时间
    sleep_future.deadline = std.time.milliTimestamp() - 1;
    const result2 = sleep_future.poll(&ctx);
    try testing.expect(result2.isReady());
}
