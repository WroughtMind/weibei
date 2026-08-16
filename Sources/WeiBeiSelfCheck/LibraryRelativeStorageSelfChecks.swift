import Foundation
import WeiBeiCore

func checkLibraryRelativeStorage() throws {
    expect(
        CourseLibraryLayout.defaultRootURL().lastPathComponent
            == CourseLibraryLayout.defaultFolderName,
        "default library lives under Documents/魏碑资料库"
    )
    expect(
        CourseLibraryLayout.commonMaterialsDirectoryName == "通用资料"
            && CourseLibraryLayout.commonNotesDirectoryName == "通用笔记",
        "common folders use the locked names"
    )
    expect(
        CourseLibraryLayout.courseMaterialsDirectoryName == "文稿"
            && CourseLibraryLayout.courseNotesDirectoryName == "笔记",
        "course folders use the locked names"
    )

    let common = StudyItem(
        id: "imported:common",
        title: "讲义",
        subtitle: "讲义.pdf",
        kind: .pdf,
        urlPath: nil,
        isSample: false,
        storage: .common(relativePath: "通用资料/讲义.pdf")
    )
    let owned = StudyItem(
        id: "imported:owned",
        title: "课稿",
        subtitle: "课稿.pdf",
        kind: .pdf,
        urlPath: nil,
        isSample: false,
        storage: .courseOwned(
            ownerCourseID: UUID(),
            relativePath: "文稿/课稿.pdf"
        )
    )
    let encoded = try JSONEncoder().encode(common)
    let decoded = try JSONDecoder().decode(StudyItem.self, from: encoded)
    expect(
        decoded.storage == .common(relativePath: "通用资料/讲义.pdf"),
        "common storage round-trips by relative path"
    )
    let ownedDecoded = try JSONDecoder().decode(
        StudyItem.self,
        from: try JSONEncoder().encode(owned)
    )
    expect(
        ownedDecoded.storage.ownerCourseID != nil
            && ownedDecoded.storage.relativePath == "文稿/课稿.pdf",
        "course-owned storage keeps course ID and relative path"
    )
    let text = String(data: encoded, encoding: .utf8) ?? ""
    expect(
        !text.contains("legacyExternal")
            && !text.contains("importedFileLastKnownPath")
            && !text.contains("importedFileBookmarkData")
            && !text.contains("sharedRelativePath")
            && !text.contains("urlPath"),
        "new items do not persist the old external-file model"
    )

    let sample = StudyItem(
        id: "sample",
        title: "样例",
        subtitle: "样例",
        kind: .html,
        urlPath: nil,
        isSample: true
    )
    expect(sample.storage == .bundledSample, "samples stay bundledSample")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("weibei-library-relative-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let commonDir = root.appendingPathComponent("通用资料", isDirectory: true)
    try FileManager.default.createDirectory(at: commonDir, withIntermediateDirectories: true)
    let original = root.appendingPathComponent("outside.pdf")
    let originalBytes = Data("original-bytes".utf8)
    try originalBytes.write(to: original)
    let copied = try copyPreservingOriginalForCheck(from: original, into: commonDir)
    expect(
        copied.lastPathComponent == "outside.pdf"
            && FileManager.default.contents(atPath: copied.path) == originalBytes
            && FileManager.default.contents(atPath: original.path) == originalBytes,
        "import copies into the library and leaves the original file untouched"
    )
    let same = try copyPreservingOriginalForCheck(from: original, into: commonDir)
    expect(same.path == copied.path, "identical content reuses the existing library file")
    let otherOriginal = root.appendingPathComponent("outside-other.pdf")
    try Data("different-bytes".utf8).write(to: otherOriginal)
    let renamed = otherOriginal.deletingLastPathComponent()
        .appendingPathComponent("outside.pdf")
    try FileManager.default.removeItem(at: renamed)
    try FileManager.default.copyItem(at: otherOriginal, to: renamed)
    let second = try copyPreservingOriginalForCheck(from: renamed, into: commonDir)
    expect(
        second.lastPathComponent != "outside.pdf"
            && FileManager.default.contents(atPath: copied.path) == originalBytes
            && FileManager.default.contents(atPath: second.path) == Data("different-bytes".utf8),
        "same name with different content keeps both files"
    )

    let storeSource = try String(
        contentsOfFile: "Sources/WeiBei/Stores/WorkspaceStore.swift",
        encoding: .utf8
    )
    let libraryRootSource = try String(
        contentsOfFile: "Sources/WeiBei/Stores/WorkspaceStore+LibraryRoot.swift",
        encoding: .utf8
    )
    let modelsSource = try String(
        contentsOfFile: "Sources/WeiBeiCore/WorkspaceModels.swift",
        encoding: .utf8
    )
    let goneSource = try String(
        contentsOfFile: "Sources/WeiBei/Stores/WorkspaceStore+GoneImportedItems.swift",
        encoding: .utf8
    )
    expect(
        !modelsSource.contains("legacyExternal")
            && !modelsSource.contains("importedFileLastKnownPath")
            && !modelsSource.contains("importedFileBookmarkData")
            && !modelsSource.contains("case shared"),
        "SAFETY:library-relative-model StudyItem no longer stores the old external-file model"
    )
    expect(
        !goneSource.contains("ImportedFileRecovery")
            && goneSource.contains("resolvedLibraryURL"),
        "SAFETY:library-relative-gone gone-item handling uses library-relative paths instead of recovery"
    )
    expect(
        (storeSource.contains("copyExternalFileIntoLibrary")
            || libraryRootSource.contains("copyExternalFileIntoLibrary"))
            && libraryRootSource.contains("copyExternalFileIntoCourse")
            && libraryRootSource.contains("discoverTopLevelCourseFolders")
            && storeSource.contains("courseItemMemberships: nil"),
        "SAFETY:library-relative-import import, discovery, and persist follow the single-library model"
    )
}

private func copyPreservingOriginalForCheck(from sourceURL: URL, into directory: URL) throws -> URL {
    let sourceData = try Data(contentsOf: sourceURL)
    let preferred = directory.appendingPathComponent(sourceURL.lastPathComponent)
    if FileManager.default.fileExists(atPath: preferred.path) {
        let existing = try Data(contentsOf: preferred)
        if existing == sourceData {
            return preferred
        }
        let stem = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                try sourceData.write(to: candidate, options: [.atomic])
                return candidate
            }
            index += 1
        }
    }
    try sourceData.write(to: preferred, options: [.atomic])
    return preferred
}
