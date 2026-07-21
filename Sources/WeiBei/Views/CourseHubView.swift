import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Course hub: left materials · center conversations · right notes.
struct CourseHubView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let search: String
    @Binding var selectedMaterialID: String?
    @Binding var selectedNoteID: String?
    @Binding var selectedSessionID: UUID?
    let isCompact: Bool
    let openRelations: () -> Void
    let importCourseFolder: () -> Void
    let importMaterials: () -> Void
    let importNotes: () -> Void
    let createNote: () -> Void

    @State private var isMaterialDropTargeted = false
    @State private var isNoteDropTargeted = false

    private var courseID: UUID? { store.activeCourseID }

    private var materials: [StudyItem] {
        guard let courseID else { return [] }
        return filteredItems(store.courseMaterials(in: courseID))
    }

    private var notes: [StudyItem] {
        guard let courseID else { return [] }
        return filteredItems(store.courseNotes(in: courseID))
    }

    private var sessions: [StudySession] {
        guard let courseID else { return [] }
        let base = store.sessionsTouchingCourse(courseID)
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return base }
        return base.filter { session in
            session.title.localizedCaseInsensitiveContains(cleaned)
                || session.summary.localizedCaseInsensitiveContains(cleaned)
                || session.messages.contains { $0.text.localizedCaseInsensitiveContains(cleaned) }
        }
    }

    private var linkedNoteIDs: Set<String> {
        guard let selectedMaterialID else { return [] }
        return Set(store.linkedNoteIDs(for: selectedMaterialID))
    }

    private var linkedSessionIDs: Set<UUID> {
        guard let selectedMaterialID, let courseID else { return [] }
        return Set(store.sessionsTouchingMaterial(selectedMaterialID, in: courseID).map(\.id))
    }

    var body: some View {
        Group {
            if courseID == nil {
                coursePickerEmptyState
            } else if isCompact {
                compactBody
            } else {
                wideBody
            }
        }
        .onAppear {
            if selectedMaterialID == nil {
                selectedMaterialID = materials.first?.id
            }
        }
        .onChange(of: courseID) { _, _ in
            selectedMaterialID = materials.first?.id
            selectedNoteID = nil
            selectedSessionID = nil
        }
    }

    private var coursePickerEmptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.85))

            Text(store.ui("选择一门课程", "Choose a course"))
                .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 20, weight: .semibold))

            Text(store.ui(
                "选课后会打开文稿、对话与笔记三栏。也可从侧边栏点「进入」。",
                "Choosing a course opens materials, conversations, and notes. Sidebar Enter still works."
            ))
            .font(.system(size: 12.5))
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

            if store.courses.isEmpty {
                Text(store.ui("还没有课程，先在侧边栏新建一门。", "No courses yet. Create one in the sidebar."))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            } else {
                Menu {
                    ForEach(store.courses) { course in
                        Button(course.title) {
                            store.activateCourse(course.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(store.ui("选择课程", "Select course"))
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(WeiBeiTheme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(WeiBeiTheme.cinnabarSoft.opacity(0.55), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var wideBody: some View {
        HStack(spacing: 0) {
            hubColumn(
                title: store.ui("文稿", "Materials"),
                countLabel: store.ui("\(materials.count) 份", "\(materials.count)")
            ) {
                materialsColumn
            }

            CourseHairline(axis: .vertical)

            hubColumn(
                title: store.ui("对话记录", "Conversations"),
                countLabel: store.ui("\(sessions.count) 段", "\(sessions.count)")
            ) {
                sessionsColumn
            }

            CourseHairline(axis: .vertical)

            hubColumn(
                title: store.ui("笔记", "Notes"),
                countLabel: store.ui("\(notes.count) 份", "\(notes.count)")
            ) {
                notesColumn
            }
        }
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            materialsColumn
            CourseHairline()
            HStack(spacing: 0) {
                sessionsColumn
                CourseHairline(axis: .vertical)
                notesColumn
            }
            .frame(maxHeight: 280)
        }
    }

    private func hubColumn<Content: View>(
        title: String,
        countLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 14, weight: .semibold))
                Text(countLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 44, alignment: .center)

            CourseHairline()

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: 200)
    }

    @ViewBuilder
    private var sessionsColumn: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                CourseHubColumnEmptyState(
                    title: store.ui("还没有对话", "No conversations yet"),
                    detail: store.ui(
                        "在对话里问本课文稿后，记录会出现在这里。",
                        "Ask about this course’s materials in chat and sessions will show up here."
                    ),
                    systemImage: "bubble.left.and.text.bubble.right"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sessions) { session in
                            let linked = selectedMaterialID != nil && linkedSessionIDs.contains(session.id)
                            let dimmed = selectedMaterialID != nil && !linkedSessionIDs.contains(session.id)
                            CourseWorkspaceRow(
                                icon: "bubble.left.and.text.bubble.right",
                                title: session.title,
                                detail: store.ui(
                                    "\(session.messages.count) 条消息",
                                    "\(session.messages.count) messages"
                                ),
                                status: courseRelativeDate(session.updatedAt, language: store.interfaceLanguage),
                                selected: session.id == selectedSessionID,
                                prominence: linked ? .linked : (dimmed ? .dimmed : .normal)
                            ) {
                                selectedSessionID = session.id
                                store.continueCourseSession(session.id)
                            }
                            CourseHairline()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            hubActionBar(highlighted: false) {
                Text(store.ui("对话会随提问出现", "Conversations appear as you ask"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var materialsColumn: some View {
        VStack(spacing: 0) {
            Group {
                if materials.isEmpty {
                    CourseHubColumnEmptyState(
                        title: store.ui("还没有文稿", "No materials yet"),
                        detail: store.ui(
                            "把 PDF、HTML、Markdown 拖到这里，作为本课骨架。",
                            "Drop PDF, HTML, or Markdown here to build this course."
                        ),
                        systemImage: "doc.text"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(materials) { item in
                                let linkCount = store.linkedNoteCount(for: item.id)
                                CourseWorkspaceRow(
                                    icon: item.kind.systemImage,
                                    title: store.displayTitle(for: item),
                                    detail: linkCount > 0
                                        ? store.ui("已关联 \(linkCount) 篇笔记", "\(linkCount) linked notes")
                                        : store.ui("尚未关联笔记", "No linked notes"),
                                    status: item.kind.label(language: store.interfaceLanguage),
                                    selected: item.id == selectedMaterialID,
                                    prominence: .normal
                                ) {
                                    if selectedMaterialID == item.id {
                                        store.openCourseMaterial(item.id)
                                    } else {
                                        selectedMaterialID = item.id
                                    }
                                }
                                .contextMenu {
                                    Button(store.ui("打开文稿", "Open material")) {
                                        store.openCourseMaterial(item.id)
                                    }
                                }
                                CourseHairline()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            hubActionBar(highlighted: isMaterialDropTargeted) {
                Button(store.ui("导入文件夹", "Import folder"), action: importCourseFolder)
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                Button(store.ui("导入文稿", "Import materials"), action: importMaterials)
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                Spacer(minLength: 0)
                Button(store.ui("管理关系", "Relations"), action: openRelations)
                    .buttonStyle(WeiBeiTextActionButtonStyle())
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isMaterialDropTargeted) { providers in
            handleDrop(providers, asNotes: false)
        }
    }

    @ViewBuilder
    private var notesColumn: some View {
        VStack(spacing: 0) {
            Group {
                if notes.isEmpty {
                    CourseHubColumnEmptyState(
                        title: store.ui("还没有笔记", "No notes yet"),
                        detail: store.ui(
                            "导入 Markdown 或新建笔记，整理本课收获。",
                            "Import Markdown or create a note for this course."
                        ),
                        systemImage: "note.text"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notes) { item in
                                let linked = selectedMaterialID != nil && linkedNoteIDs.contains(item.id)
                                let dimmed = selectedMaterialID != nil && !linkedNoteIDs.contains(item.id)
                                CourseWorkspaceRow(
                                    icon: "note.text",
                                    title: store.displayTitle(for: item),
                                    detail: linked
                                        ? store.ui("与当前文稿关联", "Linked to selected material")
                                        : store.ui("课程笔记", "Course note"),
                                    status: "",
                                    selected: item.id == selectedNoteID,
                                    prominence: linked ? .linked : (dimmed ? .dimmed : .normal)
                                ) {
                                    selectedNoteID = item.id
                                    store.openCourseNote(item.id)
                                }
                                CourseHairline()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            hubActionBar(highlighted: isNoteDropTargeted) {
                Button(store.ui("导入笔记", "Import notes"), action: importNotes)
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                Button(store.ui("新建笔记", "New note"), action: createNote)
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                Spacer(minLength: 0)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isNoteDropTargeted) { providers in
            handleDrop(providers, asNotes: true)
        }
    }

    private func hubActionBar<Content: View>(
        highlighted: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            CourseHairline()
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(
                highlighted
                    ? WeiBeiTheme.cinnabarSoft.opacity(0.42)
                    : WeiBeiTheme.paperRaised.opacity(0.28)
            )
        }
    }

    private func filteredItems(_ items: [StudyItem]) -> [StudyItem] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return items }
        return items.filter {
            store.displayTitle(for: $0).localizedCaseInsensitiveContains(cleaned)
                || $0.subtitle.localizedCaseInsensitiveContains(cleaned)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], asNotes: Bool) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            let imported = store.importCourseFilesFromURLs(urls, asNotes: asNotes)
            if asNotes {
                if selectedNoteID == nil {
                    selectedNoteID = imported.first(where: \.isNotebookNote)?.id
                }
            } else if selectedMaterialID == nil {
                selectedMaterialID = imported.first(where: { !$0.isNotebookNote })?.id
            }
        }
        return true
    }
}
