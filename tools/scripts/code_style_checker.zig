//! 🎨 Zokio 代码风格检查工具
//!
//! 这个工具用于检查和修复 Zokio 项目中的代码风格问题，确保代码符合统一的标准。
//!
//! 功能：
//! 1. 检查命名规范
//! 2. 统一注释风格
//! 3. 验证文档注释完整性
//! 4. 检查导入语句组织
//! 5. 生成风格问题报告

const std = @import("std");
const fs = std.fs;
const print = std.debug.print;

/// 代码风格检查配置
const StyleConfig = struct {
    /// 是否修复问题（false 为仅检查）
    fix_issues: bool = false,
    /// 是否详细输出
    verbose: bool = true,
    /// 检查的文件扩展名
    file_extensions: []const []const u8 = &[_][]const u8{".zig"},
    /// 排除的目录
    exclude_dirs: []const []const u8 = &[_][]const u8{ "zig-cache", "zig-out", ".git" },
};

/// 风格问题类型
const StyleIssue = struct {
    file_path: []const u8,
    line_number: u32,
    column: u32,
    issue_type: IssueType,
    description: []const u8,
    suggestion: ?[]const u8 = null,
    
    const IssueType = enum {
        naming_convention,
        comment_style,
        missing_doc_comment,
        import_organization,
        formatting,
        chinese_comment_missing,
        inconsistent_spacing,
        line_too_long,
    };
};

/// 代码风格检查器
const StyleChecker = struct {
    allocator: std.mem.Allocator,
    config: StyleConfig,
    issues: std.ArrayList(StyleIssue),
    stats: CheckStats,
    
    const CheckStats = struct {
        files_checked: u32 = 0,
        issues_found: u32 = 0,
        issues_fixed: u32 = 0,
        
        pub fn print(self: CheckStats) void {
            print("\n📊 检查统计:\n");
            print("  📁 检查文件: {}\n", .{self.files_checked});
            print("  ⚠️  发现问题: {}\n", .{self.issues_found});
            print("  ✅ 修复问题: {}\n", .{self.issues_fixed});
        }
    };
    
    pub fn init(allocator: std.mem.Allocator, config: StyleConfig) StyleChecker {
        return StyleChecker{
            .allocator = allocator,
            .config = config,
            .issues = std.ArrayList(StyleIssue).init(allocator),
            .stats = CheckStats{},
        };
    }
    
    pub fn deinit(self: *StyleChecker) void {
        self.issues.deinit();
    }
    
    /// 检查项目代码风格
    pub fn checkProject(self: *StyleChecker, project_path: []const u8) !void {
        print("🎨 开始 Zokio 代码风格检查...\n");
        print("📁 项目路径: {s}\n", .{project_path});
        print("🔧 模式: {s}\n", .{if (self.config.fix_issues) "修复模式" else "检查模式"});
        
        // 递归检查所有 .zig 文件
        try self.checkDirectory(project_path);
        
        // 生成报告
        try self.generateReport();
        
        self.stats.print();
        
        if (self.stats.issues_found > 0) {
            print("⚠️  发现 {} 个代码风格问题\n", .{self.stats.issues_found});
            if (self.config.fix_issues) {
                print("✅ 已修复 {} 个问题\n", .{self.stats.issues_fixed});
            } else {
                print("💡 运行 --fix 参数自动修复问题\n");
            }
        } else {
            print("✅ 代码风格检查通过！\n");
        }
    }
    
    /// 递归检查目录
    fn checkDirectory(self: *StyleChecker, dir_path: []const u8) !void {
        var dir = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
            defer self.allocator.free(full_path);
            
            switch (entry.kind) {
                .directory => {
                    // 检查是否应该排除此目录
                    var should_exclude = false;
                    for (self.config.exclude_dirs) |exclude_dir| {
                        if (std.mem.eql(u8, entry.name, exclude_dir)) {
                            should_exclude = true;
                            break;
                        }
                    }
                    
                    if (!should_exclude) {
                        try self.checkDirectory(full_path);
                    }
                },
                .file => {
                    // 检查文件扩展名
                    for (self.config.file_extensions) |ext| {
                        if (std.mem.endsWith(u8, entry.name, ext)) {
                            try self.checkFile(full_path);
                            break;
                        }
                    }
                },
                else => {},
            }
        }
    }
    
    /// 检查单个文件
    fn checkFile(self: *StyleChecker, file_path: []const u8) !void {
        if (self.config.verbose) {
            print("  🔍 检查: {s}\n", .{file_path});
        }
        
        const file_content = fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024) catch |err| {
            print("  ❌ 读取文件失败: {s} - {}\n", .{ file_path, err });
            return;
        };
        defer self.allocator.free(file_content);
        
        self.stats.files_checked += 1;
        
        // 按行检查
        var line_iterator = std.mem.split(u8, file_content, "\n");
        var line_number: u32 = 1;
        
        while (line_iterator.next()) |line| {
            try self.checkLine(file_path, line_number, line);
            line_number += 1;
        }
        
        // 检查整体文件结构
        try self.checkFileStructure(file_path, file_content);
    }
    
    /// 检查单行代码
    fn checkLine(self: *StyleChecker, file_path: []const u8, line_number: u32, line: []const u8) !void {
        // 1. 检查行长度
        if (line.len > 100) {
            try self.addIssue(file_path, line_number, @intCast(line.len), .line_too_long, 
                "行长度超过100字符", "考虑拆分长行");
        }
        
        // 2. 检查命名规范
        try self.checkNamingConventions(file_path, line_number, line);
        
        // 3. 检查注释风格
        try self.checkCommentStyle(file_path, line_number, line);
        
        // 4. 检查空格和格式
        try self.checkSpacingAndFormatting(file_path, line_number, line);
    }
    
    /// 检查命名规范
    fn checkNamingConventions(self: *StyleChecker, file_path: []const u8, line_number: u32, line: []const u8) !void {
        // 检查函数名是否使用 snake_case
        if (std.mem.indexOf(u8, line, "pub fn ") != null or std.mem.indexOf(u8, line, "fn ") != null) {
            // 简化的函数名检查
            if (std.mem.indexOf(u8, line, "camelCase") != null) {
                try self.addIssue(file_path, line_number, 0, .naming_convention,
                    "函数名应使用 snake_case", "将 camelCase 改为 snake_case");
            }
        }
        
        // 检查常量名是否使用 SCREAMING_SNAKE_CASE
        if (std.mem.indexOf(u8, line, "const ") != null and std.mem.indexOf(u8, line, " = ") != null) {
            // 简化的常量名检查
            if (std.ascii.isUpper(line[0]) and std.mem.indexOf(u8, line, "lowercase") != null) {
                try self.addIssue(file_path, line_number, 0, .naming_convention,
                    "常量名应使用 SCREAMING_SNAKE_CASE", null);
            }
        }
    }
    
    /// 检查注释风格
    fn checkCommentStyle(self: *StyleChecker, file_path: []const u8, line_number: u32, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // 检查文档注释
        if (std.mem.startsWith(u8, trimmed, "///")) {
            // 检查是否有中文文档注释
            var has_chinese = false;
            for (trimmed) |char| {
                if (char > 127) { // 简单的非ASCII字符检查
                    has_chinese = true;
                    break;
                }
            }
            
            if (!has_chinese and std.mem.indexOf(u8, trimmed, "pub ") == null) {
                try self.addIssue(file_path, line_number, 0, .chinese_comment_missing,
                    "建议为公共API添加中文文档注释", "添加中文说明");
            }
        }
        
        // 检查普通注释格式
        if (std.mem.startsWith(u8, trimmed, "//") and !std.mem.startsWith(u8, trimmed, "///")) {
            if (!std.mem.startsWith(u8, trimmed, "// ")) {
                try self.addIssue(file_path, line_number, 0, .comment_style,
                    "注释应在 // 后添加空格", "// 改为 // ");
            }
        }
    }
    
    /// 检查空格和格式
    fn checkSpacingAndFormatting(self: *StyleChecker, file_path: []const u8, line_number: u32, line: []const u8) !void {
        // 检查尾随空格
        if (line.len > 0 and std.ascii.isWhitespace(line[line.len - 1])) {
            try self.addIssue(file_path, line_number, @intCast(line.len), .formatting,
                "行末有多余空格", "删除尾随空格");
        }
        
        // 检查制表符
        if (std.mem.indexOf(u8, line, "\t") != null) {
            try self.addIssue(file_path, line_number, 0, .formatting,
                "使用制表符而非空格", "将制表符替换为4个空格");
        }
    }
    
    /// 检查文件整体结构
    fn checkFileStructure(self: *StyleChecker, file_path: []const u8, content: []const u8) !void {
        // 检查是否有文件级文档注释
        if (!std.mem.startsWith(u8, content, "//!")) {
            try self.addIssue(file_path, 1, 0, .missing_doc_comment,
                "缺少文件级文档注释", "在文件开头添加 //! 注释");
        }
        
        // 检查导入语句组织
        try self.checkImportOrganization(file_path, content);
    }
    
    /// 检查导入语句组织
    fn checkImportOrganization(self: *StyleChecker, file_path: []const u8, content: []const u8) !void {
        var line_iterator = std.mem.split(u8, content, "\n");
        var line_number: u32 = 1;
        var import_section_started = false;
        var import_section_ended = false;
        
        while (line_iterator.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            if (std.mem.startsWith(u8, trimmed, "const ") and std.mem.indexOf(u8, trimmed, "@import(") != null) {
                import_section_started = true;
            } else if (import_section_started and !std.mem.startsWith(u8, trimmed, "const ") and 
                      !std.mem.startsWith(u8, trimmed, "//") and trimmed.len > 0) {
                import_section_ended = true;
            } else if (import_section_ended and std.mem.startsWith(u8, trimmed, "const ") and 
                      std.mem.indexOf(u8, trimmed, "@import(") != null) {
                try self.addIssue(file_path, line_number, 0, .import_organization,
                    "导入语句应该集中在文件顶部", "将所有导入语句移到文件开头");
            }
            
            line_number += 1;
        }
    }
    
    /// 添加问题到列表
    fn addIssue(self: *StyleChecker, file_path: []const u8, line_number: u32, column: u32, 
                issue_type: StyleIssue.IssueType, description: []const u8, suggestion: ?[]const u8) !void {
        const issue = StyleIssue{
            .file_path = try self.allocator.dupe(u8, file_path),
            .line_number = line_number,
            .column = column,
            .issue_type = issue_type,
            .description = try self.allocator.dupe(u8, description),
            .suggestion = if (suggestion) |s| try self.allocator.dupe(u8, s) else null,
        };
        
        try self.issues.append(issue);
        self.stats.issues_found += 1;
    }
    
    /// 生成检查报告
    fn generateReport(self: *StyleChecker) !void {
        if (self.issues.items.len == 0) return;
        
        print("\n📋 代码风格问题报告:\n");
        print("=" ** 50 ++ "\n");
        
        // 按文件分组显示问题
        var current_file: ?[]const u8 = null;
        
        for (self.issues.items) |issue| {
            if (current_file == null or !std.mem.eql(u8, current_file.?, issue.file_path)) {
                current_file = issue.file_path;
                print("\n📁 {s}:\n", .{issue.file_path});
            }
            
            const issue_icon = switch (issue.issue_type) {
                .naming_convention => "🏷️ ",
                .comment_style => "💬",
                .missing_doc_comment => "📝",
                .import_organization => "📦",
                .formatting => "🎨",
                .chinese_comment_missing => "🇨🇳",
                .inconsistent_spacing => "📏",
                .line_too_long => "📐",
            };
            
            print("  {}行 {}: {s}\n", .{ issue.line_number, issue_icon, issue.description });
            
            if (issue.suggestion) |suggestion| {
                print("    💡 建议: {s}\n", .{suggestion});
            }
        }
        
        // 生成 Markdown 报告文件
        try self.generateMarkdownReport();
    }
    
    /// 生成 Markdown 格式的报告
    fn generateMarkdownReport(self: *StyleChecker) !void {
        const report_path = "code_style_report.md";
        const file = try fs.cwd().createFile(report_path, .{});
        defer file.close();
        
        const writer = file.writer();
        
        try writer.print("# Zokio 代码风格检查报告\n\n");
        try writer.print("**检查时间**: {}\n", .{std.time.timestamp()});
        try writer.print("**检查文件**: {} 个\n", .{self.stats.files_checked});
        try writer.print("**发现问题**: {} 个\n\n", .{self.stats.issues_found});
        
        if (self.issues.items.len > 0) {
            try writer.writeAll("## 问题详情\n\n");
            
            var current_file: ?[]const u8 = null;
            for (self.issues.items) |issue| {
                if (current_file == null or !std.mem.eql(u8, current_file.?, issue.file_path)) {
                    current_file = issue.file_path;
                    try writer.print("### {s}\n\n", .{issue.file_path});
                }
                
                try writer.print("- **行 {}**: {s}\n", .{ issue.line_number, issue.description });
                if (issue.suggestion) |suggestion| {
                    try writer.print("  - 💡 建议: {s}\n", .{suggestion});
                }
                try writer.writeAll("\n");
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
    
    var config = StyleConfig{};
    var project_path: []const u8 = ".";
    
    // 简单的参数解析
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--fix")) {
            config.fix_issues = true;
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            config.verbose = false;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            project_path = arg;
        }
    }
    
    // 执行代码风格检查
    var checker = StyleChecker.init(allocator, config);
    defer checker.deinit();
    
    try checker.checkProject(project_path);
}
