import Foundation

/// The only content pacer for an Agent reply. The store owns the complete
/// answer; this queue owns only the not-yet-visible characters.
@MainActor
final class AgentStreamingDisplayPump {
    static let bufferNanoseconds: UInt64 = 80_000_000
    static let tickNanoseconds: UInt64 = 33_000_000
    static let charactersPerTick = 4
    static let catchUpCharactersPerTick = 6
    static let catchUpBacklogThreshold = 120
    static let normalBacklogThreshold = 40

    struct Hooks {
        let append: @MainActor (String) -> Void
        let replace: @MainActor (String) -> Void
        let didDrain: @MainActor () -> Void
    }

    private let hooks: Hooks
    private var task: Task<Void, Never>?
    private var receivedText = ""
    private var pending: [Character] = []
    private var pendingOffset = 0
    private var inputFinished = false
    private var isCatchingUp = false

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    var isRunning: Bool { task != nil }
    var pendingCharacterCount: Int { pending.count - pendingOffset }

    /// Accepts the cumulative model snapshot once per progress event and adds
    /// only its new suffix to the display queue.
    func enqueue(cumulativeText: String) {
        guard cumulativeText != receivedText else { return }
        guard cumulativeText.hasPrefix(receivedText) else {
            // A provider rewrite is not an append stream. Land its authoritative
            // snapshot once instead of mixing two incompatible queues.
            receivedText = cumulativeText
            pending.removeAll(keepingCapacity: true)
            pendingOffset = 0
            isCatchingUp = false
            task?.cancel()
            task = nil
            hooks.replace(cumulativeText)
            if inputFinished { hooks.didDrain() }
            return
        }

        pending.append(contentsOf: cumulativeText.dropFirst(receivedText.count))
        receivedText = cumulativeText
        scheduleAfterBufferIfNeeded()
    }

    /// Marks data completion without waiting for the visual queue.
    func finish(cumulativeText: String) {
        enqueue(cumulativeText: cumulativeText)
        inputFinished = true
        if pendingCharacterCount == 0 {
            task?.cancel()
            task = nil
            hooks.didDrain()
        }
    }

    /// Reduced-motion mode keeps the same streaming document but skips content
    /// pacing. It does not mark model input complete.
    func replaceImmediately(cumulativeText: String) {
        task?.cancel()
        task = nil
        receivedText = cumulativeText
        pending.removeAll(keepingCapacity: true)
        pendingOffset = 0
        isCatchingUp = false
        hooks.replace(cumulativeText)
        if inputFinished { hooks.didDrain() }
    }

    /// Stopped/new-question paths land the complete text immediately and
    /// retire this visual run.
    func settleImmediately(cumulativeText: String) {
        task?.cancel()
        task = nil
        receivedText = cumulativeText
        pending.removeAll(keepingCapacity: true)
        pendingOffset = 0
        inputFinished = true
        isCatchingUp = false
        hooks.replace(cumulativeText)
        hooks.didDrain()
    }

    func stopAndReset() {
        task?.cancel()
        task = nil
        receivedText = ""
        pending.removeAll(keepingCapacity: true)
        pendingOffset = 0
        inputFinished = false
        isCatchingUp = false
    }

    /// Consumes one normal or gentle-catch-up batch. Exposed for tests.
    func stepOnce() {
        guard pendingCharacterCount > 0 else { return }
        if isCatchingUp {
            if pendingCharacterCount < Self.normalBacklogThreshold {
                isCatchingUp = false
            }
        } else if pendingCharacterCount > Self.catchUpBacklogThreshold {
            isCatchingUp = true
        }
        let step = isCatchingUp
            ? Self.catchUpCharactersPerTick
            : Self.charactersPerTick
        let end = min(pending.count, pendingOffset + step)
        hooks.append(String(pending[pendingOffset..<end]))
        pendingOffset = end
        guard pendingOffset == pending.count else { return }
        pending.removeAll(keepingCapacity: true)
        pendingOffset = 0
        task?.cancel()
        task = nil
        if inputFinished { hooks.didDrain() }
    }

    private func scheduleAfterBufferIfNeeded() {
        guard pendingCharacterCount > 0, task == nil else { return }
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.bufferNanoseconds)
            } catch {
                return
            }
            while !Task.isCancelled {
                guard let self else { return }
                self.stepOnce()
                if self.pendingCharacterCount == 0 {
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: Self.tickNanoseconds)
                } catch {
                    return
                }
            }
        }
    }
}
