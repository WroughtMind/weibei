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

    /// API keys (0600 files), one file per service/account.
    public static var secretsDirectory: URL {
        applicationSupportRoot.appendingPathComponent("Secrets", isDirectory: true)
    }

    /// Pi-format agent config owned by WeiBei (auth.json, settings.json, …).
    public static var piAgentDirectory: URL {
        applicationSupportRoot.appendingPathComponent("PiAgent", isDirectory: true)
    }

    public static var piAuthJSON: URL {
        piAgentDirectory.appendingPathComponent("auth.json")
    }

    public static var piSettingsJSON: URL {
        piAgentDirectory.appendingPathComponent("settings.json")
    }

    /// Ensure the PiAgent directory exists with private permissions.
    @discardableResult
    public static func ensurePiAgentDirectory() throws -> URL {
        let dir = piAgentDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// One-time migration: if WeiBei has no OAuth auth yet but `~/.pi/agent/auth.json`
    /// does, copy it once so existing logins keep working without ongoing CLI sharing.
    public static func migrateHomePiAuthIfNeeded() {
        let fileManager = FileManager.default
        let destination = piAuthJSON
        if let existing = try? Data(contentsOf: destination), !existing.isEmpty {
            return
        }
        let homeAuth = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/auth.json")
        guard let data = try? Data(contentsOf: homeAuth),
              data.count <= 1_048_576,
              data.count > 2 else { return }
        try? ensurePiAgentDirectory()
        try? data.write(to: destination, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
