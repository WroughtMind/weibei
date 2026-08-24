import Combine
import Foundation

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
