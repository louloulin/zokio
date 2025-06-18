//! Zokio 简化版增强 async/await 演示
//!
//! 展示核心功能，避免复杂的组合子

const std = @import("std");
const zokio = @import("zokio");

// 导入增强的async API
const simple_runtime = zokio.simple_runtime;

/// 简单的异步任务
const SimpleTask = struct {
    value: u32,
    delay_ms: u64,
    start_time: ?i64 = null,

    pub const Output = u32;

    pub fn init(val: u32, delay: u64) @This() {
        return @This(){
            .value = val,
            .delay_ms = delay,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;

        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            std.debug.print("任务开始: 值={}, 延迟={}ms\n", .{ self.value, self.delay_ms });
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.delay_ms) {
            std.debug.print("任务完成: 值={}, 实际耗时={}ms\n", .{ self.value, elapsed });
            return .{ .ready = self.value };
        }

        return .pending;
    }

    pub fn reset(self: *@This()) void {
        self.start_time = null;
    }
};

/// 计算任务
const ComputeTask = struct {
    input: u32,
    computed: bool = false,

    pub const Output = u32;

    pub fn init(val: u32) @This() {
        return @This(){ .input = val };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;

        if (!self.computed) {
            std.debug.print("计算任务: 输入={}\n", .{self.input});

            // 模拟计算
            var result: u32 = self.input;
            for (0..1000) |i| {
                result = result +% @as(u32, @intCast(i % 100));
            }

            self.computed = true;
            std.debug.print("计算完成: 结果={}\n", .{result});
            return .{ .ready = result };
        }

        return .{ .ready = self.input * 2 }; // 简化结果
    }
};

/// 异步函数示例
fn asyncComputation() u64 {
    std.debug.print("执行异步计算...\n", .{});
    var sum: u64 = 0;
    for (0..10000) |i| {
        sum += i;
    }
    std.debug.print("异步计算完成: {}\n", .{sum});
    return sum;
}

fn asyncStringProcess() []const u8 {
    std.debug.print("执行字符串处理...\n", .{});
    return "处理后的字符串";
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 简化版增强 async/await 演示 ===\n", .{});

    // 创建简化运行时
    var runtime = simple_runtime.builder()
        .threads(2)
        .workStealing(true)
        .queueSize(1024)
        .metrics(true)
        .build(allocator);
    defer runtime.deinit();

    try runtime.start();

    std.debug.print("\n=== 演示1: 基础Future操作 ===\n", .{});

    // 测试ready Future
    const ready_future = zokio.ready(u32, 42);
    const ready_result = try runtime.blockOn(ready_future);
    std.debug.print("Ready Future结果: {}\n", .{ready_result});

    // 测试delay Future
    std.debug.print("开始延迟测试...\n", .{});
    const delay_start = std.time.milliTimestamp();
    const delay_future = zokio.delay(100); // 100ms延迟
    try runtime.blockOn(delay_future);
    const delay_duration = std.time.milliTimestamp() - delay_start;
    std.debug.print("延迟完成，实际耗时: {}ms\n", .{delay_duration});

    std.debug.print("\n=== 演示2: 简单异步任务 ===\n", .{});

    const simple_task = SimpleTask.init(123, 50);
    const task_start = std.time.milliTimestamp();
    const task_result = try runtime.blockOn(simple_task);
    const task_duration = std.time.milliTimestamp() - task_start;
    std.debug.print("简单任务结果: {}, 总耗时: {}ms\n", .{ task_result, task_duration });

    std.debug.print("\n=== 演示3: 计算任务 ===\n", .{});

    const compute_task = ComputeTask.init(10);
    const compute_result = try runtime.blockOn(compute_task);
    std.debug.print("计算任务结果: {}\n", .{compute_result});

    std.debug.print("\n=== 演示4: async_fn使用 ===\n", .{});

    // 使用async_fn包装函数
    const AsyncCompute = zokio.async_fn(asyncComputation);
    const async_compute_task = AsyncCompute.init(asyncComputation);
    const async_result = try runtime.blockOn(async_compute_task);
    std.debug.print("async_fn计算结果: {}\n", .{async_result});

    const AsyncString = zokio.async_fn(asyncStringProcess);
    const async_string_task = AsyncString.init(asyncStringProcess);
    const string_result = try runtime.blockOn(async_string_task);
    std.debug.print("async_fn字符串结果: {s}\n", .{string_result});

    std.debug.print("\n=== 演示5: 顺序执行多个任务 ===\n", .{});

    const task1 = SimpleTask.init(1, 30);
    const task2 = SimpleTask.init(2, 40);
    const task3 = SimpleTask.init(3, 20);

    const sequential_start = std.time.milliTimestamp();

    const result1 = try runtime.blockOn(task1);
    const result2 = try runtime.blockOn(task2);
    const result3 = try runtime.blockOn(task3);

    const sequential_duration = std.time.milliTimestamp() - sequential_start;

    std.debug.print("顺序执行结果: {}, {}, {}\n", .{ result1, result2, result3 });
    std.debug.print("顺序执行总耗时: {}ms\n", .{sequential_duration});

    std.debug.print("\n=== 演示6: 超时控制（简化版） ===\n", .{});

    // 创建一个快速任务，不会超时
    const fast_task = SimpleTask.init(99, 50); // 50ms任务
    const timeout_future = zokio.timeout(fast_task, 100); // 100ms超时

    const timeout_start = std.time.milliTimestamp();
    const timeout_result = try runtime.blockOn(timeout_future);
    const timeout_duration = std.time.milliTimestamp() - timeout_start;

    std.debug.print("超时任务结果: {}\n", .{timeout_result});
    std.debug.print("超时执行耗时: {}ms\n", .{timeout_duration});

    std.debug.print("\n=== 演示7: 运行时统计信息 ===\n", .{});

    const stats = runtime.getStats();
    std.debug.print("运行时统计:\n", .{});
    std.debug.print("  总任务数: {}\n", .{stats.total_tasks});
    std.debug.print("  运行状态: {}\n", .{stats.running});
    std.debug.print("  线程数量: {}\n", .{stats.thread_count});

    std.debug.print("\n=== 演示8: 链式Future（简化版） ===\n", .{});

    // 使用ChainFuture进行简单的链式操作
    const first_task = zokio.ready(u32, 10);
    const second_task = zokio.ready(u32, 20);

    const chain = zokio.future.ChainFuture(@TypeOf(first_task), @TypeOf(second_task))
        .init(first_task, second_task);

    const chain_result = try runtime.blockOn(chain);
    std.debug.print("链式Future结果: {}\n", .{chain_result});

    std.debug.print("\n=== 演示完成 ===\n", .{});
    std.debug.print("所有演示成功完成！\n", .{});
}
