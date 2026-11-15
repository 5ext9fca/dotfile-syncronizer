# 阶段、报告与续跑

workflow 将安装项与配置组件关联起来，先完成所选阶段的预检，再按阶段执行。字段定义见 [配置语义](../docs/configuration.md)，实现入口是 `lib/workflow.sh` / `.ps1`。

## 阶段选择

| 平台 | 默认阶段顺序 |
| --- | --- |
| Unix | packages → configuration → mirrors → shell |
| Windows | packages → git → configuration → wsl |

阶段由 [stages.tsv](schema/stages.tsv) 定义，profile 和镜像开关决定 gate。shell=none、mirrors=none、wsl=none 会关闭对应阶段。Windows 的 Linux 配置在 guest 的独立 workflow 中完成。

```bash
./install/linux.sh --only-stage packages --yes
./install/linux.sh --only-stage configuration --dry-run --yes
./install/linux.sh --from-stage configuration --yes
```

```powershell
./install/windows.ps1 -OnlyStage configuration -DryRun
./install/windows.ps1 -FromStage configuration -DryRun
```

`only` 与 `from` 互斥。只有所选阶段检查其目标和运行前提，但安装/profile 声明及组件关联仍会校验。仅配置不安装包，也不修改登录 shell；单独 shell 阶段要求 Fish 已存在；Windows 主机阶段不要求 WSL。

plan/dry-run 都会预检；plan 输出包含选择原因、依赖、实际来源、排除原因和配置文件影响。执行时会重新读取必要状态，所以预览不是旧计划重放承诺。

## 会话与报告

真实变更流程在 `${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}/workflow-<id>/` 保存会话，Windows 默认也使用 `$HOME/.dotfiles-backups`。ID 可通过入口参数指定，已存在的目录不能复用。Windows 把 ID 传给 WSL，主机与 guest 各自保存报告。

| 产物 | 用途 |
| --- | --- |
| `request.tsv` | 版本化 platform、profile、镜像开关、有效阶段选择、父会话路径、dry-run 标志 |
| `workflow.tsv` / `workflow.json` | Unix / Windows 阶段摘要，包含状态、退出码、耗时和产物路径 |
| `<stage>.log` | 阶段输出 |
| `<stage>.result` | 结构化状态和独立的 journal/child-report 路径，优先于可能落后的摘要 |
| `<stage>.tsv` | 该阶段如有的安装/apply/Git 明细，不保证每种阶段都有 |
| `packages-backups/`、配置/镜像子目录 | 机制备份与部署恢复记录 |

`--results FILE` / `-ResultsPath FILE` 发布额外顶层摘要；目标不能已经存在，父目录须存在且可写，并且不能与仓库、部署目标或会话重叠。

普通 dry-run 使用临时诊断，不保留会话；指定 results 后会保存。plan 不保存报告。预检失败发生在会话创建之前，因此可能只有终端错误，没有会话目录。不要通过解析日志中的自然语言来寻找恢复文件；使用结构化报告。

## 查看与处理失败

```bash
bash workflow/status.sh /path/to/workflow-session
```

```powershell
./workflow/status.ps1 -Session 'C:\path\to\workflow-session'
```

状态查询合并摘要、阶段结果和项目明细，显示失败项、退出码、原因和日志位置。artifact 路径中逗号和空格保留；旧摘要中的逗号串只作历史引用显示。

| 状态/退出码 | 操作 |
| --- | --- |
| success / 0 | 阶段完成；dry-run 成功对应 planned |
| failed / 一般非零 | 查看失败项与日志，处理原因后重试 |
| deferred / 75 | 完成人工前置步骤，例如 Xcode GUI 安装 |
| failed / 124 | 命令超时，不能据此认定软件未安装 |
| interrupted / 130、143 | 检查被中断步骤的当前状态后重试 |
| running | 记录尚未完成，不是成功证据；先确认旧运行已停止 |
| blocked | 前序失败导致未执行 |
| skipped | 阶段选择或 profile gate 排除 |

普通安装失败不意味着必须恢复配置。只有确实需要撤销部署时，才检查 [apply 恢复](../apply/README.md) 的 journal。

## 会话续跑

```bash
./install/linux.sh --resume /path/to/workflow-session --plan
./install/linux.sh --resume /path/to/workflow-session --dry-run --yes
./install/linux.sh --resume /path/to/workflow-session --yes
```

```powershell
./install/windows.ps1 -Resume 'C:\path\to\workflow-session' -PlanOnly
./install/windows.ps1 -Resume 'C:\path\to\workflow-session'
```

续跑从旧选择中第一个未完成阶段开始，只保留原选择剩余阶段和镜像模式；当前 profile 的 gate 仍生效。新会话记录父会话路径，重新读取当前声明、安装状态和配置目标。未在旧摘要中出现的所选阶段视为未开始。

限制：

- 不允许同时传 only/from 或镜像开关；results 和 session ID 是新运行的参数。
- 拒绝已完成会话、dry-run 来源、平台/profile 不符或无效记录。
- 旧会话缺少 request 时，用 `--from-stage` / `-FromStage` 或 only-stage 手动重试。
- dry-run 失败的状态提示会要求保留原阶段和镜像选项重新 dry-run，不给出无效的 resume 命令。
- Windows 恢复到 wsl 阶段时重新运行 guest workflow，不自动跟随 guest 的旧检查点。
- 续跑不自动恢复配置，不自动清理遗留锁，也不自动重试。

## 安装项级续跑

packages 阶段按当前依赖顺序逐项重新检查。声明应用发现路径的项，只按当前文件/目录检查所有配置方式，不运行包清单或版本探测；全部缺失时按优先方式安装。未声明发现路径的项保留以下机制专用探测。APT、RPM/DNF、Pacman、Homebrew、Cargo、WinGet 的清单检查，以及现有 check、pipx、MSVC 探测，可跳过已满足项；已存在 pipx 环境在续跑中不升级。未知状态或不足以证明完成的脚本/工具链操作仍按原逻辑执行。

旧报告成功不构成跳过理由；包被用户卸载后会重新安装。失败或探测超时阻断后续项目。项目明细在每项开始和结束时更新，便于查看未完成 packages 阶段的进度。这不是任意命令内部的指令级恢复。

## 部署锁

真实 workflow、apply、mirror、restore 共享部署租约。Unix 默认使用 `${TMPDIR:-/tmp}/dotfiles-deployment-$UID.lock`；Windows 默认使用用户临时目录中的 `dotfiles-deployment.lock`。可用 `DOTFILES_DEPLOYMENT_LOCK` 指定共同路径，嵌套流程通过 `DOTFILES_DEPLOYMENT_TOKEN` 继承所有权。不要在独立运行中手工设置继承 token。

Unix 使用 `uname -n` 获取锁记录中的主机名，不依赖额外的 `hostname` 软件包；读取所有权信息失败时不会创建锁目录。

若提示锁已存在，先检查 owner 并确认相关主机/guest 和全部写入进程停止，再由用户处理遗留锁。不能因为父 PID 不存在就自动删除。不要为了绕过活动锁换一个路径启动第二个写入流程。边界见 [架构说明](../docs/architecture.md)。

安装项明细中的 `skipped` 配合 `already-installed` / `discovered-installation`（续跑为 `resume-already-installed`）表示安装前发现已有项；环境或 provider 排除会使用各自的原因。`success` 表示安装命令的退出码被执行策略接受，不表示安装后存在性确认；`failed` / `blocked` 分别表示失败和因前序失败未执行。安装成功后不再调用发现检查，也不检查服务运行。

普通重跑使用当前平台、环境、profile 和声明重新规划；`--resume` 保留旧会话的阶段选择语义，不重新执行已完成阶段。缺失的安装项会按当前发现结果安装；新增声明在普通重跑时进入当前 profile 的选择范围。
