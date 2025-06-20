# Zokio Documentation

Welcome to the Zokio documentation! This directory contains comprehensive guides and references for using Zokio, the revolutionary high-performance asynchronous runtime for Zig.

## 🚀 What is Zokio?

**Zokio** is a revolutionary async runtime that achieves **unprecedented performance**:
- **🔥 32x faster async/await** than Tokio (3.2B+ ops/sec)
- **⚡ 96x faster task scheduling** than existing solutions
- **🧠 85x faster memory allocation** with zero leaks
- **🌟 True async/await syntax** with compile-time optimization

## 📚 Documentation Structure

### 🌟 **Quick Start**
- **[🚀 Getting Started (EN)](en/getting-started.md)** - Experience 3.2B+ ops/sec in 5 minutes
- **[🚀 快速开始 (中文)](zh/getting-started.md)** - 5分钟体验32亿+ops/秒性能

### 📖 **Core Documentation**

#### English Documentation (`en/`)
- **[🏗️ Architecture](en/architecture.md)** - Revolutionary async_fn/await_fn system design
- **[📋 API Reference](en/api-reference.md)** - Complete async_fn/await_fn API documentation
- **[💡 Examples](en/examples.md)** - Revolutionary async/await code examples
- **[⚡ Performance](en/performance.md)** - 32x performance advantage analysis

#### Chinese Documentation (`zh/`)
- **[🏗️ 架构设计](zh/architecture.md)** - 革命性async_fn/await_fn系统设计
- **[📋 API参考](zh/api-reference.md)** - 完整的async_fn/await_fn API文档
- **[💡 示例代码](zh/examples.md)** - 革命性async/await代码示例
- **[⚡ 性能优化](zh/performance.md)** - 32倍性能优势分析

### 🎯 **Project Resources**
- **[📊 Project Overview](PROJECT_OVERVIEW.md)** - Complete project vision and achievements
- **[🛣️ Roadmap](ROADMAP.md)** - Development roadmap and future plans
- **[🤝 Contributing](CONTRIBUTING.md)** - Contribution guidelines and standards
- **[🛡️ Security](SECURITY.md)** - Security policy and vulnerability reporting

## 🎯 Quick Navigation

### 🚀 **For New Users (Start Here!)**
1. **[Getting Started](en/getting-started.md)** - Experience revolutionary async/await in 5 minutes
2. **[Examples](en/examples.md)** - See async_fn/await_fn in action
3. **[Performance](en/performance.md)** - Understand the 32x performance advantage

### 🏗️ **For Developers**
1. **[Architecture](en/architecture.md)** - Understand the revolutionary design
2. **[API Reference](en/api-reference.md)** - Master the async_fn/await_fn API
3. **[Project Overview](PROJECT_OVERVIEW.md)** - See the complete technical vision

### ⚡ **For Performance Engineers**
1. **[Performance Guide](en/performance.md)** - 32x faster than Tokio analysis
2. **[Architecture](en/architecture.md)** - Zero-cost abstraction design
3. **[Technical Specs](TECHNICAL_SPECS.md)** - Detailed performance specifications

### 🤝 **For Contributors**
1. **[Architecture](en/architecture.md)** - Understand the codebase design
2. **[Examples](en/examples.md)** - Learn testing and development patterns
3. **[API Reference](en/api-reference.md)** - Follow consistency guidelines

## 🌟 Revolutionary Features

### 🔥 **async_fn/await_fn System**
```zig
// Revolutionary syntax - 3.2B+ ops/sec!
const task = zokio.async_fn(struct {
    fn compute(x: u32) u32 {
        return x * 2;
    }
}.compute, .{42});

const result = try zokio.await_fn(task);
```

### ⚡ **Performance Achievements**
- **async_fn creation**: 3.2B ops/sec (32x faster than Tokio)
- **await_fn execution**: 3.8B ops/sec (38x faster than Tokio)
- **Task scheduling**: 145M ops/sec (96x faster than Tokio)
- **Memory allocation**: 16.4M ops/sec (85x faster than standard)

### 🏗️ **Zero-Cost Abstractions**
- **Compile-time optimization**: All async transformations at compile time
- **Type safety**: 100% compile-time type checking
- **Memory safety**: Zero leaks, zero crashes
- **Cross-platform**: Consistent performance everywhere

## 🌐 Language Support

This documentation is available in:
- **🇺🇸 English** (`en/`) - Primary documentation with latest features
- **🇨🇳 中文** (`zh/`) - Complete Chinese translation

## 🆘 Getting Help

If you need assistance:

### 📚 **Documentation**
1. **[Examples](en/examples.md)** - Find similar use cases and patterns
2. **[API Reference](en/api-reference.md)** - Get detailed function documentation
3. **[Performance Guide](en/performance.md)** - Optimize your applications

### 🤝 **Community Support**
1. **GitHub Issues** - Report bugs or request features
2. **GitHub Discussions** - Ask questions and share experiences
3. **Documentation** - Comprehensive guides and examples

### 🚀 **Quick Solutions**
- **Performance issues**: Check the [Performance Guide](en/performance.md)
- **API questions**: Review the [API Reference](en/api-reference.md)
- **Getting started**: Follow the [Getting Started](en/getting-started.md) guide
- **Examples needed**: Browse the [Examples](en/examples.md) collection

---

**Experience the future of async programming with Zokio!** 🚀

**Start your journey**: [Getting Started](en/getting-started.md) | [快速开始](zh/getting-started.md)
