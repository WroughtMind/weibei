import XCTest
@testable import WeiBei

final class NoteEditingSessionTests: XCTestCase {
    @MainActor
    func testRejectsSnapshotFromStaleDocumentGeneration() throws {
        var commands: [NoteEditorSnapshotRequest] = []
        let session = NoteEditingSession(documentID: "note-a") {
            commands.append($0)
        }
        session.requestSnapshot()
        let staleCommand = try XCTUnwrap(commands.first)

        session.replaceDocument(with: "note-b")

        XCTAssertFalse(
            session.receive(
                snapshot(for: staleCommand, revision: 0, markdown: "stale")
            )
        )
        XCTAssertEqual(session.documentID, "note-b")
        XCTAssertEqual(session.currentRevision, 0)
    }

    @MainActor
    func testRetriesSnapshotBelowMinimumRevision() throws {
        var commands: [NoteEditorSnapshotRequest] = []
        var accepted: [NoteEditorSnapshotReadyEvent] = []
        let session = NoteEditingSession(
            documentID: "note-a",
            onSnapshotRequest: { commands.append($0) },
            onSnapshotAccepted: { accepted.append($0) }
        )
        XCTAssertTrue(
            session.receive(
                dirtyEvent(for: session, revision: 5)
            )
        )
        session.requestSnapshot(minimumRevision: 5)

        let first = try XCTUnwrap(commands.first)
        XCTAssertFalse(
            session.receive(
                snapshot(for: first, revision: 4, markdown: "old")
            )
        )
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands.last?.minimumRevision, 5)
        let retry = try XCTUnwrap(commands.last)
        XCTAssertTrue(
            session.receive(
                snapshot(for: retry, revision: 5, markdown: "fresh")
            )
        )
        XCTAssertEqual(accepted.map(\.markdown), ["fresh"])
    }

    @MainActor
    func testSavingSnapshotDoesNotClearLaterTyping() throws {
        var commands: [NoteEditorSnapshotRequest] = []
        let session = NoteEditingSession(documentID: "note-a") {
            commands.append($0)
        }
        session.receive(dirtyEvent(for: session, revision: 1))
        session.requestSnapshot()
        let command = try XCTUnwrap(commands.first)
        XCTAssertTrue(
            session.receive(
                snapshot(for: command, revision: 1, markdown: "first")
            )
        )

        session.receive(dirtyEvent(for: session, revision: 2))
        XCTAssertTrue(session.markSaved(revision: 1, as: .writtenToFile))

        XCTAssertEqual(session.savedRevision, 1)
        XCTAssertEqual(session.currentRevision, 2)
        XCTAssertTrue(session.dirty)
    }

    @MainActor
    func testConcurrentSnapshotRequestsShareOneFlight() throws {
        var commands: [NoteEditorSnapshotRequest] = []
        let session = NoteEditingSession(documentID: "note-a") {
            commands.append($0)
        }

        // Two callers requesting before the flight lands must share it. The
        // async snapshot() wrapper schedules through the MainActor, and
        // async-let children are not guaranteed to start within a single
        // Task.yield() on current toolchains, so drive the synchronous
        // requestSnapshot path directly: same contract, no scheduling dependence.
        var firstResult: Result<NoteEditorSnapshotReadyEvent, NoteEditingSessionError>?
        var secondResult: Result<NoteEditorSnapshotReadyEvent, NoteEditingSessionError>?
        XCTAssertTrue(session.requestSnapshot { firstResult = $0 })
        XCTAssertTrue(session.requestSnapshot { secondResult = $0 })

        XCTAssertEqual(commands.count, 1)
        let command = try XCTUnwrap(commands.first)
        XCTAssertTrue(
            session.receive(
                snapshot(for: command, revision: 0, markdown: "shared")
            )
        )

        XCTAssertEqual(try firstResult?.get().markdown, "shared")
        XCTAssertEqual(try secondResult?.get().markdown, "shared")
        XCTAssertEqual(commands.count, 1)
    }

    @MainActor
    func testAsyncSnapshotResumesWithFlightResult() async throws {
        var commands: [NoteEditorSnapshotRequest] = []
        let session = NoteEditingSession(documentID: "note-a") {
            commands.append($0)
        }

        async let awaited = session.snapshot()
        // The continuation registers before the child task's first suspension,
        // so waiting for the issued command deterministically waits for the
        // caller to be attached to the flight.
        var waits = 0
        while commands.isEmpty && waits < 10_000 {
            waits += 1
            await Task.yield()
        }
        let command = try XCTUnwrap(commands.first)

        XCTAssertTrue(
            session.receive(
                snapshot(for: command, revision: 0, markdown: "shared")
            )
        )
        let result = try await awaited
        XCTAssertEqual(result.markdown, "shared")
        XCTAssertEqual(commands.count, 1)
    }

    @MainActor
    func testOnlyCurrentBridgeTokenCanUnbindSender() {
        let session = NoteEditingSession(documentID: "note-a")
        let staleToken = session.bindSnapshotRequestHandler { _ in
            XCTFail("stale handler received a command")
        }
        var commands: [NoteEditorSnapshotRequest] = []
        let currentToken = session.bindSnapshotRequestHandler {
            commands.append($0)
        }

        session.unbindSnapshotRequestHandler(staleToken)
        XCTAssertTrue(session.requestSnapshot())
        XCTAssertEqual(commands.count, 1)

        session.unbindSnapshotRequestHandler(currentToken)
        var failure: NoteEditingSessionError?
        XCTAssertFalse(
            session.requestSnapshot { result in
                if case let .failure(error) = result {
                    failure = error
                }
            }
        )
        XCTAssertEqual(failure, .bridgeUnavailable)
    }

    @MainActor
    func testDirtyInputSchedulesOneIdleSnapshot() async throws {
        var commands: [NoteEditorSnapshotRequest] = []
        let session = NoteEditingSession(
            documentID: "note-a",
            idleSnapshotDelay: .milliseconds(20),
            maximumSnapshotAge: .seconds(1),
            onSnapshotRequest: { commands.append($0) }
        )

        session.receive(dirtyEvent(for: session, revision: 1))
        session.receive(dirtyEvent(for: session, revision: 2))
        // Poll instead of one fixed sleep: on a loaded CI runner the 20ms idle
        // timer can outrun the main thread well past any fixed window, which
        // made this test flap (commands still empty at assertion time). The
        // happy path still returns in one idle delay; only a real failure now
        // waits out the deadline.
        let deadline = Date().addingTimeInterval(2)
        while commands.isEmpty && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.minimumRevision, 2)
    }

    @MainActor
    func testSnapshotTimesOutInsteadOfHangingLifecycle() async {
        let session = NoteEditingSession(
            documentID: "note-a",
            snapshotTimeout: .milliseconds(20),
            onSnapshotRequest: { _ in }
        )

        do {
            _ = try await session.snapshot()
            XCTFail("snapshot should time out")
        } catch {
            XCTAssertEqual(error as? NoteEditingSessionError, .snapshotTimedOut)
        }
    }

    @MainActor
    func testFreshSnapshotGateFailsWhenEditorBridgeIsUnavailable() async {
        let session = NoteEditingSession(documentID: "note-a")

        do {
            _ = try await session.snapshot()
            XCTFail("snapshot unexpectedly succeeded")
        } catch {
            XCTAssertEqual(error as? NoteEditingSessionError, .bridgeUnavailable)
        }
    }

    @MainActor
    func testInvalidatingWebProcessPreservesDirtyRecoveryState() {
        let session = NoteEditingSession(documentID: "note-a")
        session.receive(dirtyEvent(for: session, revision: 3))
        let generation = session.documentGeneration

        session.invalidateBridgeGeneration()

        XCTAssertEqual(session.documentGeneration, generation + 1)
        XCTAssertEqual(session.currentRevision, 3)
        XCTAssertTrue(session.dirty)
    }

    @MainActor
    private func dirtyEvent(
        for session: NoteEditingSession,
        revision: UInt64
    ) -> NoteEditorDirtyChangedEvent {
        NoteEditorDirtyChangedEvent(
            documentID: session.documentID,
            documentGeneration: session.documentGeneration,
            revision: revision,
            dirty: true
        )
    }

    private func snapshot(
        for command: NoteEditorSnapshotRequest,
        revision: UInt64,
        markdown: String
    ) -> NoteEditorSnapshotReadyEvent {
        NoteEditorSnapshotReadyEvent(
            requestID: command.requestID ?? "",
            documentID: command.documentID,
            documentGeneration: command.documentGeneration,
            revision: revision,
            markdown: markdown
        )
    }
}
