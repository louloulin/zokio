//! Zokio: 基于Zig特性的下一代异步运行时
//!
//! Zokio是一个充分发挥Zig语言独特优势的原生异步运行时系统，
//! 通过编译时元编程、零成本抽象、显式内存管理等特性，
//! 创造一个真正体现"Zig哲学"的高性能异步运行时。

const std = @import("std");
const builtin = @import("builtin");
const config = @import("config");

// 条件导入libxev并重新导出，使子模块能够访问
pub const libxev = if (@import("builtin").is_test)
    (if (@hasDecl(@import("root"), "libxev")) @import("libxev") else null)
else
    (if (@hasDecl(@import("root"), "libxev")) @import("libxev") else null);

// 核心模块导出
pub const runtime = @import("runtime/runtime.zig");
pub const future = @import("future/future.zig");
pub const scheduler = @import("scheduler/scheduler.zig");
pub const io = @import("io/io.zig");
pub const sync = @import("sync/sync.zig");
pub const time = @import("time/time.zig");
pub const timer = @import("time/timer.zig");
pub const memory = @import("memory/memory.zig");
pub const net = @import("net/mod.zig");
pub const metrics = @import("metrics/metrics.zig");
pub const testing = @import("testing/testing.zig");
pub const utils = @import("utils/utils.zig");

// 新增的高级功能模块
pub const fs = @import("fs/mod.zig");
pub const tracing = @import("tracing/tracer.zig");
pub const bench = @import("bench/mod.zig");

// 平台能力检测
pub const platform = @import("utils/platform.zig");

// 类型别名导出
pub const Runtime = runtime.Runtime;
pub const Future = future.Future;
pub const Poll = future.Poll;
pub const Context = future.Context;
pub const Waker = future.Waker;

// 便捷函数导出
pub const ZokioRuntime = runtime.ZokioRuntime;
pub const async_fn = future.async_fn;
pub const async_fn_with_params = future.async_fn_with_params;
pub const runtime_spawn = runtime.spawn;
pub const block_on = runtime.block_on;

// Future便捷函数导出
pub const ready = future.ready;
pub const pending = future.pending;
pub const delay = future.delay;
pub const timeout = future.timeout;
pub const await_future = future.await_future;

// 🚀 高性能运行时导出
pub const RuntimeBuilder = runtime.RuntimeBuilder;
pub const RuntimePresets = runtime.RuntimePresets;
pub const JoinHandle = runtime.JoinHandle;

// 🔥 高性能运行时类型
pub const HighPerformanceRuntime = runtime.HighPerformanceRuntime;
pub const LowLatencyRuntime = runtime.LowLatencyRuntime;
pub const IOIntensiveRuntime = runtime.IOIntensiveRuntime;
pub const MemoryOptimizedRuntime = runtime.MemoryOptimizedRuntime;
pub const BalancedRuntime = runtime.BalancedRuntime;
pub const DefaultRuntime = runtime.DefaultRuntime;

// 🚀 便捷函数
pub const builder = runtime.builder;
pub const build = runtime.build;
pub const asyncMain = runtime.asyncMain;
pub const initGlobalRuntime = runtime.initGlobalRuntime;
pub const shutdownGlobalRuntime = runtime.shutdownGlobalRuntime;

// ⚠️ 已弃用：SimpleRuntime (使用DefaultRuntime替代)
pub const SimpleRuntime = runtime.DefaultRuntime;

// 🚀 核心async/await API导出 - 统一到zokio命名空间
pub const async_block_api = @import("future/async_block.zig");
pub const async_block = async_block_api.async_block;
// 使用更稳定的 await_fn 实现，避免无限循环
pub const await_fn = future.await_fn;

// 🔥 从future模块导出的async/await API
pub const async_fn_future = future.async_fn;
pub const async_fn_with_params_future = future.async_fn_with_params;
pub const async_block_future = future.async_block;
pub const await_fn_future = future.await_fn;

// CompletionBridge导出
pub const CompletionBridge = @import("runtime/completion_bridge.zig").CompletionBridge;

// 配置类型导出
pub const RuntimeConfig = runtime.RuntimeConfig;

// 🚀 事件循环相关导出
pub const AsyncEventLoop = @import("runtime/async_event_loop.zig").AsyncEventLoop;
pub const getCurrentEventLoop = runtime.getCurrentEventLoop;
pub const setCurrentEventLoop = runtime.setCurrentEventLoop;
pub const getOrCreateDefaultEventLoop = runtime.getOrCreateDefaultEventLoop;

// 🚀 libxev I/O系统导出
pub const libxev_io = struct {
    pub const LibxevDriver = @import("io/libxev.zig").LibxevDriver;
    pub const LibxevConfig = @import("io/libxev.zig").LibxevConfig;
    pub const IoOpStatus = @import("io/libxev.zig").IoOpStatus;
    pub const IoStats = @import("io/libxev.zig").IoStats;
};

// 🚀 异步I/O类型导出
pub const AsyncFile = @import("io/async_file.zig").AsyncFile;
pub const AsyncTcpStream = @import("io/async_net.zig").AsyncTcpStream;
pub const AsyncTcpListener = @import("io/async_net.zig").AsyncTcpListener;
pub const IoConfig = io.IoConfig;
pub const MemoryConfig = memory.MemoryConfig;

// 版本信息
pub const version = "0.1.0";

// 编译时配置验证
comptime {
    // 验证Zig版本
    const min_zig_version = std.SemanticVersion{ .major = 0, .minor = 14, .patch = 0 };
    if (builtin.zig_version.order(min_zig_version) == .lt) {
        @compileError("Zokio requires Zig 0.14.0 or later");
    }

    // 验证平台支持
    if (!platform.PlatformCapabilities.is_supported) {
        @compileError("Unsupported platform for Zokio");
    }

    // 编译时配置检查
    if (config.enable_io_uring and !platform.PlatformCapabilities.io_uring_available) {
        // io_uring请求但不可用，将使用备用I/O后端
    }

    if (config.enable_numa and !platform.PlatformCapabilities.numa_available) {
        // NUMA优化请求但不可用，将使用标准内存分配
    }
}

// 编译时性能报告生成
pub const PERFORMANCE_REPORT = generatePerformanceReport();

fn generatePerformanceReport() PerformanceReport {
    return PerformanceReport{
        .platform = @tagName(builtin.os.tag),
        .architecture = @tagName(builtin.cpu.arch),
        .io_backend = platform.PlatformCapabilities.preferred_io_backend,
        .simd_available = platform.PlatformCapabilities.simd_available,
        .numa_available = platform.PlatformCapabilities.numa_available,
        .cache_line_size = platform.PlatformCapabilities.cache_line_size,
        .features_enabled = .{
            .metrics = config.enable_metrics,
            .tracing = config.enable_tracing,
            .numa = config.enable_numa,
            .io_uring = config.enable_io_uring,
            .simd = config.enable_simd,
        },
    };
}

const PerformanceReport = struct {
    platform: []const u8,
    architecture: []const u8,
    io_backend: []const u8,
    simd_available: bool,
    numa_available: bool,
    cache_line_size: u32,
    features_enabled: struct {
        metrics: bool,
        tracing: bool,
        numa: bool,
        io_uring: bool,
        simd: bool,
    },
};

// 测试
test "Zokio库基础功能" {
    const testing_lib = std.testing;

    // 测试版本信息
    try testing_lib.expect(std.mem.eql(u8, version, "0.1.0"));

    // 测试编译时报告
    try testing_lib.expect(PERFORMANCE_REPORT.platform.len > 0);
    try testing_lib.expect(PERFORMANCE_REPORT.architecture.len > 0);

    // 测试平台能力
    try testing_lib.expect(platform.PlatformCapabilities.cache_line_size > 0);
}

test "编译时配置验证" {
    const testing_lib = std.testing;

    // 测试配置类型
    const test_config = RuntimeConfig{
        .worker_threads = 4,
        .enable_work_stealing = true,
        .enable_io_uring = true,
    };

    // 编译时验证应该通过
    comptime test_config.validate();

    try testing_lib.expect(test_config.worker_threads.? == 4);
}

// 引用所有子模块的测试
test {
    std.testing.refAllDecls(@This());
}
