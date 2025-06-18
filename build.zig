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
    lib.root_module.addImport("libxev", libxev.module("libxev"));

    // 安装库
    b.installArtifact(lib);

    // 单元测试
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.root_module.addOptions("config", options);
    unit_tests.root_module.addImport("libxev", libxev.module("libxev"));

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
    integration_tests.root_module.addImport("libxev", libxev.module("libxev"));
    integration_tests.root_module.addImport("zokio", lib.root_module);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "运行集成测试");
    integration_test_step.dependOn(&run_integration_tests.step);

    // 基准测试
    const benchmarks = b.addExecutable(.{
        .name = "benchmarks",
        .root_source_file = b.path("benchmarks/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    benchmarks.root_module.addOptions("config", options);
    benchmarks.root_module.addImport("libxev", libxev.module("libxev"));
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
    };

    for (examples) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
            .target = target,
            .optimize = optimize,
        });
        example.root_module.addOptions("config", options);
        example.root_module.addImport("libxev", libxev.module("libxev"));
        example.root_module.addImport("zokio", lib.root_module);

        const install_example = b.addInstallArtifact(example, .{});
        const example_step = b.step(b.fmt("example-{s}", .{example_name}), b.fmt("构建{s}示例", .{example_name}));
        example_step.dependOn(&install_example.step);
    }

    // 文档生成
    const docs = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = b.host,
        .optimize = .Debug,
    });
    docs.root_module.addOptions("config", options);
    docs.root_module.addImport("libxev", libxev.module("libxev"));

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

    // 全面测试
    const test_all_step = b.step("test-all", "运行所有测试");
    test_all_step.dependOn(&run_unit_tests.step);
    test_all_step.dependOn(&run_integration_tests.step);
    test_all_step.dependOn(&fmt_check.step);
}
