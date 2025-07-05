//! 🛡️ Zokio 统一错误处理模块
//!
//! 这个模块提供了 Zokio 的完整错误处理解决方案：
//! - 统一的错误类型系统
//! - RAII 资源管理
//! - 生产级错误日志
//! - 错误恢复机制
//! - 性能监控和诊断

const std = @import("std");

// 导出核心错误处理组件
pub const ZokioError = @import("zokio_error.zig").ZokioError;
pub const ErrorResult = @import("zokio_error.zig").ErrorResult;

pub const ResourceManager = @import("resource_manager.zig").ResourceManager;
pub const RAIIWrapper = @import("resource_manager.zig").RAIIWrapper;
pub const ScopedResourceManager = @import("resource_manager.zig").ScopedResourceManager;

pub const ErrorLogger = @import("error_logger.zig").ErrorLogger;
pub const LogLevel = @import("error_logger.zig").LogLevel;
pub const LogEntry = @import("error_logger.zig").LogEntry;
pub const ErrorLoggerConfig = @import("error_logger.zig").ErrorLoggerConfig;

// 导出便捷函数
pub const logError = @import("error_logger.zig").logError;
pub const logWarn = @import("error_logger.zig").logWarn;
pub const logInfo = @import("error_logger.zig").logInfo;
pub const logDebug = @import("error_logger.zig").logDebug;
pub const initGlobalLogger = @import("error_logger.zig").initGlobalLogger;
pub const deinitGlobalLogger = @import("error_logger.zig").deinitGlobalLogger;

/// 🎯 错误处理上下文
pub const ErrorContext = struct {
    operation: []const u8,
    component: []const u8,
    start_time: i64,
    resource_manager: ?*ResourceManager = null,

    /// 🚀 创建错误上下文
    pub fn init(operation: []const u8, component: []const u8) ErrorContext {
        return ErrorContext{
            .operation = operation,
            .component = component,
            .start_time = @intCast(std.time.nanoTimestamp()),
        };
    }

    /// ⏱️ 获取操作耗时（纳秒）
    pub fn getElapsedTime(self: *const ErrorContext) u64 {
        const now: i64 = @intCast(std.time.nanoTimestamp());
        return @intCast(now - self.start_time);
    }

    /// 🛡️ 设置资源管理器
    pub fn setResourceManager(self: *ErrorContext, manager: *ResourceManager) void {
        self.resource_manager = manager;
    }

    /// 📝 记录错误
    pub fn recordError(self: *const ErrorContext, err: ZokioError, message: []const u8) void {
        const elapsed_ms = self.getElapsedTime() / 1_000_000;

        // 构建详细的错误消息
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const detailed_message = std.fmt.allocPrint(allocator, "{s} 在 {s} 组件中失败 (耗时: {}ms): {s}", .{ self.operation, self.component, elapsed_ms, message }) catch message;

        logError(detailed_message, err);
    }

    /// ✅ 记录成功
    pub fn recordSuccess(self: *const ErrorContext) void {
        const elapsed_ms = self.getElapsedTime() / 1_000_000;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const message = std.fmt.allocPrint(allocator, "{s} 在 {s} 组件中成功完成 (耗时: {}ms)", .{ self.operation, self.component, elapsed_ms }) catch "操作成功完成";

        logInfo(message);
    }
};

/// 🔄 错误恢复策略
pub const RecoveryStrategy = enum {
    /// 立即失败
    fail_fast,
    /// 重试操作
    retry,
    /// 使用默认值
    use_default,
    /// 降级服务
    degrade_service,
    /// 忽略错误
    ignore,
};

/// 🔄 重试配置
pub const RetryConfig = struct {
    max_attempts: u32 = 3,
    initial_delay_ms: u64 = 100,
    max_delay_ms: u64 = 5000,
    backoff_multiplier: f64 = 2.0,
    jitter: bool = true,
};

/// 🔄 错误恢复器
pub const ErrorRecovery = struct {
    strategy: RecoveryStrategy,
    retry_config: RetryConfig,

    /// 🚀 创建错误恢复器
    pub fn init(strategy: RecoveryStrategy, retry_config: RetryConfig) ErrorRecovery {
        return ErrorRecovery{
            .strategy = strategy,
            .retry_config = retry_config,
        };
    }

    /// 🔄 执行带恢复的操作
    pub fn executeWithRecovery(
        self: *const ErrorRecovery,
        comptime T: type,
        operation: *const fn () anyerror!T,
        default_value: ?T,
        context: *const ErrorContext,
    ) anyerror!T {
        switch (self.strategy) {
            .fail_fast => {
                return operation() catch |err| {
                    const zokio_err = ZokioError.fromStdError(err, context.operation);
                    context.recordError(zokio_err, @errorName(err));
                    return err;
                };
            },
            .retry => {
                return self.executeWithRetry(T, operation, context);
            },
            .use_default => {
                return operation() catch |err| {
                    const zokio_err = ZokioError.fromStdError(err, context.operation);
                    context.recordError(zokio_err, @errorName(err));

                    if (default_value) |default| {
                        logWarn("使用默认值恢复操作");
                        return default;
                    } else {
                        return err;
                    }
                };
            },
            .degrade_service => {
                return operation() catch |err| {
                    const zokio_err = ZokioError.fromStdError(err, context.operation);
                    context.recordError(zokio_err, "服务降级");
                    logWarn("服务降级模式激活");

                    if (default_value) |default| {
                        return default;
                    } else {
                        return err;
                    }
                };
            },
            .ignore => {
                return operation() catch |err| {
                    const zokio_err = ZokioError.fromStdError(err, context.operation);
                    context.recordError(zokio_err, "错误被忽略");
                    logWarn("忽略错误继续执行");

                    if (default_value) |default| {
                        return default;
                    } else {
                        // 对于 ignore 策略，如果没有默认值，我们需要返回一个"安全"的值
                        // 这里的实现取决于具体的类型 T
                        return err;
                    }
                };
            },
        }
    }

    /// 🔄 执行重试操作
    fn executeWithRetry(
        self: *const ErrorRecovery,
        comptime T: type,
        operation: *const fn () anyerror!T,
        context: *const ErrorContext,
    ) anyerror!T {
        var attempt: u32 = 0;
        var delay_ms = self.retry_config.initial_delay_ms;

        while (attempt < self.retry_config.max_attempts) {
            attempt += 1;

            const result = operation();
            if (result) |value| {
                if (attempt > 1) {
                    logInfo("重试成功");
                }
                return value;
            } else |err| {
                const zokio_err = ZokioError.fromStdError(err, context.operation);

                if (attempt >= self.retry_config.max_attempts) {
                    context.recordError(zokio_err, "重试次数耗尽");
                    return err;
                } else {
                    context.recordError(zokio_err, "重试中");

                    // 添加抖动
                    var actual_delay = delay_ms;
                    if (self.retry_config.jitter) {
                        var prng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
                        const jitter_factor = 0.1 + prng.random().float(f64) * 0.2; // 10%-30% 抖动
                        actual_delay = @intFromFloat(@as(f64, @floatFromInt(delay_ms)) * jitter_factor);
                    }

                    // 等待后重试
                    std.time.sleep(actual_delay * 1_000_000); // 转换为纳秒

                    // 指数退避
                    delay_ms = @min(@as(u64, @intFromFloat(@as(f64, @floatFromInt(delay_ms)) * self.retry_config.backoff_multiplier)), self.retry_config.max_delay_ms);
                }
            }
        }

        return error.MaxRetriesExceeded;
    }
};

/// 🎯 便捷的错误处理宏
/// 执行操作并处理错误
pub fn tryWithContext(
    comptime T: type,
    operation: *const fn () anyerror!T,
    context: *const ErrorContext,
) ErrorResult(T) {
    const result = operation();
    if (result) |value| {
        context.recordSuccess();
        return .{ .ok = value };
    } else |err| {
        const zokio_err = ZokioError.fromStdError(err, context.operation);
        context.recordError(zokio_err, @errorName(err));
        return .{ .err = zokio_err };
    }
}

/// 执行操作并自动重试
pub fn tryWithRetry(
    comptime T: type,
    operation: *const fn () anyerror!T,
    retry_config: RetryConfig,
    context: *const ErrorContext,
) ErrorResult(T) {
    const recovery = ErrorRecovery.init(.retry, retry_config);
    const result = recovery.executeWithRecovery(T, operation, null, context);

    if (result) |value| {
        return .{ .ok = value };
    } else |err| {
        const zokio_err = ZokioError.fromStdError(err, context.operation);
        return .{ .err = zokio_err };
    }
}

// 🧪 测试用例
test "ErrorContext 基本功能" {
    const testing = std.testing;

    var context = ErrorContext.init("测试操作", "测试组件");

    // 模拟一些操作时间
    std.time.sleep(1_000_000); // 1ms

    const elapsed = context.getElapsedTime();
    try testing.expect(elapsed >= 1_000_000); // 至少 1ms
}

test "ErrorRecovery 基本功能" {
    const testing = std.testing;

    const retry_config = RetryConfig{
        .max_attempts = 3,
        .initial_delay_ms = 1,
        .max_delay_ms = 10,
        .backoff_multiplier = 2.0,
        .jitter = false,
    };

    const recovery = ErrorRecovery.init(.retry, retry_config);
    const context = ErrorContext.init("测试重试", "测试组件");

    // 测试成功的操作
    const success_result = recovery.executeWithRecovery(
        u32,
        struct {
            fn op() anyerror!u32 {
                return 42;
            }
        }.op,
        null,
        &context,
    ) catch |err| {
        std.log.err("操作失败: {}", .{err});
        return err;
    };

    try testing.expect(success_result == 42);

    // 测试失败的操作（使用默认值策略）
    const default_recovery = ErrorRecovery.init(.use_default, retry_config);
    const default_result = default_recovery.executeWithRecovery(
        u32,
        struct {
            fn op() anyerror!u32 {
                return error.TestError;
            }
        }.op,
        100, // 默认值
        &context,
    ) catch |err| {
        std.log.err("默认值操作失败: {}", .{err});
        return err;
    };

    try testing.expect(default_result == 100);
}
