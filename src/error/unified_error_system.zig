//! 🛡️ Zokio 统一错误处理系统
//!
//! 这是 Zokio 的核心错误处理系统，提供：
//! - 统一的错误类型定义
//! - 结构化错误信息
//! - 错误传播和转换机制
//! - 生产级错误日志
//! - 错误恢复策略

const std = @import("std");

/// 🎯 Zokio 统一错误类型
///
/// 所有 Zokio 组件都应该使用这个统一的错误类型，
/// 确保错误处理的一致性和可维护性。
pub const ZokioError = union(enum) {
    /// 运行时错误
    runtime: RuntimeError,
    /// I/O 错误
    io: IoError,
    /// 网络错误
    network: NetworkError,
    /// 内存错误
    memory: MemoryError,
    /// 任务错误
    task: TaskError,
    /// 超时错误
    timeout: TimeoutError,
    /// 配置错误
    config: ConfigError,
    /// 系统错误
    system: SystemError,

    /// 🏃 运行时错误
    pub const RuntimeError = struct {
        kind: Kind,
        message: []const u8,
        component: []const u8,
        context: ?[]const u8 = null,

        pub const Kind = enum {
            not_initialized,
            already_running,
            shutdown_in_progress,
            scheduler_failure,
            event_loop_failure,
            thread_pool_failure,
            invalid_state,
        };
    };

    /// 📁 I/O 错误
    pub const IoError = struct {
        kind: Kind,
        message: []const u8,
        path: ?[]const u8 = null,
        errno: ?i32 = null,

        pub const Kind = enum {
            file_not_found,
            permission_denied,
            file_exists,
            read_failure,
            write_failure,
            seek_failure,
            flush_failure,
            close_failure,
            invalid_path,
            device_full,
            interrupted,
            would_block,
        };
    };

    /// 🌐 网络错误
    pub const NetworkError = struct {
        kind: Kind,
        message: []const u8,
        address: ?[]const u8 = null,
        port: ?u16 = null,

        pub const Kind = enum {
            connection_refused,
            connection_reset,
            connection_timeout,
            dns_resolution_failed,
            invalid_address,
            network_unreachable,
            host_unreachable,
            protocol_error,
            ssl_error,
        };
    };

    /// 🧠 内存错误
    pub const MemoryError = struct {
        kind: Kind,
        message: []const u8,
        requested_size: ?usize = null,
        available_size: ?usize = null,

        pub const Kind = enum {
            out_of_memory,
            allocation_failed,
            invalid_free,
            double_free,
            memory_leak,
            buffer_overflow,
            use_after_free,
            alignment_error,
        };
    };

    /// 📋 任务错误
    pub const TaskError = struct {
        kind: Kind,
        message: []const u8,
        task_id: ?u64 = null,

        pub const Kind = enum {
            task_cancelled,
            task_panicked,
            task_timeout,
            spawn_failed,
            join_failed,
            invalid_task,
            queue_full,
        };
    };

    /// ⏰ 超时错误
    pub const TimeoutError = struct {
        operation: []const u8,
        timeout_duration: u64, // 纳秒
        elapsed_duration: u64, // 纳秒
        message: []const u8,
    };

    /// ⚙️ 配置错误
    pub const ConfigError = struct {
        kind: Kind,
        message: []const u8,
        field_name: ?[]const u8 = null,

        pub const Kind = enum {
            invalid_value,
            missing_required_field,
            conflicting_options,
            unsupported_platform,
            version_mismatch,
        };
    };

    /// 🖥️ 系统错误
    pub const SystemError = struct {
        kind: Kind,
        message: []const u8,
        errno: ?i32 = null,

        pub const Kind = enum {
            platform_not_supported,
            resource_exhausted,
            permission_denied,
            operation_not_permitted,
            system_call_failed,
        };
    };

    /// 📝 格式化错误信息
    pub fn format(
        self: ZokioError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (self) {
            .runtime => |err| try writer.print("运行时错误[{s}]: {s} (组件: {s})", .{ @tagName(err.kind), err.message, err.component }),
            .io => |err| try writer.print("I/O错误[{s}]: {s}", .{ @tagName(err.kind), err.message }),
            .network => |err| try writer.print("网络错误[{s}]: {s}", .{ @tagName(err.kind), err.message }),
            .memory => |err| try writer.print("内存错误[{s}]: {s}", .{ @tagName(err.kind), err.message }),
            .task => |err| try writer.print("任务错误[{s}]: {s}", .{ @tagName(err.kind), err.message }),
            .timeout => |err| try writer.print("超时错误: {s} (超时: {}ms, 已用: {}ms)", .{ err.message, err.timeout_duration / 1_000_000, err.elapsed_duration / 1_000_000 }),
            .config => |err| try writer.print("配置错误[{s}]: {s}", .{ @tagName(err.kind), err.message }),
            .system => |err| try writer.print("系统错误[{s}]: {s}", .{ @tagName(err.kind), err.message }),
        }
    }

    /// 🔄 从标准错误转换
    pub fn fromStdError(err: anyerror, context: []const u8) ZokioError {
        return switch (err) {
            error.FileNotFound => .{ .io = .{
                .kind = .file_not_found,
                .message = context,
            } },
            error.AccessDenied, error.PermissionDenied => .{ .io = .{
                .kind = .permission_denied,
                .message = context,
            } },
            error.OutOfMemory => .{ .memory = .{
                .kind = .out_of_memory,
                .message = context,
            } },
            error.ConnectionRefused => .{ .network = .{
                .kind = .connection_refused,
                .message = context,
            } },
            error.Timeout => .{ .timeout = .{
                .operation = context,
                .timeout_duration = 0,
                .elapsed_duration = 0,
                .message = "操作超时",
            } },
            else => .{ .system = .{
                .kind = .system_call_failed,
                .message = context,
                .errno = null,
            } },
        };
    }

    /// 📊 获取错误严重级别
    pub fn getSeverity(self: ZokioError) Severity {
        return switch (self) {
            .runtime => |err| switch (err.kind) {
                .not_initialized, .invalid_state => .warning,
                .already_running => .info,
                else => Severity.@"error",
            },
            .io => |err| switch (err.kind) {
                .would_block, .interrupted => .info,
                .file_not_found => .warning,
                else => Severity.@"error",
            },
            .network => |err| switch (err.kind) {
                .connection_timeout => .warning,
                else => Severity.@"error",
            },
            .memory => .critical,
            .task => |err| switch (err.kind) {
                .task_cancelled => .info,
                .task_timeout => .warning,
                else => Severity.@"error",
            },
            .timeout => .warning,
            .config => Severity.@"error",
            .system => .critical,
        };
    }

    /// 🎯 错误严重级别
    pub const Severity = enum {
        info,
        warning,
        @"error",
        critical,
    };
};

/// 📋 错误结果类型
///
/// 用于包装可能失败的操作结果
pub fn ErrorResult(comptime T: type) type {
    return union(enum) {
        success: T,
        failure: ZokioError,

        /// 检查是否成功
        pub fn isSuccess(self: @This()) bool {
            return switch (self) {
                .success => true,
                .failure => false,
            };
        }

        /// 获取成功值，失败时返回错误
        pub fn unwrap(self: @This()) !T {
            return switch (self) {
                .success => |value| value,
                .failure => |err| {
                    std.log.err("操作失败: {}", .{err});
                    return error.OperationFailed;
                },
            };
        }

        /// 获取成功值，失败时返回默认值
        pub fn unwrapOr(self: @This(), default: T) T {
            return switch (self) {
                .success => |value| value,
                .failure => default,
            };
        }
    };
}

/// 🛡️ 错误处理宏
///
/// 简化错误处理代码的编写
pub fn try_zokio(result: anytype) !@TypeOf(result.success) {
    return switch (result) {
        .success => |value| value,
        .failure => |err| {
            std.log.err("Zokio 错误: {}", .{err});
            return error.ZokioError;
        },
    };
}

/// 📝 错误日志记录器
pub const ErrorLogger = struct {
    allocator: std.mem.Allocator,
    log_file: ?std.fs.File = null,

    pub fn init(allocator: std.mem.Allocator, log_file_path: ?[]const u8) !ErrorLogger {
        var logger = ErrorLogger{
            .allocator = allocator,
        };

        if (log_file_path) |path| {
            logger.log_file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        }

        return logger;
    }

    pub fn deinit(self: *ErrorLogger) void {
        if (self.log_file) |file| {
            file.close();
        }
    }

    /// 记录错误
    pub fn logError(self: *ErrorLogger, err: ZokioError, context: ?[]const u8) void {
        const timestamp = std.time.timestamp();
        const severity = err.getSeverity();

        // 控制台输出
        switch (severity) {
            .info => std.log.info("Zokio: {}", .{err}),
            .warning => std.log.warn("Zokio: {}", .{err}),
            .@"error" => std.log.err("Zokio: {}", .{err}),
            .critical => {
                std.log.err("Zokio CRITICAL: {}", .{err});
                // 关键错误可能需要特殊处理
            },
        }

        // 文件输出
        if (self.log_file) |file| {
            const writer = file.writer();
            writer.print("[{}] [{}] {}", .{ timestamp, @tagName(severity), err }) catch {};
            if (context) |ctx| {
                writer.print(" (上下文: {s})", .{ctx}) catch {};
            }
            writer.writeAll("\n") catch {};
        }
    }
};

// 🧪 测试
test "ZokioError 基本功能" {
    const testing = std.testing;

    // 测试错误创建
    const io_error = ZokioError{ .io = .{
        .kind = .file_not_found,
        .message = "文件未找到",
        .path = "/test/file.txt",
    } };

    // 测试错误严重级别
    try testing.expect(io_error.getSeverity() == .warning);

    // 测试错误转换
    const std_error = ZokioError.fromStdError(error.OutOfMemory, "内存分配失败");
    try testing.expect(std_error.getSeverity() == .critical);
}

test "ErrorResult 功能测试" {
    const testing = std.testing;

    // 测试成功情况
    const success_result = ErrorResult(i32){ .success = 42 };
    try testing.expect(success_result.isSuccess());
    try testing.expectEqual(@as(i32, 42), try success_result.unwrap());

    // 测试失败情况
    const failure_result = ErrorResult(i32){ .failure = .{ .system = .{
        .kind = .system_call_failed,
        .message = "系统调用失败",
    } } };
    try testing.expect(!failure_result.isSuccess());
    try testing.expectEqual(@as(i32, -1), failure_result.unwrapOr(-1));
}
