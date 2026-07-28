import Foundation

/// Prepares and validates the pinned PI runtime in the repository-local build cache.
///
/// FileManager is safe for the independent path-based operations used here but is
/// not annotated Sendable by Foundation, so this value provides that guarantee.
public struct PiRuntimePreparer: @unchecked Sendable {
    private struct PackageMetadata: Decodable {
        let version: String
    }

    private let downloader: any PiRuntimeDownloading
    private let processExecutor: any ProcessExecuting
    private let fileManager: FileManager

    /// Creates a PI runtime preparer with explicit external-effect dependencies.
    ///
    /// - Parameters:
    ///   - downloader: URLSession-backed production downloader or a test fake.
    ///   - processExecutor: Executor for tar, xattr, codesign, and the version probe.
    ///   - fileManager: File manager used for repository-local cache mutations.
    public init(
        downloader: any PiRuntimeDownloading = URLSessionPiRuntimeDownloader(),
        processExecutor: any ProcessExecuting,
        fileManager: FileManager = .default
    ) {
        self.downloader = downloader
        self.processExecutor = processExecutor
        self.fileManager = fileManager
    }

    /// Ensures that a complete, signed, architecture-correct runtime exists in `.build/pi-runtime`.
    ///
    /// A valid cache is reused. Invalid state is replaced only after a complete staging
    /// runtime passes all checks; there is no fallback to the legacy shell preparer.
    ///
    /// - Parameter configuration: Repository, architecture, archive, and lock inputs.
    /// - Returns: The fully validated cached runtime.
    public func prepare(
        configuration: PiRuntimePreparationConfiguration
    ) async throws -> PreparedPiRuntime {
        let repository = PiRuntimeRepositoryPaths(root: configuration.repositoryRoot)
        try repository.validate(fileManager: fileManager)
        let manifest = try PiRuntimeVendorManifest.load(from: repository.manifest)
        let artifact = try manifest.artifact(for: configuration.architecture)
        let cache = PiRuntimeCachePaths(
            cacheRoot: repository.cache,
            version: manifest.piVersion,
            architecture: configuration.architecture,
            archiveName: artifact.archive
        )

        if let prepared = try? await validateRuntime(
            at: cache.runtime,
            repositoryManifestURL: repository.manifest,
            manifest: manifest,
            architecture: configuration.architecture
        ) {
            return prepared
        }

        do {
            try fileManager.createDirectory(at: cache.cacheRoot, withIntermediateDirectories: true)
        } catch {
            throw PiRuntimePreparationError.fileOperationFailed("create runtime cache", error)
        }
        let cacheLock = try await PiRuntimeCacheLock.acquire(
            at: cache.lock,
            configuration: configuration.lock,
            fileManager: fileManager
        )
        defer { cacheLock.release() }

        if let prepared = try? await validateRuntime(
            at: cache.runtime,
            repositoryManifestURL: repository.manifest,
            manifest: manifest,
            architecture: configuration.architecture
        ) {
            return prepared
        }

        let archiveURL = try await resolveArchive(
            configuration: configuration,
            manifest: manifest,
            artifact: artifact,
            cache: cache
        )
        return try await stageAndPublish(
            archiveURL: archiveURL,
            repository: repository,
            manifest: manifest,
            artifact: artifact,
            cache: cache,
            architecture: configuration.architecture
        )
    }

    /// Validates a prepared runtime against the repository manifest and executable behavior.
    ///
    /// - Parameters:
    ///   - runtimeURL: `PiRuntime` directory to validate.
    ///   - repositoryManifestURL: Authoritative repository manifest.
    ///   - manifest: Already parsed authoritative manifest.
    ///   - architecture: Expected executable architecture.
    /// - Returns: A prepared runtime description on success.
    public func validateRuntime(
        at runtimeURL: URL,
        repositoryManifestURL: URL,
        manifest: PiRuntimeVendorManifest,
        architecture: PiRuntimeArchitecture
    ) async throws -> PreparedPiRuntime {
        let binURL = runtimeURL.appendingPathComponent("bin", isDirectory: true)
        let executableURL = binURL.appendingPathComponent("pi")
        let packageURL = binURL.appendingPathComponent("package.json")
        let runtimeManifestURL = runtimeURL.appendingPathComponent("manifest.json")
        let binaryHashURL = runtimeURL.appendingPathComponent("binary.sha256")
        let artifactHashURL = runtimeURL.appendingPathComponent("artifact.sha256")
        let requiredFiles = [
            executableURL,
            packageURL,
            binURL.appendingPathComponent("theme/dark.json"),
            binURL.appendingPathComponent("theme/light.json"),
            runtimeURL.appendingPathComponent("LICENSE"),
            runtimeURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"),
            runtimeManifestURL,
            binaryHashURL,
            artifactHashURL,
        ]
        guard requiredFiles.allSatisfy(isNonEmptyRegularFile) else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "required files are missing")
        }
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "bin/pi is not executable")
        }

        let authoritativeManifest = try Data(contentsOf: repositoryManifestURL)
        let cachedManifest = try Data(contentsOf: runtimeManifestURL)
        guard authoritativeManifest == cachedManifest else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "manifest differs from Vendor/PiRuntime/manifest.json")
        }
        let repositoryVendorURL = repositoryManifestURL.deletingLastPathComponent()
        let repositoryLicense = try Data(contentsOf: repositoryVendorURL.appendingPathComponent("LICENSE"))
        let repositoryNotices = try Data(contentsOf: repositoryVendorURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"))
        let cachedLicense = try Data(contentsOf: runtimeURL.appendingPathComponent("LICENSE"))
        let cachedNotices = try Data(contentsOf: runtimeURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"))
        guard cachedLicense == repositoryLicense, cachedNotices == repositoryNotices else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "redistribution notices differ from Vendor/PiRuntime")
        }
        guard let cachedModel = try? JSONDecoder().decode(PiRuntimeVendorManifest.self, from: cachedManifest),
              cachedModel == manifest else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "cached manifest fields differ")
        }

        guard let packageData = try? Data(contentsOf: packageURL),
              let package = try? JSONDecoder().decode(PackageMetadata.self, from: packageData),
              package.version == manifest.piVersion else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "package.json version differs from \(manifest.piVersion)")
        }
        let expectedBinaryHash = try String(contentsOf: binaryHashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard expectedBinaryHash.count == 64,
              expectedBinaryHash.allSatisfy(\.isHexDigit),
              try PiRuntimeIntegrity.sha256(of: executableURL) == expectedBinaryHash else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "binary SHA-256 does not match")
        }
        let artifact = try manifest.artifact(for: architecture)
        let artifactLine = try String(contentsOf: artifactHashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard artifactLine == "\(artifact.sha256)  \(artifact.archive)" else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "artifact SHA-256 record does not match")
        }
        guard PiRuntimeIntegrity.hasArchitecture(architecture, executableURL: executableURL) else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "bin/pi has the wrong Mach-O architecture")
        }

        try await requireSuccessfulProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--strict", executableURL.path],
            workingDirectoryURL: runtimeURL
        )
        let versionResult = try await requireSuccessfulProcess(
            executableURL: executableURL,
            arguments: ["--version"],
            workingDirectoryURL: runtimeURL
        )
        guard versionResult.standardOutput?.stringUTF8
            .trimmingCharacters(in: .whitespacesAndNewlines) == manifest.piVersion else {
            throw PiRuntimePreparationError.runtimeInvalid(runtimeURL, "bin/pi --version differs from \(manifest.piVersion)")
        }

        return PreparedPiRuntime(
            directoryURL: runtimeURL,
            executableURL: executableURL,
            manifest: manifest,
            architecture: architecture
        )
    }

    /// Resolves and verifies a caller-supplied or downloaded release archive.
    private func resolveArchive(
        configuration: PiRuntimePreparationConfiguration,
        manifest: PiRuntimeVendorManifest,
        artifact: PiRuntimeArtifact,
        cache: PiRuntimeCachePaths
    ) async throws -> URL {
        if let archiveURL = configuration.archiveURL {
            try verifyArchive(archiveURL, expectedHash: artifact.sha256)
            return archiveURL
        }

        try fileManager.createDirectory(at: cache.downloads, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: cache.downloadedArchive.path) {
            if (try? PiRuntimeIntegrity.sha256(of: cache.downloadedArchive)) == artifact.sha256 {
                return cache.downloadedArchive
            }
            try fileManager.removeItem(at: cache.downloadedArchive)
        }

        guard let releaseBaseURL = URL(string: manifest.sourceRepository) else {
            throw PiRuntimePreparationError.manifestInvalid("sourceRepository is not a URL")
        }
        let releaseURL = releaseBaseURL
            .appendingPathComponent("releases/download")
            .appendingPathComponent("v\(manifest.piVersion)")
            .appendingPathComponent(artifact.archive)
        var finalError: Error?
        for _ in 0..<configuration.downloadAttempts {
            try Task.checkCancellation()
            let partialURL = cache.downloads
                .appendingPathComponent(".\(artifact.archive).part-\(UUID().uuidString)")
            do {
                try await downloader.download(from: releaseURL, to: partialURL)
                try verifyArchive(partialURL, expectedHash: artifact.sha256)
                if fileManager.fileExists(atPath: cache.downloadedArchive.path) {
                    try fileManager.removeItem(at: cache.downloadedArchive)
                }
                try fileManager.moveItem(at: partialURL, to: cache.downloadedArchive)
                return cache.downloadedArchive
            } catch {
                try? fileManager.removeItem(at: partialURL)
                if error is CancellationError {
                    throw error
                }
                finalError = error
            }
        }
        if let preparationError = finalError as? PiRuntimePreparationError {
            throw preparationError
        }
        throw PiRuntimePreparationError.downloadFailed(
            releaseURL,
            finalError ?? URLError(.unknown)
        )
    }

    /// Checks an archive against its manifest-pinned SHA-256.
    private func verifyArchive(_ archiveURL: URL, expectedHash: String) throws {
        let actualHash: String
        do {
            actualHash = try PiRuntimeIntegrity.sha256(of: archiveURL)
        } catch {
            throw PiRuntimePreparationError.archiveInvalid(
                "cannot read \(archiveURL.path): \(error.localizedDescription)"
            )
        }
        guard actualHash == expectedHash else {
            throw PiRuntimePreparationError.archiveHashMismatch(
                archiveURL,
                expected: expectedHash,
                actual: actualHash
            )
        }
    }

    /// Builds a complete runtime in staging, validates it, and transactionally publishes it.
    private func stageAndPublish(
        archiveURL: URL,
        repository: PiRuntimeRepositoryPaths,
        manifest: PiRuntimeVendorManifest,
        artifact: PiRuntimeArtifact,
        cache: PiRuntimeCachePaths,
        architecture: PiRuntimeArchitecture
    ) async throws -> PreparedPiRuntime {
        try fileManager.createDirectory(at: cache.runtimeParent, withIntermediateDirectories: true)
        let stagingRoot = cache.runtimeParent
            .appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let extractedURL = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        let stagingRuntime = stagingRoot.appendingPathComponent("PiRuntime", isDirectory: true)
        let stagingBin = stagingRuntime.appendingPathComponent("bin", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        do {
            try fileManager.createDirectory(at: extractedURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: stagingBin, withIntermediateDirectories: true)
        } catch {
            throw PiRuntimePreparationError.fileOperationFailed("create staging directories", error)
        }
        try await requireSuccessfulProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archiveURL.path, "-C", extractedURL.path],
            workingDirectoryURL: stagingRoot
        )

        let sourceURL = extractedURL.appendingPathComponent("pi", isDirectory: true)
        let sourceExecutable = sourceURL.appendingPathComponent("pi")
        let sourcePackage = sourceURL.appendingPathComponent("package.json")
        let sourceTheme = sourceURL.appendingPathComponent("theme", isDirectory: true)
        let sourceRequired = [
            sourceExecutable,
            sourcePackage,
            sourceTheme.appendingPathComponent("dark.json"),
            sourceTheme.appendingPathComponent("light.json"),
        ]
        guard sourceRequired.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw PiRuntimePreparationError.archiveInvalid("archive is missing pi, package.json, or required themes")
        }

        do {
            try fileManager.copyItem(at: sourceExecutable, to: stagingBin.appendingPathComponent("pi"))
            try fileManager.copyItem(at: sourcePackage, to: stagingBin.appendingPathComponent("package.json"))
            try fileManager.copyItem(at: sourceTheme, to: stagingBin.appendingPathComponent("theme", isDirectory: true))
            try fileManager.copyItem(at: repository.manifest, to: stagingRuntime.appendingPathComponent("manifest.json"))
            try fileManager.copyItem(at: repository.license, to: stagingRuntime.appendingPathComponent("LICENSE"))
            try fileManager.copyItem(at: repository.notices, to: stagingRuntime.appendingPathComponent("THIRD_PARTY_NOTICES.md"))
            try "\(artifact.sha256)  \(artifact.archive)\n".write(
                to: stagingRuntime.appendingPathComponent("artifact.sha256"),
                atomically: true,
                encoding: .utf8
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: stagingBin.appendingPathComponent("pi").path
            )
        } catch {
            throw PiRuntimePreparationError.fileOperationFailed("assemble staging runtime", error)
        }

        _ = try? await processExecutor.execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/xattr"),
                arguments: ["-dr", "com.apple.quarantine", stagingRuntime.path],
                workingDirectoryURL: stagingRoot,
                timeout: .seconds(30)
            )
        )
        let stagingExecutable = stagingBin.appendingPathComponent("pi")
        try await requireSuccessfulProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--force", "--sign", "-", "--timestamp=none", stagingExecutable.path],
            workingDirectoryURL: stagingRoot
        )
        try await requireSuccessfulProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--strict", stagingExecutable.path],
            workingDirectoryURL: stagingRoot
        )
        do {
            let binaryHash = try PiRuntimeIntegrity.sha256(of: stagingExecutable)
            try "\(binaryHash)\n".write(
                to: stagingRuntime.appendingPathComponent("binary.sha256"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            throw PiRuntimePreparationError.fileOperationFailed("write signed binary hash", error)
        }
        _ = try await validateRuntime(
            at: stagingRuntime,
            repositoryManifestURL: repository.manifest,
            manifest: manifest,
            architecture: architecture
        )

        let backupURL = cache.runtimeParent
            .appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        let hadPreviousRuntime = fileManager.fileExists(atPath: cache.runtime.path)
        var movedPreviousRuntime = false
        var publishedNewRuntime = false
        do {
            if hadPreviousRuntime {
                try fileManager.moveItem(at: cache.runtime, to: backupURL)
                movedPreviousRuntime = true
            }
            try fileManager.moveItem(at: stagingRuntime, to: cache.runtime)
            publishedNewRuntime = true
            let prepared = try await validateRuntime(
                at: cache.runtime,
                repositoryManifestURL: repository.manifest,
                manifest: manifest,
                architecture: architecture
            )
            if hadPreviousRuntime {
                try? fileManager.removeItem(at: backupURL)
            }
            return prepared
        } catch {
            if publishedNewRuntime {
                try? fileManager.removeItem(at: cache.runtime)
            }
            if movedPreviousRuntime, fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: cache.runtime)
            }
            throw PiRuntimePreparationError.fileOperationFailed("publish validated runtime", error)
        }
    }

    /// Executes a runtime preparation tool and normalizes nonzero termination.
    @discardableResult
    private func requireSuccessfulProcess(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Duration = .seconds(120)
    ) async throws -> ProcessExecutionResult {
        let result: ProcessExecutionResult
        do {
            result = try await processExecutor.execute(
                ProcessExecutionRequest(
                    executableURL: executableURL,
                    arguments: arguments,
                    workingDirectoryURL: workingDirectoryURL,
                    timeout: timeout
                )
            )
        } catch {
            throw PiRuntimePreparationError.processFailed(
                executable: executableURL,
                exitCode: -1,
                stderr: error.localizedDescription
            )
        }
        guard result.succeeded else {
            throw PiRuntimePreparationError.processFailed(
                executable: executableURL,
                exitCode: result.exitCode ?? -1,
                stderr: (result.standardError?.stringUTF8 ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    /// Confirms a required runtime path is a non-empty regular file.
    private func isNonEmptyRegularFile(_ url: URL) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }
}
