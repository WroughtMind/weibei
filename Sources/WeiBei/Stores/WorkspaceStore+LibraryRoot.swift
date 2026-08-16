import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func bootstrapDefaultLibraryIfNeeded() {
        guard courseLibraryRootURL == nil else { return }
        let root = CourseLibraryLayout.defaultRootURL()
        do {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(
                    CourseLibraryLayout.commonMaterialsDirectoryName,
                    isDirectory: true
                ),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(
                    CourseLibraryLayout.commonNotesDirectoryName,
                    isDirectory: true
                ),
                withIntermediateDirectories: true
            )
            try configureCourseLibrary(at: root)
        } catch {
            showTransientNoteStatus(error.localizedDescription)
        }
    }

    func copyExternalFileIntoLibrary(
        _ sourceURL: URL,
        isNote: Bool
    ) throws -> URL {
        guard let libraryRoot = courseLibraryRootURL else {
            throw CourseProjectRootError.missingLibrary
        }
        let directoryName = isNote
            ? CourseLibraryLayout.commonNotesDirectoryName
            : CourseLibraryLayout.commonMaterialsDirectoryName
        let directory = libraryRoot.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try copyPreservingOriginal(from: sourceURL, into: directory)
    }

    func copyExternalFileIntoCourse(
        _ sourceURL: URL,
        courseID: UUID,
        isNote: Bool
    ) throws -> URL {
        guard let courseRoot = courseRootURL(for: courseID) else {
            throw CourseProjectRootError.unavailableLibrary
        }
        let directoryName = isNote
            ? CourseLibraryLayout.courseNotesDirectoryName
            : CourseLibraryLayout.courseMaterialsDirectoryName
        let directory = courseRoot.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try copyPreservingOriginal(from: sourceURL, into: directory)
    }

    func copyPreservingOriginal(from sourceURL: URL, into directory: URL) throws -> URL {
        let sourceData = try Data(contentsOf: sourceURL)
        let preferred = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: preferred.path) {
            let existing = try Data(contentsOf: preferred)
            if existing == sourceData {
                return preferred
            }
            let unique = uniqueCopyURL(in: directory, preferred: preferred)
            try sourceData.write(to: unique, options: [.atomic])
            return unique
        }
        try sourceData.write(to: preferred, options: [.atomic])
        return preferred
    }

    func libraryRelativePath(of url: URL) -> String? {
        guard let root = courseLibraryRootURL else { return nil }
        return CourseProjectPathPolicy.relativePath(of: url, inside: root)
    }

    func applyBoundLibraryRoot(
        _ resolvedRoot: URL,
        identity: ImportedFileIdentity?,
        bookmark: Data?,
        securityScope: URL? = nil
    ) {
        if let securityScope {
            activeCourseSecurityScopes["library"] = securityScope
        }
        courseLibraryRootURL = resolvedRoot
        courseLibraryUnavailableReason = nil
        if courseLibraryRootPath != resolvedRoot.path {
            courseLibraryRootPath = resolvedRoot.path
        }
        if let identity {
            courseLibraryRootIdentity = identity
        }
        if let bookmark {
            courseLibraryRootBookmarkData = bookmark
        }
    }

    func markLibraryUnavailable(_ reason: String) {
        courseLibraryUnavailableReason = reason
    }

    func resolveRegisteredCourseFolder(
        relativePath: String,
        expectedIdentity: ImportedFileIdentity?,
        courseID: UUID,
        inside libraryRoot: URL
    ) -> URL? {
        let expectedURL = CourseProjectPathPolicy.resolvedRelativePath(
            relativePath,
            inside: libraryRoot
        )
        let liveIdentity = expectedURL.flatMap(importedFileIdentityResolver)
        if let expectedURL, let expectedIdentity, let liveIdentity,
           expectedIdentity.matchesAcrossVolumeDrift(liveIdentity) {
            return expectedURL
        }
        if let expectedURL, courseManifestCourseID(at: expectedURL) == courseID {
            return expectedURL
        }
        if let expectedIdentity {
            return findDirectory(with: expectedIdentity, inside: libraryRoot)
        }
        return nil
    }

    func courseManifestCourseID(at root: URL) -> UUID? {
        let manifestURL = root
            .appendingPathComponent(".weibei", isDirectory: true)
            .appendingPathComponent("course.json")
        guard let data = try? CourseProjectFileWorker.readBoundedRegularFile(
            at: manifestURL,
            maximumByteCount: 1_048_576
        ),
        let manifest = try? JSONDecoder().decode(CourseProjectManifest.self, from: data) else {
            return nil
        }
        return manifest.courseID
    }

    @discardableResult
    func bindLibraryRootFromBookmark() -> Bool {
        guard let bookmark = courseLibraryRootBookmarkData,
              let expectedIdentity = courseLibraryRootIdentity,
              let resolution = courseRootBookmarkResolver(bookmark) else {
            return false
        }
        let scopedURL = resolution.url
        guard courseSecurityScopeStarter(scopedURL) else {
            return false
        }
        guard let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(scopedURL),
              let liveIdentity = importedFileIdentityResolver(resolvedRoot),
              expectedIdentity.matchesAcrossVolumeDrift(liveIdentity) else {
            courseSecurityScopeStopper(scopedURL)
            return false
        }
        do {
            try validateLibraryRoot(resolvedRoot)
        } catch {
            courseSecurityScopeStopper(scopedURL)
            return false
        }
        applyBoundLibraryRoot(
            resolvedRoot,
            identity: liveIdentity,
            bookmark: resolution.isStale
                ? courseRootBookmarkMaker(resolvedRoot) ?? bookmark
                : bookmark,
            securityScope: scopedURL
        )
        return true
    }

    @discardableResult
    func bindLibraryRootOnThisComputer() -> Bool {
        let candidates = CourseLibraryRootRecovery.candidates(
            storedPath: courseLibraryRootPath,
            defaultRoot: CourseLibraryLayout.defaultRootURL(),
            includePerUserDefault: !WeiBeiSafetyTestMode.isEnabled
        )
        for candidate in candidates {
            guard let resolvedRoot = try? CourseProjectPathPolicy.existingDirectory(candidate) else {
                continue
            }
            let liveIdentity = importedFileIdentityResolver(resolvedRoot)
            let matchingCourses = courses.reduce(into: 0) { count, course in
                guard let relativePath = course.sourceRootRelativePath,
                      let folder = CourseProjectPathPolicy.resolvedRelativePath(
                        relativePath,
                        inside: resolvedRoot
                      ),
                      courseManifestCourseID(at: folder) == course.id else {
                    return
                }
                count += 1
            }
            guard CourseLibraryRootRecovery.shouldAccept(
                liveIdentity: liveIdentity,
                expectedIdentity: courseLibraryRootIdentity,
                matchingRegisteredCourseCount: matchingCourses
            ) else { continue }
            do {
                try validateLibraryRoot(resolvedRoot)
            } catch {
                markLibraryUnavailable(error.localizedDescription)
                continue
            }
            applyBoundLibraryRoot(
                resolvedRoot,
                identity: liveIdentity ?? courseLibraryRootIdentity,
                bookmark: courseRootBookmarkMaker(resolvedRoot)
            )
            return true
        }
        return false
    }

    func refreshRuntimeItemURLs() {
        for index in importedItems.indices {
            guard let url = resolvedLibraryURL(for: importedItems[index]) else {
                continue
            }
            switch CourseProjectFileWorker.entryPresence(at: url) {
            case .absent, .inaccessible:
                importedItems[index].urlPath = nil
            case .present:
                importedItems[index].urlPath = url.path
                if let actual = try? CourseProjectFileWorker.snapshotFile(at: url) {
                    importedItems[index].contentDigest = actual.sha256
                    importedItems[index].importedFileIdentity =
                        importedFileIdentityResolver(url)
                        ?? importedItems[index].importedFileIdentity
                }
            }
        }
    }

    private func uniqueCopyURL(in directory: URL, preferred: URL) -> URL {
        let stem = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
