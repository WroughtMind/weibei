import Foundation

/// Owns the lifecycle of the single foreground agent request.
@MainActor
final class AgentRequestCoordinator {
    private var task: Task<Void, Never>?
    private(set) var requestID: UUID?

    var hasTask: Bool {
        task != nil
    }

    /**
     * Launches the foreground request when no other request is active.
     *
     * @param operation - Request body executed by the task
     * @returns Whether a new task was launched
     */
    @discardableResult
    func launch(_ operation: @escaping () async -> Void) -> Bool {
        guard task == nil else { return false }
        task = Task { [weak self] in
            await operation()
            if self?.requestID == nil {
                self?.task = nil
            }
        }
        return true
    }

    /**
     * Begins the stateful request phase and returns its identity.
     *
     * @returns Newly assigned request identity
     */
    func beginRequest() -> UUID {
        let id = UUID()
        requestID = id
        return id
    }

    /**
     * Checks that an async response still belongs to the active request.
     *
     * @param id - Request identity captured before suspension
     */
    func isCurrent(_ id: UUID) -> Bool {
        requestID == id
    }

    /**
     * Clears lifecycle state only for the matching request.
     *
     * @param id - Completing request identity
     */
    func finish(_ id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        task = nil
    }

    /// Waits for the currently launched request task, if any.
    func waitForCurrentTask() async {
        await task?.value
    }

    /**
     * Cancels the active task and invalidates its identity.
     *
     * @returns Whether any request state was active
     */
    @discardableResult
    func cancel() -> Bool {
        guard task != nil || requestID != nil else { return false }
        task?.cancel()
        task = nil
        requestID = nil
        return true
    }
}
