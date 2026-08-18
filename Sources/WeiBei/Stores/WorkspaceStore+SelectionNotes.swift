import AppKit
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

    @discardableResult
    func saveSelectionNote(_ text: String, includeLatestAnswer: Bool = false) -> SelectionThread? {
        guard let selectionContext,
              selectionContext.source == .document,
              let materialID = selectionContext.itemID ?? selectedMaterialItem?.id,
              let material = item(withID: materialID), material.isCourseMaterial else { return nil }
        let previousThreads = selectionThreads
        let previousActiveThreadID = activeSelectionThreadID
        let ordinaryNote = showNotes && !activeNoteIsLoading && activeNoteItem?.excerptSourceItemID == nil
            ? activeNoteItem : nil
        let previousOrdinaryNote = ordinaryNote.map { ($0.id, noteText) }
        let existingExcerptNotebook = importedItems.first {
            $0.excerptSourceItemID == material.id && $0.isNotebookNote
        }
        guard let excerptNotebook = excerptNotebook(for: material) else { return nil }
        let previousExcerptMarkdown = storedMarkdown(for: excerptNotebook)
        let thread = beginOrReuseSelectionThread(for: selectionContext)
        guard let index = selectionThreads.firstIndex(where: { $0.id == thread.id }) else { return nil }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.isEmpty {
            selectionThreads[index].isExcerpted = true
        } else {
            selectionThreads[index].entries.append(SelectionAnnotationEntry(text: note))
        }
        if includeLatestAnswer, let attachment = latestSelectionAnswer(for: thread.id),
           !selectionThreads[index].answerAttachments.contains(where: { $0.messageID == attachment.messageID }) {
            selectionThreads[index].answerAttachments.append(attachment)
        }
        var insertedPlacementID: UUID?
        if let ordinaryNote {
            let placement = SelectionAnnotationPlacement(noteItemID: ordinaryNote.id)
            insertedPlacementID = placement.id
            selectionThreads[index].placements.append(placement)
            noteEditorCommand = NoteEditorCommand(
                kind: .insertMarkdown,
                markdown: "\n\n" + selectionPlacementMarkdown(selectionThreads[index], placement: placement) + "\n\n"
            )
        }
        selectionThreads[index].updatedAt = Date()
        activeSelectionThreadID = thread.id
        let writtenExcerptMarkdown = excerptNotebookMarkdown(for: material)
        updateNote(writtenExcerptMarkdown, for: excerptNotebook.id)
        syncSelectionThread(thread.id, excluding: ordinaryNote?.id ?? "")
        save()
        if let undoManager = NSApp.keyWindow?.undoManager {
            let createdExcerptNotebook = existingExcerptNotebook == nil ? excerptNotebook : nil
            undoManager.registerUndo(withTarget: self) { store in
                store.selectionThreads = previousThreads
                store.activeSelectionThreadID = previousActiveThreadID
                if let previousOrdinaryNote {
                    let current = store.markdown(forItemID: previousOrdinaryNote.0)
                    let restored = insertedPlacementID.map {
                        store.replacingPlacement($0, in: current, with: "")
                    } ?? current
                    store.updateNote(restored, for: previousOrdinaryNote.0)
                }
                if let existingExcerptNotebook {
                    store.updateNote(previousExcerptMarkdown, for: existingExcerptNotebook.id)
                } else if let createdExcerptNotebook, let url = createdExcerptNotebook.url {
                    let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                    if current == previousExcerptMarkdown || current == writtenExcerptMarkdown,
                       (try? FileManager.default.removeItem(at: url)) != nil {
                        store.removeItemRegistration(createdExcerptNotebook.id)
                    }
                }
                store.save()
            }
            undoManager.setActionName(ui("保存选区札记", "Save Selection Note"))
        }
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
        guard let notebook = importedItems.first(where: { $0.excerptSourceItemID == materialID }) else { return }
        updateNote(excerptNotebookMarkdown(materialID: materialID, title: notebook.title), for: notebook.id)
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
        return excerptNotebookMarkdown(materialID: material.id, title: title)
    }

    private func excerptNotebookMarkdown(materialID: String, title: String) -> String {
        let blocks = orderedExcerptThreads(for: materialID).map(selectionAnnotationMarkdown)
        return (["# \(title)"] + blocks).joined(separator: "\n\n") + "\n"
    }

    func selectionAnnotationMarkdown(_ thread: SelectionThread) -> String {
        let quoted = thread.selectionText.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }.joined(separator: "\n")
        let notes = thread.entries.map(\.text).joined(separator: "\n\n---\n\n")
        let answers = thread.answerAttachments.map { attachment in
            let body = attachment.answer.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }.joined(separator: "\n")
            return "> [!answer]- AI 回答\n> \(attachment.question)\n>\n\(body)"
        }.joined(separator: "\n\n")
        let source = thread.invalidatedAt == nil ? thread.ownerTitle : ui("\(thread.ownerTitle)（原材料已移除）", "\(thread.ownerTitle) (source removed)")
        return """
        <!-- weibei-selection-thread:\(thread.id.uuidString.lowercased()) -->
        > [!quote] 原文
        \(quoted)
        >
        > 来源：\(source)
        \(notes)
        \(answers)
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func invalidateSelectionThreads(for itemID: String) {
        let now = Date()
        var changed = false
        for index in selectionThreads.indices {
            if selectionThreads[index].itemID == itemID, selectionThreads[index].invalidatedAt == nil {
                selectionThreads[index].invalidatedAt = now
                selectionThreads[index].updatedAt = now
                changed = true
            }
            let previousCount = selectionThreads[index].placements.count
            selectionThreads[index].placements.removeAll { $0.noteItemID == itemID }
            changed = changed || previousCount != selectionThreads[index].placements.count
        }
        if changed { rewriteExcerptNotebook(for: itemID) }
    }

    func deleteSelectionThread(_ threadID: UUID) {
        guard let thread = selectionThreads.first(where: { $0.id == threadID }) else { return }
        for placement in thread.placements where placement.detachedAt == nil {
            let current = markdown(forItemID: placement.noteItemID)
            updateNote(replacingPlacement(placement.id, in: current, with: ""), for: placement.noteItemID)
        }
        selectionThreads.removeAll { $0.id == threadID }
        if activeSelectionThreadID == threadID { activeSelectionThreadID = nil }
        if let materialID = thread.itemID { rewriteExcerptNotebook(for: materialID) }
        save()
    }

    func latestSelectionAnswer(for threadID: UUID?) -> SelectionAIAnswerAttachment? {
        guard let threadID, let thread = selectionThreads.first(where: { $0.id == threadID }) else { return nil }
        let threadMessages = thread.messageIDs.compactMap { id in messages.first { $0.id == id } }
        guard let answer = threadMessages.last(where: {
            $0.role == .assistant && $0.completionState == .completed && !Self.isAgentFailureMessage($0.text)
        }) else { return nil }
        let question = threadMessages.last(where: { $0.role == .user && $0.createdAt <= answer.createdAt })?.text ?? ""
        let text = agentDisplayText(for: answer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SelectionAIAnswerAttachment(messageID: answer.id, question: question, answer: text)
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

    private func storedMarkdown(for item: StudyItem) -> String {
        markdown(forItemID: item.id)
    }

    private func markdown(forItemID itemID: String) -> String {
        if activeNoteItemID == itemID { return noteText }
        if let markdown = notesByItemID[itemID] { return markdown }
        guard let url = item(withID: itemID)?.url else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func placementNotes(from block: String) -> String {
        guard let source = block.range(of: "\n> 来源：") ?? block.range(of: "\n> Source:") else { return "" }
        let tail = block[source.upperBound...]
        guard let lineEnd = tail.firstIndex(of: "\n") else { return "" }
        let content = tail[tail.index(after: lineEnd)...]
        let placementEnd = content.range(of: "\n<!-- /weibei-selection-placement:")?.lowerBound ?? content.endIndex
        let answerEnd = content.range(of: "\n> [!answer]")?.lowerBound ?? content.endIndex
        let end = min(placementEnd, answerEnd)
        return content[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
