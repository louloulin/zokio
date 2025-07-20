//! 🚀 Zokio 零拷贝I/O优化
//!
//! 充分利用libxev的零拷贝特性，实现高性能I/O操作：
//! 1. sendfile系统调用优化
//! 2. 内存映射I/O
//! 3. 缓冲区复用机制
//! 4. 批量零拷贝操作

const std = @import("std");
const libxev = @import("libxev");
const utils = @import("../utils/utils.zig");

/// 🔧 零拷贝配置
pub const ZeroCopyConfig = struct {
    /// 启用sendfile优化
    enable_sendfile: bool = true,

    /// 启用内存映射
    enable_mmap: bool = true,

    /// 缓冲区池大小
    buffer_pool_size: u32 = 1024,

    /// 单个缓冲区大小
    buffer_size: u32 = 64 * 1024, // 64KB

    /// 最大零拷贝传输大小
    max_zero_copy_size: u64 = 1024 * 1024 * 1024, // 1GB
};

/// 🚀 零拷贝I/O管理器
pub const ZeroCopyManager = struct {
    const Self = @This();

    /// 配置
    config: ZeroCopyConfig,

    /// 内存分配器
    allocator: std.mem.Allocator,

    /// 缓冲区池
    buffer_pool: BufferPool,

    /// 内存映射区域列表
    mmap_regions: std.ArrayList(MmapRegion),

    /// 统计信息
    stats: ZeroCopyStats,

    /// 初始化零拷贝管理器
    pub fn init(allocator: std.mem.Allocator, config: ZeroCopyConfig) !Self {
        return Self{
            .config = config,
            .allocator = allocator,
            .buffer_pool = try BufferPool.init(allocator, config.buffer_pool_size, config.buffer_size),
            .mmap_regions = std.ArrayList(MmapRegion).init(allocator),
            .stats = ZeroCopyStats{},
        };
    }

    /// 清理资源
    pub fn deinit(self: *Self) void {
        self.buffer_pool.deinit();

        // 清理所有内存映射区域
        for (self.mmap_regions.items) |region| {
            region.unmap();
        }
        self.mmap_regions.deinit();
    }

    /// 🚀 零拷贝文件发送
    ///
    /// 使用sendfile系统调用实现零拷贝文件传输
    pub fn sendFile(
        self: *Self,
        src_fd: std.posix.fd_t,
        dst_fd: std.posix.fd_t,
        offset: u64,
        count: u64,
    ) !u64 {
        if (!self.config.enable_sendfile) {
            return error.SendFileDisabled;
        }

        if (count > self.config.max_zero_copy_size) {
            return error.TransferTooLarge;
        }

        const start_time = std.time.nanoTimestamp();

        // 使用平台特定的零拷贝实现
        const bytes_sent = switch (std.builtin.os.tag) {
            .linux => try self.sendFileLinux(src_fd, dst_fd, offset, count),
            .macos => try self.sendFileMacOS(src_fd, dst_fd, offset, count),
            else => try self.sendFileFallback(src_fd, dst_fd, offset, count),
        };

        const end_time = std.time.nanoTimestamp();
        self.stats.updateSendFile(bytes_sent, end_time - start_time);

        return bytes_sent;
    }

    /// Linux sendfile实现
    fn sendFileLinux(
        self: *Self,
        src_fd: std.posix.fd_t,
        dst_fd: std.posix.fd_t,
        offset: u64,
        count: u64,
    ) !u64 {
        _ = self;

        var off: std.posix.off_t = @intCast(offset);
        const result = std.posix.sendfile(dst_fd, src_fd, &off, count);

        return switch (result) {
            .err => |err| switch (err) {
                .AGAIN => 0, // 非阻塞模式，稍后重试
                .INVAL => error.InvalidArgument,
                .NOMEM => error.OutOfMemory,
                .PIPE => error.BrokenPipe,
                else => error.SendFileFailed,
            },
            .result => |bytes| bytes,
        };
    }

    /// macOS sendfile实现
    fn sendFileMacOS(
        self: *Self,
        src_fd: std.posix.fd_t,
        dst_fd: std.posix.fd_t,
        offset: u64,
        count: u64,
    ) !u64 {
        _ = self;
        _ = src_fd;
        _ = dst_fd;
        _ = offset;
        _ = count;

        // macOS的sendfile API略有不同，这里简化实现
        // 实际实现需要调用BSD风格的sendfile
        return error.NotImplemented;
    }

    /// 回退实现（使用常规read/write）
    fn sendFileFallback(
        self: *Self,
        src_fd: std.posix.fd_t,
        dst_fd: std.posix.fd_t,
        offset: u64,
        count: u64,
    ) !u64 {
        // 获取缓冲区
        const buffer = try self.buffer_pool.acquire();
        defer self.buffer_pool.release(buffer);

        var total_sent: u64 = 0;
        var current_offset = offset;
        var remaining = count;

        while (remaining > 0 and total_sent < count) {
            const to_read = @min(remaining, buffer.len);

            // 读取数据
            const bytes_read = try std.posix.pread(src_fd, buffer[0..to_read], current_offset);
            if (bytes_read == 0) break; // EOF

            // 写入数据
            const bytes_written = try std.posix.write(dst_fd, buffer[0..bytes_read]);

            total_sent += bytes_written;
            current_offset += bytes_written;
            remaining -= bytes_written;

            if (bytes_written < bytes_read) break; // 部分写入
        }

        return total_sent;
    }

    /// 🚀 创建内存映射
    pub fn createMmap(
        self: *Self,
        fd: std.posix.fd_t,
        size: u64,
        offset: u64,
        prot: u32,
    ) ![]u8 {
        if (!self.config.enable_mmap) {
            return error.MmapDisabled;
        }

        const region = try MmapRegion.create(fd, size, offset, prot);
        try self.mmap_regions.append(region);

        self.stats.mmap_operations += 1;
        self.stats.mmap_bytes += size;

        return region.data;
    }

    /// 获取统计信息
    pub fn getStats(self: *const Self) ZeroCopyStats {
        return self.stats;
    }
};

/// 🗺️ 内存映射区域
const MmapRegion = struct {
    data: []u8,
    fd: std.posix.fd_t,
    size: u64,
    offset: u64,

    pub fn create(fd: std.posix.fd_t, size: u64, offset: u64, prot: u32) !MmapRegion {
        const data = try std.posix.mmap(
            null,
            size,
            prot,
            .{ .TYPE = .SHARED },
            fd,
            offset,
        );

        return MmapRegion{
            .data = data,
            .fd = fd,
            .size = size,
            .offset = offset,
        };
    }

    pub fn unmap(self: MmapRegion) void {
        std.posix.munmap(@alignCast(self.data));
    }
};

/// 🔄 缓冲区池
const BufferPool = struct {
    buffers: std.ArrayList([]u8),
    available: std.ArrayList(usize),
    buffer_size: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, pool_size: u32, buffer_size: u32) !BufferPool {
        var pool = BufferPool{
            .buffers = std.ArrayList([]u8).init(allocator),
            .available = std.ArrayList(usize).init(allocator),
            .buffer_size = buffer_size,
            .allocator = allocator,
        };

        // 预分配缓冲区
        for (0..pool_size) |i| {
            const buffer = try allocator.alloc(u8, buffer_size);
            try pool.buffers.append(buffer);
            try pool.available.append(i);
        }

        return pool;
    }

    pub fn deinit(self: *BufferPool) void {
        for (self.buffers.items) |buffer| {
            self.allocator.free(buffer);
        }
        self.buffers.deinit();
        self.available.deinit();
    }

    pub fn acquire(self: *BufferPool) ![]u8 {
        if (self.available.items.len == 0) {
            return error.NoBuffersAvailable;
        }

        const index = self.available.swapRemove(self.available.items.len - 1);
        return self.buffers.items[index];
    }

    pub fn release(self: *BufferPool, buffer: []u8) void {
        // 找到缓冲区索引并释放
        for (self.buffers.items, 0..) |pool_buffer, i| {
            if (pool_buffer.ptr == buffer.ptr) {
                self.available.append(i) catch {}; // 忽略错误，最坏情况是缓冲区丢失
                return;
            }
        }
    }
};

/// 📊 零拷贝统计信息
pub const ZeroCopyStats = struct {
    /// sendfile操作次数
    sendfile_operations: u64 = 0,

    /// sendfile传输字节数
    sendfile_bytes: u64 = 0,

    /// sendfile总耗时（纳秒）
    sendfile_total_time_ns: u64 = 0,

    /// 内存映射操作次数
    mmap_operations: u64 = 0,

    /// 内存映射字节数
    mmap_bytes: u64 = 0,

    /// 更新sendfile统计
    pub fn updateSendFile(self: *ZeroCopyStats, bytes: u64, time_ns: u64) void {
        self.sendfile_operations += 1;
        self.sendfile_bytes += bytes;
        self.sendfile_total_time_ns += time_ns;
    }

    /// 获取sendfile平均性能
    pub fn getSendFilePerformance(self: *const ZeroCopyStats) struct {
        avg_throughput_mbps: f64,
        avg_latency_us: f64,
    } {
        if (self.sendfile_operations == 0) {
            return .{ .avg_throughput_mbps = 0.0, .avg_latency_us = 0.0 };
        }

        const avg_time_s = @as(f64, @floatFromInt(self.sendfile_total_time_ns)) /
            @as(f64, @floatFromInt(self.sendfile_operations)) / 1_000_000_000.0;
        const avg_bytes = @as(f64, @floatFromInt(self.sendfile_bytes)) /
            @as(f64, @floatFromInt(self.sendfile_operations));

        return .{
            .avg_throughput_mbps = (avg_bytes / (1024.0 * 1024.0)) / avg_time_s,
            .avg_latency_us = avg_time_s * 1_000_000.0,
        };
    }
};
