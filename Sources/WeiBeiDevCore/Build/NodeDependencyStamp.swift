import CryptoKit
import Foundation

/// Records the inputs that produced the current locked Node.js installation.
public struct NodeDependencyStamp: Codable, Equatable, Sendable {
    /// Complete Node.js version used by npm.
    public let nodeVersion: NodeVersion
    /// Lowercase SHA-256 digest of `package-lock.json`.
    public let packageLockSHA256: String
    /// Lowercase SHA-256 digest of `package.json`.
    public let packageJSONSHA256: String

    /// Creates a stamp for one Node.js version and both npm manifest digests.
    public init(nodeVersion: NodeVersion, packageLockSHA256: String, packageJSONSHA256: String) {
        self.nodeVersion = nodeVersion
        self.packageLockSHA256 = packageLockSHA256
        self.packageJSONSHA256 = packageJSONSHA256
    }
}

/// Reads and writes the deterministic Node dependency installation stamp.
public struct NodeDependencyStampStore: Sendable {
    /// Creates a stamp store.
    public init() {}

    /// Creates the expected stamp for the active Node.js version and npm manifests.
    ///
    /// - Parameters:
    ///   - nodeVersion: Active supported Node.js version.
    ///   - packageJSON: Root npm package manifest.
    ///   - packageLock: Repository package lockfile.
    /// - Returns: Stamp describing the locked dependency installation inputs.
    public func expectedStamp(
        nodeVersion: NodeVersion,
        packageJSON: URL,
        packageLock: URL
    ) throws -> NodeDependencyStamp {
        guard FileManager.default.fileExists(atPath: packageJSON.path) else {
            throw BuildWorkflowError.missingRequiredFile(packageJSON)
        }
        guard FileManager.default.fileExists(atPath: packageLock.path) else {
            throw BuildWorkflowError.missingRequiredFile(packageLock)
        }
        let packageData = try Data(contentsOf: packageJSON)
        let lockData = try Data(contentsOf: packageLock)
        let packageDigest = SHA256.hash(data: packageData).map { String(format: "%02x", $0) }.joined()
        let lockDigest = SHA256.hash(data: lockData).map { String(format: "%02x", $0) }.joined()
        return NodeDependencyStamp(
            nodeVersion: nodeVersion,
            packageLockSHA256: lockDigest,
            packageJSONSHA256: packageDigest
        )
    }

    /// Determines whether `npm ci` must recreate the locked installation.
    ///
    /// A missing, malformed, or stale stamp is treated as a cache miss rather
    /// than an error because `npm ci` can safely recreate the entire directory.
    ///
    /// - Parameters:
    ///   - expectedStamp: Stamp for the current Node.js and lockfile inputs.
    ///   - stampURL: Installed dependency stamp location.
    /// - Returns: `true` when npm must reinstall locked dependencies.
    public func needsInstallation(
        expectedStamp: NodeDependencyStamp,
        stampURL: URL
    ) -> Bool {
        guard let data = try? Data(contentsOf: stampURL),
              let installedStamp = try? JSONDecoder().decode(NodeDependencyStamp.self, from: data)
        else {
            return true
        }
        return installedStamp != expectedStamp
    }

    /// Persists the stamp after `npm ci` succeeds.
    ///
    /// - Parameters:
    ///   - stamp: Inputs represented by the completed installation.
    ///   - stampURL: Stamp path under `node_modules`.
    public func write(_ stamp: NodeDependencyStamp, to stampURL: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(stamp)
            try FileManager.default.createDirectory(
                at: stampURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: stampURL, options: .atomic)
        } catch {
            throw BuildWorkflowError.preparationStampWriteFailed(stampURL, error.localizedDescription)
        }
    }
}
