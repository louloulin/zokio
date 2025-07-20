//! 🧪 Zokio 测试运行器
//!
//! 这个工具用于系统性地运行和管理 Zokio 项目的测试，包括：
//! 1. 分类运行不同类型的测试
//! 2. 生成测试报告
//! 3. 识别和跳过有问题的测试
//! 4. 统计测试覆盖率

const std = @import("std");
const print = std.debug.print;

/// 测试运行配置
const TestConfig = struct {
    /// 是否运行需要 libxev 的测试
    run_libxev_tests: bool = false,
    /// 是否运行集成测试
    run_integration_tests: bool = true,
    /// 是否运行性能测试
    run_performance_tests: bool = false,
    /// 是否详细输出
    verbose: bool = true,
    /// 测试超时时间（秒）
    timeout_seconds: u32 = 30,
};

/// 测试结果
const TestResult = struct {
    name: []const u8,
    passed: bool,
    duration_ms: u64,
    output: []const u8,
    error_message: ?[]const u8 = null,
};

/// 测试分类
const TestCategory = enum {
    unit,
    integration,
    performance,
    libxev_dependent,
    error_handling,

    pub fn toString(self: TestCategory) []const u8 {
        return switch (self) {
            .unit => "单元测试",
            .integration => "集成测试",
            .performance => "性能测试",
            .libxev_dependent => "libxev依赖测试",
            .error_handling => "错误处理测试",
        };
    }
};

/// 测试定义
const TestDefinition = struct {
    name: []const u8,
    file_path: []const u8,
    category: TestCategory,
    requires_libxev: bool = false,
    timeout_seconds: u32 = 30,
};

/// 测试运行器
const TestRunner = struct {
    allocator: std.mem.Allocator,
    config: TestConfig,
    results: std.ArrayList(TestResult),

    pub fn init(allocator: std.mem.Allocator, config: TestConfig) TestRunner {
        return TestRunner{
            .allocator = allocator,
            .config = config,
            .results = std.ArrayList(TestResult).init(allocator),
        };
    }

    pub fn deinit(self: *TestRunner) void {
        self.results.deinit();
    }

    /// 运行所有测试
    pub fn runAllTests(self: *TestRunner) !void {
        print("🧪 开始 Zokio 测试运行...\n", .{});
        print("==================================================\n", .{});

        // 定义测试列表
        const tests = [_]TestDefinition{
            // 错误处理测试
            .{
                .name = "统一错误处理系统",
                .file_path = "src/error/unified_error_system.zig",
                .category = .error_handling,
                .requires_libxev = false,
            },
            .{
                .name = "错误处理模块",
                .file_path = "src/error/mod.zig",
                .category = .error_handling,
                .requires_libxev = false,
            },

            // 工具模块测试
            .{
                .name = "工具模块",
                .file_path = "src/utils/utils.zig",
                .category = .unit,
                .requires_libxev = false,
            },

            // 内存管理测试
            .{
                .name = "内存管理",
                .file_path = "src/memory/memory.zig",
                .category = .unit,
                .requires_libxev = false,
            },

            // 同步原语测试
            .{
                .name = "同步原语",
                .file_path = "src/sync/sync.zig",
                .category = .unit,
                .requires_libxev = false,
            },

            // 时间模块测试
            .{
                .name = "时间模块",
                .file_path = "src/time/time.zig",
                .category = .unit,
                .requires_libxev = false,
            },
        };

        // 按类别运行测试
        for (tests) |test_def| {
            if (test_def.requires_libxev and !self.config.run_libxev_tests) {
                print("⏭️  跳过 {s} (需要 libxev)\n", .{test_def.name});
                continue;
            }

            if (test_def.category == .performance and !self.config.run_performance_tests) {
                print("⏭️  跳过 {s} (性能测试)\n", .{test_def.name});
                continue;
            }

            try self.runSingleTest(test_def);
        }

        // 生成报告
        try self.generateReport();
    }

    /// 运行单个测试
    fn runSingleTest(self: *TestRunner, test_def: TestDefinition) !void {
        print("🔍 运行 {s}...\n", .{test_def.name});

        const start_time = std.time.milliTimestamp();

        // 构建测试命令
        const args = [_][]const u8{ "zig", "test", test_def.file_path };

        const result = self.runCommand(&args, test_def.timeout_seconds) catch |err| {
            const duration = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
            const error_msg = try std.fmt.allocPrint(self.allocator, "命令执行失败: {any}", .{err});

            try self.addResult(test_def.name, false, duration, "", error_msg);
            print("  ❌ {s} 失败: {s}\n", .{ test_def.name, error_msg });
            return;
        };

        const duration = @as(u64, @intCast(std.time.milliTimestamp() - start_time));
        const passed = result.exit_code == 0;

        try self.addResult(test_def.name, passed, duration, result.stdout, if (passed) null else result.stderr);

        if (passed) {
            print("  ✅ {s} 通过 ({}ms)\n", .{ test_def.name, duration });
        } else {
            print("  ❌ {s} 失败 ({}ms)\n", .{ test_def.name, duration });
            if (self.config.verbose and result.stderr.len > 0) {
                print("    错误: {s}\n", .{result.stderr});
            }
        }
    }

    /// 运行命令
    fn runCommand(self: *TestRunner, args: []const []const u8, timeout_seconds: u32) !CommandResult {
        _ = timeout_seconds; // 暂时忽略超时

        var child = std.process.Child.init(args, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);

        const term = try child.wait();

        return CommandResult{
            .exit_code = switch (term) {
                .Exited => |code| code,
                else => 1,
            },
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    const CommandResult = struct {
        exit_code: u8,
        stdout: []u8,
        stderr: []u8,
    };

    /// 添加测试结果
    fn addResult(self: *TestRunner, name: []const u8, passed: bool, duration_ms: u64, output: []const u8, error_message: ?[]const u8) !void {
        const result = TestResult{
            .name = try self.allocator.dupe(u8, name),
            .passed = passed,
            .duration_ms = duration_ms,
            .output = try self.allocator.dupe(u8, output),
            .error_message = if (error_message) |msg| try self.allocator.dupe(u8, msg) else null,
        };

        try self.results.append(result);
    }

    /// 生成测试报告
    fn generateReport(self: *TestRunner) !void {
        print("\n📋 测试报告\n", .{});
        print("==================================================\n", .{});

        var passed_count: u32 = 0;
        var total_duration: u64 = 0;

        for (self.results.items) |result| {
            if (result.passed) {
                passed_count += 1;
            }
            total_duration += result.duration_ms;
        }

        print("总体结果: {}/{} 测试通过\n", .{ passed_count, self.results.items.len });
        print("总耗时: {}ms\n", .{total_duration});
        print("成功率: {d:.1}%\n", .{@as(f64, @floatFromInt(passed_count)) / @as(f64, @floatFromInt(self.results.items.len)) * 100.0});

        // 显示失败的测试
        var has_failures = false;
        for (self.results.items) |result| {
            if (!result.passed) {
                if (!has_failures) {
                    print("\n❌ 失败的测试:\n", .{});
                    has_failures = true;
                }

                print("  • {s} ({}ms)\n", .{ result.name, result.duration_ms });
                if (result.error_message) |msg| {
                    print("    错误: {s}\n", .{msg});
                }
            }
        }

        if (!has_failures) {
            print("\n🎉 所有测试都通过了！\n", .{});
        }

        // 生成 Markdown 报告
        try self.generateMarkdownReport();
    }

    /// 生成 Markdown 报告
    fn generateMarkdownReport(self: *TestRunner) !void {
        const report_path = "test_report.md";
        const file = try std.fs.cwd().createFile(report_path, .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll("# Zokio 测试报告\n\n");
        try writer.print("**测试时间**: {}\n", .{std.time.timestamp()});

        var passed_count: u32 = 0;
        var total_duration: u64 = 0;

        for (self.results.items) |result| {
            if (result.passed) passed_count += 1;
            total_duration += result.duration_ms;
        }

        try writer.print("**总体结果**: {}/{} 测试通过\n", .{ passed_count, self.results.items.len });
        try writer.print("**总耗时**: {}ms\n", .{total_duration});
        try writer.print("**成功率**: {d:.1}%\n\n", .{@as(f64, @floatFromInt(passed_count)) / @as(f64, @floatFromInt(self.results.items.len)) * 100.0});

        try writer.writeAll("## 测试详情\n\n");

        for (self.results.items) |result| {
            const status = if (result.passed) "✅" else "❌";
            try writer.print("### {} {s}\n\n", .{ status, result.name });
            try writer.print("**耗时**: {}ms\n\n", .{result.duration_ms});

            if (result.error_message) |msg| {
                try writer.print("**错误信息**:\n```\n{s}\n```\n\n", .{msg});
            }
        }

        print("📄 详细报告已生成: {s}\n", .{report_path});
    }
};

/// 主函数
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 解析命令行参数
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = TestConfig{};

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--libxev")) {
            config.run_libxev_tests = true;
        } else if (std.mem.eql(u8, arg, "--performance")) {
            config.run_performance_tests = true;
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            config.verbose = false;
        }
    }

    // 运行测试
    var runner = TestRunner.init(allocator, config);
    defer runner.deinit();

    try runner.runAllTests();
}
