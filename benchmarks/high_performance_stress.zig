//! Zokio高性能压力测试
//!
//! 基于benchmarks和examples实现的高性能压力测试套件

const std = @import("std");
const zokio = @import("zokio");

/// 压力测试结果
const StressTestResult = struct {
    name: []const u8,
    duration_ms: u64,
    operations_completed: u64,
    ops_per_second: f64,
    peak_memory_mb: f64,
    success_rate: f64,

    pub fn format(
        self: StressTestResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}:\n", .{self.name});
        try writer.print("  持续时间: {}ms\n", .{self.duration_ms});
        try writer.print("  完成操作: {}\n", .{self.operations_completed});
        try writer.print("  操作/秒: {d:.2}\n", .{self.ops_per_second});
        try writer.print("  峰值内存: {d:.2}MB\n", .{self.peak_memory_mb});
        try writer.print("  成功率: {d:.2}%\n", .{self.success_rate * 100});
    }
};

/// 高并发任务调度压力测试
const HighConcurrencySchedulerStress = struct {
    task_count: u32,
    worker_threads: u32,
    completed_tasks: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    failed_tasks: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    const Self = @This();
    pub const Output = StressTestResult;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(StressTestResult) {
        _ = ctx;

        const start_time = std.time.milliTimestamp();

        // 创建高性能调度器配置
        const scheduler_config = comptime zokio.scheduler.SchedulerConfig{
            .worker_threads = 8,
            .queue_capacity = 1024,
            .steal_batch_size = 8,
            .enable_work_stealing = true,
            .enable_statistics = false, // 禁用统计以获得最佳性能
        };

        var scheduler = zokio.scheduler.Scheduler(scheduler_config).init();

        // 创建大量任务
        var tasks = std.ArrayList(zokio.scheduler.Task).init(std.heap.page_allocator);
        defer tasks.deinit();

        for (0..self.task_count) |i| {
            const task = zokio.scheduler.Task{
                .id = zokio.future.TaskId{ .id = i },
                .future_ptr = undefined,
                .vtable = undefined,
            };
            tasks.append(task) catch {
                _ = self.failed_tasks.fetchAdd(1, .acq_rel);
                continue;
            };
        }

        // 高并发调度所有任务
        for (tasks.items) |*task| {
            scheduler.schedule(task);

            // 模拟任务执行
            var sum: u64 = 0;
            for (0..100) |j| {
                sum += task.id.id + j;
            }

            _ = self.completed_tasks.fetchAdd(1, .acq_rel);
        }

        const end_time = std.time.milliTimestamp();
        const duration_ms = @as(u64, @intCast(end_time - start_time));
        const completed = self.completed_tasks.load(.acquire);
        const failed = self.failed_tasks.load(.acquire);

        return .{ .ready = StressTestResult{
            .name = "高并发任务调度",
            .duration_ms = duration_ms,
            .operations_completed = completed,
            .ops_per_second = @as(f64, @floatFromInt(completed)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .peak_memory_mb = @as(f64, @floatFromInt(tasks.items.len * @sizeOf(zokio.scheduler.Task))) / (1024.0 * 1024.0),
            .success_rate = @as(f64, @floatFromInt(completed)) / @as(f64, @floatFromInt(completed + failed)),
        } };
    }
};

/// 极限内存分配压力测试
const ExtremeMemoryStress = struct {
    allocation_cycles: u32,
    max_allocation_size: usize,
    allocator: std.mem.Allocator,
    allocations_completed: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    allocation_failures: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    const Self = @This();
    pub const Output = StressTestResult;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(StressTestResult) {
        _ = ctx;

        const start_time = std.time.milliTimestamp();
        var peak_memory: usize = 0;

        // 创建高性能内存分配器
        const memory_config = comptime zokio.memory.MemoryConfig{
            .strategy = .adaptive,
            .max_allocation_size = 1024 * 1024,
            .enable_numa = true,
            .enable_metrics = false,
        };

        var memory_allocator = zokio.memory.MemoryAllocator(memory_config).init(self.allocator) catch {
            return .{ .ready = StressTestResult{
                .name = "极限内存分配",
                .duration_ms = 0,
                .operations_completed = 0,
                .ops_per_second = 0,
                .peak_memory_mb = 0,
                .success_rate = 0,
            } };
        };
        defer memory_allocator.deinit();

        var active_allocations = std.ArrayList([]u8).init(self.allocator);
        defer {
            for (active_allocations.items) |allocation| {
                memory_allocator.free(allocation);
            }
            active_allocations.deinit();
        }

        // 极限内存分配循环
        for (0..self.allocation_cycles) |cycle| {
            // 随机分配大小
            const size = (cycle % (self.max_allocation_size / 8)) + 1;

            if (memory_allocator.alloc(u8, size)) |allocation| {
                // 写入数据以确保内存真正分配
                for (allocation, 0..) |*byte, i| {
                    byte.* = @intCast((cycle + i) % 256);
                }

                active_allocations.append(allocation) catch {
                    memory_allocator.free(allocation);
                    _ = self.allocation_failures.fetchAdd(1, .acq_rel);
                    continue;
                };

                peak_memory += allocation.len;
                _ = self.allocations_completed.fetchAdd(1, .acq_rel);

                // 定期释放一些内存以避免OOM
                if (cycle % 100 == 0 and active_allocations.items.len > 50) {
                    const to_free = active_allocations.orderedRemove(0);
                    peak_memory -= to_free.len;
                    memory_allocator.free(to_free);
                }
            } else |_| {
                _ = self.allocation_failures.fetchAdd(1, .acq_rel);
            }
        }

        const end_time = std.time.milliTimestamp();
        const duration_ms = @as(u64, @intCast(end_time - start_time));
        const completed = self.allocations_completed.load(.acquire);
        const failed = self.allocation_failures.load(.acquire);

        return .{ .ready = StressTestResult{
            .name = "极限内存分配",
            .duration_ms = duration_ms,
            .operations_completed = completed,
            .ops_per_second = @as(f64, @floatFromInt(completed)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .peak_memory_mb = @as(f64, @floatFromInt(peak_memory)) / (1024.0 * 1024.0),
            .success_rate = @as(f64, @floatFromInt(completed)) / @as(f64, @floatFromInt(completed + failed)),
        } };
    }
};

/// 高频I/O操作压力测试
const HighFrequencyIoStress = struct {
    io_operations: u32,
    concurrent_connections: u32,
    operations_completed: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    operations_failed: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    const Self = @This();
    pub const Output = StressTestResult;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(StressTestResult) {
        _ = ctx;

        const start_time = std.time.milliTimestamp();

        // 创建高性能I/O驱动配置
        const io_config = comptime zokio.io.IoConfig{
            .prefer_io_uring = true,
            .events_capacity = 4096,
        };

        var driver = zokio.io.IoDriver(io_config).init(std.heap.page_allocator) catch {
            return .{ .ready = StressTestResult{
                .name = "高频I/O操作",
                .duration_ms = 0,
                .operations_completed = 0,
                .ops_per_second = 0,
                .peak_memory_mb = 0,
                .success_rate = 0,
            } };
        };
        defer driver.deinit();

        var buffers = std.ArrayList([1024]u8).init(std.heap.page_allocator);
        defer buffers.deinit();

        // 预分配缓冲区
        for (0..self.concurrent_connections) |_| {
            buffers.append([_]u8{0} ** 1024) catch break;
        }

        // 高频I/O操作循环
        for (0..self.io_operations) |i| {
            const buffer_index = i % buffers.items.len;
            const buffer = &buffers.items[buffer_index];

            // 模拟文件描述符
            const fd = @as(std.posix.fd_t, @intCast((i % 100) + 1));

            if (driver.submitRead(fd, buffer, 0)) |_| {
                _ = self.operations_completed.fetchAdd(1, .acq_rel);

                // 模拟数据处理
                for (buffer, 0..) |*byte, j| {
                    byte.* = @intCast((i + j) % 256);
                }
            } else |_| {
                _ = self.operations_failed.fetchAdd(1, .acq_rel);
            }

            // 定期轮询I/O事件
            if (i % 100 == 0) {
                _ = driver.poll(0) catch 0;
            }
        }

        const end_time = std.time.milliTimestamp();
        const duration_ms = @as(u64, @intCast(end_time - start_time));
        const completed = self.operations_completed.load(.acquire);
        const failed = self.operations_failed.load(.acquire);

        return .{ .ready = StressTestResult{
            .name = "高频I/O操作",
            .duration_ms = duration_ms,
            .operations_completed = completed,
            .ops_per_second = @as(f64, @floatFromInt(completed)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .peak_memory_mb = @as(f64, @floatFromInt(buffers.items.len * 1024)) / (1024.0 * 1024.0),
            .success_rate = @as(f64, @floatFromInt(completed)) / @as(f64, @floatFromInt(completed + failed)),
        } };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== Zokio高性能压力测试套件 ===\n", .{});
    try stdout.print("基于benchmarks和examples的高性能压力测试\n\n", .{});

    // 创建高性能运行时配置
    const config = zokio.RuntimeConfig{
        .worker_threads = 8,
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .enable_metrics = false, // 禁用指标以获得最佳性能
        .enable_numa = true,
        .enable_simd = true,
        .enable_prefetch = true,
        .cache_line_optimization = true,
    };

    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    try stdout.print("运行时配置:\n", .{});
    try stdout.print("  平台: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.platform});
    try stdout.print("  架构: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.architecture});
    try stdout.print("  工作线程: {}\n", .{RuntimeType.COMPILE_TIME_INFO.worker_threads});
    try stdout.print("  I/O后端: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.io_backend});
    try stdout.print("\n", .{});

    try runtime.start();
    defer runtime.stop();

    var results = std.ArrayList(StressTestResult).init(allocator);
    defer results.deinit();

    // 压力测试1: 高并发任务调度
    try stdout.print("=== 压力测试1: 高并发任务调度 ===\n", .{});
    const scheduler_stress = HighConcurrencySchedulerStress{
        .task_count = 100_000, // 10万个任务
        .worker_threads = 8,
    };
    const scheduler_result = try runtime.blockOn(scheduler_stress);
    try results.append(scheduler_result);
    try stdout.print("{}\n", .{scheduler_result});

    // 压力测试2: 极限内存分配
    try stdout.print("=== 压力测试2: 极限内存分配 ===\n", .{});
    const memory_stress = ExtremeMemoryStress{
        .allocation_cycles = 50_000, // 5万次分配
        .max_allocation_size = 1024 * 1024, // 最大1MB
        .allocator = allocator,
    };
    const memory_result = try runtime.blockOn(memory_stress);
    try results.append(memory_result);
    try stdout.print("{}\n", .{memory_result});

    // 压力测试3: 高频I/O操作
    try stdout.print("=== 压力测试3: 高频I/O操作 ===\n", .{});
    const io_stress = HighFrequencyIoStress{
        .io_operations = 100_000, // 10万次I/O操作
        .concurrent_connections = 1000, // 1000个并发连接
    };
    const io_result = try runtime.blockOn(io_stress);
    try results.append(io_result);
    try stdout.print("{}\n", .{io_result});

    // 压力测试总结
    try stdout.print("\n=== 压力测试总结 ===\n", .{});
    var total_ops: u64 = 0;
    var total_duration: u64 = 0;
    var min_success_rate: f64 = 1.0;

    for (results.items) |result| {
        total_ops += result.operations_completed;
        total_duration += result.duration_ms;
        if (result.success_rate < min_success_rate) {
            min_success_rate = result.success_rate;
        }
    }

    try stdout.print("总操作数: {}\n", .{total_ops});
    try stdout.print("总耗时: {}ms\n", .{total_duration});
    try stdout.print("平均操作/秒: {d:.2}\n", .{@as(f64, @floatFromInt(total_ops)) / (@as(f64, @floatFromInt(total_duration)) / 1000.0)});
    try stdout.print("最低成功率: {d:.2}%\n", .{min_success_rate * 100});

    if (min_success_rate >= 0.95) {
        try stdout.print("\n✓ 所有压力测试通过！Zokio在高负载下表现优异！\n", .{});
    } else {
        try stdout.print("\n⚠ 部分测试成功率较低，需要进一步优化\n", .{});
    }
}
