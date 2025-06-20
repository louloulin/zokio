//! 简单的libxev测试

const std = @import("std");
const testing = std.testing;
const zokio = @import("zokio");

test "简单的libxev常量测试" {
    const config = zokio.io.IoConfig{
        .prefer_libxev = true,
        .events_capacity = 64,
    };

    const DriverType = zokio.io.IoDriver(config);

    // 测试常量是否存在
    std.debug.print("BACKEND_TYPE: {}\n", .{DriverType.BACKEND_TYPE});
    std.debug.print("SUPPORTS_BATCH: {}\n", .{DriverType.SUPPORTS_BATCH});

    // 验证后端类型
    try testing.expectEqual(zokio.io.IoBackendType.libxev, DriverType.BACKEND_TYPE);
    try testing.expect(DriverType.SUPPORTS_BATCH);
}
