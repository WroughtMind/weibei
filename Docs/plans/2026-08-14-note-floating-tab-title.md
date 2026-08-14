# 笔记顶部浮动 tab：移除模式切换 + 可重命名显示名

日期：2026-08-14
分支：`codex/note-floating-tab-title`

## 概述

1. 删除笔记顶部浮动 tab 上的三个模式切换按钮（rich / split / source），笔记固定为所见即所得（WYSIWYG）写作。
2. 浮动 tab 的笔记名支持点击行内重命名，并实现"自定义名 > 实时 title > 正文前几个字"的显示名状态机。

## 方案

- `NoteRenderMode` 机制保留（持久化、旧数据迁移、自检查仍依赖），但所有切换入口移除：
  浮动 tab / 笔记面板头按钮、主菜单三项（含 ⌃⌘1/2/3）、命令面板三项。
  `WorkspaceStore.setNoteRenderMode` 收敛为永远落到 `.rich`，双保险。
- 显示名解析抽成纯函数 `WeiBeiCore/NoteTabDisplayTitle.swift`：
  `resolve(customTitle:noteTitle:body:)`。正文回退去空白与 Markdown 标记后取前 20 字符。
- 自定义名持久化为 `StudyItem.customDisplayTitle: String?`（可选字段，向后兼容，
  旧数据解码为 nil）。提交空白 = 清除自定义名 = 恢复自动跟随（可逆出口）。
- 行内重命名实现在 `ImmersiveHoverTitleView`（新增可选 `TitleRename` 参数，
  默认 nil，阅读器浮动标题不受影响）；编辑中强制保持 tab 可见并聚焦文本框，
  Esc 取消、回车提交。

## 共享核心文件占用

- `Sources/WeiBei/Stores/WorkspaceStore.swift`：`agentNoteTitle` 解析、
  `setNoteCustomDisplayTitle`、`setNoteRenderMode` 收敛。本 MR 合并即释放。
- `Sources/WeiBei/App/WeiBeiApp.swift`：删除三个笔记模式菜单项。本 MR 合并即释放。
- `Sources/WeiBeiSelfCheck/main.swift`：新增本功能断言。本 MR 合并即释放。

## 验证

- `swift build`
- `swift run WeiBeiSelfCheck`（含新增断言：自动跟随 title、无 title 回退正文、
  重命名后不跟随、清空恢复跟随、三个模式按钮从 tab/菜单/命令面板消失）
- `script/build_and_run.sh package` 产出候选 App

## 结果

- `swift build` ✅；`swift run WeiBeiSelfCheck` ✅；`swift run WeiBeiWebEditorCheck` ✅；`WeiBeiPiCheck` ✅。
- `swift test --filter WeiBeiSafetyTests` 本机无 Xcode（仅 CLT），`XCTest` 模块不可用，属环境限制。
- `script/build_and_run.sh package` ✅，候选包：`dist/魏碑.app`（commit 5fe5678，签名验证通过）。
- 草稿 MR：https://github.com/weibei-app/weibei/pull/210
- 教训：`ImmersiveHoverTitleView` 是泛型 View，嵌套类型在外部引用必须带泛型参数，
  独立顶层结构（`HoverTitleRename`）更省事。
- 验收回归修复（光标卡死在文本开头、无法输入）：编辑态 TextField 原先放在
  `ViewThatFits` 候选里，测量反复重建 NSTextField，selection 每次被重置；
  同时整条 tab 的 `PaneHeaderReorderModifier` 高优先级 DragGesture 会劫持
  文本框内点选。修复：编辑态走独立固定宽度布局（`renameField`，不进
  ViewThatFits），聚焦改在 `onAppear` 执行，编辑期间 reorderRole 置 nil 禁用
  拖拽。草稿始终只写本地 `@State`，提交/失焦/取消才写回 store。
- 复测修复（f1c8403）：① 重命名预填改为解析后的当前显示名
  （`noteTabTitleDraft = store.agentNoteTitle`），此前预填可能为空的
  customDisplayTitle，空框 + placeholder 旧标题造成"光标卡开头、打字盖住旧文字"
  的假象；② 删空回车恢复自动跟随路径补断言确认（空白=清除自定义名）；
  ③ 进入/退出编辑改用 `withAnimation(WeiBeiMotion.panel)` + `.transition(.opacity)`
  平滑过渡，宽度随动画插值。
- 复测修复（焦点从未进文本框，键盘输入落进正文）：根因是编辑态 TextField 随
  `.transition(.opacity)` 动画插入，`onAppear` 里同步设置 `@FocusState` 时
  NSTextField 尚未挂进窗口响应链，焦点请求被静默丢弃；且 `@FocusState` 内部已
  记录为 true，后续重复赋 true 被当作无变化，不会重试——first responder 一直
  留在正文编辑器（WKWebView）。修复（`ReaderView.swift`）：聚焦推迟到下一
  runloop，并在插入动画结束（+0.35s）后复查，若窗口 first responder 仍不是
  文本编辑（field editor 是 NSTextView）则 false→true 切换强制重新申请；
  复查用 `@State renameFieldAlive` 判断编辑是否已结束（逃逸闭包里值类型捕获的
  `titleRename.isEditing` 是旧值），程序化切换用 `isReassertingTitleFocus`
  挡住“失焦即提交”。`WeiBeiSelfCheck` 补对应源码断言。
  取证附记：诗歌笔记（El hombre imaginario）正文在磁盘 workspace.json 中完好
  （与 /tmp/workspace-before-repro.json 全量 diff 无差异），未发生误删持久化；
  卡死的测试实例（dist/魏碑.app, PID 49817）已 kill -9 防止退出时写回脏内存。
- 认知模型修正（本轮）：tab 显示名优先级从「自定义名 > 文件名 > 正文前几个字」
  改为「自定义名 > 正文抬头（文档首个 ATX 标题）> 文件名 > 正文前几个字」。
  用户认知里的"笔记标题"是正文大标题，文件名只是兜底；此前跟随文件名导致
  改正文抬头 tab 不跟随（诗歌笔记事故放大此问题：文件名是不可见的脏数据
  "的撒打算的"）。`NoteTabDisplayTitle` 新增 `bodyHeading(from:)`（只认文档
  顶部的 ATX 标题），`agentNoteTitle` 在无自定义名时始终取正文参与解析。
- 正文抬头驱动文件名：新增 `synchronizeNoteFileNameWithHeading`，在
  `persistNote` 成功落盘后检查——无自定义名且正文首个标题与文件名不一致时
  纯 `moveItem` 改名（不重写内容、inode 不变、指纹与 bookmark 保持有效，
  冲突时按 `renamedNotebookURL` 规则追加序号；课程文件不动）。用户设过
  自定义名则不跟随（不干涉原则）。
- 数据层修复（不进仓库）：诗歌笔记磁盘文件已由"的撒打算的.md（内容为默认
  模板）"修复为 `El hombre imaginario.md`（内容为真实诗歌正文），
  workspace.json 的 title/subtitle/lastKnownPath 同步；修复前已备份。
  系统性根因（双真相源分叉、fileID 漂移、模板覆盖通道）的审计报告与
  P0/P1/P2 加固计划见主会话，后续单开任务处理。
