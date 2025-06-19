//! Zokio 高性能智能分配器
//!
//! 优化版本：减少监控开销，提升分配性能

const std = @import("std");
const utils = @import("../utils/utils.zig");

// 导入分配器实现
const OptimizedAllocator = @import("optimized_allocator.zig").OptimizedAllocator;
const ExtendedAllocator = @import("extended_allocator.zig").ExtendedAllocator;

/// 快速分配策略
pub const FastAllocationStrategy = enum {
    /// 自动选择（编译时优化）
    auto,
    /// 高性能对象池（默认策略）
    object_pool,
    /// 扩展对象池
    extended_pool,
    /// 标准分配器
    standard,
};

/// 高性能智能分配器配置
pub const FastSmartAllocatorConfig = struct {
    /// 默认分配策略
    default_strategy: FastAllocationStrategy = .extended_pool,

    /// 是否启用快速路径优化
    enable_fast_path: bool = true,

    /// 是否启用轻量级监控
    enable_lightweight_monitoring: bool = true,

    /// 小对象阈值
    small_object_threshold: usize = 256,

    /// 大对象阈值
    large_object_threshold: usize = 8192,
};

/// 轻量级统计
const LightweightStats = struct {
    total_allocations: utils.Atomic.Value(u64),
    fast_path_hits: utils.Atomic.Value(u64),

    fn init() @This() {
        return @This(){
            .total_allocations = utils.Atomic.Value(u64).init(0),
            .fast_path_hits = utils.Atomic.Value(u64).init(0),
        };
    }

    fn recordAllocation(self: *@This(), fast_path: bool) void {
        _ = self.total_allocations.fetchAdd(1, .monotonic);
        if (fast_path) {
            _ = self.fast_path_hits.fetchAdd(1, .monotonic);
        }
    }

    fn getFastPathRate(self: *const @This()) f64 {
        const total = self.total_allocations.load(.monotonic);
        const hits = self.fast_path_hits.load(.monotonic);
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(total));
    }
};

/// 高性能智能分配器
pub const FastSmartAllocator = struct {
    const Self = @This();

    /// 配置
    config: FastSmartAllocatorConfig,

    /// 基础分配器
    base_allocator: std.mem.Allocator,

    /// 高性能分配器实例（预初始化）
    optimized_allocator: OptimizedAllocator,
    extended_allocator: ExtendedAllocator,

    /// 当前策略（编译时优化）
    current_strategy: FastAllocationStrategy,

    /// 轻量级统计
    stats: LightweightStats,

    pub fn init(base_allocator: std.mem.Allocator, config: FastSmartAllocatorConfig) !Self {
        // 预初始化所有分配器以避免运行时开销
        const optimized_allocator = try OptimizedAllocator.init(base_allocator);
        const extended_allocator = try ExtendedAllocator.init(base_allocator);

        return Self{
            .config = config,
            .base_allocator = base_allocator,
            .optimized_allocator = optimized_allocator,
            .extended_allocator = extended_allocator,
            .current_strategy = config.default_strategy,
            .stats = LightweightStats.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.optimized_allocator.deinit();
        self.extended_allocator.deinit();
    }

    /// 🚀 高性能智能分配 - 快速路径优化
    pub fn alloc(self: *Self, comptime T: type, count: usize) ![]T {
        const size = @sizeOf(T) * count;

        // 🔥 快速路径：运行时策略选择，但优化路径
        if (self.config.enable_fast_path) {
            const memory = try self.allocFastPath(size);

            // 轻量级统计（可选）
            if (self.config.enable_lightweight_monitoring) {
                self.stats.recordAllocation(true);
            }

            return @as([*]T, @ptrCast(@alignCast(memory.ptr)))[0..count];
        }

        // 慢速路径：运行时策略选择
        const strategy = self.selectFastStrategy(size);
        const memory = try self.allocWithFastStrategy(size, strategy);

        if (self.config.enable_lightweight_monitoring) {
            self.stats.recordAllocation(false);
        }

        return @as([*]T, @ptrCast(@alignCast(memory.ptr)))[0..count];
    }

    /// 🚀 高性能智能释放
    pub fn free(self: *Self, memory: anytype) void {
        const slice = switch (@TypeOf(memory)) {
            []u8 => memory,
            else => std.mem.sliceAsBytes(memory),
        };

        // 🔥 快速路径：直接使用当前策略
        if (self.config.enable_fast_path) {
            self.freeFastPath(slice);
            return;
        }

        // 慢速路径：策略判断
        const size = slice.len;
        const strategy = self.selectFastStrategy(size);
        self.freeWithFastStrategy(slice, strategy);
    }

    /// 🔥 快速路径分配 - 运行时优化
    inline fn allocFastPath(self: *Self, size: usize) ![]u8 {
        // 运行时策略选择，但使用内联优化
        return switch (self.config.default_strategy) {
            .object_pool => self.optimized_allocator.alloc(size),
            .extended_pool => self.extended_allocator.alloc(size),
            .standard => self.base_allocator.alloc(u8, size),
            .auto => blk: {
                // 运行时自动选择最优策略
                if (self.config.large_object_threshold > self.config.small_object_threshold) {
                    break :blk self.extended_allocator.alloc(size);
                } else {
                    break :blk self.optimized_allocator.alloc(size);
                }
            },
        };
    }

    /// 🔥 快速路径释放 - 运行时优化
    inline fn freeFastPath(self: *Self, memory: []u8) void {
        // 运行时策略选择，但使用内联优化
        switch (self.config.default_strategy) {
            .object_pool => self.optimized_allocator.free(memory),
            .extended_pool => self.extended_allocator.free(memory),
            .standard => self.base_allocator.free(memory),
            .auto => {
                // 运行时自动选择
                if (self.config.large_object_threshold > self.config.small_object_threshold) {
                    self.extended_allocator.free(memory);
                } else {
                    self.optimized_allocator.free(memory);
                }
            },
        }
    }

    /// 快速策略选择 - 简化版本
    fn selectFastStrategy(self: *Self, size: usize) FastAllocationStrategy {
        if (size <= self.config.small_object_threshold) {
            return .object_pool;
        } else if (size <= self.config.large_object_threshold) {
            return .extended_pool;
        } else {
            return .standard;
        }
    }

    /// 使用快速策略分配
    fn allocWithFastStrategy(self: *Self, size: usize, strategy: FastAllocationStrategy) ![]u8 {
        return switch (strategy) {
            .auto => unreachable,
            .object_pool => self.optimized_allocator.alloc(size),
            .extended_pool => self.extended_allocator.alloc(size),
            .standard => self.base_allocator.alloc(u8, size),
        };
    }

    /// 使用快速策略释放
    fn freeWithFastStrategy(self: *Self, memory: []u8, strategy: FastAllocationStrategy) void {
        switch (strategy) {
            .auto => unreachable,
            .object_pool => self.optimized_allocator.free(memory),
            .extended_pool => self.extended_allocator.free(memory),
            .standard => self.base_allocator.free(memory),
        }
    }

    /// 获取标准分配器接口
    pub fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = allocFn,
                .resize = resizeFn,
                .free = freeFn,
                .remap = remapFn,
            },
        };
    }

    /// 获取轻量级统计
    pub fn getStats(self: *const Self) FastAllocatorStats {
        return FastAllocatorStats{
            .total_allocations = self.stats.total_allocations.load(.monotonic),
            .fast_path_hits = self.stats.fast_path_hits.load(.monotonic),
            .fast_path_rate = self.stats.getFastPathRate(),
            .current_strategy = self.current_strategy,
        };
    }

    // 标准分配器接口实现
    fn allocFn(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ptr_align;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        const memory = self.alloc(u8, len) catch return null;
        return memory.ptr;
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.free(buf);
    }

    fn remapFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null;
    }
};

/// 快速分配器统计
pub const FastAllocatorStats = struct {
    total_allocations: u64,
    fast_path_hits: u64,
    fast_path_rate: f64,
    current_strategy: FastAllocationStrategy,
};
