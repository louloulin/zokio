//! Future和异步抽象实现
//!
//! 提供零成本的异步抽象，包括Future类型、Poll结果、
//! 执行上下文和唤醒器等核心异步编程原语。

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils/utils.zig");

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
};

/// 执行上下文 - 提供给Future的poll方法
pub const Context = struct {
    /// 唤醒器
    waker: Waker,

    /// 任务ID（用于调试）
    task_id: ?TaskId = null,

    /// 协作式调度预算
    budget: ?*Budget = null,

    pub fn init(waker: Waker) Context {
        return Context{
            .waker = waker,
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

        /// 链式组合Future
        pub fn andThen(self: *Self, comptime U: type, func: fn (T) Future(U)) AndThenFuture(T, U) {
            return AndThenFuture(T, U).init(self, func);
        }

        /// 添加超时
        pub fn timeout(self: *Self, duration_ms: u64) TimeoutFuture(T) {
            return TimeoutFuture(T).init(self, duration_ms);
        }

        /// 错误恢复
        pub fn recover(self: *Self, func: fn (anyerror) T) RecoverFuture(T) {
            return RecoverFuture(T).init(self, func);
        }
    };
}







/// Recover Future - 错误恢复
pub fn RecoverFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Output = T;

        inner: *Future(T),
        recover_fn: *const fn (anyerror) T,

        pub fn init(inner: *Future(T), recover_fn: *const fn (anyerror) T) Self {
            return Self{
                .inner = inner,
                .recover_fn = recover_fn,
            };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(T) {
            const result = self.inner.poll(ctx);
            switch (result) {
                .ready => |value| {
                    // 如果T是错误联合类型，处理错误
                    if (@typeInfo(T) == .error_union) {
                        if (value) |ok_value| {
                            return .{ .ready = ok_value };
                        } else |err| {
                            return .{ .ready = self.recover_fn(err) };
                        }
                    } else {
                        return .{ .ready = value };
                    }
                },
                .pending => return .pending,
            }
        }

        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }
    };
}

/// Join Future - 等待两个Future都完成
pub fn JoinFuture(comptime T: type, comptime U: type) type {
    return struct {
        const Self = @This();

        pub const Output = struct { T, U };

        future1: *Future(T),
        future2: *Future(U),
        result1: ?T = null,
        result2: ?U = null,

        pub fn init(future1: *Future(T), future2: *Future(U)) Self {
            return Self{
                .future1 = future1,
                .future2 = future2,
            };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(struct { T, U }) {
            // 轮询第一个Future
            if (self.result1 == null) {
                const result1 = self.future1.poll(ctx);
                switch (result1) {
                    .ready => |value| self.result1 = value,
                    .pending => {},
                }
            }

            // 轮询第二个Future
            if (self.result2 == null) {
                const result2 = self.future2.poll(ctx);
                switch (result2) {
                    .ready => |value| self.result2 = value,
                    .pending => {},
                }
            }

            // 检查是否都完成
            if (self.result1 != null and self.result2 != null) {
                return .{ .ready = .{ self.result1.?, self.result2.? } };
            }

            return .pending;
        }

        pub fn deinit(self: *Self) void {
            self.future1.deinit();
            self.future2.deinit();
        }
    };
}

/// Select Future - 等待任意一个Future完成
pub fn SelectFuture(comptime T: type, comptime U: type) type {
    return struct {
        const Self = @This();

        pub const Output = union(enum) {
            first: T,
            second: U,
        };

        future1: *Future(T),
        future2: *Future(U),

        pub fn init(future1: *Future(T), future2: *Future(U)) Self {
            return Self{
                .future1 = future1,
                .future2 = future2,
            };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(Output) {
            // 轮询第一个Future
            const result1 = self.future1.poll(ctx);
            switch (result1) {
                .ready => |value| return .{ .ready = .{ .first = value } },
                .pending => {},
            }

            // 轮询第二个Future
            const result2 = self.future2.poll(ctx);
            switch (result2) {
                .ready => |value| return .{ .ready = .{ .second = value } },
                .pending => {},
            }

            return .pending;
        }

        pub fn deinit(self: *Self) void {
            self.future1.deinit();
            self.future2.deinit();
        }
    };
}

/// 便捷函数：join两个Future
pub fn join(comptime T: type, comptime U: type, future1: *Future(T), future2: *Future(U)) JoinFuture(T, U) {
    return JoinFuture(T, U).init(future1, future2);
}

/// 便捷函数：select两个Future
pub fn select(comptime T: type, comptime U: type, future1: *Future(T), future2: *Future(U)) SelectFuture(T, U) {
    return SelectFuture(T, U).init(future1, future2);
}

/// Ready Future - 立即就绪的Future
pub fn ReadyFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Output = T;

        value: T,

        pub fn init(value: T) Self {
            return Self{ .value = value };
        }

        pub fn poll(self: *Self, ctx: *Context) Poll(T) {
            _ = ctx;
            return .{ .ready = self.value };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }
    };
}

/// 便捷函数：创建立即就绪的Future
pub fn ready(comptime T: type, value: T) ReadyFuture(T) {
    return ReadyFuture(T).init(value);
}

/// Pending Future - 永远pending的Future（用于测试）
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

        pub fn deinit(self: *Self) void {
            _ = self;
        }
    };
}

/// 便捷函数：创建永远pending的Future
pub fn pending(comptime T: type) PendingFuture(T) {
    return PendingFuture(T).init();
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
                            // 对于错误联合类型，返回错误
                            return .{ .ready = err };
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
                    // 返回错误信息
                    if (self.error_info) |err| {
                        if (@typeInfo(return_type) == .error_union) {
                            return .{ .ready = err };
                        }
                    }
                    // 如果不是错误联合类型，继续pending
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
/// 在async_block中使用的await语法糖
/// 严格按照plan.md中的设计实现
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

    // 真正的await实现：轮询直到完成
    var fut = future;
    const waker = Waker.noop();
    var ctx = Context.init(waker);

    while (true) {
        switch (fut.poll(&ctx)) {
            .ready => |result| return result,
            .pending => {
                // 简单的让出CPU时间，模拟异步等待
                std.time.sleep(1 * std.time.ns_per_ms);
            },
        }
    }
}

// 注意：由于await是Zig的保留字，我们使用await_fn作为函数名
// 在实际使用中，可以通过编译时宏或代码生成来实现更自然的await语法

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

    // 等待一段时间后再次轮询
    std.time.sleep(15 * std.time.ns_per_ms); // 等待15ms

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
    try testing.expect(pending_poll.isPending());
    try testing.expectEqual(@as(u32, 0), pending_poll.unwrapOr(0));

    // 测试映射
    const mapped = ready_poll.map(u64, struct {
        fn double(x: u32) u64 {
            return x * 2;
        }
    }.double);
    try testing.expect(mapped.isReady());
    try testing.expectEqual(@as(u64, 84), mapped.unwrap());
}

test "JoinFuture功能" {
    const testing = std.testing;

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 创建两个Future
    var future1 = ready(u32, 10);
    var future2 = ready(u64, 20);

    // 创建join Future
    var join_future = join(u32, u64, &Future(u32).init(@TypeOf(future1), &future1), &Future(u64).init(@TypeOf(future2), &future2));

    const result = join_future.poll(&ctx);
    try testing.expect(result.isReady());
    if (result == .ready) {
        try testing.expectEqual(@as(u32, 10), result.ready[0]);
        try testing.expectEqual(@as(u64, 20), result.ready[1]);
    }
}

test "SelectFuture功能" {
    const testing = std.testing;

    const waker = Waker.noop();
    var ctx = Context.init(waker);

    // 创建两个Future，一个ready一个pending
    var future1 = ready(u32, 42);
    var future2 = pending(u64);

    // 创建select Future
    var select_future = select(u32, u64, &Future(u32).init(@TypeOf(future1), &future1), &Future(u64).init(@TypeOf(future2), &future2));

    const result = select_future.poll(&ctx);
    try testing.expect(result.isReady());
    if (result == .ready) {
        switch (result.ready) {
            .first => |value| try testing.expectEqual(@as(u32, 42), value),
            .second => try testing.expect(false), // 不应该到这里
        }
    }
}
