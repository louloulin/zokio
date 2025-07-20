//! 🔧 Zokio 运行时接口抽象
//!
//! 定义运行时的核心接口，降低模块间耦合

const std = @import("std");

/// 运行时接口
pub const RuntimeInterface = struct {
    const Self = @This();

    /// 运行时实现的虚函数表
    vtable: *const VTable,

    /// 运行时实例指针
    ptr: *anyopaque,

    const VTable = struct {
        /// 启动运行时
        start: *const fn (ptr: *anyopaque) anyerror!void,

        /// 停止运行时
        stop: *const fn (ptr: *anyopaque) void,

        /// 检查运行时是否正在运行
        isRunning: *const fn (ptr: *anyopaque) bool,

        /// 生成任务
        spawn: *const fn (ptr: *anyopaque, task_ptr: *anyopaque) anyerror!void,

        /// 阻塞等待Future完成
        blockOn: *const fn (ptr: *anyopaque, future_ptr: *anyopaque) anyerror!void,

        /// 获取运行时统计信息
        getStats: *const fn (ptr: *anyopaque) RuntimeStats,

        /// 清理资源
        deinit: *const fn (ptr: *anyopaque) void,
    };

    /// 启动运行时
    pub fn start(self: Self) !void {
        return self.vtable.start(self.ptr);
    }

    /// 停止运行时
    pub fn stop(self: Self) void {
        self.vtable.stop(self.ptr);
    }

    /// 检查运行时是否正在运行
    pub fn isRunning(self: Self) bool {
        return self.vtable.isRunning(self.ptr);
    }

    /// 生成任务
    pub fn spawn(self: Self, task: anytype) !void {
        var task_copy = task;
        return self.vtable.spawn(self.ptr, &task_copy);
    }

    /// 阻塞等待Future完成
    pub fn blockOn(self: Self, future: anytype) !void {
        var future_copy = future;
        return self.vtable.blockOn(self.ptr, &future_copy);
    }

    /// 获取运行时统计信息
    pub fn getStats(self: Self) RuntimeStats {
        return self.vtable.getStats(self.ptr);
    }

    /// 清理资源
    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }
};

/// 运行时统计信息
pub const RuntimeStats = struct {
    total_tasks: u64 = 0,
    running: bool = false,
    thread_count: u32 = 0,
    completed_tasks: u64 = 0,
    pending_tasks: u64 = 0,
    memory_usage: usize = 0,
};

/// I/O 驱动接口
pub const IoDriverInterface = struct {
    const Self = @This();

    vtable: *const VTable,
    ptr: *anyopaque,

    const VTable = struct {
        /// 提交读操作
        submitRead: *const fn (ptr: *anyopaque, fd: i32, buffer: []u8, offset: u64) anyerror!IoHandle,

        /// 提交写操作
        submitWrite: *const fn (ptr: *anyopaque, fd: i32, buffer: []const u8, offset: u64) anyerror!IoHandle,

        /// 轮询完成的操作
        poll: *const fn (ptr: *anyopaque, timeout_ms: u32) anyerror!u32,

        /// 获取操作结果
        getResult: *const fn (ptr: *anyopaque, handle: IoHandle) anyerror!IoResult,

        /// 获取统计信息
        getStats: *const fn (ptr: *anyopaque) IoStats,

        /// 清理资源
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn submitRead(self: Self, fd: i32, buffer: []u8, offset: u64) !IoHandle {
        return self.vtable.submitRead(self.ptr, fd, buffer, offset);
    }

    pub fn submitWrite(self: Self, fd: i32, buffer: []const u8, offset: u64) !IoHandle {
        return self.vtable.submitWrite(self.ptr, fd, buffer, offset);
    }

    pub fn poll(self: Self, timeout_ms: u32) !u32 {
        return self.vtable.poll(self.ptr, timeout_ms);
    }

    pub fn getResult(self: Self, handle: IoHandle) !IoResult {
        return self.vtable.getResult(self.ptr, handle);
    }

    pub fn getStats(self: Self) IoStats {
        return self.vtable.getStats(self.ptr);
    }

    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }
};

/// I/O 操作句柄
pub const IoHandle = struct {
    id: u64,
};

/// I/O 操作结果
pub const IoResult = union(enum) {
    success: struct {
        bytes_transferred: usize,
    },
    error_code: u32,
};

/// I/O 统计信息
pub const IoStats = struct {
    ops_submitted: u64 = 0,
    ops_completed: u64 = 0,
    ops_failed: u64 = 0,
    bytes_read: u64 = 0,
    bytes_written: u64 = 0,
    avg_latency_ns: u64 = 0,
};

/// 调度器接口
pub const SchedulerInterface = struct {
    const Self = @This();

    vtable: *const VTable,
    ptr: *anyopaque,

    const VTable = struct {
        /// 调度任务
        schedule: *const fn (ptr: *anyopaque, task: anytype) anyerror!void,

        /// 让出执行权
        yieldNow: *const fn (ptr: *anyopaque) void,

        /// 获取当前任务数量
        getTaskCount: *const fn (ptr: *anyopaque) u32,

        /// 获取调度器统计信息
        getStats: *const fn (ptr: *anyopaque) SchedulerStats,
    };

    pub fn schedule(self: Self, task: anytype) !void {
        return self.vtable.schedule(self.ptr, task);
    }

    pub fn yieldNow(self: Self) void {
        self.vtable.yieldNow(self.ptr);
    }

    pub fn getTaskCount(self: Self) u32 {
        return self.vtable.getTaskCount(self.ptr);
    }

    pub fn getStats(self: Self) SchedulerStats {
        return self.vtable.getStats(self.ptr);
    }
};

/// 调度器统计信息
pub const SchedulerStats = struct {
    total_scheduled: u64 = 0,
    currently_running: u32 = 0,
    queue_depth: u32 = 0,
    avg_schedule_time_ns: u64 = 0,
};

/// 创建运行时接口的辅助函数
pub fn createRuntimeInterface(comptime T: type, instance: *T) RuntimeInterface {
    const Impl = struct {
        fn start(ptr: *anyopaque) anyerror!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.start();
        }

        fn stop(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.stop();
        }

        fn isRunning(ptr: *anyopaque) bool {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.isRunning();
        }

        fn spawn(ptr: *anyopaque, task_ptr: *anyopaque) anyerror!void {
            _ = ptr;
            _ = task_ptr; // 简化实现
            // 实际实现中需要类型转换
            return; // 暂时返回空
        }

        fn blockOn(ptr: *anyopaque, future_ptr: *anyopaque) anyerror!void {
            _ = ptr;
            _ = future_ptr; // 简化实现
            // 实际实现中需要类型转换
            return; // 暂时返回空
        }

        fn getStats(ptr: *anyopaque) RuntimeStats {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getStats();
        }

        fn deinit(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.deinit();
        }
    };

    const vtable = RuntimeInterface.VTable{
        .start = Impl.start,
        .stop = Impl.stop,
        .isRunning = Impl.isRunning,
        .spawn = Impl.spawn,
        .blockOn = Impl.blockOn,
        .getStats = Impl.getStats,
        .deinit = Impl.deinit,
    };

    return RuntimeInterface{
        .vtable = &vtable,
        .ptr = instance,
    };
}

/// 创建I/O驱动接口的辅助函数
pub fn createIoDriverInterface(comptime T: type, instance: *T) IoDriverInterface {
    const Impl = struct {
        fn submitRead(ptr: *anyopaque, fd: i32, buffer: []u8, offset: u64) anyerror!IoHandle {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.submitRead(fd, buffer, offset);
        }

        fn submitWrite(ptr: *anyopaque, fd: i32, buffer: []const u8, offset: u64) anyerror!IoHandle {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.submitWrite(fd, buffer, offset);
        }

        fn poll(ptr: *anyopaque, timeout_ms: u32) anyerror!u32 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.poll(timeout_ms);
        }

        fn getResult(ptr: *anyopaque, handle: IoHandle) anyerror!IoResult {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getResult(handle);
        }

        fn getStats(ptr: *anyopaque) IoStats {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getStats();
        }

        fn deinit(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.deinit();
        }
    };

    const vtable = IoDriverInterface.VTable{
        .submitRead = Impl.submitRead,
        .submitWrite = Impl.submitWrite,
        .poll = Impl.poll,
        .getResult = Impl.getResult,
        .getStats = Impl.getStats,
        .deinit = Impl.deinit,
    };

    return IoDriverInterface{
        .vtable = &vtable,
        .ptr = instance,
    };
}
