# 配置语义

本页解释仓库自己的声明格式。应用文件使用各自的 Fish、TOML、Lua、KDL、JSONC 或 YAML 语法，不共用这里的 parser。LLM 新增声明时应同时遵守 [生成指南](llm-config-authoring.md)。

`configs/` 存放下游应用使用的原生配置源文件；本页描述的安装、部署、流程和镜像控制声明仍归各模块所有。`configs/` 不是对 `~/.config/` 的直接映射，也不会自动部署其中所有目录。

## 配置与运行产物的区别

| 文件 | 作者维护 | 读取者 | 格式 |
| --- | --- | --- | --- |
| `install/items/<id>.conf` | 是 | install reader | 平台 section + `key=value` |
| `apply/items/<id>.conf` | 是 | apply reader | `[unix]` / `[windows]` + `key=value` |
| `workflow/profiles/<name>.conf` | 是 | workflow profile reader | 无 section，六个必填字段 |
| `mirrors/current.conf` | 是 | mirror reader | 无 section，完整端点集合 |
| `install/schema/*.tsv` 等 | 维护者 | parser / dispatcher | schema 或注册表，真实 Tab 分隔 |
| 会话 `request.tsv`、`*.result`、摘要、journal | 否 | 状态查询、续跑、恢复 | 运行时产物，不是新增软件的配置入口 |

install/apply 文件名 ID 满足 `[a-z0-9][a-z0-9-]*`，来自文件名，不写 `id=`。所有声明按字面量读取，不 `source`/`eval`。不要添加 shell 引号、变量替换或行内注释来表达值；整行 `#` 注释和空行可用。为保持两端一致，统一写成无首尾空白的 `key=value`，不在等号周围加空格。

install/apply 允许 parser 去除行首尾空格，但 profile 和 mirror 并不提供同样的空白归一化。值不能带 `|`、Tab 或换行。选用现有字段的同时还必须满足所属方法/来源组合，不是“schema 中存在的字段就能用于所有项目”。

## 安装项

支持 `[linux.apt]`、`[linux.dnf]`、`[linux.pacman]`、`[macos]`、`[windows]`。省略 section 表示该平台不安装；没有继承、默认 section 或 `[wsl]`。同一文件可包含多个平台，不能重复 section 或 key。多方式声明还允许 `[平台/方式]` 子 section（见下文）。解析器会验证文件集合中的全部平台声明和依赖，不只校验当前输出平台。

安装项不接受 `schema_version`、`enabled`、`version`、任意命令或 timeout 字段。

### 字段

| 字段 | 语义与限制 |
| --- | --- |
| `order` | 必填，0..999999；依赖已满足的项目之间按数字排序，相同值按 ASCII ID 排序 |
| `method` | 单方式声明必填，必须是该平台支持的注册机制；多方式声明由 preferred_method 选出 |
| `methods`、`preferred_method` | 多方式声明的方式列表与优先安装方式；不能和公共 method 混用 |
| `detect_files`、`detect_dirs` | 分号分隔的类型化路径；分别要求普通文件、目录存在，详见应用发现 |
| `source_kind` | 必填，约束实际来源字段；没有特殊来源也要写 `default` |
| `packages` | 机制要求的包名；通常按空格拆分。winget、msvc、rustup、pipx 只允许一个包/工具链 |
| `depends_on` | 公共依赖，空格分隔的同平台安装项 ID；目标已发现时仍处理，必须存在、无重复、无环、环境兼容 |
| `install_depends_on` | 单方式声明的安装专用依赖；目标需要安装时才引入。与公共依赖重复的边仍按公共依赖处理 |
| `environments` | `native`、`wsl` 或 `native wsl`；省略通常代表两者；Windows/macOS 使用 native |
| `scope` | 仅保留旧值 `desktop`，等价 native-only；不能与 environments 同用，新配置用 environments |
| `provides` | 单个已注册 capability；只表达安装所有权，不表达服务可用性 |
| `wsl_provider` | 只允许 native-only Linux 项，必须匹配 provides 的已注册 provider；在 WSL 跳过本地安装 |
| `check` | 兼容旧声明的命令探测；新声明使用 detect_files/detect_dirs，不能与应用发现混用 |
| `source_url` | URL 来源；仅 cargo-index 可使用 `sparse+https://` |
| `mirror_url` | 来源字段为 source_url 时可提供替代 URL；镜像开关决定是否使用 |
| `source_repo` | 仓库、tap、COPR、WinGet source 等标识，由 source_kind 解释 |
| `source_release` | APT release，通过 `-t` 选择 |
| `shell` | script 必填，`bash` 或 `sh` |
| `args` | script 的字面量参数，按空格拆分；不支持 shell 引号分组或命令表达式 |
| `env` | script 的一个 `NAME=value`，值不能含空格；不是多变量列表 |
| `key_url`、`keyring` | apt-repository 的密钥 URL 和受限文件名 |
| `fallback` | apt-or-snap 的 Snap 包名 |
| `components` | rustup 的逗号分隔组件，或 MSVC 组件标识；不是 workflow 的 component 映射 |
| `font_files` | font-download 必填；空格分隔的唯一 `.otf`/`.ttf` 文件名，文件主体限字母、数字、下划线、连字符，不允许路径 |
| `workload` | MSVC workload 标识 |

`install/schema/fields.tsv` 只定义用户可写的声明字段；生成计划的字段顺序和版本由 `contracts/schema/install-plan.fields` 与 `types.tsv` 定义，二者分别维护。

字段的精确字符约束以 [fields.tsv](../install/schema/fields.tsv) 和 parser 为准。

### 方法与来源组合

下表的“必填字段”不重复公共的 `order`、`method`、`source_kind`，也不重复 source_kind 自身要求的字段。

<!-- install-methods:start -->
| method | 平台 | 方法必填字段 | source_kind | 方法可选字段 |
| --- | --- | --- | --- | --- |
| `apt` | linux.apt | packages | default apt-release | - |
| `dnf` | linux.dnf | packages | default dnf-repo | - |
| `pacman` | linux.pacman | packages | default pacman-repo | - |
| `cargo` | linux.apt linux.dnf linux.pacman | packages | default cargo-index | - |
| `pipx` | linux.apt linux.dnf linux.pacman | packages | default pypi-index | - |
| `brew` | macos | packages | default brew-tap | - |
| `cask` | macos | packages | default brew-tap | - |
| `script` | linux.apt linux.dnf linux.pacman macos | source_url shell | download | args env |
| `rustup` | linux.apt linux.dnf linux.pacman macos | packages components | default rust-dist | - |
| `apt-or-snap` | linux.apt | packages fallback | default | - |
| `apt-repository` | linux.apt | packages key_url keyring | apt-repo | - |
| `dnf-copr` | linux.dnf | packages | copr | - |
| `docker-ce` | linux.apt linux.dnf | packages | download | - |
| `xcode` | macos | 无 | default | - |
| `homebrew` | macos | source_url | download | - |
| `winget` | windows | packages | winget | - |
| `msvc` | windows | packages components workload | winget | - |
| `font-download` | linux.apt linux.dnf linux.pacman | source_url font_files | download | - |
<!-- install-methods:end -->

来源字段映射：

<!-- install-sources:start -->
| source_kind | 必填来源字段（`-` 表示无） |
| --- | --- |
| `default` | `-` |
| `apt-release` | `source_release` |
| `dnf-repo` | `source_repo` |
| `pacman-repo` | `source_repo` |
| `brew-tap` | `source_repo` |
| `cargo-index` | `source_url` |
| `pypi-index` | `source_url` |
| `rust-dist` | `source_url` |
| `download` | `source_url` |
| `apt-repo` | `source_url` |
| `copr` | `source_repo` |
| `winget` | `source_repo` |
<!-- install-sources:end -->

两张表对应 [methods.tsv](../install/schema/methods.tsv) 与 [sources.tsv](../install/schema/sources.tsv)。例如 `method=apt` 不能使用 `source_kind=apt-repo`；添加自定义 APT 仓库应使用 `apt-repository` 并提供密钥字段。

`docker-ce` 将 `source_url` 作为 Docker 官方 Linux 仓库根地址，由 Linux 入口提供的发行版 ID 和 codename 选择 Debian/Ubuntu 的 APT 仓库或 Fedora/CentOS/RHEL 的 RPM 仓库。仅在所列 CE 包未全部安装时准备仓库；不支持的发行版在只读预检失败。替换仓库文件或密钥前备份到本次会话的 packages-backups/system/docker；不自动卸载冲突包或启动服务。Pacman 不使用此方法。

`font-download` 的 source_url 必须是 HTTPS 基础目录，不接受 mirror_url；逐个追加 font_files 文件名下载，不执行脚本。目标固定为 `~/.local/share/fonts/<id>/`；作者应为整组字体声明 detect_files，并声明 Fontconfig/curl 依赖。临时文件全部解析后发布并刷新缓存，失败策略见安装手册。

### 多种安装方式与应用发现

单方式声明仍使用 `method`，可以直接增加 `detect_files` / `detect_dirs`。多方式声明将公共字段放在平台 section，将每种方式的安装参数和发现路径放在 `[平台/方式]`：

```ini
[macos]
order=30
methods=cask manual
preferred_method=cask
environments=native
provides=docker

[macos/cask]
depends_on=homebrew
packages=docker-desktop
source_kind=default
detect_dirs=brew_prefix:Caskroom/docker-desktop;applications:Docker.app

[macos/manual]
detect_dirs=applications:Docker.app
```

公共字段限于 `order`、`methods`、`preferred_method`、`depends_on`、`environments`、`scope`、`provides`、`wsl_provider`。公共依赖适用于整个应用；可安装方式子项也可声明 `depends_on`。最终计划仅合并公共依赖与首选方式依赖，按声明顺序去重；同一列表内部重复仍报错。每个安装方式必须在列表中唯一出现，并有对应子 section；子 section 除追加 `depends_on` 外不能覆盖公共字段或另写 method/check。所有可安装子项都按其机制与来源 schema 校验，包括未被选中的子项。依赖名称语法和列表内重复在所有子项校验；依赖存在性、环境可用性和循环仅对选择后的图校验，未选中方式的依赖不进入计划或 profile 依赖闭包。计划的 `depends_on` 保留完整选中图用于验证和排序，`install_depends_on` 记录其中仅安装时需要的边。观察到目标已有时，profile 闭包排除这些边；公共边及被 profile 独立选中的项目仍保留。先观察根项目，再按需观察依赖，未引入的安装工具不会执行发现查询。子 section 不写 `install_depends_on`，使用其已有的 `depends_on`。

`preferred_method` 必须在 methods 中，且是本平台支持的可执行安装机制。`manual` 只声明发现路径，不能带安装参数、声明方式级依赖或作为优先方式。每个子项至少提供一个发现路径。不自动推断包名对应的文件位置。

发现时，同一方式的全部路径必须满足条件；任一方式满足就跳过安装。多个方式都满足时，按 methods 声明顺序报告首个匹配方式。都不存在时，仅执行 preferred_method 的安装参数，不在失败后自动切换方式。`methods` 的顺序仅用于发现结果的确定性，不是安装失败回退顺序。

路径格式为 `根:相对路径`，多个路径用 `;` 分隔，路径中可含空格。根与平台/类型约束由 `install/schema/discovery-roots.tsv` 共享声明。支持的根：

- `home`：当前用户目录；所有平台可用。
- `path`：逐个检查 PATH 的非空目录，只支持单个文件名，必须显式写 Windows 扩展名；忽略空 PATH 项。
- `root`：Unix `/`；`brew_prefix`：macOS 当前上下文的 Homebrew 前缀；`applications`：macOS `/Applications`。
- `program_files`、`program_files_x86`、`local_app_data`：Windows 对应目录；program_files 优先使用显式运行上下文。

不执行变量展开、通配符或 shell 表达式；拒绝绝对路径、空段、`.` / `..`、反斜杠和保留分隔符。缺失的根目录值不匹配。符号链接按最终目标类型判断，断链不匹配。

该机制**只检查文件/目录存在性及类型**，不要求文件可执行，不运行版本命令，不查询包数据库，不验证应用完整性、版本或服务状态。匹配方式只是路径证据，不是包管理器所有权证明。声明路径的作者负责选择合适的证据。

普通预检、packages 阶段重建计划和手动续跑使用同一发现函数；声明发现路径后不再调用该项旧的 check、包清单或专用存在性探测。离线 plan 不检查文件系统，仍显示优先安装方式。`discovery` 是 parser 生成的计划字段；`detected_method`、`detected_paths`、`decision_reason` 是观察/决策字段，均不能直接写入配置。

### 探测与执行策略

普通运行根据当前声明和 profile 构建计划，在 packages 准备前与准备后重新检查；仅对待安装机制执行必要准备。普通运行与续跑都通过当前包清单跳过已有项。续跑会在执行每项前进一步检查当前安装状态。没有发现声明或内置查询的项（例如任意自定义脚本）按原机制重跑，不因历史成功就跳过。查询命令缺失视为无证据，已执行的查询发生非约定缺失码、超时或中断则失败；文件发现的访问错误也失败。内置查询覆盖包清单、pipx、Rust 工具链及声明组件、Xcode/Homebrew 和 Windows 安装机制，不检查版本、服务运行或健康。

[probes.tsv](../install/schema/probes.tsv) 将状态映射为动作；默认决策仅安装或跳过，历史 `upgrade` 观察也按已存在处理。发现查询异常、超时和中断不能当作不存在。安装命令正常退出即成功，不追加安装后存在性复核。`check` 不能替换成服务健康检查。

[execution.tsv](../install/schema/execution.tsv) 的四列是 `method`、`operation`、`timeout_seconds`、`success_codes`。`*` 为默认值，特定机制可覆盖对应操作：

- `probe` 默认 30 秒；`download` 默认 120 秒，用于 Homebrew 脚本获取。
- `install` / `modify` 默认 0，表示不设固定截止时间。流式下载并执行的 script 整条管道使用 install 策略。
- 默认成功码为 `0`；MSVC modify 接受 `0,3010`，不会扩展到普通 WinGet 安装。
- timeout 是规范十进制 0..86400；成功码是去重的逗号列表，0..65535 且包含 0。124/130/143 不能当作成功；probe/download 只能接受 0。
- 四类默认操作必须齐全，不允许重复行或未注册机制。当前不支持安装项级策略字段。

## Apply 项

| 字段 | 语义 |
| --- | --- |
| `source` | 必填，相对仓库根目录的文件或目录 |
| `target_root` | 必填；Unix 必须是 `config_home`，Windows 必须是 `local_app_data` |
| `target` | 必填，相对上述根目录的目标 |
| `method` | 必填；Unix 支持 hardlink/copy，Windows 只支持 copy |
| `exclude` | 可选；相对 source 目录的路径，以 `;` 分隔。精确路径及其子树排除，不是 glob |

`source`、`target` 和排除路径使用 `/`，不能是绝对路径，不能含 `.`、`..`、空路径段、冒号或反斜杠。文件 source 不能配 exclude。源路径及遍历到的未排除源文件不能是符号链接。

`condition=linux-kde` 是可选的 Unix 环境条件，不满足时明确跳过。`renderer=desktop-fonts` 仅支持 Unix、linux-kde、hardlink 组合：除常规 source/target 映射外，为当前配置根下的 kdeglobals、gtk-3.0/settings.ini、gtk-4.0/settings.ini 渲染 copy 候选计划。这是固定处理器，不是任意命令；不接受自定义渲染目标。Windows 不接受这两个字段。

例如 Fish 声明使用 `source=configs/fish`、`target=fish`；source 仍相对仓库根，不相对 configs 根。

Unix 目标根为 `${XDG_CONFIG_HOME:-$HOME/.config}`；Windows 为 `LOCALAPPDATA`。组件 ID 按声明选择，单独 apply 未传组件时选择该平台全部组件。profile 的组件列表只约束安装 workflow，不会过滤单独 apply。

目录部署逐文件处理，未在源中列出的目标文件保留；不执行删除同步。声明目标与仓库、备份及其他组件目标不能重叠。计划动作有 mkdir、hardlink、copy、skip；具体文件系统限制见 [apply](../apply/README.md)。

## Workflow profile

无 section，以下六个字段全部必填；`schema_version` 只在这里是用户声明字段。

| 字段 | 语义 |
| --- | --- |
| `schema_version=1` | 当前唯一版本，未知/缺失版本拒绝 |
| `install` | `all` 或空格分隔安装项 ID；显式选择自动补齐传递依赖 |
| `components` | 空格分隔 `apply-id:install-id`，同一 apply-id 不能重复；所需安装项必须在所选计划且未被环境排除 |
| `shell` | `fish` 或 `none` |
| `mirrors` | `initialize` 或 `none` |
| `wsl` | `none` 或 WSL 分发名 |

`components` 不能留空；想只安装软件，应使用阶段选择参数而非生成空 profile。Unix 要求 `wsl=none`；Windows 要求 `shell=none`、`mirrors=none`，其 WSL guest 负责 Unix 初始化。

入口自动选择 linux、wsl、macos 或 windows profile；当前没有 `--profile` 参数。新增任意 profile 文件不会自动成为可选入口。macOS 的 Git 配置关联 `xcode-command-line-tools`，因为其提供 Git；不要求 component 和 install ID 同名。

阶段注册表 [stages.tsv](../workflow/schema/stages.tsv) 定义平台、顺序、ID、gate、preflight、action；它属于执行框架，不是新增软件的修改点。处理器是允许列表中的标识符，不是命令串。

## 镜像声明

`mirrors/current.conf` 必须包含全部已支持 key，不能重复或增加未知 key。值是字面量，禁止空格、引号、反斜杠和记录分隔符。`go_sumdb` 是域名形式，其余值以 `http://`、`https://` 或 `sparse+https://` 开头；实际目标仍需符合各工具格式。

| 键 | 用途 |
| --- | --- |
| `rust_dist`、`rust_update` | Rust 下载环境变量 |
| `pypi` | PIP_INDEX_URL |
| `cargo_index` | Cargo 受管理 registry |
| `npm` | npm registry |
| `go_proxy`、`go_sumdb` | Go 代理与校验数据库 |
| `brew_git`、`brew_core`、`brew_cask` | Homebrew Git 来源环境 |
| `brew_bottles`、`brew_api` | Homebrew 下载/API 环境 |
| `ubuntu`、`ubuntu_ports`、`debian`、`debian_security` | 可识别的 APT 系统源 |
| `fedora` | Fedora 官方 repo 的替换端点 |
| `arch`、`manjaro` | Pacman mirrorlist 管理端点 |

切换镜像只改 current.conf；`legacy.conf` 是历史所有权识别依据，不能同步改为新端点。用户状态文件也不能当作输入模板手工改写。详见 [镜像生命周期](../mirrors/README.md)。

## 运行环境输入

这些变量用于定位当前主机路径或传递运行上下文，不写进安装项/组件声明来代替相对路径。

| 变量 | 使用位置与含义 |
| --- | --- |
| `HOME`、`XDG_CONFIG_HOME` | Unix 用户目录与配置根；XDG 未设置时使用 `$HOME/.config` |
| `LOCALAPPDATA` | Windows apply 根 |
| `DOTFILES_BACKUP_DIR` | 安装/部署会话的备份父目录 |
| `DOTFILES_MIRROR_CONFIG` | Unix 镜像配置默认文件；显式 mirror/apply 参数可替代 |
| `DOTFILES_WORKFLOW_SESSION_ID` | Unix 入口的默认会话 ID；显式 `--session-id` 优先 |
| `CARGO_HOME` | Cargo 配置位置；未设置时为 `$HOME/.cargo` |
| `CARGO_TARGET_DIR` | Cargo 安装编译缓存；未设置时使用 XDG cache 下的 dotfiles/cargo-install |
| `NPM_CONFIG_USERCONFIG` | npm 用户配置路径；未设置时使用 `$HOME/.npmrc` |
| `DOTFILES_DEPLOYMENT_LOCK` | 协作写入者共用的锁路径，不用于绕过活动锁 |
| `DOTFILES_DEPLOYMENT_TOKEN` | 嵌套流程自动传递的所有权 token，不应为独立运行手工设置 |

应用自身的环境变量（例如 `DOTFILES_NO_ZELLIJ`）见 [应用配置](applications.md)，验证工具选择变量见 [测试文档](../tests/README.md)。改变环境路径后预检和计划以该次调用的实际环境为准，旧报告不会固定这些路径。

## 应用与附属服务

应用文件语义见 [应用配置](applications.md)。Windows Terminal 文件是 JSONC，不能直接用不支持注释的 JSON parser 判断其无效。这些文件不能套用 install/apply 的 key=value 规则。

### 声明兼容与标准计划

旧 `scope=desktop` 在读取入口转换为 `environments=native`；未声明环境时显式填入
`native wsl`。因此旧桌面项在 WSL 的跳过原因统一为 `environment-not-selected:wsl`。
旧 `check` 转换为内部 `probe_command`，保留 Unix 执行 `--version`、Windows 仅查找命令的
原有行为。核心计划不再包含 `scope` 或 `check`；`probe_command` 不能写入声明。
单方式项也显式填入 `methods` 和 `preferred_method`，使后续阶段只处理一种标准结构。
新声明仍应使用文件系统发现；此兼容不增加版本、运行状态或服务健康保证。

### 发现结果与报告解释

发现证据随计划保存，执行报告分别记录首选方式、匹配方式、命中路径和决策原因。
`detected_paths` 是 JSON 路径数组，空字段表示没有匹配证据；离线计划不会声称文件存在。
普通执行使用该次计划的观察，人工续跑重新检查并替换证据；检查失败或被阻塞的项不会沿用旧证据。
执行失败时仍能区分原始选择原因与最终退出原因。状态命令会展示跳过项及其证据，无需解析日志。
字段版本、历史只读兼容与路径语义见 [契约说明](../contracts/README.md)。
