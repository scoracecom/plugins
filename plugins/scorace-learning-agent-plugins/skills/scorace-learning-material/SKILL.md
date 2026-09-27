---
name: scorace-learning-material
description: 仅当用户明确要求把其选择的资料制作或修订为可审阅的 ScorAce 学习资料候选包时使用。单纯阅读、解释、摘要材料或围绕材料普通练习不触发此 Skill。忠实保留来源锚点、原生结构、顺序、处理状态及数学公式、图形、题目和答案状态；不生成教学内容、练习、反馈、正式领域数据或学生状态。
---

# ScorAce 资料来源恢复

## 触发边界

只有用户明确要求制作或修订学习资料候选包时才调用本 Skill。用户只要求阅读、讲解、摘要或基于资料练习时，继续使用 `scorace-study` 与宿主已有能力，不启动候选流程。

## 边界

只读取用户明确选择的绝对路径、URL 快照或既有解析结果；不要扫描相邻目录。原件、提取运行和派生内容分别登记，原件不可修改。外部解析或模型 Provider 需要新的发送权限时先询问。

这一步只恢复来源已经存在的结构和内容，不新增解释、示例、练习、反馈或教学编排。`content_units`（内容单元）是候选，不是 ScorAce 正式 `ContentUnit`、数据库记录、题库或图谱。

需要非敏感的资料呈现选择时，只让宿主发起版本化 `choice` 或 `form` request；默认值不
代表同意，不支持交互时使用 request 固定的文字降级。不要把偏好、授权或 Provider
凭据写入候选内容、Agent 文本或可交换包。

## 本地候选工作空间

默认根目录是 `~/.scorace/`；可用 `--workspace` 覆盖。首次 `init` 才创建目录，布局只包含：

```text
sources/<material-id>/       固定来源登记
runs/<material-id>/          draft、source lock 和运行记录
candidate-packages/<material-id>/vNNNN/ 版本化候选包
```

工作空间不保存 Provider 令牌，也不等同未来正式数据空间。可交换产物不得包含来源绝对路径；原件与成功包版本都不覆盖。

开始前完整阅读[蒸馏框架](../../references/distillation-framework.md)与[领域映射](../../references/domain-mapping.md)，并且只处理用户明确选择的来源。

## 工作流

```bash
scorace distill material init \
  --material-id <stable-lowercase-id> \
  --title "<材料名称>" \
  --subject "<学科>" \
  --audience "<适用学习者>" \
  --source <source-id>=<absolute-path> \
  [--derived <derived-source-id>=<original-source-id>] \
  [--workspace <workspace-root>]
```

已有 OCR、转写或版面解析文本也用 `--source` 登记，并用 `--derived` 指向其原件。命令会固定“原件 → 提取运行 → 派生内容修订”谱系；派生文本不是独立原件。

随后只编辑该 run 的 draft：

1. `coverage.inventory` 列出所选范围的每个可寻址页段、章节或内容块；每个来源至少有一项。
2. `coverage.sections` 逐项登记 `processed | partial | skipped | failed | unknown`、未核对元素和原因。不得漏掉 inventory；只有全部 `processed` 才能写 `coverage.status=complete`。
3. `content_units` 按来源原生顺序写入 `native_label`（原生标签）、`position`（原生顺序）、`parent_ref`（同来源父单元）、`locator`（来源锚点）、实际恢复的 `content`、状态和警告。无法可靠恢复的内容用空字符串和明确警告，不猜测补齐。
   `content_units[].original_locator` 必须是可对照原件核验的准确位置；由原件直接恢复时记录该位置，来自 OCR、转写或派生文本时由用户或审查者核对原件后填写。无法核验时保持 `null` 并标记 `unknown`，不猜位置；缺少已核验定位的候选不会准入为正式 `ContentUnit`。
4. `semantic_candidates`（稀疏语义候选）可以为零个或多个；每项只引用既有内容单元，使用 `source_explicit | model_organized | model_inference`，列出实际存在的概念、方法、命题、任务、解答、答案或关系角色。角色可叠加或 `unknown`；`source_explicit` 与 `model_organized` 都附可回查原文摘录，推断保留输入候选和方法。每项均写入规范映射或未映射理由。不得使用 `model_generated` 补造解释、示例、练习或反馈。
5. `item_dispositions`（题目处置）逐项覆盖全部内容单元，使用 `extracted | partial | skipped | failed | unknown | no_answerable_task`，因此任何范围都不会静默遗漏可回答任务。`item_candidates`（来源题目候选）保留题干、题号、小题、图形/公式引用、精确定位、恢复状态，以及答案和解析各自的存在、恢复与对应状态；来源没有的内容保持缺失或未知，不补造。
6. 题目候选不是正式 `AnswerableItem`、题库条目或 `ItemCoverage`。有固定考试目标修订时，`target_connection` 只写带依据的主要、次要或可观察表现候选；没有可靠修订或依据时写 `unlinked`，不得宣称覆盖、组卷质量或正式准入。

检查和创建新候选版本：

```bash
scorace distill material check \
  --draft <draft.json> [--assessment-target <fixed-package>/assessment-target.json]
scorace distill material build \
  --draft <draft.json> [--workspace <workspace-root>] \
  [--assessment-target <fixed-package>/assessment-target.json]
```

若 draft 声明固定考试目标，必须由应用通过 `--assessment-target` 独立绑定；
draft 自报的路径或哈希不授权检查或构建。

每次成功构建生成 OKF v0.2 候选知识包：根 `index.md` 是中文主入口；`coverage.md`、`sources.md`、`content/`、`candidates/`、`items/` 和 `quality-report.md` 用标准 Markdown 链接渐进阅读；`anchors.json`、`citations.json` 和 `manifest.json` 只承载精确锚点、谱系和机器校验。候选包不是 ScorAce 正式领域数据、数据库或正式 OKF 导出投影；本阶段不把来源原生标签改造成跨材料固定分类。

## 数学生产模式（#281）

当用户同时明确选择浙江数学官方依据、教材片段和真实试卷或试题评析时，复用上面的 `material` 工作流生成少量、可回查的普通候选：

1. 为三类来源分别登记原件或已有解析结果；每个页段、章节或题目范围都进入 `coverage.inventory`，并逐项保留 `processed | partial | skipped | failed | unknown` 与理由。
2. 官方主张只写来源明确的稀疏候选；教材只记录实际出现的知识、方法或关系观察；试卷只恢复原生题号、题干、小题、公式/图形锚点和答案/解析存在与恢复状态。local parser 报告缺口时先经 quality/gap decision，再按授权范围使用 MinerU gap-only OCR；解析器不可用或扫描/图像资料需要 whole-source 时，默认写 `dependency_unavailable` 且不外发，只有显式 whole-source policy、固定 `SourceVersion`/hash 和实际范围授权通过才可发送；绝不隐式 parser fallback。
3. 每个内容单元都有 `item_dispositions`；来源题候选必须带 `Citation` 可回查、`domain_mapping.canonical_type=AnswerableItem` 且 `canonical_ref=null`，目标连接只能是有依据的 `candidate` 或 `unlinked`。公式、图形、开放小题缺口保持 `partial|unknown`，不猜测补齐。
4. Skill 只输出候选 OKF/Artifact，通过既有应用准入边界交给 #97–#100 消费；不直接写正式数据库，不创建 `ProblemArchetype`、`ItemCoverage`、教学题或第二考试目标。

验收至少回查一条官方主张、一条真实教材关系/方法观察和一道含公式、图形或开放边界的试题；三者的来源、状态、理由、coverage/unknown 必须能在包内对账。任何未能回查的部分仍公开为 unknown，不得用“生成成功”替代内容真实度。

## 完成检查

- 所选范围、内容单元和处理状态可对账，未处理范围显式可见；
- 原生标签、父子关系、顺序、来源锚点和解析警告保留；
- 可交换 sidecar 不泄露绝对私有路径或令牌；
- 新版本不覆盖原件、source lock 或旧候选包；
- 每个内容单元都有题目处置；题目候选与答案、解析、目标连接均保留来源状态，未连接不冒充正式覆盖；
- 资料有用不等于完整；`partial`、`skipped`、`failed` 和 `unknown` 不得表述为完整恢复。
