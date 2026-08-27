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

struct CourseProjectRebindProposal {
    let courseID: UUID
    let courseTitle: String
    let candidateRoot: URL
    let candidateRootIdentity: ImportedFileIdentity
    let expectedCourse: Course
    /// 只阻止确认期间的本机修改，不参与课程状态选边。
    let expectedLocalPayloadDigest: String
    let snapshot: CoursePortableAdoptionSnapshot
}

enum CourseFolderAdoptionOutcome {
    case opened(UUID)
    case requiresRebind(CourseProjectRebindProposal)
}

enum CourseProjectRebindError: LocalizedError {
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

enum CourseWorkspaceDestination: String, CaseIterable, Sendable {
    case hub
    case relations
    case materials
    case notes
    case sessions
    case memory
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
    case backupFailed
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
        case .backupFailed:
            "无法安全备份现有笔记，魏碑没有覆盖文件。待写内容仍在当前会话中，请重试。"
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

/// Isolated chrome state for the course drawer; kept off `WorkspaceStore`'s
/// `@Published` surface so open/close does not invalidate reader/agent/notes bodies.
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
    var courseLibraryRootPath: String?
    var courseLibraryRootIdentity: ImportedFileIdentity?
    var courseLibraryRootBookmarkData: Data?
    var courseLibraryRootURL: URL?
    var courseLibraryUnavailableReason: String?
    /// 资料库迁移进行中：写回、3 秒对账、课程笔记加载全部挂起（计划 §4.2）。
    @Published var libraryMigrationInFlight = false
    /// 外部文件缺席灰态（计划 §5 阶段2）：首缺席记时间，两个对账周期仍缺席才移除条目。
    var fileMissingSinceByItemID: [String: Date] = [:]
    @Published var courseItemMemberships: [CourseItemMembership] = [] {
        didSet {
            courseMembershipIndex = CourseItemMemberships(values: courseItemMemberships)
        }
    }
    @Published var activeCourseID: UUID?
    @Published var noteText = ""
    @Published var noteEditorRecoveryConflictsByItemID: [String: NoteEditorRecoveryConflict] = [:]
    var noteEditorConflictProbeDocumentID: String?
    var latestNoteEditorSnapshot: (documentID: String, digest: String, baseDigest: String, revision: UInt64)?
    let noteRecoveryStore = NoteRecoveryStore()
    lazy var noteEditingSession = NoteEditingSession(
        documentID: "",
        onSnapshotAccepted: { [weak self] snapshot in
            self?.acceptNoteEditorSnapshot(snapshot)
        }
    )
    @Published var agentDraft = ""
    @Published var messages: [AgentMessage] = []
    @Published var isAskingAgent = false
    @Published private(set) var isStoppingAgent = false
    @Published private(set) var isAgentSwitchConfirmationPresented = false
    let agentStreaming = AgentStreamingState()
    var agentStreamingUsesReducedMotion = false
    lazy var agentStreamingDisplayPump = AgentStreamingDisplayPump(hooks: .init(
        append: { [weak self] chunk in self?.agentStreaming.text.append(chunk) },
        replace: { [weak self] text in self?.agentStreaming.text = text },
        didDrain: { [weak self] in self?.finishAgentStreamingDisplay() }
    ))
    @Published var showLoadingIndicatorSamples = false
    /// Last failed user question for precise one-tap retry.
    @Published private(set) var lastFailedAgentQuestion: String?
    @Published private(set) var lastAgentFailureKind: AgentFailureKind?
    @Published private(set) var agentAuthenticationStatus = AgentAuthenticationStatus()
    @Published private(set) var latestAgentNoteProposal: StudyAgentNoteProposal?
    @Published private(set) var latestAgentLearningUpdate: StudyAgentLearningUpdate?
    @Published var noteSourceLinks: [NoteSourceLink] = [] {
        didSet {
            noteSourceRelationIndex = NoteSourceRelationIndex(links: noteSourceLinks)
        }
    }
    @Published var materialNotePairings: [String: String] = [:]
    @Published var noteMaterialPairings: [String: String] = [:]
    @Published private(set) var blankNoteDraftMaterialID: String?
    @Published var linkedSourcesPresented = false
    var studyLocationsByItemID: [String: StudyLocation] = [:]
    var studyLocationsByCourseID: [String: [String: StudyLocation]] = [:]
    var courseResumePoints: [CourseResumePoint] = []
    @Published var learningMemoryStates: [ScopedLearningMemoryState] = []
    var courseKnowledgeProfiles: [CourseKnowledgeProfile] = []
    @Published var studySessions: [StudySession] = []
    let sessionMessagePersistence = StudySessionMessagePersistence()
    @Published var activeStudySessionID: UUID? {
        didSet {
            if let chatID = agentStreaming.displayingChatID,
               activeStudySessionID != chatID {
                landAgentStreamingDisplayImmediately()
            }
        }
    }
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
                landAgentStreamingDisplayIfHidden()
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
    /// Reader viewport (HTML section / PDF page). Scroll commits must not auto-publish:
    /// every EnvironmentObject consumer would remasure and freeze main (sample 2026-08-01).
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
    @Published var layout: WorkspaceLayout = .documentAgentNotes {
        didSet { landAgentStreamingDisplayIfHidden() }
    }
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
                landAgentStreamingDisplayIfHidden()
            }
        }
    }
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
    /// 选区"记"留痕(原文标记渲染与回访;管理逻辑在 WorkspaceStore+SelectionRemark)。
    @Published var selectionRemarkRecords: [SelectionRemarkRecord] = []
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
    @Published var noteEditorCommand: NoteEditorCommand? {
        willSet {
            if let current = noteEditorCommand,
               current.id != newValue?.id,
               current.kind.isContentCommand,
               let tracked = trackedContentCommand(id: current.id),
               !tracked.isCoordinatorOwned {
                noteEditorCommandRejected(
                    current,
                    documentID: noteEditingSession.documentID
                )
            }
            guard let command = newValue,
                  command.kind.isContentCommand,
                  trackedContentCommand(id: command.id) == nil else { return }
            unresolvedContentCommands.append(
                TrackedNoteEditorCommand(
                    documentID: noteEditingSession.documentID,
                    command: command
                )
            )
        }
    }
    @Published private var unresolvedContentCommands: [TrackedNoteEditorCommand] = []
    /// Success / info banner for note create/switch — separate from errors so it auto-dismisses cleanly.
    @Published var transientNoteStatus: String?
    @Published private var noteSelectionTransitionState = NoteSelectionTransitionState.idle
    /// 卡死逃生:切换等待若长时间停在 .saving(如编辑器命令未回执、快照循环不收敛),
    /// 降级为失败态,让底部状态条的重试入口与新的切换恢复可用。只改状态,不动数据。
    private var noteSelectionWatchdogTask: Task<Void, Never>?
    /// 看门狗时长(秒),测试可调短。
    var noteSelectionWatchdogSeconds: TimeInterval = 8
    /// 契约3:内部故障静默自愈——被拒命令与失败切换在后台自动重试;
    /// 超过次数仍失败(基本等于真写不进盘)才升级为用户可见的"请重试"。
    private static let selfHealAttemptLimit = 3
    private var rejectedCommandSelfHealTask: Task<Void, Never>?
    private var rejectedCommandSelfHealAttempts = 0
    private var pendingSelectionSelfHealTask: Task<Void, Never>?
    private var pendingSelectionSelfHealAttempts = 0
    /// 自愈重试的基础间隔(秒),测试可调短。
    var noteSelectionSelfHealDelaySeconds: TimeInterval = 0.8
    private var pendingNoteSelection: PendingNoteSelection?
    /// Serious data-operation failures (note read/write/rename/restore/identity,
    /// security scope, course file move & rollback). Never auto-dismisses — only a
    /// user close or a newer important error replaces it.
    @Published var importantOperationError: String?
    /// 横幅的类型化身份,与 importantOperationError 并行记录,测试按语义断言而非比对文案。
    @Published var importantOperationNotice: ImportantOperationNotice?
    var transientNoteStatusGeneration = 0
    var transientNoteStatusTask: Task<Void, Never>?
    @Published private(set) var workspaceSaveFailure: WorkspaceSaveFailure?
    /// 展示兼容:界面与对话框仍按字符串消费保存失败文案。
    var workspaceSaveError: String? { workspaceSaveFailure?.message }
    @Published private(set) var courseFileOperationProgress: CourseFileOperationProgress?
    @Published var notebookCreationDraft: NotebookCreationDraft?
    @Published var notebookRenameDraft: NotebookRenameDraft?
    var notebookRenameInFlight = false
    @Published var modelName: String = ""
    @Published var agentProviderID: AgentProviderID = .openai
    @Published var agentBaseURL: String = ""
    @Published var agentAuthMethod: AgentAuthMethod = .apiKey
    @Published var agentCredentialProfiles: [AgentCredentialProfile] = AgentCredentialProfileStore.loadProfiles()
    @Published var activeAgentProfileID: UUID = AgentCredentialProfileStore.activeProfileID()
        ?? AgentCredentialProfileStore.loadProfiles().first?.id
        ?? AgentCredentialProfileStore.defaultProfile().id
    @Published var appearanceMode: WeiBeiAppearanceMode = .paper
    /// App-wide motion preference (system / reduce / full); resolved against the
    /// macOS switch by `WeiBeiMotionScope`. Persisted in UserDefaults, not workspace.json.
    @Published var motionPreference: WeiBeiMotionPreference = .system
    @Published var adaptImportedDocumentColors = true
    @Published var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    @Published var interfaceTextScale: WeiBeiTypography.TextScale = .standard
    @Published var courseWorkspacePresented = false
    @Published var courseWorkspaceCourseID: UUID?
    @Published var courseWorkspaceDestination: CourseWorkspaceDestination = .hub
    @Published var courseWorkspaceTargetItemID: String?
    @Published var backNavigationStack: [NavigationSnapshot] = []
    @Published var forwardNavigationStack: [NavigationSnapshot] = []

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
    /// 文件名跟随抬头的基线：上次由抬头体系登记/同步的文件名（不含扩展名）。
    /// 只有基线==当前文件名时才跟随抬头改名；对不上说明文件名被外部动过，
    /// 先登记、不动文件。内存态即可：重启丢基线只少一次自动改名，方向安全。
    var headingSyncedNoteStemByItemID: [String: String] = [:]
    var loadedCourseNoteTextByItemID: [String: String] = [:]
    var courseNoteLoadTasksByItemID: [String: Task<Void, Never>] = [:]
    var courseNoteLoadGenerationByItemID: [String: UInt64] = [:]
    var courseNoteWritesInFlight = Set<String>()
    var courseNoteWriteTasksByItemID: [String: Task<Void, Never>] = [:]
    private var blankNoteMaterializationTask: Task<Void, Never>?
    private var pendingBlankNoteText = ""
    var lastCourseNoteReadRanOnMainThread: Bool?
    var lastCourseNoteWriteRanOnMainThread: Bool?
    var lastCourseHomeSearchRanOnMainThread: Bool?
    var lastPortableAdoptionReadRanOnMainThread: Bool?
    var lastCourseRebindRootSearchRanOnMainThread: Bool?
    let workspaceDirectory: URL
    let storageURL: URL
    let importedFileIdentityResolver: (URL) -> ImportedFileIdentity?
    let courseRootBookmarkMaker: (URL) -> Data?
    let courseRootBookmarkResolver: (Data) -> CourseProjectResolvedBookmark?
    let courseSecurityScopeStarter: (URL) -> Bool
    let courseSecurityScopeStopper: (URL) -> Void
    let courseProjectMutationHook: (CourseProjectMutationStage) throws -> Void
    let notebookMarkdownReader: (URL) throws -> String
    let notebookMarkdownWriter: (String, URL) throws -> Void
    let noteBackupRootURL: URL
    let notebookFileMover: (URL, URL) throws -> Void
    let courseFileSourceRemover: @Sendable (URL) throws -> Void
    let contentSourceTrashMover: @Sendable (URL) throws -> URL
    private let workspaceSnapshotWriter:
        @Sendable (Data, URL) throws -> Void
    let coursePortableStateWriter:
        (
            Data,
            URL,
            ImportedFileIdentity,
            Data?,
            () throws -> Void
        ) throws -> Void
    let selectionAskThreadDefaults: UserDefaults
    let courseDocumentSearchIndex: CourseDocumentSearchIndex
    var activeAgentRequestID: UUID?
    var activeAgentReplyMessageID: UUID?
    var latestAgentStreamingText = ""
    private var lastAgentStreamingPublishNanoseconds: UInt64 = 0
    var agentReplyIDsThatDisplayedStreamingText: Set<UUID> = []
    private var agentVisualizationIDsUpdatingHistory: Set<String> = []
    var activeAgentReplyChatID: UUID?
    var agentRequestTask: Task<Void, Never>?
#if DEBUG
    private var capturesAgentRequestForSelfCheck = false
    private var selfCheckCapturedAgentRequest: StudyAgentRequest?
#endif
    var agentStopTask: Task<Void, Never>?
    private var pendingAgentSwitchTargetID: UUID?
    private var pendingAgentSwitchCourseID: UUID?
    private var agentDraftsBySessionID: [UUID: String] = [:]
    var pendingComposerDraft: String?
    /// Session-local identity of the one reusable, newly created empty Chat.
    /// Deliberately not persisted: reopening the App starts with a fresh empty Chat.
    private var freshlyCreatedEmptyStudySessionID: UUID?
    private var agentContextRevision: UInt64 = 0
    var coursePortableStateRevisions: [UUID: UInt64] = [:]
    var coursePortableStateDigests: [UUID: String] = [:]
    var dirtyPortableCourseIDs = Set<UUID>()
    var blockedPortableCourseIDs = Set<UUID>()
    var oversizedPortableCourseIDs = Set<UUID>()
    var persistedWorkspaceCourseIDs = Set<UUID>()
    var needsPortableCourseStateBootstrap = false
    @Published private var validatedAgentReplySourceIDs = Set<UUID>()
    private var lastAgentReplyContextRevision: UInt64?
    private var latestAgentLearningUpdateQuestion: String?
    private var isRestoringNavigation = false
    private var lastSelectionAttachmentDate: Date?
    private var lastSelectionUpdateDate: Date?
    private var pendingSelectionAttachmentTask: Task<Void, Never>?
    private var needsSelectionAskThreadsWorkspaceMigration = false
    private var shouldRemoveLegacySelectionAskThreadsAfterSave = false
    private var loadedSelectionAskThreadsFromWorkspaceSnapshot = false
    var recoveredInterruptedAgentReply = false
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
    var workspaceSaveGeneration: UInt64 = 0
    private var lastWorkspacePersistenceRanOnMainThread: Bool?
    private var courseHomePerformanceNavigationSpan: WeiBeiPerf.Span?
    private let workspaceSaveDebounceNanoseconds: UInt64 = 280_000_000
    var noteSourceLinksMigrationVersion = 0
    private var studySessionScopeMigrationVersion = 0
    private var learningMemoryScopeMigrationVersion = 0
    private var isRestoringCourseResumePoint = true
    private var legacyLearningMemoryEntries: [LearningMemoryEntry] = []
    private var legacyLearningMemoryRevision: UInt64 = 0
    private var noteSourceRelationIndex = NoteSourceRelationIndex(links: [])
    var courseMembershipIndex = CourseItemMemberships()
    private var courseWorkspaceReturnFocus: PaneFocus?
    var activeCourseSecurityScopes: [String: URL] = [:]
    var activeCourseSecurityScopeOwnerTokens: [String: UUID] = [:]
    var activeCourseRebindTokens: [UUID: UUID] = [:]
    var activeCourseRemovalTokens: [UUID: UUID] = [:]
    var activeCourseRemovalTransactionID: UUID?
    var pendingCourseTrashReceiptCleanups:
        [CourseTrashReceiptCleanup] = []
    var activeCourseFileMutationCounts: [UUID: Int] = [:]
    var activeItemFileMutationIDs = Set<String>()
    private var workspacePersistenceRemovingCourseID: UUID?
    private var workspaceRemovalCommitObserved = false
#if DEBUG
    var usesBackgroundWorkspacePersistenceForSelfCheck = false
#endif
    var resolvedCourseRootURLs: [UUID: URL] = [:]
    var courseRootUnavailableReasons: [UUID: String] = [:]
    let courseProjectFileWorker = CourseProjectFileWorker()
    var courseReconciliationTask: Task<Void, Never>?
    var courseReconciliationInFlight = false
    var lastCourseReconciliationLookupCount = 0

    var showRightPane: Bool {
        get { showNotes || showAgent }
        set {
            // Single paneState publish (notes+agent together).
            paneState.setRightPaneVisible(newValue)
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
        var showReaderSearch: Bool
        var readerSearch: String
        var readerLocationID: String?
        var readerLocationTitle: String?
        var readerPageIndex: Int
        var focusedPane: PaneFocus
        var threePaneOrder: [WorkspacePaneRole]
    }

    private enum NoteSelectionTransitionState: Equatable {
        case idle
        case saving
        case failed(NoteEditingSessionError)
        case persistenceFailed
    }

    private struct PendingNoteSelection {
        let apply: () -> Void
    }

    private struct TrackedNoteEditorCommand {
        let documentID: String
        let command: NoteEditorCommand
        var isCoordinatorOwned = false
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

    struct AgentHostToolSource: Sendable {
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

    struct AgentFileGrant: Sendable {
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

    struct AgentConversationTarget: Sendable {
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

    struct TransactionDirectoryFingerprint: Equatable {
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

    struct CreatedManagedCourseRoot {
        var root: URL
        var relativePath: String
        var identity: ImportedFileIdentity
        var fingerprint: TransactionDirectoryFingerprint
    }

    var lastUsableAgentAnswer: AgentMessage? {
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
        workspaceSnapshotWriter: @escaping @Sendable (Data, URL) throws -> Void = {
            try WorkspaceStore.writeWorkspaceSnapshot($0, to: $1)
        },
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
        if let motionPreferenceRaw = selectionAskThreadDefaults.string(
            forKey: WeiBeiMotionPreference.persistedDefaultsKey
        ), let persistedMotionPreference = WeiBeiMotionPreference(rawValue: motionPreferenceRaw) {
            motionPreference = persistedMotionPreference
        }
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
        let restoredPortableCourseStates = restorePortableCourseStates()
        rebuildCourseMembershipsFromStorage()
        refreshRuntimeItemURLs()
        WeiBeiThemeRuntime.mode = appearanceMode
        let resolvedImportedFileBookmarks = resolvePersistedImportedFileBookmarks()
        let migratedImportedItemIdentities = migrateLegacyImportedItemIdentities()
        // 空页启动（生产默认）时活跃选择随即被 resetPrimaryEntriesForLaunch 清空：
        // 此刻求值恢复出来的笔记正文，其降级错误会弹到用户永远看不到的界面上，
        // 形成「空白页+常驻误报横幅」。空页启动直接跳过这次求值。
        if !startsAtBlankEntries,
           resolvedImportedFileBookmarks || migratedImportedItemIdentities {
            noteText = noteText(for: activeNoteItem)
        }
        if startsAtBlankEntries {
            resetPrimaryEntriesForLaunch()
        }
        ensureActiveStudySession(preferFresh: startsAtBlankEntries)
        floatingSelectionPrompt = ui("当前选区", "Current selection")
        if selectedItemID != nil {
            restoreCurrentStudyLocation()
            recordCurrentStudyLocation(incrementVisit: false)
        }
        isRestoringCourseResumePoint = false
        let portableBootstrap = needsPortableCourseStateBootstrap
        let interruptedReply = recoveredInterruptedAgentReply
        let selectionAskMigration = needsSelectionAskThreadsWorkspaceMigration
        let runDeferredHousekeeping = { [weak self] in
            self?.completeDeferredLaunchHousekeeping(
                restoredCourseProjectRoots: restoredCourseProjectRoots,
                restoredPortableCourseStates: restoredPortableCourseStates,
                resolvedImportedFileBookmarks: resolvedImportedFileBookmarks,
                migratedImportedItemIdentities: migratedImportedItemIdentities,
                needsPortableCourseStateBootstrap: portableBootstrap,
                recoveredInterruptedAgentReply: interruptedReply,
                needsSelectionAskThreadsWorkspaceMigration: selectionAskMigration
            )
        }
        if WeiBeiSafetyTestMode.isEnabled {
            runDeferredHousekeeping()
        } else {
            Task { @MainActor in
                await Task.yield()
                runDeferredHousekeeping()
            }
        }
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
        importedItems.filter(\.isCourseMaterial)
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
        courseItems(in: courseID).filter(\.isCourseMaterial)
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
    func sanitizeCourseResumePoints() -> Bool {
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
                  session.hasChatHistory else {
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

    func courseRootURL(for courseID: UUID) -> URL? {
        resolvedCourseRootURLs[courseID]
    }

    func courseRootUnavailableReason(for courseID: UUID) -> String? {
        courseRootUnavailableReasons[courseID]
    }

    func removeItemRegistration(_ itemID: String) {
        fileMissingSinceByItemID.removeValue(forKey: itemID)
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
        selectionRemarkRecords.removeAll { $0.itemID == itemID }
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
        if blankNoteDraftMaterialID == itemID {
            blankNoteDraftMaterialID = nil
            pendingBlankNoteText = ""
        }
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
        orderedStudySessions.filter(\.hasChatHistory)
    }

    /// Non-empty Chats that have actually used this course.
    func sessionsTouchingCourse(_ courseID: UUID) -> [StudySession] {
        orderedStudySessions.filter {
            $0.hasChatHistory
                && $0.relatedCourseIDs.contains(courseID)
        }
    }

    /// Sessions that reference a specific material (and optionally other focus items).
    func sessionsTouchingMaterial(_ materialID: String, in courseID: UUID? = nil) -> [StudySession] {
        return orderedStudySessions.filter { session in
            guard session.hasChatHistory else { return false }
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
        return allItems.filter { linkedIDs.contains($0.id) && $0.isCourseMaterial }
    }

    var linkedSourceCount: Int {
        linkedSourcesForActiveNote.count
    }

    func contextualBrowserItems(
        _ kind: ContextualContentKind,
        courseID: UUID?
    ) -> [StudyItem] {
        allItems.filter { item in
            guard courseContextItemMatches(item, kind: kind) else {
                return false
            }
            if let courseID {
                return courseMembershipIndex.courseIDs(for: item.id)
                    .contains(courseID)
            }
            switch item.storage {
            case .common:
                return true
            case .courseOwned, .bundledSample:
                return false
            }
        }.sorted {
            displayTitle(for: $0).localizedStandardCompare(
                displayTitle(for: $1)
            ) == .orderedAscending
        }
    }

    /// One-pass course → visible-item counts for the contextual browser; replaces
    /// per-course full-library rescans that made opening stutter on large libraries.
    func contextualBrowserItemCounts(
        _ kind: ContextualContentKind
    ) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for item in allItems where courseContextItemMatches(item, kind: kind) {
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
            guard courseContextItemMatches(item, kind: kind) else { return }
            switch item.storage {
            case .common:
                count += 1
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
              courseContextItemMatches(item, kind: kind) else {
            return
        }
        switch kind {
        case .material:
            let noteID = activeNoteItem?.id
            selectMeasured(itemID: itemID, opensNotebook: false)
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
        guard materialID != noteID,
              item(withID: materialID)?.isCourseMaterial == true,
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
        orderedStudySessions.filter(\.hasChatHistory)
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

    @discardableResult
    func renameStudySession(_ id: UUID, title rawTitle: String) -> Bool {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let index = studySessions.firstIndex(where: { $0.id == id }),
              studySessions[index].title != title || !studySessions[index].titleSetByUser else { return false }
        studySessions[index].title = title
        studySessions[index].titleSetByUser = true
        studySessions[index].updatedAt = Date()
        save()
        return true
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
            agentDraft = ""; pendingComposerDraft = nil
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
        markStudySessionMessagesLoaded(session.id)
        activeStudySessionID = session.id
        freshlyCreatedEmptyStudySessionID = session.id
        messages = []
        agentDraft = ""; pendingComposerDraft = nil
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
        guard let session = loadStudySessionForActivation(id) else {
            return false
        }
        if id == activeStudySessionID {
            messages = session.messages
            return true
        }
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
        for courseID in session.relatedCourseIDs where session.hasChatHistory {
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
        forgetStudySessionMessages(id)
        studySessions.remove(at: index)
        if deletingActiveSession {
            activeStudySessionID = nil
            messages = []
            if let replacement = loadStudySessionForActivation(orderedStudySessions.first?.id) {
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

    func ensureActiveStudySession(preferFresh: Bool = false) {
        if !preferFresh,
           let session = loadStudySessionForActivation(activeStudySessionID) {
            messages = session.messages
            restoreAgentReplyState(from: session)
            return
        }
        if !preferFresh, let session = loadStudySessionForActivation(orderedStudySessions.first?.id) {
            activeStudySessionID = session.id
            messages = session.messages
            restoreAgentReplyState(from: session)
            return
        }
        let session = StudySession(title: ui("新学习会话", "New Study Session"))
        studySessions.append(session)
        markStudySessionMessagesLoaded(session.id)
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
        agentDraft = ""; pendingComposerDraft = nil
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

    func appendAgentMessage(_ message: AgentMessage) {
        if freshlyCreatedEmptyStudySessionID == activeStudySessionID {
            freshlyCreatedEmptyStudySessionID = nil
        }
        messages.append(message)
        syncActiveStudySession(titleSeed: message.role == .user ? message.text : nil)
        save()
    }

    @discardableResult
    func updateAgentMessage(
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

    func restoreAgentReplyState(from session: StudySession) {
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
        agentDraftsBySessionID[activeStudySessionID] = pendingComposerDraft ?? agentDraft
    }

    func restoreAgentDraft(for sessionID: UUID) {
        agentDraft = agentDraftsBySessionID[sessionID] ?? ""; pendingComposerDraft = agentDraft.isEmpty ? nil : agentDraft
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

    var agentReplyActionIDsInFlight = Set<UUID>()

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
        if let itemID = action.targetItemID,
           let item = allItems.first(where: { $0.id == itemID }) {
            return displayTitle(for: item)
        }
        if action.kind == .writeNote, action.targetItemID == nil {
            return ui("新建笔记", "New note")
        }
        return nil
    }

    func agentReplyActionSourceTitle(_ action: AgentReplyAction) -> String? {
        guard let itemID = action.sourceItemID,
              let item = allItems.first(where: { $0.id == itemID }) else {
            return nil
        }
        return displayTitle(for: item)
    }

    func cancelAgentReplyAction(messageID: UUID, actionID: UUID) async {
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
        // Never flushPendingWorkspaceSave() from this MainActor async path:
        // RunLoop-spin waiting for another MainActor Task deadlocks the UI.
        guard await flushPendingWorkspaceSaveAsync() else {
            await failAgentReplyAction(
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
            await confirmAgentRelationAction(messageID: messageID, snapshot: snapshot)
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
            await undoAgentRelationAction(messageID: messageID, snapshot: snapshot)
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
        guard !proposal.isEmpty else {
            await failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "笔记建议是空的。",
                    "The note proposal is empty."
                )
            )
            return
        }
        if action.targetItemID == nil {
            await confirmAgentNewCourseNoteAction(
                messageID: messageID,
                snapshot: snapshot,
                proposal: proposal
            )
            return
        }
        guard let targetItemID = action.targetItemID,
              let target = allItems.first(where: {
                  $0.id == targetItemID && $0.isNotebookNote
              }),
              item(targetItemID, belongsTo: snapshot.courseID) else {
            await failAgentReplyAction(
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
                    await failAgentReplyAction(
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
                    await failAgentReplyAction(
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
                await failAgentReplyAction(
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
            guard await flushPendingWorkspaceSaveAsync() else {
                await failAgentReplyAction(
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
            WeiBeiLog.workspace.error(
                "code=agent_note_action_read_failed action=write item=\(target.id, privacy: .private) underlying=\(WeiBeiLog.code(error), privacy: .public) detail=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
            )
            await failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "没有读取到目标笔记，因此没有写入；原笔记和这条建议都已保留。请确认笔记文件可访问后重试。",
                    "The target note could not be read, so nothing was written. The original note and this proposal are both preserved. Make sure the note file is accessible, then try again."
                )
            )
        }
    }

    private func confirmAgentNewCourseNoteAction(
        messageID: UUID,
        snapshot: (chatID: UUID, courseID: UUID?, action: AgentReplyAction),
        proposal: String
    ) async {
        guard let courseID = snapshot.courseID else {
            await failAgentReplyAction(
                messageID: messageID,
                actionID: snapshot.action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "当前没有可归属的课程，不能新建笔记。",
                    "This Chat has no course, so a new note cannot be created."
                )
            )
            return
        }
        let title = notebookTitle(fromProposedMarkdown: proposal)
        let fileStem = safeFileStem(title)
        let proposalDigest = Self.noteContentDigest(Data(proposal.utf8))
        if let existing = courseNoteMatchingFileStem(courseID: courseID, fileStem: fileStem),
           let current = try? await agentActionNoteMarkdown(existing),
           Self.noteContentDigest(Data(current.utf8)) == proposalDigest {
            await markAgentNewCourseNoteExecuted(
                messageID: messageID,
                snapshot: snapshot,
                proposal: proposal,
                itemID: existing.id
            )
            return
        }
        guard let itemID = await createCourseNotebookNote(
            courseID: courseID,
            title: title,
            markdown: proposal,
            revealInWorkspace: false,
            conflictResolution: .keepBoth(preferredFileName: nil),
            presentsError: false
        ) else {
            await failAgentReplyAction(
                messageID: messageID,
                actionID: snapshot.action.id,
                chatID: snapshot.chatID,
                message: workspaceSaveError ?? ui(
                    "笔记没有成功写入，建议内容已保留，可以重试。",
                    "The note was not written. The proposal was kept for retry."
                )
            )
            return
        }
        await markAgentNewCourseNoteExecuted(
            messageID: messageID,
            snapshot: snapshot,
            proposal: proposal,
            itemID: itemID
        )
    }

    private func markAgentNewCourseNoteExecuted(
        messageID: UUID,
        snapshot: (chatID: UUID, courseID: UUID?, action: AgentReplyAction),
        proposal: String,
        itemID: String
    ) async {
        updateAgentReplyAction(
            messageID: messageID,
            actionID: snapshot.action.id,
            chatID: snapshot.chatID
        ) {
            $0.proposedMarkdown = proposal
            $0.targetItemID = itemID
            $0.baselineContentDigest = Self.noteContentDigest(Data())
            $0.resultContentDigest = Self.noteContentDigest(Data(proposal.utf8))
            $0.state = .executed
            $0.failureMessage = nil
        }
        guard await flushPendingWorkspaceSaveAsync() else {
            await failAgentReplyAction(
                messageID: messageID,
                actionID: snapshot.action.id,
                chatID: snapshot.chatID,
                message: workspaceSaveError ?? ui(
                    "笔记已写入，但动作状态没有成功保存；可以安全重试。",
                    "The note was written, but the action status was not saved."
                )
            )
            return
        }
    }

    private func courseNoteMatchingFileStem(courseID: UUID, fileStem: String) -> StudyItem? {
        let fileName = "\(fileStem).md"
        let notes = courseNotes(in: courseID)
        if let byFileName = notes.first(where: { item in
            item.subtitle.compare(fileName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                || (item.urlPath.map {
                    URL(fileURLWithPath: $0).lastPathComponent
                        .compare(fileName, options: [.caseInsensitive, .diacriticInsensitive])
                } == .orderedSame)
        }) {
            return byFileName
        }
        return notes.first(where: {
            $0.title.compare(fileStem, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        })
    }

    private func notebookTitle(fromProposedMarkdown markdown: String) -> String {
        for line in markdown.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.drop(while: { $0 == "#" || $0.isWhitespace })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    return String(title.prefix(36))
                }
            }
        }
        let first = markdown
            .split(whereSeparator: \.isNewline)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if !first.isEmpty {
            return String(first.prefix(36))
        }
        return ui("整理建议", "Organization suggestion")
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
                guard await flushPendingWorkspaceSaveAsync() else {
                    await failAgentReplyAction(
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
                await failAgentReplyAction(
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
            guard await flushPendingWorkspaceSaveAsync() else {
                await failAgentReplyAction(
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
            WeiBeiLog.workspace.error(
                "code=agent_note_action_read_failed action=undo item=\(target.id, privacy: .private) underlying=\(WeiBeiLog.code(error), privacy: .public) detail=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
            )
            await failAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID,
                message: ui(
                    "没有读取到目标笔记，因此没有执行撤销；当前笔记内容保持不变。请确认笔记文件可访问后重试。",
                    "The target note could not be read, so the undo was not performed. The current note content is unchanged. Make sure the note file is accessible, then try again."
                )
            )
        }
    }

    private func confirmAgentRelationAction(
        messageID: UUID,
        snapshot: (chatID: UUID, courseID: UUID?, action: AgentReplyAction)
    ) async {
        let action = snapshot.action
        guard let noteItemID = action.targetItemID,
              let sourceItemID = action.sourceItemID,
              let note = allItems.first(where: {
                  $0.id == noteItemID && $0.isNotebookNote
              }),
              let source = allItems.first(where: {
                  $0.id == sourceItemID && $0.isCourseMaterial
              }),
              source.id != note.id,
              relationItemsBelongToActionScope(
                  noteItemID: note.id,
                  sourceItemID: source.id,
                  courseID: snapshot.courseID
              ) else {
            await failAgentReplyAction(
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
                await failAgentReplyAction(
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
            guard await flushPendingWorkspaceSaveAsync() else {
                await failAgentReplyAction(
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
        guard await flushPendingWorkspaceSaveAsync() else {
            noteSourceLinks.removeAll { $0.id == relation.id }
            updateAgentReplyAction(
                messageID: messageID,
                actionID: action.id,
                chatID: snapshot.chatID
            ) {
                $0.createdRelationID = nil
            }
            await failAgentReplyAction(
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
    ) async {
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
        guard await flushPendingWorkspaceSaveAsync() else {
            noteSourceLinks.append(relation)
            await failAgentReplyAction(
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
    ) async {
        updateAgentReplyAction(
            messageID: messageID,
            actionID: actionID,
            chatID: chatID
        ) {
            $0.state = .failed
            $0.failureMessage = message
        }
        _ = await flushPendingWorkspaceSaveAsync()
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
        // Never flushPendingNotePersistence() here: the default overload also
        // calls flushPendingWorkspaceSave(), which RunLoop-spins on MainActor
        // and surfaces the 60s "文件操作超过 60 秒未完成" banner.
        flushPendingNotePersistence(flushWorkspace: false)
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
        guard notePersisted else { return false }
        return await flushPendingWorkspaceSaveAsync()
    }

    func syncActiveStudySession(titleSeed: String? = nil) {
        guard let activeStudySessionID,
              let index = studySessions.firstIndex(where: { $0.id == activeStudySessionID }) else { return }
        studySessions[index].messages = messages
        studySessions[index].updatedAt = Date()
        if let titleSeed,
           !studySessions[index].titleSetByUser,
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
        let materialItems = allItems.filter(\.isCourseMaterial)
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return materialItems }
        return materialItems.filter { itemMatchesLibrarySearch($0, query: query) }
    }

    var selectedItem: StudyItem? {
        allItems.first { $0.id == selectedItemID }
    }

    var selectedMaterialItem: StudyItem? {
        guard let item = selectedItem, item.isCourseMaterial else { return nil }
        return item
    }

    var activeNoteItem: StudyItem? {
        // 笔记窗格只跟随笔记主键;选中条目本身是笔记(在文稿区打开)时不再牵引
        // 笔记窗格——文稿区/笔记区各管各的(2026-08-26 定案解耦)。
        if let activeNotebookItemID,
           let item = allItems.first(where: { $0.id == activeNotebookItemID && $0.isNotebookNote }) {
            return item
        }
        return nil
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
        case .documentAgentNotes, .documentNotesAgent:
            return isPaneVisible(role)
        }
    }

    func navigateBackInWorkspace() {
        guard let target = backNavigationStack.last else { return }
        requestNoteSelectionTransition(to: target.activeNotebookItemID) { [weak self] in
            guard let self, let previous = backNavigationStack.popLast() else { return }
            forwardNavigationStack.append(navigationSnapshot())
            applyNavigationSnapshot(previous)
        }
    }

    func navigateForwardInWorkspace() {
        guard let target = forwardNavigationStack.last else { return }
        requestNoteSelectionTransition(to: target.activeNotebookItemID) { [weak self] in
            guard let self, let next = forwardNavigationStack.popLast() else { return }
            backNavigationStack.append(navigationSnapshot())
            applyNavigationSnapshot(next)
        }
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
        let catalog = allItems
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
            $0.backend = .native
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
        if fileMissingSinceByItemID[item.id] != nil {
            return ui("文件不存在", "File missing")
        }
        return item.subtitle
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
            guard let itemID,
                  allItems.contains(where: { $0.id == itemID && $0.isNotebookNote }) else {
                selectMeasured(itemID: itemID, opensNotebook: nil)
                return
            }
            requestNoteSelectionTransition(to: itemID) { [weak self] in
                self?.selectMeasured(itemID: itemID, opensNotebook: nil)
            }
        }
    }

    var noteSelectionStatusMessage: String? {
        // 自愈期内只报中性的"正在保存",失败文案与手动重试在重试额度耗尽后才出现。
        if pendingNoteSelection != nil,
           pendingSelectionSelfHealAttempts < Self.selfHealAttemptLimit,
           noteSelectionTransitionState != .idle {
            return ui("正在保存当前笔记…", "Saving the current note…")
        }
        return switch noteSelectionTransitionState {
        case .idle:
            nil
        case .saving:
            ui("正在保存当前笔记…", "Saving the current note…")
        case .failed(.snapshotTimedOut):
            ui(
                "当前正文仍在当前页面，尚未确认保存。请重试后再切换。",
                "The current text remains on this page, but its save is not confirmed. Retry before switching."
            )
        case .failed(.bridgeUnavailable):
            ui(
                "最近的持久恢复点仍在，但最后一段编辑无法确认。请重试编辑器连接后再切换。",
                "The latest durable recovery point remains, but the final edits could not be confirmed. Retry the editor connection before switching."
            )
        case .failed(.documentChanged):
            ui(
                "保存过程中当前笔记发生了变化，魏碑没有切换。请重试。",
                "The current note changed while saving, so WeiBei did not switch. Please retry."
            )
        case .persistenceFailed:
            ui(
                "当前笔记尚未安全保存，魏碑没有切换。请重试。",
                "The current note was not safely saved, so WeiBei did not switch. Please retry."
            )
        }
    }

    var noteEditorCommandFailureMessage: String? {
        guard let rejected = firstRetryableContentCommand else { return nil }
        // 自愈期内静默:内容已保留、后台自动重发,不给用户看内部术语。
        if rejectedCommandSelfHealAttempts < Self.selfHealAttemptLimit {
            return nil
        }
        if rejected.documentID != activeNoteEditorDocumentID {
            return ui(
                "未应用的内容已保留。返回原笔记后可重试。",
                "The unapplied content is preserved. Return to its original note to retry."
            )
        }
        return ui(
            "编辑器未完成这次操作；涉及的内容已保留。请重试。",
            "The editor did not complete this operation. Its content is preserved; please retry."
        )
    }

    var canRetryRejectedNoteEditorCommand: Bool {
        firstRetryableContentCommand?.documentID == activeNoteEditorDocumentID
            && noteEditorCommand == nil
    }

    func noteEditorContentCommandPending(_ command: NoteEditorCommand, documentID: String) {
        guard var tracked = trackedContentCommand(id: command.id),
              tracked.documentID == documentID else { return }
        tracked.isCoordinatorOwned = true
        upsertTrackedContentCommand(tracked)
        if pendingNoteSelection != nil,
           noteEditingSession.documentID == documentID {
            noteSelectionTransitionState = .saving
            armNoteSelectionWatchdog()
        }
    }

    func noteEditorContentCommandApplied(_ command: NoteEditorCommand, documentID: String) {
        guard trackedContentCommand(id: command.id)?.documentID == documentID else { return }
        removeTrackedContentCommand(id: command.id)
        if unresolvedContentCommands.isEmpty {
            rejectedCommandSelfHealAttempts = 0
            rejectedCommandSelfHealTask?.cancel()
        }
        resumePendingNoteSelection(afterResolvingCommandFor: documentID)
    }

    func noteEditorCommandRejected(_ command: NoteEditorCommand, documentID: String) {
        guard command.kind.isContentCommand else { return }
        var tracked = trackedContentCommand(id: command.id)
            ?? TrackedNoteEditorCommand(documentID: documentID, command: command)
        tracked.isCoordinatorOwned = false
        upsertTrackedContentCommand(tracked)
        scheduleRejectedCommandSelfHeal()
    }

    func retryRejectedNoteEditorCommand() {
        guard noteEditorCommand == nil,
              let index = unresolvedContentCommands.firstIndex(where: {
                  !$0.isCoordinatorOwned && $0.documentID == activeNoteEditorDocumentID
              }) else { return }
        let command = unresolvedContentCommands.remove(at: index).command
        noteEditorCommand = command
        if pendingNoteSelection != nil {
            noteSelectionTransitionState = .saving
            armNoteSelectionWatchdog()
        }
    }

    var canRetryPendingNoteSelection: Bool {
        switch noteSelectionTransitionState {
        case .failed, .persistenceFailed:
            return pendingNoteSelection != nil
        case .idle, .saving:
            return false
        }
    }

    func retryPendingNoteSelection() {
        guard pendingNoteSelection != nil else { return }
        requestPendingNoteSelectionSnapshot()
    }

    func requestNoteSelectionTransition(
        to documentID: String?,
        apply: @escaping () -> Void
    ) {
        let sourceDocumentID = noteEditingSession.documentID
        guard sourceDocumentID != documentID,
              noteEditingSession.dirty || hasUnresolvedContentCommand(for: sourceDocumentID) else {
            pendingNoteSelection = nil
            noteSelectionTransitionState = .idle
            apply()
            return
        }

        pendingNoteSelection = PendingNoteSelection(apply: apply)
        if hasUnresolvedContentCommand(for: sourceDocumentID) {
            noteSelectionTransitionState = .saving
            armNoteSelectionWatchdog()
            return
        }
        guard noteSelectionTransitionState != .saving else { return }
        requestPendingNoteSelectionSnapshot()
    }

    private func trackedContentCommand(id: UUID) -> TrackedNoteEditorCommand? {
        unresolvedContentCommands.first { $0.command.id == id }
    }

    private var firstRetryableContentCommand: TrackedNoteEditorCommand? {
        unresolvedContentCommands.first { !$0.isCoordinatorOwned }
    }

    private func upsertTrackedContentCommand(_ tracked: TrackedNoteEditorCommand) {
        if let index = unresolvedContentCommands.firstIndex(where: {
            $0.command.id == tracked.command.id
        }) {
            unresolvedContentCommands[index] = tracked
        } else {
            unresolvedContentCommands.append(tracked)
        }
    }

    private func removeTrackedContentCommand(id: UUID) {
        unresolvedContentCommands.removeAll { $0.command.id == id }
    }

    private func hasUnresolvedContentCommand(for documentID: String) -> Bool {
        unresolvedContentCommands.contains { $0.documentID == documentID }
    }

    private func resumePendingNoteSelection(afterResolvingCommandFor documentID: String) {
        guard pendingNoteSelection != nil,
              noteEditingSession.documentID == documentID else { return }
        guard !hasUnresolvedContentCommand(for: documentID) else {
            noteSelectionTransitionState = .saving
            return
        }
        requestPendingNoteSelectionSnapshot()
    }

    private func requestPendingNoteSelectionSnapshot() {
        guard pendingNoteSelection != nil else { return }
        noteSelectionTransitionState = .saving
        armNoteSelectionWatchdog()
        let sourceDocumentID = noteEditingSession.documentID
        _ = noteEditingSession.requestSnapshot { [weak self] result in
            self?.finishPendingNoteSelectionSnapshot(
                result,
                sourceDocumentID: sourceDocumentID
            )
        }
    }

    private func armNoteSelectionWatchdog() {
        noteSelectionWatchdogTask?.cancel()
        let seconds = max(noteSelectionWatchdogSeconds, 0.05)
        noteSelectionWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.pendingNoteSelection != nil,
                  self.noteSelectionTransitionState == .saving else { return }
            self.failPendingNoteSelection(.snapshotTimedOut)
        }
    }

    private func disarmNoteSelectionWatchdog() {
        noteSelectionWatchdogTask?.cancel()
        noteSelectionWatchdogTask = nil
    }

    /// 被拒命令静默重发:内容已保留,后台自动重试,不打扰用户。
    private func scheduleRejectedCommandSelfHeal() {
        rejectedCommandSelfHealTask?.cancel()
        guard rejectedCommandSelfHealAttempts < Self.selfHealAttemptLimit,
              firstRetryableContentCommand != nil else { return }
        rejectedCommandSelfHealAttempts += 1
        let delay = max(noteSelectionSelfHealDelaySeconds, 0.02)
        rejectedCommandSelfHealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.retryRejectedNoteEditorCommand()
            if self.firstRetryableContentCommand != nil {
                self.scheduleRejectedCommandSelfHeal()
            }
        }
    }

    /// 失败切换静默重试:到期自动重发快照请求,不打扰用户。
    private func schedulePendingSelectionSelfHeal() {
        pendingSelectionSelfHealTask?.cancel()
        guard pendingSelectionSelfHealAttempts < Self.selfHealAttemptLimit,
              pendingNoteSelection != nil else { return }
        pendingSelectionSelfHealAttempts += 1
        let delay = max(noteSelectionSelfHealDelaySeconds, 0.02)
        pendingSelectionSelfHealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.retryPendingNoteSelection()
        }
    }

    private func finishPendingNoteSelectionSnapshot(
        _ result: Result<NoteEditorSnapshotReadyEvent, NoteEditingSessionError>,
        sourceDocumentID: String
    ) {
        guard pendingNoteSelection != nil else {
            noteSelectionTransitionState = .idle
            disarmNoteSelectionWatchdog()
            return
        }
        switch result {
        case .success(let snapshot):
            guard snapshot.documentID == sourceDocumentID,
                  noteEditingSession.documentID == sourceDocumentID else {
                failPendingNoteSelection(.documentChanged)
                return
            }
            if snapshot.revision < noteEditingSession.currentRevision {
                requestPendingNoteSelectionSnapshot()
                return
            }
            let digest = Self.noteContentDigest(Data(snapshot.markdown.utf8))
            guard let accepted = latestNoteEditorSnapshot,
                  accepted.documentID == snapshot.documentID,
                  accepted.revision == snapshot.revision,
                  accepted.digest == digest else {
                failPendingNoteSelection(.documentChanged)
                return
            }
            if noteEditorSnapshotIsDurable(snapshot, digest: digest) {
                applyPendingNoteSelection()
                return
            }
            guard item(withID: snapshot.documentID)?
                .editsBackingMarkdownFile == false else {
                failPendingNoteSelectionPersistence()
                return
            }
            Task { @MainActor [weak self] in
                await self?.persistPendingNoteSelectionSnapshot(
                    snapshot,
                    digest: digest
                )
            }
        case .failure(let error):
            failPendingNoteSelection(error)
        }
    }

    private func persistPendingNoteSelectionSnapshot(
        _ snapshot: NoteEditorSnapshotReadyEvent,
        digest: String
    ) async {
        let persisted = await persistWorkspaceNow()
        guard pendingNoteSelection != nil else {
            noteSelectionTransitionState = .idle
            disarmNoteSelectionWatchdog()
            return
        }
        guard noteEditingSession.documentID == snapshot.documentID else {
            failPendingNoteSelection(.documentChanged)
            return
        }
        guard !hasUnresolvedContentCommand(for: snapshot.documentID) else {
            noteSelectionTransitionState = .saving
            armNoteSelectionWatchdog()
            return
        }
        guard noteEditingSession.currentRevision == snapshot.revision,
              let accepted = latestNoteEditorSnapshot,
              accepted.documentID == snapshot.documentID,
              accepted.revision == snapshot.revision,
              accepted.digest == digest else {
            requestPendingNoteSelectionSnapshot()
            return
        }
        guard persisted,
              noteEditorSnapshotIsDurable(snapshot, digest: digest) else {
            failPendingNoteSelectionPersistence()
            return
        }
        applyPendingNoteSelection()
    }

    private func noteEditorSnapshotIsDurable(
        _ snapshot: NoteEditorSnapshotReadyEvent,
        digest: String
    ) -> Bool {
        guard noteEditingSession.documentID == snapshot.documentID,
              noteEditingSession.currentRevision == snapshot.revision,
              !noteEditingSession.dirty,
              let accepted = latestNoteEditorSnapshot else { return false }
        return accepted.documentID == snapshot.documentID
            && accepted.revision == snapshot.revision
            && accepted.digest == digest
            && accepted.baseDigest == digest
    }

    private func applyPendingNoteSelection() {
        let apply = pendingNoteSelection?.apply
        pendingNoteSelection = nil
        noteSelectionTransitionState = .idle
        pendingSelectionSelfHealAttempts = 0
        pendingSelectionSelfHealTask?.cancel()
        disarmNoteSelectionWatchdog()
        apply?()
    }

    private func failPendingNoteSelection(_ error: NoteEditingSessionError) {
        WeiBeiLog.noteRepair.error(
            "note selection snapshot failed: \(String(describing: error), privacy: .private)"
        )
        disarmNoteSelectionWatchdog()
        noteSelectionTransitionState = .failed(error)
        schedulePendingSelectionSelfHeal()
    }

    private func failPendingNoteSelectionPersistence() {
        WeiBeiLog.noteRepair.error(
            "note selection stopped because the accepted snapshot was not durably persisted"
        )
        disarmNoteSelectionWatchdog()
        noteSelectionTransitionState = .persistenceFailed
        schedulePendingSelectionSelfHeal()
    }

    func selectMeasured(itemID: String?, opensNotebook: Bool?) {
        invalidateAgentContext()
        persistCurrentNote()
        notebookCreationDraft = nil
        notebookRenameDraft = nil
        if let itemID {
            alignActiveCourse(with: itemID)
        }
        if opensNotebook != false,
           let itemID,
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
        let validSourceIDs = Set(allItems.lazy.filter(\.isCourseMaterial).map(\.id))
        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.replaceSources(
            for: noteItemID,
            sourceItemIDs: sourceItemIDs.intersection(validSourceIDs).subtracting([noteItemID])
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
        guard allItems.contains(where: { $0.id == sourceItemID && $0.isCourseMaterial }) else { return }
        let validNoteIDs = Set(courseNotebookItems.map(\.id))
        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.replaceNotes(
            for: sourceItemID,
            noteItemIDs: noteItemIDs.intersection(validNoteIDs).subtracting([sourceItemID])
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
            let expanded = CourseProjectFileWorker.expandedSupportedFiles(
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
                    recordCourseLibraryUIFailure(
                        error,
                        operation: "import_file_into_course",
                        path: sourceURL
                    )
                    showImportantOperationError(ui(
                        "“\(sourceURL.lastPathComponent)”未完成课程登记；原文件没有被移动或覆盖，但课程目录可能留有已写入副本。请检查课程目录后再重试。",
                        "“\(sourceURL.lastPathComponent)” was not fully registered in the course. The original file was not moved or overwritten, but a written copy may remain in the course folder. Check the course folder before trying again."
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

    func courseImportConflictResolution(
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
        keepBothLabel.font = .systemFont(ofSize: 12, weight: .medium)
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

    func itemIsAvailableInCourseContext(itemID: String, courseID: UUID) -> Bool {
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
            $0.id == itemID && $0.isCourseMaterial
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
        selectMeasured(itemID: itemID, opensNotebook: false)
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

    func continueCourseSession(
        _ sessionID: UUID,
        expectedCourseID: UUID?,
        expectedScopeNeedsReview: Bool
    ) {
        guard studySessions.contains(where: {
            $0.id == sessionID && $0.hasChatHistory
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

    /// Route one course-home question into the existing Chat/Agent pipeline.
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
        agentDraft = question; pendingComposerDraft = question
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
                      && $0.hasChatHistory
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

    func dismissCourseWorkspace(restoringFocus: Bool) {
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

    func waitForBlankNoteMaterialization() async -> Bool {
        await blankNoteMaterializationTask?.value
        return blankNoteDraftMaterialID == nil
            || noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        // 生产 60 秒兜底：交互等待不再无限挂死；大导入走后台进度路径不经过本闸门。
        let deadline = WeiBeiSafetyTestMode.isEnabled
            ? Date().addingTimeInterval(45)
            : Date().addingTimeInterval(60)
        while result == nil {
            if Date() > deadline {
                showImportantOperationError(ui("文件操作超过 60 秒未完成，已停止等待；请重试该操作。", "A file operation did not finish within 60 seconds; please retry."))
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
           let item = allItems.first(where: { $0.id == sourceItemID && $0.isCourseMaterial }) {
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
            if layout == .immersiveReading || layout == .immersiveWriting {
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
            requestNoteSelectionTransition(to: nil) { [weak self] in
                guard let self else { return }
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
        case .documentAgentNotes, .documentNotesAgent:
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
        case .documentAgentNotes, .documentNotesAgent:
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

    func restoreCurrentStudyLocation() {
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
        // Fuzzy title match for Agent short labels like "货币金融学课程 HTML".
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

    func requestPaneExpansion(_ role: WorkspacePaneRole, onCompleted: (() -> Void)? = nil) {
        paneExpansionRequest = PaneExpansionRequest(role: role, onCompleted: onCompleted)
    }

    func completePaneExpansionRequest(_ id: UUID) {
        guard let request = paneExpansionRequest, request.id == id else { return }
        paneExpansionRequest = nil
        request.onCompleted?()
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
        case .documentAgentNotes, .documentNotesAgent:
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
        case .documentAgentNotes, .documentNotesAgent:
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

    func revealRichWritingSurface() {
        if layout == .immersiveReading || layout == .immersiveConversation {
            clearUnpinnedFloatingSelection()
            layout = .immersiveWriting
        }
        if !showNotes {
            clearUnpinnedFloatingSelection()
            showNotes = true
        }
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

    func executableChord(for shortcut: AppShortcutID) -> AppShortcutChord? {
        AppShortcutCatalog.executableChord(for: shortcut, overrides: customShortcutOverrides)
    }

    @discardableResult
    func setShortcut(_ id: AppShortcutID, chord: AppShortcutChord) -> Bool {
        guard !AppShortcutCatalog.isReservedTextEditingChord(chord),
              AppShortcutCatalog.conflict(
                  for: chord,
                  excluding: id,
                  overrides: customShortcutOverrides
              ) == nil else { return false }
        if chord == id.defaultChord {
            customShortcutOverrides.removeValue(forKey: id)
        } else {
            customShortcutOverrides[id] = chord
        }
        AppShortcutCatalog.saveOverrides(customShortcutOverrides)
        objectWillChange.send()
        return true
    }

    @discardableResult
    func resetShortcut(_ id: AppShortcutID) -> Bool {
        setShortcut(id, chord: id.defaultChord)
    }

    func resetAllShortcuts() {
        customShortcutOverrides = [:]
        AppShortcutCatalog.saveOverrides([:])
        objectWillChange.send()
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

    func setInterfaceTextScale(_ scale: WeiBeiTypography.TextScale) {
        guard interfaceTextScale != scale else { return }
        interfaceTextScale = scale
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
        (try? waitForCourseFileOperation {
            _ = self.restorePortableCourseStates()
            guard self.blockedPortableCourseIDs.isEmpty else {
                return false
            }
            guard await self.reconcileCourseFilesNow(
                persistsChanges: false
            ) else {
                return false
            }
            return await self.persistWorkspaceNow()
        }) ?? false
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
        importFiles(
            panel.urls,
            selectsFirstImportedItem: selectsFirstImportedItem,
            markdownAsNotes: markdownAsNotes,
            markdownOnly: markdownOnly,
            reclassifiesExistingMarkdown: reclassifiesExistingMarkdown
        ) { selectedItems in
            if let targetNoteID, self.activeNotebookItemID == targetNoteID {
                self.setLinkedSourceIDsForActiveNote(
                    Set(self.linkedSourceIDsForActiveNote).union(selectedItems.map(\.id))
                )
            }
        }
    }

    func importFiles(
        _ urls: [URL],
        selectsFirstImportedItem: Bool = true,
        markdownAsNotes: Bool = false,
        markdownOnly: Bool = false,
        markdownNotePaths: Set<String>? = nil,
        reclassifiesExistingMarkdown: Bool = false,
        completion: @escaping ([StudyItem]) -> Void = { _ in }
    ) {
        if courseLibraryRootURL == nil {
            bootstrapDefaultLibraryIfNeeded()
        }
        guard let libraryRoot = courseLibraryRootURL else {
            showImportantOperationError(ui(
                "课程资料库不可用，未能导入。请重新打开魏碑，或到课程空间重新选择资料库文件夹。",
                "The course library is unavailable, so nothing was imported. Restart WeiBei or choose the library folder again in the course space."
            ))
            completion([])
            return
        }
        if reclassifiesExistingMarkdown || markdownNotePaths != nil {
            persistCurrentNote()
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let expandedURLs = CourseProjectFileWorker.expandedSupportedFiles(
                from: urls,
                markdownOnly: markdownOnly
            )
            var copied: [(url: URL, isNote: Bool)] = []
            var failures: [String] = []
            for (offset, rawURL) in expandedURLs.enumerated() {
                let importsIntoNotes = Self.isMarkdownFile(rawURL)
                    && (markdownNotePaths?.contains(rawURL.path) ?? markdownAsNotes)
                do {
                    let url = try Self.copyExternalFileIntoLibrary(
                        root: libraryRoot,
                        sourceURL: rawURL,
                        isNote: importsIntoNotes
                    )
                    copied.append((url, importsIntoNotes))
                } catch {
                    WeiBeiLog.workspace.error(
                        "code=common_import_failed underlying=\(WeiBeiLog.code(error), privacy: .public) path=\(rawURL.path, privacy: .private) detail=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
                    )
                    failures.append("“\(rawURL.lastPathComponent)”")
                }
                let progress = CourseFileOperationProgress(
                    completed: offset + 1,
                    total: expandedURLs.count,
                    currentFileName: rawURL.lastPathComponent
                )
                await MainActor.run { [weak self] in
                    self?.courseFileOperationProgress = progress
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { completion([]); return }
                self.courseFileOperationProgress = nil
                let selectedItems = self.applyImportedCommonFiles(
                    copied,
                    selectsFirstImportedItem: selectsFirstImportedItem,
                    reclassifiesExistingMarkdown: reclassifiesExistingMarkdown
                )
                if !failures.isEmpty {
                    let listed = failures.prefix(3).joined(separator: "\n")
                    let remaining = failures.count - min(3, failures.count)
                    self.showImportantOperationError(ui(
                        "导入完成：成功 \(copied.count) 个，失败 \(failures.count) 个。原文件均未移动；请确认这些文件可访问后重试：\n\(listed)"
                            + (remaining > 0 ? ui("\n\n另有 \(remaining) 个失败未列出。", "\n\nPlus \(remaining) more failure(s).") : ""),
                        "Import finished: \(copied.count) succeeded and \(failures.count) failed. Original files were not moved. Make sure these files are accessible, then try again:\n\(listed)"
                            + (remaining > 0 ? "\n\nPlus \(remaining) more failure(s)." : "")
                    ))
                }
                completion(selectedItems)
            }
        }
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

    nonisolated static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    static func isSupportedCourseFile(_ url: URL) -> Bool {
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
            recordCourseLibraryUIFailure(
                error,
                operation: "create_wiki_note",
                path: url
            )
            showImportantOperationError(ui(
                "双链笔记没有创建或登记，现有文件未被覆盖。请确认资料库可写，或换一个标题后重试。",
                "The wiki note was not created or registered, and existing files were not overwritten. Make sure the library is writable, or choose another title and try again."
            ))
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
            save()
            let status = sourceItem == nil
                ? ui("已新建空白笔记：\(url.lastPathComponent)", "Created blank note: \(url.lastPathComponent)")
                : ui("已为当前资料新建笔记：\(url.lastPathComponent)", "Created note from current material: \(url.lastPathComponent)")
            requestNoteSelectionTransition(to: item.id) { [weak self] in
                guard let self else { return }
                activeNotebookItemID = item.id
                noteText = markdown
                revealRichWritingSurface()
                focus(.notes)
                showTransientNoteStatus(status)
            }
            return item
        } catch {
            recordCourseLibraryUIFailure(
                error,
                operation: "create_notebook_note",
                path: notesDirectory
            )
            showImportantOperationError(ui(
                "笔记没有创建或加入列表，现有笔记未被覆盖。请确认笔记目录可写后重试。",
                "The note was not created or added to the list, and existing notes were not overwritten. Make sure the Notes folder is writable, then try again."
            ))
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
        let itemID = importedItems[index].id
        requestNoteSelectionTransition(to: itemID) { [weak self] in
            guard let self,
                  let index = importedItems.firstIndex(where: { $0.id == itemID }) else { return }
            invalidateAgentContext()
            importedItems[index].isNotebookNote = true
            removeLinksWhereSourceItemID(itemID)
            activeNotebookItemID = itemID
            if selectedItemID == itemID {
                self.selectedItemID = nil
                readerLocationTitle = selectedMaterialItem.map(displayTitle)
            }
            noteText = noteText(for: importedItems[index])
            revealRichWritingSurface()
            focus(.notes)
            save()
        }
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

    func updateSelection(_ text: String, source: SelectionSource, anchor: CGPoint? = nil, ownerTitle: String? = nil, isEditable: Bool = true, documentAnchor: SelectionDocumentAnchor? = nil) {
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
        // Multi-pane and immersive both get the selection capsule when there is an anchor
        // (previously suppressed whenever the chat column was open — looked "broken").
        let shouldRevealSelectionPrompt = anchor != nil || pinnedFloatingAgent
        let contentMatches = selectionContext.map {
            $0.text == cleaned
                && $0.source == source
                && $0.ownerTitle == resolvedOwnerTitle
                && $0.isEditable == isEditable
        } ?? false

        // Drag stream: same text, only anchor moves — no spring, no new SelectionContext id.
        if contentMatches {
            let anchorUnchanged = WorkspaceInteractionState.anchorsApproximatelyEqual(selectionAnchor, anchor, epsilon: 8)
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
            text: cleaned,
            source: source,
            ownerTitle: resolvedOwnerTitle,
            itemID: source == .note ? activeNotebookItemID : selectedItemID,
            isEditable: isEditable,
            documentAnchor: documentAnchor
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
            text: mergedText,
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

    private func sourceReferenceItem(from rawReference: String?) -> StudyItem? {
        let reference = SourceReferenceTitle.parse(rawReference ?? "")
        guard !reference.title.isEmpty else { return nil }
        if let ordinal = reference.courseItemOrdinal {
            let catalog = allItems
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
            if let material = exact.first(where: \.isCourseMaterial) { return material }
            return exact[0]
        }

        let loose = allItems.filter {
            titlesLooselyMatch(displayTitle(for: $0), rawTitle)
                || titlesLooselyMatch(displaySubtitle(for: $0), rawTitle)
        }
        if loose.count == 1 { return loose[0] }
        if loose.count > 1 {
            if let material = loose.first(where: \.isCourseMaterial) { return material }
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

    func migrateNoteSourceLinksFromMarkdown() {
        let previousCount = noteSourceLinks.count
        for note in allItems where note.isNotebookNote {
            let markdown = noteMarkdownText(for: note)
            for rawLine in markdown.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.contains("来源：") || line.localizedCaseInsensitiveContains("source:") else { continue }
                guard let source = sourceReferenceItem(from: line), source.isCourseMaterial else { continue }
                addNoteSourceLink(noteItemID: note.id, sourceItemID: source.id)
            }
        }
        if noteSourceLinks.count != previousCount { save() }
    }

    @discardableResult
    func sanitizeNoteSourceLinks() -> Bool {
        let previous = noteSourceLinks
        let validNoteItemIDs = Set(allItems.lazy.filter(\.isNotebookNote).map(\.id))
        let validSourceItemIDs = Set(allItems.lazy.filter(\.isCourseMaterial).map(\.id))
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
                    guard item.id == itemEntry.key, item.isCourseMaterial else { return false }
                    if case .common = item.storage { return true }
                    return false
                }
                guard validItemIDs.contains(itemEntry.key) || isCommonMaterial,
                      importedItems.contains(where: {
                          $0.id == itemEntry.key && $0.isCourseMaterial
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
    func migrateLegacyStudySessionScopes() -> Bool {
        var changed = sanitizeStudySessionScopes()
        guard studySessionScopeMigrationVersion < 2 else { return changed }
        ensureAllStudySessionMessagesLoaded()
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
    func migrateLegacyLearningMemoryScopes() -> Bool {
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
        courseID.map { [.course($0)] } ?? []
    }

    private func learningMemoryContextRevision(courseID: UUID?) -> UInt64 {
        learningMemoryContextScopes(courseID: courseID).reduce(0) { revision, scope in
            (revision &* 1_000_003) &+ learningMemoryRevision(in: scope) &+ 1
        }
    }

    private func learningMemoryScope(
        for _: LearningMemoryKind,
        courseID: UUID?
    ) -> LearningMemoryScope {
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
        return courseKnowledgeProfiles.filter { profile in
            courseIDs.contains(profile.courseID)
        }
    }

    func ensureCourseKnowledgeProfiles() -> Bool {
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

    private func confirmedAgentNotes(
        in target: AgentConversationTarget
    ) -> [StudyAgentPersistedNoteRef] {
        let sessionMessages: [AgentMessage]
        if activeStudySessionID == target.sessionID {
            sessionMessages = messages
        } else if let session = studySessions.first(where: { $0.id == target.sessionID }) {
            sessionMessages = session.messages
        } else {
            return []
        }
        var seen = Set<String>()
        var refs: [StudyAgentPersistedNoteRef] = []
        for message in sessionMessages {
            for action in message.actions where action.kind == .writeNote && action.state == .executed {
                guard let itemID = action.targetItemID, seen.insert(itemID).inserted else { continue }
                guard let noteItem = allItems.first(where: { $0.id == itemID && $0.isNotebookNote }) else {
                    continue
                }
                if let courseID = target.courseID, !item(itemID, belongsTo: courseID) {
                    continue
                }
                refs.append(
                    StudyAgentPersistedNoteRef(
                        itemID: itemID,
                        title: displayTitle(for: noteItem)
                    )
                )
            }
        }
        return refs
    }

    private func latestConfirmedAgentNoteItem(
        in target: AgentConversationTarget
    ) -> StudyItem? {
        guard let itemID = confirmedAgentNotes(in: target).last?.itemID else { return nil }
        return allItems.first { $0.id == itemID && $0.isNotebookNote }
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
                  course.sourceRootIdentity != nil,
                  let rawRoot = courseRootURL(for: courseID),
                  let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(rawRoot),
                  let liveRootIdentity = CourseProjectFileWorker.identity(at: resolvedRoot) else {
                return nil
            }
            // identity 只用于找回、永不用于拒绝（计划 §5 阶段5）：不一致时
            // 采用活体身份继续授权，最多记一条日志。
            if liveRootIdentity != course.sourceRootIdentity {
                WeiBeiLog.workspace.notice("agent_grant_root_identity_refreshed")
            }
            rootURL = resolvedRoot
            rootIdentity = liveRootIdentity
        }
        guard let liveRootIdentity = CourseProjectFileWorker.identity(at: rootURL),
              let membership = courseItemMemberships.first(where: {
                  $0.courseID == courseID && $0.itemID == item.id
              }),
              let relativePath = membership.courseRelativePath,
              Self.isVisibleAgentProjectPath(relativePath),
              let targetURL = item.url?.standardizedFileURL,
              let targetIdentity = item.importedFileIdentity else {
            return nil
        }
        if liveRootIdentity != rootIdentity {
            WeiBeiLog.workspace.notice("agent_grant_root_identity_drifted")
        }
        let entryURL = relativePath.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .reduce(rootURL) { $0.appendingPathComponent($1) }
            .standardizedFileURL
        guard let liveEntryIdentity = CourseProjectFileWorker.identity(at: entryURL),
              let liveTargetIdentity = CourseProjectFileWorker.identity(at: targetURL),
              CourseProjectPathPolicy.isSame(
                  targetURL,
                  targetURL.resolvingSymlinksInPath().standardizedFileURL
              ) else {
            return nil
        }
        // identity 只用于找回、永不用于拒绝：条目/目标身份漂移时刷新继续，
        // 授权以活体身份为准。
        if let entryIdentity = membership.entryIdentity, entryIdentity != liveEntryIdentity {
            WeiBeiLog.workspace.notice("agent_grant_entry_identity_refreshed")
        }
        if liveTargetIdentity != targetIdentity {
            WeiBeiLog.workspace.notice("agent_grant_target_identity_refreshed")
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
        case .bundledSample:
            return nil
        }
        return AgentFileGrant(
            courseID: courseID,
            courseTitle: courseTitle,
            rootURL: rootURL,
            rootIdentity: liveRootIdentity,
            entryURL: entryURL,
            entryIdentity: liveEntryIdentity,
            targetURL: targetURL,
            targetIdentity: liveTargetIdentity,
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
        firstMessageID: UUID
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
        let firstReply = AgentMessage(
            id: firstMessageID,
            role: .assistant,
            text: "最早一条课程回答。",
            source: "课程 Chat",
            backend: .native,
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
            backend: .native,
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
        pendingNoteWritesByItemID[noteItemID] = PendingNoteWriteState()
        return (
            sessionID,
            memoryID,
            draft,
            firstMessageID
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
        pendingNoteWritesByItemID[noteItemID] = PendingNoteWriteState()
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
            if case let .workspaceSearch(query, limit, crossLibrary) = request {
                return await self.searchWorkspaceForAgent(
                    query: query,
                    limit: limit,
                    crossLibrary: crossLibrary,
                    currentCourseID: target.courseID
                )
            }
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

    func makeLearningContext(
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
                turnCount: session.displayedMessageCount
            )
        }
        let memories = learningMemoryContextScopes(courseID: target.courseID)
            .flatMap { orderedLearningMemoryEntries(in: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
        return StudyAgentLearningContext(
            memoryRevision: learningMemoryContextRevision(courseID: target.courseID),
            lastLocation: target.courseID.flatMap { lastStudyLocation(in: $0) },
            memories: memories,
            session: session
        )
    }

    private func makeCourseProfileContext(
        courseID: UUID?
    ) -> StudyAgentCourseProfileContext {
        guard let courseID,
              let profileIndex = courseKnowledgeProfiles.firstIndex(where: {
                  $0.courseID == courseID
              }) else { return .empty }
        let profile = courseKnowledgeProfiles[profileIndex]
        return StudyAgentCourseProfileContext(
            revision: profile.revision,
            entries: profile.entries.map { entry in
                StudyAgentCourseProfileEntry(
                    id: entry.id.uuidString.lowercased(),
                    kind: entry.kind.rawValue,
                    text: entry.text
                )
            }
        )
    }

    func refreshCourseProfileContext(
        target: AgentConversationTarget
    ) -> StudyAgentCourseProfileContext {
        makeCourseProfileContext(courseID: target.courseID)
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
        guard let courseID = target.courseID,
              activeCourseRemovalTokens[courseID] == nil,
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
            let memoryID: UUID?
            let scope: LearningMemoryScope
            switch Self.parseOptionalRecordID(proposal.memoryID) {
            case .omitted:
                memoryID = nil
                scope = learningMemoryScope(
                    for: proposal.kind,
                    courseID: target.courseID
                )
            case .invalid:
                return nil
            case .id(let parsedMemoryID):
                guard entryTargetIDs.insert(parsedMemoryID).inserted,
                      let located = locatedMemory(parsedMemoryID),
                      located.2.status == .active,
                      located.0 == learningMemoryScope(
                          for: proposal.kind,
                          courseID: target.courseID
                      ) else {
                    return nil
                }
                memoryID = parsedMemoryID
                scope = located.0
            }
            validatedEntries.append(
                (
                    proposal,
                    memoryID,
                    scope,
                    text,
                    String(evidence.prefix(400)),
                    proposal.origin
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
            guard let memoryID = UUID(uuidString: proposal.memoryID),
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
                let origin: LearningMemoryOrigin = validated.origin
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
               studySessions[index].summary != summary {
                studySessions[index].summary = summary
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
        let appliedTexts = changedMemoryIDs.compactMap { id in
            scopes.lazy.compactMap { scope in
                entriesByScope[scope]?.first(where: { $0.id == id })?.text
            }.first
        }
        let summary = appliedTexts.prefix(3).joined(separator: "；")
        return AgentReplyMemoryUpdate(
            memoryIDs: changedMemoryIDs,
            summary: summary.isEmpty
                ? ui("学习进度已更新", "Study progress updated")
                : String(summary.prefix(300)),
            texts: appliedTexts
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
    ) -> AgentReplyProfileUpdate? {
        guard let courseID = target.courseID,
              activeCourseRemovalTokens[courseID] == nil,
              let update,
              update.contextRevision == expectedContextRevision,
              update.profileRevision == expectedProfileRevision,
              let profileIndex = courseKnowledgeProfiles.firstIndex(where: {
                  $0.courseID == courseID && $0.revision == expectedProfileRevision
              }) else { return nil }
        var profile = courseKnowledgeProfiles[profileIndex]
        let existingIDs = Set(profile.entries.map(\.id))
        let removedIDs = Set(update.removedEntryIDs.compactMap(UUID.init(uuidString:)))
        guard removedIDs.count == update.removedEntryIDs.count,
              removedIDs.isSubset(of: existingIDs) else { return nil }

        var targetIDs = Set<UUID>()
        var replacements: [(UUID?, CourseKnowledgeProfileEntry)] = []
        let now = Date()
        for proposal in update.entries {
            let entryID: UUID?
            switch Self.parseOptionalRecordID(proposal.entryID) {
            case .omitted:
                entryID = nil
            case .invalid:
                return nil
            case .id(let parsed):
                entryID = parsed
            }
            guard entryID.map(existingIDs.contains) ?? true,
                  entryID.map({ targetIDs.insert($0).inserted }) ?? true else { return nil }
            let existing = entryID.flatMap { id in
                profile.entries.first(where: { $0.id == id })
            }
            replacements.append(
                (
                    entryID,
                    CourseKnowledgeProfileEntry(
                        id: entryID ?? UUID(),
                        kind: proposal.kind,
                        text: proposal.text,
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
        guard profile.entries != courseKnowledgeProfiles[profileIndex].entries else { return nil }
        profile.revision &+= 1
        profile.updatedAt = now
        courseKnowledgeProfiles[profileIndex] = profile
        dirtyPortableCourseIDs.insert(courseID)
        let texts = replacements.map { $0.1.text }
        return AgentReplyProfileUpdate(
            entryIDs: replacements.map { $0.1.id },
            summary: texts.prefix(3).joined(separator: "；"),
            texts: texts
        )
    }

    private enum OptionalRecordID {
        case omitted
        case invalid
        case id(UUID)
    }

    private static func parseOptionalRecordID(_ raw: String?) -> OptionalRecordID {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return .omitted }
        guard let id = UUID(uuidString: trimmed) else { return .invalid }
        return .id(id)
    }

    func persistNativeLearningUpdate(
        _ update: StudyAgentLearningUpdate,
        expectedContextRevision: String,
        expectedUserQuestion: String,
        target: AgentConversationTarget,
        messageID: UUID
    ) async -> NativeStorePersistReceipt {
        let previousLearningStates = learningMemoryStates
        let previousStudySessions = studySessions
        let previousLatestUpdate = latestAgentLearningUpdate
        let previousLatestQuestion = latestAgentLearningUpdateQuestion
        guard let applied = applyLearningUpdate(
            update,
            expectedContextRevision: expectedContextRevision,
            expectedMemoryRevision: update.memoryRevision,
            expectedUserQuestion: expectedUserQuestion,
            target: target,
            messageID: messageID
        ) else {
            learningMemoryStates = previousLearningStates
            studySessions = previousStudySessions
            latestAgentLearningUpdate = previousLatestUpdate
            latestAgentLearningUpdateQuestion = previousLatestQuestion
            let hasClientID = update.entries.contains {
                !($0.memoryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
            }
            if hasClientID {
                return .rejected("魏碑没有保存这次学习记忆。更新只能沿用 weibei_read_learning_memory 返回的 memoryID；新建请省略该字段，不要传空字符串，也不要自己编 UUID。")
            }
            return .rejected("魏碑没有保存这次学习记忆。每条记忆需要 kind 标签和内容；更新已有记忆时 memoryID 只能从读取结果或上次回执抄写。")
        }
        let appliedLearningStates = learningMemoryStates
        let appliedStudySession = studySessions.first {
            $0.id == target.sessionID
        }
        let appliedLatestUpdate = latestAgentLearningUpdate
        let appliedLatestQuestion = latestAgentLearningUpdateQuestion
        if let courseID = target.courseID {
            dirtyPortableCourseIDs.insert(courseID)
        }
        let persisted = await persistWorkspaceNow()
        let coursePersisted = target.courseID.map {
            persistedWorkspaceCourseIDs.contains($0)
                && !dirtyPortableCourseIDs.contains($0)
                && !blockedPortableCourseIDs.contains($0)
                && !oversizedPortableCourseIDs.contains($0)
        } ?? true
        if persisted && coursePersisted {
            return NativeStorePersistReceipt(
                accepted: true,
                message: "已写入学习记忆",
                memoryUpdate: applied
            )
        }

        for memoryID in applied.memoryIDs {
            guard let appliedState = appliedLearningStates.first(where: {
                $0.entries.contains { $0.id == memoryID }
            }),
            let appliedEntry = appliedState.entries.first(where: {
                $0.id == memoryID
            }),
            let currentStateIndex = learningMemoryStates.firstIndex(where: {
                $0.scope == appliedState.scope
            }),
            let currentEntryIndex = learningMemoryStates[currentStateIndex]
                .entries.firstIndex(where: { $0.id == memoryID }),
            learningMemoryStates[currentStateIndex].entries[currentEntryIndex]
                == appliedEntry else { continue }
            if let previousEntry = previousLearningStates
                .first(where: { $0.scope == appliedState.scope })?
                .entries.first(where: { $0.id == memoryID }) {
                learningMemoryStates[currentStateIndex].entries[currentEntryIndex] =
                    previousEntry
            } else {
                learningMemoryStates[currentStateIndex].entries.remove(
                    at: currentEntryIndex
                )
            }
        }
        let changedScopes = Set(applied.memoryIDs.compactMap { memoryID in
            appliedLearningStates.first {
                $0.entries.contains { $0.id == memoryID }
            }?.scope
        })
        for scope in changedScopes {
            guard let currentIndex = learningMemoryStates.firstIndex(where: {
                $0.scope == scope
            }),
            let appliedState = appliedLearningStates.first(where: {
                $0.scope == scope
            }),
            learningMemoryStates[currentIndex].revision == appliedState.revision else {
                continue
            }
            if let previousState = previousLearningStates.first(where: {
                $0.scope == scope
            }) {
                learningMemoryStates[currentIndex].revision = previousState.revision
            } else if learningMemoryStates[currentIndex].entries.isEmpty {
                learningMemoryStates.remove(at: currentIndex)
            }
        }
        if let appliedStudySession,
           let currentIndex = studySessions.firstIndex(where: {
               $0.id == target.sessionID
           }),
           let previous = previousStudySessions.first(where: {
               $0.id == target.sessionID
           }) {
            if appliedStudySession.summary != previous.summary,
               studySessions[currentIndex].summary == appliedStudySession.summary {
                studySessions[currentIndex].summary = previous.summary
            }
            if appliedStudySession.flow.phase != previous.flow.phase,
               studySessions[currentIndex].flow.phase == appliedStudySession.flow.phase {
                studySessions[currentIndex].flow.phase = previous.flow.phase
            }
            if appliedStudySession.flow.suggestedNext
                != previous.flow.suggestedNext,
               studySessions[currentIndex].flow.suggestedNext
                == appliedStudySession.flow.suggestedNext {
                studySessions[currentIndex].flow.suggestedNext =
                    previous.flow.suggestedNext
            }
            if appliedStudySession.updatedAt != previous.updatedAt,
               studySessions[currentIndex].updatedAt == appliedStudySession.updatedAt {
                studySessions[currentIndex].updatedAt = previous.updatedAt
            }
        }
        if latestAgentLearningUpdate == appliedLatestUpdate {
            latestAgentLearningUpdate = previousLatestUpdate
        }
        if latestAgentLearningUpdateQuestion == appliedLatestQuestion {
            latestAgentLearningUpdateQuestion = previousLatestQuestion
        }
        if let courseID = target.courseID {
            dirtyPortableCourseIDs.insert(courseID)
        }
        let rollbackPersisted = await persistWorkspaceNow()
        WeiBeiLog.workspace.error(
            "code=native_learning_persist_failed course=\(target.courseID?.uuidString ?? "none", privacy: .private) rollback_persisted=\(rollbackPersisted, privacy: .public)"
        )
        if rollbackPersisted {
            return .rejected("魏碑没有写入这次学习记忆，已恢复更新前的内容，同时发生的修改不受影响。请重试。")
        }
        return .rejected("魏碑无法确认这次学习记忆的最终磁盘状态。当前会话仍保留更新前的内容，请不要关闭并重试。")
    }

    func persistNativeCourseProfileUpdate(
        _ update: StudyAgentCourseProfileUpdate,
        expectedContextRevision: String,
        target: AgentConversationTarget
    ) async -> NativeStorePersistReceipt {
        let previousProfiles = courseKnowledgeProfiles
        guard let applied = applyCourseProfileUpdate(
            update,
            expectedContextRevision: expectedContextRevision,
            expectedProfileRevision: update.profileRevision,
            target: target
        ) else {
            let hasClientID = update.entries.contains {
                !($0.entryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
            }
            if hasClientID {
                return .rejected("魏碑没有保存这次课程档案。更新只能沿用当前档案已有条目的 entryID；新建请省略该字段，不要传空字符串，也不要自己编 UUID。")
            }
            return .rejected("魏碑没有保存这次课程档案。自述掌握用 kind=concept、text 以「用户自述：」开头，checkpoint 用 userRequested。")
        }
        let appliedProfiles = courseKnowledgeProfiles
        let persisted = await persistWorkspaceNow()
        let coursePersisted = target.courseID.map {
            persistedWorkspaceCourseIDs.contains($0)
                && !dirtyPortableCourseIDs.contains($0)
                && !blockedPortableCourseIDs.contains($0)
                && !oversizedPortableCourseIDs.contains($0)
        } ?? false
        if persisted && coursePersisted {
            return NativeStorePersistReceipt(
                accepted: true,
                message: "已写入课程知识档案",
                profileUpdate: applied
            )
        }

        if let courseID = target.courseID,
           let appliedProfile = appliedProfiles.first(where: {
               $0.courseID == courseID
           }),
           let currentIndex = courseKnowledgeProfiles.firstIndex(where: {
               $0.courseID == courseID
           }),
           let previousProfile = previousProfiles.first(where: {
               $0.courseID == courseID
           }) {
            if courseKnowledgeProfiles[currentIndex] == appliedProfile {
                courseKnowledgeProfiles[currentIndex] = previousProfile
            } else {
                let changedIDs = Set(applied.entryIDs).union(
                    update.removedEntryIDs.compactMap(UUID.init(uuidString:))
                )
                for entryID in changedIDs {
                    let appliedEntry = appliedProfile.entries.first {
                        $0.id == entryID
                    }
                    let currentEntryIndex = courseKnowledgeProfiles[currentIndex]
                        .entries.firstIndex { $0.id == entryID }
                    if let currentEntryIndex {
                        guard let appliedEntry,
                              courseKnowledgeProfiles[currentIndex].entries[
                                currentEntryIndex
                              ] == appliedEntry else { continue }
                    } else {
                        guard appliedEntry == nil else { continue }
                    }
                    if let previousEntry = previousProfile.entries.first(where: {
                        $0.id == entryID
                    }) {
                        if let currentEntryIndex {
                            courseKnowledgeProfiles[currentIndex].entries[
                                currentEntryIndex
                            ] = previousEntry
                        } else {
                            courseKnowledgeProfiles[currentIndex].entries.append(
                                previousEntry
                            )
                        }
                    } else if let currentEntryIndex {
                        courseKnowledgeProfiles[currentIndex].entries.remove(
                            at: currentEntryIndex
                        )
                    }
                }
            }
            dirtyPortableCourseIDs.insert(courseID)
        }
        let rollbackPersisted = await persistWorkspaceNow()
        WeiBeiLog.workspace.error(
            "code=native_course_profile_persist_failed course=\(target.courseID?.uuidString ?? "none", privacy: .private) rollback_persisted=\(rollbackPersisted, privacy: .public)"
        )
        if rollbackPersisted {
            return .rejected("魏碑没有写入这次课程档案，已恢复更新前的内容，同时发生的修改不受影响。请重试。")
        }
        return .rejected("魏碑无法确认这次课程档案的最终磁盘状态。当前会话仍保留更新前的内容，请不要关闭并重试。")
    }

    func isLearningMemoryResolved(_ memoryID: String, in scope: LearningMemoryScope) -> Bool {
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
        return flushPendingWorkspaceSave()
    }

    func resolveLearningMemory(_ memoryID: UUID, in scope: LearningMemoryScope) {
        setLearningMemoryStatus(
            memoryID,
            in: scope,
            status: .resolved,
            resolutionEvidence: "[用户：界面确认]"
        )
    }

    func restoreLearningMemory(_ memoryID: UUID, in scope: LearningMemoryScope) {
        setLearningMemoryStatus(memoryID, in: scope, status: .active, resolutionEvidence: nil)
    }
    @discardableResult
    func deleteLearningMemory(_ memoryID: UUID, in scope: LearningMemoryScope) -> Bool {
        guard scope.courseID.map({
            activeCourseRemovalTokens[$0] == nil
        }) ?? true,
        let stateIndex = learningMemoryStateIndex(for: scope, createIfMissing: false),
        let entryIndex = learningMemoryStates[stateIndex].entries.firstIndex(where: { $0.id == memoryID }) else {
            return false
        }
        let previousState = learningMemoryStates[stateIndex]
        let previousContextRevision = agentContextRevision
        learningMemoryStates[stateIndex].entries.remove(at: entryIndex)
        learningMemoryStates[stateIndex].revision &+= 1
        let deletedState = learningMemoryStates[stateIndex]
        invalidateAgentContext()
        guard flushPendingWorkspaceSave() else {
            var rollbackApplied = false
            if learningMemoryStates[stateIndex] == deletedState {
                learningMemoryStates[stateIndex] = previousState
                if agentContextRevision == previousContextRevision &+ 1 {
                    agentContextRevision = previousContextRevision
                }
                rollbackApplied = true
            }
            let rollbackPersisted = rollbackApplied
                && flushPendingWorkspaceSave()
            if !rollbackPersisted {
                WeiBeiLog.workspace.error(
                    "code=learning_memory_delete_rollback_unverified scope=\(String(describing: scope), privacy: .private) memory=\(memoryID.uuidString, privacy: .private) rollback_applied=\(rollbackApplied, privacy: .public)"
                )
            }
            return false
        }
        return true
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
            // 锚点优先(同处原文续同线程),文字匹配兜底。
            selection.documentAnchor?.matches($0.documentAnchor) == true
                || ($0.normalizedText == normalized
                    && $0.source == selection.source
                    && ($0.itemID == nil || $0.itemID == itemID || itemID == nil))
        }) {
            selectionAskThreads[index].updatedAt = Date()
            selectionAskThreads[index].itemID = selectionAskThreads[index].itemID ?? itemID
            selectionAskThreads[index].documentAnchor = selectionAskThreads[index].documentAnchor ?? selection.documentAnchor
            save()
            return selectionAskThreads[index]
        }
        let thread = SelectionAskThread(
            selectionText: selection.text,
            source: selection.source,
            ownerTitle: selection.ownerTitle,
            itemID: itemID,
            documentAnchor: selection.documentAnchor
        )
        selectionAskThreads.insert(thread, at: 0)
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
        noteEditorCommand = NoteEditorCommand(kind: .insertMarkdown, markdown: block)
        focus(.notes)
    }

    func applyLastAgentAnswerToNote() {
        guard let content = lastAgentAnswerContentForCurrentNote() else { return }
        let block = "\n\n\(noteBlockForAgentAnswer(content))"
        noteEditorCommand = NoteEditorCommand(kind: .insertMarkdown, markdown: block)
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

    func submitAgentDraft(targetCourseID: UUID? = nil) {
        if isAgentRunningInActiveChat {
            cancelAgentRequest()
            return
        }
        let question = (pendingComposerDraft ?? agentDraft).trimmingCharacters(in: .whitespacesAndNewlines)
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
              !(pendingComposerDraft ?? agentDraft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let targetCourseID = pendingAgentSwitchCourseID
        dismissAgentSwitchConfirmation()
        stopAgent(restoreDraft: false) { [weak self] in
            guard let self,
                  self.activeStudySessionID == targetID,
                  self.studySessions.contains(where: { $0.id == targetID }),
                  !(self.pendingComposerDraft ?? self.agentDraft).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.askAgent(targetCourseID: targetCourseID)
        }
    }

    @discardableResult
    func askAgent(
        reusingLastUserMessage: Bool = false,
        replayingSelections: [SelectionContext]? = nil,
        targetCourseID: UUID? = nil,
        visibleQuestionOverride: String? = nil,
        questionOverride: String? = nil
    ) -> String? {
        let question = (questionOverride ?? pendingComposerDraft ?? agentDraft)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard agentRequestTask == nil,
              !isStoppingAgent,
              !isAskingAgent,
              !question.isEmpty else {
            return ui("当前无法提交这条回答。", "This response cannot be submitted right now.")
        }
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
            let reason = Self.userFacingAgentFailureDetail(for: error)
                ?? ui("魏碑无法准备这次回答。", "WeiBei could not prepare this response.")
            recordAgentTargetFailure(
                question: question,
                error: error,
                appendUserMessage: !reusingLastUserMessage,
                targetCourseID: targetCourseID,
                visibleQuestion: visibleQuestionOverride,
                preserveComposerDraft: questionOverride != nil
            )
            return reason
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
        return nil
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
        let chatsRoot = workspaceDirectory
            .appendingPathComponent("AgentRuntime/Chats", isDirectory: true)
        let runtimeDirectory = chatsRoot
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
        do {
            try WeiBeiAgentDataPaths.ensureOwnedDirectory(
                chatsRoot,
                inside: workspaceDirectory
            )
            try WeiBeiAgentDataPaths.ensureOwnedDirectory(
                runtimeDirectory,
                inside: workspaceDirectory
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: runtimeDirectory.path
            )
        } catch {
            WeiBeiLog.workspace.error(
                "code=agent_chat_directory_unavailable underlying=\(WeiBeiLog.code(error), privacy: .public)"
            )
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
        _ = try? await noteEditingSession.snapshot()
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
            ?? latestConfirmedAgentNoteItem(in: target)
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
        let sentCourseProfile = makeCourseProfileContext(courseID: target.courseID)
        let sentVisualAssets = await currentVisualAssetsForAgent(access: projectAccess)
        defer { Self.removeAgentVisualSnapshots(sentVisualAssets) }
        let sentLanguage = interfaceLanguage
        let courseQuery = [question, sentSelectionText ?? ""]
            .joined(separator: "\n\n")
        isAskingAgent = true
        activeAgentRequestID = requestID
        settleAgentStreamingDisplayImmediately()
        latestAgentStreamingText = ""
        lastAgentStreamingPublishNanoseconds = 0
        agentStreamingDisplayPump.stopAndReset()
        agentVisualizationIDsUpdatingHistory = []
        agentStreaming.reset()
        agentStreaming.activityText = ui("正在准备课程现场", "Preparing course context")
        defer {
            if activeAgentRequestID == requestID {
                activeAgentRequestID = nil
                activeAgentReplyMessageID = nil
                activeAgentReplyChatID = nil
                isAskingAgent = false
                lastAgentStreamingPublishNanoseconds = 0
                agentVisualizationIDsUpdatingHistory = []
                agentStreaming.activityText = nil
                agentRequestTask = nil
                if agentStreaming.displayingMessageID == nil {
                    latestAgentStreamingText = ""
                    agentStreamingDisplayPump.stopAndReset()
                }
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
            // Never flushPendingWorkspaceSave() here: RunLoop-spin on MainActor = deadlock.
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
                backend: .native,
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
            agentStreaming.begin(
                messageID: assistantMessage.id,
                chatID: target.sessionID
            )
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
                agentDraft = ""; pendingComposerDraft = nil
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
                confirmedNotes: confirmedAgentNotes(in: target)
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
            let memoryUpdate = reply.appliedMemoryUpdate ?? applyLearningUpdate(
                reply.learningUpdate,
                expectedContextRevision: request.contextRevision,
                expectedMemoryRevision: requestMemoryRevision,
                expectedUserQuestion: request.question,
                target: target,
                messageID: assistantMessage.id
            )
            let profileUpdate = reply.appliedProfileUpdate ?? applyCourseProfileUpdate(
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
               sentNoteItemID != nil || target.courseID != nil {
                actions.append(
                    AgentReplyAction(
                        kind: .writeNote,
                        targetItemID: sentNoteItemID,
                        sourceItemID: sentMaterialItemID,
                        proposedMarkdown: proposal.markdown,
                        evidence: proposal.evidence,
                        contextRevision: proposal.contextRevision,
                        baselineContentDigest: sentNoteItemID == nil
                            ? Self.noteContentDigest(Data())
                            : Self.noteContentDigest(Data(sentNoteText.utf8))
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
                latestAgentStreamingText = reply.text
                _ = updateAgentMessage(messageID, in: target.sessionID) {
                    $0.text = reply.text
                    $0.contentBlocks = visibleContentBlocks
                    $0.backend = reply.backend
                    $0.completionState = .completed
                    $0.sources = sources
                    $0.actions = actions
                    $0.memoryUpdate = memoryUpdate
                    $0.profileUpdate = profileUpdate
                    $0.failureKind = nil
                    $0.retryQuestion = nil
                    $0.toolTrace = reply.toolTrace
                }
                if agentStreaming.isDisplaying(messageID) {
                    if agentStreamingUsesReducedMotion
                        || !isAgentStreamingSurfaceVisible
                        || agentStreaming.displayingChatID != activeStudySessionID {
                        agentStreamingDisplayPump.replaceImmediately(
                            cumulativeText: reply.text
                        )
                    }
                    agentStreamingDisplayPump.finish(cumulativeText: reply.text)
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
            // Durable reply before request finish; save errors must not hide it.
            _ = await flushPendingWorkspaceSaveAsync()
        } catch is CancellationError {
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
            let failureText = Self.agentFailureMessage(
                for: error,
                kind: kind,
                language: interfaceLanguage
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
        settleAgentStreamingDisplayImmediately()
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
    func cancelAgentRequestIfRunning(
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
        agentStreamingDisplayPump.stopAndReset()
        agentStreaming.activityText = nil
        agentStopTask?.cancel()
        agentStopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.cancelStudyAgentRuntimes()
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
                backend: .native
            )
        }
#endif
        return try await dispatchStudyAgentRequest(
            request,
            provider: selectedProvider,
            target: target,
            replyMessageID: replyMessageID,
            hostToolHandler: hostToolHandler
        )
    }

    func shutdownAgentRuntime() {
        let span = WeiBeiPerf.begin("agent.shutdown")
        agentRequestTask?.cancel()
        agentStopTask?.cancel()
        WeiBeiPerf.end(span, extra: "outcome=completed")
    }

    func applyAgentProgress(
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
            case "weibei_course_search", "weibei_search_workspace":
                base = ui("正在搜索", "Searching")
            case "weibei_course_read":
                base = ui("正在读取", "Reading")
            case "weibei_course_map":
                base = ui("正在查找课程关联", "Finding course connections")
            case "weibei_read_learning_memory":
                base = ui("正在回顾学习记忆", "Reviewing learning memory")
            case "weibei_update_learning_memory":
                base = ui("正在整理学习进展", "Updating study progress")
            case "weibei_course_profile_update":
                base = ui("正在更新课程知识档案", "Updating course profile")
            case "weibei_note_proposal":
                base = ui("正在整理写入建议", "Preparing a note proposal")
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
            if agentStreaming.isDisplaying(replyMessageID) {
                let canPaceVisibleReply = !agentStreamingUsesReducedMotion
                    && isAgentStreamingSurfaceVisible
                    && agentStreaming.displayingChatID == activeStudySessionID
                if canPaceVisibleReply {
                    agentStreamingDisplayPump.enqueue(cumulativeText: text)
                } else {
                    agentStreamingDisplayPump.replaceImmediately(cumulativeText: text)
                }
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agentReplyIDsThatDisplayedStreamingText.insert(replyMessageID)
            }
            let now = DispatchTime.now().uptimeNanoseconds
            if updatesVisibleChat,
               now &- lastAgentStreamingPublishNanoseconds >= 33_000_000 {
                lastAgentStreamingPublishNanoseconds = now
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

    func resolveCourseOwnedFile(
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
            role: CourseOwnedFileRole(item: importedItems[index]),
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
            WeiBeiLog.workspace.notice("course_file_identity_refreshed")
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

    func uniqueCourseOwnedMembershipIndex(
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
              course.sourceRootIdentity != nil,
              let root = courseRootURL(for: courseID),
              let rootIdentity = importedFileIdentityResolver(root),
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
              let fileIdentity = importedFileIdentityResolver(resolvedURL) else {
            return nil
        }
        // identity 只用于尽力找回、永不用于拒绝（存储简化红线，与
        // resolveTrackedImportedFile 一致）：课程内文件以课程相对路径为准，
        // 路径下文件可读即接受。identity 不一致（iCloud 驱逐重下换 inode、
        // APFS 卷号漂移等）时刷新记录并继续，最多记一条日志（计划 §5 阶段5）。
        if course.sourceRootIdentity != rootIdentity {
            if let courseIndex = courses.firstIndex(where: { $0.id == courseID }) {
                courses[courseIndex].sourceRootIdentity = rootIdentity
            }
            WeiBeiLog.workspace.notice("note_access_root_identity_refreshed")
        }
        if item.importedFileIdentity != fileIdentity {
            if let itemIndex = importedItems.firstIndex(where: { $0.id == item.id }) {
                importedItems[itemIndex].importedFileIdentity = fileIdentity
            }
            WeiBeiLog.workspace.notice("note_access_file_identity_refreshed")
        }
        if courseItemMemberships[membershipIndex].entryIdentity != fileIdentity {
            courseItemMemberships[membershipIndex].entryIdentity = fileIdentity
        }
        return VerifiedCourseOwnedNoteAccess(
            courseID: courseID,
            root: root,
            rootIdentity: rootIdentity,
            url: resolvedURL,
            fileIdentity: fileIdentity,
            membershipIndex: membershipIndex
        )
    }

    func safeCourseOwnedFileURL(
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
                role: CourseOwnedFileRole(item: importedItems[index]),
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

    func rebuildCourseMembershipsFromStorage() {
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
        workspaceSaveFailure = nil
    }

    @discardableResult func reportWorkspaceSaveFailure(_ kind: WorkspaceSaveFailure.Kind, _ userMessage: String, reason: String? = nil) -> String {
        WeiBeiLog.workspace.error(
            "code=workspace_save_failed path=\(self.storageURL.path, privacy: .private) reason=\(reason ?? userMessage, privacy: .private)"
        )
        appendWorkspaceSaveFailureLog(userMessage)
        workspaceSaveFailure = WorkspaceSaveFailure(kind: kind, message: userMessage)
        return userMessage
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

    func invalidateAgentContext(restoreAgentDraft _: Bool = true) {
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
        guard !libraryMigrationInFlight else { return }
        guard let access = verifiedCourseOwnedNoteAccess(
            item
        ) else {
            return
        }
        if case .presentUnmaterialized = CourseProjectFileWorker.entryPresence(at: access.url) {
            setNoteFileError(
                ui("正在从 iCloud 下载…", "Downloading from iCloud…"),
                for: item.id
            )
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
                fileMissingSinceByItemID.removeValue(forKey: itemID)
                if let previousDigest,
                   previousDigest != result.snapshot.sha256 {
                    backUpUnsavedNoteContentBeforeAdopting(itemID: itemID)
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
                let presence = CourseProjectFileWorker.entryPresence(at: url)
                let unmaterialized: Bool = {
                    if case .presentUnmaterialized = presence { return true }
                    return false
                }()
                setNoteFileError(
                    unmaterialized
                        ? ui(
                            "当前不可用，iCloud 文件未下载。",
                            "Currently unavailable; the iCloud file has not been downloaded."
                        )
                        : ui(
                            "无法读取原 Markdown：\(url.lastPathComponent)",
                            "Could not read original Markdown: \(url.lastPathComponent)"
                        ),
                    for: itemID
                )
            }
        }
    }

    func noteText(for item: StudyItem?) -> String {
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
                // P0 降级标记：展示的是模板而非正文；留痕让写回守卫拒绝把模板盖回磁盘。
                setNoteFileError(noteFileUnavailableMessage(for: item), for: item.id)
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
            showImportantOperationError(ui("无法读取原 Markdown：\(url.lastPathComponent)", "Could not read original Markdown: \(url.lastPathComponent)"))
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
        guard notesByItemID[itemID] == nil,
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

    func load() {
        let data = restoredSnapshotDataOrNotice(storageURL: storageURL)
        guard let data,
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
        applyStudySessionsFromSnapshot(snapshot)
        studySessionScopeMigrationVersion = snapshot.studySessionScopeMigrationVersion ?? 0
        activeStudySessionID = snapshot.activeStudySessionID
        if let persistedSelectionAskThreads = snapshot.selectionAskThreads {
            loadedSelectionAskThreadsFromWorkspaceSnapshot = true
            selectionAskThreads = persistedSelectionAskThreads
            selectionAskThreadDefaults.removeObject(forKey: Self.legacySelectionAskThreadsDefaultsKey)
        }
        selectionRemarkRecords = snapshot.selectionRemarkRecords ?? selectionRemarkRecords
        if selectedItem?.isCourseMaterial == false,
           selectedItem?.isNotebookNote == true {
            activeNotebookItemID = selectedItemID
            selectedItemID = nil
        }
        if let activeNotebookItemID,
           !allItems.contains(where: { $0.id == activeNotebookItemID && $0.isNotebookNote }) {
            self.activeNotebookItemID = nil
        }
        materialNotePairings = materialNotePairings.filter {
            $0.key != $0.value && item(withID: $0.key)?.isCourseMaterial == true
                && item(withID: $0.value)?.isNotebookNote == true
        }
        noteMaterialPairings = noteMaterialPairings.filter {
            $0.key != $0.value && item(withID: $0.key)?.isNotebookNote == true
                && item(withID: $0.value)?.isCourseMaterial == true
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
        // Legacy field: still read for older workspaces; threePaneOrder now owns drag order.
        var migratedRetiredSplitLayout = false
        if let persistedLayoutRaw = snapshot.workspaceLayout {
            if let workspaceLayout = WorkspaceLayout.resolve(persistedValue: persistedLayoutRaw) {
                layout = workspaceLayout
                if let order = workspaceLayout.defaultThreePaneOrder {
                    threePaneOrder = order
                }
            } else if persistedLayoutRaw == WorkspaceLayout.retiredSplitPersistedValue {
                migratedRetiredSplitLayout = true
            }
        }
        if let threePaneOrder = snapshot.threePaneOrder {
            self.threePaneOrder = WorkspacePaneRole.normalized(threePaneOrder)
        }
        if let agentSurface = snapshot.agentSurface {
            self.agentSurface = agentSurface == .selectionFloat ? .hidden : agentSurface
        }
        let legacyRightPane = snapshot.showRightPane
        showReader = snapshot.showReader ?? true
        showAgent = snapshot.showAgent ?? legacyRightPane ?? true
        showNotes = snapshot.showNotes ?? legacyRightPane ?? true
        showDailyInspiration = snapshot.showDailyInspiration ?? true
        if migratedRetiredSplitLayout {
            // Retired 对半布局 → workbench：阅读+笔记可见、对话隐藏，保留既有自由顺序。
            layout = layoutMatchingThreePaneOrder(self.threePaneOrder)
            showReader = true
            showNotes = true
            showAgent = false
        }
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
        if let interfaceTextScaleRaw = snapshot.interfaceTextScaleRaw,
           let interfaceTextScale = WeiBeiTypography.TextScale(rawValue: interfaceTextScaleRaw) {
            self.interfaceTextScale = interfaceTextScale
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
        }.map(sessionMessagePersistence.annotatingMessageCount)
    }

    private var persistedActiveStudySessionID: UUID? {
        let sessions = persistedStudySessions
        guard sessions.contains(where: { $0.id == activeStudySessionID }) else {
            return sessions.max(by: { $0.updatedAt < $1.updatedAt })?.id
        }
        return activeStudySessionID
    }

    private var persistableCourses: [Course] {
        courses.map { course in
            var next = course
            next.sourceRootPath = nil
            next.sourceRootBookmarkData = nil
            return next
        }
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
                selectionRemarkRecords: selectionRemarkRecords,
                modelName: modelName,
                agentProviderID: agentProviderID.rawValue,
                agentBaseURL: agentBaseURL.isEmpty ? nil : agentBaseURL,
                workspaceLayout: layout.rawValue,
                threePaneOrder: normalizedThreePaneOrder,
                agentSurface:
                    agentSurface == .selectionFloat ? .hidden : agentSurface,
                showLibrary: nil,
                showReader: showReader,
                showAgent: showAgent,
                showNotes: showNotes,
                showRightPane: showRightPane,
                showDailyInspiration: showDailyInspiration,
                appearanceModeRaw: appearanceMode.rawValue,
                adaptImportedDocumentColors: adaptImportedDocumentColors,
                interfaceLanguageRaw: interfaceLanguage.rawValue,
                interfaceTextScaleRaw: interfaceTextScale.rawValue
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
        workspace.selectionRemarkRecords = workspace.selectionRemarkRecords?.filter {
            $0.itemID.map(removedItemIDs.contains) != true
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
        let sessionPayloads = try sessionMessageWrites(
            for: persisted.snapshot.studySessions ?? []
        )
        return (
            WorkspacePersistenceRequest(
                generation: generation,
                workspace: persisted.snapshot,
                courseItemMemberships: courseItemMemberships,
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
                needsPortableBootstrap: needsPortableCourseStateBootstrap,
                sessionMessageWrites: sessionPayloads.writes,
                sessionMessageDeletions: sessionPayloads.deletions
            ),
            persisted.resumePoints
        )
    }

    nonisolated private static func writeWorkspaceSnapshot(_ data: Data, to url: URL) throws {
        WorkspaceSnapshotRecovery.rotateBackups(primary: url)
        try data.write(to: url, options: [.atomic])
    }

    /// Queue a coalesced snapshot write. Call a flush API when the caller needs a disk receipt.
    func save() {
        scheduleDebouncedWorkspaceSave()
    }

    /// Flush any coalesced save (quit / resign active / note flush / agent send).
    @discardableResult
    func flushPendingWorkspaceSave() -> Bool {
        checkpointActiveAgentStreamingText()
        pendingWorkspaceSaveTask?.cancel()
        pendingWorkspaceSaveTask = nil
        workspaceSaveGeneration &+= 1
        workspacePersistenceSkippingCourseIDs = []
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
        return await startWorkspacePersistenceLoop().value
    }

    func persistWorkspaceRemovingCourse(
        _ courseID: UUID
    ) async -> Bool {
        guard workspacePersistenceRemovingCourseID == nil else {
            return false
        }
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
            noteEditorWorkspaceSaveFailed(reportWorkspaceSaveFailure(.coursePortableStateUnsaved, ui(
                "课程可携带状态没有成功保存。本次修改仍在当前会话中，但尚未安全保存；请不要关闭并重试。",
                "Portable course state was not saved. This change remains in the current session but is not safely stored yet; do not close it, and retry."
            ), reason: error.localizedDescription))
            return false
        }
        let noteEditorSaveReceipt = makeNoteEditorWorkspaceSaveReceipt(
            prepared.request.workspace
        )
        let result = await courseProjectFileWorker.persistWorkspace(
            prepared.request,
            portableStateWriter: {
                [coursePortableStateWriter, courseProjectMutationHook]
                data, url, directoryIdentity, previousData in
                try coursePortableStateWriter(
                    data,
                    url,
                    directoryIdentity,
                    previousData
                ) {
                    try courseProjectMutationHook(
                        .beforeCoursePortableStateCASPlacement
                    )
                }
            },
            workspaceSnapshotWriter: workspaceSnapshotWriter
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
        // A newer in-memory generation may arrive while this transaction is on disk;
        // keep the committed CAS baseline or the next compare falsely reports conflict.
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
        if let failure = result.failure {
            switch failure {
            case .portableState(let detail):
                noteEditorWorkspaceSaveFailed(reportWorkspaceSaveFailure(.coursePortableStateUnsaved, ui(
                    "课程可携带状态没有成功保存。本次修改仍在当前会话中，但尚未安全保存；请不要关闭并重试。",
                    "Portable course state was not saved. This change remains in the current session but is not safely stored yet; do not close it, and retry."
                ), reason: detail))
            case .workspace(let detail):
                noteEditorWorkspaceSaveFailed(reportWorkspaceSaveFailure(.workspaceChangesUnwritten, ui(
                    "课程更改尚未写入磁盘。本次修改仍在当前会话中，但尚未安全保存；请不要关闭并重试。",
                    "Course changes were not saved to disk. This change remains in the current session but is not safely stored yet; do not close it, and retry."
                ), reason: detail))
            case .rollbackConflict:
                noteEditorWorkspaceSaveFailed(reportWorkspaceSaveFailure(.courseStateConcurrentConflict, ui(
                    "课程状态提交时检测到并发变更，魏碑已停止覆盖。本次修改仍在当前会话中；请先处理冲突，再重试。",
                    "A concurrent change was detected while committing course state, so WeiBei stopped overwriting. This change remains in the current session; resolve the conflict, then retry."
                )))
            case .stale:
                publishOutcome = "superseded"
                return true
            }
            return false
        }
        guard workspaceSaveGeneration == generation else {
            publishOutcome = "superseded"
            return true
        }
        courseResumePoints = prepared.resumePoints
        noteSuccessfulSessionMessagePersist(writes: prepared.request.sessionMessageWrites, deletions: prepared.request.sessionMessageDeletions)
        if !oversizedPortableCourseIDs.isEmpty {
            reportWorkspaceSaveFailure(.coursePortableStateOversized, ui(
                "工作区内容已保存，但有课程的可携带状态超过 32 MB；课程文件夹中的原状态保持不变。请精简课程 Chat 或未写入草稿后重试。",
                "The workspace was saved, but a portable course state exceeds 32 MB. The state in the course folder was left unchanged. Reduce course chats or pending drafts, then retry."
            ))
        } else if !blockedPortableCourseIDs.isEmpty {
            reportWorkspaceSaveFailure(.coursePortableStateBlocked, ui(
                "工作区内容已保存，但课程文件夹中的课程状态无法安全更新；原状态已保留。请处理冲突或损坏后重试。",
                "The workspace was saved, but the course state in the course folder could not be updated safely. The original state was preserved. Resolve the conflict or damage, then retry."
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
        noteEditorDidPersistWorkspace(noteEditorSaveReceipt)
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
            var observedRealFailure = false
            let failureObservation = self.$workspaceSaveFailure.sink {
                if $0 != nil { observedRealFailure = true }
            }
            defer { withExtendedLifetime(failureObservation) {} }
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
            await self.courseProjectFileWorker
                .failWorkspacePersistenceForSelfCheck(
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
                    == (initialRevision ?? 0) + 1
                && observedRealFailure
                && self.blockedPortableCourseIDs
                    .contains(untouchedCourseID)
                && self.oversizedPortableCourseIDs
                    .contains(untouchedCourseID)
        }
    }
#endif

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
