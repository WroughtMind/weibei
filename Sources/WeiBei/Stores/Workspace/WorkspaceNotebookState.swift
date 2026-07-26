import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Course import, notebook creation, and transactional notebook rename behavior.
/// Notebook creation, backing-file rename transactions, wiki notes, and reference copying.
extension WorkspaceStore {
    func promptRenameNotebookNote(itemID: String) {
        guard let item = allItems.first(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        notebookCreationDraft = nil
        notebookRenameDraft = NotebookRenameDraft(itemID: item.id, title: displayTitle(for: item))
        showLibrary = true
        focus(.library)
    }

    func cancelRenameNotebookNote() {
        notebookRenameDraft = nil
    }

    func confirmRenameNotebookNote() {
        guard let draft = notebookRenameDraft else { return }
        renameNotebookNote(itemID: draft.itemID, to: draft.title)
    }

    func renameNotebookNote(itemID: String, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            noteFileError = ui("笔记名不能为空。", "Note name cannot be empty.")
            return
        }
        guard let initialIndex = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let oldTitle = displayTitle(for: importedItems[initialIndex])

        if let stagedNoteDraft, stagedNoteDraft.itemID == itemID {
            self.stagedNoteDraft = nil
            updateNote(stagedNoteDraft.value, for: itemID)
        }
        flushPendingNotePersistence(for: itemID)
        persistCurrentNote()
        if pendingNoteWritesByItemID[itemID] != nil {
            noteFileError = ui(
                "这份笔记还有待写草稿或外部冲突；两份内容都已保留，处理完成前不会重命名文件。",
                "This note still has a pending draft or external conflict. Both versions were kept, and the file will not be renamed until it is resolved."
            )
            save()
            return
        }
        guard let index = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let resolution = resolveTrackedImportedFile(at: index)
        guard let oldURL = resolution.url else {
            noteFileError = ui(
                "找不到这份笔记的当前位置，最新编辑已保留，未执行重命名。",
                "The current note location could not be found. The latest edit was retained and the note was not renamed."
            )
            save()
            return
        }
        let oldItem = importedItems[index]
        let oldID = oldItem.id
        let wasActiveNotebook = activeNotebookItemID == oldID
        let newURL = renamedNotebookURL(in: oldURL.deletingLastPathComponent(), title: title, currentURL: oldURL)
        let newTitle = newURL.deletingPathExtension().lastPathComponent
        let sourceMarkdown: String
        do {
            sourceMarkdown = wasActiveNotebook ? noteText : try notebookMarkdownReader(oldURL)
        } catch {
            noteFileError = ui(
                "无法重命名笔记：无法读取原 Markdown，文件和课程关系均未改动。",
                "Could not rename the note because the original Markdown could not be read. The file and course relationships were not changed."
            )
            save()
            return
        }
        let retitledMarkdown = retitledMarkdown(sourceMarkdown, from: oldTitle, to: newTitle)
        guard let originalContentDigest = noteBackingContentDigestsByItemID[oldID]
                ?? Self.noteContentDigest(at: oldURL) else {
            noteFileError = ui(
                "无法重命名笔记：无法确认原 Markdown 内容，文件和课程关系均未改动。",
                "Could not rename the note because the original Markdown contents could not be verified. The file and course relationships were not changed."
            )
            save()
            return
        }
        let sourceMarkdownDigest = Self.noteContentDigest(Data(sourceMarkdown.utf8))
        let willRewriteMarkdown = retitledMarkdown != sourceMarkdown
        let expectedOutputDigest = willRewriteMarkdown
            ? Self.noteContentDigest(Data(retitledMarkdown.utf8))
            : originalContentDigest
        let originalIdentity = oldItem.importedFileIdentity
            ?? importedFileIdentityResolver(oldURL)
        let replacementItemID = oldID.hasPrefix("file:") && originalIdentity != nil
            ? Self.makeImportedItemID()
            : (oldID.hasPrefix("file:") ? "file:\(newURL.path)" : oldID)
        var journalOldItem = oldItem
        journalOldItem.importedFileIdentity = originalIdentity
        let renameJournal = PendingNotebookRenameJournal(
            oldItem: journalOldItem,
            replacementItemID: replacementItemID,
            oldPath: oldURL.path,
            newPath: newURL.path,
            newTitle: newTitle,
            sourceMarkdown: sourceMarkdown,
            retitledMarkdown: retitledMarkdown,
            originalContentDigest: originalContentDigest,
            retitledContentDigest: expectedOutputDigest
        )
        guard save() else {
            noteFileError = ui(
                "无法重命名笔记：当前课程状态尚未安全保存，文件和关系均未改动。",
                "Could not rename the note because the current course state was not safely saved. The file and relationships were not changed."
            )
            return
        }
        removePendingNotebookRenameJournal()
        do {
            try writePendingNotebookRenameJournal(renameJournal)
        } catch {
            noteFileError = ui(
                "无法重命名笔记：无法建立崩溃恢复记录，文件和课程关系均未改动。",
                "Could not rename the note because a crash-recovery record could not be created. The file and course relationships were not changed."
            )
            save()
            return
        }

        var movedFile = false
        var verifiedApplicationOutput = false

        do {
            if oldURL.path != newURL.path {
                try notebookFileMover(oldURL, newURL)
                movedFile = true
            }
            let movedIdentity = importedFileIdentityResolver(newURL)
            let identityChanged = !oldID.hasPrefix("file:")
                && (originalIdentity == nil || movedIdentity != originalIdentity)
            let movedContentDigest = Self.noteContentDigest(at: newURL)
            let contentChanged = movedContentDigest != originalContentDigest
            if identityChanged || contentChanged {
                throw NSError(
                    domain: "WeiBei.ImportedFileIdentity",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: ui(
                            "文件身份或内容在重命名期间发生变化，操作已中止。",
                            "The file identity or content changed during rename, so the operation was stopped."
                        ),
                    ]
                )
            }

            var coordinatedIdentity: ImportedFileIdentity?
            var coordinatedDigest: String?
            var coordinationError: NSError?
            var operationError: Error?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(
                writingItemAt: newURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    guard importedFileIdentityResolver(coordinatedURL) == movedIdentity,
                          Self.noteContentDigest(at: coordinatedURL) == originalContentDigest else {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: ui(
                                    "写入前检测到文件被外部修改，操作已中止。",
                                    "The file changed externally before writing, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    if willRewriteMarkdown {
                        try notebookMarkdownWriter(retitledMarkdown, coordinatedURL)
                    }
                    let identityBeforeRead = importedFileIdentityResolver(coordinatedURL)
                    let outputData = try Data(contentsOf: coordinatedURL)
                    let identityAfterRead = importedFileIdentityResolver(coordinatedURL)
                    let outputDigest = Self.noteContentDigest(outputData)
                    guard identityBeforeRead == identityAfterRead,
                          outputDigest == expectedOutputDigest else {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 3,
                            userInfo: [
                                NSLocalizedDescriptionKey: ui(
                                    "写入后文件内容或身份不一致，操作已中止。",
                                    "The file contents or identity did not match after writing, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    if !oldID.hasPrefix("file:"), identityAfterRead == nil {
                        throw NSError(
                            domain: "WeiBei.ImportedFileIdentity",
                            code: 4,
                            userInfo: [
                                NSLocalizedDescriptionKey: ui(
                                    "写入标题后无法确认文件身份，操作已中止。",
                                    "The file identity could not be confirmed after writing the title, so the operation was stopped."
                                ),
                            ]
                        )
                    }
                    coordinatedIdentity = identityAfterRead
                    coordinatedDigest = outputDigest
                    verifiedApplicationOutput = true
                } catch {
                    operationError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
            guard let finalContentDigest = coordinatedDigest,
                  importedFileIdentityResolver(newURL) == coordinatedIdentity,
                  Self.noteContentDigest(at: newURL) == finalContentDigest else {
                throw NSError(
                    domain: "WeiBei.ImportedFileIdentity",
                    code: 5,
                    userInfo: [
                        NSLocalizedDescriptionKey: ui(
                            "提交前检测到文件再次变化，操作已中止。",
                            "The file changed again before the rename could be committed, so the operation was stopped."
                        ),
                    ]
                )
            }
            var renamedItem = oldItem
            renamedItem.id = replacementItemID
            renamedItem.title = newTitle
            renamedItem.subtitle = newURL.lastPathComponent
            renamedItem.urlPath = newURL.path
            renamedItem.importedFileIdentity = coordinatedIdentity ?? originalIdentity
            renamedItem.importedFileBookmarkData = Self.makeImportedFileBookmark(for: newURL)
                ?? oldItem.importedFileBookmarkData
            renamedItem.importedFileLastKnownPath = newURL.path
            importedItems[index] = renamedItem
            replaceItemIDEverywhere(oldID, with: replacementItemID)
            if wasActiveNotebook {
                noteText = retitledMarkdown
            }
            if let cached = notesByItemID[replacementItemID] {
                notesByItemID[replacementItemID] = self.retitledMarkdown(cached, from: oldTitle, to: newTitle)
            }
            noteBackingContentDigestsByItemID[replacementItemID] = finalContentDigest
            courseDocumentSearchIndex.synchronize(allItems)
            guard save() else {
                notebookRenameDraft = NotebookRenameDraft(itemID: replacementItemID, title: newTitle)
                noteFileError = ui(
                    "文件已重命名，但课程状态尚未写入磁盘；恢复记录已保留，重启后会自动接回。",
                    "The file was renamed, but the course state has not been saved to disk. A recovery record was retained so it can be reconnected after restart."
                )
                return
            }
            removePendingNotebookRenameJournal()
            notebookRenameDraft = nil
            noteFileError = nil
            showTransientNoteStatus(ui("已重命名为：\(newURL.lastPathComponent)", "Renamed to: \(newURL.lastPathComponent)"))
        } catch {
            var restoredOldPath = oldURL.path == newURL.path
            if movedFile {
                do {
                    try notebookFileMover(newURL, oldURL)
                    restoredOldPath = true
                } catch {
                    restoredOldPath = false
                }
            } else if oldURL.path != newURL.path {
                let currentOldIdentity = importedFileIdentityResolver(oldURL)
                restoredOldPath = Self.noteContentDigest(at: oldURL) == originalContentDigest
                    && (originalIdentity == nil || currentOldIdentity == originalIdentity)
            }

            if restoredOldPath {
                var restoredIdentity = importedFileIdentityResolver(oldURL)
                var restoredDigest = Self.noteContentDigest(at: oldURL)
                let recoveredApplicationOutput = willRewriteMarkdown
                    && verifiedApplicationOutput
                    && restoredDigest == expectedOutputDigest
                if recoveredApplicationOutput, willRewriteMarkdown {
                    do {
                        try notebookMarkdownWriter(sourceMarkdown, oldURL)
                        restoredIdentity = importedFileIdentityResolver(oldURL)
                        restoredDigest = Self.noteContentDigest(at: oldURL)
                    } catch {
                        restoredIdentity = importedFileIdentityResolver(oldURL)
                        restoredDigest = Self.noteContentDigest(at: oldURL)
                    }
                }
                let restoredOriginalGeneration = restoredDigest == originalContentDigest
                    && (originalIdentity == nil || restoredIdentity == originalIdentity)
                let restoredKnownApplicationCopy = recoveredApplicationOutput
                    && restoredDigest == sourceMarkdownDigest
                let restoredFileIsTrusted = restoredOriginalGeneration || restoredKnownApplicationCopy
                if restoredFileIsTrusted {
                    importedItems[index] = oldItem
                    importedItems[index].urlPath = oldURL.path
                    importedItems[index].importedFileLastKnownPath = oldURL.path
                    importedItems[index].importedFileIdentity = restoredIdentity
                    importedItems[index].importedFileBookmarkData = Self.makeImportedFileBookmark(for: oldURL)
                        ?? oldItem.importedFileBookmarkData
                    noteBackingContentDigestsByItemID[oldID] = restoredDigest
                } else {
                    importedItems[index] = oldItem
                    importedItems[index].urlPath = nil
                    importedItems[index].importedFileLastKnownPath = oldURL.path
                    notesByItemID[oldID] = sourceMarkdown
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                        baselineContentDigest: originalContentDigest
                    )
                    if wasActiveNotebook {
                        noteText = sourceMarkdown
                    }
                }
            } else if FileManager.default.fileExists(atPath: newURL.path) {
                let currentIdentity = importedFileIdentityResolver(newURL)
                let currentDigest = Self.noteContentDigest(at: newURL)
                let currentFileIsMovedOriginal = currentDigest == originalContentDigest
                    && (originalIdentity == nil || currentIdentity == originalIdentity)
                let currentFileIsKnownApplicationOutput = willRewriteMarkdown
                    && verifiedApplicationOutput
                    && currentDigest == expectedOutputDigest
                guard currentFileIsMovedOriginal || currentFileIsKnownApplicationOutput else {
                    importedItems[index] = oldItem
                    importedItems[index].urlPath = nil
                    importedItems[index].importedFileLastKnownPath = oldURL.path
                    notesByItemID[oldID] = sourceMarkdown
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                        baselineContentDigest: originalContentDigest
                    )
                    if wasActiveNotebook {
                        noteText = sourceMarkdown
                    }
                    courseDocumentSearchIndex.synchronize(allItems)
                    let savedRecovery = save()
                    if savedRecovery { removePendingNotebookRenameJournal() }
                    noteFileError = ui(
                        "无法重命名笔记：\(error.localizedDescription) 原关系和最新正文已保留，请重新定位文件。",
                        "Could not rename the note: \(error.localizedDescription) The original relationships and latest text were retained; relocate the file to continue."
                    )
                    return
                }
                importedItems[index].title = newTitle
                importedItems[index].subtitle = newURL.lastPathComponent
                importedItems[index].urlPath = newURL.path
                importedItems[index].importedFileIdentity = currentIdentity
                importedItems[index].importedFileBookmarkData = Self.makeImportedFileBookmark(for: newURL)
                    ?? oldItem.importedFileBookmarkData
                importedItems[index].importedFileLastKnownPath = newURL.path
                noteBackingContentDigestsByItemID[oldID] = currentDigest
                if currentFileIsKnownApplicationOutput, wasActiveNotebook {
                    noteText = retitledMarkdown
                }
            } else {
                importedItems[index] = oldItem
                importedItems[index].urlPath = nil
                importedItems[index].importedFileLastKnownPath = oldURL.path
                notesByItemID[oldID] = sourceMarkdown
                pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                    baselineContentDigest: originalContentDigest
                )
                if wasActiveNotebook {
                    noteText = sourceMarkdown
                }
            }
            courseDocumentSearchIndex.synchronize(allItems)
            let recovery = restoredOldPath
                ? ui("文件已恢复到原路径。", "The file was restored to its original path.")
                : ui("原关系和最新正文已保留，请重新定位文件。", "The original relationships and latest text were retained; relocate the file to continue.")
            noteFileError = ui(
                "无法重命名笔记：\(error.localizedDescription) \(recovery)",
                "Could not rename the note: \(error.localizedDescription) \(recovery)"
            )
            let savedRecovery = save()
            if savedRecovery { removePendingNotebookRenameJournal() }
        }
    }

    func openOrCreateWikiNote(title rawTitle: String) {
        let title = WikiLink.targetTitle(from: rawTitle)
        guard !title.isEmpty else { return }

        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)
        let fileName = "\(safeFileStem(title)).md"
        let url = notesDirectory.appendingPathComponent(fileName)
        let existingIdentity = importedFileIdentityResolver(url)

        if let index = importedItems.firstIndex(where: { item in
            if let existingIdentity {
                return item.importedFileIdentity == existingIdentity
            }
            return item.importedFileIdentity == nil && item.urlPath == url.path
        }) {
            importedItems[index].isNotebookNote = true
            removeLinksWhereSourceItemID(importedItems[index].id)
            select(itemID: importedItems[index].id)
            showTransientNoteStatus(ui("已打开双链笔记：\(importedItems[index].subtitle)", "Opened wiki note: \(importedItems[index].subtitle)"))
            save()
            return
        }

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try "# \(title)\n\n".write(to: url, atomically: true, encoding: .utf8)
            }
            let identity = importedFileIdentityResolver(url)
            if let identity {
                for index in importedItems.indices
                where importedItems[index].urlPath == url.path
                    && importedItems[index].importedFileIdentity != nil
                    && importedItems[index].importedFileIdentity != identity {
                    importedItems[index].importedFileLastKnownPath = url.path
                    importedItems[index].urlPath = nil
                }
            }

            let item = StudyItem(
                id: Self.makeImportedItemID(),
                title: title,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                importedFileIdentity: identity,
                importedFileBookmarkData: identity.flatMap { _ in Self.makeImportedFileBookmark(for: url) },
                importedFileLastKnownPath: url.path,
                isSample: false,
                isNotebookNote: true
            )
            if !importedItems.contains(where: { $0.urlPath == url.path }) {
                importedItems.append(item)
            }
            courseDocumentSearchIndex.synchronize(allItems)
            select(itemID: item.id)
            showTransientNoteStatus(ui("已创建双链笔记：\(url.lastPathComponent)", "Created wiki note: \(url.lastPathComponent)"))
        } catch {
            noteFileError = ui("无法创建双链笔记：\(error.localizedDescription)", "Could not create wiki note: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createNotebookNote(seed: NotebookNoteSeed, title rawTitle: String? = nil) -> StudyItem? {
        let sourceItem: StudyItem?
        let defaultTitle = suggestedNotebookTitle(for: seed)
        switch seed {
        case .blank:
            sourceItem = nil
        case .currentMaterial(let item):
            sourceItem = item
        }
        let title = (rawTitle ?? defaultTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            noteFileError = ui("笔记名不能为空。", "Note name cannot be empty.")
            return nil
        }

        persistCurrentNote()
        let notesDirectory = appOwnedFilesDirectory().appendingPathComponent("Notes", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let url = nextNotebookNoteURL(in: notesDirectory, title: title)
            var item = StudyItem(
                id: Self.makeImportedItemID(),
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: url.lastPathComponent,
                kind: .markdown,
                urlPath: url.path,
                isSample: false,
                isNotebookNote: true
            )
            let markdown = defaultNotebookNote(title: item.title, sourceItem: sourceItem)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            noteBackingContentDigestsByItemID[item.id] = Self.noteContentDigest(Data(markdown.utf8))
            item.importedFileIdentity = importedFileIdentityResolver(url)
            item.importedFileBookmarkData = item.importedFileIdentity.flatMap { _ in
                Self.makeImportedFileBookmark(for: url)
            }
            item.importedFileLastKnownPath = url.path
            importedItems.append(item)
            if let activeCourseID,
               courses.contains(where: { $0.id == activeCourseID }) {
                var memberships = courseMembershipIndex
                memberships.assign(itemIDs: [item.id], to: activeCourseID)
                courseItemMemberships = memberships.values
            }
            courseDocumentSearchIndex.synchronize(allItems)
            if let sourceItem {
                addNoteSourceLink(noteItemID: item.id, sourceItemID: sourceItem.id)
            }
            invalidateAgentContext()
            activeNotebookItemID = item.id
            noteText = markdown
            revealRichWritingSurface()
            focus(.notes)
            save()
            let status = sourceItem == nil
                ? ui("已新建空白笔记：\(url.lastPathComponent)", "Created blank note: \(url.lastPathComponent)")
                : ui("已为当前资料新建笔记：\(url.lastPathComponent)", "Created note from current material: \(url.lastPathComponent)")
            showTransientNoteStatus(status)
            return item
        } catch {
            noteFileError = ui("无法创建笔记：\(error.localizedDescription)", "Could not create note: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func openExistingNotebookNote(for material: StudyItem) -> Bool {
        guard let item = existingNotebookNote(for: material) else { return false }
        invalidateAgentContext()
        activeNotebookItemID = item.id
        noteText = noteText(for: item)
        revealRichWritingSurface()
        focus(.notes)
        save()
        showTransientNoteStatus(ui("已打开现有资料笔记：\(item.subtitle)", "Opened existing material note: \(item.subtitle)"))
        return true
    }

    func existingNotebookNote(for material: StudyItem) -> StudyItem? {
        let currentTitle = suggestedNotebookTitle(for: .currentMaterial(material))
        let chineseTitle = "\(material.title) 笔记"
        let englishTitle = "\(material.title) Notes"
        let displayChineseTitle = "\(displayTitle(for: material)) 笔记"
        let displayEnglishTitle = "\(displayTitle(for: material)) Notes"
        let titles = Set([currentTitle, chineseTitle, englishTitle, displayChineseTitle, displayEnglishTitle])
        return allItems.first { item in
            item.isNotebookNote && titles.contains(item.title)
        }
    }

    func suggestedNotebookTitle(for seed: NotebookNoteSeed) -> String {
        switch seed {
        case .blank:
            return ui("新笔记", "New Note")
        case .currentMaterial(let item):
            return ui("\(displayTitle(for: item)) 笔记", "\(displayTitle(for: item)) Notes")
        }
    }

    func useSelectedMarkdownAsNotebookNote() {
        guard let selectedItemID,
              let index = importedItems.firstIndex(where: { $0.id == selectedItemID && $0.canBecomeNotebookNote }) else { return }
        invalidateAgentContext()
        persistCurrentNote()
        importedItems[index].isNotebookNote = true
        removeLinksWhereSourceItemID(importedItems[index].id)
        activeNotebookItemID = importedItems[index].id
        if selectedItemID == importedItems[index].id {
            self.selectedItemID = sampleItems.first?.id
            readerLocationTitle = selectedMaterialItem.map(displayTitle)
        }
        noteText = noteText(for: importedItems[index])
        revealRichWritingSurface()
        focus(.notes)
        save()
    }

    func copyCurrentReference() {
        let selection = selectionContext?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference: String
        if !selectionAttachments.isEmpty {
            reference = selectionAttachments
                .map { quotedReferenceBlock(text: $0.text, sourceTitle: $0.ownerTitle) }
                .joined(separator: "\n\n")
        } else if let selectionContext, let selection, !selection.isEmpty {
            reference = quotedReferenceBlock(text: selection, sourceTitle: selectionContext.ownerTitle)
        } else {
            guard selectedMaterialItem != nil || activeNoteItem?.isNotebookNote == true else { return }
            reference = ui("来源：\(currentSourceReferenceTitle)", "Source: \(currentSourceReferenceTitle)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference, forType: .string)
    }

}
