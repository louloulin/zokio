//! Zokio: 基于Zig特性的下一代异步运行时
//!
//! Zokio是一个充分发挥Zig语言独特优势的原生异步运行时系统，
//! 通过编译时元编程、零成本抽象、显式内存管理等特性，
//! 创造一个真正体现"Zig哲学"的高性能异步运行时。

const std = @import("std");
const builtin = @import("builtin");

// 🚀 核心 API - 主要用户接口（高内聚，低耦合）
pub usingnamespace @import("core_api.zig");

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

// 引用所有子模块的测试
test {
    std.testing.refAllDecls(@This());
}
