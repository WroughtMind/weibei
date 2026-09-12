# 魏碑应用

这里是 #452 已验收的 Mac Catalyst 产品实现，也是唯一应用入口。保留原工作区、课程资料库、Agent、阅读器、笔记编辑器与设置；SwiftPM 只承担共用代码和检查工具，不再构建另一套会话应用。

## 构建

需要完整 Xcode 26、Node.js 22 及以上。在仓库根目录运行：

```sh
npm ci
./script/build_and_run.sh package
```

输出为 `dist/魏碑.app`。本机默认使用 Apple Development 签名；`WEIBEI_SIGNING_IDENTITY=-` 可生成 ad-hoc 候选。`WEIBEI_TARGET_ARCH` 可指定 `arm64` 或 `x86_64`；正式安装包分别在对应架构的 Mac 上原生构建和检查，不把交叉编译当成 Intel 实机验收。最低系统为 macOS 14。

`project.yml` 描述应用、共用核心、有界 PDF 助手和原有 macOS 窗口桥接。修改目标配置时运行 `xcodegen generate --spec App/project.yml`，将生成工程和 scheme 一并提交；日常构建只使用已提交工程。直接和传递依赖由 `WeiBei.xcodeproj` 内的 `Package.resolved` 锁定，`Dependencies.json` 记录来源与资源完整性。原排版补丁继续应用于同一固定 MarkdownView 提交。

主程序、PDF 助手、桥接和嵌套框架在最终签名前裁成单架构。资源字体、公式、图片和图表保留；编译期框架头文件与模块接口不进入安装包。调试符号在 App 外单独保留并核对 UUID。安装包沿用根目录 `script/build_release_dmg.sh`，详见[双架构发布流程](../Docs/releases/dual-architecture.md)。

临时（ad-hoc）签名没有开发团队身份，根应用需带 `disable-library-validation` 权限才能动态加载窗口桥；其强化运行时和嵌套签名仍保留。开发签名和 Developer ID 签名不添加此权限。静态验签不能替代实际启动检查。

## 身份、数据和更新

正式身份保持 `com.changfenhuang.weibei`，名称为“魏碑”，使用原有工作区初始化方式和资料目录。版本、构建号、源码提交及干净状态写入 App 元数据；两种架构使用同一源码和功能，分别选择自己的更新源。

其他候选身份继续在各自应用支持目录下隔离工作区、资料库和账号；不会混合或覆盖已验收候选和正式工作区。原备份、编辑器快照与唯一写闸门保持不变。

既有 Sparkle 2.9.6 随 macOS 窗口桥接嵌入一份，通过同一更新服务连接设置和顶部更新入口。继续验证更新清单签名，并在解压前验证更新包。开发签名、ad-hoc 签名、分发签名、公证和公开发布是不同状态；生成候选不会创建 Tag 或 Release。

## 共用实现

| 部分 | 实现 |
| --- | --- |
| 会话 | UIKit 复用列表，MarkdownView / Litext 排版与尺寸缓存；只同步实际变化的消息 |
| 资料和模型 | 原 WorkspaceStore、会话、Agent、账号服务与流式 HTTP 客户端 |
| 阅读与笔记 | UIKit PDFKit / WKWebView 接入原阅读器、编辑器资源和协议，保存经过原快照、写闸门与备份 |
| 工作区 | 原 SwiftUI 产品界面和常驻分栏，保留字号、八主题、抽屉与浮动会话 |
| 桌面与更新 | 原公开 Objective-C 桥接提供窗后材质、光标、文件动作和 Sparkle 更新 |

正文不截断或默认折叠，代码、公式、表格、图片和关系图实际渲染。中英文粗斜体、阅读位置、空白滚动、顶部浮动栏和分隔线改宽继续使用已验收实现。

## 验证

生产构建排除演示会话与自动验收代码。只有 `WEIBEI_ACCEPTANCE_CHECKS=1` 的隔离验收构建包含这些入口，输出到 `dist/acceptance/魏碑.app`。

`App/script/check-ci.sh` 只允许在 CI 独立桌面运行：从唯一构建入口生成隔离身份，检查 12 项会话行为，再用本地 HTTP/SSE 服务验证原资料导入、编辑器保存、PDF 助手、Agent 工具、流式回答、停止、分栏、主题及保存后重新打开。固定服务不是在线模型，不产生真实模型验证结论。

旧验收证据保留在 `Evidence/`。每次新候选按实际提交记录结果；进程内检查不替代鼠标、中文输入法和触控板手感，显示回调计时也不等同于 FPS。本机真实操作只使用画中画。
