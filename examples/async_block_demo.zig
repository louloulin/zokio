//! async_block演示程序
//!
//! 展示Zokio中async_block的使用方法，严格按照plan.md中的设计实现

const std = @import("std");
const zokio = @import("zokio");

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

    std.debug.print("=== Zokio async_block演示 ===\n\n", .{});

    // 创建运行时
    var runtime = try zokio.builder().build(allocator);
    defer runtime.deinit();

    // 启动运行时
    try runtime.start();

    // 运行async_block演示
    try asyncBlockDemonstration();

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

fn asyncBlockDemonstration() !void {
    std.debug.print("1. 基础async_block演示\n", .{});

    // 创建一个简单的async_block
    const SimpleBlock = zokio.future.async_block(struct {
        fn execute() u32 {
            return 42;
        }
    }.execute);

    var simple_block = SimpleBlock.init(struct {
        fn execute() u32 {
            return 42;
        }
    }.execute);

    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);

    switch (simple_block.poll(&ctx)) {
        .ready => |value| std.debug.print("  ✓ 简单async_block完成，结果: {}\n", .{value}),
        .pending => std.debug.print("  ⏳ 简单async_block仍在等待\n", .{}),
    }

    std.debug.print("\n2. 带错误处理的async_block演示\n", .{});

    // 创建一个可能返回错误的async_block
    const ErrorBlock = zokio.future.async_block(struct {
        fn execute() !u32 {
            // 模拟可能的错误
            if (@rem(std.time.milliTimestamp(), 2) == 0) {
                return 100;
            } else {
                return error.SimulatedError;
            }
        }
    }.execute);

    var error_block = ErrorBlock.init(struct {
        fn execute() !u32 {
            // 模拟可能的错误
            if (@rem(std.time.milliTimestamp(), 2) == 0) {
                return 100;
            } else {
                return error.SimulatedError;
            }
        }
    }.execute);

    switch (error_block.poll(&ctx)) {
        .ready => |value| std.debug.print("  ✓ 错误处理async_block完成，结果: {!}\n", .{value}),
        .pending => std.debug.print("  ⏳ 错误处理async_block仍在等待\n", .{}),
    }

    std.debug.print("\n3. 状态管理演示\n", .{});

    // 测试状态管理功能
    std.debug.print("  初始状态:\n", .{});
    std.debug.print("    已完成: {}\n", .{simple_block.isCompleted()});
    std.debug.print("    已失败: {}\n", .{simple_block.isFailed()});

    // 重置状态
    simple_block.reset();
    std.debug.print("  重置后状态:\n", .{});
    std.debug.print("    已完成: {}\n", .{simple_block.isCompleted()});
    std.debug.print("    已失败: {}\n", .{simple_block.isFailed()});

    std.debug.print("\n✓ async_block演示完成\n", .{});
}
