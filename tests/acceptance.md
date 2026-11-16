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
