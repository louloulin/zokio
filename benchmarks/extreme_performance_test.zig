const std = @import("std");
const zokio = @import("zokio");

/// 🚀 极致性能Zokio vs Tokio对比测试
/// 使用最新的优化功能和极致性能配置
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 Zokio极致性能测试 ===\n\n", .{});

    // 🔥 使用极致性能配置
    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    std.debug.print("🔧 运行时配置:\n", .{});
    std.debug.print("  配置名称: {s}\n", .{zokio.runtime.HighPerformanceRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("  工作线程: {}\n", .{zokio.runtime.HighPerformanceRuntime.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("  I/O后端: {s}\n", .{zokio.runtime.HighPerformanceRuntime.COMPILE_TIME_INFO.io_backend});
    std.debug.print("  libxev启用: {}\n", .{zokio.runtime.HighPerformanceRuntime.LIBXEV_ENABLED});
    std.debug.print("  内存策略: {s}\n", .{zokio.runtime.HighPerformanceRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("\n", .{});

    // 🚀 测试1: 极致性能spawn测试
    try testExtremeSpawnPerformance(&runtime, allocator);

    // 🚀 测试2: 高并发async_fn测试
    try testHighConcurrencyAsyncFn(&runtime, allocator);

    // 🚀 测试3: 真实I/O性能测试
    try testRealIOPerformance(&runtime, allocator);

    // 🚀 测试4: CPU密集型任务测试
    try testCPUIntensivePerformance(&runtime, allocator);

    std.debug.print("\n=== 🎉 极致性能测试完成 ===\n", .{});
}

// 🔥 简单的计算任务
const ComputeTask = struct {
    value: u32,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        // 简单计算任务
        const result = self.value * 2 + 1;
        return zokio.Poll(Self.Output){ .ready = result };
    }
};

/// 🚀 极致性能spawn测试
fn testExtremeSpawnPerformance(runtime: *zokio.runtime.HighPerformanceRuntime, allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试1: 极致性能spawn测试\n", .{});

    const task_count = 10000; // 减少任务数量避免过长等待
    const start_time = std.time.nanoTimestamp();

    // 创建大量并发任务
    var handles = std.ArrayList(zokio.runtime.JoinHandle(u32)).init(allocator);
    defer handles.deinit();

    for (0..task_count) |i| {
        const task = ComputeTask{ .value = @as(u32, @intCast(i)) };
        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // 等待所有任务完成
    var total_result: u64 = 0;
    for (handles.items) |*handle| {
        const result = try handle.join();
        total_result += result;
        handle.deinit();
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(task_count)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0);

    std.debug.print("  ✓ 完成 {} 个并发任务\n", .{task_count});
    std.debug.print("  ✓ 总结果: {}\n", .{total_result});
    std.debug.print("  ✓ 耗时: {d:.2f}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0f} ops/sec\n", .{ops_per_sec});
    std.debug.print("\n", .{});
}

/// 🚀 高并发async_fn测试
fn testHighConcurrencyAsyncFn(runtime: *zokio.runtime.HighPerformanceRuntime, allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试2: 高并发async_fn测试\n", .{});

    const task_count = 50000;
    const start_time = std.time.nanoTimestamp();

    // 创建复杂的异步任务
    var handles = std.ArrayList(zokio.runtime.JoinHandle([]const u8)).init(allocator);
    defer handles.deinit();

    for (0..task_count) |i| {
        const task = zokio.async_fn(struct {
            fn complexAsyncTask(id: u32) []const u8 {
                // 模拟复杂异步操作
                if (id % 3 == 0) {
                    return "{'type': 'database', 'result': 'success'}";
                } else if (id % 3 == 1) {
                    return "{'type': 'network', 'result': 'completed'}";
                } else {
                    return "{'type': 'file', 'result': 'processed'}";
                }
            }
        }.complexAsyncTask, .{@as(u32, @intCast(i))});

        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // 等待所有任务完成
    var success_count: u32 = 0;
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        if (std.mem.indexOf(u8, result, "success") != null or
            std.mem.indexOf(u8, result, "completed") != null or
            std.mem.indexOf(u8, result, "processed") != null)
        {
            success_count += 1;
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(task_count)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0);

    std.debug.print("  ✓ 完成 {} 个复杂异步任务\n", .{task_count});
    std.debug.print("  ✓ 成功任务: {}\n", .{success_count});
    std.debug.print("  ✓ 耗时: {d:.2f}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0f} ops/sec\n", .{ops_per_sec});
    std.debug.print("\n", .{});
}

/// 🚀 真实I/O性能测试
fn testRealIOPerformance(runtime: *zokio.runtime.HighPerformanceRuntime, allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试3: 真实I/O性能测试\n", .{});

    const io_count = 1000;
    const start_time = std.time.nanoTimestamp();

    // 创建真实I/O任务
    var handles = std.ArrayList(zokio.runtime.JoinHandle(bool)).init(allocator);
    defer handles.deinit();

    for (0..io_count) |i| {
        const task = zokio.async_fn(struct {
            fn ioTask(id: u32) bool {
                // 模拟真实I/O操作
                const filename = std.fmt.allocPrint(std.heap.page_allocator, "temp_file_{}.txt", .{id}) catch return false;
                defer std.heap.page_allocator.free(filename);

                // 写入文件
                const file = std.fs.cwd().createFile(filename, .{}) catch return false;
                defer file.close();
                defer std.fs.cwd().deleteFile(filename) catch {};

                const data = "Hello, Zokio extreme performance test!";
                _ = file.writeAll(data) catch return false;

                return true;
            }
        }.ioTask, .{@as(u32, @intCast(i))});

        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // 等待所有I/O任务完成
    var success_count: u32 = 0;
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        if (result) success_count += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(io_count)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0);

    std.debug.print("  ✓ 完成 {} 个真实I/O操作\n", .{io_count});
    std.debug.print("  ✓ 成功操作: {}\n", .{success_count});
    std.debug.print("  ✓ 耗时: {d:.2f}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0f} ops/sec (真实I/O)\n", .{ops_per_sec});
    std.debug.print("\n", .{});
}

/// 🚀 CPU密集型任务测试
fn testCPUIntensivePerformance(runtime: *zokio.runtime.HighPerformanceRuntime, allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试4: CPU密集型任务测试\n", .{});

    const task_count = 100;
    const iterations_per_task = 100000;
    const start_time = std.time.nanoTimestamp();

    // 创建CPU密集型任务
    var handles = std.ArrayList(zokio.runtime.JoinHandle(u64)).init(allocator);
    defer handles.deinit();

    for (0..task_count) |i| {
        const task = zokio.async_fn(struct {
            fn cpuIntensiveTask(task_id: u32, iterations: u32) u64 {
                var result: u64 = 0;
                var j: u32 = 0;
                while (j < iterations) : (j += 1) {
                    // CPU密集型计算
                    result += @as(u64, task_id) * @as(u64, j) + @as(u64, j * j);
                }
                return result;
            }
        }.cpuIntensiveTask, .{ @as(u32, @intCast(i)), iterations_per_task });

        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // 等待所有CPU任务完成
    var total_result: u64 = 0;
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        total_result += result;
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const total_iterations = task_count * iterations_per_task;
    const iterations_per_sec = @as(f64, @floatFromInt(total_iterations)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0);

    std.debug.print("  ✓ 完成 {} 个CPU密集型任务\n", .{task_count});
    std.debug.print("  ✓ 总迭代: {}\n", .{total_iterations});
    std.debug.print("  ✓ 总结果: {}\n", .{total_result});
    std.debug.print("  ✓ 耗时: {d:.2f}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0f} iterations/sec (CPU密集型)\n", .{iterations_per_sec});
    std.debug.print("\n", .{});
}
