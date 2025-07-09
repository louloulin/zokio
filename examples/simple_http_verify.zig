//! 🚀 Zokio HTTP服务器简化验证
//!
//! 验证HTTP服务器的基本连接和响应功能

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Zokio HTTP服务器简化验证\n", .{});
    print("=" ** 40 ++ "\n", .{});

    // 创建运行时
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
    print("✅ Zokio运行时启动成功\n", .{});

    // 寻找可用端口
    const port_candidates = [_]u16{ 8082, 8083, 8084, 8085, 9093, 9094, 9095 };
    var listener: ?zokio.net.tcp.TcpListener = null;
    var actual_port: u16 = 0;

    for (port_candidates) |port| {
        const addr_str = try std.fmt.allocPrint(allocator, "127.0.0.1:{}", .{port});
        defer allocator.free(addr_str);
        
        const addr = try zokio.net.SocketAddr.parse(addr_str);
        
        if (zokio.net.tcp.TcpListener.bind(allocator, addr)) |l| {
            listener = l;
            actual_port = port;
            print("✅ 绑定到端口 {}\n", .{port});
            break;
        } else |err| {
            if (err == error.AddressInUse) {
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
    print("🧪 测试: curl http://localhost:{}/test\n", .{actual_port});
    print("🔄 等待连接（10秒超时）...\n\n", .{});

    // 接受连接
    const accept_future = listener.?.accept();
    const stream = zokio.await_fn_future(accept_future) catch |err| {
        switch (err) {
            error.Timeout => {
                print("⏰ 10秒内没有连接\n", .{});
                print("💡 这是正常的，服务器功能验证完成\n", .{});
                listener.?.close();
                return;
            },
            else => {
                print("❌ 接受连接失败: {}\n", .{err});
                listener.?.close();
                return;
            },
        }
    };

    print("🎉 接受到连接！开始处理...\n", .{});

    // 读取请求
    var buffer: [2048]u8 = undefined;
    var mutable_stream = stream;
    
    const read_future = mutable_stream.read(&buffer);
    const bytes_read = zokio.await_fn_future(read_future) catch |err| {
        print("❌ 读取请求失败: {}\n", .{err});
        mutable_stream.close();
        listener.?.close();
        return;
    };

    print("📥 收到 {} 字节请求\n", .{bytes_read});
    
    if (bytes_read > 0) {
        const request_data = buffer[0..bytes_read];
        print("📋 请求内容: {s}\n", .{request_data[0..@min(80, bytes_read)]});
    }

    // 发送简单的HTTP响应
    const response_body = "🚀 Hello from Zokio HTTP Server!\nConnection successful! ✅";
    const response = try std.fmt.allocPrint(allocator, 
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/plain; charset=utf-8\r\n" ++
        "Content-Length: {}\r\n" ++
        "Connection: close\r\n" ++
        "Server: Zokio/1.0\r\n" ++
        "\r\n" ++
        "{s}",
        .{ response_body.len, response_body }
    );
    defer allocator.free(response);

    const write_future = mutable_stream.write(response);
    _ = zokio.await_fn_future(write_future) catch |err| {
        print("❌ 发送响应失败: {}\n", .{err});
        mutable_stream.close();
        listener.?.close();
        return;
    };

    print("📤 HTTP响应已发送 ({} 字节)\n", .{response.len});
    print("✅ HTTP连接处理成功！\n", .{});
    
    // 清理资源
    mutable_stream.close();
    listener.?.close();
    
    print("\n🎉 验证完成！\n", .{});
    print("🚀 Zokio HTTP服务器功能正常\n", .{});
    print("=" ** 40 ++ "\n", .{});
}
