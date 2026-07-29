import XCTest
@testable import WeiBei

final class AppPolicyTests: XCTestCase {
    /**
     * Verifies that only an explicit non-invasive verification launch suppresses activation.
     */
    func testLaunchActivationPolicyRequiresExplicitSuppression() {
        XCTAssertTrue(AppLaunchPolicy.shouldActivate(environment: [:]))
        XCTAssertTrue(AppLaunchPolicy.shouldActivate(environment: ["WEIBEI_SUPPRESS_ACTIVATION": "0"]))
        XCTAssertTrue(AppLaunchPolicy.shouldActivate(environment: ["WEIBEI_SUPPRESS_ACTIVATION": "true"]))
        XCTAssertFalse(AppLaunchPolicy.shouldActivate(environment: ["WEIBEI_SUPPRESS_ACTIVATION": "1"]))
    }

    /**
     * Verifies that reopening never creates a duplicate window and restores one when possible.
     */
    func testMainWindowReopenPolicyUsesExactlyOneDestination() {
        XCTAssertEqual(
            MainWindowReopenPolicy.action(hasVisibleWindows: true, hasReusableWindow: true),
            .none
        )
        XCTAssertEqual(
            MainWindowReopenPolicy.action(hasVisibleWindows: true, hasReusableWindow: false),
            .none
        )
        XCTAssertEqual(
            MainWindowReopenPolicy.action(hasVisibleWindows: false, hasReusableWindow: true),
            .showExistingWindow
        )
        XCTAssertEqual(
            MainWindowReopenPolicy.action(hasVisibleWindows: false, hasReusableWindow: false),
            .openMainWindow
        )
    }

    /**
     * Verifies that the top search action is scoped to a selected material in an active reader.
     */
    func testReaderSearchActionVisibilityMatrix() {
        XCTAssertFalse(AppChromePolicy.showsReaderSearchAction(hasSelectedMaterial: false, readerIsActive: false))
        XCTAssertFalse(AppChromePolicy.showsReaderSearchAction(hasSelectedMaterial: false, readerIsActive: true))
        XCTAssertFalse(AppChromePolicy.showsReaderSearchAction(hasSelectedMaterial: true, readerIsActive: false))
        XCTAssertTrue(AppChromePolicy.showsReaderSearchAction(hasSelectedMaterial: true, readerIsActive: true))
    }

    /**
     * Verifies the global selection agent across workspace ownership, selection, and retained-answer states.
     */
    func testGlobalFloatingAgentVisibilityMatrix() {
        XCTAssertTrue(AppChromePolicy.showsGlobalFloatingAgent(
            courseWorkspacePresented: false,
            canShowSelectionPromptSurface: true,
            surface: .selectionFloat,
            hasSelection: true,
            hasAnchor: true,
            pinned: false,
            keepOpen: false
        ))
        XCTAssertFalse(AppChromePolicy.showsGlobalFloatingAgent(
            courseWorkspacePresented: true,
            canShowSelectionPromptSurface: true,
            surface: .selectionFloat,
            hasSelection: true,
            hasAnchor: true,
            pinned: false,
            keepOpen: false
        ))
        XCTAssertFalse(AppChromePolicy.showsGlobalFloatingAgent(
            courseWorkspacePresented: false,
            canShowSelectionPromptSurface: false,
            surface: .selectionFloat,
            hasSelection: true,
            hasAnchor: true,
            pinned: false,
            keepOpen: false
        ))
        XCTAssertFalse(AppChromePolicy.showsGlobalFloatingAgent(
            courseWorkspacePresented: false,
            canShowSelectionPromptSurface: true,
            surface: .hidden,
            hasSelection: true,
            hasAnchor: true,
            pinned: true,
            keepOpen: true
        ))
        XCTAssertFalse(AppChromePolicy.showsGlobalFloatingAgent(
            courseWorkspacePresented: false,
            canShowSelectionPromptSurface: true,
            surface: .selectionFloat,
            hasSelection: true,
            hasAnchor: false,
            pinned: false,
            keepOpen: false
        ))
        XCTAssertTrue(AppChromePolicy.showsGlobalFloatingAgent(
            courseWorkspacePresented: false,
            canShowSelectionPromptSurface: true,
            surface: .selectionFloat,
            hasSelection: false,
            hasAnchor: false,
            pinned: true,
            keepOpen: false
        ))
        XCTAssertTrue(AppChromePolicy.showsGlobalFloatingAgent(
            courseWorkspacePresented: false,
            canShowSelectionPromptSurface: true,
            surface: .selectionFloat,
            hasSelection: false,
            hasAnchor: false,
            pinned: false,
            keepOpen: true
        ))
    }

    /**
     * Verifies that the transition wash represents a semantic light/dark family change.
     */
    func testAppearanceWashOnlyStagesAcrossFamilies() {
        for oldMode in WeiBeiAppearanceMode.allCases {
            for newMode in WeiBeiAppearanceMode.allCases {
                XCTAssertEqual(
                    AppearanceTransitionPolicy.stagesWash(from: oldMode, to: newMode),
                    oldMode.isDark != newMode.isDark,
                    "\(oldMode.rawValue) -> \(newMode.rawValue)"
                )
            }
        }
    }

    /**
     * Verifies the stable labels, accessibility identifiers, order, and pane destinations of empty-workspace entries.
     */
    func testEmptyWorkspaceEntriesMapToPaneToggles() {
        XCTAssertEqual(EmptyWorkspaceEntry.allCases, [.document, .chat, .notes])
        XCTAssertEqual(EmptyWorkspaceEntry.allCases.map(\.title), ["DOC", "CHAT", "NOTES"])
        XCTAssertEqual(
            EmptyWorkspaceEntry.allCases.map(\.accessibilityIdentifier),
            ["empty-workspace-entry-doc", "empty-workspace-entry-chat", "empty-workspace-entry-notes"]
        )
        XCTAssertEqual(EmptyWorkspaceEntry.allCases.map(\.paneRole), [.reader, .agent, .notes])
    }

    /**
     * 验证三个 Agent 验收场景均映射到独立应用流程，未知场景不会误入。
     */
    func testAgentVerificationScenariosRouteToOwnedFlows() {
        XCTAssertEqual(AgentVerificationScenarioPolicy.flow(for: "offline-learning-flow"), .offlineLearning)
        XCTAssertEqual(AgentVerificationScenarioPolicy.flow(for: "pi-learning-flow"), .piLearning)
        XCTAssertEqual(AgentVerificationScenarioPolicy.flow(for: "pi-course-memory-flow"), .piCourseMemory)
        XCTAssertNil(AgentVerificationScenarioPolicy.flow(for: "pane-toggle-continuity-flow"))
        XCTAssertFalse(AgentVerificationFlow.offlineLearning.waitsForReaderContext)
        XCTAssertTrue(AgentVerificationFlow.piLearning.waitsForReaderContext)
        XCTAssertTrue(AgentVerificationFlow.piCourseMemory.waitsForReaderContext)
    }
}
