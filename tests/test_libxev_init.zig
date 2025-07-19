//! 🔧 测试libxev.Loop.init()是否工作
//! 验证libxev初始化是否导致卡住

const std = @import("std");
const testing = std.testing;
const libxev = @import("libxev");

test "测试libxev.Loop.init()基础功能" {
    std.debug.print("\n=== libxev.Loop.init()测试 ===\n", .{});

    // 测试1: 直接创建libxev.Loop
    std.debug.print("1. 测试libxev.Loop.init()...\n", .{});

    var loop = libxev.Loop.init(.{}) catch |err| {
        std.debug.print("❌ libxev.Loop.init()失败: {}\n", .{err});
        return err;
    };
    defer loop.deinit();

    std.debug.print("✅ libxev.Loop.init()成功\n", .{});

    // 测试2: 非阻塞运行
    std.debug.print("2. 测试libxev.Loop.run(.no_wait)...\n", .{});

    const result = loop.run(.no_wait) catch |err| {
        std.debug.print("❌ libxev.Loop.run()失败: {}\n", .{err});
        return err;
    };

    std.debug.print("✅ libxev.Loop.run()成功，结果: {}\n", .{result});

    std.debug.print("✅ libxev基础测试完成\n", .{});
}

// AsyncEventLoop不是公开的，跳过这个测试

test "测试getOrCreateDefaultEventLoop()是否卡住" {
    std.debug.print("\n=== getOrCreateDefaultEventLoop()测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const runtime = @import("zokio").runtime;

    // 测试getOrCreateDefaultEventLoop()
    std.debug.print("1. 测试getOrCreateDefaultEventLoop()...\n", .{});

    const event_loop = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ getOrCreateDefaultEventLoop()失败: {}\n", .{err});
        return err;
    };

    std.debug.print("✅ getOrCreateDefaultEventLoop()成功: {*}\n", .{event_loop});

    // 测试第二次调用（应该返回相同的实例）
    std.debug.print("2. 测试第二次调用getOrCreateDefaultEventLoop()...\n", .{});

    const event_loop2 = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ 第二次getOrCreateDefaultEventLoop()失败: {}\n", .{err});
        return err;
    };

    std.debug.print("✅ 第二次getOrCreateDefaultEventLoop()成功: {*}\n", .{event_loop2});

    // 验证是同一个实例
    if (event_loop == event_loop2) {
        std.debug.print("✅ 两次调用返回相同实例\n", .{});
    } else {
        std.debug.print("❌ 两次调用返回不同实例\n", .{});
        return error.DifferentInstances;
    }

    // 清理全局事件循环，避免内存泄漏
    std.debug.print("3. 清理全局事件循环...\n", .{});
    runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 全局事件循环已清理\n", .{});

    std.debug.print("✅ getOrCreateDefaultEventLoop()测试完成\n", .{});
}
