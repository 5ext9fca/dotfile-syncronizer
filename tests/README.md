# 验证与交付检查

没有独立 build 步骤。两种 runner 共用 [manifest.tsv](checks/manifest.tsv)，每项作为子进程运行；一个检查失败后继续其余检查，最后只要有失败就返回非零。

## 运行

```bash
./tests/check.sh --strict
./tests/check.sh --suite all --strict
./tests/check.sh --suite all --list
```

```powershell
./tests/check.ps1 -Strict
./tests/check.ps1 -Suite all -Strict
./tests/check.ps1 -Suite all -List
```

| suite | 内容 |
| --- | --- |
| core（默认） | 当前主机的安装、apply、workflow、schema、进程、报告、续跑等契约 |
| cross | 两端安装计划一致性及可移植 PowerShell 契约/续跑/策略/计划说明测试 |
| dry-run | 当前 Linux/macOS 的默认配置方案，以及完整方案的镜像/上游安装预览 |
| lint | Unix ShellCheck，逐文件检查入口、库、handler 和测试 |
| all | 当前主机适用的全部 suite |

不适用当前主机的检查明确 SKIP。缺少适用运行时默认跳过，strict 将其视为失败。runner 不会自动安装依赖。固定“通过项数”不是长期标准，应以当前 manifest 的全部适用检查为准。

## 运行时

- Unix core：Bash；Python 3.15（共享核心、进程与终端契约测试）。
- Windows core：PowerShell 5.1 或 7，同样需要 Python 3.15。
- cross：按 manifest 需要 Bash 和 PowerShell；Linux 上 PowerShell 测试不能代替 Windows 原生验证。
- lint：ShellCheck；每个脚本独立检查，不递归展开 sourced 测试覆盖函数，以免旧版本分析器耗尽内存。

可用 `DOTFILES_TEST_BASH`、`DOTFILES_TEST_POWERSHELL`、`DOTFILES_TEST_PYTHON`、`DOTFILES_TEST_SHELLCHECK` 指定可执行文件。值是单个路径或命令名，不是 shell 命令串。Unix runner 默认使用自己的 Bash；PowerShell runner 默认当前 host。

```bash
DOTFILES_TEST_BASH=/path/to/bash-3.2 ./tests/check.sh --suite core --strict
DOTFILES_TEST_POWERSHELL=/path/to/pwsh ./tests/check.sh --suite cross --strict
```

安装探测测试使用 `tests/fixtures/install/commands/` 的真实假命令和封闭 PATH：命令发现、参数、输出、退出码与超时经过实际命令执行边界，不能依赖宿主机是否安装包管理器。Unix 安装 handler/续跑测试共享状态夹具；Windows 续跑测试用 .NET Framework 编译器构建假 WinGet，Unix PowerShell 使用对应脚本。应用发现测试只创建临时文件/目录，并验证普通计划与续跑的一致性。

安装声明的有效预期保存在独立 `expected.plan` 中，不由生产解析器生成。重复的发现无效用例以 `discovery/tool.conf` 为公共样例，用各目录的 `edits.tsv` 明确删除/插入行；Bash 和 PowerShell 的测试专用 materializer 校验原行后，在临时目录生成输入。编辑不匹配公共样例时直接失败，不能被当作“正确拒绝无效配置”。

共享同一用户/锁路径的完整 workflow suite 应串行执行。隔离夹具也必须遵守部署锁，不能通过自动删除遗留锁让测试“通过”。

## 按改动选择验证

| 改动 | 直接检查入口 |
| --- | --- |
| 安装声明/schema | `tests/install-items.sh`、`tests/install-items.ps1`、`tests/install-parity.ps1` |
| Linux 字体 | `tests/font-download.sh`（Unix）、`tests/fonts.sh`（Linux）、`tests/desktop-fonts.py`（可移植）；隔离下载/解析错误、发现、候选文件、重复部署与恢复 |
| 安装机制 | `tests/install-handlers.sh`、`tests/install-docker.sh`（CE 仓库、备份和存在性）、`tests/install-items.ps1`、相关平台 dry-run |
| 执行策略 | `tests/install-policy.sh` / `.ps1` |
| workflow/profile/阶段 | `tests/workflow-schema.sh` / `.ps1`、`tests/workflow.sh` / `.ps1` |
| 续跑/状态提示 | `tests/workflow-resume.sh` / `.ps1`、`tests/install-resume.sh` / `.ps1` |
| Apply 声明/操作 | `tests/apply-schema.sh` / `.ps1`、`tests/apply.sh` / `.ps1`、`tests/apply-contract.sh` / `.ps1` |
| 镜像 | `tests/mirrors.sh`，检查未知配置保留和重复运行 |
| 发现证据/历史安装报告 | `tests/install-report.sh` / `.ps1`，含真实状态入口、运行中/失败/阻塞快照、v1 只读兼容 |
| 数据/命令契约 | `tests/data-contract.*`、`tests/execution-contract.*`、`tests/command.*` |
| 计划解释 | `tests/plan-explain.sh` / `.ps1` |
| 应用原生配置 | 相应应用的解析/检查入口，例如 `fish -n`；不要把服务健康并入 installer 测试 |
| 仅文档 | 链接、命令/字段核对、配置示例解析；无须仅为文本改动执行真实安装 |

详细覆盖与运行参数以 manifest 为准。用临时目录、模拟包清单和录制型 handler 验证变更，不能从契约测试安装真实包、覆盖用户配置或请求真实订阅。终端测试使用本地伪终端。

## CI 与本机验证边界

仓库 CI 已禁用。[保留的 CI 配置](../.github/workflows/install.yml.disabled) 使用 `.disabled` 后缀，不再作为 GitHub Actions 工作流运行（包括 push、pull_request 和手动触发）。如需恢复，将文件改名回 `.github/workflows/install.yml` 并推送。

保留的配置覆盖 Ubuntu/macOS 的 core 和 dry-run、Linux ShellCheck，以及 Windows PowerShell 5.1/7 的 core 与 cross。macOS core 使用 `/bin/bash`，用于最低 Bash 版本兼容验证。

Fedora job 使用 `registry.fedoraproject.org/fedora:latest` 容器，安装测试工具后以普通用户依次执行 strict core、lint 和 dry-run，保留不可访问路径的权限测试，并覆盖真实 DNF 环境中的入口选择及镜像/上游两种预览。容器中的安装器仍只做 dry-run；这不验证实际软件安装、桌面启动或登录 shell 切换，也不代替完整 Windows/WSL 验证。

显式完整 Windows/WSL 流程需要正确的真实 checkout 和 WSL2 guest，不属于 hosted CI 的自动端到端流程：

```powershell
./install/windows.ps1 -DryRun
```

交付记录应写明提交、运行命令、通过/失败和未覆盖平台。CI 文件存在不等于本次提交已通过，也不能把 mock 测试称为真实包安装验证。

## 扩展 manifest

每行六个 Tab 分隔字段：ID、suite、host 集合、runtime、仓库相对 entry、arguments。host 使用 linux/macos/windows，多个 host 用空格分隔；runtime 为 bash/powershell/python。Python entry 可为单个脚本，也可为 unittest discovery 目录。arguments 为字面量空格分隔词，`-` 表示无参数，不执行 shell 表达式或引号分组。

共享解析规则优先使用共同夹具验证 Python 核心，再分别验证两端原生适配器。新增检查应验证可观察的行为或失败边界，不只复述实现。

重复运行回归由 `install-resume.*`、`install-dependencies.*` 和 `workflow.sh` 覆盖：普通运行与续跑共享存在性检查、移除证据后重装、新声明入选、发现失败阻断、安装命令成功但不创建产物仍成功、公共/安装专用依赖区分、独立根项目保留、未选中工具不执行探测，以及无待安装项时不更新包索引或系统。

`tests/profile-roots.sh` / `.ps1` 覆盖纯配置默认、none 集合、方案名称、受控目标根、跨根冲突；Unix 还验证隔离 CLI、重复部署、备份和恢复。WSL 分发和 guest profile 的隔离参数检查位于 `tests/workflow.ps1`，不能代替原生 Windows/WSL 验证。

Python 核心测试位于 `tests/core/`。检查工具默认使用本 checkout 的 `.venv`，也可显式设置 `DOTFILES_PYTHON` 或测试专用的 `DOTFILES_TEST_PYTHON`；Python 验证要求 3.15，缺失或版本不符时 strict 检查失败。运行时与协议测试涵盖固定解释器、仓库外启动、中文与空格路径、严格 JSON、操作允许列表和进程退出码一致性。

## Python 迁移验证记录（2026-11-16）

行为基线为本仓库 `bca3835`，通用实现参考为原项目 `696256f`。验证主机为 macOS，使用 Bash 3.2.57 和通过 `DOTFILES_PYTHON` 显式选择的 Python 3.15.0a8；不是 Python 正式版验证，未将参考仓库的解释器路径写入默认配置。

已运行 `./tests/check.sh --suite core --strict`（31 项通过、0 项失败、25 项平台不适用跳过）和 `python -B -m unittest discover -s tests/core`（146 项，1 项因 PowerShell 不可用跳过），以及默认和 `macos-full` 各自的镜像/上游四组 macOS dry-run。目标根、字体下载、解释输出和终端输入的专项回归通过；测试仅在隔离目录执行文件事务及假安装命令，主机入口仅运行 dry-run。

全量 `--suite all --strict` 尚不能通过：本机缺少 `pwsh` 和 ShellCheck，保留 strict 失败规则。沙箱对 `/dev/tty` 和主机目录写权限观察的限制已通过允许对应访问的重跑验证。Linux 默认/完整方案、PowerShell 5.1 原生 Windows 入口、Windows/WSL2 联动未验证；共享夹具和模拟观察不能替代这些原生检查。CI 仍为 `.disabled`，未运行。
