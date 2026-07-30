import Foundation
import CryptoKit
import Darwin
import WeiBeiCore

struct CourseProjectResolvedBookmark {
    var url: URL
    var isStale: Bool
}

struct CourseFileSnapshot: Codable, Equatable, Sendable {
    var byteCount: UInt64
    var sha256: String
}

struct CourseFileMetadata: Equatable, Sendable {
    var url: URL
    var relativePath: String
    var identity: ImportedFileIdentity
    var documentIdentifier: UInt64?
    var byteCount: UInt64
    var modificationTimeNanoseconds: Int64
    var isNote: Bool
}

struct CourseFileScanSnapshot: Sendable {
    var observations: [CourseFileMetadata]
    var indexByRelativePath: [String: Int]
    var indexesByIdentity: [ImportedFileIdentity: [Int]]
    var indexesByDocumentIdentifier: [UInt64: [Int]]
}

struct CourseSharedLinkObservation: Equatable, Sendable {
    var url: URL
    var relativePath: String
    var linkIdentity: ImportedFileIdentity
    var sharedURL: URL
    var sharedIdentity: ImportedFileIdentity
}

struct CourseFileSourceInfo: Equatable, Sendable {
    var url: URL
    var identity: ImportedFileIdentity
    var byteCount: UInt64
    var modificationTimeNanoseconds: Int64
}

enum CourseFileEntryPresence: Equatable, Sendable {
    case present(ImportedFileIdentity)
    case absent
    case inaccessible
}

struct CourseMarkdownReadResult: Sendable {
    var markdown: String
    var snapshot: CourseFileSnapshot
    var metadata: CourseFileSourceInfo
    var documentIdentifier: UInt64?
    var ranOnMainThread: Bool
}

struct CourseMarkdownWriteResult: Sendable {
    var snapshot: CourseFileSnapshot
    var metadata: CourseFileSourceInfo
    var documentIdentifier: UInt64?
    var ranOnMainThread: Bool
}

struct CourseMarkdownStagingResult: Sendable {
    var identity: ImportedFileIdentity
    var snapshot: CourseFileSnapshot
    var ranOnMainThread: Bool
}

enum CourseProjectFileWorkerError: Error {
    case unsafePath
    case unsupportedFile
    case fileTooLarge
    case targetExists
    case contentConflict
    case verificationFailed
}

actor CourseProjectFileWorker {
    nonisolated static let portableStateMaximumByteCount = 32 * 1024 * 1024

    private let fileManager = FileManager.default

    func snapshot(at url: URL) throws -> CourseFileSnapshot {
        try Self.snapshotFile(at: url)
    }

    func snapshotWithThreadEvidence(
        at url: URL
    ) throws -> (snapshot: CourseFileSnapshot, ranOnMainThread: Bool) {
        (try Self.snapshotFile(at: url), Thread.isMainThread)
    }

    nonisolated static func snapshotFile(at url: URL) throws -> CourseFileSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += UInt64(chunk.count)
        }
        return CourseFileSnapshot(
            byteCount: byteCount,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    func snapshot(of data: Data) -> CourseFileSnapshot {
        CourseFileSnapshot(
            byteCount: UInt64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    func validatedRegularSource(_ rawURL: URL) throws -> CourseFileSourceInfo {
        guard rawURL.isFileURL else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let source = rawURL.standardizedFileURL
        let resolved = source.resolvingSymlinksInPath().standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        let values = try source.resourceValues(forKeys: keys)
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              CourseProjectPathPolicy.isSame(source, resolved),
              let identity = Self.identity(at: resolved) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        return CourseFileSourceInfo(
            url: resolved,
            identity: identity,
            byteCount: UInt64(max(0, values.fileSize ?? 0)),
            modificationTimeNanoseconds: Self.nanoseconds(values.contentModificationDate)
        )
    }

    func metadata(at url: URL) throws -> CourseFileSourceInfo {
        try validatedRegularSource(url)
    }

    func stableMetadata(
        at url: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) throws -> CourseFileSourceInfo {
        _ = try stableSnapshot(
            at: url,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        )
        let result = try validatedRegularSource(url)
        guard result.identity == expectedIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        _ = try stableSnapshot(
            at: url,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        )
        return result
    }

    func stableSnapshot(
        at url: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot? = nil
    ) throws -> CourseFileSnapshot {
        guard Self.identity(at: url) == expectedIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let result = try snapshot(at: url)
        guard Self.identity(at: url) == expectedIdentity,
              expectedSnapshot.map({ $0 == result }) ?? true else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return result
    }

    func readMarkdown(
        at url: URL,
        expectedIdentity: ImportedFileIdentity
    ) throws -> CourseMarkdownReadResult {
        let ranOnMainThread = Thread.isMainThread
        let source = try validatedRegularSource(url)
        guard source.identity == expectedIdentity,
              ["md", "markdown"].contains(
                source.url.pathExtension.lowercased()
              ) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let handle = try FileHandle(forReadingFrom: source.url)
        defer { try? handle.close() }
        var data = Data()
        if source.byteCount <= UInt64(Int.max) {
            data.reserveCapacity(Int(source.byteCount))
        }
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576),
              !chunk.isEmpty {
            data.append(chunk)
            hasher.update(data: chunk)
            byteCount += UInt64(chunk.count)
        }
        guard let markdown = String(data: data, encoding: .utf8),
              Self.identity(at: source.url) == expectedIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let metadata = try validatedRegularSource(source.url)
        guard metadata.identity == expectedIdentity,
              metadata.byteCount == byteCount else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let values = try source.url.resourceValues(
            forKeys: [.documentIdentifierKey]
        )
        return CourseMarkdownReadResult(
            markdown: markdown,
            snapshot: CourseFileSnapshot(
                byteCount: byteCount,
                sha256: hasher.finalize()
                    .map { String(format: "%02x", $0) }
                    .joined()
            ),
            metadata: metadata,
            documentIdentifier: values.documentIdentifier.flatMap {
                $0 >= 0 ? UInt64($0) : nil
            },
            ranOnMainThread: ranOnMainThread
        )
    }

    func stageMarkdown(
        _ markdown: String,
        to url: URL
    ) throws -> CourseMarkdownStagingResult {
        let ranOnMainThread = Thread.isMainThread
        let data = Data(markdown.utf8)
        let writtenSnapshot = snapshot(of: data)
        try data.write(to: url, options: [.withoutOverwriting])
        guard let identity = Self.identity(at: url),
              try stableSnapshot(
                at: url,
                expectedIdentity: identity,
                expectedSnapshot: writtenSnapshot
              ) == writtenSnapshot else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return CourseMarkdownStagingResult(
            identity: identity,
            snapshot: writtenSnapshot,
            ranOnMainThread: ranOnMainThread
        )
    }

    func copyAndVerify(
        from source: URL?,
        generatedData: Data?,
        to destination: URL,
        expectedSnapshot: CourseFileSnapshot
    ) throws -> ImportedFileIdentity {
        if let source {
            try fileManager.copyItem(at: source, to: destination)
        } else if let generatedData {
            try generatedData.write(to: destination, options: [.withoutOverwriting])
        } else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        guard let identity = Self.identity(at: destination),
              try snapshot(at: destination) == expectedSnapshot else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return identity
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    nonisolated static func writePortableState(
        _ data: Data,
        to url: URL,
        expectedDirectoryIdentity: ImportedFileIdentity,
        expectedPreviousData: Data?,
        beforeCommit: () throws -> Void
    ) throws {
        guard url.lastPathComponent == "course-state.json",
              data.count <= portableStateMaximumByteCount else {
            if data.count > portableStateMaximumByteCount {
                throw CourseProjectFileWorkerError.fileTooLarge
            }
            throw CourseProjectFileWorkerError.unsafePath
        }
        let directory = url.deletingLastPathComponent()
        let directoryDescriptor = try openDirectory(
            directory,
            expectedIdentity: expectedDirectoryIdentity
        )
        defer { Darwin.close(directoryDescriptor) }
        try compareAndSwapPortableStateData(
            data,
            expectedPreviousData: expectedPreviousData,
            named: url.lastPathComponent,
            relativeTo: directoryDescriptor,
            beforeCommit: beforeCommit
        )
        guard Darwin.fsync(directoryDescriptor) == 0,
              identity(at: directory) == expectedDirectoryIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    nonisolated static func readPortableState(
        at url: URL,
        expectedDirectoryIdentity: ImportedFileIdentity
    ) throws -> Data {
        guard url.lastPathComponent == "course-state.json" else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let directory = url.deletingLastPathComponent()
        let directoryDescriptor = try openDirectory(
            directory,
            expectedIdentity: expectedDirectoryIdentity
        )
        defer { Darwin.close(directoryDescriptor) }
        guard let data = try readRegularFile(
            named: url.lastPathComponent,
            relativeTo: directoryDescriptor,
            maximumByteCount: portableStateMaximumByteCount
        ),
        identity(at: directory) == expectedDirectoryIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return data
    }

    nonisolated static func restorePortableState(
        at url: URL,
        previousData: Data?,
        attemptedData: Data,
        expectedDirectoryIdentity: ImportedFileIdentity
    ) throws {
        guard url.lastPathComponent == "course-state.json" else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let directory = url.deletingLastPathComponent()
        let directoryDescriptor = try openDirectory(
            directory,
            expectedIdentity: expectedDirectoryIdentity
        )
        defer { Darwin.close(directoryDescriptor) }
        let name = url.lastPathComponent
        let currentData = try readRegularFile(
            named: name,
            relativeTo: directoryDescriptor,
            maximumByteCount: portableStateMaximumByteCount
        )
        if currentData == previousData {
            return
        }
        guard let previousData else {
            try removePortableStateIfMatching(
                attemptedData,
                named: name,
                relativeTo: directoryDescriptor
            )
            guard Darwin.fsync(directoryDescriptor) == 0,
                  identity(at: directory) == expectedDirectoryIdentity else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            return
        }
        if let currentData, currentData != attemptedData {
            let quarantine =
                "course-state-rejected-\(UUID().uuidString.lowercased()).json"
            let moved = name.withCString { sourceName in
                quarantine.withCString { destinationName in
                    Darwin.renameatx_np(
                        directoryDescriptor,
                        sourceName,
                        directoryDescriptor,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard moved == 0 else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
        }
        try compareAndSwapPortableStateData(
            previousData,
            expectedPreviousData: currentData == attemptedData
                ? attemptedData
                : nil,
            named: name,
            relativeTo: directoryDescriptor,
            beforeCommit: {}
        )
        guard Darwin.fsync(directoryDescriptor) == 0,
              identity(at: directory) == expectedDirectoryIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    func placeWithoutReplacement(
        from source: URL,
        to destination: URL,
        courseRoot: URL,
        destinationDirectory: URL,
        expectedDestinationIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot,
        beforeRename: () throws -> Void = {}
    ) throws -> ImportedFileIdentity {
        try validateDestination(
            destination,
            courseRoot: courseRoot,
            destinationDirectory: destinationDirectory,
            expectedDestinationIdentity: expectedDestinationIdentity,
            mustExist: false
        )
        guard let sourceIdentity = Self.identity(at: source) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let identity = try Self.renameWithoutReplacementAnchored(
            from: source,
            to: destination,
            expectedSourceIdentity: sourceIdentity,
            expectedDestinationDirectoryIdentity:
                expectedDestinationIdentity,
            beforeRename: beforeRename
        )
        do {
            try validateDestination(
                destination,
                courseRoot: courseRoot,
                destinationDirectory: destinationDirectory,
                expectedDestinationIdentity: expectedDestinationIdentity,
                mustExist: true
            )
            guard Self.identity(at: destination) == identity,
                  try stableSnapshot(
                    at: destination,
                    expectedIdentity: identity,
                    expectedSnapshot: expectedSnapshot
                  ) == expectedSnapshot else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            return identity
        } catch {
            throw error
        }
    }

    func isolateWithoutReplacement(from source: URL, to destination: URL) -> Bool {
        Self.renameWithoutReplacement(from: source, to: destination)
    }

    func remove(_ url: URL, using remover: @Sendable (URL) throws -> Void) throws {
        try remover(url)
    }

    func isolateAndRemoveVerifiedFile(
        at originalURL: URL,
        quarantineURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot,
        remover: @Sendable (URL) throws -> Void
    ) -> CourseFileRemovalOutcome {
        guard fileManager.fileExists(atPath: originalURL.path) else {
            return fileManager.fileExists(atPath: quarantineURL.path)
                ? .quarantined(quarantineURL)
                : .removed
        }
        guard !fileManager.fileExists(atPath: quarantineURL.path),
              Self.renameWithoutReplacement(from: originalURL, to: quarantineURL) else {
            return fileManager.fileExists(atPath: quarantineURL.path)
                ? .quarantined(quarantineURL)
                : .restored
        }
        guard (try? stableSnapshot(
            at: quarantineURL,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        )) != nil else {
            return restoreIsolatedFile(from: quarantineURL, to: originalURL)
        }
        do {
            try remover(quarantineURL)
        } catch {
            if !fileManager.fileExists(atPath: quarantineURL.path) {
                return .removed
            }
            return restoreIsolatedFile(from: quarantineURL, to: originalURL)
        }
        return fileManager.fileExists(atPath: quarantineURL.path)
            ? restoreIsolatedFile(from: quarantineURL, to: originalURL)
            : .removed
    }

    func restoreIsolatedFile(from quarantineURL: URL, to originalURL: URL) -> CourseFileRemovalOutcome {
        guard fileManager.fileExists(atPath: quarantineURL.path) else {
            return .quarantined(quarantineURL)
        }
        guard !fileManager.fileExists(atPath: originalURL.path),
              Self.renameWithoutReplacement(from: quarantineURL, to: originalURL) else {
            return .quarantined(quarantineURL)
        }
        return .restored
    }

    func moveReplacedFileToTrash(
        at url: URL,
        selfCheckDestination: URL
    ) throws -> URL {
        if ProcessInfo.processInfo.arguments.contains("--self-check-course-project-root") {
            guard Self.renameWithoutReplacement(
                from: url,
                to: selfCheckDestination
            ) else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return selfCheckDestination
        }
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        guard let resultingURL else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return (resultingURL as URL).standardizedFileURL
    }

    func createVerifiedRollbackCopy(
        from source: URL,
        to destination: URL,
        expectedSnapshot: CourseFileSnapshot
    ) throws -> ImportedFileIdentity {
        let linked = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return false }
                return Darwin.link(sourcePath, destinationPath) == 0
            }
        }
        if !linked {
            try fileManager.copyItem(at: source, to: destination)
        }
        do {
            guard let identity = Self.identity(at: destination),
                  try snapshot(at: destination) == expectedSnapshot else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            return identity
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func reserveRollbackFile(at url: URL) throws -> ImportedFileIdentity {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard Darwin.close(descriptor) == 0, let identity = Self.identity(at: url) else {
            try? fileManager.removeItem(at: url)
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return identity
    }

    func fillReservedRollbackFile(
        from source: URL,
        to destination: URL,
        expectedDestinationIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) throws {
        guard Self.identity(at: destination) == expectedDestinationIdentity,
              !Self.isSymbolicLink(at: destination) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { try? sourceHandle.close() }
        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer { try? destinationHandle.close() }
        try destinationHandle.truncate(atOffset: 0)
        while let chunk = try sourceHandle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try destinationHandle.write(contentsOf: chunk)
        }
        try destinationHandle.synchronize()
        guard Self.identity(at: destination) == expectedDestinationIdentity,
              try snapshot(at: destination) == expectedSnapshot,
              Self.identity(at: destination) == expectedDestinationIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    func removeFileIfIdentityMatches(
        at url: URL,
        expectedIdentity: ImportedFileIdentity
    ) throws {
        let currentSnapshot = try stableSnapshot(
            at: url,
            expectedIdentity: expectedIdentity
        )
        try removeVerifiedFile(
            at: url,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: currentSnapshot
        )
    }

    func removeVerifiedFile(
        at url: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot,
        beforeRemoval: () throws -> Void = {}
    ) throws {
        _ = try stableSnapshot(
            at: url,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        )
        try beforeRemoval()
        let quarantineURL = url.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(url.lastPathComponent).weibei-remove-\(UUID().uuidString.lowercased())"
            )
        let outcome = isolateAndRemoveVerifiedFile(
            at: url,
            quarantineURL: quarantineURL,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot,
            remover: { try FileManager.default.removeItem(at: $0) }
        )
        guard case .removed = outcome else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    func finishSelfCheckTrash(at url: URL) throws {
        guard ProcessInfo.processInfo.arguments.contains(
            "--self-check-course-project-root"
        ) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    func prepareSymbolicLink(
        at preparedURL: URL,
        destinationURL: URL
    ) throws -> ImportedFileIdentity {
        guard !fileManager.fileExists(atPath: preparedURL.path) else {
            throw CourseProjectFileWorkerError.targetExists
        }
        try fileManager.createSymbolicLink(
            at: preparedURL,
            withDestinationURL: destinationURL
        )
        guard Self.isSymbolicLink(at: preparedURL),
              CourseProjectPathPolicy.isSame(
                preparedURL.resolvingSymlinksInPath(),
                destinationURL.resolvingSymlinksInPath()
              ),
              let identity = Self.identity(at: preparedURL) else {
            try? fileManager.removeItem(at: preparedURL)
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return identity
    }

    func placePreparedSymbolicLink(
        from preparedURL: URL,
        to linkURL: URL,
        destinationURL: URL,
        allowedRoot: URL,
        expectedIdentity: ImportedFileIdentity
    ) throws {
        let parent = linkURL.deletingLastPathComponent()
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(allowedRoot)
        let canonicalParent = try CourseProjectPathPolicy.existingDirectory(parent)
        guard let parentIdentity = Self.identity(at: canonicalParent) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        guard CourseProjectPathPolicy.isSame(parent, canonicalParent),
              CourseProjectPathPolicy.contains(
                canonicalRoot,
                canonicalParent,
                includingRoot: false
              ),
              Self.isSymbolicLink(at: preparedURL),
              Self.identity(at: preparedURL) == expectedIdentity,
              CourseProjectPathPolicy.isSame(
                preparedURL.resolvingSymlinksInPath(),
                destinationURL.resolvingSymlinksInPath()
              ),
              !fileManager.fileExists(atPath: linkURL.path) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let placedIdentity = try Self.renameWithoutReplacementAnchored(
            from: preparedURL,
            to: linkURL,
            expectedSourceIdentity: expectedIdentity,
            expectedDestinationDirectoryIdentity: parentIdentity,
            beforeRename: {}
        )
        guard placedIdentity == expectedIdentity,
              Self.isSymbolicLink(at: linkURL),
              Self.identity(at: linkURL) == expectedIdentity,
              CourseProjectPathPolicy.isSame(
                linkURL.resolvingSymlinksInPath(),
                destinationURL.resolvingSymlinksInPath()
              ) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    func isolateSymbolicLinkIfMatching(
        at linkURL: URL,
        to quarantineURL: URL,
        destinationURL: URL,
        expectedIdentity: ImportedFileIdentity?
    ) throws -> ImportedFileIdentity {
        guard Self.identity(at: quarantineURL) == nil,
              Self.renameWithoutReplacement(
                from: linkURL,
                to: quarantineURL
              ) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        guard Self.isSymbolicLink(at: quarantineURL),
              let isolatedIdentity = Self.identity(at: quarantineURL),
              expectedIdentity.map({ isolatedIdentity == $0 }) ?? true,
              Self.symbolicLink(
                at: quarantineURL,
                pointsTo: destinationURL
              ) else {
            _ = Self.renameWithoutReplacement(
                from: quarantineURL,
                to: linkURL
            )
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return isolatedIdentity
    }

    func isolateAndRemoveSymbolicLinkIfMatching(
        at linkURL: URL,
        quarantineURL: URL,
        destinationURL: URL,
        expectedIdentity: ImportedFileIdentity?
    ) -> Bool {
        do {
            _ = try isolateSymbolicLinkIfMatching(
                at: linkURL,
                to: quarantineURL,
                destinationURL: destinationURL,
                expectedIdentity: expectedIdentity
            )
            try fileManager.removeItem(at: quarantineURL)
            return Self.identity(at: quarantineURL) == nil
        } catch {
            return false
        }
    }

    func scanCourse(at root: URL) throws -> CourseFileScanSnapshot {
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(root)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .documentIdentifierKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in false }
        ) else {
            return CourseFileScanSnapshot(
                observations: [],
                indexByRelativePath: [:],
                indexesByIdentity: [:],
                indexesByDocumentIdentifier: [:]
            )
        }
        var result: [CourseFileMetadata] = []
        for case let rawURL as URL in enumerator {
            guard let relativePath = CourseProjectPathPolicy.relativePath(
                of: rawURL,
                inside: canonicalRoot
            ) else {
                enumerator.skipDescendants()
                continue
            }
            if relativePath == ".weibei" || relativePath.hasPrefix(".weibei/") {
                enumerator.skipDescendants()
                continue
            }
            let values = try rawURL.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                if values.isSymbolicLink == true || values.isAliasFile == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  values.isAliasFile != true,
                  Self.supportedExtensions.contains(rawURL.pathExtension.lowercased()),
                  CourseProjectPathPolicy.isSame(rawURL, rawURL.resolvingSymlinksInPath()),
                  let identity = Self.identity(at: rawURL) else {
                continue
            }
            let firstComponent = relativePath.split(separator: "/", omittingEmptySubsequences: true).first
            let isMarkdown = ["md", "markdown"].contains(rawURL.pathExtension.lowercased())
            result.append(
                CourseFileMetadata(
                    url: rawURL.standardizedFileURL,
                    relativePath: relativePath,
                    identity: identity,
                    documentIdentifier: values.documentIdentifier.flatMap {
                        $0 >= 0 ? UInt64($0) : nil
                    },
                    byteCount: UInt64(max(0, values.fileSize ?? 0)),
                    modificationTimeNanoseconds: Self.nanoseconds(values.contentModificationDate),
                    isNote: firstComponent == "笔记" && isMarkdown
                )
            )
        }
        let observations = result.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        var indexByRelativePath: [String: Int] = [:]
        var indexesByIdentity: [ImportedFileIdentity: [Int]] = [:]
        var indexesByDocumentIdentifier: [UInt64: [Int]] = [:]
        for (index, observation) in observations.enumerated() {
            indexByRelativePath[observation.relativePath] = index
            indexesByIdentity[observation.identity, default: []].append(index)
            if let documentIdentifier = observation.documentIdentifier {
                indexesByDocumentIdentifier[documentIdentifier, default: []].append(index)
            }
        }
        return CourseFileScanSnapshot(
            observations: observations,
            indexByRelativePath: indexByRelativePath,
            indexesByIdentity: indexesByIdentity,
            indexesByDocumentIdentifier: indexesByDocumentIdentifier
        )
    }

    func scanSharedOriginals(at sharedDirectory: URL) throws -> CourseFileScanSnapshot {
        let canonicalDirectory = try CourseProjectPathPolicy.existingDirectory(
            sharedDirectory
        )
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .documentIdentifierKey,
        ]
        let entries = try fileManager.contentsOfDirectory(
            at: canonicalDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        var observations: [CourseFileMetadata] = []
        for rawURL in entries {
            let values = try rawURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  values.isAliasFile != true,
                  Self.supportedExtensions.contains(
                    rawURL.pathExtension.lowercased()
                  ),
                  CourseProjectPathPolicy.isSame(
                    rawURL,
                    rawURL.resolvingSymlinksInPath()
                  ),
                  let identity = Self.identity(at: rawURL) else {
                continue
            }
            observations.append(
                CourseFileMetadata(
                    url: rawURL.standardizedFileURL,
                    relativePath: rawURL.lastPathComponent,
                    identity: identity,
                    documentIdentifier: values.documentIdentifier.flatMap {
                        $0 >= 0 ? UInt64($0) : nil
                    },
                    byteCount: UInt64(max(0, values.fileSize ?? 0)),
                    modificationTimeNanoseconds: Self.nanoseconds(
                        values.contentModificationDate
                    ),
                    isNote: false
                )
            )
        }
        observations.sort {
            $0.relativePath.localizedStandardCompare($1.relativePath)
                == .orderedAscending
        }
        var indexByRelativePath: [String: Int] = [:]
        var indexesByIdentity: [ImportedFileIdentity: [Int]] = [:]
        var indexesByDocumentIdentifier: [UInt64: [Int]] = [:]
        for (index, observation) in observations.enumerated() {
            indexByRelativePath[observation.relativePath] = index
            indexesByIdentity[observation.identity, default: []].append(index)
            if let documentIdentifier = observation.documentIdentifier {
                indexesByDocumentIdentifier[
                    documentIdentifier,
                    default: []
                ].append(index)
            }
        }
        return CourseFileScanSnapshot(
            observations: observations,
            indexByRelativePath: indexByRelativePath,
            indexesByIdentity: indexesByIdentity,
            indexesByDocumentIdentifier: indexesByDocumentIdentifier
        )
    }

    func repairSharedLink(
        at linkURL: URL,
        courseRoot: URL,
        from oldSharedURL: URL,
        to newSharedURL: URL,
        expectedLinkIdentity: ImportedFileIdentity
    ) throws {
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(
            courseRoot
        )
        let canonicalNewSharedURL = try validatedRegularSource(newSharedURL).url
        let linkParent = linkURL.deletingLastPathComponent()
        let canonicalLinkParent = try CourseProjectPathPolicy
            .existingDirectory(linkParent)
        guard CourseProjectPathPolicy.contains(
            canonicalRoot,
            linkURL,
            includingRoot: false
        ),
        CourseProjectPathPolicy.isSame(linkParent, canonicalLinkParent),
        CourseProjectPathPolicy.contains(
            canonicalRoot,
            canonicalLinkParent,
            includingRoot: false
        ),
        Self.supportedExtensions.contains(
            linkURL.pathExtension.lowercased()
        ),
        Self.isSymbolicLink(at: linkURL),
        Self.identity(at: linkURL) == expectedLinkIdentity,
        let destination = try? fileManager.destinationOfSymbolicLink(
            atPath: linkURL.path
        ) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let destinationURL = destination.hasPrefix("/")
            ? URL(fileURLWithPath: destination).standardizedFileURL
            : linkURL.deletingLastPathComponent()
                .appendingPathComponent(destination)
                .standardizedFileURL
        let canonicalDestinationURL = destinationURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(destinationURL.lastPathComponent)
            .standardizedFileURL
        let canonicalOldSharedURL = oldSharedURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(oldSharedURL.lastPathComponent)
            .standardizedFileURL
        guard CourseProjectPathPolicy.isSame(
            canonicalDestinationURL,
            canonicalOldSharedURL
        ) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let temporary = linkURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(linkURL.lastPathComponent).weibei-repair-\(UUID().uuidString.lowercased())"
            )
        try fileManager.createSymbolicLink(
            at: temporary,
            withDestinationURL: canonicalNewSharedURL
        )
        guard let preparedIdentity = Self.identity(at: temporary),
              Self.isSymbolicLink(at: temporary),
              Self.symbolicLink(
                at: temporary,
                pointsTo: canonicalNewSharedURL
              ),
              Self.isSymbolicLink(at: linkURL),
              Self.identity(at: linkURL) == expectedLinkIdentity,
              Self.renameSwap(from: temporary, to: linkURL) else {
            try? fileManager.removeItem(at: temporary)
            throw CourseProjectFileWorkerError.verificationFailed
        }
        guard Self.isSymbolicLink(at: temporary),
              Self.identity(at: temporary) == expectedLinkIdentity,
              Self.symbolicLink(
                at: temporary,
                pointsTo: canonicalOldSharedURL
              ),
              Self.isSymbolicLink(at: linkURL),
              Self.identity(at: linkURL) == preparedIdentity,
              Self.symbolicLink(
                at: linkURL,
                pointsTo: canonicalNewSharedURL
              ) else {
            _ = Self.renameSwap(from: temporary, to: linkURL)
            throw CourseProjectFileWorkerError.verificationFailed
        }
        try fileManager.removeItem(at: temporary)
    }

    func scanSharedLinks(
        at root: URL,
        sharedDirectory: URL
    ) throws -> [CourseSharedLinkObservation] {
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(root)
        guard fileManager.fileExists(atPath: sharedDirectory.path) else {
            return []
        }
        let canonicalSharedDirectory = try CourseProjectPathPolicy.existingDirectory(sharedDirectory)
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isAliasFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in false }
        ) else {
            return []
        }
        var result: [CourseSharedLinkObservation] = []
        for case let rawURL as URL in enumerator {
            guard let relativePath = CourseProjectPathPolicy.relativePath(
                of: rawURL,
                inside: canonicalRoot
            ) else {
                enumerator.skipDescendants()
                continue
            }
            if relativePath == ".weibei" || relativePath.hasPrefix(".weibei/") {
                enumerator.skipDescendants()
                continue
            }
            if Self.isSymbolicLink(at: rawURL) {
                enumerator.skipDescendants()
                guard Self.supportedExtensions.contains(rawURL.pathExtension.lowercased()),
                      let linkIdentity = Self.identity(at: rawURL) else {
                    continue
                }
                let resolvedTarget = rawURL.resolvingSymlinksInPath().standardizedFileURL
                guard CourseProjectPathPolicy.isSame(
                    resolvedTarget.deletingLastPathComponent(),
                    canonicalSharedDirectory
                ),
                let sharedInfo = try? validatedRegularSource(resolvedTarget),
                Self.isSymbolicLink(at: rawURL),
                Self.identity(at: rawURL) == linkIdentity,
                CourseProjectPathPolicy.isSame(
                    rawURL.resolvingSymlinksInPath(),
                    sharedInfo.url
                ),
                Self.identity(at: sharedInfo.url) == sharedInfo.identity else {
                    continue
                }
                result.append(
                    CourseSharedLinkObservation(
                        url: rawURL.standardizedFileURL,
                        relativePath: relativePath,
                        linkIdentity: linkIdentity,
                        sharedURL: sharedInfo.url,
                        sharedIdentity: sharedInfo.identity
                    )
                )
                continue
            }
            if (try? rawURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                continue
            }
        }
        return result.sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
    }

    func expandedSupportedFiles(
        from urls: [URL],
        markdownOnly: Bool
    ) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for rawURL in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rawURL.path, isDirectory: &isDirectory) else {
                continue
            }
            if !isDirectory.boolValue {
                appendSupported(rawURL, markdownOnly: markdownOnly, seen: &seen, result: &result)
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: rawURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in false }
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                appendSupported(fileURL, markdownOnly: markdownOnly, seen: &seen, result: &result)
                if result.count == 500 { break }
            }
            if result.count == 500 { break }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func ensureRealDirectory(_ rawDirectory: URL, inside parent: URL) throws -> URL {
        if !fileManager.fileExists(atPath: rawDirectory.path) {
            try fileManager.createDirectory(at: rawDirectory, withIntermediateDirectories: false)
        }
        let values = try rawDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        let canonical = try CourseProjectPathPolicy.existingDirectory(rawDirectory)
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              CourseProjectPathPolicy.isSame(rawDirectory, canonical),
              CourseProjectPathPolicy.contains(parent, canonical, includingRoot: false) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        return canonical
    }

    private func validateDestination(
        _ destination: URL,
        courseRoot: URL,
        destinationDirectory: URL,
        expectedDestinationIdentity: ImportedFileIdentity,
        mustExist: Bool
    ) throws {
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(courseRoot)
        let canonicalDirectory = try CourseProjectPathPolicy.existingDirectory(destinationDirectory)
        guard Self.identity(at: canonicalDirectory) == expectedDestinationIdentity,
              CourseProjectPathPolicy.contains(canonicalRoot, canonicalDirectory, includingRoot: false),
              CourseProjectPathPolicy.contains(canonicalDirectory, destination, includingRoot: false),
              CourseProjectPathPolicy.contains(canonicalRoot, destination, includingRoot: false) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        if mustExist {
            let resolved = destination.resolvingSymlinksInPath().standardizedFileURL
            guard CourseProjectPathPolicy.isSame(destination, resolved),
                  CourseProjectPathPolicy.contains(canonicalDirectory, resolved, includingRoot: false),
                  CourseProjectPathPolicy.contains(canonicalRoot, resolved, includingRoot: false) else {
                throw CourseProjectFileWorkerError.unsafePath
            }
        } else {
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw CourseProjectFileWorkerError.targetExists
            }
        }
    }

    private func appendSupported(
        _ rawURL: URL,
        markdownOnly: Bool,
        seen: inout Set<String>,
        result: inout [URL]
    ) {
        let pathExtension = rawURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(pathExtension),
              !markdownOnly || ["md", "markdown"].contains(pathExtension),
              let values = try? rawURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
              ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true else {
            return
        }
        let url = rawURL.standardizedFileURL
        guard seen.insert(url.path).inserted else { return }
        result.append(url)
    }

    nonisolated static func identity(at url: URL) -> ImportedFileIdentity? {
        var fileStat = Darwin.stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return Darwin.lstat(path, &fileStat) == 0
        }) else {
            return nil
        }
        return ImportedFileIdentity(
            volumeID: UInt64(fileStat.st_dev),
            fileID: UInt64(fileStat.st_ino),
            birthTimeSeconds: Int64(fileStat.st_birthtimespec.tv_sec),
            birthTimeNanoseconds: Int64(fileStat.st_birthtimespec.tv_nsec)
        )
    }

    nonisolated static func entryPresence(
        at url: URL
    ) -> CourseFileEntryPresence {
        var fileStat = Darwin.stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &fileStat)
        }
        if result == 0 {
            return .present(
                ImportedFileIdentity(
                    volumeID: UInt64(fileStat.st_dev),
                    fileID: UInt64(fileStat.st_ino),
                    birthTimeSeconds: Int64(
                        fileStat.st_birthtimespec.tv_sec
                    ),
                    birthTimeNanoseconds: Int64(
                        fileStat.st_birthtimespec.tv_nsec
                    )
                )
            )
        }
        return errno == ENOENT || errno == ENOTDIR
            ? .absent
            : .inaccessible
    }

    nonisolated static func isSymbolicLink(at url: URL) -> Bool {
        var fileStat = Darwin.stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return Darwin.lstat(path, &fileStat) == 0
        }) else {
            return false
        }
        return (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    nonisolated static func renameWithoutReplacement(from source: URL, to destination: URL) -> Bool {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return false }
                return Darwin.renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL)) == 0
            }
        }
    }

    nonisolated private static func renameWithoutReplacementAnchored(
        from source: URL,
        to destination: URL,
        expectedSourceIdentity: ImportedFileIdentity,
        expectedDestinationDirectoryIdentity: ImportedFileIdentity,
        beforeRename: () throws -> Void
    ) throws -> ImportedFileIdentity {
        let sourceDirectory = source.deletingLastPathComponent()
        let destinationDirectory = destination.deletingLastPathComponent()
        guard let sourceDirectoryIdentity = identity(at: sourceDirectory) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let sourceDescriptor = try openDirectory(
            sourceDirectory,
            expectedIdentity: sourceDirectoryIdentity
        )
        defer { Darwin.close(sourceDescriptor) }
        let destinationDescriptor = try openDirectory(
            destinationDirectory,
            expectedIdentity: expectedDestinationDirectoryIdentity
        )
        defer { Darwin.close(destinationDescriptor) }

        let sourceName = source.lastPathComponent
        let destinationName = destination.lastPathComponent
        guard identity(
            named: sourceName,
            relativeTo: sourceDescriptor
        ) == expectedSourceIdentity,
        identity(named: destinationName, relativeTo: destinationDescriptor)
            == nil else {
            throw CourseProjectFileWorkerError.targetExists
        }
        try beforeRename()
        guard identity(at: sourceDirectory) == sourceDirectoryIdentity,
              identity(at: destinationDirectory)
                == expectedDestinationDirectoryIdentity else {
            throw CourseProjectFileWorkerError.unsafePath
        }

        let result = sourceName.withCString { sourceNamePointer in
            destinationName.withCString { destinationNamePointer in
                Darwin.renameatx_np(
                    sourceDescriptor,
                    sourceNamePointer,
                    destinationDescriptor,
                    destinationNamePointer,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST {
                throw CourseProjectFileWorkerError.targetExists
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        guard let resultIdentity = identity(
            named: destinationName,
            relativeTo: destinationDescriptor
        ),
        resultIdentity == expectedSourceIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return resultIdentity
    }

    nonisolated private static func openDirectory(
        _ url: URL,
        expectedIdentity: ImportedFileIdentity
    ) throws -> Int32 {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var fileStat = Darwin.stat()
        guard Darwin.fstat(descriptor, &fileStat) == 0,
              identity(from: fileStat) == expectedIdentity else {
            Darwin.close(descriptor)
            throw CourseProjectFileWorkerError.unsafePath
        }
        return descriptor
    }

    nonisolated private static func compareAndSwapPortableStateData(
        _ data: Data,
        expectedPreviousData: Data?,
        named name: String,
        relativeTo directoryDescriptor: Int32,
        beforeCommit: () throws -> Void
    ) throws {
        guard data.count <= portableStateMaximumByteCount else {
            throw CourseProjectFileWorkerError.fileTooLarge
        }
        let operationID = UUID().uuidString.lowercased()
        let temporaryName = ".course-state-\(operationID).tmp"
        let candidateBackupName =
            ".course-state-candidate-\(operationID).tmp"
        let descriptor = temporaryName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var shouldRemoveTemporary = true
        var shouldRemoveCandidateBackup = true
        defer {
            Darwin.close(descriptor)
            if shouldRemoveTemporary {
                temporaryName.withCString {
                    _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
            if shouldRemoveCandidateBackup {
                candidateBackupName.withCString {
                    _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }
        func preserveCandidate(
            named candidateName: String,
            keepsTemporary: Bool
        ) throws {
            if keepsTemporary {
                shouldRemoveTemporary = false
            } else {
                shouldRemoveCandidateBackup = false
            }
            let conflictName =
                "course-state-conflict-\(UUID().uuidString.lowercased()).json"
            let preserved = candidateName.withCString { sourceName in
                conflictName.withCString { destinationName in
                    Darwin.renameatx_np(
                        directoryDescriptor,
                        sourceName,
                        directoryDescriptor,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard preserved == 0 else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
        }
        func rollBackSwapAndPreserveCandidate() throws {
            let rolledBack = temporaryName.withCString { sourceName in
                name.withCString { destinationName in
                    Darwin.renameatx_np(
                        directoryDescriptor,
                        sourceName,
                        directoryDescriptor,
                        destinationName,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard rolledBack == 0 else {
                shouldRemoveTemporary = false
                throw CourseProjectFileWorkerError.verificationFailed
            }
            try preserveCandidate(
                named: temporaryName,
                keepsTemporary: true
            )
        }
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard written > 0 else {
                    throw POSIXError(
                        POSIXErrorCode(rawValue: errno) ?? .EIO
                    )
                }
                offset += written
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let currentData: Data?
        do {
            currentData = try readRegularFile(
                named: name,
                relativeTo: directoryDescriptor,
                maximumByteCount: portableStateMaximumByteCount
            )
        } catch {
            try preserveCandidate(
                named: temporaryName,
                keepsTemporary: true
            )
            throw CourseProjectFileWorkerError.contentConflict
        }
        guard currentData == expectedPreviousData else {
            try preserveCandidate(
                named: temporaryName,
                keepsTemporary: true
            )
            throw CourseProjectFileWorkerError.contentConflict
        }
        try beforeCommit()
        try writeExclusiveData(
            data,
            named: candidateBackupName,
            relativeTo: directoryDescriptor
        )
        if expectedPreviousData == nil {
            let placed = temporaryName.withCString { sourceName in
                name.withCString { destinationName in
                    Darwin.renameatx_np(
                        directoryDescriptor,
                        sourceName,
                        directoryDescriptor,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard placed == 0 else {
                if errno == EEXIST {
                    try preserveCandidate(
                        named: temporaryName,
                        keepsTemporary: true
                    )
                    throw CourseProjectFileWorkerError.contentConflict
                }
                throw POSIXError(
                    POSIXErrorCode(rawValue: errno) ?? .EIO
                )
            }
            shouldRemoveTemporary = false
        } else {
            let swapped = temporaryName.withCString { sourceName in
                name.withCString { destinationName in
                    Darwin.renameatx_np(
                        directoryDescriptor,
                        sourceName,
                        directoryDescriptor,
                        destinationName,
                        UInt32(RENAME_SWAP)
                    )
                }
            }
            guard swapped == 0 else {
                if errno == ENOENT {
                    try preserveCandidate(
                        named: temporaryName,
                        keepsTemporary: true
                    )
                    throw CourseProjectFileWorkerError.contentConflict
                }
                throw POSIXError(
                    POSIXErrorCode(rawValue: errno) ?? .EIO
                )
            }
            let displacedData: Data?
            do {
                displacedData = try readRegularFile(
                    named: temporaryName,
                    relativeTo: directoryDescriptor,
                    maximumByteCount: portableStateMaximumByteCount
                )
            } catch {
                try rollBackSwapAndPreserveCandidate()
                throw CourseProjectFileWorkerError.contentConflict
            }
            guard displacedData == expectedPreviousData else {
                try rollBackSwapAndPreserveCandidate()
                throw CourseProjectFileWorkerError.contentConflict
            }
            let removedDisplaced = temporaryName.withCString {
                Darwin.unlinkat(directoryDescriptor, $0, 0)
            }
            guard removedDisplaced == 0 else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            shouldRemoveTemporary = false
        }
        let finalData: Data?
        do {
            finalData = try readRegularFile(
                named: name,
                relativeTo: directoryDescriptor,
                maximumByteCount: portableStateMaximumByteCount
            )
        } catch {
            try preserveCandidate(
                named: candidateBackupName,
                keepsTemporary: false
            )
            throw CourseProjectFileWorkerError.contentConflict
        }
        guard finalData == data else {
            try preserveCandidate(
                named: candidateBackupName,
                keepsTemporary: false
            )
            throw CourseProjectFileWorkerError.contentConflict
        }
        let removedCandidateBackup = candidateBackupName.withCString {
            Darwin.unlinkat(directoryDescriptor, $0, 0)
        }
        guard removedCandidateBackup == 0 else {
            shouldRemoveCandidateBackup = false
            throw CourseProjectFileWorkerError.verificationFailed
        }
        shouldRemoveCandidateBackup = false
    }

    nonisolated private static func removePortableStateIfMatching(
        _ attemptedData: Data,
        named name: String,
        relativeTo directoryDescriptor: Int32
    ) throws {
        let isolatedName =
            "course-state-rollback-\(UUID().uuidString.lowercased()).json"
        let isolated = name.withCString { sourceName in
            isolatedName.withCString { destinationName in
                Darwin.renameatx_np(
                    directoryDescriptor,
                    sourceName,
                    directoryDescriptor,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        if isolated != 0 {
            if errno == ENOENT {
                return
            }
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }

        func restoreIsolatedState() throws {
            let restored = isolatedName.withCString { sourceName in
                name.withCString { destinationName in
                    Darwin.renameatx_np(
                        directoryDescriptor,
                        sourceName,
                        directoryDescriptor,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            if restored == 0 {
                return
            }
            let conflictName =
                "course-state-conflict-\(UUID().uuidString.lowercased()).json"
            let preserved = isolatedName.withCString { sourceName in
                conflictName.withCString { destinationName in
                    Darwin.renameatx_np(
                        directoryDescriptor,
                        sourceName,
                        directoryDescriptor,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard preserved == 0 else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            throw CourseProjectFileWorkerError.contentConflict
        }

        let isolatedData: Data
        do {
            guard let data = try readRegularFile(
                named: isolatedName,
                relativeTo: directoryDescriptor,
                maximumByteCount: portableStateMaximumByteCount
            ) else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            isolatedData = data
        } catch {
            try restoreIsolatedState()
            throw error
        }
        guard isolatedData == attemptedData else {
            let candidateName =
                "course-state-conflict-\(UUID().uuidString.lowercased()).json"
            do {
                try writeExclusiveData(
                    attemptedData,
                    named: candidateName,
                    relativeTo: directoryDescriptor
                )
            } catch {
                try restoreIsolatedState()
                throw error
            }
            try restoreIsolatedState()
            return
        }
        let removed = isolatedName.withCString {
            Darwin.unlinkat(directoryDescriptor, $0, 0)
        }
        guard removed == 0 else {
            try restoreIsolatedState()
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    nonisolated private static func writeExclusiveData(
        _ data: Data,
        named name: String,
        relativeTo directoryDescriptor: Int32
    ) throws {
        guard data.count <= portableStateMaximumByteCount else {
            throw CourseProjectFileWorkerError.fileTooLarge
        }
        let descriptor = name.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }
        var completed = false
        defer {
            Darwin.close(descriptor)
            if !completed {
                name.withCString {
                    _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard written > 0 else {
                    throw POSIXError(
                        POSIXErrorCode(rawValue: errno) ?? .EIO
                    )
                }
                offset += written
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }
        completed = true
    }

    nonisolated private static func readRegularFile(
        named name: String,
        relativeTo directoryDescriptor: Int32,
        maximumByteCount: Int
    ) throws -> Data? {
        let descriptor = name.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        var fileStat = Darwin.stat()
        guard Darwin.fstat(descriptor, &fileStat) == 0,
              (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        guard fileStat.st_size >= 0,
              fileStat.st_size <= Int64(maximumByteCount) else {
            throw CourseProjectFileWorkerError.fileTooLarge
        }
        var data = Data()
        if fileStat.st_size > 0, fileStat.st_size <= Int64(Int.max) {
            data.reserveCapacity(Int(fileStat.st_size))
        }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(
                    descriptor,
                    $0.baseAddress,
                    $0.count
                )
            }
            guard count >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
            guard data.count <= maximumByteCount else {
                throw CourseProjectFileWorkerError.fileTooLarge
            }
        }
        return data
    }

    nonisolated private static func entryStat(
        named name: String,
        relativeTo directoryDescriptor: Int32
    ) -> Darwin.stat? {
        var fileStat = Darwin.stat()
        let result = name.withCString {
            Darwin.fstatat(
                directoryDescriptor,
                $0,
                &fileStat,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if result == 0 {
            return fileStat
        }
        return nil
    }

    nonisolated private static func identity(
        named name: String,
        relativeTo directoryDescriptor: Int32
    ) -> ImportedFileIdentity? {
        var fileStat = Darwin.stat()
        let result = name.withCString {
            Darwin.fstatat(
                directoryDescriptor,
                $0,
                &fileStat,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard result == 0 else { return nil }
        return identity(from: fileStat)
    }

    nonisolated private static func identity(
        from fileStat: Darwin.stat
    ) -> ImportedFileIdentity {
        ImportedFileIdentity(
            volumeID: UInt64(fileStat.st_dev),
            fileID: UInt64(fileStat.st_ino),
            birthTimeSeconds: Int64(fileStat.st_birthtimespec.tv_sec),
            birthTimeNanoseconds: Int64(
                fileStat.st_birthtimespec.tv_nsec
            )
        )
    }

    nonisolated static func renameSwap(
        from source: URL,
        to destination: URL
    ) -> Bool {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return false }
                return Darwin.renamex_np(
                    sourcePath,
                    destinationPath,
                    UInt32(RENAME_SWAP)
                ) == 0
            }
        }
    }

    nonisolated static func symbolicLink(
        at linkURL: URL,
        pointsTo destinationURL: URL
    ) -> Bool {
        guard isSymbolicLink(at: linkURL),
              let destination = try? FileManager.default
                .destinationOfSymbolicLink(atPath: linkURL.path) else {
            return false
        }
        let rawDestination = destination.hasPrefix("/")
            ? URL(fileURLWithPath: destination).standardizedFileURL
            : linkURL.deletingLastPathComponent()
                .appendingPathComponent(destination)
                .standardizedFileURL
        let canonicalDestination = rawDestination
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(rawDestination.lastPathComponent)
            .standardizedFileURL
        let canonicalExpected = destinationURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(destinationURL.lastPathComponent)
            .standardizedFileURL
        return CourseProjectPathPolicy.isSame(
            canonicalDestination,
            canonicalExpected
        )
    }

    private static func nanoseconds(_ date: Date?) -> Int64 {
        guard let date else { return 0 }
        return Int64((date.timeIntervalSince1970 * 1_000_000_000).rounded())
    }

    private static let supportedExtensions = Set([
        "pdf", "html", "htm", "md", "markdown", "txt", "text",
    ])
}

enum CourseProjectMutationStage: String, CaseIterable {
    case afterStagingDirectory
    case beforeManifestWrite
    case beforeAtomicPlacement
    case beforeOwnedRollbackCleanup
    case beforeCourseFileStagingCopy
    case afterCourseFileStagingCopy
    case beforeCourseFileAtomicPlacement
    case afterCourseFileDestinationValidationBeforeRename
    case afterCourseFileReplacementIsolationBeforeJournal
    case afterCourseFileReplacementRollbackCopyBeforeJournal
    case afterCourseFileReplacementTrashMoveBeforeJournal
    case afterCourseFileReplacementTrashed
    case afterCourseFileAtomicPlacement
    case afterSharedFilePlacementBeforeJournal
    case afterSharedSameVolumeStagingJournal
    case afterSharedSourceIsolationBeforeJournal
    case afterSharedOwnerLinkPrepareBeforeJournalIdentity
    case afterSharedAddedLinkPrepareBeforeJournalIdentity
    case afterSharedOwnerLinkPlacementBeforeJournal
    case afterSharedAddedLinkPlacementBeforeJournal
    case afterSharedWorkspaceSaveBeforeSourceCleanup
    case afterSharedSourceCleanupBeforeTransactionCleanup
    case afterSharedLinkPrepareBeforeJournalIdentity
    case afterSharedLinkPlacementBeforeJournal
    case beforeSharedLinkIsolation
    case afterSharedLinkIsolationBeforeJournal
    case afterSharedLinkRemovalWorkspaceSaveBeforeJournal
    case beforeSharedLinkRepair
    case afterCourseFileRollbackArtifactCreationBeforeJournalIdentity
    case afterCourseFileCleanupValidationBeforeIsolation
    case beforeCourseMarkdownTargetIsolation
    case afterCourseMarkdownTargetIsolationBeforeJournal
    case afterCourseMarkdownTargetPlacementBeforeJournal
    case beforeCourseFileWorkspaceSave
    case beforeCourseFileSourceRemoval
    case beforeCoursePortableStateCASPlacement
}

struct CourseProjectSimulatedCrash: Error {}

struct CourseProjectManifest: Codable, Equatable {
    static let currentSchemaVersion = 1

    var courseID: UUID
    var schemaVersion: Int

    init(courseID: UUID, schemaVersion: Int = currentSchemaVersion) {
        self.courseID = courseID
        self.schemaVersion = schemaVersion
    }

    static func read(from url: URL) throws -> CourseProjectManifest {
        try JSONDecoder().decode(CourseProjectManifest.self, from: Data(contentsOf: url))
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

enum CourseProjectRootError: LocalizedError {
    case emptyTitle
    case invalidDirectoryName
    case nonFileURL
    case missingLibrary
    case unavailableLibrary
    case rootMustNotExist
    case rootMustExist
    case rootMustBeDirectory
    case rootOutsideLibrary
    case dangerousRoot
    case overlappingRoot
    case rootAlreadyRegistered
    case rootIdentityUnavailable
    case bookmarkUnavailable
    case bookmarkResolutionFailed
    case securityScopeDenied
    case libraryIdentityMismatch
    case metadataConflict
    case manifestMismatch
    case workspaceSaveFailed

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "课程名称不能为空。"
        case .invalidDirectoryName:
            return "这个课程名称无法生成安全的文件夹名，请换一个名称。"
        case .nonFileURL:
            return "课程根目录必须是本地文件夹。"
        case .missingLibrary:
            return "请先配置课程资料库。"
        case .unavailableLibrary:
            return "课程资料库当前不可访问。"
        case .rootMustNotExist:
            return "新建课程的位置已经存在，请改用“纳入现有课程文件夹”。"
        case .rootMustExist:
            return "要接管的课程文件夹不存在。"
        case .rootMustBeDirectory:
            return "课程根必须是文件夹。"
        case .rootOutsideLibrary:
            return "新建课程必须位于已配置的课程资料库内。"
        case .dangerousRoot:
            return "不能把系统根、主目录、文稿目录、资料库根或魏碑共享状态目录作为课程根。"
        case .overlappingRoot:
            return "课程根不能与已有课程互相包含。"
        case .rootAlreadyRegistered:
            return "这个课程文件夹已经被魏碑纳入。"
        case .rootIdentityUnavailable:
            return "无法确认课程根的本地文件身份。"
        case .bookmarkUnavailable:
            return "无法保存文件夹访问授权。"
        case .bookmarkResolutionFailed:
            return "无法恢复文件夹访问授权。"
        case .securityScopeDenied:
            return "系统没有授予文件夹访问权限。"
        case .libraryIdentityMismatch:
            return "所选文件夹不是原来的课程资料库；更换资料库需要单独迁移，不能静默改绑。"
        case .metadataConflict:
            return "这个文件夹已有未知或损坏的 .weibei 元数据，魏碑不会覆盖它。"
        case .manifestMismatch:
            return "课程 manifest 与当前课程记录冲突。"
        case .workspaceSaveFailed:
            return "课程状态没有成功保存。魏碑只撤销能确认属于本次操作的内容；如果磁盘内容已经变化，会原样保留。"
        }
    }
}

enum CourseProjectPathPolicy {
    static func existingDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw CourseProjectRootError.nonFileURL }
        let aliasResolved = try resolveAliasIfNeeded(url.standardizedFileURL)
        let canonical = aliasResolved.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory) else {
            throw CourseProjectRootError.rootMustExist
        }
        guard isDirectory.boolValue else {
            throw CourseProjectRootError.rootMustBeDirectory
        }
        return canonical
    }

    static func newDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw CourseProjectRootError.nonFileURL }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CourseProjectRootError.rootMustNotExist
        }
        let rawParent = url.standardizedFileURL.deletingLastPathComponent()
        let parent = try existingDirectory(rawParent)
        let component = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !component.isEmpty, component != ".", component != ".." else {
            throw CourseProjectRootError.dangerousRoot
        }
        return parent.appendingPathComponent(component, isDirectory: true).standardizedFileURL
    }

    static func isSame(_ lhs: URL, _ rhs: URL) -> Bool {
        comparisonComponents(lhs, against: rhs) == comparisonComponents(rhs, against: lhs)
    }

    static func contains(_ root: URL, _ candidate: URL, includingRoot: Bool = true) -> Bool {
        let rootComponents = comparisonComponents(root, against: candidate)
        let candidateComponents = comparisonComponents(candidate, against: root)
        guard candidateComponents.count >= rootComponents.count else { return false }
        if !includingRoot, candidateComponents.count == rootComponents.count { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    static func overlaps(_ lhs: URL, _ rhs: URL) -> Bool {
        contains(lhs, rhs) || contains(rhs, lhs)
    }

    static func relativePath(of child: URL, inside root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              comparisonComponents(child, against: root)
                .prefix(rootComponents.count)
                .elementsEqual(comparisonComponents(root, against: child)) else {
            return nil
        }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    static func resolvedRelativePath(_ relativePath: String, inside root: URL) -> URL? {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        let candidate = components.reduce(root) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(root, resolved, includingRoot: false) else { return nil }
        return resolved
    }

    private static func resolveAliasIfNeeded(_ url: URL) throws -> URL {
        let values = try? url.resourceValues(forKeys: [.isAliasFileKey])
        guard values?.isAliasFile == true else { return url }
        return try URL(resolvingAliasFileAt: url, options: [.withoutUI])
    }

    private static func comparisonComponents(_ url: URL, against other: URL) -> [String] {
        let shouldFoldCase = volumeSupportsCaseSensitiveNames(for: url) == false
            && volumeSupportsCaseSensitiveNames(for: other) == false
        return url.standardizedFileURL.pathComponents.map { component in
            let normalized = component.precomposedStringWithCanonicalMapping
            guard shouldFoldCase else { return normalized }
            return normalized.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        }
    }

    static func volumeSupportsCaseSensitiveNames(for url: URL) -> Bool? {
        var candidate = url.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: candidate.path),
               let value = try? candidate.resourceValues(
                forKeys: [.volumeSupportsCaseSensitiveNamesKey]
               ).volumeSupportsCaseSensitiveNames {
                return value
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }
}
