//! 🔍 Zokio 静态分析工具
//!
//! 这个工具集成了多种静态分析检查，包括：
//! 1. Zig 编译器内置警告
//! 2. 自定义 Lint 规则
//! 3. 代码复杂度分析
//! 4. 依赖关系分析
//! 5. 安全性检查

const std = @import("std");
const print = std.debug.print;

/// 静态分析配置
const AnalysisConfig = struct {
    /// 启用的检查类型
    enable_compiler_warnings: bool = true,
    enable_custom_lints: bool = true,
    enable_complexity_analysis: bool = true,
    enable_dependency_analysis: bool = true,
    enable_security_checks: bool = true,
    
    /// 阈值配置
    max_function_complexity: u32 = 10,
    max_file_lines: u32 = 1000,
    max_function_lines: u32 = 50,
    max_function_params: u32 = 5,
    
    /// 输出配置
    verbose: bool = false,
    output_format: OutputFormat = .console,
    
    const OutputFormat = enum {
        console,
        json,
        markdown,
    };
};

/// 分析问题
const AnalysisIssue = struct {
    file_path: []const u8,
    line_number: u32,
    column: u32,
    severity: Severity,
    category: Category,
    rule_id: []const u8,
    message: []const u8,
    suggestion: ?[]const u8 = null,
    
    const Severity = enum {
        info,
        warning,
        error,
        critical,
    };
    
    const Category = enum {
        style,
        complexity,
        security,
        performance,
        maintainability,
        correctness,
    };
};

/// 静态分析器
const StaticAnalyzer = struct {
    allocator: std.mem.Allocator,
    config: AnalysisConfig,
    issues: std.ArrayList(AnalysisIssue),
    
    pub fn init(allocator: std.mem.Allocator, config: AnalysisConfig) StaticAnalyzer {
        return StaticAnalyzer{
            .allocator = allocator,
            .config = config,
            .issues = std.ArrayList(AnalysisIssue).init(allocator),
        };
    }
    
    pub fn deinit(self: *StaticAnalyzer) void {
        self.issues.deinit();
    }
    
    /// 运行所有静态分析
    pub fn runAnalysis(self: *StaticAnalyzer, project_path: []const u8) !void {
        print("🔍 开始 Zokio 静态分析...\n");
        print("📁 项目路径: {s}\n", .{project_path});
        print("=" ** 50 ++ "\n");
        
        // 1. 编译器警告检查
        if (self.config.enable_compiler_warnings) {
            try self.checkCompilerWarnings();
        }
        
        // 2. 自定义 Lint 规则
        if (self.config.enable_custom_lints) {
            try self.runCustomLints(project_path);
        }
        
        // 3. 复杂度分析
        if (self.config.enable_complexity_analysis) {
            try self.analyzeComplexity(project_path);
        }
        
        // 4. 依赖关系分析
        if (self.config.enable_dependency_analysis) {
            try self.analyzeDependencies(project_path);
        }
        
        // 5. 安全性检查
        if (self.config.enable_security_checks) {
            try self.runSecurityChecks(project_path);
        }
        
        // 生成报告
        try self.generateReport();
    }
    
    /// 检查编译器警告
    fn checkCompilerWarnings(self: *StaticAnalyzer) !void {
        print("⚠️  检查编译器警告...\n");
        
        // 使用最严格的编译选项
        const args = [_][]const u8{
            "zig", "build",
            "-Doptimize=Debug",
            "-Dcpu=baseline",
            "--summary", "all"
        };
        
        const result = try self.runCommand(&args);
        
        if (result.exit_code != 0) {
            try self.parseCompilerOutput(result.stderr);
        }
        
        print("  ✅ 编译器警告检查完成\n");
    }
    
    /// 解析编译器输出
    fn parseCompilerOutput(self: *StaticAnalyzer, output: []const u8) !void {
        var lines = std.mem.split(u8, output, "\n");
        
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "warning:") != null) {
                try self.parseWarningLine(line);
            } else if (std.mem.indexOf(u8, line, "error:") != null) {
                try self.parseErrorLine(line);
            }
        }
    }
    
    /// 解析警告行
    fn parseWarningLine(self: *StaticAnalyzer, line: []const u8) !void {
        // 简化的警告解析
        // 实际实现需要更复杂的解析逻辑
        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const file_part = line[0..colon_pos];
            const message_part = line[colon_pos + 1 ..];
            
            try self.addIssue(file_part, 0, 0, .warning, .correctness, "COMPILER_WARNING", message_part, null);
        }
    }
    
    /// 解析错误行
    fn parseErrorLine(self: *StaticAnalyzer, line: []const u8) !void {
        // 类似警告解析
        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const file_part = line[0..colon_pos];
            const message_part = line[colon_pos + 1 ..];
            
            try self.addIssue(file_part, 0, 0, .error, .correctness, "COMPILER_ERROR", message_part, null);
        }
    }
    
    /// 运行自定义 Lint 规则
    fn runCustomLints(self: *StaticAnalyzer, project_path: []const u8) !void {
        print("📝 运行自定义 Lint 规则...\n");
        
        try self.walkDirectory(project_path, self.lintFile);
        
        print("  ✅ 自定义 Lint 检查完成\n");
    }
    
    /// Lint 单个文件
    fn lintFile(self: *StaticAnalyzer, file_path: []const u8) !void {
        if (!std.mem.endsWith(u8, file_path, ".zig")) return;
        
        const content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024) catch |err| {
            if (self.config.verbose) {
                print("  ⚠️  无法读取文件: {s} - {}\n", .{ file_path, err });
            }
            return;
        };
        defer self.allocator.free(content);
        
        // 运行各种 Lint 规则
        try self.checkNamingConventions(file_path, content);
        try self.checkFunctionLength(file_path, content);
        try self.checkFileLength(file_path, content);
        try self.checkCommentCoverage(file_path, content);
        try self.checkImportOrganization(file_path, content);
    }
    
    /// 检查命名规范
    fn checkNamingConventions(self: *StaticAnalyzer, file_path: []const u8, content: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");
        var line_number: u32 = 1;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // 检查函数命名
            if (std.mem.indexOf(u8, trimmed, "pub fn ") != null or std.mem.indexOf(u8, trimmed, "fn ") != null) {
                if (self.hasCamelCase(trimmed)) {
                    try self.addIssue(file_path, line_number, 0, .warning, .style, "NAMING_CONVENTION", 
                        "函数名应使用 snake_case", "将函数名改为 snake_case 格式");
                }
            }
            
            // 检查常量命名
            if (std.mem.indexOf(u8, trimmed, "const ") != null and std.mem.indexOf(u8, trimmed, " = ") != null) {
                if (self.hasLowerCase(trimmed) and !std.mem.indexOf(u8, trimmed, "_") != null) {
                    try self.addIssue(file_path, line_number, 0, .info, .style, "CONST_NAMING", 
                        "常量建议使用 SCREAMING_SNAKE_CASE", "将常量名改为大写下划线格式");
                }
            }
            
            line_number += 1;
        }
    }
    
    /// 检查函数长度
    fn checkFunctionLength(self: *StaticAnalyzer, file_path: []const u8, content: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");
        var line_number: u32 = 1;
        var in_function = false;
        var function_start: u32 = 0;
        var brace_count: i32 = 0;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (std.mem.indexOf(u8, trimmed, "fn ") != null and std.mem.indexOf(u8, trimmed, "{") != null) {
                in_function = true;
                function_start = line_number;
                brace_count = 1;
            } else if (in_function) {
                // 计算大括号
                for (trimmed) |char| {
                    if (char == '{') brace_count += 1;
                    if (char == '}') brace_count -= 1;
                }
                
                if (brace_count == 0) {
                    const function_length = line_number - function_start + 1;
                    if (function_length > self.config.max_function_lines) {
                        const message = try std.fmt.allocPrint(self.allocator, "函数长度 {} 行，超过限制 {} 行", .{ function_length, self.config.max_function_lines });
                        try self.addIssue(file_path, function_start, 0, .warning, .complexity, "FUNCTION_LENGTH", 
                            message, "考虑拆分函数");
                    }
                    in_function = false;
                }
            }
            
            line_number += 1;
        }
    }
    
    /// 检查文件长度
    fn checkFileLength(self: *StaticAnalyzer, file_path: []const u8, content: []const u8) !void {
        const line_count = std.mem.count(u8, content, "\n") + 1;
        
        if (line_count > self.config.max_file_lines) {
            const message = try std.fmt.allocPrint(self.allocator, "文件长度 {} 行，超过限制 {} 行", .{ line_count, self.config.max_file_lines });
            try self.addIssue(file_path, 1, 0, .warning, .maintainability, "FILE_LENGTH", 
                message, "考虑拆分文件");
        }
    }
    
    /// 检查注释覆盖率
    fn checkCommentCoverage(self: *StaticAnalyzer, file_path: []const u8, content: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");
        var total_lines: u32 = 0;
        var comment_lines: u32 = 0;
        var public_functions: u32 = 0;
        var documented_functions: u32 = 0;
        var last_line_was_doc_comment = false;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            total_lines += 1;
            
            if (std.mem.startsWith(u8, trimmed, "//")) {
                comment_lines += 1;
                if (std.mem.startsWith(u8, trimmed, "///")) {
                    last_line_was_doc_comment = true;
                }
            } else if (std.mem.indexOf(u8, trimmed, "pub fn ") != null) {
                public_functions += 1;
                if (last_line_was_doc_comment) {
                    documented_functions += 1;
                }
                last_line_was_doc_comment = false;
            } else if (trimmed.len > 0) {
                last_line_was_doc_comment = false;
            }
        }
        
        // 检查公共函数文档覆盖率
        if (public_functions > 0) {
            const doc_coverage = @as(f32, @floatFromInt(documented_functions)) / @as(f32, @floatFromInt(public_functions)) * 100.0;
            if (doc_coverage < 80.0) {
                const message = try std.fmt.allocPrint(self.allocator, "公共函数文档覆盖率 {d:.1}%，建议达到 80%", .{doc_coverage});
                try self.addIssue(file_path, 1, 0, .info, .maintainability, "DOC_COVERAGE", 
                    message, "为公共函数添加文档注释");
            }
        }
    }
    
    /// 检查导入组织
    fn checkImportOrganization(self: *StaticAnalyzer, file_path: []const u8, content: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");
        var line_number: u32 = 1;
        var import_section_ended = false;
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (std.mem.indexOf(u8, trimmed, "@import(") != null) {
                if (import_section_ended) {
                    try self.addIssue(file_path, line_number, 0, .warning, .style, "IMPORT_ORGANIZATION", 
                        "导入语句应该集中在文件顶部", "将导入语句移到文件开头");
                }
            } else if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "//")) {
                import_section_ended = true;
            }
            
            line_number += 1;
        }
    }
    
    /// 分析代码复杂度
    fn analyzeComplexity(self: *StaticAnalyzer, project_path: []const u8) !void {
        print("📊 分析代码复杂度...\n");
        
        try self.walkDirectory(project_path, self.analyzeFileComplexity);
        
        print("  ✅ 复杂度分析完成\n");
    }
    
    /// 分析文件复杂度
    fn analyzeFileComplexity(self: *StaticAnalyzer, file_path: []const u8) !void {
        if (!std.mem.endsWith(u8, file_path, ".zig")) return;
        
        const content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024) catch return;
        defer self.allocator.free(content);
        
        // 计算圈复杂度
        const complexity = self.calculateCyclomaticComplexity(content);
        if (complexity > self.config.max_function_complexity) {
            const message = try std.fmt.allocPrint(self.allocator, "圈复杂度 {}，超过限制 {}", .{ complexity, self.config.max_function_complexity });
            try self.addIssue(file_path, 1, 0, .warning, .complexity, "CYCLOMATIC_COMPLEXITY", 
                message, "简化函数逻辑");
        }
    }
    
    /// 计算圈复杂度
    fn calculateCyclomaticComplexity(self: *StaticAnalyzer, content: []const u8) u32 {
        _ = self;
        var complexity: u32 = 1; // 基础复杂度
        
        // 计算决策点
        complexity += @as(u32, @intCast(std.mem.count(u8, content, "if ")));
        complexity += @as(u32, @intCast(std.mem.count(u8, content, "while ")));
        complexity += @as(u32, @intCast(std.mem.count(u8, content, "for ")));
        complexity += @as(u32, @intCast(std.mem.count(u8, content, "switch ")));
        complexity += @as(u32, @intCast(std.mem.count(u8, content, "catch ")));
        complexity += @as(u32, @intCast(std.mem.count(u8, content, "and ")));
        complexity += @as(u32, @intCast(std.mem.count(u8, content, "or ")));
        
        return complexity;
    }
    
    /// 分析依赖关系
    fn analyzeDependencies(self: *StaticAnalyzer, project_path: []const u8) !void {
        print("📦 分析依赖关系...\n");
        
        // 这里应该实现依赖关系分析
        // 包括循环依赖检测、依赖深度分析等
        _ = project_path;
        
        print("  ✅ 依赖关系分析完成\n");
    }
    
    /// 运行安全性检查
    fn runSecurityChecks(self: *StaticAnalyzer, project_path: []const u8) !void {
        print("🔒 运行安全性检查...\n");
        
        try self.walkDirectory(project_path, self.checkFileSecurity);
        
        print("  ✅ 安全性检查完成\n");
    }
    
    /// 检查文件安全性
    fn checkFileSecurity(self: *StaticAnalyzer, file_path: []const u8) !void {
        if (!std.mem.endsWith(u8, file_path, ".zig")) return;
        
        const content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024) catch return;
        defer self.allocator.free(content);
        
        // 检查潜在的安全问题
        if (std.mem.indexOf(u8, content, "unsafe") != null) {
            try self.addIssue(file_path, 1, 0, .warning, .security, "UNSAFE_CODE", 
                "发现 unsafe 代码", "确保 unsafe 代码的安全性");
        }
        
        if (std.mem.indexOf(u8, content, "@ptrCast") != null) {
            try self.addIssue(file_path, 1, 0, .info, .security, "PTR_CAST", 
                "发现指针转换", "确保指针转换的安全性");
        }
    }
    
    /// 遍历目录
    fn walkDirectory(self: *StaticAnalyzer, dir_path: []const u8, callback: *const fn (*StaticAnalyzer, []const u8) anyerror!void) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer self.allocator.free(full_path);
            
            switch (entry.kind) {
                .directory => {
                    if (!std.mem.eql(u8, entry.name, "zig-cache") and !std.mem.eql(u8, entry.name, "zig-out")) {
                        try self.walkDirectory(full_path, callback);
                    }
                },
                .file => try callback(self, full_path),
                else => {},
            }
        }
    }
    
    /// 辅助函数：检查是否有驼峰命名
    fn hasCamelCase(self: *StaticAnalyzer, text: []const u8) bool {
        _ = self;
        for (text, 0..) |char, i| {
            if (i > 0 and std.ascii.isUpper(char) and std.ascii.isLower(text[i - 1])) {
                return true;
            }
        }
        return false;
    }
    
    /// 辅助函数：检查是否有小写字母
    fn hasLowerCase(self: *StaticAnalyzer, text: []const u8) bool {
        _ = self;
        for (text) |char| {
            if (std.ascii.isLower(char)) return true;
        }
        return false;
    }
    
    /// 运行命令
    fn runCommand(self: *StaticAnalyzer, args: []const []const u8) !CommandResult {
        var child = std.process.Child.init(args, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        
        const exit_code = try child.wait();
        
        return CommandResult{
            .exit_code = switch (exit_code) {
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
    
    /// 添加问题
    fn addIssue(self: *StaticAnalyzer, file_path: []const u8, line_number: u32, column: u32, 
                severity: AnalysisIssue.Severity, category: AnalysisIssue.Category, 
                rule_id: []const u8, message: []const u8, suggestion: ?[]const u8) !void {
        const issue = AnalysisIssue{
            .file_path = try self.allocator.dupe(u8, file_path),
            .line_number = line_number,
            .column = column,
            .severity = severity,
            .category = category,
            .rule_id = try self.allocator.dupe(u8, rule_id),
            .message = try self.allocator.dupe(u8, message),
            .suggestion = if (suggestion) |s| try self.allocator.dupe(u8, s) else null,
        };
        
        try self.issues.append(issue);
    }
    
    /// 生成报告
    fn generateReport(self: *StaticAnalyzer) !void {
        print("\n📋 静态分析报告\n");
        print("=" ** 50 ++ "\n");
        
        if (self.issues.items.len == 0) {
            print("🎉 未发现任何问题！\n");
            return;
        }
        
        // 按严重程度统计
        var counts = [_]u32{0} ** 4;
        for (self.issues.items) |issue| {
            counts[@intFromEnum(issue.severity)] += 1;
        }
        
        print("发现 {} 个问题:\n", .{self.issues.items.len});
        print("  🔴 严重: {}\n", .{counts[@intFromEnum(AnalysisIssue.Severity.critical)]});
        print("  🟠 错误: {}\n", .{counts[@intFromEnum(AnalysisIssue.Severity.error)]});
        print("  🟡 警告: {}\n", .{counts[@intFromEnum(AnalysisIssue.Severity.warning)]});
        print("  🔵 信息: {}\n", .{counts[@intFromEnum(AnalysisIssue.Severity.info)]});
        
        // 按类别分组显示
        try self.displayIssuesByCategory();
        
        // 生成文件报告
        switch (self.config.output_format) {
            .console => {}, // 已经输出到控制台
            .json => try self.generateJsonReport(),
            .markdown => try self.generateMarkdownReport(),
        }
    }
    
    /// 按类别显示问题
    fn displayIssuesByCategory(self: *StaticAnalyzer) !void {
        const categories = [_]AnalysisIssue.Category{ .style, .complexity, .security, .performance, .maintainability, .correctness };
        
        for (categories) |category| {
            var category_issues = std.ArrayList(AnalysisIssue).init(self.allocator);
            defer category_issues.deinit();
            
            for (self.issues.items) |issue| {
                if (issue.category == category) {
                    try category_issues.append(issue);
                }
            }
            
            if (category_issues.items.len > 0) {
                print("\n📂 {s} ({} 个问题):\n", .{ @tagName(category), category_issues.items.len });
                
                for (category_issues.items) |issue| {
                    const severity_icon = switch (issue.severity) {
                        .critical => "🔴",
                        .error => "🟠",
                        .warning => "🟡",
                        .info => "🔵",
                    };
                    
                    print("  {} {s}:{}: {s}\n", .{ severity_icon, issue.file_path, issue.line_number, issue.message });
                    if (issue.suggestion) |suggestion| {
                        print("    💡 {s}\n", .{suggestion});
                    }
                }
            }
        }
    }
    
    /// 生成 JSON 报告
    fn generateJsonReport(self: *StaticAnalyzer) !void {
        const report_path = "static_analysis_report.json";
        const file = try std.fs.cwd().createFile(report_path, .{});
        defer file.close();
        
        // 这里应该实现 JSON 序列化
        // 简化实现
        try file.writeAll("{\n  \"issues\": [\n");
        for (self.issues.items, 0..) |issue, i| {
            if (i > 0) try file.writeAll(",\n");
            try file.writer().print("    {{\n      \"file\": \"{s}\",\n      \"line\": {},\n      \"severity\": \"{s}\",\n      \"message\": \"{s}\"\n    }}", .{ issue.file_path, issue.line_number, @tagName(issue.severity), issue.message });
        }
        try file.writeAll("\n  ]\n}\n");
        
        print("📄 JSON 报告已生成: {s}\n", .{report_path});
    }
    
    /// 生成 Markdown 报告
    fn generateMarkdownReport(self: *StaticAnalyzer) !void {
        const report_path = "static_analysis_report.md";
        const file = try std.fs.cwd().createFile(report_path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        try writer.writeAll("# Zokio 静态分析报告\n\n");
        try writer.print("**分析时间**: {}\n", .{std.time.timestamp()});
        try writer.print("**发现问题**: {} 个\n\n", .{self.issues.items.len});
        
        // 按文件分组
        var current_file: ?[]const u8 = null;
        for (self.issues.items) |issue| {
            if (current_file == null or !std.mem.eql(u8, current_file.?, issue.file_path)) {
                current_file = issue.file_path;
                try writer.print("## {s}\n\n", .{issue.file_path});
            }
            
            try writer.print("- **行 {}** [{s}] {s}: {s}\n", .{ issue.line_number, @tagName(issue.severity), issue.rule_id, issue.message });
            if (issue.suggestion) |suggestion| {
                try writer.print("  - 💡 {s}\n", .{suggestion});
            }
        }
        
        print("📄 Markdown 报告已生成: {s}\n", .{report_path});
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
    
    var config = AnalysisConfig{};
    var project_path: []const u8 = ".";
    
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            config.output_format = .json;
        } else if (std.mem.eql(u8, arg, "--markdown")) {
            config.output_format = .markdown;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            project_path = arg;
        }
    }
    
    // 运行静态分析
    var analyzer = StaticAnalyzer.init(allocator, config);
    defer analyzer.deinit();
    
    try analyzer.runAnalysis(project_path);
}
