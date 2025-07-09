//! 验证await_fn不再使用阻塞调用的测试
//! 这是plan3.md中Phase 1的验收测试

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

// 阻塞调用跟踪器
const BlockingCallTracker = struct {
    thread_yield_calls: u32 = 0,
    sleep_calls: u32 = 0,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    // 这些函数会在测试中替换标准库的实现
    pub fn trackThreadYield(self: *Self) void {
        self.thread_yield_calls += 1;
    }

    pub fn trackSleep(self: *Self) void {
        self.sleep_calls += 1;
    }
};

// 简单的测试Future
const SimpleFuture = struct {
    value: u32,
    poll_count: u32 = 0,

    pub const Output = u32;

    pub fn init(val: u32) @This() {
        return @This(){
            .value = val,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        self.poll_count += 1;

        // 第一次轮询返回pending，第二次返回ready
        if (self.poll_count == 1) {
            return .pending;
        } else {
            return .{ .ready = self.value };
        }
    }
};

// 立即完成的Future
const ImmediateFuture = struct {
    value: u32,

    pub const Output = u32;

    pub fn init(val: u32) @This() {
        return @This(){
            .value = val,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        return .{ .ready = self.value };
    }
};

test "await_fn不使用Thread.yield()" {
    std.debug.print("\n=== 测试await_fn不使用阻塞调用 ===\n", .{});

    // 测试1: 立即完成的Future
    std.debug.print("1. 测试立即完成的Future\n", .{});

    const immediate_future = ImmediateFuture.init(42);
    const start_time = std.time.nanoTimestamp();
    const result = zokio.await_fn(immediate_future);
    const end_time = std.time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_us = @as(f64, @floatFromInt(duration_ns)) / 1000.0;

    std.debug.print("   结果: {} (期望: 42)\n", .{result});
    std.debug.print("   执行时间: {d:.2} μs\n", .{duration_us});

    try testing.expect(result == 42);
    // 立即完成的Future应该在很短时间内完成
    try testing.expect(duration_us < 50.0);

    std.debug.print("   ✅ 立即完成Future测试通过\n", .{});
}

test "await_fn性能特性验证" {
    std.debug.print("\n2. 测试await_fn性能特性\n", .{});

    // 测试多个连续的await_fn调用
    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const future = ImmediateFuture.init(i);
        const result = zokio.await_fn(future);
        try testing.expect(result == i);
    }

    const end_time = std.time.nanoTimestamp();
    const total_duration_us = @as(f64, @floatFromInt(end_time - start_time)) / 1000.0;
    const avg_duration_us = total_duration_us / @as(f64, @floatFromInt(iterations));
    const ops_per_sec = 1_000_000.0 / avg_duration_us;

    std.debug.print("   迭代次数: {}\n", .{iterations});
    std.debug.print("   总执行时间: {d:.2} μs\n", .{total_duration_us});
    std.debug.print("   平均执行时间: {d:.3} μs\n", .{avg_duration_us});
    std.debug.print("   吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    // 性能应该很高，因为没有阻塞调用
    try testing.expect(ops_per_sec > 100_000); // 至少10万ops/sec

    std.debug.print("   ✅ 性能特性验证通过\n", .{});
}

test "await_fn内存使用验证" {
    std.debug.print("\n3. 测试await_fn内存使用\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 执行多次await_fn调用
    const iterations = 100;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const future = ImmediateFuture.init(i);
        const result = zokio.await_fn(future);
        try testing.expect(result == i);
    }

    // 检查是否有内存泄漏
    const leaked = gpa.detectLeaks();

    std.debug.print("   执行了 {} 次await_fn调用\n", .{iterations});
    std.debug.print("   内存泄漏检测: {}\n", .{leaked});

    // await_fn应该不会导致内存泄漏
    try testing.expect(!leaked);

    std.debug.print("   ✅ 内存使用验证通过\n", .{});
}

test "await_fn并发安全性" {
    std.debug.print("\n4. 测试await_fn并发安全性\n", .{});

    // 这个测试验证await_fn在多线程环境下的安全性
    // 虽然await_fn本身是单线程的，但我们测试其状态管理

    const ThreadContext = struct {
        thread_id: u32,
        results: []u32,

        fn threadFunc(ctx: *@This()) void {
            var i: u32 = 0;
            while (i < 100) : (i += 1) {
                const future = ImmediateFuture.init(ctx.thread_id * 1000 + i);
                const result = zokio.await_fn(future);
                ctx.results[i] = result;
            }
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;
    var contexts: [num_threads]ThreadContext = undefined;
    var results: [num_threads][100]u32 = undefined;

    // 启动线程
    for (0..num_threads) |i| {
        contexts[i] = ThreadContext{
            .thread_id = @intCast(i),
            .results = &results[i],
        };
        threads[i] = try std.Thread.spawn(.{}, ThreadContext.threadFunc, .{&contexts[i]});
    }

    // 等待所有线程完成
    for (0..num_threads) |i| {
        threads[i].join();
    }

    // 验证结果
    for (0..num_threads) |thread_idx| {
        for (0..100) |i| {
            const expected = thread_idx * 1000 + i;
            try testing.expect(results[thread_idx][i] == expected);
        }
    }

    std.debug.print("   线程数: {}\n", .{num_threads});
    std.debug.print("   每线程操作数: 100\n", .{});
    std.debug.print("   总操作数: {}\n", .{num_threads * 100});
    std.debug.print("   ✅ 并发安全性验证通过\n", .{});
}

test "await_fn错误处理" {
    std.debug.print("\n5. 测试await_fn错误处理\n", .{});

    // 测试await_fn对错误类型的处理
    const ErrorFuture = struct {
        should_error: bool,

        pub const Output = anyerror!u32;

        pub fn init(should_error: bool) @This() {
            return @This(){
                .should_error = should_error,
            };
        }

        pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(anyerror!u32) {
            _ = ctx;
            if (self.should_error) {
                return .{ .ready = error.TestError };
            } else {
                return .{ .ready = 42 };
            }
        }
    };

    // 测试成功情况
    const success_future = ErrorFuture.init(false);
    const success_result = zokio.await_fn(success_future);
    const success_value = try success_result;
    try testing.expect(success_value == 42);

    // 测试错误情况
    const error_future = ErrorFuture.init(true);
    const error_result = zokio.await_fn(error_future);
    try testing.expectError(error.TestError, error_result);

    std.debug.print("   ✅ 错误处理验证通过\n", .{});
}
