import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func bootstrapDefaultLibraryIfNeeded() {
        guard courseLibraryRootURL == nil else { return }
        let root = CourseLibraryLayout.defaultRootURL()
        do {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(
                    CourseLibraryLayout.commonMaterialsDirectoryName,
                    isDirectory: true
                ),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(
                    CourseLibraryLayout.commonNotesDirectoryName,
                    isDirectory: true
                ),
                withIntermediateDirectories: true
            )
            try configureCourseLibrary(at: root)
        } catch {
            recordCourseLibraryUIFailure(
                error,
                operation: "bootstrap_default_library",
                path: root
            )
            showImportantOperationError(ui(
                "魏碑资料库未能建立；没有移动或覆盖现有内容。请确认文稿目录可写后重试。",
                "The WeiBei Library could not be created. Existing content was not moved or overwritten. Make sure the Documents folder is writable, then try again."
            ))
        }
    }

    func copyExternalFileIntoCourse(
        _ sourceURL: URL,
        courseID: UUID,
        isNote: Bool
    ) throws -> URL {
        guard let courseRoot = courseRootURL(for: courseID) else {
            throw CourseProjectRootError.unavailableLibrary
        }
        let directoryName = isNote
            ? CourseLibraryLayout.courseNotesDirectoryName
            : CourseLibraryLayout.courseMaterialsDirectoryName
        let directory = courseRoot.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try Self.copyPreservingOriginal(from: sourceURL, into: directory)
    }

    /// Kernel-side copy with the original dedupe semantics: identical content
    /// resolves to the existing file, real conflicts get a unique name. Size is
    /// compared before any byte read, so large imports never enter memory whole.
    nonisolated static func copyPreservingOriginal(from sourceURL: URL, into directory: URL) throws -> URL {
        try ImportFileCopy.copyPreservingOriginal(from: sourceURL, into: directory)
    }

    nonisolated static func copyExternalFileIntoLibrary(
        root: URL,
        sourceURL: URL,
        isNote: Bool
    ) throws -> URL {
        let directoryName = isNote
            ? CourseLibraryLayout.commonNotesDirectoryName
            : CourseLibraryLayout.commonMaterialsDirectoryName
        let directory = root.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try ImportFileCopy.copyPreservingOriginal(from: sourceURL, into: directory)
    }

    func libraryRelativePath(of url: URL) -> String? {
        guard let root = courseLibraryRootURL else { return nil }
        return CourseProjectPathPolicy.relativePath(of: url, inside: root)
    }

    func applyBoundLibraryRoot(
        _ resolvedRoot: URL,
        identity: ImportedFileIdentity?,
        bookmark: Data?,
        securityScope: URL? = nil
    ) {
        if let securityScope {
            activeCourseSecurityScopes["library"] = securityScope
        }
        courseLibraryRootURL = resolvedRoot
        courseLibraryUnavailableReason = nil
        if courseLibraryRootPath != resolvedRoot.path {
            courseLibraryRootPath = resolvedRoot.path
        }
        if let identity {
            courseLibraryRootIdentity = identity
        }
        if let bookmark {
            courseLibraryRootBookmarkData = bookmark
        }
        reconcileTransientNoteFileErrorsAfterLibraryBind()
    }

    /// 库根成功绑定后复核笔记降级错误。绑定窗口期的求值会留下「无法定位
    /// 笔记文件」这类瞬态误报;文件现在可定位且没有编辑草稿的条目立即撤下,
    /// 横幅不再常驻。有草稿的条目保留错误标记——它同时是写回守卫拒绝把
    /// 模板盖回磁盘的依据,只能由真正的读盘成功来清除。
    func reconcileTransientNoteFileErrorsAfterLibraryBind() {
        guard !noteOperationErrorsByItemID.isEmpty else { return }
        for (itemID, _) in noteOperationErrorsByItemID {
            guard let item = importedItems.first(where: { $0.id == itemID }),
                  item.editsBackingMarkdownFile,
                  notesByItemID[itemID] == nil,
                  let url = resolvedLibraryURL(for: item),
                  FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            setNoteFileError(nil, for: itemID)
        }
    }

    func markLibraryUnavailable(_ reason: String) {
        courseLibraryUnavailableReason = reason
    }

    func resolveRegisteredCourseFolder(
        relativePath: String,
        expectedIdentity: ImportedFileIdentity?,
        courseID: UUID,
        inside libraryRoot: URL
    ) -> URL? {
        let expectedURL = CourseProjectPathPolicy.resolvedRelativePath(
            relativePath,
            inside: libraryRoot
        )
        let liveIdentity = expectedURL.flatMap(importedFileIdentityResolver)
        if let expectedURL, let expectedIdentity, let liveIdentity,
           expectedIdentity.matchesAcrossVolumeDrift(liveIdentity) {
            return expectedURL
        }
        if let expectedURL, courseManifestCourseID(at: expectedURL) == courseID {
            return expectedURL
        }
        if let expectedIdentity {
            return findDirectory(with: expectedIdentity, inside: libraryRoot)
        }
        return nil
    }

    func courseManifestCourseID(at root: URL) -> UUID? {
        let manifestURL = root
            .appendingPathComponent(".weibei", isDirectory: true)
            .appendingPathComponent("course.json")
        guard let data = try? CourseProjectFileWorker.readBoundedRegularFile(
            at: manifestURL,
            maximumByteCount: 1_048_576
        ),
        let manifest = try? JSONDecoder().decode(CourseProjectManifest.self, from: data) else {
            return nil
        }
        return manifest.courseID
    }

    @discardableResult
    func bindLibraryRootFromBookmark() -> Bool {
        guard let bookmark = courseLibraryRootBookmarkData,
              let expectedIdentity = courseLibraryRootIdentity,
              let resolution = courseRootBookmarkResolver(bookmark) else {
            return false
        }
        let scopedURL = resolution.url
        guard courseSecurityScopeStarter(scopedURL) else {
            return false
        }
        guard let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(scopedURL),
              let liveIdentity = importedFileIdentityResolver(resolvedRoot),
              expectedIdentity.matchesAcrossVolumeDrift(liveIdentity) else {
            courseSecurityScopeStopper(scopedURL)
            return false
        }
        do {
            try validateLibraryRoot(resolvedRoot)
        } catch {
            courseSecurityScopeStopper(scopedURL)
            return false
        }
        applyBoundLibraryRoot(
            resolvedRoot,
            identity: liveIdentity,
            bookmark: resolution.isStale
                ? courseRootBookmarkMaker(resolvedRoot) ?? bookmark
                : bookmark,
            securityScope: scopedURL
        )
        return true
    }

    @discardableResult
    func bindLibraryRootOnThisComputer() -> Bool {
        let candidates = CourseLibraryRootRecovery.candidates(
            storedPath: courseLibraryRootPath,
            defaultRoot: CourseLibraryLayout.defaultRootURL(),
            includePerUserDefault: !WeiBeiSafetyTestMode.isEnabled
        )
        for candidate in candidates {
            guard let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(candidate) else {
                continue
            }
            let liveIdentity = importedFileIdentityResolver(resolvedRoot)
            let matchingCourses = courses.reduce(into: 0) { count, course in
                guard let relativePath = course.sourceRootRelativePath,
                      let folder = CourseProjectPathPolicy.resolvedRelativePath(
                        relativePath,
                        inside: resolvedRoot
                      ),
                      courseManifestCourseID(at: folder) == course.id else {
                    return
                }
                count += 1
            }
            guard CourseLibraryRootRecovery.shouldAccept(
                liveIdentity: liveIdentity,
                expectedIdentity: courseLibraryRootIdentity,
                matchingRegisteredCourseCount: matchingCourses
            ) else { continue }
            do {
                try validateLibraryRoot(resolvedRoot)
            } catch {
                recordCourseLibraryUIFailure(
                    error,
                    operation: "restore_library_root",
                    path: resolvedRoot
                )
                markLibraryUnavailable(ui(
                    "原资料库暂时无法连接；课程记录和文件仍在原位置。请重新选择原来的资料库。",
                    "The original library could not be reconnected. Course records and files remain in their original location. Re-select the original library."
                ))
                continue
            }
            applyBoundLibraryRoot(
                resolvedRoot,
                identity: liveIdentity ?? courseLibraryRootIdentity,
                bookmark: courseRootBookmarkMaker(resolvedRoot)
            )
            return true
        }
        return false
    }

    func refreshRuntimeItemURLs() {
        for index in importedItems.indices {
            guard let url = resolvedLibraryURL(for: importedItems[index]) else {
                continue
            }
            switch CourseProjectFileWorker.entryPresence(at: url) {
            case .absent, .inaccessible:
                importedItems[index].urlPath = nil
            case .presentUnmaterialized:
                // iCloud 占位符：保留路径供点开时触发系统下载（计划 §5 阶段3）。
                importedItems[index].urlPath = url.path
            case .present:
                // 文件在场即保留路径（笔记与资料同待遇）。digest 只用于对账刷新，
                // 永不用于启动断链（「文件即真相」）。
                importedItems[index].urlPath = url.path
            }
        }
    }

    struct LibraryMigrationResult {
        let destination: URL
        let movedItemCount: Int
    }

    func migrateLibrary(to destination: URL) async throws -> LibraryMigrationResult {
        guard let libraryRoot = courseLibraryRootURL else {
            throw CourseProjectRootError.missingLibrary
        }
        try validateMigrationDestinationRelationship(
            destination,
            libraryRoot: libraryRoot
        )
        let canonicalDestination: URL
        if FileManager.default.fileExists(atPath: destination.path) {
            canonicalDestination = try CourseProjectPathPolicy.existingDirectory(destination)
            try validateMigrationDestinationContent(canonicalDestination)
        } else {
            let parent = try CourseProjectPathPolicy.existingDirectory(
                destination.deletingLastPathComponent()
            )
            canonicalDestination = parent.appendingPathComponent(
                destination.lastPathComponent,
                isDirectory: true
            )
        }

        // MainActor async 上下文禁止默认重载（内部会 flushPendingWorkspaceSave()
        // RunLoop 自旋，等待另一个 MainActor Task 会死锁）；改用异步落盘。
        flushPendingNotePersistence(flushWorkspace: false)
        guard await persistWorkspaceNow() else {
            throw CourseProjectRootError.workspaceSaveFailed
        }
        libraryMigrationInFlight = true
        defer { libraryMigrationInFlight = false }

        let fileManager = FileManager.default
        let sameVolume = Self.volumeDeviceID(of: libraryRoot)
            == Self.volumeDeviceID(of: canonicalDestination.deletingLastPathComponent())
        var movedBack: [URL] = []
        do {
            if sameVolume {
                if fileManager.fileExists(atPath: canonicalDestination.path) {
                    try fileManager.removeItem(at: canonicalDestination)
                }
                try fileManager.moveItem(at: libraryRoot, to: canonicalDestination)
            } else {
                let staging = canonicalDestination.deletingLastPathComponent()
                    .appendingPathComponent(
                        canonicalDestination.lastPathComponent + "-weibei-migrating",
                        isDirectory: true
                    )
                try? fileManager.removeItem(at: staging)
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
                let entries = try fileManager.contentsOfDirectory(
                    at: libraryRoot,
                    includingPropertiesForKeys: nil
                )
                for entry in entries {
                    let target = staging.appendingPathComponent(entry.lastPathComponent)
                    try fileManager.moveItem(at: entry, to: target)
                    movedBack.append(target)
                }
                if fileManager.fileExists(atPath: canonicalDestination.path) {
                    try fileManager.removeItem(at: canonicalDestination)
                }
                try fileManager.moveItem(at: staging, to: canonicalDestination)
            }
        } catch {
            for staged in movedBack.reversed() {
                try? fileManager.moveItem(
                    at: staged,
                    to: libraryRoot.appendingPathComponent(staged.lastPathComponent)
                )
            }
            throw CourseProjectRootError.migrationFailed(error.localizedDescription)
        }

        let previousPath = courseLibraryRootPath
        let previousIdentity = courseLibraryRootIdentity
        let previousBookmark = courseLibraryRootBookmarkData
        let previousURL = courseLibraryRootURL
        let previousUnavailableReason = courseLibraryUnavailableReason

        guard let identity = importedFileIdentityResolver(canonicalDestination),
              let bookmark = courseRootBookmarkMaker(canonicalDestination) else {
            applyBoundLibraryRoot(
                libraryRoot,
                identity: previousIdentity,
                bookmark: previousBookmark
            )
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        applyBoundLibraryRoot(canonicalDestination, identity: identity, bookmark: bookmark)
        for course in courses {
            guard let relativePath = course.sourceRootRelativePath,
                  let folder = CourseProjectPathPolicy.resolvedRelativePath(
                      relativePath,
                      inside: canonicalDestination
                  ) else {
                continue
            }
            resolvedCourseRootURLs[course.id] = folder
            courseRootUnavailableReasons.removeValue(forKey: course.id)
            _ = resolveCourseOwnedItems(for: course.id)
        }
        refreshRuntimeItemURLs()
        for course in courses {
            guard let relativePath = course.sourceRootRelativePath,
                  let folder = CourseProjectPathPolicy.resolvedRelativePath(
                      relativePath,
                      inside: canonicalDestination
                  ),
                  courseManifestCourseID(at: folder) == course.id else {
                throw CourseProjectRootError.migrationFailed(
                    ui("课程 \(course.title) 的清单校验未通过", "Course manifest check failed for \(course.title)")
                )
            }
        }
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
        libraryMigrationInFlight = false
        flushPendingNotePersistence(flushWorkspace: false)
        guard await persistWorkspaceNow() else {
            if sameVolume {
                try fileManager.moveItem(at: canonicalDestination, to: libraryRoot)
            } else {
                let entries = try fileManager.contentsOfDirectory(
                    at: canonicalDestination,
                    includingPropertiesForKeys: nil
                )
                for entry in entries {
                    try fileManager.moveItem(
                        at: entry,
                        to: libraryRoot.appendingPathComponent(entry.lastPathComponent)
                    )
                }
                try fileManager.removeItem(at: canonicalDestination)
            }
            courseLibraryRootPath = previousPath
            courseLibraryRootIdentity = previousIdentity
            courseLibraryRootBookmarkData = previousBookmark
            courseLibraryRootURL = previousURL
            courseLibraryUnavailableReason = previousUnavailableReason
            for course in courses {
                guard let relativePath = course.sourceRootRelativePath,
                      let folder = CourseProjectPathPolicy.resolvedRelativePath(
                          relativePath,
                          inside: libraryRoot
                      ) else { continue }
                resolvedCourseRootURLs[course.id] = folder
                _ = resolveCourseOwnedItems(for: course.id)
            }
            refreshRuntimeItemURLs()
            courseDocumentSearchIndex.synchronize(allItems)
            invalidateAgentContext()
            let rollbackPersisted = await persistWorkspaceNow()
            WeiBeiLog.workspace.error(
                "code=library_migration_save_failed rollback_persisted=\(rollbackPersisted, privacy: .public)"
            )
            throw CourseProjectRootError.workspaceSaveFailed
        }
        WeiBeiLog.workspace.notice("library_migration_completed")
        return LibraryMigrationResult(
            destination: canonicalDestination,
            movedItemCount: (try? fileManager.contentsOfDirectory(at: canonicalDestination, includingPropertiesForKeys: nil))?.count ?? 0
        )
    }

    private func validateMigrationDestinationRelationship(_ destination: URL, libraryRoot: URL) throws {
        let rootPath = libraryRoot.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        if destinationPath == rootPath {
            throw CourseProjectRootError.destinationIsLibrary
        }
        if destinationPath.hasPrefix(rootPath + "/") {
            throw CourseProjectRootError.destinationInsideLibrary
        }
        if rootPath.hasPrefix(destinationPath + "/") {
            throw CourseProjectRootError.destinationContainsLibrary
        }
    }

    private func validateMigrationDestinationContent(_ destination: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        guard !entries.isEmpty else { return }
        if courseManifestCourseID(at: destination) != nil {
            throw CourseProjectRootError.destinationIsLibrary
        }
        throw CourseProjectRootError.destinationNotEmpty
    }

    private static func volumeDeviceID(of url: URL) -> dev_t? {
        var statBuffer = stat()
        guard stat(url.path, &statBuffer) == 0 else { return nil }
        return statBuffer.st_dev
    }

    /// Applies already-copied common-library files to the item model in one
    /// MainActor transaction after the background copy loop finishes.
    func applyImportedCommonFiles(
        _ files: [(url: URL, isNote: Bool)],
        selectsFirstImportedItem: Bool,
        reclassifiesExistingMarkdown: Bool
    ) -> [StudyItem] {
        var roleChanged = false
        var importedIDs: [String] = []
        var didChangeItems = false
        for (url, importsIntoNotes) in files {
            guard let relativePath = libraryRelativePath(of: url) else {
                continue
            }
            let matchingIndex = importedItems.firstIndex { item in
                item.storage == .common(relativePath: relativePath)
            }
            if let matchingIndex {
                importedIDs.append(importedItems[matchingIndex].id)
                let nextTitle = url.deletingPathExtension().lastPathComponent
                let nextSubtitle = url.lastPathComponent
                let nextKind = StudyItemKind.detect(from: url)
                let nextRole = Self.isMarkdownFile(url)
                let nextMaterialVisibility = !importsIntoNotes
                if importedItems[matchingIndex].isNotebookNote != nextRole {
                    roleChanged = true
                }
                if importedItems[matchingIndex].urlPath != url.path
                    || importedItems[matchingIndex].title != nextTitle
                    || importedItems[matchingIndex].subtitle != nextSubtitle
                    || importedItems[matchingIndex].kind != nextKind
                    || importedItems[matchingIndex].isNotebookNote != nextRole
                    || importedItems[matchingIndex].appearsInMaterials != nextMaterialVisibility {
                    importedItems[matchingIndex].urlPath = url.path
                    importedItems[matchingIndex].title = nextTitle
                    importedItems[matchingIndex].subtitle = nextSubtitle
                    importedItems[matchingIndex].kind = nextKind
                    importedItems[matchingIndex].isNotebookNote = nextRole
                    importedItems[matchingIndex].appearsInMaterials = nextMaterialVisibility
                    didChangeItems = true
                }
                continue
            }

            let item = StudyItem(
                id: Self.makeImportedItemID(),
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: StudyItemKind.detect(from: url),
                urlPath: url.path,
                isSample: false,
                isNotebookNote: Self.isMarkdownFile(url),
                appearsInMaterials: !importsIntoNotes,
                storage: .common(relativePath: relativePath)
            )
            importedItems.append(item)
            importedIDs.append(item.id)
            didChangeItems = true
        }

        if roleChanged {
            if let selectedItemID,
               importedItems.first(where: { $0.id == selectedItemID })?.isCourseMaterial == false {
                self.selectedItemID = courseMaterials.first?.id
                readerLocationTitle = selectedMaterialItem.map { displayTitle(for: $0) }
                restoreCurrentStudyLocation()
            }
            if let activeNotebookItemID,
               importedItems.first(where: { $0.id == activeNotebookItemID })?.isNotebookNote == false {
                self.activeNotebookItemID = courseNotebookItems.first?.id
                noteText = noteText(for: activeNoteItem)
            }
            _ = sanitizeNoteSourceLinks()
            invalidateAgentContext()
        }
        courseDocumentSearchIndex.synchronize(allItems)
        let importedIDSet = Set(importedIDs)
        let selectedItems = importedItems.filter { importedIDSet.contains($0.id) }
        if selectsFirstImportedItem,
           let first = selectedItems.first(where: \.isCourseMaterial) {
            selectMeasured(itemID: first.id, opensNotebook: false)
        } else if didChangeItems {
            save()
        }
        return selectedItems
    }
}
