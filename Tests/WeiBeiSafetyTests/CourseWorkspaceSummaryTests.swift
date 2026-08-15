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

        XCTAssertEqual(highlights.nextStepText, "Review the linked note")
        XCTAssertEqual(highlights.nextStepSessionID, sessionID)
    }
}
