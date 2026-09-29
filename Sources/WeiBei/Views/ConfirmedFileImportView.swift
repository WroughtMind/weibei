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
    var failures: [ConfirmedFileImportFailure] = []
    var previousSkippedCount = 0
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
        previousSkippedCount
            + unsupportedNames.count
            + candidates.filter { $0.disposition == .duplicate }.count
    }
}

extension WorkspaceStore {
    func prepareConfirmedFileImport(
        _ urls: [URL],
        courseID: UUID? = nil,
        asNotes: Bool = false,
        securityScopedURLs: [URL] = []
    ) {
        guard !urls.isEmpty else { return }
        guard confirmedFileImport?.stage != .importing else { return }
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
        if var batch = confirmedFileImport, batch.stage == .importing {
            let knownURLs = batch.sourceURLs + batch.pendingSourceURLs
            if !knownURLs.contains(where: {
                $0.standardizedFileURL == url.standardizedFileURL
            }) {
                batch.pendingSourceURLs.append(url)
                confirmedFileImport = batch
            }
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
        confirmedFileImportSecurityScopes.forEach { $0.stopAccessingSecurityScopedResource() }
        confirmedFileImportSecurityScopes = []
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
              !batch.pendingSourceURLs.isEmpty,
              batch.failures.isEmpty || abandoningFailures else { return }
        prepareConfirmedFileImport(batch.pendingSourceURLs)
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
            previousSkippedCount: batch.skippedCount,
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
            var failures: [ConfirmedFileImportFailure] = []
            var completed = batch.unsupportedNames.count
            for candidate in batch.candidates {
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
                if candidate.disposition == .duplicate { continue }
                do {
                    let item = try await importConfirmedFile(candidate, batch: batch)
                    if !imported.contains(where: { $0.id == item.id }) {
                        imported.append(item)
                    }
                } catch {
                    if let recovered = await recoverConfirmedCourseImport(
                        candidate,
                        batch: batch
                    ) {
                        if !imported.contains(where: { $0.id == recovered.id }) {
                            imported.append(recovered)
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
            publishConfirmedFileImportProgress(batch)
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
        recentlyImportedItemIDs = Set(batch.importedItems.map(\.id))
        recentlyImportedClearTask?.cancel()
        recentlyImportedClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.recentlyImportedItemIDs = []
        }
        if let courseID = batch.courseID {
            presentCourseWorkspace(batch.importsMarkdownAsNotes ? .notes : .materials, courseID: courseID)
        } else {
            if courseWorkspacePresented { dismissCourseWorkspace() }
            showLibrary = true
        }
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
                    markdownOnly: asNotes
                )
            }.value
            guard let self, !Task.isCancelled,
                  var current = confirmedFileImport,
                  current.id == batchID else { return }
            current.stage = .reviewing
            current.candidates = plan.candidates
            current.unsupportedNames = plan.unsupportedNames
            confirmedFileImportTask = nil
            confirmedFileImport = current
        }
    }

    nonisolated static func makeConfirmedFileImportPlan(
        urls: [URL], destination: URL, markdownOnly: Bool
    ) -> (candidates: [ConfirmedFileImportCandidate], unsupportedNames: [String]) {
        let expansion = CourseProjectFileWorker.expandedImportSelection(
            from: urls,
            markdownOnly: markdownOnly
        )
        let expanded = expansion.supported
        var unsupported = expansion.unsupportedNames
        unsupported.append(contentsOf: urls.compactMap { url -> String? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let nested = CourseProjectFileWorker.expandedImportSelection(
                    from: [url],
                    markdownOnly: markdownOnly
            )
            return nested.supported.isEmpty && nested.unsupportedNames.isEmpty
                ? url.lastPathComponent
                : nil
        })
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
            let duplicatesReservedSource = reservedSourcesByOriginalName[originalName, default: []]
                .contains { reservedSource in
                    (try? ImportFileCopy.sourcesHaveIdenticalImportedContents(
                        reservedSource,
                        url
                    )) == true
                }
            if duplicatesReservedSource {
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
        return (candidates, unsupported.sorted())
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
        let copiedURL = try await Task.detached(priority: .userInitiated) {
            try Self.copyExternalFileIntoLibrary(
                root: root,
                sourceURL: candidate.sourceURL,
                isNote: batch.importsMarkdownAsNotes
            )
        }.value
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
    @State private var courseSearch = ""
    @State private var creatingCourse = false

    private static let bodyWidth: CGFloat = 456
    private static let maximumBodyHeight: CGFloat = 350

    private var batch: ConfirmedFileImportBatch? { store.confirmedFileImport }
    private var matchingCourses: [Course] {
        let query = courseSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? store.courses : store.courses.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let batch {
                heading(batch)
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 15)
                Divider().overlay(WeiBeiTheme.hairline.opacity(0.45))
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
                .padding(.vertical, 16)
                Divider().overlay(WeiBeiTheme.hairline.opacity(0.45))
                footer(batch)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
            }
        }
        .frame(width: 500, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
#if targetEnvironment(macCatalyst)
        .background(CatalystSheetBackground(color: WeiBeiNativePalette.paper()))
#endif
        .background(WeiBeiGlassForegroundSheet(mode: store.appearanceMode))
        .background(WeiBeiThemeBackdrop(mode: store.appearanceMode))
        .foregroundStyle(WeiBeiTheme.ink)
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .modifier(ConfirmedImportFittedPresentation())
        .interactiveDismissDisabled(batch?.stage == .importing)
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

    private func heading(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(headingTitle(batch))
                .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
            Text(headingDetail(batch))
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }

    private func headingTitle(_ batch: ConfirmedFileImportBatch) -> String {
        switch batch.stage {
        case .preparing, .reviewing: store.ui("确认导入", "Confirm Import")
        case .importing: store.ui("正在导入", "Importing")
        case .finished: store.ui("导入结果", "Import Results")
        }
    }

    private func headingDetail(_ batch: ConfirmedFileImportBatch) -> String {
        switch batch.stage {
        case .preparing, .reviewing:
            store.ui("导入副本，保留原文件。", "Import a copy and keep the original.")
        case .importing:
            destinationDescription(batch)
        case .finished:
            store.ui("已完成的导入已经保留。", "Completed imports have been kept.")
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
        VStack(alignment: .leading, spacing: 8) {
            Text(store.ui(
                "本批内容 · \(batch.candidates.count + batch.unsupportedNames.count) 个",
                "This batch · \(batch.candidates.count + batch.unsupportedNames.count) items"
            ))
                .weiBeiText(12, weight: .semibold)
            if !batch.sourceFolderNames.isEmpty {
                Text(store.ui(
                    "来源文件夹：\(batch.sourceFolderNames.joined(separator: "、"))",
                    "Source folders: \(batch.sourceFolderNames.joined(separator: ", "))"
                ))
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .lineLimit(2)
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
            }
            if !batch.sourceFolderNames.isEmpty {
                Text(store.ui(
                    "文件夹内仅导入 PDF、Word、PPT、HTML、文本和 Markdown；隐藏文件与应用包会跳过。",
                    "Folders include PDF, Word, PPT, HTML, text, and Markdown only; hidden files and app bundles are skipped."
                ))
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
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
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(candidate.sourceURL.lastPathComponent)
                        .weiBeiText(12)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(kind.label(language: store.interfaceLanguage))
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .fixedSize()
                }
                if candidate.disposition != .ready {
                    Text(candidateLabel(candidate))
                        .weiBeiText(10.5, weight: .medium)
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
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(
                    asNotes
                        ? store.ui("仅支持 Markdown，已跳过", "Markdown only; skipped")
                        : store.ui("不支持，已跳过", "Unsupported; skipped")
                )
                .weiBeiText(10.5, weight: .medium)
            }
        }
        .weiBeiText(11)
        .foregroundStyle(WeiBeiTheme.cinnabar)
        .padding(.vertical, 6)
        .help(name)
    }

    private func destinationPicker(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.ui("导入到", "Import to"))
                .weiBeiText(12, weight: .semibold)
            if !store.courses.isEmpty {
                WeiBeiSearchField(
                    text: $courseSearch,
                    prompt: store.ui("搜索课程", "Search courses"),
                    isFocused: .constant(false),
                    fontSize: 12,
                    focusesOnAppear: false,
                    chromeHeight: 30
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                destinationButton(
                    title: batch.importsMarkdownAsNotes
                        ? store.ui("通用笔记", "Common Notes")
                        : store.ui("通用资料", "Common Materials"),
                    courseID: nil,
                    selected: batch.courseID == nil
                )
                ForEach(matchingCourses) { course in
                    destinationButton(
                        title: course.title,
                        courseID: course.id,
                        selected: batch.courseID == course.id
                    )
                }
                if !courseSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   matchingCourses.isEmpty {
                    Text(store.ui("没有匹配的课程", "No matching courses"))
                        .weiBeiText(11)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                }
            }
            Button(store.ui("新建课程…", "Create Course…")) { creatingCourse = true }
                .buttonStyle(WeiBeiTextActionButtonStyle())
        }
    }

    private func destinationButton(title: String, courseID: UUID?, selected: Bool) -> some View {
        Button { store.setConfirmedFileImportDestination(courseID: courseID) } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: courseID == nil ? "tray" : "folder")
                    .frame(width: 15)
                    .padding(.top, 2)
                Text(title)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark") }
            }
            .weiBeiText(12, weight: selected ? .semibold : .regular)
            .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? WeiBeiTheme.cinnabarSoft : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func progress(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = batch.currentFileName {
                Text(current).weiBeiText(12).lineLimit(2)
            }
            ProgressView(value: Double(batch.completed), total: Double(max(1, batch.total)))
                .tint(WeiBeiTheme.cinnabar)
            Text("\(batch.completed) / \(batch.total)")
                .weiBeiText(11, design: .monospaced)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            if !batch.pendingSourceURLs.isEmpty {
                Text(store.ui(
                    "另有 \(batch.pendingSourceURLs.count) 个从 Dock 打开的文件等待本批完成。",
                    "\(batch.pendingSourceURLs.count) file(s) opened from the Dock are waiting for this batch."
                ))
                .weiBeiText(11)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func result(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.ui(
                "成功 \(batch.importedItems.count) 个 · 跳过 \(batch.skippedCount) 个 · 失败 \(batch.failures.count) 个",
                "\(batch.importedItems.count) succeeded · \(batch.skippedCount) skipped · \(batch.failures.count) failed"
            ))
            .weiBeiText(15, weight: .semibold)
            if batch.stopped {
                Text(store.ui("已停止剩余任务；已完成的导入仍然保留。", "Remaining work stopped; completed imports were kept."))
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !batch.pendingSourceURLs.isEmpty {
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
                    Text(store.ui("未导入", "Not imported"))
                        .weiBeiText(12, weight: .semibold)
                    ForEach(batch.failures) { failure in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(failure.sourceURL.lastPathComponent)
                                .weiBeiText(12, weight: .semibold)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Text(failure.message)
                                .weiBeiText(11)
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultButtons(_ batch: ConfirmedFileImportBatch) -> some View {
        if !batch.pendingSourceURLs.isEmpty {
            Button(store.ui("结束本次导入", "End This Import")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            if batch.failures.isEmpty {
                Button(store.ui(
                    "处理待导入文件（\(batch.pendingSourceURLs.count)）",
                    "Review Waiting Files (\(batch.pendingSourceURLs.count))"
                )) {
                    store.continuePendingConfirmedFileImport()
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .keyboardShortcut(.defaultAction)
            } else {
                Button(store.ui(
                    "放弃失败项并继续（\(batch.pendingSourceURLs.count)）",
                    "Leave Failures and Continue (\(batch.pendingSourceURLs.count))"
                )) {
                    store.continuePendingConfirmedFileImport(abandoningFailures: true)
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
                Button(store.ui("只重试失败项", "Retry Failed Only")) {
                    store.retryFailedConfirmedFileImport()
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .keyboardShortcut(.defaultAction)
            }
        } else if !batch.failures.isEmpty {
            Button(store.ui("完成", "Done")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            Button(store.ui("只重试失败项", "Retry Failed Only")) {
                store.retryFailedConfirmedFileImport()
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
            .keyboardShortcut(.defaultAction)
        } else if batch.importedItems.count == 1 {
            Button(store.ui("完成", "Done")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            Button(store.ui("打开文稿", "Open Document")) {
                store.openSingleConfirmedImport()
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
            .keyboardShortcut(.defaultAction)
        } else if batch.importedItems.count > 1 {
            Button(store.ui("完成", "Done")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            Button(store.ui("查看已导入资料", "View Imported Items")) {
                store.showConfirmedImportBatch()
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
            .keyboardShortcut(.defaultAction)
        } else {
            Button(store.ui("完成", "Done")) { store.dismissConfirmedFileImport() }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private func confirmTitle(_ batch: ConfirmedFileImportBatch) -> String {
        if let courseID = batch.courseID,
           let course = store.courses.first(where: { $0.id == courseID }) {
            return store.ui("加入《\(course.title)》", "Add to \(course.title)")
        }
        return batch.importsMarkdownAsNotes
            ? store.ui("加入通用笔记", "Add to Common Notes")
            : store.ui("加入通用资料", "Add to Common Materials")
    }

    private func destinationDescription(_ batch: ConfirmedFileImportBatch) -> String {
        store.ui("正在\(confirmTitle(batch))", confirmTitle(batch))
    }

    private func candidateLabel(_ candidate: ConfirmedFileImportCandidate) -> String {
        switch candidate.disposition {
        case .ready: return store.ui("可导入", "Ready")
        case .duplicate: return store.ui("重复，跳过", "Duplicate, skip")
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

private struct ConfirmedImportFittedPresentation: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
    }
}
