import Foundation

public enum WeiBeiFeedbackLink {
    public static let newIssue = URL(string: "https://github.com/WroughtMind/weibei/issues/new")!

    /// GitHub prefills `title` and `body` on the new-issue form. No label is sent.
    public static func prefilled(title: String, body: String) -> URL? {
        var components = URLComponents(url: newIssue, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
        ]
        return components?.url
    }
}

/// Build identity stamped into the packaged app (`Info.plist`).
public struct WeiBeiAppBuildInfo: Equatable, Sendable {
    public var version: String
    public var build: String
    public var commit: String
    public var isDirty: Bool

    public init(version: String, build: String, commit: String, isDirty: Bool) {
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

    public var buildDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd.HHmm.ss"
        formatter.isLenient = false
        guard let date = formatter.date(from: build), formatter.string(from: date) == build else { return nil }
        return date
    }

    /// Public version row: version and build number only.
    public var displayLine: String {
        let buildLabel = build.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !buildLabel.isEmpty else { return version }
        return "\(version) (\(buildLabel))"
    }

    /// Commit and dirty state travel with copied diagnostics, not the public version row.
    public var diagnosticLine: String {
        var parts = [displayLine]
        if !shortCommit.isEmpty, shortCommit != "—" { parts.append(shortCommit) }
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
            build: buildRaw ?? "",
            commit: commit,
            isDirty: dirty
        )
    }
}
