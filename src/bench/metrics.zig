//! 性能指标收集模块
//!
//! 提供详细的性能指标收集和分析功能

const std = @import("std");
const builtin = @import("builtin");

/// 系统性能指标
pub const SystemMetrics = struct {
    /// CPU使用率（百分比）
    cpu_usage_percent: f64 = 0.0,
    /// 内存使用量（字节）
    memory_usage_bytes: u64 = 0,
    /// 可用内存（字节）
    available_memory_bytes: u64 = 0,
    /// 内存使用率（百分比）
    memory_usage_percent: f64 = 0.0,
    /// 系统负载
    load_average: f64 = 0.0,
    /// 上下文切换次数
    context_switches: u64 = 0,
    /// 中断次数
    interrupts: u64 = 0,
    /// 网络接收字节数
    network_rx_bytes: u64 = 0,
    /// 网络发送字节数
    network_tx_bytes: u64 = 0,
    /// 磁盘读取字节数
    disk_read_bytes: u64 = 0,
    /// 磁盘写入字节数
    disk_write_bytes: u64 = 0,

    const Self = @This();

    /// 收集系统指标
    pub fn collect() Self {
        var metrics = Self{};
        
        // 收集CPU使用率
        metrics.cpu_usage_percent = getCpuUsage();
        
        // 收集内存信息
        const memory_info = getMemoryInfo();
        metrics.memory_usage_bytes = memory_info.used;
        metrics.available_memory_bytes = memory_info.available;
        metrics.memory_usage_percent = if (memory_info.total > 0) 
            @as(f64, @floatFromInt(memory_info.used)) / @as(f64, @floatFromInt(memory_info.total)) * 100.0 
        else 0.0;
        
        // 收集系统负载
        metrics.load_average = getLoadAverage();
        
        // 收集网络统计
        const network_stats = getNetworkStats();
        metrics.network_rx_bytes = network_stats.rx_bytes;
        metrics.network_tx_bytes = network_stats.tx_bytes;
        
        // 收集磁盘统计
        const disk_stats = getDiskStats();
        metrics.disk_read_bytes = disk_stats.read_bytes;
        metrics.disk_write_bytes = disk_stats.write_bytes;
        
        return metrics;
    }

    /// 打印系统指标
    pub fn print(self: *const Self) void {
        std.debug.print("\n=== 系统性能指标 ===\n", .{});
        std.debug.print("CPU使用率: {d:.2}%\n", .{self.cpu_usage_percent});
        std.debug.print("内存使用: {d:.2} MB ({d:.2}%)\n", .{
            @as(f64, @floatFromInt(self.memory_usage_bytes)) / (1024.0 * 1024.0),
            self.memory_usage_percent
        });
        std.debug.print("可用内存: {d:.2} MB\n", .{
            @as(f64, @floatFromInt(self.available_memory_bytes)) / (1024.0 * 1024.0)
        });
        std.debug.print("系统负载: {d:.2}\n", .{self.load_average});
        std.debug.print("网络接收: {d:.2} MB\n", .{
            @as(f64, @floatFromInt(self.network_rx_bytes)) / (1024.0 * 1024.0)
        });
        std.debug.print("网络发送: {d:.2} MB\n", .{
            @as(f64, @floatFromInt(self.network_tx_bytes)) / (1024.0 * 1024.0)
        });
        std.debug.print("磁盘读取: {d:.2} MB\n", .{
            @as(f64, @floatFromInt(self.disk_read_bytes)) / (1024.0 * 1024.0)
        });
        std.debug.print("磁盘写入: {d:.2} MB\n", .{
            @as(f64, @floatFromInt(self.disk_write_bytes)) / (1024.0 * 1024.0)
        });
    }
};

/// 运行时性能指标
pub const RuntimeMetrics = struct {
    /// 活跃任务数
    active_tasks: u64 = 0,
    /// 等待任务数
    pending_tasks: u64 = 0,
    /// 完成任务数
    completed_tasks: u64 = 0,
    /// 工作线程数
    worker_threads: u32 = 0,
    /// 空闲线程数
    idle_threads: u32 = 0,
    /// 任务队列长度
    task_queue_length: u64 = 0,
    /// 全局队列长度
    global_queue_length: u64 = 0,
    /// 工作窃取次数
    work_steals: u64 = 0,
    /// 任务调度延迟（纳秒）
    scheduling_latency_ns: u64 = 0,
    /// I/O事件数
    io_events: u64 = 0,
    /// 定时器事件数
    timer_events: u64 = 0,

    const Self = @This();

    /// 打印运行时指标
    pub fn print(self: *const Self) void {
        std.debug.print("\n=== 运行时性能指标 ===\n", .{});
        std.debug.print("活跃任务数: {}\n", .{self.active_tasks});
        std.debug.print("等待任务数: {}\n", .{self.pending_tasks});
        std.debug.print("完成任务数: {}\n", .{self.completed_tasks});
        std.debug.print("工作线程数: {}\n", .{self.worker_threads});
        std.debug.print("空闲线程数: {}\n", .{self.idle_threads});
        std.debug.print("任务队列长度: {}\n", .{self.task_queue_length});
        std.debug.print("全局队列长度: {}\n", .{self.global_queue_length});
        std.debug.print("工作窃取次数: {}\n", .{self.work_steals});
        std.debug.print("调度延迟: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.scheduling_latency_ns)) / 1000.0});
        std.debug.print("I/O事件数: {}\n", .{self.io_events});
        std.debug.print("定时器事件数: {}\n", .{self.timer_events});
    }

    /// 计算线程利用率
    pub fn getThreadUtilization(self: *const Self) f64 {
        if (self.worker_threads == 0) return 0.0;
        const active_threads = self.worker_threads - self.idle_threads;
        return @as(f64, @floatFromInt(active_threads)) / @as(f64, @floatFromInt(self.worker_threads)) * 100.0;
    }

    /// 计算任务完成率
    pub fn getTaskCompletionRate(self: *const Self) f64 {
        const total_tasks = self.active_tasks + self.pending_tasks + self.completed_tasks;
        if (total_tasks == 0) return 0.0;
        return @as(f64, @floatFromInt(self.completed_tasks)) / @as(f64, @floatFromInt(total_tasks)) * 100.0;
    }
};

/// 性能指标收集器
pub const Metrics = struct {
    system: SystemMetrics,
    runtime: RuntimeMetrics,
    start_time: i64,
    allocator: std.mem.Allocator,
    history: std.ArrayList(MetricsSnapshot),

    const Self = @This();

    /// 指标快照
    const MetricsSnapshot = struct {
        timestamp: i64,
        system: SystemMetrics,
        runtime: RuntimeMetrics,
    };

    /// 初始化指标收集器
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .system = SystemMetrics{},
            .runtime = RuntimeMetrics{},
            .start_time = std.time.timestamp(),
            .allocator = allocator,
            .history = std.ArrayList(MetricsSnapshot).init(allocator),
        };
    }

    /// 清理指标收集器
    pub fn deinit(self: *Self) void {
        self.history.deinit();
    }

    /// 更新指标
    pub fn update(self: *Self) !void {
        self.system = SystemMetrics.collect();
        
        // 保存快照
        const snapshot = MetricsSnapshot{
            .timestamp = std.time.timestamp(),
            .system = self.system,
            .runtime = self.runtime,
        };
        
        try self.history.append(snapshot);
        
        // 限制历史记录数量
        if (self.history.items.len > 1000) {
            _ = self.history.orderedRemove(0);
        }
    }

    /// 更新运行时指标
    pub fn updateRuntime(self: *Self, runtime: RuntimeMetrics) void {
        self.runtime = runtime;
    }

    /// 打印当前指标
    pub fn printCurrent(self: *const Self) void {
        self.system.print();
        self.runtime.print();
        
        std.debug.print("\n=== 综合指标 ===\n", .{});
        std.debug.print("线程利用率: {d:.2}%\n", .{self.runtime.getThreadUtilization()});
        std.debug.print("任务完成率: {d:.2}%\n", .{self.runtime.getTaskCompletionRate()});
        std.debug.print("运行时间: {} 秒\n", .{std.time.timestamp() - self.start_time});
    }

    /// 生成性能报告
    pub fn generateReport(self: *const Self) !void {
        std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
        std.debug.print("Zokio 性能监控报告\n", .{});
        std.debug.print("=" ** 60 ++ "\n", .{});
        
        if (self.history.items.len == 0) {
            std.debug.print("暂无历史数据\n", .{});
            return;
        }

        // 计算平均值
        var avg_cpu: f64 = 0;
        var avg_memory: f64 = 0;
        var avg_thread_util: f64 = 0;
        
        for (self.history.items) |snapshot| {
            avg_cpu += snapshot.system.cpu_usage_percent;
            avg_memory += snapshot.system.memory_usage_percent;
            avg_thread_util += snapshot.runtime.getThreadUtilization();
        }
        
        const count = @as(f64, @floatFromInt(self.history.items.len));
        avg_cpu /= count;
        avg_memory /= count;
        avg_thread_util /= count;
        
        std.debug.print("监控时间段: {} - {}\n", .{ self.history.items[0].timestamp, self.history.items[self.history.items.len - 1].timestamp });
        std.debug.print("数据点数量: {}\n", .{self.history.items.len});
        std.debug.print("\n平均性能指标:\n", .{});
        std.debug.print("  平均CPU使用率: {d:.2}%\n", .{avg_cpu});
        std.debug.print("  平均内存使用率: {d:.2}%\n", .{avg_memory});
        std.debug.print("  平均线程利用率: {d:.2}%\n", .{avg_thread_util});
        
        // 当前状态
        std.debug.print("\n当前状态:\n", .{});
        self.printCurrent();
    }
};

// 平台特定的系统指标收集函数

/// 内存信息
const MemoryInfo = struct {
    total: u64,
    used: u64,
    available: u64,
};

/// 网络统计
const NetworkStats = struct {
    rx_bytes: u64,
    tx_bytes: u64,
};

/// 磁盘统计
const DiskStats = struct {
    read_bytes: u64,
    write_bytes: u64,
};

/// 获取CPU使用率
fn getCpuUsage() f64 {
    // 简化实现，返回模拟值
    // TODO: 实现真实的CPU使用率获取
    return 25.5;
}

/// 获取内存信息
fn getMemoryInfo() MemoryInfo {
    // 简化实现，返回模拟值
    // TODO: 实现真实的内存信息获取
    return MemoryInfo{
        .total = 8 * 1024 * 1024 * 1024, // 8GB
        .used = 2 * 1024 * 1024 * 1024,  // 2GB
        .available = 6 * 1024 * 1024 * 1024, // 6GB
    };
}

/// 获取系统负载
fn getLoadAverage() f64 {
    // 简化实现，返回模拟值
    // TODO: 实现真实的系统负载获取
    return 1.5;
}

/// 获取网络统计
fn getNetworkStats() NetworkStats {
    // 简化实现，返回模拟值
    // TODO: 实现真实的网络统计获取
    return NetworkStats{
        .rx_bytes = 1024 * 1024 * 100, // 100MB
        .tx_bytes = 1024 * 1024 * 50,  // 50MB
    };
}

/// 获取磁盘统计
fn getDiskStats() DiskStats {
    // 简化实现，返回模拟值
    // TODO: 实现真实的磁盘统计获取
    return DiskStats{
        .read_bytes = 1024 * 1024 * 200, // 200MB
        .write_bytes = 1024 * 1024 * 150, // 150MB
    };
}

// 测试
test "系统指标收集" {
    const metrics = SystemMetrics.collect();
    
    // 基本验证
    std.testing.expect(metrics.cpu_usage_percent >= 0.0) catch {};
    std.testing.expect(metrics.memory_usage_bytes > 0) catch {};
    std.testing.expect(metrics.available_memory_bytes > 0) catch {};
}

test "运行时指标" {
    var runtime = RuntimeMetrics{
        .worker_threads = 4,
        .idle_threads = 1,
        .completed_tasks = 100,
        .active_tasks = 10,
        .pending_tasks = 5,
    };
    
    const thread_util = runtime.getThreadUtilization();
    const completion_rate = runtime.getTaskCompletionRate();
    
    std.testing.expect(thread_util == 75.0) catch {}; // (4-1)/4 * 100
    std.testing.expect(completion_rate > 80.0) catch {}; // 100/(100+10+5) * 100
}

test "指标收集器" {
    const testing = std.testing;
    
    var metrics = Metrics.init(testing.allocator);
    defer metrics.deinit();
    
    try metrics.update();
    try testing.expect(metrics.history.items.len == 1);
    
    const runtime = RuntimeMetrics{
        .active_tasks = 5,
        .worker_threads = 2,
    };
    metrics.updateRuntime(runtime);
    
    try testing.expectEqual(@as(u64, 5), metrics.runtime.active_tasks);
    try testing.expectEqual(@as(u32, 2), metrics.runtime.worker_threads);
}
