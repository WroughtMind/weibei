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
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath().standardizedFileURL
        }

        var existing = standardized
        var missing: [String] = []
        while existing.path != "/", existing.path != "",
              !FileManager.default.fileExists(atPath: existing.path) {
            let component = existing.lastPathComponent
            if !component.isEmpty, component != "/" {
                missing.insert(component, at: 0)
            }
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { break }
            existing = parent
        }

        var resolved = existing.resolvingSymlinksInPath().standardizedFileURL
        for component in missing {
            resolved.appendPathComponent(component, isDirectory: true)
        }
        return resolved.standardizedFileURL
    }

    static func isSameOrInside(root: URL, candidate: URL) -> Bool {
        let rootComponents = canonicalize(root).pathComponents
        let candidateComponents = canonicalize(candidate).pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
