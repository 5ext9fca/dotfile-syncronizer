# 声明维护入口

声明唯一所有者是 dotfiles-viewer。请在 Viewer checkout 阅读其 AGENTS.md、docs/configuration.md 和 docs/llm-config-authoring.md 后维护默认声明，或明确选择外部 catalog。不要在 syncronizer 重建 software/items 或 workflow/profiles 副本。

安装机制实现仍位于本项目，执行策略位于 install/schema/execution.tsv。修改规则后执行 Viewer 声明校验及隔离快照测试；涉及安装行为时在本项目执行对应主机 dry-run，不执行真实安装作为声明验证。
