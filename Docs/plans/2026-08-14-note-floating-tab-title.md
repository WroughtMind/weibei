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

（合并前补记）
