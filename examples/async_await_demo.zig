//! Zokio async_fn和await演示
//!
//! 本示例展示如何使用Zokio的async_fn和await功能
//! 创建复杂的异步操作链

const std = @import("std");
const zokio = @import("zokio");

/// 模拟异步数据获取任务
const DataFetcher = struct {
    url: []const u8,
    delay_ms: u64,
    start_time: ?i64 = null,

    pub const Output = []const u8;

    pub fn init(url: []const u8, delay: u64) @This() {
        return @This(){
            .url = url,
            .delay_ms = delay,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]const u8) {
        _ = ctx;

        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            std.debug.print("开始获取数据: {s}\n", .{self.url});
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            std.debug.print("数据获取完成: {s}\n", .{self.url});
            return .{ .ready = "模拟数据响应" };
        }

        return .pending;
    }

    pub fn reset(self: *@This()) void {
        self.start_time = null;
    }
};

/// 模拟异步数据处理任务
const DataProcessor = struct {
    input_data: []const u8,
    processing_time: u64,
    start_time: ?i64 = null,

    pub const Output = []const u8;

    pub fn init(data: []const u8, time: u64) @This() {
        return @This(){
            .input_data = data,
            .processing_time = time,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]const u8) {
        _ = ctx;

        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            std.debug.print("开始处理数据: {s}\n", .{self.input_data});
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.processing_time) {
            std.debug.print("数据处理完成\n", .{});
            return .{ .ready = "处理后的数据" };
        }

        return .pending;
    }

    pub fn reset(self: *@This()) void {
        self.start_time = null;
    }
};

/// 复杂的异步工作流
const AsyncWorkflow = struct {
    step: u32 = 0,
    fetcher: ?DataFetcher = null,
    processor: ?DataProcessor = null,
    intermediate_result: ?[]const u8 = null,

    pub const Output = []const u8;

    pub fn init() @This() {
        return @This(){};
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]const u8) {
        switch (self.step) {
            0 => {
                // 步骤1：获取数据
                if (self.fetcher == null) {
                    self.fetcher = DataFetcher.init("https://api.example.com/data", 100);
                }

                switch (self.fetcher.?.poll(ctx)) {
                    .ready => |data| {
                        self.intermediate_result = data;
                        self.step = 1;
                        return .pending; // 继续下一步
                    },
                    .pending => return .pending,
                }
            },
            1 => {
                // 步骤2：处理数据
                if (self.processor == null) {
                    self.processor = DataProcessor.init(self.intermediate_result.?, 150);
                }

                switch (self.processor.?.poll(ctx)) {
                    .ready => |processed_data| {
                        self.step = 2;
                        return .{ .ready = processed_data };
                    },
                    .pending => return .pending,
                }
            },
            else => {
                // 工作流完成
                return .{ .ready = "工作流完成" };
            },
        }
    }

    pub fn reset(self: *@This()) void {
        self.step = 0;
        self.intermediate_result = null;
        if (self.fetcher) |*f| f.reset();
        if (self.processor) |*p| p.reset();
        self.fetcher = null;
        self.processor = null;
    }
};

/// 使用async_fn包装的异步函数
const AsyncFunctions = struct {
    /// 异步计算函数
    fn asyncCompute() u64 {
        std.debug.print("执行异步计算...\n", .{});
        // 模拟计算
        var result: u64 = 0;
        for (0..1000) |i| {
            result += i;
        }
        std.debug.print("计算完成，结果: {}\n", .{result});
        return result;
    }

    /// 异步字符串处理函数
    fn asyncStringProcess() []const u8 {
        std.debug.print("执行异步字符串处理...\n", .{});
        return "处理后的字符串";
    }

    /// 可能失败的异步函数
    fn asyncMightFail() ![]const u8 {
        std.debug.print("执行可能失败的异步操作...\n", .{});
        // 模拟随机失败
        const timestamp = std.time.milliTimestamp();
        if (timestamp % 3 == 0) {
            return error.RandomFailure;
        }
        return "成功结果";
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio async_fn和await演示 ===\n", .{});

    // 配置运行时
    const config = zokio.RuntimeConfig{
        .worker_threads = 2,
        .enable_work_stealing = true,
        .enable_metrics = true,
    };

    // 创建运行时
    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    std.debug.print("\n=== 演示1: 基本async_fn使用 ===\n", .{});

    // 创建async_fn包装的函数
    const AsyncCompute = zokio.async_fn(AsyncFunctions.asyncCompute);
    const compute_task = AsyncCompute.init(AsyncFunctions.asyncCompute);

    const compute_result = try runtime.blockOn(compute_task);
    std.debug.print("async_fn计算结果: {}\n", .{compute_result});

    std.debug.print("\n=== 演示2: 字符串处理async_fn ===\n", .{});

    const AsyncStringProcess = zokio.async_fn(AsyncFunctions.asyncStringProcess);
    const string_task = AsyncStringProcess.init(AsyncFunctions.asyncStringProcess);

    const string_result = try runtime.blockOn(string_task);
    std.debug.print("字符串处理结果: {s}\n", .{string_result});

    std.debug.print("\n=== 演示3: 复杂异步工作流 ===\n", .{});

    const workflow = AsyncWorkflow.init();
    const workflow_result = try runtime.blockOn(workflow);
    std.debug.print("工作流结果: {s}\n", .{workflow_result});

    std.debug.print("\n=== 演示4: Future组合子 ===\n", .{});

    // 使用ready和delay组合
    const ready_future = zokio.ready(u32, 42);
    const delay_future = zokio.delay(50); // 50ms延迟

    // 创建链式Future
    const chain = zokio.future.ChainFuture(@TypeOf(ready_future), @TypeOf(delay_future))
        .init(ready_future, delay_future);

    const chain_start = std.time.milliTimestamp();
    try runtime.blockOn(chain);
    const chain_duration = std.time.milliTimestamp() - chain_start;
    std.debug.print("链式Future完成，耗时: {}ms\n", .{chain_duration});

    std.debug.print("\n=== 演示5: 超时处理 ===\n", .{});

    // 创建一个短时间运行的任务
    const short_task = zokio.delay(50); // 50ms任务
    const timeout_task = zokio.timeout(short_task, 100); // 100ms超时

    const timeout_start = std.time.milliTimestamp();
    const timeout_result = try runtime.blockOn(timeout_task);
    const timeout_duration = std.time.milliTimestamp() - timeout_start;

    std.debug.print("任务在超时前完成，耗时: {}ms\n", .{timeout_duration});
    _ = timeout_result;

    std.debug.print("\n=== 演示完成 ===\n", .{});
}
