//! 🚀 真正使用Zokio核心API的压测
//!
//! 使用真实的async_fn、await_fn、spawn等核心API进行压测
//! 而不是mock实现

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 真正的Zokio核心API压测 ===\n\n", .{});

    // 测试1: async_fn + spawn 压测
    try benchmarkAsyncFnWithSpawn(allocator);

    // 测试2: await_fn 嵌套压测
    try benchmarkNestedAwaitFn(allocator);

    // 测试3: 大量并发spawn压测
    try benchmarkMassiveSpawn(allocator);

    // 测试4: 混合API压测
    try benchmarkMixedAPI(allocator);

    std.debug.print("\n=== 🎉 真实API压测完成 ===\n", .{});
}

/// 测试1: async_fn + spawn 压测
fn benchmarkAsyncFnWithSpawn(allocator: std.mem.Allocator) !void {
    std.debug.print("🔥 测试1: async_fn + spawn 压测\n", .{});

    // 创建高性能运行时
    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    try runtime.start();
    defer runtime.stop();

    // 🚀 定义真正的async_fn
    const ComputeTask = zokio.async_fn_with_params(struct {
        fn compute(task_id: u32) u64 {
            var sum: u64 = 0;
            var i: u32 = 0;
            while (i < 1000) : (i += 1) {
                sum = sum +% (task_id + i);
            }
            return sum;
        }
    }.compute);

    const iterations = 10000;
    const start_time = std.time.nanoTimestamp();

    std.debug.print("  📊 使用spawn创建 {} 个async_fn任务...\n", .{iterations});

    // 🚀 使用真正的spawn API
    const handles = try allocator.alloc(zokio.JoinHandle(u64), iterations);
    defer allocator.free(handles);

    // 批量spawn任务
    for (handles, 0..) |*handle, i| {
        const task = ComputeTask{
            .params = .{ .arg0 = @intCast(i) }
        };

        handle.* = try runtime.spawn(task);
    }

    std.debug.print("  ⏳ 等待所有任务完成...\n", .{});

    // 🚀 使用真正的join API等待完成
    var completed: u64 = 0;
    var total_result: u64 = 0;
    for (handles) |*handle| {
        const result = try handle.join();
        total_result = total_result +% result;
        completed += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  ✅ 完成任务: {}\n", .{completed});
    std.debug.print("  ⏱️ 耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  📈 吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  🔢 总结果: {}\n", .{total_result});

    if (ops_per_sec > 50_000.0) {
        std.debug.print("  🚀 async_fn + spawn 性能优异\n", .{});
    } else {
        std.debug.print("  ⚠️ 性能需要优化\n", .{});
    }
}

/// 测试2: await_fn 嵌套压测
fn benchmarkNestedAwaitFn(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试2: await_fn 嵌套压测\n", .{});

    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    try runtime.start();
    defer runtime.stop();

    // 🚀 定义嵌套的async_fn
    const Step1 = zokio.async_fn_with_params(struct {
        fn step1(value: u32) u32 {
            return value + 100;
        }
    }.step1);

    const Step2 = zokio.async_fn_with_params(struct {
        fn step2(value: u32) u32 {
            return value * 2;
        }
    }.step2);

    const Step3 = zokio.async_fn_with_params(struct {
        fn step3(value: u32) u32 {
            return value - 50;
        }
    }.step3);

    // 🚀 使用真正的await_fn嵌套
    const NestedWorkflow = zokio.async_block(struct {
        fn execute() u32 {
            const step1_result = zokio.await_fn(Step1{ .params = .{ .arg0 = 42 } });
            const step2_result = zokio.await_fn(Step2{ .params = .{ .arg0 = step1_result } });
            const step3_result = zokio.await_fn(Step3{ .params = .{ .arg0 = step2_result } });
            return step3_result;
        }
    }.execute);

    const iterations = 5000;
    const start_time = std.time.nanoTimestamp();

    std.debug.print("  📊 执行 {} 次嵌套await_fn工作流...\n", .{iterations});

    var completed: u64 = 0;
    var total_result: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const workflow = NestedWorkflow.init(struct {
            fn execute() u32 {
                const step1_result = zokio.await_fn(Step1{ .params = .{ .arg0 = 42 } });
                const step2_result = zokio.await_fn(Step2{ .params = .{ .arg0 = step1_result } });
                const step3_result = zokio.await_fn(Step3{ .params = .{ .arg0 = step2_result } });
                return step3_result;
            }
        }.execute);

        const result = try runtime.blockOn(workflow);
        total_result += result;
        completed += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  ✅ 完成工作流: {}\n", .{completed});
    std.debug.print("  ⏱️ 耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  📈 吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  🔢 总结果: {}\n", .{total_result});

    if (ops_per_sec > 20_000.0) {
        std.debug.print("  🚀 嵌套await_fn 性能优异\n", .{});
    } else {
        std.debug.print("  ⚠️ 性能需要优化\n", .{});
    }
}

/// 测试3: 大量并发spawn压测
fn benchmarkMassiveSpawn(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🌊 测试3: 大量并发spawn压测\n", .{});

    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    try runtime.start();
    defer runtime.stop();

    // 🚀 轻量级async_fn任务
    const LightTask = zokio.async_fn_with_params(struct {
        fn lightWork(id: u32) u32 {
            return id * 3 + 7;
        }
    }.lightWork);

    const iterations = 50000;
    const start_time = std.time.nanoTimestamp();

    std.debug.print("  📊 大量spawn {} 个轻量级任务...\n", .{iterations});

    // 🚀 大量spawn
    const handles = try allocator.alloc(zokio.JoinHandle(u32), iterations);
    defer allocator.free(handles);

    // 批量spawn
    for (handles, 0..) |*handle, i| {
        const task = LightTask{ .params = .{ .arg0 = @intCast(i) } };
        handle.* = try runtime.spawn(task);
    }

    // 批量join
    var completed: u64 = 0;
    var total_result: u64 = 0;
    for (handles) |*handle| {
        const result = try handle.join();
        total_result += result;
        completed += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  ✅ 完成任务: {}\n", .{completed});
    std.debug.print("  ⏱️ 耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  📈 吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  🔢 总结果: {}\n", .{total_result});

    if (ops_per_sec > 100_000.0) {
        std.debug.print("  🚀 大量spawn 性能优异\n", .{});
    } else {
        std.debug.print("  ⚠️ 性能需要优化\n", .{});
    }
}

/// 测试4: 混合API压测
fn benchmarkMixedAPI(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔀 测试4: 混合API压测\n", .{});

    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    try runtime.start();
    defer runtime.stop();

    // 🚀 混合使用所有API
    const MixedTask = zokio.async_fn_with_params(struct {
        fn mixedWork(base: u32) u32 {
            // 内部使用await_fn
            const SubTask = zokio.async_fn_with_params(struct {
                fn subWork(value: u32) u32 {
                    return value + 10;
                }
            }.subWork);

            const sub_result = zokio.await_fn(SubTask{ .params = .{ .arg0 = base } });
            return sub_result * 2;
        }
    }.mixedWork);

    const iterations = 8000;
    const start_time = std.time.nanoTimestamp();

    std.debug.print("  📊 混合API测试 {} 次...\n", .{iterations});

    // 混合使用spawn和blockOn
    const spawn_handles = try allocator.alloc(zokio.JoinHandle(u32), iterations / 2);
    defer allocator.free(spawn_handles);

    // 一半使用spawn
    for (spawn_handles, 0..) |*handle, i| {
        const task = MixedTask{ .params = .{ .arg0 = @intCast(i) } };
        handle.* = try runtime.spawn(task);
    }

    // 一半使用blockOn
    var blockOn_results: u64 = 0;
    var i: u32 = iterations / 2;
    while (i < iterations) : (i += 1) {
        const task = MixedTask{ .params = .{ .arg0 = i } };
        const result = try runtime.blockOn(task);
        blockOn_results += result;
    }

    // 等待spawn任务完成
    var spawn_results: u64 = 0;
    for (spawn_handles) |*handle| {
        const result = try handle.join();
        spawn_results += result;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    std.debug.print("  ✅ 完成任务: {}\n", .{iterations});
    std.debug.print("  ⏱️ 耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  📈 吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  🔢 spawn结果: {}\n", .{spawn_results});
    std.debug.print("  🔢 blockOn结果: {}\n", .{blockOn_results});

    if (ops_per_sec > 30_000.0) {
        std.debug.print("  🚀 混合API 性能优异\n", .{});
    } else {
        std.debug.print("  ⚠️ 性能需要优化\n", .{});
    }
}
