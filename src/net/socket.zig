//! Socket地址处理模块
//!
//! 提供IP地址和Socket地址的解析、格式化和操作功能

const std = @import("std");
const builtin = @import("builtin");

/// IPv4地址
pub const Ipv4Addr = struct {
    octets: [4]u8,

    const Self = @This();

    /// 创建IPv4地址
    pub fn init(a: u8, b: u8, c: u8, d: u8) Self {
        return Self{ .octets = .{ a, b, c, d } };
    }

    /// 从字符串解析IPv4地址
    pub fn parse(str: []const u8) !Self {
        var parts = std.mem.splitScalar(u8, str, '.');
        var octets: [4]u8 = undefined;
        var i: usize = 0;

        while (parts.next()) |part| {
            if (i >= 4) return error.InvalidAddress;
            octets[i] = std.fmt.parseInt(u8, part, 10) catch return error.InvalidAddress;
            i += 1;
        }

        if (i != 4) return error.InvalidAddress;
        return Self{ .octets = octets };
    }

    /// 转换为字符串
    pub fn toString(self: Self, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{}.{}.{}.{}", .{ self.octets[0], self.octets[1], self.octets[2], self.octets[3] });
    }

    /// 转换为网络字节序的u32
    pub fn toU32(self: Self) u32 {
        return std.mem.readInt(u32, &self.octets, .big);
    }

    /// 从网络字节序的u32创建
    pub fn fromU32(addr: u32) Self {
        var octets: [4]u8 = undefined;
        std.mem.writeInt(u32, &octets, addr, .big);
        return Self{ .octets = octets };
    }

    /// 检查是否是环回地址
    pub fn isLoopback(self: Self) bool {
        return self.octets[0] == 127;
    }

    /// 检查是否是私有地址
    pub fn isPrivate(self: Self) bool {
        return (self.octets[0] == 10) or
            (self.octets[0] == 172 and self.octets[1] >= 16 and self.octets[1] <= 31) or
            (self.octets[0] == 192 and self.octets[1] == 168);
    }

    /// 检查是否是多播地址
    pub fn isMulticast(self: Self) bool {
        return self.octets[0] >= 224 and self.octets[0] <= 239;
    }

    /// 常用地址常量
    pub const LOCALHOST = Self.init(127, 0, 0, 1);
    pub const UNSPECIFIED = Self.init(0, 0, 0, 0);
    pub const BROADCAST = Self.init(255, 255, 255, 255);
};

/// IPv6地址
pub const Ipv6Addr = struct {
    segments: [8]u16,

    const Self = @This();

    /// 创建IPv6地址
    pub fn init(segments: [8]u16) Self {
        return Self{ .segments = segments };
    }

    /// 从字符串解析IPv6地址
    pub fn parse(str: []const u8) !Self {
        // 简化的IPv6解析实现
        // 在实际实现中需要处理::缩写等复杂情况
        var segments: [8]u16 = std.mem.zeroes([8]u16);
        var parts = std.mem.splitScalar(u8, str, ':');
        var i: usize = 0;

        while (parts.next()) |part| {
            if (i >= 8) return error.InvalidAddress;
            if (part.len == 0) {
                // 处理::缩写（简化版本）
                break;
            }
            segments[i] = std.fmt.parseInt(u16, part, 16) catch return error.InvalidAddress;
            i += 1;
        }

        return Self{ .segments = segments };
    }

    /// 转换为字符串
    pub fn toString(self: Self, buf: []u8) ![]u8 {
        return std.fmt.bufPrint(buf, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{
            self.segments[0], self.segments[1], self.segments[2], self.segments[3],
            self.segments[4], self.segments[5], self.segments[6], self.segments[7],
        });
    }

    /// 检查是否是环回地址
    pub fn isLoopback(self: Self) bool {
        return std.mem.eql(u16, &self.segments, &Self.LOCALHOST.segments);
    }

    /// 检查是否是未指定地址
    pub fn isUnspecified(self: Self) bool {
        return std.mem.eql(u16, &self.segments, &Self.UNSPECIFIED.segments);
    }

    /// 常用地址常量
    pub const LOCALHOST = Self.init(.{ 0, 0, 0, 0, 0, 0, 0, 1 });
    pub const UNSPECIFIED = Self.init(.{ 0, 0, 0, 0, 0, 0, 0, 0 });
};

/// IP地址（IPv4或IPv6）
pub const IpAddr = union(enum) {
    v4: Ipv4Addr,
    v6: Ipv6Addr,

    const Self = @This();

    /// 从字符串解析IP地址
    pub fn parse(str: []const u8) !Self {
        // 尝试解析IPv4
        if (Ipv4Addr.parse(str)) |ipv4| {
            return Self{ .v4 = ipv4 };
        } else |_| {}

        // 尝试解析IPv6
        if (Ipv6Addr.parse(str)) |ipv6| {
            return Self{ .v6 = ipv6 };
        } else |_| {}

        return error.InvalidAddress;
    }

    /// 转换为字符串
    pub fn toString(self: Self, buf: []u8) ![]u8 {
        return switch (self) {
            .v4 => |ipv4| ipv4.toString(buf),
            .v6 => |ipv6| ipv6.toString(buf),
        };
    }

    /// 检查是否是环回地址
    pub fn isLoopback(self: Self) bool {
        return switch (self) {
            .v4 => |ipv4| ipv4.isLoopback(),
            .v6 => |ipv6| ipv6.isLoopback(),
        };
    }

    /// 检查是否是IPv4地址
    pub fn isIpv4(self: Self) bool {
        return switch (self) {
            .v4 => true,
            .v6 => false,
        };
    }

    /// 检查是否是IPv6地址
    pub fn isIpv6(self: Self) bool {
        return switch (self) {
            .v4 => false,
            .v6 => true,
        };
    }
};

/// Socket地址
pub const SocketAddr = union(enum) {
    v4: SocketAddrV4,
    v6: SocketAddrV6,

    const Self = @This();

    /// 从IP地址和端口创建Socket地址
    pub fn init(ip_addr: IpAddr, port_num: u16) Self {
        return switch (ip_addr) {
            .v4 => |ipv4| Self{ .v4 = SocketAddrV4.init(ipv4, port_num) },
            .v6 => |ipv6| Self{ .v6 = SocketAddrV6.init(ipv6, port_num) },
        };
    }

    /// 从字符串解析Socket地址
    pub fn parse(str: []const u8) !Self {
        // 查找最后一个冒号来分离IP和端口
        if (std.mem.lastIndexOf(u8, str, ":")) |colon_pos| {
            const ip_str = str[0..colon_pos];
            const port_str = str[colon_pos + 1 ..];

            const ip_addr = try IpAddr.parse(ip_str);
            const port_num = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidAddress;

            return Self.init(ip_addr, port_num);
        }

        return error.InvalidAddress;
    }

    /// 转换为字符串
    pub fn toString(self: Self, buf: []u8) ![]u8 {
        return switch (self) {
            .v4 => |addr| addr.toString(buf),
            .v6 => |addr| addr.toString(buf),
        };
    }

    /// 获取IP地址
    pub fn ip(self: Self) IpAddr {
        return switch (self) {
            .v4 => |addr| IpAddr{ .v4 = addr.ip },
            .v6 => |addr| IpAddr{ .v6 = addr.ip },
        };
    }

    /// 获取端口
    pub fn port(self: Self) u16 {
        return switch (self) {
            .v4 => |addr| addr.port,
            .v6 => |addr| addr.port,
        };
    }

    /// 检查是否是IPv4地址
    pub fn isIpv4(self: Self) bool {
        return switch (self) {
            .v4 => true,
            .v6 => false,
        };
    }

    /// 检查是否是IPv6地址
    pub fn isIpv6(self: Self) bool {
        return switch (self) {
            .v4 => false,
            .v6 => true,
        };
    }
};

/// IPv4 Socket地址
pub const SocketAddrV4 = struct {
    ip: Ipv4Addr,
    port: u16,

    const Self = @This();

    /// 创建IPv4 Socket地址
    pub fn init(ip: Ipv4Addr, port: u16) Self {
        return Self{ .ip = ip, .port = port };
    }

    /// 转换为字符串
    pub fn toString(self: Self, buf: []u8) ![]u8 {
        var ip_buf: [16]u8 = undefined;
        const ip_str = try self.ip.toString(&ip_buf);
        return std.fmt.bufPrint(buf, "{s}:{}", .{ ip_str, self.port });
    }
};

/// IPv6 Socket地址
pub const SocketAddrV6 = struct {
    ip: Ipv6Addr,
    port: u16,
    flowinfo: u32 = 0,
    scope_id: u32 = 0,

    const Self = @This();

    /// 创建IPv6 Socket地址
    pub fn init(ip: Ipv6Addr, port: u16) Self {
        return Self{ .ip = ip, .port = port };
    }

    /// 转换为字符串
    pub fn toString(self: Self, buf: []u8) ![]u8 {
        var ip_buf: [40]u8 = undefined;
        const ip_str = try self.ip.toString(&ip_buf);
        return std.fmt.bufPrint(buf, "[{s}]:{}", .{ ip_str, self.port });
    }
};

// 测试
test "IPv4地址解析和格式化" {
    const testing = std.testing;

    const addr = try Ipv4Addr.parse("192.168.1.1");
    try testing.expectEqual(@as(u8, 192), addr.octets[0]);
    try testing.expectEqual(@as(u8, 168), addr.octets[1]);
    try testing.expectEqual(@as(u8, 1), addr.octets[2]);
    try testing.expectEqual(@as(u8, 1), addr.octets[3]);

    var buf: [16]u8 = undefined;
    const str = try addr.toString(&buf);
    try testing.expect(std.mem.eql(u8, "192.168.1.1", str));

    try testing.expect(addr.isPrivate());
    try testing.expect(!addr.isLoopback());
    try testing.expect(!addr.isMulticast());
}

test "IPv4地址特殊检查" {
    const testing = std.testing;

    try testing.expect(Ipv4Addr.LOCALHOST.isLoopback());
    try testing.expect(!Ipv4Addr.LOCALHOST.isPrivate());

    const private_addr = Ipv4Addr.init(10, 0, 0, 1);
    try testing.expect(private_addr.isPrivate());

    const multicast_addr = Ipv4Addr.init(224, 0, 0, 1);
    try testing.expect(multicast_addr.isMulticast());
}

test "Socket地址解析和格式化" {
    const testing = std.testing;

    const addr = try SocketAddr.parse("192.168.1.1:8080");
    try testing.expect(addr.isIpv4());
    try testing.expectEqual(@as(u16, 8080), addr.port());

    const ip = addr.ip();
    try testing.expect(ip.isIpv4());

    var buf: [32]u8 = undefined;
    const str = try addr.toString(&buf);
    try testing.expect(std.mem.eql(u8, "192.168.1.1:8080", str));
}
