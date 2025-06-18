//! Zokio 任务生成和管理API
//!
//! 提供与运行时分离的任务生成接口，类似于Tokio的spawn API

const std = @import("std");
const future = @import("future.zig");
const async_enhanced = @import("async_enhanced.zig");

pub const Context = future.Context;
pub const Poll = future.Poll;
pub const TaskId = future.TaskId;

/// 任务句柄 - 类似于Tokio的JoinHandle
pub fn JoinHandle(comptime T: type) type {
    return struct {
        const Self = @This();

        /// 任务ID
        task_id: TaskId,

        /// 任务状态
        state: State = .running,

        /// 任务结果
        result: ?T = null,

        /// 错误信息
        error_info: ?anyerror = null,

        /// 取消标志
        cancelled: bool = false,

        const State = enum {
            running,
            completed,
            failed,
            cancelled,
        };

        pub fn init(id: TaskId) Self {
            return Self{ .task_id = id };
        }

        /// 等待任务完成
        pub fn join(self: *Self) !T {
            // 在实际实现中，这里会与运行时交互
            // 现在返回模拟结果
            switch (self.state) {
                .completed => return self.result.?,
                .failed => return self.error_info.?,
                .cancelled => return error.TaskCancelled,
                .running => return error.TaskNotReady,
            }
        }

        /// 尝试获取结果（非阻塞）
        pub fn tryJoin(self: *Self) ?T {
            return switch (self.state) {
                .completed => self.result,
                else => null,
            };
        }

        /// 取消任务
        pub fn abort(self: *Self) void {
            self.cancelled = true;
            self.state = .cancelled;
        }

        /// 检查任务是否完成
        pub fn isFinished(self: *const Self) bool {
            return self.state != .running;
        }

        /// 获取任务ID
        pub fn getId(self: *const Self) TaskId {
            return self.task_id;
        }
    };
}

/// 任务生成器 - 与运行时分离的接口
pub const Spawner = struct {
    const Self = @This();

    /// 生成异步任务
    pub fn spawn(comptime T: type, future_arg: anytype) JoinHandle(T) {
        const task_id = TaskId.generate();

        // 在实际实现中，这里会将任务提交给运行时
        // 现在返回模拟的句柄
        const handle = JoinHandle(T).init(task_id);

        // 模拟任务执行
        _ = future_arg; // 忽略future参数

        return handle;
    }

    /// 生成阻塞任务（在线程池中执行）
    pub fn spawnBlocking(comptime T: type, func: anytype) JoinHandle(T) {
        const task_id = TaskId.generate();

        // 在实际实现中，这里会在线程池中执行阻塞任务
        const handle = JoinHandle(T).init(task_id);

        // 模拟阻塞任务执行
        _ = func; // 忽略func参数

        return handle;
    }

    /// 生成本地任务（在当前线程执行）
    pub fn spawnLocal(comptime T: type, future_arg: anytype) JoinHandle(T) {
        const task_id = TaskId.generate();

        // 在实际实现中，这里会在当前线程的本地队列中执行
        const handle = JoinHandle(T).init(task_id);

        // 模拟本地任务执行
        _ = future_arg; // 忽略future参数

        return handle;
    }
};

/// 全局任务生成器实例
pub var spawner = Spawner{};

/// 便捷的spawn函数
pub fn spawn(future_arg: anytype) JoinHandle(@TypeOf(future_arg).Output) {
    return spawner.spawn(@TypeOf(future_arg).Output, future_arg);
}

/// 便捷的spawnBlocking函数
pub fn spawnBlocking(func: anytype) JoinHandle(@TypeOf(@call(.auto, func, .{}))) {
    return spawner.spawnBlocking(@TypeOf(@call(.auto, func, .{})), func);
}

/// 便捷的spawnLocal函数
pub fn spawnLocal(future_arg: anytype) JoinHandle(@TypeOf(future_arg).Output) {
    return spawner.spawnLocal(@TypeOf(future_arg).Output, future_arg);
}

/// 任务集合 - 管理多个任务
pub fn TaskSet(comptime T: type) type {
    return struct {
        const Self = @This();

        handles: std.ArrayList(JoinHandle(T)),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .handles = std.ArrayList(JoinHandle(T)).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.handles.deinit();
        }

        /// 添加任务
        pub fn add(self: *Self, handle: JoinHandle(T)) !void {
            try self.handles.append(handle);
        }

        /// 等待所有任务完成
        pub fn joinAll(self: *Self) ![]T {
            var results = try self.allocator.alloc(T, self.handles.items.len);

            for (self.handles.items, 0..) |*handle, i| {
                results[i] = try handle.join();
            }

            return results;
        }

        /// 等待任意一个任务完成
        pub fn joinAny(self: *Self) !T {
            // 在实际实现中，这里会使用select机制
            for (self.handles.items) |*handle| {
                if (handle.tryJoin()) |result| {
                    return result;
                }
            }
            return error.NoTaskReady;
        }

        /// 取消所有任务
        pub fn abortAll(self: *Self) void {
            for (self.handles.items) |*handle| {
                handle.abort();
            }
        }

        /// 获取已完成的任务数量
        pub fn completedCount(self: *const Self) usize {
            var count: usize = 0;
            for (self.handles.items) |*handle| {
                if (handle.isFinished()) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

/// 异步作用域 - 确保所有生成的任务在作用域结束前完成
pub fn AsyncScope(comptime T: type) type {
    return struct {
        const Self = @This();

        task_set: TaskSet(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .task_set = TaskSet(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // 确保所有任务完成或被取消
            self.task_set.abortAll();
            self.task_set.deinit();
        }

        /// 在作用域内生成任务
        pub fn spawn(self: *Self, future_arg: anytype) !void {
            const handle = spawner.spawn(T, future_arg);
            try self.task_set.add(handle);
        }

        /// 等待所有任务完成
        pub fn join(self: *Self) ![]T {
            return self.task_set.joinAll();
        }
    };
}

/// 任务本地存储
pub fn TaskLocal(comptime T: type) type {
    return struct {
        const Self = @This();

        /// 存储映射：TaskId -> T
        storage: std.HashMap(TaskId, T, TaskIdContext, std.hash_map.default_max_load_percentage),
        mutex: std.Thread.Mutex = .{},

        const TaskIdContext = struct {
            pub fn hash(self: @This(), key: TaskId) u64 {
                _ = self;
                return key.id;
            }

            pub fn eql(self: @This(), a: TaskId, b: TaskId) bool {
                _ = self;
                return a.id == b.id;
            }
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .storage = std.HashMap(TaskId, T, TaskIdContext, std.hash_map.default_max_load_percentage).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.storage.deinit();
        }

        /// 设置当前任务的值
        pub fn set(self: *Self, value: T) !void {
            const task_id = getCurrentTaskId();

            self.mutex.lock();
            defer self.mutex.unlock();

            try self.storage.put(task_id, value);
        }

        /// 获取当前任务的值
        pub fn get(self: *Self) ?T {
            const task_id = getCurrentTaskId();

            self.mutex.lock();
            defer self.mutex.unlock();

            return self.storage.get(task_id);
        }

        /// 移除当前任务的值
        pub fn remove(self: *Self) void {
            const task_id = getCurrentTaskId();

            self.mutex.lock();
            defer self.mutex.unlock();

            _ = self.storage.remove(task_id);
        }

        /// 获取当前任务ID（模拟实现）
        fn getCurrentTaskId() TaskId {
            // 在实际实现中，这里会从运行时获取当前任务ID
            return TaskId.generate();
        }
    };
}

/// 任务优先级
pub const Priority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,

    pub fn toU8(self: Priority) u8 {
        return @intFromEnum(self);
    }
};

/// 任务配置
pub const TaskConfig = struct {
    priority: Priority = .normal,
    stack_size: ?usize = null,
    name: ?[]const u8 = null,
    timeout: ?u64 = null, // 毫秒
};

/// 带配置的任务生成
pub fn spawnWithConfig(future_arg: anytype, config: TaskConfig) JoinHandle(@TypeOf(future_arg).Output) {
    _ = config; // 在实际实现中会使用配置
    return spawn(future_arg);
}
