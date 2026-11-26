import SwiftUI
import WeiBeiCore

struct ContextualContentPicker: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    let kind: ContextualContentKind
    @State private var courseEntry: CourseProjectEntryPresentation?
    @State private var search: String
    @State private var searchFocused = false
    @State private var searchFocusRequest = 0

    init(kind: ContextualContentKind, initialSearch: String = "") {
        self.kind = kind
        _search = State(initialValue: initialSearch)
    }

    private struct Group: Identifiable {
        let course: Course?
        let items: [StudyItem]
        var id: String { course?.id.uuidString ?? "common" }
    }

    private var groups: [Group] {
        var byCourse: [UUID: [StudyItem]] = [:]
        var common: [StudyItem] = []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = store.allItems.filter {
            courseContextItemMatches($0, kind: kind)
                && (query.isEmpty || store.itemMatchesLibrarySearch($0, query: query))
        }.map { (item: $0, title: store.noteListDisplayTitle(for: $0)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(\.item)
        for item in items {
            for id in item.storage.ownerCourseID.map({ [$0] }) ?? store.courseMembershipIndex.courseIDs(for: item.id) {
                byCourse[id, default: []].append(item)
            }
            if case .common = item.storage { common.append(item) }
        }
        let grouped = store.courses.map { Group(course: $0, items: byCourse[$0.id] ?? []) }
            + [Group(course: nil, items: common)]
        return query.isEmpty ? grouped : grouped.filter { !$0.items.isEmpty }
    }

    var body: some View {
        GeometryReader { geometry in
            let groups = groups
            let trimmedQuery = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let filtering = !trimmedQuery.isEmpty
            let hasAnyItems = store.allItems.contains { courseContextItemMatches($0, kind: kind) }
            let isCompletelyEmpty = !filtering && !hasAnyItems && store.courses.isEmpty
            let isCoursesOnlyEmpty = !filtering && !hasAnyItems && !store.courses.isEmpty
            let available = max(1, geometry.size.width - 40)
            let columns = max(1, min(store.courses.count + 1, Int((min(available, 1140) + 16) / 200)))
            let width = min(available, CGFloat(columns) * 220 + CGFloat(columns - 1) * 16)

            ScrollView {
                if isCompletelyEmpty {
                    completelyEmptyState(availableWidth: available)
                        .frame(maxWidth: .infinity, minHeight: max(1, geometry.size.height))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        searchBar(width: width)
                        if filtering && groups.isEmpty {
                            emptySearchState(query: trimmedQuery)
                        } else {
                            globalActions
                            if isCoursesOnlyEmpty {
                                Text(kind == .note
                                     ? store.ui("还没有笔记", "No notes yet")
                                     : store.ui("还没有文稿", "No documents yet"))
                                    .weiBeiText(12)
                                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            CoursePickerColumns(columns: columns, spacing: 16) {
                                ForEach(groups) { group in
                                    courseBlock(group, showsEmptyMessage: !isCoursesOnlyEmpty)
                                }
                            }
                        }
                    }
                    .frame(width: width)
                    // Animate discrete reflow; ordinary live resizing must keep tracking the pointer.
                    .animation(reduceMotion ? nil : WeiBeiMotion.layout, value: columns)
                    // Both pickers start below the same return-control band, regardless of pane height.
                    .padding(.top, 48)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(WeiBeiTheme.paper)
        .onAppear { if kind == .note && store.notePickerPresented { searchFocused = true } }
        .sheet(item: $courseEntry) { presentation in
            CourseProjectEntrySheet(

                cancel: { courseEntry = nil },
                openCourse: { _ in courseEntry = nil }
            ).environmentObject(store)
        }
        .accessibilityIdentifier(kind == .note ? "contextual-note-picker" : "contextual-material-picker")
    }

    private func searchBar(width: CGFloat) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            WeiBeiSearchField(
                text: $search,
                prompt: store.ui("搜索名称、文件名或标签", "Search titles, filenames or tags"),
                isFocused: $searchFocused,
                fontSize: 12,
                focusRequest: searchFocusRequest,
                focusesOnAppear: kind == .note && store.notePickerPresented,
                drawsChrome: false,
                chromeHeight: 28,
                onEscape: {
                    guard !search.isEmpty else { return }
                    clearSearchAndRefocus()
                }
            )
            if !search.isEmpty {
                Button(action: clearSearchAndRefocus) {
                    Image(systemName: "xmark.circle.fill")
                        .weiBeiText(12)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.ui("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 9)
        .frame(width: min(width, 320), height: 30)
        .background(WeiBeiTheme.paperInset.opacity(0.22), in: RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius))
        .accessibilityIdentifier("contextual-content-filter")
    }

    private func completelyEmptyState(availableWidth: CGFloat) -> some View {
        let compact = availableWidth < 260
        return VStack(spacing: 0) {
            Spacer(minLength: 56)
            VStack(spacing: 12) {
                Image(systemName: kind == .note ? "note.text" : "doc.text")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .accessibilityHidden(true)
                Text(kind == .note
                     ? store.ui("还没有笔记", "No notes yet")
                     : store.ui("还没有文稿", "No documents yet"))
                    .weiBeiText(16, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                    .multilineTextAlignment(.center)
                Text(kind == .note
                     ? store.ui("拖入 Markdown，或直接新建。", "Create a note or drop Markdown files.")
                     : store.ui("支持 PDF、课件、HTML 与文本。", "PDF, slides, HTML, and text."))
                    .weiBeiText(12.5)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)

                SwiftUI.Group {
                    if compact {
                        VStack(spacing: 8) { emptyPrimaryButtons }
                    } else {
                        HStack(spacing: 10) { emptyPrimaryButtons }
                    }
                }
                .padding(.top, 6)

                if kind == .note {
                    Button(store.ui("新建课程", "New Course")) {
                        courseEntry = CourseProjectEntryPresentation()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 12, height: 26, neutralHoverWhenInactive: true, idleOpacity: 0))
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            .accessibilityIdentifier("contextual-picker-empty-library")
            Spacer(minLength: 56)
            Spacer(minLength: 56)
        }
    }

    @ViewBuilder
    private var emptyPrimaryButtons: some View {
        if kind == .note {
            Button(store.ui("新建笔记", "New Note")) {
                store.createBlankNotebookNote(in: nil)
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
            Button(store.ui("导入…", "Import…")) {
                importFiles(into: nil)
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
        } else {
            Button(store.ui("导入文稿…", "Import Documents…")) {
                importFiles(into: nil)
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
            Button(store.ui("新建课程", "New Course")) {
                courseEntry = CourseProjectEntryPresentation()
            }
            .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
        }
    }

    private func emptySearchState(query: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .accessibilityHidden(true)
            Text(store.ui("找不到「\(query)」", "No results for \"\(query)\""))
                .weiBeiText(14, weight: .medium)
                .foregroundStyle(WeiBeiTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(store.ui("清除搜索", "Clear Search"), action: clearSearchAndRefocus)
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
                .accessibilityIdentifier("contextual-picker-clear-search")
                .padding(.top, 4)
        }
        .frame(maxWidth: 300)
        .padding(.top, 56)
        .frame(maxWidth: .infinity)
    }

    private func clearSearchAndRefocus() {
        search = ""
        searchFocusRequest += 1
    }

    private var commonTitle: String {
        kind == .note ? store.ui("通用笔记", "Common Notes") : store.ui("通用资料", "Common Materials")
    }

    private func courseBlock(_ group: Group, showsEmptyMessage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    store.notePickerPresented = false
                    store.openExcerptBook(courseID: group.course?.id)
                } label: {
                    Label(store.ui("摘抄本", "Excerpts"), systemImage: "text.book.closed")
                        .weiBeiText(13).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WeiBeiTheme.accent)
            }
            if showsEmptyMessage && group.items.isEmpty {
                Text(kind == .note ? store.ui("还没有笔记", "No notes yet") : store.ui("还没有资料", "No materials yet"))
                    .weiBeiText(12).foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            ForEach(group.items) { item in
                Button { store.openContextualItem(item.id, kind: kind) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: kind == .note ? "note.text" : "doc.text").weiBeiText(12)
                        Text(kind == .note ? store.noteListDisplayTitle(for: item) : store.displayTitle(for: item))
                            .weiBeiText(13).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.noteListDisplayTitle(for: item) + "\n" + store.displaySubtitle(for: item))
                .contextMenu {
                    if kind == .note {
                        NotePDFExportMenuItem(itemID: item.id)
                    }
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
            Button(store.ui("新建课程", "New Course")) {
                courseEntry = CourseProjectEntryPresentation()
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 12, height: 28, neutralHoverWhenInactive: true, idleOpacity: 0))
            Button(kind == .note ? store.ui("导入笔记…", "Import Notes…") : store.ui("导入资料…", "Import Materials…")) {
                importFiles(into: nil)
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 12, height: 28, neutralHoverWhenInactive: true, idleOpacity: 0))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importFiles(into courseID: UUID?) {
        if kind == .note { store.importCourseNotesFromPanel(courseID: courseID) }
        else { store.importCourseMaterialsFromPanel(courseID: courseID) }
    }
}

/// Stable source order; each next course occupies the shortest column.
private struct CoursePickerColumns: Layout {
    let columns: Int
    let spacing: CGFloat

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columnWidth = max(1, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var heights = Array(repeating: CGFloat.zero, count: columns)
        return subviews.indices.map { index in
            let column = heights.indices.min(by: { heights[$0] < heights[$1] })!
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let rect = CGRect(x: CGFloat(column) * (columnWidth + spacing), y: heights[column], width: columnWidth, height: size.height)
            heights[column] += size.height + spacing
            return rect
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 220
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, rect) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading, proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
    }
}
