# Dotfile Syncronizer

跨平台软件与配置快照采集、安装和恢复工具。项目只维护软件及配置路径声明，不维护应用配置文件。手动创建快照，把当前本机配置与所选软件声明保存为 ZIP；在同平台的新环境安装软件并复制恢复配置。

软件声明、配置路径、排除项和 profile 由用户按自己的环境维护；仓库随附的声明与集合只是可修改的缺省值，不承诺覆盖用户的全部软件或配置。项目负责校验声明、按声明采集和执行、保护已有文件并清晰报告失败；用户负责声明的选择、来源、实际路径及敏感内容的排除。缺省值未覆盖某个配置不代表采集机制缺失，已声明路径不存在仍会明确失败。

## 开始使用

先准备 [Python ≥3.15](install/README.md#python-运行时)。采集前停止会写入配置的应用；所选软件及依赖的任一声明路径缺失都会使采集失败。

```bash
# 显式选择软件，也可使用 --profile macos 等已维护的集合
./snapshot/snapshot.sh create --software fish helix --output /path/to/settings.zip --dry-run
./snapshot/snapshot.sh create --software fish helix --output /path/to/settings.zip
./snapshot/snapshot.sh inspect --snapshot /path/to/settings.zip

# 在目标机器检查，再安装软件和恢复配置
./snapshot/snapshot.sh restore --snapshot /path/to/settings.zip --dry-run
./snapshot/snapshot.sh restore --snapshot /path/to/settings.zip

# 只应用配置；不会安装软件
./apply/apply.sh --snapshot /path/to/settings.zip --dry-run
```

```powershell
.\snapshot\snapshot.ps1 create -Software windows-terminal -Output C:\Snapshots\settings.zip
.\snapshot\snapshot.ps1 inspect -Snapshot C:\Snapshots\settings.zip
.\snapshot\snapshot.ps1 restore -Snapshot C:\Snapshots\settings.zip -DryRun
.\snapshot\snapshot.ps1 restore -Snapshot C:\Snapshots\settings.zip
```

快照不覆盖已有文件。输出目录需已存在，且不能位于采集路径内。归档可能含用户敏感配置，不提供自动脱敏、加密或上传；使用声明排除项并自行安全保管和传输。

## 迁移边界

- 仅支持相同安装分支、CPU 架构及 native/WSL 环境。Linux 按 APT、DNF、Pacman 区分；不强制相同发行版或 OS 版本，不转换配置格式或配置内的绝对路径。
- 快照保存选择及依赖的安装声明副本，恢复不读取项目后来修改的软件声明。它不锁定实际软件版本、不携带安装包，也不保证离线或完整环境复现。
- 配置目录递归采集普通文件及空目录，允许精确路径/子树排除；也支持单文件。遇到未排除的链接、特殊文件、缺失路径或可检测的采集期间变化时失败；不保证运行中应用的多文件瞬时一致性。
- 恢复统一复制：相同内容跳过，冲突先备份，保留目标额外文件。应用修改不会改变快照；不再要求仓库与用户配置同文件系统。
- Windows 与 WSL 分别操作；不会创建或调度 WSL。运行前需要 Python、包管理器、网络及相应权限。
- 安装前检查软件是否已存在；安装命令按退出码判断成功，不额外检查安装结果或服务状态。失败后查看报告，处理原因并手动重跑；软件安装与配置恢复不提供整体回滚。

## 声明与入口

`software/items/<id>.toml` 统一描述安装规则和本机配置路径；`workflow/profiles/*.conf` 选择软件 ID。默认 profile 是较小的软件集合，`*-full` 选择当前平台所有适用声明；完整集合可能因未配置的软件而无法采集。

安装入口仅安装软件，不会隐式应用配置、切换登录 shell、初始化持久镜像或启动 WSL：

```bash
./install/macos.sh --dry-run
./install/linux.sh --profile linux-full --dry-run --yes
./apply/mirrors.sh --dry-run
```

旧仓库 `configs/`、`install/items/`、`apply/items/` 已移除；从本机真实配置创建新快照。旧硬链接的目标文件不由迁移脚本修改，应用配置不会自动采集。旧 v2 workflow 会话可查看但不可续跑；旧部署 journal 仍可受保护恢复。

## 详细使用指南

- [快照操作](snapshot/README.md)、[安装](install/README.md)、[配置恢复](apply/README.md)
- [声明语义](docs/configuration.md)、[声明编写指南](docs/llm-config-authoring.md)
- [配置路径与应用说明](docs/applications.md)、[会话与失败处理](workflow/README.md)、[镜像](mirrors/README.md)
