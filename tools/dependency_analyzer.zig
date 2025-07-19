//! 🔍 Zokio 依赖关系分析工具
//!
//! 分析模块间的耦合度和依赖关系，识别需要重构的部分

const std = @import("std");
const print = std.debug.print;

/// 模块依赖信息
const ModuleDependency = struct {
    module_path: []const u8,
    imports: std.ArrayList([]const u8),
    exports: std.ArrayList([]const u8),
    cyclic_deps: std.ArrayList([]const u8),
    coupling_score: f32 = 0.0,
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) ModuleDependency {
        return ModuleDependency{
            .module_path = path,
            .imports = std.ArrayList([]const u8).init(allocator),
            .exports = std.ArrayList([]const u8).init(allocator),
            .cyclic_deps = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *ModuleDependency) void {
        self.imports.deinit();
        self.exports.deinit();
        self.cyclic_deps.deinit();
    }
};

/// 依赖分析器
const DependencyAnalyzer = struct {
    allocator: std.mem.Allocator,
    modules: std.HashMap([]const u8, ModuleDependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    high_coupling_modules: std.ArrayList([]const u8),
    circular_dependencies: std.ArrayList([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) DependencyAnalyzer {
        return DependencyAnalyzer{
            .allocator = allocator,
            .modules = std.HashMap([]const u8, ModuleDependency, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .high_coupling_modules = std.ArrayList([]const u8).init(allocator),
            .circular_dependencies = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *DependencyAnalyzer) void {
        var iterator = self.modules.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.modules.deinit();
        self.high_coupling_modules.deinit();
        self.circular_dependencies.deinit();
    }
    
    /// 分析项目依赖关系
    pub fn analyzeProject(self: *DependencyAnalyzer, project_path: []const u8) !void {
        print("🔍 开始分析项目依赖关系...\n");
        print("📁 项目路径: {s}\n", project_path);
        print("=" ** 50 ++ "\n");
        
        // 1. 扫描所有 Zig 文件
        try self.scanZigFiles(project_path);
        
        // 2. 分析导入关系
        try self.analyzeImports();
        
        // 3. 计算耦合度
        try self.calculateCoupling();
        
        // 4. 检测循环依赖
        try self.detectCircularDependencies();
        
        // 5. 生成报告
        try self.generateReport();
    }
    
    /// 扫描 Zig 文件
    fn scanZigFiles(self: *DependencyAnalyzer, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            print("⚠️  无法打开目录: {s} - {}\n", .{ dir_path, err });
            return;
        };
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .directory) {
                // 递归扫描子目录
                const sub_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(sub_path);
                try self.scanZigFiles(sub_path);
            } else if (std.mem.endsWith(u8, entry.name, ".zig")) {
                // 分析 Zig 文件
                const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name });
                defer self.allocator.free(file_path);
                try self.analyzeZigFile(file_path);
            }
        }
    }
    
    /// 分析单个 Zig 文件
    fn analyzeZigFile(self: *DependencyAnalyzer, file_path: []const u8) !void {
        const content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 10 * 1024 * 1024) catch |err| {
            print("⚠️  无法读取文件: {s} - {}\n", .{ file_path, err });
            return;
        };
        defer self.allocator.free(content);
        
        var module = ModuleDependency.init(self.allocator, file_path);
        
        // 解析导入语句
        var lines = std.mem.split(u8, content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // 检测 @import 语句
            if (std.mem.indexOf(u8, trimmed, "@import(") != null) {
                if (self.extractImportPath(trimmed)) |import_path| {
                    try module.imports.append(try self.allocator.dupe(u8, import_path));
                }
            }
            
            // 检测 pub 导出
            if (std.mem.startsWith(u8, trimmed, "pub ")) {
                if (self.extractExportName(trimmed)) |export_name| {
                    try module.exports.append(try self.allocator.dupe(u8, export_name));
                }
            }
        }
        
        // 存储模块信息
        const path_copy = try self.allocator.dupe(u8, file_path);
        try self.modules.put(path_copy, module);
    }
    
    /// 提取导入路径
    fn extractImportPath(self: *DependencyAnalyzer, line: []const u8) ?[]const u8 {
        _ = self;
        if (std.mem.indexOf(u8, line, "@import(\"")) |start| {
            const quote_start = start + 9; // "@import(\"".len
            if (std.mem.indexOf(u8, line[quote_start..], "\"")) |end| {
                return line[quote_start..quote_start + end];
            }
        }
        return null;
    }
    
    /// 提取导出名称
    fn extractExportName(self: *DependencyAnalyzer, line: []const u8) ?[]const u8 {
        _ = self;
        // 简化实现：提取 pub 后的标识符
        if (std.mem.indexOf(u8, line, "pub ")) |start| {
            const after_pub = line[start + 4..];
            if (std.mem.indexOf(u8, after_pub, " ")) |space| {
                return after_pub[0..space];
            }
        }
        return null;
    }
    
    /// 分析导入关系
    fn analyzeImports(self: *DependencyAnalyzer) !void {
        print("\n📊 分析导入关系...\n");
        
        var iterator = self.modules.iterator();
        while (iterator.next()) |entry| {
            const module = entry.value_ptr;
            print("📄 {s}: {} 个导入, {} 个导出\n", .{ 
                entry.key_ptr.*, 
                module.imports.items.len, 
                module.exports.items.len 
            });
        }
    }
    
    /// 计算耦合度
    fn calculateCoupling(self: *DependencyAnalyzer) !void {
        print("\n🔗 计算模块耦合度...\n");
        
        var iterator = self.modules.iterator();
        while (iterator.next()) |entry| {
            const module = entry.value_ptr;
            
            // 简单的耦合度计算：导入数量 + 导出数量
            const coupling = @as(f32, @floatFromInt(module.imports.items.len + module.exports.items.len));
            module.coupling_score = coupling;
            
            // 高耦合阈值
            if (coupling > 10.0) {
                try self.high_coupling_modules.append(entry.key_ptr.*);
            }
        }
    }
    
    /// 检测循环依赖
    fn detectCircularDependencies(self: *DependencyAnalyzer) !void {
        print("\n🔄 检测循环依赖...\n");
        
        // 简化实现：检测直接的双向依赖
        var iterator = self.modules.iterator();
        while (iterator.next()) |entry| {
            const module_a = entry.value_ptr;
            const path_a = entry.key_ptr.*;
            
            for (module_a.imports.items) |import_path| {
                if (self.modules.get(import_path)) |module_b| {
                    // 检查 B 是否也导入 A
                    for (module_b.imports.items) |b_import| {
                        if (std.mem.eql(u8, b_import, path_a)) {
                            try self.circular_dependencies.append(path_a);
                            break;
                        }
                    }
                }
            }
        }
    }
    
    /// 生成分析报告
    fn generateReport(self: *DependencyAnalyzer) !void {
        print("\n" ++ "=" ** 60 ++ "\n");
        print("📋 依赖关系分析报告\n");
        print("=" ** 60 ++ "\n");
        
        print("\n📊 总体统计:\n");
        print("  总模块数: {}\n", .{self.modules.count()});
        print("  高耦合模块数: {}\n", .{self.high_coupling_modules.items.len});
        print("  循环依赖数: {}\n", .{self.circular_dependencies.items.len});
        
        if (self.high_coupling_modules.items.len > 0) {
            print("\n⚠️  高耦合模块:\n");
            for (self.high_coupling_modules.items) |module_path| {
                if (self.modules.get(module_path)) |module| {
                    print("  - {s} (耦合度: {d:.1})\n", .{ module_path, module.coupling_score });
                }
            }
        }
        
        if (self.circular_dependencies.items.len > 0) {
            print("\n🔄 循环依赖:\n");
            for (self.circular_dependencies.items) |module_path| {
                print("  - {s}\n", .{module_path});
            }
        }
        
        print("\n💡 重构建议:\n");
        if (self.high_coupling_modules.items.len > 0) {
            print("  1. 拆分高耦合模块，使用接口抽象\n");
            print("  2. 应用依赖注入模式\n");
            print("  3. 创建中间抽象层\n");
        }
        
        if (self.circular_dependencies.items.len > 0) {
            print("  4. 消除循环依赖，重新设计模块接口\n");
            print("  5. 使用事件驱动或观察者模式\n");
        }
        
        print("  6. 遵循单一职责原则\n");
        print("  7. 最小化模块间的直接依赖\n");
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var analyzer = DependencyAnalyzer.init(allocator);
    defer analyzer.deinit();
    
    try analyzer.analyzeProject("src");
}
