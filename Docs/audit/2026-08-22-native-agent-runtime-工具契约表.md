# Native 第一棒 · 12 工具契约表

依据 `extension.ts`（2810 行）与 `PiAgentRuntime.swift` / `StudyAgentRuntime.swift` / `WorkspaceStore.swift` 实测，不靠猜。LIMITS 见 `extension.ts:96-128`。

Native 化口径：4 个 host tool 已由 Swift 执行；其余 8 个按契约等价重写，并从「读提问前快照」升级为直读 live stores。工具实现必须复用与 UI 相同的 store 能力方法，不写平行实现。因 PR #279 占用 `WorkspaceStore.swift`，live 接线延后，本表先钉死协议与复用目标。

权限等级按意图交接：读自动放行 / 写用户确认 / 破坏二次确认 / 硬护栏 deny-only。本表 12 个工具无破坏类。

---

## 共用上限（LIMITS）

| 键 | 值 |
|---|---|
| identifier | 256 |
| title | 300 |
| question | 4_000 |
| courseMapPageItems | 40 |
| courseSearch query | 500 字符；limit 默认未写、最大 8 |
| courseRead maximumCharacters | 1_000–12_000，Swift host 默认 6_000 |
| webText / web maximumCharacters | 20_000；Swift host 默认 12_000，范围 1_000–20_000 |
| visualAssetBytes | 6_000_000 |
| visualizationSpec | 1_000_000 字节 JSON |
| proposalMarkdown | 24_000 |
| proposalEvidenceItems | 16；每条 500 |
| learningText | 500；learningEvidence 400；sessionSummary 2_000 |
| profile entry text | 1_200；entries/removed 各最多 12 |

硬护栏（deny-only，任何工具不可绕过）：课程隔离、Chat 隔离、记忆隔离、目录越界、`read` 仅限内置 skill 路径。

---

## 1. `read`（Skill 读取）

| 项 | 契约 |
|---|---|
| 执行侧 | extension.ts（TS） |
| 权限 | 读 |
| 副作用 | 无写盘；把 SKILL.md 正文注入模型 |
| 输入 | `{ path: string(1..4096) }`，`additionalProperties: false` |
| 合法 path | 仅 `skill://visualize` 或已登记 visualize Skill 的真实路径 |
| 输出 content | Skill 文件 UTF-8 正文 |
| details | 先 `skill_read_pending`，Pi 侧解码后变成 `weibei_skill_read`（id/name/version/sha256/byteCount/relativePath） |
| 失败 | 非登记路径 → `"read 只接受魏碑已登记的 skill:// 路径"` |
| Native | 技能系统第三棒才完整；第一棒保持「只读内置 visualize」等价 |

## 2. `weibei_visualize`

| 项 | 契约 |
|---|---|
| 执行侧 | TS |
| 权限 | 读（产出展示 spec，不写课程文件） |
| 副作用 | 无落库；reply.richAnswer 由 Swift 渲染 |
| 输入 | `{ id: kebab-case 1..128, spec: { title?, gap 0..64, items: 1..200 } }` |
| 拒绝 | id 不合规则 / items 空 / spec JSON > 1MB |
| 输出 | 文本「互动界面 {id} 已显示。」+ details `weibei_visualization` |
| 开关 | `interactiveVisualizationsEnabled == false` 时 Pi 从 allowedToolNames 去掉此工具 |
| Native | 校验 spec 结构合法即可；**不评生成质量** |

## 3. `weibei_visual_asset`

| 项 | 契约 |
|---|---|
| 执行侧 | TS，读当前快照的 visualAssets |
| 权限 | 读 |
| 输入 | `{ assetID }` |
| 行为 | 打开文件、大小 1..6MB、读取前后 stat 一致、magic 与 mediaType 一致，返回 base64 image + sha256 |
| 失败 | 非本轮可观察 asset / 读取期间变化 / 格式不符 |
| Native 升级 | 直读 live visual asset 句柄（与当前材料图像同一来源），不暴露路径给模型 |

## 4. `weibei_course_map`（host）

| 项 | 契约 |
|---|---|
| 执行侧 | Swift `StudyAgentHostToolRequest.courseMap` → `WorkspaceStore.executeAgentHostTool` |
| 权限 | 读 |
| 输入 | `{ itemID?, offset? ≥0, limit? 1..40 }` 默认 offset=0 limit=40 |
| Swift 边界 | itemID 必须能映射到本轮 persistentAssetID；offset 0..100_000 |
| 输出 details | `course_map`：catalog（含 jumpReference）、relations、total、hasMore、profile、isTruncated |
| Native | 调用同一 `executeAgentHostTool(.courseMap)`，禁止另写索引 |

## 5. `weibei_course_search`（host）

| 项 | 契约 |
|---|---|
| 执行侧 | Swift `.courseSearch(query, limit)` |
| 权限 | 读 |
| 输入 | `{ query: 1..500, limit?: 1..8 }` |
| 输出 | 命中条目 + evidenceLabels + jumpReferences + jumpEvidence |
| 副作用 | 把有 searchText 的 id 记入 `searchedCourseItemIDs`（后续提案证据白名单） |
| Native | 同一 host 方法；证据标签生成逻辑与现 `presentCourseResults` 对齐 |

## 6. `weibei_course_read`（host）

| 项 | 契约 |
|---|---|
| 执行侧 | Swift `.courseRead(itemID, query, location, cursor, maximumCharacters)` |
| 权限 | 读 |
| 输入 | itemID 必填；query/location/cursor 可选；maximumCharacters 1_000–12_000 |
| 作用域 | item 必须属于本轮 project.items 或先前 host 返回集 |
| 输出 | results + hasMore + nextCursor + sourceRevision；读到的 sourceRevision 供档案更新校验 |
| Native | 同一 host 方法 |

## 7. `weibei_web_open`（host）

| 项 | 契约 |
|---|---|
| 执行侧 | Swift `.webOpen` |
| 权限 | 读 |
| 输入 | `{ url: 1..2048, maximumCharacters?: 1000..20000 }` |
| 硬护栏 | URL 必须是用户本轮问题里明确出现的 HTTPS 地址（`WeiBeiWebResearchURLPolicy.isExplicitlyProvided`）；禁本机/局域网/脚本 |
| 输出 | `{ url, title, text, isTruncated }` 单页 |
| Native | 同一 policy + 同一打开实现 |

## 8. `weibei_read_learning_memory`

| 项 | 契约 |
|---|---|
| 执行侧 | TS 读快照 `snapshot.learning` |
| 权限 | 读 |
| 输入 | 空对象 |
| 前置 | 必须有 `project.courseID`，否则「学习记忆只在课程 Chat 中使用」 |
| 输出 | learning JSON（lastLocation 可带 jumpReference）；记下 `lastReadMemoryRevision` |
| Native 升级 | 调用 `WorkspaceStore.learningMemoryEntries(in:)` / `learningMemoryRevision(in:)` 等现有方法，不读提问前快照 |
| 复用目标 | `learningMemoryEntries(in:)`、`learningMemoryRevision(in:)`、`learningMemoryScope(courseID:)` |

## 9. `weibei_update_learning_memory`

| 项 | 契约 |
|---|---|
| 执行侧 | TS 校验后 details 回传；Swift `WorkspaceStore.applyLearningUpdate` **提案不自动落库** |
| 权限 | 写（用户确认后才落库；工具本身只产提案） |
| 输入 | contextRevision、memoryRevision、optional sessionSummary/suggestedPhase、suggestedNext≤3、entries≤12、resolutions≤12 |
| 校验 | 必须先读过记忆且 revision 匹配；证据前缀白名单；用户陈述必须 `[用户：本轮]`；位置证据只允许 progress/nextStep + agentInference |
| 空更新拒绝 | 五项全空则失败 |
| Native | 校验后走 `applyLearningUpdate` 同一套校验/应用；工具成功 ≠ 已写入 |

## 10. `weibei_course_profile_update`

| 项 | 契约 |
|---|---|
| 执行侧 | TS 校验 + Swift `applyCourseProfileUpdate` |
| 权限 | 写（提案） |
| 输入 | contextRevision、profileRevision、checkpoint 四选一、entries≤12、removedEntryIDs≤12 |
| 校验 | 有 courseID；本轮只能更新一次；revision 匹配；来源必须本轮真实读到且 sourceRevision 一致；不能空 |
| Native | 直读 live profile + 本轮已读 sourceRevision 集，应用走 `applyCourseProfileUpdate` |

## 11. `weibei_note_proposal`

| 项 | 契约 |
|---|---|
| 执行侧 | TS 校验；Swift 组装 `StudyAgentNoteProposal` |
| 权限 | 写（待确认，不写笔记） |
| 输入 | markdown 1..24000、evidence 1..16、contextRevision |
| 校验 | revision 匹配；每条证据必须以当前材料/笔记/选区真实来源标签开头 |
| Native | 证据标签从 live 已读集合生成；提案结构不变 |

## 12. `weibei_relation_proposal`

| 项 | 契约 |
|---|---|
| 执行侧 | TS 校验；Swift `StudyAgentRelationProposal` |
| 权限 | 写（待确认） |
| 输入 | noteItemID、sourceItemID、contextRevision |
| 校验 | 有 courseID；note.role=note 且 source.role=material；非同一条目；关系尚未存在 |
| Native | catalog/relations 直读 live store（`noteSourceLinks` 同源） |

---

## 工具执行管线（Native 必须对齐）

1. pre-execute：权限等级驱动 allow / deny / ask（ask fail-closed）
2. deny-only guard：课程 / Chat / 记忆隔离、目录越界、URL 政策、skill 路径
3. execute
4. 输出校验
5. post-execute（纠错回灌）
6. finalize 恰一次 → `tool/result` 入账

host 四工具的参数边界以 `PiAgentRuntime.hostToolRequest`（约 1523–1660 行）为准，不另发明一套。
