# ChatRendererLab — 阶段 A：候选资格验证

这是 PR #451 的实际 AppKit 候选接线，不是迁移决定，也不是 #449 的主会话列表实现。

## 做了什么

固定 `Lakr233/MarkdownView@757b6fcc4b3095e84f4c0613f4b98147f49dcd09`，直接调用它的 macOS `MarkdownTextView` / Litext 正文，不创建简化 TextKit 替身。候选有基础富文本、单条长文、长代码表格、能力缺口四类合成样本，以及合成流式重放。最后一类明确不计作功能已通过。

`CandidateDocument` 串行解析、合并待处理快照，在主线程准备数学/高亮上下文；可回收显示宿主不持有唯一的准备结果。`CandidateHost` 实际使用候选的测量和显示对象；允许一次完整测量后复用，不把“不是 TextKit 视口排版”当失败理由。这里没有生产历史分页、动作卡或列表复用。

`background_parse`、`main_prepare`、`main_apply_and_layout`、`main_measure`、`submitted_to_apply` 分别记录。它们是候选组件数据，不是屏幕 FPS、完整高亮完成时延或与魏碑的速度比。自动验证中的等待与截图也不计作真实滚动基准。

## 运行

需要 macOS 14+、支持 Swift 6 的 Xcode 工具链和网络解析依赖。

```sh
# 在仓库根目录；三个模式共用同一构建/装配入口。
bash Experiments/ChatRendererLab/script/build_and_run.sh package
bash Experiments/ChatRendererLab/script/build_and_run.sh verify
bash Experiments/ChatRendererLab/script/build_and_run.sh run
```

候选位于本目录 `.artifacts/WeiBeiChatRendererLab.app`。Bundle ID 独立，不读资料库、Keychain 或模型配置，不替换魏碑。`run` 仅在用户主动运行时打开实验窗口；`verify` 从 App bundle 启动隐藏窗口，不抢前台。不要直接从 `.build` 执行 GUI 二进制。

`verify` 暂时移动**本实验自己的** `.build`，结束后恢复，防止字体/资源从编译目录加载而掩盖缺包。资源放在 `Contents/Resources`。首次真实 macOS 编译后发现 app 根符号链接会被签名拒绝，已移除；现在仅对本实验解析的 SwiftMath / Highlightr checkout 做明确的资源查找补丁（`script/prepare_app_resources.py`），优先从标准资源目录读取，再保留命令行回退。补丁不改渲染算法，不写入生产依赖，也不使用未签名根目录绕过验证。此装配方式只用于实验，不修改魏碑的正式打包脚本。候选只做本机 ad-hoc 签名，不是公证/正式发布产物。

独立工作流生成真实解析出的 `Package.resolved`、依赖树、环境/源码状态、构建日志、隐藏窗口行为报告与合成截图。传递依赖首次解析后须以该锁文件保持后续 A/B 一致；在锁文件取回之前，不宣称整个依赖图已固定。

## 自动检查说明

| 检查 | 证明什么 | 不证明什么 |
|---|---|---|
| 富内容复制与数学资源 | 已显示文档的可读内容有代码、表格文字和尾段；数学图像可生成 | 所有字形/公式视觉正确，或图片/GenUI 已适配 |
| 长文改宽与重复测量 | 改宽重排、恢复宽度得到一致高度、不重复解析原文 | 生产列表锚点、实际触控板 FPS |
| 流式与会话切换 | 中间结果可应用、尾部不遗漏、旧任务不覆盖新文档 | 高亮最终完成延迟、所有选择范围更新规则 |
| 重挂准备结果 | 新宿主能使用已有正文，未再次解析 | NSTableView 行复用与卡片草稿完整性 |

检查失败保持失败，不删样本、不靠退回纯文本通过。源码语法检查不等于 macOS 类型检查，单架构 CI 不等于 Intel/全部系统验收。

## 进入阶段 B 的必要条件

#449 将真实列表接线推送后，复用同一宿主与输入数据，比较真实魏碑正文和候选正文，而不是两个不同 Demo。正文宽度、字号、内容、流式输入、读取位置回弹修复一致；候选可以使用自己的合理准备/测量策略，冷启动和回看都要计入。先以实际热点判断价值，再补齐以下仍未完成的生产功能；缺功能的版本不能作为最终赢家：图片、来源/wiki/callout、Mermaid/GenUI、动作卡草稿、流式选区、主会话与浮窗位置维护，以及与魏碑现有 SwiftMath fork 的依赖兼容。

## 许可证与取证

代码为本实验新写，没有复制 lody-ios 的实现。上游直接依赖 MarkdownView 及其传递依赖；构建把解析到的 checkout 中许可证文件随候选包含。没有把 README 的性能描述当成结果。参考入口：

- https://github.com/Lakr233/MarkdownView/tree/757b6fcc4b3095e84f4c0613f4b98147f49dcd09
- https://github.com/Lakr233/Litext
- https://github.com/Innei/lody-ios
- https://developer.apple.com/documentation/AppKit/NSTableViewDelegate/tableView(_:heightOfRow:)

未运行的 macOS 验证与真实会话 A/B 只能写“未验证”。没有合并或正式发布授权。
