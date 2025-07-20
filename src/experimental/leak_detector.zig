//! 🧪 实验性内存泄漏检测模块
//! 
//! 提供运行时内存泄漏检测和分析功能

const std = @import("std");

/// 内存泄漏检测器
pub const LeakDetector = struct {
    allocations: std.HashMap(usize, AllocationInfo, std.hash_map.DefaultContext(usize), std.hash_map.default_max_load_percentage),
    total_allocated: usize,
    total_freed: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) LeakDetector {
        return LeakDetector{
            .allocations = std.HashMap(usize, AllocationInfo, std.hash_map.DefaultContext(usize), std.hash_map.default_max_load_percentage).init(allocator),
            .total_allocated = 0,
            .total_freed = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *LeakDetector) void {
        self.allocations.deinit();
    }
    
    pub fn trackAllocation(self: *LeakDetector, ptr: usize, size: usize, location: []const u8) !void {
        const info = AllocationInfo{
            .size = size,
            .location = location,
            .timestamp = std.time.timestamp(),
        };
        
        try self.allocations.put(ptr, info);
        self.total_allocated += size;
    }
    
    pub fn trackDeallocation(self: *LeakDetector, ptr: usize) void {
        if (self.allocations.fetchRemove(ptr)) |entry| {
            self.total_freed += entry.value.size;
        }
    }
    
    pub fn getLeakReport(self: *LeakDetector) LeakReport {
        var leaked_count: usize = 0;
        var leaked_bytes: usize = 0;
        
        var iterator = self.allocations.iterator();
        while (iterator.next()) |entry| {
            leaked_count += 1;
            leaked_bytes += entry.value_ptr.size;
        }
        
        return LeakReport{
            .leaked_allocations = leaked_count,
            .leaked_bytes = leaked_bytes,
            .total_allocated = self.total_allocated,
            .total_freed = self.total_freed,
        };
    }
    
    pub fn hasLeaks(self: *LeakDetector) bool {
        return self.allocations.count() > 0;
    }
};

/// 分配信息
pub const AllocationInfo = struct {
    size: usize,
    location: []const u8,
    timestamp: i64,
};

/// 泄漏报告
pub const LeakReport = struct {
    leaked_allocations: usize,
    leaked_bytes: usize,
    total_allocated: usize,
    total_freed: usize,
};

test "内存泄漏检测功能" {
    const testing = std.testing;
    
    var detector = LeakDetector.init(testing.allocator);
    defer detector.deinit();
    
    // 模拟分配
    try detector.trackAllocation(0x1000, 100, "test.zig:42");
    try detector.trackAllocation(0x2000, 200, "test.zig:43");
    
    // 模拟释放一个
    detector.trackDeallocation(0x1000);
    
    const report = detector.getLeakReport();
    try testing.expect(report.leaked_allocations == 1);
    try testing.expect(report.leaked_bytes == 200);
    try testing.expect(report.total_allocated == 300);
    try testing.expect(report.total_freed == 100);
    
    try testing.expect(detector.hasLeaks() == true);
    
    // 释放剩余的
    detector.trackDeallocation(0x2000);
    try testing.expect(detector.hasLeaks() == false);
}
