import Foundation
import WeiBeiCore

enum ImportedIdentitySelfCheck {
    @MainActor
    static func run() throws {
        try legacyPathSnapshotMigratesItsEntireRelationshipGraph()
        try duplicateIdentityMigrationPreservesConflictingDrafts()
        try offlineLegacyPathMigratesWhenItReturns()
        try sameVolumeMoveKeepsIdentityRelationsNavigationAndIndex()
        try temporarilyUnavailableNoteRetainsLatestEdit()
        try offlineLaunchNoteRetainsEditWhenFileReturns()
        try inactiveQueuedDraftBlocksRenameWhenExternalChanged()
        try renameRejectsChangedFileGeneration()
        try activeRenameWriteFailureIsTransactional()
        try inactiveRenameReadFailureIsTransactional()
        try successfulButIncorrectRenameWriteIsRejected()
        try initialRenameMoveFailureLeavesHealthyFileAttached()
        try failedWorkspaceSaveRecoversRenameOnRestart()
        try duplicateLegacyIdentityMigratesInOneLaunch()
        try replacedAndCrossVolumeFilesReceiveNewIdentities()
    }

    @MainActor
    private static func legacyPathSnapshotMigratesItsEntireRelationshipGraph() throws {
        let fixture = try WorkspaceFixture(name: "legacy-graph")
        defer { fixture.remove() }

        let materialURL = fixture.importsDirectory.appendingPathComponent("第一讲.txt")
        let noteURL = fixture.importsDirectory.appendingPathComponent("第一讲笔记.md")
        try Data("遗留资料中的货币乘数".utf8).write(to: materialURL)
        try Data("# 第一讲笔记\n\n遗留笔记正文".utf8).write(to: noteURL)

        let legacyMaterialID = "file:\(materialURL.path)"
        let legacyNoteID = "file:\(noteURL.path)"
        let session = StudySession(
            title: "第一讲复习",
            focusItemIDs: [legacyMaterialID, legacyNoteID]
        )
        let snapshot = PersistedWorkspace(
            importedItems: [
                StudyItem(
                    id: legacyMaterialID,
                    title: "第一讲",
                    subtitle: materialURL.lastPathComponent,
                    kind: .text,
                    urlPath: materialURL.path,
                    isSample: false
                ),
                StudyItem(
                    id: legacyNoteID,
                    title: "第一讲笔记",
                    subtitle: noteURL.lastPathComponent,
                    kind: .markdown,
                    urlPath: noteURL.path,
                    isSample: false,
                    isNotebookNote: true
                ),
            ],
            notesByItemID: [legacyNoteID: "遗留缓存笔记"],
            selectedItemID: legacyMaterialID,
            activeNotebookItemID: legacyNoteID,
            noteSourceLinks: [
                NoteSourceLink(noteItemID: legacyNoteID, sourceItemID: legacyMaterialID),
            ],
            noteSourceLinksMigrationVersion: 1,
            studyLocationsByItemID: [
                legacyMaterialID: StudyLocation(
                    itemID: legacyMaterialID,
                    itemTitle: "第一讲",
                    locationTitle: "上次读到这里",
                    visitCount: 3
                ),
            ],
            studySessions: [session],
            activeStudySessionID: session.id
        )
        try fixture.write(snapshot)

        let store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        let material = try require(
            store.importedItems.first { $0.urlPath == materialURL.path },
            "旧快照迁移后找不到资料"
        )
        let note = try require(
            store.importedItems.first { $0.urlPath == noteURL.path },
            "旧快照迁移后找不到笔记"
        )

        try check(material.id.hasPrefix("imported:"), "旧资料仍在使用路径身份")
        try check(note.id.hasPrefix("imported:"), "旧笔记仍在使用路径身份")
        try check(material.importedFileIdentity != nil, "旧资料没有补入文件身份")
        try check(note.importedFileIdentity != nil, "旧笔记没有补入文件身份")
        try check(material.importedFileBookmarkData != nil, "旧资料没有补入持久文件书签")
        try check(note.importedFileBookmarkData != nil, "旧笔记没有补入持久文件书签")
        try check(material.importedFileLastKnownPath == materialURL.path, "旧资料没有保留最后路径")
        try check(store.selectedItemID == material.id, "当前资料没有迁移到新身份")
        try check(store.activeNotebookItemID == note.id, "当前笔记没有迁移到新身份")
        try check(store.noteText == "遗留缓存笔记", "升级后没有优先恢复旧版本未写回草稿")
        try check(store.linkedSourceIDs(for: note.id) == [material.id], "笔记资料关系没有随身份迁移")
        try check(store.studyLocation(for: material.id)?.itemID == material.id, "阅读位置没有随身份迁移")
        try check(Set(store.activeStudySession?.focusItemIDs ?? []) == Set([material.id, note.id]), "学习会话没有随身份迁移")

        let diskTextBeforeConflict = try String(contentsOf: noteURL, encoding: .utf8)
        store.select(itemID: "sample-pdf")
        store.flushPendingNotePersistence()
        let diskTextAfterConflict = try String(contentsOf: noteURL, encoding: .utf8)
        let persisted = try fixture.readSnapshot()
        try check(persisted.notesByItemID[note.id] == "遗留缓存笔记", "笔记缓存没有随身份迁移")
        try check(persisted.notesByItemID[legacyNoteID] == nil, "旧路径身份仍残留在笔记缓存")
        try check(persisted.pendingNoteWritesByItemID?[note.id]?.baselineContentDigest == nil, "旧版本草稿没有迁移成未知基线待写状态")
        try check(diskTextAfterConflict == diskTextBeforeConflict, "旧版本草稿在未知基线下覆盖了磁盘正文")
        try check(persisted.studyLocationsByItemID?[legacyMaterialID] == nil, "旧路径身份仍残留在阅读位置")
    }

    @MainActor
    private static func duplicateIdentityMigrationPreservesConflictingDrafts() throws {
        let fixture = try WorkspaceFixture(name: "duplicate-identity-conflict")
        defer { fixture.remove() }

        let noteURL = fixture.importsDirectory.appendingPathComponent("重复身份笔记.md")
        try Data("# 重复身份笔记\n\n磁盘正文".utf8).write(to: noteURL)
        let identity = ImportedFileIdentity(
            volumeID: 50,
            fileID: 500,
            birthTimeSeconds: 5_000,
            birthTimeNanoseconds: 50
        )
        let canonicalID = "imported:canonical-note"
        let legacyID = "file:\(noteURL.path)"
        let snapshot = PersistedWorkspace(
            importedItems: [
                StudyItem(
                    id: canonicalID,
                    title: "重复身份笔记",
                    subtitle: noteURL.lastPathComponent,
                    kind: .markdown,
                    urlPath: noteURL.path,
                    importedFileIdentity: identity,
                    importedFileLastKnownPath: noteURL.path,
                    isSample: false,
                    isNotebookNote: true
                ),
                StudyItem(
                    id: legacyID,
                    title: "重复身份笔记旧项",
                    subtitle: noteURL.lastPathComponent,
                    kind: .markdown,
                    urlPath: noteURL.path,
                    importedFileIdentity: identity,
                    importedFileLastKnownPath: noteURL.path,
                    isSample: false,
                    isNotebookNote: true
                ),
            ],
            notesByItemID: [
                canonicalID: "规范项草稿",
                legacyID: "旧项不同草稿",
            ],
            pendingNoteWritesByItemID: [
                canonicalID: PendingNoteWriteState(baselineContentDigest: "canonical-baseline"),
                legacyID: PendingNoteWriteState(baselineContentDigest: nil),
            ],
            noteBackingContentDigestsByItemID: [
                canonicalID: "canonical-digest",
                legacyID: "legacy-digest",
            ],
            activeNotebookItemID: legacyID,
            noteSourceLinksMigrationVersion: 1,
            studyLocationsByItemID: [
                canonicalID: StudyLocation(itemID: canonicalID, itemTitle: "规范项", locationTitle: "规范位置"),
                legacyID: StudyLocation(itemID: legacyID, itemTitle: "旧项", locationTitle: "旧位置"),
            ]
        )
        try fixture.write(snapshot)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { url in url.path == noteURL.path ? identity : nil }
        )
        let diskBytesBeforeMigration = try Data(contentsOf: noteURL)
        store.flushPendingNotePersistence()
        let persisted = try fixture.readSnapshot()
        let preservedLegacyID = try require(
            persisted.notesByItemID.first { $0.value == "旧项不同草稿" }?.key,
            "同身份冲突迁移丢失了旧项草稿"
        )
        try check(preservedLegacyID != canonicalID, "同身份冲突迁移把两份不同草稿折叠到一个身份")
        try check(preservedLegacyID.hasPrefix("imported:"), "同身份冲突旧项仍停留在路径身份")
        try check(store.importedItems.filter { $0.importedFileIdentity == identity }.count == 2, "同身份冲突迁移删除了其中一个可达项")
        try check(persisted.notesByItemID[canonicalID] == "规范项草稿", "同身份冲突迁移丢失了规范项草稿")
        try check(persisted.pendingNoteWritesByItemID?[canonicalID]?.baselineContentDigest == "canonical-baseline", "同身份冲突迁移破坏了规范项待写基线")
        try check(persisted.pendingNoteWritesByItemID?[preservedLegacyID]?.baselineContentDigest == nil, "同身份冲突迁移破坏了旧项未知基线")
        try check(persisted.noteBackingContentDigestsByItemID?[canonicalID] == "canonical-digest", "同身份冲突迁移破坏了规范项磁盘摘要")
        try check(persisted.noteBackingContentDigestsByItemID?[preservedLegacyID] != nil, "同身份冲突迁移丢失了旧项磁盘摘要")
        try check(persisted.studyLocationsByItemID?[canonicalID]?.locationTitle == "规范位置", "同身份冲突迁移破坏了规范项阅读位置")
        try check(persisted.studyLocationsByItemID?[preservedLegacyID]?.locationTitle == "旧位置", "同身份冲突迁移丢失了旧项阅读位置")
        try check(persisted.activeNotebookItemID == preservedLegacyID, "同身份冲突迁移没有保留旧项的活动笔记引用")

        let firstPassIDs = Set(store.importedItems.map(\.id))
        let reopenedStore = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { url in url.path == noteURL.path ? identity : nil }
        )
        reopenedStore.flushPendingNotePersistence()
        let reopenedSnapshot = try fixture.readSnapshot()
        let diskBytesAfterMigration = try Data(contentsOf: noteURL)
        try check(Set(reopenedStore.importedItems.map(\.id)) == firstPassIDs, "同身份冲突迁移第二次启动又生成了新身份")
        try check(reopenedSnapshot.notesByItemID[canonicalID] == "规范项草稿", "同身份冲突迁移第二次启动丢失规范项草稿")
        try check(reopenedSnapshot.notesByItemID[preservedLegacyID] == "旧项不同草稿", "同身份冲突迁移第二次启动丢失旧项草稿")
        try check(diskBytesAfterMigration == diskBytesBeforeMigration, "同身份冲突迁移修改了真实 Markdown 文件")
    }

    @MainActor
    private static func offlineLegacyPathMigratesWhenItReturns() throws {
        let fixture = try WorkspaceFixture(name: "offline-legacy")
        defer { fixture.remove() }

        let materialURL = fixture.importsDirectory.appendingPathComponent("离线资料.txt")
        let noteURL = fixture.importsDirectory.appendingPathComponent("离线资料笔记.md")
        try Data("# 离线资料笔记\n\n等待资料恢复".utf8).write(to: noteURL)

        let legacyMaterialID = "file:\(materialURL.path)"
        let legacyNoteID = "file:\(noteURL.path)"
        let snapshot = PersistedWorkspace(
            importedItems: [
                StudyItem(
                    id: legacyMaterialID,
                    title: "离线资料",
                    subtitle: materialURL.lastPathComponent,
                    kind: .text,
                    urlPath: materialURL.path,
                    isSample: false
                ),
                StudyItem(
                    id: legacyNoteID,
                    title: "离线资料笔记",
                    subtitle: noteURL.lastPathComponent,
                    kind: .markdown,
                    urlPath: noteURL.path,
                    isSample: false,
                    isNotebookNote: true
                ),
            ],
            selectedItemID: legacyMaterialID,
            activeNotebookItemID: legacyNoteID,
            noteSourceLinks: [
                NoteSourceLink(noteItemID: legacyNoteID, sourceItemID: legacyMaterialID),
            ],
            noteSourceLinksMigrationVersion: 1,
            studyLocationsByItemID: [
                legacyMaterialID: StudyLocation(itemID: legacyMaterialID, itemTitle: "离线资料"),
            ]
        )
        try fixture.write(snapshot)

        var store: WorkspaceStore? = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        try check(store?.importedItems.contains { $0.id == legacyMaterialID } == true, "离线旧资料不应在升级时被删除")
        let migratedNote = try require(
            store?.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "在线旧笔记没有完成稳定身份迁移"
        )

        try Data("恢复后的离线资料".utf8).write(to: materialURL)
        let restoredMaterial = try require(
            store?.importFiles([materialURL], selectsFirstImportedItem: false).first,
            "恢复后的旧资料无法重新导入"
        )
        try check(restoredMaterial.id.hasPrefix("imported:"), "恢复后的旧资料仍使用路径身份")
        try check(store?.importedItems.filter { $0.urlPath == materialURL.path }.count == 1, "恢复后的旧资料产生了重复项")
        try check(store?.linkedSourceIDs(for: migratedNote.id) == [restoredMaterial.id], "恢复后的旧资料没有接回原笔记关系")
        try check(store?.studyLocation(for: restoredMaterial.id)?.itemID == restoredMaterial.id, "恢复后的旧资料没有接回原阅读位置")
        store?.flushPendingNotePersistence()
        store = nil

        store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        try check(store?.importedItems.contains { $0.id == legacyMaterialID } == false, "重启后仍残留离线旧路径身份")
        try check(store?.linkedSourceIDs(for: migratedNote.id) == [restoredMaterial.id], "重启后恢复资料的笔记关系丢失")
    }

    @MainActor
    private static func sameVolumeMoveKeepsIdentityRelationsNavigationAndIndex() throws {
        let fixture = try WorkspaceFixture(name: "same-volume-move")
        defer { fixture.remove() }

        let originalURL = fixture.importsDirectory.appendingPathComponent("第二讲.txt")
        let noteURL = fixture.importsDirectory.appendingPathComponent("第二讲笔记.md")
        try Data("原始索引词：流动性偏好".utf8).write(to: originalURL)
        try Data("# 第二讲笔记\n".utf8).write(to: noteURL)

        var store: WorkspaceStore? = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        _ = store?.importFiles(
            [originalURL, noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let firstMaterial = try require(
            store?.courseMaterials.first { $0.urlPath == originalURL.path },
            "首次导入没有返回资料"
        )
        let note = try require(
            store?.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "首次导入没有返回笔记"
        )
        try check(firstMaterial.id.hasPrefix("imported:"), "新导入资料没有使用稳定身份")
        try check(firstMaterial.importedFileBookmarkData != nil, "新导入资料没有持久文件书签")

        store?.setLinkedSourceIDs([firstMaterial.id], for: note.id)
        store?.select(itemID: note.id)
        let editedNote = "# 第二讲笔记\n\nFinder 移动后继续编辑"
        store?.updateNote(editedNote)
        let movedNoteURL = fixture.importsDirectory.appendingPathComponent("第二讲笔记-已整理.md")
        try FileManager.default.moveItem(at: noteURL, to: movedNoteURL)
        store?.flushPendingNotePersistence()
        try check(!FileManager.default.fileExists(atPath: noteURL.path), "笔记移动后保存错误地在旧路径新建副本")
        let persistedMovedNote = try String(contentsOf: movedNoteURL, encoding: .utf8)
        try check(persistedMovedNote == editedNote, "笔记移动后最新正文没有写入真实文件")
        store?.select(itemID: firstMaterial.id)
        let originalSessionID = store?.activeStudySessionID

        let searchIndex = CourseDocumentSearchIndex(
            databaseURL: fixture.indexDirectory.appendingPathComponent("search.sqlite3")
        )
        let originalSearch = searchIndex.lookup(items: [firstMaterial], query: "流动性偏好")
        try check(originalSearch[firstMaterial.id]?.text?.contains("流动性偏好") == true, "首次导入没有进入全文索引")

        let renamedURL = fixture.importsDirectory.appendingPathComponent("第二讲-改名.txt")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        store = nil

        store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        let renamedMaterial = try require(
            store?.courseMaterials.first { $0.id == firstMaterial.id },
            "重启后找不到改名资料"
        )
        try check(renamedMaterial.id == firstMaterial.id, "同卷改名并重启后资料身份发生变化")
        try check(renamedMaterial.urlPath == renamedURL.path, "同卷改名后必须重新导入才能找到新路径")
        try check(store?.importedItems.filter { $0.id == firstMaterial.id }.count == 1, "同卷改名后出现重复资料")
        let movedNote = try require(
            store?.courseNotebookItems.first { $0.id == note.id },
            "重启后找不到移动中的活跃笔记"
        )
        try check(movedNote.urlPath == movedNoteURL.path, "活跃笔记移动后必须重新导入才能找到新路径")
        try check(store?.noteText == editedNote, "活跃笔记移动后重启没有从新路径加载正文")
        try check(store?.linkedSourceIDs(for: note.id) == [firstMaterial.id], "改名后笔记关系丢失")
        try check(store?.studyLocation(for: firstMaterial.id) != nil, "改名后阅读位置丢失")
        try check(store?.activeStudySessionID == originalSessionID, "改名后学习会话被替换")
        try check(Set(store?.activeStudySession?.focusItemIDs ?? []).isSuperset(of: [firstMaterial.id, note.id]), "改名后学习会话焦点丢失")

        let countBeforeDuplicateImport = store?.importedItems.count
        let duplicateImport = try require(
            store?.importFiles([renamedURL], selectsFirstImportedItem: false).first,
            "改名资料重复导入失败"
        )
        try check(duplicateImport.id == firstMaterial.id, "重复导入改名资料产生了新身份")
        try check(store?.importedItems.count == countBeforeDuplicateImport, "重复导入改名资料产生了重复项")

        store?.select(itemID: firstMaterial.id)
        store?.select(itemID: "sample-pdf")
        store?.navigateBackInWorkspace()
        try check(store?.selectedItemID == firstMaterial.id, "资料改名后后退导航没有回到原资料")
        try check(store?.selectedMaterialItem?.urlPath == renamedURL.path, "改名后的后退导航仍指向旧路径")
        let movedDirectory = fixture.importsDirectory.appendingPathComponent("已整理", isDirectory: true)
        try FileManager.default.createDirectory(at: movedDirectory, withIntermediateDirectories: true)
        let movedURL = movedDirectory.appendingPathComponent("第二讲最终版.txt")
        try FileManager.default.moveItem(at: renamedURL, to: movedURL)
        try Data("更新后的索引词：期限结构理论".utf8).write(to: movedURL)
        store?.flushPendingNotePersistence()
        store = nil

        store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        let movedMaterial = try require(
            store?.courseMaterials.first { $0.id == firstMaterial.id },
            "再次重启后找不到移动资料"
        )
        try check(movedMaterial.id == firstMaterial.id, "同卷移动后资料身份发生变化")
        try check(movedMaterial.urlPath == movedURL.path, "同卷移动后必须重新导入才能找到新路径")

        searchIndex.synchronize([movedMaterial])
        let movedSearch = searchIndex.lookup(items: [movedMaterial], query: "期限结构理论")
        try check(movedSearch[firstMaterial.id]?.text?.contains("期限结构理论") == true, "资料移动后全文索引没有沿用身份并刷新内容")

        try check(store?.linkedSourceIDs(for: note.id) == [firstMaterial.id], "再次重启后笔记关系丢失")

        let finderRenamedNoteURL = fixture.importsDirectory.appendingPathComponent("Finder刚移动的笔记.md")
        try FileManager.default.moveItem(at: movedNoteURL, to: finderRenamedNoteURL)
        store?.renameNotebookNote(itemID: note.id, to: "第二讲最终笔记")
        let appRenamedNote = try require(
            store?.courseNotebookItems.first { $0.id == note.id },
            "应用内重命名后找不到原笔记身份"
        )
        try check(appRenamedNote.urlPath?.hasSuffix("第二讲最终笔记.md") == true, "应用内重命名没有更新笔记路径")
        store?.flushPendingNotePersistence()
        store = nil
        store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        try check(store?.courseNotebookItems.first { $0.id == note.id }?.urlPath == appRenamedNote.urlPath, "应用内重命名后重启丢失笔记路径")
        try check(store?.noteText.contains("Finder 移动后继续编辑") == true, "应用内重命名后重启丢失笔记正文")
        try check(store?.linkedSourceIDs(for: note.id) == [firstMaterial.id], "应用内重命名后重启丢失笔记关系")

        let appRenamedNoteURL = try require(appRenamedNote.url, "应用内重命名后笔记没有真实路径")
        let finalNoteURL = movedDirectory.appendingPathComponent("第二讲归档笔记.md")
        try FileManager.default.moveItem(at: appRenamedNoteURL, to: finalNoteURL)
        store = nil
        store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        try check(store?.courseNotebookItems.first { $0.id == note.id }?.urlPath == finalNoteURL.path, "笔记只移动不编辑并重启后没有恢复新路径")
        try check(store?.noteText.contains("Finder 移动后继续编辑") == true, "笔记只移动不编辑并重启后没有加载真实正文")
    }

    @MainActor
    private static func temporarilyUnavailableNoteRetainsLatestEdit() throws {
        let fixture = try WorkspaceFixture(name: "temporarily-unavailable-note")
        defer { fixture.remove() }

        let noteURL = fixture.importsDirectory.appendingPathComponent("暂时不可用笔记.md")
        let diskText = "# 暂时不可用笔记\n\n磁盘旧正文"
        let latestEdit = "# 暂时不可用笔记\n\n断开期间的最新编辑"
        try Data(diskText.utf8).write(to: noteURL)
        let fixedIdentity = ImportedFileIdentity(
            volumeID: 20,
            fileID: 200,
            birthTimeSeconds: 2_000,
            birthTimeNanoseconds: 20
        )
        var identityIsAvailable = true
        let resolver: (URL) -> ImportedFileIdentity? = { url in
            identityIsAvailable && url.path == noteURL.path ? fixedIdentity : nil
        }

        var store: WorkspaceStore? = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        _ = store?.importFiles(
            [noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let note = try require(
            store?.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "暂时不可用场景无法导入笔记"
        )
        store?.select(itemID: note.id)
        identityIsAvailable = false
        store?.updateNote(latestEdit)
        store?.flushPendingNotePersistence()
        let unavailableDiskText = try String(contentsOf: noteURL, encoding: .utf8)
        try check(unavailableDiskText == diskText, "文件不可用时不应覆盖磁盘旧正文")
        let cachedSnapshot = try fixture.readSnapshot()
        try check(cachedSnapshot.notesByItemID[note.id] == latestEdit, "文件不可用时没有保存最新编辑缓存")
        try check(cachedSnapshot.pendingNoteWritesByItemID?[note.id] != nil, "文件不可用时没有记录待写草稿的磁盘基线")
        store = nil

        identityIsAvailable = true
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        try check(store?.noteText == latestEdit, "文件恢复后重启没有优先恢复最新编辑缓存")
        store?.select(itemID: "sample-pdf")
        store?.flushPendingNotePersistence()
        let restoredDiskText = try String(contentsOf: noteURL, encoding: .utf8)
        let restoredSnapshot = try fixture.readSnapshot()
        try check(restoredDiskText == latestEdit, "文件恢复后没有把最新编辑写回真实文件")
        try check(restoredSnapshot.notesByItemID[note.id] == nil, "最新编辑写回成功后仍残留待写缓存")
        try check(restoredSnapshot.pendingNoteWritesByItemID?[note.id] == nil, "最新编辑写回成功后仍残留待写状态")

        store?.select(itemID: note.id)
        let conflictedEdit = "# 暂时不可用笔记\n\n魏碑断开期间的第二份编辑"
        identityIsAvailable = false
        store?.updateNote(conflictedEdit)
        store?.flushPendingNotePersistence()
        store = nil

        identityIsAvailable = true
        let externalEdit = "# 暂时不可用笔记\n\n外部编辑器的新正文"
        let externalHandle = try FileHandle(forWritingTo: noteURL)
        try externalHandle.truncate(atOffset: 0)
        try externalHandle.write(contentsOf: Data(externalEdit.utf8))
        try externalHandle.synchronize()
        try externalHandle.close()

        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        try check(store?.noteText == conflictedEdit, "磁盘冲突后没有保留魏碑待写草稿")
        store?.select(itemID: "sample-pdf")
        store?.flushPendingNotePersistence()
        let conflictDiskText = try String(contentsOf: noteURL, encoding: .utf8)
        let conflictSnapshot = try fixture.readSnapshot()
        try check(conflictDiskText == externalEdit, "魏碑待写草稿静默覆盖了外部编辑")
        try check(conflictSnapshot.notesByItemID[note.id] == conflictedEdit, "发生冲突后魏碑待写草稿没有继续保留")
        try check(conflictSnapshot.pendingNoteWritesByItemID?[note.id] != nil, "发生冲突后待写草稿丢失磁盘基线")
        try check(store?.noteFileError?.contains("冲突") == true, "发生冲突后没有向用户说明两份编辑需要处理")
    }

    @MainActor
    private static func offlineLaunchNoteRetainsEditWhenFileReturns() throws {
        let fixture = try WorkspaceFixture(name: "offline-launch-note")
        defer { fixture.remove() }

        let noteURL = fixture.importsDirectory.appendingPathComponent("启动前离线笔记.md")
        let holdingURL = fixture.root.appendingPathComponent("离线保管中的笔记.md")
        let originalText = "# 启动前离线笔记\n\n原始正文"
        let knownBaselineEdit = "# 启动前离线笔记\n\n已知基线下的离线编辑"
        let unknownBaselineEdit = "# 启动前离线笔记\n\n未知基线下的离线编辑"
        try Data(originalText.utf8).write(to: noteURL)
        let fixedIdentity = ImportedFileIdentity(
            volumeID: 30,
            fileID: 300,
            birthTimeSeconds: 3_000,
            birthTimeNanoseconds: 30
        )
        var identityIsAvailable = true
        let resolver: (URL) -> ImportedFileIdentity? = { url in
            identityIsAvailable && url.path == noteURL.path ? fixedIdentity : nil
        }

        var store: WorkspaceStore? = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        _ = store?.importFiles(
            [noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let note = try require(
            store?.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "启动前离线场景无法导入笔记"
        )
        store?.select(itemID: note.id)
        store?.flushPendingNotePersistence()
        store = nil

        try FileManager.default.moveItem(at: noteURL, to: holdingURL)
        identityIsAvailable = false
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        try check(store?.courseNotebookItems.first { $0.id == note.id }?.urlPath == nil, "启动前离线的笔记仍错误保留可写路径")
        store?.updateNote(knownBaselineEdit)
        store?.flushPendingNotePersistence()
        let offlineSnapshot = try fixture.readSnapshot()
        try check(offlineSnapshot.pendingNoteWritesByItemID?[note.id] != nil, "启动前离线编辑没有建立待写状态")
        store = nil

        try FileManager.default.moveItem(at: holdingURL, to: noteURL)
        identityIsAvailable = true
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        try check(store?.noteText == knownBaselineEdit, "文件恢复后没有恢复启动前离线编辑")
        store?.select(itemID: "sample-pdf")
        store?.flushPendingNotePersistence()
        let safelyRecoveredText = try String(contentsOf: noteURL, encoding: .utf8)
        try check(safelyRecoveredText == knownBaselineEdit, "已知磁盘基线未变化时没有安全补写离线编辑")
        store = nil

        var unknownBaselineSnapshot = try fixture.readSnapshot()
        unknownBaselineSnapshot.noteBackingContentDigestsByItemID = [:]
        try fixture.write(unknownBaselineSnapshot)
        try FileManager.default.moveItem(at: noteURL, to: holdingURL)
        identityIsAvailable = false
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        store?.updateNote(unknownBaselineEdit)
        store?.flushPendingNotePersistence()
        let pendingUnknownSnapshot = try fixture.readSnapshot()
        try check(pendingUnknownSnapshot.pendingNoteWritesByItemID?[note.id]?.baselineContentDigest == nil, "未知磁盘基线被错误伪造成已知基线")
        store = nil

        try FileManager.default.moveItem(at: holdingURL, to: noteURL)
        identityIsAvailable = true
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: resolver
        )
        try check(store?.noteText == unknownBaselineEdit, "未知基线的离线草稿没有恢复")
        store?.select(itemID: "sample-pdf")
        store?.flushPendingNotePersistence()
        let unknownBaselineDiskText = try String(contentsOf: noteURL, encoding: .utf8)
        let unknownConflictSnapshot = try fixture.readSnapshot()
        try check(unknownBaselineDiskText == knownBaselineEdit, "未知基线的草稿错误覆盖了恢复文件")
        try check(unknownConflictSnapshot.notesByItemID[note.id] == unknownBaselineEdit, "未知基线冲突后草稿没有保留")
        try check(unknownConflictSnapshot.pendingNoteWritesByItemID?[note.id]?.baselineContentDigest == nil, "未知基线冲突后被错误回填为当前磁盘基线")
        store?.renameNotebookNote(itemID: note.id, to: "冲突期间不应改名")
        let noteStillExistsAfterBlockedRename = FileManager.default.fileExists(atPath: noteURL.path)
        let postRenameConflictDiskText = noteStillExistsAfterBlockedRename
            ? try String(contentsOf: noteURL, encoding: .utf8)
            : ""
        let postRenameConflictSnapshot = try fixture.readSnapshot()
        try check(noteStillExistsAfterBlockedRename, "未知基线冲突期间仍执行了笔记重命名")
        try check(postRenameConflictDiskText == knownBaselineEdit, "未知基线冲突期间重命名操作修改了外部文件")
        try check(postRenameConflictSnapshot.pendingNoteWritesByItemID?[note.id]?.baselineContentDigest == nil, "未知基线冲突期间重命名绕过了待写保护")
    }

    @MainActor
    private static func inactiveQueuedDraftBlocksRenameWhenExternalChanged() throws {
        let fixture = try WorkspaceFixture(name: "inactive-queued-rename")
        defer { fixture.remove() }

        let noteAURL = fixture.importsDirectory.appendingPathComponent("A笔记.md")
        let noteBURL = fixture.importsDirectory.appendingPathComponent("B笔记.md")
        try Data("# A笔记\n\nA 原文".utf8).write(to: noteAURL)
        try Data("# B笔记\n\nB 原文".utf8).write(to: noteBURL)
        let store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        _ = store.importFiles(
            [noteAURL, noteBURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteAURL.path, noteBURL.path]
        )
        let noteA = try require(
            store.courseNotebookItems.first { $0.urlPath == noteAURL.path },
            "迟到草稿场景找不到 A 笔记"
        )
        let noteB = try require(
            store.courseNotebookItems.first { $0.urlPath == noteBURL.path },
            "迟到草稿场景找不到 B 笔记"
        )
        store.select(itemID: noteA.id)
        store.select(itemID: noteB.id)
        try check(store.activeNotebookItemID == noteB.id, "迟到草稿场景没有让 B 成为当前活动笔记")

        let lateDraft = "# A笔记\n\n魏碑迟到草稿"
        let externalEdit = "# A笔记\n\n外部编辑器更新"
        store.updateNote(lateDraft, for: noteA.id)
        let externalHandle = try FileHandle(forWritingTo: noteAURL)
        try externalHandle.truncate(atOffset: 0)
        try externalHandle.write(contentsOf: Data(externalEdit.utf8))
        try externalHandle.synchronize()
        try externalHandle.close()

        store.renameNotebookNote(itemID: noteA.id, to: "A笔记改名")
        let originalPathStillExists = FileManager.default.fileExists(atPath: noteAURL.path)
        let diskText = originalPathStillExists
            ? try String(contentsOf: noteAURL, encoding: .utf8)
            : ""
        store.flushPendingNotePersistence()
        let snapshot = try fixture.readSnapshot()
        try check(originalPathStillExists, "非活动 A 笔记的迟到草稿未处理就执行了重命名")
        try check(diskText == externalEdit, "非活动 A 笔记的迟到草稿覆盖了外部编辑")
        try check(snapshot.notesByItemID[noteA.id] == lateDraft, "非活动 A 笔记的迟到草稿没有保留")
        try check(snapshot.pendingNoteWritesByItemID?[noteA.id] != nil, "非活动 A 笔记的冲突没有建立待写状态")
    }

    @MainActor
    private static func renameRejectsChangedFileGeneration() throws {
        let fixture = try WorkspaceFixture(name: "rename-generation-change")
        defer { fixture.remove() }

        let noteURL = fixture.importsDirectory.appendingPathComponent("身份固定笔记.md")
        let renamedURL = fixture.importsDirectory.appendingPathComponent("不应采用的新身份.md")
        try Data("# 身份固定笔记\n\n原始内容".utf8).write(to: noteURL)
        let originalIdentity = ImportedFileIdentity(
            volumeID: 40,
            fileID: 400,
            birthTimeSeconds: 4_000,
            birthTimeNanoseconds: 40
        )
        let swappedIdentity = ImportedFileIdentity(
            volumeID: 40,
            fileID: 401,
            birthTimeSeconds: 4_001,
            birthTimeNanoseconds: 41
        )
        var observedSwappedIdentity = false
        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { url in
                if url.path == renamedURL.path {
                    observedSwappedIdentity = true
                    return swappedIdentity
                }
                if url.path == noteURL.path {
                    return observedSwappedIdentity ? swappedIdentity : originalIdentity
                }
                return nil
            }
        )
        _ = store.importFiles(
            [noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let note = try require(
            store.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "身份偷换场景无法导入笔记"
        )
        store.select(itemID: note.id)
        store.renameNotebookNote(itemID: note.id, to: "不应采用的新身份")

        let retained = try require(
            store.courseNotebookItems.first { $0.id == note.id },
            "身份偷换后原笔记状态丢失"
        )
        try check(FileManager.default.fileExists(atPath: noteURL.path), "重命名后身份变化时没有把原文件移回旧路径")
        try check(!FileManager.default.fileExists(atPath: renamedURL.path), "重命名后身份变化时错误保留了新路径文件")
        try check(retained.urlPath == nil, "重命名后陌生文件被错误接回原笔记关系")
        try check(retained.importedFileIdentity == originalIdentity, "重命名后身份变化时新文件继承了原关系身份")
        try check(store.noteFileError?.contains("身份") == true, "重命名后身份变化时没有向用户说明已中止")
        let snapshot = try fixture.readSnapshot()
        try check(snapshot.notesByItemID[note.id] != nil, "陌生身份回滚后没有保留原笔记正文")
        try check(snapshot.pendingNoteWritesByItemID?[note.id] != nil, "陌生身份回滚后没有建立待写保护")
    }

    @MainActor
    private static func activeRenameWriteFailureIsTransactional() throws {
        let fixture = try WorkspaceFixture(name: "active-rename-write-failure")
        defer { fixture.remove() }

        let materialURL = fixture.importsDirectory.appendingPathComponent("关联资料.txt")
        let noteURL = fixture.importsDirectory.appendingPathComponent("写入失败笔记.md")
        let renamedURL = fixture.importsDirectory.appendingPathComponent("不应成功的改名.md")
        let originalMarkdown = "# 写入失败笔记\n\n最新正文"
        try Data("关联资料正文".utf8).write(to: materialURL)
        try Data(originalMarkdown.utf8).write(to: noteURL)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            notebookMarkdownWriter: { markdown, url in
                if url.path == renamedURL.path {
                    throw NSError(
                        domain: "WeiBei.ImportedIdentitySelfCheck",
                        code: 71,
                        userInfo: [NSLocalizedDescriptionKey: "injected rename write failure"]
                    )
                }
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        )
        _ = store.importFiles(
            [materialURL, noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let material = try require(
            store.courseMaterials.first { $0.urlPath == materialURL.path },
            "写入失败场景无法导入资料"
        )
        let note = try require(
            store.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "写入失败场景无法导入笔记"
        )
        store.setLinkedSourceIDs([material.id], for: note.id)
        store.select(itemID: note.id)
        store.renameNotebookNote(itemID: note.id, to: "不应成功的改名")

        let retained = try require(
            store.courseNotebookItems.first { $0.id == note.id },
            "活动笔记写入失败后原身份丢失"
        )
        try check(FileManager.default.fileExists(atPath: noteURL.path), "活动笔记标题写入失败后没有恢复原路径")
        try check(!FileManager.default.fileExists(atPath: renamedURL.path), "活动笔记标题写入失败后仍保留了新路径")
        try check(retained.urlPath == noteURL.path, "活动笔记标题写入失败后课程状态提前采用了新路径")
        try check(store.linkedSourceIDs(for: note.id) == [material.id], "活动笔记标题写入失败后关系图被提前迁移")
        let diskMarkdown = try String(contentsOf: noteURL, encoding: .utf8)
        try check(diskMarkdown == originalMarkdown, "活动笔记标题写入失败后磁盘正文发生变化")
        try check(store.noteFileError?.contains("无法重命名") == true, "活动笔记标题写入失败后仍显示成功")
    }

    @MainActor
    private static func inactiveRenameReadFailureIsTransactional() throws {
        let fixture = try WorkspaceFixture(name: "inactive-rename-read-failure")
        defer { fixture.remove() }

        let materialURL = fixture.importsDirectory.appendingPathComponent("当前资料.txt")
        let noteURL = fixture.importsDirectory.appendingPathComponent("读取失败笔记.md")
        let renamedURL = fixture.importsDirectory.appendingPathComponent("不应移动的笔记.md")
        try Data("当前资料正文".utf8).write(to: materialURL)
        try Data("# 读取失败笔记\n\n磁盘正文".utf8).write(to: noteURL)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            notebookMarkdownReader: { url in
                if url.path == noteURL.path {
                    throw NSError(
                        domain: "WeiBei.ImportedIdentitySelfCheck",
                        code: 72,
                        userInfo: [NSLocalizedDescriptionKey: "injected rename read failure"]
                    )
                }
                return try String(contentsOf: url, encoding: .utf8)
            }
        )
        _ = store.importFiles(
            [materialURL, noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let material = try require(
            store.courseMaterials.first { $0.urlPath == materialURL.path },
            "读取失败场景无法导入资料"
        )
        let note = try require(
            store.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "读取失败场景无法导入笔记"
        )
        store.setLinkedSourceIDs([material.id], for: note.id)
        store.select(itemID: material.id)
        store.renameNotebookNote(itemID: note.id, to: "不应移动的笔记")

        let retained = try require(
            store.courseNotebookItems.first { $0.id == note.id },
            "非活动笔记读取失败后原身份丢失"
        )
        try check(FileManager.default.fileExists(atPath: noteURL.path), "非活动笔记读取失败后原文件消失")
        try check(!FileManager.default.fileExists(atPath: renamedURL.path), "非活动笔记读取失败后仍移动了文件")
        try check(retained.urlPath == noteURL.path, "非活动笔记读取失败后课程状态提前采用了新路径")
        try check(store.linkedSourceIDs(for: note.id) == [material.id], "非活动笔记读取失败后关系图被提前迁移")
        try check(store.noteFileError?.contains("无法重命名") == true, "非活动笔记读取失败后仍显示成功")
    }

    @MainActor
    private static func successfulButIncorrectRenameWriteIsRejected() throws {
        let fixture = try WorkspaceFixture(name: "rename-writer-wrong-content")
        defer { fixture.remove() }

        let noteURL = fixture.importsDirectory.appendingPathComponent("不能被覆盖的笔记.md")
        let renamedURL = fixture.importsDirectory.appendingPathComponent("错误写入不应成功.md")
        let originalMarkdown = "# 不能被覆盖的笔记\n\n用户正文"
        try Data(originalMarkdown.utf8).write(to: noteURL)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            notebookMarkdownWriter: { markdown, url in
                if url.path == renamedURL.path {
                    try "# 陌生正文\n\n不应接管关系".write(to: url, atomically: true, encoding: .utf8)
                } else {
                    try markdown.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        )
        _ = store.importFiles(
            [noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let note = try require(
            store.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "错误写入场景无法导入笔记"
        )
        store.select(itemID: note.id)
        store.renameNotebookNote(itemID: note.id, to: "错误写入不应成功")

        let retained = try require(
            store.courseNotebookItems.first { $0.id == note.id },
            "错误写入后原笔记身份丢失"
        )
        let restoredMarkdown = try String(contentsOf: noteURL, encoding: .utf8)
        let snapshot = try fixture.readSnapshot()
        try check(FileManager.default.fileExists(atPath: noteURL.path), "错误写入返回成功后没有恢复原路径")
        try check(!FileManager.default.fileExists(atPath: renamedURL.path), "错误写入返回成功后仍提交了新路径")
        try check(retained.urlPath == nil, "错误写入返回成功后陌生磁盘内容仍接管原关系")
        try check(restoredMarkdown.contains("陌生正文"), "错误写入返回成功后覆盖或删除了外部磁盘内容")
        try check(snapshot.notesByItemID[note.id] == originalMarkdown, "错误写入返回成功后没有保留魏碑原正文")
        try check(snapshot.pendingNoteWritesByItemID?[note.id] != nil, "错误写入返回成功后没有建立待写保护")
        try check(store.noteFileError?.contains("无法重命名") == true, "错误写入返回成功后仍显示重命名成功")
    }

    @MainActor
    private static func initialRenameMoveFailureLeavesHealthyFileAttached() throws {
        let fixture = try WorkspaceFixture(name: "rename-initial-move-failure")
        defer { fixture.remove() }

        let noteURL = fixture.importsDirectory.appendingPathComponent("移动失败笔记.md")
        let renamedURL = fixture.importsDirectory.appendingPathComponent("不应存在的新路径.md")
        let originalMarkdown = "# 移动失败笔记\n\n仍然健康"
        try Data(originalMarkdown.utf8).write(to: noteURL)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            notebookFileMover: { sourceURL, destinationURL in
                if sourceURL.path == noteURL.path && destinationURL.path == renamedURL.path {
                    throw NSError(
                        domain: "WeiBei.ImportedIdentitySelfCheck",
                        code: 73,
                        userInfo: [NSLocalizedDescriptionKey: "injected initial move failure"]
                    )
                }
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            }
        )
        _ = store.importFiles(
            [noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let note = try require(
            store.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "移动失败场景无法导入笔记"
        )
        store.select(itemID: note.id)
        store.renameNotebookNote(itemID: note.id, to: "不应存在的新路径")

        let retained = try require(
            store.courseNotebookItems.first { $0.id == note.id },
            "首次移动失败后原笔记身份丢失"
        )
        try check(FileManager.default.fileExists(atPath: noteURL.path), "首次移动失败后健康原文件消失")
        try check(!FileManager.default.fileExists(atPath: renamedURL.path), "首次移动失败后产生了新路径")
        try check(retained.urlPath == noteURL.path, "首次移动失败后健康原文件被错误标成不可用")
        try check(retained.importedFileIdentity != nil, "首次移动失败后健康原文件身份丢失")
    }

    @MainActor
    private static func failedWorkspaceSaveRecoversRenameOnRestart() throws {
        let fixture = try WorkspaceFixture(name: "rename-save-recovery")
        defer { fixture.remove() }

        let materialURL = fixture.importsDirectory.appendingPathComponent("恢复关联资料.txt")
        let noteURL = fixture.importsDirectory.appendingPathComponent("崩溃恢复笔记.md")
        let renamedURL = fixture.importsDirectory.appendingPathComponent("已恢复改名.md")
        try Data("恢复关联资料正文".utf8).write(to: materialURL)
        try Data("# 崩溃恢复笔记\n\n恢复正文".utf8).write(to: noteURL)

        var rejectWorkspaceSave = false
        var store: WorkspaceStore? = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            workspaceSnapshotWriter: { data, url in
                let renameJournalExists = FileManager.default.fileExists(
                    atPath: fixture.workspaceDirectory.appendingPathComponent("pending-notebook-rename.json").path
                )
                if rejectWorkspaceSave, renameJournalExists {
                    throw NSError(
                        domain: "WeiBei.ImportedIdentitySelfCheck",
                        code: 74,
                        userInfo: [NSLocalizedDescriptionKey: "injected workspace save failure"]
                    )
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        _ = store?.importFiles(
            [materialURL, noteURL],
            selectsFirstImportedItem: false,
            markdownNotePaths: [noteURL.path]
        )
        let material = try require(
            store?.courseMaterials.first { $0.urlPath == materialURL.path },
            "保存失败恢复场景无法导入资料"
        )
        let note = try require(
            store?.courseNotebookItems.first { $0.urlPath == noteURL.path },
            "保存失败恢复场景无法导入笔记"
        )
        store?.setLinkedSourceIDs([material.id], for: note.id)
        store?.select(itemID: note.id)
        store?.flushPendingNotePersistence()

        rejectWorkspaceSave = true
        store?.renameNotebookNote(itemID: note.id, to: "已恢复改名")
        try check(FileManager.default.fileExists(atPath: renamedURL.path), "课程状态保存失败后真实文件没有完成改名")
        try check(store?.workspaceSaveError != nil, "课程状态保存失败后没有暴露真实错误")
        try check(
            FileManager.default.fileExists(atPath: fixture.workspaceDirectory.appendingPathComponent("pending-notebook-rename.json").path),
            "课程状态保存失败后没有留下重命名恢复记录"
        )

        store = nil
        rejectWorkspaceSave = false
        store = WorkspaceStore(workspaceDirectory: fixture.workspaceDirectory)
        let recovered = try require(
            store?.courseNotebookItems.first { $0.id == note.id },
            "重启后找不到需要恢复的笔记身份"
        )
        let recoveredMarkdown = try String(contentsOf: renamedURL, encoding: .utf8)
        try check(recovered.urlPath == renamedURL.path, "重启后没有从恢复记录接回真实新路径")
        try check(recoveredMarkdown.hasPrefix("# 已恢复改名\n"), "重启后没有保留已写入的新标题")
        try check(store?.linkedSourceIDs(for: note.id) == [material.id], "重启恢复改名后资料关系丢失")
        try check(
            !FileManager.default.fileExists(atPath: fixture.workspaceDirectory.appendingPathComponent("pending-notebook-rename.json").path),
            "重启完成恢复后仍残留重命名恢复记录"
        )
    }

    @MainActor
    private static func duplicateLegacyIdentityMigratesInOneLaunch() throws {
        let fixture = try WorkspaceFixture(name: "duplicate-legacy-single-launch")
        defer { fixture.remove() }

        let firstURL = fixture.importsDirectory.appendingPathComponent("旧路径一.txt")
        let secondURL = fixture.importsDirectory.appendingPathComponent("旧路径二.txt")
        try Data("同一个真实文件".utf8).write(to: firstURL)
        try FileManager.default.linkItem(at: firstURL, to: secondURL)
        let sharedIdentity = ImportedFileIdentity(
            volumeID: 60,
            fileID: 600,
            birthTimeSeconds: 6_000,
            birthTimeNanoseconds: 60
        )
        let firstLegacyID = "file:\(firstURL.path)"
        let secondLegacyID = "file:\(secondURL.path)"
        try fixture.write(
            PersistedWorkspace(
                importedItems: [
                    StudyItem(
                        id: firstLegacyID,
                        title: "旧路径一",
                        subtitle: firstURL.lastPathComponent,
                        kind: .text,
                        urlPath: firstURL.path,
                        isSample: false
                    ),
                    StudyItem(
                        id: secondLegacyID,
                        title: "旧路径二",
                        subtitle: secondURL.lastPathComponent,
                        kind: .text,
                        urlPath: secondURL.path,
                        isSample: false
                    ),
                ],
                selectedItemID: firstLegacyID,
                noteSourceLinksMigrationVersion: 1
            )
        )

        var store: WorkspaceStore? = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { url in
                [firstURL.path, secondURL.path].contains(url.path) ? sharedIdentity : nil
            }
        )
        try check(store?.importedItems.count == 1, "两个同身份旧路径项需要第二次启动才合并")
        let firstLaunchSnapshot = try Data(contentsOf: fixture.workspaceDirectory.appendingPathComponent("workspace.json"))
        store = nil
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { url in
                [firstURL.path, secondURL.path].contains(url.path) ? sharedIdentity : nil
            }
        )
        let secondLaunchSnapshot = try Data(contentsOf: fixture.workspaceDirectory.appendingPathComponent("workspace.json"))
        try check(store?.importedItems.count == 1, "两个同身份旧路径项重启后再次变化")
        try check(firstLaunchSnapshot == secondLaunchSnapshot, "两个同身份旧路径项首次迁移不是幂等结果")
    }

    @MainActor
    private static func replacedAndCrossVolumeFilesReceiveNewIdentities() throws {
        let fixture = try WorkspaceFixture(name: "identity-boundaries")
        defer { fixture.remove() }

        let sourceURL = fixture.importsDirectory.appendingPathComponent("第三讲.txt")
        let copyURL = fixture.importsDirectory.appendingPathComponent("第三讲-副本.txt")
        try Data("第三讲原文件".utf8).write(to: sourceURL)
        try Data("第三讲跨卷副本".utf8).write(to: copyURL)

        let firstIdentity = ImportedFileIdentity(
            volumeID: 10,
            fileID: 99,
            birthTimeSeconds: 1_000,
            birthTimeNanoseconds: 10
        )
        let replacementIdentity = ImportedFileIdentity(
            volumeID: 10,
            fileID: 99,
            birthTimeSeconds: 2_000,
            birthTimeNanoseconds: 20
        )
        let crossVolumeIdentity = ImportedFileIdentity(
            volumeID: 11,
            fileID: 99,
            birthTimeSeconds: 1_000,
            birthTimeNanoseconds: 10
        )
        var identities = [
            sourceURL.path: firstIdentity,
            copyURL.path: crossVolumeIdentity,
        ]
        var store: WorkspaceStore? = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { identities[$0.path] }
        )

        let first = try require(
            store?.importFiles([sourceURL], selectsFirstImportedItem: false).first,
            "首次导入身份边界资料失败"
        )
        store?.select(itemID: first.id)
        try check(store?.studyLocation(for: first.id) != nil, "首次资料没有阅读位置")
        store?.flushPendingNotePersistence()

        try FileManager.default.removeItem(at: sourceURL)
        try Data("第三讲删除后重建".utf8).write(to: sourceURL)
        identities[sourceURL.path] = replacementIdentity
        store = nil
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { identities[$0.path] }
        )
        try check(store?.importedItems.first { $0.id == first.id }?.urlPath == nil, "重启时书签错误接受了世代不同的重建文件")
        let replacement = try require(
            store?.importFiles([sourceURL], selectsFirstImportedItem: false).first,
            "删除重建后重新导入失败"
        )
        try check(replacement.id != first.id, "删除重建的文件错误继承了旧身份")
        try check(store?.studyLocation(for: replacement.id) == nil, "删除重建的文件错误继承了旧阅读位置")
        try check(store?.importedItems.first { $0.id == first.id }?.urlPath == nil, "旧资料仍错误指向删除重建后的文件")

        let crossVolumeCopy = try require(
            store?.importFiles([copyURL], selectsFirstImportedItem: false).first,
            "跨卷副本导入失败"
        )
        try check(crossVolumeCopy.id != first.id, "跨卷副本错误继承了原文件身份")
        try check(crossVolumeCopy.id != replacement.id, "跨卷副本错误继承了重建文件身份")
        let countBeforeDuplicateImport = store?.importedItems.count
        let duplicate = try require(
            store?.importFiles([copyURL], selectsFirstImportedItem: false).first,
            "重复导入跨卷副本失败"
        )
        try check(duplicate.id == crossVolumeCopy.id, "重复导入同一文件产生了新身份")
        try check(store?.importedItems.count == countBeforeDuplicateImport, "重复导入同一文件产生了重复资料")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckError.failed(message) }
        return value
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckError.failed(message) }
    }

    private enum CheckError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            }
        }
    }

    private struct WorkspaceFixture {
        let root: URL
        let workspaceDirectory: URL
        let importsDirectory: URL
        let indexDirectory: URL

        init(name: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("weibei-stable-identity-\(name)-\(UUID().uuidString)", isDirectory: true)
            workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
            importsDirectory = root.appendingPathComponent("Imports", isDirectory: true)
            indexDirectory = root.appendingPathComponent("Index", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        }

        func write(_ snapshot: PersistedWorkspace) throws {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: workspaceDirectory.appendingPathComponent("workspace.json"), options: [.atomic])
        }

        func readSnapshot() throws -> PersistedWorkspace {
            let data = try Data(contentsOf: workspaceDirectory.appendingPathComponent("workspace.json"))
            return try JSONDecoder().decode(PersistedWorkspace.self, from: data)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
