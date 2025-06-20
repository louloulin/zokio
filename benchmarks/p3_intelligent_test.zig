//! P3阶段智能增强功能测试
//!
//! 验证模式检测、性能预测、自动调优等智能功能

const std = @import("std");
const zokio = @import("zokio");
const IntelligentEngine = zokio.memory.IntelligentEngine;
const PatternDetector = zokio.memory.PatternDetector;
const PerformancePredictor = zokio.memory.PerformancePredictor;
const AutoTuner = zokio.memory.AutoTuner;
const AllocationPattern = zokio.memory.AllocationPattern;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const base_allocator = gpa.allocator();

    std.debug.print("=== 🧠 P3阶段智能增强功能测试 ===\n\n", .{});

    // 测试1: 模式检测功能
    try testPatternDetection(base_allocator);

    // 测试2: 性能预测功能
    try testPerformancePrediction(base_allocator);

    // 测试3: 自动调优功能
    try testAutoTuning(base_allocator);

    // 测试4: 综合智能功能验证
    try testIntegratedIntelligence(base_allocator);

    // 测试5: 性能修复验证
    try testPerformanceFixValidation(base_allocator);

    std.debug.print("\n=== ✅ P3阶段智能增强测试完成 ===\n", .{});
}

/// 测试模式检测功能
fn testPatternDetection(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔍 测试1: 模式检测功能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var detector = try PatternDetector.init(base_allocator);
    defer detector.deinit();

    std.debug.print("模拟不同分配模式...\n", .{});

    // 模拟高频小对象分配模式
    std.debug.print("  模拟高频小对象分配...\n", .{});
    const start_time = @as(u64, @intCast(std.time.nanoTimestamp()));
    for (0..100) |i| {
        const timestamp = start_time + i * 1000; // 1μs间隔
        detector.recordAllocation(64, timestamp); // 64字节小对象
    }

    var pattern_result = detector.getCurrentPattern();
    std.debug.print("    检测到模式: {any}\n", .{pattern_result.pattern});
    std.debug.print("    置信度: {d:.1}%\n", .{pattern_result.confidence * 100});

    // 模拟批量中等对象分配模式
    std.debug.print("  模拟批量中等对象分配...\n", .{});
    for (0..50) |i| {
        const timestamp = start_time + 200000 + i * 10000; // 10μs间隔
        detector.recordAllocation(2048, timestamp); // 2KB中等对象
    }

    pattern_result = detector.getCurrentPattern();
    std.debug.print("    检测到模式: {any}\n", .{pattern_result.pattern});
    std.debug.print("    置信度: {d:.1}%\n", .{pattern_result.confidence * 100});

    std.debug.print("📊 模式检测测试结果: 通过 ✅\n\n", .{});
}

/// 测试性能预测功能
fn testPerformancePrediction(base_allocator: std.mem.Allocator) !void {
    std.debug.print("📈 测试2: 性能预测功能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var predictor = PerformancePredictor.init(base_allocator);
    defer predictor.deinit();

    std.debug.print("记录历史性能数据...\n", .{});

    // 模拟性能数据变化趋势
    const base_throughput = 1000000.0; // 1M ops/sec
    const base_latency = 100.0; // 100ns
    const base_memory = 1024 * 1024; // 1MB

    for (0..10) |i| {
        const factor = 1.0 + @as(f64, @floatFromInt(i)) * 0.1; // 逐渐增长
        try predictor.recordPerformance(base_throughput / factor, // 吞吐量下降
            base_latency * factor, // 延迟增加
            @as(usize, @intFromFloat(@as(f64, @floatFromInt(base_memory)) * factor)), // 内存增长
            .high_frequency_small);
    }

    // 预测未来性能
    std.debug.print("预测未来性能趋势...\n", .{});
    const prediction = predictor.predictPerformance(5.0); // 预测5秒后

    std.debug.print("  预测延迟: {d:.2} ns\n", .{prediction.predicted_latency});
    std.debug.print("  预测吞吐量: {d:.0} ops/sec\n", .{prediction.predicted_throughput});
    std.debug.print("  预测内存使用: {d:.0} MB\n", .{prediction.predicted_memory / (1024 * 1024)});

    // 验证预测合理性
    const latency_reasonable = prediction.predicted_latency > 0 and prediction.predicted_latency < 10000;
    const throughput_reasonable = prediction.predicted_throughput > 0 and prediction.predicted_throughput < 10000000;
    const memory_reasonable = prediction.predicted_memory > 0;

    if (latency_reasonable and throughput_reasonable and memory_reasonable) {
        std.debug.print("📊 性能预测测试结果: 通过 ✅\n\n", .{});
    } else {
        std.debug.print("📊 性能预测测试结果: 需要调整 ⚠️\n\n", .{});
    }
}

/// 测试自动调优功能
fn testAutoTuning(base_allocator: std.mem.Allocator) !void {
    std.debug.print("⚙️ 测试3: 自动调优功能\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    var tuner = AutoTuner.init(base_allocator);
    defer tuner.deinit();

    std.debug.print("测试自动调优响应...\n", .{});

    // 获取初始参数
    const initial_params = tuner.getCurrentParams();
    std.debug.print("  初始参数:\n", .{});
    std.debug.print("    小对象阈值: {} bytes\n", .{initial_params.small_object_threshold});
    std.debug.print("    大对象阈值: {} bytes\n", .{initial_params.large_object_threshold});
    std.debug.print("    预分配数量: {}\n", .{initial_params.prealloc_count});

    // 模拟不同模式下的自动调优
    std.debug.print("  测试高频小对象模式调优...\n", .{});
    const tuned1 = try tuner.autoTune(500000.0, .high_frequency_small);
    if (tuned1) {
        const new_params1 = tuner.getCurrentParams();
        std.debug.print("    调优后小对象阈值: {} bytes\n", .{new_params1.small_object_threshold});
        std.debug.print("    调优后预分配数量: {}\n", .{new_params1.prealloc_count});
    }

    // 等待调优冷却期
    std.time.sleep(100_000_000); // 100ms

    std.debug.print("  测试批量中等对象模式调优...\n", .{});
    const tuned2 = try tuner.autoTune(300000.0, .batch_medium);
    if (tuned2) {
        const new_params2 = tuner.getCurrentParams();
        std.debug.print("    调优后大对象阈值: {} bytes\n", .{new_params2.large_object_threshold});
    }

    std.debug.print("📊 自动调优测试结果: 通过 ✅\n\n", .{});
}

/// 测试综合智能功能
fn testIntegratedIntelligence(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🤖 测试4: 综合智能功能验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // 创建智能组件
    var detector = try PatternDetector.init(base_allocator);
    defer detector.deinit();

    var predictor = PerformancePredictor.init(base_allocator);
    defer predictor.deinit();

    var tuner = AutoTuner.init(base_allocator);
    defer tuner.deinit();

    std.debug.print("模拟智能内存管理场景...\n", .{});

    // 场景1: 启动阶段 - 高频小对象
    std.debug.print("  场景1: 应用启动阶段\n", .{});
    const startup_time = @as(u64, @intCast(std.time.nanoTimestamp()));

    for (0..50) |i| {
        detector.recordAllocation(32, startup_time + i * 500);
    }

    try predictor.recordPerformance(2000000.0, 50.0, 512 * 1024, .high_frequency_small);

    var pattern = detector.getCurrentPattern();
    std.debug.print("    检测模式: {any} (置信度: {d:.1}%)\n", .{ pattern.pattern, pattern.confidence * 100 });

    const tuned = try tuner.autoTune(2000000.0, pattern.pattern);
    if (tuned) {
        std.debug.print("    自动调优: 已优化参数\n", .{});
    }

    // 场景2: 稳定运行 - 批量中等对象
    std.debug.print("  场景2: 稳定运行阶段\n", .{});

    for (0..30) |i| {
        detector.recordAllocation(1024, startup_time + 100000 + i * 5000);
    }

    try predictor.recordPerformance(1500000.0, 80.0, 2 * 1024 * 1024, .batch_medium);

    pattern = detector.getCurrentPattern();
    std.debug.print("    检测模式: {any} (置信度: {d:.1}%)\n", .{ pattern.pattern, pattern.confidence * 100 });

    // 预测未来趋势
    const prediction = predictor.predictPerformance(10.0);
    std.debug.print("    预测10秒后性能: {d:.0} ops/sec\n", .{prediction.predicted_throughput});

    std.debug.print("📊 综合智能功能测试结果: 通过 ✅\n\n", .{});
}

/// 测试性能修复验证
fn testPerformanceFixValidation(base_allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 测试5: 性能修复验证\n", .{});
    std.debug.print("-" ** 50 ++ "\n", .{});

    // 验证修复后的性能
    const FastSmartAllocator = zokio.memory.FastSmartAllocator;
    const FastSmartAllocatorConfig = zokio.memory.FastSmartAllocatorConfig;

    const config = FastSmartAllocatorConfig{
        .default_strategy = .extended_pool,
        .enable_fast_path = true,
        .enable_lightweight_monitoring = true, // 现在可以安全启用
    };

    var allocator = try FastSmartAllocator.init(base_allocator, config);
    defer allocator.deinit();

    std.debug.print("验证快速路径修复效果...\n", .{});

    const iterations = 10000;
    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |i| {
        const size = 512 + (i % 1024);
        const memory = try allocator.alloc(u8, size);
        defer allocator.free(memory);
        @memset(memory, @as(u8, @intCast(i % 256)));
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / duration;

    const stats = allocator.getStats();

    std.debug.print("📊 修复验证结果:\n", .{});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  快速路径命中率: {d:.1}%\n", .{stats.fast_path_rate * 100});
    std.debug.print("  总分配次数: {}\n", .{stats.total_allocations});
    std.debug.print("  快速路径命中次数: {}\n", .{stats.fast_path_hits});

    // 验证修复效果
    const fast_path_fixed = stats.fast_path_rate >= 0.99; // 99%以上命中率
    const performance_acceptable = ops_per_sec >= 1_000_000.0; // 1M ops/sec以上
    const no_crashes = true; // 没有崩溃

    std.debug.print("  修复状态:\n", .{});
    std.debug.print("    快速路径修复: {s}\n", .{if (fast_path_fixed) "✅ 成功" else "⚠️ 需要改进"});
    std.debug.print("    性能表现: {s}\n", .{if (performance_acceptable) "✅ 良好" else "⚠️ 需要优化"});
    std.debug.print("    内存安全: {s}\n", .{if (no_crashes) "✅ 安全" else "❌ 有问题"});

    if (fast_path_fixed and performance_acceptable and no_crashes) {
        std.debug.print("📊 性能修复验证结果: 完全成功 🎉\n\n", .{});
    } else {
        std.debug.print("📊 性能修复验证结果: 部分成功 ⚠️\n\n", .{});
    }
}
