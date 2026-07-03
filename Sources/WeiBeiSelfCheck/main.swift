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

expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.pdf")) == .pdf, "pdf detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.html")) == .html, "html detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.md")) == .markdown, "markdown detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.txt")) == .text, "text detection")

let data = Data("""
{"output":[{"content":[{"type":"output_text","text":"只根据当前材料回答。"}]}]}
""".utf8)
let text = try OpenAIResponsesClient.extractText(from: data)
expect(text == "只根据当前材料回答。", "response parser")
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
expect(!contentViewSource.contains("文代笔") && contentViewSource.contains("Agent中"), "top bar short layout labels avoid cryptic abbreviations")
expect(contentViewSource.contains("prompt: Text(\"当前资料内搜索\").foregroundStyle(tertiaryText)"), "top search placeholder uses readable semantic ink")
expect(contentViewSource.contains("layout == store.layout ? \"checkmark\"") && contentViewSource.contains(".accessibilityLabel(Text(\"切换布局\"))"), "layout menu marks current layout and explains itself")
expect(contentViewSource.contains(": layout.systemImage") && !contentViewSource.contains(": \"rectangle.split.3x1\""), "layout menu avoids repeating one generic icon")
expect(contentViewSource.contains(".accessibilityLabel(Text(\"更多设置\"))"), "top bar more menu has a readable semantic label")
let sidebarSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/SidebarView.swift")
let sidebarSource = (try? String(contentsOf: sidebarSourceURL, encoding: .utf8)) ?? ""
expect(sidebarSource.contains("prompt: Text(\"搜索资料库\").foregroundStyle(WeiBeiTheme.tertiaryInk)"), "library search placeholder uses readable semantic ink")
let commandPaletteSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/CommandPaletteView.swift")
let commandPaletteSource = (try? String(contentsOf: commandPaletteSourceURL, encoding: .utf8)) ?? ""
expect(commandPaletteSource.contains("withAnimation(command.animation)") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "command palette uses layout motion for layout commands")
expect(!commandPaletteSource.contains("收起右栏"), "command palette avoids fixed right-pane wording")
expect(commandPaletteSource.contains("private var rightPaneCommand: PaletteCommand?") && commandPaletteSource.contains("store.layout.hasCollapsibleRightPane"), "command palette hides right pane command when the layout has no auxiliary pane")
expect(commandPaletteSource.contains("收起辅助栏") && commandPaletteSource.contains("展开辅助栏"), "command palette names auxiliary pane action by current state")
let readerViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ReaderView.swift")
let readerViewSource = (try? String(contentsOf: readerViewSourceURL, encoding: .utf8)) ?? ""
expect(readerViewSource.contains("readerStyleScript"), "html reader injects responsive reading style")
expect(readerViewSource.contains("overflow-wrap: anywhere"), "html reader prevents narrow-pane clipping")
expect(!readerViewSource.contains("readerHeader") && !readerViewSource.contains("statusBar"), "reader avoids duplicate internal chrome under unified top bar")
expect(readerViewSource.contains("if store.selectedItem?.kind == .pdf") && readerViewSource.contains("pdfFloatingControls"), "pdf controls stay available as a light floating tray")
expect(readerViewSource.contains(".accessibilityLabel(Text(\"上一页\"))") && readerViewSource.contains(".accessibilityLabel(Text(\"下一页\"))"), "pdf page controls have readable icon labels")
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
expect(appSource.contains("sharedWorkspaceStore"), "main window and settings share one workspace store")
expect(!appSource.contains("launchProbe"), "app launch path has no temporary probe logging")
expect(appSource.contains("addLocalMonitorForEvents(matching: .keyDown)") && appSource.contains("removeMonitor(shortcutMonitor)"), "app-level shortcuts survive focused web editor")
expect(appSource.contains("return flag"), "reopen does not swallow the system window creation path")
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
expect(workspaceStoreSource.contains("selectAdjacentItem(step: -1)") && workspaceStoreSource.contains("Task { await askAgent() }"), "app shortcut handler covers navigation and agent send")
expect(workspaceStoreSource.contains("func updateNote(_ value: String, for itemID: String?)") && workspaceStoreSource.contains("guard itemID == selectedItemID else { return }"), "note writes are bound to the current selected item")
expect(workspaceStoreSource.contains("func insertMarkdownSnippet(_ markdown: String)")
    && workspaceStoreSource.contains("layout = .immersiveWriting")
    && workspaceStoreSource.contains("showRightPane = true")
    && workspaceStoreSource.contains("noteRenderMode = .rich"), "markdown snippet insertion reveals the rich writing surface")
expect(!workspaceStoreSource.contains("当前页提示"), "quiet insight avoids old page alert title")
expect(workspaceStoreSource.contains("阅读线索"), "quiet insight uses margin-note language")
let notesAgentSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/NotesAgentView.swift")
let notesAgentSource = (try? String(contentsOf: notesAgentSourceURL, encoding: .utf8)) ?? ""
expect(notesAgentSource.contains("compactHovering") && notesAgentSource.contains("compactBackground"), "compact quiet insight uses a light margin-note surface")
expect(notesAgentSource.contains("let itemID = store.selectedItemID") && notesAgentSource.contains("store.updateNote(value, for: itemID)"), "rich note editor writes through selected item guard")
expect(notesAgentSource.contains("ContextRailLine") && notesAgentSource.contains(".onHover"), "context rails keep hover motion")
expect(notesAgentSource.contains("struct ContextRailItem: Identifiable") && notesAgentSource.contains("Button(action: action)"), "context rails expose actionable rows")
expect(notesAgentSource.contains(".accessibilityLabel(Text(item.help ?? item.title))") && notesAgentSource.contains(".help(item.help ?? item.title)"), "context rail actions explain their intent")
expect(notesAgentSource.contains("var edge: HorizontalEdge = .trailing") && notesAgentSource.contains("edge == .leading ? -3 : 3"), "context rails move inward from either side")
expect(!notesAgentSource.contains(".id(expanded)"), "selection agent expands without forcing a hard view identity reset")
expect(contentViewSource.contains("edge: .leading") && contentViewSource.contains("edge: .trailing"), "immersive rails declare their content-facing edge")
expect(contentViewSource.contains("conversationSourceRailItems") && contentViewSource.contains("conversationTargetRailItems") && contentViewSource.contains("writingAssistRailItems"), "immersive rails wire role-specific actions")
expect(contentViewSource.contains("store.appendSelectionToNote()") && contentViewSource.contains("store.copyCurrentReference()") && contentViewSource.contains("prepareAgentDraft"), "immersive rails connect to existing note, reference, and agent actions")
expect(!notesAgentSource.contains("Agent 抽屉"), "agent drawer avoids engineering labels")
expect(!notesAgentSource.contains("Agent 只在右下角待命"), "corner agent avoids explanatory placeholder copy")
expect(!notesAgentSource.contains("魏碑会优先读取材料"), "agent empty state avoids product-explainer copy")
expect(notesAgentSource.contains("AgentStarterChip") && notesAgentSource.contains("hovering ? -1 : 0"), "agent starter chips keep subtle hover motion")
expect(notesAgentSource.contains("emptyNoteHint") && notesAgentSource.contains("开始记录当前材料") && notesAgentSource.contains(".allowsHitTesting(false)"), "blank note editor shows a light nonblocking cue")
expect(notesAgentSource.contains("prompt: Text(\"问当前材料\").foregroundStyle(WeiBeiTheme.tertiaryInk)"), "corner agent input placeholder stays readable")
expect(notesAgentSource.contains("private var agentInputTray: some View"), "agent pane uses a dedicated input tray")
expect(notesAgentSource.contains("WeiBeiGlassHeaderBackground(") && notesAgentSource.contains("WeiBeiTheme.glassTint.opacity(0.66)"), "agent input tray uses paper glass fade instead of a hard white strip")
expect(!notesAgentSource.contains(".disabled(store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)") && !notesAgentSource.contains(".disabled(!canSend)"), "agent drawer and corner hide empty send actions instead of showing disabled buttons")
expect(notesAgentSource.contains("agentToolButton(\"整理\", help: \"整理笔记\"") && notesAgentSource.contains("agentToolButton(\"写入\", help: \"写入笔记\""), "agent toolbar uses short readable action labels")
expect(notesAgentSource.contains("private func iconButton(_ systemName: String, help: String") && notesAgentSource.contains(".accessibilityLabel(Text(help))"), "floating icon buttons carry semantic labels")
expect(notesAgentSource.contains(".help(\"收起右下角 Agent\")"), "corner agent close button explains its action")
expect(commandPaletteSource.contains("{{WEIBEI_SELECT_START}}") && commandPaletteSource.contains("插入矩阵公式"), "markdown command templates keep an editable landing point")
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
