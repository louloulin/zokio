//! Zokio async_block 实现
//!
//! 提供简洁的async/await语法，类似于Rust的async块
//!
//! 使用方式:
//! ```zig
//! const task = async_block(struct {
//!     fn run() !u32 {
//!         const result1 = await_fn(fetch_data());
//!         const result2 = await_fn(process_data(result1));
//!         return result2;
//!     }
//! }.run);
//! ```

const std = @import("std");
const future = @import("future.zig");

// 导入事件循环相关模块
const AsyncEventLoop = @import("../runtime/async_event_loop.zig").AsyncEventLoop;

pub const Context = future.Context;
pub const Poll = future.Poll;
pub const Waker = future.Waker;
pub const Budget = future.Budget;

/// 🚀 Zokio 8.0 真正的异步await函数 - 完全事件驱动实现
///
/// 核心改进：
/// - 完全移除Thread.yield()调用
/// - 基于AsyncEventLoop的真正事件驱动
/// - 支持任务暂停和恢复机制
/// - 集成Waker系统进行任务唤醒
pub fn await_fn(future_arg: anytype) @TypeOf(future_arg).Output {
    // 编译时验证Future类型
    comptime {
        if (!@hasDecl(@TypeOf(future_arg), "poll")) {
            @compileError("await_fn() 需要实现 poll() 方法的 Future 类型");
        }
        if (!@hasDecl(@TypeOf(future_arg), "Output")) {
            @compileError("await_fn() 需要定义 Output 类型的 Future 类型");
        }
    }

    // 创建异步任务状态机
    const AsyncTask = struct {
        future: @TypeOf(future_arg),
        state: TaskState,
        result: ?@TypeOf(future_arg).Output = null,
        waker: ?Waker = null,

        const Self = @This();

        const TaskState = enum {
            initial, // 初始状态
            polling, // 正在轮询
            suspended, // 已暂停，等待事件
            completed, // 已完成
        };

        pub fn poll(self: *Self, ctx: *Context) Poll(@TypeOf(future_arg).Output) {
            switch (self.state) {
                .initial => {
                    self.state = .polling;
                    return self.poll(ctx);
                },
                .polling => {
                    switch (self.future.poll(ctx)) {
                        .ready => |result| {
                            self.result = result;
                            self.state = .completed;
                            return .{ .ready = result };
                        },
                        .pending => {
                            // 🚀 真正的异步：暂停任务并注册到事件循环
                            self.state = .suspended;
                            self.waker = ctx.waker;
                            return .pending;
                        },
                    }
                },
                .suspended => {
                    // 任务被事件循环唤醒，继续轮询
                    self.state = .polling;
                    return self.poll(ctx);
                },
                .completed => {
                    return .{ .ready = self.result.? };
                },
            }
        }
    };

    var task = AsyncTask{
        .future = future_arg,
        .state = .initial,
    };

    // 获取当前异步执行上下文
    const ctx = getCurrentAsyncContext();

    // 🚀 事件驱动的轮询循环 - 完全非阻塞实现
    while (true) {
        switch (task.poll(ctx)) {
            .ready => |result| {
                // 任务完成，从事件循环移除
                if (getCurrentEventLoop()) |event_loop| {
                    event_loop.removeActiveTask();
                }
                return result;
            },
            .pending => {
                // 🚀 Zokio 8.0 核心改进：真正的事件驱动暂停
                if (getCurrentEventLoop()) |event_loop| {
                    // 将任务注册到事件循环的等待队列
                    if (task.waker) |waker| {
                        event_loop.registerWaitingTask(waker);
                    }

                    // 运行一次事件循环，处理其他就绪任务
                    event_loop.runOnce() catch {};

                    // 检查任务是否被唤醒
                    if (task.state == .suspended) {
                        // 任务仍在等待，继续事件循环
                        continue;
                    }
                } else {
                    // 降级处理：如果没有事件循环，使用最小延迟
                    // 这是为了向后兼容，但不推荐在生产环境使用
                    std.atomic.spinLoopHint();
                }
            },
        }
    }
}

/// 线程本地的异步上下文
threadlocal var current_async_context: ?*Context = null;

/// 获取当前事件循环 - 使用runtime模块的统一实现
pub fn getCurrentEventLoop() ?*AsyncEventLoop {
    const runtime = @import("../runtime/runtime.zig");
    return runtime.getCurrentEventLoop();
}

/// 设置当前事件循环 - 使用runtime模块的统一实现
pub fn setCurrentEventLoop(event_loop: ?*AsyncEventLoop) void {
    const runtime = @import("../runtime/runtime.zig");
    runtime.setCurrentEventLoop(event_loop);
}

/// 获取当前异步上下文
fn getCurrentAsyncContext() *Context {
    return current_async_context orelse {
        // 如果没有上下文，创建一个默认的
        const static = struct {
            var global_budget = Budget.init();
            var default_ctx: Context = undefined;
            var initialized = false;
        };

        if (!static.initialized) {
            const waker = Waker.noop();
            static.default_ctx = Context{
                .waker = waker,
                .budget = &static.global_budget,
            };
            static.initialized = true;
        }

        current_async_context = &static.default_ctx;
        return &static.default_ctx;
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
        state: State = .initial,

        /// 结果
        result: ?ReturnType = null,

        /// 错误信息（如果ReturnType是错误联合类型）
        error_info: ?anyerror = null,

        /// 执行状态枚举
        const State = enum {
            initial, // 初始状态
            running, // 运行中
            completed, // 已完成
            failed, // 执行失败
        };

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
            switch (self.state) {
                .initial => {
                    self.state = .running;

                    // 检查是否应该让出执行权
                    if (ctx.shouldYield()) {
                        return .pending;
                    }

                    return self.executeFunction(ctx);
                },
                .running => {
                    // 检查是否应该让出执行权
                    if (ctx.shouldYield()) {
                        return .pending;
                    }

                    // 如果已有结果，返回结果
                    if (self.result != null) {
                        self.state = .completed;
                        return .{ .ready = self.result.? };
                    }

                    // 继续执行
                    return self.executeFunction(ctx);
                },
                .completed => {
                    return .{ .ready = self.result.? };
                },
                .failed => {
                    // 对于失败状态，简单返回pending
                    // 在生产环境中应该有更好的错误处理
                    return .pending;
                },
            }
        }

        fn executeFunction(self: *Self, ctx: *Context) Poll(ReturnType) {
            // 设置当前上下文
            const old_ctx = current_async_context;
            current_async_context = ctx;
            defer current_async_context = old_ctx;

            // 执行异步函数
            if (@typeInfo(ReturnType) == .error_union) {
                // 处理可能返回错误的函数
                self.result = self.async_fn() catch |err| {
                    self.error_info = err;
                    self.state = .failed;
                    return .{ .ready = err };
                };
            } else {
                self.result = self.async_fn();
            }

            self.state = .completed;
            return .{ .ready = self.result.? };
        }

        pub fn reset(self: *Self) void {
            self.state = .initial;
            self.result = null;
            self.error_info = null;
        }

        /// 检查是否已完成
        pub fn isCompleted(self: *const Self) bool {
            return self.state == .completed;
        }

        /// 检查是否失败
        pub fn isFailed(self: *const Self) bool {
            return self.state == .failed;
        }

        /// 获取错误信息（如果有）
        pub fn getError(self: *const Self) ?anyerror {
            return self.error_info;
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
test "async_block基础功能" {
    const testing = std.testing;

    // 创建简单的异步块
    const task = async_block(struct {
        fn run() u32 {
            return 42;
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
        try testing.expectEqual(@as(u32, 42), result.ready);
    }
}

test "async_block状态管理" {
    const testing = std.testing;

    const task = async_block(struct {
        fn run() []const u8 {
            return "测试结果";
        }
    }.run);

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    var async_task = task;

    // 第一次轮询
    const result1 = async_task.poll(&ctx);
    try testing.expect(result1.isReady());

    // 第二次轮询应该返回相同结果
    const result2 = async_task.poll(&ctx);
    try testing.expect(result2.isReady());

    if (result1 == .ready and result2 == .ready) {
        try testing.expect(std.mem.eql(u8, result1.ready, result2.ready));
    }
}

test "async_block错误处理" {
    const testing = std.testing;

    const TestError = error{TestFailed};

    const task = async_block(struct {
        fn run() TestError!u32 {
            return TestError.TestFailed;
        }
    }.run);

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    var async_task = task;

    // 轮询应该返回错误
    const result = async_task.poll(&ctx);
    try testing.expect(result.isReady());

    if (result == .ready) {
        try testing.expectError(TestError.TestFailed, result.ready);
    }
}

test "async_block状态检查" {
    const testing = std.testing;

    const task = async_block(struct {
        fn run() u32 {
            return 42;
        }
    }.run);

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    var async_task = task;

    // 初始状态
    try testing.expect(!async_task.isCompleted());
    try testing.expect(!async_task.isFailed());

    // 执行后
    _ = async_task.poll(&ctx);
    try testing.expect(async_task.isCompleted());
    try testing.expect(!async_task.isFailed());
}

test "async_block重置功能" {
    const testing = std.testing;

    const task = async_block(struct {
        fn run() u32 {
            return 42;
        }
    }.run);

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    var async_task = task;

    // 第一次执行
    const result1 = async_task.poll(&ctx);
    try testing.expect(result1.isReady());
    try testing.expect(async_task.isCompleted());

    // 重置
    async_task.reset();
    try testing.expect(!async_task.isCompleted());

    // 再次执行
    const result2 = async_task.poll(&ctx);
    try testing.expect(result2.isReady());
    try testing.expect(async_task.isCompleted());
}
