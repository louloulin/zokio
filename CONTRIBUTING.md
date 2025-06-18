# Contributing to Zokio

Thank you for your interest in contributing to Zokio! This document provides guidelines and information for contributors.

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Setup](#development-setup)
4. [Contributing Guidelines](#contributing-guidelines)
5. [Pull Request Process](#pull-request-process)
6. [Testing](#testing)
7. [Documentation](#documentation)
8. [Performance Considerations](#performance-considerations)

## Code of Conduct

We are committed to providing a welcoming and inclusive environment for all contributors. Please be respectful and constructive in all interactions.

### Our Standards

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

### Prerequisites

- Zig 0.14.0 or later
- Git
- Basic understanding of async programming concepts
- Familiarity with Zig language features

### Areas for Contribution

We welcome contributions in the following areas:

1. **Core Runtime**: Scheduler improvements, I/O driver optimizations
2. **Platform Support**: New platform backends, platform-specific optimizations
3. **Documentation**: API docs, tutorials, examples
4. **Testing**: Unit tests, integration tests, benchmarks
5. **Examples**: Real-world usage examples and tutorials
6. **Performance**: Optimizations and performance analysis
7. **Bug Fixes**: Issue resolution and stability improvements

## Development Setup

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
# Then clone your fork
git clone https://github.com/your-username/zokio.git
cd zokio

# Add upstream remote
git remote add upstream https://github.com/original-org/zokio.git
```

### 2. Build and Test

```bash
# Build the project
zig build

# Run tests
zig build test-all

# Run benchmarks
zig build benchmark

# Run examples
zig build example-hello_world
```

### 3. Development Workflow

```bash
# Create a feature branch
git checkout -b feature/your-feature-name

# Make your changes
# ...

# Run tests and formatting
zig build test-all
zig build fmt

# Commit your changes
git add .
git commit -m "feat: add your feature description"

# Push to your fork
git push origin feature/your-feature-name
```

## Contributing Guidelines

### Code Style

We follow Zig's standard formatting and naming conventions:

```bash
# Format code before committing
zig build fmt
```

#### Naming Conventions

- **Types**: PascalCase (`RuntimeConfig`, `Future`)
- **Functions**: camelCase (`blockOn`, `submitRead`)
- **Variables**: snake_case (`worker_threads`, `io_driver`)
- **Constants**: SCREAMING_SNAKE_CASE (`COMPILE_TIME_INFO`)

#### Code Organization

- Keep functions focused and small
- Use meaningful variable and function names
- Add comments for complex logic
- Follow the existing module structure

### Commit Messages

Use conventional commit format:

```
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `perf`: Performance improvements
- `chore`: Maintenance tasks

Examples:
```
feat(scheduler): add work-stealing queue implementation
fix(io): resolve memory leak in io_uring driver
docs(api): update Future trait documentation
test(runtime): add integration tests for runtime lifecycle
perf(memory): optimize NUMA-aware allocator
```

### Documentation

- Update documentation for any API changes
- Add examples for new features
- Include performance implications
- Write clear, concise explanations

### Testing Requirements

All contributions must include appropriate tests:

1. **Unit Tests**: Test individual components
2. **Integration Tests**: Test component interactions
3. **Performance Tests**: Verify performance characteristics
4. **Platform Tests**: Test platform-specific features

## Pull Request Process

### 1. Before Submitting

- [ ] Code builds without warnings
- [ ] All tests pass
- [ ] Code is formatted (`zig build fmt`)
- [ ] Documentation is updated
- [ ] Performance impact is considered
- [ ] Breaking changes are documented

### 2. Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update
- [ ] Performance improvement

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing performed

## Performance Impact
Describe any performance implications

## Breaking Changes
List any breaking changes

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
```

### 3. Review Process

1. Automated checks must pass
2. At least one maintainer review required
3. Address review feedback
4. Maintain clean commit history
5. Squash commits if requested

## Testing

### Running Tests

```bash
# Run all tests
zig build test-all

# Run specific test suites
zig build test              # Unit tests
zig build test-integration  # Integration tests
zig build benchmark         # Performance tests
```

### Writing Tests

#### Unit Tests

```zig
test "scheduler task execution" {
    const testing = std.testing;
    
    var scheduler = Scheduler.init();
    defer scheduler.deinit();
    
    const task = TestTask{ .value = 42 };
    try scheduler.schedule(task);
    
    const result = try scheduler.run_once();
    try testing.expect(result == 42);
}
```

#### Integration Tests

```zig
test "runtime end-to-end" {
    const testing = std.testing;
    
    const config = RuntimeConfig{
        .worker_threads = 1,
        .enable_metrics = false,
    };
    
    var runtime = try ZokioRuntime(config).init(testing.allocator);
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();
    
    const task = SimpleTask{};
    const result = try runtime.blockOn(task);
    try testing.expect(result == expected_value);
}
```

#### Benchmark Tests

```zig
test "scheduler performance" {
    const iterations = 1_000_000;
    const start = std.time.nanoTimestamp();
    
    for (0..iterations) |_| {
        // Benchmark code
    }
    
    const end = std.time.nanoTimestamp();
    const duration_ns = end - start;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / 
                       (@as(f64, @floatFromInt(duration_ns)) / 1e9);
    
    std.debug.print("Performance: {d:.0} ops/sec\n", .{ops_per_sec});
    
    // Assert minimum performance
    try std.testing.expect(ops_per_sec > 1_000_000);
}
```

## Documentation

### API Documentation

Use Zig's documentation comments:

```zig
/// Creates a new runtime with the specified configuration.
/// 
/// The runtime must be started with `start()` before use and
/// should be stopped with `stop()` for graceful shutdown.
///
/// # Arguments
/// * `allocator` - Memory allocator for runtime resources
///
/// # Returns
/// * `Self` - Initialized runtime instance
/// * `error.OutOfMemory` - If allocation fails
///
/// # Example
/// ```zig
/// var runtime = try ZokioRuntime(config).init(allocator);
/// defer runtime.deinit();
/// ```
pub fn init(allocator: std.mem.Allocator) !Self {
    // Implementation
}
```

### Examples

Provide complete, runnable examples:

```zig
//! Example: Basic async task execution
//!
//! This example demonstrates how to create and execute
//! a simple async task using Zokio.

const std = @import("std");
const zokio = @import("zokio");

// Example implementation...
```

## Performance Considerations

### Guidelines

1. **Measure First**: Profile before optimizing
2. **Avoid Allocations**: Minimize allocations in hot paths
3. **Cache Locality**: Consider memory access patterns
4. **Platform Features**: Leverage platform-specific optimizations
5. **Compile-time**: Prefer compile-time computation

### Performance Testing

```bash
# Run performance benchmarks
zig build benchmark

# Run stress tests
zig build stress-all

# Profile with specific tools
perf record zig build benchmark  # Linux
instruments -t "Time Profiler" zig build benchmark  # macOS
```

### Optimization Checklist

- [ ] Hot paths identified and optimized
- [ ] Memory allocations minimized
- [ ] Cache-friendly data structures used
- [ ] Platform-specific features leveraged
- [ ] Benchmark results documented

## Getting Help

### Communication Channels

- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and general discussion
- **Pull Requests**: Code review and collaboration

### Resources

- [Zig Documentation](https://ziglang.org/documentation/)
- [Zokio Documentation](docs/en/README.md)
- [Architecture Guide](docs/en/architecture.md)
- [Performance Guide](docs/en/performance.md)

## Recognition

Contributors will be recognized in:

- `CONTRIBUTORS.md` file
- Release notes for significant contributions
- Project documentation for major features

## License

By contributing to Zokio, you agree that your contributions will be licensed under the same license as the project (MIT License).

---

Thank you for contributing to Zokio! Your efforts help make high-performance async programming in Zig accessible to everyone. 🚀
