# JEL DEV — JerEx Launcher Development

这是 JEL 的开发与调试副本，用于验证 ChatGPT 发现、代理选择、配置写入和启动后检查。它不是面向普通用户的发布包。

JEL DEV 会访问与稳定版相同的 ChatGPT 配置目录，但使用独立的日志目录和单实例锁。

当前开发版本：`3.5.0-dev.1`

## 启动

双击 `JEL-launcher.vbs`。

开发版专用入口：双击 `JEL-dev-launcher.vbs`。

## 无副作用诊断

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\JerEx-launcher.ps1 -Profile JEL-dev -DiagnosticOnly
```

也可以直接运行 `JEL-dev-diagnostic.ps1`。

诊断模式不会修改 `.env`，也不会打开或关闭 ChatGPT。诊断日志位于 `%LOCALAPPDATA%\JerEx\JEL-dev\logs`。

## 数据位置

- 程序与可编辑配置：当前目录
- 开发日志：`%LOCALAPPDATA%\JerEx\JEL-dev\logs\JEL.log`
- `.env` 备份：`%USERPROFILE%\.codex\jel-backups`

## 产品边界

JEL 只负责启动与环境验证。项目工作区管理属于 JEM；安装、更新和产品发现属于未来的 JECP。

## 名称说明

用户界面统一使用 `ChatGPT`。Windows 安装包目前仍使用 `OpenAI.Codex` 技术标识，脚本内部保留相关函数名和 `.codex` 路径以保证兼容性，但不会把这些内部名称作为启动提示展示给普通用户。

## 迁移说明

本目录从 C 盘历史备份复制迁移而来。旧目录未删除，可用于回退和版本对照。

旧版 `codex-auto-proxy-env.ps1` 和 `JeredEx-launcher.ps1` 未带入有效入口，避免误用会覆盖整个 `.env` 的旧逻辑。`JeredEx-launcher.vbs` 暂作为兼容别名保留，它与 `JEL-launcher.vbs` 都会调用当前的 `JerEx-launcher.ps1`。
