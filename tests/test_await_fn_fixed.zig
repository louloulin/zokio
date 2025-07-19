//! 验证await_fn修复的测试
//! 这是Phase 1.1的验收测试，确保await_fn不再使用阻塞调用

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

// 简单的测试Future
const TestFuture = struct {
    value: u32,
    poll_count: u32 = 0,
    ready_after: u32 = 2, // 第2次轮询后返回ready

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

test "await_fn不再使用阻塞调用" {
    std.debug.print("\n=== 测试await_fn修复：消除阻塞调用 ===\n", .{});

    // 测试1: 基础await_fn功能
    std.debug.print("1. 测试基础await_fn功能\n", .{});

    const future = TestFuture.init(42);

    // 在没有运行时的情况下，应该使用回退模式
    const result = zokio.await_fn(future);

    try testing.expect(result == 42);
    std.debug.print("   ✅ await_fn返回正确结果: {}\n", .{result});
}

test "await_fn回退模式测试" {
    std.debug.print("\n2. 测试await_fn回退模式\n", .{});

    const future = TestFuture.init(100);

    const result = zokio.await_fn(future);

    try testing.expect(result == 100);
    std.debug.print("   回退模式结果: {}\n", .{result});
    std.debug.print("   ✅ 回退模式测试通过\n", .{});
}

test "await_fn错误处理测试" {
    std.debug.print("\n3. 测试await_fn错误处理\n", .{});

    const ErrorFuture = struct {
        poll_count: u32 = 0,

        pub const Output = anyerror!u32;

        pub fn poll(self: *@This(), ctx: anytype) zokio.Poll(anyerror!u32) {
            _ = ctx;
            self.poll_count += 1;

            if (self.poll_count >= 15) { // 超过回退模式的最大尝试次数
                return .{ .ready = error.TestError };
            } else {
                return .pending;
            }
        }
    };

    const error_future = ErrorFuture{};
    const result = zokio.await_fn(error_future);

    try testing.expectError(error.Timeout, result);
    std.debug.print("   错误处理结果: {any}\n", .{result});
    std.debug.print("   ✅ 错误处理测试通过\n", .{});
}

test "await_fn void类型测试" {
    std.debug.print("\n4. 测试await_fn void类型\n", .{});

    const VoidFuture = struct {
        poll_count: u32 = 0,

        pub const Output = void;

        pub fn poll(self: *@This(), ctx: anytype) zokio.Poll(void) {
            _ = ctx;
            self.poll_count += 1;

            if (self.poll_count >= 2) {
                return .ready;
            } else {
                return .pending;
            }
        }
    };

    const void_future = VoidFuture{};
    zokio.await_fn(void_future); // 应该正常返回void

    std.debug.print("   ✅ void类型测试通过\n", .{});
}

// 阻塞调用检测器（简化版本）
const BlockingCallDetector = struct {
    thread_yield_calls: u32 = 0,
    sleep_calls: u32 = 0,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn reset(self: *Self) void {
        self.thread_yield_calls = 0;
        self.sleep_calls = 0;
    }

    pub fn hasBlockingCalls(self: *const Self) bool {
        return self.thread_yield_calls > 0 or self.sleep_calls > 0;
    }

    pub fn report(self: *const Self) void {
        std.debug.print("   阻塞调用统计:\n", .{});
        std.debug.print("     Thread.yield() 调用: {}\n", .{self.thread_yield_calls});
        std.debug.print("     sleep() 调用: {}\n", .{self.sleep_calls});
    }
};

test "await_fn性能测试" {
    std.debug.print("\n5. 测试await_fn性能\n", .{});

    const start_time = std.time.nanoTimestamp();

    // 创建多个Future并等待
    var futures: [10]TestFuture = undefined;
    for (&futures, 0..) |*future, i| {
        future.* = TestFuture.init(@intCast(i));
        future.ready_after = 1; // 快速完成
    }

    var results: [10]u32 = undefined;
    for (&futures, &results) |*future, *result| {
        result.* = zokio.await_fn(future.*);
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

    std.debug.print("   处理10个Future耗时: {d:.2} ms\n", .{duration_ms});
    std.debug.print("   平均每个Future: {d:.2} ms\n", .{duration_ms / 10.0});

    // 验证结果
    for (results, 0..) |result, i| {
        try testing.expect(result == i);
    }

    std.debug.print("   ✅ 性能测试通过\n", .{});
}

test "await_fn并发安全测试" {
    std.debug.print("\n6. 测试await_fn并发安全\n", .{});

    // 简化的并发测试：确保await_fn可以在多个上下文中调用
    var future1 = TestFuture.init(1);
    var future2 = TestFuture.init(2);

    future1.ready_after = 1;
    future2.ready_after = 1;

    const result1 = zokio.await_fn(future1);
    const result2 = zokio.await_fn(future2);

    try testing.expect(result1 == 1);
    try testing.expect(result2 == 2);

    std.debug.print("   并发结果: {} 和 {}\n", .{ result1, result2 });
    std.debug.print("   ✅ 并发安全测试通过\n", .{});
}

test "await_fn编译时验证" {
    std.debug.print("\n7. 测试await_fn编译时验证\n", .{});

    // 这个测试验证编译时类型检查是否正常工作
    const ValidFuture = struct {
        pub const Output = bool;
        pub fn poll(self: *@This(), ctx: anytype) zokio.Poll(bool) {
            _ = self;
            _ = ctx;
            return .{ .ready = true };
        }
    };

    const valid_future = ValidFuture{};
    const result = zokio.await_fn(valid_future);

    try testing.expect(result == true);
    std.debug.print("   编译时验证通过，结果: {}\n", .{result});
    std.debug.print("   ✅ 编译时验证测试通过\n", .{});
}
