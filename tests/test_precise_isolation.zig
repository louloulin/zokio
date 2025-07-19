//! 🔧 精确隔离测试
//! 逐个测试AsyncEventLoop的每个组件

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "测试全局互斥锁" {
    std.debug.print("\n=== 全局互斥锁测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 直接测试全局互斥锁操作
    std.debug.print("1. 测试全局互斥锁lock/unlock...\n", .{});

    // 模拟getOrCreateDefaultEventLoop的互斥锁操作
    const runtime = @import("zokio").runtime;

    // 获取全局互斥锁的引用（通过调用函数间接测试）
    std.debug.print("2. 测试第一次getOrCreateDefaultEventLoop调用...\n", .{});
    const loop1 = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ 第一次调用失败: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ 第一次调用成功: {*}\n", .{loop1});

    std.debug.print("3. 测试第二次getOrCreateDefaultEventLoop调用...\n", .{});
    const loop2 = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ 第二次调用失败: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ 第二次调用成功: {*}\n", .{loop2});

    // 验证是同一个实例
    if (loop1 == loop2) {
        std.debug.print("✅ 两次调用返回相同实例\n", .{});
    } else {
        std.debug.print("❌ 两次调用返回不同实例\n", .{});
        return error.DifferentInstances;
    }

    // 清理
    runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 全局互斥锁测试完成\n", .{});
}

test "测试通过公开API创建事件循环" {
    std.debug.print("\n=== 公开API事件循环测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const runtime = @import("zokio").runtime;

    std.debug.print("1. 通过公开API创建事件循环...\n", .{});

    const event_loop = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ getOrCreateDefaultEventLoop失败: {}\n", .{err});
        return err;
    };

    std.debug.print("✅ 事件循环创建成功: {*}\n", .{event_loop});

    // 清理
    runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 事件循环清理完成\n", .{});
}

test "测试重复调用getOrCreateDefaultEventLoop" {
    std.debug.print("\n=== 重复调用测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const runtime = @import("zokio").runtime;

    std.debug.print("1. 第一次调用getOrCreateDefaultEventLoop...\n", .{});
    const event_loop1 = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ 第一次调用失败: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ 第一次调用成功: {*}\n", .{event_loop1});

    std.debug.print("2. 第二次调用getOrCreateDefaultEventLoop...\n", .{});
    const event_loop2 = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ 第二次调用失败: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ 第二次调用成功: {*}\n", .{event_loop2});

    // 验证是同一个实例
    if (event_loop1 == event_loop2) {
        std.debug.print("✅ 两次调用返回相同实例\n", .{});
    } else {
        std.debug.print("❌ 两次调用返回不同实例\n", .{});
        return error.DifferentInstances;
    }

    // 清理
    runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 重复调用测试完成\n", .{});
}

test "测试并发访问全局事件循环" {
    std.debug.print("\n=== 并发访问测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const runtime = @import("zokio").runtime;

    // 快速连续调用多次
    std.debug.print("1. 快速连续调用getOrCreateDefaultEventLoop...\n", .{});

    // 使用不透明指针类型，避免直接引用AsyncEventLoop
    var loops: [5]?*anyopaque = undefined;

    for (&loops, 0..) |*loop_ptr, i| {
        std.debug.print("   第{}次调用...\n", .{i + 1});
        const event_loop = runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
            std.debug.print("❌ 第{}次调用失败: {}\n", .{ i + 1, err });
            return err;
        };
        loop_ptr.* = @ptrCast(event_loop);
        std.debug.print("   第{}次调用成功: {*}\n", .{ i + 1, event_loop });
    }

    // 验证所有指针都相同
    std.debug.print("2. 验证所有指针一致性...\n", .{});
    for (loops[1..], 1..) |loop_ptr, i| {
        if (loop_ptr != loops[0]) {
            std.debug.print("❌ 第{}个指针不一致: {*} vs {*}\n", .{ i + 1, loop_ptr, loops[0] });
            return error.InconsistentPointers;
        }
    }
    std.debug.print("✅ 所有指针一致\n", .{});

    // 清理
    runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 并发访问测试完成\n", .{});
}
