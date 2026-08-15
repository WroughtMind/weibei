import AppKit
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
        let panel = NSOpenPanel()
        panel.title = ui("迁移/更换魏碑资料库", "Move / Change WeiBei Library")
        panel.message = ui(
            "选择一个更持久的本地文件夹作为新的魏碑资料库。即使当前资料库仍可访问，也可以更换。课程记录会保留；安全书签失败或保存失败时会回滚。",
            "Choose a more durable local folder as the WeiBei Library. This remains available even while the current library is still reachable. Course records are kept; bookmark or save failures roll back."
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
    }

    func confirmAndConfigureCourseLibrary(at url: URL) async throws {
        let canonical = try CourseProjectPathPolicy.existingDirectory(url)
        if CourseLibraryVolatility.isVolatilePersistenceRoot(canonical) {
            guard confirmVolatileCourseLibraryUse(at: canonical) else { return }
        }
        try await configureCourseLibraryAsync(at: canonical)
    }

    @discardableResult
    func confirmVolatileCourseLibraryUse(at url: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ui(
            "该位置不保证持久，系统可能清理",
            "This location is not durable and the system may delete it"
        )
        alert.informativeText = ui(
            "当前选择：\(url.path)\n默认不会采用这个目录。只有点击“仍要使用此目录”后，魏碑才会继续。",
            "Current choice: \(url.path)\nWeiBei will not use this folder unless you click “Use This Folder Anyway”."
        )
        alert.addButton(withTitle: ui("选择其他目录", "Choose Another Folder"))
        alert.addButton(withTitle: ui("仍要使用此目录", "Use This Folder Anyway"))
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func presentCourseLibraryConfigurationError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ui("无法更换魏碑资料库", "Could not change the WeiBei Library")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: ui("好", "OK"))
        alert.runModal()
    }
}
