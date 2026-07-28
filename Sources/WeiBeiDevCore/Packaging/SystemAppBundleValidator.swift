import CryptoKit
import Foundation

/// Production signing, runtime-probe, hash, and Mach-O validator for packaged apps.
public struct SystemAppBundleValidator: AppBundlePackageValidating, @unchecked Sendable {
    private let processExecutor: any ProcessExecuting
    private let fileManager: FileManager

    /// Creates a validator that invokes macOS tools through the shared process executor.
    public init(
        processExecutor: any ProcessExecuting,
        fileManager: FileManager = .default
    ) {
        self.processExecutor = processExecutor
        self.fileManager = fileManager
    }

    /// Seals nested executables where needed and performs strict product validation.
    public func validate(
        layout: AppBundleLayout,
        builtExecutable: URL,
        request: AppBundlePackageRequest,
        metadata _: AppBuildMetadata,
        phase: AppBundleValidationPhase
    ) async throws -> String {
        if phase != .published {
            try await requireSuccess(
                executable: "/usr/bin/xattr",
                arguments: ["-cr", layout.bundle.path],
                tool: "xattr"
            )
        }

        if phase == .staged {
            try await adHocSign(layout.piExecutable)
            try await adHocSign(layout.pdfWorker)
            try await adHocSign(layout.bundle)
        } else if phase == .distributionCandidate {
            let preliminary = try await execute(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", layout.bundle.path],
                timeout: .seconds(30)
            )
            if !preliminary.succeeded {
                // File Provider metadata can invalidate an otherwise identical
                // copy. Clear it and re-seal the candidate at its final volume.
                try await requireSuccess(
                    executable: "/usr/bin/xattr",
                    arguments: ["-cr", layout.bundle.path],
                    tool: "xattr"
                )
                try await adHocSign(layout.piExecutable)
                try await adHocSign(layout.pdfWorker)
                try await adHocSign(layout.bundle)
            }
        }

        try await verifySignature(layout.piExecutable, deep: false)
        try await verifySignature(layout.bundle, deep: true)
        try verifyPiHash(layout: layout)
        let expectedPiVersion = try readPiVersion(layout: layout)
        try await verifyPiVersion(layout.piExecutable, expected: expectedPiVersion)

        if phase == .staged {
            let workerProbe = try await processExecutor.execute(
                ProcessExecutionRequest(
                    executableURL: layout.pdfWorker,
                    arguments: ["--verification-probe", "normal"],
                    environment: .inheritAndOverride(["WEIBEI_PDF_WORKER_VERIFY": "1"]),
                    timeout: .seconds(15)
                )
            )
            let workerOutput = (workerProbe.standardOutput?.stringUTF8 ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard workerProbe.succeeded, workerOutput == "verification-ok" else {
                let errorOutput = workerProbe.standardError?.stringUTF8 ?? workerOutput
                throw AppPackagingError.pdfWorkerProbeFailed(errorOutput)
            }
        }

        let buildUUID = try await executableUUID(builtExecutable)
        let packagedUUID = try await executableUUID(layout.executable)
        guard packagedUUID == buildUUID else {
            throw AppPackagingError.binaryUUIDMismatch(
                expected: buildUUID,
                actual: packagedUUID
            )
        }

        if phase == .staged {
            let piCheck = request.buildProductsDirectory.appendingPathComponent(
                request.piCheckExecutableName,
                isDirectory: false
            )
            guard fileManager.isExecutableFile(atPath: piCheck.path) else {
                throw AppPackagingError.missingInput(piCheck)
            }
            let result = try await processExecutor.execute(
                ProcessExecutionRequest(
                    executableURL: piCheck,
                    workingDirectoryURL: request.repositoryRoot,
                    environment: .inheritAndOverride([
                        "WEIBEI_PI_EXECUTABLE": layout.piExecutable.path,
                        "WEIBEI_PI_APP_BUNDLE": layout.bundle.path,
                        "WEIBEI_PI_LIVE_CHECK": "0",
                    ]),
                    timeout: .seconds(120)
                )
            )
            guard result.succeeded else {
                throw AppPackagingError.processFailed(
                    tool: request.piCheckExecutableName,
                    exitCode: result.exitCode ?? -1,
                    standardError: result.standardError?.stringUTF8 ?? ""
                )
            }
        }

        return packagedUUID
    }

    /// Applies the repository's local ad-hoc signing policy to one bundle entry.
    private func adHocSign(_ url: URL) async throws {
        try await requireSuccess(
            executable: "/usr/bin/codesign",
            arguments: ["--force", "--sign", "-", "--timestamp=none", url.path],
            tool: "codesign"
        )
    }

    /// Verifies a nested executable or complete app bundle with strict codesign checks.
    private func verifySignature(_ url: URL, deep: Bool) async throws {
        var arguments = ["--verify"]
        if deep {
            arguments.append("--deep")
        }
        arguments += ["--strict", url.path]
        let result = try await execute(
            executable: "/usr/bin/codesign",
            arguments: arguments,
            timeout: .seconds(30)
        )
        guard result.succeeded else {
            throw AppPackagingError.invalidSignature(url)
        }
    }

    /// Verifies the packaged PI executable against its post-signing hash record.
    private func verifyPiHash(layout: AppBundleLayout) throws {
        let expectedURL = layout.piRuntimeRoot.appendingPathComponent(
            "binary.sha256",
            isDirectory: false
        )
        let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let actual = try SHA256.hash(data: Data(contentsOf: layout.piExecutable))
            .map { String(format: "%02x", $0) }
            .joined()
        guard expected == actual else {
            throw AppPackagingError.piHashMismatch(expected: expected, actual: actual)
        }
    }

    /// Reads the expected PI version from the packaged, validated manifest.
    private func readPiVersion(layout: AppBundleLayout) throws -> String {
        let manifestURL = layout.piRuntimeRoot.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        guard let manifest = try? JSONDecoder().decode(
            PiRuntimeManifest.self,
            from: Data(contentsOf: manifestURL)
        ),
        manifest.schemaVersion == 1,
        !manifest.piVersion.isEmpty else {
            throw AppPackagingError.invalidPiManifest(manifestURL)
        }
        return manifest.piVersion
    }

    /// Retries the PI version probe to tolerate initial macOS execution setup.
    private func verifyPiVersion(_ executable: URL, expected: String) async throws {
        var lastOutput = ""
        for attempt in 0..<10 {
            let result = try await processExecutor.execute(
                ProcessExecutionRequest(
                    executableURL: executable,
                    arguments: ["--version"],
                    timeout: .seconds(15)
                )
            )
            lastOutput = (result.standardOutput?.stringUTF8 ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if result.succeeded, lastOutput == expected {
                return
            }
            if attempt < 9 {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw AppPackagingError.piVersionMismatch(expected: expected, actual: lastOutput)
    }

    /// Extracts the first Mach-O UUID reported by dwarfdump.
    private func executableUUID(_ executable: URL) async throws -> String {
        let result = try await execute(
            executable: "/usr/bin/dwarfdump",
            arguments: ["--uuid", executable.path],
            timeout: .seconds(15)
        )
        guard result.succeeded else {
            throw AppPackagingError.processFailed(
                tool: "dwarfdump",
                exitCode: result.exitCode ?? -1,
                standardError: result.standardError?.stringUTF8 ?? ""
            )
        }
        let firstLine = (result.standardOutput?.stringUTF8 ?? "")
            .split(whereSeparator: \.isNewline)
            .first
        let uuid = firstLine?
            .split(whereSeparator: \.isWhitespace)
            .dropFirst()
            .first
            .map(String.init) ?? ""
        guard !uuid.isEmpty else {
            throw AppPackagingError.binaryUUIDMismatch(
                expected: "Mach-O UUID",
                actual: ""
            )
        }
        return uuid
    }

    /// Runs a system validator command and throws a packaging error on failure.
    private func requireSuccess(
        executable: String,
        arguments: [String],
        tool: String
    ) async throws {
        let result = try await execute(
            executable: executable,
            arguments: arguments,
            timeout: .seconds(60)
        )
        guard result.succeeded else {
            throw AppPackagingError.processFailed(
                tool: tool,
                exitCode: result.exitCode ?? -1,
                standardError: result.standardError?.stringUTF8 ?? ""
            )
        }
    }

    /// Constructs a bounded request for one absolute macOS system executable.
    private func execute(
        executable: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> ProcessExecutionResult {
        try await processExecutor.execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: executable),
                arguments: arguments,
                timeout: timeout
            )
        )
    }
}
