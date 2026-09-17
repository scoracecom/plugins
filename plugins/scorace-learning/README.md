# ScorAce 学习 Plugin（公开试用候选）

这是公开的薄 Plugin 候选：包含 Skill、方法资源和按平台选择的 runtime helper，不携带 ScorAce 学习核心源码。优先使用宿主已经装配的 ScorAce 产品学习 API；普通材料的取得、读取、解析和理解仍由宿主承担。

本次公开试用发行固定为 Plugin `0.8.0-candidate.20260917` 与程序 `scorace` `0.1.0`，不是稳定版。安装入口和仓库说明见上级公开仓库 README。

## 平台与命令

本期候选有两个目标：原生 macOS 26.x / arm64（`darwin-arm64`）和 Windows x64 程序在 Windows 11 ARM64 系统 x64 仿真中的运行路径（`windows-x64`）。Windows ARM64 仿真不是实体 Windows x64 客户端原生验证。根据实际宿主平台只选择对应 helper；两个 helper 的 `check`、`prepare`、`run` 语义一致，helper 只负责检查、经授权准备和透传同一 `scorace` 程序，不是第二套学习 CLI。

macOS 26.x / arm64：

```sh
"<本 Skill 目录>/../../tools/scorace-runtime.sh" check
"<本 Skill 目录>/../../tools/scorace-runtime.sh" prepare --allow-download
"<本 Skill 目录>/../../tools/scorace-runtime.sh" run study ...
```

Windows 11 ARM64 / x64 仿真（cmd.exe）：

```bat
cmd.exe /d /s /c ""<本 Skill 目录>\..\..\tools\scorace-runtime.cmd" check"
cmd.exe /d /s /c ""<本 Skill 目录>\..\..\tools\scorace-runtime.cmd" prepare --allow-download"
cmd.exe /d /s /c ""<本 Skill 目录>\..\..\tools\scorace-runtime.cmd" run study ..."
```

`check` 是只读配对检查；缺少准确程序时，在已有用户授权下用对应平台的 `prepare --allow-download`，或 `prepare --archive ABSOLUTE_ZIP_PATH`；`run` 只在完整检查通过后透传 `scorace` 顶层命令。拒绝授权、缺件或校验失败时只停止依赖本地程序的操作，不修改系统保护或全局 PATH。

## 锁定与信任边界

Plugin 使用 `scorace-runtime-lock/v2`，按实际平台从唯一的 `darwin-arm64` 或 `windows-x64` 条目选择准确版本；Windows helper 读取由 `.scorace/runtime-lock.json` 自动生成的 `.scorace/runtime-lock.windows.cmd` projection，构建检查会拒绝 projection 漂移，不应手写第二份锁。每个平台的归档、可执行文件和 payload 都必须逐项匹配 lock 中的精确路径、大小和 SHA-256 摘要。摘要只证明字节完整性，不替代操作系统信任。

macOS 条目要求 Apple Developer ID（`system_trust.kind: apple_developer_id`）和该条目自己的 Team ID。Windows 条目明确为 unsigned（`system_trust.kind: unsigned`），不要求也不填写 Apple Team ID；Windows 的 unsigned 与精确摘要不等于 Windows 系统信任。SmartScreen、应用控制和其他系统策略仍由 Windows 决定，不需要关闭或绕过，本候选不宣称这些策略已经验证。

当前 `.scorace/runtime-lock.json` 已固定 Plugin `0.8.0-candidate.20260917` 与 `scorace` `0.1.0` 的双平台 runtime identity、归档 URL、SHA-256、大小和 payload；既有 runtime source revision/tree hash 与真实发行证据保持不变。macOS 条目已有 Developer ID 签名及公证 Accepted 证据；Windows 条目明确为 unsigned，hosted x64 CI 已通过，Windows 11 ARM64 通过系统 x64 仿真运行。后者不能写成实体 Windows x64 客户端原生验证。Windows helper 是 `tools/scorace-runtime.cmd`，不要求修改或绕过 PowerShell ExecutionPolicy，也不要求关闭 SmartScreen、应用控制或其他系统保护。不得用测试签名、示例值或未来地址补填或绕过校验。

固定 runtime 地址为：

- macOS：<https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.0/scorace-0.1.0-darwin-arm64.zip>
- Windows：<https://github.com/scoracecom/plugins/releases/download/scorace-v0.1.0/scorace-0.1.0-windows-x64.zip>

本候选仍不是稳定版。lock 中的精确 SHA-256 只证明归档及 payload 完整性，不替代操作系统信任；请保持 Windows 系统保护开启。

Plugin 版本、`learning-release.json`、runtime lock 和方法投影必须保持同源；程序由独立的 `scorace` 归档提供。
