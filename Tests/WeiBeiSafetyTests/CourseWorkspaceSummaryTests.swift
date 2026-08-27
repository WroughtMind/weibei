import Foundation
import XCTest
import WeiBeiCore

final class CourseWorkspaceSummaryTests: XCTestCase {
    func testLearningHighlightsIncludeChatAssociatedWithMultipleCourses() {
        let targetCourseID = UUID()
        let otherCourseID = UUID()
        let sessionID = UUID()
        let session = StudySession(
            id: sessionID,
            title: "Shared course discussion",
            messages: [
                AgentMessage(
                    role: .user,
                    text: "Explain the relationship",
                    source: nil
                ),
            ],
            relatedCourseIDs: [targetCourseID, otherCourseID],
            flow: StudyFlowState(
                phase: .plan,
                suggestedNext: ["Review the linked note"]
            )
        )

        let highlights = CourseHomeLearningHighlights(
            courseID: targetCourseID,
            learningMemoryEntries: [],
            studySessions: [session]
        )

        // 下一步建议只来自记忆 nextStep 条目；旧 flow.suggestedNext 不再浮出。
        XCTAssertNil(highlights.nextStepText)
        XCTAssertNil(highlights.nextStepSessionID)

        let memoryHighlights = CourseHomeLearningHighlights(
            courseID: targetCourseID,
            learningMemoryEntries: [
                LearningMemoryEntry(
                    kind: .nextStep,
                    text: "Review the linked note",
                    evidence: "Test",
                    origin: .userStatement,
                    sessionID: sessionID
                ),
            ],
            studySessions: [session]
        )

        XCTAssertEqual(memoryHighlights.nextStepText, "Review the linked note")
        XCTAssertEqual(memoryHighlights.nextStepSessionID, sessionID)
    }
}
