import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    static func semanticSessionTitle(
        from suggestion: String?,
        replacing currentTitle: String,
        messages: [AgentMessage],
        titleSetByUser: Bool = false
    ) -> String? {
        guard !titleSetByUser,
              let firstQuestion = messages.first(where: { $0.role == .user }),
              currentTitle == sessionTitle(from: firstQuestion.text),
              let suggestion,
              !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let title = sessionTitle(from: suggestion)
        let genericTitles = ["WeiBei", "Study Session", "New Chat", "New Conversation", "新对话", "新会话"]
        guard title != currentTitle,
              !genericTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) else {
            return nil
        }
        return title
    }

    @discardableResult
    func applySemanticSessionTitle(_ suggestion: String?, to sessionID: UUID) -> Bool {
        ensureStudySessionMessagesLoaded(sessionID)
        guard let index = studySessions.firstIndex(where: { $0.id == sessionID }),
              let title = Self.semanticSessionTitle(
                  from: suggestion,
                  replacing: studySessions[index].title,
                  messages: studySessions[index].messages,
                  titleSetByUser: studySessions[index].titleSetByUser
              ) else { return false }
        studySessions[index].title = title
        studySessions[index].updatedAt = Date()
        return true
    }

    func applySemanticSessionTitleAndSave(_ suggestion: String, to sessionID: UUID) async {
        guard applySemanticSessionTitle(suggestion, to: sessionID) else { return }
        save()
        _ = await flushPendingWorkspaceSaveAsync()
    }
}
