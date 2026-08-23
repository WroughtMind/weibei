# 魏碑纯 WYSIWYG 写作内核重构 · 执行计划

> 日期：2026-08-19（定稿：GPT 原案 → 仓库取证校准 → 修订 → 合并，全部事实断言经三轮验证）
> 状态：最终版，可执行
> 取证基准：`main @ deebd50`（即当前 `origin/main`）；行号仅用于定位，实施时必须从最新 `origin/main` 重新搜索符号并复核。注：本文行号实际取证于 `d217373`，其后 3 个提交（#262–#264 自动更新链路）未触碰 WebEditor/编辑器/笔记持久化文件，引用仍然有效；但这批提交动过 `Package.swift`、`WeiBeiApp.swift`、`ContentView.swift`、`script/`，开工前须确认这些共享面的最新占用状态
> 计划入库：按仓库规则，纯计划不单独建分支，随第一个实现 PR 一并合入 `main`
> 核心取舍：保留纯 WYSIWYG；保留 Markdown 落盘；不做源码模式；不做用户可见错误中心；恢复 v1 使用 Markdown checkpoint，不做 ProseMirror Step 日志

---

## 0. 如何使用这份计划

这份计划分三层，执行 Agent 不得混淆：

### A. 不可违反的产品与数据原则

这些是目标本身，不能为了省事改变：

- 纯 WYSIWYG；
- 用户不需要理解 Markdown、KaTeX 或解析错误；
- 普通输入不得触发全文 Markdown 序列化与全文 bridge 回传；
- 解析或渲染失败不得静默删除用户内容；
- 正常切换、失焦和退出不得丢失已确认保存的内容；
- 必须复用现有 IME、原子写、备份环、退出 flush 和失败轻提示，而不是重建第二套系统。

### B. 必须达到的结果型验收

验收关心"是否解决问题"，不强迫使用某个类名、文件名或算法。只要满足结构门槛、数据安全门槛和真实 App 闭环，具体实现可以调整。

### C. 推荐实施路径

后文的工作包、类名、文件拆分、checkpoint 时间和 PR 切分是默认方案，不是宗教：

- 可以根据工作包 A 取证合并或拆分 PR；
- 可以调整 checkpoint 最大间隔；
- 可以决定某项语法继续用 Decoration 还是升级为节点；
- 可以选择 ESM dynamic import 或多个本地静态 bundle；
- 可以调整内部类型命名与目录结构。

任何偏离默认方案的实现，只需在 PR 中写明：新证据是什么；为什么更简单或更可靠；如何仍然满足不可违反原则与验收门槛。

**不要为了机械遵守计划而保留明显多余的机器；也不要以"灵活"为名回到全文同步、数据丢失或双重实现。**

---

## 1. 产品目标与边界

### 1.1 用户最终应当感受到

1. 新笔记和长笔记中的中文输入、换行、删除、撤销、粘贴都稳定顺滑。
2. 标题、列表、引用、链接、表格、图片、代码、公式和提示块均可通过可见的 WYSIWYG 操作完成。
3. 用户不需要输入 `#`、`$$`、`|---|` 等控制符。
4. 从 Chat、网页或其他 Markdown 软件复制内容后，尽可能转成可继续编辑的结构。
5. 合法公式显示为公式；暂时不合法时在原地保留源码并继续可编辑，补完整后自动恢复。
6. 无法识别的语法可以失去特殊样式，但文字、目标地址和原始内容不能消失。
7. 正常自动保存不制造状态噪音；只有真实、持续的保存失败使用现有单行 transient 提示。
8. 切换笔记、失焦、退出和 WebContent Process 重建时行为可靠。
9. Agent 插入的内容与用户自己写的内容地位相同，可以继续普通编辑。
10. 窄窗口、深色主题、中文输入法和较长文档均可正常使用。

### 1.2 明确不做

- 源码模式；Markdown / 预览双栏；
- 用户可见的错误列表、公式诊断中心或技术错误详情；
- Word 式常驻重工具栏；第二套编辑器；
- 富文本私有落盘格式；协同编辑、CRDT、版本历史 UI；
- ProseMirror Step 级恢复日志与重放；
- Web 内第二套选区浮层（选区浮条唯一所有者是原生 SwiftUI）；
- 万能增量 Decoration 编译器（见工作包 E 的分步策略）；
- 生产保存路径的通用 AST 等价证明（见第八节两层分工）；
- 运行时 CDN。

Markdown `*.md` 继续是唯一正式落盘格式和互操作格式，但不是产品界面。

---

## 2. 已取证现状（执行前必读；行号基准 `d217373`）

### 2.1 真正的输入热路径（每击键发生）

1. **Web 端全文序列化**：Milkdown `markdownUpdated` 对每个 docChanged transaction 先做完整 Markdown 序列化，再无节流 `post('markdownChanged')` 全文（`WebEditor/src/editor.ts:2583-2596`）。已验证：`@milkdown/plugin-listener` 在 `prevDoc && !prevDoc.eq(doc)` 时无条件 `serializer(doc)`（`node_modules/@milkdown/plugin-listener/lib/index.js:82-84`）——**只要注册了 markdownUpdated listener，序列化就发生；listener 数为 0 则整个跳过**。IME 组合期间已抑制发送，组合结束补发一次（`editor.ts:2146-2160, 2587-2591`）。
2. Swift `RichMarkdownEditorView` 经 `@Binding var markdown: String`（`RichMarkdownEditorView.swift:574`）把全文写进 `NotePaneView` 的 `@State draftNoteText`（`NotesAgentView.swift:452, 709-724, 1140-1157`）。
3. `noteRailItems` 是计算属性，**每次 body 重算（即每击键）对全文逐行扫描 ATX 标题**（`NotesAgentView.swift:726-755`）。
4. **两级防抖**：220ms 视图层 flush 进 `@Published noteText` 全树发布（`NotesAgentView.swift:460, 821-831`；`WorkspaceStore.swift:342, 10804-10847`），再经 420ms 落盘防抖原子写入（`WorkspaceStore.swift:694`；`WorkspaceStore+NotesPersistence.swift:648-658`）。
5. Web 端全局 Decoration 插件 `weiBeiDialectPlugin`：**每次 state update（含纯选区移动）都新建空数组、`state.doc.descendants` 全树遍历、对每个文本节点跑 10+ 个正则**（`editor.ts:2004-2081`，各 decorate 函数 `:1123-1311`）。
6. `upgradeDisplayMath()` 在**每次 update** 全局 `querySelectorAll` 扫 math DOM 并用 KaTeX displayMode 覆盖重渲（`editor.ts:1718-1740`，调用点 `:1913, 1919`）；另有 rAF 全局扫 `.katex-error`（`:1742-1749`）。
7. 图片：`documentImageSources` 全 doc 遍历收集 src，`resolveEditorImages` 再 `querySelectorAll('img')` 按下标一一对应，每次 view update 经 rAF 触发（`editor.ts:1025-1085, 1917`）。
8. Prism 全量高亮：`decorateCodeBlock` 粒度是单块，但挂在全局 decorations 遍历里，**每次 update 对所有代码块重新 tokenize**（`editor.ts:1484-1492, 2054`）。
9. 入口静态 import Mermaid 全库 + KaTeX + 15 个 Prism grammar（`editor.ts:27-44`），单入口 iife 产物 `Resources/Editor/editor.js` 当前 **4,618,710 字节**；纯文本笔记同样承担。

结论：首要问题不是"磁盘写太频繁"，而是**一次普通输入被当成一次完整文档同步与派生重算**。

关于 `updateNSView`（`RichMarkdownEditorView.swift:780-867`）：JS 调用均为 fire-and-forget 异步且有状态守卫，**不是当前已证明的每击键主热点**；但主线程提交 JS、构造参数仍有成本。第五节硬门槛据此措辞：禁止普通输入触发 Host→Web 命令，允许合法配置变化的去重命令。

### 2.2 已有设施，必须复用而非重建

- **公式已是 ProseMirror atom 节点** `math_inline`/`math_block`（`@milkdown/plugin-math`，含 parser/serializer/基础 KaTeX 渲染）；`upgradeDisplayMath` 只是叠加的 displayMode DOM 补丁；公式源码用 `font-size: 0` 隐藏（`index.html:1036-1068`）。工作包 D 是给现有节点接可控 NodeView，不是从零建 schema。
- **IME composition 成体系**：composition 期间抑制回传、`<br>` 清理、`.ProseMirror-safari-ime-span` 样式、`isComposing`/`keyCode===229` 守卫、WebEditorCheck 专项用例（`main.swift:1697, 1746`）。
- **保存链路完备**：原子写（`WorkspaceStore+NotesPersistence.swift:424-426`）、`NoteBackupRing` 备份环、模板覆盖守卫、写后 digest 校验、失败留草稿 + 单行 transient 提示（`:676-740`；`WorkspaceStore.showTransientNoteStatus`，`WorkspaceStore.swift:18576`）。
- **退出流程完备**：`applicationShouldTerminate` 返回 `.terminateLater` + 同步 flush + 失败取消退出；`applicationWillTerminate` 与失焦兜底 flush（`WeiBeiApp.swift:44-99`）。
- **表格键盘导航已启用**：gfm preset 自带 `tableKeymap`（Tab / Shift-Tab / Mod-] / Mod-[）、`tableEditing` 已挂；缺的只有行列增删 UI 与 `columnResizingPlugin`。
- **Mermaid 已有缓存**：WeakMap 节点 identity 为键 + 代际 + 焦点快照（`editor.ts:1337-1375`），并非每次 update 重渲；真实问题是静态 import 和无防抖 `setTimeout(0)`。
- **GFM `[^脚注]` 已是语义节点**；只有行内 `^[...]` 是 Decoration。frontmatter **不是 Decoration**——进 PM 前被 `splitFrontmatter` 剥离、渲染为独立 HTML 面板（`editor.ts:838-877, 2523-2526`），round-trip 正确即可，不需要进 PM Schema。
- **WebContent Process 终止监听已在**（`RichMarkdownEditorView.swift:1078-1080`），但 `onRenderFailure` 只有 Chat 答案预览消费（`NotesAgentView.swift:5269-5275`）；**笔记主编辑器没接**（`:776-811` 默认空闭包）。
- **选区问 Agent 走原生 SwiftUI**（Web 报 `selectionChanged` 带 rect，`editor.ts:2085-2101` → `NotesAgentView.swift:790-795`）。Slash Menu 现有 13 条目（H1-H3、三种列表、引用、提示块、代码块、分隔线、表格、图片、Mermaid，`editor.ts:403-417`），无公式/链接/脚注/H4-H6；无行首＋按钮；Web 内无格式浮条。
- Chat 公式清洗 `AgentChatKaTeXMarkdown.prepare`（括号 display、单行 `$$x$$`、`\hat y`）**只在 Chat 显示侧**（仅 `NotesAgentView.swift:5100, 5115` 两处调用）；笔记链路和 `applyAgentPatch` 插入路径不过它。
- **死代码**：`noteRenderMode`（`WorkspaceStore.swift:511`）与 `MarkdownSourceTextView`（`NotesAgentView.swift:995+`）已不是活路径，收口时删除。

### 2.3 依赖与构建事实（已验证）

- `@milkdown/plugin-math` **已被 npm 正式标记废弃**（"Package no longer supported"，最后发布 2025-01-17），最高版本 **7.5.9，不存在 7.21.x**，与 kit 7.21.3 错配。工作包 D 按路径 A/B 处理，**禁止假设存在可升级版本**。
- `@milkdown/plugin-streaming` 被 `editor.ts:14` 直接 import 但未在 `package.json` 显式声明（靠 kit 传递依赖提升），工作包 H 补声明。
- `$5` 金额误判：解析/输入侧**无防护**（plugin-math input rule 无数字守卫），仅序列化侧有 `\$` 转义还原（`editor.ts:795`）。防护必须同时覆盖 **Markdown parse 入口**和**实时输入 input rule** 两处，只修一处仍会从另一处吞字。
- 样式两处并存：`index.html` 内联 `<style>` 约 1300 行（魏碑产品样式）+ `editor.css`（构建产物，含依赖 CSS）。按"产品样式 / 生成依赖样式 / 节点样式"明确所有权，只删真实重复，**不盲目合并**。
- 仓库无 TS 测试运行器（`package.json` 仅 4 个 script）；已有 `tsx` devDependency，测试用 `node --test` + tsx，不引新框架。

---

## 3. 执行原则

### 3.1 先消除错误的数据流，再增加功能

```text
测量与消费方盘点 → Bridge/Session 改造 → 保存与恢复对齐
→ 公式与局部运行时 → 高价值语义节点 → 新手写作交互 → 运行时拆分与收口
```

PR 数量可以调整，但不能在旧全文热路径仍存在时继续堆重型功能。

### 3.2 一个职责只能有一个调度者

- `NoteEditingSession` 是 snapshot 与 durability 的唯一调度者；
- Web 编辑器只报告 dirty/revision，并在收到命令后生成 snapshot；
- 正式 Markdown 文件继续由现有 `WorkspaceStore+NotesPersistence` 链路写入；
- Application Support 中的恢复文件只由 `NoteRecoveryStore` 管理；
- 不允许 Web timer、Swift timer、View debounce 和 Store debounce 各自独立决定保存节奏。

### 3.3 双协议只短期存在

- 工作包 B：笔记主路径默认切 V2，V1 仅为默认关闭的 kill switch；
- 工作包 C：可靠性验证通过后，笔记主路径不再依赖 V1；
- 最迟在公式或增量运行时工作开始前删除 V1。

避免后续多个 PR 同时维护两套真相。

### 3.4 每个阶段都要验证手感，用户上手点写死

自动检查证明结构和回归，真实 App 判断手感与完整闭环。不得等所有工作完成后才第一次体验。

执行分工（不假设执行 Agent 具备画中画等桌面操作能力）：

- **执行 Agent 负责**：全部自动检查（`WeiBeiWebEditorCheck` 驱动真实 WKWebView，覆盖输入、IME、公式、粘贴、bridge、benchmark 计数）与候选包构建；若具备画中画能力可补充轻量冒烟，没有则不构成阻塞；
- **用户上手点（写死，见第十二节）**：工作包 B 后（硬性停止线）、工作包 C 后、最终候选版，共三处；其间任何已合入 `main` 的状态用户都可随时手动体验。

---

## 4. 目标架构

### 4.1 编辑状态所有权

笔记打开时：

- ProseMirror 是实时正文、选区和 Undo/Redo 的唯一权威；
- Swift 持有文档身份、revision、dirty、目录、保存状态和最近一次完整 snapshot；
- `WorkspaceStore.noteText` 变成"最近一次同步到 Swift 的完整 snapshot"，不再是每字符实时正文。

### 4.2 `noteText` 消费方分类

工作包 A 必须盘点所有 `noteText` 读写者并分类：

- **A. 必须得到最新正文**（Agent 读取当前笔记、导出、外部同步、切换、退出）→ 显式请求 snapshot，等待满足最低 revision 后继续；
- **B. 可以使用最近 snapshot**（非活动页面、部分搜索索引、低频摘要）→ 继续读 `noteText`，接受非实时；
- **C. 只需要元数据**（目录、字数、当前标题、dirty 状态）→ 使用增量事件，不读全文。

没有这份清单，不得开始删除实时 Binding。

### 4.3 Bridge V2

Swift → Web 命令均带 envelope：`protocolVersion` / `commandID` / `requestID`（需要应答时）/ `documentID` / `documentGeneration` / `minimumRevision`（需要最新内容时）。

```text
loadDocument / requestSnapshot / applyMarkdownFragment / replaceSelection
insertStructuredBlock / setTheme / setLanguage / setEditable / focus
scrollToHeading / restoreCheckpoint
```

Web → Swift 事件：

```text
editorReady / dirtyChanged { revision, dirty }
snapshotReady { requestID, revision, markdown }
outlineChanged / selectionChanged（含 rect、activeMarks、blockType，供原生浮条）/ editorAction
```

Swift 凭 requestID/generation/minimumRevision 识别：响应是否属于当前文档、是否满足最低 revision、是否已被新请求取代。旧 WebView 的延迟回调凭 generation 拒绝写入新笔记。

### 4.4 dirty 事件必须来自 transaction 层（关键陷阱）

`dirtyChanged` 必须在 ProseMirror plugin（`apply(transaction, state)` 检查 `transaction.docChanged`）或 `dispatchTransaction` 包装中产生。

**不得继续依赖 `listenerCtx.markdownUpdated`**——否则即使不再 bridge 全文，Milkdown 仍在每次输入时完成全文序列化（2.1 条 1 已验证）。实施方式：**完全移除 markdownUpdated listener 注册**（listener 数为 0 时 plugin-listener 整体跳过序列化，`lib/index.js:82` 守卫），完整 `readMarkdown()` 只在收到 `requestSnapshot` 时调用。

工作包 B 的核心自动断言：输入 100 字符期间 `docChanged transactions > 0` 且 `markdown serialization count = 0`；一次 snapshot 请求后 `= 1`。

### 4.5 Snapshot 调度

默认策略（毫秒数是默认值，工作包 A 后可调整；"一个调度者"和"普通输入不序列化"是硬要求）：

- 停止输入约 700–1000ms → 请求正常保存 snapshot；
- 长时间持续输入 → 最大 checkpoint 年龄：普通文档目标 ≤5 秒，超大文档按实测 serialization 成本自适应放宽至 10–15 秒；
- composition 中间不强制 snapshot；
- 切换、失焦、Agent 读取、导出、外部同步、退出、WebView 即将销毁 → 立即请求；
- 同时最多一个 snapshot in flight；新请求可合并，生命周期请求可提升优先级；
- 只有 `savedRevision == currentRevision` 才转 clean，保存中继续输入保持 dirty。

### 4.6 正式保存与 Recovery Checkpoint

**正式文件**继续走现有链路：`WorkspaceStore+NotesPersistence` → 路径与身份安全 → 备份环 → 原子写 → digest 校验 → 失败留草稿与轻提示。不新建第二套正式 Markdown writer。

**恢复 checkpoint** 由新建轻量 `NoteRecoveryStore`（actor）管理，只做 checkpoint I/O：

```text
Application Support/WeiBei/Recovery/Notes/<document-id>/
  metadata.json        { documentID, baseFileDigest, checkpointDigest, revision, updatedAt, dialectVersion }
  latest-snapshot.md
```

`dialectVersion` 仅用于诊断。checkpoint 存的是 **Markdown**，天然跨编辑器 schema——schema 变化不让 checkpoint 作废，由最新 parser 按同样无损规则读取。

恢复判断用三方 digest：

1. `disk == checkpoint` → checkpoint 已过期，清理；
2. `disk == base` → 磁盘未被外部修改，自动恢复 checkpoint；
3. `disk != base && disk != checkpoint` → 真实外部冲突，两份都保留，只给一条非技术选择："这份笔记在应用外也发生了修改。使用磁盘版本｜恢复魏碑中的内容"。不静默覆盖。

### 4.7 恢复取舍

v1 不做 Step JSONL：正常切换、失焦与退出目标零损失；WebContent Process 或 App 突然被杀最多损失一个自适应 checkpoint 窗口；只有真实故障数据证明该窗口不可接受时，才另立 Step Journal 加固任务。

---

## 5. 硬原则与可调整默认值

### 5.1 硬原则

| 项目 | 要求 |
|---|---|
| 产品模式 | 只有 WYSIWYG，无源码/双栏 |
| 普通输入全文 Markdown serialization | 0 次 |
| 普通输入全文 bridge payload | 0 次 |
| 普通输入触发 Host → Web 命令 | 0 次（合法配置变化允许一次去重命令） |
| 普通输入触发全局公式 DOM 扫描 | 0 次 |
| 普通段落输入重渲未修改 KaTeX/Mermaid | 0 个 |
| 纯选区移动触发全树重装饰 | 0 次 |
| Swift 每按键全文目录扫描 | 0 次 |
| 解析失败静默删除内容 | 0 处 |
| 用户可见技术错误中心 | 0 个 |
| IME 现有行为 | 不得退化 |
| 正式文件保存 | 复用现有安全链路 |
| 核心共享文件改动 | 按职责、调用链和所有调用者正常评审，不以机械行数作为完成条件 |

### 5.2 可调整默认值

| 项目 | 默认建议 | 允许调整的依据 |
|---|---|---|
| 工作包对应 PR 数量 | 9–11 个 | diff 风险、共享文件占用、可独立验收性 |
| idle snapshot | 700–1000ms | 工作包 A serialization 数据与真实手感 |
| checkpoint 最大年龄 | 普通文档约 5s | 文档体积、serialization 时长、故障数据 |
| 某扩展是否节点化 | 先做高价值对象 | 编辑破坏率、性能热点、真实交互需求 |
| 选区浮条实现层 | 默认原生 SwiftUI | 焦点、坐标、可访问性与现有 Agent 浮层复用；产品中只能存在一套选区浮层 |
| 动态加载方式 | 默认 ESM chunks | `WKWebView.loadFileURL`、签名包与离线验证 |
| 绝对性能数字 | 第七节数值作为目标 | 工作包 A 基线与 M4 真机取样 |

---

## 6. 推荐工作包与 PR 切分

依赖顺序如下。工作包 F、G 可根据 diff 大小各拆成两个 PR；其他工作包若合并，验收边界必须仍清晰。每个工作包 = 从最新 `origin/main` 建短分支、当天推草稿 PR、声明占用。

### 工作包 A · 基线、消费方盘点与技术预研

**推荐分支**：`codex/wysiwyg-editor-baseline`；占用：无共享面

**必做**：

- `Tests/Fixtures/Writing/` 新增长文 fixtures：普通 5k/50k/100k、公式密集、代码密集、图片密集、Mermaid、30×20 表格、中文长文与中英混排；
- 仅检查模式启用的计数器（正常构建零开销）：transaction、**完整 serialization 次数**、bridge 次数与字节、Decoration 访问节点数、KaTeX/Mermaid 渲染计数、图片扫描、代码 tokenize；
- 扩展 `Sources/WeiBeiWebEditorCheck/main.swift` benchmark 模式，真实 WKWebView 跑 fixtures 输出机器可读 JSON；
- TS 测试基建：`Sources/WeiBei/WebEditor/test/` + `node --test` + tsx（确认 Node 版本与 glob 写法后固定），新增 `package.json` 脚本 `test:editor`；调 `tsconfig.editor.json` 使测试被 typecheck 但不进 esbuild 产物；落地首批 round-trip 与计数器用例；
- **`noteText` 消费方清单**（4.2 的 A/B/C 分类），产出进 `Docs/audit/`，是工作包 B 的迁移依据；
- 两个技术 spike，结论写进 `Docs/audit/`：
  - 现有 `math_inline/math_block` 能否安全覆盖 NodeView 而不复制 Schema（工作包 D 选路依据）；
  - `WKWebView.loadFileURL` 下本地 ESM dynamic import 可用性（签名包 chunk 路径、网络 guard、离线；工作包 H 选路依据，禁止运行时 CDN）；
- 基线数据进 `Docs/audit/`（日期 + fixture + 各项计数 + snapshot 耗时分布——4.5 自适应 checkpoint 年龄依据）。

**不做**：不改变用户可见行为；不先锁死性能绝对阈值；不开始正式 Bridge 迁移。

**验收**：同 fixture 重跑计数稳定；消费方清单足以支撑工作包 B；两个 spike 有明确结论或明确未决项；`npm run build:editor && npm run typecheck:editor && npm run test:editor`、`swift run WeiBeiWebEditorCheck`、`make check` 全绿。

### 工作包 B · Bridge V2 与 NoteEditingSession（手感首验）

**推荐分支**：`codex/editor-bridge-v2`；占用：`WorkspaceStore.swift`（净增 ≤0）；`NotesAgentView.swift` 目标净删除

**必做**：

- 新建 `Sources/WeiBei/Editing/`（session、bridge envelope、command queue、outline model）；
- dirty/revision 从 ProseMirror transaction 层产生（4.4）；**完全移除 `markdownUpdated` listener 注册**；
- `@Binding<String>` 退出实时输入协议；`WorkspaceStore.noteText` 改为最近 snapshot 语义；
- 按工作包 A 清单迁移消费方（A 类先 snapshot 后动作）；
- 保留全部 IME 行为、选区问 Agent、WikiLink、来源跳转和现有快捷键；
- `updateNSView` 允许真实配置变化的一次去重命令，普通输入不得触发 Host→Web 命令；
- V1 只保留为默认关闭的 kill switch；
- `noteRailItems` 过渡期基于最近 snapshot 文本（输入中目录允许滞后，工作包 E 切增量事件）。

**注意**：不要让 Web 和 Swift 各自启动 idle timer。本工作包只完成 request/response 与 session 状态，durability 调度在工作包 C 接齐。

**结构验收**（进自动断言）：连续输入 100 字符——docChanged transaction 正常增长；**完整 serialization = 0**；全文 bridge = 0；SwiftUI 不按字符接收正文；普通输入 Host→Web 命令 = 0；显式请求 snapshot 后 serialization 恰好一次；中文 composition 不重复不跳字；旧 generation 消息被拒绝；`make check` 全绿。

**真实 App 验证门（用户上手，必过才许进工作包 C）**：连续中文输入；删除、换行、Undo/Redo；50k 笔记开头/中间/结尾输入；快速切换笔记；输入后立即问 Agent；输入后立即失焦。**手感或最新正文语义不对就停在这里修，不把恢复层建在错误桥接上。**

### 工作包 C · 正式保存、Recovery Checkpoint 与生命周期

**推荐分支**：`codex/note-editing-recovery`；占用：`WeiBeiApp.swift`、`WorkspaceStore.swift`

**必做**：

- `NoteEditingSession` 成为唯一 snapshot/durability scheduler（4.5 全量接通：idle、max-age、switch、resign、agentRead、export、externalSync、terminate）；
- 新建 `NoteRecoveryStore`（actor，只做 checkpoint I/O）；正式 snapshot 继续进 `WorkspaceStore+NotesPersistence` 全链，不另起保存实现；
- 移除 220ms View 层全文 flush；420ms 正式写入 debounce 是否保留由实测决定，但最终只能有一个有效的内容 coalescing 策略；
- 笔记主编辑器消费 WebContent Process failure：销毁失效 WebView → 重建 → 加载磁盘或按三方 digest 恢复 checkpoint（4.6）→ 恢复合理光标位置；用户只见短暂重载；
- 退出复用 `terminateLater`，等待活动编辑器达到可靠边界；正常流程不增加用户状态噪音；
- **删除笔记主路径对 V1 的依赖**；kill switch 最多再保留一个短 PR，不进入公式与增量化长期开发；
- 测试：杀 WebContent Process 恢复、强退 App 恢复、save-while-typing 不错标 clean、只读/不可写不覆盖、三方 digest 三分支、正常流程零状态噪音。

**验收**：正常切换/失焦/退出零丢失；异常最多损失 checkpoint 窗口；外部修改不被静默覆盖；`make check` 全绿。

**真实 App 验证门（用户上手）**：输入后立刻切换；输入后立刻退出；保存中继续输入；Web 进程重建；外部编辑同一 Markdown 后回到魏碑。

### 工作包 D · 公式方言与现有 Math 节点 NodeView

**推荐分支**：`codex/unified-wysiwyg-math`；占用：无共享面

**实现决策**（按工作包 A spike 结论二选一，结论写 PR 描述）：

- **路径 A**：旧 plugin 可稳定覆盖 NodeView → 保留 `math_inline/math_block` 与现有 Markdown 兼容，接魏碑 NodeView，隔离已废弃 plugin，用测试锁住 round-trip；彻底移除留到工作包 H/I；
- **路径 B**：旧 plugin 与当前 Kit 实际冲突 → 只移植 math schema、remark parser、input rules、serializer 的最小必要部分为本地 extension，节点名与 Markdown 输出不变，删除旧 plugin；
- **不得假设存在 plugin-math 7.21.x**（npm 最高 7.5.9，已验证）。

**来源分级 normalization**（共享基础规则，不等于同一 heuristic）：

- `userDocument`：最保守，不猜模糊数学，不动 `$5`，不改写原始分隔符；
- `userPaste`：识别明确的 `\(...\)`/`\[...\]`/标准 `$...$`，模糊中括号留普通文本，可整体撤销；
- `agentGenerated`：允许单行 `$$x$$` 展开、`\hat y` 修复、明显模型伪定界符，仍不误伤金额引用；
- `internalFragment`：直接用规范节点或 canonical Markdown，无启发式。

`AgentChatKaTeXMarkdown.prepare` 能力按此迁入 Web 共享层；Chat 显示、笔记解析、粘贴、`applyAgentPatch` 插入四处按各自来源级别走同一模块；Swift 侧收敛为轻路由或删除。

**必做**：

- `$5`/`$10–$20`/`\$5` 防护同时落在 **parse 入口**与 **input rule** 两处（2.3）；
- 原地编辑 NodeView：未选中只显示 KaTeX；点击展开轻量编辑框（Enter 提交 / Esc 保留退出 / 点外部提交 / 节点选中时 Backspace 删整节点 / 方向键自然进出 / 块公式多行 / 行内↔块级切换 / 选中转行内公式）；
- 非法公式无损降级：显示源码 + 极轻虚线/浅底；无红字无图标无技术详情；仅聚焦或悬停一句"暂时无法显示，继续编辑即可"；修复自动恢复；
- 删除 `upgradeDisplayMath` 全局扫描、`.katex-error` 扫描、`font-size: 0` 隐藏链（含 `index.html:1036-1113` 内联样式）；
- Slash Menu 加行内/块公式（中文/拼音/别名搜索）；
- 公式测试矩阵：行内/块级/兼容分隔符/求和积分/上下标/矩阵/cases/aligned/希腊字母/中文混排/金额/转义/code 内/不完整 `\frac{a}{`/未知命令/列表表格内/保存重开/Undo-Redo。

**验收**：改普通段落未修改公式渲染数 = 0；改一个公式只重渲该公式；失败公式源码完整可续编；金额不误判；Chat/Agent 内容进笔记可显示可续编；`make check` 全绿。

**真实 App 验证门**：公式输入、编辑、不完整态、金额、Chat 粘贴、保存重开。

### 工作包 E · 有取证依据的增量运行时优化

**推荐分支**：`codex/incremental-editor-runtime`；占用：`NotesAgentView.swift` 目标净删除（删全文目录扫描）

**推荐顺序**（每步以工作包 A 计数器验证收益）：

1. `transaction.docChanged === false` 时直接复用旧 `DecorationSet`——纯光标/选区移动不再全树重装饰（零风险收益）；
2. 可限制在单 textblock 的 inline 语法改 changed-range 局部重装饰；
3. 图片改 Image NodeView 自管理（src/加载态/尺寸/alt/拖放/粘贴/主题），删除全 doc 遍历 + DOM 下标配对（`editor.ts:1025-1085`）；
4. 代码块只在自身内容变化时 tokenize；
5. Mermaid 保留已有缓存，加源码稳定 250–400ms debounce，失败显示原文本可续编；
6. outline 直接从 heading 节点产生、仅标题增删/文字/层级变化时发送；删除 Swift 全文逐行扫描（`NotesAgentView.swift:726-755`）与 markdown 行号 vs DOM 下标错位隐患；
7. ResizeObserver/高度报告统一节流。

**不要求**：不把所有跨块正则做成完美增量算法；即将在工作包 F 节点化的复杂语法不先写高风险跨块增量状态机；少数低频、暂未节点化且未构成热点的扫描可短期保留并记录。

**验收**：100k 长文和密集 fixture 中改普通段落——无全文 serialization/bridge；纯选区移动不重新装饰全文；不重解析所有图片；未修改 KaTeX/Mermaid 调用 = 0；未变化 outline 不发送；真实输入 p95 较基线显著改善且无规律性 checkpoint 卡顿；`make check` 全绿。

**真实 App 验证门**：普通长文、公式密集、代码密集、图片密集、Mermaid 文档各体验一次。

### 工作包 F · 高价值 Markdown 语义对象

**推荐拆分**：按 diff 大小一个或两个**顺序** PR（如 `codex/structured-inline-nodes` + `codex/structured-block-nodes`）；不并行改两套 Schema。

**第一优先级**（明确对象语义与编辑需求）：`wiki_link`、`highlight` mark、行内 `^[...]` footnote、Callout（独立节点，脱离 blockquote Decoration）、Embed。

每项至少齐备：parse / serialize / render-edit / copy-paste / undo-redo / selection-delete / round-trip。

**暂不默认节点化**：Frontmatter（PM 外属性面板可继续存在）；Comment（只需弱化显示则 Decoration 足够）；Source Reference（可继续是 mark/Decoration）。只有满足至少一项才升级：字符串装饰经常被光标或删除破坏；需要独立编辑 UI；Copy/Paste 或 Agent Patch 经常损坏；是已测得性能热点；用户明确把它当对象操作。**不为"架构完整"节点化所有扩展。**

**验收**：每项过 `parse → render → edit → copy → paste → undo → redo → serialize → reopen`；旧文件内容不丢失；第八节门禁全过；`make check` 全绿。

**真实 App 验证门**：旧文件打开、复制粘贴、复杂块编辑。

### 工作包 G · 纯 WYSIWYG 写作交互

**推荐拆分**：基础发现入口与复杂结构操作可分两个 PR（如 `codex/wysiwyg-authoring-basics` + `codex/wysiwyg-authoring-structures`）。

**界面所有权**：原生 SwiftUI 负责唯一选区浮条（复用现有问 Agent 坐标、焦点、可访问性）；Web 上报 `selectionRect / activeMarks / blockType / canConvertToMath`，点击发结构化命令。Web 负责 Slash Menu、行首＋、表格单元格菜单、公式与 Callout 节点内部交互。若实施证明 Web 内统一浮条更可靠可调整，但**产品中只能存在一套选区浮层**。

**基础交互**：新笔记极淡提示（输入即消失，不提 Markdown）；行首＋与 Slash 共用命令数据；Slash 补齐 H4–H6、链接、笔记链接、脚注与公式；中文/英文/拼音/别名搜索；选区浮条（粗体/斜体/高亮/链接/行内代码/公式/引用/问 Agent，不遮选区、键盘可导航、Esc 关闭、操作后光标稳定）；链接原地编辑（单行输入、读剪贴板不自动提交、Enter/Esc、已有链接可编辑/打开/移除）。

**复杂结构**（复用已有基础，只补缺口）：表格增删行列、表头、列宽（挂 `columnResizingPlugin`）、TSV/Excel 粘贴、最后一格 Tab 新增行、窄窗口横滚、删空表格、表格内公式/链接/强调（Tab 导航已有，勿重复造）；图片 /图片、拖入、粘贴、Finder、URL、选中更换/删除/调尺寸、失败保留可选中节点不吞地址；Callout 类型下拉、标题正文原地编辑、折叠可选、不显示 `[!note]`、未知类型中性保留；键盘可达与 VoiceOver。

**验收**：完全不懂 Markdown 的用户只靠可见操作完成标题/列表/待办/引用/链接/高亮/行内与块公式/表格/图片/Callout/选中问 Agent，全程不要求看到或修复 Markdown 控制符；`make check` 全绿。

**真实 App 验证门**：新手基础任务与完整任务。

### 工作包 H · Editor / Viewer 运行时拆分与按需加载

**推荐分支**：`codex/editor-viewer-runtime-split`；占用：`Package.swift`（如资源声明变化）、`script/`（如构建脚本变化）

**决策**：用工作包 A 预研结论——本地 ESM chunks 在开发、离线、候选包中稳定则用 code splitting；不稳定则多个本地静态 bundle 按需注入；不用运行时 CDN。

**必做**：`editor-entry` 与 `viewer-entry` 分离（viewer 无 history/upload/可编辑 NodeView/写作菜单，保留选择、来源跳转、紧凑高度报告）；`@milkdown/plugin-streaming` 显式声明；Mermaid、Prism grammar、必要时 KaTeX renderer 按需加载；纯文本笔记不执行无关模块；资源 manifest 与完整性自检；CSS 按所有权梳理只删真实重复；如工作包 D 选路径 A，此包完成旧 plugin-math 移除。

**验收**：纯文本笔记不执行 Mermaid/未使用 grammar；只读 Chat 不加载编辑能力；本地离线、开发构建、候选签名包均正常；editor 核心体积与初始化成本显著低于当前 4.6MB 单包；CI 产物零差异；`make check` 全绿。

**真实 App 验证门**：冷启动、Chat 历史渲染、签名包。

### 工作包 I · 收口、删除旧路径与唯一候选版

**推荐分支**：`codex/wysiwyg-writing-final-validation`；占用：按实际触碰声明

**必做**：删除 Bridge V1 残余与 kill switch、旧公式 DOM 补丁、重复 parser、死代码（`noteRenderMode`、`MarkdownSourceTextView` 及关联）、真实无效 CSS；更新架构说明与本计划决策记录；从干净 `main` 构建唯一候选 App；Agent 先初步全链路冒烟清阻塞；交付用户最终闭环验收。本工作包只做迁移收口、删除和验证，不发明新交互。

---

## 7. 性能与可靠性验收

### 7.1 结构门槛

进入自动检查，不依赖机器速度，不得放宽：普通输入完整 serialization = 0；普通输入全文 bridge = 0；普通输入 Host→Web 命令 = 0；普通段落输入全局 math DOM 扫描 = 0；未修改 KaTeX/Mermaid 重渲 = 0；纯选区移动全树重装饰 = 0；Swift 每按键全文目录扫描 = 0；未知内容静默删除 = 0；用户可见技术错误中心 = 0。

### 7.2 候选版性能目标

| 场景 | 初始目标 |
|---|---:|
| 5k 字 input-to-paint p95 | ≤16ms |
| 50k 字 p95 | ≤24ms |
| 100k 字 p95 | ≤40ms |
| 连续输入 >100ms 长任务 | 0 次 |
| 50k 笔记切换 | ≤250ms |
| 50k editor ready | ≤600ms |
| idle 到正式持久化 | 通常 ≤1s |

工作包 A 后可基于 M4 真机数据调整绝对数值，但不得通过放宽数值掩盖结构门槛失败。

### 7.3 可靠性

正常切换/失焦/退出内容丢失 = 0；异常崩溃最多一个自适应 checkpoint 窗口；保存中继续输入不错误转 clean；外部修改不被恢复文件静默覆盖；WebContent Process 重建能从磁盘或 checkpoint 恢复；只读/不可写/路径异常沿用现有保护与轻提示。

---

## 8. 数据无损策略（两层，不得混用）

**CI 层（严格）**：涉及 parser/serializer 的改动对所有 fixtures 执行 `原 Markdown → parse → 文档树 → serialize → 新 Markdown → 再 parse → 第二棵树`：语义等价；serializer 幂等；frontmatter 未知字段保留；图片、WikiLink、来源 target 保留；公式 source 完整；code fence 逐字保留；未知 payload 不消失；正文不异常减少。

**生产层（保守，防误报卡死用户）**：新 serializer 首次写旧文件——先走现有备份环；serializer 抛错则不覆盖；正文无异常归零；公式、图片、WikiLink 等关键 target 无无解释大量减少；原子写 + 写后 digest；失败保留最新内容并用现有轻提示。**不在生产保存路径做容易误报的通用 AST 等价比较。**

---

## 9. 测试体系与验证命令

- TS 纯逻辑（工作包 A 建）：`npm run test:editor`（node --test + tsx）、`npm run typecheck:editor`。覆盖 bridge envelope 与 generation、revision/dirty reducer、snapshot 合并、math normalization 与金额规则、round-trip、outline diff、changed-range Decorations、checkpoint metadata 与冲突判断。
- 真实 WKWebView：`swift run WeiBeiWebEditorCheck`。覆盖 IME、Bridge V2、snapshot 请求、Web 进程重建、Math NodeView、粘贴、Slash 与选区命令、表格键盘流、图片与 Mermaid、主题与资源加载、benchmark 计数。
- Swift：`swift test --filter WeiBeiSafetyTests`。覆盖 session 状态机、stale generation、save-while-typing、fresh snapshot gate、正式保存复用、recovery checkpoint、三方 digest 冲突、切换/失焦/退出、Agent 读写最新正文。
- 总闸：`make check`（SelfCheck + SafetyTests + WebEditorCheck + PiCheck）；CI 另有产物零差异（`git diff --exit-code -- Sources/WeiBei/Resources/Editor`）、`git diff --check`、工作树干净。

**每个 PR 的最小完成条件**：构建与相关检查通过；editor 生成产物随 PR 提交且与源零差异；核心文件改动完成正常代码审查；草稿 PR 写清占用、实际改动、未做、验证与真实冒烟；用户可见改动至少一次冒烟——执行 Agent 具备画中画能力时做轻量真实 App 冒烟，不具备则以 `WeiBeiWebEditorCheck` 真实 WKWebView harness 冒烟替代并在 PR 注明。

---

## 10. 仓库硬约束

- 每个实现任务从最新 `origin/main` 建短分支 `codex/<任务名>`，当天推草稿 PR；
- 共享核心面（`WorkspaceStore.swift`、`WeiBeiApp.swift`、`ContentView.swift`、`StableDocumentWorkspace.swift`、`WeiBeiSelfCheck/main.swift`、`Package.swift`、`script/`、`.github/`、`VERSION`）修改前在草稿 PR 声明占用；发现已占用即停手交主会话协调；
- 核心文件按实际职责与完整调用链评审；新逻辑优先进 `Sources/WeiBei/Editing/`、`WebEditor/src/bridge/`、`WebEditor/src/nodes/` 等聚焦文件，但不为控制行数外移逻辑；
- 不绕过自动检查，不用回退实现伪造通过；
- 旧分支只用于取证，不整体 merge 或批量 cherry-pick。

这些仓库规则是执行环境约束，不应反过来驱动产品设计；合理改动确实需要豁免时按流程说明真实理由，而不是扭曲实现讨好行数。

---

## 11. 风险与回滚

| 风险 | 默认缓解 | 回滚边界 |
|---|---|---|
| Bridge V2 最新正文消费方遗漏 | 工作包 A 消费方清单 + fresh snapshot gate | kill switch（工作包 C 后删除） |
| `markdownUpdated` 仍暗中序列化全文 | 计数器断言 dirty 来自 transaction（serialization = 0） | 单 PR 回退 Bridge 实现 |
| checkpoint 周期造成规律性卡顿 | idle + max-age 自适应、单一 in-flight | 放宽 max-age，不回到每击键同步 |
| checkpoint 误覆盖外部修改 | 三方 digest 三分支 | 磁盘与 checkpoint 两份都保留 |
| 旧 math plugin 与新 Kit 冲突 | 工作包 A spike，路径 A/B | 复用旧节点或本地最小移植 |
| 增量 Decoration 错位 | 先跳过 non-docChanged 再局部化；跨块语法不做增量正则 | 对该语法暂退全量扫描 |
| 节点化破坏旧文件 | 高价值优先 + CI 严格 round-trip + 生产保守不变量 | 保留 Decoration/mark 实现 |
| 双浮层与焦点冲突 | 唯一选区浮层所有者 | 保留现有原生问 Agent 路径 |
| dynamic import 不稳 | 工作包 A 预研 | 多个本地静态 bundle |
| 生产无损检查误报 | 严格检查只在 CI | 生产使用备份 + 保守不变量 |

---

## 12. 真实 App 验证节奏与用户上手点

不假设执行 Agent 具备画中画等桌面操作能力：能自动化的门全部由 `WeiBeiWebEditorCheck`（真实 WKWebView harness）+ benchmark 计数承担；用户上手点写死为三处，**不会直到全部做完才第一次开 App**。

- **工作包 B 后（用户上手，硬性停止线）**：输入手感与最新正文——中文连续输入；长文开头/中间/结尾；快速切换；输入后立即问 Agent；失焦与返回。不过则停在 B 修桥接，不得进入 C；
- **工作包 C 后（用户上手）**：可靠性——输入后立即切换/退出；保存中继续输入；杀 WebContent Process；强制杀 App；外部修改同一文件；
- **工作包 D/E/F/G/H 后（自动门）**：公式矩阵、长文性能计数、旧文件 round-trip、Slash/浮条/表格键盘流等均由 harness 与结构断言承担；每个工作包合入 `main` 后均为可用状态，用户可随时手动体验，体验发现问题定向回归；
- **最终候选版（用户上手）**：按第十三节清单验收，四栏，不要求记录工程证据；某项失败后定向修复并回归该场景及相关路径，不从第一项重跑。

---

## 13. 最终用户验收清单

| 用户怎么操作 | 应该看到什么 | 是否通过 | 问题备注 |
|---|---|---|---|
| 新建笔记连续输入中文两分钟 | 顺滑，无重复字、跳字、明显停顿 |  |  |
| 长笔记开头/中间/结尾输入 | 三处手感基本一致 |  |  |
| `/` 或 `＋` 插入标题、列表、待办 | 不输入控制符，结构立即出现 |  |  |
| 选中文字加粗、链接、高亮 | 只有一套轻量浮条 |  |  |
| 插入行内/块公式 | 正常显示，可点击原地编辑 |  |  |
| 故意删掉公式一个大括号 | 源码原地保留，补回后恢复 |  |  |
| 输入 `$5`、`$10–$20` | 仍是普通金额文字 |  |  |
| 从 Chat 复制含公式与列表的回答 | 粘贴后成为可编辑结构 |  |  |
| 插入并编辑表格 | Tab 导航与增删行列自然 |  |  |
| 粘贴或拖入图片 | 正常显示，重开仍存在 |  |  |
| 插入代码块和 Mermaid | 节点内可编辑，正文输入不受影响 |  |  |
| 快速切换多份笔记 | 内容不丢失，无长期未写回 |  |  |
| 输入后立即关闭再重开 | 正常退出零丢失；异常退出恢复最近 checkpoint |  |  |
| 应用外修改同一份笔记后重开 | 出现版本选择，不静默覆盖 |  |  |
| Agent 读取并插入当前笔记 | 读到最新内容，插入位置正确且可继续编辑 |  |  |
| 窄窗口与深色主题 | 表格、公式、菜单和浮层不溢出 |  |  |
| 打开含未知 Markdown 的旧笔记 | 正文可读，未知内容不被静默删除 |  |  |

---

## 14. 最终完成定义

同时满足才算完成：

1. 产品保持纯 WYSIWYG，无源码或双栏；
2. 普通输入不再 serialization 或 bridge 全文（4.4 断言）；
3. Swift 不再每字符发布完整正文；
4. Agent、切换、导出等需要最新正文的路径使用 fresh snapshot；
5. 正常保存继续复用现有安全链路；
6. 异常恢复使用轻量 checkpoint，不引入 Step Journal；
7. IME 不退化；
8. 公式使用现有节点上的可编辑 NodeView 或兼容的本地最小 extension；
9. `$5` 等金额不误判；
10. 未修改公式、图片、代码和 Mermaid 不因普通正文输入而重算；
11. 高价值 Markdown 对象具备稳定编辑与 round-trip；

12. 不懂 Markdown 的用户可以完成完整常见写作；
13. 未知语法和旧笔记内容不静默丢失；
14. Bridge V1、旧全文 Binding、旧公式补丁与死代码已删除而非并存；
15. 自动检查、CI、核心文件代码审查和真实 App 阶段验收全部通过；
16. 从干净 `main` 构建的唯一候选版完成用户闭环。

这份计划约束的是正确的产品结果、数据安全和性能结构，不约束执行 Agent 必须用某个漂亮但多余的架构。执行中持续以"能否更简单、更可靠地满足目标"为判断标准。

## 15. 执行决策记录（2026-08-20）

- 笔记编辑只保留 Bridge V2；普通输入只发 dirty，最新全文只由显式 snapshot 请求产生。
- 正常保存继续复用原笔记持久化链；异常恢复只保存轻量 checkpoint，没有引入 Step Journal。
- 公式沿用现有 `math_inline` / `math_block` 节点与本地 NodeView；旧 `plugin-math` 和旧 DOM/CSS 补丁已移除。
- 本地 ESM 在真实 `WKWebView.loadFileURL` 下被拒绝，因此采用普通本地 IIFE：编辑、只读、KaTeX、Mermaid、Prism 分包，按内容首次加载。
- Reader / Chat 使用只读入口并保留累计流式渲染；历史、上传、Slash、可编辑 NodeView 与 dirty/snapshot 不进入只读包。
- 源码编辑器、双栏/源码显示模式、Bridge V1 全文回传和 kill switch 已删除，不保留兼容层。
