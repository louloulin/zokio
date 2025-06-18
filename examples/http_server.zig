//! HTTP服务器示例
//!
//! 展示Zokio的HTTP服务能力

const std = @import("std");
const zokio = @import("zokio");

/// HTTP请求结构
const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn init(allocator: std.mem.Allocator) HttpRequest {
        return HttpRequest{
            .method = "GET",
            .path = "/",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
        };
    }

    pub fn deinit(self: *HttpRequest) void {
        self.headers.deinit();
    }
};

/// HTTP响应结构
const HttpResponse = struct {
    status_code: u16,
    status_text: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn init(allocator: std.mem.Allocator) HttpResponse {
        return HttpResponse{
            .status_code = 200,
            .status_text = "OK",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
        };
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
    }
};

/// HTTP请求处理器
const HttpHandler = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn handle(self: *Self, request: HttpRequest) !HttpResponse {
        var response = HttpResponse.init(self.allocator);

        // 根据路径处理请求
        if (std.mem.eql(u8, request.path, "/")) {
            response.body =
                \\<!DOCTYPE html>
                \\<html>
                \\<head><title>Zokio HTTP Server</title></head>
                \\<body>
                \\<h1>欢迎使用Zokio HTTP服务器!</h1>
                \\<p>这是一个基于Zig和Zokio构建的高性能异步HTTP服务器。</p>
                \\<ul>
                \\<li><a href="/hello">Hello页面</a></li>
                \\<li><a href="/api/status">API状态</a></li>
                \\</ul>
                \\</body>
                \\</html>
            ;
            try response.headers.put("Content-Type", "text/html; charset=utf-8");
        } else if (std.mem.eql(u8, request.path, "/hello")) {
            response.body = "Hello, Zokio!";
            try response.headers.put("Content-Type", "text/plain; charset=utf-8");
        } else if (std.mem.eql(u8, request.path, "/api/status")) {
            response.body =
                \\{
                \\  "status": "ok",
                \\  "server": "Zokio HTTP Server",
                \\  "version": "0.1.0",
                \\  "timestamp": "2024-01-01T00:00:00Z"
                \\}
            ;
            try response.headers.put("Content-Type", "application/json");
        } else {
            response.status_code = 404;
            response.status_text = "Not Found";
            response.body = "404 - 页面未找到";
            try response.headers.put("Content-Type", "text/plain; charset=utf-8");
        }

        return response;
    }
};

/// HTTP连接处理任务
const HttpConnection = struct {
    client_fd: std.posix.fd_t,
    handler: *HttpHandler,
    buffer: [4096]u8 = undefined,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;

        std.debug.print("处理HTTP连接: {}\n", .{self.client_fd});

        // 简化实现：模拟HTTP请求处理
        var request = HttpRequest.init(self.handler.allocator);
        defer request.deinit();

        // 模拟解析HTTP请求
        request.method = "GET";
        request.path = "/";

        // 处理请求
        var response = self.handler.handle(request) catch |err| {
            std.debug.print("处理请求时出错: {}\n", .{err});
            return .{ .ready = {} };
        };
        defer response.deinit();

        // 模拟发送响应
        std.debug.print("HTTP {} {s} -> {s} {s}\n", .{
            response.status_code,
            response.status_text,
            request.method,
            request.path,
        });

        return .{ .ready = {} };
    }
};

/// HTTP服务器任务
const HttpServer = struct {
    address: std.net.Address,
    handler: HttpHandler,
    listener_fd: ?std.posix.fd_t = null,
    running: bool = false,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        if (!self.running) {
            std.debug.print("启动HTTP服务器，监听地址: {}\n", .{self.address});

            // 简化实现：模拟服务器启动
            self.listener_fd = 1;
            self.running = true;

            std.debug.print("HTTP服务器启动成功，等待连接...\n", .{});
            return .pending;
        }

        // 简化实现：模拟处理HTTP连接
        std.debug.print("接受新HTTP连接\n", .{});

        var connection = HttpConnection{
            .client_fd = 2,
            .handler = &self.handler,
        };

        // 处理连接
        switch (connection.poll(ctx)) {
            .ready => {},
            .pending => return .pending,
        }

        return .{ .ready = {} };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio HTTP服务器示例 ===\n", .{});

    // 创建运行时配置
    const config = zokio.RuntimeConfig{
        .worker_threads = 4,
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .enable_metrics = true,
    };

    // 创建运行时实例
    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    std.debug.print("运行时创建成功\n", .{});

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 创建HTTP处理器
    const handler = HttpHandler{
        .allocator = allocator,
    };

    // 创建服务器地址
    const address = try std.net.Address.parseIp("127.0.0.1", 8080);

    // 创建HTTP服务器
    const server = HttpServer{
        .address = address,
        .handler = handler,
    };

    std.debug.print("\n=== 启动HTTP服务器 ===\n", .{});
    std.debug.print("访问 http://127.0.0.1:8080 查看服务器\n", .{});

    // 运行服务器（简化实现：只运行一次）
    try runtime.blockOn(server);

    std.debug.print("\n=== HTTP服务器示例完成 ===\n", .{});
}
