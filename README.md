# Dotfile Syncronizer

以 Fish 为入口的跨平台安装器与配置仓库。可多次手动运行，按当前声明检查并跳过已有软件，安装缺失项、部署配置并记录结果；允许失败后人工处理，再重新运行或断点续跑。安装成功表示命令按执行策略正常退出，不进行安装后存在性复核。

支持 Linux 的 APT、DNF（包括原生 Fedora）、Pacman 分支、macOS，以及 Windows 主机与 `FedoraLinux-44` WSL2 的组合。Linux 分支按可用包管理器选择，不按发行版名称选择。

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

在仓库根目录运行。Unix 仓库配置使用文件级硬链接，桌面字体设置渲染后复制；仓库和目标配置目录必须位于同一文件系统。实际安装需要相应包管理器、网络和权限；`--yes` 只跳过 Linux 安装器自身确认，不代替 sudo 授权或外部安装程序的人工步骤。

```bash
# Linux：先预览，再执行
./install/linux.sh --plan
./install/linux.sh --dry-run --yes
./install/linux.sh --yes

# macOS
./install/macos.sh --dry-run
./install/macos.sh
```

Windows 完整流程要求 checkout 位于 `FedoraLinux-44` 内；WSL 分发必须已初始化为 WSL2。安装器不会替你创建分发。

```powershell
$repo = '\\wsl.localhost\FedoraLinux-44\home\<user>\dotfiles'
& "$repo\install\windows.ps1" -DryRun
& "$repo\install\windows.ps1"
```

Unix 默认启用安装下载镜像，并在后续阶段初始化持久镜像设置。使用 `--no-china-mirrors` 或 Windows `-NoChinaMirrors` 跳过镜像设置；这不会撤销已有设置。详见 [安装](install/README.md) 和 [镜像](mirrors/README.md)。

原生 Debian/Ubuntu 和 Fedora/CentOS/RHEL 的 Docker 使用官方 CE 仓库；Arch 使用发行版包，WSL 使用 Windows Docker Desktop。已有冲突包由操作者处理后重跑，详见 [Docker 所有权与软件来源](install/README.md#docker-所有权)。

原生 Linux 默认安装 Noto CJK 和 JetBrainsMono Nerd Font（不再下载苹方）；原生 KDE 的 `desktop-fonts` 组件配置桌面正文和等宽回退。IDE 自行配置，应用重启或重新登录后生效。来源和适用范围见 [字体安装](install/README.md#linux-桌面字体) 与 [桌面字体部署](apply/README.md#桌面字体)。

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

`apply/apply.sh` 默认还应用当前镜像声明；只改应用配置时使用 `--no-mirrors`。续跑创建新会话、保留原阶段选择和镜像开关，并重新检查当前状态。dry-run 会话不能作为续跑来源，应保留原选项重新 dry-run。见 [workflow](workflow/README.md)。

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

## 本地验证

仓库 CI 已禁用，原工作流保留为 `.github/workflows/install.yml.disabled`。验证请手动运行本地检查；恢复方式见 [验证文档](tests/README.md#ci-与本机验证边界)。

```bash
./tests/check.sh --suite all --strict
```

```powershell
./tests/check.ps1 -Suite all -Strict
```

缺少当前主机适用的运行时会使 strict 检查失败；不适用的主机会明确跳过。测试不会安装真实软件或将服务可用性作为交付门槛。完整 Windows/WSL dry-run 仍需对应的本机环境。
