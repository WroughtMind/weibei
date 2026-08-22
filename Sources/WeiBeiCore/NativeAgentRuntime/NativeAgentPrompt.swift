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
        let catalog = tools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        assembler.add(NativePromptSection(id: "tools", order: 20, text: "可用工具：\n\(catalog)"))
        if !skillCatalog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assembler.add(NativePromptSection(id: "skills", order: 15, text: skillCatalog))
        }
        return assembler.assemble()
    }
}
