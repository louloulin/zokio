//! Zokio 优化内存分配器 v2
//!
//! 基于第一次测试的发现，实现真正的高性能对象池

const std = @import("std");
const utils = @import("../utils/utils.zig");

/// 缓存行大小
const CACHE_LINE_SIZE = 64;

/// 高性能对象池
pub const HighPerformanceObjectPool = struct {
    const Self = @This();
    
    // 对象大小
    object_size: usize,
    // 预分配的内存块
    memory_chunks: std.ArrayList([]u8),
    // 空闲对象栈
    free_objects: std.ArrayList(*anyopaque),
    // 基础分配器
    base_allocator: std.mem.Allocator,
    // 统计信息
    total_allocated: usize,
    total_reused: usize,
    
    pub fn init(base_allocator: std.mem.Allocator, object_size: usize, initial_count: usize) !Self {
        var self = Self{
            .object_size = object_size,
            .memory_chunks = std.ArrayList([]u8).init(base_allocator),
            .free_objects = std.ArrayList(*anyopaque).init(base_allocator),
            .base_allocator = base_allocator,
            .total_allocated = 0,
            .total_reused = 0,
        };
        
        // 预分配对象
        try self.preallocateObjects(initial_count);
        
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        // 释放所有内存块
        for (self.memory_chunks.items) |chunk| {
            self.base_allocator.free(chunk);
        }
        self.memory_chunks.deinit();
        self.free_objects.deinit();
    }
    
    pub fn alloc(self: *Self) ![]u8 {
        // 尝试从空闲列表获取
        if (self.free_objects.items.len > 0) {
            const ptr = self.free_objects.pop();
            self.total_reused += 1;
            return @as([*]u8, @ptrCast(ptr))[0..self.object_size];
        }
        
        // 分配新对象
        const memory = try self.base_allocator.alloc(u8, self.object_size);
        self.total_allocated += 1;
        return memory;
    }
    
    pub fn free(self: *Self, memory: []u8) void {
        if (memory.len != self.object_size) return;
        
        // 将对象放回空闲列表
        const ptr = @as(*anyopaque, @ptrCast(memory.ptr));
        self.free_objects.append(ptr) catch {
            // 如果无法放回列表，直接释放
            self.base_allocator.free(memory);
        };
    }
    
    fn preallocateObjects(self: *Self, count: usize) !void {
        // 批量分配内存块
        const chunk_size = self.object_size * count;
        const chunk = try self.base_allocator.alloc(u8, chunk_size);
        try self.memory_chunks.append(chunk);
        
        // 将内存块分割为对象并加入空闲列表
        var i: usize = 0;
        while (i < count) {
            const offset = i * self.object_size;
            const ptr = @as(*anyopaque, @ptrCast(chunk.ptr + offset));
            try self.free_objects.append(ptr);
            i += 1;
        }
    }
    
    pub fn getReuseRate(self: *const Self) f64 {
        const total = self.total_allocated + self.total_reused;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_reused)) / @as(f64, @floatFromInt(total));
    }
};

/// 优化的内存分配器
pub const OptimizedAllocator = struct {
    const Self = @This();
    
    // 小对象池 (8B-256B)
    small_pools: [6]HighPerformanceObjectPool,
    // 基础分配器
    base_allocator: std.mem.Allocator,
    
    pub fn init(base_allocator: std.mem.Allocator) !Self {
        var self = Self{
            .small_pools = undefined,
            .base_allocator = base_allocator,
        };
        
        // 初始化小对象池
        const small_sizes = [_]usize{ 8, 16, 32, 64, 128, 256 };
        for (&self.small_pools, 0..) |*pool, i| {
            const size = small_sizes[i];
            const initial_count = 10000; // 预分配1万个对象
            pool.* = try HighPerformanceObjectPool.init(base_allocator, size, initial_count);
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
    
    pub fn getStats(self: *const Self) AllocationStats {
        var stats = AllocationStats{
            .total_pools = self.small_pools.len,
            .total_allocated = 0,
            .total_reused = 0,
            .reuse_rate = 0.0,
        };
        
        for (self.small_pools) |pool| {
            stats.total_allocated += pool.total_allocated;
            stats.total_reused += pool.total_reused;
        }
        
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

pub const AllocationStats = struct {
    total_pools: usize,
    total_allocated: usize,
    total_reused: usize,
    reuse_rate: f64,
};
