# 安装

安装入口负责依赖、配置和后续初始化的完整 workflow。软件清单来自 [items](items/)，不是写死在平台脚本中。字段语义见 [配置参考](../docs/configuration.md)，新增声明见 [LLM 指南](../docs/llm-config-authoring.md)。

## 平台与前提

| 入口 | 检测与前提 | 默认行为 |
| --- | --- | --- |
| `linux.sh` | Linux；依次查找 Pacman、APT、DNF；需要 `/etc/os-release` | 软件 → 配置 → 镜像初始化 → Fish 登录 shell |
| `macos.sh` | macOS；按可执行文件和标准路径定位 Homebrew | 有序处理 Xcode/Homebrew，再安装、配置和初始化 |
| `windows.ps1` | Windows PowerShell 5.1 或 PowerShell 7；WinGet | Windows 软件 → Git 全局设置 → Terminal 配置 → WSL |

Unix 硬链接要求仓库与配置目标在同一文件系统。修改系统配置和登录 shell 可能需要 sudo。包管理器、下载站点、登录权限和 GUI 步骤由运行环境提供。

原生 Fedora 使用同一个 `./install/linux.sh` 入口，自动选择 `linux.dnf` 声明和 Linux profile，无须 WSL 或单独的 Fedora 脚本。先运行 `./install/linux.sh --dry-run --yes`，确认后运行 `./install/linux.sh --yes`。完整流程要求当前用户可使用 sudo，且系统提供 `chsh`；精简安装需先补齐这些前提。原生 Fedora 包含 WezTerm 和本地 Docker engine，WSL 则按现有环境声明跳过它们。默认镜像阶段处理 Fedora 的 `fedora.repo` 和 `fedora-updates.repo`。

需要输入 sudo 密码时，请从交互式终端启动安装器。阶段日志记录会保留终端输入；`--yes` 仅跳过安装器确认，不会提供或跳过 sudo 认证。

Windows 的完整流程或任何包含 `wsl` 的选择，要求仓库位于已初始化的 `FedoraLinux-44` WSL2 内。预检验证 UNC 路径、分发版本和 Fedora guest，随后调用 guest 的 Linux 安装器。Windows 驱动器 checkout 或其他分发的 checkout 不满足完整流程要求。仅选择主机阶段不会要求 WSL。

macOS Xcode Command Line Tools 需要 GUI 完成时返回 `75/deferred`；完成后手动重试。安装成功表示命令退出码被执行策略接受（包括声明允许的重启码），不进行安装后存在性复核，也不代表应用完成登录、系统已重启或 Docker daemon 已运行。

## 命令

```bash
./install/linux.sh --plan
./install/linux.sh --dry-run --yes
./install/linux.sh --dry-run --yes --no-china-mirrors
./install/linux.sh --yes
./install/macos.sh --dry-run
./install/macos.sh
```

```powershell
./install/windows.ps1 -PlanOnly
./install/windows.ps1 -DryRun
./install/windows.ps1 -NoChinaMirrors
```

| Unix 参数 | Windows 参数 | 含义 |
| --- | --- | --- |
| `--plan` | `-PlanOnly` | 预检并输出阶段计划与说明，不安装、不保存会话报告 |
| `--dry-run` | `-DryRun` | 预检并走执行路径，打印变更但不实际部署 |
| `--results FILE` | `-ResultsPath FILE` | 额外发布摘要；dry-run 指定后会保存诊断会话 |
| `--only-stage NAME` | `-OnlyStage NAME` | 仅执行一个阶段 |
| `--from-stage NAME` | `-FromStage NAME` | 从阶段开始，继续后续允许的阶段 |
| `--resume SESSION` | `-Resume SESSION` | 从实际安装会话恢复选择并重新预检 |
| `--session-id ID` | `-SessionId ID` | 指定新会话 ID，不能覆盖已存在会话 |
| `--no-china-mirrors` | `-NoChinaMirrors` | 跳过镜像设置，不撤销已存在配置 |
| `--china-mirrors` | 默认启用 | 显式使用镜像 |
| `--yes`（仅 Linux） | 无 | 跳过安装器自身确认，不替代系统授权 |

`only-stage` 与 `from-stage` 互斥。`resume` 不能同时传阶段选择或镜像开关；可以结合 plan、dry-run、新结果路径和新会话 ID。命令中的 `SESSION` 是旧会话目录，不是摘要文件或恢复 journal。

## 重要副作用

- 仅有待安装的 APT 类项目时更新索引。仅有待安装的 Pacman 包时执行 `pacman -Syu`，保留其完整同步升级语义；这不是每次重跑都执行的维护任务。独立 `rust-analyzer` 只在准备安装 Rust 工具链时移除。DNF 的仓库准备与元数据刷新同样随实际安装执行。
- 软件机制可能添加 APT 仓库/密钥、启用 COPR、添加 Homebrew tap 或运行声明的下载脚本。
- Rust toolchain 机制安装声明组件并设置默认工具链；普通运行和续跑均跳过已有 pipx 环境。Rust 工具链及声明组件均已发现时也跳过，不重设默认工具链。
- Unix 部署应用文件、初始化镜像，并按 profile 设置 Fish 登录 shell；Windows 的 `git` 阶段默认没有身份设置项，个人身份由操作者在本机配置。
- 修改前的配置冲突进入备份；包安装、系统更新、Git 身份和登录 shell 不属于 apply journal 的恢复范围。

## 下载源与持久镜像

安装项的 `source_kind` 决定来源字段。可用 `mirror_url` 的项目在镜像启用时选择它，否则选择 `source_url`。安装进程还会导出镜像环境变量。原生包安装使用当时系统包源；持久系统镜像在后续镜像阶段处理。详见 [镜像生命周期](../mirrors/README.md)。

## Docker 所有权

| 环境 | 当前声明 |
| --- | --- |
| Linux APT（Debian/Ubuntu） | Docker 官方仓库的 `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` |
| Linux DNF（Fedora/CentOS/RHEL） | 同上，Docker 官方 RPM 仓库 |
| Linux Pacman | Arch 发行版维护的 `docker`（无 Docker 官方 CE 包仓库） |
| macOS | Homebrew cask `docker-desktop` |
| Windows | WinGet `Docker.DockerDesktop` |
| WSL | 跳过原生 engine，由 `windows-docker-desktop` 声明提供 |

APT/DNF 使用专用 `docker-ce` handler；按包清单检查 CE，已有 Moby 或 `docker.io` 不会被当作 CE 跳过。仓库文件和密钥覆盖前保存到本次会话备份。已有冲突包需由操作者先处理，再手动重跑；安装器不自动删除 Moby、Podman、containerd 或容器数据。非上述发行版的 APT/DNF 主机在 Docker 待安装时预检失败，不猜测兼容仓库。镜像开关不改写 Docker 官方源。参考 [Fedora](https://docs.docker.com/engine/install/fedora/)、[Debian](https://docs.docker.com/engine/install/debian/) 和 [Ubuntu](https://docs.docker.com/engine/install/ubuntu/) 官方说明。

此表解释 [docker.conf](items/docker.conf) 的当前选择。Docker Desktop 的首次启动、授权和 WSL 集成开关由用户处理；安装器不执行 `docker info`、启动容器或检查服务健康。

macOS Docker 声明 cask/manual 两种发现方式，优先使用 cask 安装。仅检查声明的目录：已有 `/Applications/Docker.app` 时跳过，不启动 Docker 或查询版本；只有独立 Docker CLI 不会满足这些目录条件。应用完整性与版本不在存在性检查保证内。多方式声明和路径规则见 [配置语义](../docs/configuration.md#多种安装方式与应用发现)。

## 离线检查声明

```bash
./install/plan.sh --platform linux.apt
./install/plan.sh --platform linux.dnf --no-china-mirrors --explain
./install/plan.sh --platform linux.pacman
./install/plan.sh --platform macos
./install/plan.sh --platform windows
./install/plan.sh --platform linux.dnf --wsl --explain
```

```powershell
./install/plan.ps1 -Platform windows -Explain
./install/plan.ps1 -Platform linux.apt -NoChinaMirrors
```

离线 plan 不探测本机安装状态，可以跨平台解析声明。默认输出版本化 `install-plan`，`--explain` / `-Explain` 输出可读说明。`--items DIR` / `-Items DIR` 可校验候选声明集合。平台安装器自身的 `--plan` 则检查当前主机及所选阶段，并显示配置变更。

## 从 WSL 调用 Windows 入口

```bash
windows_install_path="$(wslpath -w "$PWD/install/windows.ps1")"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$windows_install_path" -DryRun
```

先在 WSL shell 中解析路径；`wslpath` 不是 PowerShell cmdlet。完整流程仍必须从 `FedoraLinux-44` 内的 checkout 发起。

失败处理和续跑范围见 [workflow](../workflow/README.md)，回归入口见 [tests](../tests/README.md)。

重复运行始终读取当前声明、平台和 profile，不依据旧成功报告跳过。`depends_on` 是公共依赖；单方式的 `install_depends_on` 和多方式子项的 `depends_on` 是安装专用依赖。发现目标已有时不引入其安装工具；profile 独立选中该工具（包括 `install=all`）时仍会处理。自定义脚本若未声明发现路径，无法推断其产物，每次仍执行；请提供已核实的 `detect_files` / `detect_dirs`。

## 软件来源核对

安装项名称表示目标用途，不保证所有平台由同一发布者打包。2026-11-13 检查现有声明后，需要区分以下来源：

- WezTerm：APT 使用上游 Fury 仓库；DNF 使用上游文档列出的 `wezfurlong/wezterm-nightly` COPR，属于 nightly 通道；Pacman/Homebrew 使用各自软件仓库。见 [上游安装说明](https://github.com/wezterm/wezterm/blob/main/docs/install/linux.md)。本次保留既有通道。
- OpenCode：当前 `https://opencode.ai/install` 指向 OpenCode 1 安装脚本；最新文档另列 v2 安装地址和 `anomalyco/tap/opencode-v2`。这是主版本通道差异，不能仅视为镜像替换；本次未升级应用主版本。见 [v1 脚本](https://opencode.ai/install) 和 [当前安装说明](https://opencode.ai/docs/)。
- `pkg-config`：Fedora 的 `pkgconf-pkg-config` 实际由 pkgconf 提供兼容命令，属于替代实现，保留发行版默认选择。见 [Fedora 包说明](https://packages.fedoraproject.org/pkgs/pkgconf/pkgconf-pkg-config/)。
- Helix：Debian 的 `hx`、Fedora/Arch 的 `helix` 和 Snap `helix` 均是上游文档列出的包名，不因名称不同改源。见 [Helix 包管理器说明](https://docs.helix-editor.com/master/package-managers.html)。
- ty 的 PyPI/pipx 安装是 [Astral 支持的方法](https://docs.astral.sh/ty/installation/)；mise 的 Cargo 安装见 [上游说明](https://mise.jdx.dev/installing-mise.html)。其余默认发行版、Homebrew、WinGet 包与 Cargo/PyPI 项仍按声明使用各自渠道；版本、补丁和同步时间可能不同。

此检查核对声明和上述特殊来源，不表示已在每个平台下载、安装或验证全部远程包可用性。镜像来源仍由安装项 `mirror_url` 和镜像开关决定，不等同于软件项目或发布通道变化。

## 终端字体

`jetbrains-mono` 安装项统一提供 JetBrainsMono Nerd Font，替代原 APT 普通字体声明；已有普通 JetBrains Mono 不会被卸载。默认 profile 使用 `install=all`，因此自动包含字体和所需的解压依赖。

| 环境 | 安装来源 |
| --- | --- |
| 原生 Linux APT / DNF | [getnf](https://github.com/getnf/getnf) 的 `-i JetBrainsMono`，下载 Nerd Fonts 发布包到 `~/.local/share/fonts/JetBrainsMono`；安装依赖为 curl、tar、xz（APT 包名 xz-utils）、Fontconfig |
| 原生 Linux Pacman | [ttf-jetbrains-mono-nerd](https://archlinux.org/packages/extra/any/ttf-jetbrains-mono-nerd/) |
| macOS | Homebrew cask [font-jetbrains-mono-nerd-font](https://formulae.brew.sh/cask/font-jetbrains-mono-nerd-font)，依赖 Homebrew |
| Windows | WinGet [DEVCOM.JetBrainsMonoNerdFont](https://github.com/DevelopersCommunity/wix-JetBrainsMonoNF) |
| WSL | 跳过 guest 字体安装，使用 Windows 主机终端的字体 |

APT/DNF 在下载前检查上述字体目录，已存在则跳过；其他平台使用包管理器的安装状态。getnf 下载使用上游 GitHub，不随镜像开关改写。WezTerm、Windows Terminal 和 Zellij 网页终端均指定该字体；远程浏览器仍需在客户端安装字体。

## Linux 桌面字体

原生 Linux 默认安装 `noto-cjk`、`fontconfig` 和桌面渲染所需的 `python`，均为 native-only；不再包含苹方下载项。已安装的苹方文件不会被删除。macOS、Windows、WSL 的字体安装选择不变。APT/DNF 的 JetBrainsMono 发现也接受 `~/.local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf`，避免对已散放的 Nerd Font 重复安装。

字体安装仍由 `install/items/` 声明；桌面 family 与回退由 `configs/fontconfig/60-dotfiles-fonts.conf` 声明，见 [桌面字体](../apply/README.md#桌面字体)。更换 family 时应同时选择提供该字体的安装项；XML 不会自动推导包名或下载地址。

自定义 `font-download` 项必须提供 `source_url`（HTTPS 基础目录）、`font_files` 和 `font_family`。下载文件全部暂存、经 `fc-scan` 解析且每个文件均包含声明的 family 后才发布，随后执行 `fc-cache`；不执行远端脚本。下载、解析或 family 不匹配会明确终止；安装成功仍仅取决于命令退出码，不作安装后存在性复核。

目标固定为 `~/.local/share/fonts/<安装项 ID>/`。作者应为整组文件声明 `detect_files`，缺少任一文件就重新下载整组；同时声明 Fontconfig/curl 依赖。字体二进制不入库，不固定版本，不自动升级。新增下载来源前需核实授权与来源，仓库不再提供第三方苹方下载声明。

Noto CJK 使用 [APT fonts-noto-cjk](https://packages.ubuntu.com/noble/fonts-noto-cjk)、[DNF google-noto-sans-cjk-fonts](https://packages.fedoraproject.org/pkgs/google-noto-sans-cjk-fonts/google-noto-sans-cjk-fonts/) 或 [Pacman noto-fonts-cjk](https://archlinux.org/packages/extra/any/noto-fonts-cjk/)，保留 `Noto Sans CJK SC` family。字体来源不随镜像开关改变；发行版软件包仍使用当前包管理器仓库。

```bash
./install/linux.sh --plan
./install/linux.sh --dry-run --yes
./install/linux.sh --yes
```

完整 workflow 先安装字体再部署桌面设置。原生 KDE 的配置预检需要 Python 3、`kreadconfig6` 或 `kreadconfig5`；GTK 未声明字体时还需相应 GTK 库和可访问的桌面显示，以读取有效默认字号。预览会报告缺失字体，但仍展示候选变更；实际配置部署会要求三种字体均可用。只选 configuration 阶段或独立 apply 不下载字体，见 [桌面字体部署](../apply/README.md#桌面字体)。
