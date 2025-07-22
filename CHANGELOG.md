# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 项目重构为顶级开源项目标准
- 完整的模块化架构设计
- 标准的开源项目文件和规范
- 完善的测试体系和CI/CD流程
- 专业的文档系统和API文档

### Changed
- 重构项目目录结构
- 优化核心代码模块组织
- 改进性能基准测试系统

### Fixed
- AsyncEventLoop全局互斥锁问题
- 性能测试目标调整
- 内存分配优化

## [0.8.0] - 2025-12-09

### Added
- 修复AsyncEventLoop全局互斥锁问题
- 添加精确隔离测试验证功能
- 优化性能测试目标

### Performance
- 任务调度性能：251M ops/sec (超越目标251倍)
- Future轮询性能：247M ops/sec (超越目标164倍)
- 事件循环性能：2.8M ops/sec (超越目标28倍)
- Waker调用性能：493M ops/sec (超越目标98倍)
- 内存分配性能：107K ops/sec (超越目标2.1倍)
- 并发任务性能：14.7M ops/sec (超越目标294倍)

### Tests
- 单元测试：15/15 通过 (100%)
- 集成测试：4/4 通过 (100%)
- 性能测试：6/6 通过 (100%)

## [0.7.0] - 2025-12-08

### Added
- libxev深度集成优化
- 真实异步I/O实现
- 高性能调度器

### Changed
- 完全基于libxev的I/O后端
- 优化内存分配策略
- 改进错误处理机制

## [0.6.0] - 2025-12-07

### Added
- HTTP服务器优化
- 阶段性性能提升
- 并发连接处理

### Performance
- HTTP服务器性能大幅提升
- 支持高并发连接
- 内存使用优化

## [0.5.0] - 2025-12-06

### Added
- 基础异步运行时实现
- Future和Task系统
- 基本的I/O操作支持

### Features
- async/await语法支持
- 事件驱动架构
- 跨平台兼容性

## [0.1.0] - 2025-12-01

### Added
- 项目初始化
- 基础架构设计
- 核心概念实现

---

## 版本说明

- **Major版本**：不兼容的API更改
- **Minor版本**：向后兼容的功能添加
- **Patch版本**：向后兼容的错误修复

## 贡献指南

请参阅 [CONTRIBUTING.md](CONTRIBUTING.md) 了解如何为项目做出贡献。

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。
