# 计划与报告契约

[schema/types.tsv](schema/types.tsv) 定义类型和版本；同目录 `<kind>.fields` 定义列集合。`dotfiles_core/contracts.py` 统一读写，Bash 与 PowerShell 通过 `lib/data-contract.sh` / `.ps1` 薄包装调用，不能自行维护另一份字段顺序。

## 文本封套

```text
# dotfiles|install-result|2
id|status|elapsed_seconds|reason|selected_method|detected_method|detected_paths|decision_reason
docker|skipped|0|discovered-installation|cask|manual|["/Applications/Docker.app"]|discovered-installation
```

第一行是类型和版本，第二行是列名。读取器接受列重排并归一化，拒绝未知版本、缺失/重复/未知列或错误列数。空结果也需要两行头部。值不能含 `|`、Tab、CR/LF，空格和逗号是普通内容。

封套读取器验证形状，领域语义仍由 install/apply/stage reader 验证。写入前验证完整文档，再原子替换单个文件。不要将“字段合法”理解为可以任意执行其中的数据。

## 类型

| kind | 用途 |
| --- | --- |
| install-plan | 安装声明、动作、原因、来源、探测状态 |
| apply-plan | 文件操作、目标、备份、前置状态和原因 |
| install-result | 安装项状态、耗时、执行原因、首选方式与发现证据 |
| apply-result | 文件操作结果 |
| git-result | Git 设置结果 |
| stage-result | 阶段状态与显式 artifact 引用 |
| command-result | 原生命令策略、状态、退出码、耗时和输出路径 |
| workflow-request | 保存阶段选择、镜像模式和父会话，供人工续跑 |
| workflow-summary | Unix 摘要读取的规范列定义 |

install-plan 当前版本为 7：包含归一化的环境、方式与 `probe_command`，包含字体文件列表 `font_files` 和下载校验 family `font_family`，以及安装专用依赖 `install_depends_on`、`detected_method`、`detected_paths`、`decision_reason`；不再包含旧声明字段 `scope`、`check`。install-result 和 workflow-request 当前版本为 2；其他契约版本仍为 1，以 schema 为准。内部 install 计划行带 `schema_version=7`，apply 计划行带 `schema_version=1`，执行器在 dispatch 前拒绝不支持的版本。不接受旧的无封套 plan/detail report，也没有持久计划重放接口。

`dotfiles_core/contracts.py` 为状态查询提供显式 install-result v1 只读兼容适配，按历史 schema 校验后补空的新字段。它不推测历史证据，不改写历史文件，不让通用契约读取器或执行器接受旧计划。未知版本和坏列仍拒绝。

`selected_method` 是计划中的首选安装方式，即使因其他方式的文件证据而跳过也保持原值，不表示实际执行过该方式。`detected_method` 是首个满足全部声明路径的方式；`detected_paths` 是本次检查命中的绝对路径组成的 JSON 字符串数组，顺序为该方式声明的文件路径、目录路径。空字段表示没有命中证据；PATH 根保存第一个命中的非空 PATH 目录中的路径。路径按检查入口记录，不解析成符号链接最终目标；不是包管理器所有权、版本或完整性证明。JSON 转义保护路径内的特殊字符和外层 `|` 分隔符，消费者应解析 JSON，不按逗号或分号拆路径。

`decision_reason` 保存动作选择原因，即使执行失败后 `reason` 变为退出码仍保留：离线规划为 `offline-preferred-method`；检查后所有方式都不匹配为 `no-discovery-match`；匹配、环境排除和其他机制使用对应决策原因。正在重新检查、检查失败或被前序失败阻塞的项不发布旧发现证据和旧决策原因。成功执行安装不会自动补造发现证据或追加健康检查。

平台安装器的 workflow plan 同时显示人类说明和各阶段计划；独立 `install/plan.*` 默认输出纯 install-plan，`apply --plan/-PlanOnly` 输出 apply-plan。恢复预览走恢复接口，不是普通 apply-plan。

## Workflow 特殊格式

Unix 摘要 `workflow.tsv` 使用带列名的 `|` 分隔文本，文件自身没有上面的封套；读取器在内部补 workflow-summary 封套。Windows 摘要是 `workflow.json`，字段语义由 [report-fields.tsv](../workflow/schema/report-fields.tsv) 定义。不要因文件扩展名为 `.tsv` 就假定 Tab 分隔。

报告使用 UTF-8；Windows PowerShell 5.1 的状态读取器也显式按 UTF-8 读取，保留中文路径，并逐项处理 JSON 摘要数组。

每个执行阶段的 `<stage>.result` 是 key/value 封套：stage、status、exit_code、retry_stage、reason、report 各一次，recovery_journal/child_report 可重复。重复 key 每条保存一个路径，不把逗号当数组分隔符。日志中的自然语言不具有机器契约含义。

状态读取优先使用合法 stage-result，并补充请求中尚未出现的阶段。无效 stage-result 不能把阶段变成成功；中断留下的 running 只表示未完成。旧摘要的逗号拼接引用仅供兼容展示。

恢复 journal 继续使用 apply 自己的版本化事务格式。不要将 journal、summary、request 或普通安装项配置互换。

## 命令与退出码

`lib/command.*` 接收显式 mutation/probe 策略和参数数组，支持 dry-run、继承终端或捕获输出。显式下载脚本仍通过其声明 shell 执行，这是安装机制，不是配置 reader 执行任意表达式。

Windows PowerShell 5.1 使用兼容的参数序列化：空参数、空白和引号按 Windows 转义规则处理，普通参数不额外加引号，确保 WSL 能正确识别 `--list` 等开关。

机制 timeout 和额外成功码来自 [execution.tsv](../install/schema/execution.tsv)。原生命令保留退出码；124 表示超时，130/143 表示中断。安装 adapter 将声明的额外成功码归一为成功，例如 MSVC modify 的 3010。具体 stage/item 分类由 [outcomes.tsv](../workflow/schema/outcomes.tsv) 决定。

Bash capture 目录包含 stdout、stderr 和 command.result；PowerShell 返回含对应结果的对象。取消/超时沿用现有进程组或进程树清理方式，不扩展为服务监管或跨 WSL 生命周期保证。

## 维护

新增字段或版本时同时检查两端 reader/writer、消费者和共享夹具；不要只改 Markdown 或单个输出点。配置生成任务通常不需要修改 contracts。原子发布只保证单文件快照，不保证多份报告同时更新或断电落盘。完整边界见 [架构文档](../docs/architecture.md)。

核心/原生临时 JSON 协议版本独立于持久数据契约。其请求只在当前调用中有效；不是保存计划、重放或迁移会话格式。安装计划仍为 v7，普通安装续跑请求为 v3，v2 仅可查看。

## 配置快照

ZIP manifest v1 由 `dotfiles_core/snapshot.py` 定义，独立于上述执行计划和报告。保存软件声明副本、平台及配置内容摘要；详见 [快照](../snapshot/README.md)。普通安装 request v3 支持续跑，v2 仅可查看。快照会话必须使用原归档重新 restore，不能交给安装入口 resume。
