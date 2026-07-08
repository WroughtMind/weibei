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
        let (frontmatter, body) = splitFrontmatter(markdown)
        var foundTags = frontmatterTags(in: frontmatter)
        var inFence = false
        for rawLine in body.components(separatedBy: .newlines) {
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

    private static func splitFrontmatter(_ markdown: String) -> (frontmatter: [String], body: String) {
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return ([], markdown)
        }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ([], markdown)
        }
        let frontmatter = Array(lines[1..<end])
        lines.removeSubrange(0...end)
        return (frontmatter, lines.joined(separator: "\n"))
    }

    private static func frontmatterTags(in lines: [String]) -> [String] {
        var result: [String] = []
        var readingTagsList = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if readingTagsList {
                if trimmed.hasPrefix("- ") {
                    result.append(contentsOf: tags(fromValue: String(trimmed.dropFirst(2))))
                    continue
                }
                if line.first?.isWhitespace == false {
                    readingTagsList = false
                }
            }
            guard trimmed.lowercased().hasPrefix("tags:") else { continue }
            let value = String(trimmed.dropFirst("tags:".count)).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                readingTagsList = true
            } else {
                result.append(contentsOf: tags(fromValue: value))
            }
        }
        return result
    }

    private static func tags(fromValue rawValue: String) -> [String] {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let pieces = value.contains(",") ? value.split(separator: ",").map(String.init) : [value]
        return pieces.compactMap(normalizedTag)
    }

    private static func normalizedTag(_ rawTag: String) -> String? {
        let tag = rawTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !tag.isEmpty,
              tag.range(of: #"^[\p{L}\p{N}_/-]+$"#, options: .regularExpression) != nil else { return nil }
        return "#\(tag)"
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
