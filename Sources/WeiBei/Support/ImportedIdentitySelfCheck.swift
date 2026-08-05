import Foundation
import WeiBeiCore

enum ImportedIdentitySelfCheck {
    @MainActor
    static func run() throws {
        try launchAndPrimaryEntriesStartBlank()
        try storageModelsDecodeLegacySnapshotsAndRoundTrip()
        try legacyPathSnapshotMigratesItsEntireRelationshipGraph()
        try selectionThreadMigrationWaitsForWorkspaceCommit()
        try duplicateIdentityMigrationPreservesConflictingDrafts()
        try duplicateIdentityPreservesConflictingStorageMetadata()
        try offlineLegacyPathMigratesWhenItReturns()
        try legacyChatScopesMigrateOnceAndPersist()
        try failedLearningMemoryMigrationKeepsLegacySnapshotRecoverable()
        try learningMemoryEditsRejectTruncationAndRetrySave()
        try courseResumePointRestoresOneAtomicLearningScene()
        try sameVolumeMoveKeepsIdentityRelationsNavigationAndIndex()
        try temporarilyUnavailableNoteRetainsLatestEdit()
        try offlineLaunchNoteRetainsEditWhenFileReturns()
        try inactiveQueuedDraftBlocksRenameWhenExternalChanged()
        try reentrantNotebookRenameKeepsOneRecoveryTransaction()
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
    private static func launchAndPrimaryEntriesStartBlank() throws {
        let fixture = try WorkspaceFixture(name: "blank-primary-entries")
        defer { fixture.remove() }

        let materialURL = fixture.importsDirectory
            .appendingPathComponent("上次文稿.txt")
        let noteURL = fixture.importsDirectory
            .appendingPathComponent("上次笔记.md")
        try Data("上次打开的文稿".utf8).write(to: materialURL)
        try Data("# 上次打开的笔记".utf8).write(to: noteURL)
        let material = StudyItem(
            id: "launch-material",
            title: "上次文稿",
            subtitle: materialURL.lastPathComponent,
            kind: .text,
            urlPath: materialURL.path,
            isSample: false
        )
        let note = StudyItem(
            id: "launch-note",
            title: "上次笔记",
            subtitle: noteURL.lastPathComponent,
            kind: .markdown,
            urlPath: noteURL.path,
            isSample: false,
            isNotebookNote: true
        )
        let oldChat = StudySession(
            title: "上次会话",
            messages: [
                AgentMessage(
                    role: .user,
                    text: "上次问题",
                    source: nil
                ),
            ]
        )
        try fixture.write(
            PersistedWorkspace(
                importedItems: [material, note],
                selectedItemID: material.id,
                activeNotebookItemID: note.id,
                studySessions: [oldChat],
                activeStudySessionID: oldChat.id,
                workspaceLayout: .documentAgentNotes,
                showReader: true,
                showAgent: true,
                showNotes: true
            )
        )

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults:
                fixture.selectionAskThreadDefaults,
            startsAtBlankEntries: true
        )
        try check(
            store.selectedMaterialItem == nil
                && store.activeNoteItem == nil
                && !store.showReader
                && !store.showAgent
                && !store.showNotes,
            "冷启动恢复了上次具体内容或栏位，没有停在空白入口"
        )
        try check(
            store.activeStudySession?.messages.isEmpty == true
                && store.activeStudySessionID != oldChat.id
                && store.historicalStudySessions.contains {
                    $0.id == oldChat.id
                },
            "冷启动没有创建空白 Chat，或错误删除了旧会话"
        )

        for _ in 0..<6 { store.openReaderEntry() }
        try check(
            store.showReader && store.focusedPane == .reader,
            "连续点击文稿入口把文稿栏反复关闭了"
        )
        for _ in 0..<6 { store.openAgentEntry() }
        try check(
            store.showAgent && store.focusedPane == .agent,
            "连续点击 Chat 入口把会话栏反复关闭了"
        )
        for _ in 0..<6 { store.openNotesEntry() }
        try check(
            store.showNotes && store.focusedPane == .notes,
            "连续点击笔记入口把笔记栏反复关闭了"
        )

        store.openContextualItem(material.id, kind: .material)
        store.openContextualItem(note.id, kind: .note)
        store.showContextualBrowser(.note)
        try check(
            store.activeNoteItem == nil
                && store.selectedMaterialItem?.id == material.id,
            "笔记内容页不能稳定返回笔记列表；note=\(store.activeNoteItem?.id ?? "nil") material=\(store.selectedMaterialItem?.id ?? "nil")"
        )
        store.openContextualItem(note.id, kind: .note)
        store.showContextualBrowser(.material)
        try check(
            store.selectedMaterialItem == nil
                && store.activeNoteItem?.id == note.id,
            "文稿内容页不能稳定返回文稿列表"
        )
    }

    @MainActor
    private static func reentrantNotebookRenameKeepsOneRecoveryTransaction()
        throws {
        let fixture = try WorkspaceFixture(name: "reentrant-note-rename")
        defer { fixture.remove() }

        let noteURL = fixture.importsDirectory
            .appendingPathComponent("并发重命名笔记.md")
        try Data("# 并发重命名笔记\n\n正文".utf8).write(to: noteURL)
        let note = StudyItem(
            id: "reentrant-note-rename",
            title: "并发重命名笔记",
            subtitle: noteURL.lastPathComponent,
            kind: .markdown,
            urlPath: noteURL.path,
            isSample: false,
            isNotebookNote: true
        )
        try fixture.write(
            PersistedWorkspace(
                importedItems: [note],
                activeNotebookItemID: note.id
            )
        )
        var store: WorkspaceStore?
        let noteID = note.id
        var moveCount = 0
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            notebookFileMover: { source, target in
                moveCount += 1
                if moveCount == 1 {
                    store?.renameNotebookNote(
                        itemID: noteID,
                        to: "第二个重命名不应进入"
                    )
                }
                try FileManager.default.moveItem(
                    at: source,
                    to: target
                )
            },
            selectionAskThreadDefaults:
                fixture.selectionAskThreadDefaults
        )

        store?.renameNotebookNote(
            itemID: note.id,
            to: "唯一完成的重命名"
        )
        try check(
            moveCount == 1,
            "连续确认启动了多个笔记重命名事务；移动次数=\(moveCount)，错误=\(store?.noteFileError ?? "nil")"
        )
        try check(
            store?.courseNotebookItems.first(where: {
                $0.id == note.id
            })?.urlPath?.hasSuffix("唯一完成的重命名.md") == true,
            "笔记重命名串行守卫没有保留唯一事务结果"
        )
    }

    @MainActor
    private static func courseResumePointRestoresOneAtomicLearningScene() throws {
        let fixture = try WorkspaceFixture(name: "course-resume-point")
        defer { fixture.remove() }

        let materialURL = fixture.importsDirectory.appendingPathComponent("shared.html")
        let noteURL = fixture.importsDirectory.appendingPathComponent("course-a-note.md")
        let otherMaterialURL = fixture.importsDirectory.appendingPathComponent("course-b.txt")
        let otherNoteURL = fixture.importsDirectory.appendingPathComponent("course-b-note.md")
        try Data("<h1 id=\"a\">A</h1><h1 id=\"b\">B</h1>".utf8).write(to: materialURL)
        try Data("# 课程 A 笔记".utf8).write(to: noteURL)
        try Data("课程 B 文稿".utf8).write(to: otherMaterialURL)
        try Data("# 课程 B 笔记".utf8).write(to: otherNoteURL)
        let materialIdentity = ImportedFileIdentity(
            volumeID: 80,
            fileID: 801,
            birthTimeSeconds: 8_001,
            birthTimeNanoseconds: 81
        )
        let noteIdentity = ImportedFileIdentity(
            volumeID: 80,
            fileID: 802,
            birthTimeSeconds: 8_002,
            birthTimeNanoseconds: 82
        )
        let libraryIdentity = ImportedFileIdentity(
            volumeID: 80,
            fileID: 800,
            birthTimeSeconds: 8_000,
            birthTimeNanoseconds: 80
        )
        let otherMaterialIdentity = ImportedFileIdentity(
            volumeID: 80,
            fileID: 803,
            birthTimeSeconds: 8_003,
            birthTimeNanoseconds: 83
        )
        let otherNoteIdentity = ImportedFileIdentity(
            volumeID: 80,
            fileID: 804,
            birthTimeSeconds: 8_004,
            birthTimeNanoseconds: 84
        )
        let courseA = Course(id: UUID(), title: "课程 A")
        let courseB = Course(id: UUID(), title: "课程 B")
        let chatOnlyCourse = Course(id: UUID(), title: "仅对话课程")
        let materialOnlyCourse = Course(id: UUID(), title: "仅文稿课程")
        let material = StudyItem(
            id: "resume-shared-material",
            title: "共享文稿",
            subtitle: materialURL.lastPathComponent,
            kind: .html,
            urlPath: materialURL.path,
            importedFileIdentity: materialIdentity,
            isSample: false,
            storage: .shared(sharedRelativePath: "shared.html")
        )
        let note = StudyItem(
            id: "resume-course-a-note",
            title: "课程 A 笔记",
            subtitle: noteURL.lastPathComponent,
            kind: .markdown,
            urlPath: noteURL.path,
            importedFileIdentity: noteIdentity,
            isSample: false,
            isNotebookNote: true
        )
        let otherMaterial = StudyItem(
            id: "resume-course-b-material",
            title: "课程 B 文稿",
            subtitle: otherMaterialURL.lastPathComponent,
            kind: .text,
            urlPath: otherMaterialURL.path,
            importedFileIdentity: otherMaterialIdentity,
            isSample: false
        )
        let otherNote = StudyItem(
            id: "resume-course-b-note",
            title: "课程 B 笔记",
            subtitle: otherNoteURL.lastPathComponent,
            kind: .markdown,
            urlPath: otherNoteURL.path,
            importedFileIdentity: otherNoteIdentity,
            isSample: false,
            isNotebookNote: true
        )
        let chatA1 = StudySession(
            id: UUID(),
            title: "课程 A Chat 1",
            messages: [AgentMessage(role: .user, text: "A1", source: nil)],
            courseID: courseA.id
        )
        let chatA2 = StudySession(
            id: UUID(),
            title: "课程 A Chat 2",
            messages: [AgentMessage(role: .user, text: "A2", source: nil)],
            courseID: courseA.id
        )
        let chatB = StudySession(
            id: UUID(),
            title: "课程 B Chat",
            messages: [AgentMessage(role: .user, text: "B", source: nil)],
            courseID: courseB.id
        )
        let chatOnly = StudySession(
            id: UUID(),
            title: "仅对话 Chat",
            messages: [AgentMessage(role: .user, text: "只聊课程", source: nil)],
            courseID: chatOnlyCourse.id
        )
        try fixture.write(
            PersistedWorkspace(
                importedItems: [material, note, otherMaterial, otherNote],
                courses: [courseA, courseB, chatOnlyCourse, materialOnlyCourse],
                courseItemMemberships: [
                    CourseItemMembership(courseID: courseA.id, itemID: material.id),
                    CourseItemMembership(courseID: courseB.id, itemID: material.id),
                    CourseItemMembership(courseID: materialOnlyCourse.id, itemID: material.id),
                    CourseItemMembership(courseID: courseA.id, itemID: note.id),
                    CourseItemMembership(courseID: courseB.id, itemID: otherMaterial.id),
                    CourseItemMembership(courseID: courseB.id, itemID: otherNote.id),
                ],
                activeCourseID: courseB.id,
                courseLibraryRootPath: fixture.importsDirectory.path,
                courseLibraryRootIdentity: libraryIdentity,
                courseLibraryRootBookmarkData: Data("library-root".utf8),
                studySessions: [chatA1, chatA2, chatB, chatOnly],
                studySessionScopeMigrationVersion: 1,
                activeStudySessionID: chatB.id
            )
        )

        func makeStore(
            workspaceSnapshotWriter: @escaping (Data, URL) throws -> Void = {
                try $0.write(to: $1, options: [.atomic])
            }
        ) -> WorkspaceStore {
            WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { url in
                    switch url.path {
                    case materialURL.path: materialIdentity
                    case noteURL.path: noteIdentity
                    case otherMaterialURL.path: otherMaterialIdentity
                    case otherNoteURL.path: otherNoteIdentity
                    case fixture.importsDirectory.path: libraryIdentity
                    default: nil
                    }
                },
                courseRootBookmarkResolver: { _ in
                    CourseProjectResolvedBookmark(
                        url: fixture.importsDirectory,
                        isStale: false
                    )
                },
                courseSecurityScopeStarter: { _ in true },
                courseSecurityScopeStopper: { _ in },
                workspaceSnapshotWriter: workspaceSnapshotWriter,
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
        }

        let store = makeStore()
        store.activateCourse(courseA.id)
        try check(store.openCourseMaterial(material.id), "课程 A 无法打开共享文稿")
        store.updateReaderHTMLLocation(id: "section-a", title: "A 段", reason: "scroll")
        store.openCourseNote(note.id)
        try check(
            store.activateStudySession(
                chatA2.id,
                expectedCourseID: courseA.id,
                expectedScopeNeedsReview: false
            ),
            "课程 A 无法切到指定 Chat"
        )
        store.setLayout(.immersiveReading)
        store.updateReaderHTMLLocation(
            id: "section-a-deep",
            title: "A 深读段",
            reason: "scroll"
        )
        store.setLayout(.immersiveConversation)
        let captureStartedAt = Date()
        try check(
            store.activateStudySession(
                chatA1.id,
                expectedCourseID: courseA.id,
                expectedScopeNeedsReview: false
            )
                && store.activateStudySession(
                    chatA2.id,
                    expectedCourseID: courseA.id,
                    expectedScopeNeedsReview: false
            ),
            "沉浸对话无法切换并返回原 Chat"
        )
        let captureFinishedAt = Date()
        let pointA = try require(
            store.courseResumePoint(for: courseA.id),
            "课程 A 没有保存学习现场"
        )
        try check(
            pointA.materialLocation?.locationID == "section-a-deep"
                && pointA.chatID == chatA2.id
                && pointA.noteItemID == note.id
                && pointA.savedAt >= captureStartedAt
                && pointA.savedAt <= captureFinishedAt,
            "沉浸阅读更新位置时丢掉了同一现场的精确 Chat 或笔记"
        )

        store.activateCourse(courseB.id)
        try check(store.openCourseMaterial(material.id), "课程 B 无法打开共享文稿")
        try check(
            store.courseResumePoint(for: courseB.id)?.materialLocation?.locationID == nil
                && store.readerLocationID == nil,
            "课程 B 首次打开共享文稿时继承了课程 A 的位置"
        )
        store.updateReaderHTMLLocation(id: "section-b", title: "B 段", reason: "scroll")
        try check(
            store.activateStudySession(
                chatB.id,
                expectedCourseID: courseB.id,
                expectedScopeNeedsReview: false
            ),
            "课程 B 无法切到自己的 Chat"
        )
        let pointB = try require(
            store.courseResumePoint(for: courseB.id),
            "课程 B 没有保存学习现场"
        )
        try check(
            pointB.materialLocation?.locationID == "section-b"
                && pointB.chatID == chatB.id
                && pointB.noteItemID == nil,
            "共享文稿的课程 B 位置或 Chat 串进了课程 A"
        )
        try check(
            store.courseResumePoint(for: courseA.id)?.materialLocation?.locationID == "section-a-deep",
            "课程 B 的共享文稿位置覆盖了课程 A 的恢复位置"
        )

        try check(store.flushPendingWorkspaceSave(), "课程学习现场无法写入磁盘")
        let reopened = makeStore()
        try check(
            reopened.courseResumePoint(for: courseA.id) == pointA
                && reopened.courseResumePoint(for: courseB.id) == pointB,
            "重开后课程学习现场不一致"
        )
        let rollbackStore = makeStore { _, _ in
            throw CheckError.failed("预期中的课程关系保存失败")
        }
        try check(
            rollbackStore.courseResumePointSurvivesFailedMembershipSaveForSelfCheck(
                itemID: material.id,
                courseID: courseA.id
            ),
            "课程关系保存失败并回滚后，恢复点没有一起保留"
        )
        let committedRemovalStore = makeStore()
        try check(
            committedRemovalStore
                .courseResumePointDoesNotReviveAfterSuccessfulMembershipSaveForSelfCheck(
                    itemID: material.id,
                    courseID: courseA.id
                ),
            "课程关系成功移除后，同进程重新加入错误复活了旧恢复位置"
        )
        let sessionCountBeforeReading = reopened.studySessions.count
        reopened.activateCourse(courseB.id)
        try check(reopened.openCourseMaterial(otherMaterial.id), "无法准备课程 B 的对照文稿")
        reopened.openCourseNote(otherNote.id)
        reopened.setLayout(.documentAgentNotes)
        reopened.swapThreePaneSecondaryPanes()
        let paneOrderBeforeReading = reopened.threePaneOrder
        reopened.presentCourseWorkspace(.hub, courseID: courseA.id)
        let chatBBeforeReading = try require(
            reopened.studySessions.first { $0.id == chatB.id },
            "重开后课程 B Chat 丢失"
        )
        try check(
            reopened.resumeCourseReading(courseA.id)
                && reopened.activeStudySessionID == chatB.id
                && reopened.selectedMaterialItem?.id == material.id
                && reopened.readerLocationID == "section-a-deep"
                && reopened.activeNotebookItemID == note.id
                && reopened.studySessions.first(where: { $0.id == chatB.id }) == chatBBeforeReading
                && reopened.studySessions.count == sessionCountBeforeReading
                && reopened.threePaneOrder == paneOrderBeforeReading
                && reopened.focusedPane == .reader
                && reopened.showReader
                && reopened.showAgent
                && reopened.showNotes
                && reopened.layout.isDocumentThreePane
                && !reopened.courseWorkspacePresented,
            "继续阅读切换或改写了当前 Chat，或没有原样恢复课程 A 的位置、笔记和栏位顺序"
        )
        reopened.updateReaderHTMLLocation(
            id: "section-a-resumed",
            title: "A 继续阅读",
            reason: "scroll"
        )
        try check(
            reopened.courseResumePoint(for: courseA.id)?.chatID == chatA2.id
                && reopened.courseResumePoint(for: courseA.id)?.noteItemID == note.id,
            "继续阅读后滚动时丢掉了原课程 Chat 或笔记"
        )
        reopened.activateCourse(courseB.id)
        try check(
            reopened.openCourseMaterial(otherMaterial.id, in: courseB.id),
            "无法准备继续对话前的课程 B 文稿现场"
        )
        reopened.updateReaderHTMLLocation(
            id: "section-b-current",
            title: "B 当前阅读",
            reason: "scroll"
        )
        reopened.openCourseNote(otherNote.id, in: courseB.id)
        let materialBeforeConversation = reopened.selectedMaterialItem?.id
        let locationBeforeConversation = reopened.readerLocationID
        let noteBeforeConversation = reopened.activeNotebookItemID
        reopened.presentCourseWorkspace(.hub, courseID: courseA.id)
        try check(
            reopened.resumeCourseConversation(courseA.id)
                && reopened.activeStudySessionID == chatA2.id
                && reopened.selectedMaterialItem?.id == materialBeforeConversation
                && reopened.readerLocationID == locationBeforeConversation
                && reopened.activeNotebookItemID == noteBeforeConversation
                && reopened.layout.isDocumentThreePane
                && reopened.focusedPane == .agent
                && reopened.showReader
                && reopened.showAgent
                && reopened.showNotes
                && reopened.studySessions.count == sessionCountBeforeReading,
            "继续对话没有恢复精确 Chat，或覆盖了当前文稿、阅读位置和笔记现场"
        )
        try check(
            reopened.activateStudySession(
                chatOnly.id,
                expectedCourseID: chatOnlyCourse.id,
                expectedScopeNeedsReview: false
            ),
            "无法准备仅有 Chat 的课程现场"
        )
        reopened.presentCourseWorkspace(.hub, courseID: chatOnlyCourse.id)
        try check(
            reopened.courseResumePoint(for: chatOnlyCourse.id)?.materialLocation == nil
                && reopened.courseResumePoint(for: chatOnlyCourse.id)?.noteItemID == nil
                && reopened.resumeCourseConversation(chatOnlyCourse.id)
                && reopened.activeStudySessionID == chatOnly.id
                && !reopened.courseWorkspacePresented,
            "仅有 Chat 的课程不能恢复对话"
        )
        reopened.activateCourse(materialOnlyCourse.id)
        try check(
            reopened.openCourseMaterial(material.id),
            "无法准备仅有文稿的课程现场"
        )
        reopened.updateReaderHTMLLocation(
            id: "section-material-only",
            title: "仅文稿位置",
            reason: "scroll"
        )
        reopened.presentCourseWorkspace(.hub, courseID: materialOnlyCourse.id)
        try check(
            reopened.courseResumePoint(for: materialOnlyCourse.id)?.chatID == nil
                && reopened.courseResumePoint(for: materialOnlyCourse.id)?.noteItemID == nil
                && reopened.resumeCourseReading(materialOnlyCourse.id)
                && reopened.readerLocationID == "section-material-only"
                && !reopened.courseWorkspacePresented,
            "仅有文稿的课程不能恢复阅读"
        )
        try check(
            reopened.activateStudySession(
                chatA2.id,
                expectedCourseID: courseA.id,
                expectedScopeNeedsReview: false
            ),
            "可选状态检查后无法返回课程 A Chat"
        )
        try FileManager.default.removeItem(at: materialURL)
        reopened.presentCourseWorkspace(.hub, courseID: courseA.id)
        try check(
            !reopened.resumeCourseReading(courseA.id)
                && reopened.courseWorkspacePresented
                && reopened.courseResumePoint(for: courseA.id)?.materialLocation != nil,
            "文稿暂不可用时没有留在课程首页，或错误丢掉了恢复位置"
        )
        try check(
            reopened.resumeCourseConversation(courseA.id)
                && !reopened.courseWorkspacePresented
                && reopened.activeStudySessionID == chatA2.id
                && reopened.courseResumePoint(for: courseA.id)?.materialLocation != nil,
            "文稿暂不可用时不应阻止恢复同一课程 Chat"
        )

        reopened.deleteStudySession(chatA2.id)
        try check(
            reopened.courseResumePoint(for: courseA.id)?.chatID == nil
                && reopened.courseResumePoint(for: courseA.id)?.materialLocation != nil
                && reopened.courseResumePoint(for: courseA.id)?.noteItemID == note.id,
            "删除 Chat 时错误丢掉了仍有效的文稿或笔记现场"
        )
        reopened.setCourseIDs([], for: note.id)
        try check(
            reopened.courseResumePoint(for: courseA.id)?.noteItemID == nil
                && reopened.courseResumePoint(for: courseA.id)?.materialLocation != nil,
            "移出课程的笔记没有单独从学习现场清掉"
        )
        try check(reopened.flushPendingWorkspaceSave(), "移除课程资料前无法保存现场")
        var membershipSnapshot = try fixture.readSnapshot()
        membershipSnapshot.courseItemMemberships?.removeAll {
            $0.courseID == courseA.id && $0.itemID == material.id
        }
        try fixture.write(membershipSnapshot)
        let degraded = makeStore()
        try check(
            degraded.courseResumePoint(for: courseA.id) == nil
                && degraded.courseResumePoint(for: courseB.id) != nil,
            "课程 A 的无效现场没有清理，或误删了课程 B 的现场"
        )
        degraded.removeCourseRegistrationImmediatelyForSelfCheck(
            courseB.id
        )
        try check(
            degraded.courseResumePoint(for: courseB.id) == nil,
            "删除课程后仍残留课程学习现场"
        )
    }

    @MainActor
    private static func failedLearningMemoryMigrationKeepsLegacySnapshotRecoverable() throws {
        let fixture = try WorkspaceFixture(name: "learning-memory-migration-failure")
        defer { fixture.remove() }

        let course = Course(id: UUID(), title: "迁移恢复课程")
        let session = StudySession(
            id: UUID(),
            title: "迁移恢复 Chat",
            courseID: course.id,
            scopeNeedsReview: false
        )
        let memory = LearningMemoryEntry(
            kind: .confusion,
            text: "迁移失败后仍要保留",
            evidence: "旧工作区",
            origin: .agentInference,
            sessionID: session.id
        )
        try fixture.write(
            PersistedWorkspace(
                courses: [course],
                learningMemoryEntries: [memory],
                learningMemoryRevision: 3,
                studySessions: [session],
                studySessionScopeMigrationVersion: 1,
                activeStudySessionID: session.id
            )
        )

        let failedStore = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            workspaceSnapshotWriter: { _, _ in
                throw CheckError.failed("预期中的迁移保存失败")
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        try check(
            failedStore.learningMemoryEntries(in: .course(course.id)).map(\.id) == [memory.id],
            "保存失败时内存中的旧记忆无法继续使用"
        )
        let unchangedSnapshot = try fixture.readSnapshot()
        try check(
            unchangedSnapshot.learningMemoryEntries?.map(\.id) == [memory.id]
                && unchangedSnapshot.learningMemoryStates == nil
                && unchangedSnapshot.learningMemoryScopeMigrationVersion == nil,
            "迁移保存失败破坏了旧工作区快照"
        )

        let recoveredStore = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        try check(
            recoveredStore.flushPendingWorkspaceSave()
                && recoveredStore.learningMemoryEntries(in: .course(course.id)).map(\.id) == [memory.id]
                && recoveredStore.learningMemoryRevision(in: .course(course.id)) == 1,
            "保存恢复后旧记忆无法安全重试迁移"
        )
    }

    @MainActor
    private static func learningMemoryEditsRejectTruncationAndRetrySave() throws {
        let fixture = try WorkspaceFixture(name: "learning-memory-edit-save")
        defer { fixture.remove() }

        let memory = LearningMemoryEntry(
            kind: .confusion,
            text: "旧内容",
            evidence: "旧工作区",
            origin: .agentInference
        )
        try fixture.write(
            PersistedWorkspace(
                learningMemoryStates: [
                    ScopedLearningMemoryState(
                        scope: .global,
                        revision: 1,
                        entries: [memory]
                    ),
                ],
                learningMemoryScopeMigrationVersion: 1
            )
        )

        var shouldFail = true
        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            workspaceSnapshotWriter: { data, url in
                if shouldFail {
                    throw CheckError.failed("预期中的学习记忆保存失败")
                }
                try data.write(to: url, options: [.atomic])
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        let overlong = String(repeating: "字", count: 501)
        try check(
            !store.updateLearningMemory(
                memory.id,
                in: .global,
                kind: .progress,
                text: overlong
            )
                && store.learningMemoryEntries(in: .global).first?.text == memory.text,
            "用户学习记忆超过 500 字时被静默截断"
        )

        let editedText = "已完成第一轮复习"
        try check(
            !store.updateLearningMemory(
                memory.id,
                in: .global,
                kind: .progress,
                text: editedText
            )
                && store.workspaceSaveError != nil,
            "学习记忆写盘失败却返回成功"
        )
        let snapshotAfterFailure = try fixture.readSnapshot()
        try check(
            snapshotAfterFailure.learningMemoryStates?.first?.entries.first?.text == memory.text,
            "学习记忆保存失败破坏了旧快照"
        )

        shouldFail = false
        try check(
            store.updateLearningMemory(
                memory.id,
                in: .global,
                kind: .progress,
                text: editedText
            ),
            "同内容重试没有重新写入学习记忆"
        )
        let snapshotAfterRetry = try fixture.readSnapshot()
        try check(
            snapshotAfterRetry.learningMemoryStates?.first?.entries.first?.text == editedText,
            "学习记忆重试成功后没有落盘"
        )
    }

    @MainActor
    private static func legacyChatScopesMigrateOnceAndPersist() throws {
        let fixture = try WorkspaceFixture(name: "legacy-chat-scope")
        defer { fixture.remove() }

        let courseA = Course(id: UUID(), title: "课程 A")
        let courseB = Course(id: UUID(), title: "课程 B")
        let uniqueItem = StudyItem(
            id: "legacy-chat-unique",
            title: "课程 A 文稿",
            subtitle: "a.txt",
            kind: .text,
            urlPath: nil,
            isSample: false
        )
        let sharedItem = StudyItem(
            id: "legacy-chat-shared",
            title: "共享文稿",
            subtitle: "shared.txt",
            kind: .text,
            urlPath: nil,
            isSample: false
        )
        let uniqueCourseBItem = StudyItem(
            id: "legacy-chat-unique-b",
            title: "课程 B 文稿",
            subtitle: "b.txt",
            kind: .text,
            urlPath: nil,
            isSample: false
        )
        let orphanItem = StudyItem(
            id: "legacy-chat-orphan",
            title: "未归类文稿",
            subtitle: "orphan.txt",
            kind: .text,
            urlPath: nil,
            isSample: false
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let uniqueSession = StudySession(
            id: UUID(),
            title: "只属于课程 A",
            messages: [
                AgentMessage(
                    role: .user,
                    text: "解释课程 A",
                    source: nil,
                    createdAt: createdAt
                )
            ],
            focusItemIDs: [uniqueItem.id],
            materialItemID: uniqueItem.id,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let sharedSession = StudySession(
            id: UUID(),
            title: "共享文稿对话",
            messages: [AgentMessage(role: .user, text: "这份共享文稿讲什么", source: nil)],
            focusItemIDs: [sharedItem.id],
            materialItemID: sharedItem.id
        )
        let courseBSession = StudySession(
            id: UUID(),
            title: "只属于课程 B",
            messages: [AgentMessage(role: .user, text: "解释课程 B", source: nil)],
            focusItemIDs: [uniqueCourseBItem.id],
            materialItemID: uniqueCourseBItem.id
        )
        let orphanSession = StudySession(
            id: UUID(),
            title: "没有课程证据",
            messages: [AgentMessage(role: .user, text: "继续", source: nil)],
            focusItemIDs: [orphanItem.id],
            materialItemID: orphanItem.id
        )
        let blankSession = StudySession(id: UUID(), title: "新学习会话")
        let courseLearningMemory = LearningMemoryEntry(
            kind: .nextStep,
            text: "继续完成课程 A 的复习",
            evidence: "当前 Chat 中的学习建议",
            origin: .agentInference,
            sessionID: uniqueSession.id
        )
        let ambiguousLearningMemory = LearningMemoryEntry(
            kind: .confusion,
            text: "共享文稿属于哪门课还不明确",
            evidence: "共享文稿 Chat",
            origin: .userStatement,
            sessionID: sharedSession.id
        )
        let orphanLearningMemory = LearningMemoryEntry(
            kind: .goal,
            text: "先保留无法归类的学习目标",
            evidence: "旧 Chat 已经不存在",
            origin: .agentInference,
            sessionID: UUID()
        )
        let courseBLearningMemory = LearningMemoryEntry(
            kind: .understood,
            text: "已经理解课程 B 的第一章",
            evidence: "课程 B Chat",
            origin: .agentInference,
            sessionID: courseBSession.id
        )
        let snapshot = PersistedWorkspace(
            importedItems: [uniqueItem, sharedItem, uniqueCourseBItem, orphanItem],
            selectedItemID: uniqueItem.id,
            courses: [courseA, courseB],
            courseItemMemberships: [
                CourseItemMembership(courseID: courseA.id, itemID: uniqueItem.id),
                CourseItemMembership(courseID: courseA.id, itemID: sharedItem.id),
                CourseItemMembership(courseID: courseB.id, itemID: sharedItem.id),
                CourseItemMembership(courseID: courseB.id, itemID: uniqueCourseBItem.id),
            ],
            activeCourseID: courseB.id,
            learningMemoryEntries: [
                courseLearningMemory,
                courseBLearningMemory,
                ambiguousLearningMemory,
                orphanLearningMemory,
            ],
            learningMemoryRevision: 7,
            studySessions: [
                uniqueSession,
                courseBSession,
                sharedSession,
                orphanSession,
                blankSession,
            ],
            activeStudySessionID: uniqueSession.id
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var legacyObject = try require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any],
            "无法建立旧 Chat 迁移样本"
        )
        var legacySessions = try require(
            legacyObject["studySessions"] as? [[String: Any]],
            "旧 Chat 迁移样本缺少会话"
        )
        for index in legacySessions.indices {
            legacySessions[index].removeValue(forKey: "relatedCourseIDs")
            legacySessions[index].removeValue(forKey: "courseID")
            legacySessions[index].removeValue(forKey: "scopeNeedsReview")
        }
        legacyObject["studySessions"] = legacySessions
        legacyObject.removeValue(forKey: "studySessionScopeMigrationVersion")
        try JSONSerialization.data(withJSONObject: legacyObject)
            .write(
                to: fixture.workspaceDirectory.appendingPathComponent("workspace.json"),
                options: [.atomic]
            )

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        let migratedUnique = try require(
            store.studySessions.first { $0.id == uniqueSession.id },
            "唯一课程旧 Chat 在迁移时丢失"
        )
        let migratedShared = try require(
            store.studySessions.first { $0.id == sharedSession.id },
            "共享文稿旧 Chat 在迁移时丢失"
        )
        let migratedOrphan = try require(
            store.studySessions.first { $0.id == orphanSession.id },
            "无归属旧 Chat 在迁移时丢失"
        )
        let migratedBlank = try require(
            store.studySessions.first { $0.id == blankSession.id },
            "空白旧 Chat 在迁移时丢失"
        )
        try check(
            migratedUnique.relatedCourseIDs == [courseA.id],
            "唯一课程旧 Chat 没有迁入唯一课程"
        )
        try check(
            Set(migratedShared.relatedCourseIDs) == Set([courseA.id, courseB.id]),
            "共享文稿旧 Chat 没有同时关联真实相关课程"
        )
        try check(
            migratedOrphan.relatedCourseIDs.isEmpty,
            "无课程证据的旧 Chat 被猜测关联"
        )
        try check(
            migratedBlank.relatedCourseIDs.isEmpty,
            "无内容空白旧 Chat 不应关联课程"
        )
        try check(migratedUnique.title == uniqueSession.title, "旧 Chat 迁移改变了标题")
        try check(migratedUnique.messages == uniqueSession.messages, "旧 Chat 迁移改变了消息")
        try check(migratedUnique.createdAt == createdAt, "旧 Chat 迁移改变了创建时间")
        try check(migratedUnique.updatedAt == updatedAt, "旧 Chat 迁移改变了更新时间")
        try check(
            Set(store.sessionsTouchingCourse(courseA.id).map(\.id))
                == Set([uniqueSession.id, sharedSession.id])
                && Set(store.sessionsTouchingCourse(courseB.id).map(\.id))
                    == Set([courseBSession.id, sharedSession.id]),
            "课程记录没有按旧 Chat 的真实资料证据恢复多课程关联"
        )
        let courseMemories = store.learningMemoryEntries(in: .course(courseA.id))
        let courseBMemories = store.learningMemoryEntries(in: .course(courseB.id))
        let globalMemories = store.learningMemoryEntries(in: .global)
        try check(
            courseMemories.map(\.id) == [courseLearningMemory.id],
            "唯一课程旧记忆没有迁入来源 Chat 的课程"
        )
        try check(
            courseBMemories.map(\.id) == [courseBLearningMemory.id],
            "课程 B 旧记忆没有保持独立作用域"
        )
        try check(
            Set(globalMemories.map(\.id)) == Set([
                ambiguousLearningMemory.id,
                orphanLearningMemory.id,
            ]),
            "共享、待归类或孤儿旧记忆没有保留为全局记忆"
        )
        try check(
            Set((courseMemories + courseBMemories + globalMemories).map(\.id)).count == 4
                && (courseMemories + courseBMemories + globalMemories).allSatisfy {
                    $0.revisions?.first?.actor == .migration
                },
            "旧记忆迁移复制了稳定 ID，或没有留下迁移历史"
        )
        try check(store.flushPendingWorkspaceSave(), "旧 Chat 迁移结果无法保存")
        let migratedSnapshot = try fixture.readSnapshot()
        try check(
            migratedSnapshot.studySessionScopeMigrationVersion == 2
                && migratedSnapshot.learningMemoryScopeMigrationVersion == 1
                && migratedSnapshot.learningMemoryStates?.count == 3
                && migratedSnapshot.learningMemoryEntries == nil
                && migratedSnapshot.learningMemoryRevision == nil,
            "旧 Chat 或旧记忆迁移没有写入可重复识别的新格式"
        )

        let reopened = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        try check(
            reopened.studySessions == store.studySessions,
            "重开工作区后旧 Chat 迁移结果发生二次漂移"
        )
        try check(
            reopened.learningMemoryStates == store.learningMemoryStates,
            "重开工作区后旧记忆迁移发生重复或作用域漂移"
        )
        let globalRevisionBeforeCourseEdit = reopened.learningMemoryRevision(in: .global)
        let courseBRevisionBeforeCourseEdit = reopened.learningMemoryRevision(in: .course(courseB.id))
        let courseRevisionBeforeEdit = reopened.learningMemoryRevision(in: .course(courseA.id))
        try check(
            reopened.updateLearningMemory(
                courseLearningMemory.id,
                in: .course(courseA.id),
                kind: .understood,
                text: "已经完成课程 A 的第一轮复习"
            ),
            "用户无法修改课程记忆"
        )
        let editedCourseMemory = try require(
            reopened.learningMemoryEntries(in: .course(courseA.id))
                .first { $0.id == courseLearningMemory.id },
            "用户修改课程记忆后稳定 ID 丢失"
        )
        try check(
            editedCourseMemory.kind == .understood
                && editedCourseMemory.text == "已经完成课程 A 的第一轮复习"
                && editedCourseMemory.revisions?.last?.actor == .user
                && reopened.learningMemoryRevision(in: .course(courseA.id)) == courseRevisionBeforeEdit + 1
                && reopened.learningMemoryRevision(in: .course(courseB.id)) == courseBRevisionBeforeCourseEdit
                && reopened.learningMemoryRevision(in: .global) == globalRevisionBeforeCourseEdit,
            "用户修改没有追加历史，或错误推进了其他作用域修订号"
        )
        try check(
            reopened.activateStudySession(
                uniqueSession.id,
                expectedCourseID: courseA.id,
                expectedScopeNeedsReview: false
            ),
            "无法激活已迁移的旧 Chat"
        )
        let courseSessionID = reopened.createStudySession(courseID: courseA.id)?.id
        try check(
            reopened.activeStudySession?.relatedCourseIDs.isEmpty == true,
            "新建 Chat 被入口课程提前固定作用域"
        )
        try check(
            reopened.activateStudySession(
                sharedSession.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: true
            ),
            "无法激活关联多课程的旧 Chat"
        )
        try check(
            Set(reopened.activeStudySession?.relatedCourseIDs ?? [])
                == Set([courseA.id, courseB.id]),
            "关联多课程的旧 Chat 被强行归入单一课程"
        )
        try check(
            courseSessionID.map { sessionID in
                !reopened.studySessions.contains { $0.id == sessionID }
            } == true,
            "未发送消息的空白 Chat 在切换后被错误保存"
        )
        reopened.createStudySession(courseID: nil)
        try check(
            reopened.activeStudySession?.relatedCourseIDs.isEmpty == true,
            "新建统一 Chat 继承了旧会话课程关联"
        )
        reopened.removeCourseRegistrationImmediatelyForSelfCheck(
            courseA.id
        )
        for sessionID in [uniqueSession.id] {
            try check(
                reopened.studySessions.contains {
                    $0.id == sessionID
                        && !$0.relatedCourseIDs.contains(courseA.id)
                },
                "从魏碑移除课程时删除了统一 Chat，或残留课程关联"
            )
        }
        try check(
            reopened.studySessions.first { $0.id == sharedSession.id }?
                .relatedCourseIDs == [courseB.id],
            "移除课程时破坏了 Chat 与其他课程的关联"
        )
        try check(
            reopened.learningMemoryEntries(in: .course(courseA.id))
                .isEmpty,
            "从魏碑移除课程后仍残留课程学习记忆"
        )
    }

    private static func storageModelsDecodeLegacySnapshotsAndRoundTrip() throws {
        let legacyExternalData = Data(
            """
            {
              "id":"file:/tmp/legacy.txt",
              "title":"旧资料",
              "subtitle":"legacy.txt",
              "kind":"text",
              "urlPath":"/tmp/legacy.txt",
              "isSample":false,
              "isNotebookNote":false
            }
            """.utf8
        )
        let legacyExternal = try JSONDecoder().decode(StudyItem.self, from: legacyExternalData)
        try check(legacyExternal.storage == .legacyExternal, "旧外部资料没有迁移为 legacyExternal")
        try check(legacyExternal.contentRevision == 1, "旧资料没有获得首版内容修订号")
        try check(legacyExternal.contentDigest == nil, "旧资料被伪造了内容摘要")

        let legacySampleData = Data(
            """
            {
              "id":"sample",
              "title":"内置样例",
              "subtitle":"样例",
              "kind":"html",
              "urlPath":null,
              "isSample":true
            }
            """.utf8
        )
        let legacySample = try JSONDecoder().decode(StudyItem.self, from: legacySampleData)
        try check(legacySample.storage == .bundledSample, "旧内置样例被误标成外部资料")

        let ownerCourseID = UUID()
        let ownedItem = StudyItem(
            id: "imported:owned",
            title: "课程文稿",
            subtitle: "课程文稿.pdf",
            kind: .pdf,
            urlPath: "/tmp/课程/文稿/课程文稿.pdf",
            isSample: false,
            storage: .courseOwned(ownerCourseID: ownerCourseID),
            contentRevision: 7,
            contentDigest: "sha256:owned"
        )
        let sharedItem = StudyItem(
            id: "imported:shared",
            title: "共享文稿",
            subtitle: "共享文稿.pdf",
            kind: .pdf,
            urlPath: "/tmp/共享文稿/共享文稿.pdf",
            isSample: false,
            storage: .shared(sharedRelativePath: "共享文稿/共享文稿.pdf"),
            contentRevision: 3,
            contentDigest: "sha256:shared"
        )
        for item in [ownedItem, sharedItem, legacyExternal, legacySample] {
            let decoded = try JSONDecoder().decode(
                StudyItem.self,
                from: JSONEncoder().encode(item)
            )
            try check(decoded == item, "资料存储归属、修订号或摘要编码往返不一致")
        }

        struct LegacyMembership: Encodable {
            var id: UUID
            var courseID: UUID
            var itemID: String
            var createdAt: Date
        }
        let legacyMembership = LegacyMembership(
            id: UUID(),
            courseID: ownerCourseID,
            itemID: ownedItem.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decodedLegacyMembership = try JSONDecoder().decode(
            CourseItemMembership.self,
            from: JSONEncoder().encode(legacyMembership)
        )
        try check(decodedLegacyMembership.courseRelativePath == nil, "旧课程关系被伪造了相对路径")
        try check(decodedLegacyMembership.entryIdentity == nil, "旧课程关系被伪造了入口身份")
        try check(decodedLegacyMembership.documentIdentifier == nil, "旧课程关系被伪造了系统文稿身份")

        let entryIdentity = ImportedFileIdentity(
            volumeID: 12,
            fileID: 34,
            birthTimeSeconds: 56,
            birthTimeNanoseconds: 78
        )
        let membership = CourseItemMembership(
            courseID: ownerCourseID,
            itemID: sharedItem.id,
            courseRelativePath: "文稿/共享文稿.pdf",
            entryIdentity: entryIdentity,
            documentIdentifier: 9_001
        )
        let decodedMembership = try JSONDecoder().decode(
            CourseItemMembership.self,
            from: JSONEncoder().encode(membership)
        )
        try check(decodedMembership == membership, "课程入口路径和身份编码往返不一致")
        try check(decodedMembership.entryIdentity == entryIdentity, "系统文稿身份改变了文件入口身份等式")

        let resumePoint = CourseResumePoint(
            courseID: ownerCourseID,
            materialLocation: StudyLocation(
                itemID: ownedItem.id,
                itemTitle: ownedItem.title,
                pageIndex: 18
            ),
            chatID: UUID(),
            noteItemID: "imported:note",
            savedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let resumeSnapshot = PersistedWorkspace(courseResumePoints: [resumePoint])
        let restoredResumeSnapshot = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: JSONEncoder().encode(resumeSnapshot)
        )
        try check(
            restoredResumeSnapshot.courseResumePoints == [resumePoint],
            "课程恢复点的文稿位置、Chat、笔记或时间编码往返不一致"
        )

        let oldestMembershipID = UUID()
        let partialMemberships = CourseItemMemberships(values: [
            CourseItemMembership(
                id: oldestMembershipID,
                courseID: ownerCourseID,
                itemID: sharedItem.id,
                courseRelativePath: "文稿/共享文稿.pdf",
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            CourseItemMembership(
                courseID: ownerCourseID,
                itemID: sharedItem.id,
                entryIdentity: entryIdentity,
                documentIdentifier: 9_001,
                createdAt: Date(timeIntervalSince1970: 2)
            ),
        ])
        try check(partialMemberships.values.count == 1, "同一课程入口的互补元数据没有安全合并")
        try check(partialMemberships.values.first?.id == oldestMembershipID, "互补元数据合并没有保留最早关系身份")
        try check(partialMemberships.values.first?.courseRelativePath == "文稿/共享文稿.pdf", "互补元数据合并丢失课程路径")
        try check(partialMemberships.values.first?.entryIdentity == entryIdentity, "互补元数据合并丢失入口身份")
        try check(partialMemberships.values.first?.documentIdentifier == 9_001, "互补元数据合并丢失系统文稿身份")

        let conflictingMemberships = CourseItemMemberships(values: [
            membership,
            CourseItemMembership(
                courseID: ownerCourseID,
                itemID: sharedItem.id,
                courseRelativePath: "文稿/另一个入口.pdf",
                entryIdentity: entryIdentity,
                documentIdentifier: 9_001
            ),
        ])
        try check(conflictingMemberships.values.count == 2, "同一课程入口的冲突元数据被静默丢弃")
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
        let courseID = UUID()
        let session = StudySession(
            title: "第一讲复习",
            focusItemIDs: [legacyMaterialID, legacyNoteID],
            materialItemID: legacyMaterialID
        )
        let selectionThread = SelectionAskThread(
            selectionText: "货币乘数",
            source: .document,
            ownerTitle: "第一讲",
            itemID: legacyMaterialID,
            messageIDs: [UUID(), UUID()]
        )
        fixture.selectionAskThreadDefaults.set(
            try JSONEncoder().encode([selectionThread]),
            forKey: "weibei.selectionAskThreads.v1"
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
            courses: [Course(id: courseID, title: "旧课程")],
            courseItemMemberships: [
                CourseItemMembership(
                    courseID: courseID,
                    itemID: legacyMaterialID,
                    courseRelativePath: "文稿/第一讲.txt",
                    documentIdentifier: 4_242
                ),
            ],
            activeCourseID: courseID,
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
            courseResumePoints: [
                CourseResumePoint(
                    courseID: courseID,
                    materialLocation: StudyLocation(
                        itemID: legacyMaterialID,
                        itemTitle: "第一讲",
                        locationTitle: "课程恢复位置",
                        visitCount: 3
                    )
                ),
            ],
            studySessions: [session],
            activeStudySessionID: session.id
        )
        try fixture.write(snapshot)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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
        try check(
            store.courseResumePoint(for: courseID)?.materialLocation?.itemID == material.id,
            "课程恢复位置没有随资料身份迁移"
        )
        try check(Set(store.activeStudySession?.focusItemIDs ?? []) == Set([material.id, note.id]), "学习会话没有随身份迁移")
        try check(store.activeStudySession?.materialItemID == material.id, "学习会话主资料没有随身份迁移")
        try check(store.activeStudySession?.groupingMaterialItemID == material.id, "学习会话分组资料仍指向旧身份")
        let migratedMembership = try require(
            store.courseItemMemberships.first { $0.courseID == courseID },
            "课程资料归属在身份迁移时丢失"
        )
        try check(migratedMembership.itemID == material.id, "课程资料归属仍指向旧身份")
        try check(migratedMembership.courseRelativePath == "文稿/第一讲.txt", "课程入口相对路径在身份迁移时丢失")
        try check(migratedMembership.documentIdentifier == 4_242, "系统文稿身份在资料 ID 迁移时丢失")
        try check(store.selectionAskThreads.first?.itemID == material.id, "选区问答线程仍指向旧资料身份")
        try check(store.selectionAskThreads.first?.messageIDs == selectionThread.messageIDs, "选区问答线程消息关系在资料 ID 迁移时丢失")
        try check(store.flushPendingWorkspaceSave(), "资料 ID 迁移后工作区无法保存")
        let migratedSnapshot = try fixture.readSnapshot()
        try check(
            migratedSnapshot.coursePortableStateRevisions?.isEmpty == true
                && migratedSnapshot.coursePortableStateDigests?.isEmpty == true
                && migratedSnapshot.dirtyPortableCourseIDs?.isEmpty == true,
            "没有真实课程根的旧课程被错误升级成可携带课程状态"
        )
        let migratedSession = try require(
            migratedSnapshot.studySessions?.first { $0.id == session.id },
            "资料 ID 迁移后学习会话没有保存"
        )
        try check(migratedSession.materialItemID == material.id, "保存后学习会话主资料仍是旧身份")
        try check(migratedSession.groupingMaterialItemID == material.id, "保存后学习会话分组资料仍是旧身份")
        try check(migratedSession.focusItemIDs.contains(legacyMaterialID) == false, "保存后学习会话焦点仍有旧身份")
        try check(migratedSnapshot.selectionAskThreads?.first?.itemID == material.id, "保存后的同一工作区快照没有包含迁移后的选区问答")
        try check(
            migratedSnapshot.courseResumePoints?.first?.materialLocation?.itemID == material.id,
            "保存后课程恢复位置仍指向旧资料身份"
        )
        try check(migratedSnapshot.selectionAskThreads?.first?.messageIDs == selectionThread.messageIDs, "保存后的选区问答消息关系丢失")
        try check(
            fixture.selectionAskThreadDefaults.object(forKey: "weibei.selectionAskThreads.v1") == nil,
            "工作区快照保存成功后没有清理旧选区问答存储"
        )

        let reopenedMigratedStore = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        let reopenedMigratedSession = try require(
            reopenedMigratedStore.studySessions.first { $0.id == session.id },
            "重开后找不到迁移的学习会话"
        )
        try check(reopenedMigratedSession.materialItemID == material.id, "重开后学习会话主资料迁移丢失")
        try check(reopenedMigratedSession.groupingMaterialItemID == material.id, "重开后学习会话分组资料迁移丢失")
        try check(reopenedMigratedStore.selectionAskThreads.first?.itemID == material.id, "重开后选区问答线程身份迁移丢失")
        try check(reopenedMigratedStore.selectionAskThreads.first?.messageIDs == selectionThread.messageIDs, "重开后选区问答线程消息关系丢失")

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
        try check(persisted.studySessions?.contains { $0.materialItemID == legacyMaterialID } == false, "后续保存又写回了学习会话旧主资料身份")
        try check(persisted.studySessions?.contains { $0.focusItemIDs.contains(legacyMaterialID) } == false, "后续保存又写回了学习会话旧焦点身份")
        try check(persisted.courseItemMemberships?.contains { $0.itemID == legacyMaterialID } == false, "保存后课程归属仍有旧身份")
        try check(persisted.noteSourceLinks?.contains {
            $0.noteItemID == legacyMaterialID || $0.sourceItemID == legacyMaterialID
        } == false, "保存后资料关系仍有旧身份")

        try check(reopenedMigratedStore.selectionAskThreads.first?.itemID == material.id, "重开后的选区问答线程身份后来发生回退")
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
            importedFileIdentityResolver: { url in url.path == noteURL.path ? identity : nil },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: { url in url.path == noteURL.path ? identity : nil },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
    private static func selectionThreadMigrationWaitsForWorkspaceCommit() throws {
        let legacyKey = "weibei.selectionAskThreads.v1"
        let injectedSaveFailure: (Data, URL) throws -> Void = { _, _ in
            throw NSError(
                domain: "WeiBei.ImportedIdentitySelfCheck",
                code: 75,
                userInfo: [NSLocalizedDescriptionKey: "injected selection-thread migration save failure"]
            )
        }

        do {
            let fixture = try WorkspaceFixture(name: "selection-thread-commit-order")
            defer { fixture.remove() }

            let materialURL = fixture.importsDirectory.appendingPathComponent("提交顺序.txt")
            try Data("提交顺序正文".utf8).write(to: materialURL)
            let oldID = "file:\(materialURL.path)"
            let identity = ImportedFileIdentity(
                volumeID: 52,
                fileID: 502,
                birthTimeSeconds: 5_002,
                birthTimeNanoseconds: 52
            )
            let thread = SelectionAskThread(
                selectionText: "提交顺序",
                source: .document,
                ownerTitle: "提交顺序",
                itemID: oldID,
                messageIDs: [UUID()]
            )
            fixture.selectionAskThreadDefaults.set(
                try JSONEncoder().encode([thread]),
                forKey: legacyKey
            )
            try fixture.write(
                PersistedWorkspace(
                    importedItems: [
                        StudyItem(
                            id: oldID,
                            title: "提交顺序",
                            subtitle: materialURL.lastPathComponent,
                            kind: .text,
                            urlPath: materialURL.path,
                            isSample: false
                        ),
                    ],
                    selectedItemID: oldID,
                    noteSourceLinksMigrationVersion: 1
                )
            )

            var failedStore: WorkspaceStore? = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { $0.path == materialURL.path ? identity : nil },
                workspaceSnapshotWriter: injectedSaveFailure,
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            let inMemoryNewID = try require(
                failedStore?.importedItems.first?.id,
                "保存失败场景没有保留内存资料"
            )
            try check(inMemoryNewID != oldID, "保存失败场景没有真实触发资料 ID 迁移")
            try check(failedStore?.selectionAskThreads.first?.itemID == inMemoryNewID, "内存中的选区问答没有随资料 ID 一起迁移")
            try check(failedStore?.workspaceSaveError != nil, "资料 ID 迁移保存失败没有暴露错误")
            let snapshotAfterFailure = try fixture.readSnapshot()
            try check(snapshotAfterFailure.importedItems.first?.id == oldID, "工作区保存失败却提前写入了新资料 ID")
            try check(snapshotAfterFailure.selectionAskThreads == nil, "工作区保存失败却提前提交了选区问答字段")
            let defaultsAfterFailure = try JSONDecoder().decode(
                [SelectionAskThread].self,
                from: try require(
                    fixture.selectionAskThreadDefaults.data(forKey: legacyKey),
                    "保存失败后选区问答旧值丢失"
                )
            )
            try check(defaultsAfterFailure.first?.itemID == oldID, "工作区保存失败却清理或改写了旧选区问答值")
            failedStore = nil

            let failedOfflineReopen = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { _ in nil },
                workspaceSnapshotWriter: injectedSaveFailure,
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(failedOfflineReopen.importedItems.first?.id == oldID, "保存失败重开后工作区没有保持旧 ID")
            try check(failedOfflineReopen.selectionAskThreads.first?.itemID == oldID, "保存失败重开后旧选区问答不可恢复")
            try check(fixture.selectionAskThreadDefaults.data(forKey: legacyKey) != nil, "保存再次失败却清理了旧选区问答值")

            var committedStore: WorkspaceStore? = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { $0.path == materialURL.path ? identity : nil },
                workspaceSnapshotWriter: { data, url in
                    try data.write(to: url, options: [.atomic])
                },
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            let committedID = try require(committedStore?.importedItems.first?.id, "重试后资料丢失")
            try check(committedID != oldID, "保存重试后资料 ID 没有迁移")
            let committedSnapshot = try fixture.readSnapshot()
            try check(committedSnapshot.importedItems.first?.id == committedID, "保存重试后工作区没有提交新资料 ID")
            try check(committedSnapshot.selectionAskThreads?.first?.itemID == committedID, "资料和选区问答没有写入同一个工作区快照")
            try check(committedSnapshot.selectionAskThreads?.first?.messageIDs == thread.messageIDs, "保存重试后选区问答消息关系丢失")
            try check(fixture.selectionAskThreadDefaults.object(forKey: legacyKey) == nil, "工作区保存成功后没有清理旧选区问答值")
            committedStore = nil

            let reopenedStore = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { _ in nil },
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(reopenedStore.importedItems.first?.id == committedID, "保存成功后重开资料身份回退")
            try check(reopenedStore.selectionAskThreads.first?.itemID == committedID, "保存成功后重开选区问答身份回退")
            try check(reopenedStore.selectionAskThreads.first?.messageIDs == thread.messageIDs, "保存成功后重开选区问答消息关系丢失")
        }

        do {
            let fixture = try WorkspaceFixture(name: "selection-thread-explicit-empty")
            defer { fixture.remove() }
            let staleThread = SelectionAskThread(
                selectionText: "不应复活",
                source: .document,
                ownerTitle: "旧线程",
                itemID: "file:/tmp/stale"
            )
            fixture.selectionAskThreadDefaults.set(
                try JSONEncoder().encode([staleThread]),
                forKey: legacyKey
            )
            try fixture.write(
                PersistedWorkspace(
                    noteSourceLinksMigrationVersion: 1,
                    selectionAskThreads: []
                )
            )

            var store: WorkspaceStore? = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(store?.selectionAskThreads.isEmpty == true, "工作区显式空线程被旧值复活")
            try check(fixture.selectionAskThreadDefaults.object(forKey: legacyKey) == nil, "显式空线程没有清理无效旧值")
            store = nil

            fixture.selectionAskThreadDefaults.set(
                try JSONEncoder().encode([staleThread]),
                forKey: legacyKey
            )
            let reopenedStore = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(reopenedStore.selectionAskThreads.isEmpty, "重开后显式空线程被后来出现的旧值复活")
            try check(fixture.selectionAskThreadDefaults.object(forKey: legacyKey) == nil, "重开显式空线程后没有清理无效旧值")
        }

        for malformedWorkspace in [false, true] {
            let fixture = try WorkspaceFixture(
                name: malformedWorkspace
                    ? "selection-thread-malformed-workspace"
                    : "selection-thread-missing-workspace"
            )
            defer { fixture.remove() }
            let legacyThread = SelectionAskThread(
                selectionText: malformedWorkspace ? "损坏快照恢复" : "缺失快照恢复",
                source: .document,
                ownerTitle: "旧线程",
                itemID: "file:/tmp/legacy"
            )
            fixture.selectionAskThreadDefaults.set(
                try JSONEncoder().encode([legacyThread]),
                forKey: legacyKey
            )
            if malformedWorkspace {
                try Data("{not-json".utf8).write(
                    to: fixture.workspaceDirectory.appendingPathComponent("workspace.json"),
                    options: [.atomic]
                )
            }

            let store = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(store.selectionAskThreads.first?.id == legacyThread.id, "工作区缺失或损坏时没有恢复旧选区问答")
            let migratedSnapshot = try fixture.readSnapshot()
            try check(migratedSnapshot.selectionAskThreads?.first?.id == legacyThread.id, "恢复的旧选区问答没有写入工作区快照")
            try check(fixture.selectionAskThreadDefaults.object(forKey: legacyKey) == nil, "恢复成功后没有清理旧选区问答值")
        }
    }

    @MainActor
    private static func duplicateIdentityPreservesConflictingStorageMetadata() throws {
        let identity = ImportedFileIdentity(
            volumeID: 51,
            fileID: 501,
            birthTimeSeconds: 5_001,
            birthTimeNanoseconds: 51
        )
        let courseID = UUID()

        do {
            let fixture = try WorkspaceFixture(name: "duplicate-storage-conflict")
            defer { fixture.remove() }
            let url = fixture.importsDirectory.appendingPathComponent("存储归属冲突.txt")
            try Data("相同文件，不同归属".utf8).write(to: url)
            try fixture.write(
                PersistedWorkspace(
                    importedItems: [
                        StudyItem(
                            id: "imported:storage-canonical",
                            title: "课程文稿",
                            subtitle: url.lastPathComponent,
                            kind: .text,
                            urlPath: url.path,
                            importedFileIdentity: identity,
                            isSample: false,
                            storage: .courseOwned(ownerCourseID: courseID),
                            contentRevision: 2,
                            contentDigest: "digest:course"
                        ),
                        StudyItem(
                            id: "file:\(url.path)",
                            title: "旧外部文稿",
                            subtitle: url.lastPathComponent,
                            kind: .text,
                            urlPath: url.path,
                            importedFileIdentity: identity,
                            isSample: false,
                            storage: .legacyExternal,
                            contentRevision: 1,
                            contentDigest: nil
                        ),
                    ],
                    noteSourceLinksMigrationVersion: 1
                )
            )

            let store = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { $0.path == url.path ? identity : nil },
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(store.importedItems.count == 2, "同文件身份但存储归属或内容版本冲突的资料被静默合并")
            try check(Set(store.importedItems.map(\.storage)) == [
                .courseOwned(ownerCourseID: courseID),
                .legacyExternal,
            ], "存储归属冲突迁移丢失了一方")
        }

        do {
            let fixture = try WorkspaceFixture(name: "duplicate-membership-conflict")
            defer { fixture.remove() }
            let url = fixture.importsDirectory.appendingPathComponent("课程入口冲突.txt")
            try Data("相同文件，不同课程入口".utf8).write(to: url)
            let canonicalID = "imported:membership-canonical"
            let legacyID = "file:\(url.path)"
            let canonicalEntryIdentity = ImportedFileIdentity(
                volumeID: 51,
                fileID: 601,
                birthTimeSeconds: 6_001,
                birthTimeNanoseconds: 61
            )
            let legacyEntryIdentity = ImportedFileIdentity(
                volumeID: 51,
                fileID: 602,
                birthTimeSeconds: 6_002,
                birthTimeNanoseconds: 62
            )
            try fixture.write(
                PersistedWorkspace(
                    importedItems: [
                        StudyItem(
                            id: canonicalID,
                            title: "入口一",
                            subtitle: url.lastPathComponent,
                            kind: .text,
                            urlPath: url.path,
                            importedFileIdentity: identity,
                            isSample: false
                        ),
                        StudyItem(
                            id: legacyID,
                            title: "入口二",
                            subtitle: url.lastPathComponent,
                            kind: .text,
                            urlPath: url.path,
                            importedFileIdentity: identity,
                            isSample: false
                        ),
                    ],
                    courses: [Course(id: courseID, title: "入口冲突课程")],
                    courseItemMemberships: [
                        CourseItemMembership(
                            courseID: courseID,
                            itemID: canonicalID,
                            courseRelativePath: "文稿/入口一.txt",
                            entryIdentity: canonicalEntryIdentity,
                            documentIdentifier: 6_001
                        ),
                        CourseItemMembership(
                            courseID: courseID,
                            itemID: legacyID,
                            courseRelativePath: "文稿/入口二.txt",
                            entryIdentity: legacyEntryIdentity,
                            documentIdentifier: 6_002
                        ),
                    ],
                    noteSourceLinksMigrationVersion: 1
                )
            )

            let store = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { $0.path == url.path ? identity : nil },
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(store.importedItems.count == 2, "同课程入口元数据冲突的资料被静默合并")
            try check(store.courseItemMemberships.count == 2, "同课程入口元数据冲突时丢失了一条归属")
            try check(
                Set(store.courseItemMemberships.compactMap(\.courseRelativePath))
                    == ["文稿/入口一.txt", "文稿/入口二.txt"],
                "课程入口路径冲突迁移丢失了一方"
            )
            try check(
                Set(store.courseItemMemberships.compactMap(\.documentIdentifier)) == [6_001, 6_002],
                "课程入口系统文稿身份冲突迁移丢失了一方"
            )
        }

        do {
            let fixture = try WorkspaceFixture(name: "duplicate-membership-enrichment")
            defer { fixture.remove() }
            let url = fixture.importsDirectory.appendingPathComponent("课程入口补全.txt")
            try Data("相同文件，互补课程入口".utf8).write(to: url)
            let canonicalID = "imported:membership-enrichment"
            let legacyID = "file:\(url.path)"
            let entryIdentity = ImportedFileIdentity(
                volumeID: 51,
                fileID: 701,
                birthTimeSeconds: 7_001,
                birthTimeNanoseconds: 71
            )
            let item = StudyItem(
                id: canonicalID,
                title: "入口补全",
                subtitle: url.lastPathComponent,
                kind: .text,
                urlPath: url.path,
                importedFileIdentity: identity,
                isSample: false
            )
            var legacyItem = item
            legacyItem.id = legacyID
            try fixture.write(
                PersistedWorkspace(
                    importedItems: [item, legacyItem],
                    courses: [Course(id: courseID, title: "入口补全课程")],
                    courseItemMemberships: [
                        CourseItemMembership(
                            courseID: courseID,
                            itemID: canonicalID,
                            courseRelativePath: "文稿/课程入口补全.txt",
                            documentIdentifier: 7_001
                        ),
                        CourseItemMembership(
                            courseID: courseID,
                            itemID: legacyID,
                            entryIdentity: entryIdentity
                        ),
                    ],
                    noteSourceLinksMigrationVersion: 1
                )
            )

            let store = WorkspaceStore(
                workspaceDirectory: fixture.workspaceDirectory,
                importedFileIdentityResolver: { $0.path == url.path ? identity : nil },
                selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
            )
            try check(store.importedItems.count == 1, "同课程入口互补元数据阻止了安全的资料去重")
            let mergedMembership = try require(
                store.courseItemMemberships.first,
                "资料去重后课程入口关系丢失"
            )
            try check(store.courseItemMemberships.count == 1, "资料去重后课程入口关系重复")
            try check(mergedMembership.itemID == canonicalID, "资料去重后课程入口没有指向规范身份")
            try check(mergedMembership.courseRelativePath == "文稿/课程入口补全.txt", "资料去重后课程路径没有补全")
            try check(mergedMembership.entryIdentity == entryIdentity, "资料去重后入口身份没有补全")
            try check(mergedMembership.documentIdentifier == 7_001, "资料去重后系统文稿身份没有补全")
        }
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

        var store: WorkspaceStore? = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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

        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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

        var store: WorkspaceStore? = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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

        let searchIndex = CourseDocumentSearchIndex(
            databaseURL: fixture.indexDirectory.appendingPathComponent("search.sqlite3")
        )
        let originalSearch = searchIndex.lookup(items: [firstMaterial], query: "流动性偏好")
        try check(originalSearch[firstMaterial.id]?.text?.contains("流动性偏好") == true, "首次导入没有进入全文索引")

        let renamedURL = fixture.importsDirectory.appendingPathComponent("第二讲-改名.txt")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        store = nil

        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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

        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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
        try check(
            appRenamedNote.urlPath?.hasSuffix("第二讲最终笔记.md") == true,
            "应用内重命名没有更新笔记路径；实际路径=\(appRenamedNote.urlPath ?? "nil")；错误=\(store?.noteFileError ?? "nil")"
        )
        store?.flushPendingNotePersistence()
        store = nil
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        try check(store?.courseNotebookItems.first { $0.id == note.id }?.urlPath == appRenamedNote.urlPath, "应用内重命名后重启丢失笔记路径")
        try check(store?.noteText.contains("Finder 移动后继续编辑") == true, "应用内重命名后重启丢失笔记正文")
        try check(store?.linkedSourceIDs(for: note.id) == [firstMaterial.id], "应用内重命名后重启丢失笔记关系")

        let appRenamedNoteURL = try require(appRenamedNote.url, "应用内重命名后笔记没有真实路径")
        let finalNoteURL = movedDirectory.appendingPathComponent("第二讲归档笔记.md")
        try FileManager.default.moveItem(at: appRenamedNoteURL, to: finalNoteURL)
        store = nil
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: resolver,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
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
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
        )
        try check(store?.importedItems.count == 1, "两个同身份旧路径项需要第二次启动才合并")
        let firstLaunchSnapshot = try Data(contentsOf: fixture.workspaceDirectory.appendingPathComponent("workspace.json"))
        store = nil
        store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            importedFileIdentityResolver: { url in
                [firstURL.path, secondURL.path].contains(url.path) ? sharedIdentity : nil
            },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: { identities[$0.path] },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
            importedFileIdentityResolver: { identities[$0.path] },
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults
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
        let selectionAskThreadDefaults: UserDefaults
        private let selectionAskThreadDefaultsSuiteName: String

        init(name: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("weibei-stable-identity-\(name)-\(UUID().uuidString)", isDirectory: true)
            workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
            importsDirectory = root.appendingPathComponent("Imports", isDirectory: true)
            indexDirectory = root.appendingPathComponent("Index", isDirectory: true)
            selectionAskThreadDefaultsSuiteName = "weibei.imported-identity-self-check.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: selectionAskThreadDefaultsSuiteName) else {
                throw CheckError.failed("无法建立隔离的选区问答自检存储")
            }
            selectionAskThreadDefaults = defaults
            defaults.removePersistentDomain(forName: selectionAskThreadDefaultsSuiteName)
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
            selectionAskThreadDefaults.removePersistentDomain(forName: selectionAskThreadDefaultsSuiteName)
        }
    }
}
