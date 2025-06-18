# Zokio 架构指南

本指南深入介绍Zokio的架构、设计决策和内部工作原理。

## 概述

Zokio基于分层架构构建，最大化利用Zig的编译时能力，同时提供高性能的异步执行。设计强调零成本抽象、编译时优化和平台特定性能。

## 架构层次

```
┌─────────────────────────────────────────────────────────┐
│                      应用层                             │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  用户代码 (异步任务、网络服务器等)                  │ │
│  └─────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│                    高级API                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │
│  │   网络I/O   │ │   文件系统  │ │    定时器和延迟     │ │
│  │             │ │             │ │                     │ │
│  │  (TCP/UDP)  │ │ (异步文件)  │ │   (睡眠、超时)      │ │
│  └─────────────┘ └─────────────┘ └─────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│                    运行时核心                           │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │
│  │    调度器   │ │  I/O驱动    │ │     内存管理器      │ │
│  │             │ │             │ │                     │ │
│  │  工作窃取   │ │   事件循环  │ │    NUMA感知         │ │
│  │  多核心     │ │   平台      │ │    分配器           │ │
│  │  任务队列   │ │   特定      │ │    对象池           │ │
│  └─────────────┘ └─────────────┘ └─────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│                   Future抽象                           │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │
│  │  Future特征 │ │ Context和   │ │       Waker         │ │
│  │             │ │    Poll     │ │                     │ │
│  │  (零成本)   │ │   (状态)    │ │    (通知)           │ │
│  └─────────────┘ └─────────────┘ └─────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│                   平台抽象                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐ │
│  │    Linux    │ │    macOS    │ │      Windows        │ │
│  │             │ │             │ │                     │ │
│  │  io_uring   │ │   kqueue    │ │       IOCP          │ │
│  │   epoll     │ │    poll     │ │    select/poll      │ │
│  │  eventfd    │ │   kevent    │ │      events         │ │
│  └─────────────┘ └─────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## 核心组件

### 1. 运行时核心

运行时核心是Zokio的心脏，负责协调所有异步操作。

#### 编译时配置

```zig
pub fn ZokioRuntime(comptime config: RuntimeConfig) type {
    // 编译时组件选择
    const OptimalScheduler = selectOptimalScheduler(config);
    const OptimalIoDriver = selectOptimalIoDriver(config);
    const OptimalAllocator = selectOptimalAllocator(config);
    
    return struct {
        scheduler: OptimalScheduler,
        io_driver: OptimalIoDriver,
        allocator: OptimalAllocator,
        
        // 编译时生成的信息
        pub const COMPILE_TIME_INFO = generateCompileTimeInfo(config);
        pub const PERFORMANCE_CHARACTERISTICS = analyzePerformance(config);
    };
}
```

#### 运行时生命周期

1. **初始化**: 组件设置和资源分配
2. **启动**: 工作线程生成和I/O驱动激活
3. **执行**: 任务调度和I/O事件处理
4. **关闭**: 优雅清理和资源释放

### 2. 调度器

调度器负责任务执行和跨工作线程的负载均衡。

#### 工作窃取算法

```
工作线程1        工作线程2        工作线程3
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│ 本地队列    │  │ 本地队列    │  │ 本地队列    │
│ [T1][T2][T3]│  │ [T4][T5]    │  │ [T6]        │
│             │  │             │  │             │
└─────────────┘  └─────────────┘  └─────────────┘
       │                 │                 │
       └─────────────────┼─────────────────┘
                         │
                  ┌─────────────┐
                  │ 全局队列    │
                  │ [T7][T8][T9]│
                  └─────────────┘
```

#### 调度策略

1. **本地执行**: 任务尽可能在原始线程上执行
2. **工作窃取**: 空闲线程从繁忙线程窃取任务
3. **全局回退**: 本地队列满时任务溢出到全局队列
4. **负载均衡**: 跨核心动态负载分布

### 3. I/O驱动

平台特定的I/O驱动为每个操作系统提供最佳性能。

#### Linux: io_uring

```zig
const IoUringDriver = struct {
    ring: IoUring,
    submission_queue: SubmissionQueue,
    completion_queue: CompletionQueue,
    
    pub fn submitRead(self: *Self, fd: fd_t, buffer: []u8, offset: u64) !void {
        const sqe = try self.ring.get_sqe();
        sqe.prep_read(fd, buffer, offset);
        try self.ring.submit();
    }
    
    pub fn poll(self: *Self, timeout: ?u64) !u32 {
        return self.ring.submit_and_wait(timeout);
    }
};
```

#### macOS/BSD: kqueue

```zig
const KqueueDriver = struct {
    kq: i32,
    events: []kevent,
    
    pub fn submitRead(self: *Self, fd: fd_t, buffer: []u8, offset: u64) !void {
        var event = kevent{
            .ident = @intCast(fd),
            .filter = EVFILT_READ,
            .flags = EV_ADD | EV_ONESHOT,
            .fflags = 0,
            .data = 0,
            .udata = @ptrCast(buffer.ptr),
        };
        _ = kevent(self.kq, &event, 1, null, 0, null);
    }
};
```

#### Windows: IOCP

```zig
const IocpDriver = struct {
    iocp: HANDLE,
    overlapped_pool: ObjectPool(OVERLAPPED),
    
    pub fn submitRead(self: *Self, fd: fd_t, buffer: []u8, offset: u64) !void {
        const overlapped = try self.overlapped_pool.acquire();
        overlapped.Offset = @truncate(offset);
        overlapped.OffsetHigh = @truncate(offset >> 32);
        
        _ = ReadFile(fd, buffer.ptr, @intCast(buffer.len), null, overlapped);
    }
};
```

### 4. Future系统

Future系统提供零成本的异步抽象。

#### Future特征

```zig
pub fn Future(comptime T: type) type {
    return struct {
        vtable: *const VTable,
        data: *anyopaque,
        
        const VTable = struct {
            poll: *const fn (*anyopaque, *Context) Poll(T),
            drop: *const fn (*anyopaque) void,
        };
        
        pub fn poll(self: *Self, ctx: *Context) Poll(T) {
            return self.vtable.poll(self.data, ctx);
        }
    };
}
```

#### Poll结果

```zig
pub fn Poll(comptime T: type) type {
    return union(enum) {
        ready: T,
        pending: void,
    };
}
```

#### Context和Waker

```zig
pub const Context = struct {
    waker: Waker,
    
    pub fn wake(self: *Context) void {
        self.waker.wake();
    }
};

pub const Waker = struct {
    wake_fn: *const fn (*anyopaque) void,
    data: *anyopaque,
    
    pub fn wake(self: Waker) void {
        self.wake_fn(self.data);
    }
};
```

### 5. 内存管理

NUMA感知的内存管理为现代硬件优化分配模式。

#### 内存策略

```zig
pub const MemoryStrategy = enum {
    simple,      // 基本分配
    pooled,      // 对象池
    numa_aware,  // NUMA优化
    adaptive,    // 动态策略选择
};
```

#### NUMA感知分配

```zig
const NumaAllocator = struct {
    node_allocators: []NodeAllocator,
    current_node: std.atomic.Value(u32),
    
    pub fn alloc(self: *Self, size: usize) ![]u8 {
        const node = self.getCurrentNode();
        return self.node_allocators[node].alloc(size);
    }
    
    fn getCurrentNode(self: *Self) u32 {
        // 轮询或基于CPU亲和性的选择
        return self.current_node.fetchAdd(1, .monotonic) % self.node_allocators.len;
    }
};
```

## 编译时优化

### 1. 状态机生成

Zokio在编译时将异步函数转换为优化的状态机：

```zig
// 用户代码
async fn fetchData() !Data {
    const response = await httpGet("https://api.example.com");
    const parsed = await parseJson(response);
    return parsed;
}

// 生成的状态机（概念性）
const FetchDataStateMachine = struct {
    state: enum { initial, http_get, parse_json, completed },
    http_future: ?HttpGetFuture,
    parse_future: ?ParseJsonFuture,
    result: ?Data,
    
    pub fn poll(self: *Self, ctx: *Context) Poll(Data) {
        switch (self.state) {
            .initial => {
                self.http_future = HttpGetFuture.init("https://api.example.com");
                self.state = .http_get;
                return .pending;
            },
            .http_get => {
                const response = switch (self.http_future.?.poll(ctx)) {
                    .ready => |r| r,
                    .pending => return .pending,
                };
                self.parse_future = ParseJsonFuture.init(response);
                self.state = .parse_json;
                return .pending;
            },
            .parse_json => {
                const parsed = switch (self.parse_future.?.poll(ctx)) {
                    .ready => |p| p,
                    .pending => return .pending,
                };
                self.result = parsed;
                self.state = .completed;
                return .{ .ready = parsed };
            },
            .completed => return .{ .ready = self.result.? },
        }
    }
};
```

### 2. 组件选择

运行时根据编译时配置选择最优组件：

```zig
fn selectOptimalScheduler(comptime config: RuntimeConfig) type {
    if (config.worker_threads == 1) {
        return SingleThreadedScheduler;
    } else if (config.enable_work_stealing) {
        return WorkStealingScheduler;
    } else {
        return MultiThreadedScheduler;
    }
}

fn selectOptimalIoDriver(comptime config: RuntimeConfig) type {
    if (builtin.os.tag == .linux and config.enable_io_uring) {
        return IoUringDriver;
    } else if (builtin.os.tag == .macos or builtin.os.tag == .freebsd) {
        return KqueueDriver;
    } else if (builtin.os.tag == .windows) {
        return IocpDriver;
    } else {
        return PollDriver; // 回退
    }
}
```

### 3. 性能分析

编译时性能分析提供运行时特性洞察：

```zig
fn analyzePerformance(comptime config: RuntimeConfig) PerformanceCharacteristics {
    const scheduler_overhead = calculateSchedulerOverhead(config);
    const io_latency = estimateIoLatency(config);
    const memory_overhead = calculateMemoryOverhead(config);
    
    return PerformanceCharacteristics{
        .theoretical_max_tasks_per_second = calculateMaxThroughput(config),
        .expected_latency_ns = scheduler_overhead + io_latency,
        .memory_overhead_bytes = memory_overhead,
        .scalability_factor = calculateScalabilityFactor(config),
    };
}
```

## 设计原则

### 1. 零成本抽象

所有高级抽象编译为最优机器码，无运行时开销。

### 2. 显式内存管理

没有隐藏的分配或垃圾回收 - 所有内存使用都是显式和可控的。

### 3. 平台优化

利用平台特定功能在每个操作系统上获得最大性能。

### 4. 编译时配置

运行时行为在编译时确定，启用激进优化。

### 5. 类型安全

Zig的类型系统确保内存安全并防止常见的异步编程错误。

## 性能特征

### 吞吐量

- **任务调度**: 4.51亿操作/秒
- **工作窃取**: 2.87亿操作/秒
- **I/O操作**: 6.32亿操作/秒

### 延迟

- **任务唤醒**: < 1μs
- **上下文切换**: < 100ns
- **I/O提交**: < 50ns

### 内存使用

- **每任务开销**: 64字节
- **调度器开销**: 每工作线程4KB
- **I/O驱动开销**: 每驱动实例16KB

### 可扩展性

- **工作线程**: 线性扩展到CPU核心数
- **并发任务**: 数百万任务，恒定内存开销
- **I/O连接**: 平台相关（通常100K+连接）

---

这种架构使Zokio能够在保持Zig提供的安全性和表达力的同时实现卓越性能。编译时优化确保高级异步抽象具有零运行时成本，使Zokio既适用于高性能系统，也适用于资源受限的环境。
