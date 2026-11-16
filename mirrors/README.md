# 镜像配置与生命周期

当前端点声明在 [current.conf](current.conf)，历史识别端点在 [legacy.conf](legacy.conf)。更换端点只编辑 current；legacy 用来识别旧的受管理设置，不能随新镜像一起覆盖。

## 三种行为

| 行为 | 触发位置 | 效果 |
| --- | --- | --- |
| prepare | installer packages 阶段 | 为当前安装进程导出下载环境；不在此阶段统一重写系统包源 |
| initialize | installer mirrors 阶段，或 `apply/mirrors.sh --initialize` | 填充未配置项；已有用户设置按适配器规则保护；可识别官方系统源可转换为当前镜像 |
| apply | 独立 apply 显式 `--china-mirrors`，或 `apply/mirrors.sh` | 将已识别的旧受管理端点更新到 current，保留未知用户设置 |

`--no-china-mirrors` / `-NoChinaMirrors` 跳过安装镜像流程；`apply/apply.sh --no-mirrors` 跳过独立 apply 的镜像。二者都不会删除或撤销已有设置。

## 使用

```bash
./apply/mirrors.sh --plan
./apply/mirrors.sh --dry-run
./apply/mirrors.sh --initialize --dry-run
./apply/mirrors.sh --config /path/to/mirrors.conf --dry-run
./apply/mirrors.sh --results /existing/directory/mirror-result.tsv
```

`DOTFILES_MIRROR_CONFIG` 可为 Unix 入口提供默认配置路径；独立 apply 的显式参数为 `--mirror-config`，mirror 入口为 `--config`。环境变量只描述当前进程，不意味着 Windows host 的声明自动传给 WSL guest。

## 管理目标与保护规则

| 目标 | 行为 |
| --- | --- |
| `$XDG_CONFIG_HOME/fish/conf.d/15-mirrors.fish` | 生成 Fish 环境片段；已存在且无管理标记的文件保留 |
| `$XDG_CONFIG_HOME/dotfiles/mirrors.sh` | 生成供 POSIX shell 显式 source 的文件，不自动改用户 shell 启动文件 |
| `${CARGO_HOME:-$HOME/.cargo}/config.toml` | 新建受管理 registry；已有文件需匹配受管理结构才更新，不覆盖未知 Cargo 配置 |
| `${NPM_CONFIG_USERCONFIG:-$HOME/.npmrc}` | 没有 registry 时追加；更新已识别的管理端点，保留其他 key 和未知 registry |
| `go env GOENV` 指向的文件 | 仅在 Go 可用且路径适用时处理；补充缺失 key，apply 更新已知旧值 |
| APT `.list` / `.sources` | 替换可识别 Ubuntu/Debian 官方源和受管理镜像，不统一重写第三方源 |
| Fedora `fedora.repo` / `fedora-updates.repo` | 处理可识别官方 metalink/baseurl 及受管理端点 |
| Pacman `mirrorlist` | 管理当前 Arch/Manjaro 镜像条目，保留其他 fallback；Manjaro 保留当前 branch |
| `$XDG_CONFIG_HOME/dotfiles/mirror-state.conf` | 保存本次管理端点，供后续识别；不是用户编辑入口 |

未知父符号链接、阻挡目录和非文件目标不会被镜像模块强行接管。只有本次明确选择的应用组件已经计划替换父路径时，才使用其虚拟目录计划。系统源变更经 apply 备份，可能需要 sudo。

initialize 不是“所有已存在文件都不动”：npm/Go 可补缺失 key，系统官方源可转换。apply 也不是“所有 URL 都改成镜像”：所有权识别只针对已知结构、历史端点及保存的管理状态。

## 环境变量与配置语义

[environment.tsv](schema/environment.tsv) 是安装进程和持久环境片段共用的映射：Rust dist/update、PyPI、Go 代理/校验库、Homebrew Git/bottle/API。prepare 另外设置 `HOMEBREW_INSTALL_FROM_API=1`。

Cargo/npm/system 等设置由独立适配器处理。配置必须提供全部支持 key，语法见 [配置语义](../docs/configuration.md)。下载安装项自己的 `mirror_url` 与此处的持久端点是两层声明，不会自动彼此生成。

## 实现边界

`lib/mirrors.sh` 是原生薄包装；`dotfiles_core/mirror_planning.py` 协调目标、所有权与计划组合，`mirror_rules.py` 负责文本规则。原生适配器提供观察，apply 原生事务负责受保护部署；renderer 不直接写目标。

验证使用 `bash tests/mirrors.sh`，包含已有用户配置的保留、初始化、更新和恢复场景。脚本不验证镜像站的长期可用性，也不把下载站或服务健康作为安装成功标准。
