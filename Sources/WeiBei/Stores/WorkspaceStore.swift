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
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
    /// 候选与本机 digest 相等，无歧义。
    case unchanged
    /// 候选更新且本机干净，可采用候选状态。
    case useNewerCandidate
    /// 候选与本机不同且本机 dirty / 不可比：保留本机进度，需用户确认一次。
    case keepsLocalState
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
    case itemBusy
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
        case .itemBusy:
            "这份文件正在进行另一项操作，请稍后重试。"
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
        }
    }
}

enum ContentSourceRemovalError: LocalizedError {
    case itemUnavailable
    case sourceChanged
    case trashMoveFailed
    case workspaceSaveFailed
    case pendingChangesUnsaved

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
        case .pendingChangesUnsaved:
            "有尚未写入磁盘的更改，为保护内容魏碑没有执行删除。请稍后重试。"
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
    var courseLibraryRootPath: String?
    var courseLibraryRootIdentity: ImportedFileIdentity?
    var courseLibraryRootBookmarkData: Data?
    var courseLibraryRootURL: URL?
    var courseLibraryUnavailableReason: String?
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
    let agentStreaming = AgentStreamingState()
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
    /// Pane visibility + focus chrome — not `@Published` on the main store.
    let paneState = WorkspacePaneState()
    var showReader: Bool {
        get { paneState.showReader }
        set {
            if paneState.showReader != newValue {
                paneState.showReader = newValue
            }
        }
    }
    var showAgent: Bool {
        get { paneState.showAgent }
        set {
            if paneState.showAgent != newValue {
                paneState.showAgent = newValue
            }
        }
    }
    var showNotes: Bool {
        get { paneState.showNotes }
        set {
            if paneState.showNotes != newValue {
                paneState.showNotes = newValue
            }
        }
    }
    var showReaderSearch: Bool {
        get { paneState.showReaderSearch }
        set {
            if paneState.showReaderSearch != newValue {
                paneState.showReaderSearch = newValue
            }
        }
    }
    var focusedPane: PaneFocus {
        get { paneState.focusedPane }
        set {
            if paneState.focusedPane != newValue {
                paneState.focusedPane = newValue
            }
        }
    }
    var focusRequest: Int {
        get { paneState.focusRequest }
        set {
            if paneState.focusRequest != newValue {
                paneState.focusRequest = newValue
            }
        }
    }
    @Published var showDailyInspiration = true
    @Published var commandPalettePresented = false
    var librarySearch = ""
    @Published private(set) var readerSourceHighlight = ""
    @Published private(set) var readerSourceHighlightPageIndex: Int?
    @Published var readerSearch = "" {
        didSet {
            guard readerSearch != oldValue else { return }
            readerSourceHighlight = ""
            readerSourceHighlightPageIndex = nil
        }
    }
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
    /// Selection / floating-agent chrome — not `@Published` on the main store.
    let interaction = WorkspaceInteractionState()
    var agentSurface: AgentSurface {
        get { interaction.agentSurface }
        set {
            if interaction.agentSurface != newValue {
                interaction.agentSurface = newValue
            }
        }
    }
    @Published var noteRenderMode: NoteRenderMode = .rich
    var floatingSelectionPrompt: String {
        get { interaction.floatingSelectionPrompt }
        set {
            if interaction.floatingSelectionPrompt != newValue {
                interaction.floatingSelectionPrompt = newValue
            }
        }
    }
    var pinnedFloatingAgent: Bool {
        get { interaction.pinnedFloatingAgent }
        set {
            if interaction.pinnedFloatingAgent != newValue {
                interaction.pinnedFloatingAgent = newValue
            }
        }
    }
    var selectionContext: SelectionContext? {
        get { interaction.selectionContext }
        set {
            if interaction.selectionContext != newValue {
                interaction.selectionContext = newValue
            }
        }
    }
    var selectionAttachments: [SelectionContext] {
        get { interaction.selectionAttachments }
        set {
            if interaction.selectionAttachments != newValue {
                interaction.selectionAttachments = newValue
            }
        }
    }
    var selectionAnchor: CGPoint? {
        get { interaction.selectionAnchor }
        set { interaction.selectionAnchor = newValue }
    }
    /// Durable selection→chat threads (underline marks + reopen floating Q&A).
    @Published var selectionAskThreads: [SelectionAskThread] = []
    /// Thread currently shown in the floating selection agent (full answer surface).
    var activeSelectionAskThreadID: UUID? {
        get { interaction.activeSelectionAskThreadID }
        set {
            if interaction.activeSelectionAskThreadID != newValue {
                interaction.activeSelectionAskThreadID = newValue
            }
        }
    }
    /// Keeps the floating agent open while a selection-based answer streams.
    var keepFloatingSelectionForAnswer: Bool {
        get { interaction.keepFloatingSelectionForAnswer }
        set {
            if interaction.keepFloatingSelectionForAnswer != newValue {
                interaction.keepFloatingSelectionForAnswer = newValue
            }
        }
    }
    @Published var noteEditorCommand: NoteEditorCommand?
    /// Success / info banner for note create/switch — separate from errors so it auto-dismisses cleanly.
    @Published var transientNoteStatus: String?
    @Published private(set) var workspaceSaveError: String?
    /// S5：真磁盘写失败计数；满 3 次才露出可点重试的轻提示。
    private var consecutiveWorkspaceSaveFailures = 0
    @Published private(set) var courseFileOperationProgress: CourseFileOperationProgress?
    @Published var notebookCreationDraft: NotebookCreationDraft?
    @Published var notebookRenameDraft: NotebookRenameDraft?
    var notebookRenameInFlight = false
    @Published var modelName: String = ""
    @Published private(set) var agentInteractiveVisualizationsEnabled = true
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

    var notesByItemID: [String: String] = [:]
    let courseSidebarTags = CourseSidebarTagState()
    var pendingNoteWritesByItemID: [String: PendingNoteWriteState] = [:]
    var noteOperationErrorsByItemID: [String: String] = [:]
    /// 磁盘观察值：reconcile / load 可刷新，用于外部改动检测。
    var noteBackingContentDigestsByItemID: [String: String] = [:]
    /// 上次魏碑自身成功写回（或静默采纳磁盘）的 digest，专供备份环判定。
    /// 不持久化：重启后首次写回无基线会多备份一份，方向安全。
    var lastSelfWrittenNoteDigestsByItemID: [String: String] = [:]
    /// P0：启动修复例程每次启动只跑一轮（幂等，重复启动无副作用）。
    var noteDivergenceRepairDidRun = false
    /// 文件名跟随抬头的基线：上次由抬头体系登记/同步的文件名（不含扩展名）。
    /// 只有基线==当前文件名时才跟随抬头改名；对不上说明文件名被外部动过，
    /// 先登记、不动文件。内存态即可：重启丢基线只少一次自动改名，方向安全。
    var headingSyncedNoteStemByItemID: [String: String] = [:]
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
    let importedFileIdentityResolver: (URL) -> ImportedFileIdentity?
    let courseRootBookmarkMaker: (URL) -> Data?
    let courseRootBookmarkResolver: (Data) -> CourseProjectResolvedBookmark?
    let courseSecurityScopeStarter: (URL) -> Bool
    let courseSecurityScopeStopper: (URL) -> Void
    private let courseProjectMutationHook: (CourseProjectMutationStage) throws -> Void
    let notebookMarkdownReader: (URL) throws -> String
    let notebookMarkdownWriter: (String, URL) throws -> Void
    let noteBackupRootURL: URL
    let notebookFileMover: (URL, URL) throws -> Void
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
    let courseDocumentSearchIndex: CourseDocumentSearchIndex
    private var activeAgentRequestID: UUID?
    private var activeAgentReplyMessageID: UUID?
    private var latestAgentStreamingText = ""
    private var lastAgentStreamingPublishNanoseconds: UInt64 = 0
    private var agentReplyIDsThatDisplayedStreamingText: Set<UUID> = []
    private var agentVisualizationIDsUpdatingHistory: Set<String> = []
    private var activeAgentReplyChatID: UUID?
    private var agentRequestTask: Task<Void, Never>?
#if DEBUG
    private var capturesAgentRequestForSelfCheck = false
    private var selfCheckCapturedAgentRequest: StudyAgentRequest?
#endif
    private var agentStopTask: Task<Void, Never>?
    private var pendingAgentSwitchTargetID: UUID?
    private var pendingAgentSwitchCourseID: UUID?
    private var agentDraftsBySessionID: [UUID: String] = [:]
    /// Session-local identity of the one reusable, newly created empty Chat.
    /// Deliberately not persisted: reopening the App starts with a fresh empty Chat.
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
    var stagedNoteDraft: (itemID: String, value: String)?
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
    var pendingNotePersistenceByItemID: [String: PendingNotePersistence] = [:]
    var pendingNotePersistenceTasks: [String: Task<Void, Never>] = [:]
    let notePersistenceDebounceDelay: UInt64 = 420_000_000
    var studyProgressSaveTask: Task<Void, Never>?
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
    var activeCourseSecurityScopes: [String: URL] = [:]
    private var activeCourseSecurityScopeOwnerTokens: [String: UUID] = [:]
    private var activeCourseRebindTokens: [UUID: UUID] = [:]
    private var activeCourseRemovalTokens: [UUID: UUID] = [:]
    private var activeCourseRemovalTransactionID: UUID?
    private var pendingCourseTrashReceiptCleanups:
        [CourseTrashReceiptCleanup] = []
    private var activeCourseFileMutationCounts: [UUID: Int] = [:]
    private var activeItemFileMutationIDs = Set<String>()
    private var workspacePersistenceRemovingCourseID: UUID?
    private var workspaceRemovalCommitObserved = false
#if DEBUG
    private var usesBackgroundWorkspacePersistenceForSelfCheck = false
#endif
    private var resolvedCourseRootURLs: [UUID: URL] = [:]
    private var courseRootUnavailableReasons: [UUID: String] = [:]
    private let courseProjectFileWorker = CourseProjectFileWorker()
    private var courseReconciliationTask: Task<Void, Never>?
    private var courseReconciliationInFlight = false
    private var lastCourseReconciliationLookupCount = 0

    var showRightPane: Bool {
        get { showNotes || showAgent }
        set {
            // Single paneState publish (notes+agent together).
            paneState.setRightPaneVisible(newValue)
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

    struct PendingNotePersistence {
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
    private static let interactiveVisualizationsDefaultsKey = "weibei.agent.interactiveVisualizationsEnabled"

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
        noteBackupRootURL: URL? = nil,
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
        startsAtBlankEntries: Bool = false,
        startsCourseFileMaintenance: Bool = true
    ) {
        workspaceDirectory = folder.standardizedFileURL
        storageURL = folder.appendingPathComponent("workspace.json")
        self.importedFileIdentityResolver = importedFileIdentityResolver
        self.courseRootBookmarkMaker = courseRootBookmarkMaker
        self.courseRootBookmarkResolver = courseRootBookmarkResolver
        self.courseSecurityScopeStarter = courseSecurityScopeStarter
        self.courseSecurityScopeStopper = courseSecurityScopeStopper
        self.courseProjectMutationHook = courseProjectMutationHook
        self.notebookMarkdownReader = notebookMarkdownReader
        self.notebookMarkdownWriter = notebookMarkdownWriter
        self.noteBackupRootURL = noteBackupRootURL ?? NoteBackupRing.defaultRootURL()
        self.notebookFileMover = notebookFileMover
        self.courseFileSourceRemover = courseFileSourceRemover
        self.contentSourceTrashMover = contentSourceTrashMover
        self.workspaceSnapshotWriter = workspaceSnapshotWriter
        self.coursePortableStateWriter = coursePortableStateWriter
        self.selectionAskThreadDefaults = selectionAskThreadDefaults
        if selectionAskThreadDefaults.object(
            forKey: Self.interactiveVisualizationsDefaultsKey
        ) != nil {
            agentInteractiveVisualizationsEnabled = selectionAskThreadDefaults.bool(
                forKey: Self.interactiveVisualizationsDefaultsKey
            )
        }
        piRuntime = PiAgentRuntime(runtimeDirectory: folder.appendingPathComponent("AgentRuntime", isDirectory: true))
        let courseIndexDirectory = folder.appendingPathComponent("CourseIndex", isDirectory: true)
        Self.removeLegacyCourseIndex(in: courseIndexDirectory)
        courseDocumentSearchIndex = CourseDocumentSearchIndex(
            databaseURL: courseIndexDirectory.appendingPathComponent("course-search-v3.sqlite3")
        )
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        rebuildCourseMembershipsFromStorage()
        loadLegacySelectionAskThreadsIfWorkspaceFieldMissing()
        let restoredCourseProjectRoots = restoreCourseProjectRoots()
        refreshRuntimeItemURLs()
        let restoredPortableCourseStates = restorePortableCourseStates()
        rebuildCourseMembershipsFromStorage()
        refreshRuntimeItemURLs()
        // S3：不再从 journal 恢复未完成操作；仅静默清理残留事务目录。
        let recoveredCourseTrash =
            silentlyCleanupOrphanCourseTransactions()
        try? FileManager.default.removeItem(
            at: folder.appendingPathComponent("pending-notebook-rename.json")
        )
        try? FileManager.default.removeItem(
            at: folder.appendingPathComponent("pending-course-removal.json")
        )
        WeiBeiThemeRuntime.mode = appearanceMode
        let resolvedImportedFileBookmarks = resolvePersistedImportedFileBookmarks()
        let migratedImportedItemIdentities = migrateLegacyImportedItemIdentities()
        if resolvedImportedFileBookmarks
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
        if noteSourceLinksMigrationVersion < 1 {
            migrateNoteSourceLinksFromMarkdown()
            noteSourceLinksMigrationVersion = 1
            _ = save()
        } else if resolvedImportedFileBookmarks
                    || migratedImportedItemIdentities
                    || migratedStudyLocationTitles
                    || sanitizedNoteSourceLinks
                    || sanitizedCourseLibrary
                    || migratedStudySessionScopes
                    || migratedLearningMemoryScopes
                    || sanitizedCourseResumePoints
                    || restoredCourseProjectRoots
                    || restoredPortableCourseStates
                    || recoveredCourseTrash
                    || initializedCourseKnowledgeProfiles
                    || needsPortableCourseStateBootstrap
                    || recoveredInterruptedAgentReply
                    || needsSelectionAskThreadsWorkspaceMigration {
            _ = save()
        }
        floatingSelectionPrompt = ui("当前选区", "Current selection")
        if selectedItemID != nil {
            restoreCurrentStudyLocation()
            recordCurrentStudyLocation(incrementVisit: false)
        }
        isRestoringCourseResumePoint = false
        // Phase 4：课程文件维护延后到首帧之后，缩短冷启动到可交互。
        if !WeiBeiSafetyTestMode.isEnabled {
            bootstrapDefaultLibraryIfNeeded()
        }
        if startsCourseFileMaintenance {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.startCourseFileMaintenance()
            }
        }
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
        importedItems.filter { item in
            switch item.storage {
            case .courseOwned(let ownerCourseID, _):
                return ownerCourseID == courseID
            case .common, .bundledSample:
                return false
            }
        }
    }

    func courseMaterials(in courseID: UUID) -> [StudyItem] {
        courseItems(in: courseID).filter { !$0.isNotebookNote }
    }

    func courseNotes(in courseID: UUID) -> [StudyItem] {
        courseItems(in: courseID).filter(\.isNotebookNote)
    }

    func courseIDs(for itemID: String) -> [UUID] {
        if let owner = importedItems.first(where: { $0.id == itemID })?.storage.ownerCourseID {
            return [owner]
        }
        let fromMemberships = courseMembershipIndex.courseIDs(for: itemID)
        return fromMemberships
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
           !importedItems.contains(where: { $0.id == itemID }) {
            result.materialLocation = nil
        }
        if let chatID = result.chatID,
           !studySessions.contains(where: { $0.id == chatID }) {
            result.chatID = nil
        }
        if let noteItemID = result.noteItemID,
           !importedItems.contains(where: { $0.id == noteItemID }) {
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
              courseIDs(for: itemID).contains(courseID)
                || importedItems.first(where: { $0.id == itemID }).map({
                    if case .common = $0.storage { return true }
                    return false
                }) == true else {
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
            let mounted = courseMembershipIndex.courseIDs(for: item.id).contains(courseID)
            let alreadyRecorded =
                studyLocationsByCourseID[courseID.uuidString]?[item.id] != nil
            guard mounted || alreadyRecorded else {
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
                reportWorkspaceSaveFailure(ui(
                    "课程已创建，但可携带状态尚未写入。",
                    "The course was created, but its portable state has not been written yet."
                ))
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
        // S6-2：资料库身份变化不再拒绝；静默改绑到新文件夹（课程记录保留）。
        // 原先 libraryIdentityMismatch 拒绝「换库」；产品改为允许迁移绑定。
        if let persistedIdentity = courseLibraryRootIdentity,
           persistedIdentity != identity {
            showTransientNoteStatus(
                ui(
                    "已将课程资料库改绑到所选文件夹，课程记录保留。",
                    "The course library was re-bound to the selected folder. Course records were kept."
                )
            )
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
            showTransientNoteStatus(ui(
                "已有 \(legacyOrganization.migrated) 份旧资料完成整理；另有 \(legacyOrganization.errors.count) 份未完成：\(legacyOrganization.errors.first ?? "")",
                "Organized \(legacyOrganization.migrated) legacy item(s); \(legacyOrganization.errors.count) remain: \(legacyOrganization.errors.first ?? "")"
            ))
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
            guard case .common = item.storage else { return false }
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
        guard let libraryRelativePath,
              isTopLevelLibraryCourseFolder(libraryRelativePath) else {
            throw CourseProjectRootError.rootOutsideLibrary
        }
        let bookmark: Data? = nil
        let resolvedExternalRoot: URL? = nil
        let externalScopeURL: URL? = nil

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
            let metadataLooksSafe =
                metadataValues?.isDirectory == true
                && metadataValues?.isSymbolicLink != true
                && metadataValues?.isAliasFile != true
                && !CourseProjectFileWorker.isSymbolicLink(at: metadataURL)
                && CourseProjectPathPolicy.isSame(
                    metadataURL,
                    metadataURL.resolvingSymlinksInPath()
                )
                && importedFileIdentityResolver(canonicalRoot) == identity
            if metadataLooksSafe {
                do {
                    let snapshot = try await courseProjectFileWorker
                        .adoptionSnapshot(
                            at: canonicalRoot,
                            expectedRootIdentity: identity
                        )
                    adoptionSnapshot = snapshot
                    courseID = snapshot.manifest.courseID
                } catch {
                    // 布局安全但状态不可读（如超大）：保留磁盘原样并拒绝，避免改写共享课程根。
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    throw CourseProjectRootError.metadataConflict
                }
            } else {
                // S6-1：结构异常的 .weibei（symlink/非目录）→ 改名备份后按新课继续。
                let backup = metadataURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        ".weibei.backup-\(Int(Date().timeIntervalSince1970))",
                        isDirectory: true
                    )
                try? FileManager.default.moveItem(at: metadataURL, to: backup)
                adoptionSnapshot = nil
                courseID = UUID()
                showTransientNoteStatus(
                    ui(
                        "原课程元数据已备份为 \(backup.lastPathComponent)，将按新课程纳入。",
                        "Previous course metadata was backed up as \(backup.lastPathComponent); adopting as a new course."
                    )
                )
                try validateCourseProjectRoot(
                    canonicalRoot,
                    identity: identity,
                    mustBeInsideLibrary: false
                )
                // 落入下方 else 同款创建逻辑：用 staged 写新 manifest。
                let stagedMetadataURL = canonicalRoot.appendingPathComponent(
                    ".weibei-adopt-staging-\(courseID.uuidString.lowercased())",
                    isDirectory: true
                )
                do {
                    try FileManager.default.createDirectory(
                        at: stagedMetadataURL,
                        withIntermediateDirectories: false
                    )
                    guard let emptyFingerprint = transactionDirectoryFingerprint(
                        at: stagedMetadataURL
                    ) else {
                        throw CourseProjectRootError.rootIdentityUnavailable
                    }
                    createdMetadataFingerprint = emptyFingerprint
                    try CourseProjectManifest(courseID: courseID)
                        .encoded()
                        .write(
                            to: stagedMetadataURL.appendingPathComponent(
                                "course.json"
                            ),
                            options: [.atomic]
                        )
                    guard let completeFingerprint =
                            transactionDirectoryFingerprint(at: stagedMetadataURL)
                    else {
                        throw CourseProjectRootError.rootIdentityUnavailable
                    }
                    createdMetadataFingerprint = completeFingerprint
                    try FileManager.default.moveItem(
                        at: stagedMetadataURL,
                        to: metadataURL
                    )
                    createdMetadata = true
                } catch {
                    if let createdMetadataFingerprint {
                        safelyRemoveTransactionDirectory(
                            at: stagedMetadataURL,
                            expected: createdMetadataFingerprint
                        )
                    }
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    throw error
                }
            }
            if let existing = courses.first(where: { $0.id == courseID }),
               adoptionSnapshot != nil {
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
            if adoptionSnapshot != nil {
                try validateCourseProjectRoot(
                    canonicalRoot,
                    identity: identity,
                    mustBeInsideLibrary: false
                )
            }
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
            sourceRootPath: nil,
            sourceRootRelativePath: libraryRelativePath,
            sourceRootIdentity: identity,
            sourceRootBookmarkData: nil
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
            replaceNoteDrafts(previousNotesByItemID)
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
                                  let ownerCourseID,
                                  _
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
            reportWorkspaceSaveFailure(ui(
                "课程已登记，但可携带状态尚未写入。",
                "The course was registered, but its portable state has not been written yet."
            ))
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
        refreshedCourse.sourceRootPath = nil
        refreshedCourse.sourceRootRelativePath = libraryRelativePath
        refreshedCourse.sourceRootIdentity = identity
        refreshedCourse.sourceRootBookmarkData = nil
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
        // S6-4：仅移除进行中阻塞导出/重绑；Agent/笔记待写不再拒绝用户操作。
        activeCourseRemovalTokens[courseID] != nil
    }

    private func itemIsInRemovingCourse(_ itemID: String) -> Bool {
        if importedItems.first(where: { $0.id == itemID }).map({
            if case .courseOwned(let courseID, _) = $0.storage {
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
        // 真正 digest 相等：无歧义，S6-5 可自动确认。
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
        // H2：分叉 / 本机 dirty / revision 不可比 → keepsLocalState（需确认一次）；
        // 仅当本机干净且候选 revision 更新时才 useNewerCandidate。
        guard localIsClean,
              let knownRevision,
              state.revision > knownRevision else {
            return (
                state,
                statePayloadDigest,
                localPayloadDigest,
                .keepsLocalState
            )
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
                .common(existingPath)
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
                // S3：无法物化的共享项静默跳过。
                continue
            }
            guard case let .sharedReference(
                sharedRelativePath,
                expectedContentDigest
            ) = state.items[index].storage,
            sharedRelativePath == provenance.sharedRelativePath,
            expectedContentDigest == provenance.sourceContentDigest,
            state.items[index].contentDigest
                == provenance.sourceContentDigest else {
                continue
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

        return false
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
            mustBeInsideLibrary: true,
            excludingCourseID: proposal.courseID
        )

        let libraryRelativePath = courseLibraryRootURL.flatMap {
            CourseProjectPathPolicy.relativePath(
                of: canonicalRoot,
                inside: $0
            )
        }
        guard let libraryRelativePath,
              isTopLevelLibraryCourseFolder(libraryRelativePath) else {
            throw CourseProjectRootError.rootOutsideLibrary
        }
        let refreshedBookmark: Data? = nil
        let resolvedRoot = canonicalRoot
        let newScopeURL: URL? = nil

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
            let previousLastSelfWrittenDigests =
                lastSelfWrittenNoteDigestsByItemID
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
            reboundCourse.sourceRootPath = nil
            reboundCourse.sourceRootRelativePath = libraryRelativePath
            reboundCourse.sourceRootIdentity =
                proposal.candidateRootIdentity
            reboundCourse.sourceRootBookmarkData = nil
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
                switch evaluation.impact {
                case .keepsLocalState:
                    // H2：以本机进度为准，不覆盖；候选 portable 状态 best-effort 冲突备份。
                    if let candidateData = proposal.snapshot.portableStateData {
                        let weibei = resolvedRoot.appendingPathComponent(
                            ".weibei",
                            isDirectory: true
                        )
                        try? FileManager.default.createDirectory(
                            at: weibei,
                            withIntermediateDirectories: true
                        )
                        let stamp = ISO8601DateFormatter().string(from: Date())
                            .replacingOccurrences(of: ":", with: "-")
                        let backupURL = weibei.appendingPathComponent(
                            "rebind-candidate-conflict-\(stamp).json",
                            isDirectory: false
                        )
                        try? candidateData.write(
                            to: backupURL,
                            options: [.atomic]
                        )
                    }
                    dirtyPortableCourseIDs.insert(proposal.courseID)
                    needsPortableCourseStateBootstrap = true
                case .unchanged, .useNewerCandidate:
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
                }
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
                replaceNoteDrafts(previousNotesByItemID)
                pendingNoteWritesByItemID =
                    previousPendingNoteWrites
                loadedCourseNoteTextByItemID =
                    previousLoadedCourseNoteText
                noteText = previousNoteText
                noteBackingContentDigestsByItemID =
                    previousNoteBackingDigests
                lastSelfWrittenNoteDigestsByItemID =
                    previousLastSelfWrittenDigests
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
                  case let .common(itemSharedRelativePath) = item.storage,
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
            let sourceInfo: CourseFileSourceInfo
            do {
                sourceInfo = try await courseProjectFileWorker
                    .validatedRegularSource(sharedURL)
            } catch {
                // 源文件真没了：跳过该项，不中止整次导出。
                continue
            }
            // S3：身份漂移可容忍则静默继续。
            let identityOK = item.importedFileIdentity.map {
                $0.matchesAcrossVolumeDrift(sourceInfo.identity)
            } ?? true
            if !identityOK {
                continue
            }
            let sourceSnapshot: CourseFileSnapshot
            do {
                sourceSnapshot = try await courseProjectFileWorker
                    .stableSnapshot(
                        at: sourceInfo.url,
                        expectedIdentity: sourceInfo.identity
                    )
            } catch {
                continue
            }
            // digest 不一致时仍以磁盘现状导出（S3 静默降级；S6-9 可再收紧日志）。
            _ = expectedContentDigest
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
              item.storage == .common(relativePath: ""),
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
              case .courseOwned(let ownerCourseID, _) = item.storage,
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
        if case .common = importedItems[itemIndex].storage {
            try await linkSharedItem(
                itemID: itemID,
                toCourseID: addedCourseID,
                conflictResolution: conflictResolution
            )
            return
        }
        guard case .courseOwned(let ownerCourseID, _) = importedItems[itemIndex].storage,
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
        let affectedItemIDs: Set<String> = [itemID]
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: affectedItemIDs
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: affectedItemIDs
            )
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
        var sharedIdentity: ImportedFileIdentity?
        var ownerLinkIdentity: ImportedFileIdentity?
        var addedLinkIdentity: ImportedFileIdentity?
        var workspaceCommitted = false
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
            // S3：无 journal。复制到共享位 → 隔离源 → 放链接 → 保存。
            let stagedIdentity = try await courseProjectFileWorker.copyAndVerify(
                from: sourceURL,
                generatedData: nil,
                to: payloadURL,
                expectedSnapshot: sourceSnapshot
            )
            sharedIdentity = stagedIdentity
            try courseProjectMutationHook(
                .afterSharedSameVolumeStagingJournal
            )
            let placedSharedIdentity = try await courseProjectFileWorker.placeWithoutReplacement(
                from: payloadURL,
                to: sharedTarget,
                courseRoot: libraryRoot,
                destinationDirectory: sharedDirectory,
                expectedDestinationIdentity: sharedDirectoryIdentity,
                expectedSnapshot: sourceSnapshot
            )
            try courseProjectMutationHook(.afterSharedFilePlacementBeforeJournal)
            guard stagedIdentity == placedSharedIdentity,
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
            sharedIdentity = placedSharedIdentity
            let preparedOwner = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedOwnerLinkURL,
                destinationURL: sharedTarget
            )
            try courseProjectMutationHook(
                .afterSharedOwnerLinkPrepareBeforeJournalIdentity
            )
            ownerLinkIdentity = preparedOwner
            let preparedAdded = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedAddedLinkURL,
                destinationURL: sharedTarget
            )
            try courseProjectMutationHook(
                .afterSharedAddedLinkPrepareBeforeJournalIdentity
            )
            addedLinkIdentity = preparedAdded
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedOwnerLinkURL,
                to: sourceURL,
                destinationURL: sharedTarget,
                allowedRoot: ownerRoot,
                expectedIdentity: preparedOwner
            )
            try courseProjectMutationHook(.afterSharedOwnerLinkPlacementBeforeJournal)
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedAddedLinkURL,
                to: addedLinkURL,
                destinationURL: sharedTarget,
                allowedRoot: addedRoot,
                expectedIdentity: preparedAdded
            )
            try courseProjectMutationHook(.afterSharedAddedLinkPlacementBeforeJournal)

            let sharedInfo = try await revalidatedSharedArtifacts(
                sharedIdentity: placedSharedIdentity,
                ownerLinkIdentity: preparedOwner,
                addedLinkIdentity: preparedAdded
            )
            importedItems[itemIndex].urlPath = sharedTarget.path
            importedItems[itemIndex].importedFileIdentity = placedSharedIdentity
            importedItems[itemIndex].storage = .common(
                relativePath: sharedRelativePath
            )
            importedItems[itemIndex].fileByteCount = sharedInfo.byteCount
            importedItems[itemIndex].fileModificationTimeNanoseconds =
                sharedInfo.modificationTimeNanoseconds
            courseItemMemberships[ownerMembershipIndex].entryIdentity = preparedOwner
            courseItemMemberships[ownerMembershipIndex].documentIdentifier = nil
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: addedCourseID,
                    itemID: itemID,
                    courseRelativePath: addedRelativePath,
                    entryIdentity: preparedAdded,
                    documentIdentifier: nil
                )
            )
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            workspaceCommitted = true
            try courseProjectMutationHook(
                .afterSharedWorkspaceSaveBeforeSourceCleanup
            )
            if (try? await revalidatedSharedArtifacts(
                sharedIdentity: placedSharedIdentity,
                ownerLinkIdentity: preparedOwner,
                addedLinkIdentity: preparedAdded
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
            if workspaceCommitted {
                // 登记已提交：绝不回滚共享原件与成员关系（S3 无 journal 补完）。
                // 尽力清事务目录；源隔离残留留给用户/下次操作。
                await safelyRemoveSharedTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
                throw error
            }
            // 提交前失败：回滚内存与半完成共享产物。
            importedItems = previousItems
            courseItemMemberships = previousMemberships
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: addedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "added-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: addedLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: sourceURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "owner-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: ownerLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedAddedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-added-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: addedLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedOwnerLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-owner-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: ownerLinkIdentity
            )
            if !FileManager.default.fileExists(atPath: sourceURL.path) {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: sourceQuarantineURL,
                    to: sourceURL
                )
            }
            if let sharedIdentity {
                _ = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                    at: sharedTarget,
                    quarantineURL: sharedDirectory.appendingPathComponent(
                        ".\(sharedTarget.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                    ),
                    expectedIdentity: sharedIdentity,
                    expectedSnapshot: sourceSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
                _ = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                    at: payloadURL,
                    quarantineURL: sharedDirectory.appendingPathComponent(
                        ".\(payloadURL.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                    ),
                    expectedIdentity: sharedIdentity,
                    expectedSnapshot: sourceSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            throw error
        }
    }

    private func linkSharedItem(
        itemID: String,
        toCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution
    ) async throws {
        let affectedCourseIDs: Set<UUID> = [courseID]
        let affectedItemIDs: Set<String> = [itemID]
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: affectedItemIDs
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: affectedItemIDs
            )
        }
        guard conflictResolution != .replace else {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        guard let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }),
              case .common(let sharedRelativePath) = importedItems[itemIndex].storage,
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
                && $0.courseRelativePath != nil
        }) {
            return
        }
        // 纯归属兜底登记（无 courseRelativePath）不幂等返回：继续走链接流程，
        // 成功后原地补全链接条目。
        let sharedInfo = try await courseProjectFileWorker.validatedRegularSource(
            expectedSharedURL
        )
        let sharedSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sharedInfo.url,
            expectedIdentity: sharedInfo.identity
        )
        if importedItems[itemIndex].contentDigest == nil {
            // 新建的共享笔记还没有内容摘要；可携带状态校验要求 sharedReference
            // 带 SHA256 摘要，缺失会让写回校验失败并回滚整个链接登记。
            importedItems[itemIndex].contentDigest = sharedSnapshot.sha256
        }
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
        let preparedLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-link"
        )
        var linkIdentity: ImportedFileIdentity?
        let previousMemberships = courseItemMemberships
        do {
            // S3：无 journal。
            let preparedIdentity = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedLinkURL,
                destinationURL: expectedSharedURL
            )
            linkIdentity = preparedIdentity
            try courseProjectMutationHook(
                .afterSharedLinkPrepareBeforeJournalIdentity
            )
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedLinkURL,
                to: linkURL,
                destinationURL: expectedSharedURL,
                allowedRoot: courseRoot,
                expectedIdentity: preparedIdentity
            )
            try courseProjectMutationHook(.afterSharedLinkPlacementBeforeJournal)
            if let fallbackIndex = courseItemMemberships.firstIndex(where: {
                $0.courseID == courseID && $0.itemID == itemID
                    && $0.courseRelativePath == nil
            }) {
                courseItemMemberships[fallbackIndex].courseRelativePath =
                    linkRelativePath
                courseItemMemberships[fallbackIndex].entryIdentity =
                    preparedIdentity
            } else {
                courseItemMemberships.append(
                    CourseItemMembership(
                        courseID: courseID,
                        itemID: itemID,
                        courseRelativePath: linkRelativePath,
                        entryIdentity: preparedIdentity
                    )
                )
            }
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            invalidateAgentContext()
        } catch {
            // S3：无 journal 恢复；崩溃注入也必须走回滚。
            courseItemMemberships = previousMemberships
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: linkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "link-cleanup"
                ),
                destinationURL: expectedSharedURL,
                expectedIdentity: linkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-link-cleanup"
                ),
                destinationURL: expectedSharedURL,
                expectedIdentity: linkIdentity
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
            self.lastCourseNoteReadRanOnMainThread = read.ranOnMainThread
            // S2：写回改为同步原子写（主线程可接受）；读路径仍走后台 worker。
            self.persistCourseOwnedNote(markdown, itemID: itemID)
            self.lastCourseNoteWriteRanOnMainThread = true
            return (!read.ranOnMainThread, true)
        }
    }

    func writeCourseMarkdownForSelfCheck(
        itemID: String,
        markdown: String
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let item = importedItems.first(where: {
            $0.id == itemID
        }),
        item.isNotebookNote,
        case .courseOwned = item.storage else {
            throw CourseOwnedFileError.verificationFailed
        }
        persistCourseOwnedNote(markdown, itemID: itemID)
        if notesByItemID[itemID] != nil {
            // 写回失败留下草稿时，测试侧可观察；成功则 notes 已清除。
            throw CourseOwnedFileError.verificationFailed
        }
    }

    /// 写回失败路径：强制留下 notes 草稿（清 pending），供 C2 验收。
    func leaveCourseNoteDraftAfterFailedWriteForSelfCheck(
        itemID: String,
        markdown: String
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard importedItems.contains(where: {
            $0.id == itemID && $0.isNotebookNote
        }) else {
            throw CourseOwnedFileError.verificationFailed
        }
        setNoteDraft(markdown, for: itemID)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
        for membership in courseItemMemberships where membership.itemID == itemID {
            dirtyPortableCourseIDs.insert(membership.courseID)
        }
        save()
    }

    func lastSelfWrittenNoteDigestForSelfCheck(itemID: String) -> String? {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return lastSelfWrittenNoteDigestsByItemID[itemID]
    }

    func seedLastSelfWrittenNoteDigestForSelfCheck(
        itemID: String,
        digest: String?
    ) {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        if let digest {
            lastSelfWrittenNoteDigestsByItemID[itemID] = digest
        } else {
            lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: itemID)
        }
    }

    func portableNoteDraftsForSelfCheck(
        courseID: UUID
    ) throws -> [CoursePortableNoteDraft] {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let state = try makeCoursePortableState(
            courseID: courseID,
            revision: coursePortableStateRevisions[courseID] ?? 0,
            savedAt: Date()
        )
        return state.pendingNoteDrafts
    }

    func forcePersistPortableCourseStatesForSelfCheck(
        courseIDs: Set<UUID>
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        for courseID in courseIDs {
            dirtyPortableCourseIDs.insert(courseID)
        }
        _ = try persistCoursePortableStates(
            courseIDs: courseIDs,
            requiring: courseIDs
        )
        _ = save()
    }

    /// 从磁盘再读 course-state 并 apply（验 C2：本地草稿不被清空）。
    func reapplyPortableCourseStateWithoutLocalDraftWipeForSelfCheck(
        courseID: UUID
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard let stateURL = coursePortableStateURL(for: courseID),
              let data = try? Data(contentsOf: stateURL) else {
            throw CourseOwnedFileError.verificationFailed
        }
        let state = try JSONDecoder()
            .decode(CoursePortableState.self, from: data)
            .validated(expectedCourseID: courseID)
        try applyCoursePortableState(state, courseID: courseID)
    }

    func pendingCourseMarkdownDraftForSelfCheck(
        itemID: String
    ) -> String? {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
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

    func waitForCourseNoteLoadsForSelfCheck() throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let deadline = Date(timeIntervalSinceNow: 20)
        while !courseNoteLoadTasksByItemID.isEmpty, Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        guard courseNoteLoadTasksByItemID.isEmpty else {
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
        conflictResolution: CourseFileConflictResolution = .cancel,
        usesBackgroundWorkspacePersistence: Bool = false,
        requiringUnchangedCourseID: UUID? = nil
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
#if DEBUG
        let previousPersistenceMode =
            usesBackgroundWorkspacePersistenceForSelfCheck
        usesBackgroundWorkspacePersistenceForSelfCheck =
            usesBackgroundWorkspacePersistence
        defer {
            usesBackgroundWorkspacePersistenceForSelfCheck =
                previousPersistenceMode
        }
#endif
        let additionalRequiredCourseIDs = requiringUnchangedCourseID.map { Set([$0]) } ?? []
        try waitForCourseFileOperation {
            if !additionalRequiredCourseIDs.isEmpty {
                try self.beginCourseFileMutation(courseIDs: additionalRequiredCourseIDs)
            }
            defer { self.finishCourseFileMutation(courseIDs: additionalRequiredCourseIDs) }
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
        let affectedItemIDs = preservingItemID.map {
            Set([$0])
        } ?? []
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: affectedItemIDs
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: affectedItemIDs
            )
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
        // S3：本地跟踪字段代替 journal 阶段机。
        var stagedIdentity: ImportedFileIdentity?
        var placedTargetIdentity: ImportedFileIdentity?
        var replacedTargetIdentity: ImportedFileIdentity?
        var replacedTargetSnapshot: CourseFileSnapshot?
        var replacedRollbackIdentity: ImportedFileIdentity?
        var replacedTrashPath: String?
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNotes = notesByItemID
        let previousPendingNoteWrites = pendingNoteWritesByItemID
        let previousBackingDigests = noteBackingContentDigestsByItemID
        let previousLastSelfWrittenDigests = lastSelfWrittenNoteDigestsByItemID
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
            try courseProjectMutationHook(.beforeCourseFileStagingCopy)
            stagedIdentity = try await courseProjectFileWorker.copyAndVerify(
                from: sourceURL,
                generatedData: generatedData,
                to: payloadURL,
                expectedSnapshot: sourceSnapshot
            )
            try courseProjectMutationHook(.afterCourseFileStagingCopy)

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
                // 覆盖前：笔记入备份环；目标隔离进废纸篓。
                if role == .note {
                    _ = try? NoteBackupRing.capture(
                        sourceURL: targetURL,
                        itemID: itemID,
                        rootURL: noteBackupRootURL
                    )
                }
                guard let replacementIdentity = importedFileIdentityResolver(targetURL) else {
                    throw CourseOwnedFileError.targetConflict(targetURL)
                }
                let replacementSnapshot = try await courseProjectFileWorker.stableSnapshot(
                    at: targetURL,
                    expectedIdentity: replacementIdentity
                )
                replacedTargetIdentity = replacementIdentity
                replacedTargetSnapshot = replacementSnapshot
                let rollbackIdentity = try await courseProjectFileWorker.reserveRollbackFile(
                    at: replacementRollbackURL
                )
                try courseProjectMutationHook(
                    .afterCourseFileRollbackArtifactCreationBeforeJournalIdentity
                )
                replacedRollbackIdentity = rollbackIdentity
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
                try await courseProjectFileWorker.fillReservedRollbackFile(
                    from: replacementQuarantineURL,
                    to: replacementRollbackURL,
                    expectedDestinationIdentity: rollbackIdentity,
                    expectedSnapshot: replacementSnapshot
                )
                try courseProjectMutationHook(
                    .afterCourseFileReplacementRollbackCopyBeforeJournal
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
                replacedTrashPath = trashURL.path
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
                isSample: false,
                isNotebookNote: role == .note,
                storage: .courseOwned(
                    ownerCourseID: courseID,
                    relativePath: targetRelativePath
                ),
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

            var sourceCleanupPending = false
            if let rollbackIdentity = replacedRollbackIdentity,
               let replacedSnapshot = replacedTargetSnapshot {
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
                }
            }
            if let replacedTrashPath {
                do {
                    try await courseProjectFileWorker.finishSelfCheckTrash(
                        at: URL(fileURLWithPath: replacedTrashPath)
                    )
                } catch {
                    sourceCleanupPending = true
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
            // S3：无 journal 恢复；崩溃注入也必须走回滚，用户重试即可。
            if !workspaceCommitted {
                importedItems = previousImportedItems
                courseItemMemberships = previousMemberships
                replaceNoteDrafts(previousNotes)
                pendingNoteWritesByItemID = previousPendingNoteWrites
                noteBackingContentDigestsByItemID = previousBackingDigests
                lastSelfWrittenNoteDigestsByItemID =
                    previousLastSelfWrittenDigests
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
                // 尽力回滚磁盘：仅当源仍可验证时删除已落位目标，避免误删唯一副本。
                let expectedTargetIdentity =
                    placedTargetIdentity ?? stagedIdentity
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
                // 只有源仍在时才可丢弃已落位副本；生成笔记/源已失则保留磁盘文件。
                let canDiscardPlacedTarget = sourceStillVerified
                if canDiscardPlacedTarget,
                   let expectedTargetIdentity,
                   FileManager.default.fileExists(atPath: targetURL.path) {
                    let targetQuarantineURL = transactionDirectory
                        .appendingPathComponent("target-quarantine", isDirectory: false)
                    _ = await courseProjectFileWorker.isolateAndRemoveVerifiedFile(
                        at: targetURL,
                        quarantineURL: targetQuarantineURL,
                        expectedIdentity: expectedTargetIdentity,
                        expectedSnapshot: sourceSnapshot,
                        remover: { try FileManager.default.removeItem(at: $0) }
                    )
                }
                if let replacedIdentity = replacedTargetIdentity,
                   let replacedSnapshot = replacedTargetSnapshot {
                    let restoreURL: URL? = {
                        if FileManager.default.fileExists(atPath: replacementQuarantineURL.path) {
                            return replacementQuarantineURL
                        }
                        if FileManager.default.fileExists(atPath: replacementRollbackURL.path) {
                            return replacementRollbackURL
                        }
                        if let replacedTrashPath {
                            let trash = URL(fileURLWithPath: replacedTrashPath)
                            if FileManager.default.fileExists(atPath: trash.path) {
                                return trash
                            }
                        }
                        return nil
                    }()
                    if canDiscardPlacedTarget,
                       let restoreURL,
                       !FileManager.default.fileExists(atPath: targetURL.path) {
                        _ = await courseProjectFileWorker.restoreIsolatedFile(
                            from: restoreURL,
                            to: targetURL
                        )
                    }
                    _ = replacedIdentity
                    _ = replacedSnapshot
                }
                // 事务目录尽力清理；源已失且目标保留时也清 staging 残留。
                await safelyRemoveCourseFileTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
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
            if case .common = importedItems[index].storage {
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

    /// S3：不再从 journal 恢复未完成操作。启动时静默清理 `.weibei/transactions/*` 残留
    /// 与旧版 pending journal 文件。
    /// H1：含 `replaced-target` / `replacement-rollback` 等用户内容崩溃备份的目录绝不误删；
    /// 其余仅当条目全部属于已知 staging/废件白名单时才清。
    @discardableResult
    private func silentlyCleanupOrphanCourseTransactions() -> Bool {
        let fileManager = FileManager.default
        // 运行时各 safelyRemove* 白名单并集 + 无 journal 时代的 staging 名。
        let safeOrphanNames: Set<String> = [
            "journal.json",
            "payload",
            "course-note.json",
            "shared.json",
            "shared-link.json",
            "shared-link-removal.json",
            "prepared-link",
            "prepared-owner-link",
            "prepared-added-link",
            "prepared-link-cleanup",
            "isolated-link",
            "isolated-link-cleanup",
            "link-cleanup",
            "target-quarantine",
        ]
        let protectedCrashBackupNames: Set<String> = [
            "replaced-target",
            "replacement-rollback",
            "trashed-replaced-target",
        ]
        for course in courses {
            guard let root = courseRootURL(for: course.id),
                  let canonical = try? CourseProjectPathPolicy.existingDirectory(root) else {
                continue
            }
            let transactions = canonical
                .appendingPathComponent(".weibei/transactions", isDirectory: true)
            guard fileManager.fileExists(atPath: transactions.path),
                  let children = try? fileManager.contentsOfDirectory(
                    at: transactions,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                  ) else {
                continue
            }
            for child in children {
                // 仅清理事务目录本身；不触碰课程资料目标文件。
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else {
                    // 非目录残留：无身份含义，可静默清。
                    try? fileManager.removeItem(at: child)
                    continue
                }
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: child,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                ) else {
                    continue
                }
                let names = Set(entries.map(\.lastPathComponent))
                if !names.isDisjoint(with: protectedCrashBackupNames) {
                    // best-effort 还原；任一步失败则保留整目录（数据不销毁）。
                    _ = tryRestoreReplacedTargetFromOrphanTransaction(
                        child,
                        courseRoot: canonical
                    )
                    continue
                }
                // 白名单：全部条目均为已知 staging/废件才删；未知名保留。
                guard names.isSubset(of: safeOrphanNames) else {
                    continue
                }
                try? fileManager.removeItem(at: child)
            }
            if let remaining = try? fileManager.contentsOfDirectory(
                at: transactions,
                includingPropertiesForKeys: nil
            ), remaining.isEmpty {
                try? fileManager.removeItem(at: transactions)
            }
        }
        // 硬崩溃后可能残留 `.weibei-course-removal-*` 隔离目录：按身份还原到登记路径。
        let recoveredCourseTrash =
            restoreOrphanCourseRootTrashIsolations()
        // 旧版 workspace 级 journal 路径（已在 init 删除一份；此处再保险）。
        try? fileManager.removeItem(
            at: workspaceDirectory.appendingPathComponent("pending-notebook-rename.json")
        )
        try? fileManager.removeItem(
            at: workspaceDirectory.appendingPathComponent("pending-course-removal.json")
        )
        return recoveredCourseTrash
    }

    /// 旧版 course-file journal 子集：仅启动还原需要的字段（解码容忍缺字段）。
    private struct OrphanCourseFileTransactionJournal: Codable {
        var targetRelativePath: String?
        var replacedTargetIdentity: ImportedFileIdentity?
        var replacedTargetSnapshot: CourseFileSnapshot?
    }

    /// 含 `replaced-target` 的孤儿事务：target 空缺且副本可核验时还原；否则保留目录。
    @discardableResult
    private func tryRestoreReplacedTargetFromOrphanTransaction(
        _ transactionDirectory: URL,
        courseRoot: URL
    ) -> Bool {
        let fileManager = FileManager.default
        let journalURL = transactionDirectory
            .appendingPathComponent("journal.json", isDirectory: false)
        let replacedURL = transactionDirectory
            .appendingPathComponent("replaced-target", isDirectory: false)
        guard fileManager.fileExists(atPath: replacedURL.path),
              let journalData = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(
                OrphanCourseFileTransactionJournal.self,
                from: journalData
              ),
              let relativePath = journal.targetRelativePath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !relativePath.isEmpty,
              let targetURL = Self.backgroundRawRelativeURL(
                relativePath,
                inside: courseRoot
              ) else {
            return false
        }
        // target 仍在 → 不覆盖，保留事务目录。
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            return false
        }
        if let expectedIdentity = journal.replacedTargetIdentity,
           importedFileIdentityResolver(replacedURL) != expectedIdentity {
            return false
        }
        if let expectedSnapshot = journal.replacedTargetSnapshot {
            let data = (try? Data(contentsOf: replacedURL)) ?? Data()
            let digest = Self.noteContentDigest(data)
            let byteCount = UInt64(data.count)
            guard digest == expectedSnapshot.sha256,
                  byteCount == expectedSnapshot.byteCount else {
                return false
            }
        }
        // 同步路径：启动清理不 await actor。
        guard CourseProjectFileWorker.renameWithoutReplacement(
            from: replacedURL,
            to: targetURL
        ) else {
            return false
        }
        // 还原成功后，若剩余仅白名单废件则可清；否则保留。
        if let remaining = try? fileManager.contentsOfDirectory(
            at: transactionDirectory,
            includingPropertiesForKeys: nil
        ) {
            let safeNames: Set<String> = ["journal.json", "payload"]
            if remaining.allSatisfy({ safeNames.contains($0.lastPathComponent) }) {
                try? fileManager.removeItem(at: transactionDirectory)
            }
        }
        return true
    }

    private func cleanupPersistedCourseTrashReceipts() {
        pendingCourseTrashReceiptCleanups.removeAll { cleanup in
            guard !persistedWorkspaceCourseIDs.contains(
                cleanup.courseID
            ) else {
                return false
            }
            return CourseProjectFileWorker.cleanupCourseTrashReceipt(
                cleanup,
                identityResolver: importedFileIdentityResolver
            )
        }
    }

    @discardableResult
    private func restoreOrphanCourseRootTrashIsolations() -> Bool {
        var recoveredReceipts: [CourseTrashReceiptCleanup] = []
        var recoveredCourseIDs = Set<UUID>()
        for course in courses {
            if let recovery = CourseProjectFileWorker
                .recoverCourseTrashReceipt(
                    for: course,
                    resolvedRootURL: courseRootURL(for: course.id),
                    courseLibraryRootURL: courseLibraryRootURL,
                    identityResolver: importedFileIdentityResolver
                ), recoveredCourseIDs.insert(recovery.courseID).inserted {
                recoveredReceipts.append(recovery)
            }
        }
        for recovery in recoveredReceipts {
            removeCourseLocalRegistration(recovery.courseID)
            pendingCourseTrashReceiptCleanups.append(recovery)
        }
        return !recoveredReceipts.isEmpty
    }

    /// S2：旧四阶段 course-note 事务不再恢复写路径；静默清理残留事务目录。
    /// 若目标文件缺失且 original 仍在，尽力还原 original，避免用户丢文件。
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

    func validateLibraryRoot(_ root: URL) throws {
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
        nil
    }

    private var persistableCourses: [Course] {
        courses.map { course in
            var next = course
            next.sourceRootPath = nil
            next.sourceRootBookmarkData = nil
            return next
        }
    }

    private func isTopLevelLibraryCourseFolder(_ relativePath: String) -> Bool {
        let reserved = [
            CourseLibraryLayout.commonMaterialsDirectoryName,
            CourseLibraryLayout.commonNotesDirectoryName,
        ]
        return !relativePath.isEmpty
            && !relativePath.contains("/")
            && !relativePath.contains("..")
            && !reserved.contains(relativePath)
    }

    @discardableResult
    private func restoreCourseProjectRoots() -> Bool {
        var changed = false
        courseLibraryRootURL = nil
        courseLibraryUnavailableReason = nil
        resolvedCourseRootURLs.removeAll()
        courseRootUnavailableReasons.removeAll()

        if bindLibraryRootFromBookmark() {
            changed = true
        } else if bindLibraryRootOnThisComputer() {
            changed = true
        } else if courseLibraryRootPath != nil
                    || courseLibraryRootIdentity != nil
                    || courseLibraryRootBookmarkData != nil {
            courseLibraryUnavailableReason = courseLibraryUnavailableReason
                ?? CourseProjectRootError.bookmarkResolutionFailed.localizedDescription
        }

        changed = restoreCourseReferencesInsideLibrary() || changed
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
            guard let relativePath = courses[index].sourceRootRelativePath else {
                continue
            }
            let resolvedURL = resolveRegisteredCourseFolder(
                relativePath: relativePath,
                expectedIdentity: courses[index].sourceRootIdentity,
                courseID: courses[index].id,
                inside: libraryRoot
            )
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
            if let liveIdentity = importedFileIdentityResolver(resolvedURL),
               courses[index].sourceRootIdentity != liveIdentity {
                courses[index].sourceRootIdentity = liveIdentity
                changed = true
            }
            if courses[index].sourceRootRelativePath != nextRelativePath {
                courses[index].sourceRootRelativePath = nextRelativePath
                courses[index].updatedAt = Date()
                changed = true
            }
        }
        return changed
    }

    func discoverTopLevelCourseFolders() {
        guard let libraryRoot = courseLibraryRootURL else { return }
        switch CourseProjectFileWorker.entryPresence(at: libraryRoot) {
        case .absent, .inaccessible:
            return
        case .present:
            break
        }
        let reserved: Set<String> = [
            CourseLibraryLayout.commonMaterialsDirectoryName,
            CourseLibraryLayout.commonNotesDirectoryName,
        ]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: libraryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let name = child.lastPathComponent
            guard !reserved.contains(name) else { continue }
            if courses.contains(where: {
                $0.sourceRootRelativePath == name || courseRootURL(for: $0.id) == child
            }) {
                ensureCourseScaffold(at: child)
                continue
            }
            let manifestURL = child
                .appendingPathComponent(".weibei", isDirectory: true)
                .appendingPathComponent("course.json")
            let existingID: UUID?
            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder().decode(CourseProjectManifest.self, from: data) {
                existingID = manifest.courseID
            } else {
                existingID = nil
            }
            if let existingID, let index = courses.firstIndex(where: { $0.id == existingID }) {
                courses[index].title = name
                courses[index].sourceRootRelativePath = name
                resolvedCourseRootURLs[existingID] = child
                ensureCourseScaffold(at: child)
                continue
            }
            let courseID = existingID ?? UUID()
            ensureCourseScaffold(at: child)
            let writtenManifest = child
                .appendingPathComponent(".weibei", isDirectory: true)
                .appendingPathComponent("course.json")
            if !FileManager.default.fileExists(atPath: writtenManifest.path) {
                try? CourseProjectManifest(courseID: courseID)
                    .encoded()
                    .write(to: writtenManifest, options: [.atomic])
            }
            if !courses.contains(where: { $0.id == courseID }) {
                courses.append(
                    Course(
                        id: courseID,
                        title: name,
                        colorIndex: nextCourseColorIndex(),
                        sourceRootRelativePath: name
                    )
                )
            }
            resolvedCourseRootURLs[courseID] = child
        }
    }

    private func ensureCourseScaffold(at root: URL) {
        for name in [
            CourseLibraryLayout.courseMaterialsDirectoryName,
            CourseLibraryLayout.courseNotesDirectoryName,
            ".weibei",
        ] {
            try? FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
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
        let liveIdentity = importedFileIdentityResolver(root)
        let identityMatches = course.sourceRootIdentity.flatMap { expected in
            liveIdentity.map { expected.matchesAcrossVolumeDrift($0) }
        } ?? false
        if !identityMatches, courseManifestCourseID(at: root) != course.id {
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
            guard let expectedRootIdentity = liveIdentity
                    ?? course.sourceRootIdentity else {
                throw CourseProjectRootError.manifestMismatch
            }
            // S6-5：去掉 thread evidence 官僚路径，直接 adoptionSnapshot。
            let snapshot = try await courseProjectFileWorker
                .adoptionSnapshot(
                    at: root,
                    expectedRootIdentity: expectedRootIdentity
                )
            lastPortableAdoptionReadRanOnMainThread = false
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

    func findDirectory(
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
            if let live = importedFileIdentityResolver(canonical),
               identity.matchesAcrossVolumeDrift(live) {
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

    func courseHasNeverHadFolder(_ courseID: UUID) -> Bool {
        guard let course = course(withID: courseID) else { return false }
        return course.sourceRootRelativePath == nil
            && course.sourceRootPath == nil
            && course.sourceRootIdentity == nil
            && course.sourceRootBookmarkData == nil
    }

    func deleteCourse(_ courseID: UUID) async throws {
        guard course(withID: courseID) != nil else {
            throw CourseRemovalError.courseNotFound
        }
        if courseHasNeverHadFolder(courseID) {
            try await removeCourseFromWeiBei(courseID)
        } else {
            _ = try await moveCourseFolderToTrash(courseID)
        }
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

        // 同卷 receipt 只负责区分“隔离待还原”和“已进废纸篓待清登记”；
        // 不恢复 workspace 级 journal。
        var isolation: CourseRootTrashIsolation?
        var receiptCleanup: CourseTrashReceiptCleanup?
        do {
            try courseProjectMutationHook(.beforeCourseRootTrashMove)
            // S6-4：不再因 Agent/笔记 pending 拒绝废纸篓。
            guard course(withID: courseID) == prepared.course,
                  activeCourseRemovalTokens[courseID] == prepared.token,
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
                    transactionID.uuidString,
                    isDirectory: true
                )
            isolation = try await courseProjectFileWorker
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
            guard let activeIsolation = isolation else {
                throw CourseRemovalError.courseRootUnavailable
            }
            receiptCleanup = try CourseProjectFileWorker.writeCourseTrashReceipt(
                for: activeIsolation,
                courseID: courseID
            )
            let trashedRoot = try await courseProjectFileWorker
                .moveIsolatedCourseRootToTrash(
                    activeIsolation,
                    expectedCourseID: courseID,
                    selfCheckDestination: selfCheckDestination
                )
            // 已进入废纸篓：不再回滚隔离目录。
            isolation = nil
            try courseProjectMutationHook(
                .afterCourseRootTrashMoveBeforeJournal
            )
            try courseProjectMutationHook(
                .afterCourseRootTrashJournalBeforeWorkspaceSave
            )

            guard await persistWorkspaceRemovingCourse(courseID) else {
                removeCourseLocalRegistration(courseID)
                if let receiptCleanup {
                    pendingCourseTrashReceiptCleanups.append(
                        receiptCleanup
                    )
                }
                _ = save()
                if shouldDismissCourseWorkspace {
                    courseWorkspacePresented = false
                }
                finishCourseRemovalAttempt(
                    courseID,
                    token: prepared.token,
                    succeeded: true
                )
                return trashedRoot
            }

            removeCourseLocalRegistration(courseID)
            // ponytail: a crash after the workspace commit can leave one tiny
            // receipt; add a trusted cleanup index only if this becomes observable.
            if let receiptCleanup,
               !CourseProjectFileWorker.cleanupCourseTrashReceipt(
                receiptCleanup,
                identityResolver: importedFileIdentityResolver
               ) {
                pendingCourseTrashReceiptCleanups.append(
                    receiptCleanup
                )
            }
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
            if let isolation {
                await courseProjectFileWorker.restoreCourseRootTrashIsolation(
                    isolation
                )
                if importedFileIdentityResolver(root) == rootIdentity,
                   let receiptCleanup {
                    CourseProjectFileWorker.cleanupCourseTrashReceipt(
                        receiptCleanup,
                        identityResolver: importedFileIdentityResolver
                    )
                }
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

    func deleteCourseForSelfCheck(_ courseID: UUID) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        try waitForCourseFileOperation {
            try await self.deleteCourse(courseID)
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
        precondition(WeiBeiSafetyTestMode.isEnabled)
        // S3：不再有课程移除 journal 恢复。
    }

    func recoverCourseTransactionsForSelfCheck() throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        // S3：不再从 journal 恢复；启动清理已覆盖残留事务目录。
        silentlyCleanupOrphanCourseTransactions()
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

            // S6-4：已取消 Agent 并等文件突变归零；不再因笔记/Agent 待写拒绝移除。
            guard course(withID: courseID) == expectedCourse,
                  activeCourseRemovalTransactionID == token,
                  activeCourseRemovalTokens[courseID] == token,
                  activeCourseFileMutationCounts[
                    courseID,
                    default: 0
                  ] == 0 else {
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
                // Trash path still refuses when the live folder cannot accept
                // the latest portable state. Unregister-only must not require
                // that write: the folder is already gone or unwritable.
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
                guard case .courseOwned(let ownerCourseID, _) = item.storage,
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
            setNoteDraft(nil, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteOperationErrorsByItemID.removeValue(forKey: itemID)
            noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
            lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: itemID)
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
        // S3：不再阻塞于 pending journal。
        guard activeCourseRemovalTransactionID == nil else {
            throw CourseRemovalError.courseBusy
        }
        let transactionID = UUID()
        activeCourseRemovalTransactionID = transactionID
        return transactionID
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
        courseIDs: Set<UUID>,
        itemIDs: Set<String> = []
    ) throws {
        guard courseIDs.allSatisfy({ courseID in
                courses.contains(where: { $0.id == courseID })
              }) else {
            throw CourseOwnedFileError.courseNotFound
        }
        guard courseIDs.allSatisfy({
            activeCourseRemovalTokens[$0] == nil
        }) else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard itemIDs.allSatisfy({ itemID in
            importedItems.contains(where: { $0.id == itemID })
        }) else {
            throw CourseOwnedFileError.unsupportedFile
        }
        guard itemIDs.isDisjoint(with: activeItemFileMutationIDs) else {
            throw CourseOwnedFileError.itemBusy
        }
        for courseID in courseIDs {
            activeCourseFileMutationCounts[courseID, default: 0] += 1
        }
        activeItemFileMutationIDs.formUnion(itemIDs)
    }

    private func finishCourseFileMutation(
        courseIDs: Set<UUID>,
        itemIDs: Set<String> = []
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
        activeItemFileMutationIDs.subtract(itemIDs)
    }


    private func promoteCourseOwnedItemToCommon(
        itemID: String,
        conflictResolution: CourseFileConflictResolution
    ) async throws {
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID
        }),
        case .courseOwned(let ownerCourseID, _) =
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

        try beginCourseFileMutation(
            courseIDs: [ownerCourseID],
            itemIDs: [itemID]
        )
        defer {
            finishCourseFileMutation(
                courseIDs: [ownerCourseID],
                itemIDs: [itemID]
            )
        }

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
            importedItems[itemIndex].importedFileIdentity = placedIdentity
            importedItems[itemIndex].storage = .common(
                relativePath: sharedRelativePath
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
            } else {
                // ponytail: a crash here can leave one harmless old duplicate;
                // add a cleanup journal only if this becomes observable in use.
                showTransientNoteStatus(ui(
                    "课程关系已移除，但课程文件夹中的旧副本未能清理。",
                    "The course relation was removed, but the old course copy could not be cleaned up."
                ))
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
        guard !activeItemFileMutationIDs.contains(itemID),
              let item = importedItems.first(where: { $0.id == itemID }) else {
            return
        }
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

        if case .common = item.storage,
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
                    self?.showTransientNoteStatus(error.localizedDescription)
                }
            }
            return
        }
        if case .courseOwned(let ownerCourseID, _) = item.storage,
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
                    self?.showTransientNoteStatus(error.localizedDescription)
                }
            }
            return
        }
        if case .courseOwned(let ownerCourseID, _) = item.storage,
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
                    self?.showTransientNoteStatus(error.localizedDescription)
                }
            }
            return
        }
        if case .common = item.storage {
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
                        self?.showTransientNoteStatus(error.localizedDescription)
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
                        self?.showTransientNoteStatus(error.localizedDescription)
                    }
                }
                return
            }
        }

        // Legacy virtual memberships may still be removed without touching files.
        guard case .common = item.storage, added.isEmpty else { return }
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
        // 共享条目可能只存相对路径（历史数据），先从课程库根目录回填真实路径。
        _ = backfillSharedItemLocation(itemID: itemID)
        guard let item = importedItems.first(where: { $0.id == itemID }),
              !item.isSample,
              let sourceURL = item.url else {
            showTransientNoteStatus(
                ContentSourceRemovalError.itemUnavailable.localizedDescription
            )
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
            "这会把唯一原文件移到废纸篓，并从所有课程中删除。\n文件：\(displayTitle(for: item))\n路径：\(sourceURL.path)\n受影响课程：\(courseSummary)",
            "This moves the only source file to Trash and deletes it from every course.\nFile: \(displayTitle(for: item))\nPath: \(sourceURL.path)\nAffected courses: \(courseSummary)"
        )
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("移到废纸篓", "Move to Trash"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task { @MainActor [weak self] in
            do {
                try await self?.moveItemSourceToTrash(itemID)
            } catch {
                self?.showTransientNoteStatus(error.localizedDescription)
            }
        }
    }

    /// 共享条目可能只存相对路径而没有 urlPath / 文件身份（历史数据）。
    /// 删除等需要真实路径的操作前，从课程库根目录解析并就地回填。
    @discardableResult
    private func backfillSharedItemLocation(itemID: String) -> Bool {
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID
        }),
              case .common(let relativePath) = importedItems[itemIndex].storage,
              let root = courseLibraryRootURL,
              let resolved = CourseProjectPathPolicy.resolvedRelativePath(
                  relativePath,
                  inside: root
              ) else {
            return false
        }
        if importedItems[itemIndex].urlPath == nil {
            importedItems[itemIndex].urlPath = resolved.path
        }
        if importedItems[itemIndex].importedFileIdentity == nil {
            importedItems[itemIndex].importedFileIdentity =
                importedFileIdentityResolver(resolved)
        }
        return importedItems[itemIndex].url != nil
    }

    private func moveItemSourceToTrash(_ itemID: String) async throws {
        guard importedItems.contains(where: { $0.id == itemID }) else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        let affectedCourseIDs = Set(courseIDs(for: itemID))
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: [itemID]
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: [itemID]
            )
        }
        if stagedNoteDraft?.itemID == itemID,
           let draft = stagedNoteDraft {
            stagedNoteDraft = nil
            updateNote(draft.value, for: itemID)
        }
        flushPendingNotePersistence(for: itemID)
        while let task = courseNoteWriteTasksByItemID[itemID] {
            await task.value
        }
        guard await flushPendingWorkspaceSaveAsync() else {
            // 有待保存的更改没能写入磁盘时拒绝删除；这不是"找不到原文件"，
            // 分开报错避免误导（保存失败的具体原因见 workspaceSaveError / 日志）。
            throw ContentSourceRemovalError.pendingChangesUnsaved
        }
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID
        }) else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        _ = backfillSharedItemLocation(itemID: itemID)
        if case .common = importedItems[itemIndex].storage {
            _ = resolveTrackedImportedFile(at: itemIndex)
        }
        guard let sourceURL = importedItems[itemIndex].url,
              let expectedIdentity = importedItems[itemIndex]
                .importedFileIdentity else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        let formerSharedLinks: [(url: URL, identity: ImportedFileIdentity)]
        if case .common = importedItems[itemIndex].storage {
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

    func removeItemRegistration(_ itemID: String) {
        pendingNotePersistenceTasks.removeValue(forKey: itemID)?.cancel()
        courseNoteLoadTasksByItemID.removeValue(forKey: itemID)?.cancel()
        courseNoteWriteTasksByItemID.removeValue(forKey: itemID)?.cancel()
        pendingNotePersistenceByItemID.removeValue(forKey: itemID)
        courseNoteLoadGenerationByItemID.removeValue(forKey: itemID)
        courseNoteWritesInFlight.remove(itemID)
        setNoteDraft(nil, for: itemID)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
        noteOperationErrorsByItemID.removeValue(forKey: itemID)
        noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
        lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: itemID)
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
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: [itemID]
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: [itemID]
            )
        }
        guard let item = importedItems.first(where: { $0.id == itemID }),
              case .common(let sharedRelativePath) = item.storage,
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
        let isolatedLinkURL = transactionDirectory.appendingPathComponent(
            "isolated-link"
        )
        let previous = courseItemMemberships
        do {
            // S3：无 journal。隔离链接 → 更新登记 → 清理。
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
        } catch {
            // S3：无 journal 恢复；崩溃注入也必须走回滚。
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
            // S3：已提交登记则不回滚；静默留下隔离链接供用户重做/清理。
            // 崩溃注入同样走此路径（无 journal 恢复）。
            _ = sharedRelativePath
            _ = sharedSnapshot
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

#if DEBUG
    func moveItemSourceToTrashWithBlockedBackgroundSaveForSelfCheck(
        _ itemID: String,
        whileBlocked: @escaping @MainActor () -> Void
    ) async throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let previousMode = usesBackgroundWorkspacePersistenceForSelfCheck
        usesBackgroundWorkspacePersistenceForSelfCheck = true
        defer { usesBackgroundWorkspacePersistenceForSelfCheck = previousMode }
        let generation = workspaceSaveGeneration &+ 1
        await courseProjectFileWorker.prepareWorkspacePersistenceGateForSelfCheck(
            generation: generation
        )
        let deletion = Task { @MainActor in
            try await self.moveItemSourceToTrash(itemID)
        }
        await courseProjectFileWorker.waitUntilWorkspacePersistenceEnteredForSelfCheck(
            generation: generation
        )
        whileBlocked()
        await courseProjectFileWorker.releaseWorkspacePersistenceForSelfCheck(
            generation: generation
        )
        try await deletion.value
    }
#endif

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
        guard courses.contains(where: { $0.id == courseID }),
              itemIDs.isDisjoint(with: activeItemFileMutationIDs) else {
            return
        }
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
            case .common:
                return true
            case .common:
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

    /// One-pass course → visible-item counts for the contextual browser.
    /// Replaces per-course full-library rescans (`contextualBrowserItems`
    /// re-filtered + ICU-sorted once per course) that made opening the
    /// browser stutter on large libraries.
    func contextualBrowserItemCounts(
        _ kind: ContextualContentKind
    ) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for item in allItems where item.isNotebookNote == (kind == .note) {
            for courseID in courseMembershipIndex.courseIDs(for: item.id) {
                counts[courseID, default: 0] += 1
            }
        }
        return counts
    }

    /// Count of the browser's common (non-course) section without the display
    /// sort — root rows only need the number, not the sorted list.
    func contextualBrowserCommonCount(_ kind: ContextualContentKind) -> Int {
        allItems.reduce(into: 0) { count, item in
            guard item.isNotebookNote == (kind == .note) else { return }
            switch item.storage {
            case .common:
                count += 1
            case .common:
                if courseMembershipIndex.courseIDs(for: item.id).isEmpty {
                    count += 1
                }
            case .courseOwned, .bundledSample:
                break
            }
        }
    }

    func contextualBrowserCourseSummaries(
        _ kind: ContextualContentKind
    ) -> [(course: Course, itemCount: Int)] {
        let counts = contextualBrowserItemCounts(kind)
        return courses.compactMap { course in
            let count = counts[course.id] ?? 0
            guard count > 0 else { return nil }
            return (course, count)
        }.sorted {
            $0.course.title.localizedStandardCompare($1.course.title) == .orderedAscending
        }
    }

    func contextualBrowserCourses(
        _ kind: ContextualContentKind
    ) -> [Course] {
        contextualBrowserCourseSummaries(kind).map(\.course)
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
        return contextualBrowserCourseSummaries(kind).compactMap { summary in
            courseIDs.contains(summary.course.id) ? summary.course : nil
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

    /// Resolve course associations for one Agent turn. A shared item belongs to
    /// the explicit target course for this turn; unrelated memberships must not
    /// make the global Chat appear to have used those other courses.
    private func agentContextCourseIDs(
        for itemIDs: some Sequence<String>,
        targetCourseID: UUID?
    ) -> [UUID] {
        var result = Set<UUID>()
        for itemID in itemIDs {
            let memberships = courseMembershipIndex.courseIDs(for: itemID)
            if let targetCourseID,
               memberships.contains(targetCourseID) {
                result.insert(targetCourseID)
            } else {
                result.formUnion(memberships)
            }
        }
        return result.sorted { $0.uuidString < $1.uuidString }
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
                if let __wsErr = self?.ui(
                    "Chat 已删除，但对应的 Pi 运行状态清理失败：\(error.localizedDescription)",
                    "The Chat was deleted, but its Pi runtime state could not be removed: \(error.localizedDescription)"
                ) { self?.reportWorkspaceSaveFailure(__wsErr) }
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

    func saveAgentVisualizationState(
        messageID: UUID,
        visualizationID: String,
        stateJSON: String
    ) {
        guard stateJSON.utf8.count <= 262_144,
              (try? JSONSerialization.jsonObject(
                  with: Data(stateJSON.utf8),
                  options: .fragmentsAllowed
              )) != nil,
              let chatID = studySessions.first(where: { session in
                  session.messages.contains { $0.id == messageID }
              })?.id else { return }
        _ = updateAgentMessage(messageID, in: chatID) { message in
            message.contentBlocks = message.contentBlocks.map { block in
                guard case var .visualization(fragment) = block,
                      fragment.id == visualizationID else { return block }
                fragment.stateJSON = stateJSON
                return .visualization(fragment)
            }
        }
    }

    func submitAgentVisualizationAction(_ action: String, payloadJSON: String) {
        let action = String(action.prefix(200))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty,
              payloadJSON.utf8.count <= 65_536,
              (try? JSONSerialization.jsonObject(
                  with: Data(payloadJSON.utf8),
                  options: .fragmentsAllowed
              )) != nil,
              !isAgentRunningInActiveChat,
              !isStoppingAgent else { return }
        askAgent(
            replayingSelections: [],
            visibleQuestionOverride: ui(
                "互动操作：\(action)",
                "Interactive action: \(action)"
            ),
            questionOverride: ui(
                "我在互动界面中执行了「\(action)」。当前界面数据：\(payloadJSON)",
                "I used “\(action)” in the interactive view. Current view data: \(payloadJSON)"
            )
        )
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
                    message: workspaceSaveError ?? ui(
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
            notePersisted = notesByItemID[target.id] == nil
                && resultDigest != nil
                && noteBackingContentDigestsByItemID[target.id] == resultDigest
        } else {
            notePersisted = notesByItemID[target.id] == markdown
        }
        return notePersisted && flushPendingWorkspaceSave()
    }

    func syncActiveStudySession(titleSeed: String? = nil) {
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

    static func semanticSessionTitle(
        from suggestion: String?,
        replacing currentTitle: String,
        messages: [AgentMessage]
    ) -> String? {
        guard let firstQuestion = messages.first(where: { $0.role == .user }),
              currentTitle == sessionTitle(from: firstQuestion.text),
              let suggestion,
              !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let title = sessionTitle(from: suggestion)
        let genericTitles = ["WeiBei", "Study Session", "New Chat", "New Conversation", "新对话", "新会话"]
        guard title != currentTitle,
              !genericTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) else { return nil }
        return title
    }

    @discardableResult
    func applySemanticSessionTitle(_ suggestion: String?, to sessionID: UUID) -> Bool {
        guard let index = studySessions.firstIndex(where: { $0.id == sessionID }),
              let title = Self.semanticSessionTitle(
                  from: suggestion,
                  replacing: studySessions[index].title,
                  messages: studySessions[index].messages
              ) else { return false }
        studySessions[index].title = title
        studySessions[index].updatedAt = Date()
        return true
    }

    private func applySemanticSessionTitleAndSave(_ suggestion: String, to sessionID: UUID) async {
        guard applySemanticSessionTitle(suggestion, to: sessionID) else { return }
        save()
        _ = await flushPendingWorkspaceSaveAsync()
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
        if let note = activeNoteItem {
            // 正文抬头优先于文件名：只要有正文就可能提供显示名；自定义名存在时不必读正文。
            // 活动笔记的正文本就在内存（noteText），不会触发额外加载。
            let hasCustomTitle = note.customDisplayTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let body = hasCustomTitle ? "" : noteText(for: note)
            let resolved = NoteTabDisplayTitle.resolve(
                customTitle: note.customDisplayTitle,
                noteTitle: note.title,
                body: body
            )
            return resolved.isEmpty ? ui("未命名笔记", "Untitled note") : resolved
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

    /// "选择其他笔记"列表的显示名，与浮动 tab 同口径：
    /// 自定义名 > 正文抬头 > 文件名 > 正文前几个字。
    /// 仅用于笔记列表展示；`displayTitle(for:)` 保持原名语义，
    /// 引用匹配、排序、重命名草稿等仍按文件标题走。
    func noteListDisplayTitle(for item: StudyItem) -> String {
        guard item.isNotebookNote else { return item.title }
        let resolved = NoteTabDisplayTitle.resolve(
            customTitle: item.customDisplayTitle,
            noteTitle: item.title,
            body: noteMarkdownText(for: item)
        )
        return resolved.isEmpty ? item.title : resolved
    }

    func displaySubtitle(for item: StudyItem) -> String {
        item.subtitle
    }

    func displayTags(for item: StudyItem, limit: Int = 3) -> [String] {
        guard item.isNotebookNote else { return [] }
        return Array(MarkdownTagSearch.tags(in: noteMarkdownText(for: item)).prefix(limit))
    }

    func sidebarTagMarkdown(itemID: String) async -> String? {
        guard let item = importedItems.first(where: {
            $0.id == itemID && $0.isNotebookNote
        }) else { return nil }
        if case .common = item.storage,
           item.editsBackingMarkdownFile,
           item.importedFileIdentity == nil,
           activeNoteItemID != item.id,
           notesByItemID[item.id] == nil,
           loadedCourseNoteTextByItemID[item.id] == nil,
           let url = item.url?.standardizedFileURL,
           let identity = importedFileIdentityResolver(url),
           let result = try? await courseProjectFileWorker.readMarkdown(
               at: url,
               expectedIdentity: identity
           ) {
            guard let current = importedItems.first(where: { $0.id == item.id }),
                  current.importedFileIdentity == nil,
                  current.url?.standardizedFileURL == url,
                  importedFileIdentityResolver(url)?.matchesAcrossVolumeDrift(identity) == true else {
                return nil
            }
            return cleanLegacyPlaceholder(result.markdown)
        }
        return try? await agentActionNoteMarkdown(item)
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
            refreshActiveNoteFromBackingFile()
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
        markPortableCoursesDirty(forItemIDs: Set([noteItemID]).union(sourceItemIDs))
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
        markPortableCoursesDirty(forItemIDs: Set([sourceItemID]).union(noteItemIDs))
        save()
    }

    private func markPortableCoursesDirty(forItemIDs itemIDs: Set<String>) {
        for membership in courseItemMemberships where itemIDs.contains(membership.itemID) {
            dirtyPortableCourseIDs.insert(membership.courseID)
        }
        for item in importedItems where itemIDs.contains(item.id) {
            if case let .courseOwned(courseID, _) = item.storage {
                dirtyPortableCourseIDs.insert(courseID)
            }
        }
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
            guard let expanded = CourseProjectFileWorker.expandedSupportedFiles(
                from: urls,
                markdownOnly: asNotes
            ) else {
                showImportLimitExceededAlert()
                completion([])
                return
            }
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
                    showTransientNoteStatus(ui(
                        "“\(sourceURL.lastPathComponent)”未能加入课程：\(error.localizedDescription)",
                        "Could not add “\(sourceURL.lastPathComponent)” to the course: \(error.localizedDescription)"
                    ))
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

    private func showImportLimitExceededAlert() {
        guard !WeiBeiSafetyTestMode.isEnabled else { return }
        let alert = NSAlert()
        alert.messageText = ui("没有导入", "Nothing Imported")
        alert.informativeText = ui(
            "所选内容包含超过500个可导入文件。为避免只导入其中一部分，魏碑没有写入任何资料。请选择更小的文件夹，或直接选择需要的文件。",
            "The selection contains more than 500 importable files. To avoid a partial import, WeiBei did not add anything. Choose a smaller folder or select the files you need directly."
        )
        alert.addButton(withTitle: ui("知道了", "OK"))
        alert.runModal()
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
           targetItem.map({ if case .common = $0.storage { return true }; return false }) != true {
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

    private func itemIsAvailableInCourseContext(itemID: String, courseID: UUID) -> Bool {
        if courseMembershipIndex.courseIDs(for: itemID).contains(courseID) {
            return true
        }
        guard let item = importedItems.first(where: { $0.id == itemID }) else { return false }
        if case .common = item.storage { return true }
        return false
    }

    @discardableResult
    func openCourseMaterial(_ itemID: String, in requestedCourseID: UUID? = nil) -> Bool {
        if let requestedCourseID {
            guard itemIsAvailableInCourseContext(itemID: itemID, courseID: requestedCourseID) else {
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
        guard let current = importedItems.first(where: { $0.id == itemID }) else {
            if resolution.changed { save() }
            return false
        }
        if resolution.changed {
            save()
            courseDocumentSearchIndex.schedule([current])
            invalidateAgentContext()
        }
        guard let resolvedURL = resolution.url,
              FileManager.default.isReadableFile(atPath: resolvedURL.path) else {
            return false
        }
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
            guard itemIsAvailableInCourseContext(itemID: itemID, courseID: requestedCourseID) else {
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
              !isAgentRunningInActiveChat,
              agentRequestTask == nil || isAskingAgent,
              course(withID: courseID) != nil else {
            return nil
        }

        guard let session = activeStudySession
                ?? createStudySession(courseID: nil) else {
            return nil
        }

        freshlyCreatedEmptyStudySessionID = nil
        activeCourseID = courseID
        agentDraft = question
        agentDraftsBySessionID[session.id] = question
        openConversationInWorkspace(courseID: courseID)
        submitAgentDraft(targetCourseID: courseID)
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
            setNoteDraft(value, for: item.id)
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
            setNoteDraft(value, for: item.id)
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
            showTransientNoteStatus(ui("笔记名不能为空。", "Note name cannot be empty."))
            return nil
        }
        let fileStem = safeFileStem(title)
        return await createCourseNotebookNote(
            courseID: courseID,
            title: fileStem,
            markdown: defaultNotebookNote()
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
            showTransientNoteStatus(ui(
                "无法创建课程笔记：\(error.localizedDescription)",
                "Could not create the course note: \(error.localizedDescription)"
            ))
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

    func waitForCourseFileOperation<T>(
        _ operation: @escaping @MainActor () async throws -> T
    ) throws -> T {
        var result: Result<T, Error>?
        Task { @MainActor in
            do {
                result = .success(try await operation())
            } catch is CancellationError {
                // 析构/测试收尾 cancel 不应把 CancellationError 原样抛给 XCTest。
                result = .failure(
                    NSError(
                        domain: "WeiBei.WorkspaceStore",
                        code: NSUserCancelledError,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "course file operation cancelled",
                        ]
                    )
                )
            } catch {
                result = .failure(error)
            }
        }
        let deadline = WeiBeiSafetyTestMode.isEnabled
            ? Date().addingTimeInterval(45)
            : Date.distantFuture
        while result == nil {
            if Date() > deadline {
                throw NSError(
                    domain: "WeiBei.WorkspaceStore",
                    code: NSUserCancelledError,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "course file operation timed out",
                    ]
                )
            }
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
        // 同一资料允许重复新建多篇笔记，noteSourceLink 保留关联。
        createNotebookNote(seed: .currentMaterial(selectedMaterialItem))
    }

    func promptCreateBlankNotebookNote() {
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
    }

    func confirmNotebookNoteCreation() {
        guard let draft = notebookCreationDraft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            showTransientNoteStatus(ui("笔记名不能为空。", "Note name cannot be empty."))
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
            // Only assign when changed — pane visibility lives on paneState; avoid store thrash.
            applyLayoutMatchingThreePaneOrderIfNeeded()
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
        applyLayoutMatchingThreePaneOrderIfNeeded()
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
        applyLayoutMatchingThreePaneOrderIfNeeded()
    }

    /// Assign `layout` only when the matched three-pane layout actually changes.
    private func applyLayoutMatchingThreePaneOrderIfNeeded() {
        let next = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
        guard layout != next else { return }
        layout = next
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
        // Single paneState publish for the three visibility flags.
        paneState.setDocumentPanes(
            reader: roles.contains(.reader),
            agent: roles.contains(.agent),
            notes: roles.contains(.notes)
        )
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
            guard itemIsAvailableInCourseContext(itemID: item.id, courseID: courseID),
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
               itemIsAvailableInCourseContext(itemID: item.id, courseID: activeCourseID) {
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
        // 笔记固定为所见即所得（rich）写作：NoteRenderMode 机制保留用于持久化与旧数据
        // 兼容，但所有模式切换入口已移除，任何请求都收敛为展示并聚焦 rich 笔记面板。
        let nextMode = NoteRenderMode.rich
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

    func setAgentInteractiveVisualizationsEnabled(_ enabled: Bool) {
        guard agentInteractiveVisualizationsEnabled != enabled else { return }
        agentInteractiveVisualizationsEnabled = enabled
        selectionAskThreadDefaults.set(
            enabled,
            forKey: Self.interactiveVisualizationsDefaultsKey
        )
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
        guard let expandedURLs = CourseProjectFileWorker.expandedSupportedFiles(
            from: urls,
            markdownOnly: markdownOnly
        ) else {
            showImportLimitExceededAlert()
            return []
        }
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
        for rawURL in expandedURLs {
            let url: URL
            if courseLibraryRootURL != nil {
                do {
                    url = try copyExternalFileIntoLibrary(
                        rawURL,
                        isNote: isNotebookNote(rawURL)
                    )
                } catch {
                    showTransientNoteStatus(error.localizedDescription)
                    continue
                }
            } else {
                continue
            }
            guard let relativePath = libraryRelativePath(of: url) else {
                continue
            }
            let matchingIndex = importedItems.firstIndex { item in
                item.storage == .common(relativePath: relativePath)
            }
            if let matchingIndex {
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
                    || importedItems[matchingIndex].isNotebookNote != nextRole {
                    importedItems[matchingIndex].urlPath = url.path
                    importedItems[matchingIndex].title = nextTitle
                    importedItems[matchingIndex].subtitle = nextSubtitle
                    importedItems[matchingIndex].kind = nextKind
                    importedItems[matchingIndex].isNotebookNote = nextRole
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
                isSample: false,
                isNotebookNote: isNotebookNote(url),
                storage: .common(relativePath: relativePath)
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

    nonisolated static func makeImportedFileBookmark(for url: URL) -> Data? {
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

    nonisolated static func makeImportedItemID() -> String {
        "imported:\(UUID().uuidString.lowercased())"
    }

    private static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    private static func isSupportedCourseFile(_ url: URL) -> Bool {
        ["pdf", "html", "htm", "md", "markdown", "txt", "text"]
            .contains(url.pathExtension.lowercased())
    }


    func openOrCreateWikiNote(title rawTitle: String) {
        let title = WikiLink.targetTitle(from: rawTitle)
        guard !title.isEmpty else { return }

        let commonNotesDirectory = courseLibraryRootURL?.appendingPathComponent(
            CourseOwnedFileRole.note.commonDirectoryName,
            isDirectory: true
        )
        guard let notesDirectory = commonNotesDirectory else {
            showTransientNoteStatus(ui("请先选择魏碑资料库。", "Choose a WeiBei library first."))
            return
        }
        let fileName = "\(safeFileStem(title)).md"
        let url = notesDirectory.appendingPathComponent(fileName)
        let relativePath = "\(CourseLibraryLayout.commonNotesDirectoryName)/\(fileName)"

        if let index = importedItems.firstIndex(where: { item in
            item.storage == .common(relativePath: relativePath)
                || item.urlPath == url.path
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
                    && importedItems[index].importedFileIdentity != identity
                    && importedItems[index].importedFileIdentity?
                        .matchesAcrossVolumeDrift(identity) != true {
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
                isSample: false,
                isNotebookNote: true,
                storage: .common(relativePath: relativePath)
            )
            if !importedItems.contains(where: { $0.urlPath == url.path }) {
                importedItems.append(item)
            }
            courseDocumentSearchIndex.synchronize(allItems)
            select(itemID: item.id)
            showTransientNoteStatus(ui("已创建双链笔记：\(url.lastPathComponent)", "Created wiki note: \(url.lastPathComponent)"))
        } catch {
            showTransientNoteStatus(ui("无法创建双链笔记：\(error.localizedDescription)", "Could not create wiki note: \(error.localizedDescription)"))
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
            showTransientNoteStatus(ui("笔记名不能为空。", "Note name cannot be empty."))
            return nil
        }

        persistCurrentNote()
        guard courseLibraryRootURL != nil else {
            showTransientNoteStatus(ui("请先选择魏碑资料库。", "Choose a WeiBei library first."))
            return nil
        }
        // Sidebar-active course is not a workspace. A blank note goes to 通用笔记
        // unless the course workspace overlay is actually open.
        let targetCourseID: UUID?
        switch seed {
        case .blank:
            targetCourseID = courseWorkspaceCourseID
        case .currentMaterial(let item):
            targetCourseID = item.storage.ownerCourseID ?? courseWorkspaceCourseID
        }
        let notesDirectory: URL
        if let targetCourseID, let courseRoot = courseRootURL(for: targetCourseID) {
            notesDirectory = courseRoot.appendingPathComponent(
                CourseLibraryLayout.courseNotesDirectoryName,
                isDirectory: true
            )
        } else {
            notesDirectory = courseLibraryRootURL!.appendingPathComponent(
                CourseLibraryLayout.commonNotesDirectoryName,
                isDirectory: true
            )
        }

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let url = nextNotebookNoteURL(in: notesDirectory, title: title)
            let resolvedStorage: StudyItemStorage
            if let targetCourseID {
                resolvedStorage = .courseOwned(
                    ownerCourseID: targetCourseID,
                    relativePath:
                        "\(CourseLibraryLayout.courseNotesDirectoryName)/\(url.lastPathComponent)"
                )
            } else {
                resolvedStorage = .common(
                    relativePath:
                        "\(CourseLibraryLayout.commonNotesDirectoryName)/\(url.lastPathComponent)"
                )
            }
            let item = StudyItem(
                id: Self.makeImportedItemID(),
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                isSample: false,
                isNotebookNote: true,
                storage: resolvedStorage
            )
            let markdown = initialMarkdown
                ?? defaultNotebookNote()
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            noteBackingContentDigestsByItemID[item.id] = Self.noteContentDigest(Data(markdown.utf8))
            headingSyncedNoteStemByItemID[item.id] = url.deletingPathExtension().lastPathComponent
            importedItems.append(item)
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
            showTransientNoteStatus(ui("无法创建笔记：\(error.localizedDescription)", "Could not create note: \(error.localizedDescription)"))
            return nil
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
                // Silent write on interaction state first so we never fan out every pixel
                // into WorkspaceStore (or agent chat SelectionOverlay remasure).
                // Throttle a real publish so the floating capsule can track ~20fps.
                interaction.setSelectionAnchorSilently(anchor)
                if agentSurface == .selectionFloat {
                    interaction.publishSelectionAnchorIfDue(minInterval: 0.05)
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
        WorkspaceInteractionState.anchorsApproximatelyEqual(lhs, rhs, epsilon: epsilon)
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
                let isCommonMaterial = importedItems.contains { item in
                    guard item.id == itemEntry.key, !item.isNotebookNote else { return false }
                    if case .common = item.storage { return true }
                    return false
                }
                guard validItemIDs.contains(itemEntry.key) || isCommonMaterial,
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
            switch item.storage {
            case .courseOwned(let ownerCourseID, _):
                return [ownerCourseID]
            case .common:
                if let courseID = target.courseID {
                    return [courseID]
                }
                return []
            case .bundledSample:
                return []
            }
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
        case .courseOwned(let ownerCourseID, _):
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
        case .common:
            isShared = true
            guard CourseProjectFileWorker.symbolicLink(
                at: entryURL,
                pointsTo: targetURL
            ) else {
                return nil
            }
        case .common, .bundledSample:
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
            isSample: false,
            storage: .courseOwned(ownerCourseID: courseID, relativePath: relativePath)
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
            isSample: false,
            storage: .common(relativePath: "")
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
        setNoteDraft(nil, for: itemID)
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
        setNoteDraft(draft, for: noteItemID)
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
        dirtyPortableCourseIDs.insert(courseID)
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
        setNoteDraft(noteText, for: noteItemID)
        loadedCourseNoteTextByItemID[noteItemID] = noteText
        pendingNoteWritesByItemID[noteItemID] = PendingNoteWriteState(
            baselineContentDigest: importedItems.first {
                $0.id == noteItemID
            }?.contentDigest
        )
        dirtyPortableCourseIDs.insert(courseID)
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
                try await Self.executeAgentHostTool(
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
    ) async throws -> StudyAgentHostToolResult {
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

        case let .webOpen(url, maximumCharacters):
            return StudyAgentHostToolResult(
                query: url,
                items: [],
                webPages: [
                    try await WeiBeiWebResearchClient.open(
                        url,
                        maximumCharacters: maximumCharacters
                    ),
                ]
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
        case .common:
            return true
        case .bundledSample:
            return item.isSample
        case .courseOwned:
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

    func submitAgentDraft(targetCourseID: UUID? = nil) {
        if isAgentRunningInActiveChat {
            cancelAgentRequest()
            return
        }
        let question = agentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStoppingAgent else { return }
        if isAskingAgent {
            pendingAgentSwitchTargetID = activeStudySessionID
            pendingAgentSwitchCourseID = targetCourseID
            isAgentSwitchConfirmationPresented = true
            return
        }
        askAgent(targetCourseID: targetCourseID)
    }

    func dismissAgentSwitchConfirmation() {
        isAgentSwitchConfirmationPresented = false
        pendingAgentSwitchTargetID = nil
        pendingAgentSwitchCourseID = nil
    }

    func confirmAgentSwitchAndSend() {
        guard isAgentSwitchConfirmationPresented,
              let targetID = pendingAgentSwitchTargetID,
              activeStudySessionID == targetID,
              !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let targetCourseID = pendingAgentSwitchCourseID
        dismissAgentSwitchConfirmation()
        stopAgent(restoreDraft: false) { [weak self] in
            guard let self,
                  self.activeStudySessionID == targetID,
                  self.studySessions.contains(where: { $0.id == targetID }),
                  !self.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.askAgent(targetCourseID: targetCourseID)
        }
    }

    func askAgent(
        reusingLastUserMessage: Bool = false,
        replayingSelections: [SelectionContext]? = nil,
        targetCourseID: UUID? = nil,
        visibleQuestionOverride: String? = nil,
        questionOverride: String? = nil
    ) {
        flushStagedNoteDraftForAgentContext()
        let question = (questionOverride ?? agentDraft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard agentRequestTask == nil,
              !isStoppingAgent,
              !isAskingAgent,
              !question.isEmpty else { return }
        let target: AgentConversationTarget
        do {
            if (reusingLastUserMessage || targetCourseID != nil),
               let session = activeStudySession {
                target = try makeAgentConversationTarget(
                    sessionID: session.id,
                    courseID: targetCourseID
                )
            } else {
                target = try agentConversationTarget()
            }
        } catch {
            recordAgentTargetFailure(
                question: question,
                error: error,
                appendUserMessage: !reusingLastUserMessage,
                targetCourseID: targetCourseID,
                visibleQuestion: visibleQuestionOverride,
                preserveComposerDraft: questionOverride != nil
            )
            return
        }
        agentRequestTask = Task { @MainActor [weak self] in
            await self?.performAgentRequest(
                target: target,
                reusingLastUserMessage: reusingLastUserMessage,
                replayingSelections: replayingSelections,
                visibleQuestionOverride: visibleQuestionOverride,
                questionOverride: questionOverride
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
        appendUserMessage: Bool = true,
        targetCourseID: UUID? = nil,
        visibleQuestion: String? = nil,
        preserveComposerDraft: Bool = false
    ) {
        ensureActiveStudySession()
        guard let session = activeStudySession else { return }
        let requestID = UUID()
        let sourceTitle = agentMessageSourceTitle
        lastAgentFailureKind = .generic
        lastFailedAgentQuestion = question
        if !preserveComposerDraft {
            agentDraftsBySessionID[session.id] = question
        }
        focusedPane = .agent
        if appendUserMessage {
            let userMessage = AgentMessage(
                role: .user,
                text: visibleQuestion ?? question,
                source: sourceTitle
            )
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
                courseID: targetCourseID ?? session.courseID
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
        replayingSelections: [SelectionContext]? = nil,
        visibleQuestionOverride: String? = nil,
        questionOverride: String? = nil
    ) async {
        guard !Task.isCancelled, activeStudySessionID == target.sessionID else {
            agentRequestTask = nil
            return
        }
        flushStagedNoteDraftForAgentContext()
        let question = (questionOverride ?? agentDraft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                appendUserMessage: !reusingLastUserMessage,
                targetCourseID: target.courseID,
                visibleQuestion: visibleQuestionOverride,
                preserveComposerDraft: questionOverride != nil
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
            with: agentContextCourseIDs(
                for: sentSelections.compactMap(\.itemID),
                targetCourseID: target.courseID
            )
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
            with: agentContextCourseIDs(
                for: [sentMaterialItemID, sentNoteItemID].compactMap { $0 },
                targetCourseID: target.courseID
            )
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
        agentVisualizationIDsUpdatingHistory = []
        agentStreaming.text = ""
        agentStreaming.activityText = ui("正在准备课程现场", "Preparing course context")
        defer {
            if activeAgentRequestID == requestID {
                activeAgentRequestID = nil
                activeAgentReplyMessageID = nil
                activeAgentReplyChatID = nil
                isAskingAgent = false
                latestAgentStreamingText = ""
                lastAgentStreamingPublishNanoseconds = 0
                agentVisualizationIDsUpdatingHistory = []
                agentStreaming.text = ""
                agentStreaming.activityText = nil
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
                let userMessage = AgentMessage(
                    role: .user,
                    text: visibleQuestionOverride ?? question,
                    source: sourceTitle
                )
                appendAgentMessage(userMessage)
                appendMessageToActiveSelectionAskThread(userMessage.id)
                didAppendUserMessage = true
            }
            if let courseID = target.courseID {
                associateStudySession(target.sessionID, with: [courseID])
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

            if questionOverride == nil {
                agentDraft = ""
                agentDraftsBySessionID[target.sessionID] = ""
            }
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
                contextRevision: "\(requestWorkspaceRevision):\(requestID.uuidString.lowercased())",
                interactiveVisualizationsEnabled: agentInteractiveVisualizationsEnabled
            )
            agentStreaming.activityText = ui("正在思考", "Thinking")
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
                let visibleContentBlocks = currentAgentVisualizationBlocks(reply.contentBlocks)
                _ = updateAgentMessage(messageID, in: target.sessionID) {
                    $0.text = reply.text
                    $0.contentBlocks = visibleContentBlocks
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
                if reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   visibleContentBlocks.isEmpty,
                   actions.isEmpty {
                    removeAgentMessage(messageID, from: target.sessionID)
                }
            }
            associateStudySession(
                target.sessionID,
                with: sources.compactMap(\.courseID)
            )
            associateStudySession(
                target.sessionID,
                with: agentContextCourseIDs(
                    for: sources.compactMap(\.itemID),
                    targetCourseID: target.courseID
                )
            )
            associateStudySession(
                target.sessionID,
                with: agentContextCourseIDs(
                    for: reply.readItemIDs,
                    targetCourseID: target.courseID
                )
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
                    kind: .cancelled,
                    restoreDraft: questionOverride == nil
                )
            }
            if questionOverride == nil {
                agentDraftsBySessionID[target.sessionID] = question
            }
            if questionOverride == nil,
               activeStudySessionID == target.sessionID,
               agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentDraft = question
                lastAgentFailureKind = .cancelled
            }
            return
        } catch {
            guard activeAgentRequestID == requestID else { return }
            if !didAppendUserMessage {
                appendAgentMessage(
                    AgentMessage(
                        role: .user,
                        text: visibleQuestionOverride ?? question,
                        source: sourceTitle
                    )
                )
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
            if questionOverride == nil {
                agentDraftsBySessionID[target.sessionID] = question
            }
            if activeStudySessionID == target.sessionID {
                if questionOverride == nil {
                    agentDraft = question
                }
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
                    fallbackText: failureText,
                    restoreDraft: questionOverride == nil
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
        agentStreaming.text = ""
        agentStreaming.activityText = nil
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

    func retryAgentRequest(
        _ question: String,
        targetCourseID: UUID? = nil
    ) {
        guard !isAgentRunningInActiveChat, !isStoppingAgent else { return }
        let cleaned = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        agentDraft = cleaned
        lastFailedAgentQuestion = nil
        lastAgentFailureKind = nil
        submitAgentDraft(targetCourseID: targetCourseID)
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
            targetCourseID: reply.origin?.courseID
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
        let endpoint = try AgentProviderEndpoint(
            provider: selectedProvider,
            baseURL: agentBaseURL
        )
        if selectedProvider == .azureOpenAI {
            let credentialIsBound = try await piRuntime.managementCatalog()
                .credentials
                .contains {
                    $0.providerId == endpoint.piProviderID
                        && $0.type == .apiKey
                        && $0.boundEndpoint == endpoint.baseURL
                }
            guard credentialIsBound else {
                throw AgentProviderEndpointError.azureCredentialRequiresReentry
            }
        }
        await piRuntime.configure(
            PiAgentProviderConfiguration(
                provider: endpoint.piProviderID,
                model: selectedModel.isEmpty ? nil : selectedModel,
                baseURL: endpoint.baseURL
            )
        )
        try await piRuntime.writeCustomModelsJSONIfNeeded(
            providerID: selectedProvider,
            baseURL: endpoint.baseURL ?? "",
            model: selectedModel
        )
        return try await piRuntime.respond(
            to: request,
            sessionID: target.sessionID,
            workingDirectory: target.workingDirectory,
            hostToolHandler: hostToolHandler,
            sessionTitleHandler: { [weak self] title in
                await self?.applySemanticSessionTitleAndSave(title, to: target.sessionID)
            }
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
                agentStreaming.activityText = ui("正在思考", "Thinking")
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
                agentStreaming.activityText = base + ui("：", ": ") + detail
            } else {
                agentStreaming.activityText = base
            }
        case let .text(text, blocks):
            latestAgentStreamingText = text
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentReplyIDsThatDisplayedStreamingText.insert(replyMessageID)
            }
            let now = DispatchTime.now().uptimeNanoseconds
            if updatesVisibleChat,
               now &- lastAgentStreamingPublishNanoseconds >= 33_000_000 {
                lastAgentStreamingPublishNanoseconds = now
                agentStreaming.text = text
                updateStreamingAgentContentBlocks(
                    currentAgentVisualizationBlocks(blocks),
                    messageID: replyMessageID,
                    chatID: chatID
                )
            }
            if updatesVisibleChat {
                let activity = ui("正在组织回答", "Composing answer")
                if agentStreaming.activityText != activity {
                    agentStreaming.activityText = activity
                }
            }
        case let .visualization(fragment, blocks):
            if let historicalMessageID = historicalAgentMessageID(
                containingVisualization: fragment.id,
                in: chatID,
                excluding: replyMessageID
            ) {
                _ = updateAgentMessage(historicalMessageID, in: chatID) { message in
                    message.contentBlocks = message.contentBlocks.map { block in
                        guard case let .visualization(existing) = block,
                              existing.id == fragment.id else { return block }
                        var replacement = fragment
                        replacement.stateJSON = existing.stateJSON
                        return .visualization(replacement)
                    }
                }
                agentVisualizationIDsUpdatingHistory.insert(fragment.id)
            }
            _ = updateAgentMessage(replyMessageID, in: chatID) {
                $0.contentBlocks = currentAgentVisualizationBlocks(blocks)
            }
            if updatesVisibleChat {
                agentStreaming.activityText = ui("正在继续回答", "Continuing response")
            }
        }
    }

    private func historicalAgentMessageID(
        containingVisualization visualizationID: String,
        in chatID: UUID,
        excluding replyMessageID: UUID
    ) -> UUID? {
        studySessions
            .first(where: { $0.id == chatID })?
            .messages
            .first(where: { message in
                message.id != replyMessageID
                    && message.contentBlocks.contains { block in
                        if case let .visualization(fragment) = block {
                            return fragment.id == visualizationID
                        }
                        return false
                    }
            })?
            .id
    }

    private func updateStreamingAgentContentBlocks(
        _ blocks: [AgentMessageContentBlock],
        messageID: UUID,
        chatID: UUID
    ) {
        guard blocks.contains(where: {
            if case .visualization = $0 { return true }
            return false
        }),
        let sessionIndex = studySessions.firstIndex(where: { $0.id == chatID }),
        let messageIndex = studySessions[sessionIndex].messages.firstIndex(where: {
            $0.id == messageID
        }) else { return }
        studySessions[sessionIndex].messages[messageIndex].contentBlocks = blocks
        if activeStudySessionID == chatID {
            messages = studySessions[sessionIndex].messages
        }
    }

    private func removeAgentMessage(_ messageID: UUID, from chatID: UUID) {
        guard let sessionIndex = studySessions.firstIndex(where: { $0.id == chatID }) else {
            return
        }
        studySessions[sessionIndex].messages.removeAll { $0.id == messageID }
        selectionAskThreads.indices.forEach {
            selectionAskThreads[$0].messageIDs.removeAll { $0 == messageID }
        }
        if activeStudySessionID == chatID {
            messages = studySessions[sessionIndex].messages
        }
        save()
    }

    private func currentAgentVisualizationBlocks(
        _ blocks: [AgentMessageContentBlock]
    ) -> [AgentMessageContentBlock] {
        var result: [AgentMessageContentBlock] = []
        for block in blocks {
            if case let .visualization(fragment) = block,
               agentVisualizationIDsUpdatingHistory.contains(fragment.id) {
                continue
            }
            if case let .text(text) = block,
               case let .text(previous)? = result.last {
                result[result.count - 1] = .text(previous + text)
            } else {
                result.append(block)
            }
        }
        return result
    }

    private func appOwnedFilesDirectory() -> URL {
        let directory = workspaceDirectory.appendingPathComponent("Files", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func safeFileStem(_ value: String) -> String {
        MarkdownAttachmentStore.safeFileStem(value, fallback: ui("未命名", "Untitled"), limit: 80)
    }


    @discardableResult
    private func resolvePersistedImportedFileBookmarks() -> Bool {
        var changed = false
        for itemID in importedItems.map(\.id) {
            guard let index = importedItems.firstIndex(where: { $0.id == itemID }) else {
                continue
            }
            if resolveTrackedImportedFile(at: index).changed { changed = true }
        }
        return changed
    }

    func resolveTrackedImportedFile(at index: Int) -> (url: URL?, changed: Bool) {
        guard importedItems.indices.contains(index) else { return (nil, false) }
        if case .courseOwned(let courseID, _) = importedItems[index].storage {
            return resolveCourseOwnedFile(at: index, ownerCourseID: courseID)
        }
        return forgetGoneImportedItem(at: index)
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
            return forgetGoneImportedItem(at: index)
        }

        guard let identity = importedFileIdentityResolver(candidate) else {
            return forgetGoneImportedItem(at: index)
        }
        // identity 只用于尽力找回、永不用于拒绝（存储简化红线）：课程内文件
        // 以课程相对路径为准，路径下文件可读即接受。identity 不一致（iCloud
        // 驱逐重下换 inode、APFS 卷号漂移等）时沿用既有自愈逻辑刷新记录，
        // 与 applyCourseFileObservations 的对账语义一致，最多记一条日志。
        if importedItems[index].importedFileIdentity.map({ $0 != identity }) ?? false
            || courseItemMemberships[membershipIndex].entryIdentity.map({ $0 != identity }) ?? false {
            NSLog(
                "WeiBei: course-owned file identity drifted at %@; refreshed stored identity instead of refusing",
                candidate.path
            )
        }

        var changed = false
        if importedItems[index].urlPath != candidate.path
            || importedItems[index].title != candidate.deletingPathExtension().lastPathComponent
            || importedItems[index].subtitle != candidate.lastPathComponent
            || importedItems[index].kind != StudyItemKind.detect(from: candidate)
            || importedItems[index].importedFileIdentity != identity {
            importedItems[index].urlPath = candidate.path
            importedItems[index].title = candidate.deletingPathExtension().lastPathComponent
            importedItems[index].subtitle = candidate.lastPathComponent
            importedItems[index].kind = StudyItemKind.detect(from: candidate)
            importedItems[index].importedFileIdentity = identity
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
        let itemIDs = importedItems.compactMap { item -> String? in
            guard case .courseOwned(let ownerCourseID, _) = item.storage,
                  ownerCourseID == courseID else {
                return nil
            }
            return item.id
        }
        for itemID in itemIDs {
            guard let index = importedItems.firstIndex(where: { $0.id == itemID }) else {
                continue
            }
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
        if let libraryRoot = courseLibraryRootURL {
            try? await ensureCommonContentDirectories(at: libraryRoot)
            discoverTopLevelCourseFolders()
        }
        if await reconcileSharedFilesNow() {
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
            guard case .common(let relativePath) = importedItems[index].storage,
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
                showTransientNoteStatus(ui(
                    "通用资料中已有同名文件“\(newURL.lastPathComponent)”，旧共享文稿已保留。",
                    "A same-named common material already exists. The legacy shared file was kept."
                ))
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
            importedItems[index].storage = .common(
                relativePath:
                    "\(CourseOwnedFileRole.material.commonDirectoryName)/\(newURL.lastPathComponent)"
            )
            importedItems[index].urlPath = newURL.path
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
            if case .common(let relativePath) = importedItems[index].storage,
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
                  case .common(let relativePath) = importedItems[itemIndex].storage,
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

        var goneSharedIDs: [String] = []
        for itemID in itemIDs {
            guard let itemIndex = itemIndexByID[itemID],
                  let observationIndex = observationIndexByItemID[itemID] else {
                if itemIndexByID[itemID] != nil {
                    goneSharedIDs.append(itemID)
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
                nextItem.importedFileIdentity = observation.identity
                nextItem.storage = .common(
                    relativePath:
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
                if keepUnavailableImportedItem(at: itemIndex).changed {
                    changed = true
                }
            }
        }
        if forgetGoneImportedItems(ids: goneSharedIDs) {
            changed = true
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
                    isSample: false,
                    isNotebookNote: isNote,
                    storage: .common(
                        relativePath:
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
            guard case .common(let relativePath) = item.storage,
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
            // 纯归属兜底登记（无课程内链接条目）没有可对账的链接，
            // 不参与链接对账，直接保留。
            guard membership.courseRelativePath != nil
                    || membership.entryIdentity != nil else {
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
            guard case .courseOwned(let ownerCourseID, _) = importedItems[index].storage,
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

        var goneIDs: [String] = []
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
                if let relativePath = membership.courseRelativePath,
                   snapshot.preservesExistingRecord(at: relativePath) {
                    continue
                }
                goneIDs.append(itemID)
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
                    if keepUnavailableImportedItem(at: itemIndex).changed {
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
        if forgetGoneImportedItems(ids: goneIDs) {
            changed = true
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
                isSample: false,
                isNotebookNote: observation.isNote,
                storage: .courseOwned(
                    ownerCourseID: courseID,
                    relativePath: observation.relativePath
                ),
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
        // Detached + 每次 weak self：避免强引用拉长 store 生命周期，
        // 也避免 XCTest 把析构 cancel 记成用例失败。
        courseReconciliationTask = Task.detached(priority: .utility) {
            [weak self] in
            guard !Task.isCancelled else { return }
            await self?.reconcileCourseFilesNow()
            guard !Task.isCancelled else { return }
            // P0：先跑分叉修复（会丢弃/写回草稿），再跑 retry——顺序不能反，
            // 否则 retry 会把「读盘失败回退的模板草稿」直接盖回磁盘。
            await self?.repairDivergedNotebookNotesIfNeeded()
            guard !Task.isCancelled else { return }
            await self?.retryRestoredPendingNoteWrites()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.reconcileCourseFilesNow()
            }
        }
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
              case .courseOwned(let courseID, _) = item.storage,
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
    func refreshImportedFileTracking(itemID: String, url: URL) -> StudyItem? {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }),
              let identity = importedFileIdentityResolver(url) else {
            return nil
        }
        if case .courseOwned(let ownerCourseID, _) = importedItems[index].storage {
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
        importedItems[index].title = standardizedURL.deletingPathExtension().lastPathComponent
        importedItems[index].subtitle = standardizedURL.lastPathComponent
        importedItems[index].kind = StudyItemKind.detect(from: standardizedURL)
        return importedItems[index]
    }

    private func fileURLForImportedItem(_ item: StudyItem) -> URL? {
        resolvedLibraryURL(for: item)
    }

    private func rebuildCourseMembershipsFromStorage() {
        var memberships = courseItemMemberships
        for item in importedItems {
            guard case .courseOwned(let courseID, let relativePath) = item.storage,
                  !relativePath.isEmpty else {
                continue
            }
            if let index = memberships.firstIndex(where: {
                $0.courseID == courseID && $0.itemID == item.id
            }) {
                if memberships[index].courseRelativePath == nil {
                    memberships[index].courseRelativePath = relativePath
                }
            } else {
                memberships.append(
                    CourseItemMembership(
                        courseID: courseID,
                        itemID: item.id,
                        courseRelativePath: relativePath
                    )
                )
            }
        }
        courseItemMemberships = memberships
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
                ?? fileURLForImportedItem(item).flatMap(importedFileIdentityResolver)
            if item.importedFileIdentity != resolvedIdentity {
                item.importedFileIdentity = resolvedIdentity
                changed = true
            }
            let isManagedByCourseLibrary: Bool = {
                switch item.storage {
                case .courseOwned, .common:
                    return true
                case .bundledSample:
                    return false
                }
            }()
            _ = isManagedByCourseLibrary

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

    func replaceItemIDEverywhere(_ oldID: String, with newID: String) {
        guard oldID != newID else { return }

        if let oldNote = notesByItemID[oldID] {
            setNoteDraft(nil, for: oldID)
            if notesByItemID[newID] == nil {
                setNoteDraft(oldNote, for: newID)
            }
        }
        if let pendingWrite = pendingNoteWritesByItemID.removeValue(forKey: oldID),
           pendingNoteWritesByItemID[newID] == nil {
            pendingNoteWritesByItemID[newID] = pendingWrite
        }
        if let backingDigest = noteBackingContentDigestsByItemID.removeValue(forKey: oldID),
           noteBackingContentDigestsByItemID[newID] == nil {
            noteBackingContentDigestsByItemID[newID] = backingDigest
        }
        if let selfDigest = lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: oldID),
           lastSelfWrittenNoteDigestsByItemID[newID] == nil {
            lastSelfWrittenNoteDigestsByItemID[newID] = selfDigest
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

    private func clearWorkspaceSaveError() {
        consecutiveWorkspaceSaveFailures = 0
        if workspaceSaveError != nil {
            workspaceSaveError = nil
        }
    }

    /// S5：连续 3 次写盘失败才写入 workspaceSaveError（可点重试）；此前静默。
    /// 安全自检仍立即暴露，便于断言注入的单次失败。
    private func reportWorkspaceSaveFailure(_ message: String) {
        consecutiveWorkspaceSaveFailures += 1
        // 保存失败连续 3 次才上横幅，但每次都落日志——删除、退出等下游
        // 操作会因保存失败被拒绝，没有日志就完全无法事后定位。
        appendWorkspaceSaveFailureLog(message)
        if WeiBeiSafetyTestMode.isEnabled
            || consecutiveWorkspaceSaveFailures >= 3 {
            workspaceSaveError = message
        }
    }

    private func appendWorkspaceSaveFailureLog(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = storageURL.deletingLastPathComponent()
            .appendingPathComponent("weibei-save-errors.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    func showTransientNoteStatus(_ message: String) {
        // S5: sole user-visible note feedback channel (auto-expires).
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
                // 有草稿时不覆盖编辑器；无草稿则静默采用磁盘内容。
                if notesByItemID[itemID] != nil {
                    if activeNoteItemID == itemID {
                    }
                } else {
                    // 静默采纳磁盘：同步备份基线，避免后续自写误备份自身已采纳内容。
                    lastSelfWrittenNoteDigestsByItemID[itemID] =
                        result.snapshot.sha256
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
            return defaultNote(for: nil)
        }
        // 草稿优先：写回失败或文件不可达时 notesByItemID 保存最新编辑，不弹冲突。
        if item.editsBackingMarkdownFile, let cached = notesByItemID[item.id] {
            if case .courseOwned = item.storage {
                scheduleCourseNoteLoad(item)
            }
            return cleanLegacyPlaceholder(cached)
        }
        guard item.editsBackingMarkdownFile, let url = item.url else {
            if item.editsBackingMarkdownFile, notesByItemID[item.id] == nil {
                // P0 降级标记：有背书文件但定位不到，展示的是模板而非正文；
                // 留痕让写回守卫拒绝把模板盖回磁盘。
                setNoteFileError(
                    ui(
                        "无法定位笔记文件，正文展示已降级为模板；已暂停自动写回以保护磁盘内容。",
                        "The note file could not be located, so a template is shown instead of the note body. Automatic write-back is paused to protect the on-disk content."
                    ),
                    for: item.id
                )
            }
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
        if case .courseOwned = item.storage {
            if let loaded = loadedCourseNoteTextByItemID[item.id] {
                return loaded
            }
            scheduleCourseNoteLoad(item)
            return cleanLegacyPlaceholder(
                notesByItemID[item.id] ?? defaultNote(for: item)
            )
        }
        do {
            let data = try Data(contentsOf: url)
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            let digest = Self.noteContentDigest(data)
            noteBackingContentDigestsByItemID[item.id] = digest
            // 无草稿同步读盘：采纳磁盘为当前基线。
            lastSelfWrittenNoteDigestsByItemID[item.id] = digest
            // P0：读盘成功即自愈降级标记，恢复后续正常写回。
            setNoteFileError(nil, for: item.id)
            return cleanLegacyPlaceholder(markdown)
        } catch {
            if notesByItemID[item.id] == nil {
                // P0 降级标记：读盘失败且无草稿，展示的是模板而非正文。
                setNoteFileError(
                    ui(
                        "无法读取笔记文件，正文展示已降级为模板；已暂停自动写回以保护磁盘内容。",
                        "The note file could not be read, so a template is shown instead of the note body. Automatic write-back is paused to protect the on-disk content."
                    ),
                    for: item.id
                )
            }
            showTransientNoteStatus(ui("无法读取原 Markdown：\(url.lastPathComponent)", "Could not read original Markdown: \(url.lastPathComponent)"))
            return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))
        }
    }


    /// 从当前活动笔记的真实 Markdown 路径刷新。
    /// 持续监听不属于产品承诺；选择笔记或应用重新激活时读盘即可。
    func refreshActiveNoteFromBackingFile() {
        guard let item = activeNoteItem,
              item.editsBackingMarkdownFile,
              let url = item.url,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let itemID = item.id
        // 失焦会先冲刷输入。若仍有草稿或写入任务，说明落盘尚未完成，
        // 继续保留本地内容，不用一次刷新制造数据丢失。
        guard stagedNoteDraft?.itemID != itemID,
              notesByItemID[itemID] == nil,
              pendingNotePersistenceByItemID[itemID] == nil,
              !courseNoteWritesInFlight.contains(itemID),
              courseNoteWriteTasksByItemID[itemID] == nil else {
            return
        }

        if case .courseOwned(let courseID, _) = item.storage,
           let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }) {
            // 外部编辑器常用原子替换保存，inode 会变；课程内文件以相对路径
            // 为准，先沿用既有解析逻辑刷新身份，再交给后台读取。
            guard resolveCourseOwnedFile(
                at: itemIndex,
                ownerCourseID: courseID
            ).url != nil else {
                return
            }
            courseNoteLoadGenerationByItemID[itemID, default: 0] &+= 1
            courseNoteLoadTasksByItemID[itemID]?.cancel()
            courseNoteLoadTasksByItemID[itemID] = nil
            loadedCourseNoteTextByItemID.removeValue(forKey: itemID)
            scheduleCourseNoteLoad(importedItems[itemIndex])
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard let markdown = String(data: data, encoding: .utf8) else {
                return
            }
            let diskDigest = Self.noteContentDigest(data)
            if diskDigest == noteBackingContentDigestsByItemID[itemID],
               diskDigest == Self.noteContentDigest(Data(noteText.utf8)) {
                return
            }
            noteText = cleanLegacyPlaceholder(markdown)
            noteBackingContentDigestsByItemID[itemID] = diskDigest
            // 外部改动且无脏输入：静默采纳磁盘，同步备份基线。
            lastSelfWrittenNoteDigestsByItemID[itemID] = diskDigest
            setNoteDraft(nil, for: itemID)
            loadedCourseNoteTextByItemID[itemID] = noteText
            setNoteFileError(nil, for: itemID)
        } catch {
            // 静默：读失败不打扰用户。
        }
    }


    private func refreshCourseOwnedNoteMetadataAfterWrite(
        itemID: String,
        markdown: String,
        url: URL
    ) {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }),
              case .courseOwned = importedItems[index].storage else {
            return
        }
        let writtenDigest = Self.noteContentDigest(Data(markdown.utf8))
        if importedItems[index].contentDigest != writtenDigest {
            importedItems[index].contentRevision &+= 1
        }
        importedItems[index].contentDigest = writtenDigest
        if let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .documentIdentifierKey,
        ]) {
            if let size = values.fileSize {
                importedItems[index].fileByteCount = UInt64(size)
            }
            if let modified = values.contentModificationDate {
                let nanoseconds = modified.timeIntervalSince1970 * 1_000_000_000
                importedItems[index].fileModificationTimeNanoseconds =
                    nanoseconds.isFinite ? Int64(nanoseconds) : nil
            }
            if let membershipIndex = courseItemMemberships.firstIndex(
                where: { $0.itemID == itemID }
            ) {
                courseItemMemberships[membershipIndex].documentIdentifier =
                    values.documentIdentifier.flatMap {
                        $0 >= 0 ? UInt64($0) : nil
                    }
            }
        }
        if let identity = importedFileIdentityResolver(url) {
            importedItems[index].importedFileIdentity = identity
            if let membershipIndex = courseItemMemberships.firstIndex(
                where: { $0.itemID == itemID }
            ) {
                courseItemMemberships[membershipIndex].entryIdentity = identity
            }
        }
        importedItems[index].urlPath = url.path
        importedItems[index].title =
            url.deletingPathExtension().lastPathComponent
        importedItems[index].subtitle = url.lastPathComponent
        importedItems[index].kind = StudyItemKind.detect(from: url)
        noteBackingContentDigestsByItemID[itemID] = writtenDigest
        lastSelfWrittenNoteDigestsByItemID[itemID] = writtenDigest
        loadedCourseNoteTextByItemID[itemID] =
            cleanLegacyPlaceholder(markdown)
        courseDocumentSearchIndex.schedule([importedItems[index]])
    }

    func persistCourseOwnedNote(
        _ markdown: String,
        itemID: String
    ) {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }),
              importedItems[index].isNotebookNote,
              case .courseOwned = importedItems[index].storage,
              let url = importedItems[index].url else {
            retainUnreachableNoteDraft(markdown, itemID: itemID)
            save()
            return
        }
        // 用上次成功写入 digest 做备份判定（不是冲突关卡）。
        if noteBackingContentDigestsByItemID[itemID] == nil,
           let digest = importedItems[index].contentDigest {
            noteBackingContentDigestsByItemID[itemID] = digest
        }
        let wrote = writeNoteMarkdownTriple(markdown, itemID: itemID, url: url)
        if wrote {
            refreshCourseOwnedNoteMetadataAfterWrite(
                itemID: itemID,
                markdown: markdown,
                url: url
            )
            lastCourseNoteWriteRanOnMainThread = true
        }
        save()
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
        var memberships = courseItemMemberships.filter { $0.courseID == courseID }
        for item in importedItems {
            guard case .courseOwned(let owner, let path) = item.storage,
                  owner == courseID, !path.isEmpty,
                  !memberships.contains(where: { $0.itemID == item.id }) else { continue }
            memberships.append(CourseItemMembership(
                courseID: courseID, itemID: item.id, courseRelativePath: path
            ))
        }
        memberships.sort {
            ($0.courseRelativePath ?? "").localizedStandardCompare(
                $1.courseRelativePath ?? ""
            ) == .orderedAscending
        }
        var portableItems: [CoursePortableItem] = []
        for membership in memberships {
            guard let item = importedItems.first(where: {
                $0.id == membership.itemID
            }) else {
                throw CoursePortableStateError.missingCourseItem
            }
            guard let relativePath = membership.courseRelativePath else {
                // 纯归属兜底登记（链接进课程目录失败时写入）没有课程内链接
                // 条目，可携带状态无法表示；跳过它而不是让整次保存失败。
                if case .common = item.storage { continue }
                throw CoursePortableStateError.missingCourseItem
            }
            let storage: CoursePortableItemStorage
            switch item.storage {
            case .courseOwned(let ownerCourseID, _) where ownerCourseID == courseID:
                storage = .courseOwned
            case let .common(sharedRelativePath):
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
        // C2：草稿以 notesByItemID 为准（写回失败会清 pending 但留 notes）；
        // baseline 有 pending 则取，无则 nil。
        let drafts = noteItemIDs.sorted().compactMap {
            itemID -> CoursePortableNoteDraft? in
            guard let markdown = notesByItemID[itemID] else {
                return nil
            }
            return CoursePortableNoteDraft(
                itemID: itemID,
                markdown: markdown,
                baselineContentDigest: pendingNoteWritesByItemID[itemID]?
                    .baselineContentDigest
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
                let localItemIDs = portableItemIDs(
                    for: courseID, memberships: courseItemMemberships, items: importedItems
                )
                if knownRevision != nil,
                   !localItemIDs.isEmpty,
                   !localItemIDs.isSubset(of: Set(state.items.map(\.itemID))) {
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.remove(courseID)
                    changed = true
                    continue
                }
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
                        reportWorkspaceSaveFailure(ui(
                            "“\(course(withID: courseID)?.title ?? "课程")”的本机内容与课程文件夹首次建立可携带基线时不一致，魏碑已保留两边并停止自动覆盖。",
                            "The local course content did not match the course folder while establishing its first portable baseline. WeiBei preserved both sides and stopped automatic overwrites."
                        ))
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
                    // S3：无基线时静默标记脏，不抛冲突。
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.insert(courseID)
                    needsPortableCourseStateBootstrap = true
                    changed = true
                    continue
                }
                if dirtyPortableCourseIDs.contains(courseID) {
                    guard state.revision == knownRevision,
                          knownDigest == diskDigest else {
                        blockedPortableCourseIDs.insert(courseID)
                        // S3：不写常驻 workspaceSaveError 横幅。
                        continue
                    }
                    coursePortableStateRevisions[courseID] =
                        max(knownRevision, state.revision)
                    needsPortableCourseStateBootstrap = true
                    continue
                }
                guard state.revision >= knownRevision else {
                    // 磁盘更旧：保留本机，静默。
                    continue
                }
                if state.revision == knownRevision {
                    if knownDigest != diskDigest {
                        // 同 revision 不同 digest：标记阻塞，不自动覆盖。
                        blockedPortableCourseIDs.insert(courseID)
                        dirtyPortableCourseIDs.insert(courseID)
                        needsPortableCourseStateBootstrap = true
                        changed = true
                    }
                    // Matching revision is already the local baseline. Replaying it
                    // would wipe newer workspace-only links if the snapshot is stale.
                    continue
                }
                try applyCoursePortableState(state, courseID: courseID)
                coursePortableStateRevisions[courseID] = state.revision
                coursePortableStateDigests[courseID] = diskDigest
                changed = true
            } catch {
                // S3：读取失败静默阻塞，不写常驻错误横幅。
                blockedPortableCourseIDs.insert(courseID)
                dirtyPortableCourseIDs.insert(courseID)
                needsPortableCourseStateBootstrap = true
                changed = true
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
        let localItemIDs = portableItemIDs(
            for: courseID, memberships: courseItemMemberships, items: importedItems
        )
        if !localItemIDs.isEmpty, !localItemIDs.isSubset(of: Set(state.items.map(\.itemID))) {
            dirtyPortableCourseIDs.insert(courseID)
            return
        }
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
        // 纯归属兜底登记（无课程内链接条目）无法写进可携带状态；重放磁盘
        // 快照时保留这些归属与其共享条目，不随快照一起抹掉。
        let pathlessMemberships = previousMemberships.filter {
            $0.courseRelativePath == nil
        }
        let pathlessItemIDs = Set(pathlessMemberships.map(\.itemID))
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
                storage = .courseOwned(
                    ownerCourseID: courseID,
                    relativePath: portable.courseRelativePath
                )
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
                storage = .common(relativePath: sharedRelativePath)
                let existingBelongsToKnownCourse = existing.map { item in
                    if case .common = item.storage { return true }
                    return previousItemIDs.contains(item.id)
                        || otherCourseItemIDs.contains(item.id)
                } ?? false
                let existingIsCurrentCanonical: Bool
                if let existing, case let .common(existingPath) = existing.storage,
                   existingPath == sharedRelativePath {
                    existingIsCurrentCanonical = true
                } else if existingBelongsToKnownCourse,
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
                    guard case let .common(existingSharedPath) =
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
                && !pathlessItemIDs.contains(item.id)
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
        for membership in pathlessMemberships
        where !restoredMemberships.contains(where: {
            $0.itemID == membership.itemID
        }) {
            courseItemMemberships.append(membership)
        }

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
                && !pathlessItemIDs.contains($0.noteItemID)
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
        // C2：本地有草稿的条目一律保留——未落盘输入永远优先于快照重放。
        for itemID in previousNoteIDs.union(restoredNoteIDs) {
            if notesByItemID[itemID] != nil {
                continue
            }
            setNoteDraft(nil, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
            lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: itemID)
        }
        for item in state.items where item.isNotebookNote {
            // 本地草稿笔记：不覆盖其备份基线；其余用 state 内容 digest 回填。
            if notesByItemID[item.itemID] != nil {
                continue
            }
            noteBackingContentDigestsByItemID[item.itemID] =
                item.contentDigest
            if let digest = item.contentDigest {
                lastSelfWrittenNoteDigestsByItemID[item.itemID] = digest
            }
        }
        for draft in state.pendingNoteDrafts {
            // state 中的 draft 仅在本地无草稿时回填。
            if notesByItemID[draft.itemID] != nil {
                continue
            }
            setNoteDraft(draft.markdown, for: draft.itemID)
            pendingNoteWritesByItemID[draft.itemID] =
                PendingNoteWriteState(
                    baselineContentDigest: draft.baselineContentDigest
                )
        }
        rebuildCourseMembershipsFromStorage()
        refreshRuntimeItemURLs()
    }

    @discardableResult
    private func persistCoursePortableStates(
        courseIDs requestedCourseIDs: Set<UUID>? = nil,
        requiring requiredCourseIDs: Set<UUID> = []
    ) throws -> CoursePortableStateCommit {
        let courseIDs = requestedCourseIDs ?? Set(courses.map(\.id))
        let previousRevisions = coursePortableStateRevisions
        let previousDigests = coursePortableStateDigests
        let previousDirty = dirtyPortableCourseIDs
        let previousBlocked = blockedPortableCourseIDs
        let previousOversized = oversizedPortableCourseIDs
        let previousNeedsBootstrap = needsPortableCourseStateBootstrap
        var committedWrites: [CoursePortableStateWriteRecord] = []
        var conflictedCourseIDs = Set<UUID>()
        var durablePortableCourseIDs = Set<UUID>()
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
                            return item.storage == .common(relativePath: "")
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
                if blockedPortableCourseIDs.contains(courseID),
                   !(dirtyPortableCourseIDs.contains(courseID) && knownRevision != nil) {
                    if knownDigest != payloadDigest {
                        dirtyPortableCourseIDs.insert(courseID)
                    }
                    continue
                }
                if knownDigest == payloadDigest, stateExists {
                    if requiredCourseIDs.contains(courseID) {
                        guard let diskState = try? readCoursePortableState(
                            at: stateURL, expectedCourseID: courseID
                        ),
                        diskState.revision == currentRevision,
                        (try? coursePortableStatePayloadDigest(diskState)) == knownDigest else {
                            dirtyPortableCourseIDs.insert(courseID)
                            blockedPortableCourseIDs.insert(courseID)
                            continue
                        }
                    }
                    dirtyPortableCourseIDs.remove(courseID)
                    durablePortableCourseIDs.insert(courseID)
                    continue
                }
                if stateExists,
                   !(dirtyPortableCourseIDs.contains(courseID) && knownRevision != nil) {
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
                    // S3：写冲突静默记入 conflicted/dirty/blocked，不抛拒绝。
                    conflictedCourseIDs.insert(courseID)
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.insert(courseID)
                    needsPortableCourseStateBootstrap = true
                    continue
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
                durablePortableCourseIDs.insert(courseID)
            }
            let unresolvedRequiredCourseIDs = requiredCourseIDs.subtracting(durablePortableCourseIDs)
            if !unresolvedRequiredCourseIDs.isEmpty {
                // S3：未完成的可携带写回静默记 dirty/blocked，不抛拒绝。
                conflictedCourseIDs.formUnion(
                    unresolvedRequiredCourseIDs
                        .intersection(blockedPortableCourseIDs)
                        .subtracting(oversizedPortableCourseIDs)
                )
                dirtyPortableCourseIDs.formUnion(unresolvedRequiredCourseIDs)
                blockedPortableCourseIDs.formUnion(unresolvedRequiredCourseIDs)
                needsPortableCourseStateBootstrap = true
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
            if !conflictedCourseIDs.isEmpty {
                dirtyPortableCourseIDs.formUnion(conflictedCourseIDs)
                blockedPortableCourseIDs.formUnion(conflictedCourseIDs)
                needsPortableCourseStateBootstrap = true
            }
            if rollbackFailed {
                dirtyPortableCourseIDs.formUnion(conflictedCourseIDs)
                blockedPortableCourseIDs.formUnion(conflictedCourseIDs)
                needsPortableCourseStateBootstrap = true
            }
            // S3：可携带写回失败静默降级，不抛 stateConflict 拒绝整次保存。
            if !conflictedCourseIDs.isEmpty {
                needsPortableCourseStateBootstrap = true
            }
            return CoursePortableStateCommit(
                writes: [],
                previousRevisions: previousRevisions,
                previousDigests: previousDigests,
                previousDirtyCourseIDs: previousDirty,
                previousBlockedCourseIDs: previousBlocked,
                previousOversizedCourseIDs: previousOversized,
                previousNeedsBootstrap: previousNeedsBootstrap
            )
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
            // S3：回滚失败仅保留 blocked 标记，不抛拒绝。
            dirtyPortableCourseIDs.formUnion(commit.previousDirtyCourseIDs)
            blockedPortableCourseIDs.formUnion(commit.previousBlockedCourseIDs)
            needsPortableCourseStateBootstrap = true
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
        replaceNoteDrafts(snapshot.notesByItemID.mapValues(cleanLegacyPlaceholder))
        // 解码容忍旧 pendingNoteWrites；S2 写回路径不再依赖冲突状态机，启动时一次性迁移。
        if let persistedPendingNoteWrites = snapshot.pendingNoteWritesByItemID {
            pendingNoteWritesByItemID = persistedPendingNoteWrites
            // 保证草稿正文在 notesByItemID（迁移源）。
            for (itemID, _) in persistedPendingNoteWrites
            where notesByItemID[itemID] == nil {
                // 仅有 pending 标记无正文的旧数据：不伪造内容。
                continue
            }
        } else {
            pendingNoteWritesByItemID = [:]
        }
        noteBackingContentDigestsByItemID = snapshot.noteBackingContentDigestsByItemID ?? [:]
        selectedItemID = snapshot.selectedItemID
        activeNotebookItemID = snapshot.activeNotebookItemID
        courses = (snapshot.courses ?? []).map { course in
            var next = course
            next.sourceRootPath = nil
            next.sourceRootBookmarkData = nil
            return next
        }
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
        courseItemMemberships = snapshot.courseItemMemberships ?? []
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
                pendingNoteWritesByItemID: pendingNoteWritesByItemID.isEmpty
                    ? nil
                    : pendingNoteWritesByItemID,
                noteBackingContentDigestsByItemID:
                    noteBackingContentDigestsByItemID.isEmpty
                    ? nil
                    : noteBackingContentDigestsByItemID,
                selectedItemID: selectedItemID,
                activeNotebookItemID: activeNotebookItemID,
                courses: persistableCourses,
                courseItemMemberships: nil,
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
                guard case .courseOwned(let ownerCourseID, _) = item.storage,
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
                requiredPortableCourseIDs:
                    Set(activeCourseFileMutationCounts.keys)
                        .intersection(requestedCourseIDs),
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

    nonisolated private static func writeWorkspaceSnapshot(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    /// Schedule a coalesced workspace snapshot write. Verification keeps the
    /// legacy synchronous path; production saves use the file worker actor.
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
        checkpointActiveAgentStreamingText()
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = nil
        workspaceSaveGeneration &+= 1
        workspacePersistenceSkippingCourseIDs = []
#if DEBUG
        let shouldSaveImmediately = Self.mustSaveImmediately
            && !usesBackgroundWorkspacePersistenceForSelfCheck
#else
        let shouldSaveImmediately = Self.mustSaveImmediately
#endif
        if shouldSaveImmediately {
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
    func persistWorkspaceNow(
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
                clearWorkspaceSaveError()
                return true
            } catch {
                reportWorkspaceSaveFailure(ui(
                    "课程更改尚未写入磁盘：\(error.localizedDescription)",
                    "Course changes were not saved to disk: \(error.localizedDescription)"
                ))
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

    static var mustSaveImmediately: Bool {
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
            reportWorkspaceSaveFailure(ui(
                "课程可携带状态没有成功保存：\(error.localizedDescription)",
                "Portable course state was not saved: \(error.localizedDescription)"
            ))
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
            cleanupPersistedCourseTrashReceipts()
        }
        guard workspaceSaveGeneration == generation else {
            publishOutcome = "superseded"
            return true
        }
        if let failure = result.failure {
            switch failure {
            case .portableState(let detail):
                reportWorkspaceSaveFailure(ui(
                    "课程可携带状态没有成功保存：\(detail)",
                    "Portable course state was not saved: \(detail)"
                ))
            case .workspace(let detail):
                reportWorkspaceSaveFailure(ui(
                    "课程更改尚未写入磁盘：\(detail)",
                    "Course changes were not saved to disk: \(detail)"
                ))
            case .rollbackConflict:
                reportWorkspaceSaveFailure(ui(
                    "课程状态提交失败且检测到并发变更，魏碑已停止覆盖并保留现场。",
                    "The course state commit failed during a concurrent change. WeiBei stopped overwriting and preserved the files for recovery."
                ))
            case .stale:
                publishOutcome = "superseded"
                return true
            }
            return false
        }
        courseResumePoints = prepared.resumePoints
        if !oversizedPortableCourseIDs.isEmpty {
            reportWorkspaceSaveFailure(ui(
                "工作区内容已保存，但有课程的可携带状态超过 32 MB；课程文件夹中的原状态保持不变。请精简课程 Chat 或未写入草稿后重试。",
                "The workspace was saved, but a portable course state exceeds 32 MB. The state in the course folder was left unchanged. Reduce course chats or pending drafts, then retry."
            ))
        } else {
            clearWorkspaceSaveError()
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
            let requestedCourseIDs =
                persistedWorkspaceCourseIDs.intersection(
                    Set(courses.map(\.id))
                ).subtracting(skippingPortableCourseIDs)
            let portableCommit: CoursePortableStateCommit
            do {
                portableCommit = try persistCoursePortableStates(
                    courseIDs: requestedCourseIDs,
                    requiring: Set(activeCourseFileMutationCounts.keys)
                        .intersection(requestedCourseIDs)
                )
            } catch {
                reportWorkspaceSaveFailure(ui(
                    "课程可携带状态没有成功保存：\(error.localizedDescription)",
                    "Portable course state was not saved: \(error.localizedDescription)"
                ))
                return false
            }
            let persistedCourseResumePoints = sanitizedCourseResumePoints()
            let snapshot = PersistedWorkspace(
                importedItems: importedItems,
                notesByItemID: notesByItemID,
                pendingNoteWritesByItemID: pendingNoteWritesByItemID.isEmpty
                    ? nil
                    : pendingNoteWritesByItemID,
                noteBackingContentDigestsByItemID: noteBackingContentDigestsByItemID.isEmpty
                    ? nil
                    : noteBackingContentDigestsByItemID,
                selectedItemID: selectedItemID,
                activeNotebookItemID: activeNotebookItemID,
                courses: persistableCourses,
                courseItemMemberships: nil,
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
                cleanupPersistedCourseTrashReceipts()
                courseResumePoints = persistedCourseResumePoints
                if !oversizedPortableCourseIDs.isEmpty {
                    reportWorkspaceSaveFailure(ui(
                        "工作区内容已保存，但有课程的可携带状态超过 32 MB；课程文件夹中的原状态保持不变。请精简课程 Chat 或未写入草稿后重试。",
                        "The workspace was saved, but a portable course state exceeds 32 MB. The state in the course folder was left unchanged. Reduce course chats or pending drafts, then retry."
                    ))
                } else {
                    clearWorkspaceSaveError()
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
                    reportWorkspaceSaveFailure(ui(
                        "课程更改尚未写入磁盘：\(error.localizedDescription)",
                        "Course changes were not saved to disk: \(error.localizedDescription)"
                    ))
                } catch {
                    reportWorkspaceSaveFailure(ui(
                        "课程状态提交失败且检测到并发变更，魏碑已停止覆盖并保留现场。",
                        "The course state commit failed during a concurrent change. WeiBei stopped overwriting and preserved the files for recovery."
                    ))
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
