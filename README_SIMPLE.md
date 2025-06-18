# Zokio - 简洁的 Zig async/await 运行时

[![Zig Version](https://img.shields.io/badge/zig-0.14.0+-blue.svg)](https://ziglang.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()

一个用 Zig 编写的高性能异步运行时，提供简洁的 async/await 语法，类似于 Rust 的异步编程模型。

## ✨ 核心特性

- 🚀 **简洁的 async/await 语法** - 类似 Rust 的异步编程体验
- ⚡ **零成本抽象** - 编译时优化，无运行时开销
- 🛡️ **类型安全** - 完整的编译时类型检查
- 🔧 **易于使用** - 最小化的 API 设计
- 🌐 **跨平台支持** - 支持主流操作系统
- 📊 **高性能** - 优化的异步执行引擎

## 🎯 核心语法

```zig
const zokio = @import("zokio");

// 创建异步块
const task = zokio.async_block(struct {
    fn run() []const u8 {
        const result1 = zokio.await_fn(fetch_data());
        const result2 = zokio.await_fn(process_data(result1));
        return result2;
    }
}.run);

// 创建运行时并执行
var runtime = zokio.simple_runtime.builder()
    .threads(2)
    .build(allocator);
defer runtime.deinit();

try runtime.start();
const result = try runtime.blockOn(task);
```

## 🚀 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/your-username/zokio.git
cd zokio

# 构建项目
zig build

# 运行测试
zig build test

# 运行核心演示
zig build example-async_block_demo
./zig-out/bin/async_block_demo
```

### 基础示例

```zig
const std = @import("std");
const zokio = @import("zokio");

// 定义异步任务
fn fetchData() DataFetcher {
    return DataFetcher.init("https://api.example.com", 50);
}

fn processData(input: []const u8) DataProcessor {
    return DataProcessor.init(input, 30);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    // 创建运行时
    var runtime = zokio.simple_runtime.builder()
        .threads(2)
        .workStealing(true)
        .build(gpa.allocator());
    defer runtime.deinit();
    
    try runtime.start();
    
    // 定义异步工作流
    const workflow = zokio.async_block(struct {
        fn run() []const u8 {
            // 步骤1: 获取数据
            const raw_data = zokio.await_fn(fetchData());
            
            // 步骤2: 处理数据
            const processed = zokio.await_fn(processData(raw_data));
            
            return processed;
        }
    }.run);
    
    // 执行工作流
    const result = try runtime.blockOn(workflow);
    std.debug.print("结果: {s}\n", .{result});
}
```

## 📚 更多示例

### 条件分支

```zig
const conditional_task = zokio.async_block(struct {
    fn run() []const u8 {
        const data = zokio.await_fn(fetchData());
        
        if (data.len > 0) {
            return zokio.await_fn(processData(data));
        } else {
            return zokio.await_fn(fetchData()); // 重试
        }
    }
}.run);
```

### 循环操作

```zig
const loop_task = zokio.async_block(struct {
    fn run() []const u8 {
        var result: []const u8 = "初始值";
        
        for (0..3) |i| {
            std.debug.print("循环第{}次\n", .{i + 1});
            result = zokio.await_fn(processData(result));
        }
        
        return result;
    }
}.run);
```

### 复杂工作流

```zig
const complex_workflow = zokio.async_block(struct {
    fn run() []const u8 {
        // 并行获取多个数据源
        const data1 = zokio.await_fn(fetchData());
        const data2 = zokio.await_fn(fetchData());
        
        // 处理合并的数据
        const processed = zokio.await_fn(processData(data1));
        
        // 保存结果
        const saved = zokio.await_fn(saveData(processed));
        
        return saved;
    }
}.run);
```

## 🔧 API 参考

### 核心函数

- `zokio.async_block(func)` - 创建异步块
- `zokio.await_fn(future)` - 等待 Future 完成
- `zokio.simple_runtime.builder()` - 创建运行时构建器

### 运行时配置

```zig
var runtime = zokio.simple_runtime.builder()
    .threads(4)           // 设置线程数
    .workStealing(true)   // 启用工作窃取
    .queueSize(1024)      // 设置队列大小
    .metrics(true)        // 启用性能指标
    .build(allocator);
```

### Future 工具

- `zokio.ready(T, value)` - 创建已完成的 Future
- `zokio.pending(T)` - 创建挂起的 Future
- `zokio.delay(ms)` - 创建延迟 Future
- `zokio.timeout(future, ms)` - 添加超时控制

## 📊 性能特征

- **编译时优化**: 所有抽象在编译时消除
- **零分配**: async_block 不进行堆分配
- **类型安全**: 完整的编译时类型检查
- **高效调度**: 优化的任务调度器

## 🎯 设计理念

Zokio 的设计遵循以下原则：

1. **简洁性** - 最小化的 API 表面
2. **性能** - 零成本抽象和编译时优化
3. **安全性** - 类型安全和内存安全
4. **易用性** - 直观的异步编程体验

## 🔍 项目状态

- ✅ **核心功能完成** - async_block 和 await_fn 实现
- ✅ **测试通过** - 所有单元测试和集成测试
- ✅ **演示验证** - 完整的功能演示
- ✅ **文档完整** - 详细的使用文档

## 📖 文档

- [完整分析文档](ZOKIO_ASYNC_AWAIT_ANALYSIS.md) - 深入的技术分析
- [示例代码](examples/) - 各种使用示例
- [API 文档](docs/) - 详细的 API 参考

## 🤝 贡献

欢迎贡献代码、报告问题或提出建议！

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

🚀 **Zokio - 让 Zig 的异步编程更简洁、更强大、更高效！**
