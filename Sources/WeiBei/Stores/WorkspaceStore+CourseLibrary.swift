import AppKit
import CryptoKit
import Darwin
import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    // MARK: - 自 WorkspaceStore.swift 原样搬入(课程库 CRUD/导入/资料管理,行为未变)

    @discardableResult
    func createCourseInLibrary(title rawTitle: String) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.createCourseInLibraryAsync(title: rawTitle)
        }
    }

    @discardableResult
    func createCourseInLibraryAsync(title rawTitle: String) async throws -> UUID {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CourseProjectRootError.emptyTitle }
        guard let libraryRoot = courseLibraryRootURL else {
            throw courseLibraryRootPath == nil
                ? CourseProjectRootError.missingLibrary
                : CourseProjectRootError.unavailableLibrary
        }
        let rawDirectoryName = MarkdownAttachmentStore.safeFileStem(
            title,
            fallback: "",
            limit: 80
        )
        let directoryName = rawDirectoryName.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )
        guard !directoryName.isEmpty else {
            throw CourseProjectRootError.invalidDirectoryName
        }
        return try await createCourseAsync(
            title: title,
            at: libraryRoot.appendingPathComponent(directoryName, isDirectory: true)
        )
    }

    @discardableResult
    func createCourse(title rawTitle: String, at rootURL: URL) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.createCourseAsync(title: rawTitle, at: rootURL)
        }
    }

    @discardableResult
    private func createCourseAsync(
        title rawTitle: String,
        at rootURL: URL
    ) async throws -> UUID {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CourseProjectRootError.emptyTitle }
        guard let libraryRoot = courseLibraryRootURL else {
            throw courseLibraryRootPath == nil
                ? CourseProjectRootError.missingLibrary
                : CourseProjectRootError.unavailableLibrary
        }

        let courseID = UUID()
        let createdRoot = try createManagedCourseRoot(
            courseID: courseID,
            at: rootURL,
            libraryRoot: libraryRoot
        )
        let previousCourses = courses
        let previousCourseKnowledgeProfiles = courseKnowledgeProfiles
        let previousActiveCourseID = activeCourseID

        do {
            let course = Course(
                id: courseID,
                title: title,
                colorIndex: nextCourseColorIndex(),
                sourceRootPath: nil,
                sourceRootRelativePath: createdRoot.relativePath,
                sourceRootIdentity: createdRoot.identity,
                sourceRootBookmarkData: nil
            )
            courses.append(course)
            courseKnowledgeProfiles.append(
                CourseKnowledgeProfile(courseID: course.id)
            )
            activeCourseID = course.id
            resolvedCourseRootURLs[course.id] = createdRoot.root
            courseRootUnavailableReasons.removeValue(forKey: course.id)
            guard await persistWorkspaceNow() else {
                throw CourseProjectRootError.workspaceSaveFailed
            }
            // The first commit registers the new course in workspace.json.
            // Only then may the next generation include its portable state.
            if !(await persistWorkspaceNow()) {
                reportWorkspaceSaveFailure(.coursePortableStateUnwritten, ui(
                    "课程已创建，但可携带状态尚未写入；本机内容已保留。请重试。",
                    "The course was created, but its portable state was not written. Local content is preserved; please retry."
                ))
            }
            return course.id
        } catch {
            courses = previousCourses
            courseKnowledgeProfiles = previousCourseKnowledgeProfiles
            activeCourseID = previousActiveCourseID
            resolvedCourseRootURLs.removeValue(forKey: courseID)
            courseRootUnavailableReasons.removeValue(forKey: courseID)
            safelyRemoveTransactionDirectory(
                at: createdRoot.root,
                expected: createdRoot.fingerprint
            )
            throw error
        }
    }

    private func createManagedCourseRoot(
        courseID: UUID,
        at rootURL: URL,
        libraryRoot: URL
    ) throws -> CreatedManagedCourseRoot {
        let targetRoot = try CourseProjectPathPolicy.newDirectory(rootURL)
        try validateCourseProjectRoot(
            targetRoot,
            identity: nil,
            mustBeInsideLibrary: true
        )
        guard let relativePath = CourseProjectPathPolicy.relativePath(
            of: targetRoot,
            inside: libraryRoot
        ) else {
            throw CourseProjectRootError.rootOutsideLibrary
        }
        let parent = targetRoot.deletingLastPathComponent()
        guard let parentIdentity = importedFileIdentityResolver(parent) else {
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        let stagingRoot = parent.appendingPathComponent(
            ".weibei-course-staging-\(courseID.uuidString.lowercased())",
            isDirectory: true
        )
        var placedRoot = false
        var fingerprint: TransactionDirectoryFingerprint?
        do {
            try FileManager.default.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: false
            )
            guard let stagingIdentity = importedFileIdentityResolver(
                stagingRoot
            ),
            let createdFingerprint = transactionDirectoryFingerprint(
                at: stagingRoot
            ) else {
                throw CourseProjectRootError.rootIdentityUnavailable
            }
            fingerprint = createdFingerprint
            try courseProjectMutationHook(.afterStagingDirectory)
            for directoryName in ["文稿", "笔记", ".weibei"] {
                try FileManager.default.createDirectory(
                    at: stagingRoot.appendingPathComponent(
                        directoryName,
                        isDirectory: true
                    ),
                    withIntermediateDirectories: false
                )
            }
            guard let preparedFingerprint = transactionDirectoryFingerprint(
                at: stagingRoot
            ) else {
                throw CourseProjectRootError.rootIdentityUnavailable
            }
            fingerprint = preparedFingerprint
            try courseProjectMutationHook(.beforeManifestWrite)
            let manifestURL = stagingRoot.appendingPathComponent(
                ".weibei/course.json"
            )
            try CourseProjectManifest(courseID: courseID)
                .encoded()
                .write(to: manifestURL, options: [.atomic])
            let manifest = try CourseProjectManifest.read(from: manifestURL)
            guard manifest.courseID == courseID,
                  manifest.schemaVersion ==
                    CourseProjectManifest.currentSchemaVersion,
                  let completeFingerprint =
                    transactionDirectoryFingerprint(at: stagingRoot) else {
                throw CourseProjectRootError.manifestMismatch
            }
            fingerprint = completeFingerprint
            try courseProjectMutationHook(.beforeAtomicPlacement)
            guard importedFileIdentityResolver(parent) == parentIdentity,
                  !FileManager.default.fileExists(atPath: targetRoot.path)
            else {
                throw CourseProjectRootError.overlappingRoot
            }
            try validateCourseProjectRoot(
                targetRoot,
                identity: nil,
                mustBeInsideLibrary: true
            )
            try FileManager.default.moveItem(at: stagingRoot, to: targetRoot)
            placedRoot = true
            let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(
                targetRoot
            )
            guard let identity = importedFileIdentityResolver(canonicalRoot),
                  identity == stagingIdentity,
                  let finalFingerprint = transactionDirectoryFingerprint(
                    at: canonicalRoot
                  ) else {
                throw CourseProjectRootError.rootIdentityUnavailable
            }
            try validateCourseProjectRoot(
                canonicalRoot,
                identity: identity,
                mustBeInsideLibrary: true
            )
            return CreatedManagedCourseRoot(
                root: canonicalRoot,
                relativePath: relativePath,
                identity: identity,
                fingerprint: finalFingerprint
            )
        } catch {
            if let fingerprint {
                safelyRemoveTransactionDirectory(
                    at: placedRoot ? targetRoot : stagingRoot,
                    expected: fingerprint
                )
            }
            throw error
        }
    }

    func configureCourseLibrary(at rootURL: URL) throws {
        try waitForCourseFileOperation {
            try await self.configureCourseLibraryAsync(at: rootURL)
        }
    }

    func configureCourseLibraryAsync(at rootURL: URL) async throws {
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(rootURL)
        try validateLibraryRoot(canonicalRoot)
        guard let identity = importedFileIdentityResolver(canonicalRoot) else {
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        // S6-2：资料库身份变化不再拒绝；静默改绑到新文件夹（课程记录保留）。
        // 原先 libraryIdentityMismatch 拒绝「换库」；产品改为允许迁移绑定。
        if let persistedIdentity = courseLibraryRootIdentity,
           persistedIdentity != identity {
            showTransientNoteStatus(
                ui(
                    "已将课程资料库改绑到所选文件夹，课程记录保留。",
                    "The course library was re-bound to the selected folder. Course records were kept."
                )
            )
        }
        guard let bookmark = courseRootBookmarkMaker(canonicalRoot) else {
            throw CourseProjectRootError.bookmarkUnavailable
        }
        guard let resolution = courseRootBookmarkResolver(bookmark) else {
            throw CourseProjectRootError.bookmarkResolutionFailed
        }
        let scopedURL = resolution.url
        guard courseSecurityScopeStarter(scopedURL) else {
            throw CourseProjectRootError.securityScopeDenied
        }
        let resolvedRoot: URL
        do {
            resolvedRoot = try CourseProjectPathPolicy.existingDirectory(scopedURL)
            guard importedFileIdentityResolver(resolvedRoot) == identity else {
                throw CourseProjectRootError.bookmarkResolutionFailed
            }
            try await ensureCommonContentDirectories(at: resolvedRoot)
        } catch {
            courseSecurityScopeStopper(scopedURL)
            throw error
        }

        let ownerKey = "library"
        let previousScope = activeCourseSecurityScopes[ownerKey]
        let previousPath = courseLibraryRootPath
        let previousIdentity = courseLibraryRootIdentity
        let previousBookmark = courseLibraryRootBookmarkData
        let previousURL = courseLibraryRootURL
        let previousUnavailableReason = courseLibraryUnavailableReason
        let previousCourses = courses
        let previousResolvedCourseRootURLs = resolvedCourseRootURLs
        let previousCourseRootUnavailableReasons = courseRootUnavailableReasons
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNoteBackingDigests = noteBackingContentDigestsByItemID

        activeCourseSecurityScopes[ownerKey] = scopedURL
        courseLibraryRootPath = resolvedRoot.path
        courseLibraryRootIdentity = identity
        courseLibraryRootBookmarkData = bookmark
        courseLibraryRootURL = resolvedRoot
        courseLibraryUnavailableReason = nil
        _ = await restoreCourseReferencesInsideLibraryAsync()
        _ = await migrateLegacySharedMaterials(in: resolvedRoot)
        for course in courses where resolvedCourseRootURLs[course.id] != nil {
            _ = resolveCourseOwnedItems(for: course.id)
        }
        // 这里只登记资料库绑定；课程状态要在读完文件夹后再按真实内容写回。
        guard await persistWorkspaceNow(
            skippingPortableCourseIDs: Set(courses.map(\.id))
        ) else {
            courseSecurityScopeStopper(scopedURL)
            if let previousScope {
                activeCourseSecurityScopes[ownerKey] = previousScope
            } else {
                activeCourseSecurityScopes.removeValue(forKey: ownerKey)
            }
            courseLibraryRootPath = previousPath
            courseLibraryRootIdentity = previousIdentity
            courseLibraryRootBookmarkData = previousBookmark
            courseLibraryRootURL = previousURL
            courseLibraryUnavailableReason = previousUnavailableReason
            courses = previousCourses
            resolvedCourseRootURLs = previousResolvedCourseRootURLs
            courseRootUnavailableReasons = previousCourseRootUnavailableReasons
            importedItems = previousImportedItems
            courseItemMemberships = previousMemberships
            noteBackingContentDigestsByItemID = previousNoteBackingDigests
            throw CourseProjectRootError.workspaceSaveFailed
        }
        let legacyOrganization = await organizeLegacyCourses(
            in: resolvedRoot
        )
        if !legacyOrganization.errors.isEmpty {
            showImportantOperationError(ui(
                "已有 \(legacyOrganization.migrated) 份旧资料完成整理；另有 \(legacyOrganization.errors.count) 份未完成，原内容仍保留。请确认资料库可写后重试。",
                "Organized \(legacyOrganization.migrated) legacy item(s). \(legacyOrganization.errors.count) remain, and their original content is preserved. Make sure the library is writable, then try again."
            ))
        }
        _ = restorePortableCourseStates()
        await reconcileCourseFilesNow()
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
        if let previousScope {
            let stopScope = courseSecurityScopeStopper
            let runningLibraryCourseID = activeAgentReplyChatID
                .flatMap { runningChatID in
                    studySessions.first(where: { $0.id == runningChatID })?.courseID
                }
                .flatMap { runningCourseID in
                    course(withID: runningCourseID)?.sourceRootRelativePath != nil
                        ? runningCourseID
                        : nil
                }
            if let runningLibraryCourseID,
               cancelAgentRequestIfRunning(
                   in: runningLibraryCourseID,
                   completion: {
                       stopScope(previousScope)
                   }
               ) {
                // The old scope stays valid until the running Agent request has stopped.
            } else {
                courseSecurityScopeStopper(previousScope)
            }
        }
    }

    private func organizeLegacyCourses(
        in libraryRoot: URL
    ) async -> (migrated: Int, errors: [String]) {
        let rootlessCourseIDs = courses.compactMap { course -> UUID? in
            guard course.sourceRootPath == nil,
                  course.sourceRootRelativePath == nil,
                  course.sourceRootIdentity == nil else {
                return nil
            }
            return course.id
        }
        var errors: [String] = []
        var createdRoots: [CreatedManagedCourseRoot] = []
        let previousCourses = courses
        let previousResolvedRoots = resolvedCourseRootURLs

        for courseID in rootlessCourseIDs {
            guard let index = courses.firstIndex(where: {
                $0.id == courseID
            }) else { continue }
            do {
                let target = try availableLegacyCourseRoot(
                    title: courses[index].title,
                    libraryRoot: libraryRoot
                )
                let created = try createManagedCourseRoot(
                    courseID: courseID,
                    at: target,
                    libraryRoot: libraryRoot
                )
                createdRoots.append(created)
                courses[index].sourceRootPath = nil
                courses[index].sourceRootRelativePath =
                    created.relativePath
                courses[index].sourceRootIdentity = created.identity
                courses[index].sourceRootBookmarkData = nil
                courses[index].updatedAt = Date()
                resolvedCourseRootURLs[courseID] = created.root
                courseRootUnavailableReasons.removeValue(forKey: courseID)
            } catch {
                recordCourseLibraryUIFailure(
                    error,
                    operation: "organize_legacy_course",
                    path: libraryRoot
                )
                errors.append(courses[index].title)
            }
        }
        if !createdRoots.isEmpty,
           !(await persistWorkspaceNow()) {
            courses = previousCourses
            resolvedCourseRootURLs = previousResolvedRoots
            for created in createdRoots {
                safelyRemoveTransactionDirectory(
                    at: created.root,
                    expected: created.fingerprint
                )
            }
            return (
                0,
                errors + [CourseProjectRootError.workspaceSaveFailed
                    .localizedDescription]
            )
        }

        let membershipsBeforeMigration = courseItemMemberships
        let legacyItems = importedItems.filter { item in
            guard case .common = item.storage else { return false }
            return membershipsBeforeMigration.contains {
                $0.itemID == item.id
            }
        }
        var migrated = 0
        for item in legacyItems {
            let relatedCourseIDs = Set(
                membershipsBeforeMigration.filter {
                    $0.itemID == item.id
                }.map(\.courseID).filter {
                    courseRootURL(for: $0) != nil
                }
            )
            guard !relatedCourseIDs.isEmpty else { continue }
            do {
                try await organizeLegacyItem(
                    item,
                    courseIDs: relatedCourseIDs
                )
                migrated += 1
            } catch {
                recordCourseLibraryUIFailure(
                    error,
                    operation: "organize_legacy_item",
                    path: item.url
                )
                errors.append(displayTitle(for: item))
            }
        }
        return (migrated, errors)
    }

    private func availableLegacyCourseRoot(
        title: String,
        libraryRoot: URL
    ) throws -> URL {
        let rawName = MarkdownAttachmentStore.safeFileStem(
            title,
            fallback: "课程",
            limit: 80
        ).trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: ".")
            )
        )
        guard !rawName.isEmpty else {
            throw CourseProjectRootError.invalidDirectoryName
        }
        for suffix in 1...9_999 {
            let name = suffix == 1 ? rawName : "\(rawName) \(suffix)"
            let candidate = libraryRoot.appendingPathComponent(
                name,
                isDirectory: true
            )
            guard !FileManager.default.fileExists(atPath: candidate.path)
            else { continue }
            if (try? validateCourseProjectRoot(
                candidate,
                identity: nil,
                mustBeInsideLibrary: true
            )) != nil {
                return candidate
            }
        }
        throw CourseProjectRootError.invalidDirectoryName
    }

    private func organizeLegacyItem(
        _ item: StudyItem,
        courseIDs: Set<UUID>
    ) async throws {
        guard let sourceURL = item.url,
              let ownerCourseID = courseIDs.sorted(by: {
                  $0.uuidString < $1.uuidString
              }).first else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let sourceInfo = try await courseProjectFileWorker
            .validatedRegularSource(sourceURL)
        let sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sourceInfo.url,
            expectedIdentity: sourceInfo.identity
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WeiBei-Legacy-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let temporarySource = temporaryDirectory.appendingPathComponent(
            sourceURL.lastPathComponent
        )
        let temporaryIdentity = try await courseProjectFileWorker
            .copyAndVerify(
                from: sourceInfo.url,
                generatedData: nil,
                to: temporarySource,
                expectedSnapshot: sourceSnapshot
            )
        let role = CourseOwnedFileRole(item: item)
        _ = try await transactCourseOwnedFile(
            courseID: ownerCourseID,
            role: role,
            fileName: sourceURL.lastPathComponent,
            sourceURL: temporarySource,
            sourceIdentity: temporaryIdentity,
            generatedData: nil,
            conflictResolution: .keepBoth(preferredFileName: nil),
            preservingItemID: item.id,
            additionalCourseIDs: courseIDs
        )
        for courseID in courseIDs where courseID != ownerCourseID {
            try await shareCourseOwnedItem(
                itemID: item.id,
                withCourseID: courseID,
                conflictResolution: .keepBoth(preferredFileName: nil)
            )
        }
    }

    @discardableResult
    func adoptCourseFolder(at rootURL: URL, title rawTitle: String) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.adoptCourseFolderAsync(
                at: rootURL,
                title: rawTitle
            )
        }
    }

    @discardableResult
    func adoptCourseFolderAsync(
        at rootURL: URL,
        title rawTitle: String
    ) async throws -> UUID {
        switch try await adoptCourseFolderOrProposeRebindAsync(
            at: rootURL,
            title: rawTitle
        ) {
        case .opened(let courseID):
            return courseID
        case .requiresRebind:
            throw CourseProjectRootError.manifestMismatch
        }
    }

    func adoptCourseFolderOrProposeRebind(
        at rootURL: URL,
        title rawTitle: String
    ) throws -> CourseFolderAdoptionOutcome {
        try waitForCourseFileOperation {
            try await self.adoptCourseFolderOrProposeRebindAsync(
                at: rootURL,
                title: rawTitle
            )
        }
    }

    func adoptCourseFolderOrProposeRebindAsync(
        at rootURL: URL,
        title rawTitle: String
    ) async throws -> CourseFolderAdoptionOutcome {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CourseProjectRootError.emptyTitle }
        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(rootURL)
        guard let identity = importedFileIdentityResolver(canonicalRoot) else {
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        if let existing = existingCourse(at: canonicalRoot, identity: identity) {
            return .opened(
                try await refreshAdoptedCourse(
                    existing,
                    at: canonicalRoot,
                    identity: identity
                )
            )
        }

        let libraryRelativePath = courseLibraryRootURL.flatMap {
            CourseProjectPathPolicy.relativePath(of: canonicalRoot, inside: $0)
        }
        guard let libraryRelativePath,
              isTopLevelLibraryCourseFolder(libraryRelativePath) else {
            throw CourseProjectRootError.rootOutsideLibrary
        }
        let bookmark: Data? = nil
        let resolvedExternalRoot: URL? = nil
        let externalScopeURL: URL? = nil

        let metadataURL = canonicalRoot.appendingPathComponent(".weibei", isDirectory: true)
        let manifestURL = metadataURL.appendingPathComponent("course.json")
        var createdMetadata = false
        var createdMetadataFingerprint: TransactionDirectoryFingerprint?
        var adoptionSnapshot: CoursePortableAdoptionSnapshot?
        let courseID: UUID
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let metadataValues = try? metadataURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ])
            let metadataLooksSafe =
                metadataValues?.isDirectory == true
                && metadataValues?.isSymbolicLink != true
                && metadataValues?.isAliasFile != true
                && !CourseProjectFileWorker.isSymbolicLink(at: metadataURL)
                && CourseProjectPathPolicy.isSame(
                    metadataURL,
                    metadataURL.resolvingSymlinksInPath()
                )
                && importedFileIdentityResolver(canonicalRoot) == identity
            if metadataLooksSafe {
                do {
                    let snapshot = try await courseProjectFileWorker
                        .adoptionSnapshot(
                            at: canonicalRoot,
                            expectedRootIdentity: identity
                        )
                    adoptionSnapshot = snapshot
                    courseID = snapshot.manifest.courseID
                } catch {
                    // 布局安全但状态不可读（如超大）：保留磁盘原样并拒绝，避免改写共享课程根。
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    throw CourseProjectRootError.metadataConflict
                }
            } else {
                // S6-1：结构异常的 .weibei（symlink/非目录）→ 改名备份后按新课继续。
                let backup = metadataURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        ".weibei.backup-\(Int(Date().timeIntervalSince1970))",
                        isDirectory: true
                    )
                try? FileManager.default.moveItem(at: metadataURL, to: backup)
                adoptionSnapshot = nil
                courseID = UUID()
                showTransientNoteStatus(
                    ui(
                        "原课程元数据已备份为 \(backup.lastPathComponent)，将按新课程纳入。",
                        "Previous course metadata was backed up as \(backup.lastPathComponent); adopting as a new course."
                    )
                )
                try validateCourseProjectRoot(
                    canonicalRoot,
                    identity: identity,
                    mustBeInsideLibrary: false
                )
                // 落入下方 else 同款创建逻辑：用 staged 写新 manifest。
                let stagedMetadataURL = canonicalRoot.appendingPathComponent(
                    ".weibei-adopt-staging-\(courseID.uuidString.lowercased())",
                    isDirectory: true
                )
                do {
                    try FileManager.default.createDirectory(
                        at: stagedMetadataURL,
                        withIntermediateDirectories: false
                    )
                    guard let emptyFingerprint = transactionDirectoryFingerprint(
                        at: stagedMetadataURL
                    ) else {
                        throw CourseProjectRootError.rootIdentityUnavailable
                    }
                    createdMetadataFingerprint = emptyFingerprint
                    try CourseProjectManifest(courseID: courseID)
                        .encoded()
                        .write(
                            to: stagedMetadataURL.appendingPathComponent(
                                "course.json"
                            ),
                            options: [.atomic]
                        )
                    guard let completeFingerprint =
                            transactionDirectoryFingerprint(at: stagedMetadataURL)
                    else {
                        throw CourseProjectRootError.rootIdentityUnavailable
                    }
                    createdMetadataFingerprint = completeFingerprint
                    try FileManager.default.moveItem(
                        at: stagedMetadataURL,
                        to: metadataURL
                    )
                    createdMetadata = true
                } catch {
                    if let createdMetadataFingerprint {
                        safelyRemoveTransactionDirectory(
                            at: stagedMetadataURL,
                            expected: createdMetadataFingerprint
                        )
                    }
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    throw error
                }
            }
            if let existing = courses.first(where: { $0.id == courseID }),
               adoptionSnapshot != nil {
                do {
                    try validateCourseProjectRoot(
                        canonicalRoot,
                        identity: identity,
                        mustBeInsideLibrary: false,
                        excludingCourseID: existing.id
                    )
                    guard let adoptionSnapshot else {
                        throw CourseProjectRootError.manifestMismatch
                    }
                    let proposal = try await makeCourseProjectRebindProposal(
                        existing: existing,
                        candidateRoot: canonicalRoot,
                        candidateRootIdentity: identity,
                        snapshot: adoptionSnapshot
                    )
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    return .requiresRebind(proposal)
                } catch {
                    if let externalScopeURL {
                        courseSecurityScopeStopper(externalScopeURL)
                    }
                    throw error
                }
            }
            if adoptionSnapshot != nil {
                try validateCourseProjectRoot(
                    canonicalRoot,
                    identity: identity,
                    mustBeInsideLibrary: false
                )
            }
        } else {
            try validateCourseProjectRoot(
                canonicalRoot,
                identity: identity,
                mustBeInsideLibrary: false
            )
            courseID = UUID()
            let stagedMetadataURL = canonicalRoot.appendingPathComponent(
                ".weibei-adopt-staging-\(courseID.uuidString.lowercased())",
                isDirectory: true
            )
            do {
                guard importedFileIdentityResolver(canonicalRoot) == identity else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                try FileManager.default.createDirectory(at: stagedMetadataURL, withIntermediateDirectories: false)
                guard let emptyFingerprint = transactionDirectoryFingerprint(at: stagedMetadataURL) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                createdMetadataFingerprint = emptyFingerprint
                try CourseProjectManifest(courseID: courseID)
                    .encoded()
                    .write(
                        to: stagedMetadataURL.appendingPathComponent("course.json"),
                        options: [.atomic]
                    )
                guard let completeFingerprint = transactionDirectoryFingerprint(at: stagedMetadataURL) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                createdMetadataFingerprint = completeFingerprint
                guard importedFileIdentityResolver(canonicalRoot) == identity,
                      !FileManager.default.fileExists(atPath: metadataURL.path) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
                try FileManager.default.moveItem(at: stagedMetadataURL, to: metadataURL)
                createdMetadata = true
                guard importedFileIdentityResolver(canonicalRoot) == identity,
                      !CourseProjectFileWorker.isSymbolicLink(at: metadataURL),
                      CourseProjectPathPolicy.isSame(
                        metadataURL,
                        metadataURL.resolvingSymlinksInPath()
                ) else {
                    throw CourseProjectRootError.rootIdentityUnavailable
                }
            } catch {
                if let createdMetadataFingerprint {
                    safelyRemoveTransactionDirectory(
                        at: createdMetadata ? metadataURL : stagedMetadataURL,
                        expected: createdMetadataFingerprint
                    )
                }
                if let externalScopeURL { courseSecurityScopeStopper(externalScopeURL) }
                throw error
            }
        }

        let previousCourses = courses
        let previousActiveCourseID = activeCourseID
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNoteSourceLinks = noteSourceLinks
        let previousCourseStudyLocations = studyLocationsByCourseID
        let previousCourseResumePoints = courseResumePoints
        let previousLearningMemoryStates = learningMemoryStates
        let previousCourseKnowledgeProfiles = courseKnowledgeProfiles
        let previousStudySessions = studySessions
        let previousActiveStudySessionID = activeStudySessionID
        let previousMessages = messages
        let previousNotesByItemID = notesByItemID
        let previousPendingNoteWrites = pendingNoteWritesByItemID
        let previousNoteBackingDigests =
            noteBackingContentDigestsByItemID
        let previousPortableRevisions = coursePortableStateRevisions
        let previousPortableDigests = coursePortableStateDigests
        let previousDirtyPortableCourses = dirtyPortableCourseIDs
        let previousBlockedPortableCourses = blockedPortableCourseIDs
        let previousOversizedPortableCourses =
            oversizedPortableCourseIDs
        let previousPortableBootstrap =
            needsPortableCourseStateBootstrap
        guard importedFileIdentityResolver(canonicalRoot) == identity else {
            if let externalScopeURL { courseSecurityScopeStopper(externalScopeURL) }
            throw CourseProjectRootError.rootIdentityUnavailable
        }
        let course = Course(
            id: courseID,
            title: title,
            colorIndex: nextCourseColorIndex(),
            sourceRootPath: nil,
            sourceRootRelativePath: libraryRelativePath,
            sourceRootIdentity: identity,
            sourceRootBookmarkData: nil
        )
        courses.append(course)
        courseKnowledgeProfiles.append(
            CourseKnowledgeProfile(courseID: course.id)
        )
        activeCourseID = course.id
        resolvedCourseRootURLs[course.id] = resolvedExternalRoot ?? canonicalRoot
        courseRootUnavailableReasons.removeValue(forKey: course.id)
        if let externalScopeURL {
            activeCourseSecurityScopes["course:\(course.id.uuidString)"] = externalScopeURL
        }
        do {
            if let portableStateData = adoptionSnapshot?.portableStateData {
                let state = try JSONDecoder()
                    .decode(
                        CoursePortableState.self,
                        from: portableStateData
                    )
                    .validated(expectedCourseID: courseID)
                try applyCoursePortableState(state, courseID: courseID)
                coursePortableStateRevisions[courseID] = state.revision
                coursePortableStateDigests[courseID] =
                    try coursePortableStatePayloadDigest(state)
            } else {
                needsPortableCourseStateBootstrap = true
            }
            guard await persistWorkspaceNow() else {
                throw CourseProjectRootError.workspaceSaveFailed
            }
        } catch {
            courses = previousCourses
            activeCourseID = previousActiveCourseID
            importedItems = previousImportedItems
            courseItemMemberships = previousMemberships
            noteSourceLinks = previousNoteSourceLinks
            studyLocationsByCourseID = previousCourseStudyLocations
            courseResumePoints = previousCourseResumePoints
            learningMemoryStates = previousLearningMemoryStates
            courseKnowledgeProfiles = previousCourseKnowledgeProfiles
            studySessions = previousStudySessions
            activeStudySessionID = previousActiveStudySessionID
            messages = previousMessages
            replaceNoteDrafts(previousNotesByItemID)
            pendingNoteWritesByItemID = previousPendingNoteWrites
            noteBackingContentDigestsByItemID =
                previousNoteBackingDigests
            coursePortableStateRevisions = previousPortableRevisions
            coursePortableStateDigests = previousPortableDigests
            dirtyPortableCourseIDs = previousDirtyPortableCourses
            blockedPortableCourseIDs = previousBlockedPortableCourses
            oversizedPortableCourseIDs =
                previousOversizedPortableCourses
            needsPortableCourseStateBootstrap =
                previousPortableBootstrap
            resolvedCourseRootURLs.removeValue(forKey: course.id)
            courseRootUnavailableReasons.removeValue(forKey: course.id)
            if let externalScopeURL {
                activeCourseSecurityScopes.removeValue(forKey: "course:\(course.id.uuidString)")
                courseSecurityScopeStopper(externalScopeURL)
            }
            if createdMetadata,
               importedFileIdentityResolver(canonicalRoot) == identity,
               let createdMetadataFingerprint {
                safelyRemoveTransactionDirectory(
                    at: metadataURL,
                    expected: createdMetadataFingerprint
                )
            }
            throw error
        }
        try courseProjectMutationHook(
            .afterAdoptionWorkspaceSaveBeforeManifestNormalization
        )
        if let adoptionSnapshot,
           adoptionSnapshot.manifest.portableExport != nil {
            do {
                let confirmedSnapshot = try await courseProjectFileWorker
                    .adoptionSnapshot(
                        at: canonicalRoot,
                        expectedRootIdentity: identity
                    )
                guard confirmedSnapshot.metadataIdentity
                        == adoptionSnapshot.metadataIdentity,
                      confirmedSnapshot.manifestData
                        == adoptionSnapshot.manifestData,
                      confirmedSnapshot.portableStateData
                        == adoptionSnapshot.portableStateData,
                      confirmedSnapshot.completionData
                        == adoptionSnapshot.completionData,
                      confirmedSnapshot.manifest.portableExport != nil else {
                    throw CourseProjectRootError.manifestMismatch
                }
                let normalizedData = try CourseProjectManifest(
                    courseID: courseID
                ).encoded()
                try await courseProjectFileWorker
                    .normalizePortableCourseManifest(
                        with: normalizedData,
                        at: manifestURL,
                        expectedDirectoryIdentity:
                            confirmedSnapshot.metadataIdentity,
                        expectedPreviousData:
                            confirmedSnapshot.manifestData
                    )
            } catch {
                let isolatedNoteItemIDs =
                    importedItems.compactMap { item -> String? in
                        guard item.isNotebookNote,
                              case .courseOwned(
                                  let ownerCourseID,
                                  _
                              ) = item.storage,
                              ownerCourseID == course.id else {
                            return nil
                        }
                        return item.id
                    }
                for itemID in isolatedNoteItemIDs {
                    courseNoteLoadGenerationByItemID[
                        itemID,
                        default: 0
                    ] &+= 1
                    courseNoteLoadTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWriteTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWritesInFlight.remove(itemID)
                }
                resolvedCourseRootURLs.removeValue(
                    forKey: course.id
                )
                recordCourseLibraryUIFailure(
                    error,
                    operation: "adopt_course_manifest",
                    path: canonicalRoot
                )
                courseRootUnavailableReasons[course.id] = ui(
                    "课程文件夹已保留，但当前无法安全接入；魏碑没有覆盖其中内容。请修复或重新选择该课程文件夹。",
                    "The course folder is preserved but cannot be connected safely. WeiBei did not overwrite its contents. Repair or re-select the course folder."
                )
                let scopeKey =
                    "course:\(course.id.uuidString)"
                if let scopedURL =
                    activeCourseSecurityScopes.removeValue(
                        forKey: scopeKey
                    ) {
                    let stopScope = courseSecurityScopeStopper
                    if !cancelAgentRequestIfRunning(
                        in: course.id,
                        completion: {
                            stopScope(scopedURL)
                        }
                    ) {
                        stopScope(scopedURL)
                    }
                } else {
                    cancelAgentRequestIfRunning(in: course.id)
                }
                invalidateAgentContext()
                throw error
            }
        }
        if !(await persistWorkspaceNow()) {
            reportWorkspaceSaveFailure(.coursePortableStateUnwritten, ui(
                "课程已登记，但可携带状态尚未写入；本机内容已保留。请重试。",
                "The course was registered, but its portable state was not written. Local content is preserved; please retry."
            ))
        }
        if !WeiBeiSafetyTestMode.isEnabled {
            Task { @MainActor [weak self] in
                await self?.reconcileCourseFilesNow(courseID: course.id)
            }
        }
        return .opened(course.id)
    }

    @discardableResult
    private func refreshAdoptedCourse(
        _ existing: Course,
        at canonicalRoot: URL,
        identity: ImportedFileIdentity
    ) async throws -> UUID {
        guard activeCourseRebindTokens[existing.id] == nil,
              activeCourseRemovalTokens[existing.id] == nil else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard let courseIndex = courses.firstIndex(where: { $0.id == existing.id }) else {
            throw CourseProjectRootError.rootAlreadyRegistered
        }
        if existing.sourceRootRelativePath != nil,
           courseLibraryRootPath != nil,
           courseLibraryRootURL == nil {
            throw CourseProjectRootError.unavailableLibrary
        }

        let libraryRelativePath = courseLibraryRootURL.flatMap {
            CourseProjectPathPolicy.relativePath(of: canonicalRoot, inside: $0)
        }
        var refreshedBookmark: Data?
        var resolvedRoot = canonicalRoot
        var newScopeURL: URL?
        if libraryRelativePath == nil {
            guard let bookmark = courseRootBookmarkMaker(canonicalRoot) else {
                throw CourseProjectRootError.bookmarkUnavailable
            }
            guard let resolution = courseRootBookmarkResolver(bookmark) else {
                throw CourseProjectRootError.bookmarkResolutionFailed
            }
            let scopedURL = resolution.url
            guard courseSecurityScopeStarter(scopedURL) else {
                throw CourseProjectRootError.securityScopeDenied
            }
            do {
                resolvedRoot = try CourseProjectPathPolicy.existingDirectory(scopedURL)
                guard importedFileIdentityResolver(resolvedRoot) == identity else {
                    throw CourseProjectRootError.bookmarkResolutionFailed
                }
            } catch {
                courseSecurityScopeStopper(scopedURL)
                throw error
            }
            refreshedBookmark = bookmark
            newScopeURL = scopedURL
        }

        do {
            try await validateRestoredCourseRootAsync(
                resolvedRoot,
                course: existing,
                mustBeInsideLibrary: libraryRelativePath != nil
            )
        } catch {
            if let newScopeURL { courseSecurityScopeStopper(newScopeURL) }
            throw error
        }

        let scopeKey = "course:\(existing.id.uuidString)"
        let previousCourse = courses[courseIndex]
        let previousResolvedRoot = resolvedCourseRootURLs[existing.id]
        let previousUnavailableReason = courseRootUnavailableReasons[existing.id]
        let previousScope = activeCourseSecurityScopes[scopeKey]
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNoteBackingDigests = noteBackingContentDigestsByItemID

        var refreshedCourse = previousCourse
        refreshedCourse.sourceRootPath = nil
        refreshedCourse.sourceRootRelativePath = libraryRelativePath
        refreshedCourse.sourceRootIdentity = identity
        refreshedCourse.sourceRootBookmarkData = nil
        refreshedCourse.updatedAt = Date()
        courses[courseIndex] = refreshedCourse
        resolvedCourseRootURLs[existing.id] = resolvedRoot
        courseRootUnavailableReasons.removeValue(forKey: existing.id)
        if let newScopeURL {
            activeCourseSecurityScopes[scopeKey] = newScopeURL
        } else {
            activeCourseSecurityScopes.removeValue(forKey: scopeKey)
        }
        _ = resolveCourseOwnedItems(for: existing.id)

        // 先保存重新连接信息；课程状态要在读盘和扫描完成后再写回。
        guard await persistWorkspaceNow(
            skippingPortableCourseIDs: Set(courses.map(\.id))
        ) else {
            courses[courseIndex] = previousCourse
            if let previousResolvedRoot {
                resolvedCourseRootURLs[existing.id] = previousResolvedRoot
            } else {
                resolvedCourseRootURLs.removeValue(forKey: existing.id)
            }
            if let previousUnavailableReason {
                courseRootUnavailableReasons[existing.id] = previousUnavailableReason
            } else {
                courseRootUnavailableReasons.removeValue(forKey: existing.id)
            }
            if let previousScope {
                activeCourseSecurityScopes[scopeKey] = previousScope
            } else {
                activeCourseSecurityScopes.removeValue(forKey: scopeKey)
            }
            importedItems = previousImportedItems
            courseItemMemberships = previousMemberships
            noteBackingContentDigestsByItemID = previousNoteBackingDigests
            if let newScopeURL { courseSecurityScopeStopper(newScopeURL) }
            throw CourseProjectRootError.workspaceSaveFailed
        }

        _ = restorePortableCourseStates()
        guard !blockedPortableCourseIDs.contains(existing.id) else {
            throw CourseProjectRootError.metadataConflict
        }
        await reconcileCourseFilesNow(courseID: existing.id)
        guard await persistWorkspaceNow() else {
            throw CourseProjectRootError.workspaceSaveFailed
        }

        if let previousScope {
            let stopScope = courseSecurityScopeStopper
            if !cancelAgentRequestIfRunning(
                in: existing.id,
                completion: {
                    stopScope(previousScope)
                }
            ) {
                stopScope(previousScope)
            }
        }
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
        return existing.id
    }

    private func makeCourseProjectRebindProposal(
        existing: Course,
        candidateRoot: URL,
        candidateRootIdentity: ImportedFileIdentity,
        snapshot: CoursePortableAdoptionSnapshot
    ) async throws -> CourseProjectRebindProposal {
        guard !courseHasUnstableState(existing.id) else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard !(try await registeredCourseRootIsAvailable(existing)) else {
            throw CourseProjectRebindError.originalRootStillAvailable
        }
        guard course(withID: existing.id) == existing,
              activeCourseRebindTokens[existing.id] == nil,
              !courseHasUnstableState(existing.id) else {
            throw CourseProjectRebindError.proposalChanged
        }
        _ = try evaluatedCourseRebindState(
            existing: existing,
            snapshot: snapshot
        )
        let localState = try makeCoursePortableState(
            courseID: existing.id,
            revision: coursePortableStateRevisions[existing.id] ?? 0,
            savedAt: Date(timeIntervalSince1970: 0)
        )
        return CourseProjectRebindProposal(
            courseID: existing.id,
            courseTitle: existing.title,
            candidateRoot: candidateRoot,
            candidateRootIdentity: candidateRootIdentity,
            expectedCourse: existing,
            expectedLocalPayloadDigest:
                try coursePortableStatePayloadDigest(localState),
            snapshot: snapshot
        )
    }

    func courseHasUnstableState(_ courseID: UUID) -> Bool {
        // S6-4：仅移除进行中阻塞导出/重绑；Agent/笔记待写不再拒绝用户操作。
        activeCourseRemovalTokens[courseID] != nil
    }

    func itemIsInRemovingCourse(_ itemID: String) -> Bool {
        if importedItems.first(where: { $0.id == itemID }).map({
            if case .courseOwned(let courseID, _) = $0.storage {
                return activeCourseRemovalTokens[courseID] != nil
            }
            return false
        }) == true {
            return true
        }
        return courseItemMemberships.contains {
            $0.itemID == itemID
                && activeCourseRemovalTokens[$0.courseID] != nil
        }
    }

    private func courseHasPendingWork(_ courseID: UUID) -> Bool {
        if activeCourseFileMutationCounts[
            courseID,
            default: 0
        ] > 0 {
            return true
        }
        let sessionIDs = Set(
            studySessions.lazy.filter {
                $0.courseID == courseID
            }.map(\.id)
        )
        let actionIDs = Set(
            studySessions.lazy.filter {
                $0.courseID == courseID
            }.flatMap {
                $0.messages.flatMap(\.actions).map(\.id)
            }
        )
        let noteItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID == courseID
            }.map(\.itemID)
        )
        return pendingNotePersistenceByItemID.keys.contains {
            noteItemIDs.contains($0)
        } || courseNoteWritesInFlight.contains {
            noteItemIDs.contains($0)
        } || studySessions.contains {
            $0.courseID == courseID
                && $0.messages.contains {
                    $0.role == .assistant
                        && $0.completionState == .generating
                }
        } || (
            isAskingAgent
                && activeAgentReplyChatID.map(sessionIDs.contains)
                    == true
        ) || agentReplyActionIDsInFlight.contains {
            actionIDs.contains($0)
        }
    }

    private func evaluatedCourseRebindState(
        existing: Course,
        snapshot: CoursePortableAdoptionSnapshot
    ) throws -> (
        state: CoursePortableState,
        statePayloadDigest: String
    ) {
        guard snapshot.manifest.courseID == existing.id,
              let portableStateData = snapshot.portableStateData else {
            throw CourseProjectRootError.manifestMismatch
        }
        let state = try JSONDecoder()
            .decode(CoursePortableState.self, from: portableStateData)
            .validated(expectedCourseID: existing.id)
        try validateCourseRebindStorage(
            state,
            courseID: existing.id
        )
        let statePayloadDigest = try coursePortableStatePayloadDigest(state)
        return (state, statePayloadDigest)
    }

    private func validateCourseRebindStorage(
        _ state: CoursePortableState,
        courseID: UUID
    ) throws {
        let otherCourseItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID != courseID
            }.map(\.itemID)
        )
        for portable in state.items
        where otherCourseItemIDs.contains(portable.itemID) {
            guard let existing = importedItems.first(where: {
                $0.id == portable.itemID
            }) else {
                throw CoursePortableStateError.crossCourseReference
            }
            switch (portable.storage, existing.storage) {
            case let (
                .sharedReference(candidatePath, candidateDigest),
                .common(existingPath)
            ) where candidatePath == existingPath
                && candidateDigest != nil
                && candidateDigest == portable.contentDigest
                && candidateDigest == existing.contentDigest
                && portable.kind == existing.kind
                && portable.isNotebookNote == existing.isNotebookNote:
                continue
            default:
                throw CoursePortableStateError.crossCourseReference
            }
        }
    }

    func validateCourseRebindStorageForSelfCheck(
        _ state: CoursePortableState,
        courseID: UUID
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try validateCourseRebindStorage(state, courseID: courseID)
    }

    private func registeredCourseRootIsAvailable(
        _ course: Course
    ) async throws -> Bool {
        guard let expectedIdentity = course.sourceRootIdentity else {
            return false
        }
        func matches(_ rawURL: URL) -> Bool {
            guard let root = try? CourseProjectPathPolicy.existingDirectory(
                rawURL
            ),
            importedFileIdentityResolver(root) == expectedIdentity,
            let data = try? CourseProjectFileWorker.readBoundedRegularFile(
                at: root.appendingPathComponent(".weibei/course.json"),
                maximumByteCount: 1_048_576
            ),
            let manifest = try? JSONDecoder().decode(
                CourseProjectManifest.self,
                from: data
            ),
            manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion else {
                return false
            }
            return manifest.courseID == course.id
        }

        var candidates: [URL] = []
        if let resolved = resolvedCourseRootURLs[course.id] {
            candidates.append(resolved)
        }
        if let relativePath = course.sourceRootRelativePath,
           let libraryRoot = courseLibraryRootURL {
            let expectedLibraryPath = courseLibraryRootPath
            let expectedLibraryIdentity = courseLibraryRootIdentity
            let expectedLibraryBookmark = courseLibraryRootBookmarkData
            if let expected = CourseProjectPathPolicy.resolvedRelativePath(
                relativePath,
                inside: libraryRoot
            ) {
                candidates.append(expected)
            }
            let search = await courseProjectFileWorker.findDirectory(
                with: expectedIdentity,
                inside: libraryRoot
            )
            guard courseLibraryRootURL == libraryRoot,
                  courseLibraryRootPath == expectedLibraryPath,
                  courseLibraryRootIdentity == expectedLibraryIdentity,
                  courseLibraryRootBookmarkData
                    == expectedLibraryBookmark else {
                throw CourseProjectRebindError.proposalChanged
            }
            lastCourseRebindRootSearchRanOnMainThread =
                search.ranOnMainThread
            if let moved = search.url {
                candidates.append(moved)
            }
        }
        var checkedPaths = Set<String>()
        for candidate in candidates {
            guard checkedPaths.insert(
                candidate.standardizedFileURL.path
            ).inserted else {
                continue
            }
            if matches(candidate) {
                return true
            }
        }

        return false
    }

    func courseRebindRootSearchRunsOffMainForSelfCheck() -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return lastCourseRebindRootSearchRanOnMainThread == false
    }

    private func course(
        matching proposal: CourseProjectRebindProposal
    ) -> Course? {
        courses.first {
            $0.id == proposal.courseID
                && $0 == proposal.expectedCourse
        }
    }

    private func courseUsesRebindCandidate(
        _ proposal: CourseProjectRebindProposal,
        resolvedRoot: URL
    ) -> Bool {
        guard let current = course(withID: proposal.courseID),
              current.sourceRootIdentity
                == proposal.candidateRootIdentity,
              let registeredRoot =
                resolvedCourseRootURLs[proposal.courseID] else {
            return false
        }
        return CourseProjectPathPolicy.isSame(
            registeredRoot,
            resolvedRoot
        )
    }

    @discardableResult
    func confirmCourseProjectRebind(
        _ proposal: CourseProjectRebindProposal
    ) throws -> UUID {
        try waitForCourseFileOperation {
            try await self.confirmCourseProjectRebindAsync(proposal)
        }
    }

    @discardableResult
    func confirmCourseProjectRebindAsync(
        _ proposal: CourseProjectRebindProposal
    ) async throws -> UUID {
        guard let existing = course(matching: proposal) else {
            throw CourseProjectRebindError.proposalChanged
        }
        guard !courseHasUnstableState(existing.id) else {
            throw CoursePortableExportError.unstableCourseState
        }
        let rebindToken = UUID()
        guard activeCourseRebindTokens[existing.id] == nil else {
            throw CoursePortableExportError.unstableCourseState
        }
        activeCourseRebindTokens[existing.id] = rebindToken
        defer {
            if activeCourseRebindTokens[existing.id] == rebindToken {
                activeCourseRebindTokens.removeValue(forKey: existing.id)
            }
        }
        guard !(try await registeredCourseRootIsAvailable(existing)) else {
            throw CourseProjectRebindError.originalRootStillAvailable
        }

        let canonicalRoot = try CourseProjectPathPolicy.existingDirectory(
            proposal.candidateRoot
        )
        guard importedFileIdentityResolver(canonicalRoot)
                == proposal.candidateRootIdentity else {
            throw CourseProjectRebindError.proposalChanged
        }
        try validateCourseProjectRoot(
            canonicalRoot,
            identity: proposal.candidateRootIdentity,
            mustBeInsideLibrary: true,
            excludingCourseID: proposal.courseID
        )

        let libraryRelativePath = courseLibraryRootURL.flatMap {
            CourseProjectPathPolicy.relativePath(
                of: canonicalRoot,
                inside: $0
            )
        }
        guard let libraryRelativePath,
              isTopLevelLibraryCourseFolder(libraryRelativePath) else {
            throw CourseProjectRootError.rootOutsideLibrary
        }
        let refreshedBookmark: Data? = nil
        let resolvedRoot = canonicalRoot
        let newScopeURL: URL? = nil

        var shouldStopNewScopeOnFailure = newScopeURL != nil
        let confirmedSnapshot: CoursePortableAdoptionSnapshot
        do {
            confirmedSnapshot = try await courseProjectFileWorker
                .adoptionSnapshot(
                    at: resolvedRoot,
                    expectedRootIdentity:
                        proposal.candidateRootIdentity
                )
            guard confirmedSnapshot.metadataIdentity
                    == proposal.snapshot.metadataIdentity,
                  confirmedSnapshot.manifestData
                    == proposal.snapshot.manifestData,
                  confirmedSnapshot.portableStateData
                    == proposal.snapshot.portableStateData,
                  confirmedSnapshot.completionData
                    == proposal.snapshot.completionData else {
                throw CourseProjectRebindError.proposalChanged
            }
            guard let currentCourse = course(matching: proposal),
                  !courseHasUnstableState(currentCourse.id) else {
                throw CourseProjectRebindError.proposalChanged
            }
            guard !(try await registeredCourseRootIsAvailable(currentCourse)) else {
                throw CourseProjectRebindError.originalRootStillAvailable
            }
            guard course(matching: proposal) == currentCourse,
                  !courseHasUnstableState(currentCourse.id) else {
                throw CourseProjectRebindError.proposalChanged
            }
            let evaluation = try evaluatedCourseRebindState(
                existing: currentCourse,
                snapshot: confirmedSnapshot
            )
            let currentLocalState = try makeCoursePortableState(
                courseID: currentCourse.id,
                revision:
                    coursePortableStateRevisions[currentCourse.id] ?? 0,
                savedAt: Date(timeIntervalSince1970: 0)
            )
            guard try coursePortableStatePayloadDigest(currentLocalState)
                    == proposal.expectedLocalPayloadDigest else {
                throw CourseProjectRebindError.proposalChanged
            }
            guard let courseIndex = courses.firstIndex(where: {
                $0 == currentCourse
            }) else {
                throw CourseProjectRebindError.proposalChanged
            }

            let scopeKey = "course:\(proposal.courseID.uuidString)"
            let previousCourses = courses
            let previousImportedItems = importedItems
            let previousMemberships = courseItemMemberships
            let previousNoteSourceLinks = noteSourceLinks
            let previousStudyLocations = studyLocationsByCourseID
            let previousResumePoints = courseResumePoints
            let previousLearningMemoryStates = learningMemoryStates
            let previousCourseKnowledgeProfiles = courseKnowledgeProfiles
            let previousStudySessions = studySessions
            let previousActiveStudySessionID = activeStudySessionID
            let previousMessages = messages
            let previousNotesByItemID = notesByItemID
            let previousPendingNoteWrites = pendingNoteWritesByItemID
            let previousLoadedCourseNoteText =
                loadedCourseNoteTextByItemID
            let previousNoteText = noteText
            let previousNoteBackingDigests =
                noteBackingContentDigestsByItemID
            let previousLastSelfWrittenDigests =
                lastSelfWrittenNoteDigestsByItemID
            let previousPortableRevisions =
                coursePortableStateRevisions
            let previousPortableDigests = coursePortableStateDigests
            let previousDirtyPortableCourses = dirtyPortableCourseIDs
            let previousBlockedPortableCourses =
                blockedPortableCourseIDs
            let previousOversizedPortableCourses =
                oversizedPortableCourseIDs
            let previousPortableBootstrap =
                needsPortableCourseStateBootstrap
            let previousResolvedRoot =
                resolvedCourseRootURLs[proposal.courseID]
            let previousUnavailableReason =
                courseRootUnavailableReasons[proposal.courseID]
            let previousScope = activeCourseSecurityScopes[scopeKey]
            let previousScopeOwnerToken =
                activeCourseSecurityScopeOwnerTokens[scopeKey]
            var didStopPreviousScope = false

            func stopPreviousScopeIfNeeded() {
                guard !didStopPreviousScope,
                      let previousScope else {
                    return
                }
                didStopPreviousScope = true
                courseSecurityScopeStopper(previousScope)
            }

            var reboundCourse = currentCourse
            reboundCourse.sourceRootPath = nil
            reboundCourse.sourceRootRelativePath = libraryRelativePath
            reboundCourse.sourceRootIdentity =
                proposal.candidateRootIdentity
            reboundCourse.sourceRootBookmarkData = nil
            courses[courseIndex] = reboundCourse
            resolvedCourseRootURLs[proposal.courseID] = resolvedRoot
            courseRootUnavailableReasons.removeValue(
                forKey: proposal.courseID
            )
            if let newScopeURL {
                activeCourseSecurityScopes[scopeKey] = newScopeURL
                activeCourseSecurityScopeOwnerTokens[scopeKey] =
                    rebindToken
                shouldStopNewScopeOnFailure = false
            } else {
                activeCourseSecurityScopes.removeValue(forKey: scopeKey)
                activeCourseSecurityScopeOwnerTokens.removeValue(
                    forKey: scopeKey
                )
            }

            do {
                let reboundNoteItemIDs = Set(
                    evaluation.state.items.lazy.filter {
                        $0.isNotebookNote
                    }.map(\.itemID)
                ).union(
                    courseItemMemberships.lazy.filter {
                        $0.courseID == proposal.courseID
                    }.compactMap { membership in
                        self.importedItems.first {
                            $0.id == membership.itemID
                                && $0.isNotebookNote
                        }?.id
                    }
                )
                for itemID in reboundNoteItemIDs {
                    courseNoteLoadGenerationByItemID[
                        itemID,
                        default: 0
                    ] &+= 1
                    courseNoteLoadTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWriteTasksByItemID
                        .removeValue(forKey: itemID)?
                        .cancel()
                    courseNoteWritesInFlight.remove(itemID)
                    loadedCourseNoteTextByItemID.removeValue(
                        forKey: itemID
                    )
                }
                try applyCoursePortableState(
                    evaluation.state,
                    courseID: proposal.courseID
                )
                if let activeNotebookItemID,
                   reboundNoteItemIDs.contains(activeNotebookItemID) {
                    noteText = notesByItemID[activeNotebookItemID] ?? ""
                }
                coursePortableStateRevisions[proposal.courseID] =
                    evaluation.state.revision
                coursePortableStateDigests[proposal.courseID] =
                    evaluation.statePayloadDigest
                dirtyPortableCourseIDs.remove(proposal.courseID)
                blockedPortableCourseIDs.remove(proposal.courseID)
                oversizedPortableCourseIDs.remove(proposal.courseID)
                needsPortableCourseStateBootstrap =
                    !dirtyPortableCourseIDs.isEmpty
                guard await persistWorkspaceNow(
                    skippingPortableCourseIDs: [proposal.courseID]
                ) else {
                    throw CourseProjectRootError.workspaceSaveFailed
                }
            } catch {
                courses = previousCourses
                importedItems = previousImportedItems
                courseItemMemberships = previousMemberships
                noteSourceLinks = previousNoteSourceLinks
                studyLocationsByCourseID = previousStudyLocations
                courseResumePoints = previousResumePoints
                learningMemoryStates = previousLearningMemoryStates
                courseKnowledgeProfiles = previousCourseKnowledgeProfiles
                studySessions = previousStudySessions
                activeStudySessionID = previousActiveStudySessionID
                messages = previousMessages
                replaceNoteDrafts(previousNotesByItemID)
                pendingNoteWritesByItemID =
                    previousPendingNoteWrites
                loadedCourseNoteTextByItemID =
                    previousLoadedCourseNoteText
                noteText = previousNoteText
                noteBackingContentDigestsByItemID =
                    previousNoteBackingDigests
                lastSelfWrittenNoteDigestsByItemID =
                    previousLastSelfWrittenDigests
                coursePortableStateRevisions =
                    previousPortableRevisions
                coursePortableStateDigests = previousPortableDigests
                dirtyPortableCourseIDs =
                    previousDirtyPortableCourses
                blockedPortableCourseIDs =
                    previousBlockedPortableCourses
                oversizedPortableCourseIDs =
                    previousOversizedPortableCourses
                needsPortableCourseStateBootstrap =
                    previousPortableBootstrap
                if let previousResolvedRoot {
                    resolvedCourseRootURLs[proposal.courseID] =
                        previousResolvedRoot
                } else {
                    resolvedCourseRootURLs.removeValue(
                        forKey: proposal.courseID
                    )
                }
                if let previousUnavailableReason {
                    courseRootUnavailableReasons[proposal.courseID] =
                        previousUnavailableReason
                } else {
                    courseRootUnavailableReasons.removeValue(
                        forKey: proposal.courseID
                    )
                }
                if let previousScope {
                    activeCourseSecurityScopes[scopeKey] = previousScope
                } else {
                    activeCourseSecurityScopes.removeValue(
                        forKey: scopeKey
                    )
                }
                if let previousScopeOwnerToken {
                    activeCourseSecurityScopeOwnerTokens[scopeKey] =
                        previousScopeOwnerToken
                } else {
                    activeCourseSecurityScopeOwnerTokens.removeValue(
                        forKey: scopeKey
                    )
                }
                if let newScopeURL {
                    courseSecurityScopeStopper(newScopeURL)
                    shouldStopNewScopeOnFailure = false
                }
                throw error
            }

            try courseProjectMutationHook(
                .afterAdoptionWorkspaceSaveBeforeManifestNormalization
            )
            if confirmedSnapshot.manifest.portableExport != nil {
                do {
                    let finalSnapshot = try await courseProjectFileWorker
                        .adoptionSnapshot(
                            at: resolvedRoot,
                            expectedRootIdentity:
                                proposal.candidateRootIdentity
                        )
                    guard courseUsesRebindCandidate(
                        proposal,
                        resolvedRoot: resolvedRoot
                    ),
                    finalSnapshot.metadataIdentity
                            == confirmedSnapshot.metadataIdentity,
                          finalSnapshot.manifestData
                            == confirmedSnapshot.manifestData,
                          finalSnapshot.portableStateData
                            == confirmedSnapshot.portableStateData,
                          finalSnapshot.completionData
                            == confirmedSnapshot.completionData,
                          finalSnapshot.manifest.portableExport != nil else {
                        throw CourseProjectRebindError.proposalChanged
                    }
                    try await courseProjectFileWorker
                        .normalizePortableCourseManifest(
                            with: CourseProjectManifest(
                                courseID: proposal.courseID
                            ).encoded(),
                            at: resolvedRoot.appendingPathComponent(
                                ".weibei/course.json"
                            ),
                            expectedDirectoryIdentity:
                                finalSnapshot.metadataIdentity,
                            expectedPreviousData:
                                finalSnapshot.manifestData
                        )
                    guard courseUsesRebindCandidate(
                        proposal,
                        resolvedRoot: resolvedRoot
                    ) else {
                        throw CourseProjectRebindError.proposalChanged
                    }
                } catch {
                    if activeCourseRebindTokens[proposal.courseID]
                            == rebindToken,
                       courseUsesRebindCandidate(
                           proposal,
                           resolvedRoot: resolvedRoot
                       ) {
                        resolvedCourseRootURLs.removeValue(
                            forKey: proposal.courseID
                        )
                        courseRootUnavailableReasons[proposal.courseID] =
                            ui(
                                "课程文件夹仍在原位置，但重新连接未完成。请重新选择该文件夹后再试。",
                                "The course folder remains in its original location, but reconnection did not finish. Re-select the folder and try again."
                            )
                    }
                    if activeCourseSecurityScopeOwnerTokens[scopeKey]
                            == rebindToken,
                       let scopedURL =
                            activeCourseSecurityScopes.removeValue(
                                forKey: scopeKey
                            ) {
                        activeCourseSecurityScopeOwnerTokens.removeValue(
                            forKey: scopeKey
                        )
                        courseSecurityScopeStopper(scopedURL)
                    }
                    stopPreviousScopeIfNeeded()
                    cancelAgentRequestIfRunning(in: proposal.courseID)
                    invalidateAgentContext()
                    throw error
                }
            }

            guard await reconcileCourseFilesNow(
                courseID: proposal.courseID
            ) else {
                throw CourseProjectRootError.workspaceSaveFailed
            }

            stopPreviousScopeIfNeeded()
            if activeCourseSecurityScopeOwnerTokens[scopeKey]
                    == rebindToken {
                activeCourseSecurityScopeOwnerTokens.removeValue(
                    forKey: scopeKey
                )
            }
            courseDocumentSearchIndex.synchronize(allItems)
            invalidateAgentContext()
            shouldStopNewScopeOnFailure = false
            return proposal.courseID
        } catch {
            let scopeKey = "course:\(proposal.courseID.uuidString)"
            if activeCourseRebindTokens[proposal.courseID] == rebindToken,
               courseUsesRebindCandidate(
                   proposal,
                   resolvedRoot: resolvedRoot
               ) {
                resolvedCourseRootURLs.removeValue(
                    forKey: proposal.courseID
                )
                recordCourseLibraryUIFailure(
                    error,
                    operation: "confirm_course_rebind",
                    path: resolvedRoot
                )
                courseRootUnavailableReasons[proposal.courseID] = ui(
                    "课程文件夹仍在原位置，但重新连接未完成。请重新选择该文件夹后再试。",
                    "The course folder remains in its original location, but reconnection did not finish. Re-select the folder and try again."
                )
            }
            if activeCourseSecurityScopeOwnerTokens[scopeKey]
                    == rebindToken,
               let scopedURL =
                    activeCourseSecurityScopes.removeValue(
                        forKey: scopeKey
                    ) {
                activeCourseSecurityScopeOwnerTokens.removeValue(
                    forKey: scopeKey
                )
                courseSecurityScopeStopper(scopedURL)
            } else if shouldStopNewScopeOnFailure,
                      let newScopeURL {
                courseSecurityScopeStopper(newScopeURL)
            }
            throw error
        }
    }

    @discardableResult
    func importFileIntoCourse(
        _ sourceURL: URL,
        courseID: UUID,
        role: CourseOwnedFileRole,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws -> CourseOwnedFileImportResult {
        let sourceInfo: CourseFileSourceInfo
        do {
            sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        } catch {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        return try await transactCourseOwnedFile(
            courseID: courseID,
            role: role,
            fileName: sourceInfo.url.lastPathComponent,
            sourceURL: sourceInfo.url,
            sourceIdentity: sourceInfo.identity,
            generatedData: nil,
            conflictResolution: conflictResolution
        )
    }

    /// Synchronous bridge used only by the executable self-check harness.
    /// The run loop keeps servicing the main actor while all file work stays on the worker actor.
    @discardableResult
    func importFileIntoCourseForSelfCheck(
        _ sourceURL: URL,
        courseID: UUID,
        role: CourseOwnedFileRole,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws -> CourseOwnedFileImportResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return try waitForCourseFileOperation {
            try await self.importFileIntoCourse(
                sourceURL,
                courseID: courseID,
                role: role,
                conflictResolution: conflictResolution
            )
        }
    }

    @discardableResult
    func migrateLegacyExternalItemIntoCourse(
        itemID: String,
        courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws -> CourseOwnedFileImportResult {
        guard let item = importedItems.first(where: { $0.id == itemID }),
              item.storage == .common(relativePath: ""),
              let sourceURL = item.url else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        return try await transactCourseOwnedFile(
            courseID: courseID,
            role: CourseOwnedFileRole(item: item),
            fileName: sourceInfo.url.lastPathComponent,
            sourceURL: sourceInfo.url,
            sourceIdentity: sourceInfo.identity,
            generatedData: nil,
            conflictResolution: conflictResolution,
            preservingItemID: itemID
        )
    }

    @discardableResult
    func moveCourseOwnedItem(
        itemID: String,
        toCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws -> CourseOwnedFileImportResult {
        guard let item = importedItems.first(where: { $0.id == itemID }),
              case .courseOwned(let ownerCourseID, _) = item.storage,
              ownerCourseID != courseID,
              let sourceURL = item.url else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        return try await transactCourseOwnedFile(
            courseID: courseID,
            role: CourseOwnedFileRole(item: item),
            fileName: sourceInfo.url.lastPathComponent,
            sourceURL: sourceInfo.url,
            sourceIdentity: sourceInfo.identity,
            generatedData: nil,
            conflictResolution: conflictResolution,
            preservingItemID: itemID,
            additionalCourseIDs: [ownerCourseID]
        )
    }

    func shareCourseOwnedItem(
        itemID: String,
        withCourseID addedCourseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) async throws {
        guard activeCourseRemovalTokens[addedCourseID] == nil else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard conflictResolution != .replace else {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        guard let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }) else {
            throw CourseOwnedFileError.unsupportedFile
        }
        let role = CourseOwnedFileRole(item: importedItems[itemIndex])
        if case .common = importedItems[itemIndex].storage {
            try await linkSharedItem(
                itemID: itemID,
                toCourseID: addedCourseID,
                conflictResolution: conflictResolution
            )
            return
        }
        guard case .courseOwned(let ownerCourseID, _) = importedItems[itemIndex].storage,
              activeCourseRemovalTokens[ownerCourseID] == nil,
              ownerCourseID != addedCourseID,
              let ownerRoot = courseRootURL(for: ownerCourseID),
              let addedRoot = courseRootURL(for: addedCourseID),
              let ownerMembershipIndex = uniqueCourseOwnedMembershipIndex(
                itemID: itemID,
                courseID: ownerCourseID
              ),
              let sourceRelativePath = courseItemMemberships[ownerMembershipIndex].courseRelativePath,
              let sourceURL = safeCourseOwnedFileURL(
                relativePath: sourceRelativePath,
                role: role,
                inside: ownerRoot
              ),
              let libraryRoot = courseLibraryRootURL else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        let affectedCourseIDs: Set<UUID> = [
            ownerCourseID,
            addedCourseID,
        ]
        let affectedItemIDs: Set<String> = [itemID]
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: affectedItemIDs
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: affectedItemIDs
            )
        }
        let sourceInfo = try await courseProjectFileWorker.validatedRegularSource(sourceURL)
        let sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sourceInfo.url,
            expectedIdentity: sourceInfo.identity
        )
        let sharedDirectory = try await courseProjectFileWorker.ensureRealDirectory(
            libraryRoot.appendingPathComponent(
                role.commonDirectoryName,
                isDirectory: true
            ),
            inside: libraryRoot
        )
        let sharedTarget = try resolvedCourseImportTarget(
            fileName: sourceURL.lastPathComponent,
            destinationDirectory: sharedDirectory,
            role: role,
            conflictResolution: conflictResolution
        )
        if FileManager.default.fileExists(atPath: sharedTarget.path) {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        let addedDirectory = try await courseProjectFileWorker.ensureRealDirectory(
            addedRoot.appendingPathComponent(
                role.directoryName,
                isDirectory: true
            ),
            inside: addedRoot
        )
        let addedLinkURL = try resolvedCourseImportTarget(
            fileName: sharedTarget.lastPathComponent,
            destinationDirectory: addedDirectory,
            role: role,
            conflictResolution: conflictResolution == .replace ? .cancel : conflictResolution
        )
        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: ownerRoot
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(transactionDirectory),
              let sharedDirectoryIdentity = importedFileIdentityResolver(sharedDirectory) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let payloadURL = sharedDirectory.appendingPathComponent(
            ".\(sharedTarget.lastPathComponent).weibei-share-stage-\(transactionID.uuidString.lowercased())"
        )
        let preparedOwnerLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-owner-link"
        )
        let preparedAddedLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-added-link"
        )
        let ownerDirectory = sourceURL.deletingLastPathComponent()
        guard let libraryRootIdentity = CourseProjectFileWorker.identity(at: libraryRoot),
              let ownerRootIdentity = CourseProjectFileWorker.identity(at: ownerRoot),
              let addedRootIdentity = CourseProjectFileWorker.identity(at: addedRoot),
              let ownerDirectoryIdentity = CourseProjectFileWorker.identity(
                at: ownerDirectory
              ),
              let addedDirectoryIdentity = CourseProjectFileWorker.identity(
                at: addedDirectory
              ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let sourceQuarantineURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(sourceURL.lastPathComponent).weibei-share-\(transactionID.uuidString.lowercased())"
            )
        let sharedRelativePath = CourseProjectPathPolicy.relativePath(
            of: sharedTarget,
            inside: libraryRoot
        ) ?? "\(role.commonDirectoryName)/\(sharedTarget.lastPathComponent)"
        let addedRelativePath = CourseProjectPathPolicy.relativePath(
            of: addedLinkURL,
            inside: addedRoot
        ) ?? "\(role.directoryName)/\(addedLinkURL.lastPathComponent)"
        var sharedIdentity: ImportedFileIdentity?
        var ownerLinkIdentity: ImportedFileIdentity?
        var addedLinkIdentity: ImportedFileIdentity?
        var workspaceCommitted = false
        let previousItems = importedItems
        let previousMemberships = courseItemMemberships
        func revalidatedSharedArtifacts(
            sharedIdentity: ImportedFileIdentity,
            ownerLinkIdentity: ImportedFileIdentity,
            addedLinkIdentity: ImportedFileIdentity
        ) async throws -> CourseFileSourceInfo {
            guard CourseProjectFileWorker.identity(at: libraryRoot)
                    == libraryRootIdentity,
                  CourseProjectFileWorker.identity(at: ownerRoot)
                    == ownerRootIdentity,
                  CourseProjectFileWorker.identity(at: addedRoot)
                    == addedRootIdentity,
                  CourseProjectFileWorker.identity(at: sharedDirectory)
                    == sharedDirectoryIdentity,
                  CourseProjectFileWorker.identity(at: ownerDirectory)
                    == ownerDirectoryIdentity,
                  CourseProjectFileWorker.identity(at: addedDirectory)
                    == addedDirectoryIdentity,
                  CourseProjectPathPolicy.isSame(
                    sharedDirectory,
                    sharedDirectory.resolvingSymlinksInPath()
                  ),
                  CourseProjectPathPolicy.isSame(
                    ownerDirectory,
                    ownerDirectory.resolvingSymlinksInPath()
                  ),
                  CourseProjectPathPolicy.isSame(
                    addedDirectory,
                    addedDirectory.resolvingSymlinksInPath()
                  ),
                  CourseProjectFileWorker.identity(at: sourceURL)
                    == ownerLinkIdentity,
                  CourseProjectFileWorker.symbolicLink(
                    at: sourceURL,
                    pointsTo: sharedTarget
                  ),
                  CourseProjectFileWorker.identity(at: addedLinkURL)
                    == addedLinkIdentity,
                  CourseProjectFileWorker.symbolicLink(
                    at: addedLinkURL,
                    pointsTo: sharedTarget
                  ) else {
                throw CourseOwnedFileError.verificationFailed
            }
            return try await courseProjectFileWorker.stableMetadata(
                at: sharedTarget,
                expectedIdentity: sharedIdentity,
                expectedSnapshot: sourceSnapshot
            )
        }
        do {
            // S3：无 journal。复制到共享位 → 隔离源 → 放链接 → 保存。
            let stagedIdentity = try await courseProjectFileWorker.copyAndVerify(
                from: sourceURL,
                generatedData: nil,
                to: payloadURL,
                expectedSnapshot: sourceSnapshot
            )
            sharedIdentity = stagedIdentity
            try courseProjectMutationHook(
                .afterSharedSameVolumeStagingJournal
            )
            let placedSharedIdentity = try await courseProjectFileWorker.placeWithoutReplacement(
                from: payloadURL,
                to: sharedTarget,
                courseRoot: libraryRoot,
                destinationDirectory: sharedDirectory,
                expectedDestinationIdentity: sharedDirectoryIdentity,
                expectedSnapshot: sourceSnapshot
            )
            try courseProjectMutationHook(.afterSharedFilePlacementBeforeJournal)
            guard stagedIdentity == placedSharedIdentity,
                  await courseProjectFileWorker.isolateWithoutReplacement(
                    from: sourceURL,
                    to: sourceQuarantineURL
                  ) else {
                throw CourseOwnedFileError.verificationFailed
            }
            try courseProjectMutationHook(.afterSharedSourceIsolationBeforeJournal)
            _ = try await courseProjectFileWorker.stableSnapshot(
                at: sourceQuarantineURL,
                expectedIdentity: sourceInfo.identity,
                expectedSnapshot: sourceSnapshot
            )
            sharedIdentity = placedSharedIdentity
            let preparedOwner = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedOwnerLinkURL,
                destinationURL: sharedTarget
            )
            try courseProjectMutationHook(
                .afterSharedOwnerLinkPrepareBeforeJournalIdentity
            )
            ownerLinkIdentity = preparedOwner
            let preparedAdded = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedAddedLinkURL,
                destinationURL: sharedTarget
            )
            try courseProjectMutationHook(
                .afterSharedAddedLinkPrepareBeforeJournalIdentity
            )
            addedLinkIdentity = preparedAdded
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedOwnerLinkURL,
                to: sourceURL,
                destinationURL: sharedTarget,
                allowedRoot: ownerRoot,
                expectedIdentity: preparedOwner
            )
            try courseProjectMutationHook(.afterSharedOwnerLinkPlacementBeforeJournal)
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedAddedLinkURL,
                to: addedLinkURL,
                destinationURL: sharedTarget,
                allowedRoot: addedRoot,
                expectedIdentity: preparedAdded
            )
            try courseProjectMutationHook(.afterSharedAddedLinkPlacementBeforeJournal)

            let sharedInfo = try await revalidatedSharedArtifacts(
                sharedIdentity: placedSharedIdentity,
                ownerLinkIdentity: preparedOwner,
                addedLinkIdentity: preparedAdded
            )
            importedItems[itemIndex].urlPath = sharedTarget.path
            importedItems[itemIndex].importedFileIdentity = placedSharedIdentity
            importedItems[itemIndex].storage = .common(
                relativePath: sharedRelativePath
            )
            importedItems[itemIndex].fileByteCount = sharedInfo.byteCount
            importedItems[itemIndex].fileModificationTimeNanoseconds =
                sharedInfo.modificationTimeNanoseconds
            courseItemMemberships[ownerMembershipIndex].entryIdentity = preparedOwner
            courseItemMemberships[ownerMembershipIndex].documentIdentifier = nil
            courseItemMemberships.append(
                CourseItemMembership(
                    courseID: addedCourseID,
                    itemID: itemID,
                    courseRelativePath: addedRelativePath,
                    entryIdentity: preparedAdded,
                    documentIdentifier: nil
                )
            )
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            workspaceCommitted = true
            try courseProjectMutationHook(
                .afterSharedWorkspaceSaveBeforeSourceCleanup
            )
            if (try? await revalidatedSharedArtifacts(
                sharedIdentity: placedSharedIdentity,
                ownerLinkIdentity: preparedOwner,
                addedLinkIdentity: preparedAdded
            )) != nil {
                let cleanup = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                        at: sourceQuarantineURL,
                        quarantineURL: transactionDirectory
                            .appendingPathComponent("source-cleanup"),
                        expectedIdentity: sourceInfo.identity,
                        expectedSnapshot: sourceSnapshot,
                        remover: { try FileManager.default.removeItem(at: $0) }
                    )
                if case .removed = cleanup {
                    try courseProjectMutationHook(
                        .afterSharedSourceCleanupBeforeTransactionCleanup
                    )
                    await safelyRemoveSharedTransactionDirectoryInBackground(
                        transactionDirectory,
                        expectedIdentity: transactionDirectoryIdentity
                    )
                }
            }
            courseDocumentSearchIndex.schedule([importedItems[itemIndex]])
            invalidateAgentContext()
        } catch {
            if workspaceCommitted {
                // 登记已提交：绝不回滚共享原件与成员关系（S3 无 journal 补完）。
                // 尽力清事务目录；源隔离残留留给用户/下次操作。
                await safelyRemoveSharedTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
                throw error
            }
            // 提交前失败：回滚内存与半完成共享产物。
            importedItems = previousItems
            courseItemMemberships = previousMemberships
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: addedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "added-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: addedLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: sourceURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "owner-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: ownerLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedAddedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-added-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: addedLinkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedOwnerLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-owner-link-cleanup"
                ),
                destinationURL: sharedTarget,
                expectedIdentity: ownerLinkIdentity
            )
            if !FileManager.default.fileExists(atPath: sourceURL.path) {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: sourceQuarantineURL,
                    to: sourceURL
                )
            }
            if let sharedIdentity {
                _ = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                    at: sharedTarget,
                    quarantineURL: sharedDirectory.appendingPathComponent(
                        ".\(sharedTarget.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                    ),
                    expectedIdentity: sharedIdentity,
                    expectedSnapshot: sourceSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
                _ = await courseProjectFileWorker
                    .isolateAndRemoveVerifiedFile(
                    at: payloadURL,
                    quarantineURL: sharedDirectory.appendingPathComponent(
                        ".\(payloadURL.lastPathComponent).weibei-cleanup-\(UUID().uuidString.lowercased())"
                    ),
                    expectedIdentity: sharedIdentity,
                    expectedSnapshot: sourceSnapshot,
                    remover: { try FileManager.default.removeItem(at: $0) }
                )
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            throw error
        }
    }

    private func linkSharedItem(
        itemID: String,
        toCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution
    ) async throws {
        let affectedCourseIDs: Set<UUID> = [courseID]
        let affectedItemIDs: Set<String> = [itemID]
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: affectedItemIDs
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: affectedItemIDs
            )
        }
        guard conflictResolution != .replace else {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        guard let itemIndex = importedItems.firstIndex(where: { $0.id == itemID }),
              case .common(let sharedRelativePath) = importedItems[itemIndex].storage,
              let sharedURL = importedItems[itemIndex].url,
              let courseRoot = courseRootURL(for: courseID),
              let libraryRoot = courseLibraryRootURL,
              let expectedSharedURL = CourseProjectPathPolicy.resolvedRelativePath(
                sharedRelativePath,
                inside: libraryRoot
              ),
              CourseProjectPathPolicy.isSame(expectedSharedURL, sharedURL) else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        let role = CourseOwnedFileRole(item: importedItems[itemIndex])
        let allowedSharedDirectories: Set<Substring> = role == .note
            ? [Substring(role.commonDirectoryName)]
            : [Substring(role.commonDirectoryName), "共享文稿"]
        let sharedComponents = sharedRelativePath.split(separator: "/")
        guard sharedComponents.count == 2,
              allowedSharedDirectories.contains(sharedComponents[0]),
              sharedComponents[1] == Substring(sharedURL.lastPathComponent) else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        if courseItemMemberships.contains(where: {
            $0.courseID == courseID && $0.itemID == itemID
                && $0.courseRelativePath != nil
        }) {
            return
        }
        // 纯归属兜底登记（无 courseRelativePath）不幂等返回：继续走链接流程，
        // 成功后原地补全链接条目。
        let sharedInfo = try await courseProjectFileWorker.validatedRegularSource(
            expectedSharedURL
        )
        let sharedSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sharedInfo.url,
            expectedIdentity: sharedInfo.identity
        )
        if importedItems[itemIndex].contentDigest == nil {
            // 新建的共享笔记还没有内容摘要；可携带状态校验要求 sharedReference
            // 带 SHA256 摘要，缺失会让写回校验失败并回滚整个链接登记。
            importedItems[itemIndex].contentDigest = sharedSnapshot.sha256
        }
        let materialDirectory = try await courseProjectFileWorker.ensureRealDirectory(
            courseRoot.appendingPathComponent(
                role.directoryName,
                isDirectory: true
            ),
            inside: courseRoot
        )
        let linkURL = try resolvedCourseImportTarget(
            fileName: sharedURL.lastPathComponent,
            destinationDirectory: materialDirectory,
            role: role,
            conflictResolution: conflictResolution == .replace ? .cancel : conflictResolution
        )
        guard let linkRelativePath = CourseProjectPathPolicy.relativePath(
            of: linkURL,
            inside: courseRoot
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: courseRoot
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(
            transactionDirectory
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let preparedLinkURL = transactionDirectory.appendingPathComponent(
            "prepared-link"
        )
        var linkIdentity: ImportedFileIdentity?
        let previousMemberships = courseItemMemberships
        do {
            // S3：无 journal。
            let preparedIdentity = try await courseProjectFileWorker.prepareSymbolicLink(
                at: preparedLinkURL,
                destinationURL: expectedSharedURL
            )
            linkIdentity = preparedIdentity
            try courseProjectMutationHook(
                .afterSharedLinkPrepareBeforeJournalIdentity
            )
            try await courseProjectFileWorker.placePreparedSymbolicLink(
                from: preparedLinkURL,
                to: linkURL,
                destinationURL: expectedSharedURL,
                allowedRoot: courseRoot,
                expectedIdentity: preparedIdentity
            )
            try courseProjectMutationHook(.afterSharedLinkPlacementBeforeJournal)
            if let fallbackIndex = courseItemMemberships.firstIndex(where: {
                $0.courseID == courseID && $0.itemID == itemID
                    && $0.courseRelativePath == nil
            }) {
                courseItemMemberships[fallbackIndex].courseRelativePath =
                    linkRelativePath
                courseItemMemberships[fallbackIndex].entryIdentity =
                    preparedIdentity
            } else {
                courseItemMemberships.append(
                    CourseItemMembership(
                        courseID: courseID,
                        itemID: itemID,
                        courseRelativePath: linkRelativePath,
                        entryIdentity: preparedIdentity
                    )
                )
            }
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            invalidateAgentContext()
        } catch {
            // S3：无 journal 恢复；崩溃注入也必须走回滚。
            courseItemMemberships = previousMemberships
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: linkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "link-cleanup"
                ),
                destinationURL: expectedSharedURL,
                expectedIdentity: linkIdentity
            )
            _ = await courseProjectFileWorker.isolateAndRemoveSymbolicLinkIfMatching(
                at: preparedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "prepared-link-cleanup"
                ),
                destinationURL: expectedSharedURL,
                expectedIdentity: linkIdentity
            )
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            throw error
        }
    }

    func courseFileSnapshotRunsOffMainForSelfCheck(_ url: URL) throws -> Bool {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let evidence = try waitForCourseFileOperation {
            try await self.courseProjectFileWorker.snapshotWithThreadEvidence(at: url)
        }
        return evidence.snapshot.byteCount > 0 && !evidence.ranOnMainThread
    }

    func portableAdoptionReadRunsOffMainForSelfCheck() -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return lastPortableAdoptionReadRanOnMainThread == false
    }

    func migrateLegacyExternalItemForSelfCheck(
        itemID: String,
        courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws -> CourseOwnedFileImportResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return try waitForCourseFileOperation {
            try await self.migrateLegacyExternalItemIntoCourse(
                itemID: itemID,
                courseID: courseID,
                conflictResolution: conflictResolution
            )
        }
    }

    func moveCourseOwnedItemForSelfCheck(
        itemID: String,
        toCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws -> CourseOwnedFileImportResult {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        return try waitForCourseFileOperation {
            try await self.moveCourseOwnedItem(
                itemID: itemID,
                toCourseID: courseID,
                conflictResolution: conflictResolution
            )
        }
    }

    func shareCourseOwnedItemForSelfCheck(
        itemID: String,
        withCourseID courseID: UUID,
        conflictResolution: CourseFileConflictResolution = .cancel,
        usesBackgroundWorkspacePersistence: Bool = false,
        requiringUnchangedCourseID: UUID? = nil
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
#if DEBUG
        let previousPersistenceMode =
            usesBackgroundWorkspacePersistenceForSelfCheck
        usesBackgroundWorkspacePersistenceForSelfCheck =
            usesBackgroundWorkspacePersistence
        defer {
            usesBackgroundWorkspacePersistenceForSelfCheck =
                previousPersistenceMode
        }
#endif
        let additionalRequiredCourseIDs = requiringUnchangedCourseID.map { Set([$0]) } ?? []
        try waitForCourseFileOperation {
            if !additionalRequiredCourseIDs.isEmpty {
                try self.beginCourseFileMutation(courseIDs: additionalRequiredCourseIDs)
            }
            defer { self.finishCourseFileMutation(courseIDs: additionalRequiredCourseIDs) }
            try await self.shareCourseOwnedItem(
                itemID: itemID,
                withCourseID: courseID,
                conflictResolution: conflictResolution
            )
        }
    }

    func transactCourseOwnedFile(
        courseID: UUID,
        role: CourseOwnedFileRole,
        fileName: String,
        sourceURL: URL?,
        sourceIdentity: ImportedFileIdentity?,
        generatedData: Data?,
        conflictResolution: CourseFileConflictResolution = .cancel,
        preservingItemID: String? = nil,
        additionalCourseIDs: Set<UUID> = []
    ) async throws -> CourseOwnedFileImportResult {
        let affectedCourseIDs = additionalCourseIDs.union([courseID])
        let affectedItemIDs = preservingItemID.map {
            Set([$0])
        } ?? []
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: affectedItemIDs
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: affectedItemIDs
            )
        }
        guard let root = courseRootURL(for: courseID),
              let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(root),
              let canonicalRootIdentity = importedFileIdentityResolver(canonicalRoot) else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        if let sourceURL, CourseProjectPathPolicy.contains(canonicalRoot, sourceURL) {
            throw CourseOwnedFileError.sourceAlreadyInsideCourse
        }
        guard isSupportedCourseFileName(fileName, role: role) else {
            throw CourseOwnedFileError.unsupportedFile
        }

        let destinationDirectory = try courseOwnedDestinationDirectory(
            role: role,
            inside: canonicalRoot
        )
        guard let destinationDirectoryIdentity = importedFileIdentityResolver(destinationDirectory) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let targetURL = try resolvedCourseImportTarget(
            fileName: fileName,
            destinationDirectory: destinationDirectory,
            role: role,
            conflictResolution: conflictResolution
        )
        guard CourseProjectPathPolicy.contains(destinationDirectory, targetURL, includingRoot: false),
              CourseProjectPathPolicy.contains(canonicalRoot, targetURL, includingRoot: false) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let replacingItemIndex = try replacementItemIndex(
            at: targetURL,
            courseID: courseID,
            conflictResolution: conflictResolution
        )
        let replacesExistingTarget = conflictResolution == .replace
            && FileManager.default.fileExists(atPath: targetURL.path)
        guard let targetRelativePath = CourseProjectPathPolicy.relativePath(
            of: targetURL,
            inside: canonicalRoot
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let sourceSnapshot: CourseFileSnapshot
        if let sourceURL, let sourceIdentity {
            do {
                sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
                    at: sourceURL,
                    expectedIdentity: sourceIdentity
                )
            } catch {
                throw CourseOwnedFileError.sourceIdentityChanged
            }
        } else if let generatedData {
            sourceSnapshot = await courseProjectFileWorker.snapshot(of: generatedData)
        } else {
            throw CourseOwnedFileError.verificationFailed
        }

        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: canonicalRoot
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(transactionDirectory) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let payloadURL = transactionDirectory.appendingPathComponent("payload", isDirectory: false)
        let sourceQuarantineURL = sourceURL.map {
            $0.deletingLastPathComponent().appendingPathComponent(
                ".\($0.lastPathComponent).weibei-quarantine-\(transactionID.uuidString.lowercased())",
                isDirectory: false
            )
        }
        let replacementTargetItemID = replacingItemIndex.map { importedItems[$0].id }
        let itemID = replacementTargetItemID
            ?? preservingItemID
            ?? Self.makeImportedItemID()
        let retiredSourceItemID = preservingItemID.flatMap { sourceItemID in
            replacementTargetItemID != nil && replacementTargetItemID != sourceItemID
                ? sourceItemID
                : nil
        }
        // S3：本地跟踪字段代替 journal 阶段机。
        var stagedIdentity: ImportedFileIdentity?
        var placedTargetIdentity: ImportedFileIdentity?
        var replacedTargetIdentity: ImportedFileIdentity?
        var replacedTargetSnapshot: CourseFileSnapshot?
        var replacedRollbackIdentity: ImportedFileIdentity?
        var replacedTrashPath: String?
        let previousImportedItems = importedItems
        let previousMemberships = courseItemMemberships
        let previousNotes = notesByItemID
        let previousPendingNoteWrites = pendingNoteWritesByItemID
        let previousBackingDigests = noteBackingContentDigestsByItemID
        let previousLastSelfWrittenDigests = lastSelfWrittenNoteDigestsByItemID
        let previousLoadedCourseNotes = loadedCourseNoteTextByItemID
        let previousSelectedItemID = selectedItemID
        let previousActiveNotebookItemID = activeNotebookItemID
        let previousCourseWorkspaceTargetItemID = courseWorkspaceTargetItemID
        let previousNoteSourceLinks = noteSourceLinks
        let previousStudyLocations = studyLocationsByItemID
        let previousCourseStudyLocations = studyLocationsByCourseID
        let previousStudySessions = studySessions
        let previousSelectionAskThreads = selectionAskThreads
        let previousNotebookCreationDraft = notebookCreationDraft
        let previousNotebookRenameDraft = notebookRenameDraft
        let previousPendingNotePersistence = pendingNotePersistenceByItemID
        let previousBackNavigationStack = backNavigationStack
        let previousForwardNavigationStack = forwardNavigationStack
        var workspaceCommitted = false
        let replacementQuarantineURL = transactionDirectory.appendingPathComponent(
            "replaced-target",
            isDirectory: false
        )
        let replacementRollbackURL = transactionDirectory.appendingPathComponent(
            "replacement-rollback",
            isDirectory: false
        )

        do {
            try courseProjectMutationHook(.beforeCourseFileStagingCopy)
            stagedIdentity = try await courseProjectFileWorker.copyAndVerify(
                from: sourceURL,
                generatedData: generatedData,
                to: payloadURL,
                expectedSnapshot: sourceSnapshot
            )
            try courseProjectMutationHook(.afterCourseFileStagingCopy)

            if let sourceURL, let sourceIdentity {
                do {
                    _ = try await courseProjectFileWorker.stableSnapshot(
                        at: sourceURL,
                        expectedIdentity: sourceIdentity,
                        expectedSnapshot: sourceSnapshot
                    )
                } catch {
                    throw CourseOwnedFileError.sourceIdentityChanged
                }
            }
            if replacesExistingTarget {
                // 覆盖前：笔记入备份环；目标隔离进废纸篓。
                if role == .note {
                    do {
                        _ = try NoteBackupRing.capture(
                            sourceURL: targetURL,
                            itemID: itemID,
                            rootURL: noteBackupRootURL
                        )
                    } catch {
                        WeiBeiLog.noteRepair.error(
                            "code=note_backup_failed path=\(targetURL.path, privacy: .private) reason=\(error.localizedDescription, privacy: .private)"
                        )
                        throw CourseOwnedFileError.backupFailed
                    }
                }
                guard let replacementIdentity = importedFileIdentityResolver(targetURL) else {
                    throw CourseOwnedFileError.targetConflict(targetURL)
                }
                let replacementSnapshot = try await courseProjectFileWorker.stableSnapshot(
                    at: targetURL,
                    expectedIdentity: replacementIdentity
                )
                replacedTargetIdentity = replacementIdentity
                replacedTargetSnapshot = replacementSnapshot
                let rollbackIdentity = try await courseProjectFileWorker.reserveRollbackFile(
                    at: replacementRollbackURL
                )
                try courseProjectMutationHook(
                    .afterCourseFileRollbackArtifactCreationBeforeJournalIdentity
                )
                replacedRollbackIdentity = rollbackIdentity
                guard await courseProjectFileWorker.isolateWithoutReplacement(
                    from: targetURL,
                    to: replacementQuarantineURL
                ) else {
                    throw CourseOwnedFileError.targetConflict(targetURL)
                }
                try courseProjectMutationHook(
                    .afterCourseFileReplacementIsolationBeforeJournal
                )
                _ = try await courseProjectFileWorker.stableSnapshot(
                    at: replacementQuarantineURL,
                    expectedIdentity: replacementIdentity,
                    expectedSnapshot: replacementSnapshot
                )
                try await courseProjectFileWorker.fillReservedRollbackFile(
                    from: replacementQuarantineURL,
                    to: replacementRollbackURL,
                    expectedDestinationIdentity: rollbackIdentity,
                    expectedSnapshot: replacementSnapshot
                )
                try courseProjectMutationHook(
                    .afterCourseFileReplacementRollbackCopyBeforeJournal
                )
                let trashURL = try await courseProjectFileWorker
                    .moveReplacedFileToTrash(
                        at: replacementQuarantineURL,
                        selfCheckDestination: transactionDirectory
                            .appendingPathComponent("trashed-replaced-target")
                    )
                _ = try await courseProjectFileWorker.stableSnapshot(
                    at: trashURL,
                    expectedIdentity: replacementIdentity,
                    expectedSnapshot: replacementSnapshot
                )
                try courseProjectMutationHook(
                    .afterCourseFileReplacementTrashMoveBeforeJournal
                )
                replacedTrashPath = trashURL.path
                try courseProjectMutationHook(.afterCourseFileReplacementTrashed)
            }
            try courseProjectMutationHook(.beforeCourseFileAtomicPlacement)
            let targetIdentity: ImportedFileIdentity
            do {
                targetIdentity = try await courseProjectFileWorker.placeWithoutReplacement(
                    from: payloadURL,
                    to: targetURL,
                    courseRoot: canonicalRoot,
                    destinationDirectory: destinationDirectory,
                    expectedDestinationIdentity: destinationDirectoryIdentity,
                    expectedSnapshot: sourceSnapshot,
                    beforeRename: {
                        try self.courseProjectMutationHook(
                            .afterCourseFileDestinationValidationBeforeRename
                        )
                    }
                )
            } catch CourseProjectFileWorkerError.targetExists {
                throw CourseOwnedFileError.targetConflict(targetURL)
            } catch {
                throw CourseOwnedFileError.verificationFailed
            }
            try courseProjectMutationHook(.afterCourseFileAtomicPlacement)

            let resolvedTarget = targetURL.resolvingSymlinksInPath().standardizedFileURL
            guard CourseProjectPathPolicy.isSame(targetURL, resolvedTarget),
                  CourseProjectPathPolicy.contains(destinationDirectory, resolvedTarget, includingRoot: false),
                  CourseProjectPathPolicy.contains(canonicalRoot, resolvedTarget, includingRoot: false),
                  targetIdentity == stagedIdentity else {
                throw CourseOwnedFileError.verificationFailed
            }
            placedTargetIdentity = targetIdentity
            _ = try await revalidatedCourseFileTargetInBackground(
                courseID: courseID,
                expectedRoot: canonicalRoot,
                expectedRootIdentity: canonicalRootIdentity,
                role: role,
                expectedDestinationIdentity: destinationDirectoryIdentity,
                targetURL: resolvedTarget,
                expectedIdentity: targetIdentity,
                expectedSnapshot: sourceSnapshot
            )

            let targetInfo = try await courseProjectFileWorker.metadata(at: resolvedTarget)
            if let retiredSourceItemID {
                replaceItemIDEverywhere(retiredSourceItemID, with: itemID)
                importedItems.removeAll { $0.id == retiredSourceItemID }
            }
            let itemStorage = StudyItemStorage.courseOwned(ownerCourseID: courseID, relativePath: targetRelativePath)
            let existingItemIndex = importedItems.firstIndex { $0.id == itemID }
                ?? importedItems.firstIndex { $0.storage == itemStorage }
            let committedItemID = existingItemIndex.map { importedItems[$0].id } ?? itemID
            let previousItem = existingItemIndex.map { importedItems[$0] }
            let detectedKind = StudyItemKind.detect(from: resolvedTarget)
            var item = StudyItem(
                id: committedItemID,
                title: resolvedTarget.deletingPathExtension().lastPathComponent,
                subtitle: resolvedTarget.lastPathComponent,
                kind: detectedKind,
                urlPath: resolvedTarget.path,
                importedFileIdentity: targetIdentity,
                isSample: false,
                isNotebookNote: role == .note || detectedKind == .markdown,
                appearsInMaterials: role == .material,
                storage: itemStorage,
                contentRevision: replacingItemIndex == nil
                    ? (previousItem?.contentRevision ?? 1)
                    : (previousItem?.contentRevision ?? 0) &+ 1,
                contentDigest: sourceSnapshot.sha256,
                fileByteCount: targetInfo.byteCount,
                fileModificationTimeNanoseconds: targetInfo.modificationTimeNanoseconds
            )
            let membership = CourseItemMembership(
                courseID: courseID,
                itemID: committedItemID,
                courseRelativePath: targetRelativePath,
                entryIdentity: targetIdentity,
                documentIdentifier: targetInfo.identity == targetIdentity
                    ? courseFileDocumentIdentifier(at: resolvedTarget)
                    : nil
            )
            if let existingItemIndex {
                item.id = importedItems[existingItemIndex].id
                importedItems[existingItemIndex] = item
                courseItemMemberships.removeAll { $0.itemID == item.id }
            } else {
                importedItems.append(item)
            }
            courseItemMemberships.append(membership)
            if role == .note {
                noteBackingContentDigestsByItemID[committedItemID] = sourceSnapshot.sha256
            }
            try courseProjectMutationHook(.beforeCourseFileWorkspaceSave)
            _ = try await revalidatedCourseFileTargetInBackground(
                courseID: courseID,
                expectedRoot: canonicalRoot,
                expectedRootIdentity: canonicalRootIdentity,
                role: role,
                expectedDestinationIdentity: destinationDirectoryIdentity,
                targetURL: resolvedTarget,
                expectedIdentity: targetIdentity,
                expectedSnapshot: sourceSnapshot
            )
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            workspaceCommitted = true

            var sourceCleanupPending = false
            if let rollbackIdentity = replacedRollbackIdentity,
               let replacedSnapshot = replacedTargetSnapshot {
                do {
                    try await courseProjectFileWorker.removeVerifiedFile(
                        at: replacementRollbackURL,
                        expectedIdentity: rollbackIdentity,
                        expectedSnapshot: replacedSnapshot,
                        beforeRemoval: {
                            try self.courseProjectMutationHook(
                                .afterCourseFileCleanupValidationBeforeIsolation
                            )
                        }
                    )
                } catch {
                    sourceCleanupPending = true
                }
            }
            if let replacedTrashPath {
                do {
                    try await courseProjectFileWorker.finishSelfCheckTrash(
                        at: URL(fileURLWithPath: replacedTrashPath)
                    )
                } catch {
                    sourceCleanupPending = true
                }
            }
            if !sourceCleanupPending {
                await safelyRemoveCourseFileTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
            }
            courseDocumentSearchIndex.schedule([item])
            invalidateAgentContext()
            return CourseOwnedFileImportResult(
                item: item,
                sourceCleanupPending: sourceCleanupPending
            )
        } catch {
            // S3：无 journal 恢复；崩溃注入也必须走回滚，用户重试即可。
            if !workspaceCommitted {
                importedItems = previousImportedItems
                courseItemMemberships = previousMemberships
                replaceNoteDrafts(previousNotes)
                pendingNoteWritesByItemID = previousPendingNoteWrites
                noteBackingContentDigestsByItemID = previousBackingDigests
                lastSelfWrittenNoteDigestsByItemID =
                    previousLastSelfWrittenDigests
                loadedCourseNoteTextByItemID = previousLoadedCourseNotes
                selectedItemID = previousSelectedItemID
                activeNotebookItemID = previousActiveNotebookItemID
                courseWorkspaceTargetItemID =
                    previousCourseWorkspaceTargetItemID
                noteSourceLinks = previousNoteSourceLinks
                studyLocationsByItemID = previousStudyLocations
                studyLocationsByCourseID = previousCourseStudyLocations
                studySessions = previousStudySessions
                selectionAskThreads = previousSelectionAskThreads
                notebookCreationDraft = previousNotebookCreationDraft
                notebookRenameDraft = previousNotebookRenameDraft
                backNavigationStack = previousBackNavigationStack
                forwardNavigationStack = previousForwardNavigationStack
                let remappedIDs = Set(
                    [itemID, retiredSourceItemID].compactMap { $0 }
                )
                for remappedID in remappedIDs {
                    pendingNotePersistenceTasks.removeValue(
                        forKey: remappedID
                    )?.cancel()
                }
                pendingNotePersistenceByItemID =
                    previousPendingNotePersistence
                for remappedID in remappedIDs {
                    if let pending =
                        previousPendingNotePersistence[remappedID] {
                        scheduleNotePersistence(
                            pending.markdown,
                            for: pending.item
                        )
                    }
                }
                // 尽力回滚磁盘：仅当源仍可验证时删除已落位目标，避免误删唯一副本。
                let expectedTargetIdentity =
                    placedTargetIdentity ?? stagedIdentity
                let sourceStillVerified: Bool
                if let sourceURL, let sourceIdentity {
                    sourceStillVerified = (try? await courseProjectFileWorker.stableSnapshot(
                        at: sourceURL,
                        expectedIdentity: sourceIdentity,
                        expectedSnapshot: sourceSnapshot
                    )) != nil
                } else {
                    sourceStillVerified = false
                }
                // 只有源仍在时才可丢弃已落位副本；生成笔记/源已失则保留磁盘文件。
                let canDiscardPlacedTarget = sourceStillVerified
                if canDiscardPlacedTarget,
                   let expectedTargetIdentity,
                   FileManager.default.fileExists(atPath: targetURL.path) {
                    let targetQuarantineURL = transactionDirectory
                        .appendingPathComponent("target-quarantine", isDirectory: false)
                    _ = await courseProjectFileWorker.isolateAndRemoveVerifiedFile(
                        at: targetURL,
                        quarantineURL: targetQuarantineURL,
                        expectedIdentity: expectedTargetIdentity,
                        expectedSnapshot: sourceSnapshot,
                        remover: { try FileManager.default.removeItem(at: $0) }
                    )
                }
                if let replacedIdentity = replacedTargetIdentity,
                   let replacedSnapshot = replacedTargetSnapshot {
                    let restoreURL: URL? = {
                        if FileManager.default.fileExists(atPath: replacementQuarantineURL.path) {
                            return replacementQuarantineURL
                        }
                        if FileManager.default.fileExists(atPath: replacementRollbackURL.path) {
                            return replacementRollbackURL
                        }
                        if let replacedTrashPath {
                            let trash = URL(fileURLWithPath: replacedTrashPath)
                            if FileManager.default.fileExists(atPath: trash.path) {
                                return trash
                            }
                        }
                        return nil
                    }()
                    if canDiscardPlacedTarget,
                       let restoreURL,
                       !FileManager.default.fileExists(atPath: targetURL.path) {
                        _ = await courseProjectFileWorker.restoreIsolatedFile(
                            from: restoreURL,
                            to: targetURL
                        )
                    }
                    _ = replacedIdentity
                    _ = replacedSnapshot
                }
                // 事务目录尽力清理；源已失且目标保留时也清 staging 残留。
                await safelyRemoveCourseFileTransactionDirectoryInBackground(
                    transactionDirectory,
                    expectedIdentity: transactionDirectoryIdentity
                )
            }
            throw error
        }
    }

    private func validatedCourseImportSource(_ sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        let source = sourceURL.standardizedFileURL
        let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
        let values = try source.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true,
              CourseProjectPathPolicy.isSame(source, resolvedSource) else {
            throw CourseOwnedFileError.sourceMustBeRegularFile
        }
        return resolvedSource
    }

    func isSupportedCourseFileName(
        _ fileName: String,
        role: CourseOwnedFileRole
    ) -> Bool {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              URL(fileURLWithPath: fileName).lastPathComponent == fileName else {
            return false
        }
        let fileURL = URL(fileURLWithPath: fileName)
        switch role {
        case .material:
            return Self.isSupportedCourseFile(fileURL)
        case .note:
            return Self.isMarkdownFile(fileURL)
        }
    }

    private func resolvedCourseImportTarget(
        fileName: String,
        destinationDirectory: URL,
        role: CourseOwnedFileRole,
        conflictResolution: CourseFileConflictResolution
    ) throws -> URL {
        let requestedName: String
        switch conflictResolution {
        case .cancel, .replace:
            requestedName = fileName
        case .keepBoth(let preferredFileName):
            let preferred = preferredFileName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let preferred, !preferred.isEmpty {
                requestedName = preferred
            } else {
                requestedName = fileName
            }
        }
        guard isSupportedCourseFileName(requestedName, role: role) else {
            throw CourseOwnedFileError.unsupportedFile
        }
        let requested = destinationDirectory
            .appendingPathComponent(requestedName, isDirectory: false)
            .standardizedFileURL
        switch conflictResolution {
        case .cancel, .replace:
            return requested
        case .keepBoth:
            guard FileManager.default.fileExists(atPath: requested.path) else {
                return requested
            }
            let stem = requested.deletingPathExtension().lastPathComponent
            let pathExtension = requested.pathExtension
            for suffix in 2...9_999 {
                let candidateName = pathExtension.isEmpty
                    ? "\(stem) \(suffix)"
                    : "\(stem) \(suffix).\(pathExtension)"
                let candidate = destinationDirectory.appendingPathComponent(candidateName)
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            throw CourseOwnedFileError.targetConflict(requested)
        }
    }

    private func replacementItemIndex(
        at targetURL: URL,
        courseID: UUID,
        conflictResolution: CourseFileConflictResolution
    ) throws -> Int? {
        let exists = FileManager.default.fileExists(atPath: targetURL.path)
        switch conflictResolution {
        case .cancel:
            if exists { throw CourseOwnedFileError.targetConflict(targetURL) }
            return nil
        case .keepBoth:
            if exists { throw CourseOwnedFileError.targetConflict(targetURL) }
            return nil
        case .replace:
            guard exists else { return nil }
            let membership = courseItemMemberships.first {
                $0.courseID == courseID
                    && $0.courseRelativePath.map {
                        CourseProjectPathPolicy.isSame(
                            targetURL,
                            courseRootURL(for: courseID)?.appendingPathComponent($0) ?? targetURL
                        )
                    } == true
            }
            guard let membership,
                  let index = importedItems.firstIndex(where: { $0.id == membership.itemID }) else {
                return nil
            }
            if case .common = importedItems[index].storage {
                throw CourseOwnedFileError.replacementTargetIsShared
            }
            return index
        }
    }

    private func courseOwnedDestinationDirectory(
        role: CourseOwnedFileRole,
        inside root: URL
    ) throws -> URL {
        let rawDirectory = root.appendingPathComponent(role.directoryName, isDirectory: true)
        return try realCourseOwnedDirectory(
            rawDirectory,
            inside: root,
            createIfMissing: true
        )
    }

    private func realCourseOwnedDirectory(
        _ rawDirectory: URL,
        inside parent: URL,
        createIfMissing: Bool
    ) throws -> URL {
        if !FileManager.default.fileExists(atPath: rawDirectory.path) {
            guard createIfMissing else {
                throw CourseOwnedFileError.unsafeCoursePath
            }
            try FileManager.default.createDirectory(
                at: rawDirectory,
                withIntermediateDirectories: false
            )
        }
        let values = try rawDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
        ])
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              values.isAliasFile != true else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let directory = try CourseProjectPathPolicy.existingDirectory(rawDirectory)
        guard CourseProjectPathPolicy.isSame(rawDirectory.standardizedFileURL, directory),
              CourseProjectPathPolicy.contains(parent, directory, includingRoot: false) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        return directory
    }

    private func courseFileTransactionDirectory(
        transactionID: UUID,
        inside root: URL
    ) throws -> URL {
        let metadata = try realCourseOwnedDirectory(
            root.appendingPathComponent(".weibei", isDirectory: true),
            inside: root,
            createIfMissing: false
        )
        let rawTransactions = metadata.appendingPathComponent("transactions", isDirectory: true)
        let transactions = try realCourseOwnedDirectory(
            rawTransactions,
            inside: metadata,
            createIfMissing: true
        )
        let transactionDirectory = transactions.appendingPathComponent(
            transactionID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: transactionDirectory,
            withIntermediateDirectories: false
        )
        return try realCourseOwnedDirectory(
            transactionDirectory,
            inside: transactions,
            createIfMissing: false
        )
    }

    private func stableCourseFileSnapshot(
        at url: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot? = nil
    ) throws -> CourseFileSnapshot {
        guard importedFileIdentityResolver(url) == expectedIdentity else {
            throw CourseOwnedFileError.sourceIdentityChanged
        }
        let snapshot = try courseFileSnapshot(at: url)
        guard importedFileIdentityResolver(url) == expectedIdentity,
              expectedSnapshot.map({ $0 == snapshot }) ?? true else {
            throw CourseOwnedFileError.sourceIdentityChanged
        }
        return snapshot
    }

    nonisolated private static func streamingCourseFileSnapshot(
        at url: URL
    ) throws -> CourseFileSnapshot {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
            byteCount += UInt64(chunk.count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return CourseFileSnapshot(byteCount: byteCount, sha256: digest)
    }

    func courseFileSnapshot(at url: URL) throws -> CourseFileSnapshot {
        try Self.streamingCourseFileSnapshot(at: url)
    }

    func courseFileDocumentIdentifier(at url: URL) -> UInt64? {
        guard let value = try? url.resourceValues(
            forKeys: [.documentIdentifierKey]
        ).documentIdentifier,
        value >= 0 else { return nil }
        return UInt64(value)
    }

    private func revalidatedCourseFileDestination(
        courseID: UUID,
        expectedRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        role: CourseOwnedFileRole,
        expectedDestinationIdentity: ImportedFileIdentity
    ) throws -> URL {
        guard let registeredRoot = courseRootURL(for: courseID),
              let canonicalRoot = try? CourseProjectPathPolicy.existingDirectory(registeredRoot),
              CourseProjectPathPolicy.isSame(canonicalRoot, expectedRoot),
              importedFileIdentityResolver(canonicalRoot) == expectedRootIdentity,
              let destinationDirectory = try? realCourseOwnedDirectory(
                canonicalRoot.appendingPathComponent(role.directoryName, isDirectory: true),
                inside: canonicalRoot,
                createIfMissing: false
              ),
              importedFileIdentityResolver(destinationDirectory) == expectedDestinationIdentity else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        return destinationDirectory
    }

    private func revalidatedCourseFileTarget(
        courseID: UUID,
        expectedRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        role: CourseOwnedFileRole,
        expectedDestinationIdentity: ImportedFileIdentity,
        targetURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) throws -> URL {
        let destinationDirectory = try revalidatedCourseFileDestination(
            courseID: courseID,
            expectedRoot: expectedRoot,
            expectedRootIdentity: expectedRootIdentity,
            role: role,
            expectedDestinationIdentity: expectedDestinationIdentity
        )
        let expectedTargetURL = destinationDirectory
            .appendingPathComponent(targetURL.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        guard CourseProjectPathPolicy.isSame(expectedTargetURL, targetURL),
              let rawValues = try? expectedTargetURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isAliasFileKey,
              ]),
              rawValues.isRegularFile == true,
              rawValues.isSymbolicLink != true,
              rawValues.isAliasFile != true else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let resolved = expectedTargetURL.resolvingSymlinksInPath().standardizedFileURL
        guard CourseProjectPathPolicy.isSame(expectedTargetURL, resolved),
              CourseProjectPathPolicy.contains(destinationDirectory, resolved, includingRoot: false),
              CourseProjectPathPolicy.contains(expectedRoot, resolved, includingRoot: false),
              importedFileIdentityResolver(resolved) == expectedIdentity,
              (try? courseFileSnapshot(at: resolved)) == expectedSnapshot else {
            throw CourseOwnedFileError.verificationFailed
        }
        return resolved
    }

    private func revalidatedCourseFileTargetInBackground(
        courseID: UUID,
        expectedRoot: URL,
        expectedRootIdentity: ImportedFileIdentity,
        role: CourseOwnedFileRole,
        expectedDestinationIdentity: ImportedFileIdentity,
        targetURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) async throws -> URL {
        let destinationDirectory = try revalidatedCourseFileDestination(
            courseID: courseID,
            expectedRoot: expectedRoot,
            expectedRootIdentity: expectedRootIdentity,
            role: role,
            expectedDestinationIdentity: expectedDestinationIdentity
        )
        let expectedTargetURL = destinationDirectory
            .appendingPathComponent(targetURL.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        let resolved = expectedTargetURL.resolvingSymlinksInPath().standardizedFileURL
        guard CourseProjectPathPolicy.isSame(expectedTargetURL, targetURL),
              CourseProjectPathPolicy.isSame(expectedTargetURL, resolved),
              CourseProjectPathPolicy.contains(destinationDirectory, resolved, includingRoot: false),
              CourseProjectPathPolicy.contains(expectedRoot, resolved, includingRoot: false),
              importedFileIdentityResolver(resolved) == expectedIdentity else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        do {
            _ = try await courseProjectFileWorker.stableSnapshot(
                at: resolved,
                expectedIdentity: expectedIdentity,
                expectedSnapshot: expectedSnapshot
            )
        } catch {
            throw CourseOwnedFileError.verificationFailed
        }
        return resolved
    }

    private func atomicRenameWithoutReplacement(from source: URL, to destination: URL) -> Bool {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return false }
                return Darwin.renamex_np(
                    sourcePath,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                ) == 0
            }
        }
    }

    private func restoreIsolatedCourseFile(
        from quarantineURL: URL,
        to originalURL: URL
    ) -> CourseFileRemovalOutcome {
        guard FileManager.default.fileExists(atPath: quarantineURL.path) else {
            return .quarantined(quarantineURL)
        }
        guard !FileManager.default.fileExists(atPath: originalURL.path),
              atomicRenameWithoutReplacement(from: quarantineURL, to: originalURL) else {
            return .quarantined(quarantineURL)
        }
        return .restored
    }

    private func atomicallyIsolateVerifiedCourseFile(
        at originalURL: URL,
        quarantineURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: originalURL.path),
              !FileManager.default.fileExists(atPath: quarantineURL.path),
              atomicRenameWithoutReplacement(
                from: originalURL,
                to: quarantineURL
              ) else {
            return false
        }
        guard (try? stableCourseFileSnapshot(
            at: quarantineURL,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        )) != nil else {
            _ = restoreIsolatedCourseFile(
                from: quarantineURL,
                to: originalURL
            )
            return false
        }
        return true
    }

    private func atomicallyIsolateAndRemoveCourseFile(
        at originalURL: URL,
        quarantineURL: URL,
        expectedIdentity: ImportedFileIdentity,
        expectedSnapshot: CourseFileSnapshot,
        remover: (URL) throws -> Void
    ) -> CourseFileRemovalOutcome {
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return FileManager.default.fileExists(atPath: quarantineURL.path)
                ? .quarantined(quarantineURL)
                : .removed
        }
        guard atomicallyIsolateVerifiedCourseFile(
            at: originalURL,
            quarantineURL: quarantineURL,
            expectedIdentity: expectedIdentity,
            expectedSnapshot: expectedSnapshot
        ) else {
            return FileManager.default.fileExists(atPath: quarantineURL.path)
                ? .quarantined(quarantineURL)
                : .restored
        }
        do {
            try remover(quarantineURL)
        } catch {
            if !FileManager.default.fileExists(atPath: quarantineURL.path) {
                return .removed
            }
            return restoreIsolatedCourseFile(
                from: quarantineURL,
                to: originalURL
            )
        }
        guard FileManager.default.fileExists(atPath: quarantineURL.path) else {
            return .removed
        }
        return restoreIsolatedCourseFile(
            from: quarantineURL,
            to: originalURL
        )
    }

    private func safelyRemoveCourseFileTransactionDirectory(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) {
        guard importedFileIdentityResolver(transactionDirectory) == expectedIdentity,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: transactionDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey],
                options: []
              ),
              entries.allSatisfy({ ["journal.json", "payload"].contains($0.lastPathComponent) }) else {
            return
        }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .isAliasFileKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.isAliasFile != true else {
                return
            }
        }
        for entry in entries {
            try? FileManager.default.removeItem(at: entry)
        }
        if (try? FileManager.default.contentsOfDirectory(atPath: transactionDirectory.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: transactionDirectory)
        }
    }

    private func safelyRemoveCourseFileTransactionDirectoryInBackground(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) async {
        await Task.detached(priority: .utility) {
            guard CourseProjectFileWorker.identity(at: transactionDirectory) == expectedIdentity,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: transactionDirectory,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                  ),
                  entries.allSatisfy({
                    ["journal.json", "payload"].contains($0.lastPathComponent)
                  }) else {
                return
            }
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                values.isAliasFile != true else {
                    return
                }
            }
            for entry in entries {
                try? FileManager.default.removeItem(at: entry)
            }
            if (try? FileManager.default.contentsOfDirectory(
                atPath: transactionDirectory.path
            ).isEmpty) == true {
                try? FileManager.default.removeItem(at: transactionDirectory)
            }
        }.value
    }

    private func safelyRemoveCourseMarkdownTransactionDirectoryInBackground(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) async {
        await Task.detached(priority: .utility) {
            guard CourseProjectFileWorker.identity(at: transactionDirectory)
                    == expectedIdentity,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: transactionDirectory,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                  ),
                  entries.allSatisfy({
                    ["course-note.json", "payload"]
                        .contains($0.lastPathComponent)
                  }) else {
                return
            }
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                values.isAliasFile != true else {
                    return
                }
            }
            for entry in entries {
                try? FileManager.default.removeItem(at: entry)
            }
            if (try? FileManager.default.contentsOfDirectory(
                atPath: transactionDirectory.path
            ).isEmpty) == true {
                try? FileManager.default.removeItem(at: transactionDirectory)
            }
        }.value
    }

    private func safelyRemoveSharedTransactionDirectoryInBackground(
        _ transactionDirectory: URL,
        expectedIdentity: ImportedFileIdentity
    ) async {
        await Task.detached(priority: .utility) {
            guard CourseProjectFileWorker.identity(at: transactionDirectory) == expectedIdentity,
                  let entries = try? FileManager.default.contentsOfDirectory(
                    at: transactionDirectory,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                  ),
                  entries.allSatisfy({
                    [
                        "shared.json",
                        "shared-link.json",
                        "shared-link-removal.json",
                        "payload",
                    ]
                        .contains($0.lastPathComponent)
                  }) else {
                return
            }
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                values.isAliasFile != true else {
                    return
                }
            }
            for entry in entries {
                try? FileManager.default.removeItem(at: entry)
            }
            if (try? FileManager.default.contentsOfDirectory(
                atPath: transactionDirectory.path
            ).isEmpty) == true {
                try? FileManager.default.removeItem(at: transactionDirectory)
            }
        }.value
    }

    /// S3：不再从 journal 恢复未完成操作。启动时静默清理 `.weibei/transactions/*` 残留
    /// 与旧版 pending journal 文件。
    /// H1：含 `replaced-target` / `replacement-rollback` 等用户内容崩溃备份的目录绝不误删；
    /// 其余仅当条目全部属于已知 staging/废件白名单时才清。
    @discardableResult
    func silentlyCleanupOrphanCourseTransactions() -> Bool {
        let fileManager = FileManager.default
        // 运行时各 safelyRemove* 白名单并集 + 无 journal 时代的 staging 名。
        let safeOrphanNames: Set<String> = [
            "journal.json",
            "payload",
            "course-note.json",
            "shared.json",
            "shared-link.json",
            "shared-link-removal.json",
            "prepared-link",
            "prepared-owner-link",
            "prepared-added-link",
            "prepared-link-cleanup",
            "isolated-link",
            "isolated-link-cleanup",
            "link-cleanup",
            "target-quarantine",
        ]
        let protectedCrashBackupNames: Set<String> = [
            "replaced-target",
            "replacement-rollback",
            "trashed-replaced-target",
        ]
        for course in courses {
            guard let root = courseRootURL(for: course.id),
                  let canonical = try? CourseProjectPathPolicy.existingDirectory(root) else {
                continue
            }
            let transactions = canonical
                .appendingPathComponent(".weibei/transactions", isDirectory: true)
            guard fileManager.fileExists(atPath: transactions.path),
                  let children = try? fileManager.contentsOfDirectory(
                    at: transactions,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                  ) else {
                continue
            }
            for child in children {
                // 仅清理事务目录本身；不触碰课程资料目标文件。
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else {
                    // 非目录残留：无身份含义，可静默清。
                    try? fileManager.removeItem(at: child)
                    continue
                }
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: child,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .isAliasFileKey,
                    ],
                    options: []
                ) else {
                    continue
                }
                let names = Set(entries.map(\.lastPathComponent))
                if !names.isDisjoint(with: protectedCrashBackupNames) {
                    // best-effort 还原；任一步失败则保留整目录（数据不销毁）。
                    _ = tryRestoreReplacedTargetFromOrphanTransaction(
                        child,
                        courseRoot: canonical
                    )
                    continue
                }
                // 白名单：全部条目均为已知 staging/废件才删；未知名保留。
                guard names.isSubset(of: safeOrphanNames) else {
                    continue
                }
                try? fileManager.removeItem(at: child)
            }
            if let remaining = try? fileManager.contentsOfDirectory(
                at: transactions,
                includingPropertiesForKeys: nil
            ), remaining.isEmpty {
                try? fileManager.removeItem(at: transactions)
            }
        }
        // 硬崩溃后可能残留 `.weibei-course-removal-*` 隔离目录：按身份还原到登记路径。
        let recoveredCourseTrash =
            restoreOrphanCourseRootTrashIsolations()
        // 旧版 workspace 级 journal 路径（已在 init 删除一份；此处再保险）。
        try? fileManager.removeItem(
            at: workspaceDirectory.appendingPathComponent("pending-notebook-rename.json")
        )
        try? fileManager.removeItem(
            at: workspaceDirectory.appendingPathComponent("pending-course-removal.json")
        )
        return recoveredCourseTrash
    }

    /// 旧版 course-file journal 子集：仅启动还原需要的字段（解码容忍缺字段）。
    private struct OrphanCourseFileTransactionJournal: Codable {
        var targetRelativePath: String?
        var replacedTargetIdentity: ImportedFileIdentity?
        var replacedTargetSnapshot: CourseFileSnapshot?
    }

    /// 含 `replaced-target` 的孤儿事务：target 空缺且副本可核验时还原；否则保留目录。
    @discardableResult
    private func tryRestoreReplacedTargetFromOrphanTransaction(
        _ transactionDirectory: URL,
        courseRoot: URL
    ) -> Bool {
        let fileManager = FileManager.default
        let journalURL = transactionDirectory
            .appendingPathComponent("journal.json", isDirectory: false)
        let replacedURL = transactionDirectory
            .appendingPathComponent("replaced-target", isDirectory: false)
        guard fileManager.fileExists(atPath: replacedURL.path),
              let journalData = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(
                OrphanCourseFileTransactionJournal.self,
                from: journalData
              ),
              let relativePath = journal.targetRelativePath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !relativePath.isEmpty,
              let targetURL = Self.backgroundRawRelativeURL(
                relativePath,
                inside: courseRoot
              ) else {
            return false
        }
        // target 仍在 → 不覆盖，保留事务目录。
        guard !fileManager.fileExists(atPath: targetURL.path) else {
            return false
        }
        if let expectedIdentity = journal.replacedTargetIdentity,
           importedFileIdentityResolver(replacedURL) != expectedIdentity {
            return false
        }
        if let expectedSnapshot = journal.replacedTargetSnapshot {
            let data = (try? Data(contentsOf: replacedURL)) ?? Data()
            let digest = Self.noteContentDigest(data)
            let byteCount = UInt64(data.count)
            guard digest == expectedSnapshot.sha256,
                  byteCount == expectedSnapshot.byteCount else {
                return false
            }
        }
        // 同步路径：启动清理不 await actor。
        guard CourseProjectFileWorker.renameWithoutReplacement(
            from: replacedURL,
            to: targetURL
        ) else {
            return false
        }
        // 还原成功后，若剩余仅白名单废件则可清；否则保留。
        if let remaining = try? fileManager.contentsOfDirectory(
            at: transactionDirectory,
            includingPropertiesForKeys: nil
        ) {
            let safeNames: Set<String> = ["journal.json", "payload"]
            if remaining.allSatisfy({ safeNames.contains($0.lastPathComponent) }) {
                try? fileManager.removeItem(at: transactionDirectory)
            }
        }
        return true
    }

    func cleanupPersistedCourseTrashReceipts() {
        pendingCourseTrashReceiptCleanups.removeAll { cleanup in
            guard !persistedWorkspaceCourseIDs.contains(
                cleanup.courseID
            ) else {
                return false
            }
            return CourseProjectFileWorker.cleanupCourseTrashReceipt(
                cleanup,
                identityResolver: importedFileIdentityResolver
            )
        }
    }

    @discardableResult
    private func restoreOrphanCourseRootTrashIsolations() -> Bool {
        var recoveredReceipts: [CourseTrashReceiptCleanup] = []
        var recoveredCourseIDs = Set<UUID>()
        for course in courses {
            if let recovery = CourseProjectFileWorker
                .recoverCourseTrashReceipt(
                    for: course,
                    resolvedRootURL: courseRootURL(for: course.id),
                    courseLibraryRootURL: courseLibraryRootURL,
                    identityResolver: importedFileIdentityResolver
                ), recoveredCourseIDs.insert(recovery.courseID).inserted {
                recoveredReceipts.append(recovery)
            }
        }
        for recovery in recoveredReceipts {
            removeCourseLocalRegistration(recovery.courseID)
            pendingCourseTrashReceiptCleanups.append(recovery)
        }
        return !recoveredReceipts.isEmpty
    }

    /// S2：旧四阶段 course-note 事务不再恢复写路径；静默清理残留事务目录。
    /// 若目标文件缺失且 original 仍在，尽力还原 original，避免用户丢文件。
    nonisolated private static func backgroundLinkMatches(
        _ linkURL: URL,
        destination: URL,
        identity: ImportedFileIdentity
    ) -> Bool {
        CourseProjectFileWorker.isSymbolicLink(at: linkURL)
            && CourseProjectFileWorker.identity(at: linkURL) == identity
            && CourseProjectPathPolicy.isSame(
                linkURL.resolvingSymlinksInPath(),
                destination.resolvingSymlinksInPath()
            )
    }

    nonisolated private static func isKnownCommonRelativePath(
        _ relativePath: String,
        fileName: String
    ) -> Bool {
        let components = relativePath.split(separator: "/")
        return components.count == 2
            && ["通用资料", "通用笔记", "共享文稿"]
                .contains(String(components[0]))
            && components[1] == Substring(fileName)
    }
    nonisolated static func backgroundRawRelativeURL(
        _ relativePath: String,
        inside root: URL
    ) -> URL? {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.first != ".weibei",
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        let candidate = components.reduce(root) {
            $0.appendingPathComponent($1, isDirectory: false)
        }.standardizedFileURL
        guard CourseProjectPathPolicy.contains(root, candidate, includingRoot: false) else {
            return nil
        }
        return candidate
    }
    private func transactionDirectoryFingerprint(
        at root: URL
    ) -> TransactionDirectoryFingerprint? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let rootValues = try? root.resourceValues(forKeys: keys),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              let rootIdentity = importedFileIdentityResolver(root) else {
            return nil
        }

        var encounteredError = false
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                encounteredError = true
                return false
            }
        ) else {
            return nil
        }
        let rootComponents = root.standardizedFileURL.pathComponents
        var entries: [String: TransactionDirectoryFingerprint.Entry] = [:]
        for case let entryURL as URL in enumerator {
            guard let values = try? entryURL.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  let identity = importedFileIdentityResolver(entryURL) else {
                return nil
            }
            let entryComponents = entryURL.standardizedFileURL.pathComponents
            guard entryComponents.count > rootComponents.count,
                  Array(entryComponents.prefix(rootComponents.count)) == rootComponents else {
                return nil
            }
            let relativePath = entryComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            if values.isDirectory == true {
                entries[relativePath] = .init(
                    kind: .directory,
                    identity: identity,
                    data: nil
                )
            } else if values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize <= 1_048_576,
                      let data = try? Data(contentsOf: entryURL) {
                entries[relativePath] = .init(
                    kind: .regularFile,
                    identity: identity,
                    data: data
                )
            } else {
                return nil
            }
        }
        guard !encounteredError else { return nil }
        return TransactionDirectoryFingerprint(
            rootIdentity: rootIdentity,
            entriesByRelativePath: entries
        )
    }

    private func safelyRemoveTransactionDirectory(
        at root: URL,
        expected: TransactionDirectoryFingerprint
    ) {
        guard transactionDirectoryMatches(at: root, expected: expected),
              (try? courseProjectMutationHook(.beforeOwnedRollbackCleanup)) != nil else {
            return
        }

        let regularFiles = expected.entriesByRelativePath
            .filter { $0.value.kind == .regularFile }
            .sorted { pathDepth($0.key) > pathDepth($1.key) }
        for (relativePath, expectedEntry) in regularFiles {
            let fileURL = transactionURL(
                relativePath: relativePath,
                inside: root
            )
            guard transactionEntry(at: fileURL, matches: expectedEntry),
                  unlinkPath(fileURL) else {
                return
            }
        }

        let directories = expected.entriesByRelativePath
            .filter { $0.value.kind == .directory }
            .sorted { pathDepth($0.key) > pathDepth($1.key) }
        for (relativePath, expectedEntry) in directories {
            let directoryURL = transactionURL(
                relativePath: relativePath,
                inside: root
            )
            guard transactionEntry(at: directoryURL, matches: expectedEntry),
                  removeEmptyDirectory(directoryURL) else {
                return
            }
        }

        guard importedFileIdentityResolver(root) == expected.rootIdentity else {
            return
        }
        _ = removeEmptyDirectory(root)
    }

    private func transactionDirectoryMatches(
        at root: URL,
        expected: TransactionDirectoryFingerprint
    ) -> Bool {
        guard importedFileIdentityResolver(root) == expected.rootIdentity else {
            return false
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        var encounteredError = false
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                encounteredError = true
                return false
            }
        ) else {
            return false
        }
        let rootComponents = root.standardizedFileURL.pathComponents
        var seenPaths = Set<String>()
        for case let entryURL as URL in enumerator {
            let entryComponents = entryURL.standardizedFileURL.pathComponents
            guard entryComponents.count > rootComponents.count,
                  Array(entryComponents.prefix(rootComponents.count)) == rootComponents else {
                return false
            }
            let relativePath = entryComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            guard let expectedEntry = expected.entriesByRelativePath[relativePath],
                  seenPaths.insert(relativePath).inserted,
                  transactionEntry(at: entryURL, matches: expectedEntry) else {
                return false
            }
        }
        return !encounteredError
            && seenPaths == Set(expected.entriesByRelativePath.keys)
    }

    private func transactionEntry(
        at url: URL,
        matches expected: TransactionDirectoryFingerprint.Entry
    ) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isSymbolicLink != true,
              let identity = importedFileIdentityResolver(url) else {
            return false
        }
        guard identity == expected.identity else { return false }
        switch expected.kind {
        case .directory:
            return values.isDirectory == true
                && values.isRegularFile != true
                && expected.data == nil
        case .regularFile:
            guard values.isRegularFile == true,
                  values.isDirectory != true,
                  let expectedData = expected.data,
                  expectedData.count <= 1_048_576,
                  values.fileSize == expectedData.count,
                  let currentData = try? Data(contentsOf: url) else {
                return false
            }
            return currentData == expectedData
        }
    }

    private func transactionURL(relativePath: String, inside root: URL) -> URL {
        relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(root) {
                $0.appendingPathComponent(String($1))
            }
    }

    private func pathDepth(_ relativePath: String) -> Int {
        relativePath.split(separator: "/", omittingEmptySubsequences: true).count
    }

    private func unlinkPath(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.unlink(path) == 0
        }
    }

    private func removeEmptyDirectory(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return Darwin.rmdir(path) == 0
        }
    }

    func validateLibraryRoot(_ root: URL) throws {
        let protectedRoots = [
            URL(fileURLWithPath: "/", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
        ].compactMap { $0?.resolvingSymlinksInPath().standardizedFileURL }
        if protectedRoots.contains(where: { CourseProjectPathPolicy.contains(root, $0) })
            || CourseProjectPathPolicy.overlaps(root, workspaceDirectory) {
            throw CourseProjectRootError.dangerousRoot
        }
        for course in courses {
            let candidates = registeredRootCandidates(
                for: course,
                proposedLibraryRoot: root
            )
            if candidates.contains(where: {
                CourseProjectPathPolicy.isSame($0, root)
                    || CourseProjectPathPolicy.contains($0, root, includingRoot: false)
            }) {
                throw CourseProjectRootError.overlappingRoot
            }
        }
    }

    private func registeredRootCandidates(
        for course: Course,
        proposedLibraryRoot: URL
    ) -> [URL] {
        var candidates: [URL] = []
        if let resolved = resolvedCourseRootURLs[course.id] {
            candidates.append(resolved)
        }
        if let relativePath = course.sourceRootRelativePath,
           let resolved = CourseProjectPathPolicy.resolvedRelativePath(
               relativePath,
               inside: proposedLibraryRoot
           ) {
            candidates.append(resolved)
        }
        return candidates
    }

    private func validateCourseProjectRoot(
        _ root: URL,
        identity: ImportedFileIdentity?,
        mustBeInsideLibrary: Bool,
        excludingCourseID: UUID? = nil
    ) throws {
        let protectedRoots = [
            URL(fileURLWithPath: "/", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
        ].compactMap { $0?.resolvingSymlinksInPath().standardizedFileURL }
        if protectedRoots.contains(where: { CourseProjectPathPolicy.contains(root, $0) })
            || CourseProjectPathPolicy.overlaps(root, workspaceDirectory) {
            throw CourseProjectRootError.dangerousRoot
        }

        if let libraryRoot = courseLibraryRootURL {
            if CourseProjectPathPolicy.isSame(root, libraryRoot)
                || CourseProjectPathPolicy.contains(root, libraryRoot, includingRoot: false) {
                throw CourseProjectRootError.dangerousRoot
            }
            for directoryName in [
                CourseOwnedFileRole.material.commonDirectoryName,
                CourseOwnedFileRole.note.commonDirectoryName,
                "共享文稿",
            ] {
                if CourseProjectPathPolicy.overlaps(
                    root,
                    libraryRoot.appendingPathComponent(
                        directoryName,
                        isDirectory: true
                    )
                ) {
                    throw CourseProjectRootError.dangerousRoot
                }
            }
            if mustBeInsideLibrary,
               !CourseProjectPathPolicy.contains(libraryRoot, root, includingRoot: false) {
                throw CourseProjectRootError.rootOutsideLibrary
            }
        } else if mustBeInsideLibrary {
            throw courseLibraryRootPath == nil
                ? CourseProjectRootError.missingLibrary
                : CourseProjectRootError.unavailableLibrary
        }

        for course in courses where course.id != excludingCourseID {
            if let identity,
               let existingIdentity = course.sourceRootIdentity,
               identity == existingIdentity {
                throw CourseProjectRootError.rootAlreadyRegistered
            }
            if let existingRoot = resolvedCourseRootURLs[course.id]
                ?? legacyCourseRootURL(for: course),
               CourseProjectPathPolicy.overlaps(root, existingRoot) {
                throw CourseProjectRootError.overlappingRoot
            }
        }
    }

    private func existingCourse(
        at root: URL,
        identity: ImportedFileIdentity
    ) -> Course? {
        courses.first { course in
            if let storedIdentity = course.sourceRootIdentity {
                return storedIdentity == identity
            }
            guard let existingRoot = resolvedCourseRootURLs[course.id]
                    ?? legacyCourseRootURL(for: course) else {
                return false
            }
            return CourseProjectPathPolicy.isSame(existingRoot, root)
        }
    }

    private func legacyCourseRootURL(for course: Course) -> URL? {
        nil
    }

    private func isTopLevelLibraryCourseFolder(_ relativePath: String) -> Bool {
        let reserved = [
            CourseLibraryLayout.commonMaterialsDirectoryName,
            CourseLibraryLayout.commonNotesDirectoryName,
        ]
        return !relativePath.isEmpty
            && !relativePath.contains("/")
            && !relativePath.contains("..")
            && !reserved.contains(relativePath)
    }

    @discardableResult
    func restoreCourseProjectRoots() -> Bool {
        var changed = false
        courseLibraryRootURL = nil
        courseLibraryUnavailableReason = nil
        resolvedCourseRootURLs.removeAll()
        courseRootUnavailableReasons.removeAll()

        if bindLibraryRootFromBookmark() {
            changed = true
        } else if bindLibraryRootOnThisComputer() {
            changed = true
        } else if courseLibraryRootPath != nil
                    || courseLibraryRootIdentity != nil
                    || courseLibraryRootBookmarkData != nil {
            courseLibraryUnavailableReason = courseLibraryUnavailableReason
                ?? ui(
                    "原资料库暂时无法连接；课程记录和文件仍在原位置。请重新选择原来的资料库。",
                    "The original library could not be reconnected. Course records and files remain in their original location. Re-select the original library."
                )
        }

        changed = restoreCourseReferencesInsideLibrary() || changed
        return changed
    }

    @discardableResult
    private func restoreCourseReferencesInsideLibrary() -> Bool {
        (try? waitForCourseFileOperation {
            await self.restoreCourseReferencesInsideLibraryAsync()
        }) ?? false
    }

    private func restoreCourseReferencesInsideLibraryAsync() async -> Bool {
        guard let libraryRoot = courseLibraryRootURL else {
            for course in courses where course.sourceRootRelativePath != nil {
                courseRootUnavailableReasons[course.id] = courseLibraryUnavailableReason
                    ?? ui(
                        "课程文件夹暂时不可用；文件仍在原位置。请重新选择原来的资料库。",
                        "The course folder is temporarily unavailable. Files remain in their original location. Re-select the original library."
                    )
            }
            return false
        }
        var changed = false
        for index in courses.indices {
            guard let relativePath = courses[index].sourceRootRelativePath else {
                continue
            }
            let resolvedURL = resolveRegisteredCourseFolder(
                relativePath: relativePath,
                expectedIdentity: courses[index].sourceRootIdentity,
                courseID: courses[index].id,
                inside: libraryRoot
            )
            guard let resolvedURL,
                  let nextRelativePath = CourseProjectPathPolicy.relativePath(
                    of: resolvedURL,
                    inside: libraryRoot
                  ) else {
                courseRootUnavailableReasons[courses[index].id] = ui(
                    "课程文件夹当前不可用；文件仍在原位置。请重新选择原来的资料库。",
                    "The course folder is unavailable. Files remain in their original location. Re-select the original library."
                )
                continue
            }
            let courseID = courses[index].id
            do {
                try await validateRestoredCourseRootAsync(
                    resolvedURL,
                    course: courses[index],
                    mustBeInsideLibrary: true
                )
            } catch {
                recordCourseLibraryUIFailure(
                    error,
                    operation: "validate_restored_course_root",
                    path: resolvedURL
                )
                courseRootUnavailableReasons[courseID] = ui(
                    "课程文件夹当前无法安全读取；魏碑没有修改其中内容。请重新选择原来的资料库。",
                    "The course folder cannot be read safely. WeiBei did not modify its contents. Re-select the original library."
                )
                continue
            }
            resolvedCourseRootURLs[courseID] = resolvedURL
            courseRootUnavailableReasons.removeValue(forKey: courseID)
            if let liveIdentity = importedFileIdentityResolver(resolvedURL),
               courses[index].sourceRootIdentity != liveIdentity {
                courses[index].sourceRootIdentity = liveIdentity
                changed = true
            }
            if courses[index].sourceRootRelativePath != nextRelativePath {
                courses[index].sourceRootRelativePath = nextRelativePath
                courses[index].updatedAt = Date()
                changed = true
            }
        }
        return changed
    }

    func discoverTopLevelCourseFolders() {
        guard let libraryRoot = courseLibraryRootURL else { return }
        switch CourseProjectFileWorker.entryPresence(at: libraryRoot) {
        case .absent, .inaccessible:
            return
        case .present, .presentUnmaterialized:
            break
        }
        let reserved: Set<String> = [
            CourseLibraryLayout.commonMaterialsDirectoryName,
            CourseLibraryLayout.commonNotesDirectoryName,
            "共享文稿",
        ]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: libraryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let name = child.lastPathComponent
            guard !reserved.contains(name) else { continue }
            if courses.contains(where: {
                $0.sourceRootRelativePath == name || courseRootURL(for: $0.id) == child
            }) {
                ensureCourseScaffold(at: child)
                continue
            }
            let metadataURL = child.appendingPathComponent(
                ".weibei",
                isDirectory: true
            )
            let manifestURL = metadataURL.appendingPathComponent(
                "course.json"
            )
            let existingManifest: CourseProjectManifest?
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                let values = try? metadataURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isAliasFileKey,
                ])
                guard values?.isDirectory == true,
                      values?.isSymbolicLink != true,
                      values?.isAliasFile != true,
                      !CourseProjectFileWorker.isSymbolicLink(
                          at: metadataURL
                      ),
                      CourseProjectPathPolicy.isSame(
                          metadataURL,
                          metadataURL.resolvingSymlinksInPath()
                      ),
                      let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(
                          CourseProjectManifest.self,
                          from: data
                      ) else {
                    continue
                }
                existingManifest = manifest
            } else {
                existingManifest = nil
            }
            // 可携带副本必须走完整接管事务，不能被普通目录扫描提前消费封印。
            guard existingManifest?.portableExport == nil else { continue }
            let existingID = existingManifest?.courseID
            if let existingID, let index = courses.firstIndex(where: { $0.id == existingID }) {
                courses[index].title = name
                courses[index].sourceRootRelativePath = name
                resolvedCourseRootURLs[existingID] = child
                ensureCourseScaffold(at: child)
                continue
            }
            let courseID = existingID ?? UUID()
            ensureCourseScaffold(at: child)
            let writtenManifest = child
                .appendingPathComponent(".weibei", isDirectory: true)
                .appendingPathComponent("course.json")
            if !FileManager.default.fileExists(atPath: writtenManifest.path) {
                try? CourseProjectManifest(courseID: courseID)
                    .encoded()
                    .write(to: writtenManifest, options: [.atomic])
            }
            if !courses.contains(where: { $0.id == courseID }) {
                courses.append(
                    Course(
                        id: courseID,
                        title: name,
                        colorIndex: nextCourseColorIndex(),
                        sourceRootRelativePath: name
                    )
                )
            }
            resolvedCourseRootURLs[courseID] = child
        }
    }

    private func ensureCourseScaffold(at root: URL) {
        for name in [
            CourseLibraryLayout.courseMaterialsDirectoryName,
            CourseLibraryLayout.courseNotesDirectoryName,
            ".weibei",
        ] {
            try? FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func validateRestoredCourseRootAsync(
        _ root: URL,
        course: Course,
        mustBeInsideLibrary: Bool
    ) async throws {
        try validateCourseProjectRoot(
            root,
            identity: course.sourceRootIdentity,
            mustBeInsideLibrary: mustBeInsideLibrary,
            excludingCourseID: course.id
        )
        let liveIdentity = importedFileIdentityResolver(root)
        let identityMatches = course.sourceRootIdentity.flatMap { expected in
            liveIdentity.map { expected.matchesAcrossVolumeDrift($0) }
        } ?? false
        if !identityMatches, courseManifestCourseID(at: root) != course.id {
            throw CourseProjectRootError.manifestMismatch
        }
        let manifestURL = root.appendingPathComponent(
            ".weibei/course.json"
        )
        let manifestData = try CourseProjectFileWorker
            .readBoundedRegularFile(
                at: manifestURL,
                maximumByteCount: 1_048_576
            )
        let manifest = try JSONDecoder().decode(
            CourseProjectManifest.self,
            from: manifestData
        )
        guard manifest.courseID == course.id,
              manifest.schemaVersion
                == CourseProjectManifest.currentSchemaVersion else {
            throw CourseProjectRootError.manifestMismatch
        }
        if manifest.portableExport != nil {
            guard let expectedRootIdentity = liveIdentity
                    ?? course.sourceRootIdentity else {
                throw CourseProjectRootError.manifestMismatch
            }
            // S6-5：去掉 thread evidence 官僚路径，直接 adoptionSnapshot。
            let snapshot = try await courseProjectFileWorker
                .adoptionSnapshot(
                    at: root,
                    expectedRootIdentity: expectedRootIdentity
                )
            lastPortableAdoptionReadRanOnMainThread = false
            guard snapshot.manifest.courseID == course.id,
                  snapshot.manifest.portableExport != nil,
                  snapshot.manifestData == manifestData else {
                throw CourseProjectRootError.manifestMismatch
            }
            try await courseProjectFileWorker
                .normalizePortableCourseManifest(
                    with: CourseProjectManifest(
                        courseID: course.id
                    ).encoded(),
                    at: manifestURL,
                    expectedDirectoryIdentity:
                        snapshot.metadataIdentity,
                    expectedPreviousData:
                        snapshot.manifestData
                )
        }
    }

    func findDirectory(
        with identity: ImportedFileIdentity,
        inside libraryRoot: URL
    ) -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }
        for case let candidate as URL in enumerator {
            let values = try? candidate.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { continue }
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            let canonical = candidate.resolvingSymlinksInPath().standardizedFileURL
            if let live = importedFileIdentityResolver(canonical),
               identity.matchesAcrossVolumeDrift(live) {
                return canonical
            }
        }
        return nil
    }

    func renameCourse(_ courseID: UUID, title rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeCourseRemovalTokens[courseID] == nil,
              !title.isEmpty,
              let index = courses.firstIndex(where: { $0.id == courseID }),
              courses[index].title != title else { return }
        courses[index].title = title
        courses[index].updatedAt = Date()
        save()
    }

    func removeCourseFromWeiBei(_ courseID: UUID) async throws {
        let transactionID = try beginCourseRemovalTransaction()
        defer { finishCourseRemovalTransaction(transactionID) }
        let prepared = try await prepareCourseRemoval(
            courseID,
            token: transactionID,
            requiresAvailableRoot: false
        )
        let shouldDismissCourseWorkspace =
            courseWorkspacePresented
                && courseWorkspaceCourseID == courseID
        guard await persistWorkspaceRemovingCourse(courseID) else {
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: false
            )
            throw CourseRemovalError.workspaceSaveFailed
        }
        removeCourseLocalRegistration(courseID)
        if shouldDismissCourseWorkspace {
            courseWorkspacePresented = false
        }
        finishCourseRemovalAttempt(
            courseID,
            token: prepared.token,
            succeeded: true
        )
    }

    func courseHasNeverHadFolder(_ courseID: UUID) -> Bool {
        guard let course = course(withID: courseID) else { return false }
        return course.sourceRootRelativePath == nil
            && course.sourceRootPath == nil
            && course.sourceRootIdentity == nil
            && course.sourceRootBookmarkData == nil
    }

    func deleteCourse(_ courseID: UUID) async throws {
        guard course(withID: courseID) != nil else {
            throw CourseRemovalError.courseNotFound
        }
        if courseHasNeverHadFolder(courseID) {
            try await removeCourseFromWeiBei(courseID)
        } else {
            _ = try await moveCourseFolderToTrash(courseID)
        }
    }

    @discardableResult
    func moveCourseFolderToTrash(_ courseID: UUID) async throws -> URL {
        let transactionID = try beginCourseRemovalTransaction()
        defer { finishCourseRemovalTransaction(transactionID) }
        let prepared = try await prepareCourseRemoval(
            courseID,
            token: transactionID,
            requiresAvailableRoot: true
        )
        let shouldDismissCourseWorkspace =
            courseWorkspacePresented
                && courseWorkspaceCourseID == courseID
        guard let root = prepared.root,
              let rootIdentity = prepared.rootIdentity else {
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: false
            )
            throw CourseRemovalError.courseRootUnavailable
        }

        // 同卷 receipt 只负责区分“隔离待还原”和“已进废纸篓待清登记”；
        // 不恢复 workspace 级 journal。
        var isolation: CourseRootTrashIsolation?
        var receiptCleanup: CourseTrashReceiptCleanup?
        do {
            try courseProjectMutationHook(.beforeCourseRootTrashMove)
            // S6-4：不再因 Agent/笔记 pending 拒绝废纸篓。
            guard course(withID: courseID) == prepared.course,
                  activeCourseRemovalTokens[courseID] == prepared.token,
                  coursePortableStateMatchesLastSaved(courseID),
                  let currentRoot = courseRootURL(for: courseID),
                  CourseProjectPathPolicy.isSame(currentRoot, root),
                  importedFileIdentityResolver(currentRoot)
                    == rootIdentity else {
                throw CourseRemovalError.courseRootChanged
            }
            let selfCheckDestination = workspaceDirectory
                .appendingPathComponent(
                    "SelfCheckTrash",
                    isDirectory: true
                )
                .appendingPathComponent(
                    transactionID.uuidString,
                    isDirectory: true
                )
            isolation = try await courseProjectFileWorker
                .isolateCourseRootForTrash(
                    at: currentRoot,
                    expectedIdentity: rootIdentity,
                    expectedCourseID: courseID,
                    transactionID: transactionID,
                    beforeIsolation: {
                        try self.courseProjectMutationHook(
                            .beforeCourseRootTrashIsolation
                        )
                    }
                )
            try courseProjectMutationHook(
                .afterCourseRootTrashIsolationBeforeJournal
            )
            guard let activeIsolation = isolation else {
                throw CourseRemovalError.courseRootUnavailable
            }
            receiptCleanup = try CourseProjectFileWorker.writeCourseTrashReceipt(
                for: activeIsolation,
                courseID: courseID
            )
            let trashedRoot = try await courseProjectFileWorker
                .moveIsolatedCourseRootToTrash(
                    activeIsolation,
                    expectedCourseID: courseID,
                    selfCheckDestination: selfCheckDestination
                )
            // 已进入废纸篓：不再回滚隔离目录。
            isolation = nil
            try courseProjectMutationHook(
                .afterCourseRootTrashMoveBeforeJournal
            )
            try courseProjectMutationHook(
                .afterCourseRootTrashJournalBeforeWorkspaceSave
            )

            guard await persistWorkspaceRemovingCourse(courseID) else {
                removeCourseLocalRegistration(courseID)
                if let receiptCleanup {
                    pendingCourseTrashReceiptCleanups.append(
                        receiptCleanup
                    )
                }
                save()
                if shouldDismissCourseWorkspace {
                    courseWorkspacePresented = false
                }
                finishCourseRemovalAttempt(
                    courseID,
                    token: prepared.token,
                    succeeded: true
                )
                return trashedRoot
            }

            removeCourseLocalRegistration(courseID)
            // ponytail: a crash after the workspace commit can leave one tiny
            // receipt; add a trusted cleanup index only if this becomes observable.
            if let receiptCleanup,
               !CourseProjectFileWorker.cleanupCourseTrashReceipt(
                receiptCleanup,
                identityResolver: importedFileIdentityResolver
               ) {
                pendingCourseTrashReceiptCleanups.append(
                    receiptCleanup
                )
            }
            if shouldDismissCourseWorkspace {
                courseWorkspacePresented = false
            }
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: true
            )
            return trashedRoot
        } catch {
            if let isolation {
                await courseProjectFileWorker.restoreCourseRootTrashIsolation(
                    isolation
                )
                if importedFileIdentityResolver(root) == rootIdentity,
                   let receiptCleanup {
                    CourseProjectFileWorker.cleanupCourseTrashReceipt(
                        receiptCleanup,
                        identityResolver: importedFileIdentityResolver
                    )
                }
            }
            finishCourseRemovalAttempt(
                courseID,
                token: prepared.token,
                succeeded: false
            )
            throw error
        }
    }

    func revealCourseRoot(_ courseID: UUID) {
        guard let root = courseRootURL(for: courseID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    func removeCourseFromWeiBeiForSelfCheck(
        _ courseID: UUID
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try waitForCourseFileOperation {
            try await self.removeCourseFromWeiBei(courseID)
        }
    }

    func deleteCourseForSelfCheck(_ courseID: UUID) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        try waitForCourseFileOperation {
            try await self.deleteCourse(courseID)
        }
    }

#if DEBUG
    func verifyCourseRemovalPersistenceRaceForSelfCheck(
        removing courseID: UUID,
        retaining retainedCourseID: UUID
    ) throws -> Bool {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            let transactionID = try self.beginCourseRemovalTransaction()
            defer {
                self.finishCourseRemovalTransaction(transactionID)
                self.usesBackgroundWorkspacePersistenceForSelfCheck = false
            }
            let prepared = try await self.prepareCourseRemoval(
                courseID,
                token: transactionID,
                requiresAvailableRoot: false
            )
            var removalSucceeded = false
            defer {
                self.finishCourseRemovalAttempt(
                    courseID,
                    token: prepared.token,
                    succeeded: removalSucceeded
                )
            }

            self.usesBackgroundWorkspacePersistenceForSelfCheck = true
            let firstGeneration = self.workspaceSaveGeneration &+ 1
            await self.courseProjectFileWorker
                .prepareWorkspacePersistenceGateForSelfCheck(
                    generation: firstGeneration
                )
            let removal = Task { @MainActor in
                await self.persistWorkspaceRemovingCourse(courseID)
            }
            await self.courseProjectFileWorker
                .waitUntilWorkspacePersistenceEnteredForSelfCheck(
                    generation: firstGeneration
                )

            guard let retainedIndex = self.courses.firstIndex(where: {
                $0.id == retainedCourseID
            }) else {
                await self.courseProjectFileWorker
                    .releaseWorkspacePersistenceForSelfCheck(
                        generation: firstGeneration
                    )
                _ = await removal.value
                return false
            }
            self.courses[retainedIndex].title = "保留课程（第二代）"
            self.courses[retainedIndex].updatedAt = Date()
            self.modelName = "课程移除第二代全局状态"
            self.workspaceSaveGeneration &+= 1
            let failingGeneration = self.workspaceSaveGeneration
            await self.courseProjectFileWorker
                .failWorkspacePersistenceForSelfCheck(
                    generation: failingGeneration
                )
            await self.courseProjectFileWorker
                .releaseWorkspacePersistenceForSelfCheck(
                    generation: firstGeneration
                )
            guard await removal.value,
                  self.workspaceSaveError != nil else {
                return false
            }

            let firstCommitted = try JSONDecoder().decode(
                PersistedWorkspace.self,
                from: Data(contentsOf: self.storageURL)
            )
            guard firstCommitted.courses?.contains(where: {
                $0.id == courseID
            }) != true else {
                return false
            }
            self.removeCourseLocalRegistration(courseID)
            removalSucceeded = true
            self.usesBackgroundWorkspacePersistenceForSelfCheck = false
            guard await self.flushPendingWorkspaceSaveAsync() else {
                return false
            }

            let compensated = try JSONDecoder().decode(
                PersistedWorkspace.self,
                from: Data(contentsOf: self.storageURL)
            )
            return self.course(withID: courseID) == nil
                && self.course(withID: retainedCourseID)?.title
                    == "保留课程（第二代）"
                && self.modelName == "课程移除第二代全局状态"
                && compensated.courses?.contains(where: {
                    $0.id == courseID
                }) != true
                && compensated.courses?.first(where: {
                    $0.id == retainedCourseID
                })?.title == "保留课程（第二代）"
                && compensated.modelName
                    == "课程移除第二代全局状态"
        }
    }
#endif

    @discardableResult
    func moveCourseFolderToTrashForSelfCheck(
        _ courseID: UUID
    ) throws -> URL {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        return try waitForCourseFileOperation {
            try await self.moveCourseFolderToTrash(courseID)
        }
    }

    func finishPendingCourseRemovalRecoveryForSelfCheck()
        throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        // S3：不再有课程移除 journal 恢复。
    }

    func recoverCourseTransactionsForSelfCheck() throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        // S3：不再从 journal 恢复；启动清理已覆盖残留事务目录。
        silentlyCleanupOrphanCourseTransactions()
    }

    func installCourseRemovalStateForSelfCheck(
        courseID: UUID,
        materialItemID: String,
        noteItemID: String,
        messageText: String,
        memoryText: String,
        globalMemoryText: String
    ) throws -> UUID {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        guard let material = importedItems.first(where: {
            $0.id == materialItemID
        }),
        let session = createStudySession(courseID: courseID) else {
            throw CourseRemovalError.courseNotFound
        }
        let message = AgentMessage(
            role: .user,
            text: messageText,
            source: nil
        )
        guard let sessionIndex = studySessions.firstIndex(where: {
            $0.id == session.id
        }) else {
            throw CourseRemovalError.courseNotFound
        }
        studySessions[sessionIndex].messages = [message]
        messages = [message]
        let memory = LearningMemoryEntry(
            kind: .progress,
            text: memoryText,
            evidence: "A0c 自检",
            origin: .agentInference,
            sessionID: session.id,
            messageID: message.id
        )
        learningMemoryStates.removeAll {
            $0.scope == .course(courseID)
        }
        learningMemoryStates.append(
            ScopedLearningMemoryState(
                scope: .course(courseID),
                revision: 1,
                entries: [memory]
            )
        )
        learningMemoryStates.removeAll { $0.scope == .global }
        learningMemoryStates.append(
            ScopedLearningMemoryState(
                scope: .global,
                revision: 1,
                entries: [
                    LearningMemoryEntry(
                        kind: .preference,
                        text: globalMemoryText,
                        evidence: "A0c 全局隔离自检",
                        origin: .userStatement
                    ),
                ]
            )
        )
        let location = StudyLocation(
            itemID: materialItemID,
            itemTitle: material.title,
            locationID: "a0c-removal",
            locationTitle: "A0c 自检位置",
            pageIndex: 2,
            lastStudiedAt: Date(),
            visitCount: 1
        )
        studyLocationsByCourseID[
            courseID.uuidString,
            default: [:]
        ][materialItemID] = location
        courseResumePoints.removeAll { $0.courseID == courseID }
        courseResumePoints.append(
            CourseResumePoint(
                courseID: courseID,
                materialLocation: location,
                chatID: session.id,
                noteItemID: noteItemID
            )
        )
        return session.id
    }

    func removeCourseRegistrationImmediatelyForSelfCheck(
        _ courseID: UUID
    ) {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        guard courses.contains(where: { $0.id == courseID }) else {
            return
        }
        removeCourseLocalRegistration(courseID)
        resolvedCourseRootURLs.removeValue(forKey: courseID)
        courseRootUnavailableReasons.removeValue(forKey: courseID)
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
    }

    private func prepareCourseRemoval(
        _ courseID: UUID,
        token: UUID,
        requiresAvailableRoot: Bool
    ) async throws -> (
        course: Course,
        root: URL?,
        rootIdentity: ImportedFileIdentity?,
        token: UUID
    ) {
        guard let expectedCourse = course(withID: courseID) else {
            throw CourseRemovalError.courseNotFound
        }
        guard activeCourseRemovalTransactionID == token,
              activeCourseRemovalTokens[courseID] == nil,
              activeCourseRebindTokens[courseID] == nil else {
            throw CourseRemovalError.courseBusy
        }

        let noteItemIDs = Set(
            courseItemMemberships.lazy.filter {
                $0.courseID == courseID
            }.map(\.itemID)
        )
        for itemID in noteItemIDs {
            flushPendingNotePersistence(for: itemID)
        }
        for itemID in noteItemIDs {
            while let task = courseNoteWriteTasksByItemID[itemID] {
                await task.value
            }
        }

        guard course(withID: courseID) == expectedCourse,
              activeCourseRemovalTransactionID == token,
              activeCourseRemovalTokens[courseID] == nil,
              activeCourseRebindTokens[courseID] == nil else {
            throw CourseRemovalError.courseBusy
        }
        activeCourseRemovalTokens[courseID] = token
        do {
            while activeCourseFileMutationCounts[courseID, default: 0] > 0 {
                await Task.yield()
            }
            cancelAgentRequestIfRunning(in: courseID)
            await agentStopTask?.value

            let reconciliationTask = courseReconciliationTask
            courseReconciliationTask?.cancel()
            courseReconciliationTask = nil
            await reconciliationTask?.value

            // S6-4：已取消 Agent 并等文件突变归零；不再因笔记/Agent 待写拒绝移除。
            guard course(withID: courseID) == expectedCourse,
                  activeCourseRemovalTransactionID == token,
                  activeCourseRemovalTokens[courseID] == token,
                  activeCourseFileMutationCounts[
                    courseID,
                    default: 0
                  ] == 0 else {
                throw CourseRemovalError.courseBusy
            }

            syncActiveStudySession()
            let root = courseRootURL(for: courseID)
            let rootIdentity = root.flatMap(
                importedFileIdentityResolver
            )
            if requiresAvailableRoot {
                guard let root,
                      let expectedIdentity =
                        expectedCourse.sourceRootIdentity,
                      rootIdentity == expectedIdentity else {
                    throw CourseRemovalError.courseRootUnavailable
                }
                try await validateRestoredCourseRootAsync(
                    root,
                    course: expectedCourse,
                    mustBeInsideLibrary:
                        expectedCourse.sourceRootRelativePath != nil
                )
                // Trash path still refuses when the live folder cannot accept the
                // latest portable state; unregister-only never requires that write.
                guard await persistWorkspaceNow(),
                      !dirtyPortableCourseIDs.contains(courseID),
                      !blockedPortableCourseIDs.contains(courseID),
                      !oversizedPortableCourseIDs.contains(courseID),
                      coursePortableStateRevisions[courseID] != nil,
                      coursePortableStateDigests[courseID] != nil,
                      coursePortableStateMatchesLastSaved(
                        courseID
                      ) else {
                    throw CourseRemovalError.latestStateNotSaved
                }
            }

            return (
                expectedCourse,
                root,
                rootIdentity,
                token
            )
        } catch {
            finishCourseRemovalAttempt(
                courseID,
                token: token,
                succeeded: false
            )
            throw error
        }
    }

    private func coursePortableStateMatchesLastSaved(
        _ courseID: UUID
    ) -> Bool {
        guard let revision =
                coursePortableStateRevisions[courseID],
              let expectedDigest =
                coursePortableStateDigests[courseID],
              let state = try? makeCoursePortableState(
                courseID: courseID,
                revision: revision,
                savedAt: Date(timeIntervalSince1970: 0)
              ),
              let digest = try? coursePortableStatePayloadDigest(
                state
              ) else {
            return false
        }
        return digest == expectedDigest
    }

    private func removeCourseLocalRegistration(_ courseID: UUID) {
        let removedItemIDs = Set(
            importedItems.compactMap { item -> String? in
                guard case .courseOwned(let ownerCourseID, _) = item.storage,
                      ownerCourseID == courseID else {
                    return nil
                }
                return item.id
            }
        )

        for itemID in removedItemIDs {
            pendingNotePersistenceTasks
                .removeValue(forKey: itemID)?.cancel()
            courseNoteLoadTasksByItemID
                .removeValue(forKey: itemID)?.cancel()
            courseNoteWriteTasksByItemID
                .removeValue(forKey: itemID)?.cancel()
            pendingNotePersistenceByItemID.removeValue(forKey: itemID)
            courseNoteLoadGenerationByItemID.removeValue(forKey: itemID)
            courseNoteWritesInFlight.remove(itemID)
            setNoteDraft(nil, for: itemID)
            pendingNoteWritesByItemID.removeValue(forKey: itemID)
            noteOperationErrorsByItemID.removeValue(forKey: itemID)
            noteBackingContentDigestsByItemID.removeValue(forKey: itemID)
            lastSelfWrittenNoteDigestsByItemID.removeValue(forKey: itemID)
            loadedCourseNoteTextByItemID.removeValue(forKey: itemID)
            studyLocationsByItemID.removeValue(forKey: itemID)
        }

        importedItems.removeAll {
            removedItemIDs.contains($0.id)
        }
        courseItemMemberships.removeAll {
            $0.courseID == courseID
        }
        noteSourceLinks.removeAll {
            removedItemIDs.contains($0.noteItemID)
                || removedItemIDs.contains($0.sourceItemID)
        }
        materialNotePairings = materialNotePairings.filter {
            !removedItemIDs.contains($0.key)
                && !removedItemIDs.contains($0.value)
        }
        noteMaterialPairings = noteMaterialPairings.filter {
            !removedItemIDs.contains($0.key)
                && !removedItemIDs.contains($0.value)
        }
        studyLocationsByCourseID.removeValue(
            forKey: courseID.uuidString
        )
        courseResumePoints.removeAll { $0.courseID == courseID }
        learningMemoryStates.removeAll {
            $0.scope == .course(courseID)
        }
        courseKnowledgeProfiles.removeAll { $0.courseID == courseID }
        courses.removeAll { $0.id == courseID }

        for index in studySessions.indices {
            studySessions[index].relatedCourseIDs.removeAll {
                $0 == courseID
            }
            studySessions[index].focusItemIDs.removeAll {
                removedItemIDs.contains($0)
            }
            if studySessions[index].materialItemID.map(
                removedItemIDs.contains
            ) == true {
                studySessions[index].materialItemID = nil
            }
        }

        selectionAskThreads = selectionAskThreads.compactMap {
            thread -> SelectionAskThread? in
            if thread.itemID.map(removedItemIDs.contains) == true {
                return nil
            }
            return thread
        }
        if activeSelectionAskThreadID.map({ id in
            !selectionAskThreads.contains { $0.id == id }
        }) == true {
            activeSelectionAskThreadID = nil
        }
        if selectionContext?.itemID.map(
            removedItemIDs.contains
        ) == true {
            selectionContext = nil
        }
        selectionAttachments.removeAll {
            $0.itemID.map(removedItemIDs.contains) == true
        }
        backNavigationStack.removeAll {
            $0.selectedItemID.map(removedItemIDs.contains) == true
                || $0.activeNotebookItemID.map(
                    removedItemIDs.contains
                ) == true
        }
        forwardNavigationStack.removeAll {
            $0.selectedItemID.map(removedItemIDs.contains) == true
                || $0.activeNotebookItemID.map(
                    removedItemIDs.contains
                ) == true
        }

        if selectedItemID.map(removedItemIDs.contains) == true {
            selectedItemID = importedItems.first(where: {
                $0.isCourseMaterial
            })?.id
        }
        if activeNotebookItemID.map(
            removedItemIDs.contains
        ) == true {
            activeNotebookItemID = importedItems.first(
                where: \.isNotebookNote
            )?.id
        }
        noteText = noteText(for: activeNoteItem)

        if activeCourseID == courseID {
            activeCourseID = courses.first?.id
        }
        if courseWorkspaceCourseID == courseID {
            courseWorkspaceCourseID = nil
            courseWorkspaceDestination = .hub
            courseWorkspaceTargetItemID = nil
        }

        ensureActiveStudySession()
        if let activeStudySessionID {
            restoreAgentDraft(for: activeStudySessionID)
        }
        if let activeStudySession {
            messages = activeStudySession.messages
            restoreAgentReplyState(from: activeStudySession)
        }

        coursePortableStateRevisions.removeValue(forKey: courseID)
        coursePortableStateDigests.removeValue(forKey: courseID)
        dirtyPortableCourseIDs.remove(courseID)
        blockedPortableCourseIDs.remove(courseID)
        oversizedPortableCourseIDs.remove(courseID)
    }

    private func finishCourseRemovalAttempt(
        _ courseID: UUID,
        token: UUID,
        succeeded: Bool,
        restartMaintenance: Bool = true
    ) {
        guard activeCourseRemovalTokens[courseID] == token else {
            return
        }
        activeCourseRemovalTokens.removeValue(forKey: courseID)
        if succeeded {
            let scopeKey = "course:\(courseID.uuidString)"
            activeCourseSecurityScopeOwnerTokens.removeValue(
                forKey: scopeKey
            )
            if let scopedURL = activeCourseSecurityScopes.removeValue(
                forKey: scopeKey
            ) {
                courseSecurityScopeStopper(scopedURL)
            }
            resolvedCourseRootURLs.removeValue(forKey: courseID)
            courseRootUnavailableReasons.removeValue(forKey: courseID)
            courseDocumentSearchIndex.synchronize(allItems)
            invalidateAgentContext()
        }
        if restartMaintenance,
           !WeiBeiSafetyTestMode.isEnabled {
            startCourseFileMaintenance()
        }
    }

    private func beginCourseRemovalTransaction(
        resumesPendingRecovery: Bool = false
    ) throws -> UUID {
        // S3：不再阻塞于 pending journal。
        guard activeCourseRemovalTransactionID == nil else {
            throw CourseRemovalError.courseBusy
        }
        let transactionID = UUID()
        activeCourseRemovalTransactionID = transactionID
        return transactionID
    }


    private func finishCourseRemovalTransaction(
        _ transactionID: UUID
    ) {
        guard activeCourseRemovalTransactionID == transactionID else {
            return
        }
        activeCourseRemovalTransactionID = nil
    }

    private func beginCourseFileMutation(
        courseIDs: Set<UUID>,
        itemIDs: Set<String> = []
    ) throws {
        guard courseIDs.allSatisfy({ courseID in
                courses.contains(where: { $0.id == courseID })
              }) else {
            throw CourseOwnedFileError.courseNotFound
        }
        guard courseIDs.allSatisfy({
            activeCourseRemovalTokens[$0] == nil
        }) else {
            throw CoursePortableExportError.unstableCourseState
        }
        guard itemIDs.allSatisfy({ itemID in
            importedItems.contains(where: { $0.id == itemID })
        }) else {
            throw CourseOwnedFileError.unsupportedFile
        }
        guard itemIDs.isDisjoint(with: activeItemFileMutationIDs) else {
            throw CourseOwnedFileError.itemBusy
        }
        let wasIdle = activeCourseFileMutationCounts.isEmpty
            && activeItemFileMutationIDs.isEmpty
        for courseID in courseIDs {
            activeCourseFileMutationCounts[courseID, default: 0] += 1
        }
        activeItemFileMutationIDs.formUnion(itemIDs)
        if wasIdle {
            pauseCourseFileWatchingForMutation()
        }
    }

    private func finishCourseFileMutation(
        courseIDs: Set<UUID>,
        itemIDs: Set<String> = []
    ) {
        for courseID in courseIDs {
            let count = activeCourseFileMutationCounts[
                courseID,
                default: 0
            ]
            if count <= 1 {
                activeCourseFileMutationCounts.removeValue(
                    forKey: courseID
                )
            } else {
                activeCourseFileMutationCounts[courseID] = count - 1
            }
        }
        activeItemFileMutationIDs.subtract(itemIDs)
        if activeCourseFileMutationCounts.isEmpty
            && activeItemFileMutationIDs.isEmpty {
            resumeCourseFileWatchingForMutation()
        }
    }


    private func promoteCourseOwnedItemToCommon(
        itemID: String,
        conflictResolution: CourseFileConflictResolution
    ) async throws {
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID
        }),
        case .courseOwned(let ownerCourseID, _) =
            importedItems[itemIndex].storage,
        let ownerRoot = courseRootURL(for: ownerCourseID),
        let membershipIndex = uniqueCourseOwnedMembershipIndex(
            itemID: itemID,
            courseID: ownerCourseID
        ),
        let relativePath = courseItemMemberships[membershipIndex]
            .courseRelativePath,
        let libraryRoot = courseLibraryRootURL else {
            throw CourseOwnedFileError.courseRootUnavailable
        }
        let role = CourseOwnedFileRole(item: importedItems[itemIndex])
        guard let sourceURL = safeCourseOwnedFileURL(
            relativePath: relativePath,
            role: role,
            inside: ownerRoot
        ) else {
            throw CourseOwnedFileError.verificationFailed
        }

        try beginCourseFileMutation(
            courseIDs: [ownerCourseID],
            itemIDs: [itemID]
        )
        defer {
            finishCourseFileMutation(
                courseIDs: [ownerCourseID],
                itemIDs: [itemID]
            )
        }

        let sourceInfo = try await courseProjectFileWorker
            .validatedRegularSource(sourceURL)
        let sourceSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sourceURL,
            expectedIdentity: sourceInfo.identity
        )
        let commonDirectory = try await courseProjectFileWorker
            .ensureRealDirectory(
                libraryRoot.appendingPathComponent(
                    role.commonDirectoryName,
                    isDirectory: true
                ),
                inside: libraryRoot
            )
        let targetURL = try resolvedCourseImportTarget(
            fileName: sourceURL.lastPathComponent,
            destinationDirectory: commonDirectory,
            role: role,
            conflictResolution: conflictResolution
        )
        guard !FileManager.default.fileExists(atPath: targetURL.path),
              let commonDirectoryIdentity = importedFileIdentityResolver(
                commonDirectory
              ) else {
            throw CourseOwnedFileError.replacementTargetIsShared
        }
        let operationID = UUID()
        let payloadURL = commonDirectory.appendingPathComponent(
            ".\(targetURL.lastPathComponent).weibei-promote-\(operationID.uuidString.lowercased())"
        )
        let previousItems = importedItems
        let previousMemberships = courseItemMemberships
        var sharedIdentity: ImportedFileIdentity?
        var workspaceCommitted = false

        do {
            let stagedIdentity = try await courseProjectFileWorker
                .copyAndVerify(
                    from: sourceURL,
                    generatedData: nil,
                    to: payloadURL,
                    expectedSnapshot: sourceSnapshot
                )
            let placedIdentity = try await courseProjectFileWorker
                .placeWithoutReplacement(
                    from: payloadURL,
                    to: targetURL,
                    courseRoot: libraryRoot,
                    destinationDirectory: commonDirectory,
                    expectedDestinationIdentity: commonDirectoryIdentity,
                    expectedSnapshot: sourceSnapshot
                )
            guard stagedIdentity == placedIdentity else {
                throw CourseOwnedFileError.verificationFailed
            }
            sharedIdentity = placedIdentity
            let targetInfo = try await courseProjectFileWorker.stableMetadata(
                at: targetURL,
                expectedIdentity: placedIdentity,
                expectedSnapshot: sourceSnapshot
            )
            guard let sharedRelativePath = CourseProjectPathPolicy
                .relativePath(of: targetURL, inside: libraryRoot) else {
                throw CourseOwnedFileError.unsafeCoursePath
            }

            importedItems[itemIndex].urlPath = targetURL.path
            importedItems[itemIndex].importedFileIdentity = placedIdentity
            importedItems[itemIndex].storage = .common(
                relativePath: sharedRelativePath
            )
            importedItems[itemIndex].subtitle = targetURL.lastPathComponent
            importedItems[itemIndex].fileByteCount = targetInfo.byteCount
            importedItems[itemIndex]
                .fileModificationTimeNanoseconds =
                targetInfo.modificationTimeNanoseconds
            courseItemMemberships.removeAll {
                $0.itemID == itemID && $0.courseID == ownerCourseID
            }
            guard await persistWorkspaceNow() else {
                throw CourseOwnedFileError.workspaceSaveFailed
            }
            workspaceCommitted = true

            let cleanup = await courseProjectFileWorker
                .isolateAndRemoveVerifiedFile(
                    at: sourceURL,
                    quarantineURL: sourceURL.deletingLastPathComponent()
                        .appendingPathComponent(
                            ".\(sourceURL.lastPathComponent).weibei-promote-cleanup-\(operationID.uuidString.lowercased())"
                        ),
                    expectedIdentity: sourceInfo.identity,
                    expectedSnapshot: sourceSnapshot,
                    remover: courseFileSourceRemover
                )
            if case .removed = cleanup {
            } else {
                // ponytail: a crash here can leave one harmless old duplicate;
                // add a cleanup journal only if this becomes observable in use.
                showImportantOperationError(ui(
                    "课程关系已移除，但课程文件夹中的旧副本未能清理。",
                    "The course relation was removed, but the old course copy could not be cleaned up."
                ))
            }
            courseDocumentSearchIndex.schedule([importedItems[itemIndex]])
            invalidateAgentContext()
        } catch {
            if !workspaceCommitted {
                importedItems = previousItems
                courseItemMemberships = previousMemberships
                if let sharedIdentity {
                    _ = await courseProjectFileWorker
                        .isolateAndRemoveVerifiedFile(
                            at: targetURL,
                            quarantineURL: commonDirectory
                                .appendingPathComponent(
                                    ".\(targetURL.lastPathComponent).weibei-promote-rollback-\(operationID.uuidString.lowercased())"
                                ),
                            expectedIdentity: sharedIdentity,
                            expectedSnapshot: sourceSnapshot,
                            remover: { try FileManager.default.removeItem(at: $0) }
                        )
                } else if FileManager.default.fileExists(
                    atPath: payloadURL.path
                ) {
                    try? FileManager.default.removeItem(at: payloadURL)
                }
            }
            throw error
        }
    }

    func removeItem(_ itemID: String, fromCourseID courseID: UUID) {
        var memberships = Set(courseIDs(for: itemID))
        memberships.remove(courseID)
        setCourseIDs(memberships, for: itemID)
    }

    private func reportCourseRelationOperationFailure(
        _ error: Error,
        operation: String,
        path: URL?,
        item: StudyItem,
        courseID: UUID,
        shouldContainRelation: Bool
    ) {
        recordCourseLibraryUIFailure(
            error,
            operation: operation,
            path: path
        )
        let relationMatches = courseIDs(for: item.id).contains(courseID)
            == shouldContainRelation
        let title = displayTitle(for: item)
        let message: String
        switch (shouldContainRelation, relationMatches) {
        case (true, true):
            message = ui(
                "“\(title)”已加入目标课程，内容已保住；旧位置未清理完成。请恢复课程文件夹访问后重试清理。",
                "“\(title)” was added to the target course and its content is safe, but the old location was not fully cleaned up. Restore access to the course folder, then retry the cleanup."
            )
        case (true, false):
            message = ui(
                "“\(title)”加入课程的操作未完整完成；磁盘文件和课程入口状态无法确认。请检查原位置、通用目录和课程目录后再试。",
                "The operation to add “\(title)” to the course did not fully complete. The disk file and course entry state could not be confirmed. Check the original location, common content, and course folder before trying again."
            )
        case (false, true):
            message = ui(
                "“\(title)”已从课程移除，共享原件仍安全保留；旧课程入口未清理完成。请恢复课程文件夹访问后重试清理。",
                "“\(title)” was removed from the course and the shared original is still safe, but the old course entry was not fully cleaned up. Restore access to the course folder, then retry the cleanup."
            )
        case (false, false):
            message = ui(
                "“\(title)”移出课程的操作未完整完成；磁盘文件和课程入口状态无法确认。请检查原位置、通用目录和课程目录后再试。",
                "The operation to remove “\(title)” from the course did not fully complete. The disk file and course entry state could not be confirmed. Check the original location, common content, and course folder before trying again."
            )
        }
        showImportantOperationError(message)
    }

    func setCourseIDs(_ courseIDs: Set<UUID>, for itemID: String) {
        guard !activeItemFileMutationIDs.contains(itemID),
              let item = importedItems.first(where: { $0.id == itemID }) else {
            return
        }
        let validCourseIDs = Set(courses.map(\.id))
        let requested = courseIDs.intersection(validCourseIDs)
        let current = Set(self.courseIDs(for: itemID))
        guard requested.union(current).allSatisfy({
            activeCourseRemovalTokens[$0] == nil
        }) else {
            return
        }
        guard requested != current else { return }
        let added = requested.subtracting(current)
        let removed = current.subtracting(requested)

        if case .common = item.storage,
           removed.isEmpty,
           let courseID = added.first,
           let sourceURL = item.url,
           confirmManagedCourseMove(
            sourceURL: sourceURL,
            courseID: courseID,
            role: CourseOwnedFileRole(item: item),
            verb: ui("移入课程", "Move into Course")
           ) {
            let resolution = courseImportConflictResolution(
                sourceURL: sourceURL,
                courseID: courseID,
                role: CourseOwnedFileRole(item: item)
            )
            guard let resolution else { return }
            Task { @MainActor [weak self] in
                do {
                    _ = try await self?.migrateLegacyExternalItemIntoCourse(
                        itemID: itemID,
                        courseID: courseID,
                        conflictResolution: resolution
                    )
                } catch {
                    guard let self else { return }
                    self.reportCourseRelationOperationFailure(
                        error,
                        operation: "move_common_item_into_course",
                        path: sourceURL,
                        item: item,
                        courseID: courseID,
                        shouldContainRelation: true
                    )
                }
            }
            return
        }
        if case .courseOwned(let ownerCourseID, _) = item.storage,
           added.count == 1,
           let courseID = added.first,
           let sourceURL = item.url {
            let movesOwnership = removed.contains(ownerCourseID)
            let role = CourseOwnedFileRole(item: item)
            let verb = movesOwnership
                ? ui("移到另一门课程", "Move to Another Course")
                : ui(
                    "转为\(role.commonDirectoryName)",
                    "Move to common content"
                )
            guard confirmManagedCourseMove(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                verb: verb
            ) else {
                return
            }
            let sharedConflictTarget = movesOwnership
                ? nil
                : courseLibraryRootURL?
                    .appendingPathComponent(
                        role.commonDirectoryName,
                        isDirectory: true
                    )
                    .appendingPathComponent(sourceURL.lastPathComponent)
            let resolution = courseImportConflictResolution(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                allowsReplace: movesOwnership,
                additionalProtectedTarget: sharedConflictTarget
            )
            guard let resolution else { return }
            Task { @MainActor [weak self] in
                do {
                    if movesOwnership {
                        _ = try await self?.moveCourseOwnedItem(
                            itemID: itemID,
                            toCourseID: courseID,
                            conflictResolution: resolution
                        )
                    } else {
                        try await self?.shareCourseOwnedItem(
                            itemID: itemID,
                            withCourseID: courseID,
                            conflictResolution: resolution
                        )
                    }
                } catch {
                    guard let self else { return }
                    self.reportCourseRelationOperationFailure(
                        error,
                        operation: movesOwnership
                            ? "move_course_owned_item"
                            : "share_course_owned_item",
                        path: sourceURL,
                        item: item,
                        courseID: courseID,
                        shouldContainRelation: true
                    )
                }
            }
            return
        }
        if case .courseOwned(let ownerCourseID, _) = item.storage,
           added.isEmpty,
           removed == [ownerCourseID],
           let sourceURL = item.url,
           let libraryRoot = courseLibraryRootURL {
            let role = CourseOwnedFileRole(item: item)
            let commonTarget = libraryRoot
                .appendingPathComponent(
                    role.commonDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(sourceURL.lastPathComponent)
            guard confirmPromotionToCommon(
                sourceURL: sourceURL,
                targetURL: commonTarget
            ),
            let resolution = commonContentConflictResolution(
                sourceURL: sourceURL,
                targetURL: commonTarget
            ) else {
                return
            }
            Task { @MainActor [weak self] in
                do {
                    try await self?.promoteCourseOwnedItemToCommon(
                        itemID: itemID,
                        conflictResolution: resolution
                    )
                } catch {
                    guard let self else { return }
                    self.recordCourseLibraryUIFailure(
                        error,
                        operation: "promote_course_item_to_common",
                        path: sourceURL
                    )
                    let becameCommon = self.importedItems.first {
                        $0.id == itemID
                    }.map {
                        if case .common = $0.storage { return true }
                        return false
                    } ?? false
                    self.showImportantOperationError(becameCommon
                        ? self.ui(
                            "“\(self.displayTitle(for: item))”已移出本课程，通用原件安全保留；课程文件夹中的旧副本未清理完成。请确认资料库可访问后重试清理。",
                            "“\(self.displayTitle(for: item))” was removed from this course and the common original is safe, but the old course copy was not fully cleaned up. Make sure the library is accessible, then retry the cleanup."
                        )
                        : self.ui(
                            "“\(self.displayTitle(for: item))”没有移出本课程；原文件和课程关系保持不变。请确认资料库可访问后重试。",
                            "“\(self.displayTitle(for: item))” was not removed from this course. The original file and course relation are unchanged. Make sure the library is accessible, then try again."
                        ))
                }
            }
            return
        }
        if case .common = item.storage {
            let role = CourseOwnedFileRole(item: item)
            if let courseID = added.first,
               let sourceURL = item.url,
               confirmManagedCourseMove(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                verb: ui("加入另一门课程", "Add to Another Course")
               ),
               let resolution = courseImportConflictResolution(
                sourceURL: sourceURL,
                courseID: courseID,
                role: role,
                allowsReplace: false
               ) {
                Task { @MainActor [weak self] in
                    do {
                        try await self?.shareCourseOwnedItem(
                            itemID: itemID,
                            withCourseID: courseID,
                            conflictResolution: resolution
                        )
                    } catch {
                        guard let self else { return }
                        self.reportCourseRelationOperationFailure(
                            error,
                            operation: "link_common_item_to_course",
                            path: sourceURL,
                            item: item,
                            courseID: courseID,
                            shouldContainRelation: true
                        )
                    }
                }
                return
            }
            if let courseID = removed.first {
                Task { @MainActor [weak self] in
                    do {
                        try await self?.removeSharedItem(
                            itemID: itemID,
                            fromCourseID: courseID
                        )
                    } catch {
                        guard let self else { return }
                        self.reportCourseRelationOperationFailure(
                            error,
                            operation: "remove_shared_item_from_course",
                            path: item.url,
                            item: item,
                            courseID: courseID,
                            shouldContainRelation: false
                        )
                    }
                }
                return
            }
        }

        // Legacy virtual memberships may still be removed without touching files.
        guard case .common = item.storage, added.isEmpty else { return }
        var memberships = courseMembershipIndex
        memberships.replaceCourses(for: itemID, courseIDs: requested)
        courseItemMemberships = memberships.values
        save()
    }

    private func confirmPromotionToCommon(
        sourceURL: URL,
        targetURL: URL
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = ui(
            "从本课程移除",
            "Remove from This Course"
        )
        alert.informativeText = ui(
            "原文件会先复制到通用目录，再解除课程关系。\n来源：\(sourceURL.path)\n目标：\(targetURL.path)",
            "The source will be copied to common content before its course relation is removed.\nSource: \(sourceURL.path)\nTarget: \(targetURL.path)"
        )
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("移除关系", "Remove Relation"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func commonContentConflictResolution(
        sourceURL: URL,
        targetURL: URL
    ) -> CourseFileConflictResolution? {
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return .cancel
        }
        let suggestedName = CourseKeepBothNaming.suggestedFileName(
            originalName: sourceURL.lastPathComponent,
            conflictingTargets: [targetURL]
        )
        let alert = NSAlert()
        alert.messageText = ui(
            "通用目录中已有同名文件",
            "A file with this name already exists"
        )
        alert.informativeText = "\(ui("冲突目标", "Conflicting target"))：\(targetURL.path)"
        let nameField = NSTextField(string: suggestedName)
        nameField.setAccessibilityLabel(ui("新文件名", "New file name"))
        nameField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = nameField
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("保留两份", "Keep Both"))
        guard alert.runModal() == .alertSecondButtonReturn else {
            return nil
        }
        let preferred = nameField.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return .keepBoth(
            preferredFileName: preferred.isEmpty ? suggestedName : preferred
        )
    }

    func confirmMoveItemSourceToTrash(_ itemID: String) {
        // 共享条目可能只存相对路径（历史数据），先从课程库根目录回填真实路径。
        _ = backfillSharedItemLocation(itemID: itemID)
        guard let item = importedItems.first(where: { $0.id == itemID }),
              !item.isSample,
              let sourceURL = item.url else {
            showImportantOperationError(ui(
                "找不到这份内容的真实原文件；魏碑没有删除课程记录。请先重新连接资料库或在 Finder 中确认文件位置。",
                "The original file could not be found. WeiBei did not delete the course record. Reconnect the library or confirm the file location in Finder."
            ))
            return
        }
        let affectedCourses = courseIDs(for: itemID).compactMap {
            course(withID: $0)?.title
        }
        let courseSummary = affectedCourses.isEmpty
            ? ui("没有课程关系", "No course relations")
            : affectedCourses.joined(separator: "、")
        let alert = NSAlert()
        alert.messageText = ui(
            "将原文件移到废纸篓？",
            "Move the Source File to Trash?"
        )
        alert.informativeText = ui(
            "这会把唯一原文件移到废纸篓，并从所有课程中删除。\n文件：\(displayTitle(for: item))\n路径：\(sourceURL.path)\n受影响课程：\(courseSummary)",
            "This moves the only source file to Trash and deletes it from every course.\nFile: \(displayTitle(for: item))\nPath: \(sourceURL.path)\nAffected courses: \(courseSummary)"
        )
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: ui("移到废纸篓", "Move to Trash"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task { @MainActor [weak self] in
            do {
                try await self?.moveItemSourceToTrash(itemID)
            } catch {
                guard let self else { return }
                self.recordCourseLibraryUIFailure(
                    error,
                    operation: "move_content_source_to_trash",
                    path: sourceURL
                )
                let message: String
                switch error as? ContentSourceRemovalError {
                case .itemUnavailable:
                    message = self.ui(
                        "找不到这份内容的真实原文件；课程记录没有删除。请重新连接资料库或在 Finder 中确认文件位置。",
                        "The original file could not be found, and the course record was not deleted. Reconnect the library or confirm the file location in Finder."
                    )
                case .sourceChanged:
                    message = self.ui(
                        "原文件在操作期间发生了变化；魏碑没有移动或覆盖它，课程关系保持不变。请核对文件后重试。",
                        "The original file changed during the operation. WeiBei did not move or overwrite it, and course relations are unchanged. Check the file, then try again."
                    )
                case .trashMoveFailed:
                    message = self.ui(
                        "删除未完整完成，魏碑无法确认原文件当前位置；课程记录变更未完成提交。请检查原位置和废纸篓后再操作。",
                        "Deletion did not fully complete, and WeiBei could not confirm the original file's current location. The course record change was not committed. Check the original location and Trash before continuing."
                    )
                case .workspaceSaveFailed:
                    message = self.ui(
                        "删除未完整完成，魏碑无法确认原文件当前位置；课程记录变更未完成提交。请检查原位置和废纸篓后再操作。",
                        "Deletion did not fully complete, and WeiBei could not confirm the original file's current location. The course record change was not committed. Check the original location and Trash before continuing."
                    )
                case .pendingChangesUnsaved:
                    message = self.ui(
                        "还有更改尚未写入磁盘；魏碑没有移动原文件。请先处理保存提示，再重试删除。",
                        "Some changes have not been written to disk. WeiBei did not move the original file. Resolve the save warning, then try deleting again."
                    )
                case nil:
                    message = self.ui(
                        "原文件没有移到废纸篓，课程记录保持不变。请确认资料库和废纸篓可用后重试。",
                        "The original file was not moved to Trash, and the course record is unchanged. Make sure the library and Trash are available, then try again."
                    )
                }
                self.showImportantOperationError(message)
            }
        }
    }

    /// 共享条目可能只存相对路径而没有 urlPath / 文件身份（历史数据）。
    /// 删除等需要真实路径的操作前，从课程库根目录解析并就地回填。
    @discardableResult
    private func backfillSharedItemLocation(itemID: String) -> Bool {
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID
        }),
              case .common(let relativePath) = importedItems[itemIndex].storage,
              let root = courseLibraryRootURL,
              let resolved = CourseProjectPathPolicy.resolvedRelativePath(
                  relativePath,
                  inside: root
              ) else {
            return false
        }
        if importedItems[itemIndex].urlPath == nil {
            importedItems[itemIndex].urlPath = resolved.path
        }
        if importedItems[itemIndex].importedFileIdentity == nil {
            importedItems[itemIndex].importedFileIdentity =
                importedFileIdentityResolver(resolved)
        }
        return importedItems[itemIndex].url != nil
    }

    private func moveItemSourceToTrash(_ itemID: String) async throws {
        guard importedItems.contains(where: { $0.id == itemID }) else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        let affectedCourseIDs = Set(courseIDs(for: itemID))
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: [itemID]
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: [itemID]
            )
        }
        flushPendingNotePersistence(for: itemID)
        while let task = courseNoteWriteTasksByItemID[itemID] {
            await task.value
        }
        guard await flushPendingWorkspaceSaveAsync() else {
            // 有待保存的更改没能写入磁盘时拒绝删除；这不是"找不到原文件"，
            // 分开报错避免误导（保存失败的具体原因见 workspaceSaveError / 日志）。
            throw ContentSourceRemovalError.pendingChangesUnsaved
        }
        guard let itemIndex = importedItems.firstIndex(where: {
            $0.id == itemID
        }) else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        _ = backfillSharedItemLocation(itemID: itemID)
        if case .common = importedItems[itemIndex].storage {
            _ = resolveTrackedImportedFile(at: itemIndex)
        }
        guard let sourceURL = importedItems[itemIndex].url,
              let expectedIdentity = importedItems[itemIndex]
                .importedFileIdentity else {
            throw ContentSourceRemovalError.itemUnavailable
        }
        let formerSharedLinks: [(url: URL, identity: ImportedFileIdentity)]
        if case .common = importedItems[itemIndex].storage {
            formerSharedLinks = courseItemMemberships.compactMap {
                membership in
                guard membership.itemID == itemID,
                      let root = courseRootURL(
                        for: membership.courseID
                      ),
                      let relativePath = membership.courseRelativePath,
                      let linkURL = Self.backgroundRawRelativeURL(
                        relativePath,
                        inside: root
                      ),
                      let identity = membership.entryIdentity else {
                    return nil
                }
                return (linkURL, identity)
            }
        } else {
            formerSharedLinks = []
        }
        let sourceSnapshot: CourseFileSnapshot
        do {
            sourceSnapshot = try await courseProjectFileWorker
                .stableSnapshot(
                    at: sourceURL,
                    expectedIdentity: expectedIdentity
                )
        } catch {
            throw ContentSourceRemovalError.sourceChanged
        }
        let trashMover = contentSourceTrashMover
        var movedTrashURL: URL?
        do {
            let trashURL = try await Task.detached(priority: .userInitiated) {
                try trashMover(sourceURL)
            }.value
            movedTrashURL = trashURL
            _ = try await courseProjectFileWorker.stableSnapshot(
                at: trashURL,
                expectedIdentity: expectedIdentity,
                expectedSnapshot: sourceSnapshot
            )
        } catch {
            if let movedTrashURL {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: movedTrashURL,
                    to: sourceURL
                )
            }
            throw ContentSourceRemovalError.trashMoveFailed
        }
        guard let trashURL = movedTrashURL else {
            throw ContentSourceRemovalError.trashMoveFailed
        }

        removeItemRegistration(itemID)
        guard await persistWorkspaceNow() else {
            _ = await courseProjectFileWorker.restoreIsolatedFile(
                from: trashURL,
                to: sourceURL
            )
            load()
            throw ContentSourceRemovalError.workspaceSaveFailed
        }

        await removeFormerSharedLinks(
            sourceURL: sourceURL,
            links: formerSharedLinks
        )
        courseDocumentSearchIndex.synchronize(allItems)
        invalidateAgentContext()
    }

    private func removeFormerSharedLinks(
        sourceURL: URL,
        links: [(url: URL, identity: ImportedFileIdentity)]
    ) async {
        for link in links {
            _ = await courseProjectFileWorker
                .isolateAndRemoveSymbolicLinkIfMatching(
                    at: link.url,
                    quarantineURL: link.url.deletingLastPathComponent()
                        .appendingPathComponent(
                            ".weibei-link-cleanup-\(UUID().uuidString.lowercased())"
                        ),
                    destinationURL: sourceURL,
                    expectedIdentity: link.identity
                )
        }
    }


    private func confirmManagedCourseMove(
        sourceURL: URL,
        courseID: UUID,
        role: CourseOwnedFileRole,
        verb: String
    ) -> Bool {
        guard let root = courseRootURL(for: courseID) else { return false }
        let target = root
            .appendingPathComponent(role.directoryName, isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent)
        let alert = NSAlert()
        alert.messageText = verb
        alert.informativeText = "\(ui("来源", "Source"))：\(sourceURL.path)\n\(ui("目标", "Target"))：\(target.path)"
        alert.addButton(withTitle: ui("取消", "Cancel"))
        alert.addButton(withTitle: verb)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func removeSharedItem(
        itemID: String,
        fromCourseID courseID: UUID
    ) async throws {
        let affectedCourseIDs: Set<UUID> = [courseID]
        try beginCourseFileMutation(
            courseIDs: affectedCourseIDs,
            itemIDs: [itemID]
        )
        defer {
            finishCourseFileMutation(
                courseIDs: affectedCourseIDs,
                itemIDs: [itemID]
            )
        }
        guard let item = importedItems.first(where: { $0.id == itemID }),
              case .common(let sharedRelativePath) = item.storage,
              let sharedURL = item.url,
              let sharedIdentity = item.importedFileIdentity,
              let root = courseRootURL(for: courseID),
              let membership = courseItemMemberships.first(where: {
                $0.courseID == courseID && $0.itemID == itemID
              }),
              let relativePath = membership.courseRelativePath,
              let linkURL = Self.backgroundRawRelativeURL(relativePath, inside: root),
              let linkIdentity = membership.entryIdentity else {
            return
        }
        let sharedSnapshot = try await courseProjectFileWorker.stableSnapshot(
            at: sharedURL,
            expectedIdentity: sharedIdentity
        )
        let transactionID = UUID()
        let transactionDirectory = try courseFileTransactionDirectory(
            transactionID: transactionID,
            inside: root
        )
        guard let transactionDirectoryIdentity = importedFileIdentityResolver(
            transactionDirectory
        ) else {
            throw CourseOwnedFileError.unsafeCoursePath
        }
        let isolatedLinkURL = transactionDirectory.appendingPathComponent(
            "isolated-link"
        )
        let previous = courseItemMemberships
        do {
            // S3：无 journal。隔离链接 → 更新登记 → 清理。
            try courseProjectMutationHook(.beforeSharedLinkIsolation)
            _ = try await courseProjectFileWorker.isolateSymbolicLinkIfMatching(
                at: linkURL,
                to: isolatedLinkURL,
                destinationURL: sharedURL,
                expectedIdentity: linkIdentity
            )
            try courseProjectMutationHook(
                .afterSharedLinkIsolationBeforeJournal
            )
        } catch {
            // S3：无 journal 恢复；崩溃注入也必须走回滚。
            if CourseProjectFileWorker.identity(at: linkURL) == nil {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: isolatedLinkURL,
                    to: linkURL
                )
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            throw error
        }
        courseItemMemberships.removeAll {
            $0.courseID == courseID && $0.itemID == itemID
        }
        guard await persistWorkspaceNow() else {
            courseItemMemberships = previous
            if CourseProjectFileWorker.identity(at: linkURL) == nil {
                _ = await courseProjectFileWorker.restoreIsolatedFile(
                    from: isolatedLinkURL,
                    to: linkURL
                )
            }
            await safelyRemoveSharedTransactionDirectoryInBackground(
                transactionDirectory,
                expectedIdentity: transactionDirectoryIdentity
            )
            return
        }
        do {
            try courseProjectMutationHook(
                .afterSharedLinkRemovalWorkspaceSaveBeforeJournal
            )
            guard await courseProjectFileWorker
                .isolateAndRemoveSymbolicLinkIfMatching(
                at: isolatedLinkURL,
                quarantineURL: transactionDirectory.appendingPathComponent(
                    "isolated-link-cleanup"
                ),
                destinationURL: sharedURL,
                expectedIdentity: linkIdentity
            ) else {
                throw CourseOwnedFileError.verificationFailed
            }
        } catch {
            // S3：已提交登记则不回滚；静默留下隔离链接供用户重做/清理。
            // 崩溃注入同样走此路径（无 journal 恢复）。
            _ = sharedRelativePath
            _ = sharedSnapshot
            throw error
        }
        await safelyRemoveSharedTransactionDirectoryInBackground(
            transactionDirectory,
            expectedIdentity: transactionDirectoryIdentity
        )
        invalidateAgentContext()
    }

    func removeSharedItemForSelfCheck(
        itemID: String,
        fromCourseID courseID: UUID
    ) throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        try waitForCourseFileOperation {
            try await self.removeSharedItem(itemID: itemID, fromCourseID: courseID)
        }
    }

    func promoteCourseOwnedItemToCommonForSelfCheck(
        itemID: String,
        conflictResolution: CourseFileConflictResolution = .cancel
    ) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try waitForCourseFileOperation {
            try await self.promoteCourseOwnedItemToCommon(
                itemID: itemID,
                conflictResolution: conflictResolution
            )
        }
    }

    func moveItemSourceToTrashForSelfCheck(_ itemID: String) throws {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        try waitForCourseFileOperation {
            try await self.moveItemSourceToTrash(itemID)
        }
    }

#if DEBUG
    func moveItemSourceToTrashWithBlockedBackgroundSaveForSelfCheck(
        _ itemID: String,
        whileBlocked: @escaping @MainActor () -> Void
    ) async throws {
        precondition(WeiBeiSafetyTestMode.isEnabled)
        let previousMode = usesBackgroundWorkspacePersistenceForSelfCheck
        usesBackgroundWorkspacePersistenceForSelfCheck = true
        defer { usesBackgroundWorkspacePersistenceForSelfCheck = previousMode }
        let generation = workspaceSaveGeneration &+ 1
        await courseProjectFileWorker.prepareWorkspacePersistenceGateForSelfCheck(
            generation: generation
        )
        let deletion = Task { @MainActor in
            try await self.moveItemSourceToTrash(itemID)
        }
        await courseProjectFileWorker.waitUntilWorkspacePersistenceEnteredForSelfCheck(
            generation: generation
        )
        whileBlocked()
        await courseProjectFileWorker.releaseWorkspacePersistenceForSelfCheck(
            generation: generation
        )
        try await deletion.value
    }
#endif

    func installRootlessCourseForSelfCheck(title: String) -> UUID {
        precondition(
            WeiBeiSafetyTestMode.isEnabled
        )
        let course = Course(
            title: title,
            colorIndex: nextCourseColorIndex()
        )
        courses.append(course)
        courseKnowledgeProfiles.append(
            CourseKnowledgeProfile(courseID: course.id)
        )
        activeCourseID = course.id
        save()
        return course.id
    }
}
