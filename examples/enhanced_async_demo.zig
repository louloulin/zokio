//! 增强的async/await功能演示
//!
//! 展示Zokio第二阶段实现的完整async/await支持

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    std.debug.print("=== Zokio 增强的async/await功能演示 ===\n", .{});

    // 演示1：基础async/await功能
    try demonstrateBasicAsyncAwait();

    // 演示2：错误处理
    try demonstrateErrorHandling();

    // 演示3：Future组合器
    try demonstrateFutureCombinators();

    // 演示4：Result类型
    try demonstrateResultType();

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

/// 演示基础async/await功能
fn demonstrateBasicAsyncAwait() !void {
    std.debug.print("\n1. 基础async/await功能演示\n", .{});

    // 创建async函数
    const AsyncCompute = zokio.future.async_fn(struct {
        fn compute() u32 {
            return 42;
        }
    }.compute);

    const compute_func = struct {
        fn compute() u32 {
            return 42;
        }
    }.compute;

    var async_task = AsyncCompute.init(compute_func);

    // 创建执行上下文
    const waker = zokio.future.Waker.noop();
    var ctx = zokio.future.Context.init(waker);

    // 轮询执行
    const result = async_task.poll(&ctx);
    switch (result) {
        .ready => |value| {
            std.debug.print("   异步计算结果: {}\n", .{value});
            std.debug.print("   任务状态: 已完成\n", .{});
        },
        .pending => {
            std.debug.print("   任务状态: 等待中\n", .{});
        },
    }

    // 检查状态
    std.debug.print("   isCompleted: {}\n", .{async_task.isCompleted()});
    std.debug.print("   isFailed: {}\n", .{async_task.isFailed()});
}

/// 演示错误处理
fn demonstrateErrorHandling() !void {
    std.debug.print("\n2. 错误处理演示\n", .{});

    const TestError = error{ComputationFailed};

    // 创建会失败的async函数
    const AsyncErrorFunc = zokio.future.async_fn(struct {
        fn compute() TestError!u32 {
            return TestError.ComputationFailed;
        }
    }.compute);

    const error_func = struct {
        fn compute() TestError!u32 {
            return TestError.ComputationFailed;
        }
    }.compute;

    var async_task = AsyncErrorFunc.init(error_func);

    const waker = zokio.future.Waker.noop();
    var ctx = zokio.future.Context.init(waker);

    // 轮询执行
    const result = async_task.poll(&ctx);
    switch (result) {
        .ready => |value| {
            std.debug.print("   意外的成功结果: {any}\n", .{value});
        },
        .pending => {
            std.debug.print("   任务状态: 等待中（错误处理）\n", .{});
        },
    }

    // 检查错误状态
    std.debug.print("   isCompleted: {}\n", .{async_task.isCompleted()});
    std.debug.print("   isFailed: {}\n", .{async_task.isFailed()});
    if (async_task.isFailed()) {
        std.debug.print("   任务执行失败\n", .{});
    }
}

/// 演示Future组合器
fn demonstrateFutureCombinators() !void {
    std.debug.print("\n3. Future组合器演示\n", .{});

    const waker = zokio.future.Waker.noop();
    var ctx = zokio.future.Context.init(waker);

    // 创建基础Future
    const ready_future = zokio.future.ready(u32, 21);
    std.debug.print("   创建Ready Future，值: 21\n", .{});

    // 使用Map组合器
    const transform_fn = struct {
        fn double(x: u32) u64 {
            return @as(u64, x) * 2;
        }
    }.double;

    var map_future = zokio.future.MapFuture(@TypeOf(ready_future), u64, transform_fn).init(ready_future);
    const map_result = map_future.poll(&ctx);

    switch (map_result) {
        .ready => |value| {
            std.debug.print("   Map变换结果: {} -> {}\n", .{ 21, value });
        },
        .pending => {
            std.debug.print("   Map变换: 等待中\n", .{});
        },
    }

    // 演示超时Future
    const delay_future = zokio.future.delay(10); // 10ms延迟
    var timeout_future = zokio.future.TimeoutFuture(@TypeOf(delay_future)).init(delay_future, 50); // 50ms超时

    std.debug.print("   创建超时Future（10ms延迟，50ms超时）\n", .{});

    // 第一次轮询应该pending
    const timeout_result1 = timeout_future.poll(&ctx);
    switch (timeout_result1) {
        .ready => std.debug.print("   超时Future: 意外完成\n", .{}),
        .pending => std.debug.print("   超时Future: 等待中\n", .{}),
    }

    // 等待一段时间后再次轮询
    std.time.sleep(15 * std.time.ns_per_ms);
    const timeout_result2 = timeout_future.poll(&ctx);
    switch (timeout_result2) {
        .ready => std.debug.print("   超时Future: 已完成\n", .{}),
        .pending => std.debug.print("   超时Future: 仍在等待\n", .{}),
    }
}

/// 演示Result类型
fn demonstrateResultType() !void {
    std.debug.print("\n4. Result类型演示\n", .{});

    const TestError = error{ProcessingFailed};

    // 成功的Result
    const ok_result = zokio.future.Result(u32, TestError){ .ok = 100 };
    std.debug.print("   成功Result: isOk={}, 值={}\n", .{ ok_result.isOk(), ok_result.unwrap() });

    // 失败的Result
    const err_result = zokio.future.Result(u32, TestError){ .err = TestError.ProcessingFailed };
    std.debug.print("   失败Result: isErr={}, 错误={any}\n", .{ err_result.isErr(), err_result.unwrapErr() });

    // Result映射
    const mapped_result = ok_result.map(u64, struct {
        fn triple(x: u32) u64 {
            return @as(u64, x) * 3;
        }
    }.triple);

    if (mapped_result.isOk()) {
        std.debug.print("   映射结果: {} -> {}\n", .{ 100, mapped_result.unwrap() });
    }

    // Result链式操作
    const chained_result = ok_result.andThen(u64, struct {
        fn process(x: u32) zokio.future.Result(u64, TestError) {
            if (x > 50) {
                return .{ .ok = @as(u64, x) * 2 };
            } else {
                return .{ .err = TestError.ProcessingFailed };
            }
        }
    }.process);

    if (chained_result.isOk()) {
        std.debug.print("   链式操作结果: {}\n", .{chained_result.unwrap()});
    }
}
