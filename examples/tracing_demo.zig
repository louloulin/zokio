//! 分布式追踪和监控演示
//!
//! 展示Zokio的分布式追踪功能，包括Span创建、事件记录、上下文传播等。

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio分布式追踪和监控演示 ===\n\n");

    // 初始化全局追踪器
    const tracer_config = zokio.tracing.TracerConfig{
        .max_spans = 1000,
        .max_events_per_span = 50,
        .enable_sampling = true,
        .sampling_rate = 1.0, // 100%采样用于演示
        .buffer_size = 512,
        .flush_interval = zokio.timer.Duration.fromSecs(1),
    };

    try zokio.tracing.initGlobalTracer(allocator, tracer_config);

    // 创建运行时
    var runtime = try zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();

    // 运行追踪演示
    try runtime.block_on(tracingDemonstration(allocator));

    std.debug.print("\n=== 演示完成 ===\n");
}

fn tracingDemonstration(allocator: std.mem.Allocator) !void {
    std.debug.print("1. 追踪上下文演示\n");

    // 创建根追踪上下文
    const root_context = zokio.tracing.TraceContext.new();
    std.debug.print("  根上下文:\n");
    std.debug.print("    trace_id: {x}\n", .{root_context.trace_id});
    std.debug.print("    span_id: {x}\n", .{root_context.span_id});
    std.debug.print("    parent_span_id: {?}\n", .{root_context.parent_span_id});

    // 创建子上下文
    const child_context = root_context.child();
    std.debug.print("  子上下文:\n");
    std.debug.print("    trace_id: {x} (应该与父相同)\n", .{child_context.trace_id});
    std.debug.print("    span_id: {x}\n", .{child_context.span_id});
    std.debug.print("    parent_span_id: {x}\n", .{child_context.parent_span_id.?});

    std.debug.print("  上下文关系验证:\n");
    std.debug.print("    trace_id相同: {}\n", .{root_context.trace_id == child_context.trace_id});
    std.debug.print("    span_id不同: {}\n", .{root_context.span_id != child_context.span_id});
    std.debug.print("    父子关系正确: {}\n", .{child_context.parent_span_id.? == root_context.span_id});

    std.debug.print("\n2. 追踪事件演示\n");

    // 创建不同级别的追踪事件
    const levels = [_]zokio.tracing.Level{ .trace, .debug, .info, .warn, .err };

    for (levels) |level| {
        var event = zokio.tracing.TraceEvent.init(allocator, level, "这是一个测试事件", root_context);
        defer event.deinit();

        try event.addAttribute("level", level.toString());
        try event.addAttribute("component", "demo");
        try event.addAttribute("version", "1.0.0");

        std.debug.print("  {s}事件:\n", .{level.toString()});
        std.debug.print("    消息: {s}\n", .{event.message});
        std.debug.print("    时间戳: {} 纳秒\n", .{event.timestamp.nanos});
        std.debug.print("    属性数量: {}\n", .{event.attributes.count()});
    }

    std.debug.print("\n3. Span生命周期演示\n");

    // 创建一个Span
    var span = zokio.tracing.Span.init(allocator, "database_query", root_context);
    defer span.deinit();

    std.debug.print("  Span创建:\n");
    std.debug.print("    名称: {s}\n", .{span.name});
    std.debug.print("    开始时间: {} 纳秒\n", .{span.start_time.nanos});
    std.debug.print("    状态: {s}\n", .{@tagName(span.status)});

    // 添加属性
    try span.addAttribute("db.type", "postgresql");
    try span.addAttribute("db.name", "users");
    try span.addAttribute("db.operation", "SELECT");
    try span.addAttribute("db.table", "user_profiles");

    // 模拟一些工作
    std.time.sleep(1000000); // 1毫秒

    // 添加事件
    var query_start_event = zokio.tracing.TraceEvent.init(allocator, .info, "开始执行查询", span.context);
    defer query_start_event.deinit();
    try query_start_event.addAttribute("query", "SELECT * FROM user_profiles WHERE id = $1");
    try span.addEvent(query_start_event);

    // 模拟更多工作
    std.time.sleep(2000000); // 2毫秒

    var query_end_event = zokio.tracing.TraceEvent.init(allocator, .info, "查询执行完成", span.context);
    defer query_end_event.deinit();
    try query_end_event.addAttribute("rows_returned", "1");
    try query_end_event.addAttribute("execution_time_ms", "3");
    try span.addEvent(query_end_event);

    // 设置状态并完成Span
    span.setStatus(.ok);
    span.finish();

    std.debug.print("  Span完成:\n");
    std.debug.print("    结束时间: {} 纳秒\n", .{span.end_time.?.nanos});
    std.debug.print("    持续时间: {}微秒\n", .{span.duration().?.asMicros()});
    std.debug.print("    最终状态: {s}\n", .{@tagName(span.status)});
    std.debug.print("    属性数量: {}\n", .{span.attributes.count()});
    std.debug.print("    事件数量: {}\n", .{span.events.items.len});

    std.debug.print("\n4. 追踪器演示\n");

    if (zokio.tracing.getGlobalTracer()) |tracer| {
        std.debug.print("  全局追踪器已初始化\n");

        // 开始一个新的Span
        var web_request_span = tracer.startSpan("web_request") catch |err| {
            std.debug.print("  创建Span失败: {}\n", .{err});
            return;
        };

        try web_request_span.addAttribute("http.method", "GET");
        try web_request_span.addAttribute("http.url", "/api/users/123");
        try web_request_span.addAttribute("http.user_agent", "Zokio-Client/1.0");

        std.debug.print("  Web请求Span已创建\n");

        // 记录一些日志
        try tracer.info("处理用户请求");
        try tracer.debug("验证用户权限");
        try tracer.info("查询用户数据");

        // 创建子Span
        var auth_span = tracer.startSpan("authentication") catch |err| {
            std.debug.print("  创建认证Span失败: {}\n", .{err});
            tracer.finishSpan(web_request_span);
            return;
        };

        try auth_span.addAttribute("auth.method", "jwt");
        try auth_span.addAttribute("auth.user_id", "123");

        std.debug.print("  认证Span已创建\n");

        // 模拟认证过程
        std.time.sleep(500000); // 0.5毫秒

        try tracer.info("JWT令牌验证成功");
        auth_span.setStatus(.ok);
        tracer.finishSpan(auth_span);

        std.debug.print("  认证Span已完成\n");

        // 继续处理主请求
        try tracer.info("用户认证成功，继续处理请求");

        // 模拟数据库查询
        var db_span = tracer.startSpan("database_query") catch |err| {
            std.debug.print("  创建数据库Span失败: {}\n", .{err});
            tracer.finishSpan(web_request_span);
            return;
        };

        try db_span.addAttribute("db.type", "postgresql");
        try db_span.addAttribute("db.query", "SELECT * FROM users WHERE id = $1");

        std.time.sleep(1500000); // 1.5毫秒

        try tracer.info("数据库查询完成");
        db_span.setStatus(.ok);
        tracer.finishSpan(db_span);

        std.debug.print("  数据库Span已完成\n");

        // 完成主请求
        try tracer.info("请求处理完成");
        web_request_span.setStatus(.ok);
        tracer.finishSpan(web_request_span);

        std.debug.print("  Web请求Span已完成\n");

        // 刷新追踪器输出
        std.debug.print("\n  刷新追踪器输出:\n");
        tracer.flush();
    } else {
        std.debug.print("  全局追踪器未初始化\n");
    }

    std.debug.print("\n5. 错误追踪演示\n");

    if (zokio.tracing.getGlobalTracer()) |tracer| {
        var error_span = tracer.startSpan("error_handling") catch |err| {
            std.debug.print("  创建错误Span失败: {}\n", .{err});
            return;
        };

        try error_span.addAttribute("operation", "file_processing");
        try error_span.addAttribute("file_path", "/nonexistent/file.txt");

        // 模拟错误情况
        try tracer.warn("文件不存在，尝试创建");
        try tracer.err("文件创建失败：权限不足");

        error_span.setStatus(.err);
        tracer.finishSpan(error_span);

        std.debug.print("  错误Span已完成\n");
        tracer.flush();
    }

    std.debug.print("\n6. 性能监控演示\n");

    if (zokio.tracing.getGlobalTracer()) |tracer| {
        var perf_span = tracer.startSpan("performance_test") catch |err| {
            std.debug.print("  创建性能Span失败: {}\n", .{err});
            return;
        };

        const start_time = zokio.timer.Instant.now();

        // 模拟计算密集型任务
        var result: u64 = 0;
        for (0..1000000) |i| {
            result += i;
        }

        const end_time = zokio.timer.Instant.now();
        const duration = end_time.sub(start_time);

        try perf_span.addAttribute("task_type", "computation");
        try perf_span.addAttribute("iterations", "1000000");
        try perf_span.addAttribute("result", std.fmt.allocPrint(allocator, "{}", .{result}) catch "unknown");
        try perf_span.addAttribute("duration_us", std.fmt.allocPrint(allocator, "{}", .{duration.asMicros()}) catch "unknown");

        try tracer.info("计算任务完成");

        perf_span.setStatus(.ok);
        tracer.finishSpan(perf_span);

        std.debug.print("  性能测试完成，耗时: {}微秒\n", .{duration.asMicros()});
        tracer.flush();
    }

    std.debug.print("\n7. 上下文传播演示\n");

    if (zokio.tracing.getGlobalTracer()) |tracer| {
        // 获取当前上下文
        const current_context = tracer.getCurrentContext();
        std.debug.print("  当前上下文: {?}\n", .{current_context});

        // 设置新的上下文
        const new_context = zokio.tracing.TraceContext.new();
        tracer.setCurrentContext(new_context);

        const context_span = tracer.startSpan("context_propagation") catch |err| {
            std.debug.print("  创建上下文Span失败: {}\n", .{err});
            return;
        };

        try tracer.info("在新上下文中执行操作");

        tracer.finishSpan(context_span);

        // 恢复原上下文
        tracer.setCurrentContext(current_context);

        std.debug.print("  上下文传播演示完成\n");
        tracer.flush();
    }

    std.debug.print("\n✓ 分布式追踪和监控演示完成\n");
}
