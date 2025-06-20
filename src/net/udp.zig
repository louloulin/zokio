//! UDP网络模块
//!
//! 提供异步UDP套接字功能

const std = @import("std");
const builtin = @import("builtin");

const future = @import("../future/future.zig");
const socket = @import("socket.zig");
const NetError = @import("mod.zig").NetError;

const Future = future.Future;
const Poll = future.Poll;
const Context = future.Context;
const SocketAddr = socket.SocketAddr;
const IpAddr = socket.IpAddr;

/// UDP套接字
pub const UdpSocket = struct {
    fd: std.posix.socket_t,
    local_addr: SocketAddr,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 绑定到指定地址
    pub fn bind(allocator: std.mem.Allocator, addr: SocketAddr) !Self {
        const family = switch (addr) {
            .v4 => std.posix.AF.INET,
            .v6 => std.posix.AF.INET6,
        };

        const fd = try std.posix.socket(family, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
        errdefer std.posix.close(fd);

        // 设置SO_REUSEADDR
        const reuse: c_int = 1;
        try std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, std.mem.asBytes(&reuse));

        // 设置非阻塞模式
        try setNonBlocking(fd);

        // 绑定地址
        try bindSocket(fd, addr);

        // 获取实际绑定的地址
        const local_addr = try getLocalAddr(fd);

        return Self{
            .fd = fd,
            .local_addr = local_addr,
            .allocator = allocator,
        };
    }

    /// 创建未绑定的UDP套接字
    pub fn unbound(allocator: std.mem.Allocator, family: AddressFamily) !Self {
        const af = switch (family) {
            .ipv4 => std.posix.AF.INET,
            .ipv6 => std.posix.AF.INET6,
        };

        const fd = try std.posix.socket(af, std.posix.SOCK.DGRAM, std.posix.IPPROTO.UDP);
        errdefer std.posix.close(fd);

        // 设置非阻塞模式
        try setNonBlocking(fd);

        // 创建一个未指定的本地地址
        const local_addr = switch (family) {
            .ipv4 => SocketAddr{ .v4 = socket.SocketAddrV4.init(socket.Ipv4Addr.UNSPECIFIED, 0) },
            .ipv6 => SocketAddr{ .v6 = socket.SocketAddrV6.init(socket.Ipv6Addr.UNSPECIFIED, 0) },
        };

        return Self{
            .fd = fd,
            .local_addr = local_addr,
            .allocator = allocator,
        };
    }

    /// 关闭套接字
    pub fn close(self: *Self) void {
        std.posix.close(self.fd);
    }

    /// 异步发送数据到指定地址
    pub fn sendTo(self: *Self, data: []const u8, addr: SocketAddr) SendToFuture {
        return SendToFuture.init(self.fd, data, addr);
    }

    /// 异步接收数据
    pub fn recvFrom(self: *Self, buffer: []u8) RecvFromFuture {
        return RecvFromFuture.init(self.fd, buffer);
    }

    /// 连接到指定地址（用于后续的send/recv操作）
    pub fn connect(self: *Self, addr: SocketAddr) !void {
        try connectSocket(self.fd, addr);
    }

    /// 异步发送数据（需要先connect）
    pub fn send(self: *Self, data: []const u8) SendFuture {
        return SendFuture.init(self.fd, data);
    }

    /// 异步接收数据（需要先connect）
    pub fn recv(self: *Self, buffer: []u8) RecvFuture {
        return RecvFuture.init(self.fd, buffer);
    }

    /// 获取本地地址
    pub fn localAddr(self: *const Self) SocketAddr {
        return self.local_addr;
    }

    /// 设置广播选项
    pub fn setBroadcast(self: *Self, broadcast: bool) !void {
        const value: c_int = if (broadcast) 1 else 0;
        try std.posix.setsockopt(self.fd, std.posix.SOL.SOCKET, std.posix.SO.BROADCAST, std.mem.asBytes(&value));
    }

    /// 加入多播组
    pub fn joinMulticast(self: *Self, multicast_addr: IpAddr, interface_addr: ?IpAddr) !void {
        switch (multicast_addr) {
            .v4 => |ipv4| {
                var mreq = std.posix.ip_mreq{
                    .imr_multiaddr = .{ .s_addr = ipv4.toU32() },
                    .imr_interface = .{ .s_addr = if (interface_addr) |iface|
                        switch (iface) {
                            .v4 => |v4| v4.toU32(),
                            .v6 => return error.InvalidAddress,
                        }
                    else
                        socket.Ipv4Addr.UNSPECIFIED.toU32() },
                };
                try std.posix.setsockopt(self.fd, std.posix.IPPROTO.IP, std.posix.IP.ADD_MEMBERSHIP, std.mem.asBytes(&mreq));
            },
            .v6 => {
                // IPv6多播实现
                return error.NotSupported;
            },
        }
    }

    /// 离开多播组
    pub fn leaveMulticast(self: *Self, multicast_addr: IpAddr, interface_addr: ?IpAddr) !void {
        switch (multicast_addr) {
            .v4 => |ipv4| {
                var mreq = std.posix.ip_mreq{
                    .imr_multiaddr = .{ .s_addr = ipv4.toU32() },
                    .imr_interface = .{ .s_addr = if (interface_addr) |iface|
                        switch (iface) {
                            .v4 => |v4| v4.toU32(),
                            .v6 => return error.InvalidAddress,
                        }
                    else
                        socket.Ipv4Addr.UNSPECIFIED.toU32() },
                };
                try std.posix.setsockopt(self.fd, std.posix.IPPROTO.IP, std.posix.IP.DROP_MEMBERSHIP, std.mem.asBytes(&mreq));
            },
            .v6 => {
                // IPv6多播实现
                return error.NotSupported;
            },
        }
    }
};

/// 地址族
pub const AddressFamily = enum {
    ipv4,
    ipv6,
};

/// SendTo Future
pub const SendToFuture = struct {
    fd: std.posix.socket_t,
    data: []const u8,
    addr: SocketAddr,
    bytes_sent: usize = 0,

    const Self = @This();
    pub const Output = !usize;

    pub fn init(fd: std.posix.socket_t, data: []const u8, addr: SocketAddr) Self {
        return Self{
            .fd = fd,
            .data = data,
            .addr = addr,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!usize) {
        _ = ctx;

        const result = sendToSocket(self.fd, self.data, self.addr);
        if (result) |bytes_sent| {
            self.bytes_sent = bytes_sent;
            return .{ .ready = bytes_sent };
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            else => return .{ .ready = err },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// RecvFrom Future
pub const RecvFromFuture = struct {
    fd: std.posix.socket_t,
    buffer: []u8,
    bytes_received: usize = 0,
    sender_addr: ?SocketAddr = null,

    const Self = @This();
    pub const Output = !struct { usize, SocketAddr };

    pub fn init(fd: std.posix.socket_t, buffer: []u8) Self {
        return Self{
            .fd = fd,
            .buffer = buffer,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(!struct { usize, SocketAddr }) {
        _ = ctx;

        const result = recvFromSocket(self.fd, self.buffer);
        if (result) |recv_result| {
            self.bytes_received = recv_result.bytes;
            self.sender_addr = recv_result.addr;
            return .{ .ready = .{ recv_result.bytes, recv_result.addr } };
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            else => return .{ .ready = err },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// Send Future（用于已连接的套接字）
pub const SendFuture = struct {
    fd: std.posix.socket_t,
    data: []const u8,
    bytes_sent: usize = 0,

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

        const result = std.posix.send(self.fd, self.data, 0);
        if (result) |bytes_sent| {
            self.bytes_sent = bytes_sent;
            return .{ .ready = bytes_sent };
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            else => return .{ .ready = err },
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

/// Recv Future（用于已连接的套接字）
pub const RecvFuture = struct {
    fd: std.posix.socket_t,
    buffer: []u8,
    bytes_received: usize = 0,

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

        const result = std.posix.recv(self.fd, self.buffer, 0);
        if (result) |bytes_received| {
            self.bytes_received = bytes_received;
            return .{ .ready = bytes_received };
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

/// 连接套接字到指定地址
fn connectSocket(fd: std.posix.socket_t, addr: SocketAddr) !void {
    switch (addr) {
        .v4 => |v4_addr| {
            const sockaddr = std.posix.sockaddr.in{
                .family = std.posix.AF.INET,
                .port = std.mem.nativeToBig(u16, v4_addr.port),
                .addr = v4_addr.ip.toU32(),
                .zero = [_]u8{0} ** 8,
            };
            try std.posix.connect(fd, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in));
        },
        .v6 => |v6_addr| {
            const sockaddr = std.posix.sockaddr.in6{
                .family = std.posix.AF.INET6,
                .port = std.mem.nativeToBig(u16, v6_addr.port),
                .flowinfo = v6_addr.flowinfo,
                .addr = @bitCast(v6_addr.ip.segments),
                .scope_id = v6_addr.scope_id,
            };
            try std.posix.connect(fd, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in6));
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

/// 发送数据到指定地址
fn sendToSocket(fd: std.posix.socket_t, data: []const u8, addr: SocketAddr) !usize {
    switch (addr) {
        .v4 => |v4_addr| {
            const sockaddr = std.posix.sockaddr.in{
                .family = std.posix.AF.INET,
                .port = std.mem.nativeToBig(u16, v4_addr.port),
                .addr = v4_addr.ip.toU32(),
                .zero = [_]u8{0} ** 8,
            };
            return std.posix.sendto(fd, data, 0, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in));
        },
        .v6 => |v6_addr| {
            const sockaddr = std.posix.sockaddr.in6{
                .family = std.posix.AF.INET6,
                .port = std.mem.nativeToBig(u16, v6_addr.port),
                .flowinfo = v6_addr.flowinfo,
                .addr = @bitCast(v6_addr.ip.segments),
                .scope_id = v6_addr.scope_id,
            };
            return std.posix.sendto(fd, data, 0, @ptrCast(&sockaddr), @sizeOf(std.posix.sockaddr.in6));
        },
    }
}

/// 从套接字接收数据
fn recvFromSocket(fd: std.posix.socket_t, buffer: []u8) !struct { bytes: usize, addr: SocketAddr } {
    var addr: std.posix.sockaddr = undefined;
    var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

    const bytes = try std.posix.recvfrom(fd, buffer, 0, &addr, &addr_len);
    const socket_addr = try parseSocketAddr(&addr);

    return .{ .bytes = bytes, .addr = socket_addr };
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
test "UDP套接字创建" {
    const testing = std.testing;

    const addr = try SocketAddr.parse("127.0.0.1:0");
    var socket_obj = try UdpSocket.bind(testing.allocator, addr);
    defer socket_obj.close();

    try testing.expect(socket_obj.localAddr().isIpv4());
}
