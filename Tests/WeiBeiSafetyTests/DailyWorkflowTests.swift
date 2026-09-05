import XCTest
import WeiBeiCore
@testable import WeiBei

@MainActor
final class DailyWorkflowTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testConcurrentChatsKeepTheirQuestionStreamAndCancellation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkspaceStore(workspaceDirectory: root.appendingPathComponent("Workspace"), startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        defer { store.selfCheckAgentResponder = nil; try? FileManager.default.removeItem(at: root) }
        let started = expectation(description: "Both requests reached their own responder")
        started.expectedFulfillmentCount = 2
        store.selfCheckAgentResponder = { request in
            let run = store.agentRun
            store.applyAgentProgress(.text("片段：" + request.question, []), requestID: request.id,
                                     replyMessageID: try XCTUnwrap(run.activeAgentReplyMessageID),
                                     chatID: try XCTUnwrap(run.chatID))
            started.fulfill()
            try await Task.sleep(for: .milliseconds(250))
            return StudyAgentReply(text: "回答：" + request.question, backend: .native)
        }
        let first = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.agentDraft = "问题甲"
        XCTAssertNil(store.askAgent())
        let second = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.agentDraft = "问题乙"
        XCTAssertNil(store.askAgent())
        XCTAssertNotEqual(first.id, second.id)
        wait(for: [started], timeout: 8)
        XCTAssertTrue(store.isAgentRunning(in: first.id))
        XCTAssertTrue(store.isAgentRunning(in: second.id))
        XCTAssertTrue(store.activateStudySession(first.id, expectedCourseID: nil, expectedScopeNeedsReview: false))
        XCTAssertEqual(store.agentStreaming.text, "片段：问题甲")
        store.cancelAgentRequest()
        let secondTask = store.agentRuns[second.id]?.agentRequestTask
        try store.waitForCourseFileOperation {
            await store.waitForAgentRequestsToStop()
            await secondTask?.value
        }
        let firstMessages = try XCTUnwrap(store.studySessions.first { $0.id == first.id }).messages
        let secondMessages = try XCTUnwrap(store.studySessions.first { $0.id == second.id }).messages
        XCTAssertEqual(firstMessages.first?.text, "问题甲")
        XCTAssertEqual(firstMessages.last?.completionState, .interrupted)
        XCTAssertTrue(firstMessages.last?.text.contains("片段：问题甲") == true)
        XCTAssertEqual(secondMessages.first?.text, "问题乙")
        XCTAssertEqual(secondMessages.last?.text, "回答：问题乙")
        XCTAssertNotEqual(secondMessages.last?.completionState, .interrupted)
        let stopping = expectation(description: "Both requests ready for app exit")
        stopping.expectedFulfillmentCount = 2
        store.selfCheckAgentResponder = { request in
            stopping.fulfill()
            try await Task.sleep(for: .seconds(10))
            return StudyAgentReply(text: request.question, backend: .native)
        }
        store.agentDraft = "退出甲"
        XCTAssertNil(store.askAgent())
        store.activateStudySession(second.id, expectedCourseID: nil, expectedScopeNeedsReview: false)
        store.agentDraft = "退出乙"
        XCTAssertNil(store.askAgent())
        wait(for: [stopping], timeout: 8)
        store.cancelAllAgentRequests()
        try store.waitForCourseFileOperation { await store.waitForAgentRequestsToStop() }
        XCTAssertFalse(store.studySessions.flatMap(\.messages).contains { $0.completionState == .generating })
        XCTAssertFalse(store.agentRuns.values.contains { $0.agentRequestTask != nil })
        let saved = try store.waitForCourseFileOperation { await store.flushPendingWorkspaceSaveAsync() }
        XCTAssertTrue(saved)
    }

    func testBlankNoteSearchAndExplicitResume() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root.appendingPathComponent("Workspace"), startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let library = root.appendingPathComponent("资料库")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try store.waitForCourseFileOperation { try await store.configureCourseLibraryAsync(at: library) }
        store.createBlankNotebookNote()
        let note = try XCTUnwrap(store.activeNoteItem)
        XCTAssertNil(store.notebookCreationDraft)
        XCTAssertEqual(store.focusedPane, .notes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(note.url).path))
        store.noteText = "开头\n" + String(repeating: "正文 ", count: 80) + "共同搜索命中词"
        store.persistCurrentNote()
        let result = try store.waitForCourseFileOperation { await store.searchAllCourses(currentCourseID: nil, query: "共同搜索命中词") }
        XCTAssertEqual(result.hits.first?.result.itemID, note.id)
        XCTAssertTrue(result.hits.first?.result.matchedText?.contains("共同搜索命中词") == true)
        let firstAction = AgentReplyAction(kind: .writeNote, targetItemID: note.id, proposedMarkdown: "追加甲")
        let secondAction = AgentReplyAction(kind: .writeNote, targetItemID: note.id, proposedMarkdown: "追加乙")
        let firstReply = AgentMessage(role: .assistant, text: "甲", source: nil, actions: [firstAction])
        let secondReply = AgentMessage(role: .assistant, text: "乙", source: nil, actions: [secondAction])
        store.appendAgentMessage(firstReply)
        _ = store.createStudySession(courseID: nil)
        store.appendAgentMessage(secondReply)
        try store.waitForCourseFileOperation {
            async let first: Void = store.confirmAgentReplyAction(messageID: firstReply.id, actionID: firstAction.id)
            async let second: Void = store.confirmAgentReplyAction(messageID: secondReply.id, actionID: secondAction.id)
            _ = await (first, second)
        }
        let written = try String(contentsOf: XCTUnwrap(note.url), encoding: .utf8)
        XCTAssertTrue(written.contains("追加甲"))
        XCTAssertTrue(written.contains("追加乙"))
        XCTAssertTrue(written.contains("共同搜索命中词"))
        store.captureLastWork()
        let point = try XCTUnwrap(store.lastWork)
        XCTAssertEqual(point.noteID, note.id)
        let saved = try store.waitForCourseFileOperation { await store.flushPendingWorkspaceSaveAsync() }
        XCTAssertTrue(saved)
        let reopened = WorkspaceStore(workspaceDirectory: root.appendingPathComponent("Workspace"), startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        XCTAssertFalse(reopened.showNotes)
        XCTAssertTrue(reopened.canContinueLastWork)
        reopened.continueLastWork()
        XCTAssertEqual(reopened.activeNoteItem?.id, note.id)
        XCTAssertTrue(reopened.showNotes)
        XCTAssertTrue(reopened.agentRuns.isEmpty)
    }
}
