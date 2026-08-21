import Foundation
import WeiBeiCore

/// Transient/important feedback and small settings setters — split out so
/// WorkspaceStore.swift itself stays within its frozen size budget.
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

    func showTransientNoteStatus(_ message: String) {
        // S5: sole transient feedback channel (auto-expires). Identity is the
        // generation, not the text — the same sentence shown twice still gets its
        // own full 2.4s window, and only the newest generation may clear the slot.
        transientNoteStatusGeneration += 1
        let generation = transientNoteStatusGeneration
        transientNoteStatusTask?.cancel()
        transientNoteStatus = message
        transientNoteStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.transientNoteStatusGeneration == generation else { return }
            self.transientNoteStatus = nil
        }
    }

    func showImportantOperationError(_ message: String) {
        importantOperationError = message
    }

    func dismissImportantOperationError() {
        importantOperationError = nil
    }
}
