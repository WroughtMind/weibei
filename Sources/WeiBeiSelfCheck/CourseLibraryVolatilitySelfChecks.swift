import Foundation
import WeiBeiCore

func checkCourseLibraryVolatility() {
    let fileManager = FileManager.default
    let unique = UUID().uuidString

    let documents = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
    expect(
        !CourseLibraryVolatility.isVolatilePersistenceRoot(documents),
        "Documents must not be treated as a volatile library root"
    )

    let applicationSupport = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support", isDirectory: true)
    expect(
        !CourseLibraryVolatility.isVolatilePersistenceRoot(applicationSupport),
        "Application Support must not be treated as Library/Caches"
    )

    expect(
        !CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: "/tmp-safe", isDirectory: true)
        ),
        "/tmp-safe must not match /tmp by string prefix"
    )
    expect(
        !CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: "/private/tmp-safe", isDirectory: true)
        ),
        "/private/tmp-safe must not match /private/tmp by string prefix"
    )

    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        ),
        "/private/tmp is a volatile root"
    )
    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: "/tmp", isDirectory: true)
        ),
        "/tmp must resolve to the /private/tmp volatile root"
    )
    let missingTmpChild = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        .appendingPathComponent("weibei-vol-missing-\(unique)", isDirectory: true)
    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(missingTmpChild),
        "a missing subdirectory of /private/tmp is still volatile after prefix normalization"
    )

    let existingTmpChild = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        .appendingPathComponent("weibei-vol-\(unique)", isDirectory: true)
    do {
        try fileManager.createDirectory(at: existingTmpChild, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: existingTmpChild) }
        expect(
            CourseLibraryVolatility.isVolatilePersistenceRoot(existingTmpChild),
            "a subdirectory of /private/tmp is volatile"
        )
    } catch {
        expect(false, "could not create /private/tmp subdirectory fixture: \(error)")
    }

    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: "/private/var/folders", isDirectory: true)
        ),
        "/private/var/folders is a volatile root"
    )
    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: "/var/folders", isDirectory: true)
        ),
        "/var/folders must resolve to /private/var/folders"
    )
    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        ),
        "NSTemporaryDirectory() is volatile"
    )

    let caches = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches", isDirectory: true)
    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(caches),
        "~/Library/Caches is a volatile root"
    )
    expect(
        CourseLibraryVolatility.isVolatilePersistenceRoot(
            caches.appendingPathComponent("weibei-vol-\(unique)", isDirectory: true)
        ),
        "a subdirectory of ~/Library/Caches is volatile"
    )

    let support = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Application Support/WeiBeiSelfCheck-\(unique)",
            isDirectory: true
        )
    let target = URL(
        fileURLWithPath: "/private/tmp/weibei-vol-target-\(unique)",
        isDirectory: true
    )
    let link = support.appendingPathComponent("library-link", isDirectory: true)
    do {
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        defer {
            try? fileManager.removeItem(at: support)
            try? fileManager.removeItem(at: target)
        }
        expect(
            CourseLibraryVolatility.isVolatilePersistenceRoot(link),
            "a symlink from a durable parent into /private/tmp is volatile"
        )
        expect(
            !CourseLibraryVolatility.isVolatilePersistenceRoot(support),
            "the durable parent of that symlink is not volatile"
        )
    } catch {
        expect(false, "could not create volatility symlink fixtures: \(error)")
    }
}
