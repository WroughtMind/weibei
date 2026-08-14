# 笔记持久化 P0 止血：分叉修复例程 + 模板覆盖封堵 + 重命名哨兵

日期：2026-08-15
分支：`codex/note-persistence-hardening-p0`
任务来源：诗歌笔记事故（磁盘文件被默认模板覆盖、正文仅存于 workspace.json 草稿层）后的体系审计。

## 审计结论（根因）

1. **双真相源分叉**：写盘失败/文件不可达时正文进入 `notesByItemID` 草稿层并无限期遮蔽磁盘内容，UI 无常驻提示（`WorkspaceStore.swift` noteText(for:)、noteMarkdownText、agentActionNoteMarkdown 均为草稿优先）。
2. **fileID 指纹漂移**：5 个笔记的 `importedFileIdentity` 与实际文件 inode 不符（旧版写路径遗留；当前代码仍有两个缺口：rename 的 `?? originalIdentity` 兜底、refreshImportedFileTracking 解析失败静默）。
3. **模板覆盖通道**：`noteText(for:)` 读失败回退 `defaultNote` 模板；之后 rename 第 1 步 `persistCurrentNote` 会把模板当真内容写回旧文件，且模板首行 `# oldTitle` 命中 `retitledMarkdown` 前缀改写 → 新文件也是模板。

## P0 范围

- [ ] 启动时一次性幂等修复例程（仿 `retryRestoredPendingNoteWrites`，挂在 load 之后）：
  - 草稿≠磁盘 → 磁盘现内容入 NoteBackupRing → 以草稿为准原子写回 → 刷新指纹 → 清草稿；
  - 磁盘==草稿时只刷指纹不动内容（幂等）；
  - 修复现存的 fileID 漂移；
  - 先实现干跑（输出修复清单）+  fixture 验证，再开执行开关。
- [ ] 焊死模板覆盖通道：`noteText(for:)` 回退 defaultNote 的分支同时置 degraded 标记（复用 `noteOperationErrorsByItemID` 机制）；`writeNoteMarkdownTriple` 在 degraded 且磁盘 digest ≠ 模板 digest 时拒绝覆盖（留草稿 + 常驻错误提示）。
- [ ] rename 前置哨兵：`sourceMarkdown` 形态等于 `defaultNote(for:)` 模板且磁盘 digest 显示另有内容时，中止重命名并提示。
- [ ] WeiBeiSelfCheck 新增断言锁死上述不变量。

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

（待填）
