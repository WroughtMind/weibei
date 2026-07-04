import Foundation
import WeiBeiCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("self-check failed: \(message)\n", stderr)
        exit(1)
    }
}

let runScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("script/build_and_run.sh")
let runScript = (try? String(contentsOf: runScriptURL, encoding: .utf8)) ?? ""
expect(runScript.contains("kCGWindowOwnerName") && runScript.contains("\"$APP_DISPLAY_NAME\""), "run script verifies the visible app window by owner name")
expect(runScript.contains("let isOnscreen = window[kCGWindowIsOnscreen as String] as? NSNumber") && runScript.contains("let visibleEnough = isOnscreen == nil || isOnscreen?.intValue != 0"), "run script tolerates missing onscreen metadata when the window is otherwise capturable")
expect(!runScript.contains("pid=\"$(pgrep -x \"$PRODUCT_NAME\""), "run script window verification does not depend on pgrep")
expect(runScript.contains("visual_verify_window") && runScript.contains("--visual-verify") && runScript.contains("visual_non_black_ratio") && runScript.contains("visual verify failed: captured window is black or empty") && runScript.contains("nonBlackRatio < 0.02"), "run script exposes an explicit visual non-black window check")
expect(runScript.contains("visual verify blocked: macOS refused window capture") && runScript.contains("Grant Screen Recording permission"), "visual verification reports capture-permission failures instead of looking like an app rendering failure")
expect(runScript.contains("RUN_VISUAL_VERIFY=false")
    && runScript.contains("if [[ \"${2:-}\" == \"--visual-verify\"")
    && runScript.contains("if [[ \"$RUN_VISUAL_VERIFY\" == true ]]; then\n          visual_verify_window")
    && runScript.contains("swift run WeiBeiWebEditorCheck"), "run script verify mode includes Web editor checks and honors --verify --visual-verify")
let editorIndexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
let editorIndexSource = (try? String(contentsOf: editorIndexURL, encoding: .utf8)) ?? ""
expect(
    editorIndexSource.contains(".ProseMirror span[data-type=\"math_inline\"],")
        && editorIndexSource.contains(".ProseMirror span[data-type=\"math-inline\"],")
        && editorIndexSource.contains(".ProseMirror div[data-type=\"math-block\"],")
        && editorIndexSource.contains(".ProseMirror .math-inline")
        && editorIndexSource.contains(".ProseMirror .math-block"),
    "math styling hides raw source for common Milkdown math node attribute and class shapes"
)
expect(
    editorIndexSource.contains(".ProseMirror .math-inline {\n      color: transparent")
        && editorIndexSource.contains("font-size: 0;")
        && editorIndexSource.contains("font-size: 1rem;")
        && editorIndexSource.contains(".ProseMirror .katex-error {\n      color: var(--cinnabar)"),
    "math styling collapses raw source while keeping KaTeX and errors readable"
)
expect(editorIndexSource.contains("color: rgba(58, 46, 38, .56)") && !editorIndexSource.contains("color: rgba(58, 46, 38, .36)"), "editable markdown markers stay readable on paper")
expect(editorIndexSource.contains(".frontmatter-title {\n      color: var(--muted)") && editorIndexSource.contains("li[data-item-type=\"task\"][data-checked=\"true\"] {\n      color: var(--muted)"), "small frontmatter and completed task text avoid faint low-contrast ink")
expect(editorIndexSource.contains(".weibei-source-reference") && editorIndexSource.contains("border-bottom: 1px dotted"), "source references have readable link styling")

expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.pdf")) == .pdf, "pdf detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.html")) == .html, "html detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.md")) == .markdown, "markdown detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.txt")) == .text, "text detection")

let data = Data("""
{"output":[{"content":[{"type":"output_text","text":"只根据当前材料回答。"}]}]}
""".utf8)
let text = try OpenAIResponsesClient.extractText(from: data)
expect(text == "只根据当前材料回答。", "response parser")
let groundedPrompt = OpenAIResponsesClient.composePrompt(
    question: "解释金融体系",
    materialTitle: "Mishkin 教材样例",
    materialText: "金融体系把储蓄者的资金转移给有投资机会的人。",
    noteTitle: "利率笔记",
    noteText: "## 摘录\n金融体系和利率相关。",
    selectionTitle: "Mishkin 教材样例，第 1 页选区",
    selectionText: "储蓄者的资金转移给有投资机会的人",
    recentMessages: [
        AgentMessage(role: .user, text: "上一问", source: "利率笔记")
    ]
)
expect(groundedPrompt.input.contains("当前材料：Mishkin 教材样例"), "agent prompt includes material title")
expect(groundedPrompt.input.contains("当前笔记：利率笔记"), "agent prompt includes note title")
expect(groundedPrompt.input.contains("当前选区（来源：Mishkin 教材样例，第 1 页选区）："), "agent prompt includes selection source")
expect(groundedPrompt.input.contains("用户（来源：利率笔记）：上一问"), "agent prompt keeps recent message source")
expect(groundedPrompt.instructions.contains("来源依据") && groundedPrompt.instructions.contains("没有用到的来源不要列"), "agent prompt requires grounded source evidence")
let noteOnlyPrompt = OpenAIResponsesClient.composePrompt(
    question: "整理这段",
    materialTitle: "未选择材料",
    materialText: "",
    noteTitle: "概念笔记",
    noteText: "实际利率需要区分通胀预期。",
    selectionText: "实际利率",
    recentMessages: []
)
expect(noteOnlyPrompt.input.contains("当前材料：无") && noteOnlyPrompt.input.contains("当前选区（来源：概念笔记）："), "note-only prompt anchors selection to the current note")
let openAIClientSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBeiCore/OpenAIResponsesClient.swift")
let openAIClientSource = (try? String(contentsOf: openAIClientSourceURL, encoding: .utf8)) ?? ""
expect(
    openAIClientSource.contains("let hasMaterial = !trimmedMaterial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty")
        && openAIClientSource.contains(": \"当前材料：无\"")
        && openAIClientSource.contains("只根据当前笔记和当前选区回答")
        && openAIClientSource.contains("当前选区（来源：\\(selectionLabel)）")
        && !openAIClientSource.contains("只根据当前材料和当前笔记回答"),
    "agent request prompt switches to note-only context when no material exists"
)
expect(OpenAIAPIKeyStore.cleaned("  sk-test\n") == "sk-test", "api key cleaning")

let temporaryKeychainStore = KeychainPasswordStore(
    service: "com.changfenhuang.weibei.selfcheck.\(UUID().uuidString)",
    account: "OPENAI_API_KEY"
)
try? temporaryKeychainStore.delete()
try temporaryKeychainStore.save("  sk-selfcheck\n")
expect(temporaryKeychainStore.load() == "sk-selfcheck", "keychain save and load")
try temporaryKeychainStore.delete()
expect(temporaryKeychainStore.load().isEmpty, "keychain delete")

let missingSelectionInsight = QuietInsight.make(
    materialTitle: "利率资料",
    materialText: "实际利率扣除了通货膨胀后的购买力变化。",
    noteText: "# 利率资料\n",
    selectionText: "实际利率扣除了通货膨胀后的购买力变化。"
)
expect(missingSelectionInsight.body.contains("还没有进入笔记"), "selection insight")

let coveredMaterialInsight = QuietInsight.make(
    materialTitle: "利率资料",
    materialText: "实际利率扣除了通货膨胀后的购买力变化。",
    noteText: "实际利率扣除了通货膨胀后的购买力变化。",
    selectionText: nil
)
expect(coveredMaterialInsight.body.contains("已经覆盖"), "covered material insight")
let noteOnlyInsight = QuietInsight.make(
    materialTitle: "新概念笔记",
    materialText: "",
    noteText: "实际利率需要区分名义利率和通胀预期。",
    selectionText: nil
)
expect(noteOnlyInsight.body.contains("当前笔记有一条") && !noteOnlyInsight.body.contains("先导入"), "note-only quiet insight uses note context")
expect(noteOnlyInsight.noteBlock.contains("来源：新概念笔记"), "note-only quiet insight keeps note source")
let coveredNoteSelectionInsight = QuietInsight.make(
    materialTitle: "新概念笔记",
    materialText: "",
    noteText: "实际利率需要区分名义利率和通胀预期。",
    selectionText: "实际利率需要区分名义利率和通胀预期。"
)
expect(!coveredNoteSelectionInsight.body.contains("当前材料其他段落"), "covered note selection avoids fake material relation")
let agentInsight = QuietInsight.agent(materialTitle: "利率资料", answer: "这份材料更适合先补通胀预期这一层。")
expect(agentInsight?.body.contains("通胀预期") == true, "agent insight keeps answer")
expect(agentInsight?.noteBlock.contains("Agent 洞察") == true, "agent insight writes labeled note block")
expect(QuietInsight.agent(materialTitle: "利率资料", answer: "   \n") == nil, "empty agent insight is ignored")
let markdownNoiseInsight = QuietInsight.make(
    materialTitle: "Markdown 验收",
    materialText: """
    ![image](missing.png)
    | 能力 | 状态 |
    | --- | --- |
    - [ ] todo
    删除线、重点高亮、货币理论、新概念笔记。
    """,
    noteText: "",
    selectionText: nil
)
expect(!markdownNoiseInsight.body.contains("[image]"), "quiet insight ignores markdown image syntax")
expect(markdownNoiseInsight.body.contains("货币理论"), "quiet insight keeps readable markdown prose")

expect(PageNavigator.previous(0) == 0, "pdf previous clamps first page")
expect(PageNavigator.next(0, pageCount: 2) == 1, "pdf next advances")
expect(PageNavigator.next(1, pageCount: 2) == 1, "pdf next clamps last page")
expect(PageNavigator.display(0, pageCount: 0) == "1 / 1", "pdf display empty")
expect(ReaderSearch.cleaned("  利率\n") == "利率", "reader search trims query")
expect(ReaderSearch.firstMatch(in: "实际利率与名义利率", query: "名义")?.location == 5, "reader search finds first match")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: "money")?.location == 0, "reader search ignores case")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: " ") == nil, "reader search ignores empty query")
let pdfSourceReference = SourceReferenceTitle.parse("> 来源：Mishkin 教材样例，第 3 页")
expect(pdfSourceReference.title == "Mishkin 教材样例" && pdfSourceReference.pageIndex == 2, "source reference parses pdf page")
let calloutSourceReference = SourceReferenceTitle.parse("""
> [!quote] 选区摘录
> 实际利率
>
> 来源：Mishkin 教材样例，第 12 页
""")
expect(calloutSourceReference.title == "Mishkin 教材样例" && calloutSourceReference.pageIndex == 11, "source reference parses quote callout")
expect(WikiLink.targetTitle(from: "  货币理论 | 显示名 ") == "货币理论", "wikilink alias keeps target title")
expect(WikiLink.targetTitle(from: "  货币理论 ") == "货币理论", "wikilink plain title")
expect(WikiLink.targetTitle(from: "货币理论#利率") == "货币理论", "wikilink heading target opens note title")
expect(WikiLink.targetTitle(from: "货币理论#^rate-block") == "货币理论", "wikilink block target opens note title")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论|Money]] 继续写", cursor: 6) == "货币理论", "wikilink title at cursor")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论#利率]] 继续写", cursor: 8) == "货币理论", "wikilink heading title at cursor")
expect(WikiLink.enclosingTitle(in: "没有双链", cursor: 2) == nil, "wikilink title ignores plain text")
expect(WorkspaceLayout.documentAgentNotes.hasCollapsibleRightPane, "three-pane layout can collapse right pane")
expect(WorkspaceLayout.documentNotesSplit.hasCollapsibleRightPane, "split layout can collapse right pane")
expect(!WorkspaceLayout.immersiveReading.hasCollapsibleRightPane, "immersive reading has no right pane to collapse")
expect(WorkspaceLayout.documentAgentNotes.label == "阅读-对话-笔记"
    && WorkspaceLayout.documentNotesAgent.label == "阅读-笔记-对话"
    && WorkspaceLayout.documentNotesSplit.label == "阅读/笔记对半", "layout labels use task language instead of internal pane names")
expect(WorkspaceLayout.immersiveConversation.systemImage == "bubble.left.and.text.bubble.right" && WorkspaceLayout.immersiveWriting.systemImage == "square.and.pencil", "immersive layouts expose semantic menu icons")
let contentViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ContentView.swift")
let contentViewSource = (try? String(contentsOf: contentViewSourceURL, encoding: .utf8)) ?? ""
expect(!contentViewSource.isEmpty, "content view source is readable")
let themeSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/Theme.swift")
let themeSource = (try? String(contentsOf: themeSourceURL, encoding: .utf8)) ?? ""
expect(themeSource.contains(".fill(.regularMaterial)") && themeSource.contains("paperWashOpacity"), "header glass uses one shared paper material wash")
expect(themeSource.contains("WeiBeiTheme.glassTint.opacity(0.16 * opacity)") && !themeSource.contains("WeiBeiTheme.paperInset.opacity(0.10 * opacity)"), "header handoff fade avoids a hard paper edge")
expect(themeSource.contains("paperRaised.opacity(0.985)")
    && themeSource.contains(".opacity(0.015)")
    && !themeSource.contains("paperRaised.opacity(0.92)"), "floating panels stay readable without losing the light glass surface")
expect(
    themeSource.contains("func weibeiInputPrompt")
        && themeSource.contains("weight: Font.Weight = .regular")
        && themeSource.contains("Text(text)")
        && themeSource.contains(".foregroundStyle(WeiBeiTheme.secondaryInk.opacity(0.84))")
        && !themeSource.contains(".foregroundStyle(WeiBeiTheme.secondaryInk.opacity(0.72))")
        && themeSource.contains(".allowsHitTesting(false)")
        && themeSource.contains("fontSize: CGFloat = 13")
        && themeSource.contains(".zIndex(2)")
        && !themeSource.contains(".foregroundColor(.white)")
        && !themeSource.contains(".foregroundStyle(.white)")
        && !themeSource.contains("NSViewRepresentable")
        && !themeSource.contains("NSColor("),
    "input placeholders use a shared SwiftUI semantic ink overlay without white vibrancy or AppKit drawing"
)
expect(themeSource.contains("func weibeiInputSurface")
    && themeSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && themeSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
    && themeSource.contains(".tint(WeiBeiTheme.link)")
    && themeSource.contains(".fill(WeiBeiTheme.paperRaised.opacity(active ? 0.66 : 0.60))")
    && themeSource.contains(".stroke(WeiBeiTheme.glassHighlight.opacity(active ? 0.34 : 0.24), lineWidth: 1)")
    && themeSource.contains(".stroke(WeiBeiTheme.paperInset.opacity(active ? 0.30 : 0.38), lineWidth: 1)")
    && themeSource.contains(".stroke(active ? WeiBeiTheme.link.opacity(0.34) : WeiBeiTheme.hairline.opacity(0.54), lineWidth: 1)")
    && !themeSource.contains(".environment(\\.colorScheme, .light)"), "input surfaces force readable text color without locking the control color scheme")
expect(themeSource.contains("tertiaryInk.opacity(0.58)") && themeSource.contains("tertiaryInk.opacity(0.60)"), "disabled button text remains legible on light paper surfaces")
expect(contentViewSource.contains("ResizableTwoPane<First: View, Second: View>: NSViewRepresentable"), "two-pane layout uses native bridge")
expect(contentViewSource.contains("ResizableThreePane<First: View, Second: View, Third: View>: NSViewRepresentable"), "three-pane layout uses native bridge")
expect(contentViewSource.contains("WeiBeiSplitView: NSSplitView"), "content panes use native split view")
expect(contentViewSource.contains("alpha: 0.26"), "native split divider keeps a visible but quiet WeiBei hairline")
expect(contentViewSource.contains("override func layout()"), "native split applies saved positions after first real layout")
expect(contentViewSource.contains("libraryResizeHandle"), "library pane keeps SwiftUI resize handle")
expect(contentViewSource.contains("minimumContentWidthWithLibrary"), "library leaves readable width for the workspace")
expect(contentViewSource.contains("normalSidePaneMinimum"), "normal three-pane layout relaxes side panes when library is open")
expect(!contentViewSource.contains("DragGesture()"), "content panes avoid SwiftUI drag resizing")
expect(!contentViewSource.contains(".id(store.layout)"), "layout changes avoid whole-screen identity resets")
expect(!contentViewSource.contains("PaneSeparator"), "content panes avoid hand-drawn split separators")
expect(contentViewSource.components(separatedBy: ".transition(WeiBeiTransition.rightPanel)").count >= 5
    && contentViewSource.components(separatedBy: ".transition(WeiBeiTransition.layout)").count >= 3, "right-pane visibility changes use shared transitions instead of naked tree swaps")
expect(!contentViewSource.contains("topBarContentFade"), "top bar avoids a duplicate content fade wash")
expect(contentViewSource.contains("store.toggleLibrary()")
    && contentViewSource.contains("sidebar.left")
    && contentViewSource.contains("WeiBeiIconButtonStyle(active: store.showLibrary)")
    && contentViewSource.contains("store.showLibrary ? \"收起资料库\" : \"打开资料库\"")
    && !contentViewSource.contains("恢复资料库")
    && !contentViewSource.contains(".opacity(isImmersiveLayout ? 0.45 : 1)"), "immersive top bar keeps a clear stateful library chooser instead of dimming a live control")
expect(contentViewSource.contains("WeiBeiHeaderHandoffFade(height: 18, opacity: isImmersiveLayout ? 0.42 : 0.34)")
    && contentViewSource.contains("paperOpacity: backgroundPaperOpacity - (isImmersiveLayout ? 0.06 : 0)")
    && contentViewSource.contains("materialOpacity: backgroundMaterialOpacity + (isImmersiveLayout ? 0.03 : 0)"), "immersive top bar keeps the same variants while using a lighter glass handoff")
expect(!contentViewSource.contains("文代笔") && !contentViewSource.contains("Agent中") && contentViewSource.contains("对话中栏") && contentViewSource.contains("对话右栏"), "top bar short layout labels avoid cryptic abbreviations")
for helperName in ["openReader", "openWriting", "openLibrary", "askCurrentSelection", "prepareAgentDraft"] {
    if let helperStart = contentViewSource.range(of: "private func \(helperName)")?.lowerBound,
       let helperEnd = contentViewSource[helperStart...].range(of: "\n    }\n")?.upperBound {
        let helperSource = String(contentViewSource[helperStart..<helperEnd])
        expect(!helperSource.contains("showLibrary = false"), "\(helperName) keeps a user-opened immersive library visible")
        expect(!helperSource.contains("store.layout =") && !helperSource.contains("store.showRightPane = true") && !helperSource.contains("store.showLibrary = true"), "\(helperName) routes durable layout changes through WorkspaceStore helpers")
    } else {
        expect(false, "\(helperName) source is readable")
    }
}
expect(contentViewSource.contains(".weibeiInputSurface(active: searchFocused.wrappedValue, height: controlHeight)")
    && contentViewSource.contains(".weibeiInputPrompt(\"资料内搜索\", visible: store.readerSearch.isEmpty, fontSize: 12)")
    && contentViewSource.contains("topIconButton(\"magnifyingglass\", help: \"打开资料内搜索\")")
    && contentViewSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && contentViewSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
    && !contentViewSource.contains(".foregroundColor(primaryText)\n                    .foregroundStyle(primaryText)\n                    .tint(WeiBeiTheme.link)"), "top search uses fixed ink on its paper input surface instead of inheriting top bar chrome text")
expect(contentViewSource.contains("case .compact, .glyph:\n            return 28"), "compact top bar controls keep a readable 28-point height")
expect(contentViewSource.contains("private var hasReaderScopedTopActions: Bool")
    && contentViewSource.contains("case .immersiveConversation, .immersiveWriting:")
    && contentViewSource.contains("store.hasSelectedMaterial && hasReaderScopedTopActions")
    && contentViewSource.contains("store.canCopyReference && hasReaderScopedTopActions"), "top material search and reference actions stay scoped to reader-first layouts")
expect(contentViewSource.contains("if shouldShowSearchAction && !store.showReaderSearch"), "top bar hides the search icon while the search field is already open")
expect(contentViewSource.contains("variant == .glyph || variant == .compact ? shortLayoutLabel : store.layout.label"), "compact top bar uses short layout labels")
expect(contentViewSource.contains("layout == store.layout ? \"checkmark\"") && contentViewSource.contains(".accessibilityLabel(Text(\"切换布局\"))"), "layout menu marks current layout and explains itself")
expect(contentViewSource.contains(": layout.systemImage") && !contentViewSource.contains(": \"rectangle.split.3x1\""), "layout menu avoids repeating one generic icon")
expect(contentViewSource.contains(".accessibilityLabel(Text(\"更多设置\"))"), "top bar more menu has a readable semantic label")
expect(contentViewSource.contains("return \"打开对话\"")
    && contentViewSource.contains("return \"问选区\"")
    && contentViewSource.contains("store.hasSelectedMaterial ? \"问资料\" : \"问笔记\"")
    && contentViewSource.contains("return \"打开对话区\"")
    && contentViewSource.contains("return \"按当前选区提问\"")
    && contentViewSource.contains("按当前资料提问")
    && contentViewSource.contains("按当前笔记提问")
    && contentViewSource.contains("Section(\"对话入口\")")
    && !contentViewSource.contains("Section(\"Agent 入口\")")
    && !contentViewSource.contains("打开 Agent 对话区"), "top bar names conversation entry by the actual action instead of a generic agent label")
expect(themeSource.contains("return \"标准\"")
    && themeSource.contains("return \"紧凑\"")
    && themeSource.contains("return \"图标\"")
    && !themeSource.contains("甲 纸脊")
    && !themeSource.contains("乙 窄栏")
    && !themeSource.contains("丁 图形"), "top bar variants use user-facing style names instead of internal prototypes")
let sidebarSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/SidebarView.swift")
let sidebarSource = (try? String(contentsOf: sidebarSourceURL, encoding: .utf8)) ?? ""
expect(sidebarSource.contains(".weibeiInputPrompt(\"搜索资料库\", visible: store.librarySearch.isEmpty, fontSize: 13)") && sidebarSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "library search placeholder uses the shared readable overlay above the field")
let notesAgentSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/NotesAgentView.swift")
let notesAgentSource = (try? String(contentsOf: notesAgentSourceURL, encoding: .utf8)) ?? ""
expect(notesAgentSource.contains(".weibeiInputPrompt(agentPrompt, visible: store.agentDraft.isEmpty, fontSize: 14)"), "agent tray placeholder uses readable non-vibrant prompt text")
expect(notesAgentSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)")
    && !notesAgentSource.contains("SelectionAnchorCoordinate.y(")
    && !notesAgentSource.contains("contentView.convert("), "note source editor selection anchors use the shared coordinate helper")
expect(!sidebarSource.contains("commandPalettePresented.toggle()") && !sidebarSource.contains("Label(\"命令\", systemImage: \"command\")"), "sidebar does not duplicate the command palette entry")
expect(sidebarSource.contains("sidebarSection(title: \"导入资料\", items: importedMaterialItems)") && sidebarSource.contains("sidebarSection(title: \"笔记\", items: notebookItems)"), "sidebar separates materials from notebook notes")
expect(sidebarSource.contains("!$0.isSample && !$0.isNotebookNote") && sidebarSource.contains("store.filteredItems.filter(\\.isNotebookNote)"), "sidebar material list excludes notebook notes without hiding notes")
expect(contentViewSource.contains("topIconButton(\"command\", help: \"命令面板\")"), "top bar keeps the command palette entry")
let commandPaletteSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/CommandPaletteView.swift")
let commandPaletteSource = (try? String(contentsOf: commandPaletteSourceURL, encoding: .utf8)) ?? ""
expect(commandPaletteSource.contains(".weibeiInputSurface(active: searchFocused, height: 36)")
    && commandPaletteSource.contains(".weibeiInputPrompt(\"输入命令\", visible: query.isEmpty")
    && commandPaletteSource.contains("WeiBeiTheme.hairline.opacity(0.72)")
    && !commandPaletteSource.contains("Divider()"), "command palette search uses WeiBei input surface and semantic hairline")
expect(commandPaletteSource.contains("withAnimation(command.animation)") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "command palette uses layout motion for layout commands")
expect(commandPaletteSource.contains("PaletteCommand(title: \"聚焦对话\", shortcut: \"⌘4\"")
    && !commandPaletteSource.contains("PaletteCommand(title: \"聚焦 Agent\""), "command palette names the conversation pane by task language")
expect(!commandPaletteSource.contains("收起右栏"), "command palette avoids fixed right-pane wording")
expect(!commandPaletteSource.contains("Agent 整理资料与笔记") && !commandPaletteSource.contains("本地排序资料库"), "command palette avoids half-built library organization shortcuts")
expect(commandPaletteSource.contains("store.showLibrary ? \"收起资料库\" : \"打开资料库\"")
    && !commandPaletteSource.contains("恢复资料"), "command palette names the library toggle as an explicit library action")
expect(!commandPaletteSource.contains("PaletteCommand(title: \"顶栏") && contentViewSource.contains("Section(\"顶部栏\")"), "top bar variants live in the more menu instead of the command palette")
expect(commandPaletteSource.contains("private var rightPaneCommand: PaletteCommand?") && commandPaletteSource.contains("store.layout.hasCollapsibleRightPane"), "command palette hides right pane command when the layout has no auxiliary pane")
expect(commandPaletteSource.contains("收起辅助栏") && commandPaletteSource.contains("展开辅助栏"), "command palette names auxiliary pane action by current state")
expect(commandPaletteSource.contains("title: store.showRightPane ? \"收起辅助栏\" : \"展开辅助栏\",\n            shortcut: \"⌘J\",\n            animation: WeiBeiMotion.layout"), "command palette auxiliary pane command uses layout motion")
expect(commandPaletteSource.contains("if store.canCopyReference")
    && commandPaletteSource.contains("PaletteCommand(title: store.copyReferenceActionTitle")
    && commandPaletteSource.contains("if store.hasSelectedMaterial")
    && commandPaletteSource.contains("PaletteCommand(title: \"打开资料内搜索\""), "command palette names copy-reference by the actual current target")
expect(appSource.contains("Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }")
    && contentViewSource.contains("topIconButton(\"quote.opening\", help: store.copyReferenceActionTitle)"), "top bar and app menu share the same copy-reference wording")
expect(commandPaletteSource.contains("private var canSendAgentDraft: Bool") && commandPaletteSource.contains("PaletteCommand(title: store.sendAgentActionTitle"), "command palette hides the agent send command until a draft exists")
expect(commandPaletteSource.contains("if store.canApplyAgentAnswer") && commandPaletteSource.contains("if store.canReplaceNoteSelection") && commandPaletteSource.contains("PaletteCommand(title: \"替换笔记选区\""), "command palette hides agent answer actions until they can work")
expect(commandPaletteSource.contains("if store.selectionContext != nil")
    && commandPaletteSource.contains("PaletteCommand(title: \"问当前选区\"")
    && commandPaletteSource.contains("Task { await store.askAgent() }"), "command palette selection action sends the selection question instead of only preparing a draft")
expect(commandPaletteSource.contains("if store.canOpenSelectedSourceReference") && commandPaletteSource.contains("PaletteCommand(title: \"打开选区来源\""), "command palette exposes source jump only for parseable note references")
expect(commandPaletteSource.contains("if store.canUseSelectionAgentSurface") && commandPaletteSource.contains("items.insert(agentSurfaceCommand(.selectionFloat, shortcut: \"⌃⌥3\")"), "command palette only exposes selection-float mode when an anchored selection exists")
expect(commandPaletteSource.contains("private func agentSurfaceCommand(_ surface: AgentSurface, shortcut: String)")
    && commandPaletteSource.contains("surface.actionLabel")
    && !commandPaletteSource.contains("Agent 底部抽屉")
    && !commandPaletteSource.contains("Agent 右下角小窗")
    && !commandPaletteSource.contains("Agent 划线浮层")
    && !commandPaletteSource.contains("Agent 静默洞察"), "command palette uses user-facing agent surface actions instead of internal surface names")
expect(commandPaletteSource.contains("if store.agentSurface != .hidden") && commandPaletteSource.contains("agentSurfaceCommand(.hidden, shortcut: \"⌃⌥0\")"), "command palette hides the agent hide action when already hidden")
let readerViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ReaderView.swift")
let readerViewSource = (try? String(contentsOf: readerViewSourceURL, encoding: .utf8)) ?? ""
let selectionAnchorContentPointSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/SelectionAnchorContentPoint.swift")
let selectionAnchorContentPointSource = (try? String(contentsOf: selectionAnchorContentPointSourceURL, encoding: .utf8)) ?? ""
expect(selectionAnchorContentPointSource.contains("static func fromLocalPoint")
    && selectionAnchorContentPointSource.contains("static func fromWebPoint")
    && selectionAnchorContentPointSource.contains("static func fromScreenPoint")
    && selectionAnchorContentPointSource.contains("SelectionAnchorCoordinate.y"), "selection anchors use one AppKit-to-SwiftUI coordinate helper")
expect(readerViewSource.contains("readerStyleScript"), "html reader injects responsive reading style")
expect(readerViewSource.contains("overflow-wrap: anywhere"), "html reader prevents narrow-pane clipping")
expect(readerViewSource.contains("color-scheme: light") && readerViewSource.contains("color: #1d1814 !important") && readerViewSource.contains("a { color: #31566b !important; }"), "html reader forces readable ink over imported white text")
expect(!readerViewSource.contains("readerHeader") && !readerViewSource.contains("statusBar"), "reader avoids duplicate internal chrome under unified top bar")
expect(readerViewSource.contains("ReaderStateMessage") && !readerViewSource.contains("ContentUnavailableView("), "reader empty states use WeiBei paper styling")
expect(readerViewSource.contains("if store.selectedMaterialItem?.kind == .pdf") && readerViewSource.contains("if let item = store.selectedMaterialItem"), "reader renders materials, not notebook notes")
expect(readerViewSource.contains("NotebookSelectedReaderView") && readerViewSource.contains("阅读区只显示资料"), "reader explains notebook selection instead of rendering it as material")
expect(readerViewSource.contains("ZStack(alignment: .bottomTrailing)")
    && readerViewSource.contains(".padding(.trailing, isImmersive ? 18 : 10)")
    && readerViewSource.contains(".padding(.bottom, isImmersive ? 18 : 12)")
    && readerViewSource.contains("pdfFloatingControls")
    && !readerViewSource.contains("ZStack(alignment: .bottomLeading)")
    && !readerViewSource.contains("ZStack(alignment: .trailing)"), "pdf controls sit on the bottom-right page edge instead of covering the reading start")
expect(readerViewSource.contains("pdfControlsHovering")
    && readerViewSource.contains("WeiBeiTheme.paperRaised.opacity(pdfControlsHovering ? 0.88 : 0.78)")
    && readerViewSource.contains(".opacity(pdfControlsHovering || pdfBrowseMode == .page ? 0.94 : 0.64)")
    && readerViewSource.contains(".offset(x: pdfControlsHovering || pdfBrowseMode == .page ? 0 : 3)")
    && readerViewSource.contains(".scaleEffect(pdfControlsHovering ? 1.01 : 1, anchor: .trailing)")
    && readerViewSource.contains(".onHover"), "pdf controls stay low-distraction as a right-edge rail until the pointer approaches")
expect(readerViewSource.contains("case .scroll: \"滚动\"")
    && readerViewSource.contains("case .page: \"翻页\"")
    && readerViewSource.contains("case .scroll: \"arrow.up.and.down\"")
    && readerViewSource.contains("case .page: \"rectangle.portrait\"")
    && readerViewSource.contains("private var pdfModeToggle: some View")
    && readerViewSource.contains("pdfBrowseMode = pdfBrowseMode.toggled")
    && readerViewSource.contains("Image(systemName: pdfBrowseMode.systemImage)")
    && readerViewSource.contains(".frame(width: 24, height: 24)")
    && readerViewSource.contains(".accessibilityLabel(Text(\"切换 PDF 浏览方式，当前\\(pdfBrowseMode.label)\"))")
    && !readerViewSource.contains("ForEach(PDFBrowseMode.allCases)")
    && !readerViewSource.contains("Button(mode.label)")
    && !readerViewSource.contains("Text(pdfBrowseMode.label)")
    && !readerViewSource.contains("case .scroll: \"连续\""), "pdf mode control uses one compact readable toggle instead of a bulky two-choice segment")
expect(readerViewSource.contains(".accessibilityLabel(Text(\"上一页\"))") && readerViewSource.contains(".accessibilityLabel(Text(\"下一页\"))"), "pdf page controls have readable icon labels")
expect(!readerViewSource.contains(".disabled(pdfPageIndex"), "pdf pager keeps arrows visible instead of showing grey dead buttons")
expect(readerViewSource.contains("syncReaderLocationTitle") && readerViewSource.contains("第 \\(pdfPageIndex + 1) 页"), "pdf reader page updates feed the shared reference title")
expect(readerViewSource.contains("var onSelectionChange: (String, CGPoint?, Int) -> Void") && readerViewSource.contains("pageIndex(for: selection, in: view)") && readerViewSource.contains("ownerTitle: ownerTitle"), "pdf selection source uses the selected page, not only the current page")
expect(readerViewSource.contains("SelectionAnchorContentPoint.fromLocalPoint(localPoint, in: view)")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)")
    && !readerViewSource.contains("SelectionAnchorCoordinate.y(")
    && !readerViewSource.contains("contentView.convert("), "reader selection anchors route PDF, HTML, and text through the shared coordinate helper")
expect(readerViewSource.contains("pendingPDFPageIndex") && readerViewSource.contains("applyPendingPDFPageIfReady") && readerViewSource.contains("store.readerTargetPageIndex = nil"), "pdf reader consumes source-jump target pages")
expect(readerViewSource.contains("onSourceReference: { reference in store.openSourceReference(reference) }"), "markdown reader source references can jump back to material")
let richEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/RichMarkdownEditorView.swift")
let richEditorSource = (try? String(contentsOf: richEditorSourceURL, encoding: .utf8)) ?? ""
expect(richEditorSource.contains("SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)")
    && !richEditorSource.contains("SelectionAnchorCoordinate.y(")
    && !richEditorSource.contains("contentView.convert("), "rich markdown editor selection anchors use the shared coordinate helper")
expect(richEditorSource.contains("var documentID = \"\"") && richEditorSource.contains("var pendingExternalMarkdown: String?"), "rich editor tracks document identity and pending external sync")
expect(
    richEditorSource.contains("window.weiBeiDocumentID")
        && richEditorSource.contains("func setDocumentID(_ id: String)")
        && richEditorSource.contains("guard messageMatchesDocument(message.body) else { return }"),
    "rich editor rejects stale web callbacks from a previous document"
)
expect(richEditorSource.contains("guard text == pendingExternalMarkdown else { return }"), "rich editor ignores stale markdown callbacks during document sync")
expect(richEditorSource.contains("command && shift && !option && !control") && richEditorSource.contains("[\"a\", \"r\", \"e\", \"c\"].includes(key)"), "rich editor forwards command-shift agent shortcuts to Swift")
expect(richEditorSource.contains("runPendingCommandIfReady()")
    && richEditorSource.contains("guard isReady,")
    && richEditorSource.contains("self.command.wrappedValue = nil"), "rich editor does not drop commands before the web editor is ready")
let webEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/WebEditor/src/editor.js")
let webEditorSource = (try? String(contentsOf: webEditorSourceURL, encoding: .utf8)) ?? ""
expect(!webEditorSource.contains("event.metaKey && event.shiftKey && event.key.toLowerCase() === 'a'"), "web editor does not steal command-shift-a from Swift agent write action")
expect(webEditorSource.contains("const insertionCursorMarker = '{{WEIBEI_CURSOR}}'")
    && webEditorSource.contains("insertionSelectionStartMarker")
    && webEditorSource.contains("placeCursorAtInsertionMarker()"), "web editor removes command snippet cursor markers after insertion")
expect(webEditorSource.contains("let currentDocumentID = window.weiBeiDocumentID || ''")
    && webEditorSource.contains("postMessage({ ...body, documentID: currentDocumentID })")
    && webEditorSource.contains("setDocumentID: (next) =>"), "web editor tags bridge messages with the current document identity")
let appSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/App/WeiBeiApp.swift")
let appSource = (try? String(contentsOf: appSourceURL, encoding: .utf8)) ?? ""
expect(appSource.contains("window.isOpaque = true"), "main window declares opaque paper backing for stable capture")
expect(appSource.contains("sharedWorkspaceStore"), "main window and settings share one workspace store")
expect(!appSource.contains("launchProbe"), "app launch path has no temporary probe logging")
expect(appSource.contains("addLocalMonitorForEvents(matching: .keyDown)") && appSource.contains("removeMonitor(shortcutMonitor)"), "app-level shortcuts survive focused web editor")
expect(appSource.contains("applicationShouldHandleReopen") && appSource.contains("return true") && !appSource.contains("return flag"), "reopen creates a main window when no visible window exists")
expect(!appSource.contains("Form {") && appSource.contains("sectionTitle(\"对话设置\")") && appSource.contains(".weibeiInputPrompt(\"OpenAI 密钥\", visible: store.openAIAPIKey.isEmpty, fontSize: 13)") && appSource.contains("SecureField(\"\", text: $store.openAIAPIKey)") && appSource.contains(".foregroundColor(WeiBeiTheme.ink)") && appSource.contains(".weibeiInputSurface(active: focusedField == .apiKey)"), "settings key input uses WeiBei input surface instead of the default form field")
expect(appSource.contains("WeiBeiTextActionButtonStyle(active: true)") && appSource.contains(".background(WeiBeiTheme.paper)"), "settings view uses WeiBei paper and button styles")
let workspaceStoreSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Stores/WorkspaceStore.swift")
let workspaceStoreSource = (try? String(contentsOf: workspaceStoreSourceURL, encoding: .utf8)) ?? ""
expect(
    workspaceStoreSource.contains("shortcutKey(from event: NSEvent)")
        && workspaceStoreSource.contains("case 0: return \"a\"")
        && workspaceStoreSource.contains("case 18: return \"1\"")
        && workspaceStoreSource.contains("case 125: return \"down\""),
    "app shortcuts normalize hardware keys"
)
expect(workspaceStoreSource.contains("animateLayoutChange") && workspaceStoreSource.contains("withAnimation(WeiBeiMotion.layout)"), "app shortcut layout changes stay animated")
expect(workspaceStoreSource.contains("animatePanelChange") && workspaceStoreSource.contains("withAnimation(WeiBeiMotion.panel)"), "app shortcut panel changes stay animated")
expect(workspaceStoreSource.contains("if modifiers == [.command, .shift]") && workspaceStoreSource.contains("applyLastAgentAnswerToNote()") && workspaceStoreSource.contains("replaceSelectionWithLastAgentAnswer()") && workspaceStoreSource.contains("applyAgentPatchToEditor()"), "app shortcut handler owns command-shift agent write actions")
expect(workspaceStoreSource.contains("case \"a\":\n                guard canApplyAgentAnswer else { return false }\n                animatePanelChange { applyLastAgentAnswerToNote() }")
    && workspaceStoreSource.contains("case \"r\":\n                guard canReplaceNoteSelection else { return false }\n                animatePanelChange { replaceSelectionWithLastAgentAnswer() }")
    && workspaceStoreSource.contains("case \"e\":\n                guard canApplyAgentAnswer else { return false }\n                animatePanelChange { applyAgentPatchToEditor() }"), "agent write shortcuts do not swallow unavailable actions")
expect(workspaceStoreSource.contains("case \"j\":\n                guard layout.hasCollapsibleRightPane else { return false }\n                animateLayoutChange { toggleRightPane() }"), "right-pane shortcut does not swallow unavailable layouts")
expect(workspaceStoreSource.contains("var canCopyReference: Bool")
    && workspaceStoreSource.contains("var copyReferenceActionTitle: String")
    && workspaceStoreSource.contains("if selectionContext != nil { return \"复制选区引用\" }")
    && workspaceStoreSource.contains("if hasSelectedMaterial { return \"复制资料引用\" }")
    && workspaceStoreSource.contains("guard canCopyReference else { return false }")
    && workspaceStoreSource.contains("guard hasSelectedMaterial else { return false }"), "app shortcuts and menus name copy-reference by the actual current target")
expect(workspaceStoreSource.contains("selectAdjacentItem(step: -1)") && workspaceStoreSource.contains("Task { await askAgent() }"), "app shortcut handler covers navigation and agent send")
expect(workspaceStoreSource.contains("case \"return\":\n                guard !isAskingAgent && !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }\n                Task { await askAgent() }"), "app shortcut does not swallow command-return when there is no sendable agent draft")
expect(workspaceStoreSource.contains("showQuietInsight = agentSurface == .quietInsight") && !workspaceStoreSource.contains("agentSurface = .quietInsight\n            showQuietInsight = true"), "immersive reading preserves the chosen agent surface")
expect(workspaceStoreSource.contains("func updateNote(_ value: String, for itemID: String?)") && workspaceStoreSource.contains("guard itemID == selectedItemID else { return }"), "note writes are bound to the current selected item")
expect(workspaceStoreSource.contains("@Published var readerLocationTitle") && workspaceStoreSource.contains("var currentReferenceTitle"), "store tracks the current reader reference title")
expect(workspaceStoreSource.contains("@Published var readerTargetPageIndex") && workspaceStoreSource.contains("func openSourceReference") && workspaceStoreSource.contains("SourceReferenceTitle.parse"), "store can jump from source reference text to the referenced material")
expect(workspaceStoreSource.contains("ownerTitle: String? = nil") && workspaceStoreSource.contains("let resolvedOwnerTitle"), "selection updates can carry a precise reader source title")
expect(workspaceStoreSource.contains("withAnimation(WeiBeiMotion.panel) {\n            selectionContext = SelectionContext")
    && workspaceStoreSource.contains("agentSurface = .selectionFloat\n            showQuietInsight = false"), "selection updates reveal the floating agent through the shared panel animation")
expect(workspaceStoreSource.contains("func askSelection()") && workspaceStoreSource.components(separatedBy: "withAnimation(WeiBeiMotion.panel) {").count >= 3, "selection and agent entry paths use shared panel motion")
expect(workspaceStoreSource.contains("sourceTitle: selectionContext.ownerTitle") && workspaceStoreSource.contains("来源：\\(currentReferenceTitle)"), "copy reference uses real selection or current reader source")
expect(workspaceStoreSource.contains("private func quotedReferenceBlock") && workspaceStoreSource.contains("> [!quote] 选区摘录") && !workspaceStoreSource.contains("## 选区摘录"), "selection excerpts use the shared quote callout format")
expect(workspaceStoreSource.contains("selectionOwnerTitle(for source: SelectionSource)") && workspaceStoreSource.contains("selectedItem?.isNotebookNote == true"), "selection fallback title treats notebook notes as notes")
expect(workspaceStoreSource.contains("var selectedMaterialItem") && workspaceStoreSource.contains("!item.isNotebookNote"), "selected material excludes notebook notes")
expect(workspaceStoreSource.contains("var navigableItems") && workspaceStoreSource.contains("let materialItems = allItems.filter { !$0.isNotebookNote }"), "material navigation skips notebook notes")
expect(
    workspaceStoreSource.contains("guard hasSelectedMaterial else")
        && workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("if layout == .immersiveConversation || layout == .immersiveWriting")
        && workspaceStoreSource.contains("setLayout(.immersiveReading)"),
    "reader search reveal refuses notebook-only context and moves to a visible reader layout"
)
expect(
    workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("guard !hasSelectedMaterial else { return }")
        && workspaceStoreSource.contains("showReaderSearch = false")
        && workspaceStoreSource.contains("readerSearch = \"\""),
    "material search state clears when selection no longer points to a material"
)
if let hideReaderSearchStart = workspaceStoreSource.range(of: "func hideReaderSearch()")?.lowerBound,
   let updateReaderLocationStart = workspaceStoreSource.range(of: "func updateReaderLocationTitle")?.lowerBound {
    let hideReaderSearchSource = String(workspaceStoreSource[hideReaderSearchStart..<updateReaderLocationStart])
    expect(hideReaderSearchSource.contains("clearUnpinnedFloatingSelection(keepContext: false)") && !hideReaderSearchSource.contains("selectionContext = nil"), "reader search dismissal preserves pinned selection agents through the shared clear helper")
} else {
    expect(false, "reader search dismissal source is readable")
}
expect(workspaceStoreSource.contains("var selectedMaterialTitle") && workspaceStoreSource.contains("selectedMaterialItem?.title ?? \"未选择材料\""), "agent material title does not invent a current material")
expect(workspaceStoreSource.contains("var agentMessageSourceTitle: String?") && workspaceStoreSource.contains("selectedMaterialItem?.title ?? selectedItem?.title") && !workspaceStoreSource.contains("source: selectedMaterialItem?.title"), "agent message source falls back to the selected note title")
expect(workspaceStoreSource.contains("private var quietInsightReferenceTitle: String") && workspaceStoreSource.contains("selectionContext?.ownerTitle ?? selectedMaterialItem?.title ?? selectedItem?.title") && workspaceStoreSource.contains("没有证据就说\\(evidenceText)"), "quiet insight uses real note or material source wording")
expect(workspaceStoreSource.contains("private func clearUnpinnedFloatingSelection(keepContext: Bool = true)") && workspaceStoreSource.contains("guard !pinnedFloatingAgent else { return }") && workspaceStoreSource.contains("if agentSurface == .selectionFloat"), "workspace changes clear stale unpinned selection anchors through one helper")
expect(workspaceStoreSource.contains("guard cleaned.count >= 2 else {\n            clearUnpinnedFloatingSelection(keepContext: false)\n            return\n        }"), "short or cleared selections remove stale unpinned selection floats")
expect(workspaceStoreSource.contains("let itemChanged = selectedItemID != itemID") && workspaceStoreSource.contains("clearUnpinnedFloatingSelection(keepContext: false)"), "selecting a different item clears the old selection context")
expect(workspaceStoreSource.contains("func toggleLibrary() {\n        showLibrary.toggle()\n        clearUnpinnedFloatingSelection()") && workspaceStoreSource.contains("func toggleRightPane() {\n        guard layout.hasCollapsibleRightPane else { return }\n        showRightPane.toggle()\n        clearUnpinnedFloatingSelection()"), "pane visibility changes invalidate stale floating selection anchors")
expect(workspaceStoreSource.contains("focus(showRightPane ? rightPaneRevealFocus : .reader)")
    && workspaceStoreSource.contains("private var rightPaneRevealFocus: PaneFocus")
    && workspaceStoreSource.contains("case .documentNotesAgent, .immersiveConversation:\n            .agent"), "right-pane reveal focuses the visible agent pane when the right pane is Agent")
expect(workspaceStoreSource.contains("func revealLibrary()")
    && workspaceStoreSource.contains("if !showLibrary {\n            clearUnpinnedFloatingSelection()\n        }")
    && workspaceStoreSource.contains("focus(.library)\n        save()"), "library reveal uses the shared durable state path")
expect(workspaceStoreSource.contains("layout == .immersiveReading || layout == .immersiveWriting") && workspaceStoreSource.contains("agentSurface = .cornerPanel") && !workspaceStoreSource.contains("layout = .immersiveConversation\n                showLibrary = false\n                showRightPane = true"), "agent focus in immersive layouts opens an overlay instead of switching layout")
if let setLayoutStart = workspaceStoreSource.range(of: "func setLayout(_ layout: WorkspaceLayout)")?.lowerBound,
   let setAgentSurfaceStart = workspaceStoreSource.range(of: "func setAgentSurface")?.lowerBound {
    let setLayoutSource = String(workspaceStoreSource[setLayoutStart..<setAgentSurfaceStart])
    expect(!setLayoutSource.contains("showLibrary = false"), "layout switching preserves the current library visibility")
    expect(!setLayoutSource.contains("showRightPane = true"), "layout switching preserves a user-collapsed auxiliary pane")
    expect(setLayoutSource.contains("clearUnpinnedFloatingSelection()"), "layout switching invalidates stale floating selection anchors")
} else {
    expect(false, "layout switching source is readable")
}
if let agentFocusStart = workspaceStoreSource.range(of: "if pane == .agent")?.lowerBound,
   let focusEnd = workspaceStoreSource.range(of: "focusedPane = pane")?.lowerBound {
    let agentFocusSource = String(workspaceStoreSource[agentFocusStart..<focusEnd])
    expect(!agentFocusSource.contains("showLibrary = false"), "agent focus does not close a user-opened immersive library")
} else {
    expect(false, "agent focus source is readable")
}
if let insertStart = workspaceStoreSource.range(of: "func insertMarkdownSnippet")?.lowerBound,
   let insertEnd = workspaceStoreSource[insertStart...].range(of: "\n    }\n")?.upperBound {
    let insertSource = String(workspaceStoreSource[insertStart..<insertEnd])
    expect(!insertSource.contains("showLibrary = false"), "markdown insertion keeps a user-opened immersive library visible")
} else {
    expect(false, "markdown insertion source is readable")
}
if let setNoteModeStart = workspaceStoreSource.range(of: "func setNoteRenderMode(_ mode: NoteRenderMode)")?.lowerBound,
   let revealStart = workspaceStoreSource.range(of: "private func revealRichWritingSurface")?.lowerBound {
    let setNoteModeSource = String(workspaceStoreSource[setNoteModeStart..<revealStart])
    expect(
        setNoteModeSource.contains("layout = .immersiveWriting")
            && setNoteModeSource.contains("showRightPane = true")
            && setNoteModeSource.contains("noteRenderMode = mode")
            && setNoteModeSource.contains("focus(.notes)"),
        "note render mode commands reveal and focus the writing surface"
    )
} else {
    expect(false, "note render mode source is readable")
}
expect(workspaceStoreSource.contains("var canUseSelectionAgentSurface: Bool")
    && workspaceStoreSource.contains("var visibleAgentSurfaces: [AgentSurface]")
    && workspaceStoreSource.contains("guard surface != .selectionFloat || canUseSelectionAgentSurface else { return }")
    && workspaceStoreSource.contains("case \"3\":\n                guard canUseSelectionAgentSurface else { return false }")
    && workspaceStoreSource.contains("self.agentSurface = agentSurface == .selectionFloat ? .hidden : agentSurface")
    && workspaceStoreSource.contains("agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface"), "selection-float agent surface is hidden, rejected, and never restored as durable workspace chrome")
expect(!workspaceStoreSource.contains("selectedItem?.title ?? \"当前材料\"") && !workspaceStoreSource.contains("保存后 Agent 会用当前材料") && !workspaceStoreSource.contains("已选择材料、当前选区和右侧笔记"), "agent context avoids fake material fallback copy")
expect(workspaceStoreSource.contains("var agentPromptScope") && workspaceStoreSource.contains("var selectionPromptScope") && !workspaceStoreSource.contains("var libraryOrganizationScope"), "agent prompt builders avoid half-built library organization context")
expect(!workspaceStoreSource.contains("请根据当前文档和当前笔记") && !workspaceStoreSource.contains("请根据当前材料和当前笔记") && !workspaceStoreSource.contains("结合当前文档和笔记"), "agent draft presets do not hardcode fake material context")
expect(workspaceStoreSource.contains("func resetNote()") && workspaceStoreSource.contains("createNotebookNote()") && !workspaceStoreSource.contains("updateNote(defaultNote(for: selectedItem))"), "new note command creates a notebook note instead of overwriting the current material note")
expect(workspaceStoreSource.contains("isNotebookNote: true") && workspaceStoreSource.contains("nextNotebookNoteURL") && workspaceStoreSource.contains("try defaultNote(for: item).write"), "new notebook notes are backed by local markdown files")
expect(workspaceStoreSource.contains("importedItems.append(item)\n            revealRichWritingSurface()\n            select(itemID: item.id)"), "new notebook notes reveal the rich writing surface")
expect(workspaceStoreSource.contains("let title = item?.title ?? \"新笔记\"") && workspaceStoreSource.contains("let excerptSeed = item.map { $0.isNotebookNote ? \"- \" : \"> 来源：\\($0.title)\" } ?? \"- \"") && !workspaceStoreSource.contains("未命名材料"), "standalone note template avoids fake material/source copy")
expect(workspaceStoreSource.contains("已创建双链笔记：\\(url.lastPathComponent)") && !workspaceStoreSource.contains("已创建双链笔记：\\(url.path)") && !workspaceStoreSource.contains("无法创建双链笔记：\\(url.path)"), "wikilink note statuses avoid exposing full local paths")
expect(workspaceStoreSource.contains("private func revealRichWritingSurface()")
    && workspaceStoreSource.contains("layout = .immersiveWriting")
    && workspaceStoreSource.contains("showRightPane = true")
    && workspaceStoreSource.contains("noteRenderMode = .rich"), "writing actions share one rich writing surface reveal")
expect(workspaceStoreSource.contains("func insertMarkdownSnippet(_ markdown: String) {\n        revealRichWritingSurface()")
    && workspaceStoreSource.contains("func useSelectedMarkdownAsNotebookNote()")
    && workspaceStoreSource.contains("revealRichWritingSurface()\n        focus(.notes)"), "markdown insertion and imported markdown notes reveal the rich writing surface")
expect(!workspaceStoreSource.contains("当前页提示"), "quiet insight avoids old page alert title")
expect(workspaceStoreSource.contains("阅读线索"), "quiet insight uses margin-note language")
expect(appSource.contains("if store.canCopyReference") && appSource.contains("if store.hasSelectedMaterial") && appSource.contains("Button(\"打开资料内搜索\")"), "app menu hides material-only actions when there is no material context")
expect(appSource.contains("Button(\"新建笔记\") { animateLayout { store.resetNote() } }"), "new-note menu command uses layout motion")
expect(appSource.contains("Button(store.sendAgentActionTitle)") && workspaceStoreSource.contains("var sendAgentActionTitle: String"), "app send command uses one stable action label")
expect(appSource.contains("if !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty")
    && appSource.contains(".keyboardShortcut(.return, modifiers: [.command])"), "app menu hides the agent send action until a draft can really send")
expect(appSource.contains("Button(store.showLibrary ? \"收起资料库\" : \"打开资料库\")")
    && !appSource.contains("恢复资料")
    && appSource.contains("Button(store.showRightPane ? \"收起辅助栏\" : \"展开辅助栏\")"), "app menu names pane toggles by current state")
expect(appSource.contains("Button(AgentSurface.bottomDrawer.actionLabel)")
    && appSource.contains("Button(AgentSurface.selectionFloat.actionLabel)")
    && appSource.contains("if store.canUseSelectionAgentSurface")
    && !appSource.contains("Agent 底部抽屉")
    && !appSource.contains("Agent 右下角小窗")
    && !appSource.contains("Agent 划线浮层")
    && !appSource.contains("Agent 静默洞察"), "app menu uses the same user-facing agent surface labels as the command palette")
expect(appSource.contains("if store.layout.hasCollapsibleRightPane")
    && appSource.contains("if store.canApplyAgentAnswer")
    && appSource.contains("if store.canReplaceNoteSelection")
    && !appSource.contains(".disabled("), "app menu hides unavailable actions instead of showing disabled grey items")
expect(appSource.contains("Button(\"聚焦资料\") { animateLayout { store.focus(.library) } }")
    && appSource.contains("Button(\"聚焦对话\") { animateLayout { store.focus(.agent) } }")
    && !appSource.contains("Button(\"聚焦 Agent\")")
    && appSource.contains("Button(\"下一份资料\") { animateLayout { store.selectAdjacentItem(step: 1) } }"), "app menu focus and material navigation use the same layout motion as shortcuts")
expect(appSource.contains("Button(\"写入回答到笔记\") { animatePanel { store.applyLastAgentAnswerToNote() } }")
    && appSource.contains("Button(\"替换笔记选区\") { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }")
    && appSource.contains("Button(\"追加整理建议\") { animatePanel { store.applyAgentPatchToEditor() } }")
    && !appSource.contains("用 Agent 替换笔记选区")
    && !appSource.contains("追加 Agent 整理建议"), "app menu agent write actions use the same panel motion as shortcuts")
let directPromptConsumers = [appSource, contentViewSource, sidebarSource, commandPaletteSource, notesAgentSource].joined(separator: "\n")
expect(!directPromptConsumers.contains("WeiBeiInputPrompt("), "views use the shared input prompt overlay instead of direct prompt layering")
expect(!workspaceStoreSource.contains("请解释我刚才选中的内容") && !notesAgentSource.contains("请解释我刚才选中的内容"), "agent entry does not invent a missing selection")
expect(notesAgentSource.contains("compactHovering") && notesAgentSource.contains(".weibeiAnnotationPanel(cornerRadius: 5)") && !notesAgentSource.contains("compactBackground"), "compact quiet insight reuses the shared annotation surface")
expect(!notesAgentSource.contains(".opacity(compactHovering ? 1 : 0.68)")
    && notesAgentSource.contains("if compactHovering {\n                HStack(spacing: 4)"), "compact quiet insight actions stay hidden until hover without dimming the text")
expect(notesAgentSource.contains("if compactHovering {\n                HStack(spacing: 4)") && notesAgentSource.contains(".transition(WeiBeiTransition.floating)"), "compact quiet insight keeps actions hidden until hover")
expect(notesAgentSource.contains("@State private var panelHovering = false")
    && notesAgentSource.contains("if panelHovering {\n                        HStack(spacing: 4)")
    && notesAgentSource.contains("iconButton(\"text.badge.plus\", help: \"收进摘录\")")
    && notesAgentSource.contains("iconButton(\"bubble.left\", help: \"追问\")")
    && notesAgentSource.contains("iconButton(\"xmark\", help: \"忽略阅读线索\")")
    && !notesAgentSource.contains("Button(\"收进摘录\")")
    && !notesAgentSource.contains("Button(\"追问\")")
    && !notesAgentSource.contains("Button(\"忽略\")"), "regular quiet insight behaves like a margin note: actions are icon-only and hidden until hover")
expect(notesAgentSource.contains("let itemID = store.selectedItemID") && notesAgentSource.contains("store.updateNote(value, for: itemID)"), "rich note editor writes through selected item guard")
expect(notesAgentSource.contains("ContextRailLine") && notesAgentSource.contains(".onHover"), "context rails keep hover motion")
expect(!notesAgentSource.contains(".id(store.noteRenderMode)"), "note mode changes avoid forced hard view identity resets")
expect(notesAgentSource.contains("struct ContextRailItem: Identifiable") && notesAgentSource.contains("Button(action: action)"), "context rails expose actionable rows")
expect(notesAgentSource.contains("var systemImage: String?") && notesAgentSource.contains("Image(systemName: systemImage)"), "context rail rows support semantic icons")
expect(notesAgentSource.contains(".accessibilityLabel(Text(item.help ?? item.title))") && notesAgentSource.contains(".help(item.help ?? item.title)"), "context rail actions explain their intent")
expect(notesAgentSource.contains("var edge: HorizontalEdge = .trailing") && notesAgentSource.contains("edge == .leading ? -3 : 3"), "context rails move inward from either side")
expect(notesAgentSource.contains("private var railBackground: some View")
    && notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(0.10)")
    && notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(0.26)")
    && notesAgentSource.contains(".frame(width: 22)")
    && !notesAgentSource.contains("WeiBeiTheme.paper.opacity(0.18)")
    && !notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(0.40),\n                    WeiBeiTheme.paper.opacity(0.42),\n                    WeiBeiTheme.paper.opacity(0.28)"), "immersive context rails avoid full-height heavy background bands")
expect(!notesAgentSource.contains(".id(expanded)"), "selection agent expands without forcing a hard view identity reset")
expect(contentViewSource.contains("edge: .leading") && contentViewSource.contains("edge: .trailing"), "immersive rails declare their content-facing edge")
expect(contentViewSource.contains("conversationSourceRailItems") && contentViewSource.contains("conversationTargetRailItems") && contentViewSource.contains("writingAssistRailItems"), "immersive rails wire role-specific actions")
expect(contentViewSource.contains("systemImage: \"square.and.pencil\"") && contentViewSource.contains("systemImage: \"quote.opening\""), "immersive rail actions use stable semantic icons")
expect(contentViewSource.contains("ContextRailItem(title: \"资料库\", help: \"打开资料库选择资料\", systemImage: \"sidebar.left\", emphasized: items.isEmpty)")
    && contentViewSource.contains("private func openLibrary()")
    && contentViewSource.contains("store.revealLibrary()")
    && workspaceStoreSource.contains("func revealLibrary()"), "immersive writing keeps a library entry and opens it through the shared store helper")
expect(contentViewSource.components(separatedBy: "ContextRailItem(title: \"资料库\", help: \"打开资料库选择资料\", systemImage: \"sidebar.left\"").count >= 3
    && contentViewSource.contains("emphasized: items.isEmpty"), "immersive rails keep a lightweight library chooser even when a document is already selected")
expect(contentViewSource.contains("store.agentPromptScope")
    && contentViewSource.contains("store.hasSelectedMaterial ? \"请检查当前笔记缺少来源的位置")
    && contentViewSource.contains("\"请检查当前笔记缺少来源的位置，并标出需要补证据的段落。\""), "immersive agent rails reuse real context wording")
expect(contentViewSource.contains(".overlay(alignment: agentAlignment)") && contentViewSource.contains("if store.agentSurface != .quietInsight {\n                        agentOverlay"), "immersive layouts can show the lightweight agent overlay")
expect(!contentViewSource.contains("来源预览"), "immersive writing document rail avoids duplicate reader entries")
expect(!contentViewSource.contains("title: store.selectedItem?.title ?? \"当前材料\"") && contentViewSource.contains("if let item = store.selectedMaterialItem"), "immersive rails avoid fake current material entries")
expect(contentViewSource.contains("store.appendSelectionToNote()") && contentViewSource.contains("store.copyCurrentReference()") && contentViewSource.contains("prepareAgentDraft"), "immersive rails connect to existing note, reference, and agent actions")
expect(!notesAgentSource.contains("Agent 抽屉"), "agent drawer avoids engineering labels")
expect(!notesAgentSource.contains("Agent 只在右下角待命"), "corner agent avoids explanatory placeholder copy")
expect(!notesAgentSource.contains("魏碑会优先读取材料"), "agent empty state avoids product-explainer copy")
expect(!notesAgentSource.contains("Text(\"当前上下文\")") && !notesAgentSource.contains("contextLine("), "agent empty state avoids diagnostic context rows")
expect(notesAgentSource.contains("Text(\"已含选区\")"), "agent empty state keeps a compact selection cue")
expect(notesAgentSource.contains("AgentStarterChip") && notesAgentSource.contains("hovering ? -1 : 0"), "agent starter chips keep subtle hover motion")
expect(notesAgentSource.contains("if store.hasSelectedMaterial") && notesAgentSource.contains("starterChip(\"梳理材料\"") && notesAgentSource.contains("starterChip(\"出复习题\""), "agent starter chips hide material actions without a selected material")
expect(notesAgentSource.contains("canPolishNoteSelection") && notesAgentSource.contains("store.selectionContext?.isNoteSelection == true"), "selection agent only shows polish for note selections")
expect(notesAgentSource.contains("Text(\"正在读选区...\")")
    && notesAgentSource.contains(".foregroundStyle(WeiBeiTheme.secondaryInk)")
    && notesAgentSource.contains("if message.text.hasPrefix(\"Agent 请求失败：\")")
    && notesAgentSource.contains("if message.role == .user {\n            return WeiBeiTheme.link")
    && !notesAgentSource.contains("if message.role == .user || message.text.hasPrefix(\"Agent 请求失败：\")"), "selection floating agent reserves cinnabar for real failures instead of ordinary progress or user text")
expect(notesAgentSource.contains("private var isCredentialNotice: Bool")
    && notesAgentSource.contains("message.text.hasPrefix(\"未配置 OPENAI_API_KEY\")")
    && notesAgentSource.contains("credentialNoticeContent")
    && notesAgentSource.contains("Text(\"需要设置密钥\")")
    && notesAgentSource.contains("设置后会结合\\(store.agentPromptScope)作答；未配置时不会编造内容。")
    && notesAgentSource.contains("isCredentialNotice ? 360 : 560")
    && notesAgentSource.contains("if !isUser && !isCredentialNotice"), "agent credential notice renders as a compact setup hint instead of a raw chat/error bubble")
expect(notesAgentSource.contains("store.canOpenSelectedSourceReference") && notesAgentSource.contains("Button(\"来源\")") && notesAgentSource.contains("openSourceReference()"), "selection agent exposes a lightweight source jump when the note selection is a reference")
expect(notesAgentSource.contains("onSourceReference: { reference in store.openSourceReference(reference) }"), "note editor source references can jump back to material")
expect(notesAgentSource.contains("emptyNoteHintText") && notesAgentSource.contains("store.hasSelectedMaterial ? \"开始记录当前材料\" : \"开始记录当前笔记\"") && notesAgentSource.contains(".allowsHitTesting(false)"), "blank note editor cue matches whether a material is selected")
expect(notesAgentSource.contains("noteFileStatusColor(for message: String)") && notesAgentSource.contains("message.hasPrefix(\"无法\") ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk"), "note file success statuses do not render as errors")
expect(notesAgentSource.contains(".help(\"新建独立 Markdown 笔记\")") && notesAgentSource.contains("结合\\(store.agentPromptScope)和当前选区作答") && !notesAgentSource.contains("结合已选择材料、选区和笔记"), "note and floating agent hints avoid fake current material context")
expect(notesAgentSource.contains("Button(\"作为笔记编辑\")")
    && commandPaletteSource.contains("PaletteCommand(title: \"作为笔记编辑当前 Markdown\"")
    && !notesAgentSource.contains("Button(\"写回原 Markdown\")")
    && !commandPaletteSource.contains("写回当前 Markdown 文件"), "imported markdown conversion is named as editing, not an immediate overwrite")
expect(notesAgentSource.contains("drawerPrompt") && notesAgentSource.contains("return \"问当前选区\"") && !notesAgentSource.contains("问当前选区或当前材料"), "agent drawer placeholder avoids fake material context")
expect(notesAgentSource.components(separatedBy: "!store.isAskingAgent && !store.agentDraft.trimmingCharacters").count >= 4, "all agent send affordances hide while a request is running")
expect(notesAgentSource.contains("store.hasSelectedMaterial ? \"问当前材料\" : \"问当前笔记\"") && notesAgentSource.contains(".weibeiInputPrompt(agentPrompt, visible: store.agentDraft.isEmpty, fontSize: 14)") && notesAgentSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "agent input placeholder matches context and uses the shared readable overlay")
expect(notesAgentSource.contains("store.hasSelectedMaterial ? \"来源\" : \"笔记\"") && notesAgentSource.contains("store.selectedMaterialItem?.title ?? \"当前笔记\""), "agent drawer source row avoids fake current material")
expect(notesAgentSource.contains(".weibeiInputSurface(active: draftFocused, height: 42)")
    && notesAgentSource.contains("WeiBeiIconButtonStyle(active: true, size: 34)"), "bottom agent drawer input reads as a compact composer instead of a search strip")
if let cornerStart = notesAgentSource.range(of: "struct CornerAgentView")?.lowerBound,
   let selectionStart = notesAgentSource.range(of: "struct FloatingSelectionAgentView")?.lowerBound {
    let cornerAgentSource = String(notesAgentSource[cornerStart..<selectionStart])
    expect(!cornerAgentSource.contains("cornerToolButton(")
        && !cornerAgentSource.contains("整理笔记")
        && cornerAgentSource.contains("Text(\"对话\")")
        && !cornerAgentSource.contains("Text(\"Agent\")")
        && cornerAgentSource.contains(".weibeiInputSurface(active: draftFocused, height: 38)")
        && cornerAgentSource.contains(".help(\"收起对话浮窗\")"), "corner agent stays a lightweight localized prompt surface")
} else {
    expect(false, "corner agent source is readable")
}
if let selectionStart = notesAgentSource.range(of: "struct FloatingSelectionAgentView")?.lowerBound,
   let contextRailStart = notesAgentSource.range(of: "struct ContextRailItem")?.lowerBound {
    let floatingSelectionSource = String(notesAgentSource[selectionStart..<contextRailStart])
    expect(floatingSelectionSource.contains("private var promptSeparator: some View")
        && floatingSelectionSource.contains("WeiBeiTheme.hairline.opacity(0.78)")
        && !floatingSelectionSource.contains("Divider()"), "selection floating agent uses WeiBei hairline separators instead of system dividers")
    expect(floatingSelectionSource.contains(".frame(height: 34)")
        && floatingSelectionSource.contains(".weibeiInputSurface(active: draftFocused, height: 34)"), "expanded selection agent keeps a small but usable follow-up composer")
    expect(floatingSelectionSource.contains("Text(\"关闭选区对话\")")
        && floatingSelectionSource.contains("help: \"关闭选区对话\"")
        && !floatingSelectionSource.contains("收起选区 Agent"), "selection floating close affordances avoid internal agent naming")
} else {
    expect(false, "selection floating agent source is readable")
}
expect(notesAgentSource.contains("private var agentInputTray: some View"), "agent pane uses a dedicated input tray")
expect(notesAgentSource.contains("WeiBeiGlassHeaderBackground(") && notesAgentSource.contains("WeiBeiTheme.glassTint.opacity(0.66)"), "agent input tray uses paper glass fade instead of a hard white strip")
expect(notesAgentSource.contains(".weibeiInputSurface(active: draftFocused, height: 46)")
    && notesAgentSource.contains("WeiBeiIconButtonStyle(active: canSendDraft, size: 34)"), "main agent input keeps a real chat-composer height instead of collapsing into a search-field strip")
expect(!notesAgentSource.contains("RoundedRectangle(cornerRadius: 9)")
    && !notesAgentSource.contains(".stroke(draftFocused ? WeiBeiTheme.link.opacity(0.16) : WeiBeiTheme.hairline.opacity(0.34), lineWidth: 1)")
    && !notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(0.46)"), "agent input tray avoids a heavy nested form border")
expect(!notesAgentSource.contains(".disabled(store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)") && !notesAgentSource.contains(".disabled(!canSend)") && !notesAgentSource.contains(".disabled(store.isAskingAgent)"), "agent inputs hide unavailable send actions instead of showing disabled buttons")
expect(notesAgentSource.contains("agentToolButton(\"整理\", help: \"整理笔记\"") && notesAgentSource.contains("agentToolButton(\"写入回答\", help: \"写入回答到笔记\""), "agent toolbar uses short readable action labels")
expect(notesAgentSource.contains("if !store.messages.isEmpty {\n                    agentToolButton(\"整理\""), "agent header avoids duplicating the organize action in the empty state")
expect(notesAgentSource.contains("private func iconButton(_ systemName: String, help: String") && notesAgentSource.contains(".accessibilityLabel(Text(help))"), "floating icon buttons carry semantic labels")
expect(notesAgentSource.contains("private func togglePinnedFloatingAgent()")
    && notesAgentSource.contains("if store.pinnedFloatingAgent {\n            dragOffset = .zero\n            settledOffset = .zero\n        }")
    && !notesAgentSource.contains("store.pinnedFloatingAgent.toggle()\n                    }\n                }\n                iconButton(\"xmark\""), "unpinning the selection agent returns it to the current selection anchor")
expect(notesAgentSource.contains(".help(\"收起对话浮窗\")") && !notesAgentSource.contains(".help(\"收起右下角 Agent\")"), "corner agent close button explains its action without engineering labels")
expect(commandPaletteSource.contains("插入行内公式") && commandPaletteSource.contains("${{WEIBEI_SELECT_START}}x_i = \\\\frac{a}{b}{{WEIBEI_SELECT_END}}$") && commandPaletteSource.contains("插入矩阵公式"), "markdown command templates keep an editable landing point")
expect(commandPaletteSource.contains("private func markdownInsertCommand") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "markdown insert commands use layout motion when revealing writing")
let editorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/WebEditor/src/editor.js")
let editorSource = (try? String(contentsOf: editorSourceURL, encoding: .utf8)) ?? ""
expect(editorSource.contains("decorateSourceReferences") && editorSource.contains("sourceReferenceActivated") && editorSource.contains("activateSourceReference"), "web editor exposes source references as clickable bridge actions")
let richMarkdownEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/RichMarkdownEditorView.swift")
let richMarkdownEditorSource = (try? String(contentsOf: richMarkdownEditorSourceURL, encoding: .utf8)) ?? ""
expect(richMarkdownEditorSource.contains("\"sourceReferenceActivated\"") && richMarkdownEditorSource.contains("onSourceReference(reference)"), "rich editor bridges source-reference clicks into Swift")
expect(LibraryNavigator.adjacentID(in: [], selectedID: nil, step: 1) == nil, "library navigation empty")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: nil, step: 1) == "a", "library navigation defaults first")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "b", step: 1) == "c", "library navigation next")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "a", step: -1) == "c", "library navigation wraps previous")

expect(SelectionContext(text: "文档", source: .document, ownerTitle: "资料").isNoteSelection == false, "document selection is read-only")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isNoteSelection == true, "note selection is replaceable")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isReplaceableNoteSelection, "editable note selection can be replaced")
expect(!SelectionContext(text: "预览", source: .note, ownerTitle: "资料", isEditable: false).isReplaceableNoteSelection, "preview note selection is not replaceable")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: true) == 20, "flipped content view keeps selection y")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: false) == 80, "non-flipped content view converts selection y")
expect(!SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false), "selection agent waits for anchor before floating")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: true, pinned: false), "selection agent appears when anchored")
expect(SelectionFloatingAgentPlacement.expandedHalfWidth == 156 && SelectionFloatingAgentPlacement.compactHalfWidth == 82, "selection agent placement constants match the compact and expanded surfaces")
expect(contentViewSource.contains("SelectionFloatingAgentPlacement.expandedHalfWidth")
    && contentViewSource.contains("SelectionFloatingAgentPlacement.compactHalfWidth")
    && !contentViewSource.contains("surfaceHalfWidth: floatingAgentExpanded ? 170 : 82"), "selection agent placement uses shared width constants instead of duplicate magic numbers")
expect(notesAgentSource.contains(".frame(width: CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2), alignment: .leading)")
    && !notesAgentSource.contains(".frame(width: 312, alignment: .leading)"), "expanded selection agent visual width matches placement half-width")
let floatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
let topInsetFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    topInset: 42
)
expect(floatingPoint.x == 486 && floatingPoint.y == 218, "selection agent opens close beside the text anchor")
expect(topInsetFloatingPoint.x == 486 && topInsetFloatingPoint.y == 176, "selection agent compensates top bar coordinate space")
let compactEdgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 12, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
let compactCenterFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
expect(compactCenterFloatingPoint.x == 320 && compactCenterFloatingPoint.y == 218, "selection prompt centers on the text anchor when compact")
expect(compactEdgeFloatingPoint.x == 100 && compactEdgeFloatingPoint.y == 218, "selection prompt clamps only at the edge when compact")
let edgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 1160, y: 760),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
expect(edgeFloatingPoint.x == 994 && edgeFloatingPoint.y == 708, "selection agent flips to the left of text near the window edge")
expect(AgentMessage(role: .assistant, text: "整理完成", source: nil).isUsableAgentAnswer, "usable agent answer")
expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY。", source: nil).isUsableAgentAnswer, "api key setup message is not writable")
expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY 或钥匙串密钥。", source: nil).isUsableAgentAnswer, "keychain setup message is not writable")
expect(!AgentMessage(role: .assistant, text: "Agent 请求失败：网络错误", source: nil).isUsableAgentAnswer, "agent error is not writable")

let importedMarkdown = StudyItem(id: "file:/tmp/note.md", title: "note", subtitle: "note.md", kind: .markdown, urlPath: "/tmp/note.md", isSample: false)
let notebookMarkdown = StudyItem(id: "file:/tmp/notebook.md", title: "notebook", subtitle: "notebook.md", kind: .markdown, urlPath: "/tmp/notebook.md", isSample: false, isNotebookNote: true)
let sampleMarkdown = StudyItem(id: "sample", title: "sample", subtitle: "sample", kind: .markdown, urlPath: nil, isSample: true)
expect(importedMarkdown.isImportedMarkdownFile, "imported markdown is readable as material")
expect(!importedMarkdown.editsBackingMarkdownFile, "imported markdown material does not edit backing file")
expect(importedMarkdown.canBecomeNotebookNote, "imported markdown can become an editable notebook note")
expect(notebookMarkdown.editsBackingMarkdownFile, "notebook markdown edits its backing file")
expect(!notebookMarkdown.canBecomeNotebookNote, "notebook markdown does not offer duplicate conversion")
expect(!sampleMarkdown.isImportedMarkdownFile, "sample markdown stays app-owned")
expect(!sampleMarkdown.canBecomeNotebookNote, "sample markdown cannot become a backing-file note")

let persisted = PersistedWorkspace(noteRenderMode: .preview, showLibrary: false, showRightPane: false)
let restored = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(persisted))
expect(restored.showLibrary == false && restored.showRightPane == false, "pane collapse state persists")
expect(restored.noteRenderMode == .preview, "note render mode persists without collapsing preview or split back to rich")
expect(workspaceStoreSource.contains("if let noteRenderMode = snapshot.noteRenderMode {\n            self.noteRenderMode = noteRenderMode\n        }")
    && !workspaceStoreSource.contains("noteRenderMode == .source ? .source : .rich"), "workspace load restores the saved note render mode exactly")

let attachmentRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("weibei-self-check-\(UUID().uuidString)", isDirectory: true)
let attachmentDirectory = attachmentRoot.appendingPathComponent(".weibei-assets", isDirectory: true)
let dataURL = "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())"
let firstAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(firstAttachment.src == ".weibei-assets/图 1).png", "attachment uses relative markdown path")
expect(firstAttachment.alt == "图 1)", "attachment alt uses safe stem")
expect(MarkdownAttachmentStore.markdownImage(for: firstAttachment) == "![图 1)](.weibei-assets/图%201%29.png)", "markdown image escapes path")

let secondAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(secondAttachment.src == ".weibei-assets/图 1)-2.png", "attachment avoids overwriting duplicate names")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(firstAttachment.src).path), "first attachment written")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(secondAttachment.src).path), "second attachment written")
let rawAttachment = try MarkdownAttachmentStore.save(
    data: Data([1, 2, 3]),
    originalName: "dragged.webp",
    mime: "",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(rawAttachment.src == ".weibei-assets/dragged.webp", "raw image data save keeps image extension")
expect(MarkdownAttachmentStore.isSupportedImageExtension("HEIC"), "image extension check is case insensitive")
expect(MarkdownAttachmentStore.mimeType(forFileExtension: "jpeg") == "image/jpeg", "mime from extension")
let blockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "来源：课程 HTML",
    replacing: NSRange(location: ("来源：课程 HTML" as NSString).length, length: 0)
)
expect(blockInsert.text == "来源：课程 HTML\n\n![pasted](Attachments/pasted.png)", "block markdown insertion separates from inline text")
let middleBlockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "前文后文",
    replacing: NSRange(location: ("前文" as NSString).length, length: 0)
)
expect(middleBlockInsert.text == "前文\n\n![pasted](Attachments/pasted.png)\n\n后文", "block markdown insertion separates both sides")
try? FileManager.default.removeItem(at: attachmentRoot)

print("WeiBei self-check passed")
