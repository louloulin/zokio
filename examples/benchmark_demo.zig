//! 基准测试演示程序
//!
//! 展示Zokio的性能基准测试功能和与Tokio的对比

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 性能基准测试演示 ===\n", .{});

    // 演示1：基准测试管理器
    try demonstrateBenchmarkManager(allocator);

    // 演示2：性能指标收集
    try demonstrateMetricsCollection(allocator);

    // 演示3：性能分析器
    try demonstrateProfiler(allocator);

    // 演示4：与Tokio性能对比
    try demonstrateTokioComparison(allocator);

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

/// 演示基准测试管理器
fn demonstrateBenchmarkManager(allocator: std.mem.Allocator) !void {
    std.debug.print("\n1. 基准测试管理器演示\n", .{});

    const config = zokio.bench.BenchConfig{
        .warmup_iterations = 100,
        .test_iterations = 1000,
        .verbose = true,
    };

    var manager = zokio.bench.BenchmarkManager.init(allocator, config);
    defer manager.deinit();

    // 运行任务调度基准测试
    try manager.runBenchmark("任务调度", .task_scheduling, zokio.bench.benchmark.TaskSchedulingBenchmarks.simpleTaskCreation);

    // 运行I/O操作基准测试
    try manager.runBenchmark("I/O操作", .io_operations, zokio.bench.benchmark.IoOperationBenchmarks.memoryIoSimulation);

    // 运行内存分配基准测试
    try manager.runBenchmark("内存分配", .memory_allocation, zokio.bench.benchmark.MemoryAllocationBenchmarks.simpleAllocation);

    // 运行Future组合基准测试
    try manager.runBenchmark("Future组合", .future_composition, zokio.bench.benchmark.FutureCompositionBenchmarks.simpleFutureChain);

    // 运行并发操作基准测试
    try manager.runBenchmark("并发操作", .concurrency, zokio.bench.benchmark.ConcurrencyBenchmarks.atomicOperations);

    // 生成性能报告
    try manager.generateReport();
}

/// 演示性能指标收集
fn demonstrateMetricsCollection(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. 性能指标收集演示\n", .{});

    var metrics = zokio.bench.metrics.Metrics.init(allocator);
    defer metrics.deinit();

    // 模拟运行时指标
    var runtime = zokio.bench.metrics.RuntimeMetrics{
        .active_tasks = 150,
        .pending_tasks = 50,
        .completed_tasks = 10000,
        .worker_threads = 8,
        .idle_threads = 2,
        .task_queue_length = 25,
        .global_queue_length = 10,
        .work_steals = 500,
        .scheduling_latency_ns = 5000,
        .io_events = 2000,
        .timer_events = 300,
    };

    metrics.updateRuntime(runtime);

    // 更新系统指标
    try metrics.update();

    // 模拟一段时间的运行
    std.debug.print("模拟运行时指标收集...\n", .{});
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        // 模拟指标变化
        runtime.completed_tasks += 100;
        runtime.active_tasks = 120 + (i * 10);
        runtime.pending_tasks = 40 - (i * 5);
        runtime.work_steals += 50;
        
        metrics.updateRuntime(runtime);
        try metrics.update();
        
        // 模拟时间间隔
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    // 打印当前指标
    metrics.printCurrent();

    // 生成性能报告
    try metrics.generateReport();
}

/// 演示性能分析器
fn demonstrateProfiler(allocator: std.mem.Allocator) !void {
    std.debug.print("\n3. 性能分析器演示\n", .{});

    var profiler = zokio.bench.profiler.Profiler.init(allocator);
    defer profiler.deinit();

    // 模拟一些函数调用
    std.debug.print("模拟函数调用分析...\n", .{});

    // 模拟任务调度函数
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const timer = zokio.bench.profiler.Timer.start("task_schedule");
        
        // 模拟任务调度工作
        var j: u32 = 0;
        while (j < 1000) : (j += 1) {
            _ = j * j;
        }
        
        const duration = timer.end();
        try profiler.recordCall("task_schedule", duration);
    }

    // 模拟I/O操作函数
    i = 0;
    while (i < 50) : (i += 1) {
        const timer = zokio.bench.profiler.Timer.start("io_operation");
        
        // 模拟I/O操作工作
        var buffer: [1024]u8 = undefined;
        @memset(&buffer, @as(u8, @intCast(i % 256)));
        
        const duration = timer.end();
        try profiler.recordCall("io_operation", duration);
    }

    // 模拟内存分配函数
    i = 0;
    while (i < 200) : (i += 1) {
        const timer = zokio.bench.profiler.Timer.start("memory_alloc");
        
        // 模拟内存分配工作
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const temp_allocator = arena.allocator();
        
        const mem = temp_allocator.alloc(u8, 64) catch continue;
        @memset(mem, 0xFF);
        
        const duration = timer.end();
        try profiler.recordCall("memory_alloc", duration);
    }

    // 生成性能分析报告
    profiler.generateReport();

    // 导出JSON数据
    const json_data = try profiler.exportJson(allocator);
    defer allocator.free(json_data);
    std.debug.print("\n📄 性能数据已导出为JSON格式 ({} 字节)\n", .{json_data.len});
}

/// 演示与Tokio性能对比
fn demonstrateTokioComparison(allocator: std.mem.Allocator) !void {
    std.debug.print("\n4. 与Tokio性能对比演示\n", .{});

    // 检查是否要运行真实的Tokio基准测试
    const use_real_benchmarks = false; // 设置为true以运行真实的Tokio基准测试

    if (use_real_benchmarks) {
        std.debug.print("🚀 将运行真实的Tokio基准测试进行对比\n", .{});
        std.debug.print("⚠️  这需要安装Rust和Cargo环境\n", .{});
    } else {
        std.debug.print("📚 使用基于文献的Tokio基准数据进行对比\n", .{});
    }

    var comparison_manager = zokio.bench.comparison.ComparisonManager.init(allocator, use_real_benchmarks);
    defer comparison_manager.deinit();

    // 模拟Zokio的性能数据
    std.debug.print("生成Zokio性能数据...\n", .{});

    // 任务调度性能（模拟优于Tokio）
    var task_metrics = zokio.bench.PerformanceMetrics{};
    const task_latencies = [_]u64{ 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000 };
    task_metrics.calculate(&task_latencies);
    task_metrics.throughput_ops_per_sec = 1_200_000.0; // 比Tokio的1M更高

    const task_result = zokio.bench.comparison.ComparisonResult.create(
        task_metrics,
        zokio.bench.comparison.TokioBaselines.getStaticBaseline(.task_scheduling)
    );
    task_result.print("任务调度");

    if (use_real_benchmarks) {
        try comparison_manager.addComparison(task_metrics, .task_scheduling, 1000);
    } else {
        try comparison_manager.addComparisonStatic(task_metrics, .task_scheduling);
    }

    // I/O操作性能（模拟接近Tokio）
    var io_metrics = zokio.bench.PerformanceMetrics{};
    const io_latencies = [_]u64{ 15000, 18000, 22000, 25000, 30000, 35000, 40000, 45000 };
    io_metrics.calculate(&io_latencies);
    io_metrics.throughput_ops_per_sec = 480_000.0; // 略低于Tokio的500K

    const io_result = zokio.bench.comparison.ComparisonResult.create(
        io_metrics,
        zokio.bench.comparison.TokioBaselines.getStaticBaseline(.io_operations)
    );
    io_result.print("I/O操作");

    if (use_real_benchmarks) {
        try comparison_manager.addComparison(io_metrics, .io_operations, 1000);
    } else {
        try comparison_manager.addComparisonStatic(io_metrics, .io_operations);
    }

    // 网络操作性能（模拟优于Tokio）
    var network_metrics = zokio.bench.PerformanceMetrics{};
    const network_latencies = [_]u64{ 80000, 90000, 95000, 100000, 110000, 120000, 150000, 200000 };
    network_metrics.calculate(&network_latencies);
    network_metrics.throughput_ops_per_sec = 120_000.0; // 高于Tokio的100K

    const network_result = zokio.bench.comparison.ComparisonResult.create(
        network_metrics,
        zokio.bench.comparison.TokioBaselines.getStaticBaseline(.network_operations)
    );
    network_result.print("网络操作");

    if (use_real_benchmarks) {
        try comparison_manager.addComparison(network_metrics, .network_operations, 1000);
    } else {
        try comparison_manager.addComparisonStatic(network_metrics, .network_operations);
    }

    // 内存分配性能（模拟需要优化）
    var memory_metrics = zokio.bench.PerformanceMetrics{};
    const memory_latencies = [_]u64{ 150, 200, 250, 300, 350, 400, 500, 800 };
    memory_metrics.calculate(&memory_latencies);
    memory_metrics.throughput_ops_per_sec = 8_000_000.0; // 低于Tokio的10M

    const memory_result = zokio.bench.comparison.ComparisonResult.create(
        memory_metrics,
        zokio.bench.comparison.TokioBaselines.getStaticBaseline(.memory_allocation)
    );
    memory_result.print("内存分配");

    if (use_real_benchmarks) {
        try comparison_manager.addComparison(memory_metrics, .memory_allocation, 1000);
    } else {
        try comparison_manager.addComparisonStatic(memory_metrics, .memory_allocation);
    }

    // Future组合性能（模拟显著优于Tokio）
    var future_metrics = zokio.bench.PerformanceMetrics{};
    const future_latencies = [_]u64{ 300, 350, 400, 450, 500, 600, 800, 1200 };
    future_metrics.calculate(&future_latencies);
    future_metrics.throughput_ops_per_sec = 2_500_000.0; // 高于Tokio的2M

    const future_result = zokio.bench.comparison.ComparisonResult.create(
        future_metrics,
        zokio.bench.comparison.TokioBaselines.getStaticBaseline(.future_composition)
    );
    future_result.print("Future组合");

    if (use_real_benchmarks) {
        try comparison_manager.addComparison(future_metrics, .future_composition, 1000);
    } else {
        try comparison_manager.addComparisonStatic(future_metrics, .future_composition);
    }

    // 生成综合对比报告
    comparison_manager.generateReport();

    // 显示各项测试的摘要
    std.debug.print("\n📋 测试摘要:\n", .{});
    std.debug.print("  任务调度: {s}\n", .{task_result.generateSummary()});
    std.debug.print("  I/O操作: {s}\n", .{io_result.generateSummary()});
    std.debug.print("  网络操作: {s}\n", .{network_result.generateSummary()});
    std.debug.print("  内存分配: {s}\n", .{memory_result.generateSummary()});
    std.debug.print("  Future组合: {s}\n", .{future_result.generateSummary()});
}
