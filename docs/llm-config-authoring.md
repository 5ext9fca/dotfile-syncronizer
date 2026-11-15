# 面向 LLM 的配置生成指南

本文件用于指导代码代理在本仓库新增或修改配置。目标是生成当前 parser/handler 真正支持、能预览和验证的声明，而不是设计一套新格式。先阅读 [AGENTS.md](../AGENTS.md)、[配置语义](configuration.md) 和相关 schema；代码与 schema 是字段、平台和行为的最终依据。

## 任务输入与输出

生成前明确：应用/组件名称、目标平台、native/WSL 范围、安装方式、包 ID 或下载源、依赖、是否有需部署的配置、目标位置，以及用户是否要求修改 profile。能从当前文件确认的内容直接复用；无法确认的软件包 ID、下载地址或目标路径列为待核实，不编造默认值。

完成后输出：

1. 新增/修改文件及每个文件的职责。
2. 平台矩阵：安装方法、包/来源、依赖、环境；未支持平台明确说明。
3. 是否改变默认 install/profile/component 选择、镜像、登录 shell 或备份行为。
4. 实际执行的验证命令和结果；区分“schema 接受”与“包/远程源实际可用”。
5. 未覆盖的平台和必须由用户完成的外部前提。不要声称未运行的原生测试通过。

保留用户未要求修改的配置。不要通过运行真实安装来校验生成结果；使用离线 plan、隔离测试和相应主机的 dry-run。

## 先选择正确层级

| 用户意图 | 优先修改 | 通常不用修改 |
| --- | --- | --- |
| 增加一种软件 | `install/items/<id>.conf` | 平台入口、阶段表、报告契约 |
| 部署新应用的文件 | `configs/<应用>/` + `apply/items/<id>.conf` | 直接在入口追加 ln/cp |
| 改安装集合/组件关联 | `workflow/profiles/*.conf` | handler 或任意新 CLI 参数 |
| 换镜像 | `mirrors/current.conf` 或安装项 URL 来源 | `legacy.conf`、用户 mirror-state |
| 改已有应用行为 | 该应用的原生配置文件 | install/apply schema |

只有现有方法不能表达明确需求时，才考虑扩展 schema、handler 和两端测试；不能偷偷向 `.conf` 添加不支持的字段或把命令串塞进 method。

## 新增安装项：执行步骤

1. 查看 `install/schema/fields.tsv`、`methods.tsv`、`sources.tsv`，并阅读目标方法的 handler。寻找同方法的现有项作为参考，不只按同类软件复制。
2. 确定未使用的 ID，文件名使用 `[a-z0-9][a-z0-9-]*.conf`；一个软件一个文件。
3. 为实际支持的平台写独立 section。Linux 分别用 linux.apt/linux.dnf/linux.pacman；macos/windows 独立。省略不支持平台，不生成空 section，不生成 `[default]` 或 `[wsl]`。
4. 每个 section 写 order、method、source_kind，以及机制和来源要求的所有字段。不要从前一个 section 隐式继承值。
5. 明确依赖：例如 brew/cask 需要 homebrew，编译型 Cargo 项通常需要 rust-toolchain；依赖以现有声明和 handler 的实际命令为准，不只照抄这些例子。
6. 公共依赖写 `depends_on`；仅安装过程使用的工具写 `install_depends_on`（单方式）或方式子 section 的 `depends_on`。两类依赖都必须在同一平台存在、没有重复/环且环境兼容。order 只能排序已满足依赖的项，不能代替依赖边。
7. 如需 native-only，使用 `environments=native`；不要再混用 scope。新增 capability/provider 需要有明确安装所有权语义，并同步注册表；不因“运行时能力”引入服务探测。
8. 校验整个候选文件集合的五个平台。解析成功不能证明远程包名或 URL 可用；新增来源须核实其权威发布信息或现有仓库依据。

以下是现有 [ripgrep.conf](../install/items/ripgrep.conf) 的两个 section，用于说明结构；它已经存在，不要再新建一个重复安装 ripgrep 的 ID：

```ini
[linux.apt]
order=20
method=apt
packages=ripgrep
source_kind=default

[macos]
order=20
method=brew
packages=ripgrep
source_kind=default
install_depends_on=homebrew
```

涉及特殊机制时优先阅读这些真实声明：

| 需求 | 参考文件 | 注意 |
| --- | --- | --- |
| 下载字体 | [隔离下载夹具](../tests/fixtures/install/font-download/sample.conf) | font-download 只接收 HTTPS 基础目录和受限 font_files、font_family；整组 detect_files，Fontconfig/curl 依赖，native-only |
| 下载脚本 | [codex.conf](../install/items/codex.conf) | shell/env 是受限字段，不是任意 shell 代码 |
| 自定义 APT 仓库 / COPR | [wezterm.conf](../install/items/wezterm.conf) | 方法与来源必须配对；APT 密钥字段不可省略 |
| 工具链组件 | [rust-toolchain.conf](../install/items/rust-toolchain.conf) | components 与 workflow components 不是同一语义 |
| 官方 Docker CE 仓库 | [docker.conf](../install/items/docker.conf) | `docker-ce` 只支持 Debian/Ubuntu 和 Fedora/CentOS/RHEL，host facts 由 Linux 入口传入 |
| Windows/WSL 所有权 | [docker.conf](../install/items/docker.conf) | WSL provider 声明不代表 Docker Desktop 已启动 |
| MSVC | [msvc.conf](../install/items/msvc.conf) | workload/component；3010 成功码来自执行策略，不写进安装项 |

应用存在性应使用 `detect_files` / `detect_dirs`，不新增版本命令 `check`。路径格式是 `根:相对路径`，多个条件用分号分隔；只按文件/目录存在性判断，不假设版本或完整性。优先复用实测路径；不根据包名臆测安装位置。

声明多种方式时，在平台 section 写 `methods` 和 `preferred_method`，并为每种方式提供 `[平台/方式]` 子 section；公共字段和路径根规则见 [应用发现](configuration.md#多种安装方式与应用发现)。每个可安装子项单独满足该机制的必填来源/包字段，并至少声明一个发现路径。manual 只用于发现外部安装，不能作为 preferred_method。任一方式存在即跳过；全部缺失只执行优先方式。不要把方法列表当作失败后依次重试的队列。`discovery` 是生成字段，禁止手写。

不要在安装项写 `schema_version`、`enabled`、`version`、`timeout`、`command` 或 `post_install`。不要添加未知 key 期待被忽略。`packages`/`args` 不支持 shell 引号分组；`env` 只有一个 NAME=value。URL 值不加引号，只有 cargo-index 接受 sparse+https。

## 新增 apply 配置：执行步骤

1. 将源文件放在 `configs/` 下所属应用目录，例如 `configs/fish/conf.d/40-example.fish`。新增应用才创建新的应用目录；目录名不等于自动部署。
2. 新建 `apply/items/<id>.conf`，使用 `[unix]` 或 `[windows]`；核对 `apply/schema/fields.tsv`。
3. source 从仓库根定位，例如 `configs/fish`，不从 configs 根定位；target 从声明的 target_root 定位。路径一律用 `/`，不写 `$HOME`、`~`、绝对路径、反斜杠或点段。
4. Unix 通常选择 hardlink/config_home；明确需要复制才用 copy。Windows 只能 copy/local_app_data。
5. 目录中有运行时状态时加 exclude。它是 `;` 分隔的精确相对路径及子树，不是 `*.cache` 这样的 glob。文件 source 不配 exclude。
6. 检查 source 确实存在，目标不与其他组件或仓库/备份重叠，未排除 source 不是 symlink。hardlink 需要同文件系统。
7. 若要加入完整安装流程，修改相应 `*-full` profile 的 `components=apply-id:install-id`，并确保 install 选择包含所需项。不要仅新增 apply 文件就宣称 workflow 会自动选择它。

以下为现有 Fish 声明；不要将 fish_variables 加回受托管文件：

```ini
[unix]
source=configs/fish
target_root=config_home
target=fish
method=hardlink
exclude=fish_variables
```

Windows Terminal 示例见 [windows-terminal.conf](../apply/items/windows-terminal.conf)。其源 `settings.json` 是 JSONC，copy 会替换整份目标，不做字段合并。

## 修改 profile 或镜像

profile v2 必须包含 schema_version/install/components/shell/mirrors/wsl/wsl_profile 七个字段。`install=none` 表示不安装；`components=none` 表示不部署。无安装关联时写 `components=apply-id`，有依赖时写 `apply-id:install-id`。`install=all` 包含全部平台安装项；显式列表自动补依赖。默认方案保持纯配置，完整环境写入 `*-full`。

```ini
schema_version=2
install=all
components=windows-terminal:windows-terminal
shell=none
mirrors=initialize
wsl=FedoraLinux-44
wsl_profile=wsl-full
```

这是 `windows-full` 的结构。新方案可通过 `--profile NAME` / `-Profile NAME` 选择，名称仅含小写字母、数字和连字符且以字母开头。wsl 和 wsl_profile 必须同时启用；自定义已有 WSL2 分发必须提供对应 guest profile，checkout 必须位于该分发内。不要生成自动创建分发的命令。apply 只使用组件，不继承其余行为。

新增目标根时选择已支持的根：Unix home/config_home，Windows home/app_data/local_app_data；例如 `.zshrc` 或 `.gitconfig` 使用 home，漫游设置使用 app_data。不要把整个 home 视为禁止保存报告的范围；只保护具体托管目标及现有仓库/备份路径。桌面字体 renderer 仍限定 config_home。用隔离根验证缺失变量、跨根重叠、备份和恢复。

镜像配置从完整 `mirrors/current.conf` 复制后只改需要的端点，不生成“只含变化 key”的文件。不得修改 legacy 以切换当前镜像；不得生成 mirror-state 或恢复 journal。安装项 mirror_url 与持久镜像 key 各自管理，不推断不存在的自动关联。

## 应用原生配置

保留原生格式和现有组织：Fish conf.d 使用数字前缀，Helix TOML、WezTerm Lua、Zellij KDL、Windows Terminal JSONC 均交给相应格式/应用校验。生成 Lua/Fish 等可执行配置时，其代码能力不意味着 install `.conf` 同样可执行。

## 验证顺序

先离线验证候选安装集合；`--items` 指向包含完整依赖文件的目录，不只指向孤立的新文件：

```bash
(
  set -eu
  candidate_dir="$(mktemp -d)"
  trap 'rm -rf -- "$candidate_dir"' EXIT
  cp install/items/*.conf "$candidate_dir/"
  # 将候选的新/修改声明写入 candidate_dir，暂不执行安装。
  for platform in linux.apt linux.dnf linux.pacman macos windows; do
    ./install/plan.sh --items "$candidate_dir" --platform "$platform" > /dev/null || exit "$?"
  done
)
```

该子 shell 遇到解析失败即返回非零，并清理临时目录；验证结果不能被清理命令覆盖。该示例只解析现有集合，新增文件由生成任务写入注释指定的位置。

随后运行相关 schema/契约测试，再按当前主机预览：

```bash
bash tests/install-items.sh
bash tests/apply-schema.sh
bash tests/workflow-schema.sh
./install/linux.sh --plan
./install/linux.sh --dry-run --yes
./apply/apply.sh --plan --no-mirrors
```

```powershell
./tests/install-items.ps1
./tests/apply-schema.ps1
./tests/workflow-schema.ps1
./install/windows.ps1 -PlanOnly
./apply/windows.ps1 -PlanOnly
```

上面 Linux/Windows 命令只在适用主机执行；macOS 使用 `install/macos.sh --dry-run`。Windows 完整预览仍要求正确 WSL checkout，不能用 PowerShell 在 Linux 上解析成功来替代它。改变共享解析/执行代码时，按 [tests](../tests/README.md) 补两端回归；纯声明优先验证解析、选择、依赖和 dry-run。

## 交付前自检

- 所有 key 均由当前 schema/方法允许；必填字段齐全，没有虚构平台或 CLI 参数。
- 文件名 ID、依赖、环境、provider、component 关联一致；未支持的平台明确省略。
- 未生成机器绝对路径或将运行产物当配置模板；没有把未知用户文件纳入破坏性同步。
- 未扩大版本锁定、回滚、强制打断、持久性或服务健康范围。
- 例子是结构示例还是可直接执行的文件已标注；校验结果与未验证内容如实报告。

方式级依赖：公共 section 的 `depends_on` 表示所有方式共享的依赖；可安装方式子项的
`depends_on` 仅在该方式为 `preferred_method` 时合入静态图；目标已发现时，不通过此边引入依赖。profile 独立选中的依赖仍处理。不要把方式专用的安装工具放入公共依赖。
两层相同依赖合并一次，同一列表内部重复仍无效；`manual` 子项不能声明依赖。
切换首选方式后重新生成并验证计划及 profile 闭包，确认依赖缺失、环境约束和循环均通过。

### 桌面字体声明

修改字体下载先用 `fc-scan` 核对样本 family、字重和字符覆盖，不执行第三方脚本、不提交字体二进制。下载项必须声明 `font_family`，维护 `font_files` 与整组 `detect_files` 的一致性，目标目录按安装项 ID 固定；不要增加自定义路径字段、镜像、版本锁定或安装后验证。

`desktop-fonts` 的 Fontconfig 源仍是应用原生 XML；`condition=linux-kde` 和 `renderer=desktop-fonts` 是新增的受限 apply 字段。修改前阅读 `lib/desktop-fonts.sh` 与 `apply/renderers/desktop-fonts.py`，使用临时 KDE/GTK 配置验证保留用户设置、重复 apply、备份与恢复。不要向 Fish/Helix/Zellij 添加终端字体字段，不修改 WezTerm 的既有回退链，也不要把中文通配替换规则用于所有字体请求。

桌面正文与等宽字体读取 Fontconfig XML 的 `system-ui`、`monospace` 首选 family，预检读取全部顶层 alias 的 prefer/accept family。默认正文为 Noto Sans CJK SC，不再提供苹方下载项。改 family 时同步核对安装项与 profile 关联；不要在处理器另写一份字体列表。下载夹具中的 example.org 仅用于测试，不是实际字体来源。
