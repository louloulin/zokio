//! 🧪 实验性 NUMA 感知模块
//! 
//! 提供 NUMA 拓扑感知的实验性功能

const std = @import("std");

/// NUMA 节点信息
pub const NumaNode = struct {
    id: u32,
    cpu_count: u32,
    memory_size: u64,
    
    pub fn init(id: u32) NumaNode {
        return NumaNode{
            .id = id,
            .cpu_count = std.Thread.getCpuCount() catch 1,
            .memory_size = 1024 * 1024 * 1024, // 1GB 默认
        };
    }
};

/// NUMA 感知分配器
pub const NumaAllocator = struct {
    node: NumaNode,
    base_allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, node_id: u32) NumaAllocator {
        return NumaAllocator{
            .node = NumaNode.init(node_id),
            .base_allocator = allocator,
        };
    }
    
    pub fn alloc(self: *NumaAllocator, comptime T: type, n: usize) ![]T {
        // 简化实现：使用基础分配器
        return self.base_allocator.alloc(T, n);
    }
    
    pub fn free(self: *NumaAllocator, memory: anytype) void {
        self.base_allocator.free(memory);
    }
};

test "NUMA 基础功能" {
    const testing = std.testing;
    
    var numa_alloc = NumaAllocator.init(testing.allocator, 0);
    
    const memory = try numa_alloc.alloc(u32, 100);
    defer numa_alloc.free(memory);
    
    try testing.expect(memory.len == 100);
    try testing.expect(numa_alloc.node.id == 0);
}
