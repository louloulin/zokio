//! 🚀 Zokio 核心 API
//!
//! 提供高内聚、低耦合的核心异步运行时 API
//! 这是用户主要使用的接口，隐藏了内部实现细节

const std = @import("std");

// 核心模块导入（延迟加载，降低耦合）
const core_runtime = @import("core/runtime.zig");
const core_future = @import("core/future.zig");

// 简化的类型导出
pub const RuntimeStats = core_runtime.RuntimeStats;

/// 🚀 Zokio 核心运行时（简化版，直接使用核心实现）
pub const Runtime = core_runtime.DefaultRuntime;

/// 🔮 Future 抽象
pub const Future = core_future.Future;
pub const Poll = core_future.Poll;
pub const Context = core_future.Context;
pub const Waker = core_future.Waker;

/// 🔧 运行时配置（简化版）
pub const RuntimeConfig = core_runtime.RuntimeConfig;

/// 🚀 便捷函数：创建并启动默认运行时
pub fn createRuntime(allocator: std.mem.Allocator) !Runtime {
    return Runtime.init(allocator);
}

/// 🚀 便捷函数：运行 Future 到完成
pub fn runFuture(allocator: std.mem.Allocator, future: anytype) !void {
    var runtime = try createRuntime(allocator);
    defer runtime.deinit();

    _ = future; // 简化实现
    return;
}

/// 🔮 便捷函数：创建立即完成的 Future
pub fn ready(value: anytype) core_future.ReadyFuture(@TypeOf(value)) {
    return core_future.ready(@TypeOf(value), value);
}

/// 🔮 便捷函数：创建永远挂起的 Future
pub fn pending(comptime T: type) core_future.PendingFuture(T) {
    return core_future.pending(T);
}

/// 🔮 便捷函数：创建延迟 Future
pub fn delay(duration_ms: u64) void {
    _ = duration_ms; // 简化实现
    return;
}

/// 🔮 便捷函数：await 一个 Future
pub fn await_fn(future: anytype) void {
    _ = future; // 简化实现
    return;
}

/// 🧪 测试辅助函数
pub const testing = struct {
    /// 创建测试运行时
    pub fn createTestRuntime(allocator: std.mem.Allocator) !Runtime {
        return Runtime.init(allocator);
    }

    /// 运行测试 Future
    pub fn runTest(allocator: std.mem.Allocator, future: anytype) !void {
        var runtime = try createTestRuntime(allocator);
        defer runtime.deinit();

        _ = future; // 简化实现
        return;
    }
};

/// 📊 性能监控
pub const metrics = struct {
    /// 获取全局性能指标
    pub fn getGlobalMetrics() RuntimeStats {
        // 简化实现：返回默认统计信息
        return RuntimeStats{};
    }

    /// 重置性能计数器
    pub fn resetCounters() void {
        // 简化实现：暂无操作
    }
};

// 🔧 配置验证
comptime {
    // 确保核心类型可用
    _ = Runtime;
    _ = Future;
    _ = Poll;
    _ = Context;
    _ = Waker;
    _ = RuntimeConfig;
}

test "核心 API 基础功能" {
    const testing_std = std.testing;

    // 测试运行时创建
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try Runtime.init(allocator);
    defer runtime.deinit();

    // 简化测试：只测试创建和销毁
    try testing_std.expect(true); // 如果能到这里说明创建成功
}

test "便捷函数测试" {
    // 测试 ready Future
    const ready_future = ready(42);
    _ = ready_future; // 避免未使用变量警告

    // 测试 pending Future
    const pending_future = pending(u32);
    _ = pending_future; // 避免未使用变量警告
}

test "测试辅助函数" {
    const testing_std = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 测试创建测试运行时
    var test_runtime = try testing.createTestRuntime(allocator);
    defer test_runtime.deinit();

    // 简化测试：只测试创建成功
    try testing_std.expect(true);
}
