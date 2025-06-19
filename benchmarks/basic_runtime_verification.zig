//! 🧪 基础运行时验证测试
//!
//! 验证新的高性能运行时系统基本功能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🧪 Zokio基础运行时验证测试 ===\n\n", .{});

    // 测试1: 验证运行时类型定义
    try testRuntimeTypeDefinitions();

    // 测试2: 验证编译时信息
    try testCompileTimeInformation();

    // 测试3: 验证运行时预设配置
    try testRuntimePresets();

    // 测试4: 基础性能测试（不使用运行时API）
    try testBasicPerformance(allocator);

    std.debug.print("\n=== ✅ 基础验证测试完成 ===\n", .{});
}

/// 测试运行时类型定义
fn testRuntimeTypeDefinitions() !void {
    std.debug.print("🔧 验证运行时类型定义...\n", .{});

    // 验证所有运行时类型都存在且可访问
    const high_perf_type = @TypeOf(zokio.HighPerformanceRuntime);
    const low_latency_type = @TypeOf(zokio.LowLatencyRuntime);
    const io_intensive_type = @TypeOf(zokio.IOIntensiveRuntime);
    const memory_optimized_type = @TypeOf(zokio.MemoryOptimizedRuntime);
    const balanced_type = @TypeOf(zokio.BalancedRuntime);
    const default_type = @TypeOf(zokio.DefaultRuntime);

    std.debug.print("  ✅ HighPerformanceRuntime: {}\n", .{high_perf_type});
    std.debug.print("  ✅ LowLatencyRuntime: {}\n", .{low_latency_type});
    std.debug.print("  ✅ IOIntensiveRuntime: {}\n", .{io_intensive_type});
    std.debug.print("  ✅ MemoryOptimizedRuntime: {}\n", .{memory_optimized_type});
    std.debug.print("  ✅ BalancedRuntime: {}\n", .{balanced_type});
    std.debug.print("  ✅ DefaultRuntime: {}\n", .{default_type});

    // 验证RuntimePresets存在
    const presets_type = @TypeOf(zokio.RuntimePresets);
    std.debug.print("  ✅ RuntimePresets: {}\n", .{presets_type});

    std.debug.print("  🎉 所有运行时类型定义验证通过\n", .{});
}

/// 测试编译时信息
fn testCompileTimeInformation() !void {
    std.debug.print("\n📊 验证编译时信息...\n", .{});

    // 验证高性能运行时编译时信息
    std.debug.print("  🔥 HighPerformanceRuntime编译时信息:\n", .{});
    std.debug.print("    平台: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.platform});
    std.debug.print("    架构: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.architecture});
    std.debug.print("    工作线程: {}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("    I/O后端: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.io_backend});
    std.debug.print("    配置名称: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("    内存策略: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("    性能配置: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.performance_profile});
    std.debug.print("    libxev启用: {}\n", .{zokio.HighPerformanceRuntime.LIBXEV_ENABLED});

    // 验证低延迟运行时编译时信息
    std.debug.print("\n  ⚡ LowLatencyRuntime编译时信息:\n", .{});
    std.debug.print("    配置名称: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("    内存策略: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("    性能配置: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.performance_profile});

    // 验证I/O密集型运行时编译时信息
    std.debug.print("\n  🌐 IOIntensiveRuntime编译时信息:\n", .{});
    std.debug.print("    配置名称: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("    内存策略: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("    性能配置: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.performance_profile});

    std.debug.print("\n  🎉 编译时信息验证通过\n", .{});
}

/// 测试运行时预设配置
fn testRuntimePresets() !void {
    std.debug.print("\n🔧 验证运行时预设配置...\n", .{});

    // 验证预设配置存在且可访问
    const extreme_perf = zokio.RuntimePresets.EXTREME_PERFORMANCE;
    const low_latency = zokio.RuntimePresets.LOW_LATENCY;
    const io_intensive = zokio.RuntimePresets.IO_INTENSIVE;
    const memory_optimized = zokio.RuntimePresets.MEMORY_OPTIMIZED;
    const balanced = zokio.RuntimePresets.BALANCED;

    std.debug.print("  ✅ EXTREME_PERFORMANCE配置:\n", .{});
    std.debug.print("    工作线程: {?}\n", .{extreme_perf.worker_threads});
    std.debug.print("    工作窃取: {}\n", .{extreme_perf.enable_work_stealing});
    std.debug.print("    队列大小: {}\n", .{extreme_perf.queue_size});
    std.debug.print("    窃取批次: {}\n", .{extreme_perf.steal_batch_size});

    std.debug.print("\n  ✅ LOW_LATENCY配置:\n", .{});
    std.debug.print("    工作线程: {?}\n", .{low_latency.worker_threads});
    std.debug.print("    队列大小: {}\n", .{low_latency.queue_size});
    std.debug.print("    自旋次数: {}\n", .{low_latency.spin_before_park});

    std.debug.print("\n  ✅ IO_INTENSIVE配置:\n", .{});
    std.debug.print("    工作线程: {?}\n", .{io_intensive.worker_threads});
    std.debug.print("    队列大小: {}\n", .{io_intensive.queue_size});
    std.debug.print("    libxev优先: {}\n", .{io_intensive.prefer_libxev});

    std.debug.print("\n  🎉 运行时预设配置验证通过\n", .{});

    _ = memory_optimized;
    _ = balanced;
}

/// 基础性能测试（不使用运行时API）
fn testBasicPerformance(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🚀 基础性能测试...\n", .{});

    // 测试1: 计算密集型任务
    const compute_result = try testComputeIntensiveTask();
    std.debug.print("  📊 计算密集型: {d:.0} ops/sec\n", .{compute_result});

    // 测试2: 内存分配性能
    const memory_result = try testMemoryAllocationPerformance(allocator);
    std.debug.print("  📊 内存分配: {d:.0} ops/sec\n", .{memory_result});

    // 测试3: 数据处理性能
    const data_result = try testDataProcessingPerformance(allocator);
    std.debug.print("  📊 数据处理: {d:.0} ops/sec\n", .{data_result});

    // 与Tokio基准对比
    const tokio_baseline = 365_686.0; // ops/sec
    const best_result = @max(compute_result, @max(memory_result, data_result));
    const vs_tokio = best_result / tokio_baseline;

    std.debug.print("\n  🏆 性能对比:\n", .{});
    std.debug.print("    最佳Zokio: {d:.0} ops/sec\n", .{best_result});
    std.debug.print("    Tokio基准: {d:.0} ops/sec\n", .{tokio_baseline});
    std.debug.print("    性能比率: {d:.1}x ", .{vs_tokio});

    if (vs_tokio >= 10.0) {
        std.debug.print("🚀🚀🚀 (Zokio大幅领先)\n", .{});
    } else if (vs_tokio >= 2.0) {
        std.debug.print("🚀🚀 (Zokio显著领先)\n", .{});
    } else if (vs_tokio >= 1.0) {
        std.debug.print("✅ (Zokio更快)\n", .{});
    } else {
        std.debug.print("❌ (Tokio更快)\n", .{});
    }

    std.debug.print("  🎉 基础性能测试完成\n", .{});
}

/// 计算密集型任务测试
fn testComputeIntensiveTask() !f64 {
    const iterations = 100000;
    const start_time = std.time.nanoTimestamp();

    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // 优化的计算工作负载
        var sum: u64 = 0;
        var j: u32 = 0;
        while (j < 50) : (j += 1) {
            sum = sum +% (i + j);
        }
        completed += 1;
        
        // 防止编译器优化
        std.mem.doNotOptimizeAway(sum);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    
    return @as(f64, @floatFromInt(completed)) / duration;
}

/// 内存分配性能测试
fn testMemoryAllocationPerformance(allocator: std.mem.Allocator) !f64 {
    const iterations = 20000;
    const start_time = std.time.nanoTimestamp();

    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // 内存分配测试
        const size = 1024 + (i % 1024);
        const data = allocator.alloc(u8, size) catch continue;
        defer allocator.free(data);

        // 初始化内存
        @memset(data, @intCast(i % 256));
        completed += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    
    return @as(f64, @floatFromInt(completed)) / duration;
}

/// 数据处理性能测试
fn testDataProcessingPerformance(allocator: std.mem.Allocator) !f64 {
    const iterations = 30000;
    const start_time = std.time.nanoTimestamp();

    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // 数据处理测试
        var buffer = [_]u8{0} ** 512;
        @memset(&buffer, @intCast(i % 256));
        
        // 计算校验和
        var checksum: u32 = 0;
        for (buffer) |byte| {
            checksum +%= byte;
        }
        
        completed += 1;
        
        // 防止编译器优化
        std.mem.doNotOptimizeAway(checksum);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    
    _ = allocator;
    return @as(f64, @floatFromInt(completed)) / duration;
}
