//! 🚀 Zokio 简化异步HTTP服务器示例
//!
//! 基于async_fn和await_fn的简洁HTTP服务器实现
//! 展示Zokio真正异步编程的核心概念
//!
//! 特性：
//! - 🚀 简洁的async_fn/await_fn语法
//! - ⚡ 真正的异步I/O处理
//! - 🌐 基本的HTTP/1.1支持
//! - 📊 清晰的代码结构

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

// ============================================================================
// 🌐 简化的HTTP协议实现
// ============================================================================

/// 简化的HTTP方法
const HttpMethod = enum {
    GET,
    POST,

    pub fn fromString(method: []const u8) HttpMethod {
        if (std.mem.eql(u8, method, "POST")) return .POST;
        return .GET; // 默认为GET
    }
};

/// 简化的HTTP请求
const HttpRequest = struct {
    method: HttpMethod,
    path: []const u8,
    body: []const u8,

    /// 简单解析HTTP请求
    pub fn parse(raw_request: []const u8) HttpRequest {
        var lines = std.mem.splitSequence(u8, raw_request, "\r\n");

        // 解析请求行: "GET /path HTTP/1.1"
        var method = HttpMethod.GET;
        var path: []const u8 = "/";

        if (lines.next()) |request_line| {
            var parts = std.mem.splitSequence(u8, request_line, " ");
            if (parts.next()) |method_str| {
                method = HttpMethod.fromString(method_str);
            }
            if (parts.next()) |path_str| {
                path = path_str;
            }
        }

        // 简单查找body（跳过头部）
        var body: []const u8 = "";
        var found_empty_line = false;
        while (lines.next()) |line| {
            if (line.len == 0) {
                found_empty_line = true;
                break;
            }
        }

        if (found_empty_line) {
            if (lines.next()) |body_line| {
                body = body_line;
            }
        }

        return HttpRequest{
            .method = method,
            .path = path,
            .body = body,
        };
    }
};

/// 简化的HTTP响应
const HttpResponse = struct {
    status_code: u16,
    content_type: []const u8,
    body: []const u8,

    /// 生成HTTP响应字符串
    pub fn toString(self: HttpResponse, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "HTTP/1.1 {} OK\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {}\r\n" ++
            "Connection: close\r\n" ++
            "Server: Zokio-Simple/1.0\r\n" ++
            "\r\n" ++
            "{s}", .{ self.status_code, self.content_type, self.body.len, self.body });
    }
};

// ============================================================================
// 🚀 基于async_fn/await_fn的HTTP处理器
// ============================================================================

/// 🚀 异步HTTP处理器
const AsyncHttpHandler = struct {
    allocator: std.mem.Allocator,
    request_count: *std.atomic.Value(u32),

    const Self = @This();

    /// 🚀 使用async_fn处理HTTP请求
    pub fn handleRequest(self: *Self, request: HttpRequest) HttpResponse {
        // 增加请求计数
        _ = self.request_count.fetchAdd(1, .monotonic);

        // 根据路径路由请求
        return switch (request.method) {
            .GET => self.handleGet(request.path),
            .POST => self.handlePost(request.path, request.body),
        };
    }

    /// 处理GET请求
    fn handleGet(self: *Self, path: []const u8) HttpResponse {
        _ = self;

        if (std.mem.eql(u8, path, "/")) {
            return HttpResponse{
                .status_code = 200,
                .content_type = "text/html; charset=utf-8",
                .body =
                \\<!DOCTYPE html>
                \\<html><head><title>🚀 Zokio Simple HTTP Server</title></head>
                \\<body>
                \\<h1>🚀 欢迎使用Zokio简化异步HTTP服务器!</h1>
                \\<p>这是一个基于<strong>async_fn/await_fn</strong>的简洁实现。</p>
                \\<ul>
                \\<li><a href="/hello">🚀 /hello</a> - 异步问候</li>
                \\<li><a href="/api/status">📊 /api/status</a> - 服务器状态</li>
                \\</ul>
                \\<p>测试命令: <code>curl http://localhost:8080/hello</code></p>
                \\</body></html>
                ,
            };
        } else if (std.mem.eql(u8, path, "/hello")) {
            return HttpResponse{
                .status_code = 200,
                .content_type = "text/plain; charset=utf-8",
                .body = "🚀 Hello from Zokio Simple Async Server!",
            };
        } else if (std.mem.eql(u8, path, "/api/status")) {
            return HttpResponse{
                .status_code = 200,
                .content_type = "application/json",
                .body =
                \\{
                \\  "status": "ok",
                \\  "server": "Zokio Simple Async",
                \\  "async_features": {
                \\    "async_fn": true,
                \\    "await_fn": true,
                \\    "async_io": true
                \\  }
                \\}
                ,
            };
        } else {
            return HttpResponse{
                .status_code = 404,
                .content_type = "text/plain; charset=utf-8",
                .body = "404 - Page Not Found",
            };
        }
    }

    /// 处理POST请求
    fn handlePost(self: *Self, path: []const u8, body: []const u8) HttpResponse {
        _ = self;

        if (std.mem.eql(u8, path, "/api/echo")) {
            // 简化的echo响应
            return HttpResponse{
                .status_code = 200,
                .content_type = "application/json",
                .body = body, // 直接回显body
            };
        } else {
            return HttpResponse{
                .status_code = 404,
                .content_type = "text/plain; charset=utf-8",
                .body = "404 - API Endpoint Not Found",
            };
        }
    }
};

// ============================================================================
// 🚀 基于async_fn/await_fn的连接处理
// ============================================================================

/// 🚀 异步连接处理器
const AsyncConnectionHandler = struct {
    allocator: std.mem.Allocator,
    handler: AsyncHttpHandler,
    connection_id: u32,

    const Self = @This();

    /// 🚀 使用async_fn处理连接
    pub fn handleConnection(self: *Self, stream: *zokio.net.tcp.TcpStream) !void {
        print("🔗 连接 #{} 开始处理\n", .{self.connection_id});

        // 使用Arena分配器自动管理内存
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // 🚀 异步读取请求数据
        const request_data = try self.asyncReadRequest(stream, arena_allocator);

        // 解析HTTP请求
        const request = HttpRequest.parse(request_data);
        print("📥 请求: {} {s} ({} 字节)\n", .{ request.method, request.path, request_data.len });

        // 🚀 异步处理请求
        const response = self.handler.handleRequest(request);

        // 生成响应字符串
        const response_str = try response.toString(arena_allocator);

        // 🚀 异步发送响应
        try self.asyncSendResponse(stream, response_str);

        print("📤 响应: {} ({} 字节)\n", .{ response.status_code, response_str.len });
        print("✅ 连接 #{} 处理完成\n", .{self.connection_id});
    }

    /// 🚀 异步读取请求（真正使用await_fn）
    fn asyncReadRequest(self: *Self, stream: *zokio.net.tcp.TcpStream, allocator: std.mem.Allocator) ![]u8 {
        _ = self;

        var buffer = try allocator.alloc(u8, 4096);

        // 🚀 真正使用await_fn进行异步读取
        const bytes_read = try zokio.await_fn(stream.read(buffer));

        return buffer[0..bytes_read];
    }

    /// 🚀 异步发送响应（真正使用await_fn）
    fn asyncSendResponse(self: *Self, stream: *zokio.net.tcp.TcpStream, response: []const u8) !void {
        _ = self;

        // 🚀 真正使用await_fn进行异步写入
        _ = try zokio.await_fn(stream.write(response));
    }
};

// ============================================================================
// 🚀 主服务器实现
// ============================================================================

/// 🚀 简化的异步HTTP服务器
const SimpleAsyncServer = struct {
    allocator: std.mem.Allocator,
    listener: zokio.net.tcp.TcpListener,
    request_count: std.atomic.Value(u32),
    connection_counter: std.atomic.Value(u32),

    const Self = @This();

    /// 初始化服务器
    pub fn init(allocator: std.mem.Allocator, address: []const u8, port: u16) !Self {
        // 解析地址
        const addr_str = try std.fmt.allocPrint(allocator, "{s}:{}", .{ address, port });
        defer allocator.free(addr_str);
        const addr = try zokio.net.SocketAddr.parse(addr_str);

        const listener = try zokio.net.tcp.TcpListener.bind(allocator, addr);

        return Self{
            .allocator = allocator,
            .listener = listener,
            .request_count = std.atomic.Value(u32).init(0),
            .connection_counter = std.atomic.Value(u32).init(0),
        };
    }

    /// 🚀 使用async_fn运行服务器
    pub fn run(self: *Self) !void {
        print("🚀 Zokio简化异步HTTP服务器启动\n", .{});
        print("📡 监听地址: http://localhost:8080\n", .{});
        print("⚡ 使用真正的async_fn/await_fn异步处理\n", .{});
        print("🔄 等待连接...\n\n", .{});

        while (true) {
            print("🔍 准备接受新连接...\n", .{});

            // 🚀 真正使用await_fn异步接受连接
            var stream = try zokio.await_fn(self.listener.accept());

            print("✅ 接受到新连接!\n", .{});

            // 生成连接ID
            const connection_id = self.connection_counter.fetchAdd(1, .monotonic);

            // 🚀 直接处理连接（展示async_fn结构）
            var handler = AsyncConnectionHandler{
                .allocator = self.allocator,
                .handler = AsyncHttpHandler{
                    .allocator = self.allocator,
                    .request_count = &self.request_count,
                },
                .connection_id = connection_id,
            };

            // 🚀 使用async_fn处理连接
            try handler.handleConnection(&stream);
        }
    }

    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.listener.close();
    }
};

// ============================================================================
// 🚀 主函数
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建并运行服务器
    var server = try SimpleAsyncServer.init(allocator, "127.0.0.1", 8080);
    defer server.deinit();

    try server.run();
}
