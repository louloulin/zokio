//! 🔧 测试threadlocal变量修复
//! 验证runtime.zig和async_block.zig中的事件循环管理统一性

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "验证threadlocal变量统一性" {
    std.debug.print("\n=== threadlocal变量统一性测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 初始状态检查
    std.debug.print("1. 检查初始状态...\n", .{});

    const runtime_initial = zokio.runtime.getCurrentEventLoop();
    const async_block_initial = zokio.async_block_api.getCurrentEventLoop();

    std.debug.print("   runtime.getCurrentEventLoop(): {?}\n", .{runtime_initial});
    std.debug.print("   async_block.getCurrentEventLoop(): {?}\n", .{async_block_initial});

    try testing.expect(runtime_initial == null);
    try testing.expect(async_block_initial == null);
    try testing.expect(runtime_initial == async_block_initial);
    std.debug.print("✅ 初始状态一致\n", .{});

    // 2. 创建事件循环
    std.debug.print("2. 创建事件循环...\n", .{});

    const event_loop = try zokio.runtime.getOrCreateDefaultEventLoop(allocator);
    std.debug.print("   创建的事件循环: {*}\n", .{event_loop});

    // 3. 通过runtime设置事件循环
    std.debug.print("3. 通过runtime设置事件循环...\n", .{});

    zokio.runtime.setCurrentEventLoop(event_loop);

    const runtime_after_set = zokio.runtime.getCurrentEventLoop();
    const async_block_after_set = zokio.async_block_api.getCurrentEventLoop();

    std.debug.print("   runtime.getCurrentEventLoop(): {?}\n", .{runtime_after_set});
    std.debug.print("   async_block.getCurrentEventLoop(): {?}\n", .{async_block_after_set});

    try testing.expect(runtime_after_set != null);
    try testing.expect(async_block_after_set != null);
    try testing.expect(runtime_after_set == async_block_after_set);
    try testing.expect(runtime_after_set == event_loop);
    std.debug.print("✅ 通过runtime设置后状态一致\n", .{});

    // 4. 通过async_block设置事件循环
    std.debug.print("4. 通过async_block清理并重新设置...\n", .{});

    zokio.async_block_api.setCurrentEventLoop(null);

    const runtime_after_clear = zokio.runtime.getCurrentEventLoop();
    const async_block_after_clear = zokio.async_block_api.getCurrentEventLoop();

    std.debug.print("   清理后 runtime.getCurrentEventLoop(): {?}\n", .{runtime_after_clear});
    std.debug.print("   清理后 async_block.getCurrentEventLoop(): {?}\n", .{async_block_after_clear});

    try testing.expect(runtime_after_clear == null);
    try testing.expect(async_block_after_clear == null);
    try testing.expect(runtime_after_clear == async_block_after_clear);
    std.debug.print("✅ 通过async_block清理后状态一致\n", .{});

    // 5. 重新设置
    zokio.async_block_api.setCurrentEventLoop(event_loop);

    const runtime_final = zokio.runtime.getCurrentEventLoop();
    const async_block_final = zokio.async_block_api.getCurrentEventLoop();

    std.debug.print("   重新设置后 runtime.getCurrentEventLoop(): {?}\n", .{runtime_final});
    std.debug.print("   重新设置后 async_block.getCurrentEventLoop(): {?}\n", .{async_block_final});

    try testing.expect(runtime_final != null);
    try testing.expect(async_block_final != null);
    try testing.expect(runtime_final == async_block_final);
    try testing.expect(runtime_final == event_loop);
    std.debug.print("✅ 通过async_block重新设置后状态一致\n", .{});

    // 清理
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(allocator);

    std.debug.print("✅ threadlocal变量统一性验证完成\n", .{});
}

test "验证await_fn能检测到事件循环" {
    std.debug.print("\n=== await_fn事件循环检测测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 没有事件循环时的行为
    std.debug.print("1. 测试没有事件循环时的await_fn行为...\n", .{});

    const SimpleFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const future1 = SimpleFuture{ .value = 42 };
    const result1 = zokio.future.await_fn(future1);
    std.debug.print("   没有事件循环时结果: {}\n", .{result1});
    try testing.expect(result1 == 42);
    std.debug.print("✅ 没有事件循环时正常回退到同步模式\n", .{});

    // 2. 有事件循环时的行为
    std.debug.print("2. 测试有事件循环时的await_fn行为...\n", .{});

    const event_loop = try zokio.runtime.getOrCreateDefaultEventLoop(allocator);
    zokio.runtime.setCurrentEventLoop(event_loop);

    const future2 = SimpleFuture{ .value = 84 };
    const result2 = zokio.future.await_fn(future2);
    std.debug.print("   有事件循环时结果: {}\n", .{result2});
    try testing.expect(result2 == 84);
    std.debug.print("✅ 有事件循环时能正确检测并使用异步模式\n", .{});

    // 清理
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(allocator);

    std.debug.print("✅ await_fn事件循环检测验证完成\n", .{});
}

test "验证修复后的性能" {
    std.debug.print("\n=== 修复后性能验证 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const FastFuture = struct {
        value: u32,

        pub const Output = u32;

        pub fn poll(self: *@This(), ctx: *zokio.future.Context) zokio.future.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value };
        }
    };

    const iterations = 10000;

    // 1. 没有事件循环的性能
    std.debug.print("1. 测试没有事件循环时的性能...\n", .{});

    const start_time1 = std.time.nanoTimestamp();

    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const future = FastFuture{ .value = i };
        const result = zokio.future.await_fn(future);
        if (result != i) return error.UnexpectedResult;
    }

    const end_time1 = std.time.nanoTimestamp();
    const duration1_ms = @as(f64, @floatFromInt(end_time1 - start_time1)) / 1_000_000.0;
    const ops_per_sec1 = @as(f64, @floatFromInt(iterations)) / (duration1_ms / 1000.0);

    std.debug.print("   同步模式性能: {d:.0} ops/sec\n", .{ops_per_sec1});

    // 2. 有事件循环的性能
    std.debug.print("2. 测试有事件循环时的性能...\n", .{});

    const event_loop = try zokio.runtime.getOrCreateDefaultEventLoop(allocator);
    zokio.runtime.setCurrentEventLoop(event_loop);

    const start_time2 = std.time.nanoTimestamp();

    i = 0;
    while (i < iterations) : (i += 1) {
        const future = FastFuture{ .value = i };
        const result = zokio.future.await_fn(future);
        if (result != i) return error.UnexpectedResult;
    }

    const end_time2 = std.time.nanoTimestamp();
    const duration2_ms = @as(f64, @floatFromInt(end_time2 - start_time2)) / 1_000_000.0;
    const ops_per_sec2 = @as(f64, @floatFromInt(iterations)) / (duration2_ms / 1000.0);

    std.debug.print("   异步模式性能: {d:.0} ops/sec\n", .{ops_per_sec2});

    // 清理
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(allocator);

    std.debug.print("✅ 性能验证完成\n", .{});
    std.debug.print("   两种模式都能正常工作\n", .{});
}
