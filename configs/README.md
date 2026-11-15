# 被管理应用的配置源

这里集中保存要交付给被管理应用的原生配置。名称 `configs` 表示配置内容的来源，不是安装器运行参数的统一目录，也不表示要原样复制到用户的 `~/.config/`。

- `fish/`、`git/`、`helix/`、`wezterm/`、`zellij/`：Unix 应用配置，按声明逐文件硬链接到目标位置。
- `fontconfig/`：原生 Linux KDE 的正文/等宽字体选择规则；由 desktop-fonts 显式部署。
- `windows-terminal/`：Windows Terminal 配置，按声明复制到 LocalState。

**目录位置不决定部署行为。** `apply/items/` 决定组件源文件、目标和排除项，`workflow/profiles/` 决定完整流程选择哪些组件。源路径仍相对仓库根填写，例如 `source=configs/fish`；目标仍是 `target=fish`，组件 ID 也仍是 `fish`。不要把整个 configs 目录当作部署单元。

安装软件、配置部署、流程选择和镜像策略的控制声明分别位于仓库根下的 `install/`、`apply/`、`workflow/`、`mirrors/`，不因本目录名称而归入这里。

新增或修改配置见 [LLM 配置生成指南](../docs/llm-config-authoring.md)；部署和恢复命令见 [apply 手册](../apply/README.md)；各应用行为见 [应用配置](../docs/applications.md)。
