import Foundation

@MainActor
extension WorkspaceStore {
    /// 选区"记"保存:空札记=纯摘录(与 appendSelectionToNote 同构),有札记=引用块+一句话。
    /// 走既有 insertMarkdown + focus(.notes) 通道,不切布局。
    func saveSelectionRemark(_ remark: String) {
        guard let selection = selectionContext else { return }
        let note = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        var block = "\n\(quotedReferenceBlock(text: selection.text, sourceTitle: selection.ownerTitle))"
        if !note.isEmpty {
            block += "\n\n\(note)"
        }
        noteEditorCommand = NoteEditorCommand(kind: .insertMarkdown, markdown: block)
        focus(.notes)
    }
}
