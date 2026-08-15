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
    private var metaByItemID: [String: (
        request: CourseSidebarTagRequest,
        meta: CourseSidebarNoteMeta
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
        metaByItemID.removeValue(forKey: itemID)
        draftRevision &+= 1
        if exists {
            draftRevisionsByItemID[itemID] = draftRevision
        } else {
            draftRevisionsByItemID.removeValue(forKey: itemID)
        }
    }

    func replacedNoteDrafts(keeping itemIDs: Set<String>) {
        metaByItemID.removeAll()
        draftRevision &+= 1
        draftRevisionsByItemID = Dictionary(
            uniqueKeysWithValues: itemIDs.map { ($0, draftRevision) }
        )
    }

    func cachedMeta(for request: CourseSidebarTagRequest) -> CourseSidebarNoteMeta? {
        guard request.draftToken == nil,
              let entry = metaByItemID[request.itemID],
              entry.request == request else { return nil }
        return entry.meta
    }

    func cache(_ meta: CourseSidebarNoteMeta, for request: CourseSidebarTagRequest) {
        guard request.draftToken == nil else { return }
        metaByItemID[request.itemID] = (request, meta)
    }

    func pruneCache(keeping itemIDs: Set<String>) {
        metaByItemID = metaByItemID.filter { itemIDs.contains($0.key) }
    }

    func clearCache() {
        metaByItemID.removeAll()
    }

    func tags(in markdown: String) async -> [String]? {
        await parser.tags(in: markdown)
    }
}

extension WorkspaceStore {
    func cachedSidebarNoteMeta(for request: CourseSidebarTagRequest) -> CourseSidebarNoteMeta? {
        courseSidebarTags.cachedMeta(for: request)
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

    /// 加载一条笔记的侧边栏元信息：标签 + 与浮动 tab 同口径的显示名。
    /// 正文经 `sidebarTagMarkdown` 异步获取（内存草稿 / 活动笔记 / 读盘），
    /// 显示名用 `NoteTabDisplayTitle.resolve` 解析，绝不回退同步读盘。
    func loadSidebarNoteMeta(for request: CourseSidebarTagRequest) async -> CourseSidebarNoteMeta? {
        if let cached = cachedSidebarNoteMeta(for: request) { return cached }
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
        let resolved = NoteTabDisplayTitle.resolve(
            customTitle: current.customDisplayTitle,
            noteTitle: current.title,
            body: markdown
        )
        // 解析结果为空或等于文件名时不存覆盖，行视图直接显示 item.title，
        // 也避免投影因 nil/等值字符串的差别反复抖动。
        let resolvedTitle = (resolved.isEmpty || resolved == current.title) ? nil : resolved
        let meta = CourseSidebarNoteMeta(tags: tags, resolvedTitle: resolvedTitle)
        courseSidebarTags.cache(meta, for: request)
        return meta
    }
}
