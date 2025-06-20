//! 定时器和时间管理演示
//!
//! 展示Zokio的定时器功能，包括延迟执行、超时控制、时间测量等。

const std = @import("std");
const zokio = @import("zokio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio定时器和时间管理演示 ===\n\n", .{});

    // 创建运行时
    var runtime = try zokio.builder()
        .threads(2)
        .metrics(true)
        .build(allocator);
    defer runtime.deinit();

    // 启动运行时
    try runtime.start();

    // 运行定时器演示
    try timerDemonstration();

    std.debug.print("\n=== 演示完成 ===\n", .{});
}

fn timerDemonstration() !void {
    std.debug.print("1. 时间类型基础演示\n", .{});

    // Duration演示
    const duration_examples = [_]struct {
        name: []const u8,
        duration: zokio.timer.Duration,
    }{
        .{ .name = "1纳秒", .duration = zokio.timer.Duration.fromNanos(1) },
        .{ .name = "1微秒", .duration = zokio.timer.Duration.fromMicros(1) },
        .{ .name = "1毫秒", .duration = zokio.timer.Duration.fromMillis(1) },
        .{ .name = "1秒", .duration = zokio.timer.Duration.fromSecs(1) },
        .{ .name = "1分钟", .duration = zokio.timer.Duration.fromSecs(60) },
    };

    for (duration_examples) |example| {
        std.debug.print("  {s}:\n", .{example.name});
        std.debug.print("    纳秒: {}\n", .{example.duration.asNanos()});
        std.debug.print("    微秒: {}\n", .{example.duration.asMicros()});
        std.debug.print("    毫秒: {}\n", .{example.duration.asMillis()});
        std.debug.print("    秒: {}\n", .{example.duration.asSecs()});
    }

    std.debug.print("\n2. Duration运算演示\n", .{});

    const d1 = zokio.timer.Duration.fromMillis(1500); // 1.5秒
    const d2 = zokio.timer.Duration.fromMillis(500); // 0.5秒

    std.debug.print("  d1 = {}ms, d2 = {}ms\n", .{ d1.asMillis(), d2.asMillis() });
    std.debug.print("  d1 + d2 = {}ms\n", .{d1.add(d2).asMillis()});
    std.debug.print("  d1 - d2 = {}ms\n", .{d1.sub(d2).asMillis()});
    std.debug.print("  d1 * 2 = {}ms\n", .{d1.mul(2).asMillis()});
    std.debug.print("  d1 / 3 = {}ms\n", .{d1.div(3).asMillis()});

    std.debug.print("\n3. Instant时间点演示\n", .{});

    const start_time = zokio.timer.Instant.now();
    std.debug.print("  开始时间: {} 纳秒\n", .{start_time.nanos});

    // 模拟一些工作
    var sum: u64 = 0;
    for (0..1000000) |i| {
        sum += i;
    }

    const end_time = zokio.timer.Instant.now();
    const elapsed = end_time.sub(start_time);

    std.debug.print("  结束时间: {} 纳秒\n", .{end_time.nanos});
    std.debug.print("  耗时: {}微秒 (计算结果: {})\n", .{ elapsed.asMicros(), sum });
    std.debug.print("  end_time.isAfter(start_time): {}\n", .{end_time.isAfter(start_time)});

    std.debug.print("\n4. 延迟Future演示\n", .{});

    // 创建延迟Future
    var delay_future = zokio.timer.DelayFuture.init(zokio.timer.Duration.fromNanos(1000)); // 1微秒延迟
    defer delay_future.deinit();

    const waker = zokio.Waker.noop();
    var ctx = zokio.Context.init(waker);

    const delay_start = zokio.timer.Instant.now();

    // 等待一小段时间确保延迟到期
    std.time.sleep(10000); // 10微秒

    switch (delay_future.poll(&ctx)) {
        .ready => {
            const delay_end = zokio.timer.Instant.now();
            const actual_delay = delay_end.sub(delay_start);
            std.debug.print("  ✓ 延迟Future完成，实际延迟: {}微秒\n", .{actual_delay.asMicros()});
        },
        .pending => std.debug.print("  ⏳ 延迟Future仍在等待\n", .{}),
    }

    std.debug.print("\n5. 便利函数演示\n", .{});

    // 使用便利函数创建延迟
    var simple_delay = zokio.timer.delay(zokio.timer.Duration.fromNanos(500));
    defer simple_delay.deinit();

    std.time.sleep(1000); // 等待1微秒

    switch (simple_delay.poll(&ctx)) {
        .ready => std.debug.print("  ✓ 简单延迟完成\n", .{}),
        .pending => std.debug.print("  ⏳ 简单延迟仍在等待\n", .{}),
    }

    std.debug.print("\n6. 定时器轮演示\n", .{});

    // 获取下一个定时器截止时间
    if (zokio.timer.getNextTimerDeadline()) |deadline| {
        const now = zokio.timer.Instant.now();
        if (deadline.isAfter(now)) {
            const remaining = deadline.sub(now);
            std.debug.print("  下一个定时器将在 {}微秒后触发\n", .{remaining.asMicros()});
        } else {
            std.debug.print("  有定时器已经到期\n", .{});
        }
    } else {
        std.debug.print("  当前没有活跃的定时器\n", .{});
    }

    // 处理到期的定时器
    zokio.timer.processTimers();
    std.debug.print("  ✓ 定时器处理完成\n", .{});

    std.debug.print("\n7. 时间测量工具演示\n", .{});

    // 测量函数执行时间
    const measure_start = zokio.timer.Instant.now();

    // 模拟一个计算密集型任务
    var result: f64 = 1.0;
    for (0..100000) |i| {
        result += @sqrt(@as(f64, @floatFromInt(i + 1)));
    }

    const measure_end = zokio.timer.Instant.now();
    const execution_time = measure_end.sub(measure_start);

    std.debug.print("  计算任务执行时间: {}微秒\n", .{execution_time.asMicros()});
    std.debug.print("  计算结果: {d:.2}\n", .{result});

    std.debug.print("\n8. 高精度时间比较演示\n", .{});

    const time1 = zokio.timer.Instant.now();
    const time2 = zokio.timer.Instant.now();
    const time3 = zokio.timer.Instant.now();

    std.debug.print("  时间序列:\n", .{});
    std.debug.print("    time1: {} 纳秒\n", .{time1.nanos});
    std.debug.print("    time2: {} 纳秒\n", .{time2.nanos});
    std.debug.print("    time3: {} 纳秒\n", .{time3.nanos});

    std.debug.print("  时间关系:\n", .{});
    std.debug.print("    time2.isAfter(time1): {}\n", .{time2.isAfter(time1)});
    std.debug.print("    time3.isAfter(time2): {}\n", .{time3.isAfter(time2)});
    std.debug.print("    time1.isBefore(time3): {}\n", .{time1.isBefore(time3)});

    const diff_1_2 = time2.sub(time1);
    const diff_2_3 = time3.sub(time2);

    std.debug.print("  时间差:\n", .{});
    std.debug.print("    time2 - time1: {} 纳秒\n", .{diff_1_2.asNanos()});
    std.debug.print("    time3 - time2: {} 纳秒\n", .{diff_2_3.asNanos()});

    std.debug.print("\n9. Duration特殊值演示\n", .{});

    const zero_duration = zokio.timer.Duration.fromNanos(0);
    const max_duration = zokio.timer.Duration.fromNanos(std.math.maxInt(u64));

    std.debug.print("  零时长:\n", .{});
    std.debug.print("    isZero(): {}\n", .{zero_duration.isZero()});
    std.debug.print("    纳秒: {}\n", .{zero_duration.asNanos()});

    std.debug.print("  最大时长:\n", .{});
    std.debug.print("    纳秒: {}\n", .{max_duration.asNanos()});
    std.debug.print("    秒: {}\n", .{max_duration.asSecs()});
    std.debug.print("    年(约): {d:.1}\n", .{@as(f64, @floatFromInt(max_duration.asSecs())) / (365.25 * 24 * 3600)});

    std.debug.print("\n10. 性能基准测试\n", .{});

    // 测试Instant.now()的性能
    const bench_start = zokio.timer.Instant.now();
    const iterations = 1000000;

    for (0..iterations) |_| {
        _ = zokio.timer.Instant.now();
    }

    const bench_end = zokio.timer.Instant.now();
    const bench_duration = bench_end.sub(bench_start);
    const avg_time_per_call = bench_duration.asNanos() / iterations;

    std.debug.print("  Instant.now() 性能测试:\n", .{});
    std.debug.print("    总调用次数: {}\n", .{iterations});
    std.debug.print("    总耗时: {}微秒\n", .{bench_duration.asMicros()});
    std.debug.print("    平均每次调用: {} 纳秒\n", .{avg_time_per_call});
    std.debug.print("    每秒可调用: {d:.0} 次\n", .{1_000_000_000.0 / @as(f64, @floatFromInt(avg_time_per_call))});

    std.debug.print("\n✓ 定时器和时间管理演示完成\n", .{});
}
