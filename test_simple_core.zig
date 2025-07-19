//! 简单的错误处理系统测试
//! 用于验证错误处理系统的基本功能

const std = @import("std");
const testing = std.testing;

// 测试统一错误处理系统
const error_system = @import("src/error/unified_error_system.zig");

test "统一错误处理系统测试" {
    std.debug.print("\n=== 测试统一错误处理系统 ===\n", .{});

    // 测试错误创建
    const io_error = error_system.ZokioError{ .io = .{
        .kind = .file_not_found,
        .message = "测试文件未找到",
        .path = "/test/file.txt",
    } };

    // 测试错误严重级别
    const severity = io_error.getSeverity();
    try testing.expect(severity == .warning);

    std.debug.print("✅ 统一错误处理系统测试通过\n", .{});
}
