import SwiftUI
import WeiBeiCore

struct ExcerptNotebookView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let materialID: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.ui("按原文顺序", "Source order"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer()
                Button(store.ui("恢复原文顺序", "Restore source order")) {
                    store.restoreExcerptSourceOrder(for: materialID)
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(WeiBeiTheme.cinnabar)
            }
            .padding(.horizontal, 22).frame(height: 36)
            Divider().opacity(0.45)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.orderedExcerptThreads(for: materialID)) { thread in
                        excerpt(thread)
                            .draggable(thread.id.uuidString)
                            .dropDestination(for: String.self) { ids, _ in
                                guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                                store.moveExcerptThread(id, before: thread.id, materialID: materialID)
                                return true
                            }
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 18)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
        .background(WeiBeiTheme.paper)
    }

    private func excerpt(_ thread: SelectionThread) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(WeiBeiTheme.cinnabar).frame(width: 3, height: 18)
                Text(thread.selectionText).font(.system(size: 14, design: .serif))
                    .foregroundStyle(WeiBeiTheme.secondaryInk).textSelection(.enabled)
            }
            ForEach(Array(thread.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().frame(width: 72) }
                Text(entry.text).font(.system(size: 15)).foregroundStyle(WeiBeiTheme.ink).textSelection(.enabled)
            }
            ForEach(thread.answerAttachments) { attachment in
                SelectionAnswerAttachmentView(attachment: attachment)
            }
        }
        .padding(.vertical, 18).contentShape(Rectangle())
        .overlay(alignment: .bottom) { Divider().opacity(0.55) }
    }
}

private struct SelectionAnswerAttachmentView: View {
    let attachment: SelectionAIAnswerAttachment
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !attachment.question.isEmpty {
                    Text(attachment.question).font(.system(size: 12, weight: .medium)).foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                Text(attachment.answer).font(.system(size: 13)).foregroundStyle(WeiBeiTheme.ink).textSelection(.enabled)
            }
            .padding(.top, 8)
        } label: {
            Text("AI 回答").font(.system(size: 11, weight: .semibold)).foregroundStyle(WeiBeiTheme.cinnabar)
        }
        .onHover { expanded = $0 }
    }
}
