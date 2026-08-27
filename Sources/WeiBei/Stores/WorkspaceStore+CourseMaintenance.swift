import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    // MARK: - 自 WorkspaceStore.swift 原样搬入(课程文件维护/对账,行为未变)

    @discardableResult
    func resolveCourseOwnedItems(for courseID: UUID) -> Bool {
        var changed = false
        let itemIDs = importedItems.compactMap { item -> String? in
            guard case .courseOwned(let ownerCourseID, _) = item.storage,
                  ownerCourseID == courseID else {
                return nil
            }
            return item.id
        }
        for itemID in itemIDs {
            guard let index = importedItems.firstIndex(where: { $0.id == itemID }) else {
                continue
            }
            if resolveCourseOwnedFile(
                at: index,
                ownerCourseID: courseID
            ).changed {
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    func reconcileCourseFilesNow(
        courseID requestedCourseID: UUID? = nil,
        persistsChanges: Bool = true
    ) async -> Bool {
        guard !courseReconciliationInFlight else { return false }
        guard !libraryMigrationInFlight else { return false }
        courseReconciliationInFlight = true
        defer { courseReconciliationInFlight = false }
        var succeeded = true
        if let libraryRoot = courseLibraryRootURL {
            try? await ensureCommonContentDirectories(at: libraryRoot)
            discoverTopLevelCourseFolders()
        }
        if await reconcileSharedFilesNow() {
            if persistsChanges, !(await persistWorkspaceNow()) {
                succeeded = false
            }
            courseDocumentSearchIndex.synchronize(allItems)
            invalidateAgentContext()
        }
        let courseIDs = requestedCourseID.map { [$0] } ?? courses.map(\.id)
        for courseID in courseIDs {
            guard activeCourseRemovalTokens[courseID] == nil,
                  courses.contains(where: { $0.id == courseID }),
                  let root = courseRootURL(for: courseID) else {
                succeeded = false
                continue
            }
            do {
                let snapshot = try await courseProjectFileWorker.scanCourse(at: root)
                guard activeCourseRemovalTokens[courseID] == nil,
                      courses.contains(where: { $0.id == courseID }),
                      courseRootURL(for: courseID) == root else {
                    succeeded = false
                    continue
                }
                var changed = await applyCourseFileObservations(
                    snapshot,
                    courseID: courseID,
                    root: root
                )
                if let libraryRoot = courseLibraryRootURL {
                    for directoryName in [
                        CourseOwnedFileRole.material.commonDirectoryName,
                        CourseOwnedFileRole.note.commonDirectoryName,
                        "共享文稿",
                    ] {
                        let sharedDirectory = libraryRoot.appendingPathComponent(
                            directoryName,
                            isDirectory: true
                        )
                        guard FileManager.default.fileExists(
                            atPath: sharedDirectory.path
                        ) else { continue }
                        let sharedObservations = try await courseProjectFileWorker.scanSharedLinks(
                            at: root,
                            sharedDirectory: sharedDirectory
                        )
                        if applySharedLinkObservations(
                            sharedObservations,
                            courseID: courseID,
                            libraryRoot: libraryRoot,
                            courseRoot: root
                        ) {
                            changed = true
                        }
                    }
                }
                if changed {
                    if persistsChanges, !(await persistWorkspaceNow()) {
                        succeeded = false
                    }
                    courseDocumentSearchIndex.synchronize(allItems)
                    invalidateAgentContext()
                }
            } catch {
                succeeded = false
                recordCourseLibraryUIFailure(
                    error,
                    operation: "reconcile_course_folder",
                    path: root
                )
                courseRootUnavailableReasons[courseID] = ui(
                    "课程文件夹暂时无法对账；磁盘内容没有被覆盖。请确认文件夹可访问后重试。",
                    "The course folder could not be reconciled. Disk content was not overwritten. Make sure the folder is accessible, then try again."
                )
                if let expectedIdentity = course(withID: courseID)?.sourceRootIdentity,
                   importedFileIdentityResolver(root) != expectedIdentity {
                    cancelAgentRequestIfRunning(in: courseID)
                }
            }
        }
        refreshCourseFileWatchers()
        return succeeded
    }

    func reconcileCourseFilesForSelfCheck(courseID: UUID? = nil) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        try waitForCourseFileOperation {
            _ = await self.reconcileCourseFilesNow(courseID: courseID)
        }
    }

    func courseReconciliationLookupCountForSelfCheck() -> Int {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return lastCourseReconciliationLookupCount
    }

    private func reconcileSharedFilesNow() async -> Bool {
        guard let libraryRoot = courseLibraryRootURL else { return false }
        var changed = false
        for (directoryName, isNote) in [
            (CourseOwnedFileRole.material.commonDirectoryName, false),
            (CourseOwnedFileRole.note.commonDirectoryName, true),
            ("共享文稿", false),
        ] {
            if await reconcileSharedFilesNow(
                libraryRoot: libraryRoot,
                directoryName: directoryName,
                isNote: isNote
            ) {
                changed = true
            }
        }
        return changed
    }

    func ensureCommonContentDirectories(at libraryRoot: URL) async throws {
        for role in [CourseOwnedFileRole.material, .note] {
            _ = try await courseProjectFileWorker.ensureRealDirectory(
                libraryRoot.appendingPathComponent(
                    role.commonDirectoryName,
                    isDirectory: true
                ),
                inside: libraryRoot
            )
        }
    }

    func migrateLegacySharedMaterials(
        in libraryRoot: URL
    ) async -> Bool {
        let oldDirectory = libraryRoot.appendingPathComponent(
            "共享文稿",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: oldDirectory.path) else {
            return false
        }
        let newDirectory = libraryRoot.appendingPathComponent(
            CourseOwnedFileRole.material.commonDirectoryName,
            isDirectory: true
        )
        var changed = false
        for index in importedItems.indices {
            guard case .common(let relativePath) = importedItems[index].storage,
                  relativePath.hasPrefix("共享文稿/"),
                  let oldURL = CourseProjectPathPolicy.resolvedRelativePath(
                    relativePath,
                    inside: libraryRoot
                  ),
                  importedFileIdentityResolver(oldURL)
                    == importedItems[index].importedFileIdentity else {
                continue
            }
            let newURL = newDirectory.appendingPathComponent(
                oldURL.lastPathComponent
            )
            guard !FileManager.default.fileExists(atPath: newURL.path) else {
                showTransientNoteStatus(ui(
                    "通用资料中已有同名文件“\(newURL.lastPathComponent)”，旧共享文稿已保留。",
                    "A same-named common material already exists. The legacy shared file was kept."
                ))
                continue
            }
            guard CourseProjectFileWorker.renameWithoutReplacement(
                from: oldURL,
                to: newURL
            ) else {
                continue
            }
            for membership in courseItemMemberships
            where membership.itemID == importedItems[index].id {
                guard let root = courseRootURL(for: membership.courseID),
                      let relativePath = membership.courseRelativePath,
                      let linkIdentity = membership.entryIdentity,
                      let linkURL = Self.backgroundRawRelativeURL(
                        relativePath,
                        inside: root
                      ) else {
                    continue
                }
                do {
                    try await courseProjectFileWorker.repairSharedLink(
                        at: linkURL,
                        courseRoot: root,
                        from: oldURL,
                        to: newURL,
                        expectedLinkIdentity: linkIdentity
                    )
                } catch {
                    recordCourseLibraryUIFailure(
                        error,
                        operation: "repair_migrated_shared_link",
                        path: linkURL
                    )
                    courseRootUnavailableReasons[membership.courseID] = ui(
                        "通用资料已迁移并保留，但这门课程的入口暂时无法修复。请确认课程文件夹可访问后重试。",
                        "The common material was moved and preserved, but this course entry could not be repaired. Make sure the course folder is accessible, then try again."
                    )
                }
            }
            importedItems[index].storage = .common(
                relativePath:
                    "\(CourseOwnedFileRole.material.commonDirectoryName)/\(newURL.lastPathComponent)"
            )
            importedItems[index].urlPath = newURL.path
            changed = true
        }
        if (try? FileManager.default.contentsOfDirectory(
            atPath: oldDirectory.path
        ).isEmpty) == true {
            try? FileManager.default.removeItem(at: oldDirectory)
        }
        return changed
    }

    private func reconcileSharedFilesNow(
        libraryRoot: URL,
        directoryName: String,
        isNote: Bool
    ) async -> Bool {
        let sharedDirectory = libraryRoot.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: sharedDirectory.path),
              let snapshot = try? await courseProjectFileWorker
                .scanSharedOriginals(
                    at: sharedDirectory,
                    isNote: isNote
                ) else {
            return false
        }
        var changed = false
        var itemIndexByID: [String: Int] = [:]
        for index in importedItems.indices {
            if case .common(let relativePath) = importedItems[index].storage,
               relativePath.hasPrefix("\(directoryName)/") {
                itemIndexByID[importedItems[index].id] = index
            }
        }
        let itemIDs = itemIndexByID.keys.sorted()
        let courseRootsByID = Dictionary(
            uniqueKeysWithValues: courses.compactMap { course in
                courseRootURL(for: course.id).map { (course.id, $0) }
            }
        )
        var sharedMembershipsByItemID: [
            String: [CourseItemMembership]
        ] = [:]
        for membership in courseItemMemberships
        where itemIndexByID[membership.itemID] != nil {
            sharedMembershipsByItemID[
                membership.itemID,
                default: []
            ].append(membership)
        }
        var consumedObservationIndexes = Set<Int>()
        var observationIndexByItemID: [String: Int] = [:]

        for itemID in itemIDs {
            guard let itemIndex = itemIndexByID[itemID],
                  case .common(let relativePath) = importedItems[itemIndex].storage,
                  relativePath.hasPrefix("\(directoryName)/") else {
                continue
            }
            let fileName = String(
                relativePath.dropFirst(directoryName.count + 1)
            )
            guard !fileName.contains("/"),
                  let observationIndex = snapshot.indexByRelativePath[fileName],
                  consumedObservationIndexes.insert(observationIndex).inserted else {
                continue
            }
            observationIndexByItemID[itemID] = observationIndex
        }

        func firstUnconsumed(_ indexes: [Int]?) -> Int? {
            guard let indexes else { return nil }
            for index in indexes
            where consumedObservationIndexes.insert(index).inserted {
                return index
            }
            return nil
        }

        for itemID in itemIDs where observationIndexByItemID[itemID] == nil {
            guard let itemIndex = itemIndexByID[itemID],
                  let identity = importedItems[itemIndex].importedFileIdentity,
                  let observationIndex = firstUnconsumed(
                    snapshot.indexesByIdentity[identity]
                  ) else {
                continue
            }
            observationIndexByItemID[itemID] = observationIndex
        }

        var goneSharedIDs: [String] = []
        for itemID in itemIDs {
            guard let itemIndex = itemIndexByID[itemID],
                  let observationIndex = observationIndexByItemID[itemID] else {
                if itemIndexByID[itemID] != nil {
                    goneSharedIDs.append(itemID)
                }
                continue
            }
            let observation = snapshot.observations[observationIndex]
            let previous = importedItems[itemIndex]
            if let oldURL = previous.url,
               !CourseProjectPathPolicy.isSame(oldURL, observation.url),
               previous.importedFileIdentity == observation.identity {
                for membership in sharedMembershipsByItemID[itemID] ?? [] {
                    guard let courseRoot =
                            courseRootsByID[membership.courseID],
                          let relativePath =
                            membership.courseRelativePath,
                          let linkIdentity = membership.entryIdentity,
                          let linkURL = Self.backgroundRawRelativeURL(
                            relativePath,
                            inside: courseRoot
                          ) else {
                        continue
                    }
                    do {
                        try courseProjectMutationHook(
                            .beforeSharedLinkRepair
                        )
                        try await courseProjectFileWorker.repairSharedLink(
                            at: linkURL,
                            courseRoot: courseRoot,
                            from: oldURL,
                            to: observation.url,
                            expectedLinkIdentity: linkIdentity
                        )
                    } catch {
                        recordCourseLibraryUIFailure(
                            error,
                            operation: "repair_renamed_shared_link",
                            path: linkURL
                        )
                        courseRootUnavailableReasons[
                            membership.courseID
                        ] = ui(
                            "共享原件已改名并保留，但这门课程的入口暂时无法修复。请确认课程文件夹可访问后重试。",
                            "The shared original was renamed and preserved, but this course entry could not be repaired. Make sure the course folder is accessible, then try again."
                        )
                    }
                }
            }
            do {
                let identityChanged =
                    previous.importedFileIdentity != observation.identity
                let metadataChanged = previous.fileByteCount != nil
                    && previous.fileModificationTimeNanoseconds != nil
                    && (previous.fileByteCount != observation.byteCount
                        || previous.fileModificationTimeNanoseconds
                            != observation.modificationTimeNanoseconds)
                var digest = previous.contentDigest
                var revision = previous.contentRevision
                if identityChanged || metadataChanged {
                    let fileSnapshot = try await courseProjectFileWorker.snapshot(
                        at: observation.url
                    )
                    if identityChanged || digest != fileSnapshot.sha256 {
                        revision &+= 1
                    }
                    digest = fileSnapshot.sha256
                }
                var nextItem = previous
                nextItem.title =
                    observation.url.deletingPathExtension().lastPathComponent
                nextItem.subtitle = observation.url.lastPathComponent
                nextItem.kind = StudyItemKind.detect(from: observation.url)
                nextItem.urlPath = observation.url.path
                nextItem.importedFileIdentity = observation.identity
                nextItem.storage = .common(
                    relativePath:
                        "\(directoryName)/\(observation.relativePath)"
                )
                nextItem.isNotebookNote = isNote || nextItem.kind == .markdown
                nextItem.appearsInMaterials = nextItem.appearsInMaterials ?? !isNote
                nextItem.contentRevision = revision
                nextItem.contentDigest = digest
                nextItem.fileByteCount = observation.byteCount
                nextItem.fileModificationTimeNanoseconds =
                    observation.modificationTimeNanoseconds
                if nextItem != previous {
                    importedItems[itemIndex] = nextItem
                    changed = true
                }
            } catch {
                if keepUnavailableImportedItem(at: itemIndex).changed {
                    changed = true
                }
            }
        }
        if forgetGoneImportedItems(ids: goneSharedIDs) {
            changed = true
        }
        for (observationIndex, observation) in snapshot.observations.enumerated()
        where !consumedObservationIndexes.contains(observationIndex) {
            importedItems.append(
                StudyItem(
                    id: Self.makeImportedItemID(),
                    title:
                        observation.url.deletingPathExtension().lastPathComponent,
                    subtitle: observation.url.lastPathComponent,
                    kind: StudyItemKind.detect(from: observation.url),
                    urlPath: observation.url.path,
                    importedFileIdentity: observation.identity,
                    isSample: false,
                    isNotebookNote: isNote || StudyItemKind.detect(from: observation.url) == .markdown,
                    appearsInMaterials: !isNote,
                    storage: .common(
                        relativePath:
                            "\(directoryName)/\(observation.relativePath)"
                    ),
                    contentRevision: 1,
                    contentDigest: nil,
                    fileByteCount: observation.byteCount,
                    fileModificationTimeNanoseconds:
                        observation.modificationTimeNanoseconds
                )
            )
            changed = true
        }
        return changed
    }

    private func applySharedLinkObservations(
        _ observations: [CourseSharedLinkObservation],
        courseID: UUID,
        libraryRoot: URL,
        courseRoot: URL
    ) -> Bool {
        var itemIDByIdentity: [ImportedFileIdentity: String] = [:]
        var itemIDByPath: [String: String] = [:]
        var sharedItemIDs = Set<String>()
        for item in importedItems {
            guard case .common(let relativePath) = item.storage,
                  let expectedURL = CourseProjectPathPolicy.resolvedRelativePath(
                    relativePath,
                    inside: libraryRoot
                  ) else {
                continue
            }
            sharedItemIDs.insert(item.id)
            itemIDByPath[expectedURL.standardizedFileURL.path] = item.id
            if let identity = item.importedFileIdentity {
                itemIDByIdentity[identity] = item.id
            }
        }
        let observationItemIDs: [String?] = observations.map {
            itemIDByPath[$0.sharedURL.standardizedFileURL.path]
                ?? itemIDByIdentity[$0.sharedIdentity]
        }
        var observationIndexesByItemID: [String: [Int]] = [:]
        var observationIndexByLinkIdentity: [ImportedFileIdentity: Int] = [:]
        var observationIndexByRelativePath: [String: Int] = [:]
        for index in observations.indices {
            guard let itemID = observationItemIDs[index] else { continue }
            observationIndexesByItemID[itemID, default: []].append(index)
            observationIndexByLinkIdentity[
                observations[index].linkIdentity
            ] = index
            observationIndexByRelativePath[
                observations[index].relativePath
            ] = index
        }
        var nextCandidateOffsetByItemID: [String: Int] = [:]
        var consumedObservationIndexes = Set<Int>()
        func firstUnconsumed(for itemID: String) -> Int? {
            guard let indexes = observationIndexesByItemID[itemID] else {
                return nil
            }
            var offset = nextCandidateOffsetByItemID[itemID] ?? 0
            while offset < indexes.count {
                let index = indexes[offset]
                offset += 1
                if consumedObservationIndexes.insert(index).inserted {
                    nextCandidateOffsetByItemID[itemID] = offset
                    return index
                }
            }
            nextCandidateOffsetByItemID[itemID] = offset
            return nil
        }

        var changed = false
        var removalIndexes = Set<Int>()
        var matchedItemIDs = Set<String>()
        for membershipIndex in courseItemMemberships.indices {
            let membership = courseItemMemberships[membershipIndex]
            guard membership.courseID == courseID,
                  sharedItemIDs.contains(membership.itemID) else {
                continue
            }
            // 纯归属兜底登记（无课程内链接条目）没有可对账的链接，
            // 不参与链接对账，直接保留。
            guard membership.courseRelativePath != nil
                    || membership.entryIdentity != nil else {
                continue
            }
            let identityMatch = membership.entryIdentity.flatMap {
                observationIndexByLinkIdentity[$0]
            }.flatMap { index in
                observationItemIDs[index] == membership.itemID
                    && consumedObservationIndexes.insert(index).inserted
                    ? index
                    : nil
            }
            let pathMatch = identityMatch == nil
                ? membership.courseRelativePath.flatMap {
                    observationIndexByRelativePath[$0]
                  }.flatMap { index in
                    observationItemIDs[index] == membership.itemID
                        && consumedObservationIndexes.insert(index).inserted
                        ? index
                        : nil
                  }
                : nil
            guard let matchIndex =
                identityMatch
                ?? pathMatch
                ?? firstUnconsumed(for: membership.itemID) else {
                if let relativePath = membership.courseRelativePath,
                   let rawEntryURL = Self.backgroundRawRelativeURL(
                    relativePath,
                    inside: courseRoot
                   ),
                   CourseProjectFileWorker.entryPresence(at: rawEntryURL)
                    != .absent {
                    courseRootUnavailableReasons[courseID] = ui(
                        "共享入口暂时无法读取；已保留课程成员关系，待入口恢复后继续对账。",
                        "A shared entry is temporarily unreadable. Its course membership was preserved until the entry recovers."
                    )
                    continue
                }
                removalIndexes.insert(membershipIndex)
                changed = true
                continue
            }
            matchedItemIDs.insert(membership.itemID)
            let observation = observations[matchIndex]
            if courseItemMemberships[membershipIndex].courseRelativePath
                != observation.relativePath
                || courseItemMemberships[membershipIndex].entryIdentity
                    != observation.linkIdentity
                || courseItemMemberships[membershipIndex].documentIdentifier
                    != nil {
                courseItemMemberships[membershipIndex].courseRelativePath =
                    observation.relativePath
                courseItemMemberships[membershipIndex].entryIdentity =
                    observation.linkIdentity
                courseItemMemberships[membershipIndex].documentIdentifier = nil
                changed = true
            }
        }
        if !removalIndexes.isEmpty {
            courseItemMemberships = courseItemMemberships.enumerated().compactMap {
                removalIndexes.contains($0.offset) ? nil : $0.element
            }
        }
        var existingItemIDs = Set(courseItemMemberships.compactMap {
            $0.courseID == courseID ? $0.itemID : nil
        })
        for index in observations.indices
        where !consumedObservationIndexes.contains(index) {
            guard let itemID = observationItemIDs[index],
                  existingItemIDs.insert(itemID).inserted else {
                continue
            }
            let observation = observations[index]
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: courseID,
                    itemID: itemID,
                    courseRelativePath: observation.relativePath,
                    entryIdentity: observation.linkIdentity
                )
            )
            changed = true
        }
        return changed
    }

    private func applyCourseFileObservations(
        _ snapshot: CourseFileScanSnapshot,
        courseID: UUID,
        root: URL
    ) async -> Bool {
        let observations = snapshot.observations
        var changed = false
        var lookupCount = 0
        var itemIndexByID: [String: Int] = [:]
        for index in importedItems.indices {
            guard case .courseOwned(let ownerCourseID, _) = importedItems[index].storage,
                  ownerCourseID == courseID else {
                continue
            }
            itemIndexByID[importedItems[index].id] = index
        }
        var membershipIndexesByItemID: [String: [Int]] = [:]
        for index in courseItemMemberships.indices
        where courseItemMemberships[index].courseID == courseID {
            membershipIndexesByItemID[
                courseItemMemberships[index].itemID,
                default: []
            ].append(index)
        }
        let ownedItemIDs = itemIndexByID.keys.sorted()
        var matchedObservationByItemID: [String: Int] = [:]
        var consumedObservationIndexes = Set<Int>()

        for itemID in ownedItemIDs {
            lookupCount += 1
            guard let membershipIndexes = membershipIndexesByItemID[itemID],
                  membershipIndexes.count == 1,
                  let relativePath = courseItemMemberships[
                    membershipIndexes[0]
                  ].courseRelativePath,
                  let observationIndex = snapshot.indexByRelativePath[relativePath],
                  consumedObservationIndexes.insert(observationIndex).inserted else {
                continue
            }
            matchedObservationByItemID[itemID] = observationIndex
        }

        func firstUnconsumed(_ indexes: [Int]?) -> Int? {
            guard let indexes else { return nil }
            for index in indexes {
                lookupCount += 1
                if consumedObservationIndexes.insert(index).inserted {
                    return index
                }
            }
            return nil
        }

        for itemID in ownedItemIDs where matchedObservationByItemID[itemID] == nil {
            lookupCount += 1
            guard let itemIndex = itemIndexByID[itemID],
                  let membershipIndexes = membershipIndexesByItemID[itemID],
                  membershipIndexes.count == 1 else {
                continue
            }
            let item = importedItems[itemIndex]
            let membership = courseItemMemberships[membershipIndexes[0]]
            let identityMatch = item.importedFileIdentity.flatMap {
                firstUnconsumed(snapshot.indexesByIdentity[$0])
            } ?? membership.entryIdentity.flatMap {
                firstUnconsumed(snapshot.indexesByIdentity[$0])
            }
            let documentMatch = identityMatch == nil
                ? membership.documentIdentifier.flatMap {
                    firstUnconsumed(snapshot.indexesByDocumentIdentifier[$0])
                }
                : nil
            if let match = identityMatch ?? documentMatch {
                matchedObservationByItemID[itemID] = match
            }
        }

        var goneIDs: [String] = []
        for itemID in ownedItemIDs {
            lookupCount += 1
            guard let itemIndex = itemIndexByID[itemID],
                  let membershipIndexes = membershipIndexesByItemID[itemID],
                  membershipIndexes.count == 1 else {
                continue
            }
            let membershipIndex = membershipIndexes[0]
            let item = importedItems[itemIndex]
            let membership = courseItemMemberships[membershipIndex]
            guard let observationIndex = matchedObservationByItemID[itemID] else {
                if let relativePath = membership.courseRelativePath,
                   snapshot.preservesExistingRecord(at: relativePath) {
                    continue
                }
                goneIDs.append(itemID)
                continue
            }
            let observation = observations[observationIndex]
            let identityChanged = item.importedFileIdentity != observation.identity
                || membership.entryIdentity != observation.identity
            let hasMetadataBaseline = item.fileByteCount != nil
                && item.fileModificationTimeNanoseconds != nil
            let metadataChanged = hasMetadataBaseline
                && (item.fileByteCount != observation.byteCount
                    || item.fileModificationTimeNanoseconds != observation.modificationTimeNanoseconds)
            var nextDigest = item.contentDigest
            var nextRevision = item.contentRevision
            if identityChanged || metadataChanged {
                do {
                    let snapshot = try await courseProjectFileWorker.snapshot(at: observation.url)
                    if identityChanged || item.contentDigest != snapshot.sha256 {
                        nextRevision &+= 1
                    }
                    nextDigest = snapshot.sha256
                } catch {
                    if keepUnavailableImportedItem(at: itemIndex).changed {
                        changed = true
                    }
                    continue
                }
            }

            var nextItem = importedItems[itemIndex]
            if nextDigest != item.contentDigest {
                backUpUnsavedNoteContentBeforeAdopting(itemID: itemID)
            }
            fileMissingSinceByItemID.removeValue(forKey: itemID)
            nextItem.title = observation.url.deletingPathExtension().lastPathComponent
            nextItem.subtitle = observation.url.lastPathComponent
            nextItem.kind = StudyItemKind.detect(from: observation.url)
            nextItem.urlPath = observation.url.path
            nextItem.importedFileIdentity = observation.identity
            nextItem.isNotebookNote = observation.isNote || nextItem.kind == .markdown
            nextItem.appearsInMaterials = nextItem.appearsInMaterials ?? !observation.isNote
            nextItem.contentRevision = nextRevision
            nextItem.contentDigest = nextDigest
            nextItem.fileByteCount = observation.byteCount
            nextItem.fileModificationTimeNanoseconds = observation.modificationTimeNanoseconds
            if importedItems[itemIndex] != nextItem {
                importedItems[itemIndex] = nextItem
                changed = true
            }
            if observation.isNote, let nextDigest {
                noteBackingContentDigestsByItemID[itemID] = nextDigest
            }
            if courseItemMemberships[membershipIndex].courseRelativePath
                != observation.relativePath
                || courseItemMemberships[membershipIndex].entryIdentity
                    != observation.identity
                || courseItemMemberships[membershipIndex].documentIdentifier
                    != observation.documentIdentifier {
                courseItemMemberships[membershipIndex].courseRelativePath =
                    observation.relativePath
                courseItemMemberships[membershipIndex].entryIdentity =
                    observation.identity
                courseItemMemberships[membershipIndex].documentIdentifier =
                    observation.documentIdentifier
                changed = true
            }
        }
        if forgetGoneImportedItems(ids: goneIDs) {
            changed = true
        }

        for (observationIndex, observation) in observations.enumerated()
        where !consumedObservationIndexes.contains(observationIndex) {
            lookupCount += 1
            let item = StudyItem(
                id: Self.makeImportedItemID(),
                title: observation.url.deletingPathExtension().lastPathComponent,
                subtitle: observation.url.lastPathComponent,
                kind: StudyItemKind.detect(from: observation.url),
                urlPath: observation.url.path,
                importedFileIdentity: observation.identity,
                isSample: false,
                isNotebookNote: observation.isNote || StudyItemKind.detect(from: observation.url) == .markdown,
                appearsInMaterials: !observation.isNote,
                storage: .courseOwned(
                    ownerCourseID: courseID,
                    relativePath: observation.relativePath
                ),
                contentRevision: 1,
                contentDigest: nil,
                fileByteCount: observation.byteCount,
                fileModificationTimeNanoseconds: observation.modificationTimeNanoseconds
            )
            importedItems.append(item)
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: courseID,
                    itemID: item.id,
                    courseRelativePath: observation.relativePath,
                    entryIdentity: observation.identity,
                    documentIdentifier: observation.documentIdentifier
                )
            )
            changed = true
        }
        lastCourseReconciliationLookupCount = lookupCount
        if changed {
            courseRootUnavailableReasons.removeValue(forKey: courseID)
        }
        return changed
    }

    func startCourseFileMaintenance() {
        stopCourseFileMaintenance()
        let storeID = ObjectIdentifier(self)
        let session = CourseFileWatchSession { [weak self] in
            Task { @MainActor in
                await self?.handleCourseFileWatchEvent()
            }
        }
        CourseFileWatchRegistry.attach(storeID, session: session)
        refreshCourseFileWatchers()
        // Detached + 每次 weak self：避免强引用拉长 store 生命周期，
        // 也避免 XCTest 把析构 cancel 记成用例失败。
        courseReconciliationTask = Task.detached(priority: .utility) {
            [weak self] in
            defer {
                CourseFileWatchRegistry.removeIfCurrent(storeID, session: session)
            }
            guard !Task.isCancelled else { return }
            await self?.reconcileCourseFilesNow()
            guard !Task.isCancelled else { return }
            await self?.retryRestoredPendingNoteWrites()
            await self?.refreshCourseFileWatchers()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.reconcileCourseFilesNow()
                await self?.refreshCourseFileWatchers()
            }
        }
    }

    func pauseCourseFileWatchingForMutation() {
        CourseFileWatchRegistry.session(for: ObjectIdentifier(self))?.pause()
    }

    func resumeCourseFileWatchingForMutation() {
        CourseFileWatchRegistry.session(for: ObjectIdentifier(self))?
            .resume(watching: directoriesToWatch())
    }

    func stopCourseFileMaintenance() {
        courseReconciliationTask?.cancel()
        courseReconciliationTask = nil
        CourseFileWatchRegistry.remove(ObjectIdentifier(self))
    }

    func courseFileWatchDirectoryCountForSelfCheck() -> Int {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return CourseFileWatchRegistry.session(for: ObjectIdentifier(self))?
            .watchedDirectoryCount ?? 0
    }

    private func handleCourseFileWatchEvent() async {
        guard let session = CourseFileWatchRegistry.session(
            for: ObjectIdentifier(self)
        ), !session.isPaused else { return }
        guard activeCourseFileMutationCounts.isEmpty,
              activeItemFileMutationIDs.isEmpty else { return }
        if courseReconciliationInFlight {
            session.poke()
            return
        }
        _ = await reconcileCourseFilesNow()
    }

    private func refreshCourseFileWatchers() {
        guard let session = CourseFileWatchRegistry.session(
            for: ObjectIdentifier(self)
        ), !session.isPaused else { return }
        session.replaceDirectories(directoriesToWatch())
    }

    private func directoriesToWatch() -> [URL] {
        var roots: [URL] = []
        if let libraryRoot = courseLibraryRootURL {
            roots.append(libraryRoot)
        }
        for course in courses {
            if let root = courseRootURL(for: course.id) {
                roots.append(root)
            }
        }
        var directories: [URL] = []
        var seen = Set<String>()
        for root in roots {
            for directory in Self.enumerableWatchDirectories(from: root) {
                let path = directory.standardizedFileURL.path
                if seen.insert(path).inserted {
                    directories.append(directory.standardizedFileURL)
                }
            }
        }
        return directories
    }

    private static func enumerableWatchDirectories(from root: URL) -> [URL] {
        let rootURL = root.standardizedFileURL
        var result = [rootURL]
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in false }
        ) else {
            return result
        }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                continue
            }
            result.append(url.standardizedFileURL)
        }
        return result
    }
}
