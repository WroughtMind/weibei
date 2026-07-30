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

/// The two persisted learning signals shown on one course home.
///
/// `learningMemoryEntries` must already belong to `courseID`; sessions are
/// filtered again here so a stale source Chat can never become a course action.
public struct CourseHomeLearningHighlights: Equatable, Sendable {
    public let summary: LearningMemoryEntry?
    public let nextStepText: String?
    public let nextStepSessionID: UUID?

    public init(
        courseID: UUID,
        learningMemoryEntries: [LearningMemoryEntry],
        studySessions: [StudySession]
    ) {
        let memories = learningMemoryEntries
            .filter {
                $0.status == .active
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        let sessions = studySessions
            .filter {
                $0.courseID == courseID
                    && $0.scopeNeedsReview == false
                    && !$0.messages.isEmpty
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }

        summary = memories.first { $0.kind == .summary }
            ?? memories.first { $0.kind == .understood }

        if let memory = memories.first(where: { $0.kind == .nextStep }) {
            nextStepText = memory.text
            nextStepSessionID = memory.sessionID.flatMap { memorySessionID in
                sessions.first(where: { $0.id == memorySessionID })?.id
            }
            return
        }

        for session in sessions {
            if let suggestion = session.flow.suggestedNext
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                nextStepText = suggestion
                nextStepSessionID = session.id
                return
            }
        }

        nextStepText = nil
        nextStepSessionID = nil
    }
}
