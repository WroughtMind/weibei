import Foundation
import WeiBeiCore

func courseContextItemMatches(
    _ item: StudyItem,
    kind: ContextualContentKind
) -> Bool {
    kind == .note ? item.isNotebookNote : item.isCourseMaterial
}

extension WorkspaceStore {
    var activeNoteIsLoading: Bool {
        activeNoteItemID.map { courseNoteLoadTasksByItemID[$0] != nil } ?? false
    }

    func moveCourse(_ courseID: UUID, before targetCourseID: UUID) {
        guard courseID != targetCourseID,
              let sourceIndex = courses.firstIndex(where: { $0.id == courseID }),
              let targetIndex = courses.firstIndex(where: { $0.id == targetCourseID }) else { return }
        let course = courses.remove(at: sourceIndex)
        courses.insert(course, at: sourceIndex < targetIndex ? targetIndex - 1 : targetIndex)
        save()
    }

    func moveCourseItem(
        _ itemID: String,
        before targetItemID: String?,
        intoNotebook: Bool
    ) {
        guard let sourceIndex = importedItems.firstIndex(where: { $0.id == itemID }) else { return }
        if intoNotebook {
            guard importedItems[sourceIndex].kind == .markdown else { return }
            importedItems[sourceIndex].isNotebookNote = true
        } else {
            importedItems[sourceIndex].appearsInMaterials = true
        }
        if let targetItemID,
           itemID != targetItemID,
           let targetIndex = importedItems.firstIndex(where: { $0.id == targetItemID }) {
            let item = importedItems.remove(at: sourceIndex)
            importedItems.insert(item, at: sourceIndex < targetIndex ? targetIndex - 1 : targetIndex)
        }
        invalidateAgentContext()
        save()
    }
}
