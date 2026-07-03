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
expect(!runScript.contains("pid=\"$(pgrep -x \"$PRODUCT_NAME\""), "run script window verification does not depend on pgrep")
expect(runScript.contains("visual_verify_window") && runScript.contains("--visual-verify") && runScript.contains("visual_non_black_ratio") && runScript.contains("visual verify failed: captured window is black or empty") && runScript.contains("nonBlackRatio < 0.02"), "run script exposes an explicit visual non-black window check")
let editorIndexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
let editorIndexSource = (try? String(contentsOf: editorIndexURL, encoding: .utf8)) ?? ""
expect(
    editorIndexSource.contains(".ProseMirror span[data-type=\"math_inline\"],")
        && editorIndexSource.contains(".ProseMirror .math-inline")
        && editorIndexSource.contains(".ProseMirror .math-block"),
    "math styling hides raw source for both Milkdown math node class shapes"
)
expect(editorIndexSource.contains(".ProseMirror .math-inline {\n      color: transparent") && editorIndexSource.contains(".ProseMirror .katex-error {\n      color: var(--cinnabar)"), "math styling hides raw source while keeping KaTeX errors readable")
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
expect(
    themeSource.contains("struct WeiBeiInputPrompt")
        && themeSource.contains(".foregroundColor(WeiBeiTheme.tertiaryInk)")
        && themeSource.contains(".foregroundStyle(WeiBeiTheme.tertiaryInk)")
        && !themeSource.contains(".foregroundColor(.white)")
        && !themeSource.contains(".foregroundStyle(.white)")
        && !themeSource.contains(".colorMultiply(WeiBeiTheme.tertiaryInk)"),
    "input placeholders draw readable semantic ink without white vibrancy hacks"
)
expect(themeSource.contains("func weibeiInputSurface") && themeSource.contains(".foregroundColor(WeiBeiTheme.ink)") && themeSource.contains(".foregroundStyle(WeiBeiTheme.ink)") && themeSource.contains(".tint(WeiBeiTheme.link)"), "input surfaces force readable text color on paper")
expect(contentViewSource.contains("ResizableTwoPane<First: View, Second: View>: NSViewRepresentable"), "two-pane layout uses native bridge")
expect(contentViewSource.contains("ResizableThreePane<First: View, Second: View, Third: View>: NSViewRepresentable"), "three-pane layout uses native bridge")
expect(contentViewSource.contains("WeiBeiSplitView: NSSplitView"), "content panes use native split view")
expect(contentViewSource.contains("override func layout()"), "native split applies saved positions after first real layout")
expect(contentViewSource.contains("libraryResizeHandle"), "library pane keeps SwiftUI resize handle")
expect(contentViewSource.contains("minimumContentWidthWithLibrary"), "library leaves readable width for the workspace")
expect(contentViewSource.contains("normalSidePaneMinimum"), "normal three-pane layout relaxes side panes when library is open")
expect(!contentViewSource.contains("DragGesture()"), "content panes avoid SwiftUI drag resizing")
expect(!contentViewSource.contains(".id(store.layout)"), "layout changes avoid whole-screen identity resets")
expect(!contentViewSource.contains("PaneSeparator"), "content panes avoid hand-drawn split separators")
expect(!contentViewSource.contains("topBarContentFade"), "top bar avoids a duplicate content fade wash")
expect(contentViewSource.contains("store.toggleLibrary()") && contentViewSource.contains("sidebar.left") && !contentViewSource.contains(".opacity(isImmersiveLayout ? 0.45 : 1)"), "immersive top bar keeps a clear library chooser instead of dimming a live control")
expect(!contentViewSource.contains("文代笔") && !contentViewSource.contains("Agent中") && contentViewSource.contains("对话中栏") && contentViewSource.contains("对话右栏"), "top bar short layout labels avoid cryptic abbreviations")
for helperName in ["openReader", "openWriting", "askCurrentSelection", "prepareAgentDraft"] {
    if let helperStart = contentViewSource.range(of: "private func \(helperName)")?.lowerBound,
       let helperEnd = contentViewSource[helperStart...].range(of: "\n    }\n")?.upperBound {
        let helperSource = String(contentViewSource[helperStart..<helperEnd])
        expect(!helperSource.contains("showLibrary = false"), "\(helperName) keeps a user-opened immersive library visible")
    } else {
        expect(false, "\(helperName) source is readable")
    }
}
expect(contentViewSource.contains("if store.readerSearch.isEmpty") && contentViewSource.contains("WeiBeiInputPrompt(\"当前资料内搜索\")") && contentViewSource.contains(".foregroundColor(primaryText)"), "top search placeholder uses readable semantic ink above the field")
expect(contentViewSource.contains("store.hasSelectedMaterial && store.layout != .immersiveConversation"), "top search only appears when a material is selected")
expect(contentViewSource.contains("layout == store.layout ? \"checkmark\"") && contentViewSource.contains(".accessibilityLabel(Text(\"切换布局\"))"), "layout menu marks current layout and explains itself")
expect(contentViewSource.contains(": layout.systemImage") && !contentViewSource.contains(": \"rectangle.split.3x1\""), "layout menu avoids repeating one generic icon")
expect(contentViewSource.contains(".accessibilityLabel(Text(\"更多设置\"))"), "top bar more menu has a readable semantic label")
let sidebarSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/SidebarView.swift")
let sidebarSource = (try? String(contentsOf: sidebarSourceURL, encoding: .utf8)) ?? ""
expect(sidebarSource.contains("if store.librarySearch.isEmpty") && sidebarSource.contains("WeiBeiInputPrompt(\"搜索资料库\")") && sidebarSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "library search placeholder uses readable semantic ink above the field")
expect(!sidebarSource.contains("commandPalettePresented.toggle()") && !sidebarSource.contains("Label(\"命令\", systemImage: \"command\")"), "sidebar does not duplicate the command palette entry")
expect(sidebarSource.contains("sidebarSection(title: \"导入资料\", items: importedMaterialItems)") && sidebarSource.contains("sidebarSection(title: \"笔记\", items: notebookItems)"), "sidebar separates materials from notebook notes")
expect(sidebarSource.contains("!$0.isSample && !$0.isNotebookNote") && sidebarSource.contains("store.filteredItems.filter(\\.isNotebookNote)"), "sidebar material list excludes notebook notes without hiding notes")
expect(contentViewSource.contains("topIconButton(\"command\", help: \"命令面板\")"), "top bar keeps the command palette entry")
let commandPaletteSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/CommandPaletteView.swift")
let commandPaletteSource = (try? String(contentsOf: commandPaletteSourceURL, encoding: .utf8)) ?? ""
expect(commandPaletteSource.contains("withAnimation(command.animation)") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "command palette uses layout motion for layout commands")
expect(!commandPaletteSource.contains("收起右栏"), "command palette avoids fixed right-pane wording")
expect(commandPaletteSource.contains("store.showLibrary ? \"收起资料\" : \"恢复资料\""), "command palette names the library toggle by current state")
expect(!commandPaletteSource.contains("PaletteCommand(title: \"顶栏") && contentViewSource.contains("Section(\"顶部栏\")"), "top bar variants live in the more menu instead of the command palette")
expect(commandPaletteSource.contains("private var rightPaneCommand: PaletteCommand?") && commandPaletteSource.contains("store.layout.hasCollapsibleRightPane"), "command palette hides right pane command when the layout has no auxiliary pane")
expect(commandPaletteSource.contains("收起辅助栏") && commandPaletteSource.contains("展开辅助栏"), "command palette names auxiliary pane action by current state")
expect(commandPaletteSource.contains("title: store.showRightPane ? \"收起辅助栏\" : \"展开辅助栏\",\n            shortcut: \"⌘J\",\n            animation: WeiBeiMotion.layout"), "command palette auxiliary pane command uses layout motion")
expect(commandPaletteSource.contains("if store.hasSelectedMaterial") && commandPaletteSource.contains("PaletteCommand(title: \"复制引用\"") && commandPaletteSource.contains("PaletteCommand(title: \"搜索当前资料\""), "command palette hides material-only actions without a selected material")
expect(commandPaletteSource.contains("private var canSendAgentDraft: Bool") && commandPaletteSource.contains("PaletteCommand(title: \"发送 Agent 问题\""), "command palette hides the agent send command until a draft exists")
expect(commandPaletteSource.contains("if store.canApplyAgentAnswer") && commandPaletteSource.contains("if store.canReplaceNoteSelection") && commandPaletteSource.contains("PaletteCommand(title: \"替换笔记选区\""), "command palette hides agent answer actions until they can work")
expect(commandPaletteSource.contains("if store.selectionContext != nil") && commandPaletteSource.contains("PaletteCommand(title: \"问选区 Agent\""), "command palette hides selection actions until a real selection exists")
expect(commandPaletteSource.contains("if store.canOpenSelectedSourceReference") && commandPaletteSource.contains("PaletteCommand(title: \"打开选区来源\""), "command palette exposes source jump only for parseable note references")
expect(commandPaletteSource.contains("if store.agentSurface != .hidden") && commandPaletteSource.contains("PaletteCommand(title: \"隐藏 Agent\""), "command palette hides the agent hide action when already hidden")
let readerViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ReaderView.swift")
let readerViewSource = (try? String(contentsOf: readerViewSourceURL, encoding: .utf8)) ?? ""
expect(readerViewSource.contains("readerStyleScript"), "html reader injects responsive reading style")
expect(readerViewSource.contains("overflow-wrap: anywhere"), "html reader prevents narrow-pane clipping")
expect(readerViewSource.contains("color-scheme: light") && readerViewSource.contains("color: #1d1814 !important") && readerViewSource.contains("a { color: #31566b !important; }"), "html reader forces readable ink over imported white text")
expect(!readerViewSource.contains("readerHeader") && !readerViewSource.contains("statusBar"), "reader avoids duplicate internal chrome under unified top bar")
expect(readerViewSource.contains("ReaderStateMessage") && !readerViewSource.contains("ContentUnavailableView("), "reader empty states use WeiBei paper styling")
expect(readerViewSource.contains("if store.selectedMaterialItem?.kind == .pdf") && readerViewSource.contains("if let item = store.selectedMaterialItem"), "reader renders materials, not notebook notes")
expect(readerViewSource.contains("NotebookSelectedReaderView") && readerViewSource.contains("阅读区只显示资料"), "reader explains notebook selection instead of rendering it as material")
expect(readerViewSource.contains("pdfFloatingControls"), "pdf controls stay available as a light floating tray")
expect(readerViewSource.contains(".accessibilityLabel(Text(\"上一页\"))") && readerViewSource.contains(".accessibilityLabel(Text(\"下一页\"))"), "pdf page controls have readable icon labels")
expect(readerViewSource.contains("syncReaderLocationTitle") && readerViewSource.contains("第 \\(pdfPageIndex + 1) 页"), "pdf reader page updates feed the shared reference title")
expect(readerViewSource.contains("var onSelectionChange: (String, CGPoint?, Int) -> Void") && readerViewSource.contains("pageIndex(for: selection, in: view)") && readerViewSource.contains("ownerTitle: ownerTitle"), "pdf selection source uses the selected page, not only the current page")
expect(readerViewSource.contains("pendingPDFPageIndex") && readerViewSource.contains("applyPendingPDFPageIfReady") && readerViewSource.contains("store.readerTargetPageIndex = nil"), "pdf reader consumes source-jump target pages")
expect(readerViewSource.contains("onSourceReference: { reference in store.openSourceReference(reference) }"), "markdown reader source references can jump back to material")
let richEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/RichMarkdownEditorView.swift")
let richEditorSource = (try? String(contentsOf: richEditorSourceURL, encoding: .utf8)) ?? ""
expect(richEditorSource.contains("var documentID = \"\"") && richEditorSource.contains("var pendingExternalMarkdown: String?"), "rich editor tracks document identity and pending external sync")
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
let appSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/App/WeiBeiApp.swift")
let appSource = (try? String(contentsOf: appSourceURL, encoding: .utf8)) ?? ""
expect(appSource.contains("window.isOpaque = true"), "main window declares opaque paper backing for stable capture")
expect(appSource.contains("sharedWorkspaceStore"), "main window and settings share one workspace store")
expect(!appSource.contains("launchProbe"), "app launch path has no temporary probe logging")
expect(appSource.contains("addLocalMonitorForEvents(matching: .keyDown)") && appSource.contains("removeMonitor(shortcutMonitor)"), "app-level shortcuts survive focused web editor")
expect(appSource.contains("return flag"), "reopen does not swallow the system window creation path")
expect(!appSource.contains("Form {") && appSource.contains("WeiBeiInputPrompt(\"OpenAI 密钥\")") && appSource.contains("SecureField(\"\", text: $store.openAIAPIKey)") && appSource.contains(".foregroundColor(WeiBeiTheme.ink)") && appSource.contains(".weibeiInputSurface(active: focusedField == .apiKey)"), "settings key input uses WeiBei input surface instead of the default form field")
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
expect(workspaceStoreSource.contains("guard hasSelectedMaterial || selectionContext != nil else { return false }") && workspaceStoreSource.contains("guard hasSelectedMaterial else { return false }"), "app shortcuts avoid material-only actions without material or selection context")
expect(workspaceStoreSource.contains("selectAdjacentItem(step: -1)") && workspaceStoreSource.contains("Task { await askAgent() }"), "app shortcut handler covers navigation and agent send")
expect(workspaceStoreSource.contains("showQuietInsight = agentSurface == .quietInsight") && !workspaceStoreSource.contains("agentSurface = .quietInsight\n            showQuietInsight = true"), "immersive reading preserves the chosen agent surface")
expect(workspaceStoreSource.contains("func updateNote(_ value: String, for itemID: String?)") && workspaceStoreSource.contains("guard itemID == selectedItemID else { return }"), "note writes are bound to the current selected item")
expect(workspaceStoreSource.contains("@Published var readerLocationTitle") && workspaceStoreSource.contains("var currentReferenceTitle"), "store tracks the current reader reference title")
expect(workspaceStoreSource.contains("@Published var readerTargetPageIndex") && workspaceStoreSource.contains("func openSourceReference") && workspaceStoreSource.contains("SourceReferenceTitle.parse"), "store can jump from source reference text to the referenced material")
expect(workspaceStoreSource.contains("ownerTitle: String? = nil") && workspaceStoreSource.contains("let resolvedOwnerTitle"), "selection updates can carry a precise reader source title")
expect(workspaceStoreSource.contains("sourceTitle: selectionContext.ownerTitle") && workspaceStoreSource.contains("来源：\\(currentReferenceTitle)"), "copy reference uses real selection or current reader source")
expect(workspaceStoreSource.contains("private func quotedReferenceBlock") && workspaceStoreSource.contains("> [!quote] 选区摘录") && !workspaceStoreSource.contains("## 选区摘录"), "selection excerpts use the shared quote callout format")
expect(workspaceStoreSource.contains("selectionOwnerTitle(for source: SelectionSource)") && workspaceStoreSource.contains("selectedItem?.isNotebookNote == true"), "selection fallback title treats notebook notes as notes")
expect(workspaceStoreSource.contains("var selectedMaterialItem") && workspaceStoreSource.contains("!item.isNotebookNote"), "selected material excludes notebook notes")
expect(workspaceStoreSource.contains("var navigableItems") && workspaceStoreSource.contains("let materialItems = allItems.filter { !$0.isNotebookNote }"), "material navigation skips notebook notes")
expect(
    workspaceStoreSource.contains("guard hasSelectedMaterial else")
        && workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("func revealReaderSearch()"),
    "reader search reveal refuses notebook-only context"
)
expect(
    workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("guard !hasSelectedMaterial else { return }")
        && workspaceStoreSource.contains("showReaderSearch = false")
        && workspaceStoreSource.contains("readerSearch = \"\""),
    "material search state clears when selection no longer points to a material"
)
expect(workspaceStoreSource.contains("var selectedMaterialTitle") && workspaceStoreSource.contains("selectedMaterialItem?.title ?? \"未选择材料\""), "agent material title does not invent a current material")
expect(workspaceStoreSource.contains("var agentMessageSourceTitle: String?") && workspaceStoreSource.contains("selectedMaterialItem?.title ?? selectedItem?.title") && !workspaceStoreSource.contains("source: selectedMaterialItem?.title"), "agent message source falls back to the selected note title")
expect(workspaceStoreSource.contains("private var quietInsightReferenceTitle: String") && workspaceStoreSource.contains("selectionContext?.ownerTitle ?? selectedMaterialItem?.title ?? selectedItem?.title") && workspaceStoreSource.contains("没有证据就说\\(evidenceText)"), "quiet insight uses real note or material source wording")
expect(workspaceStoreSource.contains("layout == .immersiveReading || layout == .immersiveWriting") && workspaceStoreSource.contains("agentSurface = .cornerPanel") && !workspaceStoreSource.contains("layout = .immersiveConversation\n                showLibrary = false\n                showRightPane = true"), "agent focus in immersive layouts opens an overlay instead of switching layout")
if let setLayoutStart = workspaceStoreSource.range(of: "func setLayout(_ layout: WorkspaceLayout)")?.lowerBound,
   let setAgentSurfaceStart = workspaceStoreSource.range(of: "func setAgentSurface")?.lowerBound {
    let setLayoutSource = String(workspaceStoreSource[setLayoutStart..<setAgentSurfaceStart])
    expect(!setLayoutSource.contains("showLibrary = false"), "layout switching preserves the current library visibility")
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
expect(workspaceStoreSource.contains("let canShowSelectionFloat = SelectionFloatingAgentPlacement.isVisible") && workspaceStoreSource.contains("surface == .selectionFloat && !canShowSelectionFloat ? .cornerPanel : surface"), "selection-float agent surface falls back to a visible corner panel when no selection can anchor it")
expect(!workspaceStoreSource.contains("selectedItem?.title ?? \"当前材料\"") && !workspaceStoreSource.contains("保存后 Agent 会用当前材料") && !workspaceStoreSource.contains("已选择材料、当前选区和右侧笔记"), "agent context avoids fake material fallback copy")
expect(workspaceStoreSource.contains("var agentPromptScope") && workspaceStoreSource.contains("var selectionPromptScope") && workspaceStoreSource.contains("var libraryOrganizationScope"), "agent prompt builders share context wording")
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
expect(appSource.contains("if store.hasSelectedMaterial || store.selectionContext != nil") && appSource.contains("if store.hasSelectedMaterial") && appSource.contains("Button(\"搜索当前资料\")"), "app menu hides material-only actions when there is no material context")
expect(appSource.contains("Button(\"新建笔记\") { animateLayout { store.resetNote() } }"), "new-note menu command uses layout motion")
expect(appSource.contains("Button(store.hasSelectedMaterial ? \"问当前材料\" : \"问当前笔记\")"), "app command label matches whether a material is selected")
expect(appSource.contains("Button(store.showLibrary ? \"收起资料\" : \"恢复资料\")") && appSource.contains("Button(store.showRightPane ? \"收起辅助栏\" : \"展开辅助栏\")"), "app menu names pane toggles by current state")
expect(appSource.contains("Button(\"聚焦资料\") { animateLayout { store.focus(.library) } }")
    && appSource.contains("Button(\"下一份资料\") { animateLayout { store.selectAdjacentItem(step: 1) } }"), "app menu focus and material navigation use the same layout motion as shortcuts")
expect(appSource.contains("Button(\"应用 Agent 到笔记\") { animatePanel { store.applyLastAgentAnswerToNote() } }")
    && appSource.contains("Button(\"追加 Agent 整理建议\") { animatePanel { store.applyAgentPatchToEditor() } }"), "app menu agent write actions use the same panel motion as shortcuts")
let notesAgentSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/NotesAgentView.swift")
let notesAgentSource = (try? String(contentsOf: notesAgentSourceURL, encoding: .utf8)) ?? ""
expect(!workspaceStoreSource.contains("请解释我刚才选中的内容") && !notesAgentSource.contains("请解释我刚才选中的内容"), "agent entry does not invent a missing selection")
expect(notesAgentSource.contains("compactHovering") && notesAgentSource.contains("compactBackground"), "compact quiet insight uses a light margin-note surface")
expect(notesAgentSource.contains(".opacity(compactHovering ? 1 : 0.68)") && notesAgentSource.contains("paperRaised.opacity(compactHovering ? 0.82 : 0.58)"), "compact quiet insight stays readable before hover")
expect(notesAgentSource.contains("let itemID = store.selectedItemID") && notesAgentSource.contains("store.updateNote(value, for: itemID)"), "rich note editor writes through selected item guard")
expect(notesAgentSource.contains("ContextRailLine") && notesAgentSource.contains(".onHover"), "context rails keep hover motion")
expect(notesAgentSource.contains("struct ContextRailItem: Identifiable") && notesAgentSource.contains("Button(action: action)"), "context rails expose actionable rows")
expect(notesAgentSource.contains("var systemImage: String?") && notesAgentSource.contains("Image(systemName: systemImage)"), "context rail rows support semantic icons")
expect(notesAgentSource.contains(".accessibilityLabel(Text(item.help ?? item.title))") && notesAgentSource.contains(".help(item.help ?? item.title)"), "context rail actions explain their intent")
expect(notesAgentSource.contains("var edge: HorizontalEdge = .trailing") && notesAgentSource.contains("edge == .leading ? -3 : 3"), "context rails move inward from either side")
expect(!notesAgentSource.contains(".id(expanded)"), "selection agent expands without forcing a hard view identity reset")
expect(contentViewSource.contains("edge: .leading") && contentViewSource.contains("edge: .trailing"), "immersive rails declare their content-facing edge")
expect(contentViewSource.contains("conversationSourceRailItems") && contentViewSource.contains("conversationTargetRailItems") && contentViewSource.contains("writingAssistRailItems"), "immersive rails wire role-specific actions")
expect(contentViewSource.contains("systemImage: \"square.and.pencil\"") && contentViewSource.contains("systemImage: \"quote.opening\""), "immersive rail actions use stable semantic icons")
expect(contentViewSource.contains("store.selectionPromptScope") && contentViewSource.contains("store.agentPromptScope") && contentViewSource.contains("store.hasSelectedMaterial ? \"请检查当前笔记缺少来源的位置"), "immersive agent rails reuse real context wording")
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
expect(notesAgentSource.contains("store.canOpenSelectedSourceReference") && notesAgentSource.contains("Button(\"来源\")") && notesAgentSource.contains("openSourceReference()"), "selection agent exposes a lightweight source jump when the note selection is a reference")
expect(notesAgentSource.contains("onSourceReference: { reference in store.openSourceReference(reference) }"), "note editor source references can jump back to material")
expect(notesAgentSource.contains("emptyNoteHintText") && notesAgentSource.contains("store.hasSelectedMaterial ? \"开始记录当前材料\" : \"开始记录当前笔记\"") && notesAgentSource.contains(".allowsHitTesting(false)"), "blank note editor cue matches whether a material is selected")
expect(notesAgentSource.contains("noteFileStatusColor(for message: String)") && notesAgentSource.contains("message.hasPrefix(\"无法\") ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk"), "note file success statuses do not render as errors")
expect(notesAgentSource.contains(".help(\"新建独立 Markdown 笔记\")") && notesAgentSource.contains("结合\\(store.agentPromptScope)和当前选区作答") && !notesAgentSource.contains("结合已选择材料、选区和笔记"), "note and floating agent hints avoid fake current material context")
expect(notesAgentSource.contains("drawerPrompt") && notesAgentSource.contains("return \"问当前选区\"") && !notesAgentSource.contains("问当前选区或当前材料"), "agent drawer placeholder avoids fake material context")
expect(notesAgentSource.contains("store.hasSelectedMaterial ? \"问当前材料\" : \"问当前笔记\"") && notesAgentSource.contains("if store.agentDraft.isEmpty") && notesAgentSource.contains("WeiBeiInputPrompt(agentPrompt)") && notesAgentSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "agent input placeholder matches context and stays readable above the field")
expect(notesAgentSource.contains("store.hasSelectedMaterial ? \"来源\" : \"笔记\"") && notesAgentSource.contains("store.selectedMaterialItem?.title ?? \"当前笔记\""), "agent drawer source row avoids fake current material")
if let cornerStart = notesAgentSource.range(of: "struct CornerAgentView")?.lowerBound,
   let selectionStart = notesAgentSource.range(of: "struct FloatingSelectionAgentView")?.lowerBound {
    let cornerAgentSource = String(notesAgentSource[cornerStart..<selectionStart])
    expect(!cornerAgentSource.contains("cornerToolButton(") && !cornerAgentSource.contains("整理笔记"), "corner agent stays a lightweight prompt surface")
} else {
    expect(false, "corner agent source is readable")
}
expect(notesAgentSource.contains("private var agentInputTray: some View"), "agent pane uses a dedicated input tray")
expect(notesAgentSource.contains("WeiBeiGlassHeaderBackground(") && notesAgentSource.contains("WeiBeiTheme.glassTint.opacity(0.66)"), "agent input tray uses paper glass fade instead of a hard white strip")
expect(!notesAgentSource.contains(".disabled(store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)") && !notesAgentSource.contains(".disabled(!canSend)") && !notesAgentSource.contains(".disabled(store.isAskingAgent)"), "agent inputs hide unavailable send actions instead of showing disabled buttons")
expect(notesAgentSource.contains("agentToolButton(\"整理\", help: \"整理笔记\"") && notesAgentSource.contains("agentToolButton(\"写入\", help: \"写入笔记\""), "agent toolbar uses short readable action labels")
expect(notesAgentSource.contains("if !store.messages.isEmpty {\n                    agentToolButton(\"整理\""), "agent header avoids duplicating the organize action in the empty state")
expect(notesAgentSource.contains("private func iconButton(_ systemName: String, help: String") && notesAgentSource.contains(".accessibilityLabel(Text(help))"), "floating icon buttons carry semantic labels")
expect(notesAgentSource.contains(".help(\"收起右下角 Agent\")"), "corner agent close button explains its action")
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
let floatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
let topInsetFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    topInset: 42
)
expect(floatingPoint.x == 496 && floatingPoint.y == 228, "selection agent opens beside the text anchor")
expect(topInsetFloatingPoint.x == 496 && topInsetFloatingPoint.y == 186, "selection agent compensates top bar coordinate space")
let compactEdgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 12, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: 82
)
expect(compactEdgeFloatingPoint.x == 100 && compactEdgeFloatingPoint.y == 228, "selection prompt clamps using compact width")
let edgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 1160, y: 760),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
expect(edgeFloatingPoint.x == 1012 && edgeFloatingPoint.y == 708, "selection agent clamps near window edge")
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

let persisted = PersistedWorkspace(showLibrary: false, showRightPane: false)
let restored = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(persisted))
expect(restored.showLibrary == false && restored.showRightPane == false, "pane collapse state persists")

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
