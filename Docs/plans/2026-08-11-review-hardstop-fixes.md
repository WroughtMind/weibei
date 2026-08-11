# 魏碑审查 hard stop 修复方案：宣发阻断批次（2026-08-11）

状态：**实施中（用户已批准按计划串行推进）**。基于 2026-08-11 外部深度审查（审查范围 c2156e32 → origin/main 5d0ecb53，即 PR #176–#188 全部合并后的现状）。

进度：
- [x] PR-A `codex/fix-note-integrity` — C1 + C2 + H1（#189 已合入）
- [x] PR-B `codex/fix-note-watcher` — C3 + H4 + H5（本分支）
- [ ] PR-C `codex/fix-course-boundaries` — H2 + H3

## 一句话

「拆除事务引擎」的方向和主体实现正确，但换上的新安全网自身有 8 个实锤缝隙（3 CRITICAL + 5 HIGH）；本方案用三个串行 PR 把缝隙全部补上，并为每个修复钉一条此前缺失的测试锚。全部是小改动，无架构返工，不回退任何已批准的产品语义。

## 产品原则（沿用存储简化方案，不变）

默认沉默、永不拒绝保存、横幅是产品缺陷。本方案所有修复都在这三条之内：修的是「兜底没兜住」，不是恢复任何拒绝关卡。

## 修复清单（审查结论回顾，行号为 origin/main = 5d0ecb53）

| # | 级别 | 问题 | 位置 |
|---|------|------|------|
| C1 | CRITICAL | 备份判定基线被 reconcile（3 秒循环）与笔记加载回调刷成「磁盘最新内容」，写回时判「没变」跳过备份——外部编辑器版本被覆盖且不入备份环（课程笔记） | `WorkspaceStore.swift:18048`、`:18853`、`:18996-19004` |
| C2 | CRITICAL | 写回失败的课程笔记草稿只在 `notesByItemID`（pending 条目已删），课程状态导出只认 pending（`:19493`），启动重放又清空 `notesByItemID`（`:20135`）——草稿活不过重启 | `WorkspaceStore.swift:19019`、`:19493`、`:19645`、`:20135` |
| C3 | CRITICAL | watcher cancel handler 读活值 `self.fileDescriptor`，重挂时 close 的是新 fd——监听器在第一次自动保存后永久失效（已 harness 实证） | `NoteFileWatcher.swift:96-101` |
| H1 | HIGH | 启动清理无白名单递归删事务目录，销毁 `replaced-target` 崩溃备份副本（运行时版本 `:5177` 明明有白名单） | `WorkspaceStore.swift:5365` |
| H2 | HIGH | 分叉课程拷贝（内容不同 + 本机 dirty）被归入 `.unchanged`，UI 又对 `.unchanged` 零确认自动绑定——分叉进度对用户不可见 | `WorkspaceStore.swift:2530`、`CourseWorkspaceComponents.swift:636` |
| H3 | HIGH | symlink 解析后无「仍在课程根内」校验，根外文件可被登记为课程笔记（写回覆盖根外文件、导出打包根外内容） | `CourseProjectRootSupport.swift:2608` |
| H4 | HIGH | 静默重载的脏判定漏 `stagedNoteDraft` 层，连续打字 burst 期间判「无脏」，重载丢弃输入 | `WorkspaceStore.swift:19098` |
| H5 | HIGH | 目录级 kqueue 收不到子文件就地写入（`sed -i`/追加类全盲区）；注释声称 poll mtime 但代码无 stat | `NoteFileWatcher.swift:88-91`、`:127-139` |

## 分阶段实施（三个 PR，串行，每个独立可合入、独立可回滚）

### PR-A `codex/fix-note-integrity` — 笔记数据完整性（C1 + C2 + H1）

**C1 修法：分离「备份判定基线」与「磁盘观察值」两个概念。**
现状 `noteBackingContentDigestsByItemID` 一肩挑两职：既当外部改动观察值（reconcile/load 需要刷新它），又当备份判定基线（要求它只反映「上次魏碑写入」）。两职冲突即是根因。

- 新增内存字典 `lastSelfWrittenNoteDigestsByItemID: [String: String]`（**不持久化**，避免 schema 变更；重启后首次写回会因无基线多备份一份，方向安全）。
- 只允许三类写入点：① 写回成功后（现 `:19011` 处）；② 无草稿静默采纳磁盘内容时（load 无草稿分支与外部重载采纳处 `:19088`）；③ `applyCoursePortableState` 回填笔记内容时（`:20141` 一带）。
- `writeNoteMarkdownTriple` 的备份判定改用新字典；`noteBackingContentDigestsByItemID` 保留原名与全部现有读写（外部改动检测继续用它），不再参与备份决策。
- 实施第一步：grep `noteBackingContentDigestsByItemID` 全部读取点，确认备份决策读者唯一（见「最脆弱假设 1」）。

**C2 修法：草稿导出与重放两端都修。**
- `makeCoursePortableState`（`:19491`）的 drafts 改为遍历该课程 noteItemIDs 中 `notesByItemID` 有值的条目；`baselineContentDigest` 取 pending 条目的值，无 pending 则为 nil（若 `CoursePortableNoteDraft.baselineContentDigest` 为非 optional，改为 optional 并保持解码容忍——见「最脆弱假设 2」）。
- `applyCoursePortableState` 的清除循环（`:20135`）改为：本地存在草稿（`notesByItemID` 有值）而 state 无对应 draft 的条目**保留不清**——本地未落盘输入永远优先于快照重放；state 中的 draft 仅在本地无草稿时回填。

**H1 修法：启动清理套白名单 + best-effort 还原。**
- `silentlyCleanupOrphanCourseTransactions`（`:5365`）沿用运行时白名单语义：目录条目全部 ∈ {`journal.json`, `payload`} 才删。
- 含 `replaced-target` / `replacement-rollback` 的目录：读 `journal.json` 取 targetURL，副本 snapshot 匹配且 targetURL 空缺时还原被替换文件；任何一步不成立则**保留目录不删**（数据不销毁是底线，还原是增强）。
- 顺手修同函数区域的既知 LOW：隔离目录空目录检查（`:5417-5445`）从 `for child` 循环体内移出，children 为空时也执行。

**验收断言（全部为此前缺失的测试锚）：**
1. course-owned 路径接线 `noteBackupRootURL` 注入（补上 CourseProjectRootSelfCheck 中 `_ = backupRoot` 放弃掉的验证），断言：外部写入 B → reconcile 执行 → 魏碑写回 → 备份环出现内容为 B 的文件。
2. 魏碑连续写回 N 次（无外部改动）→ 断言备份环不新增条目（防自写刷环）。
3. 写回失败留草稿 → course state 落盘 → 重建 store 模拟重启 → 断言草稿仍在且启动迁移重试触发；再加「state 未及重写即重启」变体（验 apply 端防御）。
4. 构造含 `replaced-target` 的孤儿事务目录 → 启动清理 → 断言副本未被删除；纯 {journal.json, payload} 目录 → 断言被清。

**共享核心面占用**：`WorkspaceStore.swift`、`WeiBeiSelfCheck/main.swift`。
**涉及文件**：`Sources/WeiBei/Stores/WorkspaceStore.swift`、`Tests/WeiBeiSafetyTests/CourseProjectRootSelfCheck.swift`、`Tests/WeiBeiSafetyTests/ImportedIdentitySelfCheck.swift`、`Sources/WeiBeiSelfCheck/main.swift`、（视 schema）`Sources/WeiBeiCore/CoursePortableState.swift`。规模约 250 行（含测试）。

### PR-B `codex/fix-note-watcher` — 文件监听生命周期与盲区（C3 + H4 + H5 + deinit 竞态）

**C3 修法：cancel handler 按值捕获自己的 fd。**
```swift
let fd = fileDescriptor
source.setCancelHandler { close(fd) }
```
`fileDescriptor` 的复位（-1）移入 `stopLocked`/`startLocked` 主流程；handler 不再读写实例状态。

**deinit 竞态（同文件同根因，一并修）**：deinit 只 `source?.cancel()` + 取消 pending work item，删除直接 `close`（close 全权归 cancel handler）——消除 double-close/TOCTOU。「安全测试模式关监听」保留为降噪开关，但注释改写：它不再是正确性依赖。

**H4 修法**：`isActiveNoteDirty`（`:19098`）增加一行：`if stagedNoteDraft?.itemID == itemID { return true }`。

**H5 修法：目录 + 文件双 kqueue source。**
- 保留目录 source（抓 rename/delete/create，即原子替换类保存）；新增文件 fd source（`open(fileURL, O_EVTONLY)`，eventMask `.write/.extend/.attrib`，抓就地写入）。
- 目录事件到达时在既有 0.12s coalesce work 中重开文件 fd（文件可能已被原子替换成新 inode）；两个 source 的事件汇入同一 coalesce 路径。
- 文件 fd open 失败（如 iCloud 占位未下载）降级为仅目录监听（等同现状），不崩溃。
- 删除 `:127` 与实现不符的「poll mtime/size」注释，改为如实描述双 source 机制。

**验收断言（自检新用例，参考现有 main.swift:1854 段模式，事件等待带 2s 超时）：**
1. watch → 外部原子写 → 事件到达（现有用例保留）。
2. **重挂后仍活**：watch → 触发一次重挂（再次 watch 同/异 URL）→ 外部写 → 事件到达（钉 C3；现状此用例会失败）。
3. **就地写可见**：`FileHandle` 追加写 → 事件到达（钉 H5；现状会失败）。
4. 快速连续 watch/stop 切换多轮 → 无崩溃、终态监听正确（钉生命周期）。
5. H4：注入 staged 草稿 → 断言 `isActiveNoteDirty == true`（经 selfcheck 钩子暴露，`isActiveNoteDirty` 为 private，新增测试模式查询函数）。

**共享核心面占用**：`WorkspaceStore.swift`、`WeiBeiSelfCheck/main.swift`。
**涉及文件**：`Sources/WeiBeiCore/NoteFileWatcher.swift`、`Sources/WeiBei/Stores/WorkspaceStore.swift`、`Sources/WeiBeiSelfCheck/main.swift`。规模约 150 行（含测试）。

### PR-C `codex/fix-course-boundaries` — 课程边界（H2 + H3）

**H2 修法：重绑 impact 引入第三态，回归 S6-5 原批准语义（「仅当确有歧义时弹一次确认」）。**
- `CourseProjectRebindImpact` 增加 `.keepsLocalState`；`evaluatedCourseRebindState`（`:2530`）的 guard-else 分支（digest 不等 / 本机 dirty / revision 不可比）返回它；真正 digest 相等的早退分支保持 `.unchanged`。
- `CourseWorkspaceComponents` 自动确认仅限 `.unchanged`；`.keepsLocalState` 弹一次确认，文案说明：「候选文件夹包含与本机不同的课程进度；确认后以本机进度为准，候选中的差异会以冲突备份保留」。
- confirm 时的复评估（`:2857` `evaluation.impact == proposal.impact`）兼容三态。
- 自检：分叉候选 + 本机 dirty → 断言 impact == `.keepsLocalState` 且不自动绑定；候选与本机 digest 相等 → 断言仍 `.unchanged` 自动确认（保住 S6-5 的无歧义顺滑路径）。

**H3 修法：symlink 解析加 containment，根内链接保留 S6-6 功能。**
- `scanCourse` 的文件 symlink 分支（`:2608`）：解析结果必须仍在课程根（canonical 路径前缀比对，注意尾斜杠与大小写；优先复用 `CourseProjectPathPolicy` 既有的包含判定，实施时确认函数名）；根外目标跳过登记 + `NSLog` 一条（默认沉默，不弹提示）。
- 自检：课程根内 symlink 指向根外文件 → 断言未登记为课程文件；根内指向根内 → 断言照常登记（保住 S6-6 已合并功能）。

**共享核心面占用**：`WorkspaceStore.swift`。
**涉及文件**：`Sources/WeiBei/Stores/WorkspaceStore.swift`、`Sources/WeiBei/Views/CourseWorkspaceComponents.swift`、`Sources/WeiBei/Stores/CourseProjectRootSupport.swift`、`Tests/WeiBeiSafetyTests/CourseProjectRootSelfCheck.swift`。规模约 150 行（含测试）。

## 明确不做（本批次外，宣发阻断解除后另立批次）

审查还发现约 14 条 MEDIUM 与若干 LOW/ADVISORY，本批**不做**，避免宣发阻断批次膨胀：

- 恒真自检清理（`lastPortableAdoptionReadRanOnMainThread` 硬编码、7 处 `check(true, …)`、三选一 OR 弱化断言）
- S6-2 换资料库回补一次确认（现为零确认静默改绑）
- 退出 flush 的 2s 超时降级（现为无限等待）
- ignore 窗口「丢弃改延后补查」与按目标笔记收窄
- courseOwned 笔记切回时重读磁盘（iCloud 降级路径）
- workspaceSaveError chip 挂载到主窗口 surface + 失败类别分计
- 重命名回滚的 newURL 身份校验、共享链接移除失败回滚、`.weibei` symlink 元数据解析、WebView element fullscreen 默认值、P4 空转项等

例外说明：PR-A 顺手修 `:5417` 空目录检查、PR-B 顺手修 deinit 竞态——均与主修复同文件同根因，不属于批次膨胀。

## 执行顺序与流程（AGENTS.md 合规）

- **PR-A → PR-B → PR-C 严格串行**（三者都占用共享核心面 `WorkspaceStore.swift` / `WeiBeiSelfCheck/main.swift`，同一时间只允许一个活跃任务占用）。
- 每个 PR：从最新 `origin/main` 开 `codex/<任务名>` 分支（worktree 隔离，**不触碰主仓 `~/Documents/魏碑` 的脏工作区**）；当天推送 + 草稿 PR + 占用声明；CI 绿（swift build / WeiBeiSelfCheck / 编辑器自检 / WeiBeiSafetyTests）+ 完成定义达标后转正式合入。用户批准本方案即视为按既定工作计划滚动合并的授权（与 #176–#188 批次同模式）。
- 本方案文档随 PR-A 一并入库（AGENTS.md：工作计划默认由首个相关实现合并请求纳入 main）。
- **全部合入后**：从干净 main 构建唯一候选版，Agent 先完成初步全链路冒烟，再按 AGENTS.md 给用户十几个普通使用场景清单（重点覆盖本批修复行为：外部编辑后可找回、崩溃后草稿还在、外部改动 1 秒内刷新、打字不被重载打断、分叉拷贝弹确认）——同时补上 #176–#188 批次缺失的人工验收环节。

## 最脆弱假设

1. **C1 假设备份决策的读者唯一**（`writeNoteMarkdownTriple`）。实施第一步 grep `noteBackingContentDigestsByItemID` 全部读取点核实；若存在第二个备份决策点，一并切换到新字典。若发现该字典读者中有依赖「基线=上次自写」语义的其他逻辑，逐个判定归属。
2. **C2 假设 course-state schema 可容忍 baseline 缺省**。若 `CoursePortableNoteDraft.baselineContentDigest` 非 optional，改 optional 并验证旧文件解码容忍（新增条目数量变化本身向后兼容：drafts 字段已存在）。
3. **H5 假设文件 fd 在 iCloud/网络卷上 open 可能失败**——失败即降级为现状（仅目录监听），行为不回退、不崩溃。
4. **自检稳定性**：文件事件类用例在 CI 共享 runner 上以 2s 超时等待（沿用现有 1854 段模式，该模式已在 CI 稳定运行）。

## 依赖清单

无新第三方依赖、无新权限、无破坏性 schema 变更（course-state 仅 optional 化一个字段 + drafts 条目增多，双向可读）。

## 验收命令

`swift build`、`swift run WeiBeiSelfCheck`、`swift test --filter WeiBeiSafetyTests`（与 CI 一致）。PR-B 额外做一次真实窗口手工验证（外部改文件 → 1 秒内刷新；打字时外部改文件 → 不打断），结果记入 PR 描述。

## 评审记录

- 2026-08-11 外部深度审查（4 风险面并行 + 全部 CRITICAL/HIGH 逐行复核，C3 含 harness 运行实证）：8 个 hard stop 全部 CONFIRMED，本方案即其修复承接。
