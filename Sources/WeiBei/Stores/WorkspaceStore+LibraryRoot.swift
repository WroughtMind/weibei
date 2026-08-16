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

    func refreshRuntimeItemURLs() {
        for index in importedItems.indices {
            if let url = resolvedLibraryURL(for: importedItems[index]) {
                importedItems[index].urlPath = url.path
            }
        }
    }

    func discoverTopLevelCourseFolders() {
        guard let libraryRoot = courseLibraryRootURL else { return }
        switch CourseProjectFileWorker.entryPresence(at: libraryRoot) {
        case .absent, .inaccessible:
            return
        case .present:
            break
        }
        let reserved: Set<String> = [
            CourseLibraryLayout.commonMaterialsDirectoryName,
            CourseLibraryLayout.commonNotesDirectoryName,
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
            let manifestURL = child
                .appendingPathComponent(".weibei", isDirectory: true)
                .appendingPathComponent("course.json")
            let existingID: UUID?
            if let data = try? Data(contentsOf: manifestURL),
               let manifest = try? JSONDecoder().decode(CourseProjectManifest.self, from: data) {
                existingID = manifest.courseID
            } else {
                existingID = nil
            }
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
