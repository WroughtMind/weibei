import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    @FocusState private var librarySearchFocused: Bool
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
                onRenameCourse: { course in
                    renameCourseTitle = course.title
                    courseToRename = course
                },
                onManageCourse: { courseID in
                    courseManagementPresentation = CourseManagementPresentation(courseID: courseID)
                }
            )
                .background(WeiBeiTheme.paper)
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper)
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
                detail: ui("只修改显示名称，资料与笔记保持原位。", "Only the display title changes; files stay where they are."),
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
        HStack(spacing: 6) {
            librarySearchField

            Menu {
                Button(ui("新建课程", "New Course")) {
                    courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
                }
                Divider()
                Button(ui("导入文稿", "Import materials")) {
                    importMaterialsFromSidebar()
                }
                Button(ui("导入笔记", "Import notes")) {
                    importNotesFromSidebar()
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(SidebarAddMenuButtonStyle())
            .accessibilityLabel(Text(ui("添加", "Add")))
            .help(ui("新建课程，或导入文稿和笔记", "Create a course, or import materials and notes"))
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.35))
                .frame(height: 1)
        }
        .zIndex(1)
    }

    private var librarySearchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .weiBeiText(10.5, weight: .medium)
                .foregroundStyle(librarySearchFocused
                    ? WeiBeiTheme.link.opacity(0.72)
                    : WeiBeiTheme.placeholderInk)
            TextField(
                "",
                text: Binding(
                    get: { model.query },
                    set: model.updateQuery
                ),
                prompt: Text(ui("搜索课程资料与笔记", "Search course materials and notes"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .focused($librarySearchFocused)
            .foregroundColor(WeiBeiTheme.ink)
            .weiBeiText(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .weibeiInputSurface(
            active: librarySearchFocused,
            height: 28,
            horizontalPadding: 8
        )
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
    let onRenameCourse: (Course) -> Void
    let onManageCourse: (UUID) -> Void

    var body: some View {
        List {
            Section {
                if model.courses.isEmpty {
                    if store.courses.isEmpty {
                        SidebarEmptyRow(
                            title: ui("还没有课程", "No courses yet")
                        )
                    } else {
                        SidebarEmptyRow(title: ui("还没有匹配课程", "No matching courses"))
                    }
                } else {
                    ForEach(model.courses) { row in
                        courseRow(row)
                    }
                }
            }

            if !model.unassignedMaterials.isEmpty {
                Section {
                    ForEach(model.unassignedMaterials) { row in
                        itemRow(row, compact: false, accent: nil, opensNotebook: false)
                    }
                } header: {
                    SidebarSectionHeader(title: ui("独立资料", "Unassigned Materials"))
                }
            }

            if !model.unassignedNotes.isEmpty {
                Section {
                    ForEach(model.unassignedNotes) { row in
                        itemRow(row, compact: false, accent: nil, opensNotebook: true)
                    }
                } header: {
                    SidebarSectionHeader(title: ui("独立笔记", "Unassigned Notes"))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(WeiBeiTheme.paper)
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

    @ViewBuilder
    private func courseRow(_ row: CourseSidebarCourseRow) -> some View {
        let course = row.course
        let expanded = model.activeCourseID == course.id
        let accent = sidebarCourseAccent(colorIndex: course.colorIndex)

        HStack(spacing: 4) {
            SidebarCourseRow(
                course: course,
                materialCount: row.materialCount,
                noteCount: row.noteCount,
                expanded: expanded,
                language: model.interfaceLanguage,
                onToggle: { store.activateCourse(expanded ? nil : course.id) },
                onEnter: { store.openCourseSpace(course.id) }
            )
        }
        .contextMenu { courseContextMenu(for: course) }
        .draggable("course:\(course.id.uuidString)")
        .dropDestination(for: String.self) { values, _ in
            guard let courseID = draggedCourseID(from: values) else { return false }
            store.moveCourse(courseID, before: course.id)
            return true
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        if expanded {
            SidebarCourseGroupHeader(
                title: ui("资料", "Materials"),
                systemImage: "doc.text",
                count: row.materials.count,
                accent: accent,
                add: { store.importCourseMaterialsFromPanel(courseID: course.id) },
                onDropItem: {
                    store.moveCourseItem($0, before: row.materials.first?.id, intoNotebook: false)
                }
            )
            .id("\(course.id.uuidString)-materials-header")
            .listRowInsets(EdgeInsets(top: 4, leading: 28, bottom: 0, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if row.materials.isEmpty {
                SidebarEmptyRow(
                    title: ui("暂无资料", "No materials"),
                    actionTitle: ui("导入资料…", "Import…"),
                    action: { store.importCourseMaterialsFromPanel(courseID: course.id) }
                )
                .id("\(course.id.uuidString)-materials-empty")
                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 2, trailing: 6))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(row.materials) { item in
                    itemRow(item, compact: true, accent: accent, opensNotebook: false)
                }
            }

            SidebarCourseGroupHeader(
                title: ui("笔记", "Notes"),
                systemImage: "note.text",
                count: row.notes.count,
                accent: accent,
                add: { store.importCourseNotesFromPanel(courseID: course.id) },
                onDropItem: {
                    store.moveCourseItem($0, before: row.notes.first?.id, intoNotebook: true)
                }
            )
            .id("\(course.id.uuidString)-notes-header")
            .listRowInsets(EdgeInsets(top: 4, leading: 28, bottom: 0, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if row.notes.isEmpty {
                SidebarEmptyRow(
                    title: ui("暂无笔记", "No notes"),
                    actionTitle: ui("导入笔记…", "Import…"),
                    action: { store.importCourseNotesFromPanel(courseID: course.id) }
                )
                .id("\(course.id.uuidString)-notes-empty")
                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 4, trailing: 6))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(row.notes) { item in
                    itemRow(item, compact: true, accent: accent, opensNotebook: true)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(
        _ row: CourseSidebarItemRow,
        compact: Bool,
        accent: Color?,
        opensNotebook: Bool
    ) -> some View {
        let item = row.item
        let selected = opensNotebook
            ? model.activeNotebookItemID == item.id
            : model.selectedItemID == item.id
        Group {
            if model.notebookRenameDraft?.itemID == item.id {
                NotebookRenameRow(
                    store: store,
                    model: model,
                    item: item,
                    selected: selected,
                    compact: compact,
                    accent: accent ?? WeiBeiTheme.cinnabar
                )
            } else {
                HStack(spacing: 2) {
                    Button { open(item, opensNotebook: opensNotebook) } label: {
                        LibraryRow(
                            item: item,
                            resolvedTitle: row.resolvedTitle,
                            tags: row.tags,
                            selected: selected,
                            compact: compact,
                            accent: accent
                        )
                    }
                    .buttonStyle(.plain)

                }
                .contextMenu {
                    itemContextMenu(for: row, opensNotebook: opensNotebook)
                }
                .draggable("item:\(item.id)")
                .dropDestination(for: String.self) { values, _ in
                    guard let itemID = draggedItemID(from: values) else { return false }
                    store.moveCourseItem(
                        itemID,
                        before: item.id,
                        intoNotebook: opensNotebook
                    )
                    return true
                }
            }
        }
        .listRowInsets(EdgeInsets(
            top: 1,
            leading: compact ? 28 : 2,
            bottom: 1,
            trailing: 2
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // 显示名与标签共用同一条异步正文管线：compact 行（课程分组内）不展示标签，
        // 但展示解析后的笔记名，所以笔记行无论 compact 与否都要加载。
        .task(id: row.tagRequest) { [weak store = store, weak model = model] in
            guard let request = row.tagRequest else { return }
            if request.draftToken == nil,
               store?.cachedSidebarNoteMeta(for: request) != nil {
                return
            }
            guard
                  let meta = await store?.loadSidebarNoteMeta(for: request),
                  !Task.isCancelled else { return }
            model?.acceptLoadedNoteMeta([(request, meta)])
        }
    }

    @ViewBuilder
    private func courseContextMenu(for course: Course) -> some View {
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
                    : ui("删除资料…", "Delete Material…"))
            }
        }
    }

    private func open(_ item: StudyItem, opensNotebook: Bool) {
        if item.isSample {
            store.select(itemID: item.id)
            store.showLibrary = false
        } else if opensNotebook {
            store.openCourseNote(item.id)
        } else {
            store.openCourseMaterial(item.id)
        }
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        model.interfaceLanguage.text(chinese, english)
    }

    private func draggedCourseID(from values: [String]) -> UUID? {
        values.first(where: { $0.hasPrefix("course:") }).flatMap {
            UUID(uuidString: String($0.dropFirst("course:".count)))
        }
    }

    private func draggedItemID(from values: [String]) -> String? {
        values.first(where: { $0.hasPrefix("item:") }).map {
            String($0.dropFirst("item:".count))
        }
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .weiBeiText(12, weight: .semibold)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .textCase(nil)
    }
}

private struct SidebarEmptyRow: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .weiBeiText(12)
                .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.78))
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.plain)
                .weiBeiText(10.5, weight: .medium)
                .foregroundStyle(
                    hovering ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk.opacity(0.85)
                )
                .contentShape(Rectangle())
            }
        }
        .frame(minHeight: 28, alignment: .leading)
        .onHover { isHovering in
            hovering = isHovering
        }
    }
}

private struct SidebarCourseGroupHeader: View {
    let title: String
    let systemImage: String
    let count: Int
    let accent: Color
    var add: (() -> Void)? = nil
    var onDropItem: ((String) -> Void)? = nil

    @State private var hoveringAdd = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .weiBeiText(9.5, weight: .semibold)
                .foregroundStyle(accent.opacity(0.74))
            Text(title)
                .weiBeiText(10.5, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer(minLength: 4)
            Text("\(count)")
                .weiBeiText(9.5, weight: .medium, design: .monospaced)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                        .weiBeiText(9.5, weight: .semibold)
                        .frame(width: 18, height: 18)
                        .background {
                            if hoveringAdd {
                                WeiBeiEtchedBackdrop(
                                    shape: Circle(),
                                    fill: WeiBeiTheme.paperInset.opacity(0.34),
                                    stroke: WeiBeiTheme.hairline.opacity(0.30)
                                )
                            }
                        }
                }
                .buttonStyle(.plain)
                .onHover { hoveringAdd = $0 }
                .foregroundStyle(accent.opacity(0.82))
                .accessibilityLabel(Text("添加\(title)"))
                .help("添加\(title)")
            }
        }
        .frame(height: 18)
        .dropDestination(for: String.self) { values, _ in
            guard let itemID = values.first(where: { $0.hasPrefix("item:") }).map({
                String($0.dropFirst("item:".count))
            }), let onDropItem else {
                return false
            }
            onDropItem(itemID)
            return true
        }
    }
}

private struct SidebarCourseRow: View {
    let course: Course
    let materialCount: Int
    let noteCount: Int
    let expanded: Bool
    let language: WeiBeiInterfaceLanguage
    let onToggle: () -> Void
    let onEnter: () -> Void
    @State private var hovering = false
    @State private var hoveringEnter = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "book.closed.fill" : "book.closed")
                        .foregroundStyle(accent.opacity(expanded || hovering ? 1 : 0.78))
                        .frame(width: 18)
                        .scaleEffect(expanded || hovering ? 1.08 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.title)
                            .weiBeiText(13, weight: .medium)
                            .lineLimit(1)
                            .foregroundStyle(WeiBeiTheme.ink)
                        Text(language.text(
                            "\(materialCount) 份资料 · \(noteCount) 份笔记",
                            "\(materialCount) materials · \(noteCount) notes"
                        ))
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(expanded
                ? language.text("收起课程内容", "Collapse course contents")
                : language.text("展开课程内容", "Expand course contents")))

            Button(action: onEnter) {
                Image(systemName: "arrow.right")
                    .weiBeiText(9.5, weight: .semibold)
                    .foregroundStyle(enterTint)
                    .frame(width: 22, height: 22)
                    .background {
                        if enterBackdropOpacity > 0 {
                            WeiBeiEtchedBackdrop(
                                shape: Circle(),
                                fill: WeiBeiTheme.paperInset.opacity(enterBackdropOpacity),
                                stroke: WeiBeiTheme.hairline.opacity(0.30)
                            )
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(language.text("进入课程空间", "Enter course space"))
            .accessibilityLabel(Text(language.text("进入课程空间", "Enter course space")))
            .onHover { hoveringEnter = $0 }
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { rowBackdrop }
        .offset(x: expanded || hovering ? 2 : 0)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.layout, value: expanded)
        .animation(WeiBeiMotion.hover, value: hovering)
        .animation(WeiBeiMotion.hover, value: hoveringEnter)
    }

    @ViewBuilder
    private var rowBackdrop: some View {
        if expanded {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperInset.opacity(0.70),
                stroke: WeiBeiTheme.hairline.opacity(0.40)
            )
        } else if hovering {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperInset.opacity(0.30),
                stroke: WeiBeiTheme.hairline.opacity(0.30)
            )
        }
    }

    private var accent: Color {
        sidebarCourseAccent(colorIndex: course.colorIndex)
    }

    private var enterTint: Color {
        if hoveringEnter { return accent.opacity(0.95) }
        if expanded || hovering { return accent.opacity(0.82) }
        return WeiBeiTheme.tertiaryInk.opacity(0.85)
    }

    private var enterBackdropOpacity: Double {
        if hoveringEnter { return 0.52 }
        if expanded || hovering { return 0.38 }
        return 0
    }
}

/// 侧栏搜索框旁边的加号菜单按钮：与搜索框同高度、同圆角语言，弱化到次级操作的分量。
private struct SidebarAddMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarAddMenuButtonBody(configuration: configuration)
    }
}

private struct SidebarAddMenuButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .weiBeiText(12, weight: .medium)
            .foregroundStyle(hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .frame(width: 28, height: 28)
            .background {
                WeiBeiEtchedBackdrop(
                    shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    fill: WeiBeiTheme.paperInset.opacity(highlighted ? 0.42 : 0.18),
                    stroke: WeiBeiTheme.hairline.opacity(highlighted ? 0.62 : 0.42)
                )
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(WeiBeiMotion.press, value: configuration.isPressed)
            .animation(WeiBeiMotion.hover, value: hovering)
            .onHover { hovering = $0 }
    }

    private var highlighted: Bool {
        hovering || configuration.isPressed
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
        .onAppear { titleFocused = true }
    }
}

private struct NotebookRenameRow: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    let item: StudyItem
    let selected: Bool
    let compact: Bool
    let accent: Color
    @FocusState private var focused: Bool

    private var title: Binding<String> {
        Binding(
            get: { model.notebookRenameDraft?.title ?? "" },
            set: { store.notebookRenameDraft?.title = $0 }
        )
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 8) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(accent.opacity(0.78))
                .frame(width: compact ? 15 : 18)
            TextField(
                "",
                text: title,
                prompt: Text(model.interfaceLanguage.text("笔记名", "Note title"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .weiBeiText(compact ? 12.5 : 13, weight: .medium)
            .foregroundColor(WeiBeiTheme.ink)
            .onSubmit {
                if !title.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    store.confirmRenameNotebookNote()
                }
            }
            Button { store.cancelRenameNotebookNote() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 20))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(model.interfaceLanguage.text("取消", "Cancel")))
        }
        .padding(.horizontal, compact ? 7 : 9)
        .frame(height: compact ? 38 : 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperInset.opacity(selected ? 0.74 : 0.44))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { focused = true }
    }
}

private struct LibraryRow: View {
    let item: StudyItem
    /// 解析后的显示名（自定义名 / 正文抬头）；nil 时显示文件名。
    let resolvedTitle: String?
    let tags: [String]
    let selected: Bool
    let compact: Bool
    let accent: Color?
    @State private var hovering = false

    var body: some View {
        CourseSidebarDiagnostics.recordLibraryRowBodyForTesting()
        return HStack(spacing: compact ? 7 : 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(iconColor)
                .frame(width: compact ? 15 : 18)
                .scaleEffect(selected || hovering ? 1.08 : 1)
                .opacity(selected || hovering ? 1 : 0.78)
            VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                Text(resolvedTitle ?? item.title)
                    .weiBeiText(compact ? 12.5 : 13, weight: compact ? .medium : .regular)
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(item.subtitle)
                    .font(compact ? .system(size: 10.5) : .caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                if !compact, !tags.isEmpty {
                    Text(tags.prefix(3).joined(separator: " "))
                        .weiBeiText(10.5, weight: .medium)
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, compact ? 7 : 9)
        .frame(height: compact ? 38 : (tags.isEmpty ? 48 : 58))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { rowBackdrop }
        .offset(x: selected || hovering ? (compact ? 1 : 2) : 0)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill((accent ?? WeiBeiTheme.cinnabar).opacity(0.72))
                    .frame(width: compact ? 2 : 3, height: compact ? 18 : 24)
                    .padding(.leading, 2)
            }
        }
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.micro, value: selected)
        .animation(WeiBeiMotion.hover, value: hovering)
    }

    @ViewBuilder
    private var rowBackdrop: some View {
        if selected {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperInset.opacity(compact ? 0.54 : 0.70),
                stroke: WeiBeiTheme.hairline.opacity(0.40)
            )
        } else if hovering {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperInset.opacity(compact ? 0.22 : 0.30),
                stroke: WeiBeiTheme.hairline.opacity(0.30)
            )
        }
    }

    private var iconColor: Color {
        if let accent {
            return accent.opacity(item.isNotebookNote ? 0.70 : 0.82)
        }
        return item.kind == .pdf ? WeiBeiTheme.link : WeiBeiTheme.tertiaryInk
    }
}

#if DEBUG
enum CourseSidebarDiagnostics {
    private(set) static var libraryRowBodyCountForTesting = 0

    static func resetForTesting() {
        libraryRowBodyCountForTesting = 0
    }

    static func recordLibraryRowBodyForTesting() {
        libraryRowBodyCountForTesting &+= 1
    }
}
#else
enum CourseSidebarDiagnostics {
    static func recordLibraryRowBodyForTesting() {}
}
#endif

private func sidebarCourseAccent(colorIndex: Int) -> Color {
    switch ((colorIndex % 4) + 4) % 4 {
    case 0: WeiBeiTheme.cinnabar
    case 1: WeiBeiTheme.moss
    case 2: WeiBeiTheme.link
    default: WeiBeiTheme.secondaryInk
    }
}
