import Foundation
import SwiftUI
import WeiBeiCore

enum CourseWorkspacePage: String, CaseIterable, Identifiable {
    case hub
    case relations
    case records

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .hub:
            language.text("课程首页", "Course Home")
        case .relations:
            language.text("关系台", "Relations")
        case .records:
            language.text("学习记录", "Learning Records")
        }
    }
}

enum CourseRelationLens: String, CaseIterable, Identifiable {
    case notes
    case materials

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .notes:
            language.text("笔记", "Notes")
        case .materials:
            language.text("资料", "Materials")
        }
    }
}

struct CourseWorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var page: CourseWorkspacePage = .hub
    @State private var relationLens: CourseRelationLens = .notes
    @State private var selectedNoteID: String?
    @State private var selectedMaterialID: String?
    @State private var selectedSessionID: UUID?
    @State private var search = ""
    @State private var newNoteTitle = ""
    @State private var newNoteError: String?
    @State private var showsNewNotePrompt = false
    @State private var courseManagementPresentation:
        CourseManagementPresentation?
    @State private var coursePendingRemoval: Course?
    @State private var courseRemovalError: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                CourseWorkspaceHeader(
                    page: $page,
                    search: $search,
                    searchFocused: $searchFocused,
                    isCompact: geometry.size.width < 900,
                    dismiss: store.dismissCourseWorkspace,
                    importMaterials: {
                        store.importCourseMaterialsFromPanel(
                            courseID: store.courseWorkspaceCourseID
                        )
                    },
                    importNotes: {
                        store.importCourseNotesFromPanel(
                            courseID: store.courseWorkspaceCourseID
                        )
                    },
                    createNote: promptForNewNote,
                    manageCourse: presentCourseSettings,
                    requestCourseRemoval:
                        presentCourseRemovalConfirmation
                )

                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.72))
                    .frame(height: 1)

                pageContent(size: geometry.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(WeiBeiTheme.paper)
            .foregroundStyle(WeiBeiTheme.ink)
            .background {
                EscapeKeyBridge(
                    isEnabled: !showsNewNotePrompt
                ) {
                    store.dismissCourseWorkspace()
                }
            }
        }
        .onAppear(perform: prepareInitialRoute)
        .onAppear {
        }
        .onChange(of: page) { _, _ in
            search = ""
        }
        .onChange(of: store.courseWorkspaceCourseID) { _, newCourseID in
            selectedMaterialID = newCourseID.flatMap { store.courseMaterials(in: $0).first?.id }
            selectedNoteID = nil
            selectedSessionID = nil
        }
        .sheet(isPresented: $showsNewNotePrompt) {
            CourseNewNoteSheet(
                title: $newNoteTitle,
                error: newNoteError,
                cancel: { showsNewNotePrompt = false },
                create: createNewNote
            )
            .environmentObject(store)
        }
        .sheet(item: $courseManagementPresentation) {
            presentation in
            CourseManagementSheet(
                courseID: presentation.courseID
            )
            .environmentObject(store)
        }
        .confirmationDialog(
            store.ui(
                "从魏碑移除这门课程？",
                "Remove this course from WeiBei?"
            ),
            isPresented: Binding(
                get: { coursePendingRemoval != nil },
                set: {
                    if !$0 { coursePendingRemoval = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: coursePendingRemoval
        ) { course in
            Button(store.ui(
                "从魏碑移除“\(course.title)”",
                "Remove “\(course.title)” from WeiBei"
            )) {
                removeCourseFromWeiBei(course)
            }
            Button(
                store.ui("取消", "Cancel"),
                role: .cancel
            ) {
                coursePendingRemoval = nil
            }
        } message: { _ in
            Text(store.ui(
                "只会从魏碑中移除这门课程。资料、笔记原文件和 Chat 都会保留，不会移到废纸篓。",
                "This only removes the course from WeiBei. Material files, note files, and Chats are kept and are not moved to Trash."
            ))
        }
        .alert(
            store.ui("无法移除课程", "Could Not Remove Course"),
            isPresented: Binding(
                get: { courseRemovalError != nil },
                set: {
                    if !$0 { courseRemovalError = nil }
                }
            )
        ) {
            Button(store.ui("好", "OK"), role: .cancel) {}
        } message: {
            Text(courseRemovalError ?? "")
        }
    }

    @ViewBuilder
    private func pageContent(size: CGSize) -> some View {
        switch page {
        case .hub:
            CourseHubView(
                search: search,
                selectedMaterialID: $selectedMaterialID,
                selectedNoteID: $selectedNoteID,
                selectedSessionID: $selectedSessionID,
                isCompact: size.width < 960,
                openRelations: {
                    withAnimation(WeiBeiMotion.panel) { page = .relations }
                },
                openRecords: {
                    withAnimation(WeiBeiMotion.panel) { page = .records }
                },
                importMaterials: {
                    store.importCourseMaterialsFromPanel(
                        courseID: store.courseWorkspaceCourseID
                    )
                },
                importNotes: {
                    store.importCourseNotesFromPanel(
                        courseID: store.courseWorkspaceCourseID
                    )
                },
                createNote: promptForNewNote
            )
        case .relations:
            CourseRelationsView(
                lens: $relationLens,
                search: search,
                selectedNoteID: $selectedNoteID,
                selectedMaterialID: $selectedMaterialID,
                isCompact: size.width < 900
            )
        case .records:
            CourseRecordsView(
                search: search,
                selectedSessionID: $selectedSessionID,
                isCompact: size.width < 900
            )
        }
    }

    private func promptForNewNote() {
        newNoteTitle = store.ui("新笔记", "New Note")
        newNoteError = nil
        store.noteFileError = nil
        showsNewNotePrompt = true
    }

    private func presentCourseSettings() {
        guard let courseID = store.courseWorkspaceCourseID else {
            return
        }
        courseManagementPresentation =
            CourseManagementPresentation(courseID: courseID)
    }

    private func presentCourseRemovalConfirmation() {
        coursePendingRemoval = store.courseWorkspaceCourse
    }

    private func removeCourseFromWeiBei(_ course: Course) {
        coursePendingRemoval = nil
        Task { @MainActor in
            do {
                try await store.removeCourseFromWeiBei(course.id)
            } catch {
                courseRemovalError = error.localizedDescription
            }
        }
    }

    private func createNewNote() {
        guard let courseID = store.courseWorkspaceCourseID else {
            newNoteError = store.ui("无法新建笔记。", "Could not create the note.")
            return
        }
        Task { @MainActor in
            guard let noteID = await store.createCourseNotebookNote(
                courseID: courseID,
                title: newNoteTitle
            ) else {
                newNoteError = store.noteFileError
                    ?? store.ui("无法新建笔记。", "Could not create the note.")
                return
            }
            selectedNoteID = noteID
            page = .hub
            showsNewNotePrompt = false
        }
    }

    private func prepareInitialRoute() {
        switch store.courseWorkspaceDestination {
        case .hub:
            page = .hub
            selectedMaterialID = store.courseWorkspaceTargetItemID
                ?? store.courseWorkspaceCourseID.flatMap {
                    store.courseMaterials(in: $0).first?.id
                }
        case .relations:
            page = .relations
        case .materials:
            relationLens = .materials
            selectedMaterialID = store.courseWorkspaceTargetItemID
                ?? store.courseWorkspaceCourseID.flatMap {
                    store.courseMaterials(in: $0).first?.id
                }
            page = .relations
        case .notes:
            relationLens = .notes
            selectedNoteID = store.courseWorkspaceTargetItemID
                ?? store.courseWorkspaceCourseID.flatMap {
                    store.courseNotes(in: $0).first?.id
                }
            page = .relations
        case .sessions:
            if let rawID = store.courseWorkspaceTargetItemID {
                selectedSessionID = UUID(uuidString: rawID)
            }
            selectedSessionID = selectedSessionID
                ?? store.courseWorkspaceCourseID.flatMap {
                    store.sessionsTouchingCourse($0).first?.id
                }
            page = .records
        }
    }

}

private struct CourseNewNoteSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var title: String
    let error: String?
    let cancel: () -> Void
    let create: () -> Void

    private var cleanedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.ui("新建课程笔记", "New course note"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 20, weight: .semibold))
                Text(store.ui("新笔记会写入当前课程文件夹里的“笔记”目录。", "The note will be written to the Notes folder inside this course."))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            TextField(store.ui("笔记名称", "Note name"), text: $title)
                .textFieldStyle(.roundedBorder)

            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeiBeiTheme.cinnabar)
            }

            HStack {
                Spacer()
                Button(store.ui("取消", "Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(store.ui("新建", "Create"), action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanedTitle.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(WeiBeiTheme.paper)
    }
}

struct CourseWorkspaceHeader: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var page: CourseWorkspacePage
    @Binding var search: String
    var searchFocused: FocusState<Bool>.Binding
    let isCompact: Bool
    let dismiss: () -> Void
    let importMaterials: () -> Void
    let importNotes: () -> Void
    let createNote: () -> Void
    let manageCourse: () -> Void
    let requestCourseRemoval: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: dismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(store.ui("返回工作台", "Back to workspace"))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(store.ui("关闭课程空间并返回工作台", "Close course space")))

            hubTitleBlock
            .frame(minWidth: isCompact ? 96 : 120, alignment: .leading)

            if isCompact {
                Menu {
                    ForEach(CourseWorkspacePage.allCases) { candidate in
                        Button(candidate.label(language: store.interfaceLanguage)) {
                            page = candidate
                        }
                    }
                } label: {
                    Label(page.label(language: store.interfaceLanguage), systemImage: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                HStack(spacing: 22) {
                    ForEach(CourseWorkspacePage.allCases) { candidate in
                        CourseWorkspaceTab(
                            title: candidate.label(language: store.interfaceLanguage),
                            active: candidate == page
                        ) {
                            withAnimation(WeiBeiMotion.panel) {
                                page = candidate
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            if let saveError = store.workspaceSaveError {
                Button(action: { _ = store.retryWorkspaceSave() }) {
                    Label(store.ui("保存失败，点此重试", "Save failed, retry"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                }
                .buttonStyle(.plain)
                .help(saveError)
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                TextField(searchPrompt, text: $search)
                    .textFieldStyle(.plain)
                    .focused(searchFocused)
                    .font(.system(size: 12))
            }
            .weibeiInputSurface(active: searchFocused.wrappedValue, height: 30)
            .frame(width: isCompact ? 160 : 220)

            Menu {
                Button(action: importMaterials) {
                    Label(store.ui("导入资料", "Import materials"), systemImage: "doc.badge.plus")
                }
                Button(action: importNotes) {
                    Label(store.ui("导入 Markdown 笔记", "Import Markdown notes"), systemImage: "note.text.badge.plus")
                }
                Divider()
                Button(action: createNote) {
                    Label(store.ui("新建笔记", "New note"), systemImage: "square.and.pencil")
                }
            } label: {
                Label(store.ui("添加", "Add"), systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(WeiBeiTheme.paperInset.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(store.ui("添加文稿或笔记", "Add materials or notes"))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.88, materialOpacity: 0.05))
    }

    private var searchPrompt: String {
        switch page {
        case .hub:
            store.ui("搜索本课文稿、对话与笔记", "Search this course")
        case .relations:
            store.ui("搜索工作区资料与笔记", "Search workspace materials and notes")
        case .records:
            store.ui("搜索学习记录", "Search learning records")
        }
    }

    private var hubTitleBlock: some View {
        Menu {
            if store.courses.isEmpty {
                Text(store.ui("还没有课程", "No courses yet"))
            } else {
                ForEach(store.courses) { course in
                    Button {
                        store.selectCourseWorkspaceCourse(course.id)
                        page = .hub
                    } label: {
                        if course.id == store.courseWorkspaceCourseID {
                            Label(course.title, systemImage: "checkmark")
                        } else {
                            Text(course.title)
                        }
                    }
                }
            }
            if store.courseWorkspaceCourse != nil {
                Divider()
                Button(
                    store.ui(
                        "课程设置…",
                        "Course Settings…"
                    ),
                    action: manageCourse
                )
                Button(
                    store.ui(
                        "从魏碑移除…",
                        "Remove from WeiBei…"
                    ),
                    action: requestCourseRemoval
                )
            }
        } label: {
            HStack(spacing: 6) {
                Text(hubCourseTitle)
                    .font(courseTitleDisplayFont(hubCourseTitle, size: 20))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden) // system pull-down chevron + our own would double up
        .help(store.ui(
            "选择或管理课程",
            "Choose or manage a course"
        ))
        .accessibilityLabel(Text(store.ui(
            "课程菜单",
            "Course menu"
        )))
    }

    private var hubCourseTitle: String {
        if let course = store.courseWorkspaceCourse {
            return course.title
        }
        return store.ui("选择课程", "Select course")
    }
}

struct CourseWorkspaceTab: View {
    @EnvironmentObject private var store: WorkspaceStore
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 12.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 8)
                .frame(height: 40)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(active ? WeiBeiTheme.cinnabar : Color.clear)
                        .frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
