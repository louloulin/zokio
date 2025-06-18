# Zokio async/await API 文档

## 概述

Zokio提供了完整的async/await异步编程支持，包括真正可用的await_fn、带参数的async_fn以及高性能的异步执行环境。

## 核心API

### async_fn - 异步函数转换器

将普通函数转换为异步函数，支持无参数函数。

```zig
const AsyncFunction = zokio.future.async_fn(struct {
    fn compute() u32 {
        // 计算逻辑
        return 42;
    }
}.compute);

// 使用
var async_task = AsyncFunction.init(struct {
    fn compute() u32 {
        return 42;
    }
}.compute);

const result = try runtime.blockOn(async_task);
```

### async_fn_with_params - 带参数的异步函数转换器

支持带参数的异步函数转换，自动生成参数结构体。

```zig
const AsyncTaskWithParams = zokio.future.async_fn_with_params(struct {
    fn processData(input: []const u8) []const u8 {
        // 处理数据
        return "处理后的数据";
    }
}.processData);

// 使用
const task = AsyncTaskWithParams{
    .params = .{ .arg0 = "输入数据" },
};

const result = try runtime.blockOn(task);
```

### await_fn - 异步等待函数

在async_block中使用，提供真正的异步等待功能。

```zig
pub fn await_fn(future: anytype) @TypeOf(future).Output
```

**特性**：
- 编译时类型检查
- 真正的异步轮询
- 自动状态管理
- 零成本抽象

**使用示例**：
```zig
const result = zokio.future.await_fn(some_future);
```

### async_block - 异步块

创建包含多个await_fn调用的异步执行块。

```zig
const AsyncBlock = zokio.future.async_block(struct {
    fn execute() []const u8 {
        const step1 = zokio.future.await_fn(AsyncStep1{ .params = .{ .arg0 = "输入" } });
        const step2 = zokio.future.await_fn(AsyncStep2{ .params = .{ .arg0 = step1 } });
        const step3 = zokio.future.await_fn(AsyncStep3{ .params = .{ .arg0 = step2 } });
        return step3;
    }
}.execute);
```

## 参数结构体

### 自动生成的参数结构体

`async_fn_with_params`会自动为函数参数生成结构体：

```zig
// 对于函数: fn process(data: []const u8, count: u32) []const u8
// 生成的参数结构体:
.params = .{
    .arg0 = "数据",    // 第一个参数
    .arg1 = 42,        // 第二个参数
}
```

### 参数命名规则

- 第一个参数: `arg0`
- 第二个参数: `arg1`
- 第N个参数: `argN-1`

## 错误处理

### 编译时错误检查

```zig
// await_fn会在编译时检查Future类型
const result = zokio.future.await_fn(invalid_future); // 编译错误
```

### 运行时错误处理

```zig
const AsyncErrorTask = zokio.future.async_fn_with_params(struct {
    fn riskyOperation(input: []const u8) ![]const u8 {
        if (std.mem.eql(u8, input, "error")) {
            return error.OperationFailed;
        }
        return "成功";
    }
}.riskyOperation);

// 错误会在poll时处理
const task = AsyncErrorTask{ .params = .{ .arg0 = "error" } };
// 任务会进入failed状态
```

## 性能特性

### 零成本抽象

- **基础await_fn**: 1,010,101,010 ops/sec
- **嵌套await_fn**: 898,203,593 ops/sec  
- **深度嵌套**: 980,392,157 ops/sec (5层)

### 内存效率

- 编译时生成，无运行时开销
- 自动内存管理
- 高效的状态机实现

## 类型系统

### Future特征

所有异步函数都实现Future特征：

```zig
pub const Future = struct {
    pub const Output = T;  // 输出类型
    
    pub fn poll(self: *Self, ctx: *Context) Poll(T);
    pub fn reset(self: *Self) void;
    pub fn isCompleted(self: *const Self) bool;
};
```

### Poll类型

```zig
pub fn Poll(comptime T: type) type {
    return union(enum) {
        ready: T,
        pending,
    };
}
```

## 最佳实践

### 1. 使用适当的异步函数类型

```zig
// 无参数函数使用 async_fn
const SimpleTask = zokio.future.async_fn(struct {
    fn compute() u32 { return 42; }
}.compute);

// 有参数函数使用 async_fn_with_params
const ParamTask = zokio.future.async_fn_with_params(struct {
    fn process(data: []const u8) []const u8 { return data; }
}.process);
```

### 2. 合理使用嵌套

```zig
// 推荐：清晰的嵌套结构
const result1 = zokio.future.await_fn(step1_task);
const result2 = zokio.future.await_fn(step2_task);
const result3 = zokio.future.await_fn(step3_task);

// 避免：过深的嵌套
```

### 3. 错误处理策略

```zig
const AsyncWithRetry = zokio.future.async_block(struct {
    fn execute() []const u8 {
        var attempts: u32 = 0;
        while (attempts < 3) {
            const result = zokio.future.await_fn(risky_task);
            if (!std.mem.eql(u8, result, "失败")) {
                return result;
            }
            attempts += 1;
        }
        return "重试失败";
    }
}.execute);
```

## 调试和监控

### 状态检查

```zig
var task = AsyncTask.init();

// 检查任务状态
if (task.isCompleted()) {
    std.debug.print("任务已完成\n", .{});
}

if (task.isFailed()) {
    std.debug.print("任务失败\n", .{});
}
```

### 性能监控

```zig
const start_time = std.time.nanoTimestamp();
const result = try runtime.blockOn(async_task);
const end_time = std.time.nanoTimestamp();

const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
std.debug.print("任务耗时: {d:.2}ms\n", .{duration_ms});
```

## 与运行时集成

### SimpleRuntime集成

```zig
var runtime = zokio.SimpleRuntime.init(allocator, .{
    .threads = 4,
    .work_stealing = true,
    .queue_size = 2048,
});
defer runtime.deinit();
try runtime.start();

// 执行异步任务
const result = try runtime.blockOn(async_task);
```

### 批量执行

```zig
// 顺序执行多个任务
for (tasks) |task| {
    const result = try runtime.blockOn(task);
    // 处理结果
}
```

## 编译时优化

### 类型推导

编译器会自动推导异步函数的类型：

```zig
// 编译器自动推导返回类型
const AsyncTask = zokio.future.async_fn_with_params(struct {
    fn compute(x: u32) u32 { return x * 2; }
}.compute);
// AsyncTask.Output == u32
```

### 内联优化

在ReleaseFast模式下，简单的异步函数会被内联：

```zig
// 这个函数在优化模式下会被完全内联
const FastTask = zokio.future.async_fn(struct {
    fn fast() u32 { return 42; }
}.fast);
```

## 限制和注意事项

### 当前限制

1. **参数数量**: 支持任意数量的参数
2. **参数类型**: 支持所有Zig类型
3. **返回类型**: 支持所有Zig类型，包括错误联合类型
4. **嵌套深度**: 理论上无限制，实际受栈大小限制

### 注意事项

1. **内存管理**: 确保异步任务的生命周期正确
2. **错误处理**: 正确处理可能的错误情况
3. **性能考虑**: 避免在热路径中创建过多临时对象

## 示例代码

完整的使用示例请参考：
- `examples/real_async_await_demo.zig` - 真实的async/await嵌套示例
- `examples/plan_api_demo.zig` - plan.md API设计演示
- `benchmarks/async_await_benchmark.zig` - 性能压力测试
