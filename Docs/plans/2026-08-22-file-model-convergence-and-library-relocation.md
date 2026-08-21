# 魏碑文件模型收敛与资料库迁移入口 总体实施计划

**版本：** 2.0（细化执行步骤）
**日期：** 2026-08-22
**文档性质：** 任务一（资料库迁移入口）与任务二（文件模型收敛）的产品与工程执行计划
**状态：** 已经三份独立对抗性审查修正 + 零体验回退约束；不代表授权合并、打标签、发布

---

# 0. 一句话本质

> **文件就是文件，文件夹就是文件夹。App 只是访问它们：外部爱怎么改就怎么改，App 都采用；App 自己要写回时，先比一次再动笔；任何销毁动作之前，先留副本。**

## 0.1 第一约束：零体验回退

**任何阶段合入后，用户体验不允许有任何回退。** 六条可验收指标：

1. **可见性不回退**：用户需要知道的状态（笔记不可用、写冲突、库不可用）仍能在使用现场明确看到——从"主动弹横幅"改为"条内状态"，绝不静默消失；
2. **数据安全不回退**：防丢能力只升不降；新机制通过 8/12 事故全场景回归之前，旧锁一道不拆；
3. **编辑不回退**：光标下内容被换/被冲的可能性为零（现有 dirty 守卫全部保留）；
4. **性能不回退**：比对只发生在写回与采用两个低频时点，不引入逐键/逐帧开销；
5. **功能不回退**：多机搬运、搜索索引、Agent 读写授权、崩溃恢复全部保功能；
6. **可逆**：每阶段独立可发布；任一阶段验收发现回退即该阶段回滚，不影响已合入部分。

每个阶段的 PR 必须附"回退自查表"，逐条对照上述六条作答。

---

# 1. 背景与审查结论

## 1.1 病灶

8/12 诗歌笔记事故（读盘失败→模板被当正文写回）后层层补丁，形成互相矛盾的锁：启动检查"指纹对不上就切断链接"（`WorkspaceStore+LibraryRoot.swift:245-249`）与 3 秒对账"指纹对不上就以文件为准"判决相反；P0 降级、重命名哨兵、分叉修复、快照回放各自带独立判定。用户库在 iCloud 同步目录，瞬断周期性触发误报。

## 1.2 三份对抗性审查的硬性修正（全部并入设计）

1. 写回比对必须下沉到**唯一底层写函数**，规则补齐：重读失败或无基线 ⇒ 拒写并保留待写内容；摘要不符 ⇒ 待写内容先入备份环再采用磁盘。rename 直写（`WorkspaceStore+NotesPersistence.swift:217`）、repair 直写（`:584`）、retry（`:476-500`）、agent 写笔记全部经此函数。
2. **销毁前副本先行**：采用外部内容、删除条目、丢弃未落盘输入、冲突选边之前，将销毁内容先写入备份环（`NoteBackupRing.capture(content:)` 收内存字节）。同时修复审查发现的两个现状漏洞：外部删除正在编辑的笔记丢未落盘输入（`WorkspaceStore.swift:7797-7804`）；冲突条选「使用磁盘版本」销毁 checkpoint（`WorkspaceStore+NoteEditing.swift:236-238`）。
3. 崩溃恢复的 baseFileDigest 三态判别（`WorkspaceStore+NoteEditing.swift:296-309`）不得简化。
4. 可携带快照 revision/payload 双校验（`CourseProjectRootSupport.swift:535-573`）维持不动——它本身就是防双机互盖的 compare-before-write。
5. **iCloud 占位符必须新增识别**：扫描 `.skipsHiddenFiles`（`CourseProjectRootSupport.swift:2652`）看不见 `.名字.md.icloud` → 误判删除 → 条目连同草稿与元数据被清（`WorkspaceStore+GoneImportedItems.swift:29-34` → `WorkspaceStore.swift:7796-7821`），周期性丢数据。
6. 三本 digest 账区分：`.common` 共享项 `contentDigest` 是可携带完整性闸（`CoursePortableState.swift:381-393`）必须保持刷新；`noteBackingContentDigestsByItemID` 是 Agent 落盘确认（`WorkspaceStore.swift:9602`）与崩溃恢复基线必须保留；弱化的只是"拿 digest 当信任判决去切断"。
7. `importedFileIdentity` 必须持续刷新（Agent 授权 `WorkspaceStore.swift:13896-13906`、搜索索引 `CourseDocumentSearchIndex.swift:115-134`、Pi 扩展 `extension.ts:739-750,1516-1555` 强制要求），但只用于找回不用于拒绝。
8. 资料项（PDF 等）"世代不同即断链"保留：删除重建的资料不得继承旧 itemID 的阅读位置/学习记忆（`ImportedIdentitySelfCheck.swift:3254-3261` 锁定）。

## 1.3 审查确认可安全拆除（修正落地后）

模板形态启发与模板守卫、重命名哨兵、启动分叉修复例程（`WorkspaceStore+NotesPersistence.swift:502-639` + `Sources/WeiBeiCore/NoteDivergenceRepair.swift`）、启动指纹断链（笔记部分）、`PendingNoteWriteState.baselineContentDigest`（纯写无读账）。

---

# 2. 目标与非目标

**目标**：Finder 里增改删文件 App 都采用、可用、不报警；全 App 一种哲学"文件即真相"；任何销毁前必有副本；iCloud/网盘瞬断零误报；代码净减少（拆多于增）。

**不做**：不碰笔记 Markdown 格式、Agent 能力、界面视觉；不删多机搬运能力；不做 iCloud 专用同步逻辑；不改变写回成功路径性能。

---

# 3. 设计原则（最高裁决）

1. 文件即真相：外部增删改一律采用，无"记录为准"的判决点；
2. 不主动报警：一时读不到→静默重试；只在用户实际使用时显示状态；永不出现定时/启动横幅；
3. 一道锁：所有写盘共用一个底层写闸门；
4. 副本先行：任何销毁动作之前先写备份环；
5. 身份只用于找回不用于拒绝；
6. 笔记与资料区别对待。

---

# 4. 任务一：设置中的「资料库位置」迁移入口

分支：`codex/library-location-setting`（从最新 `origin/main` 拉，当天推送建草稿 PR）。

## 4.1 产品行为（逐屏）

- 设置「通用」区新增一行「资料库位置」：左为标题，右为当前完整路径（截断显示，悬停见全）+「更改…」按钮；
- 点「更改…」→ `NSOpenPanel`（仅选目录）→ 选中后弹确认框：显示「从 X 迁移到 Y」、预计文件数与体积、警告"迁移期间请勿操作 App"；
- 确认 → 行内进度条（迁移中禁用一切设置交互）→ 成功：路径更新 + 短暂成功提示；失败：红色错误条 + 原路径不变；
- 目标位于 iCloud/网盘同步目录（判定：路径含 `Library/Mobile Documents` 或常见云盘目录名）：确认框内多一句黄色提示，不阻止；
- 迁移期间：写回、3 秒对账、课程笔记加载全部挂起；正在编辑的笔记先正常落盘再开始搬。

## 4.2 实现步骤（按提交顺序）

**第 1 步：`migrateLibrary(to:)` 核心方法**（新代码全部落在 `WorkspaceStore+LibraryRoot.swift`，不碰冻结文件）：

```
func migrateLibrary(to destination: URL) async throws -> LibraryMigrationResult
```

1. 前置校验（任一不满足则抛出带用户文案的错误）：
   - destination 不在当前库内部、不是当前库的上级、不等于当前库；
   - destination 存在且非空：若含合法魏碑课程清单（`.weibei/course.json`）→ 抛 `.destinationIsLibrary`（UI 改走「认领」流程并明确提示）；否则抛 `.destinationNotEmpty`；
2. `flushPendingNotePersistence` 落盘当前编辑 → 置 `libraryMigrationInFlight = true`（写回/对账/课程笔记加载检查此标志挂起）；
3. 同卷（`st_dev` 相同）：`FileManager.moveItem(libraryRoot, destination)`，原子完成；
   跨卷：逐个顶层条目 `moveItem` 到临时目录 `destination-weibei-migrating`，全部成功后 `moveItem(临时目录, destination)`；任一失败 → 已搬的搬回 → 抛错；
4. `applyBoundLibraryRoot(destination, identity:, bookmark:)` 重绑 → `refreshRuntimeItemURLs()` 重扫 → 逐课程校验 `courseManifestCourseID` 全部匹配；
5. `libraryMigrationInFlight = false` → 持久化 → 记 `WeiBeiLog`（阶段码 + 结果码，不记路径隐私）。

**第 2 步：设置 UI**（`SettingsView.swift` 新增设置组，复用现有 `settingsGroup`/`compactMenu` 模式）：

- 路径显示行 +「更改…」按钮 + 确认对话框 + 进度/错误呈现；
- 迁移中状态绑定 `libraryMigrationInFlight`，禁用按钮与相关设置项；
- 「认领已存在的库」流程：同一面板，检测到目标是合法库时确认框文案改为「认领此位置的现有资料库？」，确认后走 `bindLibraryRootOnThisComputer` 同款校验 + `applyBoundLibraryRoot`，不做文件移动。

**第 3 步：测试**（`Tests/WeiBeiSafetyTests/` 新增 `LibraryMigrationSafetyTests.swift`）：

- `migrateLibraryMovesTreeAndRebinds`：临时双目录，迁移后全部课程/笔记/材料可打开、原目录消失、绑定指向新位置；
- `migrateLibraryRejectsNestedAndNonEmpty`：目标嵌套/非空拒绝且原库不动；
- `migrateLibraryAdoptsExistingLibrary`：目标是合法库走认领，无文件移动；
- `migrateLibraryFailureKeepsOriginal`：注入移动失败（只读目标），原库原绑定纹丝不动；
- `migrateLibrarySuspendsAndResumesServices`：迁移中写回挂起、完成后恢复；
- 迁移涉及文件移动/删除，以上即仓库完成定义要求的专项自动验证。

**第 4 步：验证与冒烟**：

```
swift build
swift run WeiBeiSelfCheck
swift test --filter LibraryMigrationSafetyTests（CI 执行，本机无 Xcode）
./script/check_file_growth.sh <base> <head>（确认冻结文件零增长）
```

CI 绿后打候选包，用户真实冒烟：设置里把库迁到 `~/魏碑资料库-迁移测试`，确认笔记全部可开后迁回。

## 4.3 共享核心面占用登记

预计 `SettingsView.swift`（接线）、`Tests/`（新测试文件）、可能 `WeiBeiSelfCheck/main.swift`（若加源码断言）——PR 中登记，合并即释放。

---

# 5. 任务二：文件模型收敛（五阶段，顺序推进，各自独立分支/PR/验收）

## 阶段 0：行为基线冻结

分支 `codex/filemodel-phase0-baseline`。

1. 跑全量现有测试确认绿（记录基线清单）；
2. 新增两个**当前必失败**的测试（标注为预期失败，不进 CI 门槛，阶段 2 转正式）：
   - `externalDeleteKeepsUnsavedInput`：编辑中外部删除文件，未落盘输入应可从备份环找回（现状：直接丢）；
   - `useDiskConflictKeepsUserVersion`：冲突条选「使用磁盘版本」后，用户版本应可从备份环找回（现状：checkpoint 被删）；
3. 在 `WorkspaceStore.swift:17987-17992`（repair→retry 顺序锁）等关键约束处补注释引用本计划；
4. 验收：`swift build` + `swift run WeiBeiSelfCheck` 绿，零行为变化，回退自查表全 N/A。

## 阶段 1：底层写闸门（核心锁）

分支 `codex/filemodel-phase1-write-gate`。

1. 在 `WorkspaceStore+NotesPersistence.swift` 的 `writeNotebookMarkdown`（:420-422，全仓唯一底层笔记写盘函数）内置比对：
   - 入参增加 `expectedBaseline: String?`（调用方传入自己认为的磁盘基线 digest）；
   - 写前重读磁盘 digest：**重读失败或 baseline 缺失 ⇒ 抛 `.writeRefusedKeepContent`**（调用方保留待写内容到草稿/恢复仓）；
   - **重读 digest ≠ baseline ⇒ 先将待写内容 `NoteBackupRing.capture(content:)`，再抛 `.diskChangedAdoptDisk`**（调用方改为采用磁盘内容并刷新编辑器）；
   - 一致 ⇒ 原子写，写后刷新 `noteBackingContentDigestsByItemID` 与 `lastSelfWrittenNoteDigestsByItemID`；
2. 全部写路径强制经此函数并传基线：
   - `persistNote`（现 `writeNoteMarkdownTriple` :692-759 改为薄封装，模板守卫此阶段保留并存）；
   - rename 标题改写（现直写点 :217 改走闸门；rename 的身份偷换回滚 :183-211 与写后校验 :218-230 保留）；
   - repair restoreDraft（:584）、`retryRestoredPendingNoteWrites`（:476-500）、`persistAgentActionNote`（`WorkspaceStore.swift:9586-9607`）；
3. 源码断言（`WeiBeiSelfCheck/main.swift`，SAFETY 前缀）：禁止出现绕过 `writeNotebookMarkdown` 的新笔记写盘点（对 `notebookMarkdownWriter(` 直接调用做白名单制）；
4. 新测试 `WriteGateSafetyTests.swift`：无基线拒写、重读失败拒写、摘要不符副本先行且采用磁盘、四条写路径全覆盖、kill 模拟原子性；
5. 验收：CI 绿；用户冒烟：正常编辑一条笔记（应无感）、用外部编辑器改同一文件后在 App 里继续编辑（应看到磁盘内容被采用且自己的输入在备份中）；回退自查表逐条作答。

## 阶段 2：副本先行与外部删除保护

分支 `codex/filemodel-phase2-backup-first`。

1. 采用外部内容前副本先行，接入点：
   - 对账 `applyCourseFileObservations` 刷新条目时（`WorkspaceStore.swift:17899-17914`）；
   - `scheduleCourseNoteLoad` 静默采纳磁盘时（:18661-18674）；
   - `refreshActiveNoteFromBackingFile`（:18752-18807）；
   - 判定源统一为「存在未落盘内容」：`notesByItemID[id] != nil || pendingNotePersistenceByItemID[id] != nil || 编辑器 dirty checkpoint 存在`；
2. 外部删除保护：
   - `applyCourseFileObservations` 的 gone 判定（:17866-17872）不再直接 `forgetGoneImportedItem`：文件缺席时条目置 `fileMissingSince = Date()` 灰态保留；连续两个对账周期（≈6 秒）仍缺席才走 `removeItemRegistration`，且移除前对未落盘内容副本先行（修 `WorkspaceStore.swift:7797-7804`）；
   - 灰态条目在列表显示「文件不存在」；期间文件重新出现 → 按相对路径认领回**同一 itemID**，关联/阅读位置/配对不丢（修"撤销变新条目"问题）；
3. 冲突条修复：`resolveNoteEditorRecoveryConflict(useDisk: true)`（`WorkspaceStore+NoteEditing.swift:233-255`）执行前先把用户版本 `NoteBackupRing.capture(content:)`，按钮副标题注明「魏碑中的修改已存入备份」；
4. 阶段 0 的两个预期失败测试转正式（现在应通过）；新增 `goneItemGraysAndReclaims`、`goneItemRemovalBacksUpDraft`；
5. 验收：CI 绿；用户冒烟：编辑中在 Finder 删除该笔记（输入不丢、条目灰态）、Cmd-Z 放回（原样回来）、制造一次冲突选「使用磁盘版本」（自己的版本可找回）；回退自查表。

## 阶段 3：容断与 iCloud 占位符

分支 `codex/filemodel-phase3-transient-tolerance`。

1. 占位符识别（`CourseProjectRootSupport.swift` 扫描层，:2652 附近）：
   - 目录枚举不再一刀切 `.skipsHiddenFiles`；对 `^\..+\.(md|markdown|pdf|html)\.icloud$` 形态的项还原为逻辑路径 `名字.md`，标记 `isMaterialized = false`；
   - `entryPresence` 对逻辑路径：实体不存在但占位符存在 ⇒ 新 case `.presentUnmaterialized`，**永不判 absent**；
2. 展示：占位符条目正常显示；用户点开 → `Data(contentsOf:)` 触发系统下载，期间编辑器空态显示「正在从 iCloud 下载…」；下载失败/超时 ⇒ 条内状态「当前不可用，iCloud 文件未下载」，不弹横幅；
3. 删除启动指纹断链（`WorkspaceStore+LibraryRoot.swift:245-249` 的笔记部分）：digest 不符不再 `urlPath = nil`；资料项（非笔记）世代保护保留为：重建文件世代不同（identity 不匹配且 manifest 不符）→ 按新条目处理，不继承旧 itemID 进度；
4. `setNoteFileError` 的 `showImportantOperationError` 通道在笔记不可用场景降格为条内状态（阶段 2 灰态机制复用）；`showImportantOperationError` 本身保留给其他真实重要错误；
5. 新测试 `TransientToleranceSafetyTests.swift`：占位符识别、占位符不被判删除、瞬断无横幅、资料世代保护、启动无断链；
6. 验收：CI 绿；用户冒烟：把库放在 iCloud 目录（本机现状）重启三次、强制驱逐一个文件后打开它；回退自查表。

## 阶段 4：冗余锁拆除与测试重构

分支 `codex/filemodel-phase4-guard-removal`。前置：阶段 1-3 全绿；显示层确认"读失败时 `noteText` 永不出现模板内容"。

1. 拆除（按序）：
   - 模板形态启发 `NoteTemplateShape` 与模板覆盖守卫（`WorkspaceStore+NotesPersistence.swift:703-729`，已被写闸门严格覆盖）；
   - 重命名哨兵（:137-152）；
   - 启动分叉修复例程（:502-639 + `Sources/WeiBeiCore/NoteDivergenceRepair.swift` + `main.swift:2098-2260` 自检）；`retryRestoredPendingNoteWrites` 改走写闸门（消除 repair→retry 顺序依赖，删除 :17987-17992 顺序注释）；
   - `PendingNoteWriteState.baselineContentDigest`（`WorkspaceModels.swift:1883-1889` 及全部读写点）；
2. 测试重写（清单见 §6）；侧栏令牌剔除 digest 分量（`CourseSidebarModel.swift:31,49`，revision/byte/mtime 兜底）；`canCoalesceDuplicateItem` 不动；
3. 8/12 事故全场景回归测试 `PoetryIncidentRegressionTests.swift`：读盘失败 → 降级显示 → 编辑 → 写回 / 改名 / 重启 retry，正文必不丢，逐通道断言；
4. 验收：CI 绿 + 事故场景复现冒烟；PR 附代码净减少量统计（预期净减 >1000 行）；回退自查表。

## 阶段 5：身份语义对齐与收尾

分支 `codex/filemodel-phase5-identity-cleanup`。

1. 三处"身份用于拒绝"对齐为"只用于找回"：
   - `verifiedCourseOwnedNoteAccess`（`WorkspaceStore.swift:18039-18084`）：身份不符改为刷新记录 + 记日志，与 :17158-17161 既有红线注释统一；
   - 搜索索引身份闸门（`CourseDocumentSearchIndex.swift:121-130`）：不符降级为日志并照索引（fd 级 TOCTOU 保护已有）；
   - `makeAgentFileGrant`（:13896-13906）：同步对齐，Pi 扩展侧（`extension.ts:739-750,1516-1555`）协议不变仅放宽拒绝条件；
2. `.common` 共享项 digest 保持对账刷新（可携带完整性闸不动）；courseOwned 笔记 digest 降格为写闸门比对专用；
3. 更新 AGENTS.md 与相关注释，把"文件即真相 + 一道锁 + 副本先行"写成仓库明文约定；
4. 全量回归（含 Pi 终止语义、编辑器自检、安全测试全量）+ 用户完整验收清单（约十二项普通使用场景）。

---

# 6. 测试影响清单（阶段 4 重写对象）

- `Sources/WeiBeiSelfCheck/main.swift:2098-2279`（修复规划器全部 fixture + 顺序/模板/哨兵源码断言）；
- `Tests/WeiBeiSafetyTests/ImportedIdentitySelfCheck.swift:1436/1505-1506、1801/1884、2039、2725、2780/2832、2958/2999、3199-3261`；
- `Tests/WeiBeiSafetyTests/CourseProjectRootSelfCheck.swift` 可携带/共享 digest 断言（:2262-2288、3062-3171、5500、6173-6224、6340、6451、6510）——仅改弱化语义部分，可携带校验本身不动；
- `SelfCheckNotes.swift:9-43`（`baselineContentDigest` 回环断言）。

明确不动：`LibraryRelativeOnlyTests.swift:114-135`、`SelfCheckImport.swift:52-59`、可携带快照双校验相关测试。

---

# 7. 风险登记

| 风险 | 等级 | 缓解 |
|---|---|---|
| 写闸门遗漏写路径，事故通道重开 | 高 | 全部写路径强制走底层函数 + 源码断言防新增绕过点；阶段 4 事故全场景回归 |
| 备份环 20 份/50MB 上限，高频覆写副本被逐出 | 中 | 如实标注为缓冲非保险；必要时调上限 |
| 占位符识别漏非 iCloud 云盘形态 | 中 | 通用后缀匹配 + 持续缺席灰态兜底，不绑死 iCloud |
| 行为变更导致老用户数据问题 | 中 | 每阶段独立验收；不改任何磁盘格式 |
| 阶段间半成品状态长期使用 | 低 | 每阶段独立可发布；写闸门与旧锁并存期无行为冲突 |

---

# 8. 已拍板事项

1. 多机搬运能力：**保留，不动**（用户不依赖，但保留无成本；快照双校验不属于拆除对象）；
2. 迁移目标在云同步目录：**提示但不阻止**；
3. 横幅最终形态：**条目灰态/条内状态，可见性不降，不主动弹**；
4. 零体验回退为第一约束，每阶段 PR 附回退自查表。

---

# 9. 执行顺序总览

1. 任务一（迁移入口）：分支 `codex/library-location-setting`；
2. 任务二阶段 0-5：每阶段一个分支一个 PR，按顺序推进，不并行；
3. 全部合入后：从干净 main 打候选版，给用户一份约十二项的普通使用场景清单整体验收。
