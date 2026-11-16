# 快照兼容入口与组合迁移

快照实现与格式归 dotfiles-viewer。create/inspect 调用 Viewer 的 v2 导出与验证 API，不维护归档副本实现。安装前准备 Python 3.14 和 Viewer 0.2.x。

```bash
./snapshot/snapshot.sh create --profile macos --output /existing/path/settings.zip --dry-run
./snapshot/snapshot.sh inspect --snapshot /existing/path/settings.zip
./snapshot/snapshot.sh restore --snapshot /existing/path/settings.zip --dry-run
./snapshot/snapshot.sh restore --snapshot /existing/path/settings.zip
./snapshot/snapshot.sh restore --snapshot /existing/path/settings.zip --configuration-only
```

支持 --catalog DIR 或 DOTFILES_CATALOG 选择统一声明，PowerShell 使用 -Catalog。导出必须选择 profile 或 software；归档包含安装依赖声明和配置。旧 v1 不兼容，需要重新导出。

restore 固定并验证归档、预检配置，再执行归档中的安装规则，最后让 Viewer 重新规划配置并应用。当前默认目录变化不改变归档内的安装规则。安装失败阻断配置阶段，配置失败不撤销软件安装。

同平台分支、CPU 架构及 native/WSL 环境才可应用。冲突先备份，未知目标文件保留；多硬链接需 --detach-hardlink / -DetachHardlink。共享部署锁覆盖组合运行，子调用继承所有权。没有自动续跑或历史 journal 恢复入口。Viewer 的配置结果会链接到安装会话报告，失败后检查并手动重跑。
