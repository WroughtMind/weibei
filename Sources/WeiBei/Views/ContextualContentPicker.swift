import Combine
import SwiftUI
import WeiBeiCore

struct ContextualContentPicker: View {
    @EnvironmentObject private var store: WorkspaceStore
    let kind: ContextualContentKind

    var body: some View {
        ContextualContentPickerContent(store: store, kind: kind)
    }
}

/// File metadata changes prepare the directory; geometry, hover, and chat updates
/// only read it. Kept per picker so READ and NOTE retain independent identities.
@MainActor
final class ContextualContentPickerModel: ObservableObject {
    struct Group: Identifiable {
        let course: Course?
        let items: [StudyItem]
        var id: String { course?.id.uuidString ?? "common" }
    }

    @Published private(set) var groups: [Group] = []
    private var subscription: AnyCancellable?
    private(set) var projectionBuildCountForTesting = 0

    init(store: WorkspaceStore, kind: ContextualContentKind) {
        subscription = Publishers.CombineLatest3(
            store.$importedItems.removeDuplicates(),
            store.$courses.removeDuplicates(),
            store.$courseItemMemberships.removeDuplicates()
        ).sink { [weak self, weak store] items, courses, memberships in
            guard let self else { return }
            store?.pruneSidebarTagCache(keeping: Set(items.map(\.id)))
            projectionBuildCountForTesting += 1
            let membershipIndex = Dictionary(grouping: memberships, by: \.itemID)
            var byCourse: [UUID: [StudyItem]] = [:]
            var common: [StudyItem] = []
            for item in items.filter({ courseContextItemMatches($0, kind: kind) }).sorted(by: {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }) {
                let owners = item.storage.ownerCourseID.map { [$0] }
                    ?? (membershipIndex[item.id] ?? []).map(\.courseID)
                for id in Set(owners) { byCourse[id, default: []].append(item) }
                if case .common = item.storage { common.append(item) }
            }
            groups = courses.map { Group(course: $0, items: byCourse[$0.id] ?? []) }
                + [Group(course: nil, items: common)]
        }
    }
}

private struct ContextualContentPickerContent: View {
    @ObservedObject var store: WorkspaceStore
    let kind: ContextualContentKind
    @StateObject private var model: ContextualContentPickerModel
    @State private var courseEntry: CourseProjectEntryPresentation?
    @State private var choosingImportTarget = false

    init(store: WorkspaceStore, kind: ContextualContentKind) {
        self.store = store
        self.kind = kind
        _model = StateObject(wrappedValue: ContextualContentPickerModel(store: store, kind: kind))
    }

    var body: some View {
        GeometryReader { geometry in
            let groups = model.groups
            let available = max(1, geometry.size.width - 40)
            let columns = min(groups.count, max(1, Int((min(available, 1140) + 16) / 200)))
            let width = min(available, CGFloat(columns) * 220 + CGFloat(columns - 1) * 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    globalActions
                    CoursePickerColumns(columns: columns, spacing: 16) {
                        ForEach(groups) { group in
                            courseBlock(group)
                        }
                    }
                }
                .frame(width: width)
                .padding(.top, min(100, max(28, geometry.size.height * 0.12)))
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background(WeiBeiTheme.paper)
        .sheet(item: $courseEntry) { presentation in
            CourseProjectEntrySheet(
                initialIntent: presentation.intent,
                cancel: { courseEntry = nil },
                openCourse: { _ in courseEntry = nil }
            ).environmentObject(store)
        }
        .sheet(isPresented: $choosingImportTarget) {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.ui("导入到哪里？", "Import into…")).weiBeiText(17, weight: .semibold)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(commonTitle) { importFiles(into: nil) }
                        ForEach(store.courses) { course in
                            Button(course.title) { importFiles(into: course.id) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 300)
                HStack { Spacer(); Button(store.ui("取消", "Cancel")) { choosingImportTarget = false }.keyboardShortcut(.cancelAction) }
            }
            .buttonStyle(.plain)
            .padding(24)
            .frame(width: 320)
            .background(WeiBeiTheme.paper)
        }
        .accessibilityIdentifier(kind == .note ? "contextual-note-picker" : "contextual-material-picker")
    }

    private var commonTitle: String {
        kind == .note ? store.ui("通用笔记", "Common Notes") : store.ui("通用资料", "Common Materials")
    }

    private func courseBlock(_ group: ContextualContentPickerModel.Group) -> some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.course?.title ?? commonTitle)
                    .weiBeiText(14, weight: .semibold)
                    .lineLimit(2)
                Button {
                    if kind == .note {
                        if let id = group.course?.id { store.createBlankNotebookNote(in: id) }
                        else { store.createBlankNotebookNote(in: nil) }
                    } else {
                        importFiles(into: group.course?.id)
                    }
                } label: {
                    Image(systemName: "plus").weiBeiText(12, weight: .medium).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .accessibilityLabel(kind == .note ? store.ui("新建笔记", "New Note") : store.ui("导入资料", "Import Materials"))
                Spacer(minLength: 0)
            }
            if kind == .note {
                Button {
                    store.openExcerptBook(courseID: group.course?.id)
                } label: {
                    Label(store.ui("摘抄本", "Excerpts"), systemImage: "text.book.closed")
                        .weiBeiText(13).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WeiBeiTheme.cinnabar)
            }
            if group.items.isEmpty {
                Text(kind == .note ? store.ui("还没有笔记", "No notes yet") : store.ui("还没有资料", "No materials yet"))
                    .weiBeiText(12).foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            ForEach(group.items) { item in
                Button { store.openContextualItem(item.id, kind: kind) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: kind == .note ? "note.text" : "doc.text").weiBeiText(12)
                        ContextualContentPickerTitle(store: store, item: item, kind: kind)
                            .weiBeiText(13).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.displayTitle(for: item))
                .contextMenu {
                    if let id = group.course?.id {
                        Button(store.ui("从本课程移除", "Remove from This Course")) { store.removeItem(item.id, fromCourseID: id) }
                    }
                    Button(store.ui("将原文件移到废纸篓…", "Move Source File to Trash…")) { store.confirmMoveItemSourceToTrash(item.id) }
                }
            }
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(courseWorkspaceAccent(colorIndex: group.course?.colorIndex ?? 3).opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
    }

    private var globalActions: some View {
        HStack(spacing: 12) {
            Button(store.ui("＋ 新建课程", "+ New Course")) { courseEntry = CourseProjectEntryPresentation(intent: .create) }
            Button(kind == .note ? store.ui("导入笔记…", "Import notes…") : store.ui("导入资料…", "Import materials…")) {
                choosingImportTarget = true
            }
        }
        .buttonStyle(.plain)
        .weiBeiText(11.5)
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importFiles(into courseID: UUID?) {
        choosingImportTarget = false
        // Let the target sheet dismiss before presenting the system file panel.
        DispatchQueue.main.async {
            if kind == .note { store.importCourseNotesFromPanel(courseID: courseID) }
            else { store.importCourseMaterialsFromPanel(courseID: courseID) }
        }
    }
}

/// A visible title uses the existing asynchronous sidebar metadata pipeline.
/// Recycled rows can immediately reuse the prepared title for the same revision.
struct ContextualContentPickerTitle: View {
    let store: WorkspaceStore
    let item: StudyItem
    let kind: ContextualContentKind
    @State private var loaded: (request: CourseSidebarTagRequest, meta: CourseSidebarNoteMeta)?

    var body: some View {
        let request = store.sidebarTagRequest(for: item, draftToken: nil)
        let customTitle = NoteTabDisplayTitle.normalizedCustomTitle(item.customDisplayTitle)
        let meta = store.cachedSidebarNoteMeta(for: request)
            ?? (loaded?.request == request ? loaded?.meta : nil)
        Text(kind == .note ? (customTitle ?? meta?.resolvedTitle ?? item.title) : item.title)
            .task(id: request) {
                guard kind == .note, customTitle == nil,
                      store.cachedSidebarNoteMeta(for: request) == nil,
                      let result = await store.loadSidebarNoteMeta(for: request),
                      !Task.isCancelled else { return }
                loaded = (request, result)
            }
    }
}

/// Stable source order; each next course occupies the shortest column.
private struct CoursePickerColumns: Layout {
    let columns: Int
    let spacing: CGFloat

    struct Cache {
        var width: CGFloat?
        var columns = 0
        var spacing: CGFloat = 0
        var frames: [CGRect] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    private func frames(width: CGFloat, subviews: Subviews, cache: inout Cache) -> [CGRect] {
        if cache.width == width, cache.columns == columns, cache.spacing == spacing,
           cache.frames.count == subviews.count { return cache.frames }
        let columnWidth = max(1, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var heights = Array(repeating: CGFloat.zero, count: columns)
        let frames = subviews.indices.map { index in
            let column = heights.indices.min(by: { heights[$0] < heights[$1] })!
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let rect = CGRect(x: CGFloat(column) * (columnWidth + spacing), y: heights[column], width: columnWidth, height: size.height)
            heights[column] += size.height + spacing
            return rect
        }
        cache = Cache(width: width, columns: columns, spacing: spacing, frames: frames)
        return frames
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 220
        return CGSize(width: width, height: frames(width: width, subviews: subviews, cache: &cache).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for (view, rect) in zip(subviews, frames(width: bounds.width, subviews: subviews, cache: &cache)) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading, proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
    }
}
