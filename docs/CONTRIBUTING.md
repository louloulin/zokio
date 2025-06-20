# Contributing to Zokio

Thank you for your interest in contributing to Zokio! This document provides guidelines and information for contributors.

## 🎯 Project Vision

Zokio aims to be the **fastest, safest, and most developer-friendly async runtime** in existence. Every contribution should align with our core principles:

- **🚀 Performance First**: Maintain revolutionary performance advantages
- **🛡️ Safety**: Zero-cost abstractions with compile-time guarantees
- **💡 Developer Experience**: Intuitive APIs and excellent documentation
- **🌐 Cross-Platform**: Consistent behavior across all platforms

## 🚀 Getting Started

### Prerequisites

- **Zig 0.14.0+**: Download from [ziglang.org](https://ziglang.org/download/)
- **Git**: For version control
- **Basic understanding of async programming**
- **Familiarity with Zig language**

### Development Setup

1. **Fork and Clone**
   ```bash
   git clone https://github.com/yourusername/zokio.git
   cd zokio
   ```

2. **Build and Test**
   ```bash
   zig build
   zig build test
   ```

3. **Run Benchmarks**
   ```bash
   zig build bench
   ```

## 📋 Contribution Areas

### 🔥 High Priority Areas

1. **async_fn/await_fn Enhancements**
   - Advanced async combinators
   - Error handling improvements
   - Performance optimizations

2. **Runtime Core Improvements**
   - Scheduler optimizations
   - Memory management enhancements
   - I/O driver improvements

3. **Documentation and Examples**
   - API documentation
   - Tutorial content
   - Real-world examples

### 🌟 Medium Priority Areas

1. **Ecosystem Development**
   - Network protocol implementations
   - Database drivers
   - Utility libraries

2. **Developer Tools**
   - IDE integration
   - Debugging tools
   - Profiling utilities

3. **Testing and Quality Assurance**
   - Test coverage improvements
   - Benchmark development
   - Cross-platform testing

## 🛠️ Development Guidelines

### Code Style

1. **Follow Zig Conventions**
   ```zig
   // ✅ Good: Clear, descriptive names
   const AsyncTask = struct {
       pub fn poll(self: *@This(), ctx: *Context) Poll(T) {
           // Implementation
       }
   };
   
   // ❌ Avoid: Unclear abbreviations
   const AT = struct {
       pub fn p(s: *@This(), c: *Ctx) P(T) {
           // Implementation
       }
   };
   ```

2. **Performance-Conscious Code**
   ```zig
   // ✅ Good: Zero-cost abstractions
   pub fn async_fn(comptime func: anytype, args: anytype) AsyncFnWrapper(func, args) {
       return AsyncFnWrapper(func, args).init(args);
   }
   
   // ❌ Avoid: Runtime overhead
   pub fn async_fn_slow(func: *const fn() void) RuntimeWrapper {
       return RuntimeWrapper{ .func = func };
   }
   ```

3. **Documentation Standards**
   ```zig
   /// Creates an async function wrapper with compile-time optimization.
   /// 
   /// This function transforms any regular function into an async task
   /// that can be executed by the Zokio runtime with revolutionary performance.
   /// 
   /// Performance: 3.2B+ operations per second
   /// 
   /// Example:
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

### Testing Requirements

1. **Unit Tests**
   ```zig
   test "async_fn basic functionality" {
       const task = zokio.async_fn(struct {
           fn add(a: u32, b: u32) u32 {
               return a + b;
           }
       }.add, .{10, 20});
       
       // Test implementation
       try std.testing.expect(task.result == 30);
   }
   ```

2. **Performance Tests**
   ```zig
   test "async_fn performance benchmark" {
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
       
       // Should achieve >1B ops/sec
       try std.testing.expect(ops_per_sec > 1_000_000_000);
   }
   ```

3. **Integration Tests**
   ```zig
   test "full async workflow" {
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

## 📊 Performance Standards

### Minimum Performance Requirements

| Component | Minimum Performance | Target Performance |
|-----------|-------------------|-------------------|
| **async_fn creation** | 1B ops/sec | 3B+ ops/sec |
| **await_fn execution** | 1B ops/sec | 3B+ ops/sec |
| **Task scheduling** | 10M ops/sec | 100M+ ops/sec |
| **Memory allocation** | 1M ops/sec | 10M+ ops/sec |

### Performance Testing

1. **Benchmark Every Change**
   ```bash
   # Run before making changes
   zig build bench > before.txt
   
   # Make your changes
   
   # Run after making changes
   zig build bench > after.txt
   
   # Compare results
   diff before.txt after.txt
   ```

2. **Performance Regression Prevention**
   - All PRs must include performance impact analysis
   - No regressions >5% without justification
   - Performance improvements should be documented

## 🔄 Contribution Process

### 1. Issue Creation

- **Bug Reports**: Use the bug report template
- **Feature Requests**: Use the feature request template
- **Performance Issues**: Include benchmark data

### 2. Pull Request Process

1. **Create Feature Branch**
   ```bash
   git checkout -b feature/async-combinators
   ```

2. **Make Changes**
   - Follow coding standards
   - Add comprehensive tests
   - Update documentation

3. **Test Thoroughly**
   ```bash
   zig build test
   zig build bench
   zig build test-all-platforms
   ```

4. **Submit Pull Request**
   - Clear description of changes
   - Performance impact analysis
   - Link to related issues

### 3. Review Process

- **Code Review**: At least 2 approvals required
- **Performance Review**: Benchmark validation
- **Documentation Review**: Ensure docs are updated
- **Cross-Platform Testing**: CI validation

## 🌐 Documentation Contributions

### Documentation Standards

1. **Bilingual Support**
   - English documentation is required
   - Chinese translations are highly valued
   - Other languages welcome

2. **Code Examples**
   - All examples must be runnable
   - Include performance expectations
   - Show both basic and advanced usage

3. **API Documentation**
   - Complete function documentation
   - Performance characteristics
   - Usage examples
   - Error conditions

### Documentation Structure

```
docs/
├── en/                 # English documentation
│   ├── getting-started.md
│   ├── api-reference.md
│   ├── examples.md
│   └── performance.md
├── zh/                 # Chinese documentation
│   ├── getting-started.md
│   ├── api-reference.md
│   ├── examples.md
│   └── performance.md
└── PROJECT_OVERVIEW.md
```

## 🤝 Community Guidelines

### Code of Conduct

- **Be Respectful**: Treat all contributors with respect
- **Be Constructive**: Provide helpful feedback
- **Be Inclusive**: Welcome contributors of all backgrounds
- **Be Patient**: Help newcomers learn and contribute

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: General questions and ideas
- **Pull Requests**: Code contributions and reviews

## 🏆 Recognition

### Contributor Recognition

- **Contributors List**: All contributors are recognized in README
- **Release Notes**: Significant contributions highlighted
- **Community Spotlight**: Outstanding contributors featured

### Contribution Types

- **Code Contributions**: New features, bug fixes, optimizations
- **Documentation**: Guides, examples, translations
- **Testing**: Test cases, benchmarks, quality assurance
- **Community**: Helping others, issue triage, discussions

## 📈 Getting Help

### Resources

- **[Getting Started Guide](en/getting-started.md)**: Basic setup and usage
- **[API Reference](en/api-reference.md)**: Complete API documentation
- **[Examples](en/examples.md)**: Practical code examples
- **[Architecture Guide](en/architecture.md)**: Internal design details

### Support

- **GitHub Issues**: Technical questions and bug reports
- **GitHub Discussions**: General questions and brainstorming
- **Code Review**: Detailed feedback on pull requests

---

**Thank you for contributing to Zokio! Together, we're building the future of asynchronous programming.** 🚀
