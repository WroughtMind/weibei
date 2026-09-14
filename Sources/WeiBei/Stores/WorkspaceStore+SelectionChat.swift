import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func composerDraft(for sessionID: UUID?) -> String {
        guard let sessionID else { return "" }
        if sessionID == activeStudySessionID { return pendingComposerDraft ?? agentDraft }
        return agentDraftsBySessionID[sessionID]
            ?? studySessions.first(where: { $0.id == sessionID })?.draft ?? ""
    }

    func saveComposerDraft(_ draft: String, for sessionID: UUID?) {
        guard let sessionID else { return }
        agentDraftsBySessionID[sessionID] = draft
        if sessionID == activeStudySessionID { pendingComposerDraft = draft }
        save()
    }

    func replaceComposerDraft(_ draft: String, for sessionID: UUID) {
        saveComposerDraft(draft, for: sessionID)
        if let index = studySessions.firstIndex(where: { $0.id == sessionID }) {
            studySessions[index].draft = draft
        }
        if sessionID == activeStudySessionID { agentDraft = draft }
        if sessionID == activeSelectionAskThreadID { floatingAgentDraft = draft }
    }

    func conversationMessages(in sessionID: UUID?) -> [AgentMessage] {
        guard let sessionID else { return [] }
        return sessionID == activeStudySessionID ? messages
            : studySessions.first(where: { $0.id == sessionID })?.messages ?? []
    }

    func streaming(in sessionID: UUID?) -> AgentStreamingState {
        sessionID.flatMap { agentRuns[$0]?.streaming } ?? idleAgentRun.streaming
    }

    var isFloatingChatRunning: Bool {
        activeSelectionAskThreadID.map { isAgentRunning(in: $0) } ?? false
    }

    func clearAutomaticSelectionAttachment() {
        if let id = automaticSelection?.id {
            selectionAttachments.removeAll { $0.id == id }
        }
        automaticSelection = nil
    }

    func updateAutomaticSelection(_ selection: SelectionContext) {
        guard isConversationSurfaceVisible else { return }
        if let previous = automaticSelection,
           previous.text == selection.text, previous.itemID == selection.itemID,
           previous.source == selection.source,
           selection.documentAnchor == nil || previous.documentAnchor == selection.documentAnchor {
            return
        }
        clearAutomaticSelectionAttachment()
        automaticSelection = selection
        selectionAttachments.append(selection)
        invalidateAgentContext()
    }

    func selectionChatContext(_ thread: SelectionAskThread) -> SelectionContext {
        SelectionContext(id: thread.id, text: thread.selectionText, source: thread.source,
            ownerTitle: thread.ownerTitle, itemID: thread.itemID, isEditable: thread.source == .note,
            documentAnchor: thread.documentAnchor)
    }

    private func ledgerURL(for sessionID: UUID) -> URL {
        workspaceDirectory.appendingPathComponent("NativeAgent/Ledgers", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("ledger.jsonl")
    }

    func ensureSelectionChat(_ thread: SelectionAskThread) throws {
        if studySessions.contains(where: { $0.id == thread.id }) {
            _ = try loadDiscussion(thread.id)
            return
        }
        var history: [AgentMessage] = []
        if !thread.messageIDs.isEmpty {
            ensureAllStudySessionMessagesLoaded()
            let saved = studySessions.flatMap(\.messages)
            for messageID in thread.messageIDs {
                guard var message = saved.first(where: { $0.id == messageID }) else {
                    throw AgentConversationTargetError(message: ui("原问答尚未完整读取，内容没有改动。", "The original discussion could not be fully read. Its content is unchanged."))
                }
                message.id = UUID()
                message.origin = AgentReplyOrigin(requestID: message.origin?.requestID ?? UUID(),
                    chatID: thread.id, courseID: message.origin?.courseID)
                history.append(message)
            }
            try NativeAgentLedger.importConversation(history, to: ledgerURL(for: thread.id))
        } else if let parentID = thread.parentSessionID {
            let source = ledgerURL(for: parentID)
            if FileManager.default.fileExists(atPath: source.path) {
                try NativeAgentLedger.forkCompletedHistory(from: source, to: ledgerURL(for: thread.id))
            } else {
                // Older saved chats have visible messages but no native ledger.
                let parent = try loadDiscussion(parentID)
                try NativeAgentLedger.importConversation(parent.messages, to: ledgerURL(for: thread.id))
            }
        }
        let parent = studySessions.first { $0.id == thread.parentSessionID }
        let session = StudySession(id: thread.id, title: thread.ownerTitle, messages: history,
            relatedCourseIDs: parent?.relatedCourseIDs, focusItemIDs: [thread.itemID].compactMap { $0 },
            materialItemID: thread.source == .document ? thread.itemID : nil)
        studySessions.append(session)
        sessionMessagePersistence.markLoaded(session.id)
        if let index = selectionAskThreads.firstIndex(where: { $0.id == thread.id }) {
            selectionAskThreads[index].messageIDs = history.map(\.id)
        }
        save()
    }

    private func loadDiscussion(_ id: UUID) throws -> StudySession {
        guard let session = loadStudySessionForActivation(id) else {
            throw AgentConversationTargetError(message: ui("这段问答无法完整读取，原记录已保留。", "This discussion could not be fully read. The saved history is unchanged."))
        }
        return session
    }

    func executeDiscussionTool(_ request: StudyAgentHostToolRequest, target: AgentConversationTarget,
                               focusItemIDs: Set<String>) throws -> StudyAgentHostToolResult {
        guard studySessions.contains(where: { $0.id == target.sessionID }) else {
            throw AgentConversationTargetError(message: ui("原会话已删除。", "The original conversation was deleted."))
        }
        switch request {
        case let .discussionSearch(query, itemID, allChats):
            let parentID = selectionAskThreads.first(where: { $0.id == target.sessionID })?.parentSessionID ?? target.sessionID
            let matchingThreads = selectionAskThreads.filter { thread in
                if let itemID { return thread.itemID == itemID }
                return allChats || thread.parentSessionID == parentID
                    || thread.itemID.map(focusItemIDs.contains) == true
            }
            for thread in matchingThreads { try ensureSelectionChat(thread) }
            let threadIDs = Set(matchingThreads.map(\.id))
            let sessions = studySessions.filter { session in
                guard session.id != target.sessionID, session.hasChatHistory else { return false }
                if threadIDs.contains(session.id) { return true }
                if selectionAskThreads.contains(where: { $0.id == session.id }) { return false }
                if let itemID { return session.focusItemIDs.contains(itemID) || session.materialItemID == itemID }
                return allChats || session.id == parentID
            }
            var discussions: [StudyAgentDiscussion] = []
            for session in sessions {
                let messages = try loadDiscussion(session.id).messages
                let thread = selectionAskThreads.first { $0.id == session.id }
                if let query, ![session.title, thread?.selectionText ?? "", messages.map(\.text).joined(separator: "\n")]
                    .contains(where: { $0.localizedCaseInsensitiveContains(query) }) { continue }
                discussions.append(StudyAgentDiscussion(id: session.id, title: session.title,
                    sourceTitle: thread?.ownerTitle, selection: thread?.selectionText,
                    lastQuestionAt: messages.last(where: { $0.role == .user })?.createdAt))
            }
            discussions.sort { ($0.lastQuestionAt ?? .distantPast) > ($1.lastQuestionAt ?? .distantPast) }
            return StudyAgentHostToolResult(query: query ?? "", items: [], discussions: discussions)
        case let .discussionRead(chatID):
            if let thread = selectionAskThreads.first(where: { $0.id == chatID }) { try ensureSelectionChat(thread) }
            let session = try loadDiscussion(chatID)
            let thread = selectionAskThreads.first { $0.id == chatID }
            let entries = conversationMessages(in: chatID).map { message in
                var source = AgentReplySource(itemID: thread?.itemID, kind: .discussion,
                    title: session.title, label: "", excerpt: message.text)
                source.discussionID = chatID
                source.messageID = message.id
                return StudyAgentDiscussionMessage(role: message.role, completionState: message.completionState, source: source)
            }
            return StudyAgentHostToolResult(query: "", items: [], discussions: [
                StudyAgentDiscussion(id: chatID, title: session.title, sourceTitle: thread?.ownerTitle,
                    selection: thread?.selectionText, messages: entries)
            ])
        default:
            throw AgentConversationTargetError(message: "不是问答读取请求")
        }
    }
}
