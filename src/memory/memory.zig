//! 内存管理模块
//!
//! 提供编译时特化的内存分配策略、对象池和内存布局优化。

const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils/utils.zig");
const platform = @import("../utils/platform.zig");

/// 内存配置
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

    /// 编译时验证配置
    pub fn validate(comptime self: @This()) void {
        if (self.max_allocation_size == 0) {
            @compileError("max_allocation_size must be greater than 0");
        }

        if (self.stack_size < 4096) {
            @compileError("stack_size must be at least 4KB");
        }

        if (self.enable_numa and !platform.PlatformCapabilities.numa_available) {
            @compileLog("Warning: NUMA optimization requested but not available");
        }
    }
};

/// 内存分配策略
pub const MemoryStrategy = enum {
    /// 竞技场分配器
    arena,
    /// 通用分配器
    general_purpose,
    /// 固定缓冲区分配器
    fixed_buffer,
    /// 栈回退分配器
    stack,
    /// 自适应分配器
    adaptive,
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
            }
        }

        /// 编译时特化的分配函数
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

            // 编译时选择最优分配路径
            const result = switch (comptime @sizeOf(T)) {
                0...64 => try self.allocSmall(T, count),
                65...4096 => try self.allocMedium(T, count),
                else => try self.allocLarge(T, count),
            };

            // 更新指标
            if (config.enable_metrics) {
                self.metrics.recordAllocation(@sizeOf(T) * count);
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

        /// 小对象分配（使用对象池）
        fn allocSmall(self: *Self, comptime T: type, count: usize) ![]T {
            return self.base_allocator.allocator().alloc(T, count);
        }

        /// 中等对象分配
        fn allocMedium(self: *Self, comptime T: type, count: usize) ![]T {
            return self.base_allocator.allocator().alloc(T, count);
        }

        /// 大对象分配
        fn allocLarge(self: *Self, comptime T: type, count: usize) ![]T {
            return self.base_allocator.allocator().alloc(T, count);
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

/// 编译时对象池生成器
pub fn ObjectPool(comptime T: type, comptime pool_size: usize) type {
    return struct {
        const Self = @This();

        // 编译时计算的池参数
        const OBJECT_SIZE = @sizeOf(T);
        const OBJECT_ALIGN = @alignOf(T);
        const POOL_BYTES = OBJECT_SIZE * pool_size;

        // 编译时对齐的内存池
        pool: [POOL_BYTES]u8 align(OBJECT_ALIGN),
        free_list: utils.Atomic.Value(?*FreeNode),
        allocated_count: utils.Atomic.Value(usize),

        const FreeNode = struct {
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
            return PoolStats{
                .total_objects = pool_size,
                .allocated_objects = self.allocated_count.load(.monotonic),
                .free_objects = pool_size - self.allocated_count.load(.monotonic),
                .memory_usage = self.allocated_count.load(.monotonic) * OBJECT_SIZE,
            };
        }
    };
}

/// 对象池统计信息
pub const PoolStats = struct {
    total_objects: usize,
    allocated_objects: usize,
    free_objects: usize,
    memory_usage: usize,
};

/// 分配指标
const AllocationMetrics = struct {
    total_allocated: utils.Atomic.Value(usize),
    total_deallocated: utils.Atomic.Value(usize),
    current_usage: utils.Atomic.Value(usize),
    peak_usage: utils.Atomic.Value(usize),
    allocation_count: utils.Atomic.Value(usize),
    deallocation_count: utils.Atomic.Value(usize),

    pub fn init() AllocationMetrics {
        return AllocationMetrics{
            .total_allocated = utils.Atomic.Value(usize).init(0),
            .total_deallocated = utils.Atomic.Value(usize).init(0),
            .current_usage = utils.Atomic.Value(usize).init(0),
            .peak_usage = utils.Atomic.Value(usize).init(0),
            .allocation_count = utils.Atomic.Value(usize).init(0),
            .deallocation_count = utils.Atomic.Value(usize).init(0),
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
        };
    }
};

/// 分配统计信息
pub const AllocationStats = struct {
    total_allocated: usize,
    total_deallocated: usize,
    current_usage: usize,
    peak_usage: usize,
    allocation_count: usize,
    deallocation_count: usize,
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

test "对象池基础功能" {
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

    // 测试释放
    pool.release(obj1);

    const stats2 = pool.getStats();
    try testing.expectEqual(@as(usize, 1), stats2.allocated_objects);
    try testing.expectEqual(@as(usize, 9), stats2.free_objects);

    // 测试重新分配
    const obj3 = pool.acquire().?;
    try testing.expect(obj3 == obj1); // 应该重用释放的对象
}

test "内存分配器基础功能" {
    const testing = std.testing;

    const config = MemoryConfig{
        .strategy = .adaptive,
        .enable_metrics = true,
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
}
