import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Selection, navigation, pane layout, and presentation behavior exposed by the workspace façade.
extension WorkspaceStore {
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
        if let text = DocumentTextExtractor.cachedText(for: item), !text.isEmpty {
            return text
        }
        return sampleText(for: item)
    }

    var selectedMaterialTitle: String {
        selectedMaterialItem.map(displayTitle) ?? ui("未选择材料", "No material selected")
    }

    var agentMessageSourceTitle: String? {
        hasSelectedMaterial ? currentSourceReferenceTitle : activeNoteItem.map(displayTitle)
    }

    var currentReferenceTitle: String {
        readerLocationTitle ?? selectedMaterialItem.map(displayTitle) ?? activeNoteItem.map(displayTitle) ?? ui("当前笔记", "Current note")
    }

    var currentSourceReferenceTitle: String {
        guard let item = selectedMaterialItem else {
            return activeNoteItem.map(displayTitle) ?? ui("当前笔记", "Current note")
        }
        let itemTitle = sourceReferenceBaseTitle(for: item)
        switch item.kind {
        case .pdf:
            return ui("\(itemTitle)，第 \(readerPageIndex + 1) 页", "\(itemTitle), page \(readerPageIndex + 1)")
        case .html:
            guard let locationTitle = readerLocationTitle,
                  locationTitle != itemTitle else { return itemTitle }
            if let locationID = readerLocationID,
               locationID.hasPrefix("html-section-") {
                return ui(
                    "\(itemTitle)，章节标识：\(locationID)，章节：\(locationTitle)",
                    "\(itemTitle), section id: \(locationID), section: \(locationTitle)"
                )
            }
            let sectionOrdinal = readerLocationID.flatMap { id -> Int? in
                guard id.hasPrefix("html-heading-") else { return nil }
                return Int(id.dropFirst("html-heading-".count)).map { $0 + 1 }
            }
            if let sectionOrdinal {
                return ui(
                    "\(itemTitle)，章节序号：\(sectionOrdinal)，章节：\(locationTitle)",
                    "\(itemTitle), section number: \(sectionOrdinal), section: \(locationTitle)"
                )
            }
            return ui("\(itemTitle)，章节：\(locationTitle)", "\(itemTitle), section: \(locationTitle)")
        case .markdown, .text:
            return itemTitle
        }
    }

    func sourceReferenceBaseTitle(for item: StudyItem) -> String {
        let title = displayTitle(for: item)
        let catalog = Array(allItems.prefix(500))
        let matchingIndexes = catalog.indices.filter {
            displayTitle(for: catalog[$0]) == title
        }
        guard matchingIndexes.count > 1,
              let index = catalog.firstIndex(where: { $0.id == item.id }) else {
            return title
        }
        return ui("\(title)，条目：\(index + 1)", "\(title), item: \(index + 1)")
    }

    var hasSelectionAttachments: Bool {
        !selectionAttachments.isEmpty
    }

    var agentSelectionTitle: String? {
        if !selectionAttachments.isEmpty {
            if selectionAttachments.count == 1 {
                return selectionAttachments[0].ownerTitle
            }
            return ui("\(selectionAttachments.count) 个已选文本片段", "\(selectionAttachments.count) selected text fragments")
        }
        // Live selection (before/without 「问」 attachment) still counts as ask context.
        let live = selectionContext?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !live.isEmpty else { return nil }
        return selectionContext?.ownerTitle
    }

    var agentSelectionText: String? {
        if !selectionAttachments.isEmpty {
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
        guard let selectionContext else { return nil }
        let live = selectionContext.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !live.isEmpty else { return nil }
        return ui(
            """
            选区（来源：\(selectionContext.ownerTitle)）：
            \(live)
            """,
            """
            Selection (source: \(selectionContext.ownerTitle)):
            \(live)
            """
        )
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
        isAskingAgent ? ui("停止回答", "Stop response") : ui("发送问题", "Send question")
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
        activeStudySessionTitle
    }

    var agentPromptScope: String {
        hasSelectedMaterial ? ui("当前材料和当前笔记", "the current material and current note") : ui("当前笔记", "the current note")
    }

    var agentInputPrompt: String {
        if hasSelectionAttachments {
            return ui("输入问题", "Ask a question")
        }
        return hasSelectedMaterial
            ? ui("问当前课程或材料", "Ask the course or current material")
            : ui("问当前课程或笔记", "Ask the course or current note")
    }

    var selectionPromptScope: String {
        selectionContext?.source == .note ? ui("当前笔记", "the current note") : agentPromptScope
    }

    var canApplyAgentAnswer: Bool {
        lastUsableAgentAnswer != nil
    }

    var agentWriteActionTitle: String {
        latestAgentNoteProposal == nil
            ? ui("写入回答", "Write Answer")
            : ui("写入建议", "Write Proposal")
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

    var quietInsightReferenceTitle: String {
        selectionContext?.ownerTitle
            ?? (hasSelectedMaterial ? currentSourceReferenceTitle : activeNoteItem.map(displayTitle))
            ?? ui("当前笔记", "Current note")
    }

    /// Single source of truth for "which env-var override is active for the key field".
    /// Empty when none. Consolidates the three previously independent checks (see M4):
    /// the former `openAIKeyHelpText` detection and the `envKeyOverride` /
    /// `envModelOverride` copies in the Settings view extensions.
    var activeKeyEnvOverride: String {
        let envName = agentProviderID.environmentAPIKeyName
        if !Self.environmentValue(envName).isEmpty { return envName }
        if agentProviderID != .openai,
           !Self.environmentValue("OPENAI_API_KEY").isEmpty {
            return "OPENAI_API_KEY"
        }
        return ""
    }

    /// Single source of truth for "which env-var override is active for the model field".
    /// Empty when none. Replaces the `envModelOverride` copy in AgentModelPicker.swift.
    var activeModelEnvOverride: String {
        let pi = ProcessInfo.processInfo.environment["WEIBEI_PI_MODEL"] ?? ""
        let openai = ProcessInfo.processInfo.environment["WEIBEI_OPENAI_MODEL"] ?? ""
        return !pi.isEmpty ? "WEIBEI_PI_MODEL" : (!openai.isEmpty ? "WEIBEI_OPENAI_MODEL" : "")
    }

    var openAIKeyHelpText: String {
        // Env-var override takes precedence — the Settings key is inert while set.
        if !activeKeyEnvOverride.isEmpty {
            return ui(
                "正在使用本机环境变量 \(activeKeyEnvOverride)。设置里的密钥在没有环境变量时才会使用。",
                "Using local environment variable \(activeKeyEnvOverride). The Settings key is used only when that env is empty."
            )
        }
        let fieldKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)
        if !fieldKey.isEmpty {
            return ui(
                "当前提供商：\(agentProviderID.label(language: interfaceLanguage))。密钥保存在魏碑应用数据中，跨次启动自动带上。",
                "Provider: \(agentProviderID.label(language: interfaceLanguage)). The key is stored in WeiBei app data and restored on launch."
            )
        }
        return ui(
            "未配置 \(agentProviderID.label(language: interfaceLanguage)) 密钥。填入后自动保存即可提问。",
            "No \(agentProviderID.label(language: interfaceLanguage)) key yet. Enter one and it saves automatically."
        )
    }

    var piChatGPTSubscriptionConnected: Bool {
        Self.localPiSubscriptionAuthIsAvailable()
    }

    var piChatGPTSubscriptionModelLabel: String {
        let settings = Self.localPiSubscriptionSettings()
        let model = settings["defaultModel"] ?? "gpt-5.5"
        let thinking = settings["defaultThinkingLevel"]
        return thinking.map { "\(model) · \($0)" } ?? model
    }

    static func localPiSubscriptionAuthIsAvailable() -> Bool {
        WeiBeiAgentDataPaths.migrateHomePiAuthIfNeeded()
        let authURL = WeiBeiAgentDataPaths.piAuthJSON
        guard let data = try? Data(contentsOf: authURL),
              data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credential = root["openai-codex"] as? [String: Any],
              credential["type"] as? String == "oauth",
              let access = credential["access"] as? String,
              !access.isEmpty,
              let refresh = credential["refresh"] as? String,
              !refresh.isEmpty else {
            return false
        }
        return true
    }

    static func localPiSubscriptionSettings() -> [String: String] {
        let settingsURL = WeiBeiAgentDataPaths.piSettingsJSON
        guard let data = try? Data(contentsOf: settingsURL),
              data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["defaultProvider"] as? String == "openai-codex" else {
            return [:]
        }
        return ["defaultModel", "defaultThinkingLevel"].reduce(into: [:]) { result, key in
            if let value = root[key] as? String, !value.isEmpty {
                result[key] = value
            }
        }
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

    func itemMatchesLibrarySearch(_ item: StudyItem, query: String) -> Bool {
        displayTitle(for: item).localizedCaseInsensitiveContains(query)
            || displaySubtitle(for: item).localizedCaseInsensitiveContains(query)
            || item.kind.label(language: interfaceLanguage).localizedCaseInsensitiveContains(query)
            || noteTagsMatchLibrarySearch(item, query: query)
    }

    func noteTagsMatchLibrarySearch(_ item: StudyItem, query: String) -> Bool {
        guard item.isNotebookNote else { return false }
        return MarkdownTagSearch.matches(query: query, in: noteMarkdownText(for: item))
    }

    func noteMarkdownText(for item: StudyItem) -> String {
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
        WeiBeiPerf.measure("workspace.select") {
            selectMeasured(itemID: itemID)
        }
    }

    func selectMeasured(itemID: String?) {
        invalidateAgentContext()
        persistCurrentNote()
        notebookCreationDraft = nil
        notebookRenameDraft = nil
        if let itemID {
            alignActiveCourse(with: itemID)
        }
        if let itemID,
           let item = allItems.first(where: { $0.id == itemID && $0.isNotebookNote }) {
            activeNotebookItemID = item.id
            noteText = noteText(for: item)
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            syncActiveStudySession()
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
            clearUnpinnedFloatingSelection(keepContext: false)
            selectionAttachments = []
            lastSelectionAttachmentDate = nil
            readerPageIndex = 0
            readerLocationID = nil
            requestReaderPDFPage(nil, recordsLocation: false)
            readerTargetLocationID = nil
            readerTargetLocationTitle = nil
        }
        if itemChanged {
            readerLocationTitle = selectedMaterialItem.map(displayTitle)
            restoreCurrentStudyLocation()
            // Scheme A: hang current conversation, switch to the material's latest session
            // without wiping history. Messages stay on the StudySession record.
            if let materialID = selectedMaterialItem?.id {
                activateLatestStudySession(forMaterialID: materialID)
            }
        } else if readerLocationTitle == nil {
            readerLocationTitle = selectedMaterialItem.map(displayTitle)
        }
        clearReaderSearchIfNeeded()
        noteText = noteText(for: activeNoteItem)
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        syncActiveStudySession()
        recordCurrentStudyLocation(incrementVisit: itemChanged)
        clearGeneratedQuietInsight()
        refreshQuietInsightIfNeeded()
        save()
    }

    /// Activate the most recently updated session for a material, or keep the current empty one.
    func activateLatestStudySession(forMaterialID materialID: String) {
        syncActiveStudySession()
        if let active = activeStudySession,
           active.groupingMaterialItemID == materialID {
            return
        }
        if let match = orderedStudySessions.first(where: { $0.groupingMaterialItemID == materialID }) {
            activeStudySessionID = match.id
            messages = match.messages
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            lastAgentReplyContextRevision = nil
            invalidateAgentContext()
            return
        }
        // No session for this material yet: keep current session and re-tag it if empty.
        if let activeStudySessionID,
           let index = studySessions.firstIndex(where: { $0.id == activeStudySessionID }),
           studySessions[index].messages.isEmpty {
            studySessions[index].materialItemID = materialID
            if !studySessions[index].focusItemIDs.contains(materialID) {
                studySessions[index].focusItemIDs.insert(materialID, at: 0)
            }
        }
    }

    func alignActiveCourse(with itemID: String) {
        let containingCourseIDs = courseMembershipIndex.courseIDs(for: itemID)
        guard !containingCourseIDs.isEmpty else { return }
        if let activeCourseID, containingCourseIDs.contains(activeCourseID) { return }
        activeCourseID = containingCourseIDs.first
    }

    func setLinkedSourceIDsForActiveNote(_ sourceItemIDs: Set<String>) {
        guard let noteItemID = activeNotebookItemID else { return }
        setLinkedSourceIDs(sourceItemIDs, for: noteItemID)
    }

    func setLinkedSourceIDs(_ sourceItemIDs: Set<String>, for noteItemID: String) {
        guard allItems.contains(where: { $0.id == noteItemID && $0.isNotebookNote }) else { return }
        let validSourceIDs = Set(allItems.lazy.filter { !$0.isNotebookNote }.map(\.id))
        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.replaceSources(
            for: noteItemID,
            sourceItemIDs: sourceItemIDs.intersection(validSourceIDs)
        )
        guard relations.links != noteSourceLinks else { return }
        invalidateAgentContext()
        noteSourceLinks = relations.links
        save()
    }

    func setLinkedCourseSourceIDs(_ sourceItemIDs: Set<String>, for noteItemID: String) {
        let courseSourceIDs = Set(courseMaterials.map(\.id))
        let retainedNonCourseIDs = Set(linkedSourceIDs(for: noteItemID)).subtracting(courseSourceIDs)
        setLinkedSourceIDs(
            retainedNonCourseIDs.union(sourceItemIDs.intersection(courseSourceIDs)),
            for: noteItemID
        )
    }

    func setLinkedNoteIDs(_ noteItemIDs: Set<String>, for sourceItemID: String) {
        guard allItems.contains(where: { $0.id == sourceItemID && !$0.isNotebookNote }) else { return }
        let validNoteIDs = Set(courseNotebookItems.map(\.id))
        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.replaceNotes(
            for: sourceItemID,
            noteItemIDs: noteItemIDs.intersection(validNoteIDs)
        )
        guard relations.links != noteSourceLinks else { return }
        invalidateAgentContext()
        noteSourceLinks = relations.links
        save()
    }

    func presentCourseWorkspace(
        _ destination: CourseWorkspaceDestination = .hub,
        selecting itemID: String? = nil,
        courseID: UUID? = nil
    ) {
        persistCurrentNote()
        if let courseID {
            activateCourse(courseID)
        }
        courseWorkspaceReturnFocus = focusedPane
        courseWorkspaceDestination = destination
        courseWorkspaceTargetItemID = itemID
        courseWorkspacePresented = true
    }

    /// Sidebar / create-course entry into the course hub for a specific course.
    func openCourseSpace(_ courseID: UUID) {
        guard courses.contains(where: { $0.id == courseID }) else { return }
        showLibrary = false
        presentCourseWorkspace(.hub, courseID: courseID)
    }

    /// Drop / programmatic import into the active course (materials by default; Markdown stays material unless notes panel).
    @discardableResult
    func importCourseFilesFromURLs(_ urls: [URL], asNotes: Bool = false) -> [StudyItem] {
        let items = importFiles(
            urls,
            selectsFirstImportedItem: false,
            markdownAsNotes: asNotes,
            markdownOnly: asNotes,
            reclassifiesExistingMarkdown: true
        )
        if let courseID = activeCourseID {
            assignItemIDs(Set(items.map(\.id)), to: courseID)
        }
        return items
    }

    func dismissCourseWorkspace() {
        dismissCourseWorkspace(restoringFocus: true)
    }

    func openCourseMaterial(_ itemID: String) {
        guard courseMaterials.contains(where: { $0.id == itemID }) else { return }
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        select(itemID: itemID)
        if layout == .immersiveWriting || layout == .immersiveConversation {
            setLayout(.immersiveReading)
        } else {
            showReader = true
            focus(.reader)
            save()
        }
    }

    func openCourseNote(_ itemID: String) {
        guard courseNotebookItems.contains(where: { $0.id == itemID }) else { return }
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        select(itemID: itemID)
    }

    func continueCourseSession(_ sessionID: UUID) {
        guard studySessions.contains(where: { $0.id == sessionID && !$0.messages.isEmpty }) else { return }
        activateStudySession(sessionID)
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        setLayout(.immersiveConversation)
    }

    func dismissCourseWorkspace(restoringFocus: Bool) {
        guard courseWorkspacePresented else { return }
        courseWorkspacePresented = false
        courseWorkspaceTargetItemID = nil
        courseFolderImportDraft = nil
        guard restoringFocus, let courseWorkspaceReturnFocus else {
            self.courseWorkspaceReturnFocus = nil
            return
        }
        focusedPane = courseWorkspaceReturnFocus
        focusRequest += 1
        self.courseWorkspaceReturnFocus = nil
    }

    func selectAdjacentItem(step: Int) {
        let ids = navigableItems.map(\.id)
        guard let nextID = LibraryNavigator.adjacentID(in: ids, selectedID: selectedItemID, step: step) else { return }
        select(itemID: nextID)
        focus(.reader)
    }

    func updateNote(_ value: String) {
        guard noteText != value else { return }
        invalidateAgentContext()
        noteText = value
        clearGeneratedQuietInsight()
        guard let item = activeNoteItem else { return }
        if !item.editsBackingMarkdownFile {
            notesByItemID[item.id] = value
        }
        scheduleNotePersistence(value, for: item)
    }

    func stageNoteDraft(_ value: String, for itemID: String?) {
        guard let itemID else { return }
        if stagedNoteDraft?.itemID != itemID || stagedNoteDraft?.value != value {
            invalidateAgentContext()
        }
        stagedNoteDraft = (itemID, value)
    }

    func clearStagedNoteDraft(for itemID: String?, matching value: String? = nil) {
        guard let itemID, let stagedNoteDraft, stagedNoteDraft.itemID == itemID else { return }
        if let value, stagedNoteDraft.value != value { return }
        self.stagedNoteDraft = nil
    }

    func flushStagedNoteDraftForAgentContext() {
        guard let stagedNoteDraft, stagedNoteDraft.itemID == activeNoteItemID else { return }
        self.stagedNoteDraft = nil
        updateNote(stagedNoteDraft.value, for: stagedNoteDraft.itemID)
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
    func commitInactiveNoteDraft(_ value: String, itemID: String) {
        guard let item = allItems.first(where: { $0.id == itemID }) else { return }
        if !item.editsBackingMarkdownFile {
            notesByItemID[item.id] = value
        }
        scheduleNotePersistence(value, for: item)
    }

    func createBlankNotebookNote() {
        createNotebookNote(seed: .blank)
    }

    @discardableResult
    func createCourseNotebookNote(title: String) -> String? {
        createNotebookNote(seed: .blank, title: title)?.id
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

}
