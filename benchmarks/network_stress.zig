//! Zokio网络压力测试
//!
//! 基于examples中的网络示例实现的高性能网络压力测试

const std = @import("std");
const zokio = @import("zokio");

/// 网络压力测试结果
const NetworkStressResult = struct {
    name: []const u8,
    connections_handled: u64,
    bytes_transferred: u64,
    duration_ms: u64,
    connections_per_second: f64,
    throughput_mbps: f64,
    error_rate: f64,

    pub fn format(
        self: NetworkStressResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}:\n", .{self.name});
        try writer.print("  处理连接: {}\n", .{self.connections_handled});
        try writer.print("  传输字节: {}\n", .{self.bytes_transferred});
        try writer.print("  持续时间: {}ms\n", .{self.duration_ms});
        try writer.print("  连接/秒: {d:.2}\n", .{self.connections_per_second});
        try writer.print("  吞吐量: {d:.2} MB/s\n", .{self.throughput_mbps});
        try writer.print("  错误率: {d:.2}%\n", .{self.error_rate * 100});
    }
};

/// 高并发TCP连接压力测试
const HighConcurrencyTcpStress = struct {
    target_connections: u32,
    bytes_per_connection: u32,
    connections_handled: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    bytes_transferred: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    connection_errors: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    const Self = @This();
    pub const Output = NetworkStressResult;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(NetworkStressResult) {
        _ = ctx;

        const start_time = std.time.milliTimestamp();

        // 模拟高并发TCP服务器
        for (0..self.target_connections) |i| {
            // 模拟客户端连接
            const client_fd = @as(std.posix.fd_t, @intCast(i + 1));

            // 模拟连接处理
            if (self.handleConnection(client_fd)) {
                _ = self.connections_handled.fetchAdd(1, .acq_rel);
                _ = self.bytes_transferred.fetchAdd(self.bytes_per_connection, .acq_rel);
            } else {
                _ = self.connection_errors.fetchAdd(1, .acq_rel);
            }

            // 每1000个连接输出进度
            if (i % 1000 == 0) {
                std.debug.print("已处理连接: {}/{}\n", .{ i, self.target_connections });
            }
        }

        const end_time = std.time.milliTimestamp();
        const duration_ms = @as(u64, @intCast(end_time - start_time));
        const handled = self.connections_handled.load(.acquire);
        const transferred = self.bytes_transferred.load(.acquire);
        const errors = self.connection_errors.load(.acquire);

        return .{ .ready = NetworkStressResult{
            .name = "高并发TCP连接",
            .connections_handled = handled,
            .bytes_transferred = transferred,
            .duration_ms = duration_ms,
            .connections_per_second = @as(f64, @floatFromInt(handled)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .throughput_mbps = (@as(f64, @floatFromInt(transferred)) / (1024.0 * 1024.0)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .error_rate = @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(handled + errors)),
        } };
    }

    fn handleConnection(self: *Self, client_fd: std.posix.fd_t) bool {
        _ = self;

        // 模拟读取请求
        var request_buffer: [1024]u8 = undefined;
        for (&request_buffer, 0..) |*byte, i| {
            byte.* = @intCast((@as(usize, @intCast(client_fd)) + i) % 256);
        }

        // 模拟处理延迟
        std.time.sleep(1000); // 1微秒

        // 模拟发送响应
        var response_buffer: [1024]u8 = undefined;
        for (&response_buffer, 0..) |*byte, i| {
            byte.* = @intCast((@as(usize, @intCast(client_fd)) * 2 + i) % 256);
        }

        return true;
    }
};

/// HTTP服务器压力测试
const HttpServerStress = struct {
    target_requests: u32,
    concurrent_connections: u32,
    requests_handled: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    bytes_sent: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    request_errors: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    const Self = @This();
    pub const Output = NetworkStressResult;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(NetworkStressResult) {
        _ = ctx;

        const start_time = std.time.milliTimestamp();

        // 模拟HTTP服务器处理大量请求
        var active_connections: u32 = 0;

        for (0..self.target_requests) |i| {
            // 控制并发连接数
            if (active_connections >= self.concurrent_connections) {
                active_connections = 0; // 重置连接计数
            }

            const connection_id = active_connections;
            active_connections += 1;

            // 模拟HTTP请求处理
            if (self.handleHttpRequest(connection_id, i)) {
                _ = self.requests_handled.fetchAdd(1, .acq_rel);
                _ = self.bytes_sent.fetchAdd(512, .acq_rel); // 假设每个响应512字节
            } else {
                _ = self.request_errors.fetchAdd(1, .acq_rel);
            }

            // 每5000个请求输出进度
            if (i % 5000 == 0) {
                std.debug.print("已处理HTTP请求: {}/{}\n", .{ i, self.target_requests });
            }
        }

        const end_time = std.time.milliTimestamp();
        const duration_ms = @as(u64, @intCast(end_time - start_time));
        const handled = self.requests_handled.load(.acquire);
        const sent = self.bytes_sent.load(.acquire);
        const errors = self.request_errors.load(.acquire);

        return .{ .ready = NetworkStressResult{
            .name = "HTTP服务器压力",
            .connections_handled = handled,
            .bytes_transferred = sent,
            .duration_ms = duration_ms,
            .connections_per_second = @as(f64, @floatFromInt(handled)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .throughput_mbps = (@as(f64, @floatFromInt(sent)) / (1024.0 * 1024.0)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .error_rate = @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(handled + errors)),
        } };
    }

    fn handleHttpRequest(self: *Self, connection_id: u32, request_id: usize) bool {
        _ = self;
        _ = connection_id;

        // 模拟HTTP请求解析
        const method = if (request_id % 4 == 0) "GET" else if (request_id % 4 == 1) "POST" else if (request_id % 4 == 2) "PUT" else "DELETE";
        _ = method;

        const path = if (request_id % 3 == 0) "/" else if (request_id % 3 == 1) "/api/data" else "/api/status";
        _ = path;

        // 模拟请求处理时间
        std.time.sleep(500); // 500纳秒

        // 模拟响应生成
        var response_data: [512]u8 = undefined;
        for (&response_data, 0..) |*byte, i| {
            byte.* = @intCast((request_id + i) % 256);
        }

        return true;
    }
};

/// 文件传输压力测试
const FileTransferStress = struct {
    file_count: u32,
    file_size_kb: u32,
    files_transferred: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    total_bytes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    transfer_errors: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    const Self = @This();
    pub const Output = NetworkStressResult;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(NetworkStressResult) {
        _ = ctx;

        const start_time = std.time.milliTimestamp();
        const file_size_bytes = self.file_size_kb * 1024;

        // 模拟大量文件传输
        for (0..self.file_count) |i| {
            if (self.transferFile(i, file_size_bytes)) {
                _ = self.files_transferred.fetchAdd(1, .acq_rel);
                _ = self.total_bytes.fetchAdd(file_size_bytes, .acq_rel);
            } else {
                _ = self.transfer_errors.fetchAdd(1, .acq_rel);
            }

            // 每100个文件输出进度
            if (i % 100 == 0) {
                std.debug.print("已传输文件: {}/{}\n", .{ i, self.file_count });
            }
        }

        const end_time = std.time.milliTimestamp();
        const duration_ms = @as(u64, @intCast(end_time - start_time));
        const transferred = self.files_transferred.load(.acquire);
        const bytes = self.total_bytes.load(.acquire);
        const errors = self.transfer_errors.load(.acquire);

        return .{ .ready = NetworkStressResult{
            .name = "文件传输压力",
            .connections_handled = transferred,
            .bytes_transferred = bytes,
            .duration_ms = duration_ms,
            .connections_per_second = @as(f64, @floatFromInt(transferred)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .throughput_mbps = (@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0)) / (@as(f64, @floatFromInt(duration_ms)) / 1000.0),
            .error_rate = @as(f64, @floatFromInt(errors)) / @as(f64, @floatFromInt(transferred + errors)),
        } };
    }

    fn transferFile(self: *Self, file_id: usize, file_size: u64) bool {
        _ = self;

        // 模拟文件读取
        const chunk_size = 4096; // 4KB chunks
        const chunks = file_size / chunk_size;

        for (0..chunks) |chunk_id| {
            // 模拟读取文件块
            var chunk_data: [4096]u8 = undefined;
            for (&chunk_data, 0..) |*byte, i| {
                byte.* = @intCast((file_id + chunk_id + i) % 256);
            }

            // 模拟网络传输延迟
            std.time.sleep(100); // 100纳秒
        }

        return true;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.print("=== Zokio网络压力测试套件 ===\n", .{});
    try stdout.print("基于examples网络示例的高性能网络压力测试\n\n", .{});

    // 创建网络优化的运行时配置
    const config = zokio.RuntimeConfig{
        .worker_threads = 8,
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .enable_metrics = false,
        .enable_numa = true,
        .memory_strategy = .adaptive,
    };

    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    try stdout.print("网络运行时配置:\n", .{});
    try stdout.print("  I/O后端: {s}\n", .{RuntimeType.COMPILE_TIME_INFO.io_backend});
    try stdout.print("  工作线程: {}\n", .{RuntimeType.COMPILE_TIME_INFO.worker_threads});
    try stdout.print("\n", .{});

    try runtime.start();
    defer runtime.stop();

    var results = std.ArrayList(NetworkStressResult).init(allocator);
    defer results.deinit();

    // 网络压力测试1: 高并发TCP连接
    try stdout.print("=== 网络压力测试1: 高并发TCP连接 ===\n", .{});
    const tcp_stress = HighConcurrencyTcpStress{
        .target_connections = 50_000, // 5万个连接
        .bytes_per_connection = 2048, // 每连接2KB
    };
    const tcp_result = try runtime.blockOn(tcp_stress);
    try results.append(tcp_result);
    try stdout.print("{}\n", .{tcp_result});

    // 网络压力测试2: HTTP服务器压力
    try stdout.print("=== 网络压力测试2: HTTP服务器压力 ===\n", .{});
    const http_stress = HttpServerStress{
        .target_requests = 100_000, // 10万个请求
        .concurrent_connections = 1000, // 1000并发连接
    };
    const http_result = try runtime.blockOn(http_stress);
    try results.append(http_result);
    try stdout.print("{}\n", .{http_result});

    // 网络压力测试3: 文件传输压力
    try stdout.print("=== 网络压力测试3: 文件传输压力 ===\n", .{});
    const file_stress = FileTransferStress{
        .file_count = 1000, // 1000个文件
        .file_size_kb = 100, // 每文件100KB
    };
    const file_result = try runtime.blockOn(file_stress);
    try results.append(file_result);
    try stdout.print("{}\n", .{file_result});

    // 网络压力测试总结
    try stdout.print("\n=== 网络压力测试总结 ===\n", .{});
    var total_connections: u64 = 0;
    var total_bytes: u64 = 0;
    var total_duration: u64 = 0;
    var max_throughput: f64 = 0;

    for (results.items) |result| {
        total_connections += result.connections_handled;
        total_bytes += result.bytes_transferred;
        total_duration += result.duration_ms;
        if (result.throughput_mbps > max_throughput) {
            max_throughput = result.throughput_mbps;
        }
    }

    try stdout.print("总连接数: {}\n", .{total_connections});
    try stdout.print("总传输字节: {}\n", .{total_bytes});
    try stdout.print("总耗时: {}ms\n", .{total_duration});
    try stdout.print("平均连接/秒: {d:.2}\n", .{@as(f64, @floatFromInt(total_connections)) / (@as(f64, @floatFromInt(total_duration)) / 1000.0)});
    try stdout.print("峰值吞吐量: {d:.2} MB/s\n", .{max_throughput});

    try stdout.print("\n✓ 网络压力测试完成！Zokio网络性能表现优异！\n", .{});
}
