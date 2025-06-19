//! Zokio 内存管理模块 V2 - 零开销抽象实现
//!
//! P0 优化：统一接口零开销重构
//! 目标：从 8.59M ops/sec 提升到 15M+ ops/sec (1.7x 提升)
//!
//! 核心优化技术：
//! - 🚀 编译时特化消除运行时开销
//! - ⚡ 内联函数减少调用栈深度
//! - 🎯 直接分配路径避免中间层
//! - 🧠 线程本地缓存减少原子操作

const std = @import("std");
const fast_smart_allocator = @import("fast_smart_allocator.zig");
const FastSmartAllocator = fast_smart_allocator.FastSmartAllocator;
const FastSmartAllocatorConfig = fast_smart_allocator.FastSmartAllocatorConfig;
const ExtendedAllocator = @import("extended_allocator.zig").ExtendedAllocator;
const OptimizedAllocator = @import("optimized_allocator.zig").OptimizedAllocator;

/// 缓存行大小（64字节，适用于大多数现代CPU）
const CACHE_LINE_SIZE = 64;

/// 性能模式枚举
pub const PerformanceMode = enum {
    /// 🚀 超高性能模式 - 零开销，无监控
    ultra_fast,
    /// 🔥 高性能模式 - 最小开销，基础统计
    high_performance,
    /// ⚖️ 平衡模式 - 轻量级监控
    balanced,
    /// 📊 调试模式 - 完整监控和调试信息
    debug,
};

/// 优化配置结构
pub const OptimizedConfig = struct {
    /// 性能模式
    mode: PerformanceMode = .high_performance,

    /// 小对象阈值（字节）
    small_threshold: usize = 256,

    /// 大对象阈值（字节）
    large_threshold: usize = 8192,

    /// 是否启用线程本地缓存
    enable_thread_local_cache: bool = true,

    /// 是否启用缓存行对齐
    enable_cache_alignment: bool = true,

    /// 是否启用预取优化
    enable_prefetch: bool = true,

    /// 编译时验证配置
    pub fn validate(comptime self: @This()) void {
        if (self.small_threshold == 0) {
            @compileError("small_threshold must be greater than 0");
        }
        if (self.large_threshold <= self.small_threshold) {
            @compileError("large_threshold must be greater than small_threshold");
        }
    }
};

/// 🚀 编译时特化的零开销内存管理器
pub fn ZokioMemoryV2(comptime config: OptimizedConfig) type {
    // 编译时验证配置
    comptime config.validate();

    return struct {
        const Self = @This();

        // 编译时选择最优分配器实现
        const AllocImpl = switch (config.mode) {
            .ultra_fast => UltraFastAllocator,
            .high_performance => HighPerformanceAllocator,
            .balanced => BalancedAllocator,
            .debug => DebugAllocator,
        };

        /// 分配器实现
        allocator_impl: AllocImpl,

        /// 基础分配器
        base_allocator: std.mem.Allocator,

        /// 线程本地缓存（如果启用）
        thread_local_cache: if (config.enable_thread_local_cache) ThreadLocalCache else void,

        /// 统计信息（仅在调试模式下）
        stats: if (config.mode == .debug) DebugStats else void,

        /// 初始化内存管理器
        pub fn init(base_allocator: std.mem.Allocator) !Self {
            return Self{
                .allocator_impl = try AllocImpl.init(base_allocator),
                .base_allocator = base_allocator,
                .thread_local_cache = if (config.enable_thread_local_cache)
                    ThreadLocalCache.init()
                else {},
                .stats = if (config.mode == .debug)
                    DebugStats.init()
                else {},
            };
        }

        /// 清理资源
        pub fn deinit(self: *Self) void {
            self.allocator_impl.deinit();
            if (config.enable_thread_local_cache) {
                self.thread_local_cache.deinit();
            }
        }

        /// 🚀 零开销分配函数 - 编译时特化
        pub inline fn alloc(self: *Self, comptime T: type, count: usize) ![]T {
            const size = @sizeOf(T) * count;

            // 编译时大小分类和路径选择
            return if (comptime size <= config.small_threshold)
                self.allocSmallFast(T, count, size)
            else if (comptime size <= config.large_threshold)
                self.allocMediumFast(T, count, size)
            else
                self.allocLargeFast(T, count, size);
        }

        /// 🚀 零开销释放函数
        pub inline fn free(self: *Self, memory: anytype) void {
            const size = @sizeOf(@TypeOf(memory[0])) * memory.len;

            // 编译时大小分类和路径选择
            if (comptime size <= config.small_threshold) {
                self.freeSmallFast(memory, size);
            } else if (comptime size <= config.large_threshold) {
                self.freeMediumFast(memory, size);
            } else {
                self.freeLargeFast(memory, size);
            }
        }

        /// 🚀 小对象快速分配 - 内联优化
        inline fn allocSmallFast(self: *Self, comptime T: type, count: usize, size: usize) ![]T {
            // 线程本地缓存优先
            if (config.enable_thread_local_cache) {
                if (self.thread_local_cache.tryAllocSmall(T, count)) |memory| {
                    return memory;
                }
            }

            // 直接调用优化分配器，避免中间层
            const memory = try self.allocator_impl.allocSmall(T, count);

            // 缓存行对齐优化
            if (config.enable_cache_alignment and @sizeOf(T) >= 32) {
                return self.alignToCacheLine(memory);
            }

            // 预取优化
            if (config.enable_prefetch and memory.len > 0) {
                @prefetch(&memory[0], .{});
            }

            // 调试模式统计
            if (config.mode == .debug) {
                self.stats.recordSmallAllocation(size);
            }

            return memory;
        }

        /// ⚡ 中等对象快速分配
        inline fn allocMediumFast(self: *Self, comptime T: type, count: usize, size: usize) ![]T {
            // 线程本地缓存优先
            if (config.enable_thread_local_cache) {
                if (self.thread_local_cache.tryAllocMedium(T, count)) |memory| {
                    return memory;
                }
            }

            // 直接调用扩展分配器
            const memory = try self.allocator_impl.allocMedium(T, count);

            // 预取优化
            if (config.enable_prefetch and memory.len > 0) {
                @prefetch(&memory[0], .{});
            }

            // 调试模式统计
            if (config.mode == .debug) {
                self.stats.recordMediumAllocation(size);
            }

            return memory;
        }

        /// 🎯 大对象快速分配
        inline fn allocLargeFast(self: *Self, comptime T: type, count: usize, size: usize) ![]T {
            // 大对象直接从基础分配器分配
            const memory = try self.base_allocator.alloc(T, count);

            // 大对象预取优化
            if (config.enable_prefetch and memory.len > 0) {
                // 预取多个缓存行
                var i: usize = 0;
                while (i < size) : (i += CACHE_LINE_SIZE) {
                    const ptr = @as([*]u8, @ptrCast(memory.ptr)) + i;
                    @prefetch(ptr, .{});
                }
            }

            // 调试模式统计
            if (config.mode == .debug) {
                self.stats.recordLargeAllocation(size);
            }

            return memory;
        }

        /// 🚀 小对象快速释放
        inline fn freeSmallFast(self: *Self, memory: anytype, size: usize) void {
            // 线程本地缓存回收
            if (config.enable_thread_local_cache) {
                if (self.thread_local_cache.tryFreeSmall(memory)) {
                    return;
                }
            }

            self.allocator_impl.freeSmall(memory);

            // 调试模式统计
            if (config.mode == .debug) {
                self.stats.recordSmallDeallocation(size);
            }
        }

        /// ⚡ 中等对象快速释放
        inline fn freeMediumFast(self: *Self, memory: anytype, size: usize) void {
            // 线程本地缓存回收
            if (config.enable_thread_local_cache) {
                if (self.thread_local_cache.tryFreeMedium(memory)) {
                    return;
                }
            }

            self.allocator_impl.freeMedium(memory);

            // 调试模式统计
            if (config.mode == .debug) {
                self.stats.recordMediumDeallocation(size);
            }
        }

        /// 🎯 大对象快速释放
        inline fn freeLargeFast(self: *Self, memory: anytype, size: usize) void {
            self.base_allocator.free(memory);

            // 调试模式统计
            if (config.mode == .debug) {
                self.stats.recordLargeDeallocation(size);
            }
        }

        /// 缓存行对齐优化
        inline fn alignToCacheLine(self: *Self, memory: anytype) @TypeOf(memory) {
            _ = self;
            const addr = @intFromPtr(memory.ptr);
            const aligned_addr = std.mem.alignForward(usize, addr, CACHE_LINE_SIZE);
            if (aligned_addr == addr) {
                return memory;
            }

            // 如果需要重新对齐，这里可以实现更复杂的逻辑
            // 简化版本：直接返回原内存
            return memory;
        }

        /// 获取标准分配器接口
        pub fn allocator(self: *Self) std.mem.Allocator {
            return self.allocator_impl.allocator();
        }

        /// 获取统计信息（仅调试模式）
        pub fn getStats(self: *const Self) if (config.mode == .debug) DebugStats else void {
            if (config.mode == .debug) {
                return self.stats;
            } else {
                return {};
            }
        }
    };
}

/// 🚀 超高性能分配器 - 零开销实现
const UltraFastAllocator = struct {
    base_allocator: std.mem.Allocator,
    optimized: OptimizedAllocator,
    extended: ExtendedAllocator,

    pub fn init(base_allocator: std.mem.Allocator) !UltraFastAllocator {
        return UltraFastAllocator{
            .base_allocator = base_allocator,
            .optimized = try OptimizedAllocator.init(base_allocator),
            .extended = try ExtendedAllocator.init(base_allocator),
        };
    }

    pub fn deinit(self: *UltraFastAllocator) void {
        self.optimized.deinit();
        self.extended.deinit();
    }

    /// 小对象分配 - 直接路径
    pub inline fn allocSmall(self: *UltraFastAllocator, comptime T: type, count: usize) ![]T {
        return self.optimized.alloc(T, count);
    }

    /// 中等对象分配 - 直接路径
    pub inline fn allocMedium(self: *UltraFastAllocator, comptime T: type, count: usize) ![]T {
        return self.extended.alloc(T, count);
    }

    /// 小对象释放 - 直接路径
    pub inline fn freeSmall(self: *UltraFastAllocator, memory: anytype) void {
        self.optimized.free(memory);
    }

    /// 中等对象释放 - 直接路径
    pub inline fn freeMedium(self: *UltraFastAllocator, memory: anytype) void {
        self.extended.free(memory);
    }

    pub fn allocator(self: *UltraFastAllocator) std.mem.Allocator {
        return self.base_allocator;
    }
};

/// 🔥 高性能分配器 - 最小开销实现
const HighPerformanceAllocator = struct {
    base_allocator: std.mem.Allocator,
    smart: FastSmartAllocator,

    pub fn init(base_allocator: std.mem.Allocator) !HighPerformanceAllocator {
        const config = FastSmartAllocatorConfig{};
        return HighPerformanceAllocator{
            .base_allocator = base_allocator,
            .smart = try FastSmartAllocator.init(base_allocator, config),
        };
    }

    pub fn deinit(self: *HighPerformanceAllocator) void {
        self.smart.deinit();
    }

    /// 小对象分配
    pub inline fn allocSmall(self: *HighPerformanceAllocator, comptime T: type, count: usize) ![]T {
        return self.smart.alloc(T, count);
    }

    /// 中等对象分配
    pub inline fn allocMedium(self: *HighPerformanceAllocator, comptime T: type, count: usize) ![]T {
        return self.smart.alloc(T, count);
    }

    /// 小对象释放
    pub inline fn freeSmall(self: *HighPerformanceAllocator, memory: anytype) void {
        self.smart.free(memory);
    }

    /// 中等对象释放
    pub inline fn freeMedium(self: *HighPerformanceAllocator, memory: anytype) void {
        self.smart.free(memory);
    }

    pub fn allocator(self: *HighPerformanceAllocator) std.mem.Allocator {
        return self.base_allocator;
    }
};

/// ⚖️ 平衡分配器 - 轻量级监控
const BalancedAllocator = struct {
    base_allocator: std.mem.Allocator,
    smart: FastSmartAllocator,
    allocation_count: std.atomic.Value(u64),

    pub fn init(base_allocator: std.mem.Allocator) !BalancedAllocator {
        return BalancedAllocator{
            .base_allocator = base_allocator,
            .smart = try FastSmartAllocator.init(base_allocator, .{}),
            .allocation_count = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *BalancedAllocator) void {
        self.smart.deinit();
    }

    /// 小对象分配
    pub inline fn allocSmall(self: *BalancedAllocator, comptime T: type, count: usize) ![]T {
        _ = self.allocation_count.fetchAdd(1, .monotonic);
        return self.smart.alloc(T, count);
    }

    /// 中等对象分配
    pub inline fn allocMedium(self: *BalancedAllocator, comptime T: type, count: usize) ![]T {
        _ = self.allocation_count.fetchAdd(1, .monotonic);
        return self.smart.alloc(T, count);
    }

    /// 小对象释放
    pub inline fn freeSmall(self: *BalancedAllocator, memory: anytype) void {
        self.smart.free(memory);
    }

    /// 中等对象释放
    pub inline fn freeMedium(self: *BalancedAllocator, memory: anytype) void {
        self.smart.free(memory);
    }

    pub fn allocator(self: *BalancedAllocator) std.mem.Allocator {
        return self.base_allocator;
    }
};

/// 📊 调试分配器 - 完整监控
const DebugAllocator = struct {
    base_allocator: std.mem.Allocator,
    smart: FastSmartAllocator,

    pub fn init(base_allocator: std.mem.Allocator) !DebugAllocator {
        return DebugAllocator{
            .base_allocator = base_allocator,
            .smart = try FastSmartAllocator.init(base_allocator, .{}),
        };
    }

    pub fn deinit(self: *DebugAllocator) void {
        self.smart.deinit();
    }

    /// 小对象分配
    pub inline fn allocSmall(self: *DebugAllocator, comptime T: type, count: usize) ![]T {
        return self.smart.alloc(T, count);
    }

    /// 中等对象分配
    pub inline fn allocMedium(self: *DebugAllocator, comptime T: type, count: usize) ![]T {
        return self.smart.alloc(T, count);
    }

    /// 小对象释放
    pub inline fn freeSmall(self: *DebugAllocator, memory: anytype) void {
        self.smart.free(memory);
    }

    /// 中等对象释放
    pub inline fn freeMedium(self: *DebugAllocator, memory: anytype) void {
        self.smart.free(memory);
    }

    pub fn allocator(self: *DebugAllocator) std.mem.Allocator {
        return self.base_allocator;
    }
};

/// 🧠 线程本地缓存 - 减少原子操作
const ThreadLocalCache = struct {
    /// 小对象缓存数组（8种大小类别）
    small_cache: [8]SmallObjectCache,

    /// 中等对象缓存
    medium_cache: MediumObjectCache,

    /// 缓存统计
    hit_count: u64,
    miss_count: u64,

    const SmallObjectCache = struct {
        objects: [32]*anyopaque, // 每种大小32个对象
        count: u8,
        size_class: u8,

        pub fn init(size_class: u8) SmallObjectCache {
            return SmallObjectCache{
                .objects = undefined,
                .count = 0,
                .size_class = size_class,
            };
        }

        pub fn tryGet(self: *SmallObjectCache) ?*anyopaque {
            if (self.count == 0) return null;
            self.count -= 1;
            return self.objects[self.count];
        }

        pub fn tryPut(self: *SmallObjectCache, obj: *anyopaque) bool {
            if (self.count >= 32) return false;
            self.objects[self.count] = obj;
            self.count += 1;
            return true;
        }
    };

    const MediumObjectCache = struct {
        objects: [16]*anyopaque, // 16个中等对象
        count: u8,

        pub fn init() MediumObjectCache {
            return MediumObjectCache{
                .objects = undefined,
                .count = 0,
            };
        }

        pub fn tryGet(self: *MediumObjectCache) ?*anyopaque {
            if (self.count == 0) return null;
            self.count -= 1;
            return self.objects[self.count];
        }

        pub fn tryPut(self: *MediumObjectCache, obj: *anyopaque) bool {
            if (self.count >= 16) return false;
            self.objects[self.count] = obj;
            self.count += 1;
            return true;
        }
    };

    pub fn init() ThreadLocalCache {
        var cache = ThreadLocalCache{
            .small_cache = undefined,
            .medium_cache = MediumObjectCache.init(),
            .hit_count = 0,
            .miss_count = 0,
        };

        // 初始化小对象缓存
        for (0..8) |i| {
            cache.small_cache[i] = SmallObjectCache.init(@intCast(i));
        }

        return cache;
    }

    pub fn deinit(self: *ThreadLocalCache) void {
        _ = self;
        // 清理缓存中的对象（如果需要）
    }

    /// 尝试从缓存分配小对象
    pub fn tryAllocSmall(self: *ThreadLocalCache, comptime T: type, count: usize) ?[]T {
        const size = @sizeOf(T) * count;
        const size_class = getSizeClass(size);

        if (size_class >= 8) return null;

        if (self.small_cache[size_class].tryGet()) |obj| {
            self.hit_count += 1;
            return @as([*]T, @ptrCast(@alignCast(obj)))[0..count];
        }

        self.miss_count += 1;
        return null;
    }

    /// 尝试从缓存分配中等对象
    pub fn tryAllocMedium(self: *ThreadLocalCache, comptime T: type, count: usize) ?[]T {
        if (self.medium_cache.tryGet()) |obj| {
            self.hit_count += 1;
            return @as([*]T, @ptrCast(@alignCast(obj)))[0..count];
        }

        self.miss_count += 1;
        return null;
    }

    /// 尝试释放小对象到缓存
    pub fn tryFreeSmall(self: *ThreadLocalCache, memory: anytype) bool {
        const size = @sizeOf(@TypeOf(memory[0])) * memory.len;
        const size_class = getSizeClass(size);

        if (size_class >= 8) return false;

        return self.small_cache[size_class].tryPut(@ptrCast(memory.ptr));
    }

    /// 尝试释放中等对象到缓存
    pub fn tryFreeMedium(self: *ThreadLocalCache, memory: anytype) bool {
        return self.medium_cache.tryPut(@ptrCast(memory.ptr));
    }

    /// 获取大小类别
    fn getSizeClass(size: usize) usize {
        if (size <= 8) return 0;
        if (size <= 16) return 1;
        if (size <= 32) return 2;
        if (size <= 64) return 3;
        if (size <= 128) return 4;
        if (size <= 256) return 5;
        if (size <= 512) return 6;
        if (size <= 1024) return 7;
        return 8; // 超出小对象范围
    }

    /// 获取缓存命中率
    pub fn getHitRate(self: *const ThreadLocalCache) f32 {
        const total = self.hit_count + self.miss_count;
        if (total == 0) return 0.0;
        return @as(f32, @floatFromInt(self.hit_count)) / @as(f32, @floatFromInt(total));
    }
};

/// 📊 调试统计信息
const DebugStats = struct {
    /// 分配统计
    small_allocations: std.atomic.Value(u64),
    medium_allocations: std.atomic.Value(u64),
    large_allocations: std.atomic.Value(u64),

    /// 释放统计
    small_deallocations: std.atomic.Value(u64),
    medium_deallocations: std.atomic.Value(u64),
    large_deallocations: std.atomic.Value(u64),

    /// 字节统计
    total_allocated_bytes: std.atomic.Value(u64),
    total_deallocated_bytes: std.atomic.Value(u64),

    /// 时间统计
    total_allocation_time: std.atomic.Value(u64),
    allocation_count: std.atomic.Value(u64),

    pub fn init() DebugStats {
        return DebugStats{
            .small_allocations = std.atomic.Value(u64).init(0),
            .medium_allocations = std.atomic.Value(u64).init(0),
            .large_allocations = std.atomic.Value(u64).init(0),
            .small_deallocations = std.atomic.Value(u64).init(0),
            .medium_deallocations = std.atomic.Value(u64).init(0),
            .large_deallocations = std.atomic.Value(u64).init(0),
            .total_allocated_bytes = std.atomic.Value(u64).init(0),
            .total_deallocated_bytes = std.atomic.Value(u64).init(0),
            .total_allocation_time = std.atomic.Value(u64).init(0),
            .allocation_count = std.atomic.Value(u64).init(0),
        };
    }

    pub fn recordSmallAllocation(self: *DebugStats, size: usize) void {
        _ = self.small_allocations.fetchAdd(1, .monotonic);
        _ = self.total_allocated_bytes.fetchAdd(size, .monotonic);
        _ = self.allocation_count.fetchAdd(1, .monotonic);
    }

    pub fn recordMediumAllocation(self: *DebugStats, size: usize) void {
        _ = self.medium_allocations.fetchAdd(1, .monotonic);
        _ = self.total_allocated_bytes.fetchAdd(size, .monotonic);
        _ = self.allocation_count.fetchAdd(1, .monotonic);
    }

    pub fn recordLargeAllocation(self: *DebugStats, size: usize) void {
        _ = self.large_allocations.fetchAdd(1, .monotonic);
        _ = self.total_allocated_bytes.fetchAdd(size, .monotonic);
        _ = self.allocation_count.fetchAdd(1, .monotonic);
    }

    pub fn recordSmallDeallocation(self: *DebugStats, size: usize) void {
        _ = self.small_deallocations.fetchAdd(1, .monotonic);
        _ = self.total_deallocated_bytes.fetchAdd(size, .monotonic);
    }

    pub fn recordMediumDeallocation(self: *DebugStats, size: usize) void {
        _ = self.medium_deallocations.fetchAdd(1, .monotonic);
        _ = self.total_deallocated_bytes.fetchAdd(size, .monotonic);
    }

    pub fn recordLargeDeallocation(self: *DebugStats, size: usize) void {
        _ = self.large_deallocations.fetchAdd(1, .monotonic);
        _ = self.total_deallocated_bytes.fetchAdd(size, .monotonic);
    }

    /// 获取平均分配时间（纳秒）
    pub fn getAverageAllocationTime(self: *const DebugStats) u64 {
        const total_time = self.total_allocation_time.load(.monotonic);
        const count = self.allocation_count.load(.monotonic);
        if (count == 0) return 0;
        return total_time / count;
    }

    /// 获取总分配次数
    pub fn getTotalAllocations(self: *const DebugStats) u64 {
        return self.small_allocations.load(.monotonic) +
            self.medium_allocations.load(.monotonic) +
            self.large_allocations.load(.monotonic);
    }

    /// 获取当前内存使用量
    pub fn getCurrentMemoryUsage(self: *const DebugStats) u64 {
        const allocated = self.total_allocated_bytes.load(.monotonic);
        const deallocated = self.total_deallocated_bytes.load(.monotonic);
        return allocated - deallocated;
    }
};
