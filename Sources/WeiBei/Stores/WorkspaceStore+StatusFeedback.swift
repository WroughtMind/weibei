import Foundation
import WeiBeiCore

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
