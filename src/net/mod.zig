//! 网络协议栈模块
//!
//! 提供高性能的异步网络操作支持，包括TCP、UDP、HTTP等协议

const std = @import("std");

// 导出网络相关模块
pub const tcp = @import("tcp.zig");
pub const udp = @import("udp.zig");
pub const http = @import("http.zig");
pub const tls = @import("tls.zig");

// 导出核心类型
pub const SocketAddr = @import("socket.zig").SocketAddr;
pub const IpAddr = @import("socket.zig").IpAddr;
pub const Ipv4Addr = @import("socket.zig").Ipv4Addr;
pub const Ipv6Addr = @import("socket.zig").Ipv6Addr;

// 导出网络错误类型
pub const NetError = error{
    /// 地址已在使用
    AddressInUse,
    /// 地址不可用
    AddressNotAvailable,
    /// 连接被拒绝
    ConnectionRefused,
    /// 连接被重置
    ConnectionReset,
    /// 连接超时
    ConnectionTimeout,
    /// 网络不可达
    NetworkUnreachable,
    /// 主机不可达
    HostUnreachable,
    /// 权限被拒绝
    PermissionDenied,
    /// 资源暂时不可用
    WouldBlock,
    /// 操作被中断
    Interrupted,
    /// 无效的地址格式
    InvalidAddress,
    /// DNS解析失败
    DnsResolutionFailed,
    /// TLS握手失败
    TlsHandshakeFailed,
    /// 协议错误
    ProtocolError,
    /// 缓冲区太小
    BufferTooSmall,
    /// 操作不支持
    NotSupported,
};

/// 网络配置
pub const NetConfig = struct {
    /// TCP配置
    tcp: TcpConfig = .{},
    /// UDP配置
    udp: UdpConfig = .{},
    /// HTTP配置
    http: HttpConfig = .{},
    /// TLS配置
    tls: TlsConfig = .{},
    /// 是否启用IPv6
    enable_ipv6: bool = true,
    /// 默认超时时间（毫秒）
    default_timeout_ms: u32 = 30000,
    /// 连接池大小
    connection_pool_size: u32 = 100,
    /// 是否启用TCP_NODELAY
    tcp_nodelay: bool = true,
    /// 是否启用SO_REUSEADDR
    reuse_addr: bool = true,
    /// 接收缓冲区大小
    recv_buffer_size: u32 = 64 * 1024,
    /// 发送缓冲区大小
    send_buffer_size: u32 = 64 * 1024,
};

/// TCP配置
pub const TcpConfig = struct {
    /// 监听队列长度
    backlog: u32 = 128,
    /// 保活时间（秒）
    keepalive_time: u32 = 7200,
    /// 保活间隔（秒）
    keepalive_interval: u32 = 75,
    /// 保活探测次数
    keepalive_probes: u32 = 9,
    /// 是否启用Nagle算法
    nagle: bool = false,
};

/// UDP配置
pub const UdpConfig = struct {
    /// 是否启用广播
    broadcast: bool = false,
    /// 多播TTL
    multicast_ttl: u8 = 1,
    /// 是否启用多播环回
    multicast_loop: bool = true,
};

/// HTTP配置
pub const HttpConfig = struct {
    /// HTTP版本
    version: HttpVersion = .http1_1,
    /// 最大头部大小
    max_header_size: u32 = 8 * 1024,
    /// 最大请求体大小
    max_body_size: u32 = 1024 * 1024,
    /// 连接超时时间（毫秒）
    connection_timeout_ms: u32 = 30000,
    /// 请求超时时间（毫秒）
    request_timeout_ms: u32 = 60000,
    /// 是否启用压缩
    enable_compression: bool = true,
    /// 是否启用HTTP/2
    enable_http2: bool = false,
};

/// HTTP版本
pub const HttpVersion = enum {
    http1_0,
    http1_1,
    http2,
    http3,
};

/// TLS配置
pub const TlsConfig = struct {
    /// TLS版本
    version: TlsVersion = .tls1_3,
    /// 证书文件路径
    cert_file: ?[]const u8 = null,
    /// 私钥文件路径
    key_file: ?[]const u8 = null,
    /// CA证书文件路径
    ca_file: ?[]const u8 = null,
    /// 是否验证证书
    verify_cert: bool = true,
    /// 是否验证主机名
    verify_hostname: bool = true,
    /// 支持的密码套件
    cipher_suites: []const []const u8 = &.{},
};

/// TLS版本
pub const TlsVersion = enum {
    tls1_0,
    tls1_1,
    tls1_2,
    tls1_3,
};

/// 网络统计信息
pub const NetStats = struct {
    /// TCP连接数
    tcp_connections: u64 = 0,
    /// UDP套接字数
    udp_sockets: u64 = 0,
    /// 发送的字节数
    bytes_sent: u64 = 0,
    /// 接收的字节数
    bytes_received: u64 = 0,
    /// 连接错误数
    connection_errors: u64 = 0,
    /// 超时错误数
    timeout_errors: u64 = 0,
    /// DNS查询数
    dns_queries: u64 = 0,
    /// TLS握手数
    tls_handshakes: u64 = 0,

    /// 获取网络吞吐量统计
    pub fn getThroughputStats(self: *const NetStats) ThroughputStats {
        return ThroughputStats{
            .total_bytes = self.bytes_sent + self.bytes_received,
            .sent_bytes = self.bytes_sent,
            .received_bytes = self.bytes_received,
        };
    }

    /// 获取连接统计
    pub fn getConnectionStats(self: *const NetStats) ConnectionStats {
        return ConnectionStats{
            .active_connections = self.tcp_connections + self.udp_sockets,
            .tcp_connections = self.tcp_connections,
            .udp_sockets = self.udp_sockets,
            .error_rate = if (self.tcp_connections + self.udp_sockets > 0)
                @as(f64, @floatFromInt(self.connection_errors)) / @as(f64, @floatFromInt(self.tcp_connections + self.udp_sockets))
            else
                0.0,
        };
    }
};

/// 吞吐量统计
pub const ThroughputStats = struct {
    total_bytes: u64,
    sent_bytes: u64,
    received_bytes: u64,
};

/// 连接统计
pub const ConnectionStats = struct {
    active_connections: u64,
    tcp_connections: u64,
    udp_sockets: u64,
    error_rate: f64,
};

/// 网络管理器
pub const NetManager = struct {
    config: NetConfig,
    stats: NetStats,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 初始化网络管理器
    pub fn init(allocator: std.mem.Allocator, config: NetConfig) Self {
        return Self{
            .config = config,
            .stats = NetStats{},
            .allocator = allocator,
        };
    }

    /// 清理网络管理器
    pub fn deinit(self: *Self) void {
        _ = self;
        // 清理资源
    }

    /// 获取统计信息
    pub fn getStats(self: *const Self) NetStats {
        return self.stats;
    }

    /// 重置统计信息
    pub fn resetStats(self: *Self) void {
        self.stats = NetStats{};
    }

    /// 更新统计信息
    pub fn updateStats(self: *Self, comptime field: []const u8, delta: u64) void {
        @field(self.stats, field) += delta;
    }
};

// 测试
test "网络配置默认值" {
    const testing = std.testing;

    const config = NetConfig{};
    try testing.expect(config.enable_ipv6);
    try testing.expectEqual(@as(u32, 30000), config.default_timeout_ms);
    try testing.expectEqual(@as(u32, 100), config.connection_pool_size);
    try testing.expect(config.tcp_nodelay);
    try testing.expect(config.reuse_addr);
}

test "网络统计功能" {
    const testing = std.testing;

    var stats = NetStats{};
    stats.tcp_connections = 10;
    stats.udp_sockets = 5;
    stats.bytes_sent = 1000;
    stats.bytes_received = 2000;
    stats.connection_errors = 2;

    const throughput = stats.getThroughputStats();
    try testing.expectEqual(@as(u64, 3000), throughput.total_bytes);
    try testing.expectEqual(@as(u64, 1000), throughput.sent_bytes);
    try testing.expectEqual(@as(u64, 2000), throughput.received_bytes);

    const connection = stats.getConnectionStats();
    try testing.expectEqual(@as(u64, 15), connection.active_connections);
    try testing.expectEqual(@as(u64, 10), connection.tcp_connections);
    try testing.expectEqual(@as(u64, 5), connection.udp_sockets);
    try testing.expectEqual(@as(f64, 2.0 / 15.0), connection.error_rate);
}

test "网络管理器基础功能" {
    const testing = std.testing;

    const config = NetConfig{};
    var manager = NetManager.init(testing.allocator, config);
    defer manager.deinit();

    // 测试统计更新
    manager.updateStats("tcp_connections", 5);
    manager.updateStats("bytes_sent", 1000);

    const stats = manager.getStats();
    try testing.expectEqual(@as(u64, 5), stats.tcp_connections);
    try testing.expectEqual(@as(u64, 1000), stats.bytes_sent);

    // 测试重置
    manager.resetStats();
    const reset_stats = manager.getStats();
    try testing.expectEqual(@as(u64, 0), reset_stats.tcp_connections);
    try testing.expectEqual(@as(u64, 0), reset_stats.bytes_sent);
}
