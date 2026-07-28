import Foundation

/// Absolute Node.js executable paths used by web-resource workflows.
public struct NodeBuildToolchain: Equatable, Sendable {
    /// Node.js executable used for version checks.
    public let node: URL
    /// npm executable used for locked installation and resource builds.
    public let npm: URL

    /// Creates a Node.js toolchain from explicitly resolved executable paths.
    public init(node: URL, npm: URL) {
        self.node = node
        self.npm = npm
    }

    /// Resolves Node.js and npm from the inherited `PATH`.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> NodeBuildToolchain {
        NodeBuildToolchain(
            node: try resolveExecutable(named: "node", environment: environment, fileManager: fileManager),
            npm: try resolveExecutable(named: "npm", environment: environment, fileManager: fileManager)
        )
    }
}

/// Absolute executable paths used by repository build workflows.
public struct BuildToolchain: Equatable, Sendable {
    /// Node.js executable used for version checks.
    public let node: URL
    /// npm executable used for locked installation and resource builds.
    public let npm: URL
    /// Swift executable used for SwiftPM builds and tests.
    public let swift: URL

    /// Creates a build toolchain from explicitly resolved executable paths.
    ///
    /// - Parameters:
    ///   - node: Absolute path to the Node.js executable.
    ///   - npm: Absolute path to the npm executable.
    ///   - swift: Absolute path to the Swift executable.
    public init(node: URL, npm: URL, swift: URL) {
        self.node = node
        self.npm = npm
        self.swift = swift
    }

    /// Resolves required build executables from the inherited `PATH`.
    ///
    /// - Parameters:
    ///   - environment: Environment whose `PATH` is searched.
    ///   - fileManager: File manager used to confirm executable permissions.
    /// - Returns: Absolute paths for Node.js, npm, and Swift.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> BuildToolchain {
        let nodeToolchain = try NodeBuildToolchain.resolve(
            environment: environment,
            fileManager: fileManager
        )
        return BuildToolchain(
            node: nodeToolchain.node,
            npm: nodeToolchain.npm,
            swift: try resolveExecutable(named: "swift", environment: environment, fileManager: fileManager)
        )
    }
}

/// Resolves one executable from `PATH` without invoking a shell.
private func resolveExecutable(
    named name: String,
    environment: [String: String],
    fileManager: FileManager
) throws -> URL {
    let searchPath = environment["PATH"] ?? ""
    for directory in searchPath.split(separator: ":", omittingEmptySubsequences: false) {
        let baseDirectory = directory.isEmpty ? "." : String(directory)
        let candidate = URL(fileURLWithPath: baseDirectory, isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
            .standardizedFileURL
        if fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
    }
    throw BuildWorkflowError.missingExecutable(name)
}

/// Build mode used by SwiftPM workflows.
public enum SwiftBuildConfiguration: String, CaseIterable, Sendable {
    /// Debug products used by the repository check.
    case debug
    /// Optimized products used by run, verification, and packaging.
    case release
}
