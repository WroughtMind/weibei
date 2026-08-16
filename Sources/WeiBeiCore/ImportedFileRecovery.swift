import Foundation

/// Decision helper for the existing imported-file recovery chain.
///
/// Callers still own bookmarks, security scopes, and persistence. This type
/// only answers whether a stored identity may bind to a candidate URL.
public enum ImportedFileRecovery {
    public enum Source: Equatable, Sendable {
        case currentPath
        case bookmark
        case lastKnownPath
    }

    public enum Outcome: Equatable, Sendable {
        case resolved(url: URL, identity: ImportedFileIdentity, via: Source)
        case identityConflict(url: URL)
        case missing
    }

    public static func resolve(
        storedIdentity: ImportedFileIdentity,
        currentPath: String?,
        lastKnownPath: String?,
        bookmarkURL: URL?,
        identityAt: (URL) -> ImportedFileIdentity?
    ) -> Outcome {
        let currentURL = currentPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        if let currentURL,
           let identity = identityAt(currentURL),
           identity.matchesAcrossVolumeDrift(storedIdentity) {
            return .resolved(url: currentURL, identity: identity, via: .currentPath)
        }

        if let bookmarkURL {
            let resolvedBookmark = bookmarkURL.standardizedFileURL
            if let identity = identityAt(resolvedBookmark),
               identity.matchesAcrossVolumeDrift(storedIdentity) {
                return .resolved(
                    url: resolvedBookmark,
                    identity: identity,
                    via: .bookmark
                )
            }
        }

        guard let lastKnownPath else { return .missing }
        let fallbackURL = URL(fileURLWithPath: lastKnownPath).standardizedFileURL
        if let currentURL, fallbackURL == currentURL {
            return .missing
        }
        guard let identity = identityAt(fallbackURL) else { return .missing }
        if identity.matchesAcrossVolumeDrift(storedIdentity) {
            return .resolved(
                url: fallbackURL,
                identity: identity,
                via: .lastKnownPath
            )
        }
        return .identityConflict(url: fallbackURL)
    }

    public enum LocationAvailability: Equatable, Sendable {
        case present
        case absent
        case inaccessible
    }

    /// Only a confirmed-absent file under a present parent may drop.
    public static func shouldForgetGoneSource(
        file: LocationAvailability,
        parent: LocationAvailability,
        isSample: Bool
    ) -> Bool {
        !isSample && file == .absent && parent == .present
    }
}
