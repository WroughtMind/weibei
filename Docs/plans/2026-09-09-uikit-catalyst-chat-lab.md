# 魏碑 Catalyst 完整候选接入方案

日期：2026-09-09。原 PR：[#452](https://github.com/WroughtMind/weibei/pull/452)，标题和分支保持不变。

**状态：方案已按用户追加要求重定范围，完整魏碑候选尚未完成。** 已交付的 930c6035 是固定重放会话实验，只证明这条会话路线能够运行，不是完整魏碑。现有成果继续使用；正常产品入口必须接入魏碑原有业务、文件与真实模型，不能再以实验正文或简化资料库结束任务。

## 1. 最终交付和明确边界

交付一个能在 Mac 上使用的独立「魏碑·Catalyst 候选」App：课程和资料、阅读、选区提问、真实会话、笔记、关联与记忆、设置和桌面操作使用现有魏碑业务；会话核心明确采用 Mac Catalyst + UIKit UICollectionView + MarkdownView / Litext UIKit。允许复用适合的 SwiftUI 外层。正文不能替换成 AppKit、SwiftUI List 或整页网页会话。

三个交付对象必须分清：

| 对象 | 作用 | 能否作为本次最终交付 |
| --- | --- | --- |
| 已有固定重放实验 | 可复现内容、流式、滚动和富内容验证；继续保留源代码、检查和旧证据 | 不能 |
| 本次完整魏碑候选 | 接入原有产品业务，在独立资料目录中完成正常使用；界面品质与魏碑一致 | 必须交付 |
| 正式魏碑迁移与发布 | 决定替换正式架构、用户数据安排、正式签名、公证、更新和发布 | 本次未授权；另行决定 |

用户已授权本分支实施、验证、提交、推送、更新原 PR 和生成独立候选；未授权合并、发布、替换正式 App、迁移用户资料或读取生产凭据。候选的资料迁移功能只能在其独立测试资料上验证；不能借「完整产品」自行迁移正式资料。

不重新讨论是否选 UIKit，不以开发成本预先排除此路线，也不预设它获胜。视觉、数据安全和正常桌面使用任一不达标，都不能靠滚动数据掩盖。

## 2. 本轮核验的真实起点

| 项目 | 已核实事实 |
| --- | --- |
| 工作目录 | /private/tmp/weibei-catalyst-452；独立克隆内只有本任务工作树，分支 codex/uikit-catalyst-chat-lab |
| 已推送实验 | 930c603517c80379d372a61274980c504e4ba3e6；原 PR 开放，读取时没有评论、行评论或评审 |
| 产品功能基线 | 已合并 main：02555d8506504e9fd68374855d3cff87428c9eb6；本分支通过 7511383fae1ea2d01d90c24897fc762cd37f177d 合入此主线 |
| 主线增量 | 相对实验初始主线 429a86fc，包含已合并的 #450、#453、#454；没有迁入 #449/#451 的未合并成果 |
| 现有目标 | Experiments/CatalystChatLab 已有独立 Xcode 项目、CatalystChatLab target / scheme、资源、锁文件和构建脚本，继续沿用 |
| 工具环境 | Xcode 26.6（17F113），macOS SDK 26.5；本机 macOS 27.0（26A5421a）、arm64；真正 Catalyst 编译目标使用 macabi |
| 已证明的应用资格 | 930c6035 的 Release Catalyst 构建、UIKit 链接、资源、临时签名与进程内 10 项会话检查已通过；这些结果仅适用于该实验提交 |
| 当前未提交施工 | 已加入业务源码引用和少量平台接点；WeiBeiCore 的部分构建通过，但仍排除了快捷键文件，随后纳入 WorkspaceStore 的完整目标尚未构建通过，不能称完整业务已接入 |
| 真实操作工具 | 本任务显式应用路径、重新取得窗口及刷新辅助功能树后，坐标拖动/滚轮仍返回 noWindowsAvailable；辅助功能操作和截图能工作。已协调各任务独立窗口，未重启共享服务或抢占用户桌面 |

遵守根 [开发规则](../../AGENTS.md)；本轮检索修改目录没有其他 AGENTS.md。其他任务的源码、构建缓存、运行进程和发布流程不属于本任务。若后续发现共享文件的新重叠，先登记并协调该文件的修改范围，不将其他路线的完成作为前置条件。

## 3. 功能对齐：按现有产品入口交付

下面的「接入」是实施要求，不代表现在已经完成。每一行最终必须记录候选实际结果和证据，不能因为表格写了「复用」就标记通过。相对下列已合并基线没有的产品能力，不自行编造为既有功能。

| 产品入口与行为 | 主线实际实现 | 候选接入与必要适配 | 当前缺口 |
| --- | --- | --- | --- |
| 空白入口、继续上次工作 | EmptyWorkspaceLauncherView、WorkspaceStore+WorkResume；恢复资料、笔记、会话、草稿、布局和窗格顺序 | 复用恢复点和打开动作；候选启动使用独立的同格式工作区；关闭与重开接回原保存流程 | 目前默认仍是实验窗口；正常启动、保存时机未接入 |
| 课程与资料库 | SidebarView、CourseSidebarModel、CourseWorkspaceView；WorkspaceStore+CourseLibrary、+LibraryRoot、CourseProjectRootSupport | 课程创建/管理、通用资料/笔记、课程文稿/笔记、文件导入、重命名、关系移除及原文件删除均调用原业务事务；文件选择与确认界面改用 Catalyst 可用界面 | 系统文件面板和同步确认框尚未适配；不得自动选覆盖或删除 |
| 课程空间 | CourseHubView、CourseDocNoteWorkspaceView、CourseRecordsView；概览、文稿与笔记、对话、课程记忆四个真实页面 | 优先复用既有 SwiftUI 页面、查询和操作；只替换平台宿主及确实不可用的界面 API | 页面尚未装入候选，不能缩成单一文件列表 |
| 文件即真相与异常恢复 | CourseFileWatchSession、+CourseMaintenance、+GoneImportedItems、+CourseLibraryVolatility、+SnapshotRecovery、+CoursePortable | 保留外部增删改、目录恢复、未物化 iCloud 文件、缺席保护、灰态条目、便携课程状态和失败提示；不在新 UI 另建一套判断 | 文件监视、目录权限和恢复需在候选实际运行验证 |
| PDF 阅读 | ReaderView 内 PDFKit 宿主、PDFReaderOpenSafety、ReaderPDFContentRailPreview、ReaderPDFRemarkMarks；有界取文助手与 Vision OCR | 使用 UIKit PDFView/PDFDocument；接回原页码、搜索、选区、来源定位、标记和目录预览；保留有界解析/OCR，不能只画首页 | 平台宿主、PDF 选区桥、标记及签名后的助手调用未贯通 |
| HTML / Markdown / 文本阅读 | ReaderView、ReaderWebRemarkMarks；Resources/Editor 的 viewer、selection 脚本及本地资源配置 | UIKit WKWebView 加载同一读取资源，沿用正文和选区消息协议；保留文章原内容、标题定位、搜索、本地图片、代码和公式 | 尚未接现有阅读器桥；不得将文件内容简单塞进实验消息冒充阅读器 |
| 选区、摘录与来源 | WorkspaceStore+SelectionRemark、SelectionAnchors、SelectionExperience、ExcerptBookView；updateSelection、openExcerptSource、openAgentReplySource | PDF/WK/会话选区均传原 SelectionContext 和文档锚点；选区提问、摘记、摘录本、回到来源、连续追问使用原动作 | 当前实验选区仅接合成内容，真实定位、摘录持久化未接入 |
| 会话创建、切换、历史恢复 | StudySession、AgentMessage、WorkspaceStore+SessionMessages、StudySessionMessagePersistence、StudySessionMessageStore | 原存储负责会话身份、完整消息、按会话加载、草稿与中断恢复；既有 UICollectionView 只负责显示、分批前插和阅读位置 | 已有未验证的 AgentMessage 显示接点，尚未订阅原 store；前 240 条不是历史总量上限 |
| 模型配置与真实 Agent | SettingsView / AgentSettingsView / AgentModelPicker、AgentAccountService；WorkspaceStore+NativeAgent、NativeStudyAgentRuntime、NativeLLMAdapterFactory | 复用已有服务、订阅/API/本地与自定义端点、配置切换、模型列表、认证、Agent 工具、上下文和检索；正常设置写入候选自己的凭据目录 | 当前回答仍是固定事件；真实设置、认证打开、发送和停止未接通；不另写仅支持一种模型的简化客户端 |
| 真实流式、停止、重试与动作 | askAgent、applyAgentProgress、AgentConversationRun、AgentStreamingDisplayPump、cancelAgentRequest、retryAgentRequest、confirmAgentReplyAction | 原业务拥有请求和完成状态；UIKit 按消息/块消费变化，来源、重试、复制、引用、写入建议直接调原方法；最终尾字、停止和切换会话不能重播 | 实验的流式正确性不能代替真实 Agent 路径验证 |
| 笔记编辑与安全保存 | RichMarkdownEditorView、NoteEditorBridge、NoteEditingSession、WorkspaceStore+NoteEditing、WorkspaceStore+NotesPersistence、NoteRecoveryStore、NoteBackupRing | UIKit WKWebView 加载同一 Milkdown 编辑器和协议；保留普通输入、中文、格式、斜杠菜单、选区命令、图片/公式/代码、目录、打字机模式及恢复；唯一写闸门不变 | 当前实验笔记只是进程内文本；原编辑会话、确认写入、磁盘验证和重开尚未接通 |
| AI 文稿建议与确认 | AgentDocumentConfirmationCenter / Overlay、AgentReplyActionPersistence、confirmAgentReplyAction、persistAgentActionNote | 原请求继续等待用户确认；保留预览/编辑/取消/确认和冲突状态，原动作确认后经原写闸门保存；普通手动编辑仍按现有自动保存语义 | 禁止用实验卡片「收录」代替生产动作与落盘确认 |
| 富内容与交互扩展 | 实验的 MarkdownView/Litext、SwiftMath、高亮/表格/图片/Mermaid；主线 AgentVisualizationView、NativeChatAttachment、AgentMessageContentBlock | 已有普通正文实现保留；真实 GenUI 用同一内容/事件协议的 UIKit WKWebView 承载，action 回调 submitAgentVisualizationAction；卡片草稿/折叠/交互状态归原消息存储 | 实验卡片尚不是完整 GenUI；真实来源、附件地址、动态内容块和状态恢复尚未对齐 |
| 文稿、笔记关联与 wiki | CourseRelationsView、CourseRelationGraphModel、NoteSourceRelations；openOrCreateWikiNote、课程文件关系事务 | 原关系查询/修改和 wiki 打开逻辑复用；不靠文件名另建独立映射，不丢课程作用域 | 真实关联页面和会话动作未接通 |
| 学习记忆与课程画像 | LearningModels、CourseKnowledgeIndex；persistNativeLearningUpdate、persistNativeCourseProfileUpdate、updateLearningMemory；课程记忆页面 | 保留更新依据、来源、编辑、解决/恢复、删除和课程/会话隔离；同一 Agent 回写真实存储 | 不能把合成「记忆卡」算作现有记忆系统已接入 |
| 搜索、导航与命令 | WorkspaceStore+GlobalSearch、CourseDocumentSearchIndex、CommandPaletteView、ContentRailView、Reader 搜索/页码/标题导航 | 全局搜索、当前资料搜索、导航前后、资料切换和命令面板接原动作；SQLite 索引保留 | 索引部分编译已通过；查询界面、来源跳转和文件更新后的结果尚未验证 |
| 主题、字号、语言、动态效果、快捷键 | Theme、WorkspaceStore+AppearancePreference、AppShortcutCatalog、SettingsView | 保留八主题、现有字体资源、90%–160% 字号档、中英文、动态效果偏好和快捷键录制/冲突规则；UIKeyCommand/UIMenuBuilder 适配桌面菜单 | 快捷键暂时排除是编译缺口，须纳回；主题和设置尚未接入，不能用默认 iOS 蓝色控件代替 |
| 窗格、焦点、窗口生命周期 | ContentView、StableDocumentWorkspace、WorkspacePaneState、PaneSeatMotion、App/WeiBeiApp | 同一 Catalyst 窗口中的阅读/会话/笔记常驻控制器，保留三栏、双栏、沉浸、重排、窄窗细轨、聚焦和开关；设置独立呈现；关闭、重开与多场景使用现有共享工作区语义 | 不使用 AppKit 叠窗或辅助阅读窗口拼接；关闭前保存和多场景编辑权尚需实测，不能预先称已支持独立多工作区 |
| 关于、反馈与候选来源 | SettingsView、WeiBeiAppBuildInfo、WeiBeiUpdateService | 关于显示独立候选版本/来源/许可；反馈沿用现有入口。正式更新安装通道与发布设施属于明确授权边界，候选清楚显示不接正式更新通道 | 不装入会覆盖正式应用的自动更新器，也不放无作用的「检查更新」按钮；这项发行差异单独报告 |

上表的源码均来自记录的已合并主线，平台适配落在本分支。源文件默认相对 Sources/WeiBei 或 Sources/WeiBeiCore；主要核验入口见文末。

## 4. 代码与数据边界

### 4.1 直接复用业务，不另造资料库

候选引用同一份 Sources/WeiBei/Stores、Editing 和所需 WeiBeiCore 代码。原 WorkspaceStore 仍是用户操作、课程、会话、笔记、关系和持久化的入口；显示控制器不能自己改 workspace.json、课程元数据或笔记文件。使用主线已有纯 SwiftUI 页面时引用原文件，不复制后分叉成第二套产品。

Xcode 引用目录本身不算适配完成。逐个核验依赖，AppKit 专属宿主不加入 Catalyst 编译；其对应的产品行为必须有真实 UIKit 实现。不可用的导入不能改名伪装，也不能用空函数、返回成功或整段排除业务来消除编译错误。需要平台差异时把分支限制在具体 API 接点，避免铺一层通用 AppKit 仿造接口。

### 4.2 已查证的 SDK 接点

本机通过 Swift 编译器对 arm64-apple-ios16.0-macabi 和实际 SDK 做资格检查，不运行测试数据操作：

| 接点 | 实际证据 | 必要处理及验证界限 |
| --- | --- | --- |
| UIKit、PDFView/PDFDocument、WKWebView | 实验 UIKit/WK 实际运行；PDFView/PDFDocument 类型检查通过 | 新阅读器须在真实文件上验证选区、搜索和定位；类型存在不等于阅读体验完成 |
| NSFileCoordinator、Dispatch 文件监视、作用域书签、startAccessingSecurityScopedResource、FileManager.trashItem | 同一份 Catalyst 正向探针类型检查通过，包括 .withSecurityScope | 保留原保护算法；验证书签重开、外部变化和受控删除真实行为，不因为类名含 NS 就删掉 |
| homeDirectoryForCurrentUser | 编译器明确报 Mac Catalyst 不可用 | 仅在 Catalyst 用 Foundation 的标准目录 API；生产默认目录语义维持原样 |
| Process.executableURL / run | 编译器明确报 Mac Catalyst 不可用 | 使用已验证可编译的 POSIX spawn 启动现有有界 PDF 助手；保持输入、输出、时间、内存和取消界限；当前尚无嵌入签名后实际调用证明 |
| NSOpenPanel / NSAlert / NSEvent / NSView / NSColor | 主线实际依赖 AppKit，不能在此 UIKit 目标整体链接 | 文件选择用 UIDocumentPicker；确认用系统 alert/sheet 并异步返回原业务选择；键盘、颜色与视图按平台类型适配；不嵌套事件循环伪造同步确认 |
| 本地资源、Bundle.module | 原 SwiftPM 与 Xcode framework 的资源布局不同 | 明确使用候选 app/framework bundle；包含原 Agent 提示与技能、编辑器、字体、公式等资源，离开 checkout 也能正常加载 |

仅有一个现有 PDF 工具进程负责有界取文，不承载阅读 UI、产品状态或 AppKit 窗口；不能把它扩成第二个应用来拼出 Catalyst 界面。

### 4.3 独立目录必须端到端成立

独立 Bundle ID 继续使用 org.weibei.CatalystChatLab；Xcode 目标、scheme、DerivedData、输出和验证数据沿用本实验目录。最终应用名称可以明确标识「魏碑·Catalyst 候选」，不改 PR 标题，不占用正式应用名称或安装位置。

启动必须在建立 WorkspaceStore、账号单例、索引和定时维护之前统一设置本应用独立路径。当前源码核验发现：init(workspaceDirectory:) 只控制工作区快照/会话/索引；bootstrapDefaultLibraryIfNeeded() 另调 CourseLibraryLayout.defaultRootURL()，未传工作区实例路径。因此不能把「初始化参数不同」当作资料库已经隔离。

采用现有 WEIBEI_WORKSPACE_DIR 约定，在候选进程内部设为其稳定的 Application Support 子目录，再初始化原 store；默认库根按现有规则位于工作区的独立同级目录。明确传入同一候选的备份目录；UserDefaults 以本应用域隔离；Agent 凭据、配置和运行目录使用候选 Bundle ID 对应目录。检查 NoteRecoveryStore、附件、课程索引、会话消息和草稿最终 URL，没有任何一个隐式落到正式魏碑路径。测试目录与日常候选目录也必须分开。

继续使用原 workspace.json、课程 .weibei 状态、Markdown 原文件、相对路径和会话消息文件格式。保留 NSFileCoordinator、唯一 writeNotebookMarkdownThroughGate、NoteBackupRing、写后重读、外部磁盘内容优先、待写草稿和缺席保护。用户普通编辑按原行为自动保存；Agent 建议仍必须通过其原确认入口。存储失败时不能展示「已保存」，也不能清空 pending 内容来换取窗口关闭成功。

候选首次启动不导入正式工作区、不搜索生产凭据、不迁移用户资料。测试使用本任务自建材料和用户在候选中明确打开的文件；真实模型由用户在候选设置里配置，不在聊天中索取密钥，不以固定回答掩盖网络失败。

### 4.4 当前未提交改动复核及处理决定

| 已有施工 | 用途与现状 | 继续实施前的决定 / 影响正式版的位置 |
| --- | --- | --- |
| Xcode 引用原 Stores/Editing/Core、编辑器资源及 PDF helper | 方向正确，但完整应用未编译，Core 暂排除快捷键 | 保留引用思路；按实际依赖完善，快捷键重新纳入；生成项目不能取代完整构建 |
| 原文件的条件 UIKit/AppKit import | 仅解决导入资格，内部 NSAlert 等仍未适配 | 每项按真实调用者核验，分支尽量收窄到 Catalyst；不进行无依据的批量替换 |
| OCR 缩略图、HTML 取文依赖、Agent 资源 bundle | 来自真实 SDK/打包差异 | 保留必要平台处理；验证图片像素、取文结果和离线资源，原 macOS 路径必须继续通过检查 |
| 文稿/缓存默认目录 API 替换 | 当前修改也影响原 macOS 路径，超出必要范围 | 收窄为 Catalyst 接点，原平台目录行为保持；先验证候选默认库与实际 store 一致 |
| 新增 NotebookWriteGate 并把原写闸门迁出 store | 为已取消的简化业务层做的提取；完整复用 store 后没有必要 | 取消这项多余提取，继续使用原 store 中唯一写闸门，不保留两个入口或新增第二条笔记写盘路径 |
| Catalyst PDF POSIX 启动路径 | API 编译已过，签名后运行与边界尚未验证 | 保留有界助手的方案，定向验证后才算接入；不把失败改成全量主线程解析 |
| ConversationController 的 AgentMessage 接点 | 还没有真实 store 订阅；只初步映射了文本与状态 | 沿用现有列表，补齐消息动作、来源和完整内容块；核验请求/会话代次，避免旧异步结果串到新会话 |
| 曾出现的简化 CandidateWorkspaceStore | 已删除，未编译或提交 | 不重建；使用原 WorkspaceStore 和原业务事务 |

这些决定不是删除功能以过编译。当前原始修改保留至核验完成，随后只整理本任务多余改动；不覆盖他人工作，不 reset 整个分支，不从头替换实验。

## 5. 产品结构与真实业务流

### 5.1 一个完整工作区

保持魏碑现在的产品结构：统一顶栏、资料抽屉/课程空间、阅读—会话—笔记三处常驻内容、可调整/交换/收起窗格、沉浸入口、选区操作和独立设置。窗口内部使用 UIKit 容器和真正子控制器；可移植的 SwiftUI 页面由 UIHostingController 承载。既有 AppKit StableDocumentWorkspace 的布局与保持内容不重建的规则是参照，其 NSView 宿主本身不进入 Catalyst。

默认显示正常空白工作区或用户上次内容，不打开实验历史。重放只通过明确的独立验证启动参数进入，不在正常界面塞实验开关、缓存统计或调试文案。未配置模型时正常提示配置入口；点击发送必须真实发送或给出明确错误，不能自动切到重放。

### 5.2 数据流和职责

    真实文件/课程/会话/设置
        → 原 WorkspaceStore 及原编辑会话/Agent runtime/持久化
        → UIKit/SwiftUI 产品呈现
            ├─ UIKit PDFView 或 WKWebView 阅读器
            ├─ 原 ConversationController + UICollectionView
            │   └─ MarkdownView/Litext UIKit + 必要真实附件
            └─ UIKit WKWebView + 原编辑器资源及 NoteEditorBridge

读取和会话选区回到原 updateSelection / 选区动作；来源调用原 openAgentReplySource / openExcerptSource；发送调用原 askAgent；取消、重试、动作确认均调用原 store。会话展示订阅当前会话与正在变化的消息，不把输入框或课程界面的每次变化转换成整表刷新。

原 store 的 StudySessionMessagePersistence 按会话加载真实消息；显示层分批准备当前可见段与可回看的历史。切换会话后旧异步结果必须因会话/消息身份不匹配被拒绝。流式数据的最终权威仍是原 AgentMessage；文本展示优化不能遗漏 contentBlocks、工具/错误状态、来源或 action 状态。

### 5.3 首个必须完成的闭环

从候选正常启动 → 创建/打开独立课程 → 通过正常入口导入 PDF、HTML、Markdown 或文本 → 阅读并选择具体位置 → 将选区带入提问 → 用户在候选设置中配置的模型实际流式回答 → 来源返回原位置 → 编辑或确认建议写入笔记 → 正常关闭/重开 → 文件、笔记正文、会话、草稿及阅读上下文正确恢复。

先用一个自建 Markdown 材料跑完整链，再在同一链验证 PDF、HTML、文本。一个格式贯通只是中间里程碑，不能宣布所有阅读器完成。模型未配置时可继续验证文件、编辑、恢复和受控 Agent 协议检查；真实模型一项保持待验，不能把自建响应端点算作真实服务已接通。

### 5.4 关闭与多场景不能成为丢数据口

原 macOS 的 applicationShouldTerminate 能等待编辑器快照和落盘；Catalyst 不能假定同样的 AppKit 回调存在。UIKit 场景失活、进入后台、用户关闭和重新打开时必须调用原新鲜快照、停止任务及持久化接口，并验证最后几次输入没有丢失。优先持续维护可恢复快照，不依赖最后一次 willTerminate 抢救。

沿用主线「共享工作区状态」语义，不扩展成多套独立工作区产品。多个窗口同开时，必须明确原编辑会话的持有者，窗口重建不能让另一个编辑器抢走会话或用旧快照覆盖正文；确认/取消只能唤醒自己的请求一次。该问题验证前不宣称多窗口编辑已通过，也不能让损失内容的关闭路径成为默认体验。

## 6. 视觉质量：与魏碑一致是硬门槛

### 6.1 基线来源及其有效范围

视觉基线首先来自 main@02555d85 的实际 Theme、ContentView、ReaderView、NotesAgentView、ComposerView、SettingsView 和真实资源。已查看仓库保存的[三栏真实截图](../../website/assets/第二幕-真实三窗截图-去黑边.webp)及[纸面会话截图](../../website/assets/第三幕-真实截图-纸面-沉浸对话.webp)：统一薄顶栏、低干扰细分隔、克制的朱色选中态、纸面正文、自然字号层级、底部输入区和阅读/会话/笔记并排是已有产品语言。

这些图片是已入库的历史设计参照，不能代表 02555d85 的当前实机结果，也不能从工具缩放后的预览判断像素清晰度。实施时另从记录清楚的已合并主线生成隔离参考候选，在同样自建内容、字号、正文宽度和本机屏幕缩放下取真正对照；不打开用户正式资料做截图，不引用其他未合并实验画面作为基线。

### 6.2 保持一致的具体要求

| 视觉面 | 使用的现有依据 | 候选验收要求 |
| --- | --- | --- |
| 主题和材质 | Theme 的八主题、paper/ink/cinnabar 等语义色、前景玻璃可读层 | 阅读/会话/笔记/课程/设置同一主题同步，原生与网页颜色匹配；系统材质允许平台光学差异，但不能发灰、糊字或文字对比不足 |
| 字体和层级 | WeiBeiTypography、WeiBeiStele / WeiBeiSteleMono 及 OFL；中文系统衬线/正文与现有字号档 | 沿用品牌层级与等宽代码，不整窗 scale transform；选择正确字体与屏幕 scale，不因 Catalyst 默认控件而突然出现手机式字号/留白 |
| 顶栏、图标与分栏 | 现有线性系统图标和控件约定；26 点图标按钮、30 点输入控件、36 点顶栏是源码参考 | 按 Mac idiom 的实际点坐标实现自然密度；触控目标、焦点和可访问名称有效；不凭截图机械缩放所有尺寸 |
| 消息与输入 | 现有消息阅读密度、留白、来源/动作和输入位置 | 正常对话没有实验按钮墙、性能标签和无作用控制；发送/停止、选区、错误和焦点状态清楚；输入法候选不会被布局变化打断 |
| 富内容 | 原正文语义和 MarkdownView/Litext/UIKit 实际输出 | 公式为真实数学排版，代码保留缩进高亮，表格仍可选可横读，图片按像素与布局尺寸加载；不截图替代表格、不缩小整块掩盖裁切 |
| 动态与交互 | WeiBeiMotion、原动态效果偏好、窗格常驻 | 流式旧段不重复动画，改宽保住文字位置，选择不闪烁，折叠/展开及卡片草稿不因复用丢失 |

不得默认改为 iPad 缩放布局，不用整体位图、正文截图、图标模糊放大或额外滤镜凑出类似颜色。真实 PDF 页面图像和普通图片是内容本身，不等于可以把会话、公式、表格或控件预先截图。

### 6.3 检查方法和失败标准

先在本机实际屏幕缩放、正常使用主题中检验完整三栏、沉浸会话、长回答、流式和改宽；再定向检查亮/暗纸面与玻璃的原生/网页交界处，并切换全部现有主题确认同步与可读。字号使用同一个现有档位；基线和候选正文宽度按点记录一致。观察字体基线、行距、图标描边、低对比文字、截断、叠色和输入焦点，不构造主题×字号×窗口尺寸的庞大组合矩阵。

使用画中画保存完整窗口和能说明问题的局部原始截图，记录实际 backing scale 和点尺寸；提供未二次缩放的原图用于清晰度判断。截图可以辅助评审，不能替代拖选、输入法、焦点、右键、横向滚动的真实操作。若工具只能给缩放预览或无法产生坐标输入，清晰度/手感对应项标为未验收。

出现模糊、主要内容裁切、平台风格违和、主题断层、窗口拼接感或选字/输入受阻，视觉/桌面门槛判为未通过。先修本分支真实原因，不靠减少功能、缩字号、隐藏内容、旧版路径兜底或口头解释宣布合格。

## 7. 会话内核继续遵守的约束

保留现有已投入的消息、准备结果和 cell 生命周期分离。消息 UUID、内容代次、会话身份、实际宽度与字体决定有效结果；滚动不重新解析未变历史，不把全部 UIView 永久保存。有效解析、代码分词、排版、尺寸和附件准备可以复用；首次准备、改宽失效和内存必须分别测量。

按改变的消息或块更新，不每批字 reloadData，不给旧段重新设置内容或播放动画。停止和完成保留正文，最终内容完整。异步结果绑定身份并在新 cell 安装正确显示基线；选择、草稿、折叠、GenUI 状态和必要附件横向位置由消息状态保留。

UICollectionView 所属会话控制器是外层滚动唯一决策者。正文或图片只报告尺寸变化；阅读历史时不被流式拉走，前插与图片增高保持阅读锚点，改宽尽量保持同处文字。用户主动滚动之后不能恢复旧意图；不采用多轮固定延时滚到底。

保留长历史所有内容可访问、长单条完整正文、真实公式/表格/图片/代码。专用交互网页只承载它的真实能力，不兜底普通会话正文。优化实际热点，不自研通用排版引擎，不以同一模板带来的命中率冒充一般性能。

## 8. 实施顺序与每阶段结束条件

方案落地后按下面顺序继续实施，不逐阶段询问是否继续。阶段是可验证的增量，不是缩减最终交付范围。

| 阶段 | 改动与依赖 | 本阶段应交付的行为 | 结束条件 |
| --- | --- | --- | --- |
| 0. 整理接点与原业务完整构建 | 先复核并收窄第 4.4 节现有改动；完善 Catalyst 目标的真实依赖、资源和 API 接点；同步准备隔离的已合并主线视觉参考 | 能启动原 WorkspaceStore 的独立空白魏碑窗口，课程/设置/阅读/会话/笔记实际有归属；固定重放成为验证入口 | 完整 app 构建/链接通过，资源与 helper 装配正确；隔离路径运行检查通过；主线被触及的代码仍可构建；此阶段不称产品已完成 |
| 1. 先贯通一条真实业务链 | 正常导入一个自建 Markdown 材料；原阅读与选区、模型设置、askAgent、UIKit 展示、原编辑器、确认与持久化 | 资料打开 → 选区提问 → 真实流式/停止 → 来源 → 笔记编辑/确认 → 正常重开恢复 | 同一候选经正常入口完成；模型由候选设置配置；没有固定答复替代、没有第二套业务 store，最后输入与正文回读一致 |
| 2. 补齐阅读、课程与内容能力 | 沿用阶段 1；完成 PDF/HTML/文本及 OCR/搜索/标记、课程管理与资料关系、摘录本、完整消息块/GenUI | 用户在不同资料类型及课程间完整使用；消息动作、真实来源、卡片状态和附件正常 | 第 3 节对应项目实际验证；PDF 助手边界、跨课程隔离、外部文件变化、重启恢复通过；未实现项目仍列为缺口 |
| 3. 完整工作区与视觉对齐 | 关联/记忆/画像、完整设置和快捷键、窗格与窄窗/沉浸/重排、场景保存；对照已合并主线视觉 | 阅读、会话、笔记、课程和设置具有统一魏碑外观，桌面操作自然，现有功能有完整入口 | 第 3 节功能表无未交付业务；第 6 节视觉与真实桌面入口检查通过，丢稿/串会话/关闭风险清零 |
| 4. 完整候选验证、性能和交付 | 从已提交干净本分支生成 Release，保留独立构建/资源/签名证据；只补有意义的回归 | 可拷出开发目录运行的完整 App 和 zip，准确来源、功能表、实际证据与采用建议 | 当前提交的本地/必要 CI 通过；每类证据分别报告；真实交互未验收时不得称任务完成，不合并或发布 |

阶段 1 的真实模型环境依赖不阻止阶段 2/3 中独立的文件、编辑、界面工作。画中画坐标通道故障也不阻止代码/资源/数据安全验证；但两者都不能被计作已通过。

## 9. 少量必要验证与证据标准

复用已有检查，优先选择会保护实际行为的检查；不新增通用测试平台，不按每个函数凑测试。当前新增平台分支至少保留一个能够失败的行为检查，不测试普通源码字词或类名。

| 证据层 | 最小必要验证 | 不能据此宣称的结果 |
| --- | --- | --- |
| 构建/链接 | 本实验 Release Xcode/Catalyst 目标；检查 app Mach-O 平台、架构、UIKit 和正确 framework；共享代码另过受影响主线构建 | 不能替代资源可见或操作通过 |
| 资源/签名 | 在独立解压副本严格验证签名；从 app/framework 加载编辑器、字体、公式、Agent 资源/技能和 PDF helper；脱离源码目录运行 | 临时签名不等于公证、正式发布或所有 Mac 兼容性 |
| 核心业务链 | 一个新临时课程，四种文件走同一导入/阅读/提问/来源/笔记/重开流程；已有 DailyWorkflow 等按影响选用 | 自建协议响应只保护接线，不能声称用户真实服务可用 |
| 笔记/文件保护 | 复用 WriteGateSafety、PoetryIncidentRegression、NoteEditingSession、NoteRecoveryStore；在候选检查外部改文、保存失败保留草稿和恢复；原文件移除/覆盖用隔离样本 | 编译或编辑器显示正常不能替代磁盘内容与备份证明 |
| 课程/会话隔离 | 复用 WorkspaceDirectoryIsolation、SessionMessageExternalization、ComposerDraftIsolation 和相关课程安全检查；两个临时课程只验证一次必要切换/重开/错误消息归属 | 当前会话看起来正常不等于旧异步结果不会串到新会话 |
| PDF 助手 | 真实小 PDF 成功取文；受控超时/取消/输出界限检查；所有 helper 与签名路径来自本实验 | API typecheck 不代表 helper 能在候选中启动 |
| 会话性能/正确性 | 保留已有重放检查：长历史首次/热回看、单条长答、定向流式、前插、改宽、图片到达、卡片状态；增加真实 store 接入后的必要身份/最终内容检查 | 旧 930c6035 的 10 项通过不自动转移到新完整候选 |
| 实际桌面/视觉 | 第 6 节对照；鼠标拖选和跨段/跨附件复制、右键、快捷键、中文组词、焦点、附件横滚和分栏拖动；关闭重开真实操作 | 辅助功能 Scroll/Click、截图或程序设置偏移不冒充鼠标/触控板/输入法 |

性能使用同机、同内容、同字号与正文宽度的 Release；单独记录启动到可操作、首次历史准备、热回看、单条长回答、流式和改宽。记录主线程热点、常驻与峰值内存、WebKit 辅助进程是否纳入、可见视图/缓存数量以及真正失效成本。并行任务导致环境非独占时写明，不抢停别人进程。

只有真实呈现帧采样能报告 FPS；现有显示回调间隔、组件毫秒和平均 CPU 都不能换算成 FPS。首次成本不能藏在预热中，未改变历史的解析与测量次数必须可核对。其他候选尚未交付时独立完成本方案；可用时再做完整端到端比较，不复制未合并代码，也不把宿主、正文、资源或实现的共同差异全部归因于 UIKit。

画中画错误按工具故障记录，应用错误按应用错误记录。使用本任务完整应用路径及最新辅助功能树；不重启共享服务、不关闭正式魏碑、不停止其他实验。缺少真实交互证据时保留「未验收」，由实际可用的画中画操作或用户在最终候选的正常体验补齐，不伪造完成。

## 10. 交付包、当前判断和未决事项

最终交付目录包含独立 .app 与保留权限的 zip、提交 SHA/主线基线/实际锁文件/构建设置和产物哈希、许可、构建及签名日志、功能对齐表、最少必要检查结果、真实视觉证据、性能原始数据和采用建议。用户体验清单只保留「操作 / 应看到什么 / 是否通过 / 问题备注」四栏，工程采样与来源记录由实施者完成。

完成标准是第 3 节既有产品业务实际接入、原文件/安全存储/真实模型/恢复链成立、视觉和桌面品质通过；不是 target 建好、链接了 WeiBeiCore 或有一份计划。中途交付必须明确还缺哪些功能。正式更新发布通道等第 1 节边界单列，不混成业务功能被静默削减。

目前判断：**完整候选未完成；不能建议采用或宣称 UIKit 胜出。** 930c6035 仍是可运行的会话资格样本。已有原始证据和图形空白漏检的修复记录保留在[实验说明](../../Experiments/CatalystChatLab/README.md)及[桌面记录](../../Experiments/CatalystChatLab/Evidence/desktop-checks.md)，不重新包装为完整产品证明。

没有需要用户再次决定的技术路线。需要用户环境参与的事实只有：真实服务须由用户在候选设置中配置，以及最后的桌面/视觉体验需真实操作；界面就绪前不索取密钥或逐阶段提问。若后续证据表明某个公开 API 无法保留既有产品行为，集中报告具体入口、实际 API 证据和对用户的影响，再由用户决定范围；不能自行藏掉入口或使用虚假替代。

## 来源与继续实施入口

- 产品基线：[main@02555d85](https://github.com/WroughtMind/weibei/tree/02555d8506504e9fd68374855d3cff87428c9eb6)、[产品介绍](../../README.md)、[应用生命周期和菜单](../../Sources/WeiBei/App/WeiBeiApp.swift)、[主窗口](../../Sources/WeiBei/Views/ContentView.swift)、[常驻窗格](../../Sources/WeiBei/Views/StableDocumentWorkspace.swift)。
- 原业务：[WorkspaceStore](../../Sources/WeiBei/Stores/WorkspaceStore.swift)、[资料库根与导入](../../Sources/WeiBei/Stores/WorkspaceStore+LibraryRoot.swift)、[真实 Agent](../../Sources/WeiBei/Stores/WorkspaceStore+NativeAgent.swift)、[会话恢复](../../Sources/WeiBei/Stores/WorkspaceStore+SessionMessages.swift)、[继续上次工作](../../Sources/WeiBei/Stores/WorkspaceStore+WorkResume.swift)。
- 编辑与保护：[原写闸门](../../Sources/WeiBei/Stores/WorkspaceStore+NotesPersistence.swift)、[编辑会话接入](../../Sources/WeiBei/Editing/WorkspaceStore+NoteEditing.swift)、[编辑器协议](../../Sources/WeiBei/Editing/NoteEditorBridge.swift)、[文件监视](../../Sources/WeiBei/Stores/CourseFileWatchSession.swift)、[备份环](../../Sources/WeiBeiCore/NoteBackupRing.swift)。
- 界面依据：[主题/字体/尺寸](../../Sources/WeiBei/Support/Theme.swift)、[设置](../../Sources/WeiBei/Views/Settings/SettingsView.swift)、[模型配置](../../Sources/WeiBei/Views/Settings/AgentSettingsView.swift)、[课程空间](../../Sources/WeiBei/Views/CourseWorkspaceView.swift)、[阅读器](../../Sources/WeiBei/Views/ReaderView.swift)。
- 上游保持现有已核对许可证与锁定提交：[MarkdownView](https://github.com/Lakr233/MarkdownView/tree/757b6fcc4b3095e84f4c0613f4b98147f49dcd09)、[Litext](https://github.com/Lakr233/Litext/tree/130b4eef642d76a3d2dcf07ab966f32f08e14b90)、[直接及传递锁文件](../../Experiments/CatalystChatLab/CatalystChatLab.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)、[随包许可](../../Experiments/CatalystChatLab/Resources/ThirdPartyNotices.txt)。现有锁包含 Highlightr 2.3.0、Litext 2.2.1、LRUCache 1.3.0、swift-cmark 0.8.0、swift-collections 1.6.0、SwiftMath 1.7.3；Mermaid 11.12.0 及传递通知留在实验资源中。
- [lody-ios](https://github.com/Innei/lody-ios) 与 [FlowDown](https://github.com/Lakr233/FlowDown) 仅作公开产品/API 研究；已有实验未复制其 AGPL 实现。需要新增来源时先检查具体 revision 与许可，不凭 README 或视频推定性能。
- 平台依据：[Mac Catalyst](https://developer.apple.com/documentation/uikit/mac-catalyst)、[Mac idiom](https://developer.apple.com/documentation/uikit/choosing-a-user-interface-idiom-for-your-mac-app)、[列表布局与性能](https://developer.apple.com/videos/play/wwdc2021/10252/)。文档用于确认行为，性能结论必须来自本实验。

接手时继续原分支和 #452，先看最新 PR、本方案、实际工作树与证据；不从旧进度推断目录不存在。计划、实验资格、业务接入、候选和验收分别记录。完成文档不是完成任务，下一步按阶段 0 继续实施。
