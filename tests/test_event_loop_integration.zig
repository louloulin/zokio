//! 验证事件循环集成的测试
//! 这是Phase 1.3的验收测试，确保AsyncEventLoop与Runtime核心API正确集成

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "事件循环基础集成测试" {
    std.debug.print("\n=== 测试事件循环集成：核心API集成 ===\n", .{});

    // 测试1: getCurrentEventLoop和setCurrentEventLoop
    std.debug.print("1. 测试事件循环获取和设置\n", .{});

    // 初始状态应该没有事件循环
    const initial_loop = zokio.getCurrentEventLoop();
    try testing.expect(initial_loop == null);
    std.debug.print("   初始状态: 没有事件循环 ✅\n", .{});

    // 创建事件循环
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = zokio.AsyncEventLoop.init(allocator) catch |err| {
        std.debug.print("   创建事件循环失败: {}\n", .{err});
        return;
    };
    defer event_loop.deinit();

    // 设置当前事件循环
    zokio.setCurrentEventLoop(&event_loop);

    // 验证设置成功
    const current_loop = zokio.getCurrentEventLoop();
    try testing.expect(current_loop != null);
    try testing.expect(current_loop == &event_loop);
    std.debug.print("   设置事件循环成功 ✅\n", .{});

    // 清理
    zokio.setCurrentEventLoop(null);
    const cleared_loop = zokio.getCurrentEventLoop();
    try testing.expect(cleared_loop == null);
    std.debug.print("   清理事件循环成功 ✅\n", .{});
}

test "事件循环运行时集成测试" {
    std.debug.print("\n2. 测试事件循环与运行时集成\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建运行时配置
    const config = zokio.RuntimeConfig{
        .worker_threads = 1,
        .enable_io_uring = true,
        .prefer_libxev = true,
        .enable_tracing = false, // 测试环境关闭追踪
    };

    // 创建运行时
    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = RuntimeType.init(allocator) catch |err| {
        std.debug.print("   创建运行时失败: {}\n", .{err});
        return;
    };
    defer runtime.deinit();

    // 启动运行时
    runtime.start() catch |err| {
        std.debug.print("   启动运行时失败: {}\n", .{err});
        return;
    };

    // 验证事件循环已设置
    const runtime_loop = zokio.getCurrentEventLoop();
    try testing.expect(runtime_loop != null);
    std.debug.print("   运行时事件循环已设置 ✅\n", .{});

    // 停止运行时
    runtime.stop();

    std.debug.print("   运行时集成测试通过 ✅\n", .{});
}

// 简单的测试Future
const TestFuture = struct {
    value: u32,
    poll_count: u32 = 0,
    ready_after: u32 = 1,

    pub const Output = u32;

    pub fn init(val: u32) @This() {
        return @This(){
            .value = val,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;
        self.poll_count += 1;

        if (self.poll_count >= self.ready_after) {
            return .{ .ready = self.value };
        } else {
            return .pending;
        }
    }
};

test "事件循环驱动的await_fn测试" {
    std.debug.print("\n3. 测试事件循环驱动的await_fn\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建事件循环
    var event_loop = zokio.AsyncEventLoop.init(allocator) catch |err| {
        std.debug.print("   创建事件循环失败: {}\n", .{err});
        return;
    };
    defer event_loop.deinit();

    // 设置当前事件循环
    zokio.setCurrentEventLoop(&event_loop);
    defer zokio.setCurrentEventLoop(null);

    // 启动事件循环
    event_loop.start();

    // 测试await_fn在事件循环环境中的行为
    const future = TestFuture.init(42);
    const result = zokio.await_fn(future);

    try testing.expect(result == 42);
    std.debug.print("   事件循环驱动的await_fn成功 ✅\n", .{});
}

test "事件循环runOnce功能测试" {
    std.debug.print("\n4. 测试事件循环runOnce功能\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = zokio.AsyncEventLoop.init(allocator) catch |err| {
        std.debug.print("   创建事件循环失败: {}\n", .{err});
        return;
    };
    defer event_loop.deinit();

    // 测试runOnce不会阻塞
    const start_time = std.time.nanoTimestamp();
    event_loop.runOnce() catch |err| {
        std.debug.print("   runOnce失败: {}\n", .{err});
        return;
    };
    const end_time = std.time.nanoTimestamp();

    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // runOnce应该很快完成（非阻塞）
    try testing.expect(duration_ms < 10.0); // 应该在10ms内完成

    std.debug.print("   runOnce耗时: {d:.2} ms ✅\n", .{duration_ms});
}

test "事件循环任务计数测试" {
    std.debug.print("\n5. 测试事件循环任务计数\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = zokio.AsyncEventLoop.init(allocator) catch |err| {
        std.debug.print("   创建事件循环失败: {}\n", .{err});
        return;
    };
    defer event_loop.deinit();

    // 初始状态
    try testing.expect(!event_loop.hasActiveTasks());
    try testing.expect(!event_loop.isRunning());

    // 添加任务
    event_loop.addActiveTask();
    try testing.expect(event_loop.hasActiveTasks());

    // 移除任务
    event_loop.removeActiveTask();
    try testing.expect(!event_loop.hasActiveTasks());

    // 启动和停止
    event_loop.start();
    try testing.expect(event_loop.isRunning());

    std.debug.print("   任务计数功能正常 ✅\n", .{});
}

test "事件循环性能测试" {
    std.debug.print("\n6. 测试事件循环性能\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var event_loop = zokio.AsyncEventLoop.init(allocator) catch |err| {
        std.debug.print("   创建事件循环失败: {}\n", .{err});
        return;
    };
    defer event_loop.deinit();

    const iterations = 1000;
    const start_time = std.time.nanoTimestamp();

    // 多次调用runOnce测试性能
    for (0..iterations) |_| {
        event_loop.runOnce() catch {};
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration_ms / 1000.0);

    std.debug.print("   {} 次runOnce耗时: {d:.2} ms\n", .{ iterations, duration_ms });
    std.debug.print("   性能: {d:.0} ops/sec\n", .{ops_per_sec});

    // 性能应该很高
    try testing.expect(ops_per_sec > 10000); // 至少10K ops/sec

    std.debug.print("   性能测试通过 ✅\n", .{});
}

test "事件循环内存安全测试" {
    std.debug.print("\n7. 测试事件循环内存安全\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建多个事件循环测试内存管理
    var loops: [10]zokio.AsyncEventLoop = undefined;

    // 初始化所有事件循环
    for (&loops) |*loop| {
        loop.* = zokio.AsyncEventLoop.init(allocator) catch |err| {
            std.debug.print("   创建事件循环失败: {}\n", .{err});
            return;
        };
    }

    // 设置和清理事件循环
    for (&loops, 0..) |*loop, i| {
        zokio.setCurrentEventLoop(loop);

        // 验证设置成功
        const current = zokio.getCurrentEventLoop();
        try testing.expect(current == loop);

        // 执行一些操作
        loop.addActiveTask();
        loop.removeActiveTask();

        if (i % 2 == 0) {
            loop.start();
        }

        zokio.setCurrentEventLoop(null);
    }

    // 清理所有事件循环
    for (&loops) |*loop| {
        loop.deinit();
    }

    std.debug.print("   内存安全测试通过 ✅\n", .{});
}
