import Foundation

/// 标识一个由魏碑应用内置测试钩子执行的验收场景。
public enum VerificationScenarioID: String, CaseIterable, Codable, Sendable {
    case offlineLearningFlow = "offline-learning-flow"
    case immersiveConversationFlow = "immersive-conversation-flow"
    case emptyWorkspaceInspirationOff = "empty-workspace-inspiration-off"
    case emptyWorkspaceOpenDoc = "empty-workspace-open-doc"
    case emptyWorkspaceOpenChat = "empty-workspace-open-chat"
    case emptyWorkspaceOpenNotes = "empty-workspace-open-notes"
    case linkedSourcesFlow = "linked-sources-flow"
    case courseWorkspaceOverviewFlow = "course-workspace-overview-flow"
    case courseWorkspaceWorkflowFlow = "course-workspace-workflow-flow"
    case paneToggleContinuityFlow = "pane-toggle-continuity-flow"
    case paneLayoutStabilityFlow = "pane-layout-stability-flow"
    case paneReorderWidthFlow = "pane-reorder-width-flow"
    case readerScrollPersistenceFlow = "reader-scroll-persistence-flow"

    case emptyWorkspaceLightWide = "empty-workspace-light-wide"
    case emptyWorkspaceLightNarrow = "empty-workspace-light-narrow"
    case emptyWorkspaceDarkWide = "empty-workspace-dark-wide"
    case emptyWorkspaceDarkNarrow = "empty-workspace-dark-narrow"
    case emptyWorkspaceCalligraphyLight = "empty-workspace-calligraphy-light"
    case emptyWorkspaceCalligraphyDark = "empty-workspace-calligraphy-dark"
    case notebookCreationFlow = "notebook-creation-flow"
    case pureWritingFlow = "pure-writing-flow"
    case contentRailDormantPreview = "content-rail-dormant-preview"
    case contentRailActivationPreview = "content-rail-activation-preview"
    case loadingIndicatorSamples = "loading-indicator-samples"

    case piLearningFlow = "pi-learning-flow"
    case piCourseMemoryFlow = "pi-course-memory-flow"
}

/// 描述场景运行所需能力。
public struct VerificationScenarioRequirements: Equatable, Codable, Sendable {
    public let requiresOnlinePI: Bool
    public let requiresVisualInspection: Bool

    /// 创建场景能力要求。
    public init(requiresOnlinePI: Bool = false, requiresVisualInspection: Bool = false) {
        self.requiresOnlinePI = requiresOnlinePI
        self.requiresVisualInspection = requiresVisualInspection
    }
}

/// 指定场景完成后应验证的应用产物。
public enum VerificationResultContract: String, Codable, Sendable {
    case offlineLearning
    case emptyWorkspace
    case linkedSources
    case courseWorkspaceOverview
    case courseWorkspaceWorkflow
    case paneToggleContinuity
    case paneLayoutStability
    case paneReorderWidth
    case readerScrollPersistence
    case piLearning
    case piCourseMemory
    case visualOnly
}

/// 包含运行场景所需的稳定元数据。
public struct VerificationScenario: Equatable, Codable, Sendable {
    public let id: VerificationScenarioID
    public let timeoutSeconds: TimeInterval
    public let requirements: VerificationScenarioRequirements
    public let resultContract: VerificationResultContract
    public let isDefault: Bool

    /// 创建类型化验收场景。
    public init(
        id: VerificationScenarioID,
        timeoutSeconds: TimeInterval,
        requirements: VerificationScenarioRequirements,
        resultContract: VerificationResultContract,
        isDefault: Bool
    ) {
        self.id = id
        self.timeoutSeconds = timeoutSeconds
        self.requirements = requirements
        self.resultContract = resultContract
        self.isDefault = isDefault
    }
}

/// 提供 CLI 与验证工作流共享的场景注册表。
public struct VerificationScenarioRegistry: Sendable {
    public let scenarios: [VerificationScenario]

    /// 创建注册表，并拒绝重复场景标识。
    public init(scenarios: [VerificationScenario] = Self.builtInScenarios) {
        precondition(Set(scenarios.map(\.id)).count == scenarios.count, "Verification scenario identifiers must be unique.")
        self.scenarios = scenarios
    }

    /// 返回默认运行的十三个离线行为场景。
    public var defaultScenarios: [VerificationScenario] {
        scenarios.filter(\.isDefault)
    }

    /// 返回全部场景；在线场景仅在调用方明确允许时出现。
    public func allScenarios(includeLivePI: Bool) -> [VerificationScenario] {
        scenarios.filter { includeLivePI || !$0.requirements.requiresOnlinePI }
    }

    /// 按命令行中的稳定标识查找场景。
    public func scenario(named name: String) -> VerificationScenario? {
        scenarios.first { $0.id.rawValue == name }
    }

    /// 内置场景及其与旧验证脚本一致的最大等待时间。
    public static let builtInScenarios: [VerificationScenario] = [
        .init(id: .offlineLearningFlow, timeoutSeconds: 6, requirements: .init(), resultContract: .offlineLearning, isDefault: true),
        .init(id: .immersiveConversationFlow, timeoutSeconds: 6, requirements: .init(), resultContract: .offlineLearning, isDefault: true),
        .init(id: .emptyWorkspaceInspirationOff, timeoutSeconds: 6, requirements: .init(), resultContract: .emptyWorkspace, isDefault: true),
        .init(id: .emptyWorkspaceOpenDoc, timeoutSeconds: 6, requirements: .init(), resultContract: .emptyWorkspace, isDefault: true),
        .init(id: .emptyWorkspaceOpenChat, timeoutSeconds: 6, requirements: .init(), resultContract: .emptyWorkspace, isDefault: true),
        .init(id: .emptyWorkspaceOpenNotes, timeoutSeconds: 6, requirements: .init(), resultContract: .emptyWorkspace, isDefault: true),
        .init(id: .linkedSourcesFlow, timeoutSeconds: 6, requirements: .init(), resultContract: .linkedSources, isDefault: true),
        .init(id: .courseWorkspaceOverviewFlow, timeoutSeconds: 30, requirements: .init(), resultContract: .courseWorkspaceOverview, isDefault: true),
        .init(id: .courseWorkspaceWorkflowFlow, timeoutSeconds: 30, requirements: .init(), resultContract: .courseWorkspaceWorkflow, isDefault: true),
        .init(id: .paneToggleContinuityFlow, timeoutSeconds: 360, requirements: .init(), resultContract: .paneToggleContinuity, isDefault: true),
        .init(id: .paneLayoutStabilityFlow, timeoutSeconds: 36, requirements: .init(), resultContract: .paneLayoutStability, isDefault: true),
        .init(id: .paneReorderWidthFlow, timeoutSeconds: 36, requirements: .init(), resultContract: .paneReorderWidth, isDefault: true),
        .init(id: .readerScrollPersistenceFlow, timeoutSeconds: 24, requirements: .init(), resultContract: .readerScrollPersistence, isDefault: true),

        .init(id: .emptyWorkspaceLightWide, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .emptyWorkspaceLightNarrow, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .emptyWorkspaceDarkWide, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .emptyWorkspaceDarkNarrow, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .emptyWorkspaceCalligraphyLight, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .emptyWorkspaceCalligraphyDark, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .notebookCreationFlow, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .pureWritingFlow, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .contentRailDormantPreview, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .contentRailActivationPreview, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),
        .init(id: .loadingIndicatorSamples, timeoutSeconds: 10, requirements: .init(requiresVisualInspection: true), resultContract: .visualOnly, isDefault: false),

        .init(id: .piLearningFlow, timeoutSeconds: 120, requirements: .init(requiresOnlinePI: true), resultContract: .piLearning, isDefault: false),
        .init(id: .piCourseMemoryFlow, timeoutSeconds: 120, requirements: .init(requiresOnlinePI: true), resultContract: .piCourseMemory, isDefault: false)
    ]
}
