# Zokio 快速开始

本指南将帮助您快速上手Zokio，这是Zig的高性能异步运行时。

## 前置要求

开始之前，请确保您有：

- **Zig 0.14.0或更高版本**: 从[ziglang.org](https://ziglang.org/download/)下载
- **支持的平台**: Linux、macOS、Windows或BSD
- **基础Zig知识**: 熟悉Zig语法和概念

## 安装

### 方法1: 使用Zig包管理器（推荐）

将Zokio添加到您的`build.zig.zon`：

```zig
.{
    .name = "my-zokio-project",
    .version = "0.1.0",
    .dependencies = .{
        .zokio = .{
            .url = "https://github.com/louloulin/zokio/archive/main.tar.gz",
            .hash = "1234567890abcdef...", // 替换为实际哈希值
        },
    },
}
```

更新您的`build.zig`：

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 添加Zokio依赖
    const zokio_dep = b.dependency("zokio", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 链接Zokio
    exe.root_module.addImport("zokio", zokio_dep.module("zokio"));

    b.installArtifact(exe);
}
```

### 方法2: Git子模块

```bash
git submodule add https://github.com/louloulin/zokio.git deps/zokio
```

然后在您的`build.zig`中：

```zig
const zokio = b.addModule("zokio", .{
    .root_source_file = b.path("deps/zokio/src/lib.zig"),
});
exe.root_module.addImport("zokio", zokio);
```

## 您的第一个Zokio应用程序

创建`src/main.zig`：

```zig
const std = @import("std");
const zokio = @import("zokio");

// 定义一个简单的异步任务
const HelloTask = struct {
    name: []const u8,
    
    // 必需：定义输出类型
    pub const Output = void;
    
    // 必需：实现poll方法
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx; // 在这个简单示例中不使用上下文
        
        std.debug.print("来自异步任务的问候: {s}!\n", .{self.name});
        
        // 返回就绪状态和结果
        return .{ .ready = {} };
    }
};

pub fn main() !void {
    // 设置内存分配器
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 配置运行时
    const config = zokio.RuntimeConfig{
        .worker_threads = 4,              // 使用4个工作线程
        .enable_work_stealing = true,     // 启用工作窃取进行负载均衡
        .enable_io_uring = true,          // 在Linux上使用io_uring（如果可用）
        .enable_metrics = true,           // 启用性能指标
        .enable_numa = true,              // 启用NUMA优化
    };

    // 创建运行时实例
    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    // 打印运行时信息
    std.debug.print("Zokio运行时已启动！\n", .{});
    std.debug.print("平台: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.platform});
    std.debug.print("架构: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.architecture});
    std.debug.print("工作线程: {}\n", .{RuntimeType.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("I/O后端: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.io_backend});

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 创建并执行异步任务
    const task = HelloTask{ .name = "Zokio" };
    try runtime.blockOn(task);
    
    std.debug.print("任务成功完成！\n", .{});
}
```

## 构建和运行

```bash
# 构建应用程序
zig build

# 运行应用程序
./zig-out/bin/my-app
```

预期输出：
```
Zokio运行时已启动！
平台: darwin
架构: aarch64
工作线程: 4
I/O后端: kqueue
来自异步任务的问候: Zokio!
任务成功完成！
```

## 理解基础知识

### 运行时配置

`RuntimeConfig`结构体允许您自定义运行时行为：

```zig
const config = zokio.RuntimeConfig{
    // 工作线程数量（null = 自动检测CPU核心数）
    .worker_threads = null,
    
    // 启用工作窃取调度器进行负载均衡
    .enable_work_stealing = true,
    
    // 平台特定的I/O优化
    .enable_io_uring = true,    // Linux: io_uring
    .enable_kqueue = true,      // macOS/BSD: kqueue
    .enable_iocp = true,        // Windows: IOCP
    
    // 内存优化
    .enable_numa = true,        // NUMA感知分配
    .enable_simd = true,        // SIMD优化
    .memory_strategy = .adaptive, // 自适应内存管理
    
    // 调试和监控
    .enable_metrics = true,     // 性能指标
    .enable_tracing = false,    // 分布式追踪
    .check_async_context = true, // 异步上下文验证
};
```

### 任务实现

每个异步任务必须实现：

1. **输出类型**: 定义任务返回的内容
2. **poll方法**: 核心异步逻辑

```zig
const MyTask = struct {
    data: SomeData,
    
    // 必需：输出类型
    pub const Output = ResultType;
    
    // 必需：Poll方法
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(ResultType) {
        // 您的异步逻辑在这里
        
        if (task_is_ready) {
            return .{ .ready = result };
        } else {
            // 任务未就绪，稍后将再次轮询
            return .pending;
        }
    }
};
```

### 运行时操作

```zig
// 创建运行时
var runtime = try zokio.ZokioRuntime(config).init(allocator);
defer runtime.deinit();

// 启动运行时（生成工作线程）
try runtime.start();
defer runtime.stop();

// 执行任务并等待完成
const result = try runtime.blockOn(task);

// 生成任务并发运行（立即返回）
const handle = try runtime.spawn(task);
const result = try handle.join(); // 等待完成
```

## 下一步

现在您有了一个基本的Zokio应用程序在运行，探索：

1. **[架构指南](architecture.md)**: 了解Zokio内部工作原理
2. **[API参考](api-reference.md)**: 完整的API文档
3. **[示例代码](examples.md)**: 更复杂的示例和模式
4. **[性能指南](performance.md)**: 优化技术

## 常见模式

### 错误处理

```zig
const ErrorTask = struct {
    pub const Output = !u32; // 任务可以返回错误
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(!u32) {
        _ = ctx;
        _ = self;
        
        if (some_error_condition) {
            return .{ .ready = error.SomeError };
        }
        
        return .{ .ready = 42 };
    }
};

// 执行时处理错误
const result = runtime.blockOn(ErrorTask{}) catch |err| {
    std.debug.print("任务失败: {}\n", .{err});
    return;
};
```

### 异步延迟

```zig
const DelayTask = struct {
    delay_ms: u64,
    start_time: ?i64 = null,
    
    pub const Output = void;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        
        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            return .pending;
        }
        
        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            return .{ .ready = {} };
        }
        
        return .pending;
    }
};

// 使用延迟任务
const delay = DelayTask{ .delay_ms = 1000 }; // 1秒延迟
try runtime.blockOn(delay);
```

## 故障排除

### 常见问题

1. **编译错误**: 确保您使用的是Zig 0.14.0或更高版本
2. **平台支持**: 检查您的平台是否受支持
3. **内存问题**: 使用适当的分配器并检查泄漏
4. **性能**: 使用`-O ReleaseFast`启用优化

### 调试模式

为开发启用调试功能：

```zig
const config = zokio.RuntimeConfig{
    .enable_metrics = true,
    .enable_tracing = true,
    .check_async_context = true,
};
```

### 获取帮助

- 查看[示例代码](examples.md)了解类似用例
- 查看[API参考](api-reference.md)获取详细文档
- 在GitHub上开issue报告错误或功能请求

---

您现在已经准备好使用Zokio构建高性能异步应用程序了！🚀
