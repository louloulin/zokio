//! Zokio 简化版嵌套 await 演示
//!
//! 展示基本的await功能，避免复杂的类型问题

const std = @import("std");
const zokio = @import("zokio");

// 导入增强的async API
const async_enhanced = zokio.async_enhanced;
const simple_runtime = zokio.simple_runtime;

/// 模拟异步数据获取
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
            return .{ .ready = "模拟数据" };
        }
        
        return .pending;
    }
    
    pub fn reset(self: *@This()) void {
        self.start_time = null;
    }
};

/// 模拟异步数据处理
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
            std.debug.print("开始处理数据: {s}\n", .{self.input});
            return .pending;
        }
        
        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            std.debug.print("数据处理完成\n", .{});
            return .{ .ready = "处理后的数据" };
        }
        
        return .pending;
    }
    
    pub fn reset(self: *@This()) void {
        self.start_time = null;
    }
};

/// 手动实现的异步工作流
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
                        std.debug.print("工作流: 获取到数据 - {s}\n", .{data});
                        return .pending; // 继续下一步
                    },
                    .pending => return .pending,
                }
            },
            1 => {
                // 步骤2：处理数据
                if (self.processor == null) {
                    self.processor = DataProcessor.init(self.intermediate_result.?, 80);
                }
                
                switch (self.processor.?.poll(ctx)) {
                    .ready => |processed_data| {
                        self.step = 2;
                        std.debug.print("工作流: 处理完成 - {s}\n", .{processed_data});
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

/// 使用AsyncContext的手动await演示
fn demonstrateManualAwait(ctx: *async_enhanced.AsyncContext) ![]const u8 {
    std.debug.print("=== 开始手动await演示 ===\n", .{});
    
    // 步骤1: 获取数据
    const fetcher = DataFetcher.init("手动await数据源", 60);
    const raw_data = try ctx.await_future(fetcher);
    std.debug.print("手动await: 获取到数据 - {s}\n", .{raw_data});
    
    // 步骤2: 处理数据
    const processor = DataProcessor.init(raw_data, 40);
    const processed_data = try ctx.await_future(processor);
    std.debug.print("手动await: 处理完成 - {s}\n", .{processed_data});
    
    return processed_data;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 简化版嵌套 await 演示 ===\n", .{});

    // 创建运行时
    var runtime = simple_runtime.builder()
        .threads(2)
        .workStealing(true)
        .build(allocator);
    defer runtime.deinit();

    try runtime.start();

    std.debug.print("\n=== 演示1: 基础Future操作 ===\n", .{});
    
    // 测试基础Future
    const simple_fetcher = DataFetcher.init("基础测试", 50);
    const simple_start = std.time.milliTimestamp();
    const simple_result = try runtime.blockOn(simple_fetcher);
    const simple_duration = std.time.milliTimestamp() - simple_start;
    
    std.debug.print("基础Future结果: {s}\n", .{simple_result});
    std.debug.print("基础Future耗时: {}ms\n", .{simple_duration});

    std.debug.print("\n=== 演示2: 手动实现的异步工作流 ===\n", .{});
    
    const workflow = AsyncWorkflow.init();
    const workflow_start = std.time.milliTimestamp();
    const workflow_result = try runtime.blockOn(workflow);
    const workflow_duration = std.time.milliTimestamp() - workflow_start;
    
    std.debug.print("异步工作流结果: {s}\n", .{workflow_result});
    std.debug.print("工作流总耗时: {}ms\n", .{workflow_duration});

    std.debug.print("\n=== 演示3: 手动await使用 ===\n", .{});
    
    // 创建手动的AsyncContext
    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);
    var async_ctx = async_enhanced.AsyncContext.init(&ctx);
    
    // 使用手动await
    const manual_start = std.time.milliTimestamp();
    const manual_result = try demonstrateManualAwait(&async_ctx);
    const manual_duration = std.time.milliTimestamp() - manual_start;
    
    std.debug.print("手动await最终结果: {s}\n", .{manual_result});
    std.debug.print("手动await总耗时: {}ms\n", .{manual_duration});

    std.debug.print("\n=== 演示4: 链式await操作 ===\n", .{});
    
    // 创建链式操作
    const chain_start = std.time.milliTimestamp();
    
    const step1 = DataFetcher.init("链式步骤1", 30);
    const result1 = try async_ctx.await_future(step1);
    std.debug.print("链式步骤1完成: {s}\n", .{result1});
    
    const step2 = DataProcessor.init(result1, 40);
    const result2 = try async_ctx.await_future(step2);
    std.debug.print("链式步骤2完成: {s}\n", .{result2});
    
    const step3 = DataFetcher.init("链式步骤3", 25);
    const result3 = try async_ctx.await_future(step3);
    std.debug.print("链式步骤3完成: {s}\n", .{result3});
    
    const chain_duration = std.time.milliTimestamp() - chain_start;
    
    std.debug.print("链式操作完成，总耗时: {}ms\n", .{chain_duration});

    std.debug.print("\n=== 演示5: 并行vs顺序对比 ===\n", .{});
    
    // 顺序执行
    const seq_start = std.time.milliTimestamp();
    
    const seq_task1 = DataFetcher.init("顺序任务1", 40);
    const seq_result1 = try runtime.blockOn(seq_task1);
    
    const seq_task2 = DataFetcher.init("顺序任务2", 50);
    const seq_result2 = try runtime.blockOn(seq_task2);
    
    const seq_task3 = DataFetcher.init("顺序任务3", 30);
    const seq_result3 = try runtime.blockOn(seq_task3);
    
    const seq_duration = std.time.milliTimestamp() - seq_start;
    
    std.debug.print("顺序执行结果: {s}, {s}, {s}\n", .{ seq_result1, seq_result2, seq_result3 });
    std.debug.print("顺序执行总耗时: {}ms\n", .{seq_duration});

    std.debug.print("\n=== 演示6: 超时控制 ===\n", .{});
    
    // 创建一个快速任务，不会超时
    const fast_task = DataFetcher.init("快速任务", 30);
    const timeout_future = zokio.timeout(fast_task, 100); // 100ms超时
    
    const timeout_start = std.time.milliTimestamp();
    const timeout_result = try runtime.blockOn(timeout_future);
    const timeout_duration = std.time.milliTimestamp() - timeout_start;
    
    std.debug.print("超时任务结果: {s}\n", .{timeout_result});
    std.debug.print("超时执行耗时: {}ms\n", .{timeout_duration});

    std.debug.print("\n=== 演示完成 ===\n", .{});
    std.debug.print("所有简化版嵌套await演示成功完成！\n", .{});
    std.debug.print("这展示了Zokio的核心异步功能和await模式\n", .{});
}
