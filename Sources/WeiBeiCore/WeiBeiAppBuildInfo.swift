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

/// Remote channel used by tier-0 “check for updates” (prompt only, no silent install).
public struct WeiBeiUpdateManifest: Equatable, Sendable, Codable {
    public var version: String
    public var build: Int
    public var commit: String
    public var url: String
    public var notes: String?

    public init(version: String, build: Int, commit: String, url: String, notes: String? = nil) {
        self.version = version
        self.build = build
        self.commit = commit
        self.url = url
        self.notes = notes
    }

    public var shortCommit: String {
        let trimmed = commit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return trimmed.isEmpty ? "—" : trimmed }
        return String(trimmed.prefix(8))
    }

    public var downloadURL: URL? {
        URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum WeiBeiUpdateCheckResult: Equatable, Sendable {
    case upToDate(local: WeiBeiAppBuildInfo, remote: WeiBeiUpdateManifest)
    case updateAvailable(local: WeiBeiAppBuildInfo, remote: WeiBeiUpdateManifest)
    case failed(String)
}

public enum WeiBeiUpdateChecker {
    /// Canonical channel: repo `Docs/releases/latest.json` on `main`.
    public static let defaultManifestURL = URL(
        string: "https://raw.githubusercontent.com/weibei-app/weibei/main/Docs/releases/latest.json"
    )!

    /// Fallback listing page when the manifest URL is missing or invalid.
    public static let defaultReleasesPageURL = URL(
        string: "https://github.com/weibei-app/weibei/releases"
    )!

    /// Isolation-only override key. Never read outside verification runs.
    public static let candidateManifestURLEnvironmentKey = "WEIBEI_UPDATE_MANIFEST_URL"
    /// Same activation gate used by scripted app verification.
    public static let suppressActivationEnvironmentKey = "WEIBEI_SUPPRESS_ACTIVATION"

    /// Public channel, or a verification-only candidate manifest when isolation is active.
    ///
    /// `WEIBEI_UPDATE_MANIFEST_URL` is ignored unless `WEIBEI_SUPPRESS_ACTIVATION=1`, so a
    /// normal user session cannot be redirected away from the public channel.
    public static func resolvedManifestURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        guard environment[suppressActivationEnvironmentKey] == "1" else {
            return defaultManifestURL
        }
        let raw = environment[candidateManifestURLEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" || scheme == "file"
        else {
            return defaultManifestURL
        }
        return url
    }

    public static func compare(
        local: WeiBeiAppBuildInfo,
        remote: WeiBeiUpdateManifest
    ) -> WeiBeiUpdateCheckResult {
        if remote.build > local.build {
            return .updateAvailable(local: local, remote: remote)
        }
        return .upToDate(local: local, remote: remote)
    }

    public static func check(
        local: WeiBeiAppBuildInfo = .current(),
        manifestURL: URL? = nil,
        session: URLSession = .shared
    ) async -> WeiBeiUpdateCheckResult {
        let resolvedURL = manifestURL ?? resolvedManifestURL()
        do {
            var request = URLRequest(url: resolvedURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 12
            request.setValue("WeiBei-UpdateCheck", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed("HTTP \(http.statusCode)")
            }
            let decoder = JSONDecoder()
            let remote = try decoder.decode(WeiBeiUpdateManifest.self, from: data)
            guard remote.build > 0, !remote.version.isEmpty, remote.downloadURL != nil else {
                return .failed("invalid update manifest")
            }
            return compare(local: local, remote: remote)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
