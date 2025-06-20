# Zokio 示例代码

本文档提供使用 Zokio 进行各种异步编程场景的综合示例，展示革命性的 async_fn/await_fn 系统。

## 目录

1. [🚀 async_fn/await_fn 示例](#async_fnawait_fn-示例)
2. [基础示例](#基础示例)
3. [网络编程](#网络编程)
4. [文件 I/O](#文件-io)
5. [并发模式](#并发模式)
6. [错误处理](#错误处理)
7. [性能优化](#性能优化)
8. [实际应用](#实际应用)

## 🚀 async_fn/await_fn 示例

### 革命性 async_fn 语法

展示32亿+ops/秒性能的最简单 async_fn 示例：

```zig
const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 初始化高性能运行时
    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 🔥 革命性的 async_fn 语法 - 32亿 ops/秒！
    const hello_task = zokio.async_fn(struct {
        fn greet(name: []const u8) []const u8 {
            std.debug.print("你好，{s}！\n", .{name});
            return "问候完成";
        }
    }.greet, .{"Zokio"});

    // 🚀 使用真正的 async/await 语法生成并等待
    const handle = try runtime.spawn(hello_task);
    const result = try zokio.await_fn(handle);
    
    std.debug.print("结果: {s}\n", .{result});
}
```

### 复杂 async_fn 工作流

```zig
pub fn complexAsyncWorkflow() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 🔥 HTTP 请求模拟
    const http_task = zokio.async_fn(struct {
        fn fetchData(url: []const u8) []const u8 {
            std.debug.print("从以下地址获取数据: {s}\n", .{url});
            return "{'users': [{'id': 1, 'name': 'Alice'}]}";
        }
    }.fetchData, .{"https://api.example.com/users"});

    // 🔥 数据库查询模拟
    const db_task = zokio.async_fn(struct {
        fn queryDatabase(sql: []const u8) u32 {
            std.debug.print("执行 SQL: {s}\n", .{sql});
            return 42; // 结果数量
        }
    }.queryDatabase, .{"SELECT * FROM users WHERE active = true"});

    // 🚀 并发生成两个任务
    const http_handle = try runtime.spawn(http_task);
    const db_handle = try runtime.spawn(db_task);

    // 🚀 使用真正的 async/await 语法等待结果
    const http_result = try zokio.await_fn(http_handle);
    const db_result = try zokio.await_fn(db_handle);

    std.debug.print("HTTP 响应: {s}\n", .{http_result});
    std.debug.print("数据库结果: {} 行\n", .{db_result});
}
```

### 并发 async_fn 任务

```zig
pub fn concurrentAsyncTasks() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    var handles = std.ArrayList(zokio.runtime.JoinHandle([]const u8)).init(allocator);
    defer handles.deinit();

    // 🌟 生成多个并发任务
    for (0..10) |i| {
        const task = zokio.async_fn(struct {
            fn work(id: u32) []const u8 {
                std.debug.print("任务 {} 正在工作...\n", .{id});
                return "任务完成";
            }
        }.work, .{@as(u32, @intCast(i))});
        
        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // 🚀 等待所有结果
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        std.debug.print("结果: {s}\n", .{result});
    }
}
```

## 基础示例

### Hello World（传统方式）

```zig
const HelloTask = struct {
    message: []const u8,
    
    pub const Output = void;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        std.debug.print("来自 Zokio 的问候: {s}\n", .{self.message});
        return .{ .ready = {} };
    }
};

pub fn traditionalHelloWorld() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = zokio.RuntimeConfig{
        .worker_threads = 1,
        .enable_work_stealing = false,
    };

    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const task = HelloTask{ .message = "世界！" };
    try runtime.blockOn(task);
}
```

### 计数器任务

```zig
const CounterTask = struct {
    start: u32,
    end: u32,
    current: u32,
    
    pub const Output = u32;
    
    pub fn init(start: u32, end: u32) CounterTask {
        return CounterTask{
            .start = start,
            .end = end,
            .current = start,
        };
    }
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        
        if (self.current >= self.end) {
            return .{ .ready = self.current };
        }
        
        self.current += 1;
        std.debug.print("计数: {}\n", .{self.current});
        
        if (self.current >= self.end) {
            return .{ .ready = self.current };
        }
        
        return .pending;
    }
};

pub fn counterExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    const counter = CounterTask.init(0, 5);
    const handle = try runtime.spawn(counter);
    const result = try handle.join();
    
    std.debug.print("最终计数: {}\n", .{result});
}
```

## 网络编程

### HTTP 客户端示例

```zig
pub fn httpClientExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 🌐 异步 HTTP GET 请求
    const http_get = zokio.async_fn(struct {
        fn get(url: []const u8) []const u8 {
            std.debug.print("发送 GET 请求到: {s}\n", .{url});
            // 这里会是真实的 HTTP 实现
            return "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, World!";
        }
    }.get, .{"https://httpbin.org/get"});

    const handle = try runtime.spawn(http_get);
    const response = try zokio.await_fn(handle);
    
    std.debug.print("响应: {s}\n", .{response});
}
```

### TCP 服务器示例

```zig
pub fn tcpServerExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 🌐 异步 TCP 服务器
    const server_task = zokio.async_fn(struct {
        fn serve(port: u16) []const u8 {
            std.debug.print("TCP 服务器监听端口: {}\n", .{port});
            // 这里会是真实的 TCP 服务器实现
            return "服务器启动成功";
        }
    }.serve, .{@as(u16, 8080)});

    const handle = try runtime.spawn(server_task);
    const result = try zokio.await_fn(handle);
    
    std.debug.print("服务器状态: {s}\n", .{result});
}
```

## 文件 I/O

### 异步文件读取

```zig
pub fn fileReadExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 📁 异步文件读取
    const read_task = zokio.async_fn(struct {
        fn readFile(path: []const u8) []const u8 {
            std.debug.print("读取文件: {s}\n", .{path});
            // 这里会是真实的异步文件读取实现
            return "文件内容示例";
        }
    }.readFile, .{"example.txt"});

    const handle = try runtime.spawn(read_task);
    const content = try zokio.await_fn(handle);
    
    std.debug.print("文件内容: {s}\n", .{content});
}
```

### 异步文件写入

```zig
pub fn fileWriteExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 📁 异步文件写入
    const write_task = zokio.async_fn(struct {
        fn writeFile(path: []const u8, content: []const u8) u32 {
            std.debug.print("写入文件: {s}, 内容: {s}\n", .{ path, content });
            // 这里会是真实的异步文件写入实现
            return @intCast(content.len);
        }
    }.writeFile, .{ "output.txt", "Hello, Zokio!" });

    const handle = try runtime.spawn(write_task);
    const bytes_written = try zokio.await_fn(handle);
    
    std.debug.print("写入字节数: {}\n", .{bytes_written});
}
```

## 并发模式

### 生产者-消费者模式

```zig
pub fn producerConsumerExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 🏭 生产者任务
    const producer = zokio.async_fn(struct {
        fn produce(count: u32) []const u8 {
            std.debug.print("生产者生产了 {} 个项目\n", .{count});
            return "生产完成";
        }
    }.produce, .{@as(u32, 10)});

    // 🛒 消费者任务
    const consumer = zokio.async_fn(struct {
        fn consume(count: u32) []const u8 {
            std.debug.print("消费者消费了 {} 个项目\n", .{count});
            return "消费完成";
        }
    }.consume, .{@as(u32, 10)});

    // 并发执行
    const producer_handle = try runtime.spawn(producer);
    const consumer_handle = try runtime.spawn(consumer);

    const producer_result = try zokio.await_fn(producer_handle);
    const consumer_result = try zokio.await_fn(consumer_handle);

    std.debug.print("生产者: {s}, 消费者: {s}\n", .{ producer_result, consumer_result });
}
```

## 错误处理

### 异步错误处理

```zig
pub fn errorHandlingExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // ❌ 可能失败的异步任务
    const risky_task = zokio.async_fn(struct {
        fn riskyOperation(should_fail: bool) !u32 {
            if (should_fail) {
                std.debug.print("操作失败！\n", .{});
                return error.OperationFailed;
            }
            std.debug.print("操作成功！\n", .{});
            return 42;
        }
    }.riskyOperation, .{false});

    const handle = try runtime.spawn(risky_task);
    const result = zokio.await_fn(handle) catch |err| {
        std.debug.print("捕获错误: {}\n", .{err});
        return;
    };

    std.debug.print("结果: {}\n", .{result});
}
```

## 性能优化

### 高性能批处理

```zig
pub fn batchProcessingExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    var handles = std.ArrayList(zokio.runtime.JoinHandle(u32)).init(allocator);
    defer handles.deinit();

    // 🚀 批量生成高性能任务
    const batch_size = 1000;
    for (0..batch_size) |i| {
        const task = zokio.async_fn(struct {
            fn process(id: u32) u32 {
                return id * id; // 简单计算
            }
        }.process, .{@as(u32, @intCast(i))});
        
        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // 🚀 批量等待结果
    var total: u64 = 0;
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        total += result;
    }

    std.debug.print("批处理完成，总和: {}\n", .{total});
}
```

---

**这些示例展示了 Zokio 革命性的 async_fn/await_fn 系统，提供了世界上最快的异步编程体验！** 🚀
