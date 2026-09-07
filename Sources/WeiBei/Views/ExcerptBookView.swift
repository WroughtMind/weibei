import SwiftUI
import WeiBeiCore

struct ExcerptBookButton: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        Button {
            store.excerptBookCourseID = store.activeCourseID
            store.excerptBookPresented = true
        } label: {
            Image(systemName: "text.book.closed")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 28))
        .help(store.ui("打开摘抄本", "Open excerpts"))
        .accessibilityLabel(Text(store.ui("摘抄本", "Excerpts")))
    }
}

/// One book per course. Passages remain independent of the editable notebook.
struct ExcerptBookView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let courseID: UUID?

    private var records: [SelectionRemarkRecord] { store.excerpts(in: courseID) }
    private var sourceIDs: [String] {
        var seen = Set<String>()
        return records.compactMap { record in
            let key = record.itemID ?? record.ownerTitle
            return seen.insert(key).inserted ? key : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(courseID.flatMap(store.course(withID:))?.title ?? store.ui("通用资料", "Common materials"))
                        .weiBeiText(12).foregroundStyle(WeiBeiTheme.secondaryInk)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(store.ui("摘抄本", "Excerpts")).weiBeiText(24, weight: .semibold)
                        Text(store.ui("\(records.count) 则 · \(sourceIDs.count) 篇文稿", "\(records.count) excerpts · \(sourceIDs.count) documents"))
                            .weiBeiText(11).foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(WeiBeiIconButtonStyle(size: 30))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text(store.ui("关闭摘抄本", "Close excerpts")))
            }
            .padding(24)
            Divider()
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.ui("读到想留下的句子，就记在这里。", "Keep passages you want to return to here."))
                        .weiBeiText(17, weight: .medium)
                    Text(store.ui("选中文稿里的文字，点「记」。原文和批注会按文稿归集。", "Select a passage and choose Remark. Excerpts and remarks are grouped by document."))
                        .weiBeiText(13).foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        ForEach(sourceIDs, id: \.self) { key in
                            let group = records.filter { ($0.itemID ?? $0.ownerTitle) == key }
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(group.first?.itemID.flatMap(store.item(withID:)).map(store.displayTitle(for:)) ?? group.first?.ownerTitle ?? "").weiBeiText(15, weight: .semibold)
                                    Spacer()
                                    Text("\(group.count)").weiBeiText(11).foregroundStyle(WeiBeiTheme.tertiaryInk)
                                }
                                .padding(.bottom, 8)
                                .overlay(alignment: .bottom) { Rectangle().fill(WeiBeiTheme.cinnabar.opacity(0.35)).frame(height: 1) }
                                ForEach(group) { record in
                                    ExcerptBookRow(record: record)
                                }
                            }
                        }
                    }
                    .padding(28)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 640, maxWidth: 760, minHeight: 420, idealHeight: 620)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper)
        .textSelection(.enabled)
        .accessibilityIdentifier("course-excerpt-book")
    }
}

private struct ExcerptBookRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let record: SelectionRemarkRecord
    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var saveFailed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.selectionText).weiBeiText(16).lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            if editing {
                TextField(store.ui("批注", "Remark"), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).weiBeiText(14).lineLimit(2...8)
                    .focused($focused)
                HStack {
                    Button(store.ui("保存批注", "Save remark")) {
                        saving = true
                        Task { @MainActor in
                            let saved = await store.updateExcerptRemark(record.id, text: draft)
                            saving = false
                            saveFailed = !saved
                            if saved { editing = false }
                        }
                    }.disabled(saving)
                    Button(store.ui("取消", "Cancel")) { editing = false }.disabled(saving)
                    if saveFailed { Text(store.ui("尚未保存，请重试", "Not saved; retry")).foregroundStyle(WeiBeiTheme.cinnabar) }
                }
            } else if !record.remarkText.isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(WeiBeiTheme.cinnabar).frame(width: 5, height: 5).padding(.top, 7)
                    Text(record.remarkText).weiBeiText(14).lineSpacing(4)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
            }
            HStack(spacing: 14) {
                Button(store.ui("回到原文", "View source")) {
                    store.openExcerptSource(record)
                }.disabled(record.itemID.flatMap(store.item(withID:)) == nil)
                Button(store.ui("编辑批注", "Edit remark")) { draft = record.remarkText; editing = true; focused = true }
                Spacer()
                Button(store.ui("加入笔记末尾", "Append to note")) {
                    store.appendExcerptToNote(record)
                    store.excerptBookPresented = false
                }
                .disabled(store.activeNoteItem == nil)
                .help(store.activeNoteItem == nil
                    ? store.ui("先打开要加入的笔记", "Open a note first")
                    : store.ui("加入「\(store.agentNoteTitle)」末尾", "Append to “\(store.agentNoteTitle)”"))
            }
            .weiBeiText(11).foregroundStyle(WeiBeiTheme.secondaryInk)
            .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 11, height: 28))
            Divider().padding(.top, 6)
        }
    }
}
