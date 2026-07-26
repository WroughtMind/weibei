import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Course membership, study-session, and learning-memory state exposed by the workspace façade.
extension WorkspaceStore {
    var allItems: [StudyItem] {
        sampleItems + importedItems
    }

    var courseMaterials: [StudyItem] {
        importedItems.filter { !$0.isNotebookNote }
    }

    var courseNotebookItems: [StudyItem] {
        importedItems.filter(\.isNotebookNote)
    }

    var activeCourse: Course? {
        guard let activeCourseID else { return nil }
        return courses.first { $0.id == activeCourseID }
    }

    func course(withID courseID: UUID) -> Course? {
        courses.first { $0.id == courseID }
    }

    func courseItems(in courseID: UUID) -> [StudyItem] {
        let itemIDs = Set(courseMembershipIndex.itemIDs(in: courseID))
        return importedItems.filter { itemIDs.contains($0.id) }
    }

    func courseMaterials(in courseID: UUID) -> [StudyItem] {
        courseItems(in: courseID).filter { !$0.isNotebookNote }
    }

    func courseNotes(in courseID: UUID) -> [StudyItem] {
        courseItems(in: courseID).filter(\.isNotebookNote)
    }

    func courseIDs(for itemID: String) -> [UUID] {
        courseMembershipIndex.courseIDs(for: itemID)
    }

    var unassignedCourseMaterials: [StudyItem] {
        courseMaterials.filter { courseMembershipIndex.courseIDs(for: $0.id).isEmpty }
    }

    var unassignedCourseNotes: [StudyItem] {
        courseNotebookItems.filter { courseMembershipIndex.courseIDs(for: $0.id).isEmpty }
    }

    func activateCourse(_ id: UUID?) {
        let resolvedID = id.flatMap { candidate in
            courses.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        guard activeCourseID != resolvedID else { return }
        activeCourseID = resolvedID
        save()
    }

    @discardableResult
    func createCourse(title rawTitle: String) -> UUID? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let course = Course(
            title: title,
            colorIndex: nextCourseColorIndex()
        )
        courses.append(course)
        activeCourseID = course.id
        save()
        return course.id
    }

    func renameCourse(_ courseID: UUID, title rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let index = courses.firstIndex(where: { $0.id == courseID }),
              courses[index].title != title else { return }
        courses[index].title = title
        courses[index].updatedAt = Date()
        save()
    }

    func deleteCourse(_ courseID: UUID) {
        guard courses.contains(where: { $0.id == courseID }) else { return }
        courses.removeAll { $0.id == courseID }
        var memberships = courseMembershipIndex
        memberships.removeCourse(courseID)
        courseItemMemberships = memberships.values
        if activeCourseID == courseID {
            activeCourseID = courses.first?.id
        }
        save()
    }

    func setCourseIDs(_ courseIDs: Set<UUID>, for itemID: String) {
        guard importedItems.contains(where: { $0.id == itemID }) else { return }
        let validCourseIDs = Set(courses.map(\.id))
        var memberships = courseMembershipIndex
        memberships.replaceCourses(for: itemID, courseIDs: courseIDs.intersection(validCourseIDs))
        guard memberships.values != courseItemMemberships else { return }
        courseItemMemberships = memberships.values
        save()
    }

    func assignItemIDs(_ itemIDs: Set<String>, to courseID: UUID) {
        guard courses.contains(where: { $0.id == courseID }) else { return }
        let validItemIDs = Set(importedItems.map(\.id))
        var memberships = courseMembershipIndex
        memberships.assign(itemIDs: itemIDs.intersection(validItemIDs), to: courseID)
        guard memberships.values != courseItemMemberships else { return }
        courseItemMemberships = memberships.values
        activeCourseID = courseID
        save()
    }

    func relationCount(in courseID: UUID) -> Int {
        let materialIDs = Set(courseMaterials(in: courseID).map(\.id))
        let noteIDs = Set(courseNotes(in: courseID).map(\.id))
        return noteSourceLinks.lazy.filter {
            materialIDs.contains($0.sourceItemID) && noteIDs.contains($0.noteItemID)
        }.count
    }

    var recentCourseSessions: [StudySession] {
        orderedStudySessions.filter { !$0.messages.isEmpty }
    }

    /// Sessions that touch any material/note belonging to the course (no session.courseID yet).
    func sessionsTouchingCourse(_ courseID: UUID) -> [StudySession] {
        let itemIDs = Set(courseMembershipIndex.itemIDs(in: courseID))
        guard !itemIDs.isEmpty else { return [] }
        return orderedStudySessions.filter { session in
            guard !session.messages.isEmpty else { return false }
            if let materialID = session.materialItemID, itemIDs.contains(materialID) {
                return true
            }
            if let groupingID = session.groupingMaterialItemID, itemIDs.contains(groupingID) {
                return true
            }
            return session.focusItemIDs.contains(where: itemIDs.contains)
        }
    }

    /// Sessions that reference a specific material (and optionally other focus items).
    func sessionsTouchingMaterial(_ materialID: String, in courseID: UUID? = nil) -> [StudySession] {
        let allowed: Set<String>? = courseID.map { Set(courseMembershipIndex.itemIDs(in: $0)) }
        return orderedStudySessions.filter { session in
            guard !session.messages.isEmpty else { return false }
            let touches = session.materialItemID == materialID
                || session.groupingMaterialItemID == materialID
                || session.focusItemIDs.contains(materialID)
            guard touches else { return false }
            if let allowed {
                let sessionItems = Set(session.focusItemIDs + [session.materialItemID, session.groupingMaterialItemID].compactMap { $0 })
                return !sessionItems.isDisjoint(with: allowed)
            }
            return true
        }
    }

    /// Best-effort course ownership for a session via materials/focus items (no session.courseID yet).
    func primaryCourseID(for session: StudySession) -> UUID? {
        let touched = Set(
            session.focusItemIDs
                + [session.materialItemID, session.groupingMaterialItemID].compactMap { $0 }
        )
        guard !touched.isEmpty else { return nil }
        let matched = courses.filter { course in
            !Set(courseMembershipIndex.itemIDs(in: course.id)).isDisjoint(with: touched)
        }
        if let activeCourseID, matched.contains(where: { $0.id == activeCourseID }) {
            return activeCourseID
        }
        return matched.first?.id
    }

    var activeCourseMemories: [LearningMemoryEntry] {
        orderedLearningMemoryEntries.filter { $0.status == .active }
    }

    var recentCourseMessages: [AgentMessage] {
        studySessions
            .flatMap(\.messages)
            .sorted { $0.createdAt > $1.createdAt }
    }

    var courseWorkspaceSummary: CourseWorkspaceSummary {
        CourseWorkspaceSummary(
            importedItems: importedItems,
            noteSourceLinks: noteSourceLinks,
            studyLocationsByItemID: studyLocationsByItemID,
            studySessions: studySessions,
            learningMemoryEntries: learningMemoryEntries
        )
    }

    var courseMaterialsWithoutReadingPosition: [StudyItem] {
        courseMaterials.filter { studyLocationsByItemID[$0.id] == nil }
    }

    var courseMaterialsWithoutNoteLinks: [StudyItem] {
        let validNoteIDs = Set(courseNotebookItems.map(\.id))
        let linkedIDs = Set(noteSourceLinks.lazy.filter { validNoteIDs.contains($0.noteItemID) }.map(\.sourceItemID))
        return courseMaterials.filter { !linkedIDs.contains($0.id) }
    }

    var courseNotesWithoutSourceLinks: [StudyItem] {
        let validSourceIDs = Set(courseMaterials.map(\.id))
        let linkedIDs = Set(noteSourceLinks.lazy.filter { validSourceIDs.contains($0.sourceItemID) }.map(\.noteItemID))
        return courseNotebookItems.filter { !linkedIDs.contains($0.id) }
    }

    func studyLocation(for itemID: String) -> StudyLocation? {
        studyLocationsByItemID[itemID]
    }

    func linkedNotes(for sourceItemID: String) -> [StudyItem] {
        let noteIDs = Set(linkedNoteIDs(for: sourceItemID))
        return courseNotebookItems.filter { noteIDs.contains($0.id) }
    }

    func linkedNoteIDs(for sourceItemID: String) -> [String] {
        noteSourceRelationIndex.noteIDs(for: sourceItemID)
    }

    func linkedNoteCount(for sourceItemID: String) -> Int {
        noteSourceRelationIndex.noteCount(for: sourceItemID)
    }

    func item(withID itemID: String) -> StudyItem? {
        allItems.first { $0.id == itemID }
    }

    var linkedSourceIDsForActiveNote: [String] {
        guard let noteItemID = activeNotebookItemID else { return [] }
        return linkedSourceIDs(for: noteItemID)
    }

    func linkedSourceIDs(for noteItemID: String) -> [String] {
        noteSourceRelationIndex.sourceIDs(for: noteItemID)
    }

    func linkedSourceCount(for noteItemID: String) -> Int {
        noteSourceRelationIndex.sourceCount(for: noteItemID)
    }

    func linkedCourseSourceIDs(for noteItemID: String) -> [String] {
        let validCourseIDs = Set(courseMaterials.map(\.id))
        return noteSourceRelationIndex.sourceIDs(for: noteItemID).filter(validCourseIDs.contains)
    }

    var linkedSourcesForActiveNote: [StudyItem] {
        let linkedIDs = Set(linkedSourceIDsForActiveNote)
        return allItems.filter { linkedIDs.contains($0.id) && !$0.isNotebookNote }
    }

    var linkedSourceCount: Int {
        linkedSourcesForActiveNote.count
    }

    var filteredItems: [StudyItem] {
        let query = librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }
        return allItems.filter { itemMatchesLibrarySearch($0, query: query) }
    }

    var activeStudySession: StudySession? {
        guard let activeStudySessionID else { return nil }
        return studySessions.first { $0.id == activeStudySessionID }
    }

    var orderedStudySessions: [StudySession] {
        studySessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Sessions for the session menu: either all, or material-grouped with current material first.
    var studySessionsForMenu: [StudySession] {
        if showAllStudySessions {
            return orderedStudySessions
        }
        if let materialID = selectedMaterialItem?.id {
            let matching = orderedStudySessions.filter { $0.groupingMaterialItemID == materialID }
            if !matching.isEmpty { return matching }
        }
        return orderedStudySessions
    }

    /// Grouped history for the expanded "view all" picker: material title → sessions.
    var studySessionsGroupedByMaterial: [(materialID: String?, title: String, sessions: [StudySession])] {
        var groups: [String?: [StudySession]] = [:]
        for session in orderedStudySessions {
            groups[session.groupingMaterialItemID, default: []].append(session)
        }
        return groups.keys.sorted { lhs, rhs in
            let leftDate = groups[lhs]?.first?.updatedAt ?? .distantPast
            let rightDate = groups[rhs]?.first?.updatedAt ?? .distantPast
            return leftDate > rightDate
        }.map { materialID in
            let title: String
            if let materialID, let item = allItems.first(where: { $0.id == materialID }) {
                title = displayTitle(for: item)
            } else {
                title = ui("未关联资料", "Unlinked")
            }
            return (materialID, title, groups[materialID] ?? [])
        }
    }

    var orderedLearningMemoryEntries: [LearningMemoryEntry] {
        learningMemoryEntries.sorted { $0.updatedAt > $1.updatedAt }
    }

    func learningMemoryKindLabel(_ kind: LearningMemoryKind) -> String {
        switch kind {
        case .goal: ui("目标", "Goal")
        case .understood: ui("已理解", "Understood")
        case .confusion: ui("困惑", "Confusion")
        case .nextStep: ui("下一步", "Next Step")
        case .preference: ui("偏好", "Preference")
        }
    }

    var activeStudySessionTitle: String {
        activeStudySession?.title ?? ui("新学习会话", "New Study Session")
    }

    var lastStudyLocation: StudyLocation? {
        studyLocationsByItemID.values.max { $0.lastStudiedAt < $1.lastStudiedAt }
    }

    var canResumePreviousStudy: Bool {
        lastStudyLocation != nil
    }

    var hasCurrentSessionInferredMemory: Bool {
        guard let activeStudySessionID else { return false }
        return learningMemoryEntries.contains {
            $0.sessionID == activeStudySessionID && $0.origin == .agentInference
        }
    }

    func createStudySession() {
        cancelAgentRequest()
        syncActiveStudySession()
        let materialID = selectedMaterialItem?.id
        let session = StudySession(
            title: ui("新学习会话", "New Study Session"),
            focusItemIDs: [materialID].compactMap { $0 },
            materialItemID: materialID
        )
        studySessions.append(session)
        activeStudySessionID = session.id
        messages = []
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        lastAgentReplyContextRevision = nil
        invalidateAgentContext()
        save()
    }

    func setShowAllStudySessions(_ enabled: Bool) {
        showAllStudySessions = enabled
    }

    func activateStudySession(_ id: UUID) {
        guard id != activeStudySessionID,
              let session = studySessions.first(where: { $0.id == id }) else { return }
        cancelAgentRequest()
        syncActiveStudySession()
        activeStudySessionID = id
        messages = session.messages
        latestAgentNoteProposal = nil
        latestAgentLearningUpdate = nil
        lastAgentReplyContextRevision = nil
        invalidateAgentContext()
        save()
    }

    func deleteStudySession(_ id: UUID) {
        guard studySessions.count > 1,
              let index = studySessions.firstIndex(where: { $0.id == id }) else { return }
        let deletingActiveSession = activeStudySessionID == id
        if deletingActiveSession { cancelAgentRequest() }
        studySessions.remove(at: index)
        learningMemoryEntries.removeAll { $0.sessionID == id && $0.origin == .agentInference }
        if deletingActiveSession, let replacement = orderedStudySessions.first {
            activeStudySessionID = replacement.id
            messages = replacement.messages
            latestAgentNoteProposal = nil
            latestAgentLearningUpdate = nil
            lastAgentReplyContextRevision = nil
            invalidateAgentContext()
        }
        learningMemoryRevision &+= 1
        save()
    }

    func clearCurrentSessionInferredMemory() {
        guard let activeStudySessionID else { return }
        let previousCount = learningMemoryEntries.count
        learningMemoryEntries.removeAll {
            $0.sessionID == activeStudySessionID && $0.origin == .agentInference
        }
        guard learningMemoryEntries.count != previousCount else { return }
        learningMemoryRevision &+= 1
        latestAgentLearningUpdate = nil
        invalidateAgentContext()
        save()
    }

    func resumePreviousStudy() {
        guard let location = lastStudyLocation,
              let item = allItems.first(where: { $0.id == location.itemID }) else { return }
        if layout == .immersiveConversation || layout == .immersiveWriting {
            setLayout(item.isNotebookNote ? .immersiveWriting : .immersiveReading)
        }
        select(itemID: location.itemID)
        if item.isNotebookNote {
            showNotes = true
            focus(.notes)
            return
        }
        requestReaderPDFPage(location.pageIndex, recordsLocation: false)
        requestReaderHTMLLocation(id: location.locationID, title: location.locationTitle)
        showReader = true
        focus(.reader)
    }

    func ensureActiveStudySession() {
        if let activeStudySessionID,
           let session = studySessions.first(where: { $0.id == activeStudySessionID }) {
            messages = session.messages
            return
        }
        if let session = orderedStudySessions.first {
            activeStudySessionID = session.id
            messages = session.messages
            return
        }
        let session = StudySession(title: ui("新学习会话", "New Study Session"))
        studySessions = [session]
        activeStudySessionID = session.id
        messages = []
    }

    func appendAgentMessage(_ message: AgentMessage) {
        messages.append(message)
        syncActiveStudySession(titleSeed: message.role == .user ? message.text : nil)
        save()
    }

    func syncActiveStudySession(titleSeed: String? = nil) {
        guard let activeStudySessionID,
              let index = studySessions.firstIndex(where: { $0.id == activeStudySessionID }) else { return }
        studySessions[index].messages = messages
        studySessions[index].updatedAt = Date()
        if let titleSeed,
           studySessions[index].messages.filter({ $0.role == .user }).count == 1 {
            studySessions[index].title = Self.sessionTitle(from: titleSeed)
        }
        if studySessions[index].materialItemID == nil,
           let materialID = selectedMaterialItem?.id {
            studySessions[index].materialItemID = materialID
        }
        for itemID in [selectedItemID, activeNoteItemID].compactMap({ $0 }) {
            if !studySessions[index].focusItemIDs.contains(itemID) {
                studySessions[index].focusItemIDs.append(itemID)
            }
        }
        if studySessions[index].focusItemIDs.count > 24 {
            studySessions[index].focusItemIDs.removeFirst(studySessions[index].focusItemIDs.count - 24)
        }
    }

    static func sessionTitle(from text: String) -> String {
        let title = text
            .replacingOccurrences(of: #"[`*_>#\[\]()]"#, with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return title.isEmpty ? "Study Session" : String(title.prefix(36))
    }

}
