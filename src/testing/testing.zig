//! 测试工具模块
//! 
//! 提供异步测试和模拟工具。

const std = @import("std");
const future = @import("../future/future.zig");
const runtime = @import("../runtime/runtime.zig");

/// 异步测试运行器
pub fn asyncTest(comptime test_fn: anytype) !void {
    const config = runtime.RuntimeConfig{
        .worker_threads = 1,
        .enable_metrics = false,
    };
    
    var test_runtime = try runtime.ZokioRuntime(config).init(std.testing.allocator);
    defer test_runtime.deinit();
    
    try test_runtime.start();
    defer test_runtime.stop();
    
    // 运行测试函数
    const test_future = future.async_fn(test_fn).init(test_fn);
    _ = try test_runtime.blockOn(test_future);
}

/// 模拟时间
pub const MockTime = struct {
    current_time: std.atomic.Value(i64),
    
    pub fn init() MockTime {
        return MockTime{
            .current_time = std.atomic.Value(i64).init(0),
        };
    }
    
    pub fn now(self: *const MockTime) i64 {
        return self.current_time.load(.monotonic);
    }
    
    pub fn advance(self: *MockTime, duration_ms: u64) void {
        _ = self.current_time.fetchAdd(@intCast(duration_ms), .monotonic);
    }
    
    pub fn set(self: *MockTime, time_ms: i64) void {
        self.current_time.store(time_ms, .monotonic);
    }
};

// 测试
test "异步测试运行器" {
    const testing = std.testing;
    
    const TestFunction = struct {
        fn testAsync() u32 {
            return 42;
        }
    };
    
    try asyncTest(TestFunction.testAsync);
    
    // 如果到达这里，说明异步测试成功运行
    try testing.expect(true);
}

test "模拟时间功能" {
    const testing = std.testing;
    
    var mock_time = MockTime.init();
    
    // 测试初始时间
    try testing.expectEqual(@as(i64, 0), mock_time.now());
    
    // 测试时间推进
    mock_time.advance(1000);
    try testing.expectEqual(@as(i64, 1000), mock_time.now());
    
    // 测试时间设置
    mock_time.set(5000);
    try testing.expectEqual(@as(i64, 5000), mock_time.now());
}
