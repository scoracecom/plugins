# ScorAce Plugins

ScorAce 的公开学习插件仓库。同源提供 [Agent Plugins 1.0](https://agent-plugins.org/specification) 标准包 [`plugins/scorace-learning-agent-plugins`](plugins/scorace-learning-agent-plugins) 和 Codex 原生包 [`plugins/scorace-learning`](plugins/scorace-learning)，包含普通学习 `scorace-study`、考试目标候选 `scorace-assessment-target` 和学习资料候选 `scorace-learning-material` 三个 Skill；后两者仅在明确要求制作正式流程候选时使用。插件版本、Learning API/Core 与 CLI 兼容信息以各包的 `learning-release.json` 为准。插件不携带学习核心源码或 CLI；配套 CLI 通过 [npm](https://www.npmjs.com/package/@scorace/cli) 分发。

## 兼容宿主

支持 Agent Plugins **Agent Skills 组件**的宿主可按各自文档安装 `plugins/scorace-learning-agent-plugins` 目录。标准规定插件包及 Skill 的发现格式，不统一安装、升级或权限机制。ScorAce 的受管学习操作还需要宿主提供已获授权的本地文件、命令执行与相关内容读取能力，以及下文的 CLI；具体可用功能取决于宿主。当前发布验证的操作系统范围为 macOS 和 Windows。详细边界见[标准包说明](plugins/scorace-learning-agent-plugins/README.md)。

## Codex 安装

```bash
git clone https://github.com/scoracecom/plugins.git
cd plugins
codex plugin marketplace add .
codex plugin add scorace-learning@scorace
```

安装完成后开启新的 Codex 会话，让宿主加载 ScorAce Plugin 的三个 Skill。卸载使用：

```bash
codex plugin remove scorace-learning@scorace
```

以上是 Codex 的原生 Plugin 命令；其他宿主请使用各自的安装方式。npm 只用于安装 ScorAce CLI。

## CLI 准备

需要受管学习操作时，Skill 先运行：

```bash
scorace version --json
```

只有合法 JSON 对象且其 `protocol` 与[发行清单](plugins/scorace-learning/learning-release.json)中的 `cli_protocol` 一致，才可继续。`version` 仅用于诊断。找不到 CLI 时先检查 Node.js 和 npm；Node.js 需要 `>=24`。两者可用并取得用户正常授权后，执行一次：

```bash
npm install -g @scorace/cli@latest
```

随后再次运行版本检查。协议不符时最多再安装/升级一次并复查；仍失败、输出不是合法 JSON 或命令失败时停止受管操作，保留原请求。`scorace` 命令名可能命中旧 Plugin 的 binary；旧 binary、SEA/helper 或其他输出不满足发行清单所列协议时按不可用处理，不改 PATH，也不调用旧 helper。

## Codex 升级与数据保留

升级时按取得 Plugin 的来源刷新 Git 内容。通过 `https://github.com/scoracecom/plugins.git` 配置的 Git marketplace 运行：

```bash
codex plugin marketplace upgrade scorace
```

也可以省略 marketplace 名称以升级全部已配置的 Git marketplace。随后重新执行：

```bash
codex plugin add scorace-learning@scorace
```

从本地 clone 使用的用户运行 `git -C /path/to/plugins pull --ff-only`，再执行同一个 `codex plugin add` 命令。

核对 Codex 返回的版本与安装路径，并在新会话中继续。Plugin 缓存只保存公开发行物；用户选择的学习目录保存 Markdown、附件和其他学习成果，程序状态保存于用户应用状态目录。在 Codex 中，用户方法位于 `CODEX_HOME/skills` 方法目录。升级或卸载 Plugin 不删除 ScorAce 学习成果，也不覆盖用户方法。旧版本的 runtime helper 不属于当前候选的回退入口。

其他操作系统尚未纳入发布验证。
