import Foundation

/// Keeps the 问 / 摘录 capsule from being cleared by empty PDFKit selection pulses.
///
/// After the reader stops exposing PDFKit's tagged accessibility tree, `PDFView`
/// still draws a live highlight but also emits empty `PDFViewSelectionChanged`
/// (and empty `mouseDown`) reports. Those used to cancel the 60ms debounced
/// real selection, so the capsule never appeared.
public struct PDFSelectionReportGate: Equatable, Sendable {
    public var isTracking = false
    public var lastNonEmptyAt: TimeInterval = 0

    /// Ignore empty reports that arrive just after a real selection.
    public static let emptySuppression: TimeInterval = 0.16

    public init() {}

    public mutating func beginTracking() {
        isTracking = true
    }

    public mutating func endTracking() {
        isTracking = false
    }

    /// Whether this snapshot should be forwarded to `updateSelection`.
    public mutating func shouldPublish(text: String, now: TimeInterval) -> Bool {
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty {
            if isTracking {
                return false
            }
            if lastNonEmptyAt > 0, now - lastNonEmptyAt < Self.emptySuppression {
                return false
            }
            return true
        }
        lastNonEmptyAt = now
        return true
    }
}
