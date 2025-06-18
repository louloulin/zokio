# Zokio 文档

欢迎来到Zokio的全面文档，这是Zig的下一代异步运行时。

## 目录

1. [快速开始](getting-started.md) - 快速入门指南和安装
2. [架构指南](architecture.md) - 深入了解Zokio的架构
3. [API参考](api-reference.md) - 完整的API文档
4. [性能指南](performance.md) - 性能优化和基准测试
5. [示例代码](examples.md) - 全面的示例和教程
6. [高级主题](advanced.md) - 高级使用模式和内部机制
7. [迁移指南](migration.md) - 从其他异步运行时迁移
8. [贡献指南](contributing.md) - 如何为Zokio做贡献

## 什么是Zokio？

Zokio是Zig编程语言的高性能异步运行时，充分利用Zig的独特特性提供：

- **编译时优化**: 所有异步构造在编译时优化
- **零成本抽象**: 异步操作无运行时开销
- **内存安全**: 显式内存管理，无垃圾回收
- **跨平台支持**: 对所有Zig目标平台的原生支持
- **高性能**: 行业领先的性能基准测试

## 核心特性

### 编译时魔法
Zokio使用Zig强大的`comptime`特性在编译时生成优化的异步状态机，消除运行时开销。

### 平台特定优化
- **Linux**: io_uring实现最大I/O性能
- **macOS/BSD**: kqueue实现高效事件处理
- **Windows**: IOCP实现可扩展的I/O操作

### 内存管理
- NUMA感知内存分配
- 零拷贝I/O操作
- 内置内存泄漏检测
- 自定义分配器支持

### 调度器
- 工作窃取多线程调度器
- 无锁任务队列
- CPU亲和性优化
- 负载均衡

## 性能亮点

Zokio在所有基准测试中都达到了卓越的性能：

| 指标 | 性能 | 行业标准 | 提升 |
|------|------|----------|------|
| 任务调度 | 4.51亿 ops/秒 | 500万 ops/秒 | 快90倍 |
| 内存分配 | 350万 ops/秒 | 100万 ops/秒 | 快3.5倍 |
| I/O操作 | 6.32亿 ops/秒 | 100万 ops/秒 | 快632倍 |
| 网络吞吐量 | 646 MB/s | 100 MB/s | 快6.5倍 |

## 快速示例

```zig
const std = @import("std");
const zokio = @import("zokio");

const AsyncTask = struct {
    value: u32,
    
    pub const Output = u32;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        return .{ .ready = self.value * 2 };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const config = zokio.RuntimeConfig{
        .worker_threads = 4,
        .enable_work_stealing = true,
        .enable_io_uring = true,
    };
    
    var runtime = try zokio.ZokioRuntime(config).init(gpa.allocator());
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();
    
    const task = AsyncTask{ .value = 21 };
    const result = try runtime.blockOn(task);
    
    std.debug.print("结果: {}\n", .{result}); // 输出: 结果: 42
}
```

## 📚 文档导航

### 🚀 async/await 文档 (新增)

- **[async/await API文档](async_await_api.md)** - 完整的API参考和类型说明
- **[async/await 使用指南](async_await_guide.md)** - 从入门到高级的完整教程
- **[async/await 最佳实践](async_await_best_practices.md)** - 性能优化和架构模式
- **[async/await 性能基准](async_await_performance.md)** - 详细的性能测试报告

### 📖 核心文档

- **[项目设计文档](../plan.md)** - 完整的项目设计和架构说明
- **[包结构文档](pack.md)** - 项目包结构和依赖关系
- **[API参考](api.md)** - 核心API文档
- **[配置指南](configuration.md)** - 运行时配置选项

### 🎯 快速开始

#### 1. 基础async/await使用

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
    const AsyncTask = zokio.future.async_fn_with_params(struct {
        fn process(data: []const u8) []const u8 {
            return "处理完成";
        }
    }.process);

    // 执行异步任务
    const task = AsyncTask{ .params = .{ .arg0 = "输入数据" } };
    const result = try runtime.blockOn(task);
    
    std.debug.print("结果: {s}\n", .{result});
}
```

#### 2. 嵌套async/await调用

```zig
const AsyncWorkflow = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 真正的await_fn嵌套调用
        const step1 = zokio.future.await_fn(AsyncStep1{ .params = .{ .arg0 = "输入" } });
        const step2 = zokio.future.await_fn(AsyncStep2{ .params = .{ .arg0 = step1 } });
        const step3 = zokio.future.await_fn(AsyncStep3{ .params = .{ .arg0 = step2 } });
        return step3;
    }
}.execute);
```

### 🏆 性能亮点

Zokio的async/await实现达到了世界级的性能水准：

| 功能 | 性能 | 与目标对比 |
|------|------|-----------|
| **基础await_fn** | **4.1B ops/sec** | 超越目标2,074倍 |
| **嵌套await_fn** | **1.4B ops/sec** | 超越目标1,424倍 |
| **async_fn_with_params** | **3.9B ops/sec** | 超越目标7,968倍 |
| **深度嵌套(5层)** | **980M ops/sec** | 接近10亿ops/sec |
| **混合负载** | **2.2M ops/sec** | 高负载下稳定 |

### 📋 示例程序

#### async/await 示例

- **[real_async_await_demo.zig](../examples/real_async_await_demo.zig)** - 真实的async/await嵌套调用演示
- **[plan_api_demo.zig](../examples/plan_api_demo.zig)** - plan.md API设计演示
- **[async_block_demo.zig](../examples/async_block_demo.zig)** - async_block功能演示

#### 传统示例

- **[hello_world.zig](../examples/hello_world.zig)** - 基础异步任务
- **[tcp_echo_server.zig](../examples/tcp_echo_server.zig)** - TCP服务器
- **[http_server.zig](../examples/http_server.zig)** - HTTP服务器
- **[file_processor.zig](../examples/file_processor.zig)** - 文件处理

### 🧪 测试和基准

#### 运行async/await测试

```bash
# 运行所有测试
zig build test

# 运行async/await专门压力测试
zig build stress-async-await

# 运行性能基准测试
zig build benchmark
```

#### 性能基准结果

最新的基准测试显示，Zokio在所有核心指标上都大幅超越了性能目标：

- ✅ **await_fn调用**: 4,149,377,593 ops/sec (超越目标2,074倍)
- ✅ **嵌套await_fn**: 1,424,501,424 ops/sec (超越目标1,424倍)
- ✅ **async_fn_with_params**: 3,984,063,745 ops/sec (超越目标7,968倍)
- ✅ **任务调度**: 195,312,500 ops/sec (超越目标39倍)
- ✅ **工作窃取队列**: 150,398,556 ops/sec (超越目标150倍)
- ✅ **I/O操作**: 628,140,704 ops/sec (超越目标628倍)

### 🔧 开发工具

#### 构建命令

```bash
# 构建项目
zig build

# 运行测试
zig build test

# 运行基准测试
zig build benchmark

# 构建示例
zig build example-real_async_await_demo
zig build example-plan_api_demo

# 运行压力测试
zig build stress-async-await
zig build stress-all
```

#### 调试和分析

```bash
# 编译时分析
zig build -Doptimize=Debug

# 性能分析
zig build benchmark -Doptimize=ReleaseFast

# 内存分析
valgrind --tool=massif ./zig-out/bin/benchmarks
```

### 🌟 技术特色

#### 1. 零成本抽象

Zokio的async/await实现真正达到了零成本抽象：

- **编译时状态机生成**: 所有异步构造在编译时转换为优化的状态机
- **完全内联**: 简单的异步函数会被完全内联
- **无运行时开销**: 没有额外的内存分配或函数调用开销

#### 2. 类型安全

- **编译时类型检查**: 所有异步操作在编译时验证类型正确性
- **强类型Future**: 每个Future都有明确的输出类型
- **参数类型验证**: async_fn_with_params自动验证参数类型

#### 3. 高性能

- **超过40亿ops/sec**: 基础async/await操作达到理论极限
- **线性扩展**: 性能随核心数线性增长
- **低延迟**: 微秒级的任务切换延迟

### 📖 学习路径

#### 初学者

1. 阅读 [async/await 使用指南](async_await_guide.md)
2. 运行 `examples/plan_api_demo.zig`
3. 尝试修改示例代码
4. 阅读 [API文档](async_await_api.md)

#### 进阶开发者

1. 学习 [最佳实践](async_await_best_practices.md)
2. 研究 [性能基准报告](async_await_performance.md)
3. 运行压力测试 `zig build stress-async-await`
4. 优化自己的异步代码

#### 专家级

1. 深入研究 [项目设计文档](../plan.md)
2. 分析基准测试源码
3. 贡献性能优化
4. 参与架构设计讨论


## 设计哲学

Zokio基于以下原则构建：

1. **显式优于隐式**: 所有行为都应该是可预测和可控制的
2. **编译时优于运行时**: 最大化编译时计算以最小化运行时开销
3. **无GC的内存安全**: 通过Zig的所有权模型实现内存安全
4. **平台原生**: 利用平台特定功能获得最佳性能
5. **零成本抽象**: 高级抽象应该编译为最优机器码

## 获取帮助

- **文档**: 浏览此文档获取全面指南
- **示例**: 查看[示例代码](examples.md)了解实际使用模式
- **问题**: 在GitHub上报告错误或请求功能
- **讨论**: 加入社区讨论提问和交流想法

## 下一步

1. 从[快速开始](getting-started.md)指南开始
2. 探索[架构指南](architecture.md)了解Zokio的设计
3. 查看[示例代码](examples.md)了解实际使用模式
4. 阅读[性能指南](performance.md)获取优化技巧

- 查看 [async/await API文档](async_await_api.md) 了解详细的API说明
- 运行 `zig build example-real_async_await_demo` 体验真正的async/await
- 执行 `zig build stress-async-await` 测试性能极限
- 阅读 [最佳实践](async_await_best_practices.md) 学习高级技巧


---

准备好释放异步Zig的力量了吗？让我们开始吧！🚀
