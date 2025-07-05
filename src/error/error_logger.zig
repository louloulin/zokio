//! 📝 Zokio 错误日志和诊断系统
//!
//! 提供生产级的错误日志功能：
//! - 结构化日志记录
//! - 错误堆栈跟踪
//! - 性能影响最小化
//! - 异步日志写入
//! - 错误统计和分析

const std = @import("std");
const ZokioError = @import("zokio_error.zig").ZokioError;

/// 📊 日志级别
pub const LogLevel = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    fatal = 5,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    pub fn getColor(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "\x1b[37m", // 白色
            .debug => "\x1b[36m", // 青色
            .info => "\x1b[32m", // 绿色
            .warn => "\x1b[33m", // 黄色
            .err => "\x1b[31m", // 红色
            .fatal => "\x1b[35m", // 紫色
        };
    }
};

/// 📋 日志条目
pub const LogEntry = struct {
    timestamp: i64,
    level: LogLevel,
    message: []const u8,
    source_location: std.builtin.SourceLocation,
    thread_id: u32,
    error_info: ?ZokioError = null,
    context: std.StringHashMap([]const u8),

    /// 🚀 创建日志条目
    pub fn init(
        allocator: std.mem.Allocator,
        level: LogLevel,
        message: []const u8,
        source: std.builtin.SourceLocation,
        error_info: ?ZokioError,
    ) !LogEntry {
        return LogEntry{
            .timestamp = @intCast(std.time.nanoTimestamp()),
            .level = level,
            .message = try allocator.dupe(u8, message),
            .source_location = source,
            .thread_id = @intCast(std.Thread.getCurrentId()),
            .error_info = error_info,
            .context = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// 🧹 清理日志条目
    pub fn deinit(self: *LogEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.message);

        var iterator = self.context.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.context.deinit();
    }

    /// 📝 添加上下文信息
    pub fn addContext(self: *LogEntry, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        const key_copy = try allocator.dupe(u8, key);
        const value_copy = try allocator.dupe(u8, value);
        try self.context.put(key_copy, value_copy);
    }

    /// 🎨 格式化为字符串
    pub fn format(self: *const LogEntry, allocator: std.mem.Allocator, use_color: bool) ![]u8 {
        const timestamp_ms = @divTrunc(self.timestamp, 1_000_000);
        const color = if (use_color) self.level.getColor() else "";
        const reset = if (use_color) "\x1b[0m" else "";

        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        // 基本信息
        try result.writer().print("{s}[{d}] {s} {s}:{d} (线程:{d}) - {s}{s}\n", .{ color, timestamp_ms, self.level.toString(), self.source_location.file, self.source_location.line, self.thread_id, self.message, reset });

        // 错误详细信息
        if (self.error_info) |err| {
            const detailed_msg = try err.getDetailedMessage(allocator);
            defer allocator.free(detailed_msg);
            try result.writer().print("  错误详情: {s}\n", .{detailed_msg});
        }

        // 上下文信息
        if (self.context.count() > 0) {
            try result.writer().print("  上下文:\n", .{});
            var iterator = self.context.iterator();
            while (iterator.next()) |entry| {
                try result.writer().print("    {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }

        return result.toOwnedSlice();
    }
};

/// 📊 错误统计信息
pub const ErrorStats = struct {
    total_errors: u64 = 0,
    errors_by_level: [6]u64 = [_]u64{0} ** 6,
    errors_by_type: std.StringHashMap(u64),
    last_error_time: ?i64 = null,

    pub fn init(allocator: std.mem.Allocator) ErrorStats {
        return ErrorStats{
            .errors_by_type = std.StringHashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorStats) void {
        self.errors_by_type.deinit();
    }

    pub fn recordError(self: *ErrorStats, level: LogLevel, error_type: []const u8) !void {
        self.total_errors += 1;
        self.errors_by_level[@intFromEnum(level)] += 1;
        self.last_error_time = @intCast(std.time.nanoTimestamp());

        const result = try self.errors_by_type.getOrPut(error_type);
        if (result.found_existing) {
            result.value_ptr.* += 1;
        } else {
            result.value_ptr.* = 1;
        }
    }
};

/// 🏗️ 错误日志器配置
pub const ErrorLoggerConfig = struct {
    min_level: LogLevel = .info,
    max_entries: usize = 10000,
    enable_console: bool = true,
    enable_file: bool = false,
    log_file_path: ?[]const u8 = null,
    use_color: bool = true,
    buffer_size: usize = 4096,
    flush_interval_ms: u64 = 1000,
};

/// 📝 错误日志器
pub const ErrorLogger = struct {
    config: ErrorLoggerConfig,
    entries: std.ArrayList(LogEntry),
    stats: ErrorStats,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    log_file: ?std.fs.File = null,
    buffer: std.ArrayList(u8),

    /// 🚀 初始化错误日志器
    pub fn init(allocator: std.mem.Allocator, config: ErrorLoggerConfig) !ErrorLogger {
        var logger = ErrorLogger{
            .config = config,
            .entries = std.ArrayList(LogEntry).init(allocator),
            .stats = ErrorStats.init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
            .buffer = std.ArrayList(u8).init(allocator),
        };

        // 打开日志文件
        if (config.enable_file and config.log_file_path != null) {
            logger.log_file = std.fs.cwd().createFile(config.log_file_path.?, .{
                .truncate = false,
            }) catch |err| {
                std.log.warn("无法打开日志文件 {s}: {}", .{ config.log_file_path.?, err });
                return err;
            };
        }

        return logger;
    }

    /// 🧹 清理日志器
    pub fn deinit(self: *ErrorLogger) void {
        self.flush();

        // 清理所有日志条目
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }

        self.entries.deinit();
        self.stats.deinit();
        self.buffer.deinit();

        if (self.log_file) |file| {
            file.close();
        }
    }

    /// 📝 记录日志
    pub fn log(
        self: *ErrorLogger,
        level: LogLevel,
        message: []const u8,
        error_info: ?ZokioError,
        source: std.builtin.SourceLocation,
    ) void {
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        var entry = LogEntry.init(self.allocator, level, message, source, error_info) catch {
            // 如果无法创建日志条目，至少输出到控制台
            std.log.err("无法创建日志条目: {s}", .{message});
            return;
        };

        // 记录统计信息
        const error_type = if (error_info) |err| err.getShortDescription() else "general";
        self.stats.recordError(level, error_type) catch {};

        // 输出到控制台
        if (self.config.enable_console) {
            self.outputToConsole(&entry);
        }

        // 添加到缓冲区
        self.addToBuffer(&entry);

        // 存储到数组列表（限制大小）
        if (self.entries.items.len >= self.config.max_entries) {
            // 移除最旧的条目
            var old_entry = self.entries.orderedRemove(0);
            old_entry.deinit(self.allocator);
        }
        self.entries.append(entry) catch {};
    }

    /// 🖥️ 输出到控制台
    fn outputToConsole(self: *ErrorLogger, entry: *const LogEntry) void {
        const formatted = entry.format(self.allocator, self.config.use_color) catch {
            std.debug.print("无法格式化日志条目\n", .{});
            return;
        };
        defer self.allocator.free(formatted);

        std.debug.print("{s}", .{formatted});
    }

    /// 📦 添加到缓冲区
    fn addToBuffer(self: *ErrorLogger, entry: *const LogEntry) void {
        const formatted = entry.format(self.allocator, false) catch return;
        defer self.allocator.free(formatted);

        self.buffer.appendSlice(formatted) catch {
            // 如果缓冲区满了，强制刷新
            self.flush();
            self.buffer.appendSlice(formatted) catch {};
        };
    }

    /// 💾 刷新缓冲区到文件
    pub fn flush(self: *ErrorLogger) void {
        if (self.log_file) |file| {
            if (self.buffer.items.len > 0) {
                file.writeAll(self.buffer.items) catch |err| {
                    std.log.warn("写入日志文件失败: {}", .{err});
                };
                self.buffer.clearRetainingCapacity();
            }
        }
    }

    /// 📊 获取统计信息
    pub fn getStats(self: *ErrorLogger) ErrorStats {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.stats;
    }

    /// 🔍 搜索日志条目
    pub fn searchEntries(self: *ErrorLogger, allocator: std.mem.Allocator, pattern: []const u8) ![]LogEntry {
        self.mutex.lock();
        defer self.mutex.unlock();

        var results = std.ArrayList(LogEntry).init(allocator);

        for (self.entries.items) |entry| {
            if (std.mem.indexOf(u8, entry.message, pattern) != null) {
                try results.append(entry);
            }
        }

        return results.toOwnedSlice();
    }
};

/// 🎯 便捷的日志宏
pub var global_logger: ?*ErrorLogger = null;

pub fn initGlobalLogger(allocator: std.mem.Allocator, config: ErrorLoggerConfig) !void {
    const logger = try allocator.create(ErrorLogger);
    logger.* = try ErrorLogger.init(allocator, config);
    global_logger = logger;
}

pub fn deinitGlobalLogger(allocator: std.mem.Allocator) void {
    if (global_logger) |logger| {
        logger.deinit();
        allocator.destroy(logger);
        global_logger = null;
    }
}

/// 📝 便捷的日志函数
pub fn logError(message: []const u8, error_info: ?ZokioError) void {
    if (global_logger) |logger| {
        logger.log(.err, message, error_info, @src());
    }
}

pub fn logWarn(message: []const u8) void {
    if (global_logger) |logger| {
        logger.log(.warn, message, null, @src());
    }
}

pub fn logInfo(message: []const u8) void {
    if (global_logger) |logger| {
        logger.log(.info, message, null, @src());
    }
}

pub fn logDebug(message: []const u8) void {
    if (global_logger) |logger| {
        logger.log(.debug, message, null, @src());
    }
}

// 🧪 测试用例
test "ErrorLogger 基本功能" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = ErrorLoggerConfig{
        .min_level = .debug,
        .enable_console = false, // 测试时不输出到控制台
        .max_entries = 100,
    };

    var logger = try ErrorLogger.init(allocator, config);
    defer logger.deinit();

    // 记录一些日志
    logger.log(.info, "测试信息日志", null, @src());
    logger.log(.warn, "测试警告日志", null, @src());

    const test_error = ZokioError{ .io_error = .{
        .kind = .file_not_found,
        .message = "测试文件未找到",
    } };
    logger.log(.err, "测试错误日志", test_error, @src());

    const stats = logger.getStats();
    try testing.expect(stats.total_errors == 3);
    try testing.expect(stats.errors_by_level[@intFromEnum(LogLevel.info)] == 1);
    try testing.expect(stats.errors_by_level[@intFromEnum(LogLevel.warn)] == 1);
    try testing.expect(stats.errors_by_level[@intFromEnum(LogLevel.err)] == 1);
}
