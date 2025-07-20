//! 🚀 Zokio 高级定时器优化
//!
//! 充分利用libxev的定时器特性，实现高性能定时器管理：
//! 1. 分层时间轮算法
//! 2. libxev原生定时器集成
//! 3. 批量定时器处理
//! 4. 高精度定时器支持

const std = @import("std");
const libxev = @import("libxev");
const utils = @import("../utils/utils.zig");
const Waker = @import("../core/future.zig").Waker;

/// 🔧 高级定时器配置
pub const AdvancedTimerConfig = struct {
    /// 启用libxev原生定时器
    enable_libxev_timers: bool = true,

    /// 时间轮层数
    wheel_levels: u8 = 4,

    /// 每层槽数量
    slots_per_level: u16 = 256,

    /// 基础时间精度（微秒）
    base_precision_us: u32 = 1000, // 1ms

    /// 批量处理大小
    batch_size: u32 = 64,

    /// 高精度定时器阈值（微秒）
    high_precision_threshold_us: u32 = 10000, // 10ms
};

/// 🚀 高级定时器管理器
pub const AdvancedTimerManager = struct {
    const Self = @This();

    /// 配置
    config: AdvancedTimerConfig,

    /// 内存分配器
    allocator: std.mem.Allocator,

    /// 分层时间轮
    time_wheels: []TimeWheel,

    /// libxev定时器池
    libxev_timers: std.ArrayList(LibxevTimer),

    /// 批量处理队列
    batch_queue: std.ArrayList(TimerEntry),

    /// 统计信息
    stats: TimerStats,

    /// 下一个定时器ID
    next_timer_id: utils.Atomic.Value(u64),

    /// 初始化高级定时器管理器
    pub fn init(allocator: std.mem.Allocator, config: AdvancedTimerConfig) !Self {
        const time_wheels = try allocator.alloc(TimeWheel, config.wheel_levels);

        // 初始化分层时间轮
        for (time_wheels, 0..) |*wheel, level| {
            const precision_us = config.base_precision_us * std.math.pow(u32, config.slots_per_level, @intCast(level));
            wheel.* = try TimeWheel.init(allocator, config.slots_per_level, precision_us);
        }

        return Self{
            .config = config,
            .allocator = allocator,
            .time_wheels = time_wheels,
            .libxev_timers = std.ArrayList(LibxevTimer).init(allocator),
            .batch_queue = std.ArrayList(TimerEntry).init(allocator),
            .stats = TimerStats{},
            .next_timer_id = utils.Atomic.Value(u64).init(1),
        };
    }

    /// 清理资源
    pub fn deinit(self: *Self) void {
        for (self.time_wheels) |*wheel| {
            wheel.deinit();
        }
        self.allocator.free(self.time_wheels);

        for (self.libxev_timers.items) |*timer| {
            timer.deinit();
        }
        self.libxev_timers.deinit();

        self.batch_queue.deinit();
    }

    /// 🚀 注册定时器
    pub fn registerTimer(
        self: *Self,
        duration_us: u64,
        waker: Waker,
        loop: ?*libxev.Loop,
    ) !TimerHandle {
        const timer_id = self.next_timer_id.fetchAdd(1, .monotonic);
        const expire_time = std.time.microTimestamp() + @as(i64, @intCast(duration_us));

        // 根据精度要求选择定时器类型
        if (self.config.enable_libxev_timers and
            loop != null and
            duration_us <= self.config.high_precision_threshold_us)
        {
            // 使用libxev高精度定时器
            return try self.registerLibxevTimer(timer_id, duration_us, waker, loop.?);
        } else {
            // 使用分层时间轮
            return try self.registerWheelTimer(timer_id, expire_time, waker);
        }
    }

    /// 注册libxev定时器
    fn registerLibxevTimer(
        self: *Self,
        timer_id: u64,
        duration_us: u64,
        waker: Waker,
        loop: *libxev.Loop,
    ) !TimerHandle {
        var libxev_timer = try LibxevTimer.init(timer_id, waker);

        // 配置libxev定时器
        const duration_ms = (duration_us + 999) / 1000; // 向上取整到毫秒
        libxev_timer.timer.run(
            loop,
            &libxev_timer.completion,
            duration_ms,
            LibxevTimer,
            &libxev_timer,
            LibxevTimer.callback,
        );

        try self.libxev_timers.append(libxev_timer);
        self.stats.libxev_timers_active += 1;

        return TimerHandle{ .id = timer_id, .timer_type = .libxev };
    }

    /// 注册时间轮定时器
    fn registerWheelTimer(
        self: *Self,
        timer_id: u64,
        expire_time: i64,
        waker: Waker,
    ) !TimerHandle {
        const entry = TimerEntry{
            .id = timer_id,
            .expire_time = @intCast(expire_time),
            .waker = waker,
        };

        // 选择合适的时间轮层级
        const current_time = std.time.microTimestamp();
        const delay_us = @as(u64, @intCast(expire_time - current_time));

        for (self.time_wheels) |*wheel| {
            if (delay_us <= wheel.max_delay_us) {
                try wheel.addTimer(entry);
                self.stats.wheel_timers_active += 1;
                return TimerHandle{ .id = timer_id, .timer_type = .wheel };
            }
        }

        // 如果延迟太长，使用最高层级
        const top_wheel = &self.time_wheels[self.time_wheels.len - 1];
        try top_wheel.addTimer(entry);
        self.stats.wheel_timers_active += 1;

        return TimerHandle{ .id = timer_id, .timer_type = .wheel };
    }

    /// 🚀 批量处理到期定时器
    pub fn processBatch(self: *Self) !u32 {
        self.batch_queue.clearRetainingCapacity();

        const current_time = std.time.microTimestamp();
        var processed_count: u32 = 0;

        // 处理时间轮定时器
        for (self.time_wheels) |*wheel| {
            const expired = try wheel.getExpiredTimers(current_time, &self.batch_queue);
            processed_count += expired;

            if (self.batch_queue.items.len >= self.config.batch_size) {
                break;
            }
        }

        // 批量唤醒
        for (self.batch_queue.items) |entry| {
            entry.waker.wake();
            self.stats.timers_fired += 1;
        }

        self.stats.batch_operations += 1;
        return processed_count;
    }

    /// 获取统计信息
    pub fn getStats(self: *const Self) TimerStats {
        return self.stats;
    }
};

/// 🕰️ 时间轮
const TimeWheel = struct {
    slots: []std.ArrayList(TimerEntry),
    slot_count: u16,
    precision_us: u32,
    max_delay_us: u64,
    current_slot: u16,
    last_tick_time: i64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, slot_count: u16, precision_us: u32) !TimeWheel {
        const slots = try allocator.alloc(std.ArrayList(TimerEntry), slot_count);
        for (slots) |*slot| {
            slot.* = std.ArrayList(TimerEntry).init(allocator);
        }

        return TimeWheel{
            .slots = slots,
            .slot_count = slot_count,
            .precision_us = precision_us,
            .max_delay_us = @as(u64, precision_us) * slot_count,
            .current_slot = 0,
            .last_tick_time = std.time.microTimestamp(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TimeWheel) void {
        for (self.slots) |*slot| {
            slot.deinit();
        }
        self.allocator.free(self.slots);
    }

    pub fn addTimer(self: *TimeWheel, entry: TimerEntry) !void {
        const current_time = std.time.microTimestamp();
        const delay_us = entry.expire_time - @as(u64, @intCast(current_time));
        const slot_index = (self.current_slot + @as(u16, @intCast(delay_us / self.precision_us))) % self.slot_count;

        try self.slots[slot_index].append(entry);
    }

    pub fn getExpiredTimers(
        self: *TimeWheel,
        current_time: i64,
        batch_queue: *std.ArrayList(TimerEntry),
    ) !u32 {
        var count: u32 = 0;

        // 检查当前槽的定时器
        var slot = &self.slots[self.current_slot];
        var i: usize = 0;
        while (i < slot.items.len) {
            const entry = slot.items[i];
            if (entry.expire_time <= @as(u64, @intCast(current_time))) {
                try batch_queue.append(entry);
                _ = slot.swapRemove(i);
                count += 1;
            } else {
                i += 1;
            }
        }

        // 推进时间轮
        const elapsed_us = current_time - self.last_tick_time;
        if (elapsed_us >= self.precision_us) {
            const ticks = @as(u16, @intCast(@divTrunc(elapsed_us, self.precision_us)));
            self.current_slot = (self.current_slot + ticks) % self.slot_count;
            self.last_tick_time = current_time;
        }

        return count;
    }
};

/// 🔧 libxev定时器包装
const LibxevTimer = struct {
    timer: libxev.Timer,
    completion: libxev.Completion,
    timer_id: u64,
    waker: Waker,

    pub fn init(timer_id: u64, waker: Waker) !LibxevTimer {
        return LibxevTimer{
            .timer = try libxev.Timer.init(),
            .completion = .{},
            .timer_id = timer_id,
            .waker = waker,
        };
    }

    pub fn deinit(self: *LibxevTimer) void {
        self.timer.deinit();
    }

    pub fn callback(
        userdata: ?*LibxevTimer,
        loop: *libxev.Loop,
        completion: *libxev.Completion,
        result: libxev.Timer.RunError!void,
    ) libxev.CallbackAction {
        _ = loop;
        _ = completion;
        _ = result;

        if (userdata) |timer| {
            timer.waker.wake();
        }

        return .disarm;
    }
};

/// 📊 定时器统计信息
pub const TimerStats = struct {
    /// libxev定时器活跃数量
    libxev_timers_active: u32 = 0,

    /// 时间轮定时器活跃数量
    wheel_timers_active: u32 = 0,

    /// 已触发定时器总数
    timers_fired: u64 = 0,

    /// 批量操作次数
    batch_operations: u64 = 0,
};

/// 🎯 定时器句柄
pub const TimerHandle = struct {
    id: u64,
    timer_type: TimerType = .wheel,

    pub const TimerType = enum {
        wheel,
        libxev,
    };
};

/// 🕰️ 定时器条目
pub const TimerEntry = struct {
    id: u64,
    expire_time: u64,
    waker: Waker,
};
