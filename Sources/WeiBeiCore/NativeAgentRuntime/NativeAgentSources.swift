import Foundation

enum NativeAgentSources {
    static func label(_ source: AgentReplySource, turn: Int, index: Int) -> AgentReplySource {
        var source = source
        let kind = source.kind == .discussion ? "问答" : source.kind == .selection ? "选区" : (source.kind == .note ? "笔记" : "材料")
        source.label = "[\(kind)：r\(turn).\(index)]"
        return source
    }

    static func attach(to result: inout NativeToolExecutionResult, name: String, turn: Int, index: inout Int) {
        guard !result.isError, name == "weibei_course_read" || name == "weibei_search_workspace" || name == "weibei_read_discussion",
              var payload = try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(result.text.utf8)) else { return }
        for itemIndex in payload.items.indices {
            guard let source = payload.items[itemIndex].source, !source.excerpt.isEmpty else { continue }
            index += 1
            payload.items[itemIndex].source = label(source, turn: turn, index: index)
        }
        if var discussions = payload.discussions {
            for discussionIndex in discussions.indices {
                guard var messages = discussions[discussionIndex].messages else { continue }
                for messageIndex in messages.indices {
                    index += 1
                    messages[messageIndex].source = label(messages[messageIndex].source, turn: turn, index: index)
                }
                discussions[discussionIndex].messages = messages
            }
            payload.discussions = discussions
        }
        if let data = try? JSONEncoder().encode(payload), let text = String(data: data, encoding: .utf8) {
            result.text = text
        }
    }

    static func used(in text: String, available: [AgentReplySource]) -> [AgentReplySource] {
        var labels = Set<String>()
        return available.filter { !$0.label.isEmpty && text.contains($0.label) && labels.insert($0.label).inserted }
    }

    static func fromToolText(_ text: String, aliases: NativeStateAliases? = nil) -> [AgentReplySource] {
        guard let payload = try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(text.utf8)) else { return [] }
        let sources = payload.items.compactMap(\.source)
            + (payload.discussions ?? []).flatMap { ($0.messages ?? []).map(\.source) }
        return sources
            .map { aliases?.resolving($0) ?? $0 }
            .filter { !$0.label.isEmpty && !$0.excerpt.isEmpty }
    }
}
