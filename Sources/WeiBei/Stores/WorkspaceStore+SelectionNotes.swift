import Foundation
import WeiBeiCore

extension WorkspaceStore {
    func selectionMarks(forItemID itemID: String?) -> [SelectionMark] {
        guard let itemID else { return [] }
        return selectionThreads(forItemID: itemID).compactMap { thread in
            guard thread.hasAsk || thread.hasNote else { return nil }
            return SelectionMark(id: thread.id, text: thread.selectionText, hasAsk: thread.hasAsk,
                                 hasNote: thread.hasNote, sourceAnchor: thread.sourceAnchor)
        }
    }

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

    func openExcerptNotebook(for materialID: String) {
        guard let material = item(withID: materialID), let notebook = excerptNotebook(for: material) else { return }
        select(itemID: notebook.id)
    }

    func orderedExcerptThreads(for materialID: String) -> [SelectionThread] {
        selectionThreads.filter { $0.itemID == materialID && $0.hasNote }.sorted {
            switch ($0.customOrder, $1.customOrder) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return ($0.sourceAnchor?.startOffset ?? 0) < ($1.sourceAnchor?.startOffset ?? 0)
            }
        }
    }

    func moveExcerptThread(_ movingID: UUID, before targetID: UUID, materialID: String) {
        var ids = orderedExcerptThreads(for: materialID).map(\.id)
        guard let source = ids.firstIndex(of: movingID), let target = ids.firstIndex(of: targetID) else { return }
        let id = ids.remove(at: source)
        ids.insert(id, at: target > source ? target - 1 : target)
        for (order, id) in ids.enumerated() {
            if let index = selectionThreads.firstIndex(where: { $0.id == id }) { selectionThreads[index].customOrder = order }
        }
        rewriteExcerptNotebook(for: materialID)
    }

    func restoreExcerptSourceOrder(for materialID: String) {
        for index in selectionThreads.indices where selectionThreads[index].itemID == materialID {
            selectionThreads[index].customOrder = nil
        }
        rewriteExcerptNotebook(for: materialID)
    }

    private func rewriteExcerptNotebook(for materialID: String) {
        guard let material = item(withID: materialID),
              let notebook = importedItems.first(where: { $0.excerptSourceItemID == materialID }) else { return }
        updateNote(excerptNotebookMarkdown(for: material), for: notebook.id)
        save()
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
        let blocks = orderedExcerptThreads(for: material.id).map(selectionAnnotationMarkdown)
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
