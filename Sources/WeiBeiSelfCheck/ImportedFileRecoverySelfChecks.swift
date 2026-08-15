import Darwin
import Foundation
import WeiBeiCore

func checkImportedFileRecovery() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("weibei-import-recovery-\(UUID().uuidString)", isDirectory: true)
    try! fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let original = root.appendingPathComponent("note.md")
    try! Data("original".utf8).write(to: original)
    let originalIdentity = identityAt(original)
    expect(originalIdentity != nil, "recovery fixture identity is available")
    guard let originalIdentity else { return }

    let recovered = ImportedFileRecovery.resolve(
        storedIdentity: originalIdentity,
        currentPath: original.path,
        lastKnownPath: original.path,
        bookmarkURL: nil,
        identityAt: identityAt
    )
    expect(
        recovered == .resolved(
            url: original.standardizedFileURL,
            identity: originalIdentity,
            via: .currentPath
        ),
        "identity match at the current path recovers the same file"
    )

    let bookmarkOnly = root.appendingPathComponent("via-bookmark.md")
    try! Data("original".utf8).write(to: bookmarkOnly)
    let bookmarkIdentity = identityAt(bookmarkOnly)
    expect(bookmarkIdentity != nil, "bookmark fixture identity is available")
    guard let bookmarkIdentity else { return }
    let bookmarkRecovered = ImportedFileRecovery.resolve(
        storedIdentity: bookmarkIdentity,
        currentPath: root.appendingPathComponent("gone.md").path,
        lastKnownPath: root.appendingPathComponent("gone.md").path,
        bookmarkURL: bookmarkOnly,
        identityAt: identityAt
    )
    expect(
        bookmarkRecovered == .resolved(
            url: bookmarkOnly.standardizedFileURL,
            identity: bookmarkIdentity,
            via: .bookmark
        ),
        "identity match via bookmark recovers when the current path is gone"
    )

    let lastKnown = root.appendingPathComponent("last-known.md")
    try! Data("original".utf8).write(to: lastKnown)
    let lastKnownIdentity = identityAt(lastKnown)
    expect(lastKnownIdentity != nil, "last-known fixture identity is available")
    guard let lastKnownIdentity else { return }
    let lastKnownRecovered = ImportedFileRecovery.resolve(
        storedIdentity: lastKnownIdentity,
        currentPath: nil,
        lastKnownPath: lastKnown.path,
        bookmarkURL: nil,
        identityAt: identityAt
    )
    expect(
        lastKnownRecovered == .resolved(
            url: lastKnown.standardizedFileURL,
            identity: lastKnownIdentity,
            via: .lastKnownPath
        ),
        "identity match via lastKnownPath recovers the same file"
    )

    let occupied = root.appendingPathComponent("occupied.md")
    try! Data("original".utf8).write(to: occupied)
    let occupiedIdentity = identityAt(occupied)
    expect(occupiedIdentity != nil, "occupied fixture identity is available")
    guard let occupiedIdentity else { return }
    try! Data("REPLACED".utf8).write(to: occupied, options: .atomic)
    let replacementIdentity = identityAt(occupied)
    expect(
        replacementIdentity != nil
            && replacementIdentity?.matchesAcrossVolumeDrift(occupiedIdentity) != true,
        "replacement file must not match the stored identity"
    )
    let conflict = ImportedFileRecovery.resolve(
        storedIdentity: occupiedIdentity,
        currentPath: occupied.path,
        lastKnownPath: occupied.path,
        bookmarkURL: nil,
        identityAt: identityAt
    )
    expect(
        conflict == .identityConflict(url: occupied.standardizedFileURL),
        "a different file occupying the same path is refused"
    )

    let gone = root.appendingPathComponent("missing.md")
    try! Data("original".utf8).write(to: gone)
    let goneIdentity = identityAt(gone)
    expect(goneIdentity != nil, "missing fixture identity is available")
    guard let goneIdentity else { return }
    try! fileManager.removeItem(at: gone)
    let missing = ImportedFileRecovery.resolve(
        storedIdentity: goneIdentity,
        currentPath: gone.path,
        lastKnownPath: gone.path,
        bookmarkURL: nil,
        identityAt: identityAt
    )
    expect(missing == .missing, "an invalid bookmark and missing path stay missing")
}

private func identityAt(_ url: URL) -> ImportedFileIdentity? {
    var fileStat = Darwin.stat()
    guard url.withUnsafeFileSystemRepresentation({ path in
        guard let path else { return false }
        return Darwin.lstat(path, &fileStat) == 0
    }) else { return nil }
    return ImportedFileIdentity(
        volumeID: UInt64(fileStat.st_dev),
        fileID: UInt64(fileStat.st_ino),
        birthTimeSeconds: Int64(fileStat.st_birthtimespec.tv_sec),
        birthTimeNanoseconds: Int64(fileStat.st_birthtimespec.tv_nsec)
    )
}
