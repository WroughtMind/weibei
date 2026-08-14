import Foundation

/// 笔记浮动 tab 的显示名解析。
///
/// 优先级：用户手动重命名的自定义名 > 笔记实时 title > 正文前几个字。
/// 自定义名清空（全空白）后恢复自动跟随，保证重命名始终可逆。
public enum NoteTabDisplayTitle {
    /// 正文回退显示名的最大字符数。
    public static let fallbackCharacterLimit = 20

    public static func resolve(customTitle: String?, noteTitle: String, body: String) -> String {
        if let custom = normalized(customTitle) {
            return custom
        }
        if let title = normalized(noteTitle) {
            return title
        }
        return bodyExcerpt(from: body)
    }

    /// 正文回退：去掉空白与 Markdown 标记后取前 `limit` 个字符。
    public static func bodyExcerpt(from body: String, limit: Int = fallbackCharacterLimit) -> String {
        var excerpt = ""
        for rawLine in body.components(separatedBy: .newlines) {
            let line = strippedLine(rawLine)
            guard !line.isEmpty else { continue }
            if !excerpt.isEmpty {
                excerpt.append(" ")
            }
            excerpt.append(line)
            if excerpt.count >= limit {
                break
            }
        }
        return String(excerpt.prefix(limit))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func strippedLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        // 引用块
        while line.hasPrefix(">") {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        // ATX 标题
        let headingMarks = line.prefix { $0 == "#" }.count
        if headingMarks > 0 {
            let after = line.dropFirst(headingMarks)
            if after.first?.isWhitespace == true {
                line = after.trimmingCharacters(in: .whitespaces)
            }
        }
        // 无序 / 有序列表标记
        line = line.replacingOccurrences(
            of: #"^(?:[-*+]|\d+[.)])\s+"#,
            with: "",
            options: .regularExpression
        )
        // 图片整体丢弃；双链 / 链接保留可读文本
        line = line.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[\[([^\]|]*)\|([^\]]*)\]\]"#, with: "$2", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[\[([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // 行内强调 / 代码 / 删除线标记
        line = line.replacingOccurrences(of: #"[*_`~]+"#, with: "", options: .regularExpression)
        return line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
