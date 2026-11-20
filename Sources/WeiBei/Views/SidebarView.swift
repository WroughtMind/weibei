import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    @State private var librarySearchFocused = false
    @State private var showsImport = false
    @State private var importCourseID: UUID?
    @State private var importsNotes = false
    @State private var lastBrowsedCourseID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsImport { importControls }
            CourseSidebarList(store: store, model: model, panes: store.paneState,
                              lastBrowsedCourseID: $lastBrowsedCourseID)
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .tint(WeiBeiTheme.cinnabar)
        .onReceive(store.paneState.$focusRequest) { _ in
            librarySearchFocused = store.paneState.focusedPane == .library
        }
        .onAppear {
            librarySearchFocused = store.paneState.focusedPane == .library
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            librarySearchField
            Button {
                if !showsImport {
                    let candidate = lastBrowsedCourseID ?? model.activeCourseID
                    importCourseID = model.browsing.courses.first { $0.id == candidate }?.id
                    importsNotes = false
                }
                showsImport.toggle()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ui("导入资料", "Import files"))
            .help(ui("导入文稿或笔记", "Import documents or notes"))
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        Divider()
    }

    @ViewBuilder
    private var importControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(ui("课程", "Course"), selection: $importCourseID) {
                Text(ui("不指定课程", "Unassigned")).tag(UUID?.none)
                ForEach(model.browsing.courses) { row in
                    Text(row.course.title).tag(Optional(row.id))
                }
            }
            .pickerStyle(.menu)
            Picker(ui("归入", "Import as"), selection: $importsNotes) {
                Text(ui("文稿", "Documents")).tag(false)
                Text(ui("笔记", "Notes")).tag(true)
            }
            .pickerStyle(.segmented)
            Button(ui("选择文件…", "Choose Files…")) {
                showsImport = false
                if importsNotes {
                    store.importCourseNotesFromPanel(courseID: importCourseID)
                } else {
                    store.importCourseMaterialsFromPanel(courseID: importCourseID)
                }
            }
            .buttonStyle(.bordered)
        }
        .font(.system(size: 12))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        Divider()
    }

    private var librarySearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            WeiBeiSearchField(
                text: Binding(get: { model.query }, set: model.updateQuery),
                prompt: ui("搜索课程与文件", "Search courses and files"),
                isFocused: $librarySearchFocused,
                drawsChrome: false,
                chromeHeight: 28
            )
            .accessibilityLabel(ui("搜索课程、文稿与笔记", "Search courses, documents and notes"))
            .frame(maxWidth: .infinity, alignment: .leading)
            if !model.query.isEmpty {
                Button {
                    model.updateQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ui("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 7)
        .background(WeiBeiTheme.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        model.interfaceLanguage.text(chinese, english)
    }
}

private struct SidebarFileLocation: Hashable {
    let courseID: UUID?
    let itemID: String
    let isNote: Bool
}

struct CourseSidebarList: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    @ObservedObject var panes: WorkspacePaneState
    @Binding var lastBrowsedCourseID: UUID?
    @State private var expandedCourses: Set<UUID> = []
    @State private var collapsedResults: Set<UUID> = []
    @FocusState private var focusedCourse: UUID?

    private var searching: Bool {
        !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            // Keep the actual browsing list mounted so its scroll offset survives filtering.
            outline(model.browsing, results: false)
                .opacity(searching ? 0 : 1)
                .allowsHitTesting(!searching)
                .accessibilityHidden(searching)
                .disabled(searching)
            if searching { outline(model.projection, results: true) }
        }
        .onAppear {
            expandedCourses = store.libraryDrawer.expandedCourseIDs ?? Set([model.activeCourseID].compactMap { $0 })
            revealImport()
        }
        .onChange(of: model.query) { _, _ in collapsedResults.removeAll() }
        .onChange(of: model.recentlyImportedItemIDs) { _, _ in revealImport() }
        .task(id: model.searchTagTaskID) { [weak store = store, weak model = model] in
            guard let requests = model?.missingTagRequestsForSearch(),
                  !requests.isEmpty else { return }
            var results: [(request: CourseSidebarTagRequest, meta: CourseSidebarNoteMeta)] = []
            for request in requests {
                guard !Task.isCancelled else { return }
                if let meta = await store?.loadSidebarNoteMeta(for: request) {
                    results.append((request, meta))
                    if results.count == 32 {
                        model?.acceptLoadedNoteMeta(results)
                        results.removeAll(keepingCapacity: true)
                        await Task.yield()
                    }
                }
            }
            guard !Task.isCancelled else { return }
            if !results.isEmpty { model?.acceptLoadedNoteMeta(results) }
        }
    }

    private func revealImport() {
        if !model.recentlyImportedItemIDs.isEmpty, let id = model.activeCourseID {
            expandedCourses.insert(id)
            store.libraryDrawer.expandedCourseIDs = expandedCourses
        }
    }

    private func outline(_ projection: CourseSidebarProjection, results: Bool) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(projection.courses) { row in
                    courseRow(row, results: results)
                }
                if !projection.unassignedMaterials.isEmpty {
                    SidebarSectionHeader(title: ui("通用资料", "General materials"), topSpacing: 10)
                    ForEach(projection.unassignedMaterials) { row in itemRow(row, opensNotebook: false, result: results) }
                }
                if !projection.unassignedNotes.isEmpty {
                    SidebarSectionHeader(title: ui("独立笔记", "Unassigned notes"), topSpacing: 10)
                    ForEach(projection.unassignedNotes) { row in itemRow(row, opensNotebook: true, result: results) }
                }
                if projection.courses.isEmpty && projection.unassignedMaterials.isEmpty && projection.unassignedNotes.isEmpty {
                    SidebarEmptyRow(title: results ? ui("没有匹配结果", "No results") : ui("还没有课程", "No courses yet"))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 18)
            .scrollContentBackground(.hidden)
            .contentMargins(.all, 0, for: .scrollContent)
            .task(id: model.firstVisibleItemID(in: model.recentlyImportedItemIDs)) {
                guard !results, let target = model.firstVisibleItemID(in: model.recentlyImportedItemIDs) else { return }
                await Task.yield()
                if let course = model.browsing.courses.first(where: { $0.id == model.activeCourseID }),
                   course.materials.contains(where: { $0.id == target }) || course.notes.contains(where: { $0.id == target }) {
                    proxy.scrollTo(SidebarFileLocation(courseID: course.id, itemID: target, isNote: !course.materials.contains(where: { $0.id == target })), anchor: .center)
                } else {
                    proxy.scrollTo(SidebarFileLocation(courseID: nil, itemID: target, isNote: !model.browsing.unassignedMaterials.contains(where: { $0.id == target })), anchor: .center)
                }
            }
        }
    }

    private func toggleCourse(_ id: UUID, results: Bool) {
        lastBrowsedCourseID = id
        if results {
            if !collapsedResults.insert(id).inserted { collapsedResults.remove(id) }
        } else {
            if !expandedCourses.insert(id).inserted { expandedCourses.remove(id) }
            store.libraryDrawer.expandedCourseIDs = expandedCourses
        }
    }

    @ViewBuilder
    private func courseRow(_ row: CourseSidebarCourseRow, results: Bool) -> some View {
        let course = row.course
        let expanded = results ? !collapsedResults.contains(row.id) : expandedCourses.contains(row.id)
        Button { toggleCourse(row.id, results: results) } label: {
            HStack(spacing: 7) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 11)
                Image(systemName: "book.closed")
                    .font(.system(size: 13))
                    .foregroundStyle([WeiBeiTheme.cinnabar, WeiBeiTheme.moss, WeiBeiTheme.link, WeiBeiTheme.secondaryInk][((course.colorIndex % 4) + 4) % 4])
                    .frame(width: 15)
                Text(course.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarRowStyle(selected: false))
        .focused($focusedCourse, equals: row.id)
        .accessibilityLabel(course.title)
        .accessibilityValue(expanded ? ui("已展开", "Expanded") : ui("已收起", "Collapsed"))
        .onKeyPress(.rightArrow) {
            if !expanded { toggleCourse(row.id, results: results) }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if expanded { toggleCourse(row.id, results: results) }
            return .handled
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(row.id)
        if expanded {
            if results {
                ForEach(row.materials) { item in itemRow(item, opensNotebook: false, courseID: row.id, result: true) }
                ForEach(row.notes) { item in itemRow(item, opensNotebook: true, courseID: row.id, result: true) }
                if row.materials.isEmpty && row.notes.isEmpty {
                    SidebarEmptyRow(title: ui("暂无资料", "No files"), leadingInset: 36)
                }
            } else {
                courseContents(row)
            }
        }
    }

    @ViewBuilder
    private func courseContents(_ row: CourseSidebarCourseRow) -> some View {
        SidebarCourseGroupHeader(title: ui("文稿", "Documents"), count: row.materialCount)
        .id("\(row.id.uuidString)-materials-header")
        if row.materials.isEmpty {
            SidebarEmptyRow(
                title: row.materialCount == 0
                    ? ui("暂无文稿", "No documents")
                    : ui("没有匹配的文稿", "No matching documents"),
                leadingInset: 50,
                actionTitle: row.materialCount == 0 ? ui("导入…", "Import…") : nil,
                action: { store.importCourseMaterialsFromPanel(courseID: row.id) }
            )
            .id("\(row.id.uuidString)-materials-empty")
        } else {
            ForEach(row.materials) { item in
                itemRow(item, opensNotebook: false, courseID: row.id)
            }
        }
        SidebarCourseGroupHeader(title: ui("笔记", "Notes"), count: row.noteCount)
        .id("\(row.id.uuidString)-notes-header")
        if row.notes.isEmpty {
            SidebarEmptyRow(
                title: row.noteCount == 0
                    ? ui("暂无笔记", "No notes")
                    : ui("没有匹配的笔记", "No matching notes"),
                leadingInset: 50,
                actionTitle: row.noteCount == 0 ? ui("导入…", "Import…") : nil,
                action: { store.importCourseNotesFromPanel(courseID: row.id) }
            )
            .id("\(row.id.uuidString)-notes-empty")
        } else {
            ForEach(row.notes) { item in
                itemRow(item, opensNotebook: true, courseID: row.id)
            }
        }
    }

    private func itemRow(_ row: CourseSidebarItemRow, opensNotebook: Bool, courseID: UUID? = nil, result: Bool = false) -> some View {
        let item = row.item
        let nested = courseID != nil
        let opened = opensNotebook ? panes.showNotes && model.activeNotebookItemID == item.id
            : panes.showReader && model.selectedItemID == item.id
        let selected = opened && panes.lastContentPane == (opensNotebook ? .notes : .reader)
        return Button { open(item, opensNotebook: opensNotebook, courseID: courseID) } label: {
            LibraryRow(
                item: item,
                subtitle: store.displaySubtitle(for: item),
                resolvedTitle: row.resolvedTitle,
                selected: selected,
                opened: opened,
                isNote: opensNotebook,
                language: model.interfaceLanguage,
                match: result ? model.query : ""
            )
            .padding(.leading, nested ? 18 : 6)
            .padding(.trailing, 6)
        }
        .buttonStyle(SidebarRowStyle(selected: selected))
        .contextMenu {
            if opensNotebook {
                NotePDFExportMenuItem(itemID: item.id)
            }
        }
        .accessibilityValue(opened ? (selected ? ui("当前内容", "Current") : ui("已打开", "Open")) : "")
        .help(([row.resolvedTitle ?? item.title, store.displaySubtitle(for: item)] + row.tags)
            .joined(separator: "\n"))
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(SidebarFileLocation(courseID: courseID, itemID: item.id, isNote: opensNotebook))
        // Search still indexes tags and resolved note titles without displaying
        // another metadata line in every row.
        .task(id: row.tagRequest) { [weak store = store, weak model = model] in
            guard let request = row.tagRequest else { return }
            if request.draftToken == nil, store?.cachedSidebarNoteMeta(for: request) != nil { return }
            guard let meta = await store?.loadSidebarNoteMeta(for: request),
                  !Task.isCancelled else { return }
            model?.acceptLoadedNoteMeta([(request, meta)])
        }
    }

    private func open(_ item: StudyItem, opensNotebook: Bool, courseID: UUID?) {
        if item.isSample {
            store.select(itemID: item.id)
            store.showLibrary = false
            return
        }
        let opened = opensNotebook
            ? store.openCourseNote(item.id, in: courseID, keepLibraryOpen: store.libraryDrawer.displaysAlongsideWorkspace)
            : store.openCourseMaterial(item.id, in: courseID, keepLibraryOpen: store.libraryDrawer.displaysAlongsideWorkspace)
        if !opened {
            store.revealCourseFolder(containing: item.id, in: courseID)
        }
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        model.interfaceLanguage.text(chinese, english)
    }
}

private struct SidebarSectionHeader: View {
    let title: String
    var topSpacing: CGFloat = 0

    var body: some View {
        Text(title)
            .weiBeiText(11, weight: .semibold)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topSpacing)
            .padding(.bottom, 5)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .selectionDisabled()
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SidebarEmptyRow: View {
    let title: String
    var leadingInset: CGFloat = 16
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer(minLength: 4)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
            }
        }
        .weiBeiText(12)
        .frame(minHeight: 30)
        .listRowInsets(EdgeInsets(top: 0, leading: leadingInset, bottom: 0, trailing: 18))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }
}

private struct SidebarCourseGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(count)).monospacedDigit()
        }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 7)
            .padding(.bottom, 1)
            .listRowInsets(EdgeInsets(top: 0, leading: 50, bottom: 0, trailing: 12))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .selectionDisabled()
            .accessibilityAddTraits(.isHeader)

    }
}

private struct SidebarRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }

    private struct Row: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? WeiBeiTheme.cinnabar.opacity(0.15) : (hovered ? WeiBeiTheme.paperInset : .clear))
                        .shadow(color: hovered ? Color.black.opacity(0.22) : .clear, radius: 3, y: 2)
                }
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { hovered = $0 }
        }
    }
}

private struct LibraryRow: View {
    let item: StudyItem
    let subtitle: String
    let resolvedTitle: String?
    let selected: Bool
    let opened: Bool
    let isNote: Bool
    let language: WeiBeiInterfaceLanguage
    let match: String

    private var title: Text {
        let value = resolvedTitle ?? item.title
        guard !match.isEmpty, let range = value.range(of: match, options: [.caseInsensitive, .diacriticInsensitive]) else { return Text(value) }
        var text = AttributedString(value)
        if let hit = Range(range, in: text) { text[hit].inlinePresentationIntent = .stronglyEmphasized }
        return Text(text)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isNote ? "square.and.pencil" : "doc.text")
                .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                title.lineLimit(1)
                // Keep file-availability errors visible; ordinary filenames
                // belong in the tooltip, not a duplicated second title line.
                if subtitle != item.subtitle {
                    Text(subtitle)
                        .weiBeiText(11)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }
            }
            if opened {
                Spacer(minLength: 3)
                Text(selected ? (isNote ? language.text("正在编辑", "Editing") : language.text("正在阅读", "Reading")) : language.text("已打开", "Open"))
                    .font(.system(size: 10))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .contentShape(Rectangle())
    }
}
