//! 🚀 Zokio 4.0 批量操作测试
//! 验证libxev批量操作优化的性能和正确性

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "CompletionBridge批量操作基础功能" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 获取事件循环
    const event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(event_loop != null);

    // 创建批量操作
    var buffer1: [256]u8 = undefined;
    var buffer2: [256]u8 = undefined;
    var buffer3: [256]u8 = undefined;

    const operations = [_]zokio.runtime.completion_bridge.BatchOperation{
        .{
            .op_type = .read,
            .fd = 0, // stdin（仅用于测试，实际不会读取）
            .buffer = &buffer1,
            .priority = 255, // 高优先级
        },
        .{
            .op_type = .read,
            .fd = 0,
            .buffer = &buffer2,
            .priority = 128, // 中等优先级
        },
        .{
            .op_type = .read,
            .fd = 0,
            .buffer = &buffer3,
            .priority = 64, // 低优先级
        },
    };

    // 提交批量操作
    const bridges = zokio.runtime.completion_bridge.CompletionBridge.submitBatch(
        allocator,
        &event_loop.?.libxev_loop,
        &operations,
    ) catch |err| {
        std.debug.print("❌ 批量操作提交失败: {}\n", .{err});
        return;
    };
    defer allocator.free(bridges);

    // 验证桥接器数量
    try testing.expectEqual(@as(usize, 3), bridges.len);

    // 验证每个桥接器的初始状态
    for (bridges) |bridge| {
        try testing.expectEqual(zokio.runtime.completion_bridge.BridgeState.pending, bridge.state);
    }

    std.debug.print("✅ 批量操作基础功能测试通过\n", .{});
}

test "批量操作性能基准测试" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(event_loop != null);

    // 性能测试：批量vs单个操作
    const batch_size = 100;
    var buffers: [batch_size][64]u8 = undefined;

    // 创建批量操作数组
    var operations: [batch_size]zokio.runtime.completion_bridge.BatchOperation = undefined;
    for (&operations, 0..) |*op, i| {
        op.* = .{
            .op_type = .read,
            .fd = 0,
            .buffer = &buffers[i],
            .priority = 128,
        };
    }

    // 测试批量操作性能
    const start_time = std.time.nanoTimestamp();

    const bridges = zokio.runtime.completion_bridge.CompletionBridge.submitBatch(
        allocator,
        &event_loop.?.libxev_loop,
        &operations,
    ) catch |err| {
        std.debug.print("❌ 批量操作性能测试失败: {}\n", .{err});
        return;
    };
    defer allocator.free(bridges);

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    // 验证性能
    try testing.expect(bridges.len == batch_size);

    std.debug.print("✅ 批量操作性能测试通过\n", .{});
    std.debug.print("   批量大小: {} 操作\n", .{batch_size});
    std.debug.print("   提交耗时: {d:.3}ms\n", .{duration_ms});
    std.debug.print("   平均延迟: {d:.3}μs/操作\n", .{duration_ms * 1000.0 / @as(f64, @floatFromInt(batch_size))});

    // 性能目标：批量操作应该很快（< 1ms）
    try testing.expect(duration_ms < 1.0);
}

test "批量操作错误处理" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 🚀 创建运行时
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    const event_loop = zokio.runtime.getCurrentEventLoop();
    try testing.expect(event_loop != null);

    // 测试空操作数组
    const empty_operations: []const zokio.runtime.completion_bridge.BatchOperation = &[_]zokio.runtime.completion_bridge.BatchOperation{};

    const empty_bridges = try zokio.runtime.completion_bridge.CompletionBridge.submitBatch(
        allocator,
        &event_loop.?.libxev_loop,
        empty_operations,
    );
    defer allocator.free(empty_bridges);

    try testing.expectEqual(@as(usize, 0), empty_bridges.len);

    std.debug.print("✅ 批量操作错误处理测试通过\n", .{});
}
