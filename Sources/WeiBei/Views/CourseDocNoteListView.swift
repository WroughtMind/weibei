import SwiftUI
import WeiBeiCore

/// Course-local, list-first management for the durable Document ↔ Note links.
///
/// Course membership, Chat associations, and learning memory are deliberately
/// kept out of this surface. Toggling a row only changes `NoteSourceLink` data.
struct CourseDocNoteListView: View {
    @EnvironmentObject private var store: WorkspaceStore

    @Binding var lens: CourseRelationLens
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    let isCompact: Bool

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

    private var selectedItem: StudyItem? {
        switch lens {
        case .materials:
            if let selectedMaterialID,
               let item = documents.first(where: { $0.id == selectedMaterialID }) {
                return item
            }
            return documents.first
        case .notes:
            if let selectedNoteID,
               let item = notes.first(where: { $0.id == selectedNoteID }) {
                return item
            }
            return notes.first
        }
    }

    var body: some View {
        GeometryReader { proxy in
            if documents.isEmpty && notes.isEmpty {
                emptyCourse
            } else if isCompact || proxy.size.width < 760 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        itemList
                        CourseHairline()
                        inspector
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        itemList
                    }
                    .frame(width: min(380, max(310, proxy.size.width * 0.34)))
                    .background(WeiBeiTheme.paperRaised.opacity(0.16))

                    CourseHairline(axis: .vertical)

                    inspector
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(WeiBeiTheme.paper)
        .onAppear(perform: ensureSelection)
        .onChange(of: documents.map(\.id)) { _, _ in
            ensureSelection()
        }
        .onChange(of: notes.map(\.id)) { _, _ in
            ensureSelection()
        }
    }

    private var emptyCourse: some View {
        CourseEmptyState(
            title: store.ui(
                "这门课还没有文档或笔记",
                "This course has no documents or notes"
            ),
            detail: store.ui(
                "从右上角“添加”导入文档，或新建、导入一篇笔记。",
                "Use Add to import a document, or create or import a note."
            ),
            systemImage: "doc.text",
            alignment: .center
        )
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 22) {
            itemSection(
                title: store.ui("文档", "Documents"),
                count: documents.count,
                items: documents,
                kind: .materials
            )

            itemSection(
                title: store.ui("笔记", "Notes"),
                count: notes.count,
                items: notes,
                kind: .notes
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func itemSection(
        title: String,
        count: Int,
        items: [StudyItem],
        kind: CourseRelationLens
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(WeiBeiTypography.brandFont(
                        language: store.interfaceLanguage,
                        size: 13,
                        weight: .semibold
                    ))
                    .foregroundStyle(WeiBeiTheme.ink)

                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)

                Spacer(minLength: 0)
            }

            if items.isEmpty {
                Text(kind == .materials
                     ? store.ui(
                        "还没有文档。可从右上角“添加”导入。",
                        "No documents yet. Import one from Add."
                     )
                     : store.ui(
                        "还没有笔记。新建或导入笔记后即可建立关联。",
                        "No notes yet. Create or import one to start linking."
                     ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        WeiBeiTheme.paperInset.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            } else {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        CourseDocNoteRow(
                            icon: kind == .notes ? "note.text" : item.kind.systemImage,
                            title: store.displayTitle(for: item),
                            detail: rowDetail(for: item, kind: kind),
                            relationCount: relationCount(for: item, kind: kind),
                            selected: isSelected(item, kind: kind)
                        ) {
                            select(item, kind: kind)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    inspectorHeader(for: selectedItem)
                    CourseHairline()
                    relationshipEditor(for: selectedItem)
                }
                .padding(isCompact ? 18 : 28)
                .frame(maxWidth: 720, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            CourseEmptyState(
                title: store.ui("选择一个文档或笔记", "Select a document or note"),
                detail: store.ui(
                    "选择后可查看并维护它的长期 Doc ↔ Note 关联。",
                    "Select an item to inspect and maintain its durable Document ↔ Note links."
                ),
                systemImage: "link",
                alignment: .center
            )
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }

    private func inspectorHeader(for item: StudyItem) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(lens == .materials ? "DOCUMENT" : "NOTE")
                    .font(WeiBeiTypography.englishBrandFont(size: 9.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(WeiBeiTheme.cinnabar)

                Text(store.displayTitle(for: item))
                    .font(WeiBeiTypography.brandFont(
                        language: store.interfaceLanguage,
                        size: 20,
                        weight: .semibold
                    ))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                let subtitle = store.displaySubtitle(for: item)
                if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 14)

            Button(store.ui("打开", "Open")) {
                open(item)
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
    }

    private func relationshipEditor(for item: StudyItem) -> some View {
        let counterparts = lens == .materials ? notes : documents
        let heading = lens == .materials
            ? store.ui("关联的笔记", "Linked notes")
            : store.ui("关联的文档", "Linked documents")

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(heading)
                        .font(WeiBeiTypography.brandFont(
                            language: store.interfaceLanguage,
                            size: 14,
                            weight: .semibold
                        ))
                        .foregroundStyle(WeiBeiTheme.ink)

                    Text("\(relationCount(for: item, kind: lens))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }

                Text(store.ui(
                    "勾选只会建立文档与笔记的长期关联；不会改变课程归属、当前 Chat 或课程记忆。",
                    "Checking an item only changes the durable Document ↔ Note link. It does not change course membership, the current Chat, or course memory."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            if counterparts.isEmpty {
                relationshipEmptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(counterparts) { counterpart in
                        CourseDocNoteLinkRow(
                            icon: lens == .materials
                                ? "note.text"
                                : counterpart.kind.systemImage,
                            title: store.displayTitle(for: counterpart),
                            detail: counterpartDetail(counterpart),
                            linked: isLinked(item, to: counterpart)
                        ) {
                            toggleLink(item, counterpart: counterpart)
                        }

                        if counterpart.id != counterparts.last?.id {
                            CourseHairline().padding(.leading, 42)
                        }
                    }
                }
                .background(
                    WeiBeiTheme.paperRaised.opacity(0.24),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WeiBeiTheme.hairline.opacity(0.64), lineWidth: 1)
                }
            }
        }
    }

    private var relationshipEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lens == .materials
                 ? store.ui(
                    "这门课还没有笔记",
                    "This course has no notes yet"
                 )
                 : store.ui(
                    "这门课还没有文档",
                    "This course has no documents yet"
                 ))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)

            Text(lens == .materials
                 ? store.ui(
                    "新建或导入笔记后，就能在这里把它连接回当前文档。",
                    "Create or import a note, then connect it back to this document here."
                 )
                 : store.ui(
                    "导入文档后，就能在这里把当前笔记连接到它的来源。",
                    "Import a document, then connect this note to its source here."
                 ))
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            WeiBeiTheme.paperInset.opacity(0.20),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private func rowDetail(for item: StudyItem, kind: CourseRelationLens) -> String {
        let count = relationCount(for: item, kind: kind)
        let relationText = store.ui("\(count) 条关联", "\(count) links")
        if kind == .notes {
            return store.ui("课程笔记 · \(relationText)", "Course note · \(relationText)")
        }
        return "\(item.kind.label(language: store.interfaceLanguage)) · \(relationText)"
    }

    private func counterpartDetail(_ item: StudyItem) -> String {
        if lens == .materials {
            return store.ui("课程笔记", "Course note")
        }
        return item.kind.label(language: store.interfaceLanguage)
    }

    private func relationCount(for item: StudyItem, kind: CourseRelationLens) -> Int {
        switch kind {
        case .materials:
            return store.linkedNoteIDs(for: item.id)
                .lazy
                .filter { noteIDs.contains($0) }
                .count
        case .notes:
            return store.linkedCourseSourceIDs(for: item.id)
                .lazy
                .filter { documentIDs.contains($0) }
                .count
        }
    }

    private func isSelected(_ item: StudyItem, kind: CourseRelationLens) -> Bool {
        switch kind {
        case .materials:
            return lens == .materials && selectedMaterialID == item.id
        case .notes:
            return lens == .notes && selectedNoteID == item.id
        }
    }

    private func select(_ item: StudyItem, kind: CourseRelationLens) {
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

    private func open(_ item: StudyItem) {
        guard let courseID else { return }
        switch lens {
        case .materials:
            selectedMaterialID = item.id
            _ = store.openCourseMaterial(item.id, in: courseID)
        case .notes:
            selectedNoteID = item.id
            store.openCourseNote(item.id, in: courseID)
        }
    }

    private func isLinked(_ item: StudyItem, to counterpart: StudyItem) -> Bool {
        switch lens {
        case .materials:
            return store.linkedNoteIDs(for: item.id).contains(counterpart.id)
        case .notes:
            return store.linkedCourseSourceIDs(for: item.id).contains(counterpart.id)
        }
    }

    private func toggleLink(_ item: StudyItem, counterpart: StudyItem) {
        switch lens {
        case .materials:
            var linkedNoteIDs = Set(store.linkedNoteIDs(for: item.id))
            if linkedNoteIDs.contains(counterpart.id) {
                linkedNoteIDs.remove(counterpart.id)
            } else {
                linkedNoteIDs.insert(counterpart.id)
            }
            store.setLinkedNoteIDs(linkedNoteIDs, for: item.id)
            selectedMaterialID = item.id
            selectedNoteID = counterpart.id
        case .notes:
            var linkedDocumentIDs = Set(store.linkedCourseSourceIDs(for: item.id))
            if linkedDocumentIDs.contains(counterpart.id) {
                linkedDocumentIDs.remove(counterpart.id)
            } else {
                linkedDocumentIDs.insert(counterpart.id)
            }
            store.setLinkedCourseSourceIDs(linkedDocumentIDs, for: item.id)
            selectedNoteID = item.id
            selectedMaterialID = counterpart.id
        }
    }

    private func ensureSelection() {
        switch lens {
        case .materials:
            if let selectedMaterialID,
               documents.contains(where: { $0.id == selectedMaterialID }) {
                return
            }
        case .notes:
            if let selectedNoteID,
               notes.contains(where: { $0.id == selectedNoteID }) {
                return
            }
        }

        if let firstDocument = documents.first {
            lens = .materials
            selectedMaterialID = firstDocument.id
            selectedNoteID = nil
        } else if let firstNote = notes.first {
            lens = .notes
            selectedNoteID = firstNote.id
            selectedMaterialID = nil
        } else {
            selectedMaterialID = nil
            selectedNoteID = nil
        }
    }
}

private struct CourseDocNoteRow: View {
    let icon: String
    let title: String
    let detail: String
    let relationCount: Int
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
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

                if relationCount == 0 {
                    Circle()
                        .stroke(WeiBeiTheme.tertiaryInk.opacity(0.56), lineWidth: 1)
                        .frame(width: 7, height: 7)
                } else {
                    Text("\(relationCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.link)
                        .frame(minWidth: 18)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .background(
                selected
                    ? WeiBeiTheme.cinnabarSoft.opacity(0.30)
                    : (hovering ? WeiBeiTheme.paperInset.opacity(0.18) : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(WeiBeiTheme.cinnabar)
                        .frame(width: 2, height: 24)
                        .padding(.leading, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.hover, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CourseDocNoteLinkRow: View {
    @EnvironmentObject private var store: WorkspaceStore

    let icon: String
    let title: String
    let detail: String
    let linked: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: linked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(linked ? WeiBeiTheme.moss : WeiBeiTheme.tertiaryInk)
                    .frame(width: 20)

                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(linked
                     ? store.ui("已关联", "Linked")
                     : store.ui("未关联", "Not linked"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(linked ? WeiBeiTheme.moss : WeiBeiTheme.tertiaryInk)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
            .background(hovering ? WeiBeiTheme.paperInset.opacity(0.16) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(WeiBeiMotion.hover, value: hovering)
        .accessibilityValue(Text(
            linked
                ? store.ui("已关联", "Linked")
                : store.ui("未关联", "Not linked")
        ))
    }
}