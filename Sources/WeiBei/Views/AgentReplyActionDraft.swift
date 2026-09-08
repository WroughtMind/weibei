import SwiftUI
import WeiBeiCore

final class AgentReplyActionDraft: ObservableObject {
    let headingPrefix: String
    @Published var title: String
    @Published var bodyText: String
    @Published var isWorking = false

    init(action: AgentReplyAction) {
        let draft = Self.noteDraft(from: action.proposedMarkdown ?? "")
        headingPrefix = draft.headingPrefix
        title = draft.title
        bodyText = draft.body
    }

    private static func noteDraft(
        from markdown: String
    ) -> (headingPrefix: String, title: String, body: String) {
        var lines = markdown.components(separatedBy: .newlines)
        if let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }) {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            let prefix = String(line.prefix(while: { $0 == "#" }))
            let title = line.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                lines.remove(at: index)
                return (
                    prefix.isEmpty ? "##" : prefix,
                    title,
                    lines.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return (
            "##",
            "整理建议",
            markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
