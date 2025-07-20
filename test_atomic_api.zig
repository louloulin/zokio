const std = @import("std");

test "atomic API test" {
    var atomic_bool = std.atomic.Value(bool).init(false);
    var atomic_u32 = std.atomic.Value(u32).init(0);
    
    // 测试可用的方法
    _ = atomic_bool.load(.monotonic);
    atomic_bool.store(true, .monotonic);
    
    _ = atomic_u32.load(.monotonic);
    atomic_u32.store(42, .monotonic);
    _ = atomic_u32.fetchAdd(1, .monotonic);
    _ = atomic_u32.fetchSub(1, .monotonic);
    
    // 测试 compare and swap
    _ = atomic_bool.cmpxchgWeak(false, true, .monotonic, .monotonic);
    _ = atomic_u32.cmpxchgWeak(42, 84, .monotonic, .monotonic);
}
