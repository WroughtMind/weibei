import Foundation

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

}
