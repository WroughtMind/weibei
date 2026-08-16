import AppKit
import CryptoKit
import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
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

    private func renameNotebookNoteInTransaction(
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

        if let stagedNoteDraft, stagedNoteDraft.itemID == itemID {
            self.stagedNoteDraft = nil
            updateNote(stagedNoteDraft.value, for: itemID)
        }
        flushPendingNotePersistence(for: itemID)
        persistCurrentNote()
        guard let index = importedItems.firstIndex(where: { $0.id == itemID && $0.isNotebookNote }) else { return }
        let resolution = resolveTrackedImportedFile(at: index)
        guard let oldURL = resolution.url else {
            showTransientNoteStatus(
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
            showTransientNoteStatus(message)
            return
        }
        // P0 重命名哨兵：sourceMarkdown 呈默认模板形态、读盘曾降级、且磁盘另有内容
        // （digest 不同于模板），说明正文未能完整读出——继续 rename 会把模板写回新旧
        // 两个文件（8/12 诗歌笔记事故的通道）。中止并保留现状。
        if noteOperationErrorsByItemID[oldID] != nil,
           NoteTemplateShape.isDefaultTemplateShape(sourceMarkdown, title: oldTitle),
           let diskDigest = Self.noteContentDigest(at: oldURL),
           diskDigest != Self.noteContentDigest(Data(defaultNote(for: oldItem).utf8)) {
            showTransientNoteStatus(
                ui(
                    "正文未能完整读取，为保护内容未执行重命名。",
                    "The note body could not be fully read, so the rename was not performed in order to protect the content."
                )
            )
            save()
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
                        rolled.importedFileLastKnownPath = oldURL.path
                        rolled.importedFileBookmarkData = nil
                        importedItems[idx] = rolled
                    }
                    setNoteDraft(sourceMarkdown, for: oldID)
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                        baselineContentDigest: nil
                    )
                    courseDocumentSearchIndex.synchronize(allItems)
                    _ = await persistWorkspaceNow()
                    showTransientNoteStatus(
                        ui(
                            "重命名已中止：目标位置的文件身份与原笔记不一致，原正文已保留。",
                            "Rename was aborted because the file identity at the destination did not match the original note. The original content was retained."
                        )
                    )
                    showTransientNoteStatus(ui(
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
                try notebookMarkdownWriter(retitledMarkdown, newURL)
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
            renamedItem.importedFileBookmarkData = Self.makeImportedFileBookmark(for: newURL)
                ?? oldItem.importedFileBookmarkData
            renamedItem.importedFileLastKnownPath = newURL.path
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
                    rolled.importedFileLastKnownPath = oldURL.path
                    rolled.importedFileIdentity =
                        importedFileIdentityResolver(oldURL)
                        ?? originalIdentity
                    rolled.importedFileBookmarkData =
                        Self.makeImportedFileBookmark(for: oldURL)
                        ?? oldItem.importedFileBookmarkData
                    noteBackingContentDigestsByItemID[oldID] = diskDigest
                } else {
                    // 磁盘上是陌生内容或路径未恢复：切断路径关系，保留正文草稿。
                    rolled.urlPath = nil
                    rolled.importedFileLastKnownPath = oldURL.path
                    setNoteDraft(sourceMarkdown, for: oldID)
                    pendingNoteWritesByItemID[oldID] = PendingNoteWriteState(
                        baselineContentDigest: originalContentDigest
                    )
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
            showTransientNoteStatus(message)
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
            showTransientNoteStatus(
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
        importedItems[index].importedFileLastKnownPath = newURL.path
        if let bookmark = Self.makeImportedFileBookmark(for: newURL) {
            importedItems[index].importedFileBookmarkData = bookmark
        }
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

    func setNoteFileError(_ message: String?, for itemID: String) {
        if let message {
            // P0：同一条错误已记录时不重复弹 transient，避免渲染期反复触发提示。
            let alreadyRecorded = noteOperationErrorsByItemID[itemID] == message
            noteOperationErrorsByItemID[itemID] = message
            if !alreadyRecorded, activeNoteItemID == itemID {
                showTransientNoteStatus(message)
            }
        } else {
            noteOperationErrorsByItemID.removeValue(forKey: itemID)
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

    /// P0 启动修复：收敛「磁盘 vs 草稿」双真相源分叉，并修复 fileID 指纹漂移。
    ///
    /// 必须在 retryRestoredPendingNoteWrites 之前运行：retry 会把草稿直接写回，
    /// 若草稿是「读盘失败回退的模板」而磁盘仍有真实内容，先跑 repair 才能把
    /// 这种嫌疑草稿安全丢弃（否则模板会被 retry 盖回磁盘）。
    ///
    /// 安全性质：
    /// - 判定与执行分离：NoteDivergenceRepairPlanner（WeiBeiCore 纯函数）出清单，
    ///   这里只负责采集现场和执行；UserDefaults `WeiBeiNoteRepairDisabled=1`
    ///   时干跑（只打日志不写盘）。
    /// - 备份先行：restoreDraft 写盘前先把磁盘现内容入 NoteBackupRing，备份失败
    ///   则不写。
    /// - 幂等：收敛后再次运行所有项的 action 都是 .none。
    /// - 全程不弹窗；结果写 NSLog。
    func repairDivergedNotebookNotesIfNeeded() {
        guard !noteDivergenceRepairDidRun else { return }
        noteDivergenceRepairDidRun = true
        let dryRun = UserDefaults.standard.bool(forKey: "WeiBeiNoteRepairDisabled")
        var plans: [(
            itemID: String,
            action: NoteRepairAction,
            url: URL,
            draft: String?,
            identityDrifted: Bool
        )] = []
        for item in importedItems where item.editsBackingMarkdownFile {
            // 有意不走 resolveTrackedImportedFile：指纹漂移的笔记在那里会被判
            // 不可达，而本例程的职责正是修复这类漂移。直接用最后已知路径+lstat，
            // 是否可信由 planner 按 digest 内容寻址判断。
            // 注意 item.url 只来自 urlPath，老笔记可能只有 importedFileLastKnownPath，
            // 必须回退，否则这类笔记会被整批漏修。
            guard let url = item.url?.standardizedFileURL
                ?? item.importedFileLastKnownPath.map({
                    URL(fileURLWithPath: $0).standardizedFileURL
                }) else { continue }
            let draft = notesByItemID[item.id]
            let diskDigest = Self.noteContentDigest(at: url)
            let liveIdentity = importedFileIdentityResolver(url)
            let state = NoteRepairItemState(
                draftDigest: draft.map { Self.noteContentDigest(Data($0.utf8)) },
                draftIsTemplateShape: draft.map {
                    NoteTemplateShape.isDefaultTemplateShape(
                        $0,
                        title: displayTitle(for: item)
                    )
                } ?? false,
                diskDigest: diskDigest,
                templateDigest: Self.noteContentDigest(
                    Data(defaultNote(for: item).utf8)
                ),
                identityDrifted: liveIdentity.map { live in
                    item.importedFileIdentity?.matchesAcrossVolumeDrift(live) != true
                } ?? false,
                liveIdentityAvailable: liveIdentity != nil,
                lastSelfWrittenDigest: lastSelfWrittenNoteDigestsByItemID[item.id],
                recordedContentDigest: item.contentDigest
            )
            let action = NoteDivergenceRepairPlanner.action(for: state)
            if action != .none {
                plans.append((item.id, action, url, draft, state.identityDrifted))
            }
        }
        guard !plans.isEmpty else { return }
        for plan in plans {
            NSLog(
                "WeiBei note repair: item=%@ action=%@ path=%@%@",
                plan.itemID,
                plan.action.rawValue,
                plan.url.path,
                dryRun ? " (dry-run)" : ""
            )
        }
        guard !dryRun else { return }
        var changed = false
        for plan in plans {
            let itemID = plan.itemID
            switch plan.action {
            case .none:
                continue
            case .restoreDraft:
                guard let draft = plan.draft else { continue }
                // 备份先行；备份失败绝不写盘。
                do {
                    _ = try NoteBackupRing.capture(
                        sourceURL: plan.url,
                        itemID: itemID,
                        rootURL: noteBackupRootURL
                    )
                } catch {
                    NSLog(
                        "WeiBei note repair: backup failed, skip restore item=%@ error=%@",
                        itemID,
                        error.localizedDescription
                    )
                    continue
                }
                do {
                    try notebookMarkdownWriter(draft, plan.url)
                    let writtenDigest = Self.noteContentDigest(Data(draft.utf8))
                    noteBackingContentDigestsByItemID[itemID] = writtenDigest
                    lastSelfWrittenNoteDigestsByItemID[itemID] = writtenDigest
                    setNoteDraft(nil, for: itemID)
                    setNoteFileError(nil, for: itemID)
                    if let refreshed = refreshImportedFileTracking(
                        itemID: itemID,
                        url: plan.url
                    ) {
                        courseDocumentSearchIndex.schedule([refreshed])
                    }
                    changed = true
                } catch {
                    NSLog(
                        "WeiBei note repair: restore write failed item=%@ error=%@",
                        itemID,
                        error.localizedDescription
                    )
                }
            case .discardRedundantDraft:
                // 磁盘==草稿：只清草稿不动内容；仅指纹漂移时才刷指纹（幂等）。
                setNoteDraft(nil, for: itemID)
                setNoteFileError(nil, for: itemID)
                if plan.identityDrifted,
                   let refreshed = refreshImportedFileTracking(
                       itemID: itemID,
                       url: plan.url
                   ) {
                    courseDocumentSearchIndex.schedule([refreshed])
                }
                changed = true
            case .discardSuspectTemplateDraft:
                // 草稿是模板形态但磁盘另有真实内容：草稿是降级产物，丢弃它让
                // 显示层回到磁盘真相；不写盘、不刷指纹（磁盘内容未辨认为可信）。
                setNoteDraft(nil, for: itemID)
                setNoteFileError(nil, for: itemID)
                showTransientNoteStatus(
                    ui(
                        "检测到笔记正文曾降级显示为模板，已恢复为磁盘上的真实内容。",
                        "The note body had fallen back to a template; it has been restored to the real on-disk content."
                    )
                )
                changed = true
            case .refreshIdentityOnly:
                if let refreshed = refreshImportedFileTracking(
                    itemID: itemID,
                    url: plan.url
                ) {
                    courseDocumentSearchIndex.schedule([refreshed])
                    changed = true
                } else {
                    NSLog(
                        "WeiBei note repair: identity refresh failed item=%@",
                        itemID
                    )
                }
            }
        }
        if changed {
            save()
        }
    }

    func persistCurrentNote() {
        guard let item = activeNoteItem else { return }
        if let stagedNoteDraft, stagedNoteDraft.itemID == item.id {
            self.stagedNoteDraft = nil
            updateNote(stagedNoteDraft.value, for: item.id)
        }
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
        if let stagedNoteDraft {
            self.stagedNoteDraft = nil
            updateNote(stagedNoteDraft.value, for: stagedNoteDraft.itemID)
        }
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

    /// S2 三件套：备份（外部改动）→ 原子写 → 失败留草稿。
    /// 返回是否成功写回磁盘。永不因 digest 冲突拒绝写回。
    @discardableResult
    func writeNoteMarkdownTriple(
        _ markdown: String,
        itemID: String,
        url: URL
    ) -> Bool {
        // 备份判定只用「上次自写」基线，不受 reconcile/load 刷写的磁盘观察值影响。
        let lastSelfDigest = lastSelfWrittenNoteDigestsByItemID[itemID]
        let currentDigest = Self.noteContentDigest(at: url)
        // P0 模板覆盖守卫：读取降级（noteOperationErrorsByItemID 有记录）期间，
        // 拒绝把默认模板写回「另有真实内容」的磁盘文件——这正是诗歌笔记被覆盖的通道。
        // 磁盘内容是我们上次自己写的（digest == lastSelfDigest）时放行，
        // 不误伤「用户真的把正文删成模板」的连续编辑。
        if noteOperationErrorsByItemID[itemID] != nil,
           let item = importedItems.first(where: { $0.id == itemID }),
           item.editsBackingMarkdownFile {
            let template = defaultNote(for: item)
            let templateDigest = Self.noteContentDigest(Data(template.utf8))
            let writingIsTemplate = NoteTemplateShape.isDefaultTemplateShape(
                markdown,
                title: displayTitle(for: item)
            ) || Self.noteContentDigest(Data(markdown.utf8)) == templateDigest
            if writingIsTemplate,
               let currentDigest,
               currentDigest != templateDigest,
               currentDigest != lastSelfDigest {
                let message = ui(
                    "已拦截模板写回：笔记正文此前未能完整读取，为保护磁盘内容未执行写入，最新内容已保留在草稿中。",
                    "Template write-back was blocked because the note body could not be fully read earlier. The on-disk content was protected and the latest text was kept as a draft."
                )
                setNoteDraft(markdown, for: itemID)
                setNoteFileError(message, for: itemID)
                showTransientNoteStatus(message)
                return false
            }
        }
        if FileManager.default.fileExists(atPath: url.path),
           currentDigest != lastSelfDigest {
            _ = try? NoteBackupRing.capture(
                sourceURL: url,
                itemID: itemID,
                rootURL: noteBackupRootURL
            )
        }
        do {
            try notebookMarkdownWriter(markdown, url)
            let writtenDigest = Self.noteContentDigest(Data(markdown.utf8))
            noteBackingContentDigestsByItemID[itemID] = writtenDigest
            lastSelfWrittenNoteDigestsByItemID[itemID] = writtenDigest
            setNoteDraft(nil, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            setNoteFileError(nil, for: itemID)
            return true
        } catch {
            setNoteDraft(markdown, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            showTransientNoteStatus(
                ui(
                    "无法写回原 Markdown：\(url.lastPathComponent)",
                    "Could not write original Markdown: \(url.lastPathComponent)"
                )
            )
            return false
        }
    }

    /// 文件不可达时静默保留草稿（无冲突横幅）。
    func retainUnreachableNoteDraft(
        _ markdown: String,
        itemID: String
    ) {
        setNoteDraft(markdown, for: itemID)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
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
