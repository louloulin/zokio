# Zokio async/await 最佳实践

## 设计原则

### 1. 零成本抽象

Zokio的async/await实现遵循零成本抽象原则，确保异步代码的性能与手写的状态机相当。

```zig
// 好的做法：利用编译时优化
const OptimizedAsync = zokio.future.async_fn(struct {
    fn compute() u32 {
        // 简单计算会被编译器内联
        return 42 * 2;
    }
}.compute);

// 避免：不必要的复杂性
const OverComplexAsync = zokio.future.async_block(struct {
    fn execute() u32 {
        // 对于简单计算，直接使用同步代码更好
        const step1 = zokio.future.await_fn(SimpleAdd{ .params = .{ .arg0 = 40, .arg1 = 2 } });
        return step1;
    }
}.execute);
```

### 2. 类型安全

充分利用Zig的编译时类型检查，确保异步代码的正确性。

```zig
// 好的做法：明确的类型定义
const TypeSafeAsync = zokio.future.async_fn_with_params(struct {
    fn processData(input: []const u8) []const u8 {
        // 明确的输入输出类型
        return processString(input);
    }
}.processData);

// 编译时会检查类型匹配
const result = zokio.future.await_fn(TypeSafeAsync{ .params = .{ .arg0 = "字符串" } });
```

## 架构模式

### 1. 分层异步架构

```zig
// 数据层
const DataLayer = struct {
    const AsyncFetchUser = zokio.future.async_fn_with_params(struct {
        fn fetchUser(id: u32) []const u8 {
            // 数据库查询逻辑
            return "用户数据";
        }
    }.fetchUser);
    
    const AsyncSaveUser = zokio.future.async_fn_with_params(struct {
        fn saveUser(data: []const u8) u64 {
            // 保存逻辑
            return 12345;
        }
    }.saveUser);
};

// 业务层
const BusinessLayer = struct {
    const AsyncProcessUser = zokio.future.async_block(struct {
        fn execute() []const u8 {
            // 获取用户数据
            const user_data = zokio.future.await_fn(
                DataLayer.AsyncFetchUser{ .params = .{ .arg0 = 123 } }
            );
            
            // 业务逻辑处理
            const processed = processBusinessLogic(user_data);
            
            // 保存处理结果
            _ = zokio.future.await_fn(
                DataLayer.AsyncSaveUser{ .params = .{ .arg0 = processed } }
            );
            
            return processed;
        }
    }.execute);
};

// 表示层
const PresentationLayer = struct {
    const AsyncHandleRequest = zokio.future.async_block(struct {
        fn execute() []const u8 {
            const result = zokio.future.await_fn(BusinessLayer.AsyncProcessUser.init());
            return formatResponse(result);
        }
    }.execute);
};
```

### 2. 管道模式

```zig
const DataPipeline = struct {
    // 阶段1：数据获取
    const AsyncFetch = zokio.future.async_fn_with_params(struct {
        fn fetch(source: []const u8) []const u8 {
            return fetchFromSource(source);
        }
    }.fetch);
    
    // 阶段2：数据验证
    const AsyncValidate = zokio.future.async_fn_with_params(struct {
        fn validate(data: []const u8) []const u8 {
            return validateData(data);
        }
    }.validate);
    
    // 阶段3：数据转换
    const AsyncTransform = zokio.future.async_fn_with_params(struct {
        fn transform(data: []const u8) []const u8 {
            return transformData(data);
        }
    }.transform);
    
    // 阶段4：数据输出
    const AsyncOutput = zokio.future.async_fn_with_params(struct {
        fn output(data: []const u8) []const u8 {
            return outputData(data);
        }
    }.output);
    
    // 完整管道
    const AsyncPipeline = zokio.future.async_block(struct {
        fn execute() []const u8 {
            const fetched = zokio.future.await_fn(AsyncFetch{ .params = .{ .arg0 = "数据源" } });
            const validated = zokio.future.await_fn(AsyncValidate{ .params = .{ .arg0 = fetched } });
            const transformed = zokio.future.await_fn(AsyncTransform{ .params = .{ .arg0 = validated } });
            const output = zokio.future.await_fn(AsyncOutput{ .params = .{ .arg0 = transformed } });
            return output;
        }
    }.execute);
};
```

## 性能优化

### 1. 避免过度异步化

```zig
// 好的做法：只对I/O密集型操作使用异步
const AsyncFileProcessor = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 异步I/O操作
        const content = zokio.future.await_fn(readFileAsync("input.txt"));
        
        // 同步CPU密集型操作
        const processed = processCpuIntensive(content);
        
        // 异步I/O操作
        _ = zokio.future.await_fn(writeFileAsync("output.txt", processed));
        
        return "处理完成";
    }
}.execute);

// 避免：对CPU密集型操作过度异步化
const OverAsyncProcessor = zokio.future.async_block(struct {
    fn execute() u32 {
        // 不必要的异步化
        const a = zokio.future.await_fn(AsyncAdd{ .params = .{ .arg0 = 1, .arg1 = 2 } });
        const b = zokio.future.await_fn(AsyncMultiply{ .params = .{ .arg0 = a, .arg1 = 3 } });
        return b; // 这些操作直接用同步代码更高效
    }
}.execute);
```

### 2. 批量操作优化

```zig
// 好的做法：批量处理
const BatchProcessor = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 批量获取数据
        const batch_data = zokio.future.await_fn(
            AsyncBatchFetch{ .params = .{ .arg0 = "批量查询" } }
        );
        
        // 批量处理
        const processed = processBatch(batch_data);
        
        // 批量保存
        _ = zokio.future.await_fn(
            AsyncBatchSave{ .params = .{ .arg0 = processed } }
        );
        
        return "批量处理完成";
    }
}.execute);

// 避免：逐个处理
const IndividualProcessor = zokio.future.async_block(struct {
    fn execute() []const u8 {
        const items = [_]u32{ 1, 2, 3, 4, 5 };
        for (items) |item| {
            // 每个项目都单独异步处理，效率低
            _ = zokio.future.await_fn(AsyncProcessItem{ .params = .{ .arg0 = item } });
        }
        return "逐个处理完成";
    }
}.execute);
```

### 3. 内存管理优化

```zig
// 好的做法：使用栈分配和对象池
const MemoryOptimizedAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 使用栈分配的缓冲区
        var buffer: [4096]u8 = undefined;
        
        const result = zokio.future.await_fn(
            AsyncProcessWithBuffer{ .params = .{ .arg0 = &buffer } }
        );
        
        return result;
    }
}.execute);

// 避免：频繁的堆分配
const MemoryWastefulAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 每次都分配新内存，效率低
        const buffer = allocator.alloc(u8, 4096) catch return "内存分配失败";
        defer allocator.free(buffer);
        
        const result = zokio.future.await_fn(
            AsyncProcessWithBuffer{ .params = .{ .arg0 = buffer } }
        );
        
        return result;
    }
}.execute);
```

## 错误处理策略

### 1. 分层错误处理

```zig
// 底层：具体错误
const DatabaseError = error{
    ConnectionFailed,
    QueryTimeout,
    DataNotFound,
};

const AsyncDatabaseOp = zokio.future.async_fn_with_params(struct {
    fn query(sql: []const u8) DatabaseError![]const u8 {
        // 数据库操作可能失败
        if (std.mem.eql(u8, sql, "INVALID")) {
            return DatabaseError.QueryTimeout;
        }
        return "查询结果";
    }
}.query);

// 中层：业务错误
const BusinessError = error{
    InvalidInput,
    ProcessingFailed,
    ValidationError,
};

const AsyncBusinessLogic = zokio.future.async_block(struct {
    fn execute() (BusinessError || DatabaseError)![]const u8 {
        const data = zokio.future.await_fn(
            AsyncDatabaseOp{ .params = .{ .arg0 = "SELECT * FROM users" } }
        ) catch |err| switch (err) {
            DatabaseError.DataNotFound => return BusinessError.InvalidInput,
            else => return err,
        };
        
        return processBusinessData(data);
    }
}.execute);

// 顶层：用户友好的错误
const AsyncUserInterface = zokio.future.async_block(struct {
    fn execute() []const u8 {
        const result = zokio.future.await_fn(AsyncBusinessLogic.init()) catch |err| {
            return switch (err) {
                BusinessError.InvalidInput => "输入数据无效",
                BusinessError.ValidationError => "数据验证失败",
                DatabaseError.ConnectionFailed => "数据库连接失败",
                else => "系统错误",
            };
        };
        
        return result;
    }
}.execute);
```

### 2. 重试和恢复

```zig
const ResilientAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        var attempts: u32 = 0;
        const max_attempts = 3;
        
        while (attempts < max_attempts) {
            const result = zokio.future.await_fn(
                UnreliableOperation{ .params = .{ .arg0 = "数据" } }
            );
            
            // 检查操作是否成功
            if (!std.mem.eql(u8, result, "失败")) {
                return result;
            }
            
            attempts += 1;
            
            // 指数退避
            const delay_ms = @as(u64, 100) * (@as(u64, 1) << @intCast(attempts));
            std.time.sleep(delay_ms * std.time.ns_per_ms);
            
            std.debug.print("重试第 {} 次，延迟 {}ms\n", .{ attempts, delay_ms });
        }
        
        return "重试失败";
    }
}.execute);
```

### 3. 超时处理

```zig
const TimeoutAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        const start_time = std.time.milliTimestamp();
        const timeout_ms = 5000; // 5秒超时
        
        // 在实际实现中，这里会有更复杂的超时逻辑
        const result = zokio.future.await_fn(SlowOperation{ .params = .{ .arg0 = "数据" } });
        
        const elapsed = std.time.milliTimestamp() - start_time;
        if (elapsed > timeout_ms) {
            return "操作超时";
        }
        
        return result;
    }
}.execute);
```

## 测试策略

### 1. 单元测试

```zig
test "异步函数单元测试" {
    const testing = std.testing;
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();
    
    // 测试正常情况
    const normal_task = TestAsyncFunction{ .params = .{ .arg0 = "正常输入" } };
    const normal_result = try runtime.blockOn(normal_task);
    try testing.expectEqualStrings("期望输出", normal_result);
    
    // 测试边界情况
    const edge_task = TestAsyncFunction{ .params = .{ .arg0 = "" } };
    const edge_result = try runtime.blockOn(edge_task);
    try testing.expectEqualStrings("空输入处理", edge_result);
}
```

### 2. 集成测试

```zig
test "异步工作流集成测试" {
    const testing = std.testing;
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();
    
    // 测试完整的异步工作流
    const workflow = CompleteWorkflow.init();
    const result = try runtime.blockOn(workflow);
    
    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, "成功") != null);
}
```

### 3. 性能测试

```zig
test "异步函数性能测试" {
    const testing = std.testing;
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var runtime = zokio.SimpleRuntime.init(allocator, .{});
    defer runtime.deinit();
    try runtime.start();
    
    const iterations = 10000;
    const start_time = std.time.nanoTimestamp();
    
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        const task = PerformanceTestAsync{ .params = .{ .arg0 = i } };
        _ = try runtime.blockOn(task);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = end_time - start_time;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(duration_ns)) / 1_000_000_000.0);
    
    std.debug.print("性能测试: {d:.0} ops/sec\n", .{ops_per_sec});
    
    // 确保性能达到预期
    try testing.expect(ops_per_sec > 100_000); // 至少10万ops/sec
}
```

## 监控和调试

### 1. 性能监控

```zig
const MonitoredAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        const start_time = std.time.nanoTimestamp();
        
        const result = zokio.future.await_fn(MonitoredOperation{ .params = .{ .arg0 = "数据" } });
        
        const end_time = std.time.nanoTimestamp();
        const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
        
        // 记录性能指标
        std.debug.print("操作耗时: {d:.2}ms\n", .{duration_ms});
        
        // 性能告警
        if (duration_ms > 1000) {
            std.debug.print("⚠️ 性能告警：操作耗时超过1秒\n", .{});
        }
        
        return result;
    }
}.execute);
```

### 2. 调试日志

```zig
const DebugAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        std.debug.print("🚀 开始异步操作\n", .{});
        
        const step1_result = zokio.future.await_fn(DebugStep1{ .params = .{ .arg0 = "输入" } });
        std.debug.print("✅ 步骤1完成: {s}\n", .{step1_result});
        
        const step2_result = zokio.future.await_fn(DebugStep2{ .params = .{ .arg0 = step1_result } });
        std.debug.print("✅ 步骤2完成: {s}\n", .{step2_result});
        
        std.debug.print("🎉 异步操作完成\n", .{});
        return step2_result;
    }
}.execute);
```

### 3. 错误追踪

```zig
const TrackedAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        const operation_id = generateOperationId();
        std.debug.print("📋 操作ID: {}\n", .{operation_id});
        
        const result = zokio.future.await_fn(
            TrackedOperation{ .params = .{ .arg0 = "数据" } }
        ) catch |err| {
            std.debug.print("❌ 操作失败 [ID: {}]: {}\n", .{ operation_id, err });
            return "操作失败";
        };
        
        std.debug.print("✅ 操作成功 [ID: {}]\n", .{operation_id});
        return result;
    }
}.execute);
```

## 部署和运维

### 1. 配置管理

```zig
const ProductionConfig = struct {
    max_retries: u32 = 3,
    timeout_ms: u64 = 5000,
    batch_size: u32 = 100,
    enable_monitoring: bool = true,
};

const ConfigurableAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        const config = ProductionConfig{};
        
        var attempts: u32 = 0;
        while (attempts < config.max_retries) {
            const result = zokio.future.await_fn(
                ConfigurableOperation{ .params = .{ .arg0 = "数据" } }
            );
            
            if (!std.mem.eql(u8, result, "失败")) {
                if (config.enable_monitoring) {
                    std.debug.print("📊 操作成功，尝试次数: {}\n", .{attempts + 1});
                }
                return result;
            }
            
            attempts += 1;
        }
        
        return "配置化重试失败";
    }
}.execute);
```

### 2. 健康检查

```zig
const HealthCheckAsync = zokio.future.async_block(struct {
    fn execute() []const u8 {
        // 检查数据库连接
        const db_status = zokio.future.await_fn(CheckDatabase{ .params = .{ .arg0 = "health" } });
        if (std.mem.eql(u8, db_status, "失败")) {
            return "数据库不健康";
        }
        
        // 检查外部服务
        const service_status = zokio.future.await_fn(CheckExternalService{ .params = .{ .arg0 = "ping" } });
        if (std.mem.eql(u8, service_status, "失败")) {
            return "外部服务不健康";
        }
        
        return "系统健康";
    }
}.execute);
```

## 总结

遵循这些最佳实践可以帮助你：

1. **构建高性能的异步应用** - 利用Zokio的零成本抽象
2. **编写可维护的代码** - 清晰的架构和错误处理
3. **确保系统可靠性** - 完善的测试和监控
4. **优化资源使用** - 高效的内存和CPU利用

记住，异步编程的目标是提高系统的并发性和响应性，而不是让所有操作都变成异步。明智地选择何时使用异步，何时使用同步，是构建高效系统的关键。
