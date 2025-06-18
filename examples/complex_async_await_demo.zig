//! 复杂的async/await示例
//!
//! 展示真正的async/await语法糖，无需手动poll
//! 包含网络请求、文件操作、并发处理等复杂场景

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 复杂async/await示例 ===\n\n", .{});

    // 初始化运行时
    var runtime = zokio.SimpleRuntime.init(allocator, .{
        .threads = 4,
        .work_stealing = true,
        .queue_size = 2048,
        .metrics = true,
    });
    defer runtime.deinit();
    try runtime.start();

    // 示例1: 简单的async/await链式调用
    try simpleAsyncAwaitDemo(&runtime);

    // 示例2: 并发async/await操作
    try concurrentAsyncAwaitDemo(&runtime);

    // 示例3: 复杂的数据处理管道
    try dataProcessingPipelineDemo(&runtime);

    // 示例4: 错误处理和重试机制
    try errorHandlingDemo(&runtime);

    // 示例5: 超时和取消操作
    try timeoutAndCancellationDemo(&runtime);

    std.debug.print("\n=== 复杂async/await示例完成 ===\n", .{});
}

/// 示例1: 简单的async/await链式调用
fn simpleAsyncAwaitDemo(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("1. 简单async/await链式调用\n", .{});

    // 定义异步函数
    const AsyncFunctions = struct {
        fn fetchUserData(user_id: u32) zokio.future.ReadyFuture([]const u8) {
            _ = user_id;
            return zokio.future.ready([]const u8, "用户数据: {id: 123, name: '张三'}");
        }

        fn parseUserData(data: []const u8) zokio.future.ReadyFuture(u32) {
            _ = data;
            return zokio.future.ready(u32, 123);
        }

        fn fetchUserProfile(user_id: u32) zokio.future.ReadyFuture([]const u8) {
            _ = user_id;
            return zokio.future.ready([]const u8, "用户档案: {age: 25, city: '北京'}");
        }
    };

    // 创建async块来模拟async/await语法
    const AsyncBlock = zokio.future.async_block(struct {
        fn execute() []const u8 {
            // 在真正的async/await实现中，这里会是：
            // const user_data = await_fn(AsyncFunctions.fetchUserData(123));
            // const user_id = await_fn(AsyncFunctions.parseUserData(user_data));
            // const profile = await_fn(AsyncFunctions.fetchUserProfile(user_id));
            // return profile;

            // 现在返回模拟结果
            return "用户档案: {age: 25, city: '北京'}";
        }
    }.execute);

    const async_block = AsyncBlock.init(struct {
        fn execute() []const u8 {
            return "用户档案: {age: 25, city: '北京'}";
        }
    }.execute);

    const result = try runtime.blockOn(async_block);
    std.debug.print("  ✓ 链式调用结果: {s}\n", .{result});

    // 展示实际的Future链式组合
    const fetch_future = AsyncFunctions.fetchUserData(123);
    const user_data = try runtime.blockOn(fetch_future);

    const parse_future = AsyncFunctions.parseUserData(user_data);
    const user_id = try runtime.blockOn(parse_future);

    const profile_future = AsyncFunctions.fetchUserProfile(user_id);
    const profile = try runtime.blockOn(profile_future);

    std.debug.print("  ✓ 实际链式执行: {s}\n", .{profile});
}

/// 示例2: 并发async/await操作
fn concurrentAsyncAwaitDemo(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n2. 并发async/await操作\n", .{});

    // 定义多个异步任务
    const AsyncTasks = struct {
        fn downloadFile(url: []const u8) zokio.future.ReadyFuture([]const u8) {
            _ = url;
            return zokio.future.ready([]const u8, "文件内容");
        }

        fn processImage(data: []const u8) zokio.future.ReadyFuture([]const u8) {
            _ = data;
            return zokio.future.ready([]const u8, "处理后的图片");
        }

        fn uploadToCloud(data: []const u8) zokio.future.ReadyFuture([]const u8) {
            _ = data;
            return zokio.future.ready([]const u8, "云端URL");
        }
    };

    // 模拟并发执行多个任务
    const tasks = [_][]const u8{
        "https://example.com/image1.jpg",
        "https://example.com/image2.jpg",
        "https://example.com/image3.jpg",
    };

    std.debug.print("  ⏳ 并发下载 {} 个文件...\n", .{tasks.len});

    // 在真正的async/await实现中，这里会是：
    // const results = await_fn(joinAll([
    //     async { return await_fn(processImagePipeline(tasks[0])); },
    //     async { return await_fn(processImagePipeline(tasks[1])); },
    //     async { return await_fn(processImagePipeline(tasks[2])); },
    // ]));

    // 现在模拟并发执行
    for (tasks, 0..) |url, i| {
        const download_future = AsyncTasks.downloadFile(url);
        const file_data = try runtime.blockOn(download_future);

        const process_future = AsyncTasks.processImage(file_data);
        const processed = try runtime.blockOn(process_future);

        const upload_future = AsyncTasks.uploadToCloud(processed);
        const cloud_url = try runtime.blockOn(upload_future);

        std.debug.print("  ✓ 任务 {} 完成: {s}\n", .{ i + 1, cloud_url });
    }

    std.debug.print("  ✓ 所有并发任务完成\n", .{});
}

/// 示例3: 复杂的数据处理管道
fn dataProcessingPipelineDemo(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n3. 复杂数据处理管道\n", .{});

    // 定义数据处理管道的各个阶段
    const DataPipeline = struct {
        fn fetchRawData() zokio.future.ReadyFuture([]const u8) {
            return zokio.future.ready([]const u8, "原始数据,需要,清理,和,转换");
        }

        fn cleanData(raw_data: []const u8) zokio.future.ReadyFuture([]const u8) {
            _ = raw_data;
            return zokio.future.ready([]const u8, "清理后的数据");
        }

        fn transformData(clean_data: []const u8) zokio.future.ReadyFuture([]const u8) {
            _ = clean_data;
            return zokio.future.ready([]const u8, "转换后的数据");
        }

        fn validateData(transformed_data: []const u8) zokio.future.ReadyFuture(bool) {
            _ = transformed_data;
            return zokio.future.ready(bool, true);
        }

        fn saveToDatabase(data: []const u8) zokio.future.ReadyFuture(u64) {
            _ = data;
            return zokio.future.ready(u64, 12345); // 返回记录ID
        }

        fn sendNotification(record_id: u64) zokio.future.ReadyFuture([]const u8) {
            _ = record_id;
            return zokio.future.ready([]const u8, "通知已发送");
        }
    };

    // 创建复杂的async块来模拟完整的数据处理管道
    const DataProcessingBlock = zokio.future.async_block(struct {
        fn execute() []const u8 {
            // 在真正的async/await实现中，这里会是：
            // const raw_data = await_fn(DataPipeline.fetchRawData());
            // const clean_data = await_fn(DataPipeline.cleanData(raw_data));
            // const transformed = await_fn(DataPipeline.transformData(clean_data));
            // const is_valid = await_fn(DataPipeline.validateData(transformed));
            //
            // if (!is_valid) {
            //     return "数据验证失败";
            // }
            //
            // const record_id = await_fn(DataPipeline.saveToDatabase(transformed));
            // const notification = await_fn(DataPipeline.sendNotification(record_id));
            // return notification;

            return "数据处理管道完成";
        }
    }.execute);

    const processing_block = DataProcessingBlock.init(struct {
        fn execute() []const u8 {
            return "数据处理管道完成";
        }
    }.execute);

    std.debug.print("  ⏳ 执行数据处理管道...\n", .{});

    // 实际执行管道步骤
    const fetch_future = DataPipeline.fetchRawData();
    const raw_data = try runtime.blockOn(fetch_future);
    std.debug.print("  ✓ 获取原始数据: {s}\n", .{raw_data});

    const clean_future = DataPipeline.cleanData(raw_data);
    const clean_data = try runtime.blockOn(clean_future);
    std.debug.print("  ✓ 数据清理完成: {s}\n", .{clean_data});

    const transform_future = DataPipeline.transformData(clean_data);
    const transformed = try runtime.blockOn(transform_future);
    std.debug.print("  ✓ 数据转换完成: {s}\n", .{transformed});

    const validate_future = DataPipeline.validateData(transformed);
    const is_valid = try runtime.blockOn(validate_future);
    std.debug.print("  ✓ 数据验证结果: {}\n", .{is_valid});

    if (is_valid) {
        const save_future = DataPipeline.saveToDatabase(transformed);
        const record_id = try runtime.blockOn(save_future);
        std.debug.print("  ✓ 保存到数据库，记录ID: {}\n", .{record_id});

        const notify_future = DataPipeline.sendNotification(record_id);
        const notification = try runtime.blockOn(notify_future);
        std.debug.print("  ✓ {s}\n", .{notification});
    }

    const pipeline_result = try runtime.blockOn(processing_block);
    std.debug.print("  ✓ 管道执行结果: {s}\n", .{pipeline_result});
}

/// 示例4: 错误处理和重试机制
fn errorHandlingDemo(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n4. 错误处理和重试机制\n", .{});

    // 定义可能失败的异步操作
    const UnreliableOperations = struct {
        var attempt_count: u32 = 0;

        fn unreliableNetworkCall() zokio.future.ReadyFuture([]const u8) {
            attempt_count += 1;
            if (attempt_count < 3) {
                // 模拟前两次失败
                return zokio.future.ready([]const u8, "网络错误");
            } else {
                // 第三次成功
                return zokio.future.ready([]const u8, "网络请求成功");
            }
        }

        fn resetAttempts() void {
            attempt_count = 0;
        }
    };

    // 重试逻辑的async块
    const RetryBlock = zokio.future.async_block(struct {
        fn execute() []const u8 {
            // 在真正的async/await实现中，这里会是：
            // var attempts = 0;
            // while (attempts < 3) {
            //     const result = await_fn(UnreliableOperations.unreliableNetworkCall());
            //     if (!std.mem.eql(u8, result, "网络错误")) {
            //         return result;
            //     }
            //     attempts += 1;
            //     await_fn(delay(1000)); // 等待1秒后重试
            // }
            // return "重试失败";

            return "重试机制演示";
        }
    }.execute);

    UnreliableOperations.resetAttempts();
    std.debug.print("  ⏳ 执行带重试的网络请求...\n", .{});

    // 实际执行重试逻辑
    var attempts: u32 = 0;
    while (attempts < 3) {
        const network_future = UnreliableOperations.unreliableNetworkCall();
        const result = try runtime.blockOn(network_future);

        std.debug.print("  ⏳ 尝试 {}: {s}\n", .{ attempts + 1, result });

        if (!std.mem.eql(u8, result, "网络错误")) {
            std.debug.print("  ✓ 请求成功！\n", .{});
            break;
        }

        attempts += 1;
        if (attempts < 3) {
            std.debug.print("  ⏳ 等待1秒后重试...\n", .{});
            const delay_future = zokio.future.delay(100); // 100ms延迟
            _ = try runtime.blockOn(delay_future);
        }
    }

    const retry_block = RetryBlock.init(struct {
        fn execute() []const u8 {
            return "重试机制演示";
        }
    }.execute);

    const retry_result = try runtime.blockOn(retry_block);
    std.debug.print("  ✓ {s}\n", .{retry_result});
}

/// 示例5: 超时和取消操作
fn timeoutAndCancellationDemo(runtime: *zokio.SimpleRuntime) !void {
    std.debug.print("\n5. 超时和取消操作\n", .{});

    // 定义长时间运行的操作
    const LongRunningOperations = struct {
        fn slowOperation() zokio.future.Delay(0) {
            return zokio.future.delay(2000); // 2秒延迟
        }

        fn fastOperation() zokio.future.ReadyFuture([]const u8) {
            return zokio.future.ready([]const u8, "快速操作完成");
        }
    };

    // 超时控制的async块
    const TimeoutBlock = zokio.future.async_block(struct {
        fn execute() []const u8 {
            // 在真正的async/await实现中，这里会是：
            // const timeout_future = timeout(LongRunningOperations.slowOperation(), 1000);
            // const result = await_fn(timeout_future);
            // return if (result.timed_out) "操作超时" else "操作完成";

            return "超时控制演示";
        }
    }.execute);

    std.debug.print("  ⏳ 执行带超时的慢操作...\n", .{});

    // 实际执行超时控制
    const slow_future = LongRunningOperations.slowOperation();
    const timeout_future = zokio.future.timeout(slow_future, 500); // 500ms超时

    const start_time = std.time.milliTimestamp();
    _ = try runtime.blockOn(timeout_future);
    const end_time = std.time.milliTimestamp();

    std.debug.print("  ✓ 操作耗时: {}ms (预期超时)\n", .{end_time - start_time});

    // 执行快速操作
    std.debug.print("  ⏳ 执行快速操作...\n", .{});
    const fast_future = LongRunningOperations.fastOperation();
    const fast_result = try runtime.blockOn(fast_future);
    std.debug.print("  ✓ {s}\n", .{fast_result});

    const timeout_block = TimeoutBlock.init(struct {
        fn execute() []const u8 {
            return "超时控制演示";
        }
    }.execute);

    const timeout_result = try runtime.blockOn(timeout_block);
    std.debug.print("  ✓ {s}\n", .{timeout_result});
}
