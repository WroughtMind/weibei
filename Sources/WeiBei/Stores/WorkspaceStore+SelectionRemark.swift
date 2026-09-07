import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    // MARK: - 记保存

    /// Saves the excerpt independently. The caller keeps its draft until persistence succeeds.
    @discardableResult
    func saveSelectionRemark(_ remark: String, for selection: SelectionContext, courseID requestedCourseID: UUID?) async -> Bool {
        let itemID = selection.itemID
            ?? (selection.source == .note ? activeNotebookItemID : selectedItemID)
        let existingRecord = selectionRemarkRecords.first { $0.id == selection.id }
        let courseID: UUID?
        if let existingRecord { courseID = existingRecord.courseID }
        else { courseID = itemID.flatMap { id in allItems.first { $0.id == id }?.storage.ownerCourseID } ?? requestedCourseID }
        let note = remark.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = SelectionAttachmentMerge.normalized(selection.text)
        if let index = selectionRemarkRecords.firstIndex(where: {
            guard $0.source == selection.source, $0.itemID == itemID else { return false }
            if $0.id == selection.id { return true }
            guard $0.courseID == courseID else { return false }
            if let anchor = selection.documentAnchor, $0.documentAnchor != nil {
                return anchor.matches($0.documentAnchor) && SelectionAttachmentMerge.normalized($0.selectionText) == normalized
            }
            return !normalized.isEmpty && SelectionAttachmentMerge.normalized($0.selectionText) == normalized
        }) {
            selectionRemarkRecords[index].remarkText = note
            selectionRemarkRecords[index].documentAnchor = selection.documentAnchor ?? selectionRemarkRecords[index].documentAnchor
            selectionRemarkRecords[index].createdAt = Date()
        } else {
            selectionRemarkRecords.insert(SelectionRemarkRecord(
                selectionText: selection.text,
                remarkText: note,
                courseID: courseID,
                source: selection.source,
                ownerTitle: selection.ownerTitle,
                itemID: itemID,
                documentAnchor: selection.documentAnchor
            ), at: 0)
        }
        return await persistWorkspaceNow()
    }

    func excerpts(in courseID: UUID?) -> [SelectionRemarkRecord] {
        selectionRemarkRecords.filter { excerptCourseID(for: $0) == courseID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func excerptCourseID(for record: SelectionRemarkRecord) -> UUID? {
        record.courseID ?? record.itemID.flatMap { id in allItems.first { $0.id == id }?.storage.ownerCourseID }
    }

    func openExcerptBook(courseID: UUID?, at recordID: UUID? = nil) {
        excerptBookCourseID = courseID
        excerptBookTargetRecordID = recordID
        dismissFloatingSelectionAgent()
        excerptBookPresented = true
    }

    func updateExcerptRemark(_ recordID: UUID, text: String) async -> Bool {
        guard let index = selectionRemarkRecords.firstIndex(where: { $0.id == recordID }) else { return false }
        selectionRemarkRecords[index].remarkText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return await persistWorkspaceNow()
    }

    /// 当前材料的记留痕(第三/四刀渲染原文朱砂标记用)。
    func selectionRemarkRecords(forItemID itemID: String?) -> [SelectionRemarkRecord] {
        guard let itemID else { return selectionRemarkRecords }
        let courseID = allItems.first { $0.id == itemID }?.storage.ownerCourseID ?? activeCourseID
        return selectionRemarkRecords.filter { $0.itemID == itemID && ($0.courseID == nil || $0.courseID == courseID) }
    }

    /// 点击原文标记先查看已存批注；只有主动编辑才请求输入焦点。
    func openSelectionRemarkRecord(_ recordID: String, anchor: SelectionPopoverAnchor?) {
        guard let record = selectionRemarkRecords.first(where: { $0.id.uuidString == recordID }) else { return }
        excerptRevealRequest = nil
        keepFloatingSelectionForAnswer = true
        selectionContext = SelectionContext(
            id: record.id,
            text: record.selectionText,
            source: record.source,
            ownerTitle: record.ownerTitle,
            itemID: record.itemID,
            documentAnchor: record.documentAnchor
        )
        selectionAnchor = anchor
        interaction.floatingComposerMode = .remark
        agentSurface = .selectionFloat
        keepFloatingSelectionForAnswer = true
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
