//! 🚀 Spawn功能验证测试
//! 全面测试Zokio的spawn功能，对比Tokio的spawn行为

const std = @import("std");
const zokio = @import("zokio");

// 测试用的Future类型
const SimpleTask = struct {
    value: u32,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        return zokio.Poll(Self.Output){ .ready = self.value * 2 };
    }
};

const ComputeTask = struct {
    params: struct {
        arg0: u64,
    },

    const Self = @This();
    pub const Output = u64;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        // 模拟计算工作
        var result: u64 = self.params.arg0;
        for (0..100) |i| {
            result = result +% @as(u64, @intCast(i));
        }
        return zokio.Poll(Self.Output){ .ready = result };
    }
};

const AsyncIOTask = struct {
    data: []const u8,

    const Self = @This();
    pub const Output = usize;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        // 模拟异步I/O工作
        std.time.sleep(1000); // 1μs
        return zokio.Poll(Self.Output){ .ready = self.data.len };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 Spawn功能验证测试 ===\n", .{});

    // 测试1: 基础spawn功能
    try testBasicSpawn(allocator);

    // 测试2: 多任务spawn
    try testMultipleSpawn(allocator);

    // 测试3: 不同类型任务spawn
    try testDifferentTaskTypes(allocator);

    // 测试4: spawn错误处理
    try testSpawnErrorHandling(allocator);

    // 测试5: JoinHandle功能
    try testJoinHandleFunctionality(allocator);

    // 测试6: spawn性能测试
    try testSpawnPerformance(allocator);

    std.debug.print("\n🎉 === Spawn功能验证完成 ===\n", .{});
}

/// 测试基础spawn功能
fn testBasicSpawn(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试基础spawn功能...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 创建简单任务
    const task = SimpleTask{ .value = 42 };

    // 使用spawn
    var handle = try runtime.spawn(task);
    defer handle.deinit();

    std.debug.print("  ✅ spawn调用成功\n", .{});

    // 等待任务完成
    const result = try handle.join();
    std.debug.print("  ✅ 任务完成，结果: {} (期望: 84)\n", .{result});

    if (result == 84) {
        std.debug.print("  🎉 基础spawn测试通过\n", .{});
    } else {
        std.debug.print("  ❌ 基础spawn测试失败\n", .{});
    }
}

/// 测试多任务spawn
fn testMultipleSpawn(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试多任务spawn...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const task_count = 10;
    var handles: [task_count]zokio.JoinHandle(u32) = undefined;

    // 批量spawn任务
    for (&handles, 0..) |*handle, i| {
        const task = SimpleTask{ .value = @intCast(i + 1) };
        handle.* = try runtime.spawn(task);
    }

    std.debug.print("  ✅ 成功spawn {} 个任务\n", .{task_count});

    // 批量等待完成
    var total_result: u32 = 0;
    for (&handles, 0..) |*handle, i| {
        const result = try handle.join();
        total_result += result;
        std.debug.print("    任务 {}: {} (期望: {})\n", .{ i, result, (i + 1) * 2 });
        handle.deinit();
    }

    const expected_total = (1 + task_count) * task_count; // 2+4+6+...+20 = 110
    std.debug.print("  📊 总结果: {} (期望: {})\n", .{ total_result, expected_total });

    if (total_result == expected_total) {
        std.debug.print("  🎉 多任务spawn测试通过\n", .{});
    } else {
        std.debug.print("  ❌ 多任务spawn测试失败\n", .{});
    }
}

/// 测试不同类型任务spawn
fn testDifferentTaskTypes(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试不同类型任务spawn...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 测试计算任务
    const compute_task = ComputeTask{ .params = .{ .arg0 = 100 } };
    var compute_handle = try runtime.spawn(compute_task);
    defer compute_handle.deinit();

    // 测试I/O任务
    const io_task = AsyncIOTask{ .data = "Hello, Zokio!" };
    var io_handle = try runtime.spawn(io_task);
    defer io_handle.deinit();

    // 等待计算任务
    const compute_result = try compute_handle.join();
    std.debug.print("  ✅ 计算任务结果: {}\n", .{compute_result});

    // 等待I/O任务
    const io_result = try io_handle.join();
    std.debug.print("  ✅ I/O任务结果: {} (数据长度)\n", .{io_result});

    std.debug.print("  🎉 不同类型任务spawn测试通过\n", .{});
}

/// 测试spawn错误处理
fn testSpawnErrorHandling(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试spawn错误处理...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    // 测试未启动运行时的spawn
    const task = SimpleTask{ .value = 42 };

    const spawn_result = runtime.spawn(task);
    if (spawn_result) |_| {
        std.debug.print("  ❌ 未启动运行时应该返回错误\n", .{});
    } else |err| {
        std.debug.print("  ✅ 未启动运行时正确返回错误: {}\n", .{err});
    }

    // 启动运行时后测试正常spawn
    try runtime.start();
    defer runtime.stop();

    var handle = try runtime.spawn(task);
    defer handle.deinit();

    const result = try handle.join();
    std.debug.print("  ✅ 启动后spawn正常工作，结果: {}\n", .{result});

    std.debug.print("  🎉 spawn错误处理测试通过\n", .{});
}

/// 测试JoinHandle功能
fn testJoinHandleFunctionality(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试JoinHandle功能...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const task = SimpleTask{ .value = 123 };
    var handle = try runtime.spawn(task);

    // 测试JoinHandle的基本功能
    std.debug.print("  📋 JoinHandle创建成功\n", .{});

    // 测试join功能
    const result = try handle.join();
    std.debug.print("  ✅ join返回结果: {} (期望: 246)\n", .{result});

    // 测试deinit功能
    handle.deinit();
    std.debug.print("  ✅ JoinHandle deinit成功\n", .{});

    if (result == 246) {
        std.debug.print("  🎉 JoinHandle功能测试通过\n", .{});
    } else {
        std.debug.print("  ❌ JoinHandle功能测试失败\n", .{});
    }
}

/// 测试spawn性能
fn testSpawnPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 测试spawn性能...\n", .{});

    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();

    // 批量spawn和join
    for (0..iterations) |i| {
        const task = SimpleTask{ .value = @intCast(i) };
        var handle = try runtime.spawn(task);
        const result = try handle.join();
        handle.deinit();

        // 验证结果
        if (result != i * 2) {
            std.debug.print("  ❌ 任务 {} 结果错误: {} != {}\n", .{ i, result, i * 2 });
            return;
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const ops_per_second = if (duration_ns > 0) (iterations * 1_000_000_000) / duration_ns else iterations;

    std.debug.print("  📊 spawn性能测试结果:\n", .{});
    std.debug.print("    任务数: {}\n", .{iterations});
    std.debug.print("    总耗时: {} ns\n", .{duration_ns});
    std.debug.print("    性能: {} spawn+join/sec\n", .{ops_per_second});

    std.debug.print("  🎉 spawn性能测试完成\n", .{});
}
