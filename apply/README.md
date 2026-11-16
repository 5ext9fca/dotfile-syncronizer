# 配置部署与恢复

apply 将 `apply/items/*.conf` 声明的源文件部署到目标配置目录，不安装依赖。Unix 默认组件使用文件级硬链接；Windows 使用复制。应用源文件仍放在各自目录。字段定义见 [配置语义](../docs/configuration.md)。

## 当前组件

| ID | 源 | 目标 | 默认方式 |
| --- | --- | --- | --- |
| fish | `configs/fish/` | `$XDG_CONFIG_HOME/fish` | hardlink，排除 `fish_variables` |
| git | `configs/git/` | `$XDG_CONFIG_HOME/git` | hardlink |
| helix | `configs/helix/` | `$XDG_CONFIG_HOME/helix` | hardlink |
| wezterm | `configs/wezterm/` | `$XDG_CONFIG_HOME/wezterm` | hardlink |
| zellij | `configs/zellij/` | `$XDG_CONFIG_HOME/zellij` | hardlink |
| desktop-fonts | `configs/fontconfig/60-dotfiles-fonts.conf` + 当前桌面设置 | Fontconfig `conf.d`、`kdeglobals`、GTK 3/4 `settings.ini` | 原生 KDE；规则 hardlink，候选设置 copy |
| windows-terminal | `configs/windows-terminal/settings.json` | `LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` | copy |

默认组件从当前平台 profile 读取，WSL 默认不选择 WezTerm，所有默认方案都排除 `desktop-fonts`。`--profile NAME` / `-Profile NAME` 可选择仓库内其他方案，不能与显式组件同时传入。apply 只读取组件，不执行方案中的安装、shell、WSL 或镜像行为。

目标根按所选组件解析：Unix `home=$HOME`、`config_home=${XDG_CONFIG_HOME:-$HOME/.config}`；Windows `home=%USERPROFILE%`、`app_data=%APPDATA%`、`local_app_data=%LOCALAPPDATA%`。必需根缺失、非绝对或不可用时在变更前失败；跨根按最终路径检查重叠，桌面字体 renderer 仍只允许 `config_home`。

## 使用

```bash
./apply/apply.sh --plan --no-mirrors
./apply/apply.sh --dry-run
./apply/apply.sh fish helix --no-mirrors
./apply/apply.sh --results /existing/directory/apply-result.tsv
```

```powershell
./apply/windows.ps1 -PlanOnly
./apply/windows.ps1 -DryRun
./apply/windows.ps1 -Components windows-terminal
./apply/windows.ps1 -ResultsPath 'C:\existing\directory\apply-result.tsv'
```

| Unix | Windows | 用途 |
| --- | --- | --- |
| `--profile NAME` | `-Profile NAME` | 选择仓库内方案的组件，与显式组件互斥 |
| `--china-mirrors` | 无 | 显式更新 Unix 镜像 |
| `--plan` | `-PlanOnly` | 输出版本化文件计划，不部署 |
| `--dry-run` | `-DryRun` | 显示将执行的操作，不修改目标 |
| 位置参数 component | `-Components` | 指定组件；省略时读取 profile |
| `--results FILE` | `-ResultsPath FILE` | 文件操作明细报告 |
| `--restore JOURNAL` | `-Restore JOURNAL` | 显式恢复，不能同时选择组件 |
| `--no-mirrors` | 无 | Unix 跳过镜像更新 |
| `--mirror-config FILE` | 无 | Unix 使用指定镜像配置 |

`--stage-result` / `-StageResultPath` 用于 workflow 传递结构化阶段结果，一般不需手动传入。Unix 镜像更新必须显式指定 `--china-mirrors`。

## 文件操作语义

- 目录按文件展开，目标中未被声明的文件不会被删除。
- hardlink 只有源与目标为同一个文件实体时才跳过；内容相同但 inode 不同仍会部署并备份旧目标。
- copy 在内容相同时跳过。Windows Terminal 是整份配置替换，不是 JSON 合并。
- 冲突文件、符号链接或阻挡路径的对象先进入该次备份；正确的现有目录可复用。
- 检查全部计划的路径、父目录权限、目标重叠和硬链接文件系统约束，再执行文件操作。拒绝源符号链接和不支持的文件类型。
- 编辑一个仍共用 inode 的硬链接会影响另一端；编辑器或 Git 的原子替换可能打断链接关系，之后需要重新 apply。

计划中的 `reason` 区分 new、replace、unchanged、excluded，以及镜像的保护原因。plan 可能包含本次调用生成的临时渲染文件，不支持把输出保存后当作永久部署脚本。

## 备份与恢复

真实操作使用 `${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}` 下的唯一会话。Unix journal 为 `journal.tsv`，Windows 为 `journal.jsonl`；备份位于会话 `files/`。全部跳过也可能留下空的审计 journal。

每项操作记录 prepared/applied 等状态。失败时尝试恢复当前操作；之前成功项保留，之后操作阻断。这不是全流程自动回滚。

```bash
./apply/apply.sh --restore /path/to/session/journal.tsv --plan
./apply/apply.sh --restore /path/to/session/journal.tsv
```

```powershell
./apply/windows.ps1 -Restore 'C:\path\to\session\journal.jsonl' -PlanOnly
./apply/windows.ps1 -Restore 'C:\path\to\session\journal.jsonl'
```

恢复先验证相关记录，然后按反向操作顺序处理。目标/备份内容或身份改变、父路径被替换、待删除目录新增未追踪文件等情况会阻止恢复；不会递归删除应用新增数据。已完成恢复再次执行是无操作。

仅使用这些脚本产生的 journal，不手工伪造或跨版本猜测字段。失败时保留的备份、staging 和 journal 用于人工检查。恢复不会卸载包、撤销 Git 身份或重置登录 shell；系统镜像文件恢复可能需要 sudo。

## 与镜像、workflow 的关系

独立 Unix apply 默认只部署应用配置，`apply fish` 不处理镜像。显式指定 `--china-mirrors` 才应用 `mirrors/current.conf`；`--no-mirrors` 保留为显式关闭选项。

安装 workflow 的 configuration 阶段禁用内嵌镜像，再单独执行 mirrors 初始化阶段。镜像复用同一文件计划/备份机制，规则见 [镜像说明](../mirrors/README.md)。真实部署和恢复遵守同一 [部署锁](../workflow/README.md)，不会自动清理异常退出留下的锁。

## 桌面字体

`desktop-fonts` 仅在原生 Linux 且 `XDG_CURRENT_DESKTOP` 包含 KDE 时应用；其他环境明确记录 `requires-native-linux-kde` 跳过。它不受 `--no-mirrors` 控制。

```bash
./apply/apply.sh --plan --no-mirrors desktop-fonts
./apply/apply.sh --dry-run --no-mirrors desktop-fonts
./apply/apply.sh --no-mirrors desktop-fonts
```

默认组件要求 `Noto Sans CJK SC` 和 `JetBrainsMono Nerd Font`。预览报告缺失项并提示安装；实际部署在任何文件变更前失败。完整安装的预览允许字体尚未安装，并不把配置前置检查当作安装成功判据。

Fontconfig 规则通过显式映射硬链接，按请求 family 区分：sans-serif、serif、system-ui 默认优先 Noto Sans CJK SC；monospace 依次使用 JetBrainsMono Nerd Font、Noto Sans CJK SC。显式网页/文档字体仍优先，不覆盖 Emoji 和其他文字的必要回退。

字体行为统一读取该组件 `source` 指向的 Fontconfig XML：`system-ui` 的第一个 `prefer/family` 用作 KDE/GTK 正文字体，`monospace` 的第一个用作 KDE 等宽字体；顶层 alias 中全部 `prefer/family` 和 `accept/family` 去重后用于缺失字体预检。必须显式声明 sans-serif、serif、system-ui、monospace 四组非空 prefer；重复 alias、XML 实体及含控制字符、逗号、竖线、反斜杠或方括号的 family 会被拒绝。这里读取的是显式声明，不求解系统 Fontconfig 的 match/include 规则。

修改 `configs/fontconfig/60-dotfiles-fonts.conf` 中的 family 即可改变上述行为，无需修改 Python/Bash；所选字体仍须由安装声明或用户自行安装。只保留 Fontconfig 部署、停用 KDE/GTK 修改时，从 apply 项移除 `renderer=desktop-fonts`；`condition=linux-kde` 仍决定整个组件的适用环境。更改安装集合使用 `install/items/` 和 workflow profile。详见 [Fontconfig 用户配置](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html)。

渲染器读取当前 `kdeglobals`、`gtk-3.0/settings.ini`、`gtk-4.0/settings.ini`，只更改托管字体 family；保留字号、字体参数、缩放、抗锯齿、其他键和注释及文件权限。KDE 未声明项先通过 KConfig 查询继承设置，仍无值时使用 Plasma 内置默认字号（常规 10、小字号 8）；GTK 缺失项通过运行中的 GTK 读取默认字体。无法安全解析、重复托管键、不可变 KConfig 标记或设置路径为符号链接时明确失败。已选定的 Python ≥3.15 运行时和 KConfig 读取工具必须在配置预检时可用。

候选文件使用现有 copy 操作，内容相同即跳过；冲突备份、当前操作失败回滚、journal、部署锁和显式受保护恢复均复用现有契约。预览只在临时目录生成候选文件，并打印字体键变化，不下载或刷新缓存，不修改用户设置。设置在应用重启或重新登录后生效，不自动退出会话。WezTerm 保留已有回退链；Fish、终端 Helix 和 Zellij 继承终端字体，IDE 由用户自行配置。

实际安装、部署后可独立验收（不属于安装成功判断）：

```bash
fc-match 'sans-serif:charset=0041'
fc-match 'sans-serif:charset=4e2d'
fc-match 'monospace:charset=0041'
fc-match 'monospace:charset=4e2d'
```

预期依次为 Noto CJK、Noto CJK、JetBrainsMono、Noto CJK。中文验收使用字符条件，单独 `lang=zh-cn` 不保证选到含中文字符的第一个 family。另需在 KDE、GTK、浏览器默认正文和 WezTerm 检查中文标点、粗体、图标和表格对齐。

规划与执行调度由 `dotfiles_core/apply_*.py` 统一负责；原生适配器保留完整事务、journal、恢复和部署租约。独立 apply、plan、dry-run 与 restore 都需要预先准备 [Python 运行时](../install/README.md#python-运行时)。
