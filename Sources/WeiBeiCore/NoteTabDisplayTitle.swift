import Foundation

/// 笔记浮动 tab 的显示名解析。
///
/// 优先级：用户手动重命名的自定义名 > 正文抬头（第一个非空行，不强制是
/// Markdown 一级标题，普通文字行也算）> 笔记文件名 > 正文前几个字。
/// 用户认知里的"笔记标题"是正文最上面那行字，文件名只是兜底；
/// 自定义名清空（全空白）后恢复自动跟随，保证重命名始终可逆。
public enum NoteTabDisplayTitle {
    /// 正文回退显示名的最大字符数。
    public static let fallbackCharacterLimit = 20

    public static func resolve(customTitle: String?, noteTitle: String, body: String) -> String {
        if let custom = normalized(customTitle) {
            return custom
        }
        if let heading = bodyTitleLine(from: body) {
            return heading
        }
        if let title = normalized(noteTitle) {
            return title
        }
        return bodyExcerpt(from: body)
    }

    /// 正文抬头：第一个能剥出文字的非空行。标准 ATX 标题（`# …`）、
    /// 无空格的 `#开头`、普通文字行都算——用户不一定用 Markdown 语法写标题。
    /// 行首的 `#` 一律剥掉，避免把井号带进名字；剥不出文字的行（纯图片、
    /// 纯 `<br />` 等）跳过继续往下找。结果按 `fallbackCharacterLimit` 截断，
    /// 避免长标题撑爆 tab 和文件名。
    public static func bodyTitleLine(from body: String) -> String? {
        for rawLine in body.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            line = String(line.drop(while: { $0 == "#" }))
                .trimmingCharacters(in: .whitespaces)
            let text = strippedLine(line)
            guard !text.isEmpty else { continue }
            return String(text.prefix(fallbackCharacterLimit))
        }
        return nil
    }

    /// 严格抬头：仅认第一个非空行是 ATX 标题（`# …`，井号+空格）的情况。
    /// 用于驱动文件重命名这类落盘动作——只有用户显式写了标题才动文件名；
    /// 普通首行文字只影响显示（见 `bodyTitleLine`），不改名，避免把
    /// 无标题草稿/首句正文误当标题把文件改飞。
    public static func bodyStrictHeading(from body: String) -> String? {
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let headingMarks = line.prefix { $0 == "#" }.count
            guard headingMarks > 0,
                  line.dropFirst(headingMarks).first?.isWhitespace == true else { return nil }
            let text = strippedLine(line)
            guard !text.isEmpty else { return nil }
            return String(text.prefix(fallbackCharacterLimit))
        }
        return nil
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

    /// 归一化自定义名：全空白视为未设置。侧边栏等不读正文的场景用它
    /// 同步判断"用户是否给过自定义名"，与 `resolve` 的判定口径保持一致。
    public static func normalizedCustomTitle(_ value: String?) -> String? {
        normalized(value)
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
        // 简单 HTML 标签（如 <br />）整体丢弃
        line = line.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
