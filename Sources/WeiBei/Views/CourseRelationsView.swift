import Foundation
import SwiftUI
import WeiBeiCore

struct CourseRelationsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    let isCompact: Bool

    private var filteredNotes: [StudyItem] {
        filtered(store.courseNotebookItems)
    }

    private var filteredMaterials: [StudyItem] {
        filtered(store.courseMaterials)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(store.ui("查看", "View"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)

                Menu {
                    ForEach(CourseRelationLens.allCases) { candidate in
                        Button(candidate.label(language: store.interfaceLanguage)) {
                            withAnimation(WeiBeiMotion.panel) {
                                lens = candidate
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(lens.label(language: store.interfaceLanguage))
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(WeiBeiTheme.ink)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Text(store.ui(
                    "先查看长期关联，需要调整时再进入管理。",
                    "Review durable links first. Manage them only when needed."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .padding(.horizontal, 22)
            .frame(height: 40)
            .background(WeiBeiTheme.paperRaised.opacity(0.28))

            CourseHairline()

            if lens == .notes {
                relationSplit(
                    list: noteList,
                    detail: AnyView(NoteRelationDetail(noteID: resolvedNoteID))
                )
            } else {
                relationSplit(
                    list: materialList,
                    detail: AnyView(MaterialRelationDetail(materialID: resolvedMaterialID))
                )
            }
        }
        .onAppear(perform: ensureSelections)
        .onChange(of: lens) { _, _ in ensureSelections() }
        .onChange(of: store.importedItems) { _, _ in ensureSelections() }
    }

    private var resolvedNoteID: String? {
        if let selectedNoteID, filteredNotes.contains(where: { $0.id == selectedNoteID }) {
            return selectedNoteID
        }
        return filteredNotes.first?.id
    }

    private var resolvedMaterialID: String? {
        if let selectedMaterialID, filteredMaterials.contains(where: { $0.id == selectedMaterialID }) {
            return selectedMaterialID
        }
        return filteredMaterials.first?.id
    }

    private var noteList: AnyView {
        AnyView(
            CourseEntityList(
                items: filteredNotes,
                selectedID: resolvedNoteID,
                emptyTitle: store.ui("还没有课程笔记", "No course notes yet"),
                emptyDetail: store.ui("点顶部“加入”，新建或导入 Markdown 笔记。", "Use Add above to create or import Markdown notes."),
                status: { item in
                    let count = store.linkedCourseSourceIDs(for: item.id).count
                    return count == 0
                        ? store.ui("尚未关联资料", "No material links")
                        : store.ui("\(count) 份资料", "\(count) materials")
                },
                detail: { item in courseFolderLabel(item, store: store) },
                select: { selectedNoteID = $0 }
            )
        )
    }

    private var materialList: AnyView {
        AnyView(
            CourseEntityList(
                items: filteredMaterials,
                selectedID: resolvedMaterialID,
                emptyTitle: store.ui("还没有课程资料", "No course materials yet"),
                emptyDetail: store.ui("点顶部“导入”，选择 PDF、HTML、Markdown、文本或文件夹。", "Use Import for PDF, HTML, Markdown, text, or folders."),
                status: { item in
                    let count = store.linkedNoteCount(for: item.id)
                    return count == 0
                        ? store.ui("尚未关联笔记", "No note links")
                        : store.ui("\(count) 份笔记", "\(count) notes")
                },
                detail: { item in
                    if let location = store.studyLocation(for: item.id) {
                        return courseLocationLabel(location, store: store)
                    }
                    return courseFolderLabel(item, store: store)
                },
                select: { selectedMaterialID = $0 }
            )
        )
    }

    @ViewBuilder
    private func relationSplit(list: AnyView, detail: AnyView) -> some View {
        if isCompact {
            VStack(spacing: 0) {
                list
                CourseHairline()
                detail.frame(minHeight: 360)
            }
        } else {
            HStack(spacing: 0) {
                list
                    .frame(width: 350)
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.72))
                    .frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func ensureSelections() {
        if selectedNoteID == nil || !store.courseNotebookItems.contains(where: { $0.id == selectedNoteID }) {
            selectedNoteID = store.courseNotebookItems.first?.id
        }
        if selectedMaterialID == nil || !store.courseMaterials.contains(where: { $0.id == selectedMaterialID }) {
            selectedMaterialID = store.courseMaterials.first?.id
        }
    }

    private func filtered(_ items: [StudyItem]) -> [StudyItem] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return items }
        return items.filter { item in
            store.displayTitle(for: item).localizedCaseInsensitiveContains(cleaned)
                || store.displaySubtitle(for: item).localizedCaseInsensitiveContains(cleaned)
                || (item.url?.path.localizedCaseInsensitiveContains(cleaned) == true)
        }
    }
}

struct CourseEntityList: View {
    @EnvironmentObject private var store: WorkspaceStore
    let items: [StudyItem]
    let selectedID: String?
    let emptyTitle: String
    let emptyDetail: String
    let status: (StudyItem) -> String
    let detail: (StudyItem) -> String
    let select: (String) -> Void

    var body: some View {
        if items.isEmpty {
            CourseEmptyState(title: emptyTitle, detail: emptyDetail, systemImage: "tray")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        CourseWorkspaceRow(
                            icon: item.kind.systemImage,
                            title: store.displayTitle(for: item),
                            detail: detail(item),
                            status: status(item),
                            selected: item.id == selectedID
                        ) {
                            select(item.id)
                        }
                        CourseHairline()
                    }
                }
                .padding(.vertical, 6)
            }
            .background(WeiBeiTheme.paperRaised.opacity(0.22))
        }
    }
}

struct NoteRelationDetail: View {
    @EnvironmentObject private var store: WorkspaceStore
    let noteID: String?
    @State private var isManagingLinks = false

    private var note: StudyItem? {
        noteID.flatMap(store.item(withID:))
    }

    private var linkedSourceIDs: Set<String> {
        Set(noteID.map(store.linkedCourseSourceIDs(for:)) ?? [])
    }

    var body: some View {
        Group {
            if let note, let noteID {
                VStack(spacing: 0) {
                CourseRelationDetailHeader(
                    mark: "NOTE",
                    title: store.displayTitle(for: note),
                    detail: store.ui(
                        "\(linkedSourceIDs.count) 份长期关联资料",
                        "\(linkedSourceIDs.count) linked materials"
                    ),
                    manageTitle: isManagingLinks
                        ? store.ui("完成", "Done")
                        : store.ui("管理关联", "Manage links"),
                    manage: {
                        withAnimation(WeiBeiMotion.reveal) {
                            isManagingLinks.toggle()
                        }
                    },
                    openTitle: store.ui("打开笔记", "Open note"),
                    open: { store.openCourseNote(noteID) }
                )

                CourseHairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(store.ui(
                            isManagingLinks
                                ? "选择长期支撑这份笔记的资料。更改会自动保存。"
                                : "这些资料会长期跟随这份笔记，打开其他文稿不会改变它们。",
                            isManagingLinks
                                ? "Choose the materials that support this note. Changes save automatically."
                                : "These materials stay with this note even when another document is open."
                        ))
                            .font(.system(size: 12))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)

                        if store.courseMaterials.isEmpty {
                            CourseEmptyState(
                                title: store.ui("还没有可关联资料", "No materials to link"),
                                detail: store.ui("点课程首页顶部“导入”添加资料或文件夹。", "Use Import above to add materials or folders."),
                                systemImage: "books.vertical"
                            )
                        } else if isManagingLinks {
                            VStack(spacing: 0) {
                                ForEach(store.courseMaterials) { material in
                                    RelationSelectionRow(
                                        item: material,
                                        checked: linkedSourceIDs.contains(material.id),
                                        detail: courseFolderLabel(material, store: store)
                                    ) {
                                        store.setLinkedCourseSourceIDs(
                                            toggled(material.id, in: linkedSourceIDs),
                                            for: noteID
                                        )
                                    }
                                    CourseHairline()
                                }
                            }
                        } else if linkedSourceIDs.isEmpty {
                            CourseEmptyState(
                                title: store.ui("还没有关联资料", "No linked materials"),
                                detail: store.ui("需要时点“管理关联”，为这份笔记选择长期资料。", "Use Manage links when this note needs supporting materials."),
                                systemImage: "link"
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(store.courseMaterials.filter { linkedSourceIDs.contains($0.id) }) { material in
                                    CourseLinkedItemRow(
                                        item: material,
                                        detail: courseFolderLabel(material, store: store)
                                    )
                                    CourseHairline()
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                if isManagingLinks {
                    CourseHairline()
                    relationFooter(
                        countTitle: store.ui(
                            "已关联 \(linkedSourceIDs.count) 份资料",
                            "\(linkedSourceIDs.count) linked materials"
                        ),
                        statusTitle: store.ui("更改自动保存", "Changes save automatically"),
                        errorTitle: store.workspaceSaveError,
                        retryTitle: store.ui("重试保存", "Retry save"),
                        retry: { _ = store.retryWorkspaceSave() }
                    )
                }
                }
            } else {
                CourseEmptyState(
                    title: store.ui("选择一份笔记", "Select a note"),
                    detail: store.ui("在左侧选择笔记后，可以查看它的长期资料关系。", "Choose a note to review its material relationships."),
                    systemImage: "note.text"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: noteID) { _, _ in isManagingLinks = false }
    }

}

struct MaterialRelationDetail: View {
    @EnvironmentObject private var store: WorkspaceStore
    let materialID: String?
    @State private var isManagingLinks = false

    private var material: StudyItem? {
        materialID.flatMap(store.item(withID:))
    }

    private var linkedNoteIDs: Set<String> {
        Set(materialID.map(store.linkedNoteIDs(for:)) ?? [])
    }

    var body: some View {
        Group {
            if let material, let materialID {
                VStack(spacing: 0) {
                CourseRelationDetailHeader(
                    mark: courseMaterialMark(material.kind),
                    title: store.displayTitle(for: material),
                    detail: materialDetail(material),
                    manageTitle: isManagingLinks
                        ? store.ui("完成", "Done")
                        : store.ui("管理关联", "Manage links"),
                    manage: {
                        withAnimation(WeiBeiMotion.reveal) {
                            isManagingLinks.toggle()
                        }
                    },
                    openTitle: store.ui("打开资料", "Open material"),
                    open: { store.openCourseMaterial(materialID) }
                )

                CourseHairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(store.ui(
                            isManagingLinks
                                ? "选择会长期使用这份资料的笔记。更改不会切换当前文稿。"
                                : "这些笔记长期使用这份资料，查看关系不会切换当前文稿。",
                            isManagingLinks
                                ? "Choose the notes that use this material. Changes do not switch the open document."
                                : "These notes use this material. Reviewing links does not switch the open document."
                        ))
                            .font(.system(size: 12))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)

                        if store.courseNotebookItems.isEmpty {
                            CourseEmptyState(
                                title: store.ui("还没有课程笔记", "No course notes yet"),
                                detail: store.ui("先新建或导入笔记，再回来建立关系。", "Create or import a note before linking this material."),
                                systemImage: "note.text"
                            )
                        } else if isManagingLinks {
                            VStack(spacing: 0) {
                                ForEach(store.courseNotebookItems) { note in
                                    RelationSelectionRow(
                                        item: note,
                                        checked: linkedNoteIDs.contains(note.id),
                                        detail: store.ui(
                                            "\(store.linkedCourseSourceIDs(for: note.id).count) 份资料",
                                            "\(store.linkedCourseSourceIDs(for: note.id).count) materials"
                                        )
                                    ) {
                                        store.setLinkedNoteIDs(
                                            toggled(note.id, in: linkedNoteIDs),
                                            for: materialID
                                        )
                                    }
                                    CourseHairline()
                                }
                            }
                        } else if linkedNoteIDs.isEmpty {
                            CourseEmptyState(
                                title: store.ui("还没有关联笔记", "No linked notes"),
                                detail: store.ui("需要时点“管理关联”，选择会使用这份资料的笔记。", "Use Manage links when notes should use this material."),
                                systemImage: "link"
                            )
                        } else {
                            VStack(spacing: 0) {
                                ForEach(store.courseNotebookItems.filter { linkedNoteIDs.contains($0.id) }) { note in
                                    CourseLinkedItemRow(
                                        item: note,
                                        detail: store.ui(
                                            "\(store.linkedCourseSourceIDs(for: note.id).count) 份资料",
                                            "\(store.linkedCourseSourceIDs(for: note.id).count) materials"
                                        )
                                    )
                                    CourseHairline()
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                if isManagingLinks {
                    CourseHairline()
                    relationFooter(
                        countTitle: store.ui(
                            "已关联 \(linkedNoteIDs.count) 份笔记",
                            "\(linkedNoteIDs.count) linked notes"
                        ),
                        statusTitle: store.ui("更改自动保存", "Changes save automatically"),
                        errorTitle: store.workspaceSaveError,
                        retryTitle: store.ui("重试保存", "Retry save"),
                        retry: { _ = store.retryWorkspaceSave() }
                    )
                }
                }
            } else {
                CourseEmptyState(
                    title: store.ui("选择一份资料", "Select a material"),
                    detail: store.ui("在左侧选择资料后，可以查看阅读位置和关联笔记。", "Choose a material to inspect its reading position and note links."),
                    systemImage: "books.vertical"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: materialID) { _, _ in isManagingLinks = false }
    }

    private func materialDetail(_ material: StudyItem) -> String {
        if let location = store.studyLocation(for: material.id) {
            return "\(courseLocationLabel(location, store: store)) · \(courseRelativeDate(location.lastStudiedAt, language: store.interfaceLanguage))"
        }
        return store.ui("尚无阅读位置", "No reading position")
    }
}
