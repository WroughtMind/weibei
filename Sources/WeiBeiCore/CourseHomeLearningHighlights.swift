import Foundation

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
                $0.relatedCourseIDs.contains(courseID)
                    && $0.scopeNeedsReview == false
                    && $0.hasChatHistory
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

        nextStepText = nil
        nextStepSessionID = nil
    }
}
