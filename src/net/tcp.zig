//! TCP网络模块
//!
//! 提供异步TCP客户端和服务器功能

const std = @import("std");
const builtin = @import("builtin");
// const libxev = @import("libxev"); // 暂时注释掉，因为还没有完全集成

const future = @import("../future/future.zig");
const socket = @import("socket.zig");
const NetError = @import("mod.zig").NetError;

const Future = future.Future;
const Poll = future.Poll;
const Context = future.Context;
const SocketAddr = socket.SocketAddr;
const IpAddr = socket.IpAddr;

/// TCP流
pub const TcpStream = struct {
    fd: std.posix.socket_t,
    local_addr: SocketAddr,
    peer_addr: SocketAddr,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 连接到指定地址
    pub fn connect(allocator: std.mem.Allocator, addr: SocketAddr) !Self {
        const family = switch (addr) {
            .v4 => std.posix.AF.INET,
            .v6 => std.posix.AF.INET6,
        };

        const fd = try std.posix.socket(family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        errdefer std.posix.close(fd);

        // 设置非阻塞模式
        try setNonBlocking(fd);

        // 连接到目标地址
        try connectSocket(fd, addr);

        // 获取本地地址
        const local_addr = try getLocalAddr(fd);

        return Self{
            .fd = fd,
            .local_addr = local_addr,
            .peer_addr = addr,
            .allocator = allocator,
        };
    }

    /// 从文件描述符创建TCP流
    pub fn fromFd(allocator: std.mem.Allocator, fd: std.posix.socket_t) !Self {
        const local_addr = try getLocalAddr(fd);
        const peer_addr = try getPeerAddr(fd);

        return Self{
            .fd = fd,
            .local_addr = local_addr,
            .peer_addr = peer_addr,
            .allocator = allocator,
        };
    }

    /// 关闭连接
    pub fn close(self: *Self) void {
        std.posix.close(self.fd);
    }

    /// 异步读取数据
    pub fn read(self: *Self, buffer: []u8) ReadFuture {
        return ReadFuture.init(self.fd, buffer);
    }

    /// 异步写入数据
    pub fn write(self: *Self, data: []const u8) WriteFuture {
        return WriteFuture.init(self.fd, data);
    }

    /// 获取本地地址
    pub fn localAddr(self: *const Self) SocketAddr {
        return self.local_addr;
    }

    /// 获取对端地址
    pub fn peerAddr(self: *const Self) SocketAddr {
        return self.peer_addr;
    }

    /// 设置TCP_NODELAY选项
    pub fn setNodelay(self: *Self, nodelay: bool) !void {
        const value: c_int = if (nodelay) 1 else 0;
        try std.posix.setsockopt(self.fd, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY, std.mem.asBytes(&value));
    }

    /// 设置SO_KEEPALIVE选项
    pub fn setKeepalive(self: *Self, keepalive: bool) !void {
        const value: c_int = if (keepalive) 1 else 0;
        try std.posix.setsockopt(self.fd, std.posix.SOL.SOCKET, std.posix.SO.KEEPALIVE, std.mem.asBytes(&value));
    }
};

/// TCP监听器
pub const TcpListener = struct {
    fd: std.posix.socket_t,
    local_addr: SocketAddr,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 绑定到指定地址并开始监听
    pub fn bind(allocator: std.mem.Allocator, addr: SocketAddr) !Self {
        const family = switch (addr) {
            .v4 => std.posix.AF.INET,
            .v6 => std.posix.AF.INET6,
        };

        const fd = try std.posix.socket(family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        errdefer std.posix.close(fd);

        // 设置SO_REUSEADDR
        const reuse: c_int = 1;
        try std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&reuse));

        // 设置非阻塞模式
        try setNonBlocking(fd);

        // 绑定地址
        try bindSocket(fd, addr);

        // 开始监听
        try std.posix.listen(fd, 128);

        // 获取实际绑定的地址
        const local_addr = try getLocalAddr(fd);

        return Self{
            .fd = fd,
            .local_addr = local_addr,
            .allocator = allocator,
        };
    }

    /// 关闭监听器
    pub fn close(self: *Self) void {
        std.posix.close(self.fd);
    }

    /// 异步接受连接
    pub fn accept(self: *Self) AcceptFuture {
        return AcceptFuture.init(self.fd, self.allocator);
    }

    /// 获取本地地址
    pub fn localAddr(self: *const Self) SocketAddr {
        return self.local_addr;
    }
};

/// 读取Future
pub const ReadFuture = struct {
    fd: std.posix.socket_t,
    buffer: []u8,
    bytes_read: usize = 0,

    const Self = @This();
    pub const Output = !usize;

    pub fn init(fd: std.posix.socket_t, buffer: []u8) Self {
        return Self{
            .fd = fd,
            .buffer = buffer,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!usize) {
        _ = ctx;

        const result = std.posix.read(self.fd, self.buffer);
        if (result) |bytes_read| {
            self.bytes_read = bytes_read;
            return .{ .ready = bytes_read };
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            else => return .{ .ready = err },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// 写入Future
pub const WriteFuture = struct {
    fd: std.posix.socket_t,
    data: []const u8,
    bytes_written: usize = 0,

    const Self = @This();
    pub const Output = !usize;

    pub fn init(fd: std.posix.socket_t, data: []const u8) Self {
        return Self{
            .fd = fd,
            .data = data,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!usize) {
        _ = ctx;

        const result = std.posix.write(self.fd, self.data[self.bytes_written..]);
        if (result) |bytes_written| {
            self.bytes_written += bytes_written;
            if (self.bytes_written >= self.data.len) {
                return .{ .ready = self.bytes_written };
            } else {
                return .pending;
            }
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            else => return .{ .ready = err },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// 接受连接Future
pub const AcceptFuture = struct {
    fd: std.posix.socket_t,
    allocator: std.mem.Allocator,

    const Self = @This();
    pub const Output = !TcpStream;

    pub fn init(fd: std.posix.socket_t, allocator: std.mem.Allocator) Self {
        return Self{
            .fd = fd,
            .allocator = allocator,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!TcpStream) {
        _ = ctx;

        var addr: std.posix.sockaddr = undefined;
        var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

        const result = std.posix.accept(self.fd, &addr, &addr_len, std.posix.SOCK.CLOEXEC);
        if (result) |client_fd| {
            // 设置非阻塞模式
            setNonBlocking(client_fd) catch |err| {
                std.posix.close(client_fd);
                return .{ .ready = err };
            };

            const stream = TcpStream.fromFd(self.allocator, client_fd) catch |err| {
                std.posix.close(client_fd);
                return .{ .ready = err };
            };

            return .{ .ready = stream };
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            else => return .{ .ready = err },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

// 辅助函数

/// 设置套接字为非阻塞模式
fn setNonBlocking(fd: std.posix.socket_t) !void {
    const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | std.posix.O.NONBLOCK);
}

/// 连接套接字到指定地址
fn connectSocket(fd: std.posix.socket_t, addr: SocketAddr) !void {
    switch (addr) {
        .v4 => |v4_addr| {
            var sockaddr = std.posix.sockaddr.in{
                .family = std.posix.AF.INET,
                .port = std.mem.nativeToBig(u16, v4_addr.port),
                .addr = v4_addr.ip.toU32(),
                .zero = [_]u8{0} ** 8,
            };
            const result = std.posix.connect(fd, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in));
            result catch |err| switch (err) {
                error.WouldBlock => {}, // 非阻塞连接正在进行
                else => return err,
            };
        },
        .v6 => |v6_addr| {
            var sockaddr = std.posix.sockaddr.in6{
                .family = std.posix.AF.INET6,
                .port = std.mem.nativeToBig(u16, v6_addr.port),
                .flowinfo = v6_addr.flowinfo,
                .addr = @bitCast(v6_addr.ip.segments),
                .scope_id = v6_addr.scope_id,
            };
            const result = std.posix.connect(fd, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in6));
            result catch |err| switch (err) {
                error.WouldBlock => {}, // 非阻塞连接正在进行
                else => return err,
            };
        },
    }
}

/// 绑定套接字到指定地址
fn bindSocket(fd: std.posix.socket_t, addr: SocketAddr) !void {
    switch (addr) {
        .v4 => |v4_addr| {
            const sockaddr = std.posix.sockaddr.in{
                .family = std.posix.AF.INET,
                .port = std.mem.nativeToBig(u16, v4_addr.port),
                .addr = v4_addr.ip.toU32(),
                .zero = [_]u8{0} ** 8,
            };
            try std.posix.bind(fd, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in));
        },
        .v6 => |v6_addr| {
            const sockaddr = std.posix.sockaddr.in6{
                .family = std.posix.AF.INET6,
                .port = std.mem.nativeToBig(u16, v6_addr.port),
                .flowinfo = v6_addr.flowinfo,
                .addr = @bitCast(v6_addr.ip.segments),
                .scope_id = v6_addr.scope_id,
            };
            try std.posix.bind(fd, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in6));
        },
    }
}

/// 获取套接字的本地地址
fn getLocalAddr(fd: std.posix.socket_t) !SocketAddr {
    var addr: std.posix.sockaddr = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

    try std.posix.getsockname(fd, &addr, &addr_len);

    return parseSocketAddr(&addr);
}

/// 获取套接字的对端地址
fn getPeerAddr(fd: std.posix.socket_t) !SocketAddr {
    var addr: std.posix.sockaddr = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

    try std.posix.getpeername(fd, &addr, &addr_len);

    return parseSocketAddr(&addr);
}

/// 解析sockaddr结构为SocketAddr
fn parseSocketAddr(addr: *const std.posix.sockaddr) !SocketAddr {
    switch (addr.family) {
        std.posix.AF.INET => {
            const in_addr: *const std.posix.sockaddr.in = @ptrCast(@alignCast(addr));
            const ip = socket.Ipv4Addr.fromU32(in_addr.addr);
            const port = std.mem.bigToNative(u16, in_addr.port);
            return SocketAddr{ .v4 = socket.SocketAddrV4.init(ip, port) };
        },
        std.posix.AF.INET6 => {
            const in6_addr: *const std.posix.sockaddr.in6 = @ptrCast(@alignCast(addr));
            const segments: [8]u16 = @bitCast(in6_addr.addr);
            const ip = socket.Ipv6Addr.init(segments);
            const port = std.mem.bigToNative(u16, in6_addr.port);
            return SocketAddr{ .v6 = socket.SocketAddrV6{
                .ip = ip,
                .port = port,
                .flowinfo = in6_addr.flowinfo,
                .scope_id = in6_addr.scope_id,
            } };
        },
        else => return error.InvalidAddress,
    }
}

// 测试
test "TCP地址解析" {
    const testing = std.testing;

    const addr = try SocketAddr.parse("127.0.0.1:8080");
    try testing.expect(addr.isIpv4());
    try testing.expectEqual(@as(u16, 8080), addr.port());
}
