# 验收记录

本文件记录各次变更的实际验证结果；历史记录不代表当前版本或未执行平台已通过验证。测试运行方法及 CI 状态见 [测试与验证](README.md)。

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
