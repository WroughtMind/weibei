import Foundation
import XCTest
@testable import WeiBeiDevCore

final class PiRuntimeTests: XCTestCase {
    /// Verifies both supported architectures resolve to their explicit manifest artifacts.
    func testManifestLoadsBothArchitectures() throws {
        let fixture = try PiRuntimeFixture()
        defer { fixture.remove() }

        let manifest = try PiRuntimeVendorManifest.load(from: fixture.manifestURL)

        XCTAssertEqual(try manifest.artifact(for: .arm64).archive, "pi-darwin-arm64.tar.gz")
        XCTAssertEqual(try manifest.artifact(for: .x86_64).archive, "pi-darwin-x64.tar.gz")
        XCTAssertEqual(manifest.piVersion, "0.80.2")
    }

    /// Verifies unsafe version paths are rejected before they can influence cache paths.
    func testManifestRejectsUnsafeVersion() throws {
        let fixture = try PiRuntimeFixture(piVersion: "../escape")
        defer { fixture.remove() }

        XCTAssertThrowsError(try PiRuntimeVendorManifest.load(from: fixture.manifestURL)) { error in
            XCTAssertEqual((error as? PiRuntimePreparationError)?.code, "pi_manifest_invalid")
        }
    }

    /// Verifies preparation downloads, verifies, signs, probes, and publishes a complete runtime.
    func testPrepareDownloadsAndPublishesValidatedRuntime() async throws {
        let fixture = try PiRuntimeFixture()
        defer { fixture.remove() }
        let downloader = FakePiRuntimeDownloader(sourceArchiveURL: fixture.archiveURL)
        let executor = FakePiRuntimeProcessExecutor(extractedSourceURL: fixture.extractedSourceURL)
        let preparer = PiRuntimePreparer(downloader: downloader, processExecutor: executor)

        let prepared = try await preparer.prepare(
            configuration: PiRuntimePreparationConfiguration(
                repositoryRoot: fixture.rootURL,
                architecture: .arm64
            )
        )

        XCTAssertTrue(prepared.directoryURL.path.hasPrefix(fixture.rootURL.appendingPathComponent(".build").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: prepared.executableURL.path))
        XCTAssertEqual(prepared.manifest.piVersion, "0.80.2")
        let downloadCount = await downloader.downloadCount
        let tarInvocationCount = await executor.invocationCount(executable: "/usr/bin/tar")
        let codesignInvocationCount = await executor.invocationCount(executable: "/usr/bin/codesign")
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(tarInvocationCount, 1)
        XCTAssertGreaterThanOrEqual(codesignInvocationCount, 3)
        XCTAssertEqual(
            try String(contentsOf: prepared.directoryURL.appendingPathComponent("artifact.sha256"), encoding: .utf8),
            "\(fixture.archiveHash)  pi-darwin-arm64.tar.gz\n"
        )
    }

    /// Verifies a valid cache is reused without a second archive extraction.
    func testPrepareReusesCompleteCache() async throws {
        let fixture = try PiRuntimeFixture()
        defer { fixture.remove() }
        let downloader = FakePiRuntimeDownloader(sourceArchiveURL: fixture.archiveURL)
        let executor = FakePiRuntimeProcessExecutor(extractedSourceURL: fixture.extractedSourceURL)
        let preparer = PiRuntimePreparer(downloader: downloader, processExecutor: executor)
        let configuration = PiRuntimePreparationConfiguration(
            repositoryRoot: fixture.rootURL,
            architecture: .arm64
        )

        let first = try await preparer.prepare(configuration: configuration)
        let second = try await preparer.prepare(configuration: configuration)

        XCTAssertEqual(first, second)
        let downloadCount = await downloader.downloadCount
        let tarInvocationCount = await executor.invocationCount(executable: "/usr/bin/tar")
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(tarInvocationCount, 1)
    }

    /// Verifies x86_64 uses the darwin-x64 cache key and accepts an x86_64 Mach-O runtime.
    func testPrepareSupportsX86_64Runtime() async throws {
        let fixture = try PiRuntimeFixture(architecture: .x86_64)
        defer { fixture.remove() }
        let executor = FakePiRuntimeProcessExecutor(extractedSourceURL: fixture.extractedSourceURL)
        let preparer = PiRuntimePreparer(
            downloader: FakePiRuntimeDownloader(sourceArchiveURL: fixture.archiveURL),
            processExecutor: executor
        )

        let prepared = try await preparer.prepare(
            configuration: PiRuntimePreparationConfiguration(
                repositoryRoot: fixture.rootURL,
                architecture: .x86_64,
                archiveURL: fixture.archiveURL
            )
        )

        XCTAssertEqual(prepared.architecture, .x86_64)
        XCTAssertTrue(prepared.directoryURL.path.contains("/darwin-x64/"))
    }

    /// Verifies a caller-provided archive with the wrong digest fails without extraction.
    func testPrepareRejectsArchiveHashMismatch() async throws {
        let fixture = try PiRuntimeFixture()
        defer { fixture.remove() }
        let wrongArchive = fixture.rootURL.appendingPathComponent("wrong.tar.gz")
        try Data("wrong".utf8).write(to: wrongArchive)
        let executor = FakePiRuntimeProcessExecutor(extractedSourceURL: fixture.extractedSourceURL)
        let preparer = PiRuntimePreparer(
            downloader: FakePiRuntimeDownloader(sourceArchiveURL: fixture.archiveURL),
            processExecutor: executor
        )

        var capturedError: PiRuntimePreparationError?
        do {
            _ = try await preparer.prepare(
                configuration: PiRuntimePreparationConfiguration(
                    repositoryRoot: fixture.rootURL,
                    architecture: .arm64,
                    archiveURL: wrongArchive
                )
            )
        } catch let error as PiRuntimePreparationError {
            capturedError = error
        }
        let preparationError = try XCTUnwrap(capturedError)
        XCTAssertEqual(preparationError.code, "pi_archive_hash_mismatch")
        let tarInvocationCount = await executor.invocationCount(executable: "/usr/bin/tar")
        XCTAssertEqual(tarInvocationCount, 0)
    }

    /// Verifies a corrupt repository-local archive is discarded and downloaded again.
    func testPrepareReplacesCorruptDownloadedArchive() async throws {
        let fixture = try PiRuntimeFixture()
        defer { fixture.remove() }
        let cachedArchive = fixture.rootURL
            .appendingPathComponent(".build/pi-runtime/downloads/pi-darwin-arm64.tar.gz")
        try FileManager.default.createDirectory(
            at: cachedArchive.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("corrupt".utf8).write(to: cachedArchive)
        let downloader = FakePiRuntimeDownloader(sourceArchiveURL: fixture.archiveURL)
        let executor = FakePiRuntimeProcessExecutor(extractedSourceURL: fixture.extractedSourceURL)
        let preparer = PiRuntimePreparer(downloader: downloader, processExecutor: executor)

        _ = try await preparer.prepare(
            configuration: PiRuntimePreparationConfiguration(
                repositoryRoot: fixture.rootURL,
                architecture: .arm64
            )
        )

        let downloadCount = await downloader.downloadCount
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(try PiRuntimeIntegrity.sha256(of: cachedArchive), fixture.archiveHash)
    }

    /// Verifies a failed final validation restores the runtime directory that preceded staging.
    func testPublishFailureRestoresPreviousRuntimeDirectory() async throws {
        let fixture = try PiRuntimeFixture()
        defer { fixture.remove() }
        let runtimeURL = fixture.rootURL
            .appendingPathComponent(".build/pi-runtime/0.80.2/darwin-arm64/PiRuntime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        let markerURL = runtimeURL.appendingPathComponent("previous-runtime-marker")
        try Data("keep".utf8).write(to: markerURL)
        let executor = FakePiRuntimeProcessExecutor(
            extractedSourceURL: fixture.extractedSourceURL,
            failVersionProbeNumber: 2
        )
        let preparer = PiRuntimePreparer(
            downloader: FakePiRuntimeDownloader(sourceArchiveURL: fixture.archiveURL),
            processExecutor: executor
        )

        do {
            _ = try await preparer.prepare(
                configuration: PiRuntimePreparationConfiguration(
                    repositoryRoot: fixture.rootURL,
                    architecture: .arm64
                )
            )
            XCTFail("Expected final validation failure")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
        }
    }

    /// Verifies an active cache lock times out instead of mutating a concurrent preparation.
    func testCacheLockTimesOutWhileOwned() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiRuntimeLockTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent(".prepare.lock", isDirectory: true)
        let owner = try await PiRuntimeCacheLock.acquire(
            at: lockURL,
            configuration: PiRuntimeCacheLockConfiguration(timeout: .seconds(1), retryInterval: .milliseconds(5)),
            fileManager: .default
        )
        defer { owner.release() }

        var capturedError: PiRuntimePreparationError?
        do {
            _ = try await PiRuntimeCacheLock.acquire(
                at: lockURL,
                configuration: PiRuntimeCacheLockConfiguration(
                    timeout: .milliseconds(30),
                    retryInterval: .milliseconds(5)
                ),
                fileManager: .default
            )
        } catch let error as PiRuntimePreparationError {
            capturedError = error
        }
        let preparationError = try XCTUnwrap(capturedError)
        XCTAssertEqual(preparationError.code, "pi_cache_lock_timeout")
    }

    /// Verifies an unlocked diagnostic file can be acquired without stale-owner mutation.
    func testCacheLockAcquiresExistingUnlockedFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiRuntimeLockTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lockURL = root.appendingPathComponent(".prepare.lock", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("stale diagnostics\n".utf8).write(to: lockURL)

        let lock = try await PiRuntimeCacheLock.acquire(
            at: lockURL,
            configuration: PiRuntimeCacheLockConfiguration(
                timeout: .seconds(1),
                retryInterval: .milliseconds(5)
            ),
            fileManager: .default
        )

        lock.release()
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    }
}

private final class PiRuntimeFixture {
    let rootURL: URL
    let manifestURL: URL
    let archiveURL: URL
    let archiveHash: String
    let extractedSourceURL: URL

    /// Creates a repository, pinned archive, and extracted archive fixture.
    init(
        piVersion: String = "0.80.2",
        architecture: PiRuntimeArchitecture = .arm64
    ) throws {
        let fileManager = FileManager.default
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("PiRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        let vendorURL = rootURL.appendingPathComponent("Vendor/PiRuntime", isDirectory: true)
        extractedSourceURL = rootURL.appendingPathComponent("ArchiveSource/pi", isDirectory: true)
        archiveURL = rootURL.appendingPathComponent("fixture.tar.gz")
        try fileManager.createDirectory(
            at: extractedSourceURL.appendingPathComponent("theme", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: vendorURL, withIntermediateDirectories: true)

        let cpuBytes: [UInt8]
        switch architecture {
        case .arm64:
            cpuBytes = [0x0c, 0x00, 0x00, 0x01]
        case .x86_64:
            cpuBytes = [0x07, 0x00, 0x00, 0x01]
        }
        var machO = Data([0xcf, 0xfa, 0xed, 0xfe] + cpuBytes)
        machO.append(Data(repeating: 0, count: 56))
        try machO.write(to: extractedSourceURL.appendingPathComponent("pi"))
        try #"{"version":"0.80.2"}"#.write(
            to: extractedSourceURL.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"name":"dark"}"#.write(
            to: extractedSourceURL.appendingPathComponent("theme/dark.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"name":"light"}"#.write(
            to: extractedSourceURL.appendingPathComponent("theme/light.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data("archive".utf8).write(to: archiveURL)
        archiveHash = try PiRuntimeIntegrity.sha256(of: archiveURL)
        try "MIT".write(to: vendorURL.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)
        try "notices".write(
            to: vendorURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = PiRuntimeVendorManifest(
            schemaVersion: 1,
            piVersion: piVersion,
            sourceRepository: "https://example.com/pi",
            sourceCommit: String(repeating: "a", count: 40),
            license: "MIT",
            artifacts: [
                "darwin-arm64": PiRuntimeArtifact(
                    archive: "pi-darwin-arm64.tar.gz",
                    sha256: archiveHash
                ),
                "darwin-x64": PiRuntimeArtifact(
                    archive: "pi-darwin-x64.tar.gz",
                    sha256: archiveHash
                ),
            ]
        )
        manifestURL = vendorURL.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)
    }

    /// Removes the complete temporary repository fixture.
    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor FakePiRuntimeDownloader: PiRuntimeDownloading {
    private let sourceArchiveURL: URL
    private(set) var downloadCount = 0

    /// Creates a downloader that copies a local pinned archive.
    init(sourceArchiveURL: URL) {
        self.sourceArchiveURL = sourceArchiveURL
    }

    /// Copies the fixture archive to the requested download staging URL.
    func download(from sourceURL: URL, to destinationURL: URL) async throws {
        XCTAssertEqual(sourceURL.absoluteString, "https://example.com/pi/releases/download/v0.80.2/pi-darwin-arm64.tar.gz")
        downloadCount += 1
        try FileManager.default.copyItem(at: sourceArchiveURL, to: destinationURL)
    }
}

private actor FakePiRuntimeProcessExecutor: ProcessExecuting {
    private struct Invocation {
        let executable: String
        let arguments: [String]
    }

    private let extractedSourceURL: URL
    private let failVersionProbeNumber: Int?
    private var invocations: [Invocation] = []
    private var versionProbeCount = 0

    /// Creates a process fake that expands a controlled archive source.
    init(extractedSourceURL: URL, failVersionProbeNumber: Int? = nil) {
        self.extractedSourceURL = extractedSourceURL
        self.failVersionProbeNumber = failVersionProbeNumber
    }

    /// Simulates tar, codesign, xattr, and the PI version executable.
    func execute(_ request: ProcessExecutionRequest) async throws -> ProcessExecutionResult {
        let executableURL = request.executableURL
        let arguments = request.arguments
        invocations.append(Invocation(executable: executableURL.path, arguments: arguments))
        if executableURL.path == "/usr/bin/tar" {
            guard let destinationIndex = arguments.firstIndex(of: "-C"),
                  arguments.indices.contains(destinationIndex + 1) else {
                return result(for: request, exitCode: 2, standardError: "missing extraction directory")
            }
            let destination = URL(fileURLWithPath: arguments[destinationIndex + 1], isDirectory: true)
                .appendingPathComponent("pi", isDirectory: true)
            try FileManager.default.copyItem(at: extractedSourceURL, to: destination)
        }
        if executableURL.lastPathComponent == "pi", arguments == ["--version"] {
            versionProbeCount += 1
            if versionProbeCount == failVersionProbeNumber {
                return result(for: request, exitCode: 0, standardOutput: "unexpected\n")
            }
            return result(for: request, exitCode: 0, standardOutput: "0.80.2\n")
        }
        return result(for: request, exitCode: 0)
    }

    /// Returns how many times a given absolute executable was invoked.
    func invocationCount(executable: String) -> Int {
        invocations.count { $0.executable == executable }
    }

    /// Creates a shared-executor result for one simulated process.
    private func result(
        for request: ProcessExecutionRequest,
        exitCode: Int32,
        standardOutput: String = "",
        standardError: String = ""
    ) -> ProcessExecutionResult {
        ProcessExecutionResult(
            command: ProcessCommand(
                executableURL: request.executableURL,
                arguments: request.arguments,
                workingDirectoryURL: request.workingDirectoryURL
            ),
            processIdentifier: 123,
            termination: .exited(code: exitCode),
            standardOutput: CapturedProcessOutput(
                data: Data(standardOutput.utf8),
                totalByteCount: standardOutput.utf8.count,
                isTruncated: false
            ),
            standardError: CapturedProcessOutput(
                data: Data(standardError.utf8),
                totalByteCount: standardError.utf8.count,
                isTruncated: false
            ),
            duration: .zero
        )
    }
}
