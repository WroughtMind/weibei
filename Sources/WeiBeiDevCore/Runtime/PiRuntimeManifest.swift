import Foundation

/// A supported embedded PI runtime architecture.
public enum PiRuntimeArchitecture: String, CaseIterable, Codable, Sendable {
    case arm64
    case x86_64

    /// The artifact key used by the vendor manifest.
    public var artifactKey: String {
        switch self {
        case .arm64:
            return "darwin-arm64"
        case .x86_64:
            return "darwin-x64"
        }
    }

    /// The architecture of the current Swift process.
    public static var host: PiRuntimeArchitecture {
#if arch(arm64)
        return .arm64
#elseif arch(x86_64)
        return .x86_64
#else
#error("WeiBeiDevTool only supports arm64 and x86_64 macOS hosts")
#endif
    }
}

/// Download metadata for one architecture-specific PI runtime archive.
public struct PiRuntimeArtifact: Codable, Equatable, Sendable {
    /// Release archive file name.
    public let archive: String

    /// Manifest-pinned lowercase SHA-256 of the release archive.
    public let sha256: String

    /// Creates architecture-specific archive metadata.
    ///
    /// - Parameters:
    ///   - archive: Release archive file name.
    ///   - sha256: Expected lowercase SHA-256 of the archive.
    public init(archive: String, sha256: String) {
        self.archive = archive
        self.sha256 = sha256
    }
}

/// The complete preparation-side representation of `Vendor/PiRuntime/manifest.json`.
public struct PiRuntimeVendorManifest: Codable, Equatable, Sendable {
    /// Manifest schema version understood by preparation and application runtimes.
    public let schemaVersion: Int

    /// Pinned PI runtime release version.
    public let piVersion: String

    /// HTTPS repository from which release archives are downloaded.
    public let sourceRepository: String

    /// Source commit used to build the pinned runtime.
    public let sourceCommit: String

    /// License identifier required for redistribution.
    public let license: String

    /// Architecture-keyed release artifact metadata.
    public let artifacts: [String: PiRuntimeArtifact]

    /// Creates a vendor manifest.
    public init(
        schemaVersion: Int,
        piVersion: String,
        sourceRepository: String,
        sourceCommit: String,
        license: String,
        artifacts: [String: PiRuntimeArtifact]
    ) {
        self.schemaVersion = schemaVersion
        self.piVersion = piVersion
        self.sourceRepository = sourceRepository
        self.sourceCommit = sourceCommit
        self.license = license
        self.artifacts = artifacts
    }

    /// Loads and validates the PI vendor manifest at the supplied URL.
    ///
    /// - Parameter url: Manifest file URL.
    /// - Returns: A validated manifest.
    public static func load(from url: URL) throws -> PiRuntimeVendorManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PiRuntimePreparationError.manifestUnreadable(url, error)
        }

        let manifest: PiRuntimeVendorManifest
        do {
            manifest = try JSONDecoder().decode(PiRuntimeVendorManifest.self, from: data)
        } catch {
            throw PiRuntimePreparationError.manifestInvalid("cannot decode \(url.path): \(error.localizedDescription)")
        }
        try manifest.validate()
        return manifest
    }

    /// Returns the artifact for a supported architecture.
    ///
    /// - Parameter architecture: Requested host architecture.
    /// - Returns: The matching release artifact.
    public func artifact(for architecture: PiRuntimeArchitecture) throws -> PiRuntimeArtifact {
        guard let artifact = artifacts[architecture.artifactKey] else {
            throw PiRuntimePreparationError.manifestInvalid("missing artifact \(architecture.artifactKey)")
        }
        return artifact
    }

    /// Validates all fields that form the preparation and runtime integrity contract.
    public func validate() throws {
        guard schemaVersion == 1 else {
            throw PiRuntimePreparationError.manifestInvalid("unsupported schema version \(schemaVersion)")
        }
        let versionCharacters = CharacterSet(charactersIn: "0123456789.-")
        guard !piVersion.isEmpty,
              !piVersion.contains(".."),
              piVersion.unicodeScalars.allSatisfy(versionCharacters.contains),
              URL(fileURLWithPath: piVersion).lastPathComponent == piVersion else {
            throw PiRuntimePreparationError.manifestInvalid("piVersion must be a safe numeric release token")
        }
        guard let repositoryURL = URL(string: sourceRepository),
              repositoryURL.scheme == "https",
              repositoryURL.host != nil else {
            throw PiRuntimePreparationError.manifestInvalid("sourceRepository must be an HTTPS URL")
        }
        guard sourceCommit.count == 40, sourceCommit.allSatisfy(\.isHexDigit) else {
            throw PiRuntimePreparationError.manifestInvalid("sourceCommit must be a 40-character hexadecimal commit")
        }
        guard license == "MIT" else {
            throw PiRuntimePreparationError.manifestInvalid("PI runtime license must be MIT")
        }
        for architecture in PiRuntimeArchitecture.allCases {
            let artifact = try artifact(for: architecture)
            guard !artifact.archive.isEmpty,
                  artifact.archive == URL(fileURLWithPath: artifact.archive).lastPathComponent,
                  !artifact.archive.contains("/") else {
                throw PiRuntimePreparationError.manifestInvalid("\(architecture.artifactKey) archive must be a file name")
            }
            guard artifact.sha256.count == 64,
                  artifact.sha256 == artifact.sha256.lowercased(),
                  artifact.sha256.allSatisfy(\.isHexDigit) else {
                throw PiRuntimePreparationError.manifestInvalid("\(architecture.artifactKey) SHA-256 must be 64 lowercase hexadecimal characters")
            }
        }
    }
}
