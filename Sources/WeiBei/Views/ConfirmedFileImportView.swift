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

    func continuePendingConfirmedFileImport() {
        guard let batch = confirmedFileImport,
              batch.stage == .finished,
              !batch.pendingSourceURLs.isEmpty else { return }
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
        var reservedSourcesByTargetName: [String: URL] = [:]
        for url in expanded {
            let initialTargetName: String
            do {
                switch try ImportFileCopy.collision(from: url, into: destination) {
                case .available:
                    initialTargetName = url.lastPathComponent
                case .duplicate:
                    candidates.append(ConfirmedFileImportCandidate(sourceURL: url, disposition: .duplicate))
                    continue
                case .conflict(let suggested):
                    initialTargetName = suggested
                }
            } catch {
                initialTargetName = url.lastPathComponent
            }
            if let reservedSource = reservedSourcesByTargetName[initialTargetName],
               (try? ImportFileCopy.sourcesHaveIdenticalImportedContents(
                    reservedSource,
                    url
               )) == true {
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
            reservedSourcesByTargetName[targetName] = url
            candidates.append(ConfirmedFileImportCandidate(sourceURL: url, disposition: disposition))
        }
        if markdownOnly {
            unsupported = unsupported.map { "\($0)（仅支持 Markdown）" }
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

    private var batch: ConfirmedFileImportBatch? { store.confirmedFileImport }
    private var matchingCourses: [Course] {
        let query = courseSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? store.courses : store.courses.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let batch {
                heading(batch)
                switch batch.stage {
                case .preparing:
                    Text(store.ui("正在核对文件与目标…", "Checking files and destination…"))
                        .weiBeiText(13)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                case .reviewing:
                    review(batch)
                case .importing:
                    progress(batch)
                case .finished:
                    result(batch)
                }
            }
        }
        .padding(24)
        .frame(width: 540, height: 600, alignment: .topLeading)
#if targetEnvironment(macCatalyst)
        .background(CatalystSheetBackground(color: WeiBeiNativePalette.paper()))
#endif
        .background(WeiBeiGlassForegroundSheet(mode: store.appearanceMode))
        .background(WeiBeiThemeBackdrop(mode: store.appearanceMode))
        .foregroundStyle(WeiBeiTheme.ink)
        .preferredColorScheme(store.appearanceMode.colorScheme)
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

    private func heading(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.ui("确认导入", "Confirm Import"))
                .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
            Text(store.ui(
                "导入副本，原文件保留。确认前不会复制文件。",
                "A copy will be imported and the original kept. Nothing is copied before confirmation."
            ))
            .weiBeiText(12)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
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
            }
            Spacer(minLength: 0)
            HStack {
                Button(store.ui("取消", "Cancel")) { store.dismissConfirmedFileImport() }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmTitle(batch)) { store.confirmFileImport() }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(batch.confirmableCount == 0 || batch.destinationError != nil)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(batch.candidates) { candidate in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: StudyItemKind.detect(from: candidate.sourceURL).systemImage)
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                            Text(candidate.sourceURL.lastPathComponent)
                                .weiBeiText(12)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(StudyItemKind.detect(from: candidate.sourceURL).label(language: store.interfaceLanguage))
                                .weiBeiText(10.5)
                                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                            Text(candidateLabel(candidate))
                                .weiBeiText(10.5, weight: .medium)
                                .foregroundStyle(candidateColor(candidate))
                        }
                    }
                    ForEach(batch.unsupportedNames, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "nosign")
                            Text(name).lineLimit(1)
                            Spacer()
                            Text(store.ui("不支持", "Unsupported"))
                        }
                        .weiBeiText(11)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                    }
                }
            }
            .frame(maxHeight: 150)
            if !batch.sourceFolderNames.isEmpty {
                Text(store.ui(
                    "文件夹内仅导入 PDF、Word、PPT、HTML、文本和 Markdown；隐藏文件与应用包会跳过。",
                    "Folders include PDF, Word, PPT, HTML, text, and Markdown only; hidden files and app bundles are skipped."
                ))
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        }
        .padding(12)
        .weibeiEtchedBackground(
            fill: WeiBeiTheme.paperRaised.opacity(0.30),
            stroke: WeiBeiTheme.hairline.opacity(0.28),
            cornerRadius: 12
        )
    }

    private func destinationPicker(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.ui("归属", "Destination"))
                .weiBeiText(12, weight: .semibold)
            WeiBeiSearchField(
                text: $courseSearch,
                prompt: store.ui("搜索课程", "Search courses"),
                isFocused: .constant(false),
                fontSize: 12,
                focusesOnAppear: false,
                chromeHeight: 30
            )
            ScrollView {
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
                }
            }
            .frame(maxHeight: 120)
            Button(store.ui("新建课程…", "Create Course…")) { creatingCourse = true }
                .buttonStyle(WeiBeiTextActionButtonStyle())
        }
    }

    private func destinationButton(title: String, courseID: UUID?, selected: Bool) -> some View {
        Button { store.setConfirmedFileImportDestination(courseID: courseID) } label: {
            HStack(spacing: 8) {
                Image(systemName: courseID == nil ? "tray" : "folder")
                Text(title).lineLimit(1)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(WeiBeiTextActionButtonStyle(active: selected, fontSize: 12, height: 30))
    }

    private func progress(_ batch: ConfirmedFileImportBatch) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(destinationDescription(batch))
                .weiBeiText(13, weight: .semibold)
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
            }
            Spacer()
            HStack {
                Spacer()
                Button(store.ui("停止剩余导入", "Stop Remaining")) {
                    store.stopConfirmedFileImport()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
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
            }
            if !batch.pendingSourceURLs.isEmpty {
                Text(store.ui(
                    "另有 \(batch.pendingSourceURLs.count) 个文件尚未处理，原文件仍保留。",
                    "\(batch.pendingSourceURLs.count) file(s) are still waiting; their originals are unchanged."
                ))
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            if !batch.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(batch.failures) { failure in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(failure.sourceURL.lastPathComponent).weiBeiText(12, weight: .semibold)
                                Text(failure.message).weiBeiText(11).foregroundStyle(WeiBeiTheme.secondaryInk)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            Spacer()
            HStack(spacing: 8) {
                if !batch.pendingSourceURLs.isEmpty {
                    Button(store.ui(
                        "处理待导入文件（\(batch.pendingSourceURLs.count)）",
                        "Review Waiting Files (\(batch.pendingSourceURLs.count))"
                    )) {
                        store.continuePendingConfirmedFileImport()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }
                if !batch.failures.isEmpty {
                    Button(store.ui("只重试失败项", "Retry Failed Only")) {
                        store.retryFailedConfirmedFileImport()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }
                Spacer()
                if batch.pendingSourceURLs.isEmpty, batch.importedItems.count == 1 {
                    Button(store.ui("打开文稿", "Open Document")) {
                        store.openSingleConfirmedImport()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                } else if batch.pendingSourceURLs.isEmpty, batch.importedItems.count > 1 {
                    Button(store.ui("查看已导入资料", "View Imported Items")) {
                        store.showConfirmedImportBatch()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                Button(
                    batch.pendingSourceURLs.isEmpty
                        ? store.ui("完成", "Done")
                        : store.ui("暂不处理待导入文件", "Leave Waiting Files")
                ) { store.dismissConfirmedFileImport() }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
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
