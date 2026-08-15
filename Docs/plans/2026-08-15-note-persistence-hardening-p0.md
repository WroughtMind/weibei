# 笔记持久化 P0 止血：分叉修复例程 + 模板覆盖封堵 + 重命名哨兵

日期：2026-08-15
分支：`codex/note-persistence-hardening-p0`
任务来源：诗歌笔记事故（磁盘文件被默认模板覆盖、正文仅存于 workspace.json 草稿层）后的体系审计。

## 审计结论（根因）

1. **双真相源分叉**：写盘失败/文件不可达时正文进入 `notesByItemID` 草稿层并无限期遮蔽磁盘内容，UI 无常驻提示（`WorkspaceStore.swift` noteText(for:)、noteMarkdownText、agentActionNoteMarkdown 均为草稿优先）。
2. **fileID 指纹漂移**：5 个笔记的 `importedFileIdentity` 与实际文件 inode 不符（旧版写路径遗留；当前代码仍有两个缺口：rename 的 `?? originalIdentity` 兜底、refreshImportedFileTracking 解析失败静默）。
3. **模板覆盖通道**：`noteText(for:)` 读失败回退 `defaultNote` 模板；之后 rename 第 1 步 `persistCurrentNote` 会把模板当真内容写回旧文件，且模板首行 `# oldTitle` 命中 `retitledMarkdown` 前缀改写 → 新文件也是模板。

## P0 范围

- [x] 启动时一次性幂等修复例程（仿 `retryRestoredPendingNoteWrites`，挂在 load 之后）：
  - 草稿≠磁盘 → 磁盘现内容入 NoteBackupRing → 以草稿为准原子写回 → 刷新指纹 → 清草稿；
  - 磁盘==草稿时只刷指纹不动内容（幂等）；
  - 修复现存的 fileID 漂移；
  - 先实现干跑（输出修复清单）+  fixture 验证，再开执行开关。
- [x] 焊死模板覆盖通道：`noteText(for:)` 回退 defaultNote 的分支同时置 degraded 标记（复用 `noteOperationErrorsByItemID` 机制）；`writeNoteMarkdownTriple` 在 degraded 且磁盘 digest ≠ 模板 digest 时拒绝覆盖（留草稿 + 常驻错误提示）。
- [x] rename 前置哨兵：`sourceMarkdown` 形态等于 `defaultNote(for:)` 模板且磁盘 digest 显示另有内容时，中止重命名并提示。
- [x] WeiBeiSelfCheck 新增断言锁死上述不变量。

## 共享核心面占用

- `Sources/WeiBei/Stores/WorkspaceStore.swift` —— 本任务占用，释放条件：本 MR 合并。
- `Sources/WeiBeiSelfCheck/main.swift` —— 本任务占用，释放条件：本 MR 合并。

## 验证

- `swift build` / `swift run WeiBeiSelfCheck` / `swift run WeiBeiWebEditorCheck`
- 本机仅 CLT 无 Xcode，WeiBeiSafetyTests（XCTest）跑不了，属环境限制。

## 不做（后续任务）

- P1：write-behind journal、指纹刷新内聚进 writeNoteMarkdownTriple、rename 纯 mv 化、未落盘草稿常驻可见性。
- P2：磁盘文件唯一真相源、customDisplayTitle 废弃、sample 笔记物化。

## 验收记录

实现要点（2026-08-15，分支 `codex/note-persistence-hardening-p0`）：

- 新增 `Sources/WeiBeiCore/NoteDivergenceRepair.swift`：
  - `NoteTemplateShape.isDefaultTemplateShape(_:title:)`：结构判定默认模板形态（首行 `# <title>` + 三个固定小节、正文为空，中英双语）；
  - `NoteDivergenceRepairPlanner.action(for:)`：纯函数修复判定，输入为 digest/指纹现场，输出 `none / restoreDraft / discardRedundantDraft / discardSuspectTemplateDraft / refreshIdentityOnly`。盲态（文件不可读、指纹漂移且磁盘内容不可辨认）一律不动。
- `WorkspaceStore`：
  - `repairDivergedNotebookNotesIfNeeded()` 挂在 `startCourseFileMaintenance`，**先于** `retryRestoredPendingNoteWrites`（否则 retry 会把模板草稿盖回磁盘）；每次启动一轮，判定/执行分离，`WeiBeiNoteRepairDisabled=1` 干跑只打 NSLog；restoreDraft 备份先行（备份失败不写盘），写回有意走显式 writer 而非 persistNote，避免触发 MR #210 的文件名同步造成抖动；全程不弹窗，仅嫌疑模板草稿被丢弃时给一次 transient 提示。
  - `noteText(for:)` 两个 defaultNote 回退分支在无草稿时置 degraded（`noteOperationErrorsByItemID`）；读盘成功即自愈清除；`setNoteFileError` 增加同消息去重避免渲染期 toast 刷屏。
  - `writeNoteMarkdownTriple` 守卫：degraded + 待写内容为模板形态 + 磁盘 digest ≠ 模板 digest + 磁盘 digest ≠ 上次自写 digest → 拒绝写（留草稿 + 常驻错误 + transient），后者放行避免误伤「用户真把正文删成模板」。
  - rename 哨兵：`sourceMarkdown` 模板形态 + 该笔记有降级记录 + 磁盘 digest ≠ 模板 digest → 中止重命名并提示「正文未能完整读取，为保护内容未执行重命名。」
- `WeiBeiSelfCheck`：模板形态判定 7 组用例 + 修复 planner 9 组临时目录 fixture 用例（含 restore→收敛幂等链、备份内容校验、盲态保护）+ WorkspaceStore 接线源码断言（含 repair 先于 retry 的顺序断言、模板小节文案同步断言）。

验证命令与结果：

- `swift build` → Build complete!
- `swift run WeiBeiSelfCheck` → WeiBei self-check passed
- `swift run WeiBeiWebEditorCheck` → WeiBei web editor check passed
- XCTest（WeiBeiSafetyTests）受环境限制未跑（本机仅 CLT 无 Xcode），PiCheck 与本改动无关未跑。

遗留风险：degraded 期间用户把模板改成「模板+少量字符」再写回不在守卫范围内（非精确模板形态），留待 P1 的 write-behind journal / 指纹内聚一并处理；修复例程的 restoreDraft 与用户启动后即时编辑存在理论竞态（草稿本身优先，方向安全）。
