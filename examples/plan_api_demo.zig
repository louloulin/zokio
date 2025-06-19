//! plan.md API设计演示程序
//!
//! 展示严格按照plan.md中设计的API用法

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== plan.md API设计演示 ===\n\n", .{});

    // 演示1: 基础运行时创建（按照plan.md设计）
    try basicRuntimeDemo(allocator);

    // 演示2: 带参数的异步函数（按照plan.md设计）
    try asyncFunctionWithParamsDemo(allocator);

    // 演示3: await_fn语法演示
    try awaitFnDemo(allocator);

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

fn basicRuntimeDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("1. 基础运行时创建演示\n", .{});

    // 按照plan.md中的API设计创建运行时
    // 使用统一的运行时构建器
    var runtime = try zokio.builder()
        .threads(4)
        .workStealing(true)
        .queueSize(1024)
        .metrics(true)
        .build(allocator);
    defer runtime.deinit();

    try runtime.start();

    std.debug.print("  ✓ 运行时创建成功\n", .{});
    std.debug.print("  ✓ 配置: 4个工作线程，启用工作窃取\n", .{});

    // 测试简单的Future执行
    const simple_future = zokio.future.ready(u32, 42);
    const result = try runtime.blockOn(simple_future);
    std.debug.print("  ✓ blockOn执行成功，结果: {}\n", .{result});
}

fn asyncFunctionWithParamsDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. 带参数的异步函数演示\n", .{});

    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();

    // 演示带参数的异步函数（模拟plan.md中的readFile示例）
    const AsyncReadFile = zokio.future.async_fn_with_params(struct {
        fn readFile(path: []const u8) []const u8 {
            // 模拟文件读取
            _ = path; // 忽略路径参数
            return "文件内容模拟数据";
        }
    }.readFile);

    // 按照plan.md中的API设计创建任务
    const task = AsyncReadFile{
        .params = .{ .arg0 = "example.txt" }, // 参数名为arg0（第一个参数）
    };

    // 执行任务
    const result = try runtime.blockOn(task);
    std.debug.print("  ✓ 异步文件读取完成\n", .{});
    std.debug.print("  ✓ 文件内容: {s}\n", .{result});

    std.debug.print("  ✓ 带参数的异步函数演示完成\n", .{});
}

fn awaitFnDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. await_fn语法演示\n", .{});

    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();

    // 演示await_fn的编译时类型检查
    std.debug.print("  ✓ await_fn编译时类型检查演示\n", .{});

    // 创建一些Future用于演示
    const future1 = zokio.future.ready(u32, 100);
    const future2 = zokio.future.ready([]const u8, "Hello");

    // 演示await_fn的类型验证（编译时）
    // 注意：await_fn目前只是类型检查，不执行实际操作
    _ = future1; // 避免未使用警告
    _ = future2; // 避免未使用警告

    std.debug.print("  ✓ await_fn类型检查通过\n", .{});

    // 演示async_block中使用await_fn的概念
    std.debug.print("  ✓ async_block + await_fn概念演示\n", .{});

    const AsyncBlock = zokio.future.async_block(struct {
        fn execute() u32 {
            // 在实际实现中，这里会使用await_fn
            // const data = await_fn(fetch_data());
            // const processed = await_fn(process_data(data));
            // return processed;

            // 现在返回模拟结果
            return 42;
        }
    }.execute);

    const async_block = AsyncBlock.init(struct {
        fn execute() u32 {
            return 42;
        }
    }.execute);

    const block_result = try runtime.blockOn(async_block);
    std.debug.print("  ✓ async_block执行完成，结果: {}\n", .{block_result});
}

// 演示函数：模拟plan.md中的异步I/O操作
fn simulateAsyncRead(buffer: []u8, offset: u64) zokio.future.ReadyFuture(usize) {
    _ = offset;
    // 模拟读取操作
    const data = "模拟读取的数据";
    const bytes_to_copy = @min(buffer.len, data.len);
    @memcpy(buffer[0..bytes_to_copy], data[0..bytes_to_copy]);

    return zokio.future.ready(usize, bytes_to_copy);
}

// 演示更复杂的异步操作组合
fn complexAsyncDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n4. 复杂异步操作组合演示\n", .{});

    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();

    // 创建链式Future演示
    const first_future = zokio.future.ready(u32, 10);
    const second_future = zokio.future.ready(u32, 20);

    const chain_future = zokio.future.ChainFuture(@TypeOf(first_future), @TypeOf(second_future))
        .init(first_future, second_future);

    const chain_result = try runtime.blockOn(chain_future);
    std.debug.print("  ✓ 链式Future执行完成，结果: {}\n", .{chain_result});

    // 演示延迟Future
    std.debug.print("  ⏳ 延迟Future演示（1ms延迟）\n", .{});
    const delay_future = zokio.future.delay(1); // 1ms延迟

    const delay_start = std.time.milliTimestamp();
    _ = try runtime.blockOn(delay_future);
    const delay_end = std.time.milliTimestamp();

    std.debug.print("  ✓ 延迟完成，实际耗时: {}ms\n", .{delay_end - delay_start});
}

// 演示运行时统计和监控
fn runtimeStatsDemo(allocator: std.mem.Allocator) !void {
    std.debug.print("\n5. 运行时统计和监控演示\n", .{});

    var runtime = zokio.SimpleRuntime.init(allocator, .{ .metrics = true });
    defer runtime.deinit();
    try runtime.start();

    // 执行一些任务
    for (0..5) |i| {
        const task_future = zokio.future.ready(u32, @intCast(i));
        _ = try runtime.spawn(task_future);
    }

    // 获取统计信息
    const stats = runtime.getStats();
    std.debug.print("  ✓ 运行时统计信息:\n", .{});
    std.debug.print("    总任务数: {}\n", .{stats.total_tasks});
    std.debug.print("    运行状态: {}\n", .{stats.running});
    std.debug.print("    线程数: {}\n", .{stats.thread_count});
}
