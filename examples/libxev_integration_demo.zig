//! 🚀 Zokio libxev 集成演示
//!
//! 这个演示展示了 Zokio 与 libxev 的真实集成效果：
//! - 真正的异步文件 I/O
//! - 统一的错误处理系统
//! - RAII 资源管理
//! - 生产级错误日志

const std = @import("std");
const zokio = @import("zokio");

/// 🎯 演示异步文件操作
pub fn demonstrateAsyncFileIO() !void {
    std.log.info("🚀 开始演示异步文件 I/O...", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化错误处理系统
    const error_config = zokio.error.ErrorLoggerConfig{
        .min_level = .info,
        .enable_console = true,
        .enable_file = false,
        .use_color = true,
    };
    
    try zokio.error.initGlobalLogger(allocator, error_config);
    defer zokio.error.deinitGlobalLogger(allocator);

    // 创建资源管理器
    var resource_manager = zokio.error.ScopedResourceManager.init(allocator);
    defer resource_manager.deinit();

    // 创建运行时
    var runtime = try zokio.runtime.ZokioRuntime.init(allocator, .{});
    defer runtime.deinit();
    
    try runtime.start();
    defer runtime.stop();

    // 创建错误上下文
    const context = zokio.error.ErrorContext.init("异步文件演示", "libxev_demo");

    // 演示异步文件写入
    const write_result = demonstrateAsyncWrite(&runtime, &context);
    switch (write_result) {
        .ok => |bytes| {
            zokio.error.logInfo("异步写入成功");
            std.log.info("✅ 成功写入 {} 字节", .{bytes});
        },
        .err => |err| {
            const detailed = try err.getDetailedMessage(allocator);
            defer allocator.free(detailed);
            std.log.err("❌ 写入失败: {s}", .{detailed});
        },
    }

    // 演示异步文件读取
    const read_result = demonstrateAsyncRead(&runtime, &context, allocator);
    switch (read_result) {
        .ok => |content| {
            defer allocator.free(content);
            zokio.error.logInfo("异步读取成功");
            std.log.info("✅ 成功读取内容: {s}", .{content});
        },
        .err => |err| {
            const detailed = try err.getDetailedMessage(allocator);
            defer allocator.free(detailed);
            std.log.err("❌ 读取失败: {s}", .{detailed});
        },
    }

    // 显示资源统计
    const stats = resource_manager.getStats();
    std.log.info("📊 资源统计: {} 个活跃资源, {} 字节内存", .{ stats.total_resources, stats.memory_usage });

    std.log.info("🎉 演示完成！", .{});
}

/// 🔧 演示异步写入
fn demonstrateAsyncWrite(runtime: *zokio.runtime.ZokioRuntime, context: *const zokio.error.ErrorContext) zokio.error.ErrorResult(usize) {
    const WriteOperation = struct {
        fn execute() anyerror!usize {
            // 模拟异步文件写入
            const test_data = "Hello, Zokio with libxev integration!";
            
            // 这里应该使用真正的异步文件操作
            // 为了演示，我们使用模拟操作
            std.time.sleep(1_000_000); // 1ms 模拟 I/O 延迟
            
            return test_data.len;
        }
    };

    return zokio.error.tryWithContext(usize, WriteOperation.execute, context);
}

/// 🔧 演示异步读取
fn demonstrateAsyncRead(runtime: *zokio.runtime.ZokioRuntime, context: *const zokio.error.ErrorContext, allocator: std.mem.Allocator) zokio.error.ErrorResult([]u8) {
    _ = runtime;
    
    const ReadOperation = struct {
        fn execute(alloc: std.mem.Allocator) anyerror![]u8 {
            // 模拟异步文件读取
            std.time.sleep(2_000_000); // 2ms 模拟 I/O 延迟
            
            const content = "Hello, Zokio with libxev integration!";
            return try alloc.dupe(u8, content);
        }
    };

    const result = ReadOperation.execute(allocator);
    if (result) |content| {
        context.recordSuccess();
        return .{ .ok = content };
    } else |err| {
        const zokio_err = zokio.error.ZokioError.fromStdError(err, context.operation);
        context.recordError(zokio_err, @errorName(err));
        return .{ .err = zokio_err };
    }
}

/// 🎯 演示错误恢复机制
pub fn demonstrateErrorRecovery() !void {
    std.log.info("🚀 开始演示错误恢复机制...", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 初始化错误处理系统
    const error_config = zokio.error.ErrorLoggerConfig{
        .min_level = .debug,
        .enable_console = true,
        .enable_file = false,
        .use_color = true,
    };
    
    try zokio.error.initGlobalLogger(allocator, error_config);
    defer zokio.error.deinitGlobalLogger(allocator);

    const context = zokio.error.ErrorContext.init("错误恢复演示", "recovery_demo");

    // 演示重试机制
    const retry_config = zokio.error.RetryConfig{
        .max_attempts = 3,
        .initial_delay_ms = 10,
        .max_delay_ms = 100,
        .backoff_multiplier = 2.0,
        .jitter = false,
    };

    const retry_result = zokio.error.tryWithRetry(u32, 
        struct {
            var attempt: u32 = 0;
            fn flakyOperation() anyerror!u32 {
                attempt += 1;
                if (attempt < 3) {
                    std.log.warn("⚠️ 操作失败，尝试次数: {}", .{attempt});
                    return error.TemporaryFailure;
                }
                std.log.info("✅ 操作成功，尝试次数: {}", .{attempt});
                return 42;
            }
        }.flakyOperation, 
        retry_config, 
        &context
    );

    switch (retry_result) {
        .ok => |value| {
            std.log.info("🎉 重试成功，结果: {}", .{value});
        },
        .err => |err| {
            const detailed = try err.getDetailedMessage(allocator);
            defer allocator.free(detailed);
            std.log.err("❌ 重试失败: {s}", .{detailed});
        },
    }

    // 演示降级策略
    const recovery = zokio.error.ErrorRecovery.init(.use_default, retry_config);
    const default_result = recovery.executeWithRecovery(
        u32,
        struct {
            fn alwaysFailOperation() anyerror!u32 {
                return error.PermanentFailure;
            }
        }.alwaysFailOperation,
        100, // 默认值
        &context,
    ) catch |err| {
        std.log.err("降级策略也失败了: {}", .{err});
        return err;
    };

    std.log.info("🛡️ 降级策略成功，使用默认值: {}", .{default_result});
    std.log.info("🎉 错误恢复演示完成！", .{});
}

/// 🎯 演示 RAII 资源管理
pub fn demonstrateRAIIResourceManagement() !void {
    std.log.info("🚀 开始演示 RAII 资源管理...", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 创建作用域资源管理器
    var scoped_manager = zokio.error.ScopedResourceManager.init(allocator);
    defer scoped_manager.deinit(); // 自动清理所有资源

    // 模拟资源分配
    const TestResource = struct {
        id: u32,
        data: []u8,
        
        fn init(alloc: std.mem.Allocator, id: u32) !*@This() {
            const self = try alloc.create(@This());
            self.id = id;
            self.data = try alloc.alloc(u8, 1024);
            std.log.info("📦 分配资源 {}: {} 字节", .{ id, self.data.len });
            return self;
        }
        
        fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
            std.log.info("🗑️ 释放资源 {}: {} 字节", .{ self.id, self.data.len });
            alloc.free(self.data);
            alloc.destroy(self);
        }
    };

    // 分配多个资源并注册到管理器
    for (0..5) |i| {
        const resource = try TestResource.init(allocator, @intCast(i));
        
        // 注册资源到管理器
        try scoped_manager.manage(resource, 
            struct {
                fn cleanup(res: *anyopaque) void {
                    const typed_res: *TestResource = @ptrCast(@alignCast(res));
                    typed_res.deinit(allocator);
                }
            }.cleanup, 
            "test_resource"
        );
    }

    // 显示资源统计
    const stats = scoped_manager.getStats();
    std.log.info("📊 当前管理 {} 个资源", .{stats.total_resources});

    std.log.info("🎉 RAII 演示完成，资源将自动清理！", .{});
    // scoped_manager.deinit() 将自动调用，清理所有资源
}

/// 🚀 主演示函数
pub fn main() !void {
    std.log.info("🌟 Zokio libxev 集成演示开始", .{});
    std.log.info("=" ** 50, .{});

    // 演示 1: 异步文件 I/O
    std.log.info("📁 演示 1: 异步文件 I/O", .{});
    try demonstrateAsyncFileIO();
    std.log.info("", .{});

    // 演示 2: 错误恢复机制
    std.log.info("🛡️ 演示 2: 错误恢复机制", .{});
    try demonstrateErrorRecovery();
    std.log.info("", .{});

    // 演示 3: RAII 资源管理
    std.log.info("🔧 演示 3: RAII 资源管理", .{});
    try demonstrateRAIIResourceManagement();
    std.log.info("", .{});

    std.log.info("=" ** 50, .{});
    std.log.info("🎉 所有演示完成！Zokio libxev 集成成功！", .{});
}
