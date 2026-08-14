import SwiftUI
import WeiBeiCore

/// Course-local management for the durable Doc ↔ Note relationship.
///
/// `CourseItemMembership` continues to own course membership. This surface only
/// reads and writes the explicit `NoteSourceLink` pairs already stored by
/// `WorkspaceStore`; it never treats Chat scope or the current pane selection as
/// a saved Doc ↔ Note link.
struct CourseDocNoteWorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore

    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    let isCompact: Bool

    @State private var presentation: CourseDocNotePresentation = .list
    @State private var showsNewNotePrompt = false
    @State private var newNoteTitle = ""
    @State private var newNoteError: String?

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

    private var cleanedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredDocuments: [StudyItem] {
        documents.filter(matchesSearch)
    }

    private var filteredNotes: [StudyItem] {
        notes.filter(matchesSearch)
    }

    private var documentIDs: Set<String> {
        Set(documents.map(\.id))
    }

    private var noteIDs: Set<String> {
        Set(notes.map(\.id))
    }

    private var courseLinkCount: Int {
        store.noteSourceLinks.lazy.filter {
            documentIDs.contains($0.sourceItemID)
                && noteIDs.contains($0.noteItemID)
        }.count
    }

    private var selectedDocument: StudyItem? {
        guard let selectedMaterialID else { return nil }
        return documents.first { $0.id == selectedMaterialID }
    }

    private var selectedNote: StudyItem? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    private var selectedPairIsLinked: Bool {
        guard let selectedDocument, let selectedNote else { return false }
        return store.linkedNoteIDs(for: selectedDocument.id).contains(selectedNote.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CourseHairline()

            Group {
                if courseID == nil {
                    noCourseState
                } else if documents.isEmpty || notes.isEmpty {
                    setupState
                } else if presentation == .map {
                    CourseRelationPaperView(
                        lens: $lens,
                        search: search,
                        selectedNoteID: $selectedNoteID,
                        selectedMaterialID: $selectedMaterialID,
                        isCompact: isCompact
                    )
                } else {
                    listWorkspace
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WeiBeiTheme.paper)
        .onAppear(perform: repairSelection)
        .onChange(of: courseID) { _, _ in
            presentation = .list
            repairSelection()
        }
        .onChange(of: documents.map(\.id)) { _, _ in
            repairSelection()
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            repairSelection()
        }
        .sheet(isPresented: $showsNewNotePrompt) {
            CourseDocNoteNewNoteSheet(
                title: $newNoteTitle,
                error: newNoteError,
                cancel: { showsNewNotePrompt = false },
                create: createNote
            )
            .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.ui("文档与笔记", "Docs & Notes"))
                    .font(WeiBeiTypography.brandFont(
                        language: store.interfaceLanguage,
                        size: 14,
                        weight: .semibold
                    ))
                    .foregroundStyle(WeiBeiTheme.ink)

                Text(store.ui(
                    "文档 \(documents.count) · 笔记 \(notes.count) · 关联 \(courseLinkCount)",
                    "\(documents.count) docs · \(notes.count) notes · \(courseLinkCount) links"
                ))
                .font(.system(size: 10.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            Spacer(minLength: 8)

            Picker("", selection: $presentation) {
                ForEach(CourseDocNotePresentation.allCases) { candidate in
                    Text(candidate.label(language: store.interfaceLanguage))
                        .tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: isCompact ? 126 : 154)
            .disabled(documents.isEmpty || notes.isEmpty)
            .accessibilityLabel(Text(store.ui(
                "文档与笔记显示方式",
                "Docs and Notes presentation"
            )))

            Menu {
                Button {
                    store.importCourseMaterialsFromPanel(courseID: courseID)
                } label: {
                    Label(store.ui("导入文档", "Import docs"), systemImage: "doc.badge.plus")
                }

                Button {
                    store.importCourseNotesFromPanel(courseID: courseID)
                } label: {
                    Label(store.ui("导入笔记", "Import notes"), systemImage: "note.text.badge.plus")
                }

                Divider()

                Button(action: promptForNewNote) {
                    Label(store.ui("新建笔记", "New note"), systemImage: "square.and.pencil")
                }
            } label: {
                Label(store.ui("添加", "Add"), systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(WeiBeiTheme.paperInset.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(WeiBeiTheme.paperRaised.opacity(0.24))
    }

    @ViewBuilder
    private var listWorkspace: some View {
        GeometryReader { proxy in
            if isCompact || proxy.size.width < 760 {
                ScrollView {
                    VStack(spacing: 0) {
                        documentColumn
                            .frame(minHeight: 230)
                        CourseHairline()
                        noteColumn
                            .frame(minHeight: 230)
                        CourseHairline()
                        inspector
                            .frame(minHeight: 300)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    documentColumn
                        .frame(width: max(230, proxy.size.width * 0.29))
                    CourseHairline(axis: .vertical)
                    noteColumn
                        .frame(width: max(230, proxy.size.width * 0.29))
                    CourseHairline(axis: .vertical)
                    inspector
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(WeiBeiTheme.paperRaised.opacity(0.10))
    }

    private var documentColumn: some View {
        CourseDocNoteColumn(
            title: store.ui("文档", "Docs"),
            count: filteredDocuments.count,
            emptyTitle: cleanedSearch.isEmpty
                ? store.ui("还没有文档", "No docs yet")
                : store.ui("没有匹配的文档", "No matching docs"),
            emptyDetail: cleanedSearch.isEmpty
                ? store.ui("导入 PDF、HTML、Markdown 或文本。", "Import PDF, HTML, Markdown, or text.")
                : store.ui("换个搜索词再试。", "Try another search query."),
            items: filteredDocuments
        ) { document in
            CourseDocNoteItemRow(
                icon: document.kind.systemImage,
                title: store.displayTitle(for: document),
                detail: documentDetail(document),
                status: store.ui(
                    "关联 \(store.linkedNoteIDs(for: document.id).filter(noteIDs.contains).count)",
                    "\(store.linkedNoteIDs(for: document.id).filter(noteIDs.contains).count) linked"
                ),
                selected: document.id == selectedMaterialID,
                linked: document.id == selectedMaterialID && selectedPairIsLinked
            ) {
                lens = .materials
                selectedMaterialID = document.id
            }
        }
    }

    private var noteColumn: some View {
        CourseDocNoteColumn(
            title: store.ui("笔记", "Notes"),
            count: filteredNotes.count,
            emptyTitle: cleanedSearch.isEmpty
                ? store.ui("还没有笔记", "No notes yet")
                : store.ui("没有匹配的笔记", "No matching notes"),
            emptyDetail: cleanedSearch.isEmpty
                ? store.ui("新建或导入 Markdown 笔记。", "Create or import Markdown notes.")
                : store.ui("换个搜索词再试。", "Try another search query."),
            items: filteredNotes
        ) { note in
            let linkedToSelectedDocument = selectedDocument.map {
                store.linkedNoteIDs(for: $0.id).contains(note.id)
            } ?? false

            CourseDocNoteItemRow(
                icon: "note.text",
                title: store.displayTitle(for: note),
                detail: noteDetail(note),
                status: linkedToSelectedDocument
                    ? store.ui("已关联", "Linked")
                    : store.ui(
                        "关联 \(store.linkedCourseSourceIDs(for: note.id).filter(documentIDs.contains).count)",
                        "\(store.linkedCourseSourceIDs(for: note.id).filter(documentIDs.contains).count) linked"
                    ),
                selected: note.id == selectedNoteID,
                linked: linkedToSelectedDocument
            ) {
                lens = .notes
                selectedNoteID = note.id
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.ui("关联详情", "Link Details"))
                        .font(WeiBeiTypography.brandFont(
                            language: store.interfaceLanguage,
                            size: 17,
                            weight: .semibold
                        ))
                    Text(store.ui(
                        "这里管理的是持久的文档—笔记关联，不会改变课程归属或切换当前对话。",
                        "This manages durable Doc–Note links only. It does not change course membership or switch the current Chat."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if let selectedDocument, let selectedNote {
                    CourseDocNoteObjectCard(
                        mark: store.ui("文档", "DOC"),
                        icon: selectedDocument.kind.systemImage,
                        title: store.displayTitle(for: selectedDocument),
                        detail: documentDetail(selectedDocument)
                    )

                    HStack(spacing: 8) {
                        Image(systemName: selectedPairIsLinked ? "link" : "link.badge.plus")
                            .foregroundStyle(
                                selectedPairIsLinked
                                    ? WeiBeiTheme.moss
                                    : WeiBeiTheme.cinnabar
                            )
                        Text(selectedPairIsLinked
                             ? store.ui("这则笔记已关联到当前文档", "This note is linked to the current doc")
                             : store.ui("这两个项目尚未建立关联", "These items are not linked yet"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(
                        (selectedPairIsLinked
                            ? WeiBeiTheme.moss.opacity(0.09)
                            : WeiBeiTheme.cinnabarSoft.opacity(0.24)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                    CourseDocNoteObjectCard(
                        mark: store.ui("笔记", "NOTE"),
                        icon: "note.text",
                        title: store.displayTitle(for: selectedNote),
                        detail: noteDetail(selectedNote)
                    )

                    HStack(spacing: 10) {
                        Button(
                            selectedPairIsLinked
                                ? store.ui("解除关联", "Unlink")
                                : store.ui("建立关联", "Link Doc & Note"),
                            action: toggleSelectedPairLink
                        )
                        .buttonStyle(WeiBeiTextActionButtonStyle(
                            active: !selectedPairIsLinked
                        ))

                        Button(store.ui("打开文档", "Open doc")) {
                            guard let courseID else { return }
                            _ = store.openCourseMaterial(selectedDocument.id, in: courseID)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())

                        Button(store.ui("打开笔记", "Open note")) {
                            guard let courseID else { return }
                            store.openCourseNote(selectedNote.id, in: courseID)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }

                    linkedItemsSection(
                        document: selectedDocument,
                        excluding: selectedNote.id
                    )
                } else {
                    CourseEmptyState(
                        title: store.ui("选择一份文档和一则笔记", "Select a doc and a note"),
                        detail: store.ui(
                            "左侧选择文档，中间选择笔记，然后在这里建立或解除明确关联。",
                            "Choose a doc on the left and a note in the middle, then link or unlink them here."
                        ),
                        systemImage: "link"
                    )
                    .frame(minHeight: 220)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(WeiBeiTheme.paper.opacity(0.74))
    }

    @ViewBuilder
    private func linkedItemsSection(
        document: StudyItem,
        excluding currentNoteID: String
    ) -> some View {
        let linkedIDs = Set(store.linkedNoteIDs(for: document.id))
        let linkedNotes = notes.filter {
            linkedIDs.contains($0.id) && $0.id != currentNoteID
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(store.ui("同一文档的其他关联笔记", "Other notes linked to this doc"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)

            if linkedNotes.isEmpty {
                Text(store.ui("没有其他关联笔记。", "No other linked notes."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .padding(.vertical, 8)
            } else {
                ForEach(linkedNotes) { note in
                    Button {
                        selectedNoteID = note.id
                        lens = .notes
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "note.text")
                                .foregroundStyle(WeiBeiTheme.moss)
                                .frame(width: 18)
                            Text(store.displayTitle(for: note))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(WeiBeiTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .background(
                            WeiBeiTheme.paperRaised.opacity(0.34),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noCourseState: some View {
        CourseEmptyState(
            title: store.ui("先选择一门课程", "Choose a course first"),
            detail: store.ui(
                "文档与笔记的关联会在当前课程范围内显示。",
                "Doc–Note links are shown inside the active course."
            ),
            systemImage: "books.vertical"
        )
        .frame(maxWidth: 480, minHeight: 320)
        .padding(30)
    }

    private var setupState: some View {
        VStack(spacing: 18) {
            Image(systemName: setupImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.70))

            VStack(spacing: 7) {
                Text(setupTitle)
                    .font(WeiBeiTypography.brandFont(
                        language: store.interfaceLanguage,
                        size: 19,
                        weight: .semibold
                    ))
                    .foregroundStyle(WeiBeiTheme.ink)

                Text(setupDetail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if documents.isEmpty {
                    Button(store.ui("导入文档", "Import docs")) {
                        store.importCourseMaterialsFromPanel(courseID: courseID)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }

                if notes.isEmpty {
                    Button(store.ui("新建笔记", "New note"), action: promptForNewNote)
                        .buttonStyle(WeiBeiTextActionButtonStyle(
                            active: !documents.isEmpty
                        ))

                    Button(store.ui("导入笔记", "Import notes")) {
                        store.importCourseNotesFromPanel(courseID: courseID)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
        }
        .frame(maxWidth: 520)
        .padding(42)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }

    private var setupImage: String {
        if documents.isEmpty && notes.isEmpty { return "doc.text.magnifyingglass" }
        if documents.isEmpty { return "doc.badge.plus" }
        return "note.text.badge.plus"
    }

    private var setupTitle: String {
        if documents.isEmpty && notes.isEmpty {
            return store.ui("从一份文档和一则笔记开始", "Start with a doc and a note")
        }
        if documents.isEmpty {
            return store.ui("还缺少可关联的文档", "Add a doc to link")
        }
        return store.ui("为这门课创建第一则笔记", "Create the first note for this course")
    }

    private var setupDetail: String {
        if documents.isEmpty && notes.isEmpty {
            return store.ui(
                "导入课程文档，再新建或导入笔记。只有真实存在的文档—笔记关联才会出现在关系图中。",
                "Import course docs, then create or import notes. Only real Doc–Note links appear on the map."
            )
        }
        if documents.isEmpty {
            return store.ui(
                "已有笔记不会被自动假定为来自某份文档；导入文档后再明确建立关联。",
                "Existing notes are not automatically assumed to come from a doc. Import one, then create an explicit link."
            )
        }
        return store.ui(
            "当前已有文档，但没有笔记。先创建笔记，关系管理才有实际对象。",
            "This course has docs but no notes. Create a note before opening the relationship map."
        )
    }

    private func matchesSearch(_ item: StudyItem) -> Bool {
        guard !cleanedSearch.isEmpty else { return true }
        return store.displayTitle(for: item)
            .localizedCaseInsensitiveContains(cleanedSearch)
            || store.displaySubtitle(for: item)
                .localizedCaseInsensitiveContains(cleanedSearch)
            || item.id.localizedCaseInsensitiveContains(cleanedSearch)
    }

    private func documentDetail(_ document: StudyItem) -> String {
        let subtitle = store.displaySubtitle(for: document)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if subtitle.isEmpty {
            return document.kind.label(language: store.interfaceLanguage)
        }
        return "\(document.kind.label(language: store.interfaceLanguage)) · \(subtitle)"
    }

    private func noteDetail(_ note: StudyItem) -> String {
        let subtitle = store.displaySubtitle(for: note)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return subtitle.isEmpty
            ? store.ui("课程笔记", "Course note")
            : subtitle
    }

    private func repairSelection() {
        if let selectedMaterialID,
           !documents.contains(where: { $0.id == selectedMaterialID }) {
            self.selectedMaterialID = nil
        }
        if let selectedNoteID,
           !notes.contains(where: { $0.id == selectedNoteID }) {
            self.selectedNoteID = nil
        }

        if selectedMaterialID == nil {
            selectedMaterialID = documents.first?.id
        }
        if selectedNoteID == nil {
            if let documentID = selectedMaterialID {
                let linkedIDs = Set(store.linkedNoteIDs(for: documentID))
                selectedNoteID = notes.first(where: { linkedIDs.contains($0.id) })?.id
                    ?? notes.first?.id
            } else {
                selectedNoteID = notes.first?.id
            }
        }
    }

    private func toggleSelectedPairLink() {
        guard let selectedDocument, let selectedNote else { return }
        var linkedNoteIDs = Set(store.linkedNoteIDs(for: selectedDocument.id))
        if !linkedNoteIDs.insert(selectedNote.id).inserted {
            linkedNoteIDs.remove(selectedNote.id)
        }
        store.setLinkedNoteIDs(linkedNoteIDs, for: selectedDocument.id)
    }

    private func promptForNewNote() {
        newNoteTitle = store.ui("新笔记", "New Note")
        newNoteError = nil
        showsNewNotePrompt = true
    }

    private func createNote() {
        guard let courseID else {
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
            selectedNoteID = noteID
            lens = .notes
            showsNewNotePrompt = false
        }
    }
}

private enum CourseDocNotePresentation: String, CaseIterable, Identifiable {
    case list
    case map

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .list:
            language.text("列表", "List")
        case .map:
            language.text("关系图", "Map")
        }
    }
}

private struct CourseDocNoteColumn<Row: View>: View {
    let title: String
    let count: Int
    let emptyTitle: String
    let emptyDetail: String
    let items: [StudyItem]
    @ViewBuilder let row: (StudyItem) -> Row

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(WeiBeiTheme.paperRaised.opacity(0.22))

            CourseHairline()

            if items.isEmpty {
                CourseEmptyState(
                    title: emptyTitle,
                    detail: emptyDetail,
                    systemImage: "magnifyingglass"
                )
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                            if item.id != items.last?.id {
                                CourseHairline().padding(.leading, 42)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(WeiBeiTheme.paperRaised.opacity(0.13))
    }
}

private struct CourseDocNoteItemRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let selected: Bool
    let linked: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(linked ? WeiBeiTheme.moss : WeiBeiTheme.secondaryInk)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(status)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(linked ? WeiBeiTheme.moss : WeiBeiTheme.tertiaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
            .background(
                selected
                    ? WeiBeiTheme.paperInset.opacity(0.36)
                    : (hovering ? WeiBeiTheme.paperInset.opacity(0.16) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(linked ? WeiBeiTheme.moss : WeiBeiTheme.cinnabar)
                        .frame(width: 2.5, height: 24)
                        .padding(.leading, 3)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.hover, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CourseDocNoteObjectCard: View {
    let mark: String
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(mark.uppercased())
                    .font(WeiBeiTypography.englishBrandFont(size: 8.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            WeiBeiTheme.paperRaised.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.68), lineWidth: 1)
        }
    }
}

private struct CourseDocNoteNewNoteSheet: View {
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
                    .font(WeiBeiTypography.brandFont(
                        language: store.interfaceLanguage,
                        size: 20,
                        weight: .semibold
                    ))
                Text(store.ui(
                    "新笔记会写入当前课程文件夹里的“笔记”目录。",
                    "The note will be written to the Notes folder inside this course."
                ))
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
