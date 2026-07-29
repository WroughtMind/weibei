import Foundation
import WeiBeiCore

/**
 * Encapsulates launch behavior that depends on process configuration.
 */
enum AppLaunchPolicy {
    /**
     * Returns whether a launch may activate the application and install interactive shortcuts.
     *
     * @param environment - Process environment used for the launch
     * @returns `false` for a non-invasive verification launch
     */
    static func shouldActivate(environment: [String: String]) -> Bool {
        environment["WEIBEI_SUPPRESS_ACTIVATION"] != "1"
    }
}

/**
 * Describes the action needed when macOS asks the app to reopen.
 */
enum MainWindowReopenAction: Equatable {
    case none
    case showExistingWindow
    case openMainWindow
}

/**
 * Selects a deterministic reopen action without depending on AppKit window instances.
 */
enum MainWindowReopenPolicy {
    /**
     * Resolves how the application should respond to a Dock reopen request.
     *
     * @param hasVisibleWindows - Whether macOS already has a visible application window
     * @param hasReusableWindow - Whether a hidden or minimized key-capable window can be restored
     * @returns The single window action the delegate should perform
     */
    static func action(hasVisibleWindows: Bool, hasReusableWindow: Bool) -> MainWindowReopenAction {
        guard !hasVisibleWindows else { return .none }
        return hasReusableWindow ? .showExistingWindow : .openMainWindow
    }
}

/**
 * Captures semantic appearance-transition behavior independently of SwiftUI animation state.
 */
enum AppearanceTransitionPolicy {
    /**
     * Returns whether changing modes crosses the light/dark family boundary and needs a wash.
     *
     * @param oldMode - Appearance mode being left
     * @param newMode - Appearance mode being entered
     * @returns `true` only for a light-to-dark or dark-to-light transition
     */
    static func stagesWash(from oldMode: WeiBeiAppearanceMode, to newMode: WeiBeiAppearanceMode) -> Bool {
        oldMode.isDark != newMode.isDark
    }
}

/**
 * Defines visibility decisions shared by top chrome and the global selection agent.
 */
enum AppChromePolicy {
    /**
     * Returns whether the material-scoped search action belongs in the top bar.
     *
     * @param hasSelectedMaterial - Whether a material is currently selected
     * @param readerIsActive - Whether the reader pane is part of the active workspace
     * @returns `true` when search has both a material and an active reader destination
     */
    static func showsReaderSearchAction(hasSelectedMaterial: Bool, readerIsActive: Bool) -> Bool {
        hasSelectedMaterial && readerIsActive
    }

    /**
     * Returns whether the global selection agent should be presented over the workspace.
     *
     * @param courseWorkspacePresented - Whether the course workspace temporarily owns the window
     * @param canShowSelectionPromptSurface - Whether the store permits a selection prompt
     * @param surface - Current agent presentation surface
     * @param hasSelection - Whether a selection or retained answer is available
     * @param hasAnchor - Whether a live selection has a screen anchor
     * @param pinned - Whether the floating agent is pinned
     * @param keepOpen - Whether an answer is retaining the floating agent
     * @returns `true` when both application chrome and placement policies permit presentation
     */
    static func showsGlobalFloatingAgent(
        courseWorkspacePresented: Bool,
        canShowSelectionPromptSurface: Bool,
        surface: AgentSurface,
        hasSelection: Bool,
        hasAnchor: Bool,
        pinned: Bool,
        keepOpen: Bool
    ) -> Bool {
        !courseWorkspacePresented
            && canShowSelectionPromptSurface
            && SelectionFloatingAgentPlacement.isVisible(
                surface: surface,
                hasSelection: hasSelection,
                hasAnchor: hasAnchor,
                pinned: pinned,
                keepOpen: keepOpen
            )
    }
}

/**
 * Stable semantic entries shown when every document pane is closed.
 */
enum EmptyWorkspaceEntry: CaseIterable, Equatable {
    case document
    case chat
    case notes

    /// Short product label rendered in the empty workspace.
    var title: String {
        switch self {
        case .document: "DOC"
        case .chat: "CHAT"
        case .notes: "NOTES"
        }
    }

    /// Accessibility identifier used by real-window verification.
    var accessibilityIdentifier: String {
        switch self {
        case .document: "empty-workspace-entry-doc"
        case .chat: "empty-workspace-entry-chat"
        case .notes: "empty-workspace-entry-notes"
        }
    }

    /// Pane toggled by this entry.
    var paneRole: WorkspacePaneRole {
        switch self {
        case .document: .reader
        case .chat: .agent
        case .notes: .notes
        }
    }
}

/**
 * Identifies the application-owned Agent workflow for a verification scenario.
 */
enum AgentVerificationFlow: Equatable {
    case offlineLearning
    case piLearning
    case piCourseMemory

    /// Whether the flow must wait for reader-backed context before asking the Agent.
    var waitsForReaderContext: Bool {
        self == .piLearning || self == .piCourseMemory
    }
}

/**
 * Keeps CLI scenario names and application Agent routing behind one testable boundary.
 */
enum AgentVerificationScenarioPolicy {
    /**
     * Resolves a scenario name to the Agent workflow executed by WorkspaceStore.
     *
     * @param scenario - Scenario identifier supplied by the verification runner
     * @returns The matching Agent flow, or nil for a non-Agent scenario
     */
    static func flow(for scenario: String) -> AgentVerificationFlow? {
        switch scenario {
        case "offline-learning-flow": .offlineLearning
        case "pi-learning-flow": .piLearning
        case "pi-course-memory-flow": .piCourseMemory
        default: nil
        }
    }
}
