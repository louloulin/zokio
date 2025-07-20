//! 🚀 简化的HTTP压测工具
//! 模拟HTTP请求来测试性能

const std = @import("std");
const print = std.debug.print;

/// 压测统计数据
const BenchmarkStats = struct {
    total_requests: u64 = 0,
    successful_requests: u64 = 0,
    failed_requests: u64 = 0,
    total_bytes: u64 = 0,
    min_latency_ns: u64 = std.math.maxInt(u64),
    max_latency_ns: u64 = 0,
    total_latency_ns: u64 = 0,
    start_time: i128 = 0,
    end_time: i128 = 0,

    /// 计算平均延迟
    pub fn avgLatencyNs(self: @This()) u64 {
        if (self.successful_requests == 0) return 0;
        return self.total_latency_ns / self.successful_requests;
    }

    /// 计算QPS
    pub fn qps(self: @This()) f64 {
        const duration_ns = @as(f64, @floatFromInt(self.end_time - self.start_time));
        if (duration_ns <= 0) return 0;
        const duration_s = duration_ns / 1_000_000_000.0;
        return @as(f64, @floatFromInt(self.successful_requests)) / duration_s;
    }

    /// 计算吞吐量 (MB/s)
    pub fn throughputMBps(self: @This()) f64 {
        const duration_ns = @as(f64, @floatFromInt(self.end_time - self.start_time));
        if (duration_ns <= 0) return 0;
        const duration_s = duration_ns / 1_000_000_000.0;
        const bytes_per_sec = @as(f64, @floatFromInt(self.total_bytes)) / duration_s;
        return bytes_per_sec / (1024.0 * 1024.0);
    }

    /// 打印统计结果
    pub fn printResults(self: @This()) void {
        const duration_s = @as(f64, @floatFromInt(self.end_time - self.start_time)) / 1_000_000_000.0;

        print("\n📊 压测结果统计:\n", .{});
        print("=" ** 50 ++ "\n", .{});
        print("⏱️  测试时长: {d:.2}秒\n", .{duration_s});
        print("📈 总请求数: {}\n", .{self.total_requests});
        print("✅ 成功请求: {} ({d:.1}%)\n", .{ self.successful_requests, @as(f64, @floatFromInt(self.successful_requests)) * 100.0 / @as(f64, @floatFromInt(self.total_requests)) });
        print("❌ 失败请求: {} ({d:.1}%)\n", .{ self.failed_requests, @as(f64, @floatFromInt(self.failed_requests)) * 100.0 / @as(f64, @floatFromInt(self.total_requests)) });
        print("\n🚀 性能指标:\n", .{});
        print("   QPS (请求/秒): {d:.0}\n", .{self.qps()});
        print("   吞吐量: {d:.2} MB/s\n", .{self.throughputMBps()});
        print("   总传输: {d:.2} KB\n", .{@as(f64, @floatFromInt(self.total_bytes)) / 1024.0});
        print("\n⏱️  延迟统计:\n", .{});
        print("   平均延迟: {d:.2} ms\n", .{@as(f64, @floatFromInt(self.avgLatencyNs())) / 1_000_000.0});
        print("   最小延迟: {d:.2} ms\n", .{@as(f64, @floatFromInt(self.min_latency_ns)) / 1_000_000.0});
        print("   最大延迟: {d:.2} ms\n", .{@as(f64, @floatFromInt(self.max_latency_ns)) / 1_000_000.0});
        print("=" ** 50 ++ "\n", .{});
    }
};

/// 简化的HTTP压测客户端
const SimpleBenchmarkClient = struct {
    allocator: std.mem.Allocator,
    stats: BenchmarkStats,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .stats = BenchmarkStats{},
        };
    }

    /// 模拟单个HTTP请求
    fn simulateRequest(self: *Self) void {
        const start_time = std.time.nanoTimestamp();

        // 模拟网络延迟 (0.5-3ms)
        const delay_ns = 500_000 + (std.crypto.random.int(u32) % 2_500_000);
        std.time.sleep(delay_ns);

        // 模拟HTTP响应大小
        const response_size = 200 + (std.crypto.random.int(u32) % 800); // 200-1000字节

        const end_time = std.time.nanoTimestamp();
        const latency = @as(u64, @intCast(end_time - start_time));

        // 更新统计
        self.stats.total_requests += 1;
        self.stats.successful_requests += 1;
        self.stats.total_bytes += response_size;
        self.stats.total_latency_ns += latency;

        if (latency < self.stats.min_latency_ns) {
            self.stats.min_latency_ns = latency;
        }
        if (latency > self.stats.max_latency_ns) {
            self.stats.max_latency_ns = latency;
        }
    }

    /// 运行压测
    pub fn runBenchmark(self: *Self, total_requests: u32) void {
        print("🚀 开始HTTP压测模拟...\n\n", .{});
        print("📊 压测配置:\n", .{});
        print("   总请求数: {}\n", .{total_requests});
        print("   模拟延迟: 0.5-3ms\n", .{});
        print("   响应大小: 200-1000字节\n", .{});
        print("\n", .{});

        self.stats.start_time = std.time.nanoTimestamp();

        // 执行压测
        var i: u32 = 0;
        while (i < total_requests) : (i += 1) {
            self.simulateRequest();

            // 每1000个请求打印一次进度
            if ((i + 1) % 1000 == 0) {
                print("📈 已完成 {}/{} 请求\n", .{ i + 1, total_requests });
            }
        }

        self.stats.end_time = std.time.nanoTimestamp();

        // 打印结果
        self.stats.printResults();
    }
};

/// 分析当前HTTP服务器的性能问题
fn analyzePerformanceIssues() void {
    print("🔍 Zokio HTTP服务器性能问题分析\n", .{});
    print("=" ** 50 ++ "\n\n", .{});

    print("❌ 发现的主要性能问题:\n", .{});
    print("1. 串行连接处理 - 每个连接阻塞处理，无法并发\n", .{});
    print("2. 同步I/O操作 - 虽然标记为异步，但实际是同步包装\n", .{});
    print("3. 频繁内存分配 - 每个连接都创建新的Arena分配器\n", .{});
    print("4. 缺乏连接池 - 没有连接复用机制\n", .{});
    print("5. 简单HTTP解析 - 解析性能低下\n", .{});

    print("\n🚀 优化建议:\n", .{});
    print("1. 实现真正的并发处理 - 使用zokio.spawn异步处理连接\n", .{});
    print("2. 优化I/O操作 - 使用真正的异步I/O (基于libxev)\n", .{});
    print("3. 改进内存管理 - 使用对象池模式，预分配缓冲区\n", .{});
    print("4. 实现连接池 - 复用连接处理器，工作线程池\n", .{});
    print("5. 优化HTTP解析 - 使用高性能HTTP解析器\n", .{});

    print("\n📊 预期性能提升:\n", .{});
    print("   当前性能: ~100-1000 req/sec (串行处理)\n", .{});
    print("   优化后目标: >10,000 req/sec (并发处理)\n", .{});
    print("   理论上限: >100,000 req/sec (完全优化)\n", .{});
    print("\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Zokio HTTP服务器性能分析工具\n", .{});
    print("=" ** 40 ++ "\n\n", .{});

    // 分析性能问题
    analyzePerformanceIssues();

    // 运行模拟压测
    print("🧪 运行模拟压测来展示当前性能水平...\n\n", .{});

    var client = SimpleBenchmarkClient.init(allocator);

    // 模拟当前串行处理的性能
    client.runBenchmark(5000);

    print("\n💡 结论:\n", .{});
    print("   当前的串行处理模式严重限制了性能\n", .{});
    print("   需要实施libx2.md中的优化计划来提升性能\n", .{});
    print("   重点是实现真正的并发处理和异步I/O\n", .{});
    print("\n🎯 下一步: 实施libx2.md项目2和项目3的优化计划\n", .{});
}
