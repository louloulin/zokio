//! Zokio核心层模块
//!
//! 核心层包含Zokio异步运行时的基础组件：
//! - 运行时核心 (runtime)
//! - Future抽象 (future)
//! - 任务调度器 (scheduler)
//! - 执行上下文 (context)
//! - Waker系统 (waker)
//! - 任务抽象 (task)

const std = @import("std");

// 核心模块导出
pub const runtime = @import("runtime.zig");
pub const future = @import("future.zig");
pub const scheduler = @import("scheduler.zig");
pub const waker = @import("waker.zig");

// 新增核心组件 (待实现)
// pub const context = @import("context.zig");
// pub const task = @import("task.zig");

// 便捷类型导出
pub const Runtime = runtime.Runtime;
pub const Future = future.Future;
pub const Poll = future.Poll;
pub const Context = future.Context;
pub const Scheduler = scheduler.Scheduler;
pub const Waker = waker.Waker;

// 便捷函数导出
pub const spawn = runtime.spawn;
pub const block_on = runtime.block_on;
pub const yield_now = scheduler.yield_now;

test "core module compilation" {
    // 确保所有核心模块能正常编译
    _ = runtime;
    _ = future;
    _ = scheduler;
    _ = waker;
}
