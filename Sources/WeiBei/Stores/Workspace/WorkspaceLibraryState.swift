import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Course import, notebook creation, and transactional notebook rename behavior.
extension WorkspaceStore {
    func importFilesFromPanel() {
        presentImportPanel(linkToActiveNote: false)
    }

    func prepareCourseFolderImportFromPanel() {
        let panel = NSOpenPanel()
        panel.title = ui("选择课程文件夹", "Choose a course folder")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK else {
            courseFolderImportDraft = nil
            return
        }

        let rootURLs = panel.urls
        Task { [weak self] in
            guard let self else { return }
            let supportedFiles = await courseLibraryService.supportedFiles(in: rootURLs)
            let draft = makeCourseFolderImportDraft(rootURLs: rootURLs, supportedFiles: supportedFiles)
            guard !draft.markdownFiles.isEmpty else {
                importCourseFolder(draft, notePaths: [])
                courseFolderImportDraft = nil
                return
            }
            courseFolderImportDraft = draft
        }
    }

    func importCourseFolder(_ draft: CourseFolderImportDraft, notePaths: Set<String>) {
        _ = importFiles(
            draft.rootURLs,
            selectsFirstImportedItem: false,
            markdownNotePaths: notePaths,
            reclassifiesExistingMarkdown: true
        )

        var memberships = courseMembershipIndex
        var selectedCourseID: UUID?
        for rootURL in draft.rootURLs {
            let standardizedRoot = rootURL.standardizedFileURL
            let itemIDs = Set(importedItems.compactMap { item -> String? in
                guard let itemURL = item.url?.standardizedFileURL,
                      Self.isFileURL(itemURL, inside: standardizedRoot) else { return nil }
                return item.id
            })
            guard !itemIDs.isEmpty else { continue }
            let courseID = ensureCourse(forImportRoot: standardizedRoot)
            memberships.assign(itemIDs: itemIDs, to: courseID)
            selectedCourseID = selectedCourseID ?? courseID
        }
        courseItemMemberships = memberships.values
        if let selectedCourseID {
            activeCourseID = selectedCourseID
        }
        save()
    }

    func ensureCourse(forImportRoot rootURL: URL) -> UUID {
        let rootPath = rootURL.standardizedFileURL.path
        if let course = courses.first(where: { $0.sourceRootPath == rootPath }) {
            return course.id
        }

        let course = Course(
            title: rootURL.lastPathComponent.isEmpty
                ? ui("未命名课程", "Untitled Course")
                : rootURL.lastPathComponent,
            colorIndex: nextCourseColorIndex(),
            sourceRootPath: rootPath
        )
        courses.append(course)
        return course.id
    }

    nonisolated static func isFileURL(_ itemURL: URL, inside rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let itemPath = itemURL.standardizedFileURL.path
        return itemPath == rootPath || itemPath.hasPrefix(rootPath + "/")
    }

    @discardableResult
    func retryWorkspaceSave() -> Bool {
        save()
    }

    func importCourseMaterialsFromPanel() {
        presentImportPanel(
            linkToActiveNote: false,
            selectsFirstImportedItem: false,
            reclassifiesExistingMarkdown: true,
            assigningToCourseID: activeCourseID,
            panelTitle: ui("选择课程资料或文件夹", "Choose course materials or a folder")
        )
    }

    func importCourseNotesFromPanel() {
        presentImportPanel(
            linkToActiveNote: false,
            selectsFirstImportedItem: false,
            markdownAsNotes: true,
            markdownOnly: true,
            reclassifiesExistingMarkdown: true,
            assigningToCourseID: activeCourseID,
            panelTitle: ui("选择 Markdown 笔记或文件夹", "Choose Markdown notes or a folder")
        )
    }

    func importAndLinkSourcesFromPanel() {
        presentImportPanel(linkToActiveNote: true)
    }

    func presentImportPanel(
        linkToActiveNote: Bool,
        selectsFirstImportedItem: Bool = true,
        markdownAsNotes: Bool = false,
        markdownOnly: Bool = false,
        reclassifiesExistingMarkdown: Bool = false,
        assigningToCourseID: UUID? = nil,
        panelTitle: String? = nil
    ) {
        let panel = NSOpenPanel()
        panel.title = panelTitle ?? ui("选择学习资料或课程文件夹", "Choose study materials or a course folder")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = markdownOnly
            ? [UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]
            : [.pdf, .html, .plainText, UTType(filenameExtension: "md") ?? .plainText, UTType(filenameExtension: "markdown") ?? .plainText]

        guard panel.runModal() == .OK else { return }
        let targetNoteID = linkToActiveNote ? activeNotebookItemID : nil
        let selectedItems = importFiles(
            panel.urls,
            selectsFirstImportedItem: selectsFirstImportedItem,
            markdownAsNotes: markdownAsNotes,
            markdownOnly: markdownOnly,
            reclassifiesExistingMarkdown: reclassifiesExistingMarkdown
        )
        if let assigningToCourseID {
            let importedPaths = Set(panel.urls
                .flatMap(Self.supportedCourseFiles(at:))
                .map { $0.standardizedFileURL.path })
            let importedItemIDs = Set(importedItems.compactMap { item -> String? in
                guard let path = item.url?.standardizedFileURL.path,
                      importedPaths.contains(path) else { return nil }
                return item.id
            })
            assignItemIDs(importedItemIDs, to: assigningToCourseID)
        }
        if let targetNoteID, targetNoteID == activeNotebookItemID {
            setLinkedSourceIDsForActiveNote(
                Set(linkedSourceIDsForActiveNote).union(selectedItems.map(\.id))
            )
        }
    }

    @discardableResult
    func importFiles(
        _ urls: [URL],
        selectsFirstImportedItem: Bool = true,
        markdownAsNotes: Bool = false,
        markdownOnly: Bool = false,
        markdownNotePaths: Set<String>? = nil,
        reclassifiesExistingMarkdown: Bool = false
    ) -> [StudyItem] {
        let supportedURLs = urls
            .flatMap(Self.supportedCourseFiles(at:))
            .reduce(into: [URL]()) { result, url in
                if !result.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    result.append(url)
                }
            }
        let expandedURLs = markdownOnly
            ? supportedURLs.filter(Self.isMarkdownFile)
            : supportedURLs
        let isNotebookNote: (URL) -> Bool = { url in
            guard Self.isMarkdownFile(url) else { return false }
            return markdownNotePaths?.contains(url.path) ?? markdownAsNotes
        }

        if reclassifiesExistingMarkdown || markdownNotePaths != nil {
            persistCurrentNote()
        }
        var roleChanged = false
        var importedIDs: [String] = []
        var didChangeItems = false
        for url in expandedURLs {
            let identity = importedFileIdentityResolver(url)
            let bookmarkData = identity.flatMap { _ in Self.makeImportedFileBookmark(for: url) }
            if let identity {
                for index in importedItems.indices
                where importedItems[index].urlPath == url.path
                    && importedItems[index].importedFileIdentity != nil
                    && importedItems[index].importedFileIdentity != identity {
                    importedItems[index].importedFileLastKnownPath = url.path
                    importedItems[index].urlPath = nil
                    didChangeItems = true
                }
            }
            let identityMatchingIndex = importedItems.firstIndex { item in
                if let identity {
                    return item.importedFileIdentity == identity
                }
                return item.importedFileIdentity == nil && item.urlPath == url.path
            }
            let legacyPathMatchingIndex = identity == nil ? nil : importedItems.firstIndex { item in
                item.id.hasPrefix("file:")
                    && item.importedFileIdentity == nil
                    && (item.urlPath == url.path || item.importedFileLastKnownPath == url.path)
            }
            let matchingIndex = identityMatchingIndex ?? legacyPathMatchingIndex

            if let matchingIndex {
                if identity != nil, importedItems[matchingIndex].id.hasPrefix("file:") {
                    let oldID = importedItems[matchingIndex].id
                    let newID = Self.makeImportedItemID()
                    importedItems[matchingIndex].id = newID
                    replaceItemIDEverywhere(oldID, with: newID)
                    didChangeItems = true
                }
                importedIDs.append(importedItems[matchingIndex].id)
                let nextTitle = url.deletingPathExtension().lastPathComponent
                let nextSubtitle = url.lastPathComponent
                let nextKind = StudyItemKind.detect(from: url)
                let nextRole = isNotebookNote(url)
                if importedItems[matchingIndex].isNotebookNote != nextRole {
                    roleChanged = true
                }
                if importedItems[matchingIndex].urlPath != url.path
                    || importedItems[matchingIndex].title != nextTitle
                    || importedItems[matchingIndex].subtitle != nextSubtitle
                    || importedItems[matchingIndex].kind != nextKind
                    || importedItems[matchingIndex].isNotebookNote != nextRole
                    || importedItems[matchingIndex].importedFileIdentity != identity
                    || importedItems[matchingIndex].importedFileBookmarkData != bookmarkData
                    || importedItems[matchingIndex].importedFileLastKnownPath != url.path {
                    importedItems[matchingIndex].urlPath = url.path
                    importedItems[matchingIndex].title = nextTitle
                    importedItems[matchingIndex].subtitle = nextSubtitle
                    importedItems[matchingIndex].kind = nextKind
                    importedItems[matchingIndex].isNotebookNote = nextRole
                    importedItems[matchingIndex].importedFileIdentity = identity
                    importedItems[matchingIndex].importedFileBookmarkData = bookmarkData
                        ?? importedItems[matchingIndex].importedFileBookmarkData
                    importedItems[matchingIndex].importedFileLastKnownPath = url.path
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
                importedFileIdentity: identity,
                importedFileBookmarkData: bookmarkData,
                importedFileLastKnownPath: url.path,
                isSample: false,
                isNotebookNote: isNotebookNote(url)
            )
            importedItems.append(item)
            importedIDs.append(item.id)
            didChangeItems = true
        }

        if roleChanged {
            if let selectedItemID,
               importedItems.first(where: { $0.id == selectedItemID })?.isNotebookNote == true {
                self.selectedItemID = courseMaterials.first?.id ?? sampleItems.first?.id
                readerLocationTitle = selectedMaterialItem.map(displayTitle)
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
        let selectedItems = importedItems.filter { importedIDSet.contains($0.id) && !$0.isNotebookNote }
        if selectsFirstImportedItem, let first = selectedItems.first {
            select(itemID: first.id)
        } else if didChangeItems {
            save()
        }
        return selectedItems
    }

    nonisolated static func resolveImportedFileIdentity(at url: URL) -> ImportedFileIdentity? {
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

    nonisolated static func makeImportedFileBookmark(for url: URL) -> Data? {
        let resourceKeys: Set<URLResourceKey> = [
            .fileResourceIdentifierKey,
            .volumeIdentifierKey,
            .creationDateKey,
        ]
        if let scopedBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: resourceKeys,
            relativeTo: nil
        ) {
            return scopedBookmark
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: resourceKeys,
            relativeTo: nil
        )
    }

    nonisolated static func resolveImportedFileBookmark(_ data: Data) -> ResolvedImportedFileBookmark? {
        var isStale = false
        if let scopedURL = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return ResolvedImportedFileBookmark(url: scopedURL.standardizedFileURL, isStale: isStale)
        }
        isStale = false
        guard let plainURL = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return ResolvedImportedFileBookmark(url: plainURL.standardizedFileURL, isStale: isStale)
    }

    nonisolated static func makeImportedItemID() -> String {
        "imported:\(UUID().uuidString.lowercased())"
    }

    func makeCourseFolderImportDraft(rootURLs: [URL], supportedFiles: [URL]) -> CourseFolderImportDraft {
        let markdownFiles = supportedFiles.filter(CourseLibraryService.isMarkdownFile)
        return CourseFolderImportDraft(
            rootURLs: rootURLs,
            markdownFiles: markdownFiles,
            notePaths: Set(markdownFiles.filter(CourseLibraryService.defaultsToNotebookNote).map(\.path)),
            automaticMaterialCount: supportedFiles.count - markdownFiles.count
        )
    }

    static func supportedCourseFiles(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            return isSupportedCourseFile(url) ? [url] : []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard isSupportedCourseFile(fileURL),
                  (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append(fileURL)
            if files.count == 500 { break }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func isSupportedCourseFile(_ url: URL) -> Bool {
        ["pdf", "html", "htm", "md", "markdown", "txt", "text"]
            .contains(url.pathExtension.lowercased())
    }

    static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    static func defaultMarkdownIsNotebookNote(_ url: URL) -> Bool {
        let description = (url.deletingPathExtension().lastPathComponent + " "
            + url.deletingLastPathComponent().pathComponents.suffix(3).joined(separator: " ")).lowercased()
        return ["笔记", "note", "notes", "notebook"].contains { description.contains($0) }
    }

}
