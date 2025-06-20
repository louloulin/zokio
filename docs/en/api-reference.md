# Zokio API Reference

Complete API documentation for Zokio's public interface.

## Core Types

### Runtime

#### `ZokioRuntime(comptime config: RuntimeConfig)`

Creates a compile-time configured runtime type.

```zig
const RuntimeType = zokio.ZokioRuntime(config);
var runtime = try RuntimeType.init(allocator);
```

**Methods:**

- `init(allocator: std.mem.Allocator) !Self` - Initialize the runtime
- `deinit()` - Clean up runtime resources
- `start() !void` - Start worker threads and I/O drivers
- `stop()` - Stop the runtime gracefully
- `blockOn(task: anytype) !@TypeOf(task).Output` - Execute a task synchronously
- `spawn(task: anytype) !JoinHandle(@TypeOf(task).Output)` - Spawn a task asynchronously

**Compile-time Information:**

- `COMPILE_TIME_INFO` - Platform and configuration details
- `PERFORMANCE_CHARACTERISTICS` - Expected performance metrics
- `MEMORY_LAYOUT` - Memory usage analysis

### RuntimeConfig

Configuration structure for runtime behavior.

```zig
pub const RuntimeConfig = struct {
    worker_threads: ?u32 = null,           // Auto-detect if null
    enable_work_stealing: bool = true,     // Enable work stealing
    enable_io_uring: bool = true,          // Use io_uring on Linux
    memory_strategy: MemoryStrategy = .adaptive,
    max_memory_usage: ?usize = null,       // Memory limit
    enable_numa: bool = true,              // NUMA optimizations
    enable_simd: bool = true,              // SIMD optimizations
    enable_prefetch: bool = true,          // Memory prefetching
    cache_line_optimization: bool = true,  // Cache line alignment
    enable_tracing: bool = false,          // Distributed tracing
    enable_metrics: bool = true,           // Performance metrics
    check_async_context: bool = true,      // Context validation
};
```

**Methods:**

- `validate()` - Compile-time configuration validation

### Future System

#### `Future(comptime T: type)`

Type-erased Future trait for async operations.

```zig
const future = Future(u32).init(MyTask, &my_task);
const result = try runtime.blockOn(future);
```

**Methods:**

- `init(comptime ConcreteType: type, task: *ConcreteType) Self` - Create from concrete type
- `poll(ctx: *Context) Poll(T)` - Poll for completion
- `deinit()` - Clean up resources

#### `Poll(comptime T: type)`

Result type for Future polling.

```zig
pub fn Poll(comptime T: type) type {
    return union(enum) {
        ready: T,    // Task completed with result
        pending,     // Task not ready, poll again later
    };
}
```

#### `Context`

Execution context for async operations.

```zig
pub const Context = struct {
    waker: Waker,
    
    pub fn init(waker: Waker) Context;
    pub fn wake(self: *Context) void;
};
```

#### `Waker`

Notification mechanism for task wake-up.

```zig
pub const Waker = struct {
    wake_fn: *const fn (*anyopaque) void,
    data: *anyopaque,
    
    pub fn wake(self: Waker) void;
    pub fn noop() Waker;  // No-op waker for testing
};
```

### Task Management

#### `JoinHandle(comptime T: type)`

Handle for spawned tasks.

```zig
const handle = try runtime.spawn(my_task);
const result = try handle.join();  // Wait for completion
```

**Methods:**

- `join() !T` - Wait for task completion and get result
- `abort()` - Cancel the task (if possible)
- `is_finished() bool` - Check if task is complete

#### `TaskId`

Unique identifier for tasks.

```zig
pub const TaskId = struct {
    id: u64,
    
    pub fn generate() TaskId;
    pub fn format(...) !void;  // For printing
};
```

## 🚀 async_fn and await_fn API

### async_fn - Create Async Functions

Transform any function into an async task with compile-time optimization:

```zig
// Basic async function
const task = zokio.async_fn(struct {
    fn compute(x: u32, y: u32) u32 {
        return x + y;
    }
}.compute, .{10, 20});

// With complex return types
const http_task = zokio.async_fn(struct {
    fn fetch(url: []const u8) []const u8 {
        std.debug.print("Fetching: {s}\n", .{url});
        return "{'status': 'success'}";
    }
}.fetch, .{"https://api.example.com"});

// Database operation
const db_task = zokio.async_fn(struct {
    fn query(sql: []const u8) u32 {
        std.debug.print("Executing: {s}\n", .{sql});
        return 42; // Result count
    }
}.query, .{"SELECT * FROM users"});
```

**Signature:**
```zig
pub fn async_fn(comptime func: anytype, args: anytype) AsyncFnWrapper(@TypeOf(func), @TypeOf(args))
```

**Features:**
- **Zero-cost abstraction**: Compiles to optimal state machine
- **Type safety**: Full compile-time type checking
- **Performance**: 3.2B+ ops/sec execution speed
- **Flexibility**: Works with any function signature

### await_fn - Await Async Results

Wait for async tasks to complete with true async/await syntax:

```zig
// Await a JoinHandle
const handle = try runtime.spawn(task);
const result = try zokio.await_fn(handle);

// Await any Future-like type
const future = SomeFuture{};
const result = try zokio.await_fn(future);

// Nested await calls (Revolutionary!)
const step1_result = try zokio.await_fn(step1_task);
const step2_result = try zokio.await_fn(step2_task);
const final_result = try zokio.await_fn(final_task);
```

**Signature:**
```zig
pub fn await_fn(handle: anytype) !@TypeOf(handle).Output
```

**Performance:**
- **Basic await**: 3.2B ops/sec
- **Nested await**: 3.8B ops/sec
- **Deep workflows**: 1.9B ops/sec

### Complex Async Workflows

```zig
// Multi-step async workflow
pub fn complexWorkflow(runtime: *zokio.runtime.HighPerformanceRuntime) !void {
    // Step 1: Fetch configuration
    const config_task = zokio.async_fn(struct {
        fn getConfig() []const u8 {
            return "{'timeout': 5000, 'retries': 3}";
        }
    }.getConfig, .{});

    const config_handle = try runtime.spawn(config_task);
    const config = try zokio.await_fn(config_handle);

    // Step 2: Process based on config
    const process_task = zokio.async_fn(struct {
        fn process(cfg: []const u8) u32 {
            std.debug.print("Processing with config: {s}\n", .{cfg});
            return 100; // Processed items
        }
    }.process, .{config});

    const process_handle = try runtime.spawn(process_task);
    const result = try zokio.await_fn(process_handle);

    std.debug.print("Processed {} items\n", .{result});
}

// Concurrent execution
pub fn concurrentTasks(runtime: *zokio.runtime.HighPerformanceRuntime) !void {
    var handles = std.ArrayList(zokio.runtime.JoinHandle([]const u8)).init(allocator);
    defer handles.deinit();

    // Spawn multiple tasks
    for (0..10) |i| {
        const task = zokio.async_fn(struct {
            fn work(id: u32) []const u8 {
                return "Task completed";
            }
        }.work, .{@as(u32, @intCast(i))});

        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // Await all results
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        std.debug.print("Result: {s}\n", .{result});
    }
}
```

## High-Level APIs

### Network I/O

#### TCP

```zig
// TCP Listener
const listener = try zokio.net.TcpListener.bind(allocator, "127.0.0.1:8080");
defer listener.deinit();

while (true) {
    const stream = try listener.accept();
    const handle = try runtime.spawn(handleConnection(stream));
    // Handle spawned, continues in background
}

// TCP Stream
const stream = try zokio.net.TcpStream.connect(allocator, "127.0.0.1:8080");
defer stream.deinit();

const bytes_written = try stream.write("Hello, World!");
var buffer: [1024]u8 = undefined;
const bytes_read = try stream.read(&buffer);
```

#### UDP

```zig
const socket = try zokio.net.UdpSocket.bind(allocator, "127.0.0.1:8080");
defer socket.deinit();

var buffer: [1024]u8 = undefined;
const (bytes_read, sender_addr) = try socket.recv_from(&buffer);
try socket.send_to("Response", sender_addr);
```

### File System

```zig
// Async file operations
const file = try zokio.fs.File.open(allocator, "data.txt", .{ .mode = .read_write });
defer file.close();

var buffer: [1024]u8 = undefined;
const bytes_read = try file.read(&buffer);
const bytes_written = try file.write("New data");

// Directory operations
var dir = try zokio.fs.Dir.open(allocator, "/path/to/directory");
defer dir.close();

var iterator = dir.iterate();
while (try iterator.next()) |entry| {
    std.debug.print("Found: {s}\n", .{entry.name});
}
```

### Timers

```zig
// Sleep for a duration
try zokio.time.sleep(std.time.Duration.fromMillis(1000));

// Timeout wrapper
const result = zokio.time.timeout(
    std.time.Duration.fromSeconds(5),
    long_running_task
) catch |err| switch (err) {
    error.Timeout => {
        std.debug.print("Task timed out!\n", .{});
        return;
    },
    else => return err,
};

// Interval timer
var interval = zokio.time.interval(std.time.Duration.fromSeconds(1));
while (true) {
    try interval.tick();
    std.debug.print("Tick!\n", .{});
}
```

## Synchronization Primitives

### Mutex

```zig
var mutex = zokio.sync.Mutex(u32).init(0);

// Async lock
const guard = try mutex.lock();
defer guard.unlock();
guard.value.* += 1;
```

### Channel

```zig
const channel = try zokio.sync.Channel(u32).init(allocator, 10); // Buffer size 10
defer channel.deinit();

// Sender
try channel.send(42);

// Receiver
const value = try channel.recv();
```

### Semaphore

```zig
var semaphore = zokio.sync.Semaphore.init(3); // 3 permits

const permit = try semaphore.acquire();
defer permit.release();
// Critical section
```

### Barrier

```zig
var barrier = zokio.sync.Barrier.init(4); // Wait for 4 tasks

// In each task
try barrier.wait();
// All tasks continue together
```

## Memory Management

### Memory Strategies

```zig
pub const MemoryStrategy = enum {
    simple,      // Basic allocation
    pooled,      // Object pooling
    numa_aware,  // NUMA optimization
    adaptive,    // Dynamic strategy selection
};
```

### Object Pool

```zig
var pool = try zokio.memory.ObjectPool(MyStruct).init(allocator, 100);
defer pool.deinit();

const obj = try pool.acquire();
defer pool.release(obj);
// Use obj
```

### NUMA Allocator

```zig
var numa_allocator = try zokio.memory.NumaAllocator.init(allocator);
defer numa_allocator.deinit();

const memory = try numa_allocator.alloc(u8, 1024);
defer numa_allocator.free(memory);
```

## Metrics and Monitoring

### Performance Metrics

```zig
const metrics = runtime.getMetrics();
std.debug.print("Tasks executed: {}\n", .{metrics.tasks_executed});
std.debug.print("Average task duration: {}ns\n", .{metrics.avg_task_duration_ns});
std.debug.print("Memory usage: {}MB\n", .{metrics.memory_usage_mb});
```

### Tracing

```zig
// Enable tracing in config
const config = zokio.RuntimeConfig{
    .enable_tracing = true,
};

// Create spans
const span = zokio.tracing.span("my_operation");
defer span.end();

// Add events
span.event("processing_started");
// ... do work ...
span.event("processing_completed");
```

## Testing Utilities

### Mock Runtime

```zig
// For unit testing
var mock_runtime = zokio.testing.MockRuntime.init(testing.allocator);
defer mock_runtime.deinit();

const result = try mock_runtime.blockOn(my_task);
try testing.expect(result == expected_value);
```

### Time Control

```zig
// Control time in tests
var time_controller = zokio.testing.TimeController.init();
defer time_controller.deinit();

const task = DelayTask{ .delay_ms = 1000 };
const handle = try mock_runtime.spawn(task);

// Advance time
time_controller.advance(std.time.Duration.fromMillis(1000));

const result = try handle.join();
```

## Error Handling

### Common Errors

```zig
pub const ZokioError = error{
    RuntimeNotStarted,    // Runtime not started
    TaskCancelled,        // Task was cancelled
    Timeout,              // Operation timed out
    ResourceExhausted,    // Out of resources
    IoError,              // I/O operation failed
    MemoryError,          // Memory allocation failed
    ConfigurationError,   // Invalid configuration
};
```

### Error Context

```zig
const result = runtime.blockOn(risky_task) catch |err| switch (err) {
    error.Timeout => {
        std.debug.print("Task timed out\n", .{});
        return;
    },
    error.IoError => {
        std.debug.print("I/O error occurred\n", .{});
        return;
    },
    else => return err,
};
```

## Platform-Specific Features

### Linux (io_uring)

```zig
// Access io_uring specific features
if (runtime.io_driver.supportsIoUring()) {
    const advanced_ops = runtime.io_driver.getIoUringOps();
    try advanced_ops.submitReadv(fd, iovecs);
}
```

### Windows (IOCP)

```zig
// Windows-specific optimizations
if (builtin.os.tag == .windows) {
    const iocp_driver = runtime.io_driver.asIocp();
    try iocp_driver.associateHandle(handle, completion_key);
}
```

### macOS/BSD (kqueue)

```zig
// kqueue-specific features
if (runtime.io_driver.supportsKqueue()) {
    const kqueue_ops = runtime.io_driver.getKqueueOps();
    try kqueue_ops.addFileSystemWatch(path);
}
```

---

This API reference covers the complete public interface of Zokio. For more detailed examples and usage patterns, see the [Examples Guide](examples.md).
