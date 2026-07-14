import Foundation

public struct AgentSourceReference: Identifiable, Hashable, Sendable {
    public static let maximumTitleLength = 300
    public var rawValue: String
    public var title: String
    public var pageIndex: Int?
    public var sectionTitle: String?
    public var sectionLocationID: String?
    public var sectionOrdinal: Int?
    public var courseItemOrdinal: Int?

    public init?(rawValue: String) {
        let parsed = SourceReferenceTitle.parse(rawValue)
        guard !parsed.title.isEmpty else { return nil }
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        title = parsed.title
        pageIndex = parsed.pageIndex
        sectionTitle = parsed.sectionTitle
        sectionLocationID = parsed.sectionLocationID
        sectionOrdinal = parsed.sectionOrdinal
        courseItemOrdinal = parsed.courseItemOrdinal
    }

    public var id: String {
        let foldedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let page = pageIndex.map { String($0) } ?? ""
        let section = sectionOrdinal.map { String($0) } ?? ""
        let item = courseItemOrdinal.map { String($0) } ?? ""
        return [foldedTitle, page, sectionLocationID ?? "", section, item, sectionTitle ?? ""]
            .joined(separator: "|")
    }

    fileprivate var hasLocator: Bool {
        pageIndex != nil
            || sectionTitle != nil
            || sectionLocationID != nil
            || sectionOrdinal != nil
            || courseItemOrdinal != nil
    }
}

public struct AgentAnswerPresentation: Equatable, Sendable {
    public var bodyMarkdown: String
    public var sourceReferences: [AgentSourceReference]
    public var interactiveKinds: [String]

    public init(
        bodyMarkdown: String,
        sourceReferences: [AgentSourceReference],
        interactiveKinds: [String] = []
    ) {
        self.bodyMarkdown = bodyMarkdown
        self.sourceReferences = sourceReferences
        self.interactiveKinds = interactiveKinds
    }

    public static func parse(_ markdown: String, fallbackSource: String?) -> AgentAnswerPresentation {
        let lines = markdown.components(separatedBy: .newlines)
        var bodyLines = lines
        var extractedLine = Array(repeating: false, count: lines.count)
        var references: [AgentSourceReference] = []
        var interactiveKinds: [String] = []
        var isInsideFence = false
        var activeFence: Character?
        var activeFenceLanguage: String?
        var interactiveJSONLines: [String] = []

        for (index, line) in lines.enumerated() {
            if let fence = fenceMarker(in: line) {
                if isInsideFence, activeFence == fence {
                    if activeFenceLanguage == "weibei-interactive" {
                        let metadata = interactiveMetadata(in: interactiveJSONLines)
                        references.append(contentsOf: metadata.references)
                        if let kind = metadata.kind, !interactiveKinds.contains(kind) {
                            interactiveKinds.append(kind)
                        }
                    }
                    isInsideFence = false
                    activeFence = nil
                    activeFenceLanguage = nil
                    interactiveJSONLines.removeAll(keepingCapacity: true)
                } else if !isInsideFence {
                    isInsideFence = true
                    activeFence = fence
                    activeFenceLanguage = fenceLanguage(in: line)
                }
                continue
            }
            if isInsideFence {
                if activeFenceLanguage == "weibei-interactive",
                   interactiveJSONLines.reduce(0, { $0 + $1.utf8.count }) < 16_384 {
                    interactiveJSONLines.append(line)
                }
                continue
            }
            if let rawReference = dedicatedReference(in: line),
               let reference = AgentSourceReference(rawValue: rawReference) {
                references.append(reference)
                bodyLines[index] = ""
                extractedLine[index] = true
            } else {
                references.append(contentsOf: inlineEvidenceReferences(in: line))
            }
        }

        removeEmptySourceHeadings(from: &bodyLines, extractedLine: extractedLine)

        if let fallbackSource = fallbackSource?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallbackSource.isEmpty {
            let raw = fallbackSource.hasPrefix("来源：")
                || fallbackSource.lowercased().hasPrefix("source:")
                ? fallbackSource
                : "来源：\(fallbackSource)"
            if let fallback = AgentSourceReference(rawValue: raw),
               !references.contains(where: {
                   sameTitle($0, fallback) && (!$0.hasLocator || !fallback.hasLocator)
               }) {
                references.append(fallback)
            }
        }

        return AgentAnswerPresentation(
            bodyMarkdown: normalizedBody(bodyLines),
            sourceReferences: deduplicated(references),
            interactiveKinds: interactiveKinds
        )
    }

    private static func dedicatedReference(in rawLine: String) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }

        while line.hasPrefix(">") {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        line = line.replacingOccurrences(
            of: #"^(?:[-*+]\s+|\d+[.)]\s+)"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        for marker in ["**", "__", "`", "*"] {
            if line.hasPrefix(marker), line.hasSuffix(marker), line.count > marker.count * 2 {
                line = String(line.dropFirst(marker.count).dropLast(marker.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if line.hasPrefix("来源：") {
            let suffix = line.dropFirst("来源：".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : line
        }
        if line.lowercased().hasPrefix("source:") {
            let suffix = line.dropFirst("source:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : line
        }
        return nil
    }

    private static func inlineEvidenceReferences(in line: String) -> [AgentSourceReference] {
        let pattern = #"\[(?:材料|笔记|选区|material|note|selection)\s*[:：]\s*([^\]\n]{1,\#(AgentSourceReference.maximumTitleLength)})\]"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return expression.matches(in: line, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let titleRange = Range(match.range(at: 1), in: line) else { return nil }
            let title = line[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return AgentSourceReference(rawValue: "来源：\(title)")
        }
    }

    private static func fenceMarker(in line: String) -> Character? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func fenceLanguage(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let suffix: Substring
        if trimmed.hasPrefix("```") {
            suffix = trimmed.dropFirst(3)
        } else if trimmed.hasPrefix("~~~") {
            suffix = trimmed.dropFirst(3)
        } else {
            return nil
        }
        return suffix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map { String($0).lowercased() }
    }

    private static let supportedInteractiveKinds: Set<String> = [
        "quiz", "reveal", "chart", "function-plot", "parameter-lab", "text-study", "design-compare", "palette",
        "study-board", "relationship-map", "timeline", "comparison-matrix", "annotated-passage", "derivation-steps",
        "flashcards", "sequence-builder", "scenario-lab", "evidence-board", "spectrum", "decision-path", "unit-workbench",
        "reaction-balance", "algorithm-trace", "language-aligner", "argument-map", "visual-analysis", "spatial-layers",
        "pathway-lab"
    ]

    private static func interactiveMetadata(
        in lines: [String]
    ) -> (kind: String?, references: [AgentSourceReference]) {
        let json = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !json.isEmpty,
              json.utf8.count <= 16_384,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return (nil, [])
        }

        let protocolVersion = root["version"] as? Int
        let kind = (protocolVersion == nil || protocolVersion == 1)
            ? (root["kind"] as? String).flatMap { supportedInteractiveKinds.contains($0) ? $0 : nil }
            : nil
        var rawReferences: [String] = []
        appendInteractiveSourceValues(from: root, depth: 0, to: &rawReferences)

        let references: [AgentSourceReference] = rawReferences.prefix(24).compactMap { rawReference -> AgentSourceReference? in
            let trimmed = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let lowercased = trimmed.lowercased()
            if trimmed.hasPrefix("来源：") || lowercased.hasPrefix("source:") {
                return AgentSourceReference(rawValue: trimmed)
            }
            for prefix in ["材料：", "笔记：", "选区：", "material:", "note:", "selection:"] {
                if lowercased.hasPrefix(prefix.lowercased()) {
                    let title = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    return title.isEmpty ? nil : AgentSourceReference(rawValue: "来源：\(title)")
                }
            }
            return AgentSourceReference(rawValue: "来源：\(trimmed)")
        }
        return (kind, references)
    }

    private static func appendSourceValues(from object: [String: Any], to result: inout [String]) {
        if let source = object["source"] as? String {
            result.append(source)
        }
        if let sources = object["sources"] as? [String] {
            result.append(contentsOf: sources.prefix(8))
        }
    }

    private static func appendInteractiveSourceValues(
        from object: [String: Any],
        depth: Int,
        to result: inout [String]
    ) {
        appendSourceValues(from: object, to: &result)
        guard depth < 3, result.count < 24 else { return }

        let containerKeys = [
            "items", "nodes", "events", "metrics", "rows", "columns", "series", "points", "lanes",
            "annotations", "steps", "cards", "controls", "outcomes", "choices", "options", "edges", "swatches",
            "variables", "checks", "species", "codeLines", "pairs", "zones", "lenses", "layers", "features", "states"
        ]
        for key in containerKeys {
            if let children = object[key] as? [[String: Any]] {
                for child in children.prefix(12) where result.count < 24 {
                    appendInteractiveSourceValues(from: child, depth: depth + 1, to: &result)
                }
            } else if let child = object[key] as? [String: Any] {
                appendInteractiveSourceValues(from: child, depth: depth + 1, to: &result)
            }
        }
    }

    private static func removeEmptySourceHeadings(from lines: inout [String], extractedLine: [Bool]) {
        for index in lines.indices where isSourceHeading(lines[index]) {
            var cursor = index + 1
            var foundReference = false
            var foundBody = false
            while cursor < lines.count {
                let trimmed = lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("#") { break }
                if extractedLine[cursor] {
                    foundReference = true
                } else if !trimmed.isEmpty {
                    foundBody = true
                    break
                }
                cursor += 1
            }
            if foundReference && !foundBody {
                lines[index] = ""
            }
        }
    }

    private static func isSourceHeading(_ line: String) -> Bool {
        let heading = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :："))
            .lowercased()
        return ["来源", "相关资料", "参考资料", "sources", "source", "references"].contains(heading)
    }

    private static func normalizedBody(_ lines: [String]) -> String {
        var result: [String] = []
        var blankCount = 0
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blankCount += 1
                if blankCount <= 2 { result.append("") }
            } else {
                blankCount = 0
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduplicated(_ references: [AgentSourceReference]) -> [AgentSourceReference] {
        var result: [AgentSourceReference] = []
        for reference in references {
            if result.contains(where: { $0.id == reference.id }) { continue }
            if let index = result.firstIndex(where: {
                sameTitle($0, reference)
                    && $0.courseItemOrdinal == reference.courseItemOrdinal
                    && (!$0.hasLocator || !reference.hasLocator)
            }) {
                if reference.hasLocator && !result[index].hasLocator {
                    result[index] = reference
                }
                continue
            }
            result.append(reference)
        }
        return result
    }

    private static func sameTitle(_ lhs: AgentSourceReference, _ rhs: AgentSourceReference) -> Bool {
        lhs.title.compare(rhs.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
