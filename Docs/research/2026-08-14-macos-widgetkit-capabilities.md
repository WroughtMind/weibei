# 魏碑 macOS WidgetKit 能力边界研究

> 核验日期：2026-08-14  
> 资料范围：仅使用 Apple 官方开发者文档、Human Interface Guidelines 与 WWDC。  
> 用途：为魏碑首批桌面 / 通知中心小组件定范围；本文记录平台事实和落地约束，不是实现 PR。

## 结论

魏碑可以在 Mac 桌面和通知中心提供原生 WidgetKit 小组件。仓库当前最低系统是 macOS 14，正好可以直接使用 App Intents 配置、`Button` / `Toggle` 交互和桌面小组件，不需要兼容旧的 SiriKit 配置路径。

“响应式小组件”在 WidgetKit 中的准确含义是：**系统按时间线展示快照；用户点击按钮或开关后执行 App Intent、持久化结果并立即重载；其他区域通过深链接打开魏碑的准确页面。** 它不是常驻的小型 App，不能承载滚动课程列表、文本输入、聊天或任意手势。Apple 明确说明小组件通常只读，不支持滚动列表和文本输入；互动控件只支持绑定 App Intent 的 `Button` 与 `Toggle`：[Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)、[Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)。

首发尺寸宜只做 `systemSmall`、`systemMedium`、`systemLarge` 三档，并让同一种小组件按尺寸增减信息。`systemExtraLarge` 在 Mac 上可用，但不适合作为首版门槛；配件型小组件不出现在 Mac；Apple 在 WWDC26 宣布的竖向超大号 `systemExtraLargePortrait` 要到 macOS 27，当前仍不应成为生产基线：[Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)、[WidgetKit foundations — WWDC26](https://developer.apple.com/videos/play/wwdc2026/277/)。

## macOS 可用位置与尺寸

| Widget family | Mac 桌面 | 通知中心 | 首版判断 |
|---|---:|---:|---|
| `systemSmall` | 是 | 是 | 必做；单一重点、一个入口或一个快捷动作 |
| `systemMedium` | 是 | 是 | 必做；最适合课程续学、今日进度与名言卡 |
| `systemLarge` | 是 | 是 | 建议做；可放少量课程 / 学习项目，但仍不可滚动 |
| `systemExtraLarge` | 是 | 是 | 后续按真实需求增加，不作为首版门槛 |
| `systemExtraLargePortrait` | macOS 27 新增 | macOS 27 新增 | 目前不做；WWDC26 公布、macOS 27 仍是新系统线 |
| `accessoryCircular` / `Corner` / `Inline` / `Rectangular` | 否 | 否 | 不属于 Mac 小组件范围 |

Apple 当前尺寸矩阵明确列出 Mac 支持小、中、大、超大号，位置均为桌面和通知中心；配件型 family 的支持设备表不含 Mac：[Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)。原生 Mac 小组件与来自配对 iPhone 的小组件都能出现在 Mac，但魏碑已有原生 Mac App，应实现原生 Mac widget extension：[Widgets and watch complications](https://developer.apple.com/documentation/widgetkit/widgets-and-complications-collection)。

桌面位置是 macOS 14 新增能力；WWDC23 同时引入 Mac 桌面小组件、新内容边距、可移除背景和互动能力：[Bring widgets to new places](https://developer.apple.com/videos/play/wwdc2023/10027/)、[WWDC23 WidgetKit updates](https://developer.apple.com/documentation/updates/wwdc2023)。

## 交互能力与明确限制

| 需求 | WidgetKit 能否原生完成 | 正确做法 |
|---|---:|---|
| 点击课程后打开对应课程 | 是 | 给整体视图加 `widgetURL(_:)`，或使用 `Link` 指向课程深链接 |
| 一个中 / 大组件内打开不同课程 | 是 | 每一行用独立 `Link`；macOS 14 已支持小号及以上的多目标链接 |
| 在桌面直接完成“已学习 / 稍后继续” | 是 | `Button(intent:)` 或 `Toggle(..., intent:)` 执行 App Intent |
| 点击后立即看到状态变化 | 是，但由系统重载 | Intent 返回前先写完共享数据；返回后系统立即请求新时间线 |
| 展开、滚动完整课程目录 | 否 | 只展示固定数量摘要；点击进入 App |
| 在组件内输入问题、编辑笔记、聊天 | 否 | 深链接进入魏碑对应场景 |
| 任意点击、拖拽、手势或普通 SwiftUI 控件 | 否 | 互动只使用 App Intent 版本的 `Button` / `Toggle` |
| 像 App 一样持续运行和实时观察状态 | 否 | 依靠时间线、事件重载和系统支持的动态日期 |

Apple 的深链接规则：`widgetURL(_:)` 可让小组件打开指定 App 场景；较大布局可放多个 `Link`。当前策略文档说明 macOS 14 起 `systemSmall` 及以上都可使用 `Link`，macOS 13 及以前只有大号和超大号可用：[Linking to specific app scenes](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)、[Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)。

互动小组件从 macOS 14 起可用。按钮或开关触发 App Intent 的 `perform()`；Apple 要求 Intent 返回前完成持久化，返回后系统会立即重载时间线。普通控件不工作，单纯为了打开 App 的动作应使用 `Link` 或 `widgetURL(_:)`，而不是伪装成按钮：[Adding interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)、[Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)。

可配置小组件用 `WidgetConfigurationIntent`、`AppIntentConfiguration` 和 `AppIntentTimelineProvider`。这些 API 从 macOS 14 开始；魏碑当前最低系统已经覆盖，不需要旧版 SiriKit Intent 兼容层：[Making a configurable widget](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)、[Migrating from SiriKit Intents to App Intents](https://developer.apple.com/documentation/widgetkit/migrating-from-sirikit-intents-to-app-intents)。

## 更新与“实时性”边界

Widget extension 不会因为小组件在桌面上就持续运行。WidgetKit 在独立进程中按时间线归档 SwiftUI 视图，显示时由系统渲染。因此不能把 `@State`、长期观察器或持续轮询当作刷新机制：[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)、[Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)。

| 变化类型 | 应用机制 | 魏碑适用例子 |
|---|---|---|
| 可预测时间 | `Timeline` + `.atEnd` / `.after(date)` | 每日思想卡、下一次计划学习时间 |
| 只在 App 数据变化时更新 | `.never` + `WidgetCenter.reloadTimelines(ofKind:)` | 课程进度、最近打开资料、笔记计数 |
| 小组件内发生互动 | App Intent 完成后系统立即重载 | 标记今日学习完成、切换稍后继续 |
| 服务器主动变化 | WidgetKit push notification，可选 | 魏碑当前本地优先场景不需要首版引入 |

系统刷新不是精确定时器：时间线日期只是最早 / 期望更新时间，实际可能更晚。Apple 要求时间线条目通常至少相隔约 5 分钟；常看的组件典型预算为每天 40–70 次刷新，约 15–60 分钟一次，但预算会按可见频率、最近刷新和 App 活跃状态动态调整。开发者模式下不施加同样预算，因此必须离开 Xcode 调试器测试真实刷新：[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)、[TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider)。

这意味着“每秒变化的进度”不应进入首批组件。倒计时可使用 WidgetKit 支持的动态日期文本，而不是每秒重载时间线。课程进度应由魏碑写入后定向调用 `reloadTimelines(ofKind:)`，不要定时扫描整个工作区。

## 数据共享与进程边界

主 App 与 widget extension 是两个进程。Apple 的标准方案是让两个 target 加入同一个 App Group，在共享容器中读写小组件所需数据；少量设置可用 `UserDefaults(suiteName:)`，结构化数据 / 文件可用共享容器 URL：[Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)、[UserDefaults.init(suiteName:)](https://developer.apple.com/documentation/foundation/userdefaults/init%28suitename%3A%29)。

Apple 还建议由主 App 提前准备好小组件数据，而不是让 widget provider 临时做重活。网络请求虽受支持，但 extension 资源有限，系统可能在请求完成前终止它：[TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider)、[Making network requests in a widget extension](https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension)。

对魏碑的最小落地推论：主 App 每次课程、进度或最近资料真正变化时，写一份**小而稳定的共享快照**，再定向重载相应 widget kind。小组件只读取该快照，不扫描课程目录、不解析 PDF / Markdown、不启动模型、不实例化完整 `WorkspaceStore`。这既符合 WidgetKit 进程模型，也避免让桌面组件碰触原始课程和笔记文件。

## 隐私、性能与可访问性底线

### 隐私

- 小组件是高可见内容。首版默认不展示问题正文、回答、笔记正文、文件路径、API / 模型状态等敏感信息；课程标题也应允许使用通用占位或由用户选择是否显示。
- 对可能敏感的 SwiftUI 视图加 `privacySensitive(_:)`，并提供真实占位 / 脱敏状态。Apple 要求审查一直可见内容并支持敏感数据遮盖：[Creating a widget extension — Hide sensitive content](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)、[Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)。
- 共享容器只放渲染所需最小字段，不复制课程原文或完整笔记数据库。App Group 需要主 App 与 extension 都有匹配 entitlement，签名和发布验收必须同时覆盖两者：[Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)。

### 性能与视觉适配

- 小组件视图只使用 WidgetKit 支持的 SwiftUI；不能嵌入 `NSViewRepresentable` / AppKit 视图：[SwiftUI views for widgets](https://developer.apple.com/documentation/widgetkit/swiftui-views)。
- 时间线 entry 应直接包含渲染所需值；视图构建阶段不做磁盘遍历、全文解析、网络等待或模型调用。
- 使用 `.containerBackground(for: .widget)` 标识可移除背景，并服从系统 `widgetContentMargins`；Mac 桌面会根据环境采用全彩或 vibrant 等渲染，不能依赖固定背景和固定品牌色：[Displaying the right widget background](https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background)、[Preparing widgets for additional contexts](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)。
- 更新动画只用来说明状态变化，不把组件做成持续动效。Apple HIG 建议使用最多约 2 秒的过渡动画：[Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)。

### 可访问性

- 使用真实 `Text` 和系统字体，不把文字栅格化；一般字号不小于 11pt。这样文字能正确缩放并被 VoiceOver 朗读：[Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)。
- 给图片、进度、按钮和开关补充简短、随状态更新的 `accessibilityLabel`；Apple 要求小组件每次内容变化时同步更新对应无障碍描述：[Adding accessible descriptions](https://developer.apple.com/documentation/activitykit/adding-accessible-descriptions-to-widgets-and-live-activities)。
- 不只用颜色表达完成 / 未完成；同时使用文字、图形或符号。每个尺寸、浅色 / 深色、全彩 / vibrant、中文 / 英文和 VoiceOver 都要单独预览与验收。

## 魏碑当前仓库的直接影响

- `Package.swift` 当前最低系统是 macOS 14，平台能力无需再抬高部署版本。
- 当前仓库没有 widget extension target、Xcode 工程或 App Group entitlement。实现不只是新增一个 SwiftUI 文件，还必须产出可嵌入主 App 的 `.appex`，并把主 App / extension 的 App Group、签名、打包和候选包验收打通。
- Apple 的标准起点是添加独立 Widget Extension target；一个 extension 可通过 `WidgetBundle` 暴露多个 widget kind：[Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)、[WidgetBundle](https://developer.apple.com/documentation/widgetkit/widgetbundle)。
- 首版无需网络、推送、位置、Live Activity、macOS 27 专属 family 或新的第三方依赖。魏碑已有本地课程数据，App Group 快照 + timeline + App Intent + deep link 足够形成端到端闭环。

## 给后续产品计划的硬边界

1. 先做 2–3 种真正高频的信息 / 动作，不为每个尺寸各造一个“新组件”；同一 widget kind 自适应小、中、大尺寸。
2. 每个组件必须在两秒内让人看懂；交互只保留最重要的一个动作，其他点击进入准确 App 场景。
3. 组件展示的是主 App 已准备好的结果，不把文件系统、模型和课程业务逻辑复制进 extension。
4. 任何“实时”承诺都必须重写为时间线、事件重载或动态日期；不能承诺秒级、准点或后台常驻。
5. 首版验收至少覆盖：桌面 / 通知中心、小 / 中 / 大、浅色 / 深色 / vibrant、离开 Xcode 的真实刷新、App 未运行时点击、深链接准确性、互动后持久化、VoiceOver、隐藏 / 删除课程后的旧快照清理，以及候选包中 `.appex` 的签名与 App Group entitlement。

