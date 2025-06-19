//! 🚀 简单的运行时测试
//!
//! 验证新的高性能运行时基本功能

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 Zokio运行时基本功能测试 ===\n\n", .{});

    // 测试1: 验证运行时类型存在
    try testRuntimeTypes();

    // 测试2: 基本运行时创建和销毁
    try testBasicRuntimeLifecycle(allocator);

    // 测试3: 编译时信息验证
    try testCompileTimeInfo();

    std.debug.print("\n=== 🎉 基本功能测试完成 ===\n", .{});
}

/// 测试运行时类型存在
fn testRuntimeTypes() !void {
    std.debug.print("🔧 测试运行时类型...\n", .{});

    // 验证所有运行时类型都存在
    std.debug.print("  ✅ HighPerformanceRuntime: {}\n", .{@TypeOf(zokio.HighPerformanceRuntime)});
    std.debug.print("  ✅ LowLatencyRuntime: {}\n", .{@TypeOf(zokio.LowLatencyRuntime)});
    std.debug.print("  ✅ IOIntensiveRuntime: {}\n", .{@TypeOf(zokio.IOIntensiveRuntime)});
    std.debug.print("  ✅ MemoryOptimizedRuntime: {}\n", .{@TypeOf(zokio.MemoryOptimizedRuntime)});
    std.debug.print("  ✅ BalancedRuntime: {}\n", .{@TypeOf(zokio.BalancedRuntime)});
    std.debug.print("  ✅ DefaultRuntime: {}\n", .{@TypeOf(zokio.DefaultRuntime)});

    std.debug.print("  🎉 所有运行时类型验证通过\n", .{});
}

/// 测试基本运行时生命周期
fn testBasicRuntimeLifecycle(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔄 测试运行时生命周期...\n", .{});

    // 测试默认运行时
    std.debug.print("  📋 测试DefaultRuntime...\n", .{});
    {
        var runtime = try zokio.DefaultRuntime.init(allocator);
        defer runtime.deinit();
        std.debug.print("    ✅ 初始化成功\n", .{});

        try runtime.start();
        std.debug.print("    ✅ 启动成功\n", .{});

        runtime.stop();
        std.debug.print("    ✅ 停止成功\n", .{});
    }

    // 测试高性能运行时
    std.debug.print("  📋 测试HighPerformanceRuntime...\n", .{});
    {
        var runtime = try zokio.HighPerformanceRuntime.init(allocator);
        defer runtime.deinit();
        std.debug.print("    ✅ 初始化成功\n", .{});

        try runtime.start();
        std.debug.print("    ✅ 启动成功\n", .{});

        runtime.stop();
        std.debug.print("    ✅ 停止成功\n", .{});
    }

    std.debug.print("  🎉 运行时生命周期测试通过\n", .{});
}

/// 测试编译时信息
fn testCompileTimeInfo() !void {
    std.debug.print("\n📊 测试编译时信息...\n", .{});

    // 测试高性能运行时编译时信息
    std.debug.print("  🔥 HighPerformanceRuntime编译时信息:\n", .{});
    std.debug.print("    平台: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.platform});
    std.debug.print("    架构: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.architecture});
    std.debug.print("    工作线程: {}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("    I/O后端: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.io_backend});
    std.debug.print("    配置名称: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("    内存策略: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("    性能配置: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.performance_profile});
    std.debug.print("    libxev启用: {}\n", .{zokio.HighPerformanceRuntime.LIBXEV_ENABLED});

    // 测试低延迟运行时编译时信息
    std.debug.print("\n  ⚡ LowLatencyRuntime编译时信息:\n", .{});
    std.debug.print("    配置名称: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("    内存策略: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("    性能配置: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.performance_profile});

    // 测试I/O密集型运行时编译时信息
    std.debug.print("\n  🌐 IOIntensiveRuntime编译时信息:\n", .{});
    std.debug.print("    配置名称: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("    内存策略: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("    性能配置: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.performance_profile});

    std.debug.print("\n  🎉 编译时信息验证通过\n", .{});
}
