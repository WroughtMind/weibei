# Native 真实 App 提案冒烟失败报告

日期：2026-08-22  
分支：`codex/native-agent-runtime`（草稿 MR #285）  
状态：**实现未对齐产品路径，不是评测夹具问题。** 已停手，待 K3 查根因后再执行。

## 0. 结论（先看这）

用户按清单在真实 App 里验 Native 四条提案，**全部未过关**；最后一轮回答后会话窗口卡死、滑不动。

这不是 CLI 评测集、luna 题库或 judge 分数的事。账本证明 Native 工具链路没有把「模型提案 → `StudyAgentReply` 字段 → `WorkspaceStore` 待确认动作 → 用户确认后落库」接上。Pi 走的是同一套 Store 消费端；Native 在工具执行、详情回传、动作挂载三处都断了。

当前用户手里的包是 **`bf42650`**。之后有一笔未经验收的修订号修补 **`4a5e10d`**（只修了「数字 1 对不上修订号」这一层，**没有**把提案接到确认卡片/落库，也**没有**重打包）。

## 1. 现场

| 项 | 值 |
|---|---|
| 后端 | `defaults weibei.debug.studyAgentBackend = native` |
| 课程 | `02-经济原理导论`（PDF，第 1 页） |
| 活跃会话 | `978E465C-F8BF-499B-814F-AD8D9F555239` |
| Native 账本 | `~/Library/Application Support/WeiBei/NativeAgent/Ledgers/978e465c-f8bf-499b-814f-ad8d9f555239/ledger.jsonl` |
| 工作区 | `~/Library/Application Support/WeiBei/workspace.json` |
| 冒烟后 UI | `showAgent = false`，`agentSurface = hidden` |

清单要求：每条都是「先给建议、确认前不落库」。

## 2. 五轮对话（账本原文）

### 2.1 「记下复利进度，先给我看，不要直接改记忆」

工具：`weibei_learning_memory` → 空参数 `weibei_course_search`（结果 `items: []`）→ `weibei_learning_update` 参数 `{"contextRevision":1,"memoryRevision":1}`。

工具失败文案：`学习状态建议的上下文或记忆修订号不匹配`。

模型回复：写了拟记录草稿，并说还没改记忆。

### 2.2 「改动吧」

再次 `learning_memory` + `learning_update`，仍是 `contextRevision: 1`，再次失败。记忆未改。

### 2.3 「更新这门课的知识档案建议，我已掌握单利，复利还不熟。」

**没有调用** `weibei_course_profile_update`。模型把这句话判成学习状态、不是课程知识档案，拒绝提交。

### 2.4 「把『利率是资金使用价格』做成一条笔记建议，并给出证据句。」

1. `course_search` 空 query → 空结果  
2. `course_search` `query=利率 资金使用价格 单利 复利` → 命中 PDF `imported:a9167ab7-…`，带 `sourceRevision`  
3. `course_read` 参数 `{}`（无 itemID）→ 宿主报 **「这份资料不属于当前 Chat 的查询范围」**  
4. `weibei_note_proposal`：`contextRevision: 1`，`evidence` 是**字符串**不是数组 → `笔记建议的 contextRevision 不匹配`

模型回复：提交失败，把拟写正文写在聊天里。`workspace.json` 该条 **没有 `actions`**，所以界面上没有「写入笔记」确认卡。

### 2.5 「建议把这条笔记关联到利率课文，先给我确认。」

只调了 `course_search`。**没有** `weibei_relation_proposal`。模型说笔记还只是未写入提案、工作区没有笔记条目，不能关联。

落盘最后一条助手消息：无 `actions`、无 `richAnswer`、无 `sources`、无 `contentBlocks`。

## 3. 根因分层（实现，不是测试）

下面每一层单独就能让四条验收失败。它们叠在一起。

### A. 修订号：App 给的是字符串，模型回的是数字 `1`

App 组请求时：

```
contextRevision: "\(requestWorkspaceRevision):\(requestID.uuidString.lowercased())"
```

位置：`WorkspaceStore.swift` 约 16459 行。

Native `learning_memory` 原先只 JSON 编码 `StudyAgentLearningContext`（里面有 `memoryRevision: 1`），**不带本轮 `contextRevision`**。模型把 `1` 填进写入类工具。工具用 `as? String` 取参数，JSON 数字进不来，直接判不匹配。

`4a5e10d` 做了：系统提示写明本轮修订号、`learning_memory` 回传该字符串、拒绝用数字 `1` 冒充。  
**未在真实 App 验证。** 即便模型改回传字符串，B/C/D 仍会让提案看不见或落不了库。

### B. Native 工具成功了也不把提案字段交给 Store

`NativeAgentLoop.applySideEffects`（约 304–317 行）：

- `weibei_learning_update` 只填 `contextRevision` / `memoryRevision`，**丢掉 `entries`**。Store 的 `applyLearningUpdate` 对空 `entries` 等于没写。
- `weibei_course_profile_update` 的 `entries` **写死 `[]`**，`checkpoint` 还经常不是工具参数。Store 的 `applyCourseProfileUpdate` 没有来源条目就直接 return。
- 工具 `execute` 本身也没把 `entries` / `checkpoint` / `removedEntryIDs` 放进 `details`（对比 Pi `extension.ts` 2100–2193、2246–2450 行，details 是完整提案）。

也就是说：**校验通过 ≠ 魏碑收到一份可确认/可落库的提案。**

Pi 路径：工具 `details` → `PiRPCProtocol` 解码成 `StudyAgentLearningUpdate` / `StudyAgentCourseProfileUpdate` / `StudyAgentNoteProposal`。Native 缺这一截。

### C. 笔记确认卡只挂在「当前已有笔记」上

`WorkspaceStore.swift` 约 16498 行：

```
if let proposal = reply.noteProposal, let sentNoteItemID {
    actions.append(writeNote(targetItemID: sentNoteItemID, …))
}
```

没有 `sentNoteItemID`（用户在课程 Chat 对着 PDF 页聊、没打开一条笔记）→ **不生成 `AgentReplyAction`**。界面确认卡只渲染 `message.actions`（`NotesAgentView` 约 3266 行）。

确认写入 `confirmAgentNoteAction`（约 9117 行）还要求目标已是课程笔记文件。没有「确认后新建课程笔记」的路径。

关系同理：`createRelation` 需要已存在的 `noteItemID` + 材料 `sourceItemID`。笔记没落地，关联不可能成立。用户连续说「先提案再关联」、中间没有确认写入，产品上也必须定义：关联挂在待确认笔记上，还是必须先写入。

### D. Native 运行时没接课程档案 live store

`WorkspaceStore+NativeAgent.swift` 约 113–121 行：`NativeLiveStores` 只接了 `learning`，**没有 `profile`**。档案修订、已有条目、本轮读到的 `sourceRevision` Native 侧几乎是空的。Pi 有 snapshot 里的 `courseProfile` 和「只能引用本轮真实读到的材料」。

### E. 档案那条被系统契约劝退

`system.md` 把课程知识档案定义成「课程材料中的认识」，不是用户掌握程度。模型按契约拒绝调用 `course_profile_update`。清单却要求这条必须出档案建议。  
这是 **prompt/契约 vs 验收口径** 冲突，不是模型偶发偷懒。要验过，必须改工具描述或系统提示，让「用户要求更新档案」走提案，而不是直接拒。

### F. 空 `course_read` 误报查询范围

宿主 `courseRead` 在 itemID 对不上资料白名单时抛「这份资料不属于当前 Chat 的查询范围」（`WorkspaceStore.swift` 约 14872 行）。模型在已搜到条目后调用 `course_read` 却传 `{}`，被同一句错误盖住。`4a5e10d` 改为缺 itemID 时报「需要搜索结果里的 itemID」，并尝试用本轮已搜 ID 兜底。仍未实机验证。

## 4. 滑动卡住

用户原话：最后一次回答之后会话窗口卡住，滑不动，一直卡在那附件。

落盘能确定的：

- 最后一条助手消息**没有** `actions` / `richAnswer` / `sources` / `contentBlocks`，所以卡死时**并不是**已落盘的确认卡。
- 每条消息都带 `source = "02-经济原理导论，条目：3，第 1 页"`（当前阅读页作为上下文附件）。
- 冒烟结束后 `showAgent = false`、`agentSurface = hidden`，对话栏可能被收起或切走。
- 确认卡组件 `AgentReplyActionCard` 内有 **`TextEditor` 嵌在对话 `ScrollView` 里**（`NotesAgentView` 约 3854 行）。一旦卡片出现，子滚动抢父滚动是已知模式。这次失败路径没挂上 `actions`，所以**不能把这次卡死单归因于确认卡**，但修好 C 之后这个坑会变成必现风险，必须一并处理（例如禁止 TextEditor 抢滚动）。
- 对话行用 Markdown WKWebView；仓库里已有注释：WebView 高度回调会打乱滚动（约 1638 行）。最后一条是带标题的 Markdown，不能排除。

**未复现。** 不要当成已修复。K3 需要对着卡住的窗口看：是阅读页附件条、Markdown WebView、还是未落盘的瞬时附件层。

## 5. 已做 / 未做

| 项 | 状态 |
|---|---|
| 修订号写入系统提示 + `learning_memory` 回传 | 代码在 `4a5e10d`，仅自检，未重打包、未实机 |
| 提案 `entries` 进 `StudyAgentReply` | **未做** |
| Native 接 `profile` live store | **未做** |
| 无当前笔记时仍出「写入笔记」卡，确认后新建 | **未做** |
| 关联在笔记未写入时如何挂提案 | **未做** |
| 档案口径 vs 清单 | **未做** |
| 确认卡 TextEditor 抢滚动 | **未做** |
| 会话卡死实机复现 | **未做** |
| 用 `4a5e10d` 重打包给用户再验 | **未做** |

## 6. 建议 K3 查的顺序

不要先改评测题。按产品数据流查：

1. Pi 一条成功的「笔记建议 → 确认卡 → 写入」在 Store 里的字段长什么样（`reply.noteProposal`、`actions`、`sentNoteItemID`）。Native 缺哪一截。
2. `applySideEffects` 是否必须按 `PiRPCProtocol` 同样的 details 形状填 `StudyAgentLearningUpdate` / `StudyAgentCourseProfileUpdate`。
3. 无打开笔记时，Pi 真实 App 把笔记提案写到哪（当前笔记 / 新建课程笔记 / 只出正文不出卡）。Native 必须同一行为。
4. `applyLearningUpdate` / `applyCourseProfileUpdate` 是自动落库还是只挂待确认。清单写的是确认才写；若 Pi 本来就自动写，要写明产品口径，不能只改 Native。
5. 卡滚动：卡住瞬间的视图层级（对话 ScrollView、PDF 附件、WebView、TextEditor）。

## 7. 执行约束（给后续执行者）

- 仍是草稿 MR #285，不删 Pi，不改 `script/`，默认后端仍是 Pi。
- `WorkspaceStore.swift` 已被本任务占用；若必须改确认卡挂载/新建笔记，先在 MR 里写清占用。
- 未重打包前不要让用户再验，否则验的还是 `bf42650`。
