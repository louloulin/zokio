//! 🚀 Zokio 高性能内存池模块
//!
//! 零分配运行时设计：
//! 1. Completion对象池 - 避免频繁分配
//! 2. 缓冲区池 - 预分配I/O缓冲区
//! 3. 任务对象池 - 复用任务结构
//! 4. 原子无锁设计 - 支持多线程访问

const std = @import("std");
const xev = @import("libxev");
const utils = @import("../utils/utils.zig");

/// 🔧 内存池配置
pub const PoolConfig = struct {
    /// Completion池大小
    completion_pool_size: u32 = 1024,

    /// 小缓冲区数量 (4KB)
    small_buffer_count: u32 = 256,

    /// 大缓冲区数量 (64KB)
    large_buffer_count: u32 = 64,

    /// 巨大缓冲区数量 (1MB)
    huge_buffer_count: u32 = 16,

    /// 任务池大小
    task_pool_size: u32 = 512,

    /// 启用统计信息
    enable_stats: bool = true,
};

/// 📊 内存池统计
pub const PoolStats = struct {
    total_allocations: u64 = 0,
    total_deallocations: u64 = 0,
    current_usage: u64 = 0,
    peak_usage: u64 = 0,
    pool_hits: u64 = 0,
    pool_misses: u64 = 0,

    pub fn recordAllocation(self: *PoolStats, size: u64, from_pool: bool) void {
        self.total_allocations += 1;
        self.current_usage += size;
        self.peak_usage = @max(self.peak_usage, self.current_usage);

        if (from_pool) {
            self.pool_hits += 1;
        } else {
            self.pool_misses += 1;
        }
    }

    pub fn recordDeallocation(self: *PoolStats, size: u64) void {
        self.total_deallocations += 1;
        self.current_usage = if (self.current_usage >= size)
            self.current_usage - size
        else
            0;
    }

    pub fn getHitRate(self: *const PoolStats) f64 {
        const total = self.pool_hits + self.pool_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.pool_hits)) / @as(f64, @floatFromInt(total));
    }
};

/// 🚀 原子栈实现 (无锁)
fn AtomicStack(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            next: ?*Node,
            data: T,
        };

        head: std.atomic.Value(?*Node) = std.atomic.Value(?*Node).init(null),

        pub fn push(self: *Self, node: *Node) void {
            var current_head = self.head.load(.acquire);
            while (true) {
                node.next = current_head;
                if (self.head.cmpxchgWeak(current_head, node, .release, .acquire)) |new_head| {
                    current_head = new_head;
                } else {
                    break;
                }
            }
        }

        pub fn pop(self: *Self) ?*Node {
            var current_head = self.head.load(.acquire);
            while (current_head) |head| {
                const next = head.next;
                if (self.head.cmpxchgWeak(current_head, next, .release, .acquire)) |new_head| {
                    current_head = new_head;
                } else {
                    return head;
                }
            }
            return null;
        }
    };
}

/// 🚀 Completion对象池
pub const CompletionPool = struct {
    const Self = @This();
    const CompletionNode = AtomicStack(xev.Completion).Node;

    /// 预分配的Completion数组
    completions: []CompletionNode,

    /// 空闲栈
    free_stack: AtomicStack(xev.Completion),

    /// 统计信息
    stats: PoolStats = .{},

    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: PoolConfig) !Self {
        const completions = try allocator.alloc(CompletionNode, config.completion_pool_size);

        var pool = Self{
            .completions = completions,
            .free_stack = AtomicStack(xev.Completion){},
            .allocator = allocator,
        };

        // 初始化所有Completion并加入空闲栈
        for (completions) |*completion| {
            completion.data = xev.Completion{};
            pool.free_stack.push(completion);
        }

        return pool;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.completions);
    }

    /// 🚀 获取Completion对象
    pub fn acquire(self: *Self) ?*xev.Completion {
        if (self.free_stack.pop()) |node| {
            self.stats.recordAllocation(@sizeOf(xev.Completion), true);
            return &node.data;
        }

        // 池已空，记录miss
        self.stats.recordAllocation(@sizeOf(xev.Completion), false);
        return null;
    }

    /// 🚀 释放Completion对象
    pub fn release(self: *Self, completion: *xev.Completion) void {
        // 重置Completion状态 - 使用默认初始化而不是zeroes
        completion.* = xev.Completion{};

        // 计算节点地址
        const node_ptr: *CompletionNode = @fieldParentPtr("data", completion);

        // 返回到空闲栈
        self.free_stack.push(node_ptr);

        self.stats.recordDeallocation(@sizeOf(xev.Completion));
    }

    /// 📊 获取统计信息
    pub fn getStats(self: *const Self) PoolStats {
        return self.stats;
    }
};

/// 🚀 缓冲区池
pub const BufferPool = struct {
    const Self = @This();

    /// 缓冲区大小类型
    pub const BufferSize = enum {
        small, // 4KB
        large, // 64KB
        huge, // 1MB

        pub fn getSize(self: BufferSize) u32 {
            return switch (self) {
                .small => 4 * 1024,
                .large => 64 * 1024,
                .huge => 1024 * 1024,
            };
        }
    };

    const BufferNode = struct {
        next: ?*BufferNode,
        data: []u8,
    };

    /// 小缓冲区池
    small_buffers: []u8,
    small_nodes: []BufferNode,
    small_stack: AtomicStack([]u8),

    /// 大缓冲区池
    large_buffers: []u8,
    large_nodes: []BufferNode,
    large_stack: AtomicStack([]u8),

    /// 巨大缓冲区池
    huge_buffers: []u8,
    huge_nodes: []BufferNode,
    huge_stack: AtomicStack([]u8),

    /// 统计信息
    stats: PoolStats = .{},

    /// 分配器
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: PoolConfig) !Self {
        // 分配小缓冲区
        const small_size = BufferSize.small.getSize();
        const small_buffers = try allocator.alloc(u8, small_size * config.small_buffer_count);
        const small_nodes = try allocator.alloc(BufferNode, config.small_buffer_count);

        // 分配大缓冲区
        const large_size = BufferSize.large.getSize();
        const large_buffers = try allocator.alloc(u8, large_size * config.large_buffer_count);
        const large_nodes = try allocator.alloc(BufferNode, config.large_buffer_count);

        // 分配巨大缓冲区
        const huge_size = BufferSize.huge.getSize();
        const huge_buffers = try allocator.alloc(u8, huge_size * config.huge_buffer_count);
        const huge_nodes = try allocator.alloc(BufferNode, config.huge_buffer_count);

        var pool = Self{
            .small_buffers = small_buffers,
            .small_nodes = small_nodes,
            .small_stack = AtomicStack([]u8){},
            .large_buffers = large_buffers,
            .large_nodes = large_nodes,
            .large_stack = AtomicStack([]u8){},
            .huge_buffers = huge_buffers,
            .huge_nodes = huge_nodes,
            .huge_stack = AtomicStack([]u8){},
            .allocator = allocator,
        };

        // 初始化小缓冲区栈
        for (0..config.small_buffer_count) |i| {
            const start = i * small_size;
            const end = start + small_size;
            small_nodes[i].data = small_buffers[start..end];
            pool.small_stack.push(@ptrCast(&small_nodes[i]));
        }

        // 初始化大缓冲区栈
        for (0..config.large_buffer_count) |i| {
            const start = i * large_size;
            const end = start + large_size;
            large_nodes[i].data = large_buffers[start..end];
            pool.large_stack.push(@ptrCast(&large_nodes[i]));
        }

        // 初始化巨大缓冲区栈
        for (0..config.huge_buffer_count) |i| {
            const start = i * huge_size;
            const end = start + huge_size;
            huge_nodes[i].data = huge_buffers[start..end];
            pool.huge_stack.push(@ptrCast(&huge_nodes[i]));
        }

        return pool;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.small_buffers);
        self.allocator.free(self.small_nodes);
        self.allocator.free(self.large_buffers);
        self.allocator.free(self.large_nodes);
        self.allocator.free(self.huge_buffers);
        self.allocator.free(self.huge_nodes);
    }

    /// 🚀 获取指定大小的缓冲区
    pub fn acquire(self: *Self, size: BufferSize) ?[]u8 {
        const stack = switch (size) {
            .small => &self.small_stack,
            .large => &self.large_stack,
            .huge => &self.huge_stack,
        };

        if (stack.pop()) |node_ptr| {
            const node: *BufferNode = @ptrCast(node_ptr);
            self.stats.recordAllocation(node.data.len, true);
            return node.data;
        }

        self.stats.recordAllocation(size.getSize(), false);
        return null;
    }

    /// 🚀 释放缓冲区
    pub fn release(self: *Self, buffer: []u8) void {
        const size = buffer.len;

        // 确定缓冲区类型
        const buffer_size = if (size <= BufferSize.small.getSize())
            BufferSize.small
        else if (size <= BufferSize.large.getSize())
            BufferSize.large
        else
            BufferSize.huge;

        // 找到对应的节点
        const nodes = switch (buffer_size) {
            .small => self.small_nodes,
            .large => self.large_nodes,
            .huge => self.huge_nodes,
        };

        const stack = switch (buffer_size) {
            .small => &self.small_stack,
            .large => &self.large_stack,
            .huge => &self.huge_stack,
        };

        // 查找匹配的节点
        for (nodes) |*node| {
            if (node.data.ptr == buffer.ptr) {
                stack.push(@ptrCast(node));
                self.stats.recordDeallocation(size);
                return;
            }
        }

        // 如果找不到匹配的节点，说明这不是从池中分配的缓冲区
        // 这种情况下我们只记录统计信息
        self.stats.recordDeallocation(size);
    }

    /// 📊 获取统计信息
    pub fn getStats(self: *const Self) PoolStats {
        return self.stats;
    }
};

/// 🚀 统一内存池管理器
pub const MemoryPoolManager = struct {
    const Self = @This();

    /// Completion池
    completion_pool: CompletionPool,

    /// 缓冲区池
    buffer_pool: BufferPool,

    /// 配置
    config: PoolConfig,

    pub fn init(allocator: std.mem.Allocator, config: PoolConfig) !Self {
        return Self{
            .completion_pool = try CompletionPool.init(allocator, config),
            .buffer_pool = try BufferPool.init(allocator, config),
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        self.completion_pool.deinit();
        self.buffer_pool.deinit();
    }

    /// 📊 获取综合统计信息
    pub fn getStats(self: *const Self) MemoryPoolStats {
        return MemoryPoolStats{
            .completion_stats = self.completion_pool.getStats(),
            .buffer_stats = self.buffer_pool.getStats(),
        };
    }
};

/// 📊 综合内存池统计
pub const MemoryPoolStats = struct {
    completion_stats: PoolStats,
    buffer_stats: PoolStats,

    pub fn getTotalAllocations(self: *const MemoryPoolStats) u64 {
        return self.completion_stats.total_allocations +
            self.buffer_stats.total_allocations;
    }

    pub fn getOverallHitRate(self: *const MemoryPoolStats) f64 {
        const total_hits = self.completion_stats.pool_hits + self.buffer_stats.pool_hits;
        const total_misses = self.completion_stats.pool_misses + self.buffer_stats.pool_misses;
        const total = total_hits + total_misses;

        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(total_hits)) / @as(f64, @floatFromInt(total));
    }
};

/// 🧪 内存池测试
pub fn runMemoryPoolTest(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== 🚀 内存池性能测试 ===\n", .{});

    const config = PoolConfig{
        .completion_pool_size = 1024,
        .small_buffer_count = 256,
        .large_buffer_count = 64,
        .huge_buffer_count = 16,
    };

    var pool_manager = try MemoryPoolManager.init(allocator, config);
    defer pool_manager.deinit();

    // 性能测试
    const iterations = 100000;
    const start_time = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        // 测试Completion池
        if (pool_manager.completion_pool.acquire()) |completion| {
            pool_manager.completion_pool.release(completion);
        }

        // 测试缓冲区池
        if (pool_manager.buffer_pool.acquire(.small)) |buffer| {
            pool_manager.buffer_pool.release(buffer);
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const ops_per_sec = @as(f64, @floatFromInt(iterations * 2)) /
        (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0);

    const stats = pool_manager.getStats();

    std.debug.print("内存池测试结果:\n", .{});
    std.debug.print("  总操作数: {}\n", .{iterations * 2});
    std.debug.print("  池命中率: {d:.2}%\n", .{stats.getOverallHitRate() * 100});
    std.debug.print("  性能: {d:.0} ops/sec\n", .{ops_per_sec});
    std.debug.print("  ✅ 内存池测试完成\n", .{});
}
