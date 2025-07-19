//! 🔧 逐步排除问题的测试
//! 一步一步找出DefaultRuntime.start()卡住的原因

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "步骤1: 测试DefaultRuntime.init()" {
    std.debug.print("\n=== 步骤1: DefaultRuntime.init() ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = zokio.runtime.DefaultRuntime.init(allocator) catch |err| {
        std.debug.print("❌ DefaultRuntime.init()失败: {}\n", .{err});
        return err;
    };
    defer runtime.deinit();

    std.debug.print("✅ DefaultRuntime.init()成功\n", .{});
}

test "步骤2: 测试running状态检查" {
    std.debug.print("\n=== 步骤2: running状态检查 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    // 测试running.load(.acquire)
    const initial_running = runtime.running.load(.acquire);
    std.debug.print("初始running状态: {}\n", .{initial_running});
    try testing.expect(!initial_running);

    // 测试running.store(true, .release)
    runtime.running.store(true, .release);
    const after_set_running = runtime.running.load(.acquire);
    std.debug.print("设置后running状态: {}\n", .{after_set_running});
    try testing.expect(after_set_running);

    std.debug.print("✅ running状态操作正常\n", .{});
}

test "步骤3: 测试getOrCreateDefaultEventLoop调用" {
    std.debug.print("\n=== 步骤3: getOrCreateDefaultEventLoop调用 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    // 手动调用getOrCreateDefaultEventLoop
    std.debug.print("调用getOrCreateDefaultEventLoop...\n", .{});
    const event_loop = zokio.runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ getOrCreateDefaultEventLoop失败: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ getOrCreateDefaultEventLoop成功: {*}\n", .{event_loop});

    // 清理
    zokio.runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 清理完成\n", .{});
}

test "步骤4: 测试setCurrentEventLoop调用" {
    std.debug.print("\n=== 步骤4: setCurrentEventLoop调用 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    // 创建事件循环
    const event_loop = try zokio.runtime.getOrCreateDefaultEventLoop(allocator);
    std.debug.print("创建事件循环: {*}\n", .{event_loop});

    // 测试setCurrentEventLoop
    std.debug.print("调用setCurrentEventLoop...\n", .{});
    zokio.runtime.setCurrentEventLoop(event_loop);
    std.debug.print("✅ setCurrentEventLoop完成\n", .{});

    // 验证设置成功
    const current = zokio.runtime.getCurrentEventLoop();
    std.debug.print("getCurrentEventLoop结果: {?}\n", .{current});

    if (current == null) {
        std.debug.print("❌ 事件循环设置失败\n", .{});
        zokio.runtime.cleanupDefaultEventLoop(allocator);
        return error.EventLoopNotSet;
    } else {
        std.debug.print("✅ 事件循环设置成功\n", .{});
    }

    // 清理
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 清理完成\n", .{});
}

test "步骤5: 测试日志输出" {
    std.debug.print("\n=== 步骤5: 日志输出测试 ===\n", .{});

    // 测试std.log.info是否会卡住
    std.debug.print("测试std.log.info...\n", .{});
    std.log.info("🔥 这是一个测试日志", .{});
    std.debug.print("✅ std.log.info正常\n", .{});

    // 测试格式化输出
    const test_value = 42;
    std.log.info("测试格式化: {}", .{test_value});
    std.debug.print("✅ 格式化日志正常\n", .{});
}

test "步骤6: 模拟start()的每个步骤" {
    std.debug.print("\n=== 步骤6: 模拟start()步骤 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    // 步骤1: 检查running状态
    std.debug.print("6.1 检查running状态...\n", .{});
    if (runtime.running.load(.acquire)) {
        std.debug.print("运行时已启动，返回\n", .{});
        return;
    }
    std.debug.print("✅ running状态检查完成\n", .{});

    // 步骤2: 设置running状态
    std.debug.print("6.2 设置running状态...\n", .{});
    runtime.running.store(true, .release);
    std.debug.print("✅ running状态设置完成\n", .{});

    // 步骤3: 创建事件循环
    std.debug.print("6.3 创建事件循环...\n", .{});
    const default_event_loop = try zokio.runtime.getOrCreateDefaultEventLoop(allocator);
    std.debug.print("✅ 事件循环创建完成: {*}\n", .{default_event_loop});

    // 步骤4: 设置事件循环
    std.debug.print("6.4 设置事件循环...\n", .{});
    zokio.runtime.setCurrentEventLoop(default_event_loop);
    std.debug.print("✅ 事件循环设置完成\n", .{});

    // 步骤5: 日志输出
    std.debug.print("6.5 日志输出...\n", .{});
    std.log.info("🔥 事件循环已设置", .{});
    std.debug.print("✅ 日志输出完成\n", .{});

    // 清理
    runtime.running.store(false, .release);
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 所有步骤完成，没有卡住\n", .{});
}
