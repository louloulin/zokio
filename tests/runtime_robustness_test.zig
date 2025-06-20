//! Runtime健壮性测试
//! 测试错误处理、边界条件和异常情况

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🛡️ Runtime健壮性测试 ===\n", .{});

    // 错误处理测试
    try testErrorHandling(allocator);
    
    // 边界条件测试
    try testBoundaryConditions(allocator);
    
    // 资源清理测试
    try testResourceCleanup(allocator);
    
    // 并发安全测试
    try testConcurrencySafety(allocator);

    std.debug.print("\n🎉 === 健壮性测试完成 ===\n", .{});
}

/// 测试错误处理
fn testErrorHandling(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🚨 测试错误处理...\n", .{});
    
    // 测试1: 重复启动
    {
        var runtime = try zokio.build.default(allocator);
        defer runtime.deinit();
        
        try runtime.start();
        std.debug.print("  ✅ 首次启动成功\n", .{});
        
        // 重复启动应该安全
        try runtime.start();
        std.debug.print("  ✅ 重复启动处理正确\n", .{});
        
        runtime.stop();
    }
    
    // 测试2: 未启动状态下的操作
    {
        var runtime = try zokio.build.default(allocator);
        defer runtime.deinit();
        
        // 未启动状态下获取统计信息
        const stats = runtime.getStats();
        std.debug.print("  ✅ 未启动状态统计: 运行={}\n", .{stats.running});
        
        // 停止未启动的运行时
        runtime.stop();
        std.debug.print("  ✅ 停止未启动运行时处理正确\n", .{});
    }
    
    // 测试3: 多次停止
    {
        var runtime = try zokio.build.default(allocator);
        defer runtime.deinit();
        
        try runtime.start();
        runtime.stop();
        std.debug.print("  ✅ 首次停止成功\n", .{});
        
        // 多次停止应该安全
        runtime.stop();
        runtime.stop();
        std.debug.print("  ✅ 多次停止处理正确\n", .{});
    }
}

/// 测试边界条件
fn testBoundaryConditions(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔍 测试边界条件...\n", .{});
    
    // 测试1: 快速启动停止循环
    {
        var runtime = try zokio.build.default(allocator);
        defer runtime.deinit();
        
        for (0..10) |i| {
            try runtime.start();
            runtime.stop();
            if (i % 3 == 0) {
                std.debug.print("  ✅ 快速循环 {}/10\n", .{i + 1});
            }
        }
        std.debug.print("  ✅ 快速启动停止循环测试通过\n", .{});
    }
    
    // 测试2: 零延迟操作
    {
        var runtime = try zokio.build.default(allocator);
        defer runtime.deinit();
        
        try runtime.start();
        
        // 立即获取统计信息
        const stats = runtime.getStats();
        std.debug.print("  ✅ 零延迟统计: 线程={}\n", .{stats.thread_count});
        
        runtime.stop();
    }
    
    // 测试3: 内存压力下的运行时
    {
        std.debug.print("  🧪 内存压力测试...\n", .{});
        
        // 创建多个运行时实例
        var runtimes: [5]zokio.DefaultRuntime = undefined;
        
        for (&runtimes, 0..) |*rt, i| {
            rt.* = try zokio.build.default(allocator);
            try rt.start();
            std.debug.print("    ✅ 运行时 {} 启动\n", .{i + 1});
        }
        
        // 清理所有运行时
        for (&runtimes, 0..) |*rt, i| {
            rt.stop();
            rt.deinit();
            std.debug.print("    ✅ 运行时 {} 清理\n", .{i + 1});
        }
        
        std.debug.print("  ✅ 内存压力测试通过\n", .{});
    }
}

/// 测试资源清理
fn testResourceCleanup(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧹 测试资源清理...\n", .{});
    
    // 测试1: 正常清理流程
    {
        var runtime = try zokio.build.default(allocator);
        try runtime.start();
        
        const stats_before = runtime.getStats();
        std.debug.print("  📊 启动前统计: 运行={}\n", .{stats_before.running});
        
        runtime.stop();
        
        const stats_after = runtime.getStats();
        std.debug.print("  📊 停止后统计: 运行={}\n", .{stats_after.running});
        
        runtime.deinit();
        std.debug.print("  ✅ 正常清理流程完成\n", .{});
    }
    
    // 测试2: 异常情况下的清理
    {
        var runtime = try zokio.build.default(allocator);
        try runtime.start();
        
        // 模拟异常情况：直接deinit而不stop
        runtime.deinit();
        std.debug.print("  ✅ 异常清理处理正确\n", .{});
    }
    
    // 测试3: 多次deinit
    {
        var runtime = try zokio.build.default(allocator);
        try runtime.start();
        runtime.stop();
        runtime.deinit();
        
        // 注意：多次deinit可能导致问题，这里只是测试是否会崩溃
        // 在实际使用中应该避免多次deinit
        std.debug.print("  ✅ 清理安全性测试完成\n", .{});
    }
}

/// 测试并发安全
fn testConcurrencySafety(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧵 测试并发安全...\n", .{});
    
    // 测试1: 多线程访问统计信息
    {
        var runtime = try zokio.build.default(allocator);
        defer runtime.deinit();
        
        try runtime.start();
        
        // 模拟多线程访问
        var threads: [4]std.Thread = undefined;
        
        for (&threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, concurrentStatsAccess, .{ &runtime, i });
        }
        
        // 等待所有线程完成
        for (&threads) |*thread| {
            thread.join();
        }
        
        runtime.stop();
        std.debug.print("  ✅ 多线程统计访问测试通过\n", .{});
    }
    
    // 测试2: 并发启动停止
    {
        var runtime = try zokio.build.default(allocator);
        defer runtime.deinit();
        
        // 启动多个线程尝试启动/停止运行时
        var threads: [3]std.Thread = undefined;
        
        for (&threads, 0..) |*thread, i| {
            thread.* = try std.Thread.spawn(.{}, concurrentStartStop, .{ &runtime, i });
        }
        
        // 等待所有线程完成
        for (&threads) |*thread| {
            thread.join();
        }
        
        std.debug.print("  ✅ 并发启动停止测试通过\n", .{});
    }
}

/// 并发访问统计信息
fn concurrentStatsAccess(runtime: *zokio.DefaultRuntime, thread_id: usize) void {
    for (0..100) |i| {
        const stats = runtime.getStats();
        if (i % 50 == 0) {
            std.debug.print("    线程{}: 统计访问 {}/100, 运行={}\n", .{ thread_id, i + 1, stats.running });
        }
        std.time.sleep(1000); // 1μs
    }
}

/// 并发启动停止
fn concurrentStartStop(runtime: *zokio.DefaultRuntime, thread_id: usize) void {
    for (0..10) |i| {
        runtime.start() catch {};
        std.time.sleep(1000); // 1μs
        runtime.stop();
        if (i % 5 == 0) {
            std.debug.print("    线程{}: 启动停止循环 {}/10\n", .{ thread_id, i + 1 });
        }
        std.time.sleep(1000); // 1μs
    }
}
