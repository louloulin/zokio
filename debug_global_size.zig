//! 调试全局数据大小问题

const std = @import("std");

pub fn main() !void {
    std.debug.print("=== 调试全局数据大小 ===\n", .{});

    // 测试1: 不导入zokio
    std.debug.print("1. 基础程序启动成功\n", .{});

    // 测试2: 导入zokio
    const zokio = @import("zokio");
    std.debug.print("2. 导入zokio成功\n", .{});

    // 测试3: 检查DefaultRuntime大小
    std.debug.print("3. DefaultRuntime大小: {} bytes\n", .{@sizeOf(zokio.DefaultRuntime)});

    // 测试4: 检查各个配置的Runtime类型大小
    std.debug.print("4. 检查各配置Runtime类型大小:\n", .{});

    // 检查内存优化Runtime
    std.debug.print("   MemoryOptimizedRuntime: {} bytes\n", .{@sizeOf(zokio.MemoryOptimizedRuntime)});

    // 检查平衡Runtime
    std.debug.print("   BalancedRuntime: {} bytes\n", .{@sizeOf(zokio.BalancedRuntime)});

    // 检查低延迟Runtime
    std.debug.print("   LowLatencyRuntime: {} bytes\n", .{@sizeOf(zokio.LowLatencyRuntime)});

    // 检查I/O密集型Runtime
    std.debug.print("   IOIntensiveRuntime: {} bytes\n", .{@sizeOf(zokio.IOIntensiveRuntime)});

    // 检查极致性能Runtime - 这个可能是问题所在！
    std.debug.print("   检查极致性能Runtime...\n", .{});
    std.debug.print("   HighPerformanceRuntime: {} bytes\n", .{@sizeOf(zokio.HighPerformanceRuntime)});

    // 测试5: 模拟comprehensive_benchmark的使用模式
    std.debug.print("5. 模拟comprehensive_benchmark使用模式:\n", .{});

    // 创建GPA - 这里可能是问题所在
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    std.debug.print("   GPA创建成功\n", .{});

    // 测试build函数调用
    std.debug.print("   测试build函数调用...\n", .{});
    _ = allocator; // 标记为已使用

    std.debug.print("=== 调试完成 ===\n", .{});
}
