import Foundation

/// 本轮最小定位：正在看哪份、哪一页。只附加在发给模型的当前用户消息上，不写入账本。
public enum NativeTurnLocation {
    public static func block(for request: StudyAgentRequest) -> String? {
        var lines: [String] = []
        if let focus = request.focus {
            if let title = trimmed(focus.materialTitle) {
                lines.append(request.language.text("材料：\(title)", "Material: \(title)"))
            } else if let id = trimmed(focus.materialItemID) {
                lines.append(request.language.text("材料 ID：\(id)", "Material ID: \(id)"))
            }
            if let page = focus.pageIndex {
                let facing = displayPage(page)
                lines.append(request.language.text("页码：\(facing)", "Page: \(facing)"))
            }
            if let section = trimmed(focus.sectionTitle) {
                lines.append(request.language.text("章节：\(section)", "Section: \(section)"))
            }
        }
        if let note = request.courseContext.items.first(where: \.isCurrentNote) {
            lines.append(request.language.text("笔记：\(note.title)", "Note: \(note.title)"))
        }
        for asset in request.visualAssets {
            lines.append(
                request.language.text(
                    "可观察图像 assetID：\(asset.id)",
                    "Visible image assetID: \(asset.id)"
                )
            )
        }
        guard !lines.isEmpty else { return nil }
        let header = request.language.text(
            "本轮阅读位置（只给定位，不是正文；需要正文时再读取）：",
            "Current reading location (position only, not the body; read when needed):"
        )
        return ([header] + lines).joined(separator: "\n")
    }

    public static func applying(to messages: inout [NativeModelMessage], request: StudyAgentRequest) {
        guard let block = block(for: request),
              let index = messages.lastIndex(where: { $0.role == .user }) else { return }
        let existing = messages[index].content
        if existing.contains(block) { return }
        messages[index].content = existing.isEmpty ? block : existing + "\n\n" + block
    }

    /// `StudyAgentFocus.pageIndex` is 0-based; the model sees the facing page.
    public static func displayPage(_ pageIndex: Int) -> Int {
        pageIndex + 1
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
