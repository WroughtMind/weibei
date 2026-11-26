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

}
