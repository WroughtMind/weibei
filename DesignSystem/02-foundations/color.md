# 色彩

WeiBei 有两层颜色：品牌资产颜色和产品运行时颜色。两者气质一致，但用途不同，不能拿宣传图随机取样覆盖 App 的现有主题。

## 产品运行时：代码事实源

`Sources/WeiBei/Support/Theme.swift` 是当前 App 的色彩事实源。以下数值应原样进入语义 token。

### 纸面主题

| Token | 值 | 用途 |
|---|---:|---|
| `surface.paper` | `#F4EAD5` | 主工作面 |
| `surface.paperRaised` | `#F9F1DE` | 抬升面、浮层 |
| `surface.paperInset` | `#E8DBBF` | 输入、内嵌区域 |
| `text.ink` | `#1D1814` | 主正文 |
| `text.secondaryInk` | `#55493E` | 次级正文、说明 |
| `text.tertiaryInk` | `#7D6E5D` | 占位、弱提示 |
| `accent.cinnabar` | `#91261B` | 当前落点、关键动作 |
| `accent.link` | `#305469` | 链接、引用、焦点 |
| `accent.moss` | `#3B624C` | 成功、稳定状态 |

### 墨石主题

| Token | 值 |
|---|---:|
| `surface.paper` | `#0F0F0F` |
| `surface.paperRaised` | `#151515` |
| `surface.paperInset` | `#1C1C1C` |
| `text.ink` | `#D7CBB0` |
| `text.secondaryInk` | `#9B9178` |
| `text.tertiaryInk` | `#6F6655` |
| `accent.cinnabar` | `#A6362B` |
| `accent.link` | `#C8B98A` |
| `accent.moss` | `#B88A42` |

墨石不是简单反相。它保留暖色文字和材料层级，不用纯白正文，也不把品牌变成蓝紫色科技界面。

## 品牌资产颜色

Logo、宣传图和社交图片使用锁定的展示色：

| Token | 值 | 用途 |
|---|---:|---|
| `brand.paper` | `#F2E2CA` | 宣传背景、App Icon 底面 |
| `brand.ink` | `#231F1C` | 干净 Logo |
| `brand.cinnabar` | `#AA2A23` | Logo 落印 |
| `brand.stone` | `#4D667A` | 宣传图定位线 |

这些色值来自已确认的视觉方向并经过规范化，不应从每张生成图重新吸色。

## 朱砂与石青的分工

- 朱砂：当前出处、当前落点、极少数主行动；同一视图只出现一个主要朱砂锚点。
- 石青 / link：链接、引用、跳转、键盘焦点和可操作证据。
- 系统错误：使用 macOS 语义红，并配合图标与文字；不能借用品牌朱砂。
- 颜色不能是唯一提示。选中、错误、离线和索引不完整都要有文字或图形差异。

## 当前漂移

`Sources/WeiBei/Resources/Editor/index.html` 仍有一套近似值，例如 `#F1E4CF`、`#F7ECD9` 和 `#31566B`。短期把它们记录为 Web 编辑器渲染补偿；长期应由同一个 token 构建步骤生成，避免 SwiftUI 与编辑器继续漂移。

## 对比度

正文、链接和控件文字至少满足 WCAG AA。纸纹不得降低正文对比度；实时阅读和编辑区域使用近乎纯色纸面，纹理只放在品牌图、空状态大面积留白或非正文边缘。
