import SwiftUI
import WeiBeiCore

struct ExcerptBookButton: View {
    @EnvironmentObject private var store: WorkspaceStore
    var itemID: String? = nil

    var body: some View {
        Button {
            let record = itemID.flatMap { store.selectionRemarkRecords(forItemID: $0).first }
            store.openExcerptBook(
                courseID: record.map { store.excerptCourseID(for: $0) } ?? store.activeCourseID,
                at: record?.id
            )
        } label: {
            Image(systemName: "text.book.closed")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 28))
        .help(store.ui(itemID == nil ? "摘抄本" : "本篇摘抄", itemID == nil ? "Excerpts" : "Document excerpts"))
        .accessibilityLabel(Text(store.ui("摘抄本", "Excerpts")))
    }
}

struct ExcerptBookView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let courseID: UUID?

    var body: some View {
        let groups = Dictionary(grouping: store.excerpts(in: courseID), by: \.excerptSourceKey)
            .mapValues { $0.sorted(by: SelectionRemarkRecord.inDocumentOrder) }
        let sources = groups.keys.sorted {
            let order = sourceTitle(groups[$0]?.first).localizedStandardCompare(sourceTitle(groups[$1]?.first))
            return order == .orderedSame ? $0 < $1 : order == .orderedAscending
        }
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(courseID.flatMap(store.course(withID:))?.title ?? store.ui("通用资料", "Common materials"))
                        .weiBeiText(20, weight: .medium, design: .serif).lineLimit(1)
                    Spacer()
                    if !sources.isEmpty {
                        Menu {
                            ForEach(sources, id: \.self) { source in
                                Button(sourceTitle(groups[source]?.first)) {
                                    if let record = groups[source]?.first {
                                        withAnimation(WeiBeiMotion.panel) { proxy.scrollTo(record.id, anchor: .top) }
                                    }
                                }
                            }
                        } label: { Image(systemName: "list.bullet").foregroundStyle(WeiBeiTheme.secondaryInk) }
                        .menuStyle(.button).menuIndicator(.hidden)
                        .buttonStyle(WeiBeiIconButtonStyle(size: 28))
                        .help(store.ui("文稿目录", "Documents"))
                        .accessibilityLabel(Text(store.ui("文稿目录", "Documents")))
                    }
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(WeiBeiIconButtonStyle(size: 30))
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel(Text(store.ui("关闭摘抄本", "Close excerpts")))
                }
                .padding(.horizontal, 28).padding(.vertical, 18)
                Divider().opacity(0.55)
                if sources.isEmpty {
                    Text(store.ui("还没有摘抄", "No excerpts yet"))
                        .weiBeiText(14).foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sources, id: \.self) { source in
                                ForEach(Array((groups[source] ?? []).enumerated()), id: \.element.id) { index, record in
                                    HStack(alignment: .top, spacing: 28) {
                                        Group {
                                            if index == 0 {
                                                Text(sourceTitle(record)).weiBeiText(12.5, weight: .medium).lineSpacing(5)
                                                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                                                    .padding(.top, 7)
                                            } else {
                                                Color.clear.frame(height: 1)
                                            }
                                        }
                                        .frame(width: 126, alignment: .leading)
                                        ExcerptBookRow(record: record, selected: store.excerptBookTargetRecordID == record.id)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.top, index == 0 ? 36 : 26)
                                    .id(record.id)
                                }
                            }
                        }
                        .padding(.horizontal, 28).padding(.bottom, 40)
                    }
                    .onAppear {
                        if let target = store.excerptBookTargetRecordID { proxy.scrollTo(target, anchor: .center) }
                    }
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 800, maxWidth: 920, minHeight: 440, idealHeight: 640)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper)
        .accessibilityLabel(Text(store.ui("摘抄本", "Excerpts")))
        .accessibilityIdentifier("course-excerpt-book")
    }

    private func sourceTitle(_ record: SelectionRemarkRecord?) -> String {
        guard let record else { return "" }
        if let item = record.itemID.flatMap(store.item(withID:)) { return store.displayTitle(for: item) }
        return record.ownerTitle
    }
}

private struct ExcerptBookRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let record: SelectionRemarkRecord
    var selected: Bool
    @State private var editing = false
    @State private var hovering = false
    @FocusState private var menuFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Text(record.selectionText).weiBeiText(18, design: .serif).lineSpacing(7)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu { actions } label: { Image(systemName: "ellipsis").foregroundStyle(WeiBeiTheme.secondaryInk) }
                    .menuStyle(.button).menuIndicator(.hidden)
                    .buttonStyle(WeiBeiIconButtonStyle(size: 28))
                    .focused($menuFocused)
                    .opacity(hovering || menuFocused ? 1 : 0)
                    .accessibilityLabel(Text(store.ui("摘抄操作", "Excerpt actions")))
            }
            if editing {
                ExcerptRemarkEditor(record: record) { editing = false }
            } else if !record.remarkText.isEmpty {
                Text(record.remarkText).weiBeiText(13.5).lineSpacing(5)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .textSelection(.enabled)
                    .padding(.leading, 13)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(WeiBeiTheme.cinnabar.opacity(0.55)).frame(width: 1)
                    }
            }
            if let page = record.documentAnchor?.pdf?.pageIndex {
                Button(store.ui("第 \(page + 1) 页", "Page \(page + 1)")) { store.openExcerptSource(record) }
                    .buttonStyle(.plain).weiBeiText(10.5).foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .disabled(record.itemID.flatMap(store.item(withID:)) == nil)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            if selected {
                Circle().fill(WeiBeiTheme.cinnabar).frame(width: 5, height: 5).offset(x: -18)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { actions }
    }

    @ViewBuilder private var actions: some View {
        Button(store.ui("回到原文", "View source")) { store.openExcerptSource(record) }
            .disabled(record.itemID.flatMap(store.item(withID:)) == nil)
        Button(store.ui("编辑批注", "Edit remark")) { editing = true }
    }
}

struct ExcerptRemarkPopover: View {
    @EnvironmentObject private var store: WorkspaceStore
    let record: SelectionRemarkRecord
    var close: () -> Void
    @State private var editing = false
    @State private var textHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editing {
                ExcerptRemarkEditor(record: record) { editing = false }
            } else {
                ScrollView {
                    Text(record.remarkText.isEmpty ? store.ui("已摘抄", "Excerpt saved") : record.remarkText)
                        .weiBeiText(14).lineSpacing(5)
                        .foregroundStyle(record.remarkText.isEmpty ? WeiBeiTheme.secondaryInk : WeiBeiTheme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ExcerptPopoverTextHeight.self, value: proxy.size.height)
                        })
                }
                .frame(height: min(max(textHeight, 24), 240))
                .onPreferenceChange(ExcerptPopoverTextHeight.self) { textHeight = $0 }
            }
            HStack(spacing: 3) {
                Button {
                    store.openExcerptBook(courseID: store.excerptCourseID(for: record), at: record.id)
                } label: { Image(systemName: "text.book.closed") }
                .help(store.ui("在摘抄本中查看", "Show in excerpts"))
                .accessibilityLabel(Text(store.ui("在摘抄本中查看", "Show in excerpts")))
                Spacer()
                if !editing {
                    Button { editing = true } label: { Image(systemName: "pencil") }
                        .help(store.ui("编辑批注", "Edit remark"))
                        .accessibilityLabel(Text(store.ui("编辑批注", "Edit remark")))
                }
                Button(action: close) { Image(systemName: "xmark") }
                    .help(store.ui("关闭", "Close"))
                    .accessibilityLabel(Text(store.ui("关闭", "Close")))
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 28))
        }
        .padding(14).frame(width: 340)
        .accessibilityIdentifier("excerpt-remark-preview")
    }
}

private struct ExcerptRemarkEditor: View {
    @EnvironmentObject private var store: WorkspaceStore
    let record: SelectionRemarkRecord
    var finish: () -> Void
    @State private var draft: String
    @State private var saving = false
    @State private var failed = false

    init(record: SelectionRemarkRecord, finish: @escaping () -> Void) {
        self.record = record
        self.finish = finish
        _draft = State(initialValue: record.remarkText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SelectionRemarkField(text: $draft) {
                guard !saving else { return }
                saving = true
                Task { @MainActor in
                    let saved = await store.updateExcerptRemark(record.id, text: draft)
                    saving = false
                    failed = !saved
                    if saved { finish() }
                }
            }
            .disabled(saving)
            HStack {
                Button(store.ui("取消", "Cancel"), action: finish).disabled(saving)
                    .buttonStyle(.plain)
                if failed { Text(store.ui("尚未保存，请重试", "Not saved; retry")).foregroundStyle(WeiBeiTheme.cinnabar) }
            }
            .weiBeiText(11).foregroundStyle(WeiBeiTheme.secondaryInk)
        }
        .weiBeiOnExitCommand(perform: finish)
    }
}

private struct ExcerptPopoverTextHeight: PreferenceKey {
    static let defaultValue: CGFloat = 24
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
