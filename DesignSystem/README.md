# WeiBei Design System

魏碑不是一款套着古风皮肤的 AI 聊天应用。它是一张可以阅读、书写、提问并回到出处的安静工作台。

这是 WeiBei `0.1.0` 的品牌与产品设计基线，依据仓库当前的 macOS 14+ SwiftPM 实现、README 产品叙事、现有“纸 / 墨 / 石青 / 朱砂”语言，以及已确认的宣传图 Logo 重建而成。

## 先说结论

原来的 `1254 × 1254` 图片可以作为高分辨率视觉参考，不能单独当作完整 App 图标交付。它没有透明通道、不是标准 1024 母版，也没有 16–512 pt 的尺寸适配；仓库当前的手工 `.app` 打包脚本还没有引用图标。

这套文件已经补齐：

- 宣传图观感一致的拓印纹理 Logo 母版；
- 固定轮廓的 SVG 生产版、透明版、单色版和反白版；
- macOS 十槽 `.iconset`、Xcode `AppIcon.appiconset` 和可直接复制的 `AppIcon.icns`；
- 16–64 px 小尺寸光学版、favicon、GitHub 头像、Social Preview 和 Open Graph 图；
- 从仓库同步的 `WeiBeiStele` / `WeiBeiSteleMono` 与使用真实字体导出的英文组合标；
- 产品视觉、交互、文案、动效、无障碍、SwiftUI 映射和 QA 文档；
- 可重复构建、校验并记录哈希的资产脚本。

## 设计判断

1. 内容和笔记是主角，Agent 在学习过程旁边工作。
2. “纸”是舒适的连续工作面，不是仿古背景贴图。
3. “碑感”来自方正、稳定、节制，不来自到处使用书法字体。
4. 朱砂方块只有两个相关含义：品牌中的落印；产品中的当前出处。它不是通知红点。
5. 图形与名称分开管理。产品仍可使用“魏碑 / WeiBei”，但名称决策完成前，不把文字焊死进图形母版。

## 从哪里开始

- 品牌定位：[01-brand/brand-foundation.md](01-brand/brand-foundation.md)
- Logo 规则：[01-brand/logo.md](01-brand/logo.md)
- App 图标：[01-brand/app-icon.md](01-brand/app-icon.md)
- 色彩与主题：[02-foundations/color.md](02-foundations/color.md)
- 工作区结构：[03-workspace/workspace-architecture.md](03-workspace/workspace-architecture.md)
- 组件清单：[04-components/component-inventory.md](04-components/component-inventory.md)
- 实现接入：[08-implementation/INSTALL.md](08-implementation/INSTALL.md)
- 发布验收：[09-qa/release-checklist.md](09-qa/release-checklist.md)

## 资产入口

| 目的 | 文件 |
|---|---|
| 视觉批准参考 | `assets/logo/reference/approved-textured-mark-1254.png` |
| 标准矢量母版 | `assets/logo/source/weibei-mark-master.svg` |
| App 图标 1024 | `assets/app-icon/weibei-app-icon-1024.png` |
| 手工打包用图标 | `assets/app-icon/AppIcon.icns` |
| Xcode 资产目录 | `assets/app-icon/AppIcon.appiconset/` |
| GitHub 首页宣传图 | `assets/github/readme-hero-1983x793.png` |
| GitHub 分享卡片 | `assets/github/github-social-preview-1280x640.png` |
| Web 图标 | `assets/web/` |
| 品牌字体与字样 | `assets/fonts/`、`assets/logo/exports/wordmark/` |
| 文件哈希与体积 | `assets/asset-manifest.json` |

## 母版优先级

1. 轮廓、比例和朱砂位置以 `weibei-mark-master.svg` 为生产基准。
2. 拓印质感以 `approved-textured-mark-1254.png` 为视觉基准。
3. 小于 64 px 使用光学版，不能机械缩小拓印纹理。
4. 所有导出由 `scripts/build-assets.sh` 生成，禁止手工另存一套“差不多”的文件。

## 重建与校验

```bash
DesignSystem/scripts/build-assets.sh
DesignSystem/scripts/verify-assets.sh
```

图像与品牌字样导出需要 ImageMagick；ICNS 与清单生成需要 Node.js。字体从本文件夹读取，构建不会联网。

## 当前接入状态

应用打包由 `make package` 统一进入 Swift CLI；`AppIcon.icns` 的复制与
`CFBundleIconFile` 写入属于 Swift 打包核心。根目录 Makefile 只表达任务
依赖，不承载图标复制、plist 生成或签名逻辑。
