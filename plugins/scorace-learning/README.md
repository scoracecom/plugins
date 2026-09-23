# ScorAce 学习 Plugin

这是 ScorAce 的宿主 Plugin 候选 `0.8.0-candidate.20260923.4`：包含 Skill、方法资源和发行清单，不携带学习核心源码、旧 binary、SEA 或平台 runtime helper。宿主负责会话、文件、授权、命令执行和呈现；Skill 只提供学习工作指引。受管学习操作统一通过 npm 包 `@scorace/cli` 执行；本候选的 CLI 版本为 `0.1.8`，Plugin 的官方 `.codex-plugin/plugin.json` 不承载 CLI 私有字段。

## 安装、升级与卸载

公开用户从 [ScorAce Plugins](https://github.com/scoracecom/plugins) 获取 Plugin，并使用 Codex 的原生 Plugin 机制：

```sh
git clone https://github.com/scoracecom/plugins.git
cd plugins
codex plugin marketplace add .
codex plugin add scorace-learning@scorace
```

升级时按取得 Plugin 的来源刷新 Git 内容。通过 `https://github.com/scoracecom/plugins.git` 配置的 Git marketplace 运行 `codex plugin marketplace upgrade scorace`，再执行 `codex plugin add scorace-learning@scorace`；从本地 clone 使用的用户运行 `git -C /path/to/plugins pull --ff-only`，再执行同一个 `codex plugin add` 命令。两种来源都要核对宿主返回的版本与安装路径，并在新 Codex 会话中继续。卸载使用 `codex plugin remove scorace-learning@scorace`。ScorAce 源仓的 `plugins/scorace-learning` 只用于生成和检查候选，不是用户的 npm 安装入口；不要把 Plugin 复制到学习目录。

## CLI 准备与协议

需要受管学习操作时，先运行：

```sh
scorace version --json
```

只接受合法 JSON 对象 `{ "version": "...", "protocol": 7 }`；`protocol: 7` 是唯一兼容性判定，`version` 只用于诊断。版本检查不读取学习正文，也不创建学习状态。

找不到 `scorace` 时，先运行 `node --version` 和 `npm --version`。缺少 Node.js（需要 24 或更高版本）或 npm 时，清晰报告缺少的依赖，不伪造可用 CLI。Node.js 与 npm 都可用后，在用户正常授权下执行一次：

```sh
npm install -g @scorace/cli@latest
```

安装完成后重新运行 `scorace version --json`。若 `protocol` 不是 `7`，在用户授权下最多再执行一次上述升级，再检查一次；仍不兼容、输出不是合法 JSON 或命令失败时停止受管操作并保留原请求。`scorace` 命令名可能命中旧 Plugin 的 binary；只有合法 JSON 且 `protocol: 7` 才能继续，旧 binary、SEA/helper 或其他输出都按不可用处理。不得改 PATH、绕过 npm 发行入口或绕过授权。

协议通过后，所有学习者、空间、资产、方法、网络、任务、互动和复盘操作都使用同一个 `scorace study ...` CLI。CLI 缺失、不兼容或执行失败只影响依赖它的受管操作；普通问答和宿主已经取得的材料仍按实际能力处理。

## 发行与许可说明

`learning-release.json` 固定记录 `cli_package: "@scorace/cli"` 与 `cli_protocol: 7`，以及 Plugin/API/Core 版本和公开文件摘要；这些字段不复制到官方宿主 manifest。npm 是 CLI 的发行机制，Plugin 的安装、启用、更新和卸载仍沿用宿主标准机制。

Plugin 缓存只保存公开发行物。用户选择的学习目录保存 Markdown、附件和其他学习成果，程序状态保存于用户应用状态目录，用户方法仍位于宿主的 `CODEX_HOME/skills` 方法目录；升级或卸载 Plugin 不删除这些内容，也不覆盖用户方法。旧 Plugin 的运行时和 helper 已退出当前发行，不能作为 CLI 回退入口。

当前正式支持和发布验证仅覆盖 macOS 与 Windows；两者使用同一个 Plugin、npm CLI 和 Learning Core。其他操作系统不承诺支持，也不纳入发布验证。

仓库和 CLI 的 npm 元数据使用 `UNLICENSED`，表示没有授予标准开源许可；这不承诺代码保密，也不自动授予额外使用权。用户成果保存在用户明确选择的学习空间，不放入 Plugin 缓存。
