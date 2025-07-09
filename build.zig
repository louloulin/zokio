const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 特性开关配置
    const enable_metrics = b.option(bool, "metrics", "启用运行时指标收集") orelse true;
    const enable_tracing = b.option(bool, "tracing", "启用分布式追踪") orelse false;
    const enable_numa = b.option(bool, "numa", "启用NUMA感知优化") orelse true;
    const enable_io_uring = b.option(bool, "io_uring", "启用io_uring支持") orelse true;
    const enable_simd = b.option(bool, "simd", "启用SIMD优化") orelse true;
    const debug_mode = b.option(bool, "debug", "启用调试模式") orelse false;

    // 基准测试配置选择
    const benchmark_config = b.option([]const u8, "benchmark_config", "基准测试配置选择") orelse "memory_optimized";

    // 编译时配置选项
    const options = b.addOptions();
    options.addOption(bool, "enable_metrics", enable_metrics);
    options.addOption(bool, "enable_tracing", enable_tracing);
    options.addOption(bool, "enable_numa", enable_numa);
    options.addOption(bool, "enable_io_uring", enable_io_uring);
    options.addOption(bool, "enable_simd", enable_simd);
    options.addOption(bool, "debug_mode", debug_mode);
    options.addOption(?[]const u8, "benchmark_config", benchmark_config);

    // libxev依赖
    const libxev = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    // 主库构建
    const lib = b.addStaticLibrary(.{
        .name = "zokio",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addOptions("config", options);
    lib.root_module.addImport("libxev", libxev.module("xev"));

    // 安装库
    b.installArtifact(lib);

    // 单元测试
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addOptions("config", options);
    unit_tests.root_module.addImport("libxev", libxev.module("xev"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "运行单元测试");
    test_step.dependOn(&run_unit_tests.step);

    // 集成测试
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addOptions("config", options);
    integration_tests.root_module.addImport("libxev", libxev.module("xev"));
    integration_tests.root_module.addImport("zokio", lib.root_module);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "运行集成测试");
    integration_test_step.dependOn(&run_integration_tests.step);

    // libxev集成测试
    const libxev_tests = b.addTest(.{
        .root_source_file = b.path("tests/libxev_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    libxev_tests.root_module.addOptions("config", options);
    libxev_tests.root_module.addImport("libxev", libxev.module("xev"));
    libxev_tests.root_module.addImport("zokio", lib.root_module);

    const run_libxev_tests = b.addRunArtifact(libxev_tests);
    const libxev_test_step = b.step("test-libxev", "运行libxev集成测试");
    libxev_test_step.dependOn(&run_libxev_tests.step);

    // 真实性验证测试
    const real_impl_tests = b.addTest(.{
        .root_source_file = b.path("test_real_implementation.zig"),
        .target = target,
        .optimize = optimize,
    });
    real_impl_tests.root_module.addOptions("config", options);
    real_impl_tests.root_module.addImport("libxev", libxev.module("xev"));
    real_impl_tests.root_module.addImport("zokio", lib.root_module);

    const run_real_impl_tests = b.addRunArtifact(real_impl_tests);
    const real_impl_test_step = b.step("test-real", "运行真实性验证测试");

    // await_fn非阻塞测试
    const await_fn_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_await_fn_no_blocking.zig"),
        .target = target,
        .optimize = optimize,
    });
    await_fn_tests.root_module.addOptions("config", options);
    await_fn_tests.root_module.addImport("libxev", libxev.module("xev"));
    await_fn_tests.root_module.addImport("zokio", lib.root_module);

    const run_await_fn_tests = b.addRunArtifact(await_fn_tests);
    const await_fn_test_step = b.step("test-await-fn", "运行await_fn非阻塞测试");
    await_fn_test_step.dependOn(&run_await_fn_tests.step);

    // CompletionBridge修复测试
    const completion_bridge_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_completion_bridge_fix.zig"),
        .target = target,
        .optimize = optimize,
    });
    completion_bridge_tests.root_module.addOptions("config", options);
    completion_bridge_tests.root_module.addImport("libxev", libxev.module("xev"));
    completion_bridge_tests.root_module.addImport("zokio", lib.root_module);

    const run_completion_bridge_tests = b.addRunArtifact(completion_bridge_tests);
    const completion_bridge_test_step = b.step("test-completion-bridge", "运行CompletionBridge修复测试");
    completion_bridge_test_step.dependOn(&run_completion_bridge_tests.step);

    // 异步文件I/O修复测试
    const async_file_io_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_async_file_io_fix.zig"),
        .target = target,
        .optimize = optimize,
    });
    async_file_io_tests.root_module.addOptions("config", options);
    async_file_io_tests.root_module.addImport("libxev", libxev.module("xev"));
    async_file_io_tests.root_module.addImport("zokio", lib.root_module);

    const run_async_file_io_tests = b.addRunArtifact(async_file_io_tests);
    const async_file_io_test_step = b.step("test-async-file-io", "运行异步文件I/O修复测试");
    async_file_io_test_step.dependOn(&run_async_file_io_tests.step);

    // libxev集成验证测试 (使用新的测试文件)
    const libxev_integration_new_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_libxev_integration.zig"),
        .target = target,
        .optimize = optimize,
    });
    libxev_integration_new_tests.root_module.addOptions("config", options);
    libxev_integration_new_tests.root_module.addImport("libxev", libxev.module("xev"));
    libxev_integration_new_tests.root_module.addImport("zokio", lib.root_module);

    const run_libxev_integration_new_tests = b.addRunArtifact(libxev_integration_new_tests);
    const libxev_integration_new_test_step = b.step("test-libxev-new", "运行新的libxev集成验证测试");
    libxev_integration_new_test_step.dependOn(&run_libxev_integration_new_tests.step);

    // 真实I/O性能测试
    const real_io_performance_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_real_io_performance.zig"),
        .target = target,
        .optimize = optimize,
    });
    real_io_performance_tests.root_module.addOptions("config", options);
    real_io_performance_tests.root_module.addImport("libxev", libxev.module("xev"));
    real_io_performance_tests.root_module.addImport("zokio", lib.root_module);

    const run_real_io_performance_tests = b.addRunArtifact(real_io_performance_tests);
    const real_io_performance_test_step = b.step("test-real-io-perf", "运行真实I/O性能测试");
    real_io_performance_test_step.dependOn(&run_real_io_performance_tests.step);

    // HTTP压测工具
    const http_benchmark = b.addExecutable(.{
        .name = "http_benchmark",
        .root_source_file = b.path("tools/http_benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    http_benchmark.root_module.addOptions("config", options);
    http_benchmark.root_module.addImport("libxev", libxev.module("xev"));
    http_benchmark.root_module.addImport("zokio", lib.root_module);

    const run_http_benchmark = b.addRunArtifact(http_benchmark);
    const http_benchmark_step = b.step("http-benchmark", "🚀 运行HTTP服务器压测工具");
    http_benchmark_step.dependOn(&run_http_benchmark.step);

    // 简化HTTP测试服务器
    const simple_test_server = b.addExecutable(.{
        .name = "simple_test_server",
        .root_source_file = b.path("tools/simple_test_server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_simple_test_server = b.addRunArtifact(simple_test_server);
    const simple_test_server_step = b.step("test-server", "🚀 运行简化HTTP测试服务器");
    simple_test_server_step.dependOn(&run_simple_test_server.step);

    // 简化HTTP压测工具
    const simple_benchmark = b.addExecutable(.{
        .name = "simple_benchmark",
        .root_source_file = b.path("tools/simple_benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_simple_benchmark = b.addRunArtifact(simple_benchmark);
    const simple_benchmark_step = b.step("http-perf-analysis", "🔍 运行HTTP性能分析和压测");
    simple_benchmark_step.dependOn(&run_simple_benchmark.step);

    // 并发HTTP服务器
    const concurrent_http_server = b.addExecutable(.{
        .name = "concurrent_http_server",
        .root_source_file = b.path("examples/concurrent_http_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    concurrent_http_server.root_module.addOptions("config", options);
    concurrent_http_server.root_module.addImport("libxev", libxev.module("xev"));
    concurrent_http_server.root_module.addImport("zokio", lib.root_module);

    const run_concurrent_http_server = b.addRunArtifact(concurrent_http_server);
    const concurrent_http_server_step = b.step("concurrent-http-server", "🚀 运行并发HTTP服务器 (阶段1优化)");
    concurrent_http_server_step.dependOn(&run_concurrent_http_server.step);

    // 阶段1并发服务器
    const stage1_server = b.addExecutable(.{
        .name = "stage1_concurrent_server",
        .root_source_file = b.path("examples/stage1_concurrent_server.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_stage1_server = b.addRunArtifact(stage1_server);
    const stage1_server_step = b.step("stage1-server", "🚀 运行阶段1并发HTTP服务器性能测试");
    stage1_server_step.dependOn(&run_stage1_server.step);

    // 阶段2异步I/O服务器
    const stage2_server = b.addExecutable(.{
        .name = "stage2_async_io_server",
        .root_source_file = b.path("examples/stage2_async_io_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    stage2_server.root_module.addOptions("config", options);
    stage2_server.root_module.addImport("libxev", libxev.module("xev"));
    stage2_server.root_module.addImport("zokio", lib.root_module);

    const run_stage2_server = b.addRunArtifact(stage2_server);
    const stage2_server_step = b.step("stage2-server", "🚀 运行阶段2异步I/O HTTP服务器");
    stage2_server_step.dependOn(&run_stage2_server.step);

    // 阶段2性能测试
    const stage2_perf_test = b.addExecutable(.{
        .name = "stage2_performance_test",
        .root_source_file = b.path("tools/stage2_performance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    stage2_perf_test.root_module.addOptions("config", options);
    stage2_perf_test.root_module.addImport("libxev", libxev.module("xev"));
    stage2_perf_test.root_module.addImport("zokio", lib.root_module);

    const run_stage2_perf_test = b.addRunArtifact(stage2_perf_test);
    const stage2_perf_test_step = b.step("stage2-test", "🚀 运行阶段2异步I/O性能测试");
    stage2_perf_test_step.dependOn(&run_stage2_perf_test.step);

    real_impl_test_step.dependOn(&run_real_impl_tests.step);

    // 核心修复验证测试
    const core_fixes_tests = b.addTest(.{
        .root_source_file = b.path("test_core_fixes.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_fixes_tests.root_module.addOptions("config", options);
    core_fixes_tests.root_module.addImport("libxev", libxev.module("xev"));
    core_fixes_tests.root_module.addImport("zokio", lib.root_module);

    const run_core_fixes_tests = b.addRunArtifact(core_fixes_tests);
    const core_fixes_test_step = b.step("test-fixes", "运行核心修复验证测试");
    core_fixes_test_step.dependOn(&run_core_fixes_tests.step);

    // libxev 集成测试
    const libxev_integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/libxev_integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    libxev_integration_tests.root_module.addOptions("config", options);
    libxev_integration_tests.root_module.addImport("libxev", libxev.module("xev"));
    libxev_integration_tests.root_module.addImport("zokio", lib.root_module);

    const run_libxev_integration_tests = b.addRunArtifact(libxev_integration_tests);
    const libxev_integration_test_step = b.step("test-libxev-integration", "运行 libxev 集成测试");
    libxev_integration_test_step.dependOn(&run_libxev_integration_tests.step);

    // Zokio 7.0 事件驱动核心测试
    const event_driven_core_tests = b.addTest(.{
        .root_source_file = b.path("test_event_driven_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    event_driven_core_tests.root_module.addOptions("config", options);
    event_driven_core_tests.root_module.addImport("libxev", libxev.module("xev"));
    event_driven_core_tests.root_module.addImport("zokio", lib.root_module);

    const run_event_driven_core_tests = b.addRunArtifact(event_driven_core_tests);
    const event_driven_core_test_step = b.step("test-event-driven", "运行 Zokio 7.0 事件驱动核心测试");
    event_driven_core_test_step.dependOn(&run_event_driven_core_tests.step);

    // Zokio 7.1 无限循环修复验证测试
    const infinite_loop_fix_tests = b.addTest(.{
        .root_source_file = b.path("test_infinite_loop_fix.zig"),
        .target = target,
        .optimize = optimize,
    });
    infinite_loop_fix_tests.root_module.addOptions("config", options);
    infinite_loop_fix_tests.root_module.addImport("libxev", libxev.module("xev"));
    infinite_loop_fix_tests.root_module.addImport("zokio", lib.root_module);

    const run_infinite_loop_fix_tests = b.addRunArtifact(infinite_loop_fix_tests);
    const infinite_loop_fix_test_step = b.step("test-loop-fix", "运行 Zokio 7.1 无限循环修复验证测试");
    infinite_loop_fix_test_step.dependOn(&run_infinite_loop_fix_tests.step);

    // Zokio 7.2 全面单元测试
    const comprehensive_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/comprehensive_unit_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    comprehensive_unit_tests.root_module.addOptions("config", options);
    comprehensive_unit_tests.root_module.addImport("libxev", libxev.module("xev"));
    comprehensive_unit_tests.root_module.addImport("zokio", lib.root_module);

    const run_comprehensive_unit_tests = b.addRunArtifact(comprehensive_unit_tests);
    const comprehensive_unit_test_step = b.step("test-unit", "运行 Zokio 7.2 全面单元测试");
    comprehensive_unit_test_step.dependOn(&run_comprehensive_unit_tests.step);

    // Zokio 7.2 集成测试
    const comprehensive_integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    comprehensive_integration_tests.root_module.addOptions("config", options);
    comprehensive_integration_tests.root_module.addImport("libxev", libxev.module("xev"));
    comprehensive_integration_tests.root_module.addImport("zokio", lib.root_module);

    const run_comprehensive_integration_tests = b.addRunArtifact(comprehensive_integration_tests);
    const comprehensive_integration_test_step = b.step("test-integration-new", "运行 Zokio 7.2 集成测试");
    comprehensive_integration_test_step.dependOn(&run_comprehensive_integration_tests.step);

    // Zokio 7.2 性能基准测试
    const performance_benchmarks = b.addTest(.{
        .root_source_file = b.path("tests/performance_benchmarks.zig"),
        .target = target,
        .optimize = optimize,
    });
    performance_benchmarks.root_module.addOptions("config", options);
    performance_benchmarks.root_module.addImport("libxev", libxev.module("xev"));
    performance_benchmarks.root_module.addImport("zokio", lib.root_module);

    const run_performance_benchmarks = b.addRunArtifact(performance_benchmarks);
    const performance_benchmark_step = b.step("test-performance", "运行 Zokio 7.2 性能基准测试");
    performance_benchmark_step.dependOn(&run_performance_benchmarks.step);

    // Zokio 7.3 I/O 性能基准测试
    const io_performance_tests = b.addTest(.{
        .root_source_file = b.path("tests/io_performance_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    io_performance_tests.root_module.addOptions("config", options);
    io_performance_tests.root_module.addImport("libxev", libxev.module("xev"));
    io_performance_tests.root_module.addImport("zokio", lib.root_module);

    const run_io_performance_tests = b.addRunArtifact(io_performance_tests);
    const io_performance_test_step = b.step("test-io-performance", "运行 Zokio 7.3 I/O 性能基准测试");
    io_performance_test_step.dependOn(&run_io_performance_tests.step);

    // Zokio 7.2 全面测试套件
    const comprehensive_test_step = b.step("test-comprehensive", "运行 Zokio 7.2 全面测试套件");
    comprehensive_test_step.dependOn(&run_comprehensive_unit_tests.step);
    comprehensive_test_step.dependOn(&run_comprehensive_integration_tests.step);
    comprehensive_test_step.dependOn(&run_performance_benchmarks.step);

    // Zokio 7.3 完整测试套件（包含 I/O 性能测试）
    const complete_test_step = b.step("test-complete", "运行 Zokio 7.3 完整测试套件");
    complete_test_step.dependOn(&run_comprehensive_unit_tests.step);
    complete_test_step.dependOn(&run_comprehensive_integration_tests.step);
    complete_test_step.dependOn(&run_performance_benchmarks.step);
    complete_test_step.dependOn(&run_io_performance_tests.step);

    // libxev可用性测试
    const libxev_availability_tests = b.addTest(.{
        .root_source_file = b.path("tests/libxev_availability_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    libxev_availability_tests.root_module.addImport("libxev", libxev.module("xev"));

    const run_libxev_availability_tests = b.addRunArtifact(libxev_availability_tests);
    const libxev_availability_test_step = b.step("test-libxev-availability", "测试libxev可用性");
    libxev_availability_test_step.dependOn(&run_libxev_availability_tests.step);

    // 简单libxev测试
    const simple_libxev_tests = b.addTest(.{
        .root_source_file = b.path("tests/simple_libxev_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_libxev_tests.root_module.addOptions("config", options);
    simple_libxev_tests.root_module.addImport("libxev", libxev.module("xev"));
    simple_libxev_tests.root_module.addImport("zokio", lib.root_module);

    const run_simple_libxev_tests = b.addRunArtifact(simple_libxev_tests);
    const simple_libxev_test_step = b.step("test-simple-libxev", "运行简单libxev测试");
    simple_libxev_test_step.dependOn(&run_simple_libxev_tests.step);

    // 高性能调度器测试
    const high_perf_scheduler_tests = b.addTest(.{
        .root_source_file = b.path("tests/high_performance_scheduler_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    high_perf_scheduler_tests.root_module.addOptions("config", options);
    high_perf_scheduler_tests.root_module.addImport("libxev", libxev.module("xev"));
    high_perf_scheduler_tests.root_module.addImport("zokio", lib.root_module);

    const run_high_perf_scheduler_tests = b.addRunArtifact(high_perf_scheduler_tests);
    const high_perf_scheduler_test_step = b.step("test-high-perf-scheduler", "运行高性能调度器测试");
    high_perf_scheduler_test_step.dependOn(&run_high_perf_scheduler_tests.step);

    // 基准测试
    const benchmarks = b.addExecutable(.{
        .name = "benchmarks",
        .root_source_file = b.path("benchmarks/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    benchmarks.root_module.addOptions("config", options);
    benchmarks.root_module.addImport("libxev", libxev.module("xev"));
    benchmarks.root_module.addImport("zokio", lib.root_module);

    const run_benchmarks = b.addRunArtifact(benchmarks);
    const benchmark_step = b.step("benchmark", "运行性能基准测试");
    benchmark_step.dependOn(&run_benchmarks.step);

    // 示例程序
    const examples = [_][]const u8{
        "hello_world",
        "tcp_echo_server",
        "http_server",
        "simple_http_server",
        "simple_http_test",
        "http_demo_test",
        "simple_http_verify",
        "file_processor",
        "async_await_demo",
        "async_block_demo",
        "async_fs_demo",
        "timer_demo",
        "tracing_demo",
        "advanced_sync_demo",
        "plan_api_demo",
        "complex_async_await_demo",
        "real_async_await_demo",
        "libxev_demo",
        "high_performance_scheduler_demo",
        "memory_demo",
        "simple_memory_demo",
        "enhanced_async_demo",
        "network_demo",
        "fs_demo",
        "benchmark_demo",
        "tokio_stress_test",
        "tokio_test_simple",
    };

    for (examples) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
            .target = target,
            .optimize = optimize,
        });
        example.root_module.addOptions("config", options);
        example.root_module.addImport("libxev", libxev.module("xev"));
        example.root_module.addImport("zokio", lib.root_module);

        const install_example = b.addInstallArtifact(example, .{});
        const example_step = b.step(b.fmt("example-{s}", .{example_name}), b.fmt("构建{s}示例", .{example_name}));
        example_step.dependOn(&install_example.step);

        // 🌐 特别的HTTP服务器演示
        if (std.mem.eql(u8, example_name, "http_server")) {
            const http_demo_run = b.addRunArtifact(example);
            const http_demo_step = b.step("http-demo", "🚀 运行革命性HTTP服务器演示 (32B+ ops/sec)");
            http_demo_step.dependOn(&http_demo_run.step);
        }

        // 🚀 简化的HTTP服务器演示
        if (std.mem.eql(u8, example_name, "simple_http_server")) {
            const simple_http_demo_run = b.addRunArtifact(example);
            const simple_http_demo_step = b.step("simple-http-demo", "🚀 运行简化异步HTTP服务器演示 (基于async_fn/await_fn)");
            simple_http_demo_step.dependOn(&simple_http_demo_run.step);
        }

        // 🧪 HTTP服务器测试
        if (std.mem.eql(u8, example_name, "simple_http_test")) {
            const http_test_run = b.addRunArtifact(example);
            const http_test_step = b.step("http-test", "🧪 运行HTTP服务器基础功能测试");
            http_test_step.dependOn(&http_test_run.step);
        }

        // 🎯 HTTP服务器演示测试
        if (std.mem.eql(u8, example_name, "http_demo_test")) {
            const http_demo_test_run = b.addRunArtifact(example);
            const http_demo_test_step = b.step("http-demo-test", "🎯 运行HTTP服务器完整演示测试");
            http_demo_test_step.dependOn(&http_demo_test_run.step);
        }

        // 🔍 HTTP服务器简化验证
        if (std.mem.eql(u8, example_name, "simple_http_verify")) {
            const http_verify_run = b.addRunArtifact(example);
            const http_verify_step = b.step("http-verify", "🔍 运行HTTP服务器简化验证");
            http_verify_step.dependOn(&http_verify_run.step);
        }
    }

    // 文档生成
    const docs = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    docs.root_module.addOptions("config", options);
    docs.root_module.addImport("libxev", libxev.module("xev"));

    const docs_step = b.step("docs", "生成API文档");
    const docs_install = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&docs_install.step);
    docs_install.step.dependOn(&docs.step);

    // 格式化检查
    const fmt_step = b.step("fmt", "检查代码格式");
    const fmt_check = b.addFmt(.{
        .paths = &[_][]const u8{ "src", "tests", "examples", "benchmarks" },
        .check = true,
    });
    fmt_step.dependOn(&fmt_check.step);

    // 高性能压力测试
    const high_perf_stress = b.addExecutable(.{
        .name = "high_performance_stress",
        .root_source_file = b.path("benchmarks/high_performance_stress.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    high_perf_stress.root_module.addImport("zokio", lib.root_module);
    high_perf_stress.root_module.addOptions("config", options);
    high_perf_stress.root_module.addImport("libxev", libxev.module("xev"));

    const high_perf_stress_cmd = b.addRunArtifact(high_perf_stress);
    const high_perf_stress_step = b.step("stress-high-perf", "运行高性能压力测试");
    high_perf_stress_step.dependOn(&high_perf_stress_cmd.step);

    // 网络压力测试
    const network_stress = b.addExecutable(.{
        .name = "network_stress",
        .root_source_file = b.path("benchmarks/network_stress.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    network_stress.root_module.addImport("zokio", lib.root_module);
    network_stress.root_module.addOptions("config", options);
    network_stress.root_module.addImport("libxev", libxev.module("xev"));

    const network_stress_cmd = b.addRunArtifact(network_stress);
    const network_stress_step = b.step("stress-network", "运行网络压力测试");
    network_stress_step.dependOn(&network_stress_cmd.step);

    // async/await专门压力测试
    const async_await_stress = b.addExecutable(.{
        .name = "async_await_benchmark",
        .root_source_file = b.path("benchmarks/async_await_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    async_await_stress.root_module.addImport("zokio", lib.root_module);
    async_await_stress.root_module.addOptions("config", options);
    async_await_stress.root_module.addImport("libxev", libxev.module("xev"));

    const async_await_stress_cmd = b.addRunArtifact(async_await_stress);
    const async_await_stress_step = b.step("stress-async-await", "运行async/await专门压力测试");
    async_await_stress_step.dependOn(&async_await_stress_cmd.step);

    // 真实异步压力测试
    const real_async_stress = b.addExecutable(.{
        .name = "real_async_benchmark",
        .root_source_file = b.path("benchmarks/real_async_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    real_async_stress.root_module.addImport("zokio", lib.root_module);
    real_async_stress.root_module.addOptions("config", options);
    real_async_stress.root_module.addImport("libxev", libxev.module("xev"));

    const real_async_stress_cmd = b.addRunArtifact(real_async_stress);
    const real_async_stress_step = b.step("stress-real-async", "运行真实异步压力测试");
    real_async_stress_step.dependOn(&real_async_stress_cmd.step);

    // Tokio vs Zokio直接对比测试
    const tokio_vs_zokio = b.addExecutable(.{
        .name = "tokio_vs_zokio_comparison",
        .root_source_file = b.path("benchmarks/tokio_vs_zokio_direct_comparison.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    tokio_vs_zokio.root_module.addImport("zokio", lib.root_module);
    tokio_vs_zokio.root_module.addOptions("config", options);
    tokio_vs_zokio.root_module.addImport("libxev", libxev.module("xev"));

    const tokio_vs_zokio_cmd = b.addRunArtifact(tokio_vs_zokio);
    const tokio_vs_zokio_step = b.step("tokio-vs-zokio", "运行Tokio vs Zokio直接性能对比");
    tokio_vs_zokio_step.dependOn(&tokio_vs_zokio_cmd.step);

    // 优化的Tokio vs Zokio对比测试
    const optimized_tokio_vs_zokio = b.addExecutable(.{
        .name = "optimized_tokio_vs_zokio_comparison",
        .root_source_file = b.path("benchmarks/optimized_tokio_vs_zokio_comparison.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    optimized_tokio_vs_zokio.root_module.addImport("zokio", lib.root_module);
    optimized_tokio_vs_zokio.root_module.addOptions("config", options);
    optimized_tokio_vs_zokio.root_module.addImport("libxev", libxev.module("xev"));

    const optimized_tokio_vs_zokio_cmd = b.addRunArtifact(optimized_tokio_vs_zokio);
    const optimized_tokio_vs_zokio_step = b.step("optimized-tokio-vs-zokio", "运行优化的Tokio vs Zokio对比测试");
    optimized_tokio_vs_zokio_step.dependOn(&optimized_tokio_vs_zokio_cmd.step);

    // 简化的优化测试
    const simple_optimized_test = b.addExecutable(.{
        .name = "simple_optimized_test",
        .root_source_file = b.path("benchmarks/simple_optimized_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const simple_optimized_test_cmd = b.addRunArtifact(simple_optimized_test);
    const simple_optimized_test_step = b.step("simple-optimized", "运行简化的优化性能测试");
    simple_optimized_test_step.dependOn(&simple_optimized_test_cmd.step);

    // 简化的Zokio整体测试
    const simplified_zokio_test = b.addExecutable(.{
        .name = "simplified_zokio_test",
        .root_source_file = b.path("benchmarks/simplified_zokio_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    simplified_zokio_test.root_module.addImport("zokio", lib.root_module);
    simplified_zokio_test.root_module.addOptions("config", options);
    simplified_zokio_test.root_module.addImport("libxev", libxev.module("xev"));

    const simplified_zokio_test_cmd = b.addRunArtifact(simplified_zokio_test);
    const simplified_zokio_test_step = b.step("simplified-zokio", "运行简化的Zokio整体性能测试");
    simplified_zokio_test_step.dependOn(&simplified_zokio_test_cmd.step);

    // 高性能运行时测试
    const high_performance_runtime_test = b.addExecutable(.{
        .name = "high_performance_runtime_test",
        .root_source_file = b.path("benchmarks/high_performance_runtime_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    high_performance_runtime_test.root_module.addImport("zokio", lib.root_module);
    high_performance_runtime_test.root_module.addOptions("config", options);
    high_performance_runtime_test.root_module.addImport("libxev", libxev.module("xev"));

    const high_performance_runtime_test_cmd = b.addRunArtifact(high_performance_runtime_test);
    const high_performance_runtime_test_step = b.step("high-perf-runtime", "运行高性能运行时测试");
    high_performance_runtime_test_step.dependOn(&high_performance_runtime_test_cmd.step);

    // 简单运行时测试
    const simple_runtime_test = b.addExecutable(.{
        .name = "simple_runtime_test",
        .root_source_file = b.path("benchmarks/simple_runtime_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    simple_runtime_test.root_module.addImport("zokio", lib.root_module);
    simple_runtime_test.root_module.addOptions("config", options);
    simple_runtime_test.root_module.addImport("libxev", libxev.module("xev"));

    const simple_runtime_test_cmd = b.addRunArtifact(simple_runtime_test);
    const simple_runtime_test_step = b.step("simple-runtime", "运行简单运行时测试");
    simple_runtime_test_step.dependOn(&simple_runtime_test_cmd.step);

    // 调试运行时测试
    const debug_runtime_test = b.addExecutable(.{
        .name = "debug_runtime_test",
        .root_source_file = b.path("debug_runtime_test.zig"),
        .target = target,
        .optimize = .Debug,
    });
    debug_runtime_test.root_module.addImport("zokio", lib.root_module);
    debug_runtime_test.root_module.addOptions("config", options);
    debug_runtime_test.root_module.addImport("libxev", libxev.module("xev"));

    const debug_runtime_test_cmd = b.addRunArtifact(debug_runtime_test);
    const debug_runtime_test_step = b.step("debug-runtime", "运行调试运行时测试");
    debug_runtime_test_step.dependOn(&debug_runtime_test_cmd.step);

    // 基础运行时验证测试
    const basic_runtime_verification = b.addExecutable(.{
        .name = "basic_runtime_verification",
        .root_source_file = b.path("benchmarks/basic_runtime_verification.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    basic_runtime_verification.root_module.addImport("zokio", lib.root_module);
    basic_runtime_verification.root_module.addOptions("config", options);
    basic_runtime_verification.root_module.addImport("libxev", libxev.module("xev"));

    const basic_runtime_verification_cmd = b.addRunArtifact(basic_runtime_verification);
    const basic_runtime_verification_step = b.step("verify-runtime", "运行基础运行时验证测试");
    basic_runtime_verification_step.dependOn(&basic_runtime_verification_cmd.step);

    // 真正使用Zokio核心API的压测
    const real_zokio_api_benchmark = b.addExecutable(.{
        .name = "real_zokio_api_benchmark",
        .root_source_file = b.path("benchmarks/real_zokio_api_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    real_zokio_api_benchmark.root_module.addImport("zokio", lib.root_module);
    real_zokio_api_benchmark.root_module.addOptions("config", options);
    real_zokio_api_benchmark.root_module.addImport("libxev", libxev.module("xev"));

    const real_zokio_api_benchmark_cmd = b.addRunArtifact(real_zokio_api_benchmark);
    const real_zokio_api_benchmark_step = b.step("real-api-bench", "运行真正使用Zokio核心API的压测");
    real_zokio_api_benchmark_step.dependOn(&real_zokio_api_benchmark_cmd.step);

    // 简化的真实API测试
    const simple_real_api_test = b.addExecutable(.{
        .name = "simple_real_api_test",
        .root_source_file = b.path("benchmarks/simple_real_api_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    simple_real_api_test.root_module.addImport("zokio", lib.root_module);
    simple_real_api_test.root_module.addOptions("config", options);
    simple_real_api_test.root_module.addImport("libxev", libxev.module("xev"));

    const simple_real_api_test_cmd = b.addRunArtifact(simple_real_api_test);
    const simple_real_api_test_step = b.step("simple-real-api", "运行简化的真实API测试");
    simple_real_api_test_step.dependOn(&simple_real_api_test_cmd.step);

    // 最简化的spawn测试
    const minimal_spawn_test = b.addExecutable(.{
        .name = "minimal_spawn_test",
        .root_source_file = b.path("benchmarks/minimal_spawn_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    minimal_spawn_test.root_module.addImport("zokio", lib.root_module);
    minimal_spawn_test.root_module.addOptions("config", options);
    minimal_spawn_test.root_module.addImport("libxev", libxev.module("xev"));

    const minimal_spawn_test_cmd = b.addRunArtifact(minimal_spawn_test);
    const minimal_spawn_test_step = b.step("minimal-spawn", "运行最简化的spawn测试");
    minimal_spawn_test_step.dependOn(&minimal_spawn_test_cmd.step);

    // 简化的性能对比测试
    const simple_comparison = b.addExecutable(.{
        .name = "simple_comparison",
        .root_source_file = b.path("benchmarks/simple_comparison.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    simple_comparison.root_module.addImport("zokio", lib.root_module);
    simple_comparison.root_module.addOptions("config", options);
    simple_comparison.root_module.addImport("libxev", libxev.module("xev"));

    const simple_comparison_cmd = b.addRunArtifact(simple_comparison);
    const simple_comparison_step = b.step("simple-comparison", "运行简化的性能对比测试");
    simple_comparison_step.dependOn(&simple_comparison_cmd.step);

    // 内存分配性能专项测试
    const memory_perf_test = b.addExecutable(.{
        .name = "memory_performance_test",
        .root_source_file = b.path("benchmarks/memory_performance_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    memory_perf_test.root_module.addImport("zokio", lib.root_module);
    memory_perf_test.root_module.addOptions("config", options);
    memory_perf_test.root_module.addImport("libxev", libxev.module("xev"));

    const memory_perf_test_cmd = b.addRunArtifact(memory_perf_test);
    const memory_perf_test_step = b.step("memory-perf", "运行内存分配性能专项测试");
    memory_perf_test_step.dependOn(&memory_perf_test_cmd.step);

    // 简化的内存分配测试
    const simple_memory_test = b.addExecutable(.{
        .name = "simple_memory_test",
        .root_source_file = b.path("benchmarks/simple_memory_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    simple_memory_test.root_module.addImport("zokio", lib.root_module);
    simple_memory_test.root_module.addOptions("config", options);
    simple_memory_test.root_module.addImport("libxev", libxev.module("xev"));

    const simple_memory_test_cmd = b.addRunArtifact(simple_memory_test);
    const simple_memory_test_step = b.step("simple-memory", "运行简化的内存分配性能测试");
    simple_memory_test_step.dependOn(&simple_memory_test_cmd.step);

    // 优化内存分配器测试
    const optimized_memory_test = b.addExecutable(.{
        .name = "optimized_memory_test",
        .root_source_file = b.path("benchmarks/optimized_memory_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    optimized_memory_test.root_module.addImport("zokio", lib.root_module);
    optimized_memory_test.root_module.addOptions("config", options);
    optimized_memory_test.root_module.addImport("libxev", libxev.module("xev"));

    const optimized_memory_test_cmd = b.addRunArtifact(optimized_memory_test);
    const optimized_memory_test_step = b.step("optimized-memory", "运行优化内存分配器性能测试");
    optimized_memory_test_step.dependOn(&optimized_memory_test_cmd.step);

    // 扩展内存分配器测试 (修复大对象问题)
    const extended_memory_test = b.addExecutable(.{
        .name = "extended_memory_test",
        .root_source_file = b.path("benchmarks/extended_memory_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    extended_memory_test.root_module.addImport("zokio", lib.root_module);
    extended_memory_test.root_module.addOptions("config", options);
    extended_memory_test.root_module.addImport("libxev", libxev.module("xev"));

    const extended_memory_test_cmd = b.addRunArtifact(extended_memory_test);
    const extended_memory_test_step = b.step("extended-memory", "运行扩展内存分配器性能测试");
    extended_memory_test_step.dependOn(&extended_memory_test_cmd.step);

    // 智能统一内存分配器测试
    const smart_allocator_test = b.addExecutable(.{
        .name = "smart_allocator_test",
        .root_source_file = b.path("benchmarks/smart_allocator_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    smart_allocator_test.root_module.addImport("zokio", lib.root_module);
    smart_allocator_test.root_module.addOptions("config", options);
    smart_allocator_test.root_module.addImport("libxev", libxev.module("xev"));

    const smart_allocator_test_cmd = b.addRunArtifact(smart_allocator_test);
    const smart_allocator_test_step = b.step("smart-memory", "运行智能统一内存分配器测试");
    smart_allocator_test_step.dependOn(&smart_allocator_test_cmd.step);

    // 高性能智能分配器测试 (性能修复版)
    const fast_smart_allocator_test = b.addExecutable(.{
        .name = "fast_smart_allocator_test",
        .root_source_file = b.path("benchmarks/fast_smart_allocator_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    fast_smart_allocator_test.root_module.addImport("zokio", lib.root_module);
    fast_smart_allocator_test.root_module.addOptions("config", options);
    fast_smart_allocator_test.root_module.addImport("libxev", libxev.module("xev"));

    const fast_smart_allocator_test_cmd = b.addRunArtifact(fast_smart_allocator_test);
    const fast_smart_allocator_test_step = b.step("fast-memory", "运行高性能智能分配器测试");
    fast_smart_allocator_test_step.dependOn(&fast_smart_allocator_test_cmd.step);

    // 统一内存管理接口测试 (P1阶段)
    const unified_memory_test = b.addExecutable(.{
        .name = "unified_memory_test",
        .root_source_file = b.path("benchmarks/unified_memory_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    unified_memory_test.root_module.addImport("zokio", lib.root_module);
    unified_memory_test.root_module.addOptions("config", options);
    unified_memory_test.root_module.addImport("libxev", libxev.module("xev"));

    const unified_memory_test_cmd = b.addRunArtifact(unified_memory_test);
    const unified_memory_test_step = b.step("unified-memory", "运行统一内存管理接口测试");
    unified_memory_test_step.dependOn(&unified_memory_test_cmd.step);

    // P2阶段性能优化验证测试
    const p2_optimization_test = b.addExecutable(.{
        .name = "p2_optimization_test",
        .root_source_file = b.path("benchmarks/p2_optimization_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    p2_optimization_test.root_module.addImport("zokio", lib.root_module);
    p2_optimization_test.root_module.addOptions("config", options);
    p2_optimization_test.root_module.addImport("libxev", libxev.module("xev"));

    const p2_optimization_test_cmd = b.addRunArtifact(p2_optimization_test);
    const p2_optimization_test_step = b.step("p2-memory", "运行P2阶段性能优化验证测试");
    p2_optimization_test_step.dependOn(&p2_optimization_test_cmd.step);

    // P3阶段智能增强功能测试
    const p3_intelligent_test = b.addExecutable(.{
        .name = "p3_intelligent_test",
        .root_source_file = b.path("benchmarks/p3_intelligent_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    p3_intelligent_test.root_module.addImport("zokio", lib.root_module);
    p3_intelligent_test.root_module.addOptions("config", options);
    p3_intelligent_test.root_module.addImport("libxev", libxev.module("xev"));

    const p3_intelligent_test_cmd = b.addRunArtifact(p3_intelligent_test);
    const p3_intelligent_test_step = b.step("p3-memory", "运行P3阶段智能增强功能测试");
    p3_intelligent_test_step.dependOn(&p3_intelligent_test_cmd.step);

    // 统一接口性能修复验证测试
    const unified_performance_fix_test = b.addExecutable(.{
        .name = "unified_performance_fix_test",
        .root_source_file = b.path("benchmarks/unified_performance_fix_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    unified_performance_fix_test.root_module.addImport("zokio", lib.root_module);
    unified_performance_fix_test.root_module.addOptions("config", options);
    unified_performance_fix_test.root_module.addImport("libxev", libxev.module("xev"));

    const unified_performance_fix_test_cmd = b.addRunArtifact(unified_performance_fix_test);
    const unified_performance_fix_test_step = b.step("unified-fix", "运行统一接口性能修复验证测试");
    unified_performance_fix_test_step.dependOn(&unified_performance_fix_test_cmd.step);

    // P0 优化：统一接口 V2 零开销重构验证测试
    const unified_v2_test = b.addExecutable(.{
        .name = "unified_v2_test",
        .root_source_file = b.path("benchmarks/unified_v2_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    unified_v2_test.root_module.addImport("zokio", lib.root_module);
    unified_v2_test.root_module.addOptions("config", options);
    unified_v2_test.root_module.addImport("libxev", libxev.module("xev"));

    const unified_v2_test_cmd = b.addRunArtifact(unified_v2_test);
    const unified_v2_test_step = b.step("unified-fix-v2", "运行P0优化：统一接口V2零开销重构验证测试");
    unified_v2_test_step.dependOn(&unified_v2_test_cmd.step);

    // I/O性能测试
    const io_performance_test = b.addExecutable(.{
        .name = "io_performance_test",
        .root_source_file = b.path("benchmarks/io_performance_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    io_performance_test.root_module.addImport("zokio", lib.root_module);
    io_performance_test.root_module.addOptions("config", options);
    io_performance_test.root_module.addImport("libxev", libxev.module("xev"));

    const io_performance_test_cmd = b.addRunArtifact(io_performance_test);
    const legacy_io_performance_test_step = b.step("io-perf", "运行I/O系统性能测试");
    legacy_io_performance_test_step.dependOn(&io_performance_test_cmd.step);

    // 真实I/O测试
    const real_io_test = b.addExecutable(.{
        .name = "real_io_test",
        .root_source_file = b.path("benchmarks/real_io_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    real_io_test.root_module.addImport("zokio", lib.root_module);
    real_io_test.root_module.addOptions("config", options);
    real_io_test.root_module.addImport("libxev", libxev.module("xev"));

    const real_io_test_cmd = b.addRunArtifact(real_io_test);
    const real_io_test_step = b.step("real-io", "运行真实libxev I/O测试");
    real_io_test_step.dependOn(&real_io_test_cmd.step);

    // 调度器性能测试
    const scheduler_perf_test = b.addExecutable(.{
        .name = "scheduler_performance_test",
        .root_source_file = b.path("benchmarks/scheduler_performance_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    scheduler_perf_test.root_module.addImport("zokio", lib.root_module);
    scheduler_perf_test.root_module.addOptions("config", options);
    scheduler_perf_test.root_module.addImport("libxev", libxev.module("xev"));

    const scheduler_perf_test_cmd = b.addRunArtifact(scheduler_perf_test);
    const scheduler_perf_test_step = b.step("scheduler-perf", "运行调度器性能基准测试");
    scheduler_perf_test_step.dependOn(&scheduler_perf_test_cmd.step);

    // 简化调度器测试
    const simple_scheduler_test = b.addExecutable(.{
        .name = "simple_scheduler_test",
        .root_source_file = b.path("benchmarks/simple_scheduler_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    simple_scheduler_test.root_module.addImport("zokio", lib.root_module);
    simple_scheduler_test.root_module.addOptions("config", options);
    simple_scheduler_test.root_module.addImport("libxev", libxev.module("xev"));

    const simple_scheduler_test_cmd = b.addRunArtifact(simple_scheduler_test);
    const simple_scheduler_test_step = b.step("simple-scheduler", "运行简化调度器性能测试");
    simple_scheduler_test_step.dependOn(&simple_scheduler_test_cmd.step);

    // 修复版libxev驱动测试
    const fixed_libxev_test = b.addExecutable(.{
        .name = "fixed_libxev_test",
        .root_source_file = b.path("benchmarks/fixed_libxev_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    fixed_libxev_test.root_module.addImport("libxev", libxev.module("xev"));

    const fixed_libxev_test_cmd = b.addRunArtifact(fixed_libxev_test);
    const fixed_libxev_test_step = b.step("fixed-libxev", "运行修复版libxev驱动测试");
    fixed_libxev_test_step.dependOn(&fixed_libxev_test_cmd.step);

    // 综合压力测试
    const stress_all_step = b.step("stress-all", "运行所有压力测试");
    stress_all_step.dependOn(&run_benchmarks.step);
    stress_all_step.dependOn(&high_perf_stress_cmd.step);
    stress_all_step.dependOn(&network_stress_cmd.step);
    stress_all_step.dependOn(&async_await_stress_cmd.step);
    stress_all_step.dependOn(&real_async_stress_cmd.step);
    stress_all_step.dependOn(&tokio_vs_zokio_cmd.step);

    // Runtime系统性诊断测试
    const runtime_diagnosis = b.addExecutable(.{
        .name = "runtime_diagnosis",
        .root_source_file = b.path("runtime_diagnosis.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });

    const runtime_diagnosis_cmd = b.addRunArtifact(runtime_diagnosis);
    const runtime_diagnosis_step = b.step("diagnose", "运行Runtime系统性诊断");
    runtime_diagnosis_step.dependOn(&runtime_diagnosis_cmd.step);

    // Runtime组件分层诊断测试
    const runtime_component_diagnosis = b.addExecutable(.{
        .name = "runtime_component_diagnosis",
        .root_source_file = b.path("runtime_component_diagnosis.zig"),
        .target = target,
        .optimize = .Debug,
    });

    // 添加详细的调试信息
    runtime_component_diagnosis.root_module.strip = false;
    runtime_component_diagnosis.root_module.addImport("zokio", lib.root_module);
    runtime_component_diagnosis.root_module.addOptions("config", options);
    runtime_component_diagnosis.root_module.addImport("libxev", libxev.module("xev"));

    const runtime_component_diagnosis_cmd = b.addRunArtifact(runtime_component_diagnosis);
    const runtime_component_diagnosis_step = b.step("diagnose-runtime", "运行Runtime组件分层诊断");
    runtime_component_diagnosis_step.dependOn(&runtime_component_diagnosis_cmd.step);

    // 简化Runtime诊断测试
    const simple_runtime_diagnosis = b.addExecutable(.{
        .name = "simple_runtime_diagnosis",
        .root_source_file = b.path("simple_runtime_diagnosis.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    simple_runtime_diagnosis.root_module.addImport("zokio", lib.root_module);
    simple_runtime_diagnosis.root_module.addOptions("config", options);
    simple_runtime_diagnosis.root_module.addImport("libxev", libxev.module("xev"));

    const simple_runtime_diagnosis_cmd = b.addRunArtifact(simple_runtime_diagnosis);
    const simple_runtime_diagnosis_step = b.step("diagnose-simple", "运行简化Runtime诊断");
    simple_runtime_diagnosis_step.dependOn(&simple_runtime_diagnosis_cmd.step);

    // Runtime配置稳定性测试
    const runtime_stability_test = b.addExecutable(.{
        .name = "runtime_stability_test",
        .root_source_file = b.path("tests/runtime_stability_test.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    runtime_stability_test.root_module.addImport("zokio", lib.root_module);
    runtime_stability_test.root_module.addOptions("config", options);
    runtime_stability_test.root_module.addImport("libxev", libxev.module("xev"));

    const runtime_stability_test_cmd = b.addRunArtifact(runtime_stability_test);
    const runtime_stability_test_step = b.step("test-runtime-stability", "运行Runtime配置稳定性测试");
    runtime_stability_test_step.dependOn(&runtime_stability_test_cmd.step);

    // Runtime健壮性测试
    const runtime_robustness_test = b.addExecutable(.{
        .name = "runtime_robustness_test",
        .root_source_file = b.path("tests/runtime_robustness_test.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    runtime_robustness_test.root_module.addImport("zokio", lib.root_module);
    runtime_robustness_test.root_module.addOptions("config", options);
    runtime_robustness_test.root_module.addImport("libxev", libxev.module("xev"));

    const runtime_robustness_test_cmd = b.addRunArtifact(runtime_robustness_test);
    const runtime_robustness_test_step = b.step("test-runtime-robustness", "运行Runtime健壮性测试");
    runtime_robustness_test_step.dependOn(&runtime_robustness_test_cmd.step);

    // 综合性能基准测试
    const comprehensive_benchmark = b.addExecutable(.{
        .name = "comprehensive_benchmark",
        .root_source_file = b.path("tests/comprehensive_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast, // 使用最高优化级别进行基准测试
    });
    comprehensive_benchmark.root_module.addImport("zokio", lib.root_module);
    comprehensive_benchmark.root_module.addOptions("config", options);
    comprehensive_benchmark.root_module.addImport("libxev", libxev.module("xev"));

    const comprehensive_benchmark_cmd = b.addRunArtifact(comprehensive_benchmark);
    const comprehensive_benchmark_step = b.step("benchmark-comprehensive", "运行综合性能基准测试");
    comprehensive_benchmark_step.dependOn(&comprehensive_benchmark_cmd.step);

    // 调试全局数据大小
    const debug_global_size = b.addExecutable(.{
        .name = "debug_global_size",
        .root_source_file = b.path("debug_global_size.zig"),
        .target = target,
        .optimize = .Debug,
    });
    debug_global_size.root_module.addImport("zokio", lib.root_module);
    debug_global_size.root_module.addOptions("config", options);
    debug_global_size.root_module.addImport("libxev", libxev.module("xev"));

    const debug_global_size_cmd = b.addRunArtifact(debug_global_size);
    const debug_global_size_step = b.step("debug-global-size", "调试全局数据大小问题");
    debug_global_size_step.dependOn(&debug_global_size_cmd.step);

    // Spawn功能验证测试
    const spawn_functionality_test = b.addExecutable(.{
        .name = "spawn_functionality_test",
        .root_source_file = b.path("tests/spawn_functionality_test.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    spawn_functionality_test.root_module.addImport("zokio", lib.root_module);
    spawn_functionality_test.root_module.addOptions("config", options);
    spawn_functionality_test.root_module.addImport("libxev", libxev.module("xev"));

    const spawn_functionality_test_cmd = b.addRunArtifact(spawn_functionality_test);
    const spawn_functionality_test_step = b.step("test-spawn-functionality", "运行Spawn功能验证测试");
    spawn_functionality_test_step.dependOn(&spawn_functionality_test_cmd.step);

    // 简化Spawn测试
    const simple_spawn_test = b.addExecutable(.{
        .name = "simple_spawn_test",
        .root_source_file = b.path("tests/simple_spawn_test.zig"),
        .target = target,
        .optimize = .Debug, // 使用Debug模式便于调试
    });
    simple_spawn_test.root_module.addImport("zokio", lib.root_module);
    simple_spawn_test.root_module.addOptions("config", options);
    simple_spawn_test.root_module.addImport("libxev", libxev.module("xev"));

    const simple_spawn_test_cmd = b.addRunArtifact(simple_spawn_test);
    const simple_spawn_test_step = b.step("test-simple-spawn", "运行简化Spawn测试");
    simple_spawn_test_step.dependOn(&simple_spawn_test_cmd.step);

    // 真实异步验证测试
    const real_async_verification = b.addExecutable(.{
        .name = "real_async_verification",
        .root_source_file = b.path("tests/real_async_verification.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    real_async_verification.root_module.addImport("zokio", lib.root_module);
    real_async_verification.root_module.addOptions("config", options);
    real_async_verification.root_module.addImport("libxev", libxev.module("xev"));

    const real_async_verification_cmd = b.addRunArtifact(real_async_verification);
    const real_async_verification_step = b.step("test-real-async", "运行真实异步验证测试");
    real_async_verification_step.dependOn(&real_async_verification_cmd.step);

    // async_fn和await_fn例子
    const async_await_examples = b.addExecutable(.{
        .name = "async_await_examples",
        .root_source_file = b.path("tests/async_await_examples.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });
    async_await_examples.root_module.addImport("zokio", lib.root_module);
    async_await_examples.root_module.addOptions("config", options);
    async_await_examples.root_module.addImport("libxev", libxev.module("xev"));

    const async_await_examples_cmd = b.addRunArtifact(async_await_examples);
    const async_await_examples_step = b.step("test-async-await", "运行async_fn和await_fn例子");
    async_await_examples_step.dependOn(&async_await_examples_cmd.step);

    // 极致性能测试
    const extreme_performance_test = b.addExecutable(.{
        .name = "extreme_performance_test",
        .root_source_file = b.path("benchmarks/extreme_performance_test.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    extreme_performance_test.root_module.addImport("zokio", lib.root_module);
    extreme_performance_test.root_module.addOptions("config", options);
    extreme_performance_test.root_module.addImport("libxev", libxev.module("xev"));

    const extreme_performance_test_cmd = b.addRunArtifact(extreme_performance_test);
    const extreme_performance_test_step = b.step("extreme-performance", "运行极致性能测试");
    extreme_performance_test_step.dependOn(&extreme_performance_test_cmd.step);

    // TCP绑定测试
    const tcp_test = b.addExecutable(.{
        .name = "tcp-test",
        .root_source_file = b.path("test_tcp_bind.zig"),
        .target = target,
        .optimize = optimize,
    });
    tcp_test.root_module.addImport("zokio", lib.root_module);
    tcp_test.root_module.addOptions("config", options);
    tcp_test.root_module.addImport("libxev", libxev.module("xev"));

    const run_tcp_test = b.addRunArtifact(tcp_test);
    const tcp_test_step = b.step("tcp-test", "运行TCP绑定诊断测试");
    tcp_test_step.dependOn(&run_tcp_test.step);

    // Zokio 2.0 异步实现测试
    const async_impl_test = b.addTest(.{
        .root_source_file = b.path("test_async_implementation.zig"),
        .target = target,
        .optimize = optimize,
    });
    async_impl_test.root_module.addOptions("config", options);
    async_impl_test.root_module.addImport("libxev", libxev.module("xev"));

    const run_async_impl_test = b.addRunArtifact(async_impl_test);
    const async_impl_test_step = b.step("test-async-impl", "运行Zokio 2.0异步实现测试");
    async_impl_test_step.dependOn(&run_async_impl_test.step);

    // Zokio 2.0 简化异步测试
    const async_simple_test = b.addTest(.{
        .root_source_file = b.path("test_async_simple.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_async_simple_test = b.addRunArtifact(async_simple_test);
    const async_simple_test_step = b.step("test-async-simple", "运行Zokio 2.0简化异步测试");
    async_simple_test_step.dependOn(&run_async_simple_test.step);

    // 全面测试 (旧版本)
    const test_all_step = b.step("test-legacy", "运行所有旧版测试");
    test_all_step.dependOn(&run_unit_tests.step);
    test_all_step.dependOn(&run_integration_tests.step);
    test_all_step.dependOn(&fmt_check.step);
}
