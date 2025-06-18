//! Zokio 增强版 async/await 演示
//!
//! 展示新的简化API，支持嵌套调用和与运行时分离

const std = @import("std");
const zokio = @import("zokio");

// 导入增强的async API
const async_enhanced = zokio.async_enhanced;
const spawn_api = zokio.spawn_api;
const simple_runtime = zokio.simple_runtime;

/// 异步数据获取函数
fn fetchUserData(user_id: u32) ![]const u8 {
    std.debug.print("正在获取用户 {} 的数据...\n", .{user_id});

    // 模拟网络延迟
    std.time.sleep(100 * std.time.ns_per_ms);

    if (user_id == 0) {
        return error.UserNotFound;
    }

    return "用户数据";
}

/// 异步数据处理函数
fn processUserData(data: []const u8) ![]const u8 {
    std.debug.print("正在处理数据: {s}\n", .{data});

    // 模拟处理时间
    std.time.sleep(50 * std.time.ns_per_ms);

    return "处理后的数据";
}

/// 异步保存函数
fn saveProcessedData(data: []const u8) !void {
    std.debug.print("正在保存数据: {s}\n", .{data});

    // 模拟保存时间
    std.time.sleep(30 * std.time.ns_per_ms);

    std.debug.print("数据保存完成\n", .{});
}

/// 复杂的异步工作流
const AsyncWorkflow = struct {
    user_id: u32,
    step: u32 = 0,
    user_data: ?[]const u8 = null,
    processed_data: ?[]const u8 = null,

    pub const Output = void;

    pub fn init(id: u32) @This() {
        return @This(){ .user_id = id };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;

        switch (self.step) {
            0 => {
                // 步骤1: 获取用户数据
                self.user_data = fetchUserData(self.user_id) catch |err| {
                    std.debug.print("获取用户数据失败: {}\n", .{err});
                    return .{ .ready = {} };
                };
                self.step = 1;
                return .pending;
            },
            1 => {
                // 步骤2: 处理数据
                if (self.user_data) |data| {
                    self.processed_data = processUserData(data) catch |err| {
                        std.debug.print("处理数据失败: {}\n", .{err});
                        return .{ .ready = {} };
                    };
                }
                self.step = 2;
                return .pending;
            },
            2 => {
                // 步骤3: 保存数据
                if (self.processed_data) |data| {
                    saveProcessedData(data) catch |err| {
                        std.debug.print("保存数据失败: {}\n", .{err});
                        return .{ .ready = {} };
                    };
                }
                return .{ .ready = {} };
            },
            else => {
                return .{ .ready = {} };
            },
        }
    }
};

/// 并发任务示例
const ConcurrentTask = struct {
    task_id: u32,
    duration_ms: u64,
    start_time: ?i64 = null,

    pub const Output = u32;

    pub fn init(id: u32, duration: u64) @This() {
        return @This(){
            .task_id = id,
            .duration_ms = duration,
        };
    }

    pub fn poll(self: *@This(), ctx: *zokio.Context) zokio.Poll(u32) {
        _ = ctx;

        if (self.start_time == null) {
            self.start_time = std.time.milliTimestamp();
            std.debug.print("任务 {} 开始执行\n", .{self.task_id});
            return .pending;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time.?;
        if (elapsed >= self.duration_ms) {
            std.debug.print("任务 {} 执行完成\n", .{self.task_id});
            return .{ .ready = self.task_id * 10 };
        }

        return .pending;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 增强版 async/await 演示 ===\n", .{});

    // 创建简化运行时
    var runtime = simple_runtime.builder()
        .threads(2)
        .workStealing(true)
        .queueSize(1024)
        .metrics(true)
        .build(allocator);
    defer runtime.deinit();

    try runtime.start();

    std.debug.print("\n=== 演示1: 简化的Future使用 ===\n", .{});

    // 使用ready Future
    const ready_future = zokio.ready(u32, 42);
    const ready_result = try runtime.blockOn(ready_future);
    std.debug.print("Ready Future结果: {}\n", .{ready_result});

    // 使用delay Future
    std.debug.print("开始延迟测试...\n", .{});
    const delay_start = std.time.milliTimestamp();
    const delay_future = zokio.delay(100); // 100ms延迟
    try runtime.blockOn(delay_future);
    const delay_duration = std.time.milliTimestamp() - delay_start;
    std.debug.print("延迟完成，实际耗时: {}ms\n", .{delay_duration});

    std.debug.print("\n=== 演示2: 复杂异步工作流 ===\n", .{});

    const workflow = AsyncWorkflow.init(123);
    const workflow_start = std.time.milliTimestamp();
    try runtime.blockOn(workflow);
    const workflow_duration = std.time.milliTimestamp() - workflow_start;
    std.debug.print("工作流完成，总耗时: {}ms\n", .{workflow_duration});

    std.debug.print("\n=== 演示3: 并发任务执行 ===\n", .{});

    // 创建多个并发任务
    const task1 = ConcurrentTask.init(1, 80);
    const task2 = ConcurrentTask.init(2, 120);
    const task3 = ConcurrentTask.init(3, 60);

    // 使用join组合子并发执行
    const concurrent_tasks = struct {
        task1: ConcurrentTask,
        task2: ConcurrentTask,
        task3: ConcurrentTask,
    }{
        .task1 = task1,
        .task2 = task2,
        .task3 = task3,
    };

    const join_future = async_enhanced.join(concurrent_tasks);
    const concurrent_start = std.time.milliTimestamp();
    const join_results = try runtime.blockOn(join_future);
    const concurrent_duration = std.time.milliTimestamp() - concurrent_start;

    std.debug.print("并发任务结果: task1={}, task2={}, task3={}\n", .{ join_results.task1, join_results.task2, join_results.task3 });
    std.debug.print("并发执行总耗时: {}ms\n", .{concurrent_duration});

    std.debug.print("\n=== 演示4: 选择第一个完成的任务 ===\n", .{});

    // 创建不同执行时间的任务
    const fast_task = ConcurrentTask.init(10, 50);
    const slow_task = ConcurrentTask.init(20, 200);

    const select_tasks = struct {
        fast: ConcurrentTask,
        slow: ConcurrentTask,
    }{
        .fast = fast_task,
        .slow = slow_task,
    };

    const select_future = async_enhanced.select(select_tasks);
    const select_start = std.time.milliTimestamp();
    const select_result = try runtime.blockOn(select_future);
    const select_duration = std.time.milliTimestamp() - select_start;

    std.debug.print("第一个完成的任务结果: {}\n", .{select_result});
    std.debug.print("选择执行耗时: {}ms\n", .{select_duration});

    std.debug.print("\n=== 演示5: 超时控制 ===\n", .{});

    // 创建一个长时间运行的任务
    const long_task = ConcurrentTask.init(99, 300); // 300ms任务
    const timeout_future = zokio.timeout(long_task, 150); // 150ms超时

    const timeout_start = std.time.milliTimestamp();
    const timeout_result = try runtime.blockOn(timeout_future);
    const timeout_duration = std.time.milliTimestamp() - timeout_start;

    std.debug.print("超时任务结果: {}\n", .{timeout_result});
    std.debug.print("超时执行耗时: {}ms\n", .{timeout_duration});

    std.debug.print("\n=== 演示6: 运行时统计信息 ===\n", .{});

    const stats = runtime.getStats();
    std.debug.print("运行时统计:\n", .{});
    std.debug.print("  总任务数: {}\n", .{stats.total_tasks});
    std.debug.print("  运行状态: {}\n", .{stats.running});
    std.debug.print("  线程数量: {}\n", .{stats.thread_count});

    std.debug.print("\n=== 演示完成 ===\n", .{});
}
