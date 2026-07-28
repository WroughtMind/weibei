import Foundation

/// Resolves reproducible version and Git provenance for local app packaging.
public struct GitBuildMetadataResolver: @unchecked Sendable {
    private let processExecutor: any ProcessExecuting
    private let fileManager: FileManager

    /// Creates a resolver that invokes Git through the shared process executor.
    public init(
        processExecutor: any ProcessExecuting,
        fileManager: FileManager = .default
    ) {
        self.processExecutor = processExecutor
        self.fileManager = fileManager
    }

    /// Reads VERSION and full-history Git state from the repository.
    public func resolve(repositoryRoot: URL) async throws -> AppBuildMetadata {
        let versionFile = repositoryRoot.appendingPathComponent("VERSION", isDirectory: false)
        guard fileManager.fileExists(atPath: versionFile.path) else {
            throw AppPackagingError.missingInput(versionFile)
        }
        let version = try String(contentsOf: versionFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let shallow = try await git(
            ["rev-parse", "--is-shallow-repository"],
            repositoryRoot: repositoryRoot
        )
        guard shallow == "false" else {
            throw AppPackagingError.shallowRepository
        }
        let commit = try await git(
            ["rev-parse", "--verify", "HEAD"],
            repositoryRoot: repositoryRoot
        )
        let buildNumberText = try await git(
            ["rev-list", "--count", commit],
            repositoryRoot: repositoryRoot
        )
        guard let buildNumber = Int(buildNumberText) else {
            throw AppPackagingError.invalidBuildMetadata(
                "Git returned an invalid revision count: \(buildNumberText)"
            )
        }
        let status = try await git(
            ["status", "--porcelain=v1", "--untracked-files=normal"],
            repositoryRoot: repositoryRoot
        )
        return try AppBuildMetadata(
            version: version,
            buildNumber: buildNumber,
            gitCommit: commit,
            sourceDirty: !status.isEmpty
        )
    }

    /// Runs a bounded Git query and returns trimmed standard output.
    private func git(_ arguments: [String], repositoryRoot: URL) async throws -> String {
        let result = try await processExecutor.execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["-C", repositoryRoot.path] + arguments,
                workingDirectoryURL: repositoryRoot,
                timeout: .seconds(30)
            )
        )
        guard result.succeeded else {
            throw AppPackagingError.processFailed(
                tool: "git",
                exitCode: result.exitCode ?? -1,
                standardError: result.standardError?.stringUTF8 ?? ""
            )
        }
        return (result.standardOutput?.stringUTF8 ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
