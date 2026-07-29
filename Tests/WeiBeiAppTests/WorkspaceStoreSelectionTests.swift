import CoreGraphics
import XCTest
@testable import WeiBei
import WeiBeiCore

final class WorkspaceStoreSelectionTests: WorkspaceStoreTestCase {
    /**
     * 验证有意义选区创建浮动上下文，空白选区会完整清理瞬态状态。
     */
    @MainActor
    func testSelectionLifecycleCreatesAndClearsFloatingContext() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        store.updateSelection(
            "  cited text  ",
            source: .document,
            anchor: CGPoint(x: 80, y: 120),
            ownerTitle: "Reader",
            isEditable: false
        )
        XCTAssertEqual(store.selectionContext?.text, "cited text")
        XCTAssertEqual(store.selectionContext?.ownerTitle, "Reader")
        XCTAssertEqual(store.agentSurface, .selectionFloat)
        XCTAssertNotNil(store.selectionAnchor)

        store.updateSelection(" \n\t ", source: .document)
        XCTAssertNil(store.selectionContext)
        XCTAssertNil(store.selectionAnchor)
        XCTAssertEqual(store.agentSurface, .hidden)
    }

    /**
     * 验证选择不同材料会清理未固定选区和附件，避免跨材料泄漏上下文。
     */
    @MainActor
    func testMaterialSwitchClearsUnpinnedSelectionContext() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        let secondID = try XCTUnwrap(store.sampleItems.dropFirst().first?.id)
        let selection = SelectionContext(
            text: "first material excerpt",
            source: .document,
            ownerTitle: "First",
            isEditable: false
        )
        store.updateSelection(selection.text, source: selection.source, ownerTitle: selection.ownerTitle, isEditable: false)
        store.addSelectionAttachment(selection)
        XCTAssertFalse(store.selectionAttachments.isEmpty)

        store.select(itemID: secondID)
        XCTAssertNil(store.selectionContext)
        XCTAssertTrue(store.selectionAttachments.isEmpty)
    }

    /**
     * 验证重复和被包含的选区不会制造重复附件。
     */
    @MainActor
    func testSelectionAttachmentsDeduplicateContainedFragments() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        store.addSelectionAttachment(
            SelectionContext(text: "Alpha beta gamma", source: .document, ownerTitle: "Reader")
        )
        store.addSelectionAttachment(
            SelectionContext(text: "beta", source: .document, ownerTitle: "Reader")
        )
        XCTAssertEqual(store.selectionAttachments.map(\.text), ["Alpha beta gamma"])
    }
}
