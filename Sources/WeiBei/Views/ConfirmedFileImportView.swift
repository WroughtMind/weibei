import Foundation
import SwiftUI
import WeiBeiCore

enum ConfirmedFileImportStage: Equatable, Sendable {
    case preparing
    case reviewing
    case importing
    case finished
}

enum ConfirmedFileImportDisposition: Equatable, Sendable {
    case ready
    case duplicate
    case conflict(suggestedFileName: String)
}

struct ConfirmedFileImportCandidate: Identifiable, Equatable, Sendable {
    let sourceURL: URL
    var disposition: ConfirmedFileImportDisposition
    var id: String { sourceURL.path }
}

struct ConfirmedFileImportFailure: Identifiable, Equatable, Sendable {
    let sourceURL: URL
    let message: String
    var id: String { sourceURL.path }
}

struct PendingConfirmedFileImport: Sendable {
    var sourceURLs: [URL]
    var courseID: UUID?
    var importsMarkdownAsNotes: Bool
    var securityScopedURLs: [URL]
}

struct ConfirmedFileImportBatch: Identifiable, Equatable, Sendable {
    let id: UUID
    var sourceURLs: [URL]
    var sourceFolderNames: [String]
    var courseID: UUID?
    var importsMarkdownAsNotes: Bool
    var stage: ConfirmedFileImportStage = .preparing
    var candidates: [ConfirmedFileImportCandidate] = []
    var unsupportedNames: [String] = []
    var importedItems: [StudyItem] = []
    var successfulCopiesByOriginalName: [String: [URL]] = [:]
    var failures: [ConfirmedFileImportFailure] = []
    var previousDuplicateCount = 0
    var previousUnsupportedCount = 0
    var completed = 0
    var total = 0
    var currentFileName: String?
    var stopped = false
    var destinationError: String?
    var pendingSourceURLs: [URL] = []

    var confirmableCount: Int {
        candidates.count
    }

    var skippedCount: Int {
        duplicateCount + unsupportedCount
    }

    var duplicateCount: Int {
        previousDuplicateCount
            + candidates.filter { $0.disposition == .duplicate }.count
    }

    var unsupportedCount: Int {
        previousUnsupportedCount + unsupportedNames.count
    }
}

extension WorkspaceStore {
    @discardableResult
    func receiveDroppedFiles(_ providers: [NSItemProvider], courseID: UUID? = nil, asNotes: Bool = false) -> Bool {
        WeiBeiDroppedFileURLs.load(providers) { [weak self] result in
            guard let self else {
                WeiBeiLog.workspace.notice("[DEBUG-wb-drop] store_released")
                result.securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                return
            }
            if !result.urls.isEmpty {
                self.prepareConfirmedFileImport(result.urls, courseID: courseID, asNotes: asNotes,
                    securityScopedURLs: result.securityScopedURLs)
            }
            if !result.failures.isEmpty {
                self.importantOperationError = self.ui(
                    "未能接收 \(result.failures.count) 个拖入文件，请重试。",
                    "Could not receive \(result.failures.count) dropped file(s). Please try again."
                )
            }
            let stage = self.confirmedFileImport.map { String(describing: $0.stage) } ?? "nil"
            WeiBeiLog.workspace.notice("[DEBUG-wb-drop] store_received stage=\(stage, privacy: .public) error_present=\(self.importantOperationError != nil, privacy: .public)")
        }
    }

    func prepareConfirmedFileImport(
        _ urls: [URL],
        courseID: UUID? = nil,
        asNotes: Bool = false,
        securityScopedURLs: [URL] = []
    ) {
        guard !urls.isEmpty else {
            releaseConfirmedFileImportSecurityScopes(securityScopedURLs)
            return
        }
        if confirmedFileImport?.stage == .importing {
            enqueuePendingConfirmedFileImport(
                urls,
                courseID: courseID,
                asNotes: asNotes,
                securityScopedURLs: securityScopedURLs
            )
            return
        }
        dismissConfirmedFileImport()
        confirmedFileImportSecurityScopes = securityScopedURLs
        let folders = urls.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map(\.lastPathComponent)
        confirmedFileImport = ConfirmedFileImportBatch(
            id: UUID(),
            sourceURLs: urls,
            sourceFolderNames: folders,
            courseID: courseID,
            importsMarkdownAsNotes: asNotes
        )
        refreshConfirmedFileImportPlan()
    }

    func receiveExternalFileForConfirmedImport(_ url: URL) {
        if confirmedFileImport?.stage == .importing {
            enqueuePendingConfirmedFileImport([url])
            return
        }
        if var batch = confirmedFileImport,
           batch.courseID == nil,
           !batch.importsMarkdownAsNotes,
           (batch.stage == .preparing || batch.stage == .reviewing) {
            if !batch.sourceURLs.contains(where: {
                $0.standardizedFileURL == url.standardizedFileURL
            }) {
                batch.sourceURLs.append(url)
                confirmedFileImport = batch
                refreshConfirmedFileImportPlan()
            }
            return
        }
        prepareConfirmedFileImport([url])
    }

    func setConfirmedFileImportDestination(courseID: UUID?) {
        guard var batch = confirmedFileImport,
              batch.stage == .reviewing || batch.stage == .preparing else { return }
        batch.courseID = courseID
        confirmedFileImport = batch
        refreshConfirmedFileImportPlan()
    }

    func selectNewCourseForConfirmedFileImport(_ courseID: UUID) {
        setConfirmedFileImportDestination(courseID: courseID)
    }

    func dismissConfirmedFileImport() {
        confirmedFileImportTask?.cancel()
        confirmedFileImportTask = nil
        releaseConfirmedFileImportSecurityScopes(confirmedFileImportSecurityScopes)
        for request in pendingConfirmedFileImports {
            releaseConfirmedFileImportSecurityScopes(request.securityScopedURLs)
        }
        confirmedFileImportSecurityScopes = []
        pendingConfirmedFileImports = []
        confirmedFileImportStopRequested = false
        confirmedFileImport = nil
    }

    func stopConfirmedFileImport() {
        guard confirmedFileImport?.stage == .importing else { return }
        confirmedFileImportStopRequested = true
    }

    func continuePendingConfirmedFileImport(abandoningFailures: Bool = false) {
        guard let batch = confirmedFileImport,
              batch.stage == .finished,
              !pendingConfirmedFileImports.isEmpty,
              batch.failures.isEmpty || abandoningFailures else { return }
        let request = pendingConfirmedFileImports.removeFirst()
        releaseConfirmedFileImportSecurityScopes(confirmedFileImportSecurityScopes)
        confirmedFileImportSecurityScopes = request.securityScopedURLs
        let remainingURLs = pendingConfirmedFileImports.flatMap(\.sourceURLs)
        let folders = request.sourceURLs.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map(\.lastPathComponent)
        confirmedFileImport = ConfirmedFileImportBatch(
            id: UUID(),
            sourceURLs: request.sourceURLs,
            sourceFolderNames: folders,
            courseID: request.courseID,
            importsMarkdownAsNotes: request.importsMarkdownAsNotes,
            pendingSourceURLs: remainingURLs
        )
        refreshConfirmedFileImportPlan()
    }

    private func enqueuePendingConfirmedFileImport(
        _ urls: [URL],
        courseID: UUID? = nil,
        asNotes: Bool = false,
        securityScopedURLs: [URL] = []
    ) {
        guard var batch = confirmedFileImport, batch.stage == .importing else {
            releaseConfirmedFileImportSecurityScopes(securityScopedURLs)
            return
        }
        var knownPaths = Set<String>()
        if batch.courseID == courseID, batch.importsMarkdownAsNotes == asNotes {
            knownPaths.formUnion(batch.sourceURLs.map { $0.standardizedFileURL.path })
        }
        for request in pendingConfirmedFileImports
        where request.courseID == courseID
            && request.importsMarkdownAsNotes == asNotes {
            knownPaths.formUnion(request.sourceURLs.map { $0.standardizedFileURL.path })
        }
        let acceptedURLs = urls.filter {
            knownPaths.insert($0.standardizedFileURL.path).inserted
        }
        let acceptedPaths = Set(acceptedURLs.map { $0.standardizedFileURL.path })
        let acceptedScopes = securityScopedURLs.filter {
            acceptedPaths.contains($0.standardizedFileURL.path)
        }
        releaseConfirmedFileImportSecurityScopes(
            securityScopedURLs.filter {
                !acceptedPaths.contains($0.standardizedFileURL.path)
            }
        )
        guard !acceptedURLs.isEmpty else { return }
        pendingConfirmedFileImports.append(PendingConfirmedFileImport(
            sourceURLs: acceptedURLs,
            courseID: courseID,
            importsMarkdownAsNotes: asNotes,
            securityScopedURLs: acceptedScopes
        ))
        batch.pendingSourceURLs = pendingConfirmedFileImports.flatMap(\.sourceURLs)
        confirmedFileImport = batch
    }

    private func releaseConfirmedFileImportSecurityScopes(_ urls: [URL]) {
        urls.forEach(courseSecurityScopeStopper)
    }

    func prepareInitialCourseImportAfterEntryDismissal(
        _ urls: [URL],
        courseID: UUID
    ) {
        guard !urls.isEmpty else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.prepareConfirmedFileImport(urls, courseID: courseID)
        }
    }

    func retryFailedConfirmedFileImport() {
        guard let batch = confirmedFileImport,
              batch.stage == .finished,
              !batch.failures.isEmpty else { return }
        let failedURLs = batch.failures.map(\.sourceURL)
        confirmedFileImport = ConfirmedFileImportBatch(
            id: batch.id,
            sourceURLs: failedURLs,
            sourceFolderNames: batch.sourceFolderNames,
            courseID: batch.courseID,
            importsMarkdownAsNotes: batch.importsMarkdownAsNotes,
            importedItems: batch.importedItems,
            successfulCopiesByOriginalName: batch.successfulCopiesByOriginalName,
            previousDuplicateCount: batch.duplicateCount,
            previousUnsupportedCount: batch.unsupportedCount,
            pendingSourceURLs: batch.pendingSourceURLs
        )
        refreshConfirmedFileImportPlan()
    }

    func confirmFileImport() {
        guard var batch = confirmedFileImport,
              batch.stage == .reviewing,
              batch.confirmableCount > 0,
              batch.destinationError == nil else { return }
        batch.stage = .importing
        let preflightFailures = batch.failures
        batch.failures = []
        batch.completed = 0
        batch.total = batch.candidates.count + batch.unsupportedNames.count
        batch.currentFileName = nil
        batch.stopped = false
        confirmedFileImportStopRequested = false
        confirmedFileImport = batch

        let initialBatch = batch
        confirmedFileImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var batch = initialBatch
            var imported = batch.importedItems
            var failures = preflightFailures
            var completed = batch.unsupportedNames.count
            for (candidateIndex, plannedCandidate) in batch.candidates.enumerated() {
                var candidate = plannedCandidate
                if confirmedFileImportStopRequested {
                    batch.stopped = true
                    break
                }
                batch.currentFileName = candidate.sourceURL.lastPathComponent
                batch.completed = completed
                publishConfirmedFileImportProgress(batch)
                defer {
                    completed += 1
                    batch.completed = completed
                    publishConfirmedFileImportProgress(batch)
                }
                do {
                    let successfulCopies = batch.successfulCopiesByOriginalName[
                        candidate.sourceURL.lastPathComponent,
                        default: []
                    ]
                    if candidate.disposition == .duplicate || !successfulCopies.isEmpty {
                        // A preview may refer to an earlier source whose copy failed,
                        // or to destination content that changed before confirmation.
                        candidate.disposition = .ready
                        batch.candidates[candidateIndex] = candidate
                        candidate.disposition = try await revalidatedDuplicateDisposition(
                            candidate.sourceURL,
                            batch: batch,
                            successfulCopies: successfulCopies
                        )
                        batch.candidates[candidateIndex] = candidate
                        if candidate.disposition == .duplicate { continue }
                    }
                    let item = try await importConfirmedFile(candidate, batch: batch)
                    if !imported.contains(where: { $0.id == item.id }) {
                        imported.append(item)
                    }
                    if let copiedURL = resolvedLibraryURL(for: item) {
                        batch.successfulCopiesByOriginalName[
                            candidate.sourceURL.lastPathComponent,
                            default: []
                        ].append(copiedURL)
                    }
                } catch {
                    if let recovered = await recoverConfirmedCourseImport(
                        candidate,
                        batch: batch
                    ) {
                        if !imported.contains(where: { $0.id == recovered.id }) {
                            imported.append(recovered)
                        }
                        if let copiedURL = resolvedLibraryURL(for: recovered) {
                            batch.successfulCopiesByOriginalName[
                                candidate.sourceURL.lastPathComponent,
                                default: []
                            ].append(copiedURL)
                        }
                        continue
                    }
                    WeiBeiLog.workspace.error(
                        "code=confirmed_import_failed underlying=\(WeiBeiLog.code(error), privacy: .public) path=\(candidate.sourceURL.path, privacy: .private) detail=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
                    )
                    failures.append(ConfirmedFileImportFailure(
                        sourceURL: candidate.sourceURL,
                        message: confirmedImportFailureMessage(error)
                    ))
                }
            }
            batch.stage = .finished
            batch.currentFileName = nil
            batch.importedItems = imported
            batch.failures = failures
            batch.completed = completed
            batch.stopped = batch.stopped || confirmedFileImportStopRequested
            confirmedFileImportStopRequested = false
            confirmedFileImportTask = nil
            settleConfirmedFileImport(batch)
        }
    }

    private func publishConfirmedFileImportProgress(_ batch: ConfirmedFileImportBatch) {
        var next = batch
        if let current = confirmedFileImport, current.id == batch.id {
            for url in current.pendingSourceURLs where !next.pendingSourceURLs.contains(where: {
                $0.standardizedFileURL == url.standardizedFileURL
            }) {
                next.pendingSourceURLs.append(url)
            }
        }
        confirmedFileImport = next
    }

    private func settleConfirmedFileImport(_ batch: ConfirmedFileImportBatch) {
        guard confirmedFileImport?.id == batch.id else { return }
        publishConfirmedFileImportProgress(batch)
        guard let settled = confirmedFileImport, settled.id == batch.id else { return }
        if settled.stopped,
           settled.failures.isEmpty,
           settled.pendingSourceURLs.isEmpty {
            let remaining = max(0, settled.total - settled.completed)
            dismissConfirmedFileImport()
            showTransientNoteStatus(
                remaining > 0
                    ? ui(
                        "导入已停止；\(remaining) 份未导入。",
                        "Import stopped; \(remaining) item(s) were not imported."
                    )
                    : ui(
                        "导入已停止；已完成的导入仍然保留。",
                        "Import stopped. Completed imports were kept."
                    )
            )
            return
        }
        guard settled.failures.isEmpty,
              !settled.stopped,
              settled.pendingSourceURLs.isEmpty else { return }

        let feedback = confirmedImportCompletionFeedback(settled)
        if settled.importedItems.count == 1 {
            openSingleConfirmedImport()
        } else if !settled.importedItems.isEmpty {
            showConfirmedImportBatch()
        } else {
            dismissConfirmedFileImport()
        }
        if let feedback {
            showTransientNoteStatus(feedback)
        }
    }

    private func confirmedImportCompletionFeedback(_ batch: ConfirmedFileImportBatch) -> String? {
        let imported = batch.importedItems.count
        let duplicates = batch.duplicateCount
        let unsupported = batch.unsupportedCount
        let chineseRole = batch.importsMarkdownAsNotes ? "笔记" : "资料"
        let englishRole = batch.importsMarkdownAsNotes ? "notes" : "materials"
        if imported == 0 {
            if duplicates > 0, unsupported > 0 {
                return ui(
                    "没有新增内容；\(duplicates) 个已存在，\(unsupported) 个格式不支持。",
                    "Nothing new was imported. \(duplicates) already existed and \(unsupported) had unsupported formats."
                )
            }
            if duplicates > 0 {
                return ui(
                    "这 \(duplicates) 份\(chineseRole)已存在，未重复导入。",
                    "These \(duplicates) \(englishRole) already exist and were not imported again."
                )
            }
            if unsupported > 0 {
                return ui(
                    "没有可导入的文件；\(unsupported) 个格式不支持。",
                    "No files could be imported; \(unsupported) had unsupported formats."
                )
            }
            return ui(
                "所选内容没有可导入的文件。",
                "The selected content has no importable files."
            )
        }
        if duplicates > 0, unsupported > 0 {
            return ui(
                "\(duplicates) 个已存在未重复导入，\(unsupported) 个格式不支持。",
                "\(duplicates) already existed and were not imported again; \(unsupported) had unsupported formats."
            )
        }
        if duplicates > 0 {
            return ui(
                "\(duplicates) 个已存在，未重复导入。",
                "\(duplicates) already existed and were not imported again."
            )
        }
        if unsupported > 0 {
            return ui(
                "\(unsupported) 个格式不支持，未导入。",
                "\(unsupported) had unsupported formats and were not imported."
            )
        }
        return nil
    }

    func openSingleConfirmedImport() {
        guard let batch = confirmedFileImport, batch.importedItems.count == 1,
              let item = batch.importedItems.first else { return }
        if let courseID = batch.courseID {
            if batch.importsMarkdownAsNotes {
                _ = openCourseNote(item.id, in: courseID)
            } else {
                _ = openCourseMaterial(item.id, in: courseID)
            }
        } else {
            if courseWorkspacePresented { dismissCourseWorkspace() }
            selectMeasured(itemID: item.id, opensNotebook: batch.importsMarkdownAsNotes)
        }
        dismissConfirmedFileImport()
    }

    func showConfirmedImportBatch() {
        guard let batch = confirmedFileImport, !batch.importedItems.isEmpty else { return }
        librarySearch = ""
        if let courseID = batch.courseID {
            activateCourse(courseID)
        }
        recentlyImportedItemIDs = Set(batch.importedItems.map(\.id))
        recentlyImportedClearTask?.cancel()
        recentlyImportedClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.recentlyImportedItemIDs = []
        }
        if courseWorkspacePresented { dismissCourseWorkspace(restoringFocus: false) }
        revealLibrary()
        dismissConfirmedFileImport()
    }

    private func refreshConfirmedFileImportPlan() {
        guard var batch = confirmedFileImport else { return }
        confirmedFileImportTask?.cancel()
        batch.stage = .preparing
        batch.candidates = []
        batch.unsupportedNames = []
        batch.destinationError = nil
        confirmedFileImport = batch

        let batchID = batch.id
        let urls = batch.sourceURLs
        let asNotes = batch.importsMarkdownAsNotes
        let courseID = batch.courseID
        let successfulCopies = batch.successfulCopiesByOriginalName
        let destination: URL?
        if let courseID {
            destination = courseRootURL(for: courseID)?.appendingPathComponent(
                asNotes ? CourseOwnedFileRole.note.directoryName : CourseOwnedFileRole.material.directoryName,
                isDirectory: true
            )
        } else {
            destination = courseLibraryRootURL?.appendingPathComponent(
                asNotes ? CourseOwnedFileRole.note.commonDirectoryName : CourseOwnedFileRole.material.commonDirectoryName,
                isDirectory: true
            )
        }
        guard let destination else {
            batch.stage = .reviewing
            batch.destinationError = ui(
                "目标文件夹当前不可用，请先重新连接资料库或课程文件夹。",
                "The destination folder is unavailable. Reconnect the library or course folder first."
            )
            confirmedFileImport = batch
            return
        }

        confirmedFileImportTask = Task { @MainActor [weak self] in
            let plan = await Task.detached(priority: .userInitiated) {
                Self.makeConfirmedFileImportPlan(
                    urls: urls,
                    destination: destination,
                    markdownOnly: asNotes,
                    successfulCopiesByOriginalName: successfulCopies
                )
            }.value
            guard let self, !Task.isCancelled,
                  var current = confirmedFileImport,
                  current.id == batchID else { return }
            current.stage = .reviewing
            current.candidates = plan.candidates
            current.unsupportedNames = plan.unsupportedNames
            current.failures = plan.unavailableSourceURLs.map {
                ConfirmedFileImportFailure(
                    sourceURL: $0,
                    message: self.ui(
                        "文件已移动、删除或暂时无法访问。请恢复文件后重试。",
                        "The file was moved, deleted, or is temporarily unavailable. Restore it, then retry."
                    )
                )
            }
            confirmedFileImportTask = nil
            if current.candidates.isEmpty {
                confirmedFileImport = current
                if current.failures.isEmpty, current.pendingSourceURLs.isEmpty {
                    let feedback = confirmedImportCompletionFeedback(current)
                    dismissConfirmedFileImport()
                    if let feedback { showTransientNoteStatus(feedback) }
                } else {
                    current.stage = .finished
                    confirmedFileImport = current
                }
            } else {
                confirmedFileImport = current
            }
        }
    }

    nonisolated static func makeConfirmedFileImportPlan(
        urls: [URL], destination: URL, markdownOnly: Bool,
        successfulCopiesByOriginalName: [String: [URL]] = [:]
    ) -> (
        candidates: [ConfirmedFileImportCandidate],
        unsupportedNames: [String],
        unavailableSourceURLs: [URL]
    ) {
        let expansion = CourseProjectFileWorker.expandedImportSelection(
            from: urls,
            markdownOnly: markdownOnly
        )
        let expanded = expansion.supported
        let unsupported = expansion.unsupportedNames
        var candidates: [ConfirmedFileImportCandidate] = []
        var reservedTargetNames = Set<String>()
        var reservedSourcesByOriginalName: [String: [URL]] = [:]
        for url in expanded {
            do {
                switch try ImportFileCopy.collision(from: url, into: destination) {
                case .available, .conflict:
                    break
                case .duplicate:
                    candidates.append(ConfirmedFileImportCandidate(sourceURL: url, disposition: .duplicate))
                    continue
                }
            } catch {}
            let originalName = url.lastPathComponent
            let duplicatesSuccessfulCopy = successfulCopiesByOriginalName[originalName, default: []]
                .contains { copiedURL in
                    guard CourseProjectPathPolicy.isSame(
                        copiedURL.deletingLastPathComponent().resolvingSymlinksInPath(),
                        destination.resolvingSymlinksInPath()
                    ) else { return false }
                    return (try? ImportFileCopy.sourceHasIdenticalImportedContents(url, at: copiedURL)) == true
                }
            let duplicatesReservedSource = reservedSourcesByOriginalName[originalName, default: []]
                .contains { reservedSource in
                    (try? ImportFileCopy.sourcesHaveIdenticalImportedContents(
                        reservedSource,
                        url
                    )) == true
                }
            if duplicatesSuccessfulCopy || duplicatesReservedSource {
                candidates.append(ConfirmedFileImportCandidate(sourceURL: url, disposition: .duplicate))
                continue
            }
            let targetName = nextConfirmedImportTargetName(
                for: url,
                in: destination,
                reserved: reservedTargetNames
            )
            let disposition: ConfirmedFileImportDisposition = targetName == url.lastPathComponent
                ? .ready
                : .conflict(suggestedFileName: targetName)
            reservedTargetNames.insert(targetName)
            reservedSourcesByOriginalName[originalName, default: []].append(url)
            candidates.append(ConfirmedFileImportCandidate(sourceURL: url, disposition: disposition))
        }
        return (candidates, unsupported.sorted(), expansion.unavailableSourceURLs)
    }

    nonisolated private static func nextConfirmedImportTargetName(
        for sourceURL: URL,
        in directory: URL,
        reserved: Set<String>
    ) -> String {
        let preferred = sourceURL.lastPathComponent
        if !reserved.contains(preferred),
           !FileManager.default.fileExists(atPath: directory.appendingPathComponent(preferred).path) {
            return preferred
        }
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        for suffix in 2...9_999 {
            let name = pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(pathExtension)"
            if !reserved.contains(name),
               !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
                return name
            }
        }
        return pathExtension.isEmpty
            ? "\(stem) \(UUID().uuidString.lowercased())"
            : "\(stem) \(UUID().uuidString.lowercased()).\(pathExtension)"
    }

    private func revalidatedDuplicateDisposition(
        _ sourceURL: URL,
        batch: ConfirmedFileImportBatch,
        successfulCopies: [URL]
    ) async throws -> ConfirmedFileImportDisposition {
        let destination: URL
        if let courseID = batch.courseID {
            guard let root = courseRootURL(for: courseID) else {
                throw CocoaError(.fileNoSuchFile)
            }
            destination = root.appendingPathComponent(
                batch.importsMarkdownAsNotes
                    ? CourseOwnedFileRole.note.directoryName
                    : CourseOwnedFileRole.material.directoryName,
                isDirectory: true
            )
        } else {
            guard let root = courseLibraryRootURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            destination = root.appendingPathComponent(
                batch.importsMarkdownAsNotes
                    ? CourseOwnedFileRole.note.commonDirectoryName
                    : CourseOwnedFileRole.material.commonDirectoryName,
                isDirectory: true
            )
        }
        return try await Task.detached(priority: .userInitiated) {
            () throws -> ConfirmedFileImportDisposition in
            // A same-name representative may have been safely renamed by an
            // earlier conflict. Compare its actual copy, never just its source.
            for copiedURL in successfulCopies {
                guard CourseProjectPathPolicy.isSame(
                    copiedURL.deletingLastPathComponent().resolvingSymlinksInPath(),
                    destination.resolvingSymlinksInPath()
                ) else { continue }
                if (try? ImportFileCopy.sourceHasIdenticalImportedContents(
                    sourceURL,
                    at: copiedURL
                )) == true {
                    return .duplicate
                }
            }
            let collision = try ImportFileCopy.collision(from: sourceURL, into: destination)
            switch collision {
            case .available: return .ready
            case .duplicate: return .duplicate
            case .conflict(let suggested): return .conflict(suggestedFileName: suggested)
            }
        }.value
    }

    private func importConfirmedFile(
        _ candidate: ConfirmedFileImportCandidate,
        batch: ConfirmedFileImportBatch
    ) async throws -> StudyItem {
        if let courseID = batch.courseID {
            let resolution: CourseFileConflictResolution
            switch candidate.disposition {
            case .conflict(let suggested):
                resolution = .keepBoth(preferredFileName: suggested)
            case .ready, .duplicate:
                resolution = .cancel
            }
            return try await importFileIntoCourse(
                candidate.sourceURL,
                courseID: courseID,
                role: batch.importsMarkdownAsNotes ? .note : .material,
                conflictResolution: resolution
            ).item
        }

        guard let root = courseLibraryRootURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let copiedURL = try await copyExternalFileIntoLibrary(
            root: root,
            sourceURL: candidate.sourceURL,
            isNote: batch.importsMarkdownAsNotes
        )
        guard let item = applyImportedCommonFiles(
            [(copiedURL, batch.importsMarkdownAsNotes)],
            selectsFirstImportedItem: false,
            reclassifiesExistingMarkdown: false
        ).first else {
            throw CocoaError(.fileWriteUnknown)
        }
        return item
    }

    private func confirmedImportFailureMessage(_ error: Error) -> String {
        let cocoaCode = (error as? CocoaError)?.code
        if cocoaCode == .fileNoSuchFile || cocoaCode == .fileReadNoSuchFile {
            return ui(
                "文件已移动、删除或暂时无法访问。请恢复文件后重试。",
                "The file was moved, deleted, or is temporarily unavailable. Restore it, then retry."
            )
        }
        if cocoaCode == .fileReadNoPermission || cocoaCode == .fileWriteNoPermission {
            return ui(
                "没有读取来源或写入目标的权限。请重新选择可访问的文件夹后重试。",
                "WeiBei cannot read the source or write to the destination. Re-select an accessible folder, then retry."
            )
        }
        return ui(
            "复制或登记没有完成，原文件仍保留。请检查文件与目标文件夹后重试。",
            "Copying or registration did not finish. The original is still kept. Check the file and destination, then retry."
        )
    }

    private func recoverConfirmedCourseImport(
        _ candidate: ConfirmedFileImportCandidate,
        batch: ConfirmedFileImportBatch
    ) async -> StudyItem? {
        guard case .ready = candidate.disposition,
              let courseID = batch.courseID,
              let root = courseRootURL(for: courseID) else { return nil }
        let role: CourseOwnedFileRole = batch.importsMarkdownAsNotes ? .note : .material
        let directory = root.appendingPathComponent(role.directoryName, isDirectory: true)
        guard (try? ImportFileCopy.collision(
            from: candidate.sourceURL,
            into: directory
        )) == .duplicate else { return nil }
        _ = await reconcileCourseFilesNow(courseID: courseID)
        let expectedStorage = StudyItemStorage.courseOwned(
            ownerCourseID: courseID,
            relativePath: "\(role.directoryName)/\(candidate.sourceURL.lastPathComponent)"
        )
        return importedItems.first { $0.storage == expectedStorage }
    }
}

struct ConfirmedFileImportView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var creatingCourse = false

    private static let bodyWidth: CGFloat = 396
    private static let maximumBodyHeight: CGFloat = 300

    private var batch: ConfirmedFileImportBatch? { store.confirmedFileImport }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let batch {
                ConfirmedImportCappedBodyLayout(
                    width: Self.bodyWidth,
                    maximumHeight: Self.maximumBodyHeight
                ) {
                    stageContent(batch)
                        .frame(width: Self.bodyWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    ScrollView {
                        stageContent(batch)
                            .frame(width: Self.bodyWidth, alignment: .leading)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .clipped()
                .padding(.horizontal, 22)
                .padding(.top, 22)
                footer(batch)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 440, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
#if targetEnvironment(macCatalyst)
        .modifier(CatalystIndependentSheetFitting(color: WeiBeiNativePalette.paper()))
#endif
        .background(WeiBeiGlassForegroundSheet(mode: store.appearanceMode))
        .background(WeiBeiThemeBackdrop(mode: store.appearanceMode))
        .foregroundStyle(WeiBeiTheme.ink)
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .modifier(WeiBeiFittedSheetPresentation())
        .interactiveDismissDisabled(batch?.stage == .importing)
        .onAppear {
            WeiBeiLog.workspace.notice("[DEBUG-wb-drop] confirmation_appeared")
        }
        .sheet(isPresented: $creatingCourse) {
            CourseProjectEntrySheet(
                cancel: { creatingCourse = false },
                openCourse: { courseID in
                    creatingCourse = false
                    store.selectNewCourseForConfirmedFileImport(courseID)
                },
                allowsInitialImport: false
            )
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private func stageContent(_ batch: ConfirmedFileImportBatch) -> some View {
        switch batch.stage {
        case .preparing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(store.ui("正在核对文件与目标…", "Checking files and destination…"))
                    .weiBeiText(13)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .reviewing:
            review(batch)
        case .importing:
            progress(batch)
        case .finished:
            result(batch)
        }
    }

    @ViewBuilder
    private func footer(_ batch: ConfirmedFileImportBatch) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            switch batch.stage {
            case .preparing:
                Button(store.ui("取消", "Cancel")) { store.dismissConfirmedFileImport() }
                    .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
                    .keyboardShortcut(.cancelAction)
            case .reviewing:
                Button(store.ui("取消", "Cancel")) { store.dismissConfirmedFileImport() }
                    .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button(store.ui("导入", "Import")) { store.confirmFileImport() }
                    .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(batch.confirmableCount == 0 || batch.destinationError != nil)
            case .importing:
                Button(store.ui("停止剩余导入", "Stop Remaining")) {
                    store.stopConfirmedFileImport()
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            case .finished:
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { resultButtons(batch) }
                    VStack(alignment: .trailing, spacing: 8) { resultButtons(batch) }
                }
            }
        }
    }

    private func review(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            fileSummary(batch)
            destinationPicker(batch)
            if let error = batch.destinationError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fileSummary(_ batch: ConfirmedFileImportBatch) -> some View {
        let fileCount = batch.candidates.count + batch.unsupportedNames.count + batch.failures.count
        return VStack(alignment: .leading, spacing: 8) {
            if !batch.sourceFolderNames.isEmpty {
                Text(store.ui(
                    "可导入文稿 · \(batch.candidates.count)个",
                    "Importable documents · \(batch.candidates.count)"
                ))
                .weiBeiText(12, weight: .semibold)
            } else if fileCount > 1 {
                Text(store.ui("\(fileCount)个文件", "\(fileCount) files"))
                .weiBeiText(12, weight: .semibold)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(batch.candidates.enumerated()), id: \.element.id) { index, candidate in
                    if index > 0 { Divider().overlay(WeiBeiTheme.hairline.opacity(0.30)) }
                    candidateRow(candidate)
                }
                ForEach(Array(batch.unsupportedNames.enumerated()), id: \.offset) { index, name in
                    if !batch.candidates.isEmpty || index > 0 {
                        Divider().overlay(WeiBeiTheme.hairline.opacity(0.30))
                    }
                    unsupportedRow(name, asNotes: batch.importsMarkdownAsNotes)
                }
                ForEach(Array(batch.failures.enumerated()), id: \.element.id) { index, failure in
                    if !batch.candidates.isEmpty || !batch.unsupportedNames.isEmpty || index > 0 {
                        Divider().overlay(WeiBeiTheme.hairline.opacity(0.30))
                    }
                    unavailableSourceRow(failure)
                }
            }
        }
    }

    private func candidateRow(_ candidate: ConfirmedFileImportCandidate) -> some View {
        let kind = StudyItemKind.detect(from: candidate.sourceURL)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.sourceURL.lastPathComponent)
                    .weiBeiText(13)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if candidate.disposition != .ready {
                    Text(candidateLabel(candidate))
                        .weiBeiText(12, weight: .medium)
                        .foregroundStyle(candidateColor(candidate))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
        .help(candidate.sourceURL.lastPathComponent)
    }

    private func unsupportedRow(_ name: String, asNotes: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "nosign")
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .weiBeiText(13)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(
                    asNotes
                        ? store.ui("仅支持 Markdown", "Markdown only")
                        : store.ui("格式不支持", "Unsupported format")
                )
                .weiBeiText(12, weight: .medium)
            }
        }
        .foregroundStyle(WeiBeiTheme.cinnabar)
        .padding(.vertical, 6)
        .help(name)
    }

    private func unavailableSourceRow(_ failure: ConfirmedFileImportFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(failure.sourceURL.lastPathComponent)
                    .weiBeiText(13)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(failure.message)
                    .weiBeiText(12, weight: .medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(WeiBeiTheme.cinnabar)
        .padding(.vertical, 6)
        .help(failure.sourceURL.lastPathComponent)
    }

    private func destinationPicker(_ batch: ConfirmedFileImportBatch) -> some View {
        HStack(spacing: 12) {
            Text(store.ui("导入到", "Import to"))
                .weiBeiText(12, weight: .semibold)
            Spacer(minLength: 0)
            Menu {
                Button {
                    store.setConfirmedFileImportDestination(courseID: nil)
                } label: {
                    if batch.courseID == nil {
                        Label(commonDestinationTitle(batch), systemImage: "checkmark")
                    } else {
                        Text(commonDestinationTitle(batch))
                    }
                }
                ForEach(store.courses) { course in
                    Button {
                        store.setConfirmedFileImportDestination(courseID: course.id)
                    } label: {
                        if batch.courseID == course.id {
                            Label(course.title, systemImage: "checkmark")
                        } else {
                            Text(course.title)
                        }
                    }
                }
                Divider()
                Button(store.ui("新建课程…", "Create Course…")) { creatingCourse = true }
            } label: {
                HStack(spacing: 6) {
                    Text(destinationTitle(batch))
                        .weiBeiText(13)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .weiBeiText(12, weight: .semibold)
                }
                .foregroundStyle(WeiBeiTheme.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .weibeiEtchedBackground(
                    fill: WeiBeiTheme.paperRaised.opacity(0.52),
                    stroke: WeiBeiTheme.hairline.opacity(0.3),
                    cornerRadius: 8
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    private func progress(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = batch.currentFileName {
                Text(current).weiBeiText(13).lineLimit(2)
            }
            ProgressView(value: Double(batch.completed), total: Double(max(1, batch.total)))
                .tint(WeiBeiTheme.cinnabar)
            Text("\(batch.completed) / \(batch.total)")
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }

    private func result(_ batch: ConfirmedFileImportBatch) -> some View {
        let commonFailureMessage = sharedFailureMessage(batch)
        return VStack(alignment: .leading, spacing: 14) {
            Text(resultSummary(batch))
                .weiBeiText(13, weight: .semibold)
            if batch.stopped, !batch.pendingSourceURLs.isEmpty {
                Text(store.ui(
                    "已停止；\(batch.pendingSourceURLs.count) 个文件未处理。已完成的导入已保留，原文件未变。",
                    "Stopped with \(batch.pendingSourceURLs.count) file(s) unprocessed. Completed imports were kept and originals are unchanged."
                ))
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if batch.stopped {
                Text(store.ui(
                    "已停止；已完成的导入仍然保留。",
                    "Stopped. Completed imports were kept."
                ))
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            } else if !batch.pendingSourceURLs.isEmpty {
                Text(store.ui(
                    "另有 \(batch.pendingSourceURLs.count) 个文件尚未处理，原文件仍保留。",
                    "\(batch.pendingSourceURLs.count) file(s) are still waiting; their originals are unchanged."
                ))
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !batch.failures.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let message = commonFailureMessage {
                        Text(message)
                            .weiBeiText(12)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(batch.failures) { failure in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(failure.sourceURL.lastPathComponent)
                                .weiBeiText(13, weight: .semibold)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            if commonFailureMessage == nil {
                                Text(failure.message)
                                    .weiBeiText(12)
                                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultButtons(_ batch: ConfirmedFileImportBatch) -> some View {
        if !batch.pendingSourceURLs.isEmpty {
            Button(store.ui("结束", "End")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            if batch.failures.isEmpty {
                Button(store.ui(
                    "继续处理（\(batch.pendingSourceURLs.count)）",
                    "Continue (\(batch.pendingSourceURLs.count))"
                )) {
                    store.continuePendingConfirmedFileImport()
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .keyboardShortcut(.defaultAction)
            } else {
                Button(store.ui(
                    "放弃失败项，继续（\(batch.pendingSourceURLs.count)）",
                    "Leave Failures, Continue (\(batch.pendingSourceURLs.count))"
                )) {
                    store.continuePendingConfirmedFileImport(abandoningFailures: true)
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
                Button(store.ui("重试失败项", "Retry Failed")) {
                    store.retryFailedConfirmedFileImport()
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .keyboardShortcut(.defaultAction)
            }
        } else if !batch.failures.isEmpty {
            Button(store.ui("关闭", "Close")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            Button(store.ui("重试失败项", "Retry Failed")) {
                store.retryFailedConfirmedFileImport()
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
            .keyboardShortcut(.defaultAction)
        } else {
            Button(store.ui("关闭", "Close")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private func resultSummary(_ batch: ConfirmedFileImportBatch) -> String {
        var chinese: [String] = []
        var english: [String] = []
        if !batch.importedItems.isEmpty {
            chinese.append("\(batch.importedItems.count)个已导入")
            english.append("\(batch.importedItems.count) imported")
        }
        if batch.duplicateCount > 0 {
            chinese.append("\(batch.duplicateCount)个已存在")
            english.append("\(batch.duplicateCount) already existed")
        }
        if batch.unsupportedCount > 0 {
            chinese.append("\(batch.unsupportedCount)个格式不支持")
            english.append("\(batch.unsupportedCount) unsupported")
        }
        if !batch.failures.isEmpty {
            chinese.append("\(batch.failures.count)个失败")
            english.append("\(batch.failures.count) failed")
        }
        if chinese.isEmpty {
            return store.ui("没有导入文件", "No files imported")
        }
        return store.ui(chinese.joined(separator: " · "), english.joined(separator: " · "))
    }

    private func sharedFailureMessage(_ batch: ConfirmedFileImportBatch) -> String? {
        guard let message = batch.failures.first?.message,
              batch.failures.allSatisfy({ $0.message == message }) else { return nil }
        return message
    }

    private func commonDestinationTitle(_ batch: ConfirmedFileImportBatch) -> String {
        batch.importsMarkdownAsNotes
            ? store.ui("通用笔记", "Common Notes")
            : store.ui("通用资料", "Common Materials")
    }

    private func destinationTitle(_ batch: ConfirmedFileImportBatch) -> String {
        guard let courseID = batch.courseID else { return commonDestinationTitle(batch) }
        return store.courses.first(where: { $0.id == courseID })?.title
            ?? store.ui("选择课程", "Choose Course")
    }

    private func candidateLabel(_ candidate: ConfirmedFileImportCandidate) -> String {
        switch candidate.disposition {
        case .ready: return store.ui("可导入", "Ready")
        case .duplicate: return store.ui("已存在", "Already exists")
        case .conflict(let name): return store.ui("同名，另存为 \(name)", "Name conflict, save as \(name)")
        }
    }

    private func candidateColor(_ candidate: ConfirmedFileImportCandidate) -> Color {
        switch candidate.disposition {
        case .ready: WeiBeiTheme.secondaryInk
        case .duplicate: WeiBeiTheme.tertiaryInk
        case .conflict: WeiBeiTheme.cinnabar
        }
    }

}

private struct ConfirmedImportCappedBodyLayout: Layout {
    let width: CGFloat
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let measurement = subviews.first else { return .zero }
        let contentHeight = measurement.sizeThatFits(
            ProposedViewSize(width: width, height: nil)
        ).height
        return CGSize(width: width, height: min(maximumHeight, max(1, ceil(contentHeight))))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: nil)
        )
        subviews[1].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: bounds.height)
        )
    }
}
