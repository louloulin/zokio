# Zokio基于libxev的完整异步I/O改造计划

## 🎯 **项目概述**

基于对libxev代码库的深度分析，制定Zokio完全基于libxev实现真正异步I/O的改造计划。libxev是一个跨平台、高性能的事件循环库，支持Linux(io_uring/epoll)、macOS(kqueue)、Windows(IOCP)和WebAssembly。

## 📊 **libxev核心功能分析**

### **🔥 libxev架构优势**
1. **跨平台统一API** - 支持Linux、macOS、Windows、WASI
2. **Proactor模式** - 工作完成通知，而非就绪通知
3. **零运行时分配** - 可预测的性能，适合嵌入式环境
4. **高级抽象** - TCP、UDP、文件、进程、定时器
5. **线程池支持** - 可选的通用线程池
6. **树摇优化** - Zig编译器只包含使用的功能

### **🚀 libxev核心组件**
```zig
// 核心事件循环
xev.Loop - 主事件循环
xev.Completion - 完成结构体
xev.CallbackAction - 回调动作

// 高级抽象
xev.TCP - TCP客户端和服务器
xev.UDP - UDP套接字
xev.Timer - 定时器
xev.File - 文件I/O
xev.Process - 进程管理
xev.Stream - 通用流接口
```

### **⚡ libxev I/O模式**
- **异步操作提交** - 提交I/O操作到事件循环
- **完成通知** - 操作完成时触发回调
- **非阻塞执行** - 事件循环处理多个并发操作
- **零拷贝优化** - 直接内存操作，减少拷贝

## 🔧 **Zokio集成libxev改造方案**

### **Phase 1: 核心事件循环重构 (1周)**

#### **1.1 替换AsyncEventLoop实现**
```zig
// 当前实现 (伪异步)
pub const AsyncEventLoop = struct {
    libxev_loop: libxev.Loop,  // 已有但未充分利用
    // ... 其他字段
};

// 🚀 新实现 (真正异步)
pub const AsyncEventLoop = struct {
    loop: xev.Loop,
    completions: std.ArrayList(xev.Completion),
    running: std.atomic.Value(bool),
    
    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .loop = try xev.Loop.init(.{}),
            .completions = std.ArrayList(xev.Completion).init(allocator),
            .running = std.atomic.Value(bool).init(false),
        };
    }
    
    pub fn run(self: *Self) !void {
        self.running.store(true, .release);
        try self.loop.run(.until_done);
    }
};
```

#### **1.2 重构await_fn集成libxev**
```zig
// 🚀 真正的libxev集成await_fn
pub fn await_fn(future: anytype) @TypeOf(future).Output {
    var ctx = getCurrentAsyncContext();
    
    while (true) {
        switch (future.poll(&ctx)) {
            .ready => |result| return result,
            .pending => {
                // 🔥 关键：将任务注册到libxev事件循环
                ctx.event_loop.registerFutureCompletion(future, ctx.waker);
                
                // 暂停当前任务，让libxev处理I/O事件
                suspendCurrentTask(&ctx);
            },
        }
    }
}
```

### **Phase 2: TCP/UDP网络I/O重构 (1.5周)**

#### **2.1 基于xev.TCP的真正异步TCP**
```zig
// 🚀 新的TCP实现 - 直接使用libxev
pub const TcpStream = struct {
    xev_tcp: xev.TCP,
    event_loop: *AsyncEventLoop,
    
    pub fn connect(allocator: std.mem.Allocator, addr: std.net.Address) !Self {
        var tcp = try xev.TCP.init(addr);
        var event_loop = getCurrentEventLoop();
        
        return Self{
            .xev_tcp = tcp,
            .event_loop = event_loop,
        };
    }
    
    pub fn read(self: *Self, buffer: []u8) ReadFuture {
        return ReadFuture{
            .tcp = &self.xev_tcp,
            .buffer = buffer,
            .event_loop = self.event_loop,
        };
    }
};

// 🚀 基于libxev的ReadFuture
pub const ReadFuture = struct {
    tcp: *xev.TCP,
    buffer: []u8,
    event_loop: *AsyncEventLoop,
    completion: ?xev.Completion = null,
    
    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!usize) {
        if (self.completion == null) {
            // 首次轮询：提交读取操作到libxev
            var c: xev.Completion = undefined;
            self.tcp.read(
                &self.event_loop.loop,
                &c,
                .{ .slice = self.buffer },
                *Self,
                self,
                readCallback,
            );
            self.completion = c;
            return .pending;
        }
        
        // 检查操作是否完成
        if (self.completion.?.state == .complete) {
            const result = self.completion.?.result.read;
            return .{ .ready = result };
        }
        
        return .pending;
    }
    
    fn readCallback(
        self: *Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        // 标记完成并唤醒等待的任务
        completion.state = .complete;
        completion.result = .{ .read = result };
        
        // 唤醒等待的Future
        if (self.waker) |waker| {
            waker.wake();
        }
        
        return .disarm;
    }
};
```

#### **2.2 TcpListener基于xev.TCP.accept**
```zig
pub const TcpListener = struct {
    xev_tcp: xev.TCP,
    event_loop: *AsyncEventLoop,
    
    pub fn accept(self: *Self) AcceptFuture {
        return AcceptFuture{
            .listener = &self.xev_tcp,
            .event_loop = self.event_loop,
        };
    }
};

pub const AcceptFuture = struct {
    listener: *xev.TCP,
    event_loop: *AsyncEventLoop,
    completion: ?xev.Completion = null,
    
    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!TcpStream) {
        if (self.completion == null) {
            var c: xev.Completion = undefined;
            self.listener.accept(
                &self.event_loop.loop,
                &c,
                *Self,
                self,
                acceptCallback,
            );
            self.completion = c;
            return .pending;
        }
        
        if (self.completion.?.state == .complete) {
            const result = self.completion.?.result.accept;
            if (result) |tcp| {
                return .{ .ready = TcpStream{
                    .xev_tcp = tcp,
                    .event_loop = self.event_loop,
                }};
            } else |err| {
                return .{ .ready = err };
            }
        }
        
        return .pending;
    }
    
    fn acceptCallback(
        self: *Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        completion.state = .complete;
        completion.result = .{ .accept = result };
        
        if (self.waker) |waker| {
            waker.wake();
        }
        
        return .disarm;
    }
};
```

### **Phase 3: 文件I/O和定时器 (1周)**

#### **3.1 基于xev.File的异步文件I/O**
```zig
pub const AsyncFile = struct {
    xev_file: xev.File,
    event_loop: *AsyncEventLoop,
    
    pub fn open(path: []const u8, flags: std.fs.File.OpenFlags) !Self {
        var file = try xev.File.init(path, flags);
        return Self{
            .xev_file = file,
            .event_loop = getCurrentEventLoop(),
        };
    }
    
    pub fn read(self: *Self, buffer: []u8, offset: u64) FileReadFuture {
        return FileReadFuture{
            .file = &self.xev_file,
            .buffer = buffer,
            .offset = offset,
            .event_loop = self.event_loop,
        };
    }
};
```

#### **3.2 基于xev.Timer的异步定时器**
```zig
pub const AsyncTimer = struct {
    xev_timer: xev.Timer,
    event_loop: *AsyncEventLoop,
    
    pub fn sleep(duration_ms: u64) TimerFuture {
        return TimerFuture{
            .duration_ms = duration_ms,
            .event_loop = getCurrentEventLoop(),
        };
    }
};

pub const TimerFuture = struct {
    duration_ms: u64,
    event_loop: *AsyncEventLoop,
    completion: ?xev.Completion = null,
    
    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!void) {
        if (self.completion == null) {
            const timer = try xev.Timer.init();
            var c: xev.Completion = undefined;
            timer.run(
                &self.event_loop.loop,
                &c,
                self.duration_ms,
                *Self,
                self,
                timerCallback,
            );
            self.completion = c;
            return .pending;
        }
        
        if (self.completion.?.state == .complete) {
            return .{ .ready = {} };
        }
        
        return .pending;
    }
    
    fn timerCallback(
        self: *Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Timer.RunError!void,
    ) xev.CallbackAction {
        completion.state = .complete;
        completion.result = .{ .timer = result };
        
        if (self.waker) |waker| {
            waker.wake();
        }
        
        return .disarm;
    }
};
```

## 🎯 **实施优先级和时间表**

### **Week 1: 核心事件循环**
- [ ] 重构AsyncEventLoop使用xev.Loop
- [ ] 修改await_fn集成libxev完成机制
- [ ] 更新Context和Waker系统

### **Week 2-3: 网络I/O**
- [ ] 重写TcpStream基于xev.TCP
- [ ] 重写TcpListener基于xev.TCP.accept
- [ ] 实现UDP支持基于xev.UDP
- [ ] 更新HTTP服务器示例

### **Week 4: 文件和定时器**
- [ ] 实现AsyncFile基于xev.File
- [ ] 实现AsyncTimer基于xev.Timer
- [ ] 添加进程管理基于xev.Process

## ✅ **验收标准**

### **功能验收**
- [ ] 所有I/O操作基于libxev实现
- [ ] HTTP服务器支持1000+并发连接
- [ ] 文件I/O完全异步化
- [ ] 定时器精确度<1ms

### **性能验收**
- [ ] 网络I/O吞吐量 >100K ops/sec
- [ ] 文件I/O吞吐量 >50K ops/sec
- [ ] 内存使用 <1KB per connection
- [ ] CPU使用率 <50% at 1K connections

### **兼容性验收**
- [ ] Linux (io_uring + epoll)
- [ ] macOS (kqueue)
- [ ] Windows (IOCP) - 未来支持
- [ ] WASI (poll_oneoff)

## 🔧 **技术实施细节**

### **libxev集成架构图**
```
┌─────────────────────────────────────────────────────────────┐
│                    Zokio应用层                              │
├─────────────────────────────────────────────────────────────┤
│  async_fn/await_fn  │  TcpStream  │  AsyncFile  │  Timer    │
├─────────────────────────────────────────────────────────────┤
│                  Zokio Future抽象层                         │
│  Future trait  │  Poll  │  Context  │  Waker               │
├─────────────────────────────────────────────────────────────┤
│                  libxev集成层                               │
│  AsyncEventLoop  │  CompletionManager  │  CallbackRouter   │
├─────────────────────────────────────────────────────────────┤
│                    libxev核心                               │
│  xev.Loop  │  xev.TCP  │  xev.File  │  xev.Timer          │
├─────────────────────────────────────────────────────────────┤
│                  操作系统层                                 │
│  io_uring  │  epoll  │  kqueue  │  IOCP  │  poll_oneoff   │
└─────────────────────────────────────────────────────────────┘
```

### **关键技术突破点**

#### **1. Completion到Future的桥接**
```zig
// 🚀 核心桥接机制：将libxev的Completion模式转换为Zokio的Future模式
pub const CompletionBridge = struct {
    completion: xev.Completion,
    waker: ?Waker = null,
    state: enum { pending, ready, error } = .pending,
    result: union(enum) {
        none: void,
        read: xev.ReadError!usize,
        write: xev.WriteError!usize,
        accept: xev.AcceptError!xev.TCP,
        timer: xev.Timer.RunError!void,
    } = .none,

    pub fn init() Self {
        return Self{
            .completion = .{},
        };
    }

    // 通用回调函数，处理所有类型的完成事件
    pub fn genericCallback(
        bridge: *Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Result,
    ) xev.CallbackAction {
        // 保存结果
        bridge.result = switch (result) {
            .read => |r| .{ .read = r },
            .write => |r| .{ .write = r },
            .accept => |r| .{ .accept = r },
            .timer => |r| .{ .timer = r },
            else => .none,
        };

        // 标记为就绪
        bridge.state = if (bridge.result == .none) .error else .ready;

        // 唤醒等待的Future
        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }
};
```

#### **2. 零拷贝I/O优化**
```zig
// 🚀 零拷贝读取实现
pub const ZeroCopyReadFuture = struct {
    tcp: *xev.TCP,
    buffer: xev.ReadBuffer,  // libxev的零拷贝缓冲区
    bridge: CompletionBridge,

    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror![]const u8) {
        switch (self.bridge.state) {
            .pending => {
                if (self.bridge.completion.state == .dead) {
                    // 首次提交读取操作
                    self.bridge.waker = ctx.waker;
                    self.tcp.read(
                        ctx.event_loop.loop,
                        &self.bridge.completion,
                        self.buffer,
                        *CompletionBridge,
                        &self.bridge,
                        CompletionBridge.genericCallback,
                    );
                }
                return .pending;
            },
            .ready => {
                if (self.bridge.result.read) |bytes_read| {
                    // 返回零拷贝的数据切片
                    return .{ .ready = self.buffer.slice[0..bytes_read] };
                } else |err| {
                    return .{ .ready = err };
                }
            },
            .error => return .{ .ready = error.IOError },
        }
    }
};
```

#### **3. 批量操作优化**
```zig
// 🚀 批量I/O操作支持
pub const BatchIOFuture = struct {
    operations: []IOOperation,
    completions: []CompletionBridge,
    completed_count: std.atomic.Value(usize),

    const IOOperation = union(enum) {
        read: struct { tcp: *xev.TCP, buffer: []u8 },
        write: struct { tcp: *xev.TCP, data: []const u8 },
        accept: struct { listener: *xev.TCP },
    };

    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror![]IOResult) {
        const total = self.operations.len;
        const completed = self.completed_count.load(.acquire);

        if (completed == 0) {
            // 首次轮询：提交所有操作
            for (self.operations, self.completions) |op, *bridge| {
                bridge.waker = ctx.waker;
                switch (op) {
                    .read => |r| r.tcp.read(
                        ctx.event_loop.loop,
                        &bridge.completion,
                        .{ .slice = r.buffer },
                        *CompletionBridge,
                        bridge,
                        CompletionBridge.genericCallback,
                    ),
                    .write => |w| w.tcp.write(
                        ctx.event_loop.loop,
                        &bridge.completion,
                        .{ .slice = w.data },
                        *CompletionBridge,
                        bridge,
                        CompletionBridge.genericCallback,
                    ),
                    .accept => |a| a.listener.accept(
                        ctx.event_loop.loop,
                        &bridge.completion,
                        *CompletionBridge,
                        bridge,
                        CompletionBridge.genericCallback,
                    ),
                }
            }
            return .pending;
        }

        if (completed == total) {
            // 所有操作完成，收集结果
            var results = std.ArrayList(IOResult).init(ctx.allocator);
            for (self.completions) |bridge| {
                results.append(IOResult.fromBridge(bridge)) catch {};
            }
            return .{ .ready = results.toOwnedSlice() };
        }

        return .pending;
    }
};
```

## 📈 **性能优化策略**

### **1. 内存池管理**
- **Completion池**: 预分配xev.Completion结构体
- **缓冲区池**: 复用读写缓冲区，减少分配
- **Future池**: 复用Future实例，避免频繁创建

### **2. 批量处理优化**
- **批量提交**: 一次提交多个I/O操作
- **批量完成**: 一次处理多个完成事件
- **批量唤醒**: 减少Waker调用次数

### **3. 零拷贝优化**
- **直接缓冲区**: 使用libxev的零拷贝缓冲区
- **内存映射**: 大文件使用mmap
- **Scatter/Gather I/O**: 支持向量化I/O

### **4. CPU亲和性优化**
- **NUMA感知**: 绑定线程到特定CPU核心
- **缓存局部性**: 优化数据结构布局
- **分支预测**: 减少条件分支

## 🧪 **测试验证计划**

### **单元测试**
```zig
test "libxev TCP read/write" {
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    var server = try xev.TCP.init(std.net.Address.parseIp4("127.0.0.1", 8080));
    try server.bind(std.net.Address.parseIp4("127.0.0.1", 8080));
    try server.listen(128);

    // 测试异步accept
    var accept_future = AcceptFuture{ .listener = &server };
    // ... 测试逻辑
}
```

### **集成测试**
- **HTTP服务器压力测试**: 1000并发连接
- **文件I/O性能测试**: 大文件读写
- **网络吞吐量测试**: TCP/UDP数据传输
- **内存泄漏测试**: 长时间运行验证

### **基准测试**
- **与Tokio对比**: 相同场景下的性能对比
- **与Node.js对比**: 事件循环性能对比
- **与Go对比**: 并发处理能力对比

---

**开始时间**: 立即开始
**预计完成**: 4周
**负责人**: Zokio开发团队
**优先级**: 最高 (P0)

## 🔍 **当前代码分析 - 需要改造的I/O操作清单**

### **🚨 高优先级改造项目**

#### **1. 网络I/O模块 (src/net/tcp.zig)**
```zig
// ❌ 当前实现：直接系统调用
std.posix.read(self.fd, self.buffer)           // Line 235
std.posix.write(self.fd, self.data)            // Line 310
std.posix.accept(self.listener_fd, &addr)      // Line 394

// ✅ 目标实现：libxev异步调用
xev_tcp.read(&loop, &completion, buffer, callback)
xev_tcp.write(&loop, &completion, data, callback)
xev_tcp.accept(&loop, &completion, callback)
```

#### **2. 文件I/O模块 (src/fs/file.zig, src/fs/async_fs.zig)**
```zig
// ❌ 当前实现：阻塞文件操作
std.posix.read(self.fd, buffer)                // file.zig:82
std.posix.write(self.fd, data)                 // file.zig:101
std.posix.pread(self.file.fd, buffer, offset)  // async_fs.zig:167
std.posix.pwrite(self.file.fd, data, offset)   // async_fs.zig:200

// ✅ 目标实现：libxev异步文件I/O
xev_file.read(&loop, &completion, buffer, offset, callback)
xev_file.write(&loop, &completion, data, offset, callback)
```

#### **3. 运行时阻塞调用 (src/runtime/runtime.zig)**
```zig
// ❌ 当前实现：阻塞sleep调用
std.Thread.yield() catch {};                   // Line 882
std.time.sleep(delay_ns);                      // 已修复但需验证
std.atomic.spinLoopHint();                     // 需要优化为事件驱动

// ✅ 目标实现：事件驱动等待
event_loop.runOnce() catch {};
completion_bridge.waitForCompletion();
```

### **📋 详细改造计划**

#### **Phase 1: 核心事件循环重构 (Week 1)**

**1.1 AsyncEventLoop完全重写**
- **文件**: `src/runtime/async_event_loop.zig`
- **当前问题**: 混合使用libxev和自定义实现
- **改造目标**: 100%基于xev.Loop实现
```zig
// 🚀 新的AsyncEventLoop架构
pub const AsyncEventLoop = struct {
    xev_loop: xev.Loop,
    completion_manager: CompletionManager,
    waker_registry: WakerRegistry,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .xev_loop = try xev.Loop.init(.{}),
            .completion_manager = CompletionManager.init(allocator),
            .waker_registry = WakerRegistry.init(allocator),
        };
    }

    pub fn run(self: *Self) !void {
        try self.xev_loop.run(.until_done);
    }

    pub fn runOnce(self: *Self) !void {
        try self.xev_loop.run(.no_wait);
    }
};
```

**1.2 Context和Waker系统重构**
- **文件**: `src/future/future.zig`
- **当前问题**: Waker类型不兼容
- **改造目标**: 统一Waker接口
```zig
// 🚀 统一的Waker接口
pub const Waker = struct {
    completion_bridge: *CompletionBridge,

    pub fn wake(self: *const Self) void {
        self.completion_bridge.notify();
    }
};

pub const Context = struct {
    waker: Waker,
    event_loop: ?*AsyncEventLoop,
    task_id: TaskId,
};
```

#### **Phase 2: 网络I/O完全重构 (Week 2)**

**2.1 TcpStream基于xev.TCP**
- **文件**: `src/net/tcp.zig`
- **改造范围**: 所有TCP操作
```zig
// 🚀 新的TcpStream实现
pub const TcpStream = struct {
    xev_tcp: xev.TCP,
    event_loop: *AsyncEventLoop,

    pub fn read(self: *Self, buffer: []u8) XevReadFuture {
        return XevReadFuture.init(&self.xev_tcp, buffer, self.event_loop);
    }

    pub fn write(self: *Self, data: []const u8) XevWriteFuture {
        return XevWriteFuture.init(&self.xev_tcp, data, self.event_loop);
    }
};

// 🚀 基于libxev的ReadFuture
pub const XevReadFuture = struct {
    xev_tcp: *xev.TCP,
    buffer: []u8,
    bridge: CompletionBridge,

    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!usize) {
        if (self.bridge.state == .pending) {
            // 提交读取操作到libxev
            self.xev_tcp.read(
                &ctx.event_loop.xev_loop,
                &self.bridge.completion,
                .{ .slice = self.buffer },
                *CompletionBridge,
                &self.bridge,
                CompletionBridge.readCallback,
            );
            self.bridge.waker = ctx.waker;
            return .pending;
        }

        return self.bridge.getResult();
    }
};
```

**2.2 TcpListener基于xev.TCP.accept**
```zig
pub const XevAcceptFuture = struct {
    xev_tcp: *xev.TCP,
    bridge: CompletionBridge,
    allocator: std.mem.Allocator,

    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!TcpStream) {
        if (self.bridge.state == .pending) {
            self.xev_tcp.accept(
                &ctx.event_loop.xev_loop,
                &self.bridge.completion,
                *CompletionBridge,
                &self.bridge,
                CompletionBridge.acceptCallback,
            );
            self.bridge.waker = ctx.waker;
            return .pending;
        }

        if (self.bridge.result.accept) |xev_tcp| {
            return .{ .ready = TcpStream{
                .xev_tcp = xev_tcp,
                .event_loop = ctx.event_loop,
            }};
        } else |err| {
            return .{ .ready = err };
        }
    }
};
```

#### **Phase 3: 文件I/O重构 (Week 3)**

**3.1 AsyncFile基于xev.File**
- **文件**: `src/fs/file.zig`, `src/fs/async_fs.zig`
```zig
// 🚀 新的AsyncFile实现
pub const AsyncFile = struct {
    xev_file: xev.File,
    event_loop: *AsyncEventLoop,

    pub fn open(path: []const u8, flags: std.fs.File.OpenFlags) !Self {
        return Self{
            .xev_file = try xev.File.init(path, flags),
            .event_loop = getCurrentEventLoop(),
        };
    }

    pub fn read(self: *Self, buffer: []u8, offset: u64) XevFileReadFuture {
        return XevFileReadFuture.init(&self.xev_file, buffer, offset);
    }
};
```

#### **Phase 4: 定时器和进程管理 (Week 4)**

**4.1 AsyncTimer基于xev.Timer**
```zig
pub const AsyncTimer = struct {
    pub fn sleep(duration_ms: u64) XevTimerFuture {
        return XevTimerFuture.init(duration_ms);
    }
};

pub const XevTimerFuture = struct {
    duration_ms: u64,
    bridge: CompletionBridge,

    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!void) {
        if (self.bridge.state == .pending) {
            const timer = try xev.Timer.init();
            timer.run(
                &ctx.event_loop.xev_loop,
                &self.bridge.completion,
                self.duration_ms,
                *CompletionBridge,
                &self.bridge,
                CompletionBridge.timerCallback,
            );
            self.bridge.waker = ctx.waker;
            return .pending;
        }

        return self.bridge.getResult();
    }
};
```

### **🎯 改造验收标准**

#### **功能验收**
- [ ] 所有`std.posix.read/write/accept`调用替换为libxev
- [ ] 所有`std.time.sleep`调用移除
- [ ] HTTP服务器示例完全基于libxev运行
- [ ] 文件I/O示例完全异步化

#### **性能验收**
- [ ] TCP吞吐量 >100K ops/sec (当前目标)
- [ ] 文件I/O吞吐量 >50K ops/sec
- [ ] 并发连接数 >1000 (无阻塞)
- [ ] 内存使用 <1KB per connection

#### **兼容性验收**
- [ ] Linux (io_uring优先，epoll降级)
- [ ] macOS (kqueue)
- [ ] 所有现有示例正常运行
- [ ] 所有测试通过

---

**技术负责人**: 异步I/O专家
**质量保证**: 性能测试工程师
**文档维护**: 技术文档工程师
**代码审查**: 高级Zig开发工程师

## 🛠 **立即开始实施指南**

### **Step 1: 创建CompletionBridge核心组件**

首先创建libxev和Zokio Future之间的桥接组件：

```bash
# 创建新文件
touch src/runtime/completion_bridge.zig
```

```zig
// src/runtime/completion_bridge.zig
const std = @import("std");
const xev = @import("libxev");
const future = @import("../future/future.zig");

/// 🚀 libxev Completion到Zokio Future的桥接器
pub const CompletionBridge = struct {
    const Self = @This();

    // libxev completion
    completion: xev.Completion = .{},

    // 状态管理
    state: enum { pending, ready, error } = .pending,

    // 结果存储
    result: union(enum) {
        none: void,
        read: xev.ReadError!usize,
        write: xev.WriteError!usize,
        accept: xev.AcceptError!xev.TCP,
        timer: xev.Timer.RunError!void,
        file_read: xev.ReadError!usize,
        file_write: xev.WriteError!usize,
    } = .none,

    // Waker用于唤醒等待的Future
    waker: ?future.Waker = null,

    pub fn init() Self {
        return Self{};
    }

    /// 通用回调函数 - 处理读取完成
    pub fn readCallback(
        bridge: *Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        _ = loop;
        _ = completion;

        bridge.result = .{ .read = result };
        bridge.state = .ready;

        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 通用回调函数 - 处理写入完成
    pub fn writeCallback(
        bridge: *Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        _ = loop;
        _ = completion;

        bridge.result = .{ .write = result };
        bridge.state = .ready;

        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 通用回调函数 - 处理accept完成
    pub fn acceptCallback(
        bridge: *Self,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        _ = loop;
        _ = completion;

        bridge.result = .{ .accept = result };
        bridge.state = .ready;

        if (bridge.waker) |waker| {
            waker.wake();
        }

        return .disarm;
    }

    /// 获取结果 - 泛型版本
    pub fn getResult(self: *Self, comptime T: type) future.Poll(T) {
        switch (self.state) {
            .pending => return .pending,
            .ready => {
                switch (self.result) {
                    .read => |r| {
                        if (T == anyerror!usize) {
                            return .{ .ready = r };
                        }
                    },
                    .write => |r| {
                        if (T == anyerror!usize) {
                            return .{ .ready = r };
                        }
                    },
                    .accept => |r| {
                        // 这里需要转换xev.TCP到TcpStream
                        // 在实际实现中会有具体的转换逻辑
                        _ = r;
                        return .pending; // 临时实现
                    },
                    else => return .pending,
                }
            },
            .error => {
                if (T == anyerror!usize) {
                    return .{ .ready = error.IOError };
                }
            },
        }
        return .pending;
    }

    /// 重置桥接器状态
    pub fn reset(self: *Self) void {
        self.state = .pending;
        self.result = .none;
        self.waker = null;
        self.completion = .{};
    }
};
```

### **Step 2: 重构TcpStream的read方法**

修改 `src/net/tcp.zig` 中的ReadFuture：

```zig
// 在tcp.zig开头添加导入
const CompletionBridge = @import("../runtime/completion_bridge.zig").CompletionBridge;

// 🚀 新的基于libxev的ReadFuture
pub const ReadFuture = struct {
    xev_tcp: *xev.TCP,
    buffer: []u8,
    bridge: CompletionBridge,
    event_loop: *AsyncEventLoop,

    const Self = @This();
    pub const Output = anyerror!usize;

    pub fn init(xev_tcp: *xev.TCP, buffer: []u8, event_loop: *AsyncEventLoop) Self {
        return Self{
            .xev_tcp = xev_tcp,
            .buffer = buffer,
            .bridge = CompletionBridge.init(),
            .event_loop = event_loop,
        };
    }

    pub fn poll(self: *Self, ctx: *Context) Poll(anyerror!usize) {
        switch (self.bridge.state) {
            .pending => {
                // 检查是否已经提交了操作
                if (self.bridge.completion.state == .dead) {
                    // 首次提交读取操作到libxev
                    self.bridge.waker = ctx.waker;
                    self.xev_tcp.read(
                        &self.event_loop.xev_loop,
                        &self.bridge.completion,
                        .{ .slice = self.buffer },
                        *CompletionBridge,
                        &self.bridge,
                        CompletionBridge.readCallback,
                    );
                }
                return .pending;
            },
            .ready, .error => {
                return self.bridge.getResult(anyerror!usize);
            },
        }
    }

    pub fn deinit(self: *Self) void {
        self.bridge.reset();
    }

    pub fn reset(self: *Self) void {
        self.bridge.reset();
    }
};
```

### **Step 3: 立即测试基础功能**

创建一个简单的测试来验证libxev集成：

```bash
# 创建测试文件
touch tests/libxev_integration_test.zig
```

```zig
// tests/libxev_integration_test.zig
const std = @import("std");
const testing = std.testing;
const xev = @import("libxev");
const CompletionBridge = @import("../src/runtime/completion_bridge.zig").CompletionBridge;

test "libxev basic integration" {
    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // 测试定时器
    const timer = try xev.Timer.init();
    defer timer.deinit();

    var bridge = CompletionBridge.init();

    // 运行1ms定时器
    timer.run(&loop, &bridge.completion, 1, *CompletionBridge, &bridge, CompletionBridge.timerCallback);

    // 运行事件循环
    try loop.run(.until_done);

    // 验证结果
    try testing.expect(bridge.state == .ready);
}

test "libxev TCP basic test" {
    if (std.builtin.os.tag == .wasi) return error.SkipZigTest;

    var loop = try xev.Loop.init(.{});
    defer loop.deinit();

    // 创建TCP服务器
    const addr = std.net.Address.parseIp4("127.0.0.1", 0) catch unreachable;
    var server = try xev.TCP.init(addr);
    defer server.close(&loop, &.{}, void, null, struct {
        fn callback(_: ?*void, _: *xev.Loop, _: *xev.Completion, _: xev.CloseError!void) xev.CallbackAction {
            return .disarm;
        }
    }.callback);

    try server.bind(addr);
    try server.listen(128);

    std.debug.print("libxev TCP test passed\n", .{});
}
```

### **Step 4: 运行测试验证**

```bash
# 编译并运行测试
zig build test

# 如果测试通过，继续下一步
# 如果测试失败，先修复基础集成问题
```

### **Step 5: 逐步替换现有实现**

按照以下顺序逐步替换：

1. **先替换TcpStream.read()** - 最简单的操作
2. **然后替换TcpStream.write()** - 类似的模式
3. **接着替换TcpListener.accept()** - 稍微复杂
4. **最后替换文件I/O** - 最复杂的部分

每一步都要：
- 运行测试确保功能正常
- 运行HTTP服务器示例验证实际使用
- 检查性能是否有提升

### **Step 6: 性能验证**

在每个阶段完成后运行性能测试：

```bash
# 运行网络性能测试
zig build stress-network

# 运行HTTP服务器压力测试
zig build example-simple_http_server &
curl -X GET http://localhost:8080/ # 验证功能
ab -n 10000 -c 100 http://localhost:8080/ # 压力测试
```

---

**立即行动计划**:
1. ✅ 创建CompletionBridge组件 (30分钟)
2. ✅ 重构ReadFuture (1小时)
3. ✅ 编写基础测试 (30分钟)
4. ✅ 验证基础功能 (30分钟)
5. 🔄 逐步替换其他I/O操作 (持续进行)

**预期收益**:
- 真正的异步I/O (消除所有阻塞调用)
- 性能提升 2-5倍
- 更好的并发支持 (1000+ connections)
- 跨平台兼容性 (Linux/macOS/Windows)
