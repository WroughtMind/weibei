import Foundation

enum NativeAgentSources {
    static func label(_ source: AgentReplySource, turn: Int, index: Int) -> AgentReplySource {
        var source = source
        let kind = source.kind == .selection ? "选区" : (source.kind == .note ? "笔记" : "材料")
        source.label = "[\(kind)：r\(turn).\(index)]"
        return source
    }

    static func attach(to result: inout NativeToolExecutionResult, name: String, turn: Int, index: inout Int) {
        guard !result.isError, name == "weibei_course_read" || name == "weibei_search_workspace",
              var payload = try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(result.text.utf8)) else { return }
        for itemIndex in payload.items.indices {
            guard let source = payload.items[itemIndex].source, !source.excerpt.isEmpty else { continue }
            index += 1
            payload.items[itemIndex].source = label(source, turn: turn, index: index)
        }
        if let data = try? JSONEncoder().encode(payload), let text = String(data: data, encoding: .utf8) {
            result.text = text
        }
    }

    static func used(in text: String, available: [AgentReplySource]) -> [AgentReplySource] {
        var labels = Set<String>()
        return available.filter { !$0.label.isEmpty && text.contains($0.label) && labels.insert($0.label).inserted }
    }

    static func fromToolText(_ text: String) -> [AgentReplySource] {
        (try? JSONDecoder().decode(StudyAgentHostToolResult.self, from: Data(text.utf8)))?
            .items.compactMap(\.source).filter { !$0.label.isEmpty && !$0.excerpt.isEmpty } ?? []
    }
}
