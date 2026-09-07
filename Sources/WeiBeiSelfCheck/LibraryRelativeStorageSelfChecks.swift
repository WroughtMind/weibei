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

    let storeSource = try String(
        contentsOfFile: "Sources/WeiBei/Stores/WorkspaceStore.swift",
        encoding: .utf8
    )
    let courseMaintenanceSource = try String(
        contentsOfFile: "Sources/WeiBei/Stores/WorkspaceStore+CourseMaintenance.swift",
        encoding: .utf8
    )
    let courseLibrarySource = try String(
        contentsOfFile: "Sources/WeiBei/Stores/WorkspaceStore+CourseLibrary.swift",
        encoding: .utf8
    )
    let coursePortableSource = try String(
        contentsOfFile: "Sources/WeiBei/Stores/WorkspaceStore+CoursePortable.swift",
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
    // 源码文本只做「不得出现」式墓碑检查,防止已删模型复活;
    // 禁止「必须包含某标识符」式形状锁:不验证行为,重构改名即误报(2026-08-25 测试审计定案)。
    expect(
        !modelsSource.contains("legacyExternal")
            && !modelsSource.contains("importedFileLastKnownPath")
            && !modelsSource.contains("importedFileBookmarkData")
            && !modelsSource.contains("case shared"),
        "SAFETY:library-relative-model StudyItem no longer stores the old external-file model"
    )
    expect(
        !goneSource.contains("ImportedFileRecovery")
            && !goneSource.contains("legacyFileURL"),
        "SAFETY:library-relative-gone gone-item handling stays off the old recovery and legacy-file paths"
    )
    let flattenedStoreSource = (
        storeSource + "\n" + courseMaintenanceSource + "\n" + courseLibrarySource
            + "\n" + coursePortableSource
    )
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    expect(
        !flattenedStoreSource.contains("?? activeCourseID ?? sourceItem"),
        "SAFETY:library-relative-notes blank notes no longer inherit the sidebar-active course through a fallback chain"
    )
    let hubSource = try String(
        contentsOfFile: "Sources/WeiBei/Views/CourseHubView.swift",
        encoding: .utf8
    )
    expect(
        !hubSource.contains("纳入已有文件夹")
            && !hubSource.contains("Add existing folder"),
        "SAFETY:library-inside-entry App no longer offers in-place adoption of outside course folders"
    )
}
