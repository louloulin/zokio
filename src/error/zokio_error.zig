//! 🚀 Zokio 统一错误处理系统
//!
//! 这是 Zokio 的统一错误处理系统，提供：
//! - 结构化错误类型
//! - 错误传播机制
//! - 详细的错误诊断信息
//! - RAII 模式的资源管理
//! - 生产级错误日志

const std = @import("std");

/// 🎯 Zokio 统一错误类型
pub const ZokioError = union(enum) {
    /// I/O 错误
    io_error: IOError,
    /// 网络错误
    network_error: NetworkError,
    /// 超时错误
    timeout_error: TimeoutError,
    /// 资源错误
    resource_error: ResourceError,
    /// 运行时错误
    runtime_error: RuntimeError,
    /// 内存错误
    memory_error: MemoryError,
    /// 任务错误
    task_error: TaskError,

    /// 🔧 I/O 错误详细信息
    pub const IOError = struct {
        kind: IOErrorKind,
        message: []const u8,
        file_path: ?[]const u8 = null,
        line_number: ?u32 = null,
        errno: ?i32 = null,
        
        pub const IOErrorKind = enum {
            file_not_found,
            permission_denied,
            file_exists,
            read_error,
            write_error,
            seek_error,
            flush_error,
            close_error,
            invalid_path,
            device_full,
            interrupted,
            would_block,
        };
    };

    /// 🌐 网络错误详细信息
    pub const NetworkError = struct {
        kind: NetworkErrorKind,
        address: ?std.net.Address = null,
        port: ?u16 = null,
        message: []const u8,
        errno: ?i32 = null,
        
        pub const NetworkErrorKind = enum {
            connection_refused,
            connection_reset,
            connection_timeout,
            address_in_use,
            address_not_available,
            network_unreachable,
            host_unreachable,
            dns_resolution_failed,
            tls_handshake_failed,
            protocol_error,
            invalid_address,
            socket_error,
        };
    };

    /// ⏰ 超时错误详细信息
    pub const TimeoutError = struct {
        operation: []const u8,
        timeout_duration: u64, // 纳秒
        elapsed_duration: u64, // 纳秒
        message: []const u8,
    };

    /// 📦 资源错误详细信息
    pub const ResourceError = struct {
        kind: ResourceErrorKind,
        resource_type: []const u8,
        message: []const u8,
        
        pub const ResourceErrorKind = enum {
            resource_exhausted,
            resource_not_found,
            resource_busy,
            resource_locked,
            resource_corrupted,
            quota_exceeded,
            handle_invalid,
        };
    };

    /// 🏃 运行时错误详细信息
    pub const RuntimeError = struct {
        kind: RuntimeErrorKind,
        component: []const u8,
        message: []const u8,
        
        pub const RuntimeErrorKind = enum {
            runtime_not_started,
            runtime_shutdown,
            scheduler_error,
            event_loop_error,
            thread_pool_error,
            configuration_error,
            initialization_error,
        };
    };

    /// 💾 内存错误详细信息
    pub const MemoryError = struct {
        kind: MemoryErrorKind,
        requested_size: ?usize = null,
        available_size: ?usize = null,
        message: []const u8,
        
        pub const MemoryErrorKind = enum {
            out_of_memory,
            allocation_failed,
            deallocation_failed,
            memory_leak,
            double_free,
            use_after_free,
            buffer_overflow,
            alignment_error,
        };
    };

    /// 📋 任务错误详细信息
    pub const TaskError = struct {
        kind: TaskErrorKind,
        task_id: ?u64 = null,
        message: []const u8,
        
        pub const TaskErrorKind = enum {
            task_cancelled,
            task_panicked,
            task_timeout,
            task_spawn_failed,
            task_join_failed,
            task_not_found,
            task_already_finished,
        };
    };

    /// 🔍 获取错误的简短描述
    pub fn getShortDescription(self: ZokioError) []const u8 {
        return switch (self) {
            .io_error => |err| switch (err.kind) {
                .file_not_found => "文件未找到",
                .permission_denied => "权限被拒绝",
                .read_error => "读取错误",
                .write_error => "写入错误",
                else => "I/O 错误",
            },
            .network_error => |err| switch (err.kind) {
                .connection_refused => "连接被拒绝",
                .connection_timeout => "连接超时",
                .dns_resolution_failed => "DNS 解析失败",
                else => "网络错误",
            },
            .timeout_error => "操作超时",
            .resource_error => |err| switch (err.kind) {
                .resource_exhausted => "资源耗尽",
                .resource_not_found => "资源未找到",
                else => "资源错误",
            },
            .runtime_error => |err| switch (err.kind) {
                .runtime_not_started => "运行时未启动",
                .runtime_shutdown => "运行时已关闭",
                else => "运行时错误",
            },
            .memory_error => |err| switch (err.kind) {
                .out_of_memory => "内存不足",
                .allocation_failed => "内存分配失败",
                else => "内存错误",
            },
            .task_error => |err| switch (err.kind) {
                .task_cancelled => "任务被取消",
                .task_panicked => "任务崩溃",
                else => "任务错误",
            },
        };
    }

    /// 📝 获取详细的错误信息
    pub fn getDetailedMessage(self: ZokioError, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .io_error => |err| {
                if (err.file_path) |path| {
                    return std.fmt.allocPrint(allocator, "I/O 错误: {s} (文件: {s}, 行: {?})", .{ err.message, path, err.line_number });
                } else {
                    return std.fmt.allocPrint(allocator, "I/O 错误: {s}", .{err.message});
                }
            },
            .network_error => |err| {
                if (err.address) |addr| {
                    return std.fmt.allocPrint(allocator, "网络错误: {s} (地址: {}, 端口: {?})", .{ err.message, addr, err.port });
                } else {
                    return std.fmt.allocPrint(allocator, "网络错误: {s}", .{err.message});
                }
            },
            .timeout_error => |err| {
                const timeout_ms = err.timeout_duration / 1_000_000;
                const elapsed_ms = err.elapsed_duration / 1_000_000;
                return std.fmt.allocPrint(allocator, "超时错误: {s} (超时: {}ms, 已用: {}ms)", .{ err.message, timeout_ms, elapsed_ms });
            },
            .resource_error => |err| {
                return std.fmt.allocPrint(allocator, "资源错误: {s} (资源类型: {s})", .{ err.message, err.resource_type });
            },
            .runtime_error => |err| {
                return std.fmt.allocPrint(allocator, "运行时错误: {s} (组件: {s})", .{ err.message, err.component });
            },
            .memory_error => |err| {
                if (err.requested_size) |size| {
                    return std.fmt.allocPrint(allocator, "内存错误: {s} (请求大小: {} 字节)", .{ err.message, size });
                } else {
                    return std.fmt.allocPrint(allocator, "内存错误: {s}", .{err.message});
                }
            },
            .task_error => |err| {
                if (err.task_id) |id| {
                    return std.fmt.allocPrint(allocator, "任务错误: {s} (任务ID: {})", .{ err.message, id });
                } else {
                    return std.fmt.allocPrint(allocator, "任务错误: {s}", .{err.message});
                }
            },
        };
    }

    /// 🔄 从标准错误转换
    pub fn fromStdError(err: anyerror, context: []const u8) ZokioError {
        return switch (err) {
            error.FileNotFound => .{ .io_error = .{
                .kind = .file_not_found,
                .message = context,
            }},
            error.AccessDenied, error.PermissionDenied => .{ .io_error = .{
                .kind = .permission_denied,
                .message = context,
            }},
            error.OutOfMemory => .{ .memory_error = .{
                .kind = .out_of_memory,
                .message = context,
            }},
            error.ConnectionRefused => .{ .network_error = .{
                .kind = .connection_refused,
                .message = context,
            }},
            error.Timeout => .{ .timeout_error = .{
                .operation = context,
                .timeout_duration = 0,
                .elapsed_duration = 0,
                .message = "操作超时",
            }},
            else => .{ .runtime_error = .{
                .kind = .initialization_error,
                .component = "unknown",
                .message = context,
            }},
        };
    }
};

/// 🛡️ 错误处理结果类型
pub fn ErrorResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ZokioError,

        pub fn isOk(self: @This()) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }

        pub fn isErr(self: @This()) bool {
            return !self.isOk();
        }

        pub fn unwrap(self: @This()) T {
            return switch (self) {
                .ok => |value| value,
                .err => |err| {
                    std.log.err("尝试解包错误结果: {s}", .{err.getShortDescription()});
                    @panic("尝试解包错误结果");
                },
            };
        }

        pub fn unwrapOr(self: @This(), default: T) T {
            return switch (self) {
                .ok => |value| value,
                .err => default,
            };
        }

        pub fn expect(self: @This(), message: []const u8) T {
            return switch (self) {
                .ok => |value| value,
                .err => |err| {
                    std.log.err("{s}: {s}", .{ message, err.getShortDescription() });
                    @panic(message);
                },
            };
        }
    };
}
