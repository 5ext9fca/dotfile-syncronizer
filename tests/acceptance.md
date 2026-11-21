# 验收记录

本文件记录各次变更的实际验证结果；历史记录不代表当前版本或未执行平台已通过验证。测试运行方法及 CI 状态见 [测试与验证](README.md)。

## 2026-11-22 · 原生 Windows 桌面字体

Windows 11 Pro x64（26300），checkout 的 Python 3.14.0 虚拟环境，editable Viewer 0.2.0。实机应用使用字体专用 profile；测试未采集本机配置。

- `install/windows.ps1 -Profile windows-fonts -DryRun` 显示保留已注册的六份苹方，计划安装 SF Pro Text。实际运行安装八份 SF Pro Text，再次运行两项都报告 `already-installed`。
- Windows PowerShell 5.1 的默认及完整 profile 预览起初因传给 Python 的引号被移除而找不到部署锁脚本。修复取路径的参数后，`-Profile windows -DryRun` 和 `-Profile windows-full -DryRun` 均通过。单独运行 `tests/install-items.ps1` 通过 76 个共享用例及处理器检查。
- 本机备份六项桌面字体及有关注册表原值，通过 Win32 更改字体后回读，六项均为 SF Pro Text；逐字节比较六份 LOGFONT 中字体名之前的字段，字号、字重等均保留。机器级 GDI 回退首项指向系统目录中的苹方常规体，其 SHA-256 与原用户字体一致。
- 八份 SF Pro Text 的字符映射都包含数字 0，苹方包含“夜”。当前会话的 WinForms 字形比较中，“夜、曲”与直接指定苹方的结果不同。本次未重启，重启后各应用的实际回退尚未验证。
- 在临时目录以本机 Arial 字体模拟下载，声明不同家族，处理器在创建安装目标之前报错。Git Bash 和 Windows Python 的路径格式及空行导致原始 `tests/install-parity.ps1` 失败；分别转换路径并忽略输出空行后，20 种平台、镜像和环境组合的全部非空计划行一致。
- 首轮严格检查受到会话中断。修复 PowerShell 5.1 入口后，以独立测试锁重新运行 `tests/check.ps1 -Strict`，21 项通过、4 项失败、29 项平台跳过。两个报告契约用例断言失败；另两个套件都在快照读失败用例中将临时文件的创建也模拟成权限错误，Windows 不断重试并耗用内存，确认调用栈后终止了对应的测试子进程。单独限制测试进程的 `tempfile.TMP_MAX=64` 重跑 Python 套件，163 项中报告 8 个断言失败、12 个错误及 11 项跳过。
- 已复核两仓库的 README、AGENTS、配置及安装文档。原生 Linux、WSL、macOS 和 CI 未运行。

## 2026-11-22 · 对接 dotfile-viewer 和 Linux 桌面字体

Fedora 45 KDE（原生 x86_64、DNF）、Python 3.14.10，checkout 的 `.venv` 安装新版 Viewer 0.2.0。本轮按操作请求配置了桌面；快照回归另用临时 HOME 和合成内容。

- `./install/linux.sh --dry-run --yes` 的默认选择（显式 `--profile linux`）、`linux-full` 和 `linux-fonts` 均通过。执行两次 `./install/linux.sh --profile linux-fonts --yes`，首次保留已有的六个 PingFang SC 文件、安装八个 SF Pro Text 文件，第二次两项均跳过。
- 通过 Viewer 的版本检查、备份和显式硬链接拆分保存四个桌面配置，再通知 KDE 更新当前会话。KDE、GTK portal 均返回 SF Pro Text。用 `pango-view --serialize-to` 检查 Regular、Medium、Semibold，“夜曲”均使用 PingFang SC，“Nocturne 03:42”均使用 SF Pro Text；`fc-match monospace` 仍为 JetBrainsMono Nerd Font。
- 在四份合成配置上通过 Viewer 导出、检查、应用预览、应用及重复应用。归档含字体声明，恢复的配置内容一致，重复应用四项均跳过。安装器的 `snapshot/snapshot.sh restore --dry-run` 同样通过。
- 首轮 `./tests/check.sh --strict` 为 26 通过、5 失败、23 项平台跳过。Linux 入口测试的夹具缺安装目录并沿用旧 catalog 定位；计划解释读取 Viewer 声明后仍从旧目录枚举排除项。两处修正后用例通过。镜像、apply 契约、执行契约在与本机操作并行时失败，分别用独立部署锁重跑通过。
- 最终设置独立测试锁再跑完整 `./tests/check.sh --strict`，31 项通过、0 失败、23 项平台跳过。构建 Viewer wheel 并逐字节核对其中的两份字体声明、桌面依赖及两个 Linux profile，结果一致。
- Viewer 严格检查 24 项通过。安装器 Python 回归 163 项，其中 PowerShell 包装器和 macOS 专用用例各跳过一项。变更的 shell 脚本通过 `bash -n`；本机无 ShellCheck 和 PowerShell。已复核两项目 README、AGENTS、配置说明、安装与快照文档。原生 APT、Pacman、WSL、macOS、Windows 未执行。

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
