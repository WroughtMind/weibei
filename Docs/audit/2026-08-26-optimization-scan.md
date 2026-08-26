# 优化全景扫描（2026-08-26）

**性质：** 一次性快照，不回头更新。四路侦察：性能热点 / 路线图落地状态 / 体验与正确性遗留 / 工程效率与资源。全部条目有代码或文档证据。
**背景：** 体检路线图（决策 5–13）与近期性能战役（聊天滚动 / 侧栏 / picker / 流式渲染 / 公式扫描）均已闭环，不重复列。`2026-08-22-audit-remediation-roadmap.md` 批次表标「待做」已滞后，勿当现状。

## 第一梯队 · 快赢（小时级 ~ 半天）

| 项 | 维度 | 问题 | 工作量 | 证据 |
|---|---|---|---|---|
| 冷启动去全文件 SHA256（**推荐首刀**） | 性能+红线 | init 主线程两次 `refreshRuntimeItemURLs()`，每个带 digest 的资料整文件读+哈希两遍；且 digest 断链违反「文件即真相」红线（最后残留） | 半天+验证 | `WorkspaceStore+LibraryRoot.swift:271-284`；方案已落档 `Docs/plans/2026-08-26-startup-digest-decouple.md` |
| 记忆「先给我看」口径打架 | 体验/正确性 | 系统提示要求不得写入、无确认卡 UI、验收清单要求当场写入，三处互斥 | 半天 | `AgentResources/system.md:174-177`；`NativeAgentTools.swift:598`；验收清单草稿:13 |
| 输入框 agentDraft 隔离 | 性能 | 每敲一字整棵 AgentPaneView（含消息 WKWebView）参与更新 | 小时级~1天 | `NotesAgentView.swift:251-252`；`WorkspaceStore.swift:345` |
| 侧栏 noteText 订阅收窄 | 性能 | 打字每 120ms 全量 rebuild 侧栏投影，仅为刷新标题来自正文的条目 | 小时级 | `CourseSidebarModel.swift:163-173` |

## 第二梯队 · 半天到两天

| 项 | 维度 | 问题 | 工作量 | 风险 | 证据 |
|---|---|---|---|---|---|
| 重命名 identity `?? original` 兜底 | 数据安全 | 改名/移动后偶发对账与身份自愈异常 | 半天~1天 | 低 | `WorkspaceStore+NotesPersistence.swift:272,317` |
| 未落盘草稿常驻可见性 | 数据安全 | 写盘失败后草稿优先于磁盘，用户不知未落盘（P0 的 P1 项） | 1~2天 | 中 | `2026-08-15-note-persistence-hardening-p0.md:34-36` |
| SQLite 连接复用 | 性能 | 每次 lookup/index 开关一次库，首延迟不稳 | 小时级~1天 | 中 | `CourseDocumentSearchIndex.swift:1713-1743` |
| init 同步瀑布拆分 | 性能 | 首帧前只留最小可渲染状态（与 SHA256 项叠加效果最好） | 1~2天 | 中 | `WorkspaceStore.swift:1022-1096` |

## 第三梯队 · 需要规划的大件

| 项 | 维度 | 问题 | 工作量 | 风险 | 证据 |
|---|---|---|---|---|---|
| WorkspaceStore 课程域拆分 | 工程效率 | 21731 行单文件，增量编译瓶颈；课程/对账域约占一半可剥离 | 中大 | 中 | `WorkspaceStore.swift`（L1000-8000, L17800-20700） |
| 聊天 WebView 卸载策略 | 运行时内存 | Eager VStack 挂载后永不卸载，展开历史只增不减 | 中大 | 高（Lazy remount 卡死雷区） | `NotesAgentView.swift:1452-1456` |
| workspace.json 消息外置 | 磁盘+启动 | 全量会话消息正文内嵌主快照无上限 | 大 | 高（数据模型迁移） | `WorkspaceModels.swift:2040-2042` |
| 3 秒轮询 → FSEvents | 功耗 | App 存活期每 3 秒全量对账课程文件 | 中 | 中 | `WorkspaceStore.swift:18612-18633` |
| Agent 工作区级检索工具 | 功能缺口 | 级联检索到课程层即止，跨笔记搜不到 | 中大 | 中（课程隔离护栏） | `NativeAgentPrompt.swift:78-79` |

## 卫生区 · 顺手清理

| 事项 | 说明 | 工作量 | 证据 |
|---|---|---|---|
| StreamFinalizeProbe 探针清理 | 流式闪动已修复，调查探针仍挂主路径 | 小 | `StreamFinalizeProbe.swift:5-8` |
| 高度缓存加上限 | `AgentFinalizedMarkdownHeightCache` 无界字典改 LRU | 小 | `NotesAgentView.swift:4697-4716` |
| SystemAppearanceObserver 移除 | onAppear 注册 Distributed 观察者无对称移除 | 小 | `WeiBeiApp.swift:502-520` |
| Attachments 孤儿回收 | 图片只写不收（需按 markdown 引用安全 GC） | 中 | `MarkdownAttachmentStore.swift:19-82` |

## 开工前置提醒

- 工作树有在途的「测试错误类型化」改造（约九成完成、未提交、在 main 上落后 origin/main 4 提交）：任何新刀开工前先归置它。
- 验证手段现成：`WEIBEI_PERF=1` 启动指标 `beginLaunch→finishLaunch`；输入探针 `input.agent_to_next_main_queue_proxy`；`make check` 全自检。

## 建议节奏

先归置在途工作 → 启动 SHA256（方案已落档）→ 记忆口径 / 输入隔离按体感排 → 大件单独立项。
