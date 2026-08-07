import Foundation

/// On-disk locations owned by WeiBei for Agent credentials.
///
/// Intentionally **not** `~/.pi/agent` — terminal Pi keeps its own files;
/// WeiBei keeps a separate store under Application Support so opening the app
/// never depends on (or rewrites) the user's CLI Pi config.
public enum WeiBeiAgentDataPaths {
    public static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("com.changfenhuang.weibei", isDirectory: true)
    }

    /// Pi-format agent config owned by WeiBei (auth.json, settings.json, …).
    public static var piAgentDirectory: URL {
        applicationSupportRoot.appendingPathComponent("PiAgent", isDirectory: true)
    }

    /// Ensure the PiAgent directory exists with private permissions.
    @discardableResult
    public static func ensurePiAgentDirectory() throws -> URL {
        let dir = piAgentDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

}
