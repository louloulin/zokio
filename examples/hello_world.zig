//! Zokio Hello World 示例
//!
//! 展示Zokio异步运行时的基本使用方法

const std = @import("std");
const zokio = @import("zokio");

/// 简单的异步任务
const HelloTask = struct {
    message: []const u8,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        std.debug.print("异步任务: {s}\n", .{self.message});
        return .{ .ready = {} };
    }
};

/// 异步延迟任务
const DelayTask = struct {
    delay_ms: u64,
    start_time: ?i64 = null,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;

        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            std.debug.print("开始延迟 {}ms...\n", .{self.delay_ms});
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            std.debug.print("延迟完成!\n", .{});
            return .{ .ready = {} };
        }

        return .pending;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio Hello World 示例 ===\n", .{});

    // 创建运行时配置
    const config = zokio.RuntimeConfig{
        .worker_threads = 2,
        .enable_work_stealing = true,
        .enable_metrics = true,
        .enable_tracing = false,
    };

    // 创建运行时实例
    const RuntimeType = zokio.experimental.comptime_runtime.generateRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    std.debug.print("运行时创建成功\n", .{});
    std.debug.print("平台: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.platform});
    std.debug.print("架构: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.architecture});
    std.debug.print("工作线程: {}\n", .{RuntimeType.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("I/O后端: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.io_backend});

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    std.debug.print("\n=== 执行异步任务 ===\n", .{});

    // 创建简单任务
    const hello_task = HelloTask{
        .message = "Hello, Zokio!",
    };

    // 执行任务
    try runtime.blockOn(hello_task);

    // 创建延迟任务
    const delay_task = DelayTask{
        .delay_ms = 100,
    };

    std.debug.print("\n=== 执行延迟任务 ===\n", .{});
    try runtime.blockOn(delay_task);

    std.debug.print("\n=== 示例完成 ===\n", .{});
}
