import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func parentLocationIsAvailable(for item: StudyItem) -> Bool {
        switch parentLocationPresence(for: item) {
        case .present:
            return true
        case .absent, .inaccessible, .none:
            return false
        }
    }

    /// 只有文件确认不存在、且父位置仍在时，才拿掉这一条登记。
    @discardableResult
    func forgetGoneImportedItem(at index: Int) -> (url: URL?, changed: Bool) {
        guard importedItems.indices.contains(index) else { return (nil, false) }
        let item = importedItems[index]
        let fileURL = candidateFileURL(for: item)
        let filePresence = locationAvailability(
            CourseProjectFileWorker.entryPresence(at: fileURL)
        )
        let parentPresence = parentLocationPresence(for: item)
            ?? .inaccessible
        if !ImportedFileRecovery.shouldForgetGoneSource(
            file: filePresence,
            parent: parentPresence,
            isSample: item.isSample
        ) {
            if filePresence == .present {
                return (fileURL.standardizedFileURL, false)
            }
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

    private func candidateFileURL(for item: StudyItem) -> URL {
        switch item.storage {
        case .courseOwned(let courseID):
            if let root = courseRootURL(for: courseID),
               let relativePath = courseItemMemberships.first(where: {
                   $0.itemID == item.id && $0.courseID == courseID
               })?.courseRelativePath {
                return urlByAppendingRelativePath(relativePath, to: root)
            }
        case .shared(let relativePath):
            if let root = courseLibraryRootURL {
                return urlByAppendingRelativePath(relativePath, to: root)
            }
        case .legacyExternal, .bundledSample:
            break
        }
        let path = item.urlPath ?? item.importedFileLastKnownPath ?? ""
        return URL(fileURLWithPath: path)
    }

    private func parentLocationPresence(
        for item: StudyItem
    ) -> ImportedFileRecovery.LocationAvailability? {
        let parentURL: URL?
        switch item.storage {
        case .courseOwned(let courseID):
            parentURL = courseRootURL(for: courseID)
        case .shared:
            parentURL = courseLibraryRootURL
        case .legacyExternal, .bundledSample:
            parentURL = candidateFileURL(for: item).deletingLastPathComponent()
        }
        guard let parentURL, !parentURL.path.isEmpty, parentURL.path != "/" else {
            return nil
        }
        return locationAvailability(
            CourseProjectFileWorker.entryPresence(at: parentURL)
        )
    }

    private func locationAvailability(
        _ presence: CourseFileEntryPresence
    ) -> ImportedFileRecovery.LocationAvailability {
        switch presence {
        case .present:
            return .present
        case .absent:
            return .absent
        case .inaccessible:
            return .inaccessible
        }
    }

    private func urlByAppendingRelativePath(_ relativePath: String, to root: URL) -> URL {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else { return root }
        var url = root
        for (index, component) in components.enumerated() {
            url.appendPathComponent(
                component,
                isDirectory: index + 1 < components.count
            )
        }
        return url
    }
}
