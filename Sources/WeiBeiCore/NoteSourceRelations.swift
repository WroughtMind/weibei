import Foundation

public enum NoteSourceLinkOrigin: String, Codable, Hashable, Sendable {
    case manual
    case noteCreation
    case excerpt
    case folderBatch
}

public struct NoteSourceLink: Identifiable, Codable, Hashable, Sendable {
    public var noteID: String
    public var sourceID: String
    public var origin: NoteSourceLinkOrigin
    public var createdAt: Date

    public var id: String { "\(noteID)\u{1F}\(sourceID)" }

    public init(
        noteID: String,
        sourceID: String,
        origin: NoteSourceLinkOrigin = .manual,
        createdAt: Date = Date()
    ) {
        self.noteID = noteID
        self.sourceID = sourceID
        self.origin = origin
        self.createdAt = createdAt
    }
}

public struct NoteSourceRelations: Equatable, Sendable {
    public private(set) var links: [NoteSourceLink]

    public init(links: [NoteSourceLink] = []) {
        var seen = Set<String>()
        self.links = links.filter { seen.insert($0.id).inserted }
    }

    public func sourceIDs(for noteID: String) -> [String] {
        links.filter { $0.noteID == noteID }.map(\.sourceID)
    }

    public func isLinked(noteID: String, sourceID: String) -> Bool {
        links.contains { $0.noteID == noteID && $0.sourceID == sourceID }
    }

    @discardableResult
    public mutating func link(
        noteID: String,
        sourceID: String,
        origin: NoteSourceLinkOrigin = .manual,
        createdAt: Date = Date()
    ) -> Bool {
        guard noteID != sourceID, !isLinked(noteID: noteID, sourceID: sourceID) else { return false }
        links.append(NoteSourceLink(noteID: noteID, sourceID: sourceID, origin: origin, createdAt: createdAt))
        return true
    }

    @discardableResult
    public mutating func unlink(noteID: String, sourceID: String) -> Bool {
        let previousCount = links.count
        links.removeAll { $0.noteID == noteID && $0.sourceID == sourceID }
        return links.count != previousCount
    }

    public mutating func replaceSources(
        for noteID: String,
        sourceIDs: some Sequence<String>,
        origin: NoteSourceLinkOrigin = .manual,
        createdAt: Date = Date()
    ) {
        let uniqueSourceIDs = Array(Set(sourceIDs.filter { $0 != noteID })).sorted()
        let existingBySourceID = Dictionary(
            uniqueKeysWithValues: links
                .filter { $0.noteID == noteID }
                .map { ($0.sourceID, $0) }
        )
        links.removeAll { $0.noteID == noteID }
        links.append(contentsOf: uniqueSourceIDs.map { sourceID in
            existingBySourceID[sourceID]
                ?? NoteSourceLink(noteID: noteID, sourceID: sourceID, origin: origin, createdAt: createdAt)
        })
    }

    public mutating func removeLinks(withMissingItemIDs availableItemIDs: Set<String>) {
        links.removeAll { !availableItemIDs.contains($0.noteID) || !availableItemIDs.contains($0.sourceID) }
    }
}

public struct WorkspaceOpenSelection: Equatable, Sendable {
    public private(set) var materialID: String?
    public private(set) var noteID: String?

    public init(materialID: String? = nil, noteID: String? = nil) {
        self.materialID = materialID
        self.noteID = noteID
    }

    public mutating func openMaterial(_ itemID: String?) {
        materialID = itemID
    }

    public mutating func activateNote(_ itemID: String?) {
        noteID = itemID
    }
}

public enum StudyMaterialDiscovery {
    public static let supportedFileExtensions: Set<String> = [
        "pdf", "html", "htm", "md", "markdown", "txt", "text"
    ]

    public static func urls(from selections: [URL], fileManager: FileManager = .default) -> [URL] {
        var discoveredByPath: [String: URL] = [:]
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .isPackageKey,
            .isSymbolicLinkKey
        ]

        func include(_ url: URL) {
            let normalized = url.standardizedFileURL
            guard supportedFileExtensions.contains(normalized.pathExtension.lowercased()) else { return }
            discoveredByPath[normalized.path] = normalized
        }

        for selection in selections {
            let normalized = selection.standardizedFileURL
            let values = try? normalized.resourceValues(forKeys: resourceKeys)
            if values?.isDirectory != true {
                if values?.isHidden != true, values?.isSymbolicLink != true {
                    include(normalized)
                }
                continue
            }

            guard values?.isPackage != true, values?.isSymbolicLink != true,
                  let enumerator = fileManager.enumerator(
                    at: normalized,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else { continue }

            for case let url as URL in enumerator {
                let childValues = try? url.resourceValues(forKeys: resourceKeys)
                if childValues?.isSymbolicLink == true {
                    if childValues?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                if childValues?.isPackage == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard childValues?.isRegularFile == true, childValues?.isHidden != true else { continue }
                include(url)
            }
        }

        return discoveredByPath.values.sorted { $0.path < $1.path }
    }
}

public struct StudyAgentSource: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var kind: StudyItemKind
    public var text: String

    public init(id: String, title: String, kind: StudyItemKind, text: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.text = text
    }
}

public enum StudyAgentSourceContextBuilder {
    public static func scopedSources(
        _ availableSources: [StudyAgentSource],
        selectedIDs: some Sequence<String>,
        totalCharacterLimit: Int = 12_000,
        perSourceLimit: Int = 6_000
    ) -> [StudyAgentSource] {
        let selectedIDSet = Set(selectedIDs)
        guard !selectedIDSet.isEmpty, totalCharacterLimit > 0, perSourceLimit > 0 else { return [] }

        var seen = Set<String>()
        let selectedSources = availableSources.filter { source in
            selectedIDSet.contains(source.id) && seen.insert(source.id).inserted
        }
        var remainingBudget = totalCharacterLimit
        var result: [StudyAgentSource] = []

        for (index, source) in selectedSources.enumerated() where remainingBudget > 0 {
            let remainingSourceCount = selectedSources.count - index
            let fairShare = max(1, remainingBudget / max(remainingSourceCount, 1))
            let sourceBudget = min(perSourceLimit, fairShare, remainingBudget)
            let trimmedText = String(source.text.prefix(sourceBudget))
            guard !trimmedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result.append(StudyAgentSource(id: source.id, title: source.title, kind: source.kind, text: trimmedText))
            remainingBudget -= trimmedText.count
        }

        return result
    }
}
