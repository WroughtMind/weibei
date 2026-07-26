import Foundation
import XCTest
@testable import WeiBeiCore

/// Covers durable note-to-source relationship normalization and mutation.
final class NoteSourceRelationsTests: XCTestCase {
    /// Verifies duplicate pairs collapse to the oldest durable relationship.
    func testInitializationDeduplicatesPairsAndKeepsOldestLink() {
        let oldest = NoteSourceLink(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            noteItemID: "note:a",
            sourceItemID: "source:a",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let duplicate = NoteSourceLink(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            noteItemID: "note:a",
            sourceItemID: "source:a",
            createdAt: Date(timeIntervalSince1970: 20)
        )

        let relations = NoteSourceRelations(links: [duplicate, oldest])

        XCTAssertEqual(relations.links, [oldest])
        XCTAssertEqual(relations.sourceIDs(for: "note:a"), ["source:a"])
    }

    /// Verifies replacing one note's sources leaves relationships owned by other notes untouched.
    func testReplacingSourcesIsScopedToOneNote() {
        let retained = NoteSourceLink(noteItemID: "note:b", sourceItemID: "source:shared")
        var relations = NoteSourceRelations(
            links: [
                NoteSourceLink(noteItemID: "note:a", sourceItemID: "source:old"),
                retained,
            ]
        )

        relations.replaceSources(for: "note:a", sourceItemIDs: ["source:new", "source:shared"])

        XCTAssertEqual(Set(relations.sourceIDs(for: "note:a")), ["source:new", "source:shared"])
        XCTAssertTrue(relations.isLinked(noteItemID: "note:b", sourceItemID: "source:shared"))
        XCTAssertFalse(relations.isLinked(noteItemID: "note:a", sourceItemID: "source:old"))
    }

    /// Verifies sanitation removes dangling, self-referential, and duplicate relationships.
    func testSanitizeKeepsOnlyValidCrossItemRelationships() {
        var relations = NoteSourceRelations(
            links: [
                NoteSourceLink(noteItemID: "note:valid", sourceItemID: "source:valid"),
                NoteSourceLink(noteItemID: "note:missing", sourceItemID: "source:valid"),
                NoteSourceLink(noteItemID: "note:valid", sourceItemID: "source:missing"),
                NoteSourceLink(noteItemID: "same", sourceItemID: "same"),
            ]
        )

        relations.sanitize(
            validNoteItemIDs: ["note:valid", "same"],
            validSourceItemIDs: ["source:valid", "same"]
        )

        XCTAssertEqual(relations.links.count, 1)
        XCTAssertTrue(relations.isLinked(noteItemID: "note:valid", sourceItemID: "source:valid"))
    }

    /// Verifies the read index exposes both directions and stable counts.
    func testRelationIndexSupportsBothDirections() {
        let index = NoteSourceRelationIndex(
            links: [
                NoteSourceLink(noteItemID: "note:a", sourceItemID: "source:a"),
                NoteSourceLink(noteItemID: "note:a", sourceItemID: "source:b"),
                NoteSourceLink(noteItemID: "note:b", sourceItemID: "source:a"),
            ]
        )

        XCTAssertEqual(Set(index.sourceIDs(for: "note:a")), ["source:a", "source:b"])
        XCTAssertEqual(Set(index.noteIDs(for: "source:a")), ["note:a", "note:b"])
        XCTAssertEqual(index.sourceCount(for: "note:a"), 2)
        XCTAssertEqual(index.noteCount(for: "source:a"), 2)
    }
}
