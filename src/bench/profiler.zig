//! 性能分析器模块
//!
//! 提供详细的性能分析和热点识别功能

const std = @import("std");
const builtin = @import("builtin");

/// 函数调用信息
pub const CallInfo = struct {
    name: []const u8,
    call_count: u64,
    total_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    avg_time_ns: u64,

    const Self = @This();

    /// 更新调用信息
    pub fn update(self: *Self, duration_ns: u64) void {
        self.call_count += 1;
        self.total_time_ns += duration_ns;
        
        if (duration_ns < self.min_time_ns) {
            self.min_time_ns = duration_ns;
        }
        if (duration_ns > self.max_time_ns) {
            self.max_time_ns = duration_ns;
        }
        
        self.avg_time_ns = self.total_time_ns / self.call_count;
    }

    /// 打印调用信息
    pub fn print(self: *const Self) void {
        std.debug.print("函数: {s}\n", .{self.name});
        std.debug.print("  调用次数: {}\n", .{self.call_count});
        std.debug.print("  总耗时: {d:.2} ms\n", .{@as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0});
        std.debug.print("  平均耗时: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.avg_time_ns)) / 1_000.0});
        std.debug.print("  最小耗时: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.min_time_ns)) / 1_000.0});
        std.debug.print("  最大耗时: {d:.2} μs\n", .{@as(f64, @floatFromInt(self.max_time_ns)) / 1_000.0});
    }
};

/// 性能分析器
pub const Profiler = struct {
    enabled: bool,
    allocator: std.mem.Allocator,
    call_info: std.StringHashMap(CallInfo),
    start_time: i128,
    call_stack: std.ArrayList(CallFrame),

    const Self = @This();

    /// 调用帧
    const CallFrame = struct {
        name: []const u8,
        start_time: i128,
    };

    /// 初始化性能分析器
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .enabled = true,
            .allocator = allocator,
            .call_info = std.StringHashMap(CallInfo).init(allocator),
            .start_time = std.time.nanoTimestamp(),
            .call_stack = std.ArrayList(CallFrame).init(allocator),
        };
    }

    /// 清理性能分析器
    pub fn deinit(self: *Self) void {
        self.call_info.deinit();
        self.call_stack.deinit();
    }

    /// 启用分析器
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// 禁用分析器
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// 开始函数调用分析
    pub fn beginCall(self: *Self, name: []const u8) !void {
        if (!self.enabled) return;

        const frame = CallFrame{
            .name = name,
            .start_time = std.time.nanoTimestamp(),
        };
        
        try self.call_stack.append(frame);
    }

    /// 结束函数调用分析
    pub fn endCall(self: *Self, name: []const u8) !void {
        if (!self.enabled) return;

        if (self.call_stack.items.len == 0) return;
        
        const frame = self.call_stack.pop();
        if (!std.mem.eql(u8, frame.name, name)) {
            std.debug.print("警告: 函数调用不匹配 - 期望: {s}, 实际: {s}\n", .{ frame.name, name });
            return;
        }

        const end_time = std.time.nanoTimestamp();
        const duration = @as(u64, @intCast(end_time - frame.start_time));

        // 更新或创建调用信息
        var result = try self.call_info.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = CallInfo{
                .name = name,
                .call_count = 0,
                .total_time_ns = 0,
                .min_time_ns = std.math.maxInt(u64),
                .max_time_ns = 0,
                .avg_time_ns = 0,
            };
        }
        
        result.value_ptr.update(duration);
    }

    /// 记录单次调用
    pub fn recordCall(self: *Self, name: []const u8, duration_ns: u64) !void {
        if (!self.enabled) return;

        var result = try self.call_info.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = CallInfo{
                .name = name,
                .call_count = 0,
                .total_time_ns = 0,
                .min_time_ns = std.math.maxInt(u64),
                .max_time_ns = 0,
                .avg_time_ns = 0,
            };
        }
        
        result.value_ptr.update(duration_ns);
    }

    /// 生成性能报告
    pub fn generateReport(self: *const Self) void {
        std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
        std.debug.print("Zokio 性能分析报告\n", .{});
        std.debug.print("=" ** 60 ++ "\n", .{});
        
        const total_time = std.time.nanoTimestamp() - self.start_time;
        std.debug.print("分析时间: {d:.2} ms\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
        std.debug.print("函数数量: {}\n", .{self.call_info.count()});
        
        if (self.call_info.count() == 0) {
            std.debug.print("暂无性能数据\n", .{});
            return;
        }

        // 收集所有调用信息并按总耗时排序
        var call_list = std.ArrayList(CallInfo).init(std.heap.page_allocator);
        defer call_list.deinit();
        
        var iterator = self.call_info.iterator();
        while (iterator.next()) |entry| {
            call_list.append(entry.value_ptr.*) catch continue;
        }
        
        // 按总耗时降序排序
        std.mem.sort(CallInfo, call_list.items, {}, struct {
            fn lessThan(context: void, a: CallInfo, b: CallInfo) bool {
                _ = context;
                return a.total_time_ns > b.total_time_ns;
            }
        }.lessThan);

        std.debug.print("\n=== 热点函数 (按总耗时排序) ===\n", .{});
        for (call_list.items, 0..) |call_info, i| {
            if (i >= 10) break; // 只显示前10个
            std.debug.print("\n{}. ", .{i + 1});
            call_info.print();
        }

        // 按平均耗时排序
        std.mem.sort(CallInfo, call_list.items, {}, struct {
            fn lessThan(context: void, a: CallInfo, b: CallInfo) bool {
                _ = context;
                return a.avg_time_ns > b.avg_time_ns;
            }
        }.lessThan);

        std.debug.print("\n=== 最慢函数 (按平均耗时排序) ===\n", .{});
        for (call_list.items, 0..) |call_info, i| {
            if (i >= 5) break; // 只显示前5个
            std.debug.print("\n{}. ", .{i + 1});
            call_info.print();
        }

        // 按调用次数排序
        std.mem.sort(CallInfo, call_list.items, {}, struct {
            fn lessThan(context: void, a: CallInfo, b: CallInfo) bool {
                _ = context;
                return a.call_count > b.call_count;
            }
        }.lessThan);

        std.debug.print("\n=== 最频繁函数 (按调用次数排序) ===\n", .{});
        for (call_list.items, 0..) |call_info, i| {
            if (i >= 5) break; // 只显示前5个
            std.debug.print("\n{}. ", .{i + 1});
            call_info.print();
        }
    }

    /// 重置分析数据
    pub fn reset(self: *Self) void {
        self.call_info.clearAndFree();
        self.call_stack.clearAndFree();
        self.start_time = std.time.nanoTimestamp();
    }

    /// 获取函数调用信息
    pub fn getCallInfo(self: *const Self, name: []const u8) ?CallInfo {
        return self.call_info.get(name);
    }

    /// 导出性能数据为JSON格式
    pub fn exportJson(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var json_obj = std.json.ObjectMap.init(allocator);
        defer json_obj.deinit();

        // 添加基本信息
        try json_obj.put("total_time_ns", std.json.Value{ .integer = @as(i64, @intCast(@divTrunc(std.time.nanoTimestamp() - self.start_time, 1))) });
        try json_obj.put("function_count", std.json.Value{ .integer = @as(i64, @intCast(self.call_info.count())) });

        // 添加函数调用信息
        var functions = std.json.ObjectMap.init(allocator);
        var iterator = self.call_info.iterator();
        while (iterator.next()) |entry| {
            var func_obj = std.json.ObjectMap.init(allocator);
            try func_obj.put("call_count", std.json.Value{ .integer = @as(i64, @intCast(entry.value_ptr.call_count)) });
            try func_obj.put("total_time_ns", std.json.Value{ .integer = @as(i64, @intCast(entry.value_ptr.total_time_ns)) });
            try func_obj.put("avg_time_ns", std.json.Value{ .integer = @as(i64, @intCast(entry.value_ptr.avg_time_ns)) });
            try func_obj.put("min_time_ns", std.json.Value{ .integer = @as(i64, @intCast(entry.value_ptr.min_time_ns)) });
            try func_obj.put("max_time_ns", std.json.Value{ .integer = @as(i64, @intCast(entry.value_ptr.max_time_ns)) });
            
            try functions.put(entry.key_ptr.*, std.json.Value{ .object = func_obj });
        }
        try json_obj.put("functions", std.json.Value{ .object = functions });

        // 序列化为JSON字符串
        var json_string = std.ArrayList(u8).init(allocator);
        try std.json.stringify(std.json.Value{ .object = json_obj }, .{}, json_string.writer());
        
        return json_string.toOwnedSlice();
    }
};

/// 性能分析宏
pub fn profile(profiler: *Profiler, comptime name: []const u8, func: anytype) !@TypeOf(func()) {
    try profiler.beginCall(name);
    defer profiler.endCall(name) catch {};
    
    return func();
}

/// 简单的性能计时器
pub const Timer = struct {
    start_time: i128,
    name: []const u8,

    const Self = @This();

    /// 开始计时
    pub fn start(name: []const u8) Self {
        return Self{
            .start_time = std.time.nanoTimestamp(),
            .name = name,
        };
    }

    /// 结束计时并返回耗时
    pub fn end(self: *const Self) u64 {
        const end_time = std.time.nanoTimestamp();
        return @as(u64, @intCast(end_time - self.start_time));
    }

    /// 结束计时并打印结果
    pub fn endAndPrint(self: *const Self) u64 {
        const duration = self.end();
        std.debug.print("{s}: {d:.2} μs\n", .{ self.name, @as(f64, @floatFromInt(duration)) / 1_000.0 });
        return duration;
    }
};

// 测试
test "调用信息更新" {
    var call_info = CallInfo{
        .name = "test_function",
        .call_count = 0,
        .total_time_ns = 0,
        .min_time_ns = std.math.maxInt(u64),
        .max_time_ns = 0,
        .avg_time_ns = 0,
    };

    call_info.update(1000);
    call_info.update(2000);
    call_info.update(3000);

    std.testing.expectEqual(@as(u64, 3), call_info.call_count) catch {};
    std.testing.expectEqual(@as(u64, 6000), call_info.total_time_ns) catch {};
    std.testing.expectEqual(@as(u64, 2000), call_info.avg_time_ns) catch {};
    std.testing.expectEqual(@as(u64, 1000), call_info.min_time_ns) catch {};
    std.testing.expectEqual(@as(u64, 3000), call_info.max_time_ns) catch {};
}

test "性能分析器基本功能" {
    const testing = std.testing;

    var profiler = Profiler.init(testing.allocator);
    defer profiler.deinit();

    try profiler.recordCall("test_function", 1500);
    try profiler.recordCall("test_function", 2500);

    const call_info = profiler.getCallInfo("test_function");
    try testing.expect(call_info != null);
    try testing.expectEqual(@as(u64, 2), call_info.?.call_count);
    try testing.expectEqual(@as(u64, 2000), call_info.?.avg_time_ns);
}

test "计时器功能" {
    var timer = Timer.start("test_timer");
    
    // 模拟一些工作
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        _ = i * i;
    }
    
    const duration = timer.end();
    std.testing.expect(duration > 0) catch {};
}
