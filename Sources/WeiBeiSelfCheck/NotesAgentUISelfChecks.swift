import AppKit
import Foundation
import WeiBeiCore

/**
 * 验证笔记、阅读器选择和 Agent 界面源码契约。
 */
enum NotesAgentUISelfChecks {
    /**
     * 执行该领域的自检。
     */
    @MainActor
    static func run() throws {
        let offlineChinesePreview = AgentOfflinePreview.render(
            AgentOfflinePreviewInput(
                language: .chinese,
                question: "解释利率为什么是资金价格",
                hasMaterial: true,
                materialTitle: "Mishkin 教材样例",
                materialText: "利率是资金使用价格的表达。金融市场通过利率配置资源。",
                noteTitle: "货币金融学课程 HTML",
                noteText: "## 摘录\n来源：Mishkin 教材样例",
                selectionTitle: "已选文本片段",
                selectionText: "利率是资金使用价格的表达。"
            )
        )
        let offlineEnglishPreview = AgentOfflinePreview.render(
            AgentOfflinePreviewInput(
                language: .english,
                question: "Explain the selected sentence",
                hasMaterial: false,
                materialTitle: "No document",
                materialText: "",
                noteTitle: "Current note",
                noteText: "",
                selectionTitle: nil,
                selectionText: nil
            )
        )

        // WP9: 行文进行中 V3 loading motion — no three-dot pulse card; hang-proof AppKit orbit.
        // Deleted overlay views (drawer / corner / quiet insight / compact previews) are gone.
        expect(LibraryNavigator.adjacentID(in: [], selectedID: nil, step: 1) == nil, "library navigation empty")
        expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: nil, step: 1) == "a", "library navigation defaults first")
        expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "b", step: 1) == "c", "library navigation next")
        expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "a", step: -1) == "c", "library navigation wraps previous")

        expect(SelectionContext(text: "文档", source: .document, ownerTitle: "资料").isNoteSelection == false, "document selection is read-only")
        expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isNoteSelection == true, "note selection is replaceable")
        expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isReplaceableNoteSelection, "editable note selection can be replaced")
        expect(!SelectionContext(text: "预览", source: .note, ownerTitle: "资料", isEditable: false).isReplaceableNoteSelection, "preview note selection is not replaceable")
        expect(SelectionAttachmentMerge.mergedText(existing: "当前笔记已经覆盖材", incoming: "开头。建议检查是否写了来源、例子和待追问。", withinSelectionGesture: true) == "当前笔记已经覆盖材开头。建议检查是否写了来源、例子和待追问。", "same-gesture selection attachment stitches split live selection fragments into one attachment")
        expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用", incoming: "使用价格的表达", withinSelectionGesture: true) == "利率是资金使用价格的表达", "same-gesture overlapping fragments merge without duplicate overlap text")
        expect(SelectionAttachmentMerge.mergedText(existing: "你们", incoming: "好", withinSelectionGesture: true) == "你们好", "same-gesture single-character live-selection fragments merge into one human selection")
        expect(SelectionAttachmentMerge.mergedText(existing: "开头。建议检查是否写了来源。", incoming: "你们好", withinSelectionGesture: true) == "开头。建议检查是否写了来源。你们好", "same-gesture short trailing live-selection fragments still merge after sentence punctuation")
        expect(SelectionAttachmentMerge.mergedText(existing: "利率", incoming: "利率是资金使用价格", withinSelectionGesture: false) == "利率是资金使用价格", "selection attachment merge still replaces a shorter contained selection with the fuller text")
        expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格。", incoming: "通货膨胀预期会改变真实利率。", withinSelectionGesture: true) == nil, "same-gesture selection attachment does not blindly stitch separate complete sentences")
        expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格", incoming: "通货膨胀预期", withinSelectionGesture: false) == nil, "separate selections outside one gesture remain separate fragments")
        expect(SelectionAttachmentMerge.containsSelection("当前笔记已经覆盖材料开头。建议检查是否写了来源。", fragment: "材料 开头。")
            && !SelectionAttachmentMerge.containsSelection("利率是资金使用价格", fragment: ""), "selection attachment containment ignores whitespace and rejects empty fragments")
        expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: true) == 20, "flipped content view keeps selection y")
        expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: false) == 80, "non-flipped content view converts selection y")
        expect(!SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false), "selection agent waits for anchor before floating")
        expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: true, pinned: false), "selection agent appears when anchored")
        expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false, keepOpen: true), "keepOpen floats stay visible without a live drag anchor")
        expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: false, hasAnchor: false, pinned: true), "pinned floats stay visible without selection")
        expect(SelectionFloatingAgentPlacement.expandedHalfWidth == 230 && SelectionFloatingAgentPlacement.compactHalfWidth == 82, "selection agent placement constants match the compact and expanded surfaces")
        let floatingPoint = SelectionFloatingAgentPlacement.position(
            anchor: FloatingAgentCoordinate(x: 320, y: 200),
            canvas: FloatingAgentCoordinate(x: 1200, y: 800)
        )
        let topInsetFloatingPoint = SelectionFloatingAgentPlacement.position(
            anchor: FloatingAgentCoordinate(x: 320, y: 200),
            canvas: FloatingAgentCoordinate(x: 1200, y: 800),
            topInset: 42
        )
        expect(floatingPoint.x == 562 && floatingPoint.y == 245.5, "selection agent opens close beside the text anchor")
        expect(topInsetFloatingPoint.x == 562 && topInsetFloatingPoint.y == 228, "selection agent compensates top bar coordinate space")
        let compactEdgeFloatingPoint = SelectionFloatingAgentPlacement.position(
            anchor: FloatingAgentCoordinate(x: 12, y: 200),
            canvas: FloatingAgentCoordinate(x: 1200, y: 800),
            surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
            prefersAnchorCenter: true
        )
        let compactCenterFloatingPoint = SelectionFloatingAgentPlacement.position(
            anchor: FloatingAgentCoordinate(x: 320, y: 200),
            canvas: FloatingAgentCoordinate(x: 1200, y: 800),
            surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
            prefersAnchorCenter: true
        )
        expect(compactCenterFloatingPoint.x == 320 && compactCenterFloatingPoint.y == 210, "selection prompt centers on the text anchor when compact")
        expect(compactEdgeFloatingPoint.x == 100 && compactEdgeFloatingPoint.y == 210, "selection prompt clamps only at the edge when compact")
        let edgeFloatingPoint = SelectionFloatingAgentPlacement.position(
            anchor: FloatingAgentCoordinate(x: 1160, y: 760),
            canvas: FloatingAgentCoordinate(x: 1200, y: 800)
        )
        expect(edgeFloatingPoint.x == 918 && edgeFloatingPoint.y == 572, "selection agent flips to the left of text near the window edge")
        expect(AgentMessage(role: .assistant, text: "整理完成", source: nil).isUsableAgentAnswer, "usable agent answer")
        expect(!AgentMessage(role: .assistant, text: "未配置密钥。", source: nil).isUsableAgentAnswer, "credential setup message is not writable")
        expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY。", source: nil).isUsableAgentAnswer, "api key setup message is not writable")
        expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY 或钥匙串密钥。", source: nil).isUsableAgentAnswer, "keychain setup message is not writable")
        expect(AgentMessage(role: .assistant, text: offlineChinesePreview, source: nil).isUsableAgentAnswer, "offline draft is visible in chat and writable to notes")
        expect(AgentMessage(role: .assistant, text: offlineEnglishPreview, source: nil).isUsableAgentAnswer, "English offline draft is visible in chat and writable to notes")
        expect(!AgentMessage(role: .assistant, text: "请求失败：网络错误", source: nil).isUsableAgentAnswer, "agent error is not writable")
        expect(!AgentMessage(role: .assistant, text: "请求失败\n可直接重试。", source: nil).isUsableAgentAnswer, "generic failure header without colon is not writable")
        expect(!AgentMessage(role: .assistant, text: "Agent 请求失败：网络错误", source: nil).isUsableAgentAnswer, "legacy agent error is not writable")
    }
}
