//! 简单的测试运行器
//! 用于验证基础模块的测试

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("🧪 开始运行 Zokio 基础模块测试...\n", .{});
    
    // 测试列表 - 只包含不依赖 libxev 的模块
    const tests = [_][]const u8{
        "src/error/unified_error_system.zig",
        "src/utils/utils.zig",
        "src/memory/memory.zig",
        "src/sync/sync.zig",
        "src/time/time.zig",
    };
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    for (tests) |test_file| {
        total += 1;
        std.debug.print("\n🔍 测试: {s}\n", .{test_file});
        
        // 运行测试
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zig", "test", test_file },
        }) catch |err| {
            std.debug.print("  ❌ 执行失败: {any}\n", .{err});
            continue;
        };
        
        if (result.term.Exited == 0) {
            std.debug.print("  ✅ 通过\n", .{});
            passed += 1;
        } else {
            std.debug.print("  ❌ 失败\n", .{});
            if (result.stderr.len > 0) {
                std.debug.print("  错误: {s}\n", .{result.stderr});
            }
        }
        
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    
    std.debug.print("\n📋 测试结果: {}/{} 通过\n", .{ passed, total });
    
    if (passed == total) {
        std.debug.print("🎉 所有测试都通过了！\n", .{});
    } else {
        std.debug.print("⚠️  有 {} 个测试失败\n", .{total - passed});
    }
}
