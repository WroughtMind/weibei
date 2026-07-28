# 仓库映射

本设计体系依据 GitHub `weibei-app/weibei` 的 `main` 审查整理。

| 设计领域 | 当前事实源 |
|---|---|
| 产品定位与功能范围 | `README.md` |
| 包、平台和资源 | `Package.swift` |
| 色彩、字体、指标、动效、共享表面 | `Sources/WeiBei/Support/Theme.swift` |
| 字体注册 | `Sources/WeiBei/Support/WeiBeiResources.swift` |
| 纸面 / 墨石 Web 编辑器 | `Sources/WeiBei/Resources/Editor/index.html` |
| pane 模型与默认顺序 | `Sources/WeiBeiCore/WorkspaceModels.swift` |
| NSSplitView、宽度、模式、持久 pane | `Sources/WeiBei/Views/ContentView.swift` |
| 阅读 | `ReaderView` |
| 对话与笔记 | `NotesAgentView` |
| 课程目录 | `SidebarView` |
| 命令面板 | `CommandPaletteView` |
| 空工作区 | `EmptyWorkspaceLauncherView` |
| 内容轨道 | `ContentRailView` |
| 设计回归断言 | `Sources/WeiBeiSelfCheck/SelfChecks.swift` |
| 历史视觉参考 | `DesignReferences/` |
| 手工应用打包 | `script/build_and_run.sh` |
| 发布元数据验证 | `script/verify_release_metadata.sh` |

## 文档与代码同步

改 Theme、pane 指标、字体边界或动效时，同一个提交应更新：

1. 对应源码；
2. `DesignSystem/08-implementation/tokens.json`；
3. 相关设计文档；
4. `WeiBeiSelfCheck` 的断言；
5. `DesignReferences/` 或新的视觉基线截图；
6. 必要时提升 `DesignSystem/VERSION`。

历史 `DesignReferences/` 是参考图库，不是 token 或组件状态的事实源。发生冲突时，以已测试的源码和本设计系统的明确决策为准，并补写 decision log。
