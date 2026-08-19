import Foundation
import XCTest
@testable import WeiBei

final class NoteRecoveryStoreTests: XCTestCase {
    private var rootURL: URL!
    private var store: NoteRecoveryStore!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = NoteRecoveryStore(rootURL: rootURL)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
    }

    func testClassifiesAndCleansStaleCheckpoint() async throws {
        let checkpoint = try await store.store(
            documentID: "note-a",
            baseFileDigest: NoteRecoveryStore.digest("base"),
            revision: 4,
            markdown: "checkpoint"
        )

        let result = try await store.classify(
            documentID: "note-a",
            diskDigest: checkpoint.metadata.checkpointDigest
        )

        XCTAssertEqual(result, .stale)
        let removed = try await store.load(documentID: "note-a")
        XCTAssertNil(removed)
    }

    func testRestoresWhenDiskStillMatchesBase() async throws {
        let baseDigest = NoteRecoveryStore.digest("base")
        let checkpoint = try await store.store(
            documentID: "note-a",
            baseFileDigest: baseDigest,
            revision: 5,
            markdown: "new text"
        )

        let result = try await store.classify(
            documentID: "note-a",
            diskDigest: baseDigest
        )

        XCTAssertEqual(result, .restore(checkpoint))
        let retained = try await store.load(documentID: "note-a")
        XCTAssertNotNil(retained)
    }

    func testKeepsCheckpointWhenDiskAndCheckpointDiverged() async throws {
        let checkpoint = try await store.store(
            documentID: "note-a",
            baseFileDigest: NoteRecoveryStore.digest("base"),
            revision: 6,
            markdown: "in-app edit"
        )

        let result = try await store.classify(
            documentID: "note-a",
            diskDigest: NoteRecoveryStore.digest("external edit")
        )

        XCTAssertEqual(result, .conflict(checkpoint))
        let retained = try await store.load(documentID: "note-a")
        XCTAssertEqual(retained, checkpoint)
    }

    func testDocumentIDCannotEscapeRecoveryRoot() async throws {
        let unsafeID = "../../outside/笔记?name=/tmp"
        try await store.store(
            documentID: unsafeID,
            baseFileDigest: NoteRecoveryStore.digest("base"),
            revision: 1,
            markdown: "safe"
        )

        let directory = rootURL.appendingPathComponent(
            NoteRecoveryStore.directoryName(for: unsafeID),
            isDirectory: true
        )
        XCTAssertEqual(
            directory.deletingLastPathComponent().standardizedFileURL,
            rootURL.standardizedFileURL
        )
        XCTAssertTrue(directory.lastPathComponent.allSatisfy { $0.isHexDigit })
        XCTAssertEqual(directory.lastPathComponent.count, 64)
        let loaded = try await store.load(documentID: unsafeID)
        XCTAssertEqual(loaded?.markdown, "safe")
    }

    func testDamagedMetadataIsRetainedAndNeverSelectedForRestore() async throws {
        let documentID = "note-a"
        try await store.store(
            documentID: documentID,
            baseFileDigest: NoteRecoveryStore.digest("base"),
            revision: 2,
            markdown: "checkpoint"
        )
        let directory = rootURL.appendingPathComponent(
            NoteRecoveryStore.directoryName(for: documentID),
            isDirectory: true
        )
        let metadataURL = directory.appendingPathComponent("metadata.json")
        try Data("not-json".utf8).write(to: metadataURL, options: [.atomic])

        let result = try await store.classify(
            documentID: documentID,
            diskDigest: NoteRecoveryStore.digest("base")
        )

        XCTAssertEqual(result, .damaged)
        XCTAssertEqual(try Data(contentsOf: metadataURL), Data("not-json".utf8))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("latest-snapshot.md").path
        ))
    }

    func testPersistedSnapshotCannotReappearAfterLateCheckpointTask() async throws {
        let digest = NoteRecoveryStore.digest("saved")
        XCTAssertFalse(try await store.removeIfCheckpointMatches(
            documentID: "note-a",
            checkpointDigest: digest
        ))

        try await store.store(
            documentID: "note-a",
            baseFileDigest: NoteRecoveryStore.digest("base"),
            revision: 3,
            markdown: "saved"
        )

        XCTAssertNil(try await store.load(documentID: "note-a"))
    }
}
