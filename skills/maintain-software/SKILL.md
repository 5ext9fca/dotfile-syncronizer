---
name: maintain-software
description: 定位 Viewer 的统一软件声明并按其指南维护，在 syncronizer 验证安装行为。
---

# 维护统一声明

声明唯一来源已迁入 dotfile-viewer。本项目不维护软件与 profile 副本。先定位用户指定的 Viewer checkout 或外部 catalog，阅读其 AGENTS.md、docs/configuration.md、docs/llm-config-authoring.md；按这些文档修改并做无安装验证。

涉及安装机制时读取本项目对应 handler 和 install/schema/execution.tsv，执行当前主机 dry-run。使用预先准备的 Python 3.14 与 Viewer 依赖，不采集真实配置作为测试，不隐式安装软件或应用快照。验证记录写入 tests/acceptance.md。
