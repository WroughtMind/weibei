import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

enum WeiBeiSafetyTestMode {
#if DEBUG
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["WEIBEI_SAFETY_TEST_MODE"] == "1"
    }
#else
    static let isEnabled = false
#endif
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

enum CourseHomeSearchResultKind: String, Sendable {
    case material
    case note
    case chat
}

struct CourseHomeSearchResult: Identifiable, Sendable {
    let id: String
    let kind: CourseHomeSearchResultKind
    let itemID: String?
    let sessionID: UUID?
    let title: String
    let detail: String
    let matchedText: String?
}

struct CourseHomeSearchOutcome: Sendable {
    let results: [CourseHomeSearchResult]
    let availability: CourseDocumentIndexAvailability
}

enum CourseProjectRebindImpact: Equatable {
    case unchanged
    case useNewerCandidate
}

struct CourseProjectRebindProposal {
    let courseID: UUID
    let courseTitle: String
    let candidateRoot: URL
    let candidateRootIdentity: ImportedFileIdentity
    let expectedCourse: Course
    let expectedLocalPayloadDigest: String
    let snapshot: CoursePortableAdoptionSnapshot
    let impact: CourseProjectRebindImpact
}

enum CourseFolderAdoptionOutcome {
    case opened(UUID)
    case requiresRebind(CourseProjectRebindProposal)
}

private enum CourseProjectRebindError: LocalizedError {
    case originalRootStillAvailable
    case proposalChanged

    var errorDescription: String? {
        switch self {
        case .originalRootStillAvailable:
            return "原课程文件夹仍然可以安全访问；魏碑不会把同一门课程静默改绑到另一处。"
        case .proposalChanged:
            return "课程或所选文件夹在确认前发生了变化，请重新选择后再试。"
        }
    }
}

private struct AgentReplySourceFileSnapshot: Sendable {
    let source: AgentReplySource
    let itemID: String
    let url: URL
    let expectedIdentity: ImportedFileIdentity?
}

private struct CoursePortableStateWriteRecord {
    let url: URL
    let previousData: Data?
    let committedData: Data
    let expectedDirectoryIdentity: ImportedFileIdentity
}

private struct CoursePortableStateCommit {
    let writes: [CoursePortableStateWriteRecord]
    let previousRevisions: [UUID: UInt64]
    let previousDigests: [UUID: String]
    let previousDirtyCourseIDs: Set<UUID>
    let previousBlockedCourseIDs: Set<UUID>
    let previousOversizedCourseIDs: Set<UUID>
    let previousNeedsBootstrap: Bool
}


enum CourseWorkspaceDestination: String, CaseIterable, Sendable {
    case hub
    case relations
    case materials
    case notes
    case sessions
}

enum CourseOwnedFileRole: String, Codable, Sendable {
    case material
    case note

    var directoryName: String {
        switch self {
        case .material: "文稿"
        case .note: "笔记"
        }
    }

    var commonDirectoryName: String {
        switch self {
        case .material: "通用资料"
        case .note: "通用笔记"
        }
    }
}

enum ContextualContentKind: Equatable, Sendable {
    case material
    case note
}

enum CourseFileConflictResolution: Equatable, Sendable {
    case cancel
    case keepBoth(preferredFileName: String?)
    case replace
}

enum CourseKeepBothNaming {
    static func suggestedFileName(
        originalName: String,
        conflictingTargets: [URL]
    ) -> String {
        let originalURL = URL(fileURLWithPath: originalName)
        let stem = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension
        let directories = conflictingTargets.map {
            $0.deletingLastPathComponent().standardizedFileURL
        }
        for suffix in 2...9_999 {
            let candidate = pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(pathExtension)"
            if directories.allSatisfy({
                !FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent(candidate).path
                )
            }) {
                return candidate
            }
        }
        return pathExtension.isEmpty
            ? "\(stem) \(UUID().uuidString.lowercased())"
            : "\(stem) \(UUID().uuidString.lowercased()).\(pathExtension)"
    }
}

struct CourseOwnedFileImportResult {
    var item: StudyItem
    var sourceCleanupPending: Bool
}

struct CourseFileOperationProgress: Equatable, Sendable {
    var completed: Int
    var total: Int
    var currentFileName: String
}

enum CourseFileRemovalOutcome: Sendable {
    case removed
    case restored
    case quarantined(URL)
}

enum CourseOwnedFileError: LocalizedError {
    case courseNotFound
    case courseRootUnavailable
    case sourceMustBeRegularFile
    case unsupportedFile
    case sourceAlreadyInsideCourse
    case sourceIdentityChanged
    case unsafeCoursePath
    case targetConflict(URL)
    case replacementTargetIsShared
    case verificationFailed
    case workspaceSaveFailed

    var errorDescription: String? {
        switch self {
        case .courseNotFound:
            "找不到要接收文件的课程。"
        case .courseRootUnavailable:
            "课程文件夹当前不可访问。"
        case .sourceMustBeRegularFile:
            "首个版本只接收普通本地文件；符号链接和别名不会被移动。"
        case .unsupportedFile:
            "这个文件类型当前不能加入课程。"
        case .sourceAlreadyInsideCourse:
            "这个文件已经位于当前课程文件夹中。"
        case .sourceIdentityChanged:
            "复制期间来源文件发生了变化，魏碑没有删除或登记它。"
        case .unsafeCoursePath:
            "课程目标路径越出了当前课程文件夹，魏碑已停止操作。"
        case .targetConflict(let url):
            "课程中已经存在“\(url.lastPathComponent)”。魏碑没有覆盖它。"
        case .replacementTargetIsShared:
            "这份共享原件正被其他课程使用，不能替换；可以取消或改名保留两份。"
        case .verificationFailed:
            "复制后的文件校验失败，原文件保持不变。"
        case .workspaceSaveFailed:
            "课程文件已经复制，但课程状态没有成功保存；魏碑已安全撤销本次登记。"
        }
    }
}

enum CourseRemovalError: LocalizedError {
    case courseNotFound
    case courseBusy
    case latestStateNotSaved
    case courseRootUnavailable
    case courseRootChanged
    case workspaceSaveFailed
    case workspaceSaveFailedAfterTrash(URL)

    var errorDescription: String? {
        switch self {
        case .courseNotFound:
            "找不到这门课程。"
        case .courseBusy:
            "课程仍有正在进行的写入或操作，魏碑没有移除这门课。请稍后重试。"
        case .latestStateNotSaved:
            "课程最新状态尚未安全写入课程文件夹，魏碑没有移除这门课。"
        case .courseRootUnavailable:
            "课程文件夹当前不可访问，不能移到废纸篓。"
        case .courseRootChanged:
            "课程文件夹已发生变化，魏碑已停止操作。"
        case .workspaceSaveFailed:
            "魏碑没有保存移除结果，课程仍保持登记。"
        case .workspaceSaveFailedAfterTrash(let trashURL):
            "课程文件夹已移到废纸篓，但魏碑没有保存取消登记结果。课程仍会显示为不可用：\(trashURL.path)"
        }
    }
}

enum ContentSourceRemovalError: LocalizedError {
    case itemUnavailable
    case sourceChanged
    case trashMoveFailed
    case workspaceSaveFailed

    var errorDescription: String? {
        switch self {
        case .itemUnavailable:
            "找不到这份资料或笔记的真实原文件。"
        case .sourceChanged:
            "原文件已经发生变化，魏碑没有删除它。"
        case .trashMoveFailed:
            "原文件没有成功移到 macOS 废纸篓，课程关系保持不变。"
        case .workspaceSaveFailed:
            "魏碑没有保存删除结果，原文件已从废纸篓恢复。"
        }
    }
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
    private(set) var courseLibraryRootPath: String?
    private(set) var courseLibraryRootIdentity: ImportedFileIdentity?
    private(set) var courseLibraryRootBookmarkData: Data?
    private(set) var courseLibraryRootURL: URL?
    private(set) var courseLibraryUnavailableReason: String?
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
    @Published private(set) var isStoppingAgent = false
    @Published private(set) var isAgentSwitchConfirmationPresented = false
    @Published var agentStreamingText = ""
    @Published var agentActivityText: String?
    @Published var showLoadingIndicatorSamples = false
    /// Last failed user question for precise one-tap retry.
    @Published private(set) var lastFailedAgentQuestion: String?
    @Published private(set) var lastAgentFailureKind: AgentFailureKind?
    @Published private(set) var agentAuthenticationStatus = AgentAuthenticationStatus()
    @Published private(set) var latestAgentNoteProposal: StudyAgentNoteProposal?
    @Published private(set) var latestAgentLearningUpdate: StudyAgentLearningUpdate?
    @Published private(set) var noteSourceLinks: [NoteSourceLink] = [] {
        didSet {
            noteSourceRelationIndex = NoteSourceRelationIndex(links: noteSourceLinks)
        }
    }
    @Published private(set) var materialNotePairings: [String: String] = [:]
    @Published private(set) var noteMaterialPairings: [String: String] = [:]
    @Published private(set) var blankNoteDraftMaterialID: String?
    @Published var linkedSourcesPresented = false
    private(set) var studyLocationsByItemID: [String: StudyLocation] = [:]
    private(set) var studyLocationsByCourseID: [String: [String: StudyLocation]] = [:]
    private(set) var courseResumePoints: [CourseResumePoint] = []
    @Published private(set) var learningMemoryStates: [ScopedLearningMemoryState] = []
    private(set) var courseKnowledgeProfiles: [CourseKnowledgeProfile] = []
    @Published private(set) var studySessions: [StudySession] = []
    @Published private(set) var activeStudySessionID: UUID?
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
    @Published private(set) var readerSourceHighlight = ""
    @Published private(set) var readerSourceHighlightPageIndex: Int?
    @Published var readerSearch = "" {
        didSet {
            guard readerSearch != oldValue else { return }
            readerSourceHighlight = ""
            readerSourceHighlightPageIndex = nil
        }
    }
    @Published var showReaderSearch = false
    /// Reader viewport (HTML section / PDF page). Scroll commits must not
    /// auto-publish — every EnvironmentObject consumer (agent chat WKWebView
    /// rows) would remasure and freeze the main thread (sample 2026-08-01).
    private var suppressReaderViewportPublish = false
    private var readerLocationIDValue: String?
    private var readerLocationTitleValue: String?
    private var readerPageIndexValue = 0
    var readerLocationID: String? {
        get { readerLocationIDValue }
        set {
            guard readerLocationIDValue != newValue else { return }
            if !suppressReaderViewportPublish {
                objectWillChange.send()
            }
            readerLocationIDValue = newValue
        }
    }
    var readerLocationTitle: String? {
        get { readerLocationTitleValue }
        set {
            guard readerLocationTitleValue != newValue else { return }
            if !suppressReaderViewportPublish {
                objectWillChange.send()
            }
            readerLocationTitleValue = newValue
        }
    }
    var readerPageIndex: Int {
        get { readerPageIndexValue }
        set {
            let next = max(newValue, 0)
            guard readerPageIndexValue != next else { return }
            if !suppressReaderViewportPublish {
                objectWillChange.send()
            }
            readerPageIndexValue = next
        }
    }
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
    @Published var floatingSelectionPrompt = ""
    @Published var pinnedFloatingAgent = false
    @Published var selectionContext: SelectionContext?
    @Published var selectionAttachments: [SelectionContext] = []
    /// Selection capsule position. Anchor-only drag/scroll updates must not
    /// `@Published`-fanout into agent chat (SelectionOverlay remasure freeze).
    private var selectionAnchorValue: CGPoint?
    private var suppressSelectionAnchorPublish = false
    private var lastSelectionAnchorPublishAt: CFAbsoluteTime = 0
    var selectionAnchor: CGPoint? {
        get { selectionAnchorValue }
        set {
            guard !Self.anchorsApproximatelyEqual(selectionAnchorValue, newValue) else { return }
            if !suppressSelectionAnchorPublish {
                objectWillChange.send()
            }
            selectionAnchorValue = newValue
        }
    }
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
    @Published private(set) var courseFileOperationProgress: CourseFileOperationProgress?
    @Published var notebookCreationDraft: NotebookCreationDraft?
    @Published var notebookRenameDraft: NotebookRenameDraft?
    private var notebookRenameInFlight = false
    @Published var modelName: String = ""
    @Published var agentProviderID: AgentProviderID = .openai
    @Published var agentBaseURL: String = ""
    @Published var agentAuthMethod: AgentAuthMethod = .apiKey
    @Published var agentCredentialProfiles: [AgentCredentialProfile] = AgentCredentialProfileStore.loadProfiles()
    @Published var activeAgentProfileID: UUID = AgentCredentialProfileStore.activeProfileID()
        ?? AgentCredentialProfileStore.loadProfiles().first?.id
        ?? AgentCredentialProfileStore.defaultProfile().id
    @Published var appearanceMode: WeiBeiAppearanceMode = .paper
    @Published var adaptImportedDocumentColors = true
    @Published var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    @Published var courseWorkspacePresented = false
    @Published private(set) var courseWorkspaceCourseID: UUID?
    @Published private(set) var courseWorkspaceDestination: CourseWorkspaceDestination = .hub
    @Published private(set) var courseWorkspaceTargetItemID: String?
    @Published private var backNavigationStack: [NavigationSnapshot] = []
    @Published private var forwardNavigationStack: [NavigationSnapshot] = []

    private var notesByItemID: [String: String] = [:]
    private var pendingNoteWritesByItemID: [String: PendingNoteWriteState] = [:]
    private var noteOperationErrorsByItemID: [String: String] = [:]
    private var noteBackingContentDigestsByItemID: [String: String] = [:]
    private var loadedCourseNoteTextByItemID: [String: String] = [:]
    private var courseNoteLoadTasksByItemID: [String: Task<Void, Never>] = [:]
    private var courseNoteLoadGenerationByItemID: [String: UInt64] = [:]
    private var courseNoteWritesInFlight = Set<String>()
    private var courseNoteWriteTasksByItemID: [String: Task<Void, Never>] = [:]
    private var blankNoteMaterializationTask: Task<Void, Never>?
    private var pendingBlankNoteText = ""
    private var lastCourseNoteReadRanOnMainThread: Bool?
    private var lastCourseNoteWriteRanOnMainThread: Bool?
    private var lastCourseHomeSearchRanOnMainThread: Bool?
    private var lastPortableAdoptionReadRanOnMainThread: Bool?
    private var lastCourseRebindRootSearchRanOnMainThread: Bool?
    private let workspaceDirectory: URL
    private let storageURL: URL
    private let notebookRenameJournalURL: URL
    private let courseRemovalJournalURL: URL
    private let importedFileIdentityResolver: (URL) -> ImportedFileIdentity?
    private let courseRootBookmarkMaker: (URL) -> Data?
    private let courseRootBookmarkResolver: (Data) -> CourseProjectResolvedBookmark?
    private let courseSecurityScopeStarter: (URL) -> Bool
    private let courseSecurityScopeStopper: (URL) -> Void
    private let courseProjectMutationHook: (CourseProjectMutationStage) throws -> Void
    private let notebookMarkdownReader: (URL) throws -> String
    private let notebookMarkdownWriter: (String, URL) throws -> Void
    private let notebookFileMover: (URL, URL) throws -> Void
    private let courseFileSourceRemover: @Sendable (URL) throws -> Void
    private let contentSourceTrashMover: @Sendable (URL) throws -> URL
    private let workspaceSnapshotWriter: (Data, URL) throws -> Void
    private let coursePortableStateWriter:
        (
            Data,
            URL,
            ImportedFileIdentity,
            Data?,
            () throws -> Void
        ) throws -> Void
    private let selectionAskThreadDefaults: UserDefaults
    private let piRuntime: PiAgentRuntime
    private let courseDocumentSearchIndex: CourseDocumentSearchIndex
    private var activeAgentRequestID: UUID?
    private var activeAgentReplyMessageID: UUID?
    private var latestAgentStreamingText = ""
    private var lastAgentStreamingPublishNanoseconds: UInt64 = 0
    private var agentReplyIDsThatDisplayedStreamingText: Set<UUID> = []
    private var activeAgentReplyChatID: UUID?
    private var agentRequestTask: Task<Void, Never>?
#if DEBUG
    private var capturesAgentRequestForSelfCheck = false
    private var selfCheckCapturedAgentRequest: StudyAgentRequest?
#endif
    private var agentStopTask: Task<Void, Never>?
    private var pendingAgentSwitchTargetID: UUID?
    private var agentDraftsBySessionID: [UUID: String] = [:]
    /// Session-local proof for the one allowed course-home reuse case.
    /// Deliberately not persisted: reopening the App makes an old empty Chat non-fresh.
    private var freshlyCreatedEmptyStudySessionID: UUID?
    private var agentContextRevision: UInt64 = 0
    private var coursePortableStateRevisions: [UUID: UInt64] = [:]
    private var coursePortableStateDigests: [UUID: String] = [:]
    private var dirtyPortableCourseIDs = Set<UUID>()
    private var blockedPortableCourseIDs = Set<UUID>()
    private var oversizedPortableCourseIDs = Set<UUID>()
    private var persistedWorkspaceCourseIDs = Set<UUID>()
    private var needsPortableCourseStateBootstrap = false
    @Published private var validatedAgentReplySourceIDs = Set<UUID>()
    private var lastAgentReplyContextRevision: UInt64?
    private var latestAgentLearningUpdateQuestion: String?
    private var stagedNoteDraft: (itemID: String, value: String)?
    private var isRestoringNavigation = false
    private var lastSelectionAttachmentDate: Date?
    private var lastSelectionUpdateDate: Date?
    private var pendingSelectionAttachmentTask: Task<Void, Never>?
    private var needsSelectionAskThreadsWorkspaceMigration = false
    private var shouldRemoveLegacySelectionAskThreadsAfterSave = false
    private var loadedSelectionAskThreadsFromWorkspaceSnapshot = false
    private var recoveredInterruptedAgentReply = false
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
    /// Owns the single capture → file-worker → apply loop. New generations
    /// join this task instead of capturing an obsolete CAS baseline in parallel.
    private var workspacePersistenceTask: Task<Bool, Never>?
    private var workspacePersistenceSkippingCourseIDs = Set<UUID>()
    private var workspaceSaveGeneration: UInt64 = 0
    private var lastWorkspacePersistenceRanOnMainThread: Bool?
    private var courseHomePerformanceNavigationSpan: WeiBeiPerf.Span?
    private let workspaceSaveDebounceNanoseconds: UInt64 = 280_000_000
    private var noteSourceLinksMigrationVersion = 0
    private var studySessionScopeMigrationVersion = 0
    private var learningMemoryScopeMigrationVersion = 0
    private var isRestoringCourseResumePoint = true
    private var legacyLearningMemoryEntries: [LearningMemoryEntry] = []
    private var legacyLearningMemoryRevision: UInt64 = 0
    private var noteSourceRelationIndex = NoteSourceRelationIndex(links: [])
    private var courseMembershipIndex = CourseItemMemberships()
    private var courseWorkspaceReturnFocus: PaneFocus?
    private var activeCourseSecurityScopes: [String: URL] = [:]
    private var activeCourseSecurityScopeOwnerTokens: [String: UUID] = [:]
    private var activeCourseRebindTokens: [UUID: UUID] = [:]
    private var activeCourseRemovalTokens: [UUID: UUID] = [:]
    private var activeCourseRemovalTransactionID: UUID?
    private var activeCourseFileMutationCounts: [UUID: Int] = [:]
    private var workspacePersistenceRemovingCourseID: UUID?
    private var workspaceRemovalCommitObserved = false
#if DEBUG
    private var usesBackgroundWorkspacePersistenceForSelfCheck = false
#endif
    private var pendingCourseRemovalRecovery:
        PendingCourseRemovalJournal?
    private var resolvedCourseRootURLs: [UUID: URL] = [:]
    private var courseRootUnavailableReasons: [UUID: String] = [:]
    private let courseProjectFileWorker = CourseProjectFileWorker()
    private var courseReconciliationTask: Task<Void, Never>?
    private var courseReconciliationInFlight = false
    private var lastCourseReconciliationLookupCount = 0

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
        var memoryText: String?
        var grants: [AgentFileGrant]
    }

    private struct CourseContextBuildResult: Sendable {
        var context: StudyAgentCourseContext
    }

    private struct AgentHostToolSource: Sendable {
        var item: StudyItem
        var projectItem: StudyAgentProjectItem
        var title: String
        var subtitle: String
        var kind: String
        var role: String
        var memoryText: String?
        var relativePath: String?
        var courseIDs: [String]
        var courseTitles: [String]
        var grants: [AgentFileGrant]
    }

    private struct AgentFileGrant: Sendable {
        var courseID: UUID
        var courseTitle: String
        var rootURL: URL
        var rootIdentity: ImportedFileIdentity
        var entryURL: URL
        var entryIdentity: ImportedFileIdentity
        var targetURL: URL
        var targetIdentity: ImportedFileIdentity
        var relativePath: String
        var isShared: Bool
    }

    private struct AgentProjectAccessSnapshot: Sendable {
        var scope: StudyAgentProjectScope
        var sources: [AgentHostToolSource]
    }

    private struct AgentConversationTarget: Sendable {
        var sessionID: UUID
        var workingDirectory: URL
        var courseID: UUID?
        var courseRootURL: URL? = nil
        var courseRootIdentity: ImportedFileIdentity?
    }

    struct AgentConversationTargetError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func userFacingAgentFailureDetail(for error: Error) -> String? {
        guard let targetError = error as? AgentConversationTargetError else {
            return nil
        }
        let message = targetError.message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return message.isEmpty ? nil : message
    }

    private struct ResolvedImportedFileBookmark {
        var url: URL
        var isStale: Bool
    }

    private struct TransactionDirectoryFingerprint: Equatable {
        struct Entry: Equatable {
            enum Kind: Equatable {
                case directory
                case regularFile
            }

            var kind: Kind
            var identity: ImportedFileIdentity
            var data: Data?
        }

        var rootIdentity: ImportedFileIdentity
        var entriesByRelativePath: [String: Entry]
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

    private struct PendingCourseRemovalJournal: Codable {
        enum Stage: String, Codable {
            case prepared
            case isolated
            case trashed
            case workspaceCommitted
        }

        var transactionID: UUID
        var courseID: UUID
        var expectedCourse: Course
        var rootPath: String
        var rootIdentity: ImportedFileIdentity
        var isolationPath: String?
        var trashBookmarkData: Data?
        var trashPath: String?
        var stage: Stage
    }

    private struct PendingCourseFileTransactionJournal: Codable, Sendable {
        enum Stage: String, Codable, Sendable {
            case prepared
            case staged
            case replacementPreparing
            case replacementRollbackReserved
            case replacementIsolated
            case replacementRollbackPrepared
            case replacementTrashed
            case placed
            case workspaceCommitted
            case sourceCleanupPending
        }

        var transactionID: UUID
        var transactionDirectoryIdentity: ImportedFileIdentity
        var courseID: UUID
        var role: CourseOwnedFileRole
        var itemID: String
        var retiredSourceItemID: String?
        var sourcePath: String?
        var sourceQuarantinePath: String?
        var sourceIdentity: ImportedFileIdentity?
        var sourceSnapshot: CourseFileSnapshot
        var targetRelativePath: String
        var destinationDirectoryIdentity: ImportedFileIdentity
        var stagedIdentity: ImportedFileIdentity?
        var targetIdentity: ImportedFileIdentity?
        var replacedTargetIdentity: ImportedFileIdentity?
        var replacedTargetSnapshot: CourseFileSnapshot?
        var replacedRollbackIdentity: ImportedFileIdentity?
        var replacedTrashPath: String?
        var stage: Stage
    }

    private struct PendingCourseMarkdownWriteJournal: Codable, Sendable {
        enum Stage: String, Codable, Sendable {
            case prepared
            case staged
            case targetIsolated
            case placed
        }

        var transactionID: UUID
        var transactionDirectoryIdentity: ImportedFileIdentity
        var courseID: UUID
        var itemID: String
        var targetPath: String
        var targetRelativePath: String
        var targetIdentity: ImportedFileIdentity
        var targetSnapshot: CourseFileSnapshot
        var replacementSnapshot: CourseFileSnapshot
        var stagedIdentity: ImportedFileIdentity?
        var stage: Stage
    }

    private struct CourseMarkdownWriteTransaction {
        var result: CourseMarkdownWriteResult
        var journal: PendingCourseMarkdownWriteJournal
        var transactionDirectory: URL
    }

    private struct CourseRecoveryInput: Sendable {
        var courseID: UUID
        var root: URL
        var libraryRoot: URL?
        var courseRootsByID: [UUID: URL]
        var importedItems: [StudyItem]
        var memberships: [CourseItemMembership]
    }

    private struct PendingSharedFileTransactionJournal: Codable, Sendable {
        enum Stage: String, Codable, Sendable {
            case prepared
            case linksPreparing
            case sharedPlaced
            case linksPrepared
            case linksPlaced
            case workspaceCommitted
        }

        var transactionID: UUID
        var transactionDirectoryIdentity: ImportedFileIdentity
        var itemID: String
        var ownerCourseID: UUID
        var addedCourseID: UUID
        var sourcePath: String
        var sourceRelativePath: String
        var sourceIdentity: ImportedFileIdentity
        var sourceSnapshot: CourseFileSnapshot
        var sourceQuarantinePath: String
        var sharedPath: String
        var sharedRelativePath: String
        var sharedPayloadPath: String?
        var sharedIdentity: ImportedFileIdentity?
        var ownerLinkIdentity: ImportedFileIdentity?
        var addedLinkPath: String
        var addedLinkRelativePath: String
        var addedLinkIdentity: ImportedFileIdentity?
        var stage: Stage
    }

    private struct PendingSharedLinkRemovalJournal: Codable, Sendable {
        enum Stage: String, Codable, Sendable {
            case prepared
            case linkIsolated
            case workspaceCommitted
        }

        var transactionID: UUID
        var transactionDirectoryIdentity: ImportedFileIdentity
        var itemID: String
        var courseID: UUID
        var sharedPath: String
        var sharedRelativePath: String
        var sharedIdentity: ImportedFileIdentity
        var sharedSnapshot: CourseFileSnapshot
        var linkPath: String
        var linkRelativePath: String
        var linkIdentity: ImportedFileIdentity
        var stage: Stage
    }

    private struct PendingSharedLinkTransactionJournal: Codable, Sendable {
        enum Stage: String, Codable, Sendable {
            case prepared
            case linkPreparing
            case linkPlaced
            case workspaceCommitted
        }

        var transactionID: UUID
        var transactionDirectoryIdentity: ImportedFileIdentity
        var itemID: String
        var courseID: UUID
        var sharedPath: String
        var sharedRelativePath: String
        var sharedIdentity: ImportedFileIdentity
        var sharedSnapshot: CourseFileSnapshot
        var linkPath: String
        var linkRelativePath: String
        var linkIdentity: ImportedFileIdentity?
        var stage: Stage
    }

    private struct RecoveredCourseFileTarget: Sendable {
        var journal: PendingCourseFileTransactionJournal
        var targetURL: URL
        var targetIdentity: ImportedFileIdentity
        var metadata: CourseFileSourceInfo
    }

    private struct CreatedManagedCourseRoot {
        var root: URL
        var relativePath: String
        var identity: ImportedFileIdentity
        var fingerprint: TransactionDirectoryFingerprint
    }

    private var lastUsableAgentAnswer: AgentMessage? {
        return messages.last { $0.isUsableAgentAnswer }
    }

    private static let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private static let legacySelectionAskThreadsDefaultsKey = "weibei.selectionAskThreads.v1"

    convenience init() {
        let folder = Self.workspaceRootDirectory()
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBei", isDirectory: true)
        self.init(
            workspaceDirectory: folder,
            startsAtBlankEntries: true
        )
    }

    init(
        workspaceDirectory folder: URL,
        importedFileIdentityResolver: @escaping (URL) -> ImportedFileIdentity? = WorkspaceStore.resolveImportedFileIdentity,
        courseRootBookmarkMaker: @escaping (URL) -> Data? = WorkspaceStore.makeImportedFileBookmark,
        courseRootBookmarkResolver: @escaping (Data) -> CourseProjectResolvedBookmark? = WorkspaceStore.resolveCourseProjectBookmark,
        courseSecurityScopeStarter: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        courseSecurityScopeStopper: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
        courseProjectMutationHook: @escaping (CourseProjectMutationStage) throws -> Void = { _ in },
        notebookMarkdownReader: @escaping (URL) throws -> String = WorkspaceStore.readNotebookMarkdown,
        notebookMarkdownWriter: @escaping (String, URL) throws -> Void = WorkspaceStore.writeNotebookMarkdown,
        notebookFileMover: @escaping (URL, URL) throws -> Void = WorkspaceStore.moveNotebookFile,
        courseFileSourceRemover: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        },
        contentSourceTrashMover: @escaping @Sendable (URL) throws -> URL = {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(
                at: $0,
                resultingItemURL: &trashedURL
            )
            guard let trashedURL else {
                throw ContentSourceRemovalError.trashMoveFailed
            }
            return trashedURL as URL
        },
        workspaceSnapshotWriter: @escaping (Data, URL) throws -> Void = WorkspaceStore.writeWorkspaceSnapshot,
        coursePortableStateWriter: @escaping (
            Data,
            URL,
            ImportedFileIdentity,
            Data?,
            () throws -> Void
        ) throws -> Void = CourseProjectFileWorker.writePortableState,
        selectionAskThreadDefaults: UserDefaults = .standard,
        startsAtBlankEntries: Bool = false
    ) {
        workspaceDirectory = folder.standardizedFileURL
        storageURL = folder.appendingPathComponent("workspace.json")
        notebookRenameJournalURL = folder.appendingPathComponent("pending-notebook-rename.json")
        courseRemovalJournalURL = folder.appendingPathComponent(
            "pending-course-removal.json"
        )
        self.importedFileIdentityResolver = importedFileIdentityResolver
        self.courseRootBookmarkMaker = courseRootBookmarkMaker
        self.courseRootBookmarkResolver = courseRootBookmarkResolver
        self.courseSecurityScopeStarter = courseSecurityScopeStarter
        self.courseSecurityScopeStopper = courseSecurityScopeStopper
        self.courseProjectMutationHook = courseProjectMutationHook
        self.notebookMarkdownReader = notebookMarkdownReader
        self.notebookMarkdownWriter = notebookMarkdownWriter
        self.notebookFileMover = notebookFileMover
        self.courseFileSourceRemover = courseFileSourceRemover
        self.contentSourceTrashMover = contentSourceTrashMover
        self.workspaceSnapshotWriter = workspaceSnapshotWriter
        self.coursePortableStateWriter = coursePortableStateWriter
        self.selectionAskThreadDefaults = selectionAskThreadDefaults
        piRuntime = PiAgentRuntime(runtimeDirectory: folder.appendingPathComponent("AgentRuntime", isDirectory: true))
        let courseIndexDirectory = folder.appendingPathComponent("CourseIndex", isDirectory: true)
        Self.removeLegacyCourseIndex(in: courseIndexDirectory)
        courseDocumentSearchIndex = CourseDocumentSearchIndex(
            databaseURL: courseIndexDirectory.appendingPathComponent("course-search-v3.sqlite3")
        )
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        loadLegacySelectionAskThreadsIfWorkspaceFieldMissing()
        let restoredCourseProjectRoots = restoreCourseProjectRoots()
        let restoredPortableCourseStates = restorePortableCourseStates()
        let recoveredPendingCourseRemoval =
            recoverPendingCourseRemovalIfNeeded()
        if WeiBeiSafetyTestMode.isEnabled {
            recoverPendingCourseFileTransactions()
        }
        WeiBeiThemeRuntime.mode = appearanceMode
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
        let migratedStudySessionScopes = migrateLegacyStudySessionScopes()
        let migratedLearningMemoryScopes = migrateLegacyLearningMemoryScopes()
        let sanitizedCourseResumePoints = sanitizeCourseResumePoints()
        let initializedCourseKnowledgeProfiles = ensureCourseKnowledgeProfiles()
        courseDocumentSearchIndex.synchronize(allItems)
        if startsAtBlankEntries {
            resetPrimaryEntriesForLaunch()
        }
        ensureActiveStudySession(preferFresh: startsAtBlankEntries)
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
                    || sanitizedCourseLibrary
                    || migratedStudySessionScopes
                    || migratedLearningMemoryScopes
                    || sanitizedCourseResumePoints
                    || restoredCourseProjectRoots
                    || restoredPortableCourseStates
                    || initializedCourseKnowledgeProfiles
                    || recoveredPendingCourseRemoval
                    || needsPortableCourseStateBootstrap
                    || recoveredInterruptedAgentReply
                    || needsSelectionAskThreadsWorkspaceMigration {
            savedInitializationChanges = save()
        } else {
            savedInitializationChanges = true
        }
        if recoveredPendingNotebookRename, savedInitializationChanges {
            removePendingNotebookRenameJournal()
        }
        floatingSelectionPrompt = ui("当前选区", "Current selection")
        if selectedItemID != nil {
            restoreCurrentStudyLocation()
            recordCurrentStudyLocation(incrementVisit: false)
        }
        isRestoringCourseResumePoint = false
        startCourseFileMaintenance()
    }

    deinit {
        courseReconciliationTask?.cancel()
        courseNoteLoadTasksByItemID.values.forEach { $0.cancel() }
        courseNoteWriteTasksByItemID.values.forEach { $0.cancel() }
        for url in activeCourseSecurityScopes.values {
            courseSecurityScopeStopper(url)
        }
    }

    var allItems: [StudyItem] {
        importedItems
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

    var courseWorkspaceCourse: Course? {
        guard let courseWorkspaceCourseID else { return nil }
        return courses.first { $0.id == courseWorkspaceCourseID }
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

    func courseResumePoint(for courseID: UUID) -> CourseResumePoint? {
        courseResumePoints
            .filter { $0.courseID == courseID }
            .sorted { $0.savedAt > $1.savedAt }
            .compactMap(validatedCourseResumePoint)
            .first
    }

    private func validatedCourseResumePoint(
        _ point: CourseResumePoint
    ) -> CourseResumePoint? {
        guard courses.contains(where: { $0.id == point.courseID }) else {
            return nil
        }
        var result = point
        if let itemID = result.materialLocation?.itemID,
           !importedItems.contains(where: {
               $0.id == itemID
                   && !$0.isNotebookNote
                   && courseMembershipIndex.courseIDs(for: itemID).contains(point.courseID)
           }) {
            result.materialLocation = nil
        }
        if let chatID = result.chatID,
           !studySessions.contains(where: {
               $0.id == chatID
                   && $0.courseID == point.courseID
                   && $0.scopeNeedsReview == false
                   && !$0.messages.isEmpty
           }) {
            result.chatID = nil
        }
        if let noteItemID = result.noteItemID,
           !importedItems.contains(where: {
               $0.id == noteItemID
                   && $0.isNotebookNote
                   && courseMembershipIndex.courseIDs(for: noteItemID).contains(point.courseID)
           }) {
            result.noteItemID = nil
        }
        return result.materialLocation == nil
            && result.chatID == nil
            && result.noteItemID == nil
            ? nil
            : result
    }

    @discardableResult
    private func sanitizeCourseResumePoints() -> Bool {
        let sanitized = sanitizedCourseResumePoints()
        guard sanitized != courseResumePoints else { return false }
        courseResumePoints = sanitized
        return true
    }

    private func sanitizedCourseResumePoints() -> [CourseResumePoint] {
        var sanitized: [CourseResumePoint] = []
        for courseID in Set(courseResumePoints.map(\.courseID)) {
            if let point = courseResumePoint(for: courseID) {
                sanitized.append(point)
            }
        }
        sanitized.sort { $0.courseID.uuidString < $1.courseID.uuidString }
        return sanitized
    }

    func studyLocation(
        for itemID: String,
        in courseID: UUID?
    ) -> StudyLocation? {
        guard let courseID,
              courseMembershipIndex.courseIDs(for: itemID).contains(courseID) else {
            return studyLocationsByItemID[itemID]
        }
        if let location = studyLocationsByCourseID[courseID.uuidString]?[itemID] {
            return location
        }
        if let location = courseResumePoint(for: courseID)?.materialLocation,
           location.itemID == itemID {
            return location
        }
        return courseMembershipIndex.courseIDs(for: itemID).count > 1
            ? nil
            : studyLocationsByItemID[itemID]
    }

    @discardableResult
    private func captureCourseResumePoint(
        courseID: UUID,
        materialLocation forcedMaterialLocation: StudyLocation? = nil,
        chatID forcedChatID: UUID? = nil,
        noteItemID forcedNoteItemID: String? = nil
    ) -> Bool {
        guard activeCourseRemovalTokens[courseID] == nil,
              !isRestoringCourseResumePoint,
              courses.contains(where: { $0.id == courseID }) else {
            return false
        }
        let existingPoint = courseResumePoint(for: courseID)
        let activeMaterialLocation: StudyLocation? = selectedMaterialItem.flatMap { item in
            guard courseMembershipIndex.courseIDs(for: item.id).contains(courseID) else {
                return nil
            }
            return studyLocation(for: item.id, in: courseID)
        }
        let activeChatID: UUID? = activeStudySession.flatMap { session in
            guard session.relatedCourseIDs.contains(courseID),
                  !session.messages.isEmpty else {
                return nil
            }
            return session.id
        }
        let activeNoteItemID: String? = activeNoteItem.flatMap { item in
            guard item.isNotebookNote,
                  courseMembershipIndex.courseIDs(for: item.id).contains(courseID) else {
                return nil
            }
            return item.id
        }
        guard let point = validatedCourseResumePoint(
            CourseResumePoint(
                courseID: courseID,
                materialLocation: forcedMaterialLocation
                    ?? activeMaterialLocation
                    ?? existingPoint?.materialLocation,
                chatID: forcedChatID ?? activeChatID ?? existingPoint?.chatID,
                noteItemID: forcedNoteItemID
                    ?? activeNoteItemID
                    ?? existingPoint?.noteItemID
            )
        ) else {
            return false
        }
        courseResumePoints.removeAll { $0.courseID == courseID }
        courseResumePoints.append(point)
        courseResumePoints.sort { $0.courseID.uuidString < $1.courseID.uuidString }
        return true
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

    func selectCourseWorkspaceCourse(_ id: UUID?) {
        courseWorkspaceCourseID = id.flatMap { candidate in
            courses.contains(where: { $0.id == candidate }) ? candidate : nil
        }
    }

    @discardableResult
    func createCourseInLibrary(title rawTitle: String) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.createCourseInLibraryAsync(title: rawTitle)
        }
    }

    @discardableResult
    func createCourseInLibraryAsync(title rawTitle: String) async throws -> UUID {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CourseProjectRootError.emptyTitle }
        guard let libraryRoot = courseLibraryRootURL else {
            throw courseLibraryRootPath == nil
                ? CourseProjectRootError.missingLibrary
                : CourseProjectRootError.unavailableLibrary
        }
        let rawDirectoryName = MarkdownAttachmentStore.safeFileStem(
            title,
            fallback: "",
            limit: 80
        )
        let directoryName = rawDirectoryName.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )
        guard !directoryName.isEmpty else {
            throw CourseProjectRootError.invalidDirectoryName
        }
        return try await createCourseAsync(
            title: title,
            at: libraryRoot.appendingPathComponent(directoryName, isDirectory: true)
        )
    }

    @discardableResult
    func createCourse(title rawTitle: String, at rootURL: URL) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.createCourseAsync(title: rawTitle, at: rootURL)
        }
    }

    @discardableResult
    private func createCourseAsync(
        title rawTitle: String,
        at rootURL: URL
    ) async throws -> UUID {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CourseProjectRootError.emptyTitle }
        guard let libraryRoot = courseLibraryRootURL else {
            throw courseLibraryRootPath == nil
                ? CourseProjectRootError.missingLibrary
                : CourseProjectRootError.unavailableLibrary
        }

        let courseID = UUID()
        let createdRoot = try createManagedCourseRoot(
            courseID: courseID,
            at: rootURL,
            libraryRoot: libraryRoot
        )
        let previousCourses = courses
        let previousCourseKnowledgeProfiles = courseKnowledgeProfiles
        let previousActiveCourseID = activeCourseID

        do {
            let course = Course(
                id: courseID,
                title: title,
                colorIndex: nextCourseColorIndex(),
                sourceRootPath: nil,
                sourceRootRelativePath: createdRoot.relativePath,
                sourceRootIdentity: createdRoot.identity,
                sourceRootBookmarkData: nil
            )
            courses.append(course)
            courseKnowledgeProfiles.append(
                CourseKnowledgeProfile(courseID: course.id)
            )
            activeCourseID = course.id
            resolvedCourseRootURLs[course.id] = createdRoot.root
            courseRootUnavailableReasons.removeValue(forKey: course.id)
            guard await persistWorkspaceNow() else {
                throw CourseProjectRootError.workspaceSaveFailed
            }
            // The first commit registers the new course in workspace.json.
            // Only then may the next generation include its portable state.
            if !(await persistWorkspaceNow()) {
                workspaceSaveError = ui(
                    "课程已创建，但可携带状态尚未写入。",
                    "The course was created, but its portable state has not been written yet."
                )
            }
            return course.id
        } catch {
            courses = previousCourses
            courseKnowledgeProfiles = previousCourseKnowledgeProfiles
            activeCourseID = previousActiveCourseID
            resolvedCourseRootURLs.removeValue(forKey: courseID)
            courseRootUnavailableReasons.removeValue(forKey: courseID)
            safelyRemoveTransactionDirectory(
                at: createdRoot.root,
                expected: createdRoot.fingerprint
            )
            throw error
        }
    }

    private func createManagedCourseRoot(
        courseID: UUID,
        at rootURL: URL,
        libraryRoot: URL
    ) throws -> CreatedManagedCourseRoot {
        let targetRoot = try CourseProjectPathPolicy.newDirectory(rootURL)
        try validateCourseProjectRoot(
            targetRoot,
            identity: nil,
            mustBeInsideLibrary: true
        )
        guard let relativePath = CourseProjectPathPolicy.relativePath(
            of: targetRoot,
            inside: libraryRoot
        ) else {
            throw CourseProjectRootError.rootOutsideLibrary
        }
        let parent = targetRoot.deletingLastPathComponent()
        guard let parentIdentity = importedFileIdentityResolver(parent) else {
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        let stagingRoot = parent.appendingPathComponent(
            ".weibei-course-staging-\(courseID.uuidString.lowercased())",
            isDirectory: true
        )
        var placedRoot = false
        var fingerprint: TransactionDirectoryFingerprint?
        do {
            try FileManager.default.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: false
            )
            guard let stagingIdentity = importedFileIdentityResolver(
                stagingRoot
            ),
            let createdFingerprint = transactionDirectoryFingerprint(
                at: stagingRoot
            ) else {
                throw CourseProjectRootError.rootIdentityUnavailable
            }
            fingerprint = createdFingerprint
            try courseProjectMutationHook(.afterStagingDirectory)
            for directoryName in ["文稿", "笔记", ".weibei"] {
                try FileManager.default.createDirectory(
                    at: stagingRoot.appendingPathComponent(
                        directoryName,
                        isDirectory: true
                    ),
                    withIntermediateDirectories: false
                )
            }
            guard let preparedFingerprint = transactionDirectoryFingerprint(
                at: stagingRoot
            ) else {
                throw CourseProjectRootError.rootIdentityUnavailable
            }
            fingerprint = preparedFingerprint
            try courseProjectMutationHook(.beforeManifestWrite)
            let manifestURL = stagingRoot.appendingPathComponent(
                ".weibei/course.json"
            )
            try CourseProjectManifest(courseID: courseID)
                .encoded()
                .write(to: manifestURL, options: [.atomic])
            let manifest = try CourseProjectManifest.read(from: manifestURL)
            guard manifest.courseID == courseID,
                  manifest.schemaVersion ==
                    CourseProjectManifest.currentSchemaVersion,
                  let completeFingerprint =
                    transactionDirectoryFingerprint(at: stagingRoot) else {
                throw CourseProjectRootError.manifestMismatch
            }
            fingerprint = completeFingerprint
            try courseProjectMutationHook(.beforeAtomicPlacement)
            guard importedFileIdentityResolver(parent) == parentIdentity,
                  !FileManager.default.fileExists(atPath: targetRoot.path)
            else {
                throw CourseProjectRootError.overlappingRoot
            }
            try validateCourseProjectRoot(
                targetRoot,
                identity: nil,
                mustBeInsideLibrary: true
            )
            try FileManager.default.moveItem(at: stagingRoot, to: targetRoot)
            placedRoot = true
            let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(
                targetRoot
            )
            guard let identity = importedFileIdentityResolver(canonicalRoot),
                  identity == stagingIdentity,
                  let finalFingerprint = transactionDirectoryFingerprint(
                    at: canonicalRoot
                  ) else {
                throw CourseProjectRootError.rootIdentityUnavailable
            }
            try validateCourseProjectRoot(
                canonicalRoot,
                identity: identity,
                mustBeInsideLibrary: true
            )
            return CreatedManagedCourseRoot(
                root: canonicalRoot,
                relativePath: relativePath,
                identity: identity,
                fingerprint: finalFingerprint
            )
        } catch {
            if let fingerprint {
                safelyRemoveTransactionDirectory(
                    at: placedRoot ? targetRoot : stagingRoot,
                    expected: fingerprint
                )
            }
            throw error
        }
    }

    func configureCourseLibrary(at rootURL: URL) throws {
        try waitForCourseFileOperation {
            try await self.configureCourseLibraryAsync(at: rootURL)
        }
    }

    func configureCourseLibraryAsync(at rootURL: URL) async throws {
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(rootURL)
        try validateLibraryRoot(canonicalRoot)
        guard let identity = importedFileIdentityResolver(canonicalRoot) else {
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        if let persistedIdentity = courseLibraryRootIdentity,
           persistedIdentity != identity {
            throw CourseProjectRootError.libraryIdentityMismatch
        }
        guard let bookmark = courseRootBookmarkMaker(canonicalRoot) else {
            throw CourseProjectRootError.bookmarkUnavailable
        }
        guard let resolution = courseRootBookmarkResolver(bookmark) else {
            throw CourseProjectRootError.bookmarkResolutionFailed
        }
        let scopedURL = resolution.url
        guard courseSecurityScopeStarter(scopedURL) else {
            throw CourseProjectRootError.securityScopeDenied
        }
        let resolvedRoot: URL
        do {
            resolvedRoot = try CourseProjectPathPolicy.existingDirectory(scopedURL)
            guard importedFileIdentityResolver(resolvedRoot) == identity else {
                throw CourseProjectRootError.bookmarkResolutionFailed
            }
            try await ensureCommonContentDirectories(at: resolvedRoot)
        } catch {
            courseSecurityScopeStopper(scopedURL)
            throw error
        }

        let ownerKey = "library"
        let previousScope = activeCourseSecurityScopes[ownerKey]
        let previousPath = courseLibraryRootPath
        let previousIdentity = courseLibraryRootIdentity
        let previousBookmark = courseLibraryRootBookmarkData
        let previousURL = courseLibraryRootURL
        let previousUnavailableReason = courseLibraryUnavailableReason
        let previousCourses = courses
        let previousResolvedCourseRootURLs = resolvedCourseRootURLs
        let previousCourseRootUnavailableReasons = courseRootUnavailableReasons
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNoteBackingDigests = noteBackingContentDigestsByItemID

        activeCourseSecurityScopes[ownerKey] = scopedURL
        courseLibraryRootPath = resolvedRoot.path
        courseLibraryRootIdentity = identity
        courseLibraryRootBookmarkData = bookmark
        courseLibraryRootURL = resolvedRoot
        courseLibraryUnavailableReason = nil
        _ = restoreCourseReferencesInsideLibrary()
        _ = await migrateLegacySharedMaterials(in: resolvedRoot)
        for course in courses where resolvedCourseRootURLs[course.id] != nil {
            _ = resolveCourseOwnedItems(for: course.id)
        }
        guard await persistWorkspaceNow() else {
            courseSecurityScopeStopper(scopedURL)
            if let previousScope {
                activeCourseSecurityScopes[ownerKey] = previousScope
            } else {
                activeCourseSecurityScopes.removeValue(forKey: ownerKey)
            }
            courseLibraryRootPath = previousPath
            courseLibraryRootIdentity = previousIdentity
            courseLibraryRootBookmarkData = previousBookmark
            courseLibraryRootURL = previousURL
            courseLibraryUnavailableReason = previousUnavailableReason
            courses = previousCourses
            resolvedCourseRootURLs = previousResolvedCourseRootURLs
            courseRootUnavailableReasons = previousCourseRootUnavailableReasons
            importedItems = previousImportedItems
            courseItemMemberships = previousMemberships
            noteBackingContentDigestsByItemID = previousNoteBackingDigests
            throw CourseProjectRootError.workspaceSaveFailed
        }
        let legacyOrganization = await organizeLegacyCourses(
            in: resolvedRoot
        )
        if !legacyOrganization.errors.isEmpty {
            noteFileError = ui(
                "已有 \(legacyOrganization.migrated) 份旧资料完成整理；另有 \(legacyOrganization.errors.count) 份未完成：\(legacyOrganization.errors.first ?? "")",
                "Organized \(legacyOrganization.migrated) legacy item(s); \(legacyOrganization.errors.count) remain: \(legacyOrganization.errors.first ?? "")"
            )
        }
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
        if let previousScope {
            let stopScope = courseSecurityScopeStopper
            let runningLibraryCourseID = activeAgentReplyChatID
                .flatMap { runningChatID in
                    studySessions.first(where: { $0.id == runningChatID })?.courseID
                }
                .flatMap { runningCourseID in
                    course(withID: runningCourseID)?.sourceRootRelativePath != nil
                        ? runningCourseID
                        : nil
                }
            if let runningLibraryCourseID,
               cancelAgentRequestIfRunning(
                   in: runningLibraryCourseID,
                   completion: {
                       stopScope(previousScope)
                   }
               ) {
                // The old scope stays valid until the running PI process has stopped.
            } else {
                courseSecurityScopeStopper(previousScope)
            }
        }
    }

    private func organizeLegacyCourses(
        in libraryRoot: URL
    ) async -> (migrated: Int, errors: [String]) {
        let rootlessCourseIDs = courses.compactMap { course -> UUID? in
            guard course.sourceRootPath == nil,
                  course.sourceRootRelativePath == nil,
                  course.sourceRootIdentity == nil else {
                return nil
            }
            return course.id
        }
        var errors: [String] = []
        var createdRoots: [CreatedManagedCourseRoot] = []
        let previousCourses = courses
        let previousResolvedRoots = resolvedCourseRootURLs

        for courseID in rootlessCourseIDs {
            guard let index = courses.firstIndex(where: {
                $0.id == courseID
            }) else { continue }
            do {
                let target = try availableLegacyCourseRoot(
                    title: courses[index].title,
                    libraryRoot: libraryRoot
                )
                let created = try createManagedCourseRoot(
                    courseID: courseID,
                    at: target,
                    libraryRoot: libraryRoot
                )
                createdRoots.append(created)
                courses[index].sourceRootPath = nil
                courses[index].sourceRootRelativePath =
                    created.relativePath
                courses[index].sourceRootIdentity = created.identity
                courses[index].sourceRootBookmarkData = nil
                courses[index].updatedAt = Date()
                resolvedCourseRootURLs[courseID] = created.root
                courseRootUnavailableReasons.removeValue(forKey: courseID)
            } catch {
                errors.append(
                    "\(courses[index].title)：\(error.localizedDescription)"
                )
            }
        }
        if !createdRoots.isEmpty,
           !(await persistWorkspaceNow()) {
            courses = previousCourses
            resolvedCourseRootURLs = previousResolvedRoots
            for created in createdRoots {
                safelyRemoveTransactionDirectory(
                    at: created.root,
                    expected: created.fingerprint
                )
            }
            return (
                0,
                errors + [CourseProjectRootError.workspaceSaveFailed
                    .localizedDescription]
            )
        }

        let membershipsBeforeMigration = courseItemMemberships
        let legacyItems = importedItems.filter { item in
            guard case .legacyExternal = item.storage else { return false }
            return membershipsBeforeMigration.contains {
                $0.itemID == item.id
            }
        }
        var migrated = 0
        for item in legacyItems {
            let relatedCourseIDs = Set(
                membershipsBeforeMigration.filter {
                    $0.itemID == item.id
                }.map(\.courseID).filter {
                    courseRootURL(for: $0) != nil
                }
            )
            guard !relatedCourseIDs.isEmpty else { continue }
            do {
                try await organizeLegacyItem(
                    item,
                    courseIDs: relatedCourseIDs
                )
                migrated += 1
            } catch {
                errors.append(
                    "\(displayTitle(for: item))：\(error.localizedDescription)"
                )
            }
        }
        return (migrated, errors)
    }

    private func availableLegacyCourseRoot(
        title: String,
        libraryRoot: URL
    ) throws -> URL {
        let rawName = MarkdownAttachmentStore.safeFileStem(
            title,
            fallback: "课程",
            limit: 80
        ).trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: ".")
            )
        )
        guard !rawName.isEmpty else {
            throw CourseProjectRootError.invalidDirectoryName
        }
        for suffix in 1...9_999 {
            let name = suffix == 1 ? rawName : "\(rawName) \(suffix)"
            let candidate = libraryRoot.appendingPathComponent(
                name,
                isDirectory: true
            )
            guard !FileManager.default.fileExists(atPath: candidate.path)
            else { continue }
            if (try? validateCourseProjectRoot(
                candidate,
                identity: nil,
                mustBeInsideLibrary: true
            )) != nil {
                return candidate
            }
        }
        throw CourseProjectRootError.invalidDirectoryName
    }

    private func organizeLegacyItem(
        _ item: StudyItem,
        courseIDs: Set<UUID>
    ) async throws {
        guard let sourceURL = item.url,
              let ownerCourseID = courseIDs.sorted(by: {
                  $0.uuidString < $1.uuidString
              }).first else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let sourceInfo = try await courseProjectFileWorker
            .validatedRegularSource(sourceURL)
        let sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sourceInfo.url,
            expectedIdentity: sourceInfo.identity
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WeiBei-Legacy-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let temporarySource = temporaryDirectory.appendingPathComponent(
            sourceURL.lastPathComponent
        )
        let temporaryIdentity = try await courseProjectFileWorker
            .copyAndVerify(
                from: sourceInfo.url,
                generatedData: nil,
                to: temporarySource,
                expectedSnapshot: sourceSnapshot
            )
        let role: CourseOwnedFileRole = item.isNotebookNote
            ? .note
            : .material
        _ = try await transactCourseOwnedFile(
            courseID: ownerCourseID,
            role: role,
            fileName: sourceURL.lastPathComponent,
            sourceURL: temporarySource,
            sourceIdentity: temporaryIdentity,
            generatedData: nil,
            conflictResolution: .keepBoth(preferredFileName: nil),
            preservingItemID: item.id,
            additionalCourseIDs: courseIDs
        )
        for courseID in courseIDs where courseID != ownerCourseID {
            try await shareCourseOwnedItem(
                itemID: item.id,
                withCourseID: courseID,
                conflictResolution: .keepBoth(preferredFileName: nil)
            )
        }
    }

    @discardableResult
    func adoptCourseFolder(at rootURL: URL, title rawTitle: String) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.adoptCourseFolderAsync(
                at: rootURL,
                title: rawTitle
            )
        }
    }

    @discardableResult
    func adoptCourseFolderAsync(
        at rootURL: URL,
        title rawTitle: String
    ) async throws -> UUID {
        switch try await adoptCourseFolderOrProposeRebindAsync(
            at: rootURL,
            title: rawTitle
        ) {
        case .opened(let courseID):
            return courseID
        case .requiresRebind:
            throw CourseProjectRootError.manifestMismatch
        }
    }

    func adoptCourseFolderOrProposeRebind(
        at rootURL: URL,
        title rawTitle: String
    ) throws -> CourseFolderAdoptionOutcome {
        try waitForCourseFileOperation {
            try await self.adoptCourseFolderOrProposeRebindAsync(
                at: rootURL,
                title: rawTitle
            )
        }
    }

    func adoptCourseFolderOrProposeRebindAsync(
        at rootURL: URL,
        title rawTitle: String
    ) async throws -> CourseFolderAdoptionOutcome {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CourseProjectRootError.emptyTitle }
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(rootURL)
        guard let identity = importedFileIdentityResolver(canonicalRoot) else {
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        if let existing = existingCourse(at: canonicalRoot, identity: identity) {
            return .opened(
                try await refreshAdoptedCourse(
                    existing,
                    at: canonicalRoot,
                    identity: identity
                )
            )
        }

        let libraryRelativePath = courseLibraryRootURL.flatMap {
            CourseProjectPathPolicy.relativePath(of: canonicalRoot, inside: $0)
        }
        var bookmark: Data?
        var resolvedExternalRoot: URL?
        var externalScopeURL: URL?
        if libraryRelativePath == nil {
            guard let madeBookmark = courseRootBookmarkMaker(canonicalRoot) else {
                throw CourseProjectRootError.bookmarkUnavailable
            }
            guard let resolution = courseRootBookmarkResolver(madeBookmark) else {
                throw CourseProjectRootError.bookmarkResolutionFailed
            }
            let scopedURL = resolution.url
            guard courseSecurityScopeStarter(scopedURL) else {
                throw CourseProjectRootError.securityScopeDenied
            }
            let resolved: URL
            do {
                resolved = try CourseProjectPathPolicy.existingDirectory(scopedURL)
                guard importedFileIdentityResolver(resolved) == identity else {
                    throw CourseProjectRootError.bookmarkResolutionFailed
                }
            } catch {
                courseSecurityScopeStopper(scopedURL)
                throw error
            }
            bookmark = madeBookmark
            resolvedExternalRoot = resolved
            externalScopeURL = scopedURL
        }

        let metadataURL = canonicalRoot.appendingPathComponent(".weibei", isDirectory: true)
        let manifestURL = metadataURL.appendingPathComponent("course.json")
        var createdMetadata = false
        var createdMetadataFingerprint: TransactionDirectoryFingerprint?
        var adoptionSnapshot: CoursePortableAdoptionSnapshot?
        let courseID: UUID
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let metadataValues = try? metadataURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            guard metadataValues?.isDirectory == true,
                  metadataValues?.isSymbolicLink != true,
                  metadataValues?.isAliasFile != true,
                  !CourseProjectFileWorker.isSymbolicLink(at: metadataURL),
                  CourseProjectPathPolicy.isSame(
                    metadataURL,
                    metadataURL.resolvingSymlinksInPath()
                  ),
                  importedFileIdentityResolver(canonicalRoot) == identity else {
                if let externalScopeURL { courseSecurityScopeStopper(externalScopeURL) }
                throw CourseProjectRootError.metadataConflict
            }
            do {
                let snapshot = try await courseProjectFileWorker
                    .adoptionSnapshot(
                        at: canonicalRoot,
                        expectedRootIdentity: identity
                    )
                adoptionSnapshot = snapshot
                courseID = snapshot.manifest.courseID
            } catch {
                if let externalScopeURL {
                    courseSecurityScopeStopper(externalScopeURL)
                }
                throw CourseProjectRootError.metadataConflict
            }
            if let existing = courses.first(where: { $0.id == courseID }) {
                do {
                    try validateCourseProjectRoot(
                        canonicalRoot,
                        identity: identity,
                        mustBeInsideLibrary: false,
                        excludingCourseID: existing.id
                    )
                    guard let adoptionSnapshot else {
                        throw CourseProjectRootError.manifestMismatch
                    }
                    let proposal = try await makeCourseProjectRebindProposal(
                        existing: existing,
                        candidateRoot: canonicalRoot,
                        candidateRootIdentity: identity,
                        snapshot: adoptionSnapshot
                    )
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    return .requiresRebind(proposal)
                } catch {
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    throw error
                }
            }
            try validateCourseProjectRoot(
                canonicalRoot,
                identity: identity,
                mustBeInsideLibrary: false
            )
        } else {
            try validateCourseProjectRoot(
                canonicalRoot,
                identity: identity,
                mustBeInsideLibrary: false
            )
            courseID = UUID()
            let stagedMetadataURL = canonicalRoot.appendingPathComponent(
                ".weibei-adopt-staging-\(courseID.uuidString.lowercased())",
                isDirectory: true
            )
            do {
                guard importedFileIdentityResolver(canonicalRoot) == identity else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                try FileManager.default.createDirectory(at: stagedMetadataURL, withIntermediateDirectories: false)
                guard let emptyFingerprint = transactionDirectoryFingerprint(at: stagedMetadataURL) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                createdMetadataFingerprint = emptyFingerprint
                try CourseProjectManifest(courseID: courseID)
                    .encoded()
                    .write(
                        to: stagedMetadataURL.appendingPathComponent("course.json"),
                        options: [.atomic]
                    )
                guard let completeFingerprint = transactionDirectoryFingerprint(at: stagedMetadataURL) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                createdMetadataFingerprint = completeFingerprint
                guard importedFileIdentityResolver(canonicalRoot) == identity,
                      !FileManager.default.fileExists(atPath: metadataURL.path) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                try FileManager.default.moveItem(at: stagedMetadataURL, to: metadataURL)
                createdMetadata = true
                guard importedFileIdentityResolver(canonicalRoot) == identity,
                      !CourseProjectFileWorker.isSymbolicLink(at: metadataURL),
                      CourseProjectPathPolicy.isSame(
                        metadataURL,
                        metadataURL.resolvingSymlinksInPath()
                ) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
            } catch {
                if let createdMetadataFingerprint {
                    safelyRemoveTransactionDirectory(
                        at: createdMetadata ? metadataURL : stagedMetadataURL,
                        expected: createdMetadataFingerprint
                    )
                }
                if let externalScopeURL { courseSecurityScopeStopper(externalScopeURL) }
                throw error
            }
        }

        let previousCourses = courses
        let previousActiveCourseID = activeCourseID
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNoteSourceLinks = noteSourceLinks
        let previousCourseStudyLocations = studyLocationsByCourseID
        let previousCourseResumePoints = courseResumePoints
        let previousLearningMemoryStates = learningMemoryStates
        let previousCourseKnowledgeProfiles = courseKnowledgeProfiles
        let previousStudySessions = studySessions
        let previousActiveStudySessionID = activeStudySessionID
        let previousMessages = messages
        let previousNotesByItemID = notesByItemID
        let previousPendingNoteWrites = pendingNoteWritesByItemID
        let previousNoteBackingDigests =
            noteBackingContentDigestsByItemID
        let previousPortableRevisions = coursePortableStateRevisions
        let previousPortableDigests = coursePortableStateDigests
        let previousDirtyPortableCourses = dirtyPortableCourseIDs
        let previousBlockedPortableCourses = blockedPortableCourseIDs
        let previousOversizedPortableCourses =
            oversizedPortableCourseIDs
        let previousPortableBootstrap =
            needsPortableCourseStateBootstrap
        guard importedFileIdentityResolver(canonicalRoot) == identity else {
            if let externalScopeURL { courseSecurityScopeStopper(externalScopeURL) }
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        let course = Course(
            id: courseID,
            title: title,
            colorIndex: nextCourseColorIndex(),
            sourceRootPath: libraryRelativePath == nil ? canonicalRoot.path : nil,
            sourceRootRelativePath: libraryRelativePath,
            sourceRootIdentity: identity,
            sourceRootBookmarkData: bookmark
        )
        courses.append(course)
        courseKnowledgeProfiles.append(
            CourseKnowledgeProfile(courseID: course.id)
        )
        activeCourseID = course.id
        resolvedCourseRootURLs[course.id] = resolvedExternalRoot ?? canonicalRoot
        courseRootUnavailableReasons.removeValue(forKey: course.id)
        if let externalScopeURL {
            activeCourseSecurityScopes["course:\(course.id.uuidString)"] = externalScopeURL
        }
        do {
            if let portableStateData = adoptionSnapshot?.portableStateData {
                let state = try JSONDecoder()
                    .decode(
                        CoursePortableState.self,
                        from: portableStateData
                    )
                    .validated(expectedCourseID: courseID)
                try applyCoursePortableState(state, courseID: courseID)
                coursePortableStateRevisions[courseID] = state.revision
                coursePortableStateDigests[courseID] =
                    try coursePortableStatePayloadDigest(state)
            } else {
                needsPortableCourseStateBootstrap = true
            }
            guard await persistWorkspaceNow() else {
                throw CourseProjectRootError.workspaceSaveFailed
            }
        } catch {
            courses = previousCourses
            activeCourseID = previousActiveCourseID
            importedItems = previousImportedItems
            courseItemMemberships = previousMemberships
            noteSourceLinks = previousNoteSourceLinks
            studyLocationsByCourseID = previousCourseStudyLocations
            courseResumePoints = previousCourseResumePoints
            learningMemoryStates = previousLearningMemoryStates
            courseKnowledgeProfiles = previousCourseKnowledgeProfiles
            studySessions = previousStudySessions
            activeStudySessionID = previousActiveStudySessionID
            messages = previousMessages
            notesByItemID = previousNotesByItemID
            pendingNoteWritesByItemID = previousPendingNoteWrites
            noteBackingContentDigestsByItemID =
                previousNoteBackingDigests
            coursePortableStateRevisions = previousPortableRevisions
            coursePortableStateDigests = previousPortableDigests
            dirtyPortableCourseIDs = previousDirtyPortableCourses
            blockedPortableCourseIDs = previousBlockedPortableCourses
            oversizedPortableCourseIDs =
                previousOversizedPortableCourses
            needsPortableCourseStateBootstrap =
                previousPortableBootstrap
            resolvedCourseRootURLs.removeValue(forKey: course.id)
            courseRootUnavailableReasons.removeValue(forKey: course.id)
            if let externalScopeURL {
                activeCourseSecurityScopes.removeValue(forKey: "course:\(course.id.uuidString)")
                courseSecurityScopeStopper(externalScopeURL)
            }
            if createdMetadata,
               importedFileIdentityResolver(canonicalRoot) == identity,
               let createdMetadataFingerprint {
                safelyRemoveTransactionDirectory(
                    at: metadataURL,
                    expected: createdMetadataFingerprint
                )
            }
            throw error
        }
        try courseProjectMutationHook(
            .afterAdoptionWorkspaceSaveBeforeManifestNormalization
        )
        if let adoptionSnapshot,
           adoptionSnapshot.manifest.portableExport != nil {
            do {
                let confirmedSnapshot = try await courseProjectFileWorker
                    .adoptionSnapshot(
                        at: canonicalRoot,
                        expectedRootIdentity: identity
                    )
                guard confirmedSnapshot.metadataIdentity
                        == adoptionSnapshot.metadataIdentity,
                      confirmedSnapshot.manifestData
                        == adoptionSnapshot.manifestData,
                      confirmedSnapshot.portableStateData
                        == adoptionSnapshot.portableStateData,
                      confirmedSnapshot.completionData
                        == adoptionSnapshot.completionData,
                      confirmedSnapshot.manifest.portableExport != nil else {
                    throw CourseProjectRootError.manifestMismatch
                }
                let normalizedData = try CourseProjectManifest(
                    courseID: courseID
                ).encoded()
                try await courseProjectFileWorker
                    .normalizePortableCourseManifest(
                        with: normalizedData,
                        at: manifestURL,
                        expectedDirectoryIdentity:
                            confirmedSnapshot.metadataIdentity,
                        expectedPreviousData:
                            confirmedSnapshot.manifestData
                    )
            } catch {
                let isolatedNoteItemIDs =
                    importedItems.compactMap { item -> String? in
                        guard item.isNotebookNote,
                              case .courseOwned(
                                  let ownerCourseID
                              ) = item.storage,
                              ownerCourseID == course.id else {
                            return nil
                        }
                        return item.id
                    }
                for itemID in isolatedNoteItemIDs {
                    courseNoteLoadGenerationByItemID[
                        itemID,
                        default: 0
                    ] &+= 1
                    courseNoteLoadTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWriteTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWritesInFlight.remove(itemID)
                }
                resolvedCourseRootURLs.removeValue(
                    forKey: course.id
                )
                courseRootUnavailableReasons[course.id] =
                    error.localizedDescription
                let scopeKey =
                    "course:\(course.id.uuidString)"
                if let scopedURL =
                    activeCourseSecurityScopes.removeValue(
                        forKey: scopeKey
                    ) {
                    let stopScope = courseSecurityScopeStopper
                    if !cancelAgentRequestIfRunning(
                        in: course.id,
                        completion: {
                            stopScope(scopedURL)
                        }
                    ) {
                        stopScope(scopedURL)
                    }
                } else {
                    cancelAgentRequestIfRunning(in: course.id)
                }
                invalidateAgentContext()
                throw error
            }
        }
        if !(await persistWorkspaceNow()) {
            workspaceSaveError = ui(
                "课程已登记，但可携带状态尚未写入。",
                "The course was registered, but its portable state has not been written yet."
            )
        }
        if !WeiBeiSafetyTestMode.isEnabled {
            Task { @MainActor [weak self] in
                await self?.reconcileCourseFilesNow(courseID: course.id)
            }
        }
        return .opened(course.id)
    }

    @discardableResult
    private func refreshAdoptedCourse(
        _ existing: Course,
        at canonicalRoot: URL,
        identity: ImportedFileIdentity
    ) async throws -> UUID {
        guard activeCourseRebindTokens[existing.id] == nil,
              activeCourseRemovalTokens[existing.id] == nil else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard let courseIndex = courses.firstIndex(where: { $0.id == existing.id }) else {
            throw CourseProjectRootError.rootAlreadyRegistered
        }
        if existing.sourceRootRelativePath != nil,
           courseLibraryRootPath != nil,
           courseLibraryRootURL == nil {
            throw CourseProjectRootError.unavailableLibrary
        }

        let libraryRelativePath = courseLibraryRootURL.flatMap {
            CourseProjectPathPolicy.relativePath(of: canonicalRoot, inside: $0)
        }
        var refreshedBookmark: Data?
        var resolvedRoot = canonicalRoot
        var newScopeURL: URL?
        if libraryRelativePath == nil {
            guard let bookmark = courseRootBookmarkMaker(canonicalRoot) else {
                throw CourseProjectRootError.bookmarkUnavailable
            }
            guard let resolution = courseRootBookmarkResolver(bookmark) else {
                throw CourseProjectRootError.bookmarkResolutionFailed
            }
            let scopedURL = resolution.url
            guard courseSecurityScopeStarter(scopedURL) else {
                throw CourseProjectRootError.securityScopeDenied
            }
            do {
                resolvedRoot = try CourseProjectPathPolicy.existingDirectory(scopedURL)
                guard importedFileIdentityResolver(resolvedRoot) == identity else {
                    throw CourseProjectRootError.bookmarkResolutionFailed
                }
            } catch {
                courseSecurityScopeStopper(scopedURL)
                throw error
            }
            refreshedBookmark = bookmark
            newScopeURL = scopedURL
        }

        do {
            try await validateRestoredCourseRootAsync(
                resolvedRoot,
                course: existing,
                mustBeInsideLibrary: libraryRelativePath != nil
            )
        } catch {
            if let newScopeURL { courseSecurityScopeStopper(newScopeURL) }
            throw error
        }

        let scopeKey = "course:\(existing.id.uuidString)"
        let previousCourse = courses[courseIndex]
        let previousResolvedRoot = resolvedCourseRootURLs[existing.id]
        let previousUnavailableReason = courseRootUnavailableReasons[existing.id]
        let previousScope = activeCourseSecurityScopes[scopeKey]
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNoteBackingDigests = noteBackingContentDigestsByItemID

        var refreshedCourse = previousCourse
        refreshedCourse.sourceRootPath = libraryRelativePath == nil ? resolvedRoot.path : nil
        refreshedCourse.sourceRootRelativePath = libraryRelativePath
        refreshedCourse.sourceRootIdentity = identity
        refreshedCourse.sourceRootBookmarkData = refreshedBookmark
        refreshedCourse.updatedAt = Date()
        courses[courseIndex] = refreshedCourse
        resolvedCourseRootURLs[existing.id] = resolvedRoot
        courseRootUnavailableReasons.removeValue(forKey: existing.id)
        if let newScopeURL {
            activeCourseSecurityScopes[scopeKey] = newScopeURL
        } else {
            activeCourseSecurityScopes.removeValue(forKey: scopeKey)
        }
        _ = resolveCourseOwnedItems(for: existing.id)

        guard await persistWorkspaceNow() else {
            courses[courseIndex] = previousCourse
            if let previousResolvedRoot {
                resolvedCourseRootURLs[existing.id] = previousResolvedRoot
            } else {
                resolvedCourseRootURLs.removeValue(forKey: existing.id)
            }
            if let previousUnavailableReason {
                courseRootUnavailableReasons[existing.id] = previousUnavailableReason
            } else {
                courseRootUnavailableReasons.removeValue(forKey: existing.id)
            }
            if let previousScope {
                activeCourseSecurityScopes[scopeKey] = previousScope
            } else {
                activeCourseSecurityScopes.removeValue(forKey: scopeKey)
            }
            importedItems = previousImportedItems
            courseItemMemberships = previousMemberships
            noteBackingContentDigestsByItemID = previousNoteBackingDigests
            if let newScopeURL { courseSecurityScopeStopper(newScopeURL) }
            throw CourseProjectRootError.workspaceSaveFailed
        }

        if let previousScope {
            let stopScope = courseSecurityScopeStopper
            if !cancelAgentRequestIfRunning(
                in: existing.id,
                completion: {
                    stopScope(previousScope)
                }
            ) {
                stopScope(previousScope)
            }
        }
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
        if !WeiBeiSafetyTestMode.isEnabled {
            Task { @MainActor [weak self] in
                await self?.reconcileCourseFilesNow(courseID: existing.id)
            }
        }
        return existing.id
    }

    private func makeCourseProjectRebindProposal(
        existing: Course,
        candidateRoot: URL,
        candidateRootIdentity: ImportedFileIdentity,
        snapshot: CoursePortableAdoptionSnapshot
    ) async throws -> CourseProjectRebindProposal {
        guard !courseHasUnstableState(existing.id) else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard !(try await registeredCourseRootIsAvailable(existing)) else {
            throw CourseProjectRebindError.originalRootStillAvailable
        }
        guard course(withID: existing.id) == existing,
              activeCourseRebindTokens[existing.id] == nil,
              !courseHasUnstableState(existing.id) else {
            throw CourseProjectRebindError.proposalChanged
        }
        let evaluation = try evaluatedCourseRebindState(
            existing: existing,
            snapshot: snapshot
        )
        return CourseProjectRebindProposal(
            courseID: existing.id,
            courseTitle: existing.title,
            candidateRoot: candidateRoot,
            candidateRootIdentity: candidateRootIdentity,
            expectedCourse: existing,
            expectedLocalPayloadDigest: evaluation.localPayloadDigest,
            snapshot: snapshot,
            impact: evaluation.impact
        )
    }

    private func courseHasUnstableState(_ courseID: UUID) -> Bool {
        activeCourseRemovalTokens[courseID] != nil
            || courseHasPendingWork(courseID)
    }

    private func itemIsInRemovingCourse(_ itemID: String) -> Bool {
        if importedItems.first(where: { $0.id == itemID }).map({
            if case .courseOwned(let courseID) = $0.storage {
                return activeCourseRemovalTokens[courseID] != nil
            }
            return false
        }) == true {
            return true
        }
        return courseItemMemberships.contains {
            $0.itemID == itemID
                && activeCourseRemovalTokens[$0.courseID] != nil
        }
    }

    private func courseHasPendingWork(_ courseID: UUID) -> Bool {
        if activeCourseFileMutationCounts[
            courseID,
            default: 0
        ] > 0 {
            return true
        }
        let sessionIDs = Set(
            studySessions.lazy.filter {
                $0.courseID == courseID
            }.map(\.id)
        )
        let actionIDs = Set(
            studySessions.lazy.filter {
                $0.courseID == courseID
            }.flatMap {
                $0.messages.flatMap(\.actions).map(\.id)
            }
        )
        let noteItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID == courseID
            }.map(\.itemID)
        )
        return pendingNotePersistenceByItemID.keys.contains {
            noteItemIDs.contains($0)
        } || stagedNoteDraft.map {
            noteItemIDs.contains($0.itemID)
        } == true || courseNoteWritesInFlight.contains {
            noteItemIDs.contains($0)
        } || studySessions.contains {
            $0.courseID == courseID
                && $0.messages.contains {
                    $0.role == .assistant
                        && $0.completionState == .generating
                }
        } || (
            isAskingAgent
                && activeAgentReplyChatID.map(sessionIDs.contains)
                    == true
        ) || agentReplyActionIDsInFlight.contains {
            actionIDs.contains($0)
        }
    }

    private func evaluatedCourseRebindState(
        existing: Course,
        snapshot: CoursePortableAdoptionSnapshot
    ) throws -> (
        state: CoursePortableState,
        statePayloadDigest: String,
        localPayloadDigest: String,
        impact: CourseProjectRebindImpact
    ) {
        guard snapshot.manifest.courseID == existing.id,
              let portableStateData = snapshot.portableStateData else {
            throw CourseProjectRootError.manifestMismatch
        }
        let state = try JSONDecoder()
            .decode(CoursePortableState.self, from: portableStateData)
            .validated(expectedCourseID: existing.id)
        try validateCourseRebindStorage(
            state,
            courseID: existing.id
        )
        let localState = try makeCoursePortableState(
            courseID: existing.id,
            revision: coursePortableStateRevisions[existing.id] ?? 0,
            savedAt: Date(timeIntervalSince1970: 0)
        )
        let localPayloadDigest = try coursePortableStatePayloadDigest(
            localState
        )
        let comparableLocalState = try localStateByMaterializingSharedItems(
            localState,
            using: snapshot.manifest
        )
        let comparableLocalDigest = try coursePortableStatePayloadDigest(
            comparableLocalState
        )
        let statePayloadDigest = try coursePortableStatePayloadDigest(state)
        if statePayloadDigest == comparableLocalDigest {
            return (
                state,
                statePayloadDigest,
                localPayloadDigest,
                .unchanged
            )
        }

        let knownRevision = coursePortableStateRevisions[existing.id]
        let knownDigest = coursePortableStateDigests[existing.id]
        let localIsClean = knownDigest == localPayloadDigest
            && !dirtyPortableCourseIDs.contains(existing.id)
            && !blockedPortableCourseIDs.contains(existing.id)
            && !oversizedPortableCourseIDs.contains(existing.id)
        guard localIsClean,
              let knownRevision,
              state.revision > knownRevision else {
            throw CoursePortableStateError.stateConflict
        }
        return (
            state,
            statePayloadDigest,
            localPayloadDigest,
            .useNewerCandidate
        )
    }

    private func validateCourseRebindStorage(
        _ state: CoursePortableState,
        courseID: UUID
    ) throws {
        let otherCourseItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID != courseID
            }.map(\.itemID)
        )
        for portable in state.items
        where otherCourseItemIDs.contains(portable.itemID) {
            guard let existing = importedItems.first(where: {
                $0.id == portable.itemID
            }) else {
                throw CoursePortableStateError.crossCourseReference
            }
            switch (portable.storage, existing.storage) {
            case let (
                .sharedReference(candidatePath, candidateDigest),
                .shared(existingPath)
            ) where candidatePath == existingPath
                && candidateDigest != nil
                && candidateDigest == portable.contentDigest
                && candidateDigest == existing.contentDigest
                && portable.kind == existing.kind
                && portable.isNotebookNote == existing.isNotebookNote:
                continue
            default:
                throw CoursePortableStateError.crossCourseReference
            }
        }
    }

    func validateCourseRebindStorageForSelfCheck(
        _ state: CoursePortableState,
        courseID: UUID
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try validateCourseRebindStorage(state, courseID: courseID)
    }

    private func localStateByMaterializingSharedItems(
        _ rawState: CoursePortableState,
        using manifest: CourseProjectManifest
    ) throws -> CoursePortableState {
        guard let portableExport = manifest.portableExport else {
            return rawState
        }
        var state = rawState
        for provenance in portableExport.materializedSharedItems {
            guard let index = state.items.firstIndex(where: {
                $0.itemID == provenance.itemID
                    && $0.courseRelativePath
                        == provenance.courseRelativePath
            }) else {
                throw CoursePortableStateError.stateConflict
            }
            guard case let .sharedReference(
                sharedRelativePath,
                expectedContentDigest
            ) = state.items[index].storage,
            sharedRelativePath == provenance.sharedRelativePath,
            expectedContentDigest == provenance.sourceContentDigest,
            state.items[index].contentDigest
                == provenance.sourceContentDigest else {
                throw CoursePortableStateError.stateConflict
            }
            state.items[index].storage = .courseOwned
        }
        return try state.validated(expectedCourseID: rawState.courseID)
    }

    private func registeredCourseRootIsAvailable(
        _ course: Course
    ) async throws -> Bool {
        guard let expectedIdentity = course.sourceRootIdentity else {
            return false
        }
        func matches(_ rawURL: URL) -> Bool {
            guard let root = try? CourseProjectPathPolicy.existingDirectory(
                rawURL
            ),
            importedFileIdentityResolver(root) == expectedIdentity,
            let data = try? CourseProjectFileWorker.readBoundedRegularFile(
                at: root.appendingPathComponent(".weibei/course.json"),
                maximumByteCount: 1_048_576
            ),
            let manifest = try? JSONDecoder().decode(
                CourseProjectManifest.self,
                from: data
            ),
            manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion else {
                return false
            }
            return manifest.courseID == course.id
        }

        var candidates: [URL] = []
        if let resolved = resolvedCourseRootURLs[course.id] {
            candidates.append(resolved)
        }
        if let path = course.sourceRootPath {
            candidates.append(URL(fileURLWithPath: path, isDirectory: true))
        }
        if let relativePath = course.sourceRootRelativePath,
           let libraryRoot = courseLibraryRootURL {
            let expectedLibraryPath = courseLibraryRootPath
            let expectedLibraryIdentity = courseLibraryRootIdentity
            let expectedLibraryBookmark = courseLibraryRootBookmarkData
            if let expected = CourseProjectPathPolicy.resolvedRelativePath(
                relativePath,
                inside: libraryRoot
            ) {
                candidates.append(expected)
            }
            let search = await courseProjectFileWorker.findDirectory(
                with: expectedIdentity,
                inside: libraryRoot
            )
            guard courseLibraryRootURL == libraryRoot,
                  courseLibraryRootPath == expectedLibraryPath,
                  courseLibraryRootIdentity == expectedLibraryIdentity,
                  courseLibraryRootBookmarkData
                    == expectedLibraryBookmark else {
                throw CourseProjectRebindError.proposalChanged
            }
            lastCourseRebindRootSearchRanOnMainThread =
                search.ranOnMainThread
            if let moved = search.url {
                candidates.append(moved)
            }
        }
        var checkedPaths = Set<String>()
        for candidate in candidates {
            guard checkedPaths.insert(
                candidate.standardizedFileURL.path
            ).inserted else {
                continue
            }
            if matches(candidate) {
                return true
            }
        }

        guard let bookmark = course.sourceRootBookmarkData,
              let resolution = courseRootBookmarkResolver(bookmark),
              courseSecurityScopeStarter(resolution.url) else {
            return false
        }
        defer { courseSecurityScopeStopper(resolution.url) }
        return matches(resolution.url)
    }

    func courseRebindRootSearchRunsOffMainForSelfCheck() -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return lastCourseRebindRootSearchRanOnMainThread == false
    }

    private func course(
        matching proposal: CourseProjectRebindProposal
    ) -> Course? {
        courses.first {
            $0.id == proposal.courseID
                && $0 == proposal.expectedCourse
        }
    }

    private func courseUsesRebindCandidate(
        _ proposal: CourseProjectRebindProposal,
        resolvedRoot: URL
    ) -> Bool {
        guard let current = course(withID: proposal.courseID),
              current.sourceRootIdentity
                == proposal.candidateRootIdentity,
              let registeredRoot =
                resolvedCourseRootURLs[proposal.courseID] else {
            return false
        }
        return CourseProjectPathPolicy.isSame(
            registeredRoot,
            resolvedRoot
        )
    }

    @discardableResult
    func confirmCourseProjectRebind(
        _ proposal: CourseProjectRebindProposal
    ) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.confirmCourseProjectRebindAsync(proposal)
        }
    }

    @discardableResult
    func confirmCourseProjectRebindAsync(
        _ proposal: CourseProjectRebindProposal
    ) async throws -> UUID {
        guard let existing = course(matching: proposal) else {
            throw CourseProjectRebindError.proposalChanged
        }
        guard !courseHasUnstableState(existing.id) else {
            throw CoursePortableExportError.unstableCourseState
        }
        let rebindToken = UUID()
        guard activeCourseRebindTokens[existing.id] == nil else {
            throw CoursePortableExportError.unstableCourseState
        }
        activeCourseRebindTokens[existing.id] = rebindToken
        defer {
            if activeCourseRebindTokens[existing.id] == rebindToken {
                activeCourseRebindTokens.removeValue(forKey: existing.id)
            }
        }
        guard !(try await registeredCourseRootIsAvailable(existing)) else {
            throw CourseProjectRebindError.originalRootStillAvailable
        }

        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(
            proposal.candidateRoot
        )
        guard importedFileIdentityResolver(canonicalRoot)
                == proposal.candidateRootIdentity else {
            throw CourseProjectRebindError.proposalChanged
        }
        try validateCourseProjectRoot(
            canonicalRoot,
            identity: proposal.candidateRootIdentity,
            mustBeInsideLibrary: false,
            excludingCourseID: proposal.courseID
        )

        let libraryRelativePath = courseLibraryRootURL.flatMap {
            CourseProjectPathPolicy.relativePath(
                of: canonicalRoot,
                inside: $0
            )
        }
        var refreshedBookmark: Data?
        var resolvedRoot = canonicalRoot
        var newScopeURL: URL?
        if libraryRelativePath == nil {
            guard let bookmark = courseRootBookmarkMaker(canonicalRoot) else {
                throw CourseProjectRootError.bookmarkUnavailable
            }
            guard let resolution = courseRootBookmarkResolver(bookmark) else {
                throw CourseProjectRootError.bookmarkResolutionFailed
            }
            guard courseSecurityScopeStarter(resolution.url) else {
                throw CourseProjectRootError.securityScopeDenied
            }
            do {
                resolvedRoot = try CourseProjectPathPolicy.existingDirectory(
                    resolution.url
                )
                guard importedFileIdentityResolver(resolvedRoot)
                        == proposal.candidateRootIdentity else {
                    throw CourseProjectRebindError.proposalChanged
                }
            } catch {
                courseSecurityScopeStopper(resolution.url)
                throw error
            }
            refreshedBookmark = bookmark
            newScopeURL = resolution.url
        }

        var shouldStopNewScopeOnFailure = newScopeURL != nil
        let confirmedSnapshot: CoursePortableAdoptionSnapshot
        do {
            confirmedSnapshot = try await courseProjectFileWorker
                .adoptionSnapshot(
                    at: resolvedRoot,
                    expectedRootIdentity:
                        proposal.candidateRootIdentity
                )
            guard confirmedSnapshot.metadataIdentity
                    == proposal.snapshot.metadataIdentity,
                  confirmedSnapshot.manifestData
                    == proposal.snapshot.manifestData,
                  confirmedSnapshot.portableStateData
                    == proposal.snapshot.portableStateData,
                  confirmedSnapshot.completionData
                    == proposal.snapshot.completionData else {
                throw CourseProjectRebindError.proposalChanged
            }
            guard let currentCourse = course(matching: proposal),
                  !courseHasUnstableState(currentCourse.id) else {
                throw CourseProjectRebindError.proposalChanged
            }
            guard !(try await registeredCourseRootIsAvailable(currentCourse)) else {
                throw CourseProjectRebindError.originalRootStillAvailable
            }
            guard course(matching: proposal) == currentCourse,
                  !courseHasUnstableState(currentCourse.id) else {
                throw CourseProjectRebindError.proposalChanged
            }
            let evaluation = try evaluatedCourseRebindState(
                existing: currentCourse,
                snapshot: confirmedSnapshot
            )
            guard evaluation.localPayloadDigest
                    == proposal.expectedLocalPayloadDigest,
                  evaluation.impact == proposal.impact else {
                throw CourseProjectRebindError.proposalChanged
            }
            guard let courseIndex = courses.firstIndex(where: {
                $0 == currentCourse
            }) else {
                throw CourseProjectRebindError.proposalChanged
            }

            let scopeKey = "course:\(proposal.courseID.uuidString)"
            let previousCourses = courses
            let previousImportedItems = importedItems
            let previousMemberships = courseItemMemberships
            let previousNoteSourceLinks = noteSourceLinks
            let previousStudyLocations = studyLocationsByCourseID
            let previousResumePoints = courseResumePoints
            let previousLearningMemoryStates = learningMemoryStates
            let previousCourseKnowledgeProfiles = courseKnowledgeProfiles
            let previousStudySessions = studySessions
            let previousActiveStudySessionID = activeStudySessionID
            let previousMessages = messages
            let previousNotesByItemID = notesByItemID
            let previousPendingNoteWrites = pendingNoteWritesByItemID
            let previousLoadedCourseNoteText =
                loadedCourseNoteTextByItemID
            let previousNoteText = noteText
            let previousNoteBackingDigests =
                noteBackingContentDigestsByItemID
            let previousPortableRevisions =
                coursePortableStateRevisions
            let previousPortableDigests = coursePortableStateDigests
            let previousDirtyPortableCourses = dirtyPortableCourseIDs
            let previousBlockedPortableCourses =
                blockedPortableCourseIDs
            let previousOversizedPortableCourses =
                oversizedPortableCourseIDs
            let previousPortableBootstrap =
                needsPortableCourseStateBootstrap
            let previousResolvedRoot =
                resolvedCourseRootURLs[proposal.courseID]
            let previousUnavailableReason =
                courseRootUnavailableReasons[proposal.courseID]
            let previousScope = activeCourseSecurityScopes[scopeKey]
            let previousScopeOwnerToken =
                activeCourseSecurityScopeOwnerTokens[scopeKey]
            var didStopPreviousScope = false

            func stopPreviousScopeIfNeeded() {
                guard !didStopPreviousScope,
                      let previousScope else {
                    return
                }
                didStopPreviousScope = true
                courseSecurityScopeStopper(previousScope)
            }

            var reboundCourse = currentCourse
            reboundCourse.sourceRootPath =
                libraryRelativePath == nil ? resolvedRoot.path : nil
            reboundCourse.sourceRootRelativePath = libraryRelativePath
            reboundCourse.sourceRootIdentity =
                proposal.candidateRootIdentity
            reboundCourse.sourceRootBookmarkData = refreshedBookmark
            courses[courseIndex] = reboundCourse
            resolvedCourseRootURLs[proposal.courseID] = resolvedRoot
            courseRootUnavailableReasons.removeValue(
                forKey: proposal.courseID
            )
            if let newScopeURL {
                activeCourseSecurityScopes[scopeKey] = newScopeURL
                activeCourseSecurityScopeOwnerTokens[scopeKey] =
                    rebindToken
                shouldStopNewScopeOnFailure = false
            } else {
                activeCourseSecurityScopes.removeValue(forKey: scopeKey)
                activeCourseSecurityScopeOwnerTokens.removeValue(
                    forKey: scopeKey
                )
            }

            do {
                let reboundNoteItemIDs = Set(
                    evaluation.state.items.lazy.filter {
                        $0.isNotebookNote
                    }.map(\.itemID)
                ).union(
                    courseItemMemberships.lazy.filter {
                        $0.courseID == proposal.courseID
                    }.compactMap { membership in
                        self.importedItems.first {
                            $0.id == membership.itemID
                                && $0.isNotebookNote
                        }?.id
                    }
                )
                for itemID in reboundNoteItemIDs {
                    courseNoteLoadGenerationByItemID[
                        itemID,
                        default: 0
                    ] &+= 1
                    courseNoteLoadTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWriteTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWritesInFlight.remove(itemID)
                    loadedCourseNoteTextByItemID.removeValue(
                        forKey: itemID
                    )
                }
                try applyCoursePortableState(
                    evaluation.state,
                    courseID: proposal.courseID
                )
                if let activeNotebookItemID,
                   reboundNoteItemIDs.contains(activeNotebookItemID) {
                    noteText =
                        notesByItemID[activeNotebookItemID] ?? ""
                }
                coursePortableStateRevisions[proposal.courseID] =
                    evaluation.state.revision
                coursePortableStateDigests[proposal.courseID] =
                    evaluation.statePayloadDigest
                dirtyPortableCourseIDs.remove(proposal.courseID)
                blockedPortableCourseIDs.remove(proposal.courseID)
                oversizedPortableCourseIDs.remove(proposal.courseID)
                needsPortableCourseStateBootstrap =
                    !dirtyPortableCourseIDs.isEmpty
                guard await persistWorkspaceNow(
                    skippingPortableCourseIDs: [proposal.courseID]
                ) else {
                    throw CourseProjectRootError.workspaceSaveFailed
                }
            } catch {
                courses = previousCourses
                importedItems = previousImportedItems
                courseItemMemberships = previousMemberships
                noteSourceLinks = previousNoteSourceLinks
                studyLocationsByCourseID = previousStudyLocations
                courseResumePoints = previousResumePoints
                learningMemoryStates = previousLearningMemoryStates
                courseKnowledgeProfiles = previousCourseKnowledgeProfiles
                studySessions = previousStudySessions
                activeStudySessionID = previousActiveStudySessionID
                messages = previousMessages
                notesByItemID = previousNotesByItemID
                pendingNoteWritesByItemID =
                    previousPendingNoteWrites
                loadedCourseNoteTextByItemID =
                    previousLoadedCourseNoteText
                noteText = previousNoteText
                noteBackingContentDigestsByItemID =
                    previousNoteBackingDigests
                coursePortableStateRevisions =
                    previousPortableRevisions
                coursePortableStateDigests = previousPortableDigests
                dirtyPortableCourseIDs =
                    previousDirtyPortableCourses
                blockedPortableCourseIDs =
                    previousBlockedPortableCourses
                oversizedPortableCourseIDs =
                    previousOversizedPortableCourses
                needsPortableCourseStateBootstrap =
                    previousPortableBootstrap
                if let previousResolvedRoot {
                    resolvedCourseRootURLs[proposal.courseID] =
                        previousResolvedRoot
                } else {
                    resolvedCourseRootURLs.removeValue(
                        forKey: proposal.courseID
                    )
                }
                if let previousUnavailableReason {
                    courseRootUnavailableReasons[proposal.courseID] =
                        previousUnavailableReason
                } else {
                    courseRootUnavailableReasons.removeValue(
                        forKey: proposal.courseID
                    )
                }
                if let previousScope {
                    activeCourseSecurityScopes[scopeKey] = previousScope
                } else {
                    activeCourseSecurityScopes.removeValue(
                        forKey: scopeKey
                    )
                }
                if let previousScopeOwnerToken {
                    activeCourseSecurityScopeOwnerTokens[scopeKey] =
                        previousScopeOwnerToken
                } else {
                    activeCourseSecurityScopeOwnerTokens.removeValue(
                        forKey: scopeKey
                    )
                }
                if let newScopeURL {
                    courseSecurityScopeStopper(newScopeURL)
                    shouldStopNewScopeOnFailure = false
                }
                throw error
            }

            try courseProjectMutationHook(
                .afterAdoptionWorkspaceSaveBeforeManifestNormalization
            )
            if confirmedSnapshot.manifest.portableExport != nil {
                do {
                    let finalSnapshot = try await courseProjectFileWorker
                        .adoptionSnapshot(
                            at: resolvedRoot,
                            expectedRootIdentity:
                                proposal.candidateRootIdentity
                        )
                    guard courseUsesRebindCandidate(
                        proposal,
                        resolvedRoot: resolvedRoot
                    ),
                    finalSnapshot.metadataIdentity
                            == confirmedSnapshot.metadataIdentity,
                          finalSnapshot.manifestData
                            == confirmedSnapshot.manifestData,
                          finalSnapshot.portableStateData
                            == confirmedSnapshot.portableStateData,
                          finalSnapshot.completionData
                            == confirmedSnapshot.completionData,
                          finalSnapshot.manifest.portableExport != nil else {
                        throw CourseProjectRebindError.proposalChanged
                    }
                    try await courseProjectFileWorker
                        .normalizePortableCourseManifest(
                            with: CourseProjectManifest(
                                courseID: proposal.courseID
                            ).encoded(),
                            at: resolvedRoot.appendingPathComponent(
                                ".weibei/course.json"
                            ),
                            expectedDirectoryIdentity:
                                finalSnapshot.metadataIdentity,
                            expectedPreviousData:
                                finalSnapshot.manifestData
                        )
                    guard courseUsesRebindCandidate(
                        proposal,
                        resolvedRoot: resolvedRoot
                    ) else {
                        throw CourseProjectRebindError.proposalChanged
                    }
                } catch {
                    if activeCourseRebindTokens[proposal.courseID]
                            == rebindToken,
                       courseUsesRebindCandidate(
                           proposal,
                           resolvedRoot: resolvedRoot
                       ) {
                        resolvedCourseRootURLs.removeValue(
                            forKey: proposal.courseID
                        )
                        courseRootUnavailableReasons[proposal.courseID] =
                            error.localizedDescription
                    }
                    if activeCourseSecurityScopeOwnerTokens[scopeKey]
                            == rebindToken,
                       let scopedURL =
                            activeCourseSecurityScopes.removeValue(
                                forKey: scopeKey
                            ) {
                        activeCourseSecurityScopeOwnerTokens.removeValue(
                            forKey: scopeKey
                        )
                        courseSecurityScopeStopper(scopedURL)
                    }
                    stopPreviousScopeIfNeeded()
                    cancelAgentRequestIfRunning(in: proposal.courseID)
                    invalidateAgentContext()
                    throw error
                }
            }

            stopPreviousScopeIfNeeded()
            if activeCourseSecurityScopeOwnerTokens[scopeKey]
                    == rebindToken {
                activeCourseSecurityScopeOwnerTokens.removeValue(
                    forKey: scopeKey
                )
            }
            courseDocumentSearchIndex.synchronize(allItems)
            invalidateAgentContext()
            if !WeiBeiSafetyTestMode.isEnabled {
                Task { @MainActor [weak self] in
                    await self?.reconcileCourseFilesNow(
                        courseID: proposal.courseID
                    )
                }
            }
            shouldStopNewScopeOnFailure = false
            return proposal.courseID
        } catch {
            let scopeKey = "course:\(proposal.courseID.uuidString)"
            if activeCourseRebindTokens[proposal.courseID] == rebindToken,
               courseUsesRebindCandidate(
                   proposal,
                   resolvedRoot: resolvedRoot
               ) {
                resolvedCourseRootURLs.removeValue(
                    forKey: proposal.courseID
                )
                courseRootUnavailableReasons[proposal.courseID] =
                    error.localizedDescription
            }
            if activeCourseSecurityScopeOwnerTokens[scopeKey]
                    == rebindToken,
               let scopedURL =
                    activeCourseSecurityScopes.removeValue(
                        forKey: scopeKey
                    ) {
                activeCourseSecurityScopeOwnerTokens.removeValue(
                    forKey: scopeKey
                )
                courseSecurityScopeStopper(scopedURL)
            } else if shouldStopNewScopeOnFailure,
                      let newScopeURL {
                courseSecurityScopeStopper(newScopeURL)
            }
            throw error
        }
    }

    func courseRootURL(for courseID: UUID) -> URL? {
        resolvedCourseRootURLs[courseID]
    }

    func courseRootUnavailableReason(for courseID: UUID) -> String? {
        courseRootUnavailableReasons[courseID]
    }

    @discardableResult
    func exportPortableCourseCopy(
        courseID: UUID,
        to targetRoot: URL
    ) async throws -> URL {
        try await exportPortableCourseCopy(
            courseID: courseID,
            to: targetRoot,
            stageHook: { _ in }
        ).root
    }

    @discardableResult
    func exportPortableCourseCopyForSelfCheck(
        courseID: UUID,
        to targetRoot: URL,
        stageHook: @escaping @Sendable (
            CoursePortableExportStage
        ) throws -> Void = { _ in }
    ) throws -> CoursePortableExportResult {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            try await self.exportPortableCourseCopy(
                courseID: courseID,
                to: targetRoot,
                stageHook: stageHook
            )
        }
    }

    private func exportPortableCourseCopy(
        courseID: UUID,
        to targetRoot: URL,
        stageHook: @escaping @Sendable (
            CoursePortableExportStage
        ) throws -> Void
    ) async throws -> CoursePortableExportResult {
        guard let course = course(withID: courseID),
              let rawRoot = courseRootURL(for: courseID),
              let sourceRoot = try? CourseProjectPathPolicy.existingDirectory(
                  rawRoot
              ),
              let sourceRootIdentity = importedFileIdentityResolver(
                  sourceRoot
              ),
              course.sourceRootIdentity == sourceRootIdentity else {
            throw CourseProjectRootError.unavailableLibrary
        }
        guard !courseHasUnstableState(courseID) else {
            throw CoursePortableExportError.unstableCourseState
        }
        var state = try makeCoursePortableState(
            courseID: courseID,
            revision: coursePortableStateRevisions[courseID] ?? 0,
            savedAt: Date()
        )
        var itemsByID: [String: StudyItem] = [:]
        for item in importedItems {
            guard itemsByID.updateValue(item, forKey: item.id) == nil else {
                throw CoursePortableStateError.duplicateItemID
            }
        }
        var membershipsByItemID: [String: CourseItemMembership] = [:]
        for membership in courseItemMemberships
            where membership.courseID == courseID {
            guard membershipsByItemID.updateValue(
                membership,
                forKey: membership.itemID
            ) == nil else {
                throw CoursePortableStateError.duplicateItemID
            }
        }
        var sharedMaterials: [CoursePortableExportSharedMaterial] = []
        for index in state.items.indices {
            guard case let .sharedReference(
                sharedRelativePath,
                expectedContentDigest
            ) = state.items[index].storage else {
                continue
            }
            let role: CourseOwnedFileRole = state.items[index].isNotebookNote
                ? .note
                : .material
            let sharedDirectoryName = sharedRelativePath.split(
                separator: "/"
            ).first.map(String.init)
            let allowedSharedDirectoryNames: Set<String> = role == .note
                ? [role.commonDirectoryName]
                : [role.commonDirectoryName, "共享文稿"]
            guard let expectedContentDigest,
                  let sharedDirectoryName,
                  allowedSharedDirectoryNames.contains(sharedDirectoryName),
                  let item = itemsByID[state.items[index].itemID],
                  let membership =
                    membershipsByItemID[state.items[index].itemID],
                  membership.courseRelativePath
                    == state.items[index].courseRelativePath,
                  case let .shared(itemSharedRelativePath) = item.storage,
                  itemSharedRelativePath == sharedRelativePath,
                  item.contentDigest == expectedContentDigest,
                  let sharedURL = item.url,
                  let libraryRoot = courseLibraryRootURL,
                  let expectedSharedURL =
                    CourseProjectPathPolicy.resolvedRelativePath(
                        sharedRelativePath,
                        inside: libraryRoot
                    ),
                  CourseProjectPathPolicy.isSame(
                      expectedSharedURL,
                      sharedURL
                  ),
                  CourseProjectPathPolicy.isSame(
                      expectedSharedURL.deletingLastPathComponent(),
                      libraryRoot.appendingPathComponent(
                          sharedDirectoryName,
                          isDirectory: true
                      )
                      .resolvingSymlinksInPath()
                      .standardizedFileURL
                  ),
                  let linkURL = rawCourseItemURL(
                      relativePath: state.items[index].courseRelativePath,
                      inside: sourceRoot
                  ),
                  let linkIdentity =
                    CourseProjectFileWorker.identity(at: linkURL),
                  CourseProjectFileWorker.isSymbolicLink(at: linkURL),
                  CourseProjectFileWorker.symbolicLink(
                      at: linkURL,
                      pointsTo: sharedURL
                  ) else {
                throw CoursePortableStateError.invalidItemStorage
            }
            let sourceInfo = try await courseProjectFileWorker
                .validatedRegularSource(sharedURL)
            guard item.importedFileIdentity == sourceInfo.identity else {
                throw CoursePortableStateError.stateConflict
            }
            let sourceSnapshot = try await courseProjectFileWorker
                .stableSnapshot(
                    at: sourceInfo.url,
                    expectedIdentity: sourceInfo.identity
                )
            guard sourceSnapshot.sha256 == expectedContentDigest else {
                throw CoursePortableStateError.stateConflict
            }
            sharedMaterials.append(
                CoursePortableExportSharedMaterial(
                    itemID: item.id,
                    courseRelativePath:
                        state.items[index].courseRelativePath,
                    sharedRelativePath: sharedRelativePath,
                    linkIdentity: linkIdentity,
                    sourceURL: sourceInfo.url,
                    sourceIdentity: sourceInfo.identity,
                    sourceSnapshot: sourceSnapshot
                )
            )
            state.items[index].storage = .courseOwned
        }
        state = try state.validated(expectedCourseID: courseID)
        let sharedDirectory = sharedMaterials.isEmpty
            ? nil
            : courseLibraryRootURL
        if !sharedMaterials.isEmpty, sharedDirectory == nil {
            throw CourseProjectRootError.unavailableLibrary
        }
        return try await courseProjectFileWorker.exportPortableCourse(
            CoursePortableExportRequest(
                courseID: courseID,
                sourceRoot: sourceRoot,
                sourceRootIdentity: sourceRootIdentity,
                sharedDirectory: sharedDirectory,
                targetRoot: targetRoot,
                portableStateData: try encodedCoursePortableState(state),
                requiredRegularRelativePaths: Set(
                    state.items.map(\.courseRelativePath)
                ),
                sharedMaterials: sharedMaterials
            ),
            stageHook: stageHook
        )
    }

    @discardableResult
    func importFileIntoCourse(
        _ sourceURL: URL,
        courseID: UUID,
        role: CourseOwnedFileRole,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws -> CourseOwnedFileImportResult {
        let sourceInfo: CourseFileSourceInfo
        do {
            sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        } catch {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        return try await transactCourseOwnedFile(
            courseID: courseID,
            role: role,
            fileName: sourceInfo.url.lastPathComponent,
            sourceURL: sourceInfo.url,
            sourceIdentity: sourceInfo.identity,
            generatedData: nil,
            conflictResolution: conflictResolution
        )
    }

    /// Synchronous bridge used only by the executable self-check harness.
    /// The run loop keeps servicing the main actor while all file work stays on the worker actor.
    @discardableResult
    func importFileIntoCourseForSelfCheck(
        _ sourceURL: URL,
        courseID: UUID,
        role: CourseOwnedFileRole,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws -> CourseOwnedFileImportResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return try waitForCourseFileOperation {
            try await self.importFileIntoCourse(
                sourceURL,
                courseID: courseID,
                role: role,
                conflictResolution: conflictResolution
            )
        }
    }

    @discardableResult
    func migrateLegacyExternalItemIntoCourse(
        itemID: String,
        courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws -> CourseOwnedFileImportResult {
        guard let item = importedItems.first(where: { $0.id == itemID }),
              item.storage == .legacyExternal,
              let sourceURL = item.url else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        return try await transactCourseOwnedFile(
            courseID: courseID,
            role: item.isNotebookNote ? .note : .material,
            fileName: sourceInfo.url.lastPathComponent,
            sourceURL: sourceInfo.url,
            sourceIdentity: sourceInfo.identity,
            generatedData: nil,
            conflictResolution: conflictResolution,
            preservingItemID: itemID
        )
    }

    @discardableResult
    func moveCourseOwnedItem(
        itemID: String,
        toCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws -> CourseOwnedFileImportResult {
        guard let item = importedItems.first(where: { $0.id == itemID }),
              case .courseOwned(let ownerCourseID) = item.storage,
              ownerCourseID != courseID,
              let sourceURL = item.url else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        return try await transactCourseOwnedFile(
            courseID: courseID,
            role: item.isNotebookNote ? .note : .material,
            fileName: sourceInfo.url.lastPathComponent,
            sourceURL: sourceInfo.url,
            sourceIdentity: sourceInfo.identity,
            generatedData: nil,
            conflictResolution: conflictResolution,
            preservingItemID: itemID,
            additionalCourseIDs: [ownerCourseID]
        )
    }

    func shareCourseOwnedItem(
        itemID: String,
        withCourseID addedCourseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws {
        guard activeCourseRemovalTokens[addedCourseID] == nil else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard conflictResolution != .replace else {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        guard let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }) else {
            throw CourseOwnedFileError.unsupportedFile
        }
        let role: CourseOwnedFileRole = importedItems[itemIndex].isNotebookNote
            ? .note
            : .material
        if case .shared = importedItems[itemIndex].storage {
            try await linkSharedItem(
                itemID: itemID,
                toCourseID: addedCourseID,
                conflictResolution: conflictResolution
            )
            return
        }
        guard case .courseOwned(let ownerCourseID) = importedItems[itemIndex].storage,
              activeCourseRemovalTokens[ownerCourseID] == nil,
              ownerCourseID != addedCourseID,
              let ownerRoot = courseRootURL(for: ownerCourseID),
              let addedRoot = courseRootURL(for: addedCourseID),
              let ownerMembershipIndex = uniqueCourseOwnedMembershipIndex(
                itemID: itemID,
                courseID: ownerCourseID
              ),
              let sourceRelativePath = courseItemMemberships[ownerMembershipIndex].courseRelativePath,
              let sourceURL = safeCourseOwnedFileURL(
                relativePath: sourceRelativePath,
                role: role,
                inside: ownerRoot
              ),
              let libraryRoot = courseLibraryRootURL else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        let affectedCourseIDs: Set<UUID> = [
            ownerCourseID,
            addedCourseID,
        ]
        try beginCourseFileMutation(courseIDs: affectedCourseIDs)
        defer {
            finishCourseFileMutation(courseIDs: affectedCourseIDs)
        }
        let sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        let sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sourceInfo.url,
            expectedIdentity: sourceInfo.identity
        )
        let sharedDirectory = try await courseProjectFileWorker.ensureRealDirectory(
            libraryRoot.appendingPathComponent(
                role.commonDirectoryName,
                isDirectory: true
            ),
            inside: libraryRoot
        )
        let sharedTarget = try resolvedCourseImportTarget(
            fileName: sourceURL.lastPathComponent,
            destinationDirectory: sharedDirectory,
            role: role,
            conflictResolution: conflictResolution
        )
        if FileManager.default.fileExists(atPath: sharedTarget.path) {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        let addedDirectory = try await courseProjectFileWorker.ensureRealDirectory(
            addedRoot.appendingPathComponent(
                role.directoryName,
                isDirectory: true
            ),
            inside: addedRoot
        )
        let addedLinkURL = try resolvedCourseImportTarget(
            fileName: sharedTarget.lastPathComponent,
            destinationDirectory: addedDirectory,
            role: role,
            conflictResolution: conflictResolution == .replace ? .cancel : conflictResolution
        )
        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: ownerRoot
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(transactionDirectory),
              let sharedDirectoryIdentity = importedFileIdentityResolver(sharedDirectory) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let payloadURL = sharedDirectory.appendingPathComponent(
            ".\(sharedTarget.lastPathComponent).weibei-share-stage-\(transactionID.uuidString.lowercased())"
        )
        let journalURL = transactionDirectory.appendingPathComponent("shared.json")
        let preparedOwnerLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-owner-link"
        )
        let preparedAddedLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-added-link"
        )
        let ownerDirectory = sourceURL.deletingLastPathComponent()
        guard let libraryRootIdentity = CourseProjectFileWorker.identity(at: libraryRoot),
              let ownerRootIdentity = CourseProjectFileWorker.identity(at: ownerRoot),
              let addedRootIdentity = CourseProjectFileWorker.identity(at: addedRoot),
              let ownerDirectoryIdentity = CourseProjectFileWorker.identity(
                at: ownerDirectory
              ),
              let addedDirectoryIdentity = CourseProjectFileWorker.identity(
                at: addedDirectory
              ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let sourceQuarantineURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(sourceURL.lastPathComponent).weibei-share-\(transactionID.uuidString.lowercased())"
            )
        let sharedRelativePath = CourseProjectPathPolicy.relativePath(
            of: sharedTarget,
            inside: libraryRoot
        ) ?? "\(role.commonDirectoryName)/\(sharedTarget.lastPathComponent)"
        let addedRelativePath = CourseProjectPathPolicy.relativePath(
            of: addedLinkURL,
            inside: addedRoot
        ) ?? "\(role.directoryName)/\(addedLinkURL.lastPathComponent)"
        var journal = PendingSharedFileTransactionJournal(
            transactionID: transactionID,
            transactionDirectoryIdentity: transactionDirectoryIdentity,
            itemID: itemID,
            ownerCourseID: ownerCourseID,
            addedCourseID: addedCourseID,
            sourcePath: sourceURL.path,
            sourceRelativePath: sourceRelativePath,
            sourceIdentity: sourceInfo.identity,
            sourceSnapshot: sourceSnapshot,
            sourceQuarantinePath: sourceQuarantineURL.path,
            sharedPath: sharedTarget.path,
            sharedRelativePath: sharedRelativePath,
            sharedPayloadPath: payloadURL.path,
            sharedIdentity: nil,
            ownerLinkIdentity: nil,
            addedLinkPath: addedLinkURL.path,
            addedLinkRelativePath: addedRelativePath,
            addedLinkIdentity: nil,
            stage: .prepared
        )
        let previousItems = importedItems
        let previousMemberships = courseItemMemberships
        func revalidatedSharedArtifacts(
            sharedIdentity: ImportedFileIdentity,
            ownerLinkIdentity: ImportedFileIdentity,
            addedLinkIdentity: ImportedFileIdentity
        ) async throws -> CourseFileSourceInfo {
            guard CourseProjectFileWorker.identity(at: libraryRoot)
                    == libraryRootIdentity,
                  CourseProjectFileWorker.identity(at: ownerRoot)
                    == ownerRootIdentity,
                  CourseProjectFileWorker.identity(at: addedRoot)
                    == addedRootIdentity,
                  CourseProjectFileWorker.identity(at: sharedDirectory)
                    == sharedDirectoryIdentity,
                  CourseProjectFileWorker.identity(at: ownerDirectory)
                    == ownerDirectoryIdentity,
                  CourseProjectFileWorker.identity(at: addedDirectory)
                    == addedDirectoryIdentity,
                  CourseProjectPathPolicy.isSame(
                    sharedDirectory,
                    sharedDirectory.resolvingSymlinksInPath()
                  ),
                  CourseProjectPathPolicy.isSame(
                    ownerDirectory,
                    ownerDirectory.resolvingSymlinksInPath()
                  ),
                  CourseProjectPathPolicy.isSame(
                    addedDirectory,
                    addedDirectory.resolvingSymlinksInPath()
                  ),
                  CourseProjectFileWorker.identity(at: sourceURL)
                    == ownerLinkIdentity,
                  CourseProjectFileWorker.symbolicLink(
                    at: sourceURL,
                    pointsTo: sharedTarget
                  ),
                  CourseProjectFileWorker.identity(at: addedLinkURL)
                    == addedLinkIdentity,
                  CourseProjectFileWorker.symbolicLink(
                    at: addedLinkURL,
                    pointsTo: sharedTarget
                  ) else {
                throw CourseOwnedFileError.verificationFailed
            }
            return try await courseProjectFileWorker.stableMetadata(
                at: sharedTarget,
                expectedIdentity: sharedIdentity,
                expectedSnapshot: sourceSnapshot
            )
        }
        do {
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            let stagedIdentity = try await courseProjectFileWorker.copyAndVerify(
                from: sourceURL,
                generatedData: nil,
                to: payloadURL,
                expectedSnapshot: sourceSnapshot
            )
            journal.sharedIdentity = stagedIdentity
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            try courseProjectMutationHook(
                .afterSharedSameVolumeStagingJournal
            )
            let sharedIdentity = try await courseProjectFileWorker.placeWithoutReplacement(
                from: payloadURL,
                to: sharedTarget,
                courseRoot: libraryRoot,
                destinationDirectory: sharedDirectory,
                expectedDestinationIdentity: sharedDirectoryIdentity,
                expectedSnapshot: sourceSnapshot
            )
            try courseProjectMutationHook(.afterSharedFilePlacementBeforeJournal)
            guard stagedIdentity == sharedIdentity,
                  await courseProjectFileWorker.isolateWithoutReplacement(
                    from: sourceURL,
                    to: sourceQuarantineURL
                  ) else {
                throw CourseOwnedFileError.verificationFailed
            }
            try courseProjectMutationHook(.afterSharedSourceIsolationBeforeJournal)
            _ = try await courseProjectFileWorker.stableSnapshot(
                at: sourceQuarantineURL,
                expectedIdentity: sourceInfo.identity,
                expectedSnapshot: sourceSnapshot
            )
            journal.sharedIdentity = sharedIdentity
            journal.stage = .sharedPlaced
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            journal.stage = .linksPreparing
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            let ownerLinkIdentity = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedOwnerLinkURL,
                destinationURL: sharedTarget
            )
            try courseProjectMutationHook(
                .afterSharedOwnerLinkPrepareBeforeJournalIdentity
            )
            journal.ownerLinkIdentity = ownerLinkIdentity
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            let addedLinkIdentity = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedAddedLinkURL,
                destinationURL: sharedTarget
            )
            try courseProjectMutationHook(
                .afterSharedAddedLinkPrepareBeforeJournalIdentity
            )
            journal.addedLinkIdentity = addedLinkIdentity
            journal.stage = .linksPrepared
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedOwnerLinkURL,
                to: sourceURL,
                destinationURL: sharedTarget,
                allowedRoot: ownerRoot,
                expectedIdentity: ownerLinkIdentity
            )
            try courseProjectMutationHook(.afterSharedOwnerLinkPlacementBeforeJournal)
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedAddedLinkURL,
                to: addedLinkURL,
                destinationURL: sharedTarget,
                allowedRoot: addedRoot,
                expectedIdentity: addedLinkIdentity
            )
            try courseProjectMutationHook(.afterSharedAddedLinkPlacementBeforeJournal)
            journal.stage = .linksPlaced
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )

            let sharedInfo = try await revalidatedSharedArtifacts(
                sharedIdentity: sharedIdentity,
                ownerLinkIdentity: ownerLinkIdentity,
                addedLinkIdentity: addedLinkIdentity
            )
            importedItems[itemIndex].urlPath = sharedTarget.path
            importedItems[itemIndex].importedFileLastKnownPath = sharedTarget.path
            importedItems[itemIndex].importedFileIdentity = sharedIdentity
            importedItems[itemIndex].importedFileBookmarkData = nil
            importedItems[itemIndex].storage = .shared(
                sharedRelativePath: sharedRelativePath
            )
            importedItems[itemIndex].fileByteCount = sharedInfo.byteCount
            importedItems[itemIndex].fileModificationTimeNanoseconds =
                sharedInfo.modificationTimeNanoseconds
            courseItemMemberships[ownerMembershipIndex].entryIdentity = ownerLinkIdentity
            courseItemMemberships[ownerMembershipIndex].documentIdentifier = nil
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: addedCourseID,
                    itemID: itemID,
                    courseRelativePath: addedRelativePath,
                    entryIdentity: addedLinkIdentity,
                    documentIdentifier: nil
                )
            )
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            journal.stage = .workspaceCommitted
            try? await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            try courseProjectMutationHook(
                .afterSharedWorkspaceSaveBeforeSourceCleanup
            )
            if (try? await revalidatedSharedArtifacts(
                sharedIdentity: sharedIdentity,
                ownerLinkIdentity: ownerLinkIdentity,
                addedLinkIdentity: addedLinkIdentity
            )) != nil {
                let cleanup = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                        at: sourceQuarantineURL,
                        quarantineURL: transactionDirectory
                            .appendingPathComponent("source-cleanup"),
                        expectedIdentity: sourceInfo.identity,
                        expectedSnapshot: sourceSnapshot,
                        remover: { try FileManager.default.removeItem(at: $0) }
                    )
                if case .removed = cleanup {
                    try courseProjectMutationHook(
                        .afterSharedSourceCleanupBeforeTransactionCleanup
                    )
                    await safelyRemoveSharedTransactionDirectoryInBackground(
                        transactionDirectory,
                        expectedIdentity: transactionDirectoryIdentity
                    )
                }
            }
            courseDocumentSearchIndex.schedule([importedItems[itemIndex]])
            invalidateAgentContext()
        } catch {
            if WeiBeiSafetyTestMode.isEnabled, error is CourseProjectSimulatedCrash {
                throw error
            }
            importedItems = previousItems
            courseItemMemberships = previousMemberships
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: addedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "added-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: journal.addedLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: sourceURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "owner-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: journal.ownerLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedAddedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-added-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: journal.addedLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedOwnerLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-owner-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: journal.ownerLinkIdentity
            )
            if !FileManager.default.fileExists(atPath: sourceURL.path) {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: sourceQuarantineURL,
                    to: sourceURL
                )
            }
            let sourceWasRestored =
                (try? await courseProjectFileWorker.stableMetadata(
                    at: sourceURL,
                    expectedIdentity: sourceInfo.identity,
                    expectedSnapshot: sourceSnapshot
                )) != nil
            var sharedArtifactsWereRemoved = true
            if let sharedIdentity = journal.sharedIdentity {
                let sharedRemoval = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                    at: sharedTarget,
                    quarantineURL: sharedDirectory.appendingPathComponent(
                        ".\(sharedTarget.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                    ),
                    expectedIdentity: sharedIdentity,
                    expectedSnapshot: sourceSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
                let payloadRemoval = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                    at: payloadURL,
                    quarantineURL: sharedDirectory.appendingPathComponent(
                        ".\(payloadURL.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                    ),
                    expectedIdentity: sharedIdentity,
                    expectedSnapshot: sourceSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
                if case .removed = sharedRemoval {
                    if case .removed = payloadRemoval {
                        sharedArtifactsWereRemoved = true
                    } else {
                        sharedArtifactsWereRemoved = false
                    }
                } else {
                    sharedArtifactsWereRemoved = false
                }
            } else if CourseProjectFileWorker.identity(at: sharedTarget) != nil
                || CourseProjectFileWorker.identity(at: payloadURL) != nil {
                sharedArtifactsWereRemoved = false
            }
            if sourceWasRestored, sharedArtifactsWereRemoved {
                await safelyRemoveSharedTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
            }
            throw error
        }
    }

    private func linkSharedItem(
        itemID: String,
        toCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution
    ) async throws {
        let affectedCourseIDs: Set<UUID> = [courseID]
        try beginCourseFileMutation(courseIDs: affectedCourseIDs)
        defer {
            finishCourseFileMutation(courseIDs: affectedCourseIDs)
        }
        guard conflictResolution != .replace else {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        guard let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }),
              case .shared(let sharedRelativePath) = importedItems[itemIndex].storage,
              let sharedURL = importedItems[itemIndex].url,
              let courseRoot = courseRootURL(for: courseID),
              let libraryRoot = courseLibraryRootURL,
              let expectedSharedURL = CourseProjectPathPolicy.resolvedRelativePath(
                sharedRelativePath,
                inside: libraryRoot
              ),
              CourseProjectPathPolicy.isSame(expectedSharedURL, sharedURL) else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        let role: CourseOwnedFileRole = importedItems[itemIndex].isNotebookNote
            ? .note
            : .material
        let allowedSharedDirectories: Set<Substring> = role == .note
            ? [Substring(role.commonDirectoryName)]
            : [Substring(role.commonDirectoryName), "共享文稿"]
        let sharedComponents = sharedRelativePath.split(separator: "/")
        guard sharedComponents.count == 2,
              allowedSharedDirectories.contains(sharedComponents[0]),
              sharedComponents[1] == Substring(sharedURL.lastPathComponent) else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        if courseItemMemberships.contains(where: {
            $0.courseID == courseID && $0.itemID == itemID
        }) {
            return
        }
        let sharedInfo = try await courseProjectFileWorker.validatedRegularSource(
            expectedSharedURL
        )
        let sharedSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sharedInfo.url,
            expectedIdentity: sharedInfo.identity
        )
        let materialDirectory = try await courseProjectFileWorker.ensureRealDirectory(
            courseRoot.appendingPathComponent(
                role.directoryName,
                isDirectory: true
            ),
            inside: courseRoot
        )
        let linkURL = try resolvedCourseImportTarget(
            fileName: sharedURL.lastPathComponent,
            destinationDirectory: materialDirectory,
            role: role,
            conflictResolution: conflictResolution == .replace ? .cancel : conflictResolution
        )
        guard let linkRelativePath = CourseProjectPathPolicy.relativePath(
            of: linkURL,
            inside: courseRoot
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: courseRoot
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(
            transactionDirectory
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let journalURL = transactionDirectory.appendingPathComponent(
            "shared-link.json"
        )
        let preparedLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-link"
        )
        var journal = PendingSharedLinkTransactionJournal(
            transactionID: transactionID,
            transactionDirectoryIdentity: transactionDirectoryIdentity,
            itemID: itemID,
            courseID: courseID,
            sharedPath: expectedSharedURL.path,
            sharedRelativePath: sharedRelativePath,
            sharedIdentity: sharedInfo.identity,
            sharedSnapshot: sharedSnapshot,
            linkPath: linkURL.path,
            linkRelativePath: linkRelativePath,
            linkIdentity: nil,
            stage: .prepared
        )
        let previousMemberships = courseItemMemberships
        do {
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            journal.stage = .linkPreparing
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            let linkIdentity = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedLinkURL,
                destinationURL: expectedSharedURL
            )
            try courseProjectMutationHook(
                .afterSharedLinkPrepareBeforeJournalIdentity
            )
            journal.linkIdentity = linkIdentity
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedLinkURL,
                to: linkURL,
                destinationURL: expectedSharedURL,
                allowedRoot: courseRoot,
                expectedIdentity: linkIdentity
            )
            try courseProjectMutationHook(.afterSharedLinkPlacementBeforeJournal)
            journal.stage = .linkPlaced
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: courseID,
                    itemID: itemID,
                    courseRelativePath: linkRelativePath,
                    entryIdentity: linkIdentity
                )
            )
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            journal.stage = .workspaceCommitted
            try? await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            invalidateAgentContext()
        } catch {
            if WeiBeiSafetyTestMode.isEnabled, error is CourseProjectSimulatedCrash {
                throw error
            }
            courseItemMemberships = previousMemberships
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: linkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "link-cleanup"
                ),
                destinationURL: expectedSharedURL,
                expectedIdentity: journal.linkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-link-cleanup"
                ),
                destinationURL: expectedSharedURL,
                expectedIdentity: journal.linkIdentity
            )
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            throw error
        }
    }

    func courseFileSnapshotRunsOffMainForSelfCheck(_ url: URL) throws -> Bool {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let evidence = try waitForCourseFileOperation {
            try await self.courseProjectFileWorker.snapshotWithThreadEvidence(at: url)
        }
        return evidence.snapshot.byteCount > 0 && !evidence.ranOnMainThread
    }

    func portableAdoptionReadRunsOffMainForSelfCheck() -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return lastPortableAdoptionReadRanOnMainThread == false
    }

    func isolatedCourseNoteOpenDoesNotReadForSelfCheck(
        itemID: String,
        courseID: UUID
    ) -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        courseNoteLoadGenerationByItemID[
            itemID,
            default: 0
        ] &+= 1
        courseNoteLoadTasksByItemID
            .removeValue(forKey: itemID)?
            .cancel()
        loadedCourseNoteTextByItemID.removeValue(
            forKey: itemID
        )
        lastCourseNoteReadRanOnMainThread = nil
        openCourseNote(itemID, in: courseID)
        return activeNotebookItemID == itemID
            && courseNoteLoadTasksByItemID[itemID] == nil
            && loadedCourseNoteTextByItemID[itemID] == nil
            && lastCourseNoteReadRanOnMainThread == nil
    }

    func courseMarkdownRoundTripRunsOffMainForSelfCheck(
        itemID: String,
        markdown: String
    ) throws -> (read: Bool, write: Bool) {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            guard let item = self.importedItems.first(where: {
                $0.id == itemID
            }),
            item.isNotebookNote,
            case .courseOwned = item.storage,
            let url = item.url,
            let identity = item.importedFileIdentity else {
                throw CourseOwnedFileError.verificationFailed
            }
            let read = try await self.courseProjectFileWorker.readMarkdown(
                at: url,
                expectedIdentity: identity
            )
            let transaction = try await self.beginCourseMarkdownWrite(
                markdown,
                item: item,
                expectedContentDigest: read.snapshot.sha256
            )
            let write = transaction.result
            self.lastCourseNoteReadRanOnMainThread = read.ranOnMainThread
            self.lastCourseNoteWriteRanOnMainThread = write.ranOnMainThread
            self.applyCourseMarkdownWriteResult(
                write,
                itemID: itemID,
                markdown: markdown
            )
            guard self.performSaveNow() else {
                await self.rollbackCourseMarkdownWrite(
                    journal: transaction.journal,
                    transactionDirectory: transaction.transactionDirectory
                )
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            await self.finishCourseMarkdownWrite(transaction)
            return (!read.ranOnMainThread, !write.ranOnMainThread)
        }
    }

    func writeCourseMarkdownForSelfCheck(
        itemID: String,
        markdown: String
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try waitForCourseFileOperation {
            guard let item = self.importedItems.first(where: {
                $0.id == itemID
            }),
            item.isNotebookNote,
            case .courseOwned = item.storage else {
                throw CourseOwnedFileError.verificationFailed
            }
            self.retainPendingNoteWrite(
                markdown,
                itemID: itemID,
                fallbackURL: nil
            )
            guard self.performSaveNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            let expectedDigest = self.pendingNoteWritesByItemID[itemID]?
                .baselineContentDigest
            let transaction = try await self.beginCourseMarkdownWrite(
                markdown,
                item: item,
                expectedContentDigest: expectedDigest
            )
            let previousItems = self.importedItems
            let previousMemberships = self.courseItemMemberships
            let previousBackingDigests =
                self.noteBackingContentDigestsByItemID
            let previousLoadedNotes = self.loadedCourseNoteTextByItemID
            self.applyCourseMarkdownWriteResult(
                transaction.result,
                itemID: itemID,
                markdown: markdown
            )
            self.notesByItemID.removeValue(forKey: itemID)
            self.pendingNoteWritesByItemID.removeValue(forKey: itemID)
            guard self.performSaveNow() else {
                self.importedItems = previousItems
                self.courseItemMemberships = previousMemberships
                self.noteBackingContentDigestsByItemID =
                    previousBackingDigests
                self.loadedCourseNoteTextByItemID = previousLoadedNotes
                self.notesByItemID[itemID] = markdown
                self.pendingNoteWritesByItemID[itemID] =
                    PendingNoteWriteState(
                        baselineContentDigest: expectedDigest
                    )
                await self.rollbackCourseMarkdownWrite(
                    journal: transaction.journal,
                    transactionDirectory: transaction.transactionDirectory
                )
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            await self.finishCourseMarkdownWrite(transaction)
        }
    }

    func pendingCourseMarkdownDraftForSelfCheck(
        itemID: String
    ) -> String? {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard pendingNoteWritesByItemID[itemID] != nil else { return nil }
        return notesByItemID[itemID]
    }

    func waitForCourseNoteWritesForSelfCheck() throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let deadline = Date(timeIntervalSinceNow: 20)
        while !courseNoteWritesInFlight.isEmpty, Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        guard courseNoteWritesInFlight.isEmpty else {
            throw CourseOwnedFileError.verificationFailed
        }
    }

    func stagePendingCourseNoteForSelfCheck(
        itemID: String,
        markdown: String
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let item = importedItems.first(where: {
            $0.id == itemID && $0.isNotebookNote
        }) else {
            throw CourseOwnedFileError.verificationFailed
        }
        scheduleNotePersistence(markdown, for: item)
    }

    func discardPendingCourseNoteForSelfCheck(itemID: String) {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        cancelPendingNotePersistence(for: itemID)
        pendingNotePersistenceByItemID.removeValue(forKey: itemID)
        if stagedNoteDraft?.itemID == itemID {
            stagedNoteDraft = nil
        }
    }

    func migrateLegacyExternalItemForSelfCheck(
        itemID: String,
        courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws -> CourseOwnedFileImportResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return try waitForCourseFileOperation {
            try await self.migrateLegacyExternalItemIntoCourse(
                itemID: itemID,
                courseID: courseID,
                conflictResolution: conflictResolution
            )
        }
    }

    func moveCourseOwnedItemForSelfCheck(
        itemID: String,
        toCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws -> CourseOwnedFileImportResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return try waitForCourseFileOperation {
            try await self.moveCourseOwnedItem(
                itemID: itemID,
                toCourseID: courseID,
                conflictResolution: conflictResolution
            )
        }
    }

    func shareCourseOwnedItemForSelfCheck(
        itemID: String,
        withCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        try waitForCourseFileOperation {
            try await self.shareCourseOwnedItem(
                itemID: itemID,
                withCourseID: courseID,
                conflictResolution: conflictResolution
            )
        }
    }

    private func transactCourseOwnedFile(
        courseID: UUID,
        role: CourseOwnedFileRole,
        fileName: String,
        sourceURL: URL?,
        sourceIdentity: ImportedFileIdentity?,
        generatedData: Data?,
        conflictResolution: CourseFileConflictResolution = .cancel,
        preservingItemID: String? = nil,
        additionalCourseIDs: Set<UUID> = []
    ) async throws -> CourseOwnedFileImportResult {
        let affectedCourseIDs = additionalCourseIDs.union([courseID])
        try beginCourseFileMutation(courseIDs: affectedCourseIDs)
        defer {
            finishCourseFileMutation(courseIDs: affectedCourseIDs)
        }
        guard let root = courseRootURL(for: courseID),
              let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(root),
              let canonicalRootIdentity = importedFileIdentityResolver(canonicalRoot) else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        if let sourceURL, CourseProjectPathPolicy.contains(canonicalRoot, sourceURL) {
            throw CourseOwnedFileError.sourceAlreadyInsideCourse
        }
        guard isSupportedCourseFileName(fileName, role: role) else {
            throw CourseOwnedFileError.unsupportedFile
        }

        let destinationDirectory = try courseOwnedDestinationDirectory(
            role: role,
            inside: canonicalRoot
        )
        guard let destinationDirectoryIdentity = importedFileIdentityResolver(destinationDirectory) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let targetURL = try resolvedCourseImportTarget(
            fileName: fileName,
            destinationDirectory: destinationDirectory,
            role: role,
            conflictResolution: conflictResolution
        )
        guard CourseProjectPathPolicy.contains(destinationDirectory, targetURL, includingRoot: false),
              CourseProjectPathPolicy.contains(canonicalRoot, targetURL, includingRoot: false) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let replacingItemIndex = try replacementItemIndex(
            at: targetURL,
            courseID: courseID,
            conflictResolution: conflictResolution
        )
        let replacesExistingTarget = conflictResolution == .replace
            && FileManager.default.fileExists(atPath: targetURL.path)
        guard let targetRelativePath = CourseProjectPathPolicy.relativePath(
            of: targetURL,
            inside: canonicalRoot
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let sourceSnapshot: CourseFileSnapshot
        if let sourceURL, let sourceIdentity {
            do {
                sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
                    at: sourceURL,
                    expectedIdentity: sourceIdentity
                )
            } catch {
                throw CourseOwnedFileError.sourceIdentityChanged
            }
        } else if let generatedData {
            sourceSnapshot = await courseProjectFileWorker.snapshot(of: generatedData)
        } else {
            throw CourseOwnedFileError.verificationFailed
        }

        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: canonicalRoot
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(transactionDirectory) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let payloadURL = transactionDirectory.appendingPathComponent("payload", isDirectory: false)
        let journalURL = transactionDirectory.appendingPathComponent("journal.json", isDirectory: false)
        let sourceQuarantineURL = sourceURL.map {
            $0.deletingLastPathComponent().appendingPathComponent(
                ".\($0.lastPathComponent).weibei-quarantine-\(transactionID.uuidString.lowercased())",
                isDirectory: false
            )
        }
        let replacementTargetItemID = replacingItemIndex.map { importedItems[$0].id }
        let itemID = replacementTargetItemID
            ?? preservingItemID
            ?? Self.makeImportedItemID()
        let retiredSourceItemID = preservingItemID.flatMap { sourceItemID in
            replacementTargetItemID != nil && replacementTargetItemID != sourceItemID
                ? sourceItemID
                : nil
        }
        var journal = PendingCourseFileTransactionJournal(
            transactionID: transactionID,
            transactionDirectoryIdentity: transactionDirectoryIdentity,
            courseID: courseID,
            role: role,
            itemID: itemID,
            retiredSourceItemID: retiredSourceItemID,
            sourcePath: sourceURL?.path,
            sourceQuarantinePath: sourceQuarantineURL?.path,
            sourceIdentity: sourceIdentity,
            sourceSnapshot: sourceSnapshot,
            targetRelativePath: targetRelativePath,
            destinationDirectoryIdentity: destinationDirectoryIdentity,
            stagedIdentity: nil,
            targetIdentity: nil,
            replacedTargetIdentity: nil,
            replacedTargetSnapshot: nil,
            replacedRollbackIdentity: nil,
            replacedTrashPath: nil,
            stage: .prepared
        )
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNotes = notesByItemID
        let previousPendingNoteWrites = pendingNoteWritesByItemID
        let previousBackingDigests = noteBackingContentDigestsByItemID
        let previousLoadedCourseNotes = loadedCourseNoteTextByItemID
        let previousSelectedItemID = selectedItemID
        let previousActiveNotebookItemID = activeNotebookItemID
        let previousCourseWorkspaceTargetItemID = courseWorkspaceTargetItemID
        let previousNoteSourceLinks = noteSourceLinks
        let previousStudyLocations = studyLocationsByItemID
        let previousCourseStudyLocations = studyLocationsByCourseID
        let previousStudySessions = studySessions
        let previousSelectionAskThreads = selectionAskThreads
        let previousStagedNoteDraft = stagedNoteDraft
        let previousNotebookCreationDraft = notebookCreationDraft
        let previousNotebookRenameDraft = notebookRenameDraft
        let previousPendingNotePersistence = pendingNotePersistenceByItemID
        let previousBackNavigationStack = backNavigationStack
        let previousForwardNavigationStack = forwardNavigationStack
        var placedTargetIdentity: ImportedFileIdentity?
        var workspaceCommitted = false
        let replacementQuarantineURL = transactionDirectory.appendingPathComponent(
            "replaced-target",
            isDirectory: false
        )
        let replacementRollbackURL = transactionDirectory.appendingPathComponent(
            "replacement-rollback",
            isDirectory: false
        )

        do {
            try await writeCourseFileTransactionJournalInBackground(journal, to: journalURL)
            try courseProjectMutationHook(.beforeCourseFileStagingCopy)
            let stagedIdentity = try await courseProjectFileWorker.copyAndVerify(
                from: sourceURL,
                generatedData: generatedData,
                to: payloadURL,
                expectedSnapshot: sourceSnapshot
            )
            try courseProjectMutationHook(.afterCourseFileStagingCopy)

            journal.stagedIdentity = stagedIdentity
            journal.stage = .staged
            try await writeCourseFileTransactionJournalInBackground(journal, to: journalURL)

            if let sourceURL, let sourceIdentity {
                do {
                    _ = try await courseProjectFileWorker.stableSnapshot(
                        at: sourceURL,
                        expectedIdentity: sourceIdentity,
                        expectedSnapshot: sourceSnapshot
                    )
                } catch {
                    throw CourseOwnedFileError.sourceIdentityChanged
                }
            }
            if replacesExistingTarget {
                guard let replacementIdentity = importedFileIdentityResolver(targetURL) else {
                    throw CourseOwnedFileError.targetConflict(targetURL)
                }
                let replacementSnapshot = try await courseProjectFileWorker.stableSnapshot(
                    at: targetURL,
                    expectedIdentity: replacementIdentity
                )
                journal.replacedTargetIdentity = replacementIdentity
                journal.replacedTargetSnapshot = replacementSnapshot
                journal.stage = .replacementPreparing
                try await writeCourseFileTransactionJournalInBackground(
                    journal,
                    to: journalURL
                )
                let rollbackIdentity = try await courseProjectFileWorker.reserveRollbackFile(
                    at: replacementRollbackURL
                )
                try courseProjectMutationHook(
                    .afterCourseFileRollbackArtifactCreationBeforeJournalIdentity
                )
                journal.replacedRollbackIdentity = rollbackIdentity
                journal.stage = .replacementRollbackReserved
                try await writeCourseFileTransactionJournalInBackground(
                    journal,
                    to: journalURL
                )
                guard await courseProjectFileWorker.isolateWithoutReplacement(
                    from: targetURL,
                    to: replacementQuarantineURL
                ) else {
                    throw CourseOwnedFileError.targetConflict(targetURL)
                }
                try courseProjectMutationHook(
                    .afterCourseFileReplacementIsolationBeforeJournal
                )
                _ = try await courseProjectFileWorker.stableSnapshot(
                    at: replacementQuarantineURL,
                    expectedIdentity: replacementIdentity,
                    expectedSnapshot: replacementSnapshot
                )
                journal.stage = .replacementIsolated
                try await writeCourseFileTransactionJournalInBackground(journal, to: journalURL)
                try await courseProjectFileWorker.fillReservedRollbackFile(
                    from: replacementQuarantineURL,
                    to: replacementRollbackURL,
                    expectedDestinationIdentity: rollbackIdentity,
                    expectedSnapshot: replacementSnapshot
                )
                try courseProjectMutationHook(
                    .afterCourseFileReplacementRollbackCopyBeforeJournal
                )
                journal.stage = .replacementRollbackPrepared
                try await writeCourseFileTransactionJournalInBackground(
                    journal,
                    to: journalURL
                )
                let trashURL = try await courseProjectFileWorker
                    .moveReplacedFileToTrash(
                        at: replacementQuarantineURL,
                        selfCheckDestination: transactionDirectory
                            .appendingPathComponent("trashed-replaced-target")
                    )
                _ = try await courseProjectFileWorker.stableSnapshot(
                    at: trashURL,
                    expectedIdentity: replacementIdentity,
                    expectedSnapshot: replacementSnapshot
                )
                try courseProjectMutationHook(
                    .afterCourseFileReplacementTrashMoveBeforeJournal
                )
                journal.replacedTrashPath = trashURL.path
                journal.stage = .replacementTrashed
                try await writeCourseFileTransactionJournalInBackground(
                    journal,
                    to: journalURL
                )
                try courseProjectMutationHook(.afterCourseFileReplacementTrashed)
            }
            try courseProjectMutationHook(.beforeCourseFileAtomicPlacement)
            let targetIdentity: ImportedFileIdentity
            do {
                targetIdentity = try await courseProjectFileWorker.placeWithoutReplacement(
                    from: payloadURL,
                    to: targetURL,
                    courseRoot: canonicalRoot,
                    destinationDirectory: destinationDirectory,
                    expectedDestinationIdentity: destinationDirectoryIdentity,
                    expectedSnapshot: sourceSnapshot,
                    beforeRename: {
                        try self.courseProjectMutationHook(
                            .afterCourseFileDestinationValidationBeforeRename
                        )
                    }
                )
            } catch CourseProjectFileWorkerError.targetExists {
                throw CourseOwnedFileError.targetConflict(targetURL)
            } catch {
                throw CourseOwnedFileError.verificationFailed
            }
            try courseProjectMutationHook(.afterCourseFileAtomicPlacement)

            let resolvedTarget = targetURL.resolvingSymlinksInPath().standardizedFileURL
            guard CourseProjectPathPolicy.isSame(targetURL, resolvedTarget),
                  CourseProjectPathPolicy.contains(destinationDirectory, resolvedTarget, includingRoot: false),
                  CourseProjectPathPolicy.contains(canonicalRoot, resolvedTarget, includingRoot: false),
                  targetIdentity == stagedIdentity else {
                throw CourseOwnedFileError.verificationFailed
            }
            placedTargetIdentity = targetIdentity
            journal.targetIdentity = targetIdentity
            journal.stage = .placed
            try await writeCourseFileTransactionJournalInBackground(journal, to: journalURL)
            _ = try await revalidatedCourseFileTargetInBackground(
                courseID: courseID,
                expectedRoot: canonicalRoot,
                expectedRootIdentity: canonicalRootIdentity,
                role: role,
                expectedDestinationIdentity: destinationDirectoryIdentity,
                targetURL: resolvedTarget,
                expectedIdentity: targetIdentity,
                expectedSnapshot: sourceSnapshot
            )

            let targetInfo = try await courseProjectFileWorker.metadata(at: resolvedTarget)
            if let retiredSourceItemID {
                replaceItemIDEverywhere(retiredSourceItemID, with: itemID)
                importedItems.removeAll { $0.id == retiredSourceItemID }
            }
            let existingItemIndex = importedItems.firstIndex { $0.id == itemID }
            let previousItem = existingItemIndex.map { importedItems[$0] }
            var item = StudyItem(
                id: itemID,
                title: resolvedTarget.deletingPathExtension().lastPathComponent,
                subtitle: resolvedTarget.lastPathComponent,
                kind: StudyItemKind.detect(from: resolvedTarget),
                urlPath: resolvedTarget.path,
                importedFileIdentity: targetIdentity,
                importedFileBookmarkData: nil,
                importedFileLastKnownPath: resolvedTarget.path,
                isSample: false,
                isNotebookNote: role == .note,
                storage: .courseOwned(ownerCourseID: courseID),
                contentRevision: replacingItemIndex == nil
                    ? (previousItem?.contentRevision ?? 1)
                    : (previousItem?.contentRevision ?? 0) &+ 1,
                contentDigest: sourceSnapshot.sha256,
                fileByteCount: targetInfo.byteCount,
                fileModificationTimeNanoseconds: targetInfo.modificationTimeNanoseconds
            )
            let membership = CourseItemMembership(
                courseID: courseID,
                itemID: itemID,
                courseRelativePath: targetRelativePath,
                entryIdentity: targetIdentity,
                documentIdentifier: targetInfo.identity == targetIdentity
                    ? courseFileDocumentIdentifier(at: resolvedTarget)
                    : nil
            )
            if let existingItemIndex {
                item.id = importedItems[existingItemIndex].id
                importedItems[existingItemIndex] = item
                courseItemMemberships.removeAll { $0.itemID == item.id }
            } else {
                importedItems.append(item)
            }
            courseItemMemberships.append(membership)
            if role == .note {
                noteBackingContentDigestsByItemID[itemID] = sourceSnapshot.sha256
            }
            try courseProjectMutationHook(.beforeCourseFileWorkspaceSave)
            _ = try await revalidatedCourseFileTargetInBackground(
                courseID: courseID,
                expectedRoot: canonicalRoot,
                expectedRootIdentity: canonicalRootIdentity,
                role: role,
                expectedDestinationIdentity: destinationDirectoryIdentity,
                targetURL: resolvedTarget,
                expectedIdentity: targetIdentity,
                expectedSnapshot: sourceSnapshot
            )
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            workspaceCommitted = true
            journal.stage = .workspaceCommitted
            try? await writeCourseFileTransactionJournalInBackground(journal, to: journalURL)

            var sourceCleanupPending = false
            if let sourceURL, let sourceIdentity {
                do {
                    try courseProjectMutationHook(.beforeCourseFileSourceRemoval)
                    _ = try await revalidatedCourseFileTargetInBackground(
                        courseID: courseID,
                        expectedRoot: canonicalRoot,
                        expectedRootIdentity: canonicalRootIdentity,
                        role: role,
                        expectedDestinationIdentity: destinationDirectoryIdentity,
                        targetURL: resolvedTarget,
                        expectedIdentity: targetIdentity,
                        expectedSnapshot: sourceSnapshot
                    )
                    _ = try await courseProjectFileWorker.stableSnapshot(
                        at: sourceURL,
                        expectedIdentity: sourceIdentity,
                        expectedSnapshot: sourceSnapshot
                    )
                    guard let sourceQuarantineURL else {
                        throw CourseOwnedFileError.verificationFailed
                    }
                    let removalOutcome = await courseProjectFileWorker.isolateAndRemoveVerifiedFile(
                        at: sourceURL,
                        quarantineURL: sourceQuarantineURL,
                        expectedIdentity: sourceIdentity,
                        expectedSnapshot: sourceSnapshot,
                        remover: courseFileSourceRemover
                    )
                    guard case .removed = removalOutcome else {
                        throw CourseOwnedFileError.sourceIdentityChanged
                    }
                } catch {
                    sourceCleanupPending = true
                    journal.stage = .sourceCleanupPending
                    try? await writeCourseFileTransactionJournalInBackground(journal, to: journalURL)
                }
            }
            if let rollbackIdentity = journal.replacedRollbackIdentity,
               let replacedSnapshot = journal.replacedTargetSnapshot {
                do {
                    try await courseProjectFileWorker.removeVerifiedFile(
                        at: replacementRollbackURL,
                        expectedIdentity: rollbackIdentity,
                        expectedSnapshot: replacedSnapshot,
                        beforeRemoval: {
                            try self.courseProjectMutationHook(
                                .afterCourseFileCleanupValidationBeforeIsolation
                            )
                        }
                    )
                } catch {
                    sourceCleanupPending = true
                    journal.stage = .sourceCleanupPending
                    try? await writeCourseFileTransactionJournalInBackground(
                        journal,
                        to: journalURL
                    )
                }
            }
            if let replacedTrashPath = journal.replacedTrashPath {
                do {
                    try await courseProjectFileWorker.finishSelfCheckTrash(
                        at: URL(fileURLWithPath: replacedTrashPath)
                    )
                } catch {
                    sourceCleanupPending = true
                    journal.stage = .sourceCleanupPending
                    try? await writeCourseFileTransactionJournalInBackground(journal, to: journalURL)
                }
            }
            if !sourceCleanupPending {
                await safelyRemoveCourseFileTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
            }
            courseDocumentSearchIndex.schedule([item])
            invalidateAgentContext()
            return CourseOwnedFileImportResult(
                item: item,
                sourceCleanupPending: sourceCleanupPending
            )
        } catch {
            if WeiBeiSafetyTestMode.isEnabled, error is CourseProjectSimulatedCrash {
                throw error
            }
            if !workspaceCommitted {
                importedItems = previousImportedItems
                courseItemMemberships = previousMemberships
                notesByItemID = previousNotes
                pendingNoteWritesByItemID = previousPendingNoteWrites
                noteBackingContentDigestsByItemID = previousBackingDigests
                loadedCourseNoteTextByItemID = previousLoadedCourseNotes
                selectedItemID = previousSelectedItemID
                activeNotebookItemID = previousActiveNotebookItemID
                courseWorkspaceTargetItemID =
                    previousCourseWorkspaceTargetItemID
                noteSourceLinks = previousNoteSourceLinks
                studyLocationsByItemID = previousStudyLocations
                studyLocationsByCourseID = previousCourseStudyLocations
                studySessions = previousStudySessions
                selectionAskThreads = previousSelectionAskThreads
                stagedNoteDraft = previousStagedNoteDraft
                notebookCreationDraft = previousNotebookCreationDraft
                notebookRenameDraft = previousNotebookRenameDraft
                backNavigationStack = previousBackNavigationStack
                forwardNavigationStack = previousForwardNavigationStack
                let remappedIDs = Set(
                    [itemID, retiredSourceItemID].compactMap { $0 }
                )
                for remappedID in remappedIDs {
                    pendingNotePersistenceTasks.removeValue(
                        forKey: remappedID
                    )?.cancel()
                }
                pendingNotePersistenceByItemID =
                    previousPendingNotePersistence
                for remappedID in remappedIDs {
                    if let pending =
                        previousPendingNotePersistence[remappedID] {
                        scheduleNotePersistence(
                            pending.markdown,
                            for: pending.item
                        )
                    }
                }
                let expectedTargetIdentity =
                    placedTargetIdentity ?? journal.targetIdentity ?? journal.stagedIdentity
                let destinationStillTrusted = (try? revalidatedCourseFileDestination(
                    courseID: courseID,
                    expectedRoot: canonicalRoot,
                    expectedRootIdentity: canonicalRootIdentity,
                    role: role,
                    expectedDestinationIdentity: destinationDirectoryIdentity
                )) != nil
                let sourceStillVerified: Bool
                if let sourceURL, let sourceIdentity {
                    sourceStillVerified = (try? await courseProjectFileWorker.stableSnapshot(
                        at: sourceURL,
                        expectedIdentity: sourceIdentity,
                        expectedSnapshot: sourceSnapshot
                    )) != nil
                } else {
                    sourceStillVerified = false
                }
                if sourceStillVerified,
                   placedTargetIdentity == nil,
                   journal.targetIdentity == nil,
                   !replacesExistingTarget {
                    await safelyRemoveCourseFileTransactionDirectoryInBackground(
                        transactionDirectory,
                        expectedIdentity: transactionDirectoryIdentity
                    )
                } else if destinationStillTrusted, sourceStillVerified {
                    let targetQuarantineURL = transactionDirectory
                        .appendingPathComponent("target-quarantine", isDirectory: false)
                    var targetSafelyAbsent =
                        !FileManager.default.fileExists(atPath: targetURL.path)
                        || (placedTargetIdentity == nil
                            && journal.targetIdentity == nil
                            && !replacesExistingTarget)
                    if let expectedTargetIdentity, !targetSafelyAbsent {
                        let removalOutcome = await courseProjectFileWorker.isolateAndRemoveVerifiedFile(
                            at: targetURL,
                            quarantineURL: targetQuarantineURL,
                            expectedIdentity: expectedTargetIdentity,
                            expectedSnapshot: sourceSnapshot,
                            remover: { try FileManager.default.removeItem(at: $0) }
                        )
                        if case .removed = removalOutcome {
                            targetSafelyAbsent = true
                        }
                    }
                    var replacementRestored = journal.replacedTargetIdentity == nil
                    let replacementRestore: (url: URL, identity: ImportedFileIdentity?) = {
                        if FileManager.default.fileExists(
                            atPath: replacementQuarantineURL.path
                        ) {
                            return (
                                replacementQuarantineURL,
                                journal.replacedTargetIdentity
                            )
                        }
                        if FileManager.default.fileExists(
                            atPath: replacementRollbackURL.path
                        ) {
                            return (
                                replacementRollbackURL,
                                journal.replacedRollbackIdentity
                            )
                        }
                        return (
                            journal.replacedTrashPath.map {
                                URL(fileURLWithPath: $0).standardizedFileURL
                            } ?? replacementQuarantineURL,
                            journal.replacedTargetIdentity
                        )
                    }()
                    if let replacedIdentity = journal.replacedTargetIdentity,
                       let replacedSnapshot = journal.replacedTargetSnapshot,
                       replacementRestore.identity != nil,
                       targetSafelyAbsent,
                       (try? await courseProjectFileWorker.stableSnapshot(
                        at: replacementRestore.url,
                        expectedIdentity: replacementRestore.identity
                            ?? replacedIdentity,
                        expectedSnapshot: replacedSnapshot
                       )) != nil,
                       case .restored = await courseProjectFileWorker.restoreIsolatedFile(
                        from: replacementRestore.url,
                        to: targetURL
                       ) {
                        replacementRestored = true
                    }
                    if replacementRestored,
                       let rollbackIdentity = journal.replacedRollbackIdentity,
                       FileManager.default.fileExists(
                        atPath: replacementRollbackURL.path
                       ) {
                        switch journal.stage {
                        case .replacementRollbackReserved, .replacementIsolated:
                            try? await courseProjectFileWorker.removeFileIfIdentityMatches(
                                at: replacementRollbackURL,
                                expectedIdentity: rollbackIdentity
                            )
                        default:
                            try? await courseProjectFileWorker.removeVerifiedFile(
                                at: replacementRollbackURL,
                                expectedIdentity: rollbackIdentity,
                                expectedSnapshot: journal.replacedTargetSnapshot
                                    ?? sourceSnapshot
                            )
                        }
                    }
                    if replacementRestored,
                       let replacedTrashPath = journal.replacedTrashPath,
                       let replacedIdentity = journal.replacedTargetIdentity,
                       let replacedSnapshot = journal.replacedTargetSnapshot {
                        let trashURL = URL(
                            fileURLWithPath: replacedTrashPath
                        ).standardizedFileURL
                        if FileManager.default.fileExists(atPath: trashURL.path) {
                            try? await courseProjectFileWorker.removeVerifiedFile(
                                at: trashURL,
                                expectedIdentity: replacedIdentity,
                                expectedSnapshot: replacedSnapshot
                            )
                        }
                    }
                    if targetSafelyAbsent, replacementRestored {
                        await safelyRemoveCourseFileTransactionDirectoryInBackground(
                            transactionDirectory,
                            expectedIdentity: transactionDirectoryIdentity
                        )
                    }
                }
            }
            throw error
        }
    }

    private func validatedCourseImportSource(_ sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let source = sourceURL.standardizedFileURL
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
        let values = try source.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              CourseProjectPathPolicy.isSame(source, resolvedSource) else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        return resolvedSource
    }

    private func isSupportedCourseFileName(
        _ fileName: String,
        role: CourseOwnedFileRole
    ) -> Bool {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              URL(fileURLWithPath: fileName).lastPathComponent == fileName else {
            return false
        }
        let fileURL = URL(fileURLWithPath: fileName)
        switch role {
        case .material:
            return Self.isSupportedCourseFile(fileURL)
        case .note:
            return Self.isMarkdownFile(fileURL)
        }
    }

    private func resolvedCourseImportTarget(
        fileName: String,
        destinationDirectory: URL,
        role: CourseOwnedFileRole,
        conflictResolution: CourseFileConflictResolution
    ) throws -> URL {
        let requestedName: String
        switch conflictResolution {
        case .cancel, .replace:
            requestedName = fileName
        case .keepBoth(let preferredFileName):
            let preferred = preferredFileName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let preferred, !preferred.isEmpty {
                requestedName = preferred
            } else {
                requestedName = fileName
            }
        }
        guard isSupportedCourseFileName(requestedName, role: role) else {
            throw CourseOwnedFileError.unsupportedFile
        }
        let requested = destinationDirectory
            .appendingPathComponent(requestedName, isDirectory: false)
            .standardizedFileURL
        switch conflictResolution {
        case .cancel, .replace:
            return requested
        case .keepBoth:
            guard FileManager.default.fileExists(atPath: requested.path) else {
                return requested
            }
            let stem = requested.deletingPathExtension().lastPathComponent
            let pathExtension = requested.pathExtension
            for suffix in 2...9_999 {
                let candidateName = pathExtension.isEmpty
                    ? "\(stem) \(suffix)"
                    : "\(stem) \(suffix).\(pathExtension)"
                let candidate = destinationDirectory.appendingPathComponent(candidateName)
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            throw CourseOwnedFileError.targetConflict(requested)
        }
    }

    private func replacementItemIndex(
        at targetURL: URL,
        courseID: UUID,
        conflictResolution: CourseFileConflictResolution
    ) throws -> Int? {
        let exists = FileManager.default.fileExists(atPath: targetURL.path)
        switch conflictResolution {
        case .cancel:
            if exists { throw CourseOwnedFileError.targetConflict(targetURL) }
            return nil
        case .keepBoth:
            if exists { throw CourseOwnedFileError.targetConflict(targetURL) }
            return nil
        case .replace:
            guard exists else { return nil }
            let membership = courseItemMemberships.first {
                $0.courseID == courseID
                    && $0.courseRelativePath.map {
                        CourseProjectPathPolicy.isSame(
                            targetURL,
                            courseRootURL(for: courseID)?.appendingPathComponent($0) ?? targetURL
                        )
                    } == true
            }
            guard let membership,
                  let index = importedItems.firstIndex(where: { $0.id == membership.itemID }) else {
                return nil
            }
            if case .shared = importedItems[index].storage {
                throw CourseOwnedFileError.replacementTargetIsShared
            }
            return index
        }
    }

    private func courseOwnedDestinationDirectory(
        role: CourseOwnedFileRole,
        inside root: URL
    ) throws -> URL {
        let rawDirectory = root.appendingPathComponent(role.directoryName, isDirectory: true)
        return try realCourseOwnedDirectory(
            rawDirectory,
            inside: root,
            createIfMissing: true
        )
    }

    private func realCourseOwnedDirectory(
        _ rawDirectory: URL,
        inside parent: URL,
        createIfMissing: Bool
    ) throws -> URL {
        if !FileManager.default.fileExists(atPath: rawDirectory.path) {
            guard createIfMissing else {
                throw CourseOwnedFileError.unsafeCoursePath
            }
            try FileManager.default.createDirectory(
                at: rawDirectory,
                withIntermediateDirectories: false
            )
        }
        let values = try rawDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let directory = try CourseProjectPathPolicy.existingDirectory(rawDirectory)
        guard CourseProjectPathPolicy.isSame(rawDirectory.standardizedFileURL, directory),
              CourseProjectPathPolicy.contains(parent, directory, includingRoot: false) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        return directory
    }

    private func courseFileTransactionDirectory(
        transactionID: UUID,
        inside root: URL
    ) throws -> URL {
        let metadata = try realCourseOwnedDirectory(
            root.appendingPathComponent(".weibei", isDirectory: true),
            inside: root,
            createIfMissing: false
        )
        let rawTransactions = metadata.appendingPathComponent("transactions", isDirectory: true)
        let transactions = try realCourseOwnedDirectory(
            rawTransactions,
            inside: metadata,
            createIfMissing: true
        )
        let transactionDirectory = transactions.appendingPathComponent(
            transactionID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: transactionDirectory,
            withIntermediateDirectories: false
        )
        return try realCourseOwnedDirectory(
            transactionDirectory,
            inside: transactions,
            createIfMissing: false
        )
    }

    private func writeCourseFileTransactionJournal(
        _ journal: PendingCourseFileTransactionJournal,
        to url: URL
    ) throws {
        try JSONEncoder().encode(journal).write(to: url, options: [.atomic])
    }

    private func writeCourseFileTransactionJournalInBackground(
        _ journal: PendingCourseFileTransactionJournal,
        to url: URL
    ) async throws {
        try await courseProjectFileWorker.write(
            JSONEncoder().encode(journal),
            to: url
        )
    }

    private func stableCourseFileSnapshot(
        at url: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot? = nil
    ) throws -> CourseFileSnapshot {
        guard importedFileIdentityResolver(url) == expectedIdentity else {
            throw CourseOwnedFileError.sourceIdentityChanged
        }
        let snapshot = try courseFileSnapshot(at: url)
        guard importedFileIdentityResolver(url) == expectedIdentity,
              expectedSnapshot.map({ $0 == snapshot }) ?? true else {
            throw CourseOwnedFileError.sourceIdentityChanged
        }
        return snapshot
    }

    nonisolated private static func streamingCourseFileSnapshot(
        at url: URL
    ) throws -> CourseFileSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += UInt64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return CourseFileSnapshot(byteCount: byteCount, sha256: digest)
    }

    private func courseFileSnapshot(at url: URL) throws -> CourseFileSnapshot {
        try Self.streamingCourseFileSnapshot(at: url)
    }

    private func courseFileDocumentIdentifier(at url: URL) -> UInt64? {
        guard let value = try? url.resourceValues(
            forKeys: [.documentIdentifierKey]
        ).documentIdentifier,
        value >= 0 else { return nil }
        return UInt64(value)
    }

    private func revalidatedCourseFileDestination(
        courseID: UUID,
        expectedRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        role: CourseOwnedFileRole,
        expectedDestinationIdentity: ImportedFileIdentity
    ) throws -> URL {
        guard let registeredRoot = courseRootURL(for: courseID),
              let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(registeredRoot),
              CourseProjectPathPolicy.isSame(canonicalRoot, expectedRoot),
              importedFileIdentityResolver(canonicalRoot) == expectedRootIdentity,
              let destinationDirectory = try? realCourseOwnedDirectory(
                canonicalRoot.appendingPathComponent(role.directoryName, isDirectory: true),
                inside: canonicalRoot,
                createIfMissing: false
              ),
              importedFileIdentityResolver(destinationDirectory) == expectedDestinationIdentity else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        return destinationDirectory
    }

    private func revalidatedCourseFileTarget(
        courseID: UUID,
        expectedRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        role: CourseOwnedFileRole,
        expectedDestinationIdentity: ImportedFileIdentity,
        targetURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) throws -> URL {
        let destinationDirectory = try revalidatedCourseFileDestination(
            courseID: courseID,
            expectedRoot: expectedRoot,
            expectedRootIdentity: expectedRootIdentity,
            role: role,
            expectedDestinationIdentity: expectedDestinationIdentity
        )
        let expectedTargetURL = destinationDirectory
            .appendingPathComponent(targetURL.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        guard CourseProjectPathPolicy.isSame(expectedTargetURL, targetURL),
              let rawValues = try? expectedTargetURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
              ]),
              rawValues.isRegularFile == true,
              rawValues.isSymbolicLink != true,
              rawValues.isAliasFile != true else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let resolved = expectedTargetURL.resolvingSymlinksInPath().standardizedFileURL
        guard CourseProjectPathPolicy.isSame(expectedTargetURL, resolved),
              CourseProjectPathPolicy.contains(destinationDirectory, resolved, includingRoot: false),
              CourseProjectPathPolicy.contains(expectedRoot, resolved, includingRoot: false),
              importedFileIdentityResolver(resolved) == expectedIdentity,
              (try? courseFileSnapshot(at: resolved)) == expectedSnapshot else {
            throw CourseOwnedFileError.verificationFailed
        }
        return resolved
    }

    private func revalidatedCourseFileTargetInBackground(
        courseID: UUID,
        expectedRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        role: CourseOwnedFileRole,
        expectedDestinationIdentity: ImportedFileIdentity,
        targetURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) async throws -> URL {
        let destinationDirectory = try revalidatedCourseFileDestination(
            courseID: courseID,
            expectedRoot: expectedRoot,
            expectedRootIdentity: expectedRootIdentity,
            role: role,
            expectedDestinationIdentity: expectedDestinationIdentity
        )
        let expectedTargetURL = destinationDirectory
            .appendingPathComponent(targetURL.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        let resolved = expectedTargetURL.resolvingSymlinksInPath().standardizedFileURL
        guard CourseProjectPathPolicy.isSame(expectedTargetURL, targetURL),
              CourseProjectPathPolicy.isSame(expectedTargetURL, resolved),
              CourseProjectPathPolicy.contains(destinationDirectory, resolved, includingRoot: false),
              CourseProjectPathPolicy.contains(expectedRoot, resolved, includingRoot: false),
              importedFileIdentityResolver(resolved) == expectedIdentity else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        do {
            _ = try await courseProjectFileWorker.stableSnapshot(
                at: resolved,
                expectedIdentity: expectedIdentity,
                expectedSnapshot: expectedSnapshot
            )
        } catch {
            throw CourseOwnedFileError.verificationFailed
        }
        return resolved
    }

    private func atomicRenameWithoutReplacement(from source: URL, to destination: URL) -> Bool {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return false }
                return Darwin.renamex_np(
                    sourcePath,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                ) == 0
            }
        }
    }

    private func restoreIsolatedCourseFile(
        from quarantineURL: URL,
        to originalURL: URL
    ) -> CourseFileRemovalOutcome {
        guard FileManager.default.fileExists(atPath: quarantineURL.path) else {
            return .quarantined(quarantineURL)
        }
        guard !FileManager.default.fileExists(atPath: originalURL.path),
              atomicRenameWithoutReplacement(from: quarantineURL, to: originalURL) else {
            return .quarantined(quarantineURL)
        }
        return .restored
    }

    private func atomicallyIsolateVerifiedCourseFile(
        at originalURL: URL,
        quarantineURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: originalURL.path),
              !FileManager.default.fileExists(atPath: quarantineURL.path),
              atomicRenameWithoutReplacement(
                from: originalURL,
                to: quarantineURL
              ) else {
            return false
        }
        guard (try? stableCourseFileSnapshot(
            at: quarantineURL,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        )) != nil else {
            _ = restoreIsolatedCourseFile(
                from: quarantineURL,
                to: originalURL
            )
            return false
        }
        return true
    }

    private func atomicallyIsolateAndRemoveCourseFile(
        at originalURL: URL,
        quarantineURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot,
        remover: (URL) throws -> Void
    ) -> CourseFileRemovalOutcome {
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return FileManager.default.fileExists(atPath: quarantineURL.path)
                ? .quarantined(quarantineURL)
                : .removed
        }
        guard atomicallyIsolateVerifiedCourseFile(
            at: originalURL,
            quarantineURL: quarantineURL,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        ) else {
            return FileManager.default.fileExists(atPath: quarantineURL.path)
                ? .quarantined(quarantineURL)
                : .restored
        }
        do {
            try remover(quarantineURL)
        } catch {
            if !FileManager.default.fileExists(atPath: quarantineURL.path) {
                return .removed
            }
            return restoreIsolatedCourseFile(
                from: quarantineURL,
                to: originalURL
            )
        }
        guard FileManager.default.fileExists(atPath: quarantineURL.path) else {
            return .removed
        }
        return restoreIsolatedCourseFile(
            from: quarantineURL,
            to: originalURL
        )
    }

    private func safelyRemoveCourseFileTransactionDirectory(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) {
        guard importedFileIdentityResolver(transactionDirectory) == expectedIdentity,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: transactionDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey],
                options: []
              ),
              entries.allSatisfy({ ["journal.json", "payload"].contains($0.lastPathComponent) }) else {
            return
        }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.isAliasFile != true else {
                return
            }
        }
        for entry in entries {
            try? FileManager.default.removeItem(at: entry)
        }
        if (try? FileManager.default.contentsOfDirectory(atPath: transactionDirectory.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: transactionDirectory)
        }
    }

    private func safelyRemoveCourseFileTransactionDirectoryInBackground(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) async {
        await Task.detached(priority: .utility) {
            guard CourseProjectFileWorker.identity(at: transactionDirectory) == expectedIdentity,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: transactionDirectory,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                  ),
                  entries.allSatisfy({
                    ["journal.json", "payload"].contains($0.lastPathComponent)
                  }) else {
                return
            }
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                values.isAliasFile != true else {
                    return
                }
            }
            for entry in entries {
                try? FileManager.default.removeItem(at: entry)
            }
            if (try? FileManager.default.contentsOfDirectory(
                atPath: transactionDirectory.path
            ).isEmpty) == true {
                try? FileManager.default.removeItem(at: transactionDirectory)
            }
        }.value
    }

    private func safelyRemoveCourseMarkdownTransactionDirectoryInBackground(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) async {
        await Task.detached(priority: .utility) {
            guard CourseProjectFileWorker.identity(at: transactionDirectory)
                    == expectedIdentity,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: transactionDirectory,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                  ),
                  entries.allSatisfy({
                    ["course-note.json", "payload"]
                        .contains($0.lastPathComponent)
                  }) else {
                return
            }
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                values.isAliasFile != true else {
                    return
                }
            }
            for entry in entries {
                try? FileManager.default.removeItem(at: entry)
            }
            if (try? FileManager.default.contentsOfDirectory(
                atPath: transactionDirectory.path
            ).isEmpty) == true {
                try? FileManager.default.removeItem(at: transactionDirectory)
            }
        }.value
    }

    private func safelyRemoveSharedTransactionDirectoryInBackground(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) async {
        await Task.detached(priority: .utility) {
            guard CourseProjectFileWorker.identity(at: transactionDirectory) == expectedIdentity,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: transactionDirectory,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                  ),
                  entries.allSatisfy({
                    [
                        "shared.json",
                        "shared-link.json",
                        "shared-link-removal.json",
                        "payload",
                    ]
                        .contains($0.lastPathComponent)
                  }) else {
                return
            }
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                values.isAliasFile != true else {
                    return
                }
            }
            for entry in entries {
                try? FileManager.default.removeItem(at: entry)
            }
            if (try? FileManager.default.contentsOfDirectory(
                atPath: transactionDirectory.path
            ).isEmpty) == true {
                try? FileManager.default.removeItem(at: transactionDirectory)
            }
        }.value
    }

    private func recoverPendingCourseFileTransactionsInBackground() async {
        let importedItems = self.importedItems
        let memberships = courseItemMemberships
        let courseRootsByID = Dictionary(uniqueKeysWithValues: courses.compactMap { course in
            courseRootURL(for: course.id).map { root in (course.id, root) }
        })
        let inputs = courses.compactMap { course -> CourseRecoveryInput? in
            guard let root = courseRootURL(for: course.id) else { return nil }
            return CourseRecoveryInput(
                courseID: course.id,
                root: root,
                libraryRoot: courseLibraryRootURL,
                courseRootsByID: courseRootsByID,
                importedItems: importedItems,
                memberships: memberships
            )
        }
        let recoveredTargets = await Task.detached(priority: .utility) {
            var targets: [RecoveredCourseFileTarget] = []
            for input in inputs {
                targets.append(contentsOf: Self.recoverCourseTransactions(input))
            }
            return targets
        }.value
        guard !recoveredTargets.isEmpty else { return }
        let previousItems = self.importedItems
        let previousMemberships = courseItemMemberships
        let previousBackingDigests = noteBackingContentDigestsByItemID
        for recovered in recoveredTargets {
            let journal = recovered.journal
            if let retiredSourceItemID = journal.retiredSourceItemID,
               retiredSourceItemID != journal.itemID {
                replaceItemIDEverywhere(retiredSourceItemID, with: journal.itemID)
                self.importedItems.removeAll { $0.id == retiredSourceItemID }
            }
            let existingIndex = self.importedItems.firstIndex {
                $0.id == journal.itemID
            }
            let previousRevision = existingIndex.map {
                self.importedItems[$0].contentRevision
            } ?? 0
            let item = StudyItem(
                id: journal.itemID,
                title: recovered.targetURL.deletingPathExtension().lastPathComponent,
                subtitle: recovered.targetURL.lastPathComponent,
                kind: StudyItemKind.detect(from: recovered.targetURL),
                urlPath: recovered.targetURL.path,
                importedFileIdentity: recovered.targetIdentity,
                importedFileBookmarkData: nil,
                importedFileLastKnownPath: recovered.targetURL.path,
                isSample: false,
                isNotebookNote: journal.role == .note,
                storage: .courseOwned(ownerCourseID: journal.courseID),
                contentRevision: max(1, previousRevision &+ (existingIndex == nil ? 0 : 1)),
                contentDigest: journal.sourceSnapshot.sha256,
                fileByteCount: recovered.metadata.byteCount,
                fileModificationTimeNanoseconds:
                    recovered.metadata.modificationTimeNanoseconds
            )
            if let existingIndex {
                self.importedItems[existingIndex] = item
            } else {
                self.importedItems.append(item)
            }
            courseItemMemberships.removeAll { $0.itemID == journal.itemID }
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: journal.courseID,
                    itemID: journal.itemID,
                    courseRelativePath: journal.targetRelativePath,
                    entryIdentity: recovered.targetIdentity
                )
            )
            if journal.role == .note {
                noteBackingContentDigestsByItemID[journal.itemID] =
                    journal.sourceSnapshot.sha256
            }
        }
        guard await persistWorkspaceNow() else {
            self.importedItems = previousItems
            courseItemMemberships = previousMemberships
            noteBackingContentDigestsByItemID = previousBackingDigests
            workspaceSaveError = ui(
                "课程中有已校验文件等待恢复，状态保存成功后会自动显示。",
                "Verified course files are waiting to be recovered after workspace saving succeeds."
            )
            return
        }
        let updatedItems = self.importedItems
        let updatedMemberships = courseItemMemberships
        let updatedInputs = inputs.map {
            CourseRecoveryInput(
                courseID: $0.courseID,
                root: $0.root,
                libraryRoot: $0.libraryRoot,
                courseRootsByID: $0.courseRootsByID,
                importedItems: updatedItems,
                memberships: updatedMemberships
            )
        }
        await Task.detached(priority: .utility) {
            for input in updatedInputs {
                _ = Self.recoverCourseTransactions(input)
            }
        }.value
    }

    func recoverCourseTransactionsForSelfCheck() throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let maintenanceTask = courseReconciliationTask
        maintenanceTask?.cancel()
        courseReconciliationTask = nil
        try waitForCourseFileOperation {
            await maintenanceTask?.value
            await self.recoverPendingCourseFileTransactionsInBackground()
        }
    }

    nonisolated private static func recoverCourseTransactions(
        _ input: CourseRecoveryInput
    ) -> [RecoveredCourseFileTarget] {
        let fileManager = FileManager.default
        guard let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(input.root),
              CourseProjectPathPolicy.isSame(canonicalRoot, input.root.resolvingSymlinksInPath()) else {
            return []
        }
        let transactions = canonicalRoot
            .appendingPathComponent(".weibei/transactions", isDirectory: true)
        guard let values = try? transactions.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ]),
        values.isDirectory == true,
        values.isSymbolicLink != true,
        values.isAliasFile != true,
        CourseProjectPathPolicy.contains(canonicalRoot, transactions, includingRoot: false),
        let directories = try? fileManager.contentsOfDirectory(
            at: transactions,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ],
            options: []
        ) else {
            return []
        }
        var recoveredTargets: [RecoveredCourseFileTarget] = []
        for transactionDirectory in directories {
            guard UUID(uuidString: transactionDirectory.lastPathComponent) != nil,
                  let directoryValues = try? transactionDirectory.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                  ]),
                  directoryValues.isDirectory == true,
                  directoryValues.isSymbolicLink != true,
                  directoryValues.isAliasFile != true,
                  CourseProjectPathPolicy.contains(
                    transactions,
                    transactionDirectory,
                    includingRoot: false
                  ) else {
                continue
            }
            if let recovered = recoverCourseTransaction(
                at: transactionDirectory,
                input: input,
                canonicalRoot: canonicalRoot
            ) {
                recoveredTargets.append(recovered)
            }
        }
        return recoveredTargets
    }

    nonisolated private static func recoverCourseTransaction(
        at transactionDirectory: URL,
        input: CourseRecoveryInput,
        canonicalRoot: URL
    ) -> RecoveredCourseFileTarget? {
        let fileManager = FileManager.default
        if fileManager.fileExists(
            atPath: transactionDirectory.appendingPathComponent(
                "course-note.json"
            ).path
        ) {
            recoverCourseMarkdownWriteTransaction(
                at: transactionDirectory,
                input: input,
                canonicalRoot: canonicalRoot
            )
            return nil
        }
        if fileManager.fileExists(
            atPath: transactionDirectory.appendingPathComponent(
                "shared-link-removal.json"
            ).path
        ) {
            recoverSharedLinkRemovalTransaction(
                at: transactionDirectory,
                input: input,
                canonicalRoot: canonicalRoot
            )
            return nil
        }
        if fileManager.fileExists(
            atPath: transactionDirectory.appendingPathComponent(
                "shared-link.json"
            ).path
        ) {
            recoverSharedLinkCourseTransaction(
                at: transactionDirectory,
                input: input,
                canonicalRoot: canonicalRoot
            )
            return nil
        }
        if fileManager.fileExists(
            atPath: transactionDirectory.appendingPathComponent("shared.json").path
        ) {
            recoverSharedCourseTransaction(
                at: transactionDirectory,
                input: input,
                canonicalRoot: canonicalRoot
            )
            return nil
        }
        let journalURL = transactionDirectory.appendingPathComponent("journal.json")
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(
                PendingCourseFileTransactionJournal.self,
                from: data
              ),
              journal.courseID == input.courseID,
              journal.transactionID.uuidString.caseInsensitiveCompare(
                transactionDirectory.lastPathComponent
              ) == .orderedSame,
              CourseProjectFileWorker.identity(at: transactionDirectory)
                == journal.transactionDirectoryIdentity,
              let targetURL = backgroundTargetURL(
                journal: journal,
                root: canonicalRoot
              ) else {
            return nil
        }
        let targetIdentity = journal.targetIdentity ?? journal.stagedIdentity
        let targetMatches = targetIdentity.map {
            backgroundFileMatches(
                targetURL,
                identity: $0,
                snapshot: journal.sourceSnapshot
            )
        } ?? false
        let item = input.importedItems.first {
            $0.id == journal.itemID
                && $0.contentDigest == journal.sourceSnapshot.sha256
                && $0.importedFileIdentity == targetIdentity
        }
        let membership = input.memberships.first {
            $0.courseID == input.courseID
                && $0.itemID == journal.itemID
                && $0.courseRelativePath == journal.targetRelativePath
                && $0.entryIdentity == targetIdentity
        }
        let workspaceCommitted = item != nil && membership != nil && targetMatches
        let replacementURL = transactionDirectory.appendingPathComponent("replaced-target")
        let replacementRollbackURL = transactionDirectory.appendingPathComponent(
            "replacement-rollback"
        )
        let unrecordedSelfCheckTrashURL = transactionDirectory.appendingPathComponent(
            "trashed-replaced-target"
        )
        let trashedReplacementURL = journal.replacedTrashPath.map {
            backgroundCanonicalRawPath(URL(fileURLWithPath: $0))
        }

        if workspaceCommitted {
            var cleanupComplete = true
            if let sourcePath = journal.sourcePath,
               let sourceIdentity = journal.sourceIdentity {
                let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
                let quarantineURL = sourceURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        ".\(sourceURL.lastPathComponent).weibei-quarantine-\(journal.transactionID.uuidString.lowercased())"
                    )
                if fileManager.fileExists(atPath: quarantineURL.path) {
                    guard backgroundFileMatches(
                        quarantineURL,
                        identity: sourceIdentity,
                        snapshot: journal.sourceSnapshot
                    ) else {
                        return nil
                    }
                    try? fileManager.removeItem(at: quarantineURL)
                    cleanupComplete = !fileManager.fileExists(atPath: quarantineURL.path)
                } else if fileManager.fileExists(atPath: sourceURL.path) {
                    if backgroundFileMatches(
                        sourceURL,
                        identity: sourceIdentity,
                        snapshot: journal.sourceSnapshot
                    ) {
                        cleanupComplete = backgroundRemoveVerified(
                            sourceURL,
                            quarantineURL: quarantineURL,
                            identity: sourceIdentity,
                            snapshot: journal.sourceSnapshot
                        )
                    }
                }
            }
            if let replacedIdentity = journal.replacedTargetIdentity,
               let replacedSnapshot = journal.replacedTargetSnapshot,
               fileManager.fileExists(atPath: replacementURL.path) {
                guard backgroundFileMatches(
                    replacementURL,
                    identity: replacedIdentity,
                    snapshot: replacedSnapshot
                ) else {
                    return nil
                }
                var trashed: NSURL?
                do {
                    try fileManager.trashItem(at: replacementURL, resultingItemURL: &trashed)
                } catch {
                    cleanupComplete = false
                }
            }
            if let trashedReplacementURL,
               CourseProjectPathPolicy.contains(
                transactionDirectory,
                trashedReplacementURL,
                includingRoot: false
               ),
               fileManager.fileExists(atPath: trashedReplacementURL.path) {
                guard let replacedIdentity = journal.replacedTargetIdentity,
                      let replacedSnapshot = journal.replacedTargetSnapshot,
                      backgroundFileMatches(
                        trashedReplacementURL,
                        identity: replacedIdentity,
                        snapshot: replacedSnapshot
                      ) else {
                    return nil
                }
                try? fileManager.removeItem(at: trashedReplacementURL)
                cleanupComplete = !fileManager.fileExists(
                    atPath: trashedReplacementURL.path
                )
            }
            if let rollbackIdentity = journal.replacedRollbackIdentity,
               let replacedSnapshot = journal.replacedTargetSnapshot,
               fileManager.fileExists(atPath: replacementRollbackURL.path) {
                guard backgroundFileMatches(
                    replacementRollbackURL,
                    identity: rollbackIdentity,
                    snapshot: replacedSnapshot
                ) else {
                    return nil
                }
                try? fileManager.removeItem(at: replacementRollbackURL)
                cleanupComplete = !fileManager.fileExists(
                    atPath: replacementRollbackURL.path
                )
            }
            if cleanupComplete {
                backgroundCleanupTransaction(
                    transactionDirectory,
                    expectedIdentity: journal.transactionDirectoryIdentity
                )
            }
            return nil
        }

        let sourceIsRecoverable: Bool
        if let sourcePath = journal.sourcePath,
           let sourceIdentity = journal.sourceIdentity {
            let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
            let quarantineURL = sourceURL.deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(sourceURL.lastPathComponent).weibei-quarantine-\(journal.transactionID.uuidString.lowercased())"
                )
            sourceIsRecoverable = backgroundFileMatches(
                sourceURL,
                identity: sourceIdentity,
                snapshot: journal.sourceSnapshot
            ) || backgroundFileMatches(
                quarantineURL,
                identity: sourceIdentity,
                snapshot: journal.sourceSnapshot
            )
        } else {
            sourceIsRecoverable = false
        }
        if journal.stage == .replacementPreparing,
           let replacedIdentity = journal.replacedTargetIdentity,
           let replacedSnapshot = journal.replacedTargetSnapshot,
           backgroundFileMatches(
            targetURL,
            identity: replacedIdentity,
            snapshot: replacedSnapshot
           ) {
            if fileManager.fileExists(atPath: replacementRollbackURL.path) {
                guard backgroundIsolateAndRemoveEmptyRegularFile(
                    replacementRollbackURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "rollback-reservation-cleanup"
                    )
                ) else {
                    return nil
                }
            }
            let payloadURL = transactionDirectory.appendingPathComponent(
                "payload"
            )
            if fileManager.fileExists(atPath: payloadURL.path) {
                guard let stagedIdentity = journal.stagedIdentity,
                      backgroundRemoveVerified(
                        payloadURL,
                        quarantineURL: transactionDirectory
                            .appendingPathComponent("payload-cleanup"),
                        identity: stagedIdentity,
                        snapshot: journal.sourceSnapshot
                      ) else {
                    return nil
                }
            }
            backgroundCleanupTransaction(
                transactionDirectory,
                expectedIdentity: journal.transactionDirectoryIdentity
            )
            return nil
        }
        if targetMatches, !sourceIsRecoverable, let targetIdentity,
           let values = try? targetURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
           ]) {
            return RecoveredCourseFileTarget(
                journal: journal,
                targetURL: targetURL,
                targetIdentity: targetIdentity,
                metadata: CourseFileSourceInfo(
                    url: targetURL,
                    identity: targetIdentity,
                    byteCount: UInt64(max(0, values.fileSize ?? 0)),
                    modificationTimeNanoseconds: Int64(
                        ((values.contentModificationDate?.timeIntervalSince1970 ?? 0)
                            * 1_000_000_000).rounded()
                    )
                )
            )
        }

        let targetQuarantine = transactionDirectory.appendingPathComponent("target-quarantine")
        if targetMatches, let targetIdentity {
            guard backgroundRemoveVerified(
                targetURL,
                quarantineURL: targetQuarantine,
                identity: targetIdentity,
                snapshot: journal.sourceSnapshot
            ) else {
                return nil
            }
        } else if fileManager.fileExists(atPath: targetURL.path) {
            return nil
        }
        let replacementRestore: (url: URL, identity: ImportedFileIdentity?) = {
            if fileManager.fileExists(atPath: replacementURL.path) {
                return (replacementURL, journal.replacedTargetIdentity)
            }
            if fileManager.fileExists(atPath: replacementRollbackURL.path) {
                return (
                    replacementRollbackURL,
                    journal.replacedRollbackIdentity
                )
            }
            if fileManager.fileExists(atPath: unrecordedSelfCheckTrashURL.path) {
                return (
                    unrecordedSelfCheckTrashURL,
                    journal.replacedTargetIdentity
                )
            }
            return (
                trashedReplacementURL ?? replacementURL,
                journal.replacedTargetIdentity
            )
        }()
        if let replacedSnapshot = journal.replacedTargetSnapshot,
           let restoreIdentity = replacementRestore.identity,
           fileManager.fileExists(atPath: replacementRestore.url.path) {
            guard !fileManager.fileExists(atPath: targetURL.path),
                  backgroundFileMatches(
                    replacementRestore.url,
                    identity: restoreIdentity,
                    snapshot: replacedSnapshot
                  ),
                  CourseProjectFileWorker.renameWithoutReplacement(
                    from: replacementRestore.url,
                    to: targetURL
                  ) else {
                return nil
            }
        }
        if let rollbackIdentity = journal.replacedRollbackIdentity,
           fileManager.fileExists(atPath: replacementRollbackURL.path) {
            let removed: Bool
            switch journal.stage {
            case .replacementRollbackReserved, .replacementIsolated:
                removed = backgroundRemoveIdentityOnly(
                    replacementRollbackURL,
                    identity: rollbackIdentity
                )
            default:
                guard let replacedSnapshot = journal.replacedTargetSnapshot else {
                    return nil
                }
                removed = backgroundRemoveVerified(
                    replacementRollbackURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "rollback-cleanup"
                    ),
                    identity: rollbackIdentity,
                    snapshot: replacedSnapshot
                )
            }
            guard removed else { return nil }
        } else if journal.stage == .replacementPreparing,
                  fileManager.fileExists(
                    atPath: replacementRollbackURL.path
                  ) {
            guard backgroundIsolateAndRemoveEmptyRegularFile(
                replacementRollbackURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "rollback-reservation-cleanup"
                )
            ) else {
                return nil
            }
        }
        if let replacedIdentity = journal.replacedTargetIdentity,
           let replacedSnapshot = journal.replacedTargetSnapshot,
           fileManager.fileExists(atPath: unrecordedSelfCheckTrashURL.path) {
            guard backgroundRemoveVerified(
                unrecordedSelfCheckTrashURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "trash-cleanup"
                ),
                identity: replacedIdentity,
                snapshot: replacedSnapshot
            ) else {
                return nil
            }
        }
        if let sourcePath = journal.sourcePath,
           let sourceIdentity = journal.sourceIdentity {
            let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
            let quarantineURL = sourceURL.deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(sourceURL.lastPathComponent).weibei-quarantine-\(journal.transactionID.uuidString.lowercased())"
                )
            if fileManager.fileExists(atPath: quarantineURL.path) {
                guard !fileManager.fileExists(atPath: sourceURL.path),
                      backgroundFileMatches(
                        quarantineURL,
                        identity: sourceIdentity,
                        snapshot: journal.sourceSnapshot
                      ),
                      CourseProjectFileWorker.renameWithoutReplacement(
                        from: quarantineURL,
                        to: sourceURL
                      ) else {
                    return nil
                }
            }
        }
        let trashedReplacementIsAbsent = trashedReplacementURL.map {
            !fileManager.fileExists(atPath: $0.path)
        } ?? true
        guard !fileManager.fileExists(atPath: targetQuarantine.path),
              !fileManager.fileExists(atPath: replacementURL.path),
              !fileManager.fileExists(atPath: replacementRollbackURL.path),
              !fileManager.fileExists(atPath: unrecordedSelfCheckTrashURL.path),
              trashedReplacementIsAbsent else {
            return nil
        }
        backgroundCleanupTransaction(
            transactionDirectory,
            expectedIdentity: journal.transactionDirectoryIdentity
        )
        return nil
    }

    nonisolated private static func recoverCourseMarkdownWriteTransaction(
        at transactionDirectory: URL,
        input: CourseRecoveryInput,
        canonicalRoot: URL
    ) {
        let journalURL = transactionDirectory.appendingPathComponent(
            "course-note.json"
        )
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(
                PendingCourseMarkdownWriteJournal.self,
                from: data
              ),
              journal.courseID == input.courseID,
              journal.transactionID.uuidString.caseInsensitiveCompare(
                transactionDirectory.lastPathComponent
              ) == .orderedSame,
              CourseProjectFileWorker.identity(at: transactionDirectory)
                == journal.transactionDirectoryIdentity,
              let targetURL = backgroundRawRelativeURL(
                journal.targetRelativePath,
                inside: canonicalRoot
              ),
              CourseProjectPathPolicy.isSame(
                targetURL,
                backgroundCanonicalRawPath(
                    URL(fileURLWithPath: journal.targetPath)
                )
              ) else {
            return
        }
        let components = journal.targetRelativePath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard components.count == 2,
              components.first
                == Substring(CourseOwnedFileRole.note.directoryName) else {
            return
        }
        let payloadURL = transactionDirectory.appendingPathComponent("payload")
        let originalURL = transactionDirectory.appendingPathComponent("original")
        let stagedIdentity = journal.stagedIdentity
        let targetMatchesReplacement = stagedIdentity.map {
            backgroundFileMatches(
                targetURL,
                identity: $0,
                snapshot: journal.replacementSnapshot
            )
        } ?? false
        let payloadMatchesReplacement = stagedIdentity.map {
            backgroundFileMatches(
                payloadURL,
                identity: $0,
                snapshot: journal.replacementSnapshot
            )
        } ?? false
        let originalMatches = backgroundFileMatches(
            originalURL,
            identity: journal.targetIdentity,
            snapshot: journal.targetSnapshot
        )
        let itemCommitted = input.importedItems.contains { item in
            guard item.id == journal.itemID,
                  item.importedFileIdentity == stagedIdentity,
                  item.contentDigest == journal.replacementSnapshot.sha256 else {
                return false
            }
            if case .courseOwned(let ownerCourseID) = item.storage {
                return ownerCourseID == journal.courseID
            }
            return false
        }
        let membershipCommitted = input.memberships.contains {
            $0.courseID == journal.courseID
                && $0.itemID == journal.itemID
                && $0.courseRelativePath == journal.targetRelativePath
                && $0.entryIdentity == stagedIdentity
        }
        let workspaceCommitted =
            itemCommitted && membershipCommitted && targetMatchesReplacement

        if workspaceCommitted {
            if CourseProjectFileWorker.identity(at: originalURL) != nil {
                guard originalMatches,
                      backgroundRemoveVerified(
                        originalURL,
                        quarantineURL: transactionDirectory
                            .appendingPathComponent("original-cleanup"),
                        identity: journal.targetIdentity,
                        snapshot: journal.targetSnapshot
                      ) else {
                    return
                }
            }
            if CourseProjectFileWorker.identity(at: payloadURL) != nil {
                guard payloadMatchesReplacement,
                      let stagedIdentity,
                      backgroundRemoveVerified(
                        payloadURL,
                        quarantineURL: transactionDirectory
                            .appendingPathComponent("payload-cleanup"),
                        identity: stagedIdentity,
                        snapshot: journal.replacementSnapshot
                      ) else {
                    return
                }
            }
            backgroundCleanupCourseMarkdownTransaction(
                transactionDirectory,
                expectedIdentity: journal.transactionDirectoryIdentity
            )
            return
        }

        if CourseProjectFileWorker.identity(at: targetURL) != nil {
            guard targetMatchesReplacement,
                  let stagedIdentity,
                  backgroundRemoveVerified(
                    targetURL,
                    quarantineURL: transactionDirectory
                        .appendingPathComponent("replacement-cleanup"),
                    identity: stagedIdentity,
                    snapshot: journal.replacementSnapshot
                  ) else {
                return
            }
        }
        if CourseProjectFileWorker.identity(at: payloadURL) != nil {
            guard payloadMatchesReplacement,
                  let stagedIdentity,
                  backgroundRemoveVerified(
                    payloadURL,
                    quarantineURL: transactionDirectory
                        .appendingPathComponent("payload-cleanup"),
                    identity: stagedIdentity,
                    snapshot: journal.replacementSnapshot
                  ) else {
                return
            }
        }
        if CourseProjectFileWorker.identity(at: originalURL) != nil {
            guard originalMatches,
                  CourseProjectFileWorker.identity(at: targetURL) == nil,
                  CourseProjectFileWorker.renameWithoutReplacement(
                    from: originalURL,
                    to: targetURL
                  ) else {
                return
            }
        }
        guard backgroundFileMatches(
            targetURL,
            identity: journal.targetIdentity,
            snapshot: journal.targetSnapshot
        ) else {
            return
        }
        backgroundCleanupCourseMarkdownTransaction(
            transactionDirectory,
            expectedIdentity: journal.transactionDirectoryIdentity
        )
    }

    nonisolated private static func recoverSharedLinkRemovalTransaction(
        at transactionDirectory: URL,
        input: CourseRecoveryInput,
        canonicalRoot: URL
    ) {
        let journalURL = transactionDirectory.appendingPathComponent(
            "shared-link-removal.json"
        )
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(
                PendingSharedLinkRemovalJournal.self,
                from: data
              ),
              journal.courseID == input.courseID,
              journal.transactionID.uuidString.caseInsensitiveCompare(
                transactionDirectory.lastPathComponent
              ) == .orderedSame,
              CourseProjectFileWorker.identity(at: transactionDirectory)
                == journal.transactionDirectoryIdentity,
              let libraryRoot = input.libraryRoot,
              let sharedURL = CourseProjectPathPolicy.resolvedRelativePath(
                journal.sharedRelativePath,
                inside: libraryRoot
              ),
              isKnownCommonRelativePath(
                journal.sharedRelativePath,
                fileName: sharedURL.lastPathComponent
              ),
              CourseProjectPathPolicy.isSame(
                sharedURL,
                URL(fileURLWithPath: journal.sharedPath).resolvingSymlinksInPath()
              ),
              backgroundFileMatches(
                sharedURL,
                identity: journal.sharedIdentity,
                snapshot: journal.sharedSnapshot
              ),
              let linkURL = backgroundRawRelativeURL(
                journal.linkRelativePath,
                inside: canonicalRoot
              ),
              CourseProjectPathPolicy.isSame(
                linkURL,
                backgroundCanonicalRawPath(URL(fileURLWithPath: journal.linkPath))
              ) else {
            return
        }
        let membershipStillCommitted = input.memberships.contains {
            // The persisted membership decides whether removal committed.
            // The isolated link's inode is validated separately below.
            $0.courseID == journal.courseID
                && $0.itemID == journal.itemID
                && $0.courseRelativePath == journal.linkRelativePath
        }
        let isolatedLinkURL = transactionDirectory.appendingPathComponent(
            "isolated-link"
        )
        let linkExists = CourseProjectFileWorker.identity(at: linkURL) != nil
        let linkMatches = backgroundLinkMatches(
            linkURL,
            destination: sharedURL,
            identity: journal.linkIdentity
        )
        let isolatedLinkExists =
            CourseProjectFileWorker.identity(at: isolatedLinkURL) != nil
        let isolatedLinkMatches = backgroundLinkMatches(
            isolatedLinkURL,
            destination: sharedURL,
            identity: journal.linkIdentity
        )
        if membershipStillCommitted {
            if !linkExists, isolatedLinkMatches {
                guard CourseProjectFileWorker.renameWithoutReplacement(
                    from: isolatedLinkURL,
                    to: linkURL
                ) else {
                    return
                }
            } else {
                guard linkMatches, !isolatedLinkExists else { return }
            }
            backgroundCleanupSharedTransaction(
                transactionDirectory,
                expectedIdentity: journal.transactionDirectoryIdentity
            )
            return
        }
        if isolatedLinkExists {
            guard isolatedLinkMatches,
                  backgroundIsolateAndRemoveMatchingLink(
                    isolatedLinkURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "isolated-link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: journal.linkIdentity
                  ) else {
                return
            }
        }
        if linkExists {
            guard linkMatches,
                  backgroundIsolateAndRemoveMatchingLink(
                    linkURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: journal.linkIdentity
                  ) else {
                return
            }
        }
        backgroundCleanupSharedTransaction(
            transactionDirectory,
            expectedIdentity: journal.transactionDirectoryIdentity
        )
    }

    nonisolated private static func recoverSharedLinkCourseTransaction(
        at transactionDirectory: URL,
        input: CourseRecoveryInput,
        canonicalRoot: URL
    ) {
        let journalURL = transactionDirectory.appendingPathComponent(
            "shared-link.json"
        )
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(
                PendingSharedLinkTransactionJournal.self,
                from: data
              ),
              let libraryRoot = input.libraryRoot,
              let sharedURL = CourseProjectPathPolicy.resolvedRelativePath(
                journal.sharedRelativePath,
                inside: libraryRoot
              ),
              let linkURL = backgroundRawRelativeURL(
                journal.linkRelativePath,
                inside: canonicalRoot
              ) else {
            return
        }
        let checks = [
            journal.courseID == input.courseID,
            journal.transactionID.uuidString.caseInsensitiveCompare(
                transactionDirectory.lastPathComponent
            ) == .orderedSame,
            CourseProjectFileWorker.identity(at: transactionDirectory)
                == journal.transactionDirectoryIdentity,
            CourseProjectPathPolicy.isSame(
                sharedURL,
                URL(fileURLWithPath: journal.sharedPath)
                    .resolvingSymlinksInPath()
            ),
            isKnownCommonRelativePath(
                journal.sharedRelativePath,
                fileName: sharedURL.lastPathComponent
            ),
            CourseProjectPathPolicy.isSame(
                linkURL,
                backgroundCanonicalRawPath(
                    URL(fileURLWithPath: journal.linkPath)
                )
            ),
        ]
        guard checks.allSatisfy({ $0 }) else { return }
        let sharedMatches = backgroundFileMatches(
            sharedURL,
            identity: journal.sharedIdentity,
            snapshot: journal.sharedSnapshot
        )
        let preparedLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-link"
        )
        let committedItem = input.importedItems.first {
            guard $0.id == journal.itemID,
                  $0.importedFileIdentity == journal.sharedIdentity else {
                return false
            }
            if case .shared(let relativePath) = $0.storage {
                return relativePath == journal.sharedRelativePath
            }
            return false
        }
        let committedMembership = input.memberships.first {
            $0.courseID == journal.courseID
                && $0.itemID == journal.itemID
                && $0.courseRelativePath == journal.linkRelativePath
        }
        let expectedLinkIdentity = journal.linkIdentity
            ?? committedMembership?.entryIdentity
        let linkMatches = expectedLinkIdentity.map {
            backgroundLinkMatches(
                linkURL,
                destination: sharedURL,
                identity: $0
            )
        } ?? false
        if committedItem != nil,
           committedMembership?.entryIdentity == expectedLinkIdentity,
           sharedMatches,
           linkMatches {
            backgroundCleanupSharedTransaction(
                transactionDirectory,
                expectedIdentity: journal.transactionDirectoryIdentity
            )
            return
        }

        guard committedMembership == nil else {
            return
        }
        if linkMatches {
            guard let expectedLinkIdentity,
                  backgroundIsolateAndRemoveMatchingLink(
                    linkURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: expectedLinkIdentity
                  ) else {
                return
            }
        } else if CourseProjectFileWorker.identity(at: linkURL) != nil {
            return
        }
        if CourseProjectFileWorker.identity(at: preparedLinkURL) != nil {
            let removed = expectedLinkIdentity.map {
                backgroundIsolateAndRemoveMatchingLink(
                    preparedLinkURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "prepared-link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: $0
                )
            } ?? backgroundIsolateAndRemoveUnrecordedPreparedLink(
                preparedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-link-cleanup"
                ),
                destination: sharedURL
            )
            guard removed else {
                return
            }
        }
        backgroundCleanupSharedTransaction(
            transactionDirectory,
            expectedIdentity: journal.transactionDirectoryIdentity
        )
    }

    nonisolated private static func recoverSharedCourseTransaction(
        at transactionDirectory: URL,
        input: CourseRecoveryInput,
        canonicalRoot: URL
    ) {
        let fileManager = FileManager.default
        let journalURL = transactionDirectory.appendingPathComponent("shared.json")
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(
                PendingSharedFileTransactionJournal.self,
                from: data
              ),
              journal.ownerCourseID == input.courseID,
              journal.transactionID.uuidString.caseInsensitiveCompare(
                transactionDirectory.lastPathComponent
              ) == .orderedSame,
              CourseProjectFileWorker.identity(at: transactionDirectory)
                == journal.transactionDirectoryIdentity,
              let libraryRoot = input.libraryRoot,
              let addedRoot = input.courseRootsByID[journal.addedCourseID],
              let expectedSource = backgroundRawRelativeURL(
                journal.sourceRelativePath,
                inside: canonicalRoot
              ),
              CourseProjectPathPolicy.isSame(
                expectedSource,
                backgroundCanonicalRawPath(
                    URL(fileURLWithPath: journal.sourcePath)
                )
              ),
              let expectedAddedLink = backgroundRawRelativeURL(
                journal.addedLinkRelativePath,
                inside: addedRoot
              ),
              CourseProjectPathPolicy.isSame(
                expectedAddedLink,
                backgroundCanonicalRawPath(
                    URL(fileURLWithPath: journal.addedLinkPath)
                )
              ),
              let expectedShared = CourseProjectPathPolicy.resolvedRelativePath(
                journal.sharedRelativePath,
                inside: libraryRoot
              ),
              CourseProjectPathPolicy.isSame(
                expectedShared,
                URL(fileURLWithPath: journal.sharedPath)
                    .resolvingSymlinksInPath()
              ),
              isKnownCommonRelativePath(
                journal.sharedRelativePath,
                fileName: expectedShared.lastPathComponent
              ) else {
            return
        }
        let sourceURL = expectedSource
        let addedLinkURL = expectedAddedLink
        let sharedURL = expectedShared
        let expectedSharedPayloadURL = sharedURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(sharedURL.lastPathComponent).weibei-share-stage-\(journal.transactionID.uuidString.lowercased())"
            )
        let sharedPayloadURL: URL
        if let sharedPayloadPath = journal.sharedPayloadPath {
            guard CourseProjectPathPolicy.isSame(
                expectedSharedPayloadURL,
                backgroundCanonicalRawPath(
                    URL(fileURLWithPath: sharedPayloadPath)
                )
            ) else {
                return
            }
            sharedPayloadURL = expectedSharedPayloadURL
        } else {
            sharedPayloadURL = transactionDirectory.appendingPathComponent(
                "payload"
            )
        }
        let sourceQuarantineURL = backgroundCanonicalRawPath(
            URL(fileURLWithPath: journal.sourceQuarantinePath)
        )
        let preparedOwnerLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-owner-link"
        )
        let preparedAddedLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-added-link"
        )
        let sharedMatches = journal.sharedIdentity.map {
            backgroundFileMatches(
                sharedURL,
                identity: $0,
                snapshot: journal.sourceSnapshot
            )
        } ?? false
        let ownerLinkMatches = journal.ownerLinkIdentity.map {
            backgroundLinkMatches(
                sourceURL,
                destination: sharedURL,
                identity: $0
            )
        } ?? false
        let addedLinkMatches = journal.addedLinkIdentity.map {
            backgroundLinkMatches(
                addedLinkURL,
                destination: sharedURL,
                identity: $0
            )
        } ?? false
        let itemCommitted = input.importedItems.contains {
            guard $0.id == journal.itemID,
                  $0.importedFileIdentity == journal.sharedIdentity,
                  $0.contentDigest == journal.sourceSnapshot.sha256 else {
                return false
            }
            if case .shared(let relativePath) = $0.storage {
                return relativePath == journal.sharedRelativePath
            }
            return false
        }
        let ownerMembershipCommitted = input.memberships.contains {
            // The membership is durable commit evidence. Its physical link
            // identity may legitimately disappear after the workspace save.
            $0.courseID == journal.ownerCourseID
                && $0.itemID == journal.itemID
                && $0.courseRelativePath == journal.sourceRelativePath
        }
        let addedMembershipCommitted = input.memberships.contains {
            $0.courseID == journal.addedCourseID
                && $0.itemID == journal.itemID
                && $0.courseRelativePath == journal.addedLinkRelativePath
        }
        if itemCommitted,
           ownerMembershipCommitted,
           addedMembershipCommitted {
            guard sharedMatches else {
                return
            }
            if CourseProjectFileWorker.identity(at: sharedPayloadURL) != nil {
                guard let sharedIdentity = journal.sharedIdentity,
                      backgroundRemoveVerified(
                        sharedPayloadURL,
                        quarantineURL: sharedPayloadURL
                            .deletingLastPathComponent()
                            .appendingPathComponent(
                                ".\(sharedPayloadURL.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                            ),
                        identity: sharedIdentity,
                        snapshot: journal.sourceSnapshot
                      ) else {
                    return
                }
            }
            if CourseProjectFileWorker.identity(at: sourceQuarantineURL) != nil {
                guard backgroundRemoveVerified(
                    sourceQuarantineURL,
                    quarantineURL: sourceQuarantineURL
                        .deletingLastPathComponent()
                        .appendingPathComponent(
                            ".\(sourceQuarantineURL.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                        ),
                    identity: journal.sourceIdentity,
                    snapshot: journal.sourceSnapshot
                ) else {
                    return
                }
            }
            backgroundCleanupSharedTransaction(
                transactionDirectory,
                expectedIdentity: journal.transactionDirectoryIdentity
            )
            return
        }

        if addedLinkMatches {
            guard let addedLinkIdentity = journal.addedLinkIdentity,
                  backgroundIsolateAndRemoveMatchingLink(
                    addedLinkURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "added-link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: addedLinkIdentity
                  ) else {
                return
            }
        } else if fileManager.fileExists(atPath: addedLinkURL.path) {
            return
        }
        if ownerLinkMatches {
            guard let ownerLinkIdentity = journal.ownerLinkIdentity,
                  backgroundIsolateAndRemoveMatchingLink(
                    sourceURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "owner-link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: ownerLinkIdentity
                  ) else {
                return
            }
        } else if fileManager.fileExists(atPath: sourceURL.path) {
            guard backgroundFileMatches(
                sourceURL,
                identity: journal.sourceIdentity,
                snapshot: journal.sourceSnapshot
            ) else {
                return
            }
        }
        if CourseProjectFileWorker.identity(at: preparedAddedLinkURL) != nil {
            let removed = journal.addedLinkIdentity.map {
                backgroundIsolateAndRemoveMatchingLink(
                    preparedAddedLinkURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "prepared-added-link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: $0
                )
            } ?? backgroundIsolateAndRemoveUnrecordedPreparedLink(
                preparedAddedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-added-link-cleanup"
                ),
                destination: sharedURL
            )
            guard removed else {
                return
            }
        }
        if CourseProjectFileWorker.identity(at: preparedOwnerLinkURL) != nil {
            let removed = journal.ownerLinkIdentity.map {
                backgroundIsolateAndRemoveMatchingLink(
                    preparedOwnerLinkURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "prepared-owner-link-cleanup"
                    ),
                    destination: sharedURL,
                    identity: $0
                )
            } ?? backgroundIsolateAndRemoveUnrecordedPreparedLink(
                preparedOwnerLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-owner-link-cleanup"
                ),
                destination: sharedURL
            )
            guard removed else {
                return
            }
        }
        if sharedMatches, let sharedIdentity = journal.sharedIdentity {
            guard backgroundRemoveVerified(
                sharedURL,
                quarantineURL: sharedURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        ".\(sharedURL.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                    ),
                identity: sharedIdentity,
                snapshot: journal.sourceSnapshot
            ) else {
                return
            }
        } else if fileManager.fileExists(atPath: sharedURL.path) {
            return
        }
        if CourseProjectFileWorker.identity(at: sharedPayloadURL) != nil {
            guard let sharedIdentity = journal.sharedIdentity,
                  backgroundRemoveVerified(
                    sharedPayloadURL,
                    quarantineURL: sharedPayloadURL.deletingLastPathComponent()
                        .appendingPathComponent(
                            ".\(sharedPayloadURL.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                        ),
                    identity: sharedIdentity,
                    snapshot: journal.sourceSnapshot
                  ) else {
                return
            }
        }
        if fileManager.fileExists(atPath: sourceQuarantineURL.path) {
            guard !fileManager.fileExists(atPath: sourceURL.path),
                  backgroundFileMatches(
                    sourceQuarantineURL,
                    identity: journal.sourceIdentity,
                    snapshot: journal.sourceSnapshot
                  ),
                  CourseProjectFileWorker.renameWithoutReplacement(
                    from: sourceQuarantineURL,
                    to: sourceURL
                  ) else {
                return
            }
        }
        backgroundCleanupSharedTransaction(
            transactionDirectory,
            expectedIdentity: journal.transactionDirectoryIdentity
        )
    }

    nonisolated private static func backgroundLinkMatches(
        _ linkURL: URL,
        destination: URL,
        identity: ImportedFileIdentity
    ) -> Bool {
        CourseProjectFileWorker.isSymbolicLink(at: linkURL)
            && CourseProjectFileWorker.identity(at: linkURL) == identity
            && CourseProjectPathPolicy.isSame(
                linkURL.resolvingSymlinksInPath(),
                destination.resolvingSymlinksInPath()
            )
    }

    nonisolated private static func isKnownCommonRelativePath(
        _ relativePath: String,
        fileName: String
    ) -> Bool {
        let components = relativePath.split(separator: "/")
        return components.count == 2
            && ["通用资料", "通用笔记", "共享文稿"]
                .contains(String(components[0]))
            && components[1] == Substring(fileName)
    }

    nonisolated private static func backgroundIsolateAndRemoveMatchingLink(
        _ linkURL: URL,
        quarantineURL: URL,
        destination: URL,
        identity: ImportedFileIdentity
    ) -> Bool {
        guard CourseProjectFileWorker.identity(at: quarantineURL) == nil,
              CourseProjectFileWorker.renameWithoutReplacement(
                from: linkURL,
                to: quarantineURL
              ) else {
            return false
        }
        guard backgroundLinkMatches(
            quarantineURL,
            destination: destination,
            identity: identity
        ) else {
            _ = CourseProjectFileWorker.renameWithoutReplacement(
                from: quarantineURL,
                to: linkURL
            )
            return false
        }
        try? FileManager.default.removeItem(at: quarantineURL)
        return CourseProjectFileWorker.identity(at: quarantineURL) == nil
    }

    nonisolated private static func backgroundIsolateAndRemoveUnrecordedPreparedLink(
        _ linkURL: URL,
        quarantineURL: URL,
        destination: URL
    ) -> Bool {
        guard CourseProjectFileWorker.isSymbolicLink(at: linkURL),
              CourseProjectFileWorker.symbolicLink(
                at: linkURL,
                pointsTo: destination
              ),
              let identity = CourseProjectFileWorker.identity(at: linkURL) else {
            return false
        }
        return backgroundIsolateAndRemoveMatchingLink(
            linkURL,
            quarantineURL: quarantineURL,
            destination: destination,
            identity: identity
        )
    }

    nonisolated private static func backgroundIsolateAndRemoveEmptyRegularFile(
        _ url: URL,
        quarantineURL: URL
    ) -> Bool {
        guard CourseProjectFileWorker.identity(at: quarantineURL) == nil,
              CourseProjectFileWorker.renameWithoutReplacement(
                from: url,
                to: quarantineURL
              ) else {
            return false
        }
        let validReservation = !CourseProjectFileWorker.isSymbolicLink(
            at: quarantineURL
        )
            && ((try? CourseProjectFileWorker.snapshotFile(
                at: quarantineURL
            ))?.byteCount == 0)
        guard validReservation else {
            _ = CourseProjectFileWorker.renameWithoutReplacement(
                from: quarantineURL,
                to: url
            )
            return false
        }
        try? FileManager.default.removeItem(at: quarantineURL)
        return CourseProjectFileWorker.identity(at: quarantineURL) == nil
    }

    nonisolated private static func backgroundRawRelativeURL(
        _ relativePath: String,
        inside root: URL
    ) -> URL? {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.first != ".weibei",
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        let candidate = components.reduce(root) {
            $0.appendingPathComponent($1, isDirectory: false)
        }.standardizedFileURL
        guard CourseProjectPathPolicy.contains(root, candidate, includingRoot: false) else {
            return nil
        }
        return candidate
    }

    nonisolated private static func backgroundCanonicalRawPath(_ url: URL) -> URL {
        url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent, isDirectory: false)
            .standardizedFileURL
    }

    nonisolated private static func backgroundCleanupSharedTransaction(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) {
        let fileManager = FileManager.default
        guard CourseProjectFileWorker.identity(at: transactionDirectory) == expectedIdentity,
              let entries = try? fileManager.contentsOfDirectory(
                at: transactionDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ],
                options: []
              ),
              entries.allSatisfy({
                [
                    "shared.json",
                    "shared-link.json",
                    "shared-link-removal.json",
                    "payload",
                ]
                    .contains($0.lastPathComponent)
              }) else {
            return
        }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.isAliasFile != true else {
                return
            }
        }
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
        if (try? fileManager.contentsOfDirectory(
            atPath: transactionDirectory.path
        ).isEmpty) == true {
            try? fileManager.removeItem(at: transactionDirectory)
        }
    }

    nonisolated private static func backgroundTargetURL(
        journal: PendingCourseFileTransactionJournal,
        root: URL
    ) -> URL? {
        let components = journal.targetRelativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.first != ".weibei",
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        let target = components.reduce(root) { $0.appendingPathComponent($1) }
        let parent = target.deletingLastPathComponent()
        guard let canonicalParent = try? CourseProjectPathPolicy.existingDirectory(parent),
              CourseProjectPathPolicy.isSame(parent, canonicalParent),
              CourseProjectPathPolicy.contains(root, canonicalParent, includingRoot: false),
              CourseProjectFileWorker.identity(at: canonicalParent)
                == journal.destinationDirectoryIdentity else {
            return nil
        }
        return target.standardizedFileURL
    }

    nonisolated private static func backgroundFileMatches(
        _ url: URL,
        identity: ImportedFileIdentity,
        snapshot: CourseFileSnapshot
    ) -> Bool {
        CourseProjectPathPolicy.isSame(url, url.resolvingSymlinksInPath())
            && CourseProjectFileWorker.identity(at: url) == identity
            && (try? CourseProjectFileWorker.snapshotFile(at: url)) == snapshot
            && CourseProjectFileWorker.identity(at: url) == identity
    }

    nonisolated private static func backgroundRemoveVerified(
        _ originalURL: URL,
        quarantineURL: URL,
        identity: ImportedFileIdentity,
        snapshot: CourseFileSnapshot
    ) -> Bool {
        let fileManager = FileManager.default
        guard backgroundFileMatches(originalURL, identity: identity, snapshot: snapshot),
              !fileManager.fileExists(atPath: quarantineURL.path),
              CourseProjectFileWorker.renameWithoutReplacement(
                from: originalURL,
                to: quarantineURL
              ) else {
            return false
        }
        guard backgroundFileMatches(
            quarantineURL,
            identity: identity,
            snapshot: snapshot
        ) else {
            _ = CourseProjectFileWorker.renameWithoutReplacement(
                from: quarantineURL,
                to: originalURL
            )
            return false
        }
        do {
            try fileManager.removeItem(at: quarantineURL)
            return !fileManager.fileExists(atPath: quarantineURL.path)
        } catch {
            _ = CourseProjectFileWorker.renameWithoutReplacement(
                from: quarantineURL,
                to: originalURL
            )
            return false
        }
    }

    nonisolated private static func backgroundRemoveIdentityOnly(
        _ url: URL,
        identity: ImportedFileIdentity
    ) -> Bool {
        let fileManager = FileManager.default
        guard CourseProjectFileWorker.identity(at: url) == identity,
              !CourseProjectFileWorker.isSymbolicLink(at: url),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            return false
        }
        do {
            try fileManager.removeItem(at: url)
            return CourseProjectFileWorker.identity(at: url) == nil
        } catch {
            return false
        }
    }

    nonisolated private static func backgroundCleanupTransaction(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) {
        let fileManager = FileManager.default
        guard CourseProjectFileWorker.identity(at: transactionDirectory) == expectedIdentity,
              let entries = try? fileManager.contentsOfDirectory(
                at: transactionDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ],
                options: []
              ),
              entries.allSatisfy({
                ["journal.json", "payload"].contains($0.lastPathComponent)
              }) else {
            return
        }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.isAliasFile != true else {
                return
            }
        }
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
        if (try? fileManager.contentsOfDirectory(
            atPath: transactionDirectory.path
        ).isEmpty) == true {
            try? fileManager.removeItem(at: transactionDirectory)
        }
    }

    nonisolated private static func backgroundCleanupCourseMarkdownTransaction(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) {
        let fileManager = FileManager.default
        guard CourseProjectFileWorker.identity(at: transactionDirectory)
                == expectedIdentity,
              let entries = try? fileManager.contentsOfDirectory(
                at: transactionDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ],
                options: []
              ),
              entries.allSatisfy({
                ["course-note.json", "payload"]
                    .contains($0.lastPathComponent)
              }) else {
            return
        }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.isAliasFile != true else {
                return
            }
        }
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
        if (try? fileManager.contentsOfDirectory(
            atPath: transactionDirectory.path
        ).isEmpty) == true {
            try? fileManager.removeItem(at: transactionDirectory)
        }
    }

    private func recoverPendingCourseFileTransactions() {
        for course in courses {
            guard let root = courseRootURL(for: course.id),
                  let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(root),
                  let metadata = try? realCourseOwnedDirectory(
                    canonicalRoot.appendingPathComponent(".weibei", isDirectory: true),
                    inside: canonicalRoot,
                    createIfMissing: false
                  ),
                  let transactions = try? realCourseOwnedDirectory(
                    metadata.appendingPathComponent("transactions", isDirectory: true),
                    inside: metadata,
                    createIfMissing: false
                  ),
                  let transactionDirectories = try? FileManager.default.contentsOfDirectory(
                    at: transactions,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }
            for rawTransactionDirectory in transactionDirectories {
                guard UUID(uuidString: rawTransactionDirectory.lastPathComponent) != nil,
                      let transactionDirectory = try? realCourseOwnedDirectory(
                        rawTransactionDirectory,
                        inside: transactions,
                        createIfMissing: false
                      ) else {
                    continue
                }
                recoverPendingCourseFileTransaction(
                    at: transactionDirectory,
                    courseID: course.id,
                    root: canonicalRoot
                )
            }
        }
    }

    private func recoverPendingCourseFileTransaction(
        at transactionDirectory: URL,
        courseID: UUID,
        root: URL
    ) {
        if FileManager.default.fileExists(
            atPath: transactionDirectory.appendingPathComponent(
                "course-note.json"
            ).path
        ) {
            let courseRootsByID = Dictionary(
                uniqueKeysWithValues: courses.compactMap { course in
                    courseRootURL(for: course.id).map {
                        (course.id, $0)
                    }
                }
            )
            Self.recoverCourseMarkdownWriteTransaction(
                at: transactionDirectory,
                input: CourseRecoveryInput(
                    courseID: courseID,
                    root: root,
                    libraryRoot: courseLibraryRootURL,
                    courseRootsByID: courseRootsByID,
                    importedItems: importedItems,
                    memberships: courseItemMemberships
                ),
                canonicalRoot: root
            )
            return
        }
        let journalURL = transactionDirectory.appendingPathComponent("journal.json")
        guard let data = try? Data(contentsOf: journalURL),
              var journal = try? JSONDecoder().decode(
                PendingCourseFileTransactionJournal.self,
                from: data
              ),
              journal.transactionID.uuidString.caseInsensitiveCompare(
                transactionDirectory.lastPathComponent
              ) == .orderedSame,
              journal.courseID == courseID,
              importedFileIdentityResolver(transactionDirectory) == journal.transactionDirectoryIdentity,
              let destinationDirectory = try? realCourseOwnedDirectory(
                root.appendingPathComponent(journal.role.directoryName, isDirectory: true),
                inside: root,
                createIfMissing: false
              ) else {
            return
        }
        let targetComponents = journal.targetRelativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard targetComponents.count == 2,
              targetComponents.first == journal.role.directoryName,
              importedFileIdentityResolver(destinationDirectory) == journal.destinationDirectoryIdentity else {
            return
        }
        let targetURL = destinationDirectory
            .appendingPathComponent(targetComponents[1], isDirectory: false)
            .standardizedFileURL
        let targetQuarantineURL = transactionDirectory
            .appendingPathComponent("target-quarantine", isDirectory: false)

        let expectedTargetIdentity = journal.targetIdentity ?? journal.stagedIdentity
        func targetMatchesExpectedFile() -> Bool {
            guard let expectedTargetIdentity else { return false }
            return CourseProjectPathPolicy.isSame(
                targetURL,
                targetURL.resolvingSymlinksInPath()
            )
                && importedFileIdentityResolver(targetURL) == expectedTargetIdentity
                && (try? courseFileSnapshot(at: targetURL)) == journal.sourceSnapshot
        }
        var targetMatches = targetMatchesExpectedFile()
        let item = importedItems.first { item in
            guard item.id == journal.itemID,
                  item.contentDigest == journal.sourceSnapshot.sha256,
                  item.importedFileIdentity == expectedTargetIdentity,
                  item.isNotebookNote == (journal.role == .note) else {
                return false
            }
            if case .courseOwned(let ownerCourseID) = item.storage {
                return ownerCourseID == courseID
            }
            return false
        }
        let membership = courseItemMemberships.first {
            $0.courseID == courseID
                && $0.itemID == journal.itemID
                && $0.courseRelativePath == journal.targetRelativePath
                && $0.entryIdentity == expectedTargetIdentity
        }
        let workspaceCommitted = item != nil && membership != nil && targetMatches

        if workspaceCommitted {
            var cleanupPending = false
            if let sourcePath = journal.sourcePath,
               let sourceIdentity = journal.sourceIdentity {
                let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
                let expectedSourceQuarantineURL = sourceURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        ".\(sourceURL.lastPathComponent).weibei-quarantine-\(journal.transactionID.uuidString.lowercased())",
                        isDirectory: false
                    )
                if let recordedPath = journal.sourceQuarantinePath,
                   !CourseProjectPathPolicy.isSame(
                    URL(fileURLWithPath: recordedPath),
                    expectedSourceQuarantineURL
                   ) {
                    cleanupPending = true
                } else {
                    journal.sourceQuarantinePath = expectedSourceQuarantineURL.path
                    try? writeCourseFileTransactionJournal(journal, to: journalURL)
                }
                let sourceExists = FileManager.default.fileExists(atPath: sourceURL.path)
                let quarantineExists = FileManager.default.fileExists(
                    atPath: expectedSourceQuarantineURL.path
                )
                if sourceExists && quarantineExists {
                    cleanupPending = true
                } else if !cleanupPending, quarantineExists {
                    do {
                        _ = try stableCourseFileSnapshot(
                            at: expectedSourceQuarantineURL,
                            expectedIdentity: sourceIdentity,
                            expectedSnapshot: journal.sourceSnapshot
                        )
                        guard atomicRenameWithoutReplacement(
                            from: expectedSourceQuarantineURL,
                            to: sourceURL
                        ) else {
                            throw CourseOwnedFileError.sourceIdentityChanged
                        }
                    } catch {
                        cleanupPending = true
                    }
                }
                if !cleanupPending,
                   FileManager.default.fileExists(atPath: sourceURL.path) {
                    do {
                        _ = try validatedCourseImportSource(sourceURL)
                        _ = try stableCourseFileSnapshot(
                            at: sourceURL,
                            expectedIdentity: sourceIdentity,
                            expectedSnapshot: journal.sourceSnapshot
                        )
                        let removalOutcome = atomicallyIsolateAndRemoveCourseFile(
                            at: sourceURL,
                            quarantineURL: expectedSourceQuarantineURL,
                            expectedIdentity: sourceIdentity,
                            expectedSnapshot: journal.sourceSnapshot,
                            remover: courseFileSourceRemover
                        )
                        guard case .removed = removalOutcome else {
                            throw CourseOwnedFileError.sourceIdentityChanged
                        }
                    } catch {
                        cleanupPending = true
                    }
                }
            } else if journal.sourcePath != nil
                        || journal.sourceIdentity != nil
                        || journal.sourceQuarantinePath != nil {
                cleanupPending = true
            }
            if !cleanupPending {
                safelyRemoveCourseFileTransactionDirectory(
                    transactionDirectory,
                    expectedIdentity: journal.transactionDirectoryIdentity
                )
            }
            return
        }

        guard let sourcePath = journal.sourcePath,
              let sourceIdentity = journal.sourceIdentity else {
            return
        }
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let expectedSourceQuarantineURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(sourceURL.lastPathComponent).weibei-quarantine-\(journal.transactionID.uuidString.lowercased())",
                isDirectory: false
            )
        guard journal.sourceQuarantinePath.map({
            CourseProjectPathPolicy.isSame(
                URL(fileURLWithPath: $0),
                expectedSourceQuarantineURL
            )
        }) ?? true else {
            return
        }
        journal.sourceQuarantinePath = expectedSourceQuarantineURL.path
        try? writeCourseFileTransactionJournal(journal, to: journalURL)

        let sourceExists = FileManager.default.fileExists(atPath: sourceURL.path)
        let sourceQuarantineExists = FileManager.default.fileExists(
            atPath: expectedSourceQuarantineURL.path
        )
        if sourceExists && sourceQuarantineExists {
            return
        }
        if sourceQuarantineExists {
            guard !sourceExists,
                  (try? validatedCourseImportSource(expectedSourceQuarantineURL)) != nil,
                  (try? stableCourseFileSnapshot(
                    at: expectedSourceQuarantineURL,
                    expectedIdentity: sourceIdentity,
                    expectedSnapshot: journal.sourceSnapshot
                  )) != nil,
                  case .restored = restoreIsolatedCourseFile(
                    from: expectedSourceQuarantineURL,
                    to: sourceURL
                  ) else {
                return
            }
        }
        guard (try? validatedCourseImportSource(sourceURL)) != nil,
              atomicallyIsolateVerifiedCourseFile(
                at: sourceURL,
                quarantineURL: expectedSourceQuarantineURL,
                expectedIdentity: sourceIdentity,
                expectedSnapshot: journal.sourceSnapshot
              ) else {
            return
        }

        if FileManager.default.fileExists(atPath: targetQuarantineURL.path) {
            guard !FileManager.default.fileExists(atPath: targetURL.path),
                  let expectedTargetIdentity,
                  (try? stableCourseFileSnapshot(
                    at: targetQuarantineURL,
                    expectedIdentity: expectedTargetIdentity,
                    expectedSnapshot: journal.sourceSnapshot
                  )) != nil,
                  atomicRenameWithoutReplacement(
                    from: targetQuarantineURL,
                    to: targetURL
                  ) else {
                _ = restoreIsolatedCourseFile(
                    from: expectedSourceQuarantineURL,
                    to: sourceURL
                )
                return
            }
            targetMatches = targetMatchesExpectedFile()
        }
        if targetMatches, let expectedTargetIdentity {
            let removalOutcome = atomicallyIsolateAndRemoveCourseFile(
                at: targetURL,
                quarantineURL: targetQuarantineURL,
                expectedIdentity: expectedTargetIdentity,
                expectedSnapshot: journal.sourceSnapshot,
                remover: { try FileManager.default.removeItem(at: $0) }
            )
            guard case .removed = removalOutcome else {
                _ = restoreIsolatedCourseFile(
                    from: expectedSourceQuarantineURL,
                    to: sourceURL
                )
                return
            }
        } else if FileManager.default.fileExists(atPath: targetURL.path) {
            _ = restoreIsolatedCourseFile(
                from: expectedSourceQuarantineURL,
                to: sourceURL
            )
            return
        }
        guard !FileManager.default.fileExists(atPath: targetURL.path),
              !FileManager.default.fileExists(atPath: targetQuarantineURL.path) else {
            _ = restoreIsolatedCourseFile(
                from: expectedSourceQuarantineURL,
                to: sourceURL
            )
            return
        }
        guard case .restored = restoreIsolatedCourseFile(
            from: expectedSourceQuarantineURL,
            to: sourceURL
        ) else {
            return
        }
        safelyRemoveCourseFileTransactionDirectory(
            transactionDirectory,
            expectedIdentity: journal.transactionDirectoryIdentity
        )
    }

    private func transactionDirectoryFingerprint(
        at root: URL
    ) -> TransactionDirectoryFingerprint? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let rootValues = try? root.resourceValues(forKeys: keys),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              let rootIdentity = importedFileIdentityResolver(root) else {
            return nil
        }

        var encounteredError = false
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                encounteredError = true
                return false
            }
        ) else {
            return nil
        }
        let rootComponents = root.standardizedFileURL.pathComponents
        var entries: [String: TransactionDirectoryFingerprint.Entry] = [:]
        for case let entryURL as URL in enumerator {
            guard let values = try? entryURL.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  let identity = importedFileIdentityResolver(entryURL) else {
                return nil
            }
            let entryComponents = entryURL.standardizedFileURL.pathComponents
            guard entryComponents.count > rootComponents.count,
                  Array(entryComponents.prefix(rootComponents.count)) == rootComponents else {
                return nil
            }
            let relativePath = entryComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            if values.isDirectory == true {
                entries[relativePath] = .init(
                    kind: .directory,
                    identity: identity,
                    data: nil
                )
            } else if values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize <= 1_048_576,
                      let data = try? Data(contentsOf: entryURL) {
                entries[relativePath] = .init(
                    kind: .regularFile,
                    identity: identity,
                    data: data
                )
            } else {
                return nil
            }
        }
        guard !encounteredError else { return nil }
        return TransactionDirectoryFingerprint(
            rootIdentity: rootIdentity,
            entriesByRelativePath: entries
        )
    }

    private func safelyRemoveTransactionDirectory(
        at root: URL,
        expected: TransactionDirectoryFingerprint
    ) {
        guard transactionDirectoryMatches(at: root, expected: expected),
              (try? courseProjectMutationHook(.beforeOwnedRollbackCleanup)) != nil else {
            return
        }

        let regularFiles = expected.entriesByRelativePath
            .filter { $0.value.kind == .regularFile }
            .sorted { pathDepth($0.key) > pathDepth($1.key) }
        for (relativePath, expectedEntry) in regularFiles {
            let fileURL = transactionURL(
                relativePath: relativePath,
                inside: root
            )
            guard transactionEntry(at: fileURL, matches: expectedEntry),
                  unlinkPath(fileURL) else {
                return
            }
        }

        let directories = expected.entriesByRelativePath
            .filter { $0.value.kind == .directory }
            .sorted { pathDepth($0.key) > pathDepth($1.key) }
        for (relativePath, expectedEntry) in directories {
            let directoryURL = transactionURL(
                relativePath: relativePath,
                inside: root
            )
            guard transactionEntry(at: directoryURL, matches: expectedEntry),
                  removeEmptyDirectory(directoryURL) else {
                return
            }
        }

        guard importedFileIdentityResolver(root) == expected.rootIdentity else {
            return
        }
        _ = removeEmptyDirectory(root)
    }

    private func transactionDirectoryMatches(
        at root: URL,
        expected: TransactionDirectoryFingerprint
    ) -> Bool {
        guard importedFileIdentityResolver(root) == expected.rootIdentity else {
            return false
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        var encounteredError = false
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                encounteredError = true
                return false
            }
        ) else {
            return false
        }
        let rootComponents = root.standardizedFileURL.pathComponents
        var seenPaths = Set<String>()
        for case let entryURL as URL in enumerator {
            let entryComponents = entryURL.standardizedFileURL.pathComponents
            guard entryComponents.count > rootComponents.count,
                  Array(entryComponents.prefix(rootComponents.count)) == rootComponents else {
                return false
            }
            let relativePath = entryComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            guard let expectedEntry = expected.entriesByRelativePath[relativePath],
                  seenPaths.insert(relativePath).inserted,
                  transactionEntry(at: entryURL, matches: expectedEntry) else {
                return false
            }
        }
        return !encounteredError
            && seenPaths == Set(expected.entriesByRelativePath.keys)
    }

    private func transactionEntry(
        at url: URL,
        matches expected: TransactionDirectoryFingerprint.Entry
    ) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isSymbolicLink != true,
              let identity = importedFileIdentityResolver(url) else {
            return false
        }
        guard identity == expected.identity else { return false }
        switch expected.kind {
        case .directory:
            return values.isDirectory == true
                && values.isRegularFile != true
                && expected.data == nil
        case .regularFile:
            guard values.isRegularFile == true,
                  values.isDirectory != true,
                  let expectedData = expected.data,
                  expectedData.count <= 1_048_576,
                  values.fileSize == expectedData.count,
                  let currentData = try? Data(contentsOf: url) else {
                return false
            }
            return currentData == expectedData
        }
    }

    private func transactionURL(relativePath: String, inside root: URL) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(root) {
                $0.appendingPathComponent(String($1))
            }
    }

    private func pathDepth(_ relativePath: String) -> Int {
        relativePath.split(separator: "/", omittingEmptySubsequences: true).count
    }

    private func unlinkPath(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.unlink(path) == 0
        }
    }

    private func removeEmptyDirectory(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.rmdir(path) == 0
        }
    }

    private func validateLibraryRoot(_ root: URL) throws {
        let protectedRoots = [
            URL(fileURLWithPath: "/", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
        ].compactMap { $0?.resolvingSymlinksInPath().standardizedFileURL }
        if protectedRoots.contains(where: { CourseProjectPathPolicy.contains(root, $0) })
            || CourseProjectPathPolicy.overlaps(root, workspaceDirectory) {
            throw CourseProjectRootError.dangerousRoot
        }
        for course in courses {
            let candidates = registeredRootCandidates(
                for: course,
                proposedLibraryRoot: root
            )
            if candidates.contains(where: {
                CourseProjectPathPolicy.isSame($0, root)
                    || CourseProjectPathPolicy.contains($0, root, includingRoot: false)
            }) {
                throw CourseProjectRootError.overlappingRoot
            }
        }
    }

    private func registeredRootCandidates(
        for course: Course,
        proposedLibraryRoot: URL
    ) -> [URL] {
        var candidates: [URL] = []
        if let resolved = resolvedCourseRootURLs[course.id] {
            candidates.append(resolved)
        }
        if let path = course.sourceRootPath {
            candidates.append(
                URL(fileURLWithPath: path)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            )
        }
        if let bookmark = course.sourceRootBookmarkData,
           let resolution = courseRootBookmarkResolver(bookmark) {
            candidates.append(
                resolution.url
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
            )
        }
        if let relativePath = course.sourceRootRelativePath,
           let resolved = CourseProjectPathPolicy.resolvedRelativePath(
               relativePath,
               inside: proposedLibraryRoot
           ) {
            candidates.append(resolved)
        }
        return candidates
    }

    private func validateCourseProjectRoot(
        _ root: URL,
        identity: ImportedFileIdentity?,
        mustBeInsideLibrary: Bool,
        excludingCourseID: UUID? = nil
    ) throws {
        let protectedRoots = [
            URL(fileURLWithPath: "/", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
        ].compactMap { $0?.resolvingSymlinksInPath().standardizedFileURL }
        if protectedRoots.contains(where: { CourseProjectPathPolicy.contains(root, $0) })
            || CourseProjectPathPolicy.overlaps(root, workspaceDirectory) {
            throw CourseProjectRootError.dangerousRoot
        }

        if let libraryRoot = courseLibraryRootURL {
            if CourseProjectPathPolicy.isSame(root, libraryRoot)
                || CourseProjectPathPolicy.contains(root, libraryRoot, includingRoot: false) {
                throw CourseProjectRootError.dangerousRoot
            }
            for directoryName in [
                CourseOwnedFileRole.material.commonDirectoryName,
                CourseOwnedFileRole.note.commonDirectoryName,
                "共享文稿",
            ] {
                if CourseProjectPathPolicy.overlaps(
                    root,
                    libraryRoot.appendingPathComponent(
                        directoryName,
                        isDirectory: true
                    )
                ) {
                    throw CourseProjectRootError.dangerousRoot
                }
            }
            if mustBeInsideLibrary,
               !CourseProjectPathPolicy.contains(libraryRoot, root, includingRoot: false) {
                throw CourseProjectRootError.rootOutsideLibrary
            }
        } else if mustBeInsideLibrary {
            throw courseLibraryRootPath == nil
                ? CourseProjectRootError.missingLibrary
                : CourseProjectRootError.unavailableLibrary
        }

        for course in courses where course.id != excludingCourseID {
            if let identity,
               let existingIdentity = course.sourceRootIdentity,
               identity == existingIdentity {
                throw CourseProjectRootError.rootAlreadyRegistered
            }
            if let existingRoot = resolvedCourseRootURLs[course.id]
                ?? legacyCourseRootURL(for: course),
               CourseProjectPathPolicy.overlaps(root, existingRoot) {
                throw CourseProjectRootError.overlappingRoot
            }
        }
    }

    private func existingCourse(
        at root: URL,
        identity: ImportedFileIdentity
    ) -> Course? {
        courses.first { course in
            if let storedIdentity = course.sourceRootIdentity {
                return storedIdentity == identity
            }
            guard let existingRoot = resolvedCourseRootURLs[course.id]
                    ?? legacyCourseRootURL(for: course) else {
                return false
            }
            return CourseProjectPathPolicy.isSame(existingRoot, root)
        }
    }

    private func legacyCourseRootURL(for course: Course) -> URL? {
        guard let path = course.sourceRootPath else { return nil }
        return try? CourseProjectPathPolicy.existingDirectory(URL(fileURLWithPath: path))
    }

    @discardableResult
    private func restoreCourseProjectRoots() -> Bool {
        var changed = false
        courseLibraryRootURL = nil
        courseLibraryUnavailableReason = nil
        resolvedCourseRootURLs.removeAll()
        courseRootUnavailableReasons.removeAll()

        if let bookmark = courseLibraryRootBookmarkData,
           let expectedIdentity = courseLibraryRootIdentity,
           let resolution = courseRootBookmarkResolver(bookmark) {
            let scopedURL = resolution.url
            if courseSecurityScopeStarter(scopedURL) {
                if let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(scopedURL),
                   importedFileIdentityResolver(resolvedRoot) == expectedIdentity {
                    do {
                        try validateLibraryRoot(resolvedRoot)
                        activeCourseSecurityScopes["library"] = scopedURL
                        courseLibraryRootURL = resolvedRoot
                        if courseLibraryRootPath != resolvedRoot.path {
                            courseLibraryRootPath = resolvedRoot.path
                            changed = true
                        }
                        if resolution.isStale,
                           let refreshedBookmark = courseRootBookmarkMaker(resolvedRoot) {
                            courseLibraryRootBookmarkData = refreshedBookmark
                            changed = true
                        }
                    } catch {
                        courseSecurityScopeStopper(scopedURL)
                        courseLibraryUnavailableReason = error.localizedDescription
                    }
                } else {
                    courseSecurityScopeStopper(scopedURL)
                    courseLibraryUnavailableReason = CourseProjectRootError.bookmarkResolutionFailed.localizedDescription
                }
            } else {
                courseLibraryUnavailableReason = CourseProjectRootError.securityScopeDenied.localizedDescription
            }
        } else if courseLibraryRootPath != nil
                    || courseLibraryRootIdentity != nil
                    || courseLibraryRootBookmarkData != nil {
            courseLibraryUnavailableReason = CourseProjectRootError.bookmarkResolutionFailed.localizedDescription
        }

        changed = restoreCourseReferencesInsideLibrary() || changed
        for index in courses.indices where courses[index].sourceRootRelativePath == nil {
            let courseID = courses[index].id
            guard let bookmark = courses[index].sourceRootBookmarkData,
                  let expectedIdentity = courses[index].sourceRootIdentity else {
                if courses[index].sourceRootPath != nil {
                    courseRootUnavailableReasons[courseID] = "旧课程根没有可恢复的持久授权。"
                }
                continue
            }
            guard let resolution = courseRootBookmarkResolver(bookmark) else {
                courseRootUnavailableReasons[courseID] = CourseProjectRootError.bookmarkResolutionFailed.localizedDescription
                continue
            }
            let scopedURL = resolution.url
            guard courseSecurityScopeStarter(scopedURL) else {
                courseRootUnavailableReasons[courseID] = CourseProjectRootError.securityScopeDenied.localizedDescription
                continue
            }
            guard let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(scopedURL),
                  importedFileIdentityResolver(resolvedRoot) == expectedIdentity else {
                courseSecurityScopeStopper(scopedURL)
                courseRootUnavailableReasons[courseID] = CourseProjectRootError.bookmarkResolutionFailed.localizedDescription
                continue
            }
            do {
                try validateRestoredCourseRoot(
                    resolvedRoot,
                    course: courses[index],
                    mustBeInsideLibrary: false
                )
            } catch {
                courseSecurityScopeStopper(scopedURL)
                courseRootUnavailableReasons[courseID] = error.localizedDescription
                continue
            }
            activeCourseSecurityScopes["course:\(courseID.uuidString)"] = scopedURL
            resolvedCourseRootURLs[courseID] = resolvedRoot
            if courses[index].sourceRootPath != resolvedRoot.path {
                courses[index].sourceRootPath = resolvedRoot.path
                courses[index].updatedAt = Date()
                changed = true
            }
            if resolution.isStale,
               let refreshedBookmark = courseRootBookmarkMaker(resolvedRoot) {
                courses[index].sourceRootBookmarkData = refreshedBookmark
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    private func restoreCourseReferencesInsideLibrary() -> Bool {
        guard let libraryRoot = courseLibraryRootURL else {
            for course in courses where course.sourceRootRelativePath != nil {
                courseRootUnavailableReasons[course.id] = courseLibraryUnavailableReason
                    ?? CourseProjectRootError.unavailableLibrary.localizedDescription
            }
            return false
        }
        var changed = false
        for index in courses.indices {
            guard let relativePath = courses[index].sourceRootRelativePath,
                  let expectedIdentity = courses[index].sourceRootIdentity else {
                continue
            }
            let expectedURL = CourseProjectPathPolicy.resolvedRelativePath(
                relativePath,
                inside: libraryRoot
            )
            let resolvedURL: URL?
            if let expectedURL,
               importedFileIdentityResolver(expectedURL) == expectedIdentity {
                resolvedURL = expectedURL
            } else {
                resolvedURL = findDirectory(
                    with: expectedIdentity,
                    inside: libraryRoot
                )
            }
            guard let resolvedURL,
                  let nextRelativePath = CourseProjectPathPolicy.relativePath(
                    of: resolvedURL,
                    inside: libraryRoot
                  ) else {
                courseRootUnavailableReasons[courses[index].id] = "课程文件夹当前不可用。"
                continue
            }
            let courseID = courses[index].id
            do {
                try validateRestoredCourseRoot(
                    resolvedURL,
                    course: courses[index],
                    mustBeInsideLibrary: true
                )
            } catch {
                courseRootUnavailableReasons[courseID] = error.localizedDescription
                continue
            }
            resolvedCourseRootURLs[courseID] = resolvedURL
            courseRootUnavailableReasons.removeValue(forKey: courseID)
            if courses[index].sourceRootRelativePath != nextRelativePath {
                courses[index].sourceRootRelativePath = nextRelativePath
                courses[index].updatedAt = Date()
                changed = true
            }
        }
        return changed
    }

    private func validateRestoredCourseRoot(
        _ root: URL,
        course: Course,
        mustBeInsideLibrary: Bool
    ) throws {
        try waitForCourseFileOperation {
            try await self.validateRestoredCourseRootAsync(
                root,
                course: course,
                mustBeInsideLibrary: mustBeInsideLibrary
            )
        }
    }

    private func validateRestoredCourseRootAsync(
        _ root: URL,
        course: Course,
        mustBeInsideLibrary: Bool
    ) async throws {
        try validateCourseProjectRoot(
            root,
            identity: course.sourceRootIdentity,
            mustBeInsideLibrary: mustBeInsideLibrary,
            excludingCourseID: course.id
        )
        guard let expectedIdentity = course.sourceRootIdentity,
              importedFileIdentityResolver(root) == expectedIdentity else {
            throw CourseProjectRootError.manifestMismatch
        }
        let manifestURL = root.appendingPathComponent(
            ".weibei/course.json"
        )
        let manifestData = try CourseProjectFileWorker
            .readBoundedRegularFile(
                at: manifestURL,
                maximumByteCount: 1_048_576
            )
        let manifest = try JSONDecoder().decode(
            CourseProjectManifest.self,
            from: manifestData
        )
        guard manifest.courseID == course.id,
              manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion else {
            throw CourseProjectRootError.manifestMismatch
        }
        if manifest.portableExport != nil {
            let evidence = try await courseProjectFileWorker
                .adoptionSnapshotWithThreadEvidence(
                    at: root,
                    expectedRootIdentity: expectedIdentity
                )
            lastPortableAdoptionReadRanOnMainThread =
                evidence.ranOnMainThread
            let snapshot = evidence.snapshot
            guard snapshot.manifest.courseID == course.id,
                  snapshot.manifest.portableExport != nil,
                  snapshot.manifestData == manifestData else {
                throw CourseProjectRootError.manifestMismatch
            }
            try await courseProjectFileWorker
                .normalizePortableCourseManifest(
                    with: CourseProjectManifest(
                        courseID: course.id
                    ).encoded(),
                    at: manifestURL,
                    expectedDirectoryIdentity:
                        snapshot.metadataIdentity,
                    expectedPreviousData:
                        snapshot.manifestData
                )
        }
    }

    private func findDirectory(
        with identity: ImportedFileIdentity,
        inside libraryRoot: URL
    ) -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }
        for case let candidate as URL in enumerator {
            let values = try? candidate.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { continue }
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL
            if importedFileIdentityResolver(canonical) == identity {
                return canonical
            }
        }
        return nil
    }

    func renameCourse(_ courseID: UUID, title rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeCourseRemovalTokens[courseID] == nil,
              !title.isEmpty,
              let index = courses.firstIndex(where: { $0.id == courseID }),
              courses[index].title != title else { return }
        courses[index].title = title
        courses[index].updatedAt = Date()
        save()
    }

    func removeCourseFromWeiBei(_ courseID: UUID) async throws {
        let transactionID = try beginCourseRemovalTransaction()
        defer { finishCourseRemovalTransaction(transactionID) }
        let prepared = try await prepareCourseRemoval(
            courseID,
            token: transactionID,
            requiresAvailableRoot: false
        )
        let shouldDismissCourseWorkspace =
            courseWorkspacePresented
                && courseWorkspaceCourseID == courseID
        guard await persistWorkspaceRemovingCourse(courseID) else {
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: false
            )
            throw CourseRemovalError.workspaceSaveFailed
        }
        removeCourseLocalRegistration(courseID)
        if shouldDismissCourseWorkspace {
            courseWorkspacePresented = false
        }
        finishCourseRemovalAttempt(
            courseID,
            token: prepared.token,
            succeeded: true
        )
    }

    @discardableResult
    func moveCourseFolderToTrash(_ courseID: UUID) async throws -> URL {
        let transactionID = try beginCourseRemovalTransaction()
        defer { finishCourseRemovalTransaction(transactionID) }
        let prepared = try await prepareCourseRemoval(
            courseID,
            token: transactionID,
            requiresAvailableRoot: true
        )
        let shouldDismissCourseWorkspace =
            courseWorkspacePresented
                && courseWorkspaceCourseID == courseID
        guard let root = prepared.root,
              let rootIdentity = prepared.rootIdentity else {
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: false
            )
            throw CourseRemovalError.courseRootUnavailable
        }

        var journal = PendingCourseRemovalJournal(
            transactionID: transactionID,
            courseID: courseID,
            expectedCourse: prepared.course,
            rootPath: root.path,
            rootIdentity: rootIdentity,
            isolationPath: root.deletingLastPathComponent()
                .appendingPathComponent(
                    ".weibei-course-removal-\(transactionID.uuidString.lowercased())",
                    isDirectory: true
                )
                .appendingPathComponent(
                    root.lastPathComponent,
                    isDirectory: true
                ).path,
            trashBookmarkData: nil,
            trashPath: nil,
            stage: .prepared
        )
        do {
            try writePendingCourseRemovalJournal(journal)
            try courseProjectMutationHook(.beforeCourseRootTrashMove)
            guard course(withID: courseID) == prepared.course,
                  activeCourseRemovalTokens[courseID] == prepared.token,
                  !courseHasPendingWork(courseID),
                  coursePortableStateMatchesLastSaved(courseID),
                  let currentRoot = courseRootURL(for: courseID),
                  CourseProjectPathPolicy.isSame(currentRoot, root),
                  importedFileIdentityResolver(currentRoot)
                    == rootIdentity else {
                throw CourseRemovalError.courseRootChanged
            }
            let selfCheckDestination = workspaceDirectory
                .appendingPathComponent(
                    "SelfCheckTrash",
                    isDirectory: true
                )
                .appendingPathComponent(
                    journal.transactionID.uuidString,
                    isDirectory: true
                )
            let isolation = try await courseProjectFileWorker
                .isolateCourseRootForTrash(
                    at: currentRoot,
                    expectedIdentity: rootIdentity,
                    expectedCourseID: courseID,
                    transactionID: transactionID,
                    beforeIsolation: {
                        try self.courseProjectMutationHook(
                            .beforeCourseRootTrashIsolation
                        )
                    }
                )
            try courseProjectMutationHook(
                .afterCourseRootTrashIsolationBeforeJournal
            )
            journal.isolationPath = isolation.isolatedURL.path
            guard let trashBookmarkData =
                    courseRootBookmarkMaker(
                        isolation.isolatedURL
                    ) else {
                throw CourseProjectFileWorkerError
                    .verificationFailed
            }
            journal.trashBookmarkData = trashBookmarkData
            journal.stage = .isolated
            try writePendingCourseRemovalJournal(journal)
            let trashedRoot = try await courseProjectFileWorker
                .moveIsolatedCourseRootToTrash(
                    isolation,
                    expectedCourseID: courseID,
                    selfCheckDestination: selfCheckDestination
                )
            try courseProjectMutationHook(
                .afterCourseRootTrashMoveBeforeJournal
            )
            journal.trashPath = trashedRoot.path
            journal.stage = .trashed
            try writePendingCourseRemovalJournal(journal)
            try courseProjectMutationHook(
                .afterCourseRootTrashJournalBeforeWorkspaceSave
            )

            guard await persistWorkspaceRemovingCourse(courseID) else {
                courseRootUnavailableReasons[courseID] =
                    CourseRemovalError.workspaceSaveFailedAfterTrash(
                        trashedRoot
                    ).localizedDescription
                finishCourseRemovalAttempt(
                    courseID,
                    token: prepared.token,
                    succeeded: false
                )
                throw CourseRemovalError.workspaceSaveFailedAfterTrash(
                    trashedRoot
                )
            }

            removeCourseLocalRegistration(courseID)
            journal.stage = .workspaceCommitted
            try? writePendingCourseRemovalJournal(journal)
            removePendingCourseRemovalJournal()
            if shouldDismissCourseWorkspace {
                courseWorkspacePresented = false
            }
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: true
            )
            return trashedRoot
        } catch {
            if importedFileIdentityResolver(root) == rootIdentity {
                removePendingCourseRemovalJournal()
            } else {
                courseRootUnavailableReasons[courseID] =
                    error.localizedDescription
            }
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: false
            )
            throw error
        }
    }

    func revealCourseRoot(_ courseID: UUID) {
        guard let root = courseRootURL(for: courseID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    func removeCourseFromWeiBeiForSelfCheck(
        _ courseID: UUID
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try waitForCourseFileOperation {
            try await self.removeCourseFromWeiBei(courseID)
        }
    }

#if DEBUG
    func verifyCourseRemovalPersistenceRaceForSelfCheck(
        removing courseID: UUID,
        retaining retainedCourseID: UUID
    ) throws -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            let transactionID = try self.beginCourseRemovalTransaction()
            defer {
                self.finishCourseRemovalTransaction(transactionID)
                self.usesBackgroundWorkspacePersistenceForSelfCheck = false
            }
            let prepared = try await self.prepareCourseRemoval(
                courseID,
                token: transactionID,
                requiresAvailableRoot: false
            )
            var removalSucceeded = false
            defer {
                self.finishCourseRemovalAttempt(
                    courseID,
                    token: prepared.token,
                    succeeded: removalSucceeded
                )
            }

            self.usesBackgroundWorkspacePersistenceForSelfCheck = true
            let firstGeneration = self.workspaceSaveGeneration &+ 1
            await self.courseProjectFileWorker
                .prepareWorkspacePersistenceGateForSelfCheck(
                    generation: firstGeneration
                )
            let removal = Task { @MainActor in
                await self.persistWorkspaceRemovingCourse(courseID)
            }
            await self.courseProjectFileWorker
                .waitUntilWorkspacePersistenceEnteredForSelfCheck(
                    generation: firstGeneration
                )

            guard let retainedIndex = self.courses.firstIndex(where: {
                $0.id == retainedCourseID
            }) else {
                await self.courseProjectFileWorker
                    .releaseWorkspacePersistenceForSelfCheck(
                        generation: firstGeneration
                    )
                _ = await removal.value
                return false
            }
            self.courses[retainedIndex].title = "保留课程（第二代）"
            self.courses[retainedIndex].updatedAt = Date()
            self.modelName = "课程移除第二代全局状态"
            self.workspaceSaveGeneration &+= 1
            let failingGeneration = self.workspaceSaveGeneration
            await self.courseProjectFileWorker
                .failWorkspacePersistenceForSelfCheck(
                    generation: failingGeneration
                )
            await self.courseProjectFileWorker
                .releaseWorkspacePersistenceForSelfCheck(
                    generation: firstGeneration
                )
            guard await removal.value,
                  self.workspaceSaveError != nil else {
                return false
            }

            let firstCommitted = try JSONDecoder().decode(
                PersistedWorkspace.self,
                from: Data(contentsOf: self.storageURL)
            )
            guard firstCommitted.courses?.contains(where: {
                $0.id == courseID
            }) != true else {
                return false
            }
            self.removeCourseLocalRegistration(courseID)
            removalSucceeded = true
            self.usesBackgroundWorkspacePersistenceForSelfCheck = false
            guard self.flushPendingWorkspaceSave() else { return false }

            let compensated = try JSONDecoder().decode(
                PersistedWorkspace.self,
                from: Data(contentsOf: self.storageURL)
            )
            return self.course(withID: courseID) == nil
                && self.course(withID: retainedCourseID)?.title
                    == "保留课程（第二代）"
                && self.modelName == "课程移除第二代全局状态"
                && compensated.courses?.contains(where: {
                    $0.id == courseID
                }) != true
                && compensated.courses?.first(where: {
                    $0.id == retainedCourseID
                })?.title == "保留课程（第二代）"
                && compensated.modelName
                    == "课程移除第二代全局状态"
        }
    }
#endif

    @discardableResult
    func moveCourseFolderToTrashForSelfCheck(
        _ courseID: UUID
    ) throws -> URL {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            try await self.moveCourseFolderToTrash(courseID)
        }
    }

    func finishPendingCourseRemovalRecoveryForSelfCheck()
        throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let maintenanceTask = courseReconciliationTask
        maintenanceTask?.cancel()
        courseReconciliationTask = nil
        try waitForCourseFileOperation {
            await maintenanceTask?.value
            await self
                .finishPendingCourseRemovalRecoveryIfNeeded()
        }
    }

    func installCourseRemovalStateForSelfCheck(
        courseID: UUID,
        materialItemID: String,
        noteItemID: String,
        messageText: String,
        memoryText: String,
        globalMemoryText: String
    ) throws -> UUID {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let material = importedItems.first(where: {
            $0.id == materialItemID
        }),
        let session = createStudySession(courseID: courseID) else {
            throw CourseRemovalError.courseNotFound
        }
        let message = AgentMessage(
            role: .user,
            text: messageText,
            source: nil
        )
        guard let sessionIndex = studySessions.firstIndex(where: {
            $0.id == session.id
        }) else {
            throw CourseRemovalError.courseNotFound
        }
        studySessions[sessionIndex].messages = [message]
        messages = [message]
        let memory = LearningMemoryEntry(
            kind: .progress,
            text: memoryText,
            evidence: "A0c 自检",
            origin: .agentInference,
            sessionID: session.id,
            messageID: message.id
        )
        learningMemoryStates.removeAll {
            $0.scope == .course(courseID)
        }
        learningMemoryStates.append(
            ScopedLearningMemoryState(
                scope: .course(courseID),
                revision: 1,
                entries: [memory]
            )
        )
        learningMemoryStates.removeAll { $0.scope == .global }
        learningMemoryStates.append(
            ScopedLearningMemoryState(
                scope: .global,
                revision: 1,
                entries: [
                    LearningMemoryEntry(
                        kind: .preference,
                        text: globalMemoryText,
                        evidence: "A0c 全局隔离自检",
                        origin: .userStatement
                    ),
                ]
            )
        )
        let location = StudyLocation(
            itemID: materialItemID,
            itemTitle: material.title,
            locationID: "a0c-removal",
            locationTitle: "A0c 自检位置",
            pageIndex: 2,
            lastStudiedAt: Date(),
            visitCount: 1
        )
        studyLocationsByCourseID[
            courseID.uuidString,
            default: [:]
        ][materialItemID] = location
        courseResumePoints.removeAll { $0.courseID == courseID }
        courseResumePoints.append(
            CourseResumePoint(
                courseID: courseID,
                materialLocation: location,
                chatID: session.id,
                noteItemID: noteItemID
            )
        )
        return session.id
    }

    func removeCourseRegistrationImmediatelyForSelfCheck(
        _ courseID: UUID
    ) {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard courses.contains(where: { $0.id == courseID }) else {
            return
        }
        removeCourseLocalRegistration(courseID)
        resolvedCourseRootURLs.removeValue(forKey: courseID)
        courseRootUnavailableReasons.removeValue(forKey: courseID)
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
    }

    private func prepareCourseRemoval(
        _ courseID: UUID,
        token: UUID,
        requiresAvailableRoot: Bool
    ) async throws -> (
        course: Course,
        root: URL?,
        rootIdentity: ImportedFileIdentity?,
        token: UUID
    ) {
        guard let expectedCourse = course(withID: courseID) else {
            throw CourseRemovalError.courseNotFound
        }
        guard activeCourseRemovalTransactionID == token,
              activeCourseRemovalTokens[courseID] == nil,
              activeCourseRebindTokens[courseID] == nil else {
            throw CourseRemovalError.courseBusy
        }

        let noteItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID == courseID
            }.map(\.itemID)
        )
        if let stagedNoteDraft,
           noteItemIDs.contains(stagedNoteDraft.itemID) {
            self.stagedNoteDraft = nil
            updateNote(
                stagedNoteDraft.value,
                for: stagedNoteDraft.itemID
            )
        }
        for itemID in noteItemIDs {
            flushPendingNotePersistence(for: itemID)
        }
        for itemID in noteItemIDs {
            while let task = courseNoteWriteTasksByItemID[itemID] {
                await task.value
            }
        }

        guard course(withID: courseID) == expectedCourse,
              activeCourseRemovalTransactionID == token,
              activeCourseRemovalTokens[courseID] == nil,
              activeCourseRebindTokens[courseID] == nil else {
            throw CourseRemovalError.courseBusy
        }
        activeCourseRemovalTokens[courseID] = token
        do {
            while activeCourseFileMutationCounts[courseID, default: 0] > 0 {
                await Task.yield()
            }
            cancelAgentRequestIfRunning(in: courseID)
            await agentStopTask?.value

            let reconciliationTask = courseReconciliationTask
            courseReconciliationTask?.cancel()
            courseReconciliationTask = nil
            await reconciliationTask?.value

            guard course(withID: courseID) == expectedCourse,
                  activeCourseRemovalTransactionID == token,
                  activeCourseRemovalTokens[courseID] == token,
                  activeCourseFileMutationCounts[
                    courseID,
                    default: 0
                  ] == 0,
                  !courseHasPendingWork(courseID) else {
                throw CourseRemovalError.courseBusy
            }

            syncActiveStudySession()
            let root = courseRootURL(for: courseID)
            let rootIdentity = root.flatMap(
                importedFileIdentityResolver
            )
            if requiresAvailableRoot {
                guard let root,
                      let expectedIdentity =
                        expectedCourse.sourceRootIdentity,
                      rootIdentity == expectedIdentity else {
                    throw CourseRemovalError.courseRootUnavailable
                }
                try await validateRestoredCourseRootAsync(
                    root,
                    course: expectedCourse,
                    mustBeInsideLibrary:
                        expectedCourse.sourceRootRelativePath != nil
                )
            }

            if root != nil {
                guard await persistWorkspaceNow(),
                      !dirtyPortableCourseIDs.contains(courseID),
                      !blockedPortableCourseIDs.contains(courseID),
                      !oversizedPortableCourseIDs.contains(courseID),
                      coursePortableStateRevisions[courseID] != nil,
                      coursePortableStateDigests[courseID] != nil,
                      coursePortableStateMatchesLastSaved(
                        courseID
                      ) else {
                    throw CourseRemovalError.latestStateNotSaved
                }
            } else {
                let hasCourseOwnedItems = importedItems.contains { item in
                    guard case .courseOwned(let ownerCourseID) = item.storage else {
                        return false
                    }
                    return ownerCourseID == courseID
                }
                guard !hasCourseOwnedItems else {
                    throw CourseRemovalError.latestStateNotSaved
                }
                let isRootlessLegacyCourse =
                    expectedCourse.sourceRootPath == nil
                    && expectedCourse.sourceRootRelativePath == nil
                    && expectedCourse.sourceRootIdentity == nil
                    && expectedCourse.sourceRootBookmarkData == nil
                if !isRootlessLegacyCourse {
                    guard !requiresAvailableRoot,
                          !dirtyPortableCourseIDs.contains(courseID),
                          !blockedPortableCourseIDs.contains(courseID),
                          !oversizedPortableCourseIDs.contains(courseID),
                          coursePortableStateRevisions[courseID] != nil,
                          coursePortableStateDigests[courseID] != nil,
                          coursePortableStateMatchesLastSaved(
                            courseID
                          ) else {
                        throw CourseRemovalError.latestStateNotSaved
                    }
                }
            }

            return (
                expectedCourse,
                root,
                rootIdentity,
                token
            )
        } catch {
            finishCourseRemovalAttempt(
                courseID,
                token: token,
                succeeded: false
            )
            throw error
        }
    }

    private func coursePortableStateMatchesLastSaved(
        _ courseID: UUID
    ) -> Bool {
        guard let revision =
                coursePortableStateRevisions[courseID],
              let expectedDigest =
                coursePortableStateDigests[courseID],
              let state = try? makeCoursePortableState(
                courseID: courseID,
                revision: revision,
                savedAt: Date(timeIntervalSince1970: 0)
              ),
              let digest = try? coursePortableStatePayloadDigest(
                state
              ) else {
            return false
        }
        return digest == expectedDigest
    }

    private func removeCourseLocalRegistration(_ courseID: UUID) {
        let removedItemIDs = Set(
            importedItems.compactMap { item -> String? in
                guard case .courseOwned(let ownerCourseID) = item.storage,
                      ownerCourseID == courseID else {
                    return nil
                }
                return item.id
            }
        )

        for itemID in removedItemIDs {
            pendingNotePersistenceTasks
                .removeValue(forKey: itemID)?.cancel()
            courseNoteLoadTasksByItemID
                .removeValue(forKey: itemID)?.cancel()
            courseNoteWriteTasksByItemID
                .removeValue(forKey: itemID)?.cancel()
            pendingNotePersistenceByItemID.removeValue(forKey: itemID)
            courseNoteLoadGenerationByItemID.removeValue(forKey: itemID)
            courseNoteWritesInFlight.remove(itemID)
            notesByItemID.removeValue(forKey: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteOperationErrorsByItemID.removeValue(forKey: itemID)
            noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
            loadedCourseNoteTextByItemID.removeValue(forKey: itemID)
            studyLocationsByItemID.removeValue(forKey: itemID)
        }

        importedItems.removeAll {
            removedItemIDs.contains($0.id)
        }
        courseItemMemberships.removeAll {
            $0.courseID == courseID
        }
        noteSourceLinks.removeAll {
            removedItemIDs.contains($0.noteItemID)
                || removedItemIDs.contains($0.sourceItemID)
        }
        materialNotePairings = materialNotePairings.filter {
            !removedItemIDs.contains($0.key)
                && !removedItemIDs.contains($0.value)
        }
        noteMaterialPairings = noteMaterialPairings.filter {
            !removedItemIDs.contains($0.key)
                && !removedItemIDs.contains($0.value)
        }
        studyLocationsByCourseID.removeValue(
            forKey: courseID.uuidString
        )
        courseResumePoints.removeAll { $0.courseID == courseID }
        learningMemoryStates.removeAll {
            $0.scope == .course(courseID)
        }
        courseKnowledgeProfiles.removeAll { $0.courseID == courseID }
        courses.removeAll { $0.id == courseID }

        for index in studySessions.indices {
            studySessions[index].relatedCourseIDs.removeAll {
                $0 == courseID
            }
            studySessions[index].focusItemIDs.removeAll {
                removedItemIDs.contains($0)
            }
            if studySessions[index].materialItemID.map(
                removedItemIDs.contains
            ) == true {
                studySessions[index].materialItemID = nil
            }
        }

        selectionAskThreads = selectionAskThreads.compactMap {
            thread -> SelectionAskThread? in
            if thread.itemID.map(removedItemIDs.contains) == true {
                return nil
            }
            return thread
        }
        if activeSelectionAskThreadID.map({ id in
            !selectionAskThreads.contains { $0.id == id }
        }) == true {
            activeSelectionAskThreadID = nil
        }
        if selectionContext?.itemID.map(
            removedItemIDs.contains
        ) == true {
            selectionContext = nil
        }
        selectionAttachments.removeAll {
            $0.itemID.map(removedItemIDs.contains) == true
        }
        backNavigationStack.removeAll {
            $0.selectedItemID.map(removedItemIDs.contains) == true
                || $0.activeNotebookItemID.map(
                    removedItemIDs.contains
                ) == true
        }
        forwardNavigationStack.removeAll {
            $0.selectedItemID.map(removedItemIDs.contains) == true
                || $0.activeNotebookItemID.map(
                    removedItemIDs.contains
                ) == true
        }

        if selectedItemID.map(removedItemIDs.contains) == true {
            selectedItemID = importedItems.first(where: {
                !$0.isNotebookNote
            })?.id
        }
        if activeNotebookItemID.map(
            removedItemIDs.contains
        ) == true {
            activeNotebookItemID = importedItems.first(
                where: \.isNotebookNote
            )?.id
        }
        noteText = noteText(for: activeNoteItem)

        if activeCourseID == courseID {
            activeCourseID = courses.first?.id
        }
        if courseWorkspaceCourseID == courseID {
            courseWorkspaceCourseID = nil
            courseWorkspaceDestination = .hub
            courseWorkspaceTargetItemID = nil
        }

        ensureActiveStudySession()
        if let activeStudySessionID {
            restoreAgentDraft(for: activeStudySessionID)
        }
        if let activeStudySession {
            messages = activeStudySession.messages
            restoreAgentReplyState(from: activeStudySession)
        }

        coursePortableStateRevisions.removeValue(forKey: courseID)
        coursePortableStateDigests.removeValue(forKey: courseID)
        dirtyPortableCourseIDs.remove(courseID)
        blockedPortableCourseIDs.remove(courseID)
        oversizedPortableCourseIDs.remove(courseID)
    }

    private func finishCourseRemovalAttempt(
        _ courseID: UUID,
        token: UUID,
        succeeded: Bool,
        restartMaintenance: Bool = true
    ) {
        guard activeCourseRemovalTokens[courseID] == token else {
            return
        }
        activeCourseRemovalTokens.removeValue(forKey: courseID)
        if succeeded {
            let scopeKey = "course:\(courseID.uuidString)"
            activeCourseSecurityScopeOwnerTokens.removeValue(
                forKey: scopeKey
            )
            if let scopedURL = activeCourseSecurityScopes.removeValue(
                forKey: scopeKey
            ) {
                courseSecurityScopeStopper(scopedURL)
            }
            resolvedCourseRootURLs.removeValue(forKey: courseID)
            courseRootUnavailableReasons.removeValue(forKey: courseID)
            courseDocumentSearchIndex.synchronize(allItems)
            invalidateAgentContext()
        }
        if restartMaintenance,
           !WeiBeiSafetyTestMode.isEnabled {
            startCourseFileMaintenance()
        }
    }

    private func beginCourseRemovalTransaction(
        resumesPendingRecovery: Bool = false
    ) throws -> UUID {
        if !resumesPendingRecovery {
            clearResolvedPreparedCourseRemovalJournalIfSafe()
        }
        guard activeCourseRemovalTransactionID == nil,
              resumesPendingRecovery
                || (
                    pendingCourseRemovalRecovery == nil
                        && !FileManager.default.fileExists(
                            atPath: courseRemovalJournalURL.path
                        )
                ) else {
            throw CourseRemovalError.courseBusy
        }
        let transactionID = UUID()
        activeCourseRemovalTransactionID = transactionID
        return transactionID
    }

    private func clearResolvedPreparedCourseRemovalJournalIfSafe() {
        guard pendingCourseRemovalRecovery == nil,
              let data = try? Data(
                contentsOf: courseRemovalJournalURL
              ),
              let journal = try? JSONDecoder().decode(
                PendingCourseRemovalJournal.self,
                from: data
              ),
              journal.stage == .prepared,
              course(withID: journal.courseID)
                == journal.expectedCourse,
              importedFileIdentityResolver(
                URL(
                    fileURLWithPath: journal.rootPath,
                    isDirectory: true
                )
              ) == journal.rootIdentity else {
            return
        }
        removePendingCourseRemovalJournal()
    }

    private func finishCourseRemovalTransaction(
        _ transactionID: UUID
    ) {
        guard activeCourseRemovalTransactionID == transactionID else {
            return
        }
        activeCourseRemovalTransactionID = nil
    }

    private func beginCourseFileMutation(
        courseIDs: Set<UUID>
    ) throws {
        guard !courseIDs.isEmpty,
              courseIDs.allSatisfy({ courseID in
                courses.contains(where: { $0.id == courseID })
              }) else {
            throw CourseOwnedFileError.courseNotFound
        }
        guard courseIDs.allSatisfy({
            activeCourseRemovalTokens[$0] == nil
        }) else {
            throw CoursePortableExportError.unstableCourseState
        }
        for courseID in courseIDs {
            activeCourseFileMutationCounts[courseID, default: 0] += 1
        }
    }

    private func finishCourseFileMutation(
        courseIDs: Set<UUID>
    ) {
        for courseID in courseIDs {
            let count = activeCourseFileMutationCounts[
                courseID,
                default: 0
            ]
            if count <= 1 {
                activeCourseFileMutationCounts.removeValue(
                    forKey: courseID
                )
            } else {
                activeCourseFileMutationCounts[courseID] = count - 1
            }
        }
    }

    private func writePendingCourseRemovalJournal(
        _ journal: PendingCourseRemovalJournal
    ) throws {
        let data = try JSONEncoder().encode(journal)
        try data.write(
            to: courseRemovalJournalURL,
            options: [.atomic]
        )
    }

    private func removePendingCourseRemovalJournal() {
        try? FileManager.default.removeItem(
            at: courseRemovalJournalURL
        )
    }

    private func recoverPendingCourseRemovalIfNeeded() -> Bool {
        guard let data = try? Data(
            contentsOf: courseRemovalJournalURL
        ),
        let journal = try? JSONDecoder().decode(
            PendingCourseRemovalJournal.self,
            from: data
        ) else {
            return false
        }
        guard let currentCourse = course(withID: journal.courseID) else {
            if journal.stage == .trashed
                || journal.stage == .workspaceCommitted {
                removePendingCourseRemovalJournal()
            }
            return false
        }
        guard currentCourse == journal.expectedCourse else {
            courseRootUnavailableReasons[journal.courseID] = ui(
                "发现未完成的课程移除记录，但课程登记已经变化；魏碑没有继续处理。",
                "WeiBei found an unfinished course removal, but the course registration changed, so it stopped."
            )
            return false
        }

        switch journal.stage {
        case .prepared:
            let originalRoot = URL(
                fileURLWithPath: journal.rootPath,
                isDirectory: true
            )
            if importedFileIdentityResolver(originalRoot)
                == journal.rootIdentity {
                removePendingCourseRemovalJournal()
            } else if let isolationPath = journal.isolationPath {
                let isolatedURL = URL(
                    fileURLWithPath: isolationPath,
                    isDirectory: true
                )
                guard importedFileIdentityResolver(isolatedURL)
                        == journal.rootIdentity else {
                    courseRootUnavailableReasons[journal.courseID] =
                        ui(
                            "课程文件夹移动后，魏碑尚未确认新位置。课程登记和恢复记录都已保留。",
                            "The course folder moved before WeiBei recorded its new location. The registration and recovery record were preserved."
                        )
                    return false
                }
                var isolatedJournal = journal
                isolatedJournal.stage = .isolated
                isolatedJournal.trashBookmarkData =
                    courseRootBookmarkMaker(isolatedURL)
                do {
                    try writePendingCourseRemovalJournal(
                        isolatedJournal
                    )
                    pendingCourseRemovalRecovery =
                        isolatedJournal
                } catch {
                    courseRootUnavailableReasons[journal.courseID] =
                        error.localizedDescription
                }
            } else {
                courseRootUnavailableReasons[journal.courseID] = ui(
                    "课程文件夹移动后，魏碑尚未确认新位置。课程登记和恢复记录都已保留。",
                    "The course folder moved before WeiBei recorded its new location. The registration and recovery record were preserved."
                )
            }
            return false
        case .isolated:
            if journal.isolationPath == nil
                && journal.trashBookmarkData == nil {
                courseRootUnavailableReasons[journal.courseID] = ui(
                    "课程移除恢复记录不完整，魏碑没有继续移动或取消登记。",
                    "The course removal recovery record is incomplete, so WeiBei did not continue moving it or remove its registration."
                )
                return false
            }
            pendingCourseRemovalRecovery = journal
            return false
        case .trashed:
            guard let trashPath = journal.trashPath else {
                return false
            }
            let trashedRoot = URL(
                fileURLWithPath: trashPath,
                isDirectory: true
            )
            guard importedFileIdentityResolver(trashedRoot)
                    == journal.rootIdentity else {
                courseRootUnavailableReasons[journal.courseID] = ui(
                    "废纸篓中的课程文件夹无法再次核验，魏碑没有取消本机登记。",
                    "WeiBei could not verify the course folder in Trash, so it kept the local registration."
                )
                return false
            }
            removeCourseLocalRegistration(journal.courseID)
            resolvedCourseRootURLs.removeValue(
                forKey: journal.courseID
            )
            courseRootUnavailableReasons.removeValue(
                forKey: journal.courseID
            )
            pendingCourseRemovalRecovery = journal
            return true
        case .workspaceCommitted:
            removePendingCourseRemovalJournal()
            return false
        }
    }

    private func finishPendingCourseRemovalRecoveryIfNeeded()
        async {
        guard var journal = pendingCourseRemovalRecovery else {
            return
        }
        if let currentCourse = course(withID: journal.courseID),
           currentCourse != journal.expectedCourse {
            return
        }
        if journal.stage == .isolated,
           course(withID: journal.courseID) == nil {
            return
        }
        let transactionID: UUID
        do {
            transactionID = try beginCourseRemovalTransaction(
                resumesPendingRecovery: true
            )
        } catch {
            return
        }
        defer { finishCourseRemovalTransaction(transactionID) }
        activeCourseRemovalTokens[journal.courseID] =
            transactionID
        defer {
            finishCourseRemovalAttempt(
                journal.courseID,
                token: transactionID,
                succeeded: false,
                restartMaintenance: false
            )
        }

        if journal.stage == .isolated {
            let isolatedURL = journal.isolationPath.map {
                URL(
                    fileURLWithPath: $0,
                    isDirectory: true
                )
            }
            if let isolatedURL,
               importedFileIdentityResolver(isolatedURL)
                    == journal.rootIdentity {
                if journal.trashBookmarkData == nil {
                    journal.trashBookmarkData =
                        courseRootBookmarkMaker(isolatedURL)
                }
                do {
                    journal.stage = .isolated
                    try writePendingCourseRemovalJournal(journal)
                } catch {
                    courseRootUnavailableReasons[journal.courseID] =
                        error.localizedDescription
                    return
                }
                let transactionDirectory =
                    isolatedURL.deletingLastPathComponent()
                guard let transactionDirectoryIdentity =
                        importedFileIdentityResolver(
                            transactionDirectory
                        ) else {
                    return
                }
                let isolation = CourseRootTrashIsolation(
                    originalURL: URL(
                        fileURLWithPath: journal.rootPath,
                        isDirectory: true
                    ),
                    transactionDirectory: transactionDirectory,
                    transactionDirectoryIdentity:
                        transactionDirectoryIdentity,
                    isolatedURL: isolatedURL,
                    identity: journal.rootIdentity
                )
                let selfCheckDestination = workspaceDirectory
                    .appendingPathComponent(
                        "SelfCheckTrash",
                        isDirectory: true
                    )
                    .appendingPathComponent(
                        journal.transactionID.uuidString,
                        isDirectory: true
                    )
                do {
                    let trashURL = try await courseProjectFileWorker
                        .moveIsolatedCourseRootToTrash(
                            isolation,
                            expectedCourseID: journal.courseID,
                            selfCheckDestination:
                                selfCheckDestination
                        )
                    try courseProjectMutationHook(
                        .afterCourseRootTrashMoveBeforeJournal
                    )
                    journal.trashPath = trashURL.path
                    journal.stage = .trashed
                    try writePendingCourseRemovalJournal(journal)
                } catch {
                    courseRootUnavailableReasons[journal.courseID] =
                        error.localizedDescription
                    return
                }
            } else {
                var searchDirectories = FileManager.default.urls(
                    for: .trashDirectory,
                    in: .userDomainMask
                )
                if WeiBeiSafetyTestMode.isEnabled {
                    searchDirectories.append(
                        workspaceDirectory.appendingPathComponent(
                            "SelfCheckTrash",
                            isDirectory: true
                        )
                    )
                }
                var locatedTrashRoot: URL?
                if let bookmarkData = journal.trashBookmarkData,
                   let resolved = courseRootBookmarkResolver(
                    bookmarkData
                   ),
                   searchDirectories.contains(where: {
                       CourseProjectPathPolicy.contains(
                        $0,
                        resolved.url,
                        includingRoot: false
                       )
                   }) {
                    let startedScope =
                        courseSecurityScopeStarter(resolved.url)
                    let bookmarkVerified: Bool
                    if startedScope {
                        bookmarkVerified =
                            await courseProjectFileWorker
                                .verifiedCourseRoot(
                                    at: resolved.url,
                                    expectedIdentity:
                                        journal.rootIdentity,
                                    expectedCourseID:
                                        journal.courseID
                                )
                        courseSecurityScopeStopper(resolved.url)
                    } else {
                        bookmarkVerified =
                            await courseProjectFileWorker
                                .verifiedCourseRoot(
                                    at: resolved.url,
                                    expectedIdentity:
                                        journal.rootIdentity,
                                    expectedCourseID:
                                        journal.courseID
                                )
                    }
                    if bookmarkVerified {
                        locatedTrashRoot = resolved.url
                    }
                }
                if locatedTrashRoot == nil {
                    locatedTrashRoot =
                        await courseProjectFileWorker
                            .findVerifiedCourseRoot(
                                in: searchDirectories,
                                expectedIdentity:
                                    journal.rootIdentity,
                                expectedCourseID:
                                    journal.courseID
                            )
                }
                guard let locatedTrashRoot else {
                    courseRootUnavailableReasons[journal.courseID] =
                        ui(
                            "课程文件夹已经离开原位置，但魏碑尚未在废纸篓中重新核验到它；课程登记和恢复记录都已保留。",
                            "The course folder left its original location, but WeiBei has not reverified it in Trash. The registration and recovery record were preserved."
                        )
                    return
                }
                journal.trashPath =
                    locatedTrashRoot.standardizedFileURL.path
                journal.stage = .trashed
                do {
                    try writePendingCourseRemovalJournal(journal)
                } catch {
                    return
                }
            }
        }
        guard journal.stage == .trashed,
              let trashPath = journal.trashPath,
              importedFileIdentityResolver(
                URL(
                    fileURLWithPath: trashPath,
                    isDirectory: true
                )
              ) == journal.rootIdentity else {
            return
        }
        if course(withID: journal.courseID) != nil {
            removeCourseLocalRegistration(journal.courseID)
        }
        guard await persistWorkspaceNow() else {
            pendingCourseRemovalRecovery = journal
            return
        }
        journal.stage = .workspaceCommitted
        try? writePendingCourseRemovalJournal(journal)
        removePendingCourseRemovalJournal()
        pendingCourseRemovalRecovery = nil
        finishCourseRemovalAttempt(
            journal.courseID,
            token: transactionID,
            succeeded: true,
            restartMaintenance: false
        )
    }

    private func promoteCourseOwnedItemToCommon(
        itemID: String,
        conflictResolution: CourseFileConflictResolution
    ) async throws {
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID
        }),
        case .courseOwned(let ownerCourseID) =
            importedItems[itemIndex].storage,
        let ownerRoot = courseRootURL(for: ownerCourseID),
        let membershipIndex = uniqueCourseOwnedMembershipIndex(
            itemID: itemID,
            courseID: ownerCourseID
        ),
        let relativePath = courseItemMemberships[membershipIndex]
            .courseRelativePath,
        let libraryRoot = courseLibraryRootURL else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        let role: CourseOwnedFileRole = importedItems[itemIndex]
            .isNotebookNote ? .note : .material
        guard let sourceURL = safeCourseOwnedFileURL(
            relativePath: relativePath,
            role: role,
            inside: ownerRoot
        ) else {
            throw CourseOwnedFileError.verificationFailed
        }

        try beginCourseFileMutation(courseIDs: [ownerCourseID])
        defer { finishCourseFileMutation(courseIDs: [ownerCourseID]) }

        let sourceInfo = try await courseProjectFileWorker
            .validatedRegularSource(sourceURL)
        let sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sourceURL,
            expectedIdentity: sourceInfo.identity
        )
        let commonDirectory = try await courseProjectFileWorker
            .ensureRealDirectory(
                libraryRoot.appendingPathComponent(
                    role.commonDirectoryName,
                    isDirectory: true
                ),
                inside: libraryRoot
            )
        let targetURL = try resolvedCourseImportTarget(
            fileName: sourceURL.lastPathComponent,
            destinationDirectory: commonDirectory,
            role: role,
            conflictResolution: conflictResolution
        )
        guard !FileManager.default.fileExists(atPath: targetURL.path),
              let commonDirectoryIdentity = importedFileIdentityResolver(
                commonDirectory
              ) else {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        let operationID = UUID()
        let payloadURL = commonDirectory.appendingPathComponent(
            ".\(targetURL.lastPathComponent).weibei-promote-\(operationID.uuidString.lowercased())"
        )
        let previousItems = importedItems
        let previousMemberships = courseItemMemberships
        var sharedIdentity: ImportedFileIdentity?
        var workspaceCommitted = false

        do {
            let stagedIdentity = try await courseProjectFileWorker
                .copyAndVerify(
                    from: sourceURL,
                    generatedData: nil,
                    to: payloadURL,
                    expectedSnapshot: sourceSnapshot
                )
            let placedIdentity = try await courseProjectFileWorker
                .placeWithoutReplacement(
                    from: payloadURL,
                    to: targetURL,
                    courseRoot: libraryRoot,
                    destinationDirectory: commonDirectory,
                    expectedDestinationIdentity: commonDirectoryIdentity,
                    expectedSnapshot: sourceSnapshot
                )
            guard stagedIdentity == placedIdentity else {
                throw CourseOwnedFileError.verificationFailed
            }
            sharedIdentity = placedIdentity
            let targetInfo = try await courseProjectFileWorker.stableMetadata(
                at: targetURL,
                expectedIdentity: placedIdentity,
                expectedSnapshot: sourceSnapshot
            )
            guard let sharedRelativePath = CourseProjectPathPolicy
                .relativePath(of: targetURL, inside: libraryRoot) else {
                throw CourseOwnedFileError.unsafeCoursePath
            }

            importedItems[itemIndex].urlPath = targetURL.path
            importedItems[itemIndex].importedFileLastKnownPath =
                targetURL.path
            importedItems[itemIndex].importedFileIdentity = placedIdentity
            importedItems[itemIndex].importedFileBookmarkData = nil
            importedItems[itemIndex].storage = .shared(
                sharedRelativePath: sharedRelativePath
            )
            importedItems[itemIndex].subtitle = targetURL.lastPathComponent
            importedItems[itemIndex].fileByteCount = targetInfo.byteCount
            importedItems[itemIndex]
                .fileModificationTimeNanoseconds =
                targetInfo.modificationTimeNanoseconds
            courseItemMemberships.removeAll {
                $0.itemID == itemID && $0.courseID == ownerCourseID
            }
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            workspaceCommitted = true

            let cleanup = await courseProjectFileWorker
                .isolateAndRemoveVerifiedFile(
                    at: sourceURL,
                    quarantineURL: sourceURL.deletingLastPathComponent()
                        .appendingPathComponent(
                            ".\(sourceURL.lastPathComponent).weibei-promote-cleanup-\(operationID.uuidString.lowercased())"
                        ),
                    expectedIdentity: sourceInfo.identity,
                    expectedSnapshot: sourceSnapshot,
                    remover: courseFileSourceRemover
                )
            if case .removed = cleanup {
                noteFileError = nil
            } else {
                // ponytail: a crash here can leave one harmless old duplicate;
                // add a cleanup journal only if this becomes observable in use.
                noteFileError = ui(
                    "课程关系已移除，但课程文件夹中的旧副本未能清理。",
                    "The course relation was removed, but the old course copy could not be cleaned up."
                )
            }
            courseDocumentSearchIndex.schedule([importedItems[itemIndex]])
            invalidateAgentContext()
        } catch {
            if !workspaceCommitted {
                importedItems = previousItems
                courseItemMemberships = previousMemberships
                if let sharedIdentity {
                    _ = await courseProjectFileWorker
                        .isolateAndRemoveVerifiedFile(
                            at: targetURL,
                            quarantineURL: commonDirectory
                                .appendingPathComponent(
                                    ".\(targetURL.lastPathComponent).weibei-promote-rollback-\(operationID.uuidString.lowercased())"
                                ),
                            expectedIdentity: sharedIdentity,
                            expectedSnapshot: sourceSnapshot,
                            remover: { try FileManager.default.removeItem(at: $0) }
                        )
                } else if FileManager.default.fileExists(
                    atPath: payloadURL.path
                ) {
                    try? FileManager.default.removeItem(at: payloadURL)
                }
            }
            throw error
        }
    }

    func removeItem(_ itemID: String, fromCourseID courseID: UUID) {
        var memberships = Set(courseIDs(for: itemID))
        memberships.remove(courseID)
        setCourseIDs(memberships, for: itemID)
    }

    func setCourseIDs(_ courseIDs: Set<UUID>, for itemID: String) {
        guard let item = importedItems.first(where: { $0.id == itemID }) else { return }
        let validCourseIDs = Set(courses.map(\.id))
        let requested = courseIDs.intersection(validCourseIDs)
        let current = Set(self.courseIDs(for: itemID))
        guard requested.union(current).allSatisfy({
            activeCourseRemovalTokens[$0] == nil
        }) else {
            return
        }
        guard requested != current else { return }
        let added = requested.subtracting(current)
        let removed = current.subtracting(requested)

        if case .legacyExternal = item.storage,
           removed.isEmpty,
           let courseID = added.first,
           let sourceURL = item.url,
           confirmManagedCourseMove(
            sourceURL: sourceURL,
            courseID: courseID,
            role: item.isNotebookNote ? .note : .material,
            verb: ui("移入课程", "Move into Course")
           ) {
            let resolution = courseImportConflictResolution(
                sourceURL: sourceURL,
                courseID: courseID,
                role: item.isNotebookNote ? .note : .material
            )
            guard let resolution else { return }
            Task { @MainActor [weak self] in
                do {
                    _ = try await self?.migrateLegacyExternalItemIntoCourse(
                        itemID: itemID,
                        courseID: courseID,
                        conflictResolution: resolution
                    )
                } catch {
                    self?.noteFileError = error.localizedDescription
                }
            }
            return
        }
        if case .courseOwned(let ownerCourseID) = item.storage,
           added.count == 1,
           let courseID = added.first,
           let sourceURL = item.url {
            let movesOwnership = removed.contains(ownerCourseID)
            let role: CourseOwnedFileRole = item.isNotebookNote
                ? .note
                : .material
            let verb = movesOwnership
                ? ui("移到另一门课程", "Move to Another Course")
                : ui(
                    "转为\(role.commonDirectoryName)",
                    "Move to common content"
                )
            guard confirmManagedCourseMove(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                verb: verb
            ) else {
                return
            }
            let sharedConflictTarget = movesOwnership
                ? nil
                : courseLibraryRootURL?
                    .appendingPathComponent(
                        role.commonDirectoryName,
                        isDirectory: true
                    )
                    .appendingPathComponent(sourceURL.lastPathComponent)
            let resolution = courseImportConflictResolution(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                allowsReplace: movesOwnership,
                additionalProtectedTarget: sharedConflictTarget
            )
            guard let resolution else { return }
            Task { @MainActor [weak self] in
                do {
                    if movesOwnership {
                        _ = try await self?.moveCourseOwnedItem(
                            itemID: itemID,
                            toCourseID: courseID,
                            conflictResolution: resolution
                        )
                    } else {
                        try await self?.shareCourseOwnedItem(
                            itemID: itemID,
                            withCourseID: courseID,
                            conflictResolution: resolution
                        )
                    }
                } catch {
                    self?.noteFileError = error.localizedDescription
                }
            }
            return
        }
        if case .courseOwned(let ownerCourseID) = item.storage,
           added.isEmpty,
           removed == [ownerCourseID],
           let sourceURL = item.url,
           let libraryRoot = courseLibraryRootURL {
            let role: CourseOwnedFileRole = item.isNotebookNote
                ? .note
                : .material
            let commonTarget = libraryRoot
                .appendingPathComponent(
                    role.commonDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(sourceURL.lastPathComponent)
            guard confirmPromotionToCommon(
                sourceURL: sourceURL,
                targetURL: commonTarget
            ),
            let resolution = commonContentConflictResolution(
                sourceURL: sourceURL,
                targetURL: commonTarget
            ) else {
                return
            }
            Task { @MainActor [weak self] in
                do {
                    try await self?.promoteCourseOwnedItemToCommon(
                        itemID: itemID,
                        conflictResolution: resolution
                    )
                } catch {
                    self?.noteFileError = error.localizedDescription
                }
            }
            return
        }
        if case .shared = item.storage {
            let role: CourseOwnedFileRole = item.isNotebookNote
                ? .note
                : .material
            if let courseID = added.first,
               let sourceURL = item.url,
               confirmManagedCourseMove(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                verb: ui("加入另一门课程", "Add to Another Course")
               ),
               let resolution = courseImportConflictResolution(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                allowsReplace: false
               ) {
                Task { @MainActor [weak self] in
                    do {
                        try await self?.shareCourseOwnedItem(
                            itemID: itemID,
                            withCourseID: courseID,
                            conflictResolution: resolution
                        )
                    } catch {
                        self?.noteFileError = error.localizedDescription
                    }
                }
                return
            }
            if let courseID = removed.first {
                Task { @MainActor [weak self] in
                    do {
                        try await self?.removeSharedItem(
                            itemID: itemID,
                            fromCourseID: courseID
                        )
                    } catch {
                        self?.noteFileError = error.localizedDescription
                    }
                }
                return
            }
        }

        // Legacy virtual memberships may still be removed without touching files.
        guard case .legacyExternal = item.storage, added.isEmpty else { return }
        var memberships = courseMembershipIndex
        memberships.replaceCourses(for: itemID, courseIDs: requested)
        courseItemMemberships = memberships.values
        save()
    }

    private func confirmPromotionToCommon(
        sourceURL: URL,
        targetURL: URL
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = ui(
            "从本课程移除",
            "Remove from This Course"
        )
        alert.informativeText = ui(
            "原文件会先复制到通用目录，再解除课程关系。\n来源：\(sourceURL.path)\n目标：\(targetURL.path)",
            "The source will be copied to common content before its course relation is removed.\nSource: \(sourceURL.path)\nTarget: \(targetURL.path)"
        )
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("移除关系", "Remove Relation"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func commonContentConflictResolution(
        sourceURL: URL,
        targetURL: URL
    ) -> CourseFileConflictResolution? {
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return .cancel
        }
        let suggestedName = CourseKeepBothNaming.suggestedFileName(
            originalName: sourceURL.lastPathComponent,
            conflictingTargets: [targetURL]
        )
        let alert = NSAlert()
        alert.messageText = ui(
            "通用目录中已有同名文件",
            "A file with this name already exists"
        )
        alert.informativeText = "\(ui("冲突目标", "Conflicting target"))：\(targetURL.path)"
        let nameField = NSTextField(string: suggestedName)
        nameField.setAccessibilityLabel(ui("新文件名", "New file name"))
        nameField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = nameField
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("保留两份", "Keep Both"))
        guard alert.runModal() == .alertSecondButtonReturn else {
            return nil
        }
        let preferred = nameField.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return .keepBoth(
            preferredFileName: preferred.isEmpty ? suggestedName : preferred
        )
    }

    func confirmMoveItemSourceToTrash(_ itemID: String) {
        guard let item = importedItems.first(where: { $0.id == itemID }),
              !item.isSample,
              item.url != nil else {
            noteFileError = ContentSourceRemovalError.itemUnavailable
                .localizedDescription
            return
        }
        let affectedCourses = courseIDs(for: itemID).compactMap {
            course(withID: $0)?.title
        }
        let courseSummary = affectedCourses.isEmpty
            ? ui("没有课程关系", "No course relations")
            : affectedCourses.joined(separator: "、")
        let alert = NSAlert()
        alert.messageText = ui(
            "将原文件移到废纸篓？",
            "Move the Source File to Trash?"
        )
        alert.informativeText = ui(
            "这会移动唯一原文件，并从所有课程中移除。受影响课程：\(courseSummary)",
            "This moves the only source file and removes it from every course. Affected courses: \(courseSummary)"
        )
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("移到废纸篓", "Move to Trash"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task { @MainActor [weak self] in
            do {
                try await self?.moveItemSourceToTrash(itemID)
            } catch {
                self?.noteFileError = error.localizedDescription
            }
        }
    }

    private func moveItemSourceToTrash(_ itemID: String) async throws {
        if stagedNoteDraft?.itemID == itemID,
           let draft = stagedNoteDraft {
            stagedNoteDraft = nil
            updateNote(draft.value, for: itemID)
        }
        flushPendingNotePersistence(for: itemID)
        while let task = courseNoteWriteTasksByItemID[itemID] {
            await task.value
        }
        guard flushPendingWorkspaceSave(),
              let itemIndex = importedItems.firstIndex(where: {
                  $0.id == itemID
              }) else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        if case .legacyExternal = importedItems[itemIndex].storage {
            _ = resolveTrackedImportedFile(at: itemIndex)
        }
        guard let sourceURL = importedItems[itemIndex].url,
              let expectedIdentity = importedItems[itemIndex]
                .importedFileIdentity else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        let affectedCourseIDs = Set(courseIDs(for: itemID))
        let formerSharedLinks: [(url: URL, identity: ImportedFileIdentity)]
        if case .shared = importedItems[itemIndex].storage {
            formerSharedLinks = courseItemMemberships.compactMap {
                membership in
                guard membership.itemID == itemID,
                      let root = courseRootURL(
                        for: membership.courseID
                      ),
                      let relativePath = membership.courseRelativePath,
                      let linkURL = Self.backgroundRawRelativeURL(
                        relativePath,
                        inside: root
                      ),
                      let identity = membership.entryIdentity else {
                    return nil
                }
                return (linkURL, identity)
            }
        } else {
            formerSharedLinks = []
        }
        try beginCourseFileMutation(courseIDs: affectedCourseIDs)
        defer { finishCourseFileMutation(courseIDs: affectedCourseIDs) }

        let sourceSnapshot: CourseFileSnapshot
        do {
            sourceSnapshot = try await courseProjectFileWorker
                .stableSnapshot(
                    at: sourceURL,
                    expectedIdentity: expectedIdentity
                )
        } catch {
            throw ContentSourceRemovalError.sourceChanged
        }
        let trashMover = contentSourceTrashMover
        var movedTrashURL: URL?
        do {
            let trashURL = try await Task.detached(priority: .userInitiated) {
                try trashMover(sourceURL)
            }.value
            movedTrashURL = trashURL
            _ = try await courseProjectFileWorker.stableSnapshot(
                at: trashURL,
                expectedIdentity: expectedIdentity,
                expectedSnapshot: sourceSnapshot
            )
        } catch {
            if let movedTrashURL {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: movedTrashURL,
                    to: sourceURL
                )
            }
            throw ContentSourceRemovalError.trashMoveFailed
        }
        guard let trashURL = movedTrashURL else {
            throw ContentSourceRemovalError.trashMoveFailed
        }

        removeItemRegistration(itemID)
        guard await persistWorkspaceNow() else {
            _ = await courseProjectFileWorker.restoreIsolatedFile(
                from: trashURL,
                to: sourceURL
            )
            load()
            throw ContentSourceRemovalError.workspaceSaveFailed
        }

        await removeFormerSharedLinks(
            sourceURL: sourceURL,
            links: formerSharedLinks
        )
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
        noteFileError = nil
    }

    private func removeFormerSharedLinks(
        sourceURL: URL,
        links: [(url: URL, identity: ImportedFileIdentity)]
    ) async {
        for link in links {
            _ = await courseProjectFileWorker
                .isolateAndRemoveSymbolicLinkIfMatching(
                    at: link.url,
                    quarantineURL: link.url.deletingLastPathComponent()
                        .appendingPathComponent(
                            ".weibei-link-cleanup-\(UUID().uuidString.lowercased())"
                        ),
                    destinationURL: sourceURL,
                    expectedIdentity: link.identity
                )
        }
    }

    private func removeItemRegistration(_ itemID: String) {
        pendingNotePersistenceTasks.removeValue(forKey: itemID)?.cancel()
        courseNoteLoadTasksByItemID.removeValue(forKey: itemID)?.cancel()
        courseNoteWriteTasksByItemID.removeValue(forKey: itemID)?.cancel()
        pendingNotePersistenceByItemID.removeValue(forKey: itemID)
        courseNoteLoadGenerationByItemID.removeValue(forKey: itemID)
        courseNoteWritesInFlight.remove(itemID)
        notesByItemID.removeValue(forKey: itemID)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
        noteOperationErrorsByItemID.removeValue(forKey: itemID)
        noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
        loadedCourseNoteTextByItemID.removeValue(forKey: itemID)
        studyLocationsByItemID.removeValue(forKey: itemID)
        for courseKey in Array(studyLocationsByCourseID.keys) {
            studyLocationsByCourseID[courseKey]?.removeValue(
                forKey: itemID
            )
        }
        importedItems.removeAll { $0.id == itemID }
        courseItemMemberships.removeAll { $0.itemID == itemID }
        noteSourceLinks.removeAll {
            $0.noteItemID == itemID || $0.sourceItemID == itemID
        }
        materialNotePairings = materialNotePairings.filter {
            $0.key != itemID && $0.value != itemID
        }
        noteMaterialPairings = noteMaterialPairings.filter {
            $0.key != itemID && $0.value != itemID
        }
        for index in studySessions.indices {
            studySessions[index].focusItemIDs.removeAll { $0 == itemID }
            if studySessions[index].materialItemID == itemID {
                studySessions[index].materialItemID = nil
            }
        }
        for index in courseResumePoints.indices {
            if courseResumePoints[index].materialLocation?.itemID == itemID {
                courseResumePoints[index].materialLocation = nil
            }
            if courseResumePoints[index].noteItemID == itemID {
                courseResumePoints[index].noteItemID = nil
            }
        }
        selectionAskThreads.removeAll { $0.itemID == itemID }
        if activeSelectionAskThreadID.map({ id in
            !selectionAskThreads.contains { $0.id == id }
        }) == true {
            activeSelectionAskThreadID = nil
        }
        if selectionContext?.itemID == itemID { selectionContext = nil }
        selectionAttachments.removeAll { $0.itemID == itemID }
        backNavigationStack.removeAll {
            $0.selectedItemID == itemID || $0.activeNotebookItemID == itemID
        }
        forwardNavigationStack.removeAll {
            $0.selectedItemID == itemID || $0.activeNotebookItemID == itemID
        }
        if selectedItemID == itemID { selectedItemID = nil }
        if activeNotebookItemID == itemID {
            activeNotebookItemID = nil
            noteText = noteText(for: nil)
        }
        if courseWorkspaceTargetItemID == itemID {
            courseWorkspaceTargetItemID = nil
        }
        if stagedNoteDraft?.itemID == itemID { stagedNoteDraft = nil }
        if blankNoteDraftMaterialID == itemID {
            blankNoteDraftMaterialID = nil
            pendingBlankNoteText = ""
        }
    }

    private func confirmManagedCourseMove(
        sourceURL: URL,
        courseID: UUID,
        role: CourseOwnedFileRole,
        verb: String
    ) -> Bool {
        guard let root = courseRootURL(for: courseID) else { return false }
        let target = root
            .appendingPathComponent(role.directoryName, isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent)
        let alert = NSAlert()
        alert.messageText = verb
        alert.informativeText = "\(ui("来源", "Source"))：\(sourceURL.path)\n\(ui("目标", "Target"))：\(target.path)"
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: verb)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func removeSharedItem(
        itemID: String,
        fromCourseID courseID: UUID
    ) async throws {
        let affectedCourseIDs: Set<UUID> = [courseID]
        try beginCourseFileMutation(courseIDs: affectedCourseIDs)
        defer {
            finishCourseFileMutation(courseIDs: affectedCourseIDs)
        }
        guard let item = importedItems.first(where: { $0.id == itemID }),
              case .shared(let sharedRelativePath) = item.storage,
              let sharedURL = item.url,
              let sharedIdentity = item.importedFileIdentity,
              let root = courseRootURL(for: courseID),
              let membership = courseItemMemberships.first(where: {
                $0.courseID == courseID && $0.itemID == itemID
              }),
              let relativePath = membership.courseRelativePath,
              let linkURL = Self.backgroundRawRelativeURL(relativePath, inside: root),
              let linkIdentity = membership.entryIdentity else {
            return
        }
        let sharedSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sharedURL,
            expectedIdentity: sharedIdentity
        )
        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: root
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(
            transactionDirectory
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let journalURL = transactionDirectory.appendingPathComponent(
            "shared-link-removal.json"
        )
        let isolatedLinkURL = transactionDirectory.appendingPathComponent(
            "isolated-link"
        )
        var journal = PendingSharedLinkRemovalJournal(
            transactionID: transactionID,
            transactionDirectoryIdentity: transactionDirectoryIdentity,
            itemID: itemID,
            courseID: courseID,
            sharedPath: sharedURL.path,
            sharedRelativePath: sharedRelativePath,
            sharedIdentity: sharedIdentity,
            sharedSnapshot: sharedSnapshot,
            linkPath: linkURL.path,
            linkRelativePath: relativePath,
            linkIdentity: linkIdentity,
            stage: .prepared
        )
        try await courseProjectFileWorker.write(
            JSONEncoder().encode(journal),
            to: journalURL
        )
        let previous = courseItemMemberships
        do {
            try courseProjectMutationHook(.beforeSharedLinkIsolation)
            _ = try await courseProjectFileWorker.isolateSymbolicLinkIfMatching(
                at: linkURL,
                to: isolatedLinkURL,
                destinationURL: sharedURL,
                expectedIdentity: linkIdentity
            )
            try courseProjectMutationHook(
                .afterSharedLinkIsolationBeforeJournal
            )
            journal.stage = .linkIsolated
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
        } catch {
            if WeiBeiSafetyTestMode.isEnabled, error is CourseProjectSimulatedCrash {
                throw error
            }
            if CourseProjectFileWorker.identity(at: linkURL) == nil {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: isolatedLinkURL,
                    to: linkURL
                )
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            throw error
        }
        courseItemMemberships.removeAll {
            $0.courseID == courseID && $0.itemID == itemID
        }
        guard await persistWorkspaceNow() else {
            courseItemMemberships = previous
            if CourseProjectFileWorker.identity(at: linkURL) == nil {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: isolatedLinkURL,
                    to: linkURL
                )
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            return
        }
        do {
            try courseProjectMutationHook(
                .afterSharedLinkRemovalWorkspaceSaveBeforeJournal
            )
            journal.stage = .workspaceCommitted
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            guard await courseProjectFileWorker
                .isolateAndRemoveSymbolicLinkIfMatching(
                at: isolatedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "isolated-link-cleanup"
                ),
                destinationURL: sharedURL,
                expectedIdentity: linkIdentity
            ) else {
                throw CourseOwnedFileError.verificationFailed
            }
        } catch {
            if WeiBeiSafetyTestMode.isEnabled, error is CourseProjectSimulatedCrash {
                throw error
            }
            courseItemMemberships = previous
            if await persistWorkspaceNow(),
               CourseProjectFileWorker.identity(at: linkURL) == nil {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: isolatedLinkURL,
                    to: linkURL
                )
            }
            if CourseProjectFileWorker.identity(at: isolatedLinkURL) == nil {
                await safelyRemoveSharedTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
            }
            throw error
        }
        await safelyRemoveSharedTransactionDirectoryInBackground(
            transactionDirectory,
            expectedIdentity: transactionDirectoryIdentity
        )
        invalidateAgentContext()
    }

    func removeSharedItemForSelfCheck(
        itemID: String,
        fromCourseID courseID: UUID
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        try waitForCourseFileOperation {
            try await self.removeSharedItem(itemID: itemID, fromCourseID: courseID)
        }
    }

    func promoteCourseOwnedItemToCommonForSelfCheck(
        itemID: String,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try waitForCourseFileOperation {
            try await self.promoteCourseOwnedItemToCommon(
                itemID: itemID,
                conflictResolution: conflictResolution
            )
        }
    }

    func moveItemSourceToTrashForSelfCheck(_ itemID: String) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try waitForCourseFileOperation {
            try await self.moveItemSourceToTrash(itemID)
        }
    }

    func installRootlessCourseForSelfCheck(title: String) -> UUID {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let course = Course(
            title: title,
            colorIndex: nextCourseColorIndex()
        )
        courses.append(course)
        courseKnowledgeProfiles.append(
            CourseKnowledgeProfile(courseID: course.id)
        )
        activeCourseID = course.id
        save()
        return course.id
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

    /// Non-empty Chats that have actually used this course.
    func sessionsTouchingCourse(_ courseID: UUID) -> [StudySession] {
        orderedStudySessions.filter {
            !$0.messages.isEmpty
                && $0.relatedCourseIDs.contains(courseID)
        }
    }

    func searchCourseHome(
        courseID: UUID,
        query rawQuery: String
    ) async -> CourseHomeSearchOutcome {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              courses.contains(where: { $0.id == courseID }) else {
            return CourseHomeSearchOutcome(results: [], availability: .ready)
        }
        let itemInputs = courseItems(in: courseID).map { item in
            (
                item: item,
                title: displayTitle(for: item),
                detail: displaySubtitle(for: item),
                memoryText: item.isNotebookNote
                    ? (item.id == activeNotebookItemID
                        ? noteText
                        : notesByItemID[item.id] ?? loadedCourseNoteTextByItemID[item.id])
                    : nil
            )
        }
        let sessions = sessionsTouchingCourse(courseID)
        let searchIndex = courseDocumentSearchIndex
        let chatDetail = ui("%d 条消息", "%d messages")
        let searchTask = Task.detached(priority: .userInitiated) {
            let ranOnMainThread = pthread_main_np() != 0
            let indexedItems = itemInputs.compactMap {
                $0.memoryText == nil ? $0.item : nil
            }
            let indexed = searchIndex.lookup(
                items: indexedItems,
                query: query,
                maximumCharactersPerItem: 1_200
            )
            let availability: CourseDocumentIndexAvailability
            if indexedItems.contains(where: {
                indexed[$0.id]?.availability == .unavailable
                    || indexed[$0.id] == nil
            }) {
                availability = .unavailable
            } else if indexedItems.contains(where: {
                indexed[$0.id]?.availability == .indexing
            }) {
                availability = .indexing
            } else {
                availability = .ready
            }
            func snippet(_ text: String?) -> String? {
                guard let text else { return nil }
                let compact = text
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                guard !compact.isEmpty else { return nil }
                return String(compact.prefix(150))
            }

            var scored: [(score: Int, result: CourseHomeSearchResult)] = []
            for input in itemInputs {
                guard !Task.isCancelled else {
                    return (
                        results: [CourseHomeSearchResult](),
                        availability: CourseDocumentIndexAvailability.ready,
                        ranOnMainThread: ranOnMainThread
                    )
                }
                let titleMatches = input.title.localizedCaseInsensitiveContains(query)
                let detailMatches = input.detail.localizedCaseInsensitiveContains(query)
                let bodyMatch: String?
                if let memoryText = input.memoryText {
                    bodyMatch = memoryText.localizedCaseInsensitiveContains(query)
                        ? snippet(memoryText)
                        : nil
                } else {
                    bodyMatch = snippet(indexed[input.item.id]?.text)
                }
                guard titleMatches || detailMatches || bodyMatch != nil else { continue }
                let kind: CourseHomeSearchResultKind = input.item.isNotebookNote
                    ? .note
                    : .material
                scored.append((
                    titleMatches ? 0 : (detailMatches ? 1 : 2),
                    CourseHomeSearchResult(
                        id: "\(kind.rawValue):\(input.item.id)",
                        kind: kind,
                        itemID: input.item.id,
                        sessionID: nil,
                        title: input.title,
                        detail: input.detail,
                        matchedText: bodyMatch
                    )
                ))
            }

            for session in sessions {
                guard !Task.isCancelled else {
                    return (
                        results: [CourseHomeSearchResult](),
                        availability: CourseDocumentIndexAvailability.ready,
                        ranOnMainThread: ranOnMainThread
                    )
                }
                let titleMatches = session.title.localizedCaseInsensitiveContains(query)
                let summaryMatches = session.summary.localizedCaseInsensitiveContains(query)
                let matchingMessage = session.messages.first {
                    $0.text.localizedCaseInsensitiveContains(query)
                }?.text
                guard titleMatches || summaryMatches || matchingMessage != nil else { continue }
                let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                scored.append((
                    titleMatches ? 0 : (summaryMatches ? 1 : 2),
                    CourseHomeSearchResult(
                        id: "chat:\(session.id.uuidString)",
                        kind: .chat,
                        itemID: nil,
                        sessionID: session.id,
                        title: session.title,
                        detail: summary.isEmpty
                            ? String(format: chatDetail, session.messages.count)
                            : String(summary.prefix(150)),
                        matchedText: snippet(matchingMessage)
                    )
                ))
            }
            return (
                results: scored
                .sorted {
                    $0.score == $1.score
                        ? $0.result.title.localizedStandardCompare($1.result.title)
                            == .orderedAscending
                        : $0.score < $1.score
                }
                .prefix(50)
                .map(\.result),
                availability: availability,
                ranOnMainThread: ranOnMainThread
            )
        }
        let search = await withTaskCancellationHandler {
            await searchTask.value
        } onCancel: {
            searchTask.cancel()
        }
        guard !Task.isCancelled else {
            return CourseHomeSearchOutcome(results: [], availability: .ready)
        }
        lastCourseHomeSearchRanOnMainThread = search.ranOnMainThread
        return CourseHomeSearchOutcome(
            results: search.results,
            availability: search.availability
        )
    }

    /// Sessions that reference a specific material (and optionally other focus items).
    func sessionsTouchingMaterial(_ materialID: String, in courseID: UUID? = nil) -> [StudySession] {
        return orderedStudySessions.filter { session in
            guard !session.messages.isEmpty else { return false }
            if let courseID {
                guard session.relatedCourseIDs.contains(courseID) else { return false }
            }
            let touches = session.materialItemID == materialID
                || session.groupingMaterialItemID == materialID
                || session.focusItemIDs.contains(materialID)
            return touches
        }
    }

    /// Compatibility for older call sites that need one preferred related course.
    func primaryCourseID(for session: StudySession) -> UUID? {
        session.relatedCourseIDs.first {
            courseID in courses.contains { $0.id == courseID }
        }
    }

    var activeCourseMemories: [LearningMemoryEntry] {
        guard let activeCourseID else { return [] }
        return orderedLearningMemoryEntries(in: .course(activeCourseID))
            .filter { $0.status == .active }
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
            learningMemoryEntries: activeCourseMemories
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
        studyLocation(for: itemID, in: activeCourseID)
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

    func contextualBrowserItems(
        _ kind: ContextualContentKind,
        courseID: UUID?
    ) -> [StudyItem] {
        allItems.filter { item in
            guard item.isNotebookNote == (kind == .note) else {
                return false
            }
            if let courseID {
                return courseMembershipIndex.courseIDs(for: item.id)
                    .contains(courseID)
            }
            switch item.storage {
            case .shared:
                return true
            case .legacyExternal:
                return courseMembershipIndex.courseIDs(for: item.id).isEmpty
            case .courseOwned, .bundledSample:
                return false
            }
        }.sorted {
            displayTitle(for: $0).localizedStandardCompare(
                displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    func contextualBrowserCourses(
        _ kind: ContextualContentKind
    ) -> [Course] {
        courses.filter {
            !contextualBrowserItems(kind, courseID: $0.id).isEmpty
        }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func contextualPreferredItems(
        _ kind: ContextualContentKind
    ) -> [StudyItem] {
        switch kind {
        case .note:
            guard let materialID = selectedMaterialItem?.id else { return [] }
            let ids = linkedNoteIDs(for: materialID)
            return ids.compactMap { item(withID: $0) }
        case .material:
            guard let noteID = activeNoteItem?.id else { return [] }
            let ids = linkedSourceIDs(for: noteID)
            if !ids.isEmpty {
                return ids.compactMap { item(withID: $0) }
            }
            let courseIDs = courseMembershipIndex.courseIDs(for: noteID)
            guard courseIDs.count == 1, let courseID = courseIDs.first else {
                return []
            }
            return contextualBrowserItems(.material, courseID: courseID)
        }
    }

    func contextualPreferredCourses(
        _ kind: ContextualContentKind
    ) -> [Course] {
        guard kind == .material,
              let noteID = activeNoteItem?.id,
              linkedSourceIDs(for: noteID).isEmpty else {
            return []
        }
        let courseIDs = Set(courseMembershipIndex.courseIDs(for: noteID))
        guard courseIDs.count > 1 else { return [] }
        return courses.filter {
            courseIDs.contains($0.id)
                && !contextualBrowserItems(.material, courseID: $0.id).isEmpty
        }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func openContextualItem(
        _ itemID: String,
        kind: ContextualContentKind
    ) {
        guard let item = item(withID: itemID),
              item.isNotebookNote == (kind == .note) else {
            return
        }
        switch kind {
        case .material:
            let noteID = activeNoteItem?.id
            select(itemID: itemID)
            showReader = true
            if let noteID {
                rememberMaterialNotePair(
                    materialID: itemID,
                    noteID: noteID
                )
            }
            focus(.reader)
        case .note:
            let materialID = selectedMaterialItem?.id
            select(itemID: itemID)
            showNotes = true
            if let materialID {
                rememberMaterialNotePair(
                    materialID: materialID,
                    noteID: itemID
                )
            }
            focus(.notes)
        }
    }

    private func rememberMaterialNotePair(
        materialID: String,
        noteID: String
    ) {
        guard item(withID: materialID)?.isNotebookNote == false,
              item(withID: noteID)?.isNotebookNote == true else {
            return
        }
        guard materialNotePairings[materialID] != noteID
                || noteMaterialPairings[noteID] != materialID else {
            return
        }
        materialNotePairings[materialID] = noteID
        noteMaterialPairings[noteID] = materialID
        save()
    }

    func prepareNoteForOpening() {
        guard let material = selectedMaterialItem else { return }
        if let noteID = materialNotePairings[material.id],
           item(withID: noteID)?.isNotebookNote == true {
            openContextualItem(noteID, kind: .note)
            return
        }
        let linked = linkedNoteIDs(for: material.id).filter {
            item(withID: $0)?.isNotebookNote == true
        }
        if linked.count == 1, let noteID = linked.first {
            openContextualItem(noteID, kind: .note)
        } else if linked.isEmpty {
            beginBlankNoteDraft(for: material.id)
        } else {
            blankNoteDraftMaterialID = nil
            activeNotebookItemID = nil
            noteText = ""
        }
    }

    func prepareMaterialForOpening() {
        guard let note = activeNoteItem else { return }
        if let materialID = noteMaterialPairings[note.id],
           item(withID: materialID)?.isNotebookNote == false {
            openContextualItem(materialID, kind: .material)
            return
        }
        let linked = linkedSourceIDs(for: note.id).filter {
            item(withID: $0)?.isNotebookNote == false
        }
        let candidates = linked.isEmpty
            ? courseMembershipIndex.courseIDs(for: note.id).flatMap { courseID in
                courseMaterials(in: courseID).map(\.id)
            }
            : linked
        let uniqueCandidates = Array(Set(candidates))
        if uniqueCandidates.count == 1, let materialID = uniqueCandidates.first {
            openContextualItem(materialID, kind: .material)
        } else {
            selectedItemID = nil
        }
    }

    private func beginBlankNoteDraft(for materialID: String) {
        guard item(withID: materialID)?.isNotebookNote == false else { return }
        persistCurrentNote()
        blankNoteMaterializationTask?.cancel()
        blankNoteMaterializationTask = nil
        blankNoteDraftMaterialID = materialID
        pendingBlankNoteText = ""
        activeNotebookItemID = nil
        noteText = ""
        focus(.notes)
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

    var historicalStudySessions: [StudySession] {
        orderedStudySessions.filter { !$0.messages.isEmpty }
    }

    var globalStudySessions: [StudySession] {
        historicalStudySessions
    }

    func studySessions(in courseID: UUID) -> [StudySession] {
        historicalStudySessions.filter {
            $0.relatedCourseIDs.contains(courseID)
        }
    }

    var unclassifiedStudySessions: [StudySession] {
        []
    }

    func learningMemoryKindLabel(_ kind: LearningMemoryKind) -> String {
        switch kind {
        case .goal: ui("目标", "Goal")
        case .progress: ui("学习进度", "Progress")
        case .understood: ui("已理解", "Understood")
        case .confusion: ui("困惑", "Confusion")
        case .nextStep: ui("下一步", "Next Step")
        case .summary: ui("学习小结", "Summary")
        case .preference: ui("偏好", "Preference")
        }
    }

    var activeStudySessionTitle: String {
        activeStudySession?.title ?? ui("新学习会话", "New Study Session")
    }

    var activeStudySessionScopeTitle: String {
        activeStudySession?.title ?? ui("新对话", "New Chat")
    }

    var lastStudyLocation: StudyLocation? {
        studyLocationsByItemID.values.max { $0.lastStudiedAt < $1.lastStudiedAt }
    }

    var canResumePreviousStudy: Bool {
        lastStudyLocation != nil
    }

    @discardableResult
    func createStudySession(courseID: UUID?) -> StudySession? {
        if let freshlyCreatedEmptyStudySessionID,
           let session = studySessions.first(where: {
               $0.id == freshlyCreatedEmptyStudySessionID && $0.messages.isEmpty
           }) {
            activeStudySessionID = session.id
            messages = []
            agentDraft = ""
            agentDraftsBySessionID[session.id] = ""
            return session
        }
        dismissAgentSwitchConfirmation()
        saveActiveAgentDraft()
        syncActiveStudySession()
        let session = StudySession(
            title: ui("新对话", "New Chat")
        )
        studySessions.append(session)
        activeStudySessionID = session.id
        freshlyCreatedEmptyStudySessionID = session.id
        messages = []
        agentDraft = ""
        restoreAgentReplyState(from: session)
        lastAgentReplyContextRevision = nil
        invalidateAgentContext()
        save()
        return session
    }

    @discardableResult
    func activateStudySession(
        _ id: UUID,
        expectedCourseID: UUID?,
        expectedScopeNeedsReview: Bool
    ) -> Bool {
        guard let session = studySessions.first(where: { $0.id == id }) else {
            return false
        }
        guard id != activeStudySessionID else { return true }
        dismissAgentSwitchConfirmation()
        saveActiveAgentDraft()
        syncActiveStudySession()
        if let blankID = freshlyCreatedEmptyStudySessionID,
           blankID != id,
           studySessions.first(where: { $0.id == blankID })?.messages.isEmpty == true {
            studySessions.removeAll { $0.id == blankID }
            agentDraftsBySessionID.removeValue(forKey: blankID)
        }
        freshlyCreatedEmptyStudySessionID = nil
        activeStudySessionID = id
        messages = session.messages
        restoreAgentDraft(for: id)
        restoreAgentReplyState(from: session)
        lastAgentReplyContextRevision = nil
        invalidateAgentContext()
        for courseID in session.relatedCourseIDs where !session.messages.isEmpty {
            _ = captureCourseResumePoint(courseID: courseID, chatID: id)
        }
        save()
        return true
    }

    @discardableResult
    func classifyStudySession(_ id: UUID, as courseID: UUID?) -> Bool {
        guard let index = studySessions.firstIndex(where: { $0.id == id }) else {
            return false
        }
        if let courseID,
           courses.contains(where: { $0.id == courseID }),
           !studySessions[index].relatedCourseIDs.contains(courseID) {
            studySessions[index].relatedCourseIDs.append(courseID)
            studySessions[index].relatedCourseIDs.sort { $0.uuidString < $1.uuidString }
        }
        save()
        return true
    }

    func associateStudySession(_ id: UUID, with courseIDs: some Sequence<UUID>) {
        guard let index = studySessions.firstIndex(where: { $0.id == id }) else { return }
        let validCourseIDs = Set(courses.map(\.id))
        let additions = Set(courseIDs).intersection(validCourseIDs)
        let next = Set(studySessions[index].relatedCourseIDs).union(additions)
        guard next.count != studySessions[index].relatedCourseIDs.count else { return }
        studySessions[index].relatedCourseIDs = next.sorted { $0.uuidString < $1.uuidString }
        save()
    }

    func associateStudySession(_ id: UUID, withItemIDs itemIDs: some Sequence<String>) {
        associateStudySession(
            id,
            with: itemIDs.flatMap { courseMembershipIndex.courseIDs(for: $0) }
        )
    }

    func deleteStudySession(_ id: UUID) {
        guard let index = studySessions.firstIndex(where: { $0.id == id }) else {
            return
        }
        let deletingActiveSession = activeStudySessionID == id
        if activeAgentReplyChatID == id {
            cancelAgentRequest(restoreDraft: false)
        }
        if freshlyCreatedEmptyStudySessionID == id {
            freshlyCreatedEmptyStudySessionID = nil
        }
        agentDraftsBySessionID.removeValue(forKey: id)
        studySessions.remove(at: index)
        let runtime = piRuntime
        Task { @MainActor [weak self] in
            do {
                try await runtime.deleteSession(id)
            } catch {
                self?.workspaceSaveError = self?.ui(
                    "Chat 已删除，但对应的 Pi 运行状态清理失败：\(error.localizedDescription)",
                    "The Chat was deleted, but its Pi runtime state could not be removed: \(error.localizedDescription)"
                )
            }
        }
        if deletingActiveSession {
            activeStudySessionID = nil
            messages = []
            if let replacement = orderedStudySessions.first {
                activeStudySessionID = replacement.id
                messages = replacement.messages
                restoreAgentDraft(for: replacement.id)
                restoreAgentReplyState(from: replacement)
            } else {
                ensureActiveStudySession()
            }
            lastAgentReplyContextRevision = nil
            invalidateAgentContext(restoreAgentDraft: false)
        }
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

    private func ensureActiveStudySession(preferFresh: Bool = false) {
        if !preferFresh,
           let activeStudySessionID,
           let session = studySessions.first(where: { $0.id == activeStudySessionID }) {
            messages = session.messages
            restoreAgentReplyState(from: session)
            return
        }
        if !preferFresh, let session = orderedStudySessions.first {
            activeStudySessionID = session.id
            messages = session.messages
            restoreAgentReplyState(from: session)
            return
        }
        let session = StudySession(title: ui("新学习会话", "New Study Session"))
        studySessions.append(session)
        activeStudySessionID = session.id
        freshlyCreatedEmptyStudySessionID = session.id
        messages = []
        restoreAgentReplyState(from: session)
    }

    private func resetPrimaryEntriesForLaunch() {
        selectedItemID = nil
        activeNotebookItemID = nil
        activeStudySessionID = nil
        activeCourseID = nil
        noteText = ""
        messages = []
        agentDraft = ""
        blankNoteDraftMaterialID = nil
        pendingBlankNoteText = ""
        showLibrary = false
        showReader = false
        showAgent = false
        showNotes = false
        showReaderSearch = false
        readerSearch = ""
        layout = .documentAgentNotes
        threePaneOrder = WorkspacePaneRole.defaultThreePaneOrder
        agentSurface = .hidden
        selectionContext = nil
        selectionAttachments = []
    }

    private func appendAgentMessage(_ message: AgentMessage) {
        if freshlyCreatedEmptyStudySessionID == activeStudySessionID {
            freshlyCreatedEmptyStudySessionID = nil
        }
        messages.append(message)
        syncActiveStudySession(titleSeed: message.role == .user ? message.text : nil)
        save()
    }

    @discardableResult
    private func updateAgentMessage(
        _ messageID: UUID,
        in chatID: UUID,
        _ update: (inout AgentMessage) -> Void
    ) -> AgentMessage? {
        guard let sessionIndex = studySessions.firstIndex(where: { $0.id == chatID }),
              let messageIndex = studySessions[sessionIndex].messages.firstIndex(where: {
                  $0.id == messageID && $0.role == .assistant
              }) else { return nil }
        update(&studySessions[sessionIndex].messages[messageIndex])
        studySessions[sessionIndex].updatedAt = Date()
        let updated = studySessions[sessionIndex].messages[messageIndex]
        if activeStudySessionID == chatID {
            messages = studySessions[sessionIndex].messages
        }
        save()
        return updated
    }

    private func restoreAgentReplyState(from session: StudySession) {
        guard let reply = session.messages.last(where: { $0.role == .assistant }) else {
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            lastFailedAgentQuestion = nil
            lastAgentFailureKind = nil
            return
        }
        latestAgentNoteProposal = reply.actions
            .last(where: { $0.kind == .writeNote && $0.state == .pending })
            .flatMap(Self.noteProposal)
        latestAgentLearningUpdate = nil
        lastFailedAgentQuestion = reply.retryQuestion
        lastAgentFailureKind = reply.failureKind
    }

    private func saveActiveAgentDraft() {
        guard let activeStudySessionID else { return }
        agentDraftsBySessionID[activeStudySessionID] = agentDraft
    }

    private func restoreAgentDraft(for sessionID: UUID) {
        agentDraft = agentDraftsBySessionID[sessionID] ?? ""
    }

    private static func noteProposal(from action: AgentReplyAction) -> StudyAgentNoteProposal? {
        guard action.kind == .writeNote,
              let markdown = action.proposedMarkdown,
              let contextRevision = action.contextRevision else { return nil }
        return StudyAgentNoteProposal(
            markdown: markdown,
            evidence: action.evidence,
            contextRevision: contextRevision
        )
    }

    private var agentReplyActionIDsInFlight = Set<UUID>()

    private func agentReplyAction(
        messageID: UUID,
        actionID: UUID
    ) -> (chatID: UUID, courseID: UUID?, action: AgentReplyAction)? {
        for session in studySessions {
            guard let message = session.messages.first(where: {
                $0.id == messageID && $0.role == .assistant
            }), let action = message.actions.first(where: { $0.id == actionID }) else {
                continue
            }
            guard message.origin?.chatID == nil || message.origin?.chatID == session.id,
                  message.origin?.courseID.map(
                    session.relatedCourseIDs.contains
                  ) != false else {
                return nil
            }
            return (session.id, message.origin?.courseID, action)
        }
        return nil
    }

    private func updateAgentReplyAction(
        messageID: UUID,
        actionID: UUID,
        chatID: UUID,
        _ update: (inout AgentReplyAction) -> Void
    ) {
        _ = updateAgentMessage(messageID, in: chatID) {
            guard let index = $0.actions.firstIndex(where: { $0.id == actionID }) else { return }
            update(&$0.actions[index])
            $0.actions[index].updatedAt = Date()
        }
    }

    func agentReplyActionTargetTitle(_ action: AgentReplyAction) -> String? {
        action.targetItemID
            .flatMap { itemID in allItems.first(where: { $0.id == itemID }) }
            .map(displayTitle)
    }

    func agentReplyActionSourceTitle(_ action: AgentReplyAction) -> String? {
        action.sourceItemID
            .flatMap { itemID in allItems.first(where: { $0.id == itemID }) }
            .map(displayTitle)
    }

    func cancelAgentReplyAction(messageID: UUID, actionID: UUID) {
        guard let snapshot = agentReplyAction(messageID: messageID, actionID: actionID),
              snapshot.action.state == .pending
                || (snapshot.action.state == .failed
                    && snapshot.action.resultContentDigest == nil) else {
            return
        }
        updateAgentReplyAction(
            messageID: messageID,
            actionID: actionID,
            chatID: snapshot.chatID
        ) {
            $0.state = .cancelled
            $0.failureMessage = nil
        }
        guard flushPendingWorkspaceSave() else {
            failAgentReplyAction(
                messageID: messageID,
                actionID: actionID,
                chatID: snapshot.chatID,
                message: workspaceSaveError ?? ui(
                    "取消状态没有成功保存，可以重试。",
                    "The cancellation was not saved. You can retry."
                )
            )
            return
        }
    }

    func confirmAgentReplyAction(
        messageID: UUID,
        actionID: UUID,
        proposedMarkdown: String? = nil
    ) async {
        guard agentReplyActionIDsInFlight.insert(actionID).inserted else { return }
        defer { agentReplyActionIDsInFlight.remove(actionID) }
        guard let snapshot = agentReplyAction(messageID: messageID, actionID: actionID),
              snapshot.courseID.map({
                  activeCourseRemovalTokens[$0] == nil
              }) ?? true,
              snapshot.action.state == .pending || snapshot.action.state == .failed else {
            return
        }
        switch snapshot.action.kind {
        case .writeNote:
            await confirmAgentNoteAction(
                messageID: messageID,
                snapshot: snapshot,
                proposedMarkdown: proposedMarkdown
            )
        case .createRelation:
            confirmAgentRelationAction(messageID: messageID, snapshot: snapshot)
        }
    }

    func undoAgentReplyAction(messageID: UUID, actionID: UUID) async {
        guard agentReplyActionIDsInFlight.insert(actionID).inserted else { return }
        defer { agentReplyActionIDsInFlight.remove(actionID) }
        guard let snapshot = agentReplyAction(messageID: messageID, actionID: actionID),
              snapshot.courseID.map({
                  activeCourseRemovalTokens[$0] == nil
              }) ?? true,
              snapshot.action.state == .executed
                || (snapshot.action.state == .failed
                    && (snapshot.action.resultContentDigest != nil
                        || snapshot.action.createdRelationID != nil)) else {
            return
        }
        switch snapshot.action.kind {
        case .writeNote:
            await undoAgentNoteAction(messageID: messageID, snapshot: snapshot)
        case .createRelation:
            undoAgentRelationAction(messageID: messageID, snapshot: snapshot)
        }
    }

    private func confirmAgentNoteAction(
        messageID: UUID,
        snapshot: (chatID: UUID, courseID: UUID?, action: AgentReplyAction),
        proposedMarkdown: String?
    ) async {
        var action = snapshot.action
        let proposal = (proposedMarkdown ?? action.proposedMarkdown ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposal.isEmpty,
              let targetItemID = action.targetItemID,
              let target = allItems.first(where: {
                  $0.id == targetItemID && $0.isNotebookNote
              }),
              item(targetItemID, belongsTo: snapshot.courseID) else {
            failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "目标笔记已不存在或不属于这条 Chat 的课程。",
                    "The target note is missing or outside this Chat's course."
                )
            )
            return
        }
        do {
            let current = try await agentActionNoteMarkdown(target)
            let currentDigest = Self.noteContentDigest(Data(current.utf8))
            let result: String
            if action.resultContentDigest == currentDigest {
                result = current
            } else {
                if action.resultContentDigest != nil,
                   action.baselineContentDigest != currentDigest {
                    failAgentReplyAction(
                        messageID: messageID,
                        actionID: action.id,
                        chatID: snapshot.chatID,
                        message: ui(
                            "笔记在这次动作后又发生了变化。魏碑没有重复写入；请先核对当前内容。",
                            "The note changed after this action. WeiBei did not write it again."
                        )
                    )
                    return
                }
                guard action.state == .failed
                    || action.baselineContentDigest == nil
                    || action.baselineContentDigest == currentDigest else {
                    failAgentReplyAction(
                        messageID: messageID,
                        actionID: action.id,
                        chatID: snapshot.chatID,
                        message: ui(
                            "这份笔记在建议生成后已经变化。魏碑没有覆盖它；请核对后重试。",
                            "This note changed after the proposal was created. WeiBei did not overwrite it."
                        )
                    )
                    return
                }
                action.baselineContentDigest = currentDigest
                result = appendingAgentNoteProposal(proposal, to: current)
                action.resultContentDigest = Self.noteContentDigest(Data(result.utf8))
            }
            updateAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID
            ) {
                $0.proposedMarkdown = proposal
                $0.baselineContentDigest = action.baselineContentDigest
                $0.resultContentDigest = action.resultContentDigest
                $0.failureMessage = nil
            }
            guard await persistAgentActionNote(
                result,
                target: target,
                resultDigest: action.resultContentDigest
            ) else {
                failAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id,
                    chatID: snapshot.chatID,
                    message: noteFileError ?? workspaceSaveError ?? ui(
                        "笔记没有成功写入，建议内容已保留，可以重试。",
                        "The note was not written. The proposal was kept for retry."
                    )
                )
                return
            }
            updateAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID
            ) {
                $0.state = .executed
                $0.failureMessage = nil
            }
            guard flushPendingWorkspaceSave() else {
                failAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id,
                    chatID: snapshot.chatID,
                    message: workspaceSaveError ?? ui(
                        "笔记已写入，但动作状态没有成功保存；可以安全重试。",
                        "The note was written, but the action status was not saved."
                    )
                )
                return
            }
        } catch {
            failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "无法读取目标笔记：\(error.localizedDescription)",
                    "Could not read the target note: \(error.localizedDescription)"
                )
            )
        }
    }

    private func undoAgentNoteAction(
        messageID: UUID,
        snapshot: (chatID: UUID, courseID: UUID?, action: AgentReplyAction)
    ) async {
        let action = snapshot.action
        guard let targetItemID = action.targetItemID,
              let target = allItems.first(where: {
                  $0.id == targetItemID && $0.isNotebookNote
              }),
              item(targetItemID, belongsTo: snapshot.courseID),
              let resultDigest = action.resultContentDigest,
              let proposal = action.proposedMarkdown else {
            return
        }
        do {
            let current = try await agentActionNoteMarkdown(target)
            let currentDigest = Self.noteContentDigest(Data(current.utf8))
            if currentDigest == action.baselineContentDigest {
                updateAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id,
                    chatID: snapshot.chatID
                ) {
                    $0.state = .cancelled
                    $0.failureMessage = nil
                }
                guard flushPendingWorkspaceSave() else {
                    failAgentReplyAction(
                        messageID: messageID,
                        actionID: action.id,
                        chatID: snapshot.chatID,
                        message: workspaceSaveError ?? ui(
                            "笔记已恢复，但撤销状态没有成功保存；可以安全重试。",
                            "The note was restored, but the undo status was not saved."
                        )
                    )
                    return
                }
                return
            }
            guard currentDigest == resultDigest,
                  let restored = removingAgentNoteProposal(
                      proposal,
                      from: current,
                      baselineDigest: action.baselineContentDigest
                  ),
                  await persistAgentActionNote(
                    restored,
                    target: target,
                    resultDigest: Self.noteContentDigest(Data(restored.utf8))
                  ) else {
                failAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id,
                    chatID: snapshot.chatID,
                    message: ui(
                        "笔记在写入后又发生了变化，魏碑没有自动撤销。",
                        "The note changed after the write, so WeiBei did not undo it automatically."
                    )
                )
                return
            }
            updateAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID
            ) {
                $0.state = .cancelled
                $0.failureMessage = nil
            }
            guard flushPendingWorkspaceSave() else {
                failAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id,
                    chatID: snapshot.chatID,
                    message: workspaceSaveError ?? ui(
                        "笔记已恢复，但撤销状态没有成功保存；可以安全重试。",
                        "The note was restored, but the undo status was not saved."
                    )
                )
                return
            }
        } catch {
            failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "撤销时无法读取目标笔记：\(error.localizedDescription)",
                    "Could not read the note while undoing: \(error.localizedDescription)"
                )
            )
        }
    }

    private func confirmAgentRelationAction(
        messageID: UUID,
        snapshot: (chatID: UUID, courseID: UUID?, action: AgentReplyAction)
    ) {
        let action = snapshot.action
        guard let noteItemID = action.targetItemID,
              let sourceItemID = action.sourceItemID,
              let note = allItems.first(where: {
                  $0.id == noteItemID && $0.isNotebookNote
              }),
              let source = allItems.first(where: {
                  $0.id == sourceItemID && !$0.isNotebookNote
              }),
              relationItemsBelongToActionScope(
                  noteItemID: note.id,
                  sourceItemID: source.id,
                  courseID: snapshot.courseID
              ) else {
            failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "要关联的笔记或文稿已不存在，或不属于同一课程。",
                    "The note or material is missing or no longer belongs to the same course."
                )
            )
            return
        }
        if let existing = noteSourceLinks.first(where: {
            $0.noteItemID == note.id && $0.sourceItemID == source.id
        }) {
            guard existing.id == action.createdRelationID else {
                failAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id,
                    chatID: snapshot.chatID,
                    message: ui(
                        "这份笔记和文稿已经有关联，魏碑没有重复建立。",
                        "This note and material are already related."
                    )
                )
                return
            }
            updateAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID
            ) {
                $0.state = .executed
                $0.createdRelationID = existing.id
                $0.failureMessage = nil
            }
            guard flushPendingWorkspaceSave() else {
                failAgentReplyAction(
                    messageID: messageID,
                    actionID: action.id,
                    chatID: snapshot.chatID,
                    message: workspaceSaveError ?? ui(
                        "关系状态没有成功保存，可以重试。",
                        "The relation status was not saved. You can retry."
                    )
                )
                return
            }
            return
        }

        let relation = NoteSourceLink(
            id: action.id,
            noteItemID: note.id,
            sourceItemID: source.id
        )
        noteSourceLinks.append(relation)
        updateAgentReplyAction(
            messageID: messageID,
            actionID: action.id,
            chatID: snapshot.chatID
        ) {
            $0.state = .executed
            $0.createdRelationID = relation.id
            $0.failureMessage = nil
        }
        guard flushPendingWorkspaceSave() else {
            noteSourceLinks.removeAll { $0.id == relation.id }
            updateAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID
            ) {
                $0.createdRelationID = nil
            }
            failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: workspaceSaveError ?? ui(
                    "关系没有成功保存，可以重试。",
                    "The relation was not saved. You can retry."
                )
            )
            return
        }
        invalidateAgentContext()
    }

    private func undoAgentRelationAction(
        messageID: UUID,
        snapshot: (chatID: UUID, courseID: UUID?, action: AgentReplyAction)
    ) {
        let action = snapshot.action
        guard let relationID = action.createdRelationID,
              let relation = noteSourceLinks.first(where: { $0.id == relationID }) else {
            return
        }
        noteSourceLinks.removeAll { $0.id == relationID }
        updateAgentReplyAction(
            messageID: messageID,
            actionID: action.id,
            chatID: snapshot.chatID
        ) {
            $0.state = .cancelled
            $0.failureMessage = nil
        }
        guard flushPendingWorkspaceSave() else {
            noteSourceLinks.append(relation)
            failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: workspaceSaveError ?? ui(
                    "关系没有成功撤销，可以重试。",
                    "The relation was not undone. You can retry."
                )
            )
            return
        }
        invalidateAgentContext()
    }

    private func failAgentReplyAction(
        messageID: UUID,
        actionID: UUID,
        chatID: UUID,
        message: String
    ) {
        updateAgentReplyAction(
            messageID: messageID,
            actionID: actionID,
            chatID: chatID
        ) {
            $0.state = .failed
            $0.failureMessage = message
        }
        _ = flushPendingWorkspaceSave()
    }

    private func item(_ itemID: String, belongsTo courseID: UUID?) -> Bool {
        guard allItems.contains(where: { $0.id == itemID }) else { return false }
        guard let courseID else { return true }
        return courseMembershipIndex.courseIDs(for: itemID).contains(courseID)
    }

    private func relationItemsBelongToActionScope(
        noteItemID: String,
        sourceItemID: String,
        courseID: UUID?
    ) -> Bool {
        let noteCourses = Set(courseMembershipIndex.courseIDs(for: noteItemID))
        let sourceCourses = Set(courseMembershipIndex.courseIDs(for: sourceItemID))
        if let courseID {
            return noteCourses.contains(courseID) && sourceCourses.contains(courseID)
        }
        return !noteCourses.intersection(sourceCourses).isEmpty
    }

    private func agentActionNoteMarkdown(_ item: StudyItem) async throws -> String {
        if !item.editsBackingMarkdownFile, let pending = notesByItemID[item.id] {
            return cleanLegacyPlaceholder(pending)
        }
        if activeNoteItemID == item.id {
            return noteText
        }
        if let pending = notesByItemID[item.id] {
            return cleanLegacyPlaceholder(pending)
        }
        if let loaded = loadedCourseNoteTextByItemID[item.id] {
            return loaded
        }
        guard item.editsBackingMarkdownFile else {
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
        let url: URL
        let identity: ImportedFileIdentity
        let courseAccess: VerifiedCourseOwnedNoteAccess?
        if case .courseOwned = item.storage {
            guard let access = verifiedCourseOwnedNoteAccess(item) else {
                throw CourseOwnedFileError.verificationFailed
            }
            url = access.url
            identity = access.fileIdentity
            courseAccess = access
        } else {
            guard let itemURL = item.url,
                  let itemIdentity = item.importedFileIdentity else {
                return cleanLegacyPlaceholder(
                    notesByItemID[item.id] ?? defaultNote(for: item)
                )
            }
            url = itemURL
            identity = itemIdentity
            courseAccess = nil
        }
        let result = try await courseProjectFileWorker.readMarkdown(
            at: url,
            expectedIdentity: identity
        )
        if let courseAccess {
            guard let currentItem = importedItems.first(where: {
                $0.id == item.id
            }),
            let currentAccess =
                verifiedCourseOwnedNoteAccess(currentItem),
            currentAccess.matches(courseAccess) else {
                throw CourseOwnedFileError.verificationFailed
            }
        }
        return cleanLegacyPlaceholder(result.markdown)
    }

    private func appendingAgentNoteProposal(
        _ proposal: String,
        to current: String
    ) -> String {
        let block = noteBlockForAgentAnswer(proposal)
        guard !current.isEmpty else { return block }
        return current + (current.hasSuffix("\n") ? "\n" : "\n\n") + block
    }

    private func removingAgentNoteProposal(
        _ proposal: String,
        from current: String,
        baselineDigest: String?
    ) -> String? {
        let block = noteBlockForAgentAnswer(proposal)
        let suffixes = ["\n\n\(block)", "\n\(block)", block]
        let candidates = suffixes.compactMap { suffix -> String? in
            current.hasSuffix(suffix) ? String(current.dropLast(suffix.count)) : nil
        }
        if let baselineDigest,
           let exact = candidates.first(where: {
               Self.noteContentDigest(Data($0.utf8)) == baselineDigest
           }) {
            return exact
        }
        return candidates.first
    }

    private func persistAgentActionNote(
        _ markdown: String,
        target: StudyItem,
        resultDigest: String?
    ) async -> Bool {
        updateNote(markdown, for: target.id)
        flushPendingNotePersistence()
        if case .courseOwned = target.storage {
            while let task = courseNoteWriteTasksByItemID[target.id] {
                await task.value
            }
        }
        let notePersisted: Bool
        if target.editsBackingMarkdownFile {
            notePersisted = pendingNoteWritesByItemID[target.id] == nil
                && resultDigest != nil
                && noteBackingContentDigestsByItemID[target.id] == resultDigest
        } else {
            notePersisted = notesByItemID[target.id] == markdown
        }
        return notePersisted && flushPendingWorkspaceSave()
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
    }

    private func itemID(_ itemID: String, belongsTo session: StudySession) -> Bool {
        allItems.contains { $0.id == itemID }
    }

    private static func sessionTitle(from text: String) -> String {
        let title = text
            .replacingOccurrences(of: #"[`*_>#\[\]()]"#, with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return title.isEmpty ? "Study Session" : String(title.prefix(36))
    }

    private static func interruptedAgentReplyText(streamed: String, persisted: String) -> String {
        streamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? persisted
            : streamed
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
        guard selectedItem?.isNotebookNote == true else { return nil }
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
        return ""
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

    var effectiveReaderSearch: String {
        readerSourceHighlight.isEmpty ? readerSearch : readerSourceHighlight
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
        agentSelectionTitle(from: currentAgentSelections())
    }

    var agentSelectionText: String? {
        agentSelectionText(from: currentAgentSelections())
    }

    private func currentAgentSelections(
        allowedItemIDs: Set<String>? = nil
    ) -> [SelectionContext] {
        let selections = selectionAttachments.isEmpty
            ? [selectionContext].compactMap { $0 }
            : selectionAttachments
        return selections.filter { selection in
            guard !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            guard let allowedItemIDs else { return true }
            guard let itemID = selection.itemID else { return false }
            return allowedItemIDs.contains(itemID)
        }
    }

    private func agentSelectionTitle(from selections: [SelectionContext]) -> String? {
        guard !selections.isEmpty else { return nil }
        if selections.count == 1 {
            return selections[0].ownerTitle
        }
        return ui(
            "\(selections.count) 个已选文本片段",
            "\(selections.count) selected text fragments"
        )
    }

    private func agentSelectionText(from selections: [SelectionContext]) -> String? {
        guard !selections.isEmpty else { return nil }
        return selections.enumerated().map { index, selection in
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

    private func agentSelectionSources(
        from selections: [SelectionContext]
    ) -> [AgentReplySource] {
        return selections.compactMap { selection in
            let excerpt = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !excerpt.isEmpty else { return nil }
            let reference = SourceReferenceTitle.parse(selection.ownerTitle)
            return AgentReplySource(
                itemID: selection.itemID,
                kind: .selection,
                title: reference.title,
                label: "[选区：\(selection.ownerTitle)]",
                excerpt: String(excerpt.prefix(400)),
                pageIndex: reference.pageIndex,
                sectionTitle: reference.sectionTitle,
                sectionLocationID: reference.sectionLocationID,
                sectionOrdinal: reference.sectionOrdinal,
                courseItemOrdinal: reference.courseItemOrdinal
            )
        }
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
        isAgentRunningInActiveChat
            ? ui("停止回答", "Stop response")
            : ui("发送问题", "Send question")
    }

    var isAgentRunningInActiveChat: Bool {
        isAskingAgent && activeAgentReplyChatID == activeStudySessionID
    }

    var runningAgentChatTitle: String {
        guard let chatID = activeAgentReplyChatID,
              let session = studySessions.first(where: { $0.id == chatID }) else {
            return ui("另一条 Chat", "another Chat")
        }
        return session.title
    }

    var hasPersistedGeneratingAgentReply: Bool {
        messages.contains { $0.role == .assistant && $0.completionState == .generating }
    }

    func agentDisplayText(for message: AgentMessage) -> String {
        guard message.id == activeAgentReplyMessageID,
              message.completionState == .generating else {
            return message.text
        }
        return latestAgentStreamingText
    }

    func agentReplyDisplayedStreamingText(_ message: AgentMessage) -> Bool {
        agentReplyIDsThatDisplayedStreamingText.contains(message.id)
    }

    /// The UI draft stays transient while tokens arrive. Durability boundaries
    /// checkpoint its latest cumulative snapshot once, before the workspace is written.
    private func checkpointActiveAgentStreamingText() {
        guard let messageID = activeAgentReplyMessageID,
              let chatID = activeAgentReplyChatID,
              !latestAgentStreamingText.isEmpty,
              let message = studySessions.first(where: { $0.id == chatID })?
                .messages.first(where: { $0.id == messageID }),
              message.completionState == .generating,
              message.text != latestAgentStreamingText
        else { return }
        _ = updateAgentMessage(messageID, in: chatID) {
            $0.text = latestAgentStreamingText
            $0.backend = .pi
        }
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
        // Neutral, ChatGPT-like. Never steer toward a surface — the agent
        // already knows what is open; the placeholder should not lecture.
        ui("问点什么…", "Ask anything")
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

    var lastRegeneratableAgentReplyID: UUID? {
        guard !isAskingAgent,
              !isStoppingAgent,
              let reply = messages.last,
              reply.completionState == .completed,
              reply.isUsableAgentAnswer,
              messages.dropLast().last?.role == .user else { return nil }
        return reply.id
    }

    var canReplaceNoteSelection: Bool {
        canApplyAgentAnswer && selectionContext?.isReplaceableNoteSelection == true
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
        item.title
    }

    func displaySubtitle(for item: StudyItem) -> String {
        item.subtitle
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
        if case .courseOwned = item.storage {
            if let loaded = loadedCourseNoteTextByItemID[item.id] {
                return loaded
            }
            scheduleCourseNoteLoad(item)
            return ""
        }
        if item.editsBackingMarkdownFile, let url = item.url {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return ""
    }

    private func loadedAgentNoteText(for item: StudyItem) -> String? {
        guard item.isNotebookNote else { return nil }
        if item.id == activeNoteItemID {
            return noteText
        }
        return notesByItemID[item.id] ?? loadedCourseNoteTextByItemID[item.id]
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
            blankNoteMaterializationTask?.cancel()
            blankNoteMaterializationTask = nil
            blankNoteDraftMaterialID = nil
            activeNotebookItemID = item.id
            noteText = noteText(for: item)
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            if !isRestoringCourseResumePoint {
                syncActiveStudySession()
            }
            revealRichWritingSurface()
            focus(.notes)
            if let activeCourseID,
               courseMembershipIndex.courseIDs(for: item.id).contains(activeCourseID) {
                _ = captureCourseResumePoint(
                    courseID: activeCourseID,
                    noteItemID: item.id
                )
            }
            save()
            return
        }
        let itemChanged = selectedItemID != itemID
        if itemChanged && selectedItemID != nil {
            recordNavigationPoint()
        }
        selectedItemID = itemID
        if let blankMaterialID = blankNoteDraftMaterialID,
           blankMaterialID != itemID {
            blankNoteMaterializationTask?.cancel()
            blankNoteMaterializationTask = nil
            blankNoteDraftMaterialID = nil
        }
        if itemChanged {
            clearUnpinnedFloatingSelection(keepContext: false)
            selectionAttachments = []
            lastSelectionAttachmentDate = nil
            readerSourceHighlight = ""
            readerSourceHighlightPageIndex = nil
            readerPageIndex = 0
            readerLocationID = nil
            requestReaderPDFPage(nil, recordsLocation: false)
            readerTargetLocationID = nil
            readerTargetLocationTitle = nil
        }
        if itemChanged {
            readerLocationTitle = selectedMaterialItem.map(displayTitle)
            restoreCurrentStudyLocation()
        } else if let item = selectedMaterialItem,
                  courseMembershipIndex.courseIDs(for: item.id).count > 1 {
            restoreCurrentStudyLocation()
        } else if readerLocationTitle == nil {
            readerLocationTitle = selectedMaterialItem.map(displayTitle)
        }
        clearReaderSearchIfNeeded()
        noteText = noteText(for: activeNoteItem)
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        if !isRestoringCourseResumePoint {
            syncActiveStudySession()
        }
        recordCurrentStudyLocation(incrementVisit: itemChanged)
        save()
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
        if destination == .hub {
            if let courseHomePerformanceNavigationSpan {
                WeiBeiPerf.end(
                    courseHomePerformanceNavigationSpan,
                    extra: "outcome=superseded"
                )
            }
            courseHomePerformanceNavigationSpan = WeiBeiPerf.begin(
                "navigation.course_home_to_next_main_queue_proxy"
            )
        }
        persistCurrentNote()
        let requestedCourseID = courseID
            ?? courseWorkspaceCourseID
            ?? activeCourseID
            ?? courses.first?.id
        selectCourseWorkspaceCourse(requestedCourseID)
        courseWorkspaceReturnFocus = focusedPane
        courseWorkspaceDestination = destination
        courseWorkspaceTargetItemID = itemID
        courseWorkspacePresented = true
    }

    func finishCourseHomePerformanceNavigation() {
        guard let courseHomePerformanceNavigationSpan else { return }
        self.courseHomePerformanceNavigationSpan = nil
        WeiBeiPerf.end(
            courseHomePerformanceNavigationSpan,
            extra: "outcome=completed endpoint=next_main_queue_proxy"
        )
    }

    /// Sidebar / create-course entry into the course hub for a specific course.
    func openCourseSpace(_ courseID: UUID) {
        guard courses.contains(where: { $0.id == courseID }) else { return }
        showLibrary = false
        presentCourseWorkspace(.hub, courseID: courseID)
    }

    /// The course surface always moves real files through the recoverable course transaction.
    func importCourseFilesFromURLs(
        _ urls: [URL],
        asNotes: Bool = false,
        courseID requestedCourseID: UUID? = nil,
        completion: @escaping ([StudyItem]) -> Void = { _ in }
    ) {
        guard let courseID = requestedCourseID ?? courseWorkspaceCourseID ?? activeCourseID,
              courses.contains(where: { $0.id == courseID }) else {
            completion([])
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let expanded = await courseProjectFileWorker.expandedSupportedFiles(
                from: urls,
                markdownOnly: asNotes
            )
            guard !expanded.isEmpty,
                  confirmCourseImportPlan(
                    expanded,
                    courseID: courseID,
                    asNotes: asNotes
                  ) else {
                completion([])
                return
            }
            var imported: [StudyItem] = []
            for (offset, sourceURL) in expanded.enumerated() {
                let role: CourseOwnedFileRole = asNotes ? .note : .material
                guard let resolution = courseImportConflictResolution(
                    sourceURL: sourceURL,
                    courseID: courseID,
                    role: role
                ) else {
                    continue
                }
                courseFileOperationProgress = CourseFileOperationProgress(
                    completed: offset,
                    total: expanded.count,
                    currentFileName: sourceURL.lastPathComponent
                )
                do {
                    let result = try await importFileIntoCourse(
                        sourceURL,
                        courseID: courseID,
                        role: role,
                        conflictResolution: resolution
                    )
                    imported.append(result.item)
                } catch {
                    noteFileError = ui(
                        "“\(sourceURL.lastPathComponent)”未能加入课程：\(error.localizedDescription)",
                        "Could not add “\(sourceURL.lastPathComponent)” to the course: \(error.localizedDescription)"
                    )
                }
            }
            courseFileOperationProgress = nil
            if !imported.isEmpty {
                showTransientNoteStatus(
                    ui(
                        "已把 \(imported.count) 个文件移入课程目录。",
                        "Moved \(imported.count) file(s) into the course folder."
                    )
                )
            }
            completion(imported)
        }
    }

    private func confirmCourseImportPlan(
        _ sources: [URL],
        courseID: UUID,
        asNotes: Bool
    ) -> Bool {
        guard let root = courseRootURL(for: courseID) else { return false }
        let role: CourseOwnedFileRole = asNotes ? .note : .material
        let mappings = sources.prefix(12).map {
            "\($0.path)\n→ \(root.appendingPathComponent(role.directoryName).appendingPathComponent($0.lastPathComponent).path)"
        }
        let remaining = max(0, sources.count - mappings.count)
        let alert = NSAlert()
        alert.messageText = ui("确认移入课程", "Confirm moving into course")
        alert.informativeText = mappings.joined(separator: "\n\n")
            + (remaining > 0 ? ui("\n\n另有 \(remaining) 个文件。", "\n\nPlus \(remaining) more file(s).") : "")
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("移入课程", "Move into Course"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func courseImportConflictResolution(
        sourceURL: URL,
        courseID: UUID,
        role: CourseOwnedFileRole,
        allowsReplace: Bool = true,
        additionalProtectedTarget: URL? = nil
    ) -> CourseFileConflictResolution? {
        guard let root = courseRootURL(for: courseID) else { return nil }
        let target = root
            .appendingPathComponent(role.directoryName, isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent)
        let targetExists = FileManager.default.fileExists(atPath: target.path)
        let protectedTargetExists = additionalProtectedTarget.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        guard targetExists || protectedTargetExists else {
            return .cancel
        }
        let alert = NSAlert()
        alert.messageText = ui("课程中已有同名文件", "A file with this name already exists")
        let conflictTargetURLs = [targetExists ? target : nil, protectedTargetExists
            ? additionalProtectedTarget
            : nil]
            .compactMap { $0 }
        let conflictTargets = conflictTargetURLs.map(\.path).joined(
            separator: "\n"
        )
        alert.informativeText =
            "\(ui("来源", "Source"))：\(sourceURL.path)\n\(ui("冲突目标", "Conflicting target"))：\(conflictTargets)"
        let suggestedName = CourseKeepBothNaming.suggestedFileName(
            originalName: sourceURL.lastPathComponent,
            conflictingTargets: conflictTargetURLs
        )
        let keepBothLabel = NSTextField(
            labelWithString: ui(
                "选择“保留两份”时使用的新文件名",
                "New file name when choosing Keep Both"
            )
        )
        keepBothLabel.font = .systemFont(ofSize: 11, weight: .medium)
        keepBothLabel.textColor = .secondaryLabelColor
        let keepBothNameField = NSTextField(string: suggestedName)
        keepBothNameField.placeholderString = suggestedName
        keepBothNameField.setAccessibilityLabel(keepBothLabel.stringValue)
        let keepBothAccessory = NSStackView(
            views: [keepBothLabel, keepBothNameField]
        )
        keepBothAccessory.orientation = .vertical
        keepBothAccessory.alignment = .leading
        keepBothAccessory.spacing = 5
        keepBothNameField.widthAnchor.constraint(
            equalToConstant: 360
        ).isActive = true
        alert.accessoryView = keepBothAccessory
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("保留两份", "Keep Both"))
        let targetItem = courseItemMemberships.first {
            $0.courseID == courseID && $0.courseRelativePath == "\(role.directoryName)/\(sourceURL.lastPathComponent)"
        }.flatMap { membership in
            importedItems.first { $0.id == membership.itemID }
        }
        if allowsReplace,
           !protectedTargetExists,
           targetItem.map({ if case .shared = $0.storage { return true }; return false }) != true {
            alert.addButton(withTitle: ui("替换", "Replace"))
        }
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            let preferredName = keepBothNameField.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .keepBoth(
                preferredFileName: preferredName.isEmpty
                    ? suggestedName
                    : preferredName
            )
        case .alertThirdButtonReturn:
            return .replace
        default:
            return nil
        }
    }

    func dismissCourseWorkspace() {
        dismissCourseWorkspace(restoringFocus: true)
    }

    func courseMaterialIsAvailable(_ itemID: String) -> Bool {
        courseMaterials.first(where: { $0.id == itemID })?.urlPath != nil
    }

    @discardableResult
    func openCourseMaterial(_ itemID: String, in requestedCourseID: UUID? = nil) -> Bool {
        if let requestedCourseID {
            guard courseMembershipIndex.itemIDs(in: requestedCourseID).contains(itemID) else {
                return false
            }
        }
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID && !$0.isNotebookNote
        }),
        courseMaterials.contains(where: { $0.id == itemID }) else {
            return false
        }
        let resolution = resolveTrackedImportedFile(at: itemIndex)
        if resolution.changed {
            save()
            courseDocumentSearchIndex.schedule([importedItems[itemIndex]])
            invalidateAgentContext()
        }
        guard let resolvedURL = resolution.url,
              FileManager.default.isReadableFile(atPath: resolvedURL.path),
              let identity = importedFileIdentityResolver(resolvedURL),
              importedItems[itemIndex].importedFileIdentity.map({
                $0 == identity
              }) ?? true else {
            noteFileError = ui(
                "“\(displayTitle(for: importedItems[itemIndex]))”暂时不在课程文件夹中。把原文件放回课程后再打开；课程首页会继续保留。",
                "“\(displayTitle(for: importedItems[itemIndex]))” is not currently in the course folder. Put the original file back and try again; the course home will stay open."
            )
            return false
        }
        noteFileError = nil
        if let requestedCourseID {
            activeCourseID = requestedCourseID
        }
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        select(itemID: itemID)
        if layout == .immersiveWriting || layout == .immersiveConversation {
            setLayout(.immersiveReading)
        } else {
            showReader = true
            focus(.reader)
        }
        if let activeCourseID,
           let location = studyLocation(for: itemID, in: activeCourseID) {
            _ = captureCourseResumePoint(
                courseID: activeCourseID,
                materialLocation: location
            )
        }
        save()
        return true
    }

    func revealCourseFolder(containing itemID: String, in requestedCourseID: UUID? = nil) {
        guard let courseID = courseItemMemberships.first(where: {
            $0.itemID == itemID
                && ($0.courseID == requestedCourseID
                    || (requestedCourseID == nil
                        && ($0.courseID == activeCourseID
                            || activeCourseID == nil)))
        })?.courseID,
        let root = courseRootURL(for: courseID) else {
            return
        }
        let membership = courseItemMemberships.first {
            $0.courseID == courseID && $0.itemID == itemID
        }
        let folder: URL
        if let relativePath = membership?.courseRelativePath {
            guard let entryURL = Self.backgroundRawRelativeURL(
                relativePath,
                inside: root
            ) else {
                return
            }
            folder = entryURL.deletingLastPathComponent()
        } else {
            folder = root
        }
        guard CourseProjectPathPolicy.contains(
            root,
            folder,
            includingRoot: true
        ),
        FileManager.default.fileExists(atPath: folder.path) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func openCourseNote(_ itemID: String, in requestedCourseID: UUID? = nil) {
        guard importedItems.contains(where: {
            $0.id == itemID && $0.isNotebookNote
        }) else {
            return
        }
        if let requestedCourseID {
            guard courseMembershipIndex.itemIDs(in: requestedCourseID).contains(itemID) else {
                return
            }
            activeCourseID = requestedCourseID
        }
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        select(itemID: itemID)
    }

    func continueCourseSession(
        _ sessionID: UUID,
        expectedCourseID: UUID?,
        expectedScopeNeedsReview: Bool
    ) {
        guard studySessions.contains(where: {
            $0.id == sessionID && !$0.messages.isEmpty
        }),
        activateStudySession(
            sessionID,
            expectedCourseID: expectedCourseID,
            expectedScopeNeedsReview: expectedScopeNeedsReview
        ) else { return }
        openConversationInWorkspace(courseID: expectedCourseID)
        if let expectedCourseID {
            _ = captureCourseResumePoint(
                courseID: expectedCourseID,
                chatID: sessionID
            )
            save()
        }
    }

    /// Route one course-home question into the existing Chat/Pi pipeline.
    /// The home keeps its own draft until this method has validated the course root.
    @discardableResult
    func submitCourseHomeQuestion(
        _ rawQuestion: String,
        in courseID: UUID
    ) -> UUID? {
        let question = rawQuestion.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !question.isEmpty,
              !isStoppingAgent,
              course(withID: courseID) != nil else {
            return nil
        }

        let reusableSession: StudySession? = {
            guard let session = activeStudySession,
                  session.id == freshlyCreatedEmptyStudySessionID,
                  session.messages.isEmpty,
                  agentDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                return nil
            }
            return session
        }()
        guard let session = reusableSession
                ?? createStudySession(courseID: nil) else {
            return nil
        }

        freshlyCreatedEmptyStudySessionID = nil
        activeCourseID = courseID
        agentDraft = question
        agentDraftsBySessionID[session.id] = question
        openConversationInWorkspace(courseID: courseID)
        submitAgentDraft()
        return session.id
    }

    private func openConversationInWorkspace(courseID: UUID?) {
        if let courseID {
            activeCourseID = courseID
        }
        setDocumentPaneSet([.reader, .agent, .notes])
        layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
        focus(.agent)
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        save()
    }

    @discardableResult
    func resumeCourseReading(_ courseID: UUID) -> Bool {
        resumeCourseReadingPoint(courseID)
    }

    @discardableResult
    func resumeCourseConversation(_ courseID: UUID) -> Bool {
        guard let chatID = courseResumePoint(for: courseID)?.chatID,
              let session = studySessions.first(where: {
                  $0.id == chatID
                      && !$0.messages.isEmpty
                      && $0.relatedCourseIDs.contains(courseID)
              }) else {
            return false
        }
        continueCourseSession(
            session.id,
            expectedCourseID: courseID,
            expectedScopeNeedsReview: false
        )
        return activeStudySessionID == session.id && !courseWorkspacePresented
    }

    @discardableResult
    private func resumeCourseReadingPoint(_ courseID: UUID) -> Bool {
        guard let point = courseResumePoint(for: courseID),
              point.materialLocation != nil else {
            return false
        }
        isRestoringCourseResumePoint = true
        defer { isRestoringCourseResumePoint = false }

        var restoredMaterial = false
        if let location = point.materialLocation {
            restoredMaterial = openCourseMaterial(location.itemID, in: courseID)
            if restoredMaterial {
                readerPageIndex = max(location.pageIndex ?? 0, 0)
                readerLocationID = location.locationID
                readerLocationTitle = location.locationTitle ?? location.itemTitle
                if selectedMaterialItem?.kind == .pdf {
                    requestReaderPDFPage(location.pageIndex, recordsLocation: false)
                } else if selectedMaterialItem?.kind == .html {
                    requestReaderHTMLLocation(
                        id: location.locationID,
                        title: location.locationTitle
                    )
                }
            } else {
                return false
            }
        }

        var restoredNote = false
        if let noteItemID = point.noteItemID,
           importedItems.contains(where: { $0.id == noteItemID && $0.isNotebookNote }) {
            select(itemID: noteItemID)
            restoredNote = activeNoteItemID == noteItemID
        }

        var panes = Set(visibleDocumentPaneOrder)
        if restoredMaterial { panes.insert(.reader) }
        if restoredNote { panes.insert(.notes) }
        setDocumentPaneSet(panes)
        layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
        focus(.reader)
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        save()
        return true
    }

    private func dismissCourseWorkspace(restoringFocus: Bool) {
        guard courseWorkspacePresented else { return }
        courseWorkspacePresented = false
        courseWorkspaceTargetItemID = nil
        courseWorkspaceCourseID = nil
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
        if activeNoteItem == nil,
           let materialID = blankNoteDraftMaterialID {
            invalidateAgentContext()
            noteText = value
            pendingBlankNoteText = value
            guard !value.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            blankNoteMaterializationTask == nil else {
                return
            }
            blankNoteMaterializationTask = Task { @MainActor [weak self] in
                await self?.materializeBlankNoteDraft(
                    materialID: materialID
                )
            }
            return
        }
        if let itemID = activeNoteItem?.id,
           itemIsInRemovingCourse(itemID) {
            return
        }
        invalidateAgentContext()
        noteText = value
        guard let item = activeNoteItem else { return }
        if let materialID = selectedMaterialItem?.id,
           materialNotePairings[materialID] == item.id,
           noteMaterialPairings[item.id] == materialID,
           !noteSourceLinks.contains(where: {
               $0.noteItemID == item.id
                   && $0.sourceItemID == materialID
           }) {
            addNoteSourceLink(
                noteItemID: item.id,
                sourceItemID: materialID
            )
        }
        if !item.editsBackingMarkdownFile {
            notesByItemID[item.id] = value
        }
        scheduleNotePersistence(value, for: item)
    }

    private func materializeBlankNoteDraft(materialID: String) async {
        defer { blankNoteMaterializationTask = nil }
        guard blankNoteDraftMaterialID == materialID,
              let material = item(withID: materialID) else {
            return
        }
        let markdown = noteText
        guard !markdown.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return
        }
        let title = suggestedNotebookTitle(
            for: .currentMaterial(material)
        )
        let courseIDs = courseMembershipIndex.courseIDs(for: materialID)
        let noteID: String?
        if courseIDs.count == 1,
           let courseID = courseIDs.first,
           courseRootURL(for: courseID) != nil {
            noteID = await createCourseNotebookNote(
                courseID: courseID,
                title: title,
                markdown: markdown
            )
        } else {
            noteID = createNotebookNote(
                seed: .currentMaterial(material),
                title: title,
                initialMarkdown: markdown
            )?.id
        }
        guard let noteID else { return }
        let latestMarkdown = pendingBlankNoteText
        blankNoteDraftMaterialID = nil
        pendingBlankNoteText = ""
        rememberMaterialNotePair(
            materialID: materialID,
            noteID: noteID
        )
        addNoteSourceLink(
            noteItemID: noteID,
            sourceItemID: materialID
        )
        if latestMarkdown != markdown {
            updateNote(latestMarkdown, for: noteID)
        }
    }

    func stageNoteDraft(_ value: String, for itemID: String?) {
        guard let itemID,
              !itemIsInRemovingCourse(itemID) else {
            return
        }
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
        guard !itemIsInRemovingCourse(itemID),
              let item = allItems.first(where: { $0.id == itemID }) else {
            return
        }
        if !item.editsBackingMarkdownFile {
            notesByItemID[item.id] = value
        }
        scheduleNotePersistence(value, for: item)
    }

    func createBlankNotebookNote() {
        createNotebookNote(seed: .blank)
    }

    @discardableResult
    func createCourseNotebookNote(courseID: UUID, title rawTitle: String) async -> String? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            noteFileError = ui("笔记名不能为空。", "Note name cannot be empty.")
            return nil
        }
        let fileStem = safeFileStem(title)
        return await createCourseNotebookNote(
            courseID: courseID,
            title: fileStem,
            markdown: defaultNotebookNote(title: fileStem, sourceItem: nil)
        )
    }

    private func createCourseNotebookNote(
        courseID: UUID,
        title: String,
        markdown: String
    ) async -> String? {
        let data = Data(markdown.utf8)
        do {
            let result = try await transactCourseOwnedFile(
                courseID: courseID,
                role: .note,
                fileName: "\(safeFileStem(title)).md",
                sourceURL: nil,
                sourceIdentity: nil,
                generatedData: data
            )
            activeNotebookItemID = result.item.id
            noteText = markdown
            noteFileError = nil
            revealRichWritingSurface()
            focus(.notes)
            showTransientNoteStatus(
                ui(
                    "已在课程“笔记”目录新建：\(result.item.subtitle)",
                    "Created in the course Notes folder: \(result.item.subtitle)"
                )
            )
            return result.item.id
        } catch {
            noteFileError = ui(
                "无法创建课程笔记：\(error.localizedDescription)",
                "Could not create the course note: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func createCourseNotebookNoteForSelfCheck(
        courseID: UUID,
        title: String
    ) -> String? {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        do {
            return try waitForCourseFileOperation {
                await self.createCourseNotebookNote(courseID: courseID, title: title)
            }
        } catch {
            return nil
        }
    }

    private func waitForCourseFileOperation<T>(
        _ operation: @escaping @MainActor () async throws -> T
    ) throws -> T {
        var result: Result<T, Error>?
        Task { @MainActor in
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
        }
        while result == nil {
            RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        return try result!.get()
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
        let isOpening = !isPaneToggleActive(.reader)
        toggleDocumentPane(.reader)
        if isOpening {
            prepareMaterialForOpening()
            save()
        }
    }

    func toggleAgent() {
        if !isPaneToggleActive(.agent), selectionContext != nil {
            recordNavigationPoint()
            revealDocumentPane(.agent, clearSelection: false)
            routeSelectionToConversation()
            save()
            return
        }
        toggleDocumentPane(.agent)
    }

    func toggleNotes() {
        let isOpening = !isPaneToggleActive(.notes)
        toggleDocumentPane(.notes)
        if isOpening {
            prepareNoteForOpening()
            save()
        }
    }

    func showContextualBrowser(_ kind: ContextualContentKind) {
        switch kind {
        case .material:
            if selectedMaterialItem != nil {
                select(itemID: nil)
            }
            openDocumentPane(.reader)
        case .note:
            guard activeNoteItem != nil || blankNoteDraftMaterialID != nil else {
                openDocumentPane(.notes)
                return
            }
            persistCurrentNote()
            blankNoteMaterializationTask?.cancel()
            blankNoteMaterializationTask = nil
            pendingBlankNoteText = ""
            blankNoteDraftMaterialID = nil
            activeNotebookItemID = nil
            noteText = ""
            notebookCreationDraft = nil
            notebookRenameDraft = nil
            linkedSourcesPresented = false
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            syncActiveStudySession()
            openDocumentPane(.notes)
            save()
        }
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

    private func openDocumentPane(_ role: WorkspacePaneRole) {
        if isPaneVisible(role) {
            if focusedPane != role.focus {
                focus(role.focus)
            }
            return
        }
        recordNavigationPoint()
        if !showReader && !showAgent && !showNotes {
            threePaneOrder = WorkspacePaneRole.defaultThreePaneOrder
        }
        revealDocumentPane(role)
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
        readerSourceHighlight = ""
        readerSourceHighlightPageIndex = nil
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
        let cleanedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextID = cleanedID.isEmpty ? nil : String(cleanedID.prefix(500))
        let nextTitle = cleanedTitle.isEmpty ? selectedMaterialItem.map(displayTitle) : String(cleanedTitle.prefix(300))
        if reason == "jump" {
            clearReaderHTMLLocationTarget()
        }
        guard readerLocationID != nextID || readerLocationTitle != nextTitle else { return }
        // Scroll: persist silently. ReaderView already mirrors the active section in
        // @State; publishing here rebuilds agent chat PlatformViews and freezes UI.
        // Also skip study-progress save — successful saves assigned workspaceSaveError=nil
        // and fan out objectWillChange into the chat LazyVStack remasure loop.
        let publish = reason != "scroll"
        if publish {
            readerLocationID = nextID
            readerLocationTitle = nextTitle
            recordCurrentStudyLocation(incrementVisit: false)
        } else {
            suppressReaderViewportPublish = true
            readerLocationID = nextID
            readerLocationTitle = nextTitle
            suppressReaderViewportPublish = false
            recordCurrentStudyLocation(incrementVisit: false, schedulesSave: false)
        }
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

    func updateReaderPageIndex(_ index: Int, publishesUI: Bool = false) {
        let nextIndex = max(index, 0)
        guard readerPageIndex != nextIndex else { return }
        // Continuous PDF scroll uses publishesUI=false so agent chat WKWebViews
        // are not remasured on every page crossing (same hang class as HTML scroll).
        if publishesUI {
            readerPageIndex = nextIndex
            recordCurrentStudyLocation(incrementVisit: false)
        } else {
            suppressReaderViewportPublish = true
            readerPageIndex = nextIndex
            suppressReaderViewportPublish = false
            recordCurrentStudyLocation(incrementVisit: false, schedulesSave: false)
        }
    }

    private func recordCurrentStudyLocation(incrementVisit: Bool, schedulesSave: Bool = true) {
        guard activeCourseID.map({
            activeCourseRemovalTokens[$0] == nil
        }) ?? true,
        let item = selectedMaterialItem else {
            return
        }
        let previous = studyLocation(for: item.id, in: activeCourseID)
        let itemTitle = sourceReferenceBaseTitle(for: item)
        let locationID = item.kind == .html ? readerLocationID : nil
        let pageIndex = item.kind == .pdf ? readerPageIndex : nil
        let locationChanged = incrementVisit
            || previous?.itemTitle != itemTitle
            || previous?.locationID != locationID
            || previous?.locationTitle != readerLocationTitle
            || previous?.pageIndex != pageIndex
        let location = locationChanged
            ? StudyLocation(
                itemID: item.id,
                itemTitle: itemTitle,
                locationID: locationID,
                locationTitle: readerLocationTitle,
                pageIndex: pageIndex,
                lastStudiedAt: Date(),
                visitCount: max((previous?.visitCount ?? 0) + (incrementVisit ? 1 : 0), 1)
            )
            : previous
        let resumePointChanged = locationChanged && (activeCourseID.flatMap { courseID in
            guard courseMembershipIndex.courseIDs(for: item.id).contains(courseID),
                  let location else {
                return nil
            }
            return captureCourseResumePoint(
                courseID: courseID,
                materialLocation: location
            )
        } ?? false)
        guard locationChanged || resumePointChanged else {
            return
        }
        if let location, locationChanged {
            studyLocationsByItemID[item.id] = location
            if let activeCourseID,
               courseMembershipIndex.courseIDs(for: item.id).contains(activeCourseID) {
                studyLocationsByCourseID[activeCourseID.uuidString, default: [:]][item.id]
                    = location
            }
        }
        guard schedulesSave else { return }
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
        guard let location = studyLocation(for: item.id, in: activeCourseID) else {
            readerLocationID = nil
            readerLocationTitle = displayTitle(for: item)
            readerPageIndex = 0
            requestReaderPDFPage(nil, recordsLocation: false)
            clearReaderHTMLLocationTarget()
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

    func canOpenAgentReplySource(_ source: AgentReplySource) -> Bool {
        guard let item = agentReplySourceItem(source) else { return false }
        return item.isSample
            || item.isNotebookNote
            || validatedAgentReplySourceIDs.contains(source.id)
    }

    func validateAgentReplySources(_ sources: [AgentReplySource]) async {
        guard !sources.isEmpty else { return }
        var immediatelyAvailable = Set<UUID>()
        var snapshots = [AgentReplySourceFileSnapshot]()

        for source in sources {
            guard let item = agentReplySourceItem(source) else { continue }
            if item.isSample || item.isNotebookNote {
                immediatelyAvailable.insert(source.id)
            } else if let url = item.url {
                snapshots.append(
                    AgentReplySourceFileSnapshot(
                        source: source,
                        itemID: item.id,
                        url: url.standardizedFileURL,
                        expectedIdentity: item.importedFileIdentity
                    )
                )
            }
        }

        let validationTask = Task.detached(priority: .utility) {
            Set(snapshots.compactMap { snapshot -> UUID? in
                guard !Task.isCancelled,
                      FileManager.default.isReadableFile(atPath: snapshot.url.path),
                      let identity = Self.resolveImportedFileIdentity(at: snapshot.url),
                      snapshot.expectedIdentity.map({ $0 == identity }) ?? true else {
                    return nil
                }
                return snapshot.source.id
            })
        }
        let availableIDs = await withTaskCancellationHandler {
            await validationTask.value
        } onCancel: {
            validationTask.cancel()
        }
        guard !Task.isCancelled else { return }

        var nextAvailableIDs = immediatelyAvailable
        for snapshot in snapshots where availableIDs.contains(snapshot.source.id) {
            guard let current = agentReplySourceItem(snapshot.source),
                  current.id == snapshot.itemID,
                  current.url?.standardizedFileURL == snapshot.url,
                  current.importedFileIdentity == snapshot.expectedIdentity else {
                continue
            }
            nextAvailableIDs.insert(snapshot.source.id)
        }
        if validatedAgentReplySourceIDs != nextAvailableIDs {
            validatedAgentReplySourceIDs = nextAvailableIDs
        }
    }

    @discardableResult
    func openAgentReplySource(_ source: AgentReplySource) -> Bool {
        guard let item = agentReplySourceItem(source) else { return false }
        let chatID = activeStudySessionID
        if let courseID = source.courseID {
            activateCourse(courseID)
        }
        if item.isNotebookNote {
            dismissCourseWorkspace(restoringFocus: false)
            select(itemID: item.id)
            revealDocumentPane(.agent, clearSelection: false)
            revealDocumentPane(.notes, clearSelection: false)
            focus(.notes)
            return activeStudySessionID == chatID
        }

        let opened: Bool
        if item.isSample {
            dismissCourseWorkspace(restoringFocus: false)
            select(itemID: item.id)
            opened = true
        } else {
            opened = openCourseMaterial(item.id)
        }
        guard opened else {
            validatedAgentReplySourceIDs.remove(source.id)
            return false
        }

        requestReaderPDFPage(
            item.kind == .pdf ? source.pageIndex : nil,
            recordsLocation: item.kind == .pdf && source.pageIndex != nil
        )
        let htmlTargetID = item.kind == .html
            ? source.sectionLocationID
                ?? source.sectionOrdinal.map { "html-heading-\(max($0 - 1, 0))" }
            : nil
        requestReaderHTMLLocation(
            id: htmlTargetID,
            title: item.kind == .html ? source.sectionTitle : nil
        )
        readerSourceHighlight = source.highlightQuery
        readerSourceHighlightPageIndex = item.kind == .pdf ? source.pageIndex : nil
        revealDocumentPane(.agent, clearSelection: false)
        revealDocumentPane(.reader, clearSelection: false)
        focus(.reader)
        return activeStudySessionID == chatID
    }

    private func agentReplySourceItem(_ source: AgentReplySource) -> StudyItem? {
        guard let itemID = source.itemID,
              let item = allItems.first(where: { $0.id == itemID }) else {
            return nil
        }
        if let courseID = source.courseID {
            guard courses.contains(where: { $0.id == courseID }),
                  courseMembershipIndex.courseIDs(for: itemID).contains(courseID) else {
                return nil
            }
        }
        if item.isSample || item.isNotebookNote {
            return item
        }
        return item.urlPath == nil ? nil : item
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
                guard isAgentRunningInActiveChat
                    || !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
                submitAgentDraft()
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
        agentProviderID = provider
        modelName = ""
        touchActiveAgentProfileMetadata()
        save()
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

    func setAgentAuthMethod(_ method: AgentAuthMethod) {
        guard agentAuthMethod != method else { return }
        agentAuthMethod = method
        touchActiveAgentProfileMetadata()
    }

    func recordAgentAuthenticationSuccess(
        provider: AgentProviderID,
        authMethod: AgentAuthMethod
    ) {
        agentAuthenticationStatus.recordSuccess(
            provider: provider,
            authMethod: authMethod
        )
    }

    func selectAgentCredentialProfile(_ id: UUID) {
        guard let profile = agentCredentialProfiles.first(where: { $0.id == id }) else { return }
        activeAgentProfileID = id
        AgentCredentialProfileStore.setActiveProfileID(id)
        agentProviderID = profile.provider
        agentAuthMethod = profile.authMethod
        modelName = profile.modelName
        agentBaseURL = profile.baseURL
        save()
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
        agentCredentialProfiles.remove(at: index)
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
        guard let url else { return }
        NSWorkspace.shared.open(url)
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
        }
    }

    func importFilesFromPanel() {
        presentImportPanel(linkToActiveNote: false)
    }

    @discardableResult
    func retryWorkspaceSave() -> Bool {
        save()
    }

    func importCourseMaterialsFromPanel() {
        importCourseMaterialsFromPanel(courseID: activeCourseID)
    }

    func importCourseMaterialsFromPanel(courseID: UUID?) {
        presentImportPanel(
            linkToActiveNote: false,
            selectsFirstImportedItem: false,
            reclassifiesExistingMarkdown: true,
            assigningToCourseID: courseID,
            panelTitle: ui("选择课程资料或文件夹", "Choose course materials or a folder")
        )
    }

    func importCourseNotesFromPanel() {
        importCourseNotesFromPanel(courseID: activeCourseID)
    }

    func importCourseNotesFromPanel(courseID: UUID?) {
        presentImportPanel(
            linkToActiveNote: false,
            selectsFirstImportedItem: false,
            markdownAsNotes: true,
            markdownOnly: true,
            reclassifiesExistingMarkdown: true,
            assigningToCourseID: courseID,
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
        if let assigningToCourseID {
            importCourseFilesFromURLs(
                panel.urls,
                asNotes: markdownAsNotes,
                courseID: assigningToCourseID
            )
            return
        }
        let targetNoteID = linkToActiveNote ? activeNotebookItemID : nil
        let selectedItems = importFiles(
            panel.urls,
            selectsFirstImportedItem: selectsFirstImportedItem,
            markdownAsNotes: markdownAsNotes,
            markdownOnly: markdownOnly,
            reclassifiesExistingMarkdown: reclassifiesExistingMarkdown
        )
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
                self.selectedItemID = courseMaterials.first?.id
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
        let selectedItems = importedItems.filter { importedIDSet.contains($0.id) }
        if selectsFirstImportedItem,
           let first = selectedItems.first(where: { !$0.isNotebookNote }) {
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

    nonisolated private static func resolveCourseProjectBookmark(
        _ data: Data
    ) -> CourseProjectResolvedBookmark? {
        guard let resolved = resolveImportedFileBookmark(data) else { return nil }
        return CourseProjectResolvedBookmark(url: resolved.url, isStale: resolved.isStale)
    }

    nonisolated private static func makeImportedItemID() -> String {
        "imported:\(UUID().uuidString.lowercased())"
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
        guard !notebookRenameInFlight else { return }
        notebookRenameInFlight = true
        if Self.mustSaveImmediately {
            defer { notebookRenameInFlight = false }
            _ = try? waitForCourseFileOperation {
                await self.renameNotebookNoteInTransaction(
                    itemID: itemID,
                    to: rawTitle
                )
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.notebookRenameInFlight = false }
            await self.renameNotebookNoteInTransaction(
                itemID: itemID,
                to: rawTitle
            )
        }
    }

    private func renameNotebookNoteInTransaction(
        itemID: String,
        to rawTitle: String
    ) async {
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
        let markInitialSaveFailure = {
            self.noteFileError = self.ui(
                "无法重命名笔记：当前课程状态尚未安全保存，文件和关系均未改动。",
                "Could not rename the note because the current course state was not safely saved. The file and relationships were not changed."
            )
        }
        if Self.mustSaveImmediately {
            guard save() else {
                markInitialSaveFailure()
                return
            }
        } else if !(await persistWorkspaceNow()) {
            markInitialSaveFailure()
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
            let notebookMarkdownWriter = self.notebookMarkdownWriter
            let writeAndVerify: (URL) -> Void = { coordinatedURL in
                do {
                    guard self.importedFileIdentityResolver(
                        coordinatedURL
                    ) == movedIdentity,
                          Self.noteContentDigest(at: coordinatedURL) == originalContentDigest else {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: self.ui(
                                    "写入前检测到文件被外部修改，操作已中止。",
                                    "The file changed externally before writing, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    if willRewriteMarkdown {
                        try notebookMarkdownWriter(retitledMarkdown, coordinatedURL)
                    }
                    let identityBeforeRead =
                        self.importedFileIdentityResolver(coordinatedURL)
                    let outputData = try Data(contentsOf: coordinatedURL)
                    let identityAfterRead =
                        self.importedFileIdentityResolver(coordinatedURL)
                    let outputDigest = Self.noteContentDigest(outputData)
                    guard identityBeforeRead == identityAfterRead,
                          outputDigest == expectedOutputDigest else {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 3,
                            userInfo: [
                                NSLocalizedDescriptionKey: self.ui(
                                    "写入后文件内容或身份不一致，操作已中止。",
                                    "The file contents or identity did not match after writing, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    if !oldID.hasPrefix("file:"),
                       identityAfterRead == nil {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 4,
                            userInfo: [
                                NSLocalizedDescriptionKey: self.ui(
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
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(
                writingItemAt: newURL,
                options: .forReplacing,
                error: &coordinationError
            ) {
                writeAndVerify($0)
            }
            if let operationError { throw operationError }
            if let coordinationError {
                // Some local filesystems return fileWriteUnknown before
                // entering the accessor. Fall back only after proving the
                // coordinator performed no write; the same generation checks
                // and the final commit guard still apply.
                guard coordinationError.domain == NSCocoaErrorDomain,
                      coordinationError.code
                        == CocoaError.Code.fileWriteUnknown.rawValue else {
                    throw coordinationError
                }
                if !verifiedApplicationOutput {
                    writeAndVerify(newURL)
                    if let operationError { throw operationError }
                    guard verifiedApplicationOutput else {
                        throw coordinationError
                    }
                }
            }
            // NSFileCoordinator can report a late fileWriteUnknown even after
            // its accessor completed and verified the exact output generation.
            // In that case the identity/digest guard below remains the commit
            // authority instead of rolling a successful rename back.
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
            guard await persistWorkspaceNow() else {
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
                    let savedRecovery = await persistWorkspaceNow()
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
            let savedRecovery = await persistWorkspaceNow()
            if savedRecovery { removePendingNotebookRenameJournal() }
        }
    }

    func openOrCreateWikiNote(title rawTitle: String) {
        let title = WikiLink.targetTitle(from: rawTitle)
        guard !title.isEmpty else { return }

        let commonNotesDirectory = courseLibraryRootURL?.appendingPathComponent(
            CourseOwnedFileRole.note.commonDirectoryName,
            isDirectory: true
        )
        let notesDirectory = commonNotesDirectory
            ?? appOwnedFilesDirectory().appendingPathComponent(
                "Notes",
                isDirectory: true
            )
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
                importedFileBookmarkData: commonNotesDirectory == nil
                    ? identity.flatMap { _ in
                        Self.makeImportedFileBookmark(for: url)
                    }
                    : nil,
                importedFileLastKnownPath: url.path,
                isSample: false,
                isNotebookNote: true,
                storage: commonNotesDirectory == nil
                    ? .legacyExternal
                    : .shared(
                        sharedRelativePath:
                            "\(CourseOwnedFileRole.note.commonDirectoryName)/\(url.lastPathComponent)"
                    )
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
    private func createNotebookNote(
        seed: NotebookNoteSeed,
        title rawTitle: String? = nil,
        initialMarkdown: String? = nil
    ) -> StudyItem? {
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
        let commonNotesDirectory = courseLibraryRootURL?.appendingPathComponent(
            CourseOwnedFileRole.note.commonDirectoryName,
            isDirectory: true
        )
        let notesDirectory = commonNotesDirectory
            ?? appOwnedFilesDirectory().appendingPathComponent(
                "Notes",
                isDirectory: true
            )

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
                isNotebookNote: true,
                storage: commonNotesDirectory == nil
                    ? .legacyExternal
                    : .shared(
                        sharedRelativePath:
                            "\(CourseOwnedFileRole.note.commonDirectoryName)/\(url.lastPathComponent)"
                    )
            )
            let markdown = initialMarkdown
                ?? defaultNotebookNote(title: item.title, sourceItem: sourceItem)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            noteBackingContentDigestsByItemID[item.id] = Self.noteContentDigest(Data(markdown.utf8))
            item.importedFileIdentity = importedFileIdentityResolver(url)
            item.importedFileBookmarkData = commonNotesDirectory == nil
                ? item.importedFileIdentity.flatMap { _ in
                    Self.makeImportedFileBookmark(for: url)
                }
                : nil
            item.importedFileLastKnownPath = url.path
            importedItems.append(item)
            courseDocumentSearchIndex.synchronize(allItems)
            if let sourceItem {
                addNoteSourceLink(noteItemID: item.id, sourceItemID: sourceItem.id)
                let courseIDs = courseMembershipIndex.courseIDs(
                    for: sourceItem.id
                )
                if case .shared = item.storage, !courseIDs.isEmpty {
                    Task { @MainActor [weak self] in
                        for courseID in courseIDs {
                            try? await self?.linkSharedItem(
                                itemID: item.id,
                                toCourseID: courseID,
                                conflictResolution: .keepBoth(
                                    preferredFileName: nil
                                )
                            )
                        }
                    }
                }
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
            self.selectedItemID = nil
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
        guard !courseWorkspacePresented else { return }
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
            let anchorUnchanged = Self.anchorsApproximatelyEqual(selectionAnchor, anchor, epsilon: 8)
            let surfaceAlreadyCorrect = shouldRevealSelectionPrompt
                ? agentSurface == .selectionFloat
                : agentSurface != .selectionFloat
            if anchorUnchanged, !pinnedFloatingAgent, !keepFloatingSelectionForAnswer, surfaceAlreadyCorrect {
                return
            }
            if !anchorUnchanged {
                // Silent write first so we never assign @Published every pixel.
                // Throttle a real publish so the floating capsule can track ~20fps
                // without remasuring agent chat SelectionOverlay every frame.
                suppressSelectionAnchorPublish = true
                selectionAnchor = anchor
                suppressSelectionAnchorPublish = false
                let now = CFAbsoluteTimeGetCurrent()
                if agentSurface == .selectionFloat,
                   now - lastSelectionAnchorPublishAt >= 0.05 {
                    lastSelectionAnchorPublishAt = now
                    objectWillChange.send()
                }
            }
            // Never clear pin while the user locked the float (or mid selection-answer).
            cancelPendingSelectionAttachment()
            if pinnedFloatingAgent || keepFloatingSelectionForAnswer {
                if agentSurface != .selectionFloat {
                    agentSurface = .selectionFloat
                }
                return
            }
            if shouldRevealSelectionPrompt {
                if agentSurface != .selectionFloat {
                    withAnimation(WeiBeiMotion.panel) {
                        agentSurface = .selectionFloat
                    }
                } else {
                }
            } else if agentSurface == .selectionFloat {
                withAnimation(WeiBeiMotion.panel) {
                    agentSurface = .hidden
                }
            }
            return
        }

        invalidateAgentContext()
        let nextSelection = SelectionContext(
            text: boundedText,
            source: source,
            ownerTitle: resolvedOwnerTitle,
            itemID: source == .note ? activeNotebookItemID : selectedItemID,
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
            return
        }
        if shouldRevealSelectionPrompt {
            if agentSurface != .selectionFloat {
                withAnimation(WeiBeiMotion.panel) {
                    agentSurface = .selectionFloat
                }
            } else {
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
            itemID: selection.itemID,
            isEditable: selection.isEditable
        )
        let now = Date()
        defer { lastSelectionAttachmentDate = now }
        let sameSelectionSource: (SelectionContext) -> Bool = {
            $0.ownerTitle == cleanedSelection.ownerTitle
                && $0.source == cleanedSelection.source
                && ($0.itemID == nil || cleanedSelection.itemID == nil || $0.itemID == cleanedSelection.itemID)
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
        guard existing.source == incoming.source,
              existing.ownerTitle == incoming.ownerTitle,
              existing.itemID == nil || incoming.itemID == nil || existing.itemID == incoming.itemID else {
            return false
        }
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
            itemID: existing.itemID ?? incoming.itemID,
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
        let previousWorkspaceCourseID = courseWorkspaceCourseID

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
        if let courseWorkspaceCourseID,
           !courses.contains(where: { $0.id == courseWorkspaceCourseID }) {
            self.courseWorkspaceCourseID = courses.first?.id
        }
        let courseLocationsChanged = sanitizeCourseStudyLocations()

        return courses != previousCourses
            || courseItemMemberships != previousMemberships
            || activeCourseID != previousActiveCourseID
            || courseWorkspaceCourseID != previousWorkspaceCourseID
            || courseLocationsChanged
    }

    @discardableResult
    private func sanitizeCourseStudyLocations() -> Bool {
        let previous = studyLocationsByCourseID
        let validCourseIDs = Set(courses.map { $0.id.uuidString })
        studyLocationsByCourseID = studyLocationsByCourseID.reduce(
            into: [String: [String: StudyLocation]]()
        ) { result, entry in
            guard validCourseIDs.contains(entry.key),
                  let courseID = UUID(uuidString: entry.key) else {
                return
            }
            let validItemIDs = Set(courseMembershipIndex.itemIDs(in: courseID))
            let locations = entry.value.reduce(
                into: [String: StudyLocation]()
            ) { locations, itemEntry in
                guard validItemIDs.contains(itemEntry.key),
                      importedItems.contains(where: {
                          $0.id == itemEntry.key && !$0.isNotebookNote
                      }) else {
                    return
                }
                var location = itemEntry.value
                location.itemID = itemEntry.key
                locations[itemEntry.key] = location
            }
            if !locations.isEmpty {
                result[entry.key] = locations
            }
        }
        return studyLocationsByCourseID != previous
    }

    private func migrateCourseStudyLocationsFromLegacyIfNeeded() {
        for point in courseResumePoints {
            guard let location = point.materialLocation else { continue }
            let courseKey = point.courseID.uuidString
            var locations = studyLocationsByCourseID[courseKey] ?? [:]
            locations[location.itemID] = locations[location.itemID] ?? location
            studyLocationsByCourseID[courseKey] = locations
        }
        for (itemID, location) in studyLocationsByItemID {
            let courseIDs = courseMembershipIndex.courseIDs(for: itemID)
            guard courseIDs.count == 1, let courseID = courseIDs.first else {
                continue
            }
            let courseKey = courseID.uuidString
            var locations = studyLocationsByCourseID[courseKey] ?? [:]
            locations[itemID] = locations[itemID] ?? location
            studyLocationsByCourseID[courseKey] = locations
        }
        _ = sanitizeCourseStudyLocations()
    }

    @discardableResult
    private func migrateLegacyStudySessionScopes() -> Bool {
        var changed = sanitizeStudySessionScopes()
        guard studySessionScopeMigrationVersion < 2 else { return changed }
        let validCourseIDs = Set(courses.map(\.id))
        for index in studySessions.indices
        where !studySessions[index].messages.isEmpty {
            var related = Set(studySessions[index].relatedCourseIDs)
            let itemIDs = Set(
                studySessions[index].focusItemIDs
                    + [studySessions[index].materialItemID].compactMap { $0 }
                    + studySessions[index].messages.flatMap {
                        $0.sources.compactMap(\.itemID)
                    }
            )
            related.formUnion(
                itemIDs.flatMap { courseMembershipIndex.courseIDs(for: $0) }
            )
            related.formUnion(
                studySessions[index].messages.flatMap { message in
                    message.sources.compactMap(\.courseID)
                        + [message.origin?.courseID].compactMap { $0 }
                }
            )
            let migrated = related.intersection(validCourseIDs).sorted {
                $0.uuidString < $1.uuidString
            }
            if migrated != studySessions[index].relatedCourseIDs {
                studySessions[index].relatedCourseIDs = migrated
                changed = true
            }
        }
        studySessionScopeMigrationVersion = 2
        return true
    }

    @discardableResult
    private func sanitizeStudySessionScopes() -> Bool {
        let validCourseIDs = Set(courses.map(\.id))
        var changed = false
        for index in studySessions.indices {
            let sanitized = Set(studySessions[index].relatedCourseIDs)
                .intersection(validCourseIDs)
                .sorted { $0.uuidString < $1.uuidString }
            if sanitized != studySessions[index].relatedCourseIDs {
                studySessions[index].relatedCourseIDs = sanitized
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    private func migrateLegacyLearningMemoryScopes() -> Bool {
        guard learningMemoryScopeMigrationVersion < 1 else {
            legacyLearningMemoryEntries = []
            legacyLearningMemoryRevision = 0
            return sanitizeLearningMemoryStates()
        }

        var nextStates: [ScopedLearningMemoryState] = []
        var stateIndexByScope: [LearningMemoryScope: Int] = [:]
        var seenMemoryIDs = Set<UUID>()

        func append(_ entry: LearningMemoryEntry, to scope: LearningMemoryScope) {
            guard seenMemoryIDs.insert(entry.id).inserted else { return }
            let stateIndex: Int
            if let existingIndex = stateIndexByScope[scope] {
                stateIndex = existingIndex
            } else {
                stateIndex = nextStates.count
                stateIndexByScope[scope] = stateIndex
                nextStates.append(ScopedLearningMemoryState(scope: scope))
            }
            nextStates[stateIndex].entries.append(
                Self.learningMemoryEntryWithInitialRevision(
                    entry,
                    revision: max(nextStates[stateIndex].revision, 1)
                )
            )
            nextStates[stateIndex].revision = max(nextStates[stateIndex].revision, 1)
        }

        for state in learningMemoryStates {
            if stateIndexByScope[state.scope] == nil {
                stateIndexByScope[state.scope] = nextStates.count
                nextStates.append(
                    ScopedLearningMemoryState(
                        scope: state.scope,
                        revision: state.revision
                    )
                )
            } else if let index = stateIndexByScope[state.scope] {
                nextStates[index].revision = max(nextStates[index].revision, state.revision)
            }
            for entry in state.entries {
                append(entry, to: state.scope)
            }
        }
        for entry in legacyLearningMemoryEntries {
            append(entry, to: learningMemoryScope(forLegacySessionID: entry.sessionID))
        }
        if let globalIndex = stateIndexByScope[.global] {
            nextStates[globalIndex].revision = max(
                nextStates[globalIndex].revision,
                legacyLearningMemoryRevision
            )
        }

        learningMemoryStates = nextStates
        learningMemoryScopeMigrationVersion = 1
        return true
    }

    @discardableResult
    private func sanitizeLearningMemoryStates() -> Bool {
        let previous = learningMemoryStates
        var nextStates: [ScopedLearningMemoryState] = []
        var stateIndexByScope: [LearningMemoryScope: Int] = [:]
        var seenMemoryIDs = Set<UUID>()

        for state in learningMemoryStates {
            let stateIndex: Int
            if let existingIndex = stateIndexByScope[state.scope] {
                stateIndex = existingIndex
            } else {
                stateIndex = nextStates.count
                stateIndexByScope[state.scope] = stateIndex
                nextStates.append(
                    ScopedLearningMemoryState(
                        scope: state.scope,
                        revision: state.revision
                    )
                )
            }
            nextStates[stateIndex].revision = max(nextStates[stateIndex].revision, state.revision)
            for entry in state.entries where seenMemoryIDs.insert(entry.id).inserted {
                nextStates[stateIndex].entries.append(
                    Self.learningMemoryEntryWithInitialRevision(
                        entry,
                        revision: max(nextStates[stateIndex].revision, 1)
                    )
                )
            }
        }

        learningMemoryStates = nextStates
        return learningMemoryStates != previous
    }

    private static func learningMemoryEntryWithInitialRevision(
        _ entry: LearningMemoryEntry,
        revision: UInt64
    ) -> LearningMemoryEntry {
        guard entry.revisions?.isEmpty != false else { return entry }
        var migrated = entry
        migrated.revisions = [
            LearningMemoryRevisionRecord(
                revision: revision,
                kind: entry.kind,
                text: entry.text,
                evidence: entry.evidence,
                origin: entry.origin,
                status: entry.status,
                sessionID: entry.sessionID,
                messageID: entry.messageID,
                resolutionEvidence: entry.resolutionEvidence,
                actor: .migration,
                recordedAt: entry.updatedAt
            ),
        ]
        return migrated
    }

    private func learningMemoryScope(forLegacySessionID sessionID: UUID?) -> LearningMemoryScope {
        guard let sessionID,
              let session = studySessions.first(where: { $0.id == sessionID }),
              session.scopeNeedsReview == false,
              let courseID = session.courseID else {
            return .global
        }
        return .course(courseID)
    }

    func learningMemoryScope(courseID: UUID?) -> LearningMemoryScope {
        courseID.map(LearningMemoryScope.course) ?? .global
    }

    func learningMemoryEntries(in scope: LearningMemoryScope) -> [LearningMemoryEntry] {
        learningMemoryStates.first(where: { $0.scope == scope })?.entries ?? []
    }

    func orderedLearningMemoryEntries(in scope: LearningMemoryScope) -> [LearningMemoryEntry] {
        learningMemoryEntries(in: scope).sorted { $0.updatedAt > $1.updatedAt }
    }

    func learningMemoryRevision(in scope: LearningMemoryScope) -> UInt64 {
        learningMemoryStates.first(where: { $0.scope == scope })?.revision ?? 0
    }

    private func learningMemoryContextScopes(courseID: UUID?) -> [LearningMemoryScope] {
        courseID.map { [.global, .course($0)] } ?? [.global]
    }

    private func learningMemoryContextRevision(courseID: UUID?) -> UInt64 {
        learningMemoryContextScopes(courseID: courseID).reduce(0) { revision, scope in
            (revision &* 1_000_003) &+ learningMemoryRevision(in: scope) &+ 1
        }
    }

    private func learningMemoryScope(
        for kind: LearningMemoryKind,
        courseID: UUID?
    ) -> LearningMemoryScope {
        if kind == .goal || kind == .preference { return .global }
        return learningMemoryScope(courseID: courseID)
    }

    private func learningMemoryStateIndex(
        for scope: LearningMemoryScope,
        createIfMissing: Bool
    ) -> Int? {
        if let index = learningMemoryStates.firstIndex(where: { $0.scope == scope }) {
            return index
        }
        guard createIfMissing else { return nil }
        learningMemoryStates.append(ScopedLearningMemoryState(scope: scope))
        return learningMemoryStates.indices.last
    }

    private func sanitizedCourseKnowledgeProfiles() -> [CourseKnowledgeProfile] {
        let courseIDs = Set(courses.map(\.id))
        return courseKnowledgeProfiles.compactMap { profile in
            guard courseIDs.contains(profile.courseID) else { return nil }
            let items = courseItems(in: profile.courseID)
            let noteItemIDs = Set(items.lazy.filter(\.isNotebookNote).map(\.id))
            return profile.retainingAvailableSources(
                materialItemIDs: Set(items.map(\.id)).subtracting(noteItemIDs),
                noteItemIDs: noteItemIDs
            )
        }
    }

    private func ensureCourseKnowledgeProfiles() -> Bool {
        let courseIDs = Set(courses.map(\.id))
        var seen = Set<UUID>()
        var next = sanitizedCourseKnowledgeProfiles().filter {
            courseIDs.contains($0.courseID) && seen.insert($0.courseID).inserted
        }
        for courseID in courseIDs where !seen.contains(courseID) {
            next.append(CourseKnowledgeProfile(courseID: courseID))
        }
        next.sort { $0.courseID.uuidString < $1.courseID.uuidString }
        guard next != courseKnowledgeProfiles else { return false }
        courseKnowledgeProfiles = next
        return true
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

    /// Current reader/note focus for this turn. Chat itself is never course-scoped.
    private func agentFocusMaterialItem(
        for target: AgentConversationTarget
    ) -> StudyItem? {
        selectedMaterialItem
    }

    private func agentFocusNoteItem(
        for target: AgentConversationTarget
    ) -> StudyItem? {
        activeNoteItem.flatMap { $0.isNotebookNote ? $0 : nil }
    }

    private func makeCourseContext(
        query: String,
        courseID: UUID?,
        access: AgentProjectAccessSnapshot,
        focusMaterialItem: StudyItem? = nil,
        focusNoteItem: StudyItem? = nil
    ) async throws -> CourseContextBuildResult {
        let focusItemIDs = Set(
            [focusMaterialItem?.id, focusNoteItem?.id].compactMap { $0 }
        )
        let candidates = access.sources.compactMap { source -> CourseIndexCandidate? in
            guard focusItemIDs.contains(source.item.id) else { return nil }
            guard Self.agentHostToolSourceIsValid(source) else {
                return nil
            }
            return CourseIndexCandidate(
                item: source.item,
                title: source.title,
                subtitle: source.subtitle,
                memoryText: source.memoryText,
                grants: source.grants
            )
        }
        let scopedItemIDs = Set(candidates.map(\.item.id))
        let title = courseID
            .flatMap { course(withID: $0)?.title }
            ?? ui("全部课程", "All Courses")
        let links = noteSourceLinks.filter {
            scopedItemIDs.contains($0.noteItemID)
                && scopedItemIDs.contains($0.sourceItemID)
        }
        // Focus package is independent of tool grants so global Chat still sees
        // the open reader document (e.g. legacyExternal HTML on the Desktop).
        let currentMaterialItem = focusMaterialItem
        let currentMaterialID = currentMaterialItem?.id
        let currentMaterialTitle = currentMaterialItem.map(displayTitle)
        let currentMaterialSubtitle = currentMaterialItem.map(displaySubtitle(for:))
        let currentNoteItem = focusNoteItem
        let currentNoteID = currentNoteItem?.id
        let currentNoteTitle = currentNoteItem.map(displayTitle)
        let currentNoteSubtitle = currentNoteItem.map(displaySubtitle(for:))
        var sources = candidates.map { candidate in
            CourseKnowledgeSource(
                id: candidate.item.id,
                title: candidate.title,
                subtitle: candidate.subtitle,
                kind: candidate.item.kind.rawValue,
                role: candidate.item.isNotebookNote ? "note" : "material",
                text: "",
                isTruncated: false
            )
        }
        var includedIDs = Set(sources.map(\.id))
        if let material = currentMaterialItem, includedIDs.insert(material.id).inserted {
            sources.append(
                CourseKnowledgeSource(
                    id: material.id,
                    title: currentMaterialTitle ?? material.title,
                    subtitle: currentMaterialSubtitle ?? material.subtitle,
                    kind: material.kind.rawValue,
                    role: "material",
                    text: "",
                    isTruncated: false
                )
            )
        }
        if let note = currentNoteItem, includedIDs.insert(note.id).inserted {
            sources.append(
                CourseKnowledgeSource(
                    id: note.id,
                    title: currentNoteTitle ?? note.title,
                    subtitle: currentNoteSubtitle ?? note.subtitle,
                    kind: note.kind.rawValue,
                    role: "note",
                    text: "",
                    isTruncated: false
                )
            )
        }
        return CourseContextBuildResult(
            context: CourseKnowledgeIndex.build(
                title: title,
                sources: sources,
                links: links,
                query: query,
                currentMaterialID: currentMaterialID,
                currentNoteID: currentNoteID
            )
        )
    }

    private func makeAgentProjectAccessSnapshot(
        target: AgentConversationTarget
    ) -> AgentProjectAccessSnapshot {
        let scopedItems = importedItems
        let coursesByID = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0.title) })
        let requestedCourseIDs: (StudyItem) -> [UUID] = { item in
            self.courseMembershipIndex.courseIDs(for: item.id)
        }
        let sources = scopedItems.compactMap { item -> AgentHostToolSource? in
            let itemCourseIDs = requestedCourseIDs(item)
            let grants = itemCourseIDs.compactMap { courseID in
                self.makeAgentFileGrant(
                    item: item,
                    courseID: courseID,
                    courseTitle: coursesByID[courseID] ?? "",
                    target: target
                )
            }
            guard !grants.isEmpty || Self.agentDirectSourceIsValid(item) else {
                return nil
            }
            let primaryGrant = grants.first
            let courseIDs = itemCourseIDs.map { $0.uuidString.lowercased() }
            let courseTitles = itemCourseIDs.compactMap { coursesByID[$0] }
            let baseSubtitle = displaySubtitle(for: item)
            let memoryText = loadedAgentNoteText(for: item)
            let sourceRevision = memoryText.map(
                CourseDocumentSearchIndex.sourceRevision(forMarkdown:)
            ) ?? CourseDocumentSearchIndex.sourceRevision(for: item)
            let subtitle = courseTitles.isEmpty
                ? baseSubtitle
                : ui(
                    "课程：\(courseTitles.joined(separator: "、")) · \(baseSubtitle)",
                    "Courses: \(courseTitles.joined(separator: ", ")) · \(baseSubtitle)"
                )
            let projectItem = StudyAgentProjectItem(
                itemID: item.id,
                title: displayTitle(for: item),
                kind: item.kind.rawValue,
                role: item.isNotebookNote ? "note" : "material",
                relativePath: primaryGrant?.relativePath ?? "",
                resolvedPath: primaryGrant?.targetURL.path ?? "",
                entryIdentity: primaryGrant.map { StudyAgentFileIdentity($0.entryIdentity) },
                targetIdentity: primaryGrant.map { StudyAgentFileIdentity($0.targetIdentity) },
                isShared: primaryGrant?.isShared == true,
                courseIDs: courseIDs,
                courseTitles: courseTitles,
                sourceRevision: sourceRevision
            )
            return AgentHostToolSource(
                item: item,
                projectItem: projectItem,
                title: displayTitle(for: item),
                subtitle: subtitle,
                kind: item.kind.rawValue,
                role: item.isNotebookNote ? "note" : "material",
                memoryText: memoryText,
                relativePath: primaryGrant?.relativePath,
                courseIDs: courseIDs,
                courseTitles: courseTitles,
                grants: grants
            )
        }
        let focusItemIDs = Set(
            [selectedMaterialItem?.id, activeNoteItem?.id].compactMap { $0 }
        )
        let projectItems = sources
            .filter { focusItemIDs.contains($0.item.id) }
            .map(\.projectItem)
        let selectedCourse = target.courseID.flatMap { courseID in
            self.course(withID: courseID)
        }
        return AgentProjectAccessSnapshot(
            scope: StudyAgentProjectScope(
                kind: .global,
                chatID: target.sessionID.uuidString.lowercased(),
                courseID: target.courseID?.uuidString.lowercased(),
                courseTitle: selectedCourse?.title,
                rootPath: nil,
                rootIdentity: nil,
                items: projectItems,
                isTruncated: false
            ),
            sources: sources
        )
    }

    private func makeAgentFileGrant(
        item: StudyItem,
        courseID: UUID,
        courseTitle: String,
        target: AgentConversationTarget
    ) -> AgentFileGrant? {
        let rootURL: URL
        let rootIdentity: ImportedFileIdentity
        if target.courseID == courseID,
           let scopedRoot = target.courseRootURL,
           let expectedIdentity = target.courseRootIdentity {
            rootURL = scopedRoot
            rootIdentity = expectedIdentity
        } else {
            guard let course = course(withID: courseID),
                  let expectedIdentity = course.sourceRootIdentity,
                  let rawRoot = courseRootURL(for: courseID),
                  let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(rawRoot),
                  CourseProjectFileWorker.identity(at: resolvedRoot) == expectedIdentity else {
                return nil
            }
            rootURL = resolvedRoot
            rootIdentity = expectedIdentity
        }
        guard CourseProjectFileWorker.identity(at: rootURL) == rootIdentity,
              let membership = courseItemMemberships.first(where: {
                  $0.courseID == courseID && $0.itemID == item.id
              }),
              let relativePath = membership.courseRelativePath,
              Self.isVisibleAgentProjectPath(relativePath),
              let targetURL = item.url?.standardizedFileURL,
              let entryIdentity = membership.entryIdentity,
              let targetIdentity = item.importedFileIdentity else {
            return nil
        }
        let entryURL = relativePath.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .reduce(rootURL) { $0.appendingPathComponent($1) }
            .standardizedFileURL
        guard CourseProjectFileWorker.identity(at: entryURL) == entryIdentity,
              CourseProjectFileWorker.identity(at: targetURL) == targetIdentity,
              CourseProjectPathPolicy.isSame(
                  targetURL,
                  targetURL.resolvingSymlinksInPath().standardizedFileURL
              ) else {
            return nil
        }
        let isShared: Bool
        switch item.storage {
        case .courseOwned(let ownerCourseID):
            isShared = false
            guard ownerCourseID == courseID,
                  CourseProjectPathPolicy.isSame(entryURL, targetURL),
                  CourseProjectPathPolicy.contains(
                      rootURL,
                      targetURL,
                      includingRoot: false
                  ) else {
                return nil
            }
        case .shared:
            isShared = true
            guard CourseProjectFileWorker.symbolicLink(
                at: entryURL,
                pointsTo: targetURL
            ) else {
                return nil
            }
        case .legacyExternal, .bundledSample:
            return nil
        }
        return AgentFileGrant(
            courseID: courseID,
            courseTitle: courseTitle,
            rootURL: rootURL,
            rootIdentity: rootIdentity,
            entryURL: entryURL,
            entryIdentity: entryIdentity,
            targetURL: targetURL,
            targetIdentity: targetIdentity,
            relativePath: relativePath,
            isShared: isShared
        )
    }

    private static func isVisibleAgentProjectPath(_ path: String) -> Bool {
        guard !path.hasPrefix("/"), !path.contains("\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".")
        }
    }

    func injectLegacyCourseMembershipForAgentSelfCheck(
        itemID: String,
        courseID: UUID
    ) {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        courseItemMemberships.append(
            CourseItemMembership(courseID: courseID, itemID: itemID)
        )
    }

    func installCourseVisualForAgentSelfCheck(
        courseID: UUID,
        data: Data
    ) throws -> StudyItem {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard let root = courseRootURL(for: courseID) else {
            throw AgentConversationTargetError(message: "课程根目录不可用")
        }
        let relativePath = "文稿/课程图像.png"
        let target = root.appendingPathComponent(relativePath)
        try data.write(to: target, options: [.atomic])
        guard let identity = CourseProjectFileWorker.identity(at: target) else {
            throw AgentConversationTargetError(message: "无法核验课程图像")
        }
        let item = StudyItem(
            id: "agent-visual:\(UUID().uuidString.lowercased())",
            title: "课程图像",
            subtitle: target.lastPathComponent,
            kind: .text,
            urlPath: target.path,
            importedFileIdentity: identity,
            importedFileLastKnownPath: target.path,
            isSample: false,
            storage: .courseOwned(ownerCourseID: courseID)
        )
        importedItems.append(item)
        courseItemMemberships.append(
            CourseItemMembership(
                courseID: courseID,
                itemID: item.id,
                courseRelativePath: relativePath,
                entryIdentity: identity
            )
        )
        courseDocumentSearchIndex.synchronize(allItems)
        return item
    }

    func installLegacyVisualForAgentSelfCheck(
        at url: URL,
        courseID: UUID
    ) throws -> StudyItem {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard let identity = CourseProjectFileWorker.identity(at: url) else {
            throw AgentConversationTargetError(message: "无法核验旧外部图像")
        }
        let item = StudyItem(
            id: "agent-legacy-visual:\(UUID().uuidString.lowercased())",
            title: url.deletingPathExtension().lastPathComponent,
            subtitle: url.lastPathComponent,
            kind: .text,
            urlPath: url.path,
            importedFileIdentity: identity,
            importedFileLastKnownPath: url.path,
            isSample: false,
            storage: .legacyExternal
        )
        importedItems.append(item)
        courseItemMemberships.append(
            CourseItemMembership(courseID: courseID, itemID: item.id)
        )
        return item
    }

    func setAgentNoteFixtureForSelfCheck(
        itemID: String,
        memoryText: String,
        diskText: String? = nil
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard let index = importedItems.firstIndex(where: {
            $0.id == itemID && $0.isNotebookNote
        }), let url = importedItems[index].url else {
            throw AgentConversationTargetError(message: "课程笔记样本不存在")
        }
        cancelPendingNotePersistence(for: itemID)
        pendingNotePersistenceByItemID.removeValue(forKey: itemID)
        if let diskText {
            try Data(diskText.utf8).write(to: url, options: [.atomic])
            guard let identity = CourseProjectFileWorker.identity(at: url) else {
                throw AgentConversationTargetError(message: "无法核验课程笔记样本")
            }
            importedItems[index].importedFileIdentity = identity
            importedItems[index].contentDigest = Self.noteContentDigest(Data(diskText.utf8))
            for membershipIndex in courseItemMemberships.indices
            where courseItemMemberships[membershipIndex].itemID == itemID {
                courseItemMemberships[membershipIndex].entryIdentity = identity
            }
        }
        courseNoteLoadTasksByItemID.removeValue(forKey: itemID)?.cancel()
        notesByItemID.removeValue(forKey: itemID)
        loadedCourseNoteTextByItemID[itemID] = memoryText
        activeNotebookItemID = itemID
        noteText = memoryText
        courseDocumentSearchIndex.synchronize(allItems)
    }

    func installPortableCourseStateFixtureForSelfCheck(
        courseID: UUID,
        materialItemID: String,
        noteItemID: String,
        foreignCourseID: UUID,
        foreignItemID: String
    ) throws -> (
        sessionID: UUID,
        memoryID: UUID,
        draft: String,
        firstMessageID: UUID,
        firstRichNarrative: String
    ) {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard item(materialItemID, belongsTo: courseID),
              item(noteItemID, belongsTo: courseID),
              item(foreignItemID, belongsTo: foreignCourseID) else {
            throw AgentConversationTargetError(message: "可携带状态测试资料不完整")
        }
        let sessionID = UUID()
        let memoryID = UUID()
        let foreignMemoryID = UUID()
        let draft = "# 可携带笔记\n\n尚未写回的课程草稿。"
        let now = Date()
        let firstMessageID = UUID()
        learningMemoryStates.removeAll {
            $0.scope == .course(courseID)
                || $0.scope == .course(foreignCourseID)
                || $0.scope == .global
        }
        learningMemoryStates = [
            ScopedLearningMemoryState(
                scope: .course(courseID),
                revision: 1,
                entries: [
                    LearningMemoryEntry(
                        id: memoryID,
                        kind: .progress,
                        text: "已完成课程可携带状态测试。",
                        evidence: "课程 Chat",
                        origin: .agentInference,
                        sessionID: sessionID,
                        messageID: firstMessageID,
                        createdAt: now,
                        updatedAt: now,
                        revisions: [
                            LearningMemoryRevisionRecord(
                                revision: 1,
                                kind: .progress,
                                text: "已完成课程可携带状态测试。",
                                evidence: "课程 Chat",
                                origin: .agentInference,
                                status: .active,
                                sessionID: sessionID,
                                messageID: firstMessageID,
                                actor: .agent,
                                recordedAt: now
                            ),
                        ]
                    ),
                ]
            ),
            ScopedLearningMemoryState(
                scope: .course(foreignCourseID),
                revision: 1,
                entries: [
                    LearningMemoryEntry(
                        id: foreignMemoryID,
                        kind: .confusion,
                        text: "另一门课程的记忆。",
                        evidence: "另一门课程",
                        origin: .userStatement,
                        createdAt: now,
                        updatedAt: now
                    ),
                ]
            ),
            ScopedLearningMemoryState(
                scope: .global,
                revision: 1,
                entries: [
                    LearningMemoryEntry(
                        kind: .preference,
                        text: "全局偏好。",
                        evidence: "全局 Chat",
                        origin: .userStatement,
                        createdAt: now,
                        updatedAt: now
                    ),
                ]
            ),
        ]
        let validSource = AgentReplySource(
            itemID: materialItemID,
            courseID: courseID,
            kind: .material,
            title: "本课程资料",
            label: "本课程资料",
            excerpt: "课程内证据"
        )
        let foreignSourceWithoutCourseID = AgentReplySource(
            itemID: foreignItemID,
            kind: .material,
            title: "另一门课程资料",
            label: "另一门课程资料",
            excerpt: "不应进入可携带状态"
        )
        let validAction = AgentReplyAction(
            kind: .createRelation,
            targetItemID: noteItemID,
            sourceItemID: materialItemID
        )
        let firstRichNarrative =
            "最早一条课程回复的富回答附件必须长期保留。"
        let firstReply = AgentMessage(
            id: firstMessageID,
            role: .assistant,
            text: "最早一条课程回答。",
            source: "课程 Chat",
            backend: .pi,
            richAnswer: RichAnswerPresentation(
                mode: .narrativeOnly,
                narrative: firstRichNarrative
            ),
            actions: [
                AgentReplyAction(
                    kind: .writeNote,
                    targetItemID: noteItemID,
                    proposedMarkdown: "最早一条动作附件"
                ),
            ],
            origin: AgentReplyOrigin(
                requestID: UUID(),
                chatID: sessionID,
                courseID: courseID
            ),
            createdAt: now
        )
        let foreignActionWithoutCourseID = AgentReplyAction(
            kind: .writeNote,
            targetItemID: foreignItemID,
            proposedMarkdown: "不应进入可携带状态"
        )
        let reply = AgentMessage(
            role: .assistant,
            text: "课程回答正文必须保留。",
            source: "课程 Chat",
            backend: .pi,
            sources: [validSource, foreignSourceWithoutCourseID],
            actions: [validAction, foreignActionWithoutCourseID],
            memoryUpdate: AgentReplyMemoryUpdate(
                memoryIDs: [memoryID, foreignMemoryID],
                summary: "只允许本课程记忆"
            ),
            origin: AgentReplyOrigin(
                requestID: UUID(),
                chatID: sessionID,
                courseID: courseID
            ),
            toolTrace: ["内部工具日志不得携带"],
            createdAt: now
        )
        var longHistory = [firstReply]
        for index in 1..<500 {
            longHistory.append(
                AgentMessage(
                    role: .user,
                    text: "课程历史消息 \(index)",
                    source: "课程 Chat",
                    createdAt: now.addingTimeInterval(Double(index))
                )
            )
        }
        longHistory.append(reply)
        let courseSession = StudySession(
            id: sessionID,
            title: "可携带课程 Chat",
            messages: longHistory,
            summary: "验证课程状态投影。",
            courseID: courseID,
            focusItemIDs: [materialItemID, foreignItemID],
            materialItemID: materialItemID,
            createdAt: now,
            updatedAt: now
        )
        let foreignSession = StudySession(
            title: "另一门课程 Chat",
            courseID: foreignCourseID,
            focusItemIDs: [foreignItemID],
            materialItemID: foreignItemID,
            createdAt: now,
            updatedAt: now
        )
        studySessions = [
            courseSession,
            foreignSession,
            StudySession(
                title: "全局 Chat",
                courseID: nil,
                createdAt: now,
                updatedAt: now
            ),
        ]
        activeStudySessionID = sessionID
        messages = courseSession.messages
        noteSourceLinks = [
            NoteSourceLink(
                noteItemID: noteItemID,
                sourceItemID: materialItemID,
                createdAt: now
            ),
            NoteSourceLink(
                noteItemID: noteItemID,
                sourceItemID: foreignItemID,
                createdAt: now
            ),
        ]
        let location = StudyLocation(
            itemID: materialItemID,
            itemTitle: "本课程资料",
            locationID: "portable-location",
            locationTitle: "可携带位置",
            lastStudiedAt: now,
            visitCount: 2
        )
        studyLocationsByCourseID[courseID.uuidString] = [
            materialItemID: location,
        ]
        courseResumePoints.removeAll { $0.courseID == courseID }
        courseResumePoints.append(
            CourseResumePoint(
                courseID: courseID,
                materialLocation: location,
                chatID: sessionID,
                noteItemID: noteItemID,
                savedAt: now
            )
        )
        notesByItemID[noteItemID] = draft
        pendingNoteWritesByItemID[noteItemID] = PendingNoteWriteState(
            baselineContentDigest: importedItems.first {
                $0.id == noteItemID
            }?.contentDigest
        )
        return (
            sessionID,
            memoryID,
            draft,
            firstMessageID,
            firstRichNarrative
        )
    }

    func pendingPortableNoteDraftForSelfCheck(itemID: String) -> String? {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard pendingNoteWritesByItemID[itemID] != nil else { return nil }
        return notesByItemID[itemID]
    }

    func appendPortableCourseMessageForSelfCheck(
        courseID: UUID,
        text: String
    ) throws -> UUID {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let sessionID = studySessions.first(where: {
            $0.relatedCourseIDs.contains(courseID)
        })?.id ?? activeStudySessionID
        guard let sessionID,
              let sessionIndex = studySessions.firstIndex(where: {
                  $0.id == sessionID
              }) else {
            throw AgentConversationTargetError(
                message: "可携带状态测试缺少统一 Chat"
            )
        }
        if !studySessions[sessionIndex].relatedCourseIDs.contains(courseID) {
            studySessions[sessionIndex].relatedCourseIDs.append(courseID)
            studySessions[sessionIndex].relatedCourseIDs.sort {
                $0.uuidString < $1.uuidString
            }
        }
        let message = AgentMessage(
            role: .user,
            text: text,
            source: nil
        )
        studySessions[sessionIndex].messages.append(message)
        if activeStudySessionID == studySessions[sessionIndex].id {
            messages = studySessions[sessionIndex].messages
        }
        return message.id
    }

    func updatePortableCourseLearningForSelfCheck(
        courseID: UUID,
        materialItemID: String,
        noteItemID: String,
        memoryText: String,
        noteText: String,
        pageIndex: Int
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let item = importedItems.first(where: {
            $0.id == materialItemID
        }),
        let session = studySessions.first(where: {
            $0.relatedCourseIDs.contains(courseID)
        }),
        let memoryIndex = learningMemoryStates.firstIndex(where: {
            $0.scope == .course(courseID)
        }) else {
            throw AgentConversationTargetError(
                message: "接管后的课程学习状态不完整"
            )
        }
        let now = Date()
        learningMemoryStates[memoryIndex].revision &+= 1
        learningMemoryStates[memoryIndex].entries.append(
            LearningMemoryEntry(
                kind: .progress,
                text: memoryText,
                evidence: "接管后继续学习",
                origin: .agentInference,
                sessionID: session.id,
                createdAt: now,
                updatedAt: now
            )
        )
        let location = StudyLocation(
            itemID: materialItemID,
            itemTitle: item.title,
            locationID: "post-adoption-location",
            locationTitle: "接管后阅读位置",
            pageIndex: pageIndex,
            lastStudiedAt: now,
            visitCount: 3
        )
        studyLocationsByCourseID[courseID.uuidString, default: [:]][
            materialItemID
        ] = location
        courseResumePoints.removeAll { $0.courseID == courseID }
        courseResumePoints.append(
            CourseResumePoint(
                courseID: courseID,
                materialLocation: location,
                chatID: session.id,
                noteItemID: noteItemID,
                savedAt: now
            )
        )
        notesByItemID[noteItemID] = noteText
        loadedCourseNoteTextByItemID[noteItemID] = noteText
        pendingNoteWritesByItemID[noteItemID] = PendingNoteWriteState(
            baselineContentDigest: importedItems.first {
                $0.id == noteItemID
            }?.contentDigest
        )
    }

    func portableCourseLearningMatchesForSelfCheck(
        courseID: UUID,
        materialItemID: String,
        noteItemID: String,
        messageText: String,
        memoryText: String,
        noteText: String,
        pageIndex: Int
    ) -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let hasMessage = studySessions.contains {
            $0.relatedCourseIDs.contains(courseID)
                && $0.messages.contains { $0.text == messageText }
        }
        let hasMemory = learningMemoryStates.first {
            $0.scope == .course(courseID)
        }?.entries.contains {
            $0.text == memoryText
        } == true
        let location = studyLocationsByCourseID[
            courseID.uuidString
        ]?[materialItemID]
        let resume = courseResumePoints.first {
            $0.courseID == courseID
        }
        return hasMessage
            && hasMemory
            && location?.pageIndex == pageIndex
            && resume?.materialLocation?.pageIndex == pageIndex
            && resume?.noteItemID == noteItemID
            && pendingPortableNoteDraftForSelfCheck(
                itemID: noteItemID
            ) == noteText
    }

    func removePortableCourseMessageForSelfCheck(
        courseID: UUID,
        messageID: UUID
    ) {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let sessionIndex = studySessions.firstIndex(where: {
            $0.relatedCourseIDs.contains(courseID)
        }) else {
            return
        }
        studySessions[sessionIndex].messages.removeAll {
            $0.id == messageID
        }
        if activeStudySessionID == studySessions[sessionIndex].id {
            messages = studySessions[sessionIndex].messages
        }
    }

    func setCourseReplyGeneratingForSelfCheck(
        courseID: UUID,
        generating: Bool
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let sessionIndex = studySessions.firstIndex(where: {
            $0.relatedCourseIDs.contains(courseID)
        }),
        let messageIndex = studySessions[sessionIndex].messages.lastIndex(
            where: { $0.role == .assistant }
        ) else {
            throw CoursePortableStateError.invalidChatScope
        }
        studySessions[sessionIndex].messages[messageIndex].completionState =
            generating ? .generating : .completed
        if activeStudySessionID == studySessions[sessionIndex].id {
            messages = studySessions[sessionIndex].messages
        }
    }

    func portableStateFlagsForSelfCheck(
        courseID: UUID
    ) -> (
        dirty: Bool,
        blocked: Bool,
        oversized: Bool
    ) {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return (
            dirtyPortableCourseIDs.contains(courseID),
            blockedPortableCourseIDs.contains(courseID),
            oversizedPortableCourseIDs.contains(courseID)
        )
    }

    func removeCourseMembershipForAgentSelfCheck(
        itemID: String,
        courseID: UUID
    ) {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        courseItemMemberships.removeAll {
            $0.courseID == courseID && $0.itemID == itemID
        }
    }

    func courseResumePointSurvivesFailedMembershipSaveForSelfCheck(
        itemID: String,
        courseID: UUID
    ) -> Bool {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let previousMemberships = courseItemMemberships
        courseItemMemberships.removeAll {
            $0.courseID == courseID && $0.itemID == itemID
        }
        let saveFailed = !flushPendingWorkspaceSave()
        courseItemMemberships = previousMemberships
        return saveFailed
            && courseResumePoint(for: courseID)?.materialLocation?.itemID == itemID
    }

    func courseResumePointDoesNotReviveAfterSuccessfulMembershipSaveForSelfCheck(
        itemID: String,
        courseID: UUID
    ) -> Bool {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let previousMemberships = courseItemMemberships
        courseItemMemberships.removeAll {
            $0.courseID == courseID && $0.itemID == itemID
        }
        guard flushPendingWorkspaceSave() else {
            courseItemMemberships = previousMemberships
            return false
        }
        courseItemMemberships = previousMemberships
        let stayedRemoved = courseResumePoint(for: courseID)?.materialLocation?.itemID != itemID
        return flushPendingWorkspaceSave() && stayedRemoved
    }

    func agentProjectScopeForSelfCheck(
        courseID: UUID?
    ) throws -> StudyAgentProjectScope {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return makeAgentProjectAccessSnapshot(
            target: try agentConversationTargetForSelfCheck(courseID: courseID)
        ).scope
    }

    func agentHostSearchForSelfCheck(
        courseID: UUID?,
        query: String,
        beforeSearch: (() throws -> Void)? = nil
    ) throws -> StudyAgentHostToolResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let target = try agentConversationTargetForSelfCheck(courseID: courseID)
        let access = makeAgentProjectAccessSnapshot(target: target)
        let handler = makeAgentHostToolHandler(target: target, access: access)
        try beforeSearch?()
        return try waitForCourseFileOperation {
            try await handler(.courseSearch(query: query, limit: 8))
        }
    }

    func agentHostMapForSelfCheck(
        courseID: UUID?,
        itemID: String? = nil,
        offset: Int = 0
    ) throws -> StudyAgentHostToolResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let target = try agentConversationTargetForSelfCheck(courseID: courseID)
        let access = makeAgentProjectAccessSnapshot(target: target)
        let handler = makeAgentHostToolHandler(target: target, access: access)
        return try waitForCourseFileOperation {
            try await handler(.courseMap(itemID: itemID, offset: offset, limit: 40))
        }
    }

    func agentHostReadForSelfCheck(
        courseID: UUID?,
        itemID: String,
        query: String = "",
        location: String? = nil
    ) throws -> StudyAgentHostToolResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let target = try agentConversationTargetForSelfCheck(courseID: courseID)
        let access = makeAgentProjectAccessSnapshot(target: target)
        let handler = makeAgentHostToolHandler(target: target, access: access)
        return try waitForCourseFileOperation {
            try await handler(
                .courseRead(
                    itemID: itemID,
                    query: query,
                    location: location,
                    cursor: nil,
                    maximumCharacters: 6_000
                )
            )
        }
    }

    func agentCourseContextForSelfCheck(
        courseID: UUID?,
        query: String
    ) throws -> StudyAgentCourseContext {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let target = try agentConversationTargetForSelfCheck(courseID: courseID)
        let access = makeAgentProjectAccessSnapshot(target: target)
        return try waitForCourseFileOperation {
            try await self.makeCourseContext(
                query: query,
                courseID: courseID,
                access: access
            ).context
        }
    }

#if DEBUG
    func capturedAgentRequestForSelfCheck(
        courseID: UUID,
        materialItemID: String,
        noteItemID: String,
        selectionItemID: String
    ) throws -> StudyAgentRequest {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard let session = createStudySession(courseID: courseID) else {
            throw AgentConversationTargetError(message: "无法创建课程自检 Chat")
        }
        selectedItemID = materialItemID
        openCourseNote(noteItemID)
        noteText = "LEGACY_NOTE_REQUEST_SECRET"
        guard activeNoteItem?.id == noteItemID else {
            throw AgentConversationTargetError(
                message: "自检没有建立当前笔记焦点"
            )
        }
        selectionAttachments = []
        selectionContext = SelectionContext(
            text: "LEGACY_SELECTION_REQUEST_SECRET",
            source: .document,
            ownerTitle: "旧外部选区",
            itemID: selectionItemID
        )
        agentDraft = "检查课程授权后的最终请求"
        agentDraftsBySessionID[session.id] = agentDraft
        selfCheckCapturedAgentRequest = nil
        capturesAgentRequestForSelfCheck = true
        defer { capturesAgentRequestForSelfCheck = false }
        let target = try agentConversationTargetForSelfCheck(courseID: courseID)
        let scopedTarget = AgentConversationTarget(
            sessionID: session.id,
            workingDirectory: target.workingDirectory,
            courseID: target.courseID,
            courseRootURL: target.courseRootURL,
            courseRootIdentity: target.courseRootIdentity
        )
        try waitForCourseFileOperation {
            await self.performAgentRequest(target: scopedTarget)
        }
        guard let selfCheckCapturedAgentRequest else {
            throw AgentConversationTargetError(
                message: "没有捕获最终课程 Agent 请求："
                    + (workspaceSaveError
                        ?? messages.last?.text
                        ?? "没有可见失败原因")
            )
        }
        return selfCheckCapturedAgentRequest
    }
#endif

    private func agentConversationTargetForSelfCheck(
        courseID: UUID?
    ) throws -> AgentConversationTarget {
        try makeAgentConversationTarget(
            sessionID: UUID(),
            courseID: courseID
        )
    }

    private func makeAgentHostToolHandler(
        target: AgentConversationTarget,
        access: AgentProjectAccessSnapshot
    ) -> StudyAgentHostToolHandler {
        let preferredCourseID = target.courseID?.uuidString.lowercased()
        let sources = access.sources.sorted { left, right in
            let leftPreferred = preferredCourseID.map(left.courseIDs.contains) ?? false
            let rightPreferred = preferredCourseID.map(right.courseIDs.contains) ?? false
            if leftPreferred != rightPreferred { return leftPreferred }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
        let scopedIDs = Set(sources.map(\.item.id))
        let courseTitlesByID = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0.title) })
        let links = noteSourceLinks.filter {
            scopedIDs.contains($0.noteItemID) && scopedIDs.contains($0.sourceItemID)
        }
        let title = target.courseID
            .flatMap { courseTitlesByID[$0] }
            ?? ui("全部课程", "All Courses")
        let searchIndex = courseDocumentSearchIndex

        return { request in
            let task = Task.detached(priority: .userInitiated) {
                try Self.executeAgentHostTool(
                    request,
                    title: title,
                    sources: sources,
                    links: links,
                    searchIndex: searchIndex
                )
            }
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            return result
        }
    }

    nonisolated private static func executeAgentHostTool(
        _ request: StudyAgentHostToolRequest,
        title: String,
        sources: [AgentHostToolSource],
        links: [NoteSourceLink],
        searchIndex: CourseDocumentSearchIndex
    ) throws -> StudyAgentHostToolResult {
        try Task.checkCancellation()
        switch request {
        case let .courseMap(itemID, offset, limit):
            let approvedSources = sources.filter(agentHostToolSourceIsValid)
            let selectedSources: ArraySlice<AgentHostToolSource>
            let total: Int
            if let itemID {
                let matches = approvedSources.filter { $0.item.id == itemID }
                selectedSources = matches[...]
                total = matches.count
            } else {
                selectedSources = approvedSources.dropFirst(offset).prefix(limit)
                total = approvedSources.count
            }
            let items = selectedSources.map { source in
                let linkedItemIDs = links.compactMap { link -> String? in
                    if link.noteItemID == source.item.id { return link.sourceItemID }
                    if link.sourceItemID == source.item.id { return link.noteItemID }
                    return nil
                }
                return StudyAgentHostToolItem(
                    item: StudyAgentCourseItem(
                        id: source.item.id,
                        title: source.title,
                        subtitle: source.subtitle,
                        kind: source.kind,
                        role: source.role,
                        linkedItemIDs: linkedItemIDs,
                        headings: itemID == nil
                            ? []
                            : searchIndex.outline(item: source.item),
                        tags: source.courseTitles,
                        searchText: "",
                        isTruncated: false
                    ),
                    relativePath: source.relativePath,
                    courseIDs: source.courseIDs,
                    courseTitles: source.courseTitles,
                    sourceRevision: source.projectItem.sourceRevision
                )
            }
            return StudyAgentHostToolResult(
                query: "",
                items: items,
                total: total,
                nextCursor: offset + items.count < total
                    ? String(offset + items.count)
                    : nil
            )

        case let .courseSearch(query, limit):
            let approvedSources = sources.filter(agentHostToolSourceIsValid)
            let indexed = searchIndex.lookup(
                items: approvedSources.compactMap {
                    $0.memoryText == nil ? $0.item : nil
                },
                query: query
            )
            let matched = approvedSources.compactMap { source -> (
                source: AgentHostToolSource,
                result: CourseDocumentIndexResult,
                titleMatched: Bool
            )? in
                let titleMatched = source.title.localizedCaseInsensitiveContains(query)
                    || source.subtitle.localizedCaseInsensitiveContains(query)
                    || (
                        source.title.count >= 2
                            && query.localizedCaseInsensitiveContains(source.title)
                    )
                let indexedResult = indexed[source.item.id]
                let result: CourseDocumentIndexResult
                if let memoryText = source.memoryText {
                    result = CourseDocumentSearchIndex.readMarkdown(
                        memoryText,
                        query: titleMatched ? "" : query,
                        location: nil
                    )
                } else if titleMatched {
                    result = searchIndex.read(
                        item: source.item,
                        query: "",
                        location: nil
                    )
                } else {
                    result = indexedResult ?? CourseDocumentIndexResult(
                        text: nil,
                        isTruncated: false,
                        rank: nil
                    )
                }
                guard let text = result.text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      agentHostToolSourceIsValid(source) else {
                    return nil
                }
                return (
                    source,
                    CourseDocumentIndexResult(
                        text: text,
                        isTruncated: result.isTruncated,
                        rank: result.rank,
                        sourceRevision: result.sourceRevision
                    ),
                    titleMatched
                )
            }.sorted { left, right in
                if left.titleMatched != right.titleMatched {
                    return left.titleMatched
                }
                return (left.result.rank ?? .greatestFiniteMagnitude)
                    < (right.result.rank ?? .greatestFiniteMagnitude)
            }
            let knowledgeSources = matched.prefix(max(limit * 4, limit)).map { match in
                CourseKnowledgeSource(
                    id: match.source.item.id,
                    title: match.source.title,
                    subtitle: match.source.subtitle,
                    kind: match.source.kind,
                    role: match.source.role,
                    text: match.result.text ?? "",
                    isTruncated: match.result.isTruncated
                )
            }
            let context = CourseKnowledgeIndex.build(
                title: title,
                sources: knowledgeSources,
                links: links,
                query: query,
                currentMaterialID: nil,
                currentNoteID: nil
            )
            let sourceByID = Dictionary(
                uniqueKeysWithValues: matched.map { ($0.source.item.id, $0.source) }
            )
            let sourceRevisionByID = Dictionary(
                uniqueKeysWithValues: matched.map {
                    ($0.source.item.id, $0.result.sourceRevision)
                }
            )
            return StudyAgentHostToolResult(
                query: query,
                items: context.items.prefix(limit).compactMap { item in
                    guard let source = sourceByID[item.id] else { return nil }
                    return StudyAgentHostToolItem(
                        item: item,
                        relativePath: source.relativePath,
                        courseIDs: source.courseIDs,
                        courseTitles: source.courseTitles,
                        sourceRevision: sourceRevisionByID[item.id] ?? nil
                    )
                }
            )

        case let .courseRead(itemID, query, location, cursor, maximumCharacters):
            guard let source = sources.first(where: { $0.item.id == itemID }),
                  agentHostToolSourceIsValid(source) else {
                throw AgentConversationTargetError(message: "这份资料不属于当前 Chat 的查询范围")
            }
            let indexed: CourseDocumentIndexResult
            if let memoryText = source.memoryText {
                indexed = CourseDocumentSearchIndex.readMarkdown(
                    memoryText,
                    query: query,
                    location: location,
                    cursor: cursor,
                    sourceID: source.item.id,
                    maximumCharacters: maximumCharacters
                )
            } else {
                indexed = searchIndex.read(
                    item: source.item,
                    query: query,
                    location: location,
                    cursor: cursor,
                    maximumCharacters: maximumCharacters
                )
            }
            guard let text = indexed.text,
                  agentHostToolSourceIsValid(source) else {
                throw AgentConversationTargetError(message: "这份资料在读取期间发生了变化")
            }
            let context = CourseKnowledgeIndex.build(
                title: title,
                sources: [
                    CourseKnowledgeSource(
                        id: source.item.id,
                        title: source.title,
                        subtitle: source.subtitle,
                        kind: source.kind,
                        role: source.role,
                        text: text,
                        isTruncated: indexed.isTruncated
                    ),
                ],
                links: links,
                query: [query, location].compactMap { $0 }.joined(separator: " "),
                currentMaterialID: nil,
                currentNoteID: nil
            )
            return StudyAgentHostToolResult(
                query: query,
                items: context.items.map { item in
                    var item = item
                    item.searchText = text
                    item.isTruncated = indexed.isTruncated
                    return StudyAgentHostToolItem(
                        item: item,
                        relativePath: source.relativePath,
                        courseIDs: source.courseIDs,
                        courseTitles: source.courseTitles,
                        sourceRevision: indexed.sourceRevision
                    )
                },
                nextCursor: indexed.nextCursor,
                sourceRevision: indexed.sourceRevision
            )
        }
    }

    nonisolated private static func agentHostToolSourceIsValid(
        _ source: AgentHostToolSource
    ) -> Bool {
        source.grants.contains(where: agentFileGrantIsValid)
            || agentDirectSourceIsValid(source.item)
    }

    nonisolated private static func agentDirectSourceIsValid(
        _ item: StudyItem
    ) -> Bool {
        guard let url = item.url?.standardizedFileURL,
              FileManager.default.isReadableFile(atPath: url.path),
              CourseProjectPathPolicy.isSame(
                  url,
                  url.resolvingSymlinksInPath().standardizedFileURL
              ) else {
            return false
        }
        switch item.storage {
        case .legacyExternal:
            guard let expectedIdentity = item.importedFileIdentity else {
                return false
            }
            return CourseProjectFileWorker.identity(at: url) == expectedIdentity
        case .bundledSample:
            return item.isSample
        case .courseOwned, .shared:
            return false
        }
    }

    nonisolated private static func agentFileGrantIsValid(
        _ grant: AgentFileGrant
    ) -> Bool {
        guard CourseProjectFileWorker.identity(at: grant.rootURL) == grant.rootIdentity,
              CourseProjectFileWorker.identity(at: grant.entryURL) == grant.entryIdentity,
              CourseProjectFileWorker.identity(at: grant.targetURL) == grant.targetIdentity,
              CourseProjectPathPolicy.isSame(
                  grant.targetURL,
                  grant.targetURL.resolvingSymlinksInPath().standardizedFileURL
              ) else {
            return false
        }
        if grant.isShared {
            return CourseProjectFileWorker.symbolicLink(
                at: grant.entryURL,
                pointsTo: grant.targetURL
            )
        }
        return CourseProjectPathPolicy.isSame(grant.entryURL, grant.targetURL)
            && CourseProjectPathPolicy.contains(
                grant.rootURL,
                grant.targetURL,
                includingRoot: false
            )
    }

    private func makeLearningContext(
        target: AgentConversationTarget
    ) -> StudyAgentLearningContext {
        let targetSession = studySessions.first { $0.id == target.sessionID }
        let session = targetSession.map { session in
            StudyAgentSessionSnapshot(
                id: session.id.uuidString.lowercased(),
                title: session.title,
                summary: session.summary,
                phase: session.flow.phase.rawValue,
                focusItemIDs: session.focusItemIDs.filter {
                    itemID($0, belongsTo: session)
                },
                turnCount: session.messages.count
            )
        }
        let memories = learningMemoryContextScopes(courseID: target.courseID)
            .flatMap { scope in
                orderedLearningMemoryEntries(in: scope).filter { entry in
                    scope != .global
                        || target.courseID == nil
                        || entry.kind == .goal
                        || entry.kind == .preference
                }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        return StudyAgentLearningContext(
            memoryRevision: learningMemoryContextRevision(courseID: target.courseID),
            lastLocation: lastStudyLocation(in: target.courseID),
            memories: Array(memories.prefix(200)),
            session: session
        )
    }

    private func makeCourseProfileContext(
        courseID: UUID?,
        access: AgentProjectAccessSnapshot
    ) -> StudyAgentCourseProfileContext {
        guard let courseID,
              let profileIndex = courseKnowledgeProfiles.firstIndex(where: {
                  $0.courseID == courseID
              }) else { return .empty }
        let sourcesByID = Dictionary(
            uniqueKeysWithValues: access.sources.map { ($0.item.id, $0) }
        )
        let retained = courseKnowledgeProfiles[profileIndex].entries.filter { entry in
            entry.sources.allSatisfy { reference in
                guard let source = sourcesByID[reference.itemID],
                      (source.item.isNotebookNote ? "note" : "material")
                        == reference.role.rawValue else { return false }
                let revision = source.memoryText.map(
                    CourseDocumentSearchIndex.sourceRevision(forMarkdown:)
                ) ?? CourseDocumentSearchIndex.sourceRevision(for: source.item)
                return revision == reference.sourceRevision
            }
        }
        if retained != courseKnowledgeProfiles[profileIndex].entries {
            courseKnowledgeProfiles[profileIndex].entries = retained
            courseKnowledgeProfiles[profileIndex].overview = retained
                .filter { $0.kind == .overview }
                .max(by: { $0.updatedAt < $1.updatedAt })?.text ?? ""
            courseKnowledgeProfiles[profileIndex].revision &+= 1
            courseKnowledgeProfiles[profileIndex].updatedAt = Date()
            dirtyPortableCourseIDs.insert(courseID)
            _ = save()
        }
        let profile = courseKnowledgeProfiles[profileIndex]
        return StudyAgentCourseProfileContext(
            revision: profile.revision,
            overview: profile.overview,
            entries: profile.entries.map { entry in
                StudyAgentCourseProfileEntry(
                    id: entry.id.uuidString.lowercased(),
                    kind: entry.kind.rawValue,
                    text: entry.text,
                    sources: entry.sources.map { source in
                        StudyAgentCourseProfileSource(
                            itemID: source.itemID,
                            role: source.role.rawValue,
                            location: source.location,
                            sourceRevision: source.sourceRevision
                        )
                    }
                )
            }
        )
    }

    private func lastStudyLocation(in courseID: UUID?) -> StudyLocation? {
        guard let courseID else { return lastStudyLocation }
        let itemIDs = Set(courseItems(in: courseID).map(\.id))
        return studyLocationsByItemID.values
            .filter { itemIDs.contains($0.itemID) }
            .max { $0.lastStudiedAt < $1.lastStudiedAt }
    }

    private func applyLearningUpdate(
        _ update: StudyAgentLearningUpdate?,
        expectedContextRevision: String,
        expectedMemoryRevision: UInt64,
        expectedUserQuestion: String,
        target: AgentConversationTarget,
        messageID: UUID
    ) -> AgentReplyMemoryUpdate? {
        if activeStudySessionID == target.sessionID {
            latestAgentLearningUpdate = nil
        }
        guard target.courseID.map({ activeCourseRemovalTokens[$0] == nil }) ?? true,
              let update,
              update.contextRevision == expectedContextRevision,
              update.memoryRevision == expectedMemoryRevision,
              learningMemoryContextRevision(courseID: target.courseID)
                == expectedMemoryRevision,
              update.entries.count <= 12,
              update.resolutions.count <= 12 else { return nil }

        let scopes = learningMemoryContextScopes(courseID: target.courseID)
        var entriesByScope = Dictionary(
            uniqueKeysWithValues: scopes.map { ($0, learningMemoryEntries(in: $0)) }
        )
        func locatedMemory(_ id: UUID) -> (LearningMemoryScope, Int, LearningMemoryEntry)? {
            for scope in scopes {
                if let index = entriesByScope[scope]?.firstIndex(where: { $0.id == id }),
                   let entry = entriesByScope[scope]?[index] {
                    return (scope, index, entry)
                }
            }
            return nil
        }
        var validatedEntries: [(
            proposal: StudyAgentMemoryUpdateEntry,
            memoryID: UUID?,
            scope: LearningMemoryScope,
            text: String,
            evidence: String,
            origin: LearningMemoryOrigin
        )] = []
        var entryTargetIDs: Set<UUID> = []
        for proposal in update.entries {
            let text = proposal.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidence = proposal.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !evidence.isEmpty else { return nil }
            if evidence.hasPrefix("[用户：本轮]") || evidence.hasPrefix("[会话：当前]") {
                guard StudyAgentCurrentTurnEvidence.matches(
                    evidence,
                    question: expectedUserQuestion
                ) else { return nil }
            }
            if proposal.origin == .userStatement {
                guard evidence.hasPrefix("[用户：本轮]") else { return nil }
            }
            let memoryID: UUID?
            let scope: LearningMemoryScope
            if let rawMemoryID = proposal.memoryID {
                guard let parsedMemoryID = UUID(uuidString: rawMemoryID),
                      entryTargetIDs.insert(parsedMemoryID).inserted,
                      let located = locatedMemory(parsedMemoryID),
                      located.2.status == .active,
                      located.0 == learningMemoryScope(
                          for: proposal.kind,
                          courseID: target.courseID
                      ) else {
                    return nil
                }
                if located.2.origin == .userStatement,
                   !evidence.hasPrefix("[用户：本轮]"),
                   !evidence.hasPrefix("[会话：当前]") {
                    return nil
                }
                memoryID = parsedMemoryID
                scope = located.0
            } else {
                memoryID = nil
                scope = learningMemoryScope(
                    for: proposal.kind,
                    courseID: target.courseID
                )
            }
            validatedEntries.append(
                (
                    proposal,
                    memoryID,
                    scope,
                    String(text.prefix(500)),
                    String(evidence.prefix(400)),
                    proposal.origin == .observed ? .agentInference : proposal.origin
                )
            )
        }

        var validatedResolutions: [(
            memoryID: UUID,
            scope: LearningMemoryScope,
            evidence: String
        )] = []
        var resolutionTargetIDs: Set<UUID> = []
        for proposal in update.resolutions {
            let evidence = proposal.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard StudyAgentCurrentTurnEvidence.matches(
                evidence,
                question: expectedUserQuestion
            ),
            let memoryID = UUID(uuidString: proposal.memoryID),
            resolutionTargetIDs.insert(memoryID).inserted,
            let located = locatedMemory(memoryID),
            located.2.status == .active,
            located.2.kind == .goal
                || located.2.kind == .confusion
                || located.2.kind == .nextStep else {
                return nil
            }
            validatedResolutions.append(
                (
                    memoryID,
                    located.0,
                    String(evidence.prefix(400))
                )
            )
        }

        var sessionChanged = false
        var changedMemoryIDs: [UUID] = []
        var changedMemoryIDsByScope: [LearningMemoryScope: Set<UUID>] = [:]
        var acceptedEntries: [StudyAgentMemoryUpdateEntry] = []
        let now = Date()
        for validated in validatedEntries {
            var memoryEntries = entriesByScope[validated.scope] ?? []
            if let memoryID = validated.memoryID,
               let index = memoryEntries.firstIndex(where: { $0.id == memoryID }) {
                let origin: LearningMemoryOrigin = validated.evidence
                    .hasPrefix("[用户：本轮]")
                    ? .userStatement
                    : validated.origin
                guard memoryEntries[index].kind != validated.proposal.kind
                        || memoryEntries[index].text != validated.text
                        || memoryEntries[index].evidence != validated.evidence
                        || memoryEntries[index].origin != origin else {
                    continue
                }
                memoryEntries[index].kind = validated.proposal.kind
                memoryEntries[index].text = validated.text
                memoryEntries[index].evidence = validated.evidence
                memoryEntries[index].origin = origin
                memoryEntries[index].sessionID = target.sessionID
                memoryEntries[index].messageID = messageID
                memoryEntries[index].updatedAt = now
                changedMemoryIDs.append(memoryID)
                changedMemoryIDsByScope[validated.scope, default: []].insert(memoryID)
                acceptedEntries.append(
                    StudyAgentMemoryUpdateEntry(
                        memoryID: memoryID.uuidString.lowercased(),
                        kind: memoryEntries[index].kind,
                        text: memoryEntries[index].text,
                        evidence: memoryEntries[index].evidence,
                        origin: memoryEntries[index].origin
                    )
                )
            } else {
                let normalized = Self.normalizedMemoryText(validated.text)
                guard !memoryEntries.contains(where: {
                    $0.kind == validated.proposal.kind
                        && $0.status == .active
                        && Self.normalizedMemoryText($0.text) == normalized
                }) else {
                    continue
                }
                let entry = LearningMemoryEntry(
                    kind: validated.proposal.kind,
                    text: validated.text,
                    evidence: validated.evidence,
                    origin: validated.origin,
                    sessionID: target.sessionID,
                    messageID: messageID,
                    createdAt: now,
                    updatedAt: now
                )
                memoryEntries.append(entry)
                changedMemoryIDs.append(entry.id)
                changedMemoryIDsByScope[validated.scope, default: []].insert(entry.id)
                acceptedEntries.append(
                    StudyAgentMemoryUpdateEntry(
                        memoryID: entry.id.uuidString.lowercased(),
                        kind: entry.kind,
                        text: entry.text,
                        evidence: entry.evidence,
                        origin: entry.origin
                    )
                )
            }
            entriesByScope[validated.scope] = memoryEntries
        }

        for validated in validatedResolutions {
            var memoryEntries = entriesByScope[validated.scope] ?? []
            guard let index = memoryEntries.firstIndex(where: {
                $0.id == validated.memoryID
            }) else { continue }
            memoryEntries[index].status = .resolved
            memoryEntries[index].resolvedAt = now
            memoryEntries[index].resolutionEvidence = validated.evidence
            memoryEntries[index].sessionID = target.sessionID
            memoryEntries[index].messageID = messageID
            memoryEntries[index].updatedAt = now
            if !changedMemoryIDs.contains(validated.memoryID) {
                changedMemoryIDs.append(validated.memoryID)
            }
            changedMemoryIDsByScope[validated.scope, default: []]
                .insert(validated.memoryID)
            entriesByScope[validated.scope] = memoryEntries
        }

        for (scope, memoryIDs) in changedMemoryIDsByScope {
            var memoryEntries = entriesByScope[scope] ?? []
            let nextRevision = learningMemoryRevision(in: scope) &+ 1
            for memoryID in memoryIDs {
                guard let index = memoryEntries.firstIndex(where: { $0.id == memoryID }) else {
                    continue
                }
                Self.appendLearningMemoryRevision(
                    to: &memoryEntries[index],
                    revision: nextRevision,
                    actor: .agent,
                    recordedAt: now
                )
            }
            if let stateIndex = learningMemoryStateIndex(
                for: scope,
                createIfMissing: true
            ) {
                learningMemoryStates[stateIndex].entries = memoryEntries
                learningMemoryStates[stateIndex].revision = nextRevision
            }
            entriesByScope[scope] = memoryEntries
        }

        if let index = studySessions.firstIndex(where: { $0.id == target.sessionID }) {
            if let summary = update.sessionSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty,
               studySessions[index].summary != String(summary.prefix(2_000)) {
                studySessions[index].summary = String(summary.prefix(2_000))
                sessionChanged = true
            }
            if !studySessions[index].flow.pinnedByUser,
               let phase = update.suggestedPhase,
               studySessions[index].flow.phase != phase {
                studySessions[index].flow.phase = phase
                sessionChanged = true
            }
            let next = update.suggestedNext
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
                .map { String($0.prefix(300)) }
            if !next.isEmpty, studySessions[index].flow.suggestedNext != next {
                studySessions[index].flow.suggestedNext = next
                sessionChanged = true
            }
            if sessionChanged {
                studySessions[index].updatedAt = now
            }
        }

        var acceptedUpdate = update
        acceptedUpdate.entries = acceptedEntries
        // A5b applies valid resolutions immediately; the persisted reply attachment
        // records the changed IDs, so the legacy confirmation strip must not ask again.
        acceptedUpdate.resolutions = []
        if activeStudySessionID == target.sessionID {
            latestAgentLearningUpdate = acceptedUpdate
            latestAgentLearningUpdateQuestion = expectedUserQuestion
        }
        guard !changedMemoryIDs.isEmpty else { return nil }
        let summary = changedMemoryIDs.compactMap { id in
            scopes.lazy.compactMap { scope in
                entriesByScope[scope]?.first(where: { $0.id == id })?.text
            }.first
        }.prefix(3).joined(separator: "；")
        return AgentReplyMemoryUpdate(
            memoryIDs: changedMemoryIDs,
            summary: summary.isEmpty
                ? ui("学习进度已更新", "Study progress updated")
                : String(summary.prefix(300))
        )
    }

    private static func appendLearningMemoryRevision(
        to entry: inout LearningMemoryEntry,
        revision: UInt64,
        actor: LearningMemoryRevisionActor,
        recordedAt: Date
    ) {
        var revisions = entry.revisions ?? []
        revisions.append(
            LearningMemoryRevisionRecord(
                revision: revision,
                kind: entry.kind,
                text: entry.text,
                evidence: entry.evidence,
                origin: entry.origin,
                status: entry.status,
                sessionID: entry.sessionID,
                messageID: entry.messageID,
                resolutionEvidence: entry.resolutionEvidence,
                actor: actor,
                recordedAt: recordedAt
            )
        )
        entry.revisions = revisions
    }

    private func applyCourseProfileUpdate(
        _ update: StudyAgentCourseProfileUpdate?,
        expectedContextRevision: String,
        expectedProfileRevision: UInt64,
        target: AgentConversationTarget
    ) {
        guard let courseID = target.courseID,
              activeCourseRemovalTokens[courseID] == nil,
              let update,
              update.contextRevision == expectedContextRevision,
              update.profileRevision == expectedProfileRevision,
              let profileIndex = courseKnowledgeProfiles.firstIndex(where: {
                  $0.courseID == courseID && $0.revision == expectedProfileRevision
              }) else { return }
        var profile = courseKnowledgeProfiles[profileIndex]
        let existingIDs = Set(profile.entries.map(\.id))
        let removedIDs = Set(update.removedEntryIDs.compactMap(UUID.init(uuidString:)))
        guard removedIDs.count == update.removedEntryIDs.count,
              removedIDs.isSubset(of: existingIDs) else { return }
        let itemsByID = Dictionary(
            uniqueKeysWithValues: courseItems(in: courseID).map { ($0.id, $0) }
        )

        var targetIDs = Set<UUID>()
        var replacements: [(UUID?, CourseKnowledgeProfileEntry)] = []
        let now = Date()
        for proposal in update.entries {
            let entryID = proposal.entryID.flatMap(UUID.init(uuidString:))
            guard proposal.entryID == nil || entryID != nil,
                  entryID.map(existingIDs.contains) ?? true,
                  entryID.map({ targetIDs.insert($0).inserted }) ?? true else { return }
            var sources: [CourseKnowledgeProfileSource] = []
            for source in proposal.sources {
                guard let item = itemsByID[source.itemID],
                (item.isNotebookNote ? "note" : "material") == source.role else { return }
                let revision = item.isNotebookNote
                    ? loadedAgentNoteText(for: item).map(
                        CourseDocumentSearchIndex.sourceRevision(forMarkdown:)
                    )
                    : CourseDocumentSearchIndex.sourceRevision(for: item)
                guard revision == source.sourceRevision else { return }
                sources.append(
                    CourseKnowledgeProfileSource(
                        itemID: source.itemID,
                        role: item.isNotebookNote ? .note : .material,
                        location: source.location,
                        sourceRevision: source.sourceRevision
                    )
                )
            }
            guard !sources.isEmpty else { return }
            let existing = entryID.flatMap { id in
                profile.entries.first(where: { $0.id == id })
            }
            replacements.append(
                (
                    entryID,
                    CourseKnowledgeProfileEntry(
                        id: entryID ?? UUID(),
                        kind: proposal.kind,
                        text: String(proposal.text.prefix(1_200)),
                        sources: sources,
                        createdAt: existing?.createdAt ?? now,
                        updatedAt: now
                    )
                )
            )
        }

        profile.entries.removeAll { removedIDs.contains($0.id) }
        for (entryID, replacement) in replacements {
            if let entryID,
               let index = profile.entries.firstIndex(where: { $0.id == entryID }) {
                profile.entries[index] = replacement
            } else {
                profile.entries.append(replacement)
            }
        }
        guard profile.entries.count <= 200 else { return }
        guard profile.entries != courseKnowledgeProfiles[profileIndex].entries else { return }
        profile.overview = profile.entries
            .filter { $0.kind == .overview }
            .max(by: { $0.updatedAt < $1.updatedAt })?.text ?? ""
        profile.revision &+= 1
        profile.updatedAt = now
        courseKnowledgeProfiles[profileIndex] = profile
        dirtyPortableCourseIDs.insert(courseID)
    }

    func isLearningMemoryResolved(
        _ memoryID: String,
        in scope: LearningMemoryScope
    ) -> Bool {
        guard let id = UUID(uuidString: memoryID) else { return false }
        return learningMemoryEntries(in: scope)
            .first(where: { $0.id == id })?
            .status == .resolved
    }

    func confirmLearningMemoryResolution(
        _ resolution: StudyAgentMemoryResolution,
        in scope: LearningMemoryScope
    ) {
        guard latestAgentLearningUpdate?.resolutions.contains(resolution) == true,
              let question = latestAgentLearningUpdateQuestion,
              StudyAgentCurrentTurnEvidence.matches(resolution.evidence, question: question),
              let memoryID = UUID(uuidString: resolution.memoryID) else { return }
        setLearningMemoryStatus(
            memoryID,
            in: scope,
            status: .resolved,
            resolutionEvidence: String(resolution.evidence.prefix(400))
        )
    }

    func updateLearningMemory(
        _ memoryID: UUID,
        in scope: LearningMemoryScope,
        kind: LearningMemoryKind,
        text rawText: String
    ) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scope.courseID.map({
            activeCourseRemovalTokens[$0] == nil
        }) ?? true,
        !text.isEmpty,
              text.count <= 500,
              let stateIndex = learningMemoryStateIndex(for: scope, createIfMissing: false),
              let entryIndex = learningMemoryStates[stateIndex].entries.firstIndex(where: {
                  $0.id == memoryID
              }) else {
            return false
        }
        var entry = learningMemoryStates[stateIndex].entries[entryIndex]
        guard entry.kind != kind || entry.text != text else {
            return workspaceSaveError == nil || retryWorkspaceSave()
        }
        let now = Date()
        let revision = learningMemoryStates[stateIndex].revision &+ 1
        entry.kind = kind
        entry.text = text
        entry.evidence = "[用户：界面修改]"
        entry.origin = .userStatement
        entry.sessionID = nil
        entry.messageID = nil
        entry.updatedAt = now
        Self.appendLearningMemoryRevision(
            to: &entry,
            revision: revision,
            actor: .user,
            recordedAt: now
        )
        learningMemoryStates[stateIndex].entries[entryIndex] = entry
        learningMemoryStates[stateIndex].revision = revision
        invalidateAgentContext()
        return save()
    }

    func resolveLearningMemory(
        _ memoryID: UUID,
        in scope: LearningMemoryScope
    ) {
        setLearningMemoryStatus(
            memoryID,
            in: scope,
            status: .resolved,
            resolutionEvidence: "[用户：界面确认]"
        )
    }

    func restoreLearningMemory(
        _ memoryID: UUID,
        in scope: LearningMemoryScope
    ) {
        setLearningMemoryStatus(
            memoryID,
            in: scope,
            status: .active,
            resolutionEvidence: nil
        )
    }

    private func setLearningMemoryStatus(
        _ memoryID: UUID,
        in scope: LearningMemoryScope,
        status: LearningMemoryStatus,
        resolutionEvidence: String?
    ) {
        guard scope.courseID.map({
            activeCourseRemovalTokens[$0] == nil
        }) ?? true,
        let stateIndex = learningMemoryStateIndex(for: scope, createIfMissing: false),
              let entryIndex = learningMemoryStates[stateIndex].entries.firstIndex(where: {
                  $0.id == memoryID && $0.status != status
              }) else { return }
        let now = Date()
        let revision = learningMemoryStates[stateIndex].revision &+ 1
        var entry = learningMemoryStates[stateIndex].entries[entryIndex]
        entry.status = status
        entry.resolvedAt = status == .resolved ? now : nil
        entry.resolutionEvidence = resolutionEvidence
        entry.updatedAt = now
        Self.appendLearningMemoryRevision(
            to: &entry,
            revision: revision,
            actor: .user,
            recordedAt: now
        )
        learningMemoryStates[stateIndex].entries[entryIndex] = entry
        learningMemoryStates[stateIndex].revision = revision
        invalidateAgentContext()
        save()
    }

    func restoreLearningMemoryResolution(
        _ resolution: StudyAgentMemoryResolution,
        in scope: LearningMemoryScope
    ) {
        guard latestAgentLearningUpdate?.resolutions.contains(resolution) == true,
              let memoryID = UUID(uuidString: resolution.memoryID) else { return }
        restoreLearningMemory(memoryID, in: scope)
    }

    private static func normalizedMemoryText(_ text: String) -> String {
        text
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined()
    }

    func askToOrganizeNote() {
        agentDraft = ui(
            "请根据\(agentPromptScope)，把笔记整理成更清晰的大纲，保留来源信息，并标出缺少证据的位置。",
            "Use \(agentPromptScope) to organize the note into a clearer outline, keep source references, and mark places where evidence is missing."
        )
        submitAgentDraft()
    }

    func askSelection() {
        if let selectionContext {
            // Expand the floating selection agent into a normal chat composer.
            // Do NOT invent a prompt or auto-send — user writes and sends themselves.
            withAnimation(WeiBeiMotion.panel) {
                cancelPendingSelectionAttachment()
                addSelectionAttachment(selectionContext)
                floatingSelectionPrompt = selectionContext.label(language: interfaceLanguage)
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
                let thread = beginOrReuseSelectionAskThread(for: context)
                activeSelectionAskThreadID = thread.id
            }
            // Prefer keeping float if user is mid answer; otherwise collapse into chat.
            if !keepFloatingSelectionForAnswer, agentSurface == .selectionFloat {
                agentSurface = .hidden
                pinnedFloatingAgent = false
            }
            if !keepFloatingSelectionForAnswer {
                selectionAnchor = nil
            }
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
                itemID: thread.itemID,
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
        let itemID = selection.itemID
            ?? (selection.source == .note ? activeNotebookItemID : selectedItemID)
        if let index = selectionAskThreads.firstIndex(where: {
            $0.normalizedText == normalized
                && $0.source == selection.source
                && ($0.itemID == nil || $0.itemID == itemID || itemID == nil)
        }) {
            selectionAskThreads[index].updatedAt = Date()
            selectionAskThreads[index].itemID = selectionAskThreads[index].itemID ?? itemID
            save()
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
        save()
        return thread
    }

    func appendMessageToActiveSelectionAskThread(_ messageID: UUID) {
        guard let threadID = activeSelectionAskThreadID,
              let index = selectionAskThreads.firstIndex(where: { $0.id == threadID }) else { return }
        if !selectionAskThreads[index].messageIDs.contains(messageID) {
            selectionAskThreads[index].messageIDs.append(messageID)
            selectionAskThreads[index].updatedAt = Date()
            save()
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

    private func loadLegacySelectionAskThreadsIfWorkspaceFieldMissing() {
        guard !loadedSelectionAskThreadsFromWorkspaceSnapshot else { return }
        needsSelectionAskThreadsWorkspaceMigration = true
        if let legacyData = selectionAskThreadDefaults.data(
            forKey: Self.legacySelectionAskThreadsDefaultsKey
        ), let legacyThreads = try? JSONDecoder().decode(
            [SelectionAskThread].self,
            from: legacyData
        ) {
            selectionAskThreads = legacyThreads
        } else {
            selectionAskThreads = []
        }
        shouldRemoveLegacySelectionAskThreadsAfterSave =
            selectionAskThreadDefaults.object(forKey: Self.legacySelectionAskThreadsDefaultsKey) != nil
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

    func applyLastAgentAnswerToNote() {
        guard let content = lastAgentAnswerContentForCurrentNote() else { return }
        let block = "\n\n\(noteBlockForAgentAnswer(content))"
        updateNote(noteText + block)
        focus(.notes)
    }


    func replaceSelectionWithLastAgentAnswer() {
        guard selectionContext?.isReplaceableNoteSelection == true,
              let content = lastAgentAnswerContentForCurrentNote() else { return }
        noteEditorCommand = NoteEditorCommand(
            kind: .replaceSelection,
            markdown: content
        )
        focus(.notes)
    }

    func applyAgentPatchToEditor() {
        guard let content = lastAgentAnswerContentForCurrentNote() else { return }
        noteEditorCommand = NoteEditorCommand(kind: .applyAgentPatch, markdown: "\n\(noteBlockForAgentAnswer(content))")
        focus(.notes)
    }

    private func lastAgentAnswerContentForCurrentNote() -> String? {
        lastUsableAgentAnswer?.text
    }

    private func noteBlockForAgentAnswer(_ answer: String) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.hasPrefix("#") else { return text }
        return "## \(ui("整理建议", "Organization suggestion"))\n\(text)"
    }

    func submitAgentDraft() {
        if isAgentRunningInActiveChat {
            cancelAgentRequest()
            return
        }
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStoppingAgent else { return }
        if isAskingAgent {
            pendingAgentSwitchTargetID = activeStudySessionID
            isAgentSwitchConfirmationPresented = true
            return
        }
        askAgent()
    }

    func dismissAgentSwitchConfirmation() {
        isAgentSwitchConfirmationPresented = false
        pendingAgentSwitchTargetID = nil
    }

    func confirmAgentSwitchAndSend() {
        guard isAgentSwitchConfirmationPresented,
              let targetID = pendingAgentSwitchTargetID,
              activeStudySessionID == targetID,
              !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dismissAgentSwitchConfirmation()
        stopAgent(restoreDraft: false) { [weak self] in
            guard let self,
                  self.activeStudySessionID == targetID,
                  self.studySessions.contains(where: { $0.id == targetID }),
                  !self.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.askAgent()
        }
    }

    func askAgent(
        reusingLastUserMessage: Bool = false,
        replayingSelections: [SelectionContext]? = nil,
        replayingCourseID: UUID? = nil
    ) {
        flushStagedNoteDraftForAgentContext()
        guard agentRequestTask == nil,
              !isStoppingAgent,
              !isAskingAgent,
              !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: AgentConversationTarget
        do {
            if reusingLastUserMessage, let session = activeStudySession {
                target = try makeAgentConversationTarget(
                    sessionID: session.id,
                    courseID: replayingCourseID
                )
            } else {
                target = try agentConversationTarget()
            }
        } catch {
            recordAgentTargetFailure(
                question: question,
                error: error,
                appendUserMessage: !reusingLastUserMessage
            )
            return
        }
        agentRequestTask = Task { @MainActor [weak self] in
            await self?.performAgentRequest(
                target: target,
                reusingLastUserMessage: reusingLastUserMessage,
                replayingSelections: replayingSelections
            )
        }
    }

    private func agentConversationTarget() throws -> AgentConversationTarget {
        guard let session = activeStudySession else {
            throw AgentConversationTargetError(
                message: ui(
                    "当前 Chat 尚未准备完成，请重新打开后再试。",
                    "The current Chat is not ready. Reopen it and try again."
                )
            )
        }
        return try makeAgentConversationTarget(
            sessionID: session.id,
            courseID: currentAgentFocusCourseID
        )
    }

    private var currentAgentFocusCourseID: UUID? {
        let focusedItemIDs = currentAgentSelections().compactMap(\.itemID)
            + [selectedMaterialItem?.id, activeNoteItem?.id].compactMap { $0 }
        let focusedCourseIDs = Set(
            focusedItemIDs.flatMap { courseMembershipIndex.courseIDs(for: $0) }
        )
        if let activeCourseID, focusedCourseIDs.contains(activeCourseID) {
            return activeCourseID
        }
        if let first = focusedCourseIDs.sorted(by: { $0.uuidString < $1.uuidString }).first {
            return first
        }
        guard let activeCourseID,
              courses.contains(where: { $0.id == activeCourseID }) else { return nil }
        return activeCourseID
    }

    private func makeAgentConversationTarget(
        sessionID: UUID,
        courseID: UUID?
    ) throws -> AgentConversationTarget {
        let course = courseID.flatMap { self.course(withID: $0) }
        if let courseID {
            guard activeCourseRemovalTokens[courseID] == nil,
                  course != nil else {
                throw AgentConversationTargetError(
                    message: ui(
                        "这门课程已经不存在，魏碑没有把问题发到其他范围。",
                        "This course no longer exists. WeiBei did not send the question to another scope."
                    )
                )
            }
        }
        let runtimeDirectory = workspaceDirectory
            .appendingPathComponent("AgentRuntime/Chats", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: runtimeDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: runtimeDirectory.path
            )
        } catch {
            throw AgentConversationTargetError(
                message: ui(
                    "魏碑无法准备 Chat 的本地工作目录，请检查本机存储空间和文件权限。",
                    "WeiBei could not prepare the Chat workspace. Check local storage and file permissions."
                )
            )
        }
        let verifiedCourseRoot: URL?
        let verifiedCourseIdentity: ImportedFileIdentity?
        if let courseID,
           let expectedIdentity = course?.sourceRootIdentity,
           let root = courseRootURL(for: courseID),
           let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(root),
           importedFileIdentityResolver(resolvedRoot) == expectedIdentity {
            verifiedCourseRoot = resolvedRoot
            verifiedCourseIdentity = expectedIdentity
        } else {
            verifiedCourseRoot = nil
            verifiedCourseIdentity = nil
        }
        return AgentConversationTarget(
            sessionID: sessionID,
            workingDirectory: runtimeDirectory,
            courseID: courseID,
            courseRootURL: verifiedCourseRoot,
            courseRootIdentity: verifiedCourseIdentity
        )
    }

    private func validateAgentConversationTarget(
        _ target: AgentConversationTarget,
        mustBeActive: Bool
    ) throws {
        guard studySessions.contains(where: { $0.id == target.sessionID }),
              (!mustBeActive || activeStudySessionID == target.sessionID) else {
            throw AgentConversationTargetError(
                message: ui(
                    mustBeActive
                        ? "发送前 Chat 已经切换，这条问题没有发到其他 Chat。"
                        : "原 Chat 已不存在，这条回答没有写到其他 Chat。",
                    mustBeActive
                        ? "The Chat changed before sending. This question was not sent to another Chat."
                        : "The original Chat no longer exists. This reply was not written to another Chat."
                )
            )
        }
        guard let courseID = target.courseID else { return }
        guard activeCourseRemovalTokens[courseID] == nil,
              course(withID: courseID) != nil else {
            throw AgentConversationTargetError(
                message: ui(
                    "原课程已不存在，这条回答没有写到其他课程。",
                    "The original course no longer exists. This reply was not written to another course."
                )
            )
        }
    }

    private func recordAgentTargetFailure(
        question: String,
        error: Error,
        appendUserMessage: Bool = true
    ) {
        ensureActiveStudySession()
        guard let session = activeStudySession else { return }
        let requestID = UUID()
        let sourceTitle = agentMessageSourceTitle
        lastAgentFailureKind = .generic
        lastFailedAgentQuestion = question
        agentDraftsBySessionID[session.id] = question
        focusedPane = .agent
        if appendUserMessage {
            let userMessage = AgentMessage(role: .user, text: question, source: sourceTitle)
            appendAgentMessage(userMessage)
            appendMessageToActiveSelectionAskThread(userMessage.id)
        }
        let assistantMessage = AgentMessage(
            role: .assistant,
            text: AgentFailureKind.generic.userMessage(
                language: interfaceLanguage,
                userFacingDetail: Self.userFacingAgentFailureDetail(for: error),
                draftPreserved: true
            ),
            source: sourceTitle,
            completionState: .interrupted,
            origin: AgentReplyOrigin(
                requestID: requestID,
                chatID: session.id,
                courseID: session.courseID
            ),
            failureKind: .generic,
            retryQuestion: question
        )
        appendAgentMessage(assistantMessage)
        appendMessageToActiveSelectionAskThread(assistantMessage.id)
        _ = flushPendingWorkspaceSave()
    }

    private func askAgentAndWait() async {
        askAgent()
        await agentRequestTask?.value
    }

    private func currentVisualAssetsForAgent(
        access: AgentProjectAccessSnapshot
    ) async -> [StudyAgentVisualAsset] {
        guard let item = selectedMaterialItem,
              !item.isNotebookNote,
              let source = access.sources.first(where: { $0.item.id == item.id }),
              Self.agentHostToolSourceIsValid(source),
              let sourceURL = source.grants.first(where: Self.agentFileGrantIsValid)?
                .targetURL ?? source.item.url else {
            return []
        }
        let mediaType: String
        switch sourceURL.pathExtension.lowercased() {
        case "jpg", "jpeg":
            mediaType = "image/jpeg"
        case "png":
            mediaType = "image/png"
        case "webp":
            mediaType = "image/webp"
        default:
            return []
        }
        let searchIndex = courseDocumentSearchIndex
        let snapshot = await Task.detached(priority: .userInitiated) {
            searchIndex.verifiedSnapshot(of: source.item, maximumBytes: 6_000_000)
        }.value
        guard let snapshot, Self.agentHostToolSourceIsValid(source) else {
            if let snapshot {
                try? FileManager.default.removeItem(at: snapshot)
            }
            return []
        }
        return [
            StudyAgentVisualAsset(
                id: item.id,
                filePath: snapshot.path,
                mediaType: mediaType
            ),
        ]
    }

    private static func removeAgentVisualSnapshots(
        _ assets: [StudyAgentVisualAsset]
    ) {
        assets.forEach {
            try? FileManager.default.removeItem(atPath: $0.filePath)
        }
    }

    private func performAgentRequest(
        target: AgentConversationTarget,
        reusingLastUserMessage: Bool = false,
        replayingSelections: [SelectionContext]? = nil
    ) async {
        guard !Task.isCancelled, activeStudySessionID == target.sessionID else {
            agentRequestTask = nil
            return
        }
        flushStagedNoteDraftForAgentContext()
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAskingAgent else {
            agentRequestTask = nil
            return
        }
        let requestProvider = agentProviderID
        let requestAuthMethod = agentAuthMethod
        if reusingLastUserMessage {
            guard let userMessage = messages.last,
                  userMessage.role == .user,
                  userMessage.text.trimmingCharacters(in: .whitespacesAndNewlines) == question else {
                agentRequestTask = nil
                return
            }
        }
        do {
            try validateAgentConversationTarget(target, mustBeActive: true)
        } catch {
            recordAgentTargetFailure(
                question: question,
                error: error,
                appendUserMessage: !reusingLastUserMessage
            )
            agentRequestTask = nil
            return
        }

        persistCurrentNote()
        // Ensure live document selection is attached before we snapshot context for the request.
        if replayingSelections == nil,
           selectionAttachments.isEmpty,
           let selectionContext,
           !selectionContext.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addSelectionAttachment(selectionContext)
        }
        let projectAccess = makeAgentProjectAccessSnapshot(target: target)
        let allowedItemIDs = Set(projectAccess.sources.map(\.item.id))
        // Focus materials/notes do not require project-file grants (legacyExternal etc.).
        let replayMaterialItemID = replayingSelections?
            .first(where: { $0.source == .document })?
            .itemID
        let replayNoteItemID = replayingSelections?
            .first(where: { $0.source == .note })?
            .itemID
        let sentMaterialItem = replayMaterialItemID
            .flatMap { itemID in allItems.first(where: { $0.id == itemID }) }
            ?? agentFocusMaterialItem(for: target)
        let sentNoteItem = replayNoteItemID
            .flatMap { itemID in allItems.first(where: { $0.id == itemID }) }
            ?? agentFocusNoteItem(for: target)
        let focusAllowedItemIDs = allowedItemIDs.union(
            [sentMaterialItem?.id, sentNoteItem?.id].compactMap { $0 }
        ).union(
            (replayingSelections ?? []).compactMap(\.itemID)
        )
        let sentSelections = replayingSelections.map { selections in
            selections.filter { selection in
                guard !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let itemID = selection.itemID else { return false }
                return focusAllowedItemIDs.contains(itemID)
            }
        } ?? currentAgentSelections(allowedItemIDs: focusAllowedItemIDs)
        let sentSelectionTitle = agentSelectionTitle(from: sentSelections)
        let sentSelectionText = agentSelectionText(from: sentSelections)
        let sentSelectionSources = agentSelectionSources(from: sentSelections)
        let sentSelectionIDs = Set(sentSelections.map(\.id))
        associateStudySession(
            target.sessionID,
            withItemIDs: sentSelections.compactMap(\.itemID)
        )
        let shouldClearSentDocumentSelection = sentSelections.contains {
            $0.id == selectionContext?.id && $0.source == .document
        }
        let sourceTitle = sentMaterialItem != nil
            ? currentSourceReferenceTitle
            : sentNoteItem.map(displayTitle)
        let requestID = UUID()
        let requestWorkspaceRevision = agentContextRevision
        let requestMemoryRevision = learningMemoryContextRevision(
            courseID: target.courseID
        )
        let sentMaterialTitle = sentMaterialItem == nil
            ? ui("未选择材料", "No material selected")
            : currentSourceReferenceTitle
        let sentMaterialItemID = sentMaterialItem?.id
        let sentNoteTitle = sentNoteItem == nil
            ? ui("当前笔记", "Current Note")
            : agentNoteTitle
        let sentNoteText = sentNoteItem.flatMap { note in
            projectAccess.sources.first(where: { $0.item.id == note.id })?.memoryText
                ?? loadedAgentNoteText(for: note)
        } ?? ""
        let sentNoteItemID = sentNoteItem?.id
        associateStudySession(
            target.sessionID,
            withItemIDs: [sentMaterialItemID, sentNoteItemID]
                .compactMap { $0 }
        )
        let sentLearningContext = makeLearningContext(target: target)
        let sentCourseProfile = makeCourseProfileContext(
            courseID: target.courseID,
            access: projectAccess
        )
        let sentVisualAssets = await currentVisualAssetsForAgent(access: projectAccess)
        defer { Self.removeAgentVisualSnapshots(sentVisualAssets) }
        let sentLanguage = interfaceLanguage
        let courseQuery = [question, sentSelectionText ?? ""]
            .joined(separator: "\n\n")
        isAskingAgent = true
        activeAgentRequestID = requestID
        latestAgentStreamingText = ""
        lastAgentStreamingPublishNanoseconds = 0
        agentStreamingText = ""
        agentActivityText = ui("正在准备课程现场", "Preparing course context")
        defer {
            if activeAgentRequestID == requestID {
                activeAgentRequestID = nil
                activeAgentReplyMessageID = nil
                activeAgentReplyChatID = nil
                isAskingAgent = false
                latestAgentStreamingText = ""
                lastAgentStreamingPublishNanoseconds = 0
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

        var didAppendUserMessage = reusingLastUserMessage
        var replyMessageID: UUID?
        var didStartModelRequest = false
        do {
            if !reusingLastUserMessage {
                let userMessage = AgentMessage(role: .user, text: question, source: sourceTitle)
                appendAgentMessage(userMessage)
                appendMessageToActiveSelectionAskThread(userMessage.id)
                didAppendUserMessage = true
            }
            if let courseID = target.courseID {
                _ = captureCourseResumePoint(
                    courseID: courseID,
                    chatID: target.sessionID
                )
            }
            // Must not call flushPendingWorkspaceSave() here: that spins RunLoop on the
            // MainActor while waiting for another MainActor Task, which deadlocks UI.
            guard await flushPendingWorkspaceSaveAsync() else {
                throw AgentConversationTargetError(
                    message: ui(
                        "问题尚未安全写入本地，魏碑没有把它发送给 Agent。",
                        "The question was not safely saved, so WeiBei did not send it to the Agent."
                    )
                )
            }

            let assistantMessage = AgentMessage(
                role: .assistant,
                text: "",
                source: sourceTitle,
                backend: .pi,
                completionState: .generating,
                origin: AgentReplyOrigin(
                    requestID: requestID,
                    chatID: target.sessionID,
                    courseID: target.courseID
                ),
                retryQuestion: question
            )
            replyMessageID = assistantMessage.id
            activeAgentReplyMessageID = assistantMessage.id
            activeAgentReplyChatID = target.sessionID
            appendAgentMessage(assistantMessage)
            appendMessageToActiveSelectionAskThread(assistantMessage.id)
            guard await flushPendingWorkspaceSaveAsync() else {
                throw AgentConversationTargetError(
                    message: ui(
                        "回答状态尚未安全写入本地，魏碑没有继续请求 Agent。",
                        "The reply state was not saved safely, so WeiBei did not continue the request."
                    )
                )
            }

            agentDraft = ""
            agentDraftsBySessionID[target.sessionID] = ""
            lastFailedAgentQuestion = nil
            lastAgentFailureKind = nil
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            if !sentSelectionIDs.isEmpty {
                // No withAnimation here: animating attachment chrome while chat
                // PlatformViews remasure was part of the send-path main-thread freeze.
                cancelPendingSelectionAttachment()
                selectionAttachments.removeAll { sentSelectionIDs.contains($0.id) }
                if selectionAttachments.isEmpty {
                    lastSelectionAttachmentDate = nil
                    lastSelectionUpdateDate = nil
                }
            }
            // Keep the floating selection agent open while answering — do not dismiss it mid-stream.
            if isConversationSurfaceVisible {
                agentSurface = .hidden
                keepFloatingSelectionForAnswer = false
                if shouldClearSentDocumentSelection, !pinnedFloatingAgent {
                    clearUnpinnedFloatingSelection(keepContext: false, invalidatesAgentContext: false)
                }
            } else if shouldClearSentDocumentSelection,
                      !keepFloatingSelectionForAnswer,
                      !pinnedFloatingAgent {
                clearUnpinnedFloatingSelection(
                    keepContext: false,
                    invalidatesAgentContext: false
                )
            } else if keepFloatingSelectionForAnswer || pinnedFloatingAgent {
                agentSurface = .selectionFloat
                pinnedFloatingAgent = true
            }

            let courseBuild = try await makeCourseContext(
                query: courseQuery,
                courseID: target.courseID,
                access: projectAccess,
                focusMaterialItem: sentMaterialItem,
                focusNoteItem: sentNoteItem
            )
            guard activeAgentRequestID == requestID else { return }
            try validateAgentConversationTarget(target, mustBeActive: false)
            let hostToolHandler = makeAgentHostToolHandler(
                target: target,
                access: projectAccess
            )
            let sourceReference = SourceReferenceTitle.parse(sentMaterialTitle)
            let request = StudyAgentRequest(
                id: requestID,
                purpose: .conversation,
                question: question,
                materialTitle: sentMaterialTitle,
                materialText: "",
                materialIsTruncated: false,
                noteTitle: sentNoteTitle,
                noteText: "",
                selectionTitle: sentSelectionTitle,
                selectionText: sentSelectionText,
                selectionSources: sentSelectionSources,
                courseContext: courseBuild.context,
                projectScope: projectAccess.scope,
                focus: StudyAgentFocus(
                    chatID: target.sessionID.uuidString.lowercased(),
                    courseID: target.courseID?.uuidString.lowercased(),
                    materialItemID: sentMaterialItemID,
                    materialTitle: sentMaterialItem.map(displayTitle),
                    pageIndex: sourceReference.pageIndex,
                    sectionTitle: sourceReference.sectionTitle,
                    sectionLocationID: sourceReference.sectionLocationID,
                    sectionOrdinal: sourceReference.sectionOrdinal,
                    selectionText: sentSelectionText,
                    actionSource: sentSelectionText == nil
                        ? (sentMaterialItem == nil ? "chat" : "reader")
                        : "selection"
                ),
                visualAssets: sentVisualAssets,
                learningContext: sentLearningContext,
                courseProfile: sentCourseProfile,
                language: sentLanguage,
                contextRevision: "\(requestWorkspaceRevision):\(requestID.uuidString.lowercased())"
            )
            agentActivityText = ui("正在思考", "Thinking")
            didStartModelRequest = true
            let reply = try await executeStudyAgentRequest(
                request,
                provider: requestProvider,
                target: target,
                replyMessageID: assistantMessage.id,
                hostToolHandler: hostToolHandler
            )
            guard activeAgentRequestID == request.id else { return }
            recordAgentAuthenticationSuccess(
                provider: requestProvider,
                authMethod: requestAuthMethod
            )
            try validateAgentConversationTarget(target, mustBeActive: false)
            if activeStudySessionID == target.sessionID {
                latestAgentNoteProposal = reply.noteProposal
            }
            let memoryUpdate = applyLearningUpdate(
                reply.learningUpdate,
                expectedContextRevision: request.contextRevision,
                expectedMemoryRevision: requestMemoryRevision,
                expectedUserQuestion: request.question,
                target: target,
                messageID: assistantMessage.id
            )
            applyCourseProfileUpdate(
                reply.courseProfileUpdate,
                expectedContextRevision: request.contextRevision,
                expectedProfileRevision: sentCourseProfile.revision,
                target: target
            )
            if activeStudySessionID == target.sessionID {
                lastAgentReplyContextRevision = requestWorkspaceRevision
            }
            var actions: [AgentReplyAction] = []
            if let proposal = reply.noteProposal,
               let sentNoteItemID {
                actions.append(
                    AgentReplyAction(
                        kind: .writeNote,
                        targetItemID: sentNoteItemID,
                        sourceItemID: sentMaterialItemID,
                        proposedMarkdown: proposal.markdown,
                        evidence: proposal.evidence,
                        contextRevision: proposal.contextRevision,
                        baselineContentDigest: Self.noteContentDigest(
                            Data(sentNoteText.utf8)
                        )
                    )
                )
            }
            if let proposal = reply.relationProposal {
                actions.append(
                    AgentReplyAction(
                        kind: .createRelation,
                        targetItemID: proposal.noteItemID,
                        sourceItemID: proposal.sourceItemID,
                        contextRevision: proposal.contextRevision
                    )
                )
            }
            let sources = reply.sources
            if let messageID = replyMessageID {
                _ = updateAgentMessage(messageID, in: target.sessionID) {
                    $0.text = reply.text
                    $0.backend = reply.backend
                    $0.richAnswer = reply.richAnswer
                    $0.completionState = .completed
                    $0.sources = sources
                    $0.actions = actions
                    $0.memoryUpdate = memoryUpdate
                    $0.failureKind = nil
                    $0.retryQuestion = nil
                    $0.toolTrace = reply.toolTrace
                }
            }
            associateStudySession(
                target.sessionID,
                with: sources.compactMap(\.courseID)
            )
            associateStudySession(
                target.sessionID,
                withItemIDs: sources.compactMap(\.itemID)
            )
            associateStudySession(
                target.sessionID,
                withItemIDs: reply.readItemIDs
            )
            // The visible reply is durable before this request is considered finished.
            // A save error must not replace or hide the answer that already arrived.
            _ = await flushPendingWorkspaceSaveAsync()
        } catch PiAgentRuntimeError.cancelled, is CancellationError {
            guard activeAgentRequestID == requestID else { return }
            if let replyMessageID {
                interruptAgentReply(
                    requestID: requestID,
                    messageID: replyMessageID,
                    chatID: target.sessionID,
                    kind: .cancelled
                )
            }
            agentDraftsBySessionID[target.sessionID] = question
            if activeStudySessionID == target.sessionID,
               agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentDraft = question
                lastAgentFailureKind = .cancelled
            }
            return
        } catch {
            guard activeAgentRequestID == requestID else { return }
            if !didAppendUserMessage {
                appendAgentMessage(AgentMessage(role: .user, text: question, source: sourceTitle))
            }
            // Always restore the failed question so composer matches the failure copy.
            let kind = AgentFailureKind.classify(error)
            if didStartModelRequest {
                agentAuthenticationStatus.recordFailure(
                    kind,
                    provider: requestProvider,
                    authMethod: requestAuthMethod
                )
            }
            agentDraftsBySessionID[target.sessionID] = question
            if activeStudySessionID == target.sessionID {
                agentDraft = question
                focusedPane = .agent
                lastAgentFailureKind = kind
                lastFailedAgentQuestion = question
            }
            let failureText = kind.userMessage(
                language: interfaceLanguage,
                userFacingDetail: Self.userFacingAgentFailureDetail(for: error),
                draftPreserved: true
            )
            if let replyMessageID {
                interruptAgentReply(
                    requestID: requestID,
                    messageID: replyMessageID,
                    chatID: target.sessionID,
                    kind: kind,
                    fallbackText: failureText
                )
            } else {
                appendAgentMessage(
                    AgentMessage(
                        role: .assistant,
                        text: failureText,
                        source: sourceTitle,
                        completionState: .interrupted,
                        origin: AgentReplyOrigin(
                            requestID: requestID,
                            chatID: target.sessionID,
                            courseID: target.courseID
                        ),
                        failureKind: kind,
                        retryQuestion: question
                    )
                )
            }
            _ = await flushPendingWorkspaceSaveAsync()
        }

    }

    private func interruptAgentReply(
        requestID: UUID,
        messageID: UUID,
        chatID: UUID,
        kind: AgentFailureKind,
        fallbackText: String? = nil,
        restoreDraft: Bool = true
    ) {
        guard activeAgentRequestID == requestID,
              activeAgentReplyMessageID == messageID,
              activeAgentReplyChatID == chatID,
              studySessions.first(where: { $0.id == chatID })?
                .messages.first(where: { $0.id == messageID })?
                .completionState == .generating else { return }
        let updated = updateAgentMessage(messageID, in: chatID) {
            $0.text = Self.interruptedAgentReplyText(
                streamed: latestAgentStreamingText,
                persisted: $0.text
            )
            if $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let fallbackText {
                $0.text = fallbackText
            }
            $0.completionState = .interrupted
            $0.failureKind = kind
        }
        if restoreDraft, let question = updated?.retryQuestion {
            agentDraftsBySessionID[chatID] = question
        }
        guard activeStudySessionID == chatID else { return }
        lastAgentFailureKind = kind
        lastFailedAgentQuestion = updated?.retryQuestion
        if restoreDraft,
           agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let question = updated?.retryQuestion {
            agentDraft = question
        }
    }

    func cancelAgentRequest(restoreDraft: Bool = true) {
        stopAgent(restoreDraft: restoreDraft)
    }

    @discardableResult
    private func cancelAgentRequestIfRunning(
        in courseID: UUID,
        completion: (@MainActor () -> Void)? = nil
    ) -> Bool {
        guard let runningChatID = activeAgentReplyChatID,
              let messageID = activeAgentReplyMessageID,
              studySessions.first(where: { $0.id == runningChatID })?
                .messages.first(where: { $0.id == messageID })?
                .origin?.courseID == courseID else {
            return false
        }
        stopAgent(restoreDraft: false, completion: completion)
        return true
    }

    private func stopAgent(
        restoreDraft: Bool,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard !isStoppingAgent,
              let requestID = activeAgentRequestID,
              let messageID = activeAgentReplyMessageID,
              let chatID = activeAgentReplyChatID else { return }
        interruptAgentReply(
            requestID: requestID,
            messageID: messageID,
            chatID: chatID,
            kind: .cancelled,
            restoreDraft: restoreDraft
        )
        let requestTask = agentRequestTask
        requestTask?.cancel()
        agentRequestTask = nil
        activeAgentRequestID = nil
        activeAgentReplyMessageID = nil
        activeAgentReplyChatID = nil
        isAskingAgent = false
        isStoppingAgent = true
        latestAgentStreamingText = ""
        lastAgentStreamingPublishNanoseconds = 0
        agentStreamingText = ""
        agentActivityText = nil
        agentStopTask?.cancel()
        agentStopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.piRuntime.cancel()
            await requestTask?.value
            self.isStoppingAgent = false
            self.agentStopTask = nil
            completion?()
        }
    }

    func retryAgentRequest(_ question: String) {
        guard !isAgentRunningInActiveChat, !isStoppingAgent else { return }
        let cleaned = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        agentDraft = cleaned
        lastFailedAgentQuestion = nil
        lastAgentFailureKind = nil
        submitAgentDraft()
    }

    func regenerateLastAssistantReply() {
        guard let replyID = lastRegeneratableAgentReplyID,
              let sessionID = activeStudySessionID,
              let reply = messages.last,
              let questionMessage = messages.dropLast().last else { return }
        let question = questionMessage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let replayThread = selectionAskThreads.first {
            $0.messageIDs.contains(questionMessage.id)
        }
        let replayingSelections = replayThread.map { thread in
            [
                SelectionContext(
                    id: thread.id,
                    text: thread.selectionText,
                    source: thread.source,
                    ownerTitle: thread.ownerTitle,
                    itemID: thread.itemID,
                    isEditable: thread.source == .note
                ),
            ]
        } ?? []

        messages.removeLast()
        selectionAskThreads.indices.forEach {
            selectionAskThreads[$0].messageIDs.removeAll { $0 == replyID }
        }
        syncActiveStudySession()
        if let session = studySessions.first(where: { $0.id == sessionID }) {
            restoreAgentReplyState(from: session)
        }
        agentDraft = question
        agentDraftsBySessionID[sessionID] = question
        lastFailedAgentQuestion = nil
        lastAgentFailureKind = nil
        activeSelectionAskThreadID = replayThread?.id
        save()
        askAgent(
            reusingLastUserMessage: true,
            replayingSelections: replayingSelections,
            replayingCourseID: reply.origin?.courseID
        )
    }

    func canRetryAgentRequest(question: String?, failureKind: AgentFailureKind?) -> Bool {
        guard !isAgentRunningInActiveChat, !isStoppingAgent else { return false }
        if let failureKind, !failureKind.isRetryable { return false }
        let question = (question ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !question.isEmpty
    }

    static func isAgentFailureMessage(_ text: String) -> Bool {
        text.hasPrefix("请求失败")
            || text.hasPrefix("Agent 请求失败：")
            || text.hasPrefix("Request failed")
    }

    private func executeStudyAgentRequest(
        _ request: StudyAgentRequest,
        provider selectedProvider: AgentProviderID,
        target: AgentConversationTarget,
        replyMessageID: UUID,
        hostToolHandler: @escaping StudyAgentHostToolHandler
    ) async throws -> StudyAgentReply {
#if DEBUG
        if capturesAgentRequestForSelfCheck,
           WeiBeiSafetyTestMode.isEnabled {
            selfCheckCapturedAgentRequest = request
            return StudyAgentReply(
                text: "课程请求授权自检完成",
                backend: .pi
            )
        }
#endif
        let selectedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        await piRuntime.configure(
            PiAgentProviderConfiguration(
                provider: selectedProvider.piProviderName,
                model: selectedModel.isEmpty ? nil : selectedModel,
                baseURL: agentBaseURL.isEmpty ? nil : agentBaseURL
            )
        )
        await piRuntime.writeCustomModelsJSONIfNeeded(
            providerID: selectedProvider,
            baseURL: agentBaseURL,
            model: selectedModel
        )
        return try await piRuntime.respond(
            to: request,
            sessionID: target.sessionID,
            workingDirectory: target.workingDirectory,
            hostToolHandler: hostToolHandler
        ) { [weak self] progress in
            await self?.applyAgentProgress(
                progress,
                requestID: request.id,
                replyMessageID: replyMessageID,
                chatID: target.sessionID
            )
        }
    }

    func shutdownAgentRuntime() {
        let span = WeiBeiPerf.begin("pi.shutdown")
        agentRequestTask?.cancel()
        agentStopTask?.cancel()
        let runtime = piRuntime
        let completion = DispatchSemaphore(value: 0)
        Task.detached {
            await runtime.shutdown()
            completion.signal()
        }
        let result = completion.wait(timeout: .now() + 1)
        WeiBeiPerf.end(
            span,
            extra: result == .success
                ? "outcome=completed"
                : "outcome=timeout"
        )
    }

    private func applyAgentProgress(
        _ progress: StudyAgentProgress,
        requestID: UUID,
        replyMessageID: UUID,
        chatID: UUID
    ) {
        guard activeAgentRequestID == requestID,
              activeAgentReplyMessageID == replyMessageID,
              activeAgentReplyChatID == chatID else { return }
        let updatesVisibleChat = activeStudySessionID == chatID
        switch progress {
        case .preparing:
            if updatesVisibleChat {
                agentActivityText = ui("正在思考", "Thinking")
            }
        case let .usingTool(name, detail):
            guard updatesVisibleChat else { return }
            let base: String
            switch name {
            case "weibei_course_search":
                base = ui("正在搜索", "Searching")
            case "weibei_course_read", "read":
                base = ui("正在读取", "Reading")
            case "weibei_course_map":
                base = ui("正在查找课程关联", "Finding course connections")
            case "weibei_learning_memory":
                base = ui("正在回顾学习记忆", "Reviewing learning memory")
            case "weibei_learning_update":
                base = ui("正在整理学习进展", "Updating study progress")
            case "weibei_note_proposal":
                base = ui("正在整理写入建议", "Preparing a note proposal")
            case "weibei_rich_answer":
                base = ui("正在组织富回答", "Building a rich answer")
            default:
                base = ui("正在处理", "Working")
            }
            // Surface what the agent is actually touching, ChatGPT-style:
            // "正在搜索：泰勒展开" / "正在读取：导数.md".
            if let detail, !detail.isEmpty {
                agentActivityText = base + ui("：", ": ") + detail
            } else {
                agentActivityText = base
            }
        case let .text(text):
            latestAgentStreamingText = text
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentReplyIDsThatDisplayedStreamingText.insert(replyMessageID)
            }
            let now = DispatchTime.now().uptimeNanoseconds
            if updatesVisibleChat,
               now &- lastAgentStreamingPublishNanoseconds >= 33_000_000 {
                lastAgentStreamingPublishNanoseconds = now
                agentStreamingText = text
            }
            if updatesVisibleChat {
                let activity = ui("正在组织回答", "Composing answer")
                if agentActivityText != activity {
                    agentActivityText = activity
                }
            }
        }
    }

    private func appOwnedFilesDirectory() -> URL {
        let directory = workspaceDirectory.appendingPathComponent("Files", isDirectory: true)
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
        if case .courseOwned(let ownerCourseID) = importedItems[index].storage {
            return resolveCourseOwnedFile(at: index, ownerCourseID: ownerCourseID)
        }
        if case .shared(let sharedRelativePath) = importedItems[index].storage {
            let components = sharedRelativePath.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            let role: CourseOwnedFileRole = importedItems[index].isNotebookNote
                ? .note
                : .material
            let allowedDirectories: Set<Substring> = role == .note
                ? [Substring(role.commonDirectoryName)]
                : [Substring(role.commonDirectoryName), "共享文稿"]
            let usesPortableSharedLocation =
                components.count == 2
                    && allowedDirectories.contains(components[0])
            if usesPortableSharedLocation {
                guard let expectedDigest = importedItems[index].contentDigest,
                      let resolved = try? resolvedSharedPortableFile(
                          relativePath: sharedRelativePath,
                          expectedDigest: expectedDigest,
                          expectedKind: importedItems[index].kind,
                          isNotebookNote: importedItems[index].isNotebookNote
                      ),
                      importedItems[index].importedFileIdentity.map({
                          $0 == resolved.identity
                      }) ?? true else {
                    return markCourseOwnedItemUnavailable(at: index)
                }
                let candidate = resolved.url
                let identity = resolved.identity
                var changed = false
                if importedItems[index].urlPath != candidate.path
                    || importedItems[index].importedFileLastKnownPath != candidate.path
                    || importedItems[index].importedFileIdentity != identity
                    || importedItems[index].importedFileBookmarkData != nil {
                    importedItems[index].urlPath = candidate.path
                    importedItems[index].importedFileLastKnownPath = candidate.path
                    importedItems[index].importedFileIdentity = identity
                    importedItems[index].importedFileBookmarkData = nil
                    changed = true
                }
                return (candidate, changed)
            }
            // Older workspaces used `.shared` for ordinary external files
            // before the strict `共享文稿/<file>` contract existed. Keep those
            // records on the legacy identity/bookmark recovery path until the
            // user explicitly migrates them into a real course project.
        }
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

    private func resolveCourseOwnedFile(
        at index: Int,
        ownerCourseID: UUID
    ) -> (url: URL?, changed: Bool) {
        guard let membershipIndex = uniqueCourseOwnedMembershipIndex(
            itemID: importedItems[index].id,
            courseID: ownerCourseID
        ),
        let relativePath = courseItemMemberships[membershipIndex].courseRelativePath,
        let root = courseRootURL(for: ownerCourseID),
        let candidate = safeCourseOwnedFileURL(
            relativePath: relativePath,
            role: importedItems[index].isNotebookNote ? .note : .material,
            inside: root
        ) else {
            return markCourseOwnedItemUnavailable(at: index)
        }

        guard let identity = importedFileIdentityResolver(candidate),
              importedItems[index].importedFileIdentity.map({ $0 == identity }) ?? true,
              courseItemMemberships[membershipIndex].entryIdentity.map({ $0 == identity }) ?? true else {
            return markCourseOwnedItemUnavailable(at: index)
        }

        var changed = false
        if importedItems[index].urlPath != candidate.path
            || importedItems[index].importedFileLastKnownPath != candidate.path
            || importedItems[index].title != candidate.deletingPathExtension().lastPathComponent
            || importedItems[index].subtitle != candidate.lastPathComponent
            || importedItems[index].kind != StudyItemKind.detect(from: candidate)
            || importedItems[index].importedFileIdentity != identity
            || importedItems[index].importedFileBookmarkData != nil {
            importedItems[index].urlPath = candidate.path
            importedItems[index].importedFileLastKnownPath = candidate.path
            importedItems[index].title = candidate.deletingPathExtension().lastPathComponent
            importedItems[index].subtitle = candidate.lastPathComponent
            importedItems[index].kind = StudyItemKind.detect(from: candidate)
            importedItems[index].importedFileIdentity = identity
            importedItems[index].importedFileBookmarkData = nil
            changed = true
        }
        let documentIdentifier = courseFileDocumentIdentifier(at: candidate)
        if courseItemMemberships[membershipIndex].entryIdentity != identity
            || courseItemMemberships[membershipIndex].documentIdentifier != documentIdentifier {
            courseItemMemberships[membershipIndex].entryIdentity = identity
            courseItemMemberships[membershipIndex].documentIdentifier = documentIdentifier
            changed = true
        }
        return (candidate, changed)
    }

    @discardableResult
    private func resolveCourseOwnedItems(for courseID: UUID) -> Bool {
        var changed = false
        let itemIndices = importedItems.indices.filter { index in
            guard case .courseOwned(let ownerCourseID) = importedItems[index].storage else {
                return false
            }
            return ownerCourseID == courseID
        }
        for index in itemIndices {
            if resolveCourseOwnedFile(
                at: index,
                ownerCourseID: courseID
            ).changed {
                changed = true
            }
        }
        return changed
    }

    func reconcileCourseFilesNow(courseID requestedCourseID: UUID? = nil) async {
        guard !courseReconciliationInFlight else { return }
        courseReconciliationInFlight = true
        defer { courseReconciliationInFlight = false }
        var sharedChanged = false
        if let libraryRoot = courseLibraryRootURL {
            try? await ensureCommonContentDirectories(at: libraryRoot)
            sharedChanged = await migrateLegacySharedMaterials(
                in: libraryRoot
            )
        }
        if await reconcileSharedFilesNow() || sharedChanged {
            _ = await persistWorkspaceNow()
            courseDocumentSearchIndex.synchronize(allItems)
            invalidateAgentContext()
        }
        let courseIDs = requestedCourseID.map { [$0] } ?? courses.map(\.id)
        for courseID in courseIDs {
            guard activeCourseRemovalTokens[courseID] == nil,
                  let root = courseRootURL(for: courseID) else {
                continue
            }
            do {
                let snapshot = try await courseProjectFileWorker.scanCourse(at: root)
                guard activeCourseRemovalTokens[courseID] == nil,
                      courses.contains(where: { $0.id == courseID }),
                      courseRootURL(for: courseID) == root else {
                    continue
                }
                var changed = await applyCourseFileObservations(
                    snapshot,
                    courseID: courseID,
                    root: root
                )
                if let libraryRoot = courseLibraryRootURL {
                    for directoryName in [
                        CourseOwnedFileRole.material.commonDirectoryName,
                        CourseOwnedFileRole.note.commonDirectoryName,
                        "共享文稿",
                    ] {
                        let sharedDirectory = libraryRoot.appendingPathComponent(
                            directoryName,
                            isDirectory: true
                        )
                        guard FileManager.default.fileExists(
                            atPath: sharedDirectory.path
                        ) else { continue }
                        let sharedObservations = try await courseProjectFileWorker.scanSharedLinks(
                            at: root,
                            sharedDirectory: sharedDirectory
                        )
                        if applySharedLinkObservations(
                            sharedObservations,
                            courseID: courseID,
                            libraryRoot: libraryRoot,
                            courseRoot: root
                        ) {
                            changed = true
                        }
                    }
                }
                if changed {
                    _ = await persistWorkspaceNow()
                    courseDocumentSearchIndex.synchronize(allItems)
                    invalidateAgentContext()
                }
            } catch {
                courseRootUnavailableReasons[courseID] = ui(
                    "课程文件夹暂时无法对账：\(error.localizedDescription)",
                    "The course folder could not be reconciled: \(error.localizedDescription)"
                )
                if let expectedIdentity = course(withID: courseID)?.sourceRootIdentity,
                   importedFileIdentityResolver(root) != expectedIdentity {
                    cancelAgentRequestIfRunning(in: courseID)
                }
            }
        }
    }

    func reconcileCourseFilesForSelfCheck(courseID: UUID? = nil) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        try waitForCourseFileOperation {
            await self.reconcileCourseFilesNow(courseID: courseID)
        }
    }

    func courseReconciliationLookupCountForSelfCheck() -> Int {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return lastCourseReconciliationLookupCount
    }

    private func reconcileSharedFilesNow() async -> Bool {
        guard let libraryRoot = courseLibraryRootURL else { return false }
        var changed = false
        for (directoryName, isNote) in [
            (CourseOwnedFileRole.material.commonDirectoryName, false),
            (CourseOwnedFileRole.note.commonDirectoryName, true),
            ("共享文稿", false),
        ] {
            if await reconcileSharedFilesNow(
                libraryRoot: libraryRoot,
                directoryName: directoryName,
                isNote: isNote
            ) {
                changed = true
            }
        }
        return changed
    }

    private func ensureCommonContentDirectories(at libraryRoot: URL) async throws {
        for role in [CourseOwnedFileRole.material, .note] {
            _ = try await courseProjectFileWorker.ensureRealDirectory(
                libraryRoot.appendingPathComponent(
                    role.commonDirectoryName,
                    isDirectory: true
                ),
                inside: libraryRoot
            )
        }
    }

    private func migrateLegacySharedMaterials(
        in libraryRoot: URL
    ) async -> Bool {
        let oldDirectory = libraryRoot.appendingPathComponent(
            "共享文稿",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: oldDirectory.path) else {
            return false
        }
        let newDirectory = libraryRoot.appendingPathComponent(
            CourseOwnedFileRole.material.commonDirectoryName,
            isDirectory: true
        )
        var changed = false
        for index in importedItems.indices {
            guard case .shared(let relativePath) = importedItems[index].storage,
                  relativePath.hasPrefix("共享文稿/"),
                  let oldURL = CourseProjectPathPolicy.resolvedRelativePath(
                    relativePath,
                    inside: libraryRoot
                  ),
                  importedFileIdentityResolver(oldURL)
                    == importedItems[index].importedFileIdentity else {
                continue
            }
            let newURL = newDirectory.appendingPathComponent(
                oldURL.lastPathComponent
            )
            guard !FileManager.default.fileExists(atPath: newURL.path) else {
                noteFileError = ui(
                    "通用资料中已有同名文件“\(newURL.lastPathComponent)”，旧共享文稿已保留。",
                    "A same-named common material already exists. The legacy shared file was kept."
                )
                continue
            }
            guard CourseProjectFileWorker.renameWithoutReplacement(
                from: oldURL,
                to: newURL
            ) else {
                continue
            }
            for membership in courseItemMemberships
            where membership.itemID == importedItems[index].id {
                guard let root = courseRootURL(for: membership.courseID),
                      let relativePath = membership.courseRelativePath,
                      let linkIdentity = membership.entryIdentity,
                      let linkURL = Self.backgroundRawRelativeURL(
                        relativePath,
                        inside: root
                      ) else {
                    continue
                }
                do {
                    try await courseProjectFileWorker.repairSharedLink(
                        at: linkURL,
                        courseRoot: root,
                        from: oldURL,
                        to: newURL,
                        expectedLinkIdentity: linkIdentity
                    )
                } catch {
                    courseRootUnavailableReasons[membership.courseID] = ui(
                        "通用资料已迁移，但课程入口暂时无法修复：\(error.localizedDescription)",
                        "The common material moved, but a course entry could not be repaired."
                    )
                }
            }
            importedItems[index].storage = .shared(
                sharedRelativePath:
                    "\(CourseOwnedFileRole.material.commonDirectoryName)/\(newURL.lastPathComponent)"
            )
            importedItems[index].urlPath = newURL.path
            importedItems[index].importedFileLastKnownPath = newURL.path
            changed = true
        }
        if (try? FileManager.default.contentsOfDirectory(
            atPath: oldDirectory.path
        ).isEmpty) == true {
            try? FileManager.default.removeItem(at: oldDirectory)
        }
        return changed
    }

    private func reconcileSharedFilesNow(
        libraryRoot: URL,
        directoryName: String,
        isNote: Bool
    ) async -> Bool {
        let sharedDirectory = libraryRoot.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: sharedDirectory.path),
              let snapshot = try? await courseProjectFileWorker
                .scanSharedOriginals(
                    at: sharedDirectory,
                    isNote: isNote
                ) else {
            return false
        }
        var changed = false
        var itemIndexByID: [String: Int] = [:]
        for index in importedItems.indices {
            if case .shared(let relativePath) = importedItems[index].storage,
               relativePath.hasPrefix("\(directoryName)/") {
                itemIndexByID[importedItems[index].id] = index
            }
        }
        let itemIDs = itemIndexByID.keys.sorted()
        let courseRootsByID = Dictionary(
            uniqueKeysWithValues: courses.compactMap { course in
                courseRootURL(for: course.id).map { (course.id, $0) }
            }
        )
        var sharedMembershipsByItemID: [
            String: [CourseItemMembership]
        ] = [:]
        for membership in courseItemMemberships
        where itemIndexByID[membership.itemID] != nil {
            sharedMembershipsByItemID[
                membership.itemID,
                default: []
            ].append(membership)
        }
        var consumedObservationIndexes = Set<Int>()
        var observationIndexByItemID: [String: Int] = [:]

        for itemID in itemIDs {
            guard let itemIndex = itemIndexByID[itemID],
                  case .shared(let relativePath) = importedItems[itemIndex].storage,
                  relativePath.hasPrefix("\(directoryName)/") else {
                continue
            }
            let fileName = String(
                relativePath.dropFirst(directoryName.count + 1)
            )
            guard !fileName.contains("/"),
                  let observationIndex = snapshot.indexByRelativePath[fileName],
                  consumedObservationIndexes.insert(observationIndex).inserted else {
                continue
            }
            observationIndexByItemID[itemID] = observationIndex
        }

        func firstUnconsumed(_ indexes: [Int]?) -> Int? {
            guard let indexes else { return nil }
            for index in indexes
            where consumedObservationIndexes.insert(index).inserted {
                return index
            }
            return nil
        }

        for itemID in itemIDs where observationIndexByItemID[itemID] == nil {
            guard let itemIndex = itemIndexByID[itemID],
                  let identity = importedItems[itemIndex].importedFileIdentity,
                  let observationIndex = firstUnconsumed(
                    snapshot.indexesByIdentity[identity]
                  ) else {
                continue
            }
            observationIndexByItemID[itemID] = observationIndex
        }

        for itemID in itemIDs {
            guard let itemIndex = itemIndexByID[itemID],
                  let observationIndex = observationIndexByItemID[itemID] else {
                if let itemIndex = itemIndexByID[itemID],
                   markCourseOwnedItemUnavailable(at: itemIndex).changed {
                    changed = true
                }
                continue
            }
            let observation = snapshot.observations[observationIndex]
            let previous = importedItems[itemIndex]
            if let oldURL = previous.url,
               !CourseProjectPathPolicy.isSame(oldURL, observation.url),
               previous.importedFileIdentity == observation.identity {
                for membership in sharedMembershipsByItemID[itemID] ?? [] {
                    guard let courseRoot =
                            courseRootsByID[membership.courseID],
                          let relativePath =
                            membership.courseRelativePath,
                          let linkIdentity = membership.entryIdentity,
                          let linkURL = Self.backgroundRawRelativeURL(
                            relativePath,
                            inside: courseRoot
                          ) else {
                        continue
                    }
                    do {
                        try courseProjectMutationHook(
                            .beforeSharedLinkRepair
                        )
                        try await courseProjectFileWorker.repairSharedLink(
                            at: linkURL,
                            courseRoot: courseRoot,
                            from: oldURL,
                            to: observation.url,
                            expectedLinkIdentity: linkIdentity
                        )
                    } catch {
                        courseRootUnavailableReasons[
                            membership.courseID
                        ] = ui(
                            "共享原件已改名，但课程入口暂时无法修复：\(error.localizedDescription)",
                            "The shared original was renamed, but its course entry could not be repaired: \(error.localizedDescription)"
                        )
                    }
                }
            }
            do {
                let identityChanged =
                    previous.importedFileIdentity != observation.identity
                let metadataChanged = previous.fileByteCount != nil
                    && previous.fileModificationTimeNanoseconds != nil
                    && (previous.fileByteCount != observation.byteCount
                        || previous.fileModificationTimeNanoseconds
                            != observation.modificationTimeNanoseconds)
                var digest = previous.contentDigest
                var revision = previous.contentRevision
                if identityChanged || metadataChanged {
                    let fileSnapshot = try await courseProjectFileWorker.snapshot(
                        at: observation.url
                    )
                    if identityChanged || digest != fileSnapshot.sha256 {
                        revision &+= 1
                    }
                    digest = fileSnapshot.sha256
                }
                var nextItem = previous
                nextItem.title =
                    observation.url.deletingPathExtension().lastPathComponent
                nextItem.subtitle = observation.url.lastPathComponent
                nextItem.kind = StudyItemKind.detect(from: observation.url)
                nextItem.urlPath = observation.url.path
                nextItem.importedFileLastKnownPath = observation.url.path
                nextItem.importedFileIdentity = observation.identity
                nextItem.importedFileBookmarkData = nil
                nextItem.storage = .shared(
                    sharedRelativePath:
                        "\(directoryName)/\(observation.relativePath)"
                )
                nextItem.contentRevision = revision
                nextItem.contentDigest = digest
                nextItem.fileByteCount = observation.byteCount
                nextItem.fileModificationTimeNanoseconds =
                    observation.modificationTimeNanoseconds
                if nextItem != previous {
                    importedItems[itemIndex] = nextItem
                    changed = true
                }
            } catch {
                if markCourseOwnedItemUnavailable(at: itemIndex).changed {
                    changed = true
                }
            }
        }
        for (observationIndex, observation) in snapshot.observations.enumerated()
        where !consumedObservationIndexes.contains(observationIndex) {
            importedItems.append(
                StudyItem(
                    id: Self.makeImportedItemID(),
                    title:
                        observation.url.deletingPathExtension().lastPathComponent,
                    subtitle: observation.url.lastPathComponent,
                    kind: StudyItemKind.detect(from: observation.url),
                    urlPath: observation.url.path,
                    importedFileIdentity: observation.identity,
                    importedFileBookmarkData: nil,
                    importedFileLastKnownPath: observation.url.path,
                    isSample: false,
                    isNotebookNote: isNote,
                    storage: .shared(
                        sharedRelativePath:
                            "\(directoryName)/\(observation.relativePath)"
                    ),
                    contentRevision: 1,
                    contentDigest: nil,
                    fileByteCount: observation.byteCount,
                    fileModificationTimeNanoseconds:
                        observation.modificationTimeNanoseconds
                )
            )
            changed = true
        }
        return changed
    }

    private func applySharedLinkObservations(
        _ observations: [CourseSharedLinkObservation],
        courseID: UUID,
        libraryRoot: URL,
        courseRoot: URL
    ) -> Bool {
        var itemIDByIdentity: [ImportedFileIdentity: String] = [:]
        var itemIDByPath: [String: String] = [:]
        var sharedItemIDs = Set<String>()
        for item in importedItems {
            guard case .shared(let relativePath) = item.storage,
                  let expectedURL = CourseProjectPathPolicy.resolvedRelativePath(
                    relativePath,
                    inside: libraryRoot
                  ) else {
                continue
            }
            sharedItemIDs.insert(item.id)
            itemIDByPath[expectedURL.standardizedFileURL.path] = item.id
            if let identity = item.importedFileIdentity {
                itemIDByIdentity[identity] = item.id
            }
        }
        let observationItemIDs: [String?] = observations.map {
            itemIDByPath[$0.sharedURL.standardizedFileURL.path]
                ?? itemIDByIdentity[$0.sharedIdentity]
        }
        var observationIndexesByItemID: [String: [Int]] = [:]
        var observationIndexByLinkIdentity: [ImportedFileIdentity: Int] = [:]
        var observationIndexByRelativePath: [String: Int] = [:]
        for index in observations.indices {
            guard let itemID = observationItemIDs[index] else { continue }
            observationIndexesByItemID[itemID, default: []].append(index)
            observationIndexByLinkIdentity[
                observations[index].linkIdentity
            ] = index
            observationIndexByRelativePath[
                observations[index].relativePath
            ] = index
        }
        var nextCandidateOffsetByItemID: [String: Int] = [:]
        var consumedObservationIndexes = Set<Int>()
        func firstUnconsumed(for itemID: String) -> Int? {
            guard let indexes = observationIndexesByItemID[itemID] else {
                return nil
            }
            var offset = nextCandidateOffsetByItemID[itemID] ?? 0
            while offset < indexes.count {
                let index = indexes[offset]
                offset += 1
                if consumedObservationIndexes.insert(index).inserted {
                    nextCandidateOffsetByItemID[itemID] = offset
                    return index
                }
            }
            nextCandidateOffsetByItemID[itemID] = offset
            return nil
        }

        var changed = false
        var removalIndexes = Set<Int>()
        var matchedItemIDs = Set<String>()
        for membershipIndex in courseItemMemberships.indices {
            let membership = courseItemMemberships[membershipIndex]
            guard membership.courseID == courseID,
                  sharedItemIDs.contains(membership.itemID) else {
                continue
            }
            let identityMatch = membership.entryIdentity.flatMap {
                observationIndexByLinkIdentity[$0]
            }.flatMap { index in
                observationItemIDs[index] == membership.itemID
                    && consumedObservationIndexes.insert(index).inserted
                    ? index
                    : nil
            }
            let pathMatch = identityMatch == nil
                ? membership.courseRelativePath.flatMap {
                    observationIndexByRelativePath[$0]
                  }.flatMap { index in
                    observationItemIDs[index] == membership.itemID
                        && consumedObservationIndexes.insert(index).inserted
                        ? index
                        : nil
                  }
                : nil
            guard let matchIndex =
                identityMatch
                ?? pathMatch
                ?? firstUnconsumed(for: membership.itemID) else {
                if let relativePath = membership.courseRelativePath,
                   let rawEntryURL = Self.backgroundRawRelativeURL(
                    relativePath,
                    inside: courseRoot
                   ),
                   CourseProjectFileWorker.entryPresence(at: rawEntryURL)
                    != .absent {
                    courseRootUnavailableReasons[courseID] = ui(
                        "共享入口暂时无法读取；已保留课程成员关系，待入口恢复后继续对账。",
                        "A shared entry is temporarily unreadable. Its course membership was preserved until the entry recovers."
                    )
                    continue
                }
                removalIndexes.insert(membershipIndex)
                changed = true
                continue
            }
            matchedItemIDs.insert(membership.itemID)
            let observation = observations[matchIndex]
            if courseItemMemberships[membershipIndex].courseRelativePath
                != observation.relativePath
                || courseItemMemberships[membershipIndex].entryIdentity
                    != observation.linkIdentity
                || courseItemMemberships[membershipIndex].documentIdentifier
                    != nil {
                courseItemMemberships[membershipIndex].courseRelativePath =
                    observation.relativePath
                courseItemMemberships[membershipIndex].entryIdentity =
                    observation.linkIdentity
                courseItemMemberships[membershipIndex].documentIdentifier = nil
                changed = true
            }
        }
        if !removalIndexes.isEmpty {
            courseItemMemberships = courseItemMemberships.enumerated().compactMap {
                removalIndexes.contains($0.offset) ? nil : $0.element
            }
        }
        var existingItemIDs = Set(courseItemMemberships.compactMap {
            $0.courseID == courseID ? $0.itemID : nil
        })
        for index in observations.indices
        where !consumedObservationIndexes.contains(index) {
            guard let itemID = observationItemIDs[index],
                  existingItemIDs.insert(itemID).inserted else {
                continue
            }
            let observation = observations[index]
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: courseID,
                    itemID: itemID,
                    courseRelativePath: observation.relativePath,
                    entryIdentity: observation.linkIdentity
                )
            )
            changed = true
        }
        return changed
    }

    private func applyCourseFileObservations(
        _ snapshot: CourseFileScanSnapshot,
        courseID: UUID,
        root: URL
    ) async -> Bool {
        let observations = snapshot.observations
        var changed = false
        var lookupCount = 0
        var itemIndexByID: [String: Int] = [:]
        for index in importedItems.indices {
            guard case .courseOwned(let ownerCourseID) = importedItems[index].storage,
                  ownerCourseID == courseID else {
                continue
            }
            itemIndexByID[importedItems[index].id] = index
        }
        var membershipIndexesByItemID: [String: [Int]] = [:]
        for index in courseItemMemberships.indices
        where courseItemMemberships[index].courseID == courseID {
            membershipIndexesByItemID[
                courseItemMemberships[index].itemID,
                default: []
            ].append(index)
        }
        let ownedItemIDs = itemIndexByID.keys.sorted()
        var matchedObservationByItemID: [String: Int] = [:]
        var consumedObservationIndexes = Set<Int>()

        for itemID in ownedItemIDs {
            lookupCount += 1
            guard let membershipIndexes = membershipIndexesByItemID[itemID],
                  membershipIndexes.count == 1,
                  let relativePath = courseItemMemberships[
                    membershipIndexes[0]
                  ].courseRelativePath,
                  let observationIndex = snapshot.indexByRelativePath[relativePath],
                  consumedObservationIndexes.insert(observationIndex).inserted else {
                continue
            }
            matchedObservationByItemID[itemID] = observationIndex
        }

        func firstUnconsumed(_ indexes: [Int]?) -> Int? {
            guard let indexes else { return nil }
            for index in indexes {
                lookupCount += 1
                if consumedObservationIndexes.insert(index).inserted {
                    return index
                }
            }
            return nil
        }

        for itemID in ownedItemIDs where matchedObservationByItemID[itemID] == nil {
            lookupCount += 1
            guard let itemIndex = itemIndexByID[itemID],
                  let membershipIndexes = membershipIndexesByItemID[itemID],
                  membershipIndexes.count == 1 else {
                continue
            }
            let item = importedItems[itemIndex]
            let membership = courseItemMemberships[membershipIndexes[0]]
            let identityMatch = item.importedFileIdentity.flatMap {
                firstUnconsumed(snapshot.indexesByIdentity[$0])
            } ?? membership.entryIdentity.flatMap {
                firstUnconsumed(snapshot.indexesByIdentity[$0])
            }
            let documentMatch = identityMatch == nil
                ? membership.documentIdentifier.flatMap {
                    firstUnconsumed(snapshot.indexesByDocumentIdentifier[$0])
                }
                : nil
            if let match = identityMatch ?? documentMatch {
                matchedObservationByItemID[itemID] = match
            }
        }

        for itemID in ownedItemIDs {
            lookupCount += 1
            guard let itemIndex = itemIndexByID[itemID],
                  let membershipIndexes = membershipIndexesByItemID[itemID],
                  membershipIndexes.count == 1 else {
                continue
            }
            let membershipIndex = membershipIndexes[0]
            let item = importedItems[itemIndex]
            let membership = courseItemMemberships[membershipIndex]
            guard let observationIndex = matchedObservationByItemID[itemID] else {
                if markCourseOwnedItemUnavailable(at: itemIndex).changed {
                    changed = true
                }
                continue
            }
            let observation = observations[observationIndex]
            let identityChanged = item.importedFileIdentity != observation.identity
                || membership.entryIdentity != observation.identity
            let hasMetadataBaseline = item.fileByteCount != nil
                && item.fileModificationTimeNanoseconds != nil
            let metadataChanged = hasMetadataBaseline
                && (item.fileByteCount != observation.byteCount
                    || item.fileModificationTimeNanoseconds != observation.modificationTimeNanoseconds)
            var nextDigest = item.contentDigest
            var nextRevision = item.contentRevision
            if identityChanged || metadataChanged {
                do {
                    let snapshot = try await courseProjectFileWorker.snapshot(at: observation.url)
                    if identityChanged || item.contentDigest != snapshot.sha256 {
                        nextRevision &+= 1
                    }
                    nextDigest = snapshot.sha256
                } catch {
                    if markCourseOwnedItemUnavailable(at: itemIndex).changed {
                        changed = true
                    }
                    continue
                }
            }

            var nextItem = importedItems[itemIndex]
            nextItem.title = observation.url.deletingPathExtension().lastPathComponent
            nextItem.subtitle = observation.url.lastPathComponent
            nextItem.kind = StudyItemKind.detect(from: observation.url)
            nextItem.urlPath = observation.url.path
            nextItem.importedFileIdentity = observation.identity
            nextItem.importedFileBookmarkData = nil
            nextItem.importedFileLastKnownPath = observation.url.path
            nextItem.isNotebookNote = observation.isNote
            nextItem.contentRevision = nextRevision
            nextItem.contentDigest = nextDigest
            nextItem.fileByteCount = observation.byteCount
            nextItem.fileModificationTimeNanoseconds = observation.modificationTimeNanoseconds
            if importedItems[itemIndex] != nextItem {
                importedItems[itemIndex] = nextItem
                changed = true
            }
            if observation.isNote, let nextDigest {
                noteBackingContentDigestsByItemID[itemID] = nextDigest
            }
            if courseItemMemberships[membershipIndex].courseRelativePath
                != observation.relativePath
                || courseItemMemberships[membershipIndex].entryIdentity
                    != observation.identity
                || courseItemMemberships[membershipIndex].documentIdentifier
                    != observation.documentIdentifier {
                courseItemMemberships[membershipIndex].courseRelativePath =
                    observation.relativePath
                courseItemMemberships[membershipIndex].entryIdentity =
                    observation.identity
                courseItemMemberships[membershipIndex].documentIdentifier =
                    observation.documentIdentifier
                changed = true
            }
        }

        for (observationIndex, observation) in observations.enumerated()
        where !consumedObservationIndexes.contains(observationIndex) {
            lookupCount += 1
            let item = StudyItem(
                id: Self.makeImportedItemID(),
                title: observation.url.deletingPathExtension().lastPathComponent,
                subtitle: observation.url.lastPathComponent,
                kind: StudyItemKind.detect(from: observation.url),
                urlPath: observation.url.path,
                importedFileIdentity: observation.identity,
                importedFileBookmarkData: nil,
                importedFileLastKnownPath: observation.url.path,
                isSample: false,
                isNotebookNote: observation.isNote,
                storage: .courseOwned(ownerCourseID: courseID),
                contentRevision: 1,
                contentDigest: nil,
                fileByteCount: observation.byteCount,
                fileModificationTimeNanoseconds: observation.modificationTimeNanoseconds
            )
            importedItems.append(item)
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: courseID,
                    itemID: item.id,
                    courseRelativePath: observation.relativePath,
                    entryIdentity: observation.identity,
                    documentIdentifier: observation.documentIdentifier
                )
            )
            changed = true
        }
        lastCourseReconciliationLookupCount = lookupCount
        if changed {
            courseRootUnavailableReasons.removeValue(forKey: courseID)
        }
        return changed
    }

    private func startCourseFileMaintenance() {
        courseReconciliationTask?.cancel()
        courseReconciliationTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await self?.finishPendingCourseRemovalRecoveryIfNeeded()
            await self?.recoverPendingCourseFileTransactionsInBackground()
            await self?.reconcileCourseFilesNow()
            self?.retryRestoredPendingNoteWrites()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.reconcileCourseFilesNow()
            }
        }
    }

    private func markCourseOwnedItemUnavailable(
        at index: Int
    ) -> (url: URL?, changed: Bool) {
        var changed = false
        if let currentPath = importedItems[index].urlPath {
            importedItems[index].importedFileLastKnownPath = currentPath
            importedItems[index].urlPath = nil
            changed = true
        }
        if importedItems[index].importedFileBookmarkData != nil {
            importedItems[index].importedFileBookmarkData = nil
            changed = true
        }
        return (nil, changed)
    }

    private func uniqueCourseOwnedMembershipIndex(
        itemID: String,
        courseID: UUID
    ) -> Int? {
        let matches = courseItemMemberships.indices.filter {
            courseItemMemberships[$0].itemID == itemID
                && courseItemMemberships[$0].courseID == courseID
                && courseItemMemberships[$0].courseRelativePath != nil
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private struct VerifiedCourseOwnedNoteAccess {
        var courseID: UUID
        var root: URL
        var rootIdentity: ImportedFileIdentity
        var url: URL
        var fileIdentity: ImportedFileIdentity
        var membershipIndex: Int

        func matches(_ other: Self) -> Bool {
            courseID == other.courseID
                && rootIdentity == other.rootIdentity
                && fileIdentity == other.fileIdentity
                && CourseProjectPathPolicy.isSame(root, other.root)
                && CourseProjectPathPolicy.isSame(url, other.url)
        }
    }

    private func verifiedCourseOwnedNoteAccess(
        _ item: StudyItem
    ) -> VerifiedCourseOwnedNoteAccess? {
        guard item.isNotebookNote,
              case .courseOwned(let courseID) = item.storage,
              courseRootUnavailableReasons[courseID] == nil,
              let course = course(withID: courseID),
              let expectedRootIdentity = course.sourceRootIdentity,
              let root = courseRootURL(for: courseID),
              importedFileIdentityResolver(root)
                == expectedRootIdentity,
              let membershipIndex =
                uniqueCourseOwnedMembershipIndex(
                    itemID: item.id,
                    courseID: courseID
                ),
              let relativePath =
                courseItemMemberships[membershipIndex]
                    .courseRelativePath,
              let resolvedURL = safeCourseOwnedFileURL(
                relativePath: relativePath,
                role: .note,
                inside: root
              ),
              let itemURL = item.url,
              CourseProjectPathPolicy.isSame(
                resolvedURL,
                itemURL
              ),
              let fileIdentity = item.importedFileIdentity,
              importedFileIdentityResolver(resolvedURL)
                == fileIdentity,
              courseItemMemberships[membershipIndex]
                .entryIdentity.map({ $0 == fileIdentity })
                ?? true else {
            return nil
        }
        return VerifiedCourseOwnedNoteAccess(
            courseID: courseID,
            root: root,
            rootIdentity: expectedRootIdentity,
            url: resolvedURL,
            fileIdentity: fileIdentity,
            membershipIndex: membershipIndex
        )
    }

    private func safeCourseOwnedFileURL(
        relativePath: String,
        role: CourseOwnedFileRole,
        inside root: URL
    ) -> URL? {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.first != ".weibei",
              !components.contains("."),
              !components.contains(".."),
              isSupportedCourseFileName(components.last ?? "", role: role),
              let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(root) else {
            return nil
        }
        let rawURL = components.reduce(canonicalRoot) {
            $0.appendingPathComponent($1, isDirectory: false)
        }
        guard let rawValues = try? rawURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ]),
        rawValues.isRegularFile == true,
        rawValues.isSymbolicLink != true,
        rawValues.isAliasFile != true,
        CourseProjectPathPolicy.isSame(rawURL, rawURL.resolvingSymlinksInPath()),
        let resolved = CourseProjectPathPolicy.resolvedRelativePath(
            relativePath,
            inside: canonicalRoot
        ),
        CourseProjectPathPolicy.contains(canonicalRoot, resolved, includingRoot: false) else {
            return nil
        }
        return resolved
    }

    @discardableResult
    private func refreshImportedFileTracking(itemID: String, url: URL) -> StudyItem? {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }),
              let identity = importedFileIdentityResolver(url) else {
            return nil
        }
        if case .courseOwned(let ownerCourseID) = importedItems[index].storage {
            guard let membershipIndex = uniqueCourseOwnedMembershipIndex(
                itemID: itemID,
                courseID: ownerCourseID
            ),
            let relativePath = courseItemMemberships[membershipIndex].courseRelativePath,
            let root = courseRootURL(for: ownerCourseID),
            let resolvedURL = safeCourseOwnedFileURL(
                relativePath: relativePath,
                role: importedItems[index].isNotebookNote ? .note : .material,
                inside: root
            ),
            CourseProjectPathPolicy.isSame(resolvedURL, url.resolvingSymlinksInPath()),
            let snapshot = try? courseFileSnapshot(at: resolvedURL) else {
                return nil
            }
            if let previousDigest = importedItems[index].contentDigest,
               previousDigest != snapshot.sha256 {
                importedItems[index].contentRevision &+= 1
            }
            importedItems[index].contentDigest = snapshot.sha256
            importedItems[index].urlPath = resolvedURL.path
            importedItems[index].importedFileIdentity = identity
            importedItems[index].importedFileBookmarkData = nil
            importedItems[index].importedFileLastKnownPath = resolvedURL.path
            importedItems[index].title = resolvedURL.deletingPathExtension().lastPathComponent
            importedItems[index].subtitle = resolvedURL.lastPathComponent
            importedItems[index].kind = StudyItemKind.detect(from: resolvedURL)
            courseItemMemberships[membershipIndex].entryIdentity = identity
            courseItemMemberships[membershipIndex].documentIdentifier =
                courseFileDocumentIdentifier(at: resolvedURL)
            return importedItems[index]
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
            let isManagedByCourseLibrary: Bool = {
                switch item.storage {
                case .courseOwned, .shared:
                    return true
                case .legacyExternal, .bundledSample:
                    return false
                }
            }()
            if isManagedByCourseLibrary {
                if item.importedFileBookmarkData != nil {
                    item.importedFileBookmarkData = nil
                    changed = true
                }
            } else if resolvedIdentity != nil,
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
              oldItem.storage == newItem.storage,
              oldItem.contentRevision == newItem.contentRevision,
              oldItem.contentDigest == newItem.contentDigest,
              courseMembershipsCanCoalesce(oldID: oldItem.id, newID: newID),
              valuesCanCoalesce(notesByItemID[oldItem.id], notesByItemID[newID]),
              valuesCanCoalesce(pendingNoteWritesByItemID[oldItem.id], pendingNoteWritesByItemID[newID]),
              valuesCanCoalesce(noteBackingContentDigestsByItemID[oldItem.id], noteBackingContentDigestsByItemID[newID]),
              studyLocationsCanCoalesce(oldID: oldItem.id, newID: newID),
              pendingPersistenceCanCoalesce(oldID: oldItem.id, newID: newID) else {
            return false
        }
        return true
    }

    private func courseMembershipsCanCoalesce(oldID: String, newID: String) -> Bool {
        for oldMembership in courseItemMemberships where oldMembership.itemID == oldID {
            guard let newMembership = courseItemMemberships.first(where: {
                $0.itemID == newID && $0.courseID == oldMembership.courseID
            }) else {
                continue
            }
            guard valuesCanCoalesce(oldMembership.courseRelativePath, newMembership.courseRelativePath),
                  valuesCanCoalesce(oldMembership.entryIdentity, newMembership.entryIdentity),
                  valuesCanCoalesce(oldMembership.documentIdentifier, newMembership.documentIdentifier) else {
                return false
            }
        }
        return true
    }

    private func valuesCanCoalesce<Value: Equatable>(_ oldValue: Value?, _ newValue: Value?) -> Bool {
        oldValue == nil || newValue == nil || oldValue == newValue
    }

    private func studyLocationsCanCoalesce(oldID: String, newID: String) -> Bool {
        guard var oldLocation = studyLocationsByItemID[oldID],
              let newLocation = studyLocationsByItemID[newID] else {
            return courseStudyLocationsCanCoalesce(oldID: oldID, newID: newID)
        }
        oldLocation.itemID = newID
        return oldLocation == newLocation
            && courseStudyLocationsCanCoalesce(oldID: oldID, newID: newID)
    }

    private func courseStudyLocationsCanCoalesce(
        oldID: String,
        newID: String
    ) -> Bool {
        studyLocationsByCourseID.values.allSatisfy { locations in
            guard var oldLocation = locations[oldID],
                  let newLocation = locations[newID] else {
                return true
            }
            oldLocation.itemID = newID
            return oldLocation == newLocation
        }
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
        if let loadedNote = loadedCourseNoteTextByItemID.removeValue(
            forKey: oldID
        ), loadedCourseNoteTextByItemID[newID] == nil {
            loadedCourseNoteTextByItemID[newID] = loadedNote
        }
        courseNoteLoadTasksByItemID.removeValue(forKey: oldID)?.cancel()
        courseNoteLoadGenerationByItemID.removeValue(forKey: oldID)
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
        for courseKey in Array(studyLocationsByCourseID.keys) {
            guard var locations = studyLocationsByCourseID[courseKey],
                  var location = locations.removeValue(forKey: oldID) else {
                continue
            }
            location.itemID = newID
            if locations[newID] == nil {
                locations[newID] = location
            }
            studyLocationsByCourseID[courseKey] = locations
        }
        for index in courseResumePoints.indices {
            if courseResumePoints[index].materialLocation?.itemID == oldID {
                courseResumePoints[index].materialLocation?.itemID = newID
            }
            if courseResumePoints[index].noteItemID == oldID {
                courseResumePoints[index].noteItemID = newID
            }
        }
        for index in studySessions.indices {
            if studySessions[index].materialItemID == oldID {
                studySessions[index].materialItemID = newID
            }
            var seen = Set<String>()
            studySessions[index].focusItemIDs = studySessions[index].focusItemIDs.compactMap { itemID in
                let migratedID = itemID == oldID ? newID : itemID
                return seen.insert(migratedID).inserted ? migratedID : nil
            }
        }
        for index in selectionAskThreads.indices where selectionAskThreads[index].itemID == oldID {
            selectionAskThreads[index].itemID = newID
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
        materialNotePairings = replacingItemID(
            oldID,
            with: newID,
            in: materialNotePairings
        )
        noteMaterialPairings = replacingItemID(
            oldID,
            with: newID,
            in: noteMaterialPairings
        )

        pendingNotePersistenceTasks.removeValue(forKey: oldID)?.cancel()
        if var pending = pendingNotePersistenceByItemID.removeValue(forKey: oldID) {
            pending.item.id = newID
            scheduleNotePersistence(pending.markdown, for: pending.item)
        }
        replaceNavigationItemID(oldID, with: newID)
    }

    private func replacingItemID(
        _ oldID: String,
        with newID: String,
        in pairings: [String: String]
    ) -> [String: String] {
        var result = pairings
        if let value = result.removeValue(forKey: oldID),
           result[newID] == nil {
            result[newID] = value == oldID ? newID : value
        }
        for key in Array(result.keys) where result[key] == oldID {
            result[key] = newID
        }
        return result
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

    private func invalidateAgentContext(restoreAgentDraft _: Bool = true) {
        agentContextRevision &+= 1
        latestAgentNoteProposal = nil
        lastAgentReplyContextRevision = nil
    }

    private func clearUnpinnedFloatingSelection(keepContext: Bool = true, invalidatesAgentContext: Bool = true) {
        // Never kill the float while a selection answer is streaming / pinned for reading.
        if keepFloatingSelectionForAnswer
            || (pinnedFloatingAgent && agentSurface == .selectionFloat && isAgentRunningInActiveChat) {
            return
        }
        if !keepContext {
            // Empty selectionchange / pointerdown spam must not re-assign @Published
            // nils and fan out into agent chat remasure (scroll-only hang sample).
            let alreadyClear = selectionContext == nil
                && selectionAnchor == nil
                && !pinnedFloatingAgent
                && agentSurface != .selectionFloat
            if alreadyClear {
                cancelPendingSelectionAttachment()
                return
            }
            if invalidatesAgentContext, selectionContext != nil {
                invalidateAgentContext()
            }
            cancelPendingSelectionAttachment()
            selectionContext = nil
            selectionAnchor = nil
            let clearedPrompt = ui("当前选区", "Current selection")
            if floatingSelectionPrompt != clearedPrompt {
                floatingSelectionPrompt = clearedPrompt
            }
            pinnedFloatingAgent = false
            if agentSurface == .selectionFloat {
                agentSurface = .hidden
            }
            return
        }
        guard !pinnedFloatingAgent else { return }
        if selectionAnchor == nil, agentSurface != .selectionFloat {
            return
        }
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

    private func setNoteFileError(_ message: String?, for itemID: String) {
        if let message {
            noteOperationErrorsByItemID[itemID] = message
        } else {
            noteOperationErrorsByItemID.removeValue(forKey: itemID)
        }
        guard activeNoteItemID == itemID else { return }
        noteFileError = message
    }

    private func retryRestoredPendingNoteWrites() {
        for item in importedItems where item.editsBackingMarkdownFile {
            guard pendingNoteWritesByItemID[item.id]?
                    .baselineContentDigest != nil,
                  let markdown = notesByItemID[item.id] else {
                continue
            }
            persistNote(markdown, for: item)
        }
    }

    private func scheduleCourseNoteLoad(_ item: StudyItem) {
        guard let access = verifiedCourseOwnedNoteAccess(
            item
        ) else {
            return
        }
        let url = access.url
        let identity = access.fileIdentity
        let itemID = item.id
        guard courseNoteLoadTasksByItemID[itemID] == nil else { return }
        let generation = (courseNoteLoadGenerationByItemID[itemID] ?? 0) &+ 1
        courseNoteLoadGenerationByItemID[itemID] = generation
        let displayedText = activeNoteItemID == itemID ? noteText : nil
        courseNoteLoadTasksByItemID[itemID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if courseNoteLoadGenerationByItemID[itemID] == generation {
                    courseNoteLoadTasksByItemID[itemID] = nil
                }
            }
            do {
                let result = try await courseProjectFileWorker.readMarkdown(
                    at: url,
                    expectedIdentity: identity
                )
                guard courseNoteLoadGenerationByItemID[itemID] == generation,
                      let currentIndex = importedItems.firstIndex(where: {
                          $0.id == itemID
                      }),
                      let currentAccess =
                        verifiedCourseOwnedNoteAccess(
                            importedItems[currentIndex]
                        ),
                      currentAccess.matches(access) else {
                    return
                }
                lastCourseNoteReadRanOnMainThread = result.ranOnMainThread
                let markdown = cleanLegacyPlaceholder(result.markdown)
                loadedCourseNoteTextByItemID[itemID] = markdown
                let previousDigest = importedItems[currentIndex].contentDigest
                if let previousDigest,
                   previousDigest != result.snapshot.sha256 {
                    importedItems[currentIndex].contentRevision &+= 1
                }
                importedItems[currentIndex].contentDigest =
                    result.snapshot.sha256
                importedItems[currentIndex].fileByteCount =
                    result.metadata.byteCount
                importedItems[currentIndex].fileModificationTimeNanoseconds =
                    result.metadata.modificationTimeNanoseconds
                importedItems[currentIndex].importedFileIdentity =
                    result.metadata.identity
                importedItems[currentIndex].urlPath = result.metadata.url.path
                importedItems[currentIndex].importedFileLastKnownPath =
                    result.metadata.url.path
                noteBackingContentDigestsByItemID[itemID] =
                    result.snapshot.sha256
                if courseItemMemberships.indices.contains(
                    currentAccess.membershipIndex
                ) {
                    courseItemMemberships[
                        currentAccess.membershipIndex
                    ].entryIdentity =
                        result.metadata.identity
                    courseItemMemberships[
                        currentAccess.membershipIndex
                    ].documentIdentifier =
                        result.documentIdentifier
                }
                if let pendingWrite = pendingNoteWritesByItemID[itemID] {
                    let hasConflict =
                        pendingWrite.baselineContentDigest == nil
                        || pendingWrite.baselineContentDigest
                            != result.snapshot.sha256
                    if hasConflict {
                        if activeNoteItemID == itemID {
                            noteFileError = ui(
                                "检测到笔记冲突：魏碑草稿和外部文件都已保留，请对照后再处理。",
                                "A note conflict was detected. Both the WeiBei draft and external file were kept for review."
                            )
                        }
                    } else if activeNoteItemID == itemID {
                        noteFileError = noteOperationErrorsByItemID[itemID]
                    }
                } else {
                    if activeNoteItemID == itemID,
                       displayedText == noteText {
                        noteText = markdown
                    }
                    setNoteFileError(nil, for: itemID)
                }
                courseDocumentSearchIndex.schedule([
                    importedItems[currentIndex]
                ])
                save()
            } catch {
                guard courseNoteLoadGenerationByItemID[itemID] == generation else {
                    return
                }
                setNoteFileError(
                    ui(
                        "无法读取原 Markdown：\(url.lastPathComponent)",
                        "Could not read original Markdown: \(url.lastPathComponent)"
                    ),
                    for: itemID
                )
            }
        }
    }

    private func noteText(for item: StudyItem?) -> String {
        guard let item else {
            noteFileError = nil
            return defaultNote(for: nil)
        }
        if let pendingWrite = pendingNoteWritesByItemID[item.id],
           let cached = notesByItemID[item.id] {
            let isCourseOwned: Bool
            if case .courseOwned = item.storage {
                isCourseOwned = true
            } else {
                isCourseOwned = false
            }
            if isCourseOwned {
                scheduleCourseNoteLoad(item)
            }
            let diskDigest = isCourseOwned
                ? noteBackingContentDigestsByItemID[item.id]
                : item.url.flatMap(Self.noteContentDigest)
            if let diskDigest {
                noteBackingContentDigestsByItemID[item.id] = diskDigest
            }
            let hasConflict = diskDigest != nil
                && (pendingWrite.baselineContentDigest == nil || pendingWrite.baselineContentDigest != diskDigest)
            noteFileError = hasConflict ? ui(
                    "检测到笔记冲突：魏碑草稿和外部文件都已保留，请对照后再处理。",
                    "A note conflict was detected. Both the WeiBei draft and external file were kept for review."
                )
                : noteOperationErrorsByItemID[item.id]
            return cleanLegacyPlaceholder(cached)
        }
        guard item.editsBackingMarkdownFile, let url = item.url else {
            noteFileError = nil
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
        if case .courseOwned = item.storage {
            if let loaded = loadedCourseNoteTextByItemID[item.id] {
                noteFileError = nil
                return loaded
            }
            scheduleCourseNoteLoad(item)
            noteFileError = nil
            return cleanLegacyPlaceholder(
                notesByItemID[item.id] ?? defaultNote(for: item)
            )
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
        if let stagedNoteDraft, stagedNoteDraft.itemID == item.id {
            self.stagedNoteDraft = nil
            updateNote(stagedNoteDraft.value, for: item.id)
        }
        if pendingNotePersistenceByItemID[item.id] != nil {
            flushPendingNotePersistence(for: item.id)
        } else if pendingNoteWritesByItemID[item.id] != nil {
            persistNote(noteText, for: item)
        }
    }

    func flushPendingNotePersistence() {
        flushPendingNotePersistence(flushWorkspace: true)
    }

    func flushPendingNotePersistence(flushWorkspace: Bool) {
        let itemIDs = Array(pendingNotePersistenceByItemID.keys)
        itemIDs.forEach { flushPendingNotePersistence(for: $0) }
        studyProgressSaveTask?.cancel()
        studyProgressSaveTask = nil
        syncActiveStudySession()
        // Note flush is a durability boundary: write the workspace now, not after debounce.
        if flushWorkspace {
            _ = flushPendingWorkspaceSave()
        }
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
            let permitsSynchronousFallback = !importedItems.contains {
                guard $0.id == itemID else { return false }
                if case .courseOwned = $0.storage { return true }
                return false
            }
            baseline = noteBackingContentDigestsByItemID[itemID]
                ?? importedItems.first(where: { $0.id == itemID })?
                    .contentDigest
                ?? (permitsSynchronousFallback
                    ? fallbackURL.flatMap(Self.noteContentDigest)
                    : nil)
        }
        notesByItemID[itemID] = markdown
        pendingNoteWritesByItemID[itemID] = PendingNoteWriteState(
            baselineContentDigest: baseline
        )
    }

    private func beginCourseMarkdownWrite(
        _ markdown: String,
        item: StudyItem,
        expectedContentDigest: String?
    ) async throws -> CourseMarkdownWriteTransaction {
        guard item.isNotebookNote,
              case .courseOwned(let courseID) = item.storage,
              activeCourseRemovalTokens[courseID] == nil,
              let targetURL = item.url,
              let targetIdentity = item.importedFileIdentity,
              let root = courseRootURL(for: courseID),
              let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(
                root
              ),
              let canonicalRootIdentity = importedFileIdentityResolver(
                canonicalRoot
              ),
              let targetRelativePath = CourseProjectPathPolicy.relativePath(
                of: targetURL,
                inside: canonicalRoot
              ) else {
            throw CourseOwnedFileError.verificationFailed
        }
        let targetComponents = targetRelativePath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard targetComponents.count == 2,
              targetComponents.first
                == Substring(CourseOwnedFileRole.note.directoryName) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let destinationDirectory = targetURL.deletingLastPathComponent()
        guard let destinationDirectoryIdentity = importedFileIdentityResolver(
            destinationDirectory
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let targetSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: targetURL,
            expectedIdentity: targetIdentity
        )
        if let expectedContentDigest,
           targetSnapshot.sha256 != expectedContentDigest {
            throw CourseProjectFileWorkerError.contentConflict
        }

        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: canonicalRoot
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(
            transactionDirectory
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let journalURL = transactionDirectory.appendingPathComponent(
            "course-note.json"
        )
        let payloadURL = transactionDirectory.appendingPathComponent("payload")
        let originalURL = transactionDirectory.appendingPathComponent("original")
        let replacementSnapshot = await courseProjectFileWorker.snapshot(
            of: Data(markdown.utf8)
        )
        var journal = PendingCourseMarkdownWriteJournal(
            transactionID: transactionID,
            transactionDirectoryIdentity: transactionDirectoryIdentity,
            courseID: courseID,
            itemID: item.id,
            targetPath: targetURL.path,
            targetRelativePath: targetRelativePath,
            targetIdentity: targetIdentity,
            targetSnapshot: targetSnapshot,
            replacementSnapshot: replacementSnapshot,
            stagedIdentity: nil,
            stage: .prepared
        )
        do {
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            let staged = try await courseProjectFileWorker.stageMarkdown(
                markdown,
                to: payloadURL
            )
            guard staged.snapshot == replacementSnapshot else {
                throw CourseOwnedFileError.verificationFailed
            }
            journal.stagedIdentity = staged.identity
            journal.stage = .staged
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )

            try courseProjectMutationHook(
                .beforeCourseMarkdownTargetIsolation
            )
            guard await courseProjectFileWorker.isolateWithoutReplacement(
                from: targetURL,
                to: originalURL
            ) else {
                throw CourseProjectFileWorkerError.contentConflict
            }
            try courseProjectMutationHook(
                .afterCourseMarkdownTargetIsolationBeforeJournal
            )
            do {
                _ = try await courseProjectFileWorker.stableSnapshot(
                    at: originalURL,
                    expectedIdentity: targetIdentity,
                    expectedSnapshot: targetSnapshot
                )
            } catch {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: originalURL,
                    to: targetURL
                )
                throw CourseProjectFileWorkerError.contentConflict
            }
            journal.stage = .targetIsolated
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )

            let placedIdentity: ImportedFileIdentity
            do {
                placedIdentity = try await courseProjectFileWorker
                    .placeWithoutReplacement(
                        from: payloadURL,
                        to: targetURL,
                        courseRoot: canonicalRoot,
                        destinationDirectory: destinationDirectory,
                        expectedDestinationIdentity:
                            destinationDirectoryIdentity,
                        expectedSnapshot: replacementSnapshot
                    )
            } catch CourseProjectFileWorkerError.targetExists {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: originalURL,
                    to: targetURL
                )
                throw CourseProjectFileWorkerError.contentConflict
            }
            try courseProjectMutationHook(
                .afterCourseMarkdownTargetPlacementBeforeJournal
            )
            guard placedIdentity == staged.identity,
                  importedFileIdentityResolver(canonicalRoot)
                    == canonicalRootIdentity else {
                throw CourseOwnedFileError.verificationFailed
            }
            journal.stage = .placed
            try await courseProjectFileWorker.write(
                JSONEncoder().encode(journal),
                to: journalURL
            )
            let metadata = try await courseProjectFileWorker.stableMetadata(
                at: targetURL,
                expectedIdentity: placedIdentity,
                expectedSnapshot: replacementSnapshot
            )
            let values = try targetURL.resourceValues(
                forKeys: [.documentIdentifierKey]
            )
            return CourseMarkdownWriteTransaction(
                result: CourseMarkdownWriteResult(
                    snapshot: replacementSnapshot,
                    metadata: metadata,
                    documentIdentifier: values.documentIdentifier.flatMap {
                        $0 >= 0 ? UInt64($0) : nil
                    },
                    ranOnMainThread: staged.ranOnMainThread
                ),
                journal: journal,
                transactionDirectory: transactionDirectory
            )
        } catch {
            if WeiBeiSafetyTestMode.isEnabled, error is CourseProjectSimulatedCrash {
                throw error
            }
            await rollbackCourseMarkdownWrite(
                journal: journal,
                transactionDirectory: transactionDirectory
            )
            throw error
        }
    }

    private func rollbackCourseMarkdownWrite(
        journal: PendingCourseMarkdownWriteJournal,
        transactionDirectory: URL
    ) async {
        let targetURL = URL(fileURLWithPath: journal.targetPath)
            .standardizedFileURL
        let payloadURL = transactionDirectory.appendingPathComponent("payload")
        let originalURL = transactionDirectory.appendingPathComponent("original")
        if let stagedIdentity = journal.stagedIdentity {
            if CourseProjectFileWorker.identity(at: targetURL)
                == stagedIdentity {
                _ = await courseProjectFileWorker.isolateAndRemoveVerifiedFile(
                    at: targetURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "replacement-cleanup"
                    ),
                    expectedIdentity: stagedIdentity,
                    expectedSnapshot: journal.replacementSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
            }
            if CourseProjectFileWorker.identity(at: payloadURL)
                == stagedIdentity {
                _ = await courseProjectFileWorker.isolateAndRemoveVerifiedFile(
                    at: payloadURL,
                    quarantineURL: transactionDirectory.appendingPathComponent(
                        "payload-cleanup"
                    ),
                    expectedIdentity: stagedIdentity,
                    expectedSnapshot: journal.replacementSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
            }
        }
        if CourseProjectFileWorker.identity(at: targetURL) == nil,
           (try? await courseProjectFileWorker.stableSnapshot(
            at: originalURL,
            expectedIdentity: journal.targetIdentity,
            expectedSnapshot: journal.targetSnapshot
           )) != nil {
            _ = await courseProjectFileWorker.restoreIsolatedFile(
                from: originalURL,
                to: targetURL
            )
        }
        await safelyRemoveCourseMarkdownTransactionDirectoryInBackground(
            transactionDirectory,
            expectedIdentity: journal.transactionDirectoryIdentity
        )
    }

    private func finishCourseMarkdownWrite(
        _ transaction: CourseMarkdownWriteTransaction
    ) async {
        let targetURL = URL(
            fileURLWithPath: transaction.journal.targetPath
        ).standardizedFileURL
        guard let stagedIdentity = transaction.journal.stagedIdentity,
              (try? await courseProjectFileWorker.stableMetadata(
                at: targetURL,
                expectedIdentity: stagedIdentity,
                expectedSnapshot: transaction.journal.replacementSnapshot
              )) != nil else {
            return
        }
        let originalURL = transaction.transactionDirectory
            .appendingPathComponent("original")
        if CourseProjectFileWorker.identity(at: originalURL) != nil {
            _ = await courseProjectFileWorker.isolateAndRemoveVerifiedFile(
                at: originalURL,
                quarantineURL: transaction.transactionDirectory
                    .appendingPathComponent("original-cleanup"),
                expectedIdentity: transaction.journal.targetIdentity,
                expectedSnapshot: transaction.journal.targetSnapshot,
                remover: { try FileManager.default.removeItem(at: $0) }
            )
        }
        await safelyRemoveCourseMarkdownTransactionDirectoryInBackground(
            transaction.transactionDirectory,
            expectedIdentity:
                transaction.journal.transactionDirectoryIdentity
        )
    }

    private func persistCourseOwnedNote(
        _ markdown: String,
        itemID: String
    ) {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }),
              importedItems[index].isNotebookNote,
              case .courseOwned = importedItems[index].storage,
              importedItems[index].url != nil,
              importedItems[index].importedFileIdentity != nil else {
            retainPendingNoteWrite(
                markdown,
                itemID: itemID,
                fallbackURL: nil
            )
            setNoteFileError(
                ui(
                    "原 Markdown 已移动或不可用，最新编辑已安全保留在课程中。",
                    "The original Markdown moved or is unavailable. The latest edit is safely retained in the course."
                ),
                for: itemID
            )
            save()
            return
        }
        retainPendingNoteWrite(
            markdown,
            itemID: itemID,
            fallbackURL: nil
        )
        if Self.mustSaveImmediately {
            guard performSaveNow() else {
                setNoteFileError(
                    ui(
                        "最新编辑尚未安全保存到工作区，暂不写回原 Markdown。",
                        "The latest edit is not yet safely stored in the workspace, so the original Markdown was not changed."
                    ),
                    for: itemID
                )
                return
            }
            startCourseOwnedNoteWriteIfNeeded(itemID: itemID)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.persistWorkspaceNow() else {
                self.setNoteFileError(
                    self.ui(
                        "最新编辑尚未安全保存到工作区，暂不写回原 Markdown。",
                        "The latest edit is not yet safely stored in the workspace, so the original Markdown was not changed."
                    ),
                    for: itemID
                )
                return
            }
            self.startCourseOwnedNoteWriteIfNeeded(itemID: itemID)
        }
    }

    private func startCourseOwnedNoteWriteIfNeeded(itemID: String) {
        guard !courseNoteWritesInFlight.contains(itemID),
              let markdown = notesByItemID[itemID],
              let pendingWrite = pendingNoteWritesByItemID[itemID],
              let expectedDigest = pendingWrite.baselineContentDigest,
              let item = importedItems.first(where: { $0.id == itemID }),
              item.isNotebookNote,
              case .courseOwned = item.storage,
              let url = item.url,
              item.importedFileIdentity != nil else {
            return
        }
        courseNoteLoadGenerationByItemID[itemID, default: 0] &+= 1
        let generation = courseNoteLoadGenerationByItemID[itemID] ?? 0
        courseNoteLoadTasksByItemID[itemID]?.cancel()
        courseNoteLoadTasksByItemID[itemID] = nil
        courseNoteWritesInFlight.insert(itemID)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let transaction = try await beginCourseMarkdownWrite(
                    markdown,
                    item: item,
                    expectedContentDigest: expectedDigest
                )
                guard courseNoteLoadGenerationByItemID[itemID]
                        == generation else {
                    await rollbackCourseMarkdownWrite(
                        journal: transaction.journal,
                        transactionDirectory:
                            transaction.transactionDirectory
                    )
                    courseNoteWritesInFlight.remove(itemID)
                    courseNoteWriteTasksByItemID[itemID] = nil
                    if pendingNoteWritesByItemID[itemID] != nil {
                        startCourseOwnedNoteWriteIfNeeded(itemID: itemID)
                    }
                    return
                }
                let result = transaction.result
                let previousItems = importedItems
                let previousMemberships = courseItemMemberships
                let previousBackingDigests =
                    noteBackingContentDigestsByItemID
                let previousLoadedNotes = loadedCourseNoteTextByItemID
                let previousNotes = notesByItemID
                let previousPendingWrites = pendingNoteWritesByItemID
                lastCourseNoteWriteRanOnMainThread = result.ranOnMainThread
                applyCourseMarkdownWriteResult(
                    result,
                    itemID: itemID,
                    markdown: markdown
                )
                if notesByItemID[itemID] == markdown {
                    notesByItemID.removeValue(forKey: itemID)
                    pendingNoteWritesByItemID.removeValue(forKey: itemID)
                    setNoteFileError(nil, for: itemID)
                } else {
                    pendingNoteWritesByItemID[itemID] = PendingNoteWriteState(
                        baselineContentDigest: result.snapshot.sha256
                    )
                }
                guard await persistWorkspaceNow() else {
                    importedItems = previousItems
                    courseItemMemberships = previousMemberships
                    noteBackingContentDigestsByItemID =
                        previousBackingDigests
                    loadedCourseNoteTextByItemID = previousLoadedNotes
                    notesByItemID = previousNotes
                    pendingNoteWritesByItemID = previousPendingWrites
                    await rollbackCourseMarkdownWrite(
                        journal: transaction.journal,
                        transactionDirectory:
                            transaction.transactionDirectory
                    )
                    throw CourseOwnedFileError.workspaceSaveFailed
                }
                await finishCourseMarkdownWrite(transaction)
                courseNoteWritesInFlight.remove(itemID)
                courseNoteWriteTasksByItemID[itemID] = nil
                if pendingNoteWritesByItemID[itemID] != nil {
                    startCourseOwnedNoteWriteIfNeeded(itemID: itemID)
                }
            } catch CourseProjectFileWorkerError.contentConflict {
                guard courseNoteLoadGenerationByItemID[itemID]
                        == generation else {
                    return
                }
                courseNoteWritesInFlight.remove(itemID)
                courseNoteWriteTasksByItemID[itemID] = nil
                if activeNoteItemID == itemID {
                    noteFileError = ui(
                        "检测到笔记冲突：没有覆盖外部文件，魏碑草稿也已保留。请对照两份内容后再处理。",
                        "A note conflict was detected. The external file was not overwritten, and the WeiBei draft was retained for review."
                    )
                }
                scheduleCourseNoteLoad(item)
                save()
            } catch {
                guard courseNoteLoadGenerationByItemID[itemID]
                        == generation else {
                    return
                }
                courseNoteWritesInFlight.remove(itemID)
                courseNoteWriteTasksByItemID[itemID] = nil
                setNoteFileError(
                    ui(
                        "无法写回原 Markdown：\(url.lastPathComponent)",
                        "Could not write original Markdown: \(url.lastPathComponent)"
                    ),
                    for: itemID
                )
                save()
            }
        }
        courseNoteWriteTasksByItemID[itemID] = task
    }

    private func applyCourseMarkdownWriteResult(
        _ result: CourseMarkdownWriteResult,
        itemID: String,
        markdown: String
    ) {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }),
              case .courseOwned = importedItems[index].storage else {
            return
        }
        if importedItems[index].contentDigest != result.snapshot.sha256 {
            importedItems[index].contentRevision &+= 1
        }
        importedItems[index].contentDigest = result.snapshot.sha256
        importedItems[index].fileByteCount = result.metadata.byteCount
        importedItems[index].fileModificationTimeNanoseconds =
            result.metadata.modificationTimeNanoseconds
        importedItems[index].importedFileIdentity = result.metadata.identity
        importedItems[index].urlPath = result.metadata.url.path
        importedItems[index].importedFileLastKnownPath =
            result.metadata.url.path
        importedItems[index].title =
            result.metadata.url.deletingPathExtension().lastPathComponent
        importedItems[index].subtitle = result.metadata.url.lastPathComponent
        importedItems[index].kind = StudyItemKind.detect(
            from: result.metadata.url
        )
        noteBackingContentDigestsByItemID[itemID] = result.snapshot.sha256
        loadedCourseNoteTextByItemID[itemID] =
            cleanLegacyPlaceholder(markdown)
        if let membershipIndex = courseItemMemberships.firstIndex(
            where: { $0.itemID == itemID }
        ) {
            courseItemMemberships[membershipIndex].entryIdentity =
                result.metadata.identity
            courseItemMemberships[membershipIndex].documentIdentifier =
                result.documentIdentifier
        }
        courseDocumentSearchIndex.schedule([importedItems[index]])
    }

    private func persistNote(_ markdown: String, for item: StudyItem) {
        let noteItemID = item.id
        if item.editsBackingMarkdownFile {
            guard let index = importedItems.firstIndex(where: { $0.id == noteItemID }) else {
                retainPendingNoteWrite(markdown, itemID: noteItemID, fallbackURL: item.url)
                setNoteFileError(
                    ui("无法确认原 Markdown 的课程身份。", "Could not resolve the original Markdown identity."),
                    for: noteItemID
                )
                save()
                return
            }
            if case .courseOwned = importedItems[index].storage {
                persistCourseOwnedNote(markdown, itemID: noteItemID)
                return
            }
            let resolution = resolveTrackedImportedFile(at: index)
            guard let url = resolution.url else {
                retainPendingNoteWrite(markdown, itemID: noteItemID, fallbackURL: item.url)
                setNoteFileError(
                    ui(
                        "原 Markdown 已移动或不可用，最新编辑已安全保留在课程中。",
                        "The original Markdown moved or is unavailable. The latest edit is safely retained in the course."
                    ),
                    for: noteItemID
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
                if activeNoteItemID == noteItemID {
                    noteFileError = ui(
                        "检测到笔记冲突：没有覆盖外部文件，魏碑草稿也已保留。请对照两份内容后再处理。",
                        "A note conflict was detected. The external file was not overwritten, and the WeiBei draft was retained for review."
                    )
                }
                save()
                return
            }
            do {
                try notebookMarkdownWriter(markdown, url)
                notesByItemID.removeValue(forKey: noteItemID)
                pendingNoteWritesByItemID.removeValue(forKey: noteItemID)
                noteBackingContentDigestsByItemID[noteItemID] = Self.noteContentDigest(Data(markdown.utf8))
                setNoteFileError(nil, for: noteItemID)
                let refreshedItem = refreshImportedFileTracking(itemID: noteItemID, url: url)
                    ?? importedItems[index]
                courseDocumentSearchIndex.schedule([refreshedItem])
                save()
            } catch {
                retainPendingNoteWrite(markdown, itemID: noteItemID, fallbackURL: url)
                setNoteFileError(
                    ui(
                        "无法写回原 Markdown：\(url.lastPathComponent)",
                        "Could not write original Markdown: \(url.lastPathComponent)"
                    ),
                    for: noteItemID
                )
                save()
            }
            return
        }
        notesByItemID[noteItemID] = markdown
    }

    private func coursePortableStateURL(for courseID: UUID) -> URL? {
        guard let root = courseRootURL(for: courseID),
              let metadata = try? CourseProjectPathPolicy.existingDirectory(
                root.appendingPathComponent(".weibei", isDirectory: true)
              ),
              CourseProjectPathPolicy.contains(root, metadata, includingRoot: false),
              CourseProjectPathPolicy.isSame(
                metadata,
                metadata.resolvingSymlinksInPath()
              ) else {
            return nil
        }
        return metadata.appendingPathComponent(
            "course-state.json",
            isDirectory: false
        )
    }

    private func makeCoursePortableState(
        courseID: UUID,
        revision: UInt64,
        savedAt: Date
    ) throws -> CoursePortableState {
        guard let course = course(withID: courseID) else {
            throw CoursePortableStateError.courseIdentityMismatch
        }
        let memberships = courseItemMemberships
            .filter { $0.courseID == courseID }
            .sorted {
                ($0.courseRelativePath ?? "").localizedStandardCompare(
                    $1.courseRelativePath ?? ""
                ) == .orderedAscending
            }
        var portableItems: [CoursePortableItem] = []
        for membership in memberships {
            guard let relativePath = membership.courseRelativePath else {
                throw CoursePortableStateError.missingCourseItem
            }
            guard let item = importedItems.first(where: {
                $0.id == membership.itemID
            }) else {
                throw CoursePortableStateError.missingCourseItem
            }
            let storage: CoursePortableItemStorage
            switch item.storage {
            case .courseOwned(let ownerCourseID) where ownerCourseID == courseID:
                storage = .courseOwned
            case let .shared(sharedRelativePath):
                storage = .sharedReference(
                    sharedRelativePath: sharedRelativePath,
                    expectedContentDigest: item.contentDigest
                )
            default:
                throw CoursePortableStateError.invalidItemStorage
            }
            portableItems.append(
                CoursePortableItem(
                    itemID: item.id,
                    title: item.title,
                    kind: item.kind,
                    isNotebookNote: item.isNotebookNote,
                    courseRelativePath: relativePath,
                    storage: storage,
                    contentRevision: item.contentRevision,
                    contentDigest: item.contentDigest,
                    fileByteCount: item.fileByteCount,
                    fileModificationTimeNanoseconds:
                        item.fileModificationTimeNanoseconds,
                    membershipCreatedAt: membership.createdAt
                )
            )
        }

        let portableItemIDs = Set(portableItems.map(\.itemID))
        let noteItemIDs = Set(
            portableItems.lazy.filter(\.isNotebookNote).map(\.itemID)
        )
        let materialItemIDs = portableItemIDs.subtracting(noteItemIDs)
        let rawMemoryState = learningMemoryStates.first {
            $0.scope == .course(courseID)
        }
        let memoryIDs = Set(rawMemoryState?.entries.map(\.id) ?? [])
        let relations = noteSourceLinks.filter {
            noteItemIDs.contains($0.noteItemID)
                && materialItemIDs.contains($0.sourceItemID)
        }
        .sorted {
            $0.createdAt == $1.createdAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.createdAt < $1.createdAt
        }
        let relationIDs = Set(relations.map(\.id))
        var relationsByID: [UUID: NoteSourceLink] = [:]
        for relation in relations {
            relationsByID[relation.id] = relation
        }
        let sessions = studySessions.compactMap { current -> StudySession? in
            guard current.courseID == courseID,
                  current.scopeNeedsReview == false else {
                return nil
            }
            var portable = current
            portable.focusItemIDs = portable.focusItemIDs.filter(
                portableItemIDs.contains
            )
            if let materialItemID = portable.materialItemID,
               !materialItemIDs.contains(materialItemID) {
                portable.materialItemID = nil
            }
            for index in portable.messages.indices {
                portable.messages[index].toolTrace = []
                portable.messages[index].sources = portable.messages[index].sources
                    .filter { source in
                        guard let itemID = source.itemID else {
                            return source.courseID.map {
                                $0 == courseID
                            } ?? true
                        }
                        guard portableItemIDs.contains(itemID),
                              source.courseID.map({
                                  $0 == courseID
                              }) ?? true else {
                            return false
                        }
                        switch source.kind {
                        case .material:
                            return materialItemIDs.contains(itemID)
                        case .note:
                            return noteItemIDs.contains(itemID)
                        case .selection:
                            return true
                        }
                    }
                portable.messages[index].actions = portable.messages[index].actions
                    .filter { action in
                        guard action.targetItemID.map(
                            portableItemIDs.contains
                        ) ?? true,
                        action.sourceItemID.map(
                            portableItemIDs.contains
                        ) ?? true else {
                            return false
                        }
                        switch action.kind {
                        case .writeNote:
                            let hasValidTarget = action.targetItemID.map(
                                noteItemIDs.contains
                            ) ?? true
                            return hasValidTarget
                                && action.createdRelationID == nil
                        case .createRelation:
                            let hasValidTarget = action.targetItemID.map(
                                noteItemIDs.contains
                            ) ?? true
                            let hasValidSource = action.sourceItemID.map(
                                    materialItemIDs.contains
                                ) ?? true
                            let hasValidCreatedRelation =
                                action.createdRelationID.map { relationID in
                                    guard relationIDs.contains(relationID),
                                          let relation =
                                            relationsByID[relationID],
                                          let targetItemID =
                                            action.targetItemID,
                                          let sourceItemID =
                                            action.sourceItemID else {
                                        return false
                                    }
                                    return relation.noteItemID
                                        == targetItemID
                                        && relation.sourceItemID
                                            == sourceItemID
                                } ?? true
                            return hasValidTarget
                                && hasValidSource
                                && hasValidCreatedRelation
                        }
                    }
                if var memoryUpdate =
                    portable.messages[index].memoryUpdate {
                    memoryUpdate.memoryIDs = memoryUpdate.memoryIDs.filter(
                        memoryIDs.contains
                    )
                    portable.messages[index].memoryUpdate =
                        memoryUpdate.memoryIDs.isEmpty ? nil : memoryUpdate
                }
                if let origin = portable.messages[index].origin,
                   origin.courseID != courseID
                    || origin.chatID != portable.id {
                    portable.messages[index].origin = nil
                }
            }
            return portable
        }
        .sorted { $0.createdAt < $1.createdAt }
        let messageIDsBySessionID = Dictionary(
            uniqueKeysWithValues: sessions.map {
                ($0.id, Set($0.messages.map(\.id)))
            }
        )
        func sanitizedMemoryProvenance(
            sessionID: UUID?,
            messageID: UUID?
        ) -> (sessionID: UUID?, messageID: UUID?) {
            guard let sessionID,
                  let liveMessageIDs =
                    messageIDsBySessionID[sessionID] else {
                return (nil, nil)
            }
            guard let messageID else {
                return (sessionID, nil)
            }
            return liveMessageIDs.contains(messageID)
                ? (sessionID, messageID)
                : (sessionID, nil)
        }
        var memoryState = rawMemoryState
        if var sanitizedMemoryState = memoryState {
            for entryIndex in sanitizedMemoryState.entries.indices {
                var entry = sanitizedMemoryState.entries[entryIndex]
                let entryProvenance = sanitizedMemoryProvenance(
                    sessionID: entry.sessionID,
                    messageID: entry.messageID
                )
                entry.sessionID = entryProvenance.sessionID
                entry.messageID = entryProvenance.messageID
                if var revisions = entry.revisions {
                    for revisionIndex in revisions.indices {
                        let revisionProvenance =
                            sanitizedMemoryProvenance(
                                sessionID:
                                    revisions[revisionIndex].sessionID,
                                messageID:
                                    revisions[revisionIndex].messageID
                            )
                        revisions[revisionIndex].sessionID =
                            revisionProvenance.sessionID
                        revisions[revisionIndex].messageID =
                            revisionProvenance.messageID
                    }
                    entry.revisions = revisions
                }
                sanitizedMemoryState.entries[entryIndex] = entry
            }
            memoryState = sanitizedMemoryState
        }
        var locations: [String: StudyLocation] = [:]
        for itemID in materialItemIDs.sorted() {
            if let location = studyLocation(for: itemID, in: courseID) {
                var scoped = location
                scoped.itemID = itemID
                locations[itemID] = scoped
            }
        }
        let drafts = noteItemIDs.sorted().compactMap {
            itemID -> CoursePortableNoteDraft? in
            guard let pending = pendingNoteWritesByItemID[itemID],
                  let markdown = notesByItemID[itemID] else {
                return nil
            }
            return CoursePortableNoteDraft(
                itemID: itemID,
                markdown: markdown,
                baselineContentDigest: pending.baselineContentDigest
            )
        }
        return try CoursePortableState(
            courseID: courseID,
            revision: revision,
            savedAt: savedAt,
            metadata: CoursePortableMetadata(
                title: course.title,
                colorIndex: course.colorIndex,
                createdAt: course.createdAt,
                updatedAt: course.updatedAt
            ),
            items: portableItems,
            studySessions: [],
            learningMemoryState: memoryState,
            courseKnowledgeProfile: courseKnowledgeProfiles.first {
                $0.courseID == courseID
            }?.retainingAvailableSources(
                materialItemIDs: materialItemIDs,
                noteItemIDs: noteItemIDs
            ),
            noteSourceLinks: relations,
            studyLocationsByItemID: locations,
            resumePoint: courseResumePoint(for: courseID),
            pendingNoteDrafts: drafts
        ).validated(expectedCourseID: courseID)
    }

    private func encodedCoursePortableState(
        _ state: CoursePortableState
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    private func coursePortableStatePayloadDigest(
        _ state: CoursePortableState
    ) throws -> String {
        var normalized = state
        normalized.revision = 0
        normalized.savedAt = Date(timeIntervalSince1970: 0)
        return Self.noteContentDigest(
            try encodedCoursePortableState(normalized)
        )
    }

    private func readCoursePortableState(
        at url: URL,
        expectedCourseID: UUID
    ) throws -> CoursePortableState {
        guard let directoryIdentity = CourseProjectFileWorker.identity(
            at: url.deletingLastPathComponent()
        ) else {
            throw CoursePortableStateError.unsafeRelativePath
        }
        let data = try CourseProjectFileWorker.readPortableState(
            at: url,
            expectedDirectoryIdentity: directoryIdentity
        )
        return try JSONDecoder()
            .decode(CoursePortableState.self, from: data)
            .validated(expectedCourseID: expectedCourseID)
    }

    @discardableResult
    private func restorePortableCourseStates() -> Bool {
        var changed = false
        for courseID in courses.map(\.id) {
            let cachedState = try? makeCoursePortableState(
                courseID: courseID,
                revision: coursePortableStateRevisions[courseID] ?? 0,
                savedAt: Date(timeIntervalSince1970: 0)
            )
            let cachedDigest = cachedState.flatMap {
                try? coursePortableStatePayloadDigest($0)
            }
            guard let stateURL = coursePortableStateURL(for: courseID) else {
                if cachedDigest != coursePortableStateDigests[courseID] {
                    dirtyPortableCourseIDs.insert(courseID)
                }
                continue
            }
            guard FileManager.default.fileExists(atPath: stateURL.path) else {
                needsPortableCourseStateBootstrap = true
                if coursePortableStateDigests[courseID] != nil {
                    dirtyPortableCourseIDs.insert(courseID)
                }
                continue
            }
            do {
                let state = try readCoursePortableState(
                    at: stateURL,
                    expectedCourseID: courseID
                )
                let diskDigest = try coursePortableStatePayloadDigest(state)
                let knownRevision = coursePortableStateRevisions[courseID]
                let knownDigest = coursePortableStateDigests[courseID]
                if knownRevision == nil || knownDigest == nil {
                    let canEstablishLegacyBaseline =
                        knownRevision == nil
                        && knownDigest == nil
                        && !dirtyPortableCourseIDs.contains(courseID)
                        && cachedDigest == diskDigest
                    guard canEstablishLegacyBaseline else {
                        dirtyPortableCourseIDs.insert(courseID)
                        blockedPortableCourseIDs.insert(courseID)
                        needsPortableCourseStateBootstrap = true
                        workspaceSaveError = ui(
                            "“\(course(withID: courseID)?.title ?? "课程")”的本机内容与课程文件夹首次建立可携带基线时不一致，魏碑已保留两边并停止自动覆盖。",
                            "The local course content did not match the course folder while establishing its first portable baseline. WeiBei preserved both sides and stopped automatic overwrites."
                        )
                        changed = true
                        continue
                    }
                    // Existing legacy workspaces are the local source of truth
                    // on first upgrade. An equal payload can establish the
                    // baseline without replaying the disk snapshot over local
                    // chats, memories, drafts, or shared canonical items.
                    coursePortableStateRevisions[courseID] = state.revision
                    coursePortableStateDigests[courseID] = diskDigest
                    changed = true
                    continue
                }
                guard let knownRevision, let knownDigest else {
                    throw CoursePortableStateError.stateConflict
                }
                if dirtyPortableCourseIDs.contains(courseID) {
                    guard state.revision == knownRevision,
                          knownDigest == diskDigest else {
                        blockedPortableCourseIDs.insert(courseID)
                        workspaceSaveError = ui(
                            "“\(course(withID: courseID)?.title ?? "课程")”在文件夹与本机缓存中都发生了变化，魏碑已停止自动覆盖。",
                            "This course changed both in its folder and in the local cache. Automatic overwrite was stopped."
                        )
                        continue
                    }
                    coursePortableStateRevisions[courseID] =
                        max(knownRevision, state.revision)
                    needsPortableCourseStateBootstrap = true
                    continue
                }
                guard state.revision >= knownRevision else {
                    throw CoursePortableStateError.stateConflict
                }
                if state.revision == knownRevision,
                   knownDigest != diskDigest {
                    throw CoursePortableStateError.stateConflict
                }
                try applyCoursePortableState(state, courseID: courseID)
                coursePortableStateRevisions[courseID] = state.revision
                coursePortableStateDigests[courseID] = diskDigest
                changed = true
            } catch {
                blockedPortableCourseIDs.insert(courseID)
                workspaceSaveError = ui(
                    "“\(course(withID: courseID)?.title ?? "课程")”的可携带状态无法安全读取，原文件已保留且不会被自动覆盖：\(error.localizedDescription)",
                    "The portable state for this course could not be read safely. The original file was preserved and will not be overwritten automatically: \(error.localizedDescription)"
                )
            }
        }
        return changed
    }

    private func rawCourseItemURL(
        relativePath: String,
        inside root: URL
    ) -> URL? {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else {
            return nil
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let parent = components.dropLast().reduce(canonicalRoot) {
            $0.appendingPathComponent(String($1), isDirectory: true)
        }
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        guard CourseProjectPathPolicy.contains(
            canonicalRoot,
            resolvedParent,
            includingRoot: true
        ) else {
            return nil
        }
        let candidate = resolvedParent.appendingPathComponent(
            String(components.last!),
            isDirectory: false
        ).standardizedFileURL
        guard CourseProjectPathPolicy.contains(
            canonicalRoot,
            candidate,
            includingRoot: false
        ) else {
            return nil
        }
        return candidate
    }

    private func validatedPortableCourseOwnedFile(
        at candidate: URL,
        portable: CoursePortableItem
    ) throws -> (
        identity: ImportedFileIdentity,
        documentIdentifier: UInt64?
    )? {
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .absent:
            return nil
        case .inaccessible:
            throw CoursePortableStateError.unsafeRelativePath
        case .present:
            break
        }
        let values = try candidate.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              !CourseProjectFileWorker.isSymbolicLink(at: candidate),
              CourseProjectPathPolicy.isSame(
                  candidate,
                  candidate.resolvingSymlinksInPath()
              ),
              StudyItemKind.detect(from: candidate) == portable.kind,
              let identity = importedFileIdentityResolver(candidate),
              importedFileIdentityResolver(candidate) == identity else {
            throw CoursePortableStateError.invalidItemStorage
        }
        let documentIdentifier = try candidate.resourceValues(
            forKeys: [.documentIdentifierKey]
        ).documentIdentifier.flatMap {
            $0 >= 0 ? UInt64($0) : nil
        }
        guard importedFileIdentityResolver(candidate) == identity else {
            throw CoursePortableStateError.invalidItemStorage
        }
        return (identity, documentIdentifier)
    }

    private func resolvedSharedPortableFile(
        relativePath: String,
        expectedDigest: String,
        expectedKind: StudyItemKind,
        isNotebookNote: Bool
    ) throws -> (url: URL, identity: ImportedFileIdentity)? {
        guard let libraryRoot = courseLibraryRootURL else {
            return nil
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        let role: CourseOwnedFileRole = isNotebookNote ? .note : .material
        let allowedDirectories: Set<Substring> = role == .note
            ? [Substring(role.commonDirectoryName)]
            : [Substring(role.commonDirectoryName), "共享文稿"]
        guard components.count == 2,
              allowedDirectories.contains(components[0]),
              let candidate = CourseProjectPathPolicy.resolvedRelativePath(
                  relativePath,
                  inside: libraryRoot
              ),
              CourseProjectPathPolicy.isSame(
                  candidate.deletingLastPathComponent(),
                  libraryRoot.appendingPathComponent(
                      String(components[0]),
                      isDirectory: true
                  )
                  .resolvingSymlinksInPath()
                  .standardizedFileURL
              ) else {
            throw CoursePortableStateError.crossCourseReference
        }
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .absent:
            return nil
        case .inaccessible:
            throw CoursePortableStateError.crossCourseReference
        case .present:
            break
        }
        let values = try candidate.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              !CourseProjectFileWorker.isSymbolicLink(at: candidate),
              CourseProjectPathPolicy.isSame(
                  candidate,
                  candidate.resolvingSymlinksInPath()
              ),
              StudyItemKind.detect(from: candidate) == expectedKind,
              let identity = importedFileIdentityResolver(candidate) else {
            throw CoursePortableStateError.crossCourseReference
        }
        let snapshot = try CourseProjectFileWorker.snapshotFile(
            at: candidate
        )
        guard snapshot.sha256 == expectedDigest,
              importedFileIdentityResolver(candidate) == identity else {
            return nil
        }
        return (candidate, identity)
    }

    private func validatedPortableSharedLink(
        at candidate: URL,
        sharedURL: URL
    ) throws -> ImportedFileIdentity? {
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .absent:
            return nil
        case .inaccessible:
            throw CoursePortableStateError.invalidItemStorage
        case .present:
            break
        }
        guard CourseProjectFileWorker.isSymbolicLink(at: candidate),
              let identity = importedFileIdentityResolver(candidate),
              CourseProjectFileWorker.symbolicLink(
                  at: candidate,
                  pointsTo: sharedURL
              ),
              importedFileIdentityResolver(candidate) == identity else {
            throw CoursePortableStateError.invalidItemStorage
        }
        return identity
    }

    private func applyCoursePortableState(
        _ rawState: CoursePortableState,
        courseID: UUID
    ) throws {
        let state = try rawState.validated(expectedCourseID: courseID)
        guard let courseIndex = courses.firstIndex(where: {
            $0.id == courseID
        }),
        let root = courseRootURL(for: courseID) else {
            throw CoursePortableStateError.courseIdentityMismatch
        }

        let previousMemberships = courseItemMemberships.filter {
            $0.courseID == courseID
        }
        let previousItemIDs = Set(previousMemberships.map(\.itemID))
        let previousNoteIDs = Set(
            importedItems.lazy.filter {
                previousItemIDs.contains($0.id) && $0.isNotebookNote
            }.map(\.id)
        )
        let otherCourseItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID != courseID
            }.map(\.itemID)
        )
        let previousRelationIDs = Set(
            noteSourceLinks.lazy.filter {
                previousNoteIDs.contains($0.noteItemID)
            }.map(\.id)
        )
        let retainedRelationIDs = Set(
            noteSourceLinks.lazy.filter {
                !previousRelationIDs.contains($0.id)
            }.map(\.id)
        )
        guard retainedRelationIDs.isDisjoint(
            with: Set(state.noteSourceLinks.map(\.id))
        ) else {
            throw CoursePortableStateError.invalidRelation
        }

        var restoredItemsByID: [String: StudyItem] = [:]
        var restoredMemberships: [CourseItemMembership] = []
        for portable in state.items {
            guard let candidate = rawCourseItemURL(
                relativePath: portable.courseRelativePath,
                inside: root
            ) else {
                throw CoursePortableStateError.unsafeRelativePath
            }
            let storage: StudyItemStorage
            let itemURL: URL?
            let itemIdentity: ImportedFileIdentity?
            let membershipIdentity: ImportedFileIdentity?
            let membershipDocumentIdentifier: UInt64?
            let preservedExistingShared: StudyItem?
            let existing = importedItems.first {
                $0.id == portable.itemID
            }
            switch portable.storage {
            case .courseOwned:
                storage = .courseOwned(ownerCourseID: courseID)
                preservedExistingShared = nil
                let candidateIdentity =
                    try validatedPortableCourseOwnedFile(
                    at: candidate,
                    portable: portable
                )
                itemIdentity = candidateIdentity?.identity
                membershipIdentity = candidateIdentity?.identity
                membershipDocumentIdentifier =
                    candidateIdentity?.documentIdentifier
                itemURL = itemIdentity == nil ? nil : candidate
            case let .sharedReference(
                sharedRelativePath,
                expectedContentDigest
            ):
                guard let expectedContentDigest else {
                    throw CoursePortableStateError.invalidItemStorage
                }
                storage = .shared(sharedRelativePath: sharedRelativePath)
                let existingBelongsToKnownCourse = existing.map {
                    previousItemIDs.contains($0.id)
                        || otherCourseItemIDs.contains($0.id)
                } ?? false
                let existingIsCurrentCanonical: Bool
                if existingBelongsToKnownCourse,
                   let existing,
                   let existingURL = existing.url,
                   let existingIdentity = existing.importedFileIdentity,
                   let existingDigest = existing.contentDigest,
                   let currentCanonical =
                    try? resolvedSharedPortableFile(
                        relativePath: sharedRelativePath,
                        expectedDigest: existingDigest,
                        expectedKind: existing.kind,
                        isNotebookNote: existing.isNotebookNote
                   ),
                   CourseProjectPathPolicy.isSame(
                       currentCanonical.url,
                       existingURL
                   ),
                   currentCanonical.identity == existingIdentity {
                    existingIsCurrentCanonical = true
                } else {
                    existingIsCurrentCanonical = false
                }
                if let existing, existingIsCurrentCanonical {
                    guard case let .shared(existingSharedPath) =
                            existing.storage,
                          existingSharedPath == sharedRelativePath else {
                        throw CoursePortableStateError.crossCourseReference
                    }
                    // A shared item is one canonical workspace record used by
                    // every course. A single course's older portable snapshot
                    // may restore its membership, but it must not downgrade the
                    // canonical file URL, identity, bookmark, digest, or file
                    // metadata already verified by the workspace.
                    preservedExistingShared = existing
                    itemURL = existing.url
                    itemIdentity = existing.importedFileIdentity
                } else {
                    preservedExistingShared = nil
                    let resolved = try resolvedSharedPortableFile(
                        relativePath: sharedRelativePath,
                        expectedDigest: expectedContentDigest,
                        expectedKind: portable.kind,
                        isNotebookNote: portable.isNotebookNote
                    )
                    itemURL = resolved?.url
                    itemIdentity = resolved?.identity
                }
                let recordedLibraryRoot = (
                    courseLibraryRootURL
                        ?? courseLibraryRootPath.flatMap {
                            guard $0.hasPrefix("/") else { return nil }
                            return URL(
                                fileURLWithPath: $0,
                                isDirectory: true
                            ).standardizedFileURL
                        }
                )
                if let recordedLibraryRoot {
                    guard let sharedLinkTarget = CourseProjectPathPolicy
                        .resolvedRelativePath(
                            sharedRelativePath,
                            inside: recordedLibraryRoot
                        ) else {
                        throw CoursePortableStateError.invalidItemStorage
                    }
                    membershipIdentity = try validatedPortableSharedLink(
                        at: candidate,
                        sharedURL: sharedLinkTarget
                    )
                } else {
                    membershipIdentity = nil
                }
                membershipDocumentIdentifier = nil
            }
            if let existing,
            !previousItemIDs.contains(existing.id),
            existing.storage != storage {
                throw CoursePortableStateError.crossCourseReference
            }
            restoredItemsByID[portable.itemID] =
                preservedExistingShared
                ?? StudyItem(
                    id: portable.itemID,
                    title: portable.title,
                    subtitle: candidate.lastPathComponent,
                    kind: portable.kind,
                    urlPath: itemURL?.path,
                    importedFileIdentity: itemIdentity,
                    importedFileBookmarkData: nil,
                    importedFileLastKnownPath: itemURL?.path,
                    isSample: false,
                    isNotebookNote: portable.isNotebookNote,
                    storage: storage,
                    contentRevision: portable.contentRevision,
                    contentDigest: portable.contentDigest,
                    fileByteCount: portable.fileByteCount,
                    fileModificationTimeNanoseconds:
                        portable.fileModificationTimeNanoseconds
                )
            restoredMemberships.append(
                CourseItemMembership(
                    courseID: courseID,
                    itemID: portable.itemID,
                    courseRelativePath: portable.courseRelativePath,
                    entryIdentity: membershipIdentity,
                    documentIdentifier: membershipDocumentIdentifier,
                    createdAt: portable.membershipCreatedAt
                )
            )
        }

        importedItems.removeAll { item in
            previousItemIDs.contains(item.id)
                && !otherCourseItemIDs.contains(item.id)
        }
        for item in restoredItemsByID.values.sorted(by: {
            $0.id < $1.id
        }) {
            if let existingIndex = importedItems.firstIndex(where: {
                $0.id == item.id
            }) {
                importedItems[existingIndex] = item
            } else {
                importedItems.append(item)
            }
        }
        courseItemMemberships.removeAll { $0.courseID == courseID }
        courseItemMemberships.append(contentsOf: restoredMemberships)

        var restoredCourse = courses[courseIndex]
        restoredCourse.title = state.metadata.title
        restoredCourse.colorIndex = state.metadata.colorIndex
        restoredCourse.createdAt = state.metadata.createdAt
        restoredCourse.updatedAt = state.metadata.updatedAt
        courses[courseIndex] = restoredCourse

        if state.schemaVersion == 1 {
            for var legacySession in state.studySessions {
                if let index = studySessions.firstIndex(where: {
                    $0.id == legacySession.id
                }) {
                    let related = Set(studySessions[index].relatedCourseIDs)
                        .union(legacySession.relatedCourseIDs)
                        .union([courseID])
                    studySessions[index].relatedCourseIDs = related.sorted {
                        $0.uuidString < $1.uuidString
                    }
                } else {
                    legacySession.relatedCourseIDs = Set(
                        legacySession.relatedCourseIDs + [courseID]
                    ).sorted { $0.uuidString < $1.uuidString }
                    studySessions.append(legacySession)
                }
            }
        }
        if let chatID = state.resumePoint?.chatID,
           let index = studySessions.firstIndex(where: { $0.id == chatID }),
           !studySessions[index].relatedCourseIDs.contains(courseID) {
            studySessions[index].relatedCourseIDs.append(courseID)
            studySessions[index].relatedCourseIDs.sort {
                $0.uuidString < $1.uuidString
            }
        }
        if let activeStudySessionID,
           let active = studySessions.first(where: {
               $0.id == activeStudySessionID
           }) {
            messages = active.messages
        }

        learningMemoryStates.removeAll {
            $0.scope == .course(courseID)
        }
        if let memoryState = state.learningMemoryState {
            learningMemoryStates.append(memoryState)
        }
        courseKnowledgeProfiles.removeAll { $0.courseID == courseID }
        courseKnowledgeProfiles.append(
            state.courseKnowledgeProfile ?? CourseKnowledgeProfile(courseID: courseID)
        )

        noteSourceLinks.removeAll {
            previousNoteIDs.contains($0.noteItemID)
        }
        noteSourceLinks.append(contentsOf: state.noteSourceLinks)
        studyLocationsByCourseID[courseID.uuidString] =
            state.studyLocationsByItemID
        courseResumePoints.removeAll { $0.courseID == courseID }
        if let resumePoint = state.resumePoint {
            courseResumePoints.append(resumePoint)
        }

        let restoredNoteIDs = Set(
            state.items.lazy.filter(\.isNotebookNote).map(\.itemID)
        )
        for itemID in previousNoteIDs.union(restoredNoteIDs) {
            notesByItemID.removeValue(forKey: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
        }
        for item in state.items where item.isNotebookNote {
            noteBackingContentDigestsByItemID[item.itemID] =
                item.contentDigest
        }
        for draft in state.pendingNoteDrafts {
            notesByItemID[draft.itemID] = draft.markdown
            pendingNoteWritesByItemID[draft.itemID] =
                PendingNoteWriteState(
                    baselineContentDigest: draft.baselineContentDigest
                )
        }
    }

    @discardableResult
    private func persistCoursePortableStates(
        courseIDs requestedCourseIDs: Set<UUID>? = nil
    ) throws -> CoursePortableStateCommit {
        let courseIDs = requestedCourseIDs ?? Set(courses.map(\.id))
        let previousRevisions = coursePortableStateRevisions
        let previousDigests = coursePortableStateDigests
        let previousDirty = dirtyPortableCourseIDs
        let previousBlocked = blockedPortableCourseIDs
        let previousOversized = oversizedPortableCourseIDs
        let previousNeedsBootstrap = needsPortableCourseStateBootstrap
        var committedWrites: [CoursePortableStateWriteRecord] = []
        var conflictedCourseID: UUID?
        do {
            for courseID in courses.map(\.id)
            where courseIDs.contains(courseID) {
                let currentRevision =
                    coursePortableStateRevisions[courseID] ?? 0
                let knownRevision =
                    coursePortableStateRevisions[courseID]
                let knownDigest = coursePortableStateDigests[courseID]
                let stateURL = coursePortableStateURL(for: courseID)
                let hasPortableHistory =
                    knownRevision != nil
                    || knownDigest != nil
                    || dirtyPortableCourseIDs.contains(courseID)
                    || blockedPortableCourseIDs.contains(courseID)
                guard stateURL != nil || hasPortableHistory else {
                    // Legacy courses without a real project root remain valid
                    // workspace-only records until the user explicitly moves
                    // their files into a course folder.
                    continue
                }
                let candidate: CoursePortableState
                do {
                    candidate = try makeCoursePortableState(
                        courseID: courseID,
                        revision: currentRevision,
                        savedAt: Date(timeIntervalSince1970: 0)
                    )
                } catch {
                    let awaitsLegacyOrganization =
                        courseItemMemberships.contains { membership in
                            guard membership.courseID == courseID,
                                  let item = importedItems.first(where: {
                                      $0.id == membership.itemID
                                  }) else {
                                return false
                            }
                            return item.storage == .legacyExternal
                        }
                    if awaitsLegacyOrganization {
                        continue
                    }
                    guard stateURL == nil, hasPortableHistory else {
                        throw error
                    }
                    // A previously portable course may be temporarily offline.
                    // Preserve its workspace snapshot and conflict state instead
                    // of letting an unavailable root block every workspace save.
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.insert(courseID)
                    continue
                }
                var committed = candidate
                committed.revision = currentRevision &+ 1
                committed.savedAt = Date()
                let committedData = try encodedCoursePortableState(
                    committed
                )
                if committedData.count
                    > CourseProjectFileWorker
                        .portableStateMaximumByteCount {
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.insert(courseID)
                    oversizedPortableCourseIDs.insert(courseID)
                    needsPortableCourseStateBootstrap = true
                    continue
                }
                let payloadDigest = try coursePortableStatePayloadDigest(
                    candidate
                )
                guard let stateURL else {
                    oversizedPortableCourseIDs.remove(courseID)
                    if knownDigest != payloadDigest {
                        dirtyPortableCourseIDs.insert(courseID)
                    }
                    continue
                }
                let stateExists = FileManager.default.fileExists(
                    atPath: stateURL.path
                )
                guard let directoryIdentity =
                        CourseProjectFileWorker.identity(
                            at: stateURL.deletingLastPathComponent()
                        ) else {
                    throw CoursePortableStateError.unsafeRelativePath
                }
                if oversizedPortableCourseIDs.remove(courseID) != nil {
                    blockedPortableCourseIDs.remove(courseID)
                }
                if blockedPortableCourseIDs.contains(courseID) {
                    if knownDigest != payloadDigest {
                        dirtyPortableCourseIDs.insert(courseID)
                    }
                    continue
                }
                if knownDigest == payloadDigest, stateExists {
                    dirtyPortableCourseIDs.remove(courseID)
                    continue
                }
                if stateExists {
                    guard let knownDigest,
                          let diskState = try? readCoursePortableState(
                              at: stateURL,
                              expectedCourseID: courseID
                          ),
                          diskState.revision == currentRevision,
                          (try? coursePortableStatePayloadDigest(
                              diskState
                          )) == knownDigest else {
                        dirtyPortableCourseIDs.insert(courseID)
                        blockedPortableCourseIDs.insert(courseID)
                        continue
                    }
                }
                let previousData = stateExists
                    ? try CourseProjectFileWorker.readPortableState(
                        at: stateURL,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                    : nil
                do {
                    try coursePortableStateWriter(
                        committedData,
                        stateURL,
                        directoryIdentity,
                        previousData,
                        {
                            try courseProjectMutationHook(
                                .beforeCoursePortableStateCASPlacement
                            )
                        }
                    )
                    let verified = try readCoursePortableState(
                        at: stateURL,
                        expectedCourseID: courseID
                    )
                    guard verified.revision == committed.revision,
                          try coursePortableStatePayloadDigest(verified)
                            == payloadDigest else {
                        throw CoursePortableStateError
                            .writeVerificationFailed
                    }
                } catch CourseProjectFileWorkerError.contentConflict {
                    conflictedCourseID = courseID
                    throw CoursePortableStateError.stateConflict
                } catch {
                    try restorePortableStateFile(
                        at: stateURL,
                        previousData: previousData,
                        attemptedData: committedData,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                    throw error
                }
                committedWrites.append(
                    CoursePortableStateWriteRecord(
                        url: stateURL,
                        previousData: previousData,
                        committedData: committedData,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                )
                coursePortableStateRevisions[courseID] =
                    committed.revision
                coursePortableStateDigests[courseID] = payloadDigest
                dirtyPortableCourseIDs.remove(courseID)
            }
        } catch {
            var rollbackFailed = false
            for write in committedWrites.reversed() {
                do {
                    try restorePortableStateFile(
                        at: write.url,
                        previousData: write.previousData,
                        attemptedData: write.committedData,
                        expectedDirectoryIdentity:
                            write.expectedDirectoryIdentity
                    )
                } catch {
                    rollbackFailed = true
                }
            }
            coursePortableStateRevisions = previousRevisions
            coursePortableStateDigests = previousDigests
            dirtyPortableCourseIDs = previousDirty
            blockedPortableCourseIDs = previousBlocked
            oversizedPortableCourseIDs = previousOversized
            needsPortableCourseStateBootstrap = previousNeedsBootstrap
            if let conflictedCourseID {
                dirtyPortableCourseIDs.insert(conflictedCourseID)
                blockedPortableCourseIDs.insert(conflictedCourseID)
                needsPortableCourseStateBootstrap = true
            }
            if rollbackFailed {
                throw CoursePortableStateError.stateConflict
            }
            throw error
        }
        needsPortableCourseStateBootstrap =
            !dirtyPortableCourseIDs.isEmpty
        return CoursePortableStateCommit(
            writes: committedWrites,
            previousRevisions: previousRevisions,
            previousDigests: previousDigests,
            previousDirtyCourseIDs: previousDirty,
            previousBlockedCourseIDs: previousBlocked,
            previousOversizedCourseIDs: previousOversized,
            previousNeedsBootstrap: previousNeedsBootstrap
        )
    }

    private func rollbackCoursePortableStateCommit(
        _ commit: CoursePortableStateCommit
    ) throws {
        var rollbackFailed = false
        for write in commit.writes.reversed() {
            do {
                try restorePortableStateFile(
                    at: write.url,
                    previousData: write.previousData,
                    attemptedData: write.committedData,
                    expectedDirectoryIdentity:
                        write.expectedDirectoryIdentity
                )
            } catch {
                rollbackFailed = true
            }
        }
        coursePortableStateRevisions = commit.previousRevisions
        coursePortableStateDigests = commit.previousDigests
        dirtyPortableCourseIDs = commit.previousDirtyCourseIDs
        blockedPortableCourseIDs = commit.previousBlockedCourseIDs
        oversizedPortableCourseIDs =
            commit.previousOversizedCourseIDs
        needsPortableCourseStateBootstrap =
            commit.previousNeedsBootstrap
        if rollbackFailed {
            throw CoursePortableStateError.stateConflict
        }
    }

    private func restorePortableStateFile(
        at url: URL,
        previousData: Data?,
        attemptedData: Data,
        expectedDirectoryIdentity: ImportedFileIdentity
    ) throws {
        try CourseProjectFileWorker.restorePortableState(
            at: url,
            previousData: previousData,
            attemptedData: attemptedData,
            expectedDirectoryIdentity: expectedDirectoryIdentity
        )
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
        persistedWorkspaceCourseIDs = Set(courses.map(\.id))
        coursePortableStateRevisions = Dictionary(
            uniqueKeysWithValues: (snapshot.coursePortableStateRevisions ?? [:])
                .compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
        )
        coursePortableStateDigests = Dictionary(
            uniqueKeysWithValues: (snapshot.coursePortableStateDigests ?? [:])
                .compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
        )
        dirtyPortableCourseIDs = Set(
            snapshot.dirtyPortableCourseIDs ?? []
        )
        courseItemMemberships = CourseItemMemberships(
            values: snapshot.courseItemMemberships ?? []
        ).values
        activeCourseID = snapshot.activeCourseID
        courseLibraryRootPath = snapshot.courseLibraryRootPath
        courseLibraryRootIdentity = snapshot.courseLibraryRootIdentity
        courseLibraryRootBookmarkData = snapshot.courseLibraryRootBookmarkData
        noteSourceLinks = snapshot.noteSourceLinks ?? []
        noteSourceLinksMigrationVersion = snapshot.noteSourceLinksMigrationVersion ?? 0
        materialNotePairings = snapshot.materialNotePairings ?? [:]
        noteMaterialPairings = snapshot.noteMaterialPairings ?? [:]
        studyLocationsByItemID = snapshot.studyLocationsByItemID ?? [:]
        studyLocationsByCourseID = snapshot.studyLocationsByCourseID ?? [:]
        courseResumePoints = snapshot.courseResumePoints ?? []
        migrateCourseStudyLocationsFromLegacyIfNeeded()
        learningMemoryStates = snapshot.learningMemoryStates ?? []
        courseKnowledgeProfiles = snapshot.courseKnowledgeProfiles ?? []
        learningMemoryScopeMigrationVersion = snapshot.learningMemoryScopeMigrationVersion ?? 0
        legacyLearningMemoryEntries = snapshot.learningMemoryEntries ?? []
        legacyLearningMemoryRevision = snapshot.learningMemoryRevision ?? 0
        studySessions = (snapshot.studySessions ?? []).map { session in
            var bounded = session
            for index in bounded.messages.indices
            where bounded.messages[index].completionState == .generating {
                recoveredInterruptedAgentReply = true
                bounded.messages[index].completionState = .interrupted
                bounded.messages[index].failureKind = .cancelled
                if bounded.messages[index].retryQuestion == nil {
                    bounded.messages[index].retryQuestion = bounded.messages[..<index]
                        .last(where: { $0.role == .user })?
                        .text
                }
            }
            return bounded
        }
        studySessionScopeMigrationVersion = snapshot.studySessionScopeMigrationVersion ?? 0
        activeStudySessionID = snapshot.activeStudySessionID
        if let persistedSelectionAskThreads = snapshot.selectionAskThreads {
            loadedSelectionAskThreadsFromWorkspaceSnapshot = true
            selectionAskThreads = persistedSelectionAskThreads
            selectionAskThreadDefaults.removeObject(forKey: Self.legacySelectionAskThreadsDefaultsKey)
        }
        if selectedItem?.isNotebookNote == true {
            activeNotebookItemID = selectedItemID
            selectedItemID = nil
        }
        if let activeNotebookItemID,
           !allItems.contains(where: { $0.id == activeNotebookItemID && $0.isNotebookNote }) {
            self.activeNotebookItemID = nil
        }
        materialNotePairings = materialNotePairings.filter {
            item(withID: $0.key)?.isNotebookNote == false
                && item(withID: $0.value)?.isNotebookNote == true
        }
        noteMaterialPairings = noteMaterialPairings.filter {
            item(withID: $0.key)?.isNotebookNote == true
                && item(withID: $0.value)?.isNotebookNote == false
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

    private var persistedStudySessions: [StudySession] {
        studySessions.filter {
            $0.id != freshlyCreatedEmptyStudySessionID || !$0.messages.isEmpty
        }
    }

    private var persistedActiveStudySessionID: UUID? {
        let sessions = persistedStudySessions
        guard sessions.contains(where: { $0.id == activeStudySessionID }) else {
            return sessions.max(by: { $0.updatedAt < $1.updatedAt })?.id
        }
        return activeStudySessionID
    }

    private func makePersistedWorkspaceSnapshot()
        -> (snapshot: PersistedWorkspace, resumePoints: [CourseResumePoint]) {
        let resumePoints = sanitizedCourseResumePoints()
        return (
            PersistedWorkspace(
                importedItems: importedItems,
                notesByItemID: notesByItemID,
                pendingNoteWritesByItemID: pendingNoteWritesByItemID,
                noteBackingContentDigestsByItemID:
                    noteBackingContentDigestsByItemID,
                selectedItemID: selectedItemID,
                activeNotebookItemID: activeNotebookItemID,
                courses: courses,
                courseItemMemberships: courseItemMemberships,
                activeCourseID: activeCourseID,
                courseLibraryRootPath: courseLibraryRootPath,
                courseLibraryRootIdentity: courseLibraryRootIdentity,
                courseLibraryRootBookmarkData:
                    courseLibraryRootBookmarkData,
                noteSourceLinks: noteSourceLinks,
                noteSourceLinksMigrationVersion:
                    noteSourceLinksMigrationVersion,
                materialNotePairings: materialNotePairings,
                noteMaterialPairings: noteMaterialPairings,
                studyLocationsByItemID: studyLocationsByItemID,
                studyLocationsByCourseID: studyLocationsByCourseID,
                courseResumePoints: resumePoints,
                coursePortableStateRevisions: Dictionary(
                    uniqueKeysWithValues: coursePortableStateRevisions.map {
                        ($0.key.uuidString.lowercased(), $0.value)
                    }
                ),
                coursePortableStateDigests: Dictionary(
                    uniqueKeysWithValues: coursePortableStateDigests.map {
                        ($0.key.uuidString.lowercased(), $0.value)
                    }
                ),
                dirtyPortableCourseIDs: dirtyPortableCourseIDs.sorted {
                    $0.uuidString < $1.uuidString
                },
                learningMemoryStates: learningMemoryStates,
                courseKnowledgeProfiles: sanitizedCourseKnowledgeProfiles(),
                learningMemoryScopeMigrationVersion:
                    learningMemoryScopeMigrationVersion,
                studySessions: persistedStudySessions,
                studySessionScopeMigrationVersion:
                    studySessionScopeMigrationVersion,
                activeStudySessionID: persistedActiveStudySessionID,
                selectionAskThreads: selectionAskThreads,
                modelName: modelName,
                agentProviderID: agentProviderID.rawValue,
                agentBaseURL: agentBaseURL.isEmpty ? nil : agentBaseURL,
                workspaceLayout: layout,
                threePaneOrder: normalizedThreePaneOrder,
                agentSurface:
                    agentSurface == .selectionFloat ? .hidden : agentSurface,
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
            ),
            resumePoints
        )
    }

    private func removingCourse(
        _ courseID: UUID,
        from source: PersistedWorkspace
    ) -> PersistedWorkspace {
        var workspace = source
        let removedItemIDs = Set(
            workspace.importedItems.compactMap { item -> String? in
                guard case .courseOwned(let ownerCourseID) = item.storage,
                      ownerCourseID == courseID else {
                    return nil
                }
                return item.id
            }
        )
        workspace.importedItems.removeAll {
            removedItemIDs.contains($0.id)
        }
        workspace.notesByItemID = workspace.notesByItemID.filter {
            !removedItemIDs.contains($0.key)
        }
        workspace.pendingNoteWritesByItemID =
            workspace.pendingNoteWritesByItemID?.filter {
                !removedItemIDs.contains($0.key)
            }
        workspace.noteBackingContentDigestsByItemID =
            workspace.noteBackingContentDigestsByItemID?.filter {
                !removedItemIDs.contains($0.key)
            }
        if workspace.selectedItemID.map(
            removedItemIDs.contains
        ) == true {
            workspace.selectedItemID =
                workspace.importedItems.first?.id
        }
        if workspace.activeNotebookItemID.map(
            removedItemIDs.contains
        ) == true {
            workspace.activeNotebookItemID =
                workspace.importedItems.first(
                    where: \.isNotebookNote
                )?.id
        }

        workspace.courses?.removeAll { $0.id == courseID }
        workspace.courseItemMemberships?.removeAll {
            $0.courseID == courseID
        }
        if workspace.activeCourseID == courseID {
            workspace.activeCourseID = workspace.courses?.first?.id
        }
        workspace.noteSourceLinks?.removeAll {
            removedItemIDs.contains($0.noteItemID)
                || removedItemIDs.contains($0.sourceItemID)
        }
        workspace.materialNotePairings =
            workspace.materialNotePairings?.filter {
                !removedItemIDs.contains($0.key)
                    && !removedItemIDs.contains($0.value)
            }
        workspace.noteMaterialPairings =
            workspace.noteMaterialPairings?.filter {
                !removedItemIDs.contains($0.key)
                    && !removedItemIDs.contains($0.value)
            }
        workspace.studyLocationsByItemID =
            workspace.studyLocationsByItemID?.filter {
                !removedItemIDs.contains($0.key)
            }
        workspace.studyLocationsByCourseID?.removeValue(
            forKey: courseID.uuidString
        )
        workspace.courseResumePoints?.removeAll {
            $0.courseID == courseID
        }
        let portableKey = courseID.uuidString.lowercased()
        workspace.coursePortableStateRevisions?.removeValue(
            forKey: portableKey
        )
        workspace.coursePortableStateDigests?.removeValue(
            forKey: portableKey
        )
        workspace.dirtyPortableCourseIDs?.removeAll {
            $0 == courseID
        }
        workspace.learningMemoryStates?.removeAll {
            $0.scope == .course(courseID)
        }
        workspace.courseKnowledgeProfiles?.removeAll {
            $0.courseID == courseID
        }
        if workspace.studySessions != nil {
            for index in workspace.studySessions!.indices {
                workspace.studySessions![index].relatedCourseIDs.removeAll {
                    $0 == courseID
                }
                workspace.studySessions![index].focusItemIDs.removeAll {
                    removedItemIDs.contains($0)
                }
                if workspace.studySessions![index].materialItemID.map(
                    removedItemIDs.contains
                ) == true {
                    workspace.studySessions![index].materialItemID = nil
                }
            }
        }
        workspace.selectionAskThreads =
            workspace.selectionAskThreads?.compactMap {
                thread -> SelectionAskThread? in
                if thread.itemID.map(
                    removedItemIDs.contains
                ) == true {
                    return nil
                }
                return thread
            }
        return workspace
    }

    private func makeWorkspacePersistenceRequest(
        generation: UInt64,
        skippingPortableCourseIDs: Set<UUID>
    ) throws -> (
        request: WorkspacePersistenceRequest,
        resumePoints: [CourseResumePoint]
    ) {
        var persisted = makePersistedWorkspaceSnapshot()
        if let removingCourseID =
                workspacePersistenceRemovingCourseID {
            persisted.snapshot = removingCourse(
                removingCourseID,
                from: persisted.snapshot
            )
            persisted.resumePoints =
                persisted.snapshot.courseResumePoints ?? []
        }
        var requestedCourseIDs = persistedWorkspaceCourseIDs
            .intersection(Set(courses.map(\.id)))
            .subtracting(skippingPortableCourseIDs)
        if let removingCourseID =
                workspacePersistenceRemovingCourseID {
            requestedCourseIDs.remove(removingCourseID)
        }
        let inputs = courses.compactMap {
            course -> CoursePortableStateSaveInput? in
            guard requestedCourseIDs.contains(course.id) else { return nil }
            return CoursePortableStateSaveInput(
                courseID: course.id,
                rootURL: resolvedCourseRootURLs[course.id],
                knownRevision: coursePortableStateRevisions[course.id],
                knownDigest: coursePortableStateDigests[course.id]
            )
        }
        let removingCourseIDs = workspacePersistenceRemovingCourseID
            .map { Set([$0]) } ?? []
        return (
            WorkspacePersistenceRequest(
                generation: generation,
                workspace: persisted.snapshot,
                storageURL: storageURL,
                portableInputs: inputs,
                blockedPortableCourseIDs:
                    blockedPortableCourseIDs.subtracting(
                        removingCourseIDs
                    ),
                oversizedPortableCourseIDs:
                    oversizedPortableCourseIDs.subtracting(
                        removingCourseIDs
                    ),
                needsPortableBootstrap: needsPortableCourseStateBootstrap
            ),
            persisted.resumePoints
        )
    }

    /// Schedule a coalesced workspace snapshot write. Verification keeps the
    /// legacy synchronous path; production saves use the file worker actor.
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
        checkpointActiveAgentStreamingText()
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = nil
        workspaceSaveGeneration &+= 1
        workspacePersistenceSkippingCourseIDs = []
        if Self.mustSaveImmediately {
            return performSaveNow()
        }
        return (try? waitForCourseFileOperation {
            await self.startWorkspacePersistenceLoop().value
        }) ?? false
    }

    @discardableResult
    func flushPendingWorkspaceSaveAsync() async -> Bool {
        checkpointActiveAgentStreamingText()
        return await persistWorkspaceNow()
    }

    @discardableResult
    private func persistWorkspaceNow(
        skippingPortableCourseIDs: Set<UUID> = []
    ) async -> Bool {
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = nil
        workspaceSaveGeneration &+= 1
        workspacePersistenceSkippingCourseIDs =
            skippingPortableCourseIDs
#if DEBUG
        if Self.mustSaveImmediately
            && !usesBackgroundWorkspacePersistenceForSelfCheck {
            return performSaveNow(
                skippingPortableCourseIDs:
                    skippingPortableCourseIDs
            )
        }
#endif
        return await startWorkspacePersistenceLoop().value
    }

    private func persistWorkspaceRemovingCourse(
        _ courseID: UUID
    ) async -> Bool {
        guard workspacePersistenceRemovingCourseID == nil else {
            return false
        }
#if DEBUG
        if Self.mustSaveImmediately
            && !usesBackgroundWorkspacePersistenceForSelfCheck {
            do {
                let persisted = removingCourse(
                    courseID,
                    from: makePersistedWorkspaceSnapshot().snapshot
                )
                try workspaceSnapshotWriter(
                    JSONEncoder().encode(persisted),
                    storageURL
                )
                coursePortableStateRevisions.removeValue(
                    forKey: courseID
                )
                coursePortableStateDigests.removeValue(
                    forKey: courseID
                )
                dirtyPortableCourseIDs.remove(courseID)
                blockedPortableCourseIDs.remove(courseID)
                oversizedPortableCourseIDs.remove(courseID)
                persistedWorkspaceCourseIDs = Set(
                    persisted.courses?.map(\.id) ?? []
                )
                courseResumePoints =
                    persisted.courseResumePoints ?? []
                if workspaceSaveError != nil {
                    workspaceSaveError = nil
                }
                return true
            } catch {
                workspaceSaveError = ui(
                    "课程更改尚未写入磁盘：\(error.localizedDescription)",
                    "Course changes were not saved to disk: \(error.localizedDescription)"
                )
                return false
            }
        }
#endif
        let previousRevision =
            coursePortableStateRevisions[courseID]
        let previousDigest =
            coursePortableStateDigests[courseID]
        let wasDirty = dirtyPortableCourseIDs.contains(courseID)
        let wasBlocked = blockedPortableCourseIDs.contains(courseID)
        let wasOversized =
            oversizedPortableCourseIDs.contains(courseID)
        let wasPersisted =
            persistedWorkspaceCourseIDs.contains(courseID)
        workspacePersistenceRemovingCourseID = courseID
        workspaceRemovalCommitObserved = false
        defer {
            workspacePersistenceRemovingCourseID = nil
            workspaceRemovalCommitObserved = false
        }
        guard await persistWorkspaceNow() else {
            if workspaceRemovalCommitObserved {
                scheduleDebouncedWorkspaceSave()
                return true
            }
            coursePortableStateRevisions[courseID] =
                previousRevision
            coursePortableStateDigests[courseID] =
                previousDigest
            if wasDirty {
                dirtyPortableCourseIDs.insert(courseID)
            } else {
                dirtyPortableCourseIDs.remove(courseID)
            }
            if wasBlocked {
                blockedPortableCourseIDs.insert(courseID)
            } else {
                blockedPortableCourseIDs.remove(courseID)
            }
            if wasOversized {
                oversizedPortableCourseIDs.insert(courseID)
            } else {
                oversizedPortableCourseIDs.remove(courseID)
            }
            if wasPersisted {
                persistedWorkspaceCourseIDs.insert(courseID)
            } else {
                persistedWorkspaceCourseIDs.remove(courseID)
            }
            return false
        }
        return true
    }

    private static var mustSaveImmediately: Bool {
#if DEBUG
        if WeiBeiSafetyTestMode.isEnabled { return true }
#endif
        return false
    }

    private func scheduleDebouncedWorkspaceSave() {
        workspaceSaveGeneration &+= 1
        workspacePersistenceSkippingCourseIDs = []
        let generation = workspaceSaveGeneration
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.workspaceSaveDebounceNanoseconds ?? 280_000_000)
            guard let self, !Task.isCancelled, self.workspaceSaveGeneration == generation else { return }
            _ = await self.startWorkspacePersistenceLoop().value
        }
    }

    private func startWorkspacePersistenceLoop() -> Task<Bool, Never> {
        if let workspacePersistenceTask {
            return workspacePersistenceTask
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            defer { self.workspacePersistenceTask = nil }
            var saved = true
            while true {
                let generation = self.workspaceSaveGeneration
                let skippingPortableCourseIDs =
                    self.workspacePersistenceSkippingCourseIDs
                saved = await self.performWorkspacePersistence(
                    generation: generation,
                    skippingPortableCourseIDs:
                        skippingPortableCourseIDs
                )
                guard self.workspaceSaveGeneration != generation else {
                    return saved
                }
                self.pendingWorkspaceSaveTask?.cancel()
                self.pendingWorkspaceSaveTask = nil
            }
        }
        workspacePersistenceTask = task
        return task
    }

    private func performWorkspacePersistence(
        generation: UInt64,
        skippingPortableCourseIDs: Set<UUID> = []
    ) async -> Bool {
        let publishSpan = WeiBeiPerf.begin(
            "workspace.save_transaction_to_ui_publish"
        )
        var publishOutcome = "failed"
        defer {
            WeiBeiPerf.end(
                publishSpan,
                extra:
                    "outcome=\(publishOutcome) generation=\(generation)"
            )
        }
        let prepared: (
            request: WorkspacePersistenceRequest,
            resumePoints: [CourseResumePoint]
        )
        let snapshotSpan = WeiBeiPerf.begin(
            "workspace.save_snapshot"
        )
        do {
            prepared = try makeWorkspacePersistenceRequest(
                generation: generation,
                skippingPortableCourseIDs: skippingPortableCourseIDs
            )
            WeiBeiPerf.end(
                snapshotSpan,
                extra: "outcome=completed generation=\(generation)"
            )
        } catch {
            WeiBeiPerf.end(
                snapshotSpan,
                extra: "outcome=failed generation=\(generation)"
            )
            guard workspaceSaveGeneration == generation else { return true }
            workspaceSaveError = ui(
                "课程可携带状态没有成功保存：\(error.localizedDescription)",
                "Portable course state was not saved: \(error.localizedDescription)"
            )
            return false
        }
        let result = await courseProjectFileWorker.persistWorkspace(
            prepared.request
        )
        if result.failure == nil,
           let removingCourseID =
                workspacePersistenceRemovingCourseID,
           prepared.request.workspace.courses?.contains(
            where: { $0.id == removingCourseID }
           ) != true {
            workspaceRemovalCommitObserved = true
        }
        lastWorkspacePersistenceRanOnMainThread = result.ranOnMainThread
        if case .stale? = result.failure {
            publishOutcome = "superseded"
            return true
        }
        let hasNewerGeneration =
            workspaceSaveGeneration != generation
        let requestedRevisions = Dictionary(
            uniqueKeysWithValues:
                (
                    prepared.request.workspace
                        .coursePortableStateRevisions ?? [:]
                ).compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
        )
        let requestedDigests = Dictionary(
            uniqueKeysWithValues:
                (
                    prepared.request.workspace
                        .coursePortableStateDigests ?? [:]
                ).compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
        )
        let requestedDirty = Set(
            prepared.request.workspace.dirtyPortableCourseIDs ?? []
        )
        func mergingSet(
            _ committed: Set<UUID>,
            requested: Set<UUID>,
            live: Set<UUID>
        ) -> Set<UUID> {
            let changed = requested.symmetricDifference(live)
            return committed.subtracting(changed)
                .union(live.intersection(changed))
        }
        func mergingDictionary<Value: Equatable>(
            _ committed: [UUID: Value],
            requested: [UUID: Value],
            live: [UUID: Value]
        ) -> [UUID: Value] {
            var merged = committed
            for key in Set(requested.keys).union(live.keys)
            where requested[key] != live[key] {
                merged[key] = live[key]
            }
            return merged
        }
        // A newer in-memory generation may arrive while this transaction is
        // on disk. Keep the committed CAS baseline before building that next
        // generation; otherwise it would compare against an obsolete revision
        // and falsely report a conflict.
        if hasNewerGeneration {
            coursePortableStateRevisions = mergingDictionary(
                result.portableStateRevisions,
                requested: requestedRevisions,
                live: coursePortableStateRevisions
            )
            coursePortableStateDigests = mergingDictionary(
                result.portableStateDigests,
                requested: requestedDigests,
                live: coursePortableStateDigests
            )
            dirtyPortableCourseIDs = mergingSet(
                result.dirtyPortableCourseIDs,
                requested: requestedDirty,
                live: dirtyPortableCourseIDs
            )
            blockedPortableCourseIDs = mergingSet(
                result.blockedPortableCourseIDs,
                requested:
                    prepared.request.blockedPortableCourseIDs,
                live: blockedPortableCourseIDs
            )
            oversizedPortableCourseIDs = mergingSet(
                result.oversizedPortableCourseIDs,
                requested:
                    prepared.request.oversizedPortableCourseIDs,
                live: oversizedPortableCourseIDs
            )
            if needsPortableCourseStateBootstrap
                == prepared.request.needsPortableBootstrap {
                needsPortableCourseStateBootstrap =
                    result.needsPortableBootstrap
            }
        } else {
            coursePortableStateRevisions =
                result.portableStateRevisions
            coursePortableStateDigests =
                result.portableStateDigests
            dirtyPortableCourseIDs =
                result.dirtyPortableCourseIDs
            blockedPortableCourseIDs =
                result.blockedPortableCourseIDs
            oversizedPortableCourseIDs =
                result.oversizedPortableCourseIDs
            needsPortableCourseStateBootstrap =
                result.needsPortableBootstrap
        }
        if result.failure == nil {
            persistedWorkspaceCourseIDs = result.persistedCourseIDs
        }
        guard workspaceSaveGeneration == generation else {
            publishOutcome = "superseded"
            return true
        }
        if let failure = result.failure {
            switch failure {
            case .portableState(let detail):
                workspaceSaveError = ui(
                    "课程可携带状态没有成功保存：\(detail)",
                    "Portable course state was not saved: \(detail)"
                )
            case .workspace(let detail):
                workspaceSaveError = ui(
                    "课程更改尚未写入磁盘：\(detail)",
                    "Course changes were not saved to disk: \(detail)"
                )
            case .rollbackConflict:
                workspaceSaveError = ui(
                    "课程状态提交失败且检测到并发变更，魏碑已停止覆盖并保留现场。",
                    "The course state commit failed during a concurrent change. WeiBei stopped overwriting and preserved the files for recovery."
                )
            case .stale:
                publishOutcome = "superseded"
                return true
            }
            return false
        }
        courseResumePoints = prepared.resumePoints
        if !oversizedPortableCourseIDs.isEmpty {
            workspaceSaveError = ui(
                "工作区内容已保存，但有课程的可携带状态超过 32 MB；课程文件夹中的原状态保持不变。请精简课程 Chat 或未写入草稿后重试。",
                "The workspace was saved, but a portable course state exceeds 32 MB. The state in the course folder was left unchanged. Reduce course chats or pending drafts, then retry."
            )
        } else if blockedPortableCourseIDs.isEmpty {
            if workspaceSaveError != nil {
                workspaceSaveError = nil
            }
        } else {
            workspaceSaveError = ui(
                "有课程状态存在冲突或损坏，原文件与本机缓存均已保留；魏碑不会自动覆盖。",
                "A course state is conflicted or damaged. Both the original file and local cache were preserved, and WeiBei will not overwrite either automatically."
            )
        }
        needsSelectionAskThreadsWorkspaceMigration = false
        loadedSelectionAskThreadsFromWorkspaceSnapshot = true
        if shouldRemoveLegacySelectionAskThreadsAfterSave {
            selectionAskThreadDefaults.removeObject(
                forKey: Self.legacySelectionAskThreadsDefaultsKey
            )
            shouldRemoveLegacySelectionAskThreadsAfterSave = false
        }
        publishOutcome = "completed"
        return true
    }

#if DEBUG
    func verifyBackgroundWorkspacePersistenceForSelfCheck(
        courseID: UUID
    ) throws -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
                || WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            let initialRevision =
                self.coursePortableStateRevisions[courseID]
            guard let courseIndex = self.courses.firstIndex(where: {
                $0.id == courseID
            }) else {
                return false
            }
            let untouchedCourseID = UUID()
            self.blockedPortableCourseIDs.insert(untouchedCourseID)
            self.oversizedPortableCourseIDs.insert(untouchedCourseID)
            self.courses[courseIndex].title =
                "后台保存课程（第一代）"
            self.courses[courseIndex].updatedAt = Date()
            self.modelName = "background-save-generation-one"
            self.workspaceSaveGeneration &+= 1
            let firstGeneration = self.workspaceSaveGeneration
            await self.courseProjectFileWorker
                .prepareWorkspacePersistenceGateForSelfCheck(
                    generation: firstGeneration
                )
            let persistenceLoop = self.startWorkspacePersistenceLoop()
            await self.courseProjectFileWorker
                .waitUntilWorkspacePersistenceEnteredForSelfCheck(
                    generation: firstGeneration
                )

            self.courses[courseIndex].title =
                "后台保存课程（第二代）"
            self.courses[courseIndex].updatedAt = Date()
            self.modelName = "background-save-generation-two"
            self.workspaceSaveGeneration &+= 1
            let joinedPersistenceLoop =
                self.startWorkspacePersistenceLoop()
            await self.courseProjectFileWorker
                .releaseWorkspacePersistenceForSelfCheck(
                    generation: firstGeneration
                )
            guard await joinedPersistenceLoop.value,
                  await persistenceLoop.value else {
                return false
            }
            let persistedData = try Data(contentsOf: self.storageURL)
            let persisted = try JSONDecoder().decode(
                PersistedWorkspace.self,
                from: persistedData
            )
            return self.lastWorkspacePersistenceRanOnMainThread == false
                && persisted.modelName
                    == "background-save-generation-two"
                && persisted.courses?.first(where: {
                    $0.id == courseID
                })?.title == "后台保存课程（第二代）"
                && self.coursePortableStateRevisions[courseID]
                    == (initialRevision ?? 0) + 2
                && self.blockedPortableCourseIDs
                    .contains(untouchedCourseID)
                && self.oversizedPortableCourseIDs
                    .contains(untouchedCourseID)
        }
    }
#endif

    @discardableResult
    private func performSaveNow(
        skippingPortableCourseIDs: Set<UUID> = []
    ) -> Bool {
        WeiBeiPerf.measure("workspace.save") {
            let portableCommit: CoursePortableStateCommit
            do {
                portableCommit = try persistCoursePortableStates(
                    courseIDs: persistedWorkspaceCourseIDs.intersection(
                        Set(courses.map(\.id))
                    ).subtracting(skippingPortableCourseIDs)
                )
            } catch {
                workspaceSaveError = ui(
                    "课程可携带状态没有成功保存：\(error.localizedDescription)",
                    "Portable course state was not saved: \(error.localizedDescription)"
                )
                return false
            }
            let persistedCourseResumePoints = sanitizedCourseResumePoints()
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
                courseLibraryRootPath: courseLibraryRootPath,
                courseLibraryRootIdentity: courseLibraryRootIdentity,
                courseLibraryRootBookmarkData: courseLibraryRootBookmarkData,
                noteSourceLinks: noteSourceLinks,
                noteSourceLinksMigrationVersion: noteSourceLinksMigrationVersion,
                materialNotePairings: materialNotePairings,
                noteMaterialPairings: noteMaterialPairings,
                studyLocationsByItemID: studyLocationsByItemID,
                studyLocationsByCourseID: studyLocationsByCourseID,
                courseResumePoints: persistedCourseResumePoints,
                coursePortableStateRevisions: Dictionary(
                    uniqueKeysWithValues: coursePortableStateRevisions.map {
                        ($0.key.uuidString.lowercased(), $0.value)
                    }
                ),
                coursePortableStateDigests: Dictionary(
                    uniqueKeysWithValues: coursePortableStateDigests.map {
                        ($0.key.uuidString.lowercased(), $0.value)
                    }
                ),
                dirtyPortableCourseIDs: dirtyPortableCourseIDs.sorted {
                    $0.uuidString < $1.uuidString
                },
                learningMemoryStates: learningMemoryStates,
                courseKnowledgeProfiles: sanitizedCourseKnowledgeProfiles(),
                learningMemoryScopeMigrationVersion: learningMemoryScopeMigrationVersion,
                studySessions: persistedStudySessions,
                studySessionScopeMigrationVersion: studySessionScopeMigrationVersion,
                activeStudySessionID: persistedActiveStudySessionID,
                selectionAskThreads: selectionAskThreads,
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
                persistedWorkspaceCourseIDs = Set(courses.map(\.id))
                courseResumePoints = persistedCourseResumePoints
                if !oversizedPortableCourseIDs.isEmpty {
                    workspaceSaveError = ui(
                        "工作区内容已保存，但有课程的可携带状态超过 32 MB；课程文件夹中的原状态保持不变。请精简课程 Chat 或未写入草稿后重试。",
                        "The workspace was saved, but a portable course state exceeds 32 MB. The state in the course folder was left unchanged. Reduce course chats or pending drafts, then retry."
                    )
                } else if blockedPortableCourseIDs.isEmpty {
                    if workspaceSaveError != nil {
                        workspaceSaveError = nil
                    }
                } else {
                    workspaceSaveError = ui(
                        "有课程状态存在冲突或损坏，原文件与本机缓存均已保留；魏碑不会自动覆盖。",
                        "A course state is conflicted or damaged. Both the original file and local cache were preserved, and WeiBei will not overwrite either automatically."
                    )
                }
                needsSelectionAskThreadsWorkspaceMigration = false
                loadedSelectionAskThreadsFromWorkspaceSnapshot = true
                if shouldRemoveLegacySelectionAskThreadsAfterSave {
                    selectionAskThreadDefaults.removeObject(
                        forKey: Self.legacySelectionAskThreadsDefaultsKey
                    )
                    shouldRemoveLegacySelectionAskThreadsAfterSave = false
                }
                return true
            } catch {
                do {
                    try rollbackCoursePortableStateCommit(portableCommit)
                    workspaceSaveError = ui(
                        "课程更改尚未写入磁盘：\(error.localizedDescription)",
                        "Course changes were not saved to disk: \(error.localizedDescription)"
                    )
                } catch {
                    workspaceSaveError = ui(
                        "课程状态提交失败且检测到并发变更，魏碑已停止覆盖并保留现场。",
                        "The course state commit failed during a concurrent change. WeiBei stopped overwriting and preserved the files for recovery."
                    )
                }
                return false
            }
        }
    }

    private static func environmentValue(_ name: String) -> String {
        (ProcessInfo.processInfo.environment[name] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
