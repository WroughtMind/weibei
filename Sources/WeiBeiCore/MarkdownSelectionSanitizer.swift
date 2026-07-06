import Foundation

public enum MarkdownSelectionSanitizer {
    public static func clean(_ text: String) -> String {
        normalizedReadableMarkdown(text)
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .joined(separator: "\n")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanLine(_ rawLine: String) -> String {
        rawLine
            .replacingOccurrences(
            of: #"^\s*(?:>\s*)*(?:\\)?\[![A-Za-z][A-Za-z0-9_-]*\][+-]?\s*"#,
            with: "",
            options: .regularExpression
        )
            .replacingOccurrences(
                of: #"^\s*>\s?"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^\s*[-*+]\s+\[[ xX]\]\s*"#,
                with: "",
                options: .regularExpression
            )
    }

    private static func normalizedReadableMarkdown(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"%%[\s\S]*?%%\n?"#, with: "", options: [.regularExpression])
        text = replacingMatches(in: text, pattern: #"!\[\[([^\]\n]+)\]\]"#) { groups in
            displayForEmbed(groups[safe: 1] ?? "")
        }
        text = replacingMatches(in: text, pattern: #"\[\[([^\]\n]+)\]\]"#) { groups in
            displayForWikiLink(groups[safe: 1] ?? "")
        }
        text = replacingMatches(in: text, pattern: #"!\[([^\]\n]*)\]\([^\)\n]+\)"#) { groups in
            readableImageAlt(groups[safe: 1] ?? "")
        }
        text = replacingMatches(in: text, pattern: #"\[([^\]\n]+)\]\([^\)\n]+\)"#) { groups in
            groups[safe: 1] ?? ""
        }
        text = replacingMatches(in: text, pattern: #"==([^=\n]+)=="#) { groups in
            groups[safe: 1] ?? ""
        }
        text = replacingMatches(in: text, pattern: #"~~([^~\n]+)~~"#) { groups in
            groups[safe: 1] ?? ""
        }
        text = replacingMatches(in: text, pattern: #"`([^`\n]+)`"#) { groups in
            groups[safe: 1] ?? ""
        }
        text = replacingMatches(in: text, pattern: #"\^\[([^\]\n]+)\]"#) { groups in
            groups[safe: 1] ?? ""
        }
        return text
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return "" }
                return nsText.substring(with: range)
            }
            result += transform(groups)
            cursor = match.range.location + match.range.length
        }
        if cursor < nsText.length {
            result += nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
        }
        return result
    }

    private static func displayForWikiLink(_ raw: String) -> String {
        let fields = splitObsidianFields(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let first = fields.first else { return "" }
        if fields.count > 1 {
            let alias = fields.dropFirst().joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
            if !alias.isEmpty { return alias }
        }
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayForEmbed(_ raw: String) -> String {
        var fields = splitObsidianFields(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !fields.isEmpty else { return "" }
        let target = fields.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = fields.last, isImageSize(last) {
            fields.removeLast()
        }
        let label = fields.joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? target : label
    }

    private static func readableImageAlt(_ raw: String) -> String {
        var fields = splitObsidianFields(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if let last = fields.last, isImageSize(last) {
            fields.removeLast()
        }
        return fields.joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isImageSize(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.range(of: #"^\d{1,4}(?:x\d{1,4})?$"#, options: .regularExpression) != nil
    }

    private static func splitObsidianFields(_ raw: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            let nextIndex = raw.index(after: index)
            if character == "\\",
               nextIndex < raw.endIndex,
               raw[nextIndex] == "|" {
                fields.append(current)
                current = ""
                index = raw.index(after: nextIndex)
                continue
            }
            if character == "|" {
                fields.append(current)
                current = ""
                index = nextIndex
                continue
            }
            current.append(character)
            index = nextIndex
        }
        fields.append(current)
        return fields
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
