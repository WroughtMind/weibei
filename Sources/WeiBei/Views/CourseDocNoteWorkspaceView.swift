import SwiftUI
import WeiBeiCore

/// Course-local management for the two durable knowledge objects in WeiBei:
/// source documents and user notes. The list is the default management view;
/// the graph remains a secondary visualization of explicit NoteSourceLink data.
struct CourseDocNoteWorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    var showsGraph = false
    let isCompact: Bool
    var onEditLinks: (() -> Void)? = nil
    var createNote: (() -> Void)? = nil

    private var courseID: UUID? {
        store.courseWorkspaceCourseID
    }

    private var documents: [StudyItem] {
        guard let courseID else { return [] }
        return store.courseMaterials(in: courseID)
    }

    private var notes: [StudyItem] {
        guard let courseID else { return [] }
        return store.courseNotes(in: courseID)
    }

    private var documentIDs: Set<String> {
        Set(documents.map(\.id))
    }

    private var noteIDs: Set<String> {
        Set(notes.map(\.id))
    }

    private var cleanedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredDocuments: [StudyItem] {
        filter(documents)
    }

    private var filteredNotes: [StudyItem] {
        filter(notes)
    }

    private var selectedDocument: StudyItem? {
        selectedMaterialID.flatMap { selectedID in
            documents.first { $0.id == selectedID }
        }
    }

    private var selectedNote: StudyItem? {
        selectedNoteID.flatMap { selectedID in
            notes.first { $0.id == selectedID }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if courseID == nil {
                    CourseEmptyState(
                        title: store.ui("先选择一门课程", "Choose a course first"),
                        detail: store.ui(
                            "文稿和笔记的关联只在确定的课程里管理。",
                            "Docs and notes are managed inside an explicit course context."
                        ),
                        systemImage: "books.vertical"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
                } else if showsGraph {
                    relationshipMap
                } else {
                    listWorkspace
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeiBeiTheme.paper)
        .onAppear(perform: normalizeSelection)
        .onChange(of: courseID) { _, _ in
            selectedMaterialID = nil
            selectedNoteID = nil
            normalizeSelection()
        }
        .onChange(of: documents.map(\.id)) { _, _ in
            normalizeSelection()
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    @ViewBuilder
    private var listWorkspace: some View {
        if documents.isEmpty && notes.isEmpty {
            emptyCourseState
        } else {
            GeometryReader { proxy in
                if isCompact || proxy.size.width < 720 {
                    compactListWorkspace
                } else {
                    wideListWorkspace()
                }
            }
        }
    }

    private func wideListWorkspace() -> some View {
        HStack(spacing: 0) {
            itemColumn(
                title: store.ui("文稿", "Docs"),
                items: filteredDocuments,
                allItems: documents,
                kind: .materials
            )
            .frame(minWidth: 250, maxWidth: .infinity)

            CourseHairline(axis: .vertical)

            itemColumn(
                title: store.ui("笔记", "Notes"),
                items: filteredNotes,
                allItems: notes,
                kind: .notes
            )
            .frame(minWidth: 250, maxWidth: .infinity)
        }
    }

    private var compactListWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                compactItemSection(
                    title: store.ui("文稿", "Docs"),
                    items: filteredDocuments,
                    allItems: documents,
                    kind: .materials
                )

                compactItemSection(
                    title: store.ui("笔记", "Notes"),
                    items: filteredNotes,
                    allItems: notes,
                    kind: .notes
                )
            }
            .padding(18)
        }
    }

    private func itemColumn(
        title: String,
        items: [StudyItem],
        allItems: [StudyItem],
        kind: CourseRelationLens
    ) -> some View {
        VStack(spacing: 0) {
            sectionHeader(title: title, count: allItems.count, kind: kind)
            CourseHairline()

            if items.isEmpty {
                itemColumnEmptyState(kind: kind, hasItemsBeforeSearch: !allItems.isEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            itemRow(item, kind: kind)
                            if item.id != items.last?.id {
                                CourseHairline().padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .background(WeiBeiTheme.paper)
    }

    private func compactItemSection(
        title: String,
        items: [StudyItem],
        allItems: [StudyItem],
        kind: CourseRelationLens
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: title, count: allItems.count, kind: kind)
            CourseHairline()

            if items.isEmpty {
                itemColumnEmptyState(kind: kind, hasItemsBeforeSearch: !allItems.isEmpty)
                    .padding(18)
            } else {
                ForEach(items) { item in
                    itemRow(item, kind: kind)
                    if item.id != items.last?.id {
                        CourseHairline().padding(.leading, 42)
                    }
                }
            }
        }
        .background(
            WeiBeiTheme.paperRaised.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.62), lineWidth: 1)
        }
    }

    private func sectionHeader(title: String, count: Int, kind: CourseRelationLens) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .weiBeiText(12, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Text("\(count)")
                .weiBeiText(11, weight: .medium, design: .monospaced)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            Spacer(minLength: 0)
            if let courseID {
                if kind == .materials {
                    Button {
                        store.importCourseMaterialsFromPanel(courseID: courseID)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(size: 22))
                    .help(store.ui("导入文稿", "Import docs"))
                    .accessibilityLabel(Text(store.ui("导入文稿", "Import docs")))
                } else {
                    Menu {
                        Button(store.ui("导入笔记", "Import notes")) {
                            store.importCourseNotesFromPanel(courseID: courseID)
                        }
                        if let createNote {
                            Button(store.ui("新建笔记", "New note"), action: createNote)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .buttonStyle(WeiBeiIconButtonStyle(size: 22))
                    .help(store.ui("导入或新建笔记", "Import or create a note"))
                    .accessibilityLabel(Text(store.ui("添加笔记", "Add note")))
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var showsMaterialLinkToggles: Bool { selectedNote != nil }

    private var showsNoteLinkToggles: Bool { selectedDocument != nil }

    private func itemRow(
        _ item: StudyItem,
        kind: CourseRelationLens
    ) -> some View {
        let showsToggle = kind == .materials ? showsMaterialLinkToggles : showsNoteLinkToggles
        let counterpart: StudyItem? = kind == .materials ? selectedNote : selectedDocument
        return HStack(spacing: 0) {
            if showsToggle, let counterpart {
                Button {
                    toggleLink(item: counterpart, kind: kind == .materials ? .notes : .materials, counterpart: item)
                } label: {
                    Image(systemName: isLinked(
                        item: counterpart,
                        kind: kind == .materials ? .notes : .materials,
                        counterpart: item
                    ) ? "checkmark.square.fill" : "square")
                    .weiBeiText(14, weight: .medium)
                    .foregroundStyle(
                        isLinked(
                            item: counterpart,
                            kind: kind == .materials ? .notes : .materials,
                            counterpart: item
                        ) ? WeiBeiTheme.accent : WeiBeiTheme.tertiaryInk
                    )
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("切换关联", "Toggle link")))
            }

            CourseWorkspaceRow(
                icon: kind == .notes ? "note.text" : item.kind.systemImage,
                title: store.noteListDisplayTitle(for: item),
                detail: itemDetail(item),
                status: relationCountLabel(for: item, kind: kind),
                selected: isSelected(item, kind: kind)
            ) {
                select(item, kind: kind)
            }
        }
        .background(
            store.recentlyImportedItemIDs.contains(item.id)
                ? WeiBeiTheme.accentSoft.opacity(0.24)
                : Color.clear
        )
    }

    @ViewBuilder
    private func itemColumnEmptyState(
        kind: CourseRelationLens,
        hasItemsBeforeSearch: Bool
    ) -> some View {
        if hasItemsBeforeSearch {
            CourseEmptyState(
                title: store.ui("没有匹配结果", "No matching results"),
                detail: store.ui(
                    "换个搜索词；文稿与笔记仍保留在这门课中。",
                    "Try another query. The docs and notes remain in this course."
                ),
                systemImage: "magnifyingglass"
            )
        } else if kind == .materials {
            CourseEmptyState(
                title: store.ui("还没有文稿", "No docs yet"),
                detail: store.ui(
                    "点这一列顶部的加号导入 Word、PPT、PDF、HTML、Markdown 或文本。",
                    "Use the plus on this column to import Word, PowerPoint, PDF, HTML, Markdown, or text."
                ),
                systemImage: "doc.badge.plus"
            )
        } else {
            CourseEmptyState(
                title: store.ui("还没有笔记", "No notes yet"),
                detail: store.ui(
                    "新建或导入一篇笔记后，就能把它明确关联到文稿。",
                    "Create or import a note, then explicitly link it to a doc."
                ),
                systemImage: "note.text.badge.plus"
            )
        }
    }

    @ViewBuilder
    private var relationshipMap: some View {
        if documents.isEmpty && notes.isEmpty {
            emptyCourseState
        } else {
            CourseRelationPaperView(
                lens: $lens,
                search: search,
                selectedNoteID: $selectedNoteID,
                selectedMaterialID: $selectedMaterialID,
                isCompact: isCompact,
                allowsWorkspaceScopes: false
            )
        }
    }

    private var emptyCourseState: some View {
        VStack(spacing: 18) {
            CourseEmptyState(
                title: store.ui("这门课还没有文稿或笔记", "No docs or notes yet"),
                detail: store.ui(
                    "先加入真实文稿和笔记。魏碑只会显示明确保存的文稿—笔记关系。",
                    "Add real docs and notes first. WeiBei shows only explicitly saved doc–note links."
                ),
                systemImage: "books.vertical"
            )

            if let courseID {
                HStack(spacing: 10) {
                    Button(store.ui("导入文稿", "Import docs")) {
                        store.importCourseMaterialsFromPanel(courseID: courseID)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))

                    Button(store.ui("导入笔记", "Import notes")) {
                        store.importCourseNotesFromPanel(courseID: courseID)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func filter(_ items: [StudyItem]) -> [StudyItem] {
        guard !cleanedSearch.isEmpty else { return items }
        return items.filter { item in
            store.itemMatchesLibrarySearch(item, query: cleanedSearch)
                || item.id.localizedCaseInsensitiveContains(cleanedSearch)
        }
    }

    private func itemDetail(_ item: StudyItem) -> String {
        let subtitle = store.displaySubtitle(for: item)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !subtitle.isEmpty {
            return subtitle
        }
        return item.isNotebookNote
            ? store.ui("课程笔记", "Course note")
            : item.kind.label(language: store.interfaceLanguage)
    }

    private func isSelected(
        _ item: StudyItem,
        kind: CourseRelationLens
    ) -> Bool {
        switch kind {
        case .materials:
            item.id == selectedMaterialID
        case .notes:
            item.id == selectedNoteID
        }
    }

    private func select(
        _ item: StudyItem,
        kind: CourseRelationLens
    ) {
        lens = kind
        switch kind {
        case .materials:
            selectedMaterialID = item.id
            selectedNoteID = nil
        case .notes:
            selectedNoteID = item.id
            selectedMaterialID = nil
        }
    }

    private func open(
        _ item: StudyItem,
        kind: CourseRelationLens
    ) {
        guard let courseID else { return }
        select(item, kind: kind)
        switch kind {
        case .materials:
            _ = store.openCourseMaterial(item.id, in: courseID)
        case .notes:
            store.openCourseNote(item.id, in: courseID)
        }
    }

    private func relationCountLabel(
        for item: StudyItem,
        kind: CourseRelationLens
    ) -> String {
        switch kind {
        case .materials:
            let count = store.linkedNoteIDs(for: item.id)
                .filter(noteIDs.contains)
                .count
            return store.ui("\(count) 篇笔记", "\(count) notes")
        case .notes:
            let count = store.linkedCourseSourceIDs(for: item.id)
                .filter(documentIDs.contains)
                .count
            return store.ui("\(count) 份文稿", "\(count) docs")
        }
    }

    private func isLinked(
        item: StudyItem,
        kind: CourseRelationLens,
        counterpart: StudyItem
    ) -> Bool {
        switch kind {
        case .materials:
            store.linkedNoteIDs(for: item.id).contains(counterpart.id)
        case .notes:
            store.linkedCourseSourceIDs(for: item.id).contains(counterpart.id)
        }
    }

    private func toggleLink(
        item: StudyItem,
        kind: CourseRelationLens,
        counterpart: StudyItem
    ) {
        switch kind {
        case .materials:
            var linkedNoteIDs = Set(store.linkedNoteIDs(for: item.id))
            if linkedNoteIDs.contains(counterpart.id) {
                linkedNoteIDs.remove(counterpart.id)
            } else {
                linkedNoteIDs.insert(counterpart.id)
            }
            store.setLinkedNoteIDs(linkedNoteIDs, for: item.id)
            selectedMaterialID = item.id
            selectedNoteID = nil

        case .notes:
            var linkedDocumentIDs = Set(store.linkedCourseSourceIDs(for: item.id))
            if linkedDocumentIDs.contains(counterpart.id) {
                linkedDocumentIDs.remove(counterpart.id)
            } else {
                linkedDocumentIDs.insert(counterpart.id)
            }
            store.setLinkedCourseSourceIDs(linkedDocumentIDs, for: item.id)
            selectedNoteID = item.id
            selectedMaterialID = nil
        }
    }

    private func normalizeSelection() {
        if let selectedMaterialID,
           !documentIDs.contains(selectedMaterialID) {
            self.selectedMaterialID = nil
        }
        if let selectedNoteID,
           !noteIDs.contains(selectedNoteID) {
            self.selectedNoteID = nil
        }

        guard selectedMaterialID == nil, selectedNoteID == nil else { return }
        if lens == .materials, let firstDocument = documents.first {
            selectedMaterialID = firstDocument.id
        } else if lens == .notes, let firstNote = notes.first {
            selectedNoteID = firstNote.id
        } else if let firstDocument = documents.first {
            lens = .materials
            selectedMaterialID = firstDocument.id
        } else if let firstNote = notes.first {
            lens = .notes
            selectedNoteID = firstNote.id
        }
    }
}
