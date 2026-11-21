# 验收记录

本文件记录各次变更的实际验证结果；历史记录不代表当前版本或未执行平台已通过验证。测试运行方法及 CI 状态见 [测试与验证](README.md)。

## Viewer 依赖切换至 GitHub（2026-11-21 至 22 日）

环境为 macOS ARM64，使用本仓库 `.venv` 中的 Python 3.14.10 和 pip 26.2.2。

- `git ls-remote` 首次受沙箱 DNS 限制，获准联网后确认上游默认分支为 `main`，当时没有标签。
- 用 pip 的 `--force-reinstall` 选项和项目声明的两条依赖要求重新安装 Viewer。安装记录 `direct_url.json` 显示来源为 `https://github.com/5ext9fca/dotfile-viewer.git`，分支为 `main`，提交为 `18d2e5a0941bda75624fc2782281ebf07e04ef0a`，发行版本为 0.2.0。`pip check` 和 Viewer 公共 API 的默认 catalog 定位均通过。
- 使用 Python 解析 `pyproject.toml` 与 README 的 pip 命令，确认依赖参数一致，版本范围接受 0.2.0 并排除 0.3.0。已复核根 README、安装与测试说明、AGENTS、架构文档和禁用的 CI 工作流。
- `./tests/check.sh --suite dry-run --strict` 使用临时 `DOTFILES_BACKUP_DIR`。4 项 macOS 预演通过，4 项 Linux 检查按平台跳过。
- `./tests/check.sh --strict` 初次运行有 28 项通过、2 项失败、24 项按平台跳过。两项失败均因沙箱限制访问 `/dev/tty`。获准后在沙箱外分别重跑 `tests/command-terminal.py` 和完整 Python 核心套件，终端交互通过，Python 163 项中 162 项通过、1 项跳过。未运行原生 Linux、Windows 或 WSL 验证。

## Viewer 更名为 dotfile-viewer（2026-11-16）

环境：macOS ARM64，Python 3.14.10。依赖改为 `dotfile-viewer>=0.2,<0.3`；Python 导入、Bash/PowerShell 入口、资源定位、测试及文档均改用 `dotfile_viewer`。不添加 Viewer 旧名称兼容层；既有备份、journal、环境变量和共享部署锁协议不变。

- 卸载旧发行包后，首次离线可编辑安装因本环境缺少 setuptools 失败；随后离线安装 Viewer 构建的 wheel 成功。环境中已确认新发行包/API 可用，旧 `dotfiles_viewer` 导入不存在。运行前完成依赖安装，没有在测试期间替换解释器或运行依赖。
- `./tests/check.sh --strict`：30 项检查通过、0 失败、24 项因宿主平台不适用跳过。包括安装、应用、镜像、恢复、共享租约、超时/取消和组合快照；Python 核心测试 163 项，162 通过、1 项因 PowerShell 不可用跳过。
- `./tests/check.sh --suite dry-run --strict`：首次沙箱内执行时，4 项 macOS 检查均因默认备份父目录的可写性预检受限而失败；在沙箱外重跑，4 项 macOS 检查全部通过、4 项 Linux 检查按平台跳过。覆盖默认及完整配置、镜像与上游源预览；没有真实安装软件或应用配置。
- Viewer 自身 18 项隔离测试通过；从干净源码构建 wheel，在新的 Python 3.14 环境和 checkout 外验证新 CLI/API、54 个默认声明、五个平台图、8 个 profile 及共享锁资源，确认没有旧包或旧命令入口。
- 两仓库共 9 个相关 Bash 脚本通过语法检查；当前环境未提供 ShellCheck/PowerShell，未声称完成这些工具的检查。两仓库 `git diff --check` 通过。
- 已复核 README、AGENTS、架构、配置、声明编写指南、组件和测试文档，以及维护 skill 中的 Viewer 名称；README 补充更名升级步骤并移除过时的 Web UI 描述。历史验收记录保留当时名称。

未运行原生 Linux、Windows、WSL 验证；模拟和平台图检查不代表原生覆盖。未采集或改写真实用户配置。Viewer 功能检查发现的既有缺口记录在其 `tests/acceptance.md`，本次仅完成更名和依赖联动。

## Agent 软件声明维护 skill（2026-11-16）

本次只新增 `skills/maintain-software/SKILL.md` 并更新文档入口，没有修改软件声明、profile 或执行代码。验证环境为 macOS，checkout `.venv/bin/python` 为 Python 3.15.0a8。

- `.venv/bin/python /Users/hx/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/maintain-software` 未完成：校验器依赖的 PyYAML 不可用（`ModuleNotFoundError`），没有安装依赖或切换解释器。
- 改用该 Python 的标准库内联检查本次简单 frontmatter 的两个字段、名称与目录一致性、长度、无占位符、文档相对链接及 skill 中具体文件路径，全部通过。这不是完整 YAML 解析，也不代表标准校验器通过。
- `git diff --check` 通过；人工核对新增、修改、删除声明三类流程，确认包含来源证据、依赖引用、`all` 集合影响、配置隐私、隔离验证与实际操作边界。
- 已复核根 README、AGENTS、声明编写指南、配置语义、安装及测试手册；新增入口与既有语义一致，无 CLI/schema 变化，组件操作命令无需修改。
- 未执行安装 dry-run、快照测试、真实安装/采集/恢复或原生 Linux/Windows/WSL 检查；本次仅为 skill 与文档变更，未声称完成 agent 实际维护任务的行为测试。

## 快照迁移验证（2026-11-16）

验证主机为 macOS ARM64，Bash 3.2.57，显式选择 Python 3.15.0a8（预发布版，不代表已在正式版验证）。

- 最终共享 Python 回归：163 项，全部通过，1 项因缺少 PowerShell 跳过。
- 最终声明、归档及会话规则专项：40 项通过；完整快照恢复的假 Homebrew 边界专项通过，覆盖归档安装声明、失败阻断及成功重跑。
- `./tests/check.sh --suite core --strict` 整轮记录为 27 passed / 3 failed / 24 platform skips。失败项为终端访问受沙箱限制，以及正在迁移的 resume/假 Homebrew 夹具；修正后分别重跑 `tests/command-terminal.py`、`tests/workflow-resume.sh` 和完整 Python suite，均通过。没有把初次 strict 结果记为零失败。
- macOS 默认和 macos-full 安装 dry-run 通过；验证仅执行软件计划，不部署配置。71 个 Bash 文件语法检查、`git diff --check` 和文档相对链接检查通过。
- PowerShell、ShellCheck 不可用；Linux、原生 Windows/WSL 未执行。跨平台模型/声明测试不能替代这些原生检查。

真实安装未执行；配置写入、备份和恢复测试均限于临时目录及假安装命令，没有采集或修改操作者应用配置。


## 2026-11-16 · 依赖 Viewer 与 Python 3.14

环境：macOS ARM64，Python 3.14.10。预先安装本地 dotfiles-viewer 0.2.0 及其 FastAPI/Pydantic/AnyIO 依赖。旧 3.15 虚拟环境移至临时目录，运行之外创建新环境。

统一软件声明、profile、声明 schema、快照 v2 与部署锁归 Viewer；本项目保留安装执行、镜像及组合流程。旧 v1 快照和历史 journal 恢复命令取消，已有资料不删除。Web UI 按用户要求在 Viewer 保留，但不再是必需交付项。

- `DOTFILES_BACKUP_DIR=/private/tmp/viewer-syncronizer-validation ./install/macos.sh --dry-run`：通过。
- 同环境 `./install/macos.sh --profile macos-full --dry-run --no-china-mirrors`：通过。仅观察与预览，无真实安装。
- Python 核心回归首轮发现旧版本断言、配置阶段 sidecar 和重复 schema 路径，已修正。163 项核心检查中最后两处过期断言已改为拒绝 Python 3.13 和旧 v1，随后重跑 snapshot（24 项通过）与 runtime（10 项，9 通过、PowerShell 不可用跳过）。
- 终端中断测试在沙箱内因 /dev/tty 权限失败，授权后在沙箱外通过。
- Viewer 自身 21 项隔离测试通过；快照集成使用伪 Homebrew，验证归档安装规则、失败阻断与成功应用。未采集真实配置或变更本机软件。

原生 Linux/Windows/WSL 未执行；PowerShell 与 ShellCheck 不可用。文档已按单向依赖和新的声明所有权复核，历史验收记录保留原样。

最终完整 core 调用：28 个检查通过、2 个失败、24 个平台不适用跳过。两个失败项为旧会话提示断言和运行期间更新的备份路径断言；均已修正。`bash tests/execution-contract.sh` 重跑通过；最终 `.venv/bin/python -m unittest discover -s tests/core -v` 为 163 项、162 通过、1 项因缺少 PowerShell 跳过。其余适用检查包括安装、handlers、workflow、镜像、apply 事务、共享锁、真实进程竞争、终端输入/Ctrl-C、超时取消、依赖选择及报告均已有通过记录。没有宣称初次完整调用全绿。

`git diff --check` 通过。文档已复核两项目 README、AGENTS 和相关组件说明，移除旧恢复入口提示及重复声明位置。Viewer wheel 独立加载 54 个默认软件声明，确认包资源无需 checkout。
