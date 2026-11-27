# 测试与验证

准备 Python ≥3.14（checkout 的 .venv 或显式 DOTFILES_PYTHON），运行 `./tests/check.sh --suite all --strict` 或 Windows `./tests/check.ps1 -Suite all -Strict`。共享 manifest 定义 core、cross、dry-run、lint；strict 模式下适用主机缺少运行时即失败，不适用平台明确跳过。

Windows 上的跨 shell 安装计划对照使用 Git for Windows 的 Bash 和本机 Python。检查入口会从 PATH 中的 Git 定位同一安装目录下的 Bash，也可用 `DOTFILES_TEST_BASH` 指定其可执行文件。WSL 使用自己的 checkout 运行环境和 Python。

`tests/core/` 覆盖共享模型、规则和原生适配器。`test_snapshot.py` 覆盖声明依赖、归档完整性、恶意路径、平台拒绝、缺失/变化文件、排除、新增文件、空目录、复制恢复、冲突备份、重复恢复和 guarded journal。测试使用临时 HOME 和配置，不采集实际用户配置，不执行真实软件安装。

原生 Bash/PowerShell 契约测试保留安装处理器、命令退出码、部署事务、备份/恢复、原子报告及部署锁覆盖。旧 `.conf` 和 stage fixture 是底层兼容性测试数据，不是生产软件声明。字体模板渲染已移除，对应测试由真实字体文件的采集/恢复语义替代；字体下载处理器测试保留。

## CI 与本机验证边界

CI 仍禁用，原流程保留为 `.github/workflows/install.yml.disabled`，不据此声称跨平台 CI 通过。原生 Windows/WSL 检查需要对应环境。终端交互测试需要访问 /dev/tty；沙箱限制不是命令终端行为的回归，应在授权环境重试并明确记录。

## 验收记录

按日期和变更整理的实际环境、检查结果及未执行范围见 [验收记录](acceptance.md)。本页只维护可复用的测试说明。

测试前按[根 README 的准备步骤](../README.md#准备)从 GitHub 安装兼容的 dotfile-viewer。统一声明及快照实现的单元测试由 Viewer 维护，本项目继续验证安装、镜像、会话和组合快照流程。旧 v1 快照和公开 journal 恢复命令不再受支持。
