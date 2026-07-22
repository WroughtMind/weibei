# 魏碑第三方组件说明

本说明随魏碑安装包提供，记录当前已确认的主要第三方边界。项目级开源许可证以及完整的传递依赖许可证汇编仍需在正式公开 Release 前复核。

## 内嵌 Pi 运行体

- Pi coding agent `0.80.2`，固定源码提交 `0201806adfa825ab3d7957a4267d46e5030fd357`；
- 上游仓库：<https://github.com/earendil-works/pi>；许可证：MIT；
- 安装包保留 Pi 的 MIT 许可证、来源清单、下载产物哈希和签名后可执行文件哈希；
- 独立可执行文件由 Bun 编译。Bun 与静态链接传递组件的完整再分发材料仍是正式公开二进制发布前的检查项。

## 阅读与编辑器前端

编辑器静态资源由 `package-lock.json` 锁定的依赖构建，主要包括 Milkdown、KaTeX、Mermaid、PrismJS、DOMPurify 与 esbuild。锁文件记录实际版本、来源、完整性哈希和上游声明的许可证；正式公开 Release 前仍需生成逐项许可证清单并保留各许可证要求的正文。

## 内容与图像来源

应用内空工作台内容来源记录保存在资源包的 `Inspiration/SOURCES.md`；富回答验证图像来源保存在 `RichAnswerVerificationAssets/ATTRIBUTION.md`；魏碑 Logo、App 图标、品牌字体与宣传图的来源边界见随包的 `ASSET_ATTRIBUTIONS.md`。
