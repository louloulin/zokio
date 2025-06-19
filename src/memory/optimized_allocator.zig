//! Zokio 优化内存分配器 v3 - 高性能版本
//!
//! P2阶段性能优化：应用FastSmartAllocator的优化技术
//! 目标：从238K ops/sec提升到5M+ ops/sec

const std = @import("std");
const utils = @import("../utils/utils.zig");

/// 缓存行大小
const CACHE_LINE_SIZE = 64;

/// 🚀 无锁高性能对象池 (P2阶段优化)
pub const LockFreeObjectPool = struct {
    const Self = @This();

    // 对象大小
    object_size: usize,
    // 预分配的内存池
    memory_pool: []u8,
    // 无锁空闲链表头
    free_head: utils.Atomic.Value(?*FreeNode),
    // 基础分配器
    base_allocator: std.mem.Allocator,
    // 原子统计信息
    total_allocated: utils.Atomic.Value(usize),
    total_reused: utils.Atomic.Value(usize),

    const FreeNode = extern struct {
        next: ?*FreeNode,
    };

    pub fn init(base_allocator: std.mem.Allocator, object_size: usize, initial_count: usize) !Self {
        // 确保对象大小至少能容纳FreeNode
        const actual_object_size = @max(object_size, @sizeOf(FreeNode));

        // 分配连续的内存池
        const pool_size = actual_object_size * initial_count;
        const memory_pool = try base_allocator.alloc(u8, pool_size);

        var self = Self{
            .object_size = actual_object_size,
            .memory_pool = memory_pool,
            .free_head = utils.Atomic.Value(?*FreeNode).init(null),
            .base_allocator = base_allocator,
            .total_allocated = utils.Atomic.Value(usize).init(0),
            .total_reused = utils.Atomic.Value(usize).init(0),
        };

        // 初始化无锁空闲链表
        self.initializeFreeList(initial_count);

        return self;
    }

    pub fn deinit(self: *Self) void {
        // 释放内存池
        self.base_allocator.free(self.memory_pool);
    }

    /// 🚀 无锁快速分配
    pub fn alloc(self: *Self) ![]u8 {
        // 无锁CAS操作从空闲链表获取对象
        while (true) {
            const head = self.free_head.load(.acquire) orelse {
                // 空闲链表为空，回退到基础分配器
                _ = self.total_allocated.fetchAdd(1, .monotonic);
                return self.base_allocator.alloc(u8, self.object_size);
            };

            const next = head.next;
            if (self.free_head.cmpxchgWeak(head, next, .acq_rel, .acquire) == null) {
                // 成功获取对象
                _ = self.total_reused.fetchAdd(1, .monotonic);
                return @as([*]u8, @ptrCast(head))[0..self.object_size];
            }
            // CAS失败，重试
        }
    }

    /// 🚀 无锁快速释放
    pub fn free(self: *Self, memory: []u8) void {
        if (memory.len != self.object_size) {
            // 大小不匹配，直接释放
            self.base_allocator.free(memory);
            return;
        }

        // 检查是否来自内存池 - 更安全的检查
        const pool_start = @intFromPtr(self.memory_pool.ptr);
        const pool_end = pool_start + self.memory_pool.len;
        const mem_addr = @intFromPtr(memory.ptr);

        // 检查地址是否在池范围内且对齐正确
        if (mem_addr >= pool_start and mem_addr < pool_end and
            (mem_addr - pool_start) % self.object_size == 0)
        {
            // 来自内存池，放回空闲链表
            const node = @as(*FreeNode, @ptrCast(@alignCast(memory.ptr)));

            while (true) {
                const head = self.free_head.load(.acquire);
                node.next = head;

                if (self.free_head.cmpxchgWeak(head, node, .acq_rel, .acquire) == null) {
                    break;
                }
                // CAS失败，重试
            }
        } else {
            // 不来自内存池，直接释放
            self.base_allocator.free(memory);
        }
    }

    /// 初始化无锁空闲链表
    fn initializeFreeList(self: *Self, count: usize) void {
        // 将内存池分割为对象并构建空闲链表
        var current: ?*FreeNode = null;
        var i: usize = count;

        while (i > 0) {
            i -= 1;
            const offset = i * self.object_size;
            const node = @as(*FreeNode, @ptrCast(@alignCast(self.memory_pool.ptr + offset)));
            node.next = current;
            current = node;
        }

        // 设置链表头
        self.free_head.store(current, .release);
    }

    /// 获取复用率
    pub fn getReuseRate(self: *const Self) f64 {
        const allocated = self.total_allocated.load(.monotonic);
        const reused = self.total_reused.load(.monotonic);
        const total = allocated + reused;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(reused)) / @as(f64, @floatFromInt(total));
    }

    /// 获取统计信息
    pub fn getStats(self: *const Self) PoolStats {
        return PoolStats{
            .total_allocated = self.total_allocated.load(.monotonic),
            .total_reused = self.total_reused.load(.monotonic),
            .reuse_rate = self.getReuseRate(),
            .object_size = self.object_size,
        };
    }
};

/// 🚀 优化的内存分配器 v3 (P2阶段高性能版)
pub const OptimizedAllocator = struct {
    const Self = @This();

    // 小对象池 (8B-256B) - 使用无锁设计
    small_pools: [6]LockFreeObjectPool,
    // 基础分配器
    base_allocator: std.mem.Allocator,

    pub fn init(base_allocator: std.mem.Allocator) !Self {
        var self = Self{
            .small_pools = undefined,
            .base_allocator = base_allocator,
        };

        // 初始化小对象池 - P2阶段优化：增加预分配数量
        const small_sizes = [_]usize{ 8, 16, 32, 64, 128, 256 };
        for (&self.small_pools, 0..) |*pool, i| {
            const size = small_sizes[i];
            const initial_count = 50000; // P2优化：预分配5万个对象，提升性能
            pool.* = try LockFreeObjectPool.init(base_allocator, size, initial_count);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (&self.small_pools) |*pool| {
            pool.deinit();
        }
    }

    pub fn alloc(self: *Self, size: usize) ![]u8 {
        // 选择合适的对象池
        if (size <= 256) {
            const pool_index = self.selectPoolIndex(size);
            return self.small_pools[pool_index].alloc();
        }

        // 大对象直接分配
        return self.base_allocator.alloc(u8, size);
    }

    pub fn free(self: *Self, memory: []u8) void {
        const size = memory.len;

        // 选择合适的对象池
        if (size <= 256) {
            const pool_index = self.selectPoolIndex(size);
            self.small_pools[pool_index].free(memory);
            return;
        }

        // 大对象直接释放
        self.base_allocator.free(memory);
    }

    fn selectPoolIndex(self: *Self, size: usize) usize {
        _ = self;
        // 简单的大小映射
        if (size <= 8) return 0;
        if (size <= 16) return 1;
        if (size <= 32) return 2;
        if (size <= 64) return 3;
        if (size <= 128) return 4;
        return 5; // 256字节
    }

    /// 获取分配器接口
    pub fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = allocFn,
                .resize = resizeFn,
                .free = freeFn,
            },
        };
    }

    /// 获取优化分配器统计信息
    pub fn getStats(self: *const Self) OptimizedStats {
        var stats = OptimizedStats{
            .total_pools = self.small_pools.len,
            .total_allocated = 0,
            .total_reused = 0,
            .reuse_rate = 0.0,
            .pool_stats = undefined,
        };

        // 收集各个池的统计信息
        for (self.small_pools, 0..) |pool, i| {
            const pool_stat = pool.getStats();
            stats.pool_stats[i] = pool_stat;
            stats.total_allocated += pool_stat.total_allocated;
            stats.total_reused += pool_stat.total_reused;
        }

        // 计算总体复用率
        const total = stats.total_allocated + stats.total_reused;
        if (total > 0) {
            stats.reuse_rate = @as(f64, @floatFromInt(stats.total_reused)) / @as(f64, @floatFromInt(total));
        }

        return stats;
    }

    // 分配器接口函数
    fn allocFn(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ptr_align;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        const memory = self.alloc(len) catch return null;
        return memory.ptr;
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // 不支持resize
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.free(buf);
    }
};

/// 对象池统计信息
pub const PoolStats = struct {
    total_allocated: usize,
    total_reused: usize,
    reuse_rate: f64,
    object_size: usize,
};

/// 优化分配器统计信息
pub const OptimizedStats = struct {
    total_pools: usize,
    total_allocated: usize,
    total_reused: usize,
    reuse_rate: f64,
    pool_stats: [6]PoolStats,
};
