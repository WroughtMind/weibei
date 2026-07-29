import CoreGraphics
import Foundation
import XCTest
@testable import WeiBeiCore

final class WorkspaceModelPersistenceTests: XCTestCase {
    /**
     * Verifies that durable workspace state round-trips independent notebook and material selection.
     */
    func testPersistedWorkspaceRoundTripsIndependentSelectionsAndPendingWrites() throws {
        let material = StudyItem(
            id: "material-1",
            title: "Money",
            subtitle: "Chapter 1",
            kind: .pdf,
            urlPath: "/tmp/money.pdf",
            isSample: false
        )
        let note = StudyItem(
            id: "note-1",
            title: "Rates",
            subtitle: "rates.md",
            kind: .markdown,
            urlPath: "/tmp/rates.md",
            isSample: false,
            isNotebookNote: true
        )
        let workspace = PersistedWorkspace(
            importedItems: [material, note],
            notesByItemID: [note.id: "# Rates"],
            pendingNoteWritesByItemID: [note.id: PendingNoteWriteState(baselineContentDigest: "digest-1")],
            noteBackingContentDigestsByItemID: [note.id: "digest-2"],
            selectedItemID: material.id,
            activeNotebookItemID: note.id,
            learningMemoryRevision: 7,
            workspaceLayout: .documentAgentNotes,
            threePaneOrder: [.notes, .reader, .agent]
        )

        let decoded = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: JSONEncoder().encode(workspace)
        )

        XCTAssertEqual(decoded.selectedItemID, material.id)
        XCTAssertEqual(decoded.activeNotebookItemID, note.id)
        XCTAssertEqual(decoded.notesByItemID[note.id], "# Rates")
        XCTAssertEqual(decoded.pendingNoteWritesByItemID?[note.id]?.baselineContentDigest, "digest-1")
        XCTAssertEqual(decoded.noteBackingContentDigestsByItemID?[note.id], "digest-2")
        XCTAssertEqual(decoded.learningMemoryRevision, 7)
        XCTAssertEqual(decoded.threePaneOrder, [.notes, .reader, .agent])
    }

    /**
     * Verifies decoding older workspace documents supplies safe defaults for newer item fields.
     */
    func testStudyItemDecodesLegacyDocumentWithoutNotebookMetadata() throws {
        let data = Data(
            """
            {
              "id": "legacy",
              "title": "Legacy note",
              "subtitle": "legacy.md",
              "kind": "markdown",
              "urlPath": "/tmp/legacy.md",
              "isSample": false
            }
            """.utf8
        )

        let item = try JSONDecoder().decode(StudyItem.self, from: data)

        XCTAssertFalse(item.isNotebookNote)
        XCTAssertEqual(item.importedFileLastKnownPath, "/tmp/legacy.md")
        XCTAssertTrue(item.canBecomeNotebookNote)
        XCTAssertFalse(item.editsBackingMarkdownFile)
    }

    /**
     * Verifies pane order normalization preserves user intent while removing duplicates.
     */
    func testPaneOrderNormalizationAndReorderTargeting() {
        XCTAssertEqual(
            WorkspacePaneRole.normalized([.notes, .reader, .notes]),
            [.notes, .reader, .agent]
        )
        let frames: [WorkspacePaneRole: CGRect] = [
            .reader: CGRect(x: 0, y: 0, width: 320, height: 600),
            .agent: CGRect(x: 330, y: 0, width: 620, height: 600),
            .notes: CGRect(x: 960, y: 0, width: 360, height: 600),
        ]
        XCTAssertEqual(
            ThreePaneReorderTargeting.targetIndex(
                order: [.reader, .agent, .notes],
                frames: frames,
                role: .reader,
                horizontalDelta: 180
            ),
            1
        )
        XCTAssertNil(
            ThreePaneReorderTargeting.targetIndex(
                order: [.reader, .agent, .notes],
                frames: frames,
                role: .reader,
                horizontalDelta: 0
            )
        )
    }

    /**
     * Verifies source references retain exact jump coordinates across localized formats.
     */
    func testSourceReferenceParsesStableJumpCoordinates() {
        let chinese = SourceReferenceTitle.parse(
            "来源：重复教材，条目：7，章节标识：html-section-a1b2c3d4，章节序号：4，章节：利率"
        )
        XCTAssertEqual(chinese.title, "重复教材")
        XCTAssertEqual(chinese.courseItemOrdinal, 7)
        XCTAssertEqual(chinese.sectionLocationID, "html-section-a1b2c3d4")
        XCTAssertEqual(chinese.sectionOrdinal, 4)
        XCTAssertEqual(chinese.sectionTitle, "利率")

        let english = SourceReferenceTitle.parse(
            "Source: Repeated Course, item: 2, section id: html-section-d4c3b2a1, section number: 5, section: Interest"
        )
        XCTAssertEqual(english.title, "Repeated Course")
        XCTAssertEqual(english.courseItemOrdinal, 2)
        XCTAssertEqual(english.sectionLocationID, "html-section-d4c3b2a1")
        XCTAssertEqual(english.sectionOrdinal, 5)
        XCTAssertEqual(english.sectionTitle, "Interest")
    }
}
