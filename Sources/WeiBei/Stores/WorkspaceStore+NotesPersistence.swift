import AppKit
import CryptoKit
import Foundation
import WeiBeiCore

enum NoteWriteGateError: LocalizedError {
    case writeRefusedKeepContent
    case diskChangedAdoptDisk
    case writeVerificationFailed

    var errorDescription: String? {
        switch self {
        case .writeRefusedKeepContent:
            return "磁盘内容无法确认，写入已暂停以保护正文。"
        case .diskChangedAdoptDisk:
            return "笔记文件已被外部修改，待写内容仍保留在魏碑中。"
        case .writeVerificationFailed:
            return "写入后重读内容不一致，未标记为已保存。"
        }
    }
}

@MainActor
extension WorkspaceStore {
    func quotedReferenceBlock(text: String, sourceTitle: String) -> String {
        let quoted = MarkdownSelectionSanitizer.clean(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return ui(
            """
            > [!quote] 选区摘录
            >
            \(quoted)
            >
            > 来源：\(sourceTitle)
            """,
            """
            > [!quote] Selection excerpt
            >
            \(quoted)
            >
            > Source: \(sourceTitle)
            """
        )
    }

    /// 浮动 tab 的行内重命名只写自定义显示名；提交空白则清除，恢复自动跟随 title / 正文。
    func setNoteCustomDisplayTitle(_ rawTitle: String, for itemID: String) {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let next: String? = trimmed.isEmpty ? nil : trimmed
        guard importedItems[index].customDisplayTitle != next else { return }
        importedItems[index].customDisplayTitle = next
        save()
    }

    func setNoteDraft(_ markdown: String?, for itemID: String) {
        if let markdown {
            notesByItemID[itemID] = markdown
        } else {
            notesByItemID.removeValue(forKey: itemID)
        }
        courseSidebarTags.noteDraftChanged(itemID: itemID, exists: markdown != nil)
    }

    func replaceNoteDrafts(_ drafts: [String: String]) {
        notesByItemID = drafts
        courseSidebarTags.replacedNoteDrafts(keeping: Set(drafts.keys))
    }

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
        guard !notebookRenameInFlight else { return }
        notebookRenameInFlight = true
        if Self.mustSaveImmediately {
            defer { notebookRenameInFlight = false }
            _ = try? waitForCourseFileOperation {
                await self.renameNotebookNoteInTransaction(
                    itemID: itemID,
                    to: rawTitle
                )
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.notebookRenameInFlight = false }
            await self.renameNotebookNoteInTransaction(
                itemID: itemID,
                to: rawTitle
            )
        }
    }

    func renameNotebookNoteInTransaction(
        itemID: String,
        to rawTitle: String
    ) async {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            showTransientNoteStatus(ui("笔记名不能为空。", "Note name cannot be empty."))
            return
        }
        guard let initialIndex = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let oldTitle = displayTitle(for: importedItems[initialIndex])

        flushPendingNotePersistence(for: itemID)
        persistCurrentNote()
        guard let index = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let resolution = resolveTrackedImportedFile(at: index)
        guard let oldURL = resolution.url else {
            showImportantOperationError(
                ui(
                    "找不到这份笔记的当前位置，最新编辑已保留，未执行重命名。",
                    "The current note location could not be found. The latest edit was retained and the note was not renamed."
                )
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
            let message = ui(
                "无法重命名笔记：无法读取原 Markdown。",
                "Could not rename the note because the original Markdown could not be read."
            )
            showImportantOperationError(message)
            return
        }
        let retitledMarkdown = retitledMarkdown(sourceMarkdown, from: oldTitle, to: newTitle)
        let willRewriteMarkdown = retitledMarkdown != sourceMarkdown
        let originalIdentity = oldItem.importedFileIdentity
            ?? importedFileIdentityResolver(oldURL)
        let replacementItemID = oldID.hasPrefix("file:") && originalIdentity != nil
            ? Self.makeImportedItemID()
            : (oldID.hasPrefix("file:") ? "file:\(newURL.path)" : oldID)

        // S3：无 journal。若覆盖同路径标题改写，先入备份环。
        if willRewriteMarkdown, FileManager.default.fileExists(atPath: oldURL.path) {
            _ = try? NoteBackupRing.capture(
                sourceURL: oldURL,
                itemID: oldID,
                rootURL: noteBackupRootURL
            )
        }

        var movedFile = false
        do {
            if oldURL.path != newURL.path {
                if FileManager.default.fileExists(atPath: newURL.path),
                   !CourseProjectPathPolicy.isSame(oldURL, newURL) {
                    _ = try? NoteBackupRing.capture(
                        sourceURL: newURL,
                        itemID: replacementItemID,
                        rootURL: noteBackupRootURL
                    )
                }
                try notebookFileMover(oldURL, newURL)
                movedFile = true
                // 仅在「刚完成 move、尚未 rewrite」时做身份偷换防护。
                // rewrite 用原子写会换新 inode，那是预期行为，不能当偷换回滚。
                if let originalIdentity,
                   let afterMoveIdentity = importedFileIdentityResolver(newURL),
                   !originalIdentity.matchesAcrossVolumeDrift(afterMoveIdentity) {
                    try? notebookFileMover(newURL, oldURL)
                    if let idx = importedItems.firstIndex(where: { $0.id == oldID }) {
                        var rolled = oldItem
                        rolled.urlPath = nil
                        importedItems[idx] = rolled
                    }
                    setNoteDraft(sourceMarkdown, for: oldID)
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState()
                    courseDocumentSearchIndex.synchronize(allItems)
                    _ = await persistWorkspaceNow()
                    showImportantOperationError(
                        ui(
                            "重命名已中止：目标位置的文件身份与原笔记不一致，原正文已保留。",
                            "Rename was aborted because the file identity at the destination did not match the original note. The original content was retained."
                        )
                    )
                    showImportantOperationError(ui(
                        "重命名已中止：目标文件身份异常。",
                        "Rename aborted: unexpected file identity."
                    ))
                    return
                }
            }
            let expectedOutputDigest = Self.noteContentDigest(
                Data(retitledMarkdown.utf8)
            )
            if willRewriteMarkdown {
                // 写闸门：以移动后磁盘现况为基线；不符即中止并走统一回滚。
                let priorBackingDigest = noteBackingContentDigestsByItemID[oldID]
                let priorLastSelfDigest = lastSelfWrittenNoteDigestsByItemID[oldID]
                try writeNotebookMarkdownThroughGate(
                    retitledMarkdown,
                    itemID: oldID,
                    url: newURL,
                    expectedBaseline: Self.noteContentDigest(at: newURL)
                )
                noteBackingContentDigestsByItemID[oldID] = priorBackingDigest
                lastSelfWrittenNoteDigestsByItemID[oldID] = priorLastSelfDigest
                let writtenDigest = Self.noteContentDigest(at: newURL)
                guard writtenDigest == expectedOutputDigest else {
                    throw NSError(
                        domain: "WeiBei.ImportedFileIdentity",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: ui(
                                "写入后文件内容不一致，操作已中止。",
                                "The file contents did not match after writing, so the operation was stopped."
                            ),
                        ]
                    )
                }
            }
            let finalDigest = Self.noteContentDigest(at: newURL)
                ?? expectedOutputDigest
            let coordinatedIdentity = importedFileIdentityResolver(newURL)
            var renamedItem = oldItem
            renamedItem.id = replacementItemID
            renamedItem.title = newTitle
            renamedItem.subtitle = newURL.lastPathComponent
            renamedItem.urlPath = newURL.path
            renamedItem.importedFileIdentity = coordinatedIdentity ?? originalIdentity
            importedItems[index] = renamedItem
            replaceItemIDEverywhere(oldID, with: replacementItemID)
            if wasActiveNotebook {
                noteText = retitledMarkdown
            }
            if let cached = notesByItemID[replacementItemID] {
                setNoteDraft(
                    self.retitledMarkdown(cached, from: oldTitle, to: newTitle),
                    for: replacementItemID
                )
            }
            noteBackingContentDigestsByItemID[replacementItemID] = finalDigest
            courseDocumentSearchIndex.synchronize(allItems)
            _ = await persistWorkspaceNow()
            notebookRenameDraft = nil
            showTransientNoteStatus(ui("已重命名为：\(newURL.lastPathComponent)", "Renamed to: \(newURL.lastPathComponent)"))
        } catch {
            let originalContentDigest = Self.noteContentDigest(
                Data(sourceMarkdown.utf8)
            )
            var restoredOldPath = oldURL.path == newURL.path
            if movedFile {
                do {
                    try notebookFileMover(newURL, oldURL)
                    restoredOldPath = true
                } catch {
                    restoredOldPath = false
                }
            } else if FileManager.default.fileExists(atPath: oldURL.path) {
                // 移动未成功，原路径仍在。
                restoredOldPath = true
            }
            if let idx = importedItems.firstIndex(where: {
                $0.id == oldID || $0.id == replacementItemID
            }) {
                let diskDigest = restoredOldPath
                    ? Self.noteContentDigest(at: oldURL)
                    : nil
                let diskTrusted = diskDigest == originalContentDigest
                var rolled = oldItem
                if restoredOldPath, diskTrusted {
                    rolled.urlPath = oldURL.path
                    rolled.importedFileIdentity =
                        importedFileIdentityResolver(oldURL)
                        ?? originalIdentity
                    noteBackingContentDigestsByItemID[oldID] = diskDigest
                } else {
                    // 磁盘上是陌生内容或路径未恢复：切断路径关系，保留正文草稿。
                    rolled.urlPath = nil
                    setNoteDraft(sourceMarkdown, for: oldID)
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState()
                }
                importedItems[idx] = rolled
                if wasActiveNotebook {
                    noteText = sourceMarkdown
                }
                if notesByItemID[oldID] == nil, !diskTrusted {
                    setNoteDraft(sourceMarkdown, for: oldID)
                }
            }
            courseDocumentSearchIndex.synchronize(allItems)
            _ = await persistWorkspaceNow()
            let recovery = restoredOldPath
                ? ui("文件已恢复到原路径。", "The file was restored to its original path.")
                : ui("原关系和最新正文已保留，请重新定位文件。", "The original relationships and latest text were retained; relocate the file to continue.")
            let message = ui(
                "无法重命名笔记：\(error.localizedDescription) \(recovery)",
                "Could not rename the note: \(error.localizedDescription) \(recovery)"
            )
            showImportantOperationError(message)
        }
    }

    func nextNotebookNoteURL(in directory: URL, title: String) -> URL {
        let stem = safeFileStem(title)
        var index = 1
        var url = directory.appendingPathComponent("\(stem).md")
        while FileManager.default.fileExists(atPath: url.path) {
            index += 1
            url = directory.appendingPathComponent("\(stem) \(index).md")
        }
        return url
    }

    func renamedNotebookURL(in directory: URL, title: String, currentURL: URL) -> URL {
        let stem = safeFileStem(title)
        var index = 1
        var url = directory.appendingPathComponent("\(stem).md")
        while FileManager.default.fileExists(atPath: url.path) && url.path != currentURL.path {
            index += 1
            url = directory.appendingPathComponent("\(stem) \(index).md")
        }
        return url
    }

    /// 正文抬头驱动文件名：无自定义名且正文有严格 ATX 标题（`# …`）且与当前
    /// 文件名不一致时，纯 move 改文件名——一个字节内容都不碰，inode 不变，
    /// 指纹与 bookmark 保持有效。普通首行文字只影响 tab 显示，不改文件名。
    /// 只在成功落盘后调用；课程文件有自己的命名约束，不走这条路。
    func synchronizeNoteFileNameWithHeading(itemID: String, markdown: String, currentURL: URL) {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }) else { return }
        let item = importedItems[index]
        guard item.isNotebookNote else { return }
        guard item.customDisplayTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return }
        let stem = currentURL.deletingPathExtension().lastPathComponent
        guard let heading = NoteTabDisplayTitle.bodyStrictHeading(from: markdown) else { return }
        // 基线机制：只在「文件名是我们/抬头体系在管」（基线==当前文件名）时才跟随抬头改名。
        // 抬头与文件名一致时登记基线；基线缺失或对不上（典型：用户在 Finder 里
        // 自己改了文件名）时只登记、不动文件——下次编辑抬头才开始跟随。
        // 这样外部改名不会被立刻改回去（CI：Finder 移动后不允许在旧路径重建副本）。
        guard heading != stem else {
            headingSyncedNoteStemByItemID[itemID] = stem
            return
        }
        guard headingSyncedNoteStemByItemID[itemID] == stem else {
            headingSyncedNoteStemByItemID[itemID] = stem
            return
        }
        let newURL = renamedNotebookURL(
            in: currentURL.deletingLastPathComponent(),
            title: heading,
            currentURL: currentURL
        )
        guard newURL.path != currentURL.path else { return }
        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
        } catch {
            showImportantOperationError(
                ui(
                    "无法按正文抬头重命名笔记文件：\(error.localizedDescription)",
                    "Could not rename the note file to match its heading: \(error.localizedDescription)"
                )
            )
            return
        }
        let newStem = newURL.deletingPathExtension().lastPathComponent
        headingSyncedNoteStemByItemID[itemID] = newStem
        importedItems[index].title = newStem
        importedItems[index].subtitle = newURL.lastPathComponent
        importedItems[index].urlPath = newURL.path
        if let refreshed = refreshImportedFileTracking(itemID: itemID, url: newURL) {
            courseDocumentSearchIndex.schedule([refreshed])
        }
    }

    private func retitledMarkdown(_ markdown: String, from oldTitle: String, to newTitle: String) -> String {
        let prefix = "# \(oldTitle)\n"
        guard markdown.hasPrefix(prefix) else { return markdown }
        return "# \(newTitle)\n" + String(markdown.dropFirst(prefix.count))
    }

    func defaultNote(for item: StudyItem?) -> String {
        defaultNotebookNote()
    }

    /// 新建笔记的正文：完全空白——不预置模板小节，也不预置来源行。
    /// 笔记名交给显示名解析（正文抬头）与抬头驱动的文件改名负责；
    /// 资料关联由 noteSourceLink 表达，不靠正文里的来源行。
    func defaultNotebookNote() -> String {
        ""
    }

    static func noteContentDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func readNotebookMarkdown(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return markdown
    }

    nonisolated static func writeNotebookMarkdown(_ markdown: String, to url: URL) throws {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated static func moveNotebookFile(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    static func noteContentDigest(at url: URL) -> String? {
        (try? Data(contentsOf: url)).map(noteContentDigest)
    }

    /// P0 降级文案按实况区分（仅在降级分支做一次 lstat）：真的定位不到，还是
    /// 文件在但内容与本机记录不一致——后者对账循环通常几秒内以活体文件自愈。
    func noteFileUnavailableMessage(for item: StudyItem) -> String {
        let filePresent = resolvedLibraryURL(for: item).map {
            if case .present = CourseProjectFileWorker.entryPresence(at: $0) {
                return true
            }
            return false
        } ?? false
        return filePresent
            ? ui(
                "笔记文件内容与本机记录不一致（可能被外部修改），正文展示已降级为模板；已暂停自动写回以保护磁盘内容。",
                "The note file's content does not match this device's record (it may have been modified externally), so a template is shown instead of the note body. Automatic write-back is paused to protect the on-disk content."
            )
            : ui(
                "无法定位笔记文件，正文展示已降级为模板；已暂停自动写回以保护磁盘内容。",
                "The note file could not be located, so a template is shown instead of the note body. Automatic write-back is paused to protect the on-disk content."
            )
    }

    func setNoteFileError(_ message: String?, for itemID: String) {
        if let message {
            // P0：同一条错误已记录时不重复弹 transient，避免渲染期反复触发提示。
            let alreadyRecorded = noteOperationErrorsByItemID[itemID] == message
            noteOperationErrorsByItemID[itemID] = message
            if !alreadyRecorded {
                WeiBeiLog.noteRepair.error("note file error raised: \(message, privacy: .public)")
            }
            if !alreadyRecorded, activeNoteItemID == itemID {
                // 阶段3 横幅降格（计划 §5 阶段3）：文件缺席/未物化等不可用场景
                // 只保留条内状态，不再弹重要操作横幅；其余真实错误维持横幅。
                let itemUnavailable: Bool = {
                    guard let item = importedItems.first(where: { $0.id == itemID }),
                          let url = resolvedLibraryURL(for: item) else {
                        return true
                    }
                    switch CourseProjectFileWorker.entryPresence(at: url) {
                    case .present:
                        return false
                    case .presentUnmaterialized, .absent, .inaccessible:
                        return true
                    }
                }()
                if !itemUnavailable {
                    showImportantOperationError(message)
                }
            }
        } else {
            let cleared = noteOperationErrorsByItemID.removeValue(forKey: itemID)
            // 恢复时同步撤下横幅：横幅仍显示这条消息、且没有其他条目因同一消息
            // 出错时才清除——既不留下误报，也不误撤他人或更新后的错误。
            if let cleared,
               importantOperationError == cleared,
               !noteOperationErrorsByItemID.values.contains(cleared) {
                importantOperationError = nil
            }
        }
    }

    /// S2 启动迁移：旧 pendingNoteWrites 草稿按三件套写回一次；成功清除，失败转 notesByItemID 简单草稿。
    func retryRestoredPendingNoteWrites() {
        let draftItemIDs = Set(pendingNoteWritesByItemID.keys)
            .union(
                importedItems.compactMap { item in
                    item.editsBackingMarkdownFile && notesByItemID[item.id] != nil
                        ? item.id
                        : nil
                }
            )
        for itemID in draftItemIDs {
            guard let item = importedItems.first(where: {
                $0.id == itemID && $0.editsBackingMarkdownFile
            }),
            let markdown = notesByItemID[itemID] else {
                pendingNoteWritesByItemID.removeValue(forKey: itemID)
                continue
            }
            persistNote(markdown, for: item)
        }
        // 写出时尽量清空已迁移的 pending 状态机字段。
        if !pendingNoteWritesByItemID.isEmpty {
            pendingNoteWritesByItemID = [:]
            save()
        }
    }

    func persistCurrentNote() {
        guard !libraryMigrationInFlight else { return }
        guard let item = activeNoteItem else { return }
        if pendingNotePersistenceByItemID[item.id] != nil {
            flushPendingNotePersistence(for: item.id)
        } else if notesByItemID[item.id] != nil, item.editsBackingMarkdownFile {
            persistNote(noteText, for: item)
        }
    }

    func flushPendingNotePersistence() {
        flushPendingNotePersistence(flushWorkspace: true)
    }

    func flushPendingNotePersistence(flushWorkspace: Bool) {
        let itemIDs = Array(pendingNotePersistenceByItemID.keys)
        itemIDs.forEach { flushPendingNotePersistence(for: $0) }
        studyProgressSaveTask?.cancel()
        studyProgressSaveTask = nil
        syncActiveStudySession()
        // Note flush is a durability boundary: write the workspace now, not after debounce.
        if flushWorkspace {
            _ = flushPendingWorkspaceSave()
        }
    }

    func scheduleNotePersistence(_ markdown: String, for item: StudyItem) {
        pendingNotePersistenceByItemID[item.id] = PendingNotePersistence(item: item, markdown: markdown)
        pendingNotePersistenceTasks[item.id]?.cancel()
        let itemID = item.id
        let delay = notePersistenceDebounceDelay
        pendingNotePersistenceTasks[itemID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.flushPendingNotePersistence(for: itemID)
        }
    }

    func flushPendingNotePersistence(for itemID: String) {
        guard !libraryMigrationInFlight else { return }
        cancelPendingNotePersistence(for: itemID)
        guard let pending = pendingNotePersistenceByItemID.removeValue(forKey: itemID) else { return }
        WeiBeiPerf.measure("note.persist.flush", extra: "item=\(itemID)") {
            persistNote(pending.markdown, for: pending.item)
            save()
        }
    }

    func cancelPendingNotePersistence(for itemID: String) {
        pendingNotePersistenceTasks[itemID]?.cancel()
        pendingNotePersistenceTasks[itemID] = nil
    }

    /// S2 三件套：备份（外部改动）→ 闸门比对 → 原子写 → 失败留草稿。
    /// 阶段1 写闸门：比对下沉到唯一底层入口，模板守卫此阶段并存（计划 §5 阶段1）。
    /// 返回是否成功写回磁盘。
    @discardableResult
    func writeNoteMarkdownTriple(
        _ markdown: String,
        itemID: String,
        url: URL
    ) -> Bool {
        if noteEditorRecoveryConflictsByItemID[itemID] != nil {
            setNoteDraft(markdown, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteEditingSession.markExternallyModified(documentID: itemID)
            return false
        }
        // 备份判定只用「上次自写」基线，不受 reconcile/load 刷写的磁盘观察值影响。
        let lastSelfDigest = lastSelfWrittenNoteDigestsByItemID[itemID]
        let currentDigest = Self.noteContentDigest(at: url)
        if FileManager.default.fileExists(atPath: url.path),
           currentDigest != lastSelfDigest {
            _ = try? NoteBackupRing.capture(
                sourceURL: url,
                itemID: itemID,
                rootURL: noteBackupRootURL
            )
        }
        if noteBackingContentDigestsByItemID[itemID] == nil,
           let digest = importedItems.first(where: { $0.id == itemID })?.contentDigest {
            noteBackingContentDigestsByItemID[itemID] = digest
        }
        do {
            try writeNotebookMarkdownThroughGate(
                markdown,
                itemID: itemID,
                url: url,
                expectedBaseline: noteBackingContentDigestsByItemID[itemID]
            )
        } catch NoteWriteGateError.writeRefusedKeepContent {
            retainUnreachableNoteDraft(markdown, itemID: itemID)
            return false
        } catch NoteWriteGateError.diskChangedAdoptDisk {
            retainExternalModificationConflict(
                markdown,
                itemID: itemID,
                url: url
            )
            return false
        } catch {
            setNoteDraft(markdown, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteEditingSession.markSaveFailed(documentID: itemID)
            showImportantOperationError(
                ui(
                    "无法写回原 Markdown：\(url.lastPathComponent)。\(error.localizedDescription)",
                    "Could not write original Markdown: \(url.lastPathComponent). \(error.localizedDescription)"
                )
            )
            return false
        }
        setNoteDraft(nil, for: itemID)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
        setNoteFileError(nil, for: itemID)
        noteEditorDidPersist(markdown, documentID: itemID)
        return true
    }

    /// 磁盘内容被外部修改时保留待写正文，并交给现有冲突条显式选择。
    func retainExternalModificationConflict(
        _ markdown: String,
        itemID: String,
        url: URL
    ) {
        guard let diskMarkdown = try? String(contentsOf: url, encoding: .utf8) else { return }
        let baseDigest = noteBackingContentDigestsByItemID[itemID]
            ?? Self.noteContentDigest(Data(diskMarkdown.utf8))
        let revision = latestNoteEditorSnapshot.flatMap {
            $0.documentID == itemID ? $0.revision : nil
        } ?? (noteEditingSession.documentID == itemID
            ? noteEditingSession.currentRevision
            : 0)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
        setNoteDraft(markdown, for: itemID)
        loadedCourseNoteTextByItemID[itemID] = diskMarkdown
        noteEditingSession.markExternallyModified(documentID: itemID)
        noteEditorRecoveryConflict = NoteEditorRecoveryConflict(
            diskMarkdown: diskMarkdown,
            checkpoint: NoteRecoveryCheckpoint(
                metadata: NoteRecoveryMetadata(
                    documentID: itemID,
                    baseFileDigest: baseDigest,
                    checkpointDigest: Self.noteContentDigest(Data(markdown.utf8)),
                    revision: revision,
                    updatedAt: Date(),
                    dialectVersion: 1
                ),
                markdown: markdown
            )
        )
    }

    /// 全仓唯一笔记写盘闸门（计划 §5 阶段1）：所有写路径必须经此函数。
    /// 文件在场时写前重读磁盘 digest：重读失败或无基线 ⇒ 拒写并保留待写内容；
    /// 摘要不符 ⇒ 待写内容先入备份环再抛采用磁盘；一致才落盘并刷新双 digest。
    /// 禁止绕过本函数直接调用 notebookMarkdownWriter（SelfCheck SAFETY 断言白名单）。
    func writeNotebookMarkdownThroughGate(
        _ markdown: String,
        itemID: String,
        url: URL,
        expectedBaseline: String?
    ) throws {
        var coordinationError: NSError?
        var writeResult: Result<Void, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            writeResult = Result {
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    guard let expectedBaseline,
                          let diskDigest = Self.noteContentDigest(at: coordinatedURL) else {
                        WeiBeiLog.noteRepair.error(
                            "code=note_write_baseline_unavailable path=\(coordinatedURL.path, privacy: .private) expected_digest=\(expectedBaseline ?? "nil", privacy: .private) actual_digest=unreadable"
                        )
                        throw NoteWriteGateError.writeRefusedKeepContent
                    }
                    if diskDigest != expectedBaseline {
                        WeiBeiLog.noteRepair.error(
                            "code=note_write_external_conflict path=\(coordinatedURL.path, privacy: .private) expected_digest=\(expectedBaseline, privacy: .private) actual_digest=\(diskDigest, privacy: .private)"
                        )
                        _ = try? NoteBackupRing.capture(
                            content: Data(markdown.utf8),
                            itemID: itemID,
                            rootURL: noteBackupRootURL
                        )
                        throw NoteWriteGateError.diskChangedAdoptDisk
                    }
                }
                try notebookMarkdownWriter(markdown, coordinatedURL)
            }
        }
        if let writeResult {
            try writeResult.get()
        } else if let coordinationError {
            throw coordinationError
        } else {
            throw NoteWriteGateError.writeRefusedKeepContent
        }
        let writtenDigest = Self.noteContentDigest(Data(markdown.utf8))
        let verifiedDigest = Self.noteContentDigest(at: url)
        guard verifiedDigest == writtenDigest else {
            WeiBeiLog.noteRepair.error(
                "code=note_write_verification_failed path=\(url.path, privacy: .private) expected_digest=\(writtenDigest, privacy: .private) actual_digest=\(verifiedDigest ?? "unreadable", privacy: .private)"
            )
            throw NoteWriteGateError.writeVerificationFailed
        }
        noteBackingContentDigestsByItemID[itemID] = writtenDigest
        lastSelfWrittenNoteDigestsByItemID[itemID] = writtenDigest
    }

    /// 文件不可达时静默保留草稿（无冲突横幅）。
    func retainUnreachableNoteDraft(
        _ markdown: String,
        itemID: String
    ) {
        setNoteDraft(markdown, for: itemID)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
        noteEditingSession.markSaveFailed(documentID: itemID)
    }

    func persistNote(_ markdown: String, for item: StudyItem) {
        let noteItemID = item.id
        if item.editsBackingMarkdownFile {
            guard let index = importedItems.firstIndex(where: { $0.id == noteItemID }) else {
                retainUnreachableNoteDraft(markdown, itemID: noteItemID)
                save()
                return
            }
            if case .courseOwned = importedItems[index].storage {
                persistCourseOwnedNote(markdown, itemID: noteItemID)
                return
            }
            let resolution = resolveTrackedImportedFile(at: index)
            guard let url = resolution.url else {
                retainUnreachableNoteDraft(markdown, itemID: noteItemID)
                save()
                return
            }
            if noteBackingContentDigestsByItemID[noteItemID] == nil,
               let digest = importedItems[index].contentDigest {
                noteBackingContentDigestsByItemID[noteItemID] = digest
            }
            if writeNoteMarkdownTriple(markdown, itemID: noteItemID, url: url) {
                let refreshedItem = refreshImportedFileTracking(
                    itemID: noteItemID,
                    url: url
                ) ?? importedItems[index]
                courseDocumentSearchIndex.schedule([refreshedItem])
                synchronizeNoteFileNameWithHeading(itemID: noteItemID, markdown: markdown, currentURL: url)
            }
            save()
            return
        }
        setNoteDraft(markdown, for: noteItemID)
    }
}
