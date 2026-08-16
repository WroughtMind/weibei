import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    @FocusState private var librarySearchFocused: Bool
    @State private var courseEntryPresentation: CourseProjectEntryPresentation?
    @State private var courseToRename: Course?
    @State private var renameCourseTitle = ""
    @State private var coursePendingDeletion: Course?
    @State private var courseManagementPresentation: CourseManagementPresentation?
    @State private var courseDeletionError: String?

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
                },
                onDeleteCourse: { coursePendingDeletion = $0 }
            )
                .background(WeiBeiTheme.paperRaised.opacity(0.72))
        }
        .weibeiPanel()
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
        .confirmationDialog(
            ui("删除这门课程？", "Delete this course?"),
            isPresented: Binding(
                get: { coursePendingDeletion != nil },
                set: { if !$0 { coursePendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: coursePendingDeletion
        ) { course in
            Button(role: .destructive) { deleteCourse(course) } label: {
                Text(ui("删除“\(course.title)”", "Delete “\(course.title)”"))
            }
            Button(ui("取消", "Cancel"), role: .cancel) {
                coursePendingDeletion = nil
            }
        } message: { course in
            Text(courseDeletionMessage(for: course))
        }
        .alert(
            ui("无法删除课程", "Could Not Delete Course"),
            isPresented: Binding(
                get: { courseDeletionError != nil },
                set: { if !$0 { courseDeletionError = nil } }
            )
        ) {
            Button(ui("好", "OK"), role: .cancel) {}
        } message: {
            Text(courseDeletionError ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ui("课程目录", "Course Index"))
                        .font(WeiBeiTypography.brandFont(
                            language: model.interfaceLanguage,
                            size: 22,
                            weight: .semibold
                        ))
                    Button { store.presentCourseWorkspace(.hub) } label: {
                        HStack(spacing: 3) {
                            Text(ui("课程空间", "Course Space"))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(ui("打开课程空间", "Open course space")))
                    .help(ui("打开课程空间", "Open course space"))
                }
                Spacer()
                Button {
                    courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(WeiBeiIconButtonStyle())
                .accessibilityLabel(Text(ui("添加课程", "Add course")))
                .help(ui("新建或纳入课程", "Create or add a course"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            TextField(
                "",
                text: Binding(
                    get: { model.query },
                    set: model.updateQuery
                ),
                prompt: Text(ui("搜索课程资料与笔记", "Search course materials and notes"))
                    .font(.system(size: 13))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .focused($librarySearchFocused)
            .foregroundColor(WeiBeiTheme.ink)
            .font(.system(size: 13))
            .weibeiInputSurface(active: librarySearchFocused)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.70, materialOpacity: 0.10))
        .overlay(alignment: .bottom) {
            WeiBeiHeaderHandoffFade(height: 16, opacity: 0.72)
                .offset(y: 16)
        }
        .zIndex(1)
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        model.interfaceLanguage.text(chinese, english)
    }

    private func renameCourse(_ course: Course) {
        store.renameCourse(course.id, title: renameCourseTitle)
        courseToRename = nil
        renameCourseTitle = ""
    }

    private func deleteCourse(_ course: Course) {
        coursePendingDeletion = nil
        Task { @MainActor in
            do {
                try await store.deleteCourse(course.id)
            } catch {
                courseDeletionError = error.localizedDescription
            }
        }
    }

    private func courseDeletionMessage(for course: Course) -> String {
        guard let root = store.courseRootURL(for: course.id) else {
            if store.courseHasNeverHadFolder(course.id) {
                return ui(
                    "这门旧课程从未有课程文件夹。删除会移除课程和全部关系；外部原文件会留在独立资料或笔记中，可从侧边栏分别删除。",
                    "This legacy course never had a course folder. Deleting removes the course and all relations; external source files remain as independent materials or notes and can be deleted from the sidebar."
                )
            }
            return ui(
                "课程文件夹当前不可访问。请先在 Finder 中把它放到当前魏碑资料库里，再重新打开魏碑。",
                "The course folder is unavailable. WeiBei won’t pretend to delete it; reconnect the real folder with Add Existing Folder first."
            )
        }
        return ui(
            "会把整个课程文件夹及其中内容移到 macOS 废纸篓，并从魏碑删除：\n\(root.path)",
            "The entire course folder and its contents will be moved to the macOS Trash and deleted from WeiBei:\n\(root.path)"
        )
    }
}

struct CourseSidebarList: View {
    let store: WorkspaceStore
    @ObservedObject var model: CourseSidebarModel
    let onRenameCourse: (Course) -> Void
    let onManageCourse: (UUID) -> Void
    let onDeleteCourse: (Course) -> Void

    var body: some View {
        List {
            Section {
                if model.courses.isEmpty {
                    SidebarEmptyRow(title: ui("还没有匹配课程", "No matching courses"))
                } else {
                    ForEach(model.courses) { row in
                        courseRow(row)
                    }
                }
            } header: {
                SidebarSectionHeader(title: ui("课程", "Courses"))
            }

            if !model.unassignedMaterials.isEmpty {
                Section {
                    ForEach(model.unassignedMaterials) { row in
                        itemRow(row, compact: false, accent: nil)
                    }
                } header: {
                    SidebarSectionHeader(title: ui("独立资料", "Unassigned Materials"))
                }
            }

            if !model.unassignedNotes.isEmpty {
                Section {
                    ForEach(model.unassignedNotes) { row in
                        itemRow(row, compact: false, accent: nil)
                    }
                } header: {
                    SidebarSectionHeader(title: ui("独立笔记", "Unassigned Notes"))
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
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
            Button {
                store.activateCourse(expanded ? nil : course.id)
            } label: {
                SidebarCourseRow(
                    course: course,
                    materialCount: row.materialCount,
                    noteCount: row.noteCount,
                    expanded: expanded,
                    language: model.interfaceLanguage
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(expanded
                ? ui("收起课程内容", "Collapse course contents")
                : ui("展开课程内容", "Expand course contents")))

            Button { store.openCourseSpace(course.id) } label: {
                Text(ui("进入", "Enter"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.88))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(WeiBeiTheme.cinnabarSoft.opacity(0.42), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(ui("进入课程空间", "Enter course space"))
            .accessibilityLabel(Text(ui("进入课程空间", "Enter course space")))

            Menu { courseContextMenu(for: course) } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text(ui("管理课程", "Manage course")))
            .help(ui("管理课程", "Manage course"))
        }
        .contextMenu { courseContextMenu(for: course) }
        .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        if expanded {
            SidebarCourseGroupHeader(
                title: ui("资料", "Materials"),
                systemImage: "doc.text",
                count: row.materials.count,
                accent: accent
            )
            .id("\(course.id.uuidString)-materials-header")
            .listRowInsets(EdgeInsets(top: 4, leading: 28, bottom: 0, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if row.materials.isEmpty {
                SidebarEmptyRow(title: ui("暂无资料", "No materials"))
                    .id("\(course.id.uuidString)-materials-empty")
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 2, trailing: 6))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(row.materials) { item in
                    itemRow(item, compact: true, accent: accent)
                }
            }

            SidebarCourseGroupHeader(
                title: ui("笔记", "Notes"),
                systemImage: "note.text",
                count: row.notes.count,
                accent: accent
            )
            .id("\(course.id.uuidString)-notes-header")
            .listRowInsets(EdgeInsets(top: 4, leading: 28, bottom: 0, trailing: 6))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if row.notes.isEmpty {
                SidebarEmptyRow(title: ui("暂无笔记", "No notes"))
                    .id("\(course.id.uuidString)-notes-empty")
                    .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 4, trailing: 6))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(row.notes) { item in
                    itemRow(item, compact: true, accent: accent)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(
        _ row: CourseSidebarItemRow,
        compact: Bool,
        accent: Color?
    ) -> some View {
        let item = row.item
        let selected = item.isNotebookNote
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
                    Button { open(item) } label: {
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

                    if !item.isSample {
                        Menu { itemContextMenu(for: row) } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 22, height: compact ? 28 : 32)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel(Text(ui("管理文件", "Manage file")))
                        .help(ui("管理文件", "Manage file"))
                    }
                }
                .contextMenu { itemContextMenu(for: row) }
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
        Button(ui("进入课程空间", "Enter course space")) {
            store.openCourseSpace(course.id)
        }
        Button(ui("重命名课程", "Rename course")) {
            onRenameCourse(course)
        }
        Button(ui("课程设置…", "Course Settings…")) {
            onManageCourse(course.id)
        }
        Divider()
        Button(role: .destructive) {
            onDeleteCourse(course)
        } label: {
            Text(ui("删除课程…", "Delete Course…"))
        }
    }

    @ViewBuilder
    private func itemContextMenu(for row: CourseSidebarItemRow) -> some View {
        let item = row.item
        if item.isNotebookNote {
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
                Text(item.isNotebookNote
                    ? ui("删除笔记…", "Delete Note…")
                    : ui("删除资料…", "Delete Material…"))
            }
        }
    }

    private func open(_ item: StudyItem) {
        if item.isSample {
            store.select(itemID: item.id)
            store.showLibrary = false
        } else if item.isNotebookNote {
            store.openCourseNote(item.id)
        } else {
            store.openCourseMaterial(item.id)
        }
    }

    private func ui(_ chinese: String, _ english: String) -> String {
        model.interfaceLanguage.text(chinese, english)
    }
}

private struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .textCase(nil)
    }
}

private struct SidebarEmptyRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.78))
            .frame(height: 28, alignment: .leading)
    }
}

private struct SidebarCourseGroupHeader: View {
    let title: String
    let systemImage: String
    let count: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(accent.opacity(0.74))
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
        }
        .frame(height: 18)
    }
}

private struct SidebarCourseRow: View {
    let course: Course
    let materialCount: Int
    let noteCount: Int
    let expanded: Bool
    let language: WeiBeiInterfaceLanguage
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: expanded ? "book.closed.fill" : "book.closed")
                .foregroundStyle(accent.opacity(expanded || hovering ? 1 : 0.78))
                .frame(width: 18)
                .scaleEffect(expanded || hovering ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(language.text(
                    "\(materialCount) 份资料 · \(noteCount) 份笔记",
                    "\(materialCount) materials · \(noteCount) notes"
                ))
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(expanded ? accent.opacity(0.78) : WeiBeiTheme.tertiaryInk)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .offset(x: expanded || hovering ? 2 : 0)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.layout, value: expanded)
        .animation(WeiBeiMotion.hover, value: hovering)
    }

    private var rowBackground: Color {
        if expanded { return WeiBeiTheme.paperInset.opacity(0.70) }
        if hovering { return WeiBeiTheme.paperInset.opacity(0.30) }
        return .clear
    }

    private var accent: Color {
        sidebarCourseAccent(colorIndex: course.colorIndex)
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
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 21, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            TextField(store.ui("课程名", "Course title"), text: $title)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .font(.system(size: 13))
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
            .font(.system(size: compact ? 12.5 : 13, weight: .medium))
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
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8))
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
                    .font(.system(size: compact ? 12.5 : 13, weight: compact ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(item.subtitle)
                    .font(compact ? .system(size: 10.5) : .caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                if !compact, !tags.isEmpty {
                    Text(tags.prefix(3).joined(separator: " "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, compact ? 7 : 9)
        .frame(height: compact ? 38 : (tags.isEmpty ? 48 : 58))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .offset(x: selected || hovering ? (compact ? 1 : 2) : 0)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8))
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

    private var rowBackground: Color {
        if selected { return WeiBeiTheme.paperInset.opacity(compact ? 0.54 : 0.70) }
        if hovering { return WeiBeiTheme.paperInset.opacity(compact ? 0.22 : 0.30) }
        return .clear
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
