# 魏碑优化全量执行计划 v2（2026-08-27 定稿）

**性质：** 完整执行计划，17 项全做（含大手术），决策已锁定，交执行 agent 依序开工。
**上游依据：** `Docs/audit/2026-08-26-optimization-scan.md`（全景扫描，证据已复核属实）。
**本文档自包含：** 执行者无需会话上下文，按本文件从上往下做即可。

---

## 〇、已锁定的决策（不要再问，照此执行）

1. **记忆写入不立规矩**：删除 system.md 与工具描述里所有「先给我看」教学和禁令，不另写新规则。模型按自然理解处理。验收只描述现象：说「记下」就写入出标签；说「先给我看」就先展示、确认后写入。
2. **未落盘提示样式**：标题栏角落一枚小状态点 + 悬停看重试详情。不做大横幅。
3. **大手术全做**：第三梯队五项全部排期执行，不等体感痛点。
4. 计划文档、两份扫描文档、judge 报告 4 行残留：全部由**首个实现 PR（1.1）**带进 main，不单开文档提交。
5. **验收方式：一次性终验**——执行过程中**不打扰用户**，每刀以自动化验证为准（build/自检/定向测试/性能指标留档）；**全部 28 天完工后**，从最终 main 构建装配包、打开 App，交用户按第七节清单逐项验收。中途不安排任何用户实测环节。

## 一、执行者须知（环境规矩，每刀适用）

- **仓库**：`~/projects/魏碑`（远端 github.com/weibei-app/weibei，默认分支 main）。`~/Documents/魏碑` 是过时快照，**禁止**在那里开发。
- **开工姿势**：每刀从最新 `origin/main` 拉分支（`codex/<项名>`）；主 checkout 若被并行会话占用，则建独立 worktree。**一次只做一刀**，合入再做下一刀。
- **合并**：`gh pr merge <n> --merge --admin`。本机到 GitHub 的 HTTPS 经常瞬断：失败先查实际状态再重试，不代表操作没生效。
- **CI 红了先定性**：未触碰文件红 → fetch 看 main 是否已修（修了就变基 force-with-lease 重推）；idle snapshot 类时序抖动重跑即绿，**别改码**。
- **冻结守卫**：`Sources/WeiBei/Stores/WorkspaceStore.swift` 行数净增 ≤ 0；`Sources/WeiBei/Views/NotesAgentView.swift` 每 PR +50 行以内；新增自包含类型一律拆新文件。
- **核心面占用**：`WorkspaceStore.swift` 同一时间只允许一个未合 PR 占用。排期已按此错峰（见各刀「占用」），若实际执行顺序变动，自行保持此约束。
- **每刀验证底座**：`swift build` → `make check`（本地 Xcode 26.6，全套约 7 分钟）。性能项另加 `WEIBEI_PERF=1` 启动指标（`beginLaunch→finishLaunch`）与输入探针 `input.agent_to_next_main_queue_proxy`，改前改后各测一次留档。
- **交付验收：一次性终验**（决策⑤）。过程中执行者只做自动化验证：`swift build` → `make check` → 定向测试 → 性能指标留档；需要真机冒烟的刀由**执行者自己跑 App 验证**，不找用户。正因为用户只在终验才接触 App，**每刀自动化验证标准从严**：自检不过的刀宁可停下上报（见第八节），不带病往后走。终验构建按既有流程：从最终 main 构建 staged 包，`build_and_run.sh` 打开；交付前必验运行包含独有标记（防并行会话调包），dist 留副本。
- **红线**：identity/digest 永不用于拒绝访问（「文件即真相」）；0 个真实用户，一切老用户兼容包袱默认删；产品文案与验收受「无 AI 必须完整可用」约束。
- **搬家式拆分铁律**：只搬代码不改逻辑，严禁顺手重写。

---

## 二、总排期（工作日）

| 天 | 内容 | 产出 PR |
|---|---|---|
| D1 | 1.1 首刀：冷启动去全文件 SHA256（携带全部文档+judge 残留） | #A |
| D2 | 1.2 记忆写入不立规矩（半天）+ 1.4 侧栏订阅收窄（半天） | #B #C |
| D3 | 1.3 输入框隔离 + 卫生⑭探针清理 + 卫生⑮缓存上限 | #D |
| D4 | 2.1 重命名 identity 兜底 | #E |
| D5 | 2.3 SQLite 连接复用 | #F |
| D6–D7 | 2.4 init 同步瀑布拆分 | #G |
| D8–D9 | 2.2 未落盘状态点 | #H |
| D10–D12 | 3.1 WorkspaceStore 课程域拆分（分 2–3 个搬家 PR） | #I1–I3 |
| D13–D14 | 3.4 轮询 → FSEvents | #J |
| D15–D19 | 3.3 workspace.json 消息外置 | #K |
| D20–D24 | 3.2 聊天 WebView 卸载（原型先行） | #L |
| D25–D26 | 3.5 Agent 跨笔记检索工具 | #M |
| D27 | 卫生⑰图片孤儿回收（半天）+ 全量回归 | #N |
| D28 | 终验：全套指标复测 + 用户验收 | — |

- 合计 **约 28 个工作日**。卫生⑯（观察者移除）不占排期，搭任意触碰 `WeiBeiApp.swift` 的 PR。
- 可并行项：3.5 与 3.2/3.3 无文件交集，如开第二会话可在独立 worktree 并行（勿碰 `WorkspaceStore.swift` 的并行刀）。

大手术顺序理由（执行时勿随意调换）：3.1 先拆文件让后面每刀都快；3.4 改的正是 3.1 刚剥离的对账域；3.3 依赖 1.1/2.4 稳定后的启动路径且受益于 3.1 的瘦身；3.2 需要 D3 已落地的缓存上限与输入隔离；3.5 独立收尾。

---

## 三、第一波 · 快赢四刀（D1–D3）

### 1.1 冷启动去全文件 SHA256（首刀）｜D1｜分支 `codex/startup-digest-decouple`

**问题**：`WorkspaceStore.init` 主线程两次调 `refreshRuntimeItemURLs()`（`WorkspaceStore.swift:1040/1043`，行号随演进漂移，以符号定位）。其对每个带 `contentDigest` 的非笔记资料同步做全文件分块读取 + SHA256，不符即断链（`WorkspaceStore+LibraryRoot.swift:271-284` 的 `.present` 分支，注释自证笔记侧阶段 3 已拆、资料侧是最后残留）。库越大启动越慢；断链违反「文件即真相」红线。后台对账已具备 digest 刷新能力（`applyCourseFileObservations`），首帧后 3 秒内第一轮对账即到。

**步骤**：
- [x] `.present` 分支去掉 `snapshotFile` 哈希比对：文件在就保留路径，与笔记同待遇。
- [x] `absent` / `inaccessible` / iCloud 占位符（`presentUnmaterialized`）分支**不动**；瞬断容忍、灰态两周期保护全部保留。
- [x] `init` 两次调用保守保留（合并留给 2.4），只去哈希。
- [x] 测试迁移：新增资料版「外部修改不断链」用例（与 `TransientToleranceSafetyTests.swift:104` 的笔记版平行）；新增「对账采用外部新内容并刷新 digest」断言；核查 `ImportedIdentitySelfCheck` / `CourseProjectRootSelfCheck` 中依赖启动断链的用例改走对账路径。
- [x] 验证：`swift build` → 定向测试绿；`make check` 185/186，唯一失败为未触碰的 `testGenUIWheelInsideWebContentReachesConversationScroller`（本机 NSEvent 子类 type 0，与本刀无关、main 同源）；`WeiBeiSelfCheck` 绿。性能：20MB 全文件 SHA256 ≈ 8ms，init 两次调用则每份资料约 16ms 主线程 IO，本刀从启动路径移除。行为冒烟由自动化用例覆盖（外部改资料不断链 + 对账刷新 digest）。
- [x] **本 PR 携带**：本计划 + 扫描文档 `Docs/audit/2026-08-26-optimization-scan.md` + D1 方案 `Docs/plans/2026-08-26-startup-digest-decouple.md` + `Docs/audit/2026-08-22-eval-luna-low/独立judge评分报告.md` 的 4 行未提交补记。

**风险与回退**：外部换坏文件时用户点开才发现（与笔记现状一致；打开路径有 `PDFReaderOpenSafety` 等自有闸）。单 commit，revert 即回退。
**占用**：`WorkspaceStore.swift`（核心面）。
**终验口径**：资料多的库，打开 App 明显变快；外部改过的资料照常能打开新内容。

### 1.2 记忆写入不立规矩｜D2 上午

**问题**：system.md 第 9–10 条与两处工具描述把「先给我看」写成禁令/示范教学，等于另立一套规矩。决策①改为全部删掉，不立新规。

**步骤**：
- [x] 删除 `system.md` 学习记忆第 9 条整条，以及第 10 条里「先给我看」那组示范对话；其余与写入时机无关的条目保留并顺延编号。
- [x] 两处工具描述只删「先看拟写 / 不要直接修改 / 等待确认时不得调用」分句，其余原样保留。
- [x] 验收清单改为自然现象：说「记下」→ 写入出标签；说「先给我看」→ 先展示、确认后写入。不写必须/不得。
- [x] 改完 `system.md` 后 `swift build` 重建 bundle 产物。
- [ ] 真机冒烟改终验（决策⑤）：「记下进度」直接写入；「先给我看怎么写」先展示、确认后写入。

**占用**：无核心面。
**终验口径**：「记下进度」直接写入出标签；「先给我看怎么写」先展示、确认后再写入。

### 1.3 输入框 agentDraft 隔离｜D3｜携带卫生⑭⑮

**问题**：输入框直绑 `$store.agentDraft`（`NotesAgentView.swift:252`；@Published 在 `WorkspaceStore.swift:345`），每敲一字整棵 AgentPaneView（含每条消息一枚 WKWebView）参与更新；`onChange` 探针在 `:340`。长对话打字掉帧。

**步骤**：
- [x] 输入区抽成独立 ComposerView（**新文件**），内部 `@State` 持草稿，仅发送/切换会话时回写 store；消灭每键全树更新。
- [x] 会话切换时 seed 本地草稿，防丢已输入内容。
- [x] 卫生⑭：删除 `StreamFinalizeProbe` 及其接线。
- [x] 卫生⑮：`AgentFinalizedMarkdownHeightCache` 无界字典加 LRU 上限 256。
- [x] 卫生⑯：`SystemAppearanceObserver` 补 onDisappear 注销（本刀因拆除探针 harness 触碰 `WeiBeiApp.swift`）。
- [ ] 验证：探针 `input.agent_to_next_main_queue_proxy` 前后对比；50+ 条消息长会话打字帧率实测；`make check`。
- [x] NotesAgentView 净变化 ≤ +50（拆出 ComposerView 与高度缓存后为负）。

**风险**：草稿丢失时机（切换/崩溃）——seed 逻辑要有测试。
**占用**：WorkspaceStore.swift 仅触 :345 附近，与 1.1 错峰先后即可。
**终验口径**：长对话里打字跟手，不随历史变长而变卡。

### 1.4 侧栏 noteText 订阅收窄｜D2 下午

**问题**：`Sources/WeiBei/Views/CourseSidebarModel.swift:163-176` 订阅 `store.$noteText`，打字每 120ms `transientNoteMeta.removeAll()` + 全量 `rebuild()`（扫全部 importedItems 建投影），仅为刷新「标题取自正文」的条目。

**步骤**：
- [x] 订阅源从 `$noteText` 换成「标题相关签名」：仅当 `NoteTabDisplayTitle.bodyTitleLine` 变化才 bump `activeDraftToken` 并全量 `rebuild()`；正文其余改动忽略。
- [x] 验证：`testNoteBodyEditsDoNotRebuildSidebarUntilTitleLineChanges` 锁定正文改不动重建次数、首行变才重建且标题跟随。

**占用**：无核心面。
**终验口径**：写笔记时左侧列表安静，标题该更新的照样更新。

---

## 四、第二波 · 数据安全与稳定四刀（D4–D9）

### 2.1 重命名 identity `?? original` 兜底｜D4

**步骤**：
- [x] `Sources/WeiBei/Stores/WorkspaceStore+NotesPersistence.swift:272,317` 的 `?? original` 兜底改为确定来源，消除改名/移动后偶发对账与身份自愈异常（诗歌事故同类残留）。
- [x] 回归测试：改名 → 移动 → 对账 → 身份与课程归属不变；删除线/标签等附属信息不丢。
- **占用**：WorkspaceStore 侧扩展文件（非核心面）。
- **终验口径**：随便改名、挪笔记，都不会认错或丢东西。

### 2.2 未落盘状态点｜D8–D9

**步骤**：
- [x] 保存链路暴露 `lastPersistState`（saved / pending / failed）。
- [x] 标题栏角落一枚小状态点：saved 常灭（不抢注意力）；failed 点亮（暖色小圆点，符合「环境面平涂、操作件才浮起」的审美）；悬停显示「上次保存失败 + 重试按钮」；恢复保存后自动熄灭。
- [x] 写盘失败时内存草稿继续优先（现状），但**用户知情**；重试成功后才回到无感。
- [x] 测试：模拟写盘失败（只读目录/磁盘满桩），草稿不丢、状态机转换准确、恢复自愈。
- **占用**：`WorkspaceStore.swift`（核心面；与 2.4 已错峰）。
- **终验口径**：保存出问题时角落有提示，悬停能重试，不会再「假保存」。

### 2.3 SQLite 连接复用｜D5

**步骤**：
- [x] `Sources/WeiBeiCore/CourseDocumentSearchIndex.swift`：每次 lookup/index 开关一次库 → 长连接 + 忙超时；确认 WAL 模式。
- [x] 测试：并发 lookup/index 稳定性；多 store 共库不回退 #390 修过的竞态（`startsCourseFileMaintenance:false` 前提保持）。
- **占用**：无核心面。
- **终验口径**：课程搜索/查资料响应更快更稳，不再忽快忽慢。

### 2.4 init 同步瀑布拆分｜D6–D7｜前置：1.1 已合

**步骤**：
- [x] `WorkspaceStore.swift` init（约 :1022-1096，以符号定位）：首帧前只留最小可渲染状态；迁移/对账类工作挪后台。
- [x] 顺带合并 :1040/:1043 两次 `refreshRuntimeItemURLs()` 调用（1.1 刻意留下的可选项，此处同区域一次收掉）。
- [ ] 验证：`WEIBEI_PERF=1` `beginLaunch→finishLaunch` 与 1.1 的数据叠加对比留档；冷启动后立即操作资料/笔记无回退；`make check`。
- **占用**：`WorkspaceStore.swift`（核心面）。
- **风险**：后台化后时序敏感——瞬断容忍与灰态测试必须全绿再交付。
- **终验口径**：打开 App 更快出画面，出来的第一秒就能点。

---

## 五、第三波 · 大手术五项（D10–D26，全部执行）

### 3.1 WorkspaceStore 课程域拆分｜D10–D12｜分 2–3 个搬家 PR

**目标**：21761 行单文件（届时已因前序各刀变小）把课程文件/对账域机械剥离，恢复增量编译速度与可 review 性。
**步骤**：
- [x] 按符号（勿按行号）圈定第一块：课程文件维护/对账（`resolveCourseOwnedItems` … `startCourseFileMaintenance`）。第二块：课程库 CRUD / 导入 / 移动 / 共享 / 删除课 / 事务目录。第三块：课程可携带状态 / 课程笔记读写 / 可携带导出。
- [x] 第一块拆入 `WorkspaceStore+CourseMaintenance.swift`，**只搬不改**。搬后 `WorkspaceStore.swift` 20895 行（基线 21744）。
- [x] 第二块课程文件导入/资料管理拆入 `WorkspaceStore+CourseLibrary.swift`，只搬不改。搬后 `WorkspaceStore.swift` 14466 行（上一块 20895，−6429）。
- [x] 第三块课程可携带状态/课程笔记读写/可携带导出拆入 `WorkspaceStore+CoursePortable.swift`，只搬不改。搬后 `WorkspaceStore.swift` 12681 行（上一块 14466，−1785）。3.1 至此结束。
- [x] 本 PR 记录 WorkspaceStore.swift 行数：12681（基线 21744，累计 −9063）。冻结守卫净增 ≤ 0。
- [x] 第一块 SelfCheck 墓碑改为同时读新扩展文件（`?? activeCourseID ?? sourceItem` 仍为「不得出现」）。第二块同样让墓碑同时读 `WorkspaceStore+CourseLibrary.swift`。第三块同样让墓碑同时读 `WorkspaceStore+CoursePortable.swift`。
- **风险**：搬家丢代码——用逐符号对照 diff review，严禁顺手重构。
- **终验口径**：（不直接感知）此后每刀的交付节奏明显变快。

### 3.4 三秒轮询 → FSEvents｜D13–D14｜前置：3.1 已合（改的正是刚剥离的域）

**步骤**：
- [ ] 用 DispatchSource 文件系统监视替换 `startCourseFileMaintenance` 的 3 秒全量轮询（原 `WorkspaceStore.swift:18612-18633`，拆分后在课程维护扩展文件里）。
- [ ] 保留低频轮询兜底（60 秒一轮），防漏事件；自身写文件期间暂停监视防自触发。
- [ ] 测试：外部增/改/删课程文件在 2 秒内被对账捕获；空闲 10 分钟 CPU 采样对比留档。
- **风险**：事件丢失 → 兜底轮询保底；iCloud 占位符场景必须有测试。
- **终验口径**：挂机不再持续费电，外部改动照样很快被认出来。

### 3.3 workspace.json 消息外置｜D15–D19｜前置：1.1、2.4、3.1 已合

**问题**：全量会话消息正文内嵌主快照（`WorkspaceModels.swift:2040-2042`），每次 debounce save 全量重写（`WorkspaceStore.swift:21003-21051`）；启动 decode 与存盘随使用无限膨胀。
**步骤**：
- [ ] 新增会话消息存储：每会话一个独立文件（如 `Workspace/Sessions/<sessionID>.json`），主快照只留索引与元数据。
- [ ] 读取改懒加载：打开会话才读该会话文件。
- [ ] 保存改增量：只写脏会话文件 + 轻量主快照。
- [ ] **真实迁移**（用户本人数据在库，不可丢）：首次启动一次性搬家——先把 `workspace.json` 备份为 `workspace.json.pre-externalization`；搬迁后校验（会话数、消息数逐一对得上）通过才清空内嵌字段；校验不过则回滚用旧数据启动并报告。
- [ ] 测试：迁移正确性（大库夹具）、迁移幂等（二次启动不重搬）、单会话损坏只影响该会话且可兜底重建、`make check` 全绿。
- [ ] 验证：启动 `WEIBEI_PERF` 指标对比；长时间使用的库 debounce save 耗时对比。
- **风险与回退**：数据模型迁移，最高风险刀——每步可 revert，备份文件保底。
- **终验口径**：用得再久，打开和保存都不随聊天历史变多而变慢；旧聊天记录一条不少。

### 3.2 聊天 WebView 卸载策略｜D20–D24｜前置：D3 的缓存上限已合

**问题**：Eager VStack 挂载后永不卸载（`NotesAgentView.swift:1452-1456`），展开历史只增不减；每条消息一枚 KaTeX WebView。当年 Lazy remount 卡死是雷区，故先原型。
**步骤**：
- [ ] **Phase A 原型（独立 worktree，1–2 天）**：视口外保留上下 N 屏（N 可调，初值 3），更远消息换轻量占位（高度取自 `AgentFinalizedMarkdownHeightCache`）；临近时复挂载，走「骨架 + 淡入」过渡（禁样式不一致的内容预览）。验收：100+ 消息会话快速上下滚动无卡死、无白屏钉死；不过关就停手报告，不带病上线。
- [ ] **Phase B 落地**：flag 默认关 → **执行者自测**（100+ 消息会话滚动、打字、切会话冒烟全过）后才默认开；自测不过则保持关并在终验报告注明。用户终验在 D27–D28 一并做（决策⑤，中途不打扰）。
- [ ] 指标：内存占用前后对比（Activity Monitor / footprint 日志）留档；滚动 FPS。
- [ ] NotesAgentView +50 行约束：占位与窗口逻辑放新文件。
- **终验口径**：超长对话不再越聊越吃内存，滚动依旧顺滑。

### 3.5 Agent 工作区级检索工具｜D25–D26

**步骤**：
- [ ] 新增原生工具 `weibei_search_workspace`：级联检索——当前课程材料 → 跨课程笔记；**不含网页**（网页兜底仍在既有链路）。
- [ ] 护栏：默认课程隔离；仅当用户明确要求跨库（「我所有笔记里写过什么」）或问题明确跨课程时才广播全库；结果带来源课程 + 笔记标题 + 摘录。
- [ ] 更新 `system.md` 工具指引（注意：改 system.md 后须无条件重建产物并重建装配包——检查模式导出陷阱）。
- [ ] 测试：检索正确性、课程隔离护栏、空结果如实报告；按 luna eval 模式加一组评测夹具。
- **终验口径**：问「我笔记里写过 X 吗」能翻到其他课的笔记，并告诉你在哪门课。

---

## 六、卫生区收尾（搭车 + 独立小刀）

| # | 事项 | 时机 | 做法 |
|---|---|---|---|
| ⑭ | StreamFinalizeProbe 清理 | **D3 随 1.3** | 已删 |
| ⑮ | 高度缓存 LRU | **D3 随 1.3** | 上限 256 |
| ⑯ | SystemAppearanceObserver 对称移除 | **D3 随 1.3** | 补 onDisappear 注销 |
| ⑰ | 图片孤儿回收 | **D27 上午** | [x] 按 markdown 引用安全 GC（`MarkdownAttachmentGC.swift`）：只删「全库无引用且超过宽限期」的附件；换图/删段落写盘成功后触发；[x] 防误删测试（在用图片不收） |

---

## 七、终验：全部完工后一次性打开 App 交用户验收（D27–D28）

**这是整个计划中唯一的用户接触点（决策⑤）。** 此前一切由执行者自动化自验完成。

- [ ] 确认 17 项全部合入 main，工作树无残留改动；全套 `make check` 绿；本地 `swift test`（约 7 分钟）跑一遍留档。
- [ ] 汇总性能指标总表（各刀前后对比）：启动时间（1.1/2.4/3.3 叠加）、输入探针（1.3）、侧栏重建次数（1.4）、空闲 CPU（3.4）、长会话内存（3.2）、保存耗时（3.3）。
- [ ] 从最终 main 构建 staged 装配包：`build_and_run.sh` 打开 App；**开给用户前必验运行包含独有标记**（防并行会话调包），dist 留副本。
- [ ] 交用户一张逐项验收清单（每项一句人话 + 勾选框），覆盖全部用户可感知变化：
  1. 打开 App 明显变快（资料越多越明显）
  2. 外部改过的资料照常打开新内容
  3. 「记下进度」直接写入出标签；「先给我看怎么写」先展示、确认后再写入
  4. 长对话里打字跟手
  5. 写笔记时左侧列表安静，标题照常更新
  6. 笔记随便改名/挪动不丢东西
  7. 搜索响应又快又稳
  8. 模拟保存失败 → 角落小圆点亮 → 悬停可重试 → 恢复后熄灭
  9. 聊天记录一条不少（迁移后逐条核对）
  10. 用得再久，打开/保存不随历史变慢
  11. 超长对话内存不再只涨不降，滚动顺滑
  12. 挂机不再持续费电
  13. 问「我笔记里写过 X 吗」能翻到其他课的笔记
  14. 删掉带图段落后磁盘可回收（可选项，看得到占用下降即可）
- [ ] 用户验收中任何一项不过：记录复现步骤，按对应刀的风险与回退条款处理（单刀修复后重建包再验该项），不推倒整个计划。
- [ ] 验收通过后：更新本文件各刀勾选状态与终验结论（随收尾 PR 入库），销项。

## 八、中止与上报规矩

- 任一刀 `make check` 两轮修不绿 → 停，写清卡点上报，不带病推进。
- 3.2 原型滚动卡死复现 → 停在该 Phase，上报，不进 Phase B。
- 3.3 迁移校验不过 → 自动回滚旧数据启动，上报，不强行清空。
- 任何刀发现与扫描证据不符（行号漂移属正常，结构性不符才算）→ 停，重新侦察该刀再动。
