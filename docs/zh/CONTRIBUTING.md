# 为 Zokio 贡献

感谢您对为 Zokio 贡献的兴趣！本文档为贡献者提供指南和信息。

## 🎯 项目愿景

Zokio 旨在成为**最快、最安全、最开发者友好的异步运行时**。每个贡献都应该与我们的核心原则保持一致：

- **🚀 性能优先**：保持革命性的性能优势
- **🛡️ 安全性**：零成本抽象与编译时保证
- **💡 开发者体验**：直观的 API 和优秀的文档
- **🌐 跨平台**：所有平台上一致的行为

## 🚀 开始

### 前置要求

- **Zig 0.14.0+**：从 [ziglang.org](https://ziglang.org/download/) 下载
- **Git**：用于版本控制
- **基本异步编程理解**
- **熟悉 Zig 语言**

### 开发环境设置

1. **Fork 和 Clone**
   ```bash
   git clone https://github.com/yourusername/zokio.git
   cd zokio
   ```

2. **构建和测试**
   ```bash
   zig build
   zig build test
   ```

3. **运行基准测试**
   ```bash
   zig build bench
   ```

## 📋 贡献领域

### 🔥 高优先级领域

1. **async_fn/await_fn 增强**
   - 高级异步组合器
   - 错误处理改进
   - 性能优化

2. **运行时核心改进**
   - 调度器优化
   - 内存管理增强
   - I/O 驱动改进

3. **文档和示例**
   - API 文档
   - 教程内容
   - 真实世界示例

### 🌟 中等优先级领域

1. **生态系统开发**
   - 网络协议实现
   - 数据库驱动
   - 实用工具库

2. **开发者工具**
   - IDE 集成
   - 调试工具
   - 性能分析工具

3. **测试和质量保证**
   - 测试覆盖率改进
   - 基准测试开发
   - 跨平台测试

## 🛠️ 开发指南

### 代码风格

1. **遵循 Zig 约定**
   ```zig
   // ✅ 好：清晰、描述性的名称
   const AsyncTask = struct {
       pub fn poll(self: *@This(), ctx: *Context) Poll(T) {
           // 实现
       }
   };
   
   // ❌ 避免：不清楚的缩写
   const AT = struct {
       pub fn p(s: *@This(), c: *Ctx) P(T) {
           // 实现
       }
   };
   ```

2. **性能意识代码**
   ```zig
   // ✅ 好：零成本抽象
   pub fn async_fn(comptime func: anytype, args: anytype) AsyncFnWrapper(func, args) {
       return AsyncFnWrapper(func, args).init(args);
   }
   
   // ❌ 避免：运行时开销
   pub fn async_fn_slow(func: *const fn() void) RuntimeWrapper {
       return RuntimeWrapper{ .func = func };
   }
   ```

3. **文档标准**
   ```zig
   /// 创建具有编译时优化的异步函数包装器。
   /// 
   /// 此函数将任何常规函数转换为可以由 Zokio 运行时
   /// 以革命性性能执行的异步任务。
   /// 
   /// 性能：32亿+ 操作每秒
   /// 
   /// 示例：
   /// ```zig
   /// const task = zokio.async_fn(struct {
   ///     fn compute(x: u32) u32 {
   ///         return x * 2;
   ///     }
   /// }.compute, .{42});
   /// ```
   pub fn async_fn(comptime func: anytype, args: anytype) AsyncFnWrapper(func, args) {
       return AsyncFnWrapper(func, args).init(args);
   }
   ```

### 测试要求

1. **单元测试**
   ```zig
   test "async_fn 基本功能" {
       const task = zokio.async_fn(struct {
           fn add(a: u32, b: u32) u32 {
               return a + b;
           }
       }.add, .{10, 20});
       
       // 测试实现
       try std.testing.expect(task.result == 30);
   }
   ```

2. **性能测试**
   ```zig
   test "async_fn 性能基准测试" {
       const iterations = 1_000_000;
       const start = std.time.nanoTimestamp();
       
       for (0..iterations) |_| {
           const task = zokio.async_fn(struct {
               fn noop() void {}
           }.noop, .{});
           _ = task;
       }
       
       const end = std.time.nanoTimestamp();
       const ops_per_sec = iterations * 1_000_000_000 / (end - start);
       
       // 应该达到 >10亿 ops/秒
       try std.testing.expect(ops_per_sec > 1_000_000_000);
   }
   ```

3. **集成测试**
   ```zig
   test "完整异步工作流" {
       var runtime = try zokio.runtime.HighPerformanceRuntime.init(std.testing.allocator);
       defer runtime.deinit();
       
       try runtime.start();
       defer runtime.stop();
       
       const task = zokio.async_fn(struct {
           fn work() []const u8 {
               return "completed";
           }
       }.work, .{});
       
       const handle = try runtime.spawn(task);
       const result = try zokio.await_fn(handle);
       
       try std.testing.expectEqualStrings("completed", result);
   }
   ```

## 📊 性能标准

### 最低性能要求

| 组件 | 最低性能 | 目标性能 |
|------|----------|----------|
| **async_fn 创建** | 10亿 ops/秒 | 30亿+ ops/秒 |
| **await_fn 执行** | 10亿 ops/秒 | 30亿+ ops/秒 |
| **任务调度** | 1000万 ops/秒 | 1亿+ ops/秒 |
| **内存分配** | 100万 ops/秒 | 1000万+ ops/秒 |

### 性能测试

1. **基准测试每个更改**
   ```bash
   # 在进行更改前运行
   zig build bench > before.txt
   
   # 进行您的更改
   
   # 在进行更改后运行
   zig build bench > after.txt
   
   # 比较结果
   diff before.txt after.txt
   ```

2. **性能回归预防**
   - 所有 PR 必须包含性能影响分析
   - 没有正当理由不允许 >5% 的回归
   - 性能改进应该被记录

## 🔄 贡献流程

### 1. Issue 创建

- **Bug 报告**：使用 bug 报告模板
- **功能请求**：使用功能请求模板
- **性能问题**：包含基准测试数据

### 2. Pull Request 流程

1. **创建功能分支**
   ```bash
   git checkout -b feature/async-combinators
   ```

2. **进行更改**
   - 遵循编码标准
   - 添加全面测试
   - 更新文档

3. **彻底测试**
   ```bash
   zig build test
   zig build bench
   zig build test-all-platforms
   ```

4. **提交 Pull Request**
   - 清楚描述更改
   - 性能影响分析
   - 链接到相关 issue

### 3. 审查流程

- **代码审查**：至少需要 2 个批准
- **性能审查**：基准测试验证
- **文档审查**：确保文档已更新
- **跨平台测试**：CI 验证

## 🌐 文档贡献

### 文档标准

1. **双语支持**
   - 英文文档是必需的
   - 中文翻译非常有价值
   - 欢迎其他语言

2. **代码示例**
   - 所有示例必须可运行
   - 包含性能期望
   - 显示基本和高级用法

3. **API 文档**
   - 完整的函数文档
   - 性能特征
   - 使用示例
   - 错误条件

### 文档结构

```
docs/
├── en/                 # 英文文档
│   ├── getting-started.md
│   ├── api-reference.md
│   ├── examples.md
│   └── performance.md
├── zh/                 # 中文文档
│   ├── getting-started.md
│   ├── api-reference.md
│   ├── examples.md
│   └── performance.md
└── PROJECT_OVERVIEW.md
```

## 🤝 社区指南

### 行为准则

- **尊重他人**：尊重对待所有贡献者
- **建设性**：提供有用的反馈
- **包容性**：欢迎所有背景的贡献者
- **耐心**：帮助新手学习和贡献

### 沟通渠道

- **GitHub Issues**：Bug 报告和功能请求
- **GitHub Discussions**：一般问题和想法
- **Pull Requests**：代码贡献和审查

## 🏆 认可

### 贡献者认可

- **贡献者列表**：所有贡献者在 README 中被认可
- **发布说明**：重要贡献在发布说明中突出显示
- **社区聚光灯**：杰出贡献者被特别介绍

### 贡献类型

- **代码贡献**：新功能、bug 修复、优化
- **文档**：指南、示例、翻译
- **测试**：测试用例、基准测试、质量保证
- **社区**：帮助他人、issue 分类、讨论

## 📈 获取帮助

### 资源

- **[快速开始指南](getting-started.md)**：基本设置和使用
- **[API 参考](api-reference.md)**：完整的 API 文档
- **[示例](examples.md)**：实用代码示例
- **[架构指南](architecture.md)**：内部设计细节

### 支持

- **GitHub Issues**：技术问题和 bug 报告
- **GitHub Discussions**：一般问题和头脑风暴
- **代码审查**：Pull Request 的详细反馈

---

**感谢您为 Zokio 贡献！我们一起在构建异步编程的未来。** 🚀
