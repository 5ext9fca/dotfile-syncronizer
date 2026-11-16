# 统一声明

软件声明、配置路径、profile 和声明校验均由 dotfiles-viewer 维护。默认数据来自 Viewer 包资源；本项目不维护 software/items 或 workflow/profiles 副本。

安装入口 --catalog DIR / -Catalog DIR，或 DOTFILES_CATALOG，选择包含 software/items/*.toml 与 workflow/profiles/*.conf 的完整目录。显式目录整体替代缺省值，不合并。软件声明 v1、profile v3 保持原语义。

修改声明请在 Viewer 项目按其 docs/configuration.md 和 docs/llm-config-authoring.md 操作。安装执行策略 install/schema/execution.tsv 与观察策略 probes.tsv 仍归本项目。字段、来源、机制和依赖校验来自 Viewer，安装器只执行已验证规则。
