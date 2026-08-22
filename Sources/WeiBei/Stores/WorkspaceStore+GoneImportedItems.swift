import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    @discardableResult
    func forgetGoneImportedItem(at index: Int) -> (url: URL?, changed: Bool) {
        guard importedItems.indices.contains(index) else { return (nil, false) }
        let item = importedItems[index]
        if item.isSample {
            return (item.url, false)
        }
        if let libraryRoot = courseLibraryRootURL {
            switch CourseProjectFileWorker.entryPresence(at: libraryRoot) {
            case .absent, .inaccessible:
                return keepUnavailableImportedItem(at: index)
            case .present:
                break
            }
        }
        guard let candidate = resolvedLibraryURL(for: item) else {
            return keepUnavailableImportedItem(at: index)
        }
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .present:
            return (candidate.standardizedFileURL, false)
        case .inaccessible:
            return keepUnavailableImportedItem(at: index)
        case .absent:
            let parent = candidate.deletingLastPathComponent()
            switch CourseProjectFileWorker.entryPresence(at: parent) {
            case .present:
                removeItemRegistration(item.id)
                return (nil, true)
            case .absent, .inaccessible:
                return keepUnavailableImportedItem(at: index)
            }
        }
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
        if importedItems[index].urlPath != nil {
            importedItems[index].urlPath = nil
            changed = true
        }
        return (nil, changed)
    }

    func resolvedLibraryURL(for item: StudyItem) -> URL? {
        switch item.storage {
        case .bundledSample:
            return item.url
        case .common(let relativePath):
            guard let root = courseLibraryRootURL else { return nil }
            return CourseProjectPathPolicy.resolvedRelativePath(
                relativePath,
                inside: root
            )
        case .courseOwned(let courseID, let relativePath):
            guard let libraryRoot = courseLibraryRootURL,
                  let courseRoot = courseRootURL(for: courseID),
                  let courseRelative = CourseProjectPathPolicy.relativePath(
                    of: courseRoot,
                    inside: libraryRoot
                  ) else {
                return nil
            }
            return CourseProjectPathPolicy.resolvedRelativePath(
                "\(courseRelative)/\(relativePath)",
                inside: libraryRoot
            )
        }
    }
}
