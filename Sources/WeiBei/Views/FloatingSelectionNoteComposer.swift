import SwiftUI

enum FloatingSelectionMode {
    case ask
    case note
}

struct FloatingSelectionNoteComposer: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var draft: String
    let onSaved: () -> Void
    @FocusState private var focused: Bool
    @State private var includesLatestAnswer = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(store.ui("写下理解、疑问或联想；留空则只保存摘录", "Write a thought, question, or connection; leave blank to save only the excerpt"))
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(0.72))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.system(size: 13.5))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 96, maxHeight: 168)
            }
            .padding(6)
            .background(WeiBeiTheme.paper, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(WeiBeiTheme.hairline.opacity(0.55))
            }

            HStack {
                Text(store.ui("原文会自动排在札记前面", "The source passage stays above the note"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(0.76))
                Spacer()
                Button(saveTitle, action: save)
                .buttonStyle(.borderedProminent)
                .tint(WeiBeiTheme.cinnabar)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
            }
            if store.latestSelectionAnswer(for: store.activeSelectionThreadID) != nil {
                Toggle(store.ui("附上本轮 AI 回答", "Include the latest AI answer"), isOn: $includesLatestAnswer)
                    .toggleStyle(.checkbox).font(.system(size: 11.5)).foregroundStyle(WeiBeiTheme.secondaryInk)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear { focused = true }
    }

    private var saveTitle: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? store.ui("保存摘录", "Save excerpt")
            : store.ui("记下", "Save note")
    }

    private func save() {
        guard store.saveSelectionNote(draft, includeLatestAnswer: includesLatestAnswer) != nil else { return }
        draft = ""
        includesLatestAnswer = true
        onSaved()
    }
}
