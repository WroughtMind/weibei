import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var librarySearchFocused: Bool
    @State private var showsNewCourseSheet = false
    @State private var newCourseTitle = ""
    @State private var courseToRename: Course?
    @State private var renameCourseTitle = ""
    @State private var coursePendingDeletion: Course?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.ui("课程目录", "Course Index"))
                            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 22, weight: .semibold))
                        Button {
                            store.presentCourseWorkspace()
                        } label: {
                            HStack(spacing: 3) {
                                Text(store.ui("课程首页", "Course Home"))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(store.ui("打开课程首页", "Open course home")))
                        .help(store.ui("打开课程首页", "Open course home"))
                    }
                    Spacer()
                    Button { showsNewCourseSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle())
                    .accessibilityLabel(Text(store.ui("新建课程", "Create course")))
                    .help(store.ui("新建课程", "Create course"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                TextField(
                    "",
                    text: $store.librarySearch,
                    prompt: Text(store.ui("搜索课程资料与笔记", "Search course materials and notes"))
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

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    courseSection
                    if let activeCourseID = store.activeCourseID {
                        sidebarSection(title: store.ui("本课资料", "Course Materials"), items: materials(in: activeCourseID))
                        sidebarSection(title: store.ui("本课笔记", "Course Notes"), items: notes(in: activeCourseID))
                    } else {
                        sidebarSection(title: store.ui("独立资料", "Unassigned Materials"), items: unassignedMaterials)
                        sidebarSection(title: store.ui("全部笔记", "All Notes"), items: notebookItems)
                    }
                    sidebarSection(title: store.ui("内置示例", "Built-in Examples"), items: sampleItems)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .background {
                ZStack {
                    WeiBeiTheme.paperRaised.opacity(0.64)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.035)
                }
            }
        }
        .weibeiPanel()
        .onChange(of: store.focusRequest) { _, _ in
            librarySearchFocused = store.focusedPane == .library
        }
        .onAppear {
            librarySearchFocused = store.focusedPane == .library
        }
        .sheet(isPresented: $showsNewCourseSheet) {
            SidebarCourseNameSheet(
                heading: store.ui("新建课程", "Create Course"),
                detail: store.ui("课程只负责归拢资料与笔记，不会移动原文件。", "Courses organize materials and notes without moving files."),
                confirmTitle: store.ui("创建", "Create"),
                title: $newCourseTitle,
                cancel: closeNewCourseSheet,
                confirm: createCourse
            )
            .environmentObject(store)
        }
        .sheet(item: $courseToRename) { course in
            SidebarCourseNameSheet(
                heading: store.ui("重命名课程", "Rename Course"),
                detail: store.ui("只修改显示名称，资料与笔记保持原位。", "Only the display title changes; files stay where they are."),
                confirmTitle: store.ui("保存", "Save"),
                title: $renameCourseTitle,
                cancel: { courseToRename = nil },
                confirm: { renameCourse(course) }
            )
            .environmentObject(store)
        }
        .confirmationDialog(
            store.ui("删除课程？", "Delete course?"),
            isPresented: Binding(
                get: { coursePendingDeletion != nil },
                set: { if !$0 { coursePendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: coursePendingDeletion
        ) { course in
            Button(store.ui("删除“\(course.title)”", "Delete “\(course.title)”"), role: .destructive) {
                store.deleteCourse(course.id)
                coursePendingDeletion = nil
            }
            Button(store.ui("取消", "Cancel"), role: .cancel) {
                coursePendingDeletion = nil
            }
        } message: { _ in
            Text(store.ui("原文件不会删除，只会回到未归属状态。", "Files remain intact and become unassigned."))
        }
    }

    private var filteredItemIDs: Set<String> {
        Set(store.filteredItems.map(\.id))
    }

    private var filteredCourses: [Course] {
        let query = store.librarySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.courses }
        return store.courses.filter { course in
            course.title.localizedCaseInsensitiveContains(query)
                || store.courseItems(in: course.id).contains { filteredItemIDs.contains($0.id) }
        }
    }

    private var sampleItems: [StudyItem] {
        store.sampleItems.filter { filteredItemIDs.contains($0.id) }
    }

    private var unassignedMaterials: [StudyItem] {
        store.unassignedCourseMaterials.filter { filteredItemIDs.contains($0.id) }
    }

    private var notebookItems: [StudyItem] {
        store.filteredItems.filter(\.isNotebookNote)
    }

    private func materials(in courseID: UUID) -> [StudyItem] {
        store.courseMaterials(in: courseID).filter { filteredItemIDs.contains($0.id) }
    }

    private func notes(in courseID: UUID) -> [StudyItem] {
        store.courseNotes(in: courseID).filter { filteredItemIDs.contains($0.id) }
    }

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.ui("课程", "Courses"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .padding(.horizontal, 8)

            if filteredCourses.isEmpty {
                Text(store.ui("还没有匹配课程", "No matching courses"))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.horizontal, 9)
                    .frame(height: 40)
            } else {
                ForEach(filteredCourses) { course in
                    Button {
                        withAnimation(WeiBeiMotion.panel) {
                            store.activateCourse(store.activeCourseID == course.id ? nil : course.id)
                        }
                    } label: {
                        SidebarCourseRow(
                            course: course,
                            materialCount: store.courseMaterials(in: course.id).count,
                            noteCount: store.courseNotes(in: course.id).count,
                            selected: store.activeCourseID == course.id
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(store.ui("重命名课程", "Rename course")) {
                            renameCourseTitle = course.title
                            courseToRename = course
                        }
                        Button(store.ui("删除课程", "Delete course"), role: .destructive) {
                            coursePendingDeletion = course
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarSection(title: String, items: [StudyItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .padding(.horizontal, 8)

                ForEach(items) { item in
                    if store.notebookRenameDraft?.itemID == item.id {
                        NotebookRenameRow(item: item, selected: item.isNotebookNote ? store.activeNotebookItemID == item.id : store.selectedItemID == item.id)
                            .transition(WeiBeiTransition.message)
                    } else {
                        Button {
                            withAnimation(WeiBeiMotion.panel) {
                                open(item)
                            }
                        } label: {
                            LibraryRow(item: item, selected: item.isNotebookNote ? store.activeNotebookItemID == item.id : store.selectedItemID == item.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if item.isNotebookNote {
                                Button(store.ui("重命名笔记", "Rename Note")) {
                                    store.promptRenameNotebookNote(itemID: item.id)
                                }
                            }
                            if !item.isSample, !store.courses.isEmpty {
                                Menu(store.ui("课程归属", "Course membership")) {
                                    ForEach(store.courses) { course in
                                        let assigned = store.courseIDs(for: item.id).contains(course.id)
                                        Button {
                                            var courseIDs = Set(store.courseIDs(for: item.id))
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
                        }
                        .transition(WeiBeiTransition.message)
                    }
                }
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

    private func closeNewCourseSheet() {
        showsNewCourseSheet = false
        newCourseTitle = ""
    }

    private func createCourse() {
        guard let courseID = store.createCourse(title: newCourseTitle) else { return }
        store.activateCourse(courseID)
        closeNewCourseSheet()
    }

    private func renameCourse(_ course: Course) {
        store.renameCourse(course.id, title: renameCourseTitle)
        courseToRename = nil
        renameCourseTitle = ""
    }
}

private struct SidebarCourseRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let course: Course
    let materialCount: Int
    let noteCount: Int
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed")
                .foregroundStyle(accent.opacity(selected || hovering ? 1 : 0.78))
                .frame(width: 18)
                .scaleEffect(selected || hovering ? 1.08 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(course.title)
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.ui("\(materialCount) 份资料 · \(noteCount) 份笔记", "\(materialCount) materials · \(noteCount) notes"))
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .offset(x: selected || hovering ? 2 : 0)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(accent.opacity(0.72))
                    .frame(width: 3, height: 24)
                    .padding(.leading, 2)
            }
        }
        .weibeiHoverLift(active: hovering && !selected, amount: 1)
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.micro, value: selected)
        .animation(WeiBeiMotion.hover, value: hovering)
    }

    private var rowBackground: Color {
        if selected { return WeiBeiTheme.paperInset.opacity(0.70) }
        if hovering { return WeiBeiTheme.paperInset.opacity(0.30) }
        return .clear
    }

    private var accent: Color {
        switch ((course.colorIndex % 4) + 4) % 4 {
        case 0:
            return WeiBeiTheme.cinnabar
        case 1:
            return WeiBeiTheme.moss
        case 2:
            return WeiBeiTheme.link
        default:
            return WeiBeiTheme.secondaryInk
        }
    }
}

private struct SidebarCourseNameSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
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
    @EnvironmentObject private var store: WorkspaceStore
    var item: StudyItem
    var selected: Bool
    @FocusState private var focused: Bool

    private var title: Binding<String> {
        Binding(
            get: { store.notebookRenameDraft?.title ?? "" },
            set: { store.notebookRenameDraft?.title = $0 }
        )
    }

    private var canRename: Bool {
        !title.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                .frame(width: 18)

            TextField(
                "",
                text: title,
                prompt: Text(store.ui("笔记名", "Note title"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(WeiBeiTheme.ink)
            .onSubmit {
                if canRename {
                    store.confirmRenameNotebookNote()
                }
            }

            Button {
                store.cancelRenameNotebookNote()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 20))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(store.ui("取消", "Cancel")))
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperInset.opacity(selected ? 0.74 : 0.44))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(WeiBeiTheme.cinnabar.opacity(canRename ? 0.72 : 0.34))
                .frame(width: 3, height: 24)
                .padding(.leading, 2)
        }
        .onAppear {
            focused = true
        }
    }
}

private struct LibraryRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    var item: StudyItem
    var selected: Bool
    @State private var hovering = false

    private var tags: [String] {
        store.displayTags(for: item)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.kind == .pdf ? WeiBeiTheme.link : WeiBeiTheme.tertiaryInk)
                .frame(width: 18)
                .scaleEffect(selected || hovering ? 1.08 : 1)
                .opacity(selected || hovering ? 1 : 0.78)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayTitle(for: item))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.displaySubtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                if !tags.isEmpty {
                    Text(tags.joined(separator: " "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: tags.isEmpty ? 48 : 58)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .offset(x: selected || hovering ? 2 : 0)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(WeiBeiTheme.cinnabar.opacity(0.72))
                    .frame(width: 3, height: 24)
                    .padding(.leading, 2)
                    .transition(.scale(scale: 0.7, anchor: .center).combined(with: .opacity))
            }
        }
        .weibeiHoverLift(active: hovering && !selected, amount: 1)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.micro) {
                self.hovering = hovering
            }
        }
        .animation(WeiBeiMotion.micro, value: selected)
        .animation(WeiBeiMotion.hover, value: hovering)
    }

    private var rowBackground: Color {
        if selected { return WeiBeiTheme.paperInset.opacity(0.70) }
        if hovering { return WeiBeiTheme.paperInset.opacity(0.30) }
        return .clear
    }
}
