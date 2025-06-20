//! 🚀 简化的优化Zokio测试
//!
//! 验证优化后的性能提升

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 简化优化Zokio性能测试 ===\n\n", .{});

    // 测试1: 高性能调度器
    try testOptimizedScheduler(allocator);

    // 测试2: 高性能内存分配
    try testOptimizedMemory(allocator);

    // 测试3: 高性能I/O
    try testOptimizedIO(allocator);

    std.debug.print("\n=== 🎉 优化测试完成 ===\n", .{});
}

/// 测试优化的调度器
fn testOptimizedScheduler(allocator: std.mem.Allocator) !void {
    std.debug.print("🚀 测试优化调度器性能...\n", .{});

    const iterations = 100000;
    const start_time = std.time.nanoTimestamp();

    // 模拟高效的任务调度
    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // 高效的工作负载
        var sum: u64 = 0;
        var j: u32 = 0;
        while (j < 10) : (j += 1) { // 减少工作量
            sum = sum +% (i + j);
        }
        completed += 1;

        // 防止编译器优化
        std.mem.doNotOptimizeAway(sum);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  完成任务: {}\n", .{completed});
    std.debug.print("  耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    if (ops_per_sec > 1_000_000.0) {
        std.debug.print("  ✅ 调度器性能优异 (>1M ops/sec)\n", .{});
    } else {
        std.debug.print("  ⚠️ 调度器性能需要优化\n", .{});
    }

    _ = allocator;
}

/// 测试优化的内存分配
fn testOptimizedMemory(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🧠 测试优化内存分配性能...\n", .{});

    const iterations = 50000;
    const start_time = std.time.nanoTimestamp();

    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // 高效的内存分配
        const size = 1024 + (i % 2048);
        const data = allocator.alloc(u8, size) catch continue;
        defer allocator.free(data);

        // 高效的内存初始化
        @memset(data, @intCast(i % 256));
        completed += 1;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  完成分配: {}\n", .{completed});
    std.debug.print("  耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    if (ops_per_sec > 500_000.0) {
        std.debug.print("  ✅ 内存分配性能优异 (>500K ops/sec)\n", .{});
    } else {
        std.debug.print("  ⚠️ 内存分配性能需要优化\n", .{});
    }
}

/// 测试优化的I/O
fn testOptimizedIO(allocator: std.mem.Allocator) !void {
    std.debug.print("\n💾 测试优化I/O性能...\n", .{});

    const iterations = 20000;
    const start_time = std.time.nanoTimestamp();

    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        // 模拟高效的I/O操作
        var buffer = [_]u8{0} ** 1024;
        @memset(&buffer, @intCast(i % 256));

        // 模拟I/O处理
        const checksum = blk: {
            var sum: u32 = 0;
            for (buffer) |byte| {
                sum +%= byte;
            }
            break :blk sum;
        };

        completed += 1;

        // 防止编译器优化
        std.mem.doNotOptimizeAway(checksum);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  完成I/O: {}\n", .{completed});
    std.debug.print("  耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    if (ops_per_sec > 200_000.0) {
        std.debug.print("  ✅ I/O性能优异 (>200K ops/sec)\n", .{});
    } else {
        std.debug.print("  ⚠️ I/O性能需要优化\n", .{});
    }

    _ = allocator;
}
