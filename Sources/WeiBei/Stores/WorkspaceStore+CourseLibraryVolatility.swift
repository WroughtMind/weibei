#if targetEnvironment(macCatalyst)
import UIKit
import UniformTypeIdentifiers
#else
import AppKit
#endif
import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    var isCourseLibraryRootVolatile: Bool {
        guard let path = courseLibraryRootPath, !path.isEmpty else { return false }
        return CourseLibraryVolatility.isVolatilePersistenceRoot(
            URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    func presentCourseLibraryMigrationPicker() {
#if targetEnvironment(macCatalyst)
        Task { @MainActor in
            guard let url = await WorkspaceFileDialog.pick(
                title: ui("更换魏碑资料库", "Change WeiBei Library"), types: [.folder], multiple: false
            ).first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { try await confirmAndConfigureCourseLibrary(at: url) }
            catch { presentCourseLibraryConfigurationError(error) }
        }
#else
        let panel = NSOpenPanel()
        panel.title = ui("更换魏碑资料库", "Change WeiBei Library")
        panel.message = ui(
            "选择一个新的本地文件夹作为魏碑资料库。魏碑会改用所选文件夹，课程文件不会被移动；课程记录保留，安全书签失败或保存失败时会回滚。",
            "Choose a new local folder as the WeiBei Library. WeiBei will switch to the chosen folder without moving any course files. Course records are kept; bookmark or save failures roll back."
        )
        panel.prompt = ui("使用此目录", "Use This Folder")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                try await confirmAndConfigureCourseLibrary(at: url)
            } catch {
                presentCourseLibraryConfigurationError(error)
            }
        }
#endif
    }

    func confirmAndConfigureCourseLibrary(at url: URL) async throws {
        let canonical = try CourseProjectPathPolicy.existingDirectory(url)
        if CourseLibraryVolatility.isVolatilePersistenceRoot(canonical) {
            guard await confirmVolatileCourseLibraryUse(at: canonical) else { return }
        }
        try await configureCourseLibraryAsync(at: canonical)
    }

    @discardableResult
    func confirmVolatileCourseLibraryUse(at url: URL) async -> Bool {
        let choice = await WorkspaceFileDialog.choose(
            title: ui("该位置不保证持久，系统可能清理", "This location is not durable and the system may delete it"),
            message: ui(
                "当前选择：\(url.path)\n默认不会采用这个目录。只有点击“仍要使用此目录”后，魏碑才会继续。",
                "Current choice: \(url.path)\nWeiBei will not use this folder unless you click “Use This Folder Anyway”."
            ), buttons: [ui("选择其他目录", "Choose Another Folder"), ui("仍要使用此目录", "Use This Folder Anyway")]
        )
        return choice.index == 1
    }

    private func presentCourseLibraryConfigurationError(_ error: Error) {
        recordCourseLibraryUIFailure(error, operation: "configure_library")
        let reason = (error as? CourseProjectRootError)?.errorDescription
            ?? error.localizedDescription
        Task { @MainActor in
            _ = await WorkspaceFileDialog.choose(
                title: ui("无法更换魏碑资料库", "Could not change the WeiBei Library"),
                message: ui(
                    "资料库没有更换，原课程记录和文件保持不变。原因：\(reason)",
                    "The library was not changed. Existing course records and files remain in place. Reason: \(error.localizedDescription)"
                ), buttons: [ui("好", "OK")]
            )
        }
    }

    func recordCourseLibraryUIFailure(
        _ error: Error,
        operation: String,
        path: URL? = nil
    ) {
        let diagnosticPath = path?.path ?? ""
        WeiBeiLog.workspace.error(
            "code=course_library_ui_failure operation=\(operation, privacy: .public) underlying=\(WeiBeiLog.code(error), privacy: .public) path=\(diagnosticPath, privacy: .private) detail=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
        )
    }
}
