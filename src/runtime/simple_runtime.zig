//! Zokio 简化运行时
//!
//! 提供简洁的运行时接口，专注于核心异步执行功能

const std = @import("std");
const future = @import("../future/future.zig");
const async_block_api = @import("../future/async_block.zig");

pub const Context = future.Context;
pub const Poll = future.Poll;
pub const Waker = future.Waker;
// JoinHandle 暂时移除，简化实现

/// 简化的运行时配置
pub const SimpleConfig = struct {
    /// 工作线程数量
    threads: ?u32 = null,

    /// 是否启用工作窃取
    work_stealing: bool = true,

    /// 任务队列大小
    queue_size: u32 = 1024,

    /// 是否启用指标收集
    metrics: bool = false,
};

/// 简化的异步运行时
pub const SimpleRuntime = struct {
    const Self = @This();

    /// 配置
    config: SimpleConfig,

    /// 分配器
    allocator: std.mem.Allocator,

    /// 运行状态
    running: bool = false,

    /// 任务计数器
    task_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// 初始化运行时
    pub fn init(allocator: std.mem.Allocator, config: SimpleConfig) Self {
        return Self{
            .config = config,
            .allocator = allocator,
        };
    }

    /// 清理运行时
    pub fn deinit(self: *Self) void {
        if (self.running) {
            self.shutdown();
        }
    }

    /// 启动运行时
    pub fn start(self: *Self) !void {
        if (self.running) return;

        self.running = true;

        // 在实际实现中，这里会启动工作线程
        std.debug.print("简化运行时已启动\n", .{});
    }

    /// 关闭运行时
    pub fn shutdown(self: *Self) void {
        if (!self.running) return;

        self.running = false;

        // 在实际实现中，这里会停止工作线程
        std.debug.print("简化运行时已关闭\n", .{});
    }

    /// 阻塞执行Future直到完成
    pub fn blockOn(self: *Self, future_arg: anytype) !@TypeOf(future_arg).Output {
        if (!self.running) {
            return error.RuntimeNotStarted;
        }

        var f = future_arg;
        const waker = Waker.noop();
        var ctx = Context.init(waker);

        // 简单的轮询循环
        while (true) {
            switch (f.poll(&ctx)) {
                .ready => |result| return result,
                .pending => {
                    // 在实际实现中，这里会让出CPU并等待唤醒
                    std.time.sleep(1 * std.time.ns_per_ms); // 1ms
                },
            }
        }
    }

    /// 生成异步任务（简化版本，直接执行）
    pub fn spawn(self: *Self, future_arg: anytype) !@TypeOf(future_arg).Output {
        if (!self.running) {
            return error.RuntimeNotStarted;
        }

        _ = self.task_counter.fetchAdd(1, .monotonic);

        // 简化实现：直接执行Future
        return self.blockOn(future_arg);
    }

    /// 生成阻塞任务（简化版本，直接执行）
    pub fn spawnBlocking(self: *Self, func: anytype) !@TypeOf(@call(.auto, func, .{})) {
        if (!self.running) {
            return error.RuntimeNotStarted;
        }

        _ = self.task_counter.fetchAdd(1, .monotonic);

        // 简化实现：直接执行函数
        return @call(.auto, func, .{});
    }

    /// 获取运行时统计信息
    pub fn getStats(self: *const Self) RuntimeStats {
        return RuntimeStats{
            .total_tasks = self.task_counter.load(.monotonic),
            .running = self.running,
            .thread_count = self.config.threads orelse @intCast(std.Thread.getCpuCount() catch 1),
        };
    }
};

/// 运行时统计信息
pub const RuntimeStats = struct {
    total_tasks: u64,
    running: bool,
    thread_count: u32,
};

/// 全局运行时实例
var global_runtime: ?SimpleRuntime = null;
var global_runtime_mutex: std.Thread.Mutex = .{};

/// 获取全局运行时
pub fn getGlobalRuntime() !*SimpleRuntime {
    global_runtime_mutex.lock();
    defer global_runtime_mutex.unlock();

    if (global_runtime == null) {
        return error.RuntimeNotInitialized;
    }

    return &global_runtime.?;
}

/// 初始化全局运行时
pub fn initGlobalRuntime(allocator: std.mem.Allocator, config: SimpleConfig) !void {
    global_runtime_mutex.lock();
    defer global_runtime_mutex.unlock();

    if (global_runtime != null) {
        return error.RuntimeAlreadyInitialized;
    }

    global_runtime = SimpleRuntime.init(allocator, config);
    try global_runtime.?.start();
}

/// 关闭全局运行时
pub fn shutdownGlobalRuntime() void {
    global_runtime_mutex.lock();
    defer global_runtime_mutex.unlock();

    if (global_runtime) |*runtime| {
        runtime.deinit();
        global_runtime = null;
    }
}

/// 便捷的全局spawn函数
pub fn spawn(future_arg: anytype) !@TypeOf(future_arg).Output {
    const runtime = try getGlobalRuntime();
    return runtime.spawn(future_arg);
}

/// 便捷的全局blockOn函数
pub fn blockOn(future_arg: anytype) !@TypeOf(future_arg).Output {
    const runtime = try getGlobalRuntime();
    return runtime.blockOn(future_arg);
}

/// 便捷的全局spawnBlocking函数
pub fn spawnBlocking(func: anytype) !@TypeOf(@call(.auto, func, .{})) {
    const runtime = try getGlobalRuntime();
    return runtime.spawnBlocking(func);
}

/// 运行时构建器 - 提供流畅的配置接口
pub const RuntimeBuilder = struct {
    const Self = @This();

    config: SimpleConfig = .{},

    pub fn init() Self {
        return Self{};
    }

    /// 设置线程数
    pub fn threads(self: Self, count: u32) Self {
        var new_self = self;
        new_self.config.threads = count;
        return new_self;
    }

    /// 启用/禁用工作窃取
    pub fn workStealing(self: Self, enabled: bool) Self {
        var new_self = self;
        new_self.config.work_stealing = enabled;
        return new_self;
    }

    /// 设置队列大小
    pub fn queueSize(self: Self, size: u32) Self {
        var new_self = self;
        new_self.config.queue_size = size;
        return new_self;
    }

    /// 启用/禁用指标
    pub fn metrics(self: Self, enabled: bool) Self {
        var new_self = self;
        new_self.config.metrics = enabled;
        return new_self;
    }

    /// 构建运行时
    pub fn build(self: Self, allocator: std.mem.Allocator) SimpleRuntime {
        return SimpleRuntime.init(allocator, self.config);
    }

    /// 构建并启动运行时
    pub fn buildAndStart(self: Self, allocator: std.mem.Allocator) !SimpleRuntime {
        var runtime = self.build(allocator);
        try runtime.start();
        return runtime;
    }
};

/// 创建运行时构建器
pub fn builder() RuntimeBuilder {
    return RuntimeBuilder.init();
}

/// 异步主函数宏
pub fn asyncMain(comptime main_fn: anytype) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const config = SimpleConfig{
        .threads = null, // 自动检测
        .work_stealing = true,
        .metrics = false,
    };

    var runtime = SimpleRuntime.init(gpa.allocator(), config);
    defer runtime.deinit();

    try runtime.start();

    // 执行主函数
    const main_future = async_block_api.async_block(main_fn);
    _ = try runtime.blockOn(main_future);
}

// 测试
test "简化运行时基础功能" {
    const testing = std.testing;

    var runtime = SimpleRuntime.init(testing.allocator, .{});
    defer runtime.deinit();

    try runtime.start();

    // 测试简单Future
    const simple_future = future.ready(u32, 42);
    const result = try runtime.blockOn(simple_future);
    try testing.expectEqual(@as(u32, 42), result);

    // 测试统计信息
    const stats = runtime.getStats();
    try testing.expect(stats.running);
}

test "运行时构建器" {
    const testing = std.testing;

    var runtime = builder()
        .threads(2)
        .workStealing(true)
        .queueSize(512)
        .metrics(true)
        .build(testing.allocator);
    defer runtime.deinit();

    try testing.expectEqual(@as(?u32, 2), runtime.config.threads);
    try testing.expect(runtime.config.work_stealing);
    try testing.expectEqual(@as(u32, 512), runtime.config.queue_size);
    try testing.expect(runtime.config.metrics);
}
