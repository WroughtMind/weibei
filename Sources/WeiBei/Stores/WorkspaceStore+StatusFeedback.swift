import Foundation
import WeiBeiCore

enum PendingDeletionUndo {
    case selectionAsk(thread: SelectionAskThread, session: StudySession?)
    case excerpt(record: SelectionRemarkRecord, index: Int)
}

private let inspirationAsWatermarkDefaultsKey = "weibei.dailyInspiration.watermark"

/// Transient/important feedback and small settings setters, kept separate
/// from workspace orchestration as their own responsibility.
@MainActor
extension WorkspaceStore {
    func setMotionPreference(_ preference: WeiBeiMotionPreference) {
        guard motionPreference != preference else { return }
        motionPreference = preference
        selectionAskThreadDefaults.set(
            preference.rawValue,
            forKey: WeiBeiMotionPreference.persistedDefaultsKey
        )
    }

    func setDailyInspirationEnabled(_ enabled: Bool) {
        guard showDailyInspiration != enabled else { return }
        showDailyInspiration = enabled
        save()
    }

    /// Paper-watermark presentation for the daily line. Defaults-backed app
    /// preference kept with the rest of the small settings responsibility;
    /// the manual objectWillChange keeps @EnvironmentObject views in sync.
    var inspirationAsWatermark: Bool {
        get { selectionAskThreadDefaults.bool(forKey: inspirationAsWatermarkDefaultsKey) }
        set {
            selectionAskThreadDefaults.set(newValue, forKey: inspirationAsWatermarkDefaultsKey)
            objectWillChange.send()
        }
    }

    func setInspirationAsWatermark(_ enabled: Bool) {
        guard inspirationAsWatermark != enabled else { return }
        inspirationAsWatermark = enabled
    }

    func undoPendingDeletion() {
        guard let pending = pendingDeletionUndo else { return }
        pendingDeletionUndo = nil
        transientNoteStatusTask?.cancel()
        transientNoteStatus = nil
        transientNoteStatusRevealURL = nil
        switch pending {
        case let .selectionAsk(thread, session):
            if !selectionAskThreads.contains(where: { $0.id == thread.id }) {
                selectionAskThreads.insert(thread, at: 0)
            }
            if let session, !studySessions.contains(where: { $0.id == session.id }) {
                studySessions.append(session)
                sessionMessagePersistence.markLoaded(session.id)
            }
        case let .excerpt(record, index):
            guard !selectionRemarkRecords.contains(where: { $0.id == record.id }) else { break }
            selectionRemarkRecords.insert(record, at: min(index, selectionRemarkRecords.count))
        }
        save()
    }

    func armDeletionUndo(_ undo: PendingDeletionUndo) {
        pendingDeletionUndo = undo
        transientNoteStatusGeneration += 1
        let generation = transientNoteStatusGeneration
        transientNoteStatusTask?.cancel()
        transientNoteStatus = ui("已删除", "Deleted")
        transientNoteStatusRevealURL = nil
        transientNoteStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.transientNoteStatusGeneration == generation else { return }
            self.transientNoteStatus = nil
            self.transientNoteStatusRevealURL = nil
            self.pendingDeletionUndo = nil
        }
    }

    func showTransientNoteStatus(_ message: String, revealURL: URL? = nil) {
        // S5: sole transient feedback channel (auto-expires). Identity is the
        // generation, not the text — the same sentence shown twice still gets its
        // own full 2.4s window, and only the newest generation may clear the slot.
        // A Finder reveal stays until replaced, so the backup location remains reachable.
        transientNoteStatusGeneration += 1
        let generation = transientNoteStatusGeneration
        transientNoteStatusTask?.cancel()
        transientNoteStatus = message
        transientNoteStatusRevealURL = revealURL
        guard revealURL == nil else { return }
        transientNoteStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.transientNoteStatusGeneration == generation else { return }
            self.transientNoteStatus = nil
            self.transientNoteStatusRevealURL = nil
        }
    }

    func dismissTransientNoteStatus() {
        transientNoteStatusGeneration += 1
        transientNoteStatusTask?.cancel()
        transientNoteStatus = nil
        transientNoteStatusRevealURL = nil
    }

    func showImportantOperationError(_ message: String) {
        importantOperationNotice = nil
        importantOperationError = message
    }

    /// 带 notice 的重载:横幅文案照旧由失败现场生成,同时记录类型化身份供按语义断言。
    func showImportantOperationError(_ notice: ImportantOperationNotice, message: String) {
        importantOperationNotice = notice
        importantOperationError = message
    }

    func dismissImportantOperationError() {
        importantOperationNotice = nil
        importantOperationError = nil
    }

    /// 工作区快照失败为 failed；笔记 debounce 未落盘为 pending；其余为 saved。
    var lastPersistState: WorkspacePersistState {
        if workspaceSaveFailure != nil {
            return .failed
        }
        if !pendingNotePersistenceByItemID.isEmpty {
            return .pending
        }
        return .saved
    }
}
