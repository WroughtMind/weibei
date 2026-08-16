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
        let candidate = resolvedLibraryURL(for: item)
            ?? item.url
            ?? legacyFileURL(from: item.id)
        guard let candidate else {
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

    private func legacyFileURL(from itemID: String) -> URL? {
        guard itemID.hasPrefix("file:") else { return nil }
        let path = String(itemID.dropFirst("file:".count))
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    func resolvedLibraryURL(for item: StudyItem) -> URL? {
        switch item.storage {
        case .bundledSample:
            return item.url
        case .common(let relativePath):
            // Leftover file: items decode as common(subtitle), e.g. "笔记.md".
            // That is not a library-relative path and must not resolve under the root.
            guard let root = courseLibraryRootURL,
                  relativePath.contains("/") else { return nil }
            return root.appendingPathComponent(relativePath)
        case .courseOwned(let courseID, let relativePath):
            guard let root = courseRootURL(for: courseID),
                  relativePath.contains("/") else { return nil }
            return root.appendingPathComponent(relativePath)
        }
    }
}
