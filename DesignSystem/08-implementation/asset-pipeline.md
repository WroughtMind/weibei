# 资产流水线

## 输入

- `assets/logo/reference/approved-textured-mark-1254.png`：宣传图样式的视觉参考；
- `assets/logo/source/weibei-mark-master.svg`：固定生产轮廓；
- `assets/fonts/WeiBeiStele.ttf` 与 `WeiBeiSteleMono.ttf`：仓库自有品牌字体；
- `assets/github/readme-hero-original-1983x793.png`：README 宣传图原始构图。

## 输出

`scripts/build-assets.sh` 生成透明、单色、反白、真实字体英文组合标、App Icon、Web、GitHub、Social 和预览图。它会保留原 hero 构图，但用 `WeiBeiStele` 替换生成图中的英文名称。`scripts/build-icns.ts` 把标准 PNG 槽位封装成现代 ICNS；`scripts/build-manifest.ts` 记录路径、体积与 SHA-256。这两个 Node 工具通过仓库根目录安装的 `tsx` 执行。

## 重建

```bash
DesignSystem/scripts/build-assets.sh
DesignSystem/scripts/verify-assets.sh
```

要求：ImageMagick、Node.js。脚本不依赖网络；字体渲染直接读取 `assets/fonts/`，SVG 是可编辑母版，PNG 的干净图形版本使用同一几何坐标机械绘制。

## 变更规则

- 轮廓变化：更新 SVG、脚本中的共享路径、小尺寸预览、decision log 和版本；
- 纹理变化：替换批准参考，重新导出并人工检查 128–1024 px；
- 朱砂变化：同时检查 Logo、App Icon、favicon 和产品语义；
- 只改单个导出文件无效，下次构建会覆盖；
- 生成后提交 `asset-manifest.json`，代码审查可直接看到哈希变化。

## macOS 原生重建

在 macOS 上也可以使用系统工具重建：

```bash
iconutil -c icns DesignSystem/assets/app-icon/AppIcon.iconset \
  -o DesignSystem/assets/app-icon/AppIcon.icns
```

提交前对比系统 `iconutil` 结果和脚本 ICNS 在 Finder、Dock 与 Spotlight 的显示。
