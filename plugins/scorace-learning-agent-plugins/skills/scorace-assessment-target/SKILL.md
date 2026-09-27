---
name: scorace-assessment-target
description: 仅当用户明确要求把其选择的考试依据制作或修订为可审阅的 ScorAce 考试目标候选包时使用。单纯询问、阅读或理解考试，普通备考与教学不触发此 Skill。保留考核范围、内容、能力要求、方式、约束、来源和未知；不蒸馏教材教学单元、不建立数据库、不生成正式完整图谱或判断学生状态。
---

# ScorAce 考试目标蒸馏

## 触发边界

只有用户明确要求制作或修订考试目标候选包时才调用本 Skill。用户只要求阅读、解释或理解考试，或开展普通学习时，继续使用 `scorace-study` 与宿主已有能力，不启动候选流程。

## 目标

生成真正可用于理解考试和组织备考的目标，而不只是合规主张列表。保留原件固定、证据身份、候选包内的证据检查、用户可选纠错和历史不覆盖边界。候选包不会自动进入正式库；正式准入须按现行合同另行授权和审查。

开始前完整阅读 [`../../references/distillation-framework.md`](../../references/distillation-framework.md)。

## 输入边界

1. 列出将读取的绝对路径、URL、已有解析结果和写入目录。
2. 只处理用户选择的输入，不扫描相邻目录。
3. 原件需要解析时，优先使用已有结果；当前环境存在 MinerU `parse_documents` 且发送范围已获授权时可以调用。工具不可用时明确要求解析结果。
4. 原件与解析结果分别登记，不修改任何输入。
5. 不把用户材料、私有绝对路径或生成目标包提交到代码仓库。
6. OCR、转写或版面解析结果必须与对应原件一起登记；不能把派生
   Markdown 标成独立官方来源。

## 工作流

### 1. 固定输入

开始候选生产时调用：

```bash
scorace distill target init \
  --target-id <stable-lowercase-id> \
  --target-title "<考试名称>" \
  --region "<地区>" \
  --subject "<学科>" \
  --period "<适用时期>" \
  --draft <working-directory>/draft.json \
  --source <source-id>=<absolute-path>
```

`init` 固定路径、媒体类型、字节数和 SHA-256，并创建只读 source lock。
原件保留初始化生成的 `representation_kind=original` 与
`source_version`；解析结果改为 `representation_kind=derived_content`、
`authority=derived`，并填写：

- `lineage.original_source_ref` 与 `source_version_ref`；
- `lineage.extraction_run` 的稳定 ID、工具及版本、配置、输入范围、运行状态和警告；
- `lineage.content_revision` 的稳定 ID、修订、运行引用及派生内容哈希。

Agent 只编辑 draft 中的领域内容。新的解析结果使用新的输入、提取运行、
内容修订和包修订，不覆盖旧谱系。

### 2. 建立材料全貌和覆盖

逐份阅读可见正文、元数据、解析结果和用户声明：

- 核定 `role`、`authority`、`identity_status` 和身份依据；
- 先在 `coverage.inventory` 列出预期章节、页段或内容块及其内容角色；
- 在 `coverage.sections` 中逐项引用 `inventory_ref`，记录
  `processing_status`、采用方式、输出和 `unverified_elements`；
- 采用、背景、排除和未知范围都必须可见；
- 公式、图表、答案或解析冲突写入 `review_items`。
- 只有所有预期范围都已处理且没有未核对元素时，`coverage.status`
  才能为 `complete`；部分成功使用 `partial`。

来源身份冲突无法消解时才询问用户。普通警告不把审核责任转交用户。

### 3. 建立引用与证据主张

`Citation` 必须返回固定原件或可追溯解析结果中的页码、区域、标题路径、
段落、行号或网页快照。文本引用使用能实际包含摘录的精确行范围或字符
范围；摘录只出现在同一文件的其他位置不算有效引用。

主张继续区分：

- `official`
- `course_or_teacher`
- `past_assessment_observation`
- `model_inference`

每项主张同时填写 `content_identity`：
`source_explicit | model_organized | model_inference`。任何增加了来源未直接
表达含义的结论都使用 `model_inference`，并引用本候选包内已标记为 `accepted` 的输入主张；
`official` 不能承载这类推断。

允许的主张包括范围、内容要求、表现要求、考核方式、题型观察、频率、权重、评分要求和约束。证据足够且没有相关 blocking item 时，Agent 可将主张标记为本候选包内的 `accepted`；该状态仅表示通过本包的证据检查，不写入正式库，也不是正式领域准入。用户不逐项审批包内状态；正式准入仍须另行获得授权并依现行合同审查。

### 4. 形成连贯目标模型

在 `assessment_profile` 中组织：

- `summary`：整体说明；
- `scopes`：考试及各依据实际覆盖的范围；
- `content_domains`：内容领域、具体要求、可观察表现和考核方式；
- `assessment_methods`：跨领域考核方式、题型与作答形式；
- `constraints`：时间、评分、工具和其他明确限制；
- `relationships`：内容、能力和考核方式之间的有依据关系；
- `preparation_guidance`：有依据且明确标识为模型综合的备考含义；
- `known_gaps`：材料无法回答的问题。

主模型通过 `claim_refs` 复用证据主张，不重复发明证据身份。不要用“尽可能窄”破坏整体语义，也不要把课程标准直接写成浙江中考必考承诺。
每项 `scope`、具体要求、可观察表现、考核方式和约束都不得超出其
`claim_refs` 实际蕴含的范围；需要综合或扩写时先建立保存输入和方法的
`model_inference` 主张。覆盖为 `partial` 时，主模型和人可读正文都不得
使用“完整清单”“全面覆盖”等相反表述。

### 5. 校验并生成

```bash
scorace distill target check \
  --draft <working-directory>/draft.json
scorace distill target build \
  --draft <working-directory>/draft.json \
  --output <target-package-directory>
```

成功版本只包含：

```text
assessment-target.md
assessment-target.json
citations.json
quality-report.md
```

`assessment-target.md` 是主要产品；JSON、引用和质量报告提供结构、证据与覆盖支撑。
`assessment-target.json.domain_mapping` 自动说明每个结构化候选可映射的
规范领域对象、仍需满足的准入条件，或无法安全映射的原因。它不执行
正式领域写入，也不授予准入权限。

## 完成检查

- 目标具体回答考什么、要求做到什么、可能怎样考、有哪些约束和未知；
- 每个主要内容领域都有可观察表现或明确缺口；
- 主模型引用的主张在本候选包内标记为 `accepted` 且证据身份正确；
- 覆盖记录说明所有所选范围的处置；
- 质量报告逐项显示处理状态和未核对元素，不能用 `output_refs` 冒充完整；
- OCR、公式、图表、答案和来源冲突没有被流畅文字掩盖；
- 模型综合保留输入和方法，不冒充官方结论；
- 每个结构化候选有规范映射或明确未映射理由；
- 候选生成没有自动写入或准入正式领域数据；正式准入由用户按现行合同另行授权并审查；
- 用户纠正生成新版本，既有决定不被 Agent 静默恢复；
- 新版本不覆盖旧版本或原件。
