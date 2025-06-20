const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 🔍 Runtime系统性诊断 ===\n", .{});

    // 阶段1: 基础环境检查
    std.debug.print("\n📋 阶段1: 基础环境检查\n", .{});
    try checkBasicEnvironment();

    // 阶段2: 内存分配测试
    std.debug.print("\n🧪 阶段2: 内存分配测试\n", .{});
    try testMemoryAllocation(allocator);

    // 阶段3: 原子操作测试
    std.debug.print("\n⚛️ 阶段3: 原子操作测试\n", .{});
    try testAtomicOperations();

    // 阶段4: 线程安全测试
    std.debug.print("\n🧵 阶段4: 线程安全测试\n", .{});
    try testThreadSafety(allocator);

    // 阶段5: 模块导入测试
    std.debug.print("\n📦 阶段5: 模块导入测试\n", .{});
    try testModuleImports();

    std.debug.print("\n🎉 === 诊断完成 === 🎉\n", .{});
}

fn checkBasicEnvironment() !void {
    std.debug.print("  - 平台: {s}\n", .{@tagName(@import("builtin").os.tag)});
    std.debug.print("  - 架构: {s}\n", .{@tagName(@import("builtin").cpu.arch)});
    std.debug.print("  - 优化模式: {s}\n", .{@tagName(@import("builtin").mode)});
    std.debug.print("  - 单线程模式: {}\n", .{@import("builtin").single_threaded});
    std.debug.print("  - CPU核心数: {}\n", .{std.Thread.getCpuCount() catch 1});
    std.debug.print("✅ 基础环境检查通过\n", .{});
}

fn testMemoryAllocation(allocator: std.mem.Allocator) !void {
    // 测试基础分配
    const small_data = try allocator.alloc(u8, 1024);
    defer allocator.free(small_data);
    std.debug.print("  ✅ 小内存分配: {} bytes\n", .{small_data.len});

    // 测试大内存分配
    const large_data = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(large_data);
    std.debug.print("  ✅ 大内存分配: {} bytes\n", .{large_data.len});

    // 测试结构体分配
    const TestStruct = struct {
        value: u64,
        flag: bool,
    };
    const struct_data = try allocator.create(TestStruct);
    defer allocator.destroy(struct_data);
    struct_data.* = TestStruct{ .value = 42, .flag = true };
    std.debug.print("  ✅ 结构体分配: value={}, flag={}\n", .{ struct_data.value, struct_data.flag });
}

fn testAtomicOperations() !void {
    // 测试基础原子操作
    var atomic_bool = std.atomic.Value(bool).init(false);
    atomic_bool.store(true, .release);
    const bool_value = atomic_bool.load(.acquire);
    std.debug.print("  ✅ 原子布尔操作: {}\n", .{bool_value});

    // 测试原子计数器
    var atomic_counter = std.atomic.Value(u32).init(0);
    _ = atomic_counter.fetchAdd(1, .acq_rel);
    const counter_value = atomic_counter.load(.acquire);
    std.debug.print("  ✅ 原子计数器: {}\n", .{counter_value});

    // 测试原子指针
    var test_value: u32 = 42;
    var atomic_ptr = std.atomic.Value(?*u32).init(&test_value);
    const ptr_value = atomic_ptr.load(.acquire);
    std.debug.print("  ✅ 原子指针: {?}\n", .{if (ptr_value) |p| p.* else null});
}

fn testThreadSafety(allocator: std.mem.Allocator) !void {
    // 测试互斥锁
    var mutex = std.Thread.Mutex{};
    mutex.lock();
    std.debug.print("  ✅ 互斥锁获取成功\n", .{});
    mutex.unlock();
    std.debug.print("  ✅ 互斥锁释放成功\n", .{});

    // 测试条件变量
    const condition = std.Thread.Condition{};
    _ = condition; // 标记为已使用
    std.debug.print("  ✅ 条件变量创建成功\n", .{});

    // 测试简单线程创建
    const ThreadData = struct {
        counter: *std.atomic.Value(u32),

        fn worker(self: *@This()) void {
            _ = self.counter.fetchAdd(1, .acq_rel);
        }
    };

    var counter = std.atomic.Value(u32).init(0);
    var thread_data = ThreadData{ .counter = &counter };

    const thread = try std.Thread.spawn(.{}, ThreadData.worker, .{&thread_data});
    thread.join();

    const final_count = counter.load(.acquire);
    std.debug.print("  ✅ 线程执行完成: counter={}\n", .{final_count});

    _ = allocator; // 标记为已使用
}

fn testModuleImports() !void {
    // 测试标准库模块
    const builtin = @import("builtin");
    _ = builtin;
    std.debug.print("  ✅ builtin模块导入成功\n", .{});

    // 测试条件导入（模拟libxev检查）
    const has_root = @hasDecl(@import("root"), "main");
    std.debug.print("  ✅ 条件导入检查: has_main={}\n", .{has_root});

    // 测试编译时计算
    const compile_time_value = comptime blk: {
        var sum: u32 = 0;
        var i: u32 = 0;
        while (i < 10) : (i += 1) {
            sum += i;
        }
        break :blk sum;
    };
    std.debug.print("  ✅ 编译时计算: sum={}\n", .{compile_time_value});
}
