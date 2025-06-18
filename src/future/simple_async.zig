//! Zokio 简洁的 async/await 实现
//!
//! 提供真正简洁的async/await语法，类似于Rust

const std = @import("std");
const future = @import("future.zig");

pub const Context = future.Context;
pub const Poll = future.Poll;
pub const Waker = future.Waker;

/// 全局await函数 - 直接在async块中使用
pub fn await_fn(future_arg: anytype) @TypeOf(future_arg).Output {
    // 获取当前的异步上下文
    const ctx = getCurrentAsyncContext();

    var f = future_arg;
    while (true) {
        switch (f.poll(ctx)) {
            .ready => |result| return result,
            .pending => {
                // 在实际实现中，这里会让出控制权
                // 现在简化为短暂等待
                std.time.sleep(1 * std.time.ns_per_ms);
            },
        }
    }
}

/// 线程本地的异步上下文
threadlocal var current_async_context: ?*Context = null;

/// 获取当前异步上下文
fn getCurrentAsyncContext() *Context {
    return current_async_context orelse {
        // 如果没有上下文，创建一个默认的
        const waker = Waker.noop();
        var ctx = Context.init(waker);
        current_async_context = &ctx;
        return &ctx;
    };
}

/// 设置当前异步上下文
pub fn setCurrentAsyncContext(ctx: *Context) void {
    current_async_context = ctx;
}

/// 异步块实现
pub fn AsyncBlock(comptime ReturnType: type) type {
    return struct {
        const Self = @This();

        pub const Output = ReturnType;

        /// 异步函数
        async_fn: *const fn () ReturnType,

        /// 执行状态
        executed: bool = false,

        /// 结果
        result: ?ReturnType = null,

        pub fn init(comptime func: anytype) Self {
            const wrapper = struct {
                fn call() ReturnType {
                    return func();
                }
            };

            return Self{
                .async_fn = wrapper.call,
            };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(ReturnType) {
            if (self.executed) {
                return .{ .ready = self.result.? };
            }

            // 设置当前上下文
            const old_ctx = current_async_context;
            current_async_context = ctx;
            defer current_async_context = old_ctx;

            // 执行异步函数
            self.result = self.async_fn();
            self.executed = true;

            return .{ .ready = self.result.? };
        }

        pub fn reset(self: *Self) void {
            self.executed = false;
            self.result = null;
        }
    };
}

/// 创建异步块的便捷函数
pub fn async_block(comptime func: anytype) AsyncBlock(@TypeOf(func())) {
    return AsyncBlock(@TypeOf(func())).init(func);
}

/// await宏 - 全局可用
pub const await_macro = await_fn;

// 测试用的Future
const TestFuture = struct {
    value: u32,
    delay_ms: u64,
    start_time: ?i64 = null,

    pub const Output = u32;

    pub fn init(val: u32, delay: u64) @This() {
        return @This(){
            .value = val,
            .delay_ms = delay,
        };
    }

    pub fn poll(self: *@This(), ctx: *Context) Poll(u32) {
        _ = ctx;

        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            return .{ .ready = self.value };
        }

        return .pending;
    }
};

/// 创建测试Future的便捷函数
pub fn fetch_data() TestFuture {
    return TestFuture.init(42, 50);
}

pub fn process_data(input: u32) TestFuture {
    return TestFuture.init(input * 2, 30);
}

// 测试
test "简洁async/await语法" {
    const testing = std.testing;

    // 创建异步块
    const task = async_block(struct {
        fn run() u32 {
            const result1 = await (fetch_data());
            const result2 = await (process_data(result1));
            return result2;
        }
    }.run);

    // 创建上下文
    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 执行异步块
    var async_task = task;
    const result = async_task.poll(&ctx);

    try testing.expect(result.isReady());
    if (result == .ready) {
        try testing.expectEqual(@as(u32, 84), result.ready); // 42 * 2
    }
}

test "嵌套async块" {
    const testing = std.testing;

    const inner_task = async_block(struct {
        fn run() u32 {
            const data = await (fetch_data());
            return data + 10;
        }
    }.run);

    const outer_task = async_block(struct {
        fn run() u32 {
            const inner_result = await (inner_task);
            const processed = await (process_data(inner_result));
            return processed + 5;
        }
    }.run);

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    var async_task = outer_task;
    const result = async_task.poll(&ctx);

    try testing.expect(result.isReady());
    if (result == .ready) {
        // (42 + 10) * 2 + 5 = 109
        try testing.expectEqual(@as(u32, 109), result.ready);
    }
}
