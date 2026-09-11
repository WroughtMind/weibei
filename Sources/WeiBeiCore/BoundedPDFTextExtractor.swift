import Darwin
import Foundation

public struct BoundedPDFTextPage: Sendable {
    public var text: String
    public var isPartial: Bool

    public init(text: String, isPartial: Bool) {
        self.text = text
        self.isPartial = isPartial
    }
}

public enum BoundedPDFTextExtractor {
    private final class WorkerOutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var output = Data()
        private var overflowed = false

        func append(_ data: Data, limit: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !overflowed, output.count + data.count <= limit else {
                overflowed = true
                return false
            }
            output.append(data)
            return true
        }

        func load() -> (output: Data, overflowed: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (output, overflowed)
        }
    }

    private final class WorkerTerminationState: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func markTerminated() {
            lock.lock()
            value = true
            lock.unlock()
        }

        func wasTerminated() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct WorkerResponse: Decodable {
        var pages: [WorkerPage]
    }

    private struct WorkerPage: Decodable {
        var pageIndex: Int
        var status: String
        var text: String
    }

    private static let maximumWorkerTimeout: TimeInterval = 3.5
    private static let maximumWorkerResidentBytes: UInt64 = 384 * 1_024 * 1_024
    private static let maximumPagesPerRun = 16
    private static let workerName = "WeiBeiPDFTextWorker"

    public static func page(
        from url: URL,
        pageIndex: Int,
        maximumCharacters: Int
    ) -> BoundedPDFTextPage? {
        pages(
            from: url,
            pageIndexes: [pageIndex],
            maximumCharactersPerPage: maximumCharacters
        )?[pageIndex]
    }

    public static func pages(
        from url: URL,
        pageIndexes: [Int],
        maximumCharactersPerPage: Int,
        timeout: TimeInterval = 3.5
    ) -> [Int: BoundedPDFTextPage]? {
        let requestedIndexes = Array(Set(pageIndexes))
            .filter { $0 >= 0 }
            .sorted()
        guard !Task.isCancelled,
              !requestedIndexes.isEmpty,
              requestedIndexes.count <= maximumPagesPerRun,
              maximumCharactersPerPage > 0,
              maximumCharactersPerPage <= 1_000_000 else { return nil }
        let boundedTimeout = min(max(timeout, 0.1), maximumWorkerTimeout)
        let maximumOutputBytes = requestedIndexes.count * (maximumCharactersPerPage * 6 + 256) + 1_024
        guard let output = runWorker(
            arguments: [
                url.path,
                requestedIndexes.map(String.init).joined(separator: ","),
                String(maximumCharactersPerPage),
            ],
            timeout: boundedTimeout,
            maximumResidentBytes: maximumWorkerResidentBytes,
            maximumOutputBytes: maximumOutputBytes
        ), let response = try? JSONDecoder().decode(WorkerResponse.self, from: output) else { return nil }
        let requestedSet = Set(requestedIndexes)
        return response.pages.reduce(into: [Int: BoundedPDFTextPage]()) { result, page in
            guard requestedSet.contains(page.pageIndex),
                  page.status == "complete" || page.status == "partial" else { return }
            result[page.pageIndex] = BoundedPDFTextPage(
                text: page.text,
                isPartial: page.status == "partial"
            )
        }
    }

#if DEBUG
    public static func runSafetySelfCheck() -> Bool {
        guard runWorker(
            arguments: ["--safety-probe", "normal"],
            timeout: 1,
            maximumResidentBytes: maximumWorkerResidentBytes,
            maximumOutputBytes: 1_024,
            environmentOverrides: ["WEIBEI_PDF_WORKER_SAFETY_TEST": "1"]
        ) == Data("verification-ok\n".utf8) else { return false }

        let timeoutStart = Date()
        guard runWorker(
            arguments: ["--safety-probe", "timeout"],
            timeout: 0.15,
            maximumResidentBytes: maximumWorkerResidentBytes,
            maximumOutputBytes: 1_024,
            environmentOverrides: ["WEIBEI_PDF_WORKER_SAFETY_TEST": "1"]
        ) == nil, Date().timeIntervalSince(timeoutStart) < 1 else { return false }

        let outputStart = Date()
        guard runWorker(
            arguments: ["--safety-probe", "output"],
            timeout: 1,
            maximumResidentBytes: maximumWorkerResidentBytes,
            maximumOutputBytes: 1_024,
            environmentOverrides: ["WEIBEI_PDF_WORKER_SAFETY_TEST": "1"]
        ) == nil, Date().timeIntervalSince(outputStart) < 1 else { return false }

        let memoryStart = Date()
        guard runWorker(
            arguments: ["--safety-probe", "memory"],
            timeout: 2,
            maximumResidentBytes: 128 * 1_024 * 1_024,
            maximumOutputBytes: 1_024,
            environmentOverrides: ["WEIBEI_PDF_WORKER_SAFETY_TEST": "1"]
        ) == nil, Date().timeIntervalSince(memoryStart) < 1.5 else { return false }

        let cancellationCompletion = DispatchSemaphore(value: 0)
        let cancellationTask = Task.detached {
            _ = runWorker(
                arguments: ["--safety-probe", "timeout"],
                timeout: 2,
                maximumResidentBytes: maximumWorkerResidentBytes,
                maximumOutputBytes: 1_024,
                environmentOverrides: ["WEIBEI_PDF_WORKER_SAFETY_TEST": "1"]
            )
            cancellationCompletion.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)
        let cancellationStart = Date()
        cancellationTask.cancel()
        return cancellationCompletion.wait(timeout: .now() + 1) == .success
            && Date().timeIntervalSince(cancellationStart) < 1
    }
#endif

    private static func runWorker(
        arguments: [String],
        timeout: TimeInterval,
        maximumResidentBytes: UInt64,
        maximumOutputBytes: Int,
        environmentOverrides: [String: String] = [:]
    ) -> Data? {
        guard !Task.isCancelled,
              maximumOutputBytes > 0,
              let workerURL = workerURL() else { return nil }
#if targetEnvironment(macCatalyst)
        return runCatalystWorker(at: workerURL, arguments: arguments, timeout: timeout,
                                 maximumResidentBytes: maximumResidentBytes,
                                 maximumOutputBytes: maximumOutputBytes,
                                 environmentOverrides: environmentOverrides)
#else
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = workerURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        var environment = [
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
        ]
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        process.environment = environment

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputBox = WorkerOutputBox()
        let terminationState = WorkerTerminationState()
        let completion = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            while true {
                let chunk = outputPipe.fileHandleForReading.readData(ofLength: 64 * 1_024)
                guard !chunk.isEmpty else { break }
                guard outputBox.append(chunk, limit: maximumOutputBytes) else {
                    terminationState.markTerminated()
                    terminate(process)
                    break
                }
            }
            process.waitUntilExit()
            completion.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var terminated = false
        while completion.wait(timeout: .now() + 0.02) == .timedOut {
            if Task.isCancelled
                || Date() >= deadline
                || workerResidentBytes(process.processIdentifier).map({ $0 > maximumResidentBytes }) == true {
                terminate(process)
                terminated = true
                break
            }
        }
        if terminated {
            _ = completion.wait(timeout: .now() + 1)
        }

        let captured = outputBox.load()
        guard !Task.isCancelled,
              !terminated,
              !terminationState.wasTerminated(),
              process.terminationReason == .exit,
              process.terminationStatus == 0,
              !captured.overflowed else { return nil }
        return captured.output
#endif
    }

#if targetEnvironment(macCatalyst)
    // Catalyst exposes POSIX spawning, but not Process.run(). Keep the same
    // isolated PDF worker and its time, memory, cancellation and output limits.
    private static func runCatalystWorker(
        at url: URL, arguments: [String], timeout: TimeInterval,
        maximumResidentBytes: UInt64, maximumOutputBytes: Int,
        environmentOverrides: [String: String]
    ) -> Data? {
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { return nil }
        defer { close(descriptors[0]) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        var environment = ["LANG": "en_US.UTF-8", "PATH": "/usr/bin:/bin", "TMPDIR": NSTemporaryDirectory()]
        environment.merge(environmentOverrides) { _, new in new }
        var argv = ([url.path] + arguments).map { strdup($0) } + [nil]
        var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, url.path, &actions, &attributes, &argv, &envp)
        close(descriptors[1])
        guard result == 0 else { return nil }
        var exited = false
        var status: Int32 = 0
        defer {
            if !exited { kill(pid, SIGKILL); while waitpid(pid, &status, 0) < 0 && errno == EINTR {} }
        }
        guard fcntl(descriptors[0], F_SETFL, O_NONBLOCK) != -1 else { return nil }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            guard !Task.isCancelled, Date() < deadline,
                  workerResidentBytes(pid).map({ $0 <= maximumResidentBytes }) != false else { return nil }
            let count = read(descriptors[0], &buffer, buffer.count)
            if count > 0 {
                guard output.count + count <= maximumOutputBytes else { return nil }
                output.append(contentsOf: buffer.prefix(count))
            } else if count < 0 && errno != EAGAIN && errno != EINTR { return nil }
            if !exited { exited = waitpid(pid, &status, WNOHANG) == pid }
            if exited && count <= 0 { return status == 0 ? output : nil }
            if count <= 0 { usleep(20_000) }
        }
    }
#endif

    private static func workerURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers", isDirectory: true)
                .appendingPathComponent(workerName),
        ]
        if let executableURL = Bundle.main.executableURL {
            candidates.append(executableURL.deletingLastPathComponent().appendingPathComponent(workerName))
        }
        if let executablePath = ProcessInfo.processInfo.arguments.first {
            candidates.append(
                URL(fileURLWithPath: executablePath)
                    .standardizedFileURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(workerName)
            )
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func workerResidentBytes(_ processID: pid_t) -> UInt64? {
        var information = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            proc_pidinfo(processID, PROC_PIDTASKINFO, 0, pointer, Int32(size))
        }
        return result == Int32(size) ? information.pti_resident_size : nil
    }

#if !targetEnvironment(macCatalyst)
    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        Thread.sleep(forTimeInterval: 0.1)
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
#endif
}
