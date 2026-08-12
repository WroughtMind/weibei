import Foundation
import WeiBeiCore

private actor CourseSidebarTagParser {
    func tags(in markdown: String) -> [String]? {
        try? MarkdownTagSearch.cancellableTags(in: markdown)
    }
}

@MainActor
final class CourseSidebarTagState {
    private var draftRevisionsByItemID: [String: UInt64] = [:]
    private var draftRevision: UInt64 = 0
    private var tagsByItemID: [String: (
        request: CourseSidebarTagRequest,
        tags: [String]
    )] = [:]
    private let parser = CourseSidebarTagParser()

    func request(
        for item: StudyItem,
        activeNoteItemID: String?,
        draftToken: UUID?
    ) -> CourseSidebarTagRequest {
        CourseSidebarTagRequest(
            item: item,
            memoryContentRevision: item.id == activeNoteItemID
                ? nil
                : draftRevisionsByItemID[item.id],
            draftToken: draftToken
        )
    }

    func noteDraftChanged(itemID: String, exists: Bool) {
        tagsByItemID.removeValue(forKey: itemID)
        draftRevision &+= 1
        if exists {
            draftRevisionsByItemID[itemID] = draftRevision
        } else {
            draftRevisionsByItemID.removeValue(forKey: itemID)
        }
    }

    func replacedNoteDrafts(keeping itemIDs: Set<String>) {
        tagsByItemID.removeAll()
        draftRevision &+= 1
        draftRevisionsByItemID = Dictionary(
            uniqueKeysWithValues: itemIDs.map { ($0, draftRevision) }
        )
    }

    func cachedTags(for request: CourseSidebarTagRequest) -> [String]? {
        guard request.draftToken == nil,
              let entry = tagsByItemID[request.itemID],
              entry.request == request else { return nil }
        return entry.tags
    }

    func cache(_ tags: [String], for request: CourseSidebarTagRequest) {
        guard request.draftToken == nil else { return }
        tagsByItemID[request.itemID] = (request, tags)
    }

    func pruneCache(keeping itemIDs: Set<String>) {
        tagsByItemID = tagsByItemID.filter { itemIDs.contains($0.key) }
    }

    func clearCache() {
        tagsByItemID.removeAll()
    }

    func tags(in markdown: String) async -> [String]? {
        await parser.tags(in: markdown)
    }
}

extension WorkspaceStore {
    func cachedSidebarTags(for request: CourseSidebarTagRequest) -> [String]? {
        courseSidebarTags.cachedTags(for: request)
    }

    func sidebarTagRequest(
        for item: StudyItem,
        draftToken: UUID?
    ) -> CourseSidebarTagRequest {
        courseSidebarTags.request(
            for: item,
            activeNoteItemID: activeNoteItemID,
            draftToken: draftToken
        )
    }

    func pruneSidebarTagCache(keeping itemIDs: Set<String>) {
        courseSidebarTags.pruneCache(keeping: itemIDs)
    }

    func clearSidebarTagCache() {
        courseSidebarTags.clearCache()
    }

    func loadSidebarTags(for request: CourseSidebarTagRequest) async -> [String]? {
        if let cached = cachedSidebarTags(for: request) { return cached }
        guard let item = importedItems.first(where: { $0.id == request.itemID }),
              sidebarTagRequest(for: item, draftToken: request.draftToken) == request,
              (request.draftToken != nil) == (request.itemID == activeNoteItemID),
              let markdown = await sidebarTagMarkdown(itemID: request.itemID),
              !Task.isCancelled,
              let tags = await courseSidebarTags.tags(in: markdown),
              !Task.isCancelled,
              let current = importedItems.first(where: { $0.id == request.itemID }),
              sidebarTagRequest(for: current, draftToken: request.draftToken) == request,
              (request.draftToken != nil) == (request.itemID == activeNoteItemID) else {
            return nil
        }
        courseSidebarTags.cache(tags, for: request)
        return tags
    }
}
