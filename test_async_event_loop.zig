//! 简化的AsyncEventLoop测试，用于诊断卡住问题

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    std.debug.print("🔧 开始AsyncEventLoop测试...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // 测试1: AsyncEventLoop初始化
    std.debug.print("1. 测试AsyncEventLoop.init()...\n", .{});
    
    var event_loop = zokio.AsyncEventLoop.init(allocator) catch |err| {
        std.debug.print("❌ AsyncEventLoop初始化失败: {}\n", .{err});
        return;
    };
    defer event_loop.deinit();
    
    std.debug.print("✅ AsyncEventLoop初始化成功\n", .{});
    
    // 测试2: 设置事件循环
    std.debug.print("2. 测试setCurrentEventLoop()...\n", .{});
    
    zokio.setCurrentEventLoop(&event_loop);
    
    const current = zokio.getCurrentEventLoop();
    if (current == null) {
        std.debug.print("❌ getCurrentEventLoop返回null\n", .{});
        return;
    }
    
    if (current != &event_loop) {
        std.debug.print("❌ getCurrentEventLoop返回错误的指针\n", .{});
        return;
    }
    
    std.debug.print("✅ 事件循环设置成功\n", .{});
    
    // 测试3: runOnce
    std.debug.print("3. 测试runOnce()...\n", .{});
    
    event_loop.runOnce() catch |err| {
        std.debug.print("❌ runOnce失败: {}\n", .{err});
        return;
    };
    
    std.debug.print("✅ runOnce成功\n", .{});
    
    // 清理
    zokio.setCurrentEventLoop(null);
    
    std.debug.print("🎉 所有AsyncEventLoop测试通过！\n", .{});
}
