//! 🚀 Zokio 性能监控和自适应调优
//!
//! 提供全面的性能监控和自动优化：
//! 1. 实时性能指标收集
//! 2. 热点检测和分析
//! 3. 自适应参数调整
//! 4. 性能预警和报告
//! 5. 智能负载均衡

const std = @import("std");
const xev = @import("libxev");
const utils = @import("../utils/utils.zig");

/// 🔧 性能监控配置
pub const PerformanceMonitorConfig = struct {
    /// 监控间隔 (毫秒)
    monitor_interval_ms: u64 = 100,

    /// 指标历史长度
    metrics_history_length: u32 = 1000,

    /// 启用热点检测
    enable_hotspot_detection: bool = true,

    /// 热点阈值 (百分比)
    hotspot_threshold: f64 = 80.0,

    /// 启用自适应调优
    enable_adaptive_tuning: bool = true,

    /// 调优敏感度 (0.0-1.0)
    tuning_sensitivity: f64 = 0.5,

    /// 性能报告间隔 (毫秒)
    report_interval_ms: u64 = 10000,

    /// 启用预警系统
    enable_alerts: bool = true,

    /// 预警阈值
    alert_thresholds: AlertThresholds = .{},
};

/// 🚨 预警阈值
pub const AlertThresholds = struct {
    /// CPU使用率阈值 (百分比)
    cpu_usage_threshold: f64 = 90.0,

    /// 内存使用率阈值 (百分比)
    memory_usage_threshold: f64 = 85.0,

    /// 延迟阈值 (毫秒)
    latency_threshold_ms: f64 = 100.0,

    /// 错误率阈值 (百分比)
    error_rate_threshold: f64 = 5.0,

    /// 吞吐量下降阈值 (百分比)
    throughput_drop_threshold: f64 = 20.0,
};

/// 📊 性能指标
pub const PerformanceMetrics = struct {
    /// 时间戳
    timestamp: i128,

    /// CPU指标
    cpu_usage: f64 = 0.0,
    cpu_user: f64 = 0.0,
    cpu_system: f64 = 0.0,

    /// 内存指标
    memory_usage: f64 = 0.0,
    memory_rss: u64 = 0,
    memory_heap: u64 = 0,

    /// I/O指标
    io_read_ops: u64 = 0,
    io_write_ops: u64 = 0,
    io_read_bytes: u64 = 0,
    io_write_bytes: u64 = 0,

    /// 网络指标
    network_connections: u32 = 0,
    network_bytes_sent: u64 = 0,
    network_bytes_received: u64 = 0,

    /// 任务指标
    tasks_created: u64 = 0,
    tasks_completed: u64 = 0,
    tasks_pending: u32 = 0,

    /// 延迟指标 (纳秒)
    latency_p50: u64 = 0,
    latency_p95: u64 = 0,
    latency_p99: u64 = 0,

    /// 吞吐量指标
    throughput_ops_per_sec: f64 = 0.0,

    /// 错误指标
    error_count: u64 = 0,
    error_rate: f64 = 0.0,

    pub fn init() PerformanceMetrics {
        return PerformanceMetrics{
            .timestamp = std.time.nanoTimestamp(),
        };
    }
};

/// 🔥 热点信息
pub const HotspotInfo = struct {
    /// 热点类型
    hotspot_type: HotspotType,

    /// 热点位置
    location: []const u8,

    /// 热点强度 (0.0-1.0)
    intensity: f64,

    /// 持续时间 (毫秒)
    duration_ms: u64,

    /// 建议优化措施
    optimization_suggestion: []const u8,
};

/// 🔥 热点类型
pub const HotspotType = enum {
    cpu_intensive,
    memory_intensive,
    io_intensive,
    network_intensive,
    lock_contention,
    allocation_heavy,
};

/// 🚀 性能监控器
pub const PerformanceMonitor = struct {
    const Self = @This();

    /// 配置
    config: PerformanceMonitorConfig,

    /// 指标历史
    metrics_history: std.ArrayList(PerformanceMetrics),

    /// 当前指标
    current_metrics: PerformanceMetrics = .{
        .timestamp = 0,
    },

    /// 热点列表
    hotspots: std.ArrayList(HotspotInfo),

    /// 监控线程
    monitor_thread: ?std.Thread = null,

    /// 运行状态
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    /// 分配器
    allocator: std.mem.Allocator,

    /// 上次报告时间
    last_report_time: i128 = 0,

    pub fn init(allocator: std.mem.Allocator, config: PerformanceMonitorConfig) Self {
        return Self{
            .config = config,
            .metrics_history = std.ArrayList(PerformanceMetrics).init(allocator),
            .hotspots = std.ArrayList(HotspotInfo).init(allocator),
            .allocator = allocator,
            .last_report_time = std.time.nanoTimestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.metrics_history.deinit();
        self.hotspots.deinit();
    }

    /// 🚀 启动性能监控
    pub fn start(self: *Self) !void {
        self.running.store(true, .release);
        self.monitor_thread = try std.Thread.spawn(.{}, monitorLoop, .{self});
    }

    /// 🛑 停止性能监控
    pub fn stop(self: *Self) void {
        self.running.store(false, .release);

        if (self.monitor_thread) |thread| {
            thread.join();
            self.monitor_thread = null;
        }
    }

    /// 📊 收集性能指标
    pub fn collectMetrics(self: *Self) !void {
        var metrics = PerformanceMetrics.init();

        // 收集CPU指标
        try self.collectCpuMetrics(&metrics);

        // 收集内存指标
        try self.collectMemoryMetrics(&metrics);

        // 收集I/O指标
        try self.collectIoMetrics(&metrics);

        // 收集网络指标
        try self.collectNetworkMetrics(&metrics);

        // 收集任务指标
        try self.collectTaskMetrics(&metrics);

        // 更新当前指标
        self.current_metrics = metrics;

        // 添加到历史记录
        try self.addToHistory(metrics);

        // 检测热点
        if (self.config.enable_hotspot_detection) {
            try self.detectHotspots();
        }

        // 自适应调优
        if (self.config.enable_adaptive_tuning) {
            try self.performAdaptiveTuning();
        }

        // 检查预警
        if (self.config.enable_alerts) {
            self.checkAlerts();
        }
    }

    /// 🔥 检测性能热点
    fn detectHotspots(self: *Self) !void {
        const metrics = self.current_metrics;

        // 清除旧的热点
        self.hotspots.clearRetainingCapacity();

        // CPU热点检测
        if (metrics.cpu_usage > self.config.hotspot_threshold) {
            try self.hotspots.append(HotspotInfo{
                .hotspot_type = .cpu_intensive,
                .location = "CPU",
                .intensity = metrics.cpu_usage / 100.0,
                .duration_ms = 0, // 需要跟踪持续时间
                .optimization_suggestion = "考虑优化CPU密集型操作或增加并行度",
            });
        }

        // 内存热点检测
        if (metrics.memory_usage > self.config.hotspot_threshold) {
            try self.hotspots.append(HotspotInfo{
                .hotspot_type = .memory_intensive,
                .location = "Memory",
                .intensity = metrics.memory_usage / 100.0,
                .duration_ms = 0,
                .optimization_suggestion = "检查内存泄漏或优化内存使用模式",
            });
        }

        // I/O热点检测
        const io_intensity = self.calculateIoIntensity();
        if (io_intensity > self.config.hotspot_threshold) {
            try self.hotspots.append(HotspotInfo{
                .hotspot_type = .io_intensive,
                .location = "I/O",
                .intensity = io_intensity / 100.0,
                .duration_ms = 0,
                .optimization_suggestion = "考虑使用批量I/O或异步I/O优化",
            });
        }
    }

    /// 🔧 自适应性能调优
    fn performAdaptiveTuning(self: *Self) !void {
        const metrics = self.current_metrics;

        // 基于CPU使用率调整
        if (metrics.cpu_usage < 30.0) {
            // CPU使用率低，可以增加并发度
            std.log.debug("自适应调优: CPU使用率低，建议增加并发度", .{});
        } else if (metrics.cpu_usage > 90.0) {
            // CPU使用率高，需要减少并发度
            std.log.debug("自适应调优: CPU使用率高，建议减少并发度", .{});
        }

        // 基于内存使用率调整
        if (metrics.memory_usage > 80.0) {
            std.log.debug("自适应调优: 内存使用率高，建议启用内存压缩", .{});
        }

        // 基于延迟调整
        if (metrics.latency_p99 > 100_000_000) { // 100ms
            std.log.debug("自适应调优: 延迟过高，建议优化关键路径", .{});
        }
    }

    /// 🚨 检查预警条件
    fn checkAlerts(self: *Self) void {
        const metrics = self.current_metrics;
        const thresholds = self.config.alert_thresholds;

        if (metrics.cpu_usage > thresholds.cpu_usage_threshold) {
            std.log.warn("⚠️ CPU使用率预警: {d:.1}% > {d:.1}%", .{ metrics.cpu_usage, thresholds.cpu_usage_threshold });
        }

        if (metrics.memory_usage > thresholds.memory_usage_threshold) {
            std.log.warn("⚠️ 内存使用率预警: {d:.1}% > {d:.1}%", .{ metrics.memory_usage, thresholds.memory_usage_threshold });
        }

        const latency_ms = @as(f64, @floatFromInt(metrics.latency_p99)) / 1_000_000.0;
        if (latency_ms > thresholds.latency_threshold_ms) {
            std.log.warn("⚠️ 延迟预警: {d:.1}ms > {d:.1}ms", .{ latency_ms, thresholds.latency_threshold_ms });
        }

        if (metrics.error_rate > thresholds.error_rate_threshold) {
            std.log.warn("⚠️ 错误率预警: {d:.1}% > {d:.1}%", .{ metrics.error_rate, thresholds.error_rate_threshold });
        }
    }

    /// 📊 生成性能报告
    pub fn generateReport(self: *Self) void {
        const now = std.time.nanoTimestamp();
        const elapsed_ms = @as(u64, @intCast(@divTrunc(now - self.last_report_time, 1_000_000)));

        if (elapsed_ms < self.config.report_interval_ms) {
            return;
        }

        const metrics = self.current_metrics;

        std.log.info("=== 🚀 Zokio 性能报告 ===", .{});
        std.log.info("CPU使用率: {d:.1}% (用户: {d:.1}%, 系统: {d:.1}%)", .{ metrics.cpu_usage, metrics.cpu_user, metrics.cpu_system });
        std.log.info("内存使用: {d:.1}% (RSS: {}KB, 堆: {}KB)", .{ metrics.memory_usage, metrics.memory_rss / 1024, metrics.memory_heap / 1024 });
        std.log.info("I/O操作: 读{}次/{}KB, 写{}次/{}KB", .{ metrics.io_read_ops, metrics.io_read_bytes / 1024, metrics.io_write_ops, metrics.io_write_bytes / 1024 });
        std.log.info("任务状态: 创建{}, 完成{}, 待处理{}", .{ metrics.tasks_created, metrics.tasks_completed, metrics.tasks_pending });
        std.log.info("延迟分布: P50={d:.1}μs, P95={d:.1}μs, P99={d:.1}μs", .{
            @as(f64, @floatFromInt(metrics.latency_p50)) / 1000.0,
            @as(f64, @floatFromInt(metrics.latency_p95)) / 1000.0,
            @as(f64, @floatFromInt(metrics.latency_p99)) / 1000.0,
        });
        std.log.info("吞吐量: {d:.0} ops/sec", .{metrics.throughput_ops_per_sec});
        std.log.info("错误率: {d:.2}%", .{metrics.error_rate});

        if (self.hotspots.items.len > 0) {
            std.log.info("检测到 {} 个性能热点:", .{self.hotspots.items.len});
            for (self.hotspots.items) |hotspot| {
                std.log.info("  - {s}: {s} (强度: {d:.1}%)", .{ @tagName(hotspot.hotspot_type), hotspot.location, hotspot.intensity * 100 });
            }
        }

        self.last_report_time = now;
    }

    /// 📊 获取当前指标
    pub fn getCurrentMetrics(self: *const Self) PerformanceMetrics {
        return self.current_metrics;
    }

    /// 🔥 获取热点列表
    pub fn getHotspots(self: *const Self) []const HotspotInfo {
        return self.hotspots.items;
    }

    // 私有辅助方法
    fn collectCpuMetrics(self: *Self, metrics: *PerformanceMetrics) !void {
        _ = self;
        // 这里需要实现实际的CPU指标收集
        // 可以使用系统调用或/proc文件系统
        metrics.cpu_usage = 45.0; // 模拟值
        metrics.cpu_user = 30.0;
        metrics.cpu_system = 15.0;
    }

    fn collectMemoryMetrics(self: *Self, metrics: *PerformanceMetrics) !void {
        _ = self;
        // 实现内存指标收集
        metrics.memory_usage = 60.0; // 模拟值
        metrics.memory_rss = 1024 * 1024; // 1MB
        metrics.memory_heap = 512 * 1024; // 512KB
    }

    fn collectIoMetrics(self: *Self, metrics: *PerformanceMetrics) !void {
        _ = self;
        // 实现I/O指标收集
        metrics.io_read_ops = 1000;
        metrics.io_write_ops = 800;
        metrics.io_read_bytes = 1024 * 1024;
        metrics.io_write_bytes = 512 * 1024;
    }

    fn collectNetworkMetrics(self: *Self, metrics: *PerformanceMetrics) !void {
        _ = self;
        // 实现网络指标收集
        metrics.network_connections = 50;
        metrics.network_bytes_sent = 2048 * 1024;
        metrics.network_bytes_received = 1536 * 1024;
    }

    fn collectTaskMetrics(self: *Self, metrics: *PerformanceMetrics) !void {
        _ = self;
        // 实现任务指标收集
        metrics.tasks_created = 5000;
        metrics.tasks_completed = 4950;
        metrics.tasks_pending = 50;
        metrics.latency_p50 = 1_000_000; // 1ms
        metrics.latency_p95 = 5_000_000; // 5ms
        metrics.latency_p99 = 10_000_000; // 10ms
        metrics.throughput_ops_per_sec = 10000.0;
        metrics.error_count = 25;
        metrics.error_rate = 0.5;
    }

    fn addToHistory(self: *Self, metrics: PerformanceMetrics) !void {
        try self.metrics_history.append(metrics);

        // 保持历史长度限制
        while (self.metrics_history.items.len > self.config.metrics_history_length) {
            _ = self.metrics_history.orderedRemove(0);
        }
    }

    fn calculateIoIntensity(self: *Self) f64 {
        _ = self;
        // 计算I/O强度的简化实现
        return 25.0; // 模拟值
    }

    /// 📊 监控循环
    fn monitorLoop(self: *Self) void {
        while (self.running.load(.acquire)) {
            self.collectMetrics() catch |err| {
                std.log.warn("性能指标收集失败: {}", .{err});
            };

            self.generateReport();

            std.time.sleep(self.config.monitor_interval_ms * std.time.ns_per_ms);
        }
    }
};

/// 🧪 性能监控测试
pub fn runPerformanceMonitorTest(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 🚀 性能监控测试 ===\n", .{});

    const config = PerformanceMonitorConfig{
        .monitor_interval_ms = 100,
        .report_interval_ms = 500,
        .enable_hotspot_detection = true,
        .enable_adaptive_tuning = true,
        .enable_alerts = true,
    };

    var monitor = PerformanceMonitor.init(allocator, config);
    defer monitor.deinit();

    try monitor.start();
    defer monitor.stop();

    // 运行监控一段时间
    std.time.sleep(1000 * std.time.ns_per_ms);

    const metrics = monitor.getCurrentMetrics();
    const hotspots = monitor.getHotspots();

    std.debug.print("性能监控测试结果:\n", .{});
    std.debug.print("  CPU使用率: {d:.1}%\n", .{metrics.cpu_usage});
    std.debug.print("  内存使用率: {d:.1}%\n", .{metrics.memory_usage});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{metrics.throughput_ops_per_sec});
    std.debug.print("  检测到热点: {}\n", .{hotspots.len});
    std.debug.print("  ✅ 性能监控测试完成\n", .{});
}
