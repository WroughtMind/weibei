import CoreGraphics
import Foundation

public enum WikiLink {
    public static func targetTitle(from rawTitle: String) -> String {
        let target = splitObsidianFields(rawTitle).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let noteTitle = target
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return noteTitle.isEmpty ? target : noteTitle
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

    public static func enclosingTitle(in text: String, cursor utf16Offset: Int) -> String? {
        let nsText = text as NSString
        let cursor = max(0, min(utf16Offset, nsText.length))
        let start = nsText.range(of: "[[", options: .backwards, range: NSRange(location: 0, length: cursor))
        let end = nsText.range(of: "]]", range: NSRange(location: cursor, length: nsText.length - cursor))
        guard start.location != NSNotFound,
              end.location != NSNotFound,
              start.location + 2 <= end.location else {
            return nil
        }
        let rawTitle = nsText.substring(with: NSRange(location: start.location + 2, length: end.location - start.location - 2))
        let title = targetTitle(from: rawTitle)
        return title.isEmpty ? nil : title
    }
}

public enum SourceReferenceTitle {
    public static func parse(
        _ raw: String
    ) -> (
        title: String,
        pageIndex: Int?,
        sectionTitle: String?,
        sectionLocationID: String?,
        sectionOrdinal: Int?,
        courseItemOrdinal: Int?
    ) {
        var text = raw
            .components(separatedBy: .newlines)
            .reversed()
            .compactMap(sourceFragment)
            .first
            ?? sourceFragment(in: raw)
            ?? cleanedLine(raw)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("来源：") {
            text = String(text.dropFirst("来源：".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.lowercased().hasPrefix("source:") {
            text = String(text.dropFirst("source:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var sectionTitle: String?
        if let markerRange = text.range(of: "，章节：", options: .backwards) {
            let section = text[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            sectionTitle = section.isEmpty ? nil : unwrappedInlineMarkup(String(section))
            text = text[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let markerRange = text.range(of: #",\s*section:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            let section = text[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            sectionTitle = section.isEmpty ? nil : unwrappedInlineMarkup(String(section))
            text = text[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var sectionOrdinal: Int?
        if let range = text.range(
            of: #"(?:，章节序号：\s*\d+|,\s*section\s*(?:ordinal|number):?\s*\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            sectionOrdinal = Int(text[range].filter(\.isNumber))
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var sectionLocationID: String?
        if let range = text.range(
            of: #"(?:，章节标识：\s*[A-Za-z0-9-]+|,\s*section\s*(?:id|identifier):?\s*[A-Za-z0-9-]+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let suffix = String(text[range])
            let separator = suffix.lastIndex(where: { $0 == "：" || $0 == ":" })
            let identifier = (separator.map { String(suffix[suffix.index(after: $0)...]) } ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sectionLocationID = identifier.isEmpty ? nil : identifier
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var pageIndex: Int?
        if let range = text.range(
            of: #"(?:，第\s*\d+\s*页|,\s*page\s*\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let suffix = text[range]
            pageIndex = Int(suffix.filter(\.isNumber)).map { max($0 - 1, 0) }
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var courseItemOrdinal: Int?
        if let range = text.range(
            of: #"(?:，条目：\s*\d+|,\s*(?:item|entry):?\s*\d+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            courseItemOrdinal = Int(text[range].filter(\.isNumber))
            text = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (
            unwrappedInlineMarkup(text),
            pageIndex,
            sectionTitle,
            sectionLocationID,
            sectionOrdinal,
            courseItemOrdinal
        )
    }

    private static func unwrappedInlineMarkup(_ raw: String) -> String {
        var text = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["**", "__", "`", "*"] {
            if text.hasPrefix(marker), text.hasSuffix(marker), text.count > marker.count * 2 {
                text = String(text.dropFirst(marker.count).dropLast(marker.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func sourceFragment(in raw: String) -> String? {
        let line = cleanedLine(raw)
        let chinese = line.range(of: "来源：", options: .backwards)
        let english = line.range(of: "source:", options: [.backwards, .caseInsensitive])
        let markerRange: Range<String.Index>?
        switch (chinese, english) {
        case let (left?, right?): markerRange = left.lowerBound > right.lowerBound ? left : right
        case let (left?, nil): markerRange = left
        case let (nil, right?): markerRange = right
        case (nil, nil): markerRange = nil
        }
        guard let markerRange else { return nil }
        let fragment = String(line[markerRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let markerLength = fragment.hasPrefix("来源：") ? "来源：".count : "source:".count
        let suffix = String(fragment.dropFirst(markerLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : fragment
    }

    private static func cleanedLine(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
