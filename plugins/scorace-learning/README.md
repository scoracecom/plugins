# ScorAce 学习 Plugin（公开试用候选）

这是公开的薄 Plugin 候选：包含 Skill、方法资源和按平台选择的 runtime helper，不携带 ScorAce 学习核心源码。优先使用宿主已经装配的 ScorAce 产品学习 API；普通材料的取得、读取、解析和理解仍由宿主承担。

本次公开试用发行固定为 Plugin `0.8.0-candidate.20260916` 与程序 `scorace` `0.1.0`，不是稳定版。安装入口和仓库说明见上级公开仓库 README。

## 平台与命令

本期候选有两个目标：原生 macOS 26.x / arm64（`darwin-arm64`）和 Windows 11 / x64（`windows-x64`）。根据实际宿主平台只选择对应 helper；两个 helper 的 `check`、`prepare`、`run` 语义一致，helper 只负责检查、经授权准备和透传同一 `scorace` 程序，不是第二套学习 CLI。

macOS 26.x / arm64：

```sh
"<本 Skill 目录>/../../tools/scorace-runtime.sh" check
"<本 Skill 目录>/../../tools/scorace-runtime.sh" prepare --allow-download
"<本 Skill 目录>/../../tools/scorace-runtime.sh" run study ...
```

Windows 11 / x64（PowerShell）：

```powershell
& "<本 Skill 目录>\..\..\tools\scorace-runtime.ps1" check
& "<本 Skill 目录>\..\..\tools\scorace-runtime.ps1" prepare --allow-download
& "<本 Skill 目录>\..\..\tools\scorace-runtime.ps1" run study ...
```

`check` 是只读配对检查；缺少准确程序时，在已有用户授权下用对应平台的 `prepare --allow-download`，或 `prepare --archive ABSOLUTE_ZIP_PATH`；`run` 只在完整检查通过后透传 `scorace` 顶层命令。拒绝授权、缺件或校验失败时只停止依赖本地程序的操作，不修改系统保护或全局 PATH。

## 锁定与信任边界

Plugin 使用 `scorace-runtime-lock/v2`，按实际平台从唯一的 `darwin-arm64` 或 `windows-x64` 条目选择准确版本；每个平台的归档、可执行文件和 payload 都必须逐项匹配 lock 中的精确路径、大小和 SHA-256 摘要。摘要只证明字节完整性，不替代操作系统信任。

macOS 条目要求 Apple Developer ID（`system_trust.kind: apple_developer_id`）和该条目自己的 Team ID。Windows 条目明确为 unsigned（`system_trust.kind: unsigned`），不要求也不填写 Apple Team ID；Windows 的 unsigned 与精确摘要不等于 Windows 系统信任。SmartScreen、应用控制和其他系统策略仍由 Windows 决定，不需要关闭或绕过，本候选不宣称这些策略已经验证。

当前 `.scorace/runtime-lock.json` 已绑定真实 `0.1.0` 双平台发行值和 macOS Team ID `3G2K3NF4U6`。macOS 归档已完成 Developer ID 签名及公证并获 Accepted；Windows 归档为 unsigned，hosted x64 CI 已通过，Parallels consumer validation pending。Windows 客户端行为、SmartScreen 或其他系统策略在 Parallels 验证完成前不视为已验证；不得关闭或绕过系统保护。

固定 runtime 地址为：

- macOS：<https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.0/scorace-0.1.0-darwin-arm64.zip>
- Windows：<https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.0/scorace-0.1.0-windows-x64.zip>

本候选仍不是稳定版。lock 中的精确 SHA-256 只证明归档及 payload 完整性，不替代操作系统信任或 Parallels consumer validation。

Plugin 版本、`learning-release.json`、runtime lock 和方法投影必须保持同源；程序由独立的 `scorace` 归档提供。
