# Dotfile Syncronizer

跨平台安装器与配置仓库，默认只部署应用配置。完整软件环境需显式选择 `*-full` profile。可多次手动运行，按当前声明检查并跳过已有软件，安装缺失项、部署配置并记录结果；允许失败后人工处理，再重新运行或断点续跑。安装成功表示命令按执行策略正常退出，不进行安装后存在性复核。

支持 Linux 的 APT、DNF（包括原生 Fedora）、Pacman 分支、macOS，以及 Windows 主机和可选的已有 WSL2 分发。Linux 分支按可用包管理器选择，不按发行版名称选择。

## 脱敏版本与本机身份

本项目从源代码快照创建，不包含原仓库 Git 历史、远端配置、Clash 残留或 Python 缓存。仓库不保存个人 Git 姓名、邮箱或凭据，Windows workflow 也不写入预设身份。请在每台主机上自行设置：

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

不要将真实凭据提交到仓库。Python 缓存、`.venv/` 和本地 `.env` 文件由 `.gitignore` 排除。

## `configs/` 的用途

`configs/` 保存**被管理应用的配置源文件**，例如 Fish、Helix 和 Windows Terminal 的原生配置。这里的“配置”指交付给应用的内容；安装器自身的控制声明仍位于 `install/items/`、`apply/items/`、`workflow/profiles/` 和 `mirrors/`。

`configs/` 也不是目标 `~/.config/` 的目录镜像：部署组件、目标位置和硬链接/复制方式由 `apply/items/` 明确声明，新增一个子目录不会自动部署。详见 [配置源目录说明](configs/README.md)。

## 开始使用

先按 [运行时准备](install/README.md#python-运行时) 配置 Python ≥3.15，然后在仓库根目录运行。Unix 仓库配置使用文件级硬链接，桌面字体设置渲染后复制；仓库和目标配置目录必须位于同一文件系统。实际安装需要相应包管理器、网络和权限；`--yes` 只跳过 Linux 安装器自身确认，不代替 sudo 授权或外部安装程序的人工步骤。

```bash
# Linux：先预览，再执行
./install/linux.sh --plan
./install/linux.sh --dry-run --yes
./install/linux.sh --yes

# macOS
./install/macos.sh --dry-run
./install/macos.sh
```

Windows 默认仅复制 Terminal 配置，可从普通 Windows checkout 运行。显式选择 `windows-full` 时，checkout 要位于其声明的 `FedoraLinux-44` WSL2 内；自定义 profile 可选择其他已有 WSL2 分发和 guest profile。安装器不会创建分发。

```powershell
$repo = '\\wsl.localhost\FedoraLinux-44\home\<user>\dotfiles'
& "$repo\install\windows.ps1" -Profile windows-full -DryRun
& "$repo\install\windows.ps1" -Profile windows-full
```

默认 `linux`、`macos`、`windows`、`wsl` 不安装软件、不改 shell、不处理镜像或启动 WSL；默认也不选择桌面字体。显式使用 `--profile linux-full`、`--profile macos-full` 或 Windows `-Profile windows-full` 执行完整环境。完整方案启用安装下载镜像及 Unix 持久镜像初始化，CLI 可覆盖 profile。使用 `--no-china-mirrors` 或 Windows `-NoChinaMirrors` 跳过镜像设置；这不会撤销已有设置。详见 [安装](install/README.md) 和 [镜像](mirrors/README.md)。

原生 Debian/Ubuntu 和 Fedora/CentOS/RHEL 的 Docker 使用官方 CE 仓库；Arch 使用发行版包，WSL 使用 Windows Docker Desktop。已有冲突包由操作者处理后重跑，详见 [Docker 所有权与软件来源](install/README.md#docker-所有权)。

`linux-full` 安装 Noto CJK 和 JetBrainsMono Nerd Font（不再下载苹方）；原生 KDE 的 `desktop-fonts` 组件配置桌面正文和等宽回退。IDE 自行配置，应用重启或重新登录后生效。来源和适用范围见 [字体安装](install/README.md#linux-桌面字体) 与 [桌面字体部署](apply/README.md#桌面字体)。

## 更新配置与处理失败

```bash
./apply/apply.sh --dry-run
./apply/apply.sh fish helix --no-mirrors

bash workflow/status.sh /path/to/workflow-session
./install/linux.sh --resume /path/to/workflow-session --plan
./install/linux.sh --resume /path/to/workflow-session --yes
```

```powershell
./apply/windows.ps1 -DryRun
./workflow/status.ps1 -Session 'C:\path\to\workflow-session'
./install/windows.ps1 -Resume 'C:\path\to\workflow-session' -DryRun
```

apply 默认只部署平台 profile 的组件，也可用 `--profile NAME` / `-Profile NAME` 选择；显式组件与显式 profile 互斥。Unix 镜像更新需显式传入 `--china-mirrors`。续跑读取原 profile 名称及当前声明，保留原阶段选择和生效镜像策略，并重新检查当前状态；v1 会话不支持续跑，已有备份和恢复 journal 保留。dry-run 会话不能作为续跑来源，应保留原选项重新 dry-run。见 [workflow](workflow/README.md)。

## 项目边界

- 管理安装、配置部署、预检、失败说明和人工启动的续跑。
- 保留现有备份、受保护恢复、原子报告和部署锁；不继续扩大回滚、强制打断或持久性保证。
- 不承诺环境可复现、固定版本、计划重放或自动故障恢复。
- 不检查 Docker daemon、容器或其他服务的健康，不以服务运行状态判定安装成功。
- Clash/Mihomo 配置及订阅分发服务已拆分到独立的 `clash-config` 仓库，从其独立 checkout 部署和更新。

完整约束见 [架构与能力边界](docs/architecture.md) 和 [AGENTS.md](AGENTS.md)。

## 文档导航

| 文档 | 面向读者与内容 |
| --- | --- |
| [架构与能力边界](docs/architecture.md) | 项目结构、层间职责、当前保证和非目标 |
| [安装](install/README.md) | 平台前提、命令参数、安装副作用、离线计划 |
| [配置部署](apply/README.md) | 硬链接/复制、冲突、备份、显式恢复 |
| [workflow](workflow/README.md) | 阶段、会话报告、失败分类与续跑 |
| [镜像](mirrors/README.md) | 安装下载、初始化、当前设置更新及所有权判断 |
| [配置语义](docs/configuration.md) | install/apply/profile/mirror 字段和组合约束 |
| [LLM 配置生成指南](docs/llm-config-authoring.md) | 新增配置时的输入要求、编辑步骤、示例与验收输出 |
| [应用配置](docs/applications.md) | Fish、Helix、终端、Zellij 和 Git 的实际行为 |
| [数据契约](contracts/README.md) | 计划、报告和进程执行接口 |
| [验证](tests/README.md) | 本地检查、运行时要求和已禁用的 CI 配置 |

共享核心的 Python 运行时准备见 [安装手册](install/README.md#python-运行时)。

## 本地验证

仓库 CI 已禁用，原工作流保留为 `.github/workflows/install.yml.disabled`。验证请手动运行本地检查；恢复方式见 [验证文档](tests/README.md#ci-与本机验证边界)。

```bash
./tests/check.sh --suite all --strict
```

```powershell
./tests/check.ps1 -Suite all -Strict
```

缺少当前主机适用的运行时会使 strict 检查失败；不适用的主机会明确跳过。测试不会安装真实软件或将服务可用性作为交付门槛。完整 Windows/WSL dry-run 仍需对应的本机环境。
