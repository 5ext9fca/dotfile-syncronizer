# 配置应用与受保护恢复

配置内容来自快照，不再来自项目中的应用文件。只应用配置：

```bash
./apply/apply.sh --snapshot /path/to/snapshot.zip --dry-run
./apply/apply.sh --snapshot /path/to/snapshot.zip
./apply/apply.sh --restore /path/to/session/configuration/journal.tsv --plan
./apply/apply.sh --restore /path/to/session/configuration/journal.tsv
```

```powershell
.\apply\windows.ps1 -Snapshot C:\Snapshots\settings.zip -DryRun
.\apply\windows.ps1 -Snapshot C:\Snapshots\settings.zip
.\apply\windows.ps1 -Restore C:\Backups\session\configuration\journal.jsonl -DryRun
```

`--plan` / `-PlanOnly` 等价非变更预览。必须选择快照或 journal，二者互斥；旧组件选择、profile、结果路径和嵌入式镜像参数已移除。完整安装加恢复使用 [snapshot restore](../snapshot/README.md)。镜像更新使用独立 `apply/mirrors.sh`。

所有快照配置使用复制。相同内容跳过，冲突文件或目录先备份，目标额外文件保留。未排除的目标符号链接/重解析路径在快照预检中拒绝；先由操作者处理，再重试。源快照保持独立，不受应用修改影响。

真实操作在 `${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backups}` 创建会话及配置 journal；Windows 使用对应用户目录。每项记录 prepared/applied 等状态。失败时尝试恢复当前操作；之前成功项保留，之后操作阻断，不是全流程回滚。

journal 恢复按反向顺序执行并校验目标/备份身份和内容，用户后续修改、缺失备份或目录新增未跟踪内容会阻止恢复。旧版本产生的有效 journal 仍受支持，不可手工伪造记录。恢复不卸载包、不改登录 shell；已有旧硬链接的恢复逻辑保留。

快照应用与完整安装、镜像、journal 恢复共用部署锁。异常退出留下的锁不自动清理；查看 owner，确认所有相关写入已停止后再人工处理。
