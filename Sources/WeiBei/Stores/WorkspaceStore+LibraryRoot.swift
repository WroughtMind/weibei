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
            showImportantOperationError(error.localizedDescription)
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
                markLibraryUnavailable(error.localizedDescription)
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
            case .present:
                if let expectedDigest = importedItems[index].contentDigest,
                   let actual = try? CourseProjectFileWorker.snapshotFile(at: url),
                   actual.sha256 != expectedDigest {
                    importedItems[index].urlPath = nil
                    importedItems[index].importedFileIdentity = nil
                    continue
                }
                importedItems[index].urlPath = url.path
            }
        }
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
