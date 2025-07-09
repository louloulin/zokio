//! 🚀 Zokio HTTP服务器压测工具
//!
//! 专门用于测试Zokio HTTP服务器性能的压测工具
//! 支持并发测试、延迟测量、吞吐量分析

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

/// 压测配置
const BenchmarkConfig = struct {
    target_url: []const u8 = "http://127.0.0.1:8080",
    concurrent_connections: u32 = 10,
    total_requests: u32 = 1000,
    duration_seconds: u32 = 10,
    request_path: []const u8 = "/hello",
    keep_alive: bool = true,

    pub fn print(self: @This()) void {
        std.debug.print("📊 压测配置:\n", .{});
        std.debug.print("   目标URL: {s}\n", .{self.target_url});
        std.debug.print("   并发连接: {}\n", .{self.concurrent_connections});
        std.debug.print("   总请求数: {}\n", .{self.total_requests});
        std.debug.print("   测试时长: {}秒\n", .{self.duration_seconds});
        std.debug.print("   请求路径: {s}\n", .{self.request_path});
        std.debug.print("   保持连接: {}\n", .{self.keep_alive});
        std.debug.print("\n", .{});
    }
};

/// 压测统计数据
const BenchmarkStats = struct {
    total_requests: u64 = 0,
    successful_requests: u64 = 0,
    failed_requests: u64 = 0,
    total_bytes: u64 = 0,
    min_latency_ns: u64 = std.math.maxInt(u64),
    max_latency_ns: u64 = 0,
    total_latency_ns: u64 = 0,
    start_time: i64 = 0,
    end_time: i64 = 0,

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
        print("=" * 50 ++ "\n", .{});
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
        print("=" * 50 ++ "\n", .{});
    }
};

/// HTTP压测客户端
const HttpBenchmarkClient = struct {
    allocator: std.mem.Allocator,
    config: BenchmarkConfig,
    stats: BenchmarkStats,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: BenchmarkConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .stats = BenchmarkStats{},
        };
    }

    /// 执行单个HTTP请求 (模拟版本)
    fn performRequest(self: *Self) !void {
        const start_time = std.time.nanoTimestamp();

        // 模拟网络延迟 (0.1-2ms)
        const delay_ns = 100_000 + (std.crypto.random.int(u32) % 1_900_000);
        std.time.sleep(delay_ns);

        // 模拟HTTP请求处理
        const response_size = 200 + (std.crypto.random.int(u32) % 800); // 200-1000字节

        // 构造HTTP请求
        const request = try std.fmt.allocPrint(self.allocator, "GET {s} HTTP/1.1\r\n" ++
            "Host: 127.0.0.1:8080\r\n" ++
            "User-Agent: Zokio-Benchmark/1.0\r\n" ++
            "Accept: */*\r\n" ++
            "Connection: {s}\r\n" ++
            "\r\n", .{ self.config.request_path, if (self.config.keep_alive) "keep-alive" else "close" });
        defer self.allocator.free(request);

        // 发送请求
        stream.writeAll(request.ptr, request.len) catch |err| {
            self.stats.failed_requests += 1;
            print("❌ 发送请求失败: {}\n", .{err});
            return;
        };

        // 读取响应
        var response_buffer: [4096]u8 = undefined;
        const bytes_read = stream.readAll(&response_buffer) catch |err| {
            self.stats.failed_requests += 1;
            print("❌ 读取响应失败: {}\n", .{err});
            return;
        };

        const end_time = std.time.nanoTimestamp();
        const latency = @as(u64, @intCast(end_time - start_time));

        // 更新统计
        self.stats.total_requests += 1;
        self.stats.successful_requests += 1;
        self.stats.total_bytes += bytes_read;
        self.stats.total_latency_ns += latency;

        if (latency < self.stats.min_latency_ns) {
            self.stats.min_latency_ns = latency;
        }
        if (latency > self.stats.max_latency_ns) {
            self.stats.max_latency_ns = latency;
        }
    }

    /// 运行压测
    pub fn runBenchmark(self: *Self) !void {
        print("🚀 开始HTTP压测...\n\n", .{});
        self.config.print();

        self.stats.start_time = std.time.nanoTimestamp();

        // 简单的串行压测（后续可以改为并发）
        var i: u32 = 0;
        while (i < self.config.total_requests) : (i += 1) {
            try self.performRequest();

            // 每100个请求打印一次进度
            if ((i + 1) % 100 == 0) {
                print("📈 已完成 {}/{} 请求\n", .{ i + 1, self.config.total_requests });
            }
        }

        self.stats.end_time = std.time.nanoTimestamp();

        // 打印结果
        self.stats.printResults();
    }
};

/// 简单的HTTP服务器健康检查
fn checkServerHealth(allocator: std.mem.Allocator) !bool {
    print("🔍 检查HTTP服务器健康状态...\n", .{});

    const addr = zokio.net.SocketAddr.parse("127.0.0.1:8080") catch {
        print("❌ 无法解析服务器地址\n", .{});
        return false;
    };

    var stream = zokio.net.tcp.TcpStream.connect(allocator, addr) catch {
        print("❌ 无法连接到服务器 (127.0.0.1:8080)\n", .{});
        print("💡 请先启动HTTP服务器: zig build simple-http-demo\n", .{});
        return false;
    };
    defer stream.close();

    const request = "GET /hello HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n\r\n";
    stream.writeAll(request.ptr, request.len) catch {
        print("❌ 发送健康检查请求失败\n", .{});
        return false;
    };

    var response: [1024]u8 = undefined;
    const bytes_read = stream.readAll(&response) catch {
        print("❌ 读取健康检查响应失败\n", .{});
        return false;
    };

    if (bytes_read > 0) {
        print("✅ 服务器健康检查通过\n", .{});
        print("📡 响应大小: {} 字节\n\n", .{bytes_read});
        return true;
    }

    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Zokio HTTP服务器压测工具\n", .{});
    print("=" * 40 ++ "\n\n", .{});

    // 检查服务器健康状态
    if (!try checkServerHealth(allocator)) {
        return;
    }

    // 配置压测参数
    const config = BenchmarkConfig{
        .concurrent_connections = 1, // 先从串行开始
        .total_requests = 1000,
        .request_path = "/hello",
    };

    // 创建压测客户端
    var client = HttpBenchmarkClient.init(allocator, config);

    // 运行压测
    try client.runBenchmark();

    print("\n🎉 压测完成！\n", .{});
}
