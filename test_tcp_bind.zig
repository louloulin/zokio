//! 测试TCP绑定功能
//! 用于诊断AddressNotAvailable错误

const std = @import("std");
const zokio = @import("zokio");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🔍 测试Zokio TCP绑定功能\n", .{});
    print("=" ** 40 ++ "\n\n", .{});

    // 测试1: 地址解析
    print("📍 测试1: 地址解析\n", .{});
    const address = zokio.net.SocketAddr.parse("127.0.0.1:9090") catch |err| {
        print("❌ 地址解析失败: {}\n", .{err});
        return;
    };
    print("✅ 地址解析成功: {any}\n", .{address});
    print("   IP: {any}\n", .{address.ip()});
    print("   端口: {}\n", .{address.port()});
    print("   是IPv4: {}\n\n", .{address.isIpv4()});

    // 测试2: 使用标准库直接绑定
    print("📍 测试2: 标准库直接绑定\n", .{});
    const std_addr = try std.net.Address.parseIp("127.0.0.1", 9090);
    if (std_addr.listen(.{
        .reuse_address = true,
    })) |std_listener| {
        print("✅ 标准库绑定成功\n", .{});
        var mutable_listener = std_listener;
        mutable_listener.deinit();
    } else |err| {
        print("❌ 标准库绑定失败: {}\n", .{err});
    }
    print("\n", .{});

    // 测试3: Zokio TCP绑定
    print("📍 测试3: Zokio TCP绑定\n", .{});
    var listener = zokio.net.tcp.TcpListener.bind(allocator, address) catch |err| {
        print("❌ Zokio绑定失败: {}\n", .{err});

        // 详细错误分析
        print("\n🔍 错误分析:\n", .{});
        switch (err) {
            error.AddressNotAvailable => {
                print("   - 地址不可用，可能原因:\n", .{});
                print("     * 端口已被占用\n", .{});
                print("     * 权限不足\n", .{});
                print("     * 地址格式错误\n", .{});
                print("     * 系统网络配置问题\n", .{});
            },
            error.AddressInUse => {
                print("   - 地址已在使用中\n", .{});
            },
            error.PermissionDenied => {
                print("   - 权限被拒绝\n", .{});
            },
            else => {
                print("   - 其他错误: {}\n", .{err});
            },
        }

        // 尝试其他端口
        print("\n🔄 尝试其他端口...\n", .{});
        const ports = [_]u16{ 9091, 9092, 9093, 8888, 7777 };
        for (ports) |port| {
            const addr_str = std.fmt.allocPrint(allocator, "127.0.0.1:{}", .{port}) catch continue;
            defer allocator.free(addr_str);
            const test_addr = zokio.net.SocketAddr.parse(addr_str) catch continue;

            if (zokio.net.tcp.TcpListener.bind(allocator, test_addr)) |test_listener| {
                print("✅ 端口 {} 绑定成功!\n", .{port});
                var mutable_test_listener = test_listener;
                mutable_test_listener.close();
                break;
            } else |_| {
                print("❌ 端口 {} 绑定失败\n", .{port});
            }
        }
        return;
    };

    print("✅ Zokio绑定成功!\n", .{});
    print("   本地地址: {any}\n", .{listener.localAddr()});

    // 清理
    listener.close();

    print("\n🎉 所有测试完成!\n", .{});
}
