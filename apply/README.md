# 配置应用

此目录只保留快照应用的命令适配器，文件读取、备份、复制和原子报告由 dotfiles-viewer 负责。

```bash
./apply/apply.sh --snapshot /path/to/v2.zip --dry-run
./apply/apply.sh --snapshot /path/to/v2.zip
```

PowerShell：`./apply/windows.ps1 -Snapshot C:\Snapshots\settings.zip -DryRun`。同平台归档，相同内容跳过，冲突先备份，保留目标额外文件；多硬链接显式使用 --detach-hardlink / -DetachHardlink。

历史 --restore / -Restore 入口已移除，不接受旧 v1 快照。旧备份与 journal 不删除。持久镜像管理仍通过独立 mirrors 入口，内部文件事务仅为该功能保留。
