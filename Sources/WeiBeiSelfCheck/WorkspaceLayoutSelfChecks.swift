import AppKit
import Foundation
import WeiBeiCore

/**
 * 验证阅读器、工作区布局、主题和导航契约。
 */
enum WorkspaceLayoutSelfChecks {
    /**
     * 执行该领域的自检。
     */
    @MainActor
    static func run() throws {
        expect(MarkdownTagSearch.matches(query: "finance", in: "#finance/rate")
            && MarkdownTagSearch.matches(query: "macro", in: "---\ntags: [banking, macro/rate]\n---")
            && MarkdownTagSearch.matches(query: "#nested", in: "#nested/tag")
            && !MarkdownTagSearch.matches(query: "code-tag", in: "`#code-tag`"), "markdown tag search supports library queries without indexing code")

        expect(PageNavigator.previous(0) == 0, "pdf previous clamps first page")
        expect(PageNavigator.next(0, pageCount: 2) == 1, "pdf next advances")
        expect(PageNavigator.next(1, pageCount: 2) == 1, "pdf next clamps last page")
        expect(PageNavigator.display(0, pageCount: 0) == "1 / 1", "pdf display empty")
        expect(TopBarLeadingInset.value(isFullScreen: true) == 12, "fullscreen top-left controls start from the left edge")
        expect(TopBarLeadingInset.value(isFullScreen: false) == 80
            && TopBarLeadingInset.value(isFullScreen: false) > TopBarLeadingInset.value(isFullScreen: true), "windowed top-left controls clear the traffic-light area")
        expect(!PDFModeChipPresentation.showsLabel(isExpanded: false), "pdf mode chip hides text after collapse")
        expect(PDFModeChipPresentation.showsLabel(isExpanded: true), "pdf mode chip shows text only during transient expansion")
        expect(PDFModeChipPresentation.controlOpacity(isExpanded: false, isHovering: true)
            < PDFModeChipPresentation.controlOpacity(isExpanded: true, isHovering: true), "pdf mode chip fades back even when hover state lingers")
        expect(ReaderSearch.cleaned("  利率\n") == "利率", "reader search trims query")
        expect(ReaderSearch.firstMatch(in: "实际利率与名义利率", query: "名义")?.location == 5, "reader search finds first match")
        expect(ReaderSearch.firstMatch(in: "Money and Banking", query: "money")?.location == 0, "reader search ignores case")
        expect(ReaderSearch.firstMatch(in: "Money and Banking", query: " ") == nil, "reader search ignores empty query")
        let pdfSourceReference = SourceReferenceTitle.parse("> 来源：Mishkin 教材样例，第 3 页")
        expect(pdfSourceReference.title == "Mishkin 教材样例" && pdfSourceReference.pageIndex == 2, "source reference parses pdf page")
        let htmlSourceReference = SourceReferenceTitle.parse("来源：货币金融学课程 HTML，章节：实际利率")
        expect(
            htmlSourceReference.title == "货币金融学课程 HTML"
                && htmlSourceReference.pageIndex == nil
                && htmlSourceReference.sectionTitle == "实际利率"
                && htmlSourceReference.sectionLocationID == nil
                && htmlSourceReference.sectionOrdinal == nil,
            "source reference parses an exact HTML section"
        )
        let disambiguatedSourceReference = SourceReferenceTitle.parse("来源：重复教材，条目：7，章节标识：html-section-a1b2c3d4，章节序号：4，章节：利率")
        expect(
            disambiguatedSourceReference.title == "重复教材"
                && disambiguatedSourceReference.courseItemOrdinal == 7
                && disambiguatedSourceReference.sectionLocationID == "html-section-a1b2c3d4"
                && disambiguatedSourceReference.sectionOrdinal == 4
                && disambiguatedSourceReference.sectionTitle == "利率",
            "source reference preserves the file and section ordinals needed to disambiguate duplicate titles"
        )
        let englishSectionReference = SourceReferenceTitle.parse("Source: Repeated Course, item: 2, section id: html-section-d4c3b2a1, section number: 5, section: Interest")
        expect(
            englishSectionReference.title == "Repeated Course"
                && englishSectionReference.courseItemOrdinal == 2
                && englishSectionReference.sectionLocationID == "html-section-d4c3b2a1"
                && englishSectionReference.sectionOrdinal == 5
                && englishSectionReference.sectionTitle == "Interest",
            "source reference preserves stable HTML section ordinals in English"
        )
        let emphasizedSourceReference = SourceReferenceTitle.parse("来源：**Mishkin 教材样例**")
        expect(emphasizedSourceReference.title == "Mishkin 教材样例", "source reference ignores whole-title Markdown emphasis")
        let inlineCodeSourceReference = SourceReferenceTitle.parse("- 相关资料：`来源：Mishkin 教材样例`")
        expect(inlineCodeSourceReference.title == "Mishkin 教材样例", "source reference remains actionable when PI wraps the jump in inline code")
        let calloutSourceReference = SourceReferenceTitle.parse("""
        > [!quote] 选区摘录
        > 实际利率
        >
        > 来源：Mishkin 教材样例，第 12 页
        """)
        expect(calloutSourceReference.title == "Mishkin 教材样例" && calloutSourceReference.pageIndex == 11, "source reference parses quote callout")
        expect(WikiLink.targetTitle(from: "  货币理论 | 显示名 ") == "货币理论", "wikilink alias keeps target title")
        expect(WikiLink.targetTitle(from: "  货币理论 ") == "货币理论", "wikilink plain title")
        expect(WikiLink.targetTitle(from: "货币理论#利率") == "货币理论", "wikilink heading target opens note title")
        expect(WikiLink.targetTitle(from: "货币理论#^rate-block") == "货币理论", "wikilink block target opens note title")
        expect(WikiLink.enclosingTitle(in: "参考 [[货币理论|Money]] 继续写", cursor: 6) == "货币理论", "wikilink title at cursor")
        expect(WikiLink.enclosingTitle(in: "参考 [[货币理论#利率]] 继续写", cursor: 8) == "货币理论", "wikilink heading title at cursor")
        expect(WikiLink.enclosingTitle(in: "没有双链", cursor: 2) == nil, "wikilink title ignores plain text")
        expect(WorkspaceLayout.documentAgentNotes.hasCollapsibleRightPane, "three-pane layout can collapse right pane")
        expect(WorkspaceLayout.documentNotesSplit.hasCollapsibleRightPane, "split layout can collapse right pane")
        expect(!WorkspaceLayout.immersiveReading.hasCollapsibleRightPane, "immersive reading has no right pane to collapse")
        expect(!WorkspaceLayout.immersiveWriting.hasCollapsibleRightPane, "immersive writing keeps one uninterrupted note canvas")
        expect(WorkspaceLayout.documentAgentNotes.isDocumentThreePane
            && WorkspaceLayout.documentNotesAgent.isDocumentThreePane
            && !WorkspaceLayout.documentNotesSplit.isDocumentThreePane, "only full document layouts participate in three-pane reordering")
        expect(WorkspaceLayout.documentAgentNotes.allowsRailOnlyPanes
            && WorkspaceLayout.documentNotesSplit.allowsRailOnlyPanes
            && !WorkspaceLayout.immersiveConversation.allowsRailOnlyPanes
            && !WorkspaceLayout.immersiveWriting.allowsRailOnlyPanes, "only normal multi-pane layouts can collapse content panes into rail-only mode")
        expect(WorkspaceLayout.documentAgentNotes.defaultThreePaneOrder == [.reader, .agent, .notes]
            && WorkspaceLayout.documentNotesAgent.defaultThreePaneOrder == [.reader, .notes, .agent], "legacy three-pane layout presets map to pane role order")
        expect(WorkspacePaneRole.normalized([.notes, .reader, .notes]) == [.notes, .reader, .agent], "pane role order normalization preserves user pane order and restores missing panes")
        expect(WorkspacePaneRole.agent.focus == .agent
            && WorkspacePaneRole.reader.shortLabel(language: .chinese) == "文"
            && WorkspacePaneRole.notes.label(language: .english) == "Notes", "pane roles expose focus and localized labels")
        let reorderOrder: [WorkspacePaneRole] = [.reader, .agent, .notes]
        let reorderFrames: [WorkspacePaneRole: CGRect] = [
            .reader: CGRect(x: 0, y: 0, width: 320, height: 600),
            .agent: CGRect(x: 330, y: 0, width: 620, height: 600),
            .notes: CGRect(x: 960, y: 0, width: 360, height: 600)
        ]
        expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .reader, horizontalDelta: 180) == 1, "pane reorder target follows real resized pane overlap instead of fixed thirds")
        expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .notes, horizontalDelta: -420) == 1, "pane reorder target works from either edge using the current pane widths")
        expect(NoteRenderMode.visibleCases == [.rich, .split, .source]
            && NoteRenderMode.preview.visibleMode == .rich
            && NoteRenderMode.source.visibleMode == .source, "note render modes keep legacy preview data readable while hiding preview from the writing controls")
        expect(WorkspaceLayout.documentAgentNotes.label(language: .chinese) == "阅读-对话-笔记"
            && WorkspaceLayout.documentAgentNotes.label(language: .english) == "Reader-Chat-Notes"
            && WorkspaceLayout.documentNotesAgent.label(language: .chinese) == "阅读-笔记-对话"
            && WorkspaceLayout.documentNotesSplit.label(language: .english) == "Reader / Notes", "layout labels use localized task language instead of internal pane names")
        expect(WorkspaceLayout.immersiveConversation.systemImage == "bubble.left.and.text.bubble.right" && WorkspaceLayout.immersiveWriting.systemImage == "square.and.pencil", "immersive layouts expose semantic menu icons")
    }
}
