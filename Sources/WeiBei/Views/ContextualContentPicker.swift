import SwiftUI
import WeiBeiCore

struct ContextualContentPicker: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    let kind: ContextualContentKind
    @State private var courseEntry: CourseProjectEntryPresentation?
    @State private var choosingImportTarget = false
    @State private var pendingImport: (() -> Void)?
    @State private var search = ""
    @FocusState private var searchFocused: Bool

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
            let width = max(1, min(geometry.size.width - 48, 760))
            let columns = max(1, min(groups.count, Int((width + 20) / 300)))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pickerHeader
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                        TextField("", text: $search, prompt: Text(store.ui("搜索名称、文件名或标签", "Search title, filename or tag"))
                            .foregroundStyle(WeiBeiTheme.placeholderInk))
                            .textFieldStyle(.plain)
                            .foregroundStyle(WeiBeiTheme.ink)
                            .focused($searchFocused)
                            .accessibilityLabel(store.ui("搜索内容", "Search content"))
                            .accessibilityIdentifier("contextual-content-filter")
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .accessibilityLabel(store.ui("清除搜索", "Clear search"))
                        }
                    }
                    .weiBeiText(13)
                    .weibeiInputSurface(active: searchFocused, height: 36)
                    globalActions
                    if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && groups.allSatisfy({ $0.items.isEmpty }) {
                        Text(store.ui("没有匹配的内容", "No matching content"))
                            .weiBeiText(13).foregroundStyle(WeiBeiTheme.secondaryInk)
                    }
                    CoursePickerColumns(columns: columns, spacing: 20) {
                        ForEach(groups) { group in
                            courseBlock(group)
                        }
                    }
                }
                .frame(width: width)
                // Animate discrete reflow; ordinary live resizing must keep tracking the pointer.
                .animation(reduceMotion ? nil : WeiBeiMotion.panel, value: columns)
                .padding(.top, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background(WeiBeiTheme.paper)
        .onAppear { if kind == .note && store.notePickerPresented { searchFocused = true } }
        .sheet(item: $courseEntry) { presentation in
            CourseProjectEntrySheet(
                initialIntent: presentation.intent,
                cancel: { courseEntry = nil },
                openCourse: { _ in courseEntry = nil }
            ).environmentObject(store)
        }
        .sheet(isPresented: $choosingImportTarget, onDismiss: {
            let action = pendingImport
            pendingImport = nil
            action?()
        }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.ui("导入到哪里？", "Import into…")).weiBeiText(17, weight: .semibold)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        importTargetButton(commonTitle, symbol: "tray", courseID: nil)
                        ForEach(store.courses) { course in
                            importTargetButton(course.title, symbol: "folder", courseID: course.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 300)
                HStack {
                    Spacer()
                    Button(store.ui("取消", "Cancel")) { choosingImportTarget = false }
                        .buttonStyle(WeiBeiDialogButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
            .frame(minWidth: 320, idealWidth: 400, maxWidth: .infinity)
#if targetEnvironment(macCatalyst)
            .background(CatalystSheetBackground(color: WeiBeiNativePalette.paper()))
#endif
            .background(WeiBeiGlassForegroundSheet(mode: store.appearanceMode))
            .background(WeiBeiThemeBackdrop(mode: store.appearanceMode))
            .foregroundStyle(WeiBeiTheme.ink)
            .preferredColorScheme(store.appearanceMode.colorScheme)
        }
        .accessibilityIdentifier(kind == .note ? "contextual-note-picker" : "contextual-material-picker")
    }

    private var pickerHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind == .note ? store.ui("笔记", "Notes") : store.ui("资料", "Materials"))
                    .weiBeiText(24, weight: .semibold, design: .serif)
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer(minLength: 8)
                if kind == .note && store.notePickerPresented {
                    Button(store.ui("返回当前笔记", "Back to current note")) {
                        store.notePickerPresented = false
                        store.focus(.notes)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 12, height: 28))
                    .keyboardShortcut(.cancelAction)
                }
            }
            .frame(minHeight: 36)
            Text(kind == .note
                 ? store.ui("选择笔记，继续写作。", "Choose a note and keep writing.")
                 : store.ui("选择资料，开始阅读。", "Choose material and start reading."))
                .weiBeiText(13)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }

    private var commonTitle: String {
        kind == .note ? store.ui("通用笔记", "Common Notes") : store.ui("通用资料", "Common Materials")
    }

    private func importTargetButton(_ title: String, symbol: String, courseID: UUID?) -> some View {
        Button { importFiles(into: courseID) } label: {
            HStack(spacing: 10) {
                Label(title, systemImage: symbol)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").weiBeiText(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 13, height: 36))
        .help(title)
    }

    private func courseBlock(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.course?.title ?? commonTitle)
                    .weiBeiText(14, weight: .semibold)
                    .lineLimit(2)
                Spacer(minLength: 0)
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
                .buttonStyle(WeiBeiIconButtonStyle(size: 28))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .accessibilityLabel(kind == .note ? store.ui("新建笔记", "New Note") : store.ui("导入资料", "Import Materials"))
            }
            Divider().overlay(WeiBeiTheme.ink.opacity(0.08))
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
                        Text(kind == .note ? store.noteListDisplayTitle(for: item) : store.displayTitle(for: item))
                            .weiBeiText(13).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.noteListDisplayTitle(for: item) + "\n" + store.displaySubtitle(for: item))
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
        .background(WeiBeiTheme.paperInset.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var globalActions: some View {
        HStack(spacing: 12) {
            Button { courseEntry = CourseProjectEntryPresentation(intent: .create) } label: {
                Label(store.ui("新建课程", "New Course"), systemImage: "plus")
            }
            Button(kind == .note ? store.ui("导入笔记…", "Import notes…") : store.ui("导入资料…", "Import materials…")) {
                choosingImportTarget = true
            }
        }
        .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 12, height: 30))
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importFiles(into courseID: UUID?) {
        let action = { [store, kind] in
            if kind == .note { store.importCourseNotesFromPanel(courseID: courseID) }
            else { store.importCourseMaterialsFromPanel(courseID: courseID) }
        }
        if choosingImportTarget {
            pendingImport = action
            choosingImportTarget = false
        } else {
            action()
        }
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
