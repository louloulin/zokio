//! 🚀 Zokio 并发HTTP服务器 - 阶段1优化版本
//!
//! 这是HTTP性能优化计划阶段1的实现：基础并发处理
//! 目标：从459 QPS提升到5,000+ QPS (10倍性能提升)

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

/// 并发HTTP服务器配置
const ConcurrentServerConfig = struct {
    port: u16 = 8080,
    max_concurrent_connections: u32 = 1000,
    connection_timeout_ms: u32 = 30000,
    buffer_size: usize = 4096,
};

/// 连接统计信息
const ConnectionStats = struct {
    total_connections: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    active_connections: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    total_requests: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    pub fn incrementConnection(self: *@This()) void {
        _ = self.total_connections.fetchAdd(1, .monotonic);
        _ = self.active_connections.fetchAdd(1, .monotonic);
    }

    pub fn decrementConnection(self: *@This()) void {
        _ = self.active_connections.fetchSub(1, .monotonic);
    }

    pub fn incrementRequest(self: *@This()) void {
        _ = self.total_requests.fetchAdd(1, .monotonic);
    }

    pub fn printStats(self: *@This()) void {
        const total = self.total_connections.load(.monotonic);
        const active = self.active_connections.load(.monotonic);
        const requests = self.total_requests.load(.monotonic);

        print("📊 连接统计 - 总连接: {}, 活跃: {}, 总请求: {}\n", .{ total, active, requests });
    }
};

/// 并发连接处理器
const ConcurrentConnectionHandler = struct {
    allocator: std.mem.Allocator,
    connection_id: u64,
    stats: *ConnectionStats,
    config: ConcurrentServerConfig,

    const Self = @This();

    /// 🚀 异步连接处理函数
    pub fn handleConnectionAsync(self: *Self, stream: *zokio.net.tcp.TcpStream) !void {
        defer {
            stream.close();
            self.stats.decrementConnection();
            print("🔚 连接 {} 已关闭\n", .{self.connection_id});
        }

        print("🚀 开始异步处理连接 {}\n", .{self.connection_id});

        // 使用Arena分配器管理连接生命周期内的内存
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // 读取HTTP请求 (使用异步读取)
        var buffer: [4096]u8 = undefined;
        const read_future = stream.read(&buffer);
        const bytes_read = zokio.await_fn(read_future) catch |err| {
            print("❌ 连接 {} 读取失败: {}\n", .{ self.connection_id, err });
            return;
        };

        if (bytes_read == 0) {
            print("⚠️ 连接 {} 无数据\n", .{self.connection_id});
            return;
        }

        // 简单的HTTP请求解析
        const request_data = buffer[0..bytes_read];
        print("📥 连接 {} 收到请求: {} 字节\n", .{ self.connection_id, bytes_read });

        // 解析请求行
        const request_line = self.parseRequestLine(request_data, arena_allocator) catch |err| {
            print("❌ 连接 {} 解析请求失败: {}\n", .{ self.connection_id, err });
            return;
        };

        // 生成HTTP响应
        const response = try self.generateResponse(request_line, arena_allocator);

        // 🚀 真正的异步发送响应
        const write_future = stream.write(response);
        _ = zokio.await_fn(write_future) catch |err| {
            print("❌ 连接 {} 异步发送响应失败: {}\n", .{ self.connection_id, err });
            return;
        };

        self.stats.incrementRequest();
        print("✅ 连接 {} 处理完成\n", .{self.connection_id});
    }

    /// 解析HTTP请求行
    fn parseRequestLine(self: *Self, data: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;

        // 查找第一行（请求行）
        const line_end = std.mem.indexOf(u8, data, "\r\n") orelse data.len;
        const request_line = data[0..line_end];

        // 复制到分配器管理的内存中
        return try allocator.dupe(u8, request_line);
    }

    /// 生成HTTP响应
    fn generateResponse(self: *Self, request_line: []const u8, allocator: std.mem.Allocator) ![]const u8 {

        // 解析请求方法和路径
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse "UNKNOWN";
        const path = parts.next() orelse "/";

        // 生成响应内容
        const body = try std.fmt.allocPrint(allocator, "🚀 Zokio 并发HTTP服务器\n" ++
            "方法: {s}\n" ++
            "路径: {s}\n" ++
            "连接ID: {}\n" ++
            "时间: {}\n", .{ method, path, self.connection_id, std.time.timestamp() });

        // 生成完整的HTTP响应
        const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/plain; charset=utf-8\r\n" ++
            "Content-Length: {}\r\n" ++
            "Connection: close\r\n" ++
            "Server: Zokio-Concurrent/1.0\r\n" ++
            "\r\n" ++
            "{s}", .{ body.len, body });

        return response;
    }
};

/// 🚀 并发HTTP服务器
const ConcurrentHttpServer = struct {
    allocator: std.mem.Allocator,
    listener: zokio.net.tcp.TcpListener,
    config: ConcurrentServerConfig,
    stats: ConnectionStats,
    runtime: *zokio.HighPerformanceRuntime,
    running: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: ConcurrentServerConfig, runtime: *zokio.HighPerformanceRuntime) !Self {
        const addr = try zokio.net.SocketAddr.parse("127.0.0.1:8080");
        const listener = try zokio.net.tcp.TcpListener.bind(allocator, addr);

        return Self{
            .allocator = allocator,
            .listener = listener,
            .config = config,
            .stats = ConnectionStats{},
            .runtime = runtime,
        };
    }

    pub fn deinit(self: *Self) void {
        self.listener.close();
    }

    /// 🚀 运行并发服务器
    pub fn run(self: *Self) !void {
        self.running = true;

        print("🚀 Zokio 并发HTTP服务器启动\n", .{});
        print("📡 监听地址: http://127.0.0.1:{}\n", .{self.config.port});
        print("⚡ 最大并发连接: {}\n", .{self.config.max_concurrent_connections});
        print("🔄 等待连接...\n\n", .{});

        var connection_id: u64 = 0;

        while (self.running) {
            // 检查并发连接数限制
            const active_connections = self.stats.active_connections.load(.monotonic);
            if (active_connections >= self.config.max_concurrent_connections) {
                print("⚠️ 达到最大并发连接数限制: {}\n", .{active_connections});
                std.time.sleep(1_000_000); // 等待1ms
                continue;
            }

            // 🚀 异步接受连接
            var stream = zokio.await_fn(self.listener.accept()) catch |err| {
                print("❌ 接受连接失败: {}\n", .{err});
                continue;
            };

            connection_id += 1;
            self.stats.incrementConnection();

            print("✅ 接受连接 {} (活跃: {})\n", .{ connection_id, active_connections + 1 });

            // 🚀 关键优化：异步处理连接，不阻塞主循环
            // 创建异步连接处理任务
            const ConnectionTask = struct {
                handler: ConcurrentConnectionHandler,
                stream: zokio.net.tcp.TcpStream,

                pub const Output = bool; // 使用支持的类型

                pub fn poll(task: *@This(), ctx: *zokio.Context) zokio.Poll(bool) {
                    _ = ctx;
                    // 执行连接处理
                    task.handler.handleConnectionAsync(&task.stream) catch |err| {
                        print("❌ 连接 {} 处理异常: {}\n", .{ task.handler.connection_id, err });
                        return .{ .ready = false }; // 处理失败
                    };
                    return .{ .ready = true }; // 处理成功
                }
            };

            const task = ConnectionTask{
                .handler = ConcurrentConnectionHandler{
                    .allocator = self.allocator,
                    .connection_id = connection_id,
                    .stats = &self.stats,
                    .config = self.config,
                },
                .stream = stream,
            };

            // ✅ 使用runtime.spawn异步处理连接 - 这是性能提升的关键！
            _ = self.runtime.spawn(task) catch |err| {
                print("❌ spawn连接任务失败: {}\n", .{err});
                // 如果spawn失败，回退到同步处理
                var handler = ConcurrentConnectionHandler{
                    .allocator = self.allocator,
                    .connection_id = connection_id,
                    .stats = &self.stats,
                    .config = self.config,
                };
                handler.handleConnectionAsync(&stream) catch {};
            };

            // 每100个连接打印一次统计
            if (connection_id % 100 == 0) {
                self.stats.printStats();
            }
        }
    }

    pub fn stop(self: *Self) void {
        self.running = false;
        print("🛑 服务器停止中...\n", .{});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化Zokio运行时
    var runtime = try zokio.build.extremePerformance(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const config = ConcurrentServerConfig{
        .port = 8080,
        .max_concurrent_connections = 1000,
        .connection_timeout_ms = 30000,
    };

    var server = try ConcurrentHttpServer.init(allocator, config, &runtime);
    defer server.deinit();

    try server.run();
}
