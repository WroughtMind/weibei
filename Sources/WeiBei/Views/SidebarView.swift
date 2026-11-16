import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    @State private var librarySearchFocused = false
    @State private var courseEntryPresentation: CourseProjectEntryPresentation?
    @State private var courseToRename: Course?
    @State private var renameCourseTitle = ""
    @State private var courseManagementPresentation: CourseManagementPresentation?

    var body: some View {
        VStack(spacing: 0) {
            header
            CourseSidebarList(
                store: store,
                model: model,
                panes: store.paneState,
                onRenameCourse: { course in
                    renameCourseTitle = course.title
                    courseToRename = course
                },
                onManageCourse: { courseID in
                    courseManagementPresentation = CourseManagementPresentation(courseID: courseID)
                }
            )
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .tint(WeiBeiTheme.cinnabar)
        .onReceive(store.paneState.$focusRequest) { _ in
            librarySearchFocused = store.paneState.focusedPane == .library
        }
        .onAppear {
            librarySearchFocused = store.paneState.focusedPane == .library
        }
        .sheet(item: $courseEntryPresentation) { presentation in
            CourseProjectEntrySheet(
                initialIntent: presentation.intent,
                cancel: { courseEntryPresentation = nil },
                openCourse: { courseID in
                    courseEntryPresentation = nil
                    store.openCourseSpace(courseID)
                }
            )
            .environmentObject(store)
        }
        .sheet(item: $courseToRename) { course in
            SidebarCourseNameSheet(
                store: store,
                heading: ui("重命名课程", "Rename Course"),
                detail: ui("只修改显示名称，文稿与笔记保持原位。", "Only the display title changes; files stay where they are."),
                confirmTitle: ui("保存", "Save"),
                title: $renameCourseTitle,
                cancel: { courseToRename = nil },
                confirm: { renameCourse(course) }
            )
        }
        .sheet(item: $courseManagementPresentation) { presentation in
            CourseManagementSheet(courseID: presentation.courseID)
                .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ui("课程库", "Course Library"))
                    .font(.system(size: 19, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                addMenu
            }
            librarySearchField
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 11)
    }

    private var addMenu: some View {
        Menu {
            Button(ui("新建课程", "New Course"), systemImage: "folder.badge.plus") {
                courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
            }
            Divider()
            if let course = store.activeCourse {
                Text(ui("导入到「\(course.title)」", "Import into \(course.title)"))
            }
            Button(ui("导入文稿…", "Import Documents…"), systemImage: "doc.badge.plus") {
                importMaterialsFromSidebar()
            }
            Button(ui("导入笔记…", "Import Notes…"), systemImage: "note.text.badge.plus") {
                importNotesFromSidebar()
            }
        } label: {
            Image(systemName: "plus")
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .tint(WeiBeiTheme.secondaryInk)
        .accessibilityLabel(Text(ui("添加", "Add")))
        .help(ui("新建课程，或导入文稿和笔记", "Create a course, or import documents and notes"))
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

    private func importMaterialsFromSidebar() {
        if let courseID = store.activeCourseID {
            store.importCourseMaterialsFromPanel(courseID: courseID)
        } else {
            store.importFilesFromPanel()
        }
    }

    private func importNotesFromSidebar() {
        if let courseID = store.activeCourseID {
            store.importCourseNotesFromPanel(courseID: courseID)
        } else {
            store.importCourseNotesFromPanel(courseID: nil)
        }
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        model.interfaceLanguage.text(chinese, english)
    }

    private func renameCourse(_ course: Course) {
        store.renameCourse(course.id, title: renameCourseTitle)
        courseToRename = nil
        renameCourseTitle = ""
    }

}

struct CourseSidebarList: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    @ObservedObject var panes: WorkspacePaneState
    let onRenameCourse: (Course) -> Void
    let onManageCourse: (UUID) -> Void
    @State private var expandedCourses: Set<UUID> = []
    @State private var hoveredCourse: UUID?
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
                    if results {
                        if row.materials.isEmpty && row.notes.isEmpty {
                            Button(row.course.title) { store.openCourseSpace(row.id) }
                                .buttonStyle(.plain)
                        } else {
                            SidebarSectionHeader(title: row.course.title, topSpacing: 8)
                            ForEach(row.materials) { item in
                                itemRow(item, opensNotebook: false, courseID: row.id, result: true)
                            }
                            ForEach(row.notes) { item in
                                itemRow(item, opensNotebook: true, courseID: row.id, result: true)
                            }
                        }
                    } else {
                        courseRow(row)
                    }
                }
                if !projection.unassignedMaterials.isEmpty {
                    SidebarSectionHeader(title: ui("通用资料", "General materials"), topSpacing: 10)
                    ForEach(projection.unassignedMaterials) { row in itemRow(row, opensNotebook: false) }
                }
                if !projection.unassignedNotes.isEmpty {
                    SidebarSectionHeader(title: ui("独立笔记", "Unassigned notes"), topSpacing: 10)
                    ForEach(projection.unassignedNotes) { row in itemRow(row, opensNotebook: true) }
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
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private func toggleCourse(_ id: UUID) {
        if !expandedCourses.insert(id).inserted { expandedCourses.remove(id) }
        store.libraryDrawer.expandedCourseIDs = expandedCourses
    }

    @ViewBuilder
    private func courseRow(_ row: CourseSidebarCourseRow) -> some View {
        let course = row.course
        let expanded = expandedCourses.contains(course.id)
        HStack(spacing: 4) {
            Button { toggleCourse(course.id) } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .frame(width: 12)
                    Text(course.title)
                        .font(.system(size: 13, weight: expanded ? .semibold : .regular))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .focused($focusedCourse, equals: course.id)
            .accessibilityLabel(course.title)
            .accessibilityValue(expanded ? ui("已展开", "Expanded") : ui("已收起", "Collapsed"))
            .onKeyPress(.rightArrow) {
                if !expanded { toggleCourse(course.id) }
                return .handled
            }
            .onKeyPress(.leftArrow) {
                if expanded { toggleCourse(course.id) }
                return .handled
            }
            Button { store.openCourseSpace(course.id) } label: {
                Image(systemName: "arrow.forward.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 24, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(ui("进入\(course.title)课程空间", "Enter \(course.title)"))
            .help(ui("进入课程空间", "Open course space"))
            .opacity(hoveredCourse == course.id || focusedCourse == course.id || expanded ? 1 : 0)

        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredCourse = inside ? course.id : (hoveredCourse == course.id ? nil : hoveredCourse) }
        .contextMenu { courseContextMenu(for: course) }
        .draggable(WeiBeiWorkspaceDrag.course(course.id))
        .dropDestination(for: WeiBeiWorkspaceDrag.self) { values, _ in
            guard let courseID = draggedCourseID(from: values) else { return false }
            store.moveCourse(courseID, before: course.id)
            return true
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(course.id)
        if expanded { courseContents(row) }
    }

    @ViewBuilder
    private func courseContents(_ row: CourseSidebarCourseRow) -> some View {
        SidebarCourseGroupHeader(title: ui("文稿", "Documents")) {
            store.moveCourseItem($0, before: row.materials.first?.id, intoNotebook: false)
        }
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
        SidebarCourseGroupHeader(title: ui("笔记", "Notes")) {
            store.moveCourseItem($0, before: row.notes.first?.id, intoNotebook: true)
        }
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
        let nested = courseID != nil && !result
        let opened = opensNotebook ? panes.showNotes && model.activeNotebookItemID == item.id
            : panes.showReader && model.selectedItemID == item.id
        let selected = opened && panes.lastContentPane == (opensNotebook ? .notes : .reader)
        return Group {
            if model.notebookRenameDraft?.itemID == item.id {
                NotebookRenameRow(store: store, model: model, item: item)
                    .padding(.leading, nested ? 18 : 6)
                    .padding(.trailing, 6)
            } else {
                Button { open(item, opensNotebook: opensNotebook, courseID: courseID) } label: {
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
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? WeiBeiTheme.cinnabar.opacity(model.appearanceMode.isDark ? 0.20 : 0.09) : .clear)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(opened ? (selected ? ui("当前内容", "Current") : ui("已打开", "Open")) : "")
                .help(([row.resolvedTitle ?? item.title, store.displaySubtitle(for: item)] + row.tags)
                    .joined(separator: "\n"))
                .contextMenu { itemContextMenu(for: row, opensNotebook: opensNotebook) }
                .draggable(WeiBeiWorkspaceDrag.item(item.id))
                .dropDestination(for: WeiBeiWorkspaceDrag.self) { values, _ in
                    guard let itemID = draggedItemID(from: values) else { return false }
                    store.moveCourseItem(itemID, before: item.id, intoNotebook: opensNotebook)
                    return true
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .id(item.id)
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

    @ViewBuilder
    private func courseContextMenu(for course: Course) -> some View {
        Button(ui("打开课程空间", "Open Course")) { store.openCourseSpace(course.id) }
        Divider()
        Button(ui("导入文稿…", "Import Documents…")) {
            store.importCourseMaterialsFromPanel(courseID: course.id)
        }
        Button(ui("导入笔记…", "Import Notes…")) {
            store.importCourseNotesFromPanel(courseID: course.id)
        }
        Divider()
        Button(ui("重命名课程", "Rename course")) {
            onRenameCourse(course)
        }
        Button(ui("课程设置…", "Course Settings…")) {
            onManageCourse(course.id)
        }
    }

    @ViewBuilder
    private func itemContextMenu(
        for row: CourseSidebarItemRow,
        opensNotebook: Bool
    ) -> some View {
        let item = row.item
        if opensNotebook {
            Button(ui("重命名笔记", "Rename Note")) {
                store.promptRenameNotebookNote(itemID: item.id)
            }
        }
        if !item.isSample, !store.courses.isEmpty {
            Menu(ui("课程关系", "Course relations")) {
                ForEach(store.courses) { course in
                    let assigned = row.courseIDs.contains(course.id)
                    Button {
                        var courseIDs = row.courseIDs
                        if assigned {
                            courseIDs.remove(course.id)
                        } else {
                            courseIDs.insert(course.id)
                        }
                        store.setCourseIDs(courseIDs, for: item.id)
                    } label: {
                        Label(course.title, systemImage: assigned ? "checkmark" : "circle")
                    }
                }
            }
        }
        if !item.isSample, item.url != nil {
            Divider()
            Button(role: .destructive) {
                store.confirmMoveItemSourceToTrash(item.id)
            } label: {
                Text(opensNotebook
                    ? ui("删除笔记…", "Delete Note…")
                    : ui("删除文稿…", "Delete document…"))
            }
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

    private func draggedCourseID(from values: [WeiBeiWorkspaceDrag]) -> UUID? {
        values.compactMap { if case .course(let id) = $0 { return id }; return nil }.first
    }

    private func draggedItemID(from values: [WeiBeiWorkspaceDrag]) -> String? {
        values.compactMap { if case .item(let id) = $0 { return id }; return nil }.first
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
    let onDropItem: (String) -> Void

    var body: some View {
        Text(title)
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
            .dropDestination(for: WeiBeiWorkspaceDrag.self) { values, _ in
                guard let itemID = values.compactMap({ value -> String? in
                    if case .item(let id) = value { return id }; return nil
                }).first else { return false }
                onDropItem(itemID)
                return true
            }
    }
}

private struct SidebarCourseNameSheet: View {
    let store: WorkspaceStore
    let heading: String
    let detail: String
    let confirmTitle: String
    @Binding var title: String
    let cancel: () -> Void
    let confirm: () -> Void
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(heading)
                    .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
                Text(detail)
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            TextField(store.ui("课程名", "Course title"), text: $title)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .weiBeiText(13)
                .foregroundColor(WeiBeiTheme.ink)
                .weibeiInputSurface(active: titleFocused, height: 32)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button(store.ui("取消", "Cancel"), action: cancel)
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .weiBeiFittedSheet()
        .onAppear { titleFocused = true }
    }
}

private struct NotebookRenameRow: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    let item: StudyItem
    @FocusState private var focused: Bool

    private var title: Binding<String> {
        Binding(
            get: { model.notebookRenameDraft?.title ?? "" },
            set: { store.notebookRenameDraft?.title = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 14)
            TextField(model.interfaceLanguage.text("笔记名", "Note title"), text: title)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    if !title.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.confirmRenameNotebookNote()
                    }
                }
            Button { store.cancelRenameNotebookNote() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(model.interfaceLanguage.text("取消", "Cancel")))
        }
        .weiBeiText(13)
        .frame(minHeight: 30)
        .onAppear { focused = true }
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
            if opened && !selected {
                Spacer(minLength: 3)
                Text(language.text("已打开", "Open"))
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
