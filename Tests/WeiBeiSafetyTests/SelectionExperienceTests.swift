import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import WeiBei
import WeiBeiCore

final class SelectionExperienceTests: XCTestCase {
    @MainActor
    func testClearingReaderSelectionRemovesCapsuleAndAutomaticAttachment() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.layout = .documentAgentNotes
        store.showAgent = true
        store.updateSelection("刚选中的原文", source: .document, anchor: SelectionPopoverAnchor(x: 200, y: 100))
        XCTAssertEqual(store.selectionAttachments.count, 1)
        XCTAssertEqual(store.agentSurface, .selectionFloat)
        store.updateSelection("", source: .document)
        XCTAssertNil(store.selectionContext)
        XCTAssertNil(store.selectionAnchor)
        XCTAssertNotEqual(store.agentSurface, .selectionFloat)
        XCTAssertNil(store.automaticSelection)
        XCTAssertTrue(store.selectionAttachments.isEmpty)
    }

    @MainActor
    func testSelectionClearPreservesManualAttachmentsAndOpenedQuestion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.layout = .documentAgentNotes
        store.showAgent = true
        let manual = SelectionContext(text: "手动保留的另一段", source: .note, ownerTitle: "笔记")
        store.addSelectionAttachment(manual)
        store.updateSelection("准备提问的原文", source: .document, anchor: SelectionPopoverAnchor(x: 200, y: 100))
        store.updateSelection("", source: .note)
        XCTAssertEqual(store.selectionAttachments.count, 2, "Another reader's empty event must not remove the active passage")
        store.askSelection()
        let threadID = try XCTUnwrap(store.activeSelectionAskThreadID)
        store.updateSelection("", source: .document)
        XCTAssertNil(store.automaticSelection)
        XCTAssertEqual(store.selectionAttachments.map(\.text), [manual.text])
        XCTAssertEqual(store.activeSelectionAskThreadID, threadID)
        XCTAssertEqual(store.selectionContext?.text, "准备提问的原文")
        XCTAssertEqual(store.agentSurface, .selectionFloat)
    }

    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testAutomaticSelectionAndIndependentQuestionUseTheirOwnDraftsAndHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let savedEfforts = UserDefaults.standard.object(forKey: "agentReasoningEfforts")
        defer { UserDefaults.standard.set(savedEfforts, forKey: "agentReasoningEfforts") }
        store.agentProviderID = .openai
        store.modelName = "gpt-5.6-sol"
        store.agentReasoningEfforts[store.agentReasoningModelKey] = "max"
        let mainID = try XCTUnwrap(store.createStudySession(courseID: nil)?.id)
        store.layout = .documentAgentNotes
        store.showAgent = true
        store.selectedItemID = "document-a"
        store.saveComposerDraft("主会话未发送的草稿", for: mainID)
        store.updateSelection("公式 A 的原文", source: .document, anchor: SelectionPopoverAnchor(x: 200, y: 100))
        let attachment = try XCTUnwrap(store.selectionAttachments.first)
        XCTAssertEqual(attachment.text, "公式 A 的原文")
        XCTAssertNil(store.activeSelectionAskThreadID)
        store.askSelection()
        let firstID = try XCTUnwrap(store.activeSelectionAskThreadID)
        XCTAssertNotEqual(firstID, mainID)
        XCTAssertEqual(store.selectionAttachments, [attachment])
        XCTAssertEqual(store.composerDraft(for: mainID), "主会话未发送的草稿")
        store.saveComposerDraft("解释公式 A", for: firstID)
        var submitted: StudyAgentRequest?
        store.selfCheckAgentResponder = { request in
            submitted = request
            return StudyAgentReply(text: "公式 A 的解释", backend: .native)
        }
        store.submitAgentDraft(sessionID: firstID)
        let done = expectation(description: "independent question persisted")
        Task { @MainActor in
            await store.agentRuns[firstID]?.agentRequestTask?.value
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(submitted?.reasoningEffort, "low")
        XCTAssertEqual(submitted?.projectScope.chatID, firstID.uuidString.lowercased())
        XCTAssertEqual(submitted?.selectionSources.first?.excerpt, "公式 A 的原文")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.conversationMessages(in: firstID).map(\.text), ["解释公式 A", "公式 A 的解释"])
        XCTAssertEqual(store.composerDraft(for: firstID), "")
        XCTAssertEqual(store.composerDraft(for: mainID), "主会话未发送的草稿")
        XCTAssertEqual(store.selectionAttachments, [attachment])
        store.dismissFloatingSelectionAgent()
        XCTAssertEqual(store.selectionAttachments, [attachment])
        store.removeSelectionAttachment(id: attachment.id)
        store.updateSelection("公式 A 的原文", source: .document, anchor: nil)
        XCTAssertTrue(store.selectionAttachments.isEmpty)
        store.updateSelection("公式 B 的原文", source: .document, anchor: SelectionPopoverAnchor(x: 250, y: 150))
        XCTAssertEqual(store.selectionAttachments.map(\.text), ["公式 B 的原文"])
        store.askSelection()
        let secondID = try XCTUnwrap(store.activeSelectionAskThreadID)
        store.saveComposerDraft("还没问完 B", for: secondID)
        XCTAssertNotEqual(firstID, secondID)
        let target = WorkspaceStore.AgentConversationTarget(sessionID: mainID, workingDirectory: root, courseID: nil)
        let found = try store.executeDiscussionTool(.discussionSearch(query: nil, itemID: nil, allChats: false),
            target: target, focusItemIDs: ["document-a"])
        XCTAssertTrue(found.discussions?.contains(where: { $0.id == firstID }) == true)
        let read = try store.executeDiscussionTool(.discussionRead(chatID: firstID), target: target, focusItemIDs: [])
        let replySource = try XCTUnwrap(read.discussions?.first?.messages?.last?.source)
        XCTAssertEqual(replySource.excerpt, "公式 A 的解释")
        XCTAssertTrue(store.openAgentReplySource(replySource))
        XCTAssertEqual(store.activeStudySessionID, mainID)
        XCTAssertEqual(store.activeSelectionAskThreadID, firstID)
        XCTAssertEqual(store.selectionChatRevealMessageID, replySource.messageID)
        store.retryAgentRequest("再解释公式 A", sessionID: firstID)
        let retried = expectation(description: "retry stays in its discussion")
        Task { @MainActor in
            await store.agentRuns[firstID]?.agentRequestTask?.value
            retried.fulfill()
        }
        wait(for: [retried], timeout: 10)
        XCTAssertEqual(store.conversationMessages(in: firstID).suffix(2).map(\.text), ["再解释公式 A", "公式 A 的解释"])
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.composerDraft(for: mainID), "主会话未发送的草稿")
        XCTAssertEqual(submitted?.reasoningEffort, "low", "Retry keeps floating effort low")
        store.submitAgentDraft(sessionID: mainID)
        let mainDone = expectation(description: "main effort reaches request")
        Task { @MainActor in
            await store.agentRuns[mainID]?.agentRequestTask?.value
            mainDone.fulfill()
        }
        wait(for: [mainDone], timeout: 10)
        XCTAssertEqual(submitted?.reasoningEffort, "max")
        let (mainStream, mainContinuation) = AsyncStream<Void>.makeStream()
        let (floatStream, floatContinuation) = AsyncStream<Void>.makeStream()
        let mainTask = Task { for await _ in mainStream {} }
        let floatTask = Task { for await _ in floatStream {} }
        defer { mainContinuation.finish(); floatContinuation.finish(); mainTask.cancel(); floatTask.cancel() }
        let mainRun = AgentConversationRun(chatID: mainID)
        mainRun.agentRequestTask = mainTask
        let floatRun = AgentConversationRun(chatID: firstID)
        floatRun.agentRequestTask = floatTask
        store.agentRuns[mainID] = mainRun
        store.agentRuns[firstID] = floatRun
        store.cancelAgentRequest(in: firstID)
        XCTAssertTrue(floatTask.isCancelled)
        XCTAssertFalse(mainTask.isCancelled)
        XCTAssertTrue(store.flushPendingWorkspaceSave())
        let reopened = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        reopened.openSelectionAskThread(secondID)
        XCTAssertEqual(reopened.composerDraft(for: secondID), "还没问完 B")
        XCTAssertEqual(reopened.floatingAgentDraft, "还没问完 B")
        reopened.openSelectionAskThread(firstID)
        XCTAssertEqual(reopened.floatingAgentDraft, "")
        XCTAssertEqual(reopened.conversationMessages(in: firstID).map(\.text), ["解释公式 A", "公式 A 的解释", "再解释公式 A", "公式 A 的解释"])
        XCTAssertFalse(reopened.orderedStudySessions.contains(where: { $0.id == firstID || $0.id == secondID }))
    }

    @MainActor
    func testOldSelectionDiscussionKeepsOriginalMessagesAndFailedReadsDoNotOverwriteHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let main = try XCTUnwrap(store.createStudySession(courseID: nil))
        let original = [AgentMessage(role: .user, text: "旧问题", source: nil),
                        AgentMessage(role: .assistant, text: "旧回答", source: nil)]
        original.forEach(store.appendAgentMessage)
        let thread = SelectionAskThread(selectionText: "旧原文", source: .document,
            ownerTitle: "旧资料", messageIDs: original.map(\.id))
        store.selectionAskThreads.append(thread)
        try store.ensureSelectionChat(thread)
        let separate = store.conversationMessages(in: thread.id)
        XCTAssertEqual(store.messages, original)
        XCTAssertEqual(separate.map(\.text), original.map(\.text))
        XCTAssertTrue(Set(separate.map(\.id)).isDisjoint(with: original.map(\.id)))
        XCTAssertTrue(separate.allSatisfy { $0.origin?.chatID == thread.id }, "Restoring or retrying an old question must target its floating discussion")
        XCTAssertEqual(store.selectionAskThreads.first?.messageIDs, separate.map(\.id))
        XCTAssertTrue(store.flushPendingWorkspaceSave())

        let file = StudySessionMessageFile.fileURL(sessionID: thread.id, in: root)
        let damaged = Data("{".utf8)
        try damaged.write(to: file, options: .atomic)
        let reopened = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let target = WorkspaceStore.AgentConversationTarget(sessionID: main.id, workingDirectory: root, courseID: nil)
        XCTAssertThrowsError(try reopened.executeDiscussionTool(.discussionRead(chatID: thread.id),
            target: target, focusItemIDs: []))
        XCTAssertTrue(reopened.flushPendingWorkspaceSave())
        XCTAssertEqual(try Data(contentsOf: file), damaged)
        XCTAssertEqual(reopened.studySessions.first(where: { $0.id == thread.id })?.messageCount, original.count)
        XCTAssertEqual(reopened.conversationMessages(in: main.id), original)
    }

    @MainActor
    func testExcerptBooksPersistByCourseWithoutChangingTheNote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let firstCourse = UUID(), secondCourse = UUID()
        let anchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 0, lineRects: [SelectionRect(x: 20, y: 60, width: 80, height: 16)]))
        store.noteText = "我正在写的笔记"
        for (course, item) in [(firstCourse, "a.pdf"), (firstCourse, "b.pdf"), (secondCourse, "c.pdf")] {
            store.activeCourseID = course
            store.selectionContext = SelectionContext(text: "相同原文", source: .document, ownerTitle: item, itemID: item, documentAnchor: anchor)
            _ = try store.beginOrReuseSelectionAskThread(for: store.selectionContext!)
            let saved = saveRemark("我的批注", in: store)
            XCTAssertTrue(saved)
        }
        XCTAssertEqual(store.selectionAskThreads.count, 3, "Same PDF coordinates in different documents must not share a question")
        XCTAssertEqual(store.excerpts(in: firstCourse).map(\.itemID), ["a.pdf", "b.pdf"])
        XCTAssertEqual(store.excerpts(in: secondCourse).map(\.itemID), ["c.pdf"])
        XCTAssertEqual(store.noteText, "我正在写的笔记")
        XCTAssertNil(store.noteEditorCommand)
        XCTAssertEqual(store.selectionRemarkRecords(forItemID: "c.pdf").count, 1)
        let reopened = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        XCTAssertEqual(reopened.excerpts(in: firstCourse), store.excerpts(in: firstCourse))
        XCTAssertEqual(reopened.excerpts(in: secondCourse), store.excerpts(in: secondCourse))
    }

    @MainActor
    func testAskKeepsThePassageAndFloatingInputInEveryReadingLayout() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        for layout in [WorkspaceLayout.immersiveReading, .documentAgentNotes] {
            store.layout = layout
            store.showAgent = true
            let anchor = SelectionPopoverAnchor(x: 320, y: 210)
            store.updateSelection("原处提问", source: .document, anchor: anchor)
            store.askSelection()
            XCTAssertEqual(store.layout, layout)
            XCTAssertEqual(store.agentSurface, .selectionFloat)
            XCTAssertEqual(store.selectionAnchor, anchor)
            XCTAssertTrue(store.keepFloatingSelectionForAnswer)
        }
    }

    @MainActor
    func testOpeningQuestionFocusesTheMountedInputWithoutAnotherClick() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.updateSelection("直接开始提问", source: .document, anchor: SelectionPopoverAnchor(x: 200, y: 100))
        store.askSelection()
        let host = NSHostingView(rootView: FloatingSelectionAgentView(expanded: .constant(true))
            .environmentObject(store).environmentObject(store.paneState).environmentObject(store.interaction))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 180),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        // The window stays hidden; no activation or input on the user's desktop.
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if window.firstResponder is NSTextView { break }
        }
        XCTAssertTrue(window.firstResponder is NSTextView)
    }

    @MainActor
    func testOpenedQuestionStaysBesideThePassageWhenReaderReportsSelectionAgain() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let textAnchor = SelectionTextAnchor(startOffset: 0, endOffset: 7)
        let anchor = SelectionPopoverAnchor(x: 320, y: 210, textAnchor: textAnchor)
        store.updateSelection("准备提问的原文", source: .document, anchor: anchor)
        store.askSelection()
        let selection = store.selectionContext
        store.updateSelection("准备提问的原文", source: .document, anchor: nil)
        store.updateSelection("准备提问的原文", source: .document, anchor: SelectionPopoverAnchor(x: 600, y: 440, textAnchor: textAnchor))
        XCTAssertEqual(store.selectionAnchor, anchor)
        XCTAssertEqual(store.selectionContext, selection)
        XCTAssertEqual(store.agentSurface, .selectionFloat)
        XCTAssertFalse(store.pinnedFloatingAgent)
    }

    @MainActor
    func testSelectingInAnotherReaderStartsWithCompactActions() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.selectedItemID = "first-document"
        store.updateSelection("两份同名文稿里的相同原文", source: .document, anchor: SelectionPopoverAnchor(x: 200, y: 100), ownerTitle: "文稿")
        store.askSelection()
        // An answer still running must not keep a different passage's actions expanded.
        let chatID = UUID()
        store.activeStudySessionID = chatID
        let run = AgentConversationRun(chatID: chatID)
        run.agentRequestTask = Task {}
        store.agentRuns[chatID] = run
        XCTAssertTrue(store.isAgentRunningInActiveChat)
        var expanded = false
        let host = NSHostingView(rootView: FloatingSelectionAgentView(
            expanded: Binding(get: { expanded }, set: { expanded = $0 }))
            .environmentObject(store).environmentObject(store.paneState).environmentObject(store.interaction))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if expanded { break }
        }
        XCTAssertTrue(expanded)
        store.selectedItemID = "second-document"
        store.updateSelection("两份同名文稿里的相同原文", source: .document, anchor: SelectionPopoverAnchor(x: 600, y: 400), ownerTitle: "文稿")
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            if !expanded { break }
        }
        XCTAssertFalse(expanded)
        XCTAssertTrue(store.isAgentRunningInActiveChat)
        XCTAssertEqual(store.agentSurface, .selectionFloat)
        XCTAssertFalse(store.keepFloatingSelectionForAnswer)
        XCTAssertNil(store.activeSelectionAskThreadID)
        XCTAssertEqual(store.selectionContext?.itemID, "second-document")
    }

    @MainActor
    func testPinnedQuestionKeepsItsPassageAndPositionUntilUnpinned() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let anchor = SelectionPopoverAnchor(x: 320, y: 210)
        store.updateSelection("固定的原文", source: .document, anchor: anchor)
        store.askSelection()
        store.pinnedFloatingAgent = true
        let selection = store.selectionContext
        store.updateSelection("另外一处原文", source: .document, anchor: SelectionPopoverAnchor(x: 600, y: 440))
        store.updateSelection("", source: .document)
        XCTAssertEqual(store.selectionContext, selection)
        XCTAssertEqual(store.selectionAnchor, anchor)
        store.pinnedFloatingAgent = false
        store.updateSelection("另外一处原文", source: .document, anchor: SelectionPopoverAnchor(x: 600, y: 440))
        XCTAssertEqual(store.selectionContext?.text, "另外一处原文")
    }

    func testExcerptsFollowDocumentPositionsInsteadOfCaptureTime() {
        let later = SelectionRemarkRecord(selectionText: "后段", remarkText: "", source: .document, ownerTitle: "文稿",
            documentAnchor: SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: 20, endOffset: 22)))
        var earlier = later
        earlier.id = UUID()
        earlier.documentAnchor = SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: 0, endOffset: 2))
        earlier.createdAt = later.createdAt.addingTimeInterval(10)
        var unlocated = later
        unlocated.id = UUID()
        unlocated.documentAnchor = nil
        XCTAssertEqual([later, unlocated, earlier].sorted(by: SelectionRemarkRecord.inDocumentOrder).map(\.id), [earlier.id, later.id, unlocated.id])
        earlier.documentAnchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 1, lineRects: [SelectionRect(x: 20, y: 500, width: 50, height: 16)]))
        var lower = later
        lower.documentAnchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 1, lineRects: [SelectionRect(x: 20, y: 100, width: 50, height: 16)]))
        var nextPage = unlocated
        nextPage.documentAnchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 2, lineRects: [SelectionRect(x: 20, y: 600, width: 50, height: 16)]))
        XCTAssertEqual([nextPage, lower, earlier].sorted(by: SelectionRemarkRecord.inDocumentOrder).map(\.id), [earlier.id, lower.id, nextPage.id])
    }

    @MainActor
    func testReturningFromBookOpensSourceAndCarriesItsExactAnchor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("source.md")
        try "同一句\n\n第二处同一句".write(to: file, atomically: true, encoding: .utf8)
        let item = StudyItem(id: "source", title: "文稿", subtitle: "", kind: .markdown, urlPath: file.path, isSample: false)
        store.importedItems = [item]
        let record = SelectionRemarkRecord(selectionText: "同一句", remarkText: "批注", source: .document, ownerTitle: item.title, itemID: item.id,
            documentAnchor: SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: 6, endOffset: 9)))
        store.selectionRemarkRecords = [record]
        store.openExcerptBook(courseID: nil, at: record.id)
        store.openExcerptSource(record)
        XCTAssertFalse(store.excerptBookPresented)
        XCTAssertEqual(store.selectedMaterialItem?.id, item.id)
        let request = try XCTUnwrap(store.excerptRevealRequest)
        XCTAssertEqual(request.recordID, record.id)
        let json = selectionRemarkMarksJSON([record], activeID: record.id, revealRequest: request)
        let marks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(marks.first?["reveal"] as? String, request.id.uuidString)
        XCTAssertEqual((marks.first?["anchor"] as? [String: Int])?["startOffset"], 6)
        XCTAssertEqual(marks.first?["active"] as? Bool, true)
        XCTAssertNil(store.noteEditorCommand, "Returning to a source must not insert anything into a note")
        store.openExcerptSource(record)
        XCTAssertNotEqual(store.excerptRevealRequest?.id, request.id, "Returning again must issue a fresh scroll request")
    }

    @MainActor
    func testPendingRemarkKeepsTheSubmittedPassageWhenSelectionChanges() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let courseID = UUID()
        let submitted = SelectionContext(text: "提交时的文段", source: .document, ownerTitle: "文稿 A", itemID: "a")
        let newer = SelectionContext(text: "随后选中的文段", source: .document, ownerTitle: "文稿 B", itemID: "b")
        store.selectionContext = newer
        store.activeCourseID = UUID()
        let completed = expectation(description: "submitted excerpt saved")
        Task { @MainActor in
            let saved = await store.saveSelectionRemark("批注", for: submitted, courseID: courseID)
            XCTAssertTrue(saved)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(store.excerpts(in: courseID).first?.itemID, "a")
        XCTAssertEqual(store.selectionContext?.id, newer.id)
    }

    @MainActor
    func testRepeatedPassagesStayIndependentAndRemarkFailureKeepsDraft() throws {
        struct CannotWrite: Error {}
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, workspaceSnapshotWriter: { _, _ in throw CannotWrite() }, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.interaction.selectionNoteDraft = "还没写入的批注"
        for start in [0, 20] {
            let selection = SelectionContext(text: "同一句", source: .document, ownerTitle: "一篇文稿", itemID: "same.md", documentAnchor: SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: start, endOffset: start + 3)))
            store.selectionContext = selection
            _ = try store.beginOrReuseSelectionAskThread(for: selection)
            let saved = saveRemark(store.interaction.selectionNoteDraft, in: store)
            XCTAssertFalse(saved)
        }
        XCTAssertEqual(store.selectionAskThreads.count, 2)
        XCTAssertEqual(store.selectionRemarkRecords.count, 2)
        XCTAssertEqual(store.interaction.selectionNoteDraft, "还没写入的批注")
        XCTAssertNil(store.noteEditorCommand)
        let record = store.selectionRemarkRecords[0]
        let focusRequest = store.paneState.focusRequest
        store.openSelectionRemarkRecord(record.id.uuidString, anchor: SelectionPopoverAnchor(x: 300, y: 180))
        XCTAssertEqual(store.selectionContext?.id, record.id)
        XCTAssertEqual(store.selectionAnchor?.y, 180)
        XCTAssertTrue(store.keepFloatingSelectionForAnswer)
        XCTAssertEqual(store.interaction.selectionNoteDraft, "还没写入的批注", "Viewing a saved remark must preserve the unsubmitted draft")
        XCTAssertEqual(store.paneState.focusRequest, focusRequest, "Viewing a remark must not request input focus")
        store.updateSelection("", source: .note)
        XCTAssertEqual(store.selectionContext?.id, record.id, "An unrelated pane losing selection must not dismiss the open remark")
        store.openExcerptBook(courseID: store.excerptCourseID(for: record), at: record.id)
        XCTAssertTrue(store.excerptBookPresented)
        XCTAssertEqual(store.excerptBookTargetRecordID, record.id)
        XCTAssertFalse(store.keepFloatingSelectionForAnswer)
    }
}

@MainActor
extension XCTestCase {
    // WorkspaceStore has synchronous startup file operations; construct it outside an async task.
    func saveRemark(_ text: String, in store: WorkspaceStore) -> Bool {
        guard let selection = store.selectionContext else { return false }
        let courseID = store.activeCourseID
        let completed = expectation(description: "remark persistence completed")
        var saved = false
        Task { @MainActor in
            saved = await store.saveSelectionRemark(text, for: selection, courseID: courseID)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        return saved
    }
}
