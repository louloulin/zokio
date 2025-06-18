# Getting Started with Zokio

This guide will help you get up and running with Zokio, the high-performance asynchronous runtime for Zig.

## Prerequisites

Before you begin, ensure you have:

- **Zig 0.14.0 or later**: Download from [ziglang.org](https://ziglang.org/download/)
- **Supported Platform**: Linux, macOS, Windows, or BSD
- **Basic Zig Knowledge**: Familiarity with Zig syntax and concepts

## Installation

### Method 1: Using Zig Package Manager (Recommended)

Add Zokio to your `build.zig.zon`:

```zig
.{
    .name = "my-zokio-project",
    .version = "0.1.0",
    .dependencies = .{
        .zokio = .{
            .url = "https://github.com/louloulin/zokio/archive/main.tar.gz",
            .hash = "1234567890abcdef...", // Replace with actual hash
        },
    },
}
```

Update your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add Zokio dependency
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

    // Link Zokio
    exe.root_module.addImport("zokio", zokio_dep.module("zokio"));

    b.installArtifact(exe);
}
```

### Method 2: Git Submodule

```bash
git submodule add https://github.com/louloulin/zokio.git deps/zokio
```

Then in your `build.zig`:

```zig
const zokio = b.addModule("zokio", .{
    .root_source_file = b.path("deps/zokio/src/lib.zig"),
});
exe.root_module.addImport("zokio", zokio);
```

## Your First Zokio Application

Create `src/main.zig`:

```zig
const std = @import("std");
const zokio = @import("zokio");

// Define a simple async task
const HelloTask = struct {
    name: []const u8,
    
    // Required: Define the output type
    pub const Output = void;
    
    // Required: Implement the poll method
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx; // Context not used in this simple example
        
        std.debug.print("Hello from async task: {s}!\n", .{self.name});
        
        // Return ready with the result
        return .{ .ready = {} };
    }
};

pub fn main() !void {
    // Set up memory allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Configure the runtime
    const config = zokio.RuntimeConfig{
        .worker_threads = 4,              // Use 4 worker threads
        .enable_work_stealing = true,     // Enable work stealing for load balancing
        .enable_io_uring = true,          // Use io_uring on Linux (if available)
        .enable_metrics = true,           // Enable performance metrics
        .enable_numa = true,              // Enable NUMA optimizations
    };

    // Create the runtime instance
    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    // Print runtime information
    std.debug.print("Zokio Runtime Started!\n", .{});
    std.debug.print("Platform: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.platform});
    std.debug.print("Architecture: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.architecture});
    std.debug.print("Worker Threads: {}\n", .{RuntimeType.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("I/O Backend: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.io_backend});

    // Start the runtime
    try runtime.start();
    defer runtime.stop();

    // Create and execute an async task
    const task = HelloTask{ .name = "Zokio" };
    try runtime.blockOn(task);
    
    std.debug.print("Task completed successfully!\n", .{});
}
```

## Build and Run

```bash
# Build the application
zig build

# Run the application
./zig-out/bin/my-app
```

Expected output:
```
Zokio Runtime Started!
Platform: darwin
Architecture: aarch64
Worker Threads: 4
I/O Backend: kqueue
Hello from async task: Zokio!
Task completed successfully!
```

## Understanding the Basics

### Runtime Configuration

The `RuntimeConfig` struct allows you to customize the runtime behavior:

```zig
const config = zokio.RuntimeConfig{
    // Number of worker threads (null = auto-detect CPU cores)
    .worker_threads = null,
    
    // Enable work-stealing scheduler for load balancing
    .enable_work_stealing = true,
    
    // Platform-specific I/O optimizations
    .enable_io_uring = true,    // Linux: io_uring
    .enable_kqueue = true,      // macOS/BSD: kqueue
    .enable_iocp = true,        // Windows: IOCP
    
    // Memory optimizations
    .enable_numa = true,        // NUMA-aware allocation
    .enable_simd = true,        // SIMD optimizations
    .memory_strategy = .adaptive, // Adaptive memory management
    
    // Debugging and monitoring
    .enable_metrics = true,     // Performance metrics
    .enable_tracing = false,    // Distributed tracing
    .check_async_context = true, // Async context validation
};
```

### Task Implementation

Every async task must implement:

1. **Output type**: Define what the task returns
2. **poll method**: The core async logic

```zig
const MyTask = struct {
    data: SomeData,
    
    // Required: Output type
    pub const Output = ResultType;
    
    // Required: Poll method
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(ResultType) {
        // Your async logic here
        
        if (task_is_ready) {
            return .{ .ready = result };
        } else {
            // Task is not ready, will be polled again later
            return .pending;
        }
    }
};
```

### Runtime Operations

```zig
// Create runtime
var runtime = try zokio.ZokioRuntime(config).init(allocator);
defer runtime.deinit();

// Start runtime (spawns worker threads)
try runtime.start();
defer runtime.stop();

// Execute a task and wait for completion
const result = try runtime.blockOn(task);

// Spawn a task to run concurrently (returns immediately)
const handle = try runtime.spawn(task);
const result = try handle.join(); // Wait for completion
```

## Next Steps

Now that you have a basic Zokio application running, explore:

1. **[Architecture Guide](architecture.md)**: Understand how Zokio works internally
2. **[API Reference](api-reference.md)**: Complete API documentation
3. **[Examples](examples.md)**: More complex examples and patterns
4. **[Performance Guide](performance.md)**: Optimization techniques

## Common Patterns

### Error Handling

```zig
const ErrorTask = struct {
    pub const Output = !u32; // Task can return an error
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(!u32) {
        _ = ctx;
        _ = self;
        
        if (some_error_condition) {
            return .{ .ready = error.SomeError };
        }
        
        return .{ .ready = 42 };
    }
};

// Handle errors when executing
const result = runtime.blockOn(ErrorTask{}) catch |err| {
    std.debug.print("Task failed: {}\n", .{err});
    return;
};
```

### Async Delays

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

// Use the delay task
const delay = DelayTask{ .delay_ms = 1000 }; // 1 second delay
try runtime.blockOn(delay);
```

## Troubleshooting

### Common Issues

1. **Compilation Errors**: Ensure you're using Zig 0.14.0 or later
2. **Platform Support**: Check that your platform is supported
3. **Memory Issues**: Use a proper allocator and check for leaks
4. **Performance**: Enable optimizations with `-O ReleaseFast`

### Debug Mode

Enable debug features for development:

```zig
const config = zokio.RuntimeConfig{
    .enable_metrics = true,
    .enable_tracing = true,
    .check_async_context = true,
};
```

### Getting Help

- Check the [examples](examples.md) for similar use cases
- Review the [API reference](api-reference.md) for detailed documentation
- Open an issue on GitHub for bugs or feature requests

---

You're now ready to build high-performance async applications with Zokio! 🚀
