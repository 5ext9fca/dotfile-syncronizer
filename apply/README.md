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

`XDG_CONFIG_HOME` 未设定时使用 `$HOME/.config`。WSL profile 不选择 WezTerm，但直接运行不带组件选择的 Unix apply 仍选择所有 Unix 声明。需要同样的 WSL 选择时，使用 installer 的 configuration 阶段或显式指定组件。

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
| `--plan` | `-PlanOnly` | 输出版本化文件计划，不部署 |
| `--dry-run` | `-DryRun` | 显示将执行的操作，不修改目标 |
| 位置参数 component | `-Components` | 指定组件；省略时全部 |
| `--results FILE` | `-ResultsPath FILE` | 文件操作明细报告 |
| `--restore JOURNAL` | `-Restore JOURNAL` | 显式恢复，不能同时选择组件 |
| `--no-mirrors` | 无 | Unix 跳过镜像更新 |
| `--mirror-config FILE` | 无 | Unix 使用指定镜像配置 |

`--stage-result` / `-StageResultPath` 用于 workflow 传递结构化阶段结果，一般不需手动传入。Unix 的 `--china-mirrors` 是默认启用行为。

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

独立 Unix apply 默认应用 `mirrors/current.conf`；即使只选择 fish，也不会隐式关闭镜像阶段。需要纯应用文件更新时显式使用 `--no-mirrors`。

安装 workflow 的 configuration 阶段禁用内嵌镜像，再单独执行 mirrors 初始化阶段。镜像复用同一文件计划/备份机制，规则见 [镜像说明](../mirrors/README.md)。真实部署和恢复遵守同一 [部署锁](../workflow/README.md)，不会自动清理异常退出留下的锁。

## 桌面字体

`desktop-fonts` 仅在原生 Linux 且 `XDG_CURRENT_DESKTOP` 包含 KDE 时应用；其他环境明确记录 `requires-native-linux-kde` 跳过。它不受 `--no-mirrors` 控制。

```bash
./apply/apply.sh --plan --no-mirrors desktop-fonts
./apply/apply.sh --dry-run --no-mirrors desktop-fonts
./apply/apply.sh --no-mirrors desktop-fonts
```

组件要求 `PingFang SC`、`JetBrainsMono Nerd Font`、`Noto Sans CJK SC`。预览报告缺失项并提示安装；实际部署在任何文件变更前失败。完整安装的预览允许字体尚未安装，并不把配置前置检查当作安装成功判据。

Fontconfig 规则通过显式映射硬链接，按请求 family 区分：sans-serif、serif、system-ui 默认优先苹方；monospace 依次使用 JetBrainsMono Nerd Font、Noto Sans CJK SC。显式网页/文档字体仍优先，不覆盖 Emoji 和其他文字的必要回退。详见 [Fontconfig 用户配置](https://fontconfig.pages.freedesktop.org/fontconfig/fontconfig-user.html)。

渲染器读取当前 `kdeglobals`、`gtk-3.0/settings.ini`、`gtk-4.0/settings.ini`，只更改托管字体 family；保留字号、字体参数、缩放、抗锯齿、其他键和注释及文件权限。KDE 未声明项先通过 KConfig 查询继承设置，仍无值时使用 Plasma 内置默认字号（常规 10、小字号 8）；GTK 缺失项通过运行中的 GTK 读取默认字体。无法安全解析、重复托管键、不可变 KConfig 标记或设置路径为符号链接时明确失败。Python 3 和 KConfig 读取工具必须在配置预检时可用。

候选文件使用现有 copy 操作，内容相同即跳过；冲突备份、当前操作失败回滚、journal、部署锁和显式受保护恢复均复用现有契约。预览只在临时目录生成候选文件，并打印字体键变化，不下载或刷新缓存，不修改用户设置。设置在应用重启或重新登录后生效，不自动退出会话。WezTerm 保留已有回退链；Fish、终端 Helix 和 Zellij 继承终端字体，IDE 由用户自行配置。

实际安装、部署后可独立验收（不属于安装成功判断）：

```bash
fc-match 'sans-serif:charset=0041'
fc-match 'sans-serif:charset=4e2d'
fc-match 'monospace:charset=0041'
fc-match 'monospace:charset=4e2d'
```

预期依次为苹方、苹方、JetBrainsMono、Noto CJK。中文验收使用字符条件，单独 `lang=zh-cn` 不保证选到含中文字符的第一个 family。另需在 KDE、GTK、浏览器默认正文和 WezTerm 检查中文标点、粗体、图标和表格对齐。
