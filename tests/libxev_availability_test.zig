//! 测试libxev可用性

const std = @import("std");
const testing = std.testing;

test "libxev availability check" {
    // 直接尝试导入libxev
    const libxev = @import("libxev");
    std.debug.print("libxev imported successfully\n", .{});

    // 尝试创建一个Loop
    var loop = try libxev.Loop.init(.{});
    defer loop.deinit();
    std.debug.print("libxev Loop created successfully\n", .{});
}
