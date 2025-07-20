//! 🔧 测试DefaultRuntime上下文环境
//! 分析为什么在DefaultRuntime.start()中调用getOrCreateDefaultEventLoop()会卡住

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "测试DefaultRuntime初始化" {
    std.debug.print("\n=== DefaultRuntime初始化测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("1. 创建DefaultRuntime...\n", .{});
    var runtime = zokio.runtime.DefaultRuntime.init(allocator) catch |err| {
        std.debug.print("❌ DefaultRuntime.init()失败: {}\n", .{err});
        return err;
    };
    defer runtime.deinit();
    std.debug.print("✅ DefaultRuntime创建成功\n", .{});

    std.debug.print("2. 检查运行时状态...\n", .{});
    const running = runtime.running.load(.acquire);
    std.debug.print("   运行状态: {}\n", .{running});
    try testing.expect(!running);
    std.debug.print("✅ 运行时状态正常\n", .{});
}

test "测试在DefaultRuntime上下文中调用getOrCreateDefaultEventLoop" {
    std.debug.print("\n=== DefaultRuntime上下文事件循环测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建DefaultRuntime
    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("1. 在DefaultRuntime上下文中调用getOrCreateDefaultEventLoop...\n", .{});
    
    // 模拟start()中的调用
    const default_event_loop = zokio.runtime.getOrCreateDefaultEventLoop(runtime.base_allocator) catch |err| {
        std.debug.print("❌ getOrCreateDefaultEventLoop失败: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ 在DefaultRuntime上下文中创建事件循环成功: {*}\n", .{default_event_loop});

    std.debug.print("2. 设置事件循环...\n", .{});
    zokio.runtime.setCurrentEventLoop(default_event_loop);
    const current_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("✅ 事件循环设置成功: {?}\n", .{current_loop});

    // 清理
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(runtime.base_allocator);
    std.debug.print("✅ DefaultRuntime上下文测试完成\n", .{});
}

test "模拟完整的start()逻辑（不调用实际start）" {
    std.debug.print("\n=== 模拟start()逻辑测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("开始模拟start()逻辑...\n", .{});

    // 步骤1: 检查running状态
    std.debug.print("步骤1: 检查running状态...\n", .{});
    if (runtime.running.load(.acquire)) {
        std.debug.print("   运行时已启动，返回\n", .{});
        return;
    }
    std.debug.print("   ✅ running状态检查完成\n", .{});

    // 步骤2: 设置running状态
    std.debug.print("步骤2: 设置running状态...\n", .{});
    runtime.running.store(true, .release);
    std.debug.print("   ✅ running状态设置完成\n", .{});

    // 步骤3: 创建并设置事件循环（这是关键步骤）
    std.debug.print("步骤3: 创建并设置事件循环...\n", .{});
    const default_event_loop = zokio.runtime.getOrCreateDefaultEventLoop(runtime.base_allocator) catch |err| {
        std.debug.print("❌ getOrCreateDefaultEventLoop失败: {}\n", .{err});
        runtime.running.store(false, .release);
        return err;
    };
    std.debug.print("   ✅ 事件循环创建成功: {*}\n", .{default_event_loop});

    zokio.runtime.setCurrentEventLoop(default_event_loop);
    std.debug.print("   ✅ 事件循环设置完成\n", .{});

    // 步骤4: 日志输出
    std.debug.print("步骤4: 日志输出...\n", .{});
    std.log.info("🔥 事件循环已设置", .{});
    std.debug.print("   ✅ 第一个日志完成\n", .{});

    // 步骤5: 模拟工作线程相关逻辑
    std.debug.print("步骤5: 模拟工作线程逻辑...\n", .{});
    std.log.info("Zokio运行时启动: {} 工作线程", .{4});
    std.debug.print("   ✅ 工作线程日志完成\n", .{});

    // 步骤6: 模拟libxev相关逻辑
    std.debug.print("步骤6: 模拟libxev逻辑...\n", .{});
    std.log.info("libxev事件循环已准备就绪", .{});
    std.debug.print("   ✅ libxev日志完成\n", .{});

    // 步骤7: 最终日志
    std.debug.print("步骤7: 最终日志...\n", .{});
    std.log.info("🚀 Zokio 4.0 运行时启动完成，事件循环已就绪", .{});
    std.debug.print("   ✅ 最终日志完成\n", .{});

    // 清理
    runtime.running.store(false, .release);
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(runtime.base_allocator);

    std.debug.print("✅ 完整start()逻辑模拟成功，没有卡住\n", .{});
}

test "测试实际调用start()方法" {
    std.debug.print("\n=== 实际start()调用测试 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("准备调用runtime.start()...\n", .{});
    std.debug.print("如果这里卡住，说明问题在start()方法本身\n", .{});
    
    // 这里是关键测试 - 实际调用start()
    runtime.start() catch |err| {
        std.debug.print("❌ runtime.start()失败: {}\n", .{err});
        return err;
    };
    
    std.debug.print("✅ runtime.start()成功完成\n", .{});
    
    // 验证状态
    const running = runtime.running.load(.acquire);
    const current_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("启动后状态 - running: {}, event_loop: {?}\n", .{ running, current_loop });
    
    // 停止运行时
    runtime.stop();
    std.debug.print("✅ runtime.stop()完成\n", .{});
}
