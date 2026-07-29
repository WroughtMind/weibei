import XCTest
@testable import WeiBeiCore

final class SelectionBehaviorTests: XCTestCase {
    /**
     * Verifies selection attachment merging handles containment and gesture-local overlap.
     */
    func testSelectionAttachmentMergePreservesCompleteReadableText() {
        XCTAssertEqual(
            SelectionAttachmentMerge.mergedText(
                existing: "名义利率",
                incoming: "名义利率与实际利率",
                withinSelectionGesture: false
            ),
            "名义利率与实际利率"
        )
        XCTAssertEqual(
            SelectionAttachmentMerge.mergedText(
                existing: "名义利率与",
                incoming: "率与实际利率",
                withinSelectionGesture: true
            ),
            "名义利率与实际利率"
        )
        XCTAssertNil(
            SelectionAttachmentMerge.mergedText(
                existing: "第一段。",
                incoming: "第二段",
                withinSelectionGesture: false
            )
        )
    }

    /**
     * Verifies Markdown selection cleanup removes writing syntax without losing prose.
     */
    func testMarkdownSelectionSanitizerProducesAgentReadableText() {
        let cleaned = MarkdownSelectionSanitizer.clean(
            """
            > [!note] 重点
            > **实际利率**等于[[名义利率|名义利率]]减去==预期通胀==。

            - [x] 已完成项
            """
        )

        XCTAssertEqual(cleaned, "重点\n**实际利率**等于名义利率减去预期通胀。\n已完成项")
    }

    /**
     * Verifies the selection float remains visible only for a live or intentionally retained context.
     */
    func testSelectionFloatingAgentVisibilityContract() {
        XCTAssertTrue(
            SelectionFloatingAgentPlacement.isVisible(
                surface: .selectionFloat,
                hasSelection: true,
                hasAnchor: true,
                pinned: false
            )
        )
        XCTAssertTrue(
            SelectionFloatingAgentPlacement.isVisible(
                surface: .selectionFloat,
                hasSelection: false,
                hasAnchor: false,
                pinned: false,
                keepOpen: true
            )
        )
        XCTAssertFalse(
            SelectionFloatingAgentPlacement.isVisible(
                surface: .selectionFloat,
                hasSelection: true,
                hasAnchor: false,
                pinned: false
            )
        )
        XCTAssertFalse(
            SelectionFloatingAgentPlacement.isVisible(
                surface: .hidden,
                hasSelection: true,
                hasAnchor: true,
                pinned: true
            )
        )
    }

    /**
     * Verifies note selections expose replaceability without granting it to document selections.
     */
    func testSelectionContextReplaceabilityDependsOnOwnerAndEditability() {
        let document = SelectionContext(
            text: "text",
            source: .document,
            ownerTitle: "Course",
            isEditable: true
        )
        let lockedNote = SelectionContext(
            text: "text",
            source: .note,
            ownerTitle: "Note",
            isEditable: false
        )
        let editableNote = SelectionContext(
            text: "text",
            source: .note,
            ownerTitle: "Note",
            isEditable: true
        )

        XCTAssertFalse(document.isReplaceableNoteSelection)
        XCTAssertFalse(lockedNote.isReplaceableNoteSelection)
        XCTAssertTrue(editableNote.isReplaceableNoteSelection)
        XCTAssertEqual(editableNote.label(language: .english), "Note selection: Note")
    }
}
