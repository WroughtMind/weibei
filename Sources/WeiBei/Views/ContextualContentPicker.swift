import SwiftUI
import WeiBeiCore

struct ContextualContentPicker: View {
    @EnvironmentObject private var store: WorkspaceStore
    let kind: ContextualContentKind
    @State private var courseEntry: CourseProjectEntryPresentation?
    @State private var choosingImportTarget = false

    private struct Group: Identifiable {
        let course: Course?
        let items: [StudyItem]
        var id: String { course?.id.uuidString ?? "common" }
    }

    private var groups: [Group] {
        var byCourse: [UUID: [StudyItem]] = [:]
        var common: [StudyItem] = []
        let items = store.allItems.filter { courseContextItemMatches($0, kind: kind) }.sorted {
            store.displayTitle(for: $0).localizedStandardCompare(store.displayTitle(for: $1)) == .orderedAscending
        }
        for item in items {
            for id in item.storage.ownerCourseID.map({ [$0] }) ?? store.courseMembershipIndex.courseIDs(for: item.id) {
                byCourse[id, default: []].append(item)
            }
            if case .common = item.storage { common.append(item) }
        }
        return store.courses.map { Group(course: $0, items: byCourse[$0.id] ?? []) }
            + [Group(course: nil, items: common)]
    }

    var body: some View {
        GeometryReader { geometry in
            let groups = groups
            let available = max(1, geometry.size.width - 40)
            let columns = min(groups.count, max(1, Int((min(available, 1140) + 16) / 200)))
            let width = min(available, CGFloat(columns) * 220 + CGFloat(columns - 1) * 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    globalActions
                    CoursePickerColumns(columns: columns, spacing: 16) {
                        ForEach(groups) { group in
                            courseBlock(group)
                        }
                    }
                }
                .frame(width: width)
                .padding(.top, min(100, max(28, geometry.size.height * 0.12)))
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background(WeiBeiTheme.paper)
        .sheet(item: $courseEntry) { presentation in
            CourseProjectEntrySheet(
                initialIntent: presentation.intent,
                cancel: { courseEntry = nil },
                openCourse: { _ in courseEntry = nil }
            ).environmentObject(store)
        }
        .sheet(isPresented: $choosingImportTarget) {
            VStack(alignment: .leading, spacing: 16) {
                Text(store.ui("导入到哪里？", "Import into…")).weiBeiText(17, weight: .semibold)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(commonTitle) { importFiles(into: nil) }
                        ForEach(store.courses) { course in
                            Button(course.title) { importFiles(into: course.id) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 300)
                HStack { Spacer(); Button(store.ui("取消", "Cancel")) { choosingImportTarget = false }.keyboardShortcut(.cancelAction) }
            }
            .buttonStyle(.plain)
            .padding(24)
            .frame(width: 320)
            .background(WeiBeiTheme.paper)
        }
        .accessibilityIdentifier(kind == .note ? "contextual-note-picker" : "contextual-material-picker")
    }

    private var commonTitle: String {
        kind == .note ? store.ui("通用笔记", "Common Notes") : store.ui("通用资料", "Common Materials")
    }

    private func courseBlock(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.course?.title ?? commonTitle)
                    .weiBeiText(14, weight: .semibold)
                    .lineLimit(2)
                Button {
                    if kind == .note {
                        if let id = group.course?.id { store.createBlankNotebookNote(in: id) }
                        else { store.createBlankNotebookNote(in: nil) }
                    } else {
                        importFiles(into: group.course?.id)
                    }
                } label: {
                    Image(systemName: "plus").weiBeiText(12, weight: .medium).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .accessibilityLabel(kind == .note ? store.ui("新建笔记", "New Note") : store.ui("导入资料", "Import Materials"))
                Spacer(minLength: 0)
            }
            if group.items.isEmpty {
                Text(kind == .note ? store.ui("还没有笔记", "No notes yet") : store.ui("还没有资料", "No materials yet"))
                    .weiBeiText(12).foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
            ForEach(group.items) { item in
                Button { store.openContextualItem(item.id, kind: kind) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: kind == .note ? "note.text" : "doc.text").weiBeiText(12)
                        Text(kind == .note ? store.noteListDisplayTitle(for: item) : store.displayTitle(for: item))
                            .weiBeiText(13).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.displayTitle(for: item))
                .contextMenu {
                    if let id = group.course?.id {
                        Button(store.ui("从本课程移除", "Remove from This Course")) { store.removeItem(item.id, fromCourseID: id) }
                    }
                    Button(store.ui("将原文件移到废纸篓…", "Move Source File to Trash…")) { store.confirmMoveItemSourceToTrash(item.id) }
                }
            }
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(courseWorkspaceAccent(colorIndex: group.course?.colorIndex ?? 3).opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
    }

    private var globalActions: some View {
        HStack(spacing: 12) {
            Button(store.ui("＋ 新建课程", "+ New Course")) { courseEntry = CourseProjectEntryPresentation(intent: .create) }
            Button(kind == .note ? store.ui("导入笔记…", "Import notes…") : store.ui("导入资料…", "Import materials…")) {
                choosingImportTarget = true
            }
        }
        .buttonStyle(.plain)
        .weiBeiText(11.5)
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importFiles(into courseID: UUID?) {
        choosingImportTarget = false
        // Let the target sheet dismiss before presenting the system file panel.
        DispatchQueue.main.async {
            if kind == .note { store.importCourseNotesFromPanel(courseID: courseID) }
            else { store.importCourseMaterialsFromPanel(courseID: courseID) }
        }
    }
}

/// Stable source order; each next course occupies the shortest column.
private struct CoursePickerColumns: Layout {
    let columns: Int
    let spacing: CGFloat

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columnWidth = max(1, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var heights = Array(repeating: CGFloat.zero, count: columns)
        return subviews.indices.map { index in
            let column = heights.indices.min(by: { heights[$0] < heights[$1] })!
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let rect = CGRect(x: CGFloat(column) * (columnWidth + spacing), y: heights[column], width: columnWidth, height: size.height)
            heights[column] += size.height + spacing
            return rect
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 220
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, rect) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY), anchor: .topLeading, proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
    }
}
