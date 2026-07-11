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

    public static func runSafetySelfCheck() -> Bool {
        guard runWorker(
            arguments: ["--verification-probe", "normal"],
            timeout: 1,
            maximumResidentBytes: maximumWorkerResidentBytes,
            maximumOutputBytes: 1_024,
            enablesVerificationProbe: true
        ) == Data("verification-ok\n".utf8) else { return false }

        let timeoutStart = Date()
        guard runWorker(
            arguments: ["--verification-probe", "timeout"],
            timeout: 0.15,
            maximumResidentBytes: maximumWorkerResidentBytes,
            maximumOutputBytes: 1_024,
            enablesVerificationProbe: true
        ) == nil, Date().timeIntervalSince(timeoutStart) < 1 else { return false }

        let outputStart = Date()
        guard runWorker(
            arguments: ["--verification-probe", "output"],
            timeout: 1,
            maximumResidentBytes: maximumWorkerResidentBytes,
            maximumOutputBytes: 1_024,
            enablesVerificationProbe: true
        ) == nil, Date().timeIntervalSince(outputStart) < 1 else { return false }

        let memoryStart = Date()
        guard runWorker(
            arguments: ["--verification-probe", "memory"],
            timeout: 2,
            maximumResidentBytes: 128 * 1_024 * 1_024,
            maximumOutputBytes: 1_024,
            enablesVerificationProbe: true
        ) == nil, Date().timeIntervalSince(memoryStart) < 1.5 else { return false }

        let cancellationCompletion = DispatchSemaphore(value: 0)
        let cancellationTask = Task.detached {
            _ = runWorker(
                arguments: ["--verification-probe", "timeout"],
                timeout: 2,
                maximumResidentBytes: maximumWorkerResidentBytes,
                maximumOutputBytes: 1_024,
                enablesVerificationProbe: true
            )
            cancellationCompletion.signal()
        }
        Thread.sleep(forTimeInterval: 0.05)
        let cancellationStart = Date()
        cancellationTask.cancel()
        return cancellationCompletion.wait(timeout: .now() + 1) == .success
            && Date().timeIntervalSince(cancellationStart) < 1
    }

    private static func runWorker(
        arguments: [String],
        timeout: TimeInterval,
        maximumResidentBytes: UInt64,
        maximumOutputBytes: Int,
        enablesVerificationProbe: Bool = false
    ) -> Data? {
        guard !Task.isCancelled,
              maximumOutputBytes > 0,
              let workerURL = workerURL() else { return nil }
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
        if enablesVerificationProbe {
            environment["WEIBEI_PDF_WORKER_VERIFY"] = "1"
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
    }

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

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        Thread.sleep(forTimeInterval: 0.1)
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
}
