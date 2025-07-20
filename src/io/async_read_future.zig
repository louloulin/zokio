//! 🚀 Zokio 7.0 - 基于 libxev 的真正异步 ReadFuture
//!
//! 核心改进：
//! 1. 完全基于 libxev 事件驱动，消除轮询
//! 2. 使用 CompletionBridge 实现类型安全的异步操作
//! 3. 支持 TCP、UDP、文件等多种读取操作
//! 4. 零拷贝设计，高性能实现

const std = @import("std");
const xev = @import("libxev");
const future = @import("../core/future.zig");
const CompletionBridge = @import("../runtime/completion_bridge.zig").CompletionBridge;
const AsyncEventLoop = @import("../runtime/async_event_loop.zig").AsyncEventLoop;

/// 🔧 读取操作类型
pub const ReadType = enum {
    tcp_read,    // TCP 套接字读取
    udp_read,    // UDP 套接字读取
    file_read,   // 文件读取
    pipe_read,   // 管道读取
};

/// 🚀 基于 libxev 的异步读取 Future
pub const AsyncReadFuture = struct {
    const Self = @This();

    /// 读取类型
    read_type: ReadType,

    /// CompletionBridge 桥接器
    bridge: CompletionBridge,

    /// 事件循环引用
    event_loop: *AsyncEventLoop,

    /// 读取缓冲区
    buffer: []u8,

    /// 资源句柄（文件描述符或 libxev 对象）
    resource: union(ReadType) {
        tcp_read: *xev.TCP,
        udp_read: *xev.UDP,
        file_read: *xev.File,
        pipe_read: i32, // 文件描述符
    },

    /// 是否已提交操作
    submitted: bool = false,

    /// Future trait 实现
    pub const Output = anyerror!usize;

    /// 🔧 创建 TCP 读取 Future
    pub fn tcp(event_loop: *AsyncEventLoop, tcp_stream: *xev.TCP, buffer: []u8) Self {
        return Self{
            .read_type = .tcp_read,
            .bridge = CompletionBridge.init(),
            .event_loop = event_loop,
            .buffer = buffer,
            .resource = .{ .tcp_read = tcp_stream },
        };
    }

    /// 🔧 创建文件读取 Future
    pub fn file(event_loop: *AsyncEventLoop, file: *xev.File, buffer: []u8) Self {
        return Self{
            .read_type = .file_read,
            .bridge = CompletionBridge.init(),
            .event_loop = event_loop,
            .buffer = buffer,
            .resource = .{ .file_read = file },
        };
    }

    /// 🔧 创建 UDP 读取 Future
    pub fn udp(event_loop: *AsyncEventLoop, udp_socket: *xev.UDP, buffer: []u8) Self {
        return Self{
            .read_type = .udp_read,
            .bridge = CompletionBridge.init(),
            .event_loop = event_loop,
            .buffer = buffer,
            .resource = .{ .udp_read = udp_socket },
        };
    }

    /// 🚀 Future.poll 实现 - 核心异步逻辑
    pub fn poll(self: *Self, ctx: *future.Context) future.Poll(Output) {
        // 检查是否已经完成
        if (self.bridge.isCompleted()) {
            return self.bridge.getResult(Output);
        }

        // 如果还未提交操作，现在提交
        if (!self.submitted) {
            self.submitOperation(ctx) catch |err| {
                return .{ .ready = err };
            };
            self.submitted = true;
        }

        // 检查超时
        if (self.bridge.checkTimeout()) {
            return .{ .ready = error.Timeout };
        }

        // 操作仍在进行中
        return .pending;
    }

    /// 🔥 提交异步读取操作到 libxev
    fn submitOperation(self: *Self, ctx: *future.Context) !void {
        // 设置 Waker 以便操作完成时唤醒
        self.bridge.setWaker(ctx.waker);

        // 根据读取类型提交相应的操作
        switch (self.read_type) {
            .tcp_read => {
                try self.submitTcpRead();
            },
            .file_read => {
                try self.submitFileRead();
            },
            .udp_read => {
                try self.submitUdpRead();
            },
            .pipe_read => {
                try self.submitPipeRead();
            },
        }
    }

    /// 🔥 提交 TCP 读取操作
    fn submitTcpRead(self: *Self) !void {
        const tcp_stream = self.resource.tcp_read;
        
        // 使用 libxev 的异步读取
        tcp_stream.read(
            &self.event_loop.xev_loop,
            &self.bridge.completion,
            .{ .slice = self.buffer },
            CompletionBridge,
            &self.bridge,
            CompletionBridge.readCallback,
        );
    }

    /// 🔥 提交文件读取操作
    fn submitFileRead(self: *Self) !void {
        const file = self.resource.file_read;
        
        // 使用 libxev 的异步文件读取
        file.read(
            &self.event_loop.xev_loop,
            &self.bridge.completion,
            .{ .slice = self.buffer },
            CompletionBridge,
            &self.bridge,
            CompletionBridge.readCallback,
        );
    }

    /// 🔥 提交 UDP 读取操作
    fn submitUdpRead(self: *Self) !void {
        const udp_socket = self.resource.udp_read;
        
        // 使用 libxev 的异步 UDP 读取
        udp_socket.read(
            &self.event_loop.xev_loop,
            &self.bridge.completion,
            .{ .slice = self.buffer },
            CompletionBridge,
            &self.bridge,
            CompletionBridge.readCallback,
        );
    }

    /// 🔥 提交管道读取操作
    fn submitPipeRead(self: *Self) !void {
        // 对于管道，我们需要使用文件 API
        const fd = self.resource.pipe_read;
        const file = xev.File.initFd(fd);
        
        file.read(
            &self.event_loop.xev_loop,
            &self.bridge.completion,
            .{ .slice = self.buffer },
            CompletionBridge,
            &self.bridge,
            CompletionBridge.readCallback,
        );
    }

    /// 🔄 重置 Future 状态（用于重用）
    pub fn reset(self: *Self, new_buffer: []u8) void {
        self.bridge.reset();
        self.buffer = new_buffer;
        self.submitted = false;
    }

    /// 🧹 清理资源
    pub fn deinit(self: *Self) void {
        // CompletionBridge 会自动清理
        self.bridge.reset();
    }

    /// 📊 获取操作统计信息
    pub fn getStats(self: *const Self) struct {
        read_type: ReadType,
        buffer_size: usize,
        submitted: bool,
        bridge_stats: @TypeOf(self.bridge.getStats()),
    } {
        return .{
            .read_type = self.read_type,
            .buffer_size = self.buffer.len,
            .submitted = self.submitted,
            .bridge_stats = self.bridge.getStats(),
        };
    }

    /// 🎯 获取读取进度（如果支持）
    pub fn getProgress(self: *const Self) ?f32 {
        // 对于流式读取，进度难以确定
        // 但我们可以基于时间给出一个估计
        const stats = self.bridge.getStats();
        if (stats.elapsed_ns > 0) {
            const progress = @as(f32, @floatFromInt(stats.elapsed_ns)) / @as(f32, @floatFromInt(self.bridge.timeout_ns));
            return @min(progress, 1.0);
        }
        return null;
    }
};

/// 🧪 便利函数：创建 TCP 读取 Future
pub fn readTcp(event_loop: *AsyncEventLoop, tcp_stream: *xev.TCP, buffer: []u8) AsyncReadFuture {
    return AsyncReadFuture.tcp(event_loop, tcp_stream, buffer);
}

/// 🧪 便利函数：创建文件读取 Future
pub fn readFile(event_loop: *AsyncEventLoop, file: *xev.File, buffer: []u8) AsyncReadFuture {
    return AsyncReadFuture.file(event_loop, file, buffer);
}

/// 🧪 便利函数：创建 UDP 读取 Future
pub fn readUdp(event_loop: *AsyncEventLoop, udp_socket: *xev.UDP, buffer: []u8) AsyncReadFuture {
    return AsyncReadFuture.udp(event_loop, udp_socket, buffer);
}

/// 🧪 测试辅助函数
pub fn createTestReadFuture(event_loop: *AsyncEventLoop, buffer: []u8) AsyncReadFuture {
    // 创建一个模拟的 TCP 读取 Future 用于测试
    var tcp = std.testing.allocator.create(xev.TCP) catch unreachable;
    return AsyncReadFuture.tcp(event_loop, tcp, buffer);
}
