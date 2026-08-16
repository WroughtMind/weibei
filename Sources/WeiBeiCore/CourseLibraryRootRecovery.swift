import Foundation

/// Finds this computer's course library without a hardcoded user path.
/// Bookmarks are machine- and signature-specific; relative course folders
/// (`test/文稿/paper.pdf`) plus this user's Documents library are what travel.
public enum CourseLibraryRootRecovery {
    public static func candidates(
        storedPath: String?,
        defaultRoot: URL,
        includePerUserDefault: Bool
    ) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            let path = standardized.path
            guard !path.isEmpty, seen.insert(path).inserted else { return }
            result.append(standardized)
        }
        if let storedPath, !storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(URL(fileURLWithPath: storedPath, isDirectory: true))
        }
        guard includePerUserDefault else { return result }
        add(defaultRoot)
        if let storedPath {
            let name = URL(fileURLWithPath: storedPath, isDirectory: true).lastPathComponent
            if !name.isEmpty, name != ".", name != ".." {
                add(
                    defaultRoot
                        .deletingLastPathComponent()
                        .appendingPathComponent(name, isDirectory: true)
                )
            }
        }
        return result
    }

    /// Same-volume inode still wins. On another Mac those numbers change, so a
    /// library that already contains this workspace's course folders is enough.
    public static func shouldAccept(
        liveIdentity: ImportedFileIdentity?,
        expectedIdentity: ImportedFileIdentity?,
        matchingRegisteredCourseCount: Int
    ) -> Bool {
        if let liveIdentity, let expectedIdentity,
           expectedIdentity.matchesAcrossVolumeDrift(liveIdentity) {
            return true
        }
        return matchingRegisteredCourseCount > 0
    }
}
