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
        let materialLine = input.hasMaterial
            ? input.language.text("资料：\(input.materialTitle)", "Material: \(input.materialTitle)")
            : input.language.text("资料：未选择", "Material: none")
        let noteLine = input.language.text("笔记：\(input.noteTitle)", "Note: \(input.noteTitle)")
        let selectionLine: String
        if let selectionText = input.selectionText, !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectionLine = input.language.text(
                "选区：\(input.selectionTitle ?? "已选文本片段")\n\(preview(selectionText, limit: 360))",
                "Selection: \(input.selectionTitle ?? "selected fragments")\n\(preview(selectionText, limit: 360))"
            )
        } else {
            selectionLine = input.language.text("选区：无", "Selection: none")
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
            离线草稿：这次提问已经进入对话。

            问题：\(input.question)

            当前上下文：
            - \(materialLine)
            - \(noteLine)
            - \(selectionLine)

            \(materialBlock)

            \(noteBlock)

            这是一份可写入笔记的本地草稿，只整理当前可见上下文，不补充外部结论。设置密钥后，再发送同类问题会生成正式回答。
            """,
            """
            Offline draft: this question was sent into the chat.

            Question: \(input.question)

            Current context:
            - \(materialLine)
            - \(noteLine)
            - \(selectionLine)

            \(materialBlock)

            \(noteBlock)

            This is a writable local draft that only organizes the visible context and does not add outside claims. After a key is configured, the same kind of question will generate a full answer.
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
}
