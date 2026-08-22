# Native Agent 真实产品链路修复方案

日期：2026-08-22
分支：`codex/native-agent-runtime`（草稿 MR #285）
执行：Grok；方案与复核：Kimi；拍板：用户
依据：`Docs/audit/2026-08-22-native-runtime-真实App冒烟失败报告.md` + 三路代码取证（Pi 契约 / Native 现状 / 提示词与渲染）

进度（2026-08-22 续）：F0–F8 已落地到工作树。Native 课程 catalog/search 的 itemID 与 Store 条目 ID 同一套持久 ID（`persistentAssetIDsByContextID` 是恒等映射），关系确认不再因临时 ID 必败。

## 0. 一句话根因

Native 对齐的是 CLI 夹具契约，不是产品契约。最底层是**工具 schema 失明**（只有 `required`、没有 `properties`，模型看不见参数形状），往上依次是 details 不完整、applySideEffects 丢提案、profile store 未接、reply 无来源聚合；再往上是两个 Pi 也存在的产品契约缺口（档案条款、无笔记不出确认卡）。CLI 全绿是因为 CLI 宿主接受了简化形状——评测环境通过 ≠ 产品链路接上。

契约基线（Native 必须逐字段对齐的 Pi 形状）：

- `learning_update`：details 必有 `contextRevision`(string)、`memoryRevision`(number)、`suggestedNext`(数组)、`entries`(数组)、`resolutions`(数组)（`extension.ts:2443`，`PiRPCProtocol.swift:501-592`）
- `course_profile_update`：details 必有 `contextRevision`、`profileRevision`(number)、`checkpoint`、`entries`、`removedEntryIDs`（`extension.ts:2186`，`PiRPCProtocol.swift:594-657`）
- `note_proposal`：details 必有 `markdown`、`evidence`(string[])、`contextRevision`（`extension.ts:2513`，`PiRPCProtocol.swift:472-485`）
- `relation_proposal`：details 必有 `noteItemID`、`sourceItemID`、`contextRevision`（`extension.ts:2591`，`PiRPCProtocol.swift:486-500`）
- Store 消费端：learning/profile **校验通过即自动落库**（`WorkspaceStore.swift:15093/15408`），笔记/关系挂 `AgentReplyAction` 待确认卡（`:16497-16523`）

## 0.5 设计原则：约束分两类（用户裁决 2026-08-22）

不搞防御性设计和机械约束。所有规则必须能归进「安全闸」，否则删除：

- **安全闸（保留，且只保留一处权威）**：防编造（证据必须来自本轮真实读到的内容）、防过期（修订号匹配）、防越界（课程/Chat 作用域、目录边界）。这些由 Store 消费端在落库前统一把守（现状已有），Native 工具层**不再复制第二道**。
- **机械闸（删除，且不从 Pi 复制到 Native）**：更新时机四节点、`每轮只能更新一次档案`、entries ≤12、evidence ≤16 条、一条回复只允许一个提案、checkpoint 枚举当闸口用——这些是替模型做判断，全部废除。该不该更新、更新几次、写几条，由模型决定。
- **工具层只保留类型级校验**：参数存在、类型正确（schema 有 properties 后的自然结果）。业务错误的唯一来源是 Store 的真实回执，失败原因如实回喂模型，让它本轮自行重试——反馈回路代替防御墙。

对齐 Pi 的口径因此收窄为：**对齐数据形状（details 字段、回复字段），不对齐 Pi 的机械限制。**

## 1. 工作项（按依赖序，F0/F1 最优先）

### F0 验收清单口径修正（先于一切修复）

取证发现清单草稿本身写错了：记忆与档案更新在**真实产品里本来就是自动落库**（`applyLearningUpdate`/`applyCourseProfileUpdate` 校验通过即写，UI 只挂信息标签，`WorkspaceStore.swift:15359` 注释明确写了不再走确认条）；只有笔记/关系走确认卡。清单却要求四条都「确认前不落库」——不修它，native 做得和 Pi 一模一样也验不过。

- 改 `Docs/audit/2026-08-22-native-runtime-用户验收清单草稿.md`：记忆/档案两条的「应该看到什么」改为「回答下方出现已更新的信息标签；不需要确认」；笔记/关系保持确认卡口径。
- 这不是放低标准，是把标准对齐到真实产品行为。

### F1 工具 schema 补全 + 类型级入参校验（根因）

- 把 `NativeAgentTools.swift` 全部工具的 schema 补齐 `properties`（名称、类型、枚举），逐字段对照 `extension.ts` 四个提案工具 + 宿主工具的参数定义。
- `NativeToolRegistry.execute` 只做类型级校验（required 存在、类型对、枚举值合法），失败抛带具体字段名的 `NativeLLMFailure`，让模型能带着正确信息重试。**不加任何业务规则**。
- 附带修：`course_read` 缺 itemID 的兜底从「字典序最小」改为「本轮最近命中」（4a5e10d 的兜底方向对，选取规则错）。
- 验收：自检新增「schema 含 properties」「错类型参数报字段名」；12 场景脚本保持绿。

### F2 details 完整化 + applySideEffects 对齐解码

- 四个提案工具的 execute 返回完整 details（形状见 §0 基线）。修订号在 execute 时比对现值，**唯一目的是当场把失败回喂模型让它本轮重试**，不是防御墙；落库权威仍在 Store。
- `NativeAgentLoop.applySideEffects` 按 `PiRPCProtocol.swift:472-657` 的解码逻辑把 details 解成四个 `StudyAgent*` 类型，entries/resolutions/checkpoint/suggestedNext 等一个字段不许丢。方式二选一：把 PiRPCProtocol 的四个解码器抽成共享函数两侧复用（推荐），或 Native 复刻并配契约夹具测试。
- **机械限制一律不复制**（每轮一次、条数上限、单提案限制、先读记忆才能写的闸门）。条目真实性（memoryID 现存、evidence 前缀匹配）由 Store 现有闸口独立把守，Native 工具层不加第二道；但 Store 会拒绝的规则必须写进工具描述，让模型一开始就不踩。
- **evidence 格式规则必须写进 schema/描述**：Store 闸口要求 `userStatement` 条目的 evidence 以 `[用户：本轮]` 开头、材料证据以本轮来源标签开头（`applyLearningUpdate` 的 `StudyAgentCurrentTurnEvidence.matches`）。模型不知道这个格式就会构造出"看着对、被 Store 静默丢弃"的提案——Q10/Q11 的「上下文版本不匹配」只是这类静默丢弃的第一种， evidence 格式是第二种。
- **先查明 ID 性质再动 relation/note**：Native 课程 catalog/search 结果里的 itemID 是持久条目 ID 还是本轮临时 ID？Pi 有临时→持久映射层（`PiAgentRuntime.swift:2401-2405`，`persistentAssetIDsByContextID`），`confirmAgentRelationAction`/`confirmAgentNoteAction` 要求持久 ID 存在于 `allItems`。若 Native 给的是临时 ID，提案即使挂卡确认也必败——这是目前未探明的隐藏断点，F2 第一步先回答它。
- 验收：自检模拟「工具 details → applySideEffects → StudyAgentReply」，断言 entries 逐字段保真。

### F3 接 profile live store

- `WorkspaceStore+NativeAgent.swift:113-121` 把 `NativeLiveStores.profile` 接上（对齐 Pi snapshot 的 courseProfile：修订号、已有条目、本轮 readCourseSourceRevisions）。
- 验收：自检断言 native 运行时拿到的 profile 上下文与 Store 现值一致。

### F4 reply 全字段对齐（不止 sources）

- 做一次 `StudyAgentReply` 全字段 parity 审计：Pi 在 `PiAgentRuntime.swift:2551-2564` 填了什么，Native 在 `NativeStudyAgentRuntime.swift:102-113` 就得起齐什么——`sources`、`contentBlocks`、`richAnswer`、`toolTrace`、`memoryUpdate`，逐字段给结论。
- `sources` 必接：宿主工具命中（search/read 的 itemID + sourceRevision + 标题）聚合成引用 chips，真实 App 回答下方必须出现来源。
- `visualize` 产物必须通到真实渲染路径（这是线上已有的技能，不是 GenUI 考核范围的问题）；`contentBlocks`/`richAnswer` 其余缺口能补则补，补不了的在报告里写明差异与理由。

### F5 档案契约扩展（用户已拍板：扩展，且放宽判断权）

用户裁决（2026-08-22）：必须接受自述掌握状态；并明确哲学——**契约管安全（防编造、防过期、防越界），不管"该不该更新"的判断，时机交给模型**。现状三重拦截：system.md:144/146/147 定义+触发节点不含用户要求、:154 把掌握状态划给学习记忆、Store 闸口（:15458）要求每条目带材料来源。**Pi 同样如此**，改它 = 改产品契约，两侧同步。

- `system.md`：档案定义扩为「材料认识 + 用户自述掌握状态（标注为用户自述）」；删除/弱化四节点硬限制，改为「用户明确要求时必须提案；其余时机由模型判断，自述状态按用户原话记录」。
- `extension.ts:2110-2115` checkpoint 枚举加 `userRequested`（其余枚举值保留作分类用，不作闸口）；Native schema 同步。
- 两侧工具描述加「用户明确要求时必须提交建议；自述掌握状态不要求材料来源」。
- Store：checkpoint 为 `userRequested`（或条目标注用户自述）时放行空 sources 条目（或新增 entry kind，注意 Codable 兼容）。
- 注意：此改动后 Pi 不再是档案条款的不变基线，对拍报告 §3 需加注。

### F6 无打开笔记时的确认卡（用户已拍板：新建路径）

采用 D2a（超 Pi 基线的新能力）：`AgentReplyAction.writeNote` 支持 `targetItemID = nil` 语义 = 确认后在本课程新建笔记；确认卡照常渲染（标题+正文可编辑）；确认走 `persistAgentActionNote` 的新建分支。关系提案规则定为「只能挂已落库笔记；笔记还是提案时，agent 应说明先确认写入」——写进 system.md 和 relation 工具描述。

### F7 滚动卡死：预防随 F6 同提交，复现协议常备

- 预防（必做，**并进 F6 同一提交，不许晚于确认卡能出现的时刻**）：确认卡 `TextEditor`（`NotesAgentView.swift:3854`）加 `.scrollDisabled(true)`（或等价固定高度+内滚），全仓目前没有任何 scrollDisabled，提案卡一旦常现就必踩。
- 复现协议：下次冒烟若再卡死，用户不强制退出，先 `sample <pid> 5` 取栈（主线程停在 sizeThatFits/WKWebView 回调 = 高度链；停在 selection publish = 附件层）。Grok 在 WeiBeiPerf 加 `webview.markdown_height_accepted/ignored` 计数输出口。
- 嫌疑排序（取证结论）：① Markdown WebView 高度链（可见行永不冻结，`:4995-4997`）② 选区附件防抖+发送摘除（`WorkspaceStore.swift:711/:16384`）③ 来源行 publish 扇出。

### F8 真实路径回归测试（流程修复，防再犯）

CLI 全绿但 App 全断，缺的就是这一层。WeiBeiSelfCheck 新增「真实链路」检查：用真实字符串格式修订号构造请求 → 跑四提案工具 → applySideEffects → StudyAgentReply → 用夹具 Store 状态跑 `applyLearningUpdate`/`applyCourseProfileUpdate`/动作挂载条件，断言：记忆真的写入、档案条目真的变化、writeNote/createRelation 动作真的生成。**这条测试如果在冒烟前存在，本次失败会全部被它拦住。**

实现方式先探明再动手（写在 MR 里）：能否在 WeiBeiSelfCheck 进程里直接驱动 WorkspaceStore？若它牵扯 App 态过重，就把四条 guard/apply 逻辑抽成 WeiBeiCore 里的可测纯函数层，App 与自检共用——这顺手治了「消费逻辑长在 16k 行单例里」的架构病。若抽取代价实在过大，最低限度 = applySideEffects→Reply 逐字段断言 + 用真实格式修订号对 Store 各 guard 条件的复算测试。

流程规矩（本次教训）：任何修复后必须重打包，且设置页能看到的构建标识（版本/提交短哈希）随包更新；用户验收前先核对包标识与 MR 头提交一致，杜绝「验的是旧包」。

## 2. 执行顺序与验收门

0. F0 验收清单口径修正（文档，十分钟）
1. F1 → F2 → F3 → F4（引擎契约对齐，纯代码，每步自检+12 场景绿）
2. F8（真实链路测试先写红再转绿，证明 F1–F4 真接上了）
3. F5 / F6+F7（用户已拍板；F5 需同步 extension.ts；F7 防抢滚动并进 F6 同一提交）
4. 重打包（含构建标识）→ 用户按修正后清单四条 + 滚动观察复验

每步进草稿 MR #285；`WorkspaceStore.swift` 本任务已占用；F5 触碰 `extension.ts`/Store 消费端、F6 触碰 `WorkspaceStore.swift:16497` 挂载段和 `confirmAgentNoteAction`，都在 MR 里逐条声明。不改 `script/`、不删 Pi、默认后端不动。

## 3. 拍板后给执行者的验收口径

- 四条提案在真实 App（native 开关开）逐条过：记忆（自动落库+信息条）、档案（自述状态可落库且标注用户自述）、笔记（确认卡→确认→落库）、关系（笔记落库后→确认卡→确认→落库）；
- 回答带来源 chips；滚动不卡；
- WeiBeiSelfCheck 含 F8 新检查全绿；12 场景、能力三件套保持绿。
