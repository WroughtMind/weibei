import Foundation

/// Build identity stamped into the packaged app (`Info.plist`).
public struct WeiBeiAppBuildInfo: Equatable, Sendable {
    public var version: String
    public var build: Int
    public var commit: String
    public var isDirty: Bool

    public init(version: String, build: Int, commit: String, isDirty: Bool) {
        self.version = version
        self.build = build
        self.commit = commit
        self.isDirty = isDirty
    }

    public var shortCommit: String {
        let trimmed = commit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "—" : trimmed }
        return String(trimmed.prefix(8))
    }

    public var displayLine: String {
        var parts = ["\(version) (\(build))", shortCommit]
        if isDirty { parts.append("dirty") }
        return parts.joined(separator: " · ")
    }

    public static func current(bundle: Bundle = .main) -> WeiBeiAppBuildInfo {
        let info = bundle.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildRaw = (info["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (info["CFBundleVersion"] as? NSNumber)?.stringValue
        let commit = (info["WeiBeiGitCommit"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dirty: Bool = {
            if let flag = info["WeiBeiSourceDirty"] as? Bool { return flag }
            if let number = info["WeiBeiSourceDirty"] as? NSNumber { return number.boolValue }
            return false
        }()
        return WeiBeiAppBuildInfo(
            version: (version?.isEmpty == false) ? version! : "0.0.0",
            build: Int(buildRaw ?? "") ?? 0,
            commit: commit,
            isDirty: dirty
        )
    }
}
