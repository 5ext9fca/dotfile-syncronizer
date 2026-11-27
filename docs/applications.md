# 应用配置覆盖

应用行为由用户本机配置决定。项目不再提供 Fish、Helix、终端或 Git 的预设内容；唯一配置路径来源是 Viewer 的 `software/items/*.toml`。

目前迁移的路径覆盖 macOS Zsh、Fish、Git、Helix、WezTerm、Zellij、Windows Terminal，以及显式选择的桌面字体设置。安装清单中的其他软件可以只有安装规则，不能据此声称其配置已采集。

Fish 保留 `fish_variables` 排除项。Git 的当前声明覆盖 XDG 配置目录，不自动包含 HOME/.gitconfig；如需更多路径，应明确添加到软件声明。桌面字体项采集 Fontconfig、KDE 和 GTK 的真实文件，不再生成字体设置；未使用该桌面环境时不要选择它。

Windows 与 WSL 分别创建快照；Windows 的配置根使用 home、app_data、local_app_data。相同平台迁移不改写配置文件里的用户名、绝对路径或特定应用版本语法。

macOS 的 zsh 声明采集 HOME 下的 .zshenv、.zshrc、.zprofile、.zsh_plugins.txt，以及配置目录中的 zsh 和 zsh-abbr/user-abbreviations。Starship 和 Atuin 分别只采集 starship.toml 和 atuin/config.toml。插件缓存、生成的 bundle 和命令历史留在本机。Linux 与 WSL 的默认 zsh 声明仅安装软件。Unix 完整 profile 仍包含 Fish，导出前须准备其配置或调整选择。
