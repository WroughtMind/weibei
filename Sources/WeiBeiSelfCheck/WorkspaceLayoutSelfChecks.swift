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
    static func run(repositoryURL: URL) throws {
        let appSource = SelfCheckSupport.source(
            "Sources/WeiBei/App/WeiBeiApp.swift",
            repositoryURL: repositoryURL
        )

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
        let contentViewSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Views/ContentView.swift")
        let contentViewSource = (try? String(contentsOf: contentViewSourceURL, encoding: .utf8)) ?? ""
        expect(!contentViewSource.isEmpty, "content view source is readable")
        let stableDocumentSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Views/StableDocumentWorkspace.swift")
        let stableDocumentSource = (try? String(contentsOf: stableDocumentSourceURL, encoding: .utf8)) ?? ""
        let paneContinuityRecorderSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Support/PaneContinuityRecorder.swift")
        let paneContinuityRecorderSource = (try? String(contentsOf: paneContinuityRecorderSourceURL, encoding: .utf8)) ?? ""
        let documentPaneTransitionSource: String = {
            guard let start = contentViewSource.range(of: "private func documentPaneLayoutView() -> some View")?.lowerBound,
                  let end = contentViewSource[start...].range(of: "private func estimatedDocumentPaneFrames")?.lowerBound else {
                return ""
            }
            return String(contentViewSource[start..<end])
        }()
        let threePaneChromeSource: String = {
            guard let start = contentViewSource.range(of: "private struct ThreePaneWorkspaceChrome: View")?.lowerBound,
                  let end = contentViewSource[start...].range(of: "private struct LayoutContentView: View")?.lowerBound else {
                return ""
            }
            return String(contentViewSource[start..<end])
        }()
        expect(!documentPaneTransitionSource.isEmpty
            && documentPaneTransitionSource.contains("ThreePaneWorkspaceChrome(")
            && threePaneChromeSource.contains("StableDocumentWorkspace(")
            && threePaneChromeSource.contains("@EnvironmentObject private var paneReorder: ThreePaneReorderState")
            && !documentPaneTransitionSource.contains("switch order.count")
            && !documentPaneTransitionSource.contains("ResizableTwoPane(")
            && !documentPaneTransitionSource.contains("ResizableThreePane(")
            && !documentPaneTransitionSource.contains(".transition(WeiBeiTransition.layout)")
            && !documentPaneTransitionSource.contains(".transition(WeiBeiTransition.rightPanel)"), "ordinary pane-count changes keep one stable container instead of replacing the layout tree")
        expect(stableDocumentSource.contains("WorkspacePaneRole.allCases.map")
            && stableDocumentSource.contains("splitView.install(roleHosts: roleHosts, emptyHost: emptyHost)")
            && stableDocumentSource.contains("animator().frame = frame")
            && stableDocumentSource.contains("private let layoutAnimationDuration = 0.24")
            && stableDocumentSource.contains("equalPaneWidths(count:")
            && stableDocumentSource.contains("visibleOrder.count > displayedVisibleOrder.count")
            && stableDocumentSource.contains("func assertStableOwnership()")
            && stableDocumentSource.contains("roleHosts.values.allSatisfy { $0.superview === self }")
            && stableDocumentSource.contains("EmptyWorkspaceLauncherView().environmentObject(store)")
            && stableDocumentSource.contains("let appearanceMode: WeiBeiAppearanceMode")
            && stableDocumentSource.contains("applyEmptyBoardPaper(to: splitView, mode: appearanceMode)")
            && stableDocumentSource.contains("emptyHost?.layer?.backgroundColor = cgPaper")
            && !stableDocumentSource.contains("removeFromSuperview()")
            && !stableDocumentSource.contains("rootView ="), "document pane hosts remain under one AppKit parent while frames animate; empty board paper syncs via layer + explicit appearanceMode")
        expect(stableDocumentSource.contains("recordContinuityTransition(duration: layoutAnimationDuration)")
            && stableDocumentSource.contains("host.layer?.presentation()?.frame ?? host.frame")
            && paneContinuityRecorderSource.contains("WEIBEI_VERIFY_PANE_TRACE_DIR")
            && paneContinuityRecorderSource.contains("1.0 / 60.0"), "pane verification records ownership and presentation frames throughout each animation")
        expect(!contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showReader)")
            && !contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showAgent)")
            && !contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showNotes)")
            && !contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showRightPane)"), "pane toggles do not animate the entire layout tree")
        let paneToggleClusterSource: String = {
            guard let start = contentViewSource.range(of: "private var paneToggleCluster: some View")?.lowerBound,
                  let end = contentViewSource[start...].range(of: "private var agentPaneToggleHelp: String")?.lowerBound else {
                return ""
            }
            return String(contentViewSource[start..<end])
        }()
        expect(!paneToggleClusterSource.isEmpty
            && !paneToggleClusterSource.contains("withAnimation")
            && paneToggleClusterSource.contains("store.toggleReader()")
            && paneToggleClusterSource.contains("store.toggleAgent()")
            && paneToggleClusterSource.contains("store.toggleNotes()"), "top-bar pane toggles hand animation ownership to the stable AppKit container")
        let emptyWorkspaceSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Views/EmptyWorkspaceLauncherView.swift")
        let emptyWorkspaceSource = (try? String(contentsOf: emptyWorkspaceSourceURL, encoding: .utf8)) ?? ""
        let inspirationCatalogSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBeiCore/EmptyWorkspaceInspiration.swift")
        let inspirationCatalogSource = (try? String(contentsOf: inspirationCatalogSourceURL, encoding: .utf8)) ?? ""
        let contentRailSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Views/ContentRailView.swift")
        let contentRailSource = (try? String(contentsOf: contentRailSourceURL, encoding: .utf8)) ?? ""
        expect(contentRailSource.contains("struct ContentRailView: View")
            && contentRailSource.contains("static let normalWidth: CGFloat = ContentRailPolicy.dormantWidth")
            && contentRailSource.contains("static let railOnlyThreshold = ContentRailPolicy.railOnlyThreshold")
            && contentRailSource.contains("ContentRailPolicy.previewWidth(")
            && contentRailSource.contains("ContentRailFloatingPreviewBridge(")
            && contentRailSource.contains("SpatialTapGesture()")
            && contentRailSource.contains("private func nearestItem")
            && !contentRailSource.contains(".popover("), "shared content rail uses the latest compact policy and floats previews beyond the existing pane edge")
        expect(stableDocumentSource.contains("EmptyWorkspaceLauncherView().environmentObject(store)")
            && emptyWorkspaceSource.contains("Text(title)")
            && emptyWorkspaceSource.contains("title: \"DOC\"")
            && emptyWorkspaceSource.contains("title: \"CHAT\"")
            && emptyWorkspaceSource.contains("title: \"NOTES\"")
            && emptyWorkspaceSource.contains("action: store.toggleReader")
            && emptyWorkspaceSource.contains("action: store.toggleAgent")
            && emptyWorkspaceSource.contains("action: store.toggleNotes"), "empty workspace exposes direct document, chat, and notes entries through the existing pane toggles")
        expect(emptyWorkspaceSource.contains("WeiBeiTypography.englishBrandFont")
            && emptyWorkspaceSource.contains("entryDivider")
            && emptyWorkspaceSource.contains("Rectangle()")
            && !emptyWorkspaceSource.contains("RoundedRectangle")
            && !emptyWorkspaceSource.contains("Capsule()")
            && !emptyWorkspaceSource.contains("stroke(WeiBeiTheme.cinnabar"), "empty workspace entry uses WeiBei English lettering, hairlines, and whitespace without cards, pills, or red outlines")
        expect(emptyWorkspaceSource.contains("TimelineView(.periodic(from: .now, by: 60))")
            && emptyWorkspaceSource.contains("EmptyWorkspaceDayPeriod.current(at:")
            && emptyWorkspaceSource.contains("static let compactWidthThreshold: CGFloat = 1140")
            && emptyWorkspaceSource.contains("static let compactHeightThreshold: CGFloat = 680")
            && emptyWorkspaceSource.contains("geometry.size.width < EmptyWorkspaceLayoutMetrics.compactWidthThreshold")
            && emptyWorkspaceSource.contains("min(116, max(76")
            && emptyWorkspaceSource.contains("minimumScaleFactor(0.78)")
            && emptyWorkspaceSource.contains("EmptyWorkspacePaperField(mode: mode, compact: compact)")
            && emptyWorkspaceSource.contains("EmptyWorkspaceResolvedColor.paper")
            && emptyWorkspaceSource.contains("onChange(of: store.appearanceMode)")
            && emptyWorkspaceSource.contains("appearanceEpoch")
            && !emptyWorkspaceSource.contains("WeiBeiThemeRuntime.didChangeNotification"), "empty workspace greeting updates with time; paper field rebuilds once on appearanceMode change")
        expect(emptyWorkspaceSource.contains("selectedInspirationID")
            && emptyWorkspaceSource.contains("randomItem(excludingID: currentID")
            && emptyWorkspaceSource.contains("static let entryCenterRatio: CGFloat = 0.402")
            && emptyWorkspaceSource.contains("static let inspirationCenterRatio: CGFloat = 0.66")
            && emptyWorkspaceSource.contains("let entryCenterY = clampedCenterY(")
            && emptyWorkspaceSource.contains("let minimumInspirationCenterY = max(")
            && emptyWorkspaceSource.contains("let inspirationCenterY = min(")
            && emptyWorkspaceSource.contains(".position(x: availableSize.width / 2, y: entryCenterY)")
            && emptyWorkspaceSource.contains(".position(x: availableSize.width / 2, y: inspirationCenterY)")
            && emptyWorkspaceSource.contains("let inspirationSlotHeight = compact")
            && emptyWorkspaceSource.contains("height: inspirationSlotHeight")
            && emptyWorkspaceSource.contains("private func workspaceContent(")
            && emptyWorkspaceSource.contains("if store.showDailyInspiration")
            && emptyWorkspaceSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)")
            && emptyWorkspaceSource.contains("private func entryCluster(")
            && emptyWorkspaceSource.contains("let entryCenterRatio: CGFloat = store.showDailyInspiration ? EmptyWorkspaceLayoutMetrics.entryCenterRatio : 0.5")
            && emptyWorkspaceSource.contains(".id(inspiration.id)")
            && emptyWorkspaceSource.contains(".transition(.opacity)")
            && emptyWorkspaceSource.contains("随机换一则")
            && emptyWorkspaceSource.contains("WeiBeiTypography.englishBrandFont(size: 22, weight: .semibold)")
            && emptyWorkspaceSource.contains("formulaContent(size: compact ? 24 : 30)")
            && emptyWorkspaceSource.contains("inspirationText(size: compact ? 21 : 26)")
            && emptyWorkspaceSource.contains("foregroundStyle(WeiBeiTheme.ink.opacity(0.90))")
            && emptyWorkspaceSource.contains("foregroundStyle(WeiBeiTheme.tertiaryInk)")
            && !emptyWorkspaceSource.contains("Text(store.ui(\"随机换一则\", \"RANDOM\"))")
            && emptyWorkspaceSource.contains("accessibilityHint(Text(store.ui(\"随机换一则灵感\", \"Show a random inspiration\")))")
            && !emptyWorkspaceSource.contains("greetingRule")
            && !emptyWorkspaceSource.contains("inspirationCounter")
            && !emptyWorkspaceSource.contains("%02d / %02d")
            && !emptyWorkspaceSource.contains("inspirationOffset"), "empty workspace inspiration switches randomly without repeating the current item or showing catalog counters")
        expect(emptyWorkspaceSource.contains("if store.showDailyInspiration")
            && emptyWorkspaceSource.contains("EmptyWorkspaceInspirationCatalog.item")
            && emptyWorkspaceSource.contains("case \"empty-workspace-calligraphy-light\":")
            && emptyWorkspaceSource.contains("forcedID = \"lanting-clear-breeze\"")
            && emptyWorkspaceSource.contains("case \"empty-workspace-calligraphy-dark\":")
            && emptyWorkspaceSource.contains("forcedID = \"lanting-universe\"")
            && emptyWorkspaceSource.contains("Link(inspiration.sourceLabel")
            && emptyWorkspaceSource.contains("Link(inspiration.rightsLabel")
            && emptyWorkspaceSource.contains("Bundle.module.url(forResource:")
            && !emptyWorkspaceSource.contains("URLSession")
            && !inspirationCatalogSource.contains("URLSession"), "daily inspiration is bundled for offline use while retaining visible source and rights links")
        expect(emptyWorkspaceSource.contains("empty-workspace-entry-doc")
            && emptyWorkspaceSource.contains("empty-workspace-entry-chat")
            && emptyWorkspaceSource.contains("empty-workspace-entry-notes")
            && emptyWorkspaceSource.contains("accessibilityLabel"), "empty workspace entries remain individually named and reachable to accessibility automation")
        expect(contentViewSource.contains("case .immersiveReading:\n                PersistentPaneHost(role: .reader")
            && !contentViewSource.contains("QuietInsightView")
            && !contentViewSource.contains("AgentDrawerView")
            && !contentViewSource.contains("CornerAgentView"), "immersive reading hosts only the reader; deleted agent overlays are gone")
        let themeSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Support/Theme.swift")
        let themeSource = (try? String(contentsOf: themeSourceURL, encoding: .utf8)) ?? ""
        // Settings views must be loaded early: top-bar / theme assertions below scan agentSettingsSource.
        let settingsViewsDirEarly = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Views/Settings")
        let settingsViewsSourceEarly: String = {
            let urls = (try? FileManager.default.contentsOfDirectory(at: settingsViewsDirEarly, includingPropertiesForKeys: nil)) ?? []
            return urls
                .filter { $0.pathExtension == "swift" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: "\n")
        }()
        // appSource is defined later; for early theme checks only the settings union is needed.
        // Full agentSettingsSource (app + settings) is rebound after appSource loads.
        var agentSettingsSource = settingsViewsSourceEarly
        expect(themeSource.contains(".fill(.regularMaterial)") && themeSource.contains("paperWashOpacity"), "header glass uses one shared paper material wash")
        expect(themeSource.contains("WeiBeiTheme.glassTint.opacity(0.16 * opacity)") && !themeSource.contains("WeiBeiTheme.paperInset.opacity(0.10 * opacity)"), "header handoff fade avoids a hard paper edge")
        expect(themeSource.contains("static func glassTint(for mode:")
            && themeSource.contains("static func glassHighlight(for mode:")
            && themeSource.contains("static func documentMaskFill(for mode:")
            && themeSource.contains("var appearanceMode: WeiBeiAppearanceMode")
            && themeSource.contains("Match the page/window paper exactly")
            && themeSource.contains(".regularMaterial"), "dark glass headers match page paper solidly; light themes keep material wash")
        expect(themeSource.contains("paperRaised.opacity(0.985)")
            && themeSource.contains(".opacity(0.015)")
            && !themeSource.contains("paperRaised.opacity(0.92)"), "floating panels stay readable without losing the light glass surface")
        expect(!themeSource.contains("func weibeiInputPrompt")
            && !themeSource.contains(".overlay(alignment: .topLeading)")
            && !themeSource.contains("prompt.padding(.top, top)")
            && !themeSource.contains(".foregroundColor(.white)")
            && !themeSource.contains(".foregroundStyle(.white)"), "input placeholders use native prompt text instead of a separate overlay")
        expect(themeSource.contains("hovering = isEnabled && isHovering")
            && themeSource.contains(".onChange(of: isEnabled)")
            && themeSource.contains("hovering = false"), "icon buttons clear stale hover state when controls disable or the pointer leaves")
        expect(themeSource.contains("func weibeiInputSurface")
            && (themeSource.contains("static var placeholderInk") || themeSource.contains("static func placeholderInk"))
            && themeSource.contains("horizontalPadding: CGFloat = 10")
            && themeSource.contains(".padding(.horizontal, horizontalPadding)")
            && themeSource.contains(".foregroundColor(WeiBeiTheme.ink)")
            && themeSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
            && themeSource.contains(".tint(WeiBeiTheme.link)")
            && !themeSource.contains(".environment(\\.colorScheme, .light)")
            && themeSource.contains(".fill(WeiBeiTheme.paperRaised.opacity(active ? 0.66 : 0.60))")
            && themeSource.contains(".stroke(WeiBeiTheme.glassHighlight.opacity(active ? 0.34 : 0.24), lineWidth: 1)")
            && themeSource.contains(".stroke(WeiBeiTheme.paperInset.opacity(active ? 0.30 : 0.38), lineWidth: 1)")
            && themeSource.contains(".stroke(active ? WeiBeiTheme.link.opacity(0.34) : WeiBeiTheme.hairline.opacity(0.54), lineWidth: 1)")
            && !themeSource.contains("secondaryInk.opacity(0.84)"), "input surfaces use semantic ink without forcing the old light color scheme")
        expect(themeSource.contains("enum WeiBeiAppearanceMode")
            && themeSource.contains("case paper")
            && themeSource.contains("case xuan")
            && themeSource.contains("case inkstone")
            && themeSource.contains("case stele")
            && themeSource.contains("var isDark: Bool")
            && themeSource.contains("WeiBeiNativePalette")
            && themeSource.contains("WeiBeiThemeRuntime")
            && themeSource.contains("static var paper: Color")
            && themeSource.contains("documentMaskFill")
            && themeSource.contains("didChangeNotification"), "theme exposes four appearance modes with live palette resolution and document mask fills")
        expect(!themeSource.contains("var label: String")
            && !themeSource.contains("var actionLabel: String"), "theme-facing labels require an interface language instead of Chinese-only fallback properties")
        expect(themeSource.contains("static let appearance = Animation.easeOut(duration: 0.12)"), "appearance changes use a snappy theme transition")
        expect(themeSource.contains("tertiaryInk.opacity(0.58)") && themeSource.contains("tertiaryInk.opacity(0.60)"), "disabled button text remains legible on light paper surfaces")
        expect(themeSource.contains("englishDisplayFontName = \"WeiBeiStele-Regular\"")
            && themeSource.contains("englishMonoFontName = \"WeiBeiSteleMono-Regular\"")
            && themeSource.contains("WeiBeiResources.bundle.url(forResource: name, withExtension: \"ttf\")\n                ?? WeiBeiResources.bundle.url(forResource: name, withExtension: \"ttf\", subdirectory: \"Fonts\")")
            && themeSource.contains("case .english:\n            registerBundledFonts()\n            return .custom(englishDisplayFontName, size: size).weight(weight)")
            && themeSource.contains("static func englishBrandFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {\n        registerBundledFonts()")
            && themeSource.contains("case .english:\n            registerBundledFonts()\n            return .custom(englishMonoFontName, size: size)")
            && themeSource.contains("return .custom(englishDisplayFontName, size: size).weight(weight)")
            && !themeSource.contains("englishDisplayFontName = \"WeiBeiStele\"")
            && !themeSource.contains("englishMonoFontName = \"WeiBeiSteleMono\""), "bundled English fonts use registered PostScript names and register before custom SwiftUI font construction")
        expect(contentViewSource.contains("ResizableTwoPane<First: View, Second: View>: NSViewRepresentable"), "two-pane layout uses native bridge")
        expect(contentViewSource.contains("ResizableThreePane<First: View, Second: View, Third: View>: NSViewRepresentable"), "three-pane layout uses native bridge")
        expect(contentViewSource.contains("WeiBeiSplitView: NSSplitView"), "content panes use native split view")
        expect(contentViewSource.contains("dividerFill.setFill()")
            && contentViewSource.contains("rect.fill()")
            && contentViewSource.contains("private var dividerFill: NSColor")
            && contentViewSource.contains("private var dividerLine: NSColor")
            && contentViewSource.contains("rect.minY + 14")
            && !contentViewSource.contains("NSColor.clear.setFill()"), "native split divider uses the current paper surface instead of a transparent hard gap")
        expect(contentViewSource.contains("override func layout()"), "native split applies saved positions after first real layout")
        let courseDrawerHostSource = (try? String(
            contentsOf: repositoryURL
                .appendingPathComponent("Sources/WeiBei/Views/CourseDrawerHost.swift"),
            encoding: .utf8
        )) ?? ""
        expect(contentViewSource.contains("LayoutContentView()")
            && contentViewSource.contains("CourseLibraryDrawerLayer")
            && contentViewSource.contains("struct CourseLibraryDrawerLayer")
            && contentViewSource.contains("CourseDrawerHost")
            // Drawer chrome is AppKit-hosted; ContentView itself must not observe libraryDrawer.
            && contentViewSource.contains("LibraryAwareEscapeBridge")
            && courseDrawerHostSource.contains("NSAnimationContext")
            && courseDrawerHostSource.contains("CourseImmersiveDrawerView")
            && courseDrawerHostSource.contains("installHostingIfNeeded")
            && !contentViewSource.contains("@EnvironmentObject private var libraryDrawer: LibraryDrawerState\n    @FocusState")
            && !contentViewSource.contains(".animation(WeiBeiMotion.layout, value: store.showLibrary)")
            && !contentViewSource.contains("libraryResizeHandle")
            && !contentViewSource.contains("minimumContentWidthWithLibrary"), "course drawer slides over the living workspace without remount lag or layout-spring thrash")
        expect(contentViewSource.contains("private let railWidth = ContentRailMetrics.railOnlyWidth")
            && contentRailSource.contains("static let snapThreshold = ContentRailPolicy.snapThreshold")
            && contentRailSource.contains("static let readableWidth = ContentRailPolicy.readableWidth")
            && contentViewSource.contains("handleExpansionRequest(store.paneExpansionRequest")
            && stableDocumentSource.contains("ContentRailPolicy.expansionWidth(recentWidth:"), "normal multi-pane layouts snap to the latest compact rail and restore a bounded readable width")
        expect(!contentViewSource.contains("DragGesture()"), "content panes avoid SwiftUI drag resizing")
        expect(!contentViewSource.contains(".id(store.layout)"), "layout changes avoid whole-screen identity resets")
        expect(contentViewSource.contains("case .immersiveWriting:\n                PersistentPaneHost(role: .notes")
            && !contentViewSource.contains("writingDocumentRailItems")
            && !contentViewSource.contains("writingAssistRailItems")
            && !contentViewSource.contains("writingFirstSplitStorage"), "immersive writing reuses the persistent note host without permanent document or writing-aid rails")
        expect(!contentViewSource.contains("PaneSeparator"), "content panes avoid hand-drawn split separators")
        expect(contentViewSource.components(separatedBy: ".transition(WeiBeiTransition.layout)").count >= 2
            && !documentPaneTransitionSource.contains(".transition(WeiBeiTransition"), "immersive layouts keep shared transitions while ordinary pane visibility is animated inside the stable container")
        expect(!contentViewSource.contains("topBarContentFade"), "top bar avoids a duplicate content fade wash")
        expect(contentViewSource.contains("store.toggleLibrary()")
            && contentViewSource.contains("sidebar.left")
            && contentViewSource.contains("private var libraryButton: some View")
            && contentViewSource.contains("active: libraryDrawer.isOpen")
            && contentViewSource.contains("libraryDrawer.isOpen ? store.ui(\"收起课程抽屉\"")
            && !contentViewSource.contains("恢复课程目录")
            && !contentViewSource.contains(".opacity(isImmersiveLayout ? 0.45 : 1)"), "immersive top bar keeps a clear stateful library chooser instead of dimming a live control")
        if let leftControlsStart = contentViewSource.range(of: "private var leftPrimaryControls: some View")?.lowerBound,
           let leftControlsEnd = contentViewSource[leftControlsStart...].range(of: "\n    }\n\n    @ViewBuilder\n    private var navigationButtons")?.lowerBound {
            let leftControlsSource = String(contentViewSource[leftControlsStart..<leftControlsEnd])
            if let libraryRange = leftControlsSource.range(of: "libraryButton"),
               let navigationRange = leftControlsSource.range(of: "navigationButtons") {
                expect(libraryRange.lowerBound < navigationRange.lowerBound
                    && !leftControlsSource.contains("appearanceToggleButton")
                    && !leftControlsSource.contains("books.vertical")
                    && !leftControlsSource.contains("presentCourseWorkspace")
                    && !leftControlsSource.contains("settingsMenu"), "top-left controls keep library and navigation only; theme + Settings live on the right")
            } else {
                expect(false, "top-left controls expose library and navigation")
            }
        } else {
            expect(false, "top-left controls block is inspectable")
        }
        expect(contentViewSource.contains("WindowFullScreenReader(isFullScreen: $windowIsFullScreen)")
            && contentViewSource.contains("let isFullScreen: Bool")
            && contentViewSource.contains("TopBarLeadingInset.value(isFullScreen: isFullScreen)")
            && contentViewSource.contains("topIconButton(\"arrow.left\", help: store.ui(\"后退\"")
            && contentViewSource.contains("store.navigateBackInWorkspace()")
            && contentViewSource.contains(".keyboardShortcut(\"[\", modifiers: [.command])")
            && contentViewSource.contains("topIconButton(\"arrow.right\", help: store.ui(\"前进\"")
            && contentViewSource.contains("store.navigateForwardInWorkspace()")
            && contentViewSource.contains(".keyboardShortcut(\"]\", modifiers: [.command])")
            && contentViewSource.contains(".disabled(!store.canNavigateBack)")
            && contentViewSource.contains(".disabled(!store.canNavigateForward)"), "top bar exposes app back/forward and shifts left controls away from traffic lights outside fullscreen")
        expect(contentViewSource.contains("WeiBeiHeaderHandoffFade(")
            && contentViewSource.contains("opacity: isImmersiveLayout ? 0.42 : 0.34")
            && contentViewSource.contains("appearanceMode: store.appearanceMode")
            && contentViewSource.contains("paperOpacity: backgroundPaperOpacity - (isImmersiveLayout ? 0.06 : 0)")
            && contentViewSource.contains("materialOpacity: backgroundMaterialOpacity + (isImmersiveLayout ? 0.03 : 0)"), "immersive top bar keeps the same chrome while using a lighter glass handoff")
        expect(!contentViewSource.contains("文代笔")
            && !contentViewSource.contains("Agent中")
            && !contentViewSource.contains("对话中栏")
            && !contentViewSource.contains("对话右栏")
            && !contentViewSource.contains("shortLayoutLabel"), "compact top bar drops the layout label; no legacy fixed-position labels")
        expect(!contentViewSource.contains("showLibrary = false")
            && !contentViewSource.contains("store.layout = ")
            && !contentViewSource.contains("store.showRightPane = true"), "content view routes durable layout changes through WorkspaceStore without closing a user-opened library")
        expect(contentViewSource.contains(".weibeiInputSurface(active: searchFocused.wrappedValue, height: controlHeight)")
            && contentViewSource.contains("prompt: Text(store.ui(\"资料内搜索\"")
            && contentViewSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
            && contentViewSource.contains("topIconButton(\"magnifyingglass\", help: store.ui(\"打开资料内搜索\"")
            && !contentViewSource.contains("Label(\"搜索\", systemImage: \"magnifyingglass\")")
            && contentViewSource.contains(".foregroundColor(WeiBeiTheme.ink)")
            && contentViewSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
            && !contentViewSource.contains(".foregroundColor(primaryText)\n                    .foregroundStyle(primaryText)\n                    .tint(WeiBeiTheme.link)"), "top search uses fixed ink on its paper input surface instead of inheriting top bar chrome text")
        expect(contentViewSource.contains("private var controlHeight: CGFloat {\n        28\n    }"), "compact top bar controls keep a readable 28-point height")
        expect(contentViewSource.contains("private var leftPrimaryControls: some View")
            && contentViewSource.contains("libraryButton\n\n            navigationButtons")
            && !contentViewSource.contains("private var appearanceToggleButton: some View")
            && !contentViewSource.contains("AppearanceThemePaletteButton()")
            && themeSource.contains("struct AppearanceThemePaletteButton")
            && themeSource.contains("ForEach(WeiBeiAppearanceMode.allCases)")
            && themeSource.contains("store.setAppearanceMode(mode)")
            // Theme chooser lives only on Settings → Interface as AionUI-style layout cards.
            && agentSettingsSource.contains("private var themePicker")
            && agentSettingsSource.contains("WeiBeiThemeLayoutPreview(mode:")
            && themeSource.contains("struct WeiBeiThemeLayoutPreview")
            && !agentSettingsSource.contains("AppearanceThemePaletteButton()")
            && !contentViewSource.contains("WeiBeiBrandMark.image(for: store.appearanceMode)")
            && !contentViewSource.contains("private var brandBlock: some View")
            && contentViewSource.contains("openSettings")
            && contentViewSource.contains("openSettings()")
            && contentViewSource.contains("slider.horizontal.3")
            && contentViewSource.contains("打开设置")
            && contentViewSource.contains("WeiBeiIconButtonStyle(active: active, size: 24)")
            && !contentViewSource.contains("WeiBeiIconButtonStyle(active: store.appearanceMode == .inkstone")
            && !contentViewSource.contains("private var settingsMenu: some View")
            && !contentViewSource.contains("Image(systemName: \"gearshape\")"), "top bar is brandless and theme-free; theme lives only on Settings → Interface as layout preview cards")
        expect(themeSource.contains("enum WeiBeiIconButtonProminence")
            && themeSource.contains("@Environment(\\.colorScheme)")
            && themeSource.contains("prominence == .primary")
            && themeSource.contains("return (isPressed || hovering) ? WeiBeiTheme.onCinnabar : WeiBeiTheme.cinnabar")
            && themeSource.contains("if isPressed || hovering {\n                return WeiBeiTheme.cinnabar.opacity(primaryOpacity(isPressed: isPressed))")
            && themeSource.contains("? WeiBeiTheme.paperInset.opacity(0.58)\n                : WeiBeiTheme.cinnabarSoft.opacity(0.72)")
            && themeSource.contains("if active { return WeiBeiTheme.cinnabar }")
            && themeSource.contains("colorScheme == .dark ? 0.34 : 0.28")
            && themeSource.contains(".onHover { isHovering in"), "icon buttons share adaptive neutral, selected, primary, hover and press states across light and dark modes")
        expect(contentViewSource.contains("private var hasReaderScopedTopActions: Bool")
            && contentViewSource.contains("store.isPaneToggleActive(.reader)")
            && contentViewSource.contains("store.hasSelectedMaterial && hasReaderScopedTopActions")
            && !contentViewSource.contains("shouldShowReferenceAction"), "top material search stays scoped to reader-first layouts; copy-reference is not top-bar chrome")
        expect(contentViewSource.contains("if shouldShowSearchAction && !store.showReaderSearch"), "top bar hides the search icon while the search field is already open")
        expect(contentViewSource.contains("private var paneToggleCluster: some View")
            && contentViewSource.contains("store.toggleReader()")
            && contentViewSource.contains("store.toggleAgent()")
            && contentViewSource.contains("store.toggleNotes()"), "top bar exposes persistent reader, chat, and notes pane toggles")
        expect(!contentViewSource.contains("private var layoutMenu")
            && !contentViewSource.contains(".accessibilityLabel(Text(store.ui(\"切换布局\"")
            && !contentViewSource.contains("shortLayoutLabel")
            && !contentViewSource.contains("englishBrandFont(size: 15.5, weight: .semibold)")
            && !contentViewSource.contains("AppearanceThemePaletteButton()")
            && !agentSettingsSource.contains("AppearanceThemePaletteButton()")
            && agentSettingsSource.contains("themePicker"), "compact top bar is brandless and theme-free; theme lives only on Settings → Interface; legacy layout dropdown stays removed")
        expect(contentViewSource.contains("打开设置")
            && contentViewSource.contains("Open Settings"), "top bar settings control has a readable semantic label")
        expect(contentViewSource.contains("private var agentPaneToggleHelp: String")
            && contentViewSource.contains("用当前选区打开对话")
            && contentViewSource.contains("store.isPaneToggleActive(.agent)")
            && !contentViewSource.contains("topIconButton(\"bubble.left.and.text.bubble.right\", help: agentButtonHelp)")
            && !contentViewSource.contains("Section(\"Agent 入口\")")
            && !contentViewSource.contains("打开 Agent 对话区"), "top bar names conversation entry by the actual action instead of a generic agent label")
        expect(contentViewSource.contains("private var showsGlobalFloatingAgent: Bool")
            && !contentViewSource.contains("guard !store.isConversationSurfaceVisible else { return false }")
            && contentViewSource.contains("SelectionFloatingAgentPlacement.isVisible")
            && contentViewSource.contains("routesToConversation: store.isConversationSurfaceVisible")
            && contentViewSource.contains("multi-pane as well as immersive"), "global selection float appears in multi-pane and immersive; 问 routes to conversation when chat is open")
        expect(!themeSource.contains("enum TopBarVariant")
            && themeSource.contains("static let topBarHeight: CGFloat = 38")
            && !contentViewSource.contains("TopBarVariant")
            && !contentViewSource.contains("topBarVariant")
            && !contentViewSource.contains("setTopBarVariant"), "top bar is locked to compact constants; TopBarVariant and its selectors are gone")
        let sidebarSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/Views/SidebarView.swift")
        let sidebarSource = (try? String(contentsOf: sidebarSourceURL, encoding: .utf8)) ?? ""
        expect(sidebarSource.contains("Text(store.ui(\"课程目录\", \"Course Index\")")
            && sidebarSource.contains("Text(store.ui(\"课程空间\", \"Course Space\")")
            && sidebarSource.contains("store.presentCourseWorkspace(.hub)")
            && sidebarSource.contains("store.openCourseSpace(course.id)")
            && sidebarSource.contains("Text(store.ui(\"进入\", \"Enter\")")
            && sidebarSource.contains("store.openCourseSpace(courseID)")
            && sidebarSource.contains("prompt: Text(store.ui(\"搜索课程资料与笔记\"")
            && sidebarSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
            && sidebarSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "course index exposes course-space entry, per-course Enter, and searches materials and notes with readable ink")
    }
}
