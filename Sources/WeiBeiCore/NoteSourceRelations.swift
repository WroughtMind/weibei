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
