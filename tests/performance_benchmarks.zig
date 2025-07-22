//! 📊 Zokio 性能基准测试
//!
//! 这个文件包含了 Zokio 异步运行时的全面性能基准测试，
//! 用于验证和监控系统的性能表现。

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

// 导入核心组件
const Future = zokio.zokio.Future;
const Poll = zokio.zokio.Poll;
const Context = zokio.zokio.Context;
const await_fn = zokio.zokio.await_fn;
const async_fn = zokio.zokio.async_fn;
const Waker = @import("../src/core/future.zig").Waker;

/// 性能基准测试配置
const BenchmarkConfig = struct {
    iterations: u32 = 10000,
    warmup_iterations: u32 = 1000,
    target_ops_per_sec: u64 = 100_000,
};

/// 简单Future用于性能测试
const SimpleFuture = struct {
    value: u32,

    pub const Output = u32;

    pub fn init(val: u32) @This() {
        return @This(){ .value = val };
    }

    pub fn poll(self: *@This(), ctx: *Context) Poll(u32) {
        _ = ctx;
        return .{ .ready = self.value };
    }
};

// 测试Future创建性能
test "性能基准: Future创建" {
    const config = BenchmarkConfig{};

    // 预热
    for (0..config.warmup_iterations) |i| {
        const future = SimpleFuture.init(@intCast(i));
        _ = future;
    }

    // 实际测试
    const start_time = std.time.nanoTimestamp();

    for (0..config.iterations) |i| {
        const future = SimpleFuture.init(@intCast(i));
        _ = future;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const ops_per_sec = (@as(u64, config.iterations) * 1_000_000_000) / duration_ns;

    std.debug.print("Future创建性能: {} ops/sec\n", .{ops_per_sec});
    std.debug.print("平均延迟: {} ns\n", .{duration_ns / config.iterations});

    // 验证性能达标
    try testing.expect(ops_per_sec > config.target_ops_per_sec);
}

// 测试Waker调用性能
test "性能基准: Waker调用" {
    const config = BenchmarkConfig{};
    const waker = Waker.noop();

    // 预热
    for (0..config.warmup_iterations) |_| {
        waker.wake();
    }

    // 实际测试
    const start_time = std.time.nanoTimestamp();

    for (0..config.iterations) |_| {
        waker.wake();
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const ops_per_sec = (@as(u64, config.iterations) * 1_000_000_000) / duration_ns;

    std.debug.print("Waker调用性能: {} ops/sec\n", .{ops_per_sec});
    std.debug.print("平均延迟: {} ns\n", .{duration_ns / config.iterations});

    // 验证性能达标
    try testing.expect(ops_per_sec > config.target_ops_per_sec);
}

// 测试await_fn性能
test "性能基准: await_fn调用" {
    const config = BenchmarkConfig{ .iterations = 1000 }; // 减少迭代次数，因为await_fn相对较重

    // 🚀 设置运行时环境以启用真正的异步模式
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建并启动运行时以设置事件循环
    const runtime_config = zokio.zokio.RuntimeConfig{};
    var runtime = try zokio.zokio.Runtime(runtime_config).init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    std.debug.print("🔥 运行时已启动，事件循环已设置\n", .{});

    // 预热
    for (0..config.warmup_iterations / 10) |i| {
        const future = SimpleFuture.init(@intCast(i));
        const result = await_fn(future);
        _ = result;
    }

    // 实际测试
    const start_time = std.time.nanoTimestamp();

    for (0..config.iterations) |i| {
        const future = SimpleFuture.init(@intCast(i));
        const result = await_fn(future);
        try testing.expectEqual(@as(u32, @intCast(i)), result);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const ops_per_sec = (@as(u64, config.iterations) * 1_000_000_000) / duration_ns;

    std.debug.print("await_fn性能: {} ops/sec\n", .{ops_per_sec});
    std.debug.print("平均延迟: {} ns\n", .{duration_ns / config.iterations});

    // await_fn的性能目标相对较低，因为它包含更多逻辑
    try testing.expect(ops_per_sec > 10_000);
}

// 测试内存分配性能
test "性能基准: 内存分配" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BenchmarkConfig{};
    const allocation_size = 64; // 64字节分配

    // 预热
    for (0..config.warmup_iterations) |_| {
        const ptr = allocator.alloc(u8, allocation_size) catch continue;
        allocator.free(ptr);
    }

    // 实际测试
    const start_time = std.time.nanoTimestamp();

    for (0..config.iterations) |_| {
        const ptr = try allocator.alloc(u8, allocation_size);
        allocator.free(ptr);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const ops_per_sec = (@as(u64, config.iterations) * 1_000_000_000) / duration_ns;

    std.debug.print("内存分配性能: {} ops/sec\n", .{ops_per_sec});
    std.debug.print("平均延迟: {} ns\n", .{duration_ns / config.iterations});

    // 内存分配性能目标
    try testing.expect(ops_per_sec > 50_000);
}

// 综合性能基准测试
test "性能基准: 综合测试" {
    std.debug.print("\n=== Zokio 性能基准测试报告 ===\n", .{});
    std.debug.print("测试平台: {s}\n", .{@tagName(@import("builtin").target.os.tag)});
    std.debug.print("架构: {s}\n", .{@tagName(@import("builtin").target.cpu.arch)});
    std.debug.print("优化级别: {s}\n", .{@tagName(@import("builtin").mode)});
    std.debug.print("========================================\n", .{});

    // 运行所有基准测试
    // 注意：这里我们不能直接调用其他测试函数，
    // 但可以重复相同的测试逻辑来生成综合报告

    const config = BenchmarkConfig{};

    // Future创建测试
    {
        const start_time = std.time.nanoTimestamp();
        for (0..config.iterations) |i| {
            const future = SimpleFuture.init(@intCast(i));
            _ = future;
        }
        const end_time = std.time.nanoTimestamp();
        const duration_ns = @as(u64, @intCast(end_time - start_time));
        const ops_per_sec = (@as(u64, config.iterations) * 1_000_000_000) / duration_ns;
        std.debug.print("✅ Future创建: {} ops/sec\n", .{ops_per_sec});
    }

    // Waker调用测试
    {
        const waker = Waker.noop();
        const start_time = std.time.nanoTimestamp();
        for (0..config.iterations) |_| {
            waker.wake();
        }
        const end_time = std.time.nanoTimestamp();
        const duration_ns = @as(u64, @intCast(end_time - start_time));
        const ops_per_sec = (@as(u64, config.iterations) * 1_000_000_000) / duration_ns;
        std.debug.print("✅ Waker调用: {} ops/sec\n", .{ops_per_sec});
    }

    std.debug.print("========================================\n", .{});
    std.debug.print("🎉 所有性能基准测试完成！\n", .{});
}
