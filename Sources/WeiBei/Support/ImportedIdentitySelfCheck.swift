import Foundation
import WeiBeiCore

enum ImportedIdentitySelfCheck {
    @MainActor
    static func run() throws {
        try legacyPathSnapshotMigratesItsEntireRelationshipGraph()
        try sameVolumeMoveKeepsIdentityRelationsNavigationAndIndex()
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
        try check(store.linkedSourceIDs(for: note.id) == [material.id], "笔记资料关系没有随身份迁移")
        try check(store.studyLocation(for: material.id)?.itemID == material.id, "阅读位置没有随身份迁移")
        try check(Set(store.activeStudySession?.focusItemIDs ?? []) == Set([material.id, note.id]), "学习会话没有随身份迁移")

        let persisted = try fixture.readSnapshot()
        try check(persisted.notesByItemID[note.id] == "遗留缓存笔记", "笔记缓存没有随身份迁移")
        try check(persisted.notesByItemID[legacyNoteID] == nil, "旧路径身份仍残留在笔记缓存")
        try check(persisted.studyLocationsByItemID?[legacyMaterialID] == nil, "旧路径身份仍残留在阅读位置")
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
        store?.select(itemID: firstMaterial.id)
        store?.flushPendingNotePersistence()
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
