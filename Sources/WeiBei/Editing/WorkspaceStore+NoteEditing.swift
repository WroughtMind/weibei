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
    var checkpointIsPersisted = false
    var id: String { checkpoint.metadata.documentID }
}

@MainActor
extension WorkspaceStore {
    var activeNoteEditorDocumentID: String {
        activeNoteItemID ?? blankNoteDraftMaterialID.map { "draft:\($0)" } ?? ""
    }

    var noteEditorRecoveryConflict: NoteEditorRecoveryConflict? {
        get { noteEditorRecoveryConflictsByItemID[activeNoteEditorDocumentID] }
        set {
            if let newValue {
                noteEditorRecoveryConflictsByItemID[newValue.id] = newValue
            } else {
                noteEditorRecoveryConflictsByItemID.removeValue(
                    forKey: activeNoteEditorDocumentID
                )
            }
        }
    }

    var activeNoteSaveStatus: NoteSaveStatus {
        noteEditorRecoveryConflict == nil
            ? noteEditingSession.saveStatus
            : .externallyModified
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await noteRecoveryStore.store(
                    documentID: snapshot.documentID,
                    baseFileDigest: baseDigest,
                    revision: snapshot.revision,
                    markdown: snapshot.markdown
                )
            } catch {
                if let url = item(withID: snapshot.documentID)?.url,
                   Self.noteContentDigest(at: url) == digest { return }
                noteEditingSession.markSaveFailed(documentID: snapshot.documentID)
                WeiBeiLog.noteRepair.error(
                    "code=note_recovery_store_failed document=\(snapshot.documentID, privacy: .private) reason=\(error.localizedDescription, privacy: .private)"
                )
                let fileName = item(withID: snapshot.documentID)?
                    .url?.lastPathComponent ?? ui("这份笔记", "this note")
                let message = ui(
                    "“\(fileName)”的恢复点尚未安全保存。内容仍在本次会话中，请不要关闭并重试。",
                    "The recovery point for \(fileName) is not safely stored yet. The content remains in this session; do not close it, and retry."
                )
                setNoteFileError(message, for: snapshot.documentID)
                showImportantOperationError(message)
            }
        }
        if noteEditorRecoveryConflictsByItemID[snapshot.documentID] != nil
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
            marksSessionSaved: revision != nil,
            status: .writtenToFile
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
        completeNoteEditorSave(
            receipt,
            marksSessionSaved: true,
            status: .savedInWeiBei
        )
    }

    func noteEditorWorkspaceSaveFailed(_ message: String) {
        let documentID = noteEditingSession.documentID
        guard noteEditingSession.dirty,
              item(withID: documentID)?.editsBackingMarkdownFile == false else { return }
        noteEditingSession.markSaveFailed(documentID: documentID)
        showImportantOperationError(message)
    }

    private func completeNoteEditorSave(
        _ receipt: NoteEditorSaveReceipt,
        marksSessionSaved: Bool,
        status: NoteSaveStatus
    ) {
        Task {
            do {
                _ = try await noteRecoveryStore.removeIfCheckpointMatches(
                    documentID: receipt.documentID,
                    checkpointDigest: receipt.digest
                )
            } catch {
                WeiBeiLog.noteRepair.error(
                    "code=note_recovery_cleanup_failed document=\(receipt.documentID, privacy: .private) reason=\(error.localizedDescription, privacy: .private)"
                )
            }
        }
        guard marksSessionSaved,
              noteEditingSession.documentID == receipt.documentID else { return }
        _ = noteEditingSession.markSaved(
            revision: receipt.revision,
            as: status
        )
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
                noteEditingSession.markExternallyModified(documentID: documentID)
                cancelPendingNotePersistence(for: documentID)
                pendingNotePersistenceByItemID.removeValue(forKey: documentID)
                noteEditorRecoveryConflict = NoteEditorRecoveryConflict(
                    diskMarkdown: diskMarkdown,
                    checkpoint: checkpoint,
                    checkpointIsPersisted: true
                )
            case .none:
                let diskDigest = Self.noteContentDigest(data)
                let baseDigest = latestNoteEditorSnapshot.flatMap {
                    $0.documentID == documentID ? $0.baseDigest : nil
                } ?? noteEditorBaseDigest(for: documentID)
                if baseDigest == diskDigest {
                    _ = await freshActiveNoteEditorSnapshot()
                } else {
                    noteEditingSession.markExternallyModified(documentID: documentID)
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
                checkpoint: checkpoint,
                checkpointIsPersisted: true
            )
            return
        case .none, .stale, .damaged:
            break
        }

        let previousDigest = Self.noteContentDigest(Data(noteText.utf8))
        let diskChanged = previousDigest != Self.noteContentDigest(
            Data(diskMarkdown.utf8)
        )
        refreshActiveNoteFromBackingFile()
        guard diskChanged else { return }
        noteEditingSession.markExternallyModified(documentID: documentID)
        guard previousDigest != Self.noteContentDigest(Data(noteText.utf8)) else { return }
        noteEditingSession.replaceDocument(with: item.id)
        noteEditingSession.markExternallyModified(documentID: documentID)
        noteEditorCommand = NoteEditorCommand(
            kind: .reloadDocument,
            markdown: noteText
        )
    }

    func resolveNoteEditorRecoveryConflict(useDisk: Bool) async {
        guard let conflict = noteEditorRecoveryConflict else { return }
        if useDisk {
            let documentID = conflict.checkpoint.metadata.documentID
            let fileURL = item(withID: documentID)?.url
            let fileName = fileURL?.lastPathComponent
                ?? ui("这份笔记", "this note")
            do {
                _ = try NoteBackupRing.capture(
                    content: Data(conflict.checkpoint.markdown.utf8),
                    itemID: documentID,
                    rootURL: noteBackupRootURL
                )
            } catch {
                WeiBeiLog.noteRepair.error(
                    "code=note_conflict_backup_failed path=\(fileURL?.path ?? documentID, privacy: .private) reason=\(error.localizedDescription, privacy: .private)"
                )
                showImportantOperationError(conflict.checkpointIsPersisted
                    ? ui(
                        "暂时无法采用“\(fileName)”的磁盘版本。未写内容已保存在魏碑中，请重试。",
                        "Could not use the disk version of \(fileName). Unsaved content is stored in WeiBei; please retry."
                    )
                    : ui(
                        "暂时无法采用“\(fileName)”的磁盘版本。未写内容仍在本次会话中，但尚未安全保存；请不要关闭并重试。",
                        "Could not use the disk version of \(fileName). Unsaved content remains in this session but is not safely stored yet; do not close it, and retry."
                    ))
                return
            }
            cancelPendingNotePersistence(for: documentID)
            pendingNotePersistenceByItemID.removeValue(forKey: documentID)
            noteEditorRecoveryConflictsByItemID.removeValue(forKey: documentID)
            setNoteDraft(nil, for: documentID)
            setNoteFileError(nil, for: documentID)
            dismissImportantOperationError()
            let remainsActive = documentID == activeNoteEditorDocumentID
            if remainsActive { noteText = conflict.diskMarkdown }
            let digest = Self.noteContentDigest(Data(conflict.diskMarkdown.utf8))
            noteBackingContentDigestsByItemID[documentID] = digest
            loadedCourseNoteTextByItemID[documentID] = conflict.diskMarkdown
            if remainsActive {
                latestNoteEditorSnapshot = nil
                noteEditingSession.replaceDocument(with: documentID)
                noteEditorCommand = NoteEditorCommand(
                    kind: .reloadDocument,
                    markdown: conflict.diskMarkdown
                )
            }
            guard await persistWorkspaceNow() else {
                noteEditingSession.markSaveFailed(documentID: documentID)
                let message = ui(
                    "已采用“\(fileName)”的磁盘版本，但魏碑尚未确认清理旧草稿。未写内容已有备份，请重试保存后再关闭。",
                    "The disk version of \(fileName) is in use, but WeiBei has not confirmed removal of the old draft. The unsaved content has a backup; retry saving before closing."
                )
                setNoteFileError(message, for: documentID)
                showImportantOperationError(message)
                return
            }
            do {
                try await noteRecoveryStore.remove(documentID: documentID)
            } catch {
                WeiBeiLog.noteRepair.error(
                    "code=note_recovery_cleanup_failed document=\(documentID, privacy: .private) reason=\(error.localizedDescription, privacy: .private)"
                )
                let message = ui(
                    "已采用“\(fileName)”的磁盘正文，但旧恢复点清理未完成。未写内容已有备份；请重试保存。",
                    "The disk text for \(fileName) is in use, but the old recovery point was not removed. The unsaved content has a backup; retry saving."
                )
                setNoteFileError(message, for: documentID)
                showImportantOperationError(message)
                return
            }
            showTransientNoteStatus(ui(
                "已采用“\(fileName)”的磁盘版本；未写内容已保存在魏碑备份中。",
                "Used the disk version of \(fileName); unsaved content was kept in a WeiBei backup."
            ))
        } else {
            let documentID = conflict.checkpoint.metadata.documentID
            guard let fileURL = item(withID: documentID)?.url else { return }
            let fileName = fileURL.lastPathComponent
            setNoteDraft(conflict.checkpoint.markdown, for: documentID)
            let draftPersisted = flushPendingWorkspaceSave()
            var recoveryPersisted = conflict.checkpointIsPersisted
            do {
                let diskData = try Data(contentsOf: fileURL)
                _ = try NoteBackupRing.capture(
                    content: diskData,
                    itemID: documentID,
                    rootURL: noteBackupRootURL
                )
                let diskDigest = Self.noteContentDigest(diskData)
                _ = try await noteRecoveryStore.store(
                    documentID: documentID,
                    baseFileDigest: diskDigest,
                    revision: conflict.checkpoint.metadata.revision,
                    markdown: conflict.checkpoint.markdown
                )
                recoveryPersisted = true
                try writeNotebookMarkdownThroughGate(
                    conflict.checkpoint.markdown,
                    itemID: documentID,
                    url: fileURL,
                    expectedBaseline: diskDigest
                )
            } catch {
                noteEditingSession.markExternallyModified(documentID: documentID)
                WeiBeiLog.noteRepair.error(
                    "code=note_conflict_restore_failed path=\(fileURL.path, privacy: .private) reason=\(error.localizedDescription, privacy: .private)"
                )
                showImportantOperationError(draftPersisted || recoveryPersisted
                    ? ui(
                        "暂时无法恢复“\(fileName)”中的魏碑内容。待写内容和冲突已保存在魏碑中，请重试。",
                        "Could not restore WeiBei content to \(fileName). The unsaved content and conflict are stored in WeiBei; please retry."
                    )
                    : ui(
                        "暂时无法恢复“\(fileName)”中的魏碑内容。待写内容仍在当前编辑中，但尚未安全保存；请不要关闭并重试。",
                        "Could not restore WeiBei content to \(fileName). The unsaved content remains in the current editor but is not safely stored yet; do not close it, and retry."
                    ))
                return
            }
            noteEditorRecoveryConflictsByItemID.removeValue(forKey: documentID)
            setNoteDraft(nil, for: documentID)
            setNoteFileError(nil, for: documentID)
            dismissImportantOperationError()
            loadedCourseNoteTextByItemID[documentID] = conflict.checkpoint.markdown
            let remainsActive = documentID == activeNoteEditorDocumentID
            if remainsActive {
                noteText = conflict.checkpoint.markdown
                noteEditingSession.replaceDocument(
                    with: documentID,
                    initialRevision: conflict.checkpoint.metadata.revision
                )
                latestNoteEditorSnapshot = (
                    documentID,
                    conflict.checkpoint.metadata.checkpointDigest,
                    conflict.checkpoint.metadata.checkpointDigest,
                    conflict.checkpoint.metadata.revision
                )
                noteEditorDidPersist(
                    conflict.checkpoint.markdown,
                    documentID: documentID
                )
                noteEditorCommand = NoteEditorCommand(
                    kind: .reloadDocument,
                    markdown: conflict.checkpoint.markdown
                )
            }
            guard await persistWorkspaceNow() else {
                noteEditingSession.markSaveFailed(documentID: documentID)
                let message = ui(
                    "“\(fileName)”的正文已写入文件，但魏碑尚未确认清理旧草稿。请重试保存后再关闭。",
                    "The text was written to \(fileName), but WeiBei has not confirmed removal of the old draft. Retry saving before closing."
                )
                setNoteFileError(message, for: documentID)
                showImportantOperationError(message)
                return
            }
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
