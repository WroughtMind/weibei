# 动效

`Sources/WeiBei/Support/Theme.swift` 中的 `WeiBeiMotion` 是当前事实源。不要另建一套时间常量。

## 现有 token

| Token | 当前实现 | 用途 |
|---|---|---|
| `press` | interactiveSpring `0.18 / 0.82` | 按下反馈 |
| `micro` | easeOut `0.14s` | 小型状态变化 |
| `hover` | interactiveSpring `0.20 / 0.86`（blend `0.02`） | hover 进入与退出 |
| `reveal` | interactiveSpring `0.24 / 0.88`（blend `0.04`） | 局部内容出现 |
| `panel` | interactiveSpring `0.26 / 0.90`（blend `0.04`） | 抽屉、浮层、面板 |
| `layout` | easeOut `0.18s` | pane 重排和布局模式（长弹簧在 WebView 面板上有迟滞感，改短 ease-out） |
| `appearance` | easeOut `0.12s` | 主题切换（更短的全局 ease，避免各面板失步） |
| `sideDrawer` | easeOut `0.12s` | 课程抽屉滑入滑出（纯视觉；绝不包住焦点变化） |
| `railPreview` | easeOut `0.15s` | 内容栏预览卡出现 / 消失（内容逐帧切换必须瞬时） |
| `hoverTitleFade` | easeOut `0.14s` | 沉浸式悬停标题栏淡入淡出（无停留、无面板弹跳） |
| `tabUnderline` | easeInOut `0.25s` | 课程页签下划线滑动（页面切换的唯一动效） |

斜杠后的数值沿用代码当前定义的 spring 参数；若 SwiftUI API 调整，以 `WeiBeiMotion` 的源码和 SelfCheck 为准。

## Transition 语义

保持现有命名：side panel、command palette、floating、drawer、right panel、layout、rail、message。新增转场先归入其中一个语义，不按页面随手造动画。

## 核心动效

- 点击引用后定位原文；
- pane 展开、休眠、重排，同时保持内容实例不被重建；
- 选区动作条出现与消失；
- 写入建议与差异确认；
- 主题切换，不闪白、不丢焦点。

## 限制

- spring 只用于直接操控的物理反馈，不做持续弹跳；
- 流式回答不使用打字机装饰，不让栏宽或上方内容抖动；
- 不使用循环呼吸光、无限 shimmer、粒子和红点闪烁；
- 主题切换过程中正文对比度始终可读。

## Reduce Motion

开启 Reduce Motion 时，布局位移改为短淡入淡出或立即切换；引用定位可以滚动但不使用长距离弹簧；hover 与 press 保留非位移反馈。实现读取 `accessibilityReduceMotion`，不要只在文档里声明支持。
