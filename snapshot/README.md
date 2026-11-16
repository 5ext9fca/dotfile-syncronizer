# 软件与配置快照

快照是单个 ZIP 文件，内含 `manifest.json` 和配置 payload；格式版本为 1。创建成功前不发布最终文件，已有输出不覆盖。临时归档与输出位于同目录，使用文件硬链接进行无覆盖原子发布后移除临时名称；不支持该操作的输出文件系统会明确失败，配置恢复本身只使用复制。

## 创建与检查

```bash
./snapshot/snapshot.sh create --profile macos --output /path/to/snapshot.zip --dry-run
./snapshot/snapshot.sh create --software fish helix --output /path/to/snapshot.zip
./snapshot/snapshot.sh inspect --snapshot /path/to/snapshot.zip
```

```powershell
.\snapshot\snapshot.ps1 create -Profile windows -Output C:\Snapshots\settings.zip -DryRun
.\snapshot\snapshot.ps1 create -Software windows-terminal -Output C:\Snapshots\settings.zip
.\snapshot\snapshot.ps1 inspect -Snapshot C:\Snapshots\settings.zip
```

inspect 验证整个归档并输出 manifest，包括声明副本、配置路径及文件摘要，不输出配置文件正文。

必须且只能选择 profile 或软件 ID；依赖自动补齐。保存所选声明，不根据软件是否已经安装过滤。安装依赖各可选安装方式的声明也一同保存。依赖项声明的配置同样必须存在。

递归采集未排除的普通文件和空目录，不跟随符号链接或 Windows reparse point，不保存 UID/GID、ACL、扩展属性。文件保留可执行位，恢复文件权限为用户读写加已保存的可执行位。归档保留相对目录根，不保存源主机 HOME 路径；配置内容中的身份、绝对路径或凭据不会自动改写。

目录排除规则是相对路径及其后代，不是 glob；被排除的链接也不会访问。缺失、不可读、特殊文件、链接、大小写冲突、重叠配置路径及可检测到的采集期间变化会使整个采集失败。关闭会写入配置的应用后重试。dry-run 检查声明、路径和读取内容，但不生成归档。

## 恢复

```bash
./snapshot/snapshot.sh restore --snapshot /path/to/snapshot.zip --dry-run
./snapshot/snapshot.sh restore --snapshot /path/to/snapshot.zip
./snapshot/snapshot.sh restore --snapshot /path/to/snapshot.zip --configuration-only
```

PowerShell 使用 `restore -Snapshot FILE [-DryRun] [-ConfigurationOnly]`。完整恢复先安装再配置，`--plan` / `-PlanOnly` 等价非变更预览。无软件安装规则的配置专用项只恢复配置。

恢复前验证 manifest、所有文件 SHA-256、归档成员集合、声明版本和平台。拒绝路径穿越、绝对路径、重复/冲突成员、链接及其他平台声明；不直接调用通用解包覆盖用户目录。SHA-256 检测内容损坏，不提供归档来源认证；只恢复你信任的快照，安装声明可引用下载源。

平台要求操作系统安装分支、CPU 架构、native/WSL 一致；Linux 包管理器优先级与安装器相同：Pacman、APT、DNF。Windows 与 WSL 独立，不要求旧 checkout 位置。

使用当前实现支持的安装处理器和执行策略处理快照中的声明，不固定包版本；当前项目软件清单变化不影响快照清单。恢复前检查目标路径及输出冲突，安装后按当前文件状态重新规划配置。相同内容跳过，冲突先备份，未知额外文件保留。

## 失败与产物

真实恢复在 `${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}` 创建独立 workflow 会话，记录安装、配置结果及 journal。Windows 使用对应用户目录。原生安装命令输出流向终端；快照阶段日志记录阶段及错误，未承诺保存完整终端录制。

使用 `workflow/status.sh` 或 `workflow/status.ps1` 查看结果。解决失败原因后重新运行同一归档的 restore；快照会话不接受安装入口 `--resume`。每次重新检查当前软件及配置，不能仅因历史成功记录而跳过。

恢复不卸载包、不清理目标额外文件，不跨阶段回滚。配置当前操作失败时沿用现有事务恢复，旧文件备份及受保护 journal 恢复继续可用。无输出请求的 dry-run 不创建持久会话或变更目标配置。
