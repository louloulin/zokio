//! 🔍 真实异步验证测试
//! 验证Zokio的异步运行是否是真正的异步，而不是模拟的

const std = @import("std");
const zokio = @import("zokio");

// 简单的延迟任务 - 用于验证异步性
const DelayTask = struct {
    delay_ms: u64,
    task_id: u32,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;

        // 🔥 真实的延迟操作
        std.time.sleep(self.delay_ms * std.time.ns_per_ms);

        return zokio.Poll(Self.Output){ .ready = self.task_id };
    }
};

// 真实的CPU密集型任务
const CPUIntensiveTask = struct {
    iterations: u64,

    const Self = @This();
    pub const Output = u64;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;

        // 🔥 真实的CPU密集型计算
        var result: u64 = 1;
        for (0..self.iterations) |i| {
            result = result *% (@as(u64, @intCast(i)) + 1);
            result = result ^ (result >> 1);
            result = result +% 0x123456789ABCDEF0;
        }

        return zokio.Poll(Self.Output){ .ready = result };
    }
};

// 真实的网络模拟任务（使用sleep模拟网络延迟）
const NetworkTask = struct {
    delay_ms: u64,
    data_size: usize,

    const Self = @This();
    pub const Output = usize;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;

        // 🔥 模拟真实的网络延迟
        std.time.sleep(self.delay_ms * std.time.ns_per_ms);

        // 🔥 模拟数据传输
        var checksum: usize = 0;
        for (0..self.data_size) |i| {
            checksum = checksum +% i;
        }

        return zokio.Poll(Self.Output){ .ready = checksum };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🔍 真实异步验证测试 ===\n", .{});

    // 测试1: 并发延迟验证
    try testConcurrentDelay(allocator);

    // 测试2: 真实性能对比
    try testRealPerformanceComparison(allocator);

    std.debug.print("\n🎉 === 真实异步验证完成 ===\n", .{});
}

/// 测试并发延迟 - 验证真实异步
fn testConcurrentDelay(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试并发延迟验证...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const start_time = std.time.nanoTimestamp();

    // 🔥 创建少量延迟任务（减少并发复杂性）
    const task_count = 2;
    var handles: [task_count]zokio.JoinHandle(u32) = undefined;

    for (&handles, 0..) |*handle, i| {
        const task = DelayTask{
            .delay_ms = 10, // 每个任务延迟10ms
            .task_id = @as(u32, @intCast(i)),
        };

        handle.* = try runtime.spawn(task);
        std.debug.print("  ⏰ 启动延迟任务 {}: 10ms\n", .{i});
    }

    // 🔥 等待所有任务完成
    var completed_tasks: u32 = 0;
    for (&handles, 0..) |*handle, i| {
        const result = try handle.join();
        completed_tasks += 1;
        handle.deinit();
        std.debug.print("  ✅ 延迟任务 {} 完成: ID={}\n", .{ i, result });
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / std.time.ns_per_ms;

    std.debug.print("  📊 并发延迟结果:\n", .{});
    std.debug.print("    任务数: {}\n", .{task_count});
    std.debug.print("    完成任务数: {}\n", .{completed_tasks});
    std.debug.print("    总耗时: {d:.2} ms\n", .{duration_ms});
    std.debug.print("    平均每任务: {d:.2} ms\n", .{duration_ms / task_count});

    // 🔍 分析：如果是真实异步，总时间应该接近单个任务时间，而不是所有任务时间之和
    const expected_sequential_time = 10.0 * task_count; // 每个任务10ms
    const concurrency_ratio = expected_sequential_time / duration_ms;

    std.debug.print("  🔍 异步分析:\n", .{});
    std.debug.print("    预期顺序执行时间: {d:.2} ms\n", .{expected_sequential_time});
    std.debug.print("    实际并发执行时间: {d:.2} ms\n", .{duration_ms});
    std.debug.print("    并发效率: {d:.2}x\n", .{concurrency_ratio});

    if (concurrency_ratio > 2.0) {
        std.debug.print("  🎉 验证结果: 真实异步执行！\n", .{});
    } else {
        std.debug.print("  ⚠️ 验证结果: 可能是顺序执行\n", .{});
    }
}

/// 测试真实性能对比 - 异步 vs 同步
fn testRealPerformanceComparison(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试真实性能对比...\n", .{});

    // 🔥 异步执行测试
    const async_time = try measureAsyncExecution(allocator);

    // 🔥 同步执行测试
    const sync_time = try measureSyncExecution(allocator);

    std.debug.print("  📊 性能对比结果:\n", .{});
    std.debug.print("    异步执行时间: {d:.2} ms\n", .{async_time});
    std.debug.print("    同步执行时间: {d:.2} ms\n", .{sync_time});

    if (sync_time > async_time) {
        const speedup = sync_time / async_time;
        std.debug.print("    异步加速比: {d:.2}x\n", .{speedup});
        std.debug.print("  🎉 验证结果: 异步执行更快！\n", .{});
    } else {
        std.debug.print("  ⚠️ 验证结果: 同步执行更快或相当\n", .{});
    }
}

/// 测量异步执行时间
fn measureAsyncExecution(allocator: std.mem.Allocator) !f64 {
    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const start_time = std.time.nanoTimestamp();

    // 创建多个延迟任务
    const task_count = 3;
    var handles: [task_count]zokio.JoinHandle(u32) = undefined;

    for (&handles, 0..) |*handle, i| {
        const task = DelayTask{
            .delay_ms = 5,
            .task_id = @as(u32, @intCast(i)),
        };
        handle.* = try runtime.spawn(task);
    }

    // 等待完成
    for (&handles) |*handle| {
        _ = try handle.join();
        handle.deinit();
    }

    const end_time = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(end_time - start_time)) / std.time.ns_per_ms;
}

/// 测量同步执行时间
fn measureSyncExecution(allocator: std.mem.Allocator) !f64 {
    _ = allocator;

    const start_time = std.time.nanoTimestamp();

    // 同步执行相同的任务
    const task_count = 3;
    for (0..task_count) |_| {
        // 模拟网络延迟
        std.time.sleep(5 * std.time.ns_per_ms);

        // 模拟数据处理
        var checksum: usize = 0;
        for (0..100) |i| {
            checksum = checksum +% i;
        }
        std.debug.assert(checksum > 0); // 使用checksum避免编译器警告
    }

    const end_time = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(end_time - start_time)) / std.time.ns_per_ms;
}
