# 侧边栏/列表笔记名与浮动 tab 同一套显示名解析

日期：2026-08-15
分支：`codex/sidebar-note-display-title`

## 概述

侧边栏列表（库列表 + 课程分组"笔记"区）原先直接显示 `item.title`（文件名），
与浮动 tab 的 `NoteTabDisplayTitle.resolve` 解析结果不一致（典型：清空笔记写
个"OK"，tab 显示 OK，列表还叫"新笔记 25"）。本任务让列表行复用同一套解析：
自定义名 > 正文抬头 > item.title；非笔记条目（资料等）维持 `item.title` 不动。
排序键、行高/截断样式、NotebookRenameRow 真重命名逻辑均不动。

## 方案

- 复用现有 tags 异步管线，不在行渲染里同步读盘：
  - 缓存条目从只存 tags 扩成 `CourseSidebarNoteMeta(tags, resolvedTitle)`；
    `loadSidebarTags` 改名 `loadSidebarNoteMeta`，同一次正文获取
    （`sidebarTagMarkdown`，异步：内存草稿/活动笔记/读盘）同时产出 tags 与
    `NoteTabDisplayTitle.resolve` 解析的显示名。解析结果为空或等于文件名时
    存 nil（行视图兜底显示 `item.title`，同时避免投影因 nil/等值差别抖动）。
  - `CourseSidebarItemRow` 增加 `resolvedTitle: String?`，行构建处带上；
    `LibraryRow` 增加对应入参，显示 `Text(resolvedTitle ?? item.title)`。
  - `CourseSidebarTagState` 的缓存/草稿失效机制原样保留（`noteDraftChanged`、
    `replacedNoteDrafts`、prune/clear），`cachedSidebarTags` 改名
    `cachedSidebarNoteMeta`，transient 缓存同步扩成 meta。
- 失效语义：
  - 草稿变化/落盘：走原有 `noteDraftChanged`（清条目 + draft revision 变化
    使 request 失配），与 tags 完全一致。
  - 自定义名变化不走 `noteDraftChanged`：把 `customDisplayTitle`（和 `title`）
    编入 `CourseSidebarTagRequest`。`setNoteCustomDisplayTitle` 改
    `importedItems` → 投影重建 → request 变化 → 旧缓存失配重载；
    且行构建时对自定义名做同步短路（`NoteTabDisplayTitle.normalizedCustomTitle`，
    新增公开入口，与 resolve 同口径），设置自定义名立即上屏、不等异步加载。
    清除自定义名同理：request 失配 → 重载正文解析名。
  - 正文抬头驱动文件改名（`synchronizeNoteFileNameWithHeading`）会改
    `item.title`/`urlPath`，同样在 request 里，缓存自然失效。
- compact 行（课程分组内）原 task 守卫 `guard !compact` 跳过加载（不显示 tags）；
  现在 compact 笔记行也要显示解析名，故移除该守卫——`tagRequest` 只对笔记非空，
  资料行不受影响；`List` 只创建可见行，加载量有界，解析在 actor 上完成。

## 共享核心文件占用

- `Sources/WeiBeiSelfCheck/main.swift`：新增本功能断言。本 MR 合并即释放。
- 未改 `Sources/WeiBei/Stores/WorkspaceStore.swift`（失效靠 request 编入
  customDisplayTitle/title 完成，无需动 store）。

## 验证

- `swift build`
- `swift run WeiBeiSelfCheck`（新增断言：管线用 NoteTabDisplayTitle 解析、
  LibraryRow 显示解析名、customDisplayTitle/title 编入缓存请求保证失效）
- `swift run WeiBeiWebEditorCheck`
- `Tests/WeiBeiSafetyTests/SidebarPerformanceTests.swift` 同步适配新签名
  （本机无 Xcode 不能跑 swift test，仅保证 CI 可编译）。

## 结果

- `swift build` ✅；`swift run WeiBeiSelfCheck` ✅（含新增断言）；
  `swift run WeiBeiWebEditorCheck` ✅。
- `swift test` 本机无 Xcode（仅 CLT）不能跑，SidebarPerformanceTests 只做
  签名适配保证 CI 可编译，待 CI 验证。
- 真实 App 冒烟由用户在候选包上验收；本任务未操作任何运行中的 App。
