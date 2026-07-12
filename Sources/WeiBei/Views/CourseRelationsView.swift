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
            HStack(spacing: 18) {
                ForEach(CourseRelationLens.allCases) { candidate in
                    CourseWorkspaceTab(
                        title: candidate.label(language: store.interfaceLanguage),
                        active: candidate == lens
                    ) {
                        withAnimation(WeiBeiMotion.panel) {
                            lens = candidate
                        }
                    }
                }

                Spacer()

                Text(store.ui(
                    "选择条目只查看关系，点“打开”才会离开课程台。",
                    "Selecting shows relationships. Open only when you are ready to leave."
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(WeiBeiTheme.paperRaised.opacity(0.34))

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
                    .frame(width: 390)
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

    private var note: StudyItem? {
        noteID.flatMap(store.item(withID:))
    }

    private var linkedSourceIDs: Set<String> {
        Set(noteID.map(store.linkedCourseSourceIDs(for:)) ?? [])
    }

    var body: some View {
        if let note, let noteID {
            VStack(spacing: 0) {
                CourseRelationDetailHeader(
                    mark: "NOTE",
                    title: store.displayTitle(for: note),
                    detail: store.ui(
                        "\(linkedSourceIDs.count) 份长期关联资料",
                        "\(linkedSourceIDs.count) linked materials"
                    ),
                    openTitle: store.ui("打开笔记", "Open note"),
                    open: { store.openCourseNote(noteID) }
                )

                CourseHairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(store.ui(
                            "勾选的资料会长期跟随这份笔记。打开其他文稿不会改变这里。",
                            "Checked materials stay with this note. Opening another document does not change them."
                        ))
                            .font(.system(size: 12))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)

                        if store.courseMaterials.isEmpty {
                            CourseEmptyState(
                                title: store.ui("还没有可关联资料", "No materials to link"),
                                detail: store.ui("点课程台顶部“导入”添加资料或文件夹。", "Use Import above to add materials or folders."),
                                systemImage: "books.vertical"
                            )
                        } else {
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
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

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
        } else {
            CourseEmptyState(
                title: store.ui("选择一份笔记", "Select a note"),
                detail: store.ui("在左侧选择笔记后，可以集中管理它的资料关系。", "Choose a note to manage its material relationships."),
                systemImage: "note.text"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

struct MaterialRelationDetail: View {
    @EnvironmentObject private var store: WorkspaceStore
    let materialID: String?

    private var material: StudyItem? {
        materialID.flatMap(store.item(withID:))
    }

    private var linkedNoteIDs: Set<String> {
        Set(materialID.map(store.linkedNoteIDs(for:)) ?? [])
    }

    var body: some View {
        if let material, let materialID {
            VStack(spacing: 0) {
                CourseRelationDetailHeader(
                    mark: courseMaterialMark(material.kind),
                    title: store.displayTitle(for: material),
                    detail: materialDetail(material),
                    openTitle: store.ui("打开资料", "Open material"),
                    open: { store.openCourseMaterial(materialID) }
                )

                CourseHairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(store.ui(
                            "同一份资料可以进入多份笔记。这里只编辑长期关系，不改变当前文稿。",
                            "One material can support many notes. This edits durable links without changing the open document."
                        ))
                            .font(.system(size: 12))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)

                        if store.courseNotebookItems.isEmpty {
                            CourseEmptyState(
                                title: store.ui("还没有课程笔记", "No course notes yet"),
                                detail: store.ui("先新建或导入笔记，再回来建立关系。", "Create or import a note before linking this material."),
                                systemImage: "note.text"
                            )
                        } else {
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
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

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
        } else {
            CourseEmptyState(
                title: store.ui("选择一份资料", "Select a material"),
                detail: store.ui("在左侧选择资料后，可以查看阅读位置并管理相关笔记。", "Choose a material to inspect its reading position and note links."),
                systemImage: "books.vertical"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func materialDetail(_ material: StudyItem) -> String {
        if let location = store.studyLocation(for: material.id) {
            return "\(courseLocationLabel(location, store: store)) · \(courseRelativeDate(location.lastStudiedAt, language: store.interfaceLanguage))"
        }
        return store.ui("尚无阅读位置", "No reading position")
    }
}
