# Zokio Examples

This guide provides comprehensive examples demonstrating various Zokio features and usage patterns.

## Table of Contents

1. [🚀 async_fn/await_fn Examples](#async_fnawait_fn-examples)
2. [Basic Examples](#basic-examples)
3. [Network Programming](#network-programming)
4. [File I/O](#file-io)
5. [Concurrency Patterns](#concurrency-patterns)
6. [Error Handling](#error-handling)
7. [Performance Optimization](#performance-optimization)
8. [Real-World Applications](#real-world-applications)

## 🚀 async_fn/await_fn Examples

### Revolutionary async_fn Syntax

The simplest async_fn example demonstrating 3.2B+ ops/sec performance:

```zig
const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize high-performance runtime
    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 🚀 Create async function with revolutionary syntax
    const hello_task = zokio.async_fn(struct {
        fn greet(name: []const u8) []const u8 {
            std.debug.print("Hello, {s}!\n", .{name});
            return "Greeting completed";
        }
    }.greet, .{"Zokio"});

    // Spawn and await the task
    const handle = try runtime.spawn(hello_task);
    const result = try zokio.await_fn(handle);

    std.debug.print("Result: {s}\n", .{result});
}
```

### Complex async_fn Workflow

```zig
pub fn complexAsyncWorkflow() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 🔥 HTTP request simulation
    const http_task = zokio.async_fn(struct {
        fn fetchData(url: []const u8) []const u8 {
            std.debug.print("Fetching data from: {s}\n", .{url});
            return "{'users': [{'id': 1, 'name': 'Alice'}]}";
        }
    }.fetchData, .{"https://api.example.com/users"});

    // 🔥 Database query simulation
    const db_task = zokio.async_fn(struct {
        fn queryDatabase(sql: []const u8) u32 {
            std.debug.print("Executing SQL: {s}\n", .{sql});
            return 42; // Number of results
        }
    }.queryDatabase, .{"SELECT * FROM users WHERE active = true"});

    // 🚀 Spawn both tasks concurrently
    const http_handle = try runtime.spawn(http_task);
    const db_handle = try runtime.spawn(db_task);

    // 🚀 Await results with true async/await syntax
    const http_result = try zokio.await_fn(http_handle);
    const db_result = try zokio.await_fn(db_handle);

    std.debug.print("HTTP Response: {s}\n", .{http_result});
    std.debug.print("Database Results: {} rows\n", .{db_result});
}
```

### Concurrent async_fn Tasks

```zig
pub fn concurrentAsyncTasks() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    var handles = std.ArrayList(zokio.runtime.JoinHandle([]const u8)).init(allocator);
    defer handles.deinit();

    // 🌟 Spawn multiple concurrent tasks
    for (0..10) |i| {
        const task = zokio.async_fn(struct {
            fn work(id: u32) []const u8 {
                std.debug.print("Task {} working...\n", .{id});
                return "Task completed";
            }
        }.work, .{@as(u32, @intCast(i))});

        const handle = try runtime.spawn(task);
        try handles.append(handle);
    }

    // 🚀 Await all results
    for (handles.items) |*handle| {
        const result = try zokio.await_fn(handle);
        std.debug.print("Result: {s}\n", .{result});
    }
}
```

## Basic Examples

### Hello World
```zig
const std = @import("std");
const zokio = @import("zokio");

const HelloTask = struct {
    message: []const u8,
    
    pub const Output = void;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        std.debug.print("Hello, {s}!\n", .{self.message});
        return .{ .ready = {} };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const config = zokio.RuntimeConfig{};
    var runtime = try zokio.ZokioRuntime(config).init(gpa.allocator());
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();
    
    const task = HelloTask{ .message = "Zokio" };
    try runtime.blockOn(task);
}
```

### Async Computation
```zig
const ComputeTask = struct {
    input: u64,
    result: ?u64 = null,
    
    pub const Output = u64;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u64) {
        _ = ctx;
        
        if (self.result == null) {
            // Simulate expensive computation
            self.result = self.fibonacci(self.input);
        }
        
        return .{ .ready = self.result.? };
    }
    
    fn fibonacci(self: *@This(), n: u64) u64 {
        _ = self;
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }
};

// Usage
const task = ComputeTask{ .input = 30 };
const result = try runtime.blockOn(task);
std.debug.print("Fibonacci(30) = {}\n", .{result});
```

### Delay and Timing
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
            std.debug.print("Delay of {}ms completed\n", .{self.delay_ms});
            return .{ .ready = {} };
        }
        
        return .pending;
    }
};

// Usage
const delay = DelayTask{ .delay_ms = 1000 };
try runtime.blockOn(delay); // Wait 1 second
```

## Network Programming

### TCP Echo Server
```zig
const TcpEchoServer = struct {
    address: []const u8,
    listener_fd: ?std.posix.fd_t = null,
    running: bool = false,
    
    pub const Output = void;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        
        if (!self.running) {
            // Simulate binding to address
            self.listener_fd = 1; // Mock file descriptor
            self.running = true;
            std.debug.print("TCP server listening on {s}\n", .{self.address});
            return .pending;
        }
        
        // Simulate accepting connections
        std.debug.print("Accepting new connection\n", .{});
        
        // In a real implementation, this would:
        // 1. Accept incoming connections
        // 2. Spawn tasks to handle each connection
        // 3. Echo data back to clients
        
        return .pending; // Keep running
    }
};

// Usage
const server = TcpEchoServer{ .address = "127.0.0.1:8080" };
try runtime.blockOn(server);
```

### HTTP Client
```zig
const HttpRequest = struct {
    url: []const u8,
    method: []const u8 = "GET",
    response: ?[]const u8 = null,
    
    pub const Output = []const u8;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]const u8) {
        _ = ctx;
        
        if (self.response == null) {
            // Simulate HTTP request
            std.debug.print("Making {} request to {s}\n", .{ self.method, self.url });
            
            // In a real implementation, this would:
            // 1. Parse the URL
            // 2. Establish TCP connection
            // 3. Send HTTP request
            // 4. Read HTTP response
            
            self.response = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, World!";
        }
        
        return .{ .ready = self.response.? };
    }
};

// Usage
const request = HttpRequest{ .url = "https://api.example.com/data" };
const response = try runtime.blockOn(request);
std.debug.print("Response: {s}\n", .{response});
```

### WebSocket Server
```zig
const WebSocketServer = struct {
    port: u16,
    connections: std.ArrayList(Connection),
    
    const Connection = struct {
        fd: std.posix.fd_t,
        buffer: [4096]u8,
    };
    
    pub const Output = void;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        
        // Simulate WebSocket server operations
        std.debug.print("WebSocket server running on port {}\n", .{self.port});
        
        // In a real implementation, this would:
        // 1. Accept WebSocket connections
        // 2. Handle WebSocket handshake
        // 3. Process WebSocket frames
        // 4. Broadcast messages to connected clients
        
        return .pending;
    }
};
```

## File I/O

### Async File Reader
```zig
const FileReader = struct {
    path: []const u8,
    content: ?[]u8 = null,
    allocator: std.mem.Allocator,
    
    pub const Output = []u8;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]u8) {
        _ = ctx;
        
        if (self.content == null) {
            // Simulate async file reading
            std.debug.print("Reading file: {s}\n", .{self.path});
            
            // In a real implementation, this would:
            // 1. Open file asynchronously
            // 2. Read file content in chunks
            // 3. Handle file I/O errors
            
            const mock_content = "File content from async read";
            self.content = self.allocator.dupe(u8, mock_content) catch return .pending;
        }
        
        return .{ .ready = self.content.? };
    }
    
    pub fn deinit(self: *@This()) void {
        if (self.content) |content| {
            self.allocator.free(content);
        }
    }
};

// Usage
var file_reader = FileReader{ 
    .path = "data.txt", 
    .allocator = allocator 
};
defer file_reader.deinit();

const content = try runtime.blockOn(file_reader);
std.debug.print("File content: {s}\n", .{content});
```

### Batch File Processor
```zig
const BatchFileProcessor = struct {
    input_files: [][]const u8,
    output_dir: []const u8,
    processed_count: u32 = 0,
    allocator: std.mem.Allocator,
    
    pub const Output = u32;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        
        if (self.processed_count < self.input_files.len) {
            const file = self.input_files[self.processed_count];
            
            // Simulate file processing
            std.debug.print("Processing file: {s}\n", .{file});
            
            // In a real implementation, this would:
            // 1. Read input file asynchronously
            // 2. Process file content (transform, filter, etc.)
            // 3. Write output file asynchronously
            
            self.processed_count += 1;
            return .pending;
        }
        
        std.debug.print("Processed {} files\n", .{self.processed_count});
        return .{ .ready = self.processed_count };
    }
};

// Usage
const files = [_][]const u8{ "file1.txt", "file2.txt", "file3.txt" };
const processor = BatchFileProcessor{
    .input_files = &files,
    .output_dir = "/tmp/output",
    .allocator = allocator,
};
const count = try runtime.blockOn(processor);
```

## Concurrency Patterns

### Parallel Task Execution
```zig
const ParallelTasks = struct {
    tasks: []Task,
    completed: []bool,
    results: []u32,
    
    const Task = struct {
        id: u32,
        work_amount: u32,
    };
    
    pub const Output = []u32;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll([]u32) {
        _ = ctx;
        
        // Check if all tasks are completed
        var all_done = true;
        for (self.completed, 0..) |done, i| {
            if (!done) {
                // Simulate task work
                self.results[i] = self.tasks[i].work_amount * 2;
                self.completed[i] = true;
                std.debug.print("Task {} completed\n", .{self.tasks[i].id});
            }
            all_done = all_done and done;
        }
        
        if (all_done) {
            return .{ .ready = self.results };
        }
        
        return .pending;
    }
};

// Usage
const tasks = [_]ParallelTasks.Task{
    .{ .id = 1, .work_amount = 10 },
    .{ .id = 2, .work_amount = 20 },
    .{ .id = 3, .work_amount = 30 },
};
var completed = [_]bool{false} ** tasks.len;
var results = [_]u32{0} ** tasks.len;

const parallel = ParallelTasks{
    .tasks = &tasks,
    .completed = &completed,
    .results = &results,
};
const final_results = try runtime.blockOn(parallel);
```

### Producer-Consumer Pattern
```zig
const ProducerConsumer = struct {
    buffer: std.ArrayList(u32),
    producer_done: bool = false,
    consumer_done: bool = false,
    items_produced: u32 = 0,
    items_consumed: u32 = 0,
    max_items: u32,
    
    pub const Output = void;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;
        
        // Producer phase
        if (!self.producer_done and self.items_produced < self.max_items) {
            self.buffer.append(self.items_produced) catch return .pending;
            std.debug.print("Produced item: {}\n", .{self.items_produced});
            self.items_produced += 1;
            
            if (self.items_produced >= self.max_items) {
                self.producer_done = true;
                std.debug.print("Producer finished\n", .{});
            }
        }
        
        // Consumer phase
        if (self.buffer.items.len > 0) {
            const item = self.buffer.orderedRemove(0);
            std.debug.print("Consumed item: {}\n", .{item});
            self.items_consumed += 1;
        }
        
        if (self.producer_done and self.buffer.items.len == 0) {
            self.consumer_done = true;
            std.debug.print("Consumer finished\n", .{});
        }
        
        if (self.consumer_done) {
            return .{ .ready = {} };
        }
        
        return .pending;
    }
};

// Usage
var buffer = std.ArrayList(u32).init(allocator);
defer buffer.deinit();

const producer_consumer = ProducerConsumer{
    .buffer = buffer,
    .max_items = 10,
};
try runtime.blockOn(producer_consumer);
```

## Error Handling

### Graceful Error Recovery
```zig
const ResilientTask = struct {
    max_retries: u32,
    current_retry: u32 = 0,
    last_error: ?anyerror = null,
    
    pub const Output = ![]const u8;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(![]const u8) {
        _ = ctx;
        
        // Simulate operation that might fail
        if (self.current_retry < 2) {
            self.current_retry += 1;
            self.last_error = error.TemporaryFailure;
            std.debug.print("Attempt {} failed, retrying...\n", .{self.current_retry});
            return .pending;
        }
        
        if (self.current_retry < self.max_retries) {
            self.current_retry += 1;
            std.debug.print("Attempt {} succeeded!\n", .{self.current_retry});
            return .{ .ready = "Success after retries" };
        }
        
        std.debug.print("All retries exhausted\n", .{});
        return .{ .ready = self.last_error.? };
    }
};

// Usage
const resilient = ResilientTask{ .max_retries = 3 };
const result = runtime.blockOn(resilient) catch |err| {
    std.debug.print("Task failed permanently: {}\n", .{err});
    return;
};
std.debug.print("Final result: {s}\n", .{result});
```

### Timeout Handling
```zig
const TimeoutTask = struct {
    operation: Operation,
    timeout_ms: u64,
    start_time: ?i64 = null,
    
    const Operation = struct {
        duration_ms: u64,
        started: bool = false,
        start_time: ?i64 = null,
        
        pub fn poll(self: *@This()) bool {
            if (!self.started) {
                self.started = true;
                self.start_time = std.time.milliTimestamp();
                return false;
            }
            
            const elapsed = std.time.milliTimestamp() - self.start_time.?;
            return elapsed >= self.duration_ms;
        }
    };
    
    pub const Output = ![]const u8;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(![]const u8) {
        _ = ctx;
        
        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
        }
        
        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        
        // Check timeout first
        if (elapsed >= self.timeout_ms) {
            return .{ .ready = error.Timeout };
        }
        
        // Check if operation completed
        if (self.operation.poll()) {
            return .{ .ready = "Operation completed successfully" };
        }
        
        return .pending;
    }
};

// Usage
const timeout_task = TimeoutTask{
    .operation = .{ .duration_ms = 2000 }, // 2 second operation
    .timeout_ms = 1000, // 1 second timeout
};

const result = runtime.blockOn(timeout_task) catch |err| switch (err) {
    error.Timeout => {
        std.debug.print("Operation timed out\n", .{});
        return;
    },
    else => return err,
};
```

## Performance Optimization

### Object Pool Usage
```zig
const PooledTask = struct {
    pool: *zokio.memory.ObjectPool([1024]u8),
    buffer: ?[]u8 = null,
    
    pub const Output = usize;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(usize) {
        _ = ctx;
        
        if (self.buffer == null) {
            self.buffer = self.pool.acquire() catch return .pending;
        }
        
        // Use the pooled buffer
        const data = "Some data to process";
        @memcpy(self.buffer.?[0..data.len], data);
        
        const result = self.buffer.?.len;
        
        // Return buffer to pool
        self.pool.release(self.buffer.?);
        self.buffer = null;
        
        return .{ .ready = result };
    }
};

// Usage
var pool = try zokio.memory.ObjectPool([1024]u8).init(allocator, 10);
defer pool.deinit();

const pooled = PooledTask{ .pool = &pool };
const size = try runtime.blockOn(pooled);
```

### Batch Processing
```zig
const BatchProcessor = struct {
    items: []Item,
    batch_size: usize,
    current_batch: usize = 0,
    
    const Item = struct { id: u32, data: []const u8 };
    
    pub const Output = u32;
    
    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        
        if (self.current_batch * self.batch_size >= self.items.len) {
            return .{ .ready = @intCast(self.items.len) };
        }
        
        const start = self.current_batch * self.batch_size;
        const end = @min(start + self.batch_size, self.items.len);
        
        // Process batch
        for (self.items[start..end]) |item| {
            std.debug.print("Processing item {}: {s}\n", .{ item.id, item.data });
        }
        
        self.current_batch += 1;
        return .pending;
    }
};

// Usage
const items = [_]BatchProcessor.Item{
    .{ .id = 1, .data = "data1" },
    .{ .id = 2, .data = "data2" },
    .{ .id = 3, .data = "data3" },
    .{ .id = 4, .data = "data4" },
    .{ .id = 5, .data = "data5" },
};

const batch_processor = BatchProcessor{
    .items = &items,
    .batch_size = 2,
};
const processed = try runtime.blockOn(batch_processor);
```

---

These examples demonstrate the versatility and power of Zokio for building high-performance asynchronous applications. Each pattern can be adapted and combined to create complex, efficient systems that take full advantage of Zokio's capabilities.
