import Foundation

/// Decides whether a course-library root sits on a location the system may delete.
///
/// Comparison is by resolved path components, not string prefix, so `/tmp-safe`
/// is not treated as a child of `/tmp`.
public enum CourseLibraryVolatility {
    public static func isVolatilePersistenceRoot(_ url: URL) -> Bool {
        let resolved = canonicalize(url)
        return volatileRoots().contains { root in
            isSameOrInside(root: root, candidate: resolved)
        }
    }

    public static func volatileRoots() -> [URL] {
        [
            canonicalize(URL(fileURLWithPath: "/private/tmp", isDirectory: true)),
            canonicalize(URL(fileURLWithPath: "/private/var/folders", isDirectory: true)),
            canonicalize(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Caches", isDirectory: true)
            ),
            canonicalize(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
        ]
    }

    static func canonicalize(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    static func isSameOrInside(root: URL, candidate: URL) -> Bool {
        let rootComponents = canonicalize(root).pathComponents
        let candidateComponents = canonicalize(candidate).pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
