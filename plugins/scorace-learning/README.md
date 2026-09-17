# ScorAce 学习 Plugin（工程候选）

这是公开的薄 Plugin 候选：包含 Skill、方法资源和按平台选择的 runtime helper，不携带 ScorAce 学习核心源码。优先使用宿主已经装配的 ScorAce 产品学习 API；普通材料的取得、读取、解析和理解仍由宿主承担。

## 平台与命令

本期候选有两个目标：原生 macOS 26.x / arm64（`darwin-arm64`）和 Windows 11 / x64（`windows-x64`）。根据实际宿主平台只选择对应 helper；两个 helper 的 `check`、`prepare`、`run` 语义一致，helper 只负责检查、经授权准备和透传同一 `scorace` 程序，不是第二套学习 CLI。

macOS 26.x / arm64：

```sh
"<本 Skill 目录>/../../tools/scorace-runtime.sh" check
"<本 Skill 目录>/../../tools/scorace-runtime.sh" prepare --allow-download
"<本 Skill 目录>/../../tools/scorace-runtime.sh" run study ...
```

Windows 11 / x64（cmd.exe）：

```bat
cmd.exe /d /s /c ""<本 Skill 目录>\..\..\tools\scorace-runtime.cmd" check"
cmd.exe /d /s /c ""<本 Skill 目录>\..\..\tools\scorace-runtime.cmd" prepare --allow-download"
cmd.exe /d /s /c ""<本 Skill 目录>\..\..\tools\scorace-runtime.cmd" run study ..."
```

`check` 是只读配对检查；缺少准确程序时，在已有用户授权下用对应平台的 `prepare --allow-download`，或 `prepare --archive ABSOLUTE_ZIP_PATH`；`run` 只在完整检查通过后透传 `scorace` 顶层命令。拒绝授权、缺件或校验失败时只停止依赖本地程序的操作，不修改系统保护或全局 PATH。

## 锁定与信任边界

Plugin 使用 `scorace-runtime-lock/v2`，按实际平台从唯一的 `darwin-arm64` 或 `windows-x64` 条目选择准确版本；Windows helper 读取由 `.scorace/runtime-lock.json` 自动生成的 `.scorace/runtime-lock.windows.cmd` projection，构建检查会拒绝 projection 漂移，不应手写第二份锁。每个平台的归档、可执行文件和 payload 都必须逐项匹配 lock 中的精确路径、大小和 SHA-256 摘要。摘要只证明字节完整性，不替代操作系统信任。

macOS 条目要求 Apple Developer ID（`system_trust.kind: apple_developer_id`）和该条目自己的 Team ID。Windows 条目明确为 unsigned（`system_trust.kind: unsigned`），不要求也不填写 Apple Team ID；Windows 的 unsigned 与精确摘要不等于 Windows 系统信任。SmartScreen、应用控制和其他系统策略仍由 Windows 决定，不需要关闭或绕过，本候选不宣称这些策略已经验证。

当前 `.scorace/runtime-lock.json` 仍是空锁：程序版本、来源、归档、可执行文件摘要/大小、payload 以及 macOS Team ID 尚未填入真实发行值。因此本文件只描述工程候选；当前 runtime helper 会拒绝安装或执行本地程序，Plugin 也不可作为公开发行入口。不得用测试签名、示例值或未来地址补填或绕过校验。

Windows 公开试用的目标口径是“Windows 11 可运行 x64 程序”，放行需要 x64 CI 与 Parallels 客户端的对应证据。当前 Parallels 尚未验证，Windows 公开试用、公开下载/安装入口和 SmartScreen 等系统策略仍未完成，不能把它们写成已验证或已发布。

Plugin 版本、`learning-release.json`、runtime lock 和方法投影必须保持同源；程序由独立的 `scorace` 归档提供。
