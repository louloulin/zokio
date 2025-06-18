# Zokio async/await 使用指南

## 快速开始

### 安装和设置

1. **添加Zokio依赖**
```zig
// build.zig.zon
.{
    .name = "my-async-app",
    .version = "0.1.0",
    .dependencies = .{
        .zokio = .{
            .url = "https://github.com/your-org/zokio/archive/main.tar.gz",
            .hash = "...",
        },
    },
}
```

2. **配置build.zig**
```zig
const zokio = b.dependency("zokio", .{});
exe.root_module.addImport("zokio", zokio.module("zokio"));
```

### 第一个异步程序

```zig
const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化运行时
    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();

    // 定义异步函数
    const AsyncHello = zokio.future.async_fn_with_params(struct {
        fn sayHello(name: []const u8) []const u8 {
            std.debug.print("Hello, {s}!\n", .{name});
            return "问候完成";
        }
    }.sayHello);

    // 执行异步任务
    const task = AsyncHello{ .params = .{ .arg0 = "Zokio" } };
    const result = try runtime.blockOn(task);
    
    std.debug.print("结果: {s}\n", .{result});
}
```

## 基础概念

### 异步函数 (async_fn)

异步函数是Zokio中的基本构建块，用于将普通函数转换为可以异步执行的任务。

#### 无参数异步函数

```zig
const SimpleAsync = zokio.future.async_fn(struct {
    fn compute() u32 {
        // 执行一些计算
        var result: u32 = 0;
        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            result += i;
        }
        return result;
    }
}.compute);

// 使用
var task = SimpleAsync.init(struct {
    fn compute() u32 {
        var result: u32 = 0;
        var i: u32 = 0;
        while (i < 1000) : (i += 1) {
            result += i;
        }
        return result;
    }
}.compute);

const result = try runtime.blockOn(task);
```

#### 带参数异步函数

```zig
const AsyncCalculator = zokio.future.async_fn_with_params(struct {
    fn multiply(a: u32, b: u32) u32 {
        return a * b;
    }
}.multiply);

// 使用
const task = AsyncCalculator{
    .params = .{ .arg0 = 10, .arg1 = 20 },
};
const result = try runtime.blockOn(task); // 结果: 200
```

### 异步等待 (await_fn)

`await_fn`用于在异步块中等待其他异步操作完成。

```zig
const AsyncStep1 = zokio.future.async_fn_with_params(struct {
    fn step1(input: u32) u32 {
        return input + 10;
    }
}.step1);

const AsyncStep2 = zokio.future.async_fn_with_params(struct {
    fn step2(input: u32) u32 {
        return input * 2;
    }
}.step2);

const AsyncPipeline = zokio.future.async_block(struct {
    fn execute() u32 {
        // 使用await_fn进行异步等待
        const step1_result = zokio.future.await_fn(AsyncStep1{ .params = .{ .arg0 = 5 } });
        const step2_result = zokio.future.await_fn(AsyncStep2{ .params = .{ .arg0 = step1_result } });
        return step2_result;
    }
}.execute);
```

### 异步块 (async_block)

异步块允许你组合多个异步操作，创建复杂的异步工作流。

```zig
const ComplexWorkflow = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 步骤1: 获取数据
        const data = zokio.future.await_fn(fetchData());
        
        // 步骤2: 验证数据
        const validated = zokio.future.await_fn(validateData(data));
        
        // 步骤3: 处理数据
        const processed = zokio.future.await_fn(processData(validated));
        
        // 步骤4: 保存结果
        const saved = zokio.future.await_fn(saveData(processed));
        
        return saved;
    }
}.execute);
```

## 实际应用场景

### 1. 网络请求处理

```zig
const AsyncHttpClient = struct {
    const AsyncGet = zokio.future.async_fn_with_params(struct {
        fn httpGet(url: []const u8) []const u8 {
            // 模拟HTTP GET请求
            std.debug.print("请求: {s}\n", .{url});
            std.time.sleep(100 * std.time.ns_per_ms); // 模拟网络延迟
            return "HTTP响应数据";
        }
    }.httpGet);
    
    const AsyncPost = zokio.future.async_fn_with_params(struct {
        fn httpPost(url: []const u8, data: []const u8) []const u8 {
            std.debug.print("POST到: {s}, 数据: {s}\n", .{ url, data });
            std.time.sleep(150 * std.time.ns_per_ms);
            return "POST成功";
        }
    }.httpPost);
};

// 使用示例
const WebApiCall = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 获取用户信息
        const user_data = zokio.future.await_fn(
            AsyncHttpClient.AsyncGet{ .params = .{ .arg0 = "https://api.example.com/user/123" } }
        );
        
        // 更新用户信息
        const update_result = zokio.future.await_fn(
            AsyncHttpClient.AsyncPost{ .params = .{ .arg0 = "https://api.example.com/user/123", .arg1 = user_data } }
        );
        
        return update_result;
    }
}.execute);
```

### 2. 文件处理

```zig
const AsyncFileOps = struct {
    const AsyncReadFile = zokio.future.async_fn_with_params(struct {
        fn readFile(path: []const u8) []const u8 {
            std.debug.print("读取文件: {s}\n", .{path});
            // 模拟文件读取
            return "文件内容";
        }
    }.readFile);
    
    const AsyncWriteFile = zokio.future.async_fn_with_params(struct {
        fn writeFile(path: []const u8, content: []const u8) []const u8 {
            std.debug.print("写入文件: {s}, 内容: {s}\n", .{ path, content });
            return "写入成功";
        }
    }.writeFile);
    
    const AsyncProcessFile = zokio.future.async_fn_with_params(struct {
        fn processFile(content: []const u8) []const u8 {
            std.debug.print("处理内容: {s}\n", .{content});
            return "处理后的内容";
        }
    }.processFile);
};

// 文件处理管道
const FileProcessingPipeline = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 读取输入文件
        const content = zokio.future.await_fn(
            AsyncFileOps.AsyncReadFile{ .params = .{ .arg0 = "input.txt" } }
        );
        
        // 处理内容
        const processed = zokio.future.await_fn(
            AsyncFileOps.AsyncProcessFile{ .params = .{ .arg0 = content } }
        );
        
        // 写入输出文件
        const result = zokio.future.await_fn(
            AsyncFileOps.AsyncWriteFile{ .params = .{ .arg0 = "output.txt", .arg1 = processed } }
        );
        
        return result;
    }
}.execute);
```

### 3. 数据库操作

```zig
const AsyncDatabase = struct {
    const AsyncQuery = zokio.future.async_fn_with_params(struct {
        fn query(sql: []const u8) []const u8 {
            std.debug.print("执行查询: {s}\n", .{sql});
            std.time.sleep(50 * std.time.ns_per_ms); // 模拟数据库延迟
            return "查询结果";
        }
    }.query);
    
    const AsyncInsert = zokio.future.async_fn_with_params(struct {
        fn insert(table: []const u8, data: []const u8) u64 {
            std.debug.print("插入数据到 {s}: {s}\n", .{ table, data });
            std.time.sleep(30 * std.time.ns_per_ms);
            return 12345; // 返回插入的ID
        }
    }.insert);
};

// 数据库事务
const DatabaseTransaction = zokio.future.async_block(struct {
    fn execute() u64 {
        // 查询现有数据
        const existing = zokio.future.await_fn(
            AsyncDatabase.AsyncQuery{ .params = .{ .arg0 = "SELECT * FROM users WHERE id = 1" } }
        );
        
        // 插入新数据
        const new_id = zokio.future.await_fn(
            AsyncDatabase.AsyncInsert{ .params = .{ .arg0 = "users", .arg1 = "新用户数据" } }
        );
        
        return new_id;
    }
}.execute);
```

## 错误处理模式

### 1. 基础错误处理

```zig
const AsyncRiskyOperation = zokio.future.async_fn_with_params(struct {
    fn riskyOp(input: []const u8) ![]const u8 {
        if (std.mem.eql(u8, input, "error")) {
            return error.OperationFailed;
        }
        return "成功";
    }
}.riskyOp);

// 错误处理
const task = AsyncRiskyOperation{ .params = .{ .arg0 = "normal" } };
const result = try runtime.blockOn(task);
```

### 2. 重试机制

```zig
const RetryableOperation = zokio.future.async_block(struct {
    fn execute() []const u8 {
        var attempts: u32 = 0;
        while (attempts < 3) {
            const result = zokio.future.await_fn(
                AsyncRiskyOperation{ .params = .{ .arg0 = "可能失败的输入" } }
            );
            
            // 检查结果，如果成功则返回
            if (!std.mem.eql(u8, result, "失败")) {
                return result;
            }
            
            attempts += 1;
            std.debug.print("重试第 {} 次\n", .{attempts});
        }
        return "重试失败";
    }
}.execute);
```

### 3. 超时处理

```zig
const TimeoutOperation = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 在实际实现中，这里会有超时逻辑
        const start_time = std.time.milliTimestamp();
        
        const result = zokio.future.await_fn(slow_operation);
        
        const end_time = std.time.milliTimestamp();
        if (end_time - start_time > 5000) { // 5秒超时
            return "操作超时";
        }
        
        return result;
    }
}.execute);
```

## 性能优化技巧

### 1. 避免不必要的异步化

```zig
// 好的做法：只对真正需要异步的操作使用async_fn
const AsyncHeavyComputation = zokio.future.async_fn_with_params(struct {
    fn heavyCompute(data: []const u8) []const u8 {
        // 重计算任务
        return processLargeData(data);
    }
}.heavyCompute);

// 避免：对简单操作使用异步
// const AsyncSimpleAdd = zokio.future.async_fn_with_params(struct {
//     fn add(a: u32, b: u32) u32 { return a + b; }
// }.add); // 这样做没有必要
```

### 2. 批量操作

```zig
const BatchProcessor = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 批量处理多个项目
        var results = std.ArrayList([]const u8).init(allocator);
        defer results.deinit();
        
        const items = [_][]const u8{ "item1", "item2", "item3" };
        for (items) |item| {
            const result = zokio.future.await_fn(
                ProcessItem{ .params = .{ .arg0 = item } }
            );
            results.append(result) catch {};
        }
        
        return "批量处理完成";
    }
}.execute);
```

### 3. 内存管理

```zig
const MemoryEfficientAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 使用栈分配的缓冲区
        var buffer: [1024]u8 = undefined;
        
        const result = zokio.future.await_fn(
            ProcessWithBuffer{ .params = .{ .arg0 = &buffer } }
        );
        
        return result;
    }
}.execute);
```

## 调试和测试

### 1. 添加日志

```zig
const LoggedAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        std.debug.print("开始异步操作\n", .{});
        
        const result = zokio.future.await_fn(some_operation);
        
        std.debug.print("异步操作完成: {s}\n", .{result});
        return result;
    }
}.execute);
```

### 2. 单元测试

```zig
test "异步函数测试" {
    const testing = std.testing;
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();
    
    const task = TestAsyncFunction{ .params = .{ .arg0 = "测试输入" } };
    const result = try runtime.blockOn(task);
    
    try testing.expectEqualStrings("期望输出", result);
}
```

### 3. 性能测试

```zig
test "异步函数性能测试" {
    const start_time = std.time.nanoTimestamp();
    
    const task = PerformanceTestAsync{ .params = .{ .arg0 = 1000 } };
    _ = try runtime.blockOn(task);
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    std.debug.print("性能测试耗时: {d:.2}ms\n", .{duration_ms});
}
```

## 常见问题和解决方案

### 1. 编译错误

**问题**: `await_fn() requires a Future-like type`
**解决**: 确保传递给await_fn的是正确的Future类型

```zig
// 错误
const result = zokio.future.await_fn("不是Future");

// 正确
const result = zokio.future.await_fn(AsyncTask{ .params = .{ .arg0 = "输入" } });
```

### 2. 运行时错误

**问题**: 任务一直处于pending状态
**解决**: 检查异步函数的实现，确保正确返回结果

### 3. 性能问题

**问题**: 异步操作比同步操作慢
**解决**: 
- 检查是否过度使用异步
- 优化异步函数的实现
- 使用批量操作减少开销

## 下一步

- 查看 [API文档](async_await_api.md) 了解详细的API说明
- 运行 `examples/real_async_await_demo.zig` 查看完整示例
- 执行 `zig build stress-async-await` 进行性能测试
