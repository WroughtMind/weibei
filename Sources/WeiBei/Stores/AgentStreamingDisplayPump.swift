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
    /// Lag (in characters) that adds one extra character per tick of pace, so
    /// the rate ramps continuously with backlog instead of jumping between
    /// integer step sizes.
    static let rampLagCharacters: Double = 10.0
    /// Hard ceiling on characters per tick so huge backlogs drain as a fast
    /// but readable rush instead of an instant dump.
    static let maximumCharsPerTick = 12

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
    /// Fractional pacing credit carried between ticks so non-integer rates
    /// (e.g. 1.5 characters per tick) render as an even character flow.
    /// Clamped to ≤1 after each emit so stale credit cannot burst later.
    private var pacingCredit = 0.0

    init(hooks: Hooks) {
        self.hooks = hooks
    }

    var isRunning: Bool { task != nil }

    /// Idempotent. Steps once immediately so the first character keeps its
    /// historical published-on-arrival latency, then keeps ticking on
    /// absolute deadlines so MainActor congestion cannot accumulate drift.
    func start() {
        guard task == nil else { return }
        stepOnce()
        task = Task { @MainActor [weak self] in
            var nextTick = DispatchTime.now().uptimeNanoseconds &+ Self.tickNanoseconds
            while !Task.isCancelled {
                guard let self else { return }
                self.stepOnce()
                let now = DispatchTime.now().uptimeNanoseconds
                if nextTick <= now {
                    nextTick = now &+ Self.tickNanoseconds
                } else {
                    try? await Task.sleep(nanoseconds: nextTick - now)
                }
                nextTick &+= Self.tickNanoseconds
            }
        }
    }

    /// Cancels the loop and forgets the current run. Callers own the rest of
    /// the streaming-state cleanup around the request lifecycle.
    func stopAndReset() {
        task?.cancel()
        task = nil
        displayedPrefix = ""
        pacingCredit = 0
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
            pacingCredit = 0
            hooks.publish(target)
            return
        }
        let deficit = target.count - displayedPrefix.count
        guard deficit > 0 else { return }
        // One character per tick plus a continuous ramp with lag: near target
        // this is plain single-character typing; sustained backlog settles at
        // a constant fractional rate that the credit renders evenly.
        let charsPerTick = min(
            Double(Self.maximumCharsPerTick),
            1.0 + Double(deficit) / Self.rampLagCharacters
        )
        pacingCredit += charsPerTick
        let step = min(deficit, Int(pacingCredit.rounded(.down)))
        pacingCredit -= Double(step)
        if pacingCredit > 1 { pacingCredit = 1 }
        let newIndex = target.index(
            target.startIndex,
            offsetBy: displayedPrefix.count + step,
            limitedBy: target.endIndex
        ) ?? target.endIndex
        displayedPrefix = String(target[..<newIndex])
        hooks.publish(displayedPrefix)
    }
}
