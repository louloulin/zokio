//! Zokio 纯粹的 async/await 演示
//!
//! 展示真正简洁的async/await语法，就像Rust一样

const std = @import("std");
const zokio = @import("zokio");

// 导入核心async API
const async_block_api = @import("../src/future/async_block.zig");
const async_block = async_block_api.async_block;
const await_fn = async_block_api.await_macro;

/// 异步数据获取
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
            std.debug.print("开始获取: {s}\n", .{self.url});
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            std.debug.print("获取完成: {s}\n", .{self.url});
            return .{ .ready = "数据" };
        }

        return .pending;
    }
};

/// 异步数据处理
const DataProcessor = struct {
    input: []const u8,
    delay_ms: u64,
    start_time: ?i64 = null,

    pub const Output = []const u8;

    pub fn init(input: []const u8, delay: u64) @This() {
        return @This(){
            .input = input,
            .delay_ms = delay,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]const u8) {
        _ = ctx;

        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            std.debug.print("开始处理: {s}\n", .{self.input});
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            std.debug.print("处理完成: {s}\n", .{self.input});
            return .{ .ready = "处理后的数据" };
        }

        return .pending;
    }
};

/// 便捷函数
fn fetch_data() DataFetcher {
    return DataFetcher.init("https://api.example.com", 50);
}

fn process_data(input: []const u8) DataProcessor {
    return DataProcessor.init(input, 30);
}

fn save_data(data: []const u8) DataFetcher {
    _ = data;
    return DataFetcher.init("保存到数据库", 20);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 纯粹的 async/await 演示 ===\n", .{});

    // 创建运行时
    var runtime = zokio.simple_runtime.builder()
        .threads(1)
        .build(allocator);
    defer runtime.deinit();

    try runtime.start();

    std.debug.print("\n=== 演示1: 基础async/await语法 ===\n", .{});

    // 这就是您想要的语法！
    const simple_task = async_block(struct {
        fn run() []const u8 {
            const result1 = await_fn(fetch_data());
            const result2 = await_fn(process_data(result1));
            return result2;
        }
    }.run);

    const simple_start = std.time.milliTimestamp();
    const simple_result = try runtime.blockOn(simple_task);
    const simple_duration = std.time.milliTimestamp() - simple_start;

    std.debug.print("简单async/await结果: {s}\n", .{simple_result});
    std.debug.print("执行耗时: {}ms\n", .{simple_duration});

    std.debug.print("\n=== 演示2: 复杂的async工作流 ===\n", .{});

    const complex_task = async_block(struct {
        fn run() []const u8 {
            // 步骤1: 获取数据
            const raw_data = await_fn(fetch_data());
            std.debug.print("工作流: 获取到 {s}\n", .{raw_data});

            // 步骤2: 处理数据
            const processed = await_fn(process_data(raw_data));
            std.debug.print("工作流: 处理得到 {s}\n", .{processed});

            // 步骤3: 保存数据
            const saved = await_fn(save_data(processed));
            std.debug.print("工作流: 保存完成 {s}\n", .{saved});

            return processed;
        }
    }.run);

    const complex_start = std.time.milliTimestamp();
    const complex_result = try runtime.blockOn(complex_task);
    const complex_duration = std.time.milliTimestamp() - complex_start;

    std.debug.print("复杂工作流结果: {s}\n", .{complex_result});
    std.debug.print("执行耗时: {}ms\n", .{complex_duration});

    std.debug.print("\n=== 演示3: 多步骤async工作流 ===\n", .{});

    const multi_step_task = async_block(struct {
        fn run() []const u8 {
            // 第一步：获取数据
            const data = await_fn(fetch_data());

            // 第二步：处理数据
            const processed = await_fn(process_data(data));

            // 第三步：保存数据
            const saved = await_fn(save_data(processed));

            return saved;
        }
    }.run);

    const multi_start = std.time.milliTimestamp();
    const multi_result = try runtime.blockOn(multi_step_task);
    const multi_duration = std.time.milliTimestamp() - multi_start;

    std.debug.print("多步骤工作流结果: {s}\n", .{multi_result});
    std.debug.print("执行耗时: {}ms\n", .{multi_duration});

    std.debug.print("\n=== 演示4: 条件分支的async ===\n", .{});

    const conditional_task = async_block(struct {
        fn run() []const u8 {
            const data = await_fn(fetch_data());

            // 根据数据内容选择不同的处理方式
            if (data.len > 0) {
                return await_fn(process_data(data));
            } else {
                return await_fn(fetch_data()); // 重新获取
            }
        }
    }.run);

    const conditional_start = std.time.milliTimestamp();
    const conditional_result = try runtime.blockOn(conditional_task);
    const conditional_duration = std.time.milliTimestamp() - conditional_start;

    std.debug.print("条件分支结果: {s}\n", .{conditional_result});
    std.debug.print("执行耗时: {}ms\n", .{conditional_duration});

    std.debug.print("\n=== 演示5: 循环中的await ===\n", .{});

    const loop_task = async_block(struct {
        fn run() []const u8 {
            var final_result: []const u8 = "初始";

            // 循环执行多次异步操作
            for (0..3) |i| {
                std.debug.print("循环第{}次\n", .{i + 1});
                final_result = await_fn(process_data(final_result));
            }

            return final_result;
        }
    }.run);

    const loop_start = std.time.milliTimestamp();
    const loop_result = try runtime.blockOn(loop_task);
    const loop_duration = std.time.milliTimestamp() - loop_start;

    std.debug.print("循环async结果: {s}\n", .{loop_result});
    std.debug.print("执行耗时: {}ms\n", .{loop_duration});

    std.debug.print("\n=== 演示完成 ===\n", .{});
    std.debug.print("这就是您想要的纯粹async/await语法！\n", .{});
    std.debug.print("简洁、直观、强大！\n", .{});
}
