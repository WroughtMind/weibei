# 顶栏三板块开关图标 · 实现计划

> 给 Codex 执行用。本文自包含,带全部上下文和 file:line 引用,不用重新摸索。

## 一句话规则(整个设计的地基)

> **可见板块集合决定布局,拖拽只决定顺序,资料库不是三板块之一。**

---

## 目标

顶栏正中间放 3 个图标(文稿 / Agent / 笔记)。点亮哪个显示哪个,全点亮=三栏,点掉一个=两栏,只剩一个=独占,全关掉=空白页。

| 顶栏图标 | 控制 | 说明 |
|---|---|---|
| `doc.text` 文稿 | `showReader`:中间阅读区 | 阅读器现在是隐式 always-on,要给它加"能关"的能力(沉浸对话里它本来就不显示,这个能力已存在,只是没抽成标志) |
| `bubble.left.and.text.bubble.right` Agent | `showAgent`:对话区 | 新增独立标志,和笔记解耦 |
| `note.text` 笔记 | `showNotes`:笔记区 | 从 `showRightPane` 拆出来 |

**资料库** `showLibrary` 不在这三图标里,继续用现有侧栏的 `sidebar.left` 按钮控制(`ContentView.swift:587-593`)。

---

## 现状关键事实(实现前必读)

### 可见性标志(现在只有 2 个,且笔记/Agent 绑死)
- `@Published var showLibrary = true` — `Sources/WeiBei/Stores/WorkspaceStore.swift:41`,管左侧资料库目录(SidebarView)。
- `@Published var showRightPane = true` — `WorkspaceStore.swift:42`,管右栏(笔记+Agent 一锅端),**没有 Agent 独立开关**。
- `showRightPane` 被引用 **44 处**(全仓 grep),大多是"读"它判断可见性。

### 三栏渲染分支(要改的核心)
`Sources/WeiBei/Views/ContentView.swift:778-803`:
```swift
case .documentAgentNotes, .documentNotesAgent:
    if store.showRightPane {
        let order = store.normalizedThreePaneOrder
        documentThreePaneView(order: order)
    } else {
        ReaderPaneView()   // ← showRightPane=false 时只渲染 reader
            .transition(WeiBeiTransition.layout)
    }
```
阅读器在三栏布局里是**隐式 always-on**——`showRightPane=false` 时它作为唯一 fallback 渲染。它没有独立开关。

### 三栏里三个 pane 已是独立 slot
`documentThreePaneView`(`ContentView.swift:935-961`)用 `ResizableThreePane` 三个独立 slot,每个由 `paneView(for:)`(`ContentView.swift:984-993`)映射:`.reader`→`ReaderPaneView`、`.agent`→`AgentPaneView`、`.notes`→`NotePaneView`。`NotesAgentView`(`NotesAgentView.swift:5-18`)是死代码,无人实例化。

### 拖拽换位已实现
- `@Published var threePaneOrder: [WorkspacePaneRole]` — `WorkspaceStore.swift:53`,默认 `[.reader, .agent, .notes]`。
- `normalizedThreePaneOrder` — `WorkspaceStore.swift:717-719`,保证是 3 个 role 的排列。
- 拖拽手势:`PaneHeaderReorderModifier` — `NotesAgentView.swift:117-213`。
- 顺序→layout:`layoutMatchingThreePaneOrder` — `WorkspaceStore.swift:2132-2138`(只有两种命名 layout,实际渲染读 `normalizedThreePaneOrder`)。
- 持久化:`PersistedWorkspace.threePaneOrder`。

### 顶栏结构(`UnifiedTopBarView`,`ContentView.swift:238-761`)
单层 `HStack`(`ContentView.swift:246`),结构:
```
[leftInset spacer] [leftPrimaryControls] [brandBlock] [弹性中间(maxWidth:.infinity)] [trailing controls]
```
- **弹性中间**(`ContentView.swift:254-266`):有文档时显示文档标题 `Text`(`store.displayTitle`),否则空 `Spacer`。
- **文档标题是阅读器内标题的弱化重复**:`ReaderView.swift:111` 已显示"标题,第 N 页"(更完整),顶栏那个不带页码。拿掉不丢信息。
- **右侧 agentButton**(`ContentView.swift:303-305`,`activateAgentEntry` 在 `:690-698`):和新图标功能重叠。
- **布局菜单**(`ContentView.swift:700-732`):列出 6 个 WorkspaceLayout,trailing 侧。

### 按钮样式现成
`WeiBeiIconButtonStyle(active:)` — `Sources/WeiBei/Support/Theme.swift:467-574`,朱砂高亮已实现。`WeiBeiMetric.iconButton = 26`(`Theme.swift:264`)。`topIconButton` helper 在 `ContentView.swift:752-760`。

### 持久化结构
`PersistedWorkspace` — `Sources/WeiBeiCore/WorkspaceModels.swift:701-731`。已有 `showLibrary: Bool?`、`showRightPane: Bool?`。新增字段照此模式加可选字段。

### SelfCheck 验证行为
`WeiBeiSelfCheck` 通过公开模型、状态变化和真实产物验证行为，不再读取源码并匹配实现字符串。新增或重命名内部符号无需维护源码文本断言。

---

## 要做的 3 件事

### 事 1 · 三个对称开关(底层)

让 `showReader` / `showAgent` / `showNotes` 成为三个平等的可见性标志。

**WorkspaceStore.swift**:
- 新增 `@Published var showReader = true`、`@Published var showAgent = true`(紧邻 `showLibrary`/`showRightPane`)。
- 把 `showNotes` 作为独立标志。**推荐**:新增 `@Published var showNotes = true`;把现有 `showRightPane` 改为计算属性 `var showRightPane: Bool { showNotes || showAgent }`(让 44 处引用大多不用改)。注意:`showRightPane` 现在是 `@Published` 存储属性,改成计算属性后,任何对它直接赋值的地方(`showRightPane = ...`)都要改——grep `showRightPane =` 找到这些点,改成赋值给 `showNotes`/`showAgent`。
- 新增 `toggleReader()` / `toggleAgent()`,结构对齐现有 `toggleLibrary()`(`WorkspaceStore.swift:587-597`):recordNavigationPoint + clearUnpinnedFloatingSelection + focus + save。
- `toggleRightPane()`(`WorkspaceStore.swift:605-612`)改为同时 toggle `showNotes`+`showAgent`(或调两个 toggle)。
- `revealRightPane(focusing:)`(`WorkspaceStore.swift:614-623`):确保至少目标 pane 开着。

**WorkspaceModels.swift**(`PersistedWorkspace`,`:701-731`):
- 加 `showReader: Bool?`、`showAgent: Bool?`、`showNotes: Bool?`(可选,旧 workspace.json 不崩)。同步 init。

**WorkspaceStore.swift 持久化**:
- `load()`(约 `:2300` 附近):读三个新字段,缺省 `true`。
- `save()`(约 `:2360` 附近):写三个新字段。
- `NavigationSnapshot`(`:93-106` 附近):加 `showReader`/`showAgent`/`showNotes`;`navigationSnapshot()` 和 `applyNavigationSnapshot()`(`:934-975` 附近)同步。

**没有"不能关到最后一个"的守卫。** 3 个都能关。全关走"事 3"空白页。

### 事 2 · 顶栏中间放 3 个图标

**ContentView.swift**:

1. **拿掉文档标题块**(`:254-266`):删掉 `shouldShowTopDocumentTitle` 分支和它显示的 `Text`。中间改成弹性 Spacer。
2. **新增 `paneToggleCluster`**:3 个 `topIconButton`,顺序固定 文稿 / Agent / 笔记:
   ```swift
   private var paneToggleCluster: some View {
       HStack(spacing: topBarSpacing) {
           topIconButton("doc.text",
               help: store.showReader ? store.ui("隐藏文稿", "Hide document") : store.ui("显示文稿", "Show document"),
               active: store.showReader) {
               withAnimation(WeiBeiMotion.layout) { store.toggleReader() }
           }
           topIconButton("bubble.left.and.text.bubble.right",
               help: store.showAgent ? store.ui("隐藏对话", "Hide agent") : store.ui("显示对话", "Show agent"),
               active: store.showAgent) {
               withAnimation(WeiBeiMotion.layout) { store.toggleAgent() }
           }
           topIconButton("note.text",
               help: store.showNotes ? store.ui("隐藏笔记", "Hide notes") : store.ui("显示笔记", "Show notes"),
               active: store.showNotes) {
               withAnimation(WeiBeiMotion.layout) { store.toggleNotes() }
           }
       }
   }
   ```
3. **中间布局**:用顶栏视觉中心层放 `paneToggleCluster`,保证它相对窗口居中,不要只在剩余空间里居中。
4. **移除右侧旧 `agentButton`**(`:303-305` 及 `activateAgentEntry` `:690-698`):功能和新图标重叠。旧按钮的选区语义要迁到 Agent 图标:有选区时点击 Agent = 显示/聚焦 Agent 并带上当前选区上下文,不要只做普通开关。
5. **布局菜单保留但降级**(`:700-732`):结构不动,不再是主交互方式。两者矛盾时以图标开关的可见集合为准。

### 事 3 · 全关时显示空白页

3 个都关掉时,中间区域渲染空状态页。新增一个 `EmptyWorkspaceView`:
- 背景 `WeiBeiTheme.paper`。
- 中间一行小字:`store.ui("在顶栏点亮一个板块开始", "Light up a pane above to begin")`,`WeiBeiTheme.secondaryInk`,正文档字号(参考 `Theme.swift` 现有字号,用 `secondaryInk` + 13~14pt)。
- 可选一枚极淡朱砂闲章暗纹(`WeiBeiTheme.cinnabar.opacity(0.05)` 之类),做了加分,不做也行。
- **不强引导**,不要"新建文档"大按钮,保持安静调性。

**渲染入口**:`LayoutContentView.body`(`ContentView.swift:778`)三栏 case 里,当 `showReader == false && showAgent == false && showNotes == false` 时渲染 `EmptyWorkspaceView()`。其它组合(只开一个/两个)渲染对应数量的 pane(复用 `ResizableTwoPane` — `ContentView.swift:1265`)。

---

## 实现备注(注意的坑)

- **`showRightPane` 从存储属性改计算属性**:任何 `showRightPane = xxx` 的赋值点会编译错。grep 全部改成赋值给 `showNotes`/`showAgent`。
- **三栏渲染分支**(`ContentView.swift:778-803`):`showRightPane=false` 现在走"只渲染 reader"。改成按 `showReader`/`showAgent`/`showNotes` 组合决定渲染 0~3 个 pane。全关→空白页;只开 reader→`ReaderPaneView()`;reader+一个→`ResizableTwoPane`;三个全开→`documentThreePaneView`(现状)。
- **拖拽换位**:`threePaneOrder` 保持存全部 3 个 role 顺序,隐藏的 pane 只是不渲染、不参与拖拽,顺序不变。`PaneHeaderReorderModifier` 只挂在可见 pane 上。
- **沉浸态**(immersiveReading/Writing/Conversation,`ContentView.swift:804-878`):不走三栏逻辑。图标 active 状态来自当前 layout 的真实可见 pane;点击任一图标先退出沉浸,再按普通三板块集合开/关。
- **SelfCheck**:布局变更应通过公开状态、持久化结果和真实交互场景验证，不检查内部符号名称。
- **验证场景** `runVerificationScenarioIfNeeded`(`WorkspaceStore.swift` 约 `:1813`):它会 setLayout + toggle,确认不被新标志破坏。
- **快捷键**:⌘B(`toggleLibrary`)、⌘J(`toggleRightPane`)保留,不新增。

---

## 不做(本次范围外)

- 不动 6 个 layout 枚举(菜单降级但保留)。
- 不做圆环菜单。
- 不动 Agent 角色/静默形态。
- 不重写布局引擎(只在现有 switch 里加分支)。
- 不新增快捷键。

## 验证

- `swift build` 通过
- `swift run WeiBeiSelfCheck` 通过
- `make verify` 通过(含 offline-learning-flow 场景)
- 手动测:3 图标开关、2/3 pane 拖拽、全关空白页、沉浸态行为
