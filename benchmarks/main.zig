//! Zokio性能基准测试
//!
//! 测试各个组件的性能表现，验证是否达到设计目标。

const std = @import("std");
const zokio = @import("zokio");

/// 基准测试结果
const BenchmarkResult = struct {
    name: []const u8,
    duration_ns: u64,
    operations: u64,
    ops_per_second: f64,

    pub fn format(
        self: BenchmarkResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}: {d:.2} ops/sec ({} ops in {} ns)", .{
            self.name,
            self.ops_per_second,
            self.operations,
            self.duration_ns,
        });
    }
};

/// 运行基准测试
fn runBenchmark(
    name: []const u8,
    benchmark_fn: *const fn (u64) anyerror!void,
    operations: u64,
) !BenchmarkResult {
    const start = std.time.nanoTimestamp();

    try benchmark_fn(operations);

    const end = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end - start));
    const ops_per_second = @as(f64, @floatFromInt(operations)) / (@as(f64, @floatFromInt(duration_ns)) / 1e9);

    return BenchmarkResult{
        .name = name,
        .duration_ns = duration_ns,
        .operations = operations,
        .ops_per_second = ops_per_second,
    };
}

/// 任务调度基准测试
fn benchmarkTaskScheduling(operations: u64) !void {
    const config = zokio.scheduler.SchedulerConfig{
        .worker_threads = 4,
        .queue_capacity = 256,
        .enable_work_stealing = true,
        .enable_statistics = false, // 禁用统计以获得最佳性能
    };

    var scheduler = zokio.scheduler.Scheduler(config).init();

    // 创建任务池
    var tasks: [1000]zokio.scheduler.Task = undefined;
    for (&tasks, 0..) |*task, i| {
        task.* = zokio.scheduler.Task{
            .id = zokio.future.TaskId{ .id = i },
            .future_ptr = undefined,
            .vtable = undefined,
        };
    }

    // 基准测试：调度任务
    var i: u64 = 0;
    while (i < operations) : (i += 1) {
        const task_index = i % tasks.len;
        scheduler.schedule(&tasks[task_index]);
    }
}

/// 工作窃取队列基准测试
fn benchmarkWorkStealingQueue(operations: u64) !void {
    const TestItem = struct {
        value: u64,
    };

    var queue = zokio.scheduler.WorkStealingQueue(*TestItem, 256).init();
    var items: [1000]TestItem = undefined;

    // 初始化测试项
    for (&items, 0..) |*item, i| {
        item.value = i;
    }

    // 基准测试：推入和弹出操作
    var i: u64 = 0;
    while (i < operations) : (i += 1) {
        const item_index = i % items.len;

        // 推入
        if (queue.push(&items[item_index])) {
            // 弹出
            _ = queue.pop();
        }
    }
}

/// Future轮询基准测试
fn benchmarkFuturePolling(operations: u64) !void {
    const TestFuture = struct {
        counter: u64,
        target: u64,

        pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u64) {
            _ = ctx;
            self.counter += 1;
            if (self.counter >= self.target) {
                return .{ .ready = self.counter };
            }
            return .pending;
        }
    };

    var future = TestFuture{ .counter = 0, .target = operations };
    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);

    // 基准测试：轮询直到完成
    while (true) {
        switch (future.poll(&ctx)) {
            .ready => break,
            .pending => continue,
        }
    }
}

/// 内存分配基准测试
fn benchmarkMemoryAllocation(operations: u64) !void {
    const config = zokio.memory.MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = false, // 禁用指标以获得最佳性能
    };

    var allocator = try zokio.memory.MemoryAllocator(config).init(std.heap.page_allocator);
    defer allocator.deinit();

    // 基准测试：分配和释放小对象
    var i: u64 = 0;
    while (i < operations) : (i += 1) {
        const memory = try allocator.alloc(u32, 1);
        allocator.free(memory);
    }
}

/// 对象池基准测试
fn benchmarkObjectPool(operations: u64) !void {
    const TestObject = struct {
        value: u64,
    };

    var pool = zokio.memory.ObjectPool(TestObject, 1000).init();

    // 基准测试：获取和释放对象
    var i: u64 = 0;
    while (i < operations) : (i += 1) {
        if (pool.acquire()) |obj| {
            obj.value = i;
            pool.release(obj);
        }
    }
}

/// 原子操作基准测试
fn benchmarkAtomicOperations(operations: u64) !void {
    var atomic_value = zokio.utils.Atomic.Value(u64).init(0);

    // 基准测试：原子递增操作
    var i: u64 = 0;
    while (i < operations) : (i += 1) {
        _ = atomic_value.fetchAdd(1, .monotonic);
    }
}

/// I/O操作基准测试
fn benchmarkIoOperations(operations: u64) !void {
    const config = zokio.io.IoConfig{
        .prefer_io_uring = false, // 使用模拟后端
        .events_capacity = 1024,
    };

    var driver = try zokio.io.IoDriver(config).init(std.heap.page_allocator);
    defer driver.deinit();

    var buffer = [_]u8{0} ** 1024;

    // 基准测试：提交I/O操作
    var i: u64 = 0;
    while (i < operations) : (i += 1) {
        _ = try driver.submitRead(1, &buffer, 0);
    }
}

/// 运行所有基准测试
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("Zokio性能基准测试\n", .{});
    try stdout.print("==================\n\n", .{});

    // 显示编译时信息
    const config = zokio.RuntimeConfig{};
    const RuntimeType = zokio.ZokioRuntime(config);

    try stdout.print("编译时信息:\n", .{});
    try stdout.print("  平台: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.platform});
    try stdout.print("  架构: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.architecture});
    try stdout.print("  工作线程: {}\n", .{RuntimeType.COMPILE_TIME_INFO.worker_threads});
    try stdout.print("  I/O后端: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.io_backend});
    try stdout.print("\n", .{});

    // 基准测试参数
    const operations = 1_000_000; // 100万次操作

    // 运行基准测试
    const benchmarks = [_]struct {
        name: []const u8,
        func: *const fn (u64) anyerror!void,
    }{
        .{ .name = "任务调度", .func = benchmarkTaskScheduling },
        .{ .name = "工作窃取队列", .func = benchmarkWorkStealingQueue },
        .{ .name = "Future轮询", .func = benchmarkFuturePolling },
        .{ .name = "内存分配", .func = benchmarkMemoryAllocation },
        .{ .name = "对象池", .func = benchmarkObjectPool },
        .{ .name = "原子操作", .func = benchmarkAtomicOperations },
        .{ .name = "I/O操作", .func = benchmarkIoOperations },
    };

    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();

    for (benchmarks) |benchmark| {
        try stdout.print("运行基准测试: {s}...\n", .{benchmark.name});

        const result = try runBenchmark(benchmark.name, benchmark.func, operations);
        try results.append(result);

        try stdout.print("  {}\n", .{result});
    }

    try stdout.print("\n基准测试总结:\n", .{});
    try stdout.print("================\n", .{});

    for (results.items) |result| {
        try stdout.print("{}\n", .{result});
    }

    // 性能目标验证
    try stdout.print("\n性能目标验证:\n", .{});
    try stdout.print("==============\n", .{});

    for (results.items) |result| {
        const target_ops_per_sec: f64 = if (std.mem.indexOf(u8, result.name, "任务调度") != null)
            5_000_000 // 任务调度目标：500万ops/sec
        else if (std.mem.indexOf(u8, result.name, "Future轮询") != null)
            10_000_000 // Future轮询目标：1000万ops/sec
        else
            1_000_000; // 默认目标：100万ops/sec

        const achieved = result.ops_per_second >= target_ops_per_sec;
        const status = if (achieved) "✓ 达到" else "✗ 未达到";

        try stdout.print("{s} {s}: {d:.2} ops/sec (目标: {d:.2} ops/sec)\n", .{
            status,
            result.name,
            result.ops_per_second,
            target_ops_per_sec,
        });
    }
}
