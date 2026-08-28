import Foundation
import WeiBeiCore

private struct CoursePortableStateWriteRecord {
    let url: URL
    let previousData: Data?
    let committedData: Data
    let expectedDirectoryIdentity: ImportedFileIdentity
}

private struct CoursePortableStateCommit {
    let writes: [CoursePortableStateWriteRecord]
    let previousRevisions: [UUID: UInt64]
    let previousDigests: [UUID: String]
    let previousDirtyCourseIDs: Set<UUID>
    let previousBlockedCourseIDs: Set<UUID>
    let previousOversizedCourseIDs: Set<UUID>
    let previousNeedsBootstrap: Bool
}

@MainActor
extension WorkspaceStore {
    // MARK: - 自 WorkspaceStore.swift 原样搬入(课程可携带状态/课程笔记读写/可携带导出,行为未变)

    @discardableResult
    func exportPortableCourseCopy(
        courseID: UUID,
        to targetRoot: URL
    ) async throws -> URL {
        try await exportPortableCourseCopy(
            courseID: courseID,
            to: targetRoot,
            stageHook: { _ in }
        ).root
    }

    @discardableResult
    func exportPortableCourseCopyForSelfCheck(
        courseID: UUID,
        to targetRoot: URL,
        stageHook: @escaping @Sendable (
            CoursePortableExportStage
        ) throws -> Void = { _ in }
    ) throws -> CoursePortableExportResult {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            try await self.exportPortableCourseCopy(
                courseID: courseID,
                to: targetRoot,
                stageHook: stageHook
            )
        }
    }

    private func exportPortableCourseCopy(
        courseID: UUID,
        to targetRoot: URL,
        stageHook: @escaping @Sendable (
            CoursePortableExportStage
        ) throws -> Void
    ) async throws -> CoursePortableExportResult {
        guard let course = course(withID: courseID),
              let rawRoot = courseRootURL(for: courseID),
              let sourceRoot = try? CourseProjectPathPolicy.existingDirectory(
                  rawRoot
              ),
              let sourceRootIdentity = importedFileIdentityResolver(
                  sourceRoot
              ),
              course.sourceRootIdentity == sourceRootIdentity else {
            throw CourseProjectRootError.unavailableLibrary
        }
        guard !courseHasUnstableState(courseID) else {
            throw CoursePortableExportError.unstableCourseState
        }
        var state = try makeCoursePortableState(
            courseID: courseID,
            revision: coursePortableStateRevisions[courseID] ?? 0,
            savedAt: Date()
        )
        var itemsByID: [String: StudyItem] = [:]
        for item in importedItems {
            guard itemsByID.updateValue(item, forKey: item.id) == nil else {
                throw CoursePortableStateError.duplicateItemID
            }
        }
        var membershipsByItemID: [String: CourseItemMembership] = [:]
        for membership in courseItemMemberships
            where membership.courseID == courseID {
            guard membershipsByItemID.updateValue(
                membership,
                forKey: membership.itemID
            ) == nil else {
                throw CoursePortableStateError.duplicateItemID
            }
        }
        var sharedMaterials: [CoursePortableExportSharedMaterial] = []
        for index in state.items.indices {
            guard case let .sharedReference(
                sharedRelativePath,
                expectedContentDigest
            ) = state.items[index].storage else {
                continue
            }
            let role = CourseOwnedFileRole(portableItem: state.items[index])
            let sharedDirectoryName = sharedRelativePath.split(
                separator: "/"
            ).first.map(String.init)
            let allowedSharedDirectoryNames: Set<String> = role == .note
                ? [role.commonDirectoryName]
                : [role.commonDirectoryName, "共享文稿"]
            guard let expectedContentDigest,
                  let sharedDirectoryName,
                  allowedSharedDirectoryNames.contains(sharedDirectoryName),
                  let item = itemsByID[state.items[index].itemID],
                  let membership =
                    membershipsByItemID[state.items[index].itemID],
                  membership.courseRelativePath
                    == state.items[index].courseRelativePath,
                  case let .common(itemSharedRelativePath) = item.storage,
                  itemSharedRelativePath == sharedRelativePath,
                  item.contentDigest == expectedContentDigest,
                  let sharedURL = item.url,
                  let libraryRoot = courseLibraryRootURL,
                  let expectedSharedURL =
                    CourseProjectPathPolicy.resolvedRelativePath(
                        sharedRelativePath,
                        inside: libraryRoot
                    ),
                  CourseProjectPathPolicy.isSame(
                      expectedSharedURL,
                      sharedURL
                  ),
                  CourseProjectPathPolicy.isSame(
                      expectedSharedURL.deletingLastPathComponent(),
                      libraryRoot.appendingPathComponent(
                          sharedDirectoryName,
                          isDirectory: true
                      )
                      .resolvingSymlinksInPath()
                      .standardizedFileURL
                  ),
                  let linkURL = rawCourseItemURL(
                      relativePath: state.items[index].courseRelativePath,
                      inside: sourceRoot
                  ),
                  let linkIdentity =
                    CourseProjectFileWorker.identity(at: linkURL),
                  CourseProjectFileWorker.isSymbolicLink(at: linkURL),
                  CourseProjectFileWorker.symbolicLink(
                      at: linkURL,
                      pointsTo: sharedURL
                  ) else {
                throw CoursePortableStateError.invalidItemStorage
            }
            let sourceInfo: CourseFileSourceInfo
            do {
                sourceInfo = try await courseProjectFileWorker
                    .validatedRegularSource(sharedURL)
            } catch {
                WeiBeiLog.workspace.error(
                    "code=course_export_source_unavailable stage=validate underlying=\(WeiBeiLog.code(error), privacy: .public) path=\(sharedURL.path, privacy: .private) reason=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
                )
                throw CoursePortableExportError.invalidSourceEntry(
                    path: state.items[index].courseRelativePath,
                    reason: error.localizedDescription
                )
            }
            let sourceSnapshot: CourseFileSnapshot
            do {
                sourceSnapshot = try await courseProjectFileWorker
                    .stableSnapshot(
                        at: sourceInfo.url,
                        expectedIdentity: sourceInfo.identity
                    )
            } catch {
                WeiBeiLog.workspace.error(
                    "code=course_export_source_unavailable stage=snapshot underlying=\(WeiBeiLog.code(error), privacy: .public) path=\(sourceInfo.url.path, privacy: .private) reason=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
                )
                throw CoursePortableExportError.invalidSourceEntry(
                    path: state.items[index].courseRelativePath,
                    reason: error.localizedDescription
                )
            }
            // digest 不一致时仍以磁盘现状导出（S3 静默降级；S6-9 可再收紧日志）。
            _ = expectedContentDigest
            sharedMaterials.append(
                CoursePortableExportSharedMaterial(
                    itemID: item.id,
                    courseRelativePath:
                        state.items[index].courseRelativePath,
                    sharedRelativePath: sharedRelativePath,
                    linkIdentity: linkIdentity,
                    sourceURL: sourceInfo.url,
                    sourceIdentity: sourceInfo.identity,
                    sourceSnapshot: sourceSnapshot
                )
            )
            state.items[index].storage = .courseOwned
        }
        state = try state.validated(expectedCourseID: courseID)
        let sharedDirectory = sharedMaterials.isEmpty
            ? nil
            : courseLibraryRootURL
        if !sharedMaterials.isEmpty, sharedDirectory == nil {
            throw CourseProjectRootError.unavailableLibrary
        }
        return try await courseProjectFileWorker.exportPortableCourse(
            CoursePortableExportRequest(
                courseID: courseID,
                sourceRoot: sourceRoot,
                sourceRootIdentity: sourceRootIdentity,
                sharedDirectory: sharedDirectory,
                targetRoot: targetRoot,
                portableStateData: try encodedCoursePortableState(state),
                requiredRegularRelativePaths: Set(
                    state.items.map(\.courseRelativePath)
                ),
                sharedMaterials: sharedMaterials
            ),
            stageHook: stageHook
        )
    }

    func isolatedCourseNoteOpenDoesNotReadForSelfCheck(
        itemID: String,
        courseID: UUID
    ) -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        courseNoteLoadGenerationByItemID[
            itemID,
            default: 0
        ] &+= 1
        courseNoteLoadTasksByItemID
            .removeValue(forKey: itemID)?
            .cancel()
        loadedCourseNoteTextByItemID.removeValue(
            forKey: itemID
        )
        lastCourseNoteReadRanOnMainThread = nil
        openCourseNote(itemID, in: courseID)
        return activeNotebookItemID == itemID
            && courseNoteLoadTasksByItemID[itemID] == nil
            && loadedCourseNoteTextByItemID[itemID] == nil
            && lastCourseNoteReadRanOnMainThread == nil
    }

    func courseMarkdownRoundTripRunsOffMainForSelfCheck(
        itemID: String,
        markdown: String
    ) throws -> (read: Bool, write: Bool) {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            guard let item = self.importedItems.first(where: {
                $0.id == itemID
            }),
            item.isNotebookNote,
            case .courseOwned = item.storage,
            let url = item.url,
            let identity = item.importedFileIdentity else {
                throw CourseOwnedFileError.verificationFailed
            }
            let read = try await self.courseProjectFileWorker.readMarkdown(
                at: url,
                expectedIdentity: identity
            )
            self.lastCourseNoteReadRanOnMainThread = read.ranOnMainThread
            // S2：写回改为同步原子写（主线程可接受）；读路径仍走后台 worker。
            self.persistCourseOwnedNote(markdown, itemID: itemID)
            self.lastCourseNoteWriteRanOnMainThread = true
            return (!read.ranOnMainThread, true)
        }
    }

    func writeCourseMarkdownForSelfCheck(
        itemID: String,
        markdown: String
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let item = importedItems.first(where: {
            $0.id == itemID
        }),
        item.isNotebookNote,
        case .courseOwned = item.storage else {
            throw CourseOwnedFileError.verificationFailed
        }
        persistCourseOwnedNote(markdown, itemID: itemID)
        if notesByItemID[itemID] != nil {
            // 写回失败留下草稿时，测试侧可观察；成功则 notes 已清除。
            throw CourseOwnedFileError.verificationFailed
        }
    }

    /// 写回失败路径：强制留下 notes 草稿（清 pending），供 C2 验收。
    func leaveCourseNoteDraftAfterFailedWriteForSelfCheck(
        itemID: String,
        markdown: String
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard importedItems.contains(where: {
            $0.id == itemID && $0.isNotebookNote
        }) else {
            throw CourseOwnedFileError.verificationFailed
        }
        setNoteDraft(markdown, for: itemID)
        pendingNoteWritesByItemID.removeValue(forKey: itemID)
        for membership in courseItemMemberships where membership.itemID == itemID {
            dirtyPortableCourseIDs.insert(membership.courseID)
        }
        save()
    }

    func lastSelfWrittenNoteDigestForSelfCheck(itemID: String) -> String? {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return lastSelfWrittenNoteDigestsByItemID[itemID]
    }

    func seedLastSelfWrittenNoteDigestForSelfCheck(
        itemID: String,
        digest: String?
    ) {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        if let digest {
            lastSelfWrittenNoteDigestsByItemID[itemID] = digest
        } else {
            lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: itemID)
        }
    }

    func portableNoteDraftsForSelfCheck(
        courseID: UUID
    ) throws -> [CoursePortableNoteDraft] {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let state = try makeCoursePortableState(
            courseID: courseID,
            revision: coursePortableStateRevisions[courseID] ?? 0,
            savedAt: Date()
        )
        return state.pendingNoteDrafts
    }

    func forcePersistPortableCourseStatesForSelfCheck(
        courseIDs: Set<UUID>
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        for courseID in courseIDs {
            dirtyPortableCourseIDs.insert(courseID)
        }
        _ = try persistCoursePortableStates(
            courseIDs: courseIDs,
            requiring: courseIDs
        )
        save()
    }

    /// 从磁盘再读 course-state 并 apply（验 C2：本地草稿不被清空）。
    func reapplyPortableCourseStateWithoutLocalDraftWipeForSelfCheck(
        courseID: UUID
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard let stateURL = coursePortableStateURL(for: courseID),
              let data = try? Data(contentsOf: stateURL) else {
            throw CourseOwnedFileError.verificationFailed
        }
        let state = try JSONDecoder()
            .decode(CoursePortableState.self, from: data)
            .validated(expectedCourseID: courseID)
        try applyCoursePortableState(state, courseID: courseID)
    }

    func pendingCourseMarkdownDraftForSelfCheck(
        itemID: String
    ) -> String? {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return notesByItemID[itemID]
    }

    func waitForCourseNoteWritesForSelfCheck() throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let deadline = Date(timeIntervalSinceNow: 20)
        while !courseNoteWritesInFlight.isEmpty, Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        guard courseNoteWritesInFlight.isEmpty else {
            throw CourseOwnedFileError.verificationFailed
        }
    }

    func waitForCourseNoteLoadsForSelfCheck() throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let deadline = Date(timeIntervalSinceNow: 20)
        while !courseNoteLoadTasksByItemID.isEmpty, Date() < deadline {
            RunLoop.current.run(
                mode: .default,
                before: Date(timeIntervalSinceNow: 0.01)
            )
        }
        guard courseNoteLoadTasksByItemID.isEmpty else {
            throw CourseOwnedFileError.verificationFailed
        }
    }

    func stagePendingCourseNoteForSelfCheck(
        itemID: String,
        markdown: String
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let item = importedItems.first(where: {
            $0.id == itemID && $0.isNotebookNote
        }) else {
            throw CourseOwnedFileError.verificationFailed
        }
        scheduleNotePersistence(markdown, for: item)
    }

    func discardPendingCourseNoteForSelfCheck(itemID: String) {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        cancelPendingNotePersistence(for: itemID)
        pendingNotePersistenceByItemID.removeValue(forKey: itemID)
    }

    func openCourseNote(_ itemID: String, in requestedCourseID: UUID? = nil) {
        guard importedItems.contains(where: {
            $0.id == itemID && $0.isNotebookNote
        }) else {
            return
        }
        if let requestedCourseID {
            guard itemIsAvailableInCourseContext(itemID: itemID, courseID: requestedCourseID) else {
                return
            }
            activeCourseID = requestedCourseID
        }
        dismissCourseWorkspace(restoringFocus: false)
        showLibrary = false
        select(itemID: itemID)
    }

    @discardableResult
    func createCourseNotebookNote(courseID: UUID, title rawTitle: String) async -> String? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            showTransientNoteStatus(ui("笔记名不能为空。", "Note name cannot be empty."))
            return nil
        }
        let fileStem = safeFileStem(title)
        return await createCourseNotebookNote(
            courseID: courseID,
            title: fileStem,
            markdown: defaultNotebookNote()
        )
    }

    func createCourseNotebookNote(
        courseID: UUID,
        title: String,
        markdown: String,
        revealInWorkspace: Bool = true,
        conflictResolution: CourseFileConflictResolution = .cancel,
        presentsError: Bool = true
    ) async -> String? {
        let data = Data(markdown.utf8)
        do {
            let result = try await transactCourseOwnedFile(
                courseID: courseID,
                role: .note,
                fileName: "\(safeFileStem(title)).md",
                sourceURL: nil,
                sourceIdentity: nil,
                generatedData: data,
                conflictResolution: conflictResolution
            )
            if revealInWorkspace {
                requestNoteSelectionTransition(to: result.item.id) { [weak self] in
                    guard let self else { return }
                    activeNotebookItemID = result.item.id
                    noteText = markdown
                    revealRichWritingSurface()
                    focus(.notes)
                    showTransientNoteStatus(
                        ui(
                            "已在课程“笔记”目录新建：\(result.item.subtitle)",
                            "Created in the course Notes folder: \(result.item.subtitle)"
                        )
                    )
                }
            }
            return result.item.id
        } catch {
            if presentsError {
                recordCourseLibraryUIFailure(
                    error,
                    operation: "create_course_note",
                    path: courseRootURL(for: courseID)
                )
                showImportantOperationError(ui(
                    "课程笔记未完成登记；现有笔记未被覆盖，但课程“笔记”目录可能留有已写入副本。请检查后再重试。",
                    "The course note was not fully registered. Existing notes were not overwritten, but a written copy may remain in the course Notes folder. Check the folder before trying again."
                ))
            }
            return nil
        }
    }

    func createCourseNotebookNoteForSelfCheck(
        courseID: UUID,
        title: String
    ) -> String? {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        do {
            return try waitForCourseFileOperation {
                await self.createCourseNotebookNote(courseID: courseID, title: title)
            }
        } catch {
            return nil
        }
    }

    private func coursePortableStateURL(for courseID: UUID) -> URL? {
        guard let root = courseRootURL(for: courseID),
              let metadata = try? CourseProjectPathPolicy.existingDirectory(
                root.appendingPathComponent(".weibei", isDirectory: true)
              ),
              CourseProjectPathPolicy.contains(root, metadata, includingRoot: false),
              CourseProjectPathPolicy.isSame(
                metadata,
                metadata.resolvingSymlinksInPath()
              ) else {
            return nil
        }
        return metadata.appendingPathComponent(
            "course-state.json",
            isDirectory: false
        )
    }

    func makeCoursePortableState(
        courseID: UUID,
        revision: UInt64,
        savedAt: Date
    ) throws -> CoursePortableState {
        guard let course = course(withID: courseID) else {
            throw CoursePortableStateError.courseIdentityMismatch
        }
        var memberships = courseItemMemberships.filter { $0.courseID == courseID }
        for item in importedItems {
            guard case .courseOwned(let owner, let path) = item.storage,
                  owner == courseID, !path.isEmpty,
                  !memberships.contains(where: { $0.itemID == item.id }) else { continue }
            memberships.append(CourseItemMembership(
                courseID: courseID, itemID: item.id, courseRelativePath: path
            ))
        }
        memberships.sort {
            ($0.courseRelativePath ?? "").localizedStandardCompare(
                $1.courseRelativePath ?? ""
            ) == .orderedAscending
        }
        var portableItems: [CoursePortableItem] = []
        for membership in memberships {
            guard let item = importedItems.first(where: {
                $0.id == membership.itemID
            }) else {
                throw CoursePortableStateError.missingCourseItem
            }
            guard let relativePath = membership.courseRelativePath else {
                // 纯归属兜底登记（链接进课程目录失败时写入）没有课程内链接
                // 条目，可携带状态无法表示；跳过它而不是让整次保存失败。
                if case .common = item.storage { continue }
                throw CoursePortableStateError.missingCourseItem
            }
            let storage: CoursePortableItemStorage
            switch item.storage {
            case .courseOwned(let ownerCourseID, _) where ownerCourseID == courseID:
                storage = .courseOwned
            case let .common(sharedRelativePath):
                storage = .sharedReference(
                    sharedRelativePath: sharedRelativePath,
                    expectedContentDigest: item.contentDigest
                )
            default:
                throw CoursePortableStateError.invalidItemStorage
            }
            portableItems.append(
                CoursePortableItem(
                    itemID: item.id,
                    title: item.title,
                    kind: item.kind,
                    isNotebookNote: item.isNotebookNote,
                    appearsInMaterials: item.appearsInMaterials,
                    courseRelativePath: relativePath,
                    storage: storage,
                    contentRevision: item.contentRevision,
                    contentDigest: item.contentDigest,
                    fileByteCount: item.fileByteCount,
                    fileModificationTimeNanoseconds:
                        item.fileModificationTimeNanoseconds,
                    membershipCreatedAt: membership.createdAt
                )
            )
        }

        let portableItemIDs = Set(portableItems.map(\.itemID))
        let noteItemIDs = Set(
            portableItems.lazy.filter(\.isNotebookNote).map(\.itemID)
        )
        let materialItemIDs = Set(portableItems.lazy.filter(\.isCourseMaterial).map(\.itemID))
        let rawMemoryState = learningMemoryStates.first {
            $0.scope == .course(courseID)
        }
        let memoryIDs = Set(rawMemoryState?.entries.map(\.id) ?? [])
        let relations = noteSourceLinks.filter {
            noteItemIDs.contains($0.noteItemID)
                && materialItemIDs.contains($0.sourceItemID)
        }
        .sorted {
            $0.createdAt == $1.createdAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.createdAt < $1.createdAt
        }
        let relationIDs = Set(relations.map(\.id))
        var relationsByID: [UUID: NoteSourceLink] = [:]
        for relation in relations {
            relationsByID[relation.id] = relation
        }
        let sessions = studySessions.compactMap { current -> StudySession? in
            guard current.courseID == courseID,
                  current.scopeNeedsReview == false else {
                return nil
            }
            var portable = current
            portable.focusItemIDs = portable.focusItemIDs.filter(
                portableItemIDs.contains
            )
            if let materialItemID = portable.materialItemID,
               !materialItemIDs.contains(materialItemID) {
                portable.materialItemID = nil
            }
            for index in portable.messages.indices {
                portable.messages[index].toolTrace = []
                portable.messages[index].sources = portable.messages[index].sources
                    .filter { source in
                        guard let itemID = source.itemID else {
                            return source.courseID.map {
                                $0 == courseID
                            } ?? true
                        }
                        guard portableItemIDs.contains(itemID),
                              source.courseID.map({
                                  $0 == courseID
                              }) ?? true else {
                            return false
                        }
                        switch source.kind {
                        case .material:
                            return materialItemIDs.contains(itemID)
                        case .note:
                            return noteItemIDs.contains(itemID)
                        case .selection:
                            return true
                        }
                    }
                portable.messages[index].actions = portable.messages[index].actions
                    .filter { action in
                        guard action.targetItemID.map(
                            portableItemIDs.contains
                        ) ?? true,
                        action.sourceItemID.map(
                            portableItemIDs.contains
                        ) ?? true else {
                            return false
                        }
                        switch action.kind {
                        case .writeNote:
                            let hasValidTarget = action.targetItemID.map(
                                noteItemIDs.contains
                            ) ?? true
                            return hasValidTarget
                                && action.createdRelationID == nil
                        case .createRelation:
                            let hasValidTarget = action.targetItemID.map(
                                noteItemIDs.contains
                            ) ?? true
                            let hasValidSource = action.sourceItemID.map(
                                    materialItemIDs.contains
                                ) ?? true
                            let hasValidCreatedRelation =
                                action.createdRelationID.map { relationID in
                                    guard relationIDs.contains(relationID),
                                          let relation =
                                            relationsByID[relationID],
                                          let targetItemID =
                                            action.targetItemID,
                                          let sourceItemID =
                                            action.sourceItemID else {
                                        return false
                                    }
                                    return relation.noteItemID
                                        == targetItemID
                                        && relation.sourceItemID
                                            == sourceItemID
                                } ?? true
                            return hasValidTarget
                                && hasValidSource
                                && hasValidCreatedRelation
                        }
                    }
                if var memoryUpdate =
                    portable.messages[index].memoryUpdate {
                    memoryUpdate.memoryIDs = memoryUpdate.memoryIDs.filter(
                        memoryIDs.contains
                    )
                    portable.messages[index].memoryUpdate =
                        memoryUpdate.memoryIDs.isEmpty ? nil : memoryUpdate
                }
                if let origin = portable.messages[index].origin,
                   origin.courseID != courseID
                    || origin.chatID != portable.id {
                    portable.messages[index].origin = nil
                }
            }
            return portable
        }
        .sorted { $0.createdAt < $1.createdAt }
        let messageIDsBySessionID = Dictionary(
            uniqueKeysWithValues: sessions.map {
                ($0.id, Set($0.messages.map(\.id)))
            }
        )
        func sanitizedMemoryProvenance(
            sessionID: UUID?,
            messageID: UUID?
        ) -> (sessionID: UUID?, messageID: UUID?) {
            guard let sessionID,
                  let liveMessageIDs =
                    messageIDsBySessionID[sessionID] else {
                return (nil, nil)
            }
            guard let messageID else {
                return (sessionID, nil)
            }
            return liveMessageIDs.contains(messageID)
                ? (sessionID, messageID)
                : (sessionID, nil)
        }
        var memoryState = rawMemoryState
        if var sanitizedMemoryState = memoryState {
            for entryIndex in sanitizedMemoryState.entries.indices {
                var entry = sanitizedMemoryState.entries[entryIndex]
                let entryProvenance = sanitizedMemoryProvenance(
                    sessionID: entry.sessionID,
                    messageID: entry.messageID
                )
                entry.sessionID = entryProvenance.sessionID
                entry.messageID = entryProvenance.messageID
                if var revisions = entry.revisions {
                    for revisionIndex in revisions.indices {
                        let revisionProvenance =
                            sanitizedMemoryProvenance(
                                sessionID:
                                    revisions[revisionIndex].sessionID,
                                messageID:
                                    revisions[revisionIndex].messageID
                            )
                        revisions[revisionIndex].sessionID =
                            revisionProvenance.sessionID
                        revisions[revisionIndex].messageID =
                            revisionProvenance.messageID
                    }
                    entry.revisions = revisions
                }
                sanitizedMemoryState.entries[entryIndex] = entry
            }
            memoryState = sanitizedMemoryState
        }
        var locations: [String: StudyLocation] = [:]
        for itemID in materialItemIDs.sorted() {
            if let location = studyLocation(for: itemID, in: courseID) {
                var scoped = location
                scoped.itemID = itemID
                locations[itemID] = scoped
            }
        }
        // C2：草稿以 notesByItemID 为准（写回失败会清 pending 但留 notes）；
        // baseline 有 pending 则取，无则 nil。
        let drafts = noteItemIDs.sorted().compactMap {
            itemID -> CoursePortableNoteDraft? in
            guard let markdown = notesByItemID[itemID] else {
                return nil
            }
            return CoursePortableNoteDraft(
                itemID: itemID,
                markdown: markdown,
                baselineContentDigest: nil
            )
        }
        return try CoursePortableState(
            courseID: courseID,
            revision: revision,
            savedAt: savedAt,
            metadata: CoursePortableMetadata(
                title: course.title,
                colorIndex: course.colorIndex,
                createdAt: course.createdAt,
                updatedAt: course.updatedAt
            ),
            items: portableItems,
            studySessions: [],
            learningMemoryState: memoryState,
            courseKnowledgeProfile: courseKnowledgeProfiles.first {
                $0.courseID == courseID
            },
            noteSourceLinks: relations,
            studyLocationsByItemID: locations,
            resumePoint: courseResumePoint(for: courseID),
            pendingNoteDrafts: drafts
        ).validated(expectedCourseID: courseID)
    }

    private func encodedCoursePortableState(
        _ state: CoursePortableState
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    func coursePortableStatePayloadDigest(
        _ state: CoursePortableState
    ) throws -> String {
        var normalized = state
        normalized.revision = 0
        normalized.savedAt = Date(timeIntervalSince1970: 0)
        return Self.noteContentDigest(
            try encodedCoursePortableState(normalized)
        )
    }

    private func readCoursePortableState(
        at url: URL,
        expectedCourseID: UUID
    ) throws -> CoursePortableState {
        guard let directoryIdentity = CourseProjectFileWorker.identity(
            at: url.deletingLastPathComponent()
        ) else {
            throw CoursePortableStateError.unsafeRelativePath
        }
        let data = try CourseProjectFileWorker.readPortableState(
            at: url,
            expectedDirectoryIdentity: directoryIdentity
        )
        return try JSONDecoder()
            .decode(CoursePortableState.self, from: data)
            .validated(expectedCourseID: expectedCourseID)
    }

    @discardableResult
    func restorePortableCourseStates() -> Bool {
        var changed = false
        for courseID in courses.map(\.id) {
            guard let stateURL = coursePortableStateURL(for: courseID) else {
                continue
            }
            guard FileManager.default.fileExists(atPath: stateURL.path) else {
                needsPortableCourseStateBootstrap = true
                if coursePortableStateDigests[courseID] != nil {
                    dirtyPortableCourseIDs.insert(courseID)
                }
                continue
            }
            do {
                let state = try readCoursePortableState(
                    at: stateURL,
                    expectedCourseID: courseID
                )
                let diskDigest = try coursePortableStatePayloadDigest(state)
                try applyCoursePortableState(state, courseID: courseID)
                coursePortableStateRevisions[courseID] = state.revision
                coursePortableStateDigests[courseID] = diskDigest
                dirtyPortableCourseIDs.remove(courseID)
                blockedPortableCourseIDs.remove(courseID)
                oversizedPortableCourseIDs.remove(courseID)
                changed = true
            } catch {
                blockedPortableCourseIDs.insert(courseID)
                dirtyPortableCourseIDs.insert(courseID)
                needsPortableCourseStateBootstrap = true
                reportWorkspaceSaveFailure(.courseStateUnreadable, ui(
                    "“\(course(withID: courseID)?.title ?? "课程")”的课程状态无法读取；课程文件没有被覆盖。请恢复该课程的状态文件或重新连接原课程文件夹后重试。",
                    "The course state for “\(course(withID: courseID)?.title ?? "Course")” could not be read. Course files were not overwritten. Restore that course's state file or reconnect its original folder, then retry."
                ), reason: error.localizedDescription)
                changed = true
            }
        }
        return changed
    }

    private func rawCourseItemURL(
        relativePath: String,
        inside root: URL
    ) -> URL? {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else {
            return nil
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let parent = components.dropLast().reduce(canonicalRoot) {
            $0.appendingPathComponent(String($1), isDirectory: true)
        }
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        guard CourseProjectPathPolicy.contains(
            canonicalRoot,
            resolvedParent,
            includingRoot: true
        ) else {
            return nil
        }
        let candidate = resolvedParent.appendingPathComponent(
            String(components.last!),
            isDirectory: false
        ).standardizedFileURL
        guard CourseProjectPathPolicy.contains(
            canonicalRoot,
            candidate,
            includingRoot: false
        ) else {
            return nil
        }
        return candidate
    }

    private func validatedPortableCourseOwnedFile(
        at candidate: URL,
        portable: CoursePortableItem
    ) throws -> (
        identity: ImportedFileIdentity,
        documentIdentifier: UInt64?
    )? {
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .absent, .presentUnmaterialized:
            return nil
        case .inaccessible:
            throw CoursePortableStateError.unsafeRelativePath
        case .present:
            break
        }
        let values = try candidate.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              !CourseProjectFileWorker.isSymbolicLink(at: candidate),
              CourseProjectPathPolicy.isSame(
                  candidate,
                  candidate.resolvingSymlinksInPath()
              ),
              StudyItemKind.detect(from: candidate) == portable.kind,
              let identity = importedFileIdentityResolver(candidate),
              importedFileIdentityResolver(candidate) == identity else {
            throw CoursePortableStateError.invalidItemStorage
        }
        let documentIdentifier = try candidate.resourceValues(
            forKeys: [.documentIdentifierKey]
        ).documentIdentifier.flatMap {
            $0 >= 0 ? UInt64($0) : nil
        }
        guard importedFileIdentityResolver(candidate) == identity else {
            throw CoursePortableStateError.invalidItemStorage
        }
        return (identity, documentIdentifier)
    }

    private func resolvedSharedPortableFile(
        relativePath: String,
        expectedDigest: String,
        expectedKind: StudyItemKind,
        isNotebookNote: Bool
    ) throws -> (url: URL, identity: ImportedFileIdentity)? {
        guard let libraryRoot = courseLibraryRootURL else {
            return nil
        }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        let role: CourseOwnedFileRole = components.first
            == Substring(CourseLibraryLayout.commonMaterialsDirectoryName)
            || components.first == "共享文稿"
            ? .material
            : .note
        let allowedDirectories: Set<Substring> = role == .note
            ? [Substring(role.commonDirectoryName)]
            : [Substring(role.commonDirectoryName), "共享文稿"]
        guard components.count == 2,
              allowedDirectories.contains(components[0]),
              let candidate = CourseProjectPathPolicy.resolvedRelativePath(
                  relativePath,
                  inside: libraryRoot
              ),
              CourseProjectPathPolicy.isSame(
                  candidate.deletingLastPathComponent(),
                  libraryRoot.appendingPathComponent(
                      String(components[0]),
                      isDirectory: true
                  )
                  .resolvingSymlinksInPath()
                  .standardizedFileURL
              ) else {
            throw CoursePortableStateError.crossCourseReference
        }
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .absent, .presentUnmaterialized:
            return nil
        case .inaccessible:
            throw CoursePortableStateError.crossCourseReference
        case .present:
            break
        }
        let values = try candidate.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              !CourseProjectFileWorker.isSymbolicLink(at: candidate),
              CourseProjectPathPolicy.isSame(
                  candidate,
                  candidate.resolvingSymlinksInPath()
              ),
              StudyItemKind.detect(from: candidate) == expectedKind,
              let identity = importedFileIdentityResolver(candidate) else {
            throw CoursePortableStateError.crossCourseReference
        }
        let snapshot = try CourseProjectFileWorker.snapshotFile(
            at: candidate
        )
        guard snapshot.sha256 == expectedDigest,
              importedFileIdentityResolver(candidate) == identity else {
            return nil
        }
        return (candidate, identity)
    }

    private func validatedPortableSharedLink(
        at candidate: URL,
        sharedURL: URL
    ) throws -> ImportedFileIdentity? {
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .absent, .presentUnmaterialized:
            return nil
        case .inaccessible:
            throw CoursePortableStateError.invalidItemStorage
        case .present:
            break
        }
        guard CourseProjectFileWorker.isSymbolicLink(at: candidate),
              let identity = importedFileIdentityResolver(candidate),
              CourseProjectFileWorker.symbolicLink(
                  at: candidate,
                  pointsTo: sharedURL
              ),
              importedFileIdentityResolver(candidate) == identity else {
            throw CoursePortableStateError.invalidItemStorage
        }
        return identity
    }

    func applyCoursePortableState(
        _ rawState: CoursePortableState,
        courseID: UUID
    ) throws {
        let state = try rawState.validated(expectedCourseID: courseID)
        guard let courseIndex = courses.firstIndex(where: {
            $0.id == courseID
        }),
        let root = courseRootURL(for: courseID) else {
            throw CoursePortableStateError.courseIdentityMismatch
        }

        let previousMemberships = courseItemMemberships.filter {
            $0.courseID == courseID
        }
        let previousItemIDs = Set(previousMemberships.map(\.itemID))
        // 纯归属兜底登记（无课程内链接条目）无法写进可携带状态；重放磁盘
        // 快照时保留这些归属与其共享条目，不随快照一起抹掉。
        let pathlessMemberships = previousMemberships.filter {
            $0.courseRelativePath == nil
        }
        let pathlessItemIDs = Set(pathlessMemberships.map(\.itemID))
        let stateItemIDs = Set(state.items.map(\.itemID))
        let stateRelativePaths = Set(state.items.map(\.courseRelativePath))
        let unlistedOwnedMemberships = previousMemberships.filter {
            membership in
            guard let relativePath = membership.courseRelativePath,
                  !stateItemIDs.contains(membership.itemID),
                  !stateRelativePaths.contains(relativePath),
                  let item = importedItems.first(where: {
                      $0.id == membership.itemID
                  }),
                  case .courseOwned(let ownerCourseID, _) = item.storage else {
                return false
            }
            guard ownerCourseID == courseID else { return false }
            if notesByItemID[membership.itemID] != nil
                || pendingNoteWritesByItemID[membership.itemID] != nil {
                return true
            }
            guard let url = rawCourseItemURL(
                relativePath: relativePath,
                inside: root
            ) else {
                return false
            }
            switch CourseProjectFileWorker.entryPresence(at: url) {
            case .present, .presentUnmaterialized, .inaccessible:
                return true
            case .absent:
                return false
            }
        }
        let retainedLocalItemIDs = pathlessItemIDs.union(
            unlistedOwnedMemberships.map(\.itemID)
        )
        let previousNoteIDs = Set(
            importedItems.lazy.filter {
                previousItemIDs.contains($0.id) && $0.isNotebookNote
            }.map(\.id)
        )
        let retainedLocalNoteIDs = previousNoteIDs.intersection(
            retainedLocalItemIDs
        )
        let otherCourseItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID != courseID
            }.map(\.itemID)
        )
        let previousRelationIDs = Set(
            noteSourceLinks.lazy.filter {
                previousItemIDs.contains($0.noteItemID)
                    && previousItemIDs.contains($0.sourceItemID)
            }.map(\.id)
        )
        let retainedRelationIDs = Set(
            noteSourceLinks.lazy.filter {
                !previousRelationIDs.contains($0.id)
            }.map(\.id)
        )
        guard retainedRelationIDs.isDisjoint(
            with: Set(state.noteSourceLinks.map(\.id))
        ) else {
            throw CoursePortableStateError.invalidRelation
        }

        var restoredItemsByID: [String: StudyItem] = [:]
        var restoredMemberships: [CourseItemMembership] = []
        for portable in state.items {
            guard let candidate = rawCourseItemURL(
                relativePath: portable.courseRelativePath,
                inside: root
            ) else {
                throw CoursePortableStateError.unsafeRelativePath
            }
            let storage: StudyItemStorage
            let itemURL: URL?
            let itemIdentity: ImportedFileIdentity?
            let membershipIdentity: ImportedFileIdentity?
            let membershipDocumentIdentifier: UInt64?
            let preservedExistingShared: StudyItem?
            let existing = importedItems.first {
                $0.id == portable.itemID
            }
            switch portable.storage {
            case .courseOwned:
                storage = .courseOwned(
                    ownerCourseID: courseID,
                    relativePath: portable.courseRelativePath
                )
                preservedExistingShared = nil
                let candidateIdentity =
                    try validatedPortableCourseOwnedFile(
                    at: candidate,
                    portable: portable
                )
                itemIdentity = candidateIdentity?.identity
                membershipIdentity = candidateIdentity?.identity
                membershipDocumentIdentifier =
                    candidateIdentity?.documentIdentifier
                itemURL = itemIdentity == nil ? nil : candidate
            case let .sharedReference(
                sharedRelativePath,
                expectedContentDigest
            ):
                guard let expectedContentDigest else {
                    throw CoursePortableStateError.invalidItemStorage
                }
                storage = .common(relativePath: sharedRelativePath)
                let existingBelongsToKnownCourse = existing.map { item in
                    if case .common = item.storage { return true }
                    return previousItemIDs.contains(item.id)
                        || otherCourseItemIDs.contains(item.id)
                } ?? false
                let existingIsCurrentCanonical: Bool
                if let existing, case let .common(existingPath) = existing.storage,
                   existingPath == sharedRelativePath {
                    existingIsCurrentCanonical = true
                } else if existingBelongsToKnownCourse,
                   let existing,
                   let existingURL = existing.url,
                   let existingIdentity = existing.importedFileIdentity,
                   let existingDigest = existing.contentDigest,
                   let currentCanonical =
                    try? resolvedSharedPortableFile(
                        relativePath: sharedRelativePath,
                        expectedDigest: existingDigest,
                        expectedKind: existing.kind,
                        isNotebookNote: existing.isNotebookNote
                   ),
                   CourseProjectPathPolicy.isSame(
                       currentCanonical.url,
                       existingURL
                   ),
                   currentCanonical.identity == existingIdentity {
                    existingIsCurrentCanonical = true
                } else {
                    existingIsCurrentCanonical = false
                }
                if let existing, existingIsCurrentCanonical {
                    guard case let .common(existingSharedPath) =
                            existing.storage,
                          existingSharedPath == sharedRelativePath else {
                        throw CoursePortableStateError.crossCourseReference
                    }
                    // A shared item is one canonical workspace record used by every course;
                    // a course's older portable snapshot may restore membership but must not
                    // downgrade canonical URL/identity/bookmark/digest/metadata already verified.
                    preservedExistingShared = existing
                    itemURL = existing.url
                    itemIdentity = existing.importedFileIdentity
                } else {
                    preservedExistingShared = nil
                    let resolved = try resolvedSharedPortableFile(
                        relativePath: sharedRelativePath,
                        expectedDigest: expectedContentDigest,
                        expectedKind: portable.kind,
                        isNotebookNote: portable.isNotebookNote
                    )
                    itemURL = resolved?.url
                    itemIdentity = resolved?.identity
                }
                let recordedLibraryRoot = (
                    courseLibraryRootURL
                        ?? courseLibraryRootPath.flatMap {
                            guard $0.hasPrefix("/") else { return nil }
                            return URL(
                                fileURLWithPath: $0,
                                isDirectory: true
                            ).standardizedFileURL
                        }
                )
                if let recordedLibraryRoot {
                    guard let sharedLinkTarget = CourseProjectPathPolicy
                        .resolvedRelativePath(
                            sharedRelativePath,
                            inside: recordedLibraryRoot
                        ) else {
                        throw CoursePortableStateError.invalidItemStorage
                    }
                    membershipIdentity = try validatedPortableSharedLink(
                        at: candidate,
                        sharedURL: sharedLinkTarget
                    )
                } else {
                    membershipIdentity = nil
                }
                membershipDocumentIdentifier = nil
            }
            if let existing,
            !previousItemIDs.contains(existing.id),
            existing.storage != storage {
                throw CoursePortableStateError.crossCourseReference
            }
            restoredItemsByID[portable.itemID] =
                preservedExistingShared
                ?? StudyItem(
                    id: portable.itemID,
                    title: portable.title,
                    subtitle: candidate.lastPathComponent,
                    kind: portable.kind,
                    urlPath: itemURL?.path,
                    importedFileIdentity: itemIdentity,
                    isSample: false,
                    isNotebookNote: portable.isNotebookNote,
                    appearsInMaterials: portable.appearsInMaterials,
                    storage: storage,
                    contentRevision: portable.contentRevision,
                    contentDigest: portable.contentDigest,
                    fileByteCount: portable.fileByteCount,
                    fileModificationTimeNanoseconds:
                        portable.fileModificationTimeNanoseconds
                )
            restoredMemberships.append(
                CourseItemMembership(
                    courseID: courseID,
                    itemID: portable.itemID,
                    courseRelativePath: portable.courseRelativePath,
                    entryIdentity: membershipIdentity,
                    documentIdentifier: membershipDocumentIdentifier,
                    createdAt: portable.membershipCreatedAt
                )
            )
        }

        importedItems.removeAll { item in
            previousItemIDs.contains(item.id)
                && !otherCourseItemIDs.contains(item.id)
                && !retainedLocalItemIDs.contains(item.id)
        }
        for item in restoredItemsByID.values.sorted(by: {
            $0.id < $1.id
        }) {
            if let existingIndex = importedItems.firstIndex(where: {
                $0.id == item.id
            }) {
                importedItems[existingIndex] = item
            } else {
                importedItems.append(item)
            }
        }
        courseItemMemberships.removeAll { $0.courseID == courseID }
        courseItemMemberships.append(contentsOf: restoredMemberships)
        for membership in pathlessMemberships + unlistedOwnedMemberships
        where !restoredMemberships.contains(where: {
            $0.itemID == membership.itemID
        }) {
            courseItemMemberships.append(membership)
        }

        var restoredCourse = courses[courseIndex]
        restoredCourse.title = state.metadata.title
        restoredCourse.colorIndex = state.metadata.colorIndex
        restoredCourse.createdAt = state.metadata.createdAt
        restoredCourse.updatedAt = state.metadata.updatedAt
        courses[courseIndex] = restoredCourse

        if state.schemaVersion == 1 {
            for var legacySession in state.studySessions {
                if let index = studySessions.firstIndex(where: {
                    $0.id == legacySession.id
                }) {
                    let related = Set(studySessions[index].relatedCourseIDs)
                        .union(legacySession.relatedCourseIDs)
                        .union([courseID])
                    studySessions[index].relatedCourseIDs = related.sorted {
                        $0.uuidString < $1.uuidString
                    }
                    if studySessions[index].messages.isEmpty,
                       !legacySession.messages.isEmpty {
                        studySessions[index].messages = legacySession.messages
                        studySessions[index].messageCount =
                            legacySession.messages.count
                    }
                    markStudySessionMessagesLoaded(legacySession.id)
                } else {
                    legacySession.relatedCourseIDs = Set(
                        legacySession.relatedCourseIDs + [courseID]
                    ).sorted { $0.uuidString < $1.uuidString }
                    studySessions.append(legacySession)
                    markStudySessionMessagesLoaded(legacySession.id)
                }
            }
        }
        if let chatID = state.resumePoint?.chatID,
           let index = studySessions.firstIndex(where: { $0.id == chatID }),
           !studySessions[index].relatedCourseIDs.contains(courseID) {
            studySessions[index].relatedCourseIDs.append(courseID)
            studySessions[index].relatedCourseIDs.sort {
                $0.uuidString < $1.uuidString
            }
        }
        if let activeStudySessionID,
           let active = studySessions.first(where: {
               $0.id == activeStudySessionID
           }) {
            messages = active.messages
        }

        learningMemoryStates.removeAll {
            $0.scope == .course(courseID)
        }
        if let memoryState = state.learningMemoryState {
            learningMemoryStates.append(memoryState)
        }
        courseKnowledgeProfiles.removeAll { $0.courseID == courseID }
        courseKnowledgeProfiles.append(
            state.courseKnowledgeProfile ?? CourseKnowledgeProfile(courseID: courseID)
        )

        noteSourceLinks.removeAll {
            previousRelationIDs.contains($0.id)
        }
        noteSourceLinks.append(contentsOf: state.noteSourceLinks)
        studyLocationsByCourseID[courseID.uuidString] =
            state.studyLocationsByItemID
        if !courseResumePoints.contains(where: { $0.courseID == courseID }),
           let resumePoint = state.resumePoint {
            courseResumePoints.append(resumePoint)
        }

        let restoredNoteIDs = Set(
            state.items.lazy.filter(\.isNotebookNote).map(\.itemID)
        )
        // C2：本地有草稿的条目一律保留——未落盘输入永远优先于快照重放。
        for itemID in previousNoteIDs.union(restoredNoteIDs) {
            if notesByItemID[itemID] != nil
                || retainedLocalNoteIDs.contains(itemID) {
                continue
            }
            setNoteDraft(nil, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
            lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: itemID)
        }
        for item in state.items where item.isNotebookNote {
            // 本地草稿笔记：不覆盖其备份基线；其余用 state 内容 digest 回填。
            if notesByItemID[item.itemID] != nil {
                continue
            }
            noteBackingContentDigestsByItemID[item.itemID] =
                item.contentDigest
            if let digest = item.contentDigest {
                lastSelfWrittenNoteDigestsByItemID[item.itemID] = digest
            }
        }
        for draft in state.pendingNoteDrafts {
            // state 中的 draft 仅在本地无草稿时回填。
            if notesByItemID[draft.itemID] != nil {
                continue
            }
            setNoteDraft(draft.markdown, for: draft.itemID)
            pendingNoteWritesByItemID[draft.itemID] =
                PendingNoteWriteState()
        }
        rebuildCourseMembershipsFromStorage()
        refreshRuntimeItemURLs()
    }

    @discardableResult
    private func persistCoursePortableStates(
        courseIDs requestedCourseIDs: Set<UUID>? = nil,
        requiring requiredCourseIDs: Set<UUID> = []
    ) throws -> CoursePortableStateCommit {
        let courseIDs = requestedCourseIDs ?? Set(courses.map(\.id))
        let previousRevisions = coursePortableStateRevisions
        let previousDigests = coursePortableStateDigests
        let previousDirty = dirtyPortableCourseIDs
        let previousBlocked = blockedPortableCourseIDs
        let previousOversized = oversizedPortableCourseIDs
        let previousNeedsBootstrap = needsPortableCourseStateBootstrap
        var committedWrites: [CoursePortableStateWriteRecord] = []
        var conflictedCourseIDs = Set<UUID>()
        var durablePortableCourseIDs = Set<UUID>()
        do {
            for courseID in courses.map(\.id)
            where courseIDs.contains(courseID) {
                let currentRevision =
                    coursePortableStateRevisions[courseID] ?? 0
                let knownRevision =
                    coursePortableStateRevisions[courseID]
                let knownDigest = coursePortableStateDigests[courseID]
                let stateURL = coursePortableStateURL(for: courseID)
                let hasPortableHistory =
                    knownRevision != nil
                    || knownDigest != nil
                    || dirtyPortableCourseIDs.contains(courseID)
                    || blockedPortableCourseIDs.contains(courseID)
                guard stateURL != nil || hasPortableHistory else {
                    // Legacy courses without a real project root remain valid
                    // workspace-only records until the user explicitly moves
                    // their files into a course folder.
                    continue
                }
                let candidate: CoursePortableState
                do {
                    candidate = try makeCoursePortableState(
                        courseID: courseID,
                        revision: currentRevision,
                        savedAt: Date(timeIntervalSince1970: 0)
                    )
                } catch {
                    let awaitsLegacyOrganization =
                        courseItemMemberships.contains { membership in
                            guard membership.courseID == courseID,
                                  let item = importedItems.first(where: {
                                      $0.id == membership.itemID
                                  }) else {
                                return false
                            }
                            return item.storage == .common(relativePath: "")
                        }
                    if awaitsLegacyOrganization {
                        continue
                    }
                    guard stateURL == nil, hasPortableHistory else {
                        throw error
                    }
                    // A previously portable course may be temporarily offline.
                    // Preserve its workspace snapshot and conflict state instead
                    // of letting an unavailable root block every workspace save.
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.insert(courseID)
                    continue
                }
                var committed = candidate
                committed.revision = currentRevision &+ 1
                committed.savedAt = Date()
                let committedData = try encodedCoursePortableState(
                    committed
                )
                if committedData.count
                    > CourseProjectFileWorker
                        .portableStateMaximumByteCount {
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.insert(courseID)
                    oversizedPortableCourseIDs.insert(courseID)
                    needsPortableCourseStateBootstrap = true
                    continue
                }
                let payloadDigest = try coursePortableStatePayloadDigest(
                    candidate
                )
                guard let stateURL else {
                    oversizedPortableCourseIDs.remove(courseID)
                    if knownDigest != payloadDigest {
                        dirtyPortableCourseIDs.insert(courseID)
                    }
                    continue
                }
                let stateExists = FileManager.default.fileExists(
                    atPath: stateURL.path
                )
                guard let directoryIdentity =
                        CourseProjectFileWorker.identity(
                            at: stateURL.deletingLastPathComponent()
                        ) else {
                    throw CoursePortableStateError.unsafeRelativePath
                }
                if oversizedPortableCourseIDs.remove(courseID) != nil {
                    blockedPortableCourseIDs.remove(courseID)
                }
                if blockedPortableCourseIDs.contains(courseID) {
                    if knownDigest != payloadDigest {
                        dirtyPortableCourseIDs.insert(courseID)
                    }
                    continue
                }
                if knownDigest == payloadDigest, stateExists {
                    if requiredCourseIDs.contains(courseID) {
                        guard let diskState = try? readCoursePortableState(
                            at: stateURL, expectedCourseID: courseID
                        ),
                        diskState.revision == currentRevision,
                        (try? coursePortableStatePayloadDigest(diskState)) == knownDigest else {
                            dirtyPortableCourseIDs.insert(courseID)
                            blockedPortableCourseIDs.insert(courseID)
                            continue
                        }
                    }
                    dirtyPortableCourseIDs.remove(courseID)
                    durablePortableCourseIDs.insert(courseID)
                    continue
                }
                if stateExists {
                    guard let knownDigest,
                          let diskState = try? readCoursePortableState(
                              at: stateURL,
                              expectedCourseID: courseID
                          ),
                          diskState.revision == currentRevision,
                          (try? coursePortableStatePayloadDigest(
                              diskState
                          )) == knownDigest else {
                        dirtyPortableCourseIDs.insert(courseID)
                        blockedPortableCourseIDs.insert(courseID)
                        continue
                    }
                }
                let previousData = stateExists
                    ? try CourseProjectFileWorker.readPortableState(
                        at: stateURL,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                    : nil
                do {
                    try coursePortableStateWriter(
                        committedData,
                        stateURL,
                        directoryIdentity,
                        previousData,
                        {
                            try courseProjectMutationHook(
                                .beforeCoursePortableStateCASPlacement
                            )
                        }
                    )
                    let verified = try readCoursePortableState(
                        at: stateURL,
                        expectedCourseID: courseID
                    )
                    guard verified.revision == committed.revision,
                          try coursePortableStatePayloadDigest(verified)
                            == payloadDigest else {
                        throw CoursePortableStateError
                            .writeVerificationFailed
                    }
                } catch CourseProjectFileWorkerError.contentConflict {
                    // S3：写冲突静默记入 conflicted/dirty/blocked，不抛拒绝。
                    conflictedCourseIDs.insert(courseID)
                    dirtyPortableCourseIDs.insert(courseID)
                    blockedPortableCourseIDs.insert(courseID)
                    needsPortableCourseStateBootstrap = true
                    continue
                } catch {
                    try restorePortableStateFile(
                        at: stateURL,
                        previousData: previousData,
                        attemptedData: committedData,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                    throw error
                }
                committedWrites.append(
                    CoursePortableStateWriteRecord(
                        url: stateURL,
                        previousData: previousData,
                        committedData: committedData,
                        expectedDirectoryIdentity: directoryIdentity
                    )
                )
                coursePortableStateRevisions[courseID] =
                    committed.revision
                coursePortableStateDigests[courseID] = payloadDigest
                dirtyPortableCourseIDs.remove(courseID)
                durablePortableCourseIDs.insert(courseID)
            }
            let unresolvedRequiredCourseIDs = requiredCourseIDs.subtracting(durablePortableCourseIDs)
            if !unresolvedRequiredCourseIDs.isEmpty {
                // S3：未完成的可携带写回静默记 dirty/blocked，不抛拒绝。
                conflictedCourseIDs.formUnion(
                    unresolvedRequiredCourseIDs
                        .intersection(blockedPortableCourseIDs)
                        .subtracting(oversizedPortableCourseIDs)
                )
                dirtyPortableCourseIDs.formUnion(unresolvedRequiredCourseIDs)
                blockedPortableCourseIDs.formUnion(unresolvedRequiredCourseIDs)
                needsPortableCourseStateBootstrap = true
            }
        } catch {
            var rollbackFailed = false
            for write in committedWrites.reversed() {
                do {
                    try restorePortableStateFile(
                        at: write.url,
                        previousData: write.previousData,
                        attemptedData: write.committedData,
                        expectedDirectoryIdentity:
                            write.expectedDirectoryIdentity
                    )
                } catch {
                    rollbackFailed = true
                }
            }
            coursePortableStateRevisions = previousRevisions
            coursePortableStateDigests = previousDigests
            dirtyPortableCourseIDs = previousDirty
            blockedPortableCourseIDs = previousBlocked
            oversizedPortableCourseIDs = previousOversized
            needsPortableCourseStateBootstrap = previousNeedsBootstrap
            if !conflictedCourseIDs.isEmpty {
                dirtyPortableCourseIDs.formUnion(conflictedCourseIDs)
                blockedPortableCourseIDs.formUnion(conflictedCourseIDs)
                needsPortableCourseStateBootstrap = true
            }
            if rollbackFailed {
                dirtyPortableCourseIDs.formUnion(conflictedCourseIDs)
                blockedPortableCourseIDs.formUnion(conflictedCourseIDs)
                needsPortableCourseStateBootstrap = true
            }
            // 写回失败时保留磁盘状态与本机候选，不覆盖任一边。
            if !conflictedCourseIDs.isEmpty {
                needsPortableCourseStateBootstrap = true
            }
            return CoursePortableStateCommit(
                writes: [],
                previousRevisions: previousRevisions,
                previousDigests: previousDigests,
                previousDirtyCourseIDs: previousDirty,
                previousBlockedCourseIDs: previousBlocked,
                previousOversizedCourseIDs: previousOversized,
                previousNeedsBootstrap: previousNeedsBootstrap
            )
        }
        needsPortableCourseStateBootstrap =
            !dirtyPortableCourseIDs.isEmpty
        return CoursePortableStateCommit(
            writes: committedWrites,
            previousRevisions: previousRevisions,
            previousDigests: previousDigests,
            previousDirtyCourseIDs: previousDirty,
            previousBlockedCourseIDs: previousBlocked,
            previousOversizedCourseIDs: previousOversized,
            previousNeedsBootstrap: previousNeedsBootstrap
        )
    }

    private func rollbackCoursePortableStateCommit(
        _ commit: CoursePortableStateCommit
    ) throws {
        var rollbackFailed = false
        for write in commit.writes.reversed() {
            do {
                try restorePortableStateFile(
                    at: write.url,
                    previousData: write.previousData,
                    attemptedData: write.committedData,
                    expectedDirectoryIdentity:
                        write.expectedDirectoryIdentity
                )
            } catch {
                rollbackFailed = true
            }
        }
        coursePortableStateRevisions = commit.previousRevisions
        coursePortableStateDigests = commit.previousDigests
        dirtyPortableCourseIDs = commit.previousDirtyCourseIDs
        blockedPortableCourseIDs = commit.previousBlockedCourseIDs
        oversizedPortableCourseIDs =
            commit.previousOversizedCourseIDs
        needsPortableCourseStateBootstrap =
            commit.previousNeedsBootstrap
        if rollbackFailed {
            // S3：回滚失败仅保留 blocked 标记，不抛拒绝。
            dirtyPortableCourseIDs.formUnion(commit.previousDirtyCourseIDs)
            blockedPortableCourseIDs.formUnion(commit.previousBlockedCourseIDs)
            needsPortableCourseStateBootstrap = true
        }
    }

    private func restorePortableStateFile(
        at url: URL,
        previousData: Data?,
        attemptedData: Data,
        expectedDirectoryIdentity: ImportedFileIdentity
    ) throws {
        try CourseProjectFileWorker.restorePortableState(
            at: url,
            previousData: previousData,
            attemptedData: attemptedData,
            expectedDirectoryIdentity: expectedDirectoryIdentity
        )
    }

}
