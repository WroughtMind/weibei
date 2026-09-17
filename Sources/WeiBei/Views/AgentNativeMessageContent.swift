import AppKit
import SwiftUI
import WeiBeiCore

/// Ordered content uses native attachments in the same document while text is paced.
enum AgentNativeMessageContent {
    static func markdown(text: String, blocks: [AgentMessageContentBlock], activities: [AgentToolActivity] = []) -> String {
        let offsets = Set(activities.map { max(0, $0.textOffset ?? text.count) }).sorted()
        var inserted = Set<Int>()
        func decorate(_ value: String, start: Int) -> String {
            var output = "", cursor = value.startIndex, position = start
            for offset in offsets where offset >= start && offset <= start + value.count && !inserted.contains(offset) {
                let end = value.index(cursor, offsetBy: offset - position)
                output += value[cursor..<end]
                output += marker("activity/\(offset)")
                inserted.insert(offset)
                cursor = end; position = offset
            }
            output += value[cursor...]
            return output
        }
        guard blocks.contains(where: { if case .text = $0 { return false }; return true }) else { return decorate(text, start: 0) }
        let hasText = blocks.contains { if case .text = $0 { return true }; return false }
        var remaining = text.count
        var result = hasText ? decorate("", start: 0) : decorate(text, start: 0)
        for (index, block) in blocks.enumerated() {
            switch block {
            case let .text(value):
                let count = min(remaining, value.count)
                result += decorate(String(value.prefix(count)), start: text.count - remaining)
                remaining -= count
                if count < value.count { return result }
            case let .visualization(value):
                result += marker(value.id)
            case .unavailable:
                result += marker("unavailable-\(index)")
            }
        }
        // Text can advance between the existing throttled block publications.
        if hasText, remaining > 0 { result += decorate(String(text.suffix(remaining)), start: text.count - remaining) }
        return result
    }

    private static func marker(_ id: String) -> String {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return "\n\n![图示](weibei-visualization:\(encoded))\n\n"
    }
}

struct AgentInlineToolActivity: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject var streaming: AgentStreamingState
    let messageID: UUID
    let offset: Int

    private var activityMessage: AgentMessage? {
        guard var message = store.studySessions.lazy.flatMap(\.messages).first(where: { $0.id == messageID }) else { return nil }
        let count = message.text.count
        message.toolActivities = message.toolActivities.filter { ($0.textOffset ?? count) == offset }
        return message
    }

    var body: some View {
        if let message = activityMessage {
            let visibleText = streaming.isDisplaying(message.id) ? streaming.text : message.text
            let active = (streaming.isDisplaying(message.id) || message.completionState == .generating)
                && visibleText.count <= offset
            AgentToolActivityGroup(message: message, autoOpen: active)
        }
    }
}

struct AgentNativeContentAttachment: View {
    @EnvironmentObject private var store: WorkspaceStore
    let messageID: UUID
    let identifier: String
    let initialBlocks: [AgentMessageContentBlock]
    let onHeight: (CGFloat) -> Void

    private var blocks: [AgentMessageContentBlock] {
        store.studySessions.lazy.flatMap(\.messages).first(where: { $0.id == messageID })?.contentBlocks ?? initialBlocks
    }

    var body: some View {
        Group {
            if identifier.hasPrefix("activity/"), let offset = Int(identifier.dropFirst("activity/".count)) {
                AgentInlineToolActivity(streaming: store.streaming(in: store.studySessions.first(where: { session in
                    session.messages.contains { $0.id == messageID }
                })?.id), messageID: messageID, offset: offset)
            } else if let visualization = blocks.compactMap({ block -> AgentVisualization? in
                if case let .visualization(value) = block, value.id == identifier { return value }
                return nil
            }).first {
                AgentVisualizationView(messageID: messageID, visualization: visualization)
            } else if identifier.hasPrefix("unavailable-"),
                      let index = Int(identifier.dropFirst("unavailable-".count)),
                      blocks.indices.contains(index),
                      case let .unavailable(type, rawJSON) = blocks[index] {
                UnavailableAgentContentBlockView(type: type, rawJSON: rawJSON)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { onHeight(geometry.size.height) }
                    .onChange(of: geometry.size.height) { _, height in onHeight(height) }
            }
        }
    }
}
