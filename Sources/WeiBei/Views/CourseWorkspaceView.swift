import Foundation
import SwiftUI
import WeiBeiCore

enum CourseWorkspacePage: String, CaseIterable, Identifiable {
    case overview
    case relations
    case records

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .overview:
            language.text("概览", "Overview")
        case .relations:
            language.text("课程内容", "Course Content")
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
    @State private var page: CourseWorkspacePage = .overview
    @State private var relationLens: CourseRelationLens = .notes
    @State private var selectedNoteID: String?
    @State private var selectedMaterialID: String?
    @State private var selectedSessionID: UUID?
    @State private var search = ""
    @State private var newNoteTitle = ""
    @State private var newNoteError: String?
    @State private var showsNewNotePrompt = false
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
                    importCourseFolder: store.prepareCourseFolderImportFromPanel,
                    importMaterials: store.importCourseMaterialsFromPanel,
                    importNotes: store.importCourseNotesFromPanel,
                    createNote: promptForNewNote
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
                    isEnabled: !showsNewNotePrompt && store.courseFolderImportDraft == nil
                ) {
                    store.dismissCourseWorkspace()
                }
            }
        }
        .onAppear(perform: prepareInitialRoute)
        .onChange(of: page) { _, _ in
            search = ""
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
        .sheet(item: $store.courseFolderImportDraft) { draft in
            CourseFolderImportSheet(
                draft: draft,
                cancel: { store.courseFolderImportDraft = nil },
                confirm: { notePaths in
                    store.importCourseFolder(draft, notePaths: notePaths)
                    if store.workspaceSaveError == nil {
                        store.courseFolderImportDraft = nil
                    }
                }
            )
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private func pageContent(size: CGSize) -> some View {
        switch page {
        case .overview:
            CourseOverviewView(
                showUnlinkedNotes: {
                    relationLens = .notes
                    selectedNoteID = store.courseNotesWithoutSourceLinks.first?.id
                    page = .relations
                },
                showUnlinkedMaterials: {
                    relationLens = .materials
                    selectedMaterialID = store.courseMaterialsWithoutNoteLinks.first?.id
                    page = .relations
                },
                showMaterialsWithoutReadingPosition: {
                    relationLens = .materials
                    selectedMaterialID = store.courseMaterialsWithoutReadingPosition.first?.id
                    page = .relations
                },
                showRecords: { sessionID in
                    selectedSessionID = sessionID ?? store.recentCourseSessions.first?.id
                    page = .records
                }
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

    private func createNewNote() {
        guard let noteID = store.createCourseNotebookNote(title: newNoteTitle) else {
            newNoteError = store.noteFileError ?? store.ui("无法新建笔记。", "Could not create the note.")
            return
        }
        selectedNoteID = noteID
        relationLens = .notes
        page = .relations
        showsNewNotePrompt = false
    }

    private func prepareInitialRoute() {
        switch store.courseWorkspaceDestination {
        case .overview:
            page = .overview
        case .materials:
            relationLens = .materials
            selectedMaterialID = store.courseWorkspaceTargetItemID ?? store.courseMaterials.first?.id
            page = .relations
        case .notes:
            relationLens = .notes
            selectedNoteID = store.courseWorkspaceTargetItemID ?? store.courseNotebookItems.first?.id
            page = .relations
        case .sessions:
            if let rawID = store.courseWorkspaceTargetItemID {
                selectedSessionID = UUID(uuidString: rawID)
            }
            selectedSessionID = selectedSessionID ?? store.recentCourseSessions.first?.id
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
                Text(store.ui("新笔记会进入课程首页，并保存到本地笔记目录。", "The note will appear in the course home and save locally."))
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

private struct CourseFolderImportSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    let draft: CourseFolderImportDraft
    let cancel: () -> Void
    let confirm: (Set<String>) -> Void
    @State private var notePaths: Set<String>

    init(
        draft: CourseFolderImportDraft,
        cancel: @escaping () -> Void,
        confirm: @escaping (Set<String>) -> Void
    ) {
        self.draft = draft
        self.cancel = cancel
        self.confirm = confirm
        _notePaths = State(initialValue: draft.notePaths)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.ui("确认 Markdown 的角色", "Classify Markdown files"))
                        .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 20, weight: .semibold))
                    Text(store.ui(
                        "其他文件已经按资料处理。这里只需确认 Markdown 是课程资料还是笔记。",
                        "Other files are already materials. Only classify each Markdown file as material or note."
                    ))
                        .font(.system(size: 12))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                Spacer()
                Menu(store.ui("批量设置", "Set all")) {
                    Button(store.ui("全部作为资料", "All as materials")) { notePaths.removeAll() }
                    Button(store.ui("全部作为笔记", "All as notes")) {
                        notePaths = Set(draft.markdownFiles.map(\.path))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(22)

            CourseHairline()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(draft.markdownFiles, id: \.path) { url in
                        HStack(spacing: 14) {
                            Image(systemName: "doc.richtext")
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(relativeFolderLabel(for: url))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .help(url.path)
                            Spacer()
                            Picker("", selection: roleBinding(for: url)) {
                                Text(store.ui("资料", "Material")).tag(false)
                                Text(store.ui("笔记", "Note")).tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .tint(WeiBeiTheme.cinnabar)
                            .frame(width: 150)
                            .accessibilityLabel(Text(store.ui(
                                "\(url.deletingPathExtension().lastPathComponent) 的角色",
                                "Role for \(url.deletingPathExtension().lastPathComponent)"
                            )))
                        }
                        .padding(.horizontal, 22)
                        .frame(minHeight: 58)
                        CourseHairline()
                    }
                }
            }

            HStack {
                if let error = store.workspaceSaveError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .lineLimit(2)
                    Button(store.ui("重试保存", "Retry save")) {
                        if store.retryWorkspaceSave() {
                            store.courseFolderImportDraft = nil
                        }
                    }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                } else {
                    let materialCount = draft.automaticMaterialCount + draft.markdownFiles.count - notePaths.count
                    Text(store.ui(
                        "\(materialCount) 份资料 · \(notePaths.count) 份笔记",
                        "\(materialCount) materials · \(notePaths.count) notes"
                    ))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                Spacer()
                Button(store.ui("取消", "Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(store.ui("添加到课程", "Add to course")) { confirm(notePaths) }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .frame(height: 54)
        }
        .frame(width: 680, height: sheetHeight)
        .background(WeiBeiTheme.paper)
    }

    private var sheetHeight: CGFloat {
        min(560, max(360, CGFloat(220 + draft.markdownFiles.count * 58)))
    }

    private func relativeFolderLabel(for url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        guard let root = draft.rootURLs.first?.standardizedFileURL else {
            return folder.lastPathComponent
        }
        if folder == root {
            return store.ui("课程根目录", "Course root")
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if folder.path.hasPrefix(rootPrefix) {
            return String(folder.path.dropFirst(rootPrefix.count))
        }
        return folder.lastPathComponent
    }

    private func roleBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { notePaths.contains(url.path) },
            set: { isNote in
                if isNote {
                    notePaths.insert(url.path)
                } else {
                    notePaths.remove(url.path)
                }
            }
        )
    }
}

struct CourseWorkspaceHeader: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var page: CourseWorkspacePage
    @Binding var search: String
    var searchFocused: FocusState<Bool>.Binding
    let isCompact: Bool
    let dismiss: () -> Void
    let importCourseFolder: () -> Void
    let importMaterials: () -> Void
    let importNotes: () -> Void
    let createNote: () -> Void

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
            .accessibilityLabel(Text(store.ui("关闭课程首页并返回工作台", "Close course home")))

            VStack(alignment: .leading, spacing: 0) {
                Text(store.ui("课程首页", "Course Home"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 20, weight: .semibold))
                Text(store.interfaceLanguage == .chinese ? "COURSE HOME" : "WEIBEI")
                    .font(WeiBeiTypography.englishBrandFont(size: 8.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.74))
            }
            .frame(width: isCompact ? 122 : 148, alignment: .leading)

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

            if page != .overview {
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
            }

            Menu {
                Button(action: importCourseFolder) {
                    Label(store.ui("导入课程文件夹", "Import course folder"), systemImage: "folder.badge.plus")
                }
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
            .help(store.ui("添加课程文件夹、资料或笔记", "Add course folders, materials, or notes"))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.88, materialOpacity: 0.05))
    }

    private var searchPrompt: String {
        switch page {
        case .overview:
            store.ui("搜索课程", "Search course")
        case .relations:
            store.ui("搜索课程内容", "Search course content")
        case .records:
            store.ui("搜索学习记录", "Search learning records")
        }
    }
}

struct CourseWorkspaceTab: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: active ? .semibold : .medium))
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
