//! 🛡️ Zokio RAII 资源管理系统
//!
//! 提供自动资源管理，确保资源在任何情况下都能正确释放：
//! - 自动内存管理
//! - 文件句柄管理
//! - 网络连接管理
//! - 线程资源管理
//! - 异常安全保证

const std = @import("std");
const ZokioError = @import("zokio_error.zig").ZokioError;

/// 🔧 资源管理器接口
pub const ResourceManager = struct {
    /// 资源清理函数类型
    pub const CleanupFn = *const fn (resource: *anyopaque) void;

    /// 资源项
    const ResourceItem = struct {
        resource: *anyopaque,
        cleanup_fn: CleanupFn,
        name: []const u8,
        allocated_at: std.builtin.SourceLocation,
    };

    resources: std.ArrayList(ResourceItem),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    /// 🚀 初始化资源管理器
    pub fn init(allocator: std.mem.Allocator) ResourceManager {
        return ResourceManager{
            .resources = std.ArrayList(ResourceItem).init(allocator),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    /// 🧹 清理所有资源
    pub fn deinit(self: *ResourceManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 按照注册的逆序清理资源（LIFO）
        while (self.resources.items.len > 0) {
            const last_index = self.resources.items.len - 1;
            const item = self.resources.items[last_index];
            std.log.debug("清理资源: {s} (注册位置: {s}:{})", .{ item.name, item.allocated_at.file, item.allocated_at.line });
            item.cleanup_fn(item.resource);
            _ = self.resources.pop();
        }

        self.resources.deinit();
    }

    /// 📝 注册资源
    pub fn registerResource(
        self: *ResourceManager,
        resource: anytype,
        cleanup_fn: CleanupFn,
        name: []const u8,
        source: std.builtin.SourceLocation,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const item = ResourceItem{
            .resource = @ptrCast(resource),
            .cleanup_fn = cleanup_fn,
            .name = name,
            .allocated_at = source,
        };

        try self.resources.append(item);
        std.log.debug("注册资源: {s} (位置: {s}:{})", .{ name, source.file, source.line });
    }

    /// 🗑️ 手动释放特定资源
    pub fn releaseResource(self: *ResourceManager, resource: *anyopaque) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.resources.items, 0..) |item, i| {
            if (item.resource == resource) {
                std.log.debug("手动释放资源: {s}", .{item.name});
                item.cleanup_fn(item.resource);
                _ = self.resources.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// 📊 获取资源统计信息
    pub fn getStats(self: *ResourceManager) ResourceStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        return ResourceStats{
            .total_resources = self.resources.items.len,
            .memory_usage = self.resources.capacity * @sizeOf(ResourceItem),
        };
    }
};

/// 📊 资源统计信息
pub const ResourceStats = struct {
    total_resources: usize,
    memory_usage: usize,
};

/// 🛡️ RAII 包装器 - 自动管理单个资源
pub fn RAIIWrapper(comptime T: type) type {
    return struct {
        const Self = @This();

        resource: ?T,
        cleanup_fn: ?*const fn (*T) void,
        name: []const u8,

        /// 🚀 创建 RAII 包装器
        pub fn init(resource: T, cleanup_fn: *const fn (*T) void, name: []const u8) Self {
            return Self{
                .resource = resource,
                .cleanup_fn = cleanup_fn,
                .name = name,
            };
        }

        /// 🧹 自动清理
        pub fn deinit(self: *Self) void {
            if (self.resource) |*res| {
                if (self.cleanup_fn) |cleanup| {
                    std.log.debug("RAII 清理资源: {s}", .{self.name});
                    cleanup(res);
                }
                self.resource = null;
            }
        }

        /// 📦 获取资源引用
        pub fn get(self: *Self) ?*T {
            if (self.resource) |*res| {
                return res;
            }
            return null;
        }

        /// 🔓 释放资源所有权（不自动清理）
        pub fn release(self: *Self) ?T {
            const res = self.resource;
            self.resource = null;
            return res;
        }
    };
}

/// 🏗️ 作用域资源管理器 - 自动管理作用域内的所有资源
pub const ScopedResourceManager = struct {
    manager: ResourceManager,

    /// 🚀 初始化作用域资源管理器
    pub fn init(allocator: std.mem.Allocator) ScopedResourceManager {
        return ScopedResourceManager{
            .manager = ResourceManager.init(allocator),
        };
    }

    /// 🧹 自动清理所有资源
    pub fn deinit(self: *ScopedResourceManager) void {
        self.manager.deinit();
    }

    /// 📝 管理资源
    pub fn manage(
        self: *ScopedResourceManager,
        resource: anytype,
        cleanup_fn: ResourceManager.CleanupFn,
        name: []const u8,
    ) !void {
        try self.manager.registerResource(resource, cleanup_fn, name, @src());
    }

    /// 📊 获取统计信息
    pub fn getStats(self: *ScopedResourceManager) ResourceStats {
        return self.manager.getStats();
    }
};

/// 🔧 便捷的资源管理宏
/// 内存分配清理函数
fn cleanupAllocation(resource: *anyopaque) void {
    const allocation: *[]u8 = @ptrCast(@alignCast(resource));
    std.heap.page_allocator.free(allocation.*);
}

/// 文件句柄清理函数
fn cleanupFile(resource: *anyopaque) void {
    const file: *std.fs.File = @ptrCast(@alignCast(resource));
    file.close();
}

/// 线程句柄清理函数
fn cleanupThread(resource: *anyopaque) void {
    const thread: *std.Thread = @ptrCast(@alignCast(resource));
    thread.join();
}

/// 🎯 便捷函数：管理内存分配
pub fn manageAllocation(
    manager: *ResourceManager,
    allocation: []u8,
    name: []const u8,
) !void {
    // 创建堆上的副本来存储分配信息
    const allocation_copy = try manager.allocator.create([]u8);
    allocation_copy.* = allocation;
    try manager.registerResource(allocation_copy, cleanupAllocation, name);
}

/// 🎯 便捷函数：管理文件句柄
pub fn manageFile(
    manager: *ResourceManager,
    file: *std.fs.File,
    name: []const u8,
) !void {
    try manager.registerResource(file, cleanupFile, name);
}

/// 🎯 便捷函数：管理线程
pub fn manageThread(
    manager: *ResourceManager,
    thread: *std.Thread,
    name: []const u8,
) !void {
    try manager.registerResource(thread, cleanupThread, name);
}

// 🧪 测试用例
test "ResourceManager 基本功能" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var manager = ResourceManager.init(allocator);
    defer manager.deinit();

    // 模拟资源
    var test_resource: i32 = 42;

    const TestCleanup = struct {
        fn cleanup(resource: *anyopaque) void {
            const res: *i32 = @ptrCast(@alignCast(resource));
            res.* = 0; // 标记为已清理
        }
    };

    try manager.registerResource(&test_resource, TestCleanup.cleanup, "test_resource", @src());

    const stats = manager.getStats();
    try testing.expect(stats.total_resources == 1);

    // 资源应该在 manager.deinit() 时自动清理
}

test "RAII 包装器" {
    const testing = std.testing;

    const test_value: i32 = 42;

    const TestCleanup = struct {
        fn cleanup(resource: *i32) void {
            resource.* = 0; // 简单的清理操作
        }
    };

    {
        var wrapper = RAIIWrapper(i32).init(test_value, TestCleanup.cleanup, "test_wrapper");
        defer wrapper.deinit();

        try testing.expect(wrapper.get().?.* == 42);
    }

    // 测试通过表示没有崩溃
    try testing.expect(true);
}

test "作用域资源管理器" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var scoped = ScopedResourceManager.init(allocator);
    defer scoped.deinit(); // 自动清理所有资源

    var test_resource: i32 = 42;

    const TestCleanup = struct {
        fn cleanup(resource: *anyopaque) void {
            const res: *i32 = @ptrCast(@alignCast(resource));
            res.* = 0;
        }
    };

    try scoped.manage(&test_resource, TestCleanup.cleanup, "scoped_resource");

    const stats = scoped.getStats();
    try testing.expect(stats.total_resources == 1);
}
