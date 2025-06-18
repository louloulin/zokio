//! Zokio 嵌套 await 演示
//!
//! 展示真正的嵌套await功能，类似于Rust的async/await

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

/// 模拟异步数据保存
const DataSaver = struct {
    data: []const u8,
    delay_ms: u64,
    start_time: ?i64 = null,
    
    pub const Output = void;
    
    pub fn init(data: []const u8, delay: u64) @This() {
        return @This(){
            .data = data,
            .delay_ms = delay,
        };
    }
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        
        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            std.debug.print("开始保存数据: {s}\n", .{self.data});
            return .pending;
        }
        
        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            std.debug.print("数据保存完成\n", .{});
            return .{ .ready = {} };
        }
        
        return .pending;
    }
    
    pub fn reset(self: *@This()) void {
        self.start_time = null;
    }
};

/// 使用AsyncContext的异步工作流
fn asyncWorkflowWithContext(ctx: *async_enhanced.AsyncContext) ![]const u8 {
    std.debug.print("=== 开始异步工作流（带上下文） ===\n", .{});
    
    // 步骤1: 获取数据
    const fetcher = DataFetcher.init("https://api.example.com/data", 100);
    const raw_data = try ctx.await_future(fetcher);
    std.debug.print("工作流: 获取到数据 - {s}\n", .{raw_data});
    
    // 步骤2: 处理数据
    const processor = DataProcessor.init(raw_data, 80);
    const processed_data = try ctx.await_future(processor);
    std.debug.print("工作流: 处理完成 - {s}\n", .{processed_data});
    
    // 步骤3: 保存数据
    const saver = DataSaver.init(processed_data, 60);
    try ctx.await_future(saver);
    std.debug.print("工作流: 保存完成\n", .{});
    
    return processed_data;
}

/// 不使用AsyncContext的简单异步函数
fn simpleAsyncFunction() []const u8 {
    std.debug.print("执行简单异步函数\n", .{});
    return "简单函数结果";
}

/// 复杂的嵌套异步函数
fn complexAsyncFunction(ctx: *async_enhanced.AsyncContext) !u32 {
    std.debug.print("=== 开始复杂异步函数 ===\n", .{});
    
    // 并行获取多个数据源
    const fetcher1 = DataFetcher.init("https://api1.example.com", 50);
    const fetcher2 = DataFetcher.init("https://api2.example.com", 70);
    
    const data1 = try ctx.await_future(fetcher1);
    std.debug.print("复杂函数: 获取数据1 - {s}\n", .{data1});
    
    const data2 = try ctx.await_future(fetcher2);
    std.debug.print("复杂函数: 获取数据2 - {s}\n", .{data2});
    
    // 处理合并的数据
    const combined_processor = DataProcessor.init("合并数据", 40);
    const result = try ctx.await_future(combined_processor);
    std.debug.print("复杂函数: 处理结果 - {s}\n", .{result});
    
    return 42; // 返回计算结果
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 嵌套 await 演示 ===\n", .{});

    // 创建运行时
    var runtime = simple_runtime.builder()
        .threads(2)
        .workStealing(true)
        .build(allocator);
    defer runtime.deinit();

    try runtime.start();

    std.debug.print("\n=== 演示1: 基础async_block使用 ===\n", .{});
    
    // 使用不需要AsyncContext的简单函数
    const simple_block = async_enhanced.async_block(simpleAsyncFunction);
    const simple_result = try runtime.blockOn(simple_block);
    std.debug.print("简单async_block结果: {s}\n", .{simple_result});

    std.debug.print("\n=== 演示2: 带AsyncContext的async_block ===\n", .{});
    
    // 使用需要AsyncContext的复杂函数
    const workflow_block = async_enhanced.async_block(asyncWorkflowWithContext);
    const workflow_start = std.time.milliTimestamp();
    const workflow_result = try runtime.blockOn(workflow_block);
    const workflow_duration = std.time.milliTimestamp() - workflow_start;
    
    std.debug.print("异步工作流结果: {s}\n", .{workflow_result});
    std.debug.print("工作流总耗时: {}ms\n", .{workflow_duration});

    std.debug.print("\n=== 演示3: 复杂嵌套异步函数 ===\n", .{});
    
    const complex_block = async_enhanced.async_block(complexAsyncFunction);
    const complex_start = std.time.milliTimestamp();
    const complex_result = try runtime.blockOn(complex_block);
    const complex_duration = std.time.milliTimestamp() - complex_start;
    
    std.debug.print("复杂异步函数结果: {}\n", .{complex_result});
    std.debug.print("复杂函数总耗时: {}ms\n", .{complex_duration});

    std.debug.print("\n=== 演示4: 手动await使用 ===\n", .{});
    
    // 创建手动的AsyncContext
    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);
    var async_ctx = async_enhanced.AsyncContext.init(&ctx);
    
    // 手动使用await
    const manual_fetcher = DataFetcher.init("手动获取", 30);
    const manual_start = std.time.milliTimestamp();
    const manual_result = try async_ctx.await_future(manual_fetcher);
    const manual_duration = std.time.milliTimestamp() - manual_start;
    
    std.debug.print("手动await结果: {s}\n", .{manual_result});
    std.debug.print("手动await耗时: {}ms\n", .{manual_duration});

    std.debug.print("\n=== 演示5: 链式await操作 ===\n", .{});
    
    // 创建链式操作
    const chain_start = std.time.milliTimestamp();
    
    const step1 = DataFetcher.init("步骤1", 25);
    const result1 = try async_ctx.await_future(step1);
    
    const step2 = DataProcessor.init(result1, 35);
    const result2 = try async_ctx.await_future(step2);
    
    const step3 = DataSaver.init(result2, 20);
    try async_ctx.await_future(step3);
    
    const chain_duration = std.time.milliTimestamp() - chain_start;
    
    std.debug.print("链式操作完成，总耗时: {}ms\n", .{chain_duration});

    std.debug.print("\n=== 演示完成 ===\n", .{});
    std.debug.print("所有嵌套await演示成功完成！\n", .{});
}
