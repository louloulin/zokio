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

---

准备好释放异步Zig的力量了吗？让我们开始吧！🚀
