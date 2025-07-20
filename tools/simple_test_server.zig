//! 🚀 简化的HTTP测试服务器
//! 用于压测的最小化HTTP服务器实现

const std = @import("std");
const print = std.debug.print;

/// 简化的HTTP服务器
const SimpleTestServer = struct {
    allocator: std.mem.Allocator,
    listener: std.net.Server,
    running: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, port: u16) !Self {
        const address = std.net.Address.parseIp("127.0.0.1", port) catch unreachable;
        const listener = try address.listen(.{
            .reuse_address = true,
        });

        return Self{
            .allocator = allocator,
            .listener = listener,
        };
    }

    pub fn deinit(self: *Self) void {
        self.listener.deinit();
    }

    /// 处理单个连接
    fn handleConnection(self: *Self, connection: std.net.Server.Connection) void {
        _ = self;
        defer connection.stream.close();

        // 读取请求
        var buffer: [4096]u8 = undefined;
        const bytes_read = connection.stream.readAll(&buffer) catch |err| {
            print("❌ 读取请求失败: {}\n", .{err});
            return;
        };

        if (bytes_read == 0) return;

        // 简单的HTTP响应
        const response =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Content-Length: 26\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "🚀 Hello from Zokio Test!";

        // 发送响应
        connection.stream.writeAll(response) catch |err| {
            print("❌ 发送响应失败: {}\n", .{err});
            return;
        };
    }

    /// 运行服务器
    pub fn run(self: *Self) !void {
        self.running = true;
        print("🚀 简化HTTP测试服务器启动\n", .{});
        print("📡 监听地址: http://127.0.0.1:8080\n", .{});
        print("🔄 等待连接...\n\n", .{});

        while (self.running) {
            // 接受连接
            const connection = self.listener.accept() catch |err| {
                print("❌ 接受连接失败: {}\n", .{err});
                continue;
            };

            print("✅ 接受到新连接\n", .{});

            // 处理连接
            self.handleConnection(connection);
        }
    }

    pub fn stop(self: *Self) void {
        self.running = false;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try SimpleTestServer.init(allocator, 8080);
    defer server.deinit();

    try server.run();
}
