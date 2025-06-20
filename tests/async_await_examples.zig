//! 🚀 async_fn和await_fn运行时例子
//! 展示Zokio的真正异步函数和等待机制

const std = @import("std");
const zokio = @import("zokio");

// 🔥 异步HTTP请求模拟
const AsyncHttpRequest = struct {
    url: []const u8,
    delay_ms: u64,

    const Self = @This();
    pub const Output = []const u8;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        
        // 模拟网络延迟
        std.time.sleep(self.delay_ms * std.time.ns_per_ms);
        
        // 模拟HTTP响应
        if (std.mem.eql(u8, self.url, "https://api.example.com/users")) {
            return zokio.Poll(Self.Output){ .ready = "{'users': [{'id': 1, 'name': 'Alice'}]}" };
        } else if (std.mem.eql(u8, self.url, "https://api.example.com/posts")) {
            return zokio.Poll(Self.Output){ .ready = "{'posts': [{'id': 1, 'title': 'Hello World'}]}" };
        } else {
            return zokio.Poll(Self.Output){ .ready = "{'error': 'Not Found'}" };
        }
    }
};

// 🔥 异步数据库查询模拟
const AsyncDbQuery = struct {
    query: []const u8,
    delay_ms: u64,

    const Self = @This();
    pub const Output = u32;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        
        // 模拟数据库查询延迟
        std.time.sleep(self.delay_ms * std.time.ns_per_ms);
        
        // 模拟查询结果
        if (std.mem.indexOf(u8, self.query, "SELECT COUNT") != null) {
            return zokio.Poll(Self.Output){ .ready = 42 };
        } else if (std.mem.indexOf(u8, self.query, "SELECT") != null) {
            return zokio.Poll(Self.Output){ .ready = 123 };
        } else {
            return zokio.Poll(Self.Output){ .ready = 1 };
        }
    }
};

// 🔥 异步文件处理
const AsyncFileProcessor = struct {
    filename: []const u8,
    operation: Operation,

    const Operation = enum { read, write, delete };
    const Self = @This();
    pub const Output = bool;

    pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
        _ = ctx;
        
        // 模拟文件I/O延迟
        std.time.sleep(5 * std.time.ns_per_ms);
        
        switch (self.operation) {
            .read => {
                std.debug.print("    📖 读取文件: {s}\n", .{self.filename});
                return zokio.Poll(Self.Output){ .ready = true };
            },
            .write => {
                std.debug.print("    ✏️ 写入文件: {s}\n", .{self.filename});
                return zokio.Poll(Self.Output){ .ready = true };
            },
            .delete => {
                std.debug.print("    🗑️ 删除文件: {s}\n", .{self.filename});
                return zokio.Poll(Self.Output){ .ready = true };
            },
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 async_fn和await_fn运行时例子 ===\n", .{});

    // 示例1: 基础async_fn使用
    try basicAsyncFnExample(allocator);
    
    // 示例2: 嵌套await_fn调用
    try nestedAwaitExample(allocator);
    
    // 示例3: 并发async_fn执行
    try concurrentAsyncExample(allocator);
    
    // 示例4: 复杂的异步工作流
    try complexAsyncWorkflow(allocator);

    std.debug.print("\n🎉 === async_fn和await_fn例子完成 ===\n", .{});
}

/// 🔥 async_fn宏 - 创建异步函数
fn async_fn(comptime ReturnType: type, comptime func: anytype) type {
    return struct {
        const Self = @This();
        pub const Output = ReturnType;
        
        context: @TypeOf(func),
        
        pub fn init(ctx: @TypeOf(func)) Self {
            return Self{ .context = ctx };
        }
        
        pub fn poll(self: *Self, ctx: *anyopaque) zokio.Poll(Self.Output) {
            return self.context.poll(ctx);
        }
    };
}

/// 🔥 await_fn函数 - 等待异步操作完成
fn await_fn(runtime: anytype, future: anytype) !@TypeOf(future).Output {
    var handle = try runtime.spawn(future);
    defer handle.deinit();
    return try handle.join();
}

/// 示例1: 基础async_fn使用
fn basicAsyncFnExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 示例1: 基础async_fn使用...\n", .{});
    
    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();
    
    // 🔥 创建异步HTTP请求
    const http_request = AsyncHttpRequest{
        .url = "https://api.example.com/users",
        .delay_ms = 10,
    };
    
    std.debug.print("  🌐 发起异步HTTP请求...\n", .{});
    
    // 🚀 使用await_fn等待结果
    const response = try await_fn(&runtime, http_request);
    
    std.debug.print("  ✅ HTTP响应: {s}\n", .{response});
    std.debug.print("  🎉 基础async_fn示例完成\n", .{});
}

/// 示例2: 嵌套await_fn调用
fn nestedAwaitExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 示例2: 嵌套await_fn调用...\n", .{});
    
    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();
    
    std.debug.print("  🔄 执行嵌套异步操作...\n", .{});
    
    // 🔥 第一步：查询用户数量
    const count_query = AsyncDbQuery{
        .query = "SELECT COUNT(*) FROM users",
        .delay_ms = 8,
    };
    
    std.debug.print("  📊 查询用户数量...\n", .{});
    const user_count = try await_fn(&runtime, count_query);
    std.debug.print("  ✅ 用户数量: {}\n", .{user_count});
    
    // 🔥 第二步：基于结果获取用户数据
    if (user_count > 0) {
        const users_request = AsyncHttpRequest{
            .url = "https://api.example.com/users",
            .delay_ms = 12,
        };
        
        std.debug.print("  👥 获取用户数据...\n", .{});
        const users_data = try await_fn(&runtime, users_request);
        std.debug.print("  ✅ 用户数据: {s}\n", .{users_data});
    }
    
    std.debug.print("  🎉 嵌套await_fn示例完成\n", .{});
}

/// 示例3: 并发async_fn执行
fn concurrentAsyncExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 示例3: 并发async_fn执行...\n", .{});
    
    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();
    
    const start_time = std.time.nanoTimestamp();
    
    // 🔥 创建多个并发任务
    const http_task = AsyncHttpRequest{
        .url = "https://api.example.com/posts",
        .delay_ms = 15,
    };
    
    const db_task = AsyncDbQuery{
        .query = "SELECT * FROM posts",
        .delay_ms = 12,
    };
    
    const file_task = AsyncFileProcessor{
        .filename = "data.json",
        .operation = .read,
    };
    
    std.debug.print("  🚀 启动并发任务...\n", .{});
    
    // 🚀 并发执行所有任务
    var http_handle = try runtime.spawn(http_task);
    var db_handle = try runtime.spawn(db_task);
    var file_handle = try runtime.spawn(file_task);
    
    // 🔥 等待所有任务完成
    const http_result = try http_handle.join();
    const db_result = try db_handle.join();
    const file_result = try file_handle.join();
    
    // 清理
    http_handle.deinit();
    db_handle.deinit();
    file_handle.deinit();
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / std.time.ns_per_ms;
    
    std.debug.print("  📊 并发执行结果:\n", .{});
    std.debug.print("    HTTP响应: {s}\n", .{http_result});
    std.debug.print("    数据库结果: {}\n", .{db_result});
    std.debug.print("    文件操作: {}\n", .{file_result});
    std.debug.print("    总耗时: {d:.2} ms\n", .{duration_ms});
    std.debug.print("  🎉 并发async_fn示例完成\n", .{});
}

/// 示例4: 复杂的异步工作流
fn complexAsyncWorkflow(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧪 示例4: 复杂的异步工作流...\n", .{});
    
    var runtime = try zokio.build.memoryOptimized(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();
    
    std.debug.print("  🔄 执行复杂异步工作流...\n", .{});
    
    // 🔥 步骤1: 并发获取初始数据
    std.debug.print("  📋 步骤1: 获取初始数据...\n", .{});
    
    const config_request = AsyncHttpRequest{
        .url = "https://api.example.com/config",
        .delay_ms = 8,
    };
    
    const user_count_query = AsyncDbQuery{
        .query = "SELECT COUNT(*) FROM users",
        .delay_ms = 6,
    };
    
    var config_handle = try runtime.spawn(config_request);
    var count_handle = try runtime.spawn(user_count_query);
    
    const config_data = try config_handle.join();
    const total_users = try count_handle.join();
    
    config_handle.deinit();
    count_handle.deinit();
    
    std.debug.print("    ✅ 配置数据: {s}\n", .{config_data});
    std.debug.print("    ✅ 用户总数: {}\n", .{total_users});
    
    // 🔥 步骤2: 基于初始数据执行条件操作
    std.debug.print("  📋 步骤2: 条件操作...\n", .{});
    
    if (total_users > 10) {
        // 用户数量多，执行批量操作
        const batch_tasks = [_]AsyncFileProcessor{
            .{ .filename = "users_batch_1.json", .operation = .write },
            .{ .filename = "users_batch_2.json", .operation = .write },
            .{ .filename = "users_batch_3.json", .operation = .write },
        };
        
        var batch_handles: [3]zokio.JoinHandle(bool) = undefined;
        
        for (&batch_handles, batch_tasks) |*handle, task| {
            handle.* = try runtime.spawn(task);
        }
        
        for (&batch_handles) |*handle| {
            const result = try handle.join();
            std.debug.print("    ✅ 批量操作完成: {}\n", .{result});
            handle.deinit();
        }
    } else {
        // 用户数量少，执行单个操作
        const single_task = AsyncFileProcessor{
            .filename = "users_single.json",
            .operation = .write,
        };
        
        const result = try await_fn(&runtime, single_task);
        std.debug.print("    ✅ 单个操作完成: {}\n", .{result});
    }
    
    // 🔥 步骤3: 清理操作
    std.debug.print("  📋 步骤3: 清理操作...\n", .{});
    
    const cleanup_task = AsyncFileProcessor{
        .filename = "temp_data.tmp",
        .operation = .delete,
    };
    
    const cleanup_result = try await_fn(&runtime, cleanup_task);
    std.debug.print("    ✅ 清理完成: {}\n", .{cleanup_result});
    
    std.debug.print("  🎉 复杂异步工作流完成\n", .{});
}
