# 组件清单

这不是一份待实现的概念组件库。下面的名称直接对应仓库当前 SwiftUI / AppKit 结构，视觉修改应从共享组件进入，避免在各页面复制一份样式。

## 现有核心组件

| 产品角色 | 代码组件 | 规范重点 |
|---|---|---|
| 顶栏 | `UnifiedTopBarView` | 当前课程、模式和全局动作；不堆满工具按钮 |
| 栏标题 | `WeiBeiPaneHeader` | 短、稳定、可拖动；品牌字体只用于有限 Latin 标记 |
| 阅读 | `ReaderView` | 原文优先、选区动作、引用定位和滚动连续性 |
| 对话与笔记 | `NotesAgentView` | 回答、证据、写入确认和编辑状态 |
| 课程目录 | `SidebarView` | 课程层级、材料状态和当前位置 |
| 命令面板 | `CommandPaletteView` | 键盘优先、结果分组、明确执行范围 |
| 空工作区 | `EmptyWorkspaceLauncherView` | 一句说明、一个主要动作、少量入口 |
| 内容轨道 | `ContentRailView` | 休眠与展开、宽度恢复、可读阈值 |

## 共享表面

- `WeiBeiIconButtonStyle`
- `WeiBeiTextActionButtonStyle`
- `WeiBeiDialogButtonStyle`
- `weibeiInputSurface`
- `weibeiFloatingPanel`
- `weibeiAnnotationPanel`
- `WeiBeiGlassHeaderBackground`
- hover modifier 与 `WeiBeiTransition`

新增控件先判断能否扩展这些共享表面；只有行为或语义确实不同才建立新组件。

## App 文字按钮

`WeiBeiDialogButtonStyle(prominence:)` 提供五个层级。按钮角色、键盘快捷键和禁用状态仍由原生 `Button` 或 `Link` 管理。

| 层级 | 用途 |
| --- | --- |
| `primary` | 确认、保存、导入等主操作 |
| `secondary`（默认） | 与主操作并列的次要动作 |
| `tertiary` | 低强调的辅助动作 |
| `ghost` | 轻量就地动作，悬停显出浅底，按下内凹 |
| `text` | 导航动作，使用下划线和悬停时右移的箭头 |

`md` 对应默认 `controlSize`，基准为 14pt 字号、40pt 高。`lg` 使用 `.controlSize(.large)`，基准为 16pt 字号、约 45.7pt 高。按钮底面、边缘、图标与阴影按字号等比缩放，跟随 App 的文字大小设定。

浅色界面的 `secondary` 和 `tertiary` 使用白色键面和浅灰键面。深色界面使用两档中性石墨灰，保持主操作的视觉优先级。`ghost` 的悬停和按下使用中性灰键面，在纸色背景上也保持灰色。

## 必须覆盖的状态

每个交互组件至少记录并验收：

```text
default / hover / pressed / focused / selected /
disabled / loading / error / keyboard / VoiceOver
```

流式回答、索引和导入还要覆盖：暂停、取消、部分成功、离线、证据不足和恢复。

## 引用与出处

`CitationLink`、来源预览、当前出处锚点即使尚未独立成文件，也必须按同一语义实现：

- 可见名称包含文件与具体位置；
- hover 显示将打开什么；
- 点击定位后焦点和 VoiceOver 一起移动；
- 当前出处用石青高亮加朱砂落点，不能只变色；
- 找不到原位置时说明原因，不静默失败。

## Agent 与记忆

学习记忆、写入建议和差异确认都属于高风险操作面：显示来源、目标、变化和撤销方式。不要用“已帮你优化”替代具体差异。

## 组件审查问题

1. 它是否帮助用户阅读、定位、提问或记录？
2. 它是否抢走正文面积？
3. 状态是否只靠颜色表达？
4. 是否能键盘完成？
5. 是否能复用现有共享表面？
6. 去掉 Logo 后，它是否仍然像一个长期阅读工具，而不是通用聊天壳？
