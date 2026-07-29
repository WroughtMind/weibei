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

struct AgentRequestRevisionSnapshot: Equatable {
    let workspace: UInt64
    let memory: UInt64

    /**
     * 判断异步 Agent 结果是否仍属于当前工作区和学习记忆版本。
     */
    func isCurrent(workspace: UInt64, memory: UInt64) -> Bool {
        self.workspace == workspace && self.memory == memory
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
    private(set) static var isMeasuring = false
    private(set) static var htmlEventSequence = 0
    private(set) static var htmlSectionEventCount = 0
    private(set) static var htmlActiveEventCount = 0
    private(set) static var htmlLocationCallCount = 0
    private(set) static var htmlLocationCommitCount = 0
    private(set) static var htmlLocationReasons: [String: Int] = [:]
    private(set) static var webReaderMakeCount = 0
    private(set) static var webReaderDismantleCount = 0
    private(set) static var pdfReaderMakeCount = 0
    private(set) static var pdfReaderDismantleCount = 0
    private(set) static var noteEditorMakeCount = 0
    private(set) static var noteEditorDismantleCount = 0
    private(set) static var verificationScrollScheduleCount = 0
    private(set) static var verificationScrollResult = ""

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
    @Published private(set) var courses: [Course] = []
    @Published private(set) var courseItemMemberships: [CourseItemMembership] = [] {
        didSet {
            courseMembershipIndex = CourseItemMemberships(values: courseItemMemberships)
        }
    }
    @Published private(set) var activeCourseID: UUID?
    @Published var noteText = ""
    @Published var agentDraft = ""
    @Published var messages: [AgentMessage] = []
    @Published var isAskingAgent = false
    @Published var agentStreamingText = ""
    @Published var agentActivityText: String?
    @Published var showLoadingIndicatorSamples = false
    /// Last failed user question for precise one-tap retry.
    @Published private(set) var lastFailedAgentQuestion: String?
    @Published private(set) var lastAgentFailureKind: AgentFailureKind?
    @Published private(set) var latestAgentNoteProposal: StudyAgentNoteProposal?
    @Published private(set) var latestAgentLearningUpdate: StudyAgentLearningUpdate?
    @Published private(set) var noteSourceLinks: [NoteSourceLink] = [] {
        didSet {
            noteSourceRelationIndex = NoteSourceRelationIndex(links: noteSourceLinks)
        }
    }
    @Published var linkedSourcesPresented = false
    private(set) var studyLocationsByItemID: [String: StudyLocation] = [:]
    @Published private(set) var learningMemoryEntries: [LearningMemoryEntry] = []
    @Published private(set) var learningMemoryRevision: UInt64 = 0
    @Published private(set) var studySessions: [StudySession] = []
    @Published private(set) var activeStudySessionID: UUID?
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
    @Published private(set) var readerTargetPageRequestID = UUID()
    @Published private(set) var readerTargetPageRecordsLocation = false
    @Published var readerTargetLocationID: String?
    @Published var readerTargetLocationTitle: String?
    @Published private(set) var readerTargetLocationRequestID = UUID()
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
    @Published private(set) var paneExpansionRequest: PaneExpansionRequest?
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
    @Published private(set) var workspaceSaveError: String?
    @Published var notebookCreationDraft: NotebookCreationDraft?
    @Published var notebookRenameDraft: NotebookRenameDraft?
    @Published var modelName: String = ProcessInfo.processInfo.environment["WEIBEI_OPENAI_MODEL"] ?? "gpt-5.5"
    @Published var agentProviderID: AgentProviderID = .openai
    @Published var agentBaseURL: String = ""
    /// Loaded once in `load()` after provider/profile IDs are restored — never in the
    /// property default (that double-hit Keychain with a second load and caused dual password prompts).
    @Published var openAIAPIKey: String = ""
    @Published var openAIKeyStatus: String?
    @Published var agentAuthMethod: AgentAuthMethod = .apiKey
    @Published var agentCredentialProfiles: [AgentCredentialProfile]
    @Published var activeAgentProfileID: UUID
    // Model-list discovery (settings UI). Backed by `AgentModelListService`.
    @Published var availableModels: [String] = []
    @Published var modelListStatus: ModelListStatus = .idle
    @Published var bedrockRegion: String = ProcessInfo.processInfo.environment["WEIBEI_BEDROCK_REGION"] ?? "us-east-1"
    // Race guard for `refreshModelList` (see S2). Without this, rapidly switching
    // profiles / providers launches overlapping async fetches; whichever resolves
    // last wins and can paint the wrong provider's catalog. `modelFetchGeneration`
    // tags each in-flight request so a stale resolution is discarded; the held
    // `modelFetchTask` is cancelled when a newer request supersedes it.
    private var modelFetchGeneration: UInt64 = 0
    private var modelFetchTask: Task<Void, Never>?
    @Published var appearanceMode: WeiBeiAppearanceMode = .paper
    @Published var adaptImportedDocumentColors = true
    @Published var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    @Published var courseWorkspacePresented = false
    @Published private(set) var courseWorkspaceDestination: CourseWorkspaceDestination = .hub
    @Published private(set) var courseWorkspaceTargetItemID: String?
    @Published var courseFolderImportDraft: CourseFolderImportDraft?
    @Published private var backNavigationStack: [NavigationSnapshot] = []
    @Published private var forwardNavigationStack: [NavigationSnapshot] = []

    private var notesByItemID: [String: String] = [:]
    private var pendingNoteWritesByItemID: [String: PendingNoteWriteState] = [:]
    private var noteBackingContentDigestsByItemID: [String: String] = [:]
    private let storageURL: URL
    private let notebookRenameJournalURL: URL
    private let importedFileIdentityResolver: (URL) -> ImportedFileIdentity?
    private let notebookMarkdownReader: (URL) throws -> String
    private let notebookMarkdownWriter: (String, URL) throws -> Void
    private let notebookFileMover: (URL, URL) throws -> Void
    private let workspaceSnapshotWriter: (Data, URL) throws -> Void
    private let storedAPIKeyResolver: (() -> String)?
    private let modelListFetcher: (ModelListStrategy, String) async throws -> [String]
    private let agentRequestExecutor: ((StudyAgentRequest) async throws -> StudyAgentReply)?
    private let piRuntime: PiAgentRuntime
    private let courseDocumentSearchIndex: CourseDocumentSearchIndex
    private var activeAgentRequestID: UUID?
    private var agentRequestTask: Task<Void, Never>?
    private var quietInsightTask: Task<Void, Never>?
    private var quietInsightTaskID: UUID?
    private var agentContextRevision: UInt64 = 0
    private var lastAgentReplyContextRevision: UInt64?
    private var latestAgentLearningUpdateQuestion: String?
    private var stagedNoteDraft: (itemID: String, value: String)?
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
    private var studyProgressSaveTask: Task<Void, Never>?
    private let studyProgressSaveDelay: UInt64 = 900_000_000
    /// Coalesce the 70+ main-thread full-workspace JSON saves that fire on every UI toggle.
    private var pendingWorkspaceSaveTask: Task<Void, Never>?
    private var workspaceSaveGeneration: UInt64 = 0
    private let workspaceSaveDebounceNanoseconds: UInt64 = 280_000_000
    private var noteSourceLinksMigrationVersion = 0
    private var noteSourceRelationIndex = NoteSourceRelationIndex(links: [])
    private var courseMembershipIndex = CourseItemMemberships()
    private var courseWorkspaceReturnFocus: PaneFocus?

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
        var readerLocationID: String?
        var readerLocationTitle: String?
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

    private struct CourseIndexCandidate: Sendable {
        var item: StudyItem
        var title: String
        var subtitle: String
        var embeddedText: String?
        var fallbackText: String
    }

    private struct CourseContextBuildResult: Sendable {
        var context: StudyAgentCourseContext
        var selectedMaterialText: String?
        var selectedMaterialIsTruncated: Bool
    }

    private struct ResolvedImportedFileBookmark {
        var url: URL
        var isStale: Bool
    }

    private struct PendingNotebookRenameJournal: Codable {
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

    private var lastUsableAgentAnswer: AgentMessage? {
        guard lastAgentReplyContextRevision == agentContextRevision else { return nil }
        return messages.last { $0.isUsableAgentAnswer }
    }

    private static let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let sampleItems: [StudyItem]

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
        credentialProfiles: [AgentCredentialProfile]? = nil,
        activeCredentialProfileID: UUID? = nil,
        storedAPIKeyResolver: (() -> String)? = nil,
        modelListFetcher: @escaping (ModelListStrategy, String) async throws -> [String] = {
            try await AgentModelListService.shared.fetchModels(strategy: $0, apiKey: $1)
        },
        agentRequestExecutor: ((StudyAgentRequest) async throws -> StudyAgentReply)? = nil
    ) {
        let loadedProfiles = credentialProfiles ?? AgentCredentialProfileStore.loadProfiles()
        let resolvedActiveProfileID = activeCredentialProfileID
            ?? AgentCredentialProfileStore.activeProfileID()
            ?? loadedProfiles.first?.id
            ?? AgentCredentialProfileStore.defaultProfile().id
        sampleItems = Self.makeSampleItems(workspaceDirectory: folder)
        agentCredentialProfiles = loadedProfiles
        activeAgentProfileID = resolvedActiveProfileID
        storageURL = folder.appendingPathComponent("workspace.json")
        notebookRenameJournalURL = folder.appendingPathComponent("pending-notebook-rename.json")
        self.importedFileIdentityResolver = importedFileIdentityResolver
        self.notebookMarkdownReader = notebookMarkdownReader
        self.notebookMarkdownWriter = notebookMarkdownWriter
        self.notebookFileMover = notebookFileMover
        self.workspaceSnapshotWriter = workspaceSnapshotWriter
        self.storedAPIKeyResolver = storedAPIKeyResolver
        self.modelListFetcher = modelListFetcher
        self.agentRequestExecutor = agentRequestExecutor
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

    var allItems: [StudyItem] {
        sampleItems + importedItems
    }

    var courseMaterials: [StudyItem] {
        importedItems.filter { !$0.isNotebookNote }
    }

    var courseNotebookItems: [StudyItem] {
        importedItems.filter(\.isNotebookNote)
    }

    var activeCourse: Course? {
        guard let activeCourseID else { return nil }
        return courses.first { $0.id == activeCourseID }
    }

    func course(withID courseID: UUID) -> Course? {
        courses.first { $0.id == courseID }
    }

    func courseItems(in courseID: UUID) -> [StudyItem] {
        let itemIDs = Set(courseMembershipIndex.itemIDs(in: courseID))
        return importedItems.filter { itemIDs.contains($0.id) }
    }

    func courseMaterials(in courseID: UUID) -> [StudyItem] {
        courseItems(in: courseID).filter { !$0.isNotebookNote }
    }

    func courseNotes(in courseID: UUID) -> [StudyItem] {
        courseItems(in: courseID).filter(\.isNotebookNote)
    }

    func courseIDs(for itemID: String) -> [UUID] {
        courseMembershipIndex.courseIDs(for: itemID)
    }

    var unassignedCourseMaterials: [StudyItem] {
        courseMaterials.filter { courseMembershipIndex.courseIDs(for: $0.id).isEmpty }
    }

    var unassignedCourseNotes: [StudyItem] {
        courseNotebookItems.filter { courseMembershipIndex.courseIDs(for: $0.id).isEmpty }
    }

    func activateCourse(_ id: UUID?) {
        let resolvedID = id.flatMap { candidate in
            courses.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        guard activeCourseID != resolvedID else { return }
        activeCourseID = resolvedID
        save()
    }

    @discardableResult
    func createCourse(title rawTitle: String) -> UUID? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let course = Course(
            title: title,
            colorIndex: nextCourseColorIndex()
        )
        courses.append(course)
        activeCourseID = course.id
        save()
        return course.id
    }

    func renameCourse(_ courseID: UUID, title rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let index = courses.firstIndex(where: { $0.id == courseID }),
              courses[index].title != title else { return }
        courses[index].title = title
        courses[index].updatedAt = Date()
        save()
    }

    func deleteCourse(_ courseID: UUID) {
        guard courses.contains(where: { $0.id == courseID }) else { return }
        courses.removeAll { $0.id == courseID }
        var memberships = courseMembershipIndex
        memberships.removeCourse(courseID)
        courseItemMemberships = memberships.values
        if activeCourseID == courseID {
            activeCourseID = courses.first?.id
        }
        save()
    }

    func setCourseIDs(_ courseIDs: Set<UUID>, for itemID: String) {
        guard importedItems.contains(where: { $0.id == itemID }) else { return }
        let validCourseIDs = Set(courses.map(\.id))
        var memberships = courseMembershipIndex
        memberships.replaceCourses(for: itemID, courseIDs: courseIDs.intersection(validCourseIDs))
        guard memberships.values != courseItemMemberships else { return }
        courseItemMemberships = memberships.values
        save()
    }

    func assignItemIDs(_ itemIDs: Set<String>, to courseID: UUID) {
        guard courses.contains(where: { $0.id == courseID }) else { return }
        let validItemIDs = Set(importedItems.map(\.id))
        var memberships = courseMembershipIndex
        memberships.assign(itemIDs: itemIDs.intersection(validItemIDs), to: courseID)
        guard memberships.values != courseItemMemberships else { return }
        courseItemMemberships = memberships.values
        activeCourseID = courseID
        save()
    }

    func relationCount(in courseID: UUID) -> Int {
        let materialIDs = Set(courseMaterials(in: courseID).map(\.id))
        let noteIDs = Set(courseNotes(in: courseID).map(\.id))
        return noteSourceLinks.lazy.filter {
            materialIDs.contains($0.sourceItemID) && noteIDs.contains($0.noteItemID)
        }.count
    }

    var recentCourseSessions: [StudySession] {
        orderedStudySessions.filter { !$0.messages.isEmpty }
    }

    /// Sessions that touch any material/note belonging to the course (no session.courseID yet).
    func sessionsTouchingCourse(_ courseID: UUID) -> [StudySession] {
        let itemIDs = Set(courseMembershipIndex.itemIDs(in: courseID))
        guard !itemIDs.isEmpty else { return [] }
        return orderedStudySessions.filter { session in
            guard !session.messages.isEmpty else { return false }
            if let materialID = session.materialItemID, itemIDs.contains(materialID) {
                return true
            }
            if let groupingID = session.groupingMaterialItemID, itemIDs.contains(groupingID) {
                return true
            }
            return session.focusItemIDs.contains(where: itemIDs.contains)
        }
    }

    /// Sessions that reference a specific material (and optionally other focus items).
    func sessionsTouchingMaterial(_ materialID: String, in courseID: UUID? = nil) -> [StudySession] {
        let allowed: Set<String>? = courseID.map { Set(courseMembershipIndex.itemIDs(in: $0)) }
        return orderedStudySessions.filter { session in
            guard !session.messages.isEmpty else { return false }
            let touches = session.materialItemID == materialID
                || session.groupingMaterialItemID == materialID
                || session.focusItemIDs.contains(materialID)
            guard touches else { return false }
            if let allowed {
                let sessionItems = Set(session.focusItemIDs + [session.materialItemID, session.groupingMaterialItemID].compactMap { $0 })
                return !sessionItems.isDisjoint(with: allowed)
            }
            return true
        }
    }

    /// Best-effort course ownership for a session via materials/focus items (no session.courseID yet).
    func primaryCourseID(for session: StudySession) -> UUID? {
        let touched = Set(
            session.focusItemIDs
                + [session.materialItemID, session.groupingMaterialItemID].compactMap { $0 }
        )
        guard !touched.isEmpty else { return nil }
        let matched = courses.filter { course in
            !Set(courseMembershipIndex.itemIDs(in: course.id)).isDisjoint(with: touched)
        }
        if let activeCourseID, matched.contains(where: { $0.id == activeCourseID }) {
            return activeCourseID
        }
        return matched.first?.id
    }

    var activeCourseMemories: [LearningMemoryEntry] {
        orderedLearningMemoryEntries.filter { $0.status == .active }
    }

    var recentCourseMessages: [AgentMessage] {
        studySessions
            .flatMap(\.messages)
            .sorted { $0.createdAt > $1.createdAt }
    }

    var courseWorkspaceSummary: CourseWorkspaceSummary {
        CourseWorkspaceSummary(
            importedItems: importedItems,
            noteSourceLinks: noteSourceLinks,
            studyLocationsByItemID: studyLocationsByItemID,
            studySessions: studySessions,
            learningMemoryEntries: learningMemoryEntries
        )
    }

    var courseMaterialsWithoutReadingPosition: [StudyItem] {
        courseMaterials.filter { studyLocationsByItemID[$0.id] == nil }
    }

    var courseMaterialsWithoutNoteLinks: [StudyItem] {
        let validNoteIDs = Set(courseNotebookItems.map(\.id))
        let linkedIDs = Set(noteSourceLinks.lazy.filter { validNoteIDs.contains($0.noteItemID) }.map(\.sourceItemID))
        return courseMaterials.filter { !linkedIDs.contains($0.id) }
    }

    var courseNotesWithoutSourceLinks: [StudyItem] {
        let validSourceIDs = Set(courseMaterials.map(\.id))
        let linkedIDs = Set(noteSourceLinks.lazy.filter { validSourceIDs.contains($0.sourceItemID) }.map(\.noteItemID))
        return courseNotebookItems.filter { !linkedIDs.contains($0.id) }
    }

    func studyLocation(for itemID: String) -> StudyLocation? {
        studyLocationsByItemID[itemID]
    }

    func linkedNotes(for sourceItemID: String) -> [StudyItem] {
        let noteIDs = Set(linkedNoteIDs(for: sourceItemID))
        return courseNotebookItems.filter { noteIDs.contains($0.id) }
    }

    func linkedNoteIDs(for sourceItemID: String) -> [String] {
        noteSourceRelationIndex.noteIDs(for: sourceItemID)
    }

    func linkedNoteCount(for sourceItemID: String) -> Int {
        noteSourceRelationIndex.noteCount(for: sourceItemID)
    }

    func item(withID itemID: String) -> StudyItem? {
        allItems.first { $0.id == itemID }
    }

    var linkedSourceIDsForActiveNote: [String] {
        guard let noteItemID = activeNotebookItemID else { return [] }
        return linkedSourceIDs(for: noteItemID)
    }

    func linkedSourceIDs(for noteItemID: String) -> [String] {
        noteSourceRelationIndex.sourceIDs(for: noteItemID)
    }

    func linkedSourceCount(for noteItemID: String) -> Int {
        noteSourceRelationIndex.sourceCount(for: noteItemID)
    }

    func linkedCourseSourceIDs(for noteItemID: String) -> [String] {
        let validCourseIDs = Set(courseMaterials.map(\.id))
        return noteSourceRelationIndex.sourceIDs(for: noteItemID).filter(validCourseIDs.contains)
    }

    var linkedSourcesForActiveNote: [StudyItem] {
        let linkedIDs = Set(linkedSourceIDsForActiveNote)
        return allItems.filter { linkedIDs.contains($0.id) && !$0.isNotebookNote }
    }

    var linkedSourceCount: Int {
        linkedSourcesForActiveNote.count
    }

    var filteredItems: [StudyItem] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }
        return allItems.filter { itemMatchesLibrarySearch($0, query: query) }
    }

    var activeStudySession: StudySession? {
        guard let activeStudySessionID else { return nil }
        return studySessions.first { $0.id == activeStudySessionID }
    }

    var orderedStudySessions: [StudySession] {
        studySessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Sessions for the session menu: either all, or material-grouped with current material first.
    var studySessionsForMenu: [StudySession] {
        if showAllStudySessions {
            return orderedStudySessions
        }
        if let materialID = selectedMaterialItem?.id {
            let matching = orderedStudySessions.filter { $0.groupingMaterialItemID == materialID }
            if !matching.isEmpty { return matching }
        }
        return orderedStudySessions
    }

    /// Grouped history for the expanded "view all" picker: material title → sessions.
    var studySessionsGroupedByMaterial: [(materialID: String?, title: String, sessions: [StudySession])] {
        var groups: [String?: [StudySession]] = [:]
        for session in orderedStudySessions {
            groups[session.groupingMaterialItemID, default: []].append(session)
        }
        return groups.keys.sorted { lhs, rhs in
            let leftDate = groups[lhs]?.first?.updatedAt ?? .distantPast
            let rightDate = groups[rhs]?.first?.updatedAt ?? .distantPast
            return leftDate > rightDate
        }.map { materialID in
            let title: String
            if let materialID, let item = allItems.first(where: { $0.id == materialID }) {
                title = displayTitle(for: item)
            } else {
                title = ui("未关联资料", "Unlinked")
            }
            return (materialID, title, groups[materialID] ?? [])
        }
    }

    var orderedLearningMemoryEntries: [LearningMemoryEntry] {
        learningMemoryEntries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func learningMemoryKindLabel(_ kind: LearningMemoryKind) -> String {
        switch kind {
        case .goal: ui("目标", "Goal")
        case .understood: ui("已理解", "Understood")
        case .confusion: ui("困惑", "Confusion")
        case .nextStep: ui("下一步", "Next Step")
        case .preference: ui("偏好", "Preference")
        }
    }

    var activeStudySessionTitle: String {
        activeStudySession?.title ?? ui("新学习会话", "New Study Session")
    }

    var lastStudyLocation: StudyLocation? {
        studyLocationsByItemID.values.max { $0.lastStudiedAt < $1.lastStudiedAt }
    }

    var canResumePreviousStudy: Bool {
        lastStudyLocation != nil
    }

    var hasCurrentSessionInferredMemory: Bool {
        guard let activeStudySessionID else { return false }
        return learningMemoryEntries.contains {
            $0.sessionID == activeStudySessionID && $0.origin == .agentInference
        }
    }

    func createStudySession() {
        cancelAgentRequest()
        syncActiveStudySession()
        let materialID = selectedMaterialItem?.id
        let session = StudySession(
            title: ui("新学习会话", "New Study Session"),
            focusItemIDs: [materialID].compactMap { $0 },
            materialItemID: materialID
        )
        studySessions.append(session)
        activeStudySessionID = session.id
        messages = []
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        lastAgentReplyContextRevision = nil
        invalidateAgentContext()
        save()
    }

    func setShowAllStudySessions(_ enabled: Bool) {
        showAllStudySessions = enabled
    }

    func activateStudySession(_ id: UUID) {
        guard id != activeStudySessionID,
              let session = studySessions.first(where: { $0.id == id }) else { return }
        cancelAgentRequest()
        syncActiveStudySession()
        activeStudySessionID = id
        messages = session.messages
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        lastAgentReplyContextRevision = nil
        invalidateAgentContext()
        save()
    }

    func deleteStudySession(_ id: UUID) {
        guard studySessions.count > 1,
              let index = studySessions.firstIndex(where: { $0.id == id }) else { return }
        let deletingActiveSession = activeStudySessionID == id
        if deletingActiveSession { cancelAgentRequest() }
        studySessions.remove(at: index)
        learningMemoryEntries.removeAll { $0.sessionID == id && $0.origin == .agentInference }
        if deletingActiveSession, let replacement = orderedStudySessions.first {
            activeStudySessionID = replacement.id
            messages = replacement.messages
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            lastAgentReplyContextRevision = nil
            invalidateAgentContext()
        }
        learningMemoryRevision &+= 1
        save()
    }

    func clearCurrentSessionInferredMemory() {
        guard let activeStudySessionID else { return }
        let previousCount = learningMemoryEntries.count
        learningMemoryEntries.removeAll {
            $0.sessionID == activeStudySessionID && $0.origin == .agentInference
        }
        guard learningMemoryEntries.count != previousCount else { return }
        learningMemoryRevision &+= 1
        latestAgentLearningUpdate = nil
        invalidateAgentContext()
        save()
    }

    func resumePreviousStudy() {
        guard let location = lastStudyLocation,
              let item = allItems.first(where: { $0.id == location.itemID }) else { return }
        if layout == .immersiveConversation || layout == .immersiveWriting {
            setLayout(item.isNotebookNote ? .immersiveWriting : .immersiveReading)
        }
        select(itemID: location.itemID)
        if item.isNotebookNote {
            showNotes = true
            focus(.notes)
            return
        }
        requestReaderPDFPage(location.pageIndex, recordsLocation: false)
        requestReaderHTMLLocation(id: location.locationID, title: location.locationTitle)
        showReader = true
        focus(.reader)
    }

    private func ensureActiveStudySession() {
        if let activeStudySessionID,
           let session = studySessions.first(where: { $0.id == activeStudySessionID }) {
            messages = session.messages
            return
        }
        if let session = orderedStudySessions.first {
            activeStudySessionID = session.id
            messages = session.messages
            return
        }
        let session = StudySession(title: ui("新学习会话", "New Study Session"))
        studySessions = [session]
        activeStudySessionID = session.id
        messages = []
    }

    private func appendAgentMessage(_ message: AgentMessage) {
        messages.append(message)
        syncActiveStudySession(titleSeed: message.role == .user ? message.text : nil)
        save()
    }

    private func syncActiveStudySession(titleSeed: String? = nil) {
        guard let activeStudySessionID,
              let index = studySessions.firstIndex(where: { $0.id == activeStudySessionID }) else { return }
        studySessions[index].messages = messages
        studySessions[index].updatedAt = Date()
        if let titleSeed,
           studySessions[index].messages.filter({ $0.role == .user }).count == 1 {
            studySessions[index].title = Self.sessionTitle(from: titleSeed)
        }
        if studySessions[index].materialItemID == nil,
           let materialID = selectedMaterialItem?.id {
            studySessions[index].materialItemID = materialID
        }
        for itemID in [selectedItemID, activeNoteItemID].compactMap({ $0 }) {
            if !studySessions[index].focusItemIDs.contains(itemID) {
                studySessions[index].focusItemIDs.append(itemID)
            }
        }
        if studySessions[index].focusItemIDs.count > 24 {
            studySessions[index].focusItemIDs.removeFirst(studySessions[index].focusItemIDs.count - 24)
        }
    }

    private static func sessionTitle(from text: String) -> String {
        let title = text
            .replacingOccurrences(of: #"[`*_>#\[\]()]"#, with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return title.isEmpty ? "Study Session" : String(title.prefix(36))
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

    private func sourceReferenceBaseTitle(for item: StudyItem) -> String {
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

    private var quietInsightReferenceTitle: String {
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
                "当前提供商：\(agentProviderID.label(language: interfaceLanguage))。密钥保存在魏碑应用数据中，跨次启动自动带上，不会弹 macOS 钥匙串密码。",
                "Provider: \(agentProviderID.label(language: interfaceLanguage)). The key is stored in WeiBei app data, restored on launch, and never prompts for the Mac login keychain."
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

    private static func localPiSubscriptionAuthIsAvailable() -> Bool {
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

    private static func localPiSubscriptionSettings() -> [String: String] {
        // Prefer WeiBei-owned settings; fall back to defaults without reading terminal ~/.pi.
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
        WeiBeiPerf.measure("workspace.select") {
            selectMeasured(itemID: itemID)
        }
    }

    private func selectMeasured(itemID: String?) {
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
    private func activateLatestStudySession(forMaterialID materialID: String) {
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

    private func alignActiveCourse(with itemID: String) {
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

    private func dismissCourseWorkspace(restoringFocus: Bool) {
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

    private func flushStagedNoteDraftForAgentContext() {
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

    func focus(_ pane: PaneFocus) {
        if pane == .library {
            if !showLibrary {
                recordNavigationPoint()
                clearUnpinnedFloatingSelection()
            }
            showLibrary = true
        }
        if pane == .agent {
            if layout == .documentNotesSplit, !showAgent {
                showAgent = true
            } else if layout == .immersiveReading || layout == .immersiveWriting {
                // Primary chat is immersive conversation, not a deleted overlay surface.
                layout = .immersiveConversation
                showAgent = true
                if agentSurface != .selectionFloat {
                    agentSurface = .hidden
                }
                showQuietInsight = false
            }
        }
        collapseSelectionFloatIntoConversationIfVisible()
        focusedPane = pane
        focusRequest += 1
    }

    func toggleLibrary() {
        let willShow = !showLibrary

        // 1) Flip drawer chrome first — publishes only on `libraryDrawer`, so reader/agent/notes
        //    do not re-render and the slide can start on the next frame.
        showLibrary = willShow

        // 2) Focus / selection side effects next run-loop tick (touches WorkspaceStore @Published).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                if willShow {
                    self.clearUnpinnedFloatingSelection()
                    self.focusedPane = .library
                } else if self.focusedPane == .library {
                    self.focusedPane = .reader
                }
                self.focusRequest += 1
            }
        }
    }

    func revealLibrary() {
        if !showLibrary {
            clearUnpinnedFloatingSelection()
        }
        showLibrary = true
        focus(.library)
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
            let openingFromEmptyBoard = !showReader && !showAgent && !showNotes
            let willShow = !isPaneVisible(role)
            setDocumentPane(willShow, role)
            // Empty board → first open: restore canonical 文稿 | 对话 | 笔记 left→right order.
            if willShow && openingFromEmptyBoard {
                threePaneOrder = WorkspacePaneRole.defaultThreePaneOrder
            }
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
        let nextTitle = cleaned.isEmpty ? selectedMaterialItem.map(displayTitle) : cleaned
        guard readerLocationTitle != nextTitle else { return }
        readerLocationTitle = nextTitle
    }

    func updateReaderHTMLLocation(id: String?, title: String?, reason: String) {
        guard selectedMaterialItem?.kind == .html else { return }
        PaneToggleContinuityVerifier.recordHTMLLocationCall(reason: reason)
        let cleanedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextID = cleanedID.isEmpty ? nil : String(cleanedID.prefix(500))
        let nextTitle = cleanedTitle.isEmpty ? selectedMaterialItem.map(displayTitle) : String(cleanedTitle.prefix(300))
        if reason == "jump" {
            clearReaderHTMLLocationTarget()
        }
        guard readerLocationID != nextID || readerLocationTitle != nextTitle else { return }
        PaneToggleContinuityVerifier.recordHTMLLocationCommit(reason: reason)
        readerLocationID = nextID
        readerLocationTitle = nextTitle
        recordCurrentStudyLocation(incrementVisit: false)
    }

    private func requestReaderHTMLLocation(id: String?, title: String?) {
        readerTargetLocationID = id
        readerTargetLocationTitle = title
        readerTargetLocationRequestID = UUID()
    }

    private func clearReaderHTMLLocationTarget() {
        guard readerTargetLocationID != nil || readerTargetLocationTitle != nil else { return }
        readerTargetLocationID = nil
        readerTargetLocationTitle = nil
    }

    private func requestReaderPDFPage(_ pageIndex: Int?, recordsLocation: Bool) {
        readerTargetPageRecordsLocation = recordsLocation && pageIndex != nil
        readerTargetPageIndex = pageIndex.map { max($0, 0) }
        readerTargetPageRequestID = UUID()
    }

    func consumeReaderPDFPageRequest(_ requestID: UUID) {
        guard readerTargetPageRequestID == requestID else { return }
        readerTargetPageIndex = nil
        readerTargetPageRecordsLocation = false
    }

    func updateReaderPageIndex(_ index: Int) {
        let nextIndex = max(index, 0)
        guard readerPageIndex != nextIndex else { return }
        readerPageIndex = nextIndex
        recordCurrentStudyLocation(incrementVisit: false)
    }

    private func recordCurrentStudyLocation(incrementVisit: Bool) {
        guard let item = selectedMaterialItem else { return }
        let previous = studyLocationsByItemID[item.id]
        let itemTitle = sourceReferenceBaseTitle(for: item)
        let locationID = item.kind == .html ? readerLocationID : nil
        let pageIndex = item.kind == .pdf ? readerPageIndex : nil
        if !incrementVisit,
           previous?.itemTitle == itemTitle,
           previous?.locationID == locationID,
           previous?.locationTitle == readerLocationTitle,
           previous?.pageIndex == pageIndex {
            return
        }
        studyLocationsByItemID[item.id] = StudyLocation(
            itemID: item.id,
            itemTitle: itemTitle,
            locationID: locationID,
            locationTitle: readerLocationTitle,
            pageIndex: pageIndex,
            lastStudiedAt: Date(),
            visitCount: max((previous?.visitCount ?? 0) + (incrementVisit ? 1 : 0), 1)
        )
        studyProgressSaveTask?.cancel()
        let delay = studyProgressSaveDelay
        studyProgressSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.studyProgressSaveTask = nil
            self?.save()
        }
    }

    private func restoreCurrentStudyLocation() {
        guard let item = selectedMaterialItem else { return }
        guard let location = studyLocationsByItemID[item.id] else {
            readerLocationID = nil
            readerLocationTitle = displayTitle(for: item)
            return
        }
        readerLocationID = item.kind == .html ? location.locationID : nil
        readerLocationTitle = location.locationTitle ?? displayTitle(for: item)
        if item.kind == .pdf {
            readerPageIndex = max(location.pageIndex ?? 0, 0)
            requestReaderPDFPage(location.pageIndex, recordsLocation: false)
        } else if item.kind == .html {
            requestReaderHTMLLocation(id: location.locationID, title: location.locationTitle)
        }
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
        // Immersive chat only shows the agent pane — leave it so the reader/note is visible.
        if layout == .immersiveConversation || layout == .immersiveWriting {
            if item.isNotebookNote {
                setLayout(.immersiveWriting)
            } else {
                setLayout(.immersiveReading)
            }
        }
        select(itemID: item.id)
        if item.isNotebookNote {
            showNotes = true
            focus(.notes)
            return true
        }
        showReader = true
        requestReaderPDFPage(
            item.kind == .pdf ? reference.pageIndex : nil,
            recordsLocation: item.kind == .pdf && reference.pageIndex != nil
        )
        let htmlTargetID = item.kind == .html
            ? reference.sectionLocationID
                ?? reference.sectionOrdinal.map { "html-heading-\(max($0 - 1, 0))" }
            : nil
        requestReaderHTMLLocation(
            id: htmlTargetID,
            title: item.kind == .html ? reference.sectionTitle : nil
        )
        focus(.reader)
        return true
    }

    /// Open a material/note citation from chat tags when the label is only a human title.
    @discardableResult
    func openAgentCitation(kind: String, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Prefer the structured "来源：" parser (handles section markers).
        if openSourceReference("来源：\(trimmed)") { return true }
        if openSourceReference(trimmed) { return true }
        // Fuzzy title match for Pi short labels like "货币金融学课程 HTML".
        guard let item = resolveStudyItem(matchingCitationTitle: trimmed) else { return false }
        if item.isNotebookNote || kind == "note" {
            if layout == .immersiveConversation || layout == .immersiveReading {
                setLayout(.immersiveWriting)
            }
            select(itemID: item.id)
            showNotes = true
            focus(.notes)
            return true
        }
        openCourseMaterial(item.id)
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
            showQuietInsight = false
        }
        if layout == .immersiveConversation {
            showReaderSearch = false
            readerSearch = ""
        }
        focus(nextFocus)
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
            hasSelection: selectionContext != nil || keepFloatingSelectionForAnswer,
            hasAnchor: selectionAnchor != nil,
            pinned: pinnedFloatingAgent,
            keepOpen: keepFloatingSelectionForAnswer
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
            // Overlay chat surfaces (bottom drawer / corner) were removed; only the
            // primary agent pane / immersive conversation counts as formal chat.
            return false
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
        showQuietInsight = false
        save()
    }

    func dismissFloatingSelectionAgent() {
        guard agentSurface == .selectionFloat || selectionContext != nil || pinnedFloatingAgent else { return }
        agentSurface = .hidden
        selectionContext = nil
        selectionAnchor = nil
        pinnedFloatingAgent = false
        keepFloatingSelectionForAnswer = false
        // Keep activeSelectionAskThreadID so hover can reopen; clear only the surface.
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
            readerLocationID: readerLocationID,
            readerLocationTitle: readerLocationTitle,
            readerPageIndex: readerPageIndex,
            focusedPane: focusedPane,
            threePaneOrder: normalizedThreePaneOrder
        )
    }

    private func applyNavigationSnapshot(_ snapshot: NavigationSnapshot) {
        invalidateAgentContext()
        isRestoringNavigation = true
        defer { isRestoringNavigation = false }
        selectedItemID = snapshot.selectedItemID
        activeNotebookItemID = snapshot.activeNotebookItemID
        layout = snapshot.layout
        showLibrary = snapshot.showLibrary
        showReader = snapshot.showReader
        showAgent = snapshot.showAgent
        showNotes = snapshot.showNotes
        agentSurface = snapshot.agentSurface == .selectionFloat ? .hidden : snapshot.agentSurface
        noteRenderMode = snapshot.noteRenderMode.visibleMode
        showReaderSearch = snapshot.showReaderSearch
        readerSearch = snapshot.readerSearch
        readerLocationID = snapshot.readerLocationID
        readerLocationTitle = snapshot.readerLocationTitle
        readerPageIndex = snapshot.readerPageIndex
        focusedPane = snapshot.focusedPane
        threePaneOrder = WorkspacePaneRole.normalized(snapshot.threePaneOrder)
        noteText = noteText(for: activeNoteItem)
        requestReaderPDFPage(
            selectedMaterialItem?.kind == .pdf ? snapshot.readerPageIndex : nil,
            recordsLocation: false
        )
        requestReaderHTMLLocation(
            id: selectedMaterialItem?.kind == .html ? snapshot.readerLocationID : nil,
            title: selectedMaterialItem?.kind == .html ? snapshot.readerLocationTitle : nil
        )
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        syncActiveStudySession()
        recordCurrentStudyLocation(incrementVisit: false)
        showQuietInsight = false
        clearUnpinnedFloatingSelection(keepContext: false)
        clearReaderSearchIfNeeded()
        save()
    }

    func insertMarkdownSnippet(_ markdown: String) {
        revealRichWritingSurface()
        noteEditorCommand = NoteEditorCommand(kind: .insertMarkdown, markdown: markdown)
        focus(.notes)
        save()
    }

    /// User rebinds from Settings → Shortcuts. Empty means all defaults.
    @Published private(set) var customShortcutOverrides: [AppShortcutID: AppShortcutChord] = AppShortcutCatalog.loadOverrides()

    func chord(for shortcut: AppShortcutID) -> AppShortcutChord {
        AppShortcutCatalog.chord(for: shortcut, overrides: customShortcutOverrides)
    }

    func setShortcut(_ id: AppShortcutID, chord: AppShortcutChord) {
        if chord == id.defaultChord {
            customShortcutOverrides.removeValue(forKey: id)
        } else {
            customShortcutOverrides[id] = chord
        }
        AppShortcutCatalog.saveOverrides(customShortcutOverrides)
        objectWillChange.send()
    }

    func resetShortcut(_ id: AppShortcutID) {
        customShortcutOverrides.removeValue(forKey: id)
        AppShortcutCatalog.saveOverrides(customShortcutOverrides)
        objectWillChange.send()
    }

    func resetAllShortcuts() {
        customShortcutOverrides = [:]
        AppShortcutCatalog.saveOverrides([:])
        objectWillChange.send()
    }

    func handleAppShortcut(_ event: NSEvent) -> Bool {
        guard let key = Self.shortcutKey(from: event) else { return false }
        return handleAppShortcut(key: key, modifiers: event.modifierFlags.intersection(Self.shortcutModifierMask))
    }

    func handleAppShortcut(key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let pressed = AppShortcutChord(key: key, modifiers: modifiers)
        if let action = AppShortcutCatalog.action(matching: pressed, overrides: customShortcutOverrides) {
            return performCustomizableShortcut(action)
        }

        // Non-user-facing chords stay hard-coded (layout / note mode / agent write).
        if modifiers == [.command, .option] {
            switch key {
            case "1":
                animateLayoutChange { setLayout(.documentAgentNotes) }
            case "2":
                animateLayoutChange { setLayout(.documentNotesSplit) }
            case "s":
                guard layout.isDocumentThreePane else { return false }
                animateLayoutChange { swapThreePaneSecondaryPanes() }
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
            case "j":
                guard layout.hasCollapsibleRightPane else { return false }
                animateLayoutChange { toggleRightPane() }
            case "return":
                if isAskingAgent {
                    cancelAgentRequest()
                } else {
                    guard !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                    askAgent()
                }
            default:
                return false
            }
            return true
        }

        return false
    }

    @discardableResult
    private func performCustomizableShortcut(_ id: AppShortcutID) -> Bool {
        switch id {
        case .commandPalette:
            animatePanelChange { commandPalettePresented.toggle() }
        case .toggleAppearance:
            animatePanelChange { toggleAppearanceMode() }
        case .navigateBack:
            guard canNavigateBack else { return false }
            animateLayoutChange { navigateBackInWorkspace() }
        case .navigateForward:
            guard canNavigateForward else { return false }
            animateLayoutChange { navigateForwardInWorkspace() }
        case .courseIndex:
            animateLayoutChange { toggleLibrary() }
        case .searchInMaterial:
            guard hasSelectedMaterial else { return false }
            animatePanelChange { revealReaderSearch() }
        case .focusLibrary:
            animateLayoutChange { focus(.library) }
        case .focusReader:
            animateLayoutChange { focus(.reader) }
        case .focusNotes:
            animateLayoutChange { focus(.notes) }
        case .focusChat:
            animateLayoutChange { focus(.agent) }
        case .immersiveReading:
            animateLayoutChange { setLayout(.immersiveReading) }
        case .immersiveChat:
            animateLayoutChange { setLayout(.immersiveConversation) }
        case .immersiveWriting:
            animateLayoutChange { setLayout(.immersiveWriting) }
        case .selectionPrompt:
            guard canUseSelectionAgentSurface else { return false }
            animatePanelChange { setAgentSurface(.selectionFloat) }
        case .hideChatOverlay:
            animatePanelChange { setAgentSurface(.hidden) }
        }
        return true
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

    func setAgentProviderID(_ provider: AgentProviderID) {
        guard agentProviderID != provider else { return }
        let previousDefault = agentProviderID.defaultModelHint
        agentProviderID = provider
        // Prefer profile-scoped key; fall back to legacy per-provider store.
        openAIAPIKey = resolveStoredAPIKey()
        // Switch model when empty or still on the previous provider's default hint.
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty || trimmedModel == previousDefault {
            modelName = provider.defaultModelHint
        }
        openAIKeyStatus = nil
        // Drop the old provider's catalog so the dropdown never briefly shows the
        // previous provider's models; the Store re-fetches right after (see S2).
        availableModels = []
        modelListStatus = .idle
        touchActiveAgentProfileMetadata()
        save()
        scheduleModelListRefresh()
    }

    func updateAgentBaseURL(_ value: String) {
        agentBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        touchActiveAgentProfileMetadata()
        save()
    }

    func updateModelName(_ value: String) {
        modelName = value
        touchActiveAgentProfileMetadata()
        save()
    }

    /// Assemble the concrete listing strategy for the active provider, combining the
    /// provider's protocol with the runtime base URL / Bedrock region.
    func resolvedModelListStrategy() -> ModelListStrategy? {
        switch agentProviderID.modelListProtocol {
        case .openAICompatible:
            let base = agentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = base.isEmpty ? (agentProviderID.defaultListBaseURL ?? "") : base
            guard !resolved.isEmpty else { return nil }
            return .openAICompatible(base: resolved)
        case .anthropic:
            return .anthropic
        case .gemini:
            return .gemini
        case .openRouterPublic:
            return .openRouterPublic
        case .azureOpenAI:
            let base = agentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty else { return nil }
            return .azureOpenAI(base: base)
        case .bedrock:
            return .bedrock(region: bedrockRegion)
        case .gitHubModels:
            return .gitHubModels
        case .codexSubscription:
            // OAuth token + account id from WeiBei-owned auth.json. If absent
            // (not signed in), return nil — the caller falls back to the built-in catalog.
            guard let credential = codexSubscriptionCredential() else { return nil }
            return .codexSubscription(token: credential.token, accountID: credential.accountID)
        case .unsupported:
            return nil
        }
    }

    /// Read the openai-codex OAuth token + accountId stored by WeiBei OAuth login.
    private func codexSubscriptionCredential() -> (token: String, accountID: String)? {
        WeiBeiAgentDataPaths.migrateHomePiAuthIfNeeded()
        let url = WeiBeiAgentDataPaths.piAuthJSON
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root["openai-codex"] as? [String: Any] else { return nil }
        let token = (entry["access"] as? String) ?? ""
        let accountID = (entry["accountId"] as? String) ?? ""
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (token, accountID)
    }

    /// Whether the active provider can enumerate models at all (vs. built-in only).
    var supportsRemoteModelList: Bool {
        agentProviderID.modelListProtocol != .unsupported
    }

    /// Fetch the model catalog for the active provider. Updates `availableModels` /
    /// `modelListStatus` on the main actor. Safe to call repeatedly; debounced by the UI.
    ///
    /// Codex subscription tries the live `codex/models` endpoint first, then falls back
    /// to the built-in catalog on any failure (best-effort listing, per upstream behavior).
    /// Fetch the model catalog for the active provider. Updates `availableModels` /
    /// `modelListStatus` on the main actor.
    ///
    /// Race-safe via `modelFetchGeneration`: each call stamps a generation, and a
    /// late-resolving fetch whose generation no longer matches is discarded so rapid
    /// provider/profile switches can't paint the wrong catalog (see S2).
    ///
    /// Cancellation of an in-flight **scheduled** fetch is owned by
    /// `scheduleModelListRefresh()` only. This method must NOT cancel `modelFetchTask`:
    /// the scheduler stores the Task that awaits `refreshModelList()`, so cancelling
    /// here would cancel ourselves mid-flight, trip `Task.isCancelled` after the
    /// network returns, discard a successful catalog, and leave `modelListStatus`
    /// stuck on `.loading` (OpenAI Codex subscription looked permanently broken).
    func refreshModelList() async {
        // No strategy (unsupported provider, or Codex subscription not signed in):
        // surface the built-in catalog immediately. These are synchronous resolutions
        // — stamp them with the current generation so an in-flight async fetch that
        // resolves later is still discarded.
        modelFetchGeneration &+= 1
        let myGen = modelFetchGeneration

        guard let strategy = resolvedModelListStrategy() else {
            guard myGen == modelFetchGeneration else { return }
            availableModels = fallbackModelCatalog
            modelListStatus = .builtin
            return
        }
        // Codex subscription doesn't use an API key — it carries its own OAuth token in
        // the strategy. OpenRouter public catalog needs no credential either.
        let needsAPIKey: Bool
        if case .codexSubscription = strategy { needsAPIKey = false }
        else if strategy == .openRouterPublic { needsAPIKey = false }
        else { needsAPIKey = true }

        if needsAPIKey, resolvedAPIKey() == nil {
            guard myGen == modelFetchGeneration else { return }
            availableModels = fallbackModelCatalog
            modelListStatus = .failed(ui("未配置密钥，无法列出模型。", "No API key configured; cannot list models."))
            return
        }
        let apiKey = resolvedAPIKey()?.key ?? ""
        guard myGen == modelFetchGeneration else { return }
        modelListStatus = .loading
        do {
            let models = try await modelListFetcher(strategy, apiKey)
            // Discard if a newer request superseded this one, or this scheduled task
            // was cancelled by a later scheduleModelListRefresh().
            guard myGen == modelFetchGeneration, !Task.isCancelled else { return }
            availableModels = models.isEmpty ? fallbackModelCatalog : models
            modelListStatus = .loaded
        } catch {
            guard myGen == modelFetchGeneration, !Task.isCancelled else { return }
            availableModels = fallbackModelCatalog
            modelListStatus = (agentProviderID == .openaiCodex) ? .builtin : .failed(error.localizedDescription)
        }
    }

    /// Fire-and-forget entry point for the Store's own state transitions
    /// (`setAgentProviderID`, `selectAgentCredentialProfile`). Makes the Store the
    /// single originator of model-list fetches instead of relying on UI onChange
    /// hooks that fired from three separate places (see S2).
    ///
    /// Cancels any previous scheduled fetch before starting a new one. Do not move
    /// that cancel into `refreshModelList` — see the self-cancel note there.
    func scheduleModelListRefresh() {
        modelFetchTask?.cancel()
        modelFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Yield once so the calling mutation (provider/profile/modelName swap)
            // has fully settled before we read state inside refreshModelList.
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self.refreshModelList()
        }
    }

    /// Built-in fallback shown before the first successful fetch, or when listing fails.
    private var fallbackModelCatalog: [String] {
        agentProviderID == .openaiCodex
            ? AgentModelListService.codexSubscriptionModels
            : agentProviderID.recommendedModels
    }


    func toggleAppearanceMode() {
        setAppearanceMode(appearanceMode.toggled)
    }

    func setAppearanceMode(_ mode: WeiBeiAppearanceMode) {
        guard appearanceMode != mode else {
            WeiBeiThemeRuntime.mode = mode
            return
        }
        // Runtime first so any body that re-reads WeiBeiTheme during the publish
        // already sees the target palette (critical for paper↔xuan / inkstone↔stele).
        // One unified transaction — call sites must not wrap this in a second
        // withAnimation, or chrome / paper / WebKit update out of phase.
        WeiBeiThemeRuntime.mode = mode
        let transaction = Transaction(animation: WeiBeiMotion.appearance)
        withTransaction(transaction) {
            appearanceMode = mode
        }
        NotificationCenter.default.post(name: WeiBeiThemeRuntime.didChangeNotification, object: mode)
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

    func setInterfaceLanguage(_ language: WeiBeiInterfaceLanguage) {
        guard interfaceLanguage != language else { return }
        interfaceLanguage = language
        floatingSelectionPrompt = ui("当前选区", "Current selection")
        _ = refreshStudyLocationReferenceTitles()
        save()
    }

    func saveOpenAIAPIKey() {
        do {
            let cleanedKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)
            // Keep legacy per-provider key for compatibility with older paths.
            try OpenAIAPIKeyStore.save(cleanedKey, provider: agentProviderID.piProviderName)
            try AgentCredentialProfileStore.saveAPIKey(cleanedKey, profileID: activeAgentProfileID)
            openAIAPIKey = cleanedKey
            touchActiveAgentProfileMetadata()
            openAIKeyStatus = cleanedKey.isEmpty
                ? ui("已清除密钥。", "Key cleared.")
                : ui("密钥已保存到当前配置。", "Key saved to the current profile.")
        } catch {
            openAIKeyStatus = ui("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
        }
    }

    func clearOpenAIAPIKey() {
        openAIAPIKey = ""
        saveOpenAIAPIKey()
    }

    func setAgentAuthMethod(_ method: AgentAuthMethod) {
        guard agentAuthMethod != method else { return }
        agentAuthMethod = method
        touchActiveAgentProfileMetadata()
    }

    func selectAgentCredentialProfile(_ id: UUID) {
        guard let profile = agentCredentialProfiles.first(where: { $0.id == id }) else { return }
        activeAgentProfileID = id
        AgentCredentialProfileStore.setActiveProfileID(id)
        agentProviderID = profile.provider
        agentAuthMethod = profile.authMethod
        modelName = profile.modelName
        agentBaseURL = profile.baseURL
        openAIAPIKey = resolveStoredAPIKey()
        openAIKeyStatus = nil
        // Clear the stale model list from the previous profile, then kick off a fresh
        // fetch from the Store itself (single originator — see S2). Previously this
        // only cleared and relied on the UI's onChange hooks to refetch, which raced
        // when several hooks fired at once.
        availableModels = []
        modelListStatus = .idle
        save()
        scheduleModelListRefresh()
    }

    @discardableResult
    func createAgentCredentialProfile(name: String? = nil) -> UUID {
        let cleanedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile = AgentCredentialProfile(
            name: cleanedName.isEmpty
                ? ui("配置 \(agentCredentialProfiles.count + 1)", "Profile \(agentCredentialProfiles.count + 1)")
                : cleanedName,
            provider: agentProviderID,
            authMethod: agentAuthMethod,
            modelName: modelName,
            baseURL: agentBaseURL
        )
        agentCredentialProfiles.append(profile)
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
        // Seed keychain from current key if any.
        if !openAIAPIKey.isEmpty {
            try? AgentCredentialProfileStore.saveAPIKey(openAIAPIKey, profileID: profile.id)
        }
        selectAgentCredentialProfile(profile.id)
        return profile.id
    }

    func renameActiveAgentCredentialProfile(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard let index = agentCredentialProfiles.firstIndex(where: { $0.id == activeAgentProfileID }) else { return }
        agentCredentialProfiles[index].name = cleaned
        agentCredentialProfiles[index].updatedAt = Date()
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
    }

    func deleteActiveAgentCredentialProfile() {
        guard agentCredentialProfiles.count > 1,
              let index = agentCredentialProfiles.firstIndex(where: { $0.id == activeAgentProfileID }) else { return }
        let removed = agentCredentialProfiles.remove(at: index)
        try? AgentCredentialProfileStore.deleteAPIKey(profileID: removed.id)
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
        if let next = agentCredentialProfiles.first {
            selectAgentCredentialProfile(next.id)
        }
    }

    func openAgentProviderConsole(login: Bool) {
        let url = login
            ? AgentProviderConsoleLinks.accountURL(for: agentProviderID)
                ?? AgentProviderConsoleLinks.loginURL(for: agentProviderID)
            : AgentProviderConsoleLinks.loginURL(for: agentProviderID)
        guard let url else {
            openAIKeyStatus = ui(
                "自定义提供商请在本页填写 Base URL 与密钥。",
                "For a custom provider, enter Base URL and API key on this page."
            )
            return
        }
        NSWorkspace.shared.open(url)
        openAIKeyStatus = ui(
            "已在浏览器打开提供商页面。登录后创建密钥并粘贴回来。",
            "Opened the provider page in your browser. Sign in, create a key, then paste it here."
        )
    }

    private func touchActiveAgentProfileMetadata() {
        guard let index = agentCredentialProfiles.firstIndex(where: { $0.id == activeAgentProfileID }) else {
            bootstrapAgentCredentialProfilesIfNeeded()
            return
        }
        agentCredentialProfiles[index].provider = agentProviderID
        agentCredentialProfiles[index].authMethod = agentAuthMethod
        agentCredentialProfiles[index].modelName = modelName
        agentCredentialProfiles[index].baseURL = agentBaseURL
        agentCredentialProfiles[index].updatedAt = Date()
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
        AgentCredentialProfileStore.setActiveProfileID(activeAgentProfileID)
    }

    private func bootstrapAgentCredentialProfilesIfNeeded() {
        if agentCredentialProfiles.isEmpty {
            let seeded = AgentCredentialProfile(
                name: ui("默认", "Default"),
                provider: agentProviderID,
                authMethod: agentAuthMethod,
                modelName: modelName,
                baseURL: agentBaseURL
            )
            agentCredentialProfiles = [seeded]
            activeAgentProfileID = seeded.id
            AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
            AgentCredentialProfileStore.setActiveProfileID(seeded.id)
            if !openAIAPIKey.isEmpty {
                try? AgentCredentialProfileStore.saveAPIKey(openAIAPIKey, profileID: seeded.id)
            }
        }
    }

    func importFilesFromPanel() {
        presentImportPanel(linkToActiveNote: false)
    }

    func prepareCourseFolderImportFromPanel() {
        let panel = NSOpenPanel()
        panel.title = ui("选择课程文件夹", "Choose a course folder")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK else {
            courseFolderImportDraft = nil
            return
        }

        let draft = makeCourseFolderImportDraft(rootURLs: panel.urls)
        guard !draft.markdownFiles.isEmpty else {
            importCourseFolder(draft, notePaths: [])
            courseFolderImportDraft = nil
            return
        }
        courseFolderImportDraft = draft
    }

    func importCourseFolder(_ draft: CourseFolderImportDraft, notePaths: Set<String>) {
        _ = importFiles(
            draft.rootURLs,
            selectsFirstImportedItem: false,
            markdownNotePaths: notePaths,
            reclassifiesExistingMarkdown: true
        )

        var memberships = courseMembershipIndex
        var selectedCourseID: UUID?
        for rootURL in draft.rootURLs {
            let standardizedRoot = rootURL.standardizedFileURL
            let itemIDs = Set(importedItems.compactMap { item -> String? in
                guard let itemURL = item.url?.standardizedFileURL,
                      Self.isFileURL(itemURL, inside: standardizedRoot) else { return nil }
                return item.id
            })
            guard !itemIDs.isEmpty else { continue }
            let courseID = ensureCourse(forImportRoot: standardizedRoot)
            memberships.assign(itemIDs: itemIDs, to: courseID)
            selectedCourseID = selectedCourseID ?? courseID
        }
        courseItemMemberships = memberships.values
        if let selectedCourseID {
            activeCourseID = selectedCourseID
        }
        save()
    }

    private func ensureCourse(forImportRoot rootURL: URL) -> UUID {
        let rootPath = rootURL.standardizedFileURL.path
        if let course = courses.first(where: { $0.sourceRootPath == rootPath }) {
            return course.id
        }

        let course = Course(
            title: rootURL.lastPathComponent.isEmpty
                ? ui("未命名课程", "Untitled Course")
                : rootURL.lastPathComponent,
            colorIndex: nextCourseColorIndex(),
            sourceRootPath: rootPath
        )
        courses.append(course)
        return course.id
    }

    nonisolated private static func isFileURL(_ itemURL: URL, inside rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let itemPath = itemURL.standardizedFileURL.path
        return itemPath == rootPath || itemPath.hasPrefix(rootPath + "/")
    }

    @discardableResult
    func retryWorkspaceSave() -> Bool {
        save()
    }

    func importCourseMaterialsFromPanel() {
        presentImportPanel(
            linkToActiveNote: false,
            selectsFirstImportedItem: false,
            reclassifiesExistingMarkdown: true,
            assigningToCourseID: activeCourseID,
            panelTitle: ui("选择课程资料或文件夹", "Choose course materials or a folder")
        )
    }

    func importCourseNotesFromPanel() {
        presentImportPanel(
            linkToActiveNote: false,
            selectsFirstImportedItem: false,
            markdownAsNotes: true,
            markdownOnly: true,
            reclassifiesExistingMarkdown: true,
            assigningToCourseID: activeCourseID,
            panelTitle: ui("选择 Markdown 笔记或文件夹", "Choose Markdown notes or a folder")
        )
    }

    func importAndLinkSourcesFromPanel() {
        presentImportPanel(linkToActiveNote: true)
    }

    private func presentImportPanel(
        linkToActiveNote: Bool,
        selectsFirstImportedItem: Bool = true,
        markdownAsNotes: Bool = false,
        markdownOnly: Bool = false,
        reclassifiesExistingMarkdown: Bool = false,
        assigningToCourseID: UUID? = nil,
        panelTitle: String? = nil
    ) {
        let panel = NSOpenPanel()
        panel.title = panelTitle ?? ui("选择学习资料或课程文件夹", "Choose study materials or a course folder")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = markdownOnly
            ? [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
            : [.pdf, .html, .plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]

        guard panel.runModal() == .OK else { return }
        let targetNoteID = linkToActiveNote ? activeNotebookItemID : nil
        let selectedItems = importFiles(
            panel.urls,
            selectsFirstImportedItem: selectsFirstImportedItem,
            markdownAsNotes: markdownAsNotes,
            markdownOnly: markdownOnly,
            reclassifiesExistingMarkdown: reclassifiesExistingMarkdown
        )
        if let assigningToCourseID {
            let importedPaths = Set(panel.urls
                .flatMap(Self.supportedCourseFiles(at:))
                .map { $0.standardizedFileURL.path })
            let importedItemIDs = Set(importedItems.compactMap { item -> String? in
                guard let path = item.url?.standardizedFileURL.path,
                      importedPaths.contains(path) else { return nil }
                return item.id
            })
            assignItemIDs(importedItemIDs, to: assigningToCourseID)
        }
        if let targetNoteID, targetNoteID == activeNotebookItemID {
            setLinkedSourceIDsForActiveNote(
                Set(linkedSourceIDsForActiveNote).union(selectedItems.map(\.id))
            )
        }
    }

    @discardableResult
    func importFiles(
        _ urls: [URL],
        selectsFirstImportedItem: Bool = true,
        markdownAsNotes: Bool = false,
        markdownOnly: Bool = false,
        markdownNotePaths: Set<String>? = nil,
        reclassifiesExistingMarkdown: Bool = false
    ) -> [StudyItem] {
        let supportedURLs = urls
            .flatMap(Self.supportedCourseFiles(at:))
            .reduce(into: [URL]()) { result, url in
                if !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    result.append(url)
                }
            }
        let expandedURLs = markdownOnly
            ? supportedURLs.filter(Self.isMarkdownFile)
            : supportedURLs
        let isNotebookNote: (URL) -> Bool = { url in
            guard Self.isMarkdownFile(url) else { return false }
            return markdownNotePaths?.contains(url.path) ?? markdownAsNotes
        }

        if reclassifiesExistingMarkdown || markdownNotePaths != nil {
            persistCurrentNote()
        }
        var roleChanged = false
        var importedIDs: [String] = []
        var didChangeItems = false
        for url in expandedURLs {
            let identity = importedFileIdentityResolver(url)
            let bookmarkData = identity.flatMap { _ in Self.makeImportedFileBookmark(for: url) }
            if let identity {
                for index in importedItems.indices
                where importedItems[index].urlPath == url.path
                    && importedItems[index].importedFileIdentity != nil
                    && importedItems[index].importedFileIdentity != identity {
                    importedItems[index].importedFileLastKnownPath = url.path
                    importedItems[index].urlPath = nil
                    didChangeItems = true
                }
            }
            let identityMatchingIndex = importedItems.firstIndex { item in
                if let identity {
                    return item.importedFileIdentity == identity
                }
                return item.importedFileIdentity == nil && item.urlPath == url.path
            }
            let legacyPathMatchingIndex = identity == nil ? nil : importedItems.firstIndex { item in
                item.id.hasPrefix("file:")
                    && item.importedFileIdentity == nil
                    && (item.urlPath == url.path || item.importedFileLastKnownPath == url.path)
            }
            let matchingIndex = identityMatchingIndex ?? legacyPathMatchingIndex

            if let matchingIndex {
                if identity != nil, importedItems[matchingIndex].id.hasPrefix("file:") {
                    let oldID = importedItems[matchingIndex].id
                    let newID = Self.makeImportedItemID()
                    importedItems[matchingIndex].id = newID
                    replaceItemIDEverywhere(oldID, with: newID)
                    didChangeItems = true
                }
                importedIDs.append(importedItems[matchingIndex].id)
                let nextTitle = url.deletingPathExtension().lastPathComponent
                let nextSubtitle = url.lastPathComponent
                let nextKind = StudyItemKind.detect(from: url)
                let nextRole = isNotebookNote(url)
                if importedItems[matchingIndex].isNotebookNote != nextRole {
                    roleChanged = true
                }
                if importedItems[matchingIndex].urlPath != url.path
                    || importedItems[matchingIndex].title != nextTitle
                    || importedItems[matchingIndex].subtitle != nextSubtitle
                    || importedItems[matchingIndex].kind != nextKind
                    || importedItems[matchingIndex].isNotebookNote != nextRole
                    || importedItems[matchingIndex].importedFileIdentity != identity
                    || importedItems[matchingIndex].importedFileBookmarkData != bookmarkData
                    || importedItems[matchingIndex].importedFileLastKnownPath != url.path {
                    importedItems[matchingIndex].urlPath = url.path
                    importedItems[matchingIndex].title = nextTitle
                    importedItems[matchingIndex].subtitle = nextSubtitle
                    importedItems[matchingIndex].kind = nextKind
                    importedItems[matchingIndex].isNotebookNote = nextRole
                    importedItems[matchingIndex].importedFileIdentity = identity
                    importedItems[matchingIndex].importedFileBookmarkData = bookmarkData
                        ?? importedItems[matchingIndex].importedFileBookmarkData
                    importedItems[matchingIndex].importedFileLastKnownPath = url.path
                    didChangeItems = true
                }
                continue
            }

            let item = StudyItem(
                id: Self.makeImportedItemID(),
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: StudyItemKind.detect(from: url),
                urlPath: url.path,
                importedFileIdentity: identity,
                importedFileBookmarkData: bookmarkData,
                importedFileLastKnownPath: url.path,
                isSample: false,
                isNotebookNote: isNotebookNote(url)
            )
            importedItems.append(item)
            importedIDs.append(item.id)
            didChangeItems = true
        }

        if roleChanged {
            if let selectedItemID,
               importedItems.first(where: { $0.id == selectedItemID })?.isNotebookNote == true {
                self.selectedItemID = courseMaterials.first?.id ?? sampleItems.first?.id
                readerLocationTitle = selectedMaterialItem.map(displayTitle)
                restoreCurrentStudyLocation()
            }
            if let activeNotebookItemID,
               importedItems.first(where: { $0.id == activeNotebookItemID })?.isNotebookNote == false {
                self.activeNotebookItemID = courseNotebookItems.first?.id
                noteText = noteText(for: activeNoteItem)
            }
            _ = sanitizeNoteSourceLinks()
            invalidateAgentContext()
        }
        courseDocumentSearchIndex.synchronize(allItems)
        let importedIDSet = Set(importedIDs)
        let selectedItems = importedItems.filter { importedIDSet.contains($0.id) && !$0.isNotebookNote }
        if selectsFirstImportedItem, let first = selectedItems.first {
            select(itemID: first.id)
        } else if didChangeItems {
            save()
        }
        return selectedItems
    }

    nonisolated private static func resolveImportedFileIdentity(at url: URL) -> ImportedFileIdentity? {
        var fileStat = Darwin.stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return Darwin.lstat(path, &fileStat) == 0
        }) else {
            return nil
        }
        return ImportedFileIdentity(
            volumeID: UInt64(fileStat.st_dev),
            fileID: UInt64(fileStat.st_ino),
            birthTimeSeconds: Int64(fileStat.st_birthtimespec.tv_sec),
            birthTimeNanoseconds: Int64(fileStat.st_birthtimespec.tv_nsec)
        )
    }

    nonisolated private static func makeImportedFileBookmark(for url: URL) -> Data? {
        let resourceKeys: Set<URLResourceKey> = [
            .fileResourceIdentifierKey,
            .volumeIdentifierKey,
            .creationDateKey,
        ]
        if let scopedBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: resourceKeys,
            relativeTo: nil
        ) {
            return scopedBookmark
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: resourceKeys,
            relativeTo: nil
        )
    }

    nonisolated private static func resolveImportedFileBookmark(_ data: Data) -> ResolvedImportedFileBookmark? {
        var isStale = false
        if let scopedURL = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return ResolvedImportedFileBookmark(url: scopedURL.standardizedFileURL, isStale: isStale)
        }
        isStale = false
        guard let plainURL = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return ResolvedImportedFileBookmark(url: plainURL.standardizedFileURL, isStale: isStale)
    }

    nonisolated private static func makeImportedItemID() -> String {
        "imported:\(UUID().uuidString.lowercased())"
    }

    private func makeCourseFolderImportDraft(rootURLs: [URL]) -> CourseFolderImportDraft {
        let supportedFiles = rootURLs
            .flatMap(Self.supportedCourseFiles(at:))
            .reduce(into: [URL]()) { result, url in
                if !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    result.append(url)
                }
            }
        let markdownFiles = supportedFiles.filter(Self.isMarkdownFile)
        return CourseFolderImportDraft(
            rootURLs: rootURLs,
            markdownFiles: markdownFiles,
            notePaths: Set(markdownFiles.filter(Self.defaultMarkdownIsNotebookNote).map(\.path)),
            automaticMaterialCount: supportedFiles.count - markdownFiles.count
        )
    }

    private static func supportedCourseFiles(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            return isSupportedCourseFile(url) ? [url] : []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard isSupportedCourseFile(fileURL),
                  (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append(fileURL)
            if files.count == 500 { break }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func isSupportedCourseFile(_ url: URL) -> Bool {
        ["pdf", "html", "htm", "md", "markdown", "txt", "text"]
            .contains(url.pathExtension.lowercased())
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    private static func defaultMarkdownIsNotebookNote(_ url: URL) -> Bool {
        let description = (url.deletingPathExtension().lastPathComponent + " "
            + url.deletingLastPathComponent().pathComponents.suffix(3).joined(separator: " ")).lowercased()
        return ["笔记", "note", "notes", "notebook"].contains { description.contains($0) }
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
        guard let initialIndex = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let oldTitle = displayTitle(for: importedItems[initialIndex])

        if let stagedNoteDraft, stagedNoteDraft.itemID == itemID {
            self.stagedNoteDraft = nil
            updateNote(stagedNoteDraft.value, for: itemID)
        }
        flushPendingNotePersistence(for: itemID)
        persistCurrentNote()
        if pendingNoteWritesByItemID[itemID] != nil {
            noteFileError = ui(
                "这份笔记还有待写草稿或外部冲突；两份内容都已保留，处理完成前不会重命名文件。",
                "This note still has a pending draft or external conflict. Both versions were kept, and the file will not be renamed until it is resolved."
            )
            save()
            return
        }
        guard let index = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let resolution = resolveTrackedImportedFile(at: index)
        guard let oldURL = resolution.url else {
            noteFileError = ui(
                "找不到这份笔记的当前位置，最新编辑已保留，未执行重命名。",
                "The current note location could not be found. The latest edit was retained and the note was not renamed."
            )
            save()
            return
        }
        let oldItem = importedItems[index]
        let oldID = oldItem.id
        let wasActiveNotebook = activeNotebookItemID == oldID
        let newURL = renamedNotebookURL(in: oldURL.deletingLastPathComponent(), title: title, currentURL: oldURL)
        let newTitle = newURL.deletingPathExtension().lastPathComponent
        let sourceMarkdown: String
        do {
            sourceMarkdown = wasActiveNotebook ? noteText : try notebookMarkdownReader(oldURL)
        } catch {
            noteFileError = ui(
                "无法重命名笔记：无法读取原 Markdown，文件和课程关系均未改动。",
                "Could not rename the note because the original Markdown could not be read. The file and course relationships were not changed."
            )
            save()
            return
        }
        let retitledMarkdown = retitledMarkdown(sourceMarkdown, from: oldTitle, to: newTitle)
        guard let originalContentDigest = noteBackingContentDigestsByItemID[oldID]
                ?? Self.noteContentDigest(at: oldURL) else {
            noteFileError = ui(
                "无法重命名笔记：无法确认原 Markdown 内容，文件和课程关系均未改动。",
                "Could not rename the note because the original Markdown contents could not be verified. The file and course relationships were not changed."
            )
            save()
            return
        }
        let sourceMarkdownDigest = Self.noteContentDigest(Data(sourceMarkdown.utf8))
        let willRewriteMarkdown = retitledMarkdown != sourceMarkdown
        let expectedOutputDigest = willRewriteMarkdown
            ? Self.noteContentDigest(Data(retitledMarkdown.utf8))
            : originalContentDigest
        let originalIdentity = oldItem.importedFileIdentity
            ?? importedFileIdentityResolver(oldURL)
        let replacementItemID = oldID.hasPrefix("file:") && originalIdentity != nil
            ? Self.makeImportedItemID()
            : (oldID.hasPrefix("file:") ? "file:\(newURL.path)" : oldID)
        var journalOldItem = oldItem
        journalOldItem.importedFileIdentity = originalIdentity
        let renameJournal = PendingNotebookRenameJournal(
            oldItem: journalOldItem,
            replacementItemID: replacementItemID,
            oldPath: oldURL.path,
            newPath: newURL.path,
            newTitle: newTitle,
            sourceMarkdown: sourceMarkdown,
            retitledMarkdown: retitledMarkdown,
            originalContentDigest: originalContentDigest,
            retitledContentDigest: expectedOutputDigest
        )
        guard save() else {
            noteFileError = ui(
                "无法重命名笔记：当前课程状态尚未安全保存，文件和关系均未改动。",
                "Could not rename the note because the current course state was not safely saved. The file and relationships were not changed."
            )
            return
        }
        removePendingNotebookRenameJournal()
        do {
            try writePendingNotebookRenameJournal(renameJournal)
        } catch {
            noteFileError = ui(
                "无法重命名笔记：无法建立崩溃恢复记录，文件和课程关系均未改动。",
                "Could not rename the note because a crash-recovery record could not be created. The file and course relationships were not changed."
            )
            save()
            return
        }

        var movedFile = false
        var verifiedApplicationOutput = false

        do {
            if oldURL.path != newURL.path {
                try notebookFileMover(oldURL, newURL)
                movedFile = true
            }
            let movedIdentity = importedFileIdentityResolver(newURL)
            let identityChanged = !oldID.hasPrefix("file:")
                && (originalIdentity == nil || movedIdentity != originalIdentity)
            let movedContentDigest = Self.noteContentDigest(at: newURL)
            let contentChanged = movedContentDigest != originalContentDigest
            if identityChanged || contentChanged {
                throw NSError(
                    domain: "WeiBei.ImportedFileIdentity",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: ui(
                            "文件身份或内容在重命名期间发生变化，操作已中止。",
                            "The file identity or content changed during rename, so the operation was stopped."
                        ),
                    ]
                )
            }

            var coordinatedIdentity: ImportedFileIdentity?
            var coordinatedDigest: String?
            var coordinationError: NSError?
            var operationError: Error?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(
                writingItemAt: newURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    guard importedFileIdentityResolver(coordinatedURL) == movedIdentity,
                          Self.noteContentDigest(at: coordinatedURL) == originalContentDigest else {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: ui(
                                    "写入前检测到文件被外部修改，操作已中止。",
                                    "The file changed externally before writing, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    if willRewriteMarkdown {
                        try notebookMarkdownWriter(retitledMarkdown, coordinatedURL)
                    }
                    let identityBeforeRead = importedFileIdentityResolver(coordinatedURL)
                    let outputData = try Data(contentsOf: coordinatedURL)
                    let identityAfterRead = importedFileIdentityResolver(coordinatedURL)
                    let outputDigest = Self.noteContentDigest(outputData)
                    guard identityBeforeRead == identityAfterRead,
                          outputDigest == expectedOutputDigest else {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 3,
                            userInfo: [
                                NSLocalizedDescriptionKey: ui(
                                    "写入后文件内容或身份不一致，操作已中止。",
                                    "The file contents or identity did not match after writing, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    if !oldID.hasPrefix("file:"), identityAfterRead == nil {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 4,
                            userInfo: [
                                NSLocalizedDescriptionKey: ui(
                                    "写入标题后无法确认文件身份，操作已中止。",
                                    "The file identity could not be confirmed after writing the title, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    coordinatedIdentity = identityAfterRead
                    coordinatedDigest = outputDigest
                    verifiedApplicationOutput = true
                } catch {
                    operationError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
            guard let finalContentDigest = coordinatedDigest,
                  importedFileIdentityResolver(newURL) == coordinatedIdentity,
                  Self.noteContentDigest(at: newURL) == finalContentDigest else {
                throw NSError(
                    domain: "WeiBei.ImportedFileIdentity",
                    code: 5,
                    userInfo: [
                        NSLocalizedDescriptionKey: ui(
                            "提交前检测到文件再次变化，操作已中止。",
                            "The file changed again before the rename could be committed, so the operation was stopped."
                        ),
                    ]
                )
            }
            var renamedItem = oldItem
            renamedItem.id = replacementItemID
            renamedItem.title = newTitle
            renamedItem.subtitle = newURL.lastPathComponent
            renamedItem.urlPath = newURL.path
            renamedItem.importedFileIdentity = coordinatedIdentity ?? originalIdentity
            renamedItem.importedFileBookmarkData = Self.makeImportedFileBookmark(for: newURL)
                ?? oldItem.importedFileBookmarkData
            renamedItem.importedFileLastKnownPath = newURL.path
            importedItems[index] = renamedItem
            replaceItemIDEverywhere(oldID, with: replacementItemID)
            if wasActiveNotebook {
                noteText = retitledMarkdown
            }
            if let cached = notesByItemID[replacementItemID] {
                notesByItemID[replacementItemID] = self.retitledMarkdown(cached, from: oldTitle, to: newTitle)
            }
            noteBackingContentDigestsByItemID[replacementItemID] = finalContentDigest
            courseDocumentSearchIndex.synchronize(allItems)
            guard save() else {
                notebookRenameDraft = NotebookRenameDraft(itemID: replacementItemID, title: newTitle)
                noteFileError = ui(
                    "文件已重命名，但课程状态尚未写入磁盘；恢复记录已保留，重启后会自动接回。",
                    "The file was renamed, but the course state has not been saved to disk. A recovery record was retained so it can be reconnected after restart."
                )
                return
            }
            removePendingNotebookRenameJournal()
            notebookRenameDraft = nil
            noteFileError = nil
            showTransientNoteStatus(ui("已重命名为：\(newURL.lastPathComponent)", "Renamed to: \(newURL.lastPathComponent)"))
        } catch {
            var restoredOldPath = oldURL.path == newURL.path
            if movedFile {
                do {
                    try notebookFileMover(newURL, oldURL)
                    restoredOldPath = true
                } catch {
                    restoredOldPath = false
                }
            } else if oldURL.path != newURL.path {
                let currentOldIdentity = importedFileIdentityResolver(oldURL)
                restoredOldPath = Self.noteContentDigest(at: oldURL) == originalContentDigest
                    && (originalIdentity == nil || currentOldIdentity == originalIdentity)
            }

            if restoredOldPath {
                var restoredIdentity = importedFileIdentityResolver(oldURL)
                var restoredDigest = Self.noteContentDigest(at: oldURL)
                let recoveredApplicationOutput = willRewriteMarkdown
                    && verifiedApplicationOutput
                    && restoredDigest == expectedOutputDigest
                if recoveredApplicationOutput, willRewriteMarkdown {
                    do {
                        try notebookMarkdownWriter(sourceMarkdown, oldURL)
                        restoredIdentity = importedFileIdentityResolver(oldURL)
                        restoredDigest = Self.noteContentDigest(at: oldURL)
                    } catch {
                        restoredIdentity = importedFileIdentityResolver(oldURL)
                        restoredDigest = Self.noteContentDigest(at: oldURL)
                    }
                }
                let restoredOriginalGeneration = restoredDigest == originalContentDigest
                    && (originalIdentity == nil || restoredIdentity == originalIdentity)
                let restoredKnownApplicationCopy = recoveredApplicationOutput
                    && restoredDigest == sourceMarkdownDigest
                let restoredFileIsTrusted = restoredOriginalGeneration || restoredKnownApplicationCopy
                if restoredFileIsTrusted {
                    importedItems[index] = oldItem
                    importedItems[index].urlPath = oldURL.path
                    importedItems[index].importedFileLastKnownPath = oldURL.path
                    importedItems[index].importedFileIdentity = restoredIdentity
                    importedItems[index].importedFileBookmarkData = Self.makeImportedFileBookmark(for: oldURL)
                        ?? oldItem.importedFileBookmarkData
                    noteBackingContentDigestsByItemID[oldID] = restoredDigest
                } else {
                    importedItems[index] = oldItem
                    importedItems[index].urlPath = nil
                    importedItems[index].importedFileLastKnownPath = oldURL.path
                    notesByItemID[oldID] = sourceMarkdown
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                        baselineContentDigest: originalContentDigest
                    )
                    if wasActiveNotebook {
                        noteText = sourceMarkdown
                    }
                }
            } else if FileManager.default.fileExists(atPath: newURL.path) {
                let currentIdentity = importedFileIdentityResolver(newURL)
                let currentDigest = Self.noteContentDigest(at: newURL)
                let currentFileIsMovedOriginal = currentDigest == originalContentDigest
                    && (originalIdentity == nil || currentIdentity == originalIdentity)
                let currentFileIsKnownApplicationOutput = willRewriteMarkdown
                    && verifiedApplicationOutput
                    && currentDigest == expectedOutputDigest
                guard currentFileIsMovedOriginal || currentFileIsKnownApplicationOutput else {
                    importedItems[index] = oldItem
                    importedItems[index].urlPath = nil
                    importedItems[index].importedFileLastKnownPath = oldURL.path
                    notesByItemID[oldID] = sourceMarkdown
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                        baselineContentDigest: originalContentDigest
                    )
                    if wasActiveNotebook {
                        noteText = sourceMarkdown
                    }
                    courseDocumentSearchIndex.synchronize(allItems)
                    let savedRecovery = save()
                    if savedRecovery { removePendingNotebookRenameJournal() }
                    noteFileError = ui(
                        "无法重命名笔记：\(error.localizedDescription) 原关系和最新正文已保留，请重新定位文件。",
                        "Could not rename the note: \(error.localizedDescription) The original relationships and latest text were retained; relocate the file to continue."
                    )
                    return
                }
                importedItems[index].title = newTitle
                importedItems[index].subtitle = newURL.lastPathComponent
                importedItems[index].urlPath = newURL.path
                importedItems[index].importedFileIdentity = currentIdentity
                importedItems[index].importedFileBookmarkData = Self.makeImportedFileBookmark(for: newURL)
                    ?? oldItem.importedFileBookmarkData
                importedItems[index].importedFileLastKnownPath = newURL.path
                noteBackingContentDigestsByItemID[oldID] = currentDigest
                if currentFileIsKnownApplicationOutput, wasActiveNotebook {
                    noteText = retitledMarkdown
                }
            } else {
                importedItems[index] = oldItem
                importedItems[index].urlPath = nil
                importedItems[index].importedFileLastKnownPath = oldURL.path
                notesByItemID[oldID] = sourceMarkdown
                pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                    baselineContentDigest: originalContentDigest
                )
                if wasActiveNotebook {
                    noteText = sourceMarkdown
                }
            }
            courseDocumentSearchIndex.synchronize(allItems)
            let recovery = restoredOldPath
                ? ui("文件已恢复到原路径。", "The file was restored to its original path.")
                : ui("原关系和最新正文已保留，请重新定位文件。", "The original relationships and latest text were retained; relocate the file to continue.")
            noteFileError = ui(
                "无法重命名笔记：\(error.localizedDescription) \(recovery)",
                "Could not rename the note: \(error.localizedDescription) \(recovery)"
            )
            let savedRecovery = save()
            if savedRecovery { removePendingNotebookRenameJournal() }
        }
    }

    func openOrCreateWikiNote(title rawTitle: String) {
        let title = WikiLink.targetTitle(from: rawTitle)
        guard !title.isEmpty else { return }

        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)
        let fileName = "\(safeFileStem(title)).md"
        let url = notesDirectory.appendingPathComponent(fileName)
        let existingIdentity = importedFileIdentityResolver(url)

        if let index = importedItems.firstIndex(where: { item in
            if let existingIdentity {
                return item.importedFileIdentity == existingIdentity
            }
            return item.importedFileIdentity == nil && item.urlPath == url.path
        }) {
            importedItems[index].isNotebookNote = true
            removeLinksWhereSourceItemID(importedItems[index].id)
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
            let identity = importedFileIdentityResolver(url)
            if let identity {
                for index in importedItems.indices
                where importedItems[index].urlPath == url.path
                    && importedItems[index].importedFileIdentity != nil
                    && importedItems[index].importedFileIdentity != identity {
                    importedItems[index].importedFileLastKnownPath = url.path
                    importedItems[index].urlPath = nil
                }
            }

            let item = StudyItem(
                id: Self.makeImportedItemID(),
                title: title,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                importedFileIdentity: identity,
                importedFileBookmarkData: identity.flatMap { _ in Self.makeImportedFileBookmark(for: url) },
                importedFileLastKnownPath: url.path,
                isSample: false,
                isNotebookNote: true
            )
            if !importedItems.contains(where: { $0.urlPath == url.path }) {
                importedItems.append(item)
            }
            courseDocumentSearchIndex.synchronize(allItems)
            select(itemID: item.id)
            showTransientNoteStatus(ui("已创建双链笔记：\(url.lastPathComponent)", "Created wiki note: \(url.lastPathComponent)"))
        } catch {
            noteFileError = ui("无法创建双链笔记：\(error.localizedDescription)", "Could not create wiki note: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func createNotebookNote(seed: NotebookNoteSeed, title rawTitle: String? = nil) -> StudyItem? {
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
            return nil
        }

        persistCurrentNote()
        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let url = nextNotebookNoteURL(in: notesDirectory, title: title)
            var item = StudyItem(
                id: Self.makeImportedItemID(),
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                isSample: false,
                isNotebookNote: true
            )
            let markdown = defaultNotebookNote(title: item.title, sourceItem: sourceItem)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            noteBackingContentDigestsByItemID[item.id] = Self.noteContentDigest(Data(markdown.utf8))
            item.importedFileIdentity = importedFileIdentityResolver(url)
            item.importedFileBookmarkData = item.importedFileIdentity.flatMap { _ in
                Self.makeImportedFileBookmark(for: url)
            }
            item.importedFileLastKnownPath = url.path
            importedItems.append(item)
            if let activeCourseID,
               courses.contains(where: { $0.id == activeCourseID }) {
                var memberships = courseMembershipIndex
                memberships.assign(itemIDs: [item.id], to: activeCourseID)
                courseItemMemberships = memberships.values
            }
            courseDocumentSearchIndex.synchronize(allItems)
            if let sourceItem {
                addNoteSourceLink(noteItemID: item.id, sourceItemID: sourceItem.id)
            }
            invalidateAgentContext()
            activeNotebookItemID = item.id
            noteText = markdown
            revealRichWritingSurface()
            focus(.notes)
            save()
            let status = sourceItem == nil
                ? ui("已新建空白笔记：\(url.lastPathComponent)", "Created blank note: \(url.lastPathComponent)")
                : ui("已为当前资料新建笔记：\(url.lastPathComponent)", "Created note from current material: \(url.lastPathComponent)")
            showTransientNoteStatus(status)
            return item
        } catch {
            noteFileError = ui("无法创建笔记：\(error.localizedDescription)", "Could not create note: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    private func openExistingNotebookNote(for material: StudyItem) -> Bool {
        guard let item = existingNotebookNote(for: material) else { return false }
        invalidateAgentContext()
        activeNotebookItemID = item.id
        noteText = noteText(for: item)
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
        invalidateAgentContext()
        persistCurrentNote()
        importedItems[index].isNotebookNote = true
        removeLinksWhereSourceItemID(importedItems[index].id)
        activeNotebookItemID = importedItems[index].id
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
            reference = ui("来源：\(currentSourceReferenceTitle)", "Source: \(currentSourceReferenceTitle)")
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
        // Multi-pane and immersive both get the selection capsule when there is an anchor.
        // (Previously suppressed whenever the chat column was open — that made multi-pane
        // look "broken" vs immersive reading.)
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
        return currentSourceReferenceTitle
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
    private func resolveStudyItem(matchingCitationTitle rawTitle: String) -> StudyItem? {
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

    private func titlesLooselyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizeCitationTitle(lhs)
        let b = normalizeCitationTitle(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        // Strip common kind suffixes the model often appends.
        let strippedA = a.replacingOccurrences(of: #"\s+(html|pdf|md|markdown|text)$"#, with: "", options: .regularExpression)
        let strippedB = b.replacingOccurrences(of: #"\s+(html|pdf|md|markdown|text)$"#, with: "", options: .regularExpression)
        return strippedA == strippedB || strippedA == b || a == strippedB
    }

    private func normalizeCitationTitle(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func addNoteSourceLink(noteItemID: String, sourceItemID: String) {
        guard noteItemID != sourceItemID,
              !noteSourceLinks.contains(where: {
                  $0.noteItemID == noteItemID && $0.sourceItemID == sourceItemID
              }) else { return }
        noteSourceLinks.append(NoteSourceLink(noteItemID: noteItemID, sourceItemID: sourceItemID))
    }

    private func removeLinksWhereSourceItemID(_ sourceItemID: String) {
        let previousCount = noteSourceLinks.count
        noteSourceLinks.removeAll { $0.sourceItemID == sourceItemID }
        if noteSourceLinks.count != previousCount {
            invalidateAgentContext()
        }
    }

    private func migrateNoteSourceLinksFromMarkdown() {
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
    private func sanitizeNoteSourceLinks() -> Bool {
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
    private func sanitizeCourseLibrary() -> Bool {
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

    private func nextCourseColorIndex() -> Int {
        let used = Set(courses.map(\.colorIndex))
        return (0..<8).first(where: { !used.contains($0) }) ?? (courses.count % 8)
    }

    @discardableResult
    private func refreshStudyLocationReferenceTitles() -> Bool {
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

    private func makeCourseContext(query: String) async throws -> CourseContextBuildResult {
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

    private func makeLearningContext() -> StudyAgentLearningContext {
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

    private func sessionContinuitySummary(for session: StudySession) -> String {
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

    private func applyLearningUpdate(
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

    private static func normalizedMemoryText(_ text: String) -> String {
        text
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined()
    }

    private static func currentTurnEvidenceMatches(_ evidence: String, question: String) -> Bool {
        StudyAgentCurrentTurnEvidence.matches(evidence, question: question)
    }

    private static func resolutionEvidenceMatches(_ evidence: String, question: String) -> Bool {
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

    private func persistSelectionAskThreads() {
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

    func runVerificationScenarioIfNeeded() async {
        guard !didRunVerificationScenario else { return }
        guard Self.environmentValue("WEIBEI_SUPPRESS_ACTIVATION") == "1" else { return }
        let richAnswerReplayPath = Self.environmentValue("WEIBEI_VERIFY_RICH_ANSWER_REPLAY")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !richAnswerReplayPath.isEmpty {
            didRunVerificationScenario = true
            recordVerificationStage("recognized:rich-answer-replay")
            configureRichAnswerReplayVerification(path: richAnswerReplayPath)
            return
        }
        let scenario = Self.environmentValue("WEIBEI_VERIFY_SCENARIO")
        let agentVerificationFlow = AgentVerificationScenarioPolicy.flow(for: scenario)
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
        guard agentVerificationFlow != nil
            || RichAnswerVerificationFixture.supports(scenario)
            || scenario == "immersive-conversation-flow"
            || scenario == "notebook-creation-flow"
            || scenario == "pure-writing-flow"
            || scenario == "linked-sources-flow"
            || scenario == "pane-layout-stability-flow"
            || scenario == "content-rail-dormant-preview"
            || scenario == "content-rail-activation-preview"
            || scenario == "pane-toggle-continuity-flow"
            || scenario == "pane-reorder-width-flow"
            || scenario == "reader-scroll-persistence-flow"
            || scenario == "course-workspace-overview-flow"
            || scenario == "course-workspace-workflow-flow"
            || scenario == "course-index-navigation-flow"
            || scenario == "loading-indicator-samples"
            || emptyWorkspaceScenarios.contains(scenario) else { return }
        didRunVerificationScenario = true
        recordVerificationStage("recognized:\(scenario)")
        if emptyWorkspaceScenarios.contains(scenario) {
            configureEmptyWorkspaceVerificationScenario(scenario)
            return
        }
        if scenario == "loading-indicator-samples" {
            // Shows product V3 「行文进行中」thinking indicator in the agent stream.
            let appearanceRaw = Self.environmentValue("WEIBEI_VERIFY_APPEARANCE").lowercased()
            if appearanceRaw == "ink" || appearanceRaw == "inkstone" || appearanceRaw == "dark" {
                appearanceMode = .inkstone
            } else {
                appearanceMode = .paper
            }
            let languageRaw = Self.environmentValue("WEIBEI_VERIFY_LANGUAGE").lowercased()
            if languageRaw == "en" || languageRaw == "english" {
                interfaceLanguage = .english
            } else {
                interfaceLanguage = .chinese
            }
            layout = .immersiveConversation
            showLibrary = false
            showReader = false
            showAgent = true
            showNotes = false
            agentSurface = .hidden
            isAskingAgent = true
            agentActivityText = ui("正在读取上下文", "Reading context")
            agentStreamingText = ""
            messages = []
            showLoadingIndicatorSamples = false
            recordVerificationStage("loading-samples")
            recordVerificationStage("completed")
            return
        }
        if scenario == "content-rail-dormant-preview" || scenario == "content-rail-activation-preview" {
            layout = .documentAgentNotes
            showLibrary = false
            showReader = true
            showAgent = true
            showNotes = true
            agentSurface = .hidden
            select(itemID: "sample-html")
            updateNote(ui("# 收起轨道验收\n\n悬浮简介必须越过收起边界显示。\n", "# Dormant rail check\n\nThe hover preview must cross the dormant pane boundary.\n"))
            save()
            return
        }
        if RichAnswerVerificationFixture.supports(scenario) {
            configureRichAnswerPreviewVerification(scenario: scenario)
            return
        }
        if scenario == "course-workspace-overview-flow"
            || scenario == "course-workspace-workflow-flow"
            || scenario == "course-index-navigation-flow" {
            await runCourseWorkspaceVerification(scenario)
            return
        }
        if scenario == "pane-toggle-continuity-flow" {
            await runPaneToggleContinuityVerification()
            return
        }
        if scenario == "pane-layout-stability-flow" {
            await runPaneLayoutStabilityVerification()
            return
        }
        if scenario == "pane-reorder-width-flow" {
            await runPaneReorderWidthVerification()
            return
        }
        if scenario == "reader-scroll-persistence-flow" {
            await runReaderScrollPersistenceVerification()
            return
        }
        layout = scenario == "immersive-conversation-flow" ? .immersiveConversation : .documentAgentNotes
        if scenario == "notebook-creation-flow" {
            layout = .immersiveWriting
        }
        if scenario == "pure-writing-flow" || scenario == "linked-sources-flow" {
            layout = .immersiveWriting
        }
        showLibrary = scenario != "immersive-conversation-flow"
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        if scenario == "pure-writing-flow" || scenario == "linked-sources-flow" {
            createNotebookNote(
                seed: .currentMaterial(sampleItems[0]),
                title: ui("多资料研究笔记", "Multi-source research note")
            )
            setLinkedSourceIDsForActiveNote(["sample-html", "sample-pdf"])
            select(itemID: "sample-pdf")
            showLibrary = false
            linkedSourcesPresented = scenario == "linked-sources-flow"
            if scenario == "linked-sources-flow" {
                noteRenderMode = .source
            }
            save()
            return
        }
        if agentVerificationFlow?.waitsForReaderContext == true {
            await waitForReaderContextToSettle()
        }
        if scenario == "notebook-creation-flow" {
            promptCreateBlankNotebookNote()
            return
        }
        if agentVerificationFlow == .piCourseMemory {
            updateReaderLocationTitle(ui("实际利率", "Real interest rates"))
            updateNote(ui("# 课程学习记录\n\n", "# Course study record\n\n"))
            recordVerificationStage("course-memory-context-prepared")
            agentDraft = ui(
                "我上次学到哪？课程里哪份其他资料也提到利率，为什么相关？我还不懂名义利率和实际利率的区别，请记住这个困惑，并给出可点击来源。",
                "Where did I stop last time? Which other course material discusses interest rates, and why is it related? I still do not understand nominal versus real rates. Remember that confusion and give me a clickable source."
            )
            await askAgentAndWait()
            let answer = messages.last?.text ?? ""
            let recordedConfusion = latestAgentLearningUpdate?.entries.contains { $0.kind == .confusion } == true
            let hasJumpReference = answer.contains(ui("来源：", "Source:"))
            let previousItemID = selectedItemID
            let previousLearningUpdate = latestAgentLearningUpdate
            let openedJumpReference = openSourceReference(answer)
            if openedJumpReference, let previousItemID {
                select(itemID: previousItemID)
                latestAgentLearningUpdate = previousLearningUpdate
                lastAgentReplyContextRevision = agentContextRevision
            }
            recordVerificationStage("course-memory-reply:\(messages.last?.backend?.rawValue ?? "none")")
            recordVerificationStage("course-memory-update:\(recordedConfusion)")
            recordVerificationStage("course-memory-jump:\(hasJumpReference && openedJumpReference)")
            if messages.last?.backend == .pi,
               recordedConfusion,
               hasJumpReference,
               openedJumpReference {
                let markerURL = storageURL.deletingLastPathComponent().appendingPathComponent("pi-course-memory-verified.txt")
                try? "PI backend completed course memory and wayfinding\n".write(to: markerURL, atomically: true, encoding: .utf8)
            }
            recordVerificationStage("completed")
            return
        }
        let verificationNoteSeed = ui("# 视觉验收笔记\n\n", "# Visual verification note\n\n")
        updateNote(verificationNoteSeed)
        updateSelection(
            ui("利率是资金使用价格的表达。", "An interest rate is the price paid for using funds."),
            source: .document,
            ownerTitle: currentSourceReferenceTitle
        )
        recordVerificationStage("context-prepared")
        agentDraft = ui("解释选区，并整理成可以写入笔记的要点。", "Explain the selection and turn it into note-ready points.")
        await askAgentAndWait()
        recordVerificationStage("reply:\(messages.last?.backend?.rawValue ?? "none")")
        if messages.last?.backend == nil, let message = messages.last?.text {
            recordVerificationStage("failure:\(String(message.prefix(500)))")
        }
        applyLastAgentAnswerToNote()
        if agentVerificationFlow == .piLearning {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if messages.last?.backend == .pi, noteText.count > verificationNoteSeed.count {
                let markerURL = storageURL.deletingLastPathComponent().appendingPathComponent("pi-agent-verified.txt")
                try? "PI backend completed the packaged learning flow and persisted its note proposal\n"
                    .write(to: markerURL, atomically: true, encoding: .utf8)
            }
        }
        recordVerificationStage("completed")
    }

    private func configureRichAnswerPreviewVerification(scenario: String) {
        let presentation = RichAnswerVerificationFixture.presentation(for: scenario)
        let verifiesInlinePane = scenario == RichAnswerVerificationFixture.inlineExtendedOpenUIProgramScenario
        layout = verifiesInlinePane ? .documentAgentNotes : .immersiveConversation
        showLibrary = false
        showReader = verifiesInlinePane
        showAgent = true
        showNotes = false
        agentSurface = .hidden
        select(itemID: "sample-html")
        messages = []
        appendAgentMessage(
            AgentMessage(
                role: .user,
                text: RichAnswerVerificationFixture.question(for: scenario),
                source: "货币金融学课程 HTML"
            )
        )
        appendAgentMessage(
            AgentMessage(
                role: .assistant,
                text: presentation.narrative,
                source: "货币金融学课程 HTML",
                backend: .pi,
                richAnswer: presentation
            )
        )
        let familySummary = presentation.scenes.map(\.family.rawValue).joined(separator: ",")
        let verificationSummary = [
            "scenario=\(scenario)",
            "mode=\(presentation.mode.rawValue)",
            "scenes=\(presentation.scenes.count)",
            "families=\(familySummary)",
            "diagnostics=\(presentation.diagnostics.count)",
        ].joined(separator: "\n") + "\n"
        let markerURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("rich-answer-verified.txt")
        try? verificationSummary.write(to: markerURL, atomically: true, encoding: .utf8)
        recordVerificationStage("rich-answer:\(presentation.mode.rawValue):\(presentation.scenes.count):\(presentation.diagnostics.count)")
        focus(.agent)
        recordVerificationStage("completed")
    }

    private func configureRichAnswerReplayVerification(path: String) {
        let baseURL = storageURL.deletingLastPathComponent()
        do {
            let artifactURL = RichAnswerReplayArtifact.url(fromEnvironmentValue: path, relativeTo: baseURL)
            let artifact = try RichAnswerReplayArtifact.load(from: artifactURL)
            let materialItem = try installRichAnswerReplayMaterial(artifact, baseURL: baseURL)
            layout = .documentAgentNotes
            showLibrary = false
            showReader = true
            showAgent = true
            showNotes = false
            agentSurface = .hidden
            select(itemID: materialItem.id)
            messages = []
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            agentStreamingText = ""
            agentActivityText = "真实回放：\(artifact.status)"
            appendAgentMessage(
                AgentMessage(
                    role: .user,
                    text: artifact.question,
                    source: materialItem.title
                )
            )
            appendAgentMessage(
                AgentMessage(
                    role: .assistant,
                    text: artifact.visibleAssistantText,
                    source: materialItem.title,
                    backend: artifact.backend,
                    richAnswer: artifact.presentationForDisplay
                )
            )
            let verificationSummary = [
                "artifact=\(artifact.artifactURL.path)",
                "case=\(artifact.caseID)",
                "status=\(artifact.status)",
                "backend=\(artifact.backend?.rawValue ?? "none")",
                "materialItemID=\(artifact.materialItemID)",
                "materialKind=\(artifact.materialKind)",
                "verificationAssetID=\(artifact.verificationAssetID ?? "none")",
                "sourceFingerprint=\(artifact.sourceFingerprint ?? "none")",
                "verificationAssetFingerprint=\(artifact.verificationAssetFingerprint ?? "none")",
                "richAnswer=\(artifact.richAnswer?.mode.rawValue ?? "none")",
                "scenes=\(artifact.richAnswer?.scenes.count ?? 0)",
                "tools=\(artifact.toolTrace.joined(separator: ","))",
            ].joined(separator: "\n") + "\n"
            try verificationSummary.write(
                to: baseURL.appendingPathComponent("rich-answer-replay-verified.txt"),
                atomically: true,
                encoding: .utf8
            )
            recordVerificationStage("rich-answer-replay:\(artifact.status):\(artifact.richAnswer?.mode.rawValue ?? "none"):\(artifact.richAnswer?.scenes.count ?? 0)")
        } catch {
            configureRichAnswerReplayFailure(path: path, error: error, baseURL: baseURL)
        }
        recordVerificationStage("completed")
    }

    private func installRichAnswerReplayMaterial(
        _ artifact: RichAnswerReplayArtifact,
        baseURL: URL
    ) throws -> StudyItem {
        let directory = baseURL.appendingPathComponent("RichAnswerReplay", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let materialURL = try richAnswerReplayMaterialURL(for: artifact, directory: directory)
        let item = StudyItem(
            id: artifact.materialItemID,
            title: artifact.materialTitle,
            subtitle: "真实富回答回放材料 · \(artifact.materialKind)",
            kind: richAnswerReplayStudyItemKind(for: artifact.materialKind),
            urlPath: materialURL.path,
            isSample: false
        )
        importedItems.removeAll {
            $0.id == item.id
                || $0.id == "rich-answer-replay-material"
                || $0.urlPath == materialURL.path
        }
        importedItems.append(item)
        courseDocumentSearchIndex.synchronize(allItems)
        save()
        return item
    }

    private func richAnswerReplayMaterialURL(
        for artifact: RichAnswerReplayArtifact,
        directory: URL
    ) throws -> URL {
        let normalizedKind = artifact.materialKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isImageMaterial = normalizedKind == "image"
        let verificationAssetID = artifact.verificationAssetID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let assetID = verificationAssetID, !assetID.isEmpty {
            guard isImageMaterial else {
                throw RichAnswerReplayMaterialInstallError.unexpectedVerificationAssetID(
                    assetID,
                    artifact.materialKind
                )
            }
            try RichAnswerVerificationAssets.validateBundledResources()
            guard let url = RichAnswerVerificationAssets.url(for: assetID) else {
                throw RichAnswerReplayMaterialInstallError.missingBundledVerificationAsset(assetID)
            }
            return url
        }
        if isImageMaterial {
            throw RichAnswerReplayMaterialInstallError.missingVerificationAssetID(artifact.materialItemID)
        }
        if artifact.referencesCurrentMaterialAsset {
            throw RichAnswerReplayMaterialInstallError.missingReferencedAsset(artifact.materialItemID)
        }

        if normalizedKind == "html" {
            let escapedTitle = artifact.materialTitle
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let paragraphs = artifact.materialBody
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map {
                    $0.replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { "<p>\($0)</p>" }
                .joined(separator: "\n")
            let escapedBody = paragraphs.isEmpty
                ? "<p>当前材料没有可显示的正文。</p>"
                : paragraphs
            let materialURL = directory.appendingPathComponent("material.html")
            let document = """
            <!doctype html>
            <html lang="zh-CN">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <style>
                html, body { margin: 0; background: transparent; }
                main { box-sizing: border-box; max-width: 760px; margin: 0 auto; padding: 34px 38px 64px; }
                h1 { margin: 0 0 24px; font-family: "Songti SC", "STSong", serif; font-size: 28px; line-height: 1.35; font-weight: 600; }
                p { margin: 0 0 14px; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; font-size: 16px; line-height: 1.82; }
              </style>
            </head>
            <body><main data-weibei-paper-surface><h1>\(escapedTitle)</h1>\(escapedBody)</main></body>
            </html>
            """
            try document.write(to: materialURL, atomically: true, encoding: .utf8)
            return materialURL
        }

        let body = """
        \(artifact.materialTitle)

        \(artifact.materialBody)
        """
        let materialURL = directory.appendingPathComponent("material.txt")
        try body.write(to: materialURL, atomically: true, encoding: .utf8)
        return materialURL
    }

    private func richAnswerReplayStudyItemKind(for materialKind: String) -> StudyItemKind {
        switch materialKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "image":
            .html
        case "html":
            .html
        case "pdf":
            .pdf
        case "markdown", "md":
            .markdown
        default:
            .text
        }
    }

    private func configureRichAnswerReplayFailure(path: String, error: Error, baseURL: URL) {
        layout = .immersiveConversation
        showLibrary = false
        showReader = false
        showAgent = true
        showNotes = false
        agentSurface = .hidden
        messages = []
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        agentStreamingText = ""
        agentActivityText = "真实回放失败"
        let question = "回放富回答留档：\(path)"
        let answer = """
        富回答真实回放失败，已显式显示错误，避免空白误判。

        路径：\(path)
        错误：\(error.localizedDescription)
        """
        appendAgentMessage(AgentMessage(role: .user, text: question, source: "富回答回放"))
        appendAgentMessage(AgentMessage(role: .assistant, text: answer, source: "富回答回放"))
        try? answer.write(
            to: baseURL.appendingPathComponent("rich-answer-replay-error.txt"),
            atomically: true,
            encoding: .utf8
        )
        recordVerificationStage("rich-answer-replay-failure:\(error.localizedDescription)")
    }

    private enum RichAnswerReplayMaterialInstallError: LocalizedError {
        case missingVerificationAssetID(String)
        case missingBundledVerificationAsset(String)
        case missingReferencedAsset(String)
        case unexpectedVerificationAssetID(String, String)

        var errorDescription: String? {
            switch self {
            case let .missingVerificationAssetID(materialItemID):
                return "富回答图片回放缺少 verificationAssetID，材料 \(materialItemID) 不显示空 Canvas。"
            case let .missingBundledVerificationAsset(assetID):
                return "富回答图片回放找不到已校验的打包图片资源：\(assetID)。"
            case let .missingReferencedAsset(assetID):
                return "富回答回放引用了材料资产 \(assetID)，但没有可解析的真实图片资源。"
            case let .unexpectedVerificationAssetID(assetID, materialKind):
                return "富回答回放记录了图片资源 \(assetID)，但材料类型是 \(materialKind)，已停止安装。"
            }
        }
    }

    private func runCourseWorkspaceVerification(_ scenario: String) async {
        let fixtureDirectory = storageURL.deletingLastPathComponent()
            .appendingPathComponent("CourseWorkspaceFixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

        func fixtureURL(_ name: String, extension fileExtension: String) -> URL {
            fixtureDirectory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        }

        let materialAURL = fixtureURL("利率基础", extension: "html")
        let materialBURL = fixtureURL("货币政策", extension: "md")
        let materialCURL = fixtureURL("复习问题", extension: "txt")
        let noteAURL = fixtureURL("利率研究笔记", extension: "md")
        let noteBURL = fixtureURL("政策工具笔记", extension: "md")
        let noteCURL = fixtureURL("期末复习笔记", extension: "md")
        try? "<h1>利率基础</h1><p>名义利率与实际利率。</p>".write(to: materialAURL, atomically: true, encoding: .utf8)
        try? "# 货币政策\n\n公开市场操作与政策利率。\n".write(to: materialBURL, atomically: true, encoding: .utf8)
        try? "复习：比较名义利率与实际利率。\n".write(to: materialCURL, atomically: true, encoding: .utf8)
        try? "# 利率研究笔记\n\n## 核心要点\n".write(to: noteAURL, atomically: true, encoding: .utf8)
        try? "# 政策工具笔记\n\n## 摘录\n".write(to: noteBURL, atomically: true, encoding: .utf8)
        try? "# 期末复习笔记\n\n## 待追问\n".write(to: noteCURL, atomically: true, encoding: .utf8)

        let selectionBeforeFolderImport = selectedItemID
        let folderImportDraft = makeCourseFolderImportDraft(rootURLs: [fixtureDirectory])
        importCourseFolder(folderImportDraft, notePaths: folderImportDraft.notePaths)
        let importedFolderItems = importedItems.filter {
            $0.url?.deletingLastPathComponent().standardizedFileURL.path == fixtureDirectory.standardizedFileURL.path
        }
        let importedFolderRoles = Dictionary(uniqueKeysWithValues: importedFolderItems.map {
            ($0.subtitle, $0.isNotebookNote)
        })
        let folderItemCountPassed = importedFolderItems.count == 6
        let folderMaterialDefaultPassed = (importedFolderRoles[materialBURL.lastPathComponent] ?? true) == false
        let folderNoteDefaultsPassed = [noteAURL, noteBURL, noteCURL].allSatisfy { url in
            (importedFolderRoles[url.lastPathComponent] ?? false) == true
        }
        let folderCountSummaryPassed = folderImportDraft.automaticMaterialCount
            + folderImportDraft.markdownFiles.count
            - folderImportDraft.notePaths.count == 3
        let initialFolderClassificationPassed = folderItemCountPassed
            && folderMaterialDefaultPassed
            && folderNoteDefaultsPassed
            && folderCountSummaryPassed
        _ = importFiles(
            [materialBURL],
            selectsFirstImportedItem: false,
            markdownAsNotes: true,
            markdownOnly: true,
            reclassifiesExistingMarkdown: true
        )
        let correctedExistingFileToNote = importedItems.first(where: { $0.urlPath == materialBURL.path })?.isNotebookNote == true
        _ = importFiles(
            [materialBURL],
            selectsFirstImportedItem: false,
            reclassifiesExistingMarkdown: true
        )
        let correctedExistingFileBackToMaterial = importedItems.first(where: { $0.urlPath == materialBURL.path })?.isNotebookNote == false
        let importClassificationPassed = initialFolderClassificationPassed
            && correctedExistingFileToNote
            && correctedExistingFileBackToMaterial
            && selectedItemID == selectionBeforeFolderImport
        let importSelectionPreserved = selectedItemID == selectionBeforeFolderImport

        let materialA = StudyItem(id: "course-material-a", title: "利率基础", subtitle: materialAURL.lastPathComponent, kind: .html, urlPath: materialAURL.path, isSample: false)
        let materialB = StudyItem(id: "course-material-b", title: "货币政策", subtitle: materialBURL.lastPathComponent, kind: .markdown, urlPath: materialBURL.path, isSample: false)
        let materialC = StudyItem(id: "course-material-c", title: "复习问题", subtitle: materialCURL.lastPathComponent, kind: .text, urlPath: materialCURL.path, isSample: false)
        let noteA = StudyItem(id: "course-note-a", title: "利率研究笔记", subtitle: noteAURL.lastPathComponent, kind: .markdown, urlPath: noteAURL.path, isSample: false, isNotebookNote: true)
        let noteB = StudyItem(id: "course-note-b", title: "政策工具笔记", subtitle: noteBURL.lastPathComponent, kind: .markdown, urlPath: noteBURL.path, isSample: false, isNotebookNote: true)
        let noteC = StudyItem(id: "course-note-c", title: "期末复习笔记", subtitle: noteCURL.lastPathComponent, kind: .markdown, urlPath: noteCURL.path, isSample: false, isNotebookNote: true)

        importedItems = [materialA, materialB, materialC, noteA, noteB, noteC]
        notesByItemID = [
            noteA.id: "# 利率研究笔记\n\n## 核心要点\n",
            noteB.id: "# 政策工具笔记\n\n## 摘录\n",
            noteC.id: "# 期末复习笔记\n\n## 待追问\n",
        ]
        selectedItemID = materialA.id
        activeNotebookItemID = noteA.id
        noteText = notesByItemID[noteA.id] ?? ""
        noteSourceLinks = [
            NoteSourceLink(noteItemID: noteA.id, sourceItemID: materialA.id),
            NoteSourceLink(noteItemID: noteA.id, sourceItemID: materialB.id),
            NoteSourceLink(noteItemID: noteB.id, sourceItemID: materialB.id),
        ]
        let courseA = Course(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "货币金融学",
            colorIndex: 0
        )
        let courseB = Course(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "经济思想史",
            colorIndex: 1
        )
        courses = [courseA, courseB]
        var verificationMemberships = CourseItemMemberships()
        verificationMemberships.assign(
            itemIDs: Set([materialA.id, materialB.id, noteA.id, noteB.id]),
            to: courseA.id
        )
        verificationMemberships.assign(
            itemIDs: Set([materialB.id, materialC.id, noteB.id, noteC.id]),
            to: courseB.id
        )
        courseItemMemberships = verificationMemberships.values
        activeCourseID = courseA.id
        studyLocationsByItemID = [
            materialA.id: StudyLocation(
                itemID: materialA.id,
                itemTitle: materialA.title,
                locationID: "html-heading-1",
                locationTitle: "名义利率与实际利率",
                lastStudiedAt: Date().addingTimeInterval(-1_800),
                visitCount: 3
            )
        ]
        let activeSession = StudySession(
            title: "利率为什么会变化",
            messages: [
                AgentMessage(role: .user, text: "名义利率和实际利率有什么区别？", source: materialA.title, backend: .pi),
                AgentMessage(role: .assistant, text: "实际利率会扣除通货膨胀的影响。", source: materialA.title, backend: .pi),
            ],
            summary: "比较名义利率与实际利率，并联系货币政策工具。",
            focusItemIDs: [materialA.id, materialB.id, noteA.id],
            flow: StudyFlowState(phase: .note, suggestedNext: ["把利率公式整理到复习笔记", "用一道例题检验区别"]),
            updatedAt: Date().addingTimeInterval(-900)
        )
        let emptySession = StudySession(title: "新学习会话")
        studySessions = [activeSession, emptySession]
        activeStudySessionID = activeSession.id
        messages = activeSession.messages
        learningMemoryEntries = [
            LearningMemoryEntry(
                kind: .confusion,
                text: "仍不确定通货膨胀预期如何传导到名义利率。",
                evidence: "用户在当前会话中明确提出",
                origin: .userStatement,
                sessionID: activeSession.id
            ),
            LearningMemoryEntry(
                kind: .nextStep,
                text: "完成名义利率与实际利率的对照例题。",
                evidence: "当前会话建议",
                origin: .agentInference,
                sessionID: activeSession.id
            ),
        ]
        layout = .documentAgentNotes
        showLibrary = false
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        courseDocumentSearchIndex.synchronize(allItems)
        save()

        if scenario == "course-index-navigation-flow" {
            let unassignedURL = fixtureURL("跨课程阅读清单", extension: "txt")
            try? "待归类：金融史、政策工具与复习问题。\n".write(to: unassignedURL, atomically: true, encoding: .utf8)
            importedItems.append(
                StudyItem(
                    id: "course-material-unassigned",
                    title: "跨课程阅读清单",
                    subtitle: unassignedURL.lastPathComponent,
                    kind: .text,
                    urlPath: unassignedURL.path,
                    isSample: false
                )
            )
            activeCourseID = nil
            showLibrary = true
            courseWorkspacePresented = false
            courseDocumentSearchIndex.synchronize(allItems)
            save()
            recordVerificationStage("completed")
            return
        }

        let noteCountBeforeInvalidCreation = courseNotebookItems.count
        let invalidNoteID = createCourseNotebookNote(title: "   ")
        let invalidNoteCreationPassed = invalidNoteID == nil
            && courseNotebookItems.count == noteCountBeforeInvalidCreation
            && noteFileError?.isEmpty == false
        noteFileError = nil

        let initialSummary = courseWorkspaceSummary
        let initialRelations = NoteSourceRelations(links: noteSourceLinks)
        if scenario == "course-workspace-overview-flow" {
            let requestedPage = Self.environmentValue("WEIBEI_VERIFY_COURSE_PAGE")
            if requestedPage == "notes" {
                presentCourseWorkspace(.notes, selecting: noteA.id)
            } else if requestedPage == "materials" || requestedPage == "relations-large" {
                if requestedPage == "relations-large" {
                    activeCourseID = nil
                }
                presentCourseWorkspace(.materials, selecting: materialB.id)
            } else if requestedPage == "sessions" {
                presentCourseWorkspace(.sessions, selecting: activeSession.id.uuidString)
            } else {
                presentCourseWorkspace(.relations)
            }
            writeCourseWorkspaceVerificationReport(
                name: "course-workspace-overview-report.json",
                payload: [
                    "result": initialSummary.materialCount == 3
                        && initialSummary.noteCount == 3
                        && initialSummary.explicitLinkCount == 3
                        && initialSummary.readingPositionCount == 1
                        && initialSummary.unlinkedMaterialCount == 1
                        && initialSummary.unlinkedNoteCount == 1
                        && initialSummary.studySessionCount == 1
                        && initialSummary.unresolvedConfusionCount == 1
                        && importClassificationPassed ? "pass" : "fail",
                    "importClassificationPassed": importClassificationPassed,
                    "invalidNoteCreationPassed": invalidNoteCreationPassed,
                    "initialFolderClassificationPassed": initialFolderClassificationPassed,
                    "correctedExistingFileToNote": correctedExistingFileToNote,
                    "correctedExistingFileBackToMaterial": correctedExistingFileBackToMaterial,
                    "importSelectionPreserved": importSelectionPreserved,
                    "importedFolderItemCount": importedFolderItems.count,
                    "importedFolderRoles": importedFolderRoles,
                    "folderMaterialDefaultPassed": folderMaterialDefaultPassed,
                    "folderNoteDefaultsPassed": folderNoteDefaultsPassed,
                    "folderCountSummaryPassed": folderCountSummaryPassed,
                    "materialCount": initialSummary.materialCount,
                    "noteCount": initialSummary.noteCount,
                    "explicitLinkCount": initialSummary.explicitLinkCount,
                    "readingPositionCount": initialSummary.readingPositionCount,
                    "unlinkedMaterialIDs": courseMaterialsWithoutNoteLinks.map(\.id).sorted(),
                    "unlinkedNoteIDs": courseNotesWithoutSourceLinks.map(\.id).sorted(),
                    "studySessionCount": initialSummary.studySessionCount,
                    "unresolvedConfusionCount": initialSummary.unresolvedConfusionCount,
                    "currentMaterialID": selectedItemID ?? "",
                    "currentNoteID": activeNotebookItemID ?? "",
                    "courseWorkspacePresented": courseWorkspacePresented,
                ]
            )
            if requestedPage == "relations-large" {
                let courseC = Course(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    title: "金融史专题",
                    colorIndex: 2
                )
                let courseD = Course(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    title: "计量练习",
                    colorIndex: 3
                )
                courses.append(contentsOf: [courseC, courseD])

                var expandedMemberships = CourseItemMemberships(values: courseItemMemberships)
                var expandedRelations = NoteSourceRelations(links: noteSourceLinks)
                for index in 1...7 {
                    let materialURL = fixtureURL("扩展资料 \(index)", extension: "txt")
                    let noteURL = fixtureURL("扩展笔记 \(index)", extension: "md")
                    try? "第 \(index) 份课程材料，包含利率、政策与历史线索。\n".write(to: materialURL, atomically: true, encoding: .utf8)
                    try? "# 扩展笔记 \(index)\n\n## 课程线索\n".write(to: noteURL, atomically: true, encoding: .utf8)
                    let material = StudyItem(
                        id: "course-large-material-\(index)",
                        title: ["债券定价", "通胀预期", "央行沟通", "危机史料", "政策冲击", "回归练习", "期末框架"][index - 1],
                        subtitle: materialURL.lastPathComponent,
                        kind: .text,
                        urlPath: materialURL.path,
                        isSample: false
                    )
                    let note = StudyItem(
                        id: "course-large-note-\(index)",
                        title: ["期限结构札记", "费雪效应", "政策信号", "危机比较", "识别假设", "模型结果", "总复习图谱"][index - 1],
                        subtitle: noteURL.lastPathComponent,
                        kind: .markdown,
                        urlPath: noteURL.path,
                        isSample: false,
                        isNotebookNote: true
                    )
                    importedItems.append(contentsOf: [material, note])
                    notesByItemID[note.id] = "# \(note.title)\n\n## 课程线索\n"
                    let primaryCourseID = index <= 3 ? courseC.id : courseD.id
                    expandedMemberships.assign(itemIDs: Set([material.id, note.id]), to: primaryCourseID)
                    if index == 3 || index == 4 {
                        expandedMemberships.assign(itemIDs: Set([material.id, note.id]), to: courseB.id)
                    }
                    let nextNoteID = "course-large-note-\(index == 7 ? 1 : index + 1)"
                    expandedRelations.replaceNotes(
                        for: material.id,
                        noteItemIDs: Set([note.id, nextNoteID])
                    )
                }
                courseItemMemberships = expandedMemberships.values
                noteSourceLinks = expandedRelations.links
                activeCourseID = nil
                courseDocumentSearchIndex.synchronize(allItems)
                save()
            }
            recordVerificationStage("completed")
            return
        }

        func verifyCourseOverlayContinuity(itemID: String) async -> (passed: Bool, makeCount: Int, dismantleCount: Int) {
            select(itemID: itemID)
            try? await Task.sleep(nanoseconds: 900_000_000)
            let baselineLayout = layout
            let baselineMaterialID = selectedItemID
            let baselineNoteID = activeNotebookItemID
            let baselineNoteText = noteText
            let baselineMessages = messages
            let baselineOrder = threePaneOrder
            let baselineLocation = selectedItemID.flatMap { studyLocationsByItemID[$0] }
            PaneToggleContinuityVerifier.beginMeasurement()
            presentCourseWorkspace(.relations)
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismissCourseWorkspace()
            try? await Task.sleep(nanoseconds: 500_000_000)
            let makeCount = PaneToggleContinuityVerifier.webReaderMakeCount
                + PaneToggleContinuityVerifier.pdfReaderMakeCount
                + PaneToggleContinuityVerifier.noteEditorMakeCount
            let dismantleCount = PaneToggleContinuityVerifier.webReaderDismantleCount
                + PaneToggleContinuityVerifier.pdfReaderDismantleCount
                + PaneToggleContinuityVerifier.noteEditorDismantleCount
            let passed = layout == baselineLayout
                && selectedItemID == baselineMaterialID
                && activeNotebookItemID == baselineNoteID
                && noteText == baselineNoteText
                && messages == baselineMessages
                && threePaneOrder == baselineOrder
                && selectedItemID.flatMap { studyLocationsByItemID[$0] } == baselineLocation
                && makeCount == 0
                && dismantleCount == 0
            PaneToggleContinuityVerifier.endMeasurement()
            return (passed, makeCount, dismantleCount)
        }

        let htmlContinuity = await verifyCourseOverlayContinuity(itemID: materialA.id)
        let pdfContinuity = await verifyCourseOverlayContinuity(itemID: "sample-pdf")
        let continuityPassed = htmlContinuity.passed && pdfContinuity.passed
        let paneMakeCount = htmlContinuity.makeCount + pdfContinuity.makeCount
        let paneDismantleCount = htmlContinuity.dismantleCount + pdfContinuity.dismantleCount
        select(itemID: materialA.id)

        setLinkedSourceIDs([materialA.id], for: noteA.id)
        setLinkedSourceIDs([materialB.id, materialC.id], for: noteC.id)
        let editedRelations = NoteSourceRelations(links: noteSourceLinks)

        presentCourseWorkspace(.materials, selecting: materialC.id)
        openCourseMaterial(materialC.id)
        let materialNavigationPassed = selectedItemID == materialC.id
            && activeNotebookItemID == noteA.id
            && !editedRelations.isLinked(noteItemID: noteA.id, sourceItemID: materialC.id)

        presentCourseWorkspace(.notes, selecting: noteC.id)
        openCourseNote(noteC.id)
        let noteNavigationPassed = selectedItemID == materialC.id
            && activeNotebookItemID == noteC.id

        flushPendingNotePersistence()
        save()
        let diskData = try? Data(contentsOf: storageURL)
        let diskSnapshot = diskData.flatMap { try? JSONDecoder().decode(PersistedWorkspace.self, from: $0) }
        let diskRelations = NoteSourceRelations(links: diskSnapshot?.noteSourceLinks ?? [])
        let diskSummary = diskSnapshot.map {
            CourseWorkspaceSummary(
                importedItems: $0.importedItems,
                noteSourceLinks: $0.noteSourceLinks ?? [],
                studyLocationsByItemID: $0.studyLocationsByItemID ?? [:],
                studySessions: $0.studySessions ?? [],
                learningMemoryEntries: $0.learningMemoryEntries ?? []
            )
        }
        let persistencePassed = diskRelations.sourceIDs(for: noteA.id) == [materialA.id]
            && Set(diskRelations.sourceIDs(for: noteC.id)) == Set([materialB.id, materialC.id])
            && Set(diskRelations.noteIDs(for: materialB.id)) == Set([noteB.id, noteC.id])
            && Set(diskSnapshot?.courses?.map(\.id) ?? []) == Set([courseA.id, courseB.id])
            && diskSnapshot?.activeCourseID == courseB.id
            && diskSnapshot?.courseItemMemberships?.count == courseItemMemberships.count
            && diskSummary?.explicitLinkCount == 4
            && diskSummary?.unlinkedMaterialCount == 0
            && diskSummary?.unlinkedNoteCount == 0

        let resultPassed = initialRelations.links.count == 3
            && importClassificationPassed
            && invalidNoteCreationPassed
            && continuityPassed
            && materialNavigationPassed
            && noteNavigationPassed
            && persistencePassed
        writeCourseWorkspaceVerificationReport(
            name: "course-workspace-workflow-report.json",
            payload: [
                "result": resultPassed ? "pass" : "fail",
                "continuityPassed": continuityPassed,
                "importClassificationPassed": importClassificationPassed,
                "invalidNoteCreationPassed": invalidNoteCreationPassed,
                "initialFolderClassificationPassed": initialFolderClassificationPassed,
                "correctedExistingFileToNote": correctedExistingFileToNote,
                "correctedExistingFileBackToMaterial": correctedExistingFileBackToMaterial,
                "importSelectionPreserved": importSelectionPreserved,
                "importedFolderItemCount": importedFolderItems.count,
                "importedFolderRoles": importedFolderRoles,
                "folderMaterialDefaultPassed": folderMaterialDefaultPassed,
                "folderNoteDefaultsPassed": folderNoteDefaultsPassed,
                "folderCountSummaryPassed": folderCountSummaryPassed,
                "materialNavigationPassed": materialNavigationPassed,
                "noteNavigationPassed": noteNavigationPassed,
                "persistencePassed": persistencePassed,
                "finalMaterialID": selectedItemID ?? "",
                "finalNoteID": activeNotebookItemID ?? "",
                "noteA_sources": diskRelations.sourceIDs(for: noteA.id),
                "noteC_sources": diskRelations.sourceIDs(for: noteC.id),
                "materialB_notes": diskRelations.noteIDs(for: materialB.id),
                "paneMakeCount": paneMakeCount,
                "paneDismantleCount": paneDismantleCount,
            ]
        )
        recordVerificationStage("completed")
    }

    private func writeCourseWorkspaceVerificationReport(name: String, payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = storageURL.deletingLastPathComponent().appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
    }

    private func waitForReaderContextToSettle() async {
        var previousTitle = readerLocationTitle
        var previousPage = readerPageIndex
        var stableChecks = 0
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if readerLocationTitle == previousTitle, readerPageIndex == previousPage {
                stableChecks += 1
                if stableChecks >= 3 { return }
            } else {
                previousTitle = readerLocationTitle
                previousPage = readerPageIndex
                stableChecks = 0
            }
        }
    }

    private func runPaneToggleContinuityVerification() async {
        layout = .documentAgentNotes
        showLibrary = true
        showReader = true
        showAgent = false
        showNotes = true
        agentSurface = .hidden
        recordVerificationStage("pane-toggle-context-prepared")
        let agentMarker = AgentMessage(
            role: .assistant,
            text: "Pane continuity conversation marker",
            source: "verification",
            backend: .offline
        )
        messages = [agentMarker]
        let baselineOrder = normalizedThreePaneOrder
        let cases: [(itemID: String, agentVisible: Bool)] = [
            ("sample-html", false),
            ("sample-html", true),
            ("sample-pdf", false),
            ("sample-pdf", true),
            ("sample-md", false),
            ("sample-md", true),
        ]
        var caseReports: [String] = []
        var allPassed = true

        for verificationCase in cases {
            showReader = true
            showAgent = verificationCase.agentVisible
            showNotes = true
            select(itemID: verificationCase.itemID)
            if verificationCase.itemID == "sample-html" {
                await waitForHTMLContentRailToSettle()
                requestReaderHTMLLocation(
                    id: nil,
                    title: ui("名义利率与实际利率", "Nominal and Real Interest Rates")
                )
                await waitForHTMLContentRailToSettle()
            } else {
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)

            let noteMarker = "# Pane continuity \(verificationCase.itemID) \(verificationCase.agentVisible ? "agent-on" : "agent-off")\n\nUncommitted note state must survive pane toggles.\n"
            updateNote(noteMarker)
            try? await Task.sleep(nanoseconds: 450_000_000)
            let itemID = selectedMaterialItem?.id
            let baselineRevision = agentContextRevision
            let baselineLocation = itemID.flatMap { studyLocationsByItemID[$0] }
            let baselineMessages = messages
            PaneToggleContinuityVerifier.beginMeasurement()

            for _ in 1...20 {
                toggleNotes()
                try? await Task.sleep(nanoseconds: 520_000_000)
                toggleNotes()
                try? await Task.sleep(nanoseconds: 520_000_000)
            }
            for _ in 1...20 {
                toggleReader()
                try? await Task.sleep(nanoseconds: 520_000_000)
                toggleReader()
                try? await Task.sleep(nanoseconds: 520_000_000)
            }
            if verificationCase.itemID == "sample-html" {
                await waitForHTMLContentRailToSettle()
            } else {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }

            let finalLocation = itemID.flatMap { studyLocationsByItemID[$0] }
            let revisionDelta = agentContextRevision &- baselineRevision
            let studyLocationChanged = baselineLocation != finalLocation
            let lifecycleStable = PaneToggleContinuityVerifier.webReaderMakeCount == 0
                && PaneToggleContinuityVerifier.webReaderDismantleCount == 0
                && PaneToggleContinuityVerifier.pdfReaderMakeCount == 0
                && PaneToggleContinuityVerifier.pdfReaderDismantleCount == 0
                && PaneToggleContinuityVerifier.noteEditorMakeCount == 0
                && PaneToggleContinuityVerifier.noteEditorDismantleCount == 0
            let exercisedResizeChain = verificationCase.itemID != "sample-html"
                || PaneToggleContinuityVerifier.htmlSectionEventCount > 0
            let casePassed = exercisedResizeChain
                && PaneToggleContinuityVerifier.htmlLocationCallCount == 0
                && PaneToggleContinuityVerifier.htmlLocationCommitCount == 0
                && revisionDelta == 0
                && !studyLocationChanged
                && lifecycleStable
                && noteText == noteMarker
                && messages == baselineMessages
                && normalizedThreePaneOrder == baselineOrder
                && showReader
                && showAgent == verificationCase.agentVisible
                && showNotes
            allPassed = allPassed && casePassed
            let caseName = "\(verificationCase.itemID)-agent-\(verificationCase.agentVisible ? "on" : "off")"
            let locationReasons = PaneToggleContinuityVerifier.htmlLocationReasons
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            caseReports.append([
                "case=\(caseName)",
                "case_result=\(casePassed ? "pass" : "fail")",
                "agent_revision_delta=\(revisionDelta)",
                "study_location_changed=\(studyLocationChanged)",
                "html_location_calls=\(PaneToggleContinuityVerifier.htmlLocationCallCount)",
                "html_location_commits=\(PaneToggleContinuityVerifier.htmlLocationCommitCount)",
                "html_location_reasons=\(locationReasons)",
                "web_reader_make=\(PaneToggleContinuityVerifier.webReaderMakeCount)",
                "web_reader_dismantle=\(PaneToggleContinuityVerifier.webReaderDismantleCount)",
                "pdf_reader_make=\(PaneToggleContinuityVerifier.pdfReaderMakeCount)",
                "pdf_reader_dismantle=\(PaneToggleContinuityVerifier.pdfReaderDismantleCount)",
                "markdown_editor_make=\(PaneToggleContinuityVerifier.noteEditorMakeCount)",
                "markdown_editor_dismantle=\(PaneToggleContinuityVerifier.noteEditorDismantleCount)",
                "note_preserved=\(noteText == noteMarker)",
                "conversation_preserved=\(messages == baselineMessages)",
                "pane_order_preserved=\(normalizedThreePaneOrder == baselineOrder)",
            ].joined(separator: " "))
            PaneToggleContinuityVerifier.endMeasurement()
        }

        let report = ([
            "result=\(allPassed ? "pass" : "fail")",
            "cases=\(cases.count)",
            "notes_cycles_per_case=20",
            "reader_cycles_per_case=20",
        ] + caseReports).joined(separator: "\n") + "\n"
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("pane-toggle-continuity-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("pane-toggle-result:\(allPassed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    private func runPaneLayoutStabilityVerification() async {
        layout = .documentAgentNotes
        showLibrary = false
        showReader = true
        showAgent = false
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        await waitForHTMLContentRailToSettle()

        let noteMarker = "# Pane ownership marker\n\nUnsaved note input must survive stable slot animations.\n"
        let draftMarker = "Unsent agent draft must survive stable slot animations."
        let messageMarker = AgentMessage(
            role: .assistant,
            text: "Stable parent conversation marker",
            source: "verification",
            backend: .offline
        )
        updateNote(noteMarker)
        agentDraft = draftMarker
        messages = [messageMarker]
        try? await Task.sleep(nanoseconds: 700_000_000)

        let itemID = selectedMaterialItem?.id
        let baselineLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let baselineRevision = agentContextRevision
        let baselineOrder = normalizedThreePaneOrder
        PaneToggleContinuityVerifier.beginMeasurement()
        recordVerificationStage("pane-layout-context-prepared")

        toggleNotes()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleNotes()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleAgent()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleReader()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleReader()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleAgent()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleNotes()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleNotes()
        try? await Task.sleep(nanoseconds: 700_000_000)

        let finalLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let revisionDelta = agentContextRevision &- baselineRevision
        let passed = showReader
            && !showAgent
            && showNotes
            && noteText == noteMarker
            && agentDraft == draftMarker
            && messages == [messageMarker]
            && normalizedThreePaneOrder == baselineOrder
            && finalLocation == baselineLocation
            && revisionDelta == 0
            && PaneToggleContinuityVerifier.htmlLocationCallCount == 0
            && PaneToggleContinuityVerifier.webReaderMakeCount == 0
            && PaneToggleContinuityVerifier.webReaderDismantleCount == 0
            && PaneToggleContinuityVerifier.noteEditorMakeCount == 0
            && PaneToggleContinuityVerifier.noteEditorDismantleCount == 0
        let report = [
            "result=\(passed ? "pass" : "fail")",
            "transitions=8",
            "reader_visible=\(showReader)",
            "agent_visible=\(showAgent)",
            "notes_visible=\(showNotes)",
            "agent_revision_delta=\(revisionDelta)",
            "study_location_changed=\(finalLocation != baselineLocation)",
            "html_location_calls=\(PaneToggleContinuityVerifier.htmlLocationCallCount)",
            "web_reader_make=\(PaneToggleContinuityVerifier.webReaderMakeCount)",
            "web_reader_dismantle=\(PaneToggleContinuityVerifier.webReaderDismantleCount)",
            "note_editor_make=\(PaneToggleContinuityVerifier.noteEditorMakeCount)",
            "note_editor_dismantle=\(PaneToggleContinuityVerifier.noteEditorDismantleCount)",
            "note_preserved=\(noteText == noteMarker)",
            "agent_draft_preserved=\(agentDraft == draftMarker)",
            "conversation_preserved=\(messages == [messageMarker])",
            "pane_order_preserved=\(normalizedThreePaneOrder == baselineOrder)",
        ].joined(separator: "\n") + "\n"
        PaneToggleContinuityVerifier.endMeasurement()
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("pane-layout-stability-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("pane-layout-result:\(passed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    private func runPaneReorderWidthVerification() async {
        layout = .documentAgentNotes
        showLibrary = false
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        await waitForHTMLContentRailToSettle()

        let noteMarker = "# Reorder and width marker\n\nUnsaved text must survive pane movement.\n"
        let draftMarker = "Unsent draft must survive pane movement."
        let messageMarker = AgentMessage(
            role: .assistant,
            text: "Reorder conversation marker",
            source: "verification",
            backend: .offline
        )
        updateNote(noteMarker)
        agentDraft = draftMarker
        messages = [messageMarker]

        for _ in 0..<30 {
            let order = visibleDocumentPaneOrder
            if order.count == 3, order.allSatisfy({ threePaneReorderFrames[$0] != nil }) {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let baselineOrder = normalizedThreePaneOrder
        let baselineRevision = agentContextRevision
        let itemID = selectedMaterialItem?.id
        let baselineLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let baselineAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0
        PaneToggleContinuityVerifier.beginMeasurement()
        recordVerificationStage("pane-reorder-width-context-prepared")

        requestPaneExpansion(.agent)
        for _ in 0..<20 {
            guard paneExpansionRequest != nil else { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        let expandedAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0

        beginThreePaneReorder(.reader)
        let dragDistance = max(
            (threePaneReorderFrames[.notes]?.midX ?? 1_000)
                - (threePaneReorderFrames[.reader]?.midX ?? 0),
            1_000
        )
        updateThreePaneReorder(.reader, horizontalDelta: dragDistance)
        finishThreePaneReorder(.reader, horizontalDelta: dragDistance)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let reorderedOrder = normalizedThreePaneOrder
        let reorderedAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0

        toggleAgent()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleAgent()
        try? await Task.sleep(nanoseconds: 700_000_000)
        let restoredAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0
        let restoredStore = WorkspaceStore()
        let persistedOrder = restoredStore.normalizedThreePaneOrder
        let widthTolerance = max(12, reorderedAgentWidth * 0.12)
        let finalLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let lifecycleStable = PaneToggleContinuityVerifier.webReaderMakeCount == 0
            && PaneToggleContinuityVerifier.webReaderDismantleCount == 0
            && PaneToggleContinuityVerifier.noteEditorMakeCount == 0
            && PaneToggleContinuityVerifier.noteEditorDismantleCount == 0
        let passed = baselineOrder != reorderedOrder
            && reorderedOrder.last == .reader
            && persistedOrder == reorderedOrder
            && paneExpansionRequest == nil
            && expandedAgentWidth >= ContentRailMetrics.readableWidth
            && reorderedAgentWidth >= ContentRailMetrics.readableWidth
            && abs(restoredAgentWidth - reorderedAgentWidth) <= widthTolerance
            && noteText == noteMarker
            && agentDraft == draftMarker
            && messages == [messageMarker]
            && finalLocation == baselineLocation
            && agentContextRevision == baselineRevision
            && lifecycleStable

        let report = [
            "result=\(passed ? "pass" : "fail")",
            "baseline_order=\(baselineOrder.map(\.rawValue).joined(separator: ","))",
            "reordered_order=\(reorderedOrder.map(\.rawValue).joined(separator: ","))",
            "persisted_order=\(persistedOrder.map(\.rawValue).joined(separator: ","))",
            "baseline_agent_width=\(baselineAgentWidth)",
            "expanded_agent_width=\(expandedAgentWidth)",
            "reordered_agent_width=\(reorderedAgentWidth)",
            "restored_agent_width=\(restoredAgentWidth)",
            "width_tolerance=\(widthTolerance)",
            "expansion_consumed=\(paneExpansionRequest == nil)",
            "note_preserved=\(noteText == noteMarker)",
            "agent_draft_preserved=\(agentDraft == draftMarker)",
            "conversation_preserved=\(messages == [messageMarker])",
            "study_location_changed=\(finalLocation != baselineLocation)",
            "agent_revision_delta=\(agentContextRevision &- baselineRevision)",
            "native_lifecycle_stable=\(lifecycleStable)",
        ].joined(separator: "\n") + "\n"
        PaneToggleContinuityVerifier.endMeasurement()
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("pane-reorder-width-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("pane-reorder-width-result:\(passed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    private func runReaderScrollPersistenceVerification() async {
        PaneToggleContinuityVerifier.beginMeasurement()
        layout = .documentAgentNotes
        showLibrary = true
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        await waitForHTMLContentRailToSettle()
        let baseline = studyLocationsByItemID["sample-html"]
        let previousScrollSchedules = PaneToggleContinuityVerifier.verificationScrollScheduleCount
        NotificationCenter.default.post(name: .weiBeiVerificationUserScroll, object: nil)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let didTriggerScroll = PaneToggleContinuityVerifier.verificationScrollScheduleCount > previousScrollSchedules
        recordVerificationStage("reader-scroll-context-prepared")

        var finalLocation = studyLocationsByItemID["sample-html"]
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            finalLocation = studyLocationsByItemID["sample-html"]
            if finalLocation?.locationID != nil,
               finalLocation?.locationID != baseline?.locationID {
                break
            }
        }
        save()
        try? await Task.sleep(nanoseconds: 250_000_000)
        let restoredStore = WorkspaceStore()
        let persisted = restoredStore.studyLocationsByItemID["sample-html"]
        let scrolled = finalLocation?.locationID != nil
            && finalLocation?.locationID != baseline?.locationID
            && finalLocation?.lastStudiedAt != baseline?.lastStudiedAt
        let restored = restoredStore.selectedItemID == "sample-html"
            && restoredStore.readerLocationID == finalLocation?.locationID
            && restoredStore.readerTargetLocationID == finalLocation?.locationID
            && persisted?.locationID == finalLocation?.locationID
            && persisted?.locationTitle == finalLocation?.locationTitle
        let passed = didTriggerScroll && scrolled && restored
        let locationReasons = PaneToggleContinuityVerifier.htmlLocationReasons
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let report = [
            "result=\(passed ? "pass" : "fail")",
            "input_path=dom-wheel-event",
            "verification_scroll_triggered=\(didTriggerScroll)",
            "baseline_location_id=\(baseline?.locationID ?? "")",
            "final_location_id=\(finalLocation?.locationID ?? "")",
            "final_location_title=\(finalLocation?.locationTitle ?? "")",
            "timestamp_changed=\(finalLocation?.lastStudiedAt != baseline?.lastStudiedAt)",
            "restored_location_id=\(restoredStore.readerLocationID ?? "")",
            "restored_target_id=\(restoredStore.readerTargetLocationID ?? "")",
            "html_section_events=\(PaneToggleContinuityVerifier.htmlSectionEventCount)",
            "html_active_events=\(PaneToggleContinuityVerifier.htmlActiveEventCount)",
            "html_location_calls=\(PaneToggleContinuityVerifier.htmlLocationCallCount)",
            "html_location_reasons=\(locationReasons)",
            "verification_scroll_schedules=\(PaneToggleContinuityVerifier.verificationScrollScheduleCount)",
            "verification_scroll_result=\(PaneToggleContinuityVerifier.verificationScrollResult)",
        ].joined(separator: "\n") + "\n"
        PaneToggleContinuityVerifier.endMeasurement()
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("reader-scroll-persistence-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("reader-scroll-result:\(passed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    private func waitForHTMLContentRailToSettle() async {
        var previousEventCount = PaneToggleContinuityVerifier.htmlEventSequence
        var stableChecks = 0
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let currentEventCount = PaneToggleContinuityVerifier.htmlEventSequence
            if currentEventCount == previousEventCount {
                stableChecks += 1
                if stableChecks >= 4 { return }
            } else {
                previousEventCount = currentEventCount
                stableChecks = 0
            }
        }
    }

    private func recordVerificationStage(_ stage: String) {
        guard Self.environmentValue("WEIBEI_SUPPRESS_ACTIVATION") == "1" else { return }
        let url = storageURL.deletingLastPathComponent().appendingPathComponent("verification-state.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? "\(previous)\(stage)\n".write(to: url, atomically: true, encoding: .utf8)
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

    private func noteBlockForAgentAnswer(_ answer: String) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suggestedNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: text, language: interfaceLanguage) {
            return suggestedNoteBlock
        }
        guard !text.hasPrefix("#") else { return text }
        return "## \(ui("整理建议", "Organization suggestion"))\n\(text)"
    }

    func askAgent() {
        flushStagedNoteDraftForAgentContext()
        guard agentRequestTask == nil,
              !isAskingAgent,
              !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        agentRequestTask = Task { @MainActor [weak self] in
            await self?.performAgentRequest()
        }
    }

    /**
     * 发起当前草稿请求并等待该次 Store 管理的任务结束。
     */
    func askAgentAndWait() async {
        askAgent()
        await agentRequestTask?.value
    }

    private func currentVisualAssetsForAgent() -> [StudyAgentVisualAsset] {
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

    private func performAgentRequest() async {
        flushStagedNoteDraftForAgentContext()
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAskingAgent else {
            agentRequestTask = nil
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
        let requestID = UUID()
        let requestRevision = AgentRequestRevisionSnapshot(
            workspace: agentContextRevision,
            memory: learningMemoryRevision
        )
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
        activeAgentRequestID = requestID
        agentStreamingText = ""
        agentActivityText = ui("正在整理课程目录", "Indexing course")
        defer {
            if activeAgentRequestID == requestID {
                activeAgentRequestID = nil
                isAskingAgent = false
                agentStreamingText = ""
                agentActivityText = nil
                agentRequestTask = nil
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
            guard activeAgentRequestID == requestID,
                  requestRevision.isCurrent(
                    workspace: agentContextRevision,
                    memory: learningMemoryRevision
                  ) else {
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
                contextRevision: "\(requestRevision.workspace):\(requestID.uuidString.lowercased())"
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
            guard activeAgentRequestID == request.id,
                  requestRevision.isCurrent(
                    workspace: agentContextRevision,
                    memory: learningMemoryRevision
                  ) else { return }
            latestAgentNoteProposal = reply.noteProposal
            applyLearningUpdate(
                reply.learningUpdate,
                expectedContextRevision: request.contextRevision,
                expectedMemoryRevision: requestRevision.memory,
                expectedUserQuestion: request.question
            )
            lastAgentReplyContextRevision = requestRevision.workspace
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
            guard activeAgentRequestID == requestID else { return }
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
        guard isAskingAgent || activeAgentRequestID != nil else { return }
        agentRequestTask?.cancel()
        agentRequestTask = nil
        activeAgentRequestID = nil
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

    private func executeStudyAgentRequest(_ request: StudyAgentRequest) async throws -> StudyAgentReply {
        if let agentRequestExecutor {
            return try await agentRequestExecutor(request)
        }
        let verificationScenario = Self.environmentValue("WEIBEI_VERIFY_SCENARIO")
        let isExplicitOfflineVerification = Self.environmentValue("WEIBEI_FORCE_OFFLINE_AGENT") == "1"
            && Self.environmentValue("WEIBEI_SUPPRESS_ACTIVATION") == "1"
            && ["offline-learning-flow", "immersive-conversation-flow"].contains(verificationScenario)
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
            let linkedOAuth = PiOAuthService.readLinkedOAuthProviders(
                from: WeiBeiAgentDataPaths.piAuthJSON
            )
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
        agentRequestTask?.cancel()
        quietInsightTask?.cancel()
        let runtime = piRuntime
        let completion = DispatchSemaphore(value: 0)
        Task.detached {
            await runtime.shutdown()
            completion.signal()
        }
        _ = completion.wait(timeout: .now() + 1)
    }

    private func applyAgentProgress(_ progress: StudyAgentProgress, requestID: UUID) {
        guard activeAgentRequestID == requestID else { return }
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

    /**
     * 创建绑定到当前工作区的内置样例，避免显式工作区仍写入全局用户目录。
     */
    private static func makeSampleItems(workspaceDirectory: URL) -> [StudyItem] {
        [
            StudyItem(id: "sample-html", title: "货币金融学课程 HTML", subtitle: "HTML 教程", kind: .html, urlPath: nil, isSample: true),
            StudyItem(id: "sample-pdf", title: "Mishkin 教材样例", subtitle: "PDF 阅读", kind: .pdf, urlPath: samplePDFURL(workspaceDirectory: workspaceDirectory)?.path, isSample: true),
            StudyItem(id: "sample-md", title: "课堂笔记样例", subtitle: "Markdown", kind: .markdown, urlPath: nil, isSample: true)
        ]
    }

    /**
     * 在 Store 已选定的工作区内准备 PDF 样例。
     */
    private static func samplePDFURL(workspaceDirectory: URL) -> URL? {
        let directory = workspaceDirectory.appendingPathComponent("Samples", isDirectory: true)
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

    private func writePendingNotebookRenameJournal(_ journal: PendingNotebookRenameJournal) throws {
        let data = try JSONEncoder().encode(journal)
        try data.write(to: notebookRenameJournalURL, options: [.atomic])
    }

    private func removePendingNotebookRenameJournal() {
        try? FileManager.default.removeItem(at: notebookRenameJournalURL)
    }

    @discardableResult
    private func recoverPendingNotebookRenameIfNeeded() -> Bool {
        guard let data = try? Data(contentsOf: notebookRenameJournalURL),
              let journal = try? JSONDecoder().decode(PendingNotebookRenameJournal.self, from: data) else {
            return false
        }
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
    private func resolvePersistedImportedFileBookmarks() -> Bool {
        var changed = false
        for index in importedItems.indices {
            let resolution = resolveTrackedImportedFile(at: index)
            if resolution.changed { changed = true }
        }
        return changed
    }

    private func resolveTrackedImportedFile(at index: Int) -> (url: URL?, changed: Bool) {
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
    private func refreshImportedFileTracking(itemID: String, url: URL) -> StudyItem? {
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
    private func migrateLegacyImportedItemIdentities() -> Bool {
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

    private func canCoalesceDuplicateItem(_ oldItem: StudyItem, into newItem: StudyItem) -> Bool {
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

    private func valuesCanCoalesce<Value: Equatable>(_ oldValue: Value?, _ newValue: Value?) -> Bool {
        oldValue == nil || newValue == nil || oldValue == newValue
    }

    private func studyLocationsCanCoalesce(oldID: String, newID: String) -> Bool {
        guard var oldLocation = studyLocationsByItemID[oldID],
              let newLocation = studyLocationsByItemID[newID] else {
            return true
        }
        oldLocation.itemID = newID
        return oldLocation == newLocation
    }

    private func pendingPersistenceCanCoalesce(oldID: String, newID: String) -> Bool {
        guard let oldPending = pendingNotePersistenceByItemID[oldID],
              let newPending = pendingNotePersistenceByItemID[newID] else {
            return true
        }
        return oldPending.markdown == newPending.markdown
    }

    private func replaceItemIDEverywhere(_ oldID: String, with newID: String) {
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

    private func replaceNavigationItemID(_ oldID: String, with newID: String) {
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

    private func showTransientNoteStatus(_ message: String) {
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

    private func invalidateAgentContext() {
        agentContextRevision &+= 1
        latestAgentNoteProposal = nil
        lastAgentReplyContextRevision = nil
        quietInsightTask?.cancel()
        if isAskingAgent || activeAgentRequestID != nil {
            cancelAgentRequest()
        }
    }

    private func clearUnpinnedFloatingSelection(keepContext: Bool = true, invalidatesAgentContext: Bool = true) {
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

    private func collapseSelectionFloatIntoConversationIfVisible() {
        // Keep dual-surface answer: do not auto-collapse float into chat while answering.
        guard !keepFloatingSelectionForAnswer else { return }
        guard isConversationSurfaceVisible, agentSurface == .selectionFloat else { return }
        agentSurface = .hidden
        selectionAnchor = nil
        pinnedFloatingAgent = false
    }

    private func refreshQuietInsightIfNeeded() {
        // Quiet insight surface removed for 1.0: never schedule background generation.
        quietInsightTask?.cancel()
        quietInsightTask = nil
        quietInsightTaskID = nil
        isGeneratingQuietInsight = false
        showQuietInsight = false
    }

    private func finishQuietInsightTask(id: UUID) {
        guard quietInsightTaskID == id else { return }
        quietInsightTask = nil
        quietInsightTaskID = nil
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

    private static func noteContentDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func readNotebookMarkdown(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return markdown
    }

    nonisolated private static func writeNotebookMarkdown(_ markdown: String, to url: URL) throws {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated private static func moveNotebookFile(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    nonisolated private static func writeWorkspaceSnapshot(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    private static func noteContentDigest(at url: URL) -> String? {
        (try? Data(contentsOf: url)).map(noteContentDigest)
    }

    private func noteText(for item: StudyItem?) -> String {
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

    private func persistCurrentNote() {
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

    private func retainPendingNoteWrite(_ markdown: String, itemID: String, fallbackURL: URL?) {
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

    private func persistNote(_ markdown: String, for item: StudyItem) {
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

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let snapshot = try? JSONDecoder().decode(PersistedWorkspace.self, from: data) else {
            return
        }
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
        // Single credential resolve: profile first, then legacy per-provider store.
        // Avoids two Keychain reads (and two password dialogs) on every launch.
        openAIAPIKey = resolveStoredAPIKey()
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
            WeiBeiThemeRuntime.mode = appearanceMode
        }
        adaptImportedDocumentColors = snapshot.adaptImportedDocumentColors ?? true
        if let interfaceLanguageRaw = snapshot.interfaceLanguageRaw,
           let interfaceLanguage = WeiBeiInterfaceLanguage(rawValue: interfaceLanguageRaw) {
            self.interfaceLanguage = interfaceLanguage
        }
        noteText = noteText(for: activeNoteItem)
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

    /// Schedule a coalesced workspace snapshot write. Verification and explicit flushes write immediately.
    @discardableResult
    private func save() -> Bool {
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

    private static var mustSaveImmediately: Bool {
        // Keep verification / self-check / packaging paths synchronous and deterministic.
        let environment = ProcessInfo.processInfo.environment
        if environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1" { return true }
        if environment["WEIBEI_FORCE_IMMEDIATE_SAVE"] == "1" { return true }
        if ProcessInfo.processInfo.arguments.contains("--self-check-imported-identity") { return true }
        return false
    }

    private func scheduleDebouncedWorkspaceSave() {
        workspaceSaveGeneration &+= 1
        let generation = workspaceSaveGeneration
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.workspaceSaveDebounceNanoseconds ?? 280_000_000)
            guard let self, !Task.isCancelled, self.workspaceSaveGeneration == generation else { return }
            _ = self.performSaveNow()
        }
    }

    @discardableResult
    private func performSaveNow() -> Bool {
        WeiBeiPerf.measure("workspace.save") {
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
            do {
                let data = try JSONEncoder().encode(snapshot)
                try workspaceSnapshotWriter(data, storageURL)
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

    private func resolvedAPIKey() -> (key: String, source: String)? {
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

        // Prefer the in-settings field (already hydrated once at load). Do not re-hit
        // Keychain on every agent request — that re-triggered ACL prompts mid-session.
        let fieldKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)
        if !fieldKey.isEmpty {
            return (fieldKey, ui("设置中的密钥", "key from Settings"))
        }

        return nil
    }

    /// One-shot credential resolve used at workspace load / profile switch.
    private func resolveStoredAPIKey() -> String {
        if let storedAPIKeyResolver {
            return storedAPIKeyResolver()
        }
        let profileKey = AgentCredentialProfileStore.loadAPIKey(profileID: activeAgentProfileID)
        if !profileKey.isEmpty { return profileKey }
        return OpenAIAPIKeyStore.load(provider: agentProviderID.piProviderName)
    }

    /// Backward-compatible alias used by remaining call sites / SelfCheck slices.
    private func resolvedOpenAIAPIKey() -> (key: String, source: String)? {
        resolvedAPIKey()
    }

    private var resolvedModelName: String {
        let environmentModel = Self.environmentValue("WEIBEI_OPENAI_MODEL")
        return environmentModel.isEmpty ? modelName : environmentModel
    }

    private static func environmentValue(_ name: String) -> String {
        OpenAIAPIKeyStore.cleaned(ProcessInfo.processInfo.environment[name] ?? "")
    }

    private static func removeLegacyCourseIndex(in directory: URL) {
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

    private static func workspaceRootDirectory() -> URL? {
        let override = environmentValue("WEIBEI_WORKSPACE_DIR")
        if !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WeiBei", isDirectory: true)
    }
}
