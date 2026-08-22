import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    // MARK: - 记保存

    /// 选区"记"保存:空札记=纯摘录(与 appendSelectionToNote 同构),有札记=引用块+一句话。
    /// 走既有 insertMarkdown + focus(.notes) 通道,不切布局;同时留痕 selectionRemarkRecords。
    func saveSelectionRemark(_ remark: String) {
        guard let selection = selectionContext else { return }
        let note = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        var block = "\n\(quotedReferenceBlock(text: selection.text, sourceTitle: selection.ownerTitle))"
        if !note.isEmpty {
            block += "\n\n\(note)"
        }
        noteEditorCommand = NoteEditorCommand(kind: .insertMarkdown, markdown: block)
        focus(.notes)
        recordSelectionRemark(selection, remark: note)
    }

    /// 留痕"这段原文被记过";同锚点/同文的重复记录只刷新时间与札记内容。
    private func recordSelectionRemark(_ selection: SelectionContext, remark: String) {
        let itemID = selection.itemID
            ?? (selection.source == .note ? activeNotebookItemID : selectedItemID)
        let normalized = SelectionAttachmentMerge.normalized(selection.text)
        if let index = selectionRemarkRecords.firstIndex(where: {
            selection.documentAnchor?.matches($0.documentAnchor) == true
                || ($0.selectionText == selection.text && $0.itemID == itemID && normalized.isEmpty == false
                    && SelectionAttachmentMerge.normalized($0.selectionText) == normalized)
        }) {
            selectionRemarkRecords[index].remarkText = remark
            selectionRemarkRecords[index].documentAnchor = selectionRemarkRecords[index].documentAnchor ?? selection.documentAnchor
            selectionRemarkRecords[index].createdAt = Date()
        } else {
            selectionRemarkRecords.insert(
                SelectionRemarkRecord(
                    selectionText: selection.text,
                    remarkText: remark,
                    source: selection.source,
                    ownerTitle: selection.ownerTitle,
                    itemID: itemID,
                    documentAnchor: selection.documentAnchor
                ),
                at: 0
            )
        }
        if selectionRemarkRecords.count > 200 {
            selectionRemarkRecords = Array(selectionRemarkRecords.prefix(200))
        }
        save()
    }

    /// 当前材料的记留痕(第三/四刀渲染原文朱砂标记用)。
    func selectionRemarkRecords(forItemID itemID: String?) -> [SelectionRemarkRecord] {
        guard let itemID else { return selectionRemarkRecords }
        return selectionRemarkRecords.filter { $0.itemID == nil || $0.itemID == itemID }
    }

    // MARK: - 自 WorkspaceStore.swift 原样搬入(冻结行数抵扣,行为未变)

    func lastAgentAnswerContentForCurrentNote() -> String? {
        lastUsableAgentAnswer?.text
    }

    func noteBlockForAgentAnswer(_ answer: String) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.hasPrefix("#") else { return text }
        return "## \(ui("整理建议", "Organization suggestion"))\n\(text)"
    }
}
