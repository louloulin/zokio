//! 高级同步原语演示
//!
//! 展示Zokio的高级同步功能，包括信号量、通道、条件变量等。

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio高级同步原语演示 ===\n\n");

    // 创建运行时
    var runtime = try zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();

    // 运行同步原语演示
    try runtime.block_on(advancedSyncDemonstration());

    std.debug.print("\n=== 演示完成 ===\n");
}

fn advancedSyncDemonstration() !void {
    std.debug.print("1. 异步互斥锁演示\n");
    
    // 创建异步互斥锁
    var mutex = zokio.sync.AsyncMutex.init();
    
    std.debug.print("  互斥锁初始状态: 未锁定\n");
    
    // 第一次获取锁
    var lock_future1 = mutex.lock();
    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);
    
    switch (lock_future1.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 第一次获取锁成功\n"),
        .pending => std.debug.print("  ⏳ 第一次获取锁待定\n"),
    }
    
    // 第二次尝试获取锁（应该失败）
    var lock_future2 = mutex.lock();
    switch (lock_future2.poll(&ctx)) {
        .ready => std.debug.print("  ✗ 第二次获取锁意外成功\n"),
        .pending => std.debug.print("  ✓ 第二次获取锁正确阻塞\n"),
    }
    
    // 释放锁
    mutex.unlock();
    std.debug.print("  ✓ 锁已释放\n");
    
    // 现在第二次获取应该成功
    switch (lock_future2.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 第二次获取锁现在成功\n"),
        .pending => std.debug.print("  ⏳ 第二次获取锁仍在等待\n"),
    }
    
    mutex.unlock();
    std.debug.print("  ✓ 第二个锁已释放\n");
    
    std.debug.print("\n2. 异步信号量演示\n");
    
    // 创建信号量，初始许可数为3
    var semaphore = zokio.sync.AsyncSemaphore.init(3);
    
    std.debug.print("  信号量初始许可数: 3\n");
    
    // 获取许可
    var acquire_future1 = semaphore.acquire(1);
    switch (acquire_future1.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 获取1个许可成功，剩余许可: 2\n"),
        .pending => std.debug.print("  ⏳ 获取1个许可待定\n"),
    }
    
    var acquire_future2 = semaphore.acquire(2);
    switch (acquire_future2.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 获取2个许可成功，剩余许可: 0\n"),
        .pending => std.debug.print("  ⏳ 获取2个许可待定\n"),
    }
    
    // 尝试获取更多许可（应该阻塞）
    var acquire_future3 = semaphore.acquire(1);
    switch (acquire_future3.poll(&ctx)) {
        .ready => std.debug.print("  ✗ 获取额外许可意外成功\n"),
        .pending => std.debug.print("  ✓ 获取额外许可正确阻塞\n"),
    }
    
    // 释放一些许可
    semaphore.release(1);
    std.debug.print("  ✓ 释放1个许可，剩余许可: 1\n");
    
    // 现在应该可以获取许可了
    switch (acquire_future3.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 获取额外许可现在成功\n"),
        .pending => std.debug.print("  ⏳ 获取额外许可仍在等待\n"),
    }
    
    // 释放所有许可
    semaphore.release(3);
    std.debug.print("  ✓ 释放3个许可，信号量已重置\n");
    
    std.debug.print("\n3. 异步通道演示\n");
    
    // 创建容量为5的通道
    const ChannelType = zokio.sync.AsyncChannel(i32, 5);
    var channel = ChannelType.init();
    
    std.debug.print("  通道容量: 5\n");
    
    // 发送一些数据
    const test_values = [_]i32{ 10, 20, 30, 40, 50 };
    
    for (test_values, 0..) |value, i| {
        var send_future = channel.send(value);
        switch (send_future.poll(&ctx)) {
            .ready => std.debug.print("  ✓ 发送值 {} 成功 (第{}个)\n", .{ value, i + 1 }),
            .pending => std.debug.print("  ⏳ 发送值 {} 待定\n", .{value}),
        }
    }
    
    // 尝试发送第6个值（应该阻塞）
    var send_future_extra = channel.send(60);
    switch (send_future_extra.poll(&ctx)) {
        .ready => std.debug.print("  ✗ 发送额外值意外成功\n"),
        .pending => std.debug.print("  ✓ 发送额外值正确阻塞（通道已满）\n"),
    }
    
    // 接收一些数据
    std.debug.print("  开始接收数据:\n");
    for (0..3) |i| {
        var receive_future = channel.receive();
        switch (receive_future.poll(&ctx)) {
            .ready => |maybe_value| {
                if (maybe_value) |value| {
                    std.debug.print("    ✓ 接收到值: {} (第{}个)\n", .{ value, i + 1 });
                } else {
                    std.debug.print("    ✗ 通道已关闭\n");
                }
            },
            .pending => std.debug.print("    ⏳ 接收数据待定\n"),
        }
    }
    
    // 现在应该可以发送额外的值了
    switch (send_future_extra.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 发送额外值现在成功\n"),
        .pending => std.debug.print("  ⏳ 发送额外值仍在等待\n"),
    }
    
    // 接收剩余数据
    std.debug.print("  接收剩余数据:\n");
    var received_count: u32 = 3;
    while (received_count < 6) {
        var receive_future = channel.receive();
        switch (receive_future.poll(&ctx)) {
            .ready => |maybe_value| {
                if (maybe_value) |value| {
                    received_count += 1;
                    std.debug.print("    ✓ 接收到值: {} (总第{}个)\n", .{ value, received_count });
                } else {
                    std.debug.print("    ✗ 通道已关闭\n");
                    break;
                }
            },
            .pending => {
                std.debug.print("    ⏳ 接收数据待定\n");
                break;
            },
        }
    }
    
    std.debug.print("\n4. 通道关闭演示\n");
    
    // 关闭通道
    channel.close();
    std.debug.print("  ✓ 通道已关闭\n");
    
    // 尝试发送数据到已关闭的通道
    var send_to_closed = channel.send(100);
    switch (send_to_closed.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 向已关闭通道发送数据完成（被忽略）\n"),
        .pending => std.debug.print("  ⏳ 向已关闭通道发送数据待定\n"),
    }
    
    // 尝试从已关闭的通道接收数据
    var receive_from_closed = channel.receive();
    switch (receive_from_closed.poll(&ctx)) {
        .ready => |maybe_value| {
            if (maybe_value) |value| {
                std.debug.print("  ✓ 从已关闭通道接收到值: {}\n", .{value});
            } else {
                std.debug.print("  ✓ 从已关闭通道接收到null（正确行为）\n");
            }
        },
        .pending => std.debug.print("  ⏳ 从已关闭通道接收数据待定\n"),
    }
    
    std.debug.print("\n5. 不同类型通道演示\n");
    
    // 字符串通道
    const StringChannel = zokio.sync.AsyncChannel([]const u8, 3);
    var string_channel = StringChannel.init();
    
    const messages = [_][]const u8{ "Hello", "Zokio", "World" };
    
    std.debug.print("  字符串通道演示:\n");
    for (messages) |message| {
        var send_str = string_channel.send(message);
        switch (send_str.poll(&ctx)) {
            .ready => std.debug.print("    ✓ 发送消息: {s}\n", .{message}),
            .pending => std.debug.print("    ⏳ 发送消息待定: {s}\n", .{message}),
        }
    }
    
    for (0..messages.len) |i| {
        var receive_str = string_channel.receive();
        switch (receive_str.poll(&ctx)) {
            .ready => |maybe_message| {
                if (maybe_message) |message| {
                    std.debug.print("    ✓ 接收消息: {s} (第{}个)\n", .{ message, i + 1 });
                } else {
                    std.debug.print("    ✗ 通道已关闭\n");
                }
            },
            .pending => std.debug.print("    ⏳ 接收消息待定\n"),
        }
    }
    
    std.debug.print("\n6. 结构体通道演示\n");
    
    const Task = struct {
        id: u32,
        name: []const u8,
        priority: u8,
    };
    
    const TaskChannel = zokio.sync.AsyncChannel(Task, 2);
    var task_channel = TaskChannel.init();
    
    const tasks = [_]Task{
        .{ .id = 1, .name = "数据库查询", .priority = 1 },
        .{ .id = 2, .name = "文件处理", .priority = 2 },
    };
    
    std.debug.print("  任务通道演示:\n");
    for (tasks) |task| {
        var send_task = task_channel.send(task);
        switch (send_task.poll(&ctx)) {
            .ready => std.debug.print("    ✓ 发送任务: {} - {s} (优先级: {})\n", .{ task.id, task.name, task.priority }),
            .pending => std.debug.print("    ⏳ 发送任务待定: {}\n", .{task.id}),
        }
    }
    
    for (0..tasks.len) |i| {
        var receive_task = task_channel.receive();
        switch (receive_task.poll(&ctx)) {
            .ready => |maybe_task| {
                if (maybe_task) |task| {
                    std.debug.print("    ✓ 接收任务: {} - {s} (优先级: {}) (第{}个)\n", .{ task.id, task.name, task.priority, i + 1 });
                } else {
                    std.debug.print("    ✗ 任务通道已关闭\n");
                }
            },
            .pending => std.debug.print("    ⏳ 接收任务待定\n"),
        }
    }
    
    std.debug.print("\n7. 同步原语性能测试\n");
    
    // 互斥锁性能测试
    const mutex_iterations = 100000;
    var perf_mutex = zokio.sync.AsyncMutex.init();
    
    const mutex_start = zokio.timer.Instant.now();
    for (0..mutex_iterations) |_| {
        var lock_fut = perf_mutex.lock();
        _ = lock_fut.poll(&ctx);
        perf_mutex.unlock();
    }
    const mutex_end = zokio.timer.Instant.now();
    const mutex_duration = mutex_end.sub(mutex_start);
    
    std.debug.print("  互斥锁性能:\n");
    std.debug.print("    操作次数: {}\n", .{mutex_iterations});
    std.debug.print("    总耗时: {}微秒\n", .{mutex_duration.asMicros()});
    std.debug.print("    平均每次: {} 纳秒\n", .{mutex_duration.asNanos() / mutex_iterations});
    std.debug.print("    每秒操作: {d:.0}\n", .{@as(f64, @floatFromInt(mutex_iterations)) * 1_000_000.0 / @as(f64, @floatFromInt(mutex_duration.asMicros()))});
    
    // 信号量性能测试
    const sem_iterations = 50000;
    var perf_semaphore = zokio.sync.AsyncSemaphore.init(1);
    
    const sem_start = zokio.timer.Instant.now();
    for (0..sem_iterations) |_| {
        var acquire_fut = perf_semaphore.acquire(1);
        _ = acquire_fut.poll(&ctx);
        perf_semaphore.release(1);
    }
    const sem_end = zokio.timer.Instant.now();
    const sem_duration = sem_end.sub(sem_start);
    
    std.debug.print("  信号量性能:\n");
    std.debug.print("    操作次数: {}\n", .{sem_iterations});
    std.debug.print("    总耗时: {}微秒\n", .{sem_duration.asMicros()});
    std.debug.print("    平均每次: {} 纳秒\n", .{sem_duration.asNanos() / sem_iterations});
    std.debug.print("    每秒操作: {d:.0}\n", .{@as(f64, @floatFromInt(sem_iterations)) * 1_000_000.0 / @as(f64, @floatFromInt(sem_duration.asMicros()))});
    
    std.debug.print("\n✓ 高级同步原语演示完成\n");
}
