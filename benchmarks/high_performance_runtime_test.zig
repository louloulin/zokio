//! 🚀 高性能运行时测试
//!
//! 真正使用Zokio运行时API进行测试，验证性能提升

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🚀 Zokio高性能运行时API测试 ===\n\n", .{});

    // 测试1: 极致性能运行时
    try testHighPerformanceRuntime(allocator);

    // 测试2: 低延迟运行时
    try testLowLatencyRuntime(allocator);

    // 测试3: I/O密集型运行时
    try testIOIntensiveRuntime(allocator);

    // 测试4: 运行时API功能测试
    try testRuntimeAPIs(allocator);

    std.debug.print("\n=== 🎉 测试完成 ===\n", .{});
}

/// 🔥 测试极致性能运行时
fn testHighPerformanceRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("� 测试极致性能运行时...\n", .{});

    // 创建高性能运行时
    var runtime = try zokio.HighPerformanceRuntime.init(allocator);
    defer runtime.deinit();

    // 显示编译时信息
    std.debug.print("  � 配置名称: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("  🏗️ 性能配置: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.performance_profile});
    std.debug.print("  🔧 工作线程: {}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.worker_threads});
    std.debug.print("  💾 内存策略: {s}\n", .{zokio.HighPerformanceRuntime.COMPILE_TIME_INFO.memory_strategy});
    std.debug.print("  ⚡ libxev启用: {}\n", .{zokio.HighPerformanceRuntime.LIBXEV_ENABLED});

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 🚀 使用真实的Zokio API进行异步任务测试
    const TestTask = struct {
        id: u32,
        work_units: u32,

        const Self = @This();
        pub const Output = u64;

        pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(u64) {
            _ = ctx;

            // 执行计算工作负载
            var sum: u64 = 0;
            var i: u32 = 0;
            while (i < self.work_units) : (i += 1) {
                sum = sum +% (self.id + i);
            }

            return .{ .ready = sum };
        }
    };

    const iterations = 10000;
    const start_time = std.time.nanoTimestamp();

    // 🔥 使用运行时spawn API创建异步任务
    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const task = TestTask{
            .id = i,
            .work_units = 100,
        };

        // 使用blockOn执行任务
        const result = try runtime.blockOn(task);
        completed += 1;

        // 防止编译器优化
        std.mem.doNotOptimizeAway(result);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  🚀 完成任务: {}\n", .{completed});
    std.debug.print("  ⏱️ 耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  📈 吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    if (ops_per_sec > 100_000.0) {
        std.debug.print("  ✅ 极致性能运行时表现优异\n", .{});
    } else {
        std.debug.print("  ⚠️ 性能需要优化\n", .{});
    }
}

/// ⚡ 测试低延迟运行时
fn testLowLatencyRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("\n⚡ 测试低延迟运行时...\n", .{});

    var runtime = try zokio.LowLatencyRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("  📊 配置名称: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("  🏗️ 性能配置: {s}\n", .{zokio.LowLatencyRuntime.COMPILE_TIME_INFO.performance_profile});

    try runtime.start();
    defer runtime.stop();

    // � 低延迟任务测试
    const LowLatencyTask = struct {
        id: u32,

        const Self = @This();
        pub const Output = u32;

        pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(u32) {
            _ = ctx;
            // 极简工作负载，专注低延迟
            return .{ .ready = self.id * 2 };
        }
    };

    const iterations = 50000;
    const start_time = std.time.nanoTimestamp();

    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const task = LowLatencyTask{ .id = i };
        const result = try runtime.blockOn(task);
        completed += 1;
        std.mem.doNotOptimizeAway(result);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  🚀 完成任务: {}\n", .{completed});
    std.debug.print("  ⏱️ 耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  � 吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    if (ops_per_sec > 500_000.0) {
        std.debug.print("  ✅ 低延迟运行时表现优异\n", .{});
    } else {
        std.debug.print("  ⚠️ 延迟性能需要优化\n", .{});
    }
}

/// 🌐 测试I/O密集型运行时
fn testIOIntensiveRuntime(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🌐 测试I/O密集型运行时...\n", .{});

    var runtime = try zokio.IOIntensiveRuntime.init(allocator);
    defer runtime.deinit();

    std.debug.print("  📊 配置名称: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.config_name});
    std.debug.print("  🏗️ 性能配置: {s}\n", .{zokio.IOIntensiveRuntime.COMPILE_TIME_INFO.performance_profile});

    try runtime.start();
    defer runtime.stop();

    // 🚀 I/O密集型任务测试
    const IOTask = struct {
        id: u32,
        data_size: u32,

        const Self = @This();
        pub const Output = u32;

        pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(u32) {
            _ = ctx;

            // 模拟I/O操作
            var buffer = [_]u8{0} ** 1024;
            @memset(&buffer, @intCast(self.id % 256));

            // 计算校验和模拟I/O处理
            var checksum: u32 = 0;
            for (buffer[0..self.data_size]) |byte| {
                checksum +%= byte;
            }

            return .{ .ready = checksum };
        }
    };

    const iterations = 20000;
    const start_time = std.time.nanoTimestamp();

    var completed: u64 = 0;
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const task = IOTask{
            .id = i,
            .data_size = 512 + (i % 512), // 可变数据大小
        };
        const result = try runtime.blockOn(task);
        completed += 1;
        std.mem.doNotOptimizeAway(result);
    }

    const end_time = std.time.nanoTimestamp();
    const duration = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, @floatFromInt(completed)) / duration;

    std.debug.print("  🚀 完成I/O任务: {}\n", .{completed});
    std.debug.print("  ⏱️ 耗时: {d:.3} 秒\n", .{duration});
    std.debug.print("  📈 I/O吞吐量: {d:.0} ops/sec\n", .{ops_per_sec});

    if (ops_per_sec > 200_000.0) {
        std.debug.print("  ✅ I/O密集型运行时表现优异\n", .{});
    } else {
        std.debug.print("  ⚠️ I/O性能需要优化\n", .{});
    }
}

/// 🔧 测试运行时API功能
fn testRuntimeAPIs(allocator: std.mem.Allocator) !void {
    std.debug.print("\n🔧 测试运行时API功能...\n", .{});

    var runtime = try zokio.DefaultRuntime.init(allocator);
    defer runtime.deinit();

    try runtime.start();
    defer runtime.stop();

    // 测试1: spawnTask API
    std.debug.print("  📋 测试spawnTask API...\n", .{});

    const SimpleTask = struct {
        value: u32,

        const Self = @This();
        pub const Output = u32;

        pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(u32) {
            _ = ctx;
            return .{ .ready = self.value * 3 };
        }
    };

    const task = SimpleTask{ .value = 42 };
    const spawn_result = try runtime.spawnTask(task);
    std.debug.print("    ✅ spawnTask结果: {}\n", .{spawn_result});

    // 测试2: spawnBlocking API
    std.debug.print("  📋 测试spawnBlocking API...\n", .{});

    const blocking_result = try runtime.spawnBlocking(struct {
        fn blockingWork() u32 {
            var sum: u32 = 0;
            var i: u32 = 0;
            while (i < 1000) : (i += 1) {
                sum += i;
            }
            return sum;
        }
    }.blockingWork);
    std.debug.print("    ✅ spawnBlocking结果: {}\n", .{blocking_result});

    // 测试3: 运行时统计
    std.debug.print("  📊 测试运行时统计...\n", .{});
    const stats = runtime.getStats();
    std.debug.print("    📈 运行状态: {}\n", .{stats.running});
    std.debug.print("    🧵 线程数量: {}\n", .{stats.thread_count});

    // 测试4: 性能报告
    std.debug.print("  📋 测试性能报告...\n", .{});
    const perf_report = runtime.getPerformanceReport();
    std.debug.print("    🔧 编译时优化: {any}\n", .{perf_report.compile_time_optimizations});

    std.debug.print("  ✅ 所有API测试通过\n", .{});
}
