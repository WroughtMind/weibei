import Foundation

public struct CourseKnowledgeSource: Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: String
    public var role: String
    public var text: String
    public var isTruncated: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: String,
        role: String,
        text: String,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.role = role
        self.text = text
        self.isTruncated = isTruncated
    }
}

public enum CourseKnowledgeIndex {
    private struct RankedSource {
        var index: Int
        var source: CourseKnowledgeSource
        var score: Int
    }

    public static func build(
        title: String,
        sources: [CourseKnowledgeSource],
        links: [NoteSourceLink],
        query: String,
        currentMaterialID: String?,
        currentNoteID: String?
    ) -> StudyAgentCourseContext {
        let maximumCatalogItems = 500
        let maximumSearchItems = 80
        let maximumRelations = 500
        let includedSources = Array(sources.prefix(maximumCatalogItems))
        let includedIDs = Set(includedSources.map(\.id))
        let validLinks = links.filter {
            includedIDs.contains($0.noteItemID) && includedIDs.contains($0.sourceItemID)
        }
        let linkedIDsByItem = validLinks.reduce(into: [String: Set<String>]()) { result, link in
            result[link.noteItemID, default: []].insert(link.sourceItemID)
            result[link.sourceItemID, default: []].insert(link.noteItemID)
        }
        let terms = Array(searchTerms(in: query).prefix(32))
        let currentIDs = Set([currentMaterialID, currentNoteID].compactMap { $0 })
        let directlyLinkedIDs = currentIDs.reduce(into: Set<String>()) { result, itemID in
            result.formUnion(linkedIDsByItem[itemID] ?? [])
        }
        var rankedSources: [RankedSource] = []
        rankedSources.reserveCapacity(includedSources.count)
        for (index, source) in includedSources.enumerated() {
            let score = relevanceScore(
                source: source,
                terms: terms,
                isCurrent: currentIDs.contains(source.id),
                isDirectlyLinked: directlyLinkedIDs.contains(source.id)
            )
            rankedSources.append(RankedSource(index: index, source: source, score: score))
        }
        rankedSources.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
        }
        let searchSources = rankedSources.prefix(maximumSearchItems).map { $0.source }

        let catalog = includedSources.map { source in
            StudyAgentCourseCatalogItem(
                id: source.id,
                title: source.title,
                subtitle: source.subtitle,
                kind: source.kind,
                role: source.role,
                isCurrentMaterial: source.id == currentMaterialID,
                isCurrentNote: source.id == currentNoteID,
                linkedItemIDs: (linkedIDsByItem[source.id] ?? []).sorted(),
                tags: source.role == "note" ? MarkdownTagSearch.tags(in: source.text) : []
            )
        }
        let items = searchSources.map { source in
            let excerpt = relevantExcerpt(in: source.text, terms: terms)
            return StudyAgentCourseItem(
                id: source.id,
                title: source.title,
                subtitle: source.subtitle,
                kind: source.kind,
                role: source.role,
                isCurrentMaterial: source.id == currentMaterialID,
                isCurrentNote: source.id == currentNoteID,
                linkedItemIDs: (linkedIDsByItem[source.id] ?? []).sorted(),
                headings: headings(in: source.text),
                tags: source.role == "note" ? MarkdownTagSearch.tags(in: source.text) : [],
                searchText: excerpt.text,
                isTruncated: source.isTruncated || excerpt.isTruncated
            )
        }
        let relations = validLinks.prefix(maximumRelations).map {
            StudyAgentCourseRelation(noteItemID: $0.noteItemID, sourceItemID: $0.sourceItemID)
        }
        return StudyAgentCourseContext(
            title: title,
            catalog: catalog,
            items: items,
            relations: relations,
            isTruncated: sources.count > includedSources.count
                || validLinks.count > relations.count
                || includedSources.contains { $0.isTruncated }
        )
    }

    private static func relevanceScore(
        source: CourseKnowledgeSource,
        terms: [String],
        isCurrent: Bool,
        isDirectlyLinked: Bool
    ) -> Int {
        let titleTerms = Set(searchTerms(in: "\(source.title) \(source.subtitle)"))
        let bodyTerms = Set(searchTerms(in: source.text))
        var score = isCurrent ? 100_000 : 0
        if isDirectlyLinked { score += 50_000 }
        for term in terms {
            if titleTerms.contains(term) { score += 40 }
            if bodyTerms.contains(term) { score += 2 }
        }
        return score
    }

    private static func relevantExcerpt(in text: String, terms: [String]) -> (text: String, isTruncated: Bool) {
        let maximumCharacters = 2_400
        let sections = text
            .components(separatedBy: #"\n\s*\n"#, options: .regularExpression)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sections.isEmpty else { return ("", false) }

        let ranked = sections.enumerated().map { index, section in
            let normalized = section.lowercased()
            let score = terms.reduce(0) { result, term in
                result + normalized.components(separatedBy: term).count - 1
            }
            return (index: index, section: section, score: score)
        }
        let selected: [String]
        if ranked.contains(where: { $0.score > 0 }) {
            selected = ranked
                .filter { $0.score > 0 }
                .sorted { lhs, rhs in
                    lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
                }
                .prefix(4)
                .sorted { $0.index < $1.index }
                .map(\.section)
        } else {
            selected = Array(sections.prefix(3))
        }

        let joined = selected.joined(separator: "\n\n")
        let excerpt = String(joined.prefix(maximumCharacters))
        return (excerpt, text.count > excerpt.count || joined.count > excerpt.count)
    }

    private static func headings(in text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let heading: String?
            if line.hasPrefix("#") {
                heading = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            } else if line.range(of: #"^第\s*\d+\s*页(?:（OCR）)?$"#, options: .regularExpression) != nil {
                heading = line
            } else if line.count <= 80,
                      line.range(of: #"^(?:第.+[章节讲部分]|Chapter\s+\d+|Section\s+\d+)"#, options: [.regularExpression, .caseInsensitive]) != nil {
                heading = line
            } else {
                heading = nil
            }
            if let heading, !heading.isEmpty, !result.contains(heading) {
                result.append(String(heading.prefix(200)))
                if result.count == 12 { break }
            }
        }
        return result
    }

    private static func searchTerms(in query: String) -> [String] {
        let lower = query.lowercased()
        var terms = lower
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted)
            .filter { $0.count >= 2 }

        var current = ""
        var runs: [String] = []
        for scalar in lower.unicodeScalars {
            if (0x4E00...0x9FFF).contains(Int(scalar.value)) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        for run in runs {
            if run.count <= 20 { terms.append(run) }
            let characters = Array(run)
            if characters.count >= 2 {
                for index in 0..<(characters.count - 1) {
                    terms.append(String(characters[index...index + 1]))
                }
            }
        }
        var seen: Set<String> = []
        return terms.filter { term in
            seen.insert(term).inserted
        }
    }
}

private extension String {
    func components(separatedBy pattern: String, options: NSString.CompareOptions) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [self] }
        let range = NSRange(startIndex..<endIndex, in: self)
        var result: [String] = []
        var cursor = range.location
        for match in regex.matches(in: self, range: range) {
            let length = match.range.location - cursor
            if let swiftRange = Range(NSRange(location: cursor, length: length), in: self) {
                result.append(String(self[swiftRange]))
            }
            cursor = match.range.location + match.range.length
        }
        if let swiftRange = Range(NSRange(location: cursor, length: range.location + range.length - cursor), in: self) {
            result.append(String(self[swiftRange]))
        }
        return result
    }
}
