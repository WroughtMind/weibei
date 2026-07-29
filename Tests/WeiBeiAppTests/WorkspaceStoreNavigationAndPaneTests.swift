import AppKit
import XCTest
@testable import WeiBei
import WeiBeiCore

final class WorkspaceStoreNavigationAndPaneTests: WorkspaceStoreTestCase {
    /**
     * 验证学习会话创建、切换与删除会保持各自消息并维护唯一活动会话。
     */
    @MainActor
    func testStudySessionLifecyclePreservesIndependentMessages() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        let firstSessionID = try XCTUnwrap(store.activeStudySessionID)
        store.messages = [AgentMessage(role: .user, text: "First session", source: nil)]

        store.createStudySession()
        let secondSessionID = try XCTUnwrap(store.activeStudySessionID)
        XCTAssertNotEqual(secondSessionID, firstSessionID)
        XCTAssertEqual(store.studySessions.count, 2)
        XCTAssertTrue(store.messages.isEmpty)

        store.activateStudySession(firstSessionID)
        XCTAssertEqual(store.activeStudySessionID, firstSessionID)
        XCTAssertEqual(store.messages.map(\.text), ["First session"])

        store.deleteStudySession(secondSessionID)
        XCTAssertEqual(store.studySessions.map(\.id), [firstSessionID])
        XCTAssertEqual(store.activeStudySessionID, firstSessionID)
    }

    /**
     * 验证前进后退恢复材料和布局，并在新导航后清空前进栈。
     */
    @MainActor
    func testBackForwardRestoresWorkspaceStateAndBranchesHistory() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        let firstID = try XCTUnwrap(store.sampleItems.first?.id)
        let secondID = try XCTUnwrap(store.sampleItems.dropFirst().first?.id)

        store.select(itemID: firstID)
        store.setLayout(.immersiveReading)
        store.select(itemID: secondID)
        XCTAssertTrue(store.canNavigateBack)

        store.navigateBackInWorkspace()
        XCTAssertEqual(store.selectedItemID, firstID)
        XCTAssertEqual(store.layout, .immersiveReading)
        XCTAssertTrue(store.canNavigateForward)

        store.select(itemID: secondID)
        XCTAssertFalse(store.canNavigateForward)
    }

    /**
     * 验证 PDF 页码作为导航快照恢复，且恢复动作不会丢失前进历史。
     */
    @MainActor
    func testPDFPageNavigationPointRestoresPageIndex() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        store.select(itemID: "sample-pdf")
        store.updateReaderPageIndex(3)
        store.recordReaderPageNavigationPoint()
        store.updateReaderPageIndex(8)
        store.select(itemID: "sample-html")

        store.navigateBackInWorkspace()
        XCTAssertEqual(store.selectedItemID, "sample-pdf")
        XCTAssertEqual(store.readerPageIndex, 8)
        store.navigateBackInWorkspace()
        XCTAssertEqual(store.readerPageIndex, 3)
    }

    /**
     * 验证三栏交换只在三栏布局中生效，且始终保持完整唯一角色集合。
     */
    @MainActor
    func testThreePaneSwapHonorsLayoutBoundary() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        store.setLayout(.documentAgentNotes)
        let initial = store.normalizedThreePaneOrder
        store.swapThreePaneSecondaryPanes()
        XCTAssertNotEqual(store.normalizedThreePaneOrder, initial)
        XCTAssertEqual(Set(store.normalizedThreePaneOrder), Set(WorkspacePaneRole.allCases))

        store.setLayout(.immersiveReading)
        let immersiveOrder = store.normalizedThreePaneOrder
        store.swapThreePaneSecondaryPanes()
        XCTAssertEqual(store.normalizedThreePaneOrder, immersiveOrder)
    }

    /**
     * 验证快捷键不会吞掉当前布局或状态下不可执行的操作。
     */
    @MainActor
    func testUnavailableShortcutsReturnFalse() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        store.setLayout(.immersiveReading)
        XCTAssertFalse(store.handleAppShortcut(key: "j", modifiers: [.command]))
        XCTAssertFalse(store.handleAppShortcut(key: "s", modifiers: [.command, .option]))
        XCTAssertFalse(store.handleAppShortcut(key: "a", modifiers: [.command, .shift]))

        store.agentDraft = "   "
        XCTAssertFalse(store.handleAppShortcut(key: "return", modifiers: [.command]))
    }

    /**
     * 验证面板展开请求只能由匹配的请求 ID 消费。
     */
    @MainActor
    func testPaneExpansionRequestRequiresMatchingID() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        store.requestPaneExpansion(.notes)
        let request = try XCTUnwrap(store.paneExpansionRequest)
        store.completePaneExpansionRequest(UUID())
        XCTAssertEqual(store.paneExpansionRequest, request)
        store.completePaneExpansionRequest(request.id)
        XCTAssertNil(store.paneExpansionRequest)
    }
}
