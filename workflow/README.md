# 工作流与会话

普通安装入口只执行 packages 阶段，按 Viewer 提供的 `workflow/profiles/<name>.conf` 的 v3 软件集合选择安装规则。快照 restore 执行 packages → configuration，apply 快照仅执行 configuration；不自动改 shell、初始化持久镜像或调度 WSL。

## 预览与执行

```bash
./install/macos.sh --profile macos-full --dry-run
./install/linux.sh --profile linux-full --plan
./install/linux.sh --profile linux-full --yes
./snapshot/snapshot.sh restore --snapshot /path/to/snapshot.zip --dry-run
```

安装入口保留 `--only-stage packages`、`--from-stage packages`，不再接受旧配置、镜像、shell、WSL 阶段名。Windows 使用对应 PascalCase 参数。

安装始终先探测当前存在性，已存在时跳过；否则执行安装命令并以接受的退出码判成功。不做安装后探测或服务健康检查。允许安装失败，操作者处理原因后重跑。

## 报告与失败

真实操作保存独立会话；普通安装 dry-run 只有显式指定 results 才持久保存，快照 dry-run 不保存持久会话。摘要使用 Unix workflow.tsv 或 Windows workflow.json；stage-result 关联详细结果和配置恢复 journal，单文件原子发布。

```bash
bash workflow/status.sh /path/to/session
./install/macos.sh --resume /path/to/installation-session --plan
./install/macos.sh --resume /path/to/installation-session
```

```powershell
.\workflow\status.ps1 -Session C:\Backups\session
.\install\windows.ps1 -Resume C:\Backups\installation-session -DryRun
```

只有新普通安装 request v3 会话可以续跑；续跑读取当前声明并重新探测，不因旧报告成功而跳过。旧 request v2 会话仍可查看，必须重新启动安装；历史 journal 恢复命令已移除，既有资料保留。

快照会话使用归档声明，不接受安装入口 resume。解决失败原因后重新执行同一归档的 restore。输出包含 workflow 会话路径及 Viewer 配置结果；失败后查看备份资料并人工处理，不再提供 journal 恢复命令。

## 部署锁

真实安装、采集、恢复、apply 和镜像变更共享用户级部署租约，嵌套调用保留 owner；非变更预览不获取锁。锁不能阻止应用自己修改文件，所以采集前仍须停止配置写入。

异常退出的锁不自动回收。检查 owner，确认相关写入进程已停止后再人工处理，不依据 PID 消失自动删除。既有命令终端输入、超时和取消合同保持不变。
