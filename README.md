# ScorAce Plugins

> **当前状态：`0.1.1` public-trial readiness，待主线程发布。** 真实双平台 runtime lock、projection 与 payload 已完成最终校验；release 尚未发布，当前不应视为可用的公开下载入口。Windows 正式入口为原生 `tools/scorace-runtime.cmd`。不要降低或绕过 PowerShell ExecutionPolicy，也不要关闭任何系统保护。

ScorAce 的公开 Codex Plugin 试用仓库。当前发行是公开试用候选，不是稳定版。

## 安装

```bash
git clone https://github.com/scoracecom/plugins.git
cd plugins
codex plugin marketplace add .
codex plugin add scorace-learning@scorace
```

当前 `0.1.1` release 尚待主线程发布，不应视为可用的公开下载入口。安装后请开启新的 Codex 会话，以加载 `scorace-learning` Skill。卸载使用：

```bash
codex plugin remove scorace-learning@scorace
```

## 当前发行

- Plugin：`scorace-learning` `0.8.0-candidate.20260917.1`
- 程序：`scorace` `0.1.1`
- 发布标签：[`scorace-v0.1.1`](https://github.com/scoracecom/plugins/releases/tag/scorace-v0.1.1)（待主线程发布，当前不可下载）
- ScorAce source revision：`b50f9967481ff201544200bad925dcb49e36e7e0`
- Runtime source tree SHA-256：`6d91171e4e580bedd6267f5ff2766e3cf57c35988368906b74635b46b7858818`
- main release commit：`b50f9967481ff201544200bad925dcb49e36e7e0`
- Plugin helper fix merge：`c30a617cd7263eb435bb777493ef731970393c81`（Windows `.cmd` 入口）
- 共同 Git tree：`315ce03081ea7eeb10a5261422c1ba253a603fbb`

仓库只包含公开 Plugin、方法资源、helper、发行清单和 runtime lock，不包含 ScorAce 私有源码或 runtime 二进制。需要本地程序时，helper 仅在用户授权后按 lock 从以下固定地址取得对应平台归档：

- [macOS arm64 ZIP](https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.1/scorace-0.1.1-darwin-arm64.zip)：Developer ID 签名及公证已 Accepted；release 待主线程发布。
- [Windows x64 ZIP](https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.1/scorace-0.1.1-windows-x64.zip)：hosted x64 CI 已通过；Windows 11 ARM64 客户端通过系统 x64 仿真运行，不能冒充实体 x64 客户端原生验证；release 待主线程发布。

支持范围是原生 macOS 26.x/arm64，以及 Windows x64 程序在 hosted x64 CI 与 Windows 11 ARM64 系统 x64 仿真中的验证路径；不声称已有实体 x64 客户端原生验证。Windows 归档明确为 unsigned；精确 SHA-256 只证明文件完整性，不代表 Windows 系统信任。请保持 SmartScreen、应用控制和其他系统保护开启。

详细 helper 用法、平台边界和数据安全说明见 [`plugins/scorace-learning/README.md`](plugins/scorace-learning/README.md)。
