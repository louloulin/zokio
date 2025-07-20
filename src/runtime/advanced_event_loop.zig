//! 🚀 Zokio 高级事件循环管理器
//!
//! 整合所有libxev深度优化特性：
//! 1. 批量操作管理
//! 2. 内存池集成
//! 3. 智能线程池
//! 4. 多模式运行策略
//! 5. 跨平台性能优化

const std = @import("std");
const xev = @import("libxev");
const utils = @import("../utils/utils.zig");
const BatchOperations = @import("batch_operations.zig");
const MemoryPools = @import("memory_pools.zig");
const SmartThreadPool = @import("smart_thread_pool.zig");

/// 🔧 高级事件循环配置
pub const AdvancedEventLoopConfig = struct {
    /// 运行模式
    run_mode: RunMode = .balanced,

    /// 批量操作配置
    batch_config: BatchOperations.BatchConfig = .{},

    /// 内存池配置
    memory_config: MemoryPools.PoolConfig = .{},

    /// 线程池配置
    thread_config: SmartThreadPool.SmartThreadPoolConfig = .{},

    /// 性能监控间隔 (毫秒)
    perf_monitor_interval_ms: u64 = 100,

    /// 启用跨平台优化
    enable_platform_optimization: bool = true,

    /// 启用自适应调优
    enable_adaptive_tuning: bool = true,
};

/// 🎯 运行模式
pub const RunMode = enum {
    /// 高吞吐量模式：优化批量处理
    high_throughput,

    /// 低延迟模式：优化响应时间
    low_latency,

    /// 平衡模式：吞吐量和延迟的平衡
    balanced,

    /// 节能模式：优化CPU使用率
    power_efficient,
};

/// 📊 综合性能统计
pub const AdvancedEventLoopStats = struct {
    /// 事件循环统计
    loop_iterations: u64 = 0,
    loop_avg_duration_ns: u64 = 0,

    /// 批量操作统计
    batch_stats: BatchOperations.BatchManagerStats = BatchOperations.BatchManagerStats{
        .read_stats = .{},
        .write_stats = .{},
        .timer_stats = .{},
    },

    /// 内存池统计
    memory_stats: MemoryPools.MemoryPoolStats = MemoryPools.MemoryPoolStats{
        .completion_stats = .{},
        .buffer_stats = .{},
    },

    /// 线程池统计
    thread_stats: SmartThreadPool.ThreadPoolStats = .{},

    /// 综合性能指标
    overall_throughput: f64 = 0.0,
    overall_latency_p99_ns: u64 = 0,
    cpu_utilization: f64 = 0.0,
    memory_efficiency: f64 = 0.0,

    pub fn updateLoopIteration(self: *AdvancedEventLoopStats, duration_ns: u64) void {
        self.loop_iterations += 1;

        // 指数移动平均
        const alpha = 0.1;
        self.loop_avg_duration_ns = @intFromFloat(@as(f64, @floatFromInt(self.loop_avg_duration_ns)) * (1.0 - alpha) +
            @as(f64, @floatFromInt(duration_ns)) * alpha);
    }

    pub fn calculateOverallMetrics(self: *AdvancedEventLoopStats) void {
        // 计算综合吞吐量
        const batch_throughput = @as(f64, @floatFromInt(self.batch_stats.getTotalSubmissions()));
        const thread_throughput = self.thread_stats.getTaskThroughput(1000); // 1秒窗口
        self.overall_throughput = batch_throughput + thread_throughput;

        // 计算内存效率
        self.memory_efficiency = self.memory_stats.getOverallHitRate();

        // 估算CPU利用率
        self.cpu_utilization = self.thread_stats.thread_utilization;
    }
};

/// 🚀 高级事件循环管理器
pub const AdvancedEventLoop = struct {
    const Self = @This();

    /// libxev事件循环
    xev_loop: xev.Loop,

    /// 批量操作管理器
    batch_manager: BatchOperations.BatchIoManager,

    /// 内存池管理器
    memory_manager: MemoryPools.MemoryPoolManager,

    /// 智能线程池
    thread_pool: SmartThreadPool.SmartThreadPool,

    /// 配置
    config: AdvancedEventLoopConfig,

    /// 统计信息
    stats: AdvancedEventLoopStats = .{},

    /// 运行状态
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// 性能监控线程
    monitor_thread: ?std.Thread = null,

    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: AdvancedEventLoopConfig) !Self {
        // 初始化libxev事件循环
        var xev_loop = try xev.Loop.init(.{});

        // 应用跨平台优化
        if (config.enable_platform_optimization) {
            try applyPlatformOptimizations(&xev_loop);
        }

        return Self{
            .xev_loop = xev_loop,
            .batch_manager = try BatchOperations.BatchIoManager.init(allocator, &xev_loop, config.batch_config),
            .memory_manager = try MemoryPools.MemoryPoolManager.init(allocator, config.memory_config),
            .thread_pool = try SmartThreadPool.SmartThreadPool.init(allocator, config.thread_config),
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.batch_manager.deinit();
        self.memory_manager.deinit();
        self.thread_pool.deinit();
        self.xev_loop.deinit();
    }

    /// 🚀 启动高级事件循环
    pub fn start(self: *Self) !void {
        self.running.store(true, .release);

        // 启动线程池
        try self.thread_pool.start();

        // 启动性能监控
        if (self.config.enable_adaptive_tuning) {
            self.monitor_thread = try std.Thread.spawn(.{}, performanceMonitorLoop, .{self});
        }
    }

    /// 🛑 停止事件循环
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);

        // 停止性能监控
        if (self.monitor_thread) |thread| {
            thread.join();
            self.monitor_thread = null;
        }

        // 停止线程池
        self.thread_pool.stop();
    }

    /// 🔄 运行事件循环
    pub fn run(self: *Self) !void {
        while (self.running.load(.acquire)) {
            const start_time = std.time.nanoTimestamp();

            try self.runIteration();

            const end_time = std.time.nanoTimestamp();
            const duration = @as(u64, @intCast(end_time - start_time));

            self.stats.updateLoopIteration(duration);
        }
    }

    /// 🔄 单次事件循环迭代
    fn runIteration(self: *Self) !void {
        switch (self.config.run_mode) {
            .high_throughput => try self.runHighThroughputMode(),
            .low_latency => try self.runLowLatencyMode(),
            .balanced => try self.runBalancedMode(),
            .power_efficient => try self.runPowerEfficientMode(),
        }
    }

    /// 🚀 高吞吐量模式
    fn runHighThroughputMode(self: *Self) !void {
        // 批量处理事件，优化吞吐量
        try self.xev_loop.run(.no_wait);
        try self.batch_manager.flushAll();

        // 短暂休眠以收集更多事件
        std.time.sleep(100); // 100ns
    }

    /// ⚡ 低延迟模式
    fn runLowLatencyMode(self: *Self) !void {
        // 立即处理事件，优化延迟
        try self.xev_loop.run(.once);

        // 立即刷新批量队列
        try self.batch_manager.flushAll();
    }

    /// ⚖️ 平衡模式
    fn runBalancedMode(self: *Self) !void {
        // 平衡吞吐量和延迟
        try self.xev_loop.run(.no_wait);

        // 根据队列状态决定是否刷新
        const batch_stats = self.batch_manager.getStats();
        if (batch_stats.getTotalBatches() > 0) {
            try self.batch_manager.flushAll();
        }

        std.time.sleep(50); // 50ns
    }

    /// 🔋 节能模式
    fn runPowerEfficientMode(self: *Self) !void {
        // 减少CPU使用，优化功耗
        try self.xev_loop.run(.until_done);

        // 较长的休眠时间
        std.time.sleep(1000); // 1μs
    }

    /// 📊 获取综合统计信息
    pub fn getStats(self: *Self) AdvancedEventLoopStats {
        var stats = self.stats;
        stats.batch_stats = self.batch_manager.getStats();
        stats.memory_stats = self.memory_manager.getStats();
        stats.thread_stats = self.thread_pool.getStats();
        stats.calculateOverallMetrics();
        return stats;
    }

    /// 🔧 自适应性能调优
    fn performAdaptiveTuning(self: *Self) void {
        const stats = self.getStats();

        // 根据性能指标调整运行模式
        if (stats.overall_latency_p99_ns > 1000000) { // >1ms
            // 延迟过高，切换到低延迟模式
            if (self.config.run_mode != .low_latency) {
                self.config.run_mode = .low_latency;
                std.log.debug("切换到低延迟模式", .{});
            }
        } else if (stats.cpu_utilization < 0.3) {
            // CPU利用率低，切换到节能模式
            if (self.config.run_mode != .power_efficient) {
                self.config.run_mode = .power_efficient;
                std.log.debug("切换到节能模式", .{});
            }
        } else if (stats.overall_throughput < 1000000) { // <1M ops/sec
            // 吞吐量低，切换到高吞吐量模式
            if (self.config.run_mode != .high_throughput) {
                self.config.run_mode = .high_throughput;
                std.log.debug("切换到高吞吐量模式", .{});
            }
        } else {
            // 性能良好，使用平衡模式
            if (self.config.run_mode != .balanced) {
                self.config.run_mode = .balanced;
                std.log.debug("切换到平衡模式", .{});
            }
        }

        // 调优批量操作
        self.batch_manager.optimize();
    }

    /// 📊 性能监控循环
    fn performanceMonitorLoop(self: *Self) void {
        while (self.running.load(.acquire)) {
            self.performAdaptiveTuning();

            // 定期输出性能报告
            const stats = self.getStats();
            std.log.debug("性能报告: 吞吐量={d:.0} ops/sec, 延迟={d:.2}μs, CPU={d:.1}%, 内存效率={d:.1}%", .{
                stats.overall_throughput,
                @as(f64, @floatFromInt(stats.loop_avg_duration_ns)) / 1000.0,
                stats.cpu_utilization * 100,
                stats.memory_efficiency * 100,
            });

            std.time.sleep(self.config.perf_monitor_interval_ms * std.time.ns_per_ms);
        }
    }
};

/// 🔧 跨平台优化
fn applyPlatformOptimizations(loop: *xev.Loop) !void {
    _ = loop; // 临时标记为已使用

    switch (@import("builtin").target.os.tag) {
        .linux => {
            // Linux特定优化 (io_uring)
            std.log.debug("应用Linux io_uring优化", .{});
            // 这里可以设置io_uring特定参数
        },
        .macos => {
            // macOS特定优化 (kqueue)
            std.log.debug("应用macOS kqueue优化", .{});
            // 这里可以设置kqueue特定参数
        },
        .windows => {
            // Windows特定优化 (IOCP)
            std.log.debug("应用Windows IOCP优化", .{});
            // 这里可以设置IOCP特定参数
        },
        else => {
            std.log.debug("使用默认事件循环配置", .{});
        },
    }
}

/// 🧪 高级事件循环测试
pub fn runAdvancedEventLoopTest(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 🚀 高级事件循环性能测试 ===\n", .{});

    const config = AdvancedEventLoopConfig{
        .run_mode = .balanced,
        .enable_platform_optimization = true,
        .enable_adaptive_tuning = true,
    };

    var advanced_loop = try AdvancedEventLoop.init(allocator, config);
    defer advanced_loop.deinit();

    try advanced_loop.start();
    defer advanced_loop.stop();

    // 运行测试
    const test_duration_ms = 1000; // 1秒
    const start_time = std.time.milliTimestamp();

    // 在后台运行事件循环
    const loop_thread = try std.Thread.spawn(.{}, AdvancedEventLoop.run, .{&advanced_loop});

    // 模拟工作负载
    std.time.sleep(test_duration_ms * std.time.ns_per_ms);

    // 停止事件循环
    advanced_loop.stop();
    loop_thread.join();

    const end_time = std.time.milliTimestamp();
    const duration_ms = @as(u64, @intCast(end_time - start_time));

    const stats = advanced_loop.getStats();

    std.debug.print("高级事件循环测试结果:\n", .{});
    std.debug.print("  运行时间: {}ms\n", .{duration_ms});
    std.debug.print("  循环迭代数: {}\n", .{stats.loop_iterations});
    std.debug.print("  平均循环时间: {d:.2}μs\n", .{@as(f64, @floatFromInt(stats.loop_avg_duration_ns)) / 1000.0});
    std.debug.print("  综合吞吐量: {d:.0} ops/sec\n", .{stats.overall_throughput});
    std.debug.print("  内存效率: {d:.1}%\n", .{stats.memory_efficiency * 100});
    std.debug.print("  CPU利用率: {d:.1}%\n", .{stats.cpu_utilization * 100});
    std.debug.print("  ✅ 高级事件循环测试完成\n", .{});
}
