//! Zokio 智能统一内存分配器
//!
//! 提供统一的智能分配入口，自动选择最优分配策略

const std = @import("std");
const utils = @import("../utils/utils.zig");

// 导入所有分配器实现
const OptimizedAllocator = @import("optimized_allocator.zig").OptimizedAllocator;
const ExtendedAllocator = @import("extended_allocator.zig").ExtendedAllocator;

/// 分配策略类型
pub const AllocationStrategy = enum {
    /// 自动选择最优策略
    auto,
    /// 高性能对象池（适合固定大小高频分配）
    object_pool,
    /// 扩展对象池（适合大对象分配）
    extended_pool,
    /// 标准分配器（适合不规则分配）
    standard,
    /// 竞技场分配器（适合批量分配）
    arena,
};

/// 智能分配器配置
pub const SmartAllocatorConfig = struct {
    /// 默认分配策略
    default_strategy: AllocationStrategy = .auto,

    /// 是否启用自动策略切换
    enable_auto_switching: bool = true,

    /// 是否启用性能监控
    enable_monitoring: bool = true,

    /// 是否启用统计收集
    enable_statistics: bool = true,

    /// 自动切换阈值配置
    auto_switch_config: AutoSwitchConfig = .{},

    /// 内存预算限制（字节）
    memory_budget: ?usize = null,

    /// 是否启用内存压缩
    enable_compaction: bool = true,
};

/// 自动切换配置
pub const AutoSwitchConfig = struct {
    /// 小对象阈值（字节）
    small_object_threshold: usize = 256,

    /// 大对象阈值（字节）
    large_object_threshold: usize = 8192,

    /// 高频分配阈值（每秒分配次数）
    high_frequency_threshold: f64 = 1000.0,

    /// 复用率阈值
    reuse_rate_threshold: f64 = 0.7,

    /// 策略切换冷却时间（毫秒）
    switch_cooldown_ms: u64 = 1000,
};

/// 分配模式分析
const AllocationPattern = struct {
    /// 平均分配大小
    avg_size: f64,
    /// 分配频率（每秒）
    frequency: f64,
    /// 大小变化方差
    size_variance: f64,
    /// 生命周期模式
    lifetime_pattern: LifetimePattern,
};

/// 生命周期模式
const LifetimePattern = enum {
    /// 短生命周期（立即释放）
    short_lived,
    /// 中等生命周期（几秒内释放）
    medium_lived,
    /// 长生命周期（长时间持有）
    long_lived,
    /// 未知模式
    unknown,
};

/// 智能统一内存分配器
pub const SmartAllocator = struct {
    const Self = @This();

    /// 配置
    config: SmartAllocatorConfig,

    /// 基础分配器
    base_allocator: std.mem.Allocator,

    /// 各种分配器实例
    optimized_allocator: ?OptimizedAllocator,
    extended_allocator: ?ExtendedAllocator,
    arena_allocator: ?std.heap.ArenaAllocator,

    /// 当前活跃策略
    current_strategy: AllocationStrategy,

    /// 性能监控器
    monitor: PerformanceMonitor,

    /// 统计收集器
    statistics: AllocationStatistics,

    /// 模式分析器
    pattern_analyzer: PatternAnalyzer,

    /// 最后策略切换时间
    last_switch_time: i64,

    pub fn init(base_allocator: std.mem.Allocator, config: SmartAllocatorConfig) !Self {
        var self = Self{
            .config = config,
            .base_allocator = base_allocator,
            .optimized_allocator = null,
            .extended_allocator = null,
            .arena_allocator = null,
            .current_strategy = config.default_strategy,
            .monitor = PerformanceMonitor.init(),
            .statistics = AllocationStatistics.init(),
            .pattern_analyzer = PatternAnalyzer.init(),
            .last_switch_time = std.time.milliTimestamp(),
        };

        // 根据默认策略初始化对应的分配器
        try self.initializeAllocator(config.default_strategy);

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.optimized_allocator) |*opt_alloc| opt_alloc.deinit();
        if (self.extended_allocator) |*ext_alloc| ext_alloc.deinit();
        if (self.arena_allocator) |*arena_alloc| arena_alloc.deinit();
    }

    /// 🚀 智能分配 - 统一入口
    pub fn alloc(self: *Self, comptime T: type, count: usize) ![]T {
        const size = @sizeOf(T) * count;
        const alignment = @alignOf(T);

        // 记录分配请求
        self.statistics.recordAllocationRequest(size);

        // 分析分配模式
        const pattern = self.pattern_analyzer.analyzeRequest(size);

        // 自动选择最优策略
        const optimal_strategy = if (self.config.enable_auto_switching)
            self.selectOptimalStrategy(size, pattern)
        else
            self.current_strategy;

        // 如果需要切换策略
        if (optimal_strategy != self.current_strategy) {
            try self.switchStrategy(optimal_strategy);
        }

        // 执行分配
        const start_time = std.time.nanoTimestamp();
        const memory = try self.allocateWithStrategy(size, alignment, optimal_strategy);
        const end_time = std.time.nanoTimestamp();

        // 记录性能数据
        const duration = @as(i64, @intCast(end_time - start_time));
        self.monitor.recordAllocation(size, duration);
        self.statistics.recordSuccessfulAllocation(size, optimal_strategy);

        return @as([*]T, @ptrCast(@alignCast(memory.ptr)))[0..count];
    }

    /// 🚀 智能释放 - 统一入口
    pub fn free(self: *Self, memory: anytype) void {
        const slice = switch (@TypeOf(memory)) {
            []u8 => memory,
            else => std.mem.sliceAsBytes(memory),
        };

        const size = slice.len;

        // 记录释放请求
        self.statistics.recordDeallocationRequest(size);

        // 执行释放
        const start_time = std.time.nanoTimestamp();
        self.freeWithStrategy(slice, self.current_strategy);
        const end_time = std.time.nanoTimestamp();

        // 记录性能数据
        const duration = @as(i64, @intCast(end_time - start_time));
        self.monitor.recordDeallocation(size, duration);
        self.statistics.recordSuccessfulDeallocation(size);
    }

    /// 🧠 选择最优分配策略
    fn selectOptimalStrategy(self: *Self, size: usize, pattern: AllocationPattern) AllocationStrategy {
        const config = self.config.auto_switch_config;

        // 基于大小的初步判断
        if (size <= config.small_object_threshold) {
            // 小对象：检查频率和复用率
            if (pattern.frequency > config.high_frequency_threshold) {
                return .object_pool;
            }
        } else if (size <= config.large_object_threshold) {
            // 中大对象：使用扩展池
            return .extended_pool;
        } else {
            // 超大对象：根据生命周期选择
            return switch (pattern.lifetime_pattern) {
                .short_lived => .standard,
                .medium_lived, .long_lived => .arena,
                .unknown => .standard,
            };
        }

        // 基于当前性能选择
        const current_performance = self.monitor.getCurrentPerformance();
        if (current_performance.avg_allocation_time > 1000) { // 1μs
            // 当前性能不佳，尝试切换到更快的策略
            if (size <= config.large_object_threshold) {
                return .extended_pool;
            }
        }

        return self.current_strategy; // 保持当前策略
    }

    /// 切换分配策略
    fn switchStrategy(self: *Self, new_strategy: AllocationStrategy) !void {
        const now = std.time.milliTimestamp();

        // 检查冷却时间
        if (now - self.last_switch_time < self.config.auto_switch_config.switch_cooldown_ms) {
            return; // 在冷却期内，不切换
        }

        // 初始化新策略的分配器
        try self.initializeAllocator(new_strategy);

        self.current_strategy = new_strategy;
        self.last_switch_time = now;

        // 记录策略切换
        self.statistics.recordStrategySwitch(new_strategy);
    }

    /// 初始化指定策略的分配器
    fn initializeAllocator(self: *Self, strategy: AllocationStrategy) !void {
        switch (strategy) {
            .auto => {}, // auto策略不需要特定分配器
            .object_pool => {
                if (self.optimized_allocator == null) {
                    self.optimized_allocator = try OptimizedAllocator.init(self.base_allocator);
                }
            },
            .extended_pool => {
                if (self.extended_allocator == null) {
                    self.extended_allocator = try ExtendedAllocator.init(self.base_allocator);
                }
            },
            .arena => {
                if (self.arena_allocator == null) {
                    self.arena_allocator = std.heap.ArenaAllocator.init(self.base_allocator);
                }
            },
            .standard => {}, // 使用base_allocator
        }
    }

    /// 使用指定策略分配内存
    fn allocateWithStrategy(self: *Self, size: usize, alignment: usize, strategy: AllocationStrategy) ![]u8 {
        _ = alignment; // 简化实现，暂时忽略对齐

        return switch (strategy) {
            .auto => unreachable, // auto策略应该已经被解析为具体策略
            .object_pool => blk: {
                if (self.optimized_allocator) |*opt_alloc| {
                    break :blk try opt_alloc.alloc(size);
                }
                break :blk try self.base_allocator.alloc(u8, size);
            },
            .extended_pool => blk: {
                if (self.extended_allocator) |*ext_alloc| {
                    break :blk try ext_alloc.alloc(size);
                }
                break :blk try self.base_allocator.alloc(u8, size);
            },
            .arena => blk: {
                if (self.arena_allocator) |*arena_alloc| {
                    break :blk try arena_alloc.allocator().alloc(u8, size);
                }
                break :blk try self.base_allocator.alloc(u8, size);
            },
            .standard => try self.base_allocator.alloc(u8, size),
        };
    }

    /// 使用指定策略释放内存
    fn freeWithStrategy(self: *Self, memory: []u8, strategy: AllocationStrategy) void {
        switch (strategy) {
            .auto => unreachable,
            .object_pool => {
                if (self.optimized_allocator) |*opt_alloc| {
                    opt_alloc.free(memory);
                } else {
                    self.base_allocator.free(memory);
                }
            },
            .extended_pool => {
                if (self.extended_allocator) |*ext_alloc| {
                    ext_alloc.free(memory);
                } else {
                    self.base_allocator.free(memory);
                }
            },
            .arena => {
                // Arena分配器通常不需要单独释放
                // 内存会在arena销毁时一起释放
            },
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

    /// 获取性能统计
    pub fn getPerformanceStats(self: *const Self) PerformanceStats {
        return self.monitor.getStats();
    }

    /// 获取分配统计
    pub fn getAllocationStats(self: *const Self) AllocationStatistics {
        return self.statistics;
    }

    /// 获取当前最优策略建议
    pub fn getOptimalStrategyRecommendation(self: *const Self) AllocationStrategy {
        _ = self;
        // 简化实现：返回默认策略
        return .auto;
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
        return false; // 暂不支持resize
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
        return null; // 不支持remap
    }
};

// 辅助结构体的简化实现
const PerformanceMonitor = struct {
    total_allocations: u64 = 0,
    total_allocation_time: u64 = 0,

    fn init() @This() {
        return @This(){};
    }

    fn recordAllocation(self: *@This(), size: usize, time_ns: i64) void {
        _ = size;
        self.total_allocations += 1;
        self.total_allocation_time += @as(u64, @intCast(time_ns));
    }

    fn recordDeallocation(self: *@This(), size: usize, time_ns: i64) void {
        _ = self;
        _ = size;
        _ = time_ns;
    }

    fn getCurrentPerformance(self: *const @This()) PerformanceStats {
        return PerformanceStats{
            .avg_allocation_time = if (self.total_allocations > 0)
                self.total_allocation_time / self.total_allocations
            else
                0,
        };
    }

    fn getStats(self: *const @This()) PerformanceStats {
        return self.getCurrentPerformance();
    }
};

const AllocationStatistics = struct {
    total_requests: u64 = 0,
    successful_allocations: u64 = 0,
    strategy_switches: u64 = 0,

    fn init() @This() {
        return @This(){};
    }

    fn recordAllocationRequest(self: *@This(), size: usize) void {
        _ = size;
        self.total_requests += 1;
    }

    fn recordSuccessfulAllocation(self: *@This(), size: usize, strategy: AllocationStrategy) void {
        _ = size;
        _ = strategy;
        self.successful_allocations += 1;
    }

    fn recordDeallocationRequest(self: *@This(), size: usize) void {
        _ = self;
        _ = size;
    }

    fn recordSuccessfulDeallocation(self: *@This(), size: usize) void {
        _ = self;
        _ = size;
    }

    fn recordStrategySwitch(self: *@This(), new_strategy: AllocationStrategy) void {
        _ = new_strategy;
        self.strategy_switches += 1;
    }
};

const PatternAnalyzer = struct {
    fn init() @This() {
        return @This(){};
    }

    fn analyzeRequest(self: *@This(), size: usize) AllocationPattern {
        _ = self;
        _ = size;
        return AllocationPattern{
            .avg_size = 1024.0,
            .frequency = 100.0,
            .size_variance = 0.5,
            .lifetime_pattern = .medium_lived,
        };
    }

    fn getCurrentPattern(self: *const @This()) AllocationPattern {
        _ = self;
        return AllocationPattern{
            .avg_size = 1024.0,
            .frequency = 100.0,
            .size_variance = 0.5,
            .lifetime_pattern = .medium_lived,
        };
    }
};

const PerformanceStats = struct {
    avg_allocation_time: u64,
};
