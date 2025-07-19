//! 分布式追踪和监控系统
//!
//! 提供高性能的分布式追踪、性能监控、日志记录等功能。

const std = @import("std");
const utils = @import("../utils/utils.zig");
const time = @import("../time/timer.zig");

/// 追踪级别
pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,

    pub fn toString(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

/// 追踪上下文
pub const TraceContext = struct {
    trace_id: u128,
    span_id: u64,
    parent_span_id: ?u64,
    flags: u8,

    pub fn new() TraceContext {
        return TraceContext{
            .trace_id = generateTraceId(),
            .span_id = generateSpanId(),
            .parent_span_id = null,
            .flags = 0,
        };
    }

    pub fn child(self: TraceContext) TraceContext {
        return TraceContext{
            .trace_id = self.trace_id,
            .span_id = generateSpanId(),
            .parent_span_id = self.span_id,
            .flags = self.flags,
        };
    }

    fn generateTraceId() u128 {
        var rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
        return rng.random().int(u128);
    }

    fn generateSpanId() u64 {
        var rng = std.Random.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
        return rng.random().int(u64);
    }
};

/// 追踪事件
pub const TraceEvent = struct {
    timestamp: time.Instant,
    level: Level,
    message: []const u8,
    context: TraceContext,
    attributes: std.StringHashMap([]const u8),
    duration: ?time.Duration = null,

    pub fn init(allocator: std.mem.Allocator, level: Level, message: []const u8, context: TraceContext) TraceEvent {
        return TraceEvent{
            .timestamp = time.Instant.now(),
            .level = level,
            .message = message,
            .context = context,
            .attributes = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn addAttribute(self: *TraceEvent, key: []const u8, value: []const u8) !void {
        try self.attributes.put(key, value);
    }

    pub fn deinit(self: *TraceEvent) void {
        self.attributes.deinit();
    }
};

/// 追踪Span
pub const Span = struct {
    context: TraceContext,
    name: []const u8,
    start_time: time.Instant,
    end_time: ?time.Instant = null,
    attributes: std.StringHashMap([]const u8),
    events: std.ArrayList(TraceEvent),
    status: Status = .ok,

    pub const Status = enum {
        ok,
        err,
        timeout,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8, context: TraceContext) Span {
        return Span{
            .context = context,
            .name = name,
            .start_time = time.Instant.now(),
            .attributes = std.StringHashMap([]const u8).init(allocator),
            .events = std.ArrayList(TraceEvent).init(allocator),
        };
    }

    pub fn addAttribute(self: *Span, key: []const u8, value: []const u8) !void {
        try self.attributes.put(key, value);
    }

    pub fn addEvent(self: *Span, event: TraceEvent) !void {
        try self.events.append(event);
    }

    pub fn setStatus(self: *Span, status: Status) void {
        self.status = status;
    }

    pub fn finish(self: *Span) void {
        self.end_time = time.Instant.now();
    }

    pub fn duration(self: *const Span) ?time.Duration {
        if (self.end_time) |end| {
            return end.sub(self.start_time);
        }
        return null;
    }

    pub fn deinit(self: *Span) void {
        self.attributes.deinit();
        for (self.events.items) |*event| {
            event.deinit();
        }
        self.events.deinit();
    }
};

/// 追踪器配置
pub const TracerConfig = struct {
    max_spans: usize = 10000,
    max_events_per_span: usize = 100,
    enable_sampling: bool = true,
    sampling_rate: f64 = 0.1, // 10%采样率
    buffer_size: usize = 1024,
    flush_interval: time.Duration = time.Duration.fromSecs(5),
};

/// 追踪器
pub const Tracer = struct {
    config: TracerConfig,
    spans: utils.RingBuffer(Span),
    current_context: ?TraceContext = null,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, config: TracerConfig) !Tracer {
        return Tracer{
            .config = config,
            .spans = try utils.RingBuffer(Span).init(allocator, config.max_spans),
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Tracer) void {
        self.spans.deinit();
    }

    pub fn startSpan(self: *Tracer, name: []const u8) !*Span {
        self.mutex.lock();
        defer self.mutex.unlock();

        const context = if (self.current_context) |ctx| ctx.child() else TraceContext.new();

        // 采样决策
        if (self.config.enable_sampling) {
            var rng = std.rand.DefaultPrng.init(@intCast(std.time.nanoTimestamp()));
            if (rng.random().float(f64) > self.config.sampling_rate) {
                // 不采样，返回空Span
                return error.NotSampled;
            }
        }

        const new_span = Span.init(self.allocator, name, context);
        try self.spans.push(new_span);

        // 更新当前上下文
        self.current_context = context;

        return self.spans.back().?;
    }

    pub fn finishSpan(self: *Tracer, span: *Span) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        span.finish();

        // 如果这是当前Span，恢复父上下文
        if (self.current_context) |ctx| {
            if (ctx.span_id == span.context.span_id) {
                if (span.context.parent_span_id) |parent_id| {
                    // 查找父Span的上下文
                    for (self.spans.items()) |*parent_span| {
                        if (parent_span.context.span_id == parent_id) {
                            self.current_context = parent_span.context;
                            break;
                        }
                    }
                } else {
                    self.current_context = null;
                }
            }
        }
    }

    pub fn trace(self: *Tracer, message: []const u8) !void {
        try self.log(.trace, message);
    }

    pub fn debug(self: *Tracer, message: []const u8) !void {
        try self.log(.debug, message);
    }

    pub fn info(self: *Tracer, message: []const u8) !void {
        try self.log(.info, message);
    }

    pub fn warn(self: *Tracer, message: []const u8) !void {
        try self.log(.warn, message);
    }

    pub fn err(self: *Tracer, message: []const u8) !void {
        try self.log(.err, message);
    }

    fn log(self: *Tracer, level: Level, message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const context = self.current_context orelse TraceContext.new();
        var event = TraceEvent.init(self.allocator, level, message, context);

        // 如果有当前Span，添加到Span中
        if (self.current_context) |ctx| {
            for (self.spans.items()) |*current_span| {
                if (current_span.context.span_id == ctx.span_id) {
                    try current_span.addEvent(event);
                    return;
                }
            }
        }

        // 否则直接输出
        self.outputEvent(&event);
        event.deinit();
    }

    fn outputEvent(self: *Tracer, event: *const TraceEvent) void {
        _ = self;

        // 简单的控制台输出
        const timestamp = event.timestamp.nanos / 1_000_000; // 转换为毫秒
        std.debug.print("[{d}] {s}: {s} (trace_id={x}, span_id={x})\n", .{
            timestamp,
            event.level.toString(),
            event.message,
            event.context.trace_id,
            event.context.span_id,
        });
    }

    pub fn flush(self: *Tracer) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // 输出所有完成的Span
        for (self.spans.items()) |*completed_span| {
            if (completed_span.end_time != null) {
                self.outputSpan(completed_span);
            }
        }
    }

    fn outputSpan(self: *Tracer, span: *const Span) void {
        _ = self;

        const duration_ms = if (span.duration()) |d| d.asMillis() else 0;

        std.debug.print("Span: {s} (duration={d}ms, status={s}, trace_id={x}, span_id={x})\n", .{
            span.name,
            duration_ms,
            @tagName(span.status),
            span.context.trace_id,
            span.context.span_id,
        });

        // 输出属性
        var attr_iter = span.attributes.iterator();
        while (attr_iter.next()) |entry| {
            std.debug.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // 输出事件
        for (span.events.items) |*event| {
            std.debug.print("  Event: {s} - {s}\n", .{ event.level.toString(), event.message });
        }
    }

    pub fn getCurrentContext(self: *const Tracer) ?TraceContext {
        return self.current_context;
    }

    pub fn setCurrentContext(self: *Tracer, context: ?TraceContext) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.current_context = context;
    }
};

/// 全局追踪器实例
var global_tracer: ?*Tracer = null;

/// 初始化全局追踪器
pub fn initGlobalTracer(allocator: std.mem.Allocator, config: TracerConfig) !void {
    const tracer = try allocator.create(Tracer);
    tracer.* = try Tracer.init(allocator, config);
    global_tracer = tracer;
}

/// 获取全局追踪器
pub fn getGlobalTracer() ?*Tracer {
    return global_tracer;
}

/// 便利宏：开始一个Span
pub fn createSpan(name: []const u8) !*Span {
    if (global_tracer) |tracer| {
        return tracer.startSpan(name);
    }
    return error.NoTracer;
}

/// 便利宏：记录日志
pub fn log(level: Level, message: []const u8) void {
    if (global_tracer) |tracer| {
        tracer.log(level, message) catch {};
    }
}

// 测试
test "TraceContext生成" {
    const testing = std.testing;

    const ctx1 = TraceContext.new();
    // 添加小延迟确保时间戳不同
    std.time.sleep(1000);
    const ctx2 = TraceContext.new();

    // 不同的上下文应该有不同的ID（由于时间戳不同，概率很高）
    // 注意：由于使用时间戳作为种子，在极少数情况下可能相同
    const ids_different = ctx1.trace_id != ctx2.trace_id or ctx1.span_id != ctx2.span_id;
    try testing.expect(ids_different);

    // 子上下文应该继承trace_id
    const child = ctx1.child();
    try testing.expect(child.trace_id == ctx1.trace_id);
    try testing.expect(child.span_id != ctx1.span_id);
    try testing.expect(child.parent_span_id.? == ctx1.span_id);
}

test "Span基础功能" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const context = TraceContext.new();
    var test_span = Span.init(allocator, "test_span", context);
    defer test_span.deinit();

    try test_span.addAttribute("key1", "value1");
    try test_span.addAttribute("key2", "value2");

    test_span.setStatus(.ok);
    test_span.finish();

    try testing.expect(test_span.end_time != null);
    try testing.expect(test_span.duration() != null);
    try testing.expect(test_span.status == .ok);
    try testing.expect(test_span.attributes.count() == 2);
}
