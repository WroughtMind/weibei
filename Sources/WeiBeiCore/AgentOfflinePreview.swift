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

    public init(
        language: WeiBeiInterfaceLanguage,
        question: String,
        hasMaterial: Bool,
        materialTitle: String,
        materialText: String,
        noteTitle: String,
        noteText: String,
        selectionTitle: String?,
        selectionText: String?
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
    }
}

public enum AgentOfflinePreview {
    public static func render(_ input: AgentOfflinePreviewInput) -> String {
        let materialValue = input.hasMaterial
            ? input.materialTitle
            : input.language.text("未选择", "None")
        let noteValue = input.noteTitle
        let selectionValue: String
        if let selectionText = input.selectionText, !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectionValue = input.language.text(
                "\(input.selectionTitle ?? "已选文本片段")：\(preview(selectionText, limit: 360))",
                "\(input.selectionTitle ?? "selected fragments"): \(preview(selectionText, limit: 360))"
            )
        } else {
            selectionValue = input.language.text("无", "None")
        }

        let materialPreview = preview(input.materialText, limit: 260)
        let notePreview = preview(input.noteText, limit: 260)
        let materialBlock = materialPreview.isEmpty
            ? input.language.text("资料摘要：暂无可读文本。", "Material excerpt: no readable text yet.")
            : input.language.text("资料摘录：\(materialPreview)", "Material excerpt: \(materialPreview)")
        let noteBlock = notePreview.isEmpty
            ? input.language.text("笔记摘要：当前笔记为空。", "Note excerpt: the current note is empty.")
            : input.language.text("笔记摘录：\(notePreview)", "Note excerpt: \(notePreview)")

        return input.language.text(
            """
            ## 离线草稿

            这次提问已经进入对话；未配置密钥时，魏碑只整理当前可见上下文，不补充外部结论。

            **问题**：\(input.question)

            | 上下文 | 内容 |
            | --- | --- |
            | 资料 | \(tableCell(materialValue)) |
            | 笔记 | \(tableCell(noteValue)) |
            | 选区 | \(tableCell(selectionValue)) |

            > \(materialBlock)

            > \(noteBlock)

            ## 整理建议
            - 先把选区作为可追溯摘录写入笔记。
            - 再用资料标题和笔记标题补齐来源位置。
            - 设置密钥后，可以继续要求魏碑生成正式解释、例题或复习卡片。
            """,
            """
            ## Offline Draft

            This question was sent into the chat. Without a configured key, WeiBei only organizes the visible context and does not add outside claims.

            **Question**: \(input.question)

            | Context | Content |
            | --- | --- |
            | Material | \(tableCell(materialValue)) |
            | Note | \(tableCell(noteValue)) |
            | Selection | \(tableCell(selectionValue)) |

            > \(materialBlock)

            > \(noteBlock)

            ## Organization Suggestions
            - Save the selected text as a traceable excerpt first.
            - Keep the material title and note title attached to the answer.
            - After a key is configured, ask WeiBei for a full explanation, practice question, or review card.
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

    private static func tableCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
