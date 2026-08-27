import Foundation
import WeiBeiCore

/// Local no-Xcode mirrors for workspace-safety and course-root persistence
/// scenes that `WorkspaceSafetyTests` / `CourseWorkspaceSummaryTests` cover
/// through WorkspaceStore. Calls the same Core production APIs.
func checkWorkspaceSafetyScenes() throws {
    let targetCourseID = UUID()
    let otherCourseID = UUID()
    let sessionID = UUID()
    let nextStepMemory = LearningMemoryEntry(
        id: UUID(),
        kind: .nextStep,
        text: "Review the linked note",
        evidence: "SelfCheck",
        origin: .userStatement
    )
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
            suggestedNext: ["legacy flow suggestion no longer feeds next step"]
        )
    )
    let highlights = CourseHomeLearningHighlights(
        courseID: targetCourseID,
        learningMemoryEntries: [nextStepMemory],
        studySessions: [session]
    )
    expect(
        highlights.nextStepText == "Review the linked note"
            && highlights.nextStepSessionID == nil,
        "course-home next step comes from the nextStep memory entry of any related chat"
    )
    let legacyOnlyHighlights = CourseHomeLearningHighlights(
        courseID: targetCourseID,
        learningMemoryEntries: [],
        studySessions: [session]
    )
    expect(
        legacyOnlyHighlights.nextStepText == nil,
        "legacy flow.suggestedNext values no longer surface as the course-home next step"
    )

    let material = StudyItem(
        id: "imported:material",
        title: "文稿",
        subtitle: "文稿.txt",
        kind: .text,
        urlPath: "/tmp/文稿.txt",
        isSample: false
    )
    let note = StudyItem(
        id: "imported:note",
        title: "笔记",
        subtitle: "笔记.md",
        kind: .markdown,
        urlPath: "/tmp/笔记.md",
        isSample: false,
        isNotebookNote: true
    )
    let summary = CourseWorkspaceSummary(
        importedItems: [material, note],
        noteSourceLinks: [
            NoteSourceLink(noteItemID: note.id, sourceItemID: material.id),
        ],
        studyLocationsByItemID: [
            material.id: StudyLocation(
                itemID: material.id,
                itemTitle: material.title,
                pageIndex: 2,
                lastStudiedAt: Date(timeIntervalSince1970: 1_700_000_050)
            ),
        ],
        studySessions: [session],
        learningMemoryEntries: []
    )
    expect(
        summary.materialCount == 1
            && summary.noteCount == 1
            && summary.explicitLinkCount == 1
            && summary.readingPositionCount == 1
            && summary.unlinkedMaterialCount == 0
            && summary.unlinkedNoteCount == 0
            && summary.studySessionCount == 1,
        "course workspace summary counts persisted materials, notes, links, and chats"
    )

    let libraryIdentity = ImportedFileIdentity(
        volumeID: 1,
        fileID: 2,
        birthTimeSeconds: 3,
        birthTimeNanoseconds: 4
    )
    let course = Course(
        title: "货币银行学",
        sourceRootPath: "/tmp/WeiBei-security-hardening-web/test",
        sourceRootRelativePath: "test",
        sourceRootIdentity: libraryIdentity,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let resumePoint = CourseResumePoint(
        courseID: targetCourseID,
        materialLocation: StudyLocation(
            itemID: material.id,
            itemTitle: material.title,
            pageIndex: 18,
            lastStudiedAt: Date(timeIntervalSince1970: 1_700_000_080)
        ),
        chatID: sessionID,
        noteItemID: note.id,
        savedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    let snapshot = PersistedWorkspace(
        importedItems: [material, note],
        notesByItemID: [note.id: "# 笔记\n"],
        courses: [course],
        courseItemMemberships: [
            CourseItemMembership(courseID: course.id, itemID: material.id),
        ],
        activeCourseID: course.id,
        courseLibraryRootPath: "/tmp/WeiBei-security-hardening-web",
        courseLibraryRootIdentity: libraryIdentity,
        courseResumePoints: [resumePoint]
    )
    let restored = try JSONDecoder().decode(
        PersistedWorkspace.self,
        from: try JSONEncoder().encode(snapshot)
    )
    expect(
        restored.courseLibraryRootPath == "/tmp/WeiBei-security-hardening-web"
            && restored.courseLibraryRootIdentity == libraryIdentity
            && restored.courses == [course]
            && restored.courses?.first?.sourceRootRelativePath == "test"
            && restored.courses?.first?.sourceRootIdentity == libraryIdentity,
        "course library root and course source-root identity persist together"
    )
    expect(
        restored.courseResumePoints == [resumePoint],
        "course resume points keep material, chat, note, and timestamp"
    )
}
