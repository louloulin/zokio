//! await_fn和async_fn压力测试
//!
//! 测试async/await在高负载下的性能表现

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== await_fn和async_fn压力测试 ===\n\n", .{});

    // 初始化高性能运行时
    var runtime = try zokio.SimpleRuntime.init(allocator);
    defer runtime.deinit();
    try runtime.start();

    // 压力测试1: 基础await_fn性能
    try benchmarkBasicAwaitFn(&runtime);

    // 压力测试2: 嵌套await_fn性能
    try benchmarkNestedAwaitFn(&runtime);

    // 压力测试3: 大量并发async_fn
    try benchmarkConcurrentAsyncFn(&runtime);

    // 压力测试4: 深度嵌套链性能
    try benchmarkDeepNestedChain(&runtime);

    // 压力测试5: 混合负载压力测试
    try benchmarkMixedWorkload(&runtime);

    std.debug.print("\n=== 压力测试完成 ===\n", .{});
}

/// 压力测试1: 基础await_fn性能
fn benchmarkBasicAwaitFn(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("1. 基础await_fn性能压测\n", .{});

    const AsyncSimpleTask = zokio.future.async_fn_with_params(struct {
        fn simpleTask(value: u32) u32 {
            // 模拟轻量级计算
            return value * 2;
        }
    }.simpleTask);

    const iterations = 100000;
    std.debug.print("  ⏳ 执行 {} 次基础await_fn调用...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    // 创建大量基础await_fn调用
    const BasicAwaitBench = zokio.future.async_block(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                const result = zokio.future.await_fn(AsyncSimpleTask{ .params = .{ .arg0 = i } });
                total += result;
                i += 1;
            }
            return total;
        }
    }.execute);

    const bench_block = BasicAwaitBench.init(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                const result = zokio.future.await_fn(AsyncSimpleTask{ .params = .{ .arg0 = i } });
                total += result;
                i += 1;
            }
            return total;
        }
    }.execute);

    const result = try runtime.blockOn(bench_block);
    const end_time = std.time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("  ✓ 完成 {} 次调用，总结果: {}\n", .{ iterations, result });
    std.debug.print("  ✓ 耗时: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0} ops/sec\n", .{ops_per_sec});
}

/// 压力测试2: 嵌套await_fn性能
fn benchmarkNestedAwaitFn(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n2. 嵌套await_fn性能压测\n", .{});

    const AsyncStep1 = zokio.future.async_fn_with_params(struct {
        fn step1(value: u32) u32 {
            return value + 1;
        }
    }.step1);

    const AsyncStep2 = zokio.future.async_fn_with_params(struct {
        fn step2(value: u32) u32 {
            return value * 2;
        }
    }.step2);

    const AsyncStep3 = zokio.future.async_fn_with_params(struct {
        fn step3(value: u32) u32 {
            return value - 1;
        }
    }.step3);

    const iterations = 50000;
    std.debug.print("  ⏳ 执行 {} 次嵌套await_fn调用...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    const NestedAwaitBench = zokio.future.async_block(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                const step1_result = zokio.future.await_fn(AsyncStep1{ .params = .{ .arg0 = i } });
                const step2_result = zokio.future.await_fn(AsyncStep2{ .params = .{ .arg0 = step1_result } });
                const step3_result = zokio.future.await_fn(AsyncStep3{ .params = .{ .arg0 = step2_result } });
                total += step3_result;
                i += 1;
            }
            return total;
        }
    }.execute);

    const nested_block = NestedAwaitBench.init(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                const step1_result = zokio.future.await_fn(AsyncStep1{ .params = .{ .arg0 = i } });
                const step2_result = zokio.future.await_fn(AsyncStep2{ .params = .{ .arg0 = step1_result } });
                const step3_result = zokio.future.await_fn(AsyncStep3{ .params = .{ .arg0 = step2_result } });
                total += step3_result;
                i += 1;
            }
            return total;
        }
    }.execute);

    const result = try runtime.blockOn(nested_block);
    const end_time = std.time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations * 3)) / (duration_ms / 1000.0); // 3个await_fn调用

    std.debug.print("  ✓ 完成 {} 次嵌套调用，总结果: {}\n", .{ iterations, result });
    std.debug.print("  ✓ 耗时: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0} ops/sec (包含嵌套)\n", .{ops_per_sec});
}

/// 压力测试3: 大量并发async_fn
fn benchmarkConcurrentAsyncFn(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n3. 大量并发async_fn压测\n", .{});

    const AsyncConcurrentTask = zokio.future.async_fn_with_params(struct {
        fn concurrentTask(task_id: u32) u32 {
            // 模拟一些计算工作
            var result: u32 = task_id;
            var i: u32 = 0;
            while (i < 100) {
                result = (result * 31 + i) % 1000000;
                i += 1;
            }
            return result;
        }
    }.concurrentTask);

    const concurrent_tasks = 10000;
    std.debug.print("  ⏳ 执行 {} 个并发async_fn任务...\n", .{concurrent_tasks});

    const start_time = std.time.nanoTimestamp();

    const ConcurrentBench = zokio.future.async_block(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < concurrent_tasks) {
                const result = zokio.future.await_fn(AsyncConcurrentTask{ .params = .{ .arg0 = i } });
                total = (total + result) % 1000000; // 防止溢出
                i += 1;
            }
            return total;
        }
    }.execute);

    const concurrent_block = ConcurrentBench.init(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < concurrent_tasks) {
                const result = zokio.future.await_fn(AsyncConcurrentTask{ .params = .{ .arg0 = i } });
                total = (total + result) % 1000000; // 防止溢出
                i += 1;
            }
            return total;
        }
    }.execute);

    const result = try runtime.blockOn(concurrent_block);
    const end_time = std.time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(concurrent_tasks)) / (duration_ms / 1000.0);

    std.debug.print("  ✓ 完成 {} 个并发任务，总结果: {}\n", .{ concurrent_tasks, result });
    std.debug.print("  ✓ 耗时: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0} ops/sec\n", .{ops_per_sec});
}

/// 压力测试4: 深度嵌套链性能
fn benchmarkDeepNestedChain(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n4. 深度嵌套链性能压测\n", .{});

    // 定义深度嵌套的异步函数链
    const AsyncLevel1 = zokio.future.async_fn_with_params(struct {
        fn level1(value: u32) u32 { return value + 1; }
    }.level1);

    const AsyncLevel2 = zokio.future.async_fn_with_params(struct {
        fn level2(value: u32) u32 { return value * 2; }
    }.level2);

    const AsyncLevel3 = zokio.future.async_fn_with_params(struct {
        fn level3(value: u32) u32 { return value + 3; }
    }.level3);

    const AsyncLevel4 = zokio.future.async_fn_with_params(struct {
        fn level4(value: u32) u32 { return value * 4; }
    }.level4);

    const AsyncLevel5 = zokio.future.async_fn_with_params(struct {
        fn level5(value: u32) u32 { return value + 5; }
    }.level5);

    const iterations = 20000;
    std.debug.print("  ⏳ 执行 {} 次深度嵌套链调用...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    const DeepNestedBench = zokio.future.async_block(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                const level1_result = zokio.future.await_fn(AsyncLevel1{ .params = .{ .arg0 = i } });
                const level2_result = zokio.future.await_fn(AsyncLevel2{ .params = .{ .arg0 = level1_result } });
                const level3_result = zokio.future.await_fn(AsyncLevel3{ .params = .{ .arg0 = level2_result } });
                const level4_result = zokio.future.await_fn(AsyncLevel4{ .params = .{ .arg0 = level3_result } });
                const level5_result = zokio.future.await_fn(AsyncLevel5{ .params = .{ .arg0 = level4_result } });
                total = (total + level5_result) % 1000000; // 防止溢出
                i += 1;
            }
            return total;
        }
    }.execute);

    const deep_block = DeepNestedBench.init(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                const level1_result = zokio.future.await_fn(AsyncLevel1{ .params = .{ .arg0 = i } });
                const level2_result = zokio.future.await_fn(AsyncLevel2{ .params = .{ .arg0 = level1_result } });
                const level3_result = zokio.future.await_fn(AsyncLevel3{ .params = .{ .arg0 = level2_result } });
                const level4_result = zokio.future.await_fn(AsyncLevel4{ .params = .{ .arg0 = level3_result } });
                const level5_result = zokio.future.await_fn(AsyncLevel5{ .params = .{ .arg0 = level4_result } });
                total = (total + level5_result) % 1000000; // 防止溢出
                i += 1;
            }
            return total;
        }
    }.execute);

    const result = try runtime.blockOn(deep_block);
    const end_time = std.time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations * 5)) / (duration_ms / 1000.0); // 5层嵌套

    std.debug.print("  ✓ 完成 {} 次深度嵌套调用，总结果: {}\n", .{ iterations, result });
    std.debug.print("  ✓ 耗时: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0} ops/sec (5层嵌套)\n", .{ops_per_sec});
}

/// 压力测试5: 混合负载压力测试
fn benchmarkMixedWorkload(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n5. 混合负载压力测试\n", .{});

    // 定义不同类型的异步任务
    const AsyncFastTask = zokio.future.async_fn_with_params(struct {
        fn fastTask(value: u32) u32 {
            return value + 1;
        }
    }.fastTask);

    const AsyncMediumTask = zokio.future.async_fn_with_params(struct {
        fn mediumTask(value: u32) u32 {
            var result = value;
            var i: u32 = 0;
            while (i < 50) {
                result = (result * 17 + i) % 100000;
                i += 1;
            }
            return result;
        }
    }.mediumTask);

    const AsyncSlowTask = zokio.future.async_fn_with_params(struct {
        fn slowTask(value: u32) u32 {
            var result = value;
            var i: u32 = 0;
            while (i < 200) {
                result = (result * 23 + i) % 100000;
                i += 1;
            }
            return result;
        }
    }.slowTask);

    const iterations = 30000;
    std.debug.print("  ⏳ 执行 {} 次混合负载测试...\n", .{iterations});

    const start_time = std.time.nanoTimestamp();

    const MixedWorkloadBench = zokio.future.async_block(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                // 混合不同类型的任务
                const task_type = i % 3;
                const result = switch (task_type) {
                    0 => zokio.future.await_fn(AsyncFastTask{ .params = .{ .arg0 = i } }),
                    1 => zokio.future.await_fn(AsyncMediumTask{ .params = .{ .arg0 = i } }),
                    2 => zokio.future.await_fn(AsyncSlowTask{ .params = .{ .arg0 = i } }),
                    else => unreachable,
                };
                total = (total + result) % 1000000;
                i += 1;
            }
            return total;
        }
    }.execute);

    const mixed_block = MixedWorkloadBench.init(struct {
        fn execute() u32 {
            var total: u32 = 0;
            var i: u32 = 0;
            while (i < iterations) {
                // 混合不同类型的任务
                const task_type = i % 3;
                const result = switch (task_type) {
                    0 => zokio.future.await_fn(AsyncFastTask{ .params = .{ .arg0 = i } }),
                    1 => zokio.future.await_fn(AsyncMediumTask{ .params = .{ .arg0 = i } }),
                    2 => zokio.future.await_fn(AsyncSlowTask{ .params = .{ .arg0 = i } }),
                    else => unreachable,
                };
                total = (total + result) % 1000000;
                i += 1;
            }
            return total;
        }
    }.execute);

    const result = try runtime.blockOn(mixed_block);
    const end_time = std.time.nanoTimestamp();

    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("  ✓ 完成 {} 次混合负载测试，总结果: {}\n", .{ iterations, result });
    std.debug.print("  ✓ 耗时: {d:.2}ms\n", .{duration_ms});
    std.debug.print("  ✓ 性能: {d:.0} ops/sec\n", .{ops_per_sec});

    // 显示运行时统计
    const stats = runtime.getStats();
    std.debug.print("  📊 运行时统计:\n", .{});
    std.debug.print("    - 总任务数: {}\n", .{stats.total_tasks});
    std.debug.print("    - 线程数: {}\n", .{stats.thread_count});
    std.debug.print("    - 运行状态: {}\n", .{stats.running});
}
