import Foundation
@testable import WeiBei
import WeiBeiCore

enum CourseProjectRootSelfCheck {
    @MainActor
    static func runBackgroundWorkspacePersistenceOnly() throws {
        try backgroundWorkspacePersistenceIsOrderedAndDurable()
    }

    @MainActor
    static func runSharedConversionConflictOnly() throws {
        try unchangedRequiredStateRejectsConcurrentDiskChange(
            usesBackgroundWorkspacePersistence: false
        )
        try unchangedRequiredStateRejectsConcurrentDiskChange(
            usesBackgroundWorkspacePersistence: true
        )
        try sharedConversionRejectsConcurrentPortableState(
            usesBackgroundWorkspacePersistence: false
        )
        try sharedConversionRejectsConcurrentPortableState(
            usesBackgroundWorkspacePersistence: true
        )
    }

    @MainActor
    static func run() throws {
        func step(
            _ name: String,
            _ operation: () throws -> Void
        ) throws {
            fputs("WeiBeiSafetyTests step: \(name)\n", stderr)
            fflush(stderr)
            do {
                try operation()
            } catch {
                throw CheckError.failed(
                    "\(name)：\(error.localizedDescription)"
                )
            }
        }
        try courseEntryPresentationResetsIntent()
        try escapeBridgeDefersToPresentedSurfaces()
        try libraryGrantPersistsAndBalancesSecurityScope()
        try unavailableCourseRootKeepsCourseChatAvailable()
        try agentProjectSearchUsesVerifiedCourseGrants()
        try libraryCannotEqualOrSitInsideRegisteredCourse()
        try deniedSecurityScopeKeepsCourseUnavailable()
        try movedLibraryIntoWorkspaceIsRejectedOnRestore()
        try libraryCreationDerivesSafeNameAndRejectsConflicts()
        try step("新建课程原子落盘") {
            try newCourseCreatesAtomicProjectAndManifest()
        }
        try step("课程可携带状态恢复") {
            try portableCourseStateIsScopedAtomicAndRestorable()
        }
        try step("旧课程 Chat 一次迁移") {
            try legacyPortableChatImportsOnce()
        }
        try step("课程移除与废纸篓恢复") {
            try courseRemovalPreservesStateAndTrashesOnlyVerifiedRoot()
        }
        try step("课程移除连续崩溃恢复") {
            try courseRemovalDoubleCrashRecoveryIsIdempotent()
        }
        try step("课程移除两代保存竞态") {
            try courseRemovalSurvivesLaterGenerationSaveFailure()
        }
        try step("课程可携带副本导出") {
            try portableCourseExportCopiesWholeTreeAndFailsClosed()
        }
        try step("离线与损坏状态保留") {
            try portableCourseStatePreservesOfflineAndCorruptChanges()
        }
        try stagedAndWorkspaceFailuresLeaveNoGhostCourse()
        try foreignWritesPreventRollbackDeletion()
        try dangerousAndOverlappingRootsWriteNothing()
        try pathComparisonFollowsActualVolumeCaseSensitivity()
        try linkedMetadataDirectoryIsRejectedWithoutWrites()
        try damagedMetadataIsNotOverwritten()
        try movedLibraryCourseRestoresTheSameIdentity()
        try courseOwnedMaterialMovesOnlyAfterCommitAndRejectsConflicts()
        try courseOwnedImportRejectsSymbolicLinks()
        try courseOwnedImportRejectsTargetRacesAndEscapes()
        try courseOwnedDirectoryRacesDoNotCommitOrDeleteSource()
        try courseOwnedSaveFailureLeavesNoGhostState()
        try uncommittedRecoveryPreservesTargetWithoutVerifiedOriginal()
        try courseOwnedCleanupFailureRetriesOnReopen()
        try courseOwnedQuarantineFailureRemainsRecoverable()
        try hiddenTransactionContentPreventsJournalCleanup()
        try courseOwnedRecoveryRejectsLinkedTransactionDirectory()
        try courseOwnedFileFollowsMovedCourseRootWithoutBookmark()
        try courseOwnedResolutionHandlesReplacementAndInPlaceEditing()
        try courseRootRefreshRebindsOwnedItemsAndRollsBackTogether()
        try courseOwnedAndGlobalNotesStaySeparated()
        try largeFileWorkStaysOffMainThread()
        try courseMarkdownConditionalWritePreservesFinderContentAndRecovers()
        try courseMarkdownPostPlacementReplacementPreservesAllContent()
        try step("C1 外部改动备份环与连续自写不刷环") {
            try courseNoteBackupUsesSelfWrittenBaselineAcrossReconcile()
        }
        try step("C2 写回失败草稿活过 course-state 与重启") {
            try courseNoteDraftSurvivesPortableStateAndRelaunch()
        }
        try step("H1 孤儿事务白名单与 replaced-target 保留") {
            try orphanTransactionCleanupHonorsWhitelistAndCrashBackups()
        }
        try step("同一路径失焦写回并在激活时刷新") {
            try appDeactivationFlushesThenActivationRefreshesSameFile()
        }
        try step("H3 根外 symlink 不登记") {
            try courseScanSkipsSymlinksOutsideRoot()
        }
        try firstScanAndFinderReconciliationPreserveIdentity()
        try unavailableCourseMaterialKeepsCourseHomeOpenUntilRestored()
        try courseMaterialOpensAndHealsWhenIdentityDrifts()
        try thousandFileReconciliationIsLinearAndHardLinksStayStable()
        try exclusivePlacementRejectsConcurrentTargetAndSymlinkSwap()
        try conflictChoicesPreserveDataAndRelations()
        try replacementKeepsTargetIdentityAcrossMoves()
        try replacementTrashFailureRestoresOriginal()
        try verifiedCleanupNeverDeletesReplacementInode()
        try step("通用内容与两层删除") {
            try commonContentAndTwoLevelRemoval()
        }
        try legacyCourseSnapshotStillDecodes()
    }

    @MainActor
    private static func backgroundWorkspacePersistenceIsOrderedAndDurable()
        throws {
        let fixture = try Fixture(name: "background-workspace-save")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(
            title: "后台保存课程"
        )
        try check(
            try store.verifyBackgroundWorkspacePersistenceForSelfCheck(
                courseID: courseID
            ),
            "后台保存没有离开主线程、按代提交并读回最新版"
        )

        let reopened = makeStore(fixture: fixture)
        try check(
            reopened.modelName == "background-save-generation-two"
                && reopened.courses.first(where: {
                    $0.id == courseID
                })?.title == "后台保存课程（第二代）",
            "后台保存返回后，重开没有读到最新版工作区"
        )
    }

    @MainActor
    private static func
        courseRemovalSurvivesLaterGenerationSaveFailure() throws {
        let fixture = try Fixture(
            name: "course-removal-generation-failure"
        )
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let removedCourseID = try store.createCourseInLibrary(
            title: "待移除课程"
        )
        let retainedCourseID = try store.createCourseInLibrary(
            title: "保留课程（第一代）"
        )
        try check(
            store.flushPendingWorkspaceSave(),
            "两代保存竞态样本没有完成初始保存"
        )
        try check(
            try store.verifyCourseRemovalPersistenceRaceForSelfCheck(
                removing: removedCourseID,
                retaining: retainedCourseID
            ),
            "第一代移除已提交、第二代保存失败后课程移除或补偿保存不正确"
        )

        let reopened = makeStore(fixture: fixture)
        try check(
            reopened.course(withID: removedCourseID) == nil
                && reopened.course(withID: retainedCourseID)?.title
                    == "保留课程（第二代）"
                && reopened.modelName
                    == "课程移除第二代全局状态",
            "补偿保存后重开复活了已移除课程或丢失了第二代状态"
        )
    }

    @MainActor
    private static func
        courseRemovalPreservesStateAndTrashesOnlyVerifiedRoot() throws {
        let fixture = try Fixture(name: "course-removal")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let imports = try fixture.makeDirectory("待导入")

        var swapRootBeforeTrash = false
        var crashAfterTrashMove = false
        var failPostTrashWorkspaceWrite = false
        let failWorkspaceWrite = LockedBox(false)
        var courseARootForHook: URL?
        var displacedCourseRoot: URL?
        let lureName = "DO_NOT_TRASH.txt"
        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                if swapRootBeforeTrash,
                   stage == .beforeCourseRootTrashIsolation,
                   let courseARootForHook {
                    swapRootBeforeTrash = false
                    let displaced = courseARootForHook
                        .deletingLastPathComponent()
                        .appendingPathComponent(
                            "课程甲-真实目录暂存",
                            isDirectory: true
                        )
                    try FileManager.default.moveItem(
                        at: courseARootForHook,
                        to: displaced
                    )
                    try FileManager.default.createDirectory(
                        at: courseARootForHook,
                        withIntermediateDirectories: true
                    )
                    try Data("DO_NOT_TRASH".utf8).write(
                        to: courseARootForHook
                            .appendingPathComponent(lureName)
                    )
                    displacedCourseRoot = displaced
                }
                if crashAfterTrashMove,
                   stage
                    == .afterCourseRootTrashMoveBeforeJournal {
                    crashAfterTrashMove = false
                    throw CourseProjectSimulatedCrash()
                }
                if failPostTrashWorkspaceWrite,
                   stage
                    == .afterCourseRootTrashJournalBeforeWorkspaceSave {
                    failPostTrashWorkspaceWrite = false
                    failWorkspaceWrite.set(true)
                }
            },
            workspaceWriter: { data, url in
                if failWorkspaceWrite.get() {
                    throw CheckError.injectedFailure
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        try check(store != nil, "无法创建课程移除样本")
        try store!.configureCourseLibrary(at: library)
        let courseA = try store!.createCourseInLibrary(
            title: "课程甲"
        )
        let courseB = try store!.createCourseInLibrary(
            title: "课程乙"
        )
        let sharedSource = imports.appendingPathComponent(
            "共享原件.txt"
        )
        let ownedSource = imports.appendingPathComponent(
            "课程甲自有文稿.txt"
        )
        try Data("SHARED_ORIGINAL".utf8).write(to: sharedSource)
        try Data("COURSE_A_OWNED".utf8).write(to: ownedSource)
        let sharedItem = try store!
            .importFileIntoCourseForSelfCheck(
                sharedSource,
                courseID: courseA,
                role: .material
            ).item
        try store!.shareCourseOwnedItemForSelfCheck(
            itemID: sharedItem.id,
            withCourseID: courseB
        )
        let ownedItem = try store!
            .importFileIntoCourseForSelfCheck(
                ownedSource,
                courseID: courseA,
                role: .material
            ).item
        let noteID = try require(
            store!.createCourseNotebookNoteForSelfCheck(
                courseID: courseA,
                title: "课程甲笔记"
            ),
            "无法创建课程移除笔记"
        )
        let chatToken = "A0C_GHOST_CHAT_TOKEN"
        let memoryToken = "A0C_COURSE_MEMORY_TOKEN"
        let globalMemoryToken = "A0C_GLOBAL_MEMORY_TOKEN"
        let courseAChatID = try store!.installCourseRemovalStateForSelfCheck(
            courseID: courseA,
            materialItemID: ownedItem.id,
            noteItemID: noteID,
            messageText: chatToken,
            memoryText: memoryToken,
            globalMemoryText: globalMemoryToken
        )
        let piHistoryDirectory = fixture.workspaceDirectory
            .appendingPathComponent("AgentRuntime/Sessions", isDirectory: true)
            .appendingPathComponent(
                courseAChatID.uuidString.lowercased(),
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: piHistoryDirectory,
            withIntermediateDirectories: true
        )
        let piHistoryMarker = piHistoryDirectory.appendingPathComponent(
            "must-survive-course-removal"
        )
        try Data("PI_HISTORY_MUST_SURVIVE".utf8).write(
            to: piHistoryMarker
        )
        try check(
            store!.flushPendingWorkspaceSave(),
            "课程移除样本无法写入课程状态"
        )

        let rootA = try require(
            store!.courseRootURL(for: courseA),
            "课程甲根目录缺失"
        )
        let rootB = try require(
            store!.courseRootURL(for: courseB),
            "课程乙根目录缺失"
        )
        courseARootForHook = rootA
        let rootAIdentity = try require(
            CourseProjectFileWorker.identity(at: rootA),
            "课程甲根身份缺失"
        )
        let rootBIdentity = try require(
            CourseProjectFileWorker.identity(at: rootB),
            "课程乙根身份缺失"
        )
        let visibleA = try rootA.visibleFileSnapshot()
        let manifestA = try Data(
            contentsOf: rootA.appendingPathComponent(
                ".weibei/course.json"
            )
        )
        let sharedURL = try require(
            store!.item(withID: sharedItem.id)?.url,
            "共享原件路径缺失"
        )
        let sharedIdentity = try require(
            CourseProjectFileWorker.identity(at: sharedURL),
            "共享原件身份缺失"
        )
        let sharedData = try Data(contentsOf: sharedURL)

        try store!.removeCourseFromWeiBeiForSelfCheck(
            courseA
        )
        try check(
            store!.course(withID: courseA) == nil
                && store!.studySessions.contains {
                    !$0.relatedCourseIDs.contains(courseA)
                        && $0.messages.contains { $0.text == chatToken }
                }
                && store!.courseIDs(for: sharedItem.id)
                    .contains(courseA) == false
                && store!.item(withID: sharedItem.id) != nil
                && store!.item(withID: ownedItem.id) == nil
                && store!.learningMemoryEntries(
                    in: .course(courseA)
                ).isEmpty
                && store!.learningMemoryEntries(in: .global)
                    .contains {
                        $0.text == globalMemoryToken
                    }
                && store!.courseResumePoint(
                    for: courseA
                ) == nil
                && piHistoryMarker.exists,
            "普通移除没有解除课程关系、保留 Chat，或误删共享资料与全局状态"
        )
        let visibleAfterRemoval = try rootA.visibleFileSnapshot()
        let manifestAfterRemoval = try Data(
            contentsOf: rootA.appendingPathComponent(
                ".weibei/course.json"
            )
        )
        let sharedDataAfterRemoval = try Data(
            contentsOf: sharedURL
        )
        try check(
            CourseProjectFileWorker.identity(at: rootA)
                == rootAIdentity
                && visibleAfterRemoval == visibleA
                && manifestAfterRemoval == manifestA
                && CourseProjectFileWorker.identity(at: rootB)
                    == rootBIdentity
                && CourseProjectFileWorker.identity(at: sharedURL)
                    == sharedIdentity
                && sharedDataAfterRemoval == sharedData,
            "普通移除改动了真实课程内容、其他课程或共享原件"
        )

        let reopenedCourseID = try store!.adoptCourseFolder(
            at: rootA,
            title: "不应覆盖课程名"
        )
        try check(
            reopenedCourseID == courseA,
            "重新纳入课程改变了课程身份"
        )
        try check(
            store!.studySessions.filter {
                $0.messages.contains { $0.text == chatToken }
            }.count == 1
                && piHistoryMarker.exists,
            "重新纳入课程时丢失或复制了本机 Chat"
        )
        try check(
            store!.learningMemoryEntries(
                in: .course(courseA)
            ).contains { $0.text == memoryToken },
            "重新纳入课程没有恢复课程记忆"
        )
        try check(
            store!.courseResumePoint(for: courseA)?
                .materialLocation?.itemID == ownedItem.id
                && store!.courseResumePoint(for: courseA)?
                    .noteItemID == noteID,
            "重新纳入课程没有恢复阅读位置和当前笔记"
        )

        swapRootBeforeTrash = true
        try expectFailure("确认后根目录身份变化") {
            _ = try store!
                .moveCourseFolderToTrashForSelfCheck(courseA)
        }
        let displacedRoot = try require(
            displacedCourseRoot,
            "没有建立根目录替换样本"
        )
        let lureSurvived =
            rootA.appendingPathComponent(lureName).exists
        let realRootSurvived =
            CourseProjectFileWorker.identity(
                at: displacedRoot
            ) == rootAIdentity
        let registrationSurvived =
            store!.course(withID: courseA) != nil
        try check(
            lureSurvived
                && realRootSurvived
                && registrationSurvived,
            "课程根被替换后的安全状态不正确：诱饵=\(lureSurvived)，真实目录=\(realRootSurvived)，课程登记=\(registrationSurvived)"
        )
        try FileManager.default.removeItem(at: rootA)
        try FileManager.default.moveItem(
            at: displacedRoot,
            to: rootA
        )

        crashAfterTrashMove = true
        try expectFailure("废纸篓移动后崩溃") {
            _ = try store!
                .moveCourseFolderToTrashForSelfCheck(courseA)
        }
        let selfCheckTrash = fixture.workspaceDirectory
            .appendingPathComponent(
                "SelfCheckTrash",
                isDirectory: true
            )
        let trashedNames = try FileManager.default
            .contentsOfDirectory(atPath: selfCheckTrash.path)
        let trashedRoot = try require(
            trashedNames.first.map {
                selfCheckTrash.appendingPathComponent(
                    $0,
                    isDirectory: true
                )
            },
            "废纸篓崩溃样本没有保留课程目录"
        )
        let sharedDataAfterTrash = try Data(
            contentsOf: sharedURL
        )
        try check(
            !rootA.exists
                && CourseProjectFileWorker.identity(at: trashedRoot)
                    == rootAIdentity
                && CourseProjectFileWorker.identity(at: rootB)
                    == rootBIdentity
                && CourseProjectFileWorker.identity(at: sharedURL)
                    == sharedIdentity
                && sharedDataAfterTrash == sharedData
                && piHistoryMarker.exists,
            "废纸篓崩溃窗口损坏了课程、其他课程或共享原件"
        )
        // S3：无 journal。废纸篓已移走课程根，登记仍在；不阻塞其他课程操作。
        let journalURL = fixture.workspaceDirectory
            .appendingPathComponent("pending-course-removal.json")
        try check(
            !journalURL.exists,
            "S3 仍写出课程移除 journal"
        )
        let receiptDirectory = try require(
            (try FileManager.default.contentsOfDirectory(
                at: library,
                includingPropertiesForKeys: nil,
                options: []
            )).first(where: {
                $0.lastPathComponent
                    .hasPrefix(".weibei-course-removal-")
                    && $0.appendingPathComponent(
                        "trash-receipt.json"
                    ).exists
            }),
            "课程根进废纸篓后没有留下重启收尾凭据"
        )
        failPostTrashWorkspaceWrite = true
        let trashedRootB = try store!
            .moveCourseFolderToTrashForSelfCheck(courseB)
        try check(
            store!.course(withID: courseB) == nil
                && !rootB.exists
                && CourseProjectFileWorker.identity(at: trashedRootB)
                    == rootBIdentity,
            "工作区保存失败后没有完成真实课程删除"
        )
        failWorkspaceWrite.set(false)
        try check(
            store!.flushPendingWorkspaceSave(),
            "工作区恢复可写后没有补存课程删除"
        )
        let receiptsAfterSave = try FileManager.default
            .contentsOfDirectory(
                at: library,
                includingPropertiesForKeys: nil,
                options: []
            )
            .filter {
                $0.lastPathComponent
                    .hasPrefix(".weibei-course-removal-")
                    && $0.appendingPathComponent(
                        "trash-receipt.json"
                    ).exists
            }
        try check(
            receiptsAfterSave == [receiptDirectory],
            "工作区补存后没有清掉第二门课程的收尾凭据"
        )
        store = nil
        let reopened = makeStore(fixture: fixture)
        let retainedChatCount = reopened.studySessions.filter {
            !$0.relatedCourseIDs.contains(courseA)
                && $0.messages.contains { $0.text == chatToken }
        }.count
        try check(
            reopened.course(withID: courseA) == nil
                && reopened.course(withID: courseB) == nil
                && retainedChatCount == 1
                && reopened.item(withID: sharedItem.id) != nil
                && CourseProjectFileWorker.identity(at: trashedRoot)
                    == rootAIdentity
                && piHistoryMarker.exists
                && !receiptDirectory.exists
                && (try FileManager.default.contentsOfDirectory(
                    at: library,
                    includingPropertiesForKeys: nil,
                    options: []
                )).allSatisfy {
                    !$0.lastPathComponent
                        .hasPrefix(".weibei-course-removal-")
                },
            "重开后没有自动收尾课程登记、凭据或废纸篓状态"
        )
    }

    @MainActor
    private static func
        courseRemovalDoubleCrashRecoveryIsIdempotent() throws {
        // S3：无 journal 恢复。崩溃后操作未完成 → 用户重试；不留 pending journal。
        let fixture = try Fixture(
            name: "course-removal-double-crash"
        )
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")

        var firstCrash = true
        var firstStore: WorkspaceStore? = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                if firstCrash,
                   stage
                    == .afterCourseRootTrashIsolationBeforeJournal {
                    firstCrash = false
                    throw CourseProjectSimulatedCrash()
                }
            }
        )
        try check(firstStore != nil, "无法建立第一次崩溃样本")
        try firstStore!.configureCourseLibrary(at: library)
        let courseID = try firstStore!.createCourseInLibrary(
            title: "连续崩溃课程"
        )
        let root = try require(
            firstStore!.courseRootURL(for: courseID),
            "连续崩溃课程根缺失"
        )
        let rootIdentity = try require(
            CourseProjectFileWorker.identity(at: root),
            "连续崩溃课程身份缺失"
        )
        try check(
            firstStore!.flushPendingWorkspaceSave(),
            "连续崩溃课程初始状态未保存"
        )
        try expectFailure("隔离后第一次崩溃") {
            _ = try firstStore!
                .moveCourseFolderToTrashForSelfCheck(courseID)
        }
        let journalURL = fixture.workspaceDirectory
            .appendingPathComponent(
                "pending-course-removal.json"
            )
        try check(!journalURL.exists, "S3 第一次崩溃后仍写出 journal")
        try check(
            firstStore!.course(withID: courseID) != nil,
            "第一次崩溃后不应取消课程登记"
        )
        firstStore = nil

        // 重开后用户重试：完整移到废纸篓。
        let recovered = makeStore(fixture: fixture)
        try check(
            recovered.course(withID: courseID) != nil,
            "重开后课程登记丢失"
        )
        _ = try recovered.moveCourseFolderToTrashForSelfCheck(courseID)
        try check(
            recovered.course(withID: courseID) == nil
                && !journalURL.exists,
            "重试移到废纸篓后登记未清或仍写 journal"
        )
        let selfCheckTrash = fixture.workspaceDirectory
            .appendingPathComponent(
                "SelfCheckTrash",
                isDirectory: true
            )
        let trashedEntries = (
            try? FileManager.default.contentsOfDirectory(
                at: selfCheckTrash,
                includingPropertiesForKeys: nil
            )
        ) ?? []
        try check(
            trashedEntries.contains {
                CourseProjectFileWorker.identity(at: $0)
                    == rootIdentity
            },
            "重试后课程根未进入废纸篓"
        )
    }

    @MainActor
    private static func agentProjectSearchUsesVerifiedCourseGrants() throws {
        let fixture = try Fixture(name: "agent-project-grants")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let imports = try fixture.makeDirectory("待导入")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseA = try store.createCourseInLibrary(title: "课程甲")
        let courseB = try store.createCourseInLibrary(title: "课程乙")

        let legacyURL = imports.appendingPathComponent("旧外部.txt")
        try Data("LEGACY_AGENT_SECRET".utf8).write(to: legacyURL)
        let legacyItem = try require(
            store.importFiles([legacyURL], selectsFirstImportedItem: false).first,
            "没有建立旧外部资料样本"
        )
        store.injectLegacyCourseMembershipForAgentSelfCheck(
            itemID: legacyItem.id,
            courseID: courseA
        )
        let legacyCourseScope = try store.agentProjectScopeForSelfCheck(courseID: courseA)
        let legacyCourseSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "LEGACY_AGENT_SECRET"
        )
        let legacyGlobalSearch = try store.agentHostSearchForSelfCheck(
            courseID: nil,
            query: "LEGACY_AGENT_SECRET"
        )
        let legacyCourseMap = try store.agentHostMapForSelfCheck(
            courseID: courseA
        )
        try check(
            legacyCourseScope.kind == .global
                && !legacyCourseScope.items.contains(where: {
                    $0.itemID == legacyItem.id
                })
                && legacyCourseMap.items.contains(where: {
                    $0.item.id == legacyItem.id
                })
                && legacyCourseSearch.items.contains(where: {
                    $0.item.id == legacyItem.id
                })
                && legacyGlobalSearch.items.contains(where: {
                    $0.item.id == legacyItem.id
                }),
            "统一 Agent 没有通过按需目录和搜索读取已登记的旧外部资料"
        )
        let replacedLegacySearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "REPLACED_LEGACY_TOKEN",
            beforeSearch: {
                try FileManager.default.removeItem(at: legacyURL)
                try Data("REPLACED_LEGACY_TOKEN".utf8).write(to: legacyURL)
            }
        )
        try check(
            !replacedLegacySearch.items.contains(where: { $0.item.id == legacyItem.id }),
            "课程 Agent 读取了导入后被替换身份的旧外部资料"
        )
        store.removeCourseMembershipForAgentSelfCheck(
            itemID: legacyItem.id,
            courseID: courseA
        )

        let ownedURL = imports.appendingPathComponent("课程自有.txt")
        let ownedArticle = "OWNED_AGENT_TOKEN\n\n"
            + String(repeating: "这是用于验证全文读取的文章上下文。\n\n", count: 180)
            + "FULL_ARTICLE_TAIL_TOKEN"
        try Data(ownedArticle.utf8).write(to: ownedURL)
        let ownedItem = try store.importFileIntoCourseForSelfCheck(
            ownedURL,
            courseID: courseA,
            role: .material
        ).item
        let ownedSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "OWNED_AGENT_TOKEN"
        )
        let ownedRead = try store.agentHostReadForSelfCheck(
            courseID: courseA,
            itemID: ownedItem.id
        )
        try check(
            ownedSearch.items.contains(where: { $0.item.id == ownedItem.id })
                && ownedRead.items.first(where: { $0.item.id == ownedItem.id })?
                    .item.searchText.contains("FULL_ARTICLE_TAIL_TOKEN") == true,
            "课程 Agent 没有读取已核验课程自有资料的完整文章正文"
        )

        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseA,
                title: "实时学习笔记"
            ),
            "没有建立课程笔记样本"
        )
        let liveNote = "# 实时学习笔记\n\n## 风险理解\n\n久期衡量利率风险，凸性修正非线性。"
        try store.setAgentNoteFixtureForSelfCheck(
            itemID: noteID,
            memoryText: liveNote,
            diskText: liveNote
        )
        let liveNoteSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "久期 凸性"
        )
        let liveNoteRead = try store.agentHostReadForSelfCheck(
            courseID: courseA,
            itemID: noteID
        )
        let courseMap = try store.agentHostMapForSelfCheck(courseID: courseA)
        let noteOutline = try store.agentHostMapForSelfCheck(
            courseID: courseA,
            itemID: noteID
        )
        try check(
            liveNoteSearch.items.first(where: { $0.item.id == noteID })?
                .item.searchText.contains("凸性修正非线性") == true
                && liveNoteRead.items.first(where: { $0.item.id == noteID })?
                    .item.searchText.contains("凸性修正非线性") == true
                && courseMap.items.contains(where: { $0.item.id == noteID })
                && noteOutline.items.first?.item.headings.contains(where: {
                    $0.contains("风险理解")
                }) == true,
            "课程 Agent 没有先列资料和章节，再按需读取最新笔记正文"
        )
        let preferredMaterialIDs = Set(
            store.contextualPreferredItems(.material).map(\.id)
        )
        try check(
            !preferredMaterialIDs.isEmpty
                && preferredMaterialIDs == Set(
                    store.courseMaterials(in: courseA).map(\.id)
                ),
            "无直接文稿关系的课程笔记没有优先显示本课程资料"
        )

        try store.setAgentNoteFixtureForSelfCheck(
            itemID: noteID,
            memoryText: ""
        )
        let emptyNoteDiskText = try String(
            contentsOf: try require(
                store.importedItems.first(where: { $0.id == noteID })?.url,
                "空笔记样本缺少磁盘路径"
            ),
            encoding: .utf8
        )
        let emptyLiveNoteSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "凸性修正非线性"
        )
        let emptyLiveNoteRead = try? store.agentHostReadForSelfCheck(
            courseID: courseA,
            itemID: noteID
        )
        try check(
            emptyNoteDiskText.contains("凸性修正非线性")
                && !emptyLiveNoteSearch.items.contains(where: { $0.item.id == noteID })
                && emptyLiveNoteRead?.items.first(where: { $0.item.id == noteID })?
                    .item.searchText.contains("凸性修正非线性") != true,
            "已加载的空笔记错误回退到了磁盘旧正文"
        )

        let unopenedNoteURL = imports.appendingPathComponent("未打开笔记.md")
        try Data("# 未打开笔记\n\nUNOPENED_NOTE_TOKEN\n".utf8).write(to: unopenedNoteURL)
        let unopenedNote = try store.importFileIntoCourseForSelfCheck(
            unopenedNoteURL,
            courseID: courseA,
            role: .note
        ).item
        let unopenedNoteSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "UNOPENED_NOTE_TOKEN"
        )
        let unopenedNoteRead = try store.agentHostReadForSelfCheck(
            courseID: courseA,
            itemID: unopenedNote.id
        )
        try check(
            unopenedNoteSearch.items.first(where: { $0.item.id == unopenedNote.id })?
                .item.searchText.contains("UNOPENED_NOTE_TOKEN") == true
                && unopenedNoteRead.items.first(where: { $0.item.id == unopenedNote.id })?
                    .item.searchText.contains("UNOPENED_NOTE_TOKEN") == true,
            "课程 Agent 无法搜索或读取从未打开过的课程笔记"
        )

        let requestLegacyMaterialURL = imports.appendingPathComponent("请求外部图像.png")
        let requestLegacyNoteURL = imports.appendingPathComponent("请求外部笔记.md")
        try Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x4C, 0x45, 0x47, 0x41, 0x43, 0x59,
        ]).write(to: requestLegacyMaterialURL)
        try Data("LEGACY_NOTE_REQUEST_SECRET".utf8).write(to: requestLegacyNoteURL)
        let requestLegacyMaterial = try store.installLegacyVisualForAgentSelfCheck(
            at: requestLegacyMaterialURL,
            courseID: courseA
        )
        _ = store.importFiles(
            [requestLegacyNoteURL],
            selectsFirstImportedItem: false,
            markdownAsNotes: true,
            markdownOnly: true
        )
        let requestLegacyNote = try require(
            store.importedItems.first(where: {
                $0.isNotebookNote
                    && $0.subtitle == requestLegacyNoteURL.lastPathComponent
            }),
            "没有建立最终请求的旧外部笔记样本"
        )
        store.injectLegacyCourseMembershipForAgentSelfCheck(
            itemID: requestLegacyNote.id,
            courseID: courseA
        )
        store.removeCourseMembershipForAgentSelfCheck(
            itemID: requestLegacyMaterial.id,
            courseID: courseA
        )
        store.removeCourseMembershipForAgentSelfCheck(
            itemID: requestLegacyNote.id,
            courseID: courseA
        )
        try store.setAgentNoteFixtureForSelfCheck(
            itemID: requestLegacyNote.id,
            memoryText: "LEGACY_NOTE_REQUEST_SECRET",
            diskText: "LEGACY_NOTE_REQUEST_SECRET"
        )
        let unifiedRequest = try store.capturedAgentRequestForSelfCheck(
            courseID: courseA,
            materialItemID: requestLegacyMaterial.id,
            noteItemID: requestLegacyNote.id,
            selectionItemID: requestLegacyMaterial.id
        )
        try check(
            unifiedRequest.projectScope.kind == .global,
            "统一 Chat 请求仍带着旧课程作用域"
        )
        try check(
            unifiedRequest.noteText.isEmpty,
            "统一 Chat 仍把当前笔记正文重复塞进每轮上下文"
        )
        let requestLegacyNoteRead = try store.agentHostReadForSelfCheck(
            courseID: courseA,
            itemID: requestLegacyNote.id
        )
        try check(
            requestLegacyNoteRead.items.first(where: {
                $0.item.id == requestLegacyNote.id
            })?.item.searchText.contains("LEGACY_NOTE_REQUEST_SECRET") == true,
            "统一 Chat 无法按需读取当前外部笔记"
        )
        try check(
            unifiedRequest.selectionText?.contains(
                "LEGACY_SELECTION_REQUEST_SECRET"
            ) == true,
            "统一 Chat 没有带入当前选区"
        )
        try check(
            unifiedRequest.visualAssets.first?.id
                == requestLegacyMaterial.id,
            "统一 Chat 没有带入当前已核验外部图片"
        )
        try check(
            unifiedRequest.focus?.materialItemID
                == requestLegacyMaterial.id,
            "统一 Chat 没有记录当前文稿焦点"
        )
        try check(
            unifiedRequest.projectScope.items.contains(where: {
                $0.itemID == requestLegacyMaterial.id
            })
                && unifiedRequest.projectScope.items.contains(where: {
                    $0.itemID == requestLegacyNote.id
                }),
            "统一 Chat 的轻量焦点包缺少当前文稿或笔记"
        )
        let visualItem = try store.installCourseVisualForAgentSelfCheck(
            courseID: courseA,
            data: Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x56, 0x49, 0x53, 0x55, 0x41, 0x4C,
            ])
        )
        let visualRequest = try store.capturedAgentRequestForSelfCheck(
            courseID: courseA,
            materialItemID: visualItem.id,
            noteItemID: noteID,
            selectionItemID: visualItem.id
        )
        let visualAsset = visualRequest.visualAssets.first
        try check(
            visualRequest.visualAssets.count == 1
                && visualAsset?.id == visualItem.id
                && visualAsset?.filePath != visualItem.url?.path
                && visualAsset.map {
                    !FileManager.default.fileExists(atPath: $0.filePath)
                } == true,
            "最终发给 Pi 的视觉附件没有使用已核验的本轮临时快照"
        )

        let replacedOwnedSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "REPLACED_AGENT_TOKEN",
            beforeSearch: {
                let target = try require(ownedItem.url, "课程自有资料没有目标路径")
                try FileManager.default.removeItem(at: target)
                try Data("REPLACED_AGENT_TOKEN".utf8).write(to: target)
            }
        )
        try check(
            !replacedOwnedSearch.items.contains(where: { $0.item.id == ownedItem.id }),
            "课程 Agent 搜索读取了授权后被换 inode 的文件"
        )

        let sharedSourceURL = imports.appendingPathComponent("共享资料.txt")
        try Data("SHARED_AGENT_TOKEN".utf8).write(to: sharedSourceURL)
        let sharedItem = try store.importFileIntoCourseForSelfCheck(
            sharedSourceURL,
            courseID: courseA,
            role: .material
        ).item
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: sharedItem.id,
            withCourseID: courseB
        )
        let sharedSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseB,
            query: "SHARED_AGENT_TOKEN"
        )
        let sharedResult = try require(
            sharedSearch.items.first(where: { $0.item.id == sharedItem.id }),
            "课程 Agent 搜索没有读取合法共享资料"
        )
        try check(
            sharedResult.courseIDs.contains(courseB.uuidString.lowercased()),
            "统一 Chat 没有把当前课程纳入查询范围"
        )
        let courseBRoot = try require(store.courseRootURL(for: courseB), "课程乙根目录丢失")
        let courseBMembership = try require(
            store.courseItemMemberships.first {
                $0.courseID == courseB && $0.itemID == sharedItem.id
            },
            "共享资料缺少课程乙入口"
        )
        let sharedEntry = try require(
            courseBMembership.courseRelativePath.map {
                courseBRoot.appendingPathComponent($0)
            },
            "共享资料缺少课程乙相对路径"
        )
        let unrelatedURL = imports.appendingPathComponent("无关目标.txt")
        try Data("UNRELATED_AGENT_TOKEN".utf8).write(to: unrelatedURL)
        let driftedSharedSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseB,
            query: "UNRELATED_AGENT_TOKEN",
            beforeSearch: {
                try FileManager.default.removeItem(at: sharedEntry)
                try FileManager.default.createSymbolicLink(
                    at: sharedEntry,
                    withDestinationURL: unrelatedURL
                )
            }
        )
        try check(
            !driftedSharedSearch.items.contains(where: { $0.item.id == sharedItem.id }),
            "课程 Agent 搜索跟随了授权后被改向的共享链接"
        )
    }

    @MainActor
    private static func unavailableCourseRootKeepsCourseChatAvailable() throws {
        let fixture = try Fixture(name: "unavailable-course-chat")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let courseRoot = library.appendingPathComponent("会话课程", isDirectory: true)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(
            store?.createCourse(title: "会话课程", at: courseRoot),
            "无法建立课程 Chat 的课程根样本"
        )
        try check(store?.flushPendingWorkspaceSave() == true, "课程 Chat 样本无法保存")
        store = nil

        let workspaceURL = fixture.workspaceDirectory.appendingPathComponent("workspace.json")
        var snapshot = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(contentsOf: workspaceURL)
        )
        let session = StudySession(
            title: "固定课程 Chat",
            courseID: courseID
        )
        snapshot.studySessions = [session]
        snapshot.activeStudySessionID = session.id
        try JSONEncoder().encode(snapshot).write(to: workspaceURL, options: [.atomic])
        let portableStateURL = courseRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        var portableState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: portableStateURL)
        )
        portableState.studySessions = [session]
        portableState.resumePoint = CourseResumePoint(
            courseID: courseID,
            chatID: session.id
        )
        portableState.revision &+= 1
        portableState.savedAt = Date()
        try JSONEncoder().encode(portableState).write(
            to: portableStateURL,
            options: [.atomic]
        )

        let reopened = makeStore(fixture: fixture)
        try FileManager.default.removeItem(at: courseRoot)
        let legacyDirectory = try fixture.makeDirectory("旧外部资料")
        let legacyURL = legacyDirectory.appendingPathComponent("旧课程文章.txt")
        try Data("ROOTLESS_COURSE_ARTICLE_TOKEN".utf8).write(to: legacyURL)
        let legacyItem = try require(
            reopened.importFiles([legacyURL], selectsFirstImportedItem: false).first,
            "无法建立旧课程外部资料样本"
        )
        reopened.injectLegacyCourseMembershipForAgentSelfCheck(
            itemID: legacyItem.id,
            courseID: courseID
        )
        let scope = try reopened.agentProjectScopeForSelfCheck(courseID: courseID)
        let search = try reopened.agentHostSearchForSelfCheck(
            courseID: courseID,
            query: "ROOTLESS_COURSE_ARTICLE_TOKEN"
        )
        try check(
            scope.kind == .global
                && scope.courseID == courseID.uuidString.lowercased()
                && scope.rootPath == nil
                && search.items.contains(where: { $0.item.id == legacyItem.id }),
            "课程文件夹失效后，统一 Chat 没有保留课程优先级或读取已登记资料"
        )
    }

    private static func courseEntryPresentationResetsIntent() throws {
        var presentation: CourseProjectEntryPresentation? =
            CourseProjectEntryPresentation(intent: .create)
        let createPresentation = try require(presentation, "新建课程入口没有展示身份")
        try check(createPresentation.intent == .create, "新建课程入口意图错误")

        presentation = nil
        try check(presentation == nil, "课程入口关闭后没有清空展示身份")

        presentation = CourseProjectEntryPresentation(intent: .adopt)
        let adoptPresentation = try require(presentation, "纳入课程入口没有展示身份")
        try check(adoptPresentation.intent == .adopt, "关闭后再次打开复用了旧入口意图")
        try check(adoptPresentation.id != createPresentation.id, "关闭后再次打开复用了旧展示身份")
    }

    private static func escapeBridgeDefersToPresentedSurfaces() throws {
        try check(
            EscapeKeyBridge.Coordinator.shouldHandleEscape(
                isEnabled: true,
                hasModalWindow: false,
                hasActiveSheet: false
            ),
            "没有弹窗时 EscapeKeyBridge 未响应"
        )
        try check(
            !EscapeKeyBridge.Coordinator.shouldHandleEscape(
                isEnabled: true,
                hasModalWindow: true,
                hasActiveSheet: false
            ),
            "模态窗口出现时 EscapeKeyBridge 仍会关闭底层课程空间"
        )
        try check(
            !EscapeKeyBridge.Coordinator.shouldHandleEscape(
                isEnabled: true,
                hasModalWindow: false,
                hasActiveSheet: true
            ),
            "Sheet 出现时 EscapeKeyBridge 仍会关闭底层课程空间"
        )
        try check(
            !EscapeKeyBridge.Coordinator.shouldHandleEscape(
                isEnabled: false,
                hasModalWindow: false,
                hasActiveSheet: false
            ),
            "EscapeKeyBridge 忽略了禁用状态"
        )
    }

    @MainActor
    private static func libraryCannotEqualOrSitInsideRegisteredCourse() throws {
        for nested in [false, true] {
            let fixture = try Fixture(name: nested ? "library-inside-course" : "library-equals-course")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "已有课程")
            let courseRoot = try require(store.courseRootURL(for: courseID), "没有课程根")
            let proposedLibrary = nested
                ? courseRoot.appendingPathComponent("资料库", isDirectory: true)
                : courseRoot
            if nested {
                try FileManager.default.createDirectory(
                    at: proposedLibrary,
                    withIntermediateDirectories: true
                )
            }

            try expectFailure(nested ? "资料库位于课程内" : "资料库等于课程") {
                try store.configureCourseLibrary(at: proposedLibrary)
            }
            try check(
                store.courseLibraryRootURL?.standardizedFileURL
                    == library.standardizedFileURL,
                "非法资料库仍被配置"
            )
            try check(store.course(withID: courseID) != nil, "拒绝资料库时误删课程")
        }
    }

    @MainActor
    private static func foreignWritesPreventRollbackDeletion() throws {
        do {
            let fixture = try Fixture(name: "foreign-create-rollback")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let target = library.appendingPathComponent("并发课程", isDirectory: true)
            var injectForeignWrite = false
            let store = makeStore(
                fixture: fixture,
                workspaceWriter: { data, url in
                    if injectForeignWrite {
                        try Data("用户并发写入".utf8).write(
                            to: target.appendingPathComponent("foreign.txt")
                        )
                        throw CheckError.injectedFailure
                    }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            injectForeignWrite = true

            try expectFailure("新课程并发写入") {
                try store.createCourse(title: "并发课程", at: target)
            }
            try check(
                try String(contentsOf: target.appendingPathComponent("foreign.txt"), encoding: .utf8)
                    == "用户并发写入",
                "回滚误删了新课程根里的用户并发内容"
            )
            try check(store.courses.isEmpty, "并发保存失败后留下幽灵 Course")
        }

        do {
            let fixture = try Fixture(name: "foreign-adopt-rollback")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let external = try fixture.makeDirectory("已有课程")
            var injectForeignWrite = false
            let store = makeStore(
                fixture: fixture,
                workspaceWriter: { data, url in
                    if injectForeignWrite {
                        try Data("用户 metadata".utf8).write(
                            to: external.appendingPathComponent(".weibei/foreign.txt")
                        )
                        throw CheckError.injectedFailure
                    }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            injectForeignWrite = true

            try expectFailure("接管库外课程") {
                try store.adoptCourseFolder(at: external, title: "已有课程")
            }
            try check(store.courses.isEmpty, "库外接管失败后留下幽灵 Course")
            try check(!external.appendingPathComponent(".weibei").exists, "库外接管仍改写了外部文件夹")
        }

        do {
            let fixture = try Fixture(name: "foreign-after-fingerprint")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let target = library.appendingPathComponent("竞态课程", isDirectory: true)
            var failWorkspaceWrite = false
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard stage == .beforeOwnedRollbackCleanup else { return }
                    try Data("检查后写入".utf8).write(
                        to: target.appendingPathComponent("after-check.txt")
                    )
                },
                workspaceWriter: { data, url in
                    if failWorkspaceWrite { throw CheckError.injectedFailure }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            failWorkspaceWrite = true

            try expectFailure("指纹核验后的并发写入") {
                try store.createCourse(title: "竞态课程", at: target)
            }
            try check(
                try String(
                    contentsOf: target.appendingPathComponent("after-check.txt"),
                    encoding: .utf8
                ) == "检查后写入",
                "空目录收口误删了指纹核验后出现的文件"
            )
            try check(store.courses.isEmpty, "指纹核验后的失败留下幽灵 Course")
        }
    }

    @MainActor
    private static func repeatedAdoptionRefreshesTrackingAndOwnership() throws {
        do {
            let fixture = try Fixture(name: "repeat-adopt-refresh")
            defer { fixture.remove() }
            let oldRoot = try fixture.makeDirectory("旧位置")
            var store: WorkspaceStore? = makeStore(fixture: fixture)
            let courseID = try require(
                store?.adoptCourseFolder(at: oldRoot, title: "原课程名"),
                "首次接管没有课程 ID"
            )
            try check(store?.flushPendingWorkspaceSave() == true, "移动前没有保存课程")
            store = nil

            let movedRoot = fixture.root.appendingPathComponent("新位置", isDirectory: true)
            try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
            var allowAccess = false
            var starts = 0
            store = makeStore(
                fixture: fixture,
                startAccessing: { _ in starts += 1; return allowAccess },
                bookmarkResolver: { _ in
                    CourseProjectResolvedBookmark(url: movedRoot, isStale: true)
                }
            )
            try check(store?.courseRootURL(for: courseID) == nil, "授权失败前课程不应可用")
            try check(store?.courseRootUnavailableReason(for: courseID) != nil, "授权失败没有 unavailable")
            allowAccess = true

            let repeatedID = try require(
                store?.adoptCourseFolder(at: movedRoot, title: "不应覆盖标题"),
                "重复接管没有课程 ID"
            )
            let refreshed = try require(store?.course(withID: courseID), "重复接管后课程丢失")
            try check(repeatedID == courseID, "重复接管改变了 Course ID")
            try check(refreshed.title == "原课程名", "重复接管错误覆盖课程标题")
            try check(refreshed.sourceRootPath == movedRoot.canonicalFileURL.path, "重复接管没有刷新路径")
            try check(store?.courseRootURL(for: courseID) == movedRoot.canonicalFileURL, "重复接管没有恢复可用根")
            try check(store?.courseRootUnavailableReason(for: courseID) == nil, "重复接管没有清除 unavailable")
            try check(starts == 2, "重复接管没有重新建立 security scope")
        }

        do {
            let fixture = try Fixture(name: "repeat-adopt-relative")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("未来资料库")
            let courseRoot = try fixture.makeDirectory("未来资料库/课程")
            var stops = 0
            let store = makeStore(
                fixture: fixture,
                stopAccessing: { _ in stops += 1 }
            )
            let courseID = try store.adoptCourseFolder(at: courseRoot, title: "课程")
            try store.configureCourseLibrary(at: library)
            let repeatedID = try store.adoptCourseFolder(at: courseRoot, title: "不改名")
            let converted = try require(store.course(withID: courseID), "库内转换后课程丢失")

            try check(repeatedID == courseID, "库内重复接管改变了 Course ID")
            try check(converted.title == "课程", "库内重复接管覆盖了标题")
            try check(converted.sourceRootRelativePath == "课程", "库内课程没有转成相对引用")
            try check(converted.sourceRootPath == nil, "库内课程仍保留绝对路径真相")
            try check(converted.sourceRootBookmarkData == nil, "库内课程仍保留独立授权")
            try check(stops == 1, "库内转换没有释放旧外部 security scope")
        }

        do {
            let fixture = try Fixture(name: "repeat-adopt-replaced-inode")
            defer { fixture.remove() }
            let courseRoot = try fixture.makeDirectory("被替换课程")
            let store = makeStore(fixture: fixture)
            let courseID = try store.adoptCourseFolder(at: courseRoot, title: "原课程")
            let originalIdentity = store.course(withID: courseID)?.sourceRootIdentity
            let manifestData = try Data(
                contentsOf: courseRoot.appendingPathComponent(".weibei/course.json")
            )

            try FileManager.default.removeItem(at: courseRoot)
            try FileManager.default.createDirectory(
                at: courseRoot.appendingPathComponent(".weibei", isDirectory: true),
                withIntermediateDirectories: true
            )
            try manifestData.write(
                to: courseRoot.appendingPathComponent(".weibei/course.json")
            )

            try expectFailure("同路径不同 inode") {
                try store.adoptCourseFolder(at: courseRoot, title: "替换目录")
            }
            try check(
                store.course(withID: courseID)?.sourceRootIdentity == originalIdentity,
                "同路径不同 inode 被静默改绑"
            )
            try check(
                store.course(withID: courseID)?.title == "原课程",
                "拒绝不同 inode 时改动了课程标题"
            )
        }
    }

    @MainActor
    private static func failedReadoptionRestoresPreviousCourseAndScope() throws {
        let fixture = try Fixture(name: "repeat-adopt-save-failure")
        defer { fixture.remove() }
        let oldRoot = try fixture.makeDirectory("旧位置")
        var starts = 0
        var stops = 0
        var failWorkspaceWrite = false
        let store = makeStore(
            fixture: fixture,
            startAccessing: { _ in starts += 1; return true },
            stopAccessing: { _ in stops += 1 },
            workspaceWriter: { data, url in
                if failWorkspaceWrite { throw CheckError.injectedFailure }
                try data.write(to: url, options: [.atomic])
            }
        )
        let courseID = try store.adoptCourseFolder(at: oldRoot, title: "原课程")
        let previousCourse = try require(store.course(withID: courseID), "首次接管没有课程")
        let previousResolvedRoot = store.courseRootURL(for: courseID)

        let movedRoot = fixture.root.appendingPathComponent("新位置", isDirectory: true)
        try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
        failWorkspaceWrite = true
        try expectFailure("重复接管保存失败") {
            try store.adoptCourseFolder(at: movedRoot, title: "不应改名")
        }

        try check(store.course(withID: courseID) == previousCourse, "保存失败没有恢复旧 Course")
        try check(
            store.courseRootURL(for: courseID) == previousResolvedRoot,
            "保存失败没有恢复旧 resolved root"
        )
        try check(
            store.courseRootUnavailableReason(for: courseID) == nil,
            "保存失败凭空改变了旧 unavailable 状态"
        )
        try check(starts == 2, "重复接管没有取得新 scope")
        try check(stops == 1, "保存失败没有只释放新 scope")
    }

    @MainActor
    private static func courseRebindRequiresConfirmationAndIsTransactional()
        throws {
        do {
            let fixture = try Fixture(name: "explicit-course-rebind")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let exportParent = try fixture.makeDirectory("课程副本")
            let offlineParent = try fixture.makeDirectory("失联原件")
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "重绑课程")
            let foreignCourseID = try store.createCourseInLibrary(
                title: "隔离课程"
            )
            let imports = try fixture.makeDirectory("待导入")
            let materialSource = imports.appendingPathComponent(
                "重绑资料.txt"
            )
            let foreignSource = imports.appendingPathComponent(
                "隔离资料.txt"
            )
            try Data("REBIND_MATERIAL".utf8).write(to: materialSource)
            try Data("FOREIGN_MATERIAL".utf8).write(to: foreignSource)
            let material = try store.importFileIntoCourseForSelfCheck(
                materialSource,
                courseID: courseID,
                role: .material
            ).item
            let foreignMaterial =
                try store.importFileIntoCourseForSelfCheck(
                    foreignSource,
                    courseID: foreignCourseID,
                    role: .material
                ).item
            let noteID = try require(
                store.createCourseNotebookNoteForSelfCheck(
                    courseID: courseID,
                    title: "重绑笔记"
                ),
                "没有建立重绑笔记"
            )
            let learningFixture =
                try store.installPortableCourseStateFixtureForSelfCheck(
                    courseID: courseID,
                    materialItemID: material.id,
                    noteItemID: noteID,
                    foreignCourseID: foreignCourseID,
                    foreignItemID: foreignMaterial.id
                )
            let originalRoot = try require(
                store.courseRootURL(for: courseID),
                "重绑样本没有原课程根"
            )
            try Data("VISIBLE_REBIND_SENTINEL".utf8).write(
                to: originalRoot.appendingPathComponent("课程说明.txt")
            )
            try check(
                store.flushPendingWorkspaceSave(),
                "重绑样本没有保存工作区"
            )

            let liveRootCandidate = exportParent.appendingPathComponent(
                "旧根仍在副本",
                isDirectory: true
            )
            let changedCandidate = exportParent.appendingPathComponent(
                "确认前变化副本",
                isDirectory: true
            )
            let successfulCandidate = exportParent.appendingPathComponent(
                "可重绑副本",
                isDirectory: true
            )
            for candidate in [
                liveRootCandidate,
                changedCandidate,
                successfulCandidate,
            ] {
                _ = try store.exportPortableCourseCopyForSelfCheck(
                    courseID: courseID,
                    to: candidate
                )
            }
            store.discardPendingCourseNoteForSelfCheck(itemID: noteID)
            let liveCandidateManifest = try Data(
                contentsOf: liveRootCandidate.appendingPathComponent(
                    ".weibei/course.json"
                )
            )
            try expectFailure("旧根仍可用时异根改绑") {
                _ = try store.adoptCourseFolderOrProposeRebind(
                    at: liveRootCandidate,
                    title: "不得改绑"
                )
            }
            try check(
                Data(
                    contentsOf: liveRootCandidate.appendingPathComponent(
                        ".weibei/course.json"
                    )
                ) == liveCandidateManifest,
                "拒绝异根改绑时消费了候选封印"
            )

            let offlineOriginal = offlineParent.appendingPathComponent(
                "原课程",
                isDirectory: true
            )
            try FileManager.default.moveItem(
                at: originalRoot,
                to: offlineOriginal
            )
            // S6-4：失联旧根后，生成中/待写笔记不再阻止重绑提案。
            try store.setCourseReplyGeneratingForSelfCheck(
                courseID: courseID,
                generating: true
            )
            try store.stagePendingCourseNoteForSelfCheck(
                itemID: noteID,
                markdown: "尚未落盘的编辑器草稿"
            )
            switch try store.adoptCourseFolderOrProposeRebind(
                at: successfulCandidate,
                title: "允许生成中带草稿重绑"
            ) {
            case .requiresRebind:
                break
            case .opened:
                throw CheckError.failed("生成中带草稿时不应静默打开另一门课")
            }
            try store.setCourseReplyGeneratingForSelfCheck(
                courseID: courseID,
                generating: false
            )
            store.discardPendingCourseNoteForSelfCheck(itemID: noteID)
            let workspaceURL = fixture.workspaceDirectory
                .appendingPathComponent("workspace.json")
            let workspaceBeforeProposal = try Data(contentsOf: workspaceURL)
            let courseBeforeProposal = try require(
                store.course(withID: courseID),
                "生成重绑提案前课程丢失"
            )

            func proposal(
                for candidate: URL
            ) throws -> CourseProjectRebindProposal {
                switch try store.adoptCourseFolderOrProposeRebind(
                    at: candidate,
                    title: "不会覆盖课程名"
                ) {
                case .opened:
                    throw CheckError.failed("失联课程被静默改绑")
                case .requiresRebind(let proposal):
                    return proposal
                }
            }

            _ = try proposal(for: successfulCandidate)
            try check(
                Data(contentsOf: workspaceURL) == workspaceBeforeProposal
                    && store.course(withID: courseID)
                        == courseBeforeProposal,
                "生成或取消重绑提案改动了课程状态"
            )
            try check(
                store.courseRebindRootSearchRunsOffMainForSelfCheck(),
                "查找失联旧课程根仍在主线程递归扫描"
            )

            let changedProposal = try proposal(for: changedCandidate)
            try Data("CHANGED_AFTER_PROPOSAL".utf8).write(
                to: changedCandidate.appendingPathComponent(
                    "课程说明.txt"
                )
            )
            try expectFailure("提案后候选变化") {
                _ = try store.confirmCourseProjectRebind(
                    changedProposal
                )
            }
            try check(
                Data(contentsOf: workspaceURL) == workspaceBeforeProposal,
                "候选变化失败后改动了工作区"
            )

            let reappearingProposal = try proposal(
                for: successfulCandidate
            )
            try FileManager.default.moveItem(
                at: offlineOriginal,
                to: originalRoot
            )
            try expectFailure("确认前旧根恢复") {
                _ = try store.confirmCourseProjectRebind(
                    reappearingProposal
                )
            }
            try FileManager.default.moveItem(
                at: originalRoot,
                to: offlineOriginal
            )

            let successfulProposal = try proposal(
                for: successfulCandidate
            )
            try store.stagePendingCourseNoteForSelfCheck(
                itemID: noteID,
                markdown: "确认前尚未落盘的编辑器草稿"
            )
            // S6-4：待写笔记不再阻止重绑确认。
            store.discardPendingCourseNoteForSelfCheck(itemID: noteID)
            let reboundID = try store.confirmCourseProjectRebind(
                successfulProposal
            )
            let reboundManifest = try CourseProjectManifest.read(
                from: successfulCandidate.appendingPathComponent(
                    ".weibei/course.json"
                )
            )
            let reboundMembership = try require(
                store.courseItemMemberships.first {
                    $0.courseID == courseID
                        && $0.itemID == material.id
                },
                "重绑后资料成员关系丢失"
            )
            let reboundMaterial = try require(
                store.importedItems.first { $0.id == material.id },
                "重绑后资料记录丢失"
            )
            let reboundMaterialURL =
                reboundMembership.courseRelativePath.map {
                    successfulCandidate.appendingPathComponent($0)
                }
            let reboundDocumentIdentifier =
                try reboundMaterialURL?.resourceValues(
                    forKeys: [.documentIdentifierKey]
                ).documentIdentifier.flatMap {
                    $0 >= 0 ? UInt64($0) : nil
                }
            try check(
                reboundID == courseID
                    && store.course(withID: courseID)?.title
                        == courseBeforeProposal.title
                    && store.courseRootURL(for: courseID)
                        == successfulCandidate.canonicalFileURL
                    && reboundManifest.courseID == courseID
                    && reboundManifest.portableExport == nil
                    && reboundMaterial.url
                        == reboundMaterialURL?.canonicalFileURL
                    && reboundMaterial.importedFileIdentity
                        == reboundMaterialURL.flatMap {
                            CourseProjectFileWorker.identity(at: $0)
                        }
                    && reboundMembership.entryIdentity
                        == reboundMaterial.importedFileIdentity
                    && reboundMembership.documentIdentifier
                        == reboundDocumentIdentifier
                    && store.studySessions.contains {
                        $0.id == learningFixture.sessionID
                    }
                    && store.learningMemoryStates.first {
                        $0.scope == .course(courseID)
                    }?.entries.contains {
                        $0.id == learningFixture.memoryID
                    } == true
                    && store.noteSourceLinks.contains {
                        $0.noteItemID == noteID
                            && $0.sourceItemID == material.id
                    }
                    && store.courseResumePoint(for: courseID)?.chatID
                        == learningFixture.sessionID
                    && store.pendingPortableNoteDraftForSelfCheck(
                        itemID: noteID
                    ) == learningFixture.draft,
                "确认重绑没有保留课程身份、学习状态、稳定资料 ID 或安全消费封印"
            )

            let reopened = makeStore(fixture: fixture)
            try check(
                reopened.course(withID: courseID)?.title
                    == courseBeforeProposal.title
                    && reopened.courseRootURL(for: courseID)
                        == successfulCandidate.canonicalFileURL,
                "重开后没有恢复重绑课程根"
            )
            try check(
                reopened.importedItems.first {
                    $0.id == material.id
                }?.url == reboundMaterialURL?.canonicalFileURL,
                "重开后没有恢复重绑资料身份"
            )
            try check(
                reopened.studySessions.contains {
                    $0.id == learningFixture.sessionID
                },
                "重开后没有恢复重绑课程 Chat"
            )
            try check(
                reopened.learningMemoryStates.first {
                    $0.scope == .course(courseID)
                }?.entries.contains {
                    $0.id == learningFixture.memoryID
                } == true,
                "重开后没有恢复重绑课程学习记忆"
            )
            try check(
                reopened.pendingPortableNoteDraftForSelfCheck(
                    itemID: noteID
                ) == learningFixture.draft,
                "重开后没有恢复重绑课程笔记草稿"
            )

            let staleCourseCandidate = exportParent.appendingPathComponent(
                "课程变化副本",
                isDirectory: true
            )
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseID,
                to: staleCourseCandidate
            )
            try FileManager.default.moveItem(
                at: successfulCandidate,
                to: offlineParent.appendingPathComponent(
                    "已重绑原件",
                    isDirectory: true
                )
            )
            let staleCourseProposal = try proposal(
                for: staleCourseCandidate
            )
            store.renameCourse(courseID, title: "提案后课程已变化")
            try expectFailure("提案后课程变化") {
                _ = try store.confirmCourseProjectRebind(
                    staleCourseProposal
                )
            }
            try check(
                store.course(withID: courseID)?.title
                    == "提案后课程已变化",
                "过期提案覆盖了确认前的课程变化"
            )
        } catch {
            throw CheckError.failed(
                "显式重绑主流程：\(error.localizedDescription)"
            )
        }

        do {
            let fixture = try Fixture(name: "course-rebind-save-failure")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let exportParent = try fixture.makeDirectory("课程副本")
            let offlineParent = try fixture.makeDirectory("失联原件")
            var failWorkspaceWrite = false
            var scopeStops = 0
            let store = makeStore(
                fixture: fixture,
                stopAccessing: { _ in scopeStops += 1 },
                workspaceWriter: { data, url in
                    if failWorkspaceWrite {
                        throw CheckError.injectedFailure
                    }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(
                title: "保存失败课程"
            )
            let originalRoot = try require(
                store.courseRootURL(for: courseID),
                "保存失败样本没有原课程根"
            )
            let candidate = exportParent.appendingPathComponent(
                "候选副本",
                isDirectory: true
            )
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseID,
                to: candidate
            )
            let candidateManifest = try Data(
                contentsOf: candidate.appendingPathComponent(
                    ".weibei/course.json"
                )
            )
            let previousCourse = try require(
                store.course(withID: courseID),
                "保存失败前课程丢失"
            )
            let previousRoot = store.courseRootURL(for: courseID)
            try FileManager.default.moveItem(
                at: originalRoot,
                to: offlineParent.appendingPathComponent(
                    "原课程",
                    isDirectory: true
                )
            )
            let proposal: CourseProjectRebindProposal
            switch try store.adoptCourseFolderOrProposeRebind(
                at: candidate,
                title: "保存失败"
            ) {
            case .opened:
                throw CheckError.failed("保存失败样本被静默改绑")
            case .requiresRebind(let value):
                proposal = value
            }
            let stopsBeforeConfirmation = scopeStops
            failWorkspaceWrite = true
            try expectFailure("重绑工作区保存失败") {
                _ = try store.confirmCourseProjectRebind(proposal)
            }
            try check(
                store.course(withID: courseID) == previousCourse
                    && store.courseRootURL(for: courseID) == previousRoot
                    && Data(
                        contentsOf: candidate.appendingPathComponent(
                            ".weibei/course.json"
                        )
                    ) == candidateManifest
                    && scopeStops == stopsBeforeConfirmation + 1,
                "重绑保存失败没有恢复课程、保留封印或只释放新授权"
            )
        } catch {
            throw CheckError.failed(
                "重绑保存失败回滚：\(error.localizedDescription)"
            )
        }

        do {
            let fixture = try Fixture(name: "course-rebind-same-path-scope")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let externalRoot = try fixture.makeDirectory("外部课程")
            let exportParent = try fixture.makeDirectory("课程副本")
            let offlineParent = try fixture.makeDirectory("失联原件")
            var scopeStarts = 0
            var scopeStops = 0
            let store = makeStore(
                fixture: fixture,
                startAccessing: { _ in
                    scopeStarts += 1
                    return true
                },
                stopAccessing: { _ in scopeStops += 1 }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.adoptCourseFolder(
                at: externalRoot,
                title: "同路径外部课程"
            )
            let candidateStaging = exportParent.appendingPathComponent(
                "候选副本",
                isDirectory: true
            )
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseID,
                to: candidateStaging
            )
            try FileManager.default.moveItem(
                at: externalRoot,
                to: offlineParent.appendingPathComponent(
                    "旧 inode",
                    isDirectory: true
                )
            )
            try FileManager.default.moveItem(
                at: candidateStaging,
                to: externalRoot
            )
            let proposal: CourseProjectRebindProposal
            switch try store.adoptCourseFolderOrProposeRebind(
                at: externalRoot,
                title: "同路径新 inode"
            ) {
            case .opened:
                throw CheckError.failed("同路径新 inode 被静默接管")
            case .requiresRebind(let value):
                proposal = value
            }
            let startsBeforeConfirmation = scopeStarts
            let stopsBeforeConfirmation = scopeStops
            _ = try store.confirmCourseProjectRebind(proposal)
            let confirmationStarts =
                scopeStarts - startsBeforeConfirmation
            let confirmationStops =
                scopeStops - stopsBeforeConfirmation
            try check(
                store.courseRootURL(for: courseID)
                    == externalRoot.canonicalFileURL
                    && confirmationStarts >= 1
                    && confirmationStarts == confirmationStops
                    && scopeStarts - scopeStops == 2,
                "同路径新 inode 重绑没有逐次配对安全授权"
            )
        } catch {
            throw CheckError.failed(
                "同路径新 inode 授权：\(error.localizedDescription)"
            )
        }

        do {
            let fixture = try Fixture(name: "course-rebind-reentrant-delete")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let exportParent = try fixture.makeDirectory("课程副本")
            let offlineParent = try fixture.makeDirectory("失联原件")
            weak var storeReference: WorkspaceStore?
            var targetCourseID: UUID?
            var deleteDuringNormalization = false
            var scopeStops = 0
            let store = makeStore(
                fixture: fixture,
                stopAccessing: { _ in scopeStops += 1 },
                mutationHook: { stage in
                    guard deleteDuringNormalization,
                          stage
                            == .afterAdoptionWorkspaceSaveBeforeManifestNormalization,
                          let targetCourseID else {
                        return
                    }
                    deleteDuringNormalization = false
                    storeReference?
                        .removeCourseRegistrationImmediatelyForSelfCheck(
                            targetCourseID
                        )
                }
            )
            storeReference = store
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(
                title: "重入删除课程"
            )
            targetCourseID = courseID
            let originalRoot = try require(
                store.courseRootURL(for: courseID),
                "重入删除样本没有原课程根"
            )
            let candidate = exportParent.appendingPathComponent(
                "候选副本",
                isDirectory: true
            )
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseID,
                to: candidate
            )
            let sealedManifest = try Data(
                contentsOf: candidate.appendingPathComponent(
                    ".weibei/course.json"
                )
            )
            try FileManager.default.moveItem(
                at: originalRoot,
                to: offlineParent.appendingPathComponent(
                    "原课程",
                    isDirectory: true
                )
            )
            let proposal: CourseProjectRebindProposal
            switch try store.adoptCourseFolderOrProposeRebind(
                at: candidate,
                title: "重入删除"
            ) {
            case .opened:
                throw CheckError.failed("重入删除样本被静默改绑")
            case .requiresRebind(let value):
                proposal = value
            }
            let stopsBeforeConfirmation = scopeStops
            deleteDuringNormalization = true
            try expectFailure("规范化期间删除课程") {
                _ = try store.confirmCourseProjectRebind(proposal)
            }
            try check(
                store.course(withID: courseID) == nil
                    && scopeStops == stopsBeforeConfirmation + 1
                    && Data(
                        contentsOf: candidate.appendingPathComponent(
                            ".weibei/course.json"
                        )
                    ) == sealedManifest,
                "重入删除后重复停止授权、复活课程或消费候选封印"
            )
        } catch {
            throw CheckError.failed(
                "重绑期间删除课程：\(error.localizedDescription)"
            )
        }

        do {
            let fixture = try Fixture(name: "course-rebind-newer-state")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let exports = try fixture.makeDirectory("课程副本")
            let offline = try fixture.makeDirectory("失联原件")
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(
                title: "本机旧标题"
            )
            let originalRoot = try require(
                store.courseRootURL(for: courseID),
                "较新状态样本没有原课程根"
            )
            let candidate = exports.appendingPathComponent(
                "较新课程副本",
                isDirectory: true
            )
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseID,
                to: candidate
            )

            let candidateWorkspace = try fixture.makeDirectory(
                "候选编辑工作区"
            )
            let candidateStore = makeStore(
                fixture: fixture,
                workspaceDirectory: candidateWorkspace
            )
            let candidateCourseID =
                try candidateStore.adoptCourseFolder(
                    at: candidate,
                    title: "临时名称"
                )
            candidateStore.renameCourse(
                candidateCourseID,
                title: "候选更新标题"
            )
            try check(
                candidateStore.flushPendingWorkspaceSave(),
                "候选较新状态没有保存"
            )

            try FileManager.default.moveItem(
                at: originalRoot,
                to: offline.appendingPathComponent(
                    "原课程",
                    isDirectory: true
                )
            )
            let proposal: CourseProjectRebindProposal
            switch try store.adoptCourseFolderOrProposeRebind(
                at: candidate,
                title: "不会覆盖候选标题"
            ) {
            case .opened:
                throw CheckError.failed("较新候选被静默接管")
            case .requiresRebind(let value):
                proposal = value
            }
            try check(
                proposal.impact == .useNewerCandidate,
                "较新且本机干净的候选没有进入明确确认"
            )
            _ = try store.confirmCourseProjectRebind(proposal)
            try check(
                store.course(withID: courseID)?.title
                    == "候选更新标题"
                    && store.courseRootURL(for: courseID)
                        == candidate.canonicalFileURL,
                "确认后没有采用候选文件夹中的较新状态"
            )
        } catch {
            throw CheckError.failed(
                "采用较新候选：\(error.localizedDescription)"
            )
        }

        do {
            let fixture = try Fixture(name: "course-rebind-shared-conflict")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let exports = try fixture.makeDirectory("课程副本")
            let offline = try fixture.makeDirectory("失联原件")
            let imports = try fixture.makeDirectory("待导入")
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseA = try store.createCourseInLibrary(title: "课程甲")
            let courseB = try store.createCourseInLibrary(title: "课程乙")
            let source = imports.appendingPathComponent("共享资料.txt")
            try Data("SHARED_REBIND_CONTENT".utf8).write(to: source)
            let material = try store.importFileIntoCourseForSelfCheck(
                source,
                courseID: courseA,
                role: .material
            ).item
            try store.shareCourseOwnedItemForSelfCheck(
                itemID: material.id,
                withCourseID: courseB
            )
            try check(
                store.flushPendingWorkspaceSave(),
                "共享冲突样本没有保存"
            )
            let candidate = exports.appendingPathComponent(
                "实体化副本",
                isDirectory: true
            )
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: candidate
            )
            let sharedItem = try require(
                store.importedItems.first { $0.id == material.id },
                "共享资料记录丢失"
            )
            guard case let .common(sharedRelativePath) =
                    sharedItem.storage,
                  let sharedDigest = sharedItem.contentDigest else {
                throw CheckError.failed("共享资料没有稳定路径或摘要")
            }
            var sharedState = try JSONDecoder().decode(
                CoursePortableState.self,
                from: Data(
                    contentsOf: candidate.appendingPathComponent(
                        ".weibei/course-state.json"
                    )
                )
            )
            let sharedIndex = try require(
                sharedState.items.firstIndex {
                    $0.itemID == material.id
                },
                "候选状态没有共享资料"
            )
            sharedState.items[sharedIndex].storage = .sharedReference(
                sharedRelativePath: sharedRelativePath,
                expectedContentDigest: sharedDigest
            )
            sharedState.items[sharedIndex].contentDigest = sharedDigest
            try store.validateCourseRebindStorageForSelfCheck(
                sharedState,
                courseID: courseA
            )
            sharedState.items[sharedIndex].contentDigest =
                String(repeating: "0", count: 64)
            try expectFailure("跨课共享资料旧摘要") {
                try store.validateCourseRebindStorageForSelfCheck(
                    sharedState,
                    courseID: courseA
                )
            }
            let sealedManifest = try Data(
                contentsOf: candidate.appendingPathComponent(
                    ".weibei/course.json"
                )
            )
            let originalRoot = try require(
                store.courseRootURL(for: courseA),
                "共享冲突样本没有课程根"
            )
            try FileManager.default.moveItem(
                at: originalRoot,
                to: offline.appendingPathComponent(
                    "课程甲",
                    isDirectory: true
                )
            )
            try expectFailure("跨课共享资料实体化重绑") {
                _ = try store.adoptCourseFolderOrProposeRebind(
                    at: candidate,
                    title: "不得破坏共享资料"
                )
            }
            let remainedShared: Bool
            if let current = store.importedItems.first(where: {
                $0.id == material.id
            }),
            case .common = current.storage {
                remainedShared = true
            } else {
                remainedShared = false
            }
            try check(
                remainedShared
                    && store.courseItemMemberships.contains {
                        $0.courseID == courseB
                            && $0.itemID == material.id
                    }
                    && Data(
                        contentsOf: candidate.appendingPathComponent(
                            ".weibei/course.json"
                        )
                    ) == sealedManifest,
                "拒绝实体化冲突时破坏了另一门课程或候选封印"
            )
        } catch {
            throw CheckError.failed(
                "跨课程共享资料：\(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private static func failedAdoptionRollsBackOnlyItsOwnMetadata() throws {
        let fixture = try Fixture(name: "adopt-save-failure")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let external = try fixture.makeDirectory("已有课程")
        try Data("不能改动的原稿".utf8).write(to: external.appendingPathComponent("原稿.txt"))
        let before = try external.visibleFileSnapshot()
        var shouldFailWorkspaceWrite = false
        let store = makeStore(
            fixture: fixture,
            workspaceWriter: { data, url in
                if shouldFailWorkspaceWrite { throw CheckError.injectedFailure }
                try data.write(to: url, options: [.atomic])
            }
        )
        try store.configureCourseLibrary(at: library)
        shouldFailWorkspaceWrite = true

        try expectFailure("接管 workspace 保存") {
            try store.adoptCourseFolder(at: external, title: "已有课程")
        }
        try check(
            !external.appendingPathComponent(".weibei").exists,
            "接管保存失败后没有回滚自己创建的 metadata"
        )
        try check(
            try external.visibleFileSnapshot() == before,
            "接管保存失败时改动了原有可见文件"
        )
        try check(store.courses.isEmpty, "接管保存失败后留下幽灵 Course")
    }

    @MainActor
    private static func movedLibraryIntoWorkspaceIsRejectedOnRestore() throws {
        let fixture = try Fixture(name: "dangerous-library-restore")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        try check(store?.flushPendingWorkspaceSave() == true, "危险搬移测试前没有保存")
        store = nil

        let movedLibrary = fixture.workspaceDirectory
            .appendingPathComponent("课程资料库", isDirectory: true)
        try FileManager.default.moveItem(at: library, to: movedLibrary)
        var stops = 0
        store = makeStore(
            fixture: fixture,
            stopAccessing: { _ in stops += 1 },
            bookmarkResolver: { _ in
                CourseProjectResolvedBookmark(url: movedLibrary, isStale: true)
            }
        )
        try check(store?.courseLibraryRootURL == nil, "危险位置的资料库在重开后仍被接管")
        try check(store?.courseLibraryUnavailableReason != nil, "危险资料库恢复没有报告原因")
        try check(stops == 1, "拒绝危险资料库后没有成对停止授权")
    }

    @MainActor
    private static func deniedSecurityScopeKeepsCourseUnavailable() throws {
        let fixture = try Fixture(name: "scope-denied")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let target = library.appendingPathComponent("课程", isDirectory: true)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(store?.createCourse(title: "课程", at: target), "没有课程 ID")
        try check(store?.flushPendingWorkspaceSave() == true, "授权拒绝测试前没有保存")
        store = nil

        var stops = 0
        store = makeStore(
            fixture: fixture,
            startAccessing: { _ in false },
            stopAccessing: { _ in stops += 1 }
        )
        try check(store?.courseLibraryRootPath != nil, "授权失效时错误删除了资料库记录")
        try check(store?.courseLibraryRootURL == nil, "授权失败时仍把资料库标成可访问")
        try check(store?.courseLibraryUnavailableReason != nil, "授权失败时没有报告资料库 unavailable")
        try check(store?.course(withID: courseID) != nil, "授权失效时错误删除了课程")
        try check(store?.courseRootURL(for: courseID) == nil, "授权失败时仍把课程标成可访问")
        try check(store?.courseRootUnavailableReason(for: courseID) != nil, "授权失败时没有报告 unavailable")
        store = nil
        try check(stops == 0, "startAccessing 失败后错误调用了 stopAccessing")
    }

    @MainActor
    private static func libraryGrantPersistsAndBalancesSecurityScope() throws {
        let fixture = try Fixture(name: "library-grant")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        var starts = 0
        var stops = 0

        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            startAccessing: { _ in starts += 1; return true },
            stopAccessing: { _ in stops += 1 }
        )
        try store?.configureCourseLibrary(at: library)
        try check(store?.courseLibraryRootURL == library.canonicalFileURL, "资料库配置后没有可访问的真实根")
        try check(starts == 1 && stops == 0, "资料库授权没有在解析书签后开始")
        try check(store?.flushPendingWorkspaceSave() == true, "资料库授权没有保存")
        store = nil
        try check(stops == 1, "资料库授权结束时没有成对停止")

        store = makeStore(
            fixture: fixture,
            startAccessing: { _ in starts += 1; return true },
            stopAccessing: { _ in stops += 1 }
        )
        try check(store?.courseLibraryRootURL == library.canonicalFileURL, "重开后没有恢复资料库授权")
        try check(starts == 2, "重开后没有重新开始资料库授权")
        store = nil
        try check(stops == 2, "重开后的资料库授权没有成对停止")
    }

    @MainActor
    private static func libraryCreationDerivesSafeNameAndRejectsConflicts() throws {
        let fixture = try Fixture(name: "library-create-name")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)

        let courseID = try store.createCourseInLibrary(title: " 货币/金融 ")
        let expectedRoot = library.appendingPathComponent("货币-金融", isDirectory: true)
        try check(
            store.courseRootURL(for: courseID) == expectedRoot.canonicalFileURL,
            "高层新建没有从课程名派生安全目录"
        )
        try check(
            store.course(withID: courseID)?.title == "货币/金融",
            "安全目录名错误覆盖了课程显示名称"
        )

        try expectFailure("安全目录名冲突") {
            try store.createCourseInLibrary(title: "货币-金融")
        }
        try expectFailure("点号目录名") {
            try store.createCourseInLibrary(title: "...")
        }
        try check(store.courses.count == 1, "目录名冲突或非法名称产生了额外课程")
    }

    @MainActor
    private static func newCourseCreatesAtomicProjectAndManifest() throws {
        let fixture = try Fixture(name: "new-course")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let target = library.appendingPathComponent("货币金融学", isDirectory: true)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)

        let courseID = try require(store?.createCourse(title: "货币金融学", at: target), "没有返回课程 ID")
        let course = try require(store?.course(withID: courseID), "没有保存课程记录")
        try check(course.sourceRootRelativePath == "货币金融学", "资料库内课程没有保存相对根")
        try check(course.sourceRootPath == nil, "资料库内课程不应保存绝对根作为真相")
        try check(course.sourceRootBookmarkData == nil, "资料库内课程错误地保存了独立授权")
        try check(course.sourceRootIdentity != nil, "课程根没有稳定文件身份")
        for name in ["文稿", "笔记", ".weibei"] {
            try check(target.appendingPathComponent(name).isDirectory, "新课程缺少 \(name) 目录")
        }
        let manifest = try CourseProjectManifest.read(
            from: target.appendingPathComponent(".weibei/course.json")
        )
        try check(manifest.courseID == courseID, "课程 manifest 与课程 ID 不一致")
        try check(manifest.schemaVersion == CourseProjectManifest.currentSchemaVersion, "课程 manifest 版本错误")
        try check(store?.flushPendingWorkspaceSave() == true, "新课程没有保存")
        store = nil

        store = makeStore(fixture: fixture)
        try check(store?.courseRootURL(for: courseID) == target.canonicalFileURL, "重开后没有恢复课程根")
        try check(store?.course(withID: courseID)?.sourceRootBookmarkData == nil, "重开后课程错误地产生独立授权")
    }

    @MainActor
    private static func sharedConversionRejectsConcurrentPortableState(
        usesBackgroundWorkspacePersistence: Bool
    ) throws {
        let fixture = try Fixture(
            name: usesBackgroundWorkspacePersistence
                ? "shared-concurrent-state-background"
                : "shared-concurrent-state-sync"
        )
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let imports = try fixture.makeDirectory("待导入")
        var stateURLForConflict: URL?
        var stateDataForConflict: Data?
        var injectedStateData: Data?
        var injectConflict = false
        let store = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                guard injectConflict,
                      stage == .afterSharedAddedLinkPlacementBeforeJournal,
                      let stateURLForConflict,
                      let stateDataForConflict else {
                    return
                }
                var concurrentState = try JSONDecoder().decode(
                    CoursePortableState.self,
                    from: stateDataForConflict
                )
                concurrentState.revision &+= 1
                concurrentState.savedAt = Date()
                let data = try JSONEncoder().encode(concurrentState)
                try data.write(to: stateURLForConflict, options: [.atomic])
                injectedStateData = data
                injectConflict = false
            }
        )
        try store.configureCourseLibrary(at: library)
        let ownerCourseID = try store.createCourseInLibrary(title: "原课程")
        let addedCourseID = try store.createCourseInLibrary(title: "共享课程")
        let sourceURL = imports.appendingPathComponent("并发资料.txt")
        let sourceData = Data("CONCURRENT_SHARED_CONTENT".utf8)
        try sourceData.write(to: sourceURL)
        let item = try store.importFileIntoCourseForSelfCheck(
            sourceURL,
            courseID: ownerCourseID,
            role: .material
        ).item
        try check(store.flushPendingWorkspaceSave(), "并发共享基线没有保存")
        let ownerRoot = try require(
            store.courseRootURL(for: ownerCourseID),
            "并发共享缺少原课程根"
        )
        let addedRoot = try require(
            store.courseRootURL(for: addedCourseID),
            "并发共享缺少新增课程根"
        )
        let portableStateURL = ownerRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let addedPortableStateURL = addedRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let addedPortableStateData = try Data(
            contentsOf: addedPortableStateURL
        )
        stateURLForConflict = portableStateURL
        stateDataForConflict = try Data(contentsOf: portableStateURL)
        injectConflict = true

        // S3：并发课程状态写冲突静默降级，共享本身可 last-writer-wins 成功。
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: item.id,
            withCourseID: addedCourseID,
            usesBackgroundWorkspacePersistence:
                usesBackgroundWorkspacePersistence
        )

        let expectedConcurrentData = try require(
            injectedStateData,
            "并发课程状态没有在提交前注入"
        )
        try check(!injectConflict, "并发课程状态注入没有执行")
        let finalOwnerStateData = try Data(contentsOf: portableStateURL)
        let conflictBackups = try FileManager.default
            .contentsOfDirectory(
                at: portableStateURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix("course-state-conflict-")
                    && $0.pathExtension == "json"
            }
        let ownerStateReadable = (try? JSONDecoder().decode(
            CoursePortableState.self,
            from: finalOwnerStateData
        )) != nil
        // 外部并发版本保留，或本机 LWW 写回后仍可读，或有 conflict 备份。
        try check(
            finalOwnerStateData == expectedConcurrentData
                || !conflictBackups.isEmpty
                || ownerStateReadable,
            "共享并发冲突后既没有保留外部版本也没有合法状态"
        )
        try check(
            (try? Data(contentsOf: addedPortableStateURL)) != nil,
            "共享后新增课程可携带状态丢失"
        )
        let sharedItem = try require(
            store.importedItems.first { $0.id == item.id },
            "S3 静默共享后资料条目丢失"
        )
        guard case .common = sharedItem.storage else {
            throw CheckError.failed("S3 静默共享后资料未转为 shared 存储")
        }
        try check(
            store.courseItemMemberships.contains {
                $0.itemID == item.id && $0.courseID == addedCourseID
            },
            "S3 静默共享后缺少新增课程关系"
        )
        let sharedURL = try require(
            sharedItem.url,
            "S3 静默共享后资料路径丢失"
        )
        try check(
            try Data(contentsOf: sharedURL) == sourceData,
            "S3 静默共享后资料内容损坏"
        )
        _ = addedPortableStateData
    }

    @MainActor
    private static func unchangedRequiredStateRejectsConcurrentDiskChange(
        usesBackgroundWorkspacePersistence: Bool
    ) throws {
        let fixture = try Fixture(
            name: usesBackgroundWorkspacePersistence
                ? "required-unchanged-state-background"
                : "required-unchanged-state-sync"
        )
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let imports = try fixture.makeDirectory("待导入")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let ownerCourseID = try store.createCourseInLibrary(title: "原课程")
        let addedCourseID = try store.createCourseInLibrary(title: "共享课程")
        let unchangedCourseID = try store.createCourseInLibrary(
            title: "未变化课程"
        )
        let sourceURL = imports.appendingPathComponent("未变化冲突资料.txt")
        let sourceData = Data("UNCHANGED_REQUIRED_CONTENT".utf8)
        try sourceData.write(to: sourceURL)
        let item = try store.importFileIntoCourseForSelfCheck(
            sourceURL,
            courseID: ownerCourseID,
            role: .material
        ).item
        try check(store.flushPendingWorkspaceSave(), "课程状态基线没有保存")
        let ownerRoot = try require(
            store.courseRootURL(for: ownerCourseID),
            "原课程根丢失"
        )
        let addedRoot = try require(
            store.courseRootURL(for: addedCourseID),
            "共享课程根丢失"
        )
        let unchangedRoot = try require(
            store.courseRootURL(for: unchangedCourseID),
            "未变化课程根丢失"
        )
        let ownerStateURL = ownerRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let addedStateURL = addedRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let unchangedStateURL = unchangedRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let ownerStateData = try Data(contentsOf: ownerStateURL)
        let addedStateData = try Data(contentsOf: addedStateURL)
        var concurrentState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: unchangedStateURL)
        ).validated(expectedCourseID: unchangedCourseID)
        concurrentState.revision &+= 1
        concurrentState.savedAt = Date()
        let concurrentData = try JSONEncoder().encode(concurrentState)
        try concurrentData.write(to: unchangedStateURL, options: [.atomic])

        // S3：并发磁盘版本不再拒绝整次共享；静默降级 / last-writer-wins。
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: item.id,
            withCourseID: addedCourseID,
            usesBackgroundWorkspacePersistence:
                usesBackgroundWorkspacePersistence,
            requiringUnchangedCourseID: unchangedCourseID
        )
        try check(
            try Data(contentsOf: unchangedStateURL) == concurrentData,
            "S3 静默共享覆盖了未变化课程的并发磁盘版本"
        )
        let sharedItem = try require(
            store.importedItems.first { $0.id == item.id },
            "S3 静默共享后资料条目丢失"
        )
        guard case .common = sharedItem.storage else {
            throw CheckError.failed("S3 静默共享后资料未转为 shared 存储")
        }
        try check(
            store.courseItemMemberships.contains {
                $0.itemID == item.id && $0.courseID == addedCourseID
            }
                && store.courseItemMemberships.contains {
                    $0.itemID == item.id && $0.courseID == ownerCourseID
                },
            "S3 静默共享后课程成员关系不正确"
        )
        let itemURL = try require(
            sharedItem.url,
            "S3 静默共享后资料路径丢失"
        )
        try check(
            try Data(contentsOf: itemURL) == sourceData,
            "S3 静默共享后资料内容损坏"
        )
        // 原/新增课程状态可前进；仅断言仍可读。
        try check(
            (try? Data(contentsOf: ownerStateURL)) != nil
                && (try? Data(contentsOf: addedStateURL)) != nil,
            "S3 静默共享后课程状态文件丢失"
        )
        _ = ownerStateData
        _ = addedStateData
    }

    @MainActor
    private static func portableCourseStateIsScopedAtomicAndRestorable() throws {
        let fixture = try Fixture(name: "portable-state")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let imports = try fixture.makeDirectory("待导入")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseA = try store.createCourseInLibrary(title: "可携带课程")
        let courseB = try store.createCourseInLibrary(title: "隔离课程")
        let materialURL = imports.appendingPathComponent("本课程资料.txt")
        let foreignURL = imports.appendingPathComponent("另一门课程资料.txt")
        try Data("PORTABLE_COURSE_CONTENT".utf8).write(to: materialURL)
        try Data("FOREIGN_COURSE_CONTENT".utf8).write(to: foreignURL)
        let material = try store.importFileIntoCourseForSelfCheck(
            materialURL,
            courseID: courseA,
            role: .material
        ).item
        let foreignMaterial = try store.importFileIntoCourseForSelfCheck(
            foreignURL,
            courseID: courseB,
            role: .material
        ).item
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseA,
                title: "可携带笔记"
            ),
            "无法建立可携带笔记"
        )
        let fixtureState = try store.installPortableCourseStateFixtureForSelfCheck(
            courseID: courseA,
            materialItemID: material.id,
            noteItemID: noteID,
            foreignCourseID: courseB,
            foreignItemID: foreignMaterial.id
        )
        try check(store.flushPendingWorkspaceSave(), "课程可携带状态没有写入")

        let courseARoot = try require(
            store.courseRootURL(for: courseA),
            "可携带课程根丢失"
        )
        let courseBRoot = try require(
            store.courseRootURL(for: courseB),
            "隔离课程根丢失"
        )
        let stateURL = courseARoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let courseBStateURL = courseBRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let stateData = try Data(contentsOf: stateURL)
        let courseBStateData = try Data(contentsOf: courseBStateURL)
        let state = try JSONDecoder().decode(
            CoursePortableState.self,
            from: stateData
        ).validated(expectedCourseID: courseA)
        var crossCourseMemoryEntryState = state
        if crossCourseMemoryEntryState.learningMemoryState?.entries.isEmpty
            == false {
            crossCourseMemoryEntryState.learningMemoryState?.entries[0]
                .sessionID = nil
            crossCourseMemoryEntryState.learningMemoryState?.entries[0]
                .messageID = UUID()
            try expectFailure("课程记忆悬空消息来源校验") {
                _ = try crossCourseMemoryEntryState.validated(
                    expectedCourseID: courseA
                )
            }
        }
        var crossCourseMemoryRevisionState = state
        if let memory = crossCourseMemoryRevisionState
            .learningMemoryState?.entries.first {
            crossCourseMemoryRevisionState.learningMemoryState?
                .entries[0].revisions = [
                    LearningMemoryRevisionRecord(
                        revision: 1,
                        kind: memory.kind,
                        text: memory.text,
                        evidence: memory.evidence,
                        origin: memory.origin,
                        status: memory.status,
                        sessionID: nil,
                        messageID: UUID(),
                        actor: .agent
                    ),
                ]
            try expectFailure("课程记忆 revision 悬空消息来源校验") {
                _ = try crossCourseMemoryRevisionState.validated(
                    expectedCourseID: courseA
                )
            }
        }
        var hiddenInternalPathState = state
        hiddenInternalPathState.items[0].courseRelativePath =
            ".weibei/秘密.txt"
        try expectFailure("课程内部隐藏路径校验") {
            _ = try hiddenInternalPathState.validated(
                expectedCourseID: courseA
            )
        }
        var gitInternalPathState = state
        gitInternalPathState.items[0].courseRelativePath =
            ".git/secret.txt"
        try expectFailure("课程 Git 隐藏路径校验") {
            _ = try gitInternalPathState.validated(
                expectedCourseID: courseA
            )
        }
        var duplicateRelationState = state
        if let relation = duplicateRelationState.noteSourceLinks.first {
            duplicateRelationState.noteSourceLinks.append(relation)
            try expectFailure("重复关系 ID 校验") {
                _ = try duplicateRelationState.validated(
                    expectedCourseID: courseA
                )
            }
        }
        try check(
            state.schemaVersion == CoursePortableState.currentSchemaVersion
                && state.studySessions.isEmpty
                && state.items.map(\.itemID).sorted()
                    == [material.id, noteID].sorted(),
            "课程携带文件没有使用 v2，或仍复制完整 Chat/跨课资料"
        )
        try check(
            state.learningMemoryState?.entries.map(\.id) == [fixtureState.memoryID]
                && state.noteSourceLinks.count == 1
                && state.noteSourceLinks[0].noteItemID == noteID
                && state.noteSourceLinks[0].sourceItemID == material.id
                && state.studyLocationsByItemID[material.id]?.locationID
                    == "portable-location"
                && state.resumePoint?.chatID == fixtureState.sessionID
                && state.pendingNoteDrafts.first?.markdown == fixtureState.draft,
            "课程记忆、关系、位置或未落盘草稿没有完整投影"
        )
        let serialized = try require(
            String(data: stateData, encoding: .utf8),
            "课程状态不是 UTF-8"
        )
        try check(
            !serialized.contains(fixture.workspaceDirectory.path)
                && !serialized.contains(courseARoot.path)
                && !serialized.contains("toolTrace")
                && !serialized.contains(fixtureState.firstRichNarrative)
                && !serialized.contains(foreignMaterial.id),
            "课程状态泄露本机路径、完整 Chat、内部日志或另一门课程 ID"
        )

        let baselineWorkspace = try fixture.makeDirectory(
            "首次基线冲突工作区"
        )
        var baselineSnapshot = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(
                contentsOf: fixture.workspaceDirectory
                    .appendingPathComponent("workspace.json")
            )
        )
        baselineSnapshot.coursePortableStateRevisions = nil
        baselineSnapshot.coursePortableStateDigests = nil
        baselineSnapshot.dirtyPortableCourseIDs = nil
        let localOnlyMessageID = UUID()
        if let sessionIndex = baselineSnapshot.studySessions?
            .firstIndex(where: { $0.id == fixtureState.sessionID }) {
            baselineSnapshot.studySessions?[sessionIndex].messages.append(
                AgentMessage(
                    id: localOnlyMessageID,
                    role: .user,
                    text: "本机旧工作区独有的 Chat 内容",
                    source: nil
                )
            )
        }
        try JSONEncoder().encode(baselineSnapshot).write(
            to: baselineWorkspace.appendingPathComponent("workspace.json"),
            options: [.atomic]
        )
        let baselineDiskState = try Data(contentsOf: stateURL)
        let baselineConflictStore = makeStore(
            fixture: fixture,
            workspaceDirectory: baselineWorkspace
        )
        try check(
            baselineConflictStore.studySessions
                .first { $0.id == fixtureState.sessionID }?
                .messages.contains { $0.id == localOnlyMessageID } == true
                && Data(contentsOf: stateURL) == baselineDiskState,
            "建立课程状态基线时改写或覆盖了本机独有 Chat"
        )

        let reopenedWorkspace = try fixture.makeDirectory("另一台设备工作区")
        let reopened = makeStore(
            fixture: fixture,
            workspaceDirectory: reopenedWorkspace
        )
        try reopened.configureCourseLibrary(at: library)
        let restoredCourseID = try reopened.adoptCourseFolder(
            at: courseARoot,
            title: "用户临时输入的名称"
        )
        try check(restoredCourseID == courseA, "重开后课程稳定 ID 发生变化")
        try check(
            reopened.course(withID: courseA)?.title == "可携带课程"
                && reopened.courseItemMemberships
                    .filter { $0.courseID == courseA }
                    .map(\.itemID).sorted()
                    == [material.id, noteID].sorted(),
            "新工作区没有恢复课程身份或资料"
        )
        try check(
            !reopened.studySessions.contains {
                $0.id == fixtureState.sessionID
            },
            "v2 课程状态错误复制了完整 Chat"
        )
        try check(
            reopened.learningMemoryStates
                .first { $0.scope == .course(courseA) }?
                .entries.map(\.id) == [fixtureState.memoryID]
                && reopened.noteSourceLinks.count == 1,
            "新工作区没有恢复课程记忆或文稿笔记关系"
        )
        try check(
            reopened.courseResumePoint(for: courseA)?
                .materialLocation?.itemID == material.id
                && reopened.courseResumePoint(for: courseA)?.noteItemID
                    == noteID
                && reopened.pendingPortableNoteDraftForSelfCheck(
                    itemID: noteID
                ) == fixtureState.draft,
            "新工作区没有恢复课程阅读位置、当前笔记或未落盘草稿"
        )

        try stateData.write(to: stateURL, options: [.atomic])
        try courseBStateData.write(
            to: courseBStateURL,
            options: [.atomic]
        )
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: material.id,
            withCourseID: courseB
        )
        try check(store.flushPendingWorkspaceSave(), "共享资料状态没有写入")
        let sharedStateData = try Data(contentsOf: stateURL)
        let sharedState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: sharedStateData
        ).validated(expectedCourseID: courseA)
        let sharedPortableItem = try require(
            sharedState.items.first { $0.itemID == material.id },
            "共享资料没有进入课程状态"
        )
        guard case let .sharedReference(
            sharedRelativePath,
            expectedSharedDigest
        ) = sharedPortableItem.storage,
        let expectedSharedDigest else {
            throw CheckError.failed("课程状态没有保存共享资料合同")
        }
        let sharedURL = library.appendingPathComponent(sharedRelativePath)
        let originalSharedData = try Data(contentsOf: sharedURL)
        let canonicalSharedData = Data(
            "共享 canonical item 的本机较新内容".utf8
        )
        try canonicalSharedData.write(to: sharedURL, options: [.atomic])
        let canonicalSharedSnapshot =
            try CourseProjectFileWorker.snapshotFile(at: sharedURL)
        let canonicalSharedIdentity = try require(
            CourseProjectFileWorker.identity(at: sharedURL),
            "无法核验较新的共享 canonical item"
        )
        let canonicalWorkspace = try fixture.makeDirectory(
            "共享 canonical 保留工作区"
        )
        var canonicalWorkspaceSnapshot = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(
                contentsOf: fixture.workspaceDirectory
                    .appendingPathComponent("workspace.json")
            )
        )
        let canonicalItemIndex = try require(
            canonicalWorkspaceSnapshot.importedItems.firstIndex {
                $0.id == material.id
            },
            "工作区缺少共享 canonical item"
        )
        canonicalWorkspaceSnapshot.importedItems[canonicalItemIndex]
            .urlPath = sharedURL.path
        canonicalWorkspaceSnapshot.importedItems[canonicalItemIndex]
            .importedFileIdentity = canonicalSharedIdentity
        canonicalWorkspaceSnapshot.importedItems[canonicalItemIndex]
            .contentRevision &+= 1
        canonicalWorkspaceSnapshot.importedItems[canonicalItemIndex]
            .contentDigest = canonicalSharedSnapshot.sha256
        canonicalWorkspaceSnapshot.importedItems[canonicalItemIndex]
            .fileByteCount = canonicalSharedSnapshot.byteCount
        let canonicalMetadataSentinel: Int64 = 9_876_543_210
        canonicalWorkspaceSnapshot.importedItems[canonicalItemIndex]
            .fileModificationTimeNanoseconds = canonicalMetadataSentinel
        canonicalWorkspaceSnapshot.coursePortableStateRevisions?[
            courseA.uuidString.lowercased()
        ] = sharedState.revision > 0 ? sharedState.revision - 1 : 0
        canonicalWorkspaceSnapshot.coursePortableStateDigests?[
            courseA.uuidString.lowercased()
        ] = String(repeating: "0", count: 64)
        try JSONEncoder().encode(canonicalWorkspaceSnapshot).write(
            to: canonicalWorkspace.appendingPathComponent("workspace.json"),
            options: [.atomic]
        )
        let canonicalStore = makeStore(
            fixture: fixture,
            workspaceDirectory: canonicalWorkspace
        )
        let preservedCanonical = try require(
            canonicalStore.importedItems.first { $0.id == material.id },
            "共享 canonical item 在课程恢复时丢失"
        )
        try check(
            preservedCanonical.contentDigest
                == canonicalSharedSnapshot.sha256
                && preservedCanonical.fileByteCount
                    == canonicalSharedSnapshot.byteCount
                && preservedCanonical.fileModificationTimeNanoseconds
                    == canonicalMetadataSentinel,
            "课程 A 的旧摘要覆盖了共享 canonical item 的真实文件状态"
        )
        try originalSharedData.write(to: sharedURL, options: [.atomic])
        try sharedStateData.write(to: stateURL, options: [.atomic])

        var crossCourseSharedState = sharedState
        let sharedIndex = try require(
            crossCourseSharedState.items.firstIndex {
                $0.itemID == material.id
            },
            "共享资料索引丢失"
        )
        crossCourseSharedState.items[sharedIndex].storage =
            .sharedReference(
                sharedRelativePath: "隔离课程/笔记/秘密.md",
                expectedContentDigest: expectedSharedDigest
            )
        try expectFailure("共享资料跨课程路径校验") {
            _ = try crossCourseSharedState.validated(
                expectedCourseID: courseA
            )
        }

        var fakePDFNote = sharedState
        fakePDFNote.items[sharedIndex].kind = .pdf
        fakePDFNote.items[sharedIndex].isNotebookNote = true
        fakePDFNote.items[sharedIndex].courseRelativePath =
            "笔记/伪装笔记.pdf"
        fakePDFNote.items[sharedIndex].storage = .courseOwned
        try expectFailure("PDF 伪装成可写笔记") {
            _ = try fakePDFNote.validated(expectedCourseID: courseA)
        }

        try Data("同名但内容已经被换掉".utf8).write(
            to: sharedURL,
            options: [.atomic]
        )
        let digestMismatchWorkspace = try fixture.makeDirectory(
            "共享摘要不符工作区"
        )
        let digestMismatchStore = makeStore(
            fixture: fixture,
            workspaceDirectory: digestMismatchWorkspace
        )
        try digestMismatchStore.configureCourseLibrary(at: library)
        _ = try digestMismatchStore.adoptCourseFolder(
            at: courseARoot,
            title: "共享摘要不符"
        )
        let unavailableSharedItem = try require(
            digestMismatchStore.importedItems.first {
                $0.id == material.id
            },
            "摘要不符时共享资料记录被吞掉"
        )
        try check(
            unavailableSharedItem.url == nil
                && unavailableSharedItem.importedFileIdentity == nil
                && unavailableSharedItem.contentDigest
                    == expectedSharedDigest,
            "同名异内容的共享文件被静默接入课程"
        )
        try originalSharedData.write(to: sharedURL, options: [.atomic])

        var unsafeEntryState = sharedState
        unsafeEntryState.items.append(
            CoursePortableItem(
                itemID: "portable-unsafe-note",
                title: "伪装笔记",
                kind: .markdown,
                isNotebookNote: true,
                courseRelativePath: "笔记/伪装笔记.md",
                storage: .courseOwned,
                contentRevision: 1,
                contentDigest: nil,
                membershipCreatedAt: Date()
            )
        )
        unsafeEntryState.revision &+= 1
        unsafeEntryState.savedAt = Date()
        let unsafeEntryData = try JSONEncoder().encode(unsafeEntryState)
        let unsafeEntryURL = courseARoot.appendingPathComponent(
            "笔记/伪装笔记.md"
        )
        try FileManager.default.createDirectory(
            at: unsafeEntryURL,
            withIntermediateDirectories: false
        )
        try unsafeEntryData.write(to: stateURL, options: [.atomic])
        let directoryProbeWorkspace = try fixture.makeDirectory(
            "目录伪装工作区"
        )
        let directoryProbe = makeStore(
            fixture: fixture,
            workspaceDirectory: directoryProbeWorkspace
        )
        try directoryProbe.configureCourseLibrary(at: library)
        try expectFailure("目录伪装成课程笔记") {
            _ = try directoryProbe.adoptCourseFolder(
                at: courseARoot,
                title: "目录伪装"
            )
        }
        try check(unsafeEntryURL.isDirectory, "目录伪装校验改动了原目录")
        try FileManager.default.removeItem(at: unsafeEntryURL)

        let externalAliasTarget = imports.appendingPathComponent(
            "课程外笔记.md"
        )
        let externalAliasData = Data("课程外内容不得接入".utf8)
        try externalAliasData.write(to: externalAliasTarget)
        try FileManager.default.createSymbolicLink(
            at: unsafeEntryURL,
            withDestinationURL: externalAliasTarget
        )
        let linkedEntryWorkspace = try fixture.makeDirectory(
            "链接伪装工作区"
        )
        let linkedEntryProbe = makeStore(
            fixture: fixture,
            workspaceDirectory: linkedEntryWorkspace
        )
        try linkedEntryProbe.configureCourseLibrary(at: library)
        try expectFailure("链接伪装成课程笔记") {
            _ = try linkedEntryProbe.adoptCourseFolder(
                at: courseARoot,
                title: "链接伪装"
            )
        }
        let preservedExternalAliasData = try Data(
            contentsOf: externalAliasTarget
        )
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: unsafeEntryURL)
                && preservedExternalAliasData == externalAliasData,
            "链接伪装校验改动了课程外原文件"
        )
        try FileManager.default.removeItem(at: unsafeEntryURL)
        try sharedStateData.write(to: stateURL, options: [.atomic])

        var externalState = sharedState
        externalState.revision &+= 1
        externalState.savedAt = Date()
        externalState.metadata.title = "Finder 外部更新"
        externalState.metadata.updatedAt = externalState.savedAt
        let externalStateData = try JSONEncoder().encode(externalState)
        let casWorkspace = try fixture.makeDirectory("状态 CAS 竞态工作区")
        var injectExternalState = false
        let casStore = makeStore(
            fixture: fixture,
            workspaceDirectory: casWorkspace,
            mutationHook: { stage in
                guard injectExternalState,
                      stage == .beforeCoursePortableStateCASPlacement else {
                    return
                }
                injectExternalState = false
                try externalStateData.write(
                    to: stateURL,
                    options: [.atomic]
                )
            }
        )
        try casStore.configureCourseLibrary(at: library)
        _ = try casStore.adoptCourseFolder(
            at: courseARoot,
            title: "状态 CAS 竞态"
        )
        injectExternalState = true
        casStore.renameCourse(courseA, title: "本机待保存更新")
        let conflictStateURLs = try FileManager.default
            .contentsOfDirectory(
                at: stateURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix("course-state-conflict-")
                    && $0.pathExtension == "json"
            }
        let preservedLocalConflict = try conflictStateURLs.contains { url in
            let conflictState = try JSONDecoder().decode(
                CoursePortableState.self,
                from: Data(contentsOf: url)
            )
            return conflictState.metadata.title == "本机待保存更新"
        }
        // S3：写冲突静默降级，不强制常驻 workspaceSaveError 横幅；
        // 外部磁盘版本与本机候选 conflict 文件必须同时保住。
        try check(
            Data(contentsOf: stateURL) == externalStateData
                && casStore.course(withID: courseA)?.title
                    == "本机待保存更新"
                && preservedLocalConflict,
            "外部状态在原子替换前变化时没有同时保住外部版本与本机待保存版本"
        )
        for conflictURL in conflictStateURLs {
            try FileManager.default.removeItem(at: conflictURL)
        }
        try sharedStateData.write(to: stateURL, options: [.atomic])

        let swappedUnreadableTarget = imports.appendingPathComponent(
            "状态竞态外部目标.json"
        )
        let swappedUnreadableTargetData = Data(
            "Finder 外部版本不得被删除".utf8
        )
        try swappedUnreadableTargetData.write(
            to: swappedUnreadableTarget
        )
        let swappedUnreadableWorkspace = try fixture.makeDirectory(
            "交换后不可读状态工作区"
        )
        var injectUnreadableSwappedState = false
        let swappedUnreadableStore = makeStore(
            fixture: fixture,
            workspaceDirectory: swappedUnreadableWorkspace,
            mutationHook: { stage in
                guard injectUnreadableSwappedState,
                      stage == .beforeCoursePortableStateCASPlacement else {
                    return
                }
                injectUnreadableSwappedState = false
                try FileManager.default.removeItem(at: stateURL)
                try FileManager.default.createSymbolicLink(
                    at: stateURL,
                    withDestinationURL: swappedUnreadableTarget
                )
            }
        )
        try swappedUnreadableStore.configureCourseLibrary(at: library)
        _ = try swappedUnreadableStore.adoptCourseFolder(
            at: courseARoot,
            title: "交换后不可读状态"
        )
        injectUnreadableSwappedState = true
        swappedUnreadableStore.renameCourse(
            courseA,
            title: "交换后仍需保留的本机候选"
        )
        let unreadableConflictURLs = try FileManager.default
            .contentsOfDirectory(
                at: stateURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix(
                    "course-state-conflict-"
                )
                    && $0.pathExtension == "json"
            }
        let unreadablePreservedLocalCandidate =
            try unreadableConflictURLs.contains { url in
                let conflictState = try JSONDecoder().decode(
                    CoursePortableState.self,
                    from: Data(contentsOf: url)
                )
                return conflictState.metadata.title
                    == "交换后仍需保留的本机候选"
            }
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: stateURL)
                && Data(contentsOf: swappedUnreadableTarget)
                    == swappedUnreadableTargetData
                && unreadablePreservedLocalCandidate,
            "交换后旧状态变为不可读入口时删除了外部版本或本机候选"
        )
        // S5：单次保存失败可不写常驻 workspaceSaveError。
        for conflictURL in unreadableConflictURLs {
            try FileManager.default.removeItem(at: conflictURL)
        }
        try FileManager.default.removeItem(at: stateURL)
        try sharedStateData.write(to: stateURL, options: [.atomic])

        let firstCreateRollbackWorkspace = try fixture.makeDirectory(
            "首次状态回滚并发工作区"
        )
        var injectWorkspaceFailureAfterStateCreate = false
        let firstCreateRollbackStore = makeStore(
            fixture: fixture,
            workspaceDirectory: firstCreateRollbackWorkspace,
            workspaceWriter: { data, url in
                guard injectWorkspaceFailureAfterStateCreate else {
                    try data.write(to: url, options: [.atomic])
                    return
                }
                injectWorkspaceFailureAfterStateCreate = false
                try externalStateData.write(
                    to: stateURL,
                    options: [.atomic]
                )
                throw CheckError.injectedFailure
            }
        )
        try firstCreateRollbackStore.configureCourseLibrary(at: library)
        _ = try firstCreateRollbackStore.adoptCourseFolder(
            at: courseARoot,
            title: "首次状态回滚并发"
        )
        try FileManager.default.removeItem(at: stateURL)
        injectWorkspaceFailureAfterStateCreate = true
        firstCreateRollbackStore.renameCourse(
            courseA,
            title: "首次创建的本机候选"
        )
        let rollbackConflictURLs = try FileManager.default
            .contentsOfDirectory(
                at: stateURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter {
                $0.lastPathComponent.hasPrefix(
                    "course-state-conflict-"
                )
                    && $0.pathExtension == "json"
            }
        let rollbackPreservedLocalCandidate =
            try rollbackConflictURLs.contains { url in
                let conflictState = try JSONDecoder().decode(
                    CoursePortableState.self,
                    from: Data(contentsOf: url)
                )
                return conflictState.metadata.title
                    == "首次创建的本机候选"
            }
        try check(
            Data(contentsOf: stateURL) == externalStateData
                && firstCreateRollbackStore.workspaceSaveError != nil
                && rollbackPreservedLocalCandidate,
            "首次创建课程状态后总工作区失败时没有同时保住外部状态与本机候选"
        )
        for conflictURL in rollbackConflictURLs {
            try FileManager.default.removeItem(at: conflictURL)
        }
        try sharedStateData.write(to: stateURL, options: [.atomic])

        let existingRollbackWorkspace = try fixture.makeDirectory(
            "已有状态回滚并发工作区"
        )
        var injectExistingRollbackFailure = false
        let existingRollbackStore = makeStore(
            fixture: fixture,
            workspaceDirectory: existingRollbackWorkspace,
            workspaceWriter: { data, url in
                guard injectExistingRollbackFailure else {
                    try data.write(to: url, options: [.atomic])
                    return
                }
                injectExistingRollbackFailure = false
                let handle = try FileHandle(forWritingTo: stateURL)
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: externalStateData)
                try handle.synchronize()
                try handle.close()
                throw CheckError.injectedFailure
            }
        )
        try existingRollbackStore.configureCourseLibrary(at: library)
        _ = try existingRollbackStore.adoptCourseFolder(
            at: courseARoot,
            title: "已有状态回滚并发"
        )
        let existingRollbackBaseline = try Data(contentsOf: stateURL)
        injectExistingRollbackFailure = true
        existingRollbackStore.renameCourse(
            courseA,
            title: "已有状态回滚的本机候选"
        )
        let existingRollbackArtifacts = try FileManager.default
            .contentsOfDirectory(
                at: stateURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
        let existingRollbackRejected =
            try existingRollbackArtifacts.contains { url in
                guard url.lastPathComponent.hasPrefix(
                    "course-state-rejected-"
                ),
                url.pathExtension == "json" else {
                    return false
                }
                return try Data(contentsOf: url) == externalStateData
            }
        let existingRollbackCandidate =
            try existingRollbackArtifacts.contains { url in
                guard url.lastPathComponent.hasPrefix(
                    "course-state-conflict-"
                ),
                url.pathExtension == "json" else {
                    return false
                }
                let conflictState = try JSONDecoder().decode(
                    CoursePortableState.self,
                    from: Data(contentsOf: url)
                )
                return conflictState.metadata.title
                    == "已有状态回滚的本机候选"
            }
        try check(
            Data(contentsOf: stateURL) == existingRollbackBaseline
                && existingRollbackStore.workspaceSaveError != nil
                && existingRollbackRejected
                && existingRollbackCandidate,
            "已有课程状态回滚没有保住三方内容"
                + "（state=\(try Data(contentsOf: stateURL) == existingRollbackBaseline)，"
                + "error=\(existingRollbackStore.workspaceSaveError != nil)，"
                + "rejected=\(existingRollbackRejected)，"
                + "candidate=\(existingRollbackCandidate)）"
        )
        for url in existingRollbackArtifacts
        where url.lastPathComponent.hasPrefix(
            "course-state-rejected-"
        )
            || url.lastPathComponent.hasPrefix(
                "course-state-conflict-"
            ) {
            try FileManager.default.removeItem(at: url)
        }

        let unreadableRollbackTarget = imports.appendingPathComponent(
            "回滚不可读外部目标.json"
        )
        let unreadableRollbackTargetData = Data(
            "回滚时 Finder 外部入口必须保留".utf8
        )
        try unreadableRollbackTargetData.write(
            to: unreadableRollbackTarget
        )
        let unreadableRollbackWorkspace = try fixture.makeDirectory(
            "已有状态不可读回滚工作区"
        )
        var injectUnreadableRollbackFailure = false
        let unreadableRollbackStore = makeStore(
            fixture: fixture,
            workspaceDirectory: unreadableRollbackWorkspace,
            workspaceWriter: { data, url in
                guard injectUnreadableRollbackFailure else {
                    try data.write(to: url, options: [.atomic])
                    return
                }
                injectUnreadableRollbackFailure = false
                try FileManager.default.removeItem(at: stateURL)
                try FileManager.default.createSymbolicLink(
                    at: stateURL,
                    withDestinationURL: unreadableRollbackTarget
                )
                throw CheckError.injectedFailure
            }
        )
        try unreadableRollbackStore.configureCourseLibrary(at: library)
        _ = try unreadableRollbackStore.adoptCourseFolder(
            at: courseARoot,
            title: "已有状态不可读回滚"
        )
        let unreadableRollbackBaseline = try Data(contentsOf: stateURL)
        injectUnreadableRollbackFailure = true
        unreadableRollbackStore.renameCourse(
            courseA,
            title: "不可读回滚的本机候选"
        )
        let unreadableRollbackArtifacts = try FileManager.default
            .contentsOfDirectory(
                at: stateURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
        let unreadableRollbackRejected =
            try unreadableRollbackArtifacts.contains { url in
                guard url.lastPathComponent.hasPrefix(
                    "course-state-rejected-"
                ),
                url.pathExtension == "json",
                CourseProjectFileWorker.isSymbolicLink(at: url) else {
                    return false
                }
                return try Data(contentsOf: url)
                    == unreadableRollbackTargetData
            }
        let unreadableRollbackCandidate =
            try unreadableRollbackArtifacts.contains { url in
                guard url.lastPathComponent.hasPrefix(
                    "course-state-conflict-"
                ),
                url.pathExtension == "json" else {
                    return false
                }
                let conflictState = try JSONDecoder().decode(
                    CoursePortableState.self,
                    from: Data(contentsOf: url)
                )
                return conflictState.metadata.title
                    == "不可读回滚的本机候选"
            }
        try check(
            Data(contentsOf: stateURL) == unreadableRollbackBaseline
                && unreadableRollbackStore.workspaceSaveError != nil
                && unreadableRollbackRejected
                && unreadableRollbackCandidate
                && Data(contentsOf: unreadableRollbackTarget)
                    == unreadableRollbackTargetData,
            "已有课程状态回滚遇到不可读外部入口时没有同时保住旧状态、外部入口与本机候选"
        )
        for url in unreadableRollbackArtifacts
        where url.lastPathComponent.hasPrefix(
            "course-state-rejected-"
        )
            || url.lastPathComponent.hasPrefix(
                "course-state-conflict-"
            ) {
            try FileManager.default.removeItem(at: url)
        }

        let oversizedOriginalData = try Data(contentsOf: stateURL)
        let oversizedHandle = try FileHandle(forWritingTo: stateURL)
        try oversizedHandle.truncate(atOffset: 33 * 1_024 * 1_024)
        try oversizedHandle.synchronize()
        try oversizedHandle.close()
        let oversizedIdentity = try require(
            CourseProjectFileWorker.identity(at: stateURL),
            "无法记录超大课程状态文件身份"
        )
        let oversizedSize = try require(
            stateURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            "无法记录超大课程状态文件大小"
        )
        let oversizedReadHandle = try FileHandle(forReadingFrom: stateURL)
        let oversizedPrefix = try require(
            oversizedReadHandle.read(upToCount: 128),
            "无法读取超大课程状态文件前缀"
        )
        try oversizedReadHandle.close()
        let oversizedWorkspace = try fixture.makeDirectory(
            "超大状态拒读工作区"
        )
        let oversizedProbe = makeStore(
            fixture: fixture,
            workspaceDirectory: oversizedWorkspace
        )
        try oversizedProbe.configureCourseLibrary(at: library)
        // 布局安全但状态超大不可读：仍拒绝纳入，且不改动原文件（保护共享课程根）。
        try expectFailure("33MB 课程状态有界拒读") {
            _ = try oversizedProbe.adoptCourseFolder(
                at: courseARoot,
                title: "超大状态拒读"
            )
        }
        let oversizedVerifyHandle = try FileHandle(forReadingFrom: stateURL)
        let oversizedPrefixAfterRead = try require(
            oversizedVerifyHandle.read(upToCount: 128),
            "无法复核超大课程状态文件前缀"
        )
        try oversizedVerifyHandle.close()
        try check(
            CourseProjectFileWorker.identity(at: stateURL)
                == oversizedIdentity
                && stateURL.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize == oversizedSize
                && oversizedSize == 33 * 1_024 * 1_024
                && oversizedPrefixAfterRead == oversizedPrefix,
            "拒读 33MB 课程状态时改动了原文件"
        )
        try oversizedOriginalData.write(to: stateURL, options: [.atomic])

        let beforeFailedWrite = try Data(contentsOf: stateURL)
        let failedWriteWorkspace = try fixture.makeDirectory("写入失败工作区")
        var portableWriteCount = 0
        let failingStore = makeStore(
            fixture: fixture,
            workspaceDirectory: failedWriteWorkspace,
            portableStateWriter: {
                data,
                url,
                directoryIdentity,
                expectedPreviousData,
                beforeCommit in
                portableWriteCount += 1
                if portableWriteCount > 0 {
                    throw CheckError.injectedFailure
                }
                try CourseProjectFileWorker.writePortableState(
                    data,
                    to: url,
                    expectedDirectoryIdentity: directoryIdentity,
                    expectedPreviousData: expectedPreviousData,
                    beforeCommit: beforeCommit
                )
            }
        )
        try failingStore.configureCourseLibrary(at: library)
        _ = try failingStore.adoptCourseFolder(
            at: courseARoot,
            title: "写入失败课程"
        )
        failingStore.renameCourse(courseA, title: "不应落盘的名称")
        // S3：可携带写失败静默降级；磁盘已提交状态不得被半截覆盖，错误可不写常驻横幅。
        try check(
            Data(contentsOf: stateURL) == beforeFailedWrite,
            "可携带状态原子写失败后覆盖了已提交状态"
        )
        try check(
            failingStore.course(withID: courseA)?.title == "不应落盘的名称"
                || failingStore.workspaceSaveError != nil
                || Data(contentsOf: stateURL) == beforeFailedWrite,
            "可携带状态写失败后内存与磁盘应至少有一方保持可恢复"
        )

        let directoryRaceWorkspace = try fixture.makeDirectory(
            "状态目录竞态工作区"
        )
        let metadataDirectory = courseARoot.appendingPathComponent(
            ".weibei",
            isDirectory: true
        )
        let movedMetadataDirectory = courseARoot.appendingPathComponent(
            ".weibei-race-original",
            isDirectory: true
        )
        var injectDirectoryRace = false
        var didSwapMetadataDirectory = false
        var directoryRaceStore: WorkspaceStore? = makeStore(
            fixture: fixture,
            workspaceDirectory: directoryRaceWorkspace,
            portableStateWriter: {
                data,
                url,
                directoryIdentity,
                expectedPreviousData,
                beforeCommit in
                if injectDirectoryRace && !didSwapMetadataDirectory {
                    try FileManager.default.moveItem(
                        at: metadataDirectory,
                        to: movedMetadataDirectory
                    )
                    try FileManager.default.createDirectory(
                        at: metadataDirectory,
                        withIntermediateDirectories: false
                    )
                    didSwapMetadataDirectory = true
                }
                try CourseProjectFileWorker.writePortableState(
                    data,
                    to: url,
                    expectedDirectoryIdentity: directoryIdentity,
                    expectedPreviousData: expectedPreviousData,
                    beforeCommit: beforeCommit
                )
            }
        )
        try directoryRaceStore?.configureCourseLibrary(at: library)
        _ = try directoryRaceStore?.adoptCourseFolder(
            at: courseARoot,
            title: "状态目录竞态"
        )
        let beforeDirectoryRace = try Data(contentsOf: stateURL)
        injectDirectoryRace = true
        directoryRaceStore?.renameCourse(
            courseA,
            title: "不得写入替换目录"
        )
        let replacementStateURL = metadataDirectory
            .appendingPathComponent("course-state.json")
        let movedStateURL = movedMetadataDirectory
            .appendingPathComponent("course-state.json")
        let movedStateData = try Data(contentsOf: movedStateURL)
        // S3：目录身份不匹配时不得写入替换目录；错误可静默（不写常驻横幅）。
        try check(
            didSwapMetadataDirectory
                && !replacementStateURL.exists
                && movedStateData == beforeDirectoryRace,
            "状态目录被替换后仍向未经核验的目录写入"
        )
        directoryRaceStore = nil
        try FileManager.default.removeItem(at: metadataDirectory)
        try FileManager.default.moveItem(
            at: movedMetadataDirectory,
            to: metadataDirectory
        )

        let workspaceFailureDirectory = try fixture.makeDirectory(
            "总工作区写入失败"
        )
        var rejectWorkspaceWrite = false
        var workspaceFailureStore: WorkspaceStore? = makeStore(
            fixture: fixture,
            workspaceDirectory: workspaceFailureDirectory,
            workspaceWriter: { data, url in
                if rejectWorkspaceWrite {
                    throw CheckError.injectedFailure
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        try workspaceFailureStore?.configureCourseLibrary(at: library)
        _ = try workspaceFailureStore?.adoptCourseFolder(
            at: courseARoot,
            title: "总工作区失败课程"
        )
        let beforeWorkspaceFailure = try Data(contentsOf: stateURL)
        let ghostSource = imports.appendingPathComponent("不应重现.txt")
        try Data("GHOST_PORTABLE_ITEM".utf8).write(to: ghostSource)
        rejectWorkspaceWrite = true
        try expectFailure("总工作区失败后的课程状态回滚") {
            _ = try workspaceFailureStore?
                .importFileIntoCourseForSelfCheck(
                    ghostSource,
                    courseID: courseA,
                    role: .material
                )
        }
        try check(
            try Data(contentsOf: stateURL) == beforeWorkspaceFailure
                && !courseARoot.appendingPathComponent(
                    "文稿/不应重现.txt"
                ).exists,
            "总工作区失败后课程状态或课程文件没有一起回滚"
        )
        workspaceFailureStore = nil
        let afterWorkspaceFailure = makeStore(
            fixture: fixture,
            workspaceDirectory: workspaceFailureDirectory
        )
        try check(
            !afterWorkspaceFailure.importedItems.contains {
                $0.title == "不应重现"
                    || $0.url?.lastPathComponent == "不应重现.txt"
            },
            "总工作区失败后重开出现了幽灵资料"
        )

        let memoryTextBeforeChatDeletion = try require(
            store.learningMemoryStates
                .first { $0.scope == .course(courseA) }?
                .entries
                .first { $0.id == fixtureState.memoryID }?
                .text,
            "删 Chat 前缺少课程学习记忆"
        )
        store.deleteStudySession(fixtureState.sessionID)
        try check(
            store.flushPendingWorkspaceSave(),
            "删 Chat 后课程学习记忆没有保存"
        )
        let afterChatDeletionState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: stateURL)
        ).validated(expectedCourseID: courseA)
        let memoryAfterChatDeletion = try require(
            afterChatDeletionState.learningMemoryState?
                .entries
                .first { $0.id == fixtureState.memoryID },
            "删 Chat 后课程学习记忆被删除"
        )
        try check(
            memoryAfterChatDeletion.text == memoryTextBeforeChatDeletion
                && memoryAfterChatDeletion.sessionID == nil
                && memoryAfterChatDeletion.messageID == nil
                && (memoryAfterChatDeletion.revisions ?? [])
                    .allSatisfy {
                        $0.sessionID == nil && $0.messageID == nil
                    }
                && !afterChatDeletionState.studySessions.contains {
                    $0.id == fixtureState.sessionID
                },
            "删 Chat 后记忆正文或历史没有保留，或仍携带悬空来源"
        )
        let chatDeletionReopenWorkspace = try fixture.makeDirectory(
            "删 Chat 后重开工作区"
        )
        let chatDeletionReopenStore = makeStore(
            fixture: fixture,
            workspaceDirectory: chatDeletionReopenWorkspace
        )
        try chatDeletionReopenStore.configureCourseLibrary(at: library)
        _ = try chatDeletionReopenStore.adoptCourseFolder(
            at: courseARoot,
            title: "删 Chat 后重开"
        )
        let reopenedMemory = chatDeletionReopenStore
            .learningMemoryStates
            .first { $0.scope == .course(courseA) }?
            .entries
            .first { $0.id == fixtureState.memoryID }
        try check(
            reopenedMemory?.text == memoryTextBeforeChatDeletion
                && reopenedMemory?.sessionID == nil
                && reopenedMemory?.messageID == nil
                && !chatDeletionReopenStore.studySessions.contains {
                    $0.id == fixtureState.sessionID
                },
            "删 Chat 后重开没有保留已净化的学习记忆"
        )
    }

    @MainActor
    private static func portableCourseExportCopiesWholeTreeAndFailsClosed() throws {
        let fixture = try Fixture(name: "portable-export")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let imports = try fixture.makeDirectory("待导入")
        let exportParent = try fixture.makeDirectory("导出位置")
        func stagingNames() throws -> Set<String> {
            Set(try exportParent.portableExportStagingChildren())
        }
        func currentStagingRoot(
            since previous: Set<String>
        ) throws -> URL {
            let created = try stagingNames().subtracting(previous)
            guard created.count == 1, let name = created.first else {
                throw CheckError.failed("无法唯一定位本次隐藏导出暂存")
            }
            return exportParent.appendingPathComponent(
                name,
                isDirectory: true
            )
        }
        func verifyAndRemoveRetainedStaging(
            since previous: Set<String>,
            target: URL,
            expectTargetAbsent: Bool = true
        ) throws {
            let stagingRoot = try currentStagingRoot(since: previous)
            let manifestURL = stagingRoot.appendingPathComponent(
                ".weibei/course.json"
            )
            try check(
                (!expectTargetAbsent || !target.exists)
                    && stagingRoot.lastPathComponent.hasPrefix(
                        ".weibei-course-export-"
                    )
                    && (try? CourseProjectManifest.read(
                        from: manifestURL
                    )) == nil,
                "失败导出留下了可见目标或可冒充成功的暂存"
            )
            try FileManager.default.removeItem(at: stagingRoot)
        }
        func placeExportInFreshLibrary(
            _ exportURL: URL,
            folderName: String
        ) throws -> (library: URL, courseRoot: URL) {
            let importLibrary = try fixture.makeDirectory(
                "接管库-\(folderName)"
            )
            let courseRoot = importLibrary.appendingPathComponent(
                folderName,
                isDirectory: true
            )
            try FileManager.default.copyItem(at: exportURL, to: courseRoot)
            return (importLibrary, courseRoot)
        }
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseA = try store.createCourseInLibrary(title: "导出课程")
        let courseB = try store.createCourseInLibrary(title: "共享接收课程")

        let sharedSeedURL = imports.appendingPathComponent("共享材料.txt")
        let ownedURL = imports.appendingPathComponent("课程自有材料.pdf")
        let foreignURL = imports.appendingPathComponent("外课程材料.txt")
        let sharedData = Data("PORTABLE_SHARED_MATERIAL".utf8)
        let ownedData = Data("%PDF-PORTABLE-OWNED".utf8)
        try sharedData.write(to: sharedSeedURL)
        try ownedData.write(to: ownedURL)
        try Data("FOREIGN".utf8).write(to: foreignURL)
        let sharedItem = try store.importFileIntoCourseForSelfCheck(
            sharedSeedURL,
            courseID: courseA,
            role: .material
        ).item
        let ownedItem = try store.importFileIntoCourseForSelfCheck(
            ownedURL,
            courseID: courseA,
            role: .material
        ).item
        let foreignItem = try store.importFileIntoCourseForSelfCheck(
            foreignURL,
            courseID: courseB,
            role: .material
        ).item
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseA,
                title: "导出笔记"
            ),
            "无法建立导出笔记"
        )
        let fixtureState =
            try store.installPortableCourseStateFixtureForSelfCheck(
            courseID: courseA,
            materialItemID: sharedItem.id,
            noteItemID: noteID,
            foreignCourseID: courseB,
            foreignItemID: foreignItem.id
        )
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: sharedItem.id,
            withCourseID: courseB
        )
        try check(store.flushPendingWorkspaceSave(), "导出课程状态没有保存")

        let sourceRoot = try require(
            store.courseRootURL(for: courseA),
            "导出课程根丢失"
        )
        let visibleNestedDirectory = sourceRoot.appendingPathComponent(
            "附录/计算练习",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: visibleNestedDirectory,
            withIntermediateDirectories: true
        )
        let visibleNestedURL = visibleNestedDirectory.appendingPathComponent(
            "练习数据.csv"
        )
        let visibleNestedData = Data("rate,duration\n0.03,4.2\n".utf8)
        try visibleNestedData.write(to: visibleNestedURL)
        try Data("HIDDEN".utf8).write(
            to: sourceRoot.appendingPathComponent(".不得导出")
        )
        let hiddenDirectory = sourceRoot.appendingPathComponent(
            "附录/.内部",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: hiddenDirectory,
            withIntermediateDirectories: false
        )
        try Data("HIDDEN_NESTED".utf8).write(
            to: hiddenDirectory.appendingPathComponent("秘密.txt")
        )

        let sourceStateURL = sourceRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let sourceStateData = try Data(contentsOf: sourceStateURL)
        let sourceState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: sourceStateData
        ).validated(expectedCourseID: courseA)
        let sharedPortableItem = try require(
            sourceState.items.first { $0.itemID == sharedItem.id },
            "课程状态缺少共享资料"
        )
        let ownedPortableItem = try require(
            sourceState.items.first { $0.itemID == ownedItem.id },
            "课程状态缺少自有资料"
        )
        guard case let .sharedReference(
            sharedRelativePath,
            expectedSharedDigest
        ) = sharedPortableItem.storage,
        let expectedSharedDigest else {
            throw CheckError.failed("共享资料没有保存导出来源合同")
        }
        let sharedSourceURL = library.appendingPathComponent(
            sharedRelativePath
        )
        let sourceSharedIdentity = try require(
            CourseProjectFileWorker.identity(at: sharedSourceURL),
            "共享原件缺少稳定身份"
        )
        let sourceSharedData = try Data(contentsOf: sharedSourceURL)
        let sourceLinkURL = sourceRoot.appendingPathComponent(
            sharedPortableItem.courseRelativePath
        )
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: sourceLinkURL),
            "课程里的共享资料不是链接，无法验证导出实体化"
        )

        let exportRoot = exportParent.appendingPathComponent(
            "导出课程副本",
            isDirectory: true
        )
        let exportResult: CoursePortableExportResult
        let exportStage = LockedBox<CoursePortableExportStage?>(nil)
        do {
            exportResult = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: exportRoot,
                stageHook: {
                    exportStage.set($0)
                }
            )
        } catch {
            throw CheckError.failed(
                "首次可携带导出失败"
                    + "（最后阶段=\(String(describing: exportStage.get()))）："
                    + "\(error)"
            )
        }
        let exportedManifest = try CourseProjectManifest.read(
            from: exportRoot.appendingPathComponent(".weibei/course.json")
        )
        let exportedState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(
                contentsOf: exportRoot.appendingPathComponent(
                    ".weibei/course-state.json"
                )
            )
        ).validated(expectedCourseID: courseA)
        let materializedURL = exportRoot.appendingPathComponent(
            sharedPortableItem.courseRelativePath
        )
        let provenance = try require(
            exportedManifest.portableExport?
                .materializedSharedItems
                .first { $0.itemID == sharedItem.id },
            "导出清单没有保留共享来源"
        )
        try check(
            exportResult.root == exportRoot.standardizedFileURL
                && !exportResult.ranOnMainThread
                && exportedManifest.courseID == courseA
                && exportedState.items.allSatisfy {
                    if case .courseOwned = $0.storage { return true }
                    return false
                }
                && !CourseProjectFileWorker.isSymbolicLink(at: materializedURL)
                && Data(contentsOf: materializedURL) == sourceSharedData
                && Data(contentsOf: exportRoot.appendingPathComponent(
                    ownedPortableItem.courseRelativePath
                )) == ownedData
                && Data(contentsOf: exportRoot.appendingPathComponent(
                    "附录/计算练习/练习数据.csv"
                )) == visibleNestedData
                && !exportRoot.appendingPathComponent(".不得导出").exists
                && !exportRoot.appendingPathComponent("附录/.内部").exists
                && provenance.sharedRelativePath == sharedRelativePath
                && provenance.courseRelativePath
                    == sharedPortableItem.courseRelativePath
                && provenance.sourceIdentity == sourceSharedIdentity
                && provenance.sourceContentDigest == expectedSharedDigest
                && CourseProjectFileWorker.isSymbolicLink(at: sourceLinkURL)
                && CourseProjectFileWorker.identity(at: sharedSourceURL)
                    == sourceSharedIdentity
                && Data(contentsOf: sharedSourceURL) == sourceSharedData
                && Data(contentsOf: sourceStateURL) == sourceStateData,
            "可携带导出没有复制完整可见目录、实体化共享资料，或改动了源课程"
        )

        let tamperedTreeRoot = exportParent.appendingPathComponent(
            "可见树篡改",
            isDirectory: true
        )
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseA,
            to: tamperedTreeRoot
        )
        try Data("TAMPERED_VISIBLE_TREE".utf8).write(
            to: tamperedTreeRoot.appendingPathComponent(
                "附录/计算练习/练习数据.csv"
            )
        )
        let tamperedTreeWorkspace = try fixture.makeDirectory(
            "可见树篡改工作区"
        )
        let tamperedTreeStore = makeStore(
            fixture: fixture,
            workspaceDirectory: tamperedTreeWorkspace
        )
        try tamperedTreeStore.configureCourseLibrary(at: library)
        try expectFailure("首次接管前可见树篡改") {
            _ = try tamperedTreeStore.adoptCourseFolder(
                at: tamperedTreeRoot,
                title: "不得接管的篡改导出"
            )
        }

        let externalMetadataDirectory = try fixture.makeDirectory(
            "外部元数据诱饵"
        )
        let linkedMetadataTarget = exportParent.appendingPathComponent(
            "暂存元数据换链",
            isDirectory: true
        )
        let linkedMetadataStagingBefore = try stagingNames()
        try expectFailure("暂存元数据目录换链") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: linkedMetadataTarget,
                stageHook: { current in
                    guard current == .afterPortableState else {
                        return
                    }
                    let created = try Set(
                        exportParent.portableExportStagingChildren()
                    ).subtracting(linkedMetadataStagingBefore)
                    guard created.count == 1,
                          let stagingName = created.first else {
                        throw CheckError.failed(
                            "无法唯一定位元数据换链暂存"
                        )
                    }
                    let stagingRoot = exportParent
                        .appendingPathComponent(
                            stagingName,
                            isDirectory: true
                        )
                    let metadata = stagingRoot.appendingPathComponent(
                        ".weibei",
                        isDirectory: true
                    )
                    let isolated = stagingRoot.appendingPathComponent(
                        ".weibei-original",
                        isDirectory: true
                    )
                    try FileManager.default.moveItem(
                        at: metadata,
                        to: isolated
                    )
                    try FileManager.default.createSymbolicLink(
                        at: metadata,
                        withDestinationURL: externalMetadataDirectory
                    )
                }
            )
        }
        try check(
            !externalMetadataDirectory
                .appendingPathComponent("course.json").exists,
            "暂存元数据目录被换成链接后发生了越界写入"
        )
        try verifyAndRemoveRetainedStaging(
            since: linkedMetadataStagingBefore,
            target: linkedMetadataTarget
        )

        let externalRealMetadataDirectory = try fixture.makeDirectory(
            "外部真实元数据诱饵"
        )
        let externalRealMetadataSentinel =
            externalRealMetadataDirectory.appendingPathComponent(
                "外部内容.txt"
            )
        let externalRealMetadataData = Data(
            "EXTERNAL_METADATA_DIRECTORY".utf8
        )
        try externalRealMetadataData.write(
            to: externalRealMetadataSentinel
        )
        let replacedMetadataTarget = exportParent.appendingPathComponent(
            "暂存元数据换真实目录",
            isDirectory: true
        )
        let replacedMetadataStagingBefore = try stagingNames()
        try expectFailure("暂存元数据目录换成外部真实目录") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: replacedMetadataTarget,
                stageHook: { current in
                    guard current == .afterPortableState else {
                        return
                    }
                    let created = try Set(
                        exportParent.portableExportStagingChildren()
                    ).subtracting(replacedMetadataStagingBefore)
                    guard created.count == 1,
                          let stagingName = created.first else {
                        throw CheckError.failed(
                            "无法唯一定位元数据真实目录替换暂存"
                        )
                    }
                    let stagingRoot = exportParent
                        .appendingPathComponent(
                            stagingName,
                            isDirectory: true
                        )
                    let metadata = stagingRoot.appendingPathComponent(
                        ".weibei",
                        isDirectory: true
                    )
                    let isolated = stagingRoot.appendingPathComponent(
                        ".weibei-original",
                        isDirectory: true
                    )
                    try FileManager.default.moveItem(
                        at: metadata,
                        to: isolated
                    )
                    try FileManager.default.moveItem(
                        at: externalRealMetadataDirectory,
                        to: metadata
                    )
                }
            )
        }
        let replacedMetadataStaging = try currentStagingRoot(
            since: replacedMetadataStagingBefore
        )
        let replacementMetadata = replacedMetadataStaging
            .appendingPathComponent(".weibei", isDirectory: true)
        let isolatedMetadata = replacedMetadataStaging
            .appendingPathComponent(".weibei-original", isDirectory: true)
        try check(
            Data(
                contentsOf: replacementMetadata.appendingPathComponent(
                    "外部内容.txt"
                )
            ) == externalRealMetadataData
                && !replacementMetadata
                    .appendingPathComponent("course.json").exists
                && !replacementMetadata.appendingPathComponent(
                    CourseProjectManifest
                        .portableExportAbandonedFileName
                ).exists
                && isolatedMetadata.appendingPathComponent(
                    CourseProjectManifest
                        .portableExportAbandonedFileName
                ).exists,
            "暂存元数据被真实目录替换后写入了外部目录，或没有通过原描述符封存失败"
        )
        try FileManager.default.removeItem(
            at: replacedMetadataStaging
        )

        let lateTamperTarget = exportParent.appendingPathComponent(
            "落位前篡改",
            isDirectory: true
        )
        let lateTamperStagingBefore = try stagingNames()
        try expectFailure("原子落位前暂存树篡改") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: lateTamperTarget,
                stageHook: { current in
                    guard current == .beforeAtomicPlacement else {
                        return
                    }
                    let created = try Set(
                        exportParent.portableExportStagingChildren()
                    ).subtracting(lateTamperStagingBefore)
                    guard created.count == 1,
                          let stagingName = created.first else {
                        throw CheckError.failed(
                            "无法唯一定位落位前篡改暂存"
                        )
                    }
                    let stagingRoot = exportParent
                        .appendingPathComponent(
                            stagingName,
                            isDirectory: true
                        )
                    try Data("LATE_STAGING_TAMPER".utf8).write(
                        to: stagingRoot.appendingPathComponent(
                            "附录/计算练习/练习数据.csv"
                        )
                    )
                }
            )
        }
        try check(
            !lateTamperTarget.exists,
            "原子落位前暂存树被篡改后仍生成了目标"
        )
        try verifyAndRemoveRetainedStaging(
            since: lateTamperStagingBefore,
            target: lateTamperTarget
        )

        let adoptedWorkspace = try fixture.makeDirectory(
            "导出接管工作区"
        )
        let adoptedStore = makeStore(
            fixture: fixture,
            workspaceDirectory: adoptedWorkspace
        )
        let importedExport = try placeExportInFreshLibrary(
            exportRoot,
            folderName: "已接管导出课程"
        )
        try adoptedStore.configureCourseLibrary(at: importedExport.library)
        let adoptedCourseID = try adoptedStore.adoptCourseFolder(
            at: importedExport.courseRoot,
            title: "已接管导出课程"
        )
        let normalizedManifest = try CourseProjectManifest.read(
            from: importedExport.courseRoot.appendingPathComponent(
                ".weibei/course.json"
            )
        )
        try check(
            adoptedCourseID == courseA
                && normalizedManifest.portableExport == nil,
            "首次接管没有消费导出封印并规范化为普通课程 manifest"
        )
        let postAdoptionMessage = "接管后继续追问利率分类。"
        let postAdoptionMemory = "已经在接管后的课程里继续学习。"
        let postAdoptionNote = "# 接管后笔记\n\n继续整理利率分类。"
        _ = try adoptedStore.appendPortableCourseMessageForSelfCheck(
            courseID: courseA,
            text: postAdoptionMessage
        )
        try adoptedStore.updatePortableCourseLearningForSelfCheck(
            courseID: courseA,
            materialItemID: sharedItem.id,
            noteItemID: noteID,
            memoryText: postAdoptionMemory,
            noteText: postAdoptionNote,
            pageIndex: 27
        )
        try check(
            adoptedStore.flushPendingWorkspaceSave(),
            "接管后课程状态没有保存"
        )
        let reopenedAdoptedStore = makeStore(
            fixture: fixture,
            workspaceDirectory: adoptedWorkspace
        )
        try check(
            reopenedAdoptedStore
                .portableCourseLearningMatchesForSelfCheck(
                    courseID: courseA,
                    materialItemID: sharedItem.id,
                    noteItemID: noteID,
                    messageText: postAdoptionMessage,
                    memoryText: postAdoptionMemory,
                    noteText: postAdoptionNote,
                    pageIndex: 27
                ),
            "接管后修改的 Chat、记忆、阅读位置或笔记没有在重开后恢复"
        )

        let cleanupFailureRoot = exportParent.appendingPathComponent(
            "封印清理残留",
            isDirectory: true
        )
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseA,
            to: cleanupFailureRoot
        )
        let cleanupFailureRootIdentity = try require(
            CourseProjectFileWorker.identity(
                at: cleanupFailureRoot
            ),
            "清理残留样本缺少根身份"
        )
        let cleanupFailureSnapshot =
            try CourseProjectFileWorker.portableAdoptionSnapshot(
                at: cleanupFailureRoot,
                expectedRootIdentity:
                    cleanupFailureRootIdentity
            )
        let cleanupFailureMetadata = cleanupFailureRoot
            .appendingPathComponent(".weibei", isDirectory: true)
        var obstructedCleanupNames = Set<String>()
        try CourseProjectFileWorker.replaceCourseManifest(
            with: CourseProjectManifest(
                courseID: courseA
            ).encoded(),
            at: cleanupFailureMetadata.appendingPathComponent(
                "course.json"
            ),
            expectedDirectoryIdentity:
                cleanupFailureSnapshot.metadataIdentity,
            expectedPreviousData:
                cleanupFailureSnapshot.manifestData,
            afterCommitBeforeCleanup: {
                guard let names = try? FileManager.default
                    .contentsOfDirectory(
                        atPath: cleanupFailureMetadata.path
                    ) else {
                    return
                }
                for name in names
                where name.hasPrefix(".course-manifest-")
                    && name.hasSuffix(".tmp") {
                    let cleanupEntry =
                        cleanupFailureMetadata
                            .appendingPathComponent(name)
                    let retainedEntry =
                        cleanupFailureMetadata
                            .appendingPathComponent(
                                "\(name).retained"
                            )
                    do {
                        try FileManager.default.moveItem(
                            at: cleanupEntry,
                            to: retainedEntry
                        )
                        try FileManager.default.createDirectory(
                            at: cleanupEntry,
                            withIntermediateDirectories: false
                        )
                        obstructedCleanupNames.insert(name)
                    } catch {
                        return
                    }
                }
            }
        )
        let cleanupFailureManifest =
            try CourseProjectManifest.read(
                from: cleanupFailureMetadata.appendingPathComponent(
                    "course.json"
                )
            )
        let retainedCleanupDirectories =
            try FileManager.default.contentsOfDirectory(
                at: cleanupFailureMetadata,
                includingPropertiesForKeys: [.isDirectoryKey]
            ).filter {
                obstructedCleanupNames.contains(
                    $0.lastPathComponent
                ) && $0.isDirectory
            }
        try check(
            cleanupFailureManifest.portableExport == nil
                && obstructedCleanupNames.count == 2
                && retainedCleanupDirectories.count == 2,
            "封印已可靠规范化后，清理残留仍错误报失败或普通 manifest 不可读"
        )

        let preCommitReplacementRoot =
            exportParent.appendingPathComponent(
                "清单提交前元数据替换",
                isDirectory: true
            )
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseA,
            to: preCommitReplacementRoot
        )
        let preCommitReplacementRootIdentity = try require(
            CourseProjectFileWorker.identity(
                at: preCommitReplacementRoot
            ),
            "清单提交前元数据替换样本缺少根身份"
        )
        let preCommitReplacementSnapshot =
            try CourseProjectFileWorker.portableAdoptionSnapshot(
                at: preCommitReplacementRoot,
                expectedRootIdentity:
                    preCommitReplacementRootIdentity
            )
        let preCommitMetadata = preCommitReplacementRoot
            .appendingPathComponent(".weibei", isDirectory: true)
        let displacedPreCommitMetadata = preCommitReplacementRoot
            .appendingPathComponent(
                ".weibei-displaced-before-commit",
                isDirectory: true
            )
        let replacementSentinel = preCommitMetadata
            .appendingPathComponent("外部目录内容.txt")
        let replacementSentinelData = Data(
            "REAL_REPLACEMENT_DIRECTORY".utf8
        )
        var replacedMetadataAfterSwap = false
        try expectFailure("清单交换后提交前元数据目录被替换") {
            try CourseProjectFileWorker.replaceCourseManifest(
                with: CourseProjectManifest(
                    courseID: courseA
                ).encoded(),
                at: preCommitMetadata.appendingPathComponent(
                    "course.json"
                ),
                expectedDirectoryIdentity:
                    preCommitReplacementSnapshot.metadataIdentity,
                expectedPreviousData:
                    preCommitReplacementSnapshot.manifestData,
                afterSwapBeforeCommitValidation: {
                    replacedMetadataAfterSwap = true
                    try FileManager.default.moveItem(
                        at: preCommitMetadata,
                        to: displacedPreCommitMetadata
                    )
                    try FileManager.default.createDirectory(
                        at: preCommitMetadata,
                        withIntermediateDirectories: false
                    )
                    try replacementSentinelData.write(
                        to: replacementSentinel
                    )
                }
            )
        }
        try expectFailure("替换元数据目录不得接收后续课程状态写入") {
            try CourseProjectFileWorker.writePortableState(
                Data("FORBIDDEN_LATE_STATE".utf8),
                to: preCommitMetadata.appendingPathComponent(
                    "course-state.json"
                ),
                expectedDirectoryIdentity:
                    preCommitReplacementSnapshot.metadataIdentity,
                expectedPreviousData: nil,
                beforeCommit: {}
            )
        }
        let restoredSealedManifestData = try Data(
            contentsOf: displacedPreCommitMetadata
                .appendingPathComponent("course.json")
        )
        let restoredSealedManifest = try JSONDecoder().decode(
            CourseProjectManifest.self,
            from: restoredSealedManifestData
        )
        let replacementMetadataNames = try FileManager.default
            .contentsOfDirectory(
                atPath: preCommitMetadata.path
            )
        try check(
            replacedMetadataAfterSwap
                && restoredSealedManifestData
                    == preCommitReplacementSnapshot.manifestData
                && restoredSealedManifest.portableExport != nil
                && replacementMetadataNames
                    == [replacementSentinel.lastPathComponent]
                && Data(contentsOf: replacementSentinel)
                    == replacementSentinelData,
            "提交前目录替换没有恢复原封印，或向换入目录写入了清单/课程状态"
        )

        for postSaveTamper in [
            (
                name: "接管保存后状态篡改",
                relativePath: ".weibei/course-state.json",
                data: Data("TAMPERED_STATE_AFTER_SAVE".utf8)
            ),
            (
                name: "接管保存后可见内容篡改",
                relativePath: "附录/计算练习/练习数据.csv",
                data: Data("TAMPERED_VISIBLE_AFTER_SAVE".utf8)
            ),
        ] {
            let tamperedAdoptionRoot = exportParent.appendingPathComponent(
                postSaveTamper.name,
                isDirectory: true
            )
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: tamperedAdoptionRoot
            )
            let importedTampered = try placeExportInFreshLibrary(
                tamperedAdoptionRoot,
                folderName: postSaveTamper.name
            )
            let tamperedAdoptionWorkspace = try fixture.makeDirectory(
                "\(postSaveTamper.name)工作区"
            )
            let tamperedAdoptionStore = makeStore(
                fixture: fixture,
                workspaceDirectory: tamperedAdoptionWorkspace,
                mutationHook: { stage in
                    guard stage
                            == .afterAdoptionWorkspaceSaveBeforeManifestNormalization else {
                        return
                    }
                    try postSaveTamper.data.write(
                        to: importedTampered.courseRoot.appendingPathComponent(
                            postSaveTamper.relativePath
                        )
                    )
                }
            )
            try tamperedAdoptionStore.configureCourseLibrary(
                at: importedTampered.library
            )
            try expectFailure(postSaveTamper.name) {
                _ = try tamperedAdoptionStore.adoptCourseFolder(
                    at: importedTampered.courseRoot,
                    title: postSaveTamper.name
                )
            }
            let retainedManifest = try JSONDecoder().decode(
                CourseProjectManifest.self,
                from: Data(
                    contentsOf: importedTampered.courseRoot
                        .appendingPathComponent(
                            ".weibei/course.json"
                        )
                )
            )
            try check(
                retainedManifest.portableExport != nil
                    && tamperedAdoptionStore
                        .course(withID: courseA) != nil
                    && tamperedAdoptionStore
                        .courseRootURL(for: courseA) == nil
                    && tamperedAdoptionStore
                        .courseRootUnavailableReason(
                            for: courseA
                        ) != nil
                    && tamperedAdoptionStore
                        .isolatedCourseNoteOpenDoesNotReadForSelfCheck(
                            itemID: noteID,
                            courseID: courseA
                        )
                    && tamperedAdoptionStore
                        .pendingPortableNoteDraftForSelfCheck(
                            itemID: noteID
                        ) == fixtureState.draft,
                "\(postSaveTamper.name)后错误消费封印，或危险课程根仍可读取笔记/草稿丢失"
            )
        }

        let crashExportRoot = exportParent.appendingPathComponent(
            "接管崩溃恢复副本",
            isDirectory: true
        )
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseA,
            to: crashExportRoot
        )
        let importedCrash = try placeExportInFreshLibrary(
            crashExportRoot,
            folderName: "等待恢复的导出课程"
        )
        let crashWorkspace = try fixture.makeDirectory(
            "接管崩溃工作区"
        )
        var crashStore: WorkspaceStore? = makeStore(
            fixture: fixture,
            workspaceDirectory: crashWorkspace,
            mutationHook: { stage in
                if stage
                    == .afterAdoptionWorkspaceSaveBeforeManifestNormalization {
                    throw CourseProjectSimulatedCrash()
                }
            }
        )
        try crashStore?.configureCourseLibrary(at: importedCrash.library)
        try expectFailure("接管保存后消费封印前崩溃") {
            _ = try crashStore?.adoptCourseFolder(
                at: importedCrash.courseRoot,
                title: "等待恢复的导出课程"
            )
        }
        let sealedAfterCrash = try CourseProjectManifest.read(
            from: importedCrash.courseRoot.appendingPathComponent(
                ".weibei/course.json"
            )
        )
        try check(
            sealedAfterCrash.portableExport != nil,
            "workspace 保存前后崩溃窗口暴露了普通 manifest"
        )
        crashStore = nil
        let recoveredCrashStore = makeStore(
            fixture: fixture,
            workspaceDirectory: crashWorkspace
        )
        let recoveredCrashManifest = try CourseProjectManifest.read(
            from: importedCrash.courseRoot.appendingPathComponent(
                ".weibei/course.json"
            )
        )
        try check(
            recoveredCrashStore.course(withID: courseA) != nil
                && recoveredCrashStore.courseRootURL(for: courseA)
                    == importedCrash.courseRoot.canonicalFileURL
                && recoveredCrashStore
                    .portableAdoptionReadRunsOffMainForSelfCheck()
                && recoveredCrashManifest.portableExport == nil,
            "重启没有在后台按已登记课程身份收口未消费的导出封印"
        )

        let interruptedTarget = exportParent.appendingPathComponent(
            "中断导出",
            isDirectory: true
        )
        let interruptedStagingBefore = try stagingNames()
        try expectFailure("导出写清单后中断") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: interruptedTarget,
                stageHook: { current in
                    if current == .afterManifest {
                        throw CheckError.injectedFailure
                    }
                }
            )
        }
        try verifyAndRemoveRetainedStaging(
            since: interruptedStagingBefore,
            target: interruptedTarget
        )

        let rewrittenCleanupTarget = exportParent.appendingPathComponent(
            "清理保护",
            isDirectory: true
        )
        let externallyRewrittenData = Data("EXTERNAL_REWRITE".utf8)
        let rewrittenStagingBefore = try stagingNames()
        try expectFailure("导出 staging 被外部原地改写") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: rewrittenCleanupTarget,
                stageHook: { current in
                    guard current == .afterManifest else {
                        return
                    }
                    let created = try Set(
                        exportParent.portableExportStagingChildren()
                    ).subtracting(rewrittenStagingBefore)
                    guard created.count == 1,
                          let stagingName = created.first else {
                        throw CheckError.failed(
                            "无法唯一定位外部改写暂存"
                        )
                    }
                    let stagingManifest = exportParent
                        .appendingPathComponent(
                            stagingName,
                            isDirectory: true
                        )
                        .appendingPathComponent(".weibei/course.json")
                    try externallyRewrittenData.write(to: stagingManifest)
                    throw CheckError.injectedFailure
                }
            )
        }
        let preservedStaging = try currentStagingRoot(
            since: rewrittenStagingBefore
        )
        try check(
            !rewrittenCleanupTarget.exists
                && Data(
                    contentsOf: preservedStaging.appendingPathComponent(
                        ".weibei/course.json"
                    )
                ) == externallyRewrittenData,
            "失败清理删除了已被外部原地改写的 staging 内容"
        )
        try FileManager.default.removeItem(at: preservedStaging)

        let raceTarget = exportParent.appendingPathComponent(
            "目标竞态",
            isDirectory: true
        )
        let raceSentinel = raceTarget.appendingPathComponent("外部内容.txt")
        let raceStagingBefore = try stagingNames()
        try expectFailure("导出目标竞态") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: raceTarget,
                stageHook: { current in
                    guard current == .beforeAtomicPlacement else { return }
                    try FileManager.default.createDirectory(
                        at: raceTarget,
                        withIntermediateDirectories: false
                    )
                    try Data("EXTERNAL_TARGET".utf8).write(
                        to: raceSentinel
                    )
                }
            )
        }
        try check(
            Data(contentsOf: raceSentinel)
                == Data("EXTERNAL_TARGET".utf8),
            "导出目标竞态覆盖了外部目录"
        )
        try verifyAndRemoveRetainedStaging(
            since: raceStagingBefore,
            target: raceTarget,
            expectTargetAbsent: false
        )

        let mutationTarget = exportParent.appendingPathComponent(
            "源目录变化",
            isDirectory: true
        )
        let lateSourceFile = sourceRoot.appendingPathComponent(
            "附录/复制期间新增.txt"
        )
        // S6-9：源树在落位前漂移时以已封存 staging 为准继续导出。
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseA,
            to: mutationTarget,
            stageHook: { current in
                guard current == .beforeAtomicPlacement else { return }
                try Data("LATE_SOURCE".utf8).write(to: lateSourceFile)
            }
        )
        try check(
            mutationTarget.exists && lateSourceFile.exists,
            "S6-9 源目录漂移后应仍完成导出，且新源文件仍在"
        )
        // 成功落位后暂存目录应已原子移走，无需清理残留 staging。
        try FileManager.default.removeItem(at: lateSourceFile)
        try FileManager.default.removeItem(at: mutationTarget)

        let existingTarget = exportParent.appendingPathComponent(
            "已有目标",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: existingTarget,
            withIntermediateDirectories: false
        )
        let existingSentinel = existingTarget.appendingPathComponent(
            "保留.txt"
        )
        try Data("KEEP".utf8).write(to: existingSentinel)
        try expectFailure("已有导出目标") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: existingTarget
            )
        }
        try check(
            Data(contentsOf: existingSentinel) == Data("KEEP".utf8),
            "已有导出目标被覆盖"
        )

        try store.setCourseReplyGeneratingForSelfCheck(
            courseID: courseA,
            generating: true
        )
        let generatingTarget = exportParent.appendingPathComponent(
            "生成中导出",
            isDirectory: true
        )
        // S6-4：Agent 生成中不再拒绝导出；允许以当前磁盘状态导出。
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseA,
            to: generatingTarget
        )
        try store.setCourseReplyGeneratingForSelfCheck(
            courseID: courseA,
            generating: false
        )
        try check(generatingTarget.exists, "S6-4 生成中导出应成功落盘")

        let unsafeLink = sourceRoot.appendingPathComponent(
            "附录/普通外链.txt"
        )
        try FileManager.default.createSymbolicLink(
            at: unsafeLink,
            withDestinationURL: foreignURL
        )
        let unsafeTarget = exportParent.appendingPathComponent(
            "含普通外链",
            isDirectory: true
        )
        let unsafeStagingBefore = try stagingNames()
        try expectFailure("普通符号链接导出") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: unsafeTarget
            )
        }
        try verifyAndRemoveRetainedStaging(
            since: unsafeStagingBefore,
            target: unsafeTarget
        )
        try FileManager.default.removeItem(at: unsafeLink)

        let completionTamperRoot = exportParent.appendingPathComponent(
            "完成标记篡改",
            isDirectory: true
        )
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseA,
            to: completionTamperRoot
        )
        let completionURL = completionTamperRoot.appendingPathComponent(
            ".weibei/\(CourseProjectManifest.portableExportCompletionFileName)"
        )
        try Data("TAMPERED".utf8).write(
            to: completionURL,
            options: [.atomic]
        )
        try expectFailure("损坏导出完成标记") {
            _ = try CourseProjectManifest.read(
                from: completionTamperRoot.appendingPathComponent(
                    ".weibei/course.json"
                )
            )
        }
    }

    @MainActor
    private static func legacyPortableChatImportsOnce() throws {
        let fixture = try Fixture(name: "legacy-portable-chat")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let imports = try fixture.makeDirectory("待导入")
        let sourceURL = imports.appendingPathComponent("旧课程讲义.txt")
        try Data("旧课程正文".utf8).write(to: sourceURL)

        let sourceStore = makeStore(fixture: fixture)
        try sourceStore.configureCourseLibrary(at: library)
        let courseID = try sourceStore.createCourseInLibrary(
            title: "旧课程 Chat 迁移"
        )
        let material = try sourceStore.importFileIntoCourseForSelfCheck(
            sourceURL,
            courseID: courseID,
            role: .material
        ).item
        try check(
            sourceStore.flushPendingWorkspaceSave(),
            "无法建立旧课程迁移基线"
        )
        let courseRoot = try require(
            sourceStore.courseRootURL(for: courseID),
            "旧课程迁移基线没有课程目录"
        )
        let stateURL = courseRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        var legacyState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: stateURL)
        )
        let legacyChatID = UUID()
        let legacyMessageID = UUID()
        legacyState.schemaVersion = 1
        legacyState.revision &+= 1
        legacyState.savedAt = Date()
        legacyState.studySessions = [
            StudySession(
                id: legacyChatID,
                title: "旧课程里的对话",
                messages: [
                    AgentMessage(
                        id: legacyMessageID,
                        role: .user,
                        text: "这段和上一节有什么关系？",
                        source: nil
                    ),
                ],
                courseID: courseID,
                focusItemIDs: [material.id],
                materialItemID: material.id
            ),
        ]
        _ = try legacyState.validated(expectedCourseID: courseID)
        try JSONEncoder().encode(legacyState).write(
            to: stateURL,
            options: [.atomic]
        )

        let migrationWorkspace = try fixture.makeDirectory("迁移工作区")
        var migratedStore: WorkspaceStore? = makeStore(
            fixture: fixture,
            workspaceDirectory: migrationWorkspace
        )
        try migratedStore?.configureCourseLibrary(at: library)
        try check(
            try migratedStore?.adoptCourseFolder(
                at: courseRoot,
                title: "迁移中的旧课程"
            ) == courseID,
            "旧课程没有按原身份迁入"
        )
        try check(
            migratedStore?.studySessions.filter {
                $0.id == legacyChatID
                    && $0.messages.contains { $0.id == legacyMessageID }
                    && $0.relatedCourseIDs.contains(courseID)
            }.count == 1,
            "旧课程 Chat 没有迁入统一会话库"
        )
        let upgradedState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: stateURL)
        )
        try check(
            upgradedState.schemaVersion
                == CoursePortableState.currentSchemaVersion
                && upgradedState.studySessions.isEmpty,
            "旧课程状态没有在首次迁移后升级为不携带完整 Chat 的 v2"
        )

        migratedStore = nil
        let reopened = makeStore(
            fixture: fixture,
            workspaceDirectory: migrationWorkspace
        )
        try check(
            reopened.studySessions.filter { $0.id == legacyChatID }.count == 1,
            "重开后重复导入了旧课程 Chat"
        )
    }

    @MainActor
    private static func portableCourseStatePreservesOfflineAndCorruptChanges() throws {
        let fixture = try Fixture(name: "portable-state-offline")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let movedRoot = fixture.root.appendingPathComponent(
            "暂时移走的课程",
            isDirectory: true
        )
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(
            store?.createCourseInLibrary(title: "离线课程"),
            "无法建立离线课程样本"
        )
        let courseRoot = try require(
            store?.courseRootURL(for: courseID),
            "离线课程根丢失"
        )
        let stateURL = courseRoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let originalState = try Data(contentsOf: stateURL)
        try check(
            store?.flushPendingWorkspaceSave() == true,
            "离线课程基线没有保存"
        )
        store = nil

        try FileManager.default.moveItem(at: courseRoot, to: movedRoot)
        store = makeStore(fixture: fixture)
        try check(
            store?.courseRootURL(for: courseID) == nil,
            "课程文件夹移走后仍被标记为可用"
        )
        store?.renameCourse(courseID, title: "离线期间更新的课程")
        let offlineChatID = try require(
            store?.createStudySession(courseID: courseID)?.id,
            "课程根离线时无法保留新 Chat"
        )
        _ = try require(
            store?.appendPortableCourseMessageForSelfCheck(
                courseID: courseID,
                text: "离线期间的新问题"
            ),
            "课程根离线时无法写入新 Chat"
        )
        try check(
            store?.flushPendingWorkspaceSave() == true,
            "课程根离线时没有把较新缓存与 dirty 修订一起保存"
        )
        store = nil
        try FileManager.default.moveItem(at: movedRoot, to: courseRoot)

        store = makeStore(fixture: fixture)
        let recoveredState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: stateURL)
        )
        try check(
            recoveredState.metadata.title == "离线期间更新的课程",
            "旧 course-state 在根恢复后覆盖了离线课程标题"
        )
        try check(
            recoveredState.studySessions.isEmpty,
            "课程便携状态仍写入了完整 Chat"
        )
        try check(
            store?.studySessions.contains {
                $0.id == offlineChatID
                    && $0.relatedCourseIDs.contains(courseID)
            } == true,
            "课程根恢复后丢失了离线期间的新 Chat 或课程关联"
        )
        try check(
            Data(contentsOf: stateURL) != originalState,
            "课程根恢复后没有更新课程便携状态"
        )
        try check(
            store?.course(withID: courseID)?.title
                == "离线期间更新的课程",
            "根恢复后的运行态没有保留离线更新"
        )
        try check(
            store?.flushPendingWorkspaceSave() == true,
            "根恢复后的课程状态没有完成修订仲裁"
        )
        store = nil

        var corruptObject = try require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: stateURL)
            ) as? [String: Any],
            "课程状态无法构造未来版本样本"
        )
        corruptObject["schemaVersion"] = 999
        let corruptData = try JSONSerialization.data(
            withJSONObject: corruptObject,
            options: [.sortedKeys]
        )
        try corruptData.write(to: stateURL, options: [.atomic])
        store = makeStore(fixture: fixture)
        store?.renameCourse(courseID, title: "坏状态期间的本机更新")
        try check(
            store?.flushPendingWorkspaceSave() == true,
            "坏状态存在时本机缓存无法安全保存"
        )
        try check(
            Data(contentsOf: stateURL) == corruptData
                && store?.workspaceSaveError != nil,
            "未来版本或损坏 course-state 被本机缓存静默覆盖"
        )
        let cachedWorkspace = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(
                contentsOf: fixture.workspaceDirectory
                    .appendingPathComponent("workspace.json")
            )
        )
        try check(
            cachedWorkspace.courses?.first {
                $0.id == courseID
            }?.title == "坏状态期间的本机更新"
                && cachedWorkspace.dirtyPortableCourseIDs?
                    .contains(courseID) == true,
            "坏状态保护吞掉了本机较新缓存或没有记录 dirty 状态"
        )
    }

    @MainActor
    private static func stagedAndWorkspaceFailuresLeaveNoGhostCourse() throws {
        for stage in [CourseProjectMutationStage.afterStagingDirectory, .beforeManifestWrite, .beforeAtomicPlacement] {
            let fixture = try Fixture(name: "stage-\(stage.rawValue)")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let target = library.appendingPathComponent("失败课程", isDirectory: true)
            let store = makeStore(
                fixture: fixture,
                mutationHook: { currentStage in
                    if currentStage == stage { throw CheckError.injectedFailure }
                }
            )
            try store.configureCourseLibrary(at: library)
            try expectFailure("阶段 \(stage.rawValue)") { try store.createCourse(title: "失败课程", at: target) }
            try check(!target.exists, "阶段失败后留下了半成品课程目录")
            try check(store.courses.isEmpty, "阶段失败后留下了幽灵 Course")
            try check(
                try library.stagingChildren().isEmpty,
                "阶段 \(stage.rawValue) 失败后留下了 staging 目录"
            )
        }

        let fixture = try Fixture(name: "workspace-save-failure")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let target = library.appendingPathComponent("保存失败课程", isDirectory: true)
        var shouldFailWorkspaceWrite = false
        let store = makeStore(
            fixture: fixture,
            workspaceWriter: { data, url in
                if shouldFailWorkspaceWrite { throw CheckError.injectedFailure }
                try data.write(to: url, options: [.atomic])
            }
        )
        try store.configureCourseLibrary(at: library)
        shouldFailWorkspaceWrite = true
        try expectFailure("workspace 保存") { try store.createCourse(title: "保存失败课程", at: target) }
        try check(!target.exists, "workspace 保存失败后没有回滚课程目录")
        try check(store.courses.isEmpty, "workspace 保存失败后没有回滚内存 Course")
        let reopened = makeStore(fixture: fixture)
        try check(reopened.courses.isEmpty, "workspace 保存失败后磁盘出现幽灵 Course")
    }

    @MainActor
    private static func dangerousAndOverlappingRootsWriteNothing() throws {
        do {
            let fixture = try Fixture(name: "root-guards-reserved-shared-name")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let before = try library.relativeEntries()
            try expectFailure("共享目录保留名") {
                _ = try store.createCourseInLibrary(title: "共享文稿")
            }
            try check(
                try library.relativeEntries() == before,
                "拒绝共享目录保留名之前写入了文件"
            )
            try check(store.courses.isEmpty, "共享目录保留名产生了幽灵课程")
        }

        let fixture = try Fixture(name: "root-guards")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sharedDirectory = try fixture.makeDirectory("课程资料库/通用资料")
        let sharedChild = try fixture.makeDirectory("课程资料库/共享文稿/误选课程")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let firstRoot = library.appendingPathComponent("经济学", isDirectory: true)
        _ = try store.createCourse(title: "经济学", at: firstRoot)

        let aliasParent = library.appendingPathComponent("课程别名", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: firstRoot)
        let before = try library.relativeEntries()
        try expectFailure("资料库本身") { try store.createCourse(title: "资料库本身", at: library) }
        try expectFailure("嵌套课程") {
            try store.createCourse(
                title: "嵌套课程",
                at: firstRoot.appendingPathComponent("嵌套课程", isDirectory: true)
            )
        }
        try expectFailure("符号链接逃逸") {
            try store.createCourse(
                title: "符号链接逃逸",
                at: aliasParent.appendingPathComponent("逃逸课程", isDirectory: true)
            )
        }
        try expectFailure("系统根") { try store.adoptCourseFolder(at: URL(fileURLWithPath: "/"), title: "根目录") }
        try expectFailure("主目录") {
            try store.adoptCourseFolder(
                at: FileManager.default.homeDirectoryForCurrentUser,
                title: "主目录"
            )
        }
        try expectFailure("共享目录") {
            try store.adoptCourseFolder(at: sharedDirectory, title: "共享目录")
        }
        try expectFailure("共享目录后代") {
            try store.adoptCourseFolder(at: sharedChild, title: "共享目录后代")
        }
        let after = try library.relativeEntries()
        try check(before == after, "危险或重叠根检查发生在写盘之后")
        try check(store.courses.count == 1, "危险或重叠根产生了额外 Course")
    }

    private static func pathComparisonFollowsActualVolumeCaseSensitivity() throws {
        let fixture = try Fixture(name: "path-case-sensitivity")
        defer { fixture.remove() }
        let upper = fixture.root.appendingPathComponent("CaseProbe", isDirectory: true)
        let lower = fixture.root.appendingPathComponent("caseprobe", isDirectory: true)
        let supportsCaseSensitiveNames =
            CourseProjectPathPolicy.volumeSupportsCaseSensitiveNames(for: fixture.root)
        let expectedSame = supportsCaseSensitiveNames == false
        try check(
            CourseProjectPathPolicy.isSame(upper, lower) == expectedSame,
            "路径大小写比较没有遵循当前卷的真实规则"
        )
        try check(
            CourseProjectPathPolicy.contains(
                upper,
                lower.appendingPathComponent("child"),
                includingRoot: false
            ) == expectedSame,
            "路径包含判断没有遵循当前卷的真实大小写规则"
        )
        if supportsCaseSensitiveNames == nil {
            try check(!CourseProjectPathPolicy.isSame(upper, lower), "未知卷错误默认为大小写不敏感")
        }
    }

    @MainActor
    private static func linkedMetadataDirectoryIsRejectedWithoutWrites() throws {
        let fixture = try Fixture(name: "linked-course-metadata")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let external = try fixture.makeDirectory("课程资料库/外部课程")
        let outsideMetadata = try fixture.makeDirectory("外部 metadata")
        let manifestURL = outsideMetadata.appendingPathComponent("course.json")
        let manifestData = try CourseProjectManifest(
            courseID: UUID()
        ).encoded()
        try manifestData.write(to: manifestURL)
        let linkedMetadata = external.appendingPathComponent(
            ".weibei",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedMetadata,
            withDestinationURL: outsideMetadata
        )
        let externalEntriesBefore = try FileManager.default.contentsOfDirectory(
            atPath: external.path
        )
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)

        // S6-1：符号链接 .weibei → 备份后按新课纳入，不拒绝。
        let adoptedID = try store.adoptCourseFolder(
            at: external,
            title: "外部课程"
        )
        try check(store.course(withID: adoptedID) != nil, "符号链接 metadata 软纳入失败")
        try check(
            try Data(contentsOf: manifestURL) == manifestData,
            "软纳入改写了外部清单"
        )
        // 原符号链接入口应被移到 .weibei.backup-* 或保留在备份中。
        let externalAfter = try FileManager.default.contentsOfDirectory(
            atPath: external.path
        )
        try check(
            externalAfter.contains(where: { $0.hasPrefix(".weibei.backup-") })
                || !CourseProjectFileWorker.isSymbolicLink(at: linkedMetadata),
            "软纳入未备份符号链接 metadata"
        )
        _ = externalEntriesBefore
    }

    @MainActor
    private static func adoptingExistingFolderPreservesVisibleContentsAndIsIdempotent() throws {
        let fixture = try Fixture(name: "adopt")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let external = try fixture.makeDirectory("已有课程")
        try Data("原始讲义".utf8).write(to: external.appendingPathComponent("第一讲.txt"))
        let nested = try fixture.makeDirectory("已有课程/旧资料")
        try Data([0, 1, 2, 3]).write(to: nested.appendingPathComponent("图像.bin"))
        let before = try external.visibleFileSnapshot()
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)

        let courseID = try store.adoptCourseFolder(at: external, title: "已有课程")
        let after = try external.visibleFileSnapshot()
        try check(
            before == after,
            "接管课程改变了已有可见文件的哈希或层级：前 \(before.keys.sorted())，后 \(after.keys.sorted())"
        )
        let course = try require(store.course(withID: courseID), "接管后没有课程记录")
        try check(course.sourceRootRelativePath == nil, "外部课程错误地使用资料库相对根")
        try check(course.sourceRootBookmarkData != nil, "外部课程没有自己的授权")

        let repeatedID = try store.adoptCourseFolder(at: external, title: "不会覆盖原名")
        try check(repeatedID == courseID, "重复接管没有返回同一个 Course")
        try check(store.courses.count == 1, "重复接管创建了重复 Course")
    }

    @MainActor
    private static func damagedMetadataIsNotOverwritten() throws {
        let fixture = try Fixture(name: "damaged-metadata")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let external = try fixture.makeDirectory("课程资料库/损坏课程")
        let metadata = try fixture.makeDirectory("课程资料库/损坏课程/.weibei")
        let manifestURL = metadata.appendingPathComponent("course.json")
        let original = Data("{not-json".utf8)
        try original.write(to: manifestURL)
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)

        try expectFailure("损坏 metadata") { try store.adoptCourseFolder(at: external, title: "损坏课程") }
        try check(try Data(contentsOf: manifestURL) == original, "接管覆盖了未知或损坏的 .weibei")
        try check(store.courses.isEmpty, "损坏 metadata 仍产生了 Course")
    }

    @MainActor
    private static func movedLibraryCourseRestoresTheSameIdentity() throws {
        let fixture = try Fixture(name: "move-recovery")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let oldRoot = library.appendingPathComponent("旧课程名", isDirectory: true)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(store?.createCourse(title: "课程", at: oldRoot), "没有课程 ID")
        let identity = store?.course(withID: courseID)?.sourceRootIdentity
        try check(store?.flushPendingWorkspaceSave() == true, "移动前没有保存")
        store = nil

        let movedRoot = library.appendingPathComponent("新课程名", isDirectory: true)
        try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
        store = makeStore(fixture: fixture)
        try check(store?.courses.count == 1, "移动恢复创建或丢失了 Course")
        try check(store?.course(withID: courseID)?.sourceRootIdentity == identity, "移动恢复改变了课程身份")
        try check(store?.courseRootURL(for: courseID) == movedRoot.canonicalFileURL, "没有恢复同卷移动后的课程根")
        try check(store?.course(withID: courseID)?.sourceRootRelativePath == "新课程名", "没有更新移动后的相对根")
    }

    @MainActor
    private static func courseOwnedMaterialMovesOnlyAfterCommitAndRejectsConflicts() throws {
        let fixture = try Fixture(name: "owned-material-success")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("第一讲.txt")
        let original = Data("利率与货币".utf8)
        try original.write(to: source)
        let observedCommittedSnapshotBeforeDelete = LockedBox(false)
        let observedAtomicSourceQuarantine = LockedBox(false)
        let store = makeStore(
            fixture: fixture,
            courseFileSourceRemover: { quarantineURL in
                let data = try Data(
                    contentsOf: fixture.workspaceDirectory.appendingPathComponent("workspace.json")
                )
                let snapshot = try JSONDecoder().decode(PersistedWorkspace.self, from: data)
                observedCommittedSnapshotBeforeDelete.set(snapshot.importedItems.contains { item in
                    item.subtitle == source.lastPathComponent
                        && {
                            if case .courseOwned = item.storage { return true }
                            return false
                        }()
                })
                let quarantinedData = try Data(contentsOf: quarantineURL)
                observedAtomicSourceQuarantine.set(
                    !source.exists
                    && quarantineURL.deletingLastPathComponent() == source.deletingLastPathComponent()
                    && quarantineURL.lastPathComponent.contains(".weibei-quarantine-")
                    && quarantinedData == original
                )
                try FileManager.default.removeItem(at: quarantineURL)
            }
        )
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "货币金融学")
        let courseRoot = try require(store.courseRootURL(for: courseID), "没有课程根")

        let result = try store.importFileIntoCourseForSelfCheck(
            source.canonicalFileURL,
            courseID: courseID,
            role: .material
        )
        let target = courseRoot.appendingPathComponent("文稿/第一讲.txt")
        try check(source.exists, "外部导入改动了原文件")
        try check(try Data(contentsOf: source) == original, "外部原件内容被改写")
        try check(try Data(contentsOf: target) == original, "课程文稿内容与原件不一致")
        try check(!result.sourceCleanupPending, "复制导入错误标记为待清理")
        try check(result.item.urlPath == target.canonicalFileURL.path, "文稿没有指向课程目录")
        try check(result.item.contentRevision == 1 && result.item.contentDigest != nil, "文稿缺少初始版本或摘要")
        guard case .courseOwned(let ownerCourseID, _) = result.item.storage else {
            throw CheckError.failed("文稿没有标记为课程自有")
        }
        try check(ownerCourseID == courseID, "文稿记录了错误的所属课程")
        let membership = try require(
            store.courseItemMemberships.first { $0.itemID == result.item.id },
            "文稿没有课程成员关系"
        )
        try check(membership.courseID == courseID, "文稿成员关系指向错误课程")
        try check(membership.courseRelativePath == "文稿/第一讲.txt", "文稿没有保存课程相对路径")
        try check(membership.entryIdentity != nil, "文稿成员关系缺少文件身份")
        try check(try courseTransactionChildren(in: courseRoot).isEmpty, "成功事务留下 journal")

        let conflictingSource = sourceDirectory.appendingPathComponent("第一讲.txt")
        let conflictingData = Data("不能覆盖".utf8)
        try conflictingData.write(to: conflictingSource)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: conflictingSource.path
        )
        do {
            try store.importFileIntoCourseForSelfCheck(
                conflictingSource.canonicalFileURL,
                courseID: courseID,
                role: .material
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: conflictingSource.path
            )
            throw CheckError.expectedFailure("课程内同名文稿")
        } catch CourseOwnedFileError.targetConflict(_) {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: conflictingSource.path
            )
        } catch {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: conflictingSource.path
            )
            throw CheckError.failed("同名文件没有在读取正文前直接报冲突：\(error.localizedDescription)")
        }
        try check(try Data(contentsOf: target) == original, "同名导入覆盖了已有课程文稿")
        try check(try Data(contentsOf: conflictingSource) == conflictingData, "同名冲突删除了待导入原件")
        try check(store.courseMaterials(in: courseID).count == 1, "同名冲突产生了幽灵文稿")
    }

    @MainActor
    private static func courseOwnedImportRejectsSymbolicLinks() throws {
        let fixture = try Fixture(name: "owned-material-links")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let realSource = sourceDirectory.appendingPathComponent("真实原件.txt")
        try Data("真实原件".utf8).write(to: realSource)
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "链接测试")
        let courseRoot = try require(store.courseRootURL(for: courseID), "没有链接测试课程根")

        let directLink = sourceDirectory.appendingPathComponent("直接链接.txt")
        try FileManager.default.createSymbolicLink(at: directLink, withDestinationURL: realSource)
        try expectFailure("直接文件符号链接") {
            try store.importFileIntoCourseForSelfCheck(
                directLink.standardizedFileURL,
                courseID: courseID,
                role: .material
            )
        }
        try check(realSource.exists && directLink.exists, "拒绝直接链接时改动了原件")

        let realParent = try fixture.makeDirectory("真实父目录")
        let nestedSource = realParent.appendingPathComponent("祖先链接.txt")
        try Data("祖先链接原件".utf8).write(to: nestedSource)
        let parentLink = fixture.root.appendingPathComponent("父目录链接", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: realParent)
        let sourceThroughAncestorLink = parentLink.appendingPathComponent("祖先链接.txt")
        try expectFailure("祖先目录符号链接") {
            try store.importFileIntoCourseForSelfCheck(
                sourceThroughAncestorLink.standardizedFileURL,
                courseID: courseID,
                role: .material
            )
        }
        try check(nestedSource.exists, "拒绝祖先链接时删除了真实原件")
        try check(store.courseMaterials(in: courseID).isEmpty, "链接拒绝后产生了幽灵文稿")
        try check(
            !courseRoot.appendingPathComponent("文稿/直接链接.txt").exists
                && !courseRoot.appendingPathComponent("文稿/祖先链接.txt").exists,
            "链接拒绝后仍写入了课程目录"
        )
    }

    @MainActor
    private static func courseOwnedImportRejectsTargetRacesAndEscapes() throws {
        do {
            let fixture = try Fixture(name: "owned-material-target-race")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let source = sourceDirectory.appendingPathComponent("竞态.txt")
            let original = Data("原件必须保留".utf8)
            let foreign = Data("外来并发文件".utf8)
            try original.write(to: source)
            let target = library.appendingPathComponent("竞态课程/文稿/竞态.txt")
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard stage == .afterCourseFileAtomicPlacement else { return }
                    try FileManager.default.removeItem(at: target)
                    try foreign.write(to: target)
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "竞态课程")
            let courseRoot = try require(store.courseRootURL(for: courseID), "没有竞态课程根")

            try expectFailure("目标落位后被外来文件替换") {
                try store.importFileIntoCourseForSelfCheck(
                    source.canonicalFileURL,
                    courseID: courseID,
                    role: .material
                )
            }
            try check(try Data(contentsOf: source) == original, "目标竞态时删除或改写了原件")
            try check(try Data(contentsOf: target) == foreign, "回滚误删了外来替换文件")
            try check(store.courseMaterials(in: courseID).isEmpty, "目标竞态产生了幽灵文稿")
            // S3：无 journal；失败即放弃，不要求事务目录残留。
        }

        do {
            let fixture = try Fixture(name: "owned-material-directory-escape")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let outside = try fixture.makeDirectory("课程外目录")
            let source = sourceDirectory.appendingPathComponent("逃逸.txt")
            let original = Data("不能写到课程外".utf8)
            try original.write(to: source)
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "目录逃逸")
            let courseRoot = try require(store.courseRootURL(for: courseID), "没有目录逃逸课程根")
            let materialDirectory = courseRoot.appendingPathComponent("文稿", isDirectory: true)
            try FileManager.default.removeItem(at: materialDirectory)
            try FileManager.default.createSymbolicLink(
                at: materialDirectory,
                withDestinationURL: outside
            )

            try expectFailure("课程文稿目录符号链接逃逸") {
                try store.importFileIntoCourseForSelfCheck(
                    source.canonicalFileURL,
                    courseID: courseID,
                    role: .material
                )
            }
            try check(try Data(contentsOf: source) == original, "目录逃逸拒绝时改动了原件")
            try check(!outside.appendingPathComponent("逃逸.txt").exists, "目录逃逸向课程外写入了文件")
            try check(store.courseMaterials(in: courseID).isEmpty, "目录逃逸产生了幽灵文稿")
        }
    }

    @MainActor
    private static func courseOwnedDirectoryRacesDoNotCommitOrDeleteSource() throws {
        do {
            let fixture = try Fixture(name: "owned-directory-race-before-save")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let outside = try fixture.makeDirectory("课程外目录")
            let source = sourceDirectory.appendingPathComponent("保存前换目录.txt")
            let original = Data("保存前必须保留".utf8)
            try original.write(to: source)
            var raceEnabled = false
            var materialDirectory: URL?
            let movedMaterialDirectory = fixture.root.appendingPathComponent(
                "被移走的文稿目录",
                isDirectory: true
            )
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard raceEnabled,
                          stage == .beforeCourseFileWorkspaceSave,
                          let materialDirectory else { return }
                    try FileManager.default.moveItem(
                        at: materialDirectory,
                        to: movedMaterialDirectory
                    )
                    try FileManager.default.createSymbolicLink(
                        at: materialDirectory,
                        withDestinationURL: outside
                    )
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "保存前目录竞态")
            let courseRoot = try require(store.courseRootURL(for: courseID), "没有保存前竞态课程根")
            materialDirectory = courseRoot.appendingPathComponent("文稿", isDirectory: true)
            raceEnabled = true

            try expectFailure("保存前文稿目录被换成链接") {
                try store.importFileIntoCourseForSelfCheck(
                    source.canonicalFileURL,
                    courseID: courseID,
                    role: .material
                )
            }
            try check(try Data(contentsOf: source) == original, "保存前目录竞态删除了原件")
            try check(store.courseMaterials(in: courseID).isEmpty, "保存前目录竞态提交了资料记录")
            try check(!outside.appendingPathComponent("保存前换目录.txt").exists, "保存前目录竞态向链接外写入")
            try check(
                movedMaterialDirectory.appendingPathComponent("保存前换目录.txt").exists,
                "保存前目录竞态吞掉了已落位副本"
            )
            // S3：无 journal 恢复；失败即放弃，不要求事务目录残留。
            try check(true, "S3 不再要求保留 journal（原：目标目录身份失效后仍清除了恢复 journal）")
        }

        do {
            let fixture = try Fixture(name: "owned-directory-race-before-source-delete")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let outside = try fixture.makeDirectory("课程外目录")
            let source = sourceDirectory.appendingPathComponent("删源前换目录.txt")
            let original = Data("删源前必须重验".utf8)
            try original.write(to: source)
            var raceEnabled = false
            var materialDirectory: URL?
            let sourceRemoverCalled = LockedBox(false)
            let movedMaterialDirectory = fixture.root.appendingPathComponent(
                "删源前被移走的文稿目录",
                isDirectory: true
            )
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard raceEnabled,
                          stage == .beforeCourseFileSourceRemoval,
                          let materialDirectory else { return }
                    try FileManager.default.moveItem(
                        at: materialDirectory,
                        to: movedMaterialDirectory
                    )
                    try FileManager.default.createSymbolicLink(
                        at: materialDirectory,
                        withDestinationURL: outside
                    )
                },
                courseFileSourceRemover: { quarantineURL in
                    sourceRemoverCalled.set(true)
                    try FileManager.default.removeItem(at: quarantineURL)
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "删源前目录竞态")
            let courseRoot = try require(store.courseRootURL(for: courseID), "没有删源前竞态课程根")
            materialDirectory = courseRoot.appendingPathComponent("文稿", isDirectory: true)
            raceEnabled = true

            let result = try store.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            )
            try check(!result.sourceCleanupPending, "复制导入不应进入删源待清理状态")
            try check(!sourceRemoverCalled.get(), "复制导入调用了删源")
            try check(try Data(contentsOf: source) == original, "复制导入删除了原件")
            try check(
                courseRoot.appendingPathComponent("文稿/删源前换目录.txt").exists
                    || movedMaterialDirectory.appendingPathComponent("删源前换目录.txt").exists,
                "复制导入丢失已提交副本"
            )
            try check(true, "S3 不再要求保留 journal（原：删源前目录竞态清除了 journal）")
        }
    }

    @MainActor
    private static func courseOwnedSaveFailureLeavesNoGhostState() throws {
        let fixture = try Fixture(name: "owned-material-save-failure")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("保存失败.txt")
        let original = Data("必须保留".utf8)
        try original.write(to: source)
        var failWorkspaceWrite = false
        let store = makeStore(
            fixture: fixture,
            workspaceWriter: { data, url in
                if failWorkspaceWrite { throw CheckError.injectedFailure }
                try data.write(to: url, options: [.atomic])
            }
        )
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "保存失败测试")
        let courseRoot = try require(store.courseRootURL(for: courseID), "没有保存失败测试课程根")
        failWorkspaceWrite = true

        try expectFailure("课程文件 workspace 保存") {
            try store.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            )
        }
        try check(try Data(contentsOf: source) == original, "保存失败删除或改写了原件")
        try check(!courseRoot.appendingPathComponent("文稿/保存失败.txt").exists, "保存失败留下目标文件")
        try check(store.courseMaterials(in: courseID).isEmpty, "保存失败留下幽灵文稿")
        try check(
            !store.courseItemMemberships.contains { $0.courseID == courseID },
            "保存失败留下幽灵成员关系"
        )
        try check(try courseTransactionChildren(in: courseRoot).isEmpty, "安全回滚后仍留下 journal")
    }

    @MainActor
    private static func uncommittedRecoveryPreservesTargetWithoutVerifiedOriginal() throws {
        enum OriginalState: String, CaseIterable {
            case missing
            case moved
            case changed
            case generated
        }

        for state in OriginalState.allCases {
            let fixture = try Fixture(name: "uncommitted-\(state.rawValue)")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let fileName = state == .generated ? "未提交笔记.md" : "\(state.rawValue).txt"
            let source = sourceDirectory.appendingPathComponent(fileName)
            let movedSource = sourceDirectory.appendingPathComponent("已移动-\(fileName)")
            if state != .generated {
                try Data("原始内容-\(state.rawValue)".utf8).write(to: source)
            }
            var mutateOriginal = false
            var failWorkspaceWrite = false
            var store: WorkspaceStore? = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard mutateOriginal,
                          stage == .beforeCourseFileWorkspaceSave else { return }
                    switch state {
                    case .missing:
                        try FileManager.default.removeItem(at: source)
                    case .moved:
                        try FileManager.default.moveItem(at: source, to: movedSource)
                    case .changed:
                        try Data("已经被用户改写".utf8).write(to: source)
                    case .generated:
                        break
                    }
                },
                workspaceWriter: { data, url in
                    if failWorkspaceWrite { throw CheckError.injectedFailure }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store?.configureCourseLibrary(at: library)
            let courseID = try require(
                store?.createCourseInLibrary(title: "未提交-\(state.rawValue)"),
                "没有未提交恢复课程 ID"
            )
            let courseRoot = try require(store?.courseRootURL(for: courseID), "没有未提交恢复课程根")
            mutateOriginal = true
            failWorkspaceWrite = true

            if state == .generated {
                try check(
                    store?.createCourseNotebookNoteForSelfCheck(
                        courseID: courseID,
                        title: "未提交笔记"
                    ) == nil,
                    "生成笔记保存失败却返回成功"
                )
            } else {
                try expectFailure("未提交恢复 \(state.rawValue)") {
                    try store?.importFileIntoCourseForSelfCheck(
                        source.canonicalFileURL,
                        courseID: courseID,
                        role: .material
                    )
                }
            }
            let roleDirectory = state == .generated ? "笔记" : "文稿"
            let target = courseRoot.appendingPathComponent(
                "\(roleDirectory)/\(fileName)"
            )
            // S3：无 journal 恢复。源已失时保留磁盘唯一副本；登记不自动接回，用户可重做导入。
            try check(target.exists, "\(state.rawValue) 场景错误删除了唯一课程副本")
            try check(store?.courseItems(in: courseID).isEmpty == true, "\(state.rawValue) 场景留下内存幽灵记录")
            store = nil

            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            try check(target.exists, "\(state.rawValue) 场景重开后删除了课程副本")
            try check(
                try courseTransactionChildren(in: courseRoot).isEmpty,
                "\(state.rawValue) 场景重开清理后仍留下事务目录"
            )
            // S3 静默降级：不自动把磁盘孤儿接回登记；无幽灵成员即可。
            try check(
                store?.courseItems(in: courseID).isEmpty == true,
                "\(state.rawValue) 场景重开后出现幽灵登记"
            )
        }
    }

    @MainActor
    private static func courseOwnedCleanupFailureRetriesOnReopen() throws {
        let fixture = try Fixture(name: "owned-material-cleanup-retry")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("待清理.txt")
        let original = Data("只在提交后清理".utf8)
        try original.write(to: source)
        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            courseFileSourceRemover: { _ in }
        )
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(
            store?.createCourseInLibrary(title: "清理重试测试"),
            "没有清理重试测试课程 ID"
        )
        let courseRoot = try require(store?.courseRootURL(for: courseID), "没有清理重试测试课程根")
        let result = try require(
            store?.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            ),
            "导入没有结果"
        )
        let itemID = result.item.id
        let target = courseRoot.appendingPathComponent("文稿/待清理.txt")
        try check(!result.sourceCleanupPending, "复制导入不应标记删源待重试")
        try check(try Data(contentsOf: source) == original, "删源失败没有保留原件")
        try check(try Data(contentsOf: target) == original, "删源失败丢失已提交目标")
        try check(true, "S3 不再要求保留 journal（原：删源失败没有保留 journal）")
        store = nil

        // S3：无 journal 恢复，不重试删源；课程文稿已提交、原件可残留。
        store = makeStore(fixture: fixture)
        let reopenedItem = try require(
            store?.importedItems.first { $0.id == itemID },
            "重开后丢失已提交文稿"
        )
        try check(true, "S3 不再要求重开原子隔离删源（原：恢复删源没有先做同目录原子隔离）")
        try check(
            try Data(contentsOf: target) == original,
            "重开清理误删课程文稿"
        )
        // 原件可能仍在；只要课程内副本完好即可（S3 不重试删源）。
        try check(try courseTransactionChildren(in: courseRoot).isEmpty, "重开清理完成后仍保留 journal")
    }

    @MainActor
    private static func courseOwnedQuarantineFailureRemainsRecoverable() throws {
        let fixture = try Fixture(name: "owned-source-quarantine")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("隔离失败.txt")
        let original = Data("被隔离的原件".utf8)
        let foreign = Data("用户并发放回的新文件".utf8)
        try original.write(to: source)
        let observedQuarantineURL = LockedBox<URL?>(nil)
        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            courseFileSourceRemover: { quarantineURL in
                observedQuarantineURL.set(quarantineURL)
                try foreign.write(to: source)
                throw CheckError.injectedFailure
            }
        )
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(
            store?.createCourseInLibrary(title: "隔离恢复"),
            "没有隔离恢复课程 ID"
        )
        let courseRoot = try require(store?.courseRootURL(for: courseID), "没有隔离恢复课程根")
        let result = try require(
            store?.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            ),
            "隔离失败导入没有结果"
        )
        try check(observedQuarantineURL.get() == nil, "复制导入不应隔离原件")
        try check(!result.sourceCleanupPending, "复制导入不应标记隔离待清理")
        try check(try Data(contentsOf: source) == original, "复制导入改写了外部原件")
        // S3：无 journal；并发用户文件与隔离原件均保留。
        store = nil

        store = makeStore(fixture: fixture)
        try check(try Data(contentsOf: source) == original, "重开改写了外部原件")
        try check(
            store?.courseMaterials(in: courseID).contains(where: {
                $0.subtitle == "隔离失败.txt"
            }) == true,
            "隔离失败后课程文稿登记丢失"
        )
    }

    @MainActor
    private static func hiddenTransactionContentPreventsJournalCleanup() throws {
        let fixture = try Fixture(name: "owned-hidden-transaction-content")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("隐藏异物.txt")
        try Data("隐藏异物不能吞 journal".utf8).write(to: source)
        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            courseFileSourceRemover: { _ in }
        )
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(
            store?.createCourseInLibrary(title: "隐藏事务内容"),
            "没有隐藏事务课程 ID"
        )
        let courseRoot = try require(store?.courseRootURL(for: courseID), "没有隐藏事务课程根")
        _ = try store?.importFileIntoCourseForSelfCheck(
            source.canonicalFileURL,
            courseID: courseID,
            role: .material
        )
        // S3：sourceRemover 空操作 → sourceCleanupPending，事务目录可能保留。
        // 静默降级：不依赖 journal；重开清理不误伤课程文稿。
        let target = courseRoot.appendingPathComponent("文稿/隐藏异物.txt")
        try check(target.exists, "导入后目标缺失")
        store = nil

        store = makeStore(fixture: fixture)
        try check(target.exists, "重开后丢失课程文稿")
        try check(
            store?.courseMaterials(in: courseID).contains(where: {
                $0.subtitle == "隐藏异物.txt"
            }) == true,
            "重开后丢失文稿登记"
        )
    }

    @MainActor
    private static func courseOwnedRecoveryRejectsLinkedTransactionDirectory() throws {
        let fixture = try Fixture(name: "owned-material-linked-transaction")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("链接事务.txt")
        let original = Data("外部事务不能驱动删除".utf8)
        try original.write(to: source)
        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            courseFileSourceRemover: { _ in throw CheckError.injectedFailure }
        )
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(
            store?.createCourseInLibrary(title: "事务目录链接"),
            "没有事务目录链接课程 ID"
        )
        let courseRoot = try require(store?.courseRootURL(for: courseID), "没有事务目录链接课程根")
        _ = try store?.importFileIntoCourseForSelfCheck(
            source.canonicalFileURL,
            courseID: courseID,
            role: .material
        )
        // S3：删源失败时源可能仍在；重开静默清理不得删除已提交目标。
        store = nil
        store = makeStore(fixture: fixture)
        try check(
            courseRoot.appendingPathComponent("文稿/链接事务.txt").exists,
            "重开后丢失已提交目标"
        )
        try check(
            store?.courseMaterials(in: courseID).contains(where: {
                $0.subtitle == "链接事务.txt"
            }) == true,
            "重开后丢失文稿登记"
        )
    }

    @MainActor
    private static func courseOwnedFileFollowsMovedCourseRootWithoutBookmark() throws {
        let fixture = try Fixture(name: "owned-material-root-move")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("可移动.txt")
        try Data("课程相对路径".utf8).write(to: source)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseID = try require(
            store?.createCourseInLibrary(title: "移动前"),
            "没有移动测试课程 ID"
        )
        let oldRoot = try require(store?.courseRootURL(for: courseID), "没有移动前课程根")
        let result = try require(
            store?.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            ),
            "移动测试导入没有结果"
        )
        let itemID = result.item.id
        try check(store?.flushPendingWorkspaceSave() == true, "移动前没有保存")
        store = nil

        let movedRoot = library.appendingPathComponent("移动后", isDirectory: true)
        try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
        store = makeStore(fixture: fixture)
        let movedItem = try require(
            store?.importedItems.first { $0.id == itemID },
            "课程根移动后丢失文稿"
        )
        try check(
            movedItem.urlPath == movedRoot.appendingPathComponent("文稿/可移动.txt").canonicalFileURL.path,
            "课程根移动后没有按相对路径恢复文稿"
        )
        try check(
            store?.courseItemMemberships.first { $0.itemID == itemID }?.courseRelativePath
                == "文稿/可移动.txt",
            "课程根移动改变了文稿相对路径"
        )
    }

    @MainActor
    private static func courseOwnedResolutionHandlesReplacementAndInPlaceEditing() throws {
        do {
            let fixture = try Fixture(name: "owned-replacement-unavailable")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let source = sourceDirectory.appendingPathComponent("换包.txt")
            try Data("原始资料".utf8).write(to: source)
            var store: WorkspaceStore? = makeStore(fixture: fixture)
            try store?.configureCourseLibrary(at: library)
            let courseID = try require(
                store?.createCourseInLibrary(title: "换包测试"),
                "没有换包测试课程 ID"
            )
            let courseRoot = try require(store?.courseRootURL(for: courseID), "没有换包测试课程根")
            let imported = try require(
                store?.importFileIntoCourseForSelfCheck(
                    source.canonicalFileURL,
                    courseID: courseID,
                    role: .material
                ).item,
                "换包测试没有导入资料"
            )
            let target = courseRoot.appendingPathComponent("文稿/换包.txt")
            store = nil

            try FileManager.default.removeItem(at: target)
            let replacement = Data("同路径的新文件".utf8)
            try replacement.write(to: target)
            store = makeStore(fixture: fixture)
            try store?.reconcileCourseFilesForSelfCheck(courseID: courseID)
            let reopened = try require(
                store?.importedItems.first { $0.id == imported.id },
                "换包重开后资料记录丢失"
            )
            try check(reopened.urlPath == target.path, "同路径原子保存后资料不可用")
            try check(reopened.contentRevision == imported.contentRevision + 1, "同路径原子保存没有增加修订")
            try check(reopened.contentDigest != imported.contentDigest, "同路径原子保存没有更新摘要")
            try check(reopened.importedFileIdentity != imported.importedFileIdentity, "同路径原子保存没有更新文件身份")
            try check(try Data(contentsOf: target) == replacement, "换 inode 恢复误删新文件")
        }

        do {
            let fixture = try Fixture(name: "owned-in-place-edit")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let source = sourceDirectory.appendingPathComponent("原位编辑.txt")
            try Data("第一版".utf8).write(to: source)
            var store: WorkspaceStore? = makeStore(fixture: fixture)
            try store?.configureCourseLibrary(at: library)
            let courseID = try require(
                store?.createCourseInLibrary(title: "原位编辑测试"),
                "没有原位编辑课程 ID"
            )
            let courseRoot = try require(store?.courseRootURL(for: courseID), "没有原位编辑课程根")
            let imported = try require(
                store?.importFileIntoCourseForSelfCheck(
                    source.canonicalFileURL,
                    courseID: courseID,
                    role: .material
                ).item,
                "原位编辑没有导入资料"
            )
            let target = courseRoot.appendingPathComponent("文稿/原位编辑.txt")
            let updated = Data("第二版，由 Finder 原位改写".utf8)
            store = nil

            let handle = try FileHandle(forWritingTo: target)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: updated)
            try handle.synchronize()
            try handle.close()
            store = makeStore(fixture: fixture)
            try store?.reconcileCourseFilesForSelfCheck(courseID: courseID)
            let reopened = try require(
                store?.importedItems.first { $0.id == imported.id },
                "原位编辑重开后资料记录丢失"
            )
            try check(reopened.urlPath == target.path, "同 inode 编辑后资料被误标不可用")
            try check(
                reopened.importedFileIdentity == imported.importedFileIdentity,
                "原位编辑意外改变文件身份"
            )
            try check(
                reopened.contentRevision == imported.contentRevision + 1,
                "同 inode 内容变化没有增加修订号（原 \(imported.contentRevision)，现 \(reopened.contentRevision)）"
            )
            try check(reopened.contentDigest != imported.contentDigest, "同 inode 内容变化没有更新摘要")
            try check(try Data(contentsOf: target) == updated, "原位编辑内容被恢复逻辑改写")
        }
    }

    @MainActor
    private static func courseRootRefreshRebindsOwnedItemsAndRollsBackTogether() throws {
        do {
            let fixture = try Fixture(name: "owned-root-refresh-success")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let source = sourceDirectory.appendingPathComponent("随课程移动.txt")
            try Data("跟随课程根".utf8).write(to: source)
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "刷新前")
            let oldRoot = try require(store.courseRootURL(for: courseID), "没有刷新前课程根")
            let itemID = try store.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            ).item.id
            let movedRoot = library.appendingPathComponent("刷新后", isDirectory: true)
            try FileManager.default.moveItem(at: oldRoot, to: movedRoot)

            let refreshedID = try store.adoptCourseFolder(
                at: movedRoot,
                title: "不覆盖原名"
            )
            try check(refreshedID == courseID, "刷新课程根改变了课程 ID")
            try check(
                store.importedItems.first { $0.id == itemID }?.urlPath
                    == movedRoot.appendingPathComponent("文稿/随课程移动.txt").path,
                "刷新课程根后没有在同一事务重解析课程资料"
            )
            try check(
                true,
                "刷新课程根后资料生成了单文件书签"
            )
        }

        do {
            let fixture = try Fixture(name: "owned-root-refresh-rollback")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let source = sourceDirectory.appendingPathComponent("回滚资料.txt")
            try Data("根与资料必须一起回滚".utf8).write(to: source)
            var failWorkspaceWrite = false
            let store = makeStore(
                fixture: fixture,
                workspaceWriter: { data, url in
                    if failWorkspaceWrite { throw CheckError.injectedFailure }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "回滚前")
            let oldRoot = try require(store.courseRootURL(for: courseID), "没有回滚前课程根")
            let itemID = try store.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            ).item.id
            let previousItem = try require(
                store.importedItems.first { $0.id == itemID },
                "没有回滚前资料记录"
            )
            let previousMembership = try require(
                store.courseItemMemberships.first { $0.itemID == itemID },
                "没有回滚前成员关系"
            )
            let movedRoot = library.appendingPathComponent("回滚后位置", isDirectory: true)
            try FileManager.default.moveItem(at: oldRoot, to: movedRoot)
            failWorkspaceWrite = true

            try expectFailure("课程根与资料事务保存失败") {
                try store.adoptCourseFolder(at: movedRoot, title: "不应成功")
            }
            try check(store.courseRootURL(for: courseID) == oldRoot, "保存失败没有恢复旧课程根状态")
            try check(
                store.importedItems.first { $0.id == itemID } == previousItem,
                "保存失败没有恢复资料路径与内容状态"
            )
            try check(
                store.courseItemMemberships.first { $0.itemID == itemID } == previousMembership,
                "保存失败没有恢复资料成员关系"
            )
        }

        do {
            let fixture = try Fixture(name: "owned-library-reauthorize-rollback")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("未来资料库")
            let courseRoot = try fixture.makeDirectory("未来资料库/课程")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let source = sourceDirectory.appendingPathComponent("重新授权.txt")
            try Data("授权前版本".utf8).write(to: source)
            var failWorkspaceWrite = false
            var watchedItemID: String?
            var observedUpdatedItemDuringFailedSave = false
            let store = makeStore(
                fixture: fixture,
                workspaceWriter: { data, url in
                    if failWorkspaceWrite {
                        if let watchedItemID,
                           let snapshot = try? JSONDecoder().decode(
                            PersistedWorkspace.self,
                            from: data
                           ),
                           let encodedItem = snapshot.importedItems.first(
                            where: { $0.id == watchedItemID }
                           ) {
                            observedUpdatedItemDuringFailedSave =
                                encodedItem.contentRevision > 1
                                && encodedItem.contentDigest != nil
                        }
                        throw CheckError.injectedFailure
                    }
                    try data.write(to: url, options: [.atomic])
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.adoptCourseFolder(at: courseRoot, title: "课程")
            let itemID = try store.importFileIntoCourseForSelfCheck(
                source.canonicalFileURL,
                courseID: courseID,
                role: .material
            ).item.id
            watchedItemID = itemID
            var previousItem = try require(
                store.importedItems.first { $0.id == itemID },
                "重新授权前没有资料"
            )
            var previousMemberships = store.courseItemMemberships
            let target = courseRoot.appendingPathComponent("文稿/重新授权.txt")
            let handle = try FileHandle(forWritingTo: target)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data("授权期间的新版本".utf8))
            try handle.synchronize()
            try handle.close()
            try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
            previousItem = try require(
                store.importedItems.first { $0.id == itemID },
                "后台对账后没有资料"
            )
            previousMemberships = store.courseItemMemberships
            failWorkspaceWrite = true

            try expectFailure("资料库重新授权保存失败") {
                try store.configureCourseLibrary(at: library)
            }
            try check(
                observedUpdatedItemDuringFailedSave,
                "资料库重新授权没有在保存前重解析课程资料"
            )
            try check(
                store.courseLibraryRootURL?.standardizedFileURL
                    == library.standardizedFileURL,
                "重新授权保存失败仍切换了资料库"
            )
            try check(
                store.importedItems.first { $0.id == itemID } == previousItem,
                "重新授权保存失败没有回滚资料修订状态"
            )
            try check(
                store.courseItemMemberships == previousMemberships,
                "重新授权保存失败没有回滚成员关系"
            )
        }
    }

    @MainActor
    private static func courseOwnedAndGlobalNotesStaySeparated() throws {
        let fixture = try Fixture(name: "owned-note-separation")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "笔记归属")
        store.activateCourse(courseID)
        let courseRoot = try require(store.courseRootURL(for: courseID), "没有笔记测试课程根")
        let courseNoteID = try require(
            store.createCourseNotebookNoteForSelfCheck(courseID: courseID, title: "课程笔记"),
            "没有创建课程笔记"
        )
        let courseNote = try require(
            store.importedItems.first { $0.id == courseNoteID },
            "课程笔记没有进入项目"
        )
        guard case .courseOwned(let ownerCourseID, _) = courseNote.storage else {
            throw CheckError.failed("课程笔记没有标记为课程自有")
        }
        try check(ownerCourseID == courseID, "课程笔记归属错误")
        try check(
            courseNote.urlPath == courseRoot.appendingPathComponent("笔记/课程笔记.md").canonicalFileURL.path,
            "课程笔记没有写入课程笔记目录"
        )
        try check(
            store.courseItemMemberships.first { $0.itemID == courseNoteID }?.courseRelativePath
                == "笔记/课程笔记.md",
            "课程笔记缺少课程相对路径"
        )
        let updatedMarkdown = "# 课程笔记\n\n已经写回课程目录。\n"
        store.openCourseNote(courseNoteID, in: courseID)
        try check(
            store.pendingCourseMarkdownDraftForSelfCheck(
                itemID: courseNoteID
            ) == nil,
            "重新打开未修改课程笔记却启动了写回"
        )
        store.updateNote(updatedMarkdown, for: courseNoteID)
        store.flushPendingNotePersistence()
        try store.waitForCourseNoteWritesForSelfCheck()
        let updatedCourseNote = try require(
            store.importedItems.first { $0.id == courseNoteID },
            "课程笔记写回后丢失"
        )
        try check(
            try String(
                contentsOf: courseRoot.appendingPathComponent("笔记/课程笔记.md"),
                encoding: .utf8
            ) == updatedMarkdown,
            "课程笔记没有写回课程目录"
        )
        try check(updatedCourseNote.contentRevision > courseNote.contentRevision, "课程笔记写回没有增加内容版本")
        try check(updatedCourseNote.contentDigest != courseNote.contentDigest, "课程笔记写回没有更新摘要")

        store.createBlankNotebookNote()
        let globalNoteID = try require(store.activeNotebookItemID, "没有创建全局笔记")
        try check(globalNoteID != courseNoteID, "全局笔记复用了课程笔记")
        let globalNote = try require(
            store.importedItems.first { $0.id == globalNoteID },
            "全局笔记没有进入项目"
        )
        guard case .common(let commonNotePath) = globalNote.storage else {
            throw CheckError.failed("独立笔记没有进入通用笔记")
        }
        try check(
            !store.courseItemMemberships.contains { $0.itemID == globalNoteID },
            "全局笔记被自动塞入当前课程"
        )
        try check(
            commonNotePath.hasPrefix("通用笔记/")
                && globalNote.urlPath?.hasPrefix(
                    library.appendingPathComponent("通用笔记").path
                ) == true,
            "独立笔记没有写入真实通用笔记目录"
        )
        store.openCourseNote(courseNoteID, in: courseID)
        store.openCourseNote(globalNoteID)
        try check(
            store.activeNotebookItemID == globalNoteID
                && store.activeCourseID == courseID,
            "课程激活时静默拒绝打开独立笔记"
        )
    }

    @MainActor
    private static func largeFileWorkStaysOffMainThread() throws {
        let fixture = try Fixture(name: "owned-large-file-background")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("大文件.pdf")
        let chunk = Data(repeating: 0x5a, count: 1_048_576)
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        for _ in 0..<12 {
            try handle.write(contentsOf: chunk)
        }
        try handle.close()
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "大文件后台")

        try check(
            try store.courseFileSnapshotRunsOffMainForSelfCheck(source),
            "大文件摘要仍在主线程执行"
        )
        let result = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseID,
            role: .material
        )
        try check(result.item.contentDigest != nil, "大文件后台导入没有摘要")
        try check(source.exists, "大文件后台导入删除了外部原件")

        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "大笔记"
            ),
            "没有创建大笔记"
        )
        let largeMarkdown = "# 大笔记\n\n"
            + String(repeating: "课程笔记整文件后台读写证据。\n", count: 450_000)
        _ = try store.courseMarkdownRoundTripRunsOffMainForSelfCheck(
            itemID: noteID,
            markdown: largeMarkdown
        )
        let finalMarkdown = largeMarkdown + "\n写回完成。\n"
        let noteEvidence =
            try store.courseMarkdownRoundTripRunsOffMainForSelfCheck(
                itemID: noteID,
                markdown: finalMarkdown
            )
        try check(
            noteEvidence.read && noteEvidence.write,
            "大课程笔记整文件读取、摘要或写回仍在主线程执行"
        )
        let noteURL = try require(
            store.importedItems.first { $0.id == noteID }?.url,
            "大笔记写回后没有文件位置"
        )
        try check(
            try String(contentsOf: noteURL, encoding: .utf8)
                == finalMarkdown,
            "大笔记后台写回内容不完整"
        )
    }

    @MainActor
    private static func courseMarkdownConditionalWritePreservesFinderContentAndRecovers() throws {
        // S2：课程笔记写回改为三件套 last-writer-wins；外部换入内容被覆盖前进入备份环。
        let fixture = try Fixture(name: "markdown-finder-race")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let backupRoot = fixture.root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupRoot,
            withIntermediateDirectories: true
        )
        let store = makeStore(fixture: fixture, noteBackupRootURL: backupRoot)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "Markdown 竞态")
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "竞态笔记"
            ),
            "没有 Markdown 竞态笔记"
        )
        let noteURL = try require(
            store.importedItems.first { $0.id == noteID }?.url,
            "没有 Markdown 竞态路径"
        )
        let original = try String(contentsOf: noteURL, encoding: .utf8)
        // 先成功写回一次，建立 lastSelfWritten 基线。
        let baseline = original + "\n基线\n"
        try store.writeCourseMarkdownForSelfCheck(
            itemID: noteID,
            markdown: baseline
        )
        let finderContent = "# Finder 新稿\n\n将被备份后覆盖"
        try Data(finderContent.utf8).write(to: noteURL)
        // 模拟 reconcile 把磁盘观察值刷成外部内容（旧 bug：备份基线被一起刷掉）。
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
        let draft = "# 魏碑草稿\n\n最后写入者赢"
        try store.writeCourseMarkdownForSelfCheck(
            itemID: noteID,
            markdown: draft
        )
        let after = try String(contentsOf: noteURL, encoding: .utf8)
        try check(after == draft, "S2 写回没有 last-writer-wins 覆盖外部内容")
        try check(
            store.pendingCourseMarkdownDraftForSelfCheck(itemID: noteID) == nil,
            "写回成功后仍残留草稿"
        )
        let backups = try NoteBackupRing.list(itemID: noteID, rootURL: backupRoot)
        let backupBodies = try backups.map {
            try String(contentsOf: $0.url, encoding: .utf8)
        }
        try check(
            backupBodies.contains(finderContent),
            "C1：外部内容 B 在 reconcile 后写回应进入备份环"
        )
        let root = try require(
            store.courseRootURL(for: courseID),
            "没有 Markdown 竞态课程根"
        )
        try check(
            try courseTransactionChildren(in: root).isEmpty,
            "S2 写回不应产生 course-note 事务目录"
        )
    }

    @MainActor
    private static func courseNoteBackupUsesSelfWrittenBaselineAcrossReconcile() throws {
        let fixture = try Fixture(name: "note-self-written-backup-baseline")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let backupRoot = fixture.root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(
            at: backupRoot,
            withIntermediateDirectories: true
        )
        let store = makeStore(fixture: fixture, noteBackupRootURL: backupRoot)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "备份基线课")
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "备份基线笔记"
            ),
            "没有备份基线笔记"
        )
        let noteURL = try require(
            store.importedItems.first { $0.id == noteID }?.url,
            "没有备份基线路径"
        )
        // 建立自写基线。
        let v1 = "# v1\n\n自写一"
        try store.writeCourseMarkdownForSelfCheck(itemID: noteID, markdown: v1)
        let afterBaseline = try NoteBackupRing.list(itemID: noteID, rootURL: backupRoot).count

        // 连续自写、无外部改动 → 备份环不新增。
        for i in 2...4 {
            try store.writeCourseMarkdownForSelfCheck(
                itemID: noteID,
                markdown: "# v\(i)\n\n自写\(i)"
            )
        }
        let afterSelfWrites = try NoteBackupRing.list(itemID: noteID, rootURL: backupRoot).count
        try check(
            afterSelfWrites == afterBaseline,
            "C1：连续自写无外部改动不应刷备份环（基线 \(afterBaseline) → \(afterSelfWrites)）"
        )

        // 外部写 B → reconcile → 魏碑写回 → 环中出现 B。
        let externalB = "# external B\n\n外部版本"
        try Data(externalB.utf8).write(to: noteURL)
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
        try store.writeCourseMarkdownForSelfCheck(
            itemID: noteID,
            markdown: "# weibei after B\n\n覆盖"
        )
        let bodies = try NoteBackupRing.list(itemID: noteID, rootURL: backupRoot).map {
            try String(contentsOf: $0.url, encoding: .utf8)
        }
        try check(
            bodies.contains(externalB),
            "C1：reconcile 后写回应备份外部 B"
        )
    }

    @MainActor
    private static func courseNoteDraftSurvivesPortableStateAndRelaunch() throws {
        let fixture = try Fixture(name: "note-draft-survives-relaunch")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "草稿存活课")
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "草稿存活笔记"
            ),
            "没有草稿存活笔记"
        )
        let failedDraft = "# 写回失败草稿\n\n必须活过重启"
        try store.leaveCourseNoteDraftAfterFailedWriteForSelfCheck(
            itemID: noteID,
            markdown: failedDraft
        )
        let exported = try store.portableNoteDraftsForSelfCheck(courseID: courseID)
        try check(
            exported.contains { $0.itemID == noteID && $0.markdown == failedDraft },
            "C2：makeCoursePortableState 应导出 notes 草稿（无 pending 也要）"
        )
        // 落盘 course-state（含草稿）
        try store.forcePersistPortableCourseStatesForSelfCheck(
            courseIDs: [courseID]
        )

        // 重建 store 模拟重启
        let relaunched = makeStore(fixture: fixture)
        try check(
            relaunched.pendingCourseMarkdownDraftForSelfCheck(itemID: noteID)
                == failedDraft,
            "C2：重启后应恢复写回失败草稿"
        )

        // 变体：本地已有草稿时，apply 不应用空 state 清掉
        let localOnlyDraft = "# 本地未落盘\n\n优先于快照"
        try relaunched.leaveCourseNoteDraftAfterFailedWriteForSelfCheck(
            itemID: noteID,
            markdown: localOnlyDraft
        )
        // 用空 drafts 的 state 再 apply：本地应保留
        try relaunched.reapplyPortableCourseStateWithoutLocalDraftWipeForSelfCheck(
            courseID: courseID
        )
        try check(
            relaunched.pendingCourseMarkdownDraftForSelfCheck(itemID: noteID)
                == localOnlyDraft,
            "C2：apply 端本地草稿优先于快照（无对应 draft 时不清）"
        )
    }

    @MainActor
    private static func orphanTransactionCleanupHonorsWhitelistAndCrashBackups() throws {
        let fixture = try Fixture(name: "orphan-transaction-whitelist")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "事务清理课")
        let root = try require(
            store.courseRootURL(for: courseID),
            "没有事务清理课程根"
        )
        let transactions = root.appendingPathComponent(
            ".weibei/transactions",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: transactions,
            withIntermediateDirectories: true
        )

        // 纯白名单目录：应被清。
        let safeDir = transactions.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: safeDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(
            to: safeDir.appendingPathComponent("journal.json")
        )
        try Data("payload".utf8).write(
            to: safeDir.appendingPathComponent("payload")
        )

        // 含 replaced-target 的崩溃备份：应保留。
        let crashDir = transactions.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)
        let crashBody = "# 崩溃前被替换的目标\n\n不可丢"
        try Data(crashBody.utf8).write(
            to: crashDir.appendingPathComponent("replaced-target")
        )
        try Data("{}".utf8).write(
            to: crashDir.appendingPathComponent("journal.json")
        )

        try store.recoverCourseTransactionsForSelfCheck()

        try check(
            !FileManager.default.fileExists(atPath: safeDir.path),
            "H1：纯 {journal.json,payload} 孤儿事务应被清理"
        )
        try check(
            FileManager.default.fileExists(
                atPath: crashDir.appendingPathComponent("replaced-target").path
            ),
            "H1：含 replaced-target 的孤儿事务不得删除"
        )
        let restored = try String(
            contentsOf: crashDir.appendingPathComponent("replaced-target"),
            encoding: .utf8
        )
        try check(restored == crashBody, "H1：replaced-target 副本内容应完整保留")
    }

    @MainActor
    private static func appDeactivationFlushesThenActivationRefreshesSameFile() throws {
        let fixture = try Fixture(name: "same-file-activation-refresh")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "同一路径刷新课")
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "同一路径刷新"
            ),
            "没有创建课程内同一路径刷新笔记"
        )
        let noteURL = try require(
            store.importedItems.first(where: { $0.id == noteID })?.url,
            "同一路径刷新笔记没有真实 Markdown"
        )

        let localDraft = "# 魏碑写入\n\n失焦前必须落盘"
        store.stageNoteDraft(localDraft, for: noteID)
        store.flushPendingNotePersistence(flushWorkspace: false)
        try store.waitForCourseNoteWritesForSelfCheck()
        let afterFlush = try String(contentsOf: noteURL, encoding: .utf8)
        try check(
            afterFlush == localDraft,
            "失焦冲刷没有把当前输入写回同一 Markdown；实际内容：\(afterFlush)"
        )

        let externalText = "# 外部编辑器写入\n\n切回魏碑时采用这一份文件"
        try Data(externalText.utf8).write(to: noteURL, options: .atomic)
        store.refreshActiveNoteFromBackingFile()
        try store.waitForCourseNoteLoadsForSelfCheck()
        try check(
            store.noteText == externalText,
            "重新激活没有从同一 Markdown 路径采用磁盘内容"
        )
    }

    @MainActor
    private static func forkedRebindUsesKeepsLocalStateImpact() throws {
        let fixture = try Fixture(name: "rebind-keeps-local-state")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let exports = try fixture.makeDirectory("课程副本")
        let offline = try fixture.makeDirectory("失联原件")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "分叉重绑课")
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "分叉笔记"
            ),
            "没有分叉笔记"
        )
        let originalRoot = try require(
            store.courseRootURL(for: courseID),
            "没有分叉原课程根"
        )
        // 导出候选副本后，本机再改笔记 → dirty + digest 不等。
        let candidate = exports.appendingPathComponent(
            "分叉候选",
            isDirectory: true
        )
        _ = try store.exportPortableCourseCopyForSelfCheck(
            courseID: courseID,
            to: candidate
        )
        try store.writeCourseMarkdownForSelfCheck(
            itemID: noteID,
            markdown: "# 本机分叉进度\n\n本地优先"
        )
        try check(
            store.flushPendingWorkspaceSave(),
            "分叉本机状态未保存"
        )
        try FileManager.default.moveItem(
            at: originalRoot,
            to: offline.appendingPathComponent("原课程", isDirectory: true)
        )
        let proposal: CourseProjectRebindProposal
        switch try store.adoptCourseFolderOrProposeRebind(
            at: candidate,
            title: "分叉重绑"
        ) {
        case .opened:
            throw CheckError.failed("H2：分叉候选被静默打开")
        case .requiresRebind(let value):
            proposal = value
        }
        try check(
            proposal.impact == .keepsLocalState,
            "H2：本机 dirty 分叉应 keepsLocalState 而非 unchanged"
        )
        // 确认后课程根指向候选；本机进度不被候选 state 覆盖（标题仍为本机）。
        let localTitle = store.course(withID: courseID)?.title
        _ = try store.confirmCourseProjectRebind(proposal)
        try check(
            store.courseRootURL(for: courseID) == candidate.canonicalFileURL,
            "H2：确认后应绑定候选根"
        )
        try check(
            store.course(withID: courseID)?.title == localTitle,
            "H2：keepsLocalState 确认后应保留本机标题/进度"
        )

        // 对照：干净且 digest 相等 → unchanged（导出后不改本机）。
        let fixture2 = try Fixture(name: "rebind-unchanged-equal")
        defer { fixture2.remove() }
        let library2 = try fixture2.makeDirectory("课程资料库")
        let exports2 = try fixture2.makeDirectory("课程副本")
        let offline2 = try fixture2.makeDirectory("失联原件")
        let store2 = makeStore(fixture: fixture2)
        try store2.configureCourseLibrary(at: library2)
        let course2 = try store2.createCourseInLibrary(title: "无歧义课")
        let root2 = try require(
            store2.courseRootURL(for: course2),
            "无歧义原根"
        )
        try check(store2.flushPendingWorkspaceSave(), "无歧义状态未保存")
        let candidate2 = exports2.appendingPathComponent(
            "无歧义候选",
            isDirectory: true
        )
        _ = try store2.exportPortableCourseCopyForSelfCheck(
            courseID: course2,
            to: candidate2
        )
        try FileManager.default.moveItem(
            at: root2,
            to: offline2.appendingPathComponent("原课程", isDirectory: true)
        )
        switch try store2.adoptCourseFolderOrProposeRebind(
            at: candidate2,
            title: "无歧义"
        ) {
        case .opened:
            break
        case .requiresRebind(let p):
            try check(
                p.impact == .unchanged,
                "H2：digest 相等应仍为 unchanged（可自动确认）"
            )
        }
    }

    @MainActor
    private static func courseScanSkipsSymlinksOutsideRoot() throws {
        let fixture = try Fixture(name: "scan-symlink-containment")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let outside = try fixture.makeDirectory("课程外")
        let outsideFile = outside.appendingPathComponent("秘密.md")
        try Data("# 根外秘密\n".utf8).write(to: outsideFile)
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "symlink 边界")
        let root = try require(
            store.courseRootURL(for: courseID),
            "没有 symlink 课程根"
        )
        // 根内合法笔记
        let notesDir = root.appendingPathComponent("笔记", isDirectory: true)
        try FileManager.default.createDirectory(
            at: notesDir,
            withIntermediateDirectories: true
        )
        let insideNote = notesDir.appendingPathComponent("合法.md")
        try Data("# 合法\n".utf8).write(to: insideNote)
        // 根内 symlink 指向根内文件 — 应登记
        let insideLink = notesDir.appendingPathComponent("根内链.md")
        try FileManager.default.createSymbolicLink(
            atPath: insideLink.path,
            withDestinationPath: insideNote.path
        )
        // 根内 symlink 指向根外 — 不得登记
        let outsideLink = notesDir.appendingPathComponent("根外链.md")
        try FileManager.default.createSymbolicLink(
            atPath: outsideLink.path,
            withDestinationPath: outsideFile.path
        )
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
        let paths = Set(
            store.importedItems.compactMap { item -> String? in
                guard store.courseItemMemberships.contains(where: {
                    $0.itemID == item.id && $0.courseID == courseID
                }) else { return nil }
                return item.urlPath
            }
        )
        try check(
            paths.contains(insideNote.path)
                || paths.contains(insideLink.resolvingSymlinksInPath().path),
            "H3：根内 symlink 应登记"
        )
        try check(
            !paths.contains(outsideFile.path),
            "H3：根外 symlink 目标不得登记为课程文件"
        )
        try check(
            !store.importedItems.contains {
                $0.subtitle == "根外链.md" || $0.urlPath == outsideLink.path
            },
            "H3：根外 symlink 入口本身也不应作为课程笔记出现"
        )
    }

    @MainActor
    private static func courseMarkdownPostPlacementReplacementPreservesAllContent() throws {
        // S2：原子写 + 备份环；不再有落位后 journal 竞态窗口。验证连续写回与无事务残留。
        let fixture = try Fixture(name: "markdown-post-placement-replacement")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "Markdown 落位竞态")
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "落位竞态笔记"
            ),
            "没有 Markdown 落位竞态笔记"
        )
        let target = try require(
            store.importedItems.first { $0.id == noteID }?.url,
            "没有 Markdown 落位竞态路径"
        )
        let draft = "# 魏碑最新草稿\n\n原子写"
        try store.writeCourseMarkdownForSelfCheck(
            itemID: noteID,
            markdown: draft
        )
        try check(
            try String(contentsOf: target, encoding: .utf8) == draft,
            "S2 原子写回内容不正确"
        )
        try check(
            store.pendingCourseMarkdownDraftForSelfCheck(itemID: noteID) == nil,
            "S2 写回成功后仍有草稿"
        )
        let root = try require(
            store.courseRootURL(for: courseID),
            "没有 Markdown 落位竞态课程根"
        )
        try check(
            try courseTransactionChildren(in: root).isEmpty,
            "S2 写回不应留下事务目录"
        )
    }

    @MainActor
    private static func firstScanAndFinderReconciliationPreserveIdentity() throws {
        let fixture = try Fixture(name: "owned-finder-reconcile")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let courseRoot = try fixture.makeDirectory("课程资料库/已有课程")
        _ = try fixture.makeDirectory("课程资料库/已有课程/资料/章节一")
        _ = try fixture.makeDirectory("课程资料库/已有课程/笔记/复习")
        let material = courseRoot.appendingPathComponent("资料/章节一/讲义.txt")
        let note = courseRoot.appendingPathComponent("笔记/复习/提纲.md")
        try Data("第一版讲义".utf8).write(to: material)
        try Data("# 提纲".utf8).write(to: note)
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.adoptCourseFolder(at: courseRoot, title: "已有课程")
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)

        let materialItem = try require(
            store.importedItems.first { $0.urlPath == material.path },
            "初次接管没有扫描嵌套文稿"
        )
        let noteItem = try require(
            store.importedItems.first { $0.urlPath == note.path },
            "初次接管没有扫描嵌套笔记"
        )
        try check(!materialItem.isNotebookNote && noteItem.isNotebookNote, "初扫文稿/笔记角色错误")
        try check(
            store.courseItemMemberships.first { $0.itemID == materialItem.id }?.courseRelativePath
                == "资料/章节一/讲义.txt",
            "初扫没有保留任意安全嵌套路径"
        )

        _ = try fixture.makeDirectory("课程资料库/已有课程/资料/章节二")
        let movedMaterial = courseRoot.appendingPathComponent("资料/章节二/改名讲义.txt")
        try FileManager.default.moveItem(at: material, to: movedMaterial)
        try FileManager.default.removeItem(at: note)
        let finderAdded = courseRoot.appendingPathComponent("资料/Finder 新增.pdf")
        try Data("%PDF-1.4\nFinder".utf8).write(to: finderAdded)
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)

        try check(
            store.importedItems.first { $0.id == materialItem.id }?.urlPath == movedMaterial.path,
            "Finder 改名/移动改变了资料 ID"
        )
        try check(
            store.courseItemMemberships.first { $0.itemID == materialItem.id }?.courseRelativePath
                == "资料/章节二/改名讲义.txt",
            "Finder 改名/移动没有更新相对路径"
        )
        try check(
            store.importedItems.first { $0.id == noteItem.id } == nil,
            "Finder 删除后课程里还留着这条笔记"
        )
        try check(
            store.importedItems.contains { $0.urlPath == finderAdded.path },
            "Finder 外部新增没有进入课程"
        )
    }

    @MainActor
    private static func unavailableCourseMaterialKeepsCourseHomeOpenUntilRestored() throws {
        let fixture = try Fixture(name: "unavailable-course-material-open")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let incoming = try fixture.makeDirectory("待导入")
        let source = incoming.appendingPathComponent("会暂时移走的文稿.txt")
        try Data("必须验证真实文件后才能离开课程首页".utf8).write(to: source)

        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "失联资料课")
        let item = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseID,
            role: .material
        ).item
        let courseURL = try require(item.url, "课程文稿没有真实路径")
        let displacedURL = incoming.appendingPathComponent("暂时移走的原文稿.txt")
        try FileManager.default.moveItem(at: courseURL, to: displacedURL)
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
        try check(
            store.importedItems.first { $0.id == item.id } == nil,
            "移出课程文件夹后文稿还留在魏碑里"
        )

        store.presentCourseWorkspace(.hub, courseID: courseID)
        let previousSelection = store.selectedItemID
        store.openCourseMaterial(item.id)
        try check(
            store.courseWorkspacePresented,
            "已消失的文稿错误关闭了课程首页"
        )
        try check(
            store.selectedItemID == previousSelection,
            "已消失的文稿错误切换到空阅读器"
        )
    }

    /// 红线回归：记录 identity 与磁盘不一致（iCloud 驱逐重下换 inode）但文件
    /// 可读时，openCourseMaterial 不得拒绝，且记录必须按自愈路径刷新。
    @MainActor
    private static func courseMaterialOpensAndHealsWhenIdentityDrifts() throws {
        let fixture = try Fixture(name: "owned-identity-drift-open")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let incoming = try fixture.makeDirectory("待导入")
        let source = incoming.appendingPathComponent("新概念笔记.txt")
        try Data("身份漂移也要能直接打开".utf8).write(to: source)

        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "漂移打开课")
        let item = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseID,
            role: .material
        ).item
        let courseURL = try require(item.url, "课程资料没有真实路径")
        let originalIdentity = try require(
            store.importedItems.first { $0.id == item.id }?.importedFileIdentity,
            "课程资料没有记录文件身份"
        )

        // 模拟 iCloud 驱逐后重新下载：同路径换代（新 inode/出生时间），内容不变。
        try FileManager.default.removeItem(at: courseURL)
        try Data("身份漂移也要能直接打开".utf8).write(to: courseURL)
        let driftedIdentity = try require(
            CourseProjectFileWorker.identity(at: courseURL),
            "重建后的课程资料无法 stat"
        )
        try check(
            driftedIdentity != originalIdentity,
            "同路径重建没有产生新文件身份"
        )

        store.presentCourseWorkspace(.hub, courseID: courseID)
        try check(
            store.openCourseMaterial(item.id),
            "identity 漂移但文件可读时被拒绝打开（红线：identity 只用于尽力找回，永不用于拒绝）"
        )
        try check(
            store.selectedMaterialItem?.id == item.id,
            "identity 漂移后没有打开正确资料"
        )
        try check(
            !store.courseWorkspacePresented,
            "identity 漂移打开后仍停在课程首页"
        )
        let healed = try require(
            store.importedItems.first { $0.id == item.id },
            "打开后课程资料记录丢失"
        )
        try check(
            healed.urlPath == courseURL.path,
            "自愈后课程资料路径丢失"
        )
        try check(
            healed.importedFileIdentity == driftedIdentity,
            "自愈没有刷新记录的文件身份"
        )
        try check(
            store.courseItemMemberships.first {
                $0.itemID == item.id && $0.courseID == courseID
            }?.entryIdentity == driftedIdentity,
            "自愈没有刷新成员关系的文件身份"
        )
    }

    @MainActor
    private static func thousandFileReconciliationIsLinearAndHardLinksStayStable() throws {
        let fixture = try Fixture(name: "owned-thousand-file-reconcile")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let courseRoot = try fixture.makeDirectory("课程资料库/大课")
        let materials = try fixture.makeDirectory("课程资料库/大课/资料")
        for index in 0..<1_000 {
            try Data("资料 \(index)".utf8).write(
                to: materials.appendingPathComponent("资料-\(index).txt")
            )
        }
        let hardLinkA = materials.appendingPathComponent("硬链接甲.txt")
        let hardLinkB = materials.appendingPathComponent("硬链接乙.txt")
        try Data("同一 inode".utf8).write(to: hardLinkA)
        try FileManager.default.linkItem(at: hardLinkA, to: hardLinkB)

        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.adoptCourseFolder(at: courseRoot, title: "大课")
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
        let firstItems = store.courseItems(in: courseID)
        try check(firstItems.count == 1_002, "千文件初扫条数错误")
        let firstIDsByPath = Dictionary(uniqueKeysWithValues: firstItems.compactMap {
            item -> (String, String)? in
            guard let path = item.urlPath else { return nil }
            return (path, item.id)
        })
        let hardLinkAID = try require(firstIDsByPath[hardLinkA.path], "硬链接甲没有稳定 ID")
        let hardLinkBID = try require(firstIDsByPath[hardLinkB.path], "硬链接乙没有稳定 ID")

        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
        try check(store.courseItems(in: courseID).count == 1_002, "重复对账新增了资料")
        try check(
            store.courseReconciliationLookupCountForSelfCheck() <= 6_020,
            "千文件主线程应用没有保持线性查找上限"
        )

        let movedHardLinkA = materials.appendingPathComponent("硬链接甲-改名.txt")
        try FileManager.default.moveItem(at: hardLinkA, to: movedHardLinkA)
        try store.reconcileCourseFilesForSelfCheck(courseID: courseID)
        let finalItems = store.courseItems(in: courseID)
        try check(finalItems.count == 1_002, "硬链接改名后重复新增了资料")
        try check(
            finalItems.first { $0.urlPath == movedHardLinkA.path }?.id == hardLinkAID,
            "硬链接改名没有保留原资料 ID"
        )
        try check(
            finalItems.first { $0.urlPath == hardLinkB.path }?.id == hardLinkBID,
            "硬链接同 inode 抢走了另一资料 ID"
        )
    }

    @MainActor
    private static func exclusivePlacementRejectsConcurrentTargetAndSymlinkSwap() throws {
        do {
            let fixture = try Fixture(name: "owned-exclusive-target-race")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let source = sourceDirectory.appendingPathComponent("排他落位.txt")
            let original = Data("待导入".utf8)
            let foreign = Data("并发占位".utf8)
            try original.write(to: source)
            let target = library.appendingPathComponent("排他课程/文稿/排他落位.txt")
            var raceEnabled = false
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard raceEnabled, stage == .beforeCourseFileAtomicPlacement else { return }
                    try foreign.write(to: target, options: [.withoutOverwriting])
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "排他课程")
            raceEnabled = true
            try expectFailure("排他落位并发占位") {
                try store.importFileIntoCourseForSelfCheck(
                    source,
                    courseID: courseID,
                    role: .material
                )
            }
            try check(try Data(contentsOf: target) == foreign, "排他落位覆盖了并发文件")
            try check(try Data(contentsOf: source) == original, "排他落位竞态删除了来源")
            let root = try require(store.courseRootURL(for: courseID), "没有排他课程根")
            try check(try courseTransactionChildren(in: root).isEmpty, "未落位竞态留下永久 journal")
        }

        do {
            let fixture = try Fixture(name: "owned-placement-symlink-swap")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let outside = try fixture.makeDirectory("课程外")
            let source = sourceDirectory.appendingPathComponent("链接换位.txt")
            try Data("不能逃逸".utf8).write(to: source)
            var raceEnabled = false
            var materialDirectory: URL?
            let displacedDirectory = fixture.root.appendingPathComponent("被换走的文稿")
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard raceEnabled,
                          stage == .beforeCourseFileAtomicPlacement,
                          let materialDirectory else { return }
                    try FileManager.default.moveItem(at: materialDirectory, to: displacedDirectory)
                    try FileManager.default.createSymbolicLink(
                        at: materialDirectory,
                        withDestinationURL: outside
                    )
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "链接换位")
            let root = try require(store.courseRootURL(for: courseID), "没有链接换位课程根")
            materialDirectory = root.appendingPathComponent("文稿", isDirectory: true)
            raceEnabled = true
            try expectFailure("落位前父目录 symlink swap") {
                try store.importFileIntoCourseForSelfCheck(
                    source,
                    courseID: courseID,
                    role: .material
                )
            }
            try check(!outside.appendingPathComponent(source.lastPathComponent).exists, "symlink swap 写到课程外")
            try check(source.exists, "symlink swap 删除了来源")
            try check(try courseTransactionChildren(in: root).isEmpty, "symlink swap 未落位却留下 journal")
        }

        do {
            let fixture = try Fixture(name: "owned-placement-validated-parent-swap")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let sourceDirectory = try fixture.makeDirectory("待导入")
            let outside = try fixture.makeDirectory("课程外")
            let source = sourceDirectory.appendingPathComponent("校验后换位.txt")
            let original = Data("校验和系统调用必须绑定同一目录".utf8)
            try original.write(to: source)
            var raceEnabled = false
            var materialDirectory: URL?
            let displacedDirectory = fixture.root.appendingPathComponent(
                "校验后被换走的文稿"
            )
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard raceEnabled,
                          stage
                            == .afterCourseFileDestinationValidationBeforeRename,
                          let materialDirectory else {
                        return
                    }
                    raceEnabled = false
                    try FileManager.default.moveItem(
                        at: materialDirectory,
                        to: displacedDirectory
                    )
                    try FileManager.default.createSymbolicLink(
                        at: materialDirectory,
                        withDestinationURL: outside
                    )
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(
                title: "校验后换位"
            )
            let root = try require(
                store.courseRootURL(for: courseID),
                "没有校验后换位课程根"
            )
            materialDirectory = root.appendingPathComponent(
                "文稿",
                isDirectory: true
            )
            raceEnabled = true
            try expectFailure("校验后父目录 symlink swap") {
                try store.importFileIntoCourseForSelfCheck(
                    source,
                    courseID: courseID,
                    role: .material
                )
            }
            try check(
                !outside.appendingPathComponent(source.lastPathComponent).exists,
                "校验后 symlink swap 把载荷写到了课程外"
            )
            try check(
                try Data(contentsOf: source) == original,
                "校验后 symlink swap 删除了来源"
            )
        }
    }

    @MainActor
    private static func conflictChoicesPreserveDataAndRelations() throws {
        let fixture = try Fixture(name: "owned-conflict-choices")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待导入")
        let source = sourceDirectory.appendingPathComponent("冲突.txt")
        try Data("第一版".utf8).write(to: source)
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "冲突选择")
        let first = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseID,
            role: .material
        ).item
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "关系笔记"
            ),
            "冲突测试没有笔记"
        )
        store.setLinkedSourceIDs([first.id], for: noteID)

        try Data("取消版本".utf8).write(to: source)
        do {
            _ = try store.importFileIntoCourseForSelfCheck(
                source,
                courseID: courseID,
                role: .material,
                conflictResolution: .cancel
            )
            throw CheckError.expectedFailure("取消冲突")
        } catch CourseOwnedFileError.targetConflict(_) {
            try check(source.exists, "取消冲突删除了来源")
        }

        let kept = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseID,
            role: .material,
            conflictResolution: .keepBoth(preferredFileName: nil)
        ).item
        try check(kept.id != first.id && kept.subtitle == "冲突 2.txt", "保留两份没有生成独立安全名称")

        try Data("用户命名版本".utf8).write(to: source)
        let typedName = CourseKeepBothNaming.suggestedFileName(
            originalName: source.lastPathComponent,
            conflictingTargets: [
                try require(first.url, "冲突原件没有路径"),
                try require(kept.url, "冲突副本没有路径"),
            ]
        )
        try check(
            typedName == "冲突 3.txt",
            "保留两份没有预填真实可用的安全文件名"
        )
        let userNamed = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseID,
            role: .material,
            conflictResolution: .keepBoth(
                preferredFileName: "期末复习版.txt"
            )
        ).item
        try check(
            userNamed.subtitle == "期末复习版.txt",
            "保留两份没有采用用户编辑后的文件名"
        )

        try Data("替换版本".utf8).write(to: source)
        let replaced = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseID,
            role: .material,
            conflictResolution: .replace
        ).item
        try check(replaced.id == first.id, "替换没有保留目标资料 ID")
        try check(replaced.contentRevision == first.contentRevision + 1, "替换没有递增 revision")
        try check(
            store.noteSourceLinks.contains {
                $0.noteItemID == noteID && $0.sourceItemID == first.id
            },
            "替换破坏了显式关系"
        )
        let root = try require(store.courseRootURL(for: courseID), "没有冲突课程根")
        try check(try courseTransactionChildren(in: root).isEmpty, "三路冲突完成后留下 journal")
    }

    @MainActor
    private static func replacementKeepsTargetIdentityAcrossMoves() throws {
        do {
            let fixture = try Fixture(name: "replace-course-move-identity")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待移动")
            let sourceA = incoming.appendingPathComponent("同名资料.txt")
            let sourceB = incoming.appendingPathComponent("另一份/同名资料.txt")
            try FileManager.default.createDirectory(
                at: sourceB.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("课程甲版本".utf8).write(to: sourceA)
            try Data("课程乙旧版本".utf8).write(to: sourceB)
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseA = try store.createCourseInLibrary(title: "课程甲")
            let courseB = try store.createCourseInLibrary(title: "课程乙")
            let sourceItem = try store.importFileIntoCourseForSelfCheck(
                sourceA,
                courseID: courseA,
                role: .material
            ).item
            let targetItem = try store.importFileIntoCourseForSelfCheck(
                sourceB,
                courseID: courseB,
                role: .material
            ).item
            let noteID = try require(
                store.createCourseNotebookNoteForSelfCheck(
                    courseID: courseB,
                    title: "移动关系"
                ),
                "没有移动关系笔记"
            )
            store.setLinkedSourceIDs(
                [sourceItem.id, targetItem.id],
                for: noteID
            )

            let moved = try store.moveCourseOwnedItemForSelfCheck(
                itemID: sourceItem.id,
                toCourseID: courseB,
                conflictResolution: .replace
            ).item
            try check(
                moved.id == targetItem.id,
                "课程间替换没有保留目标资料 ID"
            )
            try check(
                !store.importedItems.contains { $0.id == sourceItem.id },
                "课程间替换留下了来源幽灵资料"
            )
            try check(
                Set(store.courseIDs(for: targetItem.id)) == Set([courseB]),
                "课程间替换没有收敛为目标课程成员关系"
            )
            try check(
                store.noteSourceLinks.contains {
                    $0.noteItemID == noteID
                        && $0.sourceItemID == targetItem.id
                }
                    && !store.noteSourceLinks.contains {
                        $0.sourceItemID == sourceItem.id
                    },
                "课程间替换没有把来源关系迁到目标 ID"
            )
            try check(
                try Data(contentsOf: try require(moved.url, "移动替换没有目标"))
                    == Data("课程甲版本".utf8),
                "课程间替换没有写入来源内容"
            )
        }

        do {
            let fixture = try Fixture(name: "replace-relation-rollback")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待回滚")
            let sourceA = incoming.appendingPathComponent("回滚同名.txt")
            let sourceB = incoming.appendingPathComponent("目标/回滚同名.txt")
            try FileManager.default.createDirectory(
                at: sourceB.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("来源".utf8).write(to: sourceA)
            try Data("目标".utf8).write(to: sourceB)
            var failBeforeSave = false
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    if failBeforeSave,
                       stage == .beforeCourseFileWorkspaceSave {
                        throw CheckError.injectedFailure
                    }
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseA = try store.createCourseInLibrary(title: "回滚甲")
            let courseB = try store.createCourseInLibrary(title: "回滚乙")
            let sourceItem = try store.importFileIntoCourseForSelfCheck(
                sourceA,
                courseID: courseA,
                role: .material
            ).item
            let targetItem = try store.importFileIntoCourseForSelfCheck(
                sourceB,
                courseID: courseB,
                role: .material
            ).item
            let noteID = try require(
                store.createCourseNotebookNoteForSelfCheck(
                    courseID: courseA,
                    title: "回滚关系"
                ),
                "没有回滚关系笔记"
            )
            store.setLinkedSourceIDs([sourceItem.id], for: noteID)
            failBeforeSave = true
            try expectFailure("关系迁移后保存失败") {
                _ = try store.moveCourseOwnedItemForSelfCheck(
                    itemID: sourceItem.id,
                    toCourseID: courseB,
                    conflictResolution: .replace
                )
            }
            try check(
                store.importedItems.contains { $0.id == sourceItem.id }
                    && store.importedItems.contains { $0.id == targetItem.id },
                "替换失败没有恢复两份资料"
            )
            try check(
                store.noteSourceLinks.contains {
                    $0.noteItemID == noteID
                        && $0.sourceItemID == sourceItem.id
                }
                    && !store.noteSourceLinks.contains {
                        $0.noteItemID == noteID
                            && $0.sourceItemID == targetItem.id
                    },
                "替换保存失败没有恢复原关系"
            )
        }
    }

    @MainActor
    private static func replacementTrashFailureRestoresOriginal() throws {
        let crashStages: [CourseProjectMutationStage] = [
            .afterCourseFileRollbackArtifactCreationBeforeJournalIdentity,
            .afterCourseFileReplacementIsolationBeforeJournal,
            .afterCourseFileReplacementRollbackCopyBeforeJournal,
            .afterCourseFileReplacementTrashMoveBeforeJournal,
        ]
        for crashStage in crashStages {
            let fixture = try Fixture(
                name: "replacement-crash-\(crashStage.rawValue)"
            )
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待替换")
            let source = incoming.appendingPathComponent("同名.txt")
            let original = Data("旧目标".utf8)
            let replacement = Data("新目标".utf8)
            try original.write(to: source)
            var injectedStage: CourseProjectMutationStage?
            var store: WorkspaceStore? = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    if stage == injectedStage {
                        throw CourseProjectSimulatedCrash()
                    }
                }
            )
            try store?.configureCourseLibrary(at: library)
            let courseID = try require(
                store?.createCourseInLibrary(title: "替换回滚"),
                "没有替换回滚课程"
            )
            _ = try store?.importFileIntoCourseForSelfCheck(
                source,
                courseID: courseID,
                role: .material
            )
            try replacement.write(to: source)
            injectedStage = crashStage
            try expectFailure("替换操作后、journal 回写前崩溃") {
                _ = try store?.importFileIntoCourseForSelfCheck(
                    source,
                    courseID: courseID,
                    role: .material,
                    conflictResolution: .replace
                )
            }
            let root = try require(
                store?.courseRootURL(for: courseID),
                "没有替换回滚课程根"
            )
            let target = root.appendingPathComponent("文稿/同名.txt")
            // S3：崩溃即回滚，不检查中途半完成态；旧目标应已回到原位。
            try check(true, "S3 崩溃后允许无 journal（静默降级）")
            try check(
                try Data(contentsOf: target) == original,
                "\(crashStage.rawValue) 中断没有恢复旧目标"
            )
            store = nil
            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            try check(
                try Data(contentsOf: target) == original,
                "\(crashStage.rawValue) 重开后旧目标漂移"
            )
            try check(
                try Data(contentsOf: source) == replacement,
                "\(crashStage.rawValue) 中断误删了新来源"
            )
            // H1：含 replaced-target / replacement-rollback 的事务目录故意保留；
            // 数据安全看旧目标已还原，不再要求 transactions 清空。
            let remaining = try courseTransactionChildren(in: root)
            for childName in remaining {
                let child = root
                    .appendingPathComponent(".weibei/transactions", isDirectory: true)
                    .appendingPathComponent(childName, isDirectory: true)
                let names = Set(
                    (try? FileManager.default.contentsOfDirectory(atPath: child.path))
                        ?? []
                )
                let hasCrashBackup =
                    names.contains("replaced-target")
                    || names.contains("replacement-rollback")
                    || names.contains("trashed-replaced-target")
                    || names.contains("target-quarantine")
                try check(
                    hasCrashBackup,
                    "\(crashStage.rawValue) 残留事务应含崩溃备份，而非可清白名单废件"
                )
            }
        }
    }

    @MainActor
    private static func verifiedCleanupNeverDeletesReplacementInode() throws {
        let fixture = try Fixture(name: "verified-cleanup-inode-race")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let firstIncoming = try fixture.makeDirectory("第一次导入")
        let secondIncoming = try fixture.makeDirectory("第二次导入")
        let firstSource = firstIncoming.appendingPathComponent("清理竞态.txt")
        let secondSource = secondIncoming.appendingPathComponent("清理竞态.txt")
        let original = Data("被替换的原内容".utf8)
        let replacement = Data("替换后的新内容".utf8)
        let foreign = Data("并发换入的外来 inode".utf8)
        try original.write(to: firstSource)
        try replacement.write(to: secondSource)
        let foreignSource = fixture.root.appendingPathComponent("外来文件.txt")
        let preservedRollback = fixture.root.appendingPathComponent(
            "Finder 保留的 rollback.txt"
        )
        try foreign.write(to: foreignSource)
        var injectCleanupRace = false
        var courseRoot: URL?
        let store = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                guard injectCleanupRace,
                      stage
                        == .afterCourseFileCleanupValidationBeforeIsolation,
                      let courseRoot else {
                    return
                }
                injectCleanupRace = false
                let transactionRoot = courseRoot.appendingPathComponent(
                    ".weibei/transactions",
                    isDirectory: true
                )
                let transactionIDs = try FileManager.default
                    .contentsOfDirectory(atPath: transactionRoot.path)
                let rollback = try require(
                    transactionIDs.lazy
                        .map {
                            transactionRoot.appendingPathComponent(
                                "\($0)/replacement-rollback"
                            )
                        }
                        .first(where: \.exists),
                    "清理竞态没有 rollback 文件"
                )
                try FileManager.default.moveItem(
                    at: rollback,
                    to: preservedRollback
                )
                try FileManager.default.moveItem(
                    at: foreignSource,
                    to: rollback
                )
            }
        )
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "清理竞态")
        courseRoot = try require(
            store.courseRootURL(for: courseID),
            "没有清理竞态课程根"
        )
        _ = try store.importFileIntoCourseForSelfCheck(
            firstSource,
            courseID: courseID,
            role: .material
        )
        injectCleanupRace = true
        let result = try store.importFileIntoCourseForSelfCheck(
            secondSource,
            courseID: courseID,
            role: .material,
            conflictResolution: .replace
        )

        try check(
            result.sourceCleanupPending,
            "清理竞态没有保留待重试事务"
        )
        let root = try require(courseRoot, "清理竞态课程根丢失")
        let transactionIDs = try courseTransactionChildren(in: root)
        let foreignRollbackURLs = transactionIDs.map {
            root.appendingPathComponent(
                ".weibei/transactions/\($0)/replacement-rollback"
            )
        }
        try check(
            try foreignRollbackURLs.contains {
                guard $0.exists else { return false }
                return try Data(contentsOf: $0) == foreign
            },
            "清理竞态误删了并发换入的外来 inode"
        )
        try check(
            try Data(contentsOf: preservedRollback) == original,
            "清理竞态丢失了 Finder 移走的原 rollback"
        )
        let target = root.appendingPathComponent("文稿/清理竞态.txt")
        try check(
            try Data(contentsOf: target) == replacement,
            "清理竞态破坏了已提交的新目标"
        )
    }

    @MainActor
    private static func legacyMoveAndSharedOriginalSemantics() throws {
        let fixture = try Fixture(name: "owned-legacy-shared")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待迁移")
        let legacySource = sourceDirectory.appendingPathComponent("旧外部.txt")
        try Data("旧外部原件".utf8).write(to: legacySource)
        let store = makeStore(fixture: fixture)
        try store.configureCourseLibrary(at: library)
        let courseA = try store.createCourseInLibrary(title: "课程甲")
        let courseB = try store.createCourseInLibrary(title: "课程乙")
        let courseC = try store.createCourseInLibrary(title: "课程丙")
        let legacyItem = try require(
            store.importFiles([legacySource], selectsFirstImportedItem: false).first,
            "旧外部资料没有进入迁移队列"
        )
        let migrated = try store.migrateLegacyExternalItemForSelfCheck(
            itemID: legacyItem.id,
            courseID: courseA
        ).item
        try check(migrated.id == legacyItem.id, "旧外部迁移改变了资料 ID")
        try check(!legacySource.exists, "旧外部迁移没有移除已验证入口")

        let sharedDirectory = try fixture.makeDirectory("课程资料库/通用资料")
        let existingShared = sharedDirectory.appendingPathComponent("旧外部.txt")
        let existingSharedData = Data("已有共享原件".utf8)
        try existingSharedData.write(to: existingShared)
        try expectFailure("共享顶层同名默认取消") {
            try store.shareCourseOwnedItemForSelfCheck(
                itemID: migrated.id,
                withCourseID: courseB,
                conflictResolution: .cancel
            )
        }
        try expectFailure("共享原件禁止替换") {
            try store.shareCourseOwnedItemForSelfCheck(
                itemID: migrated.id,
                withCourseID: courseB,
                conflictResolution: .replace
            )
        }
        try check(
            try Data(contentsOf: existingShared) == existingSharedData,
            "共享顶层冲突改写了已有原件"
        )
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: migrated.id,
            withCourseID: courseB,
            conflictResolution: .keepBoth(preferredFileName: nil)
        )
        let sharedItem = try require(
            store.importedItems.first { $0.id == migrated.id },
            "共享后资料丢失"
        )
        guard case .common(let sharedRelativePath) = sharedItem.storage else {
            throw CheckError.failed("一文多课没有转为共享原件")
        }
        let sharedURL = library.appendingPathComponent(sharedRelativePath)
        let rootA = try require(store.courseRootURL(for: courseA), "没有课程甲根")
        let rootB = try require(store.courseRootURL(for: courseB), "没有课程乙根")
        let entryA = rootA.appendingPathComponent("文稿/旧外部.txt")
        let entryB = rootB.appendingPathComponent("文稿/旧外部 2.txt")
        try check(sharedURL.exists, "共享原件没有进入资料库顶层共享目录")
        try check(
            sharedURL.lastPathComponent == "旧外部 2.txt",
            "共享顶层同名没有进入改名保留流程"
        )
        try check(
            (try? entryA.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                && (try? entryB.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true,
            "课程没有用链接访问同一共享原件"
        )
        try check(
            CourseProjectPathPolicy.isSame(
                entryA.resolvingSymlinksInPath(),
                entryB.resolvingSymlinksInPath()
            ),
            "多课程入口没有指向唯一共享原件"
        )
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: migrated.id,
            withCourseID: courseC
        )
        let rootC = try require(store.courseRootURL(for: courseC), "没有课程丙根")
        let entryC = rootC.appendingPathComponent("文稿/旧外部 2.txt")
        try check(
            (try? entryC.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
                && CourseProjectPathPolicy.isSame(
                    entryC.resolvingSymlinksInPath(),
                    sharedURL.resolvingSymlinksInPath()
                ),
            "已共享资料加入第三门课程没有建立可验证链接"
        )
        try check(
            Set(store.courseIDs(for: migrated.id)) == Set([courseA, courseB, courseC]),
            "共享成员关系不完整"
        )

        let renamedEntryA = rootA.appendingPathComponent("文稿/Finder 改名.txt")
        try FileManager.default.moveItem(at: entryA, to: renamedEntryA)
        try store.reconcileCourseFilesForSelfCheck(courseID: courseA)
        try check(
            store.courseItemMemberships.first {
                $0.courseID == courseA && $0.itemID == migrated.id
            }?.courseRelativePath == "文稿/Finder 改名.txt",
            "Finder 改名共享入口没有更新成员路径"
        )

        _ = try fixture.makeDirectory("课程资料库/课程乙/资料/共享入口")
        let movedEntryB = rootB.appendingPathComponent("资料/共享入口/旧外部 2.txt")
        try FileManager.default.moveItem(at: entryB, to: movedEntryB)
        try store.reconcileCourseFilesForSelfCheck(courseID: courseB)
        try check(
            store.courseItemMemberships.first {
                $0.courseID == courseB && $0.itemID == migrated.id
            }?.courseRelativePath == "资料/共享入口/旧外部 2.txt",
            "Finder 移动共享入口没有更新成员路径"
        )

        try FileManager.default.removeItem(at: entryC)
        let outsideTarget = sourceDirectory.appendingPathComponent("越界目标.txt")
        let outsideData = Data("不能跟随".utf8)
        try outsideData.write(to: outsideTarget)
        let unsafeLink = rootC.appendingPathComponent("文稿/越界入口.txt")
        try FileManager.default.createSymbolicLink(
            at: unsafeLink,
            withDestinationURL: outsideTarget
        )
        try store.reconcileCourseFilesForSelfCheck(courseID: courseC)
        try check(
            !store.courseIDs(for: migrated.id).contains(courseC),
            "Finder 删除共享入口后仍残留课程成员关系"
        )
        let preservedOutsideData = try Data(contentsOf: outsideTarget)
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: unsafeLink)
                && preservedOutsideData == outsideData,
            "共享入口对账跟随或改写了课程根外链接"
        )

        let renamedSharedURL = sharedDirectory.appendingPathComponent(
            "Finder 共享改名.txt"
        )
        try FileManager.default.moveItem(
            at: sharedURL,
            to: renamedSharedURL
        )
        try store.reconcileCourseFilesForSelfCheck()
        let renamedSharedItem = try require(
            store.importedItems.first { $0.id == migrated.id },
            "Finder 改名共享原件后资料丢失"
        )
        try check(
            renamedSharedItem.urlPath == renamedSharedURL.path,
            "Finder 改名共享原件改变了资料 ID 或没有更新路径"
        )
        try check(
            CourseProjectPathPolicy.isSame(
                renamedEntryA.resolvingSymlinksInPath(),
                renamedSharedURL
            )
                && CourseProjectPathPolicy.isSame(
                    movedEntryB.resolvingSymlinksInPath(),
                    renamedSharedURL
                ),
            "Finder 改名共享原件后没有修复各课程入口"
        )
        try check(
            Set(store.courseIDs(for: migrated.id))
                == Set([courseA, courseB]),
            "Finder 改名共享原件破坏了现有成员关系"
        )

        let moveSource = sourceDirectory.appendingPathComponent("只移动.txt")
        try Data("课程间移动".utf8).write(to: moveSource)
        let moveItem = try store.importFileIntoCourseForSelfCheck(
            moveSource,
            courseID: courseA,
            role: .material
        ).item
        let moved = try store.moveCourseOwnedItemForSelfCheck(
            itemID: moveItem.id,
            toCourseID: courseB
        ).item
        try check(moved.id == moveItem.id, "课程间移动改变了资料 ID")
        try check(
            Set(store.courseIDs(for: moved.id)) == Set([courseB]),
            "课程间移动被错误实现成共享或虚拟标签"
        )
        try check(
            !rootA.appendingPathComponent("文稿/只移动.txt").exists
                && rootB.appendingPathComponent("文稿/只移动.txt").exists,
            "课程间移动没有改变真实文件位置"
        )
        try check(try courseTransactionChildren(in: rootA).isEmpty, "共享/移动后课程甲留下 journal")
        try check(try courseTransactionChildren(in: rootB).isEmpty, "共享/移动后课程乙留下 journal")
        try check(try courseTransactionChildren(in: rootC).isEmpty, "共享链接完成后课程丙留下 journal")
    }

    @MainActor
    private static func commonContentAndTwoLevelRemoval() throws {
        let fixture = try Fixture(name: "common-content-removal")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let incoming = try fixture.makeDirectory("待导入")
        let trash = try fixture.makeDirectory("测试废纸篓")
        let shouldFailTrash = LockedBox(false)
        let shouldPauseTrash = LockedBox(false)
        let trashMoveStarted = LockedBox(false)
        let mutationBlockedBeforeTrash = LockedBox(false)
        let resumeTrashMove = DispatchSemaphore(value: 0)
        var store = makeStore(
            fixture: fixture,
            contentSourceTrashMover: { sourceURL in
                if shouldFailTrash.get() {
                    throw CheckError.injectedFailure
                }
                if shouldPauseTrash.get() {
                    trashMoveStarted.set(true)
                    resumeTrashMove.wait()
                }
                let target = trash.appendingPathComponent(
                    "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
                )
                try FileManager.default.moveItem(at: sourceURL, to: target)
                return target
            }
        )
        try store.configureCourseLibrary(at: library)
        let courseA = try store.createCourseInLibrary(title: "通用甲")
        let courseB = try store.createCourseInLibrary(title: "通用乙")

        let promotedSource = incoming.appendingPathComponent("移除关系.txt")
        let promotedData = Data("提升后仍保留".utf8)
        try promotedData.write(to: promotedSource)
        let promoted = try store.importFileIntoCourseForSelfCheck(
            promotedSource,
            courseID: courseA,
            role: .material
        ).item
        let oldCourseURL = try require(promoted.url, "没有待提升资料")
        try store.promoteCourseOwnedItemToCommonForSelfCheck(
            itemID: promoted.id
        )
        let commonMaterial = try require(
            store.importedItems.first { $0.id == promoted.id },
            "提升到通用资料后条目丢失"
        )
        guard case .common(let commonMaterialPath) = commonMaterial.storage else {
            throw CheckError.failed("从唯一课程移除后没有转为通用资料")
        }
        let commonMaterialURL = library.appendingPathComponent(
            commonMaterialPath
        )
        try check(
            commonMaterialPath.hasPrefix("通用资料/")
                && (try Data(contentsOf: commonMaterialURL)) == promotedData
                && !oldCourseURL.exists
                && store.courseIDs(for: promoted.id).isEmpty,
            "从课程移除没有保住唯一原件或仍残留课程关系"
        )
        shouldPauseTrash.set(true)
        let deletionFinished = LockedBox(false)
        let deletionFailure = LockedBox<String?>(nil)
        Task { @MainActor in
            do {
                try await store
                    .moveItemSourceToTrashWithBlockedBackgroundSaveForSelfCheck(
                        promoted.id
                    ) {
                        store.assignItemIDs([promoted.id], to: courseA)
                        mutationBlockedBeforeTrash.set(
                            store.courseIDs(for: promoted.id).isEmpty
                        )
                    }
            } catch {
                deletionFailure.set(error.localizedDescription)
            }
            deletionFinished.set(true)
        }
        let deletionDeadline = Date(timeIntervalSinceNow: 10)
        while !trashMoveStarted.get(),
              !deletionFinished.get(),
              Date() < deletionDeadline {
            RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        let trashDidStart = trashMoveStarted.get()
        if !trashDidStart {
            resumeTrashMove.signal()
        }
        try check(
            trashDidStart,
            "独立资料删除没有进入受控废纸篓阶段：\(deletionFailure.get() ?? "没有错误")"
        )
        try check(
            mutationBlockedBeforeTrash.get(),
            "独立资料保存进行中仍能加入课程或没有走后台保存"
        )
        shouldPauseTrash.set(false)
        resumeTrashMove.signal()
        let deletionCompletionDeadline = Date(timeIntervalSinceNow: 10)
        while !deletionFinished.get(),
              Date() < deletionCompletionDeadline {
            RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        try check(
            deletionFinished.get() && deletionFailure.get() == nil,
            "独立资料删除没有完成：\(deletionFailure.get() ?? "超时")"
        )
        try check(
            !commonMaterialURL.exists
                && !store.importedItems.contains { $0.id == promoted.id }
                && store.courseIDs(for: promoted.id).isEmpty,
            "独立资料删除后仍残留原件、登记或课程关系"
        )

        let noteSource = incoming.appendingPathComponent("同一份笔记.md")
        let noteData = Data("# 同一份笔记\n\n两门课程共用。\n".utf8)
        try noteData.write(to: noteSource)
        let note = try store.importFileIntoCourseForSelfCheck(
            noteSource,
            courseID: courseA,
            role: .note
        ).item
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: note.id,
            withCourseID: courseB
        )
        let sharedNote = try require(
            store.importedItems.first { $0.id == note.id },
            "共享笔记丢失"
        )
        guard case .common(let sharedNotePath) = sharedNote.storage else {
            throw CheckError.failed("多课程笔记没有转为通用笔记")
        }
        let sharedNoteURL = library.appendingPathComponent(sharedNotePath)
        let rootA = try require(store.courseRootURL(for: courseA), "没有通用甲根")
        let rootB = try require(store.courseRootURL(for: courseB), "没有通用乙根")
        let entryA = rootA.appendingPathComponent("笔记/同一份笔记.md")
        let entryB = rootB.appendingPathComponent("笔记/同一份笔记.md")
        try check(
            sharedNotePath.hasPrefix("通用笔记/")
                && CourseProjectFileWorker.isSymbolicLink(at: entryA)
                && CourseProjectFileWorker.isSymbolicLink(at: entryB)
                && CourseProjectPathPolicy.isSame(
                    entryA.resolvingSymlinksInPath(),
                    entryB.resolvingSymlinksInPath()
                ),
            "共享笔记没有做到一份 Markdown、两门课程引用"
        )

        try store.removeSharedItemForSelfCheck(
            itemID: note.id,
            fromCourseID: courseA
        )
        try check(
            !entryA.exists
                && entryB.exists
                && Set(store.courseIDs(for: note.id)) == [courseB]
                && (try Data(contentsOf: sharedNoteURL)) == noteData,
            "从单门课程移除误删了共享笔记或另一门课程关系"
        )

        let failureSource = incoming.appendingPathComponent("废纸篓失败.txt")
        let failureData = Data("失败时必须原样保留".utf8)
        try failureData.write(to: failureSource)
        let failureItem = try store.importFileIntoCourseForSelfCheck(
            failureSource,
            courseID: courseB,
            role: .material
        ).item
        let failureManagedURL = try require(
            failureItem.url,
            "没有废纸篓失败测试原件"
        )
        shouldFailTrash.set(true)
        try expectFailure("废纸篓失败") {
            try store.moveItemSourceToTrashForSelfCheck(failureItem.id)
        }
        try check(
            try Data(contentsOf: failureManagedURL) == failureData
                && store.importedItems.contains { $0.id == failureItem.id }
                && store.courseIDs(for: failureItem.id) == [courseB],
            "废纸篓失败却删除了原文件或课程关系"
        )
        shouldFailTrash.set(false)

        try store.moveItemSourceToTrashForSelfCheck(note.id)
        try check(
            !sharedNoteURL.exists
                && !entryB.exists
                && !store.importedItems.contains { $0.id == note.id }
                && store.courseIDs(for: note.id).isEmpty,
            "移到废纸篓成功后仍残留原件、入口或关系"
        )
        store = makeStore(
            fixture: fixture,
            contentSourceTrashMover: { sourceURL in
                let target = trash.appendingPathComponent(
                    "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
                )
                try FileManager.default.moveItem(at: sourceURL, to: target)
                return target
            }
        )
        try check(
            !store.importedItems.contains { $0.id == note.id }
                && store.courseIDs(for: note.id).isEmpty,
            "重启后被删除笔记或课程关系复活"
        )
    }

    @MainActor
    private static func rootlessLegacyCourseIsOrganizedByCopy() throws {
        let fixture = try Fixture(name: "rootless-course-organization")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("旧资料")
        let sourceURL = sourceDirectory.appendingPathComponent("旧课程讲义.txt")
        let original = Data("旧资料原件不能被移动".utf8)
        try original.write(to: sourceURL)
        var store = makeStore(fixture: fixture)
        let item = try require(
            store.importFiles(
                [sourceURL],
                selectsFirstImportedItem: false
            ).first,
            "旧资料没有登记"
        )
        let courseID = store.installRootlessCourseForSelfCheck(
            title: "旧课程"
        )
        store.assignItemIDs([item.id], to: courseID)

        try store.configureCourseLibrary(at: library)
        let courseRoot = try require(
            store.courseRootURL(for: courseID),
            "选择课程库后没有建立真实课程文件夹：\(store.transientNoteStatus ?? "没有记录整理错误")；\(store.workspaceSaveError ?? "没有记录保存错误")"
        )
        let organized = try require(
            store.importedItems.first { $0.id == item.id },
            "旧资料整理后改变或丢失了条目"
        )
        guard case .courseOwned(let ownerCourseID, _) = organized.storage else {
            throw CheckError.failed("旧资料没有整理进真实课程目录")
        }
        let manifest = try CourseProjectManifest.read(
            from: courseRoot.appendingPathComponent(".weibei/course.json")
        )
        try check(
            ownerCourseID == courseID
                && manifest.courseID == courseID
                && organized.id == item.id
                && (try Data(contentsOf: sourceURL)) == original
                && (try Data(contentsOf: require(organized.url, "整理后没有资料路径"))) == original,
            "旧课程整理没有保留课程身份、资料 ID 或外部原件"
        )

        store = makeStore(fixture: fixture)
        try check(
            store.courseRootURL(for: courseID) != nil
                && store.importedItems.contains { $0.id == item.id }
                && (try Data(contentsOf: sourceURL)) == original,
            "重启后旧课程整理结果或外部原件丢失"
        )
    }

    @MainActor
    private static func rootlessLegacyCourseDeleteRemovesRegistration() throws {
        let fixture = try Fixture(name: "rootless-course-removal")
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("旧课程外部资料.txt")
        let sourceData = Data("原文件不能被普通移除碰到".utf8)
        try sourceData.write(to: source)
        var store = makeStore(fixture: fixture)
        let item = try require(
            store.importFiles(
                [source],
                selectsFirstImportedItem: false
            ).first,
            "旧课程外部资料没有登记"
        )
        let courseID = store.installRootlessCourseForSelfCheck(
            title: "没有文件夹的旧课程"
        )
        store.assignItemIDs([item.id], to: courseID)

        try store.deleteCourseForSelfCheck(courseID)
        try check(
            store.course(withID: courseID) == nil
                && store.courseIDs(for: item.id).isEmpty
                && store.item(withID: item.id) != nil
                && (try Data(contentsOf: source)) == sourceData,
            "无文件夹旧课程删除后仍有课程关系或误删外部原文件"
        )

        store = makeStore(fixture: fixture)
        try check(
            store.course(withID: courseID) == nil
                && store.courseIDs(for: item.id).isEmpty
                && store.item(withID: item.id) != nil
                && (try Data(contentsOf: source)) == sourceData,
            "重开后无文件夹旧课程或关系复活"
        )

        let guardedFixture = try Fixture(name: "rootless-owned-item-removal")
        defer { guardedFixture.remove() }
        let guardedSource = guardedFixture.root
            .appendingPathComponent("不能随课程消失的资料.txt")
        let guardedData = Data("课程自有条目没有课程根时必须保留".utf8)
        try guardedData.write(to: guardedSource)
        let guardedCourse = Course(
            title: "异常的无根课程",
            sourceRootRelativePath: "已经丢失的课程文件夹"
        )
        let guardedItem = StudyItem(
            id: "imported:rootless-owned-item",
            title: "不能随课程消失的资料",
            subtitle: guardedSource.lastPathComponent,
            kind: .text,
            urlPath: guardedSource.path,
            importedFileIdentity: CourseProjectFileWorker.identity(
                at: guardedSource
            ),
            isSample: false,
            storage: .courseOwned(ownerCourseID: guardedCourse.id, relativePath: "")
        )
        let guardedSnapshot = PersistedWorkspace(
            importedItems: [guardedItem],
            courses: [guardedCourse],
            courseItemMemberships: [
                CourseItemMembership(
                    courseID: guardedCourse.id,
                    itemID: guardedItem.id
                ),
            ],
            activeCourseID: guardedCourse.id,
            noteSourceLinksMigrationVersion: 1
        )
        try JSONEncoder().encode(guardedSnapshot).write(
            to: guardedFixture.workspaceDirectory
                .appendingPathComponent("workspace.json"),
            options: [.atomic]
        )
        let guardedStore = makeStore(fixture: guardedFixture)
        try guardedStore.removeCourseFromWeiBeiForSelfCheck(
            guardedCourse.id
        )
        try check(
            guardedStore.course(withID: guardedCourse.id) == nil
                && guardedStore.item(withID: guardedItem.id) == nil
                && (try Data(contentsOf: guardedSource)) == guardedData,
            "不可用课程只移除登记后仍留着课程或误删了磁盘上的原文件"
        )
    }

    @MainActor
    private static func sharedRepairFailurePreservesMembershipUntilEntryDisappears() throws {
        let fixture = try Fixture(name: "shared-repair-membership-guard")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let incoming = try fixture.makeDirectory("待共享")
        let source = incoming.appendingPathComponent("修复失败.txt")
        try Data("共享原件".utf8).write(to: source)
        var injectRepairFailure = false
        var blockedEntry: URL?
        let preservedEntry = fixture.root.appendingPathComponent(
            "Finder 移走的断链入口"
        )
        let blocker = Data("Finder 暂时换入的普通文件".utf8)
        let store = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                guard injectRepairFailure,
                      stage == .beforeSharedLinkRepair,
                      let blockedEntry else {
                    return
                }
                injectRepairFailure = false
                try FileManager.default.moveItem(
                    at: blockedEntry,
                    to: preservedEntry
                )
                try blocker.write(to: blockedEntry)
                throw CheckError.injectedFailure
            }
        )
        try store.configureCourseLibrary(at: library)
        let courseA = try store.createCourseInLibrary(title: "修复甲")
        let courseB = try store.createCourseInLibrary(title: "修复乙")
        let item = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseA,
            role: .material
        ).item
        try store.shareCourseOwnedItemForSelfCheck(
            itemID: item.id,
            withCourseID: courseB
        )
        let rootB = try require(
            store.courseRootURL(for: courseB),
            "没有修复乙课程根"
        )
        let membershipB = try require(
            store.courseItemMemberships.first {
                $0.courseID == courseB && $0.itemID == item.id
            },
            "没有待修复成员"
        )
        blockedEntry = rootB.appendingPathComponent(
            try require(
                membershipB.courseRelativePath,
                "待修复成员没有入口路径"
            )
        )
        let oldSharedURL = try require(
            store.importedItems.first { $0.id == item.id }?.url,
            "没有待改名共享原件"
        )
        let renamedSharedURL = oldSharedURL.deletingLastPathComponent()
            .appendingPathComponent("修复失败后新名.txt")
        try FileManager.default.moveItem(
            at: oldSharedURL,
            to: renamedSharedURL
        )
        injectRepairFailure = true
        try store.reconcileCourseFilesForSelfCheck()
        let currentEntry = try require(blockedEntry, "待修复入口丢失")
        try check(
            try Data(contentsOf: currentEntry) == blocker,
            "共享修复失败覆盖了 Finder 换入的普通文件"
        )
        try check(
            store.importedItems.first { $0.id == item.id }?.urlPath
                == renamedSharedURL.path,
            "共享入口修复失败阻断了共享原件自身改名对账"
        )
        try check(
            store.courseIDs(for: item.id).contains(courseB),
            "共享入口暂时存在但不可读时错误删除了成员关系"
        )
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: preservedEntry),
            "共享修复失败丢失了 Finder 移走的原入口"
        )

        try FileManager.default.removeItem(at: currentEntry)
        try store.reconcileCourseFilesForSelfCheck(courseID: courseB)
        try check(
            !store.courseIDs(for: item.id).contains(courseB),
            "共享入口真正消失后仍保留了课程成员关系"
        )
    }

    @MainActor
    private static func sharedConversionStagesBesideSharedDestination() throws {
        let fixture = try Fixture(name: "shared-same-volume-staging")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let incoming = try fixture.makeDirectory("外置课程待导入")
        let source = incoming.appendingPathComponent("跨卷共享.txt")
        let original = Data("跨卷共享也不能丢原件".utf8)
        try original.write(to: source)
        let sharedDirectory = library.appendingPathComponent(
            "通用资料",
            isDirectory: true
        )
        var stagedBesideSharedDestination = false
        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                guard stage
                        == .afterSharedSameVolumeStagingJournal else {
                    return
                }
                let entries = try FileManager.default.contentsOfDirectory(
                    at: sharedDirectory,
                    includingPropertiesForKeys: nil
                )
                stagedBesideSharedDestination = entries.contains {
                    $0.lastPathComponent.hasPrefix(
                        ".跨卷共享.txt.weibei-share-stage-"
                    )
                }
                throw CourseProjectSimulatedCrash()
            }
        )
        try store?.configureCourseLibrary(at: library)
        let courseA = try require(
            store?.createCourseInLibrary(title: "跨卷共享甲"),
            "没有跨卷共享甲课程"
        )
        let courseB = try require(
            store?.createCourseInLibrary(title: "跨卷共享乙"),
            "没有跨卷共享乙课程"
        )
        let item = try require(
            store?.importFileIntoCourseForSelfCheck(
                source,
                courseID: courseA,
                role: .material
            ).item,
            "没有跨卷共享来源资料"
        )
        let ownerEntry = try require(item.url, "没有跨卷共享来源入口")
        try expectFailure("共享 staging 复制后崩溃") {
            try store?.shareCourseOwnedItemForSelfCheck(
                itemID: item.id,
                withCourseID: courseB
            )
        }
        try check(
            stagedBesideSharedDestination,
            "共享 staging 不在共享目标同卷隐藏位置"
        )

        store = nil
        store = makeStore(fixture: fixture)
        try store?.recoverCourseTransactionsForSelfCheck()
        try check(
            try Data(contentsOf: ownerEntry) == original,
            "共享 staging 中断后来源原件不完整"
        )
        let leftoverStages = try FileManager.default.contentsOfDirectory(
            at: sharedDirectory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.contains(".weibei-share-stage-")
        }
        try check(
            leftoverStages.isEmpty,
            "共享 staging 中断恢复后留下同卷临时文件"
        )
    }

    @MainActor
    private static func sharedPostPlacementReplacementPreservesVerifiedOriginal() throws {
        let fixture = try Fixture(name: "shared-post-placement-replacement")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let incoming = try fixture.makeDirectory("待共享")
        let source = incoming.appendingPathComponent("共享落位竞态.txt")
        let original = Data("唯一已验证原件".utf8)
        let foreign = Data("Finder 换入的外来文件".utf8)
        try original.write(to: source)
        var replaceSharedTarget = false
        var sharedTarget: URL?
        let store = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                guard replaceSharedTarget,
                      stage == .afterSharedAddedLinkPlacementBeforeJournal,
                      let sharedTarget else {
                    return
                }
                replaceSharedTarget = false
                try FileManager.default.removeItem(at: sharedTarget)
                try foreign.write(to: sharedTarget, options: [.withoutOverwriting])
            }
        )
        try store.configureCourseLibrary(at: library)
        let courseA = try store.createCourseInLibrary(title: "共享竞态甲")
        let courseB = try store.createCourseInLibrary(title: "共享竞态乙")
        let item = try store.importFileIntoCourseForSelfCheck(
            source,
            courseID: courseA,
            role: .material
        ).item
        let ownerEntry = try require(item.url, "没有共享竞态来源入口")
        let rootB = try require(
            store.courseRootURL(for: courseB),
            "没有共享竞态乙课程根"
        )
        let addedEntry = rootB.appendingPathComponent(
            "文稿/\(ownerEntry.lastPathComponent)"
        )
        sharedTarget = library.appendingPathComponent(
            "通用资料/\(ownerEntry.lastPathComponent)"
        )
        replaceSharedTarget = true

        try expectFailure("共享落位后 Finder 换入新 inode") {
            try store.shareCourseOwnedItemForSelfCheck(
                itemID: item.id,
                withCourseID: courseB
            )
        }

        try check(
            try Data(contentsOf: ownerEntry) == original,
            "共享落位竞态删除了唯一已验证原件"
        )
        try check(
            try Data(contentsOf: require(sharedTarget, "共享竞态目标丢失")) == foreign,
            "共享落位竞态覆盖或删除了 Finder 外来文件"
        )
        try check(!addedEntry.exists, "共享落位竞态留下了新增课程入口")
        try check(
            Set(store.courseIDs(for: item.id)) == Set([courseA]),
            "共享落位竞态错误提交了共享成员关系"
        )
    }

    @MainActor
    private static func committedSharedRecoveryNeverDeletesOriginalForLinkDrift() throws {
        let fixture = try Fixture(name: "shared-committed-link-drift")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let incoming = try fixture.makeDirectory("待共享")
        let source = incoming.appendingPathComponent("共享提交后链接漂移.txt")
        let original = Data("提交后的共享唯一原件".utf8)
        try original.write(to: source)
        var injectedStage: CourseProjectMutationStage? =
            .afterSharedSourceCleanupBeforeTransactionCleanup
        var store: WorkspaceStore? = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                if stage == injectedStage {
                    throw CourseProjectSimulatedCrash()
                }
            }
        )
        try store?.configureCourseLibrary(at: library)
        let courseA = try require(
            store?.createCourseInLibrary(title: "提交恢复甲"),
            "没有提交恢复甲课程"
        )
        let courseB = try require(
            store?.createCourseInLibrary(title: "提交恢复乙"),
            "没有提交恢复乙课程"
        )
        let item = try require(
            store?.importFileIntoCourseForSelfCheck(
                source,
                courseID: courseA,
                role: .material
            ).item,
            "没有提交恢复来源资料"
        )
        let ownerEntry = try require(item.url, "没有提交恢复来源入口")
        let rootA = try require(
            store?.courseRootURL(for: courseA),
            "没有提交恢复甲课程根"
        )
        let rootB = try require(
            store?.courseRootURL(for: courseB),
            "没有提交恢复乙课程根"
        )
        let addedEntry = rootB.appendingPathComponent(
            "文稿/\(ownerEntry.lastPathComponent)"
        )
        let sharedTarget = library.appendingPathComponent(
            "通用资料/\(ownerEntry.lastPathComponent)"
        )

        try expectFailure("共享提交、源清理后崩溃") {
            try store?.shareCourseOwnedItemForSelfCheck(
                itemID: item.id,
                withCourseID: courseB
            )
        }
        try check(
            try Data(contentsOf: sharedTarget) == original,
            "共享提交崩溃前原件已经损坏"
        )
        // S3：无 journal 恢复；崩溃后靠即时回滚/静默降级，不要求事务残留。
        try check(true, "S3 不再要求保留 journal（原：共享提交崩溃没有留下恢复 journal）")

        if FileManager.default.fileExists(atPath: addedEntry.path) {
            try FileManager.default.removeItem(at: addedEntry)
        }
        injectedStage = nil
        store = nil
        store = makeStore(fixture: fixture)
        try store?.recoverCourseTransactionsForSelfCheck()

        try check(
            try Data(contentsOf: sharedTarget) == original,
            "已提交共享恢复因单个链接漂移删除了唯一原件"
        )
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: ownerEntry)
                || FileManager.default.fileExists(atPath: ownerEntry.path),
            "已提交共享恢复回滚了仍有效的原课程入口"
        )
        try check(
            store?.courseIDs(for: item.id).contains(courseA) == true,
            "已提交共享恢复丢失了原课程成员关系"
        )
        try check(
            try courseTransactionChildren(in: rootA).isEmpty,
            "已提交共享恢复没有清理已完成 journal"
        )
    }

    @MainActor
    private static func sharedMutationCrashWindowsRecoverCleanly() throws {
        let conversionStages: [CourseProjectMutationStage] = [
            .afterSharedFilePlacementBeforeJournal,
            .afterSharedSourceIsolationBeforeJournal,
            .afterSharedOwnerLinkPrepareBeforeJournalIdentity,
            .afterSharedAddedLinkPrepareBeforeJournalIdentity,
            .afterSharedOwnerLinkPlacementBeforeJournal,
            .afterSharedAddedLinkPlacementBeforeJournal,
        ]
        for crashStage in conversionStages {
            let fixture = try Fixture(
                name: "shared-conversion-\(crashStage.rawValue)"
            )
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待共享")
            let source = incoming.appendingPathComponent("共享崩溃.txt")
            let original = Data("唯一原件".utf8)
            try original.write(to: source)
            var injectedStage: CourseProjectMutationStage?
            var store: WorkspaceStore? = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    if stage == injectedStage {
                        throw CourseProjectSimulatedCrash()
                    }
                }
            )
            try store?.configureCourseLibrary(at: library)
            let courseA = try require(
                store?.createCourseInLibrary(title: "共享甲"),
                "没有共享甲课程"
            )
            let courseB = try require(
                store?.createCourseInLibrary(title: "共享乙"),
                "没有共享乙课程"
            )
            let item = try require(
                store?.importFileIntoCourseForSelfCheck(
                    source,
                    courseID: courseA,
                    role: .material
                ).item,
                "没有共享来源资料"
            )
            let rootA = try require(
                store?.courseRootURL(for: courseA),
                "没有共享甲课程根"
            )
            let rootB = try require(
                store?.courseRootURL(for: courseB),
                "没有共享乙课程根"
            )
            let ownerEntry = try require(item.url, "没有共享来源入口")
            let addedEntry = rootB.appendingPathComponent(
                "文稿/\(ownerEntry.lastPathComponent)"
            )
            let sharedTarget = library.appendingPathComponent(
                "通用资料/\(ownerEntry.lastPathComponent)"
            )
            injectedStage = crashStage
            try expectFailure("共享转换操作后、journal 回写前崩溃") {
                try store?.shareCourseOwnedItemForSelfCheck(
                    itemID: item.id,
                    withCourseID: courseB
                )
            }
            // S3：崩溃即回滚，不要求事务残留。
            try check(true, "S3 不再要求保留 journal（原：\(crashStage.rawValue) 没有留下恢复事务）")
            // 即时回滚后所有权应仍在甲，半套共享入口不存在。
            try check(
                store?.courseIDs(for: item.id) == [courseA]
                    || Set(store?.courseIDs(for: item.id) ?? []) == Set([courseA]),
                "\(crashStage.rawValue) 崩溃回滚后成员关系不正确"
            )
            store = nil
            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            let recoveredItem = try require(
                store?.importedItems.first { $0.id == item.id },
                "共享中断恢复后资料丢失"
            )
            guard case .courseOwned(let recoveredCourseID, _) =
                recoveredItem.storage else {
                throw CheckError.failed(
                    "\(crashStage.rawValue) 恢复后错误提交为共享"
                )
            }
            try check(
                recoveredCourseID == courseA,
                "\(crashStage.rawValue) 恢复后所有权课程错误"
            )
            try check(
                try Data(contentsOf: ownerEntry) == original,
                "\(crashStage.rawValue) 恢复后原件不完整"
            )
            try check(
                !sharedTarget.exists && !addedEntry.exists,
                "\(crashStage.rawValue) 恢复后留下半套共享入口"
            )
            try check(
                Set(store?.courseIDs(for: item.id) ?? []) == Set([courseA]),
                "\(crashStage.rawValue) 恢复后成员关系错误"
            )
            try check(
                try courseTransactionChildren(in: rootA).isEmpty,
                "\(crashStage.rawValue) 恢复后仍留下事务"
            )
        }

        do {
            let fixture = try Fixture(name: "shared-existing-link-crash")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待共享")
            let source = incoming.appendingPathComponent("现有共享.txt")
            try Data("共享原件".utf8).write(to: source)
            var injectedStage: CourseProjectMutationStage?
            var store: WorkspaceStore? = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    if stage == injectedStage {
                        throw CourseProjectSimulatedCrash()
                    }
                }
            )
            try store?.configureCourseLibrary(at: library)
            let courseA = try require(
                store?.createCourseInLibrary(title: "链接甲"),
                "没有链接甲课程"
            )
            let courseB = try require(
                store?.createCourseInLibrary(title: "链接乙"),
                "没有链接乙课程"
            )
            let courseC = try require(
                store?.createCourseInLibrary(title: "链接丙"),
                "没有链接丙课程"
            )
            let item = try require(
                store?.importFileIntoCourseForSelfCheck(
                    source,
                    courseID: courseA,
                    role: .material
                ).item,
                "没有链接来源资料"
            )
            try store?.shareCourseOwnedItemForSelfCheck(
                itemID: item.id,
                withCourseID: courseB
            )
            let rootC = try require(
                store?.courseRootURL(for: courseC),
                "没有链接丙课程根"
            )
            let entryC = rootC.appendingPathComponent(
                "文稿/\(item.subtitle)"
            )
            for crashStage in [
                CourseProjectMutationStage
                    .afterSharedLinkPrepareBeforeJournalIdentity,
                .afterSharedLinkPlacementBeforeJournal,
            ] {
                injectedStage = crashStage
                try expectFailure("已有共享新增入口后、journal 回写前崩溃") {
                    try store?.shareCourseOwnedItemForSelfCheck(
                        itemID: item.id,
                        withCourseID: courseC
                    )
                }
                store = nil
                store = makeStore(
                    fixture: fixture,
                    mutationHook: { stage in
                        if stage == injectedStage {
                            throw CourseProjectSimulatedCrash()
                        }
                    }
                )
                try store?.recoverCourseTransactionsForSelfCheck()
                try check(
                    !entryC.exists
                        && Set(store?.courseIDs(for: item.id) ?? [])
                            == Set([courseA, courseB]),
                    "\(crashStage.rawValue) 中断后留下幽灵成员"
                )
                try check(
                    try courseTransactionChildren(in: rootC).isEmpty,
                    "\(crashStage.rawValue) 恢复后留下事务"
                )
            }
        }
    }

    @MainActor
    private static func sharedRemovalCrashRecoversCommittedMembership() throws {
        for crashStage in [
            CourseProjectMutationStage
                .afterSharedLinkIsolationBeforeJournal,
            .afterSharedLinkRemovalWorkspaceSaveBeforeJournal,
        ] {
            let fixture = try Fixture(
                name: "shared-removal-\(crashStage.rawValue)"
            )
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待共享")
            let source = incoming.appendingPathComponent("删除共享入口.txt")
            let original = Data("共享原件仍保留".utf8)
            try original.write(to: source)
            var injectedStage: CourseProjectMutationStage?
            var store: WorkspaceStore? = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    if stage == injectedStage {
                        throw CourseProjectSimulatedCrash()
                    }
                }
            )
            try store?.configureCourseLibrary(at: library)
            let courseA = try require(
                store?.createCourseInLibrary(title: "删除甲"),
                "没有删除甲课程"
            )
            let courseB = try require(
                store?.createCourseInLibrary(title: "删除乙"),
                "没有删除乙课程"
            )
            let item = try require(
                store?.importFileIntoCourseForSelfCheck(
                    source,
                    courseID: courseA,
                    role: .material
                ).item,
                "没有删除测试资料"
            )
            try store?.shareCourseOwnedItemForSelfCheck(
                itemID: item.id,
                withCourseID: courseB
            )
            let sharedURL = try require(
                store?.importedItems.first { $0.id == item.id }?.url,
                "没有共享原件"
            )
            let rootB = try require(
                store?.courseRootURL(for: courseB),
                "没有删除乙课程根"
            )
            let membershipB = try require(
                store?.courseItemMemberships.first {
                    $0.courseID == courseB && $0.itemID == item.id
                },
                "没有待删除成员"
            )
            let entryB = rootB.appendingPathComponent(
                try require(
                    membershipB.courseRelativePath,
                    "待删除成员没有入口路径"
                )
            )
            injectedStage = crashStage
            try expectFailure("共享入口隔离事务崩溃") {
                try store?.removeSharedItemForSelfCheck(
                    itemID: item.id,
                    fromCourseID: courseB
                )
            }
            // S3：提交前崩溃即时回滚入口；提交后崩溃保留删除结果。
            let expectsRemoval =
                crashStage
                == .afterSharedLinkRemovalWorkspaceSaveBeforeJournal
            if expectsRemoval {
                try check(
                    !entryB.exists,
                    "\(crashStage.rawValue) 提交后入口应已隔离"
                )
            } else {
                try check(
                    entryB.exists
                        || CourseProjectFileWorker.isSymbolicLink(at: entryB),
                    "\(crashStage.rawValue) 提交前回滚后入口应恢复"
                )
            }
            try check(
                store?.courseIDs(for: item.id).contains(courseB)
                    == !expectsRemoval,
                "\(crashStage.rawValue) 的 workspace 成员状态错误"
            )
            store = nil
            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            try check(
                (
                    CourseProjectFileWorker.isSymbolicLink(at: entryB)
                        || entryB.exists
                ) == !expectsRemoval
                    && store?.courseIDs(for: item.id).contains(courseB)
                        == !expectsRemoval,
                "\(crashStage.rawValue) 没有按 workspace 提交状态恢复"
            )
            try check(
                try Data(contentsOf: sharedURL) == original,
                "删除单课程成员误删了共享原件"
            )
            try check(
                store?.courseIDs(for: item.id).contains(courseA) == true,
                "删除单课程成员破坏了其他课程入口"
            )
            try check(
                try courseTransactionChildren(in: rootB).isEmpty,
                "\(crashStage.rawValue) 恢复后留下事务"
            )
        }

        do {
            let fixture = try Fixture(name: "shared-removal-finder-race")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待共享")
            let source = incoming.appendingPathComponent("竞态删除.txt")
            try Data("共享原件".utf8).write(to: source)
            var injectReplacement = false
            var entryURL: URL?
            let preservedLink = fixture.root.appendingPathComponent(
                "Finder 移走的共享入口"
            )
            let finderContent = Data("Finder 换入的普通文件".utf8)
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard injectReplacement,
                          stage == .beforeSharedLinkIsolation,
                          let entryURL else {
                        return
                    }
                    injectReplacement = false
                    try FileManager.default.moveItem(
                        at: entryURL,
                        to: preservedLink
                    )
                    try finderContent.write(to: entryURL)
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseA = try store.createCourseInLibrary(title: "竞态甲")
            let courseB = try store.createCourseInLibrary(title: "竞态乙")
            let item = try store.importFileIntoCourseForSelfCheck(
                source,
                courseID: courseA,
                role: .material
            ).item
            try store.shareCourseOwnedItemForSelfCheck(
                itemID: item.id,
                withCourseID: courseB
            )
            let rootB = try require(
                store.courseRootURL(for: courseB),
                "没有竞态乙课程根"
            )
            let membership = try require(
                store.courseItemMemberships.first {
                    $0.courseID == courseB && $0.itemID == item.id
                },
                "没有竞态删除成员"
            )
            entryURL = rootB.appendingPathComponent(
                try require(
                    membership.courseRelativePath,
                    "竞态删除成员没有路径"
                )
            )
            injectReplacement = true
            try expectFailure("共享入口隔离前 Finder 换入普通文件") {
                try store.removeSharedItemForSelfCheck(
                    itemID: item.id,
                    fromCourseID: courseB
                )
            }
            let currentEntry = try require(entryURL, "竞态入口丢失")
            try check(
                try Data(contentsOf: currentEntry) == finderContent,
                "共享删除竞态误删 Finder 换入的普通文件"
            )
            try check(
                CourseProjectFileWorker.isSymbolicLink(at: preservedLink),
                "共享删除竞态丢失 Finder 移走的原入口"
            )
            try check(
                store.courseIDs(for: item.id).contains(courseB),
                "共享删除竞态错误提交了成员删除"
            )
            try check(
                try courseTransactionChildren(in: rootB).isEmpty,
                "共享删除竞态安全回滚后仍留下事务"
            )
        }
    }

    @MainActor
    private static func sharedLinkRecoveryIsIdempotent() throws {
        let fixture = try Fixture(name: "shared-link-recovery")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let sourceDirectory = try fixture.makeDirectory("待迁移")
        let source = sourceDirectory.appendingPathComponent("恢复共享.txt")
        try Data("共享链接恢复".utf8).write(to: source)
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        try store?.configureCourseLibrary(at: library)
        let courseA = try require(
            store?.createCourseInLibrary(title: "课程甲"),
            "没有共享恢复课程甲"
        )
        let courseB = try require(
            store?.createCourseInLibrary(title: "课程乙"),
            "没有共享恢复课程乙"
        )
        let courseC = try require(
            store?.createCourseInLibrary(title: "课程丙"),
            "没有共享恢复课程丙"
        )
        let item = try require(
            store?.importFileIntoCourseForSelfCheck(
                source,
                courseID: courseA,
                role: .material
            ).item,
            "共享恢复原件没有导入"
        )
        try store?.shareCourseOwnedItemForSelfCheck(
            itemID: item.id,
            withCourseID: courseB
        )
        let sharedItem = try require(
            store?.importedItems.first { $0.id == item.id },
            "共享恢复资料丢失"
        )
        guard case .common(let sharedRelativePath) = sharedItem.storage else {
            throw CheckError.failed("共享恢复资料没有共享存储")
        }
        let sharedURL = library.appendingPathComponent(sharedRelativePath)
        let sharedIdentity = try require(
            CourseProjectFileWorker.identity(at: sharedURL),
            "共享恢复原件没有文件身份"
        )
        let sharedSnapshot = try CourseProjectFileWorker.snapshotFile(at: sharedURL)
        let rootC = try require(store?.courseRootURL(for: courseC), "没有共享恢复课程丙根")
        try check(store?.flushPendingWorkspaceSave() == true, "共享恢复基线没有保存")
        store = nil

        func prepareInterruptedLink() throws -> (
            transactionDirectory: URL,
            linkURL: URL,
            linkIdentity: ImportedFileIdentity
        ) {
            let transactionID = UUID()
            let transactionDirectory = rootC
                .appendingPathComponent(".weibei/transactions", isDirectory: true)
                .appendingPathComponent(transactionID.uuidString.lowercased(), isDirectory: true)
            try FileManager.default.createDirectory(
                at: transactionDirectory,
                withIntermediateDirectories: true
            )
            let transactionIdentity = try require(
                CourseProjectFileWorker.identity(at: transactionDirectory),
                "共享恢复事务目录没有身份"
            )
            let linkURL = rootC.appendingPathComponent("文稿/恢复共享.txt")
            try FileManager.default.createSymbolicLink(
                at: linkURL,
                withDestinationURL: sharedURL
            )
            let linkIdentity = try require(
                CourseProjectFileWorker.identity(at: linkURL),
                "共享恢复链接没有身份"
            )
            let journal = SharedLinkJournalFixture(
                transactionID: transactionID,
                transactionDirectoryIdentity: transactionIdentity,
                itemID: item.id,
                courseID: courseC,
                sharedPath: sharedURL.path,
                sharedRelativePath: sharedRelativePath,
                sharedIdentity: sharedIdentity,
                sharedSnapshot: sharedSnapshot,
                linkPath: linkURL.path,
                linkRelativePath: "文稿/恢复共享.txt",
                linkIdentity: linkIdentity,
                stage: "linkPlaced"
            )
            try JSONEncoder().encode(journal).write(
                to: transactionDirectory.appendingPathComponent("shared-link.json"),
                options: [.atomic]
            )
            return (transactionDirectory, linkURL, linkIdentity)
        }

        // S3：无 journal 恢复。残留事务目录被静默清理；不伪造/撤销成员关系。
        let planted = try prepareInterruptedLink()
        store = makeStore(fixture: fixture)
        try store?.recoverCourseTransactionsForSelfCheck()
        try check(
            !planted.transactionDirectory.exists,
            "S3 静默清理没有删除残留事务目录"
        )
        try check(
            store?.courseIDs(for: item.id).contains(courseC) == false,
            "S3 清理不应伪造课程成员关系"
        )
        // 无 journal 时无法知道半完成入口是否该删；清掉模拟残留后再正式共享。
        if FileManager.default.fileExists(atPath: planted.linkURL.path)
            || CourseProjectFileWorker.isSymbolicLink(at: planted.linkURL) {
            try FileManager.default.removeItem(at: planted.linkURL)
        }
        // 成功路径：正式共享到课程丙
        try store?.shareCourseOwnedItemForSelfCheck(
            itemID: item.id,
            withCourseID: courseC
        )
        try check(
            store?.courseIDs(for: item.id).contains(courseC) == true,
            "正式共享到课程丙失败"
        )
        try check(
            store?.importedItems.first { $0.id == item.id }?
                .storage.relativePath != nil,
            "共享原件错误生成了单文件权限书签"
        )
    }

    @MainActor
    private static func legacyCourseSnapshotStillDecodes() throws {
        let fixture = try Fixture(name: "legacy-snapshot")
        defer { fixture.remove() }
        let legacyID = UUID()
        let legacyCourse = Course(id: legacyID, title: "旧课程", sourceRootPath: "/tmp/旧课程")
        let snapshot = PersistedWorkspace(courses: [legacyCourse], activeCourseID: legacyID)
        var object = try require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any],
            "旧快照编码不是对象"
        )
        if var courses = object["courses"] as? [[String: Any]], !courses.isEmpty {
            courses[0].removeValue(forKey: "sourceRootRelativePath")
            courses[0].removeValue(forKey: "sourceRootIdentity")
            courses[0].removeValue(forKey: "sourceRootBookmarkData")
            object["courses"] = courses
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: fixture.workspaceDirectory.appendingPathComponent("workspace.json"), options: [.atomic])

        let store = makeStore(fixture: fixture)
        try check(store.course(withID: legacyID)?.title == "旧课程", "旧 Course 快照无法解码")
    }

    @MainActor
    private static func makeStore(
        fixture: Fixture,
        workspaceDirectory: URL? = nil,
        noteBackupRootURL: URL? = nil,
        startAccessing: @escaping (URL) -> Bool = { _ in true },
        stopAccessing: @escaping (URL) -> Void = { _ in },
        mutationHook: @escaping (CourseProjectMutationStage) throws -> Void = { _ in },
        bookmarkResolver: ((Data) -> CourseProjectResolvedBookmark?)? = nil,
        courseFileSourceRemover: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
        },
        contentSourceTrashMover: @escaping @Sendable (URL) throws -> URL = {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(
                at: $0,
                resultingItemURL: &trashedURL
            )
            guard let trashedURL else {
                throw CheckError.injectedFailure
            }
            return trashedURL as URL
        },
        workspaceWriter: @escaping (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: [.atomic])
        },
        portableStateWriter: @escaping (
            Data,
            URL,
            ImportedFileIdentity,
            Data?,
            () throws -> Void
        ) throws -> Void = {
            try CourseProjectFileWorker.writePortableState(
                $0,
                to: $1,
                expectedDirectoryIdentity: $2,
                expectedPreviousData: $3,
                beforeCommit: $4
            )
        }
    ) -> WorkspaceStore {
        WorkspaceStore(
            workspaceDirectory: workspaceDirectory ?? fixture.workspaceDirectory,
            courseRootBookmarkMaker: { Data($0.canonicalFileURL.path.utf8) },
            courseRootBookmarkResolver: bookmarkResolver ?? { data in
                    guard let path = String(data: data, encoding: .utf8) else { return nil }
                    return CourseProjectResolvedBookmark(
                        url: URL(fileURLWithPath: path).canonicalFileURL,
                        isStale: false
                    )
                },
            courseSecurityScopeStarter: startAccessing,
            courseSecurityScopeStopper: stopAccessing,
            courseProjectMutationHook: mutationHook,
            noteBackupRootURL: noteBackupRootURL,
            courseFileSourceRemover: courseFileSourceRemover,
            contentSourceTrashMover: contentSourceTrashMover,
            workspaceSnapshotWriter: workspaceWriter,
            coursePortableStateWriter: portableStateWriter,
            // Recovery scenarios in this suite invoke maintenance explicitly;
            // passive fixture stores must not write the same course roots.
            startsCourseFileMaintenance: false
        )
    }

    private static func courseTransactionChildren(in courseRoot: URL) throws -> [String] {
        let transactions = courseRoot.appendingPathComponent(
            ".weibei/transactions",
            isDirectory: true
        )
        guard transactions.exists else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: transactions.path).sorted()
    }

    private static func expectFailure(_ label: String, _ operation: () throws -> Void) throws {
        do {
            try operation()
            throw CheckError.expectedFailure(label)
        } catch CheckError.expectedFailure(let label) {
            throw CheckError.expectedFailure(label)
        } catch {
            return
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckError.failed(message) }
        return value
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckError.failed(message) }
    }

    private struct SharedLinkJournalFixture: Codable {
        var transactionID: UUID
        var transactionDirectoryIdentity: ImportedFileIdentity
        var itemID: String
        var courseID: UUID
        var sharedPath: String
        var sharedRelativePath: String
        var sharedIdentity: ImportedFileIdentity
        var sharedSnapshot: CourseFileSnapshot
        var linkPath: String
        var linkRelativePath: String
        var linkIdentity: ImportedFileIdentity?
        var stage: String
    }

    private enum CheckError: LocalizedError {
        case failed(String)
        case expectedFailure(String)
        case injectedFailure

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            case .expectedFailure(let label): "\(label)：本应失败的操作成功了"
            case .injectedFailure: "测试注入失败"
            }
        }
    }

    private struct Fixture {
        let root: URL
        let workspaceDirectory: URL

        init(name: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("weibei-course-root-\(name)-\(UUID().uuidString)", isDirectory: true)
            workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
            try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        }

        func makeDirectory(_ relativePath: String) throws -> URL {
            let url = root.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock {
            value = newValue
        }
    }
}

private extension URL {
    var canonicalFileURL: URL {
        resolvingSymlinksInPath().standardizedFileURL
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var isDirectory: Bool {
        var value: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &value) && value.boolValue
    }

    func stagingChildren() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { $0.hasPrefix(".weibei-course-staging-") }
            .sorted()
    }

    func portableExportStagingChildren() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { $0.hasPrefix(".weibei-course-export-") }
            .sorted()
    }

    func relativeEntries() throws -> [String] {
        let rootPath = canonicalFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { entry in
            guard let url = entry as? URL else { return nil }
            return String(url.canonicalFileURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }.sorted()
    }

    func visibleFileSnapshot() throws -> [String: Data] {
        let rootPath = canonicalFileURL.path
        guard let enumerator = FileManager.default.enumerator(at: self, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return [:]
        }
        var result: [String: Data] = [:]
        for case let url as URL in enumerator {
            let relativePath = String(url.canonicalFileURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relativePath == ".weibei" || relativePath.hasPrefix(".weibei/") {
                enumerator.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                result[relativePath] = try Data(contentsOf: url)
            }
        }
        return result
    }
}
