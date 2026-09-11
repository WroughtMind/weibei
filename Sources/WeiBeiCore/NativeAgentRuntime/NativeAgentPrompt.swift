import Foundation

public struct NativePromptSection: Sendable {
    public var id: String
    public var order: Int
    public var text: String

    public init(id: String, order: Int, text: String) {
        self.id = id
        self.order = order
        self.text = text
    }
}

public struct NativePromptAssembler: Sendable {
    public var sections: [NativePromptSection]

    public init(sections: [NativePromptSection] = []) {
        self.sections = sections
    }

    public mutating func add(_ section: NativePromptSection) {
        sections.removeAll { $0.id == section.id }
        sections.append(section)
        sections.sort { $0.order < $1.order }
    }

    public func assemble() -> String {
        sections.map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
    }

    public static func webiSystemPrompt(
        bundledText: String,
        tools: [NativeToolDefinition],
        skillCatalog: String = ""
    ) -> String {
        var assembler = NativePromptAssembler()
        assembler.add(NativePromptSection(id: "persona", order: 10, text: bundledText))
        assembler.add(NativePromptSection(id: "retrieval", order: 18, text: retrievalStrategy))
        let catalog = tools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        assembler.add(NativePromptSection(id: "tools", order: 20, text: "可用工具：\n\(catalog)"))
        if !skillCatalog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assembler.add(NativePromptSection(id: "skills", order: 15, text: skillCatalog))
        }
        return assembler.assemble()
    }

    // 随当轮消息落盘，不能插到固定系统提示或已有历史前面。
    public static func turnContext(
        contextRevision: String = "",
        confirmedNotes: [StudyAgentPersistedNoteRef] = []
    ) -> String {
        var assembler = NativePromptAssembler()
        if !contextRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assembler.add(
                NativePromptSection(
                    id: "revision",
                    order: 16,
                    text: """
                    本轮 contextRevision 是 `\(contextRevision)`。weibei_update_learning_memory、weibei_course_profile_update、weibei_note_proposal、weibei_relation_proposal 必须原样回传这个字符串，不要改成数字，也不要从 memoryRevision 或 profileRevision 推断。
                    """
                )
            )
        }
        if !confirmedNotes.isEmpty {
            let lines = confirmedNotes.map { "- noteItemID `\($0.itemID)` 标题「\($0.title)」" }.joined(separator: "\n")
            assembler.add(
                NativePromptSection(
                    id: "confirmed-notes",
                    order: 17,
                    text: """
                    本会话用户已确认写入、已经落库的笔记如下。可以对它们调用 weibei_relation_proposal；不要再说这些笔记尚未落库，也不要仅凭上一轮工具回执「尚未写回」判断。
                    \(lines)
                    """
                )
            )
        }
        return assembler.assemble()
    }

    public static let retrievalStrategy = """
    先使用本轮已有内容。需要原文且位置已知时直接读取；位置未知时查目录或搜索。
    工具结果不足时可以换词、扩大范围或续读。引用资料时使用返回的 source.label。
    不依赖个人资料的问题可以直接回答。
    """
}
