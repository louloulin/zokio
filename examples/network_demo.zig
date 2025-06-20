//! 网络协议栈演示
//!
//! 展示Zokio的网络功能，包括TCP、UDP、HTTP等协议支持

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 网络协议栈演示 ===\n", .{});

    // 演示1：Socket地址解析
    try demonstrateSocketAddresses();

    // 演示2：HTTP协议功能
    try demonstrateHttpProtocol(allocator);

    // 演示3：TLS配置
    try demonstrateTlsConfig();

    // 演示4：网络统计
    try demonstrateNetworkStats(allocator);

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

/// 演示Socket地址解析功能
fn demonstrateSocketAddresses() !void {
    std.debug.print("\n1. Socket地址解析演示\n", .{});

    // IPv4地址解析
    const ipv4 = try zokio.net.Ipv4Addr.parse("192.168.1.100");
    var ipv4_buf: [16]u8 = undefined;
    const ipv4_str = try ipv4.toString(&ipv4_buf);
    std.debug.print("   IPv4地址: {s}\n", .{ipv4_str});
    std.debug.print("   是否私有: {}\n", .{ipv4.isPrivate()});
    std.debug.print("   是否环回: {}\n", .{ipv4.isLoopback()});

    // IPv6地址解析
    const ipv6 = try zokio.net.Ipv6Addr.parse("2001:db8::1");
    var ipv6_buf: [40]u8 = undefined;
    const ipv6_str = try ipv6.toString(&ipv6_buf);
    std.debug.print("   IPv6地址: {s}\n", .{ipv6_str});
    std.debug.print("   是否环回: {}\n", .{ipv6.isLoopback()});

    // Socket地址解析
    const socket_addr = try zokio.net.SocketAddr.parse("127.0.0.1:8080");
    var socket_buf: [32]u8 = undefined;
    const socket_str = try socket_addr.toString(&socket_buf);
    std.debug.print("   Socket地址: {s}\n", .{socket_str});
    std.debug.print("   IP版本: {s}\n", .{if (socket_addr.isIpv4()) "IPv4" else "IPv6"});
    std.debug.print("   端口: {}\n", .{socket_addr.port()});
    std.debug.print("   是否环回: {}\n", .{socket_addr.ip().isLoopback()});
}

/// 演示HTTP协议功能
fn demonstrateHttpProtocol(allocator: std.mem.Allocator) !void {
    std.debug.print("\n2. HTTP协议功能演示\n", .{});

    // HTTP方法解析
    const method = try zokio.net.http.Method.parse("POST");
    std.debug.print("   HTTP方法: {s}\n", .{method.toString()});

    // HTTP状态码
    const status = zokio.net.http.StatusCode.OK;
    std.debug.print("   状态码: {} {s}\n", .{ @intFromEnum(status), status.reasonPhrase() });
    std.debug.print("   是否成功: {}\n", .{status.isSuccess()});

    // HTTP版本
    const version = zokio.net.http.Version.http1_1;
    std.debug.print("   HTTP版本: {s}\n", .{version.toString()});

    // HTTP头部操作
    var headers = zokio.net.http.Headers.init(allocator);
    defer headers.deinit();

    try headers.set("Content-Type", "application/json");
    try headers.set("User-Agent", "Zokio/1.0");
    try headers.setContentLength(256);

    std.debug.print("   Content-Type: {s}\n", .{headers.getContentType().?});
    std.debug.print("   Content-Length: {}\n", .{headers.getContentLength().?});
    std.debug.print("   包含User-Agent: {}\n", .{headers.contains("User-Agent")});

    // HTTP请求创建
    var request = zokio.net.http.Request.init(allocator, .POST, "/api/data");
    defer request.deinit();

    try request.setBody("{\"message\": \"Hello, Zokio!\"}");
    std.debug.print("   请求方法: {s}\n", .{request.method.toString()});
    std.debug.print("   请求URI: {s}\n", .{request.uri});
    std.debug.print("   请求体长度: {}\n", .{if (request.body) |body| body.len else 0});

    // HTTP响应创建
    var response = zokio.net.http.Response.init(allocator, .OK);
    defer response.deinit();

    try response.setBody("{\"status\": \"success\"}");
    std.debug.print("   响应状态: {} {s}\n", .{ @intFromEnum(response.status_code), response.status_code.reasonPhrase() });
    std.debug.print("   响应体长度: {}\n", .{if (response.body) |body| body.len else 0});

    // 序列化演示
    std.debug.print("   HTTP请求序列化:\n", .{});
    var request_buf = std.ArrayList(u8).init(allocator);
    defer request_buf.deinit();
    try request.serialize(request_buf.writer());
    std.debug.print("   {s}\n", .{request_buf.items});
}

/// 演示TLS配置
fn demonstrateTlsConfig() !void {
    std.debug.print("\n3. TLS配置演示\n", .{});

    // 客户端配置
    const client_config = zokio.net.tls.TlsConfig.client();
    std.debug.print("   客户端配置:\n", .{});
    std.debug.print("     TLS版本: {s}\n", .{client_config.version.toString()});
    std.debug.print("     验证证书: {}\n", .{client_config.verify_cert});
    std.debug.print("     验证主机名: {}\n", .{client_config.verify_hostname});

    // 服务器配置
    const server_config = zokio.net.tls.TlsConfig.server("server.crt", "server.key");
    std.debug.print("   服务器配置:\n", .{});
    std.debug.print("     证书文件: {s}\n", .{server_config.cert_file.?});
    std.debug.print("     私钥文件: {s}\n", .{server_config.key_file.?});
    std.debug.print("     验证证书: {}\n", .{server_config.verify_cert});

    // 带SNI的客户端配置
    const sni_config = client_config.withServerName("example.com");
    std.debug.print("   SNI配置:\n", .{});
    std.debug.print("     服务器名称: {s}\n", .{sni_config.server_name.?});

    // 带ALPN的配置
    const alpn_protocols = [_][]const u8{ "h2", "http/1.1" };
    const alpn_config = client_config.withAlpn(&alpn_protocols);
    std.debug.print("   ALPN配置:\n", .{});
    std.debug.print("     协议数量: {}\n", .{alpn_config.alpn_protocols.len});
    for (alpn_config.alpn_protocols, 0..) |protocol, i| {
        std.debug.print("     协议[{}]: {s}\n", .{ i, protocol });
    }
}

/// 演示网络统计功能
fn demonstrateNetworkStats(allocator: std.mem.Allocator) !void {
    std.debug.print("\n4. 网络统计功能演示\n", .{});

    // 创建网络配置
    const config = zokio.net.NetConfig{
        .enable_ipv6 = true,
        .default_timeout_ms = 30000,
        .connection_pool_size = 100,
        .tcp_nodelay = true,
        .reuse_addr = true,
    };

    std.debug.print("   网络配置:\n", .{});
    std.debug.print("     启用IPv6: {}\n", .{config.enable_ipv6});
    std.debug.print("     默认超时: {}ms\n", .{config.default_timeout_ms});
    std.debug.print("     连接池大小: {}\n", .{config.connection_pool_size});
    std.debug.print("     TCP_NODELAY: {}\n", .{config.tcp_nodelay});
    std.debug.print("     SO_REUSEADDR: {}\n", .{config.reuse_addr});

    // 创建网络管理器
    var manager = zokio.net.NetManager.init(allocator, config);
    defer manager.deinit();

    // 模拟一些网络活动
    manager.updateStats("tcp_connections", 10);
    manager.updateStats("udp_sockets", 5);
    manager.updateStats("bytes_sent", 1024 * 1024);
    manager.updateStats("bytes_received", 2 * 1024 * 1024);
    manager.updateStats("connection_errors", 2);
    manager.updateStats("dns_queries", 50);
    manager.updateStats("tls_handshakes", 8);

    // 获取统计信息
    const stats = manager.getStats();
    std.debug.print("   网络统计:\n", .{});
    std.debug.print("     TCP连接数: {}\n", .{stats.tcp_connections});
    std.debug.print("     UDP套接字数: {}\n", .{stats.udp_sockets});
    std.debug.print("     发送字节数: {} ({d:.2} MB)\n", .{ stats.bytes_sent, @as(f64, @floatFromInt(stats.bytes_sent)) / (1024.0 * 1024.0) });
    std.debug.print("     接收字节数: {} ({d:.2} MB)\n", .{ stats.bytes_received, @as(f64, @floatFromInt(stats.bytes_received)) / (1024.0 * 1024.0) });
    std.debug.print("     连接错误数: {}\n", .{stats.connection_errors});
    std.debug.print("     DNS查询数: {}\n", .{stats.dns_queries});
    std.debug.print("     TLS握手数: {}\n", .{stats.tls_handshakes});

    // 获取吞吐量统计
    const throughput = stats.getThroughputStats();
    std.debug.print("   吞吐量统计:\n", .{});
    std.debug.print("     总字节数: {} ({d:.2} MB)\n", .{ throughput.total_bytes, @as(f64, @floatFromInt(throughput.total_bytes)) / (1024.0 * 1024.0) });
    std.debug.print("     发送字节数: {} ({d:.2} MB)\n", .{ throughput.sent_bytes, @as(f64, @floatFromInt(throughput.sent_bytes)) / (1024.0 * 1024.0) });
    std.debug.print("     接收字节数: {} ({d:.2} MB)\n", .{ throughput.received_bytes, @as(f64, @floatFromInt(throughput.received_bytes)) / (1024.0 * 1024.0) });

    // 获取连接统计
    const connection = stats.getConnectionStats();
    std.debug.print("   连接统计:\n", .{});
    std.debug.print("     活跃连接数: {}\n", .{connection.active_connections});
    std.debug.print("     TCP连接数: {}\n", .{connection.tcp_connections});
    std.debug.print("     UDP套接字数: {}\n", .{connection.udp_sockets});
    std.debug.print("     错误率: {d:.2}%\n", .{connection.error_rate * 100});

    // 重置统计
    manager.resetStats();
    const reset_stats = manager.getStats();
    std.debug.print("   重置后统计:\n", .{});
    std.debug.print("     TCP连接数: {}\n", .{reset_stats.tcp_connections});
    std.debug.print("     总字节数: {}\n", .{reset_stats.bytes_sent + reset_stats.bytes_received});
}
