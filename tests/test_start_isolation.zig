//! 🔧 隔离测试DefaultRuntime.start()的每个步骤
//! 逐步排除导致卡住的具体原因

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "隔离测试1: 只测试running状态操作" {
    std.debug.print("\n=== 隔离测试1: running状态操作 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    // 模拟start()的第一步：检查running状态
    std.debug.print("1. 检查初始running状态...\n", .{});
    const initial_running = runtime.running.load(.acquire);
    std.debug.print("   初始running: {}\n", .{initial_running});
    try testing.expect(!initial_running);

    // 模拟start()的第二步：设置running状态
    std.debug.print("2. 设置running状态...\n", .{});
    runtime.running.store(true, .release);
    const after_set_running = runtime.running.load(.acquire);
    std.debug.print("   设置后running: {}\n", .{after_set_running});
    try testing.expect(after_set_running);

    // 清理
    runtime.running.store(false, .release);
    std.debug.print("✅ running状态操作正常\n", .{});
}

test "隔离测试2: 只测试事件循环创建" {
    std.debug.print("\n=== 隔离测试2: 事件循环创建 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 模拟start()的第三步：创建事件循环
    std.debug.print("1. 创建事件循环...\n", .{});
    const event_loop = zokio.runtime.getOrCreateDefaultEventLoop(allocator) catch |err| {
        std.debug.print("❌ 事件循环创建失败: {}\n", .{err});
        return err;
    };
    std.debug.print("   事件循环: {*}\n", .{event_loop});

    // 模拟start()的第四步：设置事件循环
    std.debug.print("2. 设置事件循环...\n", .{});
    zokio.runtime.setCurrentEventLoop(event_loop);
    const current_loop = zokio.runtime.getCurrentEventLoop();
    std.debug.print("   当前事件循环: {?}\n", .{current_loop});
    try testing.expect(current_loop != null);
    try testing.expect(current_loop == event_loop);

    // 清理
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(allocator);
    std.debug.print("✅ 事件循环创建和设置正常\n", .{});
}

test "隔离测试3: 只测试日志输出" {
    std.debug.print("\n=== 隔离测试3: 日志输出 ===\n", .{});

    // 模拟start()中的日志调用
    std.debug.print("1. 测试std.log.info调用...\n", .{});
    
    std.log.info("🔥 事件循环已设置", .{});
    std.debug.print("   第一个日志调用完成\n", .{});
    
    std.log.info("Zokio运行时启动: {} 工作线程", .{4});
    std.debug.print("   第二个日志调用完成\n", .{});
    
    std.log.info("libxev事件循环已准备就绪", .{});
    std.debug.print("   第三个日志调用完成\n", .{});
    
    std.log.info("🚀 Zokio 4.0 运行时启动完成，事件循环已就绪", .{});
    std.debug.print("   第四个日志调用完成\n", .{});

    std.debug.print("✅ 所有日志输出正常\n", .{});
}

test "隔离测试4: 模拟完整start()流程（无实际start调用）" {
    std.debug.print("\n=== 隔离测试4: 模拟完整start()流程 ===\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var runtime = try zokio.runtime.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("开始模拟start()流程...\n", .{});

    // 步骤1: 检查running状态
    std.debug.print("步骤1: 检查running状态...\n", .{});
    if (runtime.running.load(.acquire)) {
        std.debug.print("   运行时已启动，返回\n", .{});
        return;
    }
    std.debug.print("   running状态检查完成\n", .{});

    // 步骤2: 设置running状态
    std.debug.print("步骤2: 设置running状态...\n", .{});
    runtime.running.store(true, .release);
    std.debug.print("   running状态设置完成\n", .{});

    // 步骤3: 创建并设置事件循环
    std.debug.print("步骤3: 创建并设置事件循环...\n", .{});
    const default_event_loop = try zokio.runtime.getOrCreateDefaultEventLoop(allocator);
    zokio.runtime.setCurrentEventLoop(default_event_loop);
    std.debug.print("   事件循环设置完成\n", .{});

    // 步骤4: 日志输出
    std.debug.print("步骤4: 日志输出...\n", .{});
    std.log.info("🔥 事件循环已设置", .{});
    std.debug.print("   第一个日志完成\n", .{});

    // 步骤5: 工作线程相关（编译时条件）
    std.debug.print("步骤5: 工作线程相关...\n", .{});
    // 这里不使用编译时条件，直接模拟
    std.log.info("Zokio运行时启动: {} 工作线程", .{4});
    std.debug.print("   工作线程日志完成\n", .{});

    // 步骤6: libxev相关
    std.debug.print("步骤6: libxev相关...\n", .{});
    std.log.info("libxev事件循环已准备就绪", .{});
    std.debug.print("   libxev日志完成\n", .{});

    // 步骤7: 最终日志
    std.debug.print("步骤7: 最终日志...\n", .{});
    std.log.info("🚀 Zokio 4.0 运行时启动完成，事件循环已就绪", .{});
    std.debug.print("   最终日志完成\n", .{});

    // 清理
    runtime.running.store(false, .release);
    zokio.runtime.setCurrentEventLoop(null);
    zokio.runtime.cleanupDefaultEventLoop(allocator);

    std.debug.print("✅ 完整流程模拟成功，没有卡住\n", .{});
}

test "隔离测试5: 测试编译时条件" {
    std.debug.print("\n=== 隔离测试5: 编译时条件 ===\n", .{});

    // 测试可能导致问题的编译时计算
    std.debug.print("1. 测试编译时类型计算...\n", .{});
    
    const RuntimeType = zokio.runtime.DefaultRuntime;
    std.debug.print("   RuntimeType: {}\n", .{@TypeOf(RuntimeType)});
    
    std.debug.print("2. 测试编译时大小计算...\n", .{});
    const runtime_size = @sizeOf(RuntimeType);
    std.debug.print("   Runtime大小: {} bytes\n", .{runtime_size});

    std.debug.print("✅ 编译时条件测试正常\n", .{});
}
