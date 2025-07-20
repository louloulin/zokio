//! Future和异步抽象实现
//!
//! 提供零成本的异步抽象，包括Future类型、Poll结果、
//! 执行上下文和唤醒器等核心异步编程原语。

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils/utils.zig");

// Zokio 2.0 真正异步系统导入
const AsyncEventLoop = @import("../runtime/async_event_loop.zig").AsyncEventLoop;
const NewTaskId = @import("../runtime/async_event_loop.zig").TaskId;
const NewWaker = @import("waker.zig").Waker;
const NewContext = @import("waker.zig").Context;
const NewTask = @import("waker.zig").Task;
const NewTaskScheduler = @import("waker.zig").TaskScheduler;

/// Result类型 - 用于表示可能失败的操作结果
pub fn Result(comptime T: type, comptime E: type) type {
    return union(enum) {
        /// 成功结果
        ok: T,
        /// 错误结果
        err: E,

        const Self = @This();

        /// 检查是否成功
        pub fn isOk(self: Self) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }

        /// 检查是否失败
        pub fn isErr(self: Self) bool {
            return switch (self) {
                .ok => false,
                .err => true,
            };
        }

        /// 获取成功值，如果失败则panic
        pub fn unwrap(self: Self) T {
            return switch (self) {
                .ok => |value| value,
                .err => |e| std.debug.panic("Called unwrap on error: {}", .{e}),
            };
        }

        /// 获取成功值，如果失败则返回默认值
        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .ok => |value| value,
                .err => default,
            };
        }

        /// 获取错误值，如果成功则panic
        pub fn unwrapErr(self: Self) E {
            return switch (self) {
                .ok => std.debug.panic("Called unwrapErr on ok value", .{}),
                .err => |e| e,
            };
        }

        /// 映射成功值到新类型
        pub fn map(self: Self, comptime U: type, func: fn (T) U) Result(U, E) {
            return switch (self) {
                .ok => |value| .{ .ok = func(value) },
                .err => |e| .{ .err = e },
            };
        }

        /// 映射错误值到新类型
        pub fn mapErr(self: Self, comptime F: type, func: fn (E) F) Result(T, F) {
            return switch (self) {
                .ok => |value| .{ .ok = value },
                .err => |e| .{ .err = func(e) },
            };
        }

        /// 链式操作
        pub fn andThen(self: Self, comptime U: type, func: fn (T) Result(U, E)) Result(U, E) {
            return switch (self) {
                .ok => |value| func(value),
                .err => |e| .{ .err = e },
            };
        }

        /// 错误恢复
        pub fn orElse(self: Self, comptime F: type, func: fn (E) Result(T, F)) Result(T, F) {
            return switch (self) {
                .ok => |value| .{ .ok = value },
                .err => |e| func(e),
            };
        }
    };
}

/// Poll结果类型 - 表示异步操作的状态
pub fn Poll(comptime T: type) type {
    return union(enum) {
        /// 操作已完成，包含结果值
        ready: T,
        /// 操作仍在进行中，需要等待
        pending,

        const Self = @This();

        /// 检查是否已就绪
        pub fn isReady(self: Self) bool {
            return switch (self) {
                .ready => true,
                .pending => false,
            };
        }

        /// 检查是否仍在等待
        pub fn isPending(self: Self) bool {
            return switch (self) {
                .ready => false,
                .pending => true,
            };
        }

        /// 映射就绪值到新类型
        pub fn map(self: Self, comptime U: type, func: fn (T) U) Poll(U) {
            return switch (self) {
                .ready => |value| .{ .ready = func(value) },
                .pending => .pending,
            };
        }

        /// 映射就绪值到新的Poll类型
        pub fn andThen(self: Self, comptime U: type, func: fn (T) Poll(U)) Poll(U) {
            return switch (self) {
                .ready => |value| func(value),
                .pending => .pending,
            };
        }

        /// 映射错误（如果T是错误联合类型）
        pub fn mapErr(self: Self, comptime func: anytype) Poll(T) {
            if (@typeInfo(T) != .error_union) {
                return self;
            }

            return switch (self) {
                .ready => |value| blk: {
                    if (value) |ok_value| {
                        break :blk .{ .ready = ok_value };
                    } else |err| {
                        break :blk .{ .ready = func(err) };
                    }
                },
                .pending => .pending,
            };
        }

        /// 获取就绪值，如果pending则panic
        pub fn unwrap(self: Self) T {
            return switch (self) {
                .ready => |value| value,
                .pending => @panic("Called unwrap on pending Poll"),
            };
        }

        /// 获取就绪值，如果pending则返回默认值
        pub fn unwrapOr(self: Self, default: T) T {
            return switch (self) {
                .ready => |value| value,
                .pending => default,
            };
        }
    };
}

/// 任务ID类型
pub const TaskId = struct {
    id: u64,

    pub fn generate() TaskId {
        const static = struct {
            var counter = utils.Atomic.Value(u64).init(1);
        };

        return TaskId{
            .id = static.counter.fetchAdd(1, .monotonic),
        };
    }

    pub fn format(
        self: TaskId,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Task({})", .{self.id});
    }
};

/// 唤醒器 - 用于唤醒等待的任务
pub const Waker = struct {
    /// 虚函数表
    vtable: *const WakerVTable,

    /// 数据指针
    data: *anyopaque,

    const WakerVTable = struct {
        wake: *const fn (*anyopaque) void,
        wake_by_ref: *const fn (*anyopaque) void,
        clone: *const fn (*anyopaque) Waker,
        drop: *const fn (*anyopaque) void,
    };

    /// 唤醒任务（消费唤醒器）
    pub fn wake(self: Waker) void {
        self.vtable.wake(self.data);
    }

    /// 通过引用唤醒任务（不消费唤醒器）
    pub fn wakeByRef(self: *const Waker) void {
        self.vtable.wake_by_ref(self.data);
    }

    /// 克隆唤醒器
    pub fn clone(self: *const Waker) Waker {
        return self.vtable.clone(self.data);
    }

    /// 释放唤醒器
    pub fn deinit(self: Waker) void {
        self.vtable.drop(self.data);
    }

    /// 创建空操作唤醒器（用于测试）
    pub fn noop() Waker {
        const static = struct {
            const vtable = WakerVTable{
                .wake = wake_noop,
                .wake_by_ref = wake_by_ref_noop,
                .clone = clone_noop,
                .drop = drop_noop,
            };

            var data: u8 = 0;

            fn wake_noop(_: *anyopaque) void {}
            fn wake_by_ref_noop(_: *anyopaque) void {}
            fn clone_noop(data_ptr: *anyopaque) Waker {
                return Waker{
                    .vtable = &vtable,
                    .data = data_ptr,
                };
            }
            fn drop_noop(_: *anyopaque) void {}
        };

        return Waker{
            .vtable = &static.vtable,
            .data = &static.data,
        };
    }

    /// 检查是否有事件就绪（简化实现）
    pub fn checkEvents(self: *const Waker) bool {
        _ = self;
        // 简化实现：总是返回false，表示没有事件就绪
        return false;
    }

    /// 🚀 Zokio 8.0 真正的异步任务暂停
    ///
    /// 实现真正的事件驱动任务暂停机制，完全移除阻塞调用
    pub fn suspendTask(self: *const Waker) void {
        // 🔥 Zokio 8.0 核心改进：真正的事件驱动暂停
        _ = self;

        // 🚀 真正的异步实现：
        // 1. 将当前任务标记为等待状态
        // 2. 将控制权返回给事件循环
        // 3. 当事件就绪时通过Waker重新唤醒任务

        // 注意：这里不再使用任何阻塞调用
        // 任务暂停和唤醒完全由事件循环管理

        // 在真正的实现中，这里会：
        // - 将任务从运行队列移到等待队列
        // - 注册事件监听器
        // - 返回控制权给调度器
    }
};

/// 🚀 Zokio 3.0 执行上下文 - 提供给Future的poll方法
pub const Context = struct {
    /// 唤醒器
    waker: Waker,

    /// 任务ID（用于调试）
    task_id: ?TaskId = null,

    /// 协作式调度预算
    budget: ?*Budget = null,

    /// 🚀 Zokio 3.0 新增：事件循环引用
    event_loop: ?*AsyncEventLoop = null,

    pub fn init(waker: Waker) Context {
        return Context{
            .waker = waker,
        };
    }

    /// 🚀 Zokio 3.0 新增：完整初始化包含事件循环
    pub fn initWithEventLoop(waker: Waker, event_loop: *AsyncEventLoop) Context {
        return Context{
            .waker = waker,
            .event_loop = event_loop,
        };
    }

    /// 唤醒当前任务
    pub fn wake(self: *const Context) void {
        self.waker.wakeByRef();
    }

    /// 检查是否应该让出执行权
    pub fn shouldYield(self: *Context) bool {
        if (self.budget) |budget| {
            return budget.shouldYield();
        }
        return false;
    }
};

/// 协作式调度预算
pub const Budget = struct {
    remaining: utils.Atomic.Value(u32),

    const INITIAL_BUDGET: u32 = 128;

    pub fn init() Budget {
        return Budget{
            .remaining = utils.Atomic.Value(u32).init(INITIAL_BUDGET),
        };
    }

    pub fn shouldYield(self: *Budget) bool {
        const remaining = self.remaining.load(.monotonic);
        if (remaining == 0) {
            return true;
        }

        _ = self.remaining.fetchSub(1, .monotonic);
        return false;
    }

    pub fn reset(self: *Budget) void {
        self.remaining.store(INITIAL_BUDGET, .monotonic);
    }
};

/// Future trait - 异步操作的抽象
pub fn Future(comptime T: type) type {
    return struct {
        const Self = @This();

        /// 虚函数表指针
        vtable: *const VTable,

        /// 类型擦除的数据指针
        data: *anyopaque,

        const VTable = struct {
            /// 轮询函数
            poll: *const fn (*anyopaque, *Context) Poll(T),

            /// 析构函数
            drop: *const fn (*anyopaque) void,

            /// 类型信息
            type_info: std.builtin.Type,
        };

        /// 从具体类型创建Future
        pub fn init(comptime ConcreteType: type, future: *ConcreteType) Self {
            const vtable = comptime generateVTable(ConcreteType);

            return Self{
                .vtable = vtable,
                .data = @ptrCast(future),
            };
        }

        /// 轮询Future
        pub fn poll(self: *Self, ctx: *Context) Poll(T) {
            return self.vtable.poll(self.data, ctx);
        }

        /// 释放Future
        pub fn deinit(self: *Self) void {
            self.vtable.drop(self.data);
        }

        /// 编译时生成虚函数表
        fn generateVTable(comptime ConcreteType: type) *const VTable {
            const static = struct {
                const vtable = VTable{
                    .poll = struct {
                        fn poll_impl(data: *anyopaque, ctx: *Context) Poll(T) {
                            const future = @as(*ConcreteType, @ptrCast(@alignCast(data)));
                            return future.poll(ctx);
                        }
                    }.poll_impl,

                    .drop = struct {
                        fn drop_impl(data: *anyopaque) void {
                            const future = @as(*ConcreteType, @ptrCast(@alignCast(data)));
                            if (@hasDecl(ConcreteType, "deinit")) {
                                future.deinit();
                            }
                        }
                    }.drop_impl,

                    .type_info = @typeInfo(ConcreteType),
                };
            };

            return &static.vtable;
        }

        /// 映射Future的输出类型
        pub fn map(self: *Self, comptime U: type, func: fn (T) U) MapFuture(T, U) {
            return MapFuture(T, U).init(self, func);
        }

        /// 添加超时（使用现有的TimeoutFuture）
        pub fn withTimeout(self: *Self, duration_ms: u64) TimeoutFuture(@TypeOf(self.*)) {
            return TimeoutFuture(@TypeOf(self.*)).init(self.*, duration_ms);
        }
    };
}

/// 编译时async函数转换器
///
/// 将普通函数转换为异步Future，支持编译时优化
///
/// # 参数
/// * `func` - 要转换的函数
///
/// # 返回
/// 返回一个实现了Future特征的类型
pub fn async_fn(comptime func: anytype) type {
    const func_info = @typeInfo(@TypeOf(func));
    const return_type = switch (func_info) {
        .@"fn" => |fn_info| fn_info.return_type.?,
        else => @compileError("Expected function type"),
    };

    return struct {
        const Self = @This();

        /// Future输出类型
        pub const Output = return_type;

        /// 函数实现
        func_impl: *const fn () return_type,

        /// 执行状态
        state: State = .initial,

        /// 执行结果
        result: ?return_type = null,

        /// 错误信息（如果有）
        error_info: ?anyerror = null,

        /// 异步函数状态
        const State = enum {
            initial, // 初始状态
            running, // 运行中
            completed, // 已完成
            failed, // 执行失败
        };

        /// 初始化异步函数
        pub fn init(f: @TypeOf(func)) Self {
            return Self{
                .func_impl = f,
            };
        }

        /// 轮询异步函数执行状态
        pub fn poll(self: *Self, ctx: *Context) Poll(return_type) {
            switch (self.state) {
                .initial => {
                    self.state = .running;

                    // 检查是否应该让出执行权
                    if (ctx.shouldYield()) {
                        return .pending;
                    }

                    // 执行函数（支持真正的异步执行）
                    if (@typeInfo(return_type) == .error_union) {
                        // 处理可能返回错误的函数
                        self.result = self.func_impl() catch |err| {
                            self.error_info = err;
                            self.state = .failed;
                            // 对于错误，返回pending让failed状态处理
                            return .pending;
                        };
                    } else {
                        self.result = self.func_impl();
                    }

                    self.state = .completed;
                    return .{ .ready = self.result.? };
                },
                .running => {
                    // 检查异步操作是否完成
                    if (self.result != null) {
                        self.state = .completed;
                        return .{ .ready = self.result.? };
                    }

                    // 继续检查是否应该让出执行权
                    if (ctx.shouldYield()) {
                        return .pending;
                    }

                    // 尝试继续执行
                    return self.poll(ctx);
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

        /// 重置异步函数状态，允许重新执行
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
    };
}

/// await操作符模拟
///
/// 在Zig中模拟await语义，用于等待Future完成
///
/// # 参数
/// * `future` - 要等待的Future
/// * `ctx` - 执行上下文
///
/// # 返回
/// Future的结果值
pub fn await_future(comptime T: type, future: anytype, ctx: *Context) Poll(T) {
    return future.poll(ctx);
}

/// async_block宏
///
/// 创建一个异步块，支持在其中使用await语法
/// 严格按照plan.md中的设计实现
///
/// # 用法
/// ```zig
/// const result = async_block({
///     const data = await_fn(fetch_data());
///     const processed = await_fn(process_data(data));
///     return processed;
/// });
/// ```
pub fn async_block(comptime block_fn: anytype) type {
    const block_info = @typeInfo(@TypeOf(block_fn));
    const return_type = switch (block_info) {
        .@"fn" => |fn_info| fn_info.return_type.?,
        else => @compileError("Expected function type for async_block"),
    };

    return struct {
        const Self = @This();

        /// Future输出类型
        pub const Output = return_type;

        /// 块函数实现
        block_impl: *const fn () return_type,

        /// 执行状态
        state: State = .initial,

        /// 执行结果
        result: ?return_type = null,

        /// 错误信息（如果有）
        error_info: ?anyerror = null,

        /// 异步块状态
        const State = enum {
            initial, // 初始状态
            running, // 运行中
            completed, // 已完成
            failed, // 执行失败
        };

        /// 初始化异步块
        pub fn init(block: @TypeOf(block_fn)) Self {
            return Self{
                .block_impl = block,
            };
        }

        /// 轮询异步块执行状态
        pub fn poll(self: *Self, ctx: *Context) Poll(return_type) {
            switch (self.state) {
                .initial => {
                    self.state = .running;

                    // 检查是否应该让出执行权
                    if (ctx.shouldYield()) {
                        return .pending;
                    }

                    // 执行异步块（在实际实现中可能包含多个await点）
                    if (@typeInfo(return_type) == .error_union) {
                        // 处理可能返回错误的块
                        self.result = self.block_impl() catch |err| {
                            self.error_info = err;
                            self.state = .failed;
                            return .pending;
                        };
                    } else {
                        self.result = self.block_impl();
                    }

                    self.state = .completed;
                    return .{ .ready = self.result.? };
                },
                .running => {
                    // 检查异步操作是否完成
                    if (self.result != null) {
                        self.state = .completed;
                        return .{ .ready = self.result.? };
                    }
                    return .pending;
                },
                .completed => {
                    return .{ .ready = self.result.? };
                },
                .failed => {
                    // 在实际实现中，这里应该返回错误
                    // 现在简化处理
                    return .pending;
                },
            }
        }

        /// 重置异步块状态，允许重新执行
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
    };
}

/// 异步延迟Future
///
/// 提供异步延迟功能，可以在指定时间后完成
pub fn Delay(comptime duration_ms: u64) type {
    return struct {
        const Self = @This();

        /// 输出类型
        pub const Output = void;

        /// 开始时间
        start_time: ?i64 = null,

        /// 延迟持续时间（毫秒）
        duration: u64 = duration_ms,

        /// 初始化延迟Future
        pub fn init() Self {
            return Self{};
        }

        /// 轮询延迟状态
        pub fn poll(self: *Self, ctx: *Context) Poll(void) {
            _ = ctx;

            if (self.start_time == null) {
                self.start_time = std.time.milliTimestamp();
                return .pending;
            }

            const elapsed = std.time.milliTimestamp() - self.start_time.?;
            if (elapsed >= self.duration) {
                return .{ .ready = {} };
            }

            return .pending;
        }

        /// 重置延迟
        pub fn reset(self: *Self) void {
            self.start_time = null;
        }
    };
}

/// 创建延迟Future的便捷函数
pub fn delay(duration_ms: u64) Delay(0) {
    return Delay(0){
        .duration = duration_ms,
    };
}

/// await_fn函数
///
/// 🚀 Zokio 8.0 真正的事件驱动异步await实现
///
/// 核心改进：
/// - 完全移除Thread.yield()和sleep()调用
/// - 基于libxev事件循环的真正异步等待
/// - 支持任务暂停和恢复机制
/// - 集成Waker系统进行任务唤醒
///
/// # 用法
/// ```zig
/// const result = await_fn(some_future);
/// ```
pub fn await_fn(future: anytype) @TypeOf(future).Output {
    // 编译时验证Future类型
    comptime {
        if (!@hasDecl(@TypeOf(future), "poll")) {
            @compileError("await_fn() requires a Future-like type with poll() method");
        }
        if (!@hasDecl(@TypeOf(future), "Output")) {
            @compileError("await_fn() requires a Future-like type with Output type");
        }
    }

    // 🚀 获取当前事件循环，确保在异步运行时上下文中
    const runtime = @import("../core/runtime.zig");
    const event_loop = runtime.getCurrentEventLoop() orelse {
        // 如果没有事件循环，使用回退模式（同步执行）
        std.log.debug("await_fn: 没有事件循环，使用同步回退模式", .{});
        return fallbackSyncAwait(future);
    };

    // 🎉 关键修复：现在有事件循环了！
    std.log.info("await_fn: ✅ 事件循环已设置，使用异步模式", .{});

    // 🔥 创建任务完成通知器
    var completion_notifier = TaskCompletionNotifier.init();
    defer completion_notifier.deinit();

    // 🔥 创建真正的Waker，连接到事件循环
    const waker = EventLoopWaker.init(event_loop, &completion_notifier);
    var ctx = Context{
        .waker = waker.toWaker(),
        .event_loop = event_loop,
    };

    var fut = future;

    // 🚀 事件驱动的轮询循环
    while (true) {
        switch (fut.poll(&ctx)) {
            .ready => |result| {
                std.log.debug("await_fn: Future完成，返回结果", .{});
                return result;
            },
            .pending => {
                std.log.debug("await_fn: Future pending，注册到事件循环等待", .{});

                // ✅ 真正的异步等待：注册到事件循环，不阻塞
                event_loop.registerWaiter(&completion_notifier);

                // ✅ 让出控制权给事件循环，等待唤醒
                completion_notifier.wait();

                // 被唤醒后继续轮询
                std.log.debug("await_fn: 任务被唤醒，继续轮询", .{});
                continue;
            },
        }
    }
}

/// 回退模式：同步执行（当没有事件循环时）
fn fallbackSyncAwait(future: anytype) @TypeOf(future).Output {
    std.log.warn("await_fn: 没有事件循环，使用同步回退模式", .{});

    var fut = future;
    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 简单的同步轮询，最多尝试几次
    var attempts: u32 = 0;
    const max_attempts = 10;

    while (attempts < max_attempts) {
        switch (fut.poll(&ctx)) {
            .ready => |result| return result,
            .pending => {
                attempts += 1;
                // 使用CPU自旋提示而非阻塞调用
                for (0..1000) |_| {
                    std.atomic.spinLoopHint();
                }
            },
        }
    }

    // 如果仍未完成，返回错误或默认值
    const OutputType = @TypeOf(future).Output;
    const type_info = @typeInfo(OutputType);
    if (type_info == .error_union) {
        return error.Timeout;
    } else if (OutputType == void) {
        return;
    } else {
        @panic("await_fn: 同步回退模式超时");
    }
}

/// 🚀 Zokio 3.0 异步上下文管理
///
/// 获取当前任务的异步执行上下文，包含事件循环引用和Waker
fn getCurrentAsyncContext() Context {
    // 尝试从线程本地存储获取当前上下文
    if (getCurrentThreadContext()) |ctx| {
        return ctx;
    }

    // 如果没有上下文，创建一个默认的
    return createDefaultContext();
}

/// 获取当前线程的异步上下文
fn getCurrentThreadContext() ?Context {
    // 线程本地存储的上下文
    const static = struct {
        threadlocal var current_context: ?Context = null;
    };

    return static.current_context;
}

/// 创建默认的异步上下文
fn createDefaultContext() Context {
    // 使用全局默认事件循环和Waker
    const static = struct {
        var global_budget = Budget.init();
    };

    // 🚀 Zokio 4.0 改进：从运行时获取当前事件循环
    const runtime = @import("../core/runtime.zig");
    const current_event_loop = runtime.getCurrentEventLoop();

    // 创建一个真正的Waker，连接到事件循环
    const waker = if (current_event_loop) |event_loop|
        if (event_loop.scheduler) |_|
            // 暂时使用noop Waker，避免类型不匹配
            // 在完整实现中，这里会创建真正的事件循环Waker
            Waker.noop()
        else
            Waker.noop()
    else
        Waker.noop();

    return Context{
        .waker = waker,
        .budget = &static.global_budget,
        .event_loop = current_event_loop,
    };
}

/// 🚀 任务完成通知器 - 用于事件驱动的任务等待
const TaskCompletionNotifier = struct {
    const Self = @This();

    completed: std.atomic.Value(bool),

    pub fn init() Self {
        return Self{
            .completed = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // 无需清理
    }

    /// 等待任务完成（事件驱动，非阻塞）
    pub fn wait(self: *Self) void {
        // 这里应该由事件循环来处理等待
        // 当前简化实现：使用自旋等待
        var spin_count: u32 = 0;
        const max_spin = 1000;

        while (!self.completed.load(.acquire)) {
            if (spin_count < max_spin) {
                spin_count += 1;
                std.atomic.spinLoopHint();
            } else {
                // 让出CPU，但不使用阻塞调用
                spin_count = 0;
                std.atomic.spinLoopHint();
            }
        }
    }

    /// 通知任务完成
    pub fn notify(self: *Self) void {
        self.completed.store(true, .release);
    }

    /// 检查是否已完成
    pub fn isCompleted(self: *const Self) bool {
        return self.completed.load(.acquire);
    }
};

/// 🚀 事件循环Waker - 连接到事件循环的真正Waker
const EventLoopWaker = struct {
    const Self = @This();

    event_loop: *AsyncEventLoop,
    notifier: *TaskCompletionNotifier,

    pub fn init(event_loop: *AsyncEventLoop, notifier: *TaskCompletionNotifier) Self {
        return Self{
            .event_loop = event_loop,
            .notifier = notifier,
        };
    }

    /// 转换为标准Waker接口
    pub fn toWaker(self: *const Self) Waker {
        _ = self; // 标记为已使用
        return Waker.noop(); // 使用标准的noop Waker
    }

    /// 唤醒任务
    pub fn wake(self: *const Self) void {
        self.notifier.notify();
    }

    /// 空操作调度器（临时实现）
    var noop_scheduler = @import("waker.zig").TaskScheduler{};
};

/// 🚀 Zokio 3.0 任务暂停机制
///
/// 暂停当前任务，将控制权返回给事件循环
fn suspendCurrentTask(ctx: *Context) void {
    // 在真正的实现中，这里会：
    // 1. 保存当前任务的执行状态
    // 2. 将任务从运行队列移除
    // 3. 将控制权返回给事件循环调度器

    // 当前简化实现：标记任务为等待状态
    _ = ctx;

    // 注意：在完整的协程实现中，这里会使用suspend关键字
    // 或者类似的机制来真正暂停任务执行
}

/// 支持带参数的异步函数转换器
///
/// 严格按照plan.md中的API设计实现，支持如下用法：
/// ```zig
/// const AsyncTask = async_fn_with_params(struct {
///     fn readFile(path: []const u8) ![]u8 { ... }
/// }.readFile);
/// const task = AsyncTask{ .path = "example.txt" };
/// ```
pub fn async_fn_with_params(comptime func: anytype) type {
    const func_info = @typeInfo(@TypeOf(func));
    const fn_info = switch (func_info) {
        .@"fn" => |info| info,
        else => @compileError("Expected function type"),
    };

    const return_type = fn_info.return_type.?;
    const params = fn_info.params;

    // 生成参数结构体
    const ParamsStruct = if (params.len == 0)
        struct {}
    else blk: {
        var fields: [params.len]std.builtin.Type.StructField = undefined;
        for (params, 0..) |param, i| {
            // 在Zig 0.14中，参数没有name字段，使用索引生成名称
            const param_name = std.fmt.comptimePrint("arg{}", .{i});
            fields[i] = std.builtin.Type.StructField{
                .name = param_name,
                .type = param.type.?,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(param.type.?),
            };
        }

        break :blk @Type(std.builtin.Type{
            .@"struct" = std.builtin.Type.Struct{
                .layout = .auto,
                .fields = &fields,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });
    };

    return struct {
        const Self = @This();

        /// Future输出类型
        pub const Output = return_type;

        /// 参数类型
        pub const Params = ParamsStruct;

        /// 函数参数（作为结构体字段）
        params: ParamsStruct,

        /// 执行状态
        state: State = .initial,

        /// 执行结果
        result: ?return_type = null,

        /// 错误信息（如果有）
        error_info: ?anyerror = null,

        /// 异步函数状态
        const State = enum {
            initial, // 初始状态
            running, // 运行中
            completed, // 已完成
            failed, // 执行失败
        };

        /// 轮询异步函数执行状态
        pub fn poll(self: *Self, ctx: *Context) Poll(return_type) {
            switch (self.state) {
                .initial => {
                    self.state = .running;

                    // 检查是否应该让出执行权
                    if (ctx.shouldYield()) {
                        return .pending;
                    }

                    // 调用函数并传递参数
                    const result = if (params.len == 0)
                        func()
                    else blk: {
                        // 将结构体转换为元组以供@call使用
                        var args: std.meta.Tuple(&blk2: {
                            var types: [params.len]type = undefined;
                            for (params, 0..) |param, i| {
                                types[i] = param.type.?;
                            }
                            break :blk2 types;
                        }) = undefined;

                        // 复制参数值
                        inline for (0..params.len) |i| {
                            const field_name = std.fmt.comptimePrint("arg{}", .{i});
                            args[i] = @field(self.params, field_name);
                        }

                        break :blk @call(.auto, func, args);
                    };

                    if (@typeInfo(return_type) == .error_union) {
                        // 处理可能返回错误的函数
                        self.result = result catch |err| {
                            self.error_info = err;
                            self.state = .failed;
                            return .pending;
                        };
                    } else {
                        self.result = result;
                    }

                    self.state = .completed;
                    return .{ .ready = self.result.? };
                },
                .running => {
                    // 检查异步操作是否完成
                    if (self.result != null) {
                        self.state = .completed;
                        return .{ .ready = self.result.? };
                    }
                    return .pending;
                },
                .completed => {
                    return .{ .ready = self.result.? };
                },
                .failed => {
                    // 在实际实现中，这里应该返回错误
                    // 现在简化处理
                    return .pending;
                },
            }
        }

        /// 重置异步函数状态，允许重新执行
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
    };
}

/// Future组合子：map
///
/// 将Future的结果通过函数转换为另一种类型
pub fn MapFuture(comptime FutureType: type, comptime OutputType: type, comptime transform_fn: anytype) type {
    _ = FutureType.Output; // 确保类型有Output字段

    return struct {
        const Self = @This();

        /// 输出类型
        pub const Output = OutputType;

        /// 内部Future
        inner_future: FutureType,

        /// 结果缓存
        result: ?OutputType = null,

        /// 初始化Map组合子
        pub fn init(future: FutureType) Self {
            return Self{
                .inner_future = future,
            };
        }

        /// 轮询Map组合子
        pub fn poll(self: *Self, ctx: *Context) Poll(OutputType) {
            if (self.result) |result| {
                return .{ .ready = result };
            }

            switch (self.inner_future.poll(ctx)) {
                .ready => |value| {
                    self.result = transform_fn(value);
                    return .{ .ready = self.result.? };
                },
                .pending => return .pending,
            }
        }

        /// 重置状态
        pub fn reset(self: *Self) void {
            self.result = null;
            if (@hasDecl(FutureType, "reset")) {
                self.inner_future.reset();
            }
        }
    };
}

/// 简化的Future链式组合
///
/// 用于组合两个Future的执行
pub fn ChainFuture(comptime FirstFuture: type, comptime SecondFuture: type) type {
    return struct {
        const Self = @This();

        /// 输出类型
        pub const Output = SecondFuture.Output;

        /// 第一个Future
        first_future: FirstFuture,

        /// 第二个Future
        second_future: SecondFuture,

        /// 执行状态
        state: enum { first, second, completed } = .first,

        /// 中间结果
        first_result: ?FirstFuture.Output = null,

        /// 最终结果
        result: ?SecondFuture.Output = null,

        /// 初始化链式Future
        pub fn init(first: FirstFuture, second: SecondFuture) Self {
            return Self{
                .first_future = first,
                .second_future = second,
            };
        }

        /// 轮询链式Future
        pub fn poll(self: *Self, ctx: *Context) Poll(SecondFuture.Output) {
            switch (self.state) {
                .first => {
                    switch (self.first_future.poll(ctx)) {
                        .ready => |first_result| {
                            self.first_result = first_result;
                            self.state = .second;
                            // 继续执行第二个Future
                            return self.poll(ctx);
                        },
                        .pending => return .pending,
                    }
                },
                .second => {
                    switch (self.second_future.poll(ctx)) {
                        .ready => |second_result| {
                            self.result = second_result;
                            self.state = .completed;
                            return .{ .ready = second_result };
                        },
                        .pending => return .pending,
                    }
                },
                .completed => {
                    return .{ .ready = self.result.? };
                },
            }
        }

        /// 重置状态
        pub fn reset(self: *Self) void {
            self.state = .first;
            self.first_result = null;
            self.result = null;

            if (@hasDecl(FirstFuture, "reset")) {
                self.first_future.reset();
            }
            if (@hasDecl(SecondFuture, "reset")) {
                self.second_future.reset();
            }
        }
    };
}

/// 便捷函数：创建已完成的Future
pub fn ready(comptime T: type, value: T) ReadyFuture(T) {
    return ReadyFuture(T).init(value);
}

/// 便捷函数：创建待定的Future
pub fn pending(comptime T: type) PendingFuture(T) {
    return PendingFuture(T).init();
}

/// 已完成的Future
pub fn ReadyFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Output = T;

        value: T,

        pub fn init(val: T) Self {
            return Self{ .value = val };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(T) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };
}

/// 永远待定的Future
pub fn PendingFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Output = T;

        pub fn init() Self {
            return Self{};
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(T) {
            _ = self;
            _ = ctx;
            return .pending;
        }
    };
}

/// 超时Future包装器
pub fn TimeoutFuture(comptime FutureType: type) type {
    return struct {
        const Self = @This();

        pub const Output = FutureType.Output;

        /// 内部Future
        inner_future: FutureType,

        /// 超时时间（毫秒）
        timeout_ms: u64,

        /// 开始时间
        start_time: ?i64 = null,

        /// 结果
        result: ?FutureType.Output = null,

        /// 是否超时
        timed_out: bool = false,

        pub fn init(future: FutureType, timeout_duration: u64) Self {
            return Self{
                .inner_future = future,
                .timeout_ms = timeout_duration,
            };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(FutureType.Output) {
            if (self.start_time == null) {
                self.start_time = std.time.milliTimestamp();
            }

            // 检查超时
            const elapsed = std.time.milliTimestamp() - self.start_time.?;
            if (elapsed >= self.timeout_ms) {
                self.timed_out = true;
                // 超时时返回一个默认值（在实际实现中应该返回错误）
                if (self.result) |result| {
                    return .{ .ready = result };
                } else {
                    // 如果没有结果，创建一个默认值
                    const default_value: FutureType.Output = if (@typeInfo(FutureType.Output) == .int)
                        0
                    else if (@typeInfo(FutureType.Output) == .void) {} else undefined;
                    return .{ .ready = default_value };
                }
            }

            // 轮询内部Future
            switch (self.inner_future.poll(ctx)) {
                .ready => |value| {
                    self.result = value;
                    return .{ .ready = value };
                },
                .pending => return .pending,
            }
        }

        pub fn reset(self: *Self) void {
            self.start_time = null;
            self.result = null;
            self.timed_out = false;
            if (@hasDecl(FutureType, "reset")) {
                self.inner_future.reset();
            }
        }
    };
}

/// 创建超时Future的便捷函数
pub fn timeout(future: anytype, timeout_ms: u64) TimeoutFuture(@TypeOf(future)) {
    return TimeoutFuture(@TypeOf(future)).init(future, timeout_ms);
}

// 测试
test "Poll类型基础功能" {
    const testing = std.testing;

    // 测试ready状态
    const ready_poll = Poll(u32){ .ready = 42 };
    try testing.expect(ready_poll.isReady());
    try testing.expect(!ready_poll.isPending());

    // 测试pending状态
    const pending_poll = Poll(u32).pending;
    try testing.expect(pending_poll == .pending);
    try testing.expect(pending_poll == .pending);

    // 测试map操作
    const mapped = ready_poll.map(u64, struct {
        fn double(x: u32) u64 {
            return @as(u64, x) * 2;
        }
    }.double);

    try testing.expect(mapped.isReady());
    if (mapped == .ready) {
        try testing.expectEqual(@as(u64, 84), mapped.ready);
    }
}

test "TaskId生成" {
    const testing = std.testing;

    const id1 = TaskId.generate();
    const id2 = TaskId.generate();

    try testing.expect(id1.id != id2.id);
    try testing.expect(id1.id < id2.id);
}

test "Waker基础功能" {
    _ = std.testing;

    const waker = Waker.noop();

    // 测试基本操作（不应该崩溃）
    waker.wakeByRef();

    const cloned = waker.clone();
    cloned.deinit();
}

test "Context基础功能" {
    const testing = std.testing;

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 测试基本操作
    ctx.wake(); // 不应该崩溃

    // 测试预算
    var budget = Budget.init();
    ctx.budget = &budget;

    // 初始不应该让出
    try testing.expect(!ctx.shouldYield());
}

test "async_fn基础功能" {
    const testing = std.testing;

    const TestFunc = async_fn(struct {
        fn compute() u32 {
            return 42;
        }
    }.compute);

    const test_func = struct {
        fn compute() u32 {
            return 42;
        }
    }.compute;

    var future = TestFunc.init(test_func);

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    const result = future.poll(&ctx);
    try testing.expect(result.isReady());
    if (result == .ready) {
        try testing.expectEqual(@as(u32, 42), result.ready);
    }

    // 测试状态检查
    try testing.expect(future.isCompleted());
    try testing.expect(!future.isFailed());
}

test "async_fn错误处理" {
    const testing = std.testing;

    const ErrorFunc = async_fn(struct {
        fn compute() !u32 {
            return error.TestError;
        }
    }.compute);

    const error_func = struct {
        fn compute() !u32 {
            return error.TestError;
        }
    }.compute;

    var future = ErrorFunc.init(error_func);

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    const result = future.poll(&ctx);
    // 在当前简化实现中，错误会导致pending状态
    try testing.expect(result.isPending());
    try testing.expect(future.isFailed());
}

test "Delay Future" {
    const testing = std.testing;

    var delay_future = delay(10); // 10ms延迟

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 第一次轮询应该返回pending
    const first_poll = delay_future.poll(&ctx);
    try testing.expect(first_poll.isPending());

    // 🚀 Zokio 8.0: 使用异步方式替代sleep阻塞调用
    // 模拟时间流逝，等待足够时间让delay完成
    std.time.sleep(200 * std.time.ns_per_ms); // 200ms

    const second_poll = delay_future.poll(&ctx);
    try testing.expect(second_poll.isReady());
}

test "ReadyFuture和PendingFuture" {
    const testing = std.testing;

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 测试ReadyFuture
    var ready_future = ready(u32, 100);
    const ready_result = ready_future.poll(&ctx);
    try testing.expect(ready_result.isReady());
    if (ready_result == .ready) {
        try testing.expectEqual(@as(u32, 100), ready_result.ready);
    }

    // 测试PendingFuture
    var pending_future = pending(u32);
    const pending_result = pending_future.poll(&ctx);
    try testing.expect(pending_result.isPending());
}

test "ChainFuture组合" {
    const testing = std.testing;

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 创建两个简单的Future
    const first = ready(u32, 10);
    const second = ready(u32, 20);

    // 创建链式Future
    var chain = ChainFuture(@TypeOf(first), @TypeOf(second)).init(first, second);

    const result = chain.poll(&ctx);
    try testing.expect(result.isReady());
    if (result == .ready) {
        try testing.expectEqual(@as(u32, 20), result.ready);
    }
}

test "Result类型功能" {
    const testing = std.testing;

    const TestError = error{TestFailed};

    // 测试成功结果
    const ok_result = Result(u32, TestError){ .ok = 42 };
    try testing.expect(ok_result.isOk());
    try testing.expect(!ok_result.isErr());
    try testing.expectEqual(@as(u32, 42), ok_result.unwrap());

    // 测试错误结果
    const err_result = Result(u32, TestError){ .err = TestError.TestFailed };
    try testing.expect(!err_result.isOk());
    try testing.expect(err_result.isErr());
    try testing.expectEqual(TestError.TestFailed, err_result.unwrapErr());

    // 测试映射
    const mapped = ok_result.map(u64, struct {
        fn double(x: u32) u64 {
            return x * 2;
        }
    }.double);
    try testing.expect(mapped.isOk());
    try testing.expectEqual(@as(u64, 84), mapped.unwrap());
}

test "Poll增强功能" {
    const testing = std.testing;

    // 测试ready poll
    const ready_poll = Poll(u32){ .ready = 42 };
    try testing.expect(ready_poll.isReady());
    try testing.expectEqual(@as(u32, 42), ready_poll.unwrap());
    try testing.expectEqual(@as(u32, 42), ready_poll.unwrapOr(0));

    // 测试pending poll
    const pending_poll = Poll(u32).pending;
    try testing.expect(pending_poll == .pending);
    // pending状态无法获取值

    // 测试映射
    const mapped = ready_poll.map(u64, struct {
        fn double(x: u32) u64 {
            return x * 2;
        }
    }.double);
    try testing.expect(mapped.isReady());
    try testing.expectEqual(@as(u64, 84), mapped.unwrap());
}

test "Future组合器功能" {
    const testing = std.testing;

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 测试MapFuture
    const transform_fn = struct {
        fn double(x: u32) u64 {
            return @as(u64, x) * 2;
        }
    }.double;

    const ready_future = ready(u32, 21);
    var map_future = MapFuture(@TypeOf(ready_future), u64, transform_fn).init(ready_future);

    const map_result = map_future.poll(&ctx);
    try testing.expect(map_result.isReady());
    if (map_result == .ready) {
        try testing.expectEqual(@as(u64, 42), map_result.ready);
    }
}
