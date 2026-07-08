import Foundation

public enum MarkdownTagSearch {
    public static func matches(query rawQuery: String, in markdown: String) -> Bool {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !query.isEmpty else { return false }
        let lowerQuery = query.lowercased()
        return tags(in: markdown).contains { tag in
            tag.dropFirst().lowercased().contains(lowerQuery)
        }
    }

    public static func tags(in markdown: String) -> [String] {
        var foundTags: [String] = []
        var inFence = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: #"^(`{3,}|~{3,})"#, options: .regularExpression) != nil {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            let line = rawLine.replacingOccurrences(of: #"`[^`\n]*`"#, with: "", options: .regularExpression)
            foundTags.append(contentsOf: tags(inLine: line))
        }
        return Array(Set(foundTags)).sorted()
    }

    private static func tags(inLine line: String) -> [String] {
        let pattern = #"(^|\s)(#[\p{L}\p{N}_/-]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsLine = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            return nsLine.substring(with: match.range(at: 2))
        }
    }
}
