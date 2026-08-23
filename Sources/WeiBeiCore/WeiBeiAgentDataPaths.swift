import Foundation

public enum WeiBeiAgentDataPathError: Error, Equatable {
    case outsideWorkspace
}

/// On-disk locations owned by WeiBei for Agent credentials.
public enum WeiBeiAgentDataPaths {
    public static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("com.changfenhuang.weibei", isDirectory: true)
    }

    public static var nativeAgentDirectory: URL {
        applicationSupportRoot.appendingPathComponent("NativeAgent", isDirectory: true)
    }

    @discardableResult
    public static func ensureNativeAgentDirectory() throws -> URL {
        let dir = nativeAgentDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Creates an Agent-owned directory only when its real path remains inside
    /// the workspace. This rejects pre-existing symlinks that redirect writes.
    @discardableResult
    public static func ensureOwnedDirectory(
        _ directory: URL,
        inside workspaceRoot: URL
    ) throws -> URL {
        let declaredRoot = workspaceRoot.standardizedFileURL
        let declaredDirectory = directory.standardizedFileURL
        guard contains(declaredDirectory, inside: declaredRoot) else {
            throw WeiBeiAgentDataPathError.outsideWorkspace
        }

        let resolvedRoot = declaredRoot.resolvingSymlinksInPath().standardizedFileURL
        guard contains(
            declaredDirectory.resolvingSymlinksInPath().standardizedFileURL,
            inside: resolvedRoot
        ) else {
            throw WeiBeiAgentDataPathError.outsideWorkspace
        }

        try FileManager.default.createDirectory(
            at: declaredDirectory,
            withIntermediateDirectories: true
        )
        guard contains(
            declaredDirectory.resolvingSymlinksInPath().standardizedFileURL,
            inside: resolvedRoot
        ) else {
            throw WeiBeiAgentDataPathError.outsideWorkspace
        }
        return declaredDirectory
    }

    private static func contains(_ child: URL, inside root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let childComponents = child.pathComponents
        return childComponents.count > rootComponents.count
            && childComponents.prefix(rootComponents.count).elementsEqual(rootComponents)
    }

}
