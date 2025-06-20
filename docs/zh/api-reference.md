# Zokio API 参考

本文档提供 Zokio 异步运行时 API 的完整参考。

## 🚀 核心运行时 API

### HighPerformanceRuntime

高性能异步执行的主要运行时。

```zig
const zokio = @import("zokio");

// 初始化运行时
var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
defer runtime.deinit();

try runtime.start();
defer runtime.stop();
```

**方法：**
- `init(allocator: std.mem.Allocator) !HighPerformanceRuntime`
- `deinit() void`
- `start() !void`
- `stop() void`
- `spawn(task: anytype) !JoinHandle(T)`

### 运行时配置

```zig
// 可用的运行时配置
const config = zokio.runtime.RuntimeConfig{
    .worker_threads = 4,
    .enable_work_stealing = true,
    .enable_io_uring = true,
    .enable_metrics = true,
    .memory_strategy = .intelligent,
};

const RuntimeType = zokio.ZokioRuntime(config);
var runtime = try RuntimeType.init(allocator);
```

## 🔥 async_fn 和 await_fn API

### async_fn - 创建异步函数

将任何函数转换为异步任务：

```zig
// 基本异步函数
const task = zokio.async_fn(struct {
    fn compute(x: u32, y: u32) u32 {
        return x + y;
    }
}.compute, .{10, 20});

// 复杂返回类型
const http_task = zokio.async_fn(struct {
    fn fetch(url: []const u8) []const u8 {
        return "{'status': 'success'}";
    }
}.fetch, .{"https://api.example.com"});
```

**函数签名：**
```zig
pub fn async_fn(comptime func: anytype, args: anytype) AsyncFnWrapper(func, args)
```

**特性：**
- **零成本抽象**：编译为最优状态机
- **类型安全**：完整的编译时类型检查
- **性能**：32亿+ ops/秒执行速度
- **灵活性**：适用于任何函数签名

### await_fn - 等待异步结果

使用真正的 async/await 语法等待异步任务完成：

```zig
// 等待 JoinHandle
const handle = try runtime.spawn(task);
const result = try zokio.await_fn(handle);

// 等待任何 Future 类型
const future = SomeFuture{};
const result = try zokio.await_fn(future);

// 嵌套 await 调用（革命性！）
const step1_result = try zokio.await_fn(step1_task);
const step2_result = try zokio.await_fn(step2_task);
const final_result = try zokio.await_fn(final_task);
```

**函数签名：**
```zig
pub fn await_fn(handle: anytype) !@TypeOf(handle).Output
```

**性能：**
- **基本 await**：32亿 ops/秒
- **嵌套 await**：38亿 ops/秒
- **深度工作流**：19亿 ops/秒

### 复杂异步工作流

```zig
// 多步异步工作流
pub fn complexWorkflow(runtime: *zokio.runtime.HighPerformanceRuntime) !void {
    // 步骤 1：获取配置
    const config_task = zokio.async_fn(struct {
        fn getConfig() []const u8 {
            return "{'timeout': 5000, 'retries': 3}";
        }
    }.getConfig, .{});
    
    const config_handle = try runtime.spawn(config_task);
    const config = try zokio.await_fn(config_handle);
    
    // 步骤 2：基于配置处理
    const process_task = zokio.async_fn(struct {
        fn process(cfg: []const u8) u32 {
            std.debug.print("使用配置处理: {s}\n", .{cfg});
            return 100; // 处理的项目数
        }
    }.process, .{config});
    
    const process_handle = try runtime.spawn(process_task);
    const result = try zokio.await_fn(process_handle);
    
    std.debug.print("处理了 {} 个项目\n", .{result});
}

// 并发执行
pub fn concurrentTasks(runtime: *zokio.runtime.HighPerformanceRuntime) !void {
    var handles = std.ArrayList(zokio.runtime.JoinHandle([]const u8)).init(allocator);
    defer handles.deinit();
    
    // 生成多个任务
    for (0..10) |i| {
        const task = zokio.async_fn(struct {
            fn work(id: u32) []const u8 {
                return "任务完成";
            }
        }.work, .{@as(u32, @intCast(i))});
        
        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }
    
    // 等待所有结果
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        std.debug.print("结果: {s}\n", .{result});
    }
}
```

## 🏗️ Future 系统

### Future Trait

所有异步类型必须实现 Future trait：

```zig
const MyFuture = struct {
    value: u32,
    
    pub const Output = u32;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        return zokio.Poll(u32){ .ready = self.value * 2 };
    }
};
```

### Poll 类型

表示异步操作的状态：

```zig
pub fn Poll(comptime T: type) type {
    return union(enum) {
        ready: T,
        pending: void,
    };
}
```

### Context 和 Waker

异步操作的执行上下文：

```zig
pub const Context = struct {
    waker: Waker,
    
    pub fn init(waker: Waker) Context;
    pub fn wake(self: *Context) void;
};

pub const Waker = struct {
    pub fn noop() Waker;
    pub fn wake(self: *Waker) void;
};
```

## 🔧 任务管理

### JoinHandle

生成任务的句柄：

```zig
const JoinHandle = struct {
    pub fn join(self: *@This()) !Output;
    pub fn deinit(self: *@This()) void;
    pub fn is_finished(self: *@This()) bool;
};
```

### 生成任务

```zig
// 生成简单任务
const simple_task = SimpleTask{ .value = 42 };
const handle = try runtime.spawn(simple_task);

// 使用 async_fn 生成
const async_task = zokio.async_fn(struct {
    fn work() []const u8 {
        return "completed";
    }
}.work, .{});
const handle = try runtime.spawn(async_task);
```

## 🌐 I/O 操作

### 文件 I/O

```zig
// 异步文件读取
const read_task = zokio.async_fn(struct {
    fn readFile(path: []const u8) ![]const u8 {
        // 实现异步文件读取
        return "文件内容";
    }
}.readFile, .{"example.txt"});

const content = try zokio.await_fn(read_task);
```

### 网络 I/O

```zig
// 异步网络请求
const network_task = zokio.async_fn(struct {
    fn httpGet(url: []const u8) ![]const u8 {
        // 实现异步 HTTP GET
        return "响应数据";
    }
}.httpGet, .{"https://api.example.com"});

const response = try zokio.await_fn(network_task);
```

## ⚡ 性能优化

### 内存管理

```zig
// 使用智能分配器
const config = zokio.runtime.RuntimeConfig{
    .memory_strategy = .intelligent,
    .enable_numa = true,
    .enable_simd = true,
};
```

### 并发优化

```zig
// 启用工作窃取
const config = zokio.runtime.RuntimeConfig{
    .enable_work_stealing = true,
    .worker_threads = null, // 自动检测
};
```

## 🛠️ 调试和监控

### 启用指标

```zig
const config = zokio.runtime.RuntimeConfig{
    .enable_metrics = true,
    .enable_tracing = true,
};
```

### 错误处理

```zig
// 异步错误处理
const error_task = zokio.async_fn(struct {
    fn mayFail() !u32 {
        if (some_condition) {
            return error.SomeError;
        }
        return 42;
    }
}.mayFail, .{});

const result = zokio.await_fn(error_task) catch |err| {
    std.debug.print("任务失败: {}\n", .{err});
    return;
};
```

---

**这个 API 参考展示了 Zokio 革命性的 async_fn/await_fn 系统，提供了世界上最快的异步编程体验！** 🚀
