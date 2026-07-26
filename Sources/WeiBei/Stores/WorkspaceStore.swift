import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// State of the model-list discovery shown in Settings → 对话服务 → 模型.
enum ModelListStatus: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
    case builtin

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

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

struct CourseFolderImportDraft: Identifiable {
    let id = UUID()
    var rootURLs: [URL]
    var markdownFiles: [URL]
    var notePaths: Set<String>
    var automaticMaterialCount: Int
}

struct ThreePaneReorderDrag: Equatable {
    var role: WorkspacePaneRole
    var translation: CGFloat
    var targetIndex: Int?
}

/// Isolated from `WorkspaceStore` so drag-translation updates do not rebuild reader/agent/notes.
@MainActor
final class ThreePaneReorderState: ObservableObject {
    @Published var drag: ThreePaneReorderDrag?
}

struct PaneExpansionRequest: Equatable {
    let id = UUID()
    let role: WorkspacePaneRole
}

enum PaneToggleContinuityVerifier {
    static var isMeasuring = false
    static var htmlEventSequence = 0
    static var htmlSectionEventCount = 0
    static var htmlActiveEventCount = 0
    static var htmlLocationCallCount = 0
    static var htmlLocationCommitCount = 0
    static var htmlLocationReasons: [String: Int] = [:]
    static var webReaderMakeCount = 0
    static var webReaderDismantleCount = 0
    static var pdfReaderMakeCount = 0
    static var pdfReaderDismantleCount = 0
    static var noteEditorMakeCount = 0
    static var noteEditorDismantleCount = 0
    static var verificationScrollScheduleCount = 0
    static var verificationScrollResult = ""

    static var isEnabled: Bool {
        let scenario = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_SCENARIO"]
        return scenario == "pane-toggle-continuity-flow"
            || scenario == "pane-layout-stability-flow"
            || scenario == "pane-reorder-width-flow"
            || scenario == "reader-scroll-persistence-flow"
            || scenario == "course-workspace-workflow-flow"
    }

    static func beginMeasurement() {
        guard isEnabled else { return }
        isMeasuring = true
        htmlSectionEventCount = 0
        htmlActiveEventCount = 0
        htmlLocationCallCount = 0
        htmlLocationCommitCount = 0
        htmlLocationReasons = [:]
        webReaderMakeCount = 0
        webReaderDismantleCount = 0
        pdfReaderMakeCount = 0
        pdfReaderDismantleCount = 0
        noteEditorMakeCount = 0
        noteEditorDismantleCount = 0
        verificationScrollScheduleCount = 0
        verificationScrollResult = ""
    }

    static func endMeasurement() {
        guard isEnabled else { return }
        isMeasuring = false
    }

    static func recordHTMLActiveEvent(reason: String) {
        guard isEnabled else { return }
        htmlEventSequence += 1
        if isMeasuring {
            htmlActiveEventCount += 1
        }
    }

    static func recordHTMLSectionEvent(count: Int) {
        guard isEnabled else { return }
        htmlEventSequence += 1
        if isMeasuring { htmlSectionEventCount += 1 }
    }

    static func recordHTMLLocationCall(reason: String) {
        guard isMeasuring else { return }
        htmlLocationCallCount += 1
        htmlLocationReasons[reason, default: 0] += 1
    }

    static func recordHTMLLocationCommit(reason: String) {
        guard isMeasuring else { return }
        htmlLocationCommitCount += 1
    }

    static func recordWebReaderMake() {
        guard isEnabled else { return }
        if isMeasuring { webReaderMakeCount += 1 }
    }

    static func recordWebReaderDismantle() {
        guard isEnabled else { return }
        if isMeasuring { webReaderDismantleCount += 1 }
    }

    static func recordNoteEditorMake() {
        guard isEnabled else { return }
        if isMeasuring { noteEditorMakeCount += 1 }
    }

    static func recordPDFReaderMake() {
        guard isEnabled else { return }
        if isMeasuring { pdfReaderMakeCount += 1 }
    }

    static func recordPDFReaderDismantle() {
        guard isEnabled else { return }
        if isMeasuring { pdfReaderDismantleCount += 1 }
    }

    static func recordNoteEditorDismantle() {
        guard isEnabled else { return }
        if isMeasuring { noteEditorDismantleCount += 1 }
    }

    static func recordVerificationScrollScheduled() {
        guard isEnabled else { return }
        verificationScrollScheduleCount += 1
    }

    static func recordVerificationScrollResult(_ result: String) {
        guard isEnabled else { return }
        verificationScrollResult = result
    }
}

enum CourseWorkspaceDestination: String, CaseIterable, Sendable {
    case hub
    case relations
    case materials
    case notes
    case sessions
}

/// Isolated chrome state for the course drawer.
/// Kept off `WorkspaceStore`'s `@Published` surface so opening/closing the drawer
/// does not invalidate reader/agent/notes bodies (that was the multi-second pre-slide lag).
@MainActor
final class LibraryDrawerState: ObservableObject {
    @Published var isOpen = false
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var importedItems: [StudyItem] = []
    @Published var selectedItemID: String?
    @Published var activeNotebookItemID: String?
    @Published var courses: [Course] = []
    @Published var courseItemMemberships: [CourseItemMembership] = [] {
        didSet {
            courseMembershipIndex = CourseItemMemberships(values: courseItemMemberships)
        }
    }
    @Published var activeCourseID: UUID?
    @Published var noteText = ""
    @Published var agentDraft = ""
    @Published var messages: [AgentMessage] = []
    @Published var isAskingAgent = false
    @Published var agentStreamingText = ""
    @Published var agentActivityText: String?
    @Published var showLoadingIndicatorSamples = false
    /// Last failed user question for precise one-tap retry.
    @Published var lastFailedAgentQuestion: String?
    @Published var lastAgentFailureKind: AgentFailureKind?
    @Published var latestAgentNoteProposal: StudyAgentNoteProposal?
    @Published var latestAgentLearningUpdate: StudyAgentLearningUpdate?
    @Published var noteSourceLinks: [NoteSourceLink] = [] {
        didSet {
            noteSourceRelationIndex = NoteSourceRelationIndex(links: noteSourceLinks)
        }
    }
    @Published var linkedSourcesPresented = false
    var studyLocationsByItemID: [String: StudyLocation] = [:]
    @Published var learningMemoryEntries: [LearningMemoryEntry] = []
    @Published var learningMemoryRevision: UInt64 = 0
    @Published var studySessions: [StudySession] = []
    @Published var activeStudySessionID: UUID?
    /// When true, session picker lists every session; otherwise groups by material with a View All entry.
    @Published var showAllStudySessions = false
    /// Drawer open flag lives on `libraryDrawer` so toggles only refresh drawer chrome.
    let libraryDrawer = LibraryDrawerState()
    var showLibrary: Bool {
        get { libraryDrawer.isOpen }
        set {
            if libraryDrawer.isOpen != newValue {
                libraryDrawer.isOpen = newValue
            }
        }
    }
    @Published var showReader = true
    @Published var showAgent = true
    @Published var showNotes = true
    @Published var showDailyInspiration = true
    @Published var commandPalettePresented = false
    @Published var librarySearch = ""
    @Published var readerSearch = ""
    @Published var showReaderSearch = false
    @Published var readerLocationID: String?
    @Published var readerLocationTitle: String?
    @Published var readerPageIndex = 0
    @Published var readerTargetPageIndex: Int?
    @Published var readerTargetPageRequestID = UUID()
    @Published var readerTargetPageRecordsLocation = false
    @Published var readerTargetLocationID: String?
    @Published var readerTargetLocationTitle: String?
    @Published var readerTargetLocationRequestID = UUID()
    @Published var focusedPane: PaneFocus = .reader
    @Published var focusRequest = 0
    @Published var layout: WorkspaceLayout = .documentAgentNotes
    @Published var threePaneOrder: [WorkspacePaneRole] = WorkspacePaneRole.defaultThreePaneOrder
    /// Live drag chrome only — not `@Published` on the main store (avoids full-tree thrash).
    let threePaneReorder = ThreePaneReorderState()
    var threePaneReorderDrag: ThreePaneReorderDrag? {
        get { threePaneReorder.drag }
        set {
            if threePaneReorder.drag != newValue {
                threePaneReorder.drag = newValue
            }
        }
    }
    @Published var paneExpansionRequest: PaneExpansionRequest?
    @Published var agentSurface: AgentSurface = .hidden
    @Published var noteRenderMode: NoteRenderMode = .rich
    @Published var showQuietInsight = true
    @Published var generatedQuietInsight: QuietInsight?
    @Published var isGeneratingQuietInsight = false
    @Published var floatingSelectionPrompt = ""
    @Published var pinnedFloatingAgent = false
    @Published var selectionContext: SelectionContext?
    @Published var selectionAttachments: [SelectionContext] = []
    @Published var selectionAnchor: CGPoint?
    /// Durable selection→chat threads (underline marks + reopen floating Q&A).
    @Published var selectionAskThreads: [SelectionAskThread] = []
    /// Thread currently shown in the floating selection agent (full answer surface).
    @Published var activeSelectionAskThreadID: UUID?
    /// Keeps the floating agent open while a selection-based answer streams.
    @Published var keepFloatingSelectionForAnswer = false
    @Published var noteEditorCommand: NoteEditorCommand?
    @Published var noteFileError: String?
    /// Success / info banner for note create/switch — separate from errors so it auto-dismisses cleanly.
    @Published var transientNoteStatus: String?
    @Published var workspaceSaveError: String?
    @Published var notebookCreationDraft: NotebookCreationDraft?
    @Published var notebookRenameDraft: NotebookRenameDraft?
    @Published var modelName: String = ProcessInfo.processInfo.environment["WEIBEI_OPENAI_MODEL"] ?? "gpt-5.5"
    @Published var agentProviderID: AgentProviderID = .openai
    @Published var agentBaseURL: String = ""
    @Published var openAIAPIKey: String = ""
    @Published var openAIKeyStatus: String?
    @Published var agentAuthMethod: AgentAuthMethod = .apiKey
    @Published var agentCredentialProfiles: [AgentCredentialProfile] = AgentCredentialProfileStore.loadProfiles()
    @Published var activeAgentProfileID: UUID = AgentCredentialProfileStore.activeProfileID()
        ?? AgentCredentialProfileStore.loadProfiles().first?.id
        ?? AgentCredentialProfileStore.defaultProfile().id
    // Model-list discovery (settings UI). Backed by `AgentModelListService`.
    @Published var availableModels: [String] = []
    @Published var modelListStatus: ModelListStatus = .idle
    @Published var bedrockRegion: String = ProcessInfo.processInfo.environment["WEIBEI_BEDROCK_REGION"] ?? "us-east-1"
    // Race guard for `refreshModelList` (see S2). Without this, rapidly switching
    // profiles / providers launches overlapping async fetches; whichever resolves
    // last wins and can paint the wrong provider's catalog. `modelFetchGeneration`
    // tags each in-flight request so a stale resolution is discarded; the held
    // `modelFetchTask` is cancelled when a newer request supersedes it.
    var modelFetchGeneration: UInt64 = 0
    var modelFetchTask: Task<Void, Never>?
    @Published var appearanceMode: WeiBeiAppearanceMode = .paper
    @Published var adaptImportedDocumentColors = true
    @Published var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    @Published var courseWorkspacePresented = false
    @Published var courseWorkspaceDestination: CourseWorkspaceDestination = .hub
    @Published var courseWorkspaceTargetItemID: String?
    @Published var courseFolderImportDraft: CourseFolderImportDraft?
    @Published var backNavigationStack: [NavigationSnapshot] = []
    @Published var forwardNavigationStack: [NavigationSnapshot] = []

    var notesByItemID: [String: String] = [:]
    var pendingNoteWritesByItemID: [String: PendingNoteWriteState] = [:]
    var noteBackingContentDigestsByItemID: [String: String] = [:]
    let storageURL: URL
    let importedFileIdentityResolver: (URL) -> ImportedFileIdentity?
    let notebookMarkdownReader: (URL) throws -> String
    let notebookMarkdownWriter: (String, URL) throws -> Void
    let notebookFileMover: (URL, URL) throws -> Void
    /// Credential reads are injected so filesystem-only self-checks remain isolated from user app data.
    let apiKeyLoader: @MainActor (String) -> String
    let workspaceRepository: WorkspaceRepository
    let notebookRepository: NotebookRepository
    let courseLibraryService = CourseLibraryService()
    let agentRequests = AgentRequestCoordinator()
    let piRuntime: PiAgentRuntime
    let courseDocumentSearchIndex: CourseDocumentSearchIndex
    var quietInsightTask: Task<Void, Never>?
    var quietInsightTaskID: UUID?
    var agentContextRevision: UInt64 = 0
    var lastAgentReplyContextRevision: UInt64?
    var latestAgentLearningUpdateQuestion: String?
    var stagedNoteDraft: (itemID: String, value: String)?
    var quietInsightSignature = ""
    var isRestoringNavigation = false
    var didRunVerificationScenario = false
    var lastSelectionAttachmentDate: Date?
    var lastSelectionUpdateDate: Date?
    var pendingSelectionAttachmentTask: Task<Void, Never>?
    let selectionAttachmentMergeWindow: TimeInterval = 1.8
    let selectionAttachmentDebounceDelay: UInt64 = 520_000_000
    var threePaneReorderFrames: [WorkspacePaneRole: CGRect] = [:]
    var pendingNotePersistenceByItemID: [String: PendingNotePersistence] = [:]
    var pendingNotePersistenceTasks: [String: Task<Void, Never>] = [:]
    let notePersistenceDebounceDelay: UInt64 = 420_000_000
    var studyProgressSaveTask: Task<Void, Never>?
    let studyProgressSaveDelay: UInt64 = 900_000_000
    /// Coalesce the 70+ main-thread full-workspace JSON saves that fire on every UI toggle.
    var pendingWorkspaceSaveTask: Task<Void, Never>?
    var workspaceSaveGeneration: UInt64 = 0
    let workspaceSaveDebounceNanoseconds: UInt64 = 280_000_000
    var noteSourceLinksMigrationVersion = 0
    var noteSourceRelationIndex = NoteSourceRelationIndex(links: [])
    var courseMembershipIndex = CourseItemMemberships()
    var courseWorkspaceReturnFocus: PaneFocus?

    var showRightPane: Bool {
        get { showNotes || showAgent }
        set {
            showNotes = newValue
            showAgent = newValue
        }
    }

    struct NavigationSnapshot: Equatable {
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
        var readerLocationID: String?
        var readerLocationTitle: String?
        var readerPageIndex: Int
        var focusedPane: PaneFocus
        var threePaneOrder: [WorkspacePaneRole]
    }

    enum NotebookNoteSeed {
        case blank
        case currentMaterial(StudyItem)
    }

    struct PendingNotePersistence {
        var item: StudyItem
        var markdown: String
    }

    struct CourseIndexCandidate: Sendable {
        var item: StudyItem
        var title: String
        var subtitle: String
        var embeddedText: String?
        var fallbackText: String
    }

    struct CourseContextBuildResult: Sendable {
        var context: StudyAgentCourseContext
        var selectedMaterialText: String?
        var selectedMaterialIsTruncated: Bool
    }

    struct ResolvedImportedFileBookmark {
        var url: URL
        var isStale: Bool
    }

    struct PendingNotebookRenameJournal: Codable {
        var oldItem: StudyItem
        var replacementItemID: String
        var oldPath: String
        var newPath: String
        var newTitle: String
        var sourceMarkdown: String
        var retitledMarkdown: String
        var originalContentDigest: String
        var retitledContentDigest: String
    }

    var lastUsableAgentAnswer: AgentMessage? {
        guard lastAgentReplyContextRevision == agentContextRevision else { return nil }
        return messages.last { $0.isUsableAgentAnswer }
    }

    static let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let sampleItems: [StudyItem] = WorkspaceStore.makeSampleItems()

    convenience init() {
        let folder = Self.workspaceRootDirectory()
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBei", isDirectory: true)
        self.init(workspaceDirectory: folder)
    }

    init(
        workspaceDirectory folder: URL,
        importedFileIdentityResolver: @escaping (URL) -> ImportedFileIdentity? = WorkspaceStore.resolveImportedFileIdentity,
        notebookMarkdownReader: @escaping (URL) throws -> String = WorkspaceStore.readNotebookMarkdown,
        notebookMarkdownWriter: @escaping (String, URL) throws -> Void = WorkspaceStore.writeNotebookMarkdown,
        notebookFileMover: @escaping (URL, URL) throws -> Void = WorkspaceStore.moveNotebookFile,
        workspaceSnapshotWriter: @escaping (Data, URL) throws -> Void = WorkspaceStore.writeWorkspaceSnapshot,
        apiKeyLoader: @escaping @MainActor (String) -> String = WorkspaceStore.loadWorkspaceAPIKey
    ) {
        storageURL = folder.appendingPathComponent("workspace.json")
        let notebookRenameJournalURL = folder.appendingPathComponent("pending-notebook-rename.json")
        self.importedFileIdentityResolver = importedFileIdentityResolver
        self.notebookMarkdownReader = notebookMarkdownReader
        self.notebookMarkdownWriter = notebookMarkdownWriter
        self.notebookFileMover = notebookFileMover
        self.apiKeyLoader = apiKeyLoader
        workspaceRepository = WorkspaceRepository(
            storageURL: storageURL,
            writer: workspaceSnapshotWriter
        )
        notebookRepository = NotebookRepository(
            renameJournalURL: notebookRenameJournalURL,
            reader: notebookMarkdownReader,
            writer: notebookMarkdownWriter,
            mover: notebookFileMover
        )
        piRuntime = PiAgentRuntime(runtimeDirectory: folder.appendingPathComponent("AgentRuntime", isDirectory: true))
        let courseIndexDirectory = folder.appendingPathComponent("CourseIndex", isDirectory: true)
        Self.removeLegacyCourseIndex(in: courseIndexDirectory)
        courseDocumentSearchIndex = CourseDocumentSearchIndex(
            databaseURL: courseIndexDirectory.appendingPathComponent("course-search-v3.sqlite3")
        )
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        WeiBeiThemeRuntime.mode = appearanceMode
        loadSelectionAskThreadsIfNeeded()
        let recoveredPendingNotebookRename = recoverPendingNotebookRenameIfNeeded()
        let resolvedImportedFileBookmarks = resolvePersistedImportedFileBookmarks()
        let migratedImportedItemIdentities = migrateLegacyImportedItemIdentities()
        if recoveredPendingNotebookRename
            || resolvedImportedFileBookmarks
            || migratedImportedItemIdentities {
            noteText = noteText(for: activeNoteItem)
        }
        let migratedStudyLocationTitles = refreshStudyLocationReferenceTitles()
        let sanitizedNoteSourceLinks = sanitizeNoteSourceLinks()
        let sanitizedCourseLibrary = sanitizeCourseLibrary()
        courseDocumentSearchIndex.synchronize(allItems)
        ensureActiveStudySession()
        let savedInitializationChanges: Bool
        if noteSourceLinksMigrationVersion < 1 {
            migrateNoteSourceLinksFromMarkdown()
            noteSourceLinksMigrationVersion = 1
            savedInitializationChanges = save()
        } else if resolvedImportedFileBookmarks
                    || recoveredPendingNotebookRename
                    || migratedImportedItemIdentities
                    || migratedStudyLocationTitles
                    || sanitizedNoteSourceLinks
                    || sanitizedCourseLibrary {
            savedInitializationChanges = save()
        } else {
            savedInitializationChanges = true
        }
        if recoveredPendingNotebookRename, savedInitializationChanges {
            removePendingNotebookRenameJournal()
        }
        floatingSelectionPrompt = ui("当前选区", "Current selection")
        if selectedItemID == nil {
            select(itemID: sampleItems[0].id)
        } else {
            restoreCurrentStudyLocation()
            recordCurrentStudyLocation(incrementVisit: false)
        }
    }

    /**
     * 读取工作区当前提供商的 API Key。
     *
     * 文件身份自检会创建大量隔离工作区；该专用进程不得访问用户凭据文件。
     *
     * @param provider - Pi 提供商标识
     * @returns 已清理的 API Key；文件身份自检中固定为空
     */
    static func loadWorkspaceAPIKey(provider: String) -> String {
        guard !ProcessInfo.processInfo.arguments.contains("--self-check-imported-identity") else {
            return ""
        }
        return OpenAIAPIKeyStore.load(provider: provider)
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
            if anchorUnchanged, !pinnedFloatingAgent, !keepFloatingSelectionForAnswer, surfaceAlreadyCorrect {
                return
            }
            if !anchorUnchanged {
                selectionAnchor = anchor
            }
            // Never clear pin while the user locked the float (or mid selection-answer).
            cancelPendingSelectionAttachment()
            if pinnedFloatingAgent || keepFloatingSelectionForAnswer {
                if agentSurface != .selectionFloat {
                    agentSurface = .selectionFloat
                }
                showQuietInsight = false
                return
            }
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

        invalidateAgentContext()
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
        cancelPendingSelectionAttachment()
        // Respect pin / answer lock — do not force-unpin on every new selection.
        if pinnedFloatingAgent || keepFloatingSelectionForAnswer {
            agentSurface = .selectionFloat
            showQuietInsight = false
            return
        }
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

    static func anchorsApproximatelyEqual(_ lhs: CGPoint?, _ rhs: CGPoint?, epsilon: CGFloat = 0.5) -> Bool {
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
        if removed != nil { invalidateAgentContext() }
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
        if !selectionAttachments.isEmpty { invalidateAgentContext() }
        selectionAttachments = []
        lastSelectionAttachmentDate = nil
        lastSelectionUpdateDate = nil
        clearUnpinnedFloatingSelection(keepContext: false)
    }

    func scheduleSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool) {
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

    func cancelPendingSelectionAttachment() {
        pendingSelectionAttachmentTask?.cancel()
        pendingSelectionAttachmentTask = nil
    }

    func addSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool = false) {
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
        invalidateAgentContext()
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

    func shouldMergeSelectionAttachment(_ existing: SelectionContext, with incoming: SelectionContext, at now: Date, withinSelectionGestureHint: Bool) -> Bool {
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

    func mergedSelectionAttachment(_ existing: SelectionContext, with incoming: SelectionContext) -> SelectionContext {
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

    static func hasMeaningfulSelectionCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
        }
    }

    func selectionOwnerTitle(for source: SelectionSource) -> String {
        if source == .note || activeNoteItem?.isNotebookNote == true {
            return activeNoteItem.map(displayTitle) ?? ui("当前笔记", "Current note")
        }
        return currentSourceReferenceTitle
    }

    static func boundedSelectionText(_ text: String) -> String {
        let limit = 2_000
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit)
        if let boundary = prefix.lastIndex(where: { String($0).rangeOfCharacter(from: .whitespacesAndNewlines) != nil }),
           boundary > prefix.startIndex {
            return String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix)
    }

    func sourceReferenceItem(from rawReference: String?) -> StudyItem? {
        let reference = SourceReferenceTitle.parse(rawReference ?? "")
        guard !reference.title.isEmpty else { return nil }
        if let ordinal = reference.courseItemOrdinal {
            let catalog = Array(allItems.prefix(500))
            let index = ordinal - 1
            guard catalog.indices.contains(index) else { return nil }
            let item = catalog[index]
            guard displayTitle(for: item) == reference.title
                    || displaySubtitle(for: item) == reference.title
                    || titlesLooselyMatch(displayTitle(for: item), reference.title)
                    || titlesLooselyMatch(displaySubtitle(for: item), reference.title) else { return nil }
            return item
        }
        // Exact unique title first — never guess between duplicate file titles for note jump links.
        let matches = allItems.filter {
            displayTitle(for: $0) == reference.title || displaySubtitle(for: $0) == reference.title
        }
        if !matches.isEmpty {
            return matches.count == 1 ? matches[0] : nil
        }
        // Chat citation tags often use short human labels; only fuzzy after exact miss.
        return resolveStudyItem(matchingCitationTitle: reference.title)
    }

    /// Resolve a study item from a human citation title (exact → loose → unique contains).
    func resolveStudyItem(matchingCitationTitle rawTitle: String) -> StudyItem? {
        let needle = normalizeCitationTitle(rawTitle)
        guard !needle.isEmpty else { return nil }

        let exact = allItems.filter {
            normalizeCitationTitle(displayTitle(for: $0)) == needle
                || normalizeCitationTitle(displaySubtitle(for: $0)) == needle
        }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 {
            // Prefer materials over notes when the label says "material".
            if let material = exact.first(where: { !$0.isNotebookNote }) { return material }
            return exact[0]
        }

        let loose = allItems.filter {
            titlesLooselyMatch(displayTitle(for: $0), rawTitle)
                || titlesLooselyMatch(displaySubtitle(for: $0), rawTitle)
        }
        if loose.count == 1 { return loose[0] }
        if loose.count > 1 {
            if let material = loose.first(where: { !$0.isNotebookNote }) { return material }
            return loose[0]
        }

        // Unique contains: "货币金融学课程 HTML" vs longer catalog titles.
        let contained = allItems.filter {
            let title = normalizeCitationTitle(displayTitle(for: $0))
            let subtitle = normalizeCitationTitle(displaySubtitle(for: $0))
            return title.contains(needle) || needle.contains(title)
                || subtitle.contains(needle) || (!subtitle.isEmpty && needle.contains(subtitle))
        }
        if contained.count == 1 { return contained[0] }
        if contained.count > 1 {
            // Prefer shortest title distance (closest match).
            return contained.min { lhs, rhs in
                abs(normalizeCitationTitle(displayTitle(for: lhs)).count - needle.count)
                    < abs(normalizeCitationTitle(displayTitle(for: rhs)).count - needle.count)
            }
        }
        return nil
    }

    func titlesLooselyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizeCitationTitle(lhs)
        let b = normalizeCitationTitle(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        // Strip common kind suffixes the model often appends.
        let strippedA = a.replacingOccurrences(of: #"\s+(html|pdf|md|markdown|text)$"#, with: "", options: .regularExpression)
        let strippedB = b.replacingOccurrences(of: #"\s+(html|pdf|md|markdown|text)$"#, with: "", options: .regularExpression)
        return strippedA == strippedB || strippedA == b || a == strippedB
    }

    func normalizeCitationTitle(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    func addNoteSourceLink(noteItemID: String, sourceItemID: String) {
        guard noteItemID != sourceItemID,
              !noteSourceLinks.contains(where: {
                  $0.noteItemID == noteItemID && $0.sourceItemID == sourceItemID
              }) else { return }
        noteSourceLinks.append(NoteSourceLink(noteItemID: noteItemID, sourceItemID: sourceItemID))
    }

    func removeLinksWhereSourceItemID(_ sourceItemID: String) {
        let previousCount = noteSourceLinks.count
        noteSourceLinks.removeAll { $0.sourceItemID == sourceItemID }
        if noteSourceLinks.count != previousCount {
            invalidateAgentContext()
        }
    }

    func migrateNoteSourceLinksFromMarkdown() {
        let previousCount = noteSourceLinks.count
        for note in allItems where note.isNotebookNote {
            let markdown = noteMarkdownText(for: note)
            for rawLine in markdown.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.contains("来源：") || line.localizedCaseInsensitiveContains("source:") else { continue }
                guard let source = sourceReferenceItem(from: line), !source.isNotebookNote else { continue }
                addNoteSourceLink(noteItemID: note.id, sourceItemID: source.id)
            }
        }
        if noteSourceLinks.count != previousCount { save() }
    }

    @discardableResult
    func sanitizeNoteSourceLinks() -> Bool {
        let previous = noteSourceLinks
        let validNoteItemIDs = Set(allItems.lazy.filter(\.isNotebookNote).map(\.id))
        let validSourceItemIDs = Set(allItems.lazy.filter { !$0.isNotebookNote }.map(\.id))
        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.sanitize(
            validNoteItemIDs: validNoteItemIDs,
            validSourceItemIDs: validSourceItemIDs
        )
        noteSourceLinks = relations.links
        return noteSourceLinks != previous
    }

    @discardableResult
    func sanitizeCourseLibrary() -> Bool {
        let previousCourses = courses
        let previousMemberships = courseItemMemberships
        let previousActiveCourseID = activeCourseID

        var seenCourseIDs = Set<UUID>()
        courses = courses.filter { course in
            seenCourseIDs.insert(course.id).inserted
                && !course.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var memberships = CourseItemMemberships(values: courseItemMemberships)
        _ = memberships.sanitize(
            validCourseIDs: Set(courses.map(\.id)),
            validItemIDs: Set(importedItems.map(\.id))
        )
        courseItemMemberships = memberships.values

        if let activeCourseID,
           !courses.contains(where: { $0.id == activeCourseID }) {
            self.activeCourseID = courses.first?.id
        }

        return courses != previousCourses
            || courseItemMemberships != previousMemberships
            || activeCourseID != previousActiveCourseID
    }

    func nextCourseColorIndex() -> Int {
        let used = Set(courses.map(\.colorIndex))
        return (0..<8).first(where: { !used.contains($0) }) ?? (courses.count % 8)
    }

    @discardableResult
    func refreshStudyLocationReferenceTitles() -> Bool {
        var changed = false
        for itemID in Array(studyLocationsByItemID.keys) {
            guard let item = allItems.first(where: { $0.id == itemID }),
                  var location = studyLocationsByItemID[itemID] else { continue }
            let title = sourceReferenceBaseTitle(for: item)
            guard location.itemTitle != title else { continue }
            location.itemTitle = title
            studyLocationsByItemID[itemID] = location
            changed = true
        }
        return changed
    }

    func makeCourseContext(query: String) async throws -> CourseContextBuildResult {
        let candidates = allItems.map { item in
            let embeddedText: String?
            if item.isNotebookNote {
                embeddedText = noteMarkdownText(for: item)
            } else if item.id == selectedItemID {
                embeddedText = selectedContextText
            } else {
                embeddedText = nil
            }
            let fallbackText = item.id == "sample-md"
                ? notesByItemID[item.id] ?? defaultNote(for: item)
                : sampleText(for: item)
            return CourseIndexCandidate(
                item: item,
                title: displayTitle(for: item),
                subtitle: displaySubtitle(for: item),
                embeddedText: embeddedText,
                fallbackText: fallbackText
            )
        }
        let title = ui("当前课程", "Current Course")
        let links = noteSourceLinks
        let currentMaterialID = selectedMaterialItem?.id
        let currentMaterialItem = selectedMaterialItem
        let currentNoteID = activeNoteItem?.isNotebookNote == true ? activeNoteItem?.id : nil
        let searchIndex = courseDocumentSearchIndex
        let indexingTask = Task.detached(priority: .userInitiated) {
            let indexedByItemID = searchIndex.lookup(
                items: candidates.map(\.item),
                query: query
            )
            var sources: [CourseKnowledgeSource] = []
            sources.reserveCapacity(candidates.count)
            for candidate in candidates {
                try Task.checkCancellation()
                let indexed = indexedByItemID[candidate.item.id]
                let sampleIndexedText = candidate.item.isSample
                    ? DocumentTextExtractor.indexText(for: candidate.item, query: query)
                    : nil
                let selectedIndexedText = candidate.item.id == currentMaterialID ? indexed?.text : nil
                var text = selectedIndexedText
                    ?? candidate.embeddedText
                    ?? indexed?.text
                    ?? sampleIndexedText
                    ?? candidate.fallbackText
                // Freshly switched / unindexed materials often miss FTS + cache.
                // Extract off the main actor so the agent still sees the current file.
                if candidate.item.id == currentMaterialID,
                   text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let item = currentMaterialItem {
                    text = DocumentTextExtractor.text(for: item) ?? candidate.fallbackText
                }
                let isTruncated = indexed?.isTruncated
                    ?? (candidate.item.url != nil && !candidate.item.isSample)
                sources.append(
                    CourseKnowledgeSource(
                        id: candidate.item.id,
                        title: candidate.title,
                        subtitle: candidate.subtitle,
                        kind: candidate.item.kind.rawValue,
                        role: candidate.item.isNotebookNote ? "note" : "material",
                        text: text,
                        isTruncated: isTruncated
                    )
                )
            }
            let selectedIndex = currentMaterialID.flatMap { indexedByItemID[$0] }
            let selectedSourceText = currentMaterialID.flatMap { id in
                sources.first(where: { $0.id == id })?.text
            }
            let resolvedSelectedText: String? = {
                if let text = selectedIndex?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                if let text = selectedSourceText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                return nil
            }()
            return CourseContextBuildResult(
                context: CourseKnowledgeIndex.build(
                    title: title,
                    sources: sources,
                    links: links,
                    query: query,
                    currentMaterialID: currentMaterialID,
                    currentNoteID: currentNoteID
                ),
                selectedMaterialText: resolvedSelectedText,
                selectedMaterialIsTruncated: selectedIndex?.isTruncated
                    ?? ((selectedSourceText?.count ?? 0) > 24_000)
            )
        }
        return try await withTaskCancellationHandler {
            try await indexingTask.value
        } onCancel: {
            indexingTask.cancel()
        }
    }

    func makeLearningContext() -> StudyAgentLearningContext {
        let session = activeStudySession.map { session in
            StudyAgentSessionSnapshot(
                id: session.id.uuidString.lowercased(),
                title: session.title,
                summary: sessionContinuitySummary(for: session),
                phase: session.flow.phase.rawValue,
                focusItemIDs: session.focusItemIDs,
                turnCount: session.messages.count
            )
        }
        return StudyAgentLearningContext(
            memoryRevision: learningMemoryRevision,
            lastLocation: lastStudyLocation,
            memories: learningMemoryEntries,
            session: session
        )
    }

    func sessionContinuitySummary(for session: StudySession) -> String {
        let recentMessageLimit = 20
        let olderMessages = Array(session.messages.dropLast(min(session.messages.count, recentMessageLimit)))
        let selectedOlderMessages: [AgentMessage]
        if olderMessages.count <= 12 {
            selectedOlderMessages = olderMessages
        } else {
            selectedOlderMessages = Array(olderMessages.prefix(4)) + Array(olderMessages.suffix(8))
        }
        let earlierTranscript = selectedOlderMessages.map { message in
            let role = message.role == .user ? ui("用户", "User") : ui("助手", "Assistant")
            let text = message.text
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(role)：\(String(text.prefix(220)))"
        }.joined(separator: "\n")
        let persistedSummary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [
            persistedSummary,
            earlierTranscript.isEmpty ? "" : "\(ui("更早对话摘录", "Earlier conversation excerpts"))：\n\(earlierTranscript)",
        ].filter { !$0.isEmpty }
        return String(parts.joined(separator: "\n\n").prefix(2_000))
    }

    func applyLearningUpdate(
        _ update: StudyAgentLearningUpdate?,
        expectedContextRevision: String,
        expectedMemoryRevision: UInt64,
        expectedUserQuestion: String
    ) {
        latestAgentLearningUpdate = nil
        guard let update,
              update.contextRevision == expectedContextRevision,
              update.memoryRevision == expectedMemoryRevision,
              learningMemoryRevision == expectedMemoryRevision else { return }

        var changed = false
        let now = Date()
        for proposed in update.entries.prefix(12) {
            let text = proposed.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = proposed.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !evidence.isEmpty else { continue }
            if (evidence.hasPrefix("[用户：本轮]") || evidence.hasPrefix("[会话：当前]")),
               !Self.currentTurnEvidenceMatches(evidence, question: expectedUserQuestion) {
                continue
            }
            if proposed.origin == .userStatement,
               !evidence.hasPrefix("[用户：本轮]") {
                continue
            }
            let normalized = Self.normalizedMemoryText(text)
            if let index = learningMemoryEntries.firstIndex(where: {
                $0.kind == proposed.kind
                    && $0.status == .active
                    && Self.normalizedMemoryText($0.text) == normalized
                    && (
                        $0.origin == .userStatement
                            || proposed.origin == .userStatement
                            || $0.sessionID == activeStudySessionID
                    )
            }) {
                if learningMemoryEntries[index].origin == .userStatement,
                   proposed.origin != .userStatement {
                    continue
                }
                learningMemoryEntries[index].text = String(text.prefix(500))
                learningMemoryEntries[index].evidence = String(evidence.prefix(400))
                if proposed.origin == .userStatement {
                    learningMemoryEntries[index].origin = .userStatement
                    learningMemoryEntries[index].sessionID = activeStudySessionID
                }
                learningMemoryEntries[index].updatedAt = now
                changed = true
            } else {
                learningMemoryEntries.append(
                    LearningMemoryEntry(
                        kind: proposed.kind,
                        text: String(text.prefix(500)),
                        evidence: String(evidence.prefix(400)),
                        origin: proposed.origin == .observed ? .agentInference : proposed.origin,
                        sessionID: activeStudySessionID,
                        createdAt: now,
                        updatedAt: now
                    )
                )
                changed = true
            }
        }

        if let activeStudySessionID,
           let index = studySessions.firstIndex(where: { $0.id == activeStudySessionID }) {
            if let summary = update.sessionSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                studySessions[index].summary = String(summary.prefix(2_000))
                changed = true
            }
            if !studySessions[index].flow.pinnedByUser,
               let phase = update.suggestedPhase {
                studySessions[index].flow.phase = phase
                changed = true
            }
            let next = update.suggestedNext
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
                .map { String($0.prefix(300)) }
            if !next.isEmpty {
                studySessions[index].flow.suggestedNext = next
                changed = true
            }
            studySessions[index].updatedAt = now
        }

        if learningMemoryEntries.count > 200 {
            learningMemoryEntries = Array(
                learningMemoryEntries
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .prefix(200)
            )
        }
        if changed { learningMemoryRevision &+= 1 }
        var acceptedUpdate = update
        acceptedUpdate.resolutions = update.resolutions.prefix(12).filter { resolution in
            guard Self.resolutionEvidenceMatches(
                resolution.evidence.trimmingCharacters(in: .whitespacesAndNewlines),
                question: expectedUserQuestion
            ),
            let memoryID = UUID(uuidString: resolution.memoryID),
            let memory = learningMemoryEntries.first(where: { $0.id == memoryID }) else {
                return false
            }
            return memory.status == .active
                && (memory.kind == .goal || memory.kind == .confusion || memory.kind == .nextStep)
        }
        latestAgentLearningUpdate = acceptedUpdate
        latestAgentLearningUpdateQuestion = expectedUserQuestion
    }

    func isLearningMemoryResolved(_ memoryID: String) -> Bool {
        guard let id = UUID(uuidString: memoryID) else { return false }
        return learningMemoryEntries.first(where: { $0.id == id })?.status == .resolved
    }

    func confirmLearningMemoryResolution(_ resolution: StudyAgentMemoryResolution) {
        guard latestAgentLearningUpdate?.resolutions.contains(resolution) == true,
              let question = latestAgentLearningUpdateQuestion,
              Self.resolutionEvidenceMatches(resolution.evidence, question: question),
              let memoryID = UUID(uuidString: resolution.memoryID),
              let index = learningMemoryEntries.firstIndex(where: {
                  $0.id == memoryID
                      && $0.status == .active
                      && ($0.kind == .goal || $0.kind == .confusion || $0.kind == .nextStep)
              }) else { return }
        let now = Date()
        learningMemoryEntries[index].status = .resolved
        learningMemoryEntries[index].resolvedAt = now
        learningMemoryEntries[index].resolutionEvidence = String(resolution.evidence.prefix(400))
        learningMemoryEntries[index].updatedAt = now
        learningMemoryRevision &+= 1
        save()
    }

    func resolveLearningMemory(_ memoryID: UUID) {
        guard let index = learningMemoryEntries.firstIndex(where: {
            $0.id == memoryID
                && $0.status == .active
                && ($0.kind == .goal || $0.kind == .confusion || $0.kind == .nextStep)
        }) else { return }
        let now = Date()
        learningMemoryEntries[index].status = .resolved
        learningMemoryEntries[index].resolvedAt = now
        learningMemoryEntries[index].resolutionEvidence = "[用户：界面确认]"
        learningMemoryEntries[index].updatedAt = now
        learningMemoryRevision &+= 1
        save()
    }

    func restoreLearningMemory(_ memoryID: UUID) {
        guard let index = learningMemoryEntries.firstIndex(where: {
            $0.id == memoryID && $0.status == .resolved
        }) else { return }
        let now = Date()
        learningMemoryEntries[index].status = .active
        learningMemoryEntries[index].resolvedAt = nil
        learningMemoryEntries[index].resolutionEvidence = nil
        learningMemoryEntries[index].updatedAt = now
        learningMemoryRevision &+= 1
        save()
    }

    func restoreLearningMemoryResolution(_ resolution: StudyAgentMemoryResolution) {
        guard latestAgentLearningUpdate?.resolutions.contains(resolution) == true,
              let memoryID = UUID(uuidString: resolution.memoryID) else { return }
        restoreLearningMemory(memoryID)
    }

    static func normalizedMemoryText(_ text: String) -> String {
        text
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined()
    }

    static func currentTurnEvidenceMatches(_ evidence: String, question: String) -> Bool {
        StudyAgentCurrentTurnEvidence.matches(evidence, question: question)
    }

    static func resolutionEvidenceMatches(_ evidence: String, question: String) -> Bool {
        StudyAgentResolutionEvidence.matches(evidence, question: question)
    }

    func askToOrganizeNote() {
        agentDraft = ui(
            "请根据\(agentPromptScope)，把笔记整理成更清晰的大纲，保留来源信息，并标出缺少证据的位置。",
            "Use \(agentPromptScope) to organize the note into a clearer outline, keep source references, and mark places where evidence is missing."
        )
        askAgent()
    }

    func askSelection() {
        if let selectionContext {
            // Expand the floating selection agent into a normal chat composer.
            // Do NOT invent a prompt or auto-send — user writes and sends themselves.
            withAnimation(WeiBeiMotion.panel) {
                cancelPendingSelectionAttachment()
                addSelectionAttachment(selectionContext)
                floatingSelectionPrompt = selectionContext.label(language: interfaceLanguage)
                showQuietInsight = false
                // Record underline mark when the user opens “问” on this selection.
                let thread = beginOrReuseSelectionAskThread(for: selectionContext)
                activeSelectionAskThreadID = thread.id
                if isConversationSurfaceVisible {
                    // Conversation pane already owns Q&A — keep selection as chat context only.
                    agentSurface = .hidden
                    pinnedFloatingAgent = false
                    keepFloatingSelectionForAnswer = false
                    selectionAnchor = nil
                    focusedPane = .agent
                    focusRequest += 1
                } else {
                    agentSurface = .selectionFloat
                    keepFloatingSelectionForAnswer = true
                    focus(.agent)
                }
            }
        } else {
            withAnimation(WeiBeiMotion.panel) {
                agentDraft = ui(
                    "请根据\(agentPromptScope)，帮我梳理重点和可追问的问题。",
                    "Use \(agentPromptScope) to summarize key points and follow-up questions."
                )
                if layout == .immersiveReading {
                    layout = .immersiveConversation
                    showAgent = true
                    agentSurface = .hidden
                } else if layout == .documentNotesSplit {
                    showAgent = true
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
                _ = beginOrReuseSelectionAskThread(for: context)
            }
            // Prefer keeping float if user is mid answer; otherwise collapse into chat.
            if !keepFloatingSelectionForAnswer, agentSurface == .selectionFloat {
                agentSurface = .hidden
                pinnedFloatingAgent = false
            }
            if !keepFloatingSelectionForAnswer {
                selectionAnchor = nil
            }
            showQuietInsight = false
            focusedPane = .agent
            focusRequest += 1
        }
    }

    /// Reopen the floating agent for a past selection-ask thread (hover / mark click / top menu).
    /// When `anchor` is provided (e.g. underline click), the expanded panel docks beside that point.
    func openSelectionAskThread(_ threadID: UUID, jumpToConversation: Bool = false, anchor: CGPoint? = nil) {
        guard let thread = selectionAskThreads.first(where: { $0.id == threadID }) else { return }
        withAnimation(WeiBeiMotion.panel) {
            activeSelectionAskThreadID = thread.id
            floatingSelectionPrompt = thread.ownerTitle
            keepFloatingSelectionForAnswer = true
            // Do not force-pin on reopen — pin is an explicit user choice.
            agentSurface = .selectionFloat
            if let anchor {
                selectionAnchor = anchor
            }
            selectionContext = SelectionContext(
                id: thread.id,
                text: thread.selectionText,
                source: thread.source,
                ownerTitle: thread.ownerTitle,
                isEditable: thread.source == .note
            )
            if jumpToConversation, isConversationSurfaceVisible,
               let lastID = thread.messageIDs.last {
                focusedPane = .agent
                focusRequest += 1
                NotificationCenter.default.post(
                    name: .weiBeiScrollAgentToMessage,
                    object: nil,
                    userInfo: ["messageID": lastID.uuidString]
                )
            }
        }
    }

    @discardableResult
    func beginOrReuseSelectionAskThread(for selection: SelectionContext) -> SelectionAskThread {
        let normalized = SelectionAttachmentMerge.normalized(selection.text)
        let itemID = selection.source == .note ? activeNotebookItemID : selectedItemID
        if let index = selectionAskThreads.firstIndex(where: {
            $0.normalizedText == normalized
                && $0.source == selection.source
                && ($0.itemID == nil || $0.itemID == itemID || itemID == nil)
        }) {
            selectionAskThreads[index].updatedAt = Date()
            selectionAskThreads[index].itemID = selectionAskThreads[index].itemID ?? itemID
            persistSelectionAskThreads()
            return selectionAskThreads[index]
        }
        let thread = SelectionAskThread(
            selectionText: selection.text,
            source: selection.source,
            ownerTitle: selection.ownerTitle,
            itemID: itemID
        )
        selectionAskThreads.insert(thread, at: 0)
        if selectionAskThreads.count > 80 {
            selectionAskThreads = Array(selectionAskThreads.prefix(80))
        }
        persistSelectionAskThreads()
        return thread
    }

    func appendMessageToActiveSelectionAskThread(_ messageID: UUID) {
        guard let threadID = activeSelectionAskThreadID,
              let index = selectionAskThreads.firstIndex(where: { $0.id == threadID }) else { return }
        if !selectionAskThreads[index].messageIDs.contains(messageID) {
            selectionAskThreads[index].messageIDs.append(messageID)
            selectionAskThreads[index].updatedAt = Date()
            persistSelectionAskThreads()
        }
    }

    func selectionAskThreads(forItemID itemID: String?) -> [SelectionAskThread] {
        guard let itemID else { return selectionAskThreads }
        return selectionAskThreads.filter { $0.itemID == nil || $0.itemID == itemID }
    }

    func selectionAskThread(matchingText text: String) -> SelectionAskThread? {
        let normalized = SelectionAttachmentMerge.normalized(text)
        guard !normalized.isEmpty else { return nil }
        return selectionAskThreads.first { $0.normalizedText == normalized }
    }

    func persistSelectionAskThreads() {
        let key = "weibei.selectionAskThreads.v1"
        if let data = try? JSONEncoder().encode(selectionAskThreads) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func loadSelectionAskThreadsIfNeeded() {
        let key = "weibei.selectionAskThreads.v1"
        guard selectionAskThreads.isEmpty,
              let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SelectionAskThread].self, from: data) else { return }
        selectionAskThreads = decoded
    }

    func appendSelectionToNote() {
        guard let selectionContext else { return }
        let block = """

        \(quotedReferenceBlock(text: selectionContext.text, sourceTitle: selectionContext.ownerTitle))
        """
        updateNote(noteText + block)
        focus(.notes)
    }

    func quotedReferenceBlock(text: String, sourceTitle: String) -> String {
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
        // Quiet insight surface removed for 1.0; keep no-op for any residual callers.
        showQuietInsight = false
    }

    func askQuietInsight() {
        // Quiet insight surface removed for 1.0 — open primary conversation instead.
        showQuietInsight = false
        layout = .immersiveConversation
        showAgent = true
        agentSurface = .hidden
        focus(.agent)
    }

    func refreshQuietInsight() async {
        // Quiet insight generation disabled for 1.0 (no silent API spend).
        showQuietInsight = false
        isGeneratingQuietInsight = false
    }


    func applyLastAgentAnswerToNote() {
        guard let answer = lastUsableAgentAnswer else { return }
        let content = latestAgentNoteProposal?.markdown ?? answer.text
        let block = "\n\n\(noteBlockForAgentAnswer(content))"
        updateNote(noteText + block)
        focus(.notes)
    }

    /// Delegates deterministic verification setup to the isolated verification implementation.
    func runVerificationScenarioIfNeeded() async {
        await runWorkspaceVerificationScenarioIfNeeded()
    }

    func replaceSelectionWithLastAgentAnswer() {
        guard selectionContext?.isReplaceableNoteSelection == true,
              let answer = lastUsableAgentAnswer else { return }
        noteEditorCommand = NoteEditorCommand(
            kind: .replaceSelection,
            markdown: latestAgentNoteProposal?.markdown ?? answer.text
        )
        focus(.notes)
    }

    func applyAgentPatchToEditor() {
        guard let answer = lastUsableAgentAnswer else { return }
        let content = latestAgentNoteProposal?.markdown ?? answer.text
        noteEditorCommand = NoteEditorCommand(kind: .applyAgentPatch, markdown: "\n\(noteBlockForAgentAnswer(content))")
        focus(.notes)
    }

    func noteBlockForAgentAnswer(_ answer: String) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suggestedNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: text, language: interfaceLanguage) {
            return suggestedNoteBlock
        }
        guard !text.hasPrefix("#") else { return text }
        return "## \(ui("整理建议", "Organization suggestion"))\n\(text)"
    }

    func askAgent() {
        flushStagedNoteDraftForAgentContext()
        guard !agentRequests.hasTask,
              !isAskingAgent,
              !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        agentRequests.launch { @MainActor [weak self] in
            await self?.performAgentRequest()
        }
    }

    func askAgentAndWait() async {
        askAgent()
        await agentRequests.waitForCurrentTask()
    }

    func currentVisualAssetsForAgent() -> [StudyAgentVisualAsset] {
        guard let item = selectedMaterialItem,
              !item.isNotebookNote,
              let path = item.urlPath ?? item.importedFileLastKnownPath else {
            return []
        }
        let mediaType: String
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg":
            mediaType = "image/jpeg"
        case "png":
            mediaType = "image/png"
        case "webp":
            mediaType = "image/webp"
        default:
            return []
        }
        guard FileManager.default.isReadableFile(atPath: path) else { return [] }
        return [StudyAgentVisualAsset(id: item.id, filePath: path, mediaType: mediaType)]
    }

    func performAgentRequest() async {
        flushStagedNoteDraftForAgentContext()
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAskingAgent else {
            return
        }

        persistCurrentNote()
        // Ensure live document selection is attached before we snapshot context for the request.
        if selectionAttachments.isEmpty,
           let selectionContext,
           !selectionContext.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addSelectionAttachment(selectionContext)
        }
        let sentSelectionTitle = agentSelectionTitle
        let sentSelectionText = agentSelectionText
        let shouldClearSentDocumentSelection = sentSelectionText != nil && selectionContext?.source == .document
        let recentMessages = Array(messages.suffix(20))
        let sourceTitle = agentMessageSourceTitle
        let requestID = agentRequests.beginRequest()
        let requestWorkspaceRevision = agentContextRevision
        let requestMemoryRevision = learningMemoryRevision
        let sentMaterialTitle = currentSourceReferenceTitle
        let sentMaterialText = selectedContextText
        let sentNoteTitle = agentNoteTitle
        let sentNoteText = noteText
        let sentLearningContext = makeLearningContext()
        let sentVisualAssets = currentVisualAssetsForAgent()
        let sentLanguage = interfaceLanguage
        let courseQuery = [question, sentSelectionText ?? "", String(sentNoteText.prefix(2_000))]
            .joined(separator: "\n\n")
        agentDraft = ""
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        if !selectionAttachments.isEmpty {
            withAnimation(WeiBeiMotion.panel) {
                cancelPendingSelectionAttachment()
                selectionAttachments = []
                lastSelectionAttachmentDate = nil
                lastSelectionUpdateDate = nil
            }
        }
        // Keep the floating selection agent open while answering — do not dismiss it mid-stream.
        // (Previously clearUnpinnedFloatingSelection killed the float as soon as ask started.)
        // Conversation pane already open → answer there; never re-raise the float.
        if isConversationSurfaceVisible {
            agentSurface = .hidden
            keepFloatingSelectionForAnswer = false
            if shouldClearSentDocumentSelection, !pinnedFloatingAgent {
                clearUnpinnedFloatingSelection(keepContext: false, invalidatesAgentContext: false)
            }
        } else if shouldClearSentDocumentSelection, !keepFloatingSelectionForAnswer, !pinnedFloatingAgent {
            clearUnpinnedFloatingSelection(keepContext: false, invalidatesAgentContext: false)
        } else if keepFloatingSelectionForAnswer || pinnedFloatingAgent {
            agentSurface = .selectionFloat
            pinnedFloatingAgent = true
        }
        isAskingAgent = true
        agentStreamingText = ""
        agentActivityText = ui("正在整理课程目录", "Indexing course")
        defer {
            if agentRequests.isCurrent(requestID) {
                agentRequests.finish(requestID)
                isAskingAgent = false
                agentStreamingText = ""
                agentActivityText = nil
                // Answer finished: keep float pinned so the user can scroll the reply.
                if keepFloatingSelectionForAnswer, !isConversationSurfaceVisible {
                    pinnedFloatingAgent = true
                    agentSurface = .selectionFloat
                }
            }
        }

        var didAppendUserMessage = false
        do {
            let courseBuild = try await makeCourseContext(query: courseQuery)
            guard agentRequests.isCurrent(requestID),
                  requestWorkspaceRevision == agentContextRevision,
                  requestMemoryRevision == learningMemoryRevision else {
                if agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    agentDraft = question
                }
                return
            }
            let request = StudyAgentRequest(
                id: requestID,
                purpose: .conversation,
                question: question,
                materialTitle: sentMaterialTitle,
                materialText: courseBuild.selectedMaterialText ?? sentMaterialText,
                materialIsTruncated: courseBuild.selectedMaterialIsTruncated,
                noteTitle: sentNoteTitle,
                noteText: sentNoteText,
                selectionTitle: sentSelectionTitle,
                selectionText: sentSelectionText,
                recentMessages: recentMessages,
                courseContext: courseBuild.context,
                visualAssets: sentVisualAssets,
                learningContext: sentLearningContext,
                language: sentLanguage,
                contextRevision: "\(requestWorkspaceRevision):\(requestID.uuidString.lowercased())"
            )
            let userMessage = AgentMessage(role: .user, text: question, source: sourceTitle)
            appendAgentMessage(userMessage)
            appendMessageToActiveSelectionAskThread(userMessage.id)
            didAppendUserMessage = true
            agentActivityText = ui("正在读取上下文", "Reading context")
            if isGeneratingQuietInsight {
                await piRuntime.cancel()
            }
            let reply = try await executeStudyAgentRequest(request)
            guard agentRequests.isCurrent(request.id),
                  requestWorkspaceRevision == agentContextRevision,
                  requestMemoryRevision == learningMemoryRevision else { return }
            latestAgentNoteProposal = reply.noteProposal
            applyLearningUpdate(
                reply.learningUpdate,
                expectedContextRevision: request.contextRevision,
                expectedMemoryRevision: requestMemoryRevision,
                expectedUserQuestion: request.question
            )
            lastAgentReplyContextRevision = requestWorkspaceRevision
            let assistantMessage = AgentMessage(
                role: .assistant,
                text: reply.noteProposal?.markdown ?? reply.richAnswer?.narrative ?? reply.text,
                source: sourceTitle,
                backend: reply.backend,
                richAnswer: reply.noteProposal == nil ? reply.richAnswer : nil,
                toolTrace: reply.toolTrace
            )
            appendAgentMessage(assistantMessage)
            appendMessageToActiveSelectionAskThread(assistantMessage.id)
        } catch PiAgentRuntimeError.cancelled, is CancellationError {
            if agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentDraft = question
            }
            lastAgentFailureKind = .cancelled
            return
        } catch {
            guard agentRequests.isCurrent(requestID) else { return }
            if !didAppendUserMessage {
                appendAgentMessage(AgentMessage(role: .user, text: question, source: sourceTitle))
            }
            // Always restore the failed question so composer matches the failure copy.
            agentDraft = question
            focusedPane = .agent
            let kind = AgentFailureKind.classify(error)
            lastAgentFailureKind = kind
            lastFailedAgentQuestion = question
            let detail = error.localizedDescription
            appendAgentMessage(
                AgentMessage(
                    role: .assistant,
                    text: kind.userMessage(
                        language: interfaceLanguage,
                        detail: detail,
                        draftPreserved: true
                    ),
                    source: sourceTitle
                )
            )
        }

    }

    func cancelAgentRequest() {
        guard isAskingAgent || agentRequests.requestID != nil || agentRequests.hasTask else { return }
        agentRequests.cancel()
        isAskingAgent = false
        agentStreamingText = ""
        agentActivityText = nil
        lastAgentFailureKind = .cancelled
        Task { await piRuntime.cancel() }
    }

    /// Re-send the last failed user question (precise retry).
    func retryLastFailedAgentRequest() {
        guard !isAskingAgent else { return }
        let question = (lastFailedAgentQuestion ?? agentDraft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        agentDraft = question
        lastFailedAgentQuestion = nil
        lastAgentFailureKind = nil
        askAgent()
    }

    var canRetryLastFailedAgentRequest: Bool {
        guard !isAskingAgent else { return false }
        if let kind = lastAgentFailureKind, !kind.isRetryable { return false }
        let question = (lastFailedAgentQuestion ?? agentDraft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !question.isEmpty
    }

    static func isAgentFailureMessage(_ text: String) -> Bool {
        text.hasPrefix("请求失败")
            || text.hasPrefix("Agent 请求失败：")
            || text.hasPrefix("Request failed")
    }

    func executeStudyAgentRequest(_ request: StudyAgentRequest) async throws -> StudyAgentReply {
        let isExplicitOfflineVerification = Self.environmentValue("WEIBEI_FORCE_OFFLINE_AGENT") == "1"
            && Self.environmentValue("WEIBEI_SUPPRESS_ACTIVATION") == "1"
            && Self.environmentValue("WEIBEI_VERIFY_SCENARIO") == "offline-learning-flow"
        if isExplicitOfflineVerification {
            return try await OfflineStudyAgentRuntime().respond(to: request)
        }

        let credential = resolvedAPIKey()
        var piFailure: Error?
        if Self.environmentValue("WEIBEI_PI_DISABLED") != "1" {
            let explicitProvider = Self.environmentValue("WEIBEI_PI_PROVIDER")
            let explicitModel = Self.environmentValue("WEIBEI_PI_MODEL")
            let thinking = Self.environmentValue("WEIBEI_PI_THINKING")
            let selectedProvider = agentProviderID
            WeiBeiAgentDataPaths.migrateHomePiAuthIfNeeded()
            let linkedOAuth = PiOAuthService.readLinkedOAuthProviders(from: WeiBeiAgentDataPaths.piAuthJSON)
            // Prefer explicit Pi provider id; map legacy OpenAI API selection to openai-codex when OAuth-linked.
            let providerName: String = {
                if !explicitProvider.isEmpty { return explicitProvider }
                if selectedProvider == .openaiCodex { return "openai-codex" }
                if selectedProvider == .openai, linkedOAuth.contains("openai-codex"), agentAuthMethod == .subscription {
                    return "openai-codex"
                }
                return selectedProvider.piProviderName
            }()
            // OAuth tokens live in auth.json — do not force API key env when subscription is active.
            let usesOAuth = linkedOAuth.contains(providerName)
                || (providerName == "openai-codex" && linkedOAuth.contains("openai-codex"))
            let configuration = PiAgentProviderConfiguration(
                provider: providerName,
                model: explicitModel.isEmpty ? resolvedModelName : explicitModel,
                apiKey: usesOAuth ? nil : credential?.key,
                baseURL: agentBaseURL.isEmpty ? nil : agentBaseURL,
                thinkingLevel: thinking.isEmpty ? "medium" : thinking
            )
            await piRuntime.configure(configuration)
            await piRuntime.writeCustomModelsJSONIfNeeded(
                providerID: selectedProvider,
                baseURL: agentBaseURL,
                model: resolvedModelName
            )

            do {
                return try await piRuntime.respond(to: request) { [weak self] progress in
                    await self?.applyAgentProgress(progress, requestID: request.id)
                }
            } catch let error as PiAgentRuntimeError {
                if error == .cancelled || Task.isCancelled {
                    throw PiAgentRuntimeError.cancelled
                }
                guard error.permitsAutomaticFallback else { throw error }
                piFailure = error
                openAIKeyStatus = ui(
                    "PI 暂不可用：\(error.localizedDescription)",
                    "PI is unavailable: \(error.localizedDescription)"
                )
            } catch {
                if Task.isCancelled { throw PiAgentRuntimeError.cancelled }
                piFailure = error
                openAIKeyStatus = ui(
                    "PI 暂不可用：\(error.localizedDescription)",
                    "PI is unavailable: \(error.localizedDescription)"
                )
            }
        }

        if request.purpose == .conversation {
            throw piFailure ?? PiAgentRuntimeError.unavailable
        }

        // OpenAI HTTP fallback only for the openai provider; other providers go Offline with a clear note.
        if agentProviderID.supportsOpenAIHTTPFallback, let credential {
            do {
                let client = OpenAIResponsesClient(apiKey: credential.key, model: resolvedModelName)
                return try await client.respond(to: request) { [weak self] progress in
                    await self?.applyAgentProgress(progress, requestID: request.id)
                }
            } catch is CancellationError {
                throw PiAgentRuntimeError.cancelled
            } catch {
                if Task.isCancelled { throw PiAgentRuntimeError.cancelled }
                openAIKeyStatus = ui(
                    "在线请求失败，已改用离线草稿：\(error.localizedDescription)",
                    "Online request failed; using an offline draft: \(error.localizedDescription)"
                )
            }
        } else if !agentProviderID.supportsOpenAIHTTPFallback {
            openAIKeyStatus = ui(
                "当前提供商不支持 OpenAI HTTP 回退，已改用离线草稿。",
                "This provider has no OpenAI HTTP fallback; using an offline draft."
            )
        } else {
            openAIKeyStatus = ui(
                "PI 与在线密钥均不可用，当前使用离线草稿。",
                "PI and an online key are unavailable; using an offline draft."
            )
        }

        return try await OfflineStudyAgentRuntime().respond(to: request) { [weak self] progress in
            await self?.applyAgentProgress(progress, requestID: request.id)
        }
    }

    func shutdownAgentRuntime() {
        agentRequests.cancel()
        quietInsightTask?.cancel()
        let runtime = piRuntime
        let completion = DispatchSemaphore(value: 0)
        Task.detached {
            await runtime.shutdown()
            completion.signal()
        }
        _ = completion.wait(timeout: .now() + 1)
    }

    func applyAgentProgress(_ progress: StudyAgentProgress, requestID: UUID) {
        guard agentRequests.isCurrent(requestID) else { return }
        switch progress {
        case .readingContext:
            agentActivityText = ui("正在读取上下文", "Reading context")
        case let .usingTool(name):
            switch name {
            case "weibei_context":
                agentActivityText = ui("正在核对材料与笔记", "Checking material and notes")
            case "weibei_course_map", "weibei_course_search":
                agentActivityText = ui("正在查找课程关联", "Finding course connections")
            case "weibei_learning_memory":
                agentActivityText = ui("正在回顾学习记忆", "Reviewing learning memory")
            case "weibei_learning_update":
                agentActivityText = ui("正在整理学习进展", "Updating study progress")
            case "weibei_note_proposal":
                agentActivityText = ui("正在整理写入建议", "Preparing a note proposal")
            case "weibei_rich_answer":
                agentActivityText = ui("正在组织富回答", "Building a rich answer")
            default:
                agentActivityText = ui("正在处理", "Working")
            }
        case let .text(text):
            agentStreamingText = text
            agentActivityText = ui("正在组织回答", "Composing answer")
        }
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

    static func makeSampleItems() -> [StudyItem] {
        [
            StudyItem(id: "sample-html", title: "货币金融学课程 HTML", subtitle: "HTML 教程", kind: .html, urlPath: nil, isSample: true),
            StudyItem(id: "sample-pdf", title: "Mishkin 教材样例", subtitle: "PDF 阅读", kind: .pdf, urlPath: samplePDFURL()?.path, isSample: true),
            StudyItem(id: "sample-md", title: "课堂笔记样例", subtitle: "Markdown", kind: .markdown, urlPath: nil, isSample: true)
        ]
    }

    static func samplePDFURL() -> URL? {
        guard let root = workspaceRootDirectory() else { return nil }
        let directory = root.appendingPathComponent("Samples", isDirectory: true)
        let url = directory.appendingPathComponent("mishkin-sample.pdf")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return writeSamplePDF(to: url) ? url : nil
    }

    static func writeSamplePDF(to url: URL) -> Bool {
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

    func sampleMarkdownHTML(for item: StudyItem?) -> String {
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

    func appOwnedFilesDirectory() -> URL {
        let root = Self.workspaceRootDirectory() ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBei", isDirectory: true)
        let directory = root.appendingPathComponent("Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func safeFileStem(_ value: String) -> String {
        MarkdownAttachmentStore.safeFileStem(value, fallback: ui("未命名", "Untitled"), limit: 80)
    }

    func nextNotebookNoteURL(in directory: URL, title: String) -> URL {
        let stem = safeFileStem(title)
        var index = 1
        var url = directory.appendingPathComponent("\(stem).md")
        while FileManager.default.fileExists(atPath: url.path) {
            index += 1
            url = directory.appendingPathComponent("\(stem) \(index).md")
        }
        return url
    }

    func renamedNotebookURL(in directory: URL, title: String, currentURL: URL) -> URL {
        let stem = safeFileStem(title)
        var index = 1
        var url = directory.appendingPathComponent("\(stem).md")
        while FileManager.default.fileExists(atPath: url.path) && url.path != currentURL.path {
            index += 1
            url = directory.appendingPathComponent("\(stem) \(index).md")
        }
        return url
    }

    func retitledMarkdown(_ markdown: String, from oldTitle: String, to newTitle: String) -> String {
        let prefix = "# \(oldTitle)\n"
        guard markdown.hasPrefix(prefix) else { return markdown }
        return "# \(newTitle)\n" + String(markdown.dropFirst(prefix.count))
    }

    func writePendingNotebookRenameJournal(_ journal: PendingNotebookRenameJournal) throws {
        try notebookRepository.writeRenameJournalImmediately(journal)
    }

    func removePendingNotebookRenameJournal() {
        notebookRepository.removeRenameJournalImmediately()
    }

    @discardableResult
    func recoverPendingNotebookRenameIfNeeded() -> Bool {
        guard let journal = notebookRepository.loadRenameJournalImmediately(
            as: PendingNotebookRenameJournal.self
        ) else { return false }
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == journal.oldItem.id || $0.id == journal.replacementItemID
        }) else {
            removePendingNotebookRenameJournal()
            return false
        }

        let oldURL = URL(fileURLWithPath: journal.oldPath).standardizedFileURL
        let newURL = URL(fileURLWithPath: journal.newPath).standardizedFileURL
        let newDigest = Self.noteContentDigest(at: newURL)
        let newIdentity = importedFileIdentityResolver(newURL)
        let newFileMatchesMovedOriginal = newDigest == journal.originalContentDigest
            && (journal.oldItem.importedFileIdentity == nil
                || newIdentity == journal.oldItem.importedFileIdentity)
        let newFileMatchesApplicationOutput = newDigest == journal.retitledContentDigest
            && (journal.retitledContentDigest != journal.originalContentDigest
                || journal.oldItem.importedFileIdentity == nil
                || newIdentity == journal.oldItem.importedFileIdentity)

        if newFileMatchesMovedOriginal || newFileMatchesApplicationOutput {
            let previousID = importedItems[itemIndex].id
            var recoveredItem = importedItems[itemIndex]
            recoveredItem.id = journal.replacementItemID
            recoveredItem.title = journal.newTitle
            recoveredItem.subtitle = newURL.lastPathComponent
            recoveredItem.urlPath = newURL.path
            recoveredItem.importedFileIdentity = newIdentity ?? journal.oldItem.importedFileIdentity
            recoveredItem.importedFileBookmarkData = Self.makeImportedFileBookmark(for: newURL)
                ?? recoveredItem.importedFileBookmarkData
                ?? journal.oldItem.importedFileBookmarkData
            recoveredItem.importedFileLastKnownPath = newURL.path
            recoveredItem.kind = StudyItemKind.detect(from: newURL)
            importedItems[itemIndex] = recoveredItem
            replaceItemIDEverywhere(previousID, with: journal.replacementItemID)
            noteBackingContentDigestsByItemID[journal.replacementItemID] = newDigest
            if activeNotebookItemID == journal.replacementItemID {
                noteText = newFileMatchesApplicationOutput
                    ? journal.retitledMarkdown
                    : journal.sourceMarkdown
            }
            noteFileError = ui(
                "已从上次未完成的保存中恢复笔记重命名。",
                "Recovered a notebook rename from the previous incomplete save."
            )
            return true
        }

        let oldDigest = Self.noteContentDigest(at: oldURL)
        let oldIdentity = importedFileIdentityResolver(oldURL)
        let oldFileIsTrusted = oldDigest == journal.originalContentDigest
            && (journal.oldItem.importedFileIdentity == nil
                || oldIdentity == journal.oldItem.importedFileIdentity)
        let previousID = importedItems[itemIndex].id
        if previousID != journal.oldItem.id {
            replaceItemIDEverywhere(previousID, with: journal.oldItem.id)
        }
        importedItems[itemIndex] = journal.oldItem
        if oldFileIsTrusted {
            importedItems[itemIndex].urlPath = oldURL.path
            importedItems[itemIndex].importedFileIdentity = oldIdentity ?? journal.oldItem.importedFileIdentity
            importedItems[itemIndex].importedFileBookmarkData = Self.makeImportedFileBookmark(for: oldURL)
                ?? journal.oldItem.importedFileBookmarkData
            importedItems[itemIndex].importedFileLastKnownPath = oldURL.path
            noteBackingContentDigestsByItemID[journal.oldItem.id] = oldDigest
        } else {
            importedItems[itemIndex].urlPath = nil
            importedItems[itemIndex].importedFileLastKnownPath = journal.oldPath
            notesByItemID[journal.oldItem.id] = journal.sourceMarkdown
            pendingNoteWritesByItemID[journal.oldItem.id] = PendingNoteWriteState(
                baselineContentDigest: journal.originalContentDigest
            )
            if activeNotebookItemID == journal.oldItem.id {
                noteText = journal.sourceMarkdown
            }
        }
        noteFileError = oldFileIsTrusted
            ? ui(
                "上次笔记重命名未完成，已恢复原文件。",
                "The previous notebook rename did not finish, so the original file was restored."
            )
            : ui(
                "上次笔记重命名遇到文件冲突；原关系和最新正文均已保留。",
                "The previous notebook rename encountered a file conflict. The original relationships and latest text were retained."
            )
        return true
    }

    @discardableResult
    func resolvePersistedImportedFileBookmarks() -> Bool {
        var changed = false
        for index in importedItems.indices {
            let resolution = resolveTrackedImportedFile(at: index)
            if resolution.changed { changed = true }
        }
        return changed
    }

    func resolveTrackedImportedFile(at index: Int) -> (url: URL?, changed: Bool) {
        guard importedItems.indices.contains(index) else { return (nil, false) }
        guard let storedIdentity = importedItems[index].importedFileIdentity else {
            guard let currentURL = importedItems[index].url,
                  importedFileIdentityResolver(currentURL) != nil else {
                return (nil, false)
            }
            return (currentURL.standardizedFileURL, false)
        }

        var changed = false
        let currentURL = importedItems[index].urlPath
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        let currentPathIsValid = currentURL.map {
            importedFileIdentityResolver($0) == storedIdentity
        } ?? false
        let bookmarkResolution = currentPathIsValid
            ? nil
            : importedItems[index].importedFileBookmarkData.flatMap(Self.resolveImportedFileBookmark)
        let fallbackPath = importedItems[index].urlPath
            ?? importedItems[index].importedFileLastKnownPath
        let candidateURL = (currentPathIsValid ? currentURL : nil)
            ?? bookmarkResolution?.url
            ?? fallbackPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard let candidateURL,
              importedFileIdentityResolver(candidateURL) == storedIdentity else {
            if let path = importedItems[index].urlPath {
                importedItems[index].importedFileLastKnownPath = path
                importedItems[index].urlPath = nil
                changed = true
            }
            return (nil, changed)
        }

        let nextPath = candidateURL.path
        let nextTitle = candidateURL.deletingPathExtension().lastPathComponent
        let nextSubtitle = candidateURL.lastPathComponent
        let nextKind = StudyItemKind.detect(from: candidateURL)
        if importedItems[index].urlPath != nextPath
            || importedItems[index].importedFileLastKnownPath != nextPath
            || importedItems[index].title != nextTitle
            || importedItems[index].subtitle != nextSubtitle
            || importedItems[index].kind != nextKind {
            importedItems[index].urlPath = nextPath
            importedItems[index].importedFileLastKnownPath = nextPath
            importedItems[index].title = nextTitle
            importedItems[index].subtitle = nextSubtitle
            importedItems[index].kind = nextKind
            changed = true
        }
        let resolvedThroughFallback = !currentPathIsValid && bookmarkResolution == nil
        if importedItems[index].importedFileBookmarkData == nil
            || bookmarkResolution?.isStale == true
            || resolvedThroughFallback,
           let refreshedBookmark = Self.makeImportedFileBookmark(for: candidateURL),
           importedItems[index].importedFileBookmarkData != refreshedBookmark {
            importedItems[index].importedFileBookmarkData = refreshedBookmark
            changed = true
        }
        return (candidateURL, changed)
    }

    @discardableResult
    func refreshImportedFileTracking(itemID: String, url: URL) -> StudyItem? {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }),
              let identity = importedFileIdentityResolver(url) else {
            return nil
        }
        let standardizedURL = url.standardizedFileURL
        importedItems[index].urlPath = standardizedURL.path
        importedItems[index].importedFileIdentity = identity
        importedItems[index].importedFileBookmarkData = Self.makeImportedFileBookmark(for: standardizedURL)
            ?? importedItems[index].importedFileBookmarkData
        importedItems[index].importedFileLastKnownPath = standardizedURL.path
        importedItems[index].title = standardizedURL.deletingPathExtension().lastPathComponent
        importedItems[index].subtitle = standardizedURL.lastPathComponent
        importedItems[index].kind = StudyItemKind.detect(from: standardizedURL)
        return importedItems[index]
    }

    @discardableResult
    func migrateLegacyImportedItemIdentities() -> Bool {
        var changed = false
        var canonicalIDByIdentity: [ImportedFileIdentity: String] = [:]
        for item in importedItems
        where item.importedFileIdentity != nil && !item.id.hasPrefix("file:") {
            if let identity = item.importedFileIdentity,
               canonicalIDByIdentity[identity] == nil {
                canonicalIDByIdentity[identity] = item.id
            }
        }

        var migratedItems: [StudyItem] = []
        migratedItems.reserveCapacity(importedItems.count)
        for var item in importedItems {
            let resolvedIdentity = item.importedFileIdentity
                ?? item.url.flatMap(importedFileIdentityResolver)
            if item.importedFileIdentity != resolvedIdentity {
                item.importedFileIdentity = resolvedIdentity
                changed = true
            }
            if item.importedFileLastKnownPath == nil, let path = item.urlPath {
                item.importedFileLastKnownPath = path
                changed = true
            }
            if resolvedIdentity != nil,
               item.importedFileBookmarkData == nil,
               let url = item.url,
               let bookmark = Self.makeImportedFileBookmark(for: url) {
                item.importedFileBookmarkData = bookmark
                changed = true
            }

            if let resolvedIdentity,
               let canonicalID = canonicalIDByIdentity[resolvedIdentity],
               canonicalID != item.id {
                let canonicalItem = migratedItems.first(where: { $0.id == canonicalID })
                    ?? importedItems.first(where: { $0.id == canonicalID })
                if let canonicalItem,
                   canCoalesceDuplicateItem(item, into: canonicalItem) {
                    replaceItemIDEverywhere(item.id, with: canonicalID)
                    changed = true
                    continue
                }
                if item.id.hasPrefix("file:") {
                    let oldID = item.id
                    item.id = Self.makeImportedItemID()
                    replaceItemIDEverywhere(oldID, with: item.id)
                    changed = true
                }
                migratedItems.append(item)
                continue
            }

            if resolvedIdentity != nil, item.id.hasPrefix("file:") {
                let oldID = item.id
                item.id = Self.makeImportedItemID()
                replaceItemIDEverywhere(oldID, with: item.id)
                changed = true
            }
            if let resolvedIdentity {
                canonicalIDByIdentity[resolvedIdentity] = item.id
            }
            migratedItems.append(item)
        }
        importedItems = migratedItems
        return changed
    }

    func canCoalesceDuplicateItem(_ oldItem: StudyItem, into newItem: StudyItem) -> Bool {
        let newID = newItem.id
        guard oldItem.isNotebookNote == newItem.isNotebookNote,
              oldItem.kind == newItem.kind,
              oldItem.isSample == newItem.isSample,
              valuesCanCoalesce(notesByItemID[oldItem.id], notesByItemID[newID]),
              valuesCanCoalesce(pendingNoteWritesByItemID[oldItem.id], pendingNoteWritesByItemID[newID]),
              valuesCanCoalesce(noteBackingContentDigestsByItemID[oldItem.id], noteBackingContentDigestsByItemID[newID]),
              studyLocationsCanCoalesce(oldID: oldItem.id, newID: newID),
              pendingPersistenceCanCoalesce(oldID: oldItem.id, newID: newID) else {
            return false
        }
        return true
    }

    func valuesCanCoalesce<Value: Equatable>(_ oldValue: Value?, _ newValue: Value?) -> Bool {
        oldValue == nil || newValue == nil || oldValue == newValue
    }

    func studyLocationsCanCoalesce(oldID: String, newID: String) -> Bool {
        guard var oldLocation = studyLocationsByItemID[oldID],
              let newLocation = studyLocationsByItemID[newID] else {
            return true
        }
        oldLocation.itemID = newID
        return oldLocation == newLocation
    }

    func pendingPersistenceCanCoalesce(oldID: String, newID: String) -> Bool {
        guard let oldPending = pendingNotePersistenceByItemID[oldID],
              let newPending = pendingNotePersistenceByItemID[newID] else {
            return true
        }
        return oldPending.markdown == newPending.markdown
    }

    func replaceItemIDEverywhere(_ oldID: String, with newID: String) {
        guard oldID != newID else { return }

        if let oldNote = notesByItemID.removeValue(forKey: oldID), notesByItemID[newID] == nil {
            notesByItemID[newID] = oldNote
        }
        if let pendingWrite = pendingNoteWritesByItemID.removeValue(forKey: oldID),
           pendingNoteWritesByItemID[newID] == nil {
            pendingNoteWritesByItemID[newID] = pendingWrite
        }
        if let backingDigest = noteBackingContentDigestsByItemID.removeValue(forKey: oldID),
           noteBackingContentDigestsByItemID[newID] == nil {
            noteBackingContentDigestsByItemID[newID] = backingDigest
        }
        if selectedItemID == oldID { selectedItemID = newID }
        if activeNotebookItemID == oldID { activeNotebookItemID = newID }
        if courseWorkspaceTargetItemID == oldID { courseWorkspaceTargetItemID = newID }

        courseItemMemberships = CourseItemMemberships(
            values: courseItemMemberships.map { membership in
                var copy = membership
                if copy.itemID == oldID { copy.itemID = newID }
                return copy
            }
        ).values

        noteSourceLinks = NoteSourceRelations(
            links: noteSourceLinks.map { link in
                var copy = link
                if copy.noteItemID == oldID { copy.noteItemID = newID }
                if copy.sourceItemID == oldID { copy.sourceItemID = newID }
                return copy
            }
        ).links

        if var location = studyLocationsByItemID.removeValue(forKey: oldID) {
            location.itemID = newID
            if studyLocationsByItemID[newID] == nil {
                studyLocationsByItemID[newID] = location
            }
        }
        for index in studySessions.indices {
            var seen = Set<String>()
            studySessions[index].focusItemIDs = studySessions[index].focusItemIDs.compactMap { itemID in
                let migratedID = itemID == oldID ? newID : itemID
                return seen.insert(migratedID).inserted ? migratedID : nil
            }
        }

        if stagedNoteDraft?.itemID == oldID, let value = stagedNoteDraft?.value {
            stagedNoteDraft = (newID, value)
        }
        if notebookCreationDraft?.sourceItemID == oldID {
            notebookCreationDraft?.sourceItemID = newID
        }
        if notebookRenameDraft?.itemID == oldID {
            notebookRenameDraft?.itemID = newID
        }

        pendingNotePersistenceTasks.removeValue(forKey: oldID)?.cancel()
        if var pending = pendingNotePersistenceByItemID.removeValue(forKey: oldID) {
            pending.item.id = newID
            scheduleNotePersistence(pending.markdown, for: pending.item)
        }
        replaceNavigationItemID(oldID, with: newID)
    }

    func replaceNavigationItemID(_ oldID: String, with newID: String) {
        backNavigationStack = backNavigationStack.map { snapshot in
            var copy = snapshot
            if copy.selectedItemID == oldID { copy.selectedItemID = newID }
            if copy.activeNotebookItemID == oldID { copy.activeNotebookItemID = newID }
            return copy
        }
        forwardNavigationStack = forwardNavigationStack.map { snapshot in
            var copy = snapshot
            if copy.selectedItemID == oldID { copy.selectedItemID = newID }
            if copy.activeNotebookItemID == oldID { copy.activeNotebookItemID = newID }
            return copy
        }
    }

    func showTransientNoteStatus(_ message: String) {
        // Success toasts use a dedicated field so real errors are not overwritten / stuck.
        noteFileError = nil
        transientNoteStatus = message
        let token = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self else { return }
            if self.transientNoteStatus == token {
                self.transientNoteStatus = nil
            }
        }
    }

    func clearGeneratedQuietInsight() {
        if generatedQuietInsight != nil {
            generatedQuietInsight = nil
        }
        quietInsightSignature = ""
    }

    func layoutMatchingThreePaneOrder(_ order: [WorkspacePaneRole]) -> WorkspaceLayout {
        let normalized = WorkspacePaneRole.normalized(order)
        if normalized == [.reader, .notes, .agent] {
            return .documentNotesAgent
        }
        return .documentAgentNotes
    }

    var rightPaneRevealFocus: PaneFocus {
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

    func invalidateAgentContext() {
        agentContextRevision &+= 1
        latestAgentNoteProposal = nil
        lastAgentReplyContextRevision = nil
        quietInsightTask?.cancel()
        if isAskingAgent || agentRequests.requestID != nil {
            cancelAgentRequest()
        }
    }

    func clearUnpinnedFloatingSelection(keepContext: Bool = true, invalidatesAgentContext: Bool = true) {
        // Never kill the float while a selection answer is streaming / pinned for reading.
        if keepFloatingSelectionForAnswer || (pinnedFloatingAgent && agentSurface == .selectionFloat && isAskingAgent) {
            return
        }
        if !keepContext {
            if invalidatesAgentContext, selectionContext != nil {
                invalidateAgentContext()
            }
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

    func collapseSelectionFloatIntoConversationIfVisible() {
        // Keep dual-surface answer: do not auto-collapse float into chat while answering.
        guard !keepFloatingSelectionForAnswer else { return }
        guard isConversationSurfaceVisible, agentSurface == .selectionFloat else { return }
        agentSurface = .hidden
        selectionAnchor = nil
        pinnedFloatingAgent = false
    }

    func refreshQuietInsightIfNeeded() {
        // Quiet insight surface removed for 1.0: never schedule background generation.
        quietInsightTask?.cancel()
        quietInsightTask = nil
        quietInsightTaskID = nil
        isGeneratingQuietInsight = false
        showQuietInsight = false
    }

    func finishQuietInsightTask(id: UUID) {
        guard quietInsightTaskID == id else { return }
        quietInsightTask = nil
        quietInsightTaskID = nil
    }

    func makeQuietInsightSignature(materialText: String, noteText: String, selectionText: String?) -> String {
        [
            selectedItemID ?? "",
            String(materialText.prefix(1_000)),
            String(noteText.prefix(1_000)),
            String((selectionText ?? "").prefix(400))
        ].joined(separator: "\u{1f}")
    }

    func defaultNote(for item: StudyItem?) -> String {
        let title = item.map(displayTitle) ?? ui("新笔记", "New Note")
        let sourceItem = item?.isNotebookNote == true ? nil : item
        return defaultNotebookNote(title: title, sourceItem: sourceItem)
    }

    func defaultNotebookNote(title: String, sourceItem: StudyItem?) -> String {
        let excerptSeed = sourceItem.map { ui("> 来源：\(displayTitle(for: $0))\n", "> Source: \(displayTitle(for: $0))\n") } ?? ""
        return """
        # \(title)

        ## \(ui("核心要点", "Key Points"))

        ## \(ui("摘录", "Excerpts"))
        \(excerptSeed)

        ## \(ui("待追问", "Follow-up Questions"))
        """
    }

    static func noteContentDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func readNotebookMarkdown(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return markdown
    }

    nonisolated static func writeNotebookMarkdown(_ markdown: String, to url: URL) throws {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated static func moveNotebookFile(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    nonisolated static func writeWorkspaceSnapshot(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    static func noteContentDigest(at url: URL) -> String? {
        (try? Data(contentsOf: url)).map(noteContentDigest)
    }

    func noteText(for item: StudyItem?) -> String {
        guard let item else {
            noteFileError = nil
            return defaultNote(for: nil)
        }
        if let pendingWrite = pendingNoteWritesByItemID[item.id],
           let cached = notesByItemID[item.id] {
            let diskDigest = item.url.flatMap(Self.noteContentDigest)
            if let diskDigest {
                noteBackingContentDigestsByItemID[item.id] = diskDigest
            }
            let hasConflict = diskDigest != nil
                && (pendingWrite.baselineContentDigest == nil || pendingWrite.baselineContentDigest != diskDigest)
            noteFileError = hasConflict
                ? ui(
                    "检测到笔记冲突：魏碑草稿和外部文件都已保留，请对照后再处理。",
                    "A note conflict was detected. Both the WeiBei draft and external file were kept for review."
                )
                : ui(
                    "正在保留尚未写回原 Markdown 的最新编辑。",
                    "Keeping the latest edit that has not yet been written back to the original Markdown."
                )
            return cleanLegacyPlaceholder(cached)
        }
        guard item.editsBackingMarkdownFile, let url = item.url else {
            noteFileError = nil
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
        do {
            let data = try Data(contentsOf: url)
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            noteBackingContentDigestsByItemID[item.id] = Self.noteContentDigest(data)
            noteFileError = nil
            return cleanLegacyPlaceholder(markdown)
        } catch {
            noteFileError = ui("无法读取原 Markdown：\(url.lastPathComponent)", "Could not read original Markdown: \(url.lastPathComponent)")
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
    }

    func persistCurrentNote() {
        guard let item = activeNoteItem else { return }
        cancelPendingNotePersistence(for: item.id)
        persistNote(noteText, for: item)
    }

    func flushPendingNotePersistence() {
        let itemIDs = Array(pendingNotePersistenceByItemID.keys)
        itemIDs.forEach { flushPendingNotePersistence(for: $0) }
        studyProgressSaveTask?.cancel()
        studyProgressSaveTask = nil
        syncActiveStudySession()
        // Note flush is a durability boundary: write the workspace now, not after debounce.
        _ = flushPendingWorkspaceSave()
    }

    func scheduleNotePersistence(_ markdown: String, for item: StudyItem) {
        pendingNotePersistenceByItemID[item.id] = PendingNotePersistence(item: item, markdown: markdown)
        pendingNotePersistenceTasks[item.id]?.cancel()
        let itemID = item.id
        let delay = notePersistenceDebounceDelay
        pendingNotePersistenceTasks[itemID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.persistDebouncedNote(for: itemID)
        }
    }

    /**
     * Persists the routine debounced Markdown write through `NotebookRepository`.
     *
     * The store captures identity and conflict expectations on the main actor, then suspends
     * while the repository checks and writes the backing file. Explicit flush and rename paths
     * retain their synchronous durability semantics.
     *
     * @param itemID - Notebook item whose pending edit should be persisted
     */
    func persistDebouncedNote(for itemID: String) async {
        cancelPendingNotePersistence(for: itemID)
        guard let pending = pendingNotePersistenceByItemID.removeValue(forKey: itemID) else { return }
        let item = pending.item
        let markdown = pending.markdown
        guard item.editsBackingMarkdownFile else {
            notesByItemID[itemID] = markdown
            save()
            return
        }
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }) else {
            retainPendingNoteWrite(markdown, itemID: itemID, fallbackURL: item.url)
            noteFileError = ui("无法确认原 Markdown 的课程身份。", "Could not resolve the original Markdown identity.")
            save()
            return
        }
        let resolution = resolveTrackedImportedFile(at: index)
        guard let url = resolution.url else {
            retainPendingNoteWrite(markdown, itemID: itemID, fallbackURL: item.url)
            noteFileError = ui(
                "原 Markdown 已移动或不可用，最新编辑已安全保留在课程中。",
                "The original Markdown moved or is unavailable. The latest edit is safely retained in the course."
            )
            save()
            return
        }
        let pendingWrite = pendingNoteWritesByItemID[itemID]
        let expectedDigest = pendingWrite == nil
            ? noteBackingContentDigestsByItemID[itemID]
            : pendingWrite?.baselineContentDigest
        do {
            let result = try await notebookRepository.writeMarkdown(
                markdown,
                to: url,
                expectedContentDigest: expectedDigest,
                requiresKnownBaseline: pendingWrite != nil
            )
            guard importedItems.contains(where: {
                $0.id == itemID
                    && ($0.urlPath == url.path || $0.importedFileLastKnownPath == url.path)
            }) else {
                retainPendingNoteWrite(markdown, itemID: itemID, fallbackURL: url)
                noteFileError = ui(
                    "写回期间笔记位置发生变化，最新编辑已保留在课程中。",
                    "The note location changed during write-back. The latest edit remains in the course."
                )
                save()
                return
            }
            switch result {
            case .conflict:
                retainPendingNoteWrite(markdown, itemID: itemID, fallbackURL: url)
                noteFileError = ui(
                    "检测到笔记冲突：没有覆盖外部文件，魏碑草稿也已保留。请对照两份内容后再处理。",
                    "A note conflict was detected. The external file was not overwritten, and the WeiBei draft was retained for review."
                )
            case let .written(contentDigest):
                notesByItemID.removeValue(forKey: itemID)
                pendingNoteWritesByItemID.removeValue(forKey: itemID)
                noteBackingContentDigestsByItemID[itemID] = contentDigest
                noteFileError = nil
                if let refreshedItem = refreshImportedFileTracking(itemID: itemID, url: url) {
                    courseDocumentSearchIndex.schedule([refreshedItem])
                }
            }
            save()
        } catch {
            retainPendingNoteWrite(markdown, itemID: itemID, fallbackURL: url)
            noteFileError = ui("无法写回原 Markdown：\(url.lastPathComponent)", "Could not write original Markdown: \(url.lastPathComponent)")
            save()
        }
    }

    func flushPendingNotePersistence(for itemID: String) {
        cancelPendingNotePersistence(for: itemID)
        guard let pending = pendingNotePersistenceByItemID.removeValue(forKey: itemID) else { return }
        persistNote(pending.markdown, for: pending.item)
        save()
    }

    func cancelPendingNotePersistence(for itemID: String) {
        pendingNotePersistenceTasks[itemID]?.cancel()
        pendingNotePersistenceTasks[itemID] = nil
    }

    func retainPendingNoteWrite(_ markdown: String, itemID: String, fallbackURL: URL?) {
        let baseline: String?
        if let existingPendingWrite = pendingNoteWritesByItemID[itemID] {
            baseline = existingPendingWrite.baselineContentDigest
        } else {
            baseline = noteBackingContentDigestsByItemID[itemID]
                ?? fallbackURL.flatMap(Self.noteContentDigest)
        }
        notesByItemID[itemID] = markdown
        pendingNoteWritesByItemID[itemID] = PendingNoteWriteState(
            baselineContentDigest: baseline
        )
    }

    func persistNote(_ markdown: String, for item: StudyItem) {
        let noteItemID = item.id
        if item.editsBackingMarkdownFile {
            guard let index = importedItems.firstIndex(where: { $0.id == noteItemID }) else {
                retainPendingNoteWrite(markdown, itemID: noteItemID, fallbackURL: item.url)
                noteFileError = ui("无法确认原 Markdown 的课程身份。", "Could not resolve the original Markdown identity.")
                save()
                return
            }
            let resolution = resolveTrackedImportedFile(at: index)
            guard let url = resolution.url else {
                retainPendingNoteWrite(markdown, itemID: noteItemID, fallbackURL: item.url)
                noteFileError = ui(
                    "原 Markdown 已移动或不可用，最新编辑已安全保留在课程中。",
                    "The original Markdown moved or is unavailable. The latest edit is safely retained in the course."
                )
                save()
                return
            }
            let pendingWrite = pendingNoteWritesByItemID[noteItemID]
            let expectedDigest = pendingWrite == nil
                ? noteBackingContentDigestsByItemID[noteItemID]
                : pendingWrite?.baselineContentDigest
            let currentDigest = Self.noteContentDigest(at: url)
            let hasConflict: Bool
            if pendingWrite != nil {
                hasConflict = expectedDigest.flatMap { expected in
                    currentDigest.map { $0 != expected }
                } ?? true
            } else if let expectedDigest {
                hasConflict = currentDigest.map { $0 != expectedDigest } ?? true
            } else {
                hasConflict = false
            }
            if hasConflict {
                retainPendingNoteWrite(markdown, itemID: noteItemID, fallbackURL: url)
                noteFileError = ui(
                    "检测到笔记冲突：没有覆盖外部文件，魏碑草稿也已保留。请对照两份内容后再处理。",
                    "A note conflict was detected. The external file was not overwritten, and the WeiBei draft was retained for review."
                )
                save()
                return
            }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                notesByItemID.removeValue(forKey: noteItemID)
                pendingNoteWritesByItemID.removeValue(forKey: noteItemID)
                noteBackingContentDigestsByItemID[noteItemID] = Self.noteContentDigest(Data(markdown.utf8))
                noteFileError = nil
                let refreshedItem = refreshImportedFileTracking(itemID: noteItemID, url: url)
                    ?? importedItems[index]
                courseDocumentSearchIndex.schedule([refreshedItem])
                save()
            } catch {
                retainPendingNoteWrite(markdown, itemID: noteItemID, fallbackURL: url)
                noteFileError = ui("无法写回原 Markdown：\(url.lastPathComponent)", "Could not write original Markdown: \(url.lastPathComponent)")
                save()
            }
            return
        }
        notesByItemID[noteItemID] = markdown
    }

    func load() {
        guard let snapshot = WorkspaceRepository.load(from: storageURL) else { return }
        importedItems = snapshot.importedItems
        notesByItemID = snapshot.notesByItemID.mapValues(cleanLegacyPlaceholder)
        if let persistedPendingNoteWrites = snapshot.pendingNoteWritesByItemID {
            pendingNoteWritesByItemID = persistedPendingNoteWrites
        } else {
            pendingNoteWritesByItemID = [:]
            for item in importedItems
            where item.editsBackingMarkdownFile && notesByItemID[item.id] != nil {
                pendingNoteWritesByItemID[item.id] = PendingNoteWriteState(
                    baselineContentDigest: nil
                )
            }
        }
        noteBackingContentDigestsByItemID = snapshot.noteBackingContentDigestsByItemID ?? [:]
        selectedItemID = snapshot.selectedItemID
        activeNotebookItemID = snapshot.activeNotebookItemID
        courses = snapshot.courses ?? []
        courseItemMemberships = CourseItemMemberships(
            values: snapshot.courseItemMemberships ?? []
        ).values
        activeCourseID = snapshot.activeCourseID
        noteSourceLinks = snapshot.noteSourceLinks ?? []
        noteSourceLinksMigrationVersion = snapshot.noteSourceLinksMigrationVersion ?? 0
        studyLocationsByItemID = snapshot.studyLocationsByItemID ?? [:]
        learningMemoryEntries = snapshot.learningMemoryEntries ?? []
        learningMemoryRevision = snapshot.learningMemoryRevision ?? 0
        studySessions = (snapshot.studySessions ?? []).map { session in
            var bounded = session
            if bounded.messages.count > 500 {
                bounded.messages = Array(bounded.messages.suffix(500))
            }
            return bounded
        }
        activeStudySessionID = snapshot.activeStudySessionID
        if selectedItem?.isNotebookNote == true {
            activeNotebookItemID = selectedItemID
            selectedItemID = sampleItems.first?.id
        }
        if let activeNotebookItemID,
           !allItems.contains(where: { $0.id == activeNotebookItemID && $0.isNotebookNote }) {
            self.activeNotebookItemID = nil
        }
        if let activeCourseID,
           !courses.contains(where: { $0.id == activeCourseID }) {
            self.activeCourseID = courses.first?.id
        }
        if let modelName = snapshot.modelName {
            self.modelName = modelName
        }
        if let agentProviderID = snapshot.agentProviderID.flatMap(AgentProviderID.init(rawValue:)) {
            self.agentProviderID = agentProviderID
        }
        if let agentBaseURL = snapshot.agentBaseURL {
            self.agentBaseURL = agentBaseURL
        }
        openAIAPIKey = apiKeyLoader(agentProviderID.piProviderName)
        // Legacy field: still read so older workspaces restore immersion/multi-pane;
        // free drag order lives in threePaneOrder and is the source of truth for columns.
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
    }

    func cleanLegacyPlaceholder(_ text: String) -> String {
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

    /// Schedule a coalesced workspace snapshot write. Verification and explicit flushes write immediately.
    @discardableResult
    func save() -> Bool {
        if Self.mustSaveImmediately {
            return performSaveNow()
        }
        scheduleDebouncedWorkspaceSave()
        return true
    }

    /// Flush any coalesced save (quit / resign active / note flush / agent send).
    @discardableResult
    func flushPendingWorkspaceSave() -> Bool {
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = nil
        workspaceSaveGeneration &+= 1
        return performSaveNow()
    }

    static var mustSaveImmediately: Bool {
        // Keep verification / self-check / packaging paths synchronous and deterministic.
        let environment = ProcessInfo.processInfo.environment
        if environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1" { return true }
        if environment["WEIBEI_FORCE_IMMEDIATE_SAVE"] == "1" { return true }
        if ProcessInfo.processInfo.arguments.contains("--self-check-imported-identity") { return true }
        return false
    }

    func scheduleDebouncedWorkspaceSave() {
        workspaceSaveGeneration &+= 1
        let generation = workspaceSaveGeneration
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.workspaceSaveDebounceNanoseconds ?? 280_000_000)
            guard let self, !Task.isCancelled, self.workspaceSaveGeneration == generation else { return }
            do {
                let data = try self.encodedWorkspaceSnapshot()
                try await self.workspaceRepository.save(data, generation: generation)
                guard self.workspaceSaveGeneration == generation else { return }
                self.workspaceSaveError = nil
            } catch {
                guard self.workspaceSaveGeneration == generation else { return }
                self.workspaceSaveError = self.ui(
                    "课程更改尚未写入磁盘：\(error.localizedDescription)",
                    "Course changes were not saved to disk: \(error.localizedDescription)"
                )
            }
        }
    }

    @discardableResult
    func performSaveNow() -> Bool {
        WeiBeiPerf.measure("workspace.save") {
            do {
                workspaceSaveGeneration &+= 1
                let data = try encodedWorkspaceSnapshot()
                try workspaceRepository.saveImmediately(data, generation: workspaceSaveGeneration)
                workspaceSaveError = nil
                return true
            } catch {
                workspaceSaveError = ui(
                    "课程更改尚未写入磁盘：\(error.localizedDescription)",
                    "Course changes were not saved to disk: \(error.localizedDescription)"
                )
                return false
            }
        }
    }

    /**
     * Captures the observable state as an encoded persistence payload.
     *
     * Encoding stays on the main actor so every field belongs to one coherent UI generation;
     * the repository performs the slower filesystem write off the main actor.
     *
     * @returns Encoded `PersistedWorkspace` snapshot
     */
    func encodedWorkspaceSnapshot() throws -> Data {
        let snapshot = PersistedWorkspace(
            importedItems: importedItems,
            notesByItemID: notesByItemID,
            pendingNoteWritesByItemID: pendingNoteWritesByItemID,
            noteBackingContentDigestsByItemID: noteBackingContentDigestsByItemID,
            selectedItemID: selectedItemID,
            activeNotebookItemID: activeNotebookItemID,
            courses: courses,
            courseItemMemberships: courseItemMemberships,
            activeCourseID: activeCourseID,
            noteSourceLinks: noteSourceLinks,
            noteSourceLinksMigrationVersion: noteSourceLinksMigrationVersion,
            studyLocationsByItemID: studyLocationsByItemID,
            learningMemoryEntries: learningMemoryEntries,
            learningMemoryRevision: learningMemoryRevision,
            studySessions: studySessions,
            activeStudySessionID: activeStudySessionID,
            modelName: modelName,
            agentProviderID: agentProviderID.rawValue,
            agentBaseURL: agentBaseURL.isEmpty ? nil : agentBaseURL,
            workspaceLayout: layout,
            threePaneOrder: normalizedThreePaneOrder,
            agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface,
            noteRenderMode: noteRenderMode,
            showLibrary: nil,
            showReader: showReader,
            showAgent: showAgent,
            showNotes: showNotes,
            showRightPane: showRightPane,
            showDailyInspiration: showDailyInspiration,
            appearanceModeRaw: appearanceMode.rawValue,
            adaptImportedDocumentColors: adaptImportedDocumentColors,
            interfaceLanguageRaw: interfaceLanguage.rawValue
        )
        return try JSONEncoder().encode(snapshot)
    }

    func resolvedAPIKey() -> (key: String, source: String)? {
        if Self.environmentValue("WEIBEI_FORCE_OFFLINE_AGENT") == "1" {
            return nil
        }

        let envName = agentProviderID.environmentAPIKeyName
        let environmentKey = Self.environmentValue(envName)
        if !environmentKey.isEmpty {
            return (environmentKey, ui("本机环境变量", "local environment variable"))
        }
        // Always honor OPENAI_API_KEY as a last-resort env for openai-compatible keys.
        if agentProviderID != .openai {
            let openaiEnv = Self.environmentValue("OPENAI_API_KEY")
            if !openaiEnv.isEmpty {
                return (openaiEnv, ui("本机环境变量", "local environment variable"))
            }
        }

        // Prefer the in-settings field even before the user clicks Save — otherwise
        // typed keys look "configured" in the UI but never reach the request.
        let fieldKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)
        if !fieldKey.isEmpty {
            return (fieldKey, ui("设置中的密钥", "key from Settings"))
        }

        let savedKey = apiKeyLoader(agentProviderID.piProviderName)
        if !savedKey.isEmpty {
            return (savedKey, ui("魏碑应用数据", "WeiBei app data"))
        }

        return nil
    }

    /// Backward-compatible alias used by remaining call sites / SelfCheck slices.
    func resolvedOpenAIAPIKey() -> (key: String, source: String)? {
        resolvedAPIKey()
    }

    var resolvedModelName: String {
        let environmentModel = Self.environmentValue("WEIBEI_OPENAI_MODEL")
        return environmentModel.isEmpty ? modelName : environmentModel
    }

    static func environmentValue(_ name: String) -> String {
        OpenAIAPIKeyStore.cleaned(ProcessInfo.processInfo.environment[name] ?? "")
    }

    static func removeLegacyCourseIndex(in directory: URL) {
        for version in ["v1", "v2"] {
            let legacy = directory.appendingPathComponent("course-search-\(version).sqlite3")
            for url in [
                legacy,
                URL(fileURLWithPath: legacy.path + "-wal"),
                URL(fileURLWithPath: legacy.path + "-shm"),
            ] where FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func workspaceRootDirectory() -> URL? {
        let override = environmentValue("WEIBEI_WORKSPACE_DIR")
        if !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WeiBei", isDirectory: true)
    }
}
