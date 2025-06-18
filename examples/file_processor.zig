//! 文件处理示例
//!
//! 展示Zokio的异步文件I/O能力

const std = @import("std");
const zokio = @import("zokio");

/// 文件读取任务
const FileReader = struct {
    path: []const u8,
    content: ?[]u8 = null,
    allocator: std.mem.Allocator,

    const Self = @This();
    pub const Output = []u8;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll([]u8) {
        _ = ctx;

        if (self.content != null) {
            return .{ .ready = self.content.? };
        }

        std.debug.print("异步读取文件: {s}\n", .{self.path});

        // 简化实现：同步读取文件（在实际实现中会是异步的）
        const file = std.fs.cwd().openFile(self.path, .{}) catch |err| {
            std.debug.print("打开文件失败: {}\n", .{err});
            // 在实际实现中，这里会返回错误
            self.content = self.allocator.alloc(u8, 0) catch unreachable;
            return .{ .ready = self.content.? };
        };
        defer file.close();

        const file_size = file.getEndPos() catch 0;
        const content = self.allocator.alloc(u8, file_size) catch |err| {
            std.debug.print("分配内存失败: {}\n", .{err});
            self.content = self.allocator.alloc(u8, 0) catch unreachable;
            return .{ .ready = self.content.? };
        };

        _ = file.readAll(content) catch |err| {
            std.debug.print("读取文件失败: {}\n", .{err});
            self.allocator.free(content);
            self.content = self.allocator.alloc(u8, 0) catch unreachable;
            return .{ .ready = self.content.? };
        };

        self.content = content;
        std.debug.print("文件读取完成，大小: {} 字节\n", .{content.len});

        return .{ .ready = content };
    }

    pub fn deinit(self: *Self) void {
        if (self.content) |content| {
            self.allocator.free(content);
        }
    }
};

/// 文件写入任务
const FileWriter = struct {
    path: []const u8,
    content: []const u8,
    written: bool = false,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        _ = ctx;

        if (self.written) {
            return .{ .ready = {} };
        }

        std.debug.print("异步写入文件: {s}\n", .{self.path});

        // 简化实现：同步写入文件（在实际实现中会是异步的）
        const file = std.fs.cwd().createFile(self.path, .{}) catch |err| {
            std.debug.print("创建文件失败: {}\n", .{err});
            self.written = true;
            return .{ .ready = {} };
        };
        defer file.close();

        file.writeAll(self.content) catch |err| {
            std.debug.print("写入文件失败: {}\n", .{err});
            self.written = true;
            return .{ .ready = {} };
        };

        self.written = true;
        std.debug.print("文件写入完成，大小: {} 字节\n", .{self.content.len});

        return .{ .ready = {} };
    }
};

/// 文件处理任务
const FileProcessor = struct {
    input_path: []const u8,
    output_path: []const u8,
    allocator: std.mem.Allocator,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        std.debug.print("开始处理文件: {s} -> {s}\n", .{ self.input_path, self.output_path });

        // 读取输入文件
        var reader = FileReader{
            .path = self.input_path,
            .allocator = self.allocator,
        };
        defer reader.deinit();

        const content = switch (reader.poll(ctx)) {
            .ready => |data| data,
            .pending => return .pending,
        };

        // 处理内容（示例：转换为大写）
        var processed_content = self.allocator.alloc(u8, content.len) catch |err| {
            std.debug.print("分配内存失败: {}\n", .{err});
            return .{ .ready = {} };
        };
        defer self.allocator.free(processed_content);

        for (content, 0..) |char, i| {
            processed_content[i] = std.ascii.toUpper(char);
        }

        std.debug.print("内容处理完成，转换为大写\n");

        // 写入输出文件
        var writer = FileWriter{
            .path = self.output_path,
            .content = processed_content,
        };

        switch (writer.poll(ctx)) {
            .ready => {},
            .pending => return .pending,
        }

        std.debug.print("文件处理完成\n");
        return .{ .ready = {} };
    }
};

/// 批量文件处理任务
const BatchFileProcessor = struct {
    tasks: []FileProcessor,
    current_index: usize = 0,

    const Self = @This();
    pub const Output = void;

    pub fn poll(self: *Self, ctx: *zokio.Context) zokio.Poll(void) {
        while (self.current_index < self.tasks.len) {
            switch (self.tasks[self.current_index].poll(ctx)) {
                .ready => {
                    self.current_index += 1;
                    std.debug.print("任务 {}/{} 完成\n", .{ self.current_index, self.tasks.len });
                },
                .pending => return .pending,
            }
        }

        std.debug.print("所有文件处理任务完成\n");
        return .{ .ready = {} };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Zokio 文件处理示例 ===\n", .{});

    // 创建运行时配置
    const config = zokio.RuntimeConfig{
        .worker_threads = 2,
        .enable_work_stealing = true,
        .enable_io_uring = true,
        .enable_metrics = true,
    };

    // 创建运行时实例
    const RuntimeType = zokio.ZokioRuntime(config);
    var runtime = try RuntimeType.init(allocator);
    defer runtime.deinit();

    std.debug.print("运行时创建成功\n", .{});

    // 启动运行时
    try runtime.start();
    defer runtime.stop();

    // 创建测试文件
    const test_content = "Hello, Zokio!\nThis is a test file for async file processing.\n";

    std.debug.print("\n=== 创建测试文件 ===\n", .{});
    const create_task = FileWriter{
        .path = "test_input.txt",
        .content = test_content,
    };
    try runtime.blockOn(create_task);

    // 单个文件处理
    std.debug.print("\n=== 单个文件处理 ===\n", .{});
    const single_processor = FileProcessor{
        .input_path = "test_input.txt",
        .output_path = "test_output.txt",
        .allocator = allocator,
    };
    try runtime.blockOn(single_processor);

    // 批量文件处理
    std.debug.print("\n=== 批量文件处理 ===\n", .{});

    var processors = [_]FileProcessor{
        FileProcessor{
            .input_path = "test_input.txt",
            .output_path = "batch_output1.txt",
            .allocator = allocator,
        },
        FileProcessor{
            .input_path = "test_input.txt",
            .output_path = "batch_output2.txt",
            .allocator = allocator,
        },
    };

    const batch_processor = BatchFileProcessor{
        .tasks = &processors,
    };
    try runtime.blockOn(batch_processor);

    std.debug.print("\n=== 文件处理示例完成 ===\n", .{});
    std.debug.print("生成的文件:\n", .{});
    std.debug.print("- test_input.txt (输入文件)\n", .{});
    std.debug.print("- test_output.txt (单个处理输出)\n", .{});
    std.debug.print("- batch_output1.txt (批量处理输出1)\n", .{});
    std.debug.print("- batch_output2.txt (批量处理输出2)\n", .{});
}
