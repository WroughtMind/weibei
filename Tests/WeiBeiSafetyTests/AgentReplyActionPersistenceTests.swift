import Foundation
import XCTest
import WeiBeiCore
@testable import WeiBei

@MainActor
final class AgentReplyActionPersistenceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testNoteAndRelationActionsPersistBeforeReturning() throws {
        let (root, store, courseID, chatID) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.waitForCourseFileOperation {
            let createdID = await store.createCourseNotebookNote(
                courseID: courseID, title: "原笔记", markdown: "原始正文", revealInWorkspace: false
            )
            let noteID = try XCTUnwrap(createdID)
            let noteURL = try XCTUnwrap(store.importedItems.first { $0.id == noteID }?.url)
            let sourceURL = root.appendingPathComponent("讲义.txt")
            try "原始讲义".write(to: sourceURL, atomically: true, encoding: .utf8)
            let material = try await store.importFileIntoCourse(sourceURL, courseID: courseID, role: .material)

            let write = AgentReplyAction(kind: .writeNote, targetItemID: noteID, proposedMarkdown: "追加正文")
            let writeReply = try await self.append(write, to: store, courseID: courseID, chatID: chatID)
            let started = Date()
            await store.confirmAgentReplyAction(messageID: writeReply.id, actionID: write.id)
            XCTAssertEqual(try self.persistedAction(writeReply, in: store, chatID: chatID).state, .executed)
            XCTAssertTrue(try String(contentsOf: noteURL, encoding: .utf8).contains("追加正文"))
            await store.undoAgentReplyAction(messageID: writeReply.id, actionID: write.id)
            XCTAssertEqual(try self.persistedAction(writeReply, in: store, chatID: chatID).state, .cancelled)
            XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "原始正文")

            let relation = AgentReplyAction(kind: .createRelation, targetItemID: noteID, sourceItemID: material.item.id)
            let relationReply = try await self.append(relation, to: store, courseID: courseID, chatID: chatID)
            await store.confirmAgentReplyAction(messageID: relationReply.id, actionID: relation.id)
            XCTAssertEqual(try self.persistedAction(relationReply, in: store, chatID: chatID).state, .executed)
            let linked = try JSONDecoder().decode(PersistedWorkspace.self, from: Data(contentsOf: store.storageURL))
            XCTAssertTrue(linked.noteSourceLinks?.contains { $0.id == relation.id } == true)
            await store.undoAgentReplyAction(messageID: relationReply.id, actionID: relation.id)
            XCTAssertEqual(try self.persistedAction(relationReply, in: store, chatID: chatID).state, .cancelled)
            let unlinked = try JSONDecoder().decode(PersistedWorkspace.self, from: Data(contentsOf: store.storageURL))
            XCTAssertFalse(unlinked.noteSourceLinks?.contains { $0.id == relation.id } == true)

            let cancelled = AgentReplyAction(kind: .writeNote, targetItemID: noteID, proposedMarkdown: "不要写入")
            let cancelledReply = try await self.append(cancelled, to: store, courseID: courseID, chatID: chatID)
            await store.cancelAgentReplyAction(messageID: cancelledReply.id, actionID: cancelled.id)
            XCTAssertEqual(try self.persistedAction(cancelledReply, in: store, chatID: chatID).state, .cancelled)
            let invalid = AgentReplyAction(kind: .writeNote, targetItemID: noteID, proposedMarkdown: "")
            let invalidReply = try await self.append(invalid, to: store, courseID: courseID, chatID: chatID)
            await store.confirmAgentReplyAction(messageID: invalidReply.id, actionID: invalid.id)
            XCTAssertEqual(try self.persistedAction(invalidReply, in: store, chatID: chatID).state, .failed)
            XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "原始正文")
            // 回归曾让这些主线程动作等待到 60 秒超时；检查实际完成时间，不锁保存函数名。
            XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        }
    }

    func testNewNoteRetryReusesMatchingContentAndPreservesDifferentContent() throws {
        let (root, store, courseID, chatID) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.waitForCourseFileOperation {
            let original = "# 同名笔记\n\n原始正文"
            let createdID = await store.createCourseNotebookNote(
                courseID: courseID, title: "同名笔记", markdown: original, revealInWorkspace: false
            )
            let originalID = try XCTUnwrap(createdID)
            let originalURL = try XCTUnwrap(store.importedItems.first { $0.id == originalID }?.url)
            let retry = AgentReplyAction(kind: .writeNote, state: .failed, proposedMarkdown: original)
            let retryReply = try await self.append(retry, to: store, courseID: courseID, chatID: chatID)
            await store.confirmAgentReplyAction(messageID: retryReply.id, actionID: retry.id)
            let reused = try self.persistedAction(retryReply, in: store, chatID: chatID)
            XCTAssertEqual(reused.state, .executed)
            XCTAssertEqual(reused.targetItemID, originalID)
            XCTAssertEqual(store.courseNotes(in: courseID).count, 1)

            let different = "# 同名笔记\n\n不同正文"
            let conflict = AgentReplyAction(kind: .writeNote, proposedMarkdown: different)
            let conflictReply = try await self.append(conflict, to: store, courseID: courseID, chatID: chatID)
            await store.confirmAgentReplyAction(messageID: conflictReply.id, actionID: conflict.id)
            let kept = try self.persistedAction(conflictReply, in: store, chatID: chatID)
            XCTAssertEqual(kept.state, .executed)
            XCTAssertNotEqual(kept.targetItemID, originalID)
            XCTAssertEqual(store.courseNotes(in: courseID).count, 2)
            let keptURL = try XCTUnwrap(store.importedItems.first { $0.id == kept.targetItemID }?.url)
            XCTAssertEqual(try String(contentsOf: originalURL, encoding: .utf8), original)
            XCTAssertEqual(try String(contentsOf: keptURL, encoding: .utf8), different)
        }
    }

    private func makeWorkspace() throws -> (URL, WorkspaceStore, UUID, UUID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = root.appendingPathComponent("资料库")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(workspaceDirectory: root.appendingPathComponent("Workspace"),
                                   noteBackupRootURL: root.appendingPathComponent("Backups"),
                                   startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "动作保存课")
        let session = try XCTUnwrap(store.createStudySession(courseID: courseID))
        let index = try XCTUnwrap(store.studySessions.firstIndex { $0.id == session.id })
        store.studySessions[index].relatedCourseIDs = [courseID]
        return (root, store, courseID, session.id)
    }

    private func append(_ action: AgentReplyAction, to store: WorkspaceStore,
                        courseID: UUID, chatID: UUID) async throws -> AgentMessage {
        let reply = AgentMessage(role: .assistant, text: "建议", source: nil, actions: [action],
                                 origin: AgentReplyOrigin(requestID: UUID(), chatID: chatID, courseID: courseID))
        store.appendAgentMessage(reply)
        let saved = await store.flushPendingWorkspaceSaveAsync()
        XCTAssertTrue(saved)
        return reply
    }

    private func persistedAction(_ reply: AgentMessage, in store: WorkspaceStore,
                                 chatID: UUID) throws -> AgentReplyAction {
        let url = StudySessionMessageFile.fileURL(sessionID: chatID, in: store.workspaceDirectory)
        let payload = try StudySessionMessageFile.decoder().decode(
            PersistedStudySessionMessages.self, from: Data(contentsOf: url)
        )
        return try XCTUnwrap(payload.messages.first { $0.id == reply.id }?.actions.first)
    }
}
