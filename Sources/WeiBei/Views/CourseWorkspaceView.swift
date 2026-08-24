import Foundation
import SwiftUI
import WeiBeiCore

enum CourseWorkspacePage: String, CaseIterable, Identifiable {
    case hub
    case map
    case records
    case memory

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .hub:
            language.text("概览", "Overview")
        case .map:
            language.text("文稿与笔记", "Docs & Notes")
        case .records:
            language.text("对话", "Conversations")
        case .memory:
            language.text("课程记忆", "Course Memory")
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
            language.text("文稿", "Docs")
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
    @State private var coursePendingDeletion: Course?
    @State private var courseDeletionError: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                CourseWorkspaceHeader(
                    page: $page,
                    search: $search,
                    searchFocused: $searchFocused,
                    isCompact: geometry.size.width < 980,
                    dismiss: store.dismissCourseWorkspace,
                    manageCourse: presentCourseSettings,
                    requestCourseDeletion:
                        presentCourseDeletionConfirmation
                )

                if store.isCourseLibraryRootVolatile {
                    CourseLibraryVolatilityBanner()
                }

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
                "删除这门课程？",
                "Delete this course?"
            ),
            isPresented: Binding(
                get: { coursePendingDeletion != nil },
                set: {
                    if !$0 { coursePendingDeletion = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: coursePendingDeletion
        ) { course in
            Button(role: .destructive) {
                deleteCourse(course)
            } label: {
                Text(store.ui(
                    "删除“\(course.title)”",
                    "Delete “\(course.title)”"
                ))
            }
            Button(
                store.ui("取消", "Cancel"),
                role: .cancel
            ) {
                coursePendingDeletion = nil
            }
        } message: { course in
            Text(courseDeletionMessage(for: course))
        }
        .alert(
            store.ui("无法删除课程", "Could Not Delete Course"),
            isPresented: Binding(
                get: { courseDeletionError != nil },
                set: {
                    if !$0 { courseDeletionError = nil }
                }
            )
        ) {
            Button(store.ui("好", "OK"), role: .cancel) {}
        } message: {
            Text(courseDeletionError ?? "")
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
                    page = .map
                },
                openRecords: {
                    page = .records
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
        case .map:
            CourseRelationsView(
                lens: $relationLens,
                search: search,
                selectedNoteID: $selectedNoteID,
                selectedMaterialID: $selectedMaterialID,
                showsGraph: true,
                isCompact: size.width < 900,
                createNote: promptForNewNote
            )
        case .records:
            CourseRecordsView(
                search: search,
                selectedSessionID: $selectedSessionID,
                isCompact: size.width < 900
            )
        case .memory:
            CourseMemoryWorkspaceView(search: search)
        }
    }

    private func promptForNewNote() {
        newNoteTitle = store.ui("新笔记", "New Note")
        newNoteError = nil
        // S5：无 noteFileError 通道。
        showsNewNotePrompt = true
    }

    private func presentCourseSettings() {
        guard let courseID = store.courseWorkspaceCourseID else {
            return
        }
        courseManagementPresentation =
            CourseManagementPresentation(courseID: courseID)
    }

    private func presentCourseDeletionConfirmation() {
        coursePendingDeletion = store.courseWorkspaceCourse
    }

    private func deleteCourse(_ course: Course) {
        coursePendingDeletion = nil
        Task { @MainActor in
            do {
                try await store.deleteCourse(course.id)
            } catch {
                store.recordCourseLibraryUIFailure(
                    error,
                    operation: "delete_course",
                    path: store.courseRootURL(for: course.id)
                )
                courseDeletionError = store.ui(
                    "没有确认删除完成。请先检查课程列表和废纸篓；如果课程仍在魏碑，确认资料库可访问后再重试。",
                    "The deletion was not confirmed. Check the course list and Trash first. If the course is still in WeiBei, make sure the library is accessible before trying again."
                )
            }
        }
    }

    private func courseDeletionMessage(for course: Course) -> String {
        guard let root = store.courseRootURL(for: course.id) else {
            if store.courseHasNeverHadFolder(course.id) {
                return store.ui(
                    "这门旧课程从未有课程文件夹。删除会移除课程和全部关系；外部原文件会留在独立资料或笔记中，可从侧边栏分别删除。",
                    "This legacy course never had a course folder. Deleting removes the course and all relations; external source files remain as independent materials or notes and can be deleted from the sidebar."
                )
            }
            return store.ui(
                "课程文件夹当前不可访问。请先在 Finder 中把它放到当前魏碑资料库里，再重新打开魏碑。",
                "The course folder is unavailable. WeiBei won’t pretend to delete it; reconnect the real folder with Add Existing Folder first."
            )
        }
        return store.ui(
            "会把整个课程文件夹及其中内容移到 macOS 废纸篓，并从魏碑删除：\n\(root.path)",
            "The entire course folder and its contents will be moved to the macOS Trash and deleted from WeiBei:\n\(root.path)"
        )
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
                newNoteError = store.transientNoteStatus
                    ?? store.ui("无法新建笔记。", "Could not create the note.")
                return
            }
            selectedMaterialID = nil
            selectedNoteID = noteID
            relationLens = .notes
            page = .map
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
            page = .map
        case .materials:
            relationLens = .materials
            selectedMaterialID = store.courseWorkspaceTargetItemID
                ?? store.courseWorkspaceCourseID.flatMap {
                    store.courseMaterials(in: $0).first?.id
                }
            page = .map
        case .notes:
            relationLens = .notes
            selectedNoteID = store.courseWorkspaceTargetItemID
                ?? store.courseWorkspaceCourseID.flatMap {
                    store.courseNotes(in: $0).first?.id
                }
            page = .map
        case .sessions:
            if let rawID = store.courseWorkspaceTargetItemID {
                selectedSessionID = UUID(uuidString: rawID)
            }
            selectedSessionID = selectedSessionID
                ?? store.courseWorkspaceCourseID.flatMap {
                    store.sessionsTouchingCourse($0).first?.id
                }
            page = .records
        case .memory:
            page = .memory
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
                    .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
                Text(store.ui("新笔记会写入当前课程文件夹里的“笔记”目录。", "The note will be written to the Notes folder inside this course."))
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            TextField(store.ui("笔记名称", "Note name"), text: $title)
                .textFieldStyle(.roundedBorder)

            if let error, !error.isEmpty {
                Text(error)
                    .weiBeiText(12)
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
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Binding var page: CourseWorkspacePage
    @Namespace private var tabUnderlineNamespace
    @Binding var search: String
    var searchFocused: FocusState<Bool>.Binding
    let isCompact: Bool
    let dismiss: () -> Void
    let manageCourse: () -> Void
    let requestCourseDeletion: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: dismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(store.ui("返回工作台", "Back to workspace"))
                }
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(store.ui("关闭课程空间并返回工作台", "Close course space")))

            HStack(spacing: 8) {
                hubTitleBlock

                if isCompact {
                    Menu {
                        ForEach(CourseWorkspacePage.allCases) { candidate in
                            Button(candidate.label(language: store.interfaceLanguage)) {
                                page = candidate
                            }
                        }
                    } label: {
                        Label(page.label(language: store.interfaceLanguage), systemImage: "chevron.down")
                            .weiBeiText(12, weight: .semibold)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    HStack(spacing: 22) {
                        ForEach(CourseWorkspacePage.allCases) { candidate in
                            CourseWorkspaceTab(
                                title: candidate.label(language: store.interfaceLanguage),
                                active: candidate == page,
                                underlineNamespace: tabUnderlineNamespace
                            ) {
                                page = candidate
                            }
                        }
                    }
                    // The ONLY animated piece of a page switch: the shared cinnabar
                    // underline sliding across the tab strip. Page content swaps
                    // immediately — no panel bounce anywhere.
                    .animation(
                        reduceMotion ? nil : WeiBeiMotion.tabUnderline,
                        value: page
                    )
                }
            }

            Spacer(minLength: 12)

            if let saveError = store.workspaceSaveError {
                Button(action: { _ = store.retryWorkspaceSave() }) {
                    Label(store.ui("保存失败，点此重试", "Save failed, retry"), systemImage: "exclamationmark.triangle")
                        .weiBeiText(10.5, weight: .medium)
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
                    .weiBeiText(12)
            }
            .weibeiInputSurface(active: searchFocused.wrappedValue, height: 30)
            .frame(width: isCompact ? 160 : 220)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.88, materialOpacity: 0.05))
    }

    private var searchPrompt: String {
        switch page {
        case .hub:
            store.ui("搜索本课", "Search this course")
        case .map:
            store.ui("搜索本课文稿与笔记", "Search Docs and Notes in this course")
        case .records:
            store.ui("搜索本课对话", "Search Chats in this course")
        case .memory:
            store.ui("搜索课程记忆", "Search Course Memory")
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
                Button(role: .destructive) {
                    requestCourseDeletion()
                } label: {
                    Text(store.ui("删除课程…", "Delete Course…"))
                }
            }
        } label: {
            CourseSwitchCapsule(title: hubCourseTitle)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(store.ui(
            "选择课程",
            "Choose a course"
        ))
        .accessibilityLabel(Text(store.ui(
            "当前课程 \(hubCourseTitle)，点按以切换",
            "Current course \(hubCourseTitle), click to switch"
        )))
    }

    private var hubCourseTitle: String {
        if let course = store.courseWorkspaceCourse {
            return course.title
        }
        return store.ui("选择课程", "Select course")
    }
}

private struct CourseSwitchCapsule: View {
    let title: String
    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(courseTitleDisplayFont(title, size: 12, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: WeiBeiMetric.inputHeight)
            .background(
                WeiBeiTheme.paperRaised.opacity(hovering ? 0.90 : 0.68),
                in: RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius, style: .continuous)
                    .stroke(
                        WeiBeiTheme.hairline.opacity(hovering ? 0.80 : 0.48),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

struct CourseWorkspaceTab: View {
    @EnvironmentObject private var store: WorkspaceStore
    let title: String
    let active: Bool
    var underlineNamespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .weiBeiBrandFont(language: store.interfaceLanguage, size: 12, weight: active ? .semibold : .medium)
                .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 8)
                .frame(height: 40)
                .overlay(alignment: .bottom) {
                    // One shared underline (matched geometry) — it slides between
                    // tabs instead of each tab fading its own marker in and out.
                    if active {
                        Rectangle()
                            .fill(WeiBeiTheme.cinnabar)
                            .frame(height: 2)
                            .matchedGeometryEffect(
                                id: "course-workspace-tab-underline",
                                in: underlineNamespace
                            )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
