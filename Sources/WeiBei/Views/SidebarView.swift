import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    @State private var librarySearchFocused = false
    @State private var courseEntry: CourseProjectEntryPresentation?
    @State private var lastBrowsedCourseID: UUID?

    private var targetCourseID: UUID? {
        let candidate = lastBrowsedCourseID ?? model.activeCourseID
        return model.browsing.courses.first { $0.id == candidate }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CourseSidebarList(
                store: store,
                model: model,
                panes: store.paneState,
                lastBrowsedCourseID: $lastBrowsedCourseID
            )
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .tint(WeiBeiTheme.accent)
        .onReceive(store.paneState.$focusRequest) { _ in
            librarySearchFocused = store.paneState.focusedPane == .library
        }
        .onAppear {
            librarySearchFocused = store.paneState.focusedPane == .library
        }
        .sheet(item: $courseEntry) { _ in
            CourseProjectEntrySheet(
                cancel: { courseEntry = nil },
                openCourse: { _ in courseEntry = nil }
            )
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            librarySearchField
            addMenu
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.45))
            .frame(height: 0.5)
            .allowsHitTesting(false)
    }

    private var addMenu: some View {
        Menu {
            Button(ui("新建笔记", "New Note")) {
                store.createBlankNotebookNote(in: targetCourseID)
            }
            Button(ui("导入文稿…", "Import Documents…")) {
                store.importCourseMaterialsFromPanel(courseID: targetCourseID)
            }
            Button(ui("导入笔记…", "Import Notes…")) {
                store.importCourseNotesFromPanel(courseID: targetCourseID)
            }
            Divider()
            Button(ui("新建课程…", "New Course…")) {
                courseEntry = CourseProjectEntryPresentation()
            }
        } label: {
            Image(systemName: "plus")
                .weiBeiText(12.5, weight: .medium)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(WeiBeiTheme.secondaryInk)
        .fixedSize()
        .accessibilityLabel(ui("新建或导入", "New or import"))
        .help(ui("新建笔记、导入文稿或新建课程", "Create note, import files, or add course"))
    }

    private var librarySearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
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
                        .weiBeiText(12)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ui("清除搜索", "Clear search"))
            }
        }
        .padding(.horizontal, 8)
        .background(
            WeiBeiTheme.paperInset.opacity(0.30),
            in: RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius, style: .continuous)
        )
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
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @State private var expandedCourses: Set<UUID> = []
    @State private var collapsedResults: Set<UUID> = []
    @State private var hoveredCourseID: UUID?
    @FocusState private var focusedCourse: UUID?

    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searching: Bool {
        !trimmedQuery.isEmpty
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
                ForEach(Array(projection.courses.enumerated()), id: \.element.id) { index, row in
                    courseRow(row, isFirst: index == 0, results: results)
                }
                if !projection.courses.isEmpty && (!projection.unassignedMaterials.isEmpty || !projection.unassignedNotes.isEmpty) {
                    Rectangle()
                        .fill(WeiBeiTheme.hairline.opacity(0.45))
                        .frame(height: 0.5)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                }
                if !projection.unassignedMaterials.isEmpty {
                    SidebarSectionHeader(title: ui("通用资料", "General materials"), topSpacing: 8)
                    ForEach(projection.unassignedMaterials) { row in itemRow(row, opensNotebook: false, result: results) }
                }
                if !projection.unassignedNotes.isEmpty {
                    SidebarSectionHeader(title: ui("独立笔记", "Unassigned notes"), topSpacing: 8)
                    ForEach(projection.unassignedNotes) { row in itemRow(row, opensNotebook: true, result: results) }
                }
                if projection.courses.isEmpty && projection.unassignedMaterials.isEmpty && projection.unassignedNotes.isEmpty {
                    SidebarEmptyStateRow(
                        title: results
                            ? ui("找不到「\(trimmedQuery)」", "No results for \"\(trimmedQuery)\"")
                            : ui("还没有课程", "No courses yet")
                    )
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 18)
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, 6, for: .scrollContent)
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
        withAnimation(reduceMotion ? nil : WeiBeiMotion.layout) {
            if results {
                if !collapsedResults.insert(id).inserted { collapsedResults.remove(id) }
            } else {
                if !expandedCourses.insert(id).inserted { expandedCourses.remove(id) }
                store.libraryDrawer.expandedCourseIDs = expandedCourses
            }
        }
    }

    @ViewBuilder
    private func courseRow(_ row: CourseSidebarCourseRow, isFirst: Bool, results: Bool) -> some View {
        let course = row.course
        let expanded = results ? !collapsedResults.contains(row.id) : expandedCourses.contains(row.id)
        let totalCount = row.materialCount + row.noteCount
        let isHovered = hoveredCourseID == row.id
        HStack(spacing: 4) {
            Button { toggleCourse(row.id, results: results) } label: {
                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                            .frame(width: 10)
                        Image(systemName: "book.closed.fill")
                            .weiBeiText(12.5)
                            .foregroundStyle([WeiBeiTheme.accent, WeiBeiTheme.moss, WeiBeiTheme.link, WeiBeiTheme.secondaryInk][((course.colorIndex % 4) + 4) % 4])
                            .frame(width: 14)
                    }
                    Text(course.title)
                        .weiBeiText(13.5, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

            if isHovered {
                courseAddMenu(courseID: row.id)
            } else if totalCount > 0 {
                Text(String(totalCount))
                    .weiBeiText(11)
                    .monospacedDigit()
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius, style: .continuous)
                .fill(isHovered ? WeiBeiTheme.ink.opacity(0.055) : .clear)
        }
        .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: isHovered)
        .onHover { hovering in
            if hovering {
                hoveredCourseID = row.id
            } else if hoveredCourseID == row.id {
                hoveredCourseID = nil
            }
        }
        .contextMenu {
            courseActions(courseID: row.id)
            Divider()
            Button(ui("在访达中显示", "Show in Finder")) {
                store.revealCourseRoot(row.id)
            }
        }
        .listRowInsets(EdgeInsets(top: isFirst ? 2 : 8, leading: 8, bottom: 1, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(row.id)

        if expanded {
            if results {
                ForEach(row.materials) { item in itemRow(item, opensNotebook: false, courseID: row.id, result: true) }
                ForEach(row.notes) { item in itemRow(item, opensNotebook: true, courseID: row.id, result: true) }
                if row.materials.isEmpty && row.notes.isEmpty {
                    SidebarEmptyRow(title: ui("没有匹配内容", "No matching items"), leadingInset: 47)
                }
            } else {
                courseContents(row)
            }
        }
    }

    private func courseAddMenu(courseID: UUID) -> some View {
        Menu {
            courseActions(courseID: courseID)
        } label: {
            Image(systemName: "plus")
                .weiBeiText(11.5, weight: .medium)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(WeiBeiTheme.secondaryInk)
        .fixedSize()
        .accessibilityLabel(ui("添加到此课程", "Add to course"))
    }

    @ViewBuilder
    private func courseActions(courseID: UUID) -> some View {
        Button(ui("新建笔记", "New Note")) {
            store.createBlankNotebookNote(in: courseID)
        }
        Button(ui("导入文稿…", "Import Documents…")) {
            store.importCourseMaterialsFromPanel(courseID: courseID)
        }
        Button(ui("导入笔记…", "Import Notes…")) {
            store.importCourseNotesFromPanel(courseID: courseID)
        }
    }

    @ViewBuilder
    private func courseContents(_ row: CourseSidebarCourseRow) -> some View {
        if !row.materials.isEmpty {
            SidebarCourseGroupHeader(title: ui("文稿", "Documents"))
                .id("\(row.id.uuidString)-materials-header")
            ForEach(row.materials) { item in
                itemRow(item, opensNotebook: false, courseID: row.id)
            }
        }
        if !row.notes.isEmpty {
            SidebarCourseGroupHeader(title: ui("笔记", "Notes"))
                .id("\(row.id.uuidString)-notes-header")
            ForEach(row.notes) { item in
                itemRow(item, opensNotebook: true, courseID: row.id)
            }
        }
        if row.materials.isEmpty && row.notes.isEmpty {
            SidebarEmptyRow(
                title: ui("还没有内容", "Empty"),
                leadingInset: 47,
                actionTitle: ui("导入…", "Import…"),
                action: { store.importCourseMaterialsFromPanel(courseID: row.id) }
            )
            .id("\(row.id.uuidString)-empty")
        }
    }

    private func itemRow(_ row: CourseSidebarItemRow, opensNotebook: Bool, courseID: UUID? = nil, result: Bool = false) -> some View {
        let item = row.item
        let nested = courseID != nil
        let opened = opensNotebook ? panes.showNotes && model.activeNotebookItemID == item.id
            : panes.showReader && model.selectedItemID == item.id
        let selected = opened && panes.lastContentPane == (opensNotebook ? .notes : .reader)
        let helpTitle = row.resolvedTitle ?? item.title
        let paneStatusHelp: String? = opened
            ? (selected
                ? (opensNotebook ? ui("正在编辑", "Editing") : ui("正在阅读", "Reading"))
                : ui("已在另一栏打开", "Open in other pane"))
            : nil
        let helpLines = ([helpTitle, store.displaySubtitle(for: item)] + row.tags + [paneStatusHelp].compactMap { $0 })
            .filter { !$0.isEmpty }
        return Button { open(item, opensNotebook: opensNotebook, courseID: courseID) } label: {
            LibraryRow(
                item: item,
                subtitle: store.displaySubtitle(for: item),
                resolvedTitle: row.resolvedTitle,
                selected: selected,
                opened: opened,
                isNote: opensNotebook,
                nested: nested,
                match: result ? model.query : ""
            )
            .padding(.leading, nested ? 9 : 8)
            .padding(.trailing, 8)
        }
        .buttonStyle(SidebarRowStyle(selected: selected))
        .contextMenu {
            if opensNotebook {
                NotePDFExportMenuItem(itemID: item.id)
            }
            Button(ui("在访达中显示", "Show in Finder")) {
                store.revealCourseFolder(containing: item.id, in: courseID)
            }
            if let courseID {
                Button(ui("从本课程移除", "Remove from This Course")) {
                    store.removeItem(item.id, fromCourseID: courseID)
                }
            }
            Divider()
            Button(ui("将原文件移到废纸篓…", "Move Source File to Trash…")) {
                store.confirmMoveItemSourceToTrash(item.id)
            }
        }
        .accessibilityValue(opened ? (selected ? ui("当前内容", "Current") : ui("已打开", "Open")) : "")
        .help(helpLines.joined(separator: "\n"))
        .listRowInsets(EdgeInsets(top: 1, leading: nested ? 38 : 8, bottom: 1, trailing: 8))
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
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topSpacing)
            .padding(.bottom, 3)
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 16))
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
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            Spacer(minLength: 4)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .foregroundStyle(WeiBeiTheme.accent)
            }
        }
        .weiBeiText(12)
        .frame(minHeight: 28)
        .listRowInsets(EdgeInsets(top: 0, leading: leadingInset, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }
}

private struct SidebarEmptyStateRow: View {
    let title: String

    var body: some View {
        Text(title)
            .weiBeiText(12.5)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 72)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }
}

private struct SidebarCourseGroupHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .weiBeiText(10.5, weight: .medium)
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 5)
            .padding(.bottom, 1)
            .listRowInsets(EdgeInsets(top: 0, leading: 47, bottom: 0, trailing: 16))
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
        @Environment(\.weibeiReduceMotion) private var reduceMotion
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius, style: .continuous)
                        .fill(
                            selected
                                ? WeiBeiTheme.accent.opacity(0.12)
                                : (hovered ? WeiBeiTheme.ink.opacity(0.055) : .clear)
                        )
                }
                .opacity(configuration.isPressed ? 0.78 : 1)
                .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: hovered)
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
    let nested: Bool
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
                .weiBeiText(11)
                .foregroundStyle(selected ? WeiBeiTheme.accent : (nested ? WeiBeiTheme.tertiaryInk : WeiBeiTheme.secondaryInk))
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .weiBeiText(12, weight: selected ? .medium : .regular)
                    .foregroundStyle(selected || !nested ? WeiBeiTheme.ink : WeiBeiTheme.ink.opacity(0.78))
                    .lineLimit(1)
                // Keep file-availability errors visible; ordinary filenames
                // belong in the tooltip, not a duplicated second title line.
                if subtitle != item.subtitle {
                    Text(subtitle)
                        .weiBeiText(11)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }
            }
            if opened && !selected {
                Spacer(minLength: 4)
                Circle()
                    .fill(WeiBeiTheme.accent.opacity(0.55))
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
    }
}
