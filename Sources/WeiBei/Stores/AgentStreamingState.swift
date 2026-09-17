import Combine
import Foundation
import WeiBeiCore

@MainActor
final class AgentStreamingState: ObservableObject {
    @Published var text = ""
    @Published var activityText: String?
    @Published private(set) var displayingMessageID: UUID?
    @Published private(set) var displayingChatID: UUID?

    func begin(messageID: UUID, chatID: UUID) {
        text = ""
        displayingMessageID = messageID
        displayingChatID = chatID
    }

    func isDisplaying(_ messageID: UUID) -> Bool {
        displayingMessageID == messageID
    }

    func applyingDisplayText(to message: AgentMessage) -> AgentMessage {
        guard isDisplaying(message.id) else { return message }
        var visible = message
        visible.text = text
        // This is a presentation snapshot. The saved reply remains complete.
        if visible.completionState == .completed { visible.completionState = .generating }
        return visible
    }

    func finishDisplaying() {
        displayingMessageID = nil
        displayingChatID = nil
        activityText = nil
    }

    func reset() {
        text = ""
        activityText = nil
        displayingMessageID = nil
        displayingChatID = nil
    }
}
