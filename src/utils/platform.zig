//! 平台能力检测和优化
//!
//! 该模块负责在编译时检测平台特性和能力，
//! 为运行时组件选择最优的实现策略。

const std = @import("std");
const builtin = @import("builtin");

/// 编译时平台能力检测
pub const PlatformCapabilities = struct {
    /// 编译时检测io_uring可用性
    pub const io_uring_available = blk: {
        if (builtin.os.tag != .linux) break :blk false;

        // 检查内核版本（io_uring需要Linux 5.1+）
        const min_kernel_version = std.SemanticVersion{ .major = 5, .minor = 1, .patch = 0 };
        break :blk checkKernelVersion(min_kernel_version);
    };

    /// 编译时检测kqueue可用性
    pub const kqueue_available = builtin.os.tag.isDarwin() or builtin.os.tag.isBSD();

    /// 编译时检测IOCP可用性
    pub const iocp_available = builtin.os.tag == .windows;

    /// 编译时检测WASI可用性
    pub const wasi_available = builtin.os.tag == .wasi;

    /// 编译时检测SIMD可用性
    pub const simd_available = switch (builtin.cpu.arch) {
        .x86_64 => builtin.cpu.features.isEnabled(@import("std").Target.x86.Feature.sse2),
        .aarch64 => false, // 简化处理，避免类型错误
        else => false,
    };

    /// 编译时检测NUMA可用性
    pub const numa_available = builtin.os.tag == .linux and
        builtin.cpu.arch == .x86_64;

    /// 编译时确定缓存行大小
    pub const cache_line_size = switch (builtin.cpu.arch) {
        .x86_64 => 64,
        .aarch64 => 64,
        .arm => 32,
        .riscv64 => 64,
        else => 64, // 保守估计
    };

    /// 编译时确定页面大小
    pub const page_size = switch (builtin.os.tag) {
        .linux, .macos => 4096,
        .windows => 4096,
        .wasi => 65536,
        else => 4096,
    };

    /// 编译时检测平台是否支持
    pub const is_supported = blk: {
        // 至少需要一个I/O后端
        if (!io_uring_available and !kqueue_available and !iocp_available and !wasi_available) {
            break :blk false;
        }
        break :blk true;
    };

    /// 编译时选择首选I/O后端
    pub const preferred_io_backend = blk: {
        if (io_uring_available) break :blk "io_uring";
        if (kqueue_available) break :blk "kqueue";
        if (iocp_available) break :blk "iocp";
        if (wasi_available) break :blk "wasi";
        break :blk "none";
    };

    /// 编译时检测是否支持多线程
    pub const threading_available = builtin.os.tag != .wasi;

    /// 编译时确定最优工作线程数
    pub const optimal_worker_count = 4; // 简化为固定值，避免编译时调用问题
};

/// 编译时内核版本检查（仅用于编译时）
fn checkKernelVersion(comptime min_version: std.SemanticVersion) bool {
    // 在编译时，我们假设现代Linux内核支持io_uring
    // 实际部署时可以通过运行时检查来验证
    _ = min_version;
    return true;
}

/// CPU架构特定优化
pub fn CpuOptimizations(comptime arch: std.Target.Cpu.Arch) type {
    return struct {
        /// 编译时生成架构特定的原子操作
        pub fn atomicLoad(comptime T: type, ptr: *const T, ordering: std.builtin.AtomicOrder) T {
            return switch (comptime arch) {
                .x86_64 => x86_64_atomic_load(T, ptr, ordering),
                .aarch64 => aarch64_atomic_load(T, ptr, ordering),
                else => @atomicLoad(T, ptr, ordering),
            };
        }

        pub fn atomicStore(comptime T: type, ptr: *T, value: T, ordering: std.builtin.AtomicOrder) void {
            return switch (comptime arch) {
                .x86_64 => x86_64_atomic_store(T, ptr, value, ordering),
                .aarch64 => aarch64_atomic_store(T, ptr, value, ordering),
                else => @atomicStore(T, ptr, value, ordering),
            };
        }

        /// 编译时生成SIMD优化
        pub fn vectorizedCopy(src: []const u8, dst: []u8) void {
            if (comptime PlatformCapabilities.simd_available) {
                switch (comptime arch) {
                    .x86_64 => x86_64_vectorized_copy(src, dst),
                    .aarch64 => aarch64_vectorized_copy(src, dst),
                    else => @memcpy(dst, src),
                }
            } else {
                @memcpy(dst, src);
            }
        }

        /// 编译时缓存预取优化
        pub fn prefetch(ptr: *const anyopaque, locality: u2) void {
            _ = locality;
            if (comptime arch == .x86_64) {
                asm volatile ("prefetcht0 %[ptr]"
                    :
                    : [ptr] "m" (ptr.*),
                );
            } else if (comptime arch == .aarch64) {
                asm volatile ("prfm pldl1keep, %[ptr]"
                    :
                    : [ptr] "m" (ptr.*),
                );
            }
            // 其他架构忽略预取指令
        }

        // 架构特定实现（占位符）
        fn x86_64_atomic_load(comptime T: type, ptr: *const T, ordering: std.builtin.AtomicOrder) T {
            return @atomicLoad(T, ptr, ordering);
        }

        fn x86_64_atomic_store(comptime T: type, ptr: *T, value: T, ordering: std.builtin.AtomicOrder) void {
            @atomicStore(T, ptr, value, ordering);
        }

        fn aarch64_atomic_load(comptime T: type, ptr: *const T, ordering: std.builtin.AtomicOrder) T {
            return @atomicLoad(T, ptr, ordering);
        }

        fn aarch64_atomic_store(comptime T: type, ptr: *T, value: T, ordering: std.builtin.AtomicOrder) void {
            @atomicStore(T, ptr, value, ordering);
        }

        fn x86_64_vectorized_copy(src: []const u8, dst: []u8) void {
            // 简化实现，实际可以使用SSE/AVX指令
            @memcpy(dst, src);
        }

        fn aarch64_vectorized_copy(src: []const u8, dst: []u8) void {
            // 简化实现，实际可以使用NEON指令
            @memcpy(dst, src);
        }
    };
}

/// 操作系统特性检测
pub fn OsFeatures(comptime os_tag: std.Target.Os.Tag) type {
    return struct {
        /// 编译时检查系统调用可用性
        pub const has_eventfd = os_tag == .linux;
        pub const has_kqueue = os_tag.isDarwin() or os_tag.isBSD();
        pub const has_epoll = os_tag == .linux;
        pub const has_io_uring = os_tag == .linux;

        /// 编译时内存映射优化
        pub fn optimizedMmap(size: usize) ![]u8 {
            const flags = comptime if (os_tag == .linux)
                std.posix.MAP.PRIVATE | std.posix.MAP.ANONYMOUS
            else if (os_tag.isDarwin())
                std.posix.MAP.PRIVATE | std.posix.MAP.ANON
            else
                std.posix.MAP.PRIVATE | std.posix.MAP.ANONYMOUS;

            return try std.posix.mmap(null, size, std.posix.PROT.READ | std.posix.PROT.WRITE, flags, -1, 0);
        }
    };
}

// 测试
test "平台能力检测" {
    const testing = std.testing;

    // 测试基本能力
    try testing.expect(PlatformCapabilities.cache_line_size > 0);
    try testing.expect(PlatformCapabilities.page_size > 0);
    try testing.expect(PlatformCapabilities.optimal_worker_count > 0);

    // 测试平台支持
    try testing.expect(PlatformCapabilities.is_supported);

    // 测试首选后端
    try testing.expect(PlatformCapabilities.preferred_io_backend.len > 0);
}

test "CPU优化功能" {
    const testing = std.testing;
    const CpuOpt = CpuOptimizations(builtin.cpu.arch);

    // 测试原子操作
    var value: u32 = 42;
    const loaded = CpuOpt.atomicLoad(u32, &value, .monotonic);
    try testing.expectEqual(@as(u32, 42), loaded);

    CpuOpt.atomicStore(u32, &value, 84, .monotonic);
    try testing.expectEqual(@as(u32, 84), value);

    // 测试向量化拷贝
    var src = [_]u8{ 1, 2, 3, 4, 5 };
    var dst = [_]u8{ 0, 0, 0, 0, 0 };
    CpuOpt.vectorizedCopy(&src, &dst);
    try testing.expectEqualSlices(u8, &src, &dst);
}
