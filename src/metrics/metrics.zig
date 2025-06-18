//! 指标模块
//!
//! 提供运行时性能指标收集和报告功能。

const std = @import("std");
const utils = @import("../utils/utils.zig");

/// 运行时指标
pub const RuntimeMetrics = struct {
    // 任务指标
    tasks_spawned: utils.Atomic.Value(u64),
    tasks_completed: utils.Atomic.Value(u64),
    tasks_cancelled: utils.Atomic.Value(u64),

    // 调度指标
    scheduler_polls: utils.Atomic.Value(u64),
    work_steals: utils.Atomic.Value(u64),

    // I/O指标
    io_operations: utils.Atomic.Value(u64),
    io_completions: utils.Atomic.Value(u64),

    pub fn init() RuntimeMetrics {
        return RuntimeMetrics{
            .tasks_spawned = utils.Atomic.Value(u64).init(0),
            .tasks_completed = utils.Atomic.Value(u64).init(0),
            .tasks_cancelled = utils.Atomic.Value(u64).init(0),
            .scheduler_polls = utils.Atomic.Value(u64).init(0),
            .work_steals = utils.Atomic.Value(u64).init(0),
            .io_operations = utils.Atomic.Value(u64).init(0),
            .io_completions = utils.Atomic.Value(u64).init(0),
        };
    }

    pub fn recordTaskSpawn(self: *RuntimeMetrics) void {
        _ = self.tasks_spawned.fetchAdd(1, .monotonic);
    }

    pub fn recordTaskCompletion(self: *RuntimeMetrics) void {
        _ = self.tasks_completed.fetchAdd(1, .monotonic);
    }

    pub fn getSnapshot(self: *const RuntimeMetrics) MetricsSnapshot {
        return MetricsSnapshot{
            .tasks_spawned = self.tasks_spawned.load(.monotonic),
            .tasks_completed = self.tasks_completed.load(.monotonic),
            .tasks_cancelled = self.tasks_cancelled.load(.monotonic),
            .scheduler_polls = self.scheduler_polls.load(.monotonic),
            .work_steals = self.work_steals.load(.monotonic),
            .io_operations = self.io_operations.load(.monotonic),
            .io_completions = self.io_completions.load(.monotonic),
        };
    }
};

/// 指标快照
pub const MetricsSnapshot = struct {
    tasks_spawned: u64,
    tasks_completed: u64,
    tasks_cancelled: u64,
    scheduler_polls: u64,
    work_steals: u64,
    io_operations: u64,
    io_completions: u64,

    pub fn format(
        self: MetricsSnapshot,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print(
            \\Runtime Metrics:
            \\  Tasks: spawned={}, completed={}, cancelled={}
            \\  Scheduler: polls={}
            \\  Work Stealing: steals={}
            \\  I/O: operations={}, completions={}
        , .{
            self.tasks_spawned,
            self.tasks_completed,
            self.tasks_cancelled,
            self.scheduler_polls,
            self.work_steals,
            self.io_operations,
            self.io_completions,
        });
    }
};

// 测试
test "运行时指标基础功能" {
    const testing = std.testing;

    var metrics = RuntimeMetrics.init();

    // 测试记录指标
    metrics.recordTaskSpawn();
    metrics.recordTaskSpawn();
    metrics.recordTaskCompletion();

    // 测试快照
    const snapshot = metrics.getSnapshot();
    try testing.expectEqual(@as(u64, 2), snapshot.tasks_spawned);
    try testing.expectEqual(@as(u64, 1), snapshot.tasks_completed);
    try testing.expectEqual(@as(u64, 0), snapshot.tasks_cancelled);
}
