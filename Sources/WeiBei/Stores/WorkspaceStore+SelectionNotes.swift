import Foundation
import WeiBeiCore

extension WorkspaceStore {
    func appendSelectionToNote() {
        _ = saveSelectionNote("")
    }

    @discardableResult
    func saveSelectionNote(_ text: String) -> SelectionThread? {
        guard let selectionContext,
              selectionContext.source == .document,
              let materialID = selectionContext.itemID ?? selectedMaterialItem?.id,
              let material = item(withID: materialID), material.isCourseMaterial else { return nil }
        let ordinaryNote = showNotes && activeNoteItem?.excerptSourceItemID == nil
            ? activeNoteItem : nil
        guard let excerptNotebook = excerptNotebook(for: material) else { return nil }
        let thread = beginOrReuseSelectionThread(for: selectionContext)
        guard let index = selectionThreads.firstIndex(where: { $0.id == thread.id }) else { return nil }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            selectionThreads[index].isExcerpted = true
        } else {
            selectionThreads[index].entries.append(SelectionAnnotationEntry(text: note))
        }
        if let ordinaryNote {
            selectionThreads[index].placements.append(
                SelectionAnnotationPlacement(noteItemID: ordinaryNote.id)
            )
            noteEditorCommand = NoteEditorCommand(
                kind: .insertMarkdown,
                markdown: "\n\n" + selectionAnnotationMarkdown(selectionThreads[index]) + "\n\n"
            )
        }
        selectionThreads[index].updatedAt = Date()
        activeSelectionThreadID = thread.id
        updateNote(excerptNotebookMarkdown(for: material), for: excerptNotebook.id)
        save()
        return selectionThreads[index]
    }

    private func excerptNotebook(for material: StudyItem) -> StudyItem? {
        if let existing = importedItems.first(where: {
            $0.excerptSourceItemID == material.id && $0.isNotebookNote
        }) {
            return existing
        }
        let title = ui("\(displayTitle(for: material)) · 摘抄", "\(displayTitle(for: material)) · Excerpts")
        return createNotebookNote(
            seed: .currentMaterial(material),
            title: title,
            initialMarkdown: "# \(title)\n\n",
            excerptSourceItemID: material.id,
            activates: false
        )
    }

    private func excerptNotebookMarkdown(for material: StudyItem) -> String {
        let title = importedItems.first { $0.excerptSourceItemID == material.id }?.title
            ?? ui("\(displayTitle(for: material)) · 摘抄", "\(displayTitle(for: material)) · Excerpts")
        let blocks = selectionThreads
            .filter { $0.itemID == material.id && $0.hasNote }
            .sorted { ($0.sourceAnchor?.startOffset ?? 0) < ($1.sourceAnchor?.startOffset ?? 0) }
            .map(selectionAnnotationMarkdown)
        return (["# \(title)"] + blocks).joined(separator: "\n\n") + "\n"
    }

    func selectionAnnotationMarkdown(_ thread: SelectionThread) -> String {
        let quoted = thread.selectionText.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }.joined(separator: "\n")
        let notes = thread.entries.map(\.text).joined(separator: "\n\n---\n\n")
        return """
        <!-- weibei-selection-thread:\(thread.id.uuidString.lowercased()) -->
        > [!quote] 原文
        \(quoted)
        >
        > 来源：\(thread.ownerTitle)
        \(notes)
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
