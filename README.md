# ScorAce Plugins

> **当前状态：恢复公开试用候选。** Windows helper 已改为原生 `tools/scorace-runtime.cmd`，不要求修改或绕过脚本执行策略，也不要求关闭系统保护。Windows 验证范围包含 hosted x64 CI，以及 Windows 11 ARM64 上通过系统 x64 仿真的客户端证据；后者不能写成实体 x64 客户端原生验证。

ScorAce 的公开 Codex Plugin 试用仓库。当前发行是公开试用候选，不是稳定版。

## 安装

```bash
git clone https://github.com/scoracecom/plugins.git
cd plugins
codex plugin marketplace add .
codex plugin add scorace-learning@scorace
```

安装后请开启新的 Codex 会话，以加载 `scorace-learning` Skill。卸载使用：

```bash
codex plugin remove scorace-learning@scorace
```

## 当前发行

- Plugin：`scorace-learning` `0.8.0-candidate.20260917`
- 程序：`scorace` `0.1.0`
- 发布标签：[`scorace-v0.1.0`](https://github.com/scoracecom/plugins/releases/tag/scorace-v0.1.0)
- ScorAce source revision：`240c6451e6e7accc03e3ce70271b25eda2e9e1a1`
- Runtime source tree SHA-256：`aa06385725691ec29826637549e293c88975d33547a78dbe747f25d8f58b176c`
- main merge：`2a7a192c26c4bec193ebcc027fd4c97a2c50d2cd`
- Plugin helper fix merge：`c30a617cd7263eb435bb777493ef731970393c81`（Windows `.cmd` 入口）
- 共同 Git tree：`0579921f4dc99251adac077ca3a75f59f36c663a`

仓库只包含公开 Plugin、方法资源、helper、发行清单和 runtime lock，不包含 ScorAce 私有源码或 runtime 二进制。需要本地程序时，helper 仅在用户授权后按 lock 从以下固定地址取得对应平台归档：

- [macOS arm64 ZIP](https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.0/scorace-0.1.0-darwin-arm64.zip)：Developer ID 签名及公证已 Accepted。
- [Windows x64 ZIP](https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.0/scorace-0.1.0-windows-x64.zip)：hosted x64 CI 已通过；Windows 11 ARM64 客户端通过系统 x64 仿真运行，不能冒充实体 x64 客户端原生验证。

支持范围是原生 macOS 26.x/arm64，以及 Windows x64 程序在 hosted x64 CI 与 Windows 11 ARM64 系统 x64 仿真中的验证路径；不声称已有实体 x64 客户端原生验证。Windows 归档明确为 unsigned；精确 SHA-256 只证明文件完整性，不代表 Windows 系统信任。请保持 SmartScreen、应用控制和其他系统保护开启。

详细 helper 用法、平台边界和数据安全说明见 [`plugins/scorace-learning/README.md`](plugins/scorace-learning/README.md)。
