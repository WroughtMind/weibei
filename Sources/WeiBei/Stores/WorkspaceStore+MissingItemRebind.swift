import AppKit
import Foundation
import UniformTypeIdentifiers
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func isImportedSourceMissing(_ item: StudyItem) -> Bool {
        guard !item.isSample else { return false }
        if item.urlPath != nil { return false }
        return item.importedFileIdentity != nil
            || item.importedFileBookmarkData != nil
            || item.importedFileLastKnownPath != nil
    }

    var selectedImportedSourceIsMissing: Bool {
        if let selectedItemID,
           let item = importedItems.first(where: { $0.id == selectedItemID }) {
            return isImportedSourceMissing(item)
        }
        if let activeNotebookItemID,
           let item = importedItems.first(where: { $0.id == activeNotebookItemID }) {
            return isImportedSourceMissing(item)
        }
        return false
    }

    var missingImportedSourceDisplayTitle: String {
        if let selectedItemID,
           let item = importedItems.first(where: { $0.id == selectedItemID }),
           isImportedSourceMissing(item) {
            return displayTitle(for: item)
        }
        if let activeNotebookItemID,
           let item = importedItems.first(where: { $0.id == activeNotebookItemID }),
           isImportedSourceMissing(item) {
            return displayTitle(for: item)
        }
        return ""
    }

    func presentRebindPanelForMissingImportedItem(_ itemID: String) {
        guard let item = importedItems.first(where: { $0.id == itemID }),
              isImportedSourceMissing(item) else { return }
        let panel = NSOpenPanel()
        panel.title = ui("重新选择文件", "Choose the File Again")
        panel.message = ui(
            "只更新原来的这一条记录。不会新建条目，也不会改课程关系、笔记正文、来源或草稿。",
            "This updates the original item only. It will not create a duplicate or change course relations, note text, sources, or drafts."
        )
        panel.prompt = ui("绑定到此文件", "Bind to This File")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        if item.isNotebookNote {
            panel.allowedContentTypes = [
                UTType(filenameExtension: "md") ?? .plainText,
                UTType(filenameExtension: "markdown") ?? .plainText,
            ]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                try await rebindMissingImportedItem(id: itemID, to: url)
            } catch {
                presentMissingItemRebindError(error)
            }
        }
    }

    func presentRebindPanelForSelectedMissingImportedItem() {
        if let selectedItemID,
           let item = importedItems.first(where: { $0.id == selectedItemID }),
           isImportedSourceMissing(item) {
            presentRebindPanelForMissingImportedItem(item.id)
            return
        }
        if let activeNotebookItemID,
           let item = importedItems.first(where: { $0.id == activeNotebookItemID }),
           isImportedSourceMissing(item) {
            presentRebindPanelForMissingImportedItem(item.id)
        }
    }

    func rebindMissingImportedItem(id itemID: String, to url: URL) async throws {
        guard let index = importedItems.firstIndex(where: { $0.id == itemID }) else {
            throw MissingItemRebindError.itemNotFound
        }
        let original = importedItems[index]
        guard isImportedSourceMissing(original) else {
            throw MissingItemRebindError.itemNotMissing
        }
        let standardized = url.standardizedFileURL
        guard FileManager.default.isReadableFile(atPath: standardized.path) else {
            throw MissingItemRebindError.fileUnreadable
        }
        guard let identity = importedFileIdentityResolver(standardized) else {
            throw MissingItemRebindError.identityUnavailable
        }
        guard let bookmark = Self.makeImportedFileBookmark(for: standardized) else {
            throw MissingItemRebindError.bookmarkUnavailable
        }

        importedItems[index].urlPath = standardized.path
        importedItems[index].importedFileLastKnownPath = standardized.path
        importedItems[index].importedFileIdentity = identity
        importedItems[index].importedFileBookmarkData = bookmark
        importedItems[index].title = standardized.deletingPathExtension().lastPathComponent
        importedItems[index].subtitle = standardized.lastPathComponent
        importedItems[index].kind = StudyItemKind.detect(from: standardized)

        let saved = await persistWorkspaceNow()
        if !saved {
            importedItems[index] = original
            throw MissingItemRebindError.workspaceSaveFailed
        }
    }

    private func presentMissingItemRebindError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ui("无法重新绑定这个文件", "Could not rebind this file")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: ui("好", "OK"))
        alert.runModal()
    }
}

enum MissingItemRebindError: LocalizedError {
    case itemNotFound
    case itemNotMissing
    case fileUnreadable
    case identityUnavailable
    case bookmarkUnavailable
    case workspaceSaveFailed

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "找不到原来的条目。"
        case .itemNotMissing:
            return "这个条目当前不是缺失状态。"
        case .fileUnreadable:
            return "无法读取所选文件。"
        case .identityUnavailable:
            return "无法确认所选文件的身份。"
        case .bookmarkUnavailable:
            return "无法为所选文件创建安全书签，原记录未改动。"
        case .workspaceSaveFailed:
            return "保存失败，原记录未改动。"
        }
    }
}
