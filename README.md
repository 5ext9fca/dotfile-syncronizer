# Dotfile Syncronizer

手动运行的软件安装与配置迁移编排器。统一软件声明、profile、配置查看编辑和快照能力由依赖包 **dotfile-viewer** 提供；本项目不维护第二份声明或应用配置正文。

## 准备

准备 Git 和 Python >=3.14（验证使用 Python 3.14）。在本仓库根目录执行以下命令，从 [dotfile-viewer 的 GitHub 仓库](https://github.com/5ext9fca/dotfile-viewer) 的 `main` 分支安装兼容的 Viewer 0.2.x。

```bash
python3.14 -m venv .venv
.venv/bin/python -m pip install "dotfile-viewer @ git+https://github.com/5ext9fca/dotfile-viewer.git@main" "dotfile-viewer>=0.2,<0.3"
```

如果环境中已安装同版本的本地 `dotfile-viewer`，在上述安装命令中加上 `--force-reinstall` 即可切换来源。从旧名称升级时，先在该环境执行 `python -m pip uninstall dotfiles-viewer`，再安装 `dotfile-viewer`。本项目已同步使用 `dotfile_viewer` 导入和模块入口，不保留 Viewer 旧名称兼容层；既有备份目录、`DOTFILES_*` 环境变量和共享锁路径保持不变。

Windows 可用 `py -3.14 -m venv .venv` 创建环境，执行上述 pip 命令时将解释器路径换为 `.\.venv\Scripts\python.exe`。也可用 `DOTFILES_PYTHON` 指定已装好依赖的解释器。不要在运行过程中替换解释器。

## 安装软件

```bash
./install/macos.sh --dry-run
./install/macos.sh --profile macos-full
./install/linux.sh --dry-run --yes
./install/macos.sh --catalog /path/to/catalog --dry-run
```

`--catalog DIR`（Windows `-Catalog DIR`）选择 Viewer 格式的完整声明目录；也可共享 `DOTFILES_CATALOG`。默认从安装的 Viewer 包读取声明和 profile，不读取本项目旧目录。

普通安装只安装软件，不隐式应用配置、设置登录 shell 或启动 WSL。安装检查当前存在性，安装命令按执行策略退出即成功，不追加安装后探测或服务检查。Linux 仍按 Pacman、APT、DNF 包管理器选择分支。

## 快照迁移

```bash
# 兼容入口转交 Viewer 导出和验证
./snapshot/snapshot.sh create --profile macos --output /existing/path/settings.zip
./snapshot/snapshot.sh inspect --snapshot /existing/path/settings.zip
# 先验证配置，再安装，最后重新规划并应用配置
./snapshot/snapshot.sh restore --snapshot /existing/path/settings.zip --dry-run
./snapshot/snapshot.sh restore --snapshot /existing/path/settings.zip
# 只应用配置，不安装
./apply/apply.sh --snapshot /existing/path/settings.zip --dry-run
```

只支持 Viewer v2 ZIP，旧 v1 必须重新导出。同安装分支、CPU 架构和 native/WSL 环境才可迁移。Windows 与 WSL 分别执行。多硬链接目标需 `--detach-hardlink`（PowerShell `-DetachHardlink`）明确确认独立保存。

失败后检查报告和备份，处理原因后手动重跑。未知额外文件保留，不跨软件安装与配置阶段回滚，不自动重试或回收遗留部署锁。历史 journal 恢复命令已移除，已有资料不删除。

查看、编辑、声明维护和独立快照操作见 Viewer 文档。详细安装命令见 [安装](install/README.md)，组合流程见 [快照](snapshot/README.md)，验证见 [测试](tests/README.md)。
