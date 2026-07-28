import Foundation

/// Describes the repository paths used by developer workflows.
public struct RepositoryLayout: Equatable, Sendable {
    /// Canonical repository root directory.
    public let rootDirectory: URL

    /// SwiftPM package manifest.
    public var packageManifest: URL {
        rootDirectory.appendingPathComponent("Package.swift", isDirectory: false)
    }

    /// Root npm package manifest.
    public var packageJSON: URL {
        rootDirectory.appendingPathComponent("package.json", isDirectory: false)
    }

    /// Locked npm dependency graph.
    public var packageLock: URL {
        rootDirectory.appendingPathComponent("package-lock.json", isDirectory: false)
    }

    /// Root installation directory managed by npm.
    public var nodeModulesDirectory: URL {
        rootDirectory.appendingPathComponent("node_modules", isDirectory: true)
    }

    /// Stamp recording the inputs used by the current npm installation.
    public var nodePreparationStamp: URL {
        nodeModulesDirectory.appendingPathComponent(".weibei-install-state.json", isDirectory: false)
    }

    /// Product semantic-version source.
    public var versionFile: URL {
        rootDirectory.appendingPathComponent("VERSION", isDirectory: false)
    }

    /// Main WeiBei executable target sources.
    public var productSourcesDirectory: URL {
        rootDirectory.appendingPathComponent("Sources/WeiBei", isDirectory: true)
    }

    /// Generated browser resources embedded in the application.
    public var editorResourcesDirectory: URL {
        productSourcesDirectory.appendingPathComponent("Resources/Editor", isDirectory: true)
    }

    /// Creates a validated layout for the current working directory.
    ///
    /// The developer tool intentionally supports only invocations made at the
    /// repository root so that build inputs and generated output paths cannot
    /// silently resolve against a parent or sibling checkout.
    ///
    /// - Parameters:
    ///   - currentDirectory: Directory from which the command was invoked.
    ///   - fileManager: File manager used to validate the repository markers.
    /// - Returns: A repository layout rooted at `currentDirectory`.
    public static func locate(
        currentDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> RepositoryLayout {
        let root = currentDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let layout = RepositoryLayout(rootDirectory: root)
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: layout.packageManifest.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw RepositoryLayoutError.notRepositoryRoot(
                currentDirectory: root,
                missingMarker: "Package.swift"
            )
        }

        guard fileManager.fileExists(atPath: layout.versionFile.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw RepositoryLayoutError.notRepositoryRoot(
                currentDirectory: root,
                missingMarker: "VERSION"
            )
        }

        guard fileManager.fileExists(atPath: layout.productSourcesDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw RepositoryLayoutError.notRepositoryRoot(
                currentDirectory: root,
                missingMarker: "Sources/WeiBei"
            )
        }

        return layout
    }
}

/// Reports why the current directory cannot be used as the repository root.
public enum RepositoryLayoutError: Error, Equatable, LocalizedError, Sendable {
    case notRepositoryRoot(currentDirectory: URL, missingMarker: String)

    /// Stable code exposed in structured CLI errors.
    public var errorCode: String {
        "repository_root_required"
    }

    /// Human-readable repository discovery failure.
    public var errorDescription: String? {
        switch self {
        case let .notRepositoryRoot(currentDirectory, missingMarker):
            return "Run WeiBeiDevTool from the repository root. Missing \(missingMarker) in \(currentDirectory.path)."
        }
    }
}
