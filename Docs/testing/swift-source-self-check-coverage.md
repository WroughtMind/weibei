# Swift 源码自检覆盖迁移

## 目的

提交 `bb172e8` 删除了通过读取 Swift、TypeScript、HTML 和 CSS 源文件并匹配字符串实现的自检。本清单以其父提交 `fff070e` 为审计基线，将仍然有效的产品风险迁移到可执行行为测试、构建产物检查或明确的人工设计验收。

迁移不追求原断言数量一比一。私有符号名称、源码排列、特定 API 字面量和 SwiftUI 修饰器组合不属于产品契约，不以其他形式恢复。

## 状态定义

- **XCTest**：由 `swift test` 执行的确定性行为测试。
- **Vitest**：由 `npm run test` 执行的 TypeScript 行为测试。
- **现有门禁**：已经由 `make check` 执行的运行时 SelfCheck、WebKit 检查或生成物检查。
- **显式验收**：不进入无窗口门禁，必须通过指定的 `WeiBeiDevTool verify --scenario` 场景执行。
- **人工设计验收**：只能由真实界面判断的审美结果，不宣称自动覆盖。
- **废弃**：只约束实现形状、历史命名或源码文本，删除后不再保留。

## 迁移矩阵

| 原自检领域 | 仍有效的风险组 | 去向 | 状态 |
| --- | --- | --- | --- |
| `AgentBehaviorSelfChecks` | 应用凭据目录与终端 `~/.pi` 隔离；迁移不覆盖已有目标且拒绝异常输入 | `WeiBeiAgentDataPathsTests`；现有凭据存取 SelfCheck | XCTest + 现有门禁 |
| `DocumentPipelineSelfChecks` | 文本提取边界与缓存失效；FTS 持久化、刷新、取消和失败原子性；PDF worker 输出与生命周期边界 | `CourseDocumentSearchIndexTests`、`BoundedPDFTextExtractorTests`；现有 PDF/OCR/索引 SelfCheck | XCTest + 现有门禁 |
| `EditorSelfChecks` | Markdown、callout、数学节点、source reference、列表退出和生成资源契约 | `WeiBeiWebEditorCheck`、WebEditor Vitest、`verify:generated` | Vitest + 现有门禁 |
| `NotesAgentUISelfChecks` | 选区合并与清理、活动笔记写保护、笔记生命周期、Agent 请求快照与取消、引用跳转和快捷键拒绝语义 | `SelectionBehaviorTests`；`WorkspaceStoreNoteLifecycleTests`、`WorkspaceStoreSelectionTests`、`WorkspaceStoreAgentAndModelTests`、`WorkspaceStoreNavigationAndPaneTests`、`WorkspaceStoreCourseAndReferenceTests` | XCTest + 现有门禁 |
| `PiAgentSelfChecks` | 工具注册完整性、context-first、stale revision、路径逃逸、无证据内容拒绝、note/memory revision 和 runtime 终止语义 | `extension.test.ts`、`PiRuntimeBehaviorTests`；现有 Pi/Rich Answer 协议 SelfCheck | XCTest + Vitest + 现有门禁 |
| `ProductResourceSelfChecks` | PI 学习与课程记忆场景接线；Rich Answer fixture 可由 CLI 选择 | `AppPolicyTests`、`VerificationScenarioContractTests` | XCTest |
| `RichAnswerEmbeddingSelfChecks` | narrative/program 校验、host message、renderer/component 能力集合、Swift presentation/readiness | `contracts.test.ts`、`RichAnswerContractTests`；生成物门禁 | XCTest + Vitest + 现有门禁 |
| `SettingsSelfChecks` | provider/model 策略、刷新竞态与 fallback、设置状态持久化、主题家族切换和快捷键动作 | `WorkspaceStoreAgentAndModelTests`、`WorkspaceStorePersistenceTests`、`AppPolicyTests` | XCTest |
| `WorkspaceLayoutSelfChecks` | Content Rail 阈值、pane toggle/navigation/focus、顶栏动作策略、空工作区入口和主题语义 | `ContentRailPolicyTests`、`WorkspaceStoreNavigationAndPaneTests`、`AppPolicyTests` | XCTest |
| `WorkspaceModelSelfChecks` | 旧 snapshot 默认值、显式 `false` 和 legacy `.preview` 归一化 | `WorkspaceModelPersistenceTests`、`WorkspaceStorePersistenceTests` | XCTest |
| `WorkspaceStoreSelfChecks` | 笔记防覆盖与 flush、材料/笔记解耦、课程 membership/session、历史位置、选区线程隔离、autosave 错误与重试 | `WorkspaceStorePersistenceTests`、`WorkspaceStoreNoteLifecycleTests`、`WorkspaceStoreNavigationAndPaneTests`、`WorkspaceStoreSelectionTests`、`WorkspaceStoreCourseAndReferenceTests` | XCTest |
| `SelfCheckSupport` / `SelfCheckRunner` | 自检运行集合和退出码 | `WeiBeiDevCore` check workflow 与 CLI 集成测试 | XCTest + 现有门禁 |

## 显式真实窗口验收

裸命令只运行最初脚本的默认离线学习场景：

```bash
make verify
```

下列体验风险必须显式选择场景，不由默认命令代替：

- pane host 身份、frame 连续性和真实 WebView 键盘传递：

  ```bash
  swift run WeiBeiDevTool verify --scenario pane-toggle-continuity-flow
  ```

- Rich Answer fixture、WebKit bridge 与视觉组合：

  ```bash
  swift run WeiBeiDevTool verify --scenario rich-answer-openui-extended-inline
  ```

## 人工设计验收

以下内容保持为设计审查，不使用源码、snapshot 或像素常量伪装成行为测试：

- 字体、具体色值、透明度、阴影、圆角、间距和 hairline 观感；
- Settings、空工作区、关系纸和浮层的信息层级；
- hover、press、wash、glass 和 paper 的动画与材质；
- 原生滚动条和多栏布局在真实内容下的视觉连续性。

## 明确废弃的断言类型

- 私有函数、变量、类型或文件名必须存在；
- 某个调用必须出现固定次数或按特定源码顺序排列；
- SQL、系统 API、错误文案或常量必须以固定字面量出现；
- SwiftUI 必须使用或禁止某个具体 View、Modifier、PreferenceKey；
- 已删除历史类型或注释文本不得再次出现；
- TypeScript 模块必须保留迁移前的 `.js` 文件结构。

## 门禁

迁移后的自动化覆盖统一由以下入口执行：

```bash
make check
```

新增测试不得访问用户真实数据、网络或真实账号，不打开窗口，不自动重试，也不得读取项目源码进行文本匹配。
