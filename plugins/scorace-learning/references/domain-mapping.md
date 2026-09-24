# 蒸馏候选到 ScorAce 领域模型的映射

## 目的

蒸馏包是可独立阅读的中间候选，不是正式领域存储。每个结构化对象必须说明它可映射到哪个规范对象、还缺什么准入条件；没有一一对应关系时保持未映射，不能发明第二套正式模型。

权威语义来自仓库中的 `docs/domain/`。本文件只说明 Plugin 输出如何接近这些对象，不复制字段合同。

## 共同规则

- `mapping_status` 使用 `mapped_candidate | projection_only | unmapped`：分别表示可形成规范候选、只能作为后续投影输入、当前没有规范承载对象。
- `canonical_type` 使用现有规范对象名；没有对应对象时为 `null`。
- `admission_requirements` 列出进入正式领域数据前仍需完成的核对。
- 包内 `accepted` 只表示通过本次蒸馏检查；除非完成规范对象的决定字段与准入流程，否则不得表述为正式领域对象已经接受。
- 映射必须保留稳定 ID、原件版本、提取运行、引用、内容身份、适用目标和包修订。
- 任何映射都不得直接创建学生状态、计分结果、正式图谱修订或学习计划。

## 对象映射

| 蒸馏候选 | 规范对象或处理 | 关键边界 |
|---|---|---|
| 考试身份与目标 | `AssessmentTarget` 候选 | 目标状态和修订须在正式采用时决定 |
| 考试主张 | `AssessmentClaim` 候选 | 保留 `basis_kind`、证据、样本、推断方法、争议和决定依据 |
| 原件 | `Source` + `SourceVersion` 候选 | 固定字节、哈希和格式；不可由 OCR 文本替代 |
| OCR / 解析表示 | `ExtractionRun` 产物，随后形成 `ContentRevision` / `ContentUnit` 候选 | 不是与原件并列的官方 `Source` |
| 引用 | `SourceAnchor` + `Citation` 候选 | locator 必须定位原件或可追溯的内容单元，摘录必须与位置相符 |
| 资料覆盖记录 | 摄取运行的处理证据与 `ContentRevision` 缺口 | 不是 `ItemCoverage`；不能表达学生状态 |
| 稀疏语义候选 | `AssessmentGraphNode`、`AssessmentGraphEdge` 或 `AnswerableItem` 候选；无法映射到现行规范对象时 `unmapped` | 角色可叠加或未知；不因缺少某种维度而补造内容。当前不存在独立 `LearningMaterial` 对象；资料仍由来源版本、内容修订、内容单元、引用及存储归属共同表达 |
| 教材到考试目标连接 | 主张引用、图谱投影或活动目标的候选输入 | 连接本身不证明目标官方要求，也不产生掌握结论 |
| 图谱节点 | `AssessmentGraphNode` 候选 | 只表达可复用知识、方法、能力、题型或评分要求 |
| 图谱关系 | `AssessmentGraphEdge` 候选 | 关系方向按规范字面含义核对 |
| 来源题目候选 | `AnswerableItem` 候选 | 保留题干、题号、小题、答案/解析状态与来源锚点；固定呈现、作答合同和用途准入前不是正式题目或题库条目 |
| 题目目标连接候选 | `ItemCoverage` 的候选输入 | 必须绑定固定考试目标修订、依据与主要/次要/可观察表现角色；未连接不产生正式覆盖或组卷质量结论 |
| 质量警告与未决项 | 包级质量证据；默认无正式领域对象 | 不能因没有承载对象而静默删除 |

## 关系映射

图谱关系只使用领域模型已有语义：

`prerequisite_for | part_of | composes_with | supports | contrasts_with | variant_of | applied_by | assessed_by | scored_by | related_to`

`A prerequisite_for B` 只用于“学习 B 通常需要 A”的严格主张。来源中 A 位于 B 前面或 A 可帮助解释 B，均不自动构成前置关系；证据只能支持一般关联时使用 `related_to`，无法安全确定时保持未映射。

## 包内声明

考试目标包和学习材料包都应提供 `domain_mapping`：

```yaml
domain_mapping:
  mapping_status: mapped_candidate | projection_only | unmapped
  canonical_type: AssessmentClaim | AssessmentGraphNode | null
  canonical_ref: null
  admission_requirements: []
  notes: []
```

`canonical_ref` 只有在后续流程已经创建固定规范对象时填写。Plugin 本身只生成候选，因此默认保持 `null`。
