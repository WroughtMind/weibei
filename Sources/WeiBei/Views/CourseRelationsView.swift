import SwiftUI
import WeiBeiCore

private enum CourseDocNotePresentation: String, CaseIterable, Identifiable {
    case list
    case map

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .list:
            return language.text("清单", "List")
        case .map:
            return language.text("关系图", "Map")
        }
    }
}

private enum CourseDocNoteItemKind {
    case document
    case note
}

/// Course-local management for the only relationship represented here:
/// a durable, user-chosen link between one source document and one note.
///
/// Course membership, the currently open panes, Chat associations, and learning
/// memory are intentionally not represented as Doc ↔ Note links.
struct CourseRelationsView: View {
    @EnvironmentObject private var store: WorkspaceStore

    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    let isCompact: Bool

    @State private var presentation: CourseDocNotePresentation = .list

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

    private var visibleDocuments: [StudyItem] {
        filtered(documents)
    }

    private var visibleNotes: [StudyItem] {
        filtered(notes)
    }

    private var selectedDocument: StudyItem? {
        guard let selectedMaterialID else { return nil }
        return documents.first { $0.id == selectedMaterialID }
    }

    private var selectedNote: StudyItem? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    private var courseLinkCount: Int {
        let documentIDs = Set(documents.map(\.id))
        let noteIDs = Set(notes.map(\.id))
        return store.noteSourceLinks.lazy.filter {
            documentIDs.contains($0.sourceItemID)
                && noteIDs.contains($0.noteItemID)
        }.count
    }

    private var selectedPairIsLinked: Bool {
        guard let selectedDocument, let selectedNote else { return false }
        return store.linkedNoteIDs(for: selectedDocument.id).contains(selectedNote.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            pageHeader
            CourseHairline()

            switch presentation {
            case .list:
                listPresentation
            case .map:
                CourseRelationPaperView(
                    lens: $lens,
                    search: search,
                    selectedNoteID: $selectedNoteID,
                    selectedMaterialID: $selectedMaterialID,
                    isCompact: isCompact
                )
            }
        }
        .background(WeiBeiTheme.paper)
        .onAppear(perform: normalizeSelection)
        .onChange(of: courseID) { _, _ in
            selectedMaterialID = documents.first?.id
            selectedNoteID = notes.first?.id
            lens = documents.isEmpty ? .notes : .materials
            presentation = .list
        }
        .onChange(of: documents.map(\.id)) { _, _ in
            normalizeSelection()
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            normalizeSelection()
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.ui("文稿与笔记", "Docs & Notes"))
                    .font(WeiBeiTypography.brandFont(
                        language: store.interfaceLanguage,
                        size: 17,
                        weight: .semibold
                    ))
                    .foregroundStyle(WeiBeiTheme.ink)

                Text(store.ui(
                    "文稿 \(documents.count) · 笔记 \(notes.count) · 已保存关系 \(courseLinkCount)",
                    "\(documents.count) docs · \(notes.count) notes · \(courseLinkCount) saved links"
                ))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            Spacer(minLength: 12)

            Text(store.ui(
                "这里只管理文稿与笔记之间由你保存的关系",
                "Only user-saved Doc ↔ Note links are managed here"
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .lineLimit(1)
            .opacity(isCompact ? 0 : 1)

            Picker("", selection: $presentation) {
                ForEach(CourseDocNotePresentation.allCases) { candidate in
                    Text(candidate.label(language: store.interfaceLanguage))
                        .tag(candidate)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 152)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .background(WeiBeiTheme.paperRaised.opacity(0.24))
    }

    @ViewBuilder
    private var listPresentation: some View {
        if courseID == nil {
            CourseEmptyState(
                title: store.ui("先选择一门课程", "Choose a course first"),
                detail: store.ui(
                    "文稿与笔记关系按当前课程显示。",
                    "Doc and Note links are shown for the active course."
                ),
                systemImage: "books.vertical"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        } else if documents.isEmpty && notes.isEmpty {
            CourseEmptyState(
                title: store.ui("这门课还没有文稿或笔记", "No Docs or Notes in this course"),
                detail: store.ui(
                    "使用右上角“添加”导入文稿、导入笔记或新建笔记。",
                    "Use Add to import a Doc, import a Note, or create a new Note."
                ),
                systemImage: "doc.badge.plus"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(36)
        } else {
            VStack(spacing: 0) {
                if isCompact {
                    compactLists
                } else {
                    HStack(spacing: 0) {
                        documentColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        CourseHairline(axis: .vertical)

                        noteColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                CourseHairline()
                selectedRelationshipBar
            }
        }
    }

    private var compactLists: some View {
        VStack(spacing: 0) {
            Picker("", selection: $lens) {
                ForEach(CourseRelationLens.allCases) { candidate in
                    Text(candidate == .materials
                         ? store.ui("文稿", "Docs")
                         : store.ui("笔记", "Notes"))
                        .tag(candidate)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            CourseHairline()

            if lens == .materials {
                documentColumn
            } else {
                noteColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentColumn: some View {
        CourseDocNoteColumn(
            title: store.ui("文稿", "Docs"),
            count: visibleDocuments.count,
            emptyTitle: cleanedSearch.isEmpty
                ? store.ui("还没有文稿", "No Docs yet")
                : store.ui("没有匹配的文稿", "No matching Docs"),
            emptyDetail: cleanedSearch.isEmpty
                ? store.ui("从右上角“添加”导入 PDF、HTML、Markdown 或文本。", "Use Add to import PDF, HTML, Markdown, or text.")
                : store.ui("换一个搜索词再试。", "Try another search term."),
            emptySystemImage: "doc.text"
        ) {
            ForEach(visibleDocuments) { document in
                CourseDocNoteRow(
                    icon: document.kind.systemImage,
                    title: store.displayTitle(for: document),
                    detail: store.displaySubtitle(for: document),
                    relationCount: linkedNoteCount(for: document.id),
                    relationLabel: store.ui("篇笔记", "notes"),
                    selected: selectedMaterialID == document.id,
                    linkedToCounterpart: selectedNoteID.map {
                        store.linkedNoteIDs(for: document.id).contains($0)
                    } ?? false,
                    select: {
                        lens = .materials
                        selectedMaterialID = document.id
                    },
                    open: { openDocument(document) }
                )
            }
        }
    }

    private var noteColumn: some View {
        CourseDocNoteColumn(
            title: store.ui("笔记", "Notes"),
            count: visibleNotes.count,
            emptyTitle: cleanedSearch.isEmpty
                ? store.ui("还没有笔记", "No Notes yet")
                : store.ui("没有匹配的笔记", "No matching Notes"),
            emptyDetail: cleanedSearch.isEmpty
                ? store.ui("从右上角“添加”新建或导入 Markdown 笔记。", "Use Add to create or import a Markdown Note.")
                : store.ui("换一个搜索词再试。", "Try another search term."),
            emptySystemImage: "note.text"
        ) {
            ForEach(visibleNotes) { note in
                CourseDocNoteRow(
                    icon: "note.text",
                    title: store.displayTitle(for: note),
                    detail: store.displaySubtitle(for: note),
                    relationCount: linkedDocumentCount(for: note.id),
                    relationLabel: store.ui("份文稿", "docs"),
                    selected: selectedNoteID == note.id,
                    linkedToCounterpart: selectedMaterialID.map {
                        store.linkedCourseSourceIDs(for: note.id).contains($0)
                    } ?? false,
                    select: {
                        lens = .notes
                        selectedNoteID = note.id
                    },
                    open: { openNote(note) }
                )
            }
        }
    }

    @ViewBuilder
    private var selectedRelationshipBar: some View {
        if let selectedDocument, let selectedNote {
            HStack(spacing: 12) {
                selectedItemSummary(
                    icon: selectedDocument.kind.systemImage,
                    title: store.displayTitle(for: selectedDocument),
                    label: store.ui("文稿", "Doc")
                )

                Image(systemName: selectedPairIsLinked ? "link" : "arrow.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        selectedPairIsLinked
                            ? WeiBeiTheme.link
                            : WeiBeiTheme.tertiaryInk
                    )
                    .frame(width: 24)

                selectedItemSummary(
                    icon: "note.text",
                    title: store.displayTitle(for: selectedNote),
                    label: store.ui("笔记", "Note")
                )

                Spacer(minLength: 12)

                Text(selectedPairIsLinked
                     ? store.ui("已建立关系", "Linked")
                     : store.ui("尚未建立关系", "Not linked"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        selectedPairIsLinked
                            ? WeiBeiTheme.link
                            : WeiBeiTheme.secondaryInk
                    )

                Button(
                    selectedPairIsLinked
                        ? store.ui("移除关系", "Remove link")
                        : store.ui("建立关系", "Link Doc & Note"),
                    action: toggleSelectedRelationship
                )
                .buttonStyle(WeiBeiTextActionButtonStyle(active: !selectedPairIsLinked))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .background(WeiBeiTheme.paperRaised.opacity(0.30))
        } else {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Text(store.ui(
                    "分别选择一份文稿和一篇笔记，即可查看或修改它们的关系。",
                    "Select one Doc and one Note to inspect or change their link."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(WeiBeiTheme.paperRaised.opacity(0.26))
        }
    }

    private func selectedItemSummary(
        icon: String,
        title: String,
        label: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
    }

    private func filtered(_ items: [StudyItem]) -> [StudyItem] {
        guard !cleanedSearch.isEmpty else { return items }
        return items.filter { item in
            store.displayTitle(for: item)
                .localizedCaseInsensitiveContains(cleanedSearch)
                || store.displaySubtitle(for: item)
                    .localizedCaseInsensitiveContains(cleanedSearch)
                || item.id.localizedCaseInsensitiveContains(cleanedSearch)
        }
    }

    private func linkedNoteCount(for documentID: String) -> Int {
        let courseNoteIDs = Set(notes.map(\.id))
        return store.linkedNoteIDs(for: documentID).lazy.filter {
            courseNoteIDs.contains($0)
        }.count
    }

    private func linkedDocumentCount(for noteID: String) -> Int {
        let courseDocumentIDs = Set(documents.map(\.id))
        return store.linkedCourseSourceIDs(for: noteID).lazy.filter {
            courseDocumentIDs.contains($0)
        }.count
    }

    private func openDocument(_ document: StudyItem) {
        guard let courseID else { return }
        selectedMaterialID = document.id
        lens = .materials
        _ = store.openCourseMaterial(document.id, in: courseID)
    }

    private func openNote(_ note: StudyItem) {
        guard let courseID else { return }
        selectedNoteID = note.id
        lens = .notes
        store.openCourseNote(note.id, in: courseID)
    }

    private func toggleSelectedRelationship() {
        guard let selectedDocument, let selectedNote else { return }
        var linkedNoteIDs = Set(store.linkedNoteIDs(for: selectedDocument.id))
        if linkedNoteIDs.contains(selectedNote.id) {
            linkedNoteIDs.remove(selectedNote.id)
        } else {
            linkedNoteIDs.insert(selectedNote.id)
        }
        store.setLinkedNoteIDs(linkedNoteIDs, for: selectedDocument.id)
    }

    private func normalizeSelection() {
        if selectedMaterialID.map({ id in documents.contains { $0.id == id } }) != true {
            selectedMaterialID = documents.first?.id
        }
        if selectedNoteID.map({ id in notes.contains { $0.id == id } }) != true {
            selectedNoteID = notes.first?.id
        }
        if documents.isEmpty, !notes.isEmpty {
            lens = .notes
        } else if !documents.isEmpty, notes.isEmpty {
            lens = .materials
        }
    }
}

private struct CourseDocNoteColumn<Content: View>: View {
    let title: String
    let count: Int
    let emptyTitle: String
    let emptyDetail: String
    let emptySystemImage: String
    @ViewBuilder let content: Content

    init(
        title: String,
        count: Int,
        emptyTitle: String,
        emptyDetail: String,
        emptySystemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.emptyTitle = emptyTitle
        self.emptyDetail = emptyDetail
        self.emptySystemImage = emptySystemImage
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(WeiBeiTheme.paperRaised.opacity(0.22))

            CourseHairline()

            if count == 0 {
                CourseEmptyState(
                    title: emptyTitle,
                    detail: emptyDetail,
                    systemImage: emptySystemImage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        content
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(WeiBeiTheme.paperRaised.opacity(0.10))
    }
}

private struct CourseDocNoteRow: View {
    let icon: String
    let title: String
    let detail: String
    let relationCount: Int
    let relationLabel: String
    let selected: Bool
    let linkedToCounterpart: Bool
    let select: () -> Void
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: select) {
                HStack(spacing: 11) {
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(
                            linkedToCounterpart
                                ? WeiBeiTheme.link
                                : (selected
                                    ? WeiBeiTheme.cinnabar
                                    : WeiBeiTheme.secondaryInk)
                        )
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .foregroundStyle(WeiBeiTheme.ink)
                            .lineLimit(1)
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(relationCount) \(relationLabel)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(
                            relationCount == 0
                                ? WeiBeiTheme.tertiaryInk
                                : WeiBeiTheme.link
                        )
                        .lineLimit(1)
                }
                .padding(.leading, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: open) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open")
            .padding(.trailing, 8)
        }
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(linkedToCounterpart ? WeiBeiTheme.link : WeiBeiTheme.cinnabar)
                    .frame(width: 2.5, height: 26)
                    .padding(.leading, 3)
            }
        }
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.hover, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if selected {
            return linkedToCounterpart
                ? WeiBeiTheme.link.opacity(0.075)
                : WeiBeiTheme.paperInset.opacity(0.36)
        }
        if linkedToCounterpart {
            return WeiBeiTheme.link.opacity(0.045)
        }
        if hovering {
            return WeiBeiTheme.paperInset.opacity(0.16)
        }
        return .clear
    }
}
