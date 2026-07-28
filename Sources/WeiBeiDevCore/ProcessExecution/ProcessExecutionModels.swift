import Foundation

/// Abstraction used by development workflows to run external executables.
public protocol ProcessExecuting: Sendable {
    /// Executes one process without invoking a shell.
    ///
    /// Configuration or launch failures are thrown. Once a process has started,
    /// its exit, signal, timeout, or cancellation is represented in the result.
    func execute(_ request: ProcessExecutionRequest) async throws -> ProcessExecutionResult
}

/// Environment construction policy for a child process.
public enum ProcessEnvironment: Sendable, Equatable {
    /// Inherits the development tool's complete environment.
    case inherit

    /// Replaces the environment with exactly the supplied values.
    case replace([String: String])

    /// Inherits the current environment and overwrites the supplied keys.
    case inheritAndOverride([String: String])
}

/// Standard-input source for a child process.
public enum ProcessStandardInput: Sendable, Equatable {
    /// Inherits standard input from the development tool.
    case inherit

    /// Connects standard input to `/dev/null`.
    case null

    /// Writes the supplied data and then closes standard input.
    case data(Data)
}

/// Standard-output or standard-error destination for a child process.
public enum ProcessOutputDestination: Sendable, Equatable {
    /// Inherits the matching file descriptor from the development tool.
    case inherit

    /// Discards all bytes while continuing to drain the stream.
    case discard

    /// Captures at most `limit` bytes while counting and draining all output.
    case capture(limit: Int)
}

/// Complete configuration for one external process invocation.
public struct ProcessExecutionRequest: Sendable, Equatable {
    /// Absolute executable URL passed directly to `Foundation.Process`.
    public let executableURL: URL

    /// Arguments passed directly to the executable without shell parsing.
    public let arguments: [String]

    /// Optional child working directory.
    public let workingDirectoryURL: URL?

    /// Child environment construction policy.
    public let environment: ProcessEnvironment

    /// Standard-input source.
    public let standardInput: ProcessStandardInput

    /// Standard-output destination.
    public let standardOutput: ProcessOutputDestination

    /// Standard-error destination.
    public let standardError: ProcessOutputDestination

    /// Optional maximum execution time.
    public let timeout: Duration?

    /// Time allowed for graceful termination before sending `SIGKILL`.
    public let terminationGracePeriod: Duration

    /// Creates an external process request.
    public init(
        executableURL: URL,
        arguments: [String] = [],
        workingDirectoryURL: URL? = nil,
        environment: ProcessEnvironment = .inherit,
        standardInput: ProcessStandardInput = .null,
        standardOutput: ProcessOutputDestination = .capture(limit: 1_048_576),
        standardError: ProcessOutputDestination = .capture(limit: 1_048_576),
        timeout: Duration? = nil,
        terminationGracePeriod: Duration = .seconds(2)
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
        self.environment = environment
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timeout = timeout
        self.terminationGracePeriod = terminationGracePeriod
    }
}

/// Immutable command identity retained in execution results and reports.
public struct ProcessCommand: Sendable, Equatable, Codable {
    /// Absolute executable URL used for the invocation.
    public let executableURL: URL

    /// Arguments passed directly to the executable.
    public let arguments: [String]

    /// Optional child working directory.
    public let workingDirectoryURL: URL?

    /// Creates a command identity from a process request.
    public init(executableURL: URL, arguments: [String], workingDirectoryURL: URL?) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectoryURL = workingDirectoryURL
    }
}

/// Captured bytes and truncation metadata for one output stream.
public struct CapturedProcessOutput: Sendable, Equatable {
    /// Captured prefix, limited by the request's configured byte limit.
    public let data: Data

    /// Total bytes emitted before truncation.
    public let totalByteCount: Int

    /// Whether emitted output exceeded the captured prefix.
    public let isTruncated: Bool

    /// Captured output decoded as UTF-8, replacing malformed byte sequences.
    public var stringUTF8: String {
        String(decoding: data, as: UTF8.self)
    }

    /// Creates captured output metadata.
    public init(data: Data, totalByteCount: Int, isTruncated: Bool) {
        self.data = data
        self.totalByteCount = totalByteCount
        self.isTruncated = isTruncated
    }
}

/// Final process outcome after launch.
public enum ProcessTermination: Sendable, Equatable {
    /// The process called `exit` or returned from its entry point.
    case exited(code: Int32)

    /// The operating system terminated the process with a signal.
    case uncaughtSignal(Int32)

    /// The executor terminated the process after its configured deadline.
    case timedOut

    /// Task cancellation requested process termination.
    case cancelled
}

/// Structured result for one launched external process.
public struct ProcessExecutionResult: Sendable, Equatable {
    /// Command identity used by reports and diagnostics.
    public let command: ProcessCommand

    /// Child process identifier assigned by the operating system.
    public let processIdentifier: Int32

    /// Final process outcome.
    public let termination: ProcessTermination

    /// Captured standard output, or `nil` when output was inherited or discarded.
    public let standardOutput: CapturedProcessOutput?

    /// Captured standard error, or `nil` when output was inherited or discarded.
    public let standardError: CapturedProcessOutput?

    /// Monotonic elapsed execution time.
    public let duration: Duration

    /// Whether the child exited normally with status zero.
    public var succeeded: Bool {
        termination == .exited(code: 0)
    }

    /// Normal exit status, or `nil` for signals, timeouts, and cancellation.
    public var exitCode: Int32? {
        guard case let .exited(code) = termination else {
            return nil
        }
        return code
    }

    /// Creates a structured process result.
    public init(
        command: ProcessCommand,
        processIdentifier: Int32,
        termination: ProcessTermination,
        standardOutput: CapturedProcessOutput?,
        standardError: CapturedProcessOutput?,
        duration: Duration
    ) {
        self.command = command
        self.processIdentifier = processIdentifier
        self.termination = termination
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.duration = duration
    }
}

/// Configuration and launch failures raised before a structured result exists.
public enum ProcessExecutionError: Error, Sendable, Equatable {
    /// The executable URL was not an absolute file URL.
    case executableMustBeAbsolute(URL)

    /// The working-directory URL was not an absolute file URL.
    case workingDirectoryMustBeAbsolute(URL)

    /// A capture limit was negative.
    case invalidOutputLimit(Int)

    /// A duration was zero or negative.
    case invalidDuration(name: String)

    /// Foundation failed to launch the configured process.
    case launchFailed(executableURL: URL, description: String)
}
