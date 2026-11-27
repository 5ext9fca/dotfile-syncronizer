# 验收记录

本文件记录各次变更的实际验证结果；历史记录不代表当前版本或未执行平台已通过验证。测试运行方法及 CI 状态见 [测试与验证](README.md)。

## Zsh 普通 profile 与本机交互迁移（2026-11-27）

macOS ARM64，Python 3.14.10、系统 zsh 5.9，使用更新后的 Viewer 0.2.0 声明。

- 用 `./install/macos.sh --catalog <Viewer 资源目录> --dry-run` 分别预览 macOS 普通与完整 profile。首次在沙箱内被备份目录可写性检查阻止，取得主机权限后两者均以 packages planned 结束。普通 profile 选中 fzf 和 Antidote，完整 profile 仍包含 Fish。项目虚拟环境随后安装本地构建的 Viewer 并通过 `pip check`。
- Viewer 的严格测试 25 项通过，包含合成 zsh 配置的快照往返和幂等应用。未用真实用户配置制作测试归档。Linux、WSL 和 Windows 未运行原生安装。
- 使用临时历史和伪终端实际验证建议接受、行中右移、按词移动、历史子串搜索、Tab 选择文件、Ctrl+R 选择历史及缩写展开。首次测试未模拟正常终端尺寸，后续给 fzf 设置终端尺寸并等待过滤完成，最终按键用例通过。Zellij 替身验证独立终端和 SSH 启动一次，复用器、VS Code、显式禁用、无 TTY 和非交互调用跳过。测试后在真实登录 zsh 中确认高亮函数和方向键绑定。
- 用合成多行、反斜杠、重复命令和空目标测试历史导入及重复执行。初次真实导出没有选中 fish 的命名历史，明确选择后重新导出，验证原 zsh 历史字节保留、导入结果可读回且重复导入为零。本机认证后读回登录 shell 为 /bin/zsh。
- `./tests/check.sh --strict` 首次在沙箱中 28 项通过，两项因无法访问 /dev/tty 失败。用更新后的依赖在主机权限下重跑，30 项通过、0 项失败，24 项按平台跳过。其中 Python core 运行 163 个用例，跳过 1 个。
- 已复核根 README、安装指南、配置覆盖说明及 AGENTS.md。操作说明与配置覆盖更新在对应文档中。

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

## Unix 默认交互工具与静态插件迁移（2026-11-27）

macOS ARM64、Python 3.14.10，安装本地 Viewer 0.2.0 wheel；`pip check` 通过。Viewer 严格测试 25 项通过。macOS 普通和完整 profile 均通过不指定 catalog 的 dry-run。首次沙箱 dry-run 的默认输出目录不可写，使用主机权限重跑通过。

- `./tests/check.sh --strict` 沙箱运行因终端受限失败两项；重叠的主机测试因部署锁冲突失败三项。独立临时目录重跑通过 30 项，失败 0 项，跳过 24 项。Linux、WSL、Windows 未运行原生安装。
- 本机 Zsh 启动文件语法、非交互静默、工具 PATH、静态插件再生成、compaudit、禁网 PTY 启动及 prompt 渲染通过。Trace 确认补全后端执行一次。首次 PTY 在沙箱内因 Atuin 无法创建本地目录而失败，主机复验通过。中间配置出现函数清理命令拼写问题，修正后复验通过。
- 五次 `zsh -i -c exit` 的中位数从 620 ms 降到最终的 340 ms（330–610 ms），空配置低于计时显示精度。zprof 显示 mise 钩子是主要耗时之一。PTY 确认 Atuin、fzf-tab、原生上下键与逐词移动绑定；外部终端实际按键和视觉效果留作人工确认。
- 已复核根 README、安装指南、应用配置说明和 AGENTS.md；维护与恢复步骤在安装指南。
