# 冷启动去全文件 SHA256 世代保护（启动提速 + 文件即真相收尾）

**日期：** 2026-08-26
**状态：** 已落地（分支 `codex/startup-digest-decouple`）
**性质：** 性能优化 + AGENTS.md「文件即真相」红线合规收尾

---

## 问题

冷启动时 `WorkspaceStore.init`（主线程、首帧之前）两次调用 `refreshRuntimeItemURLs()`（`WorkspaceStore.swift:1026、1029`）。该函数对每个**非笔记资料**（PDF/EPUB/HTML 等）且带 `contentDigest` 的条目，同步调 `CourseProjectFileWorker.snapshotFile`（`CourseProjectRootSupport.swift:1628-1640`）做**全文件分块读取 + SHA256**，不符则断链（`WorkspaceStore+LibraryRoot.swift:271-284`）。

- 代价：每个带 digest 的资料冷启动被完整读两遍（主线程）；库越大启动越慢，直接对应「用久了打开变慢」。
- 合规：这是「世代保护」残留。AGENTS.md 红线写明 identity/digest「永不用于拒绝访问」；笔记侧启动断链已在阶段 3 拆除（代码注释自证），资料侧是最后一个残留。
- 冗余：后台对账通道已具备 digest 刷新能力（`applyCourseFileObservations`，`WorkspaceStore.swift:18512-18542`，文件变更即采用新 digest），首帧后 3 秒内第一轮对账就到（`startCourseFileMaintenance`，`WorkspaceStore.swift:18612-18634`）。

## 改动

1. `refreshRuntimeItemURLs()` 的 `.present` 分支：去掉 `snapshotFile` 哈希比对，文件在就保留路径，与笔记同待遇。
2. `absent` / `inaccessible` / iCloud 占位符（`presentUnmaterialized`）分支不动；瞬断容忍、灰态两周期保护全部保留。
3. `init` 两次调用保守保留、只去哈希；调用次数合并留作可选后续。

## 测试迁移

- 新增资料版「外部修改不断链」用例，与 `testStartupDigestMismatchDoesNotUnlinkNotes`（`TransientToleranceSafetyTests.swift:104`）平行。
- 新增「对账采用外部内容并刷新 digest」断言（锁对账刷新，不锁断链）。
- 核查 `ImportedIdentitySelfCheck` / `CourseProjectRootSelfCheck` 中依赖启动断链的用例，改走对账路径。

## 验证

- `swift build` → `make check`。
- 定向：`TransientToleranceSafetyTests`、`LibraryRelativeOnlyTests`、`ImportedIdentitySelfCheck`、`SnapshotRecoveryTests`。
- 性能对比：`WEIBEI_PERF=1` 启动日志 `beginLaunch→finishLaunch`，含大 PDF 的库前后各测一次。
- 真实 App 轻量冒烟：启动 → 资料照常显示可打开 → 外部改一个资料 → 对账后正常打开新内容。

## 风险与回退

- 外部把资料换成坏文件时用户点开才发现——与笔记现状一致；打开路径有 `PDFReaderOpenSafety` 等自有闸。
- 单 commit，revert 即回退。

## 前置

- 开工时先确认在途工作（测试错误类型化）已归置；从最新 `origin/main` 开 `codex/startup-digest-decouple`。
- 声明占用共享核心面 `Sources/WeiBei/Stores/WorkspaceStore.swift`（另触 `WorkspaceStore+LibraryRoot.swift`，非核心面），PR 合入即释放。

## 工作量

实现 + 测试迁移约半天；验证冒烟约半天。一天内交付。

## 落地记录（2026-08-27）

- 代码：`WorkspaceStore+LibraryRoot.swift` 的 `.present` 分支去掉 `snapshotFile`；`init` 两次 `refreshRuntimeItemURLs()` 未合并。
- 测试：`testStartupDigestMismatchDoesNotUnlinkMaterials`、`testReconciliationAdoptsExternalMaterialContentAndRefreshesDigest`。`ImportedIdentitySelfCheck.replacedAndCrossVolumeFilesReceiveNewIdentities` 未接入 `run()`，无活断言依赖启动断链；`CourseProjectRootSelfCheck` 已有「外部修改共享资料后采用真实文件」对账路径。
- 验证：`swift build` 通过；定向四套测试绿；`WeiBeiSelfCheck` 通过。`make check` 185/186，唯一失败为未触碰的 `testGenUIWheelInsideWebContentReachesConversationScroller`（本机 `NSEvent` 子类 `super.init()` 得到 type 0，与本刀无关）。
- 性能：20MB 文件分块 SHA256 ≈ 8ms；冷启动对该文件要读两遍，约 16ms 主线程 IO。本刀从启动路径移除该成本（N 份资料线性叠加）。
- 占用：未改 `WorkspaceStore.swift` 本体，只改扩展文件。
