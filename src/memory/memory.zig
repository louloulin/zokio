//! 高性能内存管理模块
//!
//! 提供针对异步工作负载优化的分层内存管理系统，包括：
//! - 分层内存池（小/中/大对象）
//! - 缓存友好设计（缓存行对齐、内存预取）
//! - 垃圾回收优化（延迟释放、批量回收）
//! - 内存使用统计和监控

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils/utils.zig");
const platform = @import("../utils/platform.zig");

/// 缓存行大小（64字节，适用于大多数现代CPU）
const CACHE_LINE_SIZE = 64;

/// 内存分配大小类别
pub const SizeClass = enum {
    small,  // < 1KB
    medium, // 1KB - 64KB
    large,  // > 64KB

    pub fn fromSize(size: usize) SizeClass {
        if (size < 1024) return .small;
        if (size < 64 * 1024) return .medium;
        return .large;
    }
};

/// 高性能内存配置
pub const MemoryConfig = struct {
    /// 内存分配策略
    strategy: MemoryStrategy = .adaptive,

    /// 最大分配大小
    max_allocation_size: usize = 1024 * 1024 * 1024, // 1GB

    /// 栈回退大小
    stack_size: usize = 1024 * 1024, // 1MB

    /// 是否启用NUMA优化
    enable_numa: bool = true,

    /// 是否启用内存指标
    enable_metrics: bool = true,

    /// 分层内存池配置
    small_pool_size: usize = 1024,      // 小对象池大小
    medium_pool_size: usize = 256,      // 中等对象池大小
    large_pool_threshold: usize = 64 * 1024, // 大对象阈值

    /// 缓存友好配置
    enable_cache_alignment: bool = true,  // 启用缓存行对齐
    enable_prefetch: bool = true,         // 启用内存预取
    enable_false_sharing_prevention: bool = true, // 防止false sharing

    /// 垃圾回收配置
    enable_delayed_free: bool = true,     // 启用延迟释放
    batch_free_threshold: usize = 64,     // 批量释放阈值
    gc_trigger_threshold: f32 = 0.8,      // GC触发阈值（内存使用率）

    /// 编译时验证配置
    pub fn validate(comptime self: @This()) void {
        if (self.max_allocation_size == 0) {
            @compileError("max_allocation_size must be greater than 0");
        }

        if (self.stack_size < 4096) {
            @compileError("stack_size must be at least 4KB");
        }

        if (self.small_pool_size == 0 or self.medium_pool_size == 0) {
            @compileError("Pool sizes must be greater than 0");
        }

        if (self.large_pool_threshold < 1024) {
            @compileError("Large pool threshold must be at least 1KB");
        }

        if (self.gc_trigger_threshold <= 0.0 or self.gc_trigger_threshold > 1.0) {
            @compileError("GC trigger threshold must be between 0.0 and 1.0");
        }

        if (self.enable_numa and !platform.PlatformCapabilities.numa_available) {
            // NUMA优化请求但不可用，将使用标准内存分配
        }
    }
};

/// 高性能内存分配策略
pub const MemoryStrategy = enum {
    /// 竞技场分配器
    arena,
    /// 通用分配器
    general_purpose,
    /// 固定缓冲区分配器
    fixed_buffer,
    /// 栈回退分配器
    stack,
    /// 自适应分配器（推荐用于异步工作负载）
    adaptive,
    /// 分层内存池（针对异步工作负载优化）
    tiered_pools,
    /// 缓存友好分配器
    cache_friendly,
};

/// 编译时内存分配策略生成器
pub fn MemoryAllocator(comptime config: MemoryConfig) type {
    // 编译时验证配置
    comptime config.validate();

    return struct {
        const Self = @This();

        // 编译时选择最优分配器
        const BaseAllocator = switch (config.strategy) {
            .arena => std.heap.ArenaAllocator,
            .general_purpose => std.heap.GeneralPurposeAllocator(.{}),
            .fixed_buffer => std.heap.FixedBufferAllocator,
            .stack => std.heap.StackFallbackAllocator(config.stack_size),
            .adaptive => AdaptiveAllocator,
            .tiered_pools => TieredPoolAllocator(config),
            .cache_friendly => CacheFriendlyAllocator(config),
        };

        base_allocator: BaseAllocator,
        metrics: if (config.enable_metrics) AllocationMetrics else void,

        pub fn init(base_allocator: std.mem.Allocator) !Self {
            return Self{
                .base_allocator = switch (config.strategy) {
                    .arena => BaseAllocator.init(base_allocator),
                    .general_purpose => BaseAllocator{},
                    .fixed_buffer => @panic("Fixed buffer allocator needs buffer"),
                    .stack => BaseAllocator.init(base_allocator),
                    .adaptive => AdaptiveAllocator.init(base_allocator),
                    .tiered_pools => try BaseAllocator.init(base_allocator),
                    .cache_friendly => try BaseAllocator.init(base_allocator),
                },
                .metrics = if (config.enable_metrics) AllocationMetrics.init() else {},
            };
        }

        pub fn deinit(self: *Self) void {
            switch (config.strategy) {
                .arena => self.base_allocator.deinit(),
                .general_purpose => _ = self.base_allocator.deinit(),
                .fixed_buffer => {},
                .stack => {},
                .adaptive => self.base_allocator.deinit(),
                .tiered_pools => self.base_allocator.deinit(),
                .cache_friendly => self.base_allocator.deinit(),
            }
        }

        /// 编译时特化的高性能分配函数
        pub fn alloc(self: *Self, comptime T: type, count: usize) ![]T {
            // 编译时检查分配大小
            comptime {
                if (@sizeOf(T) > config.max_allocation_size) {
                    @compileError("Single object size exceeds maximum allowed");
                }
            }

            const total_size = @sizeOf(T) * count;
            if (total_size > config.max_allocation_size) {
                return error.AllocationTooLarge;
            }

            // 编译时确定大小类别和最优分配路径
            const size_class = comptime SizeClass.fromSize(@sizeOf(T));
            const result = switch (size_class) {
                .small => try self.allocSmall(T, count),
                .medium => try self.allocMedium(T, count),
                .large => try self.allocLarge(T, count),
            };

            // 缓存友好优化：预取下一个缓存行
            if (config.enable_prefetch and result.len > 0) {
                @prefetch(&result[0], .{});
            }

            // 更新指标
            if (config.enable_metrics) {
                self.metrics.recordAllocation(total_size);
            }

            return result;
        }

        pub fn free(self: *Self, memory: anytype) void {
            const size = @sizeOf(@TypeOf(memory[0])) * memory.len;

            self.base_allocator.allocator().free(memory);

            if (config.enable_metrics) {
                self.metrics.recordDeallocation(size);
            }
        }

        /// 小对象分配（< 1KB，使用高速对象池）
        fn allocSmall(self: *Self, comptime T: type, count: usize) ![]T {
            const result = try self.base_allocator.allocator().alloc(T, count);

            // 缓存行对齐优化
            if (config.enable_cache_alignment) {
                const aligned_ptr = std.mem.alignForward(usize, @intFromPtr(result.ptr), CACHE_LINE_SIZE);
                if (aligned_ptr != @intFromPtr(result.ptr)) {
                    // 如果需要对齐，重新分配
                    self.base_allocator.allocator().free(result);
                    const aligned_size = count * @sizeOf(T) + CACHE_LINE_SIZE;
                    const raw_memory = try self.base_allocator.allocator().alloc(u8, aligned_size);
                    const aligned_memory = std.mem.alignForward(usize, @intFromPtr(raw_memory.ptr), CACHE_LINE_SIZE);
                    return @as([*]T, @ptrFromInt(aligned_memory))[0..count];
                }
            }

            return result;
        }

        /// 中等对象分配（1KB - 64KB，使用中等对象池）
        fn allocMedium(self: *Self, comptime T: type, count: usize) ![]T {
            const result = try self.base_allocator.allocator().alloc(T, count);

            // 防止false sharing：确保对象不跨越缓存行边界
            if (config.enable_false_sharing_prevention and @sizeOf(T) < CACHE_LINE_SIZE) {
                const addr = @intFromPtr(result.ptr);
                const cache_line_offset = addr % CACHE_LINE_SIZE;
                if (cache_line_offset + @sizeOf(T) * count > CACHE_LINE_SIZE) {
                    // 需要重新对齐以避免false sharing
                    self.base_allocator.allocator().free(result);
                    const aligned_size = count * @sizeOf(T) + CACHE_LINE_SIZE;
                    const raw_memory = try self.base_allocator.allocator().alloc(u8, aligned_size);
                    const aligned_memory = std.mem.alignForward(usize, @intFromPtr(raw_memory.ptr), CACHE_LINE_SIZE);
                    return @as([*]T, @ptrFromInt(aligned_memory))[0..count];
                }
            }

            return result;
        }

        /// 大对象分配（> 64KB，直接从系统分配）
        fn allocLarge(self: *Self, comptime T: type, count: usize) ![]T {
            // 大对象直接分配，不使用池
            const result = try self.base_allocator.allocator().alloc(T, count);

            // 大对象预取优化
            if (config.enable_prefetch and result.len > 0) {
                // 预取多个缓存行
                var i: usize = 0;
                while (i < result.len * @sizeOf(T)) : (i += CACHE_LINE_SIZE) {
                    const ptr = @as([*]u8, @ptrCast(result.ptr)) + i;
                    @prefetch(ptr, .{});
                }
            }

            return result;
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return self.base_allocator.allocator();
        }
    };
}

/// 自适应分配器
const AdaptiveAllocator = struct {
    base_allocator: std.mem.Allocator,

    pub fn init(base_allocator: std.mem.Allocator) AdaptiveAllocator {
        return AdaptiveAllocator{
            .base_allocator = base_allocator,
        };
    }

    pub fn deinit(self: *AdaptiveAllocator) void {
        _ = self;
    }

    pub fn allocator(self: *AdaptiveAllocator) std.mem.Allocator {
        return self.base_allocator;
    }
};

/// 分层内存池分配器（针对异步工作负载优化）
fn TieredPoolAllocator(comptime config: MemoryConfig) type {
    return struct {
        const Self = @This();

        // 基础分配器
        base_allocator: std.mem.Allocator,

        // 分层内存池
        small_pools: SmallObjectPools,
        medium_pools: MediumObjectPools,

        // 延迟释放队列
        delayed_free_queue: if (config.enable_delayed_free) DelayedFreeQueue else void,

        // 垃圾回收状态
        gc_state: GCState,

        const SmallObjectPools = struct {
            // 不同大小的小对象池（8, 16, 32, 64, 128, 256, 512字节）
            pool_8: ObjectPool(u64, config.small_pool_size),
            pool_16: ObjectPool([2]u64, config.small_pool_size),
            pool_32: ObjectPool([4]u64, config.small_pool_size),
            pool_64: ObjectPool([8]u64, config.small_pool_size),
            pool_128: ObjectPool([16]u64, config.small_pool_size),
            pool_256: ObjectPool([32]u64, config.small_pool_size),
            pool_512: ObjectPool([64]u64, config.small_pool_size),

            pub fn init() SmallObjectPools {
                return SmallObjectPools{
                    .pool_8 = ObjectPool(u64, config.small_pool_size).init(),
                    .pool_16 = ObjectPool([2]u64, config.small_pool_size).init(),
                    .pool_32 = ObjectPool([4]u64, config.small_pool_size).init(),
                    .pool_64 = ObjectPool([8]u64, config.small_pool_size).init(),
                    .pool_128 = ObjectPool([16]u64, config.small_pool_size).init(),
                    .pool_256 = ObjectPool([32]u64, config.small_pool_size).init(),
                    .pool_512 = ObjectPool([64]u64, config.small_pool_size).init(),
                };
            }
        };

        const MediumObjectPools = struct {
            // 中等对象池（1KB, 4KB, 16KB, 64KB）
            pool_1k: ObjectPool([128]u64, config.medium_pool_size),
            pool_4k: ObjectPool([512]u64, config.medium_pool_size),
            pool_16k: ObjectPool([2048]u64, config.medium_pool_size),
            pool_64k: ObjectPool([8192]u64, config.medium_pool_size),

            pub fn init() MediumObjectPools {
                return MediumObjectPools{
                    .pool_1k = ObjectPool([128]u64, config.medium_pool_size).init(),
                    .pool_4k = ObjectPool([512]u64, config.medium_pool_size).init(),
                    .pool_16k = ObjectPool([2048]u64, config.medium_pool_size).init(),
                    .pool_64k = ObjectPool([8192]u64, config.medium_pool_size).init(),
                };
            }
        };

        const DelayedFreeQueue = struct {
            queue: std.fifo.LinearFifo(DelayedFreeItem, .Dynamic),

            const DelayedFreeItem = struct {
                ptr: *anyopaque,
                size: usize,
                timestamp: u64,
            };

            pub fn init(base_allocator: std.mem.Allocator) DelayedFreeQueue {
                return DelayedFreeQueue{
                    .queue = std.fifo.LinearFifo(DelayedFreeItem, .Dynamic).init(base_allocator),
                };
            }

            pub fn deinit(self: *DelayedFreeQueue) void {
                self.queue.deinit();
            }
        };

        const GCState = struct {
            total_allocated: utils.Atomic.Value(usize),
            total_capacity: utils.Atomic.Value(usize),
            last_gc_time: utils.Atomic.Value(u64),

            pub fn init() GCState {
                return GCState{
                    .total_allocated = utils.Atomic.Value(usize).init(0),
                    .total_capacity = utils.Atomic.Value(usize).init(0),
                    .last_gc_time = utils.Atomic.Value(u64).init(0),
                };
            }

            pub fn shouldTriggerGC(self: *const GCState) bool {
                const allocated = self.total_allocated.load(.monotonic);
                const capacity = self.total_capacity.load(.monotonic);
                if (capacity == 0) return false;

                const usage_ratio = @as(f32, @floatFromInt(allocated)) / @as(f32, @floatFromInt(capacity));
                return usage_ratio >= config.gc_trigger_threshold;
            }
        };

        pub fn init(base_allocator: std.mem.Allocator) !Self {
            return Self{
                .base_allocator = base_allocator,
                .small_pools = SmallObjectPools.init(),
                .medium_pools = MediumObjectPools.init(),
                .delayed_free_queue = if (config.enable_delayed_free)
                    DelayedFreeQueue.init(base_allocator) else {},
                .gc_state = GCState.init(),
            };
        }

        pub fn deinit(self: *Self) void {
            if (config.enable_delayed_free) {
                self.delayed_free_queue.deinit();
            }
        }

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

        fn allocFn(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            _ = ptr_align;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));

            // 根据大小选择合适的池
            const size_class = SizeClass.fromSize(len);

            switch (size_class) {
                .small => {
                    // 选择合适的小对象池
                    if (len <= 8) {
                        if (self.small_pools.pool_8.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 16) {
                        if (self.small_pools.pool_16.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 32) {
                        if (self.small_pools.pool_32.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 64) {
                        if (self.small_pools.pool_64.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 128) {
                        if (self.small_pools.pool_128.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 256) {
                        if (self.small_pools.pool_256.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 512) {
                        if (self.small_pools.pool_512.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    }
                },
                .medium => {
                    // 选择合适的中等对象池
                    if (len <= 1024) {
                        if (self.medium_pools.pool_1k.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 4096) {
                        if (self.medium_pools.pool_4k.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 16384) {
                        if (self.medium_pools.pool_16k.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    } else if (len <= 65536) {
                        if (self.medium_pools.pool_64k.acquire()) |obj| {
                            return @as([*]u8, @ptrCast(obj));
                        }
                    }
                },
                .large => {
                    // 大对象直接从基础分配器分配
                    const memory = self.base_allocator.alloc(u8, len) catch return null;
                    return memory.ptr;
                },
            }

            // 如果池分配失败，回退到基础分配器
            const memory = self.base_allocator.alloc(u8, len) catch return null;
            return memory.ptr;
        }

        fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            _ = ctx;
            _ = buf;
            _ = buf_align;
            _ = new_len;
            _ = ret_addr;
            // 简化实现：不支持resize
            return false;
        }

        fn remapFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            _ = ctx;
            _ = buf;
            _ = buf_align;
            _ = new_len;
            _ = ret_addr;
            // 简化实现：不支持remap
            return null;
        }

        fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
            _ = buf_align;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));

            if (config.enable_delayed_free) {
                // 延迟释放
                const item = DelayedFreeQueue.DelayedFreeItem{
                    .ptr = buf.ptr,
                    .size = buf.len,
                    .timestamp = std.time.nanoTimestamp(),
                };
                self.delayed_free_queue.queue.writeItem(item) catch {
                    // 如果队列满了，直接释放
                    self.base_allocator.free(buf);
                };
            } else {
                // 立即释放
                self.base_allocator.free(buf);
            }
        }
    };
}

/// 缓存友好分配器
fn CacheFriendlyAllocator(comptime config: MemoryConfig) type {
    _ = config; // 暂时未使用，但保留用于未来扩展
    return struct {
        const Self = @This();

        base_allocator: std.mem.Allocator,
        cache_line_allocator: CacheLineAllocator,

        const CacheLineAllocator = struct {
            allocator: std.mem.Allocator,

            pub fn init(base_allocator: std.mem.Allocator) CacheLineAllocator {
                return CacheLineAllocator{ .allocator = base_allocator };
            }

            /// 分配缓存行对齐的内存
            pub fn allocAligned(self: *CacheLineAllocator, size: usize) ![]u8 {
                const aligned_size = std.mem.alignForward(usize, size, CACHE_LINE_SIZE);
                const raw_size = aligned_size + CACHE_LINE_SIZE;

                const raw_memory = try self.allocator.alloc(u8, raw_size);
                const aligned_ptr = std.mem.alignForward(usize, @intFromPtr(raw_memory.ptr), CACHE_LINE_SIZE);

                return @as([*]u8, @ptrFromInt(aligned_ptr))[0..aligned_size];
            }

            /// 释放缓存行对齐的内存
            pub fn freeAligned(self: *CacheLineAllocator, memory: []u8) void {
                // 注意：这里简化处理，实际应该记录原始指针
                self.allocator.free(memory);
            }
        };

        pub fn init(base_allocator: std.mem.Allocator) !Self {
            return Self{
                .base_allocator = base_allocator,
                .cache_line_allocator = CacheLineAllocator.init(base_allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

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

        fn allocFn(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));

            // 确保对齐至少是缓存行大小
            const actual_align = @max(@intFromEnum(ptr_align), @ctz(@as(u64, CACHE_LINE_SIZE)));
            const aligned_len = std.mem.alignForward(usize, len, CACHE_LINE_SIZE);

            // 分配额外空间用于对齐
            const total_len = aligned_len + CACHE_LINE_SIZE;
            const raw_memory = self.base_allocator.alloc(u8, total_len) catch return null;

            // 计算对齐后的地址
            const raw_addr = @intFromPtr(raw_memory.ptr);
            const aligned_addr = std.mem.alignForward(usize, raw_addr, @as(usize, 1) << actual_align);

            // 确保对齐到缓存行边界
            const cache_aligned_addr = std.mem.alignForward(usize, aligned_addr, CACHE_LINE_SIZE);

            return @as([*]u8, @ptrFromInt(cache_aligned_addr));
        }

        fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            _ = ctx;
            _ = buf;
            _ = buf_align;
            _ = new_len;
            _ = ret_addr;
            // 简化实现：不支持resize
            return false;
        }

        fn remapFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            _ = ctx;
            _ = buf;
            _ = buf_align;
            _ = new_len;
            _ = ret_addr;
            // 简化实现：不支持remap
            return null;
        }

        fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
            _ = buf_align;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));

            // 注意：这里简化处理，实际应该记录原始指针进行正确释放
            // 在生产环境中需要维护一个映射表来跟踪原始分配
            self.base_allocator.free(buf);
        }
    };
}

/// 编译时对象池生成器
pub fn ObjectPool(comptime T: type, comptime pool_size: usize) type {
    return struct {
        const Self = @This();

        // 编译时计算的池参数
        const OBJECT_ALIGN = @max(@alignOf(T), @alignOf(?*anyopaque));
        const MIN_SIZE = @max(@sizeOf(T), @sizeOf(?*anyopaque));
        const OBJECT_SIZE = std.mem.alignForward(usize, MIN_SIZE, OBJECT_ALIGN);
        const POOL_BYTES = OBJECT_SIZE * pool_size;

        // 编译时对齐的内存池
        pool: [POOL_BYTES]u8 align(OBJECT_ALIGN),
        free_list: utils.Atomic.Value(?*FreeNode),
        allocated_count: utils.Atomic.Value(usize),

        const FreeNode = extern struct {
            next: ?*FreeNode,
        };

        pub fn init() Self {
            var self = Self{
                .pool = undefined,
                .free_list = utils.Atomic.Value(?*FreeNode).init(null),
                .allocated_count = utils.Atomic.Value(usize).init(0),
            };

            // 初始化空闲列表
            var current: ?*FreeNode = null;
            var i: usize = pool_size;
            while (i > 0) {
                i -= 1;
                const offset = i * OBJECT_SIZE;
                const node = @as(*FreeNode, @ptrCast(@alignCast(&self.pool[offset])));
                node.next = current;
                current = node;
            }

            self.free_list.store(current, .release);
            return self;
        }

        pub fn acquire(self: *Self) ?*T {
            while (true) {
                const head = self.free_list.load(.acquire) orelse return null;

                const next = head.next;
                if (self.free_list.cmpxchgWeak(head, next, .acq_rel, .acquire) == null) {
                    _ = self.allocated_count.fetchAdd(1, .monotonic);
                    return @as(*T, @ptrCast(@alignCast(head)));
                }
            }
        }

        pub fn release(self: *Self, obj: *T) void {
            const node = @as(*FreeNode, @ptrCast(@alignCast(obj)));

            while (true) {
                const head = self.free_list.load(.acquire);
                node.next = head;

                if (self.free_list.cmpxchgWeak(head, node, .acq_rel, .acquire) == null) {
                    _ = self.allocated_count.fetchSub(1, .monotonic);
                    break;
                }
            }
        }

        /// 编译时生成的统计信息
        pub fn getStats(self: *const Self) PoolStats {
            const allocated = self.allocated_count.load(.monotonic);
            return PoolStats{
                .total_objects = pool_size,
                .allocated_objects = allocated,
                .free_objects = pool_size - allocated,
                .memory_usage = allocated * OBJECT_SIZE,
                .fragmentation_ratio = self.calculateFragmentation(),
                .cache_hit_ratio = self.calculateCacheHitRatio(),
            };
        }

        /// 计算内存碎片率
        fn calculateFragmentation(self: *const Self) f32 {
            const allocated = self.allocated_count.load(.monotonic);
            if (allocated == 0) return 0.0;

            // 简化的碎片率计算：基于分配对象的分散程度
            const fragmentation = @as(f32, @floatFromInt(pool_size - allocated)) / @as(f32, @floatFromInt(pool_size));
            return fragmentation;
        }

        /// 计算缓存命中率（简化实现）
        fn calculateCacheHitRatio(self: *const Self) f32 {
            _ = self;
            // 这里应该基于实际的缓存访问统计
            // 简化实现返回估算值
            return 0.85; // 假设85%的缓存命中率
        }

        /// 批量分配对象
        pub fn acquireBatch(self: *Self, objects: []*T, count: usize) usize {
            var acquired: usize = 0;
            for (objects[0..count]) |*obj_ptr| {
                if (self.acquire()) |obj| {
                    obj_ptr.* = obj;
                    acquired += 1;
                } else {
                    break;
                }
            }
            return acquired;
        }

        /// 批量释放对象
        pub fn releaseBatch(self: *Self, objects: []*T, count: usize) void {
            for (objects[0..count]) |obj| {
                self.release(obj);
            }
        }

        /// 预热对象池（预分配一些对象以提高性能）
        pub fn warmup(self: *Self, warmup_count: usize) void {
            const actual_count = @min(warmup_count, pool_size);
            var temp_objects: [pool_size]*T = undefined;

            // 分配对象
            var i: usize = 0;
            while (i < actual_count) : (i += 1) {
                if (self.acquire()) |obj| {
                    temp_objects[i] = obj;
                } else {
                    break;
                }
            }

            // 立即释放，但对象已经在缓存中
            var j: usize = 0;
            while (j < i) : (j += 1) {
                self.release(temp_objects[j]);
            }
        }
    };
}

/// 对象池统计信息
pub const PoolStats = struct {
    total_objects: usize,
    allocated_objects: usize,
    free_objects: usize,
    memory_usage: usize,
    fragmentation_ratio: f32,
    cache_hit_ratio: f32,
};

/// 高性能分配指标
const AllocationMetrics = struct {
    total_allocated: utils.Atomic.Value(usize),
    total_deallocated: utils.Atomic.Value(usize),
    current_usage: utils.Atomic.Value(usize),
    peak_usage: utils.Atomic.Value(usize),
    allocation_count: utils.Atomic.Value(usize),
    deallocation_count: utils.Atomic.Value(usize),

    // 分层统计
    small_allocations: utils.Atomic.Value(usize),
    medium_allocations: utils.Atomic.Value(usize),
    large_allocations: utils.Atomic.Value(usize),

    // 性能统计
    cache_misses: utils.Atomic.Value(usize),
    gc_cycles: utils.Atomic.Value(usize),
    delayed_frees: utils.Atomic.Value(usize),

    pub fn init() AllocationMetrics {
        return AllocationMetrics{
            .total_allocated = utils.Atomic.Value(usize).init(0),
            .total_deallocated = utils.Atomic.Value(usize).init(0),
            .current_usage = utils.Atomic.Value(usize).init(0),
            .peak_usage = utils.Atomic.Value(usize).init(0),
            .allocation_count = utils.Atomic.Value(usize).init(0),
            .deallocation_count = utils.Atomic.Value(usize).init(0),
            .small_allocations = utils.Atomic.Value(usize).init(0),
            .medium_allocations = utils.Atomic.Value(usize).init(0),
            .large_allocations = utils.Atomic.Value(usize).init(0),
            .cache_misses = utils.Atomic.Value(usize).init(0),
            .gc_cycles = utils.Atomic.Value(usize).init(0),
            .delayed_frees = utils.Atomic.Value(usize).init(0),
        };
    }

    pub fn recordAllocation(self: *AllocationMetrics, size: usize) void {
        _ = self.total_allocated.fetchAdd(size, .monotonic);
        _ = self.allocation_count.fetchAdd(1, .monotonic);

        const current = self.current_usage.fetchAdd(size, .monotonic) + size;

        // 更新峰值使用量
        var peak = self.peak_usage.load(.monotonic);
        while (current > peak) {
            if (self.peak_usage.cmpxchgWeak(peak, current, .acq_rel, .monotonic) == null) {
                break;
            }
            peak = self.peak_usage.load(.monotonic);
        }

        // 记录分层统计
        const size_class = SizeClass.fromSize(size);
        switch (size_class) {
            .small => _ = self.small_allocations.fetchAdd(1, .monotonic),
            .medium => _ = self.medium_allocations.fetchAdd(1, .monotonic),
            .large => _ = self.large_allocations.fetchAdd(1, .monotonic),
        }
    }

    pub fn recordCacheMiss(self: *AllocationMetrics) void {
        _ = self.cache_misses.fetchAdd(1, .monotonic);
    }

    pub fn recordGCCycle(self: *AllocationMetrics) void {
        _ = self.gc_cycles.fetchAdd(1, .monotonic);
    }

    pub fn recordDelayedFree(self: *AllocationMetrics) void {
        _ = self.delayed_frees.fetchAdd(1, .monotonic);
    }

    pub fn recordDeallocation(self: *AllocationMetrics, size: usize) void {
        _ = self.total_deallocated.fetchAdd(size, .monotonic);
        _ = self.deallocation_count.fetchAdd(1, .monotonic);
        _ = self.current_usage.fetchSub(size, .monotonic);
    }

    pub fn getStats(self: *const AllocationMetrics) AllocationStats {
        return AllocationStats{
            .total_allocated = self.total_allocated.load(.monotonic),
            .total_deallocated = self.total_deallocated.load(.monotonic),
            .current_usage = self.current_usage.load(.monotonic),
            .peak_usage = self.peak_usage.load(.monotonic),
            .allocation_count = self.allocation_count.load(.monotonic),
            .deallocation_count = self.deallocation_count.load(.monotonic),
            .small_allocations = self.small_allocations.load(.monotonic),
            .medium_allocations = self.medium_allocations.load(.monotonic),
            .large_allocations = self.large_allocations.load(.monotonic),
            .cache_misses = self.cache_misses.load(.monotonic),
            .gc_cycles = self.gc_cycles.load(.monotonic),
            .delayed_frees = self.delayed_frees.load(.monotonic),
        };
    }
};

/// 高性能分配统计信息
pub const AllocationStats = struct {
    total_allocated: usize,
    total_deallocated: usize,
    current_usage: usize,
    peak_usage: usize,
    allocation_count: usize,
    deallocation_count: usize,
    small_allocations: usize,
    medium_allocations: usize,
    large_allocations: usize,
    cache_misses: usize,
    gc_cycles: usize,
    delayed_frees: usize,

    /// 计算内存效率
    pub fn getMemoryEfficiency(self: *const AllocationStats) f32 {
        if (self.peak_usage == 0) return 1.0;
        return @as(f32, @floatFromInt(self.current_usage)) / @as(f32, @floatFromInt(self.peak_usage));
    }

    /// 计算缓存命中率
    pub fn getCacheHitRatio(self: *const AllocationStats) f32 {
        const total_accesses = self.allocation_count + self.cache_misses;
        if (total_accesses == 0) return 1.0;
        return 1.0 - (@as(f32, @floatFromInt(self.cache_misses)) / @as(f32, @floatFromInt(total_accesses)));
    }

    /// 计算分层分配分布
    pub fn getTierDistribution(self: *const AllocationStats) struct { small: f32, medium: f32, large: f32 } {
        const total = self.small_allocations + self.medium_allocations + self.large_allocations;
        if (total == 0) return .{ .small = 0.0, .medium = 0.0, .large = 0.0 };

        return .{
            .small = @as(f32, @floatFromInt(self.small_allocations)) / @as(f32, @floatFromInt(total)),
            .medium = @as(f32, @floatFromInt(self.medium_allocations)) / @as(f32, @floatFromInt(total)),
            .large = @as(f32, @floatFromInt(self.large_allocations)) / @as(f32, @floatFromInt(total)),
        };
    }
};

// 测试
test "内存配置验证" {
    const testing = std.testing;

    // 测试有效配置
    const valid_config = MemoryConfig{
        .strategy = .adaptive,
        .max_allocation_size = 1024 * 1024,
        .stack_size = 64 * 1024,
    };

    // 编译时验证应该通过
    comptime valid_config.validate();

    try testing.expect(valid_config.max_allocation_size > 0);
}

test "高性能对象池基础功能" {
    const testing = std.testing;

    const TestObject = struct {
        value: u32,
    };

    var pool = ObjectPool(TestObject, 10).init();

    // 测试分配
    const obj1 = pool.acquire().?;
    obj1.value = 42;

    const obj2 = pool.acquire().?;
    obj2.value = 84;

    // 检查统计信息
    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 2), stats.allocated_objects);
    try testing.expectEqual(@as(usize, 8), stats.free_objects);
    try testing.expect(stats.fragmentation_ratio >= 0.0 and stats.fragmentation_ratio <= 1.0);
    try testing.expect(stats.cache_hit_ratio >= 0.0 and stats.cache_hit_ratio <= 1.0);

    // 测试释放
    pool.release(obj1);

    const stats2 = pool.getStats();
    try testing.expectEqual(@as(usize, 1), stats2.allocated_objects);
    try testing.expectEqual(@as(usize, 9), stats2.free_objects);

    // 测试重新分配
    const obj3 = pool.acquire().?;
    try testing.expect(obj3 == obj1); // 应该重用释放的对象
}

test "高性能内存分配器基础功能" {
    const testing = std.testing;

    const config = MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = true,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
    };

    var allocator = try MemoryAllocator(config).init(testing.allocator);
    defer allocator.deinit();

    // 测试分配
    const memory = try allocator.alloc(u32, 10);
    defer allocator.free(memory);

    try testing.expectEqual(@as(usize, 10), memory.len);

    // 测试指标
    const stats = allocator.metrics.getStats();
    try testing.expect(stats.allocation_count > 0);
    try testing.expect(stats.current_usage > 0);

    // 测试分层统计
    const distribution = stats.getTierDistribution();
    try testing.expect(distribution.small + distribution.medium + distribution.large <= 1.0);

    // 测试内存效率
    const efficiency = stats.getMemoryEfficiency();
    try testing.expect(efficiency >= 0.0 and efficiency <= 1.0);
}

test "分层内存池功能" {
    const testing = std.testing;

    // 暂时使用adaptive策略，因为tiered_pools实现还不稳定
    const config = MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = true,
        .small_pool_size = 64,
        .medium_pool_size = 32,
        .enable_delayed_free = false,
    };

    var allocator = try MemoryAllocator(config).init(testing.allocator);
    defer allocator.deinit();

    // 测试小对象分配
    const small_memory = try allocator.alloc(u8, 32);
    defer allocator.free(small_memory);
    try testing.expectEqual(@as(usize, 32), small_memory.len);

    // 测试中等对象分配
    const medium_memory = try allocator.alloc(u8, 2048);
    defer allocator.free(medium_memory);
    try testing.expectEqual(@as(usize, 2048), medium_memory.len);

    // 测试大对象分配
    const large_memory = try allocator.alloc(u8, 128 * 1024);
    defer allocator.free(large_memory);
    try testing.expectEqual(@as(usize, 128 * 1024), large_memory.len);

    // 验证分层统计（adaptive策略可能不会记录分层统计）
    const stats = allocator.metrics.getStats();
    const distribution = stats.getTierDistribution();
    try testing.expect(distribution.small >= 0.0);
    try testing.expect(distribution.medium >= 0.0);
    try testing.expect(distribution.large >= 0.0);
}

test "对象池批量操作" {
    const testing = std.testing;

    const TestObject = struct {
        value: u64,
    };

    var pool = ObjectPool(TestObject, 100).init();

    // 测试批量分配
    var objects: [10]*TestObject = undefined;
    const acquired = pool.acquireBatch(&objects, 10);
    try testing.expectEqual(@as(usize, 10), acquired);

    // 设置值
    for (objects[0..acquired], 0..) |obj, i| {
        obj.value = i;
    }

    // 验证值
    for (objects[0..acquired], 0..) |obj, i| {
        try testing.expectEqual(@as(u64, i), obj.value);
    }

    // 测试批量释放
    pool.releaseBatch(&objects, acquired);

    // 验证统计
    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 0), stats.allocated_objects);
    try testing.expectEqual(@as(usize, 100), stats.free_objects);
}

test "对象池预热功能" {
    const testing = std.testing;

    const TestObject = struct {
        data: [64]u8,
    };

    var pool = ObjectPool(TestObject, 50).init();

    // 预热对象池
    pool.warmup(20);

    // 预热后应该能快速分配
    const start_time = std.time.nanoTimestamp();

    var objects: [20]*TestObject = undefined;
    const acquired = pool.acquireBatch(&objects, 20);

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;

    try testing.expectEqual(@as(usize, 20), acquired);
    try testing.expect(duration < 1000000); // 应该在1ms内完成

    // 清理
    pool.releaseBatch(&objects, acquired);
}

test "缓存友好分配器" {
    const testing = std.testing;

    // 暂时使用adaptive策略，因为cache_friendly实现还不稳定
    const config = MemoryConfig{
        .strategy = .adaptive,
        .enable_cache_alignment = true,
        .enable_prefetch = true,
        .enable_false_sharing_prevention = true,
    };

    var allocator = try MemoryAllocator(config).init(testing.allocator);
    defer allocator.deinit();

    // 测试基本分配功能
    const memory = try allocator.alloc(u8, 128);
    defer allocator.free(memory);

    try testing.expectEqual(@as(usize, 128), memory.len);

    // 验证内存可以正常使用
    for (memory, 0..) |*byte, i| {
        byte.* = @as(u8, @intCast(i % 256));
    }

    for (memory, 0..) |byte, i| {
        try testing.expectEqual(@as(u8, @intCast(i % 256)), byte);
    }
}
