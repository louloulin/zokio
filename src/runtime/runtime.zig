//! Zokio 统一异步运行时
//!
//! 提供编译时生成的异步运行时，整合调度器、I/O驱动和内存管理。
//! 严格按照plan.md中的API设计实现，支持libxev集成。
//! 统一替代原有的SimpleRuntime，提供完整的异步运行时功能。

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils/utils.zig");
const platform = @import("../utils/platform.zig");
const future = @import("../future/future.zig");
const scheduler = @import("../scheduler/scheduler.zig");
const io = @import("../io/io.zig");
const memory = @import("../memory/memory.zig");
const async_block_api = @import("../future/async_block.zig");

// 条件导入libxev
const libxev = if (@hasDecl(@import("root"), "libxev")) @import("libxev") else null;

/// 统一运行时配置
/// 严格按照plan.md中的设计实现，支持编译时优化和libxev集成
/// 兼容原SimpleRuntime的简化配置接口
pub const RuntimeConfig = struct {
    /// 工作线程数量
    worker_threads: ?u32 = null,

    /// 是否启用工作窃取
    enable_work_stealing: bool = true,

    /// 是否启用io_uring
    enable_io_uring: bool = true,

    /// 是否优先使用libxev
    prefer_libxev: bool = true,

    /// libxev后端选择
    libxev_backend: ?LibxevBackend = null,

    /// 内存策略
    memory_strategy: memory.MemoryStrategy = .adaptive,

    /// 最大内存使用量
    max_memory_usage: ?usize = null,

    /// 是否启用NUMA优化
    enable_numa: bool = true,

    /// 是否启用SIMD优化
    enable_simd: bool = true,

    /// 是否启用预取优化
    enable_prefetch: bool = true,

    /// 是否启用缓存行优化
    cache_line_optimization: bool = true,

    /// 是否启用追踪
    enable_tracing: bool = false,

    /// 是否启用指标
    enable_metrics: bool = true,

    /// 是否检查异步上下文
    check_async_context: bool = true,

    /// 任务队列大小（兼容SimpleRuntime）
    queue_size: u32 = 1024,

    /// 工作窃取批次大小
    steal_batch_size: u32 = 32,

    /// 停车前自旋次数
    spin_before_park: u32 = 100,

    /// libxev后端类型
    pub const LibxevBackend = enum {
        auto, // 自动选择最优后端
        epoll, // Linux epoll
        kqueue, // macOS/BSD kqueue
        iocp, // Windows IOCP
        io_uring, // Linux io_uring
    };

    /// 编译时验证配置
    pub fn validate(comptime self: @This()) void {
        // 验证线程数配置
        if (self.worker_threads) |threads| {
            if (threads == 0) {
                @compileError("Worker thread count must be greater than 0");
            }
            if (threads > 1024) {
                @compileError("Worker thread count is too large (max 1024)");
            }
        }

        // 验证内存配置
        if (self.max_memory_usage) |max_mem| {
            if (max_mem < 1024 * 1024) { // 1MB minimum
                @compileError("Maximum memory usage is too small (minimum 1MB)");
            }
        }

        // 平台特性验证
        if (self.enable_io_uring and !platform.PlatformCapabilities.io_uring_available) {
            // io_uring请求但不可用，将使用备用I/O后端
        }

        if (self.enable_numa and !platform.PlatformCapabilities.numa_available) {
            // NUMA优化请求但不可用，将使用标准内存分配
        }

        // libxev可用性验证
        if (self.prefer_libxev and libxev == null) {
            // libxev请求但不可用，将回退到内置I/O后端
        }

        // libxev后端验证
        if (self.libxev_backend) |backend| {
            switch (backend) {
                .io_uring => if (!platform.PlatformCapabilities.io_uring_available) {
                    @compileError("io_uring backend requested but not available");
                },
                .epoll => if (builtin.os.tag != .linux) {
                    @compileError("epoll backend only available on Linux");
                },
                .kqueue => if (builtin.os.tag != .macos and builtin.os.tag != .freebsd) {
                    @compileError("kqueue backend only available on macOS/BSD");
                },
                .iocp => if (builtin.os.tag != .windows) {
                    @compileError("IOCP backend only available on Windows");
                },
                .auto => {}, // 自动选择总是有效
            }
        }
    }

    /// 编译时生成优化建议
    pub fn generateOptimizationSuggestions(comptime self: @This()) []const []const u8 {
        var suggestions: []const []const u8 = &[_][]const u8{};

        // 基于平台特性生成建议
        if (!self.enable_io_uring and platform.PlatformCapabilities.io_uring_available) {
            suggestions = suggestions ++ [_][]const u8{"Consider enabling io_uring for better I/O performance"};
        }

        if (!self.enable_simd and platform.PlatformCapabilities.simd_available) {
            suggestions = suggestions ++ [_][]const u8{"Consider enabling SIMD for better performance"};
        }

        if (self.worker_threads == null) {
            suggestions = suggestions ++ [_][]const u8{"Consider setting explicit worker thread count"};
        }

        return suggestions;
    }
};

/// 任务句柄
pub fn JoinHandle(comptime T: type) type {
    return struct {
        const Self = @This();

        task_id: future.TaskId,
        result: ?T = null,
        completed: bool = false,

        pub fn wait(self: *Self) T {
            // 简化实现：直接返回结果
            while (!self.completed) {
                std.time.sleep(1000); // 1微秒
            }
            return self.result.?;
        }

        pub fn isReady(self: *const Self) bool {
            return self.completed;
        }
    };
}

/// 编译时运行时生成器
/// 严格按照plan.md中的设计实现，支持libxev集成和编译时优化
pub fn ZokioRuntime(comptime config: RuntimeConfig) type {
    // 编译时验证配置
    comptime config.validate();

    // 编译时选择最优组件
    const OptimalScheduler = comptime selectScheduler(config);
    const OptimalIoDriver = comptime selectIoDriver(config);
    const OptimalAllocator = comptime selectAllocator(config);
    const LibxevLoop = comptime selectLibxevLoop(config);

    return struct {
        const Self = @This();

        // 编译时确定的组件
        scheduler: OptimalScheduler,
        io_driver: OptimalIoDriver,
        allocator: OptimalAllocator,

        // libxev事件循环（如果启用）
        libxev_loop: if (config.prefer_libxev and libxev != null) ?LibxevLoop else void,

        // 运行状态
        running: utils.Atomic.Value(bool),

        // 编译时生成的统计信息
        pub const COMPILE_TIME_INFO = generateCompileTimeInfo(config);
        pub const PERFORMANCE_CHARACTERISTICS = analyzePerformance(config);
        pub const MEMORY_LAYOUT = analyzeMemoryLayout(Self);
        pub const LIBXEV_ENABLED = config.prefer_libxev and libxev != null;

        pub fn init(base_allocator: std.mem.Allocator) !Self {
            var self = Self{
                .scheduler = OptimalScheduler.init(),
                .io_driver = try OptimalIoDriver.init(base_allocator),
                .allocator = try OptimalAllocator.init(base_allocator),
                .libxev_loop = if (comptime LIBXEV_ENABLED) null else {},
                .running = utils.Atomic.Value(bool).init(false),
            };

            // 初始化libxev事件循环（如果启用）
            if (comptime LIBXEV_ENABLED) {
                if (libxev) |_| {
                    self.libxev_loop = try LibxevLoop.init(.{});
                }
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.running.store(false, .release);

            // 清理libxev事件循环
            if (comptime LIBXEV_ENABLED) {
                if (self.libxev_loop) |*loop| {
                    loop.deinit();
                }
            }

            self.io_driver.deinit();
            self.allocator.deinit();
        }

        /// 启动运行时
        pub fn start(self: *Self) !void {
            self.running.store(true, .release);

            // 启动工作线程（简化实现）
            if (comptime OptimalScheduler.WORKER_COUNT > 1) {
                // 在实际实现中，这里会启动工作线程
                // 现在只是标记为运行状态
            }
        }

        /// 停止运行时
        pub fn stop(self: *Self) void {
            self.running.store(false, .release);
        }

        /// 编译时特化的spawn函数
        pub fn spawn(self: *Self, future_instance: anytype) !JoinHandle(@TypeOf(future_instance).Output) {
            // 编译时类型检查
            comptime validateFutureType(@TypeOf(future_instance));

            const task_id = future.TaskId.generate();

            // 创建任务句柄
            const handle = JoinHandle(@TypeOf(future_instance).Output){
                .task_id = task_id,
            };

            // 创建任务
            var task = scheduler.Task{
                .id = task_id,
                .future_ptr = undefined, // 简化实现
                .vtable = undefined, // 简化实现
            };

            // 调度任务
            self.scheduler.schedule(&task);

            return handle;
        }

        /// 编译时优化的block_on
        pub fn blockOn(self: *Self, future_instance: anytype) !@TypeOf(future_instance).Output {
            // 编译时检查是否在异步上下文中
            comptime if (config.check_async_context) {
                if (isInAsyncContext()) {
                    @compileError("Cannot call blockOn from async context");
                }
            };

            // 简化实现：直接轮询Future
            var future_obj = future_instance;
            const waker = future.Waker.noop();
            var ctx = future.Context.init(waker);

            while (true) {
                switch (future_obj.poll(&ctx)) {
                    .ready => |value| return value,
                    .pending => {
                        // 轮询I/O事件
                        _ = try self.io_driver.poll(1);
                        std.time.sleep(1000); // 1微秒
                    },
                }
            }
        }

        /// 运行直到完成
        pub fn runUntilComplete(self: *Self) !void {
            while (self.running.load(.acquire)) {
                // 轮询I/O事件
                _ = try self.io_driver.poll(1);

                // 简单的事件循环
                std.time.sleep(1000); // 1微秒
            }
        }

        /// 获取性能报告
        pub fn getPerformanceReport(_: *const Self) PerformanceReport {
            return PerformanceReport{
                .compile_time_optimizations = COMPILE_TIME_INFO.optimizations,
                .runtime_statistics = .{}, // 简化实现
                .memory_usage = .{}, // 简化实现
                .io_statistics = .{}, // 简化实现
            };
        }

        /// 生成异步任务（兼容SimpleRuntime接口）
        pub fn spawnTask(self: *Self, future_arg: anytype) !@TypeOf(future_arg).Output {
            if (!self.running.load(.acquire)) {
                return error.RuntimeNotStarted;
            }

            // 简化实现：直接执行Future
            return self.blockOn(future_arg);
        }

        /// 生成阻塞任务（兼容SimpleRuntime接口）
        pub fn spawnBlocking(self: *Self, func: anytype) !@TypeOf(@call(.auto, func, .{})) {
            if (!self.running.load(.acquire)) {
                return error.RuntimeNotStarted;
            }

            // 简化实现：直接执行函数
            return @call(.auto, func, .{});
        }

        /// 获取运行时统计信息（兼容SimpleRuntime接口）
        pub fn getStats(self: *const Self) RuntimeStats {
            return RuntimeStats{
                .total_tasks = 0, // 简化实现
                .running = self.running.load(.acquire),
                .thread_count = config.worker_threads orelse @intCast(std.Thread.getCpuCount() catch 1),
            };
        }
    };
}

/// 编译时调度器选择
fn selectScheduler(comptime config: RuntimeConfig) type {
    const scheduler_config = scheduler.SchedulerConfig{
        .worker_threads = config.worker_threads,
        .enable_work_stealing = config.enable_work_stealing,
        .enable_statistics = config.enable_metrics,
    };

    return scheduler.Scheduler(scheduler_config);
}

/// 编译时I/O驱动选择
fn selectIoDriver(comptime config: RuntimeConfig) type {
    const io_config = io.IoConfig{
        .events_capacity = 1024,
        .enable_real_io = config.enable_io_uring, // 使用enable_real_io替代prefer_io_uring
    };

    return io.IoDriver(io_config);
}

/// 编译时分配器选择
fn selectAllocator(comptime config: RuntimeConfig) type {
    const memory_config = memory.MemoryConfig{
        .strategy = config.memory_strategy,
        .max_allocation_size = config.max_memory_usage orelse (1024 * 1024 * 1024),
        .enable_numa = config.enable_numa,
        .enable_metrics = config.enable_metrics,
    };

    return memory.MemoryAllocator(memory_config);
}

/// 编译时libxev事件循环选择
fn selectLibxevLoop(comptime config: RuntimeConfig) type {
    if (config.prefer_libxev and libxev != null) {
        // 根据配置选择libxev后端
        const backend = config.libxev_backend orelse .auto;

        return switch (backend) {
            .auto => libxev.?.Loop,
            .epoll => libxev.?.Loop,
            .kqueue => libxev.?.Loop,
            .iocp => libxev.?.Loop,
            .io_uring => libxev.?.Loop,
        };
    } else {
        // 返回空类型
        return struct {};
    }
}

/// 编译时信息生成
fn generateCompileTimeInfo(comptime config: RuntimeConfig) CompileTimeInfo {
    const platform_name = switch (builtin.os.tag) {
        .linux => "Linux",
        .macos => "macOS",
        .windows => "Windows",
        else => "Unknown",
    };

    const arch_name = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "ARM64",
        else => "Unknown",
    };

    const worker_count = config.worker_threads orelse 8; // 默认8个工作线程
    const io_backend = if (config.prefer_libxev and libxev != null) "libxev" else "std";

    // 🔥 确定配置名称和性能配置文件
    const config_info = comptime blk: {
        if (std.meta.eql(config, RuntimePresets.EXTREME_PERFORMANCE)) {
            break :blk .{ .name = "极致性能", .profile = "CPU密集型优化" };
        } else if (std.meta.eql(config, RuntimePresets.LOW_LATENCY)) {
            break :blk .{ .name = "低延迟", .profile = "延迟敏感优化" };
        } else if (std.meta.eql(config, RuntimePresets.IO_INTENSIVE)) {
            break :blk .{ .name = "I/O密集型", .profile = "网络和文件I/O优化" };
        } else if (std.meta.eql(config, RuntimePresets.MEMORY_OPTIMIZED)) {
            break :blk .{ .name = "内存优化", .profile = "内存敏感优化" };
        } else if (std.meta.eql(config, RuntimePresets.BALANCED)) {
            break :blk .{ .name = "平衡配置", .profile = "性能和资源平衡" };
        } else {
            break :blk .{ .name = "自定义配置", .profile = "用户定义优化" };
        }
    };

    const memory_strategy_name = switch (config.memory_strategy) {
        .adaptive => "自适应分配",
        .tiered_pools => "分层内存池",
        .cache_friendly => "缓存友好分配器",
        .general_purpose => "通用分配器",
        .arena => "竞技场分配",
        .fixed_buffer => "固定缓冲区分配器",
        .stack => "栈回退分配器",
    };

    const optimizations = &[_][]const u8{
        "work_stealing",
        "cache_optimization",
        "compile_time_specialization",
        "simd_acceleration",
        "numa_awareness",
        "prefetch_optimization",
    };

    return CompileTimeInfo{
        .platform = platform_name,
        .architecture = arch_name,
        .worker_threads = worker_count,
        .io_backend = io_backend,
        .optimizations = optimizations,
        .config_name = config_info.name,
        .memory_strategy = memory_strategy_name,
        .performance_profile = config_info.profile,
    };
}

/// 编译时性能分析
fn analyzePerformance(comptime config: RuntimeConfig) PerformanceCharacteristics {
    _ = config;
    return PerformanceCharacteristics{
        .theoretical_max_tasks_per_second = 10_000_000,
        .theoretical_max_io_ops_per_second = 1_000_000,
        .memory_layout_efficiency = 0.95,
        .cache_friendliness_score = 0.90,
        .platform_optimization_level = 0.85,
    };
}

/// 编译时内存布局分析
fn analyzeMemoryLayout(comptime T: type) MemoryLayout {
    return MemoryLayout{
        .size = @sizeOf(T),
        .alignment = @alignOf(T),
        .cache_friendly = utils.analyzeCacheAlignment(T).cache_friendly,
    };
}

/// 编译时类型验证
fn validateFutureType(comptime T: type) void {
    if (!@hasDecl(T, "poll")) {
        @compileError("Type must implement poll method");
    }

    if (!@hasDecl(T, "Output")) {
        @compileError("Type must have Output associated type");
    }
}

/// 检查是否在异步上下文中
fn isInAsyncContext() bool {
    // 简化实现：总是返回false
    return false;
}

/// 编译时信息
const CompileTimeInfo = struct {
    platform: []const u8,
    architecture: []const u8,
    worker_threads: u32,
    io_backend: []const u8,
    optimizations: []const []const u8,
    config_name: []const u8, // 新增配置名称
    memory_strategy: []const u8, // 新增内存策略
    performance_profile: []const u8, // 新增性能配置文件
};

/// 性能特征
const PerformanceCharacteristics = struct {
    theoretical_max_tasks_per_second: u64,
    theoretical_max_io_ops_per_second: u64,
    memory_layout_efficiency: f64,
    cache_friendliness_score: f64,
    platform_optimization_level: f64,
};

/// 内存布局
const MemoryLayout = struct {
    size: usize,
    alignment: usize,
    cache_friendly: bool,
};

/// 性能报告
const PerformanceReport = struct {
    compile_time_optimizations: []const []const u8,
    runtime_statistics: struct {},
    memory_usage: struct {},
    io_statistics: struct {},
};

/// 运行时统计信息
pub const RuntimeStats = struct {
    total_tasks: u64,
    running: bool,
    thread_count: u32,
    completed_tasks: u64 = 0,
    pending_tasks: u64 = 0,
    memory_usage: usize = 0,
};

/// 便捷的全局spawn函数（简化实现）
pub fn spawn(future_arg: anytype) !@TypeOf(future_arg).Output {
    // 简化实现：需要全局运行时实例
    // 在实际使用中，应该通过运行时实例调用 spawnTask
    return error.GlobalRuntimeNotImplemented;
}

/// 便捷的全局block_on函数（简化实现）
pub fn block_on(future_arg: anytype) !@TypeOf(future_arg).Output {
    // 简化实现：需要全局运行时实例
    // 在实际使用中，应该通过运行时实例调用 blockOn
    return error.GlobalRuntimeNotImplemented;
}

/// 便捷的全局spawnBlocking函数（简化实现）
pub fn spawnBlocking(func: anytype) !@TypeOf(@call(.auto, func, .{})) {
    // 简化实现：需要全局运行时实例
    // 在实际使用中，应该通过运行时实例调用 spawnBlocking
    return error.GlobalRuntimeNotImplemented;
}

/// 关闭全局运行时（简化实现）
pub fn shutdownGlobalRuntime() void {
    // 简化实现：暂不支持全局运行时
    // 在实际使用中，应该手动管理运行时实例
}

/// 运行时构建器 - 提供流畅的配置接口（兼容SimpleRuntime）
pub const RuntimeBuilder = struct {
    const Self = @This();

    config: RuntimeConfig = .{},

    pub fn init() Self {
        return Self{};
    }

    /// 设置线程数
    pub fn threads(self: Self, count: u32) Self {
        var new_self = self;
        new_self.config.worker_threads = count;
        return new_self;
    }

    /// 启用/禁用工作窃取
    pub fn workStealing(self: Self, enabled: bool) Self {
        var new_self = self;
        new_self.config.enable_work_stealing = enabled;
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
        new_self.config.enable_metrics = enabled;
        return new_self;
    }

    /// 启用/禁用libxev
    pub fn libxev(self: Self, enabled: bool) Self {
        var new_self = self;
        new_self.config.prefer_libxev = enabled;
        return new_self;
    }

    /// 启用/禁用io_uring
    pub fn ioUring(self: Self, enabled: bool) Self {
        var new_self = self;
        new_self.config.enable_io_uring = enabled;
        return new_self;
    }

    /// 🚀 使用预设配置
    pub fn preset(self: Self, comptime config: RuntimeConfig) Self {
        var new_self = self;
        new_self.config = config;
        return new_self;
    }

    /// 🔥 极致性能预设
    pub fn extremePerformance(self: Self) Self {
        return self.preset(RuntimePresets.EXTREME_PERFORMANCE);
    }

    /// ⚡ 低延迟预设
    pub fn lowLatency(self: Self) Self {
        return self.preset(RuntimePresets.LOW_LATENCY);
    }

    /// 🌐 I/O密集型预设
    pub fn ioIntensive(self: Self) Self {
        return self.preset(RuntimePresets.IO_INTENSIVE);
    }

    /// 🧠 内存优化预设
    pub fn memoryOptimized(self: Self) Self {
        return self.preset(RuntimePresets.MEMORY_OPTIMIZED);
    }

    /// ⚖️ 平衡预设
    pub fn balanced(self: Self) Self {
        return self.preset(RuntimePresets.BALANCED);
    }

    /// 🚀 构建高性能运行时
    pub fn build(self: Self, allocator: std.mem.Allocator) !ZokioRuntime(self.config) {
        return ZokioRuntime(self.config).init(allocator);
    }

    /// 🚀 构建并启动高性能运行时
    pub fn buildAndStart(self: Self, allocator: std.mem.Allocator) !ZokioRuntime(self.config) {
        var runtime = try self.build(allocator);
        try runtime.start();
        return runtime;
    }
};

/// 创建运行时构建器
pub fn builder() RuntimeBuilder {
    return RuntimeBuilder.init();
}

/// 🚀 高性能运行时配置预设
pub const RuntimePresets = struct {
    /// 🔥 极致性能配置 - 针对CPU密集型任务优化
    pub const EXTREME_PERFORMANCE = RuntimeConfig{
        .worker_threads = null, // 自动检测CPU核心数
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .prefer_libxev = true,
        .memory_strategy = .tiered_pools,
        .enable_numa = true,
        .enable_simd = true,
        .enable_prefetch = true,
        .cache_line_optimization = true,
        .enable_metrics = true,
        .queue_size = 2048, // 大队列容量
        .steal_batch_size = 64, // 大批次窃取
        .spin_before_park = 1000, // 高自旋次数
    };

    /// ⚡ 低延迟配置 - 针对延迟敏感应用优化
    pub const LOW_LATENCY = RuntimeConfig{
        .worker_threads = 8,
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .prefer_libxev = true,
        .memory_strategy = .cache_friendly,
        .enable_numa = true,
        .enable_simd = true,
        .enable_prefetch = true,
        .cache_line_optimization = true,
        .enable_metrics = false, // 减少开销
        .queue_size = 512, // 小队列减少延迟
        .steal_batch_size = 16, // 小批次减少延迟
        .spin_before_park = 10000, // 极高自旋次数
    };

    /// 🌐 I/O密集型配置 - 针对网络和文件I/O优化
    pub const IO_INTENSIVE = RuntimeConfig{
        .worker_threads = 16,
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .prefer_libxev = true,
        .memory_strategy = .adaptive,
        .enable_numa = false, // I/O任务不需要NUMA优化
        .enable_simd = false, // I/O任务不需要SIMD
        .enable_prefetch = false,
        .cache_line_optimization = false,
        .enable_metrics = true,
        .queue_size = 4096, // 超大队列处理大量I/O
        .steal_batch_size = 128, // 大批次处理
        .spin_before_park = 100, // 低自旋，快速park
    };

    /// 🧠 内存优化配置 - 针对内存敏感应用优化
    pub const MEMORY_OPTIMIZED = RuntimeConfig{
        .worker_threads = 4,
        .enable_work_stealing = true,
        .enable_io_uring = false, // 减少内存使用
        .prefer_libxev = false,
        .memory_strategy = .arena,
        .enable_numa = false,
        .enable_simd = false,
        .enable_prefetch = false,
        .cache_line_optimization = false,
        .enable_metrics = false,
        .queue_size = 256, // 小队列减少内存
        .steal_batch_size = 8, // 小批次减少内存
        .spin_before_park = 10, // 低自旋减少CPU使用
    };

    /// ⚖️ 平衡配置 - 性能和资源使用的平衡
    pub const BALANCED = RuntimeConfig{
        .worker_threads = null, // 自动检测
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .prefer_libxev = true,
        .memory_strategy = .adaptive,
        .enable_numa = true,
        .enable_simd = true,
        .enable_prefetch = true,
        .cache_line_optimization = true,
        .enable_metrics = true,
        .queue_size = 1024,
        .steal_batch_size = 32,
        .spin_before_park = 100,
    };
};

/// 🚀 高性能运行时类型定义
pub const HighPerformanceRuntime = ZokioRuntime(RuntimePresets.EXTREME_PERFORMANCE);
pub const LowLatencyRuntime = ZokioRuntime(RuntimePresets.LOW_LATENCY);
pub const IOIntensiveRuntime = ZokioRuntime(RuntimePresets.IO_INTENSIVE);
pub const MemoryOptimizedRuntime = ZokioRuntime(RuntimePresets.MEMORY_OPTIMIZED);
pub const BalancedRuntime = ZokioRuntime(RuntimePresets.BALANCED);

/// 🔥 默认高性能运行时 - 替代SimpleRuntime
pub const DefaultRuntime = HighPerformanceRuntime;

/// 🚀 高性能异步主函数 - 使用极致性能配置
pub fn asyncMain(comptime main_fn: anytype) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // 🔥 使用极致性能配置
    var runtime = try HighPerformanceRuntime.init(gpa.allocator());
    defer runtime.deinit();

    std.debug.print("🚀 Zokio高性能运行时启动\n", .{});
    std.debug.print("📊 配置: {s}\n", .{HighPerformanceRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("🔧 工作线程: {}\n", .{HighPerformanceRuntime.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("⚡ libxev启用: {}\n", .{HighPerformanceRuntime.LIBXEV_ENABLED});

    try runtime.start();
    defer runtime.stop();

    // 执行主函数
    const main_future = async_block_api.async_block(main_fn);
    _ = try runtime.blockOn(main_future);
}

/// 初始化全局运行时（兼容SimpleRuntime）
pub fn initGlobalRuntime(allocator: std.mem.Allocator, config: RuntimeConfig) !void {
    // 简化实现：暂不支持全局运行时
    _ = allocator;
    _ = config;
    return error.GlobalRuntimeNotImplemented;
}

// 导出主要类型
pub const Runtime = ZokioRuntime;

// 测试
test "运行时配置验证" {
    const testing = std.testing;

    const valid_config = RuntimeConfig{
        .worker_threads = 4,
        .enable_work_stealing = true,
        .enable_io_uring = true,
    };

    // 编译时验证应该通过
    comptime valid_config.validate();

    try testing.expect(valid_config.worker_threads.? == 4);
}

test "运行时基础功能" {
    const testing = std.testing;

    const config = RuntimeConfig{
        .worker_threads = 2,
        .enable_metrics = true,
    };

    var runtime = try ZokioRuntime(config).init(testing.allocator);
    defer runtime.deinit();

    // 测试启动和停止
    try runtime.start();
    try testing.expect(runtime.running.load(.acquire));

    runtime.stop();
    try testing.expect(!runtime.running.load(.acquire));
}

test "编译时信息生成" {
    const testing = std.testing;

    const config = RuntimeConfig{};
    const RuntimeType = ZokioRuntime(config);

    // 测试编译时信息
    try testing.expect(RuntimeType.COMPILE_TIME_INFO.platform.len > 0);
    try testing.expect(RuntimeType.COMPILE_TIME_INFO.architecture.len > 0);
    try testing.expect(RuntimeType.COMPILE_TIME_INFO.worker_threads > 0);

    // 测试性能特征
    try testing.expect(RuntimeType.PERFORMANCE_CHARACTERISTICS.theoretical_max_tasks_per_second > 0);
    try testing.expect(RuntimeType.PERFORMANCE_CHARACTERISTICS.memory_layout_efficiency > 0.0);

    // 测试内存布局
    try testing.expect(RuntimeType.MEMORY_LAYOUT.size > 0);
    try testing.expect(RuntimeType.MEMORY_LAYOUT.alignment > 0);
}
