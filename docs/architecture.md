# 架构

syncronizer 单向依赖 dotfiles-viewer>=0.2,<0.3。Viewer 拥有唯一软件声明、profile、schema、解析与依赖选择，以及配置编辑、快照 v2、文件应用和共享部署锁。此项目的 software/snapshot/install_config 模块只保留兼容导入与安装计划序列化。

本项目保留安装观察、机制 handlers、超时与退出码策略、原生适配器、镜像和安装会话调度。安装成功按命令退出策略，不增加安装后探测。配置应用调用 Viewer API，不再实现第二套快照事务。

组合恢复持有共享锁和 Viewer SnapshotSession，固定归档、预检配置、按归档声明安装，最后重新规划应用。安装失败阻断应用，应用失败不回滚安装。阶段元数据保持现有契约，Viewer 结果作为配置阶段报告。

`--catalog` 或 DOTFILES_CATALOG 决定统一声明来源；临时归档声明目录只属于本次会话。默认目录来自 Viewer 包资源。旧 v1 快照和历史 journal 恢复命令不再支持，旧备份不删除。
