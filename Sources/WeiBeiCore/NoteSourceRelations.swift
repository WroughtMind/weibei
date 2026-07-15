import Foundation

/// Durable many-to-many links between independent notes and source documents.
///
/// The current document and current note remain session state. This value only
/// manages relationships the user explicitly chose to keep with a note.
public struct NoteSourceRelations: Sendable {
    public private(set) var links: [NoteSourceLink]

    public init(links: [NoteSourceLink]) {
        self.links = Self.deduplicated(links)
    }

    public func sourceIDs(for noteItemID: String) -> [String] {
        links
            .filter { $0.noteItemID == noteItemID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.sourceItemID < rhs.sourceItemID
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map(\.sourceItemID)
    }

    public func noteIDs(for sourceItemID: String) -> [String] {
        links
            .filter { $0.sourceItemID == sourceItemID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.noteItemID < rhs.noteItemID
                }
                return lhs.createdAt < rhs.createdAt
            }
            .map(\.noteItemID)
    }

    public func isLinked(noteItemID: String, sourceItemID: String) -> Bool {
        links.contains {
            $0.noteItemID == noteItemID && $0.sourceItemID == sourceItemID
        }
    }

    public mutating func replaceSources(for noteItemID: String, sourceItemIDs: Set<String>) {
        let retained = links.filter {
            $0.noteItemID != noteItemID || sourceItemIDs.contains($0.sourceItemID)
        }
        let existingIDs = Set(retained.lazy.filter { $0.noteItemID == noteItemID }.map(\.sourceItemID))
        let additions = sourceItemIDs
            .subtracting(existingIDs)
            .sorted()
            .map { NoteSourceLink(noteItemID: noteItemID, sourceItemID: $0) }
        links = Self.deduplicated(retained + additions)
    }

    public mutating func replaceNotes(for sourceItemID: String, noteItemIDs: Set<String>) {
        let retained = links.filter {
            $0.sourceItemID != sourceItemID || noteItemIDs.contains($0.noteItemID)
        }
        let existingIDs = Set(retained.lazy.filter { $0.sourceItemID == sourceItemID }.map(\.noteItemID))
        let additions = noteItemIDs
            .subtracting(existingIDs)
            .sorted()
            .map { NoteSourceLink(noteItemID: $0, sourceItemID: sourceItemID) }
        links = Self.deduplicated(retained + additions)
    }

    public mutating func removeLinks(involving itemID: String) {
        links.removeAll {
            $0.noteItemID == itemID || $0.sourceItemID == itemID
        }
    }

    public mutating func sanitize(validNoteItemIDs: Set<String>, validSourceItemIDs: Set<String>) {
        links = Self.deduplicated(links.filter {
            validNoteItemIDs.contains($0.noteItemID)
                && validSourceItemIDs.contains($0.sourceItemID)
                && $0.noteItemID != $0.sourceItemID
        })
    }

    private static func deduplicated(_ links: [NoteSourceLink]) -> [NoteSourceLink] {
        var seen = Set<String>()
        return links
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
            .filter { link in
                seen.insert("\(link.noteItemID)\u{1F}\(link.sourceItemID)").inserted
            }
    }
}

/// Read-optimized snapshot for rendering the many-to-many relationship graph.
/// Build it when the durable links change, then reuse its constant-time lookups.
public struct NoteSourceRelationIndex: Sendable {
    private let sourceIDsByNoteID: [String: [String]]
    private let noteIDsBySourceID: [String: [String]]

    public init(links: [NoteSourceLink]) {
        let normalizedLinks = NoteSourceRelations(links: links).links
        var sources: [String: [String]] = [:]
        var notes: [String: [String]] = [:]
        for link in normalizedLinks {
            sources[link.noteItemID, default: []].append(link.sourceItemID)
            notes[link.sourceItemID, default: []].append(link.noteItemID)
        }
        sourceIDsByNoteID = sources
        noteIDsBySourceID = notes
    }

    public func sourceIDs(for noteItemID: String) -> [String] {
        sourceIDsByNoteID[noteItemID] ?? []
    }

    public func noteIDs(for sourceItemID: String) -> [String] {
        noteIDsBySourceID[sourceItemID] ?? []
    }

    public func sourceCount(for noteItemID: String) -> Int {
        sourceIDsByNoteID[noteItemID]?.count ?? 0
    }

    public func noteCount(for sourceItemID: String) -> Int {
        noteIDsBySourceID[sourceItemID]?.count ?? 0
    }
}
