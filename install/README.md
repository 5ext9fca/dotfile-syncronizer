# 软件安装

安装入口仅按统一软件声明安装软件；配置迁移使用 [快照](../snapshot/README.md)。声明位于 `software/items/*.toml`，profile 使用 v3 软件 ID 集合。

## 平台与前提

支持 macOS、Windows 和 Linux APT/DNF/Pacman，Linux 按存在的包管理器选分支。WSL 中独立运行 Linux 入口；Windows 不再调度或创建 WSL。需要 Python、网络、对应包管理器及安装权限；Linux --yes 只跳过本工具确认，不代替 sudo 或外部安装程序的人工步骤。

## 命令

```bash
./install/macos.sh --dry-run
./install/macos.sh --profile macos-full
./install/linux.sh --profile linux-full --dry-run --yes
./install/linux.sh --profile linux-full --yes
./install/plan.sh --platform linux.apt --explain
```

```powershell
.\install\windows.ps1 -DryRun
.\install\windows.ps1 -Profile windows-full
.\install\plan.ps1 -Platform windows
```

默认 profile 是较小的已声明软件集合，*-full 选择平台适用的完整集合。安装依赖自动补齐；不应用配置、修改登录 shell、初始化持久镜像或启动 WSL。仅有 packages 阶段；--plan、--dry-run、--results、--resume 及 Windows 等价参数继续可用。

## 下载源与副作用

默认使用声明的上游来源；--china-mirrors / -ChinaMirrors 显式切换安装下载源，--no-china-mirrors / -NoChinaMirrors 显式使用上游。持久镜像设置仅通过独立 apply/mirrors.sh 操作。

当前存在的软件跳过；安装成功由执行策略接受退出码判定，不做安装后验证。包管理器刷新、依赖安装及包声明的仓库操作保留；系统源文件修改前保留既有备份。原生 Pacman 更新会升级系统，Homebrew/Xcode 初始化仍可能需要用户完成外部步骤。失败后人工处理再重跑。

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

此表解释 [docker.toml](../software/items/docker.toml) 的当前选择。Docker Desktop 的首次启动、授权和 WSL 集成开关由用户处理；安装器不执行 `docker info`、启动容器或检查服务健康。

macOS Docker 声明 cask/manual 两种发现方式，优先使用 cask 安装。仅检查声明的目录：已有 `/Applications/Docker.app` 时跳过，不启动 Docker 或查询版本；只有独立 Docker CLI 不会满足这些目录条件。应用完整性与版本不在存在性检查保证内。多方式声明和路径规则见 [配置语义](../docs/configuration.md#软件声明-v1)。


## 软件来源核对

安装项名称表示目标用途，不保证所有平台由同一发布者打包。2026-11-13 检查现有声明后，需要区分以下来源：

- WezTerm：APT 使用上游 Fury 仓库；DNF 使用上游文档列出的 `wezfurlong/wezterm-nightly` COPR，属于 nightly 通道；Pacman/Homebrew 使用各自软件仓库。见 [上游安装说明](https://github.com/wezterm/wezterm/blob/main/docs/install/linux.md)。本次保留既有通道。
- OpenCode：当前 `https://opencode.ai/install` 指向 OpenCode 1 安装脚本；最新文档另列 v2 安装地址和 `anomalyco/tap/opencode-v2`。这是主版本通道差异，不能仅视为镜像替换；本次未升级应用主版本。见 [v1 脚本](https://opencode.ai/install) 和 [当前安装说明](https://opencode.ai/docs/)。
- `pkg-config`：Fedora 的 `pkgconf-pkg-config` 实际由 pkgconf 提供兼容命令，属于替代实现，保留发行版默认选择。见 [Fedora 包说明](https://packages.fedoraproject.org/pkgs/pkgconf/pkgconf-pkg-config/)。
- Helix：Debian 的 `hx`、Fedora/Arch 的 `helix` 和 Snap `helix` 均是上游文档列出的包名，不因名称不同改源。见 [Helix 包管理器说明](https://docs.helix-editor.com/master/package-managers.html)。
- ty 的 PyPI/pipx 安装是 [Astral 支持的方法](https://docs.astral.sh/ty/installation/)；mise 的 Cargo 安装见 [上游说明](https://mise.jdx.dev/installing-mise.html)。其余默认发行版、Homebrew、WinGet 包与 Cargo/PyPI 项仍按声明使用各自渠道；版本、补丁和同步时间可能不同。

此检查核对声明和上述特殊来源，不表示已在每个平台下载、安装或验证全部远程包可用性。镜像来源仍由安装项 `mirror_url` 和镜像开关决定，不等同于软件项目或发布通道变化。


## 字体

字体仍由安装规则提供，二进制不入库。desktop-fonts 是可选配置专用项，采集真实的 Fontconfig/KDE/GTK 文件，不渲染设置或检查字体服务健康。

## Python 运行时

共享核心使用 Python ≥3.14 和预先安装的 dotfile-viewer；验证仅使用 3.14，不主动拒绝更高版本。请预先在当前 checkout 的 `.venv` 中准备解释器（Unix：`.venv/bin/python`；Windows：`.venv/Scripts/python.exe`），或将 `DOTFILES_PYTHON` 设为单个解释器路径。不会自动搜索其他环境或安装依赖。初始化后固定解释器路径并保留虚拟环境路径。Windows 与 WSL 分别准备各自的运行时。启动运行时独立于受管理的 Python 安装项。

迁移参考为原项目 `696256f`，行为基线为本仓库 `bca3835`；原项目的私有配置不属于迁移内容。临时 UTF-8 JSON 协议仅用于当前调用，不是持久计划或重放接口。

所有 plan、dry-run、resume 和 restore 同样要求运行时；帮助信息不要求。运行期间不得替换正在使用的虚拟环境。核心依赖预先安装的 dotfile-viewer，不自动安装依赖。可通过预先安装的 Python 3.14 创建环境，例如 `python3.14 -m venv .venv`；Windows 使用已安装的 3.14 解释器运行同一 `-m venv .venv` 命令。

## Viewer 依赖

运行前安装 dotfile-viewer>=0.2,<0.3。默认声明与 schema 来自该包；--catalog DIR / -Catalog DIR 或 DOTFILES_CATALOG 选择外部完整目录。声明唯一来源不在本 checkout。
