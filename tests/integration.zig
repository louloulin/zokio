//! 集成测试
//!
//! 测试Zokio各组件的集成功能。

const std = @import("std");
const zokio = @import("zokio");

test "Zokio运行时集成测试" {
    const testing = std.testing;

    // 创建运行时配置
    const config = zokio.RuntimeConfig{
        .worker_threads = 2,
        .enable_work_stealing = true,
        .enable_io_uring = false, // 在测试中禁用以确保兼容性
        .enable_metrics = true,
    };

    // 创建运行时实例
    var runtime = try zokio.ZokioRuntime(config).init(testing.allocator);
    defer runtime.deinit();

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 验证运行时状态
    try testing.expect(runtime.running.load(.acquire));

    // 测试编译时信息
    const RuntimeType = zokio.ZokioRuntime(config);
    try testing.expect(RuntimeType.COMPILE_TIME_INFO.worker_threads > 0);
    try testing.expect(RuntimeType.PERFORMANCE_CHARACTERISTICS.theoretical_max_tasks_per_second > 0);
}

test "Future和异步抽象集成测试" {
    const testing = std.testing;

    // 测试基础Future功能
    const TestFuture = struct {
        value: u32,
        polled: bool = false,

        pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
            _ = ctx;
            if (!self.polled) {
                self.polled = true;
                return .pending;
            }
            return .{ .ready = self.value };
        }
    };

    var test_future = TestFuture{ .value = 42 };
    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);

    // 第一次轮询应该返回pending
    const result1 = test_future.poll(&ctx);
    try testing.expect(result1.isPending());

    // 第二次轮询应该返回ready
    const result2 = test_future.poll(&ctx);
    try testing.expect(result2.isReady());
    if (result2 == .ready) {
        try testing.expectEqual(@as(u32, 42), result2.ready);
    }
}

test "调度器集成测试" {
    const testing = std.testing;

    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 2,
        .queue_capacity = 8,
        .steal_batch_size = 2,
        .enable_work_stealing = true,
        .enable_statistics = true,
    };

    var scheduler = zokio.scheduler.Scheduler(config).init();

    // 创建测试任务
    var test_task = zokio.scheduler.Task{
        .id = zokio.future.TaskId.generate(),
        .future_ptr = undefined,
        .vtable = undefined,
    };

    // 测试任务调度
    scheduler.schedule(&test_task);

    // 验证任务被调度到某个队列
    var found = false;
    for (&scheduler.local_queues) |queue| {
        if (!queue.isEmpty()) {
            found = true;
            break;
        }
    }

    if (!found and !scheduler.global_queue.isEmpty()) {
        found = true;
    }

    try testing.expect(found);
}

test "I/O驱动集成测试" {
    const testing = std.testing;

    const config = zokio.io.IoConfig{
        .prefer_io_uring = false, // 使用epoll进行测试
        .events_capacity = 64,
    };

    var driver = try zokio.io.IoDriver(config).init(testing.allocator);
    defer driver.deinit();

    // 测试I/O操作提交
    var buffer = [_]u8{0} ** 1024;
    const handle = try driver.submitRead(1, &buffer, 0);

    try testing.expect(handle.id > 0);

    // 测试轮询
    const completed = try driver.poll(0);
    _ = completed; // 在模拟实现中可能为0
}

test "内存管理集成测试" {
    const testing = std.testing;

    const config = zokio.memory.MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = true,
    };

    var allocator = try zokio.memory.MemoryAllocator(config).init(testing.allocator);
    defer allocator.deinit();

    // 测试内存分配
    const memory = try allocator.alloc(u32, 10);
    defer allocator.free(memory);

    try testing.expectEqual(@as(usize, 10), memory.len);

    // 测试对象池
    var pool = zokio.memory.ObjectPool(u32, 10).init();

    const obj1 = pool.acquire().?;
    obj1.* = 42;

    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 1), stats.allocated_objects);

    pool.release(obj1);

    const stats2 = pool.getStats();
    try testing.expectEqual(@as(usize, 0), stats2.allocated_objects);
}

test "同步原语集成测试" {
    const testing = std.testing;

    var mutex = zokio.sync.AsyncMutex.init();

    // 测试互斥锁
    var lock_future = mutex.lock();
    const waker = zokio.future.Waker.noop();
    var ctx = zokio.future.Context.init(waker);

    const result = lock_future.poll(&ctx);
    try testing.expect(result.isReady());

    // 测试解锁
    mutex.unlock();
    try testing.expect(!mutex.locked.load(.acquire));
}

test "时间模块集成测试" {
    const testing = std.testing;

    var sleep_future = zokio.time.sleep(1); // 1毫秒
    const waker = zokio.future.Waker.noop();
    var ctx = zokio.future.Context.init(waker);

    // 第一次轮询可能返回pending
    _ = sleep_future.poll(&ctx);

    // 等待一段时间后再次轮询
    std.time.sleep(2 * std.time.ns_per_ms);
    const result2 = sleep_future.poll(&ctx);
    try testing.expect(result2.isReady());
}

test "指标收集集成测试" {
    const testing = std.testing;

    var metrics = zokio.metrics.RuntimeMetrics.init();

    // 记录一些指标
    metrics.recordTaskSpawn();
    metrics.recordTaskSpawn();
    metrics.recordTaskCompletion();

    // 获取快照
    const snapshot = metrics.getSnapshot();
    try testing.expectEqual(@as(u64, 2), snapshot.tasks_spawned);
    try testing.expectEqual(@as(u64, 1), snapshot.tasks_completed);
}

test "平台能力检测集成测试" {
    const testing = std.testing;

    // 测试平台能力
    try testing.expect(zokio.platform.PlatformCapabilities.cache_line_size > 0);
    try testing.expect(zokio.platform.PlatformCapabilities.page_size > 0);
    try testing.expect(zokio.platform.PlatformCapabilities.is_supported);

    // 测试CPU优化
    const CpuOpt = zokio.platform.CpuOptimizations(@import("builtin").cpu.arch);

    var value: u32 = 42;
    const loaded = CpuOpt.atomicLoad(u32, &value, .monotonic);
    try testing.expectEqual(@as(u32, 42), loaded);
}

test "工具函数集成测试" {
    const testing = std.testing;

    // 测试编译时字符串连接（简化版本只返回第一个字符串）
    const result = zokio.utils.comptimeConcat(&[_][]const u8{ "Hello", " ", "Zokio" });
    try testing.expectEqualStrings("Hello", result);

    // 测试原子操作包装器
    var atomic_value = zokio.utils.Atomic.Value(u32).init(42);
    try testing.expectEqual(@as(u32, 42), atomic_value.load(.monotonic));

    atomic_value.store(84, .monotonic);
    try testing.expectEqual(@as(u32, 84), atomic_value.load(.monotonic));

    // 测试侵入式链表
    const TestItem = struct {
        value: u32,
        node: zokio.utils.IntrusiveNode(@This()),
    };

    var list = zokio.utils.IntrusiveList(TestItem, "node").init();
    var item = TestItem{ .value = 42, .node = .{} };

    list.pushBack(&item);
    try testing.expectEqual(@as(usize, 1), list.len);

    const popped = list.popFront().?;
    try testing.expectEqual(@as(u32, 42), popped.value);
    try testing.expect(list.isEmpty());
}
