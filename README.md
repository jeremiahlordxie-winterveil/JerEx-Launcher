# JerEx-Launcher
A smart launcher for Windows ChatGPT / Codex to fix reconnecting issues.
你可以直接**一键复制**下方代码框内的所有内容，粘贴到 GitHub 的 `README.md` 中：

```markdown
# 🚀 JEL (JerEx Launcher)

> **告别 Windows ChatGPT / Codex 桌面客户端频繁 `Reconnecting...` 的困扰！**  
> 一键启动 · 智能代理探测 · 自动环境注入 · 丝滑稳定直连

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-blue.svg)](#)
[![Language](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](#)
[![.NET](https://img.shields.io/badge/.NET-8.0-purple.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](#)

---

## 🧐 为什么制作 JEL？

在 Windows 上使用官方 **ChatGPT / Codex** 桌面客户端时，常会遇到以下痛点：

1. **频繁卡在 `Reconnecting...`**：网络握手异常或代理节点被识别，导致客户端不断断线重连。
2. **代理端口变动后失效**：本地代理软件（如 Clash、v2rayN、Mihomo）切换了端口或协议后，ChatGPT 仍在读取旧配置导致离线。
3. **手动修改 `.env` 繁琐且易错**：每次都要寻找 `%USERPROFILE%\.codex\.env` 手动修改 `HTTP_PROXY`，容易格式写错或误删其他变量。

**JEL (JerEx Launcher)** 为此而生！它在客户端启动前自动进行三级网络健康体检，智能选出当前真正可用的本地代理并安全注入配置，保障每一次打开都能稳定直连。

---

## ✨ 核心特性

- ⚡ **智能代理发现**：内置常见代理端口池（7897, 7890, 10808, 10809, 8080 等），支持 HTTP / SOCKS5 自动识别，优先复用上次有效配置，实现毫秒级秒开。
- 🔍 **三级深度连通性验证**：
  - [x] **基础外网连通测试**（`example.com`）
  - [x] **OpenAI 核心 API 连通测试**（`api.openai.com`）
  - [x] **ChatGPT 前端网关握手**（`chatgpt.com`）
- 🛡️ **无损注入与安全备份**：精准正则更新代理变量，完整保留用户的其他自定义配置；更新前自动生成带时间戳的历史备份，杜绝配置损坏。
- 🔄 **进程智能协同**：如果代理配置发生变更且客户端正在运行，会弹出友好提示，由用户确认是否平滑重启以使新配置生效。
- 📦 **绿色免装，随处运行**：**不需要**放到特定的 GPT 安装目录下，放在电脑任意磁盘与文件夹均可自动寻址并拉起应用。

---

## 🛠️ 工作流程

```text
[ 用户双击启动 (VBS / Exe) ]
            │
            ▼
[ 1. 扫描本地代理端口 ] ──► 优先尝试缓存，自动轮询本地监听及常用端口池
            │
            ▼
[ 2. 三级健康检查探测 ] ──► 确保代理真正打通了 OpenAI 与 ChatGPT 的网络链路
            │
            ▼
[ 3. 安全更新环境配置 ] ──► 自动备份旧配置，无损写入 %USERPROFILE%\.codex\.env
            │
            ▼
[ 4. 守护启动客户端 ]   ──► 通过 Windows 官方应用协议拉起并确认进程运行
```

---

## 🚀 快速上手

### 1. 下载与解压
* 从 [Releases](../../releases) 下载最新版本的压缩包并解压。
* 可以将解压后的文件夹存放在电脑上的**任意位置**（例如 `D:\Tools\JEL` 或 `C:\Program Files\JEL`）。

### 2. 日常使用
* 双击运行文件夹内的 **`JEL-launcher.vbs`** 即可。
* **推荐做法**：右键 `JEL-launcher.vbs` ➔ **发送到 ➔ 桌面快捷方式**，将快捷方式重命名为 `ChatGPT`，并设置为文件夹内自带的精美图标 `assets\JerEx.ico`。以后直接双击桌面图标启动即可。

---

## ⚙️ 自定义配置 (`config.json`)

如果你的代理使用了特殊的自定义端口，可以直接编辑目录下的 `config.json`：

```json
{
  "testUri": "https://www.example.com/",
  "openAiTestUri": "https://api.openai.com/v1/models",
  "chatGptTestUri": "https://chatgpt.com/",
  "portCandidates": [7897, 7892, 7890, 7891, 7898, 8080, 8888, 1080, 10808, 10809],
  "proxyProtocols": ["http", "socks5h"]
}
```

* `portCandidates`：代理端口扫描候选池，按需添加你的代理端口。
* `proxyProtocols`：支持 `http` 和 `socks5h` 协议。

---

## 🔧 诊断模式

如果你想检查当前本地代理和网络状态，但**不想启动客户端、也不想修改任何配置文件**，可以运行无副作用的诊断模式：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\JerEx-launcher.ps1 -DiagnosticOnly
```

### 📁 数据与日志位置
- **运行日志**：`%LOCALAPPDATA%\JerEx\JEL\logs\JEL.log`
- **.env 配置备份**：`%USERPROFILE%\.codex\jel-backups\`

---

## ❓ 常见问题 (FAQ)

<details>
<summary><b>Q1: 我需要把 JEL 放到 ChatGPT 的安装目录或 .codex 目录下吗？</b></summary>
<b>不需要。</b> JEL 采用 Windows 标准包管理协议和全局用户路径自动寻址，放在电脑任何磁盘、任何文件夹下都能正常工作。
</details>

<details>
<summary><b>Q2: 它会覆盖或破坏我原来在 .env 里填写的其他自定义变量吗？</b></summary>
<b>不会。</b> JEL 采用精准正则替换，仅修改 <code>HTTP_PROXY</code> 和 <code>HTTPS_PROXY</code> 两行，其他内容原样保留，并在修改前在 <code>jel-backups</code> 文件夹中生成完整备份。
</details>

<details>
<summary><b>Q3: 为什么有时会弹出“需要重启 ChatGPT”的对话框？</b></summary>
当检测到你的代理端口或节点发生了变化（例如从 7890 变成了 7897），为了让正在运行的 ChatGPT 加载到新的代理环境变量，JEL 会征询你的同意以重启应用；如果不重启，配置也会在下次客户端打开时生效。
</details>

---

## 📄 开源许可证

本项目基于 [MIT 许可证](LICENSE) 开源。欢迎提交 Issue 或 Pull Request！
```
