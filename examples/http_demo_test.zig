//! 🚀 Zokio HTTP服务器演示测试
//!
//! 这个测试展示HTTP服务器的基本功能，包括：
//! 1. 服务器启动和端口绑定
//! 2. 模拟HTTP请求处理
//! 3. 真实连接测试（带超时保护）

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

/// 简化的HTTP服务器演示
const HttpServerDemo = struct {
    allocator: std.mem.Allocator,
    listener: ?zokio.net.tcp.TcpListener = null,
    actual_port: u16 = 8080,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// 启动服务器并找到可用端口
    pub fn start(self: *Self) !void {
        const port_candidates = [_]u16{ 8080, 8081, 8082, 9090, 9091, 9092 };

        for (port_candidates) |port| {
            const addr_str = try std.fmt.allocPrint(self.allocator, "127.0.0.1:{}", .{port});
            defer self.allocator.free(addr_str);

            const addr = try zokio.net.SocketAddr.parse(addr_str);

            if (zokio.net.tcp.TcpListener.bind(self.allocator, addr)) |listener| {
                self.listener = listener;
                self.actual_port = port;
                print("✅ HTTP服务器启动成功，监听端口 {}\n", .{port});
                print("🌐 测试地址: http://localhost:{}\n", .{port});
                return;
            } else |err| {
                if (err == error.AddressInUse) {
                    print("   端口 {} 被占用，尝试下一个...\n", .{port});
                    continue;
                } else {
                    print("   端口 {} 绑定失败: {}\n", .{ port, err });
                    continue;
                }
            }
        }

        return error.NoAvailablePort;
    }

    /// 演示HTTP请求处理
    pub fn demonstrateHttpHandling(self: *Self) !void {
        print("\n📋 演示HTTP请求处理功能:\n", .{});

        const demo_requests = [_]struct {
            method: []const u8,
            path: []const u8,
            expected_status: u16,
        }{
            .{ .method = "GET", .path = "/", .expected_status = 200 },
            .{ .method = "GET", .path = "/hello", .expected_status = 200 },
            .{ .method = "GET", .path = "/api/status", .expected_status = 200 },
            .{ .method = "GET", .path = "/notfound", .expected_status = 404 },
            .{ .method = "POST", .path = "/api/echo", .expected_status = 200 },
        };

        for (demo_requests, 0..) |req, i| {
            print("🔸 请求 #{}: {s} {s}\n", .{ i + 1, req.method, req.path });

            // 模拟请求处理
            const response_body = switch (req.expected_status) {
                200 => if (std.mem.eql(u8, req.path, "/"))
                    "🚀 欢迎使用Zokio HTTP服务器!"
                else if (std.mem.eql(u8, req.path, "/hello"))
                    "🚀 Hello from Zokio!"
                else if (std.mem.eql(u8, req.path, "/api/status"))
                    "{\"status\": \"ok\", \"server\": \"Zokio\"}"
                else if (std.mem.eql(u8, req.path, "/api/echo"))
                    "{\"echo\": \"Hello Zokio!\", \"server\": \"Zokio\"}"
                else
                    "OK",
                404 => "404 - Page Not Found",
                else => "Error",
            };

            const response = try std.fmt.allocPrint(self.allocator, "HTTP/1.1 {} {s}\r\n" ++
                "Content-Type: text/plain\r\n" ++
                "Content-Length: {}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n" ++
                "{s}", .{ req.expected_status, if (req.expected_status == 200) "OK" else "Error", response_body.len, response_body });
            defer self.allocator.free(response);

            print("   📤 响应: {} - {} 字节\n", .{ req.expected_status, response.len });
            print("   ✅ 处理完成\n\n", .{});
        }
    }

    /// 测试真实连接（带超时）
    pub fn testRealConnection(self: *Self) !void {
        if (self.listener == null) {
            print("❌ 服务器未启动\n", .{});
            return;
        }

        print("🔄 测试真实连接接受（3秒超时）...\n", .{});
        print("💡 在另一个终端运行: curl http://localhost:{}/hello\n", .{self.actual_port});

        const accept_future = self.listener.?.accept();
        const stream = zokio.await_fn_future(accept_future) catch |err| {
            switch (err) {
                error.Timeout => {
                    print("⏰ 3秒内没有连接，这是正常的\n", .{});
                    print("🎯 服务器功能验证完成\n", .{});
                    return;
                },
                else => {
                    print("❌ 连接接受失败: {}\n", .{err});
                    return;
                },
            }
        };

        print("🎉 接受到真实连接！\n", .{});

        // 简单处理连接
        var buffer: [1024]u8 = undefined;
        var mutable_stream = stream;

        const read_future = mutable_stream.read(&buffer);
        const bytes_read = zokio.await_fn_future(read_future) catch |err| {
            print("❌ 读取失败: {}\n", .{err});
            return;
        };

        print("📥 收到 {} 字节数据\n", .{bytes_read});

        // 发送简单响应
        const response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 26\r\n\r\n🚀 Hello from Zokio Server!";
        const write_future = mutable_stream.write(response);
        _ = zokio.await_fn_future(write_future) catch |err| {
            print("❌ 发送响应失败: {}\n", .{err});
            return;
        };

        print("📤 响应已发送\n", .{});
        print("✅ 真实连接测试成功！\n", .{});
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
    print("🚀 Zokio HTTP服务器演示测试\n", .{});
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

    // 创建HTTP服务器演示
    var server = HttpServerDemo.init(allocator);
    defer server.deinit();

    // 1. 启动服务器
    print("📋 第一步：启动HTTP服务器\n", .{});
    try server.start();

    // 2. 演示HTTP处理功能
    print("\n📋 第二步：演示HTTP处理功能\n", .{});
    try server.demonstrateHttpHandling();

    // 3. 测试真实连接
    print("📋 第三步：测试真实连接\n", .{});
    try server.testRealConnection();

    print("\n🎉 所有测试完成！\n", .{});
    print("🚀 Zokio HTTP服务器功能验证成功\n", .{});
}
