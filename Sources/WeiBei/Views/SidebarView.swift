import SwiftUI
import WeiBeiCore

struct SidebarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var librarySearchFocused: Bool
    @State private var courseEntryPresentation: CourseProjectEntryPresentation?
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
                            store.presentCourseWorkspace(.hub)
                        } label: {
                            HStack(spacing: 3) {
                                Text(store.ui("课程空间", "Course Space"))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(store.ui("打开课程空间", "Open course space")))
                        .help(store.ui("打开课程空间", "Open course space"))
                    }
                    Spacer()
                    Button {
                        courseEntryPresentation = CourseProjectEntryPresentation(intent: .create)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle())
                    .accessibilityLabel(Text(store.ui("添加课程", "Add course")))
                    .help(store.ui("新建或纳入课程", "Create or add a course"))
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
                    sidebarSection(title: store.ui("独立资料", "Unassigned Materials"), items: unassignedMaterials)
                    sidebarSection(title: store.ui("独立笔记", "Unassigned Notes"), items: unassignedNotes)
                    sidebarSection(title: store.ui("内置示例", "Built-in Examples"), items: sampleItems)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            // Solid fill only — animating ultraThinMaterial on open/close was expensive.
            .background(WeiBeiTheme.paperRaised.opacity(0.72))
        }
        .weibeiPanel()
        .onChange(of: store.focusRequest) { _, _ in
            librarySearchFocused = store.focusedPane == .library
        }
        .onAppear {
            librarySearchFocused = store.focusedPane == .library
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

    private var unassignedNotes: [StudyItem] {
        notebookItems.filter { store.courseIDs(for: $0.id).isEmpty }
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
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Button {
                                // Local reveal only — layout spring was animating the whole app shell.
                                withAnimation(WeiBeiMotion.reveal) {
                                    store.activateCourse(store.activeCourseID == course.id ? nil : course.id)
                                }
                            } label: {
                                SidebarCourseRow(
                                    course: course,
                                    materialCount: store.courseMaterials(in: course.id).count,
                                    noteCount: store.courseNotes(in: course.id).count,
                                    expanded: store.activeCourseID == course.id
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text(store.activeCourseID == course.id ? store.ui("收起课程内容", "Collapse course contents") : store.ui("展开课程内容", "Expand course contents")))

                            Button {
                                store.openCourseSpace(course.id)
                            } label: {
                                Text(store.ui("进入", "Enter"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.88))
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .background(WeiBeiTheme.cinnabarSoft.opacity(0.42), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(store.ui("进入课程空间", "Enter course space"))
                            .accessibilityLabel(Text(store.ui("进入课程空间", "Enter course space")))
                        }
                        .contextMenu {
                            Button(store.ui("进入课程空间", "Enter course space")) {
                                store.openCourseSpace(course.id)
                            }
                            Button(store.ui("重命名课程", "Rename course")) {
                                renameCourseTitle = course.title
                                courseToRename = course
                            }
                            Button(store.ui("删除课程", "Delete course"), role: .destructive) {
                                coursePendingDeletion = course
                            }
                        }

                        if store.activeCourseID == course.id {
                            courseContents(for: course)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
    }

    private func courseContents(for course: Course) -> some View {
        let accent = sidebarCourseAccent(colorIndex: course.colorIndex)
        return HStack(alignment: .top, spacing: 0) {
            LinearGradient(
                colors: [accent.opacity(0.34), accent.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1)
            .padding(.leading, 9)
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 9) {
                courseItemGroup(
                    title: store.ui("资料", "Materials"),
                    systemImage: "doc.text",
                    items: materials(in: course.id),
                    emptyTitle: store.ui("暂无资料", "No materials"),
                    accent: accent
                )
                courseItemGroup(
                    title: store.ui("笔记", "Notes"),
                    systemImage: "note.text",
                    items: notes(in: course.id),
                    emptyTitle: store.ui("暂无笔记", "No notes"),
                    accent: accent
                )
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 2)
        .padding(.top, 3)
        .padding(.bottom, 9)
    }

    private func courseItemGroup(
        title: String,
        systemImage: String,
        items: [StudyItem],
        emptyTitle: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.74))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 4)
                Text("\(items.count)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .frame(height: 18)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent.opacity(0.30))
                    .frame(width: 10, height: 1)
                    .offset(x: -13)
            }

            if items.isEmpty {
                Text(emptyTitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.78))
                    .padding(.leading, 2)
                    .frame(height: 26, alignment: .leading)
            } else {
                ForEach(items) { item in
                    sidebarItemRow(item, compact: true, accent: accent)
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
                    sidebarItemRow(item, compact: false, accent: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarItemRow(_ item: StudyItem, compact: Bool, accent: Color?) -> some View {
        let selected = item.isNotebookNote ? store.activeNotebookItemID == item.id : store.selectedItemID == item.id
        if store.notebookRenameDraft?.itemID == item.id {
            NotebookRenameRow(item: item, selected: selected, compact: compact, accent: accent ?? WeiBeiTheme.cinnabar)
                .transition(WeiBeiTransition.message)
        } else {
            Button {
                withAnimation(WeiBeiMotion.micro) {
                    open(item)
                }
            } label: {
                LibraryRow(item: item, selected: selected, compact: compact, accent: accent)
            }
            .buttonStyle(.plain)
            .contextMenu {
                itemContextMenu(for: item)
            }
            .transition(WeiBeiTransition.message)
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: StudyItem) -> some View {
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
    let expanded: Bool
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
                Text(store.ui("\(materialCount) 份资料 · \(noteCount) 份笔记", "\(materialCount) materials · \(noteCount) notes"))
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
        .overlay(alignment: .leading) {
            if expanded {
                Capsule()
                    .fill(WeiBeiTheme.hairline.opacity(0.72))
                    .frame(width: 1, height: 20)
                    .padding(.leading, 3)
            }
        }
        .weibeiHoverLift(active: hovering && !expanded, amount: 1)
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

private func sidebarCourseAccent(colorIndex: Int) -> Color {
    switch ((colorIndex % 4) + 4) % 4 {
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
    var compact: Bool
    var accent: Color
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
        HStack(spacing: compact ? 7 : 8) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(accent.opacity(0.78))
                .frame(width: compact ? 15 : 18)

            TextField(
                "",
                text: title,
                prompt: Text(store.ui("笔记名", "Note title"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .focused($focused)
            .font(.system(size: compact ? 12.5 : 13, weight: .medium))
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
        .padding(.horizontal, compact ? 7 : 9)
        .frame(height: compact ? 38 : 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperInset.opacity(selected ? 0.74 : 0.44))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 8))
        .onAppear {
            focused = true
        }
    }
}

private struct LibraryRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    var item: StudyItem
    var selected: Bool
    var compact: Bool
    var accent: Color?
    @State private var hovering = false

    private var tags: [String] {
        store.displayTags(for: item)
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(iconColor)
                .frame(width: compact ? 15 : 18)
                .scaleEffect(selected || hovering ? 1.08 : 1)
                .opacity(selected || hovering ? 1 : 0.78)

            VStack(alignment: .leading, spacing: compact ? 1 : 2) {
                Text(store.displayTitle(for: item))
                    .font(.system(size: compact ? 12.5 : 13, weight: compact ? .medium : .regular))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.displaySubtitle(for: item))
                    .font(compact ? .system(size: 10.5) : .caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                if !compact, !tags.isEmpty {
                    Text(tags.joined(separator: " "))
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
