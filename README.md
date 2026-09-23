# ScorAce Plugins

ScorAce 的公开 Codex Plugin 仓库。本候选版本为 `scorace-learning` Plugin `0.8.0-candidate.20260923.2`；配套 npm CLI 为 `@scorace/cli` `0.1.6`，它不是稳定版。支持调整计划剩余项目的时间、目标与顺序，保留完成、跳过及其结果；也支持错题本收录与分类管理、有序题集保存、原题重做和跨会话接续。Plugin 只提供宿主元数据、Skill、方法资源和发行清单，不携带学习核心源码、CLI 二进制、SEA、runtime lock 或平台 helper。

## 安装

```bash
git clone https://github.com/scoracecom/plugins.git
cd plugins
codex plugin marketplace add .
codex plugin add scorace-learning@scorace
```

安装完成后开启新的 Codex 会话，让宿主加载 `scorace-learning` Skill。卸载使用：

```bash
codex plugin remove scorace-learning@scorace
```

Plugin 的安装、启用、升级和卸载都使用 Codex 的原生 Plugin 机制，不通过 npm 安装 Plugin 本身。

## CLI 准备

需要受管学习操作时，Skill 先运行：

```bash
scorace version --json
```

只有合法 JSON 对象 `{ "version": "...", "protocol": 5 }` 才能继续；`protocol: 5` 是一般学习操作的兼容性判定；调整剩余计划还需要 CLI 至少为 `0.1.6`，旧版同协议不会保存顺序。找不到 CLI 时先检查 Node.js 和 npm；Node.js 需要 `>=24`。两者可用并取得用户正常授权后，执行一次：

```bash
npm install -g @scorace/cli@latest
```

随后再次运行版本检查。协议不符时最多再安装/升级一次并复查；仍失败、输出不是合法 JSON 或命令失败时停止受管操作，保留原学习请求。`scorace` 命令名可能命中旧 Plugin 的 binary；旧 binary、SEA/helper 或其他输出不满足 protocol 5 时按不可用处理，不改 PATH，也不调用旧 helper。

## 升级与数据保留

升级时按取得 Plugin 的来源刷新 Git 内容。通过 `https://github.com/scoracecom/plugins.git` 配置的 Git marketplace 运行：

```bash
codex plugin marketplace upgrade scorace
```

也可以省略 marketplace 名称以升级全部已配置的 Git marketplace。随后重新执行：

```bash
codex plugin add scorace-learning@scorace
```

从本地 clone 使用的用户运行 `git -C /path/to/plugins pull --ff-only`，再执行同一个 `codex plugin add` 命令。

核对宿主返回的版本与安装路径，并在新会话中继续。宿主 Plugin 缓存只保存公开发行物；用户选择的学习目录保存 Markdown、附件和其他学习成果，程序状态保存于用户应用状态目录，用户方法位于宿主的 `CODEX_HOME/skills` 方法目录。升级或卸载 Plugin 不删除这些内容，也不覆盖用户方法。旧版本的 runtime helper 不属于当前候选的回退入口。

当前正式支持和发布验证范围仅覆盖 macOS 与 Windows；其他操作系统不承诺支持。详细用户边界见 [`plugins/scorace-learning/README.md`](plugins/scorace-learning/README.md)。
