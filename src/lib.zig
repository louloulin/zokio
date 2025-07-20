//! 📚 Zokio Phase 4: 分层 API 设计
//!
//! Phase 4 实现：分层 API 架构和接口优化
//! - 🚀 简化 API：90% 用户的核心需求
//! - 🔧 高级 API：专业用户的深度定制
//! - 🧪 实验性 API：早期采用者的前沿功能
//! - 🛡️ 统一错误处理：类型安全的错误管理

const std = @import("std");
const builtin = @import("builtin");

/// 🛡️ Phase 4: 统一错误处理系统
pub const ZokioError = union(enum) {
    runtime: RuntimeError,
    io: IOError,
    memory: MemoryError,
    timeout: TimeoutError,
    future: FutureError,

    /// 获取错误上下文
    pub fn context(self: @This()) ErrorContext {
        return switch (self) {
            .runtime => |e| e.context,
            .io => |e| e.context,
            .memory => |e| e.context,
            .timeout => |e| e.context,
            .future => |e| e.context,
        };
    }

    /// 获取错误描述
    pub fn description(self: @This()) []const u8 {
        return switch (self) {
            .runtime => |e| e.description,
            .io => |e| e.description,
            .memory => |e| e.description,
            .timeout => |e| e.description,
            .future => |e| e.description,
        };
    }
};

/// 运行时错误
pub const RuntimeError = struct {
    code: RuntimeErrorCode,
    context: ErrorContext,
    description: []const u8,
};

/// I/O 错误
pub const IOError = struct {
    code: IOErrorCode,
    context: ErrorContext,
    description: []const u8,
};

/// 内存错误
pub const MemoryError = struct {
    code: MemoryErrorCode,
    context: ErrorContext,
    description: []const u8,
};

/// 超时错误
pub const TimeoutError = struct {
    code: TimeoutErrorCode,
    context: ErrorContext,
    description: []const u8,
};

/// Future 错误
pub const FutureError = struct {
    code: FutureErrorCode,
    context: ErrorContext,
    description: []const u8,
};

/// 错误上下文
pub const ErrorContext = struct {
    file: []const u8,
    line: u32,
    function: []const u8,
    timestamp: i64,
};

/// 错误代码枚举
pub const RuntimeErrorCode = enum { initialization_failed, shutdown_failed, worker_panic };
pub const IOErrorCode = enum { read_failed, write_failed, connection_lost, timeout };
pub const MemoryErrorCode = enum { out_of_memory, allocation_failed, corruption };
pub const TimeoutErrorCode = enum { operation_timeout, deadline_exceeded };
pub const FutureErrorCode = enum { poll_failed, waker_failed, state_invalid };

// 🚀 Phase 4: 简化 API - 90% 用户的核心需求
pub usingnamespace @import("core_api.zig");

/// 📚 Phase 4: 分层 API 设计
///
/// 简化 API：最常用的功能，零学习成本
pub const zokio = struct {
    // 核心运行时
    pub const Runtime = @import("core/runtime.zig").ZokioRuntime;
    pub const RuntimeConfig = @import("core/runtime.zig").RuntimeConfig;

    // 基础 Future 系统
    pub const Future = @import("core/future.zig").Future;
    pub const Poll = @import("core/future.zig").Poll;
    pub const Context = @import("core/future.zig").Context;

    // 简化的异步操作
    pub const spawn = @import("core_api.zig").spawn;
    pub const await_fn = @import("core/future.zig").await_fn;
    pub const async_fn = @import("core/future.zig").async_fn;
    pub const async_block = @import("core/future.zig").async_block;

    // 常用工具
    pub const ready = @import("core/future.zig").ready;
    pub const pending = @import("core/future.zig").pending;
    pub const delay = @import("core/future.zig").delay;
    pub const timeout = @import("core/future.zig").timeout;

    // 简化的错误类型
    pub const Error = ZokioError;
};

// 🔧 高级接口 - 需要时才导入（按需加载）
pub const advanced = struct {
    // 条件导入libxev并重新导出，使子模块能够访问
    pub const libxev = if (@import("builtin").is_test)
        (if (@hasDecl(@import("root"), "libxev")) @import("libxev") else null)
    else
        (if (@hasDecl(@import("root"), "libxev")) @import("libxev") else null);

    // 高级运行时特性
    pub const runtime = @import("core/runtime.zig");
    pub const scheduler = @import("core/scheduler.zig");

    // I/O 系统
    pub const io = @import("io/io.zig");
    pub const net = @import("net/mod.zig");
    pub const fs = @import("fs/mod.zig");

    // 工具和扩展
    pub const utils = @import("utils/utils.zig");
    pub const sync = @import("sync/sync.zig");
    pub const time = @import("time/time.zig");
    pub const memory = @import("memory/memory.zig");
    pub const error_system = @import("error/mod.zig");

    // 扩展功能
    pub const ext = @import("ext/mod.zig");
    pub const metrics = ext.metrics;
    pub const testing = ext.testing;
    pub const tracing = ext.tracing;
    pub const bench = ext.bench;
};

/// 🧪 Phase 4: 实验性 API - 早期采用者的前沿功能
pub const experimental = struct {
    // 编译时优化实验
    pub const comptime_runtime = struct {
        /// 编译时运行时生成器
        pub fn generateRuntime(comptime config: anytype) type {
            return @import("core/runtime.zig").ZokioRuntime(config);
        }

        /// 编译时性能分析
        pub fn analyzePerformance(comptime config: anytype) type {
            return struct {
                pub const analysis = config.analyzeCompileTime();
            };
        }
    };

    // 零成本抽象实验
    pub const zero_cost = struct {
        /// 零成本 Future 组合
        pub fn FutureChain(comptime futures: []const type) type {
            return @import("core/future.zig").generateOptimalChain(futures);
        }

        /// 零成本内存管理
        pub fn OptimalAllocator(comptime pattern: anytype) type {
            return @import("memory/memory.zig").OptimalAllocator(pattern);
        }
    };

    // 平台特定优化
    pub const platform_specific = struct {
        /// SIMD 优化操作
        pub const simd_ops = if (builtin.cpu.arch.endian() == .little)
            @import("experimental/simd.zig")
        else
            struct {};

        /// GPU 计算支持
        pub const gpu_compute = if (@hasDecl(@import("root"), "gpu_support"))
            @import("experimental/gpu.zig")
        else
            struct {};

        /// NUMA 感知优化
        pub const numa_aware = if (builtin.os.tag == .linux)
            @import("experimental/numa.zig")
        else
            struct {};
    };

    // 高级调试和分析
    pub const debugging = struct {
        /// 编译时调试信息
        pub const compile_time_debug = @import("experimental/debug.zig");

        /// 性能分析器
        pub const profiler = @import("experimental/profiler.zig");

        /// 内存泄漏检测
        pub const leak_detector = @import("experimental/leak_detector.zig");
    };
};

// 🔧 向后兼容性支持（逐步废弃）
pub const legacy = struct {
    // 高级特性模块导出
    pub const zero_copy = @import("io/zero_copy.zig");
    pub const advanced_timer = @import("runtime/advanced_timer.zig");
    pub const batch_io = @import("net/batch_io.zig");

    // libxev深度集成优化模块
    pub const BatchOperations = @import("runtime/batch_operations.zig");
    pub const MemoryPools = @import("runtime/memory_pools.zig");
    pub const SmartThreadPool = @import("runtime/smart_thread_pool.zig");
    pub const AdvancedEventLoop = @import("runtime/advanced_event_loop.zig");

    // Zokio 9.0 高级特性模块
    pub const LibxevAdvancedFeatures = @import("runtime/libxev_advanced_features.zig");
    pub const ErrorHandling = @import("runtime/error_handling.zig");
    pub const PerformanceMonitor = @import("runtime/performance_monitor.zig");

    // 平台能力检测
    pub const platform = @import("utils/platform.zig");

    // 向后兼容的类型别名
    pub const CompletionBridge = @import("runtime/completion_bridge.zig").CompletionBridge;
    pub const AsyncEventLoop = @import("runtime/async_event_loop.zig").AsyncEventLoop;
    pub const LibxevDriver = @import("io/libxev.zig").LibxevDriver;
    pub const LibxevConfig = @import("io/libxev.zig").LibxevConfig;
    pub const AsyncFile = @import("io/async_file.zig").AsyncFile;
};

// 🚀 专业用户接口（高级功能）
pub const professional = struct {
    // 高性能运行时类型
    pub const RuntimeBuilder = advanced.runtime.RuntimeBuilder;
    pub const RuntimePresets = advanced.runtime.RuntimePresets;
    pub const JoinHandle = advanced.runtime.JoinHandle;

    // 高性能I/O
    pub const AsyncRead = advanced.io.AsyncRead;
    pub const AsyncWrite = advanced.io.AsyncWrite;
    pub const AsyncSeek = advanced.io.AsyncSeek;

    // 高性能网络
    pub const TcpListener = advanced.net.TcpListener;
    pub const TcpStream = advanced.net.TcpStream;
    pub const UdpSocket = advanced.net.UdpSocket;

    // 高性能同步原语
    pub const Mutex = advanced.sync.Mutex;
    pub const RwLock = advanced.sync.RwLock;
    pub const Semaphore = advanced.sync.Semaphore;

    // 高性能内存管理
    pub const MemoryPool = advanced.memory.MemoryPool;
    pub const ObjectPool = advanced.memory.ObjectPool;
};

// 版本信息
pub const version = "0.1.0";

// 编译时配置验证
comptime {
    // 验证Zig版本
    const min_zig_version = std.SemanticVersion{ .major = 0, .minor = 14, .patch = 0 };
    if (builtin.zig_version.order(min_zig_version) == .lt) {
        @compileError("Zokio requires Zig 0.14.0 or later");
    }
}

// 🧪 基础测试
test "Zokio库基础功能" {
    const testing_lib = std.testing;

    // 测试版本信息
    try testing_lib.expect(std.mem.eql(u8, version, "0.1.0"));
}

test "📚 Phase 4: 分层 API 设计验证" {
    const testing = std.testing;

    // 测试简化 API
    try testing.expect(@hasDecl(zokio, "Runtime"));
    try testing.expect(@hasDecl(zokio, "Future"));
    try testing.expect(@hasDecl(zokio, "spawn"));
    try testing.expect(@hasDecl(zokio, "await_fn"));
    try testing.expect(@hasDecl(zokio, "ready"));
    try testing.expect(@hasDecl(zokio, "Error"));

    // 测试高级 API
    try testing.expect(@hasDecl(advanced, "runtime"));
    try testing.expect(@hasDecl(advanced, "scheduler"));
    try testing.expect(@hasDecl(advanced, "io"));
    try testing.expect(@hasDecl(advanced, "memory"));
    try testing.expect(@hasDecl(advanced, "ext"));

    // 测试实验性 API
    try testing.expect(@hasDecl(experimental, "comptime_runtime"));
    try testing.expect(@hasDecl(experimental, "zero_cost"));
    try testing.expect(@hasDecl(experimental, "platform_specific"));
    try testing.expect(@hasDecl(experimental, "debugging"));

    // 测试错误处理系统
    const runtime_error = RuntimeError{
        .code = .initialization_failed,
        .context = ErrorContext{
            .file = "test.zig",
            .line = 42,
            .function = "test_function",
            .timestamp = std.time.timestamp(),
        },
        .description = "Test error",
    };

    const zokio_error = ZokioError{ .runtime = runtime_error };
    try testing.expectEqualStrings("Test error", zokio_error.description());
    try testing.expectEqualStrings("test.zig", zokio_error.context().file);
    try testing.expect(zokio_error.context().line == 42);

    // 测试编译时功能
    const config = @import("core/runtime.zig").RuntimeConfig{};
    const RuntimeType = experimental.comptime_runtime.generateRuntime(config);
    try testing.expect(@hasDecl(RuntimeType, "COMPILE_TIME_INFO"));
}

// 引用所有子模块的测试
test {
    std.testing.refAllDecls(@This());
}
