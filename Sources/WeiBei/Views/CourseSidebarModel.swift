import Combine
import Foundation
import WeiBeiCore

struct CourseSidebarItemRow: Identifiable, Equatable {
    let item: StudyItem
    let tags: [String]
    /// 解析后的显示名（自定义名 / 正文抬头），nil 表示直接显示 `item.title`。
    let resolvedTitle: String?
    let tagRequest: CourseSidebarTagRequest?
    let courseIDs: Set<UUID>

    var id: String { item.id }
}

/// 一条笔记正文加载管线的产出：标签 + 与浮动 tab 同口径的显示名。
struct CourseSidebarNoteMeta: Equatable, Sendable {
    let tags: [String]
    /// 相对 `item.title` 的显示名覆盖；nil 表示没有更好的名字。
    let resolvedTitle: String?
}

struct CourseSidebarTagRequest: Hashable, Sendable {
    let itemID: String
    let storage: StudyItemStorage
    let title: String
    let customDisplayTitle: String?
    let urlPath: String?
    let importedFileIdentity: ImportedFileIdentity?
    let contentRevision: UInt64
    let contentDigest: String?
    let fileByteCount: UInt64?
    let fileModificationTimeNanoseconds: Int64?
    let memoryContentRevision: UInt64?
    let draftToken: UUID?

    init(
        item: StudyItem,
        memoryContentRevision: UInt64?,
        draftToken: UUID?
    ) {
        itemID = item.id
        storage = item.storage
        title = item.title
        customDisplayTitle = item.customDisplayTitle
        urlPath = item.urlPath
        importedFileIdentity = item.importedFileIdentity
        contentRevision = item.contentRevision
        contentDigest = item.contentDigest
        fileByteCount = item.fileByteCount
        fileModificationTimeNanoseconds = item.fileModificationTimeNanoseconds
        self.memoryContentRevision = memoryContentRevision
        self.draftToken = draftToken
    }

}

struct CourseSidebarCourseRow: Identifiable, Equatable {
    let course: Course
    let materialCount: Int
    let noteCount: Int
    let materials: [CourseSidebarItemRow]
    let notes: [CourseSidebarItemRow]

    var id: UUID { course.id }
}

private struct CourseSidebarProjection: Equatable {
    var courses: [CourseSidebarCourseRow] = []
    var unassignedMaterials: [CourseSidebarItemRow] = []
    var unassignedNotes: [CourseSidebarItemRow] = []
}

@MainActor
final class CourseSidebarModel: ObservableObject {
    @Published private var projection = CourseSidebarProjection()
    @Published private(set) var selectedItemID: String?
    @Published private(set) var activeNotebookItemID: String?
    @Published private(set) var activeCourseID: UUID?
    @Published private(set) var notebookRenameDraft: NotebookRenameDraft?
    @Published private(set) var interfaceLanguage: WeiBeiInterfaceLanguage
    @Published private(set) var appearanceMode: WeiBeiAppearanceMode
    @Published private(set) var query: String
    private var tagInputGeneration = 0

    private weak var store: WorkspaceStore?
    private var subscriptions: Set<AnyCancellable> = []
    private var rebuildTask: Task<Void, Never>?
    private var activeDraftToken = UUID()
    private var transientNoteMeta: [CourseSidebarTagRequest: CourseSidebarNoteMeta] = [:]

    private(set) var projectionBuildCountForTesting = 0

    var courses: [CourseSidebarCourseRow] { projection.courses }
    var unassignedMaterials: [CourseSidebarItemRow] { projection.unassignedMaterials }
    var unassignedNotes: [CourseSidebarItemRow] { projection.unassignedNotes }
    var searchTagTaskID: String { "\(tagInputGeneration):\(query)" }

    init(store: WorkspaceStore) {
        interfaceLanguage = store.interfaceLanguage
        appearanceMode = store.appearanceMode
        query = store.librarySearch
        start(store: store)
    }

    deinit {
        rebuildTask?.cancel()
    }

    func stop() {
        subscriptions.removeAll()
        rebuildTask?.cancel()
        rebuildTask = nil
        transientNoteMeta.removeAll()
        store?.clearSidebarTagCache()
        store = nil
    }

    private func start(store: WorkspaceStore) {
        self.store = store
        selectedItemID = store.selectedItemID
        activeNotebookItemID = store.activeNotebookItemID
        activeCourseID = store.activeCourseID
        notebookRenameDraft = store.notebookRenameDraft
        rebuild()

        store.$importedItems.dropFirst().sink { [weak self] items in
            self?.store?.pruneSidebarTagCache(
                keeping: Set(items.map(\.id))
            )
            self?.tagInputGeneration &+= 1
            self?.scheduleRebuild()
        }.store(in: &subscriptions)
        store.$courses.dropFirst().sink { [weak self] _ in
            self?.scheduleRebuild()
        }.store(in: &subscriptions)
        store.$courseItemMemberships.dropFirst().sink { [weak self] _ in
            self?.scheduleRebuild()
        }.store(in: &subscriptions)
        store.$selectedItemID.dropFirst().sink { [weak self] itemID in
            self?.selectedItemID = itemID
        }.store(in: &subscriptions)
        store.$activeNotebookItemID.dropFirst().sink { [weak self] itemID in
            guard let self else { return }
            self.activeNotebookItemID = itemID
            self.activeDraftToken = UUID()
            self.transientNoteMeta.removeAll()
            self.tagInputGeneration &+= 1
            self.scheduleRebuild()
        }.store(in: &subscriptions)
        store.$activeCourseID.dropFirst().sink { [weak self] courseID in
            self?.activeCourseID = courseID
            self?.scheduleRebuild()
        }.store(in: &subscriptions)
        store.$notebookRenameDraft.dropFirst().sink { [weak self] draft in
            self?.notebookRenameDraft = draft
        }.store(in: &subscriptions)
        store.$interfaceLanguage.dropFirst().sink { [weak self] language in
            self?.interfaceLanguage = language
            self?.scheduleRebuild()
        }.store(in: &subscriptions)
        store.$appearanceMode.dropFirst().sink { [weak self] mode in
            self?.appearanceMode = mode
        }.store(in: &subscriptions)
        store.$noteText
            .dropFirst()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.activeDraftToken = UUID()
                self.transientNoteMeta.removeAll()
                self.tagInputGeneration &+= 1
                self.scheduleRebuild()
            }
            .store(in: &subscriptions)
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.rebuild()
        }
    }

    private func rebuild() {
        guard let store else { return }
        projectionBuildCountForTesting &+= 1
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let memberships = store.courseItemMemberships
        var courseIDsByItemID: [String: Set<UUID>] = [:]
        for membership in memberships {
            courseIDsByItemID[membership.itemID, default: []].insert(membership.courseID)
        }

        let rows = store.importedItems.map { item in
            let request = tagRequest(for: item, store: store)
            let meta = request.flatMap {
                transientNoteMeta[$0] ?? store.cachedSidebarNoteMeta(for: $0)
            }
            return CourseSidebarItemRow(
                item: item,
                tags: meta?.tags ?? [],
                resolvedTitle: resolvedSidebarTitle(for: item, meta: meta),
                tagRequest: request,
                courseIDs: courseIDsByItemID[item.id] ?? []
            )
        }
        var rowsByCourseID: [UUID: [CourseSidebarItemRow]] = [:]
        for row in rows {
            for courseID in row.courseIDs {
                rowsByCourseID[courseID, default: []].append(row)
            }
        }
        let filteredRows = normalizedQuery.isEmpty
            ? rows
            : rows.filter { row in
                itemMatches(row, query: normalizedQuery, language: interfaceLanguage)
            }
        let filteredIDs = Set(filteredRows.map(\.id))

        let nextCourses: [CourseSidebarCourseRow] = store.courses.compactMap { course -> CourseSidebarCourseRow? in
            let allCourseRows = rowsByCourseID[course.id] ?? []
            let visibleRows = normalizedQuery.isEmpty
                ? allCourseRows
                : allCourseRows.filter { filteredIDs.contains($0.id) }
            guard normalizedQuery.isEmpty
                    || course.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || !visibleRows.isEmpty else {
                return nil
            }
            let displayedRows = normalizedQuery.isEmpty ? allCourseRows : visibleRows
            let noteCount = allCourseRows.lazy.filter(\.item.isNotebookNote).count
            let materialCount = allCourseRows.lazy.filter(\.item.isCourseMaterial).count
            return CourseSidebarCourseRow(
                course: course,
                materialCount: materialCount,
                noteCount: noteCount,
                materials: displayedRows.filter(\.item.isCourseMaterial),
                notes: displayedRows.filter(\.item.isNotebookNote)
            )
        }
        let nextUnassignedMaterials = filteredRows.filter {
            $0.item.isCourseMaterial && $0.courseIDs.isEmpty
        }
        let nextUnassignedNotes = filteredRows.filter {
            $0.item.isNotebookNote && $0.courseIDs.isEmpty
        }
        let nextProjection = CourseSidebarProjection(
            courses: nextCourses,
            unassignedMaterials: nextUnassignedMaterials,
            unassignedNotes: nextUnassignedNotes
        )
        if projection != nextProjection { projection = nextProjection }
    }

    func updateQuery(_ value: String) {
        guard let store, query != value else { return }
        query = value
        store.librarySearch = value
        scheduleRebuild()
    }

    private func itemMatches(
        _ row: CourseSidebarItemRow,
        query: String,
        language: WeiBeiInterfaceLanguage
    ) -> Bool {
        let tagQuery = query.trimmingCharacters(
            in: CharacterSet(charactersIn: "#")
        )
        return row.item.title.localizedCaseInsensitiveContains(query)
            || (row.resolvedTitle?.localizedCaseInsensitiveContains(query) ?? false)
            || row.item.subtitle.localizedCaseInsensitiveContains(query)
            || row.item.kind.label(language: language)
                .localizedCaseInsensitiveContains(query)
            || (!tagQuery.isEmpty && row.tags.contains {
                $0.localizedCaseInsensitiveContains(tagQuery)
            })
    }

    func missingTagRequestsForSearch() -> [CourseSidebarTagRequest] {
        guard let store,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return store.importedItems.compactMap { item in
            guard let request = tagRequest(for: item, store: store),
                  transientNoteMeta[request] == nil,
                  store.cachedSidebarNoteMeta(for: request) == nil else {
                return nil
            }
            return request
        }
    }

    /// 笔记行的显示名与浮动 tab 同口径：自定义名立即可见（不读正文），
    /// 否则用正文管线解析出的名字，都没有就回退 `item.title`（在行视图兜底）。
    private func resolvedSidebarTitle(
        for item: StudyItem,
        meta: CourseSidebarNoteMeta?
    ) -> String? {
        guard item.isNotebookNote else { return nil }
        if let custom = NoteTabDisplayTitle.normalizedCustomTitle(item.customDisplayTitle) {
            return custom
        }
        return meta?.resolvedTitle
    }

    func acceptLoadedNoteMeta(
        _ results: [(request: CourseSidebarTagRequest, meta: CourseSidebarNoteMeta)]
    ) {
        guard let store else { return }
        var changed = false
        for (request, meta) in results {
            guard let item = store.importedItems.first(where: { $0.id == request.itemID }),
                  tagRequest(for: item, store: store) == request else {
                continue
            }
            if request.draftToken != nil, transientNoteMeta[request] != meta {
                transientNoteMeta[request] = meta
                changed = true
            } else if request.draftToken == nil,
                      store.cachedSidebarNoteMeta(for: request) != nil {
                changed = true
            }
        }
        if changed { scheduleRebuild() }
    }

    private func tagRequest(
        for item: StudyItem,
        store: WorkspaceStore
    ) -> CourseSidebarTagRequest? {
        guard item.isNotebookNote else { return nil }
        return store.sidebarTagRequest(
            for: item,
            draftToken: item.id == store.activeNoteItemID
                ? activeDraftToken
                : nil
        )
    }
}
