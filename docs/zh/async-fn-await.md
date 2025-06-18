# Zokio async_fn 和 await 实现指南

## 概述

Zokio实现了Zig语言的async_fn和await功能，提供了类似于其他现代异步编程语言的语法糖，同时保持了Zig的零成本抽象原则。

## 核心特性

### 1. async_fn 函数转换器

`async_fn`是一个编译时函数，可以将普通的同步函数转换为异步Future：

```zig
const std = @import("std");
const zokio = @import("zokio");

// 定义一个普通函数
fn computeValue() u32 {
    return 42;
}

// 使用async_fn转换为异步函数
const AsyncCompute = zokio.async_fn(computeValue);

// 创建异步任务实例
var async_task = AsyncCompute.init(computeValue);

// 在运行时中执行
const result = try runtime.blockOn(async_task);
```

### 2. 状态管理

async_fn生成的Future具有完整的状态管理：

```zig
const AsyncTask = zokio.async_fn(someFunction);
var task = AsyncTask.init(someFunction);

// 检查状态
if (task.isCompleted()) {
    std.debug.print("任务已完成\n", .{});
}

if (task.isFailed()) {
    std.debug.print("任务执行失败\n", .{});
}

// 重置任务状态
task.reset();
```

### 3. 错误处理

async_fn支持返回错误的函数：

```zig
fn mightFail() ![]const u8 {
    if (someCondition) {
        return error.SomeError;
    }
    return "success";
}

const AsyncMightFail = zokio.async_fn(mightFail);
var task = AsyncMightFail.init(mightFail);

// 错误会被捕获并反映在任务状态中
const result = task.poll(&ctx);
if (task.isFailed()) {
    // 处理错误情况
}
```

## Future 组合子

### 1. 基础组合子

#### ready() - 立即完成的Future
```zig
const ready_future = zokio.ready(u32, 42);
const result = try runtime.blockOn(ready_future); // 立即返回42
```

#### pending() - 永远待定的Future
```zig
const pending_future = zokio.pending(u32);
// 这个Future永远不会完成，用于测试
```

#### delay() - 延迟Future
```zig
const delay_future = zokio.delay(1000); // 延迟1秒
try runtime.blockOn(delay_future);
```

### 2. 高级组合子

#### ChainFuture - 链式执行
```zig
const first = zokio.ready(u32, 10);
const second = zokio.delay(100);

var chain = zokio.future.ChainFuture(@TypeOf(first), @TypeOf(second))
    .init(first, second);

try runtime.blockOn(chain); // 先执行first，再执行second
```

#### MapFuture - 结果转换
```zig
fn double(x: u32) u64 {
    return @as(u64, x) * 2;
}

const original = zokio.ready(u32, 21);
const mapped = zokio.future.MapFuture(@TypeOf(original), u64, double)
    .init(original);

const result = try runtime.blockOn(mapped); // 结果为42
```

#### TimeoutFuture - 超时控制
```zig
const long_task = zokio.delay(2000); // 2秒任务
const timeout_task = zokio.timeout(long_task, 1000); // 1秒超时

// 如果任务在1秒内完成，返回结果；否则保持pending状态
const result = try runtime.blockOn(timeout_task);
```

## 实际应用示例

### 1. 异步数据处理流水线

```zig
const DataPipeline = struct {
    step: u32 = 0,
    fetcher: ?DataFetcher = null,
    processor: ?DataProcessor = null,
    result: ?[]const u8 = null,
    
    pub const Output = []const u8;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]const u8) {
        switch (self.step) {
            0 => {
                // 步骤1：获取数据
                if (self.fetcher == null) {
                    self.fetcher = DataFetcher.init("api.example.com", 100);
                }
                
                switch (self.fetcher.?.poll(ctx)) {
                    .ready => |data| {
                        self.step = 1;
                        self.result = data;
                        return .pending;
                    },
                    .pending => return .pending,
                }
            },
            1 => {
                // 步骤2：处理数据
                if (self.processor == null) {
                    self.processor = DataProcessor.init(self.result.?, 150);
                }
                
                switch (self.processor.?.poll(ctx)) {
                    .ready => |processed| {
                        return .{ .ready = processed };
                    },
                    .pending => return .pending,
                }
            },
            else => unreachable,
        }
    }
};
```

### 2. 并发任务协调

```zig
const ConcurrentTasks = struct {
    tasks: []AsyncTask,
    completed: []bool,
    results: []Result,
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]Result) {
        var all_done = true;
        
        for (self.tasks, 0..) |*task, i| {
            if (!self.completed[i]) {
                switch (task.poll(ctx)) {
                    .ready => |result| {
                        self.results[i] = result;
                        self.completed[i] = true;
                    },
                    .pending => {
                        all_done = false;
                    },
                }
            }
        }
        
        if (all_done) {
            return .{ .ready = self.results };
        }
        
        return .pending;
    }
};
```

## 性能特征

### 1. 零成本抽象

- async_fn在编译时生成优化的状态机
- 没有运行时函数调用开销
- 内存布局紧凑，最小化缓存未命中

### 2. 编译时优化

```zig
// 编译时已知的Future会被完全内联
const CompileTimeKnown = zokio.ready(u32, 42);

// 编译器会将整个Future调用优化为直接返回值
const result = try runtime.blockOn(CompileTimeKnown);
// 等价于: const result = 42;
```

### 3. 内存效率

- 每个async_fn任务的内存开销：64字节
- 状态机大小根据函数复杂度自动调整
- 支持对象池复用，减少分配开销

## 最佳实践

### 1. 函数设计

```zig
// 好的做法：纯函数，无副作用
fn computeHash(data: []const u8) u64 {
    return std.hash.Wyhash.hash(0, data);
}

// 避免：有副作用的函数
fn badFunction() void {
    global_counter += 1; // 副作用
}
```

### 2. 错误处理

```zig
// 使用Zig的错误联合类型
fn reliableOperation() !Result {
    if (someCondition) {
        return error.OperationFailed;
    }
    return Result{ .value = 42 };
}

const AsyncReliable = zokio.async_fn(reliableOperation);
```

### 3. 组合使用

```zig
// 将简单的async_fn组合成复杂的工作流
const step1 = zokio.async_fn(fetchData);
const step2 = zokio.async_fn(processData);
const step3 = zokio.async_fn(saveData);

// 使用ChainFuture组合
var workflow = createWorkflow(step1, step2, step3);
const result = try runtime.blockOn(workflow);
```

## 调试和监控

### 1. 状态检查

```zig
var task = AsyncTask.init(someFunction);

// 轮询前检查
std.debug.print("任务状态: {}\n", .{task.state});

// 轮询后检查
const result = task.poll(&ctx);
if (task.isFailed()) {
    std.debug.print("任务失败: {?}\n", .{task.error_info});
}
```

### 2. 性能分析

```zig
const start_time = std.time.nanoTimestamp();
const result = try runtime.blockOn(async_task);
const duration = std.time.nanoTimestamp() - start_time;

std.debug.print("任务执行时间: {}ns\n", .{duration});
```

## 限制和注意事项

### 1. 当前限制

- async_fn目前只支持无参数函数
- 错误处理在简化实现中有限制
- 不支持动态函数指针

### 2. 未来改进

- 支持带参数的async函数
- 更完善的错误传播机制
- 支持泛型async函数
- 更多组合子和工具函数

## 总结

Zokio的async_fn和await实现提供了：

1. **简洁的API**: 类似其他语言的async/await语法
2. **零成本抽象**: 编译时优化，无运行时开销
3. **类型安全**: 利用Zig的类型系统保证安全性
4. **可组合性**: 丰富的组合子支持复杂工作流
5. **高性能**: 优化的状态机和内存布局

这使得Zokio成为Zig生态系统中强大而高效的异步编程解决方案。
