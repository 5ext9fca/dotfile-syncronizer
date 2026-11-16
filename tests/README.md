# 测试与验证

准备 Python ≥3.15（checkout 的 .venv 或显式 DOTFILES_PYTHON），运行 `./tests/check.sh --suite all --strict` 或 Windows `./tests/check.ps1 -Suite all -Strict`。共享 manifest 定义 core、cross、dry-run、lint；strict 模式下适用主机缺少运行时即失败，不适用平台明确跳过。

`tests/core/` 覆盖共享模型、规则和原生适配器。`test_snapshot.py` 覆盖声明依赖、归档完整性、恶意路径、平台拒绝、缺失/变化文件、排除、新增文件、空目录、复制恢复、冲突备份、重复恢复和 guarded journal。测试使用临时 HOME 和配置，不采集实际用户配置，不执行真实软件安装。

原生 Bash/PowerShell 契约测试保留安装处理器、命令退出码、部署事务、备份/恢复、原子报告及部署锁覆盖。旧 `.conf` 和 stage fixture 是底层兼容性测试数据，不是生产软件声明。字体模板渲染已移除，对应测试由真实字体文件的采集/恢复语义替代；字体下载处理器测试保留。

## CI 与本机验证边界

CI 仍禁用，原流程保留为 `.github/workflows/install.yml.disabled`，不据此声称跨平台 CI 通过。原生 Windows/WSL 检查需要对应环境。终端交互测试需要访问 /dev/tty；沙箱限制不是命令终端行为的回归，应在授权环境重试并明确记录。

## 本次快照迁移验证（2026-11-16）

验证主机为 macOS ARM64，Bash 3.2.57，显式选择 Python 3.15.0a8（预发布版，不代表已在正式版验证）。

- 最终共享 Python 回归：163 项，全部通过，1 项因缺少 PowerShell 跳过。
- 最终声明、归档及会话规则专项：40 项通过；完整快照恢复的假 Homebrew 边界专项通过，覆盖归档安装声明、失败阻断及成功重跑。
- `./tests/check.sh --suite core --strict` 整轮记录为 27 passed / 3 failed / 24 platform skips。失败项为终端访问受沙箱限制，以及正在迁移的 resume/假 Homebrew 夹具；修正后分别重跑 `tests/command-terminal.py`、`tests/workflow-resume.sh` 和完整 Python suite，均通过。没有把初次 strict 结果记为零失败。
- macOS 默认和 macos-full 安装 dry-run 通过；验证仅执行软件计划，不部署配置。71 个 Bash 文件语法检查、`git diff --check` 和文档相对链接检查通过。
- PowerShell、ShellCheck 不可用；Linux、原生 Windows/WSL 未执行。跨平台模型/声明测试不能替代这些原生检查。

真实安装未执行；配置写入、备份和恢复测试均限于临时目录及假安装命令，没有采集或修改操作者应用配置。
