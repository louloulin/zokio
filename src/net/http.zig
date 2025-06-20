//! HTTP协议模块
//!
//! 提供HTTP/1.1客户端和服务器功能

const std = @import("std");
const builtin = @import("builtin");

const future = @import("../future/future.zig");
const tcp = @import("tcp.zig");
const socket = @import("socket.zig");
const NetError = @import("mod.zig").NetError;

const Future = future.Future;
const Poll = future.Poll;
const Context = future.Context;
const TcpStream = tcp.TcpStream;
const SocketAddr = socket.SocketAddr;

/// HTTP方法
pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,
    TRACE,
    CONNECT,

    /// 从字符串解析HTTP方法
    pub fn parse(str: []const u8) !Method {
        if (std.mem.eql(u8, str, "GET")) return .GET;
        if (std.mem.eql(u8, str, "POST")) return .POST;
        if (std.mem.eql(u8, str, "PUT")) return .PUT;
        if (std.mem.eql(u8, str, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, str, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, str, "OPTIONS")) return .OPTIONS;
        if (std.mem.eql(u8, str, "PATCH")) return .PATCH;
        if (std.mem.eql(u8, str, "TRACE")) return .TRACE;
        if (std.mem.eql(u8, str, "CONNECT")) return .CONNECT;
        return error.InvalidMethod;
    }

    /// 转换为字符串
    pub fn toString(self: Method) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
            .PATCH => "PATCH",
            .TRACE => "TRACE",
            .CONNECT => "CONNECT",
        };
    }
};

/// HTTP状态码
pub const StatusCode = enum(u16) {
    // 1xx 信息性状态码
    Continue = 100,
    SwitchingProtocols = 101,

    // 2xx 成功状态码
    OK = 200,
    Created = 201,
    Accepted = 202,
    NoContent = 204,

    // 3xx 重定向状态码
    MovedPermanently = 301,
    Found = 302,
    NotModified = 304,

    // 4xx 客户端错误状态码
    BadRequest = 400,
    Unauthorized = 401,
    Forbidden = 403,
    NotFound = 404,
    MethodNotAllowed = 405,

    // 5xx 服务器错误状态码
    InternalServerError = 500,
    NotImplemented = 501,
    BadGateway = 502,
    ServiceUnavailable = 503,

    /// 获取状态码的原因短语
    pub fn reasonPhrase(self: StatusCode) []const u8 {
        return switch (self) {
            .Continue => "Continue",
            .SwitchingProtocols => "Switching Protocols",
            .OK => "OK",
            .Created => "Created",
            .Accepted => "Accepted",
            .NoContent => "No Content",
            .MovedPermanently => "Moved Permanently",
            .Found => "Found",
            .NotModified => "Not Modified",
            .BadRequest => "Bad Request",
            .Unauthorized => "Unauthorized",
            .Forbidden => "Forbidden",
            .NotFound => "Not Found",
            .MethodNotAllowed => "Method Not Allowed",
            .InternalServerError => "Internal Server Error",
            .NotImplemented => "Not Implemented",
            .BadGateway => "Bad Gateway",
            .ServiceUnavailable => "Service Unavailable",
        };
    }

    /// 检查是否是成功状态码
    pub fn isSuccess(self: StatusCode) bool {
        const code = @intFromEnum(self);
        return code >= 200 and code < 300;
    }

    /// 检查是否是重定向状态码
    pub fn isRedirection(self: StatusCode) bool {
        const code = @intFromEnum(self);
        return code >= 300 and code < 400;
    }

    /// 检查是否是客户端错误状态码
    pub fn isClientError(self: StatusCode) bool {
        const code = @intFromEnum(self);
        return code >= 400 and code < 500;
    }

    /// 检查是否是服务器错误状态码
    pub fn isServerError(self: StatusCode) bool {
        const code = @intFromEnum(self);
        return code >= 500 and code < 600;
    }
};

/// HTTP版本
pub const Version = enum {
    http1_0,
    http1_1,
    http2,

    /// 从字符串解析HTTP版本
    pub fn parse(str: []const u8) !Version {
        if (std.mem.eql(u8, str, "HTTP/1.0")) return .http1_0;
        if (std.mem.eql(u8, str, "HTTP/1.1")) return .http1_1;
        if (std.mem.eql(u8, str, "HTTP/2")) return .http2;
        return error.InvalidVersion;
    }

    /// 转换为字符串
    pub fn toString(self: Version) []const u8 {
        return switch (self) {
            .http1_0 => "HTTP/1.0",
            .http1_1 => "HTTP/1.1",
            .http2 => "HTTP/2",
        };
    }
};

/// HTTP头部
pub const Headers = struct {
    headers: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    // 存储分配的字符串，用于清理
    allocated_values: std.ArrayList([]u8),

    const Self = @This();

    /// 初始化头部
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .headers = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
            .allocated_values = std.ArrayList([]u8).init(allocator),
        };
    }

    /// 清理头部
    pub fn deinit(self: *Self) void {
        // 释放所有分配的值
        for (self.allocated_values.items) |value| {
            self.allocator.free(value);
        }
        self.allocated_values.deinit();
        self.headers.deinit();
    }

    /// 设置头部
    pub fn set(self: *Self, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    /// 获取头部
    pub fn get(self: *const Self, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// 删除头部
    pub fn remove(self: *Self, name: []const u8) void {
        _ = self.headers.remove(name);
    }

    /// 检查是否包含头部
    pub fn contains(self: *const Self, name: []const u8) bool {
        return self.headers.contains(name);
    }

    /// 获取Content-Length
    pub fn getContentLength(self: *const Self) ?usize {
        if (self.get("Content-Length")) |value| {
            return std.fmt.parseInt(usize, value, 10) catch null;
        }
        return null;
    }

    /// 设置Content-Length
    pub fn setContentLength(self: *Self, length: usize) !void {
        // 分配持久的内存来存储值
        const value = try std.fmt.allocPrint(self.allocator, "{}", .{length});
        // 记录分配的值以便后续清理
        try self.allocated_values.append(value);
        try self.set("Content-Length", value);
    }

    /// 获取Content-Type
    pub fn getContentType(self: *const Self) ?[]const u8 {
        return self.get("Content-Type");
    }

    /// 设置Content-Type
    pub fn setContentType(self: *Self, content_type: []const u8) !void {
        try self.set("Content-Type", content_type);
    }
};

/// HTTP请求
pub const Request = struct {
    method: Method,
    uri: []const u8,
    version: Version,
    headers: Headers,
    body: ?[]const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 创建新的HTTP请求
    pub fn init(allocator: std.mem.Allocator, method: Method, uri: []const u8) Self {
        return Self{
            .method = method,
            .uri = uri,
            .version = .http1_1,
            .headers = Headers.init(allocator),
            .body = null,
            .allocator = allocator,
        };
    }

    /// 清理请求
    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }

    /// 设置请求体
    pub fn setBody(self: *Self, body: []const u8) !void {
        self.body = body;
        try self.headers.setContentLength(body.len);
    }

    /// 序列化请求为字符串
    pub fn serialize(self: *const Self, writer: anytype) !void {
        // 写入请求行
        try writer.print("{s} {s} {s}\r\n", .{ self.method.toString(), self.uri, self.version.toString() });

        // 写入头部
        var iterator = self.headers.headers.iterator();
        while (iterator.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // 写入空行
        try writer.writeAll("\r\n");

        // 写入请求体
        if (self.body) |body| {
            try writer.writeAll(body);
        }
    }
};

/// HTTP响应
pub const Response = struct {
    version: Version,
    status_code: StatusCode,
    headers: Headers,
    body: ?[]const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 创建新的HTTP响应
    pub fn init(allocator: std.mem.Allocator, status_code: StatusCode) Self {
        return Self{
            .version = .http1_1,
            .status_code = status_code,
            .headers = Headers.init(allocator),
            .body = null,
            .allocator = allocator,
        };
    }

    /// 清理响应
    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }

    /// 设置响应体
    pub fn setBody(self: *Self, body: []const u8) !void {
        self.body = body;
        try self.headers.setContentLength(body.len);
    }

    /// 序列化响应为字符串
    pub fn serialize(self: *const Self, writer: anytype) !void {
        // 写入状态行
        try writer.print("{s} {} {s}\r\n", .{ self.version.toString(), @intFromEnum(self.status_code), self.status_code.reasonPhrase() });

        // 写入头部
        var iterator = self.headers.headers.iterator();
        while (iterator.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // 写入空行
        try writer.writeAll("\r\n");

        // 写入响应体
        if (self.body) |body| {
            try writer.writeAll(body);
        }
    }
};

/// HTTP客户端
pub const Client = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 初始化HTTP客户端
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// 发送HTTP请求
    pub fn request(self: *Self, req: Request, addr: SocketAddr) RequestFuture {
        return RequestFuture.init(self.allocator, req, addr);
    }

    /// 发送GET请求
    pub fn get(self: *Self, uri: []const u8, addr: SocketAddr) RequestFuture {
        const req = Request.init(self.allocator, .GET, uri);
        return self.request(req, addr);
    }

    /// 发送POST请求
    pub fn post(self: *Self, uri: []const u8, body: []const u8, addr: SocketAddr) !RequestFuture {
        var req = Request.init(self.allocator, .POST, uri);
        try req.setBody(body);
        return self.request(req, addr);
    }
};

/// HTTP请求Future
pub const RequestFuture = struct {
    allocator: std.mem.Allocator,
    request: Request,
    addr: SocketAddr,
    stream: ?TcpStream = null,
    state: State = .connecting,

    const Self = @This();
    pub const Output = !Response;

    const State = enum {
        connecting,
        sending,
        receiving,
        completed,
    };

    pub fn init(allocator: std.mem.Allocator, request: Request, addr: SocketAddr) Self {
        return Self{
            .allocator = allocator,
            .request = request,
            .addr = addr,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!Response) {
        _ = ctx;
        switch (self.state) {
            .connecting => {
                // 连接到服务器
                if (self.stream == null) {
                    self.stream = TcpStream.connect(self.allocator, self.addr) catch |err| {
                        return .{ .ready = err };
                    };
                }
                self.state = .sending;
                return .pending;
            },
            .sending => {
                // 发送请求
                // 这里需要实际的发送逻辑
                self.state = .receiving;
                return .pending;
            },
            .receiving => {
                // 接收响应
                // 这里需要实际的接收和解析逻辑
                self.state = .completed;

                // 创建一个简单的响应
                const response = Response.init(self.allocator, .OK);
                return .{ .ready = response };
            },
            .completed => {
                // 已完成，返回错误或重复结果
                return .{ .ready = error.AlreadyCompleted };
            },
        }
    }

    pub fn deinit(self: *Self) void {
        self.request.deinit();
        if (self.stream) |*stream| {
            stream.close();
        }
    }
};

// 测试
test "HTTP方法解析" {
    const testing = std.testing;

    try testing.expectEqual(Method.GET, try Method.parse("GET"));
    try testing.expectEqual(Method.POST, try Method.parse("POST"));
    try testing.expectError(error.InvalidMethod, Method.parse("INVALID"));
}

test "HTTP状态码功能" {
    const testing = std.testing;

    try testing.expect(StatusCode.OK.isSuccess());
    try testing.expect(StatusCode.NotFound.isClientError());
    try testing.expect(StatusCode.InternalServerError.isServerError());
    try testing.expect(StatusCode.Found.isRedirection());

    try testing.expect(std.mem.eql(u8, "OK", StatusCode.OK.reasonPhrase()));
}

test "HTTP头部操作" {
    const testing = std.testing;

    var headers = Headers.init(testing.allocator);
    defer headers.deinit();

    try headers.set("Content-Type", "application/json");
    try headers.setContentLength(100);

    try testing.expect(std.mem.eql(u8, "application/json", headers.getContentType().?));
    try testing.expectEqual(@as(usize, 100), headers.getContentLength().?);
}
