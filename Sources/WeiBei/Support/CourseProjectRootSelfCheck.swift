import Foundation
import WeiBeiCore

enum CourseProjectRootSelfCheck {
    @MainActor
    static func run() throws {
        try courseEntryPresentationResetsIntent()
        try escapeBridgeDefersToPresentedSurfaces()
        try libraryGrantPersistsAndBalancesSecurityScope()
        try unavailableCourseRootBlocksChatWithoutClearingDraft()
        try agentProjectSearchUsesVerifiedCourseGrants()
        try libraryCannotEqualOrSitInsideRegisteredCourse()
        try deniedSecurityScopeKeepsCourseUnavailable()
        try movedLibraryIntoWorkspaceIsRejectedOnRestore()
        try libraryCreationDerivesSafeNameAndRejectsConflicts()
        try newCourseCreatesAtomicProjectAndManifest()
        try portableCourseStateIsScopedAtomicAndRestorable()
        try portableCourseExportCopiesWholeTreeAndFailsClosed()
        try portableCourseStatePreservesOfflineAndCorruptChanges()
        try stagedAndWorkspaceFailuresLeaveNoGhostCourse()
        try failedAdoptionRollsBackOnlyItsOwnMetadata()
        try foreignWritesPreventRollbackDeletion()
        try dangerousAndOverlappingRootsWriteNothing()
        try pathComparisonFollowsActualVolumeCaseSensitivity()
        try linkedMetadataDirectoryIsRejectedWithoutWrites()
        try adoptingExistingFolderPreservesVisibleContentsAndIsIdempotent()
        try repeatedAdoptionRefreshesTrackingAndOwnership()
        try failedReadoptionRestoresPreviousCourseAndScope()
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
        try firstScanAndFinderReconciliationPreserveIdentity()
        try unavailableCourseMaterialKeepsCourseHomeOpenUntilRestored()
        try thousandFileReconciliationIsLinearAndHardLinksStayStable()
        try exclusivePlacementRejectsConcurrentTargetAndSymlinkSwap()
        try conflictChoicesPreserveDataAndRelations()
        try replacementKeepsTargetIdentityAcrossMoves()
        try replacementTrashFailureRestoresOriginal()
        try verifiedCleanupNeverDeletesReplacementInode()
        try legacyMoveAndSharedOriginalSemantics()
        try sharedRepairFailurePreservesMembershipUntilEntryDisappears()
        try sharedConversionStagesBesideSharedDestination()
        try sharedPostPlacementReplacementPreservesVerifiedOriginal()
        try committedSharedRecoveryNeverDeletesOriginalForLinkDrift()
        try sharedMutationCrashWindowsRecoverCleanly()
        try sharedRemovalCrashRecoversCommittedMembership()
        try sharedLinkRecoveryIsIdempotent()
        try legacyCourseSnapshotStillDecodes()
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
        let legacyCourseContext = try store.agentCourseContextForSelfCheck(
            courseID: courseA,
            query: "LEGACY_AGENT_SECRET"
        )
        try check(
            !legacyCourseScope.items.contains(where: { $0.itemID == legacyItem.id })
                && !legacyCourseSearch.items.contains(where: { $0.item.id == legacyItem.id })
                && !legacyGlobalSearch.items.contains(where: { $0.item.id == legacyItem.id })
                && !legacyCourseContext.catalog.contains(where: { $0.id == legacyItem.id })
                && !legacyCourseContext.items.contains(where: { $0.id == legacyItem.id }),
            "课程上下文或搜索读取了未迁入课程项目的旧外部资料"
        )
        store.removeCourseMembershipForAgentSelfCheck(
            itemID: legacyItem.id,
            courseID: courseA
        )

        let ownedURL = imports.appendingPathComponent("课程自有.txt")
        try Data("OWNED_AGENT_TOKEN".utf8).write(to: ownedURL)
        let ownedItem = try store.importFileIntoCourseForSelfCheck(
            ownedURL,
            courseID: courseA,
            role: .material
        ).item
        let ownedSearch = try store.agentHostSearchForSelfCheck(
            courseID: courseA,
            query: "OWNED_AGENT_TOKEN"
        )
        try check(
            ownedSearch.items.contains(where: { $0.item.id == ownedItem.id }),
            "课程 Agent 搜索没有读取已核验的课程自有资料"
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
        try check(
            liveNoteSearch.items.first(where: { $0.item.id == noteID })?
                .item.searchText.contains("凸性修正非线性") == true
                && liveNoteRead.items.first(where: { $0.item.id == noteID })?
                    .item.searchText.contains("凸性修正非线性") == true,
            "课程 Agent 没有优先读取尚未落盘的最新笔记正文"
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
                $0.url?.standardizedFileURL == requestLegacyNoteURL.standardizedFileURL
                    && $0.isNotebookNote
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
        let deniedRequest = try store.capturedAgentRequestForSelfCheck(
            courseID: courseA,
            materialItemID: requestLegacyMaterial.id,
            noteItemID: requestLegacyNote.id,
            selectionItemID: requestLegacyMaterial.id
        )
        try check(
            deniedRequest.materialText.isEmpty
                && deniedRequest.noteText.isEmpty
                && deniedRequest.selectionText == nil
                && deniedRequest.visualAssets.isEmpty
                && deniedRequest.focus?.materialItemID == nil
                && !deniedRequest.projectScope.items.contains(where: {
                    $0.itemID == requestLegacyMaterial.id
                        || $0.itemID == requestLegacyNote.id
                })
                && !deniedRequest.courseContext.catalog.contains(where: {
                    $0.id == requestLegacyMaterial.id || $0.id == requestLegacyNote.id
                }),
            "最终发给 Pi 的请求仍包含未通过课程授权的材料、笔记、选区或视觉附件"
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
            sharedResult.courseIDs == [courseB.uuidString.lowercased()],
            "课程乙 Chat 把共享资料错误归到了另一门课程"
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
    private static func unavailableCourseRootBlocksChatWithoutClearingDraft() throws {
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
        let marker = "课程根失效时不要清空这句话"
        reopened.agentDraft = marker
        reopened.askAgent()

        try check(reopened.agentDraft == marker, "课程根失效时清空了用户草稿")
        try check(reopened.lastFailedAgentQuestion == marker, "课程根失效时没有保留精确重试问题")
        try check(!reopened.isAskingAgent, "课程根失效后仍启动了 Agent 请求")
        try check(
            reopened.messages.last?.text.contains("课程文件夹") == true,
            "课程根失效时没有给出明确可见提示"
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
            let courseRoot = try fixture.makeDirectory("外部课程")
            let proposedLibrary = nested
                ? try fixture.makeDirectory("外部课程/资料库")
                : courseRoot
            let store = makeStore(fixture: fixture)
            let courseID = try store.adoptCourseFolder(at: courseRoot, title: "外部课程")

            try expectFailure(nested ? "资料库位于课程内" : "资料库等于课程") {
                try store.configureCourseLibrary(at: proposedLibrary)
            }
            try check(store.courseLibraryRootURL == nil, "非法资料库仍被配置")
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

            try expectFailure("接管 metadata 并发写入") {
                try store.adoptCourseFolder(at: external, title: "已有课程")
            }
            try check(
                try String(
                    contentsOf: external.appendingPathComponent(".weibei/foreign.txt"),
                    encoding: .utf8
                ) == "用户 metadata",
                "回滚误删了 .weibei 里的用户并发内容"
            )
            try check(store.courses.isEmpty, "接管并发保存失败后留下幽灵 Course")
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
        let stateURL = courseARoot.appendingPathComponent(
            ".weibei/course-state.json"
        )
        let stateData = try Data(contentsOf: stateURL)
        let state = try JSONDecoder().decode(
            CoursePortableState.self,
            from: stateData
        ).validated(expectedCourseID: courseA)
        var unsafeSourceState = state
        unsafeSourceState.studySessions[0].messages[
            unsafeSourceState.studySessions[0].messages.count - 1
        ].sources.append(
            AgentReplySource(
                itemID: foreignMaterial.id,
                kind: .material,
                title: "伪装成本课程的来源",
                label: "伪装来源",
                excerpt: "没有 courseID 也必须拒绝"
            )
        )
        try expectFailure("无 courseID 的跨课来源校验") {
            _ = try unsafeSourceState.validated(expectedCourseID: courseA)
        }
        var unsafeActionState = state
        unsafeActionState.studySessions[0].messages[
            unsafeActionState.studySessions[0].messages.count - 1
        ].actions.append(
            AgentReplyAction(
                kind: .writeNote,
                targetItemID: foreignMaterial.id
            )
        )
        try expectFailure("无 courseID 的跨课动作校验") {
            _ = try unsafeActionState.validated(expectedCourseID: courseA)
        }
        var unsafeMemoryState = state
        unsafeMemoryState.studySessions[0].messages[
            unsafeMemoryState.studySessions[0].messages.count - 1
        ].memoryUpdate = AgentReplyMemoryUpdate(
            memoryIDs: [UUID()],
            summary: "伪装成本课程的记忆更新"
        )
        try expectFailure("跨作用域学习记忆校验") {
            _ = try unsafeMemoryState.validated(expectedCourseID: courseA)
        }
        var crossCourseMemoryEntryState = state
        crossCourseMemoryEntryState.learningMemoryState?.entries[0]
            .sessionID = UUID()
        try expectFailure("学习记忆 entry 跨课 Chat 校验") {
            _ = try crossCourseMemoryEntryState.validated(
                expectedCourseID: courseA
            )
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
                        sessionID: UUID(),
                        actor: .agent
                    ),
                ]
        }
        try expectFailure("学习记忆 revision 跨课 Chat 校验") {
            _ = try crossCourseMemoryRevisionState.validated(
                expectedCourseID: courseA
            )
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
        let savedReply = try require(
            state.studySessions.first?.messages.last,
            "课程 Chat 没有进入可携带状态"
        )
        try check(
            state.items.map(\.itemID).sorted() == [material.id, noteID].sorted(),
            "可携带状态混入另一门课程资料"
        )
        try check(
            state.studySessions.count == 1
                && state.studySessions[0].id == fixtureState.sessionID
                && state.studySessions[0].messages.count == 501
                && state.studySessions[0].messages.first?.id
                    == fixtureState.firstMessageID
                && state.studySessions[0].messages.first?
                    .richAnswer?.narrative
                    == fixtureState.firstRichNarrative
                && state.studySessions[0].messages.first?
                    .actions.first?.proposedMarkdown
                    == "最早一条动作附件"
                && state.studySessions[0].focusItemIDs == [material.id]
                && savedReply.text == "课程回答正文必须保留。"
                && savedReply.toolTrace.isEmpty,
            "课程 Chat 的完整历史、回复附件或课程净化结果错误"
        )
        try check(
            savedReply.sources.map(\.itemID) == [material.id]
                && savedReply.actions.count == 1
                && savedReply.actions[0].targetItemID == noteID
                && savedReply.actions[0].sourceItemID == material.id
                && savedReply.memoryUpdate?.memoryIDs == [fixtureState.memoryID],
            "无 courseID 的跨课来源、动作或记忆引用进入了可携带状态"
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
                && !serialized.contains(foreignMaterial.id),
            "课程状态泄露本机绝对路径、内部日志或另一门课程 ID"
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
                && baselineConflictStore.workspaceSaveError != nil
                && Data(contentsOf: stateURL) == baselineDiskState,
            "已有旧工作区首次建立 baseline 时用磁盘状态覆盖了本机 Chat"
        )

        let reopenedWorkspace = try fixture.makeDirectory("另一台设备工作区")
        let reopened = makeStore(
            fixture: fixture,
            workspaceDirectory: reopenedWorkspace
        )
        let restoredCourseID = try reopened.adoptCourseFolder(
            at: courseARoot,
            title: "用户临时输入的名称"
        )
        try check(restoredCourseID == courseA, "重开后课程稳定 ID 发生变化")
        try check(
            reopened.course(withID: courseA)?.title == "可携带课程"
                && reopened.courseItemMemberships
                    .filter { $0.courseID == courseA }
                    .map(\.itemID).sorted() == [material.id, noteID].sorted()
                && reopened.studySessions
                    .filter { $0.courseID == courseA }
                    .map(\.id) == [fixtureState.sessionID]
                && reopened.studySessions
                    .first { $0.id == fixtureState.sessionID }?
                    .messages.count == 501
                && reopened.studySessions
                    .first { $0.id == fixtureState.sessionID }?
                    .messages.first?.id == fixtureState.firstMessageID
                && reopened.studySessions
                    .first { $0.id == fixtureState.sessionID }?
                    .messages.first?.richAnswer?.narrative
                    == fixtureState.firstRichNarrative
                && reopened.studySessions
                    .first { $0.id == fixtureState.sessionID }?
                    .messages.first?.actions.first?.proposedMarkdown
                    == "最早一条动作附件"
                && reopened.learningMemoryStates
                    .first { $0.scope == .course(courseA) }?
                    .entries.map(\.id) == [fixtureState.memoryID]
                && reopened.noteSourceLinks.count == 1
                && reopened.courseResumePoint(for: courseA)?.chatID
                    == fixtureState.sessionID
                && reopened.pendingPortableNoteDraftForSelfCheck(itemID: noteID)
                    == fixtureState.draft,
            "新工作区没有从课程文件夹恢复完整课程状态"
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
            .importedFileLastKnownPath = sharedURL.path
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
            preservedCanonical.urlPath == sharedURL.path
                && preservedCanonical.importedFileIdentity
                    == canonicalSharedIdentity
                && preservedCanonical.contentDigest
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
        try check(
            Data(contentsOf: stateURL) == externalStateData
                && casStore.course(withID: courseA)?.title
                    == "本机待保存更新"
                && casStore.workspaceSaveError != nil
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
                && swappedUnreadableStore.workspaceSaveError != nil
                && unreadablePreservedLocalCandidate,
            "交换后旧状态变为不可读入口时删除了外部版本或本机候选"
        )
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
        _ = try existingRollbackStore.adoptCourseFolder(
            at: courseARoot,
            title: "已有状态回滚并发"
        )
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
            Data(contentsOf: stateURL) == sharedStateData
                && existingRollbackStore.workspaceSaveError != nil
                && existingRollbackRejected
                && existingRollbackCandidate,
            "已有课程状态回滚遇到外部原地改写时没有同时保住旧状态、外部版本与本机候选"
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
        _ = try unreadableRollbackStore.adoptCourseFolder(
            at: courseARoot,
            title: "已有状态不可读回滚"
        )
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
            Data(contentsOf: stateURL) == sharedStateData
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

        let beforeLocalOversizedState = try Data(contentsOf: stateURL)
        let oversizedMessageText = String(
            repeating: "x",
            count: 33 * 1_024 * 1_024
        )
        let oversizedMessageID =
            try store.appendPortableCourseMessageForSelfCheck(
                courseID: courseA,
                text: oversizedMessageText
            )
        try check(
            store.flushPendingWorkspaceSave(),
            "本机课程状态超限时阻断了总工作区保存"
        )
        let localOversizedWorkspace = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(
                contentsOf: fixture.workspaceDirectory
                    .appendingPathComponent("workspace.json")
            )
        )
        let persistedOversizedMessage = localOversizedWorkspace
            .studySessions?
            .first { $0.id == fixtureState.sessionID }?
            .messages
            .first { $0.id == oversizedMessageID }
        try check(
            Data(contentsOf: stateURL) == beforeLocalOversizedState
                && persistedOversizedMessage?.text.count
                    == oversizedMessageText.count
                && localOversizedWorkspace.dirtyPortableCourseIDs?
                    .contains(courseA) == true
                && store.workspaceSaveError?.contains("32 MB") == true,
            "本机最终课程状态超过 32MB 时没有保存工作区、保留原状态或给出明确错误"
        )
        store.removePortableCourseMessageForSelfCheck(
            courseID: courseA,
            messageID: oversizedMessageID
        )
        let recoveredMessageID =
            try store.appendPortableCourseMessageForSelfCheck(
                courseID: courseA,
                text: "缩小后的课程状态能够继续保存。"
            )
        let recoveredFromLocalOversize =
            store.flushPendingWorkspaceSave()
        let recoveredOversizeFlags =
            store.portableStateFlagsForSelfCheck(courseID: courseA)
        let recoveredCourseState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: stateURL)
        ).validated(expectedCourseID: courseA)
        try check(
            recoveredFromLocalOversize
                && !recoveredOversizeFlags.dirty
                && !recoveredOversizeFlags.blocked
                && !recoveredOversizeFlags.oversized
                && store.workspaceSaveError?.contains("32 MB") != true
                && recoveredCourseState.studySessions
                    .flatMap(\.messages)
                    .contains { $0.id == recoveredMessageID },
            "课程内容缩小后没有从超限阻断中安全恢复"
                + "（saved=\(recoveredFromLocalOversize)，"
                + "error=\(store.workspaceSaveError ?? "nil")，"
                + "flags=\(recoveredOversizeFlags)）"
        )

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
        _ = try failingStore.adoptCourseFolder(
            at: courseARoot,
            title: "写入失败课程"
        )
        failingStore.renameCourse(courseA, title: "不应落盘的名称")
        try check(
            Data(contentsOf: stateURL) == beforeFailedWrite
                && failingStore.workspaceSaveError != nil,
            "可携带状态原子写失败后覆盖了已提交状态或没有明确报错"
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
        try check(
            didSwapMetadataDirectory
                && directoryRaceStore?.workspaceSaveError != nil
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
        _ = try store.installPortableCourseStateFixtureForSelfCheck(
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
        try adoptedStore.configureCourseLibrary(at: library)
        let adoptedCourseID = try adoptedStore.adoptCourseFolder(
            at: exportRoot,
            title: "已接管导出课程"
        )
        let normalizedManifest = try CourseProjectManifest.read(
            from: exportRoot.appendingPathComponent(
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
                        to: tamperedAdoptionRoot.appendingPathComponent(
                            postSaveTamper.relativePath
                        )
                    )
                }
            )
            try tamperedAdoptionStore.configureCourseLibrary(at: library)
            try expectFailure(postSaveTamper.name) {
                _ = try tamperedAdoptionStore.adoptCourseFolder(
                    at: tamperedAdoptionRoot,
                    title: postSaveTamper.name
                )
            }
            let retainedManifest = try JSONDecoder().decode(
                CourseProjectManifest.self,
                from: Data(
                    contentsOf: tamperedAdoptionRoot
                        .appendingPathComponent(
                            ".weibei/course.json"
                        )
                )
            )
            try check(
                retainedManifest.portableExport != nil,
                "\(postSaveTamper.name)后仍错误消费了导出封印"
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
        try crashStore?.configureCourseLibrary(at: library)
        try expectFailure("接管保存后消费封印前崩溃") {
            _ = try crashStore?.adoptCourseFolder(
                at: crashExportRoot,
                title: "等待恢复的导出课程"
            )
        }
        let sealedAfterCrash = try CourseProjectManifest.read(
            from: crashExportRoot.appendingPathComponent(
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
            from: crashExportRoot.appendingPathComponent(
                ".weibei/course.json"
            )
        )
        try check(
            recoveredCrashStore.course(withID: courseA) != nil
                && recoveredCrashStore.courseRootURL(for: courseA)
                    == crashExportRoot.canonicalFileURL
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
        let mutationStagingBefore = try stagingNames()
        try expectFailure("导出期间源目录变化") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: mutationTarget,
                stageHook: { current in
                    guard current == .beforeAtomicPlacement else { return }
                    try Data("LATE_SOURCE".utf8).write(to: lateSourceFile)
                }
            )
        }
        try check(
            !mutationTarget.exists
                && lateSourceFile.exists,
            "源目录在复制期间变化后仍提交了不完整导出"
        )
        try verifyAndRemoveRetainedStaging(
            since: mutationStagingBefore,
            target: mutationTarget
        )
        try FileManager.default.removeItem(at: lateSourceFile)

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
        try expectFailure("回答生成中导出") {
            _ = try store.exportPortableCourseCopyForSelfCheck(
                courseID: courseA,
                to: generatingTarget
            )
        }
        try store.setCourseReplyGeneratingForSelfCheck(
            courseID: courseA,
            generating: false
        )
        try check(!generatingTarget.exists, "回答生成中仍抓取了半轮课程状态")

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
    private static func portableCourseStatePreservesOfflineAndCorruptChanges() throws {
        let fixture = try Fixture(name: "portable-state-offline")
        defer { fixture.remove() }
        let courseRoot = try fixture.makeDirectory("外部课程")
        let movedRoot = fixture.root.appendingPathComponent(
            "暂时移走的外部课程",
            isDirectory: true
        )
        var store: WorkspaceStore? = makeStore(fixture: fixture)
        let courseID = try require(
            store?.adoptCourseFolder(
                at: courseRoot,
                title: "外部课程"
            ),
            "无法建立离线课程样本"
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
            recoveredState.metadata.title == "离线期间更新的课程"
                && recoveredState.studySessions.contains {
                    $0.id == offlineChatID
                }
                && Data(contentsOf: stateURL) != originalState,
            "旧 course-state 在根恢复后覆盖了离线期间的新课程缓存"
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
        let sharedDirectory = try fixture.makeDirectory("课程资料库/共享文稿")
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
        let external = try fixture.makeDirectory("外部课程")
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

        try expectFailure("符号链接 metadata") {
            _ = try store.adoptCourseFolder(
                at: external,
                title: "外部课程"
            )
        }
        try check(store.courses.isEmpty, "符号链接 metadata 产生了幽灵课程")
        try check(
            try FileManager.default.contentsOfDirectory(atPath: external.path)
                == externalEntriesBefore,
            "拒绝符号链接 metadata 前写入了课程根"
        )
        try check(
            try Data(contentsOf: manifestURL) == manifestData,
            "拒绝符号链接 metadata 时改写了外部清单"
        )
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: linkedMetadata),
            "拒绝符号链接 metadata 时替换了用户入口"
        )
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
        let external = try fixture.makeDirectory("损坏课程")
        let metadata = try fixture.makeDirectory("损坏课程/.weibei")
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
                        && item.importedFileBookmarkData == nil
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
        try check(observedCommittedSnapshotBeforeDelete.get(), "原件删除前 workspace 尚未提交新文稿")
        try check(observedAtomicSourceQuarantine.get(), "原件没有先在同目录原子隔离再删除")
        try check(!source.exists, "提交成功后没有移除课程外原件")
        try check(try Data(contentsOf: target) == original, "课程文稿内容与原件不一致")
        try check(!result.sourceCleanupPending, "正常移入错误标记为待清理")
        try check(result.item.urlPath == target.canonicalFileURL.path, "文稿没有指向课程目录")
        try check(result.item.importedFileBookmarkData == nil, "课程自有文稿生成了单文件书签")
        try check(result.item.contentRevision == 1 && result.item.contentDigest != nil, "文稿缺少初始版本或摘要")
        guard case .courseOwned(let ownerCourseID) = result.item.storage else {
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
            try check(
                !(try courseTransactionChildren(in: courseRoot)).isEmpty,
                "目标被外来文件替换后没有保留可调查 journal"
            )
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
            try check(
                !(try courseTransactionChildren(in: courseRoot)).isEmpty,
                "目标目录身份失效后仍清除了恢复 journal"
            )
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
            try check(result.sourceCleanupPending, "删源前目录竞态没有进入待清理状态")
            try check(!sourceRemoverCalled.get(), "目录重验失败后仍调用了删源")
            try check(try Data(contentsOf: source) == original, "删源前目录竞态删除了原件")
            try check(
                movedMaterialDirectory.appendingPathComponent("删源前换目录.txt").exists,
                "删源前目录竞态丢失已提交副本"
            )
            try check(!(try courseTransactionChildren(in: courseRoot)).isEmpty, "删源前目录竞态清除了 journal")
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
            try check(target.exists, "\(state.rawValue) 场景错误删除了唯一课程副本")
            let journalsBeforeReopen = try courseTransactionChildren(in: courseRoot)
            try check(!journalsBeforeReopen.isEmpty, "\(state.rawValue) 场景没有保留恢复 journal")
            try check(store?.courseItems(in: courseID).isEmpty == true, "\(state.rawValue) 场景留下内存幽灵记录")
            store = nil

            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            try check(target.exists, "\(state.rawValue) 场景重开后删除了课程副本")
            try check(
                try courseTransactionChildren(in: courseRoot).isEmpty,
                "\(state.rawValue) 场景完成可见恢复后仍留下 journal"
            )
            try check(
                store?.courseItems(in: courseID).contains(where: {
                    $0.urlPath == target.path && $0.contentDigest != nil
                }) == true,
                "\(state.rawValue) 场景没有把已校验目标恢复为可见资料"
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
        try check(result.sourceCleanupPending, "删源失败没有标记待重试")
        try check(try Data(contentsOf: source) == original, "删源失败没有保留原件")
        try check(try Data(contentsOf: target) == original, "删源失败丢失已提交目标")
        try check(!(try courseTransactionChildren(in: courseRoot)).isEmpty, "删源失败没有保留 journal")
        store = nil

        let recoveryUsedAtomicQuarantine = LockedBox(false)
        store = makeStore(
            fixture: fixture,
            courseFileSourceRemover: { quarantineURL in
                recoveryUsedAtomicQuarantine.set(
                    !source.exists
                    && quarantineURL.deletingLastPathComponent() == source.deletingLastPathComponent()
                    && quarantineURL.lastPathComponent.contains(".weibei-quarantine-")
                )
                try FileManager.default.removeItem(at: quarantineURL)
            }
        )
        let reopenedItem = try require(
            store?.importedItems.first { $0.id == itemID },
            "重开后丢失已提交文稿"
        )
        try check(recoveryUsedAtomicQuarantine.get(), "恢复删源没有先做同目录原子隔离")
        try check(!source.exists, "重开没有重试清理原件")
        try check(try Data(contentsOf: target) == original, "重开清理误删课程文稿")
        try check(reopenedItem.importedFileBookmarkData == nil, "重开后课程文稿生成了单文件书签")
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
        let quarantineURL = try require(observedQuarantineURL.get(), "删源没有进入隔离路径")
        try check(result.sourceCleanupPending, "隔离恢复失败没有标记待清理")
        try check(try Data(contentsOf: source) == foreign, "隔离恢复覆盖了用户并发文件")
        try check(try Data(contentsOf: quarantineURL) == original, "隔离恢复丢失了原始副本")
        let transactionName = try require(
            courseTransactionChildren(in: courseRoot).first,
            "隔离恢复失败没有保留 journal"
        )
        let journalURL = courseRoot.appendingPathComponent(
            ".weibei/transactions/\(transactionName)/journal.json"
        )
        let journalObject = try require(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL))
                as? [String: Any],
            "隔离 journal 不是对象"
        )
        try check(
            journalObject["sourceQuarantinePath"] as? String == quarantineURL.path,
            "journal 没有记录原件隔离路径"
        )
        store = nil

        store = makeStore(fixture: fixture)
        try check(try Data(contentsOf: source) == foreign, "重开误删用户并发文件")
        try check(try Data(contentsOf: quarantineURL) == original, "重开误删隔离原件")
        try check(journalURL.exists, "存在双副本冲突时重开清除了 journal")
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
        let transactionName = try require(
            courseTransactionChildren(in: courseRoot).first,
            "没有待清理事务目录"
        )
        let transactionDirectory = courseRoot.appendingPathComponent(
            ".weibei/transactions/\(transactionName)",
            isDirectory: true
        )
        let hiddenForeign = transactionDirectory.appendingPathComponent(".foreign")
        try Data("不能删除".utf8).write(to: hiddenForeign)
        let journalURL = transactionDirectory.appendingPathComponent("journal.json")
        store = nil

        store = makeStore(fixture: fixture)
        try check(!source.exists, "恢复没有完成已核验原件清理")
        try check(hiddenForeign.exists, "事务清理误删隐藏异物")
        try check(journalURL.exists, "事务清理先删 journal 后才发现隐藏异物")
        try check(transactionDirectory.exists, "隐藏异物存在时仍删除事务目录")
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
        let transactionName = try require(
            courseTransactionChildren(in: courseRoot).first,
            "删源失败没有事务目录"
        )
        store = nil

        let transactions = courseRoot.appendingPathComponent(".weibei/transactions", isDirectory: true)
        let originalTransaction = transactions.appendingPathComponent(transactionName, isDirectory: true)
        let outsideParent = try fixture.makeDirectory("课程外事务")
        let outsideTransaction = outsideParent.appendingPathComponent(transactionName, isDirectory: true)
        try FileManager.default.moveItem(at: originalTransaction, to: outsideTransaction)
        try FileManager.default.createSymbolicLink(
            at: originalTransaction,
            withDestinationURL: outsideTransaction
        )

        store = makeStore(fixture: fixture)
        try check(try Data(contentsOf: source) == original, "链接事务目录驱动恢复删除了课程外原件")
        try check(
            outsideTransaction.appendingPathComponent("journal.json").exists,
            "链接事务目录驱动恢复清理了课程外 journal"
        )
        try check(
            courseRoot.appendingPathComponent("文稿/链接事务.txt").exists,
            "拒绝链接事务目录时丢失已提交目标"
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
        try check(movedItem.importedFileBookmarkData == nil, "课程根移动恢复依赖了单文件书签")
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
            try check(reopened.importedFileLastKnownPath == target.path, "同路径原子保存后丢失路径")
            try check(reopened.importedFileBookmarkData == nil, "换 inode 后生成了单文件书签")
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
            try check(reopened.importedFileBookmarkData == nil, "原位编辑重开后生成单文件书签")
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
                store.importedItems.first { $0.id == itemID }?.importedFileBookmarkData == nil,
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
            try check(store.courseLibraryRootURL == nil, "重新授权保存失败仍切换了资料库")
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
        guard case .courseOwned(let ownerCourseID) = courseNote.storage else {
            throw CheckError.failed("课程笔记没有标记为课程自有")
        }
        try check(ownerCourseID == courseID, "课程笔记归属错误")
        try check(
            courseNote.urlPath == courseRoot.appendingPathComponent("笔记/课程笔记.md").canonicalFileURL.path,
            "课程笔记没有写入课程笔记目录"
        )
        try check(courseNote.importedFileBookmarkData == nil, "课程笔记生成了单文件书签")
        try check(
            store.courseItemMemberships.first { $0.itemID == courseNoteID }?.courseRelativePath
                == "笔记/课程笔记.md",
            "课程笔记缺少课程相对路径"
        )
        let updatedMarkdown = "# 课程笔记\n\n已经写回课程目录。\n"
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
        try check(updatedCourseNote.importedFileBookmarkData == nil, "课程笔记写回后生成了单文件书签")

        store.createBlankNotebookNote()
        let globalNoteID = try require(store.activeNotebookItemID, "没有创建全局笔记")
        try check(globalNoteID != courseNoteID, "全局笔记复用了课程笔记")
        let globalNote = try require(
            store.importedItems.first { $0.id == globalNoteID },
            "全局笔记没有进入项目"
        )
        try check(globalNote.storage == .legacyExternal, "全局笔记被错误标记为课程自有")
        try check(
            !store.courseItemMemberships.contains { $0.itemID == globalNoteID },
            "全局笔记被自动塞入当前课程"
        )
        try check(
            globalNote.urlPath?.hasPrefix(
                fixture.workspaceDirectory.appendingPathComponent("Files/Notes").path
            ) == true,
            "全局笔记没有写入独立的 App 管理目录"
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
        try check(!source.exists, "大文件后台导入没有完成移动")

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
        do {
            let fixture = try Fixture(name: "markdown-finder-race")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            var injectFinderReplacement = false
            var noteURL: URL?
            let movedOriginal = fixture.root.appendingPathComponent(
                "Finder 保留的旧稿.md"
            )
            let finderContent = Data("# Finder 新稿\n\n不得覆盖".utf8)
            let draft = "# 魏碑草稿\n\n继续保留"
            let store = makeStore(
                fixture: fixture,
                mutationHook: { stage in
                    guard injectFinderReplacement,
                          stage == .beforeCourseMarkdownTargetIsolation,
                          let noteURL else {
                        return
                    }
                    injectFinderReplacement = false
                    try FileManager.default.moveItem(
                        at: noteURL,
                        to: movedOriginal
                    )
                    try finderContent.write(to: noteURL)
                }
            )
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(
                title: "Markdown 竞态"
            )
            let noteID = try require(
                store.createCourseNotebookNoteForSelfCheck(
                    courseID: courseID,
                    title: "竞态笔记"
                ),
                "没有 Markdown 竞态笔记"
            )
            noteURL = try require(
                store.importedItems.first { $0.id == noteID }?.url,
                "没有 Markdown 竞态路径"
            )
            let original = try Data(contentsOf: require(
                noteURL,
                "没有 Markdown 竞态路径"
            ))
            injectFinderReplacement = true
            try expectFailure("Markdown 隔离前 Finder 换入新 inode") {
                try store.writeCourseMarkdownForSelfCheck(
                    itemID: noteID,
                    markdown: draft
                )
            }
            let currentURL = try require(noteURL, "Markdown 竞态路径丢失")
            try check(
                try Data(contentsOf: currentURL) == finderContent,
                "Markdown 条件写覆盖了 Finder 换入的新内容"
            )
            try check(
                try Data(contentsOf: movedOriginal) == original,
                "Markdown 条件写丢失了 Finder 移走的旧稿"
            )
            try check(
                store.pendingCourseMarkdownDraftForSelfCheck(
                    itemID: noteID
                ) == draft,
                "Markdown 冲突没有保留魏碑草稿"
            )
            let root = try require(
                store.courseRootURL(for: courseID),
                "没有 Markdown 竞态课程根"
            )
            try check(
                try courseTransactionChildren(in: root).isEmpty,
                "Markdown 竞态安全回滚后仍留下事务"
            )
        }

        do {
            let fixture = try Fixture(name: "markdown-isolation-crash")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
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
                store?.createCourseInLibrary(title: "Markdown 恢复"),
                "没有 Markdown 恢复课程"
            )
            let noteID = try require(
                store?.createCourseNotebookNoteForSelfCheck(
                    courseID: courseID,
                    title: "恢复笔记"
                ),
                "没有 Markdown 恢复笔记"
            )
            let target = try require(
                store?.importedItems.first { $0.id == noteID }?.url,
                "没有 Markdown 恢复路径"
            )
            let original = try Data(contentsOf: target)
            let draft = "# 崩溃后仍保留的草稿"
            injectedStage =
                .afterCourseMarkdownTargetIsolationBeforeJournal
            try expectFailure("Markdown 隔离后、journal 回写前崩溃") {
                try store?.writeCourseMarkdownForSelfCheck(
                    itemID: noteID,
                    markdown: draft
                )
            }
            try check(
                !target.exists,
                "Markdown 崩溃注入没有落在旧稿已隔离窗口"
            )
            let root = try require(
                store?.courseRootURL(for: courseID),
                "没有 Markdown 恢复课程根"
            )
            try check(
                !(try courseTransactionChildren(in: root)).isEmpty,
                "Markdown 崩溃没有留下可恢复事务"
            )
            store = nil
            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            try check(
                try Data(contentsOf: target) == original,
                "Markdown 隔离中断没有恢复旧稿"
            )
            try check(
                store?.pendingCourseMarkdownDraftForSelfCheck(
                    itemID: noteID
                ) == draft,
                "Markdown 隔离中断丢失魏碑草稿"
            )
            try check(
                try courseTransactionChildren(in: root).isEmpty,
                "Markdown 隔离中断恢复后仍留下事务"
            )
        }
    }

    @MainActor
    private static func courseMarkdownPostPlacementReplacementPreservesAllContent() throws {
        let fixture = try Fixture(name: "markdown-post-placement-replacement")
        defer { fixture.remove() }
        let library = try fixture.makeDirectory("课程资料库")
        let foreign = Data("# Finder 外来稿\n\n不得覆盖".utf8)
        let draft = "# 魏碑最新草稿\n\n也不得丢失"
        var replaceTarget = false
        var noteURL: URL?
        let store = makeStore(
            fixture: fixture,
            mutationHook: { stage in
                guard replaceTarget,
                      stage == .afterCourseMarkdownTargetPlacementBeforeJournal,
                      let noteURL else {
                    return
                }
                replaceTarget = false
                try FileManager.default.removeItem(at: noteURL)
                try foreign.write(to: noteURL, options: [.withoutOverwriting])
            }
        )
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(
            title: "Markdown 落位竞态"
        )
        let noteID = try require(
            store.createCourseNotebookNoteForSelfCheck(
                courseID: courseID,
                title: "落位竞态笔记"
            ),
            "没有 Markdown 落位竞态笔记"
        )
        noteURL = try require(
            store.importedItems.first { $0.id == noteID }?.url,
            "没有 Markdown 落位竞态路径"
        )
        let target = try require(noteURL, "Markdown 落位竞态路径丢失")
        let original = try Data(contentsOf: target)
        let root = try require(
            store.courseRootURL(for: courseID),
            "没有 Markdown 落位竞态课程根"
        )
        replaceTarget = true

        try expectFailure("Markdown 落位后 Finder 换入新 inode") {
            try store.writeCourseMarkdownForSelfCheck(
                itemID: noteID,
                markdown: draft
            )
        }

        try check(
            try Data(contentsOf: target) == foreign,
            "Markdown 落位竞态覆盖或删除了 Finder 外来稿"
        )
        try check(
            store.pendingCourseMarkdownDraftForSelfCheck(itemID: noteID)
                == draft,
            "Markdown 落位竞态丢失了魏碑草稿"
        )
        let transactionIDs = try courseTransactionChildren(in: root)
        let preservedOriginals = try transactionIDs.compactMap { transactionID in
            let originalURL = root.appendingPathComponent(
                ".weibei/transactions/\(transactionID)/original"
            )
            return originalURL.exists ? try Data(contentsOf: originalURL) : nil
        }
        try check(
            preservedOriginals.contains(original),
            "Markdown 落位竞态丢失了写入前原稿"
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
            store.importedItems.first { $0.id == noteItem.id }?.urlPath == nil,
            "Finder 删除后没有保留明确不可用记录"
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
            store.importedItems.first { $0.id == item.id }?.urlPath == nil,
            "失联文稿没有被标记为不可用"
        )

        store.presentCourseWorkspace(.hub, courseID: courseID)
        let previousSelection = store.selectedItemID
        store.openCourseMaterial(item.id)
        try check(
            store.courseWorkspacePresented,
            "失联文稿错误关闭了课程首页"
        )
        try check(
            store.selectedItemID == previousSelection,
            "失联文稿错误切换到空阅读器"
        )

        try FileManager.default.moveItem(at: displacedURL, to: courseURL)
        store.openCourseMaterial(item.id)
        try check(
            !store.courseWorkspacePresented,
            "原文稿恢复后仍不能从课程首页打开"
        )
        try check(
            store.selectedMaterialItem?.id == item.id,
            "原文稿恢复后没有打开正确资料"
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
            let fixture = try Fixture(name: "replace-legacy-migrate-identity")
            defer { fixture.remove() }
            let library = try fixture.makeDirectory("课程资料库")
            let incoming = try fixture.makeDirectory("待迁移")
            let legacyURL = incoming.appendingPathComponent("迁移同名.txt")
            let targetURL = incoming.appendingPathComponent("目标/迁移同名.txt")
            try FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("旧外部新内容".utf8).write(to: legacyURL)
            try Data("课程旧内容".utf8).write(to: targetURL)
            let store = makeStore(fixture: fixture)
            try store.configureCourseLibrary(at: library)
            let courseID = try store.createCourseInLibrary(title: "迁移课程")
            let targetItem = try store.importFileIntoCourseForSelfCheck(
                targetURL,
                courseID: courseID,
                role: .material
            ).item
            let legacyItem = try require(
                store.importFiles(
                    [legacyURL],
                    selectsFirstImportedItem: false
                ).first,
                "旧外部资料没有导入"
            )
            let noteID = try require(
                store.createCourseNotebookNoteForSelfCheck(
                    courseID: courseID,
                    title: "迁移关系"
                ),
                "没有迁移关系笔记"
            )
            store.setLinkedSourceIDs(
                [legacyItem.id, targetItem.id],
                for: noteID
            )

            let migrated = try store.migrateLegacyExternalItemForSelfCheck(
                itemID: legacyItem.id,
                courseID: courseID,
                conflictResolution: .replace
            ).item
            try check(
                migrated.id == targetItem.id,
                "旧外部迁移替换没有保留目标资料 ID"
            )
            try check(!legacyURL.exists, "旧外部迁移替换没有清理已验证来源")
            try check(
                !store.importedItems.contains { $0.id == legacyItem.id }
                    && !store.noteSourceLinks.contains {
                        $0.sourceItemID == legacyItem.id
                    },
                "旧外部迁移替换留下悬空来源 ID"
            )
            try check(
                store.noteSourceLinks.contains {
                    $0.noteItemID == noteID
                        && $0.sourceItemID == targetItem.id
                },
                "旧外部迁移替换没有保留合并后的关系"
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
            if crashStage
                == .afterCourseFileRollbackArtifactCreationBeforeJournalIdentity {
                try check(
                    try Data(contentsOf: target) == original,
                    "回滚占位创建后崩溃错误移动了旧目标"
                )
            } else {
                try check(
                    !target.exists,
                    "崩溃注入点错误：旧目标仍在原位"
                )
            }
            try check(
                !(try courseTransactionChildren(in: root)).isEmpty,
                "崩溃注入没有留下可恢复 journal"
            )
            store = nil
            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            try check(
                try Data(contentsOf: target) == original,
                "\(crashStage.rawValue) 中断没有恢复旧目标"
            )
            try check(
                try Data(contentsOf: source) == replacement,
                "\(crashStage.rawValue) 中断误删了新来源"
            )
            try check(
                try courseTransactionChildren(in: root).isEmpty,
                "\(crashStage.rawValue) 恢复后仍留下 journal"
            )
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

        let sharedDirectory = try fixture.makeDirectory("课程资料库/共享文稿")
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
        guard case .shared(let sharedRelativePath) = sharedItem.storage else {
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
            "共享文稿",
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
            "共享文稿/\(ownerEntry.lastPathComponent)"
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
            "共享文稿/\(ownerEntry.lastPathComponent)"
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
        try check(
            !(try courseTransactionChildren(in: rootA)).isEmpty,
            "共享提交崩溃没有留下恢复 journal"
        )

        try FileManager.default.removeItem(at: addedEntry)
        injectedStage = nil
        store = nil
        store = makeStore(fixture: fixture)
        try store?.recoverCourseTransactionsForSelfCheck()

        try check(
            try Data(contentsOf: sharedTarget) == original,
            "已提交共享恢复因单个链接漂移删除了唯一原件"
        )
        try check(
            CourseProjectFileWorker.isSymbolicLink(at: ownerEntry),
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
                "共享文稿/\(ownerEntry.lastPathComponent)"
            )
            injectedStage = crashStage
            try expectFailure("共享转换操作后、journal 回写前崩溃") {
                try store?.shareCourseOwnedItemForSelfCheck(
                    itemID: item.id,
                    withCourseID: courseB
                )
            }
            try check(
                !(try courseTransactionChildren(in: rootA)).isEmpty,
                "\(crashStage.rawValue) 没有留下恢复事务"
            )
            store = nil
            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            let recoveredItem = try require(
                store?.importedItems.first { $0.id == item.id },
                "共享中断恢复后资料丢失"
            )
            guard case .courseOwned(let recoveredCourseID) =
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
            try check(
                !entryB.exists,
                "\(crashStage.rawValue) 没有落在入口已隔离窗口"
            )
            let expectsRemoval =
                crashStage
                == .afterSharedLinkRemovalWorkspaceSaveBeforeJournal
            try check(
                store?.courseIDs(for: item.id).contains(courseB)
                    == !expectsRemoval,
                "\(crashStage.rawValue) 的 workspace 成员状态错误"
            )
            store = nil
            store = makeStore(fixture: fixture)
            try store?.recoverCourseTransactionsForSelfCheck()
            try check(
                CourseProjectFileWorker.isSymbolicLink(at: entryB)
                    == !expectsRemoval
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
        guard case .shared(let sharedRelativePath) = sharedItem.storage else {
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

        let uncommitted = try prepareInterruptedLink()
        store = makeStore(fixture: fixture)
        try store?.recoverCourseTransactionsForSelfCheck()
        try check(
            CourseProjectFileWorker.identity(at: uncommitted.linkURL) == nil,
            "未提交共享链接恢复没有回滚链接"
        )
        try check(
            !uncommitted.transactionDirectory.exists,
            "未提交共享链接恢复没有清理 journal"
        )
        try check(
            store?.courseIDs(for: item.id).contains(courseC) == false,
            "未提交共享链接恢复伪造了课程成员关系"
        )
        store = nil

        let committed = try prepareInterruptedLink()
        let workspaceURL = fixture.workspaceDirectory.appendingPathComponent("workspace.json")
        var workspace = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(contentsOf: workspaceURL)
        )
        var memberships = workspace.courseItemMemberships ?? []
        memberships.append(
            CourseItemMembership(
                courseID: courseC,
                itemID: item.id,
                courseRelativePath: "文稿/恢复共享.txt",
                entryIdentity: committed.linkIdentity
            )
        )
        workspace.courseItemMemberships = memberships
        try JSONEncoder().encode(workspace).write(to: workspaceURL, options: [.atomic])
        let portableStateURL = rootC.appendingPathComponent(
            ".weibei/course-state.json"
        )
        var portableState = try JSONDecoder().decode(
            CoursePortableState.self,
            from: Data(contentsOf: portableStateURL)
        )
        portableState.items.append(
            CoursePortableItem(
                itemID: sharedItem.id,
                title: sharedItem.title,
                kind: sharedItem.kind,
                isNotebookNote: sharedItem.isNotebookNote,
                courseRelativePath: "文稿/恢复共享.txt",
                storage: .sharedReference(
                    sharedRelativePath: sharedRelativePath,
                    expectedContentDigest: sharedItem.contentDigest
                ),
                contentRevision: sharedItem.contentRevision,
                contentDigest: sharedItem.contentDigest,
                fileByteCount: sharedItem.fileByteCount,
                fileModificationTimeNanoseconds:
                    sharedItem.fileModificationTimeNanoseconds,
                membershipCreatedAt: Date()
            )
        )
        portableState.revision &+= 1
        portableState.savedAt = Date()
        try JSONEncoder().encode(portableState).write(
            to: portableStateURL,
            options: [.atomic]
        )

        store = makeStore(fixture: fixture)
        try store?.recoverCourseTransactionsForSelfCheck()
        try check(
            CourseProjectFileWorker.identity(at: committed.linkURL) == committed.linkIdentity,
            "已提交共享链接恢复误删了真实入口"
        )
        try check(
            !committed.transactionDirectory.exists,
            "已提交共享链接恢复没有清理 journal"
        )
        try check(
            store?.courseIDs(for: item.id).filter { $0 == courseC }.count == 1,
            "已提交共享链接恢复没有保持唯一成员关系"
        )
        try check(
            store?.importedItems.first { $0.id == item.id }?
                .importedFileBookmarkData == nil,
            "共享原件重开后错误生成了单文件权限书签"
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
        startAccessing: @escaping (URL) -> Bool = { _ in true },
        stopAccessing: @escaping (URL) -> Void = { _ in },
        mutationHook: @escaping (CourseProjectMutationStage) throws -> Void = { _ in },
        bookmarkResolver: ((Data) -> CourseProjectResolvedBookmark?)? = nil,
        courseFileSourceRemover: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.removeItem(at: $0)
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
            courseFileSourceRemover: courseFileSourceRemover,
            workspaceSnapshotWriter: workspaceWriter,
            coursePortableStateWriter: portableStateWriter
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
