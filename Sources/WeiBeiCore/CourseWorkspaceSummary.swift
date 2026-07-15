import Foundation

/// Course-level counts derived only from persisted workspace facts.
public struct CourseWorkspaceSummary: Equatable, Sendable {
    public let materialCount: Int
    public let noteCount: Int
    public let explicitLinkCount: Int
    public let readingPositionCount: Int
    public let unlinkedMaterialCount: Int
    public let unlinkedNoteCount: Int
    public let studySessionCount: Int
    public let unresolvedConfusionCount: Int

    public init(
        importedItems: [StudyItem],
        noteSourceLinks: [NoteSourceLink],
        studyLocationsByItemID: [String: StudyLocation],
        studySessions: [StudySession],
        learningMemoryEntries: [LearningMemoryEntry]
    ) {
        let courseItems = importedItems.filter { !$0.isSample }
        let materialIDs = Set(courseItems.lazy.filter { !$0.isNotebookNote }.map(\.id))
        let noteIDs = Set(courseItems.lazy.filter(\.isNotebookNote).map(\.id))

        var relations = NoteSourceRelations(links: noteSourceLinks)
        relations.sanitize(
            validNoteItemIDs: noteIDs,
            validSourceItemIDs: materialIDs
        )
        let linkedMaterialIDs = Set(relations.links.lazy.map(\.sourceItemID))
        let linkedNoteIDs = Set(relations.links.lazy.map(\.noteItemID))

        materialCount = materialIDs.count
        noteCount = noteIDs.count
        explicitLinkCount = relations.links.count
        readingPositionCount = materialIDs.lazy.filter { studyLocationsByItemID[$0] != nil }.count
        unlinkedMaterialCount = materialIDs.subtracting(linkedMaterialIDs).count
        unlinkedNoteCount = noteIDs.subtracting(linkedNoteIDs).count
        studySessionCount = studySessions.lazy.filter { !$0.messages.isEmpty }.count
        unresolvedConfusionCount = learningMemoryEntries.lazy.filter {
            $0.kind == .confusion && $0.status == .active
        }.count
    }
}
