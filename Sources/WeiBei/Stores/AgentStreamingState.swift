import Combine
import Foundation
import WeiBeiCore

@MainActor
final class AgentStreamingState: ObservableObject {
    @Published var text = ""
    @Published var activityText: String?
    @Published private(set) var displayingMessageID: UUID?
    @Published private(set) var displayingChatID: UUID?

    private var activityArrivals: [String: Date] = [:]

    func activityArrivalTimes(for ids: [String], messageID: UUID, now: Date = Date()) -> [String: Date] {
        guard isDisplaying(messageID) else { return [:] }
        var delay = 0.09
        for id in ids where activityArrivals[id] == nil {
            activityArrivals[id] = now.addingTimeInterval(delay)
            delay += 0.065
        }
        return activityArrivals.filter { ids.contains($0.key) }
    }

    func begin(messageID: UUID, chatID: UUID) {
        text = ""
        activityArrivals.removeAll(keepingCapacity: true)
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
