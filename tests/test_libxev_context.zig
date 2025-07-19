//! 🔧 测试libxev在AsyncEventLoop上下文中的行为
//! 分析为什么在AsyncEventLoop.init()中libxev.Loop.init()会卡住

const std = @import("std");
const testing = std.testing;
const libxev = @import("libxev");

test "直接测试libxev.Loop.init()" {
    std.debug.print("\n=== 直接libxev测试 ===\n", .{});

    std.debug.print("1. 创建libxev.Loop...\n", .{});
    var loop = libxev.Loop.init(.{}) catch |err| {
        std.debug.print("❌ libxev.Loop.init()失败: {}\n", .{err});
        return err;
    };
    defer loop.deinit();
    std.debug.print("✅ libxev.Loop创建成功\n", .{});

    std.debug.print("2. 测试非阻塞运行...\n", .{});
    _ = loop.run(.no_wait) catch |err| {
        std.debug.print("❌ loop.run()失败: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ libxev.Loop运行成功\n", .{});
}

test "在结构体中测试libxev.Loop.init()" {
    std.debug.print("\n=== 结构体中libxev测试 ===\n", .{});

    const TestStruct = struct {
        loop: libxev.Loop,
        value: u32,

        pub fn init() !@This() {
            std.debug.print("   TestStruct.init() 开始\n", .{});
            
            std.debug.print("   创建libxev.Loop...\n", .{});
            const loop = libxev.Loop.init(.{}) catch |err| {
                std.debug.print("   ❌ libxev.Loop.init()失败: {}\n", .{err});
                return err;
            };
            std.debug.print("   libxev.Loop创建成功\n", .{});

            std.debug.print("   TestStruct.init() 完成\n", .{});
            return @This(){
                .loop = loop,
                .value = 42,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.loop.deinit();
        }
    };

    std.debug.print("1. 创建TestStruct...\n", .{});
    var test_struct = TestStruct.init() catch |err| {
        std.debug.print("❌ TestStruct.init()失败: {}\n", .{err});
        return err;
    };
    defer test_struct.deinit();
    std.debug.print("✅ TestStruct创建成功，值: {}\n", .{test_struct.value});
}

test "模拟AsyncEventLoop的最小结构" {
    std.debug.print("\n=== 最小AsyncEventLoop模拟 ===\n", .{});

    const MinimalEventLoop = struct {
        libxev_loop: libxev.Loop,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            std.debug.print("   MinimalEventLoop.init() 开始\n", .{});
            
            std.debug.print("   创建libxev.Loop...\n", .{});
            const libxev_loop = libxev.Loop.init(.{}) catch |err| {
                std.debug.print("   ❌ libxev.Loop.init()失败: {}\n", .{err});
                return err;
            };
            std.debug.print("   libxev.Loop创建成功\n", .{});

            std.debug.print("   MinimalEventLoop.init() 完成\n", .{});
            return @This(){
                .libxev_loop = libxev_loop,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.libxev_loop.deinit();
        }
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("1. 创建MinimalEventLoop...\n", .{});
    var minimal_loop = MinimalEventLoop.init(allocator) catch |err| {
        std.debug.print("❌ MinimalEventLoop.init()失败: {}\n", .{err});
        return err;
    };
    defer minimal_loop.deinit();
    std.debug.print("✅ MinimalEventLoop创建成功\n", .{});
}

test "测试多次libxev.Loop.init()调用" {
    std.debug.print("\n=== 多次libxev初始化测试 ===\n", .{});

    std.debug.print("1. 第一次创建libxev.Loop...\n", .{});
    var loop1 = libxev.Loop.init(.{}) catch |err| {
        std.debug.print("❌ 第一次libxev.Loop.init()失败: {}\n", .{err});
        return err;
    };
    defer loop1.deinit();
    std.debug.print("✅ 第一次libxev.Loop创建成功\n", .{});

    std.debug.print("2. 第二次创建libxev.Loop...\n", .{});
    var loop2 = libxev.Loop.init(.{}) catch |err| {
        std.debug.print("❌ 第二次libxev.Loop.init()失败: {}\n", .{err});
        return err;
    };
    defer loop2.deinit();
    std.debug.print("✅ 第二次libxev.Loop创建成功\n", .{});

    std.debug.print("✅ 多次libxev初始化测试完成\n", .{});
}
