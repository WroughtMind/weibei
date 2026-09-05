import Foundation
import WeiBeiCore

extension WorkspaceStore {
    var canContinueLastWork: Bool {
        guard let point = lastWork else { return false }
        return point.materialID.flatMap { item(withID: $0) } != nil
            || point.noteID.flatMap { item(withID: $0) } != nil
            || point.chatID.map { id in studySessions.contains { $0.id == id } } == true
    }

    func captureLastWork() {
        guard showReader || showNotes || showAgent else { return }
        let draft = pendingComposerDraft ?? agentDraft
        let hasChat = activeStudySession?.hasChatHistory == true || !draft.isEmpty
        guard selectedMaterialItem != nil || activeNoteItem != nil || hasChat else { return }
        lastWork = WorkspaceResumePoint(
            materialID: selectedMaterialItem?.id,
            noteID: activeNoteItem?.id,
            chatID: hasChat ? activeStudySessionID : nil,
            draft: draft,
            layout: layout,
            order: normalizedThreePaneOrder,
            reader: showReader,
            notes: showNotes,
            chat: showAgent
        )
    }

    func continueLastWork() {
        guard let point = lastWork, canContinueLastWork else { return }
        requestNoteSelectionTransition(to: point.noteID) { [weak self] in
            guard let self else { return }
            if let id = point.materialID, item(withID: id)?.isCourseMaterial == true {
                openContextualItem(id, kind: .material)
            }
            if let id = point.noteID, item(withID: id)?.isNotebookNote == true {
                openContextualItem(id, kind: .note)
            }
            if let id = point.chatID, studySessions.contains(where: { $0.id == id }) {
                activateStudySession(id, expectedCourseID: nil, expectedScopeNeedsReview: false)
                agentDraft = point.draft
                pendingComposerDraft = point.draft.isEmpty ? nil : point.draft
            }
            layout = point.layout
            threePaneOrder = point.order
            showReader = point.reader
            showNotes = point.notes
            showAgent = point.chat
            save()
        }
    }
}
