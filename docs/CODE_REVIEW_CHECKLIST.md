# 🔍 Zokio 代码审查检查清单

> **目标**: 确保所有代码变更都符合 Zokio 项目的质量标准和最佳实践

---

## 📋 **审查前准备**

### **审查者准备**
- [ ] 理解 PR 的目的和背景
- [ ] 检查相关的 Issue 和设计文档
- [ ] 确认 PR 描述完整且清晰
- [ ] 验证 PR 大小合理（建议 <500 行变更）

### **自动化检查**
- [ ] CI/CD 流水线全部通过
- [ ] 代码格式化检查通过 (`zig fmt`)
- [ ] 编译检查无警告
- [ ] 所有测试通过
- [ ] 代码覆盖率满足要求 (>95%)

---

## 🎯 **代码质量检查**

### **1. 代码风格和格式**
- [ ] **命名规范**
  - [ ] 变量和函数使用 `snake_case`
  - [ ] 类型和结构体使用 `PascalCase`
  - [ ] 常量使用 `SCREAMING_SNAKE_CASE`
  - [ ] 文件名使用 `snake_case.zig`

- [ ] **注释和文档**
  - [ ] 所有公共 API 都有文档注释 (`///`)
  - [ ] 文档注释使用中文
  - [ ] 复杂逻辑有内联注释
  - [ ] 注释格式正确 (`// ` 后有空格)

- [ ] **代码格式**
  - [ ] 缩进使用 4 个空格
  - [ ] 行长度不超过 100 字符
  - [ ] 无尾随空格
  - [ ] 无制表符

### **2. 架构和设计**
- [ ] **模块化设计**
  - [ ] 模块职责单一且清晰
  - [ ] 接口设计合理
  - [ ] 依赖关系清晰，无循环依赖
  - [ ] 适当的抽象层次

- [ ] **错误处理**
  - [ ] 使用统一的错误处理系统
  - [ ] 错误信息清晰有用
  - [ ] 适当的错误传播
  - [ ] 资源清理正确

- [ ] **内存管理**
  - [ ] 内存分配和释放配对
  - [ ] 使用适当的分配器
  - [ ] 避免内存泄漏
  - [ ] 正确处理 OOM 情况

### **3. 性能考虑**
- [ ] **算法效率**
  - [ ] 时间复杂度合理
  - [ ] 空间复杂度合理
  - [ ] 避免不必要的分配
  - [ ] 缓存友好的数据结构

- [ ] **编译时优化**
  - [ ] 适当使用 `comptime`
  - [ ] 避免运行时开销
  - [ ] 利用 Zig 的零成本抽象

- [ ] **并发安全**
  - [ ] 正确使用同步原语
  - [ ] 避免数据竞争
  - [ ] 线程安全的设计
  - [ ] 适当的原子操作

---

## 🧪 **测试质量检查**

### **测试覆盖**
- [ ] 新功能有对应的单元测试
- [ ] 边界条件有测试覆盖
- [ ] 错误路径有测试覆盖
- [ ] 性能关键代码有基准测试

### **测试质量**
- [ ] 测试名称描述清晰
- [ ] 测试独立且可重复
- [ ] 测试数据合理
- [ ] 断言明确且有意义

### **测试组织**
- [ ] 测试文件位置正确
- [ ] 测试分类合理（单元/集成/性能）
- [ ] 测试工具使用正确
- [ ] Mock 和 Fixture 使用适当

---

## 🔒 **安全性检查**

### **内存安全**
- [ ] 无缓冲区溢出风险
- [ ] 无空指针解引用
- [ ] 无 use-after-free
- [ ] 正确的边界检查

### **并发安全**
- [ ] 无数据竞争
- [ ] 正确的锁使用
- [ ] 避免死锁
- [ ] 原子操作正确

### **输入验证**
- [ ] 外部输入有验证
- [ ] 参数范围检查
- [ ] 类型安全
- [ ] 防止注入攻击

---

## 📚 **文档和可维护性**

### **代码可读性**
- [ ] 代码逻辑清晰
- [ ] 变量名有意义
- [ ] 函数职责单一
- [ ] 复杂度适中

### **文档完整性**
- [ ] API 文档完整
- [ ] 使用示例清晰
- [ ] 设计决策有记录
- [ ] 已知限制有说明

### **向后兼容性**
- [ ] API 变更有迁移指南
- [ ] 破坏性变更有充分理由
- [ ] 版本号更新正确
- [ ] 变更日志更新

---

## 🚀 **Zokio 特定检查**

### **异步编程**
- [ ] 正确使用 `async`/`await`
- [ ] 避免阻塞操作
- [ ] 适当的并发控制
- [ ] 事件循环集成正确

### **libxev 集成**
- [ ] 正确使用 libxev API
- [ ] 错误处理完整
- [ ] 资源清理正确
- [ ] 跨平台兼容性

### **性能要求**
- [ ] 满足性能目标
- [ ] 基准测试通过
- [ ] 内存使用合理
- [ ] 延迟控制良好

---

## ✅ **最终检查**

### **代码审查完成**
- [ ] 所有检查项目都已确认
- [ ] 发现的问题都已解决
- [ ] 代码变更符合项目标准
- [ ] 准备合并到主分支

### **审查反馈**
- [ ] 反馈具体且建设性
- [ ] 提供改进建议
- [ ] 认可好的实践
- [ ] 记录学习点

---

## 📝 **审查模板**

```markdown
## 代码审查反馈

### ✅ 优点
- [列出代码的优点和好的实践]

### ⚠️ 需要改进
- [列出需要改进的地方，提供具体建议]

### 🔍 详细评论
- [针对具体代码行的详细评论]

### 📊 测试评估
- [测试覆盖率和质量评估]

### 🚀 性能评估
- [性能影响评估]

### 📚 文档评估
- [文档完整性和质量评估]

### 🎯 总体评价
- [ ] 批准合并
- [ ] 需要修改后重新审查
- [ ] 需要重大修改

### 💡 学习点
- [从这次审查中学到的东西]
```

---

## 🔧 **工具和资源**

### **自动化工具**
- `zig fmt` - 代码格式化
- `zig build test` - 运行测试
- `zig build benchmark` - 性能测试
- `tools/scripts/code_style_checker.zig` - 代码风格检查

### **参考资源**
- [Zig 风格指南](https://ziglang.org/documentation/master/#Style-Guide)
- [Zokio 贡献指南](../CONTRIBUTING.md)
- [Zokio 架构设计](docs/internals/architecture.md)
- [性能基准](benchmarks/README.md)

---

*📝 检查清单版本: v1.0 | 更新时间: 2025-01-19 | 维护者: Zokio 开发团队*
