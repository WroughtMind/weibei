# 富回答验收真实图像资产

本目录只用于富回答验收素材留档，不是 App 资源目录，后续接入案例时再从这里挑选。

- `originals/`：尺寸和体积符合仓库边界的原图。
- `processed/`：适合验收包与对话流展示的无裁切、无拉伸副本。
- `manifest.json`：逐项记录来源、许可依据、尺寸、哈希、处理命令。
- `ATTRIBUTION.md`：署名文本和使用注意。
- `COLOR_CONTRAST_WEIBEI_SCREENSHOT_SPEC.md`：颜色对比题必须使用魏碑自身可复现界面截图的采样规范。

体积边界：超过约 15MB 或长边超过 4000px 的原件只在 `<temporary-directory>/weibei-rich-answer-source-assets/` 下载和哈希核验，仓库只保存长边 2400–3200px 的高质量衍生图。
