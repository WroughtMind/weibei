import Foundation
import WeiBeiCore

/**
 * 验证工作区模型、关系、持久化和附件行为。
 */
enum WorkspaceModelSelfChecks {
    /**
     * 执行该领域的自检。
     */
    static func run(repositoryURL: URL) throws {
        let workspaceStoreSource = SelfCheckSupport.source(
            "Sources/WeiBei/Stores/WorkspaceStore.swift",
            repositoryURL: repositoryURL
        )

        let importedMarkdown = StudyItem(id: "file:/tmp/note.md", title: "note", subtitle: "note.md", kind: .markdown, urlPath: "/tmp/note.md", isSample: false)
        let notebookMarkdown = StudyItem(id: "file:/tmp/notebook.md", title: "notebook", subtitle: "notebook.md", kind: .markdown, urlPath: "/tmp/notebook.md", isSample: false, isNotebookNote: true)
        let sampleMarkdown = StudyItem(id: "sample", title: "sample", subtitle: "sample", kind: .markdown, urlPath: nil, isSample: true)
        expect(importedMarkdown.isImportedMarkdownFile, "imported markdown is readable as material")
        expect(!importedMarkdown.editsBackingMarkdownFile, "imported markdown material does not edit backing file")
        expect(importedMarkdown.canBecomeNotebookNote, "imported markdown can become an editable notebook note")
        expect(notebookMarkdown.editsBackingMarkdownFile, "notebook markdown edits its backing file")
        expect(!notebookMarkdown.canBecomeNotebookNote, "notebook markdown does not offer duplicate conversion")
        expect(!sampleMarkdown.isImportedMarkdownFile, "sample markdown stays app-owned")
        expect(!sampleMarkdown.canBecomeNotebookNote, "sample markdown cannot become a backing-file note")

        let relationNoteID = "note:research"
        let relationNoteB = "note:shared"
        let relationNoteC = "note:replacement"
        let relationSourceA = "file:/tmp/a.pdf"
        let relationSourceB = "file:/tmp/b.html"
        let oldestLink = NoteSourceLink(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            noteItemID: relationNoteID,
            sourceItemID: relationSourceA,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let duplicateLink = NoteSourceLink(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            noteItemID: relationNoteID,
            sourceItemID: relationSourceA,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let sharedSourceLink = NoteSourceLink(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            noteItemID: relationNoteB,
            sourceItemID: relationSourceA,
            createdAt: Date(timeIntervalSince1970: 3)
        )
        let sharedSourceDuplicate = NoteSourceLink(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            noteItemID: relationNoteB,
            sourceItemID: relationSourceA,
            createdAt: Date(timeIntervalSince1970: 4)
        )
        let unrelatedSourceLink = NoteSourceLink(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            noteItemID: relationNoteID,
            sourceItemID: relationSourceB,
            createdAt: Date(timeIntervalSince1970: 5)
        )
        var noteSourceRelations = NoteSourceRelations(links: [duplicateLink, oldestLink])
        expect(noteSourceRelations.links == [oldestLink]
            && noteSourceRelations.sourceIDs(for: relationNoteID) == [relationSourceA], "note-source relations keep one durable pair and preserve the oldest identity")
        noteSourceRelations.replaceSources(for: relationNoteID, sourceItemIDs: [relationSourceB])
        expect(noteSourceRelations.sourceIDs(for: relationNoteID) == [relationSourceB]
            && !noteSourceRelations.isLinked(noteItemID: relationNoteID, sourceItemID: relationSourceA), "explicitly replacing a note's sources removes unlinked material")
        noteSourceRelations.sanitize(validNoteItemIDs: [relationNoteID], validSourceItemIDs: [relationSourceA])
        expect(noteSourceRelations.links.isEmpty, "note-source sanitation removes relationships whose source no longer exists")

        var sharedSourceRelations = NoteSourceRelations(
            links: [unrelatedSourceLink, sharedSourceDuplicate, sharedSourceLink, duplicateLink, oldestLink]
        )
        expect(sharedSourceRelations.links == [oldestLink, sharedSourceLink, unrelatedSourceLink]
            && sharedSourceRelations.noteIDs(for: relationSourceA) == [relationNoteID, relationNoteB], "one source can be shared by multiple notes while duplicate pairs keep their oldest identity")
        sharedSourceRelations.replaceNotes(
            for: relationSourceA,
            noteItemIDs: [relationNoteB, relationNoteC]
        )
        expect(sharedSourceRelations.noteIDs(for: relationSourceA) == [relationNoteB, relationNoteC]
            && sharedSourceRelations.links.contains(sharedSourceLink)
            && sharedSourceRelations.links.contains(unrelatedSourceLink)
            && !sharedSourceRelations.isLinked(noteItemID: relationNoteID, sourceItemID: relationSourceA), "replacing a source's notes preserves retained links and removes only deselected notes")
        let relationIndex = NoteSourceRelationIndex(links: sharedSourceRelations.links)
        expect(relationIndex.sourceIDs(for: relationNoteB) == [relationSourceA]
            && relationIndex.noteIDs(for: relationSourceA) == [relationNoteB, relationNoteC]
            && relationIndex.sourceCount(for: relationNoteID) == 1
            && relationIndex.noteCount(for: relationSourceB) == 1, "relationship index reuses normalized note-to-source and source-to-note lookups")

        let courseMaterials = [
            StudyItem(id: "material:a", title: "第一讲", subtitle: "第一讲.pdf", kind: .pdf, urlPath: "/tmp/course/a.pdf", isSample: false),
            StudyItem(id: "material:b", title: "第二讲", subtitle: "第二讲.html", kind: .html, urlPath: "/tmp/course/b.html", isSample: false),
            StudyItem(id: "material:c", title: "补充材料", subtitle: "补充材料.txt", kind: .text, urlPath: "/tmp/course/c.txt", isSample: false)
        ]
        let courseNotes = [
            StudyItem(id: "note:a", title: "第一讲笔记", subtitle: "第一讲笔记.md", kind: .markdown, urlPath: "/tmp/course/note-a.md", isSample: false, isNotebookNote: true),
            StudyItem(id: "note:b", title: "共同主题", subtitle: "共同主题.md", kind: .markdown, urlPath: "/tmp/course/note-b.md", isSample: false, isNotebookNote: true),
            StudyItem(id: "note:c", title: "待整理", subtitle: "待整理.md", kind: .markdown, urlPath: "/tmp/course/note-c.md", isSample: false, isNotebookNote: true)
        ]
        let builtInSample = StudyItem(id: "sample:ignored", title: "内置样例", subtitle: "样例", kind: .html, urlPath: nil, isSample: true)
        let courseLinks = [
            NoteSourceLink(noteItemID: "note:a", sourceItemID: "material:a", createdAt: Date(timeIntervalSince1970: 10)),
            NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:a", createdAt: Date(timeIntervalSince1970: 11)),
            NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:b", createdAt: Date(timeIntervalSince1970: 12)),
            NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:b", createdAt: Date(timeIntervalSince1970: 13)),
            NoteSourceLink(noteItemID: "note:missing", sourceItemID: "material:c", createdAt: Date(timeIntervalSince1970: 14)),
            NoteSourceLink(noteItemID: "note:a", sourceItemID: "sample:ignored", createdAt: Date(timeIntervalSince1970: 15))
        ]
        let firstCourseSessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let secondCourseSessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let courseSummary = CourseWorkspaceSummary(
            importedItems: courseMaterials + courseNotes + [builtInSample],
            noteSourceLinks: courseLinks,
            studyLocationsByItemID: [
                "material:a": StudyLocation(itemID: "material:a", itemTitle: "第一讲"),
                "material:c": StudyLocation(itemID: "material:c", itemTitle: "补充材料"),
                "material:missing": StudyLocation(itemID: "material:missing", itemTitle: "已移除资料")
            ],
            studySessions: [
                StudySession(
                    id: firstCourseSessionID,
                    title: "第一次学习",
                    messages: [AgentMessage(role: .user, text: "解释第一讲", source: "第一讲")]
                ),
                StudySession(id: secondCourseSessionID, title: "第二次学习")
            ],
            learningMemoryEntries: [
                LearningMemoryEntry(kind: .confusion, text: "困惑一", evidence: "用户提出", origin: .userStatement),
                LearningMemoryEntry(kind: .confusion, text: "困惑二", evidence: "用户提出", origin: .userStatement),
                LearningMemoryEntry(kind: .confusion, text: "已解决困惑", evidence: "用户提出", origin: .userStatement, status: .resolved),
                LearningMemoryEntry(kind: .goal, text: "课程目标", evidence: "用户提出", origin: .userStatement)
            ]
        )
        expect(courseSummary.materialCount == 3
            && courseSummary.noteCount == 3
            && courseSummary.explicitLinkCount == 3
            && courseSummary.readingPositionCount == 2
            && courseSummary.unlinkedMaterialCount == 1
            && courseSummary.unlinkedNoteCount == 1
            && courseSummary.studySessionCount == 1
            && courseSummary.unresolvedConfusionCount == 2, "course workspace summary reports only durable facts from the imported course")

        let courseA = Course(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "货币金融学",
            colorIndex: 0,
            sourceRootPath: "/Courses/Money"
        )
        let courseB = Course(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "经济思想史",
            colorIndex: 1,
            sourceRootPath: "/Courses/History"
        )
        var courseMemberships = CourseItemMemberships()
        courseMemberships.assign(itemIDs: Set(["material-a", "note-a"]), to: courseA.id)
        courseMemberships.assign(itemIDs: Set(["material-a", "material-b"]), to: courseB.id)
        expect(Set(courseMemberships.courseIDs(for: "material-a")) == Set([courseA.id, courseB.id])
            && Set(courseMemberships.itemIDs(in: courseA.id)) == Set(["material-a", "note-a"])
            && Set(courseMemberships.itemIDs(in: courseB.id)) == Set(["material-a", "material-b"]), "one item can belong to multiple real courses without duplicating the item")
        courseMemberships.replaceCourses(for: "note-a", courseIDs: Set([courseB.id]))
        expect(courseMemberships.courseIDs(for: "note-a") == [courseB.id]
            && !courseMemberships.itemIDs(in: courseA.id).contains("note-a"), "changing course membership removes only the replaced item-course pair")

        let persisted = PersistedWorkspace(
            courses: [courseA, courseB],
            courseItemMemberships: courseMemberships.values,
            activeCourseID: courseB.id,
            noteSourceLinks: [oldestLink],
            noteSourceLinksMigrationVersion: 1,
            threePaneOrder: [.agent, .reader, .notes],
            noteRenderMode: .preview,
            showLibrary: false,
            showReader: false,
            showAgent: true,
            showNotes: false,
            showRightPane: true,
            showDailyInspiration: false,
            adaptImportedDocumentColors: false
        )
        let restored = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(persisted))
        expect(restored.showLibrary == false && restored.showReader == false && restored.showAgent == true && restored.showNotes == false && restored.showRightPane == true, "pane visibility state persists")
        expect(restored.courses == [courseA, courseB]
            && restored.courseItemMemberships == courseMemberships.values
            && restored.activeCourseID == courseB.id, "courses, many-to-many membership, and the active course persist together")
        expect(restored.showDailyInspiration == false, "daily inspiration can be disabled and restored from workspace persistence")
        let reenabledInspiration = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(PersistedWorkspace(showDailyInspiration: true)))
        expect(reenabledInspiration.showDailyInspiration == true, "daily inspiration can be re-enabled and restored from workspace persistence")
        let legacyWorkspace = try JSONDecoder().decode(PersistedWorkspace.self, from: Data(#"{"importedItems":[],"notesByItemID":{}}"#.utf8))
        expect(legacyWorkspace.showDailyInspiration == nil
            && legacyWorkspace.courses == nil
            && legacyWorkspace.courseItemMemberships == nil
            && legacyWorkspace.activeCourseID == nil
            && workspaceStoreSource.contains("showDailyInspiration = snapshot.showDailyInspiration ?? true"), "older workspace snapshots remain decodable without inventing a fake course")
        expect(restored.adaptImportedDocumentColors == false
            && workspaceStoreSource.contains("adaptImportedDocumentColors = snapshot.adaptImportedDocumentColors ?? true")
            && workspaceStoreSource.contains("adaptImportedDocumentColors: adaptImportedDocumentColors"), "imported-document color adaptation persists while old workspaces default to adapted reading")
        expect(restored.noteRenderMode == .preview, "legacy preview note mode remains decodable for old workspace snapshots")
        expect(restored.threePaneOrder == [.agent, .reader, .notes], "custom three-pane order persists")
        expect(restored.noteSourceLinks == [oldestLink] && restored.noteSourceLinksMigrationVersion == 1, "note-source relations and one-time migration state persist together")
        expect(workspaceStoreSource.contains("if let noteRenderMode = snapshot.noteRenderMode {\n            self.noteRenderMode = noteRenderMode.visibleMode\n        }")
            && workspaceStoreSource.contains("noteRenderMode = snapshot.noteRenderMode.visibleMode")
            && workspaceStoreSource.contains("let nextMode = mode.visibleMode")
            && !workspaceStoreSource.contains("noteRenderMode == .source ? .source : .rich"), "workspace load and navigation normalize legacy preview mode back to writing")

        let attachmentRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("weibei-self-check-\(UUID().uuidString)", isDirectory: true)
        let attachmentDirectory = attachmentRoot.appendingPathComponent(".weibei-assets", isDirectory: true)
        let dataURL = "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())"
        let firstAttachment = try MarkdownAttachmentStore.save(
            dataURL: dataURL,
            originalName: "图 1).png",
            mime: "image/png",
            attachmentDirectory: attachmentDirectory,
            markdownBaseURLString: attachmentRoot.absoluteString
        )
        expect(firstAttachment.src == ".weibei-assets/图 1).png", "attachment uses relative markdown path")
        expect(firstAttachment.alt == "图 1)", "attachment alt uses safe stem")
        expect(MarkdownAttachmentStore.markdownImage(for: firstAttachment) == "![图 1)](.weibei-assets/图%201%29.png)", "markdown image escapes path")

        let secondAttachment = try MarkdownAttachmentStore.save(
            dataURL: dataURL,
            originalName: "图 1).png",
            mime: "image/png",
            attachmentDirectory: attachmentDirectory,
            markdownBaseURLString: attachmentRoot.absoluteString
        )
        expect(secondAttachment.src == ".weibei-assets/图 1)-2.png", "attachment avoids overwriting duplicate names")
        expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(firstAttachment.src).path), "first attachment written")
        expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(secondAttachment.src).path), "second attachment written")
        let rawAttachment = try MarkdownAttachmentStore.save(
            data: Data([1, 2, 3]),
            originalName: "dragged.webp",
            mime: "",
            attachmentDirectory: attachmentDirectory,
            markdownBaseURLString: attachmentRoot.absoluteString
        )
        expect(rawAttachment.src == ".weibei-assets/dragged.webp", "raw image data save keeps image extension")
        expect(MarkdownAttachmentStore.isSupportedImageExtension("HEIC"), "image extension check is case insensitive")
        expect(MarkdownAttachmentStore.mimeType(forFileExtension: "jpeg") == "image/jpeg", "mime from extension")
        let blockInsert = MarkdownBlockInsertion.insert(
            "![pasted](Attachments/pasted.png)",
            into: "来源：课程 HTML",
            replacing: NSRange(location: ("来源：课程 HTML" as NSString).length, length: 0)
        )
        expect(blockInsert.text == "来源：课程 HTML\n\n![pasted](Attachments/pasted.png)", "block markdown insertion separates from inline text")
        let middleBlockInsert = MarkdownBlockInsertion.insert(
            "![pasted](Attachments/pasted.png)",
            into: "前文后文",
            replacing: NSRange(location: ("前文" as NSString).length, length: 0)
        )
        expect(middleBlockInsert.text == "前文\n\n![pasted](Attachments/pasted.png)\n\n后文", "block markdown insertion separates both sides")
        try? FileManager.default.removeItem(at: attachmentRoot)
    }
}
