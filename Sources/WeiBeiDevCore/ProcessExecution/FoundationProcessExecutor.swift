import Darwin
import Foundation

/// Executes external programs directly through `Foundation.Process`.
///
/// Executable paths and argument arrays are never interpreted by a shell.
public struct FoundationProcessExecutor: ProcessExecuting {
    /// Creates the production process executor.
    public init() {}

    /// Executes one validated request and captures its structured outcome.
    public func execute(_ request: ProcessExecutionRequest) async throws -> ProcessExecutionResult {
        try validate(request)

        let process = Process()
        process.executableURL = request.executableURL
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectoryURL
        if let environment = resolvedEnvironment(request.environment) {
            process.environment = environment
        }

        let inputPipe: Pipe?
        switch request.standardInput {
        case .inherit:
            inputPipe = nil
        case .null:
            inputPipe = nil
            process.standardInput = FileHandle.nullDevice
        case .data:
            let pipe = Pipe()
            inputPipe = pipe
            process.standardInput = pipe
        }

        let outputCapture = configureOutput(request.standardOutput, for: process, isStandardError: false)
        let errorCapture = configureOutput(request.standardError, for: process, isStandardError: true)
        let lifecycle = ProcessLifecycle(process: process, gracePeriod: request.terminationGracePeriod)
        process.terminationHandler = { terminatedProcess in
            lifecycle.processDidTerminate(
                reason: terminatedProcess.terminationReason,
                status: terminatedProcess.terminationStatus
            )
        }

        let clock = ContinuousClock()
        let start = clock.now
        do {
            try process.run()
        } catch {
            outputCapture?.cancelAfterLaunchFailure()
            errorCapture?.cancelAfterLaunchFailure()
            inputPipe?.fileHandleForReading.closeFile()
            inputPipe?.fileHandleForWriting.closeFile()
            throw ProcessExecutionError.launchFailed(
                executableURL: request.executableURL,
                description: String(describing: error)
            )
        }

        lifecycle.processDidLaunch()
        outputCapture?.childDidLaunch()
        errorCapture?.childDidLaunch()

        if case let .data(data) = request.standardInput, let inputPipe {
            inputPipe.fileHandleForReading.closeFile()
            DispatchQueue.global(qos: .utility).async {
                do {
                    try inputPipe.fileHandleForWriting.write(contentsOf: data)
                } catch {
                    // A child may intentionally close stdin before consuming all data.
                }
                inputPipe.fileHandleForWriting.closeFile()
            }
        }

        let timeoutTask: Task<Void, Never>?
        if let timeout = request.timeout {
            timeoutTask = Task {
                do {
                    try await Task.sleep(for: timeout)
                    lifecycle.requestTimeout()
                } catch {
                    // Normal process completion cancels the pending deadline.
                }
            }
        } else {
            timeoutTask = nil
        }

        let termination = await withTaskCancellationHandler {
            await lifecycle.waitForTermination()
        } onCancel: {
            lifecycle.requestCancellation()
        }
        timeoutTask?.cancel()

        if termination == .timedOut || termination == .cancelled {
            outputCapture?.forceFinish()
            errorCapture?.forceFinish()
        }
        let capturedOutput = outputCapture?.finish()
        let capturedError = errorCapture?.finish()
        return ProcessExecutionResult(
            command: ProcessCommand(
                executableURL: request.executableURL,
                arguments: request.arguments,
                workingDirectoryURL: request.workingDirectoryURL
            ),
            processIdentifier: process.processIdentifier,
            termination: termination,
            standardOutput: capturedOutput,
            standardError: capturedError,
            duration: start.duration(to: clock.now)
        )
    }

    /// Rejects unsafe paths, capture limits, and non-positive deadlines before launch.
    private func validate(_ request: ProcessExecutionRequest) throws {
        guard request.executableURL.isFileURL, request.executableURL.path.hasPrefix("/") else {
            throw ProcessExecutionError.executableMustBeAbsolute(request.executableURL)
        }
        if let workingDirectoryURL = request.workingDirectoryURL,
           (!workingDirectoryURL.isFileURL || !workingDirectoryURL.path.hasPrefix("/")) {
            throw ProcessExecutionError.workingDirectoryMustBeAbsolute(workingDirectoryURL)
        }
        for destination in [request.standardOutput, request.standardError] {
            if case let .capture(limit) = destination, limit < 0 {
                throw ProcessExecutionError.invalidOutputLimit(limit)
            }
        }
        if let timeout = request.timeout, timeout <= .zero {
            throw ProcessExecutionError.invalidDuration(name: "timeout")
        }
        if request.terminationGracePeriod <= .zero {
            throw ProcessExecutionError.invalidDuration(name: "terminationGracePeriod")
        }
    }

    /// Resolves environment policy while preserving Foundation's native inheritance behavior.
    private func resolvedEnvironment(_ environment: ProcessEnvironment) -> [String: String]? {
        switch environment {
        case .inherit:
            return nil
        case let .replace(values):
            return values
        case let .inheritAndOverride(overrides):
            return ProcessInfo.processInfo.environment.merging(overrides) { _, override in override }
        }
    }

    /// Connects one child output descriptor to inheritance, null, or bounded capture.
    private func configureOutput(
        _ destination: ProcessOutputDestination,
        for process: Process,
        isStandardError: Bool
    ) -> ProcessOutputCapture? {
        let processKeyPath: ReferenceWritableKeyPath<Process, Any?> = isStandardError
            ? \.standardError
            : \.standardOutput
        switch destination {
        case .inherit:
            return nil
        case .discard:
            process[keyPath: processKeyPath] = FileHandle.nullDevice
            return nil
        case let .capture(limit):
            let capture = ProcessOutputCapture(limit: limit)
            process[keyPath: processKeyPath] = capture.pipe
            capture.startReading()
            return capture
        }
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    let pipe = Pipe()

    private let limit: Int
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var data = Data()
    private var totalByteCount = 0
    private var didReachEnd = false

    /// Creates a bounded process-output capture.
    init(limit: Int) {
        self.limit = limit
    }

    /// Starts continuously draining the pipe so a verbose child cannot deadlock.
    func startReading() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.consume(chunk)
        }
    }

    /// Closes the parent's duplicate write descriptor after a successful launch.
    func childDidLaunch() {
        pipe.fileHandleForWriting.closeFile()
    }

    /// Tears down pipe resources when Process never launched.
    func cancelAfterLaunchFailure() {
        pipe.fileHandleForWriting.closeFile()
        pipe.fileHandleForReading.readabilityHandler = nil
        pipe.fileHandleForReading.closeFile()
    }

    /// Waits for EOF and returns the bounded prefix with total byte metadata.
    func finish() -> CapturedProcessOutput {
        finished.wait()
        pipe.fileHandleForReading.readabilityHandler = nil
        pipe.fileHandleForReading.closeFile()
        return lock.withLock {
            CapturedProcessOutput(
                data: data,
                totalByteCount: totalByteCount,
                isTruncated: totalByteCount > data.count
            )
        }
    }

    /// Stops waiting for EOF when a timed-out process tree retained a pipe descriptor.
    func forceFinish() {
        let shouldSignal = lock.withLock {
            guard !didReachEnd else {
                return false
            }
            didReachEnd = true
            return true
        }
        guard shouldSignal else {
            return
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        pipe.fileHandleForReading.closeFile()
        finished.signal()
    }

    /// Drains one chunk, retaining only the configured prefix.
    private func consume(_ chunk: Data) {
        if chunk.isEmpty {
            let shouldSignal = lock.withLock {
                guard !didReachEnd else {
                    return false
                }
                didReachEnd = true
                return true
            }
            if shouldSignal {
                finished.signal()
            }
            return
        }

        lock.withLock {
            totalByteCount += chunk.count
            let remaining = max(0, limit - data.count)
            if remaining > 0 {
                data.append(chunk.prefix(remaining))
            }
        }
    }
}

private final class ProcessLifecycle: @unchecked Sendable {
    private enum RequestedTermination {
        case timedOut
        case cancelled
    }

    private struct OperatingSystemTermination {
        let reason: Process.TerminationReason
        let status: Int32
    }

    private let process: Process
    private let gracePeriod: Duration
    private let lock = NSLock()
    private var didLaunch = false
    private var requestedTermination: RequestedTermination?
    private var operatingSystemTermination: OperatingSystemTermination?
    private var continuation: CheckedContinuation<ProcessTermination, Never>?
    private var requestedProcessIdentifiers: Set<Int32> = []

    /// Creates lifecycle state for one launched process and its termination grace period.
    init(process: Process, gracePeriod: Duration) {
        self.process = process
        self.gracePeriod = gracePeriod
    }

    /// Records successful launch and honors cancellation that arrived during setup.
    func processDidLaunch() {
        let shouldTerminate = lock.withLock {
            didLaunch = true
            return requestedTermination != nil
        }
        if shouldTerminate {
            terminateRunningProcess()
        }
    }

    /// Records OS termination and resumes the single awaiting task.
    func processDidTerminate(reason: Process.TerminationReason, status: Int32) {
        let continuationAndResult: (CheckedContinuation<ProcessTermination, Never>, ProcessTermination)? = lock.withLock {
            operatingSystemTermination = OperatingSystemTermination(reason: reason, status: status)
            guard let continuation else {
                return nil
            }
            self.continuation = nil
            return (continuation, resolvedTermination(reason: reason, status: status))
        }
        if let (continuation, result) = continuationAndResult {
            continuation.resume(returning: result)
        }
    }

    /// Requests termination with a timeout result.
    func requestTimeout() {
        requestTermination(.timedOut)
    }

    /// Requests termination with a cancellation result.
    func requestCancellation() {
        requestTermination(.cancelled)
    }

    /// Stores the first requested termination and signals a running child.
    private func requestTermination(_ reason: RequestedTermination) {
        let shouldTerminate = lock.withLock {
            guard operatingSystemTermination == nil, requestedTermination == nil else {
                return false
            }
            requestedTermination = reason
            return didLaunch
        }
        if shouldTerminate {
            terminateRunningProcess()
        }
    }

    /// Suspends until Process reports its final termination state.
    func waitForTermination() async -> ProcessTermination {
        await withCheckedContinuation { continuation in
            let immediate: ProcessTermination? = lock.withLock {
                if let operatingSystemTermination {
                    return resolvedTermination(
                        reason: operatingSystemTermination.reason,
                        status: operatingSystemTermination.status
                    )
                }
                self.continuation = continuation
                return nil
            }
            if let immediate {
                continuation.resume(returning: immediate)
            }
        }
    }

    /// Gives explicit timeout or cancellation precedence over the resulting signal.
    private func resolvedTermination(reason: Process.TerminationReason, status: Int32) -> ProcessTermination {
        switch requestedTermination {
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .cancelled
        case nil:
            switch reason {
            case .exit:
                return .exited(code: status)
            case .uncaughtSignal:
                return .uncaughtSignal(status)
            @unknown default:
                return .uncaughtSignal(status)
            }
        }
    }

    /// Sends SIGTERM, then SIGKILL after the configured grace period if needed.
    private func terminateRunningProcess() {
        guard process.isRunning else {
            return
        }
        let processIdentifier = process.processIdentifier
        let descendants = Self.descendantProcessIdentifiers(of: processIdentifier)
        let identifiers = Set(descendants + [processIdentifier])
        lock.withLock {
            requestedProcessIdentifiers.formUnion(identifiers)
        }
        for descendant in descendants.reversed() {
            Darwin.kill(descendant, SIGTERM)
        }
        process.terminate()
        let gracePeriod = gracePeriod
        let lifecycle = self
        Task.detached {
            do {
                try await Task.sleep(for: gracePeriod)
            } catch {
                return
            }
            let remainingIdentifiers = lifecycle.lock.withLock {
                lifecycle.requestedProcessIdentifiers
            }
            for identifier in remainingIdentifiers {
                Darwin.kill(identifier, SIGKILL)
            }
        }
    }

    /// Returns the current descendant process tree without invoking a shell.
    private static func descendantProcessIdentifiers(of root: Int32) -> [Int32] {
        var descendants: [Int32] = []
        var pending = [root]
        var visited: Set<Int32> = [root]

        while let parent = pending.popLast() {
            var capacity = 16
            var children: [Int32] = []
            while true {
                var buffer = [Int32](repeating: 0, count: capacity)
                let count = buffer.withUnsafeMutableBytes { bytes in
                    proc_listchildpids(parent, bytes.baseAddress, Int32(bytes.count))
                }
                guard count > 0 else {
                    children = []
                    break
                }
                if count < capacity {
                    children = Array(buffer.prefix(Int(count)))
                    break
                }
                capacity *= 2
            }
            for child in children where child > 0 && visited.insert(child).inserted {
                descendants.append(child)
                pending.append(child)
            }
        }
        return descendants
    }
}

private extension NSLock {
    /// Executes a closure while holding the lock and always unlocks afterward.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
