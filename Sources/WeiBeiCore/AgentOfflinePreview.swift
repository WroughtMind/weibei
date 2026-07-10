import Foundation

public struct AgentOfflinePreviewInput: Equatable {
    public var language: WeiBeiInterfaceLanguage
    public var question: String
    public var hasMaterial: Bool
    public var materialTitle: String
    public var materialText: String
    public var noteTitle: String
    public var noteText: String
    public var selectionTitle: String?
    public var selectionText: String?
    public var linkedSources: [StudyAgentSource]

    public init(
        language: WeiBeiInterfaceLanguage,
        question: String,
        hasMaterial: Bool,
        materialTitle: String,
        materialText: String,
        noteTitle: String,
        noteText: String,
        selectionTitle: String?,
        selectionText: String?,
        linkedSources: [StudyAgentSource] = []
    ) {
        self.language = language
        self.question = question
        self.hasMaterial = hasMaterial
        self.materialTitle = materialTitle
        self.materialText = materialText
        self.noteTitle = noteTitle
        self.noteText = noteText
        self.selectionTitle = selectionTitle
        self.selectionText = selectionText
        self.linkedSources = linkedSources
    }
}

public enum AgentOfflinePreview {
    public static func suggestedNoteBlock(from answer: String, language: WeiBeiInterfaceLanguage) -> String? {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        for heading in ["## 建议写入", "## Suggested Note"] {
            guard let headingRange = text.range(of: heading) else { continue }
            let remainder = text[headingRange.upperBound...]
            let nextHeading = remainder.range(of: "\n## ")?.lowerBound ?? remainder.endIndex
            let body = remainder[..<nextHeading].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            return language.text("## 整理建议\n\(body)", "## Organization suggestion\n\(body)")
        }
        return nil
    }

    public static func render(_ input: AgentOfflinePreviewInput) -> String {
        let materialValue = input.hasMaterial
            ? input.materialTitle
            : input.language.text("未选择", "None")
        let noteValue = input.noteTitle
        let selectionValue: String
        let selectionPreview: String
        if let selectionText = input.selectionText, !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectionPreview = preview(selectionText, limit: 220)
            selectionValue = input.language.text(
                input.selectionTitle ?? "已选文本片段",
                input.selectionTitle ?? "selected fragments"
            )
        } else {
            selectionPreview = ""
            selectionValue = input.language.text("无", "None")
        }

        let materialPreview = preview(input.materialText, limit: 180)
        let notePreview = preview(input.noteText, limit: 90)
        let linkedSourceValue = input.linkedSources.isEmpty
            ? input.language.text("无", "None")
            : input.linkedSources.map(\.title).joined(separator: "、")
        let evidence = evidenceLines(
            input: input,
            materialPreview: materialPreview,
            notePreview: notePreview,
            selectionPreview: selectionPreview,
            materialValue: materialValue
        )

        return input.language.text(
            """
            ## 离线草稿

            未配置密钥；这里只整理当前可见内容，不补充外部结论。

            **问题**：\(input.question)

            **上下文**：当前资料：\(inline(materialValue)) · 关联资料：\(inline(linkedSourceValue)) · 笔记：\(inline(noteValue)) · 选区：\(inline(selectionValue))

            ## 可确认
            \(evidence)

            ## 建议写入
            - 把可确认依据写入笔记，并保留来源。
            - 设置密钥后再生成解释、例题或复习卡片。
            """,
            """
            ## Offline Draft

            No key is configured; this only organizes visible context and does not add outside claims.

            **Question**: \(input.question)

            **Context**: Current material: \(inline(materialValue)) · Linked sources: \(inline(linkedSourceValue)) · Note: \(inline(noteValue)) · Selection: \(inline(selectionValue))

            ## Confirmed
            \(evidence)

            ## Suggested Note
            - Write the confirmed evidence into the note and keep the source attached.
            - Configure a key before asking for a full explanation, practice question, or review card.
            """
        )
    }

    public static func preview(_ text: String, limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)) + "..."
    }

    private static func evidenceLines(
        input: AgentOfflinePreviewInput,
        materialPreview: String,
        notePreview: String,
        selectionPreview: String,
        materialValue: String
    ) -> String {
        var lines: [String] = []
        if !selectionPreview.isEmpty {
            lines.append(input.language.text("- 选区依据：\(selectionPreview)", "- Selection evidence: \(selectionPreview)"))
        }
        if !materialPreview.isEmpty {
            lines.append(input.language.text("- 资料依据：\(materialPreview)", "- Material evidence: \(materialPreview)"))
        } else if input.hasMaterial {
            lines.append(input.language.text("- 资料依据：\(materialValue) 暂无可读文本。", "- Material evidence: \(materialValue) has no readable text yet."))
        }
        for source in input.linkedSources {
            let sourcePreview = preview(source.text, limit: 140)
            guard !sourcePreview.isEmpty else { continue }
            lines.append(input.language.text(
                "- 关联资料依据（\(source.title)）：\(sourcePreview)",
                "- Linked source evidence (\(source.title)): \(sourcePreview)"
            ))
        }
        if notePreview.isEmpty {
            lines.append(input.language.text("- 笔记状态：当前笔记为空。", "- Note state: the current note is empty."))
        } else {
            lines.append(input.language.text("- 笔记线索：\(notePreview)", "- Note clue: \(notePreview)"))
        }
        return lines.joined(separator: "\n")
    }

    private static func inline(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
