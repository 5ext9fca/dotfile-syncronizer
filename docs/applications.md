# 应用配置

此页解释仓库当前文件，不承诺这些偏好适用于所有应用版本。配置部署由 [apply](../apply/README.md) 声明控制；安装软件与应用首次运行/授权是不同步骤。

## Fish

`configs/fish/config.fish` 在交互 shell 中按命令是否存在初始化 mise、Starship、Zoxide。conf.d 分层为环境、路径、别名；镜像模块生成的 `15-mirrors.fish` 位于部署目标，不作为普通仓库源片段维护。

- EDITOR/VISUAL 为 hx，PAGER 为 less，MANPAGER 为 `less -R`。
- 已存在的用户 bin、Cargo、OpenCode、mise shims、Flutter、Snap 等路径按声明优先级加入；macOS 根据当前 Homebrew prefix 构建相关路径，不写死 formula 版本目录。
- 不替换 ls/cat/less/grep 的标准含义；存在 Eza 时提供 l/ll/la/lt，存在 Bat 时提供 bcat/bless；cgrep 打开彩色 grep。
- 保留 Fish 默认按键；Ctrl+左右用于单词移动。
- 交互 SSH 或识别到的独立终端中自动启动一个新的 Zellij 会话；跳过 VS Code、非终端输入输出和已有 multiplexer。设置 `DOTFILES_NO_ZELLIJ` 可禁用，手动恢复会话使用 `zellij attach`。
- `fish_variables` 是应用状态，apply 明确排除。

## Helix

使用 onedark、相对行号、多个 buffer 时的 bufferline、缩进引导及光标行。文件选择器显示隐藏文件。Python 使用 `ty server` 和 Ruff，Ruff 不负责 hover；Python/Rust/C/C++ 开启自动格式化。

软件和语言服务需已安装；单独 apply 不补装 ty/Ruff。`config.toml` 控制编辑器行为，`languages.toml` 控制语言服务，不将两者误作安装项 components。

## WezTerm

字体回退为 JetBrainsMono Nerd Font / Noto Sans CJK SC，字号 14，Tokyo Night，窗口透明度 0.9。只在多个 tab 时显示 tab bar；关闭窗口和配置的 Cmd+W 操作要求确认。macOS 启动全屏并启用背景模糊，原生 Linux 启动最大化；WSL 不触发原生 Linux 窗口逻辑。

默认安装流程包含 JetBrainsMono Nerd Font，来源与环境范围见 [字体安装](../install/README.md#终端字体)。单独 apply 不安装字体。原生 KDE 的 `desktop-fonts` 配置桌面默认正文为 Noto Sans CJK SC、等宽为 JetBrainsMono/Noto CJK，保留 WezTerm 的现有回退链，见 [桌面字体](../apply/README.md#桌面字体)。配置未对窗口系统或图形服务做健康验证。

原生 Linux 在 `gui-startup` 创建窗口后立即请求最大化。Fish 在本机 Linux WezTerm 中自动启动 Zellij 前，每 0.1 秒读取一次 PTY 尺寸，等待尺寸连续 0.5 秒不变，最多等待约 2 秒；读取失败则直接继续。此等待用于缓解 Zellij 启动与窗口最大化之间的尺寸竞态，不保证窗口管理器一定在期限内完成调整。SSH、WSL 和其他终端不增加等待。修改后需重新启动 WezTerm 验证，配置热重载不会重新执行启动事件。

## Zellij 与复制

本地 pane 使用外层终端字体；网页终端指定 JetBrainsMono Nerd Font，浏览器所在机器也需安装该字体。

默认 locked 模式只处理 Ctrl+g，其余按键传给应用。Ctrl+g 解锁后，`p`、`n` 新建 pane，`t`、`n` 新建 tab；Ctrl+g 或相应 Esc 返回锁定模式。Alt 管理快捷键只在解锁模式生效。

Zellij pane 中拖拽选择后通过 OSC 52 复制；这是 Zellij 的选区，不是外层终端的选区。应用自己捕获鼠标时，可使用应用复制操作，或按 Shift 拖拽交给外层终端。终端自身的复制快捷键仍由终端处理。

## Git 与 Windows Terminal

Unix 的 `configs/git/config` 部署到 XDG Git 配置目录。脱敏版本不携带 Git 姓名或邮箱；Windows workflow 的 git 阶段默认没有身份设置项。请在各主机使用 `git config --global user.name` 和 `git config --global user.email` 配置自己的身份。

Windows Terminal 源文件使用 JSONC，配置 PowerShell 7 为默认 profile，并列出 FedoraLinux-44。列出某个分发并不表示 installer 会创建或配置它。当前字体为 JetBrainsMono Nerd Font，主题 Tokyo Night，启动最大化。

PowerShell profile 中的 `POWERSHELL_UPDATECHECK=Off` 是仓库保留的启动通知兼容设置，维护时根据目标版本判断，不在文档中宣称它已失效。Terminal 更新采用整份文件复制；需保留个人改动时先审查源文件与备份。

Clash/Mihomo 配置及订阅分发服务已迁移至独立的 `clash-config` 仓库。
