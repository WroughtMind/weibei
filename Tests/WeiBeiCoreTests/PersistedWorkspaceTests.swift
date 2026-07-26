import Foundation
import XCTest
@testable import WeiBeiCore

/// Covers the durable workspace schema without depending on source-code text.
final class PersistedWorkspaceTests: XCTestCase {
    /// Verifies that user-facing workspace choices survive a JSON round trip.
    func testRoundTripPreservesWorkspaceChoices() throws {
        let courseID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let source = StudyItem(
            id: "material:money",
            title: "货币金融学",
            subtitle: "PDF",
            kind: .pdf,
            urlPath: "/Courses/Money.pdf",
            isSample: false
        )
        let workspace = PersistedWorkspace(
            importedItems: [source],
            notesByItemID: ["note:rates": "# 利率"],
            pendingNoteWritesByItemID: ["note:rates": PendingNoteWriteState(baselineContentDigest: "sha256:baseline")],
            noteBackingContentDigestsByItemID: ["note:rates": "sha256:current"],
            selectedItemID: source.id,
            activeNotebookItemID: "note:rates",
            activeCourseID: courseID,
            noteSourceLinks: [NoteSourceLink(noteItemID: "note:rates", sourceItemID: source.id)],
            noteSourceLinksMigrationVersion: 1,
            learningMemoryRevision: 7,
            modelName: "gpt-test",
            agentProviderID: "openai",
            agentBaseURL: "https://example.invalid/v1",
            workspaceLayout: .documentAgentNotes,
            threePaneOrder: [.agent, .reader, .notes],
            agentSurface: .selectionFloat,
            noteRenderMode: .rich,
            showLibrary: false,
            showReader: true,
            showAgent: true,
            showNotes: false,
            showRightPane: true,
            showDailyInspiration: false,
            appearanceModeRaw: "dark",
            adaptImportedDocumentColors: false,
            interfaceLanguageRaw: "zh-Hans"
        )

        let restored = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: JSONEncoder().encode(workspace)
        )

        XCTAssertEqual(restored.importedItems, [source])
        XCTAssertEqual(restored.notesByItemID, ["note:rates": "# 利率"])
        XCTAssertEqual(restored.pendingNoteWritesByItemID?["note:rates"]?.baselineContentDigest, "sha256:baseline")
        XCTAssertEqual(restored.noteBackingContentDigestsByItemID, ["note:rates": "sha256:current"])
        XCTAssertEqual(restored.selectedItemID, source.id)
        XCTAssertEqual(restored.activeNotebookItemID, "note:rates")
        XCTAssertEqual(restored.activeCourseID, courseID)
        XCTAssertEqual(restored.noteSourceLinks?.map(\.sourceItemID), [source.id])
        XCTAssertEqual(restored.noteSourceLinksMigrationVersion, 1)
        XCTAssertEqual(restored.learningMemoryRevision, 7)
        XCTAssertEqual(restored.modelName, "gpt-test")
        XCTAssertEqual(restored.agentProviderID, "openai")
        XCTAssertEqual(restored.agentBaseURL, "https://example.invalid/v1")
        XCTAssertEqual(restored.workspaceLayout, .documentAgentNotes)
        XCTAssertEqual(restored.threePaneOrder, [.agent, .reader, .notes])
        XCTAssertEqual(restored.agentSurface, .selectionFloat)
        XCTAssertEqual(restored.noteRenderMode, .rich)
        XCTAssertEqual(restored.showLibrary, false)
        XCTAssertEqual(restored.showReader, true)
        XCTAssertEqual(restored.showAgent, true)
        XCTAssertEqual(restored.showNotes, false)
        XCTAssertEqual(restored.showRightPane, true)
        XCTAssertEqual(restored.showDailyInspiration, false)
        XCTAssertEqual(restored.appearanceModeRaw, "dark")
        XCTAssertEqual(restored.adaptImportedDocumentColors, false)
        XCTAssertEqual(restored.interfaceLanguageRaw, "zh-Hans")
    }

    /// Verifies that a minimal pre-feature snapshot remains decodable without fabricated optional state.
    func testLegacyMinimalSnapshotLeavesNewFieldsAbsent() throws {
        let data = Data(#"{"importedItems":[],"notesByItemID":{}}"#.utf8)

        let workspace = try JSONDecoder().decode(PersistedWorkspace.self, from: data)

        XCTAssertTrue(workspace.importedItems.isEmpty)
        XCTAssertTrue(workspace.notesByItemID.isEmpty)
        XCTAssertNil(workspace.courses)
        XCTAssertNil(workspace.courseItemMemberships)
        XCTAssertNil(workspace.activeCourseID)
        XCTAssertNil(workspace.noteSourceLinks)
        XCTAssertNil(workspace.noteSourceLinksMigrationVersion)
        XCTAssertNil(workspace.threePaneOrder)
        XCTAssertNil(workspace.showDailyInspiration)
        XCTAssertNil(workspace.adaptImportedDocumentColors)
    }

    /// Verifies backward-compatible defaults for imported items added after the original schema.
    func testLegacyImportedItemDefaultsNotebookStateAndLastKnownPath() throws {
        let data = Data(
            #"""
            {
              "id": "imported:legacy",
              "title": "旧笔记",
              "subtitle": "Markdown",
              "kind": "markdown",
              "urlPath": "/Notes/legacy.md",
              "isSample": false
            }
            """#.utf8
        )

        let item = try JSONDecoder().decode(StudyItem.self, from: data)

        XCTAssertFalse(item.isNotebookNote)
        XCTAssertEqual(item.importedFileLastKnownPath, "/Notes/legacy.md")
        XCTAssertTrue(item.isImportedMarkdownFile)
        XCTAssertFalse(item.editsBackingMarkdownFile)
    }
}
