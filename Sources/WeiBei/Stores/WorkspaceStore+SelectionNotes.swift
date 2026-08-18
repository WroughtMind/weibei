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
        let ordinaryNote = showNotes && !activeNoteIsLoading && activeNoteItem?.excerptSourceItemID == nil
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
            let placement = SelectionAnnotationPlacement(noteItemID: ordinaryNote.id)
            selectionThreads[index].placements.append(placement)
            noteEditorCommand = NoteEditorCommand(
                kind: .insertMarkdown,
                markdown: "\n\n" + selectionPlacementMarkdown(selectionThreads[index], placement: placement) + "\n\n"
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

    func activeSelectionPlacements() -> [(thread: SelectionThread, placement: SelectionAnnotationPlacement)] {
        guard let noteID = activeNoteItemID else { return [] }
        return selectionThreads.flatMap { thread in
            thread.placements.filter { $0.noteItemID == noteID && $0.detachedAt == nil }.map { (thread, $0) }
        }
    }

    func detachSelectionPlacement(_ placementID: UUID) {
        guard let noteID = activeNoteItemID,
              let threadIndex = selectionThreads.firstIndex(where: { $0.placements.contains { $0.id == placementID } }),
              let placementIndex = selectionThreads[threadIndex].placements.firstIndex(where: { $0.id == placementID }) else { return }
        selectionThreads[threadIndex].placements[placementIndex].detachedAt = Date()
        let marker = "<!-- weibei-selection-thread:\(selectionThreads[threadIndex].id.uuidString.lowercased()) -->\n"
        let plain = selectionAnnotationMarkdown(selectionThreads[threadIndex]).replacingOccurrences(of: marker, with: "")
        updateNote(replacingPlacement(placementID, in: noteText, with: plain), for: noteID)
        save()
    }

    func deleteSelectionPlacement(_ placementID: UUID) {
        guard let noteID = activeNoteItemID,
              let threadIndex = selectionThreads.firstIndex(where: { $0.placements.contains { $0.id == placementID } }) else { return }
        selectionThreads[threadIndex].placements.removeAll { $0.id == placementID }
        updateNote(replacingPlacement(placementID, in: noteText, with: ""), for: noteID)
        save()
    }

    func moveSelectionPlacement(_ placementID: UUID, offset: Int) {
        guard let noteID = activeNoteItemID else { return }
        let placements = activeSelectionPlacements().compactMap { pair -> (UUID, String, Range<String.Index>)? in
            guard let block = placementBlock(pair.placement.id, in: noteText), let range = noteText.range(of: block) else { return nil }
            return (pair.placement.id, block, range)
        }.sorted { $0.2.lowerBound < $1.2.lowerBound }
        guard let source = placements.firstIndex(where: { $0.0 == placementID }) else { return }
        let target = source + offset
        guard placements.indices.contains(target) else { return }
        let left = min(source, target), right = max(source, target)
        let first = placements[left], second = placements[right]
        let between = noteText[first.2.upperBound..<second.2.lowerBound]
        let replacement = second.1 + between + first.1
        updateNote(noteText.replacingCharacters(in: first.2.lowerBound..<second.2.upperBound, with: replacement), for: noteID)
    }

    func reconcileSelectionPlacements(in markdown: String, noteItemID: String) {
        let linked = selectionThreads.flatMap { thread in
            thread.placements.filter { $0.noteItemID == noteItemID && $0.detachedAt == nil }
                .map { (thread: thread, placement: $0) }
        }
        guard !linked.isEmpty else { return }
        var changed = false
        var changedThreadIDs: Set<UUID> = []
        for pair in linked {
            guard let block = placementBlock(pair.placement.id, in: markdown) else {
                if let threadIndex = selectionThreads.firstIndex(where: { $0.id == pair.thread.id }) {
                    selectionThreads[threadIndex].placements.removeAll { $0.id == pair.placement.id }
                    changed = true
                }
                continue
            }
            let noteText = placementNotes(from: block)
            let texts = noteText.isEmpty ? [] : noteText.components(separatedBy: "\n\n---\n\n")
            if let threadIndex = selectionThreads.firstIndex(where: { $0.id == pair.thread.id }),
               selectionThreads[threadIndex].entries.map(\.text) != texts {
                let existing = selectionThreads[threadIndex].entries
                selectionThreads[threadIndex].entries = texts.enumerated().map { offset, text in
                    offset < existing.count ? SelectionAnnotationEntry(id: existing[offset].id, text: text,
                        createdAt: existing[offset].createdAt, updatedAt: Date()) : SelectionAnnotationEntry(text: text)
                }
                selectionThreads[threadIndex].updatedAt = Date()
                changed = true
                changedThreadIDs.insert(pair.thread.id)
            }
        }
        for id in changedThreadIDs { syncSelectionThread(id, excluding: noteItemID) }
        if changed { save() }
    }

    private func syncSelectionThread(_ threadID: UUID, excluding noteItemID: String) {
        guard let thread = selectionThreads.first(where: { $0.id == threadID }) else { return }
        if let materialID = thread.itemID { rewriteExcerptNotebook(for: materialID) }
        for placement in thread.placements where placement.noteItemID != noteItemID && placement.detachedAt == nil {
            guard let current = notesByItemID[placement.noteItemID] else { continue }
            let updated = replacingPlacement(placement.id, in: current,
                with: selectionPlacementMarkdown(thread, placement: placement))
            if updated != current { updateNote(updated, for: placement.noteItemID) }
        }
    }

    private func selectionPlacementMarkdown(_ thread: SelectionThread, placement: SelectionAnnotationPlacement) -> String {
        """
        <!-- weibei-selection-placement:\(placement.id.uuidString.lowercased()) thread:\(thread.id.uuidString.lowercased()) -->
        \(selectionAnnotationMarkdown(thread))
        <!-- /weibei-selection-placement:\(placement.id.uuidString.lowercased()) -->
        """
    }

    private func placementBlock(_ placementID: UUID, in markdown: String) -> String? {
        let id = NSRegularExpression.escapedPattern(for: placementID.uuidString.lowercased())
        let pattern = "<!-- weibei-selection-placement:\(id) thread:[^ ]+ -->[\\s\\S]*?<!-- /weibei-selection-placement:\(id) -->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)),
              let range = Range(match.range, in: markdown) else { return nil }
        return String(markdown[range])
    }

    private func replacingPlacement(_ placementID: UUID, in markdown: String, with replacement: String) -> String {
        guard let block = placementBlock(placementID, in: markdown), let range = markdown.range(of: block) else { return markdown }
        return markdown.replacingCharacters(in: range, with: replacement)
    }

    private func placementNotes(from block: String) -> String {
        guard let source = block.range(of: "\n> 来源：") ?? block.range(of: "\n> Source:") else { return "" }
        let tail = block[source.upperBound...]
        guard let lineEnd = tail.firstIndex(of: "\n") else { return "" }
        let content = tail[tail.index(after: lineEnd)...]
        let end = content.range(of: "\n<!-- /weibei-selection-placement:")?.lowerBound ?? content.endIndex
        return content[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
