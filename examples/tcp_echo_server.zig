//! TCP回显服务器示例
//!
//! 展示Zokio的网络编程能力

const std = @import("std");
const zokio = @import("zokio");

/// TCP连接处理任务
const ConnectionHandler = struct {
    client_fd: std.posix.fd_t,
    buffer: [1024]u8 = undefined,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;

        // 简化实现：模拟读取和回显
        std.debug.print("处理客户端连接: {}\n", .{self.client_fd});

        // 在实际实现中，这里会：
        // 1. 异步读取客户端数据
        // 2. 处理数据
        // 3. 异步写回客户端

        const message = "Echo: Hello from Zokio server!";
        std.debug.print("回显消息: {s}\n", .{message});

        return .{ .ready = {} };
    }
};

/// TCP服务器任务
const TcpServer = struct {
    address: std.net.Address,
    listener_fd: ?std.posix.fd_t = null,
    running: bool = false,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        if (!self.running) {
            std.debug.print("启动TCP服务器，监听地址: {}\n", .{self.address});

            // 简化实现：模拟服务器启动
            self.listener_fd = 1; // 模拟文件描述符
            self.running = true;

            std.debug.print("服务器启动成功，等待连接...\n", .{});
            return .pending;
        }

        // 简化实现：模拟接受连接
        std.debug.print("接受新连接\n", .{});

        // 在实际实现中，这里会：
        // 1. 异步接受新连接
        // 2. 为每个连接创建处理任务
        // 3. 将任务提交给调度器

        var handler = ConnectionHandler{
            .client_fd = 2, // 模拟客户端文件描述符
        };

        // 模拟处理连接
        switch (handler.poll(ctx)) {
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

    std.debug.print("=== Zokio TCP回显服务器示例 ===\n", .{});

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
    std.debug.print("I/O后端: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.io_backend});

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 创建服务器地址
    const address = try std.net.Address.parseIp("127.0.0.1", 8080);

    // 创建服务器任务
    const server = TcpServer{
        .address = address,
    };

    std.debug.print("\n=== 启动服务器 ===\n", .{});

    // 运行服务器（简化实现：只运行一次）
    try runtime.blockOn(server);

    std.debug.print("\n=== 服务器示例完成 ===\n", .{});
}
