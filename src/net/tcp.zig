//! TCP网络模块
//!
//! 提供异步TCP客户端和服务器功能

const std = @import("std");
const builtin = @import("builtin");
const libxev = @import("libxev");

const future = @import("../core/future.zig");
const socket = @import("socket.zig");
const NetError = @import("mod.zig").NetError;

// Zokio 4.0 真正异步I/O导入
const CompletionBridge = @import("../runtime/completion_bridge.zig").CompletionBridge;
const AsyncEventLoop = @import("../runtime/async_event_loop.zig").AsyncEventLoop;

const Future = future.Future;
const Poll = future.Poll;
const Context = future.Context;
const Waker = future.Waker;
const SocketAddr = socket.SocketAddr;
const IpAddr = socket.IpAddr;

/// 🚀 Zokio 4.0 获取当前事件循环
///
/// 从当前上下文获取事件循环实例
fn getCurrentEventLoop() ?*AsyncEventLoop {
    // 导入运行时模块以访问全局事件循环管理
    const runtime = @import("../core/runtime.zig");
    return runtime.getCurrentEventLoop();
}

/// TCP流
pub const TcpStream = struct {
    fd: std.posix.socket_t,
    local_addr: SocketAddr,
    peer_addr: SocketAddr,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// 连接到指定地址
    pub fn connect(allocator: std.mem.Allocator, addr: SocketAddr) !Self {
        const family: u32 = switch (addr) {
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
        const family: u32 = switch (addr) {
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

/// 🚀 Zokio 4.0 基于libxev的真正异步读取Future
///
/// 这是Zokio 4.0的核心突破，使用CompletionBridge实现libxev与Future的完美桥接，
/// 提供真正的零拷贝、事件驱动的异步读取。
pub const ReadFuture = struct {
    /// libxev TCP连接
    xev_tcp: ?libxev.TCP = null,
    /// 文件描述符（降级使用）
    fd: std.posix.socket_t,
    /// 读取缓冲区
    buffer: []u8,
    /// CompletionBridge桥接器
    bridge: CompletionBridge,
    /// 事件循环引用
    event_loop: ?*AsyncEventLoop = null,

    const Self = @This();
    pub const Output = anyerror!usize;

    pub fn init(fd: std.posix.socket_t, buffer: []u8) Self {
        return Self{
            .fd = fd,
            .buffer = buffer,
            .bridge = CompletionBridge.init(),
        };
    }

    /// 🚀 Zokio 4.0 基于CompletionBridge的异步轮询实现
    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!usize) {
        // 首次轮询：初始化libxev TCP连接
        if (self.xev_tcp == null and self.event_loop == null) {
            self.event_loop = getCurrentEventLoop();

            if (self.event_loop) |event_loop| {
                // 尝试从文件描述符创建libxev TCP连接
                self.xev_tcp = libxev.TCP.initFd(self.fd);

                if (self.xev_tcp) |*tcp| {
                    // 🚀 使用libxev进行真正的异步读取
                    return self.submitLibxevRead(tcp, &event_loop.libxev_loop, ctx.waker);
                }
            }

            // 降级到非阻塞I/O
            return self.tryDirectRead();
        }

        // 检查CompletionBridge状态
        if (self.bridge.isCompleted()) {
            return self.bridge.getResult(anyerror!usize);
        }

        // 如果有libxev连接，检查是否需要重新提交
        if (self.xev_tcp) |*tcp| {
            if (self.event_loop) |event_loop| {
                return self.submitLibxevRead(tcp, &event_loop.libxev_loop, ctx.waker);
            }
        }

        // 降级处理
        return self.tryDirectRead();
    }

    /// 🚀 提交libxev异步读取操作
    fn submitLibxevRead(self: *Self, tcp: *libxev.TCP, loop: *libxev.Loop, waker: Waker) Poll(anyerror!usize) {
        if (self.bridge.getState() == .pending) {
            // 设置Waker
            self.bridge.setWaker(waker);

            // 提交读取操作到libxev - 使用正确的API
            tcp.read(
                loop,
                &self.bridge.completion,
                .{ .slice = self.buffer },
                CompletionBridge,
                &self.bridge,
                CompletionBridge.readCompletionCallback,
            );
        }

        return .pending;
    }

    /// 🔄 降级到直接非阻塞读取
    fn tryDirectRead(self: *Self) Poll(anyerror!usize) {
        const result = std.posix.read(self.fd, self.buffer);
        if (result) |bytes_read| {
            return .{ .ready = bytes_read };
        } else |err| switch (err) {
            error.WouldBlock => return .pending,
            else => return .{ .ready = err },
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.xev_tcp) |*tcp| {
            tcp.deinit();
        }
    }

    /// 重置Future状态
    pub fn reset(self: *Self) void {
        self.bridge.reset();
        if (self.xev_tcp) |*tcp| {
            tcp.deinit();
            self.xev_tcp = null;
        }
    }
};

/// 🚀 Zokio 4.0 基于libxev的真正异步写入Future
///
/// 这是Zokio 4.0的核心突破，使用CompletionBridge实现libxev与Future的完美桥接，
/// 提供真正的零拷贝、事件驱动的异步写入。
pub const WriteFuture = struct {
    /// libxev TCP连接
    xev_tcp: ?libxev.TCP = null,
    /// 文件描述符（降级使用）
    fd: std.posix.socket_t,
    /// 写入数据
    data: []const u8,
    /// 已写入字节数
    bytes_written: usize = 0,
    /// CompletionBridge桥接器
    bridge: CompletionBridge,
    /// 事件循环引用
    event_loop: ?*AsyncEventLoop = null,

    const Self = @This();
    pub const Output = anyerror!usize;

    pub fn init(fd: std.posix.socket_t, data: []const u8) Self {
        return Self{
            .fd = fd,
            .data = data,
            .bridge = CompletionBridge.init(),
        };
    }

    /// 🚀 Zokio 4.0 基于CompletionBridge的异步轮询实现
    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!usize) {
        // 首次轮询：初始化libxev TCP连接
        if (self.xev_tcp == null and self.event_loop == null) {
            self.event_loop = getCurrentEventLoop();

            if (self.event_loop) |event_loop| {
                // 尝试从文件描述符创建libxev TCP连接
                self.xev_tcp = libxev.TCP.initFd(self.fd);

                if (self.xev_tcp) |*tcp| {
                    // 🚀 使用libxev进行真正的异步写入
                    return self.submitLibxevWrite(tcp, &event_loop.libxev_loop, ctx.waker);
                }
            }

            // 降级到非阻塞I/O
            return self.tryDirectWrite();
        }

        // 检查CompletionBridge状态
        if (self.bridge.isCompleted()) {
            const result = self.bridge.getResult(anyerror!usize);
            if (result == .ready) {
                // 更新已写入字节数
                if (result.ready) |bytes| {
                    self.bytes_written += bytes;

                    // 检查是否还有数据需要写入
                    if (self.bytes_written < self.data.len) {
                        // 重置桥接器，准备下一次写入
                        self.bridge.reset();
                        return .pending;
                    }

                    return .{ .ready = self.bytes_written };
                } else |err| {
                    return .{ .ready = err };
                }
            }
            return result;
        }

        // 如果有libxev连接，检查是否需要重新提交
        if (self.xev_tcp) |*tcp| {
            if (self.event_loop) |event_loop| {
                return self.submitLibxevWrite(tcp, &event_loop.libxev_loop, ctx.waker);
            }
        }

        // 降级处理
        return self.tryDirectWrite();
    }

    /// 🚀 提交libxev异步写入操作
    fn submitLibxevWrite(self: *Self, tcp: *libxev.TCP, loop: *libxev.Loop, waker: Waker) Poll(anyerror!usize) {
        if (self.bridge.getState() == .pending) {
            // 设置Waker
            self.bridge.setWaker(waker);

            // 获取剩余要写入的数据
            const remaining_data = self.data[self.bytes_written..];

            // 提交写入操作到libxev - 使用正确的API
            tcp.write(
                loop,
                &self.bridge.completion,
                .{ .slice = remaining_data },
                CompletionBridge,
                &self.bridge,
                CompletionBridge.writeCompletionCallback,
            );
        }

        return .pending;
    }

    /// � 降级到直接非阻塞写入
    fn tryDirectWrite(self: *Self) Poll(anyerror!usize) {
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
        if (self.xev_tcp) |*tcp| {
            tcp.deinit();
        }
    }

    /// 重置Future状态
    pub fn reset(self: *Self) void {
        self.bytes_written = 0;
        self.bridge.reset();
        if (self.xev_tcp) |*tcp| {
            tcp.deinit();
            self.xev_tcp = null;
        }
    }
};

/// 🚀 Zokio 4.0 基于libxev的真正异步接受连接Future
///
/// 这是Zokio 4.0的核心突破，使用CompletionBridge实现libxev与Future的完美桥接，
/// 提供真正的零拷贝、事件驱动的异步连接接受。
pub const AcceptFuture = struct {
    /// libxev TCP监听器
    xev_tcp: ?libxev.TCP = null,
    /// 监听器文件描述符（降级使用）
    listener_fd: std.posix.socket_t,
    /// 分配器
    allocator: std.mem.Allocator,
    /// CompletionBridge桥接器
    bridge: CompletionBridge,
    /// 事件循环引用
    event_loop: ?*AsyncEventLoop = null,

    const Self = @This();
    pub const Output = anyerror!TcpStream;

    pub fn init(fd: std.posix.socket_t, allocator: std.mem.Allocator) Self {
        return Self{
            .listener_fd = fd,
            .allocator = allocator,
            .bridge = CompletionBridge.init(),
        };
    }

    /// 🚀 Zokio 4.0 基于CompletionBridge的异步轮询实现
    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!TcpStream) {
        // 首次轮询：初始化libxev TCP监听器
        if (self.xev_tcp == null and self.event_loop == null) {
            self.event_loop = getCurrentEventLoop();

            if (self.event_loop) |event_loop| {
                // 尝试从文件描述符创建libxev TCP监听器
                self.xev_tcp = libxev.TCP.initFd(self.listener_fd);

                if (self.xev_tcp) |*tcp| {
                    // 🚀 使用libxev进行真正的异步accept
                    return self.submitLibxevAccept(tcp, &event_loop.libxev_loop, ctx.waker);
                }
            }

            // 降级到非阻塞I/O
            return self.tryDirectAccept();
        }

        // 检查CompletionBridge状态
        if (self.bridge.isCompleted()) {
            // 获取libxev.TCP结果
            if (self.bridge.getTcpResult()) |tcp_result| {
                if (tcp_result) |xev_tcp| {
                    // 将libxev.TCP转换为TcpStream
                    const client_fd = xev_tcp.fd;
                    const stream = TcpStream.fromFd(self.allocator, client_fd) catch |err| {
                        return .{ .ready = err };
                    };
                    return .{ .ready = stream };
                } else |err| {
                    return .{ .ready = err };
                }
            }

            // 如果没有TCP结果，检查其他结果类型
            return self.bridge.getResult(anyerror!TcpStream);
        }

        // 如果有libxev连接，检查是否需要重新提交
        if (self.xev_tcp) |*tcp| {
            if (self.event_loop) |event_loop| {
                return self.submitLibxevAccept(tcp, &event_loop.libxev_loop, ctx.waker);
            }
        }

        // 降级处理
        return self.tryDirectAccept();
    }

    /// 🚀 提交libxev异步accept操作
    fn submitLibxevAccept(self: *Self, tcp: *libxev.TCP, loop: *libxev.Loop, waker: Waker) Poll(anyerror!TcpStream) {
        if (self.bridge.getState() == .pending) {
            // 设置Waker
            self.bridge.setWaker(waker);

            // 提交accept操作到libxev - 使用正确的API
            tcp.accept(
                loop,
                &self.bridge.completion,
                CompletionBridge,
                &self.bridge,
                CompletionBridge.acceptCompletionCallback,
            );
        }

        return .pending;
    }

    /// � 降级到直接非阻塞accept
    fn tryDirectAccept(self: *Self) Poll(anyerror!TcpStream) {
        var addr: std.posix.sockaddr = undefined;
        var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

        const result = std.posix.accept(self.listener_fd, &addr, &addr_len, std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK);
        if (result) |client_fd| {
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
        if (self.xev_tcp) |*tcp| {
            tcp.deinit();
        }
    }

    /// 重置Future状态
    pub fn reset(self: *Self) void {
        self.bridge.reset();
        if (self.xev_tcp) |*tcp| {
            tcp.deinit();
            self.xev_tcp = null;
        }
    }
};

// 辅助函数

/// 设置套接字为非阻塞模式
fn setNonBlocking(fd: std.posix.socket_t) !void {
    const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    const nonblock_flag = switch (builtin.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos => 0x0004, // O_NONBLOCK on Darwin
        else => std.posix.O.NONBLOCK,
    };
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | nonblock_flag);
}

/// 连接套接字到指定地址
fn connectSocket(fd: std.posix.socket_t, addr: SocketAddr) !void {
    switch (addr) {
        .v4 => |v4_addr| {
            var sockaddr = std.posix.sockaddr.in{
                .family = std.posix.AF.INET,
                .port = std.mem.nativeToBig(u16, v4_addr.port),
                .addr = std.mem.bigToNative(u32, v4_addr.ip.toU32()), // 转换为主机字节序
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
                .addr = std.mem.bigToNative(u32, v4_addr.ip.toU32()), // 转换为主机字节序
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
