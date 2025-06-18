//! 工具函数和辅助类型
//!
//! 提供Zokio运行时所需的各种工具函数和辅助类型。

const std = @import("std");
const builtin = @import("builtin");

pub const platform = @import("platform.zig");

/// 编译时字符串连接
pub fn comptimeConcat(comptime strs: []const []const u8) []const u8 {
    comptime {
        var total_len: usize = 0;
        for (strs) |str| {
            total_len += str.len;
        }

        var result: [total_len]u8 = undefined;
        var pos: usize = 0;
        for (strs) |str| {
            @memcpy(result[pos .. pos + str.len], str);
            pos += str.len;
        }

        const final_result = result;
        return &final_result;
    }
}

/// 编译时字符串格式化
pub fn comptimePrint(comptime fmt: []const u8, args: anytype) []const u8 {
    return comptime std.fmt.comptimePrint(fmt, args);
}

/// 编译时类型名称获取
pub fn typeName(comptime T: type) []const u8 {
    return @typeName(T);
}

/// 编译时大小对齐
pub fn alignForward(comptime T: type, comptime alignment: u29) u29 {
    return std.mem.alignForward(u29, @sizeOf(T), alignment);
}

/// 编译时检查类型是否有特定声明
pub fn hasDecl(comptime T: type, comptime name: []const u8) bool {
    return @hasDecl(T, name);
}

/// 编译时检查类型是否有特定字段
pub fn hasField(comptime T: type, comptime name: []const u8) bool {
    return @hasField(T, name);
}

/// 编译时获取字段类型
pub fn FieldType(comptime T: type, comptime field_name: []const u8) type {
    return @TypeOf(@field(@as(T, undefined), field_name));
}

/// 编译时分支预测优化
pub fn likely(condition: bool) bool {
    return condition; // 简化实现，避免builtin.expect问题
}

pub fn unlikely(condition: bool) bool {
    return condition; // 简化实现，避免builtin.expect问题
}

/// 编译时内存布局优化
pub fn OptimizedStruct(comptime fields: []const std.builtin.Type.StructField) type {
    // 按大小排序字段以减少内存碎片
    const sorted_fields = comptime blk: {
        var sorted = fields[0..fields.len].*;
        std.sort.insertion(std.builtin.Type.StructField, &sorted, {}, struct {
            fn lessThan(_: void, a: std.builtin.Type.StructField, b: std.builtin.Type.StructField) bool {
                return @sizeOf(a.type) > @sizeOf(b.type);
            }
        }.lessThan);
        break :blk sorted;
    };

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = &sorted_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

/// 编译时缓存行对齐分析
pub fn analyzeCacheAlignment(comptime T: type) struct { size: usize, alignment: usize, cache_friendly: bool } {
    const size = @sizeOf(T);
    const alignment = @alignOf(T);
    const cache_line_size = platform.PlatformCapabilities.cache_line_size;

    return .{
        .size = size,
        .alignment = alignment,
        .cache_friendly = size <= cache_line_size and alignment >= @min(size, 8),
    };
}

/// 原子操作包装器
pub const Atomic = struct {
    /// 原子值包装器
    pub fn Value(comptime T: type) type {
        return std.atomic.Value(T);
    }
};

/// 侵入式链表节点
pub fn IntrusiveNode(comptime T: type) type {
    return struct {
        const Self = @This();

        next: ?*Self = null,
        prev: ?*Self = null,

        pub fn data(self: *Self) *T {
            return @fieldParentPtr("node", self);
        }
    };
}

/// 侵入式链表
pub fn IntrusiveList(comptime T: type, comptime node_field: []const u8) type {
    return struct {
        const Self = @This();
        const Node = @TypeOf(@field(@as(T, undefined), node_field));

        head: ?*Node = null,
        tail: ?*Node = null,
        len: usize = 0,

        pub fn init() Self {
            return Self{};
        }

        pub fn pushBack(self: *Self, item: *T) void {
            const node = &@field(item, node_field);
            node.next = null;
            node.prev = self.tail;

            if (self.tail) |tail| {
                tail.next = node;
            } else {
                self.head = node;
            }

            self.tail = node;
            self.len += 1;
        }

        pub fn popFront(self: *Self) ?*T {
            const head = self.head orelse return null;

            self.head = head.next;
            if (self.head) |new_head| {
                new_head.prev = null;
            } else {
                self.tail = null;
            }

            self.len -= 1;
            head.next = null;
            head.prev = null;

            return head.data();
        }

        pub fn remove(self: *Self, item: *T) void {
            const node = &@field(item, node_field);

            if (node.prev) |prev| {
                prev.next = node.next;
            } else {
                self.head = node.next;
            }

            if (node.next) |next| {
                next.prev = node.prev;
            } else {
                self.tail = node.prev;
            }

            node.next = null;
            node.prev = null;
            self.len -= 1;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len == 0;
        }
    };
}

/// 编译时哈希计算
pub fn comptimeHash(comptime str: []const u8) u64 {
    return comptime std.hash_map.hashString(str);
}

/// 编译时随机数生成器（用于编译时常量）
pub fn comptimeRandom(comptime seed: u64) u64 {
    // 简单的编译时伪随机数生成
    return comptime blk: {
        var x = seed;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        break :blk x;
    };
}

// 测试
test "工具函数基础功能" {
    const testing = std.testing;

    // 测试编译时字符串连接
    const result = comptimeConcat(&[_][]const u8{ "Hello", " ", "World" });
    try testing.expectEqualStrings("Hello World", result);

    // 测试类型名称
    const name = typeName(u32);
    try testing.expectEqualStrings("u32", name);

    // 测试分支预测
    try testing.expect(likely(true));
    try testing.expect(!unlikely(false));
}

test "原子操作包装器" {
    const testing = std.testing;

    var atomic_value = Atomic.Value(u32).init(42);

    // 测试基本操作
    try testing.expectEqual(@as(u32, 42), atomic_value.load(.monotonic));

    atomic_value.store(84, .monotonic);
    try testing.expectEqual(@as(u32, 84), atomic_value.load(.monotonic));

    const old_value = atomic_value.swap(168, .monotonic);
    try testing.expectEqual(@as(u32, 84), old_value);
    try testing.expectEqual(@as(u32, 168), atomic_value.load(.monotonic));
}

test "侵入式链表" {
    const testing = std.testing;

    const TestItem = struct {
        value: u32,
        node: IntrusiveNode(@This()),
    };

    var list = IntrusiveList(TestItem, "node").init();

    var item1 = TestItem{ .value = 1, .node = .{} };
    var item2 = TestItem{ .value = 2, .node = .{} };
    var item3 = TestItem{ .value = 3, .node = .{} };

    // 测试插入
    list.pushBack(&item1);
    list.pushBack(&item2);
    list.pushBack(&item3);

    try testing.expectEqual(@as(usize, 3), list.len);
    try testing.expect(!list.isEmpty());

    // 测试弹出
    const popped1 = list.popFront().?;
    try testing.expectEqual(@as(u32, 1), popped1.value);
    try testing.expectEqual(@as(usize, 2), list.len);

    // 测试移除
    list.remove(&item2);
    try testing.expectEqual(@as(usize, 1), list.len);

    const popped2 = list.popFront().?;
    try testing.expectEqual(@as(u32, 3), popped2.value);
    try testing.expect(list.isEmpty());
}
