import Foundation
import XCTest
@testable import WeiBeiDevCore

final class BuildWorkflowTests: XCTestCase {
    /// Parses the supported Node.js output format.
    func testNodeVersionParsesVersionPrefix() throws {
        let version = try NodeVersion.parse("v22.22.3\n")

        XCTAssertEqual(version, NodeVersion(major: 22, minor: 22, patch: 3))
        XCTAssertNoThrow(try version.requireSupportedMajor())
    }

    /// Accepts Node.js releases newer than the minimum supported major version.
    func testNodeVersionAcceptsNewerMajorVersions() throws {
        let version = try NodeVersion.parse("v23.0.0")

        XCTAssertNoThrow(try version.requireSupportedMajor())
    }

    /// Rejects Node.js releases below the minimum supported major version.
    func testNodeVersionRejectsOlderMajorVersions() throws {
        let version = try NodeVersion.parse("v21.0.0")

        XCTAssertThrowsError(try version.requireSupportedMajor()) { error in
            XCTAssertEqual((error as? BuildWorkflowError)?.errorCode, "unsupported_node_version")
        }
    }

    /// Rejects output that cannot identify a complete semantic version.
    func testNodeVersionRejectsMalformedOutput() {
        XCTAssertThrowsError(try NodeVersion.parse("22")) { error in
            XCTAssertEqual((error as? BuildWorkflowError)?.errorCode, "unreadable_node_version")
        }
    }

    /// Resolves build executables from a supplied PATH without invoking a shell.
    func testBuildToolchainResolvesExecutablesFromPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-toolchain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["node", "npm", "swift"] {
            let executable = directory.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: executable.path
            )
        }

        let toolchain = try BuildToolchain.resolve(environment: ["PATH": directory.path])

        XCTAssertEqual(toolchain.node, directory.appendingPathComponent("node"))
        XCTAssertEqual(toolchain.npm, directory.appendingPathComponent("npm"))
        XCTAssertEqual(toolchain.swift, directory.appendingPathComponent("swift"))
    }

    /// Requires installation when the lockfile digest or Node.js version changes.
    func testNodeDependencyStampDetectsStaleInstallation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-node-stamp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let packageLock = directory.appendingPathComponent("package-lock.json")
        let stampURL = directory.appendingPathComponent("node_modules/.weibei-install-state.json")
        try Data("{\"lockfileVersion\":3}".utf8).write(to: packageLock)
        let store = NodeDependencyStampStore()
        let initialStamp = try store.expectedStamp(
            nodeVersion: NodeVersion(major: 22, minor: 22, patch: 3),
            packageLock: packageLock
        )

        XCTAssertTrue(store.needsInstallation(expectedStamp: initialStamp, stampURL: stampURL))
        try store.write(initialStamp, to: stampURL)
        XCTAssertFalse(store.needsInstallation(expectedStamp: initialStamp, stampURL: stampURL))

        let newerNodeStamp = try store.expectedStamp(
            nodeVersion: NodeVersion(major: 22, minor: 23, patch: 0),
            packageLock: packageLock
        )
        XCTAssertTrue(store.needsInstallation(expectedStamp: newerNodeStamp, stampURL: stampURL))

        try Data("{\"lockfileVersion\":3,\"changed\":true}".utf8).write(to: packageLock)
        let changedLockStamp = try store.expectedStamp(
            nodeVersion: NodeVersion(major: 22, minor: 22, patch: 3),
            packageLock: packageLock
        )
        XCTAssertTrue(store.needsInstallation(expectedStamp: changedLockStamp, stampURL: stampURL))
    }

    /// Requires every generated resource to exist and contain data.
    func testWebEditorProductsRejectEmptyResource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-editor-products-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/WeiBei/Resources/Editor/fonts"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = RepositoryLayout(rootDirectory: root)
        let products = WebEditorBuildProducts(repository: repository)
        try Data("javascript".utf8).write(to: products.editorJavaScript)
        try Data("stylesheet".utf8).write(to: products.editorStylesheet)
        try Data().write(to: products.representativeFont)

        XCTAssertThrowsError(try products.validate()) { error in
            XCTAssertEqual(
                error as? BuildWorkflowError,
                .missingGeneratedResource(products.representativeFont)
            )
        }

        try Data("font".utf8).write(to: products.representativeFont)
        XCTAssertNoThrow(try products.validate())
    }

    /// Uses the Node.js version and lockfile stamp to avoid redundant npm installs.
    func testNodePreparationRunsNPMCIOnlyWhenStampIsStale() async throws {
        let repository = try makeRepositoryFixture()
        defer { try? FileManager.default.removeItem(at: repository.rootDirectory) }
        let executor = StubProcessExecutor(outputs: [
            StubProcessOutput(standardOutput: "v22.22.3\n"),
            StubProcessOutput(),
            StubProcessOutput(standardOutput: "v22.22.3\n"),
        ])
        let workflow = NodePreparationWorkflow(
            repository: repository,
            toolchain: NodeBuildToolchain(
                node: repository.rootDirectory.appendingPathComponent("tools/node"),
                npm: repository.rootDirectory.appendingPathComponent("tools/npm")
            ),
            processExecutor: executor
        )

        let firstResult = try await workflow.prepare()
        let secondResult = try await workflow.prepare()

        XCTAssertTrue(firstResult.installedDependencies)
        XCTAssertFalse(secondResult.installedDependencies)
        let requests = await executor.recordedRequests()
        XCTAssertEqual(requests.map(\.arguments), [["--version"], ["ci"], ["--version"]])
    }

    /// Builds once, runs Swift package tests, and invokes each verifier directly from the bin path.
    func testCheckWorkflowExecutesBuiltVerifierProductsDirectly() async throws {
        let repository = try makeRepositoryFixture()
        defer { try? FileManager.default.removeItem(at: repository.rootDirectory) }
        try createEditorProducts(repository: repository)
        let productsDirectory = repository.rootDirectory.appendingPathComponent(".build/debug")
        try FileManager.default.createDirectory(at: productsDirectory, withIntermediateDirectories: true)
        for name in ["WeiBeiSelfCheck", "WeiBei", "WeiBeiWebEditorCheck", "WeiBeiPiCheck"] {
            try createExecutable(productsDirectory.appendingPathComponent(name))
        }
        let piExecutable = repository.rootDirectory.appendingPathComponent("runtime/bin/pi")
        try createExecutable(piExecutable)
        let executor = StubProcessExecutor(outputs: [
            StubProcessOutput(standardOutput: "v22.22.3\n"),
            StubProcessOutput(),
            StubProcessOutput(),
            StubProcessOutput(),
            StubProcessOutput(standardOutput: "\(productsDirectory.path)\n"),
            StubProcessOutput(),
            StubProcessOutput(),
            StubProcessOutput(),
            StubProcessOutput(),
            StubProcessOutput(),
        ])
        let toolchain = fixtureToolchain(repository: repository)
        let workflow = CheckWorkflow(
            repository: repository,
            toolchain: toolchain,
            processExecutor: executor
        )

        let result = try await workflow.run(piExecutable: piExecutable)

        XCTAssertEqual(
            result.verifiedExecutables,
            ["WeiBeiSelfCheck", "WeiBei", "WeiBeiWebEditorCheck", "WeiBeiPiCheck"]
        )
        let requests = await executor.recordedRequests()
        XCTAssertEqual(
            requests.filter {
                $0.executableURL == toolchain.swift && $0.arguments == ["build", "-c", "debug"]
            }.count,
            1
        )
        let invokedSwiftRun = requests.contains {
            $0.executableURL.lastPathComponent == "swift" && $0.arguments.first == "run"
        }
        XCTAssertFalse(invokedSwiftRun)
        XCTAssertTrue(requests.contains {
            $0.executableURL == productsDirectory.appendingPathComponent("WeiBei")
                && $0.arguments == ["--self-check-imported-identity"]
        })
    }

    /// Creates the minimum valid repository used by build workflow tests.
    private func makeRepositoryFixture() throws -> RepositoryLayout {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-build-workflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/WeiBei"),
            withIntermediateDirectories: true
        )
        try Data().write(to: root.appendingPathComponent("Package.swift"))
        try Data().write(to: root.appendingPathComponent("VERSION"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("package.json"))
        try Data("{\"lockfileVersion\":3}".utf8).write(to: root.appendingPathComponent("package-lock.json"))
        return try RepositoryLayout.locate(currentDirectory: root)
    }

    /// Creates executable placeholders for resolved toolchain paths.
    private func fixtureToolchain(repository: RepositoryLayout) -> BuildToolchain {
        BuildToolchain(
            node: repository.rootDirectory.appendingPathComponent("tools/node"),
            npm: repository.rootDirectory.appendingPathComponent("tools/npm"),
            swift: repository.rootDirectory.appendingPathComponent("tools/swift")
        )
    }

    /// Creates the generated files required by WebEditor product validation.
    private func createEditorProducts(repository: RepositoryLayout) throws {
        let products = WebEditorBuildProducts(repository: repository)
        try FileManager.default.createDirectory(
            at: products.representativeFont.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("javascript".utf8).write(to: products.editorJavaScript)
        try Data("stylesheet".utf8).write(to: products.editorStylesheet)
        try Data("font".utf8).write(to: products.representativeFont)
    }

    /// Creates an executable placeholder at the requested location.
    private func createExecutable(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }
}

private struct StubProcessOutput: Sendable {
    let termination: ProcessTermination
    let standardOutput: String
    let standardError: String

    /// Creates one queued fake process outcome.
    init(
        termination: ProcessTermination = .exited(code: 0),
        standardOutput: String = "",
        standardError: String = ""
    ) {
        self.termination = termination
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

private actor StubProcessExecutor: ProcessExecuting {
    private var outputs: [StubProcessOutput]
    private var requests: [ProcessExecutionRequest] = []

    /// Creates a fake executor that returns outcomes in invocation order.
    init(outputs: [StubProcessOutput]) {
        self.outputs = outputs
    }

    /// Records a process request and returns its queued outcome.
    func execute(_ request: ProcessExecutionRequest) async throws -> ProcessExecutionResult {
        requests.append(request)
        let output = outputs.isEmpty ? StubProcessOutput() : outputs.removeFirst()
        let standardOutputData = Data(output.standardOutput.utf8)
        let standardErrorData = Data(output.standardError.utf8)
        return ProcessExecutionResult(
            command: ProcessCommand(
                executableURL: request.executableURL,
                arguments: request.arguments,
                workingDirectoryURL: request.workingDirectoryURL
            ),
            processIdentifier: 100,
            termination: output.termination,
            standardOutput: CapturedProcessOutput(
                data: standardOutputData,
                totalByteCount: standardOutputData.count,
                isTruncated: false
            ),
            standardError: CapturedProcessOutput(
                data: standardErrorData,
                totalByteCount: standardErrorData.count,
                isTruncated: false
            ),
            duration: .zero
        )
    }

    /// Returns all requests observed by the fake executor.
    func recordedRequests() -> [ProcessExecutionRequest] {
        requests
    }
}
