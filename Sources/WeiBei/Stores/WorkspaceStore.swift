import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var importedItems: [StudyItem] = []
    @Published var selectedItemID: String?
    @Published var noteText = ""
    @Published var agentDraft = ""
    @Published var messages: [AgentMessage] = []
    @Published var isAskingAgent = false
    @Published var showLibrary = true
    @Published var showRightPane = true
    @Published var commandPalettePresented = false
    @Published var librarySearch = ""
    @Published var readerSearch = ""
    @Published var showReaderSearch = false
    @Published var readerLocationTitle: String?
    @Published var readerPageIndex = 0
    @Published var readerTargetPageIndex: Int?
    @Published var focusedPane: PaneFocus = .reader
    @Published var focusRequest = 0
    @Published var layout: WorkspaceLayout = .documentAgentNotes
    @Published var agentSurface: AgentSurface = .bottomDrawer
    @Published var noteRenderMode: NoteRenderMode = .rich
    @Published var showQuietInsight = true
    @Published var generatedQuietInsight: QuietInsight?
    @Published var isGeneratingQuietInsight = false
    @Published var floatingSelectionPrompt = "当前选区"
    @Published var pinnedFloatingAgent = false
    @Published var selectionContext: SelectionContext?
    @Published var selectionAttachments: [SelectionContext] = []
    @Published var selectionAnchor: CGPoint?
    @Published var noteEditorCommand: NoteEditorCommand?
    @Published var noteFileError: String?
    @Published var modelName: String = ProcessInfo.processInfo.environment["WEIBEI_OPENAI_MODEL"] ?? "gpt-5.1"
    @Published var openAIAPIKey: String = OpenAIAPIKeyStore.load()
    @Published var openAIKeyStatus: String?
    @Published var appearanceMode: WeiBeiAppearanceMode = .paper
    @Published private var backNavigationStack: [NavigationSnapshot] = []
    @Published private var forwardNavigationStack: [NavigationSnapshot] = []

    private var notesByItemID: [String: String] = [:]
    private let storageURL: URL
    private var quietInsightSignature = ""
    private var isRestoringNavigation = false

    private struct NavigationSnapshot: Equatable {
        var selectedItemID: String?
        var layout: WorkspaceLayout
        var showLibrary: Bool
        var showRightPane: Bool
        var agentSurface: AgentSurface
        var noteRenderMode: NoteRenderMode
        var showReaderSearch: Bool
        var readerSearch: String
        var readerPageIndex: Int
        var focusedPane: PaneFocus
    }

    private var lastUsableAgentAnswer: AgentMessage? {
        messages.last { $0.isUsableAgentAnswer }
    }

    private static let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let sampleItems: [StudyItem] = WorkspaceStore.makeSampleItems()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("WeiBei", isDirectory: true)
        storageURL = folder.appendingPathComponent("workspace.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        if selectedItemID == nil {
            select(itemID: sampleItems[0].id)
        }
    }

    var allItems: [StudyItem] {
        sampleItems + importedItems
    }

    var filteredItems: [StudyItem] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }
        return allItems.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
                || $0.kind.label.localizedCaseInsensitiveContains(query)
        }
    }

    var navigableItems: [StudyItem] {
        let materialItems = allItems.filter { !$0.isNotebookNote }
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return materialItems }
        return materialItems.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
                || $0.kind.label.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedItem: StudyItem? {
        allItems.first { $0.id == selectedItemID }
    }

    var selectedMaterialItem: StudyItem? {
        guard let item = selectedItem, !item.isNotebookNote else { return nil }
        return item
    }

    var hasSelectedMaterial: Bool {
        selectedMaterialItem != nil
    }

    var canNavigateBack: Bool {
        !backNavigationStack.isEmpty
    }

    var canNavigateForward: Bool {
        !forwardNavigationStack.isEmpty
    }

    func navigateBackInWorkspace() {
        guard let previous = backNavigationStack.popLast() else { return }
        persistCurrentNote()
        forwardNavigationStack.append(navigationSnapshot())
        applyNavigationSnapshot(previous)
    }

    func navigateForwardInWorkspace() {
        guard let next = forwardNavigationStack.popLast() else { return }
        persistCurrentNote()
        backNavigationStack.append(navigationSnapshot())
        applyNavigationSnapshot(next)
    }

    var canUseSelectedMarkdownAsNotebookNote: Bool {
        selectedItem?.canBecomeNotebookNote == true
    }

    var currentMarkdownBaseURL: URL? {
        if let url = selectedItem?.url {
            return url.deletingLastPathComponent()
        }
        return appOwnedFilesDirectory()
    }

    var currentAttachmentDirectory: URL? {
        if let url = selectedItem?.url {
            return url.deletingLastPathComponent().appendingPathComponent(".weibei-assets", isDirectory: true)
        }
        return appOwnedFilesDirectory().appendingPathComponent("Attachments", isDirectory: true)
    }

    var selectedContextText: String {
        guard let item = selectedMaterialItem else { return "" }
        if let text = DocumentTextExtractor.text(for: item) {
            return text
        }
        return sampleText(for: item)
    }

    var selectedMaterialTitle: String {
        selectedMaterialItem?.title ?? "未选择材料"
    }

    var agentMessageSourceTitle: String? {
        hasSelectedMaterial ? currentReferenceTitle : selectedItem?.title
    }

    var currentReferenceTitle: String {
        readerLocationTitle ?? selectedMaterialItem?.title ?? selectedItem?.title ?? "当前笔记"
    }

    var hasSelectionAttachments: Bool {
        !selectionAttachments.isEmpty
    }

    var agentSelectionTitle: String? {
        guard !selectionAttachments.isEmpty else { return nil }
        if selectionAttachments.count == 1 {
            return selectionAttachments[0].ownerTitle
        }
        return "\(selectionAttachments.count) 个已选文本片段"
    }

    var agentSelectionText: String? {
        guard !selectionAttachments.isEmpty else { return nil }
        return selectionAttachments.enumerated().map { index, selection in
            """
            片段 \(index + 1)（来源：\(selection.ownerTitle)）：
            \(selection.text)
            """
        }.joined(separator: "\n\n")
    }

    var canCopyReference: Bool {
        hasSelectionAttachments || selectionContext != nil || hasSelectedMaterial || selectedItem?.isNotebookNote == true
    }

    var copyReferenceActionTitle: String {
        if hasSelectionAttachments || selectionContext != nil { return "复制选区引用" }
        if hasSelectedMaterial { return "复制资料引用" }
        return "复制笔记引用"
    }

    var sendAgentActionTitle: String {
        "发送问题"
    }

    var agentNoteTitle: String {
        if selectedItem?.isNotebookNote == true {
            return selectedItem?.title ?? "当前笔记"
        }
        if let title = selectedMaterialItem?.title {
            return "\(title) 的笔记"
        }
        return "当前笔记"
    }

    var agentPromptScope: String {
        hasSelectedMaterial ? "当前材料和当前笔记" : "当前笔记"
    }

    var agentInputPrompt: String {
        if hasSelectionAttachments {
            return "追问已选文本片段"
        }
        return hasSelectedMaterial ? "问当前材料" : "问当前笔记"
    }

    var selectionPromptScope: String {
        selectionContext?.source == .note ? "当前笔记" : agentPromptScope
    }

    var canApplyAgentAnswer: Bool {
        lastUsableAgentAnswer != nil
    }

    var lastUsableAgentAnswerID: UUID? {
        lastUsableAgentAnswer?.id
    }

    var canReplaceNoteSelection: Bool {
        canApplyAgentAnswer && selectionContext?.isReplaceableNoteSelection == true
    }

    var quietInsight: QuietInsight {
        if isGeneratingQuietInsight {
            return QuietInsight(body: hasSelectedMaterial ? "正在静默阅读当前材料和笔记。" : "正在静默阅读当前笔记。", noteBlock: "")
        }
        if let generatedQuietInsight {
            return generatedQuietInsight
        }
        return QuietInsight.make(
            materialTitle: quietInsightReferenceTitle,
            materialText: selectedContextText,
            noteText: noteText,
            selectionText: selectionContext?.text
        )
    }

    var quietInsightTitle: String {
        return "阅读线索"
    }

    var quietInsightSourceLabel: String {
        if selectionContext != nil {
            return "来自当前选区"
        }
        if !hasSelectedMaterial {
            return "来自当前笔记"
        }
        return generatedQuietInsight == nil ? "来自当前材料" : "来自材料和笔记"
    }

    var openAIKeyHelpText: String {
        if !Self.environmentValue("OPENAI_API_KEY").isEmpty {
            return "正在使用本机环境密钥。保存的密钥会在没有环境密钥时接管。"
        }
        if !OpenAIAPIKeyStore.load().isEmpty {
            return "密钥已保存，可直接用于对话。"
        }
        return "未保存密钥。保存后对话会结合\(agentPromptScope)，并在有已选文本片段时一并作答。"
    }

    func select(itemID: String?) {
        persistCurrentNote()
        let itemChanged = selectedItemID != itemID
        if itemChanged && selectedItemID != nil {
            recordNavigationPoint()
        }
        selectedItemID = itemID
        if itemChanged {
            clearUnpinnedFloatingSelection(keepContext: false)
            selectionAttachments = []
            readerPageIndex = 0
        }
        readerLocationTitle = selectedMaterialItem?.title
        clearReaderSearchIfNeeded()
        noteText = noteText(for: selectedItem)
        messages = []
        clearGeneratedQuietInsight()
        refreshQuietInsightIfNeeded()
        save()
    }

    func selectAdjacentItem(step: Int) {
        let ids = navigableItems.map(\.id)
        guard let nextID = LibraryNavigator.adjacentID(in: ids, selectedID: selectedItemID, step: step) else { return }
        select(itemID: nextID)
        focus(.reader)
    }

    func updateNote(_ value: String) {
        noteText = value
        clearGeneratedQuietInsight()
        persistCurrentNote()
        save()
    }

    func updateNote(_ value: String, for itemID: String?) {
        guard itemID == selectedItemID else { return }
        updateNote(value)
    }

    func resetNote() {
        createNotebookNote()
        focus(.notes)
    }

    func focus(_ pane: PaneFocus) {
        if pane == .library {
            if !showLibrary {
                recordNavigationPoint()
                clearUnpinnedFloatingSelection()
            }
            showLibrary = true
        }
        if pane == .agent {
            if layout == .documentNotesSplit, agentSurface == .hidden {
                agentSurface = .bottomDrawer
            } else if layout == .immersiveReading || layout == .immersiveWriting {
                if agentSurface == .hidden
                    || agentSurface == .quietInsight
                    || (agentSurface == .selectionFloat && !canUseSelectionAgentSurface) {
                    agentSurface = .cornerPanel
                    showQuietInsight = false
                }
            }
        }
        collapseSelectionFloatIntoConversationIfVisible()
        focusedPane = pane
        focusRequest += 1
    }

    func toggleLibrary() {
        recordNavigationPoint()
        showLibrary.toggle()
        clearUnpinnedFloatingSelection()
        focus(showLibrary ? .library : .reader)
        save()
    }

    func revealLibrary() {
        if !showLibrary {
            recordNavigationPoint()
            clearUnpinnedFloatingSelection()
        }
        showLibrary = true
        focus(.library)
        save()
    }

    func toggleRightPane() {
        guard layout.hasCollapsibleRightPane else { return }
        recordNavigationPoint()
        showRightPane.toggle()
        clearUnpinnedFloatingSelection()
        focus(showRightPane ? rightPaneRevealFocus : .reader)
        save()
    }

    func revealRightPane(focusing pane: PaneFocus = .notes) {
        guard layout.hasCollapsibleRightPane else { return }
        if !showRightPane {
            recordNavigationPoint()
            clearUnpinnedFloatingSelection()
        }
        showRightPane = true
        focus(pane)
        save()
    }

    func revealReaderSearch() {
        guard hasSelectedMaterial else {
            clearReaderSearchIfNeeded()
            return
        }
        if !showReaderSearch || layout == .immersiveConversation || layout == .immersiveWriting {
            recordNavigationPoint()
        }
        if layout == .immersiveConversation || layout == .immersiveWriting {
            setLayout(.immersiveReading)
        }
        showReaderSearch = true
        focus(.reader)
    }

    func hideReaderSearch() {
        if showReaderSearch || !readerSearch.isEmpty {
            recordNavigationPoint()
        }
        showReaderSearch = false
        readerSearch = ""
        clearUnpinnedFloatingSelection(keepContext: false)
        focus(.reader)
    }

    func updateReaderLocationTitle(_ title: String?) {
        let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        readerLocationTitle = cleaned.isEmpty ? selectedMaterialItem?.title : cleaned
    }

    func updateReaderPageIndex(_ index: Int) {
        readerPageIndex = max(index, 0)
    }

    func recordReaderPageNavigationPoint() {
        guard selectedMaterialItem?.kind == .pdf else { return }
        recordNavigationPoint()
    }

    var canOpenSelectedSourceReference: Bool {
        guard selectionContext?.isNoteSelection == true else { return false }
        return sourceReferenceItem(from: selectionContext?.text) != nil
    }

    func openSelectedSourceReference() {
        guard let text = selectionContext?.text else { return }
        openSourceReference(text)
    }

    @discardableResult
    func openSourceReference(_ rawReference: String) -> Bool {
        guard let item = sourceReferenceItem(from: rawReference) else { return false }
        let reference = SourceReferenceTitle.parse(rawReference)
        select(itemID: item.id)
        readerTargetPageIndex = item.kind == .pdf ? reference.pageIndex : nil
        focus(.reader)
        return true
    }

    func setLayout(_ layout: WorkspaceLayout) {
        if self.layout != layout {
            recordNavigationPoint()
            clearUnpinnedFloatingSelection()
        }
        self.layout = layout
        let nextFocus: PaneFocus = switch layout {
        case .immersiveConversation:
            .agent
        case .immersiveReading:
            .reader
        case .immersiveWriting:
            .notes
        default:
            .reader
        }
        if layout == .immersiveReading {
            showQuietInsight = agentSurface == .quietInsight
        }
        if layout == .immersiveConversation {
            showReaderSearch = false
            readerSearch = ""
        }
        focus(nextFocus)
        refreshQuietInsightIfNeeded()
        save()
    }

    var canUseSelectionAgentSurface: Bool {
        SelectionFloatingAgentPlacement.isVisible(
            surface: .selectionFloat,
            hasSelection: selectionContext != nil,
            hasAnchor: selectionAnchor != nil,
            pinned: pinnedFloatingAgent
        )
    }

    var hasPrimaryConversationPaneVisible: Bool {
        switch layout {
        case .documentAgentNotes, .documentNotesAgent:
            return showRightPane
        case .immersiveConversation:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveWriting:
            return false
        }
    }

    var isConversationSurfaceVisible: Bool {
        if hasPrimaryConversationPaneVisible {
            return true
        }
        switch layout {
        case .documentAgentNotes, .documentNotesAgent:
            return false
        case .immersiveConversation:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveWriting:
            return agentSurface == .bottomDrawer || agentSurface == .cornerPanel
        }
    }

    var canShowSelectionPromptSurface: Bool {
        hasPrimaryConversationPaneVisible || !isConversationSurfaceVisible
    }

    var visibleAgentSurfaces: [AgentSurface] {
        AgentSurface.allCases.filter { surface in
            surface != .selectionFloat || canUseSelectionAgentSurface
        }
    }

    func setAgentSurface(_ surface: AgentSurface) {
        guard surface != .selectionFloat || canUseSelectionAgentSurface else { return }
        guard agentSurface != surface else { return }
        recordNavigationPoint()
        agentSurface = surface
        showQuietInsight = surface == .quietInsight
        if surface == .quietInsight {
            refreshQuietInsightIfNeeded()
        }
        save()
    }

    func dismissFloatingSelectionAgent() {
        guard agentSurface == .selectionFloat || selectionContext != nil || pinnedFloatingAgent else { return }
        agentSurface = .hidden
        selectionContext = nil
        selectionAnchor = nil
        pinnedFloatingAgent = false
        agentDraft = ""
        save()
    }

    func setNoteRenderMode(_ mode: NoteRenderMode) {
        if noteRenderMode != mode || layout == .immersiveReading || layout == .immersiveConversation || (layout.hasCollapsibleRightPane && !showRightPane) {
            recordNavigationPoint()
        }
        if layout == .immersiveReading || layout == .immersiveConversation {
            clearUnpinnedFloatingSelection()
            layout = .immersiveWriting
        }
        if layout.hasCollapsibleRightPane {
            if !showRightPane {
                clearUnpinnedFloatingSelection()
            }
            showRightPane = true
        }
        noteRenderMode = mode
        focus(.notes)
        save()
    }

    private func revealRichWritingSurface() {
        if layout == .immersiveReading || layout == .immersiveConversation {
            clearUnpinnedFloatingSelection()
            layout = .immersiveWriting
        }
        if layout.hasCollapsibleRightPane {
            if !showRightPane {
                clearUnpinnedFloatingSelection()
            }
            showRightPane = true
        }
        noteRenderMode = .rich
    }

    private func recordNavigationPoint() {
        guard !isRestoringNavigation else { return }
        let snapshot = navigationSnapshot()
        guard backNavigationStack.last != snapshot else { return }
        backNavigationStack.append(snapshot)
        if backNavigationStack.count > 80 {
            backNavigationStack.removeFirst(backNavigationStack.count - 80)
        }
        forwardNavigationStack.removeAll()
    }

    private func navigationSnapshot() -> NavigationSnapshot {
        NavigationSnapshot(
            selectedItemID: selectedItemID,
            layout: layout,
            showLibrary: showLibrary,
            showRightPane: showRightPane,
            agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface,
            noteRenderMode: noteRenderMode,
            showReaderSearch: showReaderSearch,
            readerSearch: readerSearch,
            readerPageIndex: readerPageIndex,
            focusedPane: focusedPane
        )
    }

    private func applyNavigationSnapshot(_ snapshot: NavigationSnapshot) {
        isRestoringNavigation = true
        defer { isRestoringNavigation = false }
        selectedItemID = snapshot.selectedItemID
        layout = snapshot.layout
        showLibrary = snapshot.showLibrary
        showRightPane = snapshot.showRightPane
        agentSurface = snapshot.agentSurface == .selectionFloat ? .hidden : snapshot.agentSurface
        noteRenderMode = snapshot.noteRenderMode
        showReaderSearch = snapshot.showReaderSearch
        readerSearch = snapshot.readerSearch
        readerPageIndex = snapshot.readerPageIndex
        focusedPane = snapshot.focusedPane
        noteText = noteText(for: selectedItem)
        readerLocationTitle = selectedMaterialItem?.title
        readerTargetPageIndex = selectedMaterialItem?.kind == .pdf ? snapshot.readerPageIndex : nil
        messages = []
        showQuietInsight = agentSurface == .quietInsight
        clearUnpinnedFloatingSelection(keepContext: false)
        clearReaderSearchIfNeeded()
        refreshQuietInsightIfNeeded()
        save()
    }

    func insertMarkdownSnippet(_ markdown: String) {
        revealRichWritingSurface()
        noteEditorCommand = NoteEditorCommand(kind: .insertMarkdown, markdown: markdown)
        focus(.notes)
        save()
    }

    func handleAppShortcut(_ event: NSEvent) -> Bool {
        guard let key = Self.shortcutKey(from: event) else { return false }
        return handleAppShortcut(key: key, modifiers: event.modifierFlags.intersection(Self.shortcutModifierMask))
    }

    func handleAppShortcut(key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers == [.control, .option] {
            switch key {
            case "1":
                animatePanelChange { setAgentSurface(.bottomDrawer) }
            case "2":
                animatePanelChange { setAgentSurface(.cornerPanel) }
            case "3":
                guard canUseSelectionAgentSurface else { return false }
                animatePanelChange { setAgentSurface(.selectionFloat) }
            case "4":
                animatePanelChange { setAgentSurface(.quietInsight) }
            case "0":
                animatePanelChange { setAgentSurface(.hidden) }
            default:
                return false
            }
            return true
        }

        if modifiers == [.command, .option] {
            switch key {
            case "1":
                animateLayoutChange { setLayout(.documentAgentNotes) }
            case "2":
                animateLayoutChange { setLayout(.documentNotesAgent) }
            case "3":
                animateLayoutChange { setLayout(.documentNotesSplit) }
            case "r":
                animateLayoutChange { setLayout(.immersiveReading) }
            case "a":
                animateLayoutChange { setLayout(.immersiveConversation) }
            case "n":
                animateLayoutChange { setLayout(.immersiveWriting) }
            case "t":
                animatePanelChange { toggleAppearanceMode() }
            case "up":
                animateLayoutChange { selectAdjacentItem(step: -1) }
            case "down":
                animateLayoutChange { selectAdjacentItem(step: 1) }
            default:
                return false
            }
            return true
        }

        if modifiers == [.control, .command] {
            switch key {
            case "1":
                animatePanelChange { setNoteRenderMode(.rich) }
            case "2":
                animatePanelChange { setNoteRenderMode(.split) }
            case "3":
                animatePanelChange { setNoteRenderMode(.source) }
            case "4":
                animatePanelChange { setNoteRenderMode(.preview) }
            default:
                return false
            }
            return true
        }

        if modifiers == [.command, .shift] {
            switch key {
            case "a":
                guard canApplyAgentAnswer else { return false }
                animatePanelChange { applyLastAgentAnswerToNote() }
            case "r":
                guard canReplaceNoteSelection else { return false }
                animatePanelChange { replaceSelectionWithLastAgentAnswer() }
            case "e":
                guard canApplyAgentAnswer else { return false }
                animatePanelChange { applyAgentPatchToEditor() }
            case "c":
                guard canCopyReference else { return false }
                copyCurrentReference()
            default:
                return false
            }
            return true
        }

        if modifiers == [.command] {
            switch key {
            case "[":
                guard canNavigateBack else { return false }
                animateLayoutChange { navigateBackInWorkspace() }
            case "]":
                guard canNavigateForward else { return false }
                animateLayoutChange { navigateForwardInWorkspace() }
            case "1":
                animateLayoutChange { focus(.library) }
            case "2":
                animateLayoutChange { focus(.reader) }
            case "3":
                animateLayoutChange { focus(.notes) }
            case "4":
                animateLayoutChange { focus(.agent) }
            case "b":
                animateLayoutChange { toggleLibrary() }
            case "j":
                guard layout.hasCollapsibleRightPane else { return false }
                animateLayoutChange { toggleRightPane() }
            case "k":
                animatePanelChange { commandPalettePresented.toggle() }
            case "f":
                guard hasSelectedMaterial else { return false }
                animatePanelChange { revealReaderSearch() }
            case "return":
                guard !isAskingAgent && !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                Task { await askAgent() }
            default:
                return false
            }
            return true
        }

        return false
    }

    private func animateLayoutChange(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.layout) {
            action()
        }
    }

    private func animatePanelChange(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.panel) {
            action()
        }
    }

    private func clearReaderSearchIfNeeded() {
        guard !hasSelectedMaterial else { return }
        showReaderSearch = false
        readerSearch = ""
    }

    private static func shortcutKey(from event: NSEvent) -> String? {
        switch event.keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "o"
        case 32: return "u"
        case 33: return "["
        case 34: return "i"
        case 35: return "p"
        case 37: return "l"
        case 38: return "j"
        case 40: return "k"
        case 45: return "n"
        case 46: return "m"
        case 36, 76: return "return"
        case 125: return "down"
        case 126: return "up"
        default:
            return event.charactersIgnoringModifiers?.lowercased()
        }
    }

    func updateModelName(_ value: String) {
        modelName = value
        save()
    }

    func toggleAppearanceMode() {
        appearanceMode = appearanceMode.toggled
        save()
    }

    func setAppearanceMode(_ mode: WeiBeiAppearanceMode) {
        guard appearanceMode != mode else { return }
        appearanceMode = mode
        save()
    }

    func saveOpenAIAPIKey() {
        do {
            let cleanedKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)
            try OpenAIAPIKeyStore.save(cleanedKey)
            openAIAPIKey = cleanedKey
            openAIKeyStatus = cleanedKey.isEmpty ? "已清除密钥。" : "密钥已保存。"
        } catch {
            openAIKeyStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    func clearOpenAIAPIKey() {
        openAIAPIKey = ""
        saveOpenAIAPIKey()
    }

    func importFilesFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择学习资料"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .pdf,
            .html,
            .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText
        ]

        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    func importFiles(_ urls: [URL]) {
        let existing = Set(importedItems.compactMap(\.urlPath))
        let newItems = urls
            .filter { !existing.contains($0.path) }
            .map { url in
                StudyItem(
                    id: "file:\(url.path)",
                    title: url.deletingPathExtension().lastPathComponent,
                    subtitle: url.lastPathComponent,
                    kind: StudyItemKind.detect(from: url),
                    urlPath: url.path,
                    isSample: false
                )
            }

        importedItems.append(contentsOf: newItems)
        if let first = newItems.first {
            select(itemID: first.id)
        } else {
            save()
        }
    }

    func openOrCreateWikiNote(title rawTitle: String) {
        let title = WikiLink.targetTitle(from: rawTitle)
        guard !title.isEmpty else { return }

        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)
        let fileName = "\(Self.safeFileStem(title)).md"
        let url = notesDirectory.appendingPathComponent(fileName)

        if let index = importedItems.firstIndex(where: { $0.urlPath == url.path }) {
            importedItems[index].isNotebookNote = true
            select(itemID: importedItems[index].id)
            noteFileError = "已打开双链笔记：\(importedItems[index].subtitle)"
            save()
            return
        }

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
            }

            let item = StudyItem(
                id: "file:\(url.path)",
                title: title,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                isSample: false,
                isNotebookNote: true
            )
            if !importedItems.contains(where: { $0.urlPath == url.path }) {
                importedItems.append(item)
            }
            select(itemID: item.id)
            noteFileError = "已创建双链笔记：\(url.lastPathComponent)"
        } catch {
            noteFileError = "无法创建双链笔记：\(error.localizedDescription)"
        }
    }

    private func createNotebookNote() {
        persistCurrentNote()
        let title = "新笔记"
        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let url = nextNotebookNoteURL(in: notesDirectory, title: title)
            let item = StudyItem(
                id: "file:\(url.path)",
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                isSample: false,
                isNotebookNote: true
            )
            try defaultNote(for: item).write(to: url, atomically: true, encoding: .utf8)
            importedItems.append(item)
            revealRichWritingSurface()
            select(itemID: item.id)
            noteFileError = "已创建笔记：\(url.lastPathComponent)"
        } catch {
            noteFileError = "无法创建笔记：\(error.localizedDescription)"
        }
    }

    func useSelectedMarkdownAsNotebookNote() {
        guard let selectedItemID,
              let index = importedItems.firstIndex(where: { $0.id == selectedItemID && $0.canBecomeNotebookNote }) else { return }
        persistCurrentNote()
        importedItems[index].isNotebookNote = true
        noteText = noteText(for: importedItems[index])
        revealRichWritingSurface()
        focus(.notes)
        save()
    }

    func copyCurrentReference() {
        let selection = selectionContext?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference: String
        if !selectionAttachments.isEmpty {
            reference = selectionAttachments
                .map { quotedReferenceBlock(text: $0.text, sourceTitle: $0.ownerTitle) }
                .joined(separator: "\n\n")
        } else if let selectionContext, let selection, !selection.isEmpty {
            reference = quotedReferenceBlock(text: selection, sourceTitle: selectionContext.ownerTitle)
        } else {
            guard selectedMaterialItem != nil || selectedItem?.isNotebookNote == true else { return }
            reference = "来源：\(currentReferenceTitle)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference, forType: .string)
    }

    func updateSelection(_ text: String, source: SelectionSource, anchor: CGPoint? = nil, ownerTitle: String? = nil, isEditable: Bool = true) {
        let cleaned = MarkdownSelectionSanitizer.clean(text)
        guard Self.hasMeaningfulSelectionCharacter(cleaned) else {
            clearUnpinnedFloatingSelection(keepContext: false)
            return
        }
        clearGeneratedQuietInsight()
        let cleanedOwnerTitle = ownerTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOwnerTitle = (cleanedOwnerTitle?.isEmpty == false ? cleanedOwnerTitle : nil) ?? selectionOwnerTitle(for: source)
        let shouldRevealSelectionPrompt = canShowSelectionPromptSurface
        withAnimation(WeiBeiMotion.panel) {
            selectionContext = SelectionContext(
                text: Self.boundedSelectionText(cleaned),
                source: source,
                ownerTitle: resolvedOwnerTitle,
                isEditable: isEditable
            )
            selectionAnchor = anchor
            floatingSelectionPrompt = selectionContext?.label ?? "当前选区"
            pinnedFloatingAgent = false
            if shouldRevealSelectionPrompt {
                agentSurface = .selectionFloat
                showQuietInsight = false
            } else if agentSurface == .selectionFloat {
                agentSurface = .hidden
            }
        }
    }

    func removeSelectionAttachment(id: UUID) {
        withAnimation(WeiBeiMotion.panel) {
            selectionAttachments.removeAll { $0.id == id }
        }
    }

    private func addSelectionAttachment(_ selection: SelectionContext) {
        let cleanedText = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.hasMeaningfulSelectionCharacter(cleanedText) else { return }
        if let existingIndex = selectionAttachments.firstIndex(where: {
            $0.ownerTitle == selection.ownerTitle
                && $0.source == selection.source
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == cleanedText
        }) {
            selectionAttachments.remove(at: existingIndex)
        }
        selectionAttachments.append(selection)
        let maxAttachments = 8
        if selectionAttachments.count > maxAttachments {
            selectionAttachments.removeFirst(selectionAttachments.count - maxAttachments)
        }
    }

    private static func hasMeaningfulSelectionCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private func selectionOwnerTitle(for source: SelectionSource) -> String {
        if source == .note || selectedItem?.isNotebookNote == true {
            return selectedItem?.title ?? "当前笔记"
        }
        return currentReferenceTitle
    }

    private static func boundedSelectionText(_ text: String) -> String {
        let limit = 2_000
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit)
        if let boundary = prefix.lastIndex(where: { String($0).rangeOfCharacter(from: .whitespacesAndNewlines) != nil }),
           boundary > prefix.startIndex {
            return String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix)
    }

    private func sourceReferenceItem(from rawReference: String?) -> StudyItem? {
        let reference = SourceReferenceTitle.parse(rawReference ?? "")
        guard !reference.title.isEmpty else { return nil }
        return allItems.first {
            !$0.isNotebookNote
                && ($0.title == reference.title || $0.subtitle == reference.title)
        }
    }

    func askToOrganizeNote() {
        agentDraft = "请根据\(agentPromptScope)，把笔记整理成更清晰的大纲，保留来源信息，并标出缺少证据的位置。"
        Task { await askAgent() }
    }

    func askSelection() {
        if let selectionContext {
            withAnimation(WeiBeiMotion.panel) {
                addSelectionAttachment(selectionContext)
                floatingSelectionPrompt = selectionContext.label
                if isConversationSurfaceVisible {
                    collapseSelectionFloatIntoConversationIfVisible()
                    focus(.agent)
                } else {
                    agentSurface = .selectionFloat
                    showQuietInsight = false
                    focus(.agent)
                }
            }
        } else {
            withAnimation(WeiBeiMotion.panel) {
                agentDraft = "请根据\(agentPromptScope)，帮我梳理重点和可追问的问题。"
                if layout == .immersiveReading || layout == .documentNotesSplit {
                    agentSurface = .cornerPanel
                }
                focus(.agent)
            }
        }
    }

    func appendSelectionToNote() {
        guard let selectionContext else { return }
        let block = """

        \(quotedReferenceBlock(text: selectionContext.text, sourceTitle: selectionContext.ownerTitle))
        """
        updateNote(noteText + block)
        focus(.notes)
    }

    private func quotedReferenceBlock(text: String, sourceTitle: String) -> String {
        let quoted = MarkdownSelectionSanitizer.clean(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return """
        > [!quote] 选区摘录
        >
        \(quoted)
        >
        > 来源：\(sourceTitle)
        """
    }

    func acceptQuietInsight() {
        guard !quietInsight.noteBlock.isEmpty else { return }
        updateNote(noteText + "\n\n\(quietInsight.noteBlock)\n")
        showQuietInsight = false
        focus(.notes)
    }

    func askQuietInsight() {
        let evidenceText = hasSelectedMaterial ? "未在材料中确认" : "未在笔记或选区中确认"
        agentDraft = """
        请根据这条阅读线索继续解释，并结合\(agentPromptScope)回答。没有证据就说\(evidenceText)。

        阅读线索：
        \(quietInsight.body)
        """
        showQuietInsight = false
        agentSurface = .cornerPanel
        focus(.agent)
    }

    func refreshQuietInsight() async {
        let materialTitle = quietInsightReferenceTitle
        let materialText = selectedContextText
        let currentNoteText = noteText
        let selectionText = selectionContext?.text
        let contextScope = hasSelectedMaterial ? "当前材料、当前选区和当前笔记" : "当前选区和当前笔记"
        let evidenceText = hasSelectedMaterial ? "如果材料没有证据，就直接说未在材料中确认。" : "如果笔记和选区没有证据，就直接说未在笔记或选区中确认。"
        let signature = makeQuietInsightSignature(materialText: materialText, noteText: currentNoteText, selectionText: selectionText)
        guard signature != quietInsightSignature else { return }
        guard let credential = resolvedOpenAIAPIKey() else {
            generatedQuietInsight = nil
            return
        }

        isGeneratingQuietInsight = true
        defer { isGeneratingQuietInsight = false }

        do {
            let client = OpenAIResponsesClient(apiKey: credential.key, model: resolvedModelName)
            let answer = try await client.ask(
                question: "请静默阅读\(contextScope)，只输出一条最值得提示给用户的洞察。要温和、短、可执行；\(evidenceText)",
                materialTitle: materialTitle,
                materialText: materialText,
                noteTitle: agentNoteTitle,
                noteText: currentNoteText,
                selectionTitle: selectionContext?.ownerTitle,
                selectionText: selectionText,
                recentMessages: []
            )
            guard signature == makeQuietInsightSignature(materialText: selectedContextText, noteText: noteText, selectionText: selectionContext?.text) else { return }
            generatedQuietInsight = QuietInsight.agent(materialTitle: materialTitle, answer: answer)
            quietInsightSignature = signature
        } catch {
            generatedQuietInsight = nil
        }
    }

    private var quietInsightReferenceTitle: String {
        selectionContext?.ownerTitle ?? (hasSelectedMaterial ? currentReferenceTitle : selectedItem?.title) ?? "当前笔记"
    }

    func applyLastAgentAnswerToNote() {
        guard let answer = lastUsableAgentAnswer else { return }
        let block = """

        ## 整理建议
        \(answer.text)
        """
        updateNote(noteText + block)
        focus(.notes)
    }

    func replaceSelectionWithLastAgentAnswer() {
        guard selectionContext?.isReplaceableNoteSelection == true,
              let answer = lastUsableAgentAnswer else { return }
        noteEditorCommand = NoteEditorCommand(kind: .replaceSelection, markdown: answer.text)
        focus(.notes)
    }

    func applyAgentPatchToEditor() {
        guard let answer = lastUsableAgentAnswer else { return }
        noteEditorCommand = NoteEditorCommand(kind: .applyAgentPatch, markdown: "\n## 整理建议\n\(answer.text)")
        focus(.notes)
    }

    func askAgent() async {
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAskingAgent else { return }

        guard let credential = resolvedOpenAIAPIKey() else {
            let notice = "未配置密钥。当前不会编造回答；设置密钥后会结合\(agentPromptScope)，并在有已选文本片段时一并作答。"
            openAIKeyStatus = notice
            if !messages.contains(where: { $0.role == .assistant && $0.source == "设置" && $0.text == notice }) {
                messages.append(AgentMessage(role: .assistant, text: notice, source: "设置"))
            }
            return
        }

        persistCurrentNote()
        let sentSelectionTitle = agentSelectionTitle
        let sentSelectionText = agentSelectionText
        agentDraft = ""
        if !selectionAttachments.isEmpty {
            withAnimation(WeiBeiMotion.panel) {
                selectionAttachments = []
            }
        }
        isAskingAgent = true
        let recentMessages = Array(messages.suffix(8))
        let sourceTitle = agentMessageSourceTitle
        messages.append(AgentMessage(role: .user, text: question, source: sourceTitle))

        do {
            let client = OpenAIResponsesClient(apiKey: credential.key, model: resolvedModelName)
            let answer = try await client.ask(
                question: question,
                materialTitle: currentReferenceTitle,
                materialText: selectedContextText,
                noteTitle: agentNoteTitle,
                noteText: noteText,
                selectionTitle: sentSelectionTitle,
                selectionText: sentSelectionText,
                recentMessages: recentMessages
            )
            messages.append(AgentMessage(role: .assistant, text: answer, source: sourceTitle))
        } catch {
            messages.append(AgentMessage(role: .assistant, text: "请求失败：\(error.localizedDescription)", source: sourceTitle))
        }

        isAskingAgent = false
    }

    func sampleHTML(for item: StudyItem?) -> String {
        guard item?.id == "sample-html" else { return sampleMarkdownHTML(for: item) }
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; background: #f1e4cf; color: #201b17; font: 18px/1.85 -apple-system, BlinkMacSystemFont, "Songti SC", serif; }
        main { max-width: 820px; margin: 0 auto; padding: 64px 72px 96px; background: rgba(247, 236, 217, .44); }
        h1 { font-size: 34px; line-height: 1.28; margin: 0 0 24px; letter-spacing: 0; word-break: keep-all; }
        h2 { margin-top: 44px; font-size: 25px; }
        code { background: rgba(127, 84, 58, .12); padding: 2px 6px; border-radius: 5px; }
        blockquote { border-left: 4px solid #9f3427; margin: 28px 0; padding: 12px 20px; background: rgba(159, 52, 39, .08); }
        </style>
        </head>
        <body>
        <main>
        <h1>利率的含义与分类</h1>
        <p>利率是资金使用价格的表达，也是金融市场配置资源时最敏感的信号之一。</p>
        <h2>名义利率与实际利率</h2>
        <p>名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。</p>
        <blockquote>学习时要同时记录概念、公式、例子和材料出处，避免只留下孤立结论。</blockquote>
        <h2>短期利率与长期利率</h2>
        <p>短期利率通常受流动性和政策操作影响，长期利率更能反映期限溢价与未来预期。</p>
        <h2>复习问题</h2>
        <p>为什么通货膨胀预期上升时，名义利率通常会上行？</p>
        </main>
        </body>
        </html>
        """
    }

    func sampleText(for item: StudyItem?) -> String {
        switch item?.id {
        case "sample-html":
            return "利率是资金使用价格的表达。名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。"
        case "sample-pdf":
            return "Mishkin 教材样例：金融体系通过降低交易成本和信息成本来改善资源配置。"
        case "sample-md":
            return noteText
        default:
            return ""
        }
    }

    private static func makeSampleItems() -> [StudyItem] {
        [
            StudyItem(id: "sample-html", title: "货币金融学课程 HTML", subtitle: "HTML 教程", kind: .html, urlPath: nil, isSample: true),
            StudyItem(id: "sample-pdf", title: "Mishkin 教材样例", subtitle: "PDF 阅读", kind: .pdf, urlPath: samplePDFURL()?.path, isSample: true),
            StudyItem(id: "sample-md", title: "课堂笔记样例", subtitle: "Markdown", kind: .markdown, urlPath: nil, isSample: true)
        ]
    }

    private static func samplePDFURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = appSupport.appendingPathComponent("WeiBei/Samples", isDirectory: true)
        let url = directory.appendingPathComponent("mishkin-sample.pdf")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return writeSamplePDF(to: url) ? url : nil
    }

    private static func writeSamplePDF(to url: URL) -> Bool {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 560, height: 780)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return false
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        func draw(_ text: String, at point: CGPoint, font: NSFont, color: NSColor = .black) {
            NSString(string: text).draw(at: point, withAttributes: [
                .font: font,
                .foregroundColor: color
            ])
        }

        draw("金融体系的功能", at: CGPoint(x: 72, y: 650), font: .boldSystemFont(ofSize: 30))
        draw("金融市场和金融中介能够把储蓄者的资金转移给有投资机会的人。", at: CGPoint(x: 72, y: 598), font: .systemFont(ofSize: 16))
        draw("它们降低交易成本，缓解信息不对称，并帮助社会更有效地配置资源。", at: CGPoint(x: 72, y: 570), font: .systemFont(ofSize: 16))
        draw("利率是资金使用价格的表达。", at: CGPoint(x: 72, y: 516), font: .systemFont(ofSize: 18))
        draw("页 1", at: CGPoint(x: 72, y: 76), font: .systemFont(ofSize: 14), color: .darkGray)

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return data.write(to: url, atomically: true)
    }

    private func sampleMarkdownHTML(for item: StudyItem?) -> String {
        let title = item?.title ?? "课堂笔记样例"
        let escaped = (notesByItemID[item?.id ?? ""] ?? defaultNote(for: item))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>
        body { margin: 0; background: #f1e4cf; color: #211d19; font: 16px/1.75 ui-monospace, SFMono-Regular, Menlo, monospace; }
        main { max-width: 840px; margin: 0 auto; padding: 56px 64px; }
        h1 { font-family: -apple-system, BlinkMacSystemFont, "Songti SC", serif; font-size: 34px; }
        pre { white-space: pre-wrap; }
        </style></head><body><main><h1>\(title)</h1><pre>\(escaped)</pre></main></body></html>
        """
    }

    private func appOwnedFilesDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WeiBei/Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func safeFileStem(_ value: String) -> String {
        MarkdownAttachmentStore.safeFileStem(value, fallback: "未命名", limit: 80)
    }

    private func nextNotebookNoteURL(in directory: URL, title: String) -> URL {
        let stem = Self.safeFileStem(title)
        var index = 1
        var url = directory.appendingPathComponent("\(stem).md")
        while FileManager.default.fileExists(atPath: url.path) {
            index += 1
            url = directory.appendingPathComponent("\(stem) \(index).md")
        }
        return url
    }

    private func clearGeneratedQuietInsight() {
        generatedQuietInsight = nil
        quietInsightSignature = ""
    }

    private var rightPaneRevealFocus: PaneFocus {
        switch layout {
        case .documentNotesAgent, .immersiveConversation:
            .agent
        default:
            .notes
        }
    }

    private func clearUnpinnedFloatingSelection(keepContext: Bool = true) {
        if !keepContext {
            selectionContext = nil
            selectionAnchor = nil
            floatingSelectionPrompt = "当前选区"
            pinnedFloatingAgent = false
            if agentSurface == .selectionFloat {
                agentSurface = .hidden
            }
            return
        }
        guard !pinnedFloatingAgent else { return }
        selectionAnchor = nil
        if agentSurface == .selectionFloat {
            agentSurface = .hidden
        }
    }

    private func collapseSelectionFloatIntoConversationIfVisible() {
        guard isConversationSurfaceVisible, agentSurface == .selectionFloat else { return }
        agentSurface = .hidden
        selectionAnchor = nil
        pinnedFloatingAgent = false
    }

    private func refreshQuietInsightIfNeeded() {
        guard agentSurface == .quietInsight, showQuietInsight else { return }
        Task { await refreshQuietInsight() }
    }

    private func makeQuietInsightSignature(materialText: String, noteText: String, selectionText: String?) -> String {
        [
            selectedItemID ?? "",
            String(materialText.prefix(1_000)),
            String(noteText.prefix(1_000)),
            String((selectionText ?? "").prefix(400))
        ].joined(separator: "\u{1f}")
    }

    private func defaultNote(for item: StudyItem?) -> String {
        let title = item?.title ?? "新笔记"
        let excerptSeed = item.map { $0.isNotebookNote ? "" : "> 来源：\($0.title)\n" } ?? ""
        return """
        # \(title)

        ## 核心要点

        ## 摘录
        \(excerptSeed)

        ## 待追问
        """
    }

    private func noteText(for item: StudyItem?) -> String {
        guard let item else {
            noteFileError = nil
            return defaultNote(for: nil)
        }
        guard item.editsBackingMarkdownFile, let url = item.url else {
            noteFileError = nil
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
        do {
            noteFileError = nil
            return cleanLegacyPlaceholder(try String(contentsOf: url, encoding: .utf8))
        } catch {
            noteFileError = "无法读取原 Markdown：\(url.lastPathComponent)"
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
    }

    private func persistCurrentNote() {
        guard let selectedItemID,
              let item = allItems.first(where: { $0.id == selectedItemID }) else { return }
        if item.editsBackingMarkdownFile, let url = item.url {
            do {
                try noteText.write(to: url, atomically: true, encoding: .utf8)
                notesByItemID.removeValue(forKey: selectedItemID)
                noteFileError = nil
            } catch {
                notesByItemID[selectedItemID] = noteText
                noteFileError = "无法写回原 Markdown：\(url.lastPathComponent)"
            }
            return
        }
        notesByItemID[selectedItemID] = noteText
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? JSONDecoder().decode(PersistedWorkspace.self, from: data) else {
            return
        }
        importedItems = snapshot.importedItems
        notesByItemID = snapshot.notesByItemID.mapValues(cleanLegacyPlaceholder)
        selectedItemID = snapshot.selectedItemID
        if let modelName = snapshot.modelName {
            self.modelName = modelName
        }
        if let workspaceLayout = snapshot.workspaceLayout {
            layout = workspaceLayout
        }
        if let agentSurface = snapshot.agentSurface {
            self.agentSurface = agentSurface == .selectionFloat ? .hidden : agentSurface
        }
        if let noteRenderMode = snapshot.noteRenderMode {
            self.noteRenderMode = noteRenderMode
        }
        if let showLibrary = snapshot.showLibrary {
            self.showLibrary = showLibrary
        }
        if let showRightPane = snapshot.showRightPane {
            self.showRightPane = showRightPane
        }
        if let appearanceModeRaw = snapshot.appearanceModeRaw,
           let appearanceMode = WeiBeiAppearanceMode(rawValue: appearanceModeRaw) {
            self.appearanceMode = appearanceMode
        }
        noteText = noteText(for: selectedItem)
    }

    private func cleanLegacyPlaceholder(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"(?m)^- (?:静默洞察|Agent 洞察)：(.+)\n  来源：(.+)$"#,
                with: "> [!note] 阅读线索\n>\n> $1\n>\n> 来源：$2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?m)^> \[!note\] 阅读线索\n> ([^\n])"#,
                with: "> [!note] 阅读线索\n>\n> $1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?m)^> \[!quote\]([^\n]*)\n> ([^\n])"#,
                with: "> [!quote]$1\n>\n> $2",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\n> 待整理摘录：当前选区\n", with: "\n")
            .replacingOccurrences(of: "\n> 待整理摘录：当前选区", with: "")
            .replacingOccurrences(of: "\n* <br />\n", with: "\n")
            .replacingOccurrences(of: "\n* <br />", with: "")
            .replacingOccurrences(of: "\n- <br />\n", with: "\n")
            .replacingOccurrences(of: "\n- <br />", with: "")
    }

    private func save() {
        let snapshot = PersistedWorkspace(
            importedItems: importedItems,
            notesByItemID: notesByItemID,
            selectedItemID: selectedItemID,
            modelName: modelName,
            workspaceLayout: layout,
            agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface,
            noteRenderMode: noteRenderMode,
            showLibrary: showLibrary,
            showRightPane: showRightPane,
            appearanceModeRaw: appearanceMode.rawValue
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }

    private func resolvedOpenAIAPIKey() -> (key: String, source: String)? {
        let environmentKey = Self.environmentValue("OPENAI_API_KEY")
        if !environmentKey.isEmpty {
            return (environmentKey, "本机环境变量")
        }

        let savedKey = OpenAIAPIKeyStore.load()
        if !savedKey.isEmpty {
            return (savedKey, "macOS 钥匙串")
        }

        return nil
    }

    private var resolvedModelName: String {
        let environmentModel = Self.environmentValue("WEIBEI_OPENAI_MODEL")
        return environmentModel.isEmpty ? modelName : environmentModel
    }

    private static func environmentValue(_ name: String) -> String {
        OpenAIAPIKeyStore.cleaned(ProcessInfo.processInfo.environment[name] ?? "")
    }
}
