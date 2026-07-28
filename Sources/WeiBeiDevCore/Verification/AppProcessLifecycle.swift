import Darwin
import Foundation

/// 描述一次独立验收场景的应用启动参数。
public struct VerificationAppLaunchConfiguration: Sendable {
    public let executableURL: URL
    public let workingDirectoryURL: URL
    public let environment: [String: String]
    public let stdoutURL: URL
    public let stderrURL: URL
    public let startupProbeDelaySeconds: TimeInterval

    /// 创建应用启动配置。
    public init(
        executableURL: URL,
        workingDirectoryURL: URL,
        environment: [String: String],
        stdoutURL: URL,
        stderrURL: URL,
        startupProbeDelaySeconds: TimeInterval = 0.1
    ) {
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
        self.environment = environment
        self.stdoutURL = stdoutURL
        self.stderrURL = stderrURL
        self.startupProbeDelaySeconds = startupProbeDelaySeconds
    }
}

/// 暴露验收运行器定位窗口所需的应用进程状态。
public protocol VerificationRunningApp: AnyObject, Sendable {
    /// 应用进程标识。
    var processIdentifier: pid_t { get }

    /// 应用当前是否仍在运行。
    var isRunning: Bool { get }
}

/// 表示由验证核心拥有并负责清理的应用进程。
public final class RunningVerificationApp: VerificationRunningApp, @unchecked Sendable {
    private let process: Process
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private let lock = NSLock()
    private var handlesClosed = false

    /// 应用进程标识。
    public var processIdentifier: pid_t {
        process.processIdentifier
    }

    /// 应用当前是否仍在运行。
    public var isRunning: Bool {
        process.isRunning
    }

    /// Creates a running-app handle that owns its redirected log descriptors.
    fileprivate init(process: Process, stdoutHandle: FileHandle, stderrHandle: FileHandle) {
        self.process = process
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle
    }

    /// Terminates only this managed PID and escalates after the grace period.
    fileprivate func terminate(graceSeconds: TimeInterval, waiter: any VerificationWaiting) {
        guard process.isRunning else {
            closeHandles()
            return
        }
        process.terminate()
        let deadline = Date().addingTimeInterval(graceSeconds)
        while process.isRunning, Date() < deadline {
            waiter.wait(seconds: 0.05)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        closeHandles()
    }

    /// Closes scenario log handles exactly once after the process finishes.
    fileprivate func closeHandles() {
        lock.lock()
        defer { lock.unlock() }
        guard !handlesClosed else {
            return
        }
        handlesClosed = true
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
        closeHandles()
    }
}

/// 管理验收应用的启动和确定性清理。
public protocol VerificationAppManaging: Sendable {
    /// 启动应用，并在进程立即退出时抛出全局启动错误。
    func launch(configuration: VerificationAppLaunchConfiguration) throws -> any VerificationRunningApp

    /// 终止由当前验收场景启动的应用。
    func stop(_ app: any VerificationRunningApp)
}

/// 使用 Foundation `Process` 管理验收应用。
public struct FoundationVerificationAppManager: VerificationAppManaging {
    private let waiter: any VerificationWaiting
    private let terminationGraceSeconds: TimeInterval

    /// 创建生产应用进程管理器。
    public init(
        waiter: any VerificationWaiting = SystemVerificationWaiter(),
        terminationGraceSeconds: TimeInterval = 2
    ) {
        self.waiter = waiter
        self.terminationGraceSeconds = terminationGraceSeconds
    }

    /// 直接执行应用二进制并将输出写入场景 artifacts。
    public func launch(configuration: VerificationAppLaunchConfiguration) throws -> any VerificationRunningApp {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: configuration.executableURL.path) else {
            throw VerificationError(
                code: "app_not_executable",
                message: "Verification app is missing or not executable: \(configuration.executableURL.path)"
            )
        }
        try fileManager.createDirectory(
            at: configuration.stdoutURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.createFile(atPath: configuration.stdoutURL.path, contents: nil),
              fileManager.createFile(atPath: configuration.stderrURL.path, contents: nil) else {
            throw VerificationError(code: "artifact_creation_failed", message: "Unable to create app log files.")
        }

        let stdoutHandle = try FileHandle(forWritingTo: configuration.stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: configuration.stderrURL)
        let process = Process()
        process.executableURL = configuration.executableURL
        process.currentDirectoryURL = configuration.workingDirectoryURL
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, scenarioValue in
            scenarioValue
        }

        do {
            try process.run()
        } catch {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            throw VerificationError(code: "app_launch_failed", message: error.localizedDescription)
        }

        let runningApp = RunningVerificationApp(
            process: process,
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle
        )
        waiter.wait(seconds: configuration.startupProbeDelaySeconds)
        guard runningApp.isRunning else {
            runningApp.closeHandles()
            let stderr = (try? String(contentsOf: configuration.stderrURL, encoding: .utf8)) ?? ""
            throw VerificationError(
                code: "app_exited_early",
                message: stderr.isEmpty ? "Verification app exited immediately." : stderr
            )
        }
        return runningApp
    }

    /// 先发送终止信号，超时后仅强制清理由本管理器启动的 PID。
    public func stop(_ app: any VerificationRunningApp) {
        guard let app = app as? RunningVerificationApp else {
            return
        }
        app.terminate(graceSeconds: terminationGraceSeconds, waiter: waiter)
    }
}
