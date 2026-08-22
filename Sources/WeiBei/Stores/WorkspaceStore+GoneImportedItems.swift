import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    /// 副本先行（计划 §5 阶段2）：采用外部内容或销毁条目前，把未落盘内容存入备份环。
    func backUpUnsavedNoteContentBeforeAdopting(itemID: String) {
        guard let unsaved = pendingNotePersistenceByItemID[itemID]?.markdown
            ?? notesByItemID[itemID] else {
            return
        }
        _ = try? NoteBackupRing.capture(
            content: Data(unsaved.utf8),
            itemID: itemID,
            rootURL: noteBackupRootURL
        )
    }

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
            case .present, .presentUnmaterialized:
                break
            }
        }
        guard let candidate = resolvedLibraryURL(for: item) else {
            return keepUnavailableImportedItem(at: index)
        }
        switch CourseProjectFileWorker.entryPresence(at: candidate) {
        case .present:
            fileMissingSinceByItemID.removeValue(forKey: item.id)
            return (candidate.standardizedFileURL, false)
        case .presentUnmaterialized:
            // iCloud 占位符在：永不判缺席，也不进入灰态（计划 §5 阶段3）。
            fileMissingSinceByItemID.removeValue(forKey: item.id)
            return (candidate.standardizedFileURL, false)
        case .inaccessible:
            return keepUnavailableImportedItem(at: index)
        case .absent:
            let parent = candidate.deletingLastPathComponent()
            switch CourseProjectFileWorker.entryPresence(at: parent) {
            case .present, .presentUnmaterialized:
                // 灰态保护（计划 §5 阶段2）：iCloud 瞬断/同步延迟期间文件缺席
                // 不立即销毁条目；连续两个对账周期（≈6 秒）仍缺席才移除，
                // 移除前对未落盘内容副本先行。文件重新出现按相对路径认领回原条目。
                if let missingSince = fileMissingSinceByItemID[item.id] {
                    if Date().timeIntervalSince(missingSince) >= 6.0 {
                        backUpUnsavedNoteContentBeforeAdopting(itemID: item.id)
                        removeItemRegistration(item.id)
                        fileMissingSinceByItemID.removeValue(forKey: item.id)
                        return (nil, true)
                    }
                } else {
                    fileMissingSinceByItemID[item.id] = Date()
                }
                return keepUnavailableImportedItem(at: index)
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
