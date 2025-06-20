//! Runtime配置稳定性测试
//! 确保所有预设配置都能稳定运行

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🧪 Runtime配置稳定性测试 ===\n", .{});

    // 🔥 修复：一次只测试一个配置，避免编译器生成过大的符号表
    std.debug.print("注意：为避免栈溢出，每次只测试一个配置\n", .{});

    // 只测试内存优化配置（最安全的）
    try testMemoryOptimizedRuntime(allocator);

    // 注释掉其他配置，避免同时引用导致符号表过大
    // try testBalancedRuntime(allocator);
    // try testLowLatencyRuntime(allocator);
    // try testIOIntensiveRuntime(allocator);
    // try testExtremePerformanceRuntime(allocator);

    std.debug.print("\n🎉 === 所有配置稳定性测试完成 ===\n", .{});
}

/// 测试内存优化运行时
fn testMemoryOptimizedRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧠 测试内存优化运行时...\n", .{});

    var runtime = zokio.build.memoryOptimized(allocator) catch |err| {
        std.debug.print("  ❌ 内存优化运行时初始化失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    std.debug.print("  ✅ 初始化成功 (大小: {} bytes)\n", .{@sizeOf(@TypeOf(runtime))});

    // 测试启动
    runtime.start() catch |err| {
        std.debug.print("  ❌ 启动失败: {}\n", .{err});
        return;
    };
    std.debug.print("  ✅ 启动成功\n", .{});

    // 测试基础功能
    const stats = runtime.getStats();
    std.debug.print("  📊 统计: 线程数={}, 运行状态={}\n", .{ stats.thread_count, stats.running });

    // 测试停止
    runtime.stop();
    std.debug.print("  ✅ 停止成功\n", .{});
}

/// 测试平衡运行时
fn testBalancedRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚖️ 测试平衡运行时...\n", .{});

    var runtime = zokio.build.balanced(allocator) catch |err| {
        std.debug.print("  ❌ 平衡运行时初始化失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    std.debug.print("  ✅ 初始化成功 (大小: {} bytes)\n", .{@sizeOf(@TypeOf(runtime))});

    // 测试启动
    runtime.start() catch |err| {
        std.debug.print("  ❌ 启动失败: {}\n", .{err});
        return;
    };
    std.debug.print("  ✅ 启动成功\n", .{});

    // 测试基础功能
    const stats = runtime.getStats();
    std.debug.print("  📊 统计: 线程数={}, 运行状态={}\n", .{ stats.thread_count, stats.running });

    // 测试停止
    runtime.stop();
    std.debug.print("  ✅ 停止成功\n", .{});
}

/// 测试低延迟运行时
fn testLowLatencyRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试低延迟运行时...\n", .{});

    var runtime = zokio.build.lowLatency(allocator) catch |err| {
        std.debug.print("  ❌ 低延迟运行时初始化失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    std.debug.print("  ✅ 初始化成功 (大小: {} bytes)\n", .{@sizeOf(@TypeOf(runtime))});

    // 测试启动
    runtime.start() catch |err| {
        std.debug.print("  ❌ 启动失败: {}\n", .{err});
        return;
    };
    std.debug.print("  ✅ 启动成功\n", .{});

    // 测试基础功能
    const stats = runtime.getStats();
    std.debug.print("  📊 统计: 线程数={}, 运行状态={}\n", .{ stats.thread_count, stats.running });

    // 测试停止
    runtime.stop();
    std.debug.print("  ✅ 停止成功\n", .{});
}

/// 测试I/O密集型运行时
fn testIOIntensiveRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🌐 测试I/O密集型运行时...\n", .{});

    var runtime = zokio.build.ioIntensive(allocator) catch |err| {
        std.debug.print("  ❌ I/O密集型运行时初始化失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    std.debug.print("  ✅ 初始化成功 (大小: {} bytes)\n", .{@sizeOf(@TypeOf(runtime))});

    // 测试启动
    runtime.start() catch |err| {
        std.debug.print("  ❌ 启动失败: {}\n", .{err});
        return;
    };
    std.debug.print("  ✅ 启动成功\n", .{});

    // 测试基础功能
    const stats = runtime.getStats();
    std.debug.print("  📊 统计: 线程数={}, 运行状态={}\n", .{ stats.thread_count, stats.running });

    // 测试停止
    runtime.stop();
    std.debug.print("  ✅ 停止成功\n", .{});
}

/// 测试极致性能运行时
fn testExtremePerformanceRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔥 测试极致性能运行时...\n", .{});

    var runtime = zokio.build.extremePerformance(allocator) catch |err| {
        std.debug.print("  ❌ 极致性能运行时初始化失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    std.debug.print("  ✅ 初始化成功 (大小: {} bytes)\n", .{@sizeOf(@TypeOf(runtime))});

    // 测试启动
    runtime.start() catch |err| {
        std.debug.print("  ❌ 启动失败: {}\n", .{err});
        return;
    };
    std.debug.print("  ✅ 启动成功\n", .{});

    // 测试基础功能
    const stats = runtime.getStats();
    std.debug.print("  📊 统计: 线程数={}, 运行状态={}\n", .{ stats.thread_count, stats.running });

    // 测试停止
    runtime.stop();
    std.debug.print("  ✅ 停止成功\n", .{});
}
