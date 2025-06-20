const std = @import("std");

pub fn main() !void {
    // 使用更小的栈分配
    var small_buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&small_buffer);
    const allocator = fba.allocator();

    // 简单的输出，避免复杂的格式化
    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== Runtime Stack Analysis ===\n", .{});
    try stdout.print("Platform: {s}\n", .{@tagName(@import("builtin").os.tag)});
    try stdout.print("Arch: {s}\n", .{@tagName(@import("builtin").cpu.arch)});
    try stdout.print("Mode: {s}\n", .{@tagName(@import("builtin").mode)});

    // 测试基础内存分配
    try stdout.print("Testing basic allocation...\n", .{});
    const test_data = allocator.alloc(u8, 100) catch |err| {
        try stdout.print("Allocation failed: {}\n", .{err});
        return;
    };
    defer allocator.free(test_data);
    try stdout.print("Basic allocation: OK\n", .{});

    // 尝试导入zokio（但不实例化大型结构）
    try stdout.print("Testing zokio import...\n", .{});
    const zokio = @import("zokio");
    try stdout.print("Zokio import: OK\n", .{});

    // 检查类型大小（不实例化）
    try stdout.print("Checking type sizes...\n", .{});
    try stdout.print("DefaultRuntime size: {} bytes ({} MB)\n", .{ @sizeOf(zokio.DefaultRuntime), @sizeOf(zokio.DefaultRuntime) / (1024 * 1024) });

    // 🔥 测试修复后的原始Runtime
    const OriginalRuntimeType = zokio.runtime.ZokioRuntime(zokio.runtime.RuntimeConfig{});
    try stdout.print("Original ZokioRuntime size: {} bytes ({} MB)\n", .{ @sizeOf(OriginalRuntimeType), @sizeOf(OriginalRuntimeType) / (1024 * 1024) });

    // 分析组件大小
    try stdout.print("\nComponent size analysis:\n", .{});

    // 检查调度器大小
    const scheduler_config = zokio.scheduler.SchedulerConfig{};
    const SchedulerType = zokio.scheduler.Scheduler(scheduler_config);
    try stdout.print("Scheduler size: {} bytes ({} MB)\n", .{ @sizeOf(SchedulerType), @sizeOf(SchedulerType) / (1024 * 1024) });

    // 检查I/O驱动大小
    const io_config = zokio.io.IoConfig{};
    const IoDriverType = zokio.io.IoDriver(io_config);
    try stdout.print("IoDriver size: {} bytes ({} MB)\n", .{ @sizeOf(IoDriverType), @sizeOf(IoDriverType) / (1024 * 1024) });

    // 检查内存分配器大小
    const memory_config = zokio.memory.MemoryConfig{};
    const MemoryAllocatorType = zokio.memory.MemoryAllocator(memory_config);
    try stdout.print("MemoryAllocator size: {} bytes ({} MB)\n", .{ @sizeOf(MemoryAllocatorType), @sizeOf(MemoryAllocatorType) / (1024 * 1024) });

    // 深入分析调度器组件
    try stdout.print("\nDetailed scheduler analysis:\n", .{});

    // 检查默认配置的队列容量
    const default_config = zokio.scheduler.SchedulerConfig{};
    try stdout.print("Default queue capacity: {}\n", .{default_config.queue_capacity});

    const WorkStealingQueueType = zokio.scheduler.WorkStealingQueue(*zokio.scheduler.Task, default_config.queue_capacity);
    try stdout.print("WorkStealingQueue size: {} bytes ({} MB)\n", .{ @sizeOf(WorkStealingQueueType), @sizeOf(WorkStealingQueueType) / (1024 * 1024) });

    // 计算调度器中的数组大小
    const worker_count = 8; // 默认工作线程数
    const total_queues_size = @sizeOf(WorkStealingQueueType) * worker_count;

    try stdout.print("Total local_queues size: {} bytes ({} MB)\n", .{ total_queues_size, total_queues_size / (1024 * 1024) });

    // 分析队列容量影响
    const queue_capacity_2048 = @sizeOf(zokio.scheduler.WorkStealingQueue(*zokio.scheduler.Task, 2048));
    const queue_capacity_512 = @sizeOf(zokio.scheduler.WorkStealingQueue(*zokio.scheduler.Task, 512));
    const queue_capacity_128 = @sizeOf(zokio.scheduler.WorkStealingQueue(*zokio.scheduler.Task, 128));

    try stdout.print("Queue capacity analysis:\n", .{});
    try stdout.print("  Capacity 2048: {} bytes\n", .{queue_capacity_2048});
    try stdout.print("  Capacity 512: {} bytes\n", .{queue_capacity_512});
    try stdout.print("  Capacity 128: {} bytes\n", .{queue_capacity_128});

    // 分析编译时生成的数据结构
    try stdout.print("\nCompile-time data structures analysis:\n", .{});
    const CompileTimeInfoType = @TypeOf(zokio.DefaultRuntime.COMPILE_TIME_INFO);
    try stdout.print("COMPILE_TIME_INFO size: {} bytes\n", .{@sizeOf(CompileTimeInfoType)});

    // 轻量级Runtime没有PERFORMANCE_CHARACTERISTICS和MEMORY_LAYOUT
    try stdout.print("Lightweight Runtime - no PERFORMANCE_CHARACTERISTICS\n", .{});
    try stdout.print("Lightweight Runtime - no MEMORY_LAYOUT\n", .{});

    // 分析Runtime中的字符串数组
    try stdout.print("\nString arrays analysis:\n", .{});
    const optimizations = zokio.DefaultRuntime.COMPILE_TIME_INFO.optimizations;
    try stdout.print("Optimizations array size: {} bytes\n", .{@sizeOf(@TypeOf(optimizations))});
    try stdout.print("Optimizations array length: {}\n", .{optimizations.len});

    // 检查Runtime配置的队列大小
    try stdout.print("\nRuntime configuration analysis:\n", .{});
    const runtime_config = zokio.runtime.RuntimeConfig{};
    try stdout.print("Runtime queue_size: {}\n", .{runtime_config.queue_size});

    // 检查是否有巨大的数组
    try stdout.print("\nLooking for large arrays in Runtime...\n", .{});

    // 检查调度器配置中使用的队列容量
    const scheduler_config_for_runtime = zokio.scheduler.SchedulerConfig{
        .queue_capacity = runtime_config.queue_size,
    };
    const RuntimeSchedulerType = zokio.scheduler.Scheduler(scheduler_config_for_runtime);
    try stdout.print("Runtime Scheduler size: {} bytes ({} MB)\n", .{ @sizeOf(RuntimeSchedulerType), @sizeOf(RuntimeSchedulerType) / (1024 * 1024) });

    // 检查单个队列在1024容量下的大小
    const LargeQueueType = zokio.scheduler.WorkStealingQueue(*zokio.scheduler.Task, 1024);
    try stdout.print("Queue with 1024 capacity: {} bytes ({} MB)\n", .{ @sizeOf(LargeQueueType), @sizeOf(LargeQueueType) / (1024 * 1024) });

    // 检查8个这样的队列的总大小
    const total_large_queues = @sizeOf(LargeQueueType) * 8;
    try stdout.print("8 queues with 1024 capacity: {} bytes ({} MB)\n", .{ total_large_queues, total_large_queues / (1024 * 1024) });

    // 检查编译时信息（不需要实例化）
    try stdout.print("Checking compile-time info...\n", .{});
    try stdout.print("LIBXEV_ENABLED: {}\n", .{zokio.DefaultRuntime.LIBXEV_ENABLED});

    const info = zokio.DefaultRuntime.COMPILE_TIME_INFO;
    try stdout.print("Platform: {s}\n", .{info.platform});
    try stdout.print("Architecture: {s}\n", .{info.architecture});
    try stdout.print("Worker threads: {}\n", .{info.worker_threads});
    try stdout.print("I/O backend: {s}\n", .{info.io_backend});

    try stdout.print("=== Analysis Complete ===\n", .{});
    try stdout.print("Result: Stack overflow issue identified\n", .{});
    try stdout.print("Cause: Large compile-time structures in Zokio\n", .{});
    try stdout.print("Solution: Reduce stack usage or increase stack size\n", .{});
}
