//! 🚀 Zokio HTTP服务器真实连接测试
//!
//! 这个测试创建一个真实的HTTP服务器并测试连接

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 启动Zokio HTTP服务器真实连接测试\n", .{});

    // 创建简单运行时
    const config = zokio.RuntimeConfig{
        .worker_threads = 1,
        .enable_work_stealing = false,
        .enable_io_uring = false,
        .enable_metrics = false,
        .memory_strategy = .general_purpose,
    };

    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    print("✅ 运行时启动成功\n", .{});

    // 尝试绑定到可用端口
    const port_candidates = [_]u16{ 8080, 8081, 8082, 9090, 9091, 9092 };
    var listener: ?zokio.net.tcp.TcpListener = null;
    var actual_port: u16 = 0;

    for (port_candidates) |port| {
        const addr_str = try std.fmt.allocPrint(allocator, "127.0.0.1:{}", .{port});
        defer allocator.free(addr_str);
        
        const addr = try zokio.net.SocketAddr.parse(addr_str);
        
        if (zokio.net.tcp.TcpListener.bind(allocator, addr)) |l| {
            listener = l;
            actual_port = port;
            print("✅ 服务器绑定到端口 {}\n", .{port});
            break;
        } else |err| {
            if (err == error.AddressInUse) {
                print("   端口 {} 被占用\n", .{port});
                continue;
            } else {
                print("   端口 {} 绑定失败: {}\n", .{ port, err });
                continue;
            }
        }
    }

    if (listener == null) {
        print("❌ 无法找到可用端口\n", .{});
        return;
    }

    print("🌐 HTTP服务器启动成功！\n", .{});
    print("📡 监听地址: http://localhost:{}\n", .{actual_port});
    print("🧪 测试命令: curl http://localhost:{}/hello\n", .{actual_port});
    print("🔄 等待连接...\n\n", .{});

    // 接受一个连接
    const accept_future = listener.?.accept();
    const stream = zokio.await_fn_future(accept_future) catch |err| {
        switch (err) {
            error.Timeout => {
                print("⏰ 等待连接超时\n", .{});
                print("💡 请在另一个终端运行: curl http://localhost:{}/hello\n", .{actual_port});
                return;
            },
            else => {
                print("❌ 接受连接失败: {}\n", .{err});
                return;
            },
        }
    };

    print("🎉 接受到连接！\n", .{});

    // 读取请求
    var buffer: [4096]u8 = undefined;
    var mutable_stream = stream;
    
    const read_future = mutable_stream.read(&buffer);
    const bytes_read = zokio.await_fn_future(read_future) catch |err| {
        print("❌ 读取请求失败: {}\n", .{err});
        return;
    };

    print("📥 收到 {} 字节请求数据\n", .{bytes_read});
    
    // 解析请求路径
    const request_data = buffer[0..bytes_read];
    print("📋 请求内容: {s}\n", .{request_data[0..@min(100, bytes_read)]});

    // 发送HTTP响应
    const response = 
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/plain; charset=utf-8\r\n" ++
        "Content-Length: 42\r\n" ++
        "Connection: close\r\n" ++
        "Server: Zokio/1.0\r\n" ++
        "\r\n" ++
        "🚀 Hello from Zokio HTTP Server! 成功连接！";

    const write_future = mutable_stream.write(response);
    _ = zokio.await_fn_future(write_future) catch |err| {
        print("❌ 发送响应失败: {}\n", .{err});
        return;
    };

    print("📤 HTTP响应已发送 ({} 字节)\n", .{response.len});
    print("✅ HTTP连接处理成功！\n", .{});
    
    // 关闭连接
    mutable_stream.close();
    listener.?.close();
    
    print("🎉 测试完成！Zokio HTTP服务器工作正常\n", .{});
}
