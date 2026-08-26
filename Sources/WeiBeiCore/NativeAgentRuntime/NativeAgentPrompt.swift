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
        skillCatalog: String = "",
        contextRevision: String = "",
        confirmedNotes: [StudyAgentPersistedNoteRef] = []
    ) -> String {
        var assembler = NativePromptAssembler()
        assembler.add(NativePromptSection(id: "persona", order: 10, text: bundledText))
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
        assembler.add(NativePromptSection(id: "retrieval", order: 18, text: retrievalStrategy))
        let catalog = tools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        assembler.add(NativePromptSection(id: "tools", order: 20, text: "可用工具：\n\(catalog)"))
        if !skillCatalog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assembler.add(NativePromptSection(id: "skills", order: 15, text: skillCatalog))
        }
        return assembler.assemble()
    }

    public static let retrievalStrategy = """
    检索策略（主动级联，不要用反问打断心流）：
    1. 本轮已经打开、选中或随问题附带的文稿、笔记、选区里有答案 → 直接用。
    2. 没有 → 调用 weibei_course_search，对最相关命中再 weibei_course_read。用户说「搜索利率」或点名课程内容时，以当前课程为准。
    3. 课程没有 → 本轮还没有工作区文件检索工具，跳过这一层。
    4. 都没有 → 可以网页搜索兜底，并写明「课程里没有，我上网查了」。
    闲聊、冷知识、与当前课程无关的问题直接回答，不要先搜课程。
    """
}
