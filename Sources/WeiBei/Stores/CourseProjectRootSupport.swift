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

struct CoursePortableExportSharedMaterial: Sendable {
    var itemID: String
    var courseRelativePath: String
    var sharedRelativePath: String
    var linkIdentity: ImportedFileIdentity
    var sourceURL: URL
    var sourceIdentity: ImportedFileIdentity
    var sourceSnapshot: CourseFileSnapshot
}

struct CoursePortableExportRequest: Sendable {
    var courseID: UUID
    var sourceRoot: URL
    var sourceRootIdentity: ImportedFileIdentity
    var sharedDirectory: URL?
    var targetRoot: URL
    var portableStateData: Data
    var requiredRegularRelativePaths: Set<String>
    var sharedMaterials: [CoursePortableExportSharedMaterial]
}

struct CoursePortableExportResult: Sendable {
    var root: URL
    var ranOnMainThread: Bool
}

enum CoursePortableExportStage: Equatable, Sendable {
    case afterStagingDirectory
    case afterVisibleTree
    case afterPortableState
    case afterManifest
    case afterCompletionMarker
    case beforeAtomicPlacement
}

private enum PortableExportTreeEntryKind: String, Codable, Equatable {
    case directory
    case regularFile
}

private struct PortableExportTreeEntry: Equatable {
    var identity: ImportedFileIdentity
    var kind: PortableExportTreeEntryKind
    var snapshot: CourseFileSnapshot?
}

private struct PortableExportTreeSnapshot: Equatable {
    var entries: [String: PortableExportTreeEntry]
    var visibleTreeSHA256: String
}

private struct PortableExportDigestEntry: Codable {
    var path: String
    var kind: PortableExportTreeEntryKind
    var byteCount: UInt64?
    var sha256: String?
}

private enum PortableExportSourceEntryKind: Equatable {
    case directory
    case regularFile
    case materializedSharedLink
}

private struct PortableExportSourceEntry: Equatable {
    var identity: ImportedFileIdentity
    var kind: PortableExportSourceEntryKind
    var snapshot: CourseFileSnapshot?
}

enum CourseProjectFileWorkerError: Error {
    case unsafePath
    case unsupportedFile
    case fileTooLarge
    case targetExists
    case contentConflict
    case verificationFailed
}

struct CoursePortableAdoptionSnapshot: Sendable {
    var metadataIdentity: ImportedFileIdentity
    var manifest: CourseProjectManifest
    var manifestData: Data
    var portableStateData: Data?
    var completionData: Data?
}

struct CoursePortableStateSaveInput: Sendable {
    var courseID: UUID
    var rootURL: URL?
    var knownRevision: UInt64?
    var knownDigest: String?
}

struct WorkspacePersistenceRequest: Sendable {
    var generation: UInt64
    var workspace: PersistedWorkspace
    var storageURL: URL
    var portableInputs: [CoursePortableStateSaveInput]
    var requiredPortableCourseIDs: Set<UUID>
    var blockedPortableCourseIDs: Set<UUID>
    var oversizedPortableCourseIDs: Set<UUID>
    var needsPortableBootstrap: Bool
}

enum WorkspacePersistenceFailure: Sendable {
    case portableState(String)
    case workspace(String)
    case rollbackConflict
    case stale
}

struct WorkspacePersistenceResult: Sendable {
    var generation: UInt64
    var failure: WorkspacePersistenceFailure?
    var portableStateRevisions: [UUID: UInt64]
    var portableStateDigests: [UUID: String]
    var dirtyPortableCourseIDs: Set<UUID>
    var blockedPortableCourseIDs: Set<UUID>
    var oversizedPortableCourseIDs: Set<UUID>
    var needsPortableBootstrap: Bool
    var persistedCourseIDs: Set<UUID>
    var ranOnMainThread: Bool
}

struct CourseRootTrashIsolation: Sendable {
    var originalURL: URL
    var transactionDirectory: URL
    var transactionDirectoryIdentity: ImportedFileIdentity
    var isolatedURL: URL
    var identity: ImportedFileIdentity
}

struct CourseTrashReceiptCleanup: Sendable {
    let courseID: UUID
    fileprivate let receiptURL: URL
    fileprivate let transactionDirectory: URL
    fileprivate let transactionDirectoryIdentity: ImportedFileIdentity
}

struct CourseDirectorySearchResult: Sendable {
    var url: URL?
    var ranOnMainThread: Bool
}

enum CoursePortableExportError: LocalizedError {
    case unstableCourseState
    case invalidSourceEntry(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .unstableCourseState:
            return "这门课程仍有回答、笔记或动作尚未保存。请先等待完成或中断，再继续。"
        case let .invalidSourceEntry(path, reason):
            return "课程内容“\(path)”无法安全导出：\(reason)"
        }
    }
}

actor CourseProjectFileWorker {
    nonisolated static let portableStateMaximumByteCount = 32 * 1024 * 1024
    nonisolated static let markdownMaximumByteCount = 32 * 1024 * 1024
    nonisolated static let markdownImageMaximumByteCount =
        MarkdownAttachmentStore.maximumImageByteCount

    private let fileManager = FileManager.default
    private var highestWorkspaceSaveGeneration: UInt64 = 0
#if DEBUG
    private var selfCheckGatedWorkspaceGeneration: UInt64?
    private var selfCheckWorkspaceGenerationEntered = false
    private var selfCheckWorkspaceEntryWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var selfCheckWorkspaceRelease:
        CheckedContinuation<Void, Never>?
    private var selfCheckFailingWorkspaceGeneration: UInt64?

    func prepareWorkspacePersistenceGateForSelfCheck(
        generation: UInt64
    ) {
        selfCheckGatedWorkspaceGeneration = generation
        selfCheckWorkspaceGenerationEntered = false
        selfCheckWorkspaceEntryWaiters = []
        selfCheckWorkspaceRelease = nil
    }

    func waitUntilWorkspacePersistenceEnteredForSelfCheck(
        generation: UInt64
    ) async {
        guard selfCheckGatedWorkspaceGeneration == generation,
              !selfCheckWorkspaceGenerationEntered else {
            return
        }
        await withCheckedContinuation { continuation in
            selfCheckWorkspaceEntryWaiters.append(continuation)
        }
    }

    func releaseWorkspacePersistenceForSelfCheck(
        generation: UInt64
    ) {
        guard selfCheckGatedWorkspaceGeneration == generation else {
            return
        }
        selfCheckWorkspaceRelease?.resume()
        selfCheckWorkspaceRelease = nil
    }

    func failWorkspacePersistenceForSelfCheck(
        generation: UInt64
    ) {
        selfCheckFailingWorkspaceGeneration = generation
    }
#endif

    func verifiedCourseRoot(
        at rawURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedCourseID: UUID
    ) -> Bool {
        guard let root = try? CourseProjectPathPolicy.existingDirectory(
            rawURL
        ),
        CourseProjectPathPolicy.isSame(rawURL, root),
        Self.identity(at: root) == expectedIdentity,
        let data = try? Self.readBoundedRegularFile(
            at: root
                .appendingPathComponent(".weibei", isDirectory: true)
                .appendingPathComponent("course.json"),
            maximumByteCount: 1_048_576
        ),
        let manifest = try? JSONDecoder().decode(
            CourseProjectManifest.self,
            from: data
        ) else {
            return false
        }
        return manifest.courseID == expectedCourseID
            && manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion
    }

    func findVerifiedCourseRoot(
        in directories: [URL],
        expectedIdentity: ImportedFileIdentity,
        expectedCourseID: UUID,
        maximumEntryCount: Int = 10_000
    ) -> URL? {
        var inspected = 0
        for directory in directories {
            guard let entries = try? fileManager
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ],
                    options: [.skipsHiddenFiles]
                ) else {
                continue
            }
            for entry in entries {
                inspected += 1
                guard inspected <= maximumEntryCount else {
                    return nil
                }
                if Self.identity(at: entry) == expectedIdentity,
                   verifiedCourseRoot(
                    at: entry,
                    expectedIdentity: expectedIdentity,
                    expectedCourseID: expectedCourseID
                   ) {
                    return entry.standardizedFileURL
                }
            }
        }
        return nil
    }

    func persistWorkspace(
        _ request: WorkspacePersistenceRequest
    ) async -> WorkspacePersistenceResult {
        let ranOnMainThread = pthread_main_np() != 0
        guard request.generation > highestWorkspaceSaveGeneration else {
            return persistenceResult(
                request: request,
                failure: .stale,
                revisions: decodedRevisions(request.workspace),
                digests: decodedDigests(request.workspace),
                dirty: Set(request.workspace.dirtyPortableCourseIDs ?? []),
                blocked: request.blockedPortableCourseIDs,
                oversized: request.oversizedPortableCourseIDs,
                needsBootstrap: request.needsPortableBootstrap,
                ranOnMainThread: ranOnMainThread
            )
        }
        highestWorkspaceSaveGeneration = request.generation
#if DEBUG
        await pauseWorkspacePersistenceForSelfCheck(
            generation: request.generation
        )
#endif

        var revisions = decodedRevisions(request.workspace)
        var digests = decodedDigests(request.workspace)
        var dirty = Set(request.workspace.dirtyPortableCourseIDs ?? [])
        var blocked = request.blockedPortableCourseIDs
        var oversized = request.oversizedPortableCourseIDs
        let previousRevisions = revisions
        let previousDigests = digests
        let previousDirty = dirty
        let previousBlocked = blocked
        let previousOversized = oversized
        let previousNeedsBootstrap = request.needsPortableBootstrap
        var needsBootstrap = request.needsPortableBootstrap
        var committedWrites: [PortableWorkspaceWrite] = []
        var conflictedCourseIDs = Set<UUID>()
        var durablePortableCourseIDs = Set<UUID>()

        do {
            for input in request.portableInputs {
                let courseID = input.courseID
                let currentRevision = revisions[courseID] ?? 0
                let knownRevision = input.knownRevision
                let knownDigest = input.knownDigest
                let stateURL = portableStateURL(rootURL: input.rootURL)
                let hasPortableHistory =
                    knownRevision != nil
                    || knownDigest != nil
                    || dirty.contains(courseID)
                    || blocked.contains(courseID)
                guard stateURL != nil || hasPortableHistory else {
                    continue
                }

                var candidate: CoursePortableState
                do {
                    candidate = try Self.makePortableState(
                        courseID: courseID,
                        revision: currentRevision,
                        savedAt: Date(timeIntervalSince1970: 0),
                        workspace: request.workspace
                    )
                } catch {
                    guard stateURL == nil, hasPortableHistory else {
                        throw error
                    }
                    dirty.insert(courseID)
                    blocked.insert(courseID)
                    continue
                }
                candidate.revision = currentRevision
                candidate.savedAt = Date(timeIntervalSince1970: 0)
                var committed = candidate
                committed.revision = currentRevision &+ 1
                committed.savedAt = Date()
                let committedData = try Self.encodedPortableState(committed)
                if committedData.count > Self.portableStateMaximumByteCount {
                    dirty.insert(courseID)
                    blocked.insert(courseID)
                    oversized.insert(courseID)
                    needsBootstrap = true
                    continue
                }
                let payloadDigest = try Self.portablePayloadDigest(candidate)
                guard let stateURL else {
                    oversized.remove(courseID)
                    if knownDigest != payloadDigest {
                        dirty.insert(courseID)
                    }
                    continue
                }

                let stateExists = fileManager.fileExists(atPath: stateURL.path)
                guard let directoryIdentity = Self.identity(
                    at: stateURL.deletingLastPathComponent()
                ) else {
                    throw CourseProjectFileWorkerError.unsafePath
                }
                if oversized.remove(courseID) != nil {
                    blocked.remove(courseID)
                }
                if blocked.contains(courseID) {
                    if knownDigest != payloadDigest {
                        dirty.insert(courseID)
                    }
                    continue
                }
                if knownDigest == payloadDigest, stateExists {
                    if request.requiredPortableCourseIDs.contains(courseID) {
                        guard let diskState = try? Self.readValidatedPortableState(
                            at: stateURL,
                            expectedDirectoryIdentity: directoryIdentity,
                            expectedCourseID: courseID
                        ),
                        diskState.revision == currentRevision,
                        (try? Self.portablePayloadDigest(diskState))
                            == knownDigest else {
                            dirty.insert(courseID)
                            blocked.insert(courseID)
                            continue
                        }
                    }
                    dirty.remove(courseID)
                    durablePortableCourseIDs.insert(courseID)
                    continue
                }
                if stateExists {
                    guard let knownDigest,
                          let diskState = try? Self.readValidatedPortableState(
                            at: stateURL,
                            expectedDirectoryIdentity: directoryIdentity,
                            expectedCourseID: courseID
                          ),
                          diskState.revision == currentRevision,
                          (try? Self.portablePayloadDigest(diskState))
                            == knownDigest else {
                        dirty.insert(courseID)
                        blocked.insert(courseID)
                        continue
                    }
                }
                let previousData = stateExists
                    ? try Self.readPortableState(
                        at: stateURL,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                    : nil
                do {
                    try Self.writePortableState(
                        committedData,
                        to: stateURL,
                        expectedDirectoryIdentity: directoryIdentity,
                        expectedPreviousData: previousData,
                        beforeCommit: {}
                    )
                    let verified = try Self.readValidatedPortableState(
                        at: stateURL,
                        expectedDirectoryIdentity: directoryIdentity,
                        expectedCourseID: courseID
                    )
                    guard verified.revision == committed.revision,
                          try Self.portablePayloadDigest(verified)
                            == payloadDigest else {
                        throw CourseProjectFileWorkerError.verificationFailed
                    }
                } catch CourseProjectFileWorkerError.contentConflict {
                    // S3：写冲突静默记入 conflicted/dirty/blocked，不拒绝整次保存。
                    conflictedCourseIDs.insert(courseID)
                    dirty.insert(courseID)
                    blocked.insert(courseID)
                    needsBootstrap = true
                    continue
                } catch {
                    try Self.restorePortableState(
                        at: stateURL,
                        previousData: previousData,
                        attemptedData: committedData,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                    throw error
                }
                committedWrites.append(
                    PortableWorkspaceWrite(
                        url: stateURL,
                        previousData: previousData,
                        committedData: committedData,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                )
                revisions[courseID] = committed.revision
                digests[courseID] = payloadDigest
                dirty.remove(courseID)
                durablePortableCourseIDs.insert(courseID)
            }
            let unresolvedRequiredCourseIDs =
                request.requiredPortableCourseIDs.subtracting(
                    durablePortableCourseIDs
                )
            // S3：未完成的可携带写回静默记 dirty/blocked，不抛拒绝。
            if !unresolvedRequiredCourseIDs.isEmpty {
                conflictedCourseIDs.formUnion(
                    unresolvedRequiredCourseIDs
                        .intersection(blocked)
                        .subtracting(oversized)
                )
                dirty.formUnion(unresolvedRequiredCourseIDs)
                blocked.formUnion(unresolvedRequiredCourseIDs)
                needsBootstrap = true
            }
        } catch {
            let rollbackFailed = Self.rollbackPortableWrites(committedWrites)
            revisions = previousRevisions
            digests = previousDigests
            dirty = previousDirty
            blocked = previousBlocked
            oversized = previousOversized
            needsBootstrap = previousNeedsBootstrap
            if !conflictedCourseIDs.isEmpty {
                dirty.formUnion(conflictedCourseIDs)
                blocked.formUnion(conflictedCourseIDs)
                needsBootstrap = true
            }
            return persistenceResult(
                request: request,
                failure: rollbackFailed
                    ? .rollbackConflict
                    : .portableState(error.localizedDescription),
                revisions: revisions,
                digests: digests,
                dirty: dirty,
                blocked: blocked,
                oversized: oversized,
                needsBootstrap: needsBootstrap,
                ranOnMainThread: ranOnMainThread
            )
        }

        needsBootstrap = !dirty.isEmpty
        var workspace = request.workspace
        workspace.coursePortableStateRevisions = Dictionary(
            uniqueKeysWithValues: revisions.map {
                ($0.key.uuidString.lowercased(), $0.value)
            }
        )
        workspace.coursePortableStateDigests = Dictionary(
            uniqueKeysWithValues: digests.map {
                ($0.key.uuidString.lowercased(), $0.value)
            }
        )
        workspace.dirtyPortableCourseIDs = dirty.sorted {
            $0.uuidString < $1.uuidString
        }
#if DEBUG
        if selfCheckFailingWorkspaceGeneration == request.generation {
            selfCheckFailingWorkspaceGeneration = nil
            let rollbackFailed = Self.rollbackPortableWrites(committedWrites)
            return persistenceResult(
                request: request,
                failure: rollbackFailed
                    ? .rollbackConflict
                    : .workspace("测试注入失败"),
                revisions: previousRevisions,
                digests: previousDigests,
                dirty: previousDirty,
                blocked: previousBlocked,
                oversized: previousOversized,
                needsBootstrap: previousNeedsBootstrap,
                ranOnMainThread: ranOnMainThread
            )
        }
#endif
        do {
            let encodeSpan = WeiBeiPerf.begin(
                "workspace.save_encode"
            )
            let data: Data
            do {
                // Phase 2：编码必须离开主线程。actor 通常已离主；若误入主线程则强制 hop。
                if pthread_main_np() != 0 {
                    data = try await Task.detached(priority: .utility) {
                        try JSONEncoder().encode(workspace)
                    }.value
                } else {
                    data = try JSONEncoder().encode(workspace)
                }
                WeiBeiPerf.end(
                    encodeSpan,
                    extra:
                        "outcome=completed generation=\(request.generation) offMain=1"
                )
            } catch {
                WeiBeiPerf.end(
                    encodeSpan,
                    extra:
                        "outcome=failed generation=\(request.generation)"
                )
                throw error
            }
            let diskSpan = WeiBeiPerf.begin(
                "workspace.save_disk_commit_and_verify"
            )
            do {
                if pthread_main_np() != 0 {
                    try await Task.detached(priority: .utility) {
                        try data.write(
                            to: request.storageURL,
                            options: [.atomic]
                        )
                        let verified = try Data(
                            contentsOf: request.storageURL
                        )
                        guard verified == data else {
                            throw CourseProjectFileWorkerError
                                .verificationFailed
                        }
                    }.value
                } else {
                    try data.write(
                        to: request.storageURL,
                        options: [.atomic]
                    )
                    let verified = try Data(contentsOf: request.storageURL)
                    guard verified == data else {
                        throw CourseProjectFileWorkerError.verificationFailed
                    }
                }
                WeiBeiPerf.end(
                    diskSpan,
                    extra:
                        "outcome=completed generation=\(request.generation) offMain=1"
                )
            } catch {
                WeiBeiPerf.end(
                    diskSpan,
                    extra:
                        "outcome=failed generation=\(request.generation)"
                )
                throw error
            }
        } catch {
            let rollbackFailed = Self.rollbackPortableWrites(committedWrites)
            return persistenceResult(
                request: request,
                failure: rollbackFailed
                    ? .rollbackConflict
                    : .workspace(error.localizedDescription),
                revisions: previousRevisions,
                digests: previousDigests,
                dirty: previousDirty,
                blocked: previousBlocked,
                oversized: previousOversized,
                needsBootstrap: previousNeedsBootstrap,
                ranOnMainThread: ranOnMainThread
            )
        }
        return persistenceResult(
            request: request,
            failure: nil,
            revisions: revisions,
            digests: digests,
            dirty: dirty,
            blocked: blocked,
            oversized: oversized,
            needsBootstrap: needsBootstrap,
            ranOnMainThread: ranOnMainThread
        )
    }

#if DEBUG
    private func pauseWorkspacePersistenceForSelfCheck(
        generation: UInt64
    ) async {
        guard selfCheckGatedWorkspaceGeneration == generation else {
            return
        }
        selfCheckWorkspaceGenerationEntered = true
        let waiters = selfCheckWorkspaceEntryWaiters
        selfCheckWorkspaceEntryWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            selfCheckWorkspaceRelease = continuation
        }
        selfCheckGatedWorkspaceGeneration = nil
        selfCheckWorkspaceGenerationEntered = false
    }
#endif

    private struct PortableWorkspaceWrite {
        var url: URL
        var previousData: Data?
        var committedData: Data
        var expectedDirectoryIdentity: ImportedFileIdentity
    }

    private func persistenceResult(
        request: WorkspacePersistenceRequest,
        failure: WorkspacePersistenceFailure?,
        revisions: [UUID: UInt64],
        digests: [UUID: String],
        dirty: Set<UUID>,
        blocked: Set<UUID>,
        oversized: Set<UUID>,
        needsBootstrap: Bool,
        ranOnMainThread: Bool
    ) -> WorkspacePersistenceResult {
        WorkspacePersistenceResult(
            generation: request.generation,
            failure: failure,
            portableStateRevisions: revisions,
            portableStateDigests: digests,
            dirtyPortableCourseIDs: dirty,
            blockedPortableCourseIDs: blocked,
            oversizedPortableCourseIDs: oversized,
            needsPortableBootstrap: needsBootstrap,
            persistedCourseIDs: Set(request.workspace.courses?.map(\.id) ?? []),
            ranOnMainThread: ranOnMainThread
        )
    }

    private func decodedRevisions(
        _ workspace: PersistedWorkspace
    ) -> [UUID: UInt64] {
        Dictionary(
            uniqueKeysWithValues: (workspace.coursePortableStateRevisions ?? [:])
                .compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
        )
    }

    private func decodedDigests(
        _ workspace: PersistedWorkspace
    ) -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: (workspace.coursePortableStateDigests ?? [:])
                .compactMap { key, value in
                    UUID(uuidString: key).map { ($0, value) }
                }
        )
    }

    private func portableStateURL(rootURL: URL?) -> URL? {
        guard let rootURL else { return nil }
        guard let root = try? CourseProjectPathPolicy.existingDirectory(
            rootURL
        ),
        let metadata = try? CourseProjectPathPolicy.existingDirectory(
            root.appendingPathComponent(".weibei", isDirectory: true)
        ),
        CourseProjectPathPolicy.contains(
            root,
            metadata,
            includingRoot: false
        ),
        CourseProjectPathPolicy.isSame(
            metadata,
            metadata.resolvingSymlinksInPath()
        ) else {
            return nil
        }
        return metadata.appendingPathComponent(
            "course-state.json",
            isDirectory: false
        )
    }

    nonisolated static func makePortableState(
        courseID: UUID,
        revision: UInt64,
        savedAt: Date,
        workspace: PersistedWorkspace
    ) throws -> CoursePortableState {
        guard let course = workspace.courses?.first(where: {
            $0.id == courseID
        }) else {
            throw CoursePortableStateError.courseIdentityMismatch
        }
        let memberships = (workspace.courseItemMemberships ?? [])
            .filter { $0.courseID == courseID }
            .sorted {
                ($0.courseRelativePath ?? "").localizedStandardCompare(
                    $1.courseRelativePath ?? ""
                ) == .orderedAscending
            }
        var importedItemsByID: [String: StudyItem] = [:]
        for item in workspace.importedItems
        where importedItemsByID[item.id] == nil {
            importedItemsByID[item.id] = item
        }
        var portableItems: [CoursePortableItem] = []
        for membership in memberships {
            guard let relativePath = membership.courseRelativePath else {
                throw CoursePortableStateError.missingCourseItem
            }
            guard let item = importedItemsByID[membership.itemID] else {
                throw CoursePortableStateError.missingCourseItem
            }
            let storage: CoursePortableItemStorage
            switch item.storage {
            case .courseOwned(let ownerCourseID)
                where ownerCourseID == courseID:
                storage = .courseOwned
            case let .shared(sharedRelativePath):
                storage = .sharedReference(
                    sharedRelativePath: sharedRelativePath,
                    expectedContentDigest: item.contentDigest
                )
            default:
                throw CoursePortableStateError.invalidItemStorage
            }
            portableItems.append(
                CoursePortableItem(
                    itemID: item.id,
                    title: item.title,
                    kind: item.kind,
                    isNotebookNote: item.isNotebookNote,
                    courseRelativePath: relativePath,
                    storage: storage,
                    contentRevision: item.contentRevision,
                    contentDigest: item.contentDigest,
                    fileByteCount: item.fileByteCount,
                    fileModificationTimeNanoseconds:
                        item.fileModificationTimeNanoseconds,
                    membershipCreatedAt: membership.createdAt
                )
            )
        }

        let portableItemIDs = Set(portableItems.map(\.itemID))
        let noteItemIDs = Set(
            portableItems.lazy.filter(\.isNotebookNote).map(\.itemID)
        )
        let materialItemIDs = portableItemIDs.subtracting(noteItemIDs)
        let rawMemoryState = workspace.learningMemoryStates?.first {
            $0.scope == .course(courseID)
        }
        let courseKnowledgeProfile = workspace.courseKnowledgeProfiles?.first {
            $0.courseID == courseID
        }?.retainingAvailableSources(
            materialItemIDs: materialItemIDs,
            noteItemIDs: noteItemIDs
        )
        let memoryIDs = Set(rawMemoryState?.entries.map(\.id) ?? [])
        let relations = (workspace.noteSourceLinks ?? []).filter {
            noteItemIDs.contains($0.noteItemID)
                && materialItemIDs.contains($0.sourceItemID)
        }
        .sorted {
            $0.createdAt == $1.createdAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.createdAt < $1.createdAt
        }
        let relationIDs = Set(relations.map(\.id))
        var relationsByID: [UUID: NoteSourceLink] = [:]
        for relation in relations {
            relationsByID[relation.id] = relation
        }
        let sessions = (workspace.studySessions ?? []).compactMap {
            current -> StudySession? in
            guard current.courseID == courseID,
                  current.scopeNeedsReview == false else {
                return nil
            }
            var portable = current
            portable.focusItemIDs = portable.focusItemIDs.filter(
                portableItemIDs.contains
            )
            if let materialItemID = portable.materialItemID,
               !materialItemIDs.contains(materialItemID) {
                portable.materialItemID = nil
            }
            for index in portable.messages.indices {
                portable.messages[index].toolTrace = []
                portable.messages[index].sources =
                    portable.messages[index].sources.filter { source in
                        guard let itemID = source.itemID else {
                            return source.courseID.map {
                                $0 == courseID
                            } ?? true
                        }
                        guard portableItemIDs.contains(itemID),
                              source.courseID.map({
                                  $0 == courseID
                              }) ?? true else {
                            return false
                        }
                        switch source.kind {
                        case .material:
                            return materialItemIDs.contains(itemID)
                        case .note:
                            return noteItemIDs.contains(itemID)
                        case .selection:
                            return true
                        }
                    }
                portable.messages[index].actions =
                    portable.messages[index].actions.filter { action in
                        guard action.targetItemID.map(
                            portableItemIDs.contains
                        ) ?? true,
                        action.sourceItemID.map(
                            portableItemIDs.contains
                        ) ?? true else {
                            return false
                        }
                        switch action.kind {
                        case .writeNote:
                            let hasValidTarget = action.targetItemID.map(
                                noteItemIDs.contains
                            ) ?? true
                            return hasValidTarget
                                && action.createdRelationID == nil
                        case .createRelation:
                            let hasValidTarget = action.targetItemID.map(
                                noteItemIDs.contains
                            ) ?? true
                            let hasValidSource = action.sourceItemID.map(
                                materialItemIDs.contains
                            ) ?? true
                            let hasValidCreatedRelation =
                                action.createdRelationID.map {
                                    relationID in
                                    guard relationIDs.contains(relationID),
                                          let relation =
                                            relationsByID[relationID],
                                          let targetItemID =
                                            action.targetItemID,
                                          let sourceItemID =
                                            action.sourceItemID else {
                                        return false
                                    }
                                    return relation.noteItemID
                                        == targetItemID
                                        && relation.sourceItemID
                                            == sourceItemID
                                } ?? true
                            return hasValidTarget
                                && hasValidSource
                                && hasValidCreatedRelation
                        }
                    }
                if var memoryUpdate =
                    portable.messages[index].memoryUpdate {
                    memoryUpdate.memoryIDs =
                        memoryUpdate.memoryIDs.filter(
                            memoryIDs.contains
                        )
                    portable.messages[index].memoryUpdate =
                        memoryUpdate.memoryIDs.isEmpty
                            ? nil
                            : memoryUpdate
                }
                if let origin = portable.messages[index].origin,
                   origin.courseID != courseID
                    || origin.chatID != portable.id {
                    portable.messages[index].origin = nil
                }
            }
            return portable
        }
        .sorted { $0.createdAt < $1.createdAt }
        let messageIDsBySessionID = Dictionary(
            uniqueKeysWithValues: sessions.map {
                ($0.id, Set($0.messages.map(\.id)))
            }
        )
        func sanitizedMemoryProvenance(
            sessionID: UUID?,
            messageID: UUID?
        ) -> (sessionID: UUID?, messageID: UUID?) {
            guard let sessionID,
                  let liveMessageIDs =
                    messageIDsBySessionID[sessionID] else {
                return (nil, nil)
            }
            guard let messageID else {
                return (sessionID, nil)
            }
            return liveMessageIDs.contains(messageID)
                ? (sessionID, messageID)
                : (sessionID, nil)
        }
        var memoryState = rawMemoryState
        if var sanitizedMemoryState = memoryState {
            for entryIndex in sanitizedMemoryState.entries.indices {
                var entry = sanitizedMemoryState.entries[entryIndex]
                let provenance = sanitizedMemoryProvenance(
                    sessionID: entry.sessionID,
                    messageID: entry.messageID
                )
                entry.sessionID = provenance.sessionID
                entry.messageID = provenance.messageID
                if var revisions = entry.revisions {
                    for revisionIndex in revisions.indices {
                        let revisionProvenance =
                            sanitizedMemoryProvenance(
                                sessionID:
                                    revisions[revisionIndex].sessionID,
                                messageID:
                                    revisions[revisionIndex].messageID
                            )
                        revisions[revisionIndex].sessionID =
                            revisionProvenance.sessionID
                        revisions[revisionIndex].messageID =
                            revisionProvenance.messageID
                    }
                    entry.revisions = revisions
                }
                sanitizedMemoryState.entries[entryIndex] = entry
            }
            memoryState = sanitizedMemoryState
        }

        let membershipsByItemID = Dictionary(
            grouping: workspace.courseItemMemberships ?? [],
            by: \.itemID
        )
        let resumePoint = workspace.courseResumePoints?
            .filter { $0.courseID == courseID }
            .sorted { $0.savedAt > $1.savedAt }
            .first
        var locations: [String: StudyLocation] = [:]
        for itemID in materialItemIDs.sorted() {
            let scoped =
                workspace.studyLocationsByCourseID?[
                    courseID.uuidString
                ]?[itemID]
                ?? (
                    resumePoint?.materialLocation?.itemID == itemID
                        ? resumePoint?.materialLocation
                        : nil
                )
                ?? (
                    (membershipsByItemID[itemID]?.count ?? 0) > 1
                        ? nil
                        : workspace.studyLocationsByItemID?[itemID]
                )
            if var scoped {
                scoped.itemID = itemID
                locations[itemID] = scoped
            }
        }
        // C2：草稿以 notesByItemID 为准；baseline 有 pending 则取，无则 nil。
        let drafts = noteItemIDs.sorted().compactMap {
            itemID -> CoursePortableNoteDraft? in
            guard let markdown = workspace.notesByItemID[itemID] else {
                return nil
            }
            return CoursePortableNoteDraft(
                itemID: itemID,
                markdown: markdown,
                baselineContentDigest: workspace.pendingNoteWritesByItemID?[itemID]?
                    .baselineContentDigest
            )
        }
        return try CoursePortableState(
            courseID: courseID,
            revision: revision,
            savedAt: savedAt,
            metadata: CoursePortableMetadata(
                title: course.title,
                colorIndex: course.colorIndex,
                createdAt: course.createdAt,
                updatedAt: course.updatedAt
            ),
            items: portableItems,
            studySessions: sessions,
            learningMemoryState: memoryState,
            courseKnowledgeProfile: courseKnowledgeProfile,
            noteSourceLinks: relations,
            studyLocationsByItemID: locations,
            resumePoint: resumePoint,
            pendingNoteDrafts: drafts
        ).validated(expectedCourseID: courseID)
    }

    nonisolated private static func encodedPortableState(
        _ state: CoursePortableState
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    nonisolated private static func portablePayloadDigest(
        _ state: CoursePortableState
    ) throws -> String {
        var normalized = state
        normalized.revision = 0
        normalized.savedAt = Date(timeIntervalSince1970: 0)
        return SHA256.hash(data: try encodedPortableState(normalized))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated private static func readValidatedPortableState(
        at url: URL,
        expectedDirectoryIdentity: ImportedFileIdentity,
        expectedCourseID: UUID
    ) throws -> CoursePortableState {
        try JSONDecoder()
            .decode(
                CoursePortableState.self,
                from: readPortableState(
                    at: url,
                    expectedDirectoryIdentity: expectedDirectoryIdentity
                )
            )
            .validated(expectedCourseID: expectedCourseID)
    }

    nonisolated private static func rollbackPortableWrites(
        _ writes: [PortableWorkspaceWrite]
    ) -> Bool {
        var failed = false
        for write in writes.reversed() {
            do {
                try restorePortableState(
                    at: write.url,
                    previousData: write.previousData,
                    attemptedData: write.committedData,
                    expectedDirectoryIdentity:
                        write.expectedDirectoryIdentity
                )
            } catch {
                failed = true
            }
        }
        return failed
    }

    func exportPortableCourse(
        _ request: CoursePortableExportRequest,
        stageHook: @Sendable (CoursePortableExportStage) throws -> Void = { _ in }
    ) throws -> CoursePortableExportResult {
        let ranOnMainThread = Thread.isMainThread
        let sourceRoot = try CourseProjectPathPolicy.existingDirectory(
            request.sourceRoot
        )
        guard Self.identity(at: sourceRoot) == request.sourceRootIdentity,
              request.portableStateData.count <= Self.portableStateMaximumByteCount else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let targetRoot = try CourseProjectPathPolicy.newDirectory(
            request.targetRoot
        )
        let targetParent = try CourseProjectPathPolicy.existingDirectory(
            targetRoot.deletingLastPathComponent()
        )
        guard let targetParentIdentity = Self.identity(at: targetParent),
              !CourseProjectPathPolicy.contains(
                sourceRoot,
                targetRoot,
                includingRoot: true
              ),
              !CourseProjectPathPolicy.contains(
                targetRoot,
                sourceRoot,
                includingRoot: true
              ) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        if let rawSharedDirectory = request.sharedDirectory {
            let sharedDirectory = try CourseProjectPathPolicy.existingDirectory(
                rawSharedDirectory
            )
            guard !CourseProjectPathPolicy.contains(
                sharedDirectory,
                targetRoot,
                includingRoot: true
            ),
            !CourseProjectPathPolicy.contains(
                targetRoot,
                sharedDirectory,
                includingRoot: true
            ) else {
                throw CourseProjectFileWorkerError.unsafePath
            }
        }

        let stagingName =
            ".weibei-course-export-\(UUID().uuidString.lowercased())"
        let stagingRoot = targetParent.appendingPathComponent(
            stagingName,
            isDirectory: true
        )
        let targetParentDescriptor = try Self.openDirectory(
            targetParent,
            expectedIdentity: targetParentIdentity
        )
        defer { Darwin.close(targetParentDescriptor) }
        try Self.createDirectory(
            named: stagingName,
            relativeTo: targetParentDescriptor
        )
        let stagingDescriptor = try Self.openDirectory(
            named: stagingName,
            relativeTo: targetParentDescriptor
        )
        defer { Darwin.close(stagingDescriptor) }
        guard let stagingIdentity = Self.identity(
            ofOpenDescriptor: stagingDescriptor
        ) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        var exportCommitted = false
        var metadataDescriptor: Int32?
        defer {
            if !exportCommitted, let metadataDescriptor {
                try? Self.markPortableExportAbandoned(
                    relativeTo: metadataDescriptor,
                    rootDescriptor: stagingDescriptor
                )
            }
            if let metadataDescriptor {
                Darwin.close(metadataDescriptor)
            }
        }

        try stageHook(.afterStagingDirectory)
        var sharedByCoursePath: [
            String: CoursePortableExportSharedMaterial
        ] = [:]
        for shared in request.sharedMaterials {
            guard sharedByCoursePath.updateValue(
                shared,
                forKey: shared.courseRelativePath
            ) == nil else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
        }
        var materializedSharedPaths = Set<String>()
        var sourceEntries: [String: PortableExportSourceEntry] = [:]
        try copyVisibleCourseTree(
            from: sourceRoot,
            sourceRoot: sourceRoot,
            sourceRootIdentity: request.sourceRootIdentity,
            stagingDescriptor: stagingDescriptor,
            sharedByCoursePath: sharedByCoursePath,
            materializedSharedPaths: &materializedSharedPaths,
            sourceEntries: &sourceEntries
        )
        guard materializedSharedPaths == Set(sharedByCoursePath.keys) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let finalSourceEntries = try portableExportSourceEntries(
            at: sourceRoot,
            expectedRootIdentity: request.sourceRootIdentity,
            sharedByCoursePath: sharedByCoursePath
        )
        guard finalSourceEntries == sourceEntries else {
            throw CourseProjectFileWorkerError.contentConflict
        }
        for relativePath in request.requiredRegularRelativePaths {
            guard try Self.regularFileSnapshot(
                atRelativePath: relativePath,
                rootDescriptor: stagingDescriptor
            ) != nil else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
        }
        let visibleTreeSHA256 = try Self.treeSnapshot(
            relativeTo: stagingDescriptor,
            includeHidden: false
        ).visibleTreeSHA256
        try stageHook(.afterVisibleTree)

        try Self.createDirectory(
            named: ".weibei",
            relativeTo: stagingDescriptor
        )
        let openedMetadataDescriptor = try Self.openDirectory(
            named: ".weibei",
            relativeTo: stagingDescriptor
        )
        metadataDescriptor = openedMetadataDescriptor
        try Self.writeExclusiveData(
            request.portableStateData,
            named: "course-state.json",
            relativeTo: openedMetadataDescriptor
        )
        let stateSnapshot = Self.snapshot(
            of: request.portableStateData
        )
        try stageHook(.afterPortableState)

        let provenance = request.sharedMaterials.map {
            CourseProjectSharedMaterialProvenance(
                itemID: $0.itemID,
                courseRelativePath: $0.courseRelativePath,
                sharedRelativePath: $0.sharedRelativePath,
                sourceIdentity: $0.sourceIdentity,
                sourceContentDigest: $0.sourceSnapshot.sha256
            )
        }.sorted {
            $0.courseRelativePath < $1.courseRelativePath
        }
        let manifest = CourseProjectManifest(
            courseID: request.courseID,
            portableExport: CourseProjectPortableExportMetadata(
                portableStateSHA256: stateSnapshot.sha256,
                visibleTreeSHA256: visibleTreeSHA256,
                materializedSharedItems: provenance
            )
        )
        let manifestData = try manifest.encoded()
        try Self.writeExclusiveData(
            manifestData,
            named: "course.json",
            relativeTo: openedMetadataDescriptor
        )
        let manifestSnapshot = Self.snapshot(of: manifestData)
        try stageHook(.afterManifest)

        let completion = CourseProjectPortableExportCompletion(
            courseID: request.courseID,
            manifestSHA256: manifestSnapshot.sha256,
            portableStateSHA256: stateSnapshot.sha256,
            visibleTreeSHA256: visibleTreeSHA256
        )
        try Self.writeExclusiveData(
            completion.encoded(),
            named: CourseProjectManifest.portableExportCompletionFileName,
            relativeTo: openedMetadataDescriptor
        )
        guard Darwin.fsync(openedMetadataDescriptor) == 0,
              Darwin.fsync(stagingDescriptor) == 0 else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let sealedSnapshot = try Self.validatedPortableAdoptionSnapshot(
            rootDescriptor: stagingDescriptor,
            expectedRootIdentity: stagingIdentity
        )
        guard sealedSnapshot.manifestData == manifestData else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let stagedTree = try Self.treeSnapshot(
            relativeTo: stagingDescriptor,
            includeHidden: true
        )
        try stageHook(.afterCompletionMarker)
        try stageHook(.beforeAtomicPlacement)

        // S6-9：源树在导出期间若仅 digest/条目漂移，以已封存的 staging 为准继续落位；
        // 源根身份变化或 staging 自损仍失败。
        guard Self.identity(at: sourceRoot) == request.sourceRootIdentity,
              Self.identity(at: targetParent) == targetParentIdentity,
              Self.identity(at: stagingRoot) == stagingIdentity,
              try Self.treeSnapshot(
                  relativeTo: stagingDescriptor,
                  includeHidden: true
              ) == stagedTree else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let liveSourceEntries = try? portableExportSourceEntries(
            at: sourceRoot,
            expectedRootIdentity: request.sourceRootIdentity,
            sharedByCoursePath: sharedByCoursePath
        )
        if liveSourceEntries != sourceEntries {
            NSLog(
                "[WeiBei export] source tree drifted during export; using sealed staging (course=%@)",
                request.courseID.uuidString
            )
        }
        _ = try Self.renameWithoutReplacementAnchored(
            from: stagingRoot,
            to: targetRoot,
            expectedSourceIdentity: stagingIdentity,
            expectedDestinationDirectoryIdentity: targetParentIdentity,
            beforeRename: {}
        )
        guard Self.identity(at: targetRoot) == stagingIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let placedDescriptor = try Self.openDirectory(
            targetRoot,
            expectedIdentity: stagingIdentity
        )
        defer { Darwin.close(placedDescriptor) }
        guard try Self.treeSnapshot(
            relativeTo: placedDescriptor,
            includeHidden: true
        ) == stagedTree else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        _ = try Self.validatedPortableAdoptionSnapshot(
            rootDescriptor: placedDescriptor,
            expectedRootIdentity: stagingIdentity
        )
        exportCommitted = true
        return CoursePortableExportResult(
            root: targetRoot,
            ranOnMainThread: ranOnMainThread
        )
    }

    func snapshot(at url: URL) throws -> CourseFileSnapshot {
        try Self.snapshotFile(at: url)
    }

    func snapshotWithThreadEvidence(
        at url: URL
    ) throws -> (snapshot: CourseFileSnapshot, ranOnMainThread: Bool) {
        (try Self.snapshotFile(at: url), Thread.isMainThread)
    }

    func findDirectory(
        with identity: ImportedFileIdentity,
        inside libraryRoot: URL
    ) -> CourseDirectorySearchResult {
        let ranOnMainThread = Thread.isMainThread
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return CourseDirectorySearchResult(
                url: nil,
                ranOnMainThread: ranOnMainThread
            )
        }
        // S6-6：跟随符号链接目录（解析后比对身份），canonical 路径防环。
        var visitedCanonicalPaths = Set<String>()
        for case let candidate as URL in enumerator {
            let values = try? candidate.resourceValues(forKeys: keys)
            guard values?.isDirectory == true else { continue }
            let canonical = candidate.resolvingSymlinksInPath()
                .standardizedFileURL
            if visitedCanonicalPaths.contains(canonical.path) {
                enumerator.skipDescendants()
                continue
            }
            visitedCanonicalPaths.insert(canonical.path)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
            }
            if Self.identity(at: canonical) == identity {
                return CourseDirectorySearchResult(
                    url: canonical,
                    ranOnMainThread: ranOnMainThread
                )
            }
        }
        return CourseDirectorySearchResult(
            url: nil,
            ranOnMainThread: ranOnMainThread
        )
    }

    func adoptionSnapshot(
        at rootURL: URL,
        expectedRootIdentity: ImportedFileIdentity
    ) throws -> CoursePortableAdoptionSnapshot {
        try Self.portableAdoptionSnapshot(
            at: rootURL,
            expectedRootIdentity: expectedRootIdentity
        )
    }

    func adoptionSnapshotWithThreadEvidence(
        at rootURL: URL,
        expectedRootIdentity: ImportedFileIdentity
    ) throws -> (
        snapshot: CoursePortableAdoptionSnapshot,
        ranOnMainThread: Bool
    ) {
        let ranOnMainThread = Thread.isMainThread
        return (
            try Self.portableAdoptionSnapshot(
                at: rootURL,
                expectedRootIdentity: expectedRootIdentity
            ),
            ranOnMainThread
        )
    }

    func normalizePortableCourseManifest(
        with data: Data,
        at url: URL,
        expectedDirectoryIdentity: ImportedFileIdentity,
        expectedPreviousData: Data
    ) throws {
        try Self.replaceCourseManifest(
            with: data,
            at: url,
            expectedDirectoryIdentity: expectedDirectoryIdentity,
            expectedPreviousData: expectedPreviousData
        )
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
        let data = try Self.readBoundedRegularFile(
            at: source.url,
            maximumByteCount: Self.markdownMaximumByteCount
        )
        let byteCount = UInt64(data.count)
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
                sha256: SHA256.hash(data: data)
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

    nonisolated static func readBoundedRegularFile(
        at url: URL,
        maximumByteCount: Int
    ) throws -> Data {
        guard maximumByteCount >= 0,
              let directoryIdentity = identity(
                  at: url.deletingLastPathComponent()
              ) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let directory = url.deletingLastPathComponent()
        let directoryDescriptor = try openDirectory(
            directory,
            expectedIdentity: directoryIdentity
        )
        defer { Darwin.close(directoryDescriptor) }
        guard let data = try readRegularFile(
            named: url.lastPathComponent,
            relativeTo: directoryDescriptor,
            maximumByteCount: maximumByteCount
        ),
        identity(at: directory) == directoryIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return data
    }

    nonisolated static func readBoundedRegularFile(
        at url: URL,
        inside root: URL,
        maximumByteCount: Int
    ) throws -> Data {
        guard maximumByteCount >= 0,
              let relativePath = CourseProjectPathPolicy.relativePath(
                  of: url,
                  inside: root
              ),
              let rootIdentity = identity(at: root) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let components = try safeRelativePathComponents(relativePath)
        guard let name = components.last else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let rootDescriptor = try openDirectory(
            root,
            expectedIdentity: rootIdentity
        )
        defer { Darwin.close(rootDescriptor) }
        let parentDescriptor = try openDirectory(
            atRelativePath: components.dropLast().joined(separator: "/"),
            rootDescriptor: rootDescriptor
        )
        defer { Darwin.close(parentDescriptor) }
        guard let data = try readRegularFile(
            named: name,
            relativeTo: parentDescriptor,
            maximumByteCount: maximumByteCount
        ),
        identity(at: root) == rootIdentity else {
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
        guard let previousData else {
            let currentData = try readRegularFile(
                named: name,
                relativeTo: directoryDescriptor,
                maximumByteCount: portableStateMaximumByteCount
            )
            if currentData == nil {
                return
            }
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

        let currentData: Data?
        let currentStateWasUnreadable: Bool
        do {
            currentData = try readRegularFile(
                named: name,
                relativeTo: directoryDescriptor,
                maximumByteCount: portableStateMaximumByteCount
            )
            currentStateWasUnreadable = false
        } catch {
            currentData = nil
            currentStateWasUnreadable = true
        }
        if !currentStateWasUnreadable, currentData == previousData {
            return
        }
        if !currentStateWasUnreadable, currentData == attemptedData {
            try compareAndSwapPortableStateData(
                previousData,
                expectedPreviousData: attemptedData,
                named: name,
                relativeTo: directoryDescriptor,
                beforeCommit: {}
            )
        } else {
            let candidateName =
                "course-state-conflict-\(UUID().uuidString.lowercased()).json"
            try writeExclusiveData(
                attemptedData,
                named: candidateName,
                relativeTo: directoryDescriptor
            )
            guard Darwin.fsync(directoryDescriptor) == 0,
                  identity(at: directory) == expectedDirectoryIdentity else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
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
            if moved != 0, errno != ENOENT {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            guard Darwin.fsync(directoryDescriptor) == 0,
                  identity(at: directory) == expectedDirectoryIdentity else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            try compareAndSwapPortableStateData(
                previousData,
                expectedPreviousData: nil,
                named: name,
                relativeTo: directoryDescriptor,
                beforeCommit: {}
            )
        }
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
        if WeiBeiSafetyTestMode.isEnabled {
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

    func isolateCourseRootForTrash(
        at rawRoot: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedCourseID: UUID,
        transactionID: UUID,
        beforeIsolation: () throws -> Void = {}
    ) throws -> CourseRootTrashIsolation {
        let root = try CourseProjectPathPolicy.existingDirectory(rawRoot)
        let metadata = root.appendingPathComponent(
            ".weibei",
            isDirectory: true
        )
        let metadataValues = try metadata.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard CourseProjectPathPolicy.isSame(rawRoot, root),
              Self.identity(at: root) == expectedIdentity,
              metadataValues.isDirectory == true,
              metadataValues.isSymbolicLink != true,
              metadataValues.isAliasFile != true,
              CourseProjectPathPolicy.isSame(
                metadata,
                metadata.resolvingSymlinksInPath()
              ),
              CourseProjectPathPolicy.contains(
                root,
                metadata,
                includingRoot: false
              ) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let manifestData = try Self.readBoundedRegularFile(
            at: metadata.appendingPathComponent("course.json"),
            maximumByteCount: 1_048_576
        )
        let manifest = try JSONDecoder().decode(
            CourseProjectManifest.self,
            from: manifestData
        )
        guard manifest.courseID == expectedCourseID,
              manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion,
              Self.identity(at: root) == expectedIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }

        let transactionDirectory = root.deletingLastPathComponent()
            .appendingPathComponent(
                ".weibei-course-removal-\(transactionID.uuidString.lowercased())",
                isDirectory: true
            )
        guard !fileManager.fileExists(
            atPath: transactionDirectory.path
        ) else {
            throw CourseProjectFileWorkerError.targetExists
        }
        try fileManager.createDirectory(
            at: transactionDirectory,
            withIntermediateDirectories: false
        )
        guard let transactionDirectoryIdentity =
                Self.identity(at: transactionDirectory),
              CourseProjectPathPolicy.isSame(
                transactionDirectory,
                transactionDirectory.resolvingSymlinksInPath()
              ) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let isolatedRoot = transactionDirectory.appendingPathComponent(
            root.lastPathComponent,
            isDirectory: true
        )
        do {
            _ = try Self.renameWithoutReplacementAnchored(
                from: root,
                to: isolatedRoot,
                expectedSourceIdentity: expectedIdentity,
                expectedDestinationDirectoryIdentity:
                    transactionDirectoryIdentity,
                beforeRename: beforeIsolation
            )
            let isolatedMetadata = isolatedRoot.appendingPathComponent(
                ".weibei",
                isDirectory: true
            )
            let isolatedManifestData = try Self.readBoundedRegularFile(
                at: isolatedMetadata.appendingPathComponent(
                    "course.json"
                ),
                maximumByteCount: 1_048_576
            )
            let isolatedManifest = try JSONDecoder().decode(
                CourseProjectManifest.self,
                from: isolatedManifestData
            )
            guard Self.identity(at: isolatedRoot) == expectedIdentity,
                  isolatedManifest.courseID == expectedCourseID,
                  isolatedManifest.schemaVersion
                    == CourseProjectManifest.currentSchemaVersion else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            return CourseRootTrashIsolation(
                originalURL: root,
                transactionDirectory: transactionDirectory,
                transactionDirectoryIdentity:
                    transactionDirectoryIdentity,
                isolatedURL: isolatedRoot,
                identity: expectedIdentity
            )
        } catch {
            if Self.identity(at: isolatedRoot) == expectedIdentity,
               !fileManager.fileExists(atPath: root.path) {
                _ = Self.renameWithoutReplacement(
                    from: isolatedRoot,
                    to: root
                )
            }
            if !fileManager.fileExists(atPath: isolatedRoot.path) {
                removeEmptyDirectory(
                    transactionDirectory,
                    expectedIdentity:
                        transactionDirectoryIdentity
                )
            }
            throw error
        }
    }

    /// S3：隔离后后续步骤失败时，把课程根尽力还原到原路径并清掉空事务目录。
    func restoreCourseRootTrashIsolation(
        _ isolation: CourseRootTrashIsolation
    ) {
        let isolatedStillPresent =
            Self.identity(at: isolation.isolatedURL) == isolation.identity
        let originalStillPresent =
            Self.identity(at: isolation.originalURL) == isolation.identity
        if isolatedStillPresent, !originalStillPresent {
            _ = Self.renameWithoutReplacement(
                from: isolation.isolatedURL,
                to: isolation.originalURL
            )
        }
        if !fileManager.fileExists(atPath: isolation.isolatedURL.path) {
            removeEmptyDirectory(
                isolation.transactionDirectory,
                expectedIdentity: isolation.transactionDirectoryIdentity
            )
        }
    }

    func moveIsolatedCourseRootToTrash(
        _ isolation: CourseRootTrashIsolation,
        expectedCourseID: UUID,
        selfCheckDestination: URL
    ) throws -> URL {
        let isolatedRoot = try CourseProjectPathPolicy.existingDirectory(
            isolation.isolatedURL
        )
        let manifestData = try Self.readBoundedRegularFile(
            at: isolatedRoot
                .appendingPathComponent(".weibei", isDirectory: true)
                .appendingPathComponent("course.json"),
            maximumByteCount: 1_048_576
        )
        let manifest = try JSONDecoder().decode(
            CourseProjectManifest.self,
            from: manifestData
        )
        guard CourseProjectPathPolicy.isSame(
                isolatedRoot,
                isolation.isolatedURL
              ),
              Self.identity(at: isolatedRoot) == isolation.identity,
              manifest.courseID == expectedCourseID,
              manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion else {
            throw CourseProjectFileWorkerError.verificationFailed
        }

        let movedRoot: URL
        if WeiBeiSafetyTestMode.isEnabled {
            try fileManager.createDirectory(
                at: selfCheckDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(
                atPath: selfCheckDestination.path
            ),
            Self.renameWithoutReplacement(
                from: isolatedRoot,
                to: selfCheckDestination
            ) else {
                throw POSIXError(
                    POSIXErrorCode(rawValue: errno) ?? .EIO
                )
            }
            movedRoot = selfCheckDestination
        } else {
            var resultingURL: NSURL?
            try fileManager.trashItem(
                at: isolatedRoot,
                resultingItemURL: &resultingURL
            )
            guard let resultingURL else {
                throw CourseProjectFileWorkerError.verificationFailed
            }
            movedRoot = (resultingURL as URL).standardizedFileURL
        }
        guard Self.identity(at: isolation.originalURL)
                != isolation.identity,
              Self.identity(at: movedRoot) == isolation.identity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        removeEmptyDirectory(
            isolation.transactionDirectory,
            expectedIdentity:
                isolation.transactionDirectoryIdentity
        )
        return movedRoot
    }

    private func removeEmptyDirectory(
        _ url: URL,
        expectedIdentity: ImportedFileIdentity
    ) {
        guard Self.identity(at: url) == expectedIdentity else {
            return
        }
        _ = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.rmdir(path)
        }
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
        guard WeiBeiSafetyTestMode.isEnabled else {
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
        var visitedFileKeys = Set<String>()
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
                // 目录符号链接不向下枚举（防环）；findDirectory 负责跟随目录链接定位。
                if values.isSymbolicLink == true || values.isAliasFile == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            // S6-6：允许文件符号链接——按解析后的真实文件登记（同路径只记一次）。
            // H3：解析后必须仍在课程根内，根外目标跳过登记（默认沉默）。
            let isLink = values.isSymbolicLink == true || values.isAliasFile == true
            let fileURL: URL
            let fileValues: URLResourceValues
            if isLink {
                fileURL = rawURL.resolvingSymlinksInPath().standardizedFileURL
                guard CourseProjectPathPolicy.contains(
                        canonicalRoot,
                        fileURL,
                        includingRoot: false
                      ) else {
                    NSLog(
                        "[WeiBei scan] skip course symlink outside root: %@ -> %@",
                        rawURL.path,
                        fileURL.path
                    )
                    continue
                }
                guard let resolvedValues = try? fileURL.resourceValues(forKeys: keys),
                      resolvedValues.isRegularFile == true,
                      resolvedValues.isSymbolicLink != true,
                      resolvedValues.isAliasFile != true else {
                    continue
                }
                fileValues = resolvedValues
            } else {
                guard values.isRegularFile == true else { continue }
                fileURL = rawURL.standardizedFileURL
                fileValues = values
            }
            guard Self.supportedExtensions.contains(
                    fileURL.pathExtension.lowercased()
                  ),
                  let identity = Self.identity(at: fileURL) else {
                continue
            }
            let identityKey =
                "\(identity.volumeID).\(identity.fileID).\(relativePath)"
            if visitedFileKeys.contains(identityKey) {
                continue
            }
            visitedFileKeys.insert(identityKey)
            let firstComponent = relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .first
            let isMarkdown = ["md", "markdown"]
                .contains(fileURL.pathExtension.lowercased())
            result.append(
                CourseFileMetadata(
                    url: fileURL,
                    relativePath: relativePath,
                    identity: identity,
                    documentIdentifier: fileValues.documentIdentifier.flatMap {
                        $0 >= 0 ? UInt64($0) : nil
                    },
                    byteCount: UInt64(max(0, fileValues.fileSize ?? 0)),
                    modificationTimeNanoseconds: Self.nanoseconds(
                        fileValues.contentModificationDate
                    ),
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

    func scanSharedOriginals(
        at sharedDirectory: URL,
        isNote: Bool = false
    ) throws -> CourseFileScanSnapshot {
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
                    isNote: isNote
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

    private func copyVisibleCourseTree(
        from sourceDirectory: URL,
        sourceRoot: URL,
        sourceRootIdentity: ImportedFileIdentity,
        stagingDescriptor: Int32,
        sharedByCoursePath: [String: CoursePortableExportSharedMaterial],
        materializedSharedPaths: inout Set<String>,
        sourceEntries: inout [String: PortableExportSourceEntry]
    ) throws {
        guard Self.identity(at: sourceRoot) == sourceRootIdentity,
              let sourceDirectoryIdentity = Self.identity(at: sourceDirectory),
              !Self.isSymbolicLink(at: sourceDirectory) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let entries = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ],
            options: []
        ).sorted {
            $0.lastPathComponent.localizedStandardCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }
        for sourceURL in entries {
            let name = sourceURL.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            guard let relativePath = strictPortableExportRelativePath(
                of: sourceURL,
                inside: sourceRoot
            ) else {
                throw CourseProjectFileWorkerError.unsafePath
            }
            let values = try sourceURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            if let shared = sharedByCoursePath[relativePath] {
                let observedLinkIdentity = Self.identity(at: sourceURL)
                let isLink = Self.isSymbolicLink(at: sourceURL)
                let pointsToSharedSource = Self.symbolicLink(
                    at: sourceURL,
                    pointsTo: shared.sourceURL
                )
                guard isLink,
                      observedLinkIdentity == shared.linkIdentity,
                      pointsToSharedSource,
                      sourceEntries[relativePath] == nil,
                      !materializedSharedPaths.contains(relativePath) else {
                    throw CoursePortableExportError.invalidSourceEntry(
                        path: relativePath,
                        reason: "共享链接身份或目标不一致"
                    )
                }
                sourceEntries[relativePath] = PortableExportSourceEntry(
                    identity: shared.linkIdentity,
                    kind: .materializedSharedLink,
                    snapshot: shared.sourceSnapshot
                )
                materializedSharedPaths.insert(relativePath)
                do {
                    try copyPortableExportRegularFile(
                        from: shared.sourceURL,
                        expectedIdentity: shared.sourceIdentity,
                        expectedSnapshot: shared.sourceSnapshot,
                        relativePath: relativePath,
                        stagingDescriptor: stagingDescriptor
                    )
                } catch {
                    throw CoursePortableExportError.invalidSourceEntry(
                        path: relativePath,
                        reason: error.localizedDescription
                    )
                }
                continue
            }
            guard values.isSymbolicLink != true,
                  values.isAliasFile != true,
                  !Self.isSymbolicLink(at: sourceURL),
                  CourseProjectPathPolicy.isSame(
                    sourceURL,
                    sourceURL.resolvingSymlinksInPath()
                  ) else {
                throw CourseProjectFileWorkerError.unsafePath
            }
            if values.isDirectory == true {
                guard let sourceIdentity = Self.identity(at: sourceURL),
                      sourceEntries.updateValue(
                          PortableExportSourceEntry(
                              identity: sourceIdentity,
                              kind: .directory,
                              snapshot: nil
                          ),
                          forKey: relativePath
                      ) == nil else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
                try Self.createDirectory(
                    atRelativePath: relativePath,
                    rootDescriptor: stagingDescriptor
                )
                do {
                    try copyVisibleCourseTree(
                        from: sourceURL,
                        sourceRoot: sourceRoot,
                        sourceRootIdentity: sourceRootIdentity,
                        stagingDescriptor: stagingDescriptor,
                        sharedByCoursePath: sharedByCoursePath,
                        materializedSharedPaths: &materializedSharedPaths,
                        sourceEntries: &sourceEntries
                    )
                } catch {
                    throw CoursePortableExportError.invalidSourceEntry(
                        path: relativePath,
                        reason: error.localizedDescription
                    )
                }
            } else if values.isRegularFile == true {
                guard let sourceIdentity = Self.identity(at: sourceURL) else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
                let sourceSnapshot = try Self.snapshotFile(at: sourceURL)
                guard sourceEntries.updateValue(
                    PortableExportSourceEntry(
                        identity: sourceIdentity,
                        kind: .regularFile,
                        snapshot: sourceSnapshot
                    ),
                    forKey: relativePath
                ) == nil else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
                do {
                    try copyPortableExportRegularFile(
                        from: sourceURL,
                        expectedIdentity: sourceIdentity,
                        expectedSnapshot: sourceSnapshot,
                        relativePath: relativePath,
                        stagingDescriptor: stagingDescriptor
                    )
                } catch {
                    throw CoursePortableExportError.invalidSourceEntry(
                        path: relativePath,
                        reason: error.localizedDescription
                    )
                }
            } else {
                throw CourseProjectFileWorkerError.unsupportedFile
            }
        }
        guard Self.identity(at: sourceDirectory) == sourceDirectoryIdentity,
              Self.identity(at: sourceRoot) == sourceRootIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    private func copyPortableExportRegularFile(
        from sourceURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot,
        relativePath: String,
        stagingDescriptor: Int32
    ) throws {
        let sourceInfo = try validatedRegularSource(sourceURL)
        guard sourceInfo.identity == expectedIdentity,
              try stableSnapshot(
                at: sourceInfo.url,
                expectedIdentity: expectedIdentity,
                expectedSnapshot: expectedSnapshot
              ) == expectedSnapshot else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let copiedSnapshot = try Self.copyRegularFile(
            from: sourceInfo.url,
            expectedIdentity: expectedIdentity,
            toRelativePath: relativePath,
            rootDescriptor: stagingDescriptor
        )
        guard copiedSnapshot == expectedSnapshot else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        guard try stableSnapshot(
            at: sourceInfo.url,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        ) == expectedSnapshot else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    private func portableExportSourceEntries(
        at sourceRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        sharedByCoursePath: [String: CoursePortableExportSharedMaterial]
    ) throws -> [String: PortableExportSourceEntry] {
        var result: [String: PortableExportSourceEntry] = [:]
        var foundSharedPaths = Set<String>()
        try appendPortableExportSourceEntries(
            in: sourceRoot,
            sourceRoot: sourceRoot,
            expectedRootIdentity: expectedRootIdentity,
            sharedByCoursePath: sharedByCoursePath,
            foundSharedPaths: &foundSharedPaths,
            result: &result
        )
        guard foundSharedPaths == Set(sharedByCoursePath.keys) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return result
    }

    private func appendPortableExportSourceEntries(
        in sourceDirectory: URL,
        sourceRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        sharedByCoursePath: [String: CoursePortableExportSharedMaterial],
        foundSharedPaths: inout Set<String>,
        result: inout [String: PortableExportSourceEntry]
    ) throws {
        guard Self.identity(at: sourceRoot) == expectedRootIdentity,
              let directoryIdentity = Self.identity(at: sourceDirectory),
              !Self.isSymbolicLink(at: sourceDirectory) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let entries = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ],
            options: []
        ).sorted {
            $0.lastPathComponent.localizedStandardCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }
        for sourceURL in entries {
            guard !sourceURL.lastPathComponent.hasPrefix("."),
                  let relativePath = strictPortableExportRelativePath(
                      of: sourceURL,
                      inside: sourceRoot
                  ) else {
                continue
            }
            let values = try sourceURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            if let shared = sharedByCoursePath[relativePath] {
                guard Self.isSymbolicLink(at: sourceURL),
                      Self.identity(at: sourceURL) == shared.linkIdentity,
                      Self.symbolicLink(
                          at: sourceURL,
                          pointsTo: shared.sourceURL
                      ),
                      try stableSnapshot(
                          at: shared.sourceURL,
                          expectedIdentity: shared.sourceIdentity,
                          expectedSnapshot: shared.sourceSnapshot
                      ) == shared.sourceSnapshot,
                      foundSharedPaths.insert(relativePath).inserted,
                      result.updateValue(
                          PortableExportSourceEntry(
                              identity: shared.linkIdentity,
                              kind: .materializedSharedLink,
                              snapshot: shared.sourceSnapshot
                          ),
                          forKey: relativePath
                      ) == nil else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
                continue
            }
            guard values.isSymbolicLink != true,
                  values.isAliasFile != true,
                  !Self.isSymbolicLink(at: sourceURL),
                  CourseProjectPathPolicy.isSame(
                      sourceURL,
                      sourceURL.resolvingSymlinksInPath()
                  ),
                  let identity = Self.identity(at: sourceURL) else {
                throw CourseProjectFileWorkerError.unsafePath
            }
            if values.isDirectory == true {
                guard result.updateValue(
                    PortableExportSourceEntry(
                        identity: identity,
                        kind: .directory,
                        snapshot: nil
                    ),
                    forKey: relativePath
                ) == nil else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
                try appendPortableExportSourceEntries(
                    in: sourceURL,
                    sourceRoot: sourceRoot,
                    expectedRootIdentity: expectedRootIdentity,
                    sharedByCoursePath: sharedByCoursePath,
                    foundSharedPaths: &foundSharedPaths,
                    result: &result
                )
            } else if values.isRegularFile == true {
                let snapshot = try stableSnapshot(
                    at: sourceURL,
                    expectedIdentity: identity
                )
                guard result.updateValue(
                    PortableExportSourceEntry(
                        identity: identity,
                        kind: .regularFile,
                        snapshot: snapshot
                    ),
                    forKey: relativePath
                ) == nil else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
            } else {
                throw CourseProjectFileWorkerError.unsupportedFile
            }
        }
        guard Self.identity(at: sourceDirectory) == directoryIdentity,
              Self.identity(at: sourceRoot) == expectedRootIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    private func strictPortableExportRelativePath(
        of child: URL,
        inside root: URL
    ) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              Array(childComponents.prefix(rootComponents.count))
                == rootComponents else {
            return nil
        }
        let components = childComponents.dropFirst(rootComponents.count)
        guard components.allSatisfy({
            !$0.isEmpty
                && $0 != "."
                && $0 != ".."
                && !$0.hasPrefix(".")
        }) else {
            return nil
        }
        return components.joined(separator: "/")
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
                == expectedDestinationDirectoryIdentity,
              identity(
                named: sourceName,
                relativeTo: sourceDescriptor
              ) == expectedSourceIdentity,
              identity(
                named: destinationName,
                relativeTo: destinationDescriptor
              ) == nil else {
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

    nonisolated private static func openDirectory(
        named name: String,
        relativeTo directoryDescriptor: Int32
    ) throws -> Int32 {
        guard isSafeEntryName(name) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let descriptor = name.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var fileStat = Darwin.stat()
        guard Darwin.fstat(descriptor, &fileStat) == 0,
              (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            Darwin.close(descriptor)
            throw CourseProjectFileWorkerError.unsafePath
        }
        return descriptor
    }

    nonisolated private static func openDirectory(
        atRelativePath relativePath: String,
        rootDescriptor: Int32
    ) throws -> Int32 {
        let components = try safeRelativePathComponents(
            relativePath,
            allowEmpty: true
        )
        let duplicated = Darwin.dup(rootDescriptor)
        guard duplicated >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var current = duplicated
        do {
            for component in components {
                let next = try openDirectory(
                    named: component,
                    relativeTo: current
                )
                Darwin.close(current)
                current = next
            }
            return current
        } catch {
            Darwin.close(current)
            throw error
        }
    }

    nonisolated private static func createDirectory(
        named name: String,
        relativeTo directoryDescriptor: Int32
    ) throws {
        guard isSafeEntryName(name) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let result = name.withCString {
            Darwin.mkdirat(
                directoryDescriptor,
                $0,
                S_IRWXU
            )
        }
        guard result == 0 else {
            if errno == EEXIST {
                throw CourseProjectFileWorkerError.targetExists
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard let fileStat = entryStat(
            named: name,
            relativeTo: directoryDescriptor
        ),
        (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    nonisolated private static func createDirectory(
        atRelativePath relativePath: String,
        rootDescriptor: Int32
    ) throws {
        let components = try safeRelativePathComponents(relativePath)
        guard let name = components.last else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let parentPath = components.dropLast().joined(separator: "/")
        let parentDescriptor = try openDirectory(
            atRelativePath: parentPath,
            rootDescriptor: rootDescriptor
        )
        defer { Darwin.close(parentDescriptor) }
        try createDirectory(
            named: name,
            relativeTo: parentDescriptor
        )
    }

    nonisolated private static func markPortableExportAbandoned(
        relativeTo metadataDescriptor: Int32,
        rootDescriptor: Int32
    ) throws {
        let name = CourseProjectManifest
            .portableExportAbandonedFileName
        if entryStat(
            named: name,
            relativeTo: metadataDescriptor
        ) == nil {
            try writeExclusiveData(
                Data(#"{"schemaVersion":1}"#.utf8),
                named: name,
                relativeTo: metadataDescriptor
            )
        }
        guard Darwin.fsync(metadataDescriptor) == 0,
              Darwin.fsync(rootDescriptor) == 0 else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
    }

    nonisolated private static func safeRelativePathComponents(
        _ relativePath: String,
        allowEmpty: Bool = false
    ) throws -> [String] {
        if allowEmpty, relativePath.isEmpty {
            return []
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(isSafeEntryName) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        return components
    }

    nonisolated private static func isSafeEntryName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
    }

    nonisolated private static func identity(
        ofOpenDescriptor descriptor: Int32
    ) -> ImportedFileIdentity? {
        var fileStat = Darwin.stat()
        guard Darwin.fstat(descriptor, &fileStat) == 0 else {
            return nil
        }
        return identity(from: fileStat)
    }

    nonisolated private static func snapshot(
        of data: Data
    ) -> CourseFileSnapshot {
        CourseFileSnapshot(
            byteCount: UInt64(data.count),
            sha256: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    nonisolated private static func copyRegularFile(
        from sourceURL: URL,
        expectedIdentity: ImportedFileIdentity,
        toRelativePath relativePath: String,
        rootDescriptor: Int32
    ) throws -> CourseFileSnapshot {
        let components = try safeRelativePathComponents(relativePath)
        guard let name = components.last else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let parentDescriptor = try openDirectory(
            atRelativePath: components.dropLast().joined(separator: "/"),
            rootDescriptor: rootDescriptor
        )
        defer { Darwin.close(parentDescriptor) }
        let sourceDescriptor = sourceURL.withUnsafeFileSystemRepresentation {
            guard let path = $0 else { return Int32(-1) }
            return Darwin.open(
                path,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard sourceDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(sourceDescriptor) }
        var sourceStat = Darwin.stat()
        guard Darwin.fstat(sourceDescriptor, &sourceStat) == 0,
              (sourceStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              identity(from: sourceStat) == expectedIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let destinationDescriptor = name.withCString {
            Darwin.openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR
            )
        }
        guard destinationDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            Darwin.close(destinationDescriptor)
        }
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(
                    sourceDescriptor,
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
            try buffer.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                var offset = 0
                while offset < count {
                    let written = Darwin.write(
                        destinationDescriptor,
                        baseAddress.advanced(by: offset),
                        count - offset
                    )
                    guard written > 0 else {
                        throw POSIXError(
                            POSIXErrorCode(rawValue: errno) ?? .EIO
                        )
                    }
                    offset += written
                }
            }
            hasher.update(data: Data(buffer.prefix(count)))
            byteCount += UInt64(count)
        }
        var finalSourceStat = Darwin.stat()
        var destinationStat = Darwin.stat()
        guard Darwin.fsync(destinationDescriptor) == 0,
              Darwin.fstat(sourceDescriptor, &finalSourceStat) == 0,
              identity(from: finalSourceStat) == expectedIdentity,
              sourceStat.st_size == finalSourceStat.st_size,
              Darwin.fstat(destinationDescriptor, &destinationStat) == 0,
              (destinationStat.st_mode & mode_t(S_IFMT))
                == mode_t(S_IFREG),
              destinationStat.st_size == Int64(byteCount) else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        return CourseFileSnapshot(
            byteCount: byteCount,
            sha256: hasher.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    nonisolated private static func regularFileSnapshot(
        atRelativePath relativePath: String,
        rootDescriptor: Int32
    ) throws -> CourseFileSnapshot? {
        let components = try safeRelativePathComponents(relativePath)
        guard let name = components.last else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let parentDescriptor = try openDirectory(
            atRelativePath: components.dropLast().joined(separator: "/"),
            rootDescriptor: rootDescriptor
        )
        defer { Darwin.close(parentDescriptor) }
        return try regularFileSnapshot(
            named: name,
            relativeTo: parentDescriptor
        )
    }

    nonisolated private static func regularFileSnapshot(
        named name: String,
        relativeTo directoryDescriptor: Int32
    ) throws -> CourseFileSnapshot? {
        guard isSafeEntryName(name) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
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
        var initialStat = Darwin.stat()
        guard Darwin.fstat(descriptor, &initialStat) == 0,
              (initialStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw CourseProjectFileWorkerError.unsafePath
        }
        let initialIdentity = identity(from: initialStat)
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
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
            hasher.update(data: Data(buffer.prefix(count)))
            byteCount += UInt64(count)
        }
        var finalStat = Darwin.stat()
        guard Darwin.fstat(descriptor, &finalStat) == 0,
              identity(from: finalStat) == initialIdentity,
              initialStat.st_size == finalStat.st_size,
              finalStat.st_size == Int64(byteCount) else {
            throw CourseProjectFileWorkerError.contentConflict
        }
        return CourseFileSnapshot(
            byteCount: byteCount,
            sha256: hasher.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    nonisolated private static func directoryEntryNames(
        relativeTo directoryDescriptor: Int32
    ) throws -> [String] {
        let scanDescriptor = Darwin.openat(
            directoryDescriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard scanDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard let directory = Darwin.fdopendir(scanDescriptor) else {
            Darwin.close(scanDescriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(MAXNAMLEN) + 1
                ) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != "..", isSafeEntryName(name) else {
                continue
            }
            names.append(name)
        }
        guard errno == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return names.sorted()
    }

    nonisolated private static func treeSnapshot(
        relativeTo rootDescriptor: Int32,
        includeHidden: Bool
    ) throws -> PortableExportTreeSnapshot {
        var entries: [String: PortableExportTreeEntry] = [:]
        try appendTreeEntries(
            relativeTo: rootDescriptor,
            parentRelativePath: "",
            includeHidden: includeHidden,
            entries: &entries
        )
        let digestEntries = entries.keys.sorted().compactMap {
            path -> PortableExportDigestEntry? in
            guard path.split(separator: "/").allSatisfy({
                !$0.hasPrefix(".")
            }),
            let entry = entries[path] else {
                return nil
            }
            return PortableExportDigestEntry(
                path: path,
                kind: entry.kind,
                byteCount: entry.snapshot?.byteCount,
                sha256: entry.snapshot?.sha256
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digestData = try encoder.encode(digestEntries)
        return PortableExportTreeSnapshot(
            entries: entries,
            visibleTreeSHA256: snapshot(of: digestData).sha256
        )
    }

    nonisolated private static func appendTreeEntries(
        relativeTo directoryDescriptor: Int32,
        parentRelativePath: String,
        includeHidden: Bool,
        entries: inout [String: PortableExportTreeEntry]
    ) throws {
        for name in try directoryEntryNames(
            relativeTo: directoryDescriptor
        ) {
            if !includeHidden, name.hasPrefix(".") {
                continue
            }
            guard let fileStat = entryStat(
                named: name,
                relativeTo: directoryDescriptor
            ) else {
                throw CourseProjectFileWorkerError.contentConflict
            }
            let relativePath = parentRelativePath.isEmpty
                ? name
                : "\(parentRelativePath)/\(name)"
            let mode = fileStat.st_mode & mode_t(S_IFMT)
            if mode == mode_t(S_IFDIR) {
                let childDescriptor = try openDirectory(
                    named: name,
                    relativeTo: directoryDescriptor
                )
                guard identity(
                    ofOpenDescriptor: childDescriptor
                ) == identity(from: fileStat) else {
                    Darwin.close(childDescriptor)
                    throw CourseProjectFileWorkerError.contentConflict
                }
                let entry = PortableExportTreeEntry(
                    identity: identity(from: fileStat),
                    kind: .directory,
                    snapshot: nil
                )
                guard entries.updateValue(
                    entry,
                    forKey: relativePath
                ) == nil else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
                do {
                    try appendTreeEntries(
                        relativeTo: childDescriptor,
                        parentRelativePath: relativePath,
                        includeHidden: includeHidden,
                        entries: &entries
                    )
                    Darwin.close(childDescriptor)
                } catch {
                    Darwin.close(childDescriptor)
                    throw error
                }
                guard let currentStat = entryStat(
                    named: name,
                    relativeTo: directoryDescriptor
                ),
                identity(from: currentStat) == identity(from: fileStat) else {
                    throw CourseProjectFileWorkerError.contentConflict
                }
            } else if mode == mode_t(S_IFREG) {
                guard let snapshot = try regularFileSnapshot(
                    named: name,
                    relativeTo: directoryDescriptor
                ),
                let currentStat = entryStat(
                    named: name,
                    relativeTo: directoryDescriptor
                ),
                identity(from: currentStat) == identity(from: fileStat) else {
                    throw CourseProjectFileWorkerError.contentConflict
                }
                let entry = PortableExportTreeEntry(
                    identity: identity(from: fileStat),
                    kind: .regularFile,
                    snapshot: snapshot
                )
                guard entries.updateValue(
                    entry,
                    forKey: relativePath
                ) == nil else {
                    throw CourseProjectFileWorkerError.verificationFailed
                }
            } else {
                throw CourseProjectFileWorkerError.unsafePath
            }
        }
    }

    nonisolated static func portableAdoptionSnapshot(
        at rootURL: URL,
        expectedRootIdentity: ImportedFileIdentity
    ) throws -> CoursePortableAdoptionSnapshot {
        let rootDescriptor = try openDirectory(
            rootURL,
            expectedIdentity: expectedRootIdentity
        )
        defer { Darwin.close(rootDescriptor) }
        return try validatedPortableAdoptionSnapshot(
            rootDescriptor: rootDescriptor,
            expectedRootIdentity: expectedRootIdentity
        )
    }

    nonisolated static func replaceCourseManifest(
        with data: Data,
        at url: URL,
        expectedDirectoryIdentity: ImportedFileIdentity,
        expectedPreviousData: Data,
        afterSwapBeforeCommitValidation: () throws -> Void = {},
        afterCommitBeforeCleanup: () -> Void = {}
    ) throws {
        guard url.lastPathComponent == "course.json",
              data.count <= 1_048_576 else {
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
            named: "course.json",
            relativeTo: directoryDescriptor,
            maximumByteCount: 1_048_576,
            temporaryBaseName: "course-manifest",
            beforeCommit: {
                guard identity(at: directory)
                        == expectedDirectoryIdentity else {
                    throw CourseProjectFileWorkerError
                        .verificationFailed
                }
            },
            afterSwapBeforeCommitValidation: {
                try afterSwapBeforeCommitValidation()
                guard identity(at: directory)
                        == expectedDirectoryIdentity else {
                    throw CourseProjectFileWorkerError
                        .verificationFailed
                }
            },
            afterCommitBeforeCleanup:
                afterCommitBeforeCleanup
        )
    }

    nonisolated private static func validatedPortableAdoptionSnapshot(
        rootDescriptor: Int32,
        expectedRootIdentity: ImportedFileIdentity
    ) throws -> CoursePortableAdoptionSnapshot {
        guard identity(ofOpenDescriptor: rootDescriptor)
                == expectedRootIdentity else {
            throw CourseProjectFileWorkerError.verificationFailed
        }
        let metadataDescriptor = try openDirectory(
            named: ".weibei",
            relativeTo: rootDescriptor
        )
        defer { Darwin.close(metadataDescriptor) }
        guard entryStat(
            named: CourseProjectManifest
                .portableExportAbandonedFileName,
            relativeTo: metadataDescriptor
        ) == nil else {
            throw CourseProjectRootError.manifestMismatch
        }
        guard let metadataIdentity = identity(
            ofOpenDescriptor: metadataDescriptor
        ),
        let manifestData = try readRegularFile(
            named: "course.json",
            relativeTo: metadataDescriptor,
            maximumByteCount: 1_048_576
        ) else {
            throw CourseProjectRootError.manifestMismatch
        }
        let manifest = try JSONDecoder().decode(
            CourseProjectManifest.self,
            from: manifestData
        )
        guard manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion else {
            throw CourseProjectRootError.manifestMismatch
        }
        let portableStateData = try readRegularFile(
            named: "course-state.json",
            relativeTo: metadataDescriptor,
            maximumByteCount: portableStateMaximumByteCount
        )
        var completionData: Data?
        if let portableExport = manifest.portableExport {
            guard let portableStateData,
                  let sealedCompletionData = try readRegularFile(
                      named:
                        CourseProjectManifest
                            .portableExportCompletionFileName,
                      relativeTo: metadataDescriptor,
                      maximumByteCount: 1_048_576
                  ) else {
                throw CourseProjectRootError.manifestMismatch
            }
            completionData = sealedCompletionData
            let visibleTreeSHA256 = try treeSnapshot(
                relativeTo: rootDescriptor,
                includeHidden: false
            ).visibleTreeSHA256
            try CourseProjectManifest.validatePortableExport(
                portableExport,
                manifest: manifest,
                manifestData: manifestData,
                stateData: portableStateData,
                completionData: sealedCompletionData,
                visibleTreeSHA256: visibleTreeSHA256
            )
        }
        guard identity(ofOpenDescriptor: rootDescriptor)
                == expectedRootIdentity,
              identity(ofOpenDescriptor: metadataDescriptor)
                == metadataIdentity else {
            throw CourseProjectFileWorkerError.contentConflict
        }
        return CoursePortableAdoptionSnapshot(
            metadataIdentity: metadataIdentity,
            manifest: manifest,
            manifestData: manifestData,
            portableStateData: portableStateData,
            completionData: completionData
        )
    }

    nonisolated private static func compareAndSwapPortableStateData(
        _ data: Data,
        expectedPreviousData: Data?,
        named name: String,
        relativeTo directoryDescriptor: Int32,
        maximumByteCount: Int = portableStateMaximumByteCount,
        temporaryBaseName: String = "course-state",
        beforeCommit: () throws -> Void,
        afterSwapBeforeCommitValidation: () throws -> Void = {},
        afterCommitBeforeCleanup: () -> Void = {}
    ) throws {
        guard data.count <= maximumByteCount,
              isSafeEntryName(temporaryBaseName) else {
            throw CourseProjectFileWorkerError.fileTooLarge
        }
        let operationID = UUID().uuidString.lowercased()
        let temporaryName = ".\(temporaryBaseName)-\(operationID).tmp"
        let candidateBackupName =
            ".\(temporaryBaseName)-candidate-\(operationID).tmp"
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
                "\(temporaryBaseName)-conflict-"
                + "\(UUID().uuidString.lowercased()).json"
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
                maximumByteCount: maximumByteCount
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
                    maximumByteCount: maximumByteCount
                )
            } catch {
                try rollBackSwapAndPreserveCandidate()
                throw CourseProjectFileWorkerError.contentConflict
            }
            guard displacedData == expectedPreviousData else {
                try rollBackSwapAndPreserveCandidate()
                throw CourseProjectFileWorkerError.contentConflict
            }
            let committedData: Data?
            do {
                committedData = try readRegularFile(
                    named: name,
                    relativeTo: directoryDescriptor,
                    maximumByteCount: maximumByteCount
                )
            } catch {
                try rollBackSwapAndPreserveCandidate()
                throw CourseProjectFileWorkerError.contentConflict
            }
            guard committedData == data else {
                try rollBackSwapAndPreserveCandidate()
                throw CourseProjectFileWorkerError.contentConflict
            }
            do {
                try afterSwapBeforeCommitValidation()
            } catch {
                let validationError = error
                try rollBackSwapAndPreserveCandidate()
                guard Darwin.fsync(directoryDescriptor) == 0 else {
                    throw CourseProjectFileWorkerError
                        .verificationFailed
                }
                throw validationError
            }
            guard Darwin.fsync(directoryDescriptor) == 0 else {
                try rollBackSwapAndPreserveCandidate()
                throw CourseProjectFileWorkerError.verificationFailed
            }
            shouldRemoveTemporary = false
            shouldRemoveCandidateBackup = false
            afterCommitBeforeCleanup()
            temporaryName.withCString {
                _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
            }
            candidateBackupName.withCString {
                _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
            }
            return
        }
        let finalData: Data?
        do {
            finalData = try readRegularFile(
                named: name,
                relativeTo: directoryDescriptor,
                maximumByteCount: maximumByteCount
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
        defer {
            Darwin.close(descriptor)
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
        let initialIdentity = identity(from: fileStat)
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
        var finalStat = Darwin.stat()
        guard Darwin.fstat(descriptor, &finalStat) == 0,
              identity(from: finalStat) == initialIdentity,
              finalStat.st_size == fileStat.st_size,
              finalStat.st_size == Int64(data.count) else {
            throw CourseProjectFileWorkerError.contentConflict
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

extension CourseProjectFileWorker {
    private struct CourseTrashReceipt: Codable {
        var courseID: UUID
        var rootIdentity: ImportedFileIdentity
        var transactionDirectoryIdentity: ImportedFileIdentity
    }

    nonisolated static func writeCourseTrashReceipt(
        for isolation: CourseRootTrashIsolation,
        courseID: UUID
    ) throws -> CourseTrashReceiptCleanup {
        let receiptURL = isolation.transactionDirectory.appendingPathComponent(
            "trash-receipt.json",
            isDirectory: false
        )
        let receipt = CourseTrashReceipt(
            courseID: courseID,
            rootIdentity: isolation.identity,
            transactionDirectoryIdentity: isolation.transactionDirectoryIdentity
        )
        try JSONEncoder().encode(receipt).write(to: receiptURL, options: [.atomic])
        return CourseTrashReceiptCleanup(
            courseID: courseID,
            receiptURL: receiptURL,
            transactionDirectory: isolation.transactionDirectory,
            transactionDirectoryIdentity: isolation.transactionDirectoryIdentity
        )
    }

    @discardableResult
    nonisolated static func cleanupCourseTrashReceipt(
        _ cleanup: CourseTrashReceiptCleanup,
        identityResolver: (URL) -> ImportedFileIdentity?
    ) -> Bool {
        guard identityResolver(cleanup.transactionDirectory)?
            .matchesAcrossVolumeDrift(cleanup.transactionDirectoryIdentity) == true else {
            return false
        }
        try? FileManager.default.removeItem(at: cleanup.receiptURL)
        guard entryPresence(at: cleanup.receiptURL) == .absent else {
            return false
        }
        _ = cleanup.transactionDirectory.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.rmdir(path)
        }
        return true
    }

    nonisolated static func recoverCourseTrashReceipt(
        for course: Course,
        resolvedRootURL: URL?,
        courseLibraryRootURL: URL?,
        identityResolver: (URL) -> ImportedFileIdentity?
    ) -> CourseTrashReceiptCleanup? {
        guard let expectedIdentity = course.sourceRootIdentity else { return nil }
        let originalCandidates: [URL] = [
            resolvedRootURL,
            course.sourceRootRelativePath.flatMap { relativePath in
                courseLibraryRootURL.flatMap { libraryRoot in
                    CourseProjectPathPolicy.resolvedRelativePath(
                        relativePath,
                        inside: libraryRoot
                    )
                }
            },
            course.sourceRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            },
        ].compactMap { $0 }
        let parentPaths = Set(originalCandidates.map {
            $0.deletingLastPathComponent().standardizedFileURL.path
        })
        let fileManager = FileManager.default
        var recoveredReceipt: CourseTrashReceiptCleanup?
        for parentPath in parentPaths {
            let parent = URL(fileURLWithPath: parentPath, isDirectory: true)
            guard let siblings = try? fileManager.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }
            for sibling in siblings where sibling.lastPathComponent
                .hasPrefix(".weibei-course-removal-") {
                let receiptURL = sibling.appendingPathComponent(
                    "trash-receipt.json",
                    isDirectory: false
                )
                let siblingIdentity = identityResolver(sibling)
                let receipt = try? JSONDecoder().decode(
                    CourseTrashReceipt.self,
                    from: readBoundedRegularFile(
                        at: receiptURL,
                        maximumByteCount: 65_536
                    )
                )
                let hasVerifiedReceipt: Bool
                if let receipt, let siblingIdentity {
                    hasVerifiedReceipt = receipt.courseID == course.id
                        && receipt.rootIdentity == expectedIdentity
                        && siblingIdentity.matchesAcrossVolumeDrift(
                            receipt.transactionDirectoryIdentity
                        )
                } else {
                    hasVerifiedReceipt = false
                }
                guard let children = try? fileManager.contentsOfDirectory(
                    at: sibling,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                ) else { continue }
                for child in children where identityResolver(child)?
                    .matchesAcrossVolumeDrift(expectedIdentity) == true {
                    if let restoreTarget = originalCandidates.first(where: {
                        !fileManager.fileExists(atPath: $0.path)
                    }) {
                        _ = renameWithoutReplacement(from: child, to: restoreTarget)
                    } else if originalCandidates.contains(where: {
                        identityResolver($0)?
                            .matchesAcrossVolumeDrift(expectedIdentity) == true
                    }) {
                        try? fileManager.removeItem(at: child)
                    }
                }
                let originalRootsAreDefinitelyAbsent = !originalCandidates.isEmpty
                    && originalCandidates.allSatisfy {
                        entryPresence(at: $0) == .absent
                    }
                if hasVerifiedReceipt,
                   originalRootsAreDefinitelyAbsent,
                   recoveredReceipt == nil,
                   let siblingIdentity,
                   let remaining = try? fileManager.contentsOfDirectory(
                    at: sibling,
                    includingPropertiesForKeys: nil
                   ),
                   remaining.map(\.lastPathComponent) == [receiptURL.lastPathComponent] {
                    recoveredReceipt = CourseTrashReceiptCleanup(
                        courseID: course.id,
                        receiptURL: receiptURL,
                        transactionDirectory: sibling,
                        transactionDirectoryIdentity: siblingIdentity
                    )
                } else if hasVerifiedReceipt,
                          let siblingIdentity,
                          originalCandidates.contains(where: {
                              identityResolver($0)?
                                  .matchesAcrossVolumeDrift(expectedIdentity) == true
                          }) {
                    cleanupCourseTrashReceipt(
                        CourseTrashReceiptCleanup(
                            courseID: course.id,
                            receiptURL: receiptURL,
                            transactionDirectory: sibling,
                            transactionDirectoryIdentity: siblingIdentity
                        ),
                        identityResolver: identityResolver
                    )
                } else if let remaining = try? fileManager.contentsOfDirectory(
                    at: sibling,
                    includingPropertiesForKeys: nil
                ), remaining.isEmpty {
                    try? fileManager.removeItem(at: sibling)
                }
            }
        }
        return recoveredReceipt
    }
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
    case afterAdoptionWorkspaceSaveBeforeManifestNormalization
    case beforeCourseRootTrashMove
    case beforeCourseRootTrashIsolation
    case afterCourseRootTrashIsolationBeforeJournal
    case afterCourseRootTrashMoveBeforeJournal
    case afterCourseRootTrashJournalBeforeWorkspaceSave
}

struct CourseProjectSimulatedCrash: Error {}

struct CourseProjectSharedMaterialProvenance: Codable, Equatable, Sendable {
    var itemID: String
    var courseRelativePath: String
    var sharedRelativePath: String
    var sourceIdentity: ImportedFileIdentity
    var sourceContentDigest: String
}

struct CourseProjectPortableExportMetadata: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var portableStateSHA256: String
    var visibleTreeSHA256: String
    var materializedSharedItems: [CourseProjectSharedMaterialProvenance]

    init(
        schemaVersion: Int = currentSchemaVersion,
        portableStateSHA256: String,
        visibleTreeSHA256: String,
        materializedSharedItems: [CourseProjectSharedMaterialProvenance]
    ) {
        self.schemaVersion = schemaVersion
        self.portableStateSHA256 = portableStateSHA256
        self.visibleTreeSHA256 = visibleTreeSHA256
        self.materializedSharedItems = materializedSharedItems
    }
}

struct CourseProjectPortableExportCompletion: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var courseID: UUID
    var manifestSHA256: String
    var portableStateSHA256: String
    var visibleTreeSHA256: String

    init(
        schemaVersion: Int = currentSchemaVersion,
        courseID: UUID,
        manifestSHA256: String,
        portableStateSHA256: String,
        visibleTreeSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.courseID = courseID
        self.manifestSHA256 = manifestSHA256
        self.portableStateSHA256 = portableStateSHA256
        self.visibleTreeSHA256 = visibleTreeSHA256
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

struct CourseProjectManifest: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let portableExportCompletionFileName = "export-complete.json"
    static let portableExportAbandonedFileName = "export-abandoned.json"

    var courseID: UUID
    var schemaVersion: Int
    var portableExport: CourseProjectPortableExportMetadata?

    init(
        courseID: UUID,
        schemaVersion: Int = currentSchemaVersion,
        portableExport: CourseProjectPortableExportMetadata? = nil
    ) {
        self.courseID = courseID
        self.schemaVersion = schemaVersion
        self.portableExport = portableExport
    }

    static func read(from url: URL) throws -> CourseProjectManifest {
        guard url.lastPathComponent == "course.json" else {
            throw CourseProjectRootError.manifestMismatch
        }
        let manifestData = try CourseProjectFileWorker
            .readBoundedRegularFile(
                at: url,
                maximumByteCount: 1_048_576
            )
        let manifest = try JSONDecoder().decode(
            CourseProjectManifest.self,
            from: manifestData
        )
        guard manifest.schemaVersion == currentSchemaVersion else {
            throw CourseProjectRootError.manifestMismatch
        }
        if manifest.portableExport != nil {
            let metadataDirectory = url.deletingLastPathComponent()
            let root = metadataDirectory.deletingLastPathComponent()
            guard metadataDirectory.lastPathComponent == ".weibei",
                  let rootIdentity =
                    CourseProjectFileWorker.identity(at: root) else {
                throw CourseProjectRootError.manifestMismatch
            }
            let snapshot = try CourseProjectFileWorker
                .portableAdoptionSnapshot(
                    at: root,
                    expectedRootIdentity: rootIdentity
                )
            guard snapshot.manifestData == manifestData else {
                throw CourseProjectRootError.manifestMismatch
            }
            return snapshot.manifest
        }
        return manifest
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func validatePortableExport(
        _ portableExport: CourseProjectPortableExportMetadata,
        manifest: CourseProjectManifest,
        manifestData: Data,
        stateData: Data,
        completionData: Data,
        visibleTreeSHA256: String
    ) throws {
        guard portableExport.schemaVersion
                == CourseProjectPortableExportMetadata.currentSchemaVersion,
              isSHA256(portableExport.portableStateSHA256),
              isSHA256(portableExport.visibleTreeSHA256),
              Set(portableExport.materializedSharedItems.map(\.itemID)).count
                == portableExport.materializedSharedItems.count,
              Set(
                  portableExport.materializedSharedItems.map(
                      \.courseRelativePath
                  )
              ).count == portableExport.materializedSharedItems.count,
              portableExport.materializedSharedItems.allSatisfy({
                  !$0.itemID.isEmpty
                      && isSafeRelativePath($0.courseRelativePath)
                      && isStrictCommonContentPath($0.sharedRelativePath)
                      && isSHA256($0.sourceContentDigest)
              }) else {
            throw CourseProjectRootError.manifestMismatch
        }
        let completion = try JSONDecoder().decode(
            CourseProjectPortableExportCompletion.self,
            from: completionData
        )
        guard completion.schemaVersion
                == CourseProjectPortableExportCompletion.currentSchemaVersion,
              completion.courseID == manifest.courseID,
              completion.manifestSHA256 == sha256(manifestData),
              completion.portableStateSHA256 == sha256(stateData),
              completion.portableStateSHA256
                == portableExport.portableStateSHA256,
              completion.visibleTreeSHA256 == visibleTreeSHA256,
              completion.visibleTreeSHA256
                == portableExport.visibleTreeSHA256 else {
            throw CourseProjectRootError.manifestMismatch
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                (48...57).contains($0.value)
                    || (97...102).contains($0.value)
            }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !components.isEmpty
            && components.allSatisfy {
                !$0.isEmpty
                    && $0 != "."
                    && $0 != ".."
                    && !$0.hasPrefix(".")
            }
    }

    private static func isStrictCommonContentPath(_ path: String) -> Bool {
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return isSafeRelativePath(path)
            && components.count == 2
            && ["通用资料", "通用笔记", "共享文稿"]
                .contains(components[0])
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
