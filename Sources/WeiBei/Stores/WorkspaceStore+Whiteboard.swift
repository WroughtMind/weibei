import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    /// Classroom export creates a new, source-linked note through the existing write path.
    func saveWhiteboardNote(_ session: WhiteboardSession) -> Bool {
        guard let source = allItems.first(where: { $0.id == session.source.itemID }) else {
            showImportantOperationError(ui("原材料已不在资料库，课堂记录仍保留。", "The source is no longer in the library. The lesson is retained."))
            return false
        }
        return createNotebookNote(seed: .currentMaterial(source),
            title: session.lesson.title + " · 白板笔记", initialMarkdown: session.markdown()) != nil
    }

}
