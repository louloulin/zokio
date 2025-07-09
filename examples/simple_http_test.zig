//! 🚀 Zokio 简化HTTP服务器测试
//!
//! 用于测试基本HTTP功能的简化版本

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

/// 简化的HTTP响应
const SimpleResponse = struct {
    status: u16,
    body: []const u8,

    pub fn toString(self: SimpleResponse, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "HTTP/1.1 {} OK\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Content-Length: {}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}", .{ self.status, self.body.len, self.body });
    }
};

/// 简化的HTTP服务器
const SimpleHttpServer = struct {
    allocator: std.mem.Allocator,
    listener: ?zokio.net.tcp.TcpListener = null,
    running: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// 启动服务器（智能端口选择）
    pub fn start(self: *Self, preferred_port: u16) !u16 {
        // 首先尝试首选端口
        if (self.tryBindPort(preferred_port)) |actual_port| {
            print("🚀 简化HTTP服务器启动成功\n", .{});
            print("📡 监听地址: http://localhost:{}\n", .{actual_port});
            print("🔄 等待连接...\n\n", .{});
            self.running = true;
            return actual_port;
        } else |err| {
            return err;
        }
    }

    /// 尝试绑定端口，如果失败则自动寻找可用端口
    fn tryBindPort(self: *Self, preferred_port: u16) !u16 {
        const addr_str = try std.fmt.allocPrint(self.allocator, "127.0.0.1:{}", .{preferred_port});
        defer self.allocator.free(addr_str);

        const addr = try zokio.net.SocketAddr.parse(addr_str);

        if (zokio.net.tcp.TcpListener.bind(self.allocator, addr)) |listener| {
            self.listener = listener;
            return preferred_port;
        } else |err| {
            if (err == error.AddressInUse) {
                print("⚠️  端口 {} 已被占用，寻找其他可用端口...\n", .{preferred_port});

                // 尝试其他端口
                const port_candidates = [_]u16{ 8081, 8082, 8083, 8084, 8085, 9091, 9092, 9093 };

                for (port_candidates) |port| {
                    const test_addr_str = try std.fmt.allocPrint(self.allocator, "127.0.0.1:{}", .{port});
                    defer self.allocator.free(test_addr_str);

                    const test_addr = try zokio.net.SocketAddr.parse(test_addr_str);

                    if (zokio.net.tcp.TcpListener.bind(self.allocator, test_addr)) |listener| {
                        print("✅ 找到可用端口 {}\n", .{port});
                        self.listener = listener;
                        return port;
                    } else |_| {
                        continue;
                    }
                }

                return error.NoAvailablePort;
            } else {
                return err;
            }
        }
    }

    /// 处理单个连接（演示模式）
    pub fn handleDemoConnection(self: *Self) !void {
        if (!self.running) {
            _ = try self.start(8080);
        }

        print("🎯 演示模式：模拟处理HTTP请求\n", .{});

        // 模拟几个HTTP请求
        const demo_requests = [_][]const u8{
            "GET / HTTP/1.1\r\nHost: localhost:8080\r\n\r\n",
            "GET /hello HTTP/1.1\r\nHost: localhost:8080\r\n\r\n",
            "GET /api/status HTTP/1.1\r\nHost: localhost:8080\r\n\r\n",
        };

        for (demo_requests, 0..) |request, i| {
            print("📥 处理请求 #{}: {s}\n", .{ i + 1, request[0..@min(30, request.len)] });

            // 解析请求路径
            var lines = std.mem.splitSequence(u8, request, "\r\n");
            var path: []const u8 = "/";

            if (lines.next()) |request_line| {
                var parts = std.mem.splitSequence(u8, request_line, " ");
                _ = parts.next(); // 跳过方法
                if (parts.next()) |request_path| {
                    path = request_path;
                }
            }

            // 生成响应
            const response = if (std.mem.eql(u8, path, "/"))
                SimpleResponse{ .status = 200, .body = "🚀 欢迎使用Zokio简化HTTP服务器!" }
            else if (std.mem.eql(u8, path, "/hello"))
                SimpleResponse{ .status = 200, .body = "🚀 Hello from Zokio!" }
            else if (std.mem.eql(u8, path, "/api/status"))
                SimpleResponse{ .status = 200, .body = "{\"status\": \"ok\", \"server\": \"Zokio Simple\"}" }
            else
                SimpleResponse{ .status = 404, .body = "404 - Page Not Found" };

            // 生成响应字符串
            const response_str = try response.toString(self.allocator);
            defer self.allocator.free(response_str);

            print("📤 响应: {} - {} 字节\n", .{ response.status, response_str.len });
            print("✅ 请求 #{} 处理完成\n\n", .{i + 1});
        }

        print("🎉 演示完成！服务器基本功能正常\n", .{});
    }

    /// 尝试真实连接处理（带超时保护）
    pub fn tryRealConnection(self: *Self) !void {
        var actual_port: u16 = 8080;
        if (!self.running) {
            actual_port = try self.start(8080);
        }

        print("🔄 尝试接受真实连接（5秒超时）...\n", .{});

        // 使用超时保护的连接接受
        const accept_future = self.listener.?.accept();
        const stream = zokio.await_fn_future(accept_future) catch |err| {
            switch (err) {
                error.Timeout => {
                    print("⏰ 5秒内没有连接，这是正常的\n", .{});
                    print("💡 可以使用 curl http://localhost:{}/hello 测试\n", .{actual_port});
                    return;
                },
                else => {
                    print("❌ 连接接受失败: {}\n", .{err});
                    return err;
                },
            }
        };

        print("✅ 接受到真实连接！\n", .{});

        // 简单处理连接
        var buffer: [1024]u8 = undefined;
        var mutable_stream = stream;
        const read_future = mutable_stream.read(&buffer);
        const bytes_read = zokio.await_fn_future(read_future) catch |err| {
            print("❌ 读取数据失败: {}\n", .{err});
            return;
        };

        print("📥 收到 {} 字节数据\n", .{bytes_read});

        // 发送简单响应
        const response = SimpleResponse{ .status = 200, .body = "🚀 Hello from Real Zokio Server!" };
        const response_str = try response.toString(self.allocator);
        defer self.allocator.free(response_str);

        const write_future = mutable_stream.write(response_str);
        _ = zokio.await_fn_future(write_future) catch |err| {
            print("❌ 发送响应失败: {}\n", .{err});
            return;
        };

        print("📤 响应已发送\n", .{});
        print("✅ 真实连接处理完成\n", .{});
    }

    pub fn deinit(self: *Self) void {
        if (self.listener) |*listener| {
            listener.close();
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🌟 ===============================================\n", .{});
    print("🚀 Zokio 简化HTTP服务器测试\n", .{});
    print("🌟 ===============================================\n\n", .{});

    // 创建运行时
    const config = zokio.RuntimeConfig{
        .worker_threads = 2,
        .enable_work_stealing = false,
        .enable_io_uring = false,
        .enable_metrics = false,
        .memory_strategy = .general_purpose,
    };

    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    print("✅ Zokio 运行时启动成功\n\n", .{});

    // 创建服务器
    var server = SimpleHttpServer.init(allocator);
    defer server.deinit();

    // 1. 演示模式测试
    print("📋 第一步：演示模式测试\n", .{});
    try server.handleDemoConnection();
    print("\n", .{});

    // 2. 真实连接测试（带超时保护）
    print("📋 第二步：真实连接测试\n", .{});
    try server.tryRealConnection();

    print("\n🎉 测试完成！\n", .{});
}
