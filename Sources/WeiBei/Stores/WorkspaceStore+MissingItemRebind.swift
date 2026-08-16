import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func parentLocationIsAvailable(for item: StudyItem) -> Bool {
        switch item.storage {
        case .courseOwned(let courseID):
            return courseRootURL(for: courseID) != nil
        case .shared:
            return courseLibraryRootURL != nil
        case .legacyExternal, .bundledSample:
            return true
        }
    }

    /// 父目录还在、文件已经没了：只拿掉这一条登记。整夹找不到时留下条目。
    @discardableResult
    func forgetGoneImportedItem(at index: Int) -> (url: URL?, changed: Bool) {
        guard importedItems.indices.contains(index) else { return (nil, false) }
        let item = importedItems[index]
        let knownPath = item.urlPath ?? item.importedFileLastKnownPath
        let fileReadable = knownPath.map {
            FileManager.default.isReadableFile(atPath: $0)
        } ?? false
        if fileReadable {
            return keepUnavailableImportedItem(at: index)
        }
        guard ImportedFileRecovery.shouldForgetGoneSource(
            parentLocationAvailable: parentLocationIsAvailable(for: item),
            fileReadable: false,
            isSample: item.isSample
        ) else {
            return keepUnavailableImportedItem(at: index)
        }
        removeItemRegistration(item.id)
        return (nil, true)
    }

    func forgetGoneImportedItems(ids: [String]) -> Bool {
        var changed = false
        for itemID in ids {
            guard let index = importedItems.firstIndex(where: { $0.id == itemID }) else {
                continue
            }
            if forgetGoneImportedItem(at: index).changed {
                changed = true
            }
        }
        return changed
    }

    func keepUnavailableImportedItem(at index: Int) -> (url: URL?, changed: Bool) {
        guard importedItems.indices.contains(index) else { return (nil, false) }
        var changed = false
        if let currentPath = importedItems[index].urlPath {
            importedItems[index].importedFileLastKnownPath = currentPath
            importedItems[index].urlPath = nil
            changed = true
        }
        if importedItems[index].importedFileBookmarkData != nil {
            importedItems[index].importedFileBookmarkData = nil
            changed = true
        }
        return (nil, changed)
    }
}
