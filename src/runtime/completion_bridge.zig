//! 🚀 Zokio 4.0 CompletionBridge - libxev与Future系统的桥接器
//!
//! 这是Zokio 4.0的核心创新，实现了libxev的Completion模式与Zokio Future模式的完美桥接：
//! - 零拷贝事件转换
//! - 类型安全的结果处理
//! - 高性能的异步操作支持
//! - 统一的错误处理机制

const std = @import("std");
const libxev = @import("libxev");
const future = @import("../future/future.zig");
const Waker = @import("waker.zig").Waker;
const Context = @import("waker.zig").Context;
const Poll = future.Poll;

/// 🔧 CompletionBridge状态
pub const BridgeState = enum {
    /// 等待中 - 操作已提交但未完成
    pending,
    /// 就绪 - 操作已完成，结果可用
    ready,
    /// 错误 - 操作失败
    error_occurred,
    /// 超时 - 操作超时
    timeout,
};

/// 🚀 libxev Completion到Zokio Future的桥接器
///
/// 这是Zokio 4.0的核心组件，负责将libxev的基于回调的异步模式
/// 转换为Zokio的基于Future的异步模式。
pub const CompletionBridge = struct {
    const Self = @This();

    /// libxev completion结构
    completion: libxev.Completion,

    /// 桥接器状态
    state: BridgeState,

    /// 操作结果存储
    result: OperationResult,

    /// 用于唤醒等待任务的Waker
    waker: ?Waker,

    /// 操作开始时间（用于超时检测）
    start_time: i128,

    /// 超时时间（纳秒）
    timeout_ns: i128,

    /// 🔧 操作结果联合体
    pub const OperationResult = union(enum) {
        /// 无结果（初始状态）
        none: void,
        /// 读取操作结果
        read: libxev.ReadError!usize,
        /// 写入操作结果
        write: libxev.WriteError!usize,
        /// 接受连接结果
        accept: libxev.AcceptError!libxev.TCP,
        /// 连接操作结果
        connect: libxev.ConnectError!void,
        /// 定时器操作结果
        timer: libxev.Timer.RunError!void,
        /// 文件读取结果
        file_read: libxev.ReadError!usize,
        /// 文件写入结果
        file_write: libxev.WriteError!usize,
        /// 关闭操作结果
        close: libxev.CloseError!void,
    };

    /// 🔧 初始化CompletionBridge
    pub fn init() Self {
        return Self{
            .completion = libxev.Completion{},
            .state = .pending,
            .result = .none,
            .waker = null,
            .start_time = std.time.nanoTimestamp(),
            .timeout_ns = 30_000_000_000, // 默认30秒超时
        };
    }

    /// 🔧 初始化带超时的CompletionBridge
    pub fn initWithTimeout(timeout_ms: u32) Self {
        var bridge = init();
        bridge.timeout_ns = @as(i128, @intCast(timeout_ms)) * 1_000_000;
        return bridge;
    }

    /// 🚀 通用回调函数 - 处理读取完成
    pub fn readCallback(
        bridge: *Self,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.ReadError!usize,
    ) libxev.CallbackAction {
        _ = loop;
        _ = completion;

        // 保存读取结果
        bridge.result = .{ .read = result };
        bridge.state = if (result) |_| .ready else .error_occurred;

        // 唤醒等待的Future
        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 🚀 通用回调函数 - 处理写入完成
    pub fn writeCallback(
        bridge: *Self,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.WriteError!usize,
    ) libxev.CallbackAction {
        _ = loop;
        _ = completion;

        // 保存写入结果
        bridge.result = .{ .write = result };
        bridge.state = if (result) |_| .ready else .error_occurred;

        // 唤醒等待的Future
        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 🚀 通用回调函数 - 处理accept完成
    pub fn acceptCallback(
        bridge: *Self,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.AcceptError!libxev.TCP,
    ) libxev.CallbackAction {
        _ = loop;
        _ = completion;

        // 保存accept结果
        bridge.result = .{ .accept = result };
        bridge.state = if (result) |_| .ready else .error_occurred;

        // 唤醒等待的Future
        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 🚀 通用回调函数 - 处理连接完成
    pub fn connectCallback(
        bridge: *Self,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.ConnectError!void,
    ) libxev.CallbackAction {
        _ = loop;
        _ = completion;

        // 保存连接结果
        bridge.result = .{ .connect = result };
        bridge.state = if (result) |_| .ready else .error_occurred;

        // 唤醒等待的Future
        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 🚀 通用回调函数 - 处理定时器完成
    pub fn timerCallback(
        bridge: *Self,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.Timer.RunError!void,
    ) libxev.CallbackAction {
        _ = loop;
        _ = completion;

        // 保存定时器结果
        bridge.result = .{ .timer = result };
        bridge.state = if (result) |_| .ready else .error_occurred;

        // 唤醒等待的Future
        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 🔍 检查操作是否超时
    pub fn checkTimeout(self: *Self) bool {
        const current_time = std.time.nanoTimestamp();
        const elapsed = current_time - self.start_time;

        if (elapsed > self.timeout_ns and self.state == .pending) {
            self.state = .timeout;
            self.result = .none;
            return true;
        }

        return false;
    }

    /// 🔄 重置桥接器状态
    pub fn reset(self: *Self) void {
        self.state = .pending;
        self.result = .none;
        self.waker = null;
        self.completion = libxev.Completion{};
        self.start_time = std.time.nanoTimestamp();
    }

    /// 🎯 设置Waker
    pub fn setWaker(self: *Self, waker: Waker) void {
        self.waker = waker;
    }

    /// 📊 获取操作状态
    pub fn getState(self: *const Self) BridgeState {
        return self.state;
    }

    /// 🔍 检查操作是否完成
    pub fn isCompleted(self: *const Self) bool {
        return self.state == .ready or self.state == .error_occurred or self.state == .timeout;
    }

    /// 🔍 检查操作是否成功
    pub fn isSuccess(self: *const Self) bool {
        return self.state == .ready;
    }

    /// 🎯 获取操作结果 - 泛型版本
    ///
    /// 根据期望的返回类型T，从桥接器中提取相应的结果。
    /// 这是类型安全的结果获取机制。
    pub fn getResult(self: *Self, comptime T: type) Poll(T) {
        // 首先检查超时
        if (self.checkTimeout()) {
            return .{ .ready = error.Timeout };
        }

        switch (self.state) {
            .pending => return .pending,
            .timeout => {
                if (T == anyerror!usize or T == anyerror!void) {
                    return .{ .ready = error.Timeout };
                }
                return .pending;
            },
            .error_occurred => {
                if (T == anyerror!usize or T == anyerror!void) {
                    return .{ .ready = error.IOError };
                }
                return .pending;
            },
            .ready => {
                return self.extractTypedResult(T);
            },
        }
    }

    /// 🔧 提取类型化结果
    fn extractTypedResult(self: *Self, comptime T: type) Poll(T) {
        switch (self.result) {
            .read => |r| {
                if (T == anyerror!usize) {
                    return .{ .ready = r };
                }
            },
            .write => |r| {
                if (T == anyerror!usize) {
                    return .{ .ready = r };
                }
            },
            .file_read => |r| {
                if (T == anyerror!usize) {
                    return .{ .ready = r };
                }
            },
            .file_write => |r| {
                if (T == anyerror!usize) {
                    return .{ .ready = r };
                }
            },
            .connect => |r| {
                if (T == anyerror!void) {
                    return .{ .ready = r };
                }
            },
            .timer => |r| {
                if (T == anyerror!void) {
                    return .{ .ready = r };
                }
            },
            .close => |r| {
                if (T == anyerror!void) {
                    return .{ .ready = r };
                }
            },
            .accept => |r| {
                // accept结果需要特殊处理，因为返回的是libxev.TCP
                // 在实际使用中，调用者需要将其转换为TcpStream
                _ = r;
                if (T == anyerror!void) {
                    return .{ .ready = {} };
                }
            },
            .none => {
                if (T == anyerror!void) {
                    return .{ .ready = {} };
                }
            },
        }

        // 类型不匹配，返回pending（这通常表示编程错误）
        return .pending;
    }

    /// 🎯 获取原始libxev.TCP结果（用于accept操作）
    pub fn getTcpResult(self: *Self) ?libxev.AcceptError!libxev.TCP {
        if (self.state == .ready) {
            switch (self.result) {
                .accept => |r| return r,
                else => return null,
            }
        }
        return null;
    }

    /// 📊 获取操作统计信息
    pub fn getStats(self: *const Self) BridgeStats {
        const current_time = std.time.nanoTimestamp();
        const elapsed_ns = current_time - self.start_time;

        return BridgeStats{
            .elapsed_ns = elapsed_ns,
            .state = self.state,
            .is_timeout = elapsed_ns > self.timeout_ns,
        };
    }
};

/// 📊 桥接器统计信息
pub const BridgeStats = struct {
    /// 已经过的时间（纳秒）
    elapsed_ns: i128,
    /// 当前状态
    state: BridgeState,
    /// 是否超时
    is_timeout: bool,
};
