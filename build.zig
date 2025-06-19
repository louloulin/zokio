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

    // 编译时配置选项
    const options = b.addOptions();
    options.addOption(bool, "enable_metrics", enable_metrics);
    options.addOption(bool, "enable_tracing", enable_tracing);
    options.addOption(bool, "enable_numa", enable_numa);
    options.addOption(bool, "enable_io_uring", enable_io_uring);
    options.addOption(bool, "enable_simd", enable_simd);
    options.addOption(bool, "debug_mode", debug_mode);

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
    const io_performance_test_step = b.step("io-perf", "运行I/O系统性能测试");
    io_performance_test_step.dependOn(&io_performance_test_cmd.step);

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

    // 全面测试
    const test_all_step = b.step("test-all", "运行所有测试");
    test_all_step.dependOn(&run_unit_tests.step);
    test_all_step.dependOn(&run_integration_tests.step);
    test_all_step.dependOn(&fmt_check.step);
}
