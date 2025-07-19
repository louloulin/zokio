# Zokio源代码模块重组计划

## 🎯 **重组目标**

将当前的src目录重新组织为清晰的分层架构，提高代码的可维护性和可扩展性。

## 📊 **当前结构分析**

### 现有模块
```
src/
├── lib.zig              # 主入口
├── bench/               # 基准测试 (应移到Extension Layer)
├── core/                # 核心模块 (空目录，需要填充)
├── error/               # 错误处理 (独立系统)
├── fs/                  # 文件系统 (I/O Layer)
├── future/              # Future实现 (Core Layer)
├── io/                  # I/O操作 (I/O Layer)
├── memory/              # 内存管理 (Utility Layer)
├── metrics/             # 监控指标 (Extension Layer)
├── net/                 # 网络模块 (I/O Layer)
├── runtime/             # 运行时 (Core Layer)
├── scheduler/           # 调度器 (Core Layer)
├── sync/                # 同步原语 (Utility Layer)
├── testing/             # 测试工具 (Extension Layer)
├── time/                # 时间处理 (Utility Layer)
├── tracing/             # 链路追踪 (Extension Layer)
└── utils/               # 工具函数 (Utility Layer)
```

### 问题分析
1. **core/目录为空** - 核心模块分散在其他目录
2. **模块职责不清** - 一些模块跨越多个层次
3. **依赖关系复杂** - 缺乏清晰的依赖层次
4. **扩展模块混杂** - bench、metrics、testing等混在核心模块中

## 🏗️ **新分层架构设计**

### **Core Layer (核心层)**
```
src/core/
├── mod.zig              # 核心模块入口
├── runtime.zig          # 运行时核心 (从runtime/runtime.zig移动)
├── future.zig           # Future抽象 (从future/future.zig移动)
├── scheduler.zig        # 任务调度器 (从scheduler/scheduler.zig移动)
├── context.zig          # 执行上下文 (新建)
├── waker.zig            # Waker系统 (从runtime/waker.zig移动)
└── task.zig             # 任务抽象 (新建)
```

### **I/O Layer (I/O层)**
```
src/io/
├── mod.zig              # I/O模块入口
├── async_file.zig       # 异步文件I/O (保持)
├── async_net.zig        # 异步网络I/O (保持)
├── libxev_driver.zig    # libxev驱动 (从io/libxev.zig重命名)
├── completion_bridge.zig # 完成事件桥接 (从runtime/completion_bridge.zig移动)
├── zero_copy.zig        # 零拷贝I/O (保持)
└── buffer.zig           # 缓冲区管理 (新建)

src/net/
├── mod.zig              # 网络模块入口 (保持)
├── tcp.zig              # TCP实现 (保持)
├── udp.zig              # UDP实现 (保持)
├── http.zig             # HTTP协议 (保持)
├── tls.zig              # TLS/SSL (保持)
├── socket.zig           # Socket抽象 (保持)
└── address.zig          # 地址解析 (新建)

src/fs/
├── mod.zig              # 文件系统入口 (保持)
├── file.zig             # 文件操作 (保持)
├── dir.zig              # 目录操作 (保持)
├── metadata.zig         # 文件元数据 (保持)
├── watch.zig            # 文件监控 (保持)
└── permissions.zig      # 权限管理 (新建)
```

### **Utility Layer (工具层)**
```
src/utils/
├── mod.zig              # 工具模块入口
├── sync.zig             # 同步原语 (从sync/sync.zig移动)
├── time.zig             # 时间处理 (从time/time.zig移动)
├── memory.zig           # 内存管理 (从memory/memory.zig移动)
├── platform.zig        # 平台抽象 (保持)
├── collections.zig      # 集合类型 (新建)
├── atomic.zig           # 原子操作 (新建)
└── math.zig             # 数学工具 (新建)
```

### **Extension Layer (扩展层)**
```
src/ext/
├── mod.zig              # 扩展模块入口
├── metrics.zig          # 监控指标 (从metrics/metrics.zig移动)
├── tracing.zig          # 链路追踪 (从tracing/tracer.zig移动)
├── testing.zig          # 测试工具 (从testing/testing.zig移动)
├── bench.zig            # 基准测试 (从bench/移动并合并)
├── profiling.zig        # 性能分析 (新建)
└── debugging.zig        # 调试工具 (新建)
```

### **Error System (错误处理系统)**
```
src/error/
├── mod.zig              # 错误处理入口 (保持)
├── zokio_error.zig      # Zokio错误类型 (保持)
├── error_codes.zig      # 错误代码定义 (新建)
├── recovery.zig         # 错误恢复机制 (新建)
└── logging.zig          # 错误日志 (从error_logger.zig重命名)
```

## 🔄 **重组实施步骤**

### **Step 1: 创建新目录结构**
```bash
mkdir -p src/core src/ext
```

### **Step 2: 移动核心模块**
```bash
# 移动核心运行时组件到core/
mv src/runtime/runtime.zig src/core/
mv src/runtime/waker.zig src/core/
mv src/future/future.zig src/core/
mv src/scheduler/scheduler.zig src/core/

# 移动I/O相关组件
mv src/runtime/completion_bridge.zig src/io/
mv src/io/libxev.zig src/io/libxev_driver.zig
```

### **Step 3: 移动工具模块**
```bash
# 合并工具模块到utils/
mv src/sync/sync.zig src/utils/
mv src/time/time.zig src/utils/
mv src/memory/memory.zig src/utils/
```

### **Step 4: 移动扩展模块**
```bash
# 移动扩展功能到ext/
mv src/metrics/metrics.zig src/ext/
mv src/tracing/tracer.zig src/ext/tracing.zig
mv src/testing/testing.zig src/ext/
mv src/bench/* src/ext/ # 合并到bench.zig
```

### **Step 5: 清理空目录**
```bash
# 删除空目录
rmdir src/sync src/time src/metrics src/tracing src/testing src/bench
```

### **Step 6: 更新模块入口文件**
- 更新src/lib.zig中的导入路径
- 创建各层的mod.zig入口文件
- 更新build.zig中的模块配置

## 📋 **依赖关系设计**

### **依赖层次**
```
Extension Layer (src/ext/)
    ↓ 可以依赖所有下层
Utility Layer (src/utils/)
    ↓ 可以依赖Core Layer
I/O Layer (src/io/, src/net/, src/fs/)
    ↓ 依赖Core Layer和部分Utility Layer
Core Layer (src/core/)
    ↓ 基础层，不依赖其他业务层
Error System (src/error/)
    ↓ 被所有层使用，但不依赖业务层
```

### **模块导入规则**
1. **Core Layer**: 只能导入error模块
2. **I/O Layer**: 可以导入core和error模块
3. **Utility Layer**: 可以导入core和error模块
4. **Extension Layer**: 可以导入所有其他层
5. **Error System**: 不依赖任何业务层

## 🎯 **重组后的优势**

1. **清晰的架构层次** - 明确的依赖关系和职责边界
2. **更好的可维护性** - 模块职责单一，易于理解和修改
3. **增强的可扩展性** - 扩展层独立，易于添加新功能
4. **简化的测试** - 分层测试，降低测试复杂度
5. **优化的编译时间** - 减少不必要的依赖，提高编译效率

## ⚠️ **注意事项**

1. **保持API兼容性** - 重组过程中保持对外API不变
2. **渐进式重构** - 分步骤实施，确保每步都可编译
3. **更新文档** - 同步更新API文档和架构文档
4. **测试验证** - 每个步骤后运行完整测试套件

---

**下一步**: 开始实施Step 1，创建新的目录结构。
