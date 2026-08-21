import Foundation

/// Admission control for cold-mounting Chat markdown WebKit renderers.
///
/// Opening a historical Chat eagerly mounts up to one page of message rows, and
/// every finalized assistant row boots its own WKWebView (roughly a megabyte of
/// editor JavaScript). Booting them all at once starved the rows actually on
/// screen, so the conversation showed the unstyled native-Markdown fallback for
/// seconds before the rich renderers caught up. The queue admits a bounded
/// number of concurrent cold boots, currently-visible rows first, and frees
/// each slot when its row reports that the renderer settled (first accepted
/// measurement, render failure, or teardown). Slots whose rows never report
/// back are reclaimed by a timeout so one hung WebView cannot pin the queue.
@MainActor
public final class AgentChatMarkdownBootQueue {

    public static let shared = AgentChatMarkdownBootQueue()

    public let concurrentBootLimit: Int
    public let slotTimeout: TimeInterval

    /// Rows that currently hold a boot slot. Observed through
    /// `setAdmissionObserver` so the app target can republish to SwiftUI
    /// without WeiBeiCore depending on Combine.
    public private(set) var admittedIDs: Set<UUID> = []

    private struct PendingRequest {
        var visible: Bool
        var sequence: Int
    }

    private var pending: [UUID: PendingRequest] = [:]
    private var activeSince: [UUID: Date] = [:]
    private var nextSequence = 0
    private var admissionObserver: ((Set<UUID>) -> Void)?
    private var watchdogTimer: Timer?

    public init(concurrentBootLimit: Int = 4, slotTimeout: TimeInterval = 12) {
        self.concurrentBootLimit = max(1, concurrentBootLimit)
        self.slotTimeout = max(1, slotTimeout)
    }

    /// Register (or refresh) one row's boot request. Re-requesting is
    /// idempotent; a visibility change re-prioritizes a still-pending row but
    /// never demotes a row that already holds a slot.
    public func requestBootSlot(id: UUID, visible: Bool) {
        if admittedIDs.contains(id) { return }
        if let existing = pending[id] {
            guard existing.visible != visible else { return }
            pending[id] = PendingRequest(visible: visible, sequence: existing.sequence)
            admitNextRows()
            return
        }
        pending[id] = PendingRequest(visible: visible, sequence: nextSequence)
        nextSequence &+= 1
        admitNextRows()
    }

    public func isAdmitted(_ id: UUID) -> Bool {
        admittedIDs.contains(id)
    }

    /// Cancel a pending request, or free an admitted slot once the row's
    /// renderer settled or the row left the hierarchy.
    public func release(_ id: UUID) {
        let wasPending = pending.removeValue(forKey: id) != nil
        let wasActive = activeSince.removeValue(forKey: id) != nil
        guard wasPending || wasActive else { return }
        if wasActive, admittedIDs.remove(id) != nil {
            admissionObserver?(admittedIDs)
        }
        admitNextRows()
    }

    /// Reclaim slots whose renderers never settled. Public so the watchdog and
    /// tests drive the same deterministic path.
    public func reclaimOverdueSlots(asOf now: Date = Date()) {
        let overdueIDs = activeSince
            .filter { now.timeIntervalSince($0.value) > slotTimeout }
            .map(\.key)
        guard !overdueIDs.isEmpty else { return }
        for id in overdueIDs {
            release(id)
        }
    }

    public func setAdmissionObserver(_ observer: ((Set<UUID>) -> Void)?) {
        admissionObserver = observer
    }

    /// Visible rows outrank offscreen rows; equal priority keeps request order.
    private func admitNextRows() {
        var admitted = false
        while activeSince.count < concurrentBootLimit, !pending.isEmpty {
            guard let best = pending.min(by: { lhs, rhs in
                let lhsRank = (visible: lhs.value.visible, sequence: lhs.value.sequence)
                let rhsRank = (visible: rhs.value.visible, sequence: rhs.value.sequence)
                if lhsRank.visible != rhsRank.visible {
                    return lhsRank.visible
                }
                return lhsRank.sequence < rhsRank.sequence
            }) else { break }
            pending.removeValue(forKey: best.key)
            activeSince[best.key] = Date()
            admittedIDs.insert(best.key)
            admitted = true
        }
        if admitted {
            admissionObserver?(admittedIDs)
        }
        scheduleWatchdogIfNeeded()
    }

    private func scheduleWatchdogIfNeeded() {
        guard !activeSince.isEmpty else {
            watchdogTimer?.invalidate()
            watchdogTimer = nil
            return
        }
        guard watchdogTimer == nil else { return }
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reclaimOverdueSlots()
                if self.activeSince.isEmpty {
                    self.watchdogTimer?.invalidate()
                    self.watchdogTimer = nil
                }
            }
        }
    }
}
