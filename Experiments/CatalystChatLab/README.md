# 魏碑 · Catalyst 独立候选

沿用 #452，把已获用户认可的 UIKit UICollectionView + MarkdownView / Litext 会话接回原魏碑。正常入口直接使用原工作区、课程资料库、Agent、阅读器、笔记编辑器和设置；固定重放只用于独立检查，不替代真实业务。

## 构建与隔离

需要 Xcode 26、XcodeGen，以及本机可用的 Apple Development 签名身份和对应团队。运行：

```sh
cd Experiments/CatalystChatLab
./script/build.sh DEVELOPMENT_TEAM=你的开发团队编号
```

共享 scheme 为 `CatalystChatLab`，真正使用 `platform=macOS,variant=Mac Catalyst,arch=arm64` 目的地、Release 和 Mac idiom。最低系统为 macOS 14；实际架构以候选包记录为准，不把交叉编译当成 Intel 实机验收。

输出是 `dist/魏碑-Catalyst独立候选.app` 和同名 zip。开发签名覆盖主 App、资源、原有有界 PDF 助手和窗口组件；没有公证、合并或正式发布。缓存仅在本实验 `.build/`，不修改正式构建编号和发布脚本。

独立标识为 `org.weibei.CatalystCandidate452`。应用初始化原 store 之前设置原有工作区路径约定，使资料库、会话、备份和账号配置全部进入候选自己的目录。用户在候选设置中配置模型，不读取正式版凭据，不迁移生产资料。旧 `org.weibei.CatalystChatLab` 会话实验及已认可包保留。

`project.yml` 是目标描述；生成的 Xcode 工程和共享 scheme 一并入库。应用内的 `LabSourceRevision`、`LabSourceDirty` 记录实际构建来源。独立检查身份可通过 `LAB_BUNDLE_IDENTIFIER` 设置，不改变嵌入组件身份。

## 复用与平台接点

| 部分 | 实现 |
| --- | --- |
| 会话 | 保留原实验的解析、高亮、排版与尺寸缓存，消息为 section、正文块为复用 item；原业务只同步实际变化的消息 |
| 消息与模型 | 使用原 WorkspaceStore、StudySession、AgentMessage、Agent runtime、账号服务和 HTTP 流式客户端；发送、停止、来源和主要动作回到原入口 |
| 课程与资料 | 直接编译原业务、索引、文件事务与界面；适配文件选择、确认、系统打开和目录 API |
| 阅读与笔记 | UIKit PDFView / WKWebView 接入原阅读器、编辑器资源和协议；所有笔记保存仍经过原快照、唯一写闸门与备份 |
| 工作区 | 原 SwiftUI 产品界面放入 Catalyst 场景和常驻分栏；保留原布局、字体、八主题、抽屉与浮动会话 |
| Mac 窗口 | 独立签名的微型 macOS bundle 通过公开 Objective-C ABI 提供窗后材质、桌面光标和系统文件动作；窗口内容、列表和正文仍由 Catalyst / UIKit 承载 |

窗口组件与主 App 使用同一开发团队签名。没有关闭运行时库验证，没有私有桥接、叠窗或截图转发。CI 没有开发身份时只能产生 ad-hoc 构建检查产物，不能把它当作完整可交付包；真实候选由本机开发签名构建。

正文不截断或默认折叠。代码、公式、表格、图片和关系图实际渲染；原 GenUI 通过原内容块及动作入口呈现。有效内容准备结果与 cell 生命周期分离，离屏视图有界复用，图片到达和改宽由同一个会话控制器处理阅读位置。

## 来源

业务来源为已合并主线 `02555d8506504e9fd68374855d3cff87428c9eb6`，本分支合入记录 `7511383f`。保留 `930c6035` 会话实验及更早用户体验包的源代码和原始证据。

直接与传递 Swift 依赖由共享 scheme 的 `Package.resolved` 锁定；`Dependencies.json` 记录公开提交、Mermaid 包完整性及浏览器产物哈希。许可证随包保留在 `ThirdPartyNotices.txt`。MarkdownView / Litext 上游源码未修改。lody-ios 和 FlowDown 仅作公开实现研究，不是依赖，也未复制其 AGPL 实现。

## 验证入口与边界

- `script/check-ci.sh` 只在 CI 的独立桌面运行原 10 项会话检查；本机真实操作必须使用画中画。
- `script/business-server.py --output .build/BusinessServer` 提供本机固定 HTTP/SSE 数据，不是模型。只有单独 `.businesscheck` 身份且构建时设置 `LAB_BUSINESS_CHECK_ENDPOINT=http://127.0.0.1:端口/v1` 才自动运行原业务往返检查。它覆盖导入、原编辑器和写闸门、有界 PDF 助手、Agent 读取工具、流式、来源、图片、答案入笔记、停止及重开。
- 原笔记和存储隔离检查复用现有 Swift 测试；不另建大矩阵。

旧会话证据在 `Evidence/`。新完整候选的检查必须重新记录，旧 10/10 和性能数值不自动代表业务接入后的表现。首次准备、缓存后回看、改宽和内存分别报告；显示回调与组件耗时不能换算为 FPS。

当前仍在修复和验证完整候选，尚不能宣称全部功能与真实手感验收通过。真实模型服务、鼠标拖选、中文输入法、焦点与附件横向滚动必须分别如实记录。会话路线验证成功不等于正式魏碑整体迁移成功。
