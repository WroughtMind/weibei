import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func applyStudySessionsFromSnapshot(_ snapshot: PersistedWorkspace) {
        let incoming = (snapshot.studySessions ?? []).map { session in
            interruptedGeneratingMessages(in: session)
        }
        studySessions = incoming
        sessionMessagePersistence.resetLoadedSessions()
        let hadEmbeddedMessages = incoming.contains { !$0.messages.isEmpty }
        if hadEmbeddedMessages {
            do {
                if try !sessionMessagePersistence.migrateEmbeddedMessages(incoming) {
                    reportSessionMessageExternalizationFailure(nil)
                }
            } catch {
                reportSessionMessageExternalizationFailure(error)
            }
        } else {
            if let activeID = snapshot.activeStudySessionID {
                ensureStudySessionMessagesLoaded(activeID)
            }
        }
    }

    func loadStudySessionForActivation(_ id: UUID?) -> StudySession? {
        guard let id else { return nil }
        ensureStudySessionMessagesLoaded(id)
        return studySessions.first { $0.id == id }
    }

    func ensureStudySessionMessagesLoaded(_ id: UUID) {
        guard let index = studySessions.firstIndex(where: { $0.id == id }),
              let messages = sessionMessagePersistence.messagesIfNeeded(for: id) else {
            return
        }
        studySessions[index].messages = interruptingGenerating(messages)
        studySessions[index].messageCount = studySessions[index].messages.count
        sessionMessagePersistence.didLoad(studySessions[index])
    }

    func ensureAllStudySessionMessagesLoaded() {
        for session in studySessions where session.hasChatHistory {
            ensureStudySessionMessagesLoaded(session.id)
        }
    }

    func ensureStudySessionMessagesLoaded(touchingCourse courseID: UUID) {
        for session in sessionsTouchingCourse(courseID) {
            ensureStudySessionMessagesLoaded(session.id)
        }
    }

    private func reportSessionMessageExternalizationFailure(_ error: Error?) {
        WeiBeiLog.workspace.error(
            "code=session_message_externalization_failed path=\(self.storageURL.path, privacy: .private) reason=\(error?.localizedDescription ?? "validation", privacy: .private)"
        )
        _ = reportWorkspaceSaveFailure(
            .sessionMessageExternalizationFailed,
            ui(
                "聊天记录外置没有完成，已用原来的工作区继续。本次修改仍在当前会话中。",
                "Chat history was not moved into per-session files; WeiBei kept the original workspace. This change remains in the current session."
            ),
            reason: error?.localizedDescription
        )
    }

    private func interruptedGeneratingMessages(in session: StudySession) -> StudySession {
        var bounded = session
        bounded.messages = interruptingGenerating(session.messages)
        return bounded
    }

    private func interruptingGenerating(_ messages: [AgentMessage]) -> [AgentMessage] {
        var next = messages
        for index in next.indices where next[index].completionState == .generating {
            recoveredInterruptedAgentReply = true
            next[index].completionState = .interrupted
            next[index].failureKind = .cancelled
            if next[index].retryQuestion == nil {
                next[index].retryQuestion = next[..<index]
                    .last(where: { $0.role == .user })?
                    .text
            }
        }
        return next
    }
}
