# 动效

`Sources/WeiBei/Support/Theme.swift` 中的 `WeiBeiMotion` 是当前事实源。不要另建一套时间常量。

## 现有 token

| Token | 当前实现 | 用途 |
|---|---|---|
| `press` | spring `0.18 / 0.82` | 按下反馈 |
| `micro` | easeOut `0.14s` | 小型状态变化 |
| `hover` | spring `0.20 / 0.86` | hover 进入与退出 |
| `reveal` | spring `0.24 / 0.88` | 局部内容出现 |
| `panel` | spring `0.30 / 0.88` | 抽屉、浮层、面板 |
| `layout` | spring `0.38 / 0.90` | pane 重排和布局模式 |
| `appearance` | easeInOut `0.42s` | 纸面 / 墨石主题切换 |

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
