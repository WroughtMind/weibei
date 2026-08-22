import Foundation
import WeiBeiCore

struct NoteEditorSaveReceipt: Sendable {
    let documentID: String
    let digest: String
    let revision: UInt64
}

struct NoteEditorRecoveryConflict: Identifiable, Equatable, Sendable {
    let diskMarkdown: String
    let checkpoint: NoteRecoveryCheckpoint
    var id: String { checkpoint.metadata.documentID }
}

@MainActor
extension WorkspaceStore {
    var activeNoteEditorDocumentID: String {
        activeNoteItemID ?? blankNoteDraftMaterialID.map { "draft:\($0)" } ?? ""
    }

    func acceptNoteEditorSnapshot(_ snapshot: NoteEditorSnapshotReadyEvent) {
        let digest = Self.noteContentDigest(Data(snapshot.markdown.utf8))
        let baseDigest = latestNoteEditorSnapshot.flatMap {
            $0.documentID == snapshot.documentID ? $0.baseDigest : nil
        } ?? noteEditorBaseDigest(for: snapshot.documentID)
        latestNoteEditorSnapshot = (
            snapshot.documentID,
            digest,
            baseDigest,
            snapshot.revision
        )
        Task {
            _ = try? await noteRecoveryStore.store(
                documentID: snapshot.documentID,
                baseFileDigest: baseDigest,
                revision: snapshot.revision,
                markdown: snapshot.markdown
            )
        }
        if noteEditorRecoveryConflict?.id == snapshot.documentID
            || noteEditorConflictProbeDocumentID == snapshot.documentID { return }
        if snapshot.documentID.hasPrefix("draft:") {
            updateNote(snapshot.markdown)
        } else {
            updateNote(snapshot.markdown, for: snapshot.documentID)
            flushPendingNotePersistence(for: snapshot.documentID)
        }
    }

    func freshActiveNoteEditorSnapshot() async -> Bool {
        if noteEditingSession.dirty {
            do {
                _ = try await noteEditingSession.snapshot()
            } catch {
                return false
            }
        }
        return await waitForBlankNoteMaterialization()
    }

    func noteEditorDidPersist(_ markdown: String, documentID: String) {
        let digest = Self.noteContentDigest(Data(markdown.utf8))
        let revision = latestNoteEditorSnapshot.flatMap {
            $0.documentID == documentID && $0.digest == digest ? $0.revision : nil
        }
        completeNoteEditorSave(
            NoteEditorSaveReceipt(
                documentID: documentID,
                digest: digest,
                revision: revision ?? 0
            ),
            marksSessionSaved: revision != nil
        )
    }

    func makeNoteEditorWorkspaceSaveReceipt(
        _ workspace: PersistedWorkspace
    ) -> NoteEditorSaveReceipt? {
        guard let snapshot = latestNoteEditorSnapshot,
              item(withID: snapshot.documentID)?.editsBackingMarkdownFile == false,
              let markdown = workspace.notesByItemID[snapshot.documentID],
              snapshot.digest == Self.noteContentDigest(Data(markdown.utf8)) else {
            return nil
        }
        return NoteEditorSaveReceipt(
            documentID: snapshot.documentID,
            digest: snapshot.digest,
            revision: snapshot.revision
        )
    }

    func noteEditorDidPersistWorkspace(_ receipt: NoteEditorSaveReceipt?) {
        guard let receipt else { return }
        completeNoteEditorSave(receipt, marksSessionSaved: true)
    }

    private func completeNoteEditorSave(
        _ receipt: NoteEditorSaveReceipt,
        marksSessionSaved: Bool
    ) {
        Task {
            _ = try? await noteRecoveryStore.removeIfCheckpointMatches(
                documentID: receipt.documentID,
                checkpointDigest: receipt.digest
            )
        }
        guard marksSessionSaved,
              noteEditingSession.documentID == receipt.documentID else { return }
        _ = noteEditingSession.markSaved(revision: receipt.revision)
        if let snapshot = latestNoteEditorSnapshot,
           snapshot.documentID == receipt.documentID,
           snapshot.digest == receipt.digest {
            latestNoteEditorSnapshot = (
                snapshot.documentID,
                snapshot.digest,
                receipt.digest,
                snapshot.revision
            )
        }
    }

    func classifyNoteEditorRecovery(
        documentID: String,
        diskMarkdown: String
    ) async -> NoteRecoveryClassification {
        (try? await noteRecoveryStore.classify(
            documentID: documentID,
            diskDigest: Self.noteContentDigest(Data(diskMarkdown.utf8))
        )) ?? .damaged
    }

    func reconcileActiveNoteEditorWithBackingFile() async {
        let documentID = noteEditingSession.dirty
            ? noteEditingSession.documentID
            : activeNoteEditorDocumentID
        guard let item = item(withID: documentID),
              item.editsBackingMarkdownFile,
              let url = item.url,
              let data = try? Data(contentsOf: url),
              let diskMarkdown = String(data: data, encoding: .utf8) else { return }
        if noteEditingSession.dirty {
            switch await classifyNoteEditorRecovery(
                documentID: documentID,
                diskMarkdown: diskMarkdown
            ) {
            case .stale:
                noteEditorDidPersist(diskMarkdown, documentID: documentID)
            case .restore:
                _ = await freshActiveNoteEditorSnapshot()
            case .conflict(let checkpoint):
                cancelPendingNotePersistence(for: documentID)
                pendingNotePersistenceByItemID.removeValue(forKey: documentID)
                noteEditorRecoveryConflict = NoteEditorRecoveryConflict(
                    diskMarkdown: diskMarkdown,
                    checkpoint: checkpoint
                )
            case .none:
                let diskDigest = Self.noteContentDigest(data)
                let baseDigest = latestNoteEditorSnapshot.flatMap {
                    $0.documentID == documentID ? $0.baseDigest : nil
                } ?? noteEditorBaseDigest(for: documentID)
                if baseDigest == diskDigest {
                    _ = await freshActiveNoteEditorSnapshot()
                } else {
                    noteEditorConflictProbeDocumentID = documentID
                    defer { noteEditorConflictProbeDocumentID = nil }
                    guard let snapshot = try? await noteEditingSession.snapshot() else { return }
                    let checkpoint = NoteRecoveryCheckpoint(
                        metadata: NoteRecoveryMetadata(
                            documentID: documentID,
                            baseFileDigest: baseDigest,
                            checkpointDigest: Self.noteContentDigest(Data(snapshot.markdown.utf8)),
                            revision: snapshot.revision,
                            updatedAt: Date(),
                            dialectVersion: 1
                        ),
                        markdown: snapshot.markdown
                    )
                    noteEditorRecoveryConflict = NoteEditorRecoveryConflict(
                        diskMarkdown: diskMarkdown,
                        checkpoint: checkpoint
                    )
                }
            case .damaged:
                break
            }
            return
        }

        switch await classifyNoteEditorRecovery(
            documentID: documentID,
            diskMarkdown: diskMarkdown
        ) {
        case .restore(let checkpoint):
            latestNoteEditorSnapshot = (
                documentID,
                checkpoint.metadata.checkpointDigest,
                checkpoint.metadata.baseFileDigest,
                checkpoint.metadata.revision
            )
            noteEditingSession.replaceDocument(
                with: documentID,
                initialRevision: checkpoint.metadata.revision
            )
            restoreNoteEditorCheckpoint(checkpoint)
            flushPendingNotePersistence(for: documentID)
            noteEditorCommand = NoteEditorCommand(
                kind: .reloadDocument,
                markdown: checkpoint.markdown
            )
            return
        case .conflict(let checkpoint):
            noteEditorRecoveryConflict = NoteEditorRecoveryConflict(
                diskMarkdown: diskMarkdown,
                checkpoint: checkpoint
            )
            return
        case .none, .stale, .damaged:
            break
        }

        let previousDigest = Self.noteContentDigest(Data(noteText.utf8))
        refreshActiveNoteFromBackingFile()
        guard previousDigest != Self.noteContentDigest(Data(noteText.utf8)) else { return }
        noteEditingSession.replaceDocument(with: item.id)
        noteEditorCommand = NoteEditorCommand(
            kind: .reloadDocument,
            markdown: noteText
        )
    }

    func resolveNoteEditorRecoveryConflict(useDisk: Bool) async {
        guard let conflict = noteEditorRecoveryConflict else { return }
        noteEditorRecoveryConflict = nil
        if useDisk {
            let documentID = conflict.checkpoint.metadata.documentID
            // 副本先行（计划 §5 阶段2）：选磁盘版本前，用户版本先入备份环。
            _ = try? NoteBackupRing.capture(
                content: Data(conflict.checkpoint.markdown.utf8),
                itemID: documentID,
                rootURL: noteBackupRootURL
            )
            try? await noteRecoveryStore.remove(documentID: documentID)
            cancelPendingNotePersistence(for: documentID)
            pendingNotePersistenceByItemID.removeValue(forKey: documentID)
            let remainsActive = documentID == activeNoteEditorDocumentID
            if remainsActive { noteText = conflict.diskMarkdown }
            let digest = Self.noteContentDigest(Data(conflict.diskMarkdown.utf8))
            noteBackingContentDigestsByItemID[documentID] = digest
            lastSelfWrittenNoteDigestsByItemID[documentID] = digest
            latestNoteEditorSnapshot = nil
            setNoteDraft(nil, for: documentID)
            let nextDocumentID = remainsActive
                ? documentID
                : activeNoteEditorDocumentID
            noteEditingSession.replaceDocument(with: nextDocumentID)
            noteEditorCommand = NoteEditorCommand(
                kind: .reloadDocument,
                markdown: remainsActive ? conflict.diskMarkdown : noteText
            )
        } else {
            if noteEditingSession.dirty,
               await freshActiveNoteEditorSnapshot() { return }
            latestNoteEditorSnapshot = (
                conflict.id,
                conflict.checkpoint.metadata.checkpointDigest,
                conflict.checkpoint.metadata.baseFileDigest,
                conflict.checkpoint.metadata.revision
            )
            restoreNoteEditorCheckpoint(conflict.checkpoint)
            if !conflict.checkpoint.metadata.documentID.hasPrefix("draft:") {
                flushPendingNotePersistence(
                    for: conflict.checkpoint.metadata.documentID
                )
            }
            let remainsActive = conflict.checkpoint.metadata.documentID
                == activeNoteEditorDocumentID
            noteEditingSession.replaceDocument(
                with: remainsActive
                    ? conflict.checkpoint.metadata.documentID
                    : activeNoteEditorDocumentID,
                initialRevision: remainsActive
                    ? conflict.checkpoint.metadata.revision
                    : 0
            )
            noteEditorCommand = NoteEditorCommand(
                kind: .reloadDocument,
                markdown: remainsActive ? conflict.checkpoint.markdown : noteText
            )
        }
    }

    func restoreNoteEditorCheckpoint(_ checkpoint: NoteRecoveryCheckpoint) {
        if checkpoint.metadata.documentID.hasPrefix("draft:") {
            updateNote(checkpoint.markdown)
        } else {
            updateNote(checkpoint.markdown, for: checkpoint.metadata.documentID)
        }
    }

    private func noteEditorBaseDigest(for documentID: String) -> String {
        if documentID.hasPrefix("draft:") {
            return Self.noteContentDigest(Data())
        }
        if let digest = lastSelfWrittenNoteDigestsByItemID[documentID]
            ?? noteBackingContentDigestsByItemID[documentID] {
            return digest
        }
        if let url = item(withID: documentID)?.url,
           let data = try? Data(contentsOf: url) {
            return Self.noteContentDigest(data)
        }
        return Self.noteContentDigest(Data((notesByItemID[documentID] ?? "").utf8))
    }
}
