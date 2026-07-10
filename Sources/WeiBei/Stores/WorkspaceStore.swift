import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

enum NotebookCreationKind: String {
    case blank
    case currentMaterial
}

struct NotebookCreationDraft: Identifiable, Equatable {
    let id = UUID()
    var kind: NotebookCreationKind
    var sourceItemID: String?
    var title: String
}

struct NotebookRenameDraft: Identifiable, Equatable {
    let id = UUID()
    var itemID: String
    var title: String
}

struct ThreePaneReorderDrag: Equatable {
    var role: WorkspacePaneRole
    var translation: CGFloat
    var targetIndex: Int?
}

struct PaneExpansionRequest: Equatable {
    let id = UUID()
    let role: WorkspacePaneRole
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var importedItems: [StudyItem] = []
    @Published var selectedItemID: String?
    @Published var activeNotebookItemID: String?
    @Published private(set) var noteSourceLinks: [NoteSourceLink] = []
    @Published var selectedAgentSourceIDs: Set<String> = []
    @Published var includeCurrentMaterialInAgentScope = true
    @Published var linkedSourcesPresented = false
    @Published var noteText = ""
    @Published var agentDraft = ""
    @Published var messages: [AgentMessage] = []
    @Published var isAskingAgent = false
    @Published var showLibrary = true
    @Published var showReader = true
    @Published var showAgent = true
    @Published var showNotes = true
    @Published var showDailyInspiration = true
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
    @Published var threePaneOrder: [WorkspacePaneRole] = WorkspacePaneRole.defaultThreePaneOrder
    @Published var threePaneReorderDrag: ThreePaneReorderDrag?
    @Published private(set) var paneExpansionRequest: PaneExpansionRequest?
    @Published var agentSurface: AgentSurface = .bottomDrawer
    @Published var noteRenderMode: NoteRenderMode = .rich
    @Published var showQuietInsight = true
    @Published var generatedQuietInsight: QuietInsight?
    @Published var isGeneratingQuietInsight = false
    @Published var floatingSelectionPrompt = ""
    @Published var pinnedFloatingAgent = false
    @Published var selectionContext: SelectionContext?
    @Published var selectionAttachments: [SelectionContext] = []
    @Published var selectionAnchor: CGPoint?
    @Published var noteEditorCommand: NoteEditorCommand?
    @Published var noteFileError: String?
    @Published var notebookCreationDraft: NotebookCreationDraft?
    @Published var notebookRenameDraft: NotebookRenameDraft?
    @Published var modelName: String = ProcessInfo.processInfo.environment["WEIBEI_OPENAI_MODEL"] ?? "gpt-5.1"
    @Published var openAIAPIKey: String = OpenAIAPIKeyStore.load()
    @Published var openAIKeyStatus: String?
    @Published var appearanceMode: WeiBeiAppearanceMode = .paper
    @Published var adaptImportedDocumentColors = true
    @Published var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    @Published var topBarVariant: TopBarVariant = TopBarVariant(rawValue: UserDefaults.standard.string(forKey: "topBarVariant") ?? "") ?? .balanced
    @Published private var backNavigationStack: [NavigationSnapshot] = []
    @Published private var forwardNavigationStack: [NavigationSnapshot] = []

    private var notesByItemID: [String: String] = [:]
    private let storageURL: URL
    private var quietInsightSignature = ""
    private var isRestoringNavigation = false
    private var didRunVerificationScenario = false
    private var lastSelectionAttachmentDate: Date?
    private var lastSelectionUpdateDate: Date?
    private var pendingSelectionAttachmentTask: Task<Void, Never>?
    private let selectionAttachmentMergeWindow: TimeInterval = 1.8
    private let selectionAttachmentDebounceDelay: UInt64 = 520_000_000
    private var threePaneReorderFrames: [WorkspacePaneRole: CGRect] = [:]
    private var pendingNotePersistenceByItemID: [String: PendingNotePersistence] = [:]
    private var pendingNotePersistenceTasks: [String: Task<Void, Never>] = [:]
    private let notePersistenceDebounceDelay: UInt64 = 420_000_000
    private var activeAgentRequestID: UUID?

    var showRightPane: Bool {
        get { showNotes || showAgent }
        set {
            showNotes = newValue
            showAgent = newValue
        }
    }

    private struct NavigationSnapshot: Equatable {
        var selectedItemID: String?
        var activeNotebookItemID: String?
        var layout: WorkspaceLayout
        var showLibrary: Bool
        var showReader: Bool
        var showAgent: Bool
        var showNotes: Bool
        var agentSurface: AgentSurface
        var noteRenderMode: NoteRenderMode
        var showReaderSearch: Bool
        var readerSearch: String
        var readerPageIndex: Int
        var focusedPane: PaneFocus
        var threePaneOrder: [WorkspacePaneRole]
    }

    private enum NotebookNoteSeed {
        case blank
        case currentMaterial(StudyItem)
    }

    private struct PendingNotePersistence {
        var item: StudyItem
        var markdown: String
    }

    private var lastUsableAgentAnswer: AgentMessage? {
        messages.last { $0.isUsableAgentAnswer }
    }

    private static let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let sampleItems: [StudyItem] = WorkspaceStore.makeSampleItems()

    init() {
        let folder = Self.workspaceRootDirectory() ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBei", isDirectory: true)
        storageURL = folder.appendingPathComponent("workspace.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        floatingSelectionPrompt = ui("当前选区", "Current selection")
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
        return allItems.filter { itemMatchesLibrarySearch($0, query: query) }
    }

    var navigableItems: [StudyItem] {
        let materialItems = allItems.filter { !$0.isNotebookNote }
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return materialItems }
        return materialItems.filter { itemMatchesLibrarySearch($0, query: query) }
    }

    var selectedItem: StudyItem? {
        allItems.first { $0.id == selectedItemID }
    }

    var selectedMaterialItem: StudyItem? {
        guard let item = selectedItem, !item.isNotebookNote else { return nil }
        return item
    }

    var activeNoteItem: StudyItem? {
        if let activeNotebookItemID,
           let item = allItems.first(where: { $0.id == activeNotebookItemID && $0.isNotebookNote }) {
            return item
        }
        return selectedItem
    }

    var activeNoteItemID: String? {
        activeNoteItem?.id
    }

    var linkedSourceIDsForActiveNote: [String] {
        guard let noteID = activeNoteItemID else { return [] }
        return NoteSourceRelations(links: noteSourceLinks).sourceIDs(for: noteID)
    }

    var linkedSourcesForActiveNote: [StudyItem] {
        let linkedIDs = Set(linkedSourceIDsForActiveNote)
        return allItems.filter { linkedIDs.contains($0.id) && !$0.isNotebookNote }
    }

    var linkedSourceCount: Int { linkedSourcesForActiveNote.count }

    var agentSelectableLinkedSources: [StudyItem] {
        linkedSourcesForActiveNote.filter { $0.id != selectedMaterialItem?.id }
    }

    var selectedAgentLinkedSourceCount: Int {
        selectedAgentSourceIDs.intersection(Set(agentSelectableLinkedSources.map(\.id))).count
    }

    var agentSelectableLinkedSourceCount: Int { agentSelectableLinkedSources.count }

    private func loadSelectedLinkedAgentSources() async -> [StudyAgentSource] {
        let requests = agentSelectableLinkedSources.filter { selectedAgentSourceIDs.contains($0.id) }.map { item in
            AgentSourceLoadRequest(
                item: item,
                title: displayTitle(for: item),
                fallbackText: item.isSample ? sampleText(for: item) : ""
            )
        }
        let loadedSources = await AgentSourceTextLoader.shared.sources(for: requests)
        return StudyAgentSourceContextBuilder.scopedSources(
            loadedSources,
            selectedIDs: selectedAgentSourceIDs
        )
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

    var visibleDocumentPaneOrder: [WorkspacePaneRole] {
        normalizedThreePaneOrder.filter(isPaneVisible)
    }

    func isPaneVisible(_ role: WorkspacePaneRole) -> Bool {
        switch role {
        case .reader:
            return showReader
        case .agent:
            return showAgent
        case .notes:
            return showNotes
        }
    }

    func isPaneToggleActive(_ role: WorkspacePaneRole) -> Bool {
        switch layout {
        case .immersiveReading:
            return role == .reader
        case .immersiveConversation:
            return role == .agent
        case .immersiveWriting:
            return role == .notes
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return isPaneVisible(role)
        }
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
        if let url = activeNoteItem?.url {
            return url.deletingLastPathComponent()
        }
        return appOwnedFilesDirectory()
    }

    var currentAttachmentDirectory: URL? {
        if let url = activeNoteItem?.url {
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
        selectedMaterialItem.map(displayTitle) ?? ui("未选择材料", "No material selected")
    }

    var agentMessageSourceTitle: String? {
        hasSelectedMaterial ? currentReferenceTitle : activeNoteItem.map(displayTitle)
    }

    var currentReferenceTitle: String {
        readerLocationTitle ?? selectedMaterialItem.map(displayTitle) ?? activeNoteItem.map(displayTitle) ?? ui("当前笔记", "Current note")
    }

    var hasSelectionAttachments: Bool {
        !selectionAttachments.isEmpty
    }

    var agentSelectionTitle: String? {
        guard !selectionAttachments.isEmpty else { return nil }
        if selectionAttachments.count == 1 {
            return selectionAttachments[0].ownerTitle
        }
        return ui("\(selectionAttachments.count) 个已选文本片段", "\(selectionAttachments.count) selected text fragments")
    }

    var agentSelectionText: String? {
        guard !selectionAttachments.isEmpty else { return nil }
        return selectionAttachments.enumerated().map { index, selection in
            ui(
                """
                片段 \(index + 1)（来源：\(selection.ownerTitle)）：
                \(selection.text)
                """,
                """
                Fragment \(index + 1) (source: \(selection.ownerTitle)):
                \(selection.text)
                """
            )
        }.joined(separator: "\n\n")
    }

    var canCopyReference: Bool {
        hasSelectionAttachments || selectionContext != nil || hasSelectedMaterial || activeNoteItem?.isNotebookNote == true
    }

    var copyReferenceActionTitle: String {
        if hasSelectionAttachments || selectionContext != nil { return ui("复制选区引用", "Copy selection reference") }
        if hasSelectedMaterial { return ui("复制资料引用", "Copy material reference") }
        return ui("复制笔记引用", "Copy note reference")
    }

    var sendAgentActionTitle: String {
        ui("发送问题", "Send question")
    }

    var agentNoteTitle: String {
        if activeNoteItem?.isNotebookNote == true {
            return activeNoteItem.map(displayTitle) ?? ui("当前笔记", "Current note")
        }
        if let item = selectedMaterialItem {
            return ui("\(displayTitle(for: item)) 的笔记", "Notes for \(displayTitle(for: item))")
        }
        return ui("当前笔记", "Current note")
    }

    var agentConversationSubtitle: String {
        if includeCurrentMaterialInAgentScope, let item = selectedMaterialItem {
            return displayTitle(for: item)
        }
        return activeNoteItem.map(displayTitle) ?? ui("无上下文", "No context")
    }

    var agentPromptScope: String {
        if !selectedAgentSourceIDs.isEmpty {
            return includeCurrentMaterialInAgentScope && hasSelectedMaterial
                ? ui("当前材料、当前笔记和本次勾选的关联资料", "the current material, current note, and selected linked sources")
                : ui("当前笔记和本次勾选的关联资料", "the current note and selected linked sources")
        }
        return includeCurrentMaterialInAgentScope && hasSelectedMaterial ? ui("当前材料和当前笔记", "the current material and current note") : ui("当前笔记", "the current note")
    }

    var agentInputPrompt: String {
        if hasSelectionAttachments {
            return ui("输入问题", "Ask a question")
        }
        if !selectedAgentSourceIDs.isEmpty { return ui("问本次资料", "Ask selected sources") }
        return includeCurrentMaterialInAgentScope && hasSelectedMaterial ? ui("问当前材料", "Ask current material") : ui("问当前笔记", "Ask current note")
    }

    var selectionPromptScope: String {
        selectionContext?.source == .note ? ui("当前笔记", "the current note") : agentPromptScope
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
            return QuietInsight(
                body: hasSelectedMaterial
                    ? ui("正在静默阅读当前材料和笔记。", "Reading the current material and note in the background.")
                    : ui("正在静默阅读当前笔记。", "Reading the current note in the background."),
                noteBlock: ""
            )
        }
        if let generatedQuietInsight {
            return generatedQuietInsight
        }
        return QuietInsight.make(
            materialTitle: quietInsightReferenceTitle,
            materialText: selectedContextText,
            noteText: noteText,
            selectionText: selectionContext?.text,
            language: interfaceLanguage
        )
    }

    var quietInsightTitle: String {
        return ui("阅读线索", "Reading clue")
    }

    var quietInsightSourceLabel: String {
        if selectionContext != nil {
            return ui("来自当前选区", "From current selection")
        }
        if !hasSelectedMaterial {
            return ui("来自当前笔记", "From current note")
        }
        return generatedQuietInsight == nil ? ui("来自当前材料", "From current material") : ui("来自材料和笔记", "From material and note")
    }

    var openAIKeyHelpText: String {
        if !Self.environmentValue("OPENAI_API_KEY").isEmpty {
            return ui("正在使用本机环境密钥。保存的密钥会在没有环境密钥时接管。", "Using the local environment key. The saved key is used only when no environment key is present.")
        }
        if !OpenAIAPIKeyStore.load().isEmpty {
            return ui("密钥已保存，可直接用于对话。", "Key saved. Chat is ready.")
        }
        return ui(
            "未保存密钥。保存后对话会结合\(agentPromptScope)，并在有已选文本片段时一并作答。",
            "No key saved. After saving, chat will use \(agentPromptScope) and any selected text fragments."
        )
    }

    var appDisplayName: String {
        ui("魏碑", "WeiBei")
    }

    var brandLatinName: String {
        "WeiBei"
    }

    func ui(_ chinese: String, _ english: String) -> String {
        interfaceLanguage.text(chinese, english)
    }

    func displayTitle(for item: StudyItem) -> String {
        switch item.id {
        case "sample-html":
            return ui("货币金融学课程 HTML", "Money and Banking HTML")
        case "sample-pdf":
            return ui("Mishkin 教材样例", "Mishkin Textbook Sample")
        case "sample-md":
            return ui("课堂笔记样例", "Class Notes Sample")
        default:
            return item.title
        }
    }

    func displaySubtitle(for item: StudyItem) -> String {
        switch item.id {
        case "sample-html":
            return ui("HTML 教程", "HTML lesson")
        case "sample-pdf":
            return ui("PDF 阅读", "PDF reading")
        default:
            return item.subtitle
        }
    }

    func displayTags(for item: StudyItem, limit: Int = 3) -> [String] {
        guard item.isNotebookNote else { return [] }
        return Array(MarkdownTagSearch.tags(in: noteMarkdownText(for: item)).prefix(limit))
    }

    private func itemMatchesLibrarySearch(_ item: StudyItem, query: String) -> Bool {
        displayTitle(for: item).localizedCaseInsensitiveContains(query)
            || displaySubtitle(for: item).localizedCaseInsensitiveContains(query)
            || item.kind.label(language: interfaceLanguage).localizedCaseInsensitiveContains(query)
            || noteTagsMatchLibrarySearch(item, query: query)
    }

    private func noteTagsMatchLibrarySearch(_ item: StudyItem, query: String) -> Bool {
        guard item.isNotebookNote else { return false }
        return MarkdownTagSearch.matches(query: query, in: noteMarkdownText(for: item))
    }

    private func noteMarkdownText(for item: StudyItem) -> String {
        if item.id == activeNoteItemID {
            return noteText
        }
        if let cached = notesByItemID[item.id] {
            return cached
        }
        if item.editsBackingMarkdownFile, let url = item.url {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return ""
    }

    func select(itemID: String?) {
        persistCurrentNote()
        notebookCreationDraft = nil
        notebookRenameDraft = nil
        if let itemID,
           let item = allItems.first(where: { $0.id == itemID && $0.isNotebookNote }) {
            activateNotebookItem(item)
            revealRichWritingSurface()
            focus(.notes)
            save()
            return
        }
        let itemChanged = selectedItemID != itemID
        if itemChanged && selectedItemID != nil {
            recordNavigationPoint()
        }
        selectedItemID = itemID
        if itemChanged {
            invalidateAgentRequest()
            clearUnpinnedFloatingSelection(keepContext: false)
            selectionAttachments = []
            lastSelectionAttachmentDate = nil
            readerPageIndex = 0
        }
        readerLocationTitle = selectedMaterialItem.map(displayTitle)
        clearReaderSearchIfNeeded()
        noteText = noteText(for: activeNoteItem)
        clearGeneratedQuietInsight()
        refreshQuietInsightIfNeeded()
        save()
    }

    func isSourceLinkedToActiveNote(_ sourceID: String) -> Bool {
        guard let noteID = activeNotebookItemID else { return false }
        return NoteSourceRelations(links: noteSourceLinks).isLinked(noteID: noteID, sourceID: sourceID)
    }

    func setLinkedSourceIDsForActiveNote(_ sourceIDs: Set<String>) {
        guard let noteID = activeNotebookItemID else { return }
        let validIDs = Set(allItems.filter { !$0.isNotebookNote }.map(\.id))
        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.replaceSources(for: noteID, sourceIDs: sourceIDs.intersection(validIDs))
        noteSourceLinks = relations.links
        selectedAgentSourceIDs.formIntersection(sourceIDs)
        save()
    }

    func toggleSourceLinkToActiveNote(_ sourceID: String) {
        guard let noteID = activeNotebookItemID,
              allItems.contains(where: { $0.id == sourceID && !$0.isNotebookNote }) else { return }
        var relations = NoteSourceRelations(links: noteSourceLinks)
        if relations.isLinked(noteID: noteID, sourceID: sourceID) {
            relations.unlink(noteID: noteID, sourceID: sourceID)
            selectedAgentSourceIDs.remove(sourceID)
        } else {
            relations.link(noteID: noteID, sourceID: sourceID)
        }
        noteSourceLinks = relations.links
        save()
    }

    func setAgentSourceSelected(_ sourceID: String, selected: Bool) {
        guard isSourceLinkedToActiveNote(sourceID) else { return }
        if selected { selectedAgentSourceIDs.insert(sourceID) }
        else { selectedAgentSourceIDs.remove(sourceID) }
    }

    func selectAllLinkedAgentSources() {
        selectedAgentSourceIDs = Set(agentSelectableLinkedSources.map(\.id))
    }

    private func activateNotebookItem(_ item: StudyItem) {
        let changed = activeNotebookItemID != item.id
        activeNotebookItemID = item.id
        selectedAgentSourceIDs = []
        includeCurrentMaterialInAgentScope = true
        noteText = noteText(for: item)
        if changed {
            invalidateAgentRequest()
            messages = []
        }
    }

    private func invalidateAgentRequest() {
        activeAgentRequestID = nil
        isAskingAgent = false
    }

    func selectAdjacentItem(step: Int) {
        let ids = navigableItems.map(\.id)
        guard let nextID = LibraryNavigator.adjacentID(in: ids, selectedID: selectedItemID, step: step) else { return }
        select(itemID: nextID)
        focus(.reader)
    }

    func updateNote(_ value: String) {
        guard noteText != value else { return }
        noteText = value
        clearGeneratedQuietInsight()
        guard let item = activeNoteItem else { return }
        if !item.editsBackingMarkdownFile {
            notesByItemID[item.id] = value
        }
        scheduleNotePersistence(value, for: item)
    }

    func updateNote(_ value: String, for itemID: String?) {
        guard let itemID else {
            updateNote(value)
            return
        }
        // Local editor draft may flush after a note switch; persist that item without touching active noteText.
        if itemID != activeNoteItemID {
            commitInactiveNoteDraft(value, itemID: itemID)
            return
        }
        guard itemID == activeNoteItemID else { return }
        updateNote(value)
    }

    /// Persist a draft for a note that is no longer active (does not mutate active `noteText`).
    private func commitInactiveNoteDraft(_ value: String, itemID: String) {
        guard let item = allItems.first(where: { $0.id == itemID }) else { return }
        if !item.editsBackingMarkdownFile {
            notesByItemID[item.id] = value
        }
        scheduleNotePersistence(value, for: item)
    }

    func createBlankNotebookNote() {
        createNotebookNote(seed: .blank)
    }

    func createNotebookNoteFromCurrentMaterial() {
        guard let selectedMaterialItem else {
            createBlankNotebookNote()
            return
        }
        if openExistingNotebookNote(for: selectedMaterialItem) {
            return
        }
        createNotebookNote(seed: .currentMaterial(selectedMaterialItem))
    }

    func promptCreateBlankNotebookNote() {
        noteFileError = nil
        notebookRenameDraft = nil
        notebookCreationDraft = NotebookCreationDraft(
            kind: .blank,
            sourceItemID: nil,
            title: suggestedNotebookTitle(for: .blank)
        )
        focus(.notes)
    }

    func promptCreateNotebookNoteFromCurrentMaterial() {
        guard let selectedMaterialItem else {
            promptCreateBlankNotebookNote()
            return
        }
        if openExistingNotebookNote(for: selectedMaterialItem) {
            return
        }
        noteFileError = nil
        notebookRenameDraft = nil
        notebookCreationDraft = NotebookCreationDraft(
            kind: .currentMaterial,
            sourceItemID: selectedMaterialItem.id,
            title: suggestedNotebookTitle(for: .currentMaterial(selectedMaterialItem))
        )
        focus(.notes)
    }

    func cancelNotebookNoteCreation() {
        notebookCreationDraft = nil
        noteFileError = nil
    }

    func confirmNotebookNoteCreation() {
        guard let draft = notebookCreationDraft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            noteFileError = ui("笔记名不能为空。", "Note name cannot be empty.")
            return
        }
        notebookCreationDraft = nil
        if draft.kind == .currentMaterial,
           let sourceItemID = draft.sourceItemID,
           let item = allItems.first(where: { $0.id == sourceItemID && !$0.isNotebookNote }) {
            createNotebookNote(seed: .currentMaterial(item), title: title)
        } else {
            createNotebookNote(seed: .blank, title: title)
        }
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
            if layout == .documentNotesSplit, !showAgent, agentSurface == .hidden {
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

    func toggleReader() {
        toggleDocumentPane(.reader)
    }

    func toggleAgent() {
        if selectionContext != nil {
            recordNavigationPoint()
            revealDocumentPane(.agent, clearSelection: false)
            routeSelectionToConversation()
            save()
            return
        }
        toggleDocumentPane(.agent)
    }

    func toggleNotes() {
        toggleDocumentPane(.notes)
    }

    func toggleRightPane() {
        guard layout.hasCollapsibleRightPane else { return }
        recordNavigationPoint()
        showRightPane.toggle()
        clearUnpinnedFloatingSelection()
        focus(showRightPane ? rightPaneRevealFocus : fallbackDocumentPaneFocus())
        save()
    }

    func revealRightPane(focusing pane: PaneFocus = .notes) {
        guard layout.hasCollapsibleRightPane else { return }
        let targetVisible = pane == .agent ? showAgent : pane == .notes ? showNotes : showRightPane
        if !targetVisible {
            recordNavigationPoint()
            clearUnpinnedFloatingSelection()
        }
        switch pane {
        case .agent:
            showAgent = true
        case .notes:
            showNotes = true
        default:
            showRightPane = true
        }
        focus(pane)
        save()
    }

    private func toggleDocumentPane(_ role: WorkspacePaneRole) {
        recordNavigationPoint()
        clearUnpinnedFloatingSelection()
        if layoutIsImmersive {
            toggleDocumentPaneFromImmersive(role)
        } else {
            setDocumentPane(!isPaneVisible(role), role)
            layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
        }
        focus(isPaneVisible(role) ? role.focus : fallbackDocumentPaneFocus())
        save()
    }

    private func revealDocumentPane(_ role: WorkspacePaneRole, clearSelection: Bool = true) {
        if clearSelection {
            clearUnpinnedFloatingSelection()
        }
        if layoutIsImmersive {
            setDocumentPaneSet(immersivePaneSet().union([role]))
        } else {
            setDocumentPane(true, role)
        }
        layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
        focus(role.focus)
    }

    private var layoutIsImmersive: Bool {
        switch layout {
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return true
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return false
        }
    }

    private func toggleDocumentPaneFromImmersive(_ role: WorkspacePaneRole) {
        var visible = immersivePaneSet()
        if visible.contains(role) {
            visible.remove(role)
        } else {
            visible.insert(role)
        }
        setDocumentPaneSet(visible)
        layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
    }

    private func immersivePaneSet() -> Set<WorkspacePaneRole> {
        switch layout {
        case .immersiveReading:
            return [.reader]
        case .immersiveConversation:
            return [.agent]
        case .immersiveWriting:
            return [.notes]
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return Set(visibleDocumentPaneOrder)
        }
    }

    private func setDocumentPaneSet(_ roles: Set<WorkspacePaneRole>) {
        showReader = roles.contains(.reader)
        showAgent = roles.contains(.agent)
        showNotes = roles.contains(.notes)
        if !showReader {
            showReaderSearch = false
            readerSearch = ""
        }
    }

    private func setDocumentPane(_ visible: Bool, _ role: WorkspacePaneRole) {
        switch role {
        case .reader:
            showReader = visible
            if !visible {
                showReaderSearch = false
                readerSearch = ""
            }
        case .agent:
            showAgent = visible
        case .notes:
            showNotes = visible
        }
    }

    private func fallbackDocumentPaneFocus() -> PaneFocus {
        visibleDocumentPaneOrder.first?.focus ?? .reader
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
        readerLocationTitle = cleaned.isEmpty ? selectedMaterialItem.map(displayTitle) : cleaned
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
        let presetOrder = layout.defaultThreePaneOrder
        let orderWillChange = presetOrder.map { WorkspacePaneRole.normalized($0) != normalizedThreePaneOrder } ?? false
        if self.layout != layout || orderWillChange {
            recordNavigationPoint()
            clearUnpinnedFloatingSelection()
        }
        self.layout = layout
        if let order = presetOrder {
            threePaneOrder = order
        }
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

    var normalizedThreePaneOrder: [WorkspacePaneRole] {
        WorkspacePaneRole.normalized(threePaneOrder)
    }

    func threePaneOrderLabel(compact: Bool = false) -> String {
        let order = normalizedThreePaneOrder
        let labels = order.map { role in
            compact ? role.shortLabel(language: interfaceLanguage) : role.label(language: interfaceLanguage)
        }
        return labels.joined(separator: "-")
    }

    func swapThreePaneRoles(_ dragged: WorkspacePaneRole, over target: WorkspacePaneRole) {
        guard dragged != target else { return }
        guard layout.isDocumentThreePane else { return }
        var order = normalizedThreePaneOrder
        guard let draggedIndex = order.firstIndex(of: dragged),
              let targetIndex = order.firstIndex(of: target) else { return }
        order.swapAt(draggedIndex, targetIndex)
        applyThreePaneOrder(order, focus: dragged.focus)
    }

    func swapThreePaneSecondaryPanes() {
        guard layout.isDocumentThreePane else { return }
        var order = normalizedThreePaneOrder
        guard let notesIndex = order.firstIndex(of: .notes),
              let agentIndex = order.firstIndex(of: .agent) else { return }
        order.swapAt(notesIndex, agentIndex)
        applyThreePaneOrder(order, focus: focusedPane)
    }

    func moveThreePaneRole(_ role: WorkspacePaneRole, horizontalDelta: CGFloat) {
        guard layout.isDocumentThreePane else { return }
        var order = normalizedThreePaneOrder
        guard let targetIndex = threePaneReorderTargetIndex(for: role, horizontalDelta: horizontalDelta),
              let currentIndex = order.firstIndex(of: role),
              currentIndex != targetIndex else { return }
        order.remove(at: currentIndex)
        order.insert(role, at: min(targetIndex, order.count))
        applyThreePaneOrder(order, focus: role.focus)
    }

    func beginThreePaneReorder(_ role: WorkspacePaneRole) {
        guard layout.isDocumentThreePane else { return }
        threePaneReorderDrag = ThreePaneReorderDrag(role: role, translation: 0, targetIndex: nil)
    }

    func updateThreePaneReorderFrames(order: [WorkspacePaneRole], frames: [CGRect]) {
        guard order.count == frames.count else { return }
        let nextFrames = Dictionary(uniqueKeysWithValues: zip(order, frames))
        guard !sameReorderFrames(nextFrames, threePaneReorderFrames) else { return }
        threePaneReorderFrames = nextFrames
    }

    func requestPaneExpansion(_ role: WorkspacePaneRole) {
        paneExpansionRequest = PaneExpansionRequest(role: role)
    }

    func completePaneExpansionRequest(_ id: UUID) {
        guard paneExpansionRequest?.id == id else { return }
        paneExpansionRequest = nil
    }

    func threePaneReorderFrameList(order: [WorkspacePaneRole], fallback: [CGRect]) -> [CGRect] {
        let frames = order.compactMap { threePaneReorderFrames[$0] }
        return frames.count == order.count ? frames : fallback
    }

    func updateThreePaneReorder(_ role: WorkspacePaneRole, horizontalDelta: CGFloat) {
        guard layout.isDocumentThreePane else { return }
        threePaneReorderDrag = ThreePaneReorderDrag(
            role: role,
            translation: horizontalDelta,
            targetIndex: threePaneReorderTargetIndex(for: role, horizontalDelta: horizontalDelta)
        )
    }

    func finishThreePaneReorder(_ role: WorkspacePaneRole, horizontalDelta: CGFloat) {
        defer { threePaneReorderDrag = nil }
        moveThreePaneRole(role, horizontalDelta: horizontalDelta)
    }

    func cancelThreePaneReorder() {
        threePaneReorderDrag = nil
    }

    private func applyThreePaneOrder(_ order: [WorkspacePaneRole], focus nextFocus: PaneFocus) {
        recordNavigationPoint()
        clearUnpinnedFloatingSelection()
        threePaneReorderDrag = nil
        threePaneOrder = order
        layout = layoutMatchingThreePaneOrder(order)
        focus(nextFocus)
        save()
    }

    private func threePaneReorderTargetIndex(for role: WorkspacePaneRole, horizontalDelta: CGFloat) -> Int? {
        ThreePaneReorderTargeting.targetIndex(
            order: normalizedThreePaneOrder,
            frames: threePaneReorderFrames,
            role: role,
            horizontalDelta: horizontalDelta
        )
    }

    private func sameReorderFrames(_ lhs: [WorkspacePaneRole: CGRect], _ rhs: [WorkspacePaneRole: CGRect]) -> Bool {
        guard Set(lhs.keys) == Set(rhs.keys) else { return false }
        return lhs.allSatisfy { role, frame in
            guard let other = rhs[role] else { return false }
            return abs(frame.minX - other.minX) < 0.5
                && abs(frame.minY - other.minY) < 0.5
                && abs(frame.width - other.width) < 0.5
                && abs(frame.height - other.height) < 0.5
        }
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
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return showAgent
        case .immersiveConversation:
            return true
        case .immersiveReading, .immersiveWriting:
            return false
        }
    }

    var isConversationSurfaceVisible: Bool {
        if hasPrimaryConversationPaneVisible {
            return true
        }
        switch layout {
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return false
        case .immersiveConversation:
            return true
        case .immersiveReading, .immersiveWriting:
            return agentSurface == .bottomDrawer || agentSurface == .cornerPanel
        }
    }

    var canShowSelectionPromptSurface: Bool {
        true
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
        save()
    }

    func setNoteRenderMode(_ mode: NoteRenderMode) {
        let nextMode = mode.visibleMode
        if noteRenderMode != nextMode || layout == .immersiveReading || layout == .immersiveConversation || !showNotes {
            recordNavigationPoint()
        }
        if layout == .immersiveReading || layout == .immersiveConversation {
            clearUnpinnedFloatingSelection()
            layout = .immersiveWriting
        }
        if !showNotes {
            clearUnpinnedFloatingSelection()
            showNotes = true
        }
        noteRenderMode = nextMode
        focus(.notes)
        save()
    }

    private func revealRichWritingSurface() {
        if layout == .immersiveReading || layout == .immersiveConversation {
            clearUnpinnedFloatingSelection()
            layout = .immersiveWriting
        }
        if !showNotes {
            clearUnpinnedFloatingSelection()
            showNotes = true
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
            activeNotebookItemID: activeNotebookItemID,
            layout: layout,
            showLibrary: showLibrary,
            showReader: showReader,
            showAgent: showAgent,
            showNotes: showNotes,
            agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface,
            noteRenderMode: noteRenderMode,
            showReaderSearch: showReaderSearch,
            readerSearch: readerSearch,
            readerPageIndex: readerPageIndex,
            focusedPane: focusedPane,
            threePaneOrder: normalizedThreePaneOrder
        )
    }

    private func applyNavigationSnapshot(_ snapshot: NavigationSnapshot) {
        isRestoringNavigation = true
        defer { isRestoringNavigation = false }
        let noteChanged = activeNotebookItemID != snapshot.activeNotebookItemID
        selectedItemID = snapshot.selectedItemID
        activeNotebookItemID = snapshot.activeNotebookItemID
        selectedAgentSourceIDs = []
        includeCurrentMaterialInAgentScope = true
        if noteChanged { invalidateAgentRequest() }
        layout = snapshot.layout
        showLibrary = snapshot.showLibrary
        showReader = snapshot.showReader
        showAgent = snapshot.showAgent
        showNotes = snapshot.showNotes
        agentSurface = snapshot.agentSurface == .selectionFloat ? .hidden : snapshot.agentSurface
        noteRenderMode = snapshot.noteRenderMode.visibleMode
        showReaderSearch = snapshot.showReaderSearch
        readerSearch = snapshot.readerSearch
        readerPageIndex = snapshot.readerPageIndex
        focusedPane = snapshot.focusedPane
        threePaneOrder = WorkspacePaneRole.normalized(snapshot.threePaneOrder)
        noteText = noteText(for: activeNoteItem)
        readerLocationTitle = selectedMaterialItem.map(displayTitle)
        readerTargetPageIndex = selectedMaterialItem?.kind == .pdf ? snapshot.readerPageIndex : nil
        if noteChanged { messages = [] }
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
                animateLayoutChange { setLayout(.documentNotesSplit) }
            case "s":
                guard layout.isDocumentThreePane else { return false }
                animateLayoutChange { swapThreePaneSecondaryPanes() }
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

    func setDailyInspirationEnabled(_ enabled: Bool) {
        guard showDailyInspiration != enabled else { return }
        showDailyInspiration = enabled
        save()
    }

    func toggleImportedDocumentColorAdaptation() {
        setImportedDocumentColorAdaptation(!adaptImportedDocumentColors)
    }

    func setImportedDocumentColorAdaptation(_ enabled: Bool) {
        guard adaptImportedDocumentColors != enabled else { return }
        adaptImportedDocumentColors = enabled
        save()
    }

    func setTopBarVariant(_ variant: TopBarVariant) {
        guard topBarVariant != variant else { return }
        topBarVariant = variant
        UserDefaults.standard.set(variant.rawValue, forKey: "topBarVariant")
    }

    func setInterfaceLanguage(_ language: WeiBeiInterfaceLanguage) {
        guard interfaceLanguage != language else { return }
        interfaceLanguage = language
        floatingSelectionPrompt = ui("当前选区", "Current selection")
        save()
    }

    func saveOpenAIAPIKey() {
        do {
            let cleanedKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)
            try OpenAIAPIKeyStore.save(cleanedKey)
            openAIAPIKey = cleanedKey
            openAIKeyStatus = cleanedKey.isEmpty ? ui("已清除密钥。", "Key cleared.") : ui("密钥已保存。", "Key saved.")
        } catch {
            openAIKeyStatus = ui("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
        }
    }

    func clearOpenAIAPIKey() {
        openAIAPIKey = ""
        saveOpenAIAPIKey()
    }

    func importFilesFromPanel() {
        presentImportPanel(linkToActiveNote: false)
    }

    func importAndLinkSourcesFromPanel() {
        presentImportPanel(linkToActiveNote: true)
    }

    private func presentImportPanel(linkToActiveNote: Bool) {
        let panel = NSOpenPanel()
        panel.title = ui("选择学习资料", "Choose study materials")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .pdf,
            .html,
            .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText
        ]

        guard panel.runModal() == .OK else { return }
        let selections = panel.urls
        let targetNoteID = linkToActiveNote ? activeNotebookItemID : nil
        Task {
            let discoveredURLs = await Task.detached(priority: .userInitiated) {
                StudyMaterialDiscovery.urls(from: selections)
            }.value
            let importedIDs = importDiscoveredFiles(discoveredURLs, selectFirst: !linkToActiveNote)
            guard linkToActiveNote, let noteID = targetNoteID, activeNotebookItemID == noteID else { return }
            let validSourceIDs = Set(allItems.filter { !$0.isNotebookNote }.map(\.id))
            var relations = NoteSourceRelations(links: noteSourceLinks)
            for sourceID in importedIDs where validSourceIDs.contains(sourceID) {
                relations.link(noteID: noteID, sourceID: sourceID, origin: selections.contains(where: { $0.hasDirectoryPath }) ? .folderBatch : .manual)
            }
            noteSourceLinks = relations.links
            save()
        }
    }

    @discardableResult
    func importFiles(_ urls: [URL], selectFirst: Bool = true) -> [String] {
        importDiscoveredFiles(StudyMaterialDiscovery.urls(from: urls), selectFirst: selectFirst)
    }

    @discardableResult
    private func importDiscoveredFiles(_ discoveredURLs: [URL], selectFirst: Bool) -> [String] {
        for index in importedItems.indices where importedItems[index].fileIdentity == nil {
            if let url = importedItems[index].url {
                importedItems[index].fileIdentity = StudyMaterialDiscovery.fileIdentity(for: url)
            }
        }
        var indexByPath: [String: Int] = [:]
        var indexByIdentity: [String: Int] = [:]
        for index in importedItems.indices {
            if let path = importedItems[index].urlPath, indexByPath[path] == nil { indexByPath[path] = index }
            if let identity = importedItems[index].fileIdentity, indexByIdentity[identity] == nil { indexByIdentity[identity] = index }
        }
        var itemIDs: [String] = []

        for url in discoveredURLs {
            let identity = StudyMaterialDiscovery.fileIdentity(for: url)
            if let index = indexByPath[url.path] ?? identity.flatMap({ indexByIdentity[$0] }) {
                importedItems[index].title = url.deletingPathExtension().lastPathComponent
                importedItems[index].subtitle = url.lastPathComponent
                importedItems[index].kind = StudyItemKind.detect(from: url)
                importedItems[index].urlPath = url.path
                importedItems[index].fileIdentity = identity
                indexByPath[url.path] = index
                if let identity { indexByIdentity[identity] = index }
                itemIDs.append(importedItems[index].id)
                continue
            }
            let item = StudyItem(
                id: "item:\(UUID().uuidString)",
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: StudyItemKind.detect(from: url),
                urlPath: url.path,
                fileIdentity: identity,
                isSample: false
            )
            importedItems.append(item)
            let index = importedItems.index(before: importedItems.endIndex)
            indexByPath[url.path] = index
            if let identity { indexByIdentity[identity] = index }
            itemIDs.append(item.id)
        }
        if selectFirst, let first = itemIDs.first {
            select(itemID: first)
        } else {
            save()
        }
        return itemIDs
    }

    func promptRenameNotebookNote(itemID: String) {
        guard let item = allItems.first(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        notebookCreationDraft = nil
        notebookRenameDraft = NotebookRenameDraft(itemID: item.id, title: displayTitle(for: item))
        showLibrary = true
        focus(.library)
    }

    func cancelRenameNotebookNote() {
        notebookRenameDraft = nil
    }

    func confirmRenameNotebookNote() {
        guard let draft = notebookRenameDraft else { return }
        renameNotebookNote(itemID: draft.itemID, to: draft.title)
    }

    func renameNotebookNote(itemID: String, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            noteFileError = ui("笔记名不能为空。", "Note name cannot be empty.")
            return
        }
        guard let index = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }),
              let oldURL = importedItems[index].url else { return }

        persistCurrentNote()
        let oldItem = importedItems[index]
        let oldID = oldItem.id
        let oldTitle = displayTitle(for: oldItem)
        let newURL = renamedNotebookURL(in: oldURL.deletingLastPathComponent(), title: title, currentURL: oldURL)

        do {
            if oldURL.path != newURL.path {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            }
            importedItems[index].title = newURL.deletingPathExtension().lastPathComponent
            importedItems[index].subtitle = newURL.lastPathComponent
            importedItems[index].urlPath = newURL.path
            importedItems[index].fileIdentity = StudyMaterialDiscovery.fileIdentity(for: newURL)
            if activeNotebookItemID == oldID {
                noteText = retitledMarkdown(noteText, from: oldTitle, to: importedItems[index].title)
                persistCurrentNote()
            } else if let markdown = try? String(contentsOf: newURL, encoding: .utf8) {
                let updated = retitledMarkdown(markdown, from: oldTitle, to: importedItems[index].title)
                if updated != markdown {
                    try updated.write(to: newURL, atomically: true, encoding: .utf8)
                }
            }
            if let cached = notesByItemID[oldID] {
                notesByItemID[oldID] = retitledMarkdown(cached, from: oldTitle, to: importedItems[index].title)
            }
            save()
            notebookRenameDraft = nil
            showTransientNoteStatus(ui("已重命名为：\(newURL.lastPathComponent)", "Renamed to: \(newURL.lastPathComponent)"))
        } catch {
            noteFileError = ui("无法重命名笔记：\(error.localizedDescription)", "Could not rename note: \(error.localizedDescription)")
        }
    }

    func openOrCreateWikiNote(title rawTitle: String) {
        let title = WikiLink.targetTitle(from: rawTitle)
        guard !title.isEmpty else { return }

        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)
        let fileName = "\(safeFileStem(title)).md"
        let url = notesDirectory.appendingPathComponent(fileName)

        if let index = importedItems.firstIndex(where: { $0.urlPath == url.path }) {
            importedItems[index].isNotebookNote = true
            select(itemID: importedItems[index].id)
            showTransientNoteStatus(ui("已打开双链笔记：\(importedItems[index].subtitle)", "Opened wiki note: \(importedItems[index].subtitle)"))
            save()
            return
        }

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
            }

            let item = StudyItem(
                id: "item:\(UUID().uuidString)",
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
            showTransientNoteStatus(ui("已创建双链笔记：\(url.lastPathComponent)", "Created wiki note: \(url.lastPathComponent)"))
        } catch {
            noteFileError = ui("无法创建双链笔记：\(error.localizedDescription)", "Could not create wiki note: \(error.localizedDescription)")
        }
    }

    private func createNotebookNote(seed: NotebookNoteSeed, title rawTitle: String? = nil) {
        let sourceItem: StudyItem?
        let defaultTitle = suggestedNotebookTitle(for: seed)
        switch seed {
        case .blank:
            sourceItem = nil
        case .currentMaterial(let item):
            sourceItem = item
        }
        let title = (rawTitle ?? defaultTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            noteFileError = ui("笔记名不能为空。", "Note name cannot be empty.")
            return
        }

        persistCurrentNote()
        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let url = nextNotebookNoteURL(in: notesDirectory, title: title)
            let item = StudyItem(
                id: "item:\(UUID().uuidString)",
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                isSample: false,
                isNotebookNote: true
            )
            let markdown = defaultNotebookNote(title: item.title, sourceItem: sourceItem)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            importedItems.append(item)
            activateNotebookItem(item)
            if let sourceItem {
                var relations = NoteSourceRelations(links: noteSourceLinks)
                relations.link(noteID: item.id, sourceID: sourceItem.id, origin: .noteCreation)
                noteSourceLinks = relations.links
            }
            noteText = markdown
            revealRichWritingSurface()
            focus(.notes)
            save()
            let status = sourceItem == nil
                ? ui("已新建空白笔记：\(url.lastPathComponent)", "Created blank note: \(url.lastPathComponent)")
                : ui("已为当前资料新建笔记：\(url.lastPathComponent)", "Created note from current material: \(url.lastPathComponent)")
            showTransientNoteStatus(status)
        } catch {
            noteFileError = ui("无法创建笔记：\(error.localizedDescription)", "Could not create note: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func openExistingNotebookNote(for material: StudyItem) -> Bool {
        guard let item = existingNotebookNote(for: material) else { return false }
        activateNotebookItem(item)
        revealRichWritingSurface()
        focus(.notes)
        save()
        showTransientNoteStatus(ui("已打开现有资料笔记：\(item.subtitle)", "Opened existing material note: \(item.subtitle)"))
        return true
    }

    private func existingNotebookNote(for material: StudyItem) -> StudyItem? {
        let currentTitle = suggestedNotebookTitle(for: .currentMaterial(material))
        let chineseTitle = "\(material.title) 笔记"
        let englishTitle = "\(material.title) Notes"
        let displayChineseTitle = "\(displayTitle(for: material)) 笔记"
        let displayEnglishTitle = "\(displayTitle(for: material)) Notes"
        let titles = Set([currentTitle, chineseTitle, englishTitle, displayChineseTitle, displayEnglishTitle])
        return allItems.first { item in
            item.isNotebookNote && titles.contains(item.title)
        }
    }

    private func suggestedNotebookTitle(for seed: NotebookNoteSeed) -> String {
        switch seed {
        case .blank:
            return ui("新笔记", "New Note")
        case .currentMaterial(let item):
            return ui("\(displayTitle(for: item)) 笔记", "\(displayTitle(for: item)) Notes")
        }
    }

    func useSelectedMarkdownAsNotebookNote() {
        guard let selectedItemID,
              let index = importedItems.firstIndex(where: { $0.id == selectedItemID && $0.canBecomeNotebookNote }) else { return }
        persistCurrentNote()
        importedItems[index].isNotebookNote = true
        activateNotebookItem(importedItems[index])
        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.links.filter { $0.sourceID == importedItems[index].id }.forEach { link in
            relations.unlink(noteID: link.noteID, sourceID: link.sourceID)
        }
        noteSourceLinks = relations.links
        if selectedItemID == importedItems[index].id {
            self.selectedItemID = sampleItems.first?.id
            readerLocationTitle = selectedMaterialItem.map(displayTitle)
        }
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
            guard selectedMaterialItem != nil || activeNoteItem?.isNotebookNote == true else { return }
            reference = ui("来源：\(currentReferenceTitle)", "Source: \(currentReferenceTitle)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference, forType: .string)
    }

    func updateSelection(_ text: String, source: SelectionSource, anchor: CGPoint? = nil, ownerTitle: String? = nil, isEditable: Bool = true) {
        let cleaned = MarkdownSelectionSanitizer.clean(text)
        guard Self.hasMeaningfulSelectionCharacter(cleaned) else {
            let now = Date()
            if lastSelectionUpdateDate.map({ now.timeIntervalSince($0) > selectionAttachmentMergeWindow }) ?? true {
                lastSelectionUpdateDate = nil
            }
            clearUnpinnedFloatingSelection(keepContext: false)
            return
        }
        lastSelectionUpdateDate = Date()
        let cleanedOwnerTitle = ownerTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOwnerTitle = (cleanedOwnerTitle?.isEmpty == false ? cleanedOwnerTitle : nil) ?? selectionOwnerTitle(for: source)
        let boundedText = Self.boundedSelectionText(cleaned)
        let shouldRevealSelectionPrompt = anchor != nil || pinnedFloatingAgent
        let contentMatches = selectionContext.map {
            $0.text == boundedText
                && $0.source == source
                && $0.ownerTitle == resolvedOwnerTitle
                && $0.isEditable == isEditable
        } ?? false

        // Drag stream: same text, only anchor moves — no spring, no new SelectionContext id.
        if contentMatches {
            let anchorUnchanged = Self.anchorsApproximatelyEqual(selectionAnchor, anchor)
            let surfaceAlreadyCorrect = shouldRevealSelectionPrompt
                ? agentSurface == .selectionFloat
                : agentSurface != .selectionFloat
            if anchorUnchanged, !pinnedFloatingAgent, surfaceAlreadyCorrect {
                return
            }
            if !anchorUnchanged {
                selectionAnchor = anchor
            }
            pinnedFloatingAgent = false
            cancelPendingSelectionAttachment()
            if shouldRevealSelectionPrompt {
                if agentSurface != .selectionFloat {
                    withAnimation(WeiBeiMotion.panel) {
                        agentSurface = .selectionFloat
                        showQuietInsight = false
                    }
                } else {
                    showQuietInsight = false
                }
            } else if agentSurface == .selectionFloat {
                withAnimation(WeiBeiMotion.panel) {
                    agentSurface = .hidden
                }
            }
            return
        }

        clearGeneratedQuietInsight()
        let nextSelection = SelectionContext(
            text: boundedText,
            source: source,
            ownerTitle: resolvedOwnerTitle,
            isEditable: isEditable
        )
        // Continuous fields update immediately so the capsule tracks like a native selection tool.
        // Only agentSurface show/hide keeps a one-shot panel spring.
        selectionContext = nextSelection
        selectionAnchor = anchor
        floatingSelectionPrompt = nextSelection.label(language: interfaceLanguage)
        pinnedFloatingAgent = false
        cancelPendingSelectionAttachment()
        if shouldRevealSelectionPrompt {
            if agentSurface != .selectionFloat {
                withAnimation(WeiBeiMotion.panel) {
                    agentSurface = .selectionFloat
                    showQuietInsight = false
                }
            } else {
                showQuietInsight = false
            }
        } else if agentSurface == .selectionFloat {
            withAnimation(WeiBeiMotion.panel) {
                agentSurface = .hidden
            }
        }
    }

    private static func anchorsApproximatelyEqual(_ lhs: CGPoint?, _ rhs: CGPoint?, epsilon: CGFloat = 0.5) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return abs(left.x - right.x) < epsilon && abs(left.y - right.y) < epsilon
        default:
            return false
        }
    }

    func removeSelectionAttachment(id: UUID) {
        // Instant remove — animation here made the chip absorb the first click while hover/popover settled.
        cancelPendingSelectionAttachment()
        let removed = selectionAttachments.first(where: { $0.id == id })
        selectionAttachments.removeAll { $0.id == id }
        if selectionContext?.id == id {
                clearUnpinnedFloatingSelection(keepContext: false)
        } else if selectionAttachments.isEmpty || removed.map({ selectionContext?.text == $0.text }) == true {
            clearUnpinnedFloatingSelection(keepContext: false)
        }
    }

    func clearSelectionAttachments() {
        // Instant clear so one click always wins over hover-popover dismissal races.
        cancelPendingSelectionAttachment()
        selectionAttachments = []
        lastSelectionAttachmentDate = nil
        lastSelectionUpdateDate = nil
        clearUnpinnedFloatingSelection(keepContext: false)
    }

    private func scheduleSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool) {
        pendingSelectionAttachmentTask?.cancel()
        pendingSelectionAttachmentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.selectionAttachmentDebounceDelay ?? 520_000_000)
            guard !Task.isCancelled else { return }
            guard self?.selectionContext?.id == selection.id else { return }
            withAnimation(WeiBeiMotion.panel) {
                self?.addSelectionAttachment(selection, withinSelectionGesture: withinSelectionGesture)
            }
            self?.pendingSelectionAttachmentTask = nil
        }
    }

    private func cancelPendingSelectionAttachment() {
        pendingSelectionAttachmentTask?.cancel()
        pendingSelectionAttachmentTask = nil
    }

    private func addSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool = false) {
        let cleanedText = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.hasMeaningfulSelectionCharacter(cleanedText) else { return }
        let cleanedSelection = SelectionContext(
            id: selection.id,
            text: cleanedText,
            source: selection.source,
            ownerTitle: selection.ownerTitle,
            isEditable: selection.isEditable
        )
        let now = Date()
        defer { lastSelectionAttachmentDate = now }
        let sameSelectionSource: (SelectionContext) -> Bool = {
            $0.ownerTitle == cleanedSelection.ownerTitle && $0.source == cleanedSelection.source
        }
        if selectionAttachments.contains(where: {
            sameSelectionSource($0)
                && SelectionAttachmentMerge.containsSelection($0.text, fragment: cleanedText)
        }) {
            return
        }
        selectionAttachments.removeAll {
            sameSelectionSource($0)
                && SelectionAttachmentMerge.containsSelection(cleanedText, fragment: $0.text)
        }
        var nextSelection = cleanedSelection
        while let mergeIndex = selectionAttachments.indices.reversed().first(where: {
            shouldMergeSelectionAttachment(selectionAttachments[$0], with: nextSelection, at: now, withinSelectionGestureHint: withinSelectionGesture)
        }) {
            nextSelection = mergedSelectionAttachment(selectionAttachments[mergeIndex], with: nextSelection)
            selectionAttachments.remove(at: mergeIndex)
        }
        selectionAttachments.append(nextSelection)
        let maxAttachments = 8
        if selectionAttachments.count > maxAttachments {
            selectionAttachments.removeFirst(selectionAttachments.count - maxAttachments)
        }
    }

    private func shouldMergeSelectionAttachment(_ existing: SelectionContext, with incoming: SelectionContext, at now: Date, withinSelectionGestureHint: Bool) -> Bool {
        guard existing.source == incoming.source, existing.ownerTitle == incoming.ownerTitle else { return false }
        let withinSelectionGesture = lastSelectionAttachmentDate.map {
            now.timeIntervalSince($0) <= selectionAttachmentMergeWindow
        } ?? false
        return SelectionAttachmentMerge.mergedText(
            existing: existing.text,
            incoming: incoming.text,
            withinSelectionGesture: withinSelectionGesture || withinSelectionGestureHint
        ) != nil
    }

    private func mergedSelectionAttachment(_ existing: SelectionContext, with incoming: SelectionContext) -> SelectionContext {
        let mergedText = SelectionAttachmentMerge.mergedText(
            existing: existing.text,
            incoming: incoming.text,
            withinSelectionGesture: true
        ) ?? incoming.text
        return SelectionContext(
            id: existing.id,
            text: Self.boundedSelectionText(mergedText),
            source: existing.source,
            ownerTitle: existing.ownerTitle,
            isEditable: incoming.isEditable
        )
    }

    private static func hasMeaningfulSelectionCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private func selectionOwnerTitle(for source: SelectionSource) -> String {
        if source == .note || activeNoteItem?.isNotebookNote == true {
            return activeNoteItem.map(displayTitle) ?? ui("当前笔记", "Current note")
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
        agentDraft = ui(
            "请根据\(agentPromptScope)，把笔记整理成更清晰的大纲，保留来源信息，并标出缺少证据的位置。",
            "Use \(agentPromptScope) to organize the note into a clearer outline, keep source references, and mark places where evidence is missing."
        )
        Task { await askAgent() }
    }

    func askSelection() {
        if let selectionContext {
            if isConversationSurfaceVisible {
                routeSelectionToConversation(selectionContext)
            } else {
                withAnimation(WeiBeiMotion.panel) {
                    cancelPendingSelectionAttachment()
                    addSelectionAttachment(selectionContext)
                    floatingSelectionPrompt = selectionContext.label(language: interfaceLanguage)
                    agentSurface = .selectionFloat
                    showQuietInsight = false
                    focus(.agent)
                }
            }
        } else {
            withAnimation(WeiBeiMotion.panel) {
                agentDraft = ui(
                    "请根据\(agentPromptScope)，帮我梳理重点和可追问的问题。",
                    "Use \(agentPromptScope) to summarize key points and follow-up questions."
                )
                if layout == .immersiveReading || layout == .documentNotesSplit {
                    agentSurface = .cornerPanel
                }
                focus(.agent)
            }
        }
    }

    func routeSelectionToConversation(_ selection: SelectionContext? = nil) {
        let context = selection ?? selectionContext
        withAnimation(WeiBeiMotion.panel) {
            if let context {
                cancelPendingSelectionAttachment()
                addSelectionAttachment(context)
                floatingSelectionPrompt = context.label(language: interfaceLanguage)
            }
            if agentSurface == .selectionFloat {
                agentSurface = .hidden
            }
            selectionAnchor = nil
            pinnedFloatingAgent = false
            showQuietInsight = false
            focusedPane = .agent
            focusRequest += 1
        }
    }

    func appendSelectionToNote() {
        guard let selectionContext else { return }
        let block = """

        \(quotedReferenceBlock(text: selectionContext.text, sourceTitle: selectionContext.ownerTitle))
        """
        updateNote(noteText + block)
        if selectionContext.source == .document, let sourceID = selectedMaterialItem?.id, let noteID = activeNotebookItemID {
            var relations = NoteSourceRelations(links: noteSourceLinks)
            if relations.link(noteID: noteID, sourceID: sourceID, origin: .excerpt) {
                noteSourceLinks = relations.links
                save()
            }
        }
        focus(.notes)
    }

    private func quotedReferenceBlock(text: String, sourceTitle: String) -> String {
        let quoted = MarkdownSelectionSanitizer.clean(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return ui(
            """
            > [!quote] 选区摘录
            >
            \(quoted)
            >
            > 来源：\(sourceTitle)
            """,
            """
            > [!quote] Selection excerpt
            >
            \(quoted)
            >
            > Source: \(sourceTitle)
            """
        )
    }

    func acceptQuietInsight() {
        guard !quietInsight.noteBlock.isEmpty else { return }
        updateNote(noteText + "\n\n\(quietInsight.noteBlock)\n")
        showQuietInsight = false
        focus(.notes)
    }

    func askQuietInsight() {
        let evidenceText = hasSelectedMaterial ? ui("未在材料中确认", "not confirmed in the material") : ui("未在笔记或选区中确认", "not confirmed in the note or selection")
        agentDraft = """
        \(ui("请根据这条阅读线索继续解释，并结合\(agentPromptScope)回答。没有证据就说\(evidenceText)。", "Continue from this reading clue and answer using \(agentPromptScope). If there is no evidence, say \(evidenceText)."))

        \(ui("阅读线索", "Reading clue")):
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
        let contextScope = hasSelectedMaterial ? ui("当前材料、当前选区和当前笔记", "the current material, current selection, and current note") : ui("当前选区和当前笔记", "the current selection and current note")
        let evidenceText = hasSelectedMaterial ? ui("如果材料没有证据，就直接说未在材料中确认。", "If the material has no evidence, say it is not confirmed in the material.") : ui("如果笔记和选区没有证据，就直接说未在笔记或选区中确认。", "If the note and selection have no evidence, say it is not confirmed in the note or selection.")
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
                question: ui(
                    "请静默阅读\(contextScope)，只输出一条最值得提示给用户的洞察。要温和、短、可执行；\(evidenceText)",
                    "Read \(contextScope) quietly and output only the single most useful insight for the user. Keep it gentle, short, and actionable. \(evidenceText)"
                ),
                materialTitle: materialTitle,
                materialText: materialText,
                noteTitle: agentNoteTitle,
                noteText: currentNoteText,
                selectionTitle: selectionContext?.ownerTitle,
                selectionText: selectionText,
                recentMessages: [],
                language: interfaceLanguage
            )
            guard signature == makeQuietInsightSignature(materialText: selectedContextText, noteText: noteText, selectionText: selectionContext?.text) else { return }
            generatedQuietInsight = QuietInsight.agent(materialTitle: materialTitle, answer: answer, language: interfaceLanguage)
            quietInsightSignature = signature
        } catch {
            generatedQuietInsight = nil
        }
    }

    private var quietInsightReferenceTitle: String {
        selectionContext?.ownerTitle ?? (hasSelectedMaterial ? currentReferenceTitle : activeNoteItem.map(displayTitle)) ?? ui("当前笔记", "Current note")
    }

    func applyLastAgentAnswerToNote() {
        guard let answer = lastUsableAgentAnswer else { return }
        let block = "\n\n\(noteBlockForAgentAnswer(answer.text))"
        updateNote(noteText + block)
        focus(.notes)
    }

    func runVerificationScenarioIfNeeded() async {
        guard !didRunVerificationScenario else { return }
        guard Self.environmentValue("WEIBEI_SUPPRESS_ACTIVATION") == "1" else { return }
        let scenario = Self.environmentValue("WEIBEI_VERIFY_SCENARIO")
        let emptyWorkspaceScenarios: Set<String> = [
            "empty-workspace-light-wide",
            "empty-workspace-light-narrow",
            "empty-workspace-dark-wide",
            "empty-workspace-dark-narrow",
            "empty-workspace-calligraphy-light",
            "empty-workspace-calligraphy-dark",
            "empty-workspace-inspiration-off",
            "empty-workspace-open-doc",
            "empty-workspace-open-chat",
            "empty-workspace-open-notes",
        ]
        guard scenario == "offline-learning-flow"
            || scenario == "immersive-conversation-flow"
            || scenario == "notebook-creation-flow"
            || scenario == "linked-sources-flow"
            || emptyWorkspaceScenarios.contains(scenario) else { return }
        didRunVerificationScenario = true
        if emptyWorkspaceScenarios.contains(scenario) {
            configureEmptyWorkspaceVerificationScenario(scenario)
            return
        }
        layout = scenario == "immersive-conversation-flow" ? .immersiveConversation : .documentAgentNotes
        if scenario == "notebook-creation-flow" {
            layout = .immersiveWriting
        }
        if scenario == "linked-sources-flow" {
            layout = .immersiveWriting
        }
        showLibrary = scenario != "immersive-conversation-flow"
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        if scenario == "linked-sources-flow" {
            createNotebookNote(seed: .currentMaterial(sampleItems[0]), title: ui("多资料研究笔记", "Multi-source research note"))
            toggleSourceLinkToActiveNote("sample-pdf")
            select(itemID: "sample-pdf")
            showRightPane = true
            save()
            return
        }
        if scenario == "notebook-creation-flow" {
            promptCreateBlankNotebookNote()
            return
        }
        updateNote(ui("# 视觉验收笔记\n\n", "# Visual verification note\n\n"))
        updateSelection(
            ui("利率是资金使用价格的表达。", "An interest rate is the price paid for using funds."),
            source: .document,
            ownerTitle: currentReferenceTitle
        )
        agentDraft = ui("解释选区，并整理成可以写入笔记的要点。", "Explain the selection and turn it into note-ready points.")
        await askAgent()
        applyLastAgentAnswerToNote()
    }

    private func configureEmptyWorkspaceVerificationScenario(_ scenario: String) {
        layout = .documentAgentNotes
        showLibrary = false
        agentSurface = .hidden
        appearanceMode = scenario.contains("dark") ? .inkstone : .paper
        showDailyInspiration = scenario != "empty-workspace-inspiration-off"

        if scenario.hasPrefix("empty-workspace-open-") {
            select(itemID: "sample-html")
            updateNote("# Empty workspace entry state marker\n\nPane toggles must preserve this note.\n")
        }

        showReader = false
        showAgent = false
        showNotes = false

        switch scenario {
        case "empty-workspace-open-doc":
            toggleReader()
        case "empty-workspace-open-chat":
            toggleAgent()
        case "empty-workspace-open-notes":
            toggleNotes()
        default:
            save()
        }
    }

    func replaceSelectionWithLastAgentAnswer() {
        guard selectionContext?.isReplaceableNoteSelection == true,
              let answer = lastUsableAgentAnswer else { return }
        noteEditorCommand = NoteEditorCommand(kind: .replaceSelection, markdown: answer.text)
        focus(.notes)
    }

    func applyAgentPatchToEditor() {
        guard let answer = lastUsableAgentAnswer else { return }
        noteEditorCommand = NoteEditorCommand(kind: .applyAgentPatch, markdown: "\n\(noteBlockForAgentAnswer(answer.text))")
        focus(.notes)
    }

    private func noteBlockForAgentAnswer(_ answer: String) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suggestedNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: text, language: interfaceLanguage) {
            return suggestedNoteBlock
        }
        guard !text.hasPrefix("#") else { return text }
        return "## \(ui("整理建议", "Organization suggestion"))\n\(text)"
    }

    func askAgent() async {
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAskingAgent else { return }

        persistCurrentNote()
        let sentSelectionTitle = agentSelectionTitle
        let sentSelectionText = agentSelectionText
        let shouldClearSentDocumentSelection = sentSelectionText != nil && selectionContext?.source == .document
        let recentMessages = Array(messages.suffix(8))
        let sourceTitle = includeCurrentMaterialInAgentScope ? agentMessageSourceTitle : activeNoteItem.map(displayTitle)
        let requestMaterialTitle = includeCurrentMaterialInAgentScope ? currentReferenceTitle : ""
        let requestMaterialText = includeCurrentMaterialInAgentScope ? selectedContextText : ""
        let requestID = UUID()
        activeAgentRequestID = requestID
        isAskingAgent = true
        let requestLinkedSources = await loadSelectedLinkedAgentSources()
        guard activeAgentRequestID == requestID else { return }
        agentDraft = ""
        if !selectionAttachments.isEmpty {
            withAnimation(WeiBeiMotion.panel) {
                cancelPendingSelectionAttachment()
                selectionAttachments = []
                lastSelectionAttachmentDate = nil
                lastSelectionUpdateDate = nil
            }
        }
        if shouldClearSentDocumentSelection {
            clearUnpinnedFloatingSelection(keepContext: false)
        }
        guard let credential = resolvedOpenAIAPIKey() else {
            let notice = ui(
                "未配置密钥。当前用离线模式生成草稿；设置密钥后会结合\(agentPromptScope)，并在有已选文本片段时一并作答。",
                "No key is configured. WeiBei is generating an offline draft. After setup, answers will use \(agentPromptScope) and any selected text fragments."
            )
            openAIKeyStatus = notice
            messages.append(contentsOf: AgentOfflineTurn.messages(
                question: question,
                sourceTitle: sourceTitle,
                input: offlineAgentInput(
                    question: question,
                    selectionTitle: sentSelectionTitle,
                    selectionText: sentSelectionText,
                    materialTitle: requestMaterialTitle,
                    materialText: requestMaterialText,
                    linkedSources: requestLinkedSources
                )
            ))
            activeAgentRequestID = nil
            isAskingAgent = false
            return
        }

        messages.append(AgentMessage(role: .user, text: question, source: sourceTitle))
        do {
            let client = OpenAIResponsesClient(apiKey: credential.key, model: resolvedModelName)
            let answer = try await client.ask(
                question: question,
                materialTitle: requestMaterialTitle,
                materialText: requestMaterialText,
                noteTitle: agentNoteTitle,
                noteText: noteText,
                selectionTitle: sentSelectionTitle,
                selectionText: sentSelectionText,
                linkedSources: requestLinkedSources,
                recentMessages: recentMessages,
                language: interfaceLanguage
            )
            guard activeAgentRequestID == requestID else { return }
            messages.append(AgentMessage(role: .assistant, text: answer, source: sourceTitle))
        } catch {
            guard activeAgentRequestID == requestID else { return }
            messages.append(AgentMessage(role: .assistant, text: ui("请求失败：\(error.localizedDescription)", "Request failed: \(error.localizedDescription)"), source: sourceTitle))
        }

        if activeAgentRequestID == requestID {
            activeAgentRequestID = nil
            isAskingAgent = false
        }
    }

    private func offlineAgentInput(
        question: String,
        selectionTitle: String?,
        selectionText: String?,
        materialTitle: String,
        materialText: String,
        linkedSources: [StudyAgentSource]
    ) -> AgentOfflinePreviewInput {
        AgentOfflinePreviewInput(
            language: interfaceLanguage,
            question: question,
            hasMaterial: !materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            materialTitle: materialTitle,
            materialText: materialText,
            noteTitle: agentNoteTitle,
            noteText: noteText,
            selectionTitle: selectionTitle,
            selectionText: selectionText,
            linkedSources: linkedSources
        )
    }

    func sampleHTML(for item: StudyItem?) -> String {
        guard item?.id == "sample-html" else { return sampleMarkdownHTML(for: item) }
        let htmlLanguage = ui("zh-CN", "en")
        let title = ui("利率的含义与分类", "Meaning and Types of Interest Rates")
        let intro = ui("利率是资金使用价格的表达，也是金融市场配置资源时最敏感的信号之一。", "An interest rate is the price paid for using funds, and one of the most sensitive signals in financial resource allocation.")
        let nominalTitle = ui("名义利率与实际利率", "Nominal and Real Interest Rates")
        let nominalBody = ui("名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。", "A nominal interest rate is expressed in money terms; a real interest rate adjusts for purchasing power changes caused by inflation.")
        let quote = ui("学习时要同时记录概念、公式、例子和材料出处，避免只留下孤立结论。", "When studying, record concepts, formulas, examples, and sources together so conclusions do not stand alone.")
        let termTitle = ui("短期利率与长期利率", "Short-Term and Long-Term Interest Rates")
        let termBody = ui("短期利率通常受流动性和政策操作影响，长期利率更能反映期限溢价与未来预期。", "Short-term rates are often shaped by liquidity and policy operations; long-term rates reflect term premiums and expectations.")
        let reviewTitle = ui("复习问题", "Review Question")
        let reviewQuestion = ui("为什么通货膨胀预期上升时，名义利率通常会上行？", "Why do nominal interest rates usually rise when expected inflation increases?")
        return """
        <!doctype html>
        <html lang="\(htmlLanguage)">
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
        <h1>\(title)</h1>
        <p>\(intro)</p>
        <h2>\(nominalTitle)</h2>
        <p>\(nominalBody)</p>
        <blockquote>\(quote)</blockquote>
        <h2>\(termTitle)</h2>
        <p>\(termBody)</p>
        <h2>\(reviewTitle)</h2>
        <p>\(reviewQuestion)</p>
        </main>
        </body>
        </html>
        """
    }

    func sampleText(for item: StudyItem?) -> String {
        switch item?.id {
        case "sample-html":
            return ui("利率是资金使用价格的表达。名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。", "An interest rate is the price paid for using funds. A nominal rate is expressed in money terms; a real rate adjusts for inflation.")
        case "sample-pdf":
            return ui("Mishkin 教材样例：金融体系通过降低交易成本和信息成本来改善资源配置。", "Mishkin textbook sample: the financial system improves resource allocation by reducing transaction and information costs.")
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
        guard let root = workspaceRootDirectory() else { return nil }
        let directory = root.appendingPathComponent("Samples", isDirectory: true)
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
        let title = item.map(displayTitle) ?? ui("课堂笔记样例", "Class Notes Sample")
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
        let root = Self.workspaceRootDirectory() ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBei", isDirectory: true)
        let directory = root.appendingPathComponent("Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func safeFileStem(_ value: String) -> String {
        MarkdownAttachmentStore.safeFileStem(value, fallback: ui("未命名", "Untitled"), limit: 80)
    }

    private func nextNotebookNoteURL(in directory: URL, title: String) -> URL {
        let stem = safeFileStem(title)
        var index = 1
        var url = directory.appendingPathComponent("\(stem).md")
        while FileManager.default.fileExists(atPath: url.path) {
            index += 1
            url = directory.appendingPathComponent("\(stem) \(index).md")
        }
        return url
    }

    private func renamedNotebookURL(in directory: URL, title: String, currentURL: URL) -> URL {
        let stem = safeFileStem(title)
        var index = 1
        var url = directory.appendingPathComponent("\(stem).md")
        while FileManager.default.fileExists(atPath: url.path) && url.path != currentURL.path {
            index += 1
            url = directory.appendingPathComponent("\(stem) \(index).md")
        }
        return url
    }

    private func retitledMarkdown(_ markdown: String, from oldTitle: String, to newTitle: String) -> String {
        let prefix = "# \(oldTitle)\n"
        guard markdown.hasPrefix(prefix) else { return markdown }
        return "# \(newTitle)\n" + String(markdown.dropFirst(prefix.count))
    }

    private func showTransientNoteStatus(_ message: String) {
        noteFileError = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self?.noteFileError == message {
                self?.noteFileError = nil
            }
        }
    }

    private func clearGeneratedQuietInsight() {
        if generatedQuietInsight != nil {
            generatedQuietInsight = nil
        }
        quietInsightSignature = ""
    }

    private func layoutMatchingThreePaneOrder(_ order: [WorkspacePaneRole]) -> WorkspaceLayout {
        let normalized = WorkspacePaneRole.normalized(order)
        if normalized == [.reader, .notes, .agent] {
            return .documentNotesAgent
        }
        return .documentAgentNotes
    }

    private var rightPaneRevealFocus: PaneFocus {
        if layout.isDocumentThreePane {
            return normalizedThreePaneOrder.last?.focus ?? .notes
        }
        switch layout {
        case .documentNotesAgent, .immersiveConversation:
            return .agent
        default:
            return .notes
        }
    }

    private func clearUnpinnedFloatingSelection(keepContext: Bool = true) {
        if !keepContext {
            cancelPendingSelectionAttachment()
            selectionContext = nil
            selectionAnchor = nil
            floatingSelectionPrompt = ui("当前选区", "Current selection")
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
        let title = item.map(displayTitle) ?? ui("新笔记", "New Note")
        let sourceItem = item?.isNotebookNote == true ? nil : item
        return defaultNotebookNote(title: title, sourceItem: sourceItem)
    }

    private func defaultNotebookNote(title: String, sourceItem: StudyItem?) -> String {
        let excerptSeed = sourceItem.map { ui("> 来源：\(displayTitle(for: $0))\n", "> Source: \(displayTitle(for: $0))\n") } ?? ""
        return """
        # \(title)

        ## \(ui("核心要点", "Key Points"))

        ## \(ui("摘录", "Excerpts"))
        \(excerptSeed)

        ## \(ui("待追问", "Follow-up Questions"))
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
            noteFileError = ui("无法读取原 Markdown：\(url.lastPathComponent)", "Could not read original Markdown: \(url.lastPathComponent)")
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
    }

    private func persistCurrentNote() {
        guard let item = activeNoteItem else { return }
        cancelPendingNotePersistence(for: item.id)
        persistNote(noteText, for: item)
    }

    func flushPendingNotePersistence() {
        let itemIDs = Array(pendingNotePersistenceByItemID.keys)
        itemIDs.forEach { flushPendingNotePersistence(for: $0) }
    }

    private func scheduleNotePersistence(_ markdown: String, for item: StudyItem) {
        pendingNotePersistenceByItemID[item.id] = PendingNotePersistence(item: item, markdown: markdown)
        pendingNotePersistenceTasks[item.id]?.cancel()
        let itemID = item.id
        let delay = notePersistenceDebounceDelay
        pendingNotePersistenceTasks[itemID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.flushPendingNotePersistence(for: itemID)
        }
    }

    private func flushPendingNotePersistence(for itemID: String) {
        cancelPendingNotePersistence(for: itemID)
        guard let pending = pendingNotePersistenceByItemID.removeValue(forKey: itemID) else { return }
        persistNote(pending.markdown, for: pending.item)
        save()
    }

    private func cancelPendingNotePersistence(for itemID: String) {
        pendingNotePersistenceTasks[itemID]?.cancel()
        pendingNotePersistenceTasks[itemID] = nil
    }

    private func persistNote(_ markdown: String, for item: StudyItem) {
        let noteItemID = item.id
        if item.editsBackingMarkdownFile, let url = item.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                notesByItemID.removeValue(forKey: noteItemID)
                noteFileError = nil
            } catch {
                notesByItemID[noteItemID] = markdown
                noteFileError = ui("无法写回原 Markdown：\(url.lastPathComponent)", "Could not write original Markdown: \(url.lastPathComponent)")
            }
            return
        }
        notesByItemID[noteItemID] = markdown
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? JSONDecoder().decode(PersistedWorkspace.self, from: data) else {
            return
        }
        importedItems = snapshot.importedItems
        var didHydrateFileIdentity = false
        for index in importedItems.indices where importedItems[index].fileIdentity == nil {
            guard let url = importedItems[index].url,
                  let identity = StudyMaterialDiscovery.fileIdentity(for: url) else { continue }
            importedItems[index].fileIdentity = identity
            didHydrateFileIdentity = true
        }
        notesByItemID = snapshot.notesByItemID.mapValues(cleanLegacyPlaceholder)
        noteSourceLinks = NoteSourceRelations(links: snapshot.noteSourceLinks).links
        selectedItemID = snapshot.selectedItemID
        activeNotebookItemID = snapshot.activeNotebookItemID
        if selectedItem?.isNotebookNote == true {
            activeNotebookItemID = selectedItemID
            selectedItemID = sampleItems.first?.id
        }
        if let activeNotebookItemID,
           !allItems.contains(where: { $0.id == activeNotebookItemID && $0.isNotebookNote }) {
            self.activeNotebookItemID = nil
        }
        if let modelName = snapshot.modelName {
            self.modelName = modelName
        }
        if let workspaceLayout = snapshot.workspaceLayout {
            layout = workspaceLayout
            if let order = workspaceLayout.defaultThreePaneOrder {
                threePaneOrder = order
            }
        }
        if let threePaneOrder = snapshot.threePaneOrder {
            self.threePaneOrder = WorkspacePaneRole.normalized(threePaneOrder)
        }
        if let agentSurface = snapshot.agentSurface {
            self.agentSurface = agentSurface == .selectionFloat ? .hidden : agentSurface
        }
        if let noteRenderMode = snapshot.noteRenderMode {
            self.noteRenderMode = noteRenderMode.visibleMode
        }
        if let showLibrary = snapshot.showLibrary {
            self.showLibrary = showLibrary
        }
        let legacyRightPane = snapshot.showRightPane
        showReader = snapshot.showReader ?? true
        showAgent = snapshot.showAgent ?? legacyRightPane ?? true
        showNotes = snapshot.showNotes ?? legacyRightPane ?? true
        showDailyInspiration = snapshot.showDailyInspiration ?? true
        if let appearanceModeRaw = snapshot.appearanceModeRaw,
           let appearanceMode = WeiBeiAppearanceMode(rawValue: appearanceModeRaw) {
            self.appearanceMode = appearanceMode
        }
        adaptImportedDocumentColors = snapshot.adaptImportedDocumentColors ?? true
        if let interfaceLanguageRaw = snapshot.interfaceLanguageRaw,
           let interfaceLanguage = WeiBeiInterfaceLanguage(rawValue: interfaceLanguageRaw) {
            self.interfaceLanguage = interfaceLanguage
        }
        noteText = noteText(for: activeNoteItem)
        selectedAgentSourceIDs = []
        includeCurrentMaterialInAgentScope = true
        if didHydrateFileIdentity { save() }
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
            noteSourceLinks: noteSourceLinks,
            selectedItemID: selectedItemID,
            activeNotebookItemID: activeNotebookItemID,
            modelName: modelName,
            workspaceLayout: layout,
            threePaneOrder: normalizedThreePaneOrder,
            agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface,
            noteRenderMode: noteRenderMode,
            showLibrary: showLibrary,
            showReader: showReader,
            showAgent: showAgent,
            showNotes: showNotes,
            showRightPane: showRightPane,
            showDailyInspiration: showDailyInspiration,
            appearanceModeRaw: appearanceMode.rawValue,
            adaptImportedDocumentColors: adaptImportedDocumentColors,
            interfaceLanguageRaw: interfaceLanguage.rawValue
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }

    private func resolvedOpenAIAPIKey() -> (key: String, source: String)? {
        if Self.environmentValue("WEIBEI_FORCE_OFFLINE_AGENT") == "1" {
            return nil
        }

        let environmentKey = Self.environmentValue("OPENAI_API_KEY")
        if !environmentKey.isEmpty {
            return (environmentKey, ui("本机环境变量", "local environment variable"))
        }

        let savedKey = OpenAIAPIKeyStore.load()
        if !savedKey.isEmpty {
            return (savedKey, ui("macOS 钥匙串", "macOS Keychain"))
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

    private static func workspaceRootDirectory() -> URL? {
        let override = environmentValue("WEIBEI_WORKSPACE_DIR")
        if !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WeiBei", isDirectory: true)
    }
}
