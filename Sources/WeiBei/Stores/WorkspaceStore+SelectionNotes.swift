import Foundation
import WeiBeiCore

extension WorkspaceStore {
    @discardableResult
    func saveSelectionNote(_ text: String) -> SelectionThread? {
        guard let selectionContext else { return nil }
        let thread = beginOrReuseSelectionThread(for: selectionContext)
        guard let index = selectionThreads.firstIndex(where: { $0.id == thread.id }) else { return nil }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            selectionThreads[index].isExcerpted = true
        } else {
            selectionThreads[index].entries.append(SelectionAnnotationEntry(text: note))
        }
        selectionThreads[index].updatedAt = Date()
        activeSelectionThreadID = thread.id
        save()
        return selectionThreads[index]
    }
}
