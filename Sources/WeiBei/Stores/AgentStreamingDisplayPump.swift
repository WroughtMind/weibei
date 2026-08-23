import Foundation

/// Meters accumulated agent streaming text onto the display surface at an
/// even, typewriter-like cadence.
///
/// The real text keeps accumulating in the store (`latestAgentStreamingText`);
/// only the display prefix published through `agentStreaming.text` is paced
/// here, so network burstiness never reaches the chat surface while
/// persistence, completion, and interruption keep reading the full text.
@MainActor
final class AgentStreamingDisplayPump {
    /// Tick interval; matches the historical 33 ms streaming publish gate (~30 Hz).
    static let tickNanoseconds: UInt64 = 33_000_000
    /// One fixed amount per tick keeps network backlog from changing the
    /// visible typing speed. 4/tick ≈ 120 chars/s keeps up with normal replies.
    static let charactersPerTick = 4

    struct Hooks {
        let targetText: @MainActor () -> String
        let publish: @MainActor (String) -> Void
        let canPublish: @MainActor () -> Bool
    }

    private let hooks: Hooks
    private var task: Task<Void, Never>?
    /// Prefix of the target published so far in this run. Only advances while
    /// the target keeps it as a prefix; anomalies snap straight to full text.
    private var displayedPrefix = ""

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    var isRunning: Bool { task != nil }

    /// Idempotent. Steps once immediately so the first character keeps its
    /// historical published-on-arrival latency, then waits one full tick before
    /// the next publish so startup cannot emit two batches in the same frame.
    func start() {
        guard task == nil else { return }
        stepOnce()
        task = Task { @MainActor [weak self] in
            var nextTick = DispatchTime.now().uptimeNanoseconds &+ Self.tickNanoseconds
            while !Task.isCancelled {
                guard let self else { return }
                let now = DispatchTime.now().uptimeNanoseconds
                if nextTick > now {
                    try? await Task.sleep(nanoseconds: nextTick - now)
                }
                guard !Task.isCancelled else { return }
                self.stepOnce()
                nextTick &+= Self.tickNanoseconds
                let afterStep = DispatchTime.now().uptimeNanoseconds
                if nextTick <= afterStep {
                    nextTick = afterStep &+ Self.tickNanoseconds
                }
            }
        }
    }

    /// Cancels the loop and forgets the current run. Callers own the rest of
    /// the streaming-state cleanup around the request lifecycle.
    func stopAndReset() {
        task?.cancel()
        task = nil
        displayedPrefix = ""
    }

    /// Keeps the message in its generating state until the already-running
    /// fixed-rate loop has displayed every streamed character.
    func waitUntilCaughtUp() async {
        while !Task.isCancelled,
              hooks.canPublish(),
              displayedPrefix != hooks.targetText() {
            try? await Task.sleep(nanoseconds: Self.tickNanoseconds)
        }
    }

    /// Advances the display prefix by one tick. Exposed for deterministic tests.
    func stepOnce() {
        let target = hooks.targetText()
        guard !target.isEmpty else { return }
        // Hidden chat: no UI work; once shown again the deficit path catches up.
        guard hooks.canPublish() else { return }
        guard target.hasPrefix(displayedPrefix) else {
            // Non-append anomaly (rewrite or stale run): never stall on it.
            displayedPrefix = target
            hooks.publish(target)
            return
        }
        let deficit = target.count - displayedPrefix.count
        guard deficit > 0 else { return }
        let step = min(deficit, Self.charactersPerTick)
        let newIndex = target.index(
            target.startIndex,
            offsetBy: displayedPrefix.count + step,
            limitedBy: target.endIndex
        ) ?? target.endIndex
        displayedPrefix = String(target[..<newIndex])
        hooks.publish(displayedPrefix)
    }
}
