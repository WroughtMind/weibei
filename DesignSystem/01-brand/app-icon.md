# App Icon

## 一张 PNG 为什么不够

原始 Logo 图是 1254 × 1254 的 RGB 图片，米纸已经烘焙进去。它不是 macOS 标准母版，没有透明外框，也没有 16、32 和 64 px 的光学适配。直接缩小后，拓印纹理会变成噪点，朱砂方块在 16 px 里接近消失。

仓库采用 SwiftPM 和手工 `.app` 打包。macOS 27 需要 Icon Composer 图标经 Xcode 编译后的动态资源；只把 PNG、SVG 或 ICNS 放进 Resources，都不能得到新系统的动态外壳。

## 已交付

- `weibei-app-icon-1024.png`：完整拓印母版，透明外框；
- `weibei-app-icon-small-optical-1024.png`：低纹理、小尺寸专用；
- `AppIcon.icon/`：保留原米纸、拓印和朱砂的 macOS 27 动态图标源；
- `AppIcon.iconset/`：macOS 十个标准槽位；
- `AppIcon.appiconset/`：Xcode 资产目录与 Contents.json；
- `AppIcon.icns`：DMG、Finder 和其他传统场景的静态导出；
- `previews/`：浅色、深色和尺寸预览。

## macOS 27 处理

`AppIcon.icon` 不把 W 内部的每个拓印缺口当成独立玻璃边缘。米纸、墨色 W 和朱砂作为一个保真画面，系统只对整个图标外壳施加高光、圆角和外观变化，避免把拓印变成塑料浮雕。

## 尺寸策略

| 输出像素 | 图形处理 |
|---:|---|
| 128–1024 | 保留纸纹与拓印纹理 |
| 64 | 使用干净轮廓，朱砂略放大 |
| 32 | 纯色轮廓，确保两个负形分开 |
| 16 | 纯色轮廓，朱砂保持可见；若实际像脏点，可在最终实机版省略 |

## macOS 十槽

| 文件 | 像素 |
|---|---:|
| `icon_16x16.png` | 16 |
| `icon_16x16@2x.png` | 32 |
| `icon_32x32.png` | 32 |
| `icon_32x32@2x.png` | 64 |
| `icon_128x128.png` | 128 |
| `icon_128x128@2x.png` | 256 |
| `icon_256x256.png` | 256 |
| `icon_256x256@2x.png` | 512 |
| `icon_512x512.png` | 512 |
| `icon_512x512@2x.png` | 1024 |

## 验收位置

必须在真实应用里检查 Dock、Finder、Spotlight、About、通知、设置和浅 / 深色桌面。不要只看 1024 图片。重点看 16、32、128 px 是否仍能看出三柱 W，朱砂是否像污点，图标和 Notes、Safari、Obsidian 并排时是否过满。
