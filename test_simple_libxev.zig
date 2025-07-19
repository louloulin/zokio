//! 简化的libxev测试，用于诊断卡住问题

const std = @import("std");
const libxev = @import("libxev");

pub fn main() !void {
    std.debug.print("🔧 开始简化libxev测试...\n", .{});
    
    // 测试1: 基础libxev初始化
    std.debug.print("1. 测试libxev.Loop.init()...\n", .{});
    
    var loop = libxev.Loop.init(.{}) catch |err| {
        std.debug.print("❌ libxev初始化失败: {}\n", .{err});
        return;
    };
    defer loop.deinit();
    
    std.debug.print("✅ libxev初始化成功\n", .{});
    
    // 测试2: 运行一次事件循环
    std.debug.print("2. 测试loop.run(.no_wait)...\n", .{});
    
    const start_time = std.time.nanoTimestamp();
    
    loop.run(.no_wait) catch |err| {
        std.debug.print("❌ 事件循环运行失败: {}\n", .{err});
        return;
    };
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    
    std.debug.print("✅ 事件循环运行成功，耗时: {} ns\n", .{duration_ns});
    
    // 测试3: 多次运行
    std.debug.print("3. 测试多次运行事件循环...\n", .{});
    
    for (0..10) |i| {
        loop.run(.no_wait) catch |err| {
            std.debug.print("❌ 第{}次运行失败: {}\n", .{ i, err });
            return;
        };
    }
    
    std.debug.print("✅ 多次运行成功\n", .{});
    std.debug.print("🎉 所有libxev测试通过！\n", .{});
}
