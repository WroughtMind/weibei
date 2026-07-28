import Foundation

/// Inputs controlling one deterministic PI runtime preparation.
public struct PiRuntimePreparationConfiguration: Sendable {
    /// Repository root containing Vendor/PiRuntime and the local `.build` cache.
    public let repositoryRoot: URL

    /// Architecture-specific runtime to prepare.
    public let architecture: PiRuntimeArchitecture

    /// Optional pinned archive supplied by the caller instead of downloading.
    public let archiveURL: URL?

    /// Cache serialization timing behavior.
    public let lock: PiRuntimeCacheLockConfiguration

    /// Number of attempts made for URLSession release downloads.
    public let downloadAttempts: Int

    /// Creates PI runtime preparation inputs.
    ///
    /// - Parameters:
    ///   - repositoryRoot: WeiBei repository root; the cache is always placed below its `.build` directory.
    ///   - architecture: Runtime architecture to prepare.
    ///   - archiveURL: Optional caller-supplied archive, primarily for offline development and tests.
    ///   - lock: Cache lock timing behavior.
    ///   - downloadAttempts: Number of URLSession download attempts for a remote release.
    public init(
        repositoryRoot: URL,
        architecture: PiRuntimeArchitecture = .host,
        archiveURL: URL? = nil,
        lock: PiRuntimeCacheLockConfiguration = PiRuntimeCacheLockConfiguration(),
        downloadAttempts: Int = 3
    ) {
        self.repositoryRoot = repositoryRoot.standardizedFileURL
        self.architecture = architecture
        self.archiveURL = archiveURL?.standardizedFileURL
        self.lock = lock
        self.downloadAttempts = max(downloadAttempts, 1)
    }
}

/// A validated PI runtime ready to be copied into an application bundle.
public struct PreparedPiRuntime: Equatable, Sendable {
    /// Root of the validated `PiRuntime` directory.
    public let directoryURL: URL

    /// Validated `bin/pi` executable.
    public let executableURL: URL

    /// Authoritative vendor manifest represented by this runtime.
    public let manifest: PiRuntimeVendorManifest

    /// Mach-O architecture verified in the executable.
    public let architecture: PiRuntimeArchitecture

    /// Creates a description of a validated runtime.
    public init(
        directoryURL: URL,
        executableURL: URL,
        manifest: PiRuntimeVendorManifest,
        architecture: PiRuntimeArchitecture
    ) {
        self.directoryURL = directoryURL
        self.executableURL = executableURL
        self.manifest = manifest
        self.architecture = architecture
    }
}

struct PiRuntimeRepositoryPaths {
    let root: URL

    var manifest: URL {
        root.appendingPathComponent("Vendor/PiRuntime/manifest.json")
    }

    var license: URL {
        root.appendingPathComponent("Vendor/PiRuntime/LICENSE")
    }

    var notices: URL {
        root.appendingPathComponent("Vendor/PiRuntime/THIRD_PARTY_NOTICES.md")
    }

    var cache: URL {
        root.appendingPathComponent(".build/pi-runtime", isDirectory: true)
    }

    /// Confirms the preparation inputs exist at the configured repository root.
    func validate(fileManager: FileManager) throws {
        let requiredFiles = [manifest, license, notices]
        guard requiredFiles.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw PiRuntimePreparationError.repositoryLayoutInvalid(root)
        }
    }
}

struct PiRuntimeCachePaths {
    let cacheRoot: URL
    let version: String
    let architecture: PiRuntimeArchitecture
    let archiveName: String

    var downloads: URL {
        cacheRoot.appendingPathComponent("downloads", isDirectory: true)
    }

    var downloadedArchive: URL {
        downloads.appendingPathComponent(archiveName)
    }

    var runtimeParent: URL {
        cacheRoot
            .appendingPathComponent(version, isDirectory: true)
            .appendingPathComponent(architecture.artifactKey, isDirectory: true)
    }

    var runtime: URL {
        runtimeParent.appendingPathComponent("PiRuntime", isDirectory: true)
    }

    var lock: URL {
        cacheRoot.appendingPathComponent(".prepare-\(architecture.artifactKey).lock", isDirectory: true)
    }
}
