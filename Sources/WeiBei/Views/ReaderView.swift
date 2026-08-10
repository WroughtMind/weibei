import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore
import WebKit

extension Notification.Name {
    static let weiBeiScrollAgentToMessage = Notification.Name("WeiBeiScrollAgentToMessage")
}

struct ImmersiveHoverTitleView<Actions: View>: View {
    let mark: String
    let title: String
    let appearanceMode: WeiBeiAppearanceMode
    var isPinned = false
    var actionsAlignedTrailing = false
    var reorderRole: WorkspacePaneRole?
    @ViewBuilder var actions: () -> Actions

    @State private var visible = false
    @State private var hideTask: DispatchWorkItem?

    init(
        mark: String,
        title: String,
        appearanceMode: WeiBeiAppearanceMode,
        isPinned: Bool = false,
        actionsAlignedTrailing: Bool = false,
        reorderRole: WorkspacePaneRole? = nil,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.mark = mark
        self.title = title
        self.appearanceMode = appearanceMode
        self.isPinned = isPinned
        self.actionsAlignedTrailing = actionsAlignedTrailing
        self.reorderRole = reorderRole
        self.actions = actions
    }

    var body: some View {
        // CRITICAL: do NOT use maxHeight: .infinity. That expands the overlay's hit-test
        // region over the whole reader/chat pane and kills PDF/text selection + the
        // selection float capsule. Stay top-aligned and only as tall as the strip/chip;
        // parent uses .overlay(alignment: .top).
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
                .onHover(perform: updateVisibility)

            if visible || isPinned {
                HStack(alignment: .center, spacing: actionsAlignedTrailing ? 10 : 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            hoverMark
                            Text(title)
                                .font(.system(size: 11.8, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                                .layoutPriority(-1)
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        hoverMark
                    }
                    .frame(minWidth: 0, alignment: .leading)
                    if actionsAlignedTrailing {
                        Spacer(minLength: 14)
                    }
                    actions()
                }
                .padding(.horizontal, actionsAlignedTrailing ? 14 : 12)
                .frame(maxWidth: actionsAlignedTrailing ? .infinity : nil, alignment: .leading)
                .frame(minHeight: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(WeiBeiTheme.paperRaised.opacity(appearanceMode.isDark ? 0.88 : 0.92))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(WeiBeiTheme.hairline.opacity(appearanceMode.isDark ? 0.42 : 0.48), lineWidth: 1)
                        }
                }
                .shadow(color: WeiBeiTheme.ink.opacity(appearanceMode.isDark ? 0.28 : 0.08), radius: 9, y: 4)
                .padding(.horizontal, actionsAlignedTrailing ? 14 : 0)
                .padding(.top, 7)
                .contentShape(Rectangle())
                .onHover(perform: updateVisibility)
                .modifier(PaneHeaderReorderModifier(role: reorderRole))
                .transition(WeiBeiTransition.floating)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear {
            hideTask?.cancel()
        }
    }

    private func updateVisibility(_ hovering: Bool) {
        hideTask?.cancel()
        if hovering {
            withAnimation(WeiBeiMotion.panel) {
                visible = true
            }
            return
        }

        let task = DispatchWorkItem {
            withAnimation(WeiBeiMotion.panel) {
                visible = false
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
    }

    private var hoverMark: some View {
        Text(mark)
            .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
            .tracking(1.15)
            .baselineOffset(0.7)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.82))
    }
}

extension ImmersiveHoverTitleView where Actions == EmptyView {
    init(mark: String, title: String, appearanceMode: WeiBeiAppearanceMode, reorderRole: WorkspacePaneRole? = nil) {
        self.mark = mark
        self.title = title
        self.appearanceMode = appearanceMode
        self.reorderRole = reorderRole
        self.actions = { EmptyView() }
    }
}

struct ReaderView: View {
    var isImmersive = false
    var showsFloatingTitle = false
    var floatingTitleReorderRole: WorkspacePaneRole? = nil

    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var paneState: WorkspacePaneState
    @State private var pdfBrowseMode: PDFBrowseMode = .scroll
    @State private var pdfPageIndex = 0
    @State private var pdfPageCount = 0
    @State private var pdfControlsHovering = false
    @State private var pdfControlsExpanded = false
    @State private var pdfControlsCollapseToken = UUID()
    @State private var pendingPDFPageIndex: Int?
    @State private var pendingPDFPageRequestID: UUID?
    @State private var pendingPDFPageRecordsLocation = false
    @State private var pdfHasSelectableText: Bool?
    @State private var pdfContentRailItems: [ContentRailItem] = []
    @State private var pdfRailTargetPageIndex: Int?
    @State private var pendingPDFRailPreviewPages: Set<Int> = []
    @State private var htmlContentRailItems: [ContentRailItem] = []
    @State private var htmlContentRailActiveID: String?
    @State private var htmlContentRailTarget: WebReaderContentRailTarget?
    @State private var pendingHTMLLocationCommit: Task<Void, Never>?
    @State private var pendingHTMLContentRailActiveCommit: Task<Void, Never>?
    @State private var pendingPDFLocationCommit: Task<Void, Never>?
    /// Live pane size from a background probe. Zero until first real measurement.
    @State private var measuredPaneSize: CGSize = .zero

    var body: some View {
        // Hang-proof structure:
        // NEVER put GeometryReader as an ancestor of WKWebView / PDFView.
        // Hang report 2026-08-01: GeometryReaderLayout → PlatformView.sizeThatFits →
        // Auto Layout systemLayoutSizeFittingSize blocked the main thread for ~30s when
        // global chat publish refreshed the open HTML reader. Measure pane size only via
        // background preference (sibling, not parent), matching AgentPaneView.
        let availableWidth = max(measuredPaneSize.width, 1)
        let availableHeight = max(measuredPaneSize.height, 1)
        let railOnly = ContentRailMetrics.isRailOnly(
            availableWidth: availableWidth,
            allowed: supportsContentRail && !isImmersive
        )
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                readerBody
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(railOnly ? 0 : 1)
            .allowsHitTesting(!railOnly)

            if !railOnly, store.selectedMaterialItem?.kind == .pdf {
                pdfFloatingControls
                    .padding(.trailing, isImmersive ? 18 : 10)
                    .padding(.bottom, isImmersive ? 18 : 12)
                    .transition(WeiBeiTransition.floating)
            }

            if !railOnly, pdfHasSelectableText == false {
                pdfTextLayerNotice
                    .padding(.leading, isImmersive ? 18 : 14)
                    .padding(.bottom, isImmersive ? 18 : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(WeiBeiTransition.floating)
            }
        }
        .overlay(alignment: .leading) {
            if supportsContentRail {
                contentRail(isRailOnly: railOnly, availableWidth: availableWidth)
                    .frame(
                        width: railOnly ? min(ContentRailMetrics.railOnlyWidth, availableWidth) : availableWidth,
                        height: availableHeight,
                        alignment: .leading
                    )
                    .zIndex(6)
            }
        }
        .overlay(alignment: .top) {
            if !railOnly, showsFloatingTitle,
               store.selectedMaterialItem != nil {
                // Mask switch lives only on this hover DOC tab — not pinned, not main top bar.
                ImmersiveHoverTitleView(
                    mark: "DOC",
                    title: floatingTitle,
                    appearanceMode: store.appearanceMode,
                    reorderRole: floatingTitleReorderRole
                ) {
                    HStack(spacing: 8) {
                        ContextualContentListButton(kind: .material)
                        selectionAskThreadsMenu
                        importedDocumentAdaptationControl
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Width/height probe as background sibling — never parent of WKWebView/PDFView.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ReaderPaneSizeKey.self,
                    value: geo.size
                )
            }
        }
        .onPreferenceChange(ReaderPaneSizeKey.self) { size in
            guard size.width > 1, size.height > 1 else { return }
            if abs(measuredPaneSize.width - size.width) > 0.5
                || abs(measuredPaneSize.height - size.height) > 0.5 {
                measuredPaneSize = size
            }
        }
        // Bind paper fill to the live mode so empty reader / page chrome tracks theme switches.
        .background(Color(nsColor: WeiBeiNativePalette.paper(for: store.appearanceMode)))
        .foregroundStyle(Color(nsColor: WeiBeiNativePalette.ink(for: store.appearanceMode)))
        .animation(WeiBeiMotion.panel, value: pdfBrowseMode)
        .animation(WeiBeiMotion.panel, value: paneState.showReaderSearch)
        .animation(WeiBeiMotion.panel, value: pdfHasSelectableText)
        .onAppear {
            syncReaderLocationTitle()
            capturePendingPDFPageRequest()
            htmlContentRailActiveID = store.readerLocationID
            applyPendingPDFPageIfReady()
            applyPendingHTMLLocationIfReady()
            rebuildPDFContentRail()
        }
        .onChange(of: store.selectedItemID) { _, _ in
            pendingHTMLLocationCommit?.cancel()
            pendingHTMLLocationCommit = nil
            pendingHTMLContentRailActiveCommit?.cancel()
            pendingHTMLContentRailActiveCommit = nil
            pendingPDFLocationCommit?.cancel()
            pendingPDFLocationCommit = nil
            pdfPageIndex = 0
            pdfPageCount = store.selectedMaterialItem?.kind == .pdf && store.selectedMaterialItem?.url == nil ? 1 : 0
            pdfHasSelectableText = store.selectedMaterialItem?.kind == .pdf && store.selectedMaterialItem?.url == nil ? true : nil
            pdfContentRailItems = []
            pdfRailTargetPageIndex = nil
            pendingPDFRailPreviewPages = []
            htmlContentRailItems = []
            htmlContentRailActiveID = store.readerLocationID
            htmlContentRailTarget = nil
            syncReaderLocationTitle()
            capturePendingPDFPageRequest()
            applyPendingPDFPageIfReady()
            applyPendingHTMLLocationIfReady()
            rebuildPDFContentRail()
        }
        .onChange(of: pdfPageIndex) { _, _ in
            syncReaderLocationTitle()
        }
        .onChange(of: pdfPageCount) { _, _ in
            syncReaderLocationTitle()
            applyPendingPDFPageIfReady()
            rebuildPDFContentRail()
        }
        .onChange(of: store.readerTargetPageIndex) { _, target in
            capturePendingPDFPageRequest()
            applyPendingPDFPageIfReady()
        }
        .onChange(of: store.readerTargetPageRequestID) { _, _ in
            capturePendingPDFPageRequest()
            applyPendingPDFPageIfReady()
        }
        .onChange(of: store.readerTargetLocationID) { _, _ in
            applyPendingHTMLLocationIfReady()
        }
        .onChange(of: store.readerTargetLocationTitle) { _, _ in
            applyPendingHTMLLocationIfReady()
        }
        .onChange(of: store.readerTargetLocationRequestID) { _, _ in
            applyPendingHTMLLocationIfReady()
        }
    }

    private func selectionAskMarksJSON(for itemID: String) -> String {
        let marks = store.selectionAskThreads(forItemID: itemID)
            .prefix(40)
            .map { thread -> [String: String] in
                [
                    "id": thread.id.uuidString,
                    "text": String(thread.selectionText.prefix(240)),
                ]
            }
        guard let data = try? JSONSerialization.data(withJSONObject: Array(marks), options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func syncReaderLocationTitle() {
        guard let item = store.selectedMaterialItem else {
            store.updateReaderLocationTitle(nil)
            return
        }
        let displayTitle = store.displayTitle(for: item)
        if item.kind == .html {
            if store.readerLocationTitle == nil {
                store.updateReaderLocationTitle(displayTitle)
            }
            return
        }
        let title = item.kind == .pdf
            ? store.ui("\(displayTitle)，第 \(pdfPageIndex + 1) 页", "\(displayTitle), page \(pdfPageIndex + 1)")
            : displayTitle
        store.updateReaderLocationTitle(title)
    }

    private var floatingTitle: String {
        store.currentReferenceTitle
    }

    private var supportsContentRail: Bool {
        guard let kind = store.selectedMaterialItem?.kind else { return false }
        return kind == .pdf || kind == .html
    }

    private var contentRailItems: [ContentRailItem] {
        switch store.selectedMaterialItem?.kind {
        case .pdf:
            return pdfContentRailItems
        case .html:
            return htmlContentRailItems
        default:
            return []
        }
    }

    private var contentRailActiveID: String? {
        switch store.selectedMaterialItem?.kind {
        case .pdf:
            return Self.pdfContentRailID(pageIndex: pdfPageIndex)
        case .html:
            return htmlContentRailActiveID
        default:
            return nil
        }
    }

    private func contentRail(isRailOnly: Bool, availableWidth: CGFloat) -> some View {
        ContentRailView(
            label: store.ui("文稿导航", "Document Navigation"),
            items: contentRailItems,
            activeID: contentRailActiveID,
            appearanceMode: store.appearanceMode,
            isRailOnly: isRailOnly,
            availableWidth: availableWidth,
            topInset: showsFloatingTitle && !isRailOnly ? 46 : 14,
            bottomInset: store.selectedMaterialItem?.kind == .pdf ? 52 : 18,
            onActivate: { activateContentRailItem($0, railOnly: isRailOnly) },
            onHover: hoverContentRailItem
        )
    }

    private func activateContentRailItem(_ item: ContentRailItem, railOnly: Bool) {
        if railOnly {
            store.requestPaneExpansion(.reader)
        }
        switch store.selectedMaterialItem?.kind {
        case .pdf:
            if let pageIndex = Self.pdfPageIndex(fromContentRailID: item.id) {
                pdfRailTargetPageIndex = pageIndex
                schedulePDFLocationCommit(pageIndex)
            }
        case .html:
            htmlContentRailTarget = WebReaderContentRailTarget(id: item.id)
        default:
            break
        }
    }

    private func hoverContentRailItem(_ item: ContentRailItem?) {
        guard store.selectedMaterialItem?.kind == .pdf,
              let item,
              let pageIndex = Self.pdfPageIndex(fromContentRailID: item.id),
              let url = store.selectedMaterialItem?.url,
              item.previewImage == nil,
              !pendingPDFRailPreviewPages.contains(pageIndex) else { return }
        pendingPDFRailPreviewPages.insert(pageIndex)
        let selectedPath = url.standardizedFileURL.path
        PDFContentRailPreviewLoader.shared.load(url: url, pageIndex: pageIndex) { preview in
            guard store.selectedMaterialItem?.url?.standardizedFileURL.path == selectedPath else { return }
            pendingPDFRailPreviewPages.remove(pageIndex)
            guard let preview,
                  let itemIndex = pdfContentRailItems.firstIndex(where: { $0.id == item.id }) else { return }
            let fallbackTitle = store.ui("第 \(pageIndex + 1) 页", "Page \(pageIndex + 1)")
            let excerpt = preview.excerpt.isEmpty
                ? store.ui("扫描页；预览来自真实 PDF 页面。", "Scanned page; previewed from the real PDF page.")
                : preview.excerpt
            pdfContentRailItems[itemIndex] = ContentRailItem(
                id: item.id,
                position: item.position,
                level: item.level,
                title: preview.title.isEmpty ? fallbackTitle : preview.title,
                excerpt: excerpt,
                metadata: "\(pageIndex + 1) / \(max(pdfPageCount, 1)) · PDF",
                previewImage: preview.image
            )
        }
    }

    private func rebuildPDFContentRail() {
        guard store.selectedMaterialItem?.kind == .pdf, pdfPageCount > 0 else {
            pdfContentRailItems = []
            return
        }
        let denominator = max(pdfPageCount - 1, 1)
        pdfContentRailItems = (0..<pdfPageCount).map { pageIndex in
            let pageNumber = pageIndex + 1
            return ContentRailItem(
                id: Self.pdfContentRailID(pageIndex: pageIndex),
                position: CGFloat(pageIndex) / CGFloat(denominator),
                level: Self.pdfContentRailLevel(pageIndex: pageIndex, pageCount: pdfPageCount),
                title: store.ui("第 \(pageNumber) 页", "Page \(pageNumber)"),
                excerpt: store.ui("悬停以预览真实页面内容。", "Hover to preview the real page content."),
                metadata: "\(pageNumber) / \(pdfPageCount) · PDF"
            )
        }
    }

    private func applyHTMLContentRailSections(_ sections: [WebReaderContentRailSection]) {
        let items = sections.map { section in
            ContentRailItem(
                id: section.id,
                position: section.position,
                level: section.level,
                title: section.title,
                excerpt: section.excerpt,
                metadata: section.metadata
            )
        }
        htmlContentRailItems = items
        if let activeID = htmlContentRailActiveID,
           !htmlContentRailItems.contains(where: { $0.id == activeID }) {
            htmlContentRailActiveID = htmlContentRailItems.first?.id
        }
        applyPendingHTMLLocationIfReady()
    }

    private func applyHTMLContentRailActiveID(_ change: WebReaderContentRailActiveChange) {
        let id = change.id
        // Jump must update the rail highlight immediately. Scroll updates are
        // coalesced so fast section crossings do not re-enter WebReader updateNSView.
        if change.reason == .jump {
            if htmlContentRailActiveID != id {
                htmlContentRailActiveID = id
            }
        } else if change.reason == .scroll {
            scheduleHTMLContentRailActiveID(id)
        } else if htmlContentRailActiveID != id {
            htmlContentRailActiveID = id
        }
        guard change.reason == .scroll || change.reason == .jump else { return }
        let title = id.flatMap { activeID in
            htmlContentRailItems.first(where: { $0.id == activeID })?.title
        }
        scheduleHTMLLocationCommit(id: id, title: title, reason: change.reason)
    }

    private func scheduleHTMLContentRailActiveID(_ id: String?) {
        guard htmlContentRailActiveID != id else { return }
        pendingHTMLContentRailActiveCommit?.cancel()
        pendingHTMLContentRailActiveCommit = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            pendingHTMLContentRailActiveCommit = nil
            if htmlContentRailActiveID != id {
                htmlContentRailActiveID = id
            }
        }
    }

    private func scheduleHTMLLocationCommit(
        id: String?,
        title: String?,
        reason: WebReaderContentRailEventReason
    ) {
        pendingHTMLLocationCommit?.cancel()
        let itemID = store.selectedMaterialItem?.id
        pendingHTMLLocationCommit = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                  store.selectedMaterialItem?.id == itemID,
                  htmlContentRailActiveID == id else { return }
            pendingHTMLLocationCommit = nil
            store.updateReaderHTMLLocation(id: id, title: title, reason: reason.rawValue)
        }
    }

    private func schedulePDFLocationCommit(_ pageIndex: Int) {
        pendingPDFLocationCommit?.cancel()
        let itemID = store.selectedMaterialItem?.id
        pendingPDFLocationCommit = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                  store.selectedMaterialItem?.id == itemID,
                  pdfPageIndex == pageIndex else { return }
            pendingPDFLocationCommit = nil
            store.updateReaderPageIndex(pageIndex)
        }
    }

    private func applyPendingHTMLLocationIfReady() {
        guard store.selectedMaterialItem?.kind == .html,
              !htmlContentRailItems.isEmpty else { return }
        let targetID: String?
        if let savedID = store.readerTargetLocationID,
           let savedSection = htmlContentRailItems.first(where: { $0.id == savedID }),
           store.readerTargetLocationTitle.map({
               Self.normalizedHTMLSectionTitle($0) == Self.normalizedHTMLSectionTitle(savedSection.title)
           }) ?? true {
            targetID = savedSection.id
        } else if let targetTitle = store.readerTargetLocationTitle {
            let normalizedTarget = Self.normalizedHTMLSectionTitle(targetTitle)
            let matches = htmlContentRailItems.filter {
                Self.normalizedHTMLSectionTitle($0.title) == normalizedTarget
            }
            targetID = matches.count == 1 ? matches[0].id : nil
        } else {
            targetID = nil
        }
        guard let targetID else { return }
        let requestID = store.readerTargetLocationRequestID
        guard htmlContentRailTarget?.requestID != requestID else { return }
        htmlContentRailTarget = WebReaderContentRailTarget(id: targetID, requestID: requestID)
    }

    private static func normalizedHTMLSectionTitle(_ title: String) -> String {
        title
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined()
    }

    private static func pdfContentRailID(pageIndex: Int) -> String {
        "pdf-page-\(max(pageIndex, 0))"
    }

    private static func pdfPageIndex(fromContentRailID id: String) -> Int? {
        guard id.hasPrefix("pdf-page-") else { return nil }
        return Int(id.dropFirst("pdf-page-".count))
    }

    private static func pdfContentRailLevel(pageIndex: Int, pageCount: Int) -> Int {
        if pageIndex == 0 || pageIndex == pageCount - 1 { return 1 }
        if (pageIndex + 1).isMultiple(of: 10) { return 2 }
        return 4
    }

    @ViewBuilder
    private var importedDocumentAdaptationControl: some View {
        if supportsImportedDocumentColorAdaptation {
            Button {
                withAnimation(WeiBeiMotion.appearance) {
                    store.toggleImportedDocumentColorAdaptation()
                }
            } label: {
                Image(systemName: "eyeglasses")
            }
            .buttonStyle(WeiBeiIconButtonStyle(active: store.adaptImportedDocumentColors, size: 22))
            .accessibilityLabel(Text(importedDocumentAdaptationLabel))
            .help(importedDocumentAdaptationLabel)
        }
    }

    /// Top-chrome entry for past selection-ask threads (replaces the mid-document legend overlay).
    @ViewBuilder
    private var selectionAskThreadsMenu: some View {
        let threads = store.selectionAskThreads(forItemID: store.selectedMaterialItem?.id)
        if !threads.isEmpty {
            Menu {
                ForEach(threads.prefix(12)) { thread in
                    Button {
                        store.openSelectionAskThread(thread.id, jumpToConversation: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.truncatedAskMenuLabel(thread.selectionText))
                            if !thread.ownerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(thread.ownerTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } label: {
                Text(store.ui("已问 · \(threads.count)", "Asked · \(threads.count)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.9))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(WeiBeiTheme.cinnabarSoft.opacity(0.55), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .help(store.ui("打开已问选区列表", "Open asked-selection list"))
            .accessibilityLabel(Text(store.ui("已问选区", "Asked selections")))
        }
    }

    private static func truncatedAskMenuLabel(_ text: String, limit: Int = 28) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)) + "…"
    }

    private var supportsImportedDocumentColorAdaptation: Bool {
        guard let item = store.selectedMaterialItem, item.url != nil else { return false }
        return item.kind == .pdf || item.kind == .html
    }

    private var importedDocumentAdaptationLabel: String {
        if store.adaptImportedDocumentColors {
            return store.ui("显示导入文稿原始色彩", "Show Original Document Colors")
        }
        return store.ui("让导入文稿跟随魏碑阅读环境", "Adapt Document to WeiBei Reading")
    }

    private func applyPendingPDFPageIfReady() {
        guard let target = pendingPDFPageIndex,
              let requestID = pendingPDFPageRequestID,
              store.selectedMaterialItem?.kind == .pdf,
              pdfPageCount > 0 else { return }
        pdfBrowseMode = .page
        let resolvedPageIndex = min(max(target, 0), max(pdfPageCount - 1, 0))
        pdfPageIndex = resolvedPageIndex
        if pendingPDFPageRecordsLocation {
            schedulePDFLocationCommit(resolvedPageIndex)
        }
        pendingPDFPageIndex = nil
        pendingPDFPageRequestID = nil
        pendingPDFPageRecordsLocation = false
        store.consumeReaderPDFPageRequest(requestID)
        syncReaderLocationTitle()
    }

    private func capturePendingPDFPageRequest() {
        pendingPDFPageIndex = store.readerTargetPageIndex
        pendingPDFPageRequestID = store.readerTargetPageRequestID
        pendingPDFPageRecordsLocation = store.readerTargetPageRecordsLocation
    }

    private var pdfFloatingControls: some View {
        HStack(spacing: 6) {
            pdfControls
        }
        .buttonStyle(.plain)
        .foregroundStyle(WeiBeiTheme.ink)
        .padding(3)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(WeiBeiTheme.paperRaised.opacity(PDFModeChipPresentation.fillOpacity(isExpanded: pdfControlsExpanded, isHovering: pdfControlsHovering)))
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .opacity(pdfControlsExpanded ? 0.055 : 0.0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(WeiBeiTheme.hairline.opacity(PDFModeChipPresentation.strokeOpacity(isExpanded: pdfControlsExpanded, isHovering: pdfControlsHovering)), lineWidth: 1)
        }
        .shadow(color: WeiBeiTheme.ink.opacity(pdfControlsExpanded ? 0.045 : 0.0), radius: 7, y: 3)
        .opacity(PDFModeChipPresentation.controlOpacity(isExpanded: pdfControlsExpanded, isHovering: pdfControlsHovering))
        .offset(x: 0)
        .scaleEffect(pdfControlsExpanded ? 1 : 0.985, anchor: .trailing)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            schedulePDFControlsCollapse(after: 0.9)
        }
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                pdfControlsHovering = hovering
            }
            if !hovering {
                schedulePDFControlsCollapse(after: 0.28)
            }
        }
    }

    private var pdfTextLayerNotice: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 11, weight: .medium))
            Text(store.ui("未检测到可选文本层", "No selectable text layer"))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(WeiBeiTheme.paperRaised.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(0.24), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var pdfControls: some View {
        pdfModeToggle

        if pdfBrowseMode == .page, pdfPageCount > 1 {
            Group {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.55))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 2)

                Button {
                    revealPDFControls()
                    let next = PageNavigator.previous(pdfPageIndex)
                    guard next != pdfPageIndex else { return }
                    store.recordReaderPageNavigationPoint()
                    pdfPageIndex = next
                    schedulePDFLocationCommit(next)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 22))
                .keyboardShortcut("[", modifiers: [.command, .option])
                .accessibilityLabel(Text(store.ui("上一页", "Previous page")))
                .help(store.ui("上一页", "Previous page"))

                Text(PageNavigator.display(pdfPageIndex, pageCount: pdfPageCount))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 50, height: 22)

                Button {
                    revealPDFControls()
                    let next = PageNavigator.next(pdfPageIndex, pageCount: pdfPageCount)
                    guard next != pdfPageIndex else { return }
                    store.recordReaderPageNavigationPoint()
                    pdfPageIndex = next
                    schedulePDFLocationCommit(next)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 22))
                .keyboardShortcut("]", modifiers: [.command, .option])
                .accessibilityLabel(Text(store.ui("下一页", "Next page")))
                .help(store.ui("下一页", "Next page"))
            }
            .transition(WeiBeiTransition.floating)
        }
    }

    private var pdfModeToggle: some View {
        Button {
            withAnimation(WeiBeiMotion.panel) {
                pdfBrowseMode = pdfBrowseMode.toggled
            }
            revealPDFControls(collapseAfter: 0.85)
        } label: {
            HStack(spacing: showsPDFModeLabel ? 5 : 0) {
                Image(systemName: pdfBrowseMode.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                if showsPDFModeLabel {
                    Text(pdfBrowseMode.label(language: store.interfaceLanguage))
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(pdfModeForeground)
            .padding(.horizontal, showsPDFModeLabel ? 7 : 4)
            .frame(width: showsPDFModeLabel ? nil : 18, height: 24)
            .background(WeiBeiTheme.paperInset.opacity(pdfControlsActive ? 0.16 : 0.08))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(WeiBeiTheme.hairline.opacity(pdfControlsActive ? 0.58 : 0.18), lineWidth: 1)
            }
            .animation(WeiBeiMotion.micro, value: showsPDFModeLabel)
        }
        .accessibilityLabel(Text(store.ui("切换 PDF 浏览方式，当前\(pdfBrowseMode.label(language: store.interfaceLanguage))", "Switch PDF browsing mode. Current: \(pdfBrowseMode.label(language: store.interfaceLanguage))")))
        .help(store.ui("切换到\(pdfBrowseMode.toggled.help(language: store.interfaceLanguage))", "Switch to \(pdfBrowseMode.toggled.help(language: store.interfaceLanguage))"))
    }

    private var pdfControlsActive: Bool {
        pdfControlsExpanded
    }

    private var pdfModeForeground: Color {
        if pdfBrowseMode == .page {
            return WeiBeiTheme.cinnabar
        }
        return WeiBeiTheme.secondaryInk
    }

    private var showsPDFModeLabel: Bool {
        PDFModeChipPresentation.showsLabel(isExpanded: pdfControlsExpanded)
    }

    private func revealPDFControls(collapseAfter delay: TimeInterval = 1.25) {
        withAnimation(WeiBeiMotion.hover) {
            pdfControlsExpanded = true
        }
        schedulePDFControlsCollapse(after: delay)
    }

    private func schedulePDFControlsCollapse(after delay: TimeInterval) {
        let token = UUID()
        pdfControlsCollapseToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard pdfControlsCollapseToken == token else { return }
            collapsePDFControls()
        }
    }

    private func collapsePDFControls() {
        withAnimation(WeiBeiMotion.hover) {
            pdfControlsExpanded = false
            pdfControlsHovering = false
        }
    }

    @ViewBuilder
    private var readerBody: some View {
        if let item = store.selectedMaterialItem {
            switch item.kind {
            case .pdf:
                if let url = item.url {
                    PDFReaderRepresentable(
                        url: url,
                        browseMode: pdfBrowseMode,
                        searchQuery: store.effectiveReaderSearch,
                        searchTargetPageIndex: store.readerSourceHighlightPageIndex,
                        appearanceMode: store.appearanceMode,
                        adaptsDocumentColors: store.adaptImportedDocumentColors,
                        pageIndex: $pdfPageIndex,
                        pageCount: $pdfPageCount,
                        railTargetPageIndex: $pdfRailTargetPageIndex,
                        underlineSnippets: store.selectionAskThreads(forItemID: item.id).map(\.selectionText),
                        askUnderlineMarks: store.selectionAskThreads(forItemID: item.id).map {
                            (id: $0.id.uuidString, text: $0.selectionText)
                        },
                        onAskUnderlineActivate: { threadID, anchor in
                            if let uuid = UUID(uuidString: threadID) {
                                store.openSelectionAskThread(uuid, jumpToConversation: false, anchor: anchor)
                            }
                        },
                        onUserPageChange: schedulePDFLocationCommit,
                        onSelectableTextChange: { available in pdfHasSelectableText = available }
                    ) { text, anchor, selectionPageIndex in
                        let title = store.displayTitle(for: item)
                        let ownerTitle = store.ui("\(title)，第 \(selectionPageIndex + 1) 页", "\(title), page \(selectionPageIndex + 1)")
                        store.updateReaderLocationTitle(ownerTitle)
                        store.updateSelection(text, source: .document, anchor: anchor, ownerTitle: ownerTitle)
                    }
                } else {
                    MaterialReadFailureView(fileName: store.displayTitle(for: item))
                }
            case .html:
                if let url = item.url {
                    WebReaderRepresentable(
                        url: url,
                        searchQuery: store.effectiveReaderSearch,
                        appearanceMode: store.appearanceMode,
                        adaptsDocumentColors: store.adaptImportedDocumentColors,
                        contentRailTarget: htmlContentRailTarget,
                        selectionAskMarks: selectionAskMarksJSON(for: item.id),
                        onContentRailChange: applyHTMLContentRailSections,
                        onContentRailActiveChange: applyHTMLContentRailActiveID,
                        onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
                        onSelectionAskMark: { threadID in
                            if let uuid = UUID(uuidString: threadID) {
                                store.openSelectionAskThread(uuid, jumpToConversation: false)
                            }
                        }
                    ) { text, anchor in
                        store.updateSelection(text, source: .document, anchor: anchor)
                    }
                } else {
                    MaterialReadFailureView(fileName: store.displayTitle(for: item))
                }
            case .markdown:
                if let url = item.url {
                    if let data = try? CourseProjectFileWorker
                        .readBoundedRegularFile(
                            at: url,
                            maximumByteCount: CourseProjectFileWorker
                                .markdownMaximumByteCount
                        ),
                       let text = String(data: data, encoding: .utf8) {
                        markdownReader(markdown: text, markdownBaseURL: url.deletingLastPathComponent())
                    } else {
                        MarkdownReadFailureView(fileName: url.lastPathComponent)
                    }
                } else {
                    MaterialReadFailureView(fileName: store.displayTitle(for: item))
                }
            case .text:
                if let url = item.url,
                   let data = try? CourseProjectFileWorker
                    .readBoundedRegularFile(
                        at: url,
                        maximumByteCount: CourseProjectFileWorker
                            .markdownMaximumByteCount
                    ),
                   let text = String(data: data, encoding: .utf8) {
                    PlainTextReaderView(text: text, searchQuery: store.effectiveReaderSearch, appearanceMode: store.appearanceMode) { text, anchor in
                        store.updateSelection(text, source: .document, anchor: anchor)
                    }
                } else {
                    MaterialReadFailureView(fileName: store.displayTitle(for: item))
                }
            }
        } else if store.selectedItem?.isNotebookNote == true {
            NotebookSelectedReaderView()
        } else {
            EmptyReaderView()
        }
    }

    private func markdownReader(markdown: String, markdownBaseURL: URL?) -> some View {
        MarkdownDocumentReaderView(
            markdown: markdown,
            markdownBaseURL: markdownBaseURL,
            searchQuery: store.effectiveReaderSearch,
            appearanceMode: store.appearanceMode,
            interfaceLanguage: store.interfaceLanguage,
            selectionAskMarks: selectionAskMarksJSON(for: store.selectedMaterialItem?.id ?? ""),
            onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
            onSourceReference: { reference in store.openSourceReference(reference) },
            onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
            onSelectionAskMark: { threadID in
                if let uuid = UUID(uuidString: threadID) {
                    store.openSelectionAskThread(uuid, jumpToConversation: false)
                }
            }
        ) { text, anchor in
            store.updateSelection(text, source: .document, anchor: anchor)
        }
    }

}

struct WebReaderContentRailSection: Hashable {
    var id: String
    var position: CGFloat
    var level: Int
    var title: String
    var excerpt: String
    var metadata: String
}

struct WebReaderContentRailTarget: Equatable {
    var id: String
    var requestID = UUID()
}

enum WebReaderContentRailEventReason: String {
    case initial
    case resize
    case mutation
    case scroll
    case jump
    case programmatic
    case unknown
}

struct WebReaderContentRailActiveChange {
    var id: String?
    var reason: WebReaderContentRailEventReason
}

private struct PDFContentRailPreview {
    var image: NSImage
    var title: String
    var excerpt: String
}

private final class PDFContentRailPreviewBox: NSObject {
    let preview: PDFContentRailPreview

    init(_ preview: PDFContentRailPreview) {
        self.preview = preview
    }
}

private final class PDFContentRailPreviewLoader {
    static let shared = PDFContentRailPreviewLoader()

    private let queue = DispatchQueue(label: "WeiBei.PDFContentRailPreview", qos: .userInitiated)
    private let documentCache = NSCache<NSString, PDFDocument>()
    private let previewCache = NSCache<NSString, PDFContentRailPreviewBox>()

    private init() {
        documentCache.countLimit = 3
        previewCache.countLimit = 80
    }

    func load(url: URL, pageIndex: Int, completion: @escaping (PDFContentRailPreview?) -> Void) {
        let documentKey = cacheKey(for: url)
        let previewKey = "\(documentKey)#page=\(pageIndex)" as NSString
        if let cached = previewCache.object(forKey: previewKey) {
            DispatchQueue.main.async {
                completion(cached.preview)
            }
            return
        }

        queue.async { [documentCache, previewCache] in
            let key = documentKey as NSString
            let document: PDFDocument
            if let cached = documentCache.object(forKey: key) {
                document = cached
            } else if let loaded = PDFDocument(url: url) {
                document = loaded
                documentCache.setObject(loaded, forKey: key)
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            guard let page = document.page(at: pageIndex) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let image = page.thumbnail(of: NSSize(width: 180, height: 240), for: .mediaBox)
            let lines = (page.string ?? "")
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let title = lines.first.map { String($0.prefix(52)) } ?? ""
            let bodyLines = lines.count > 1 ? lines.dropFirst() : lines[...]
            let excerpt = String(bodyLines.joined(separator: " ").prefix(180))
            let preview = PDFContentRailPreview(image: image, title: title, excerpt: excerpt)
            previewCache.setObject(PDFContentRailPreviewBox(preview), forKey: previewKey)
            DispatchQueue.main.async {
                completion(preview)
            }
        }
    }

    private func cacheKey(for url: URL) -> String {
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)#\(modificationDate)"
    }
}

private enum PDFBrowseMode: String, CaseIterable, Identifiable {
    case scroll
    case page

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .scroll:
            return language.text("滚动", "Scroll")
        case .page:
            return language.text("翻页", "Page")
        }
    }

    var systemImage: String {
        switch self {
        case .scroll: "arrow.up.and.down"
        case .page: "rectangle.portrait"
        }
    }

    var toggled: PDFBrowseMode {
        switch self {
        case .scroll: .page
        case .page: .scroll
        }
    }

    func help(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .scroll:
            return language.text("连续滚动浏览 PDF", "continuous PDF scrolling")
        case .page:
            return language.text("单页翻页浏览 PDF", "single-page PDF browsing")
        }
    }
}

private struct ReaderPaneSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

private enum ReaderPlatformViewSizing {
    /// Prefer the SwiftUI proposal so AppKit never walks WKWebView/PDFView Auto Layout
    /// for intrinsic fitting size (that path froze the main thread in production hangs).
    static func proposedReaderSize(
        _ proposal: ProposedViewSize,
        fallback: CGSize
    ) -> CGSize {
        let width = proposal.width ?? (fallback.width > 1 ? fallback.width : 1)
        let height = proposal.height ?? (fallback.height > 1 ? fallback.height : 1)
        return CGSize(width: max(width, 1), height: max(height, 1))
    }
}

private struct PDFReaderRepresentable: NSViewRepresentable {
    var url: URL
    var browseMode: PDFBrowseMode
    var searchQuery: String
    var searchTargetPageIndex: Int?
    var appearanceMode: WeiBeiAppearanceMode
    var adaptsDocumentColors: Bool
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    @Binding var railTargetPageIndex: Int?
    var underlineSnippets: [String] = []
    /// Asked-selection marks with thread ids for hover/click reopen.
    var askUnderlineMarks: [(id: String, text: String)] = []
    var onAskUnderlineActivate: (String, CGPoint?) -> Void = { _, _ in }
    var onUserPageChange: (Int) -> Void
    var onSelectableTextChange: (Bool?) -> Void = { _ in }
    var onSelectionChange: (String, CGPoint?, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pageIndex: $pageIndex,
            pageCount: $pageCount,
            onUserPageChange: onUserPageChange,
            onSelectableTextChange: onSelectableTextChange,
            onSelectionChange: onSelectionChange,
            onAskUnderlineActivate: onAskUnderlineActivate
        )
    }

    func makeNSView(context: Context) -> ReaderPDFView {
        let view = ReaderPDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.backgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)
        view.configureDocumentColorAdaptation(enabled: adaptsDocumentColors, appearanceMode: appearanceMode)
        DispatchQueue.main.async {
            WeiBeiQuietScrollers.configureRecursively(
                in: view,
                hasVerticalScroller: true,
                hasHorizontalScroller: false
            )
            WeiBeiQuietScrollers.flashRecursively(in: view, repeatCount: 2)
        }
        context.coordinator.observe(view)
        view.reportCurrentSelection = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.reportCurrentSelection(in: view)
        }
        view.handleAskUnderlineHover = { [weak coordinator = context.coordinator, weak view] point in
            guard let view else { return }
            coordinator?.handleAskUnderlineHover(at: point, in: view)
        }
        view.handleAskUnderlineClick = { [weak coordinator = context.coordinator, weak view] point in
            guard let view else { return false }
            return coordinator?.handleAskUnderlineClick(at: point, in: view) ?? false
        }
        return view
    }

    /// Accept the SwiftUI proposal instead of Auto Layout fittingSize on PDFKit.
    /// Same hang class as HTML WKWebView: GeometryReader → PlatformView.sizeThatFits.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: ReaderPDFView,
        context: Context
    ) -> CGSize? {
        ReaderPlatformViewSizing.proposedReaderSize(proposal, fallback: nsView.bounds.size)
    }

    func updateNSView(_ view: ReaderPDFView, context: Context) {
        context.coordinator.pageIndex = $pageIndex
        context.coordinator.pageCount = $pageCount
        context.coordinator.appearanceMode = appearanceMode
        context.coordinator.onUserPageChange = onUserPageChange
        context.coordinator.onSelectableTextChange = onSelectableTextChange
        context.coordinator.onAskUnderlineActivate = onAskUnderlineActivate
        view.backgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)
        view.configureDocumentColorAdaptation(enabled: adaptsDocumentColors, appearanceMode: appearanceMode)

        if context.coordinator.loadedURL != url {
            pageCount = 0
            pageIndex = 0
            context.coordinator.load(url, in: view)
        }

        let mode: PDFDisplayMode = browseMode == .scroll ? .singlePageContinuous : .singlePage
        let modeChanged = view.displayMode != mode
        if modeChanged {
            view.displayMode = mode
            view.autoScales = true
        }

        if browseMode == .page,
           let page = view.document?.page(at: min(pageIndex, max(pageCount - 1, 0))),
           view.currentPage != page {
            view.go(to: page)
        }

        if let targetPageIndex = railTargetPageIndex,
           let page = view.document?.page(at: min(max(targetPageIndex, 0), max(pageCount - 1, 0))) {
            view.go(to: page)
            DispatchQueue.main.async {
                if railTargetPageIndex == targetPageIndex {
                    railTargetPageIndex = nil
                }
            }
        }

        context.coordinator.applySearch(
            searchQuery,
            targetPageIndex: searchTargetPageIndex,
            in: view
        )
        context.coordinator.applyAskUnderlines(askUnderlineMarks.isEmpty
            ? underlineSnippets.map { (id: "", text: $0) }
            : askUnderlineMarks, in: view)
        DispatchQueue.main.async {
            WeiBeiQuietScrollers.configureRecursively(
                in: view,
                hasVerticalScroller: true,
                hasHorizontalScroller: false
            )
            if modeChanged {
                WeiBeiQuietScrollers.flashRecursively(in: view, repeatCount: 2)
            }
        }
    }

    static func dismantleNSView(_ view: ReaderPDFView, coordinator: Coordinator) {
        coordinator.suspend()
        view.reportCurrentSelection = nil
    }

    final class Coordinator: NSObject {
        var pageIndex: Binding<Int>
        var pageCount: Binding<Int>
        var onUserPageChange: (Int) -> Void
        var onSelectableTextChange: (Bool?) -> Void
        var onSelectionChange: (String, CGPoint?, Int) -> Void
        var onAskUnderlineActivate: (String, CGPoint?) -> Void
        var appearanceMode: WeiBeiAppearanceMode = .paper
        private weak var observedView: PDFView?
        private var observer: NSObjectProtocol?
        private var pageObserver: NSObjectProtocol?
        private var eventMonitor: Any?
        private var selectionWork: DispatchWorkItem?
        private var nativeTextPageIndexes: Set<Int> = []
        private var ocrPagesByPageIndex: [Int: PDFOCRPage] = [:]
        private var pendingOCRPageIndexes: Set<Int> = []
        private var ocrHighlightedLinesByPageIndex: [Int: Set<Int>] = [:]
        private var lastSearchQuery = ""
        private var lastSearchTargetPageIndex: Int?
        private var loadGeneration = 0
        private var userNavigationDeadline = Date.distantPast
        private(set) var loadedURL: URL?
        private var lastAppliedAskUnderlineMarks: [(id: String, text: String)] = []
        private var askUnderlineHits: [(threadID: String, pageIndex: Int, hitBounds: CGRect)] = []
        private var hoveredAskThreadID: String?
        private let askUnderlineMarker = "weibei-selection-ask"
        private let askUnderlineHoverMarker = "weibei-selection-ask-hover"

        init(
            pageIndex: Binding<Int>,
            pageCount: Binding<Int>,
            onUserPageChange: @escaping (Int) -> Void,
            onSelectableTextChange: @escaping (Bool?) -> Void,
            onSelectionChange: @escaping (String, CGPoint?, Int) -> Void,
            onAskUnderlineActivate: @escaping (String, CGPoint?) -> Void
        ) {
            self.pageIndex = pageIndex
            self.pageCount = pageCount
            self.onUserPageChange = onUserPageChange
            self.onSelectableTextChange = onSelectableTextChange
            self.onSelectionChange = onSelectionChange
            self.onAskUnderlineActivate = onAskUnderlineActivate
        }

        func suspend() {
            selectionWork?.cancel()
            removeObservers()
        }

        func load(_ url: URL, in view: PDFView) {
            loadGeneration += 1
            let generation = loadGeneration
            loadedURL = url
            view.document = nil
            nativeTextPageIndexes = []
            clearOCROverlays(in: view)
            lastSearchQuery = ""
            lastSearchTargetPageIndex = nil
            lastAppliedAskUnderlineMarks = []
            askUnderlineHits = []
            hoveredAskThreadID = nil
            onSelectableTextChange(nil)

            DispatchQueue.global(qos: .userInitiated).async {
                let document = PDFDocument(url: url)
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view, self.loadGeneration == generation, self.loadedURL == url else { return }
                    view.document = document
                    view.autoScales = true
                    self.pageCount.wrappedValue = document?.pageCount ?? 0
                    self.pageIndex.wrappedValue = 0
                    if let document {
                        self.nativeTextPageIndexes = Self.selectableTextPageIndexes(in: document)
                    }
                    self.updateSelectableTextState(in: view)
                    self.configureOCROverlays(for: document, generation: generation, in: view)
                    self.ensureOCRForCurrentPage(in: view)
                    if !self.lastSearchQuery.isEmpty {
                        self.applySearch(
                            self.lastSearchQuery,
                            targetPageIndex: self.lastSearchTargetPageIndex,
                            in: view,
                            force: true
                        )
                    }
                    WeiBeiQuietScrollers.flashRecursively(in: view, repeatCount: 2)
                }
            }
        }

        private static func selectableTextPageIndexes(in document: PDFDocument) -> Set<Int> {
            Set((0..<max(document.pageCount, 0)).filter { index in
                guard let page = document.page(at: index) else { return false }
                return page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            })
        }

        private static func ocrCandidatePageIndexes(in document: PDFDocument, maxPages: Int = 12) -> [Int] {
            let pageLimit = min(max(document.pageCount, 0), max(maxPages, 0))
            guard pageLimit > 0 else { return [] }
            return (0..<pageLimit).filter { index in
                guard let page = document.page(at: index) else { return false }
                return page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            }
        }

        private func configureOCROverlays(for document: PDFDocument?, generation: Int, in view: PDFView) {
            guard let document else {
                clearOCROverlays(in: view)
                updateSelectableTextState(in: view)
                return
            }

            let pageIndexes = Self.ocrCandidatePageIndexes(in: document)
            guard !pageIndexes.isEmpty else {
                clearOCROverlays(in: view)
                updateSelectableTextState(in: view)
                return
            }

            pendingOCRPageIndexes = Set(pageIndexes)
            updateSelectableTextState(in: view)

            DispatchQueue.global(qos: .userInitiated).async {
                let pages = PDFOCRTextExtractor.pages(from: document, pageIndexes: pageIndexes)
                let indexed = Dictionary(uniqueKeysWithValues: pages.map { ($0.pageIndex, $0) })
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view, self.loadGeneration == generation else { return }
                    self.pendingOCRPageIndexes.subtract(pageIndexes)
                    self.ocrPagesByPageIndex = indexed
                    self.setOCRPageOverlayProvider(indexed.isEmpty ? nil : self, in: view)
                    self.updateSelectableTextState(in: view)
                    if self.lastSearchQuery.isEmpty {
                        view.layoutDocumentView()
                    } else {
                        self.applySearch(
                            self.lastSearchQuery,
                            targetPageIndex: self.lastSearchTargetPageIndex,
                            in: view,
                            force: true
                        )
                    }
                }
            }
        }

        private func clearOCROverlays(in view: PDFView) {
            ocrPagesByPageIndex = [:]
            pendingOCRPageIndexes = []
            ocrHighlightedLinesByPageIndex = [:]
            setOCRPageOverlayProvider(nil, in: view)
            view.layoutDocumentView()
        }

        private func updateSelectableTextState(in view: PDFView) {
            guard let document = view.document,
                  let page = view.currentPage else {
                onSelectableTextChange(nil)
                return
            }
            let index = document.index(for: page)
            guard index != NSNotFound else {
                onSelectableTextChange(nil)
                return
            }
            if pendingOCRPageIndexes.contains(index) {
                onSelectableTextChange(nil)
                return
            }
            onSelectableTextChange(nativeTextPageIndexes.contains(index) || ocrPagesByPageIndex[index] != nil)
        }

        private func setOCRPageOverlayProvider(_ provider: PDFPageOverlayViewProvider?, in view: PDFView) {
            view.pageOverlayViewProvider = provider
            view.isInMarkupMode = false
        }

        private func ensureOCRForCurrentPage(in view: PDFView) {
            guard let document = view.document,
                  let page = view.currentPage else { return }
            let index = document.index(for: page)
            guard index != NSNotFound,
                  !nativeTextPageIndexes.contains(index),
                  ocrPagesByPageIndex[index] == nil,
                  !pendingOCRPageIndexes.contains(index),
                  page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { return }

            pendingOCRPageIndexes.insert(index)
            updateSelectableTextState(in: view)
            let generation = loadGeneration

            DispatchQueue.global(qos: .userInitiated).async {
                let pages = PDFOCRTextExtractor.pages(from: document, pageIndexes: [index])
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view, self.loadGeneration == generation else { return }
                    self.pendingOCRPageIndexes.remove(index)
                    if let page = pages.first {
                        self.ocrPagesByPageIndex[page.pageIndex] = page
                    }
                    self.setOCRPageOverlayProvider(self.ocrPagesByPageIndex.isEmpty ? nil : self, in: view)
                    self.updateSelectableTextState(in: view)
                    if self.lastSearchQuery.isEmpty {
                        view.layoutDocumentView()
                    } else {
                        self.applySearch(
                            self.lastSearchQuery,
                            targetPageIndex: self.lastSearchTargetPageIndex,
                            in: view,
                            force: true
                        )
                    }
                }
            }
        }

        func observe(_ view: PDFView) {
            removeObservers()
            observedView = view
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewSelectionChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                guard let self, let view = self.observedView else { return }
                self.reportCurrentSelection(in: view)
            }
            pageObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                guard let self, let view = self.observedView, let document = view.document, let page = view.currentPage else { return }
                self.pageCount.wrappedValue = document.pageCount
                let index = document.index(for: page)
                self.pageIndex.wrappedValue = index
                if Date() <= self.userNavigationDeadline {
                    self.onUserPageChange(index)
                }
                self.updateSelectableTextState(in: view)
                self.ensureOCRForCurrentPage(in: view)
            }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown]) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                if event.type == .keyDown {
                    if self.isFirstResponderInside(view) {
                        self.markUserNavigationIntent()
                    }
                    return event
                }
                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }
                if event.type == .scrollWheel {
                    self.markUserNavigationIntent()
                    return event
                }
                if event.type == .leftMouseDown {
                    view.window?.makeFirstResponder(view)
                    return event
                }
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.reportCurrentSelection(in: view)
                }
                return event
            }
        }

        private func markUserNavigationIntent() {
            userNavigationDeadline = Date().addingTimeInterval(0.9)
        }

        private func isFirstResponderInside(_ view: NSView) -> Bool {
            guard let responder = view.window?.firstResponder as? NSView else { return false }
            return responder === view || responder.isDescendant(of: view)
        }

        private func removeObservers() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            if let pageObserver {
                NotificationCenter.default.removeObserver(pageObserver)
                self.pageObserver = nil
            }
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        func reportCurrentSelection(in view: PDFView) {
            guard let selection = view.currentSelection,
                  let text = selection.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                selectionWork?.cancel()
                onSelectionChange("", nil, pageIndex.wrappedValue)
                return
            }
            selection.color = WeiBeiNativePalette.selectionFill(for: appearanceMode)
            let selectedPageIndex = Self.pageIndex(for: selection, in: view) ?? pageIndex.wrappedValue
            reportSelectionAfterDragSettles(
                text: text,
                anchor: Self.anchor(for: selection, in: view),
                pageIndex: selectedPageIndex
            )
        }

        private func reportSelectionAfterDragSettles(text: String, anchor: CGPoint?, pageIndex: Int) {
            selectionWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onSelectionChange(text, anchor, pageIndex)
            }
            selectionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        }

        private static func anchor(for selection: PDFSelection, in view: PDFView) -> CGPoint? {
            guard let page = selection.pages.first else { return nil }
            let bounds = selection.bounds(for: page)
            guard !bounds.isEmpty else { return nil }
            let localRect = view.convert(bounds, from: page)
            let localPoint = CGPoint(x: localRect.midX, y: localRect.minY)
            return SelectionAnchorContentPoint.fromLocalPoint(localPoint, in: view)
        }

        private static func pageIndex(for selection: PDFSelection, in view: PDFView) -> Int? {
            guard let page = selection.pages.first, let document = view.document else { return nil }
            let index = document.index(for: page)
            return index == NSNotFound ? nil : index
        }

        func applySearch(
            _ query: String,
            targetPageIndex: Int?,
            in view: PDFView,
            force: Bool = false
        ) {
            let query = ReaderSearch.cleaned(query)
            guard force
                    || query != lastSearchQuery
                    || targetPageIndex != lastSearchTargetPageIndex else {
                return
            }
            lastSearchQuery = query
            lastSearchTargetPageIndex = targetPageIndex

            guard !query.isEmpty else {
                view.highlightedSelections = nil
                view.clearSelection()
                setOCRHighlightedLines([:], in: view)
                return
            }

            let allMatches = view.document?.findString(
                query,
                withOptions: [.caseInsensitive, .diacriticInsensitive]
            ) ?? []
            let matches = targetPageIndex.map { targetPageIndex in
                allMatches.filter { selection in
                    selection.pages.contains { page in
                        guard let document = view.document else { return false }
                        return document.index(for: page) == targetPageIndex
                    }
                }
            } ?? allMatches
            view.highlightedSelections = matches
            if let first = matches.first {
                setOCRHighlightedLines([:], in: view)
                view.go(to: first)
            } else {
                applyOCRSearch(
                    query,
                    targetPageIndex: targetPageIndex,
                    in: view
                )
            }
        }

        /// Cinnabar underlines for selection-ask history (PDF text layer).
        /// Uses per-line thin strips — never the multi-line union bounds (those look like red highlights).
        func applyAskUnderlines(_ marks: [(id: String, text: String)], in view: PDFView) {
            guard let document = view.document else { return }
            let signature = marks.map { "\($0.id)|\($0.text)" }
            let previous = lastAppliedAskUnderlineMarks.map { "\($0.id)|\($0.text)" }
            guard signature != previous else { return }
            lastAppliedAskUnderlineMarks = marks
            askUnderlineHits = []
            hoveredAskThreadID = nil
            clearAskUnderlineAnnotations(in: document, includingHover: true)
            let cinnabar = NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.12, alpha: 0.92)
            for mark in marks {
                let needle = mark.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard needle.count >= 4 else { continue }
                let matches = document.findString(needle, withOptions: [.caseInsensitive])
                for selection in matches.prefix(2) {
                    for line in selection.selectionsByLine() {
                        for page in line.pages {
                            let lineBounds = line.bounds(for: page)
                            guard lineBounds.width > 2, lineBounds.height > 0.5 else { continue }
                            var underlineBounds = lineBounds
                            let thickness = min(2.0, max(1.15, lineBounds.height * 0.1))
                            underlineBounds.origin.y = lineBounds.minY
                            underlineBounds.size.height = thickness
                            let annotation = PDFAnnotation(bounds: underlineBounds, forType: .underline, withProperties: nil)
                            annotation.color = cinnabar
                            annotation.userName = askUnderlineMarker
                            page.addAnnotation(annotation)
                            let pageIndex = document.index(for: page)
                            if !mark.id.isEmpty, pageIndex != NSNotFound {
                                askUnderlineHits.append((
                                    threadID: mark.id,
                                    pageIndex: pageIndex,
                                    hitBounds: lineBounds.insetBy(dx: -2, dy: -2)
                                ))
                            }
                        }
                    }
                }
            }
        }

        func handleAskUnderlineHover(at viewPoint: CGPoint, in view: PDFView) {
            let threadID = askThreadID(at: viewPoint, in: view)
            guard threadID != hoveredAskThreadID else { return }
            hoveredAskThreadID = threadID
            applyAskUnderlineHoverHighlight(in: view)
            if threadID != nil {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.iBeam.set()
            }
        }

        @discardableResult
        func handleAskUnderlineClick(at viewPoint: CGPoint, in view: PDFView) -> Bool {
            guard let hit = askUnderlineHit(at: viewPoint, in: view) else { return false }
            // Anchor at the mark's visual center-bottom so the expanded panel docks beside it.
            guard let document = view.document,
                  let page = document.page(at: hit.pageIndex) else {
                onAskUnderlineActivate(hit.threadID, SelectionAnchorContentPoint.fromLocalPoint(viewPoint, in: view))
                return true
            }
            let localRect = view.convert(hit.hitBounds, from: page)
            let localPoint = CGPoint(x: localRect.midX, y: localRect.minY)
            let anchor = SelectionAnchorContentPoint.fromLocalPoint(localPoint, in: view)
            onAskUnderlineActivate(hit.threadID, anchor)
            return true
        }

        private func askUnderlineHit(at viewPoint: CGPoint, in view: PDFView) -> (threadID: String, pageIndex: Int, hitBounds: CGRect)? {
            guard let document = view.document,
                  let page = view.page(for: viewPoint, nearest: true) else { return nil }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { return nil }
            let pagePoint = view.convert(viewPoint, to: page)
            return askUnderlineHits.first(where: {
                $0.pageIndex == pageIndex && $0.hitBounds.contains(pagePoint)
            })
        }

        private func askThreadID(at viewPoint: CGPoint, in view: PDFView) -> String? {
            askUnderlineHit(at: viewPoint, in: view)?.threadID
        }

        private func applyAskUnderlineHoverHighlight(in view: PDFView) {
            guard let document = view.document else { return }
            clearAskUnderlineAnnotations(in: document, includingHover: true, underlines: false)
            guard let threadID = hoveredAskThreadID else { return }
            let fill = NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.12, alpha: 0.12)
            for hit in askUnderlineHits where hit.threadID == threadID {
                guard let page = document.page(at: hit.pageIndex) else { continue }
                let annotation = PDFAnnotation(bounds: hit.hitBounds, forType: .highlight, withProperties: nil)
                annotation.color = fill
                annotation.userName = askUnderlineHoverMarker
                page.addAnnotation(annotation)
            }
        }

        private func clearAskUnderlineAnnotations(
            in document: PDFDocument,
            includingHover: Bool,
            underlines: Bool = true
        ) {
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                for annotation in page.annotations {
                    let name = annotation.userName
                    if underlines, name == askUnderlineMarker {
                        page.removeAnnotation(annotation)
                    } else if includingHover, name == askUnderlineHoverMarker {
                        page.removeAnnotation(annotation)
                    }
                }
            }
        }

        private func applyOCRSearch(
            _ query: String,
            targetPageIndex: Int?,
            in view: PDFView
        ) {
            var highlightedLines: [Int: Set<Int>] = [:]
            var firstPageIndex: Int?

            for page in ocrPagesByPageIndex.values
                .filter({ targetPageIndex == nil || $0.pageIndex == targetPageIndex })
                .sorted(by: { $0.pageIndex < $1.pageIndex }) {
                for (lineIndex, line) in page.lines.enumerated() {
                    guard line.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                    highlightedLines[page.pageIndex, default: []].insert(lineIndex)
                    if firstPageIndex == nil {
                        firstPageIndex = page.pageIndex
                    }
                }
            }

            view.clearSelection()
            setOCRHighlightedLines(highlightedLines, in: view)

            if let firstPageIndex,
               let page = view.document?.page(at: firstPageIndex) {
                view.go(to: page)
            }
        }

        private func setOCRHighlightedLines(_ highlightedLines: [Int: Set<Int>], in view: PDFView) {
            guard ocrHighlightedLinesByPageIndex != highlightedLines else { return }
            ocrHighlightedLinesByPageIndex = highlightedLines
            if !ocrPagesByPageIndex.isEmpty {
                view.layoutDocumentView()
            }
        }

        deinit {
            suspend()
        }
    }
}

private final class ReaderPDFView: PDFView {
    var reportCurrentSelection: (() -> Void)?
    var handleAskUnderlineHover: ((CGPoint) -> Void)?
    var handleAskUnderlineClick: ((CGPoint) -> Bool)?
    private var adaptsDocumentColors = true
    private var documentAppearanceMode: WeiBeiAppearanceMode = .paper
    private var trackingArea: NSTrackingArea?

    func configureDocumentColorAdaptation(enabled: Bool, appearanceMode: WeiBeiAppearanceMode) {
        guard adaptsDocumentColors != enabled || documentAppearanceMode != appearanceMode else { return }
        adaptsDocumentColors = enabled
        documentAppearanceMode = appearanceMode
        invalidatePageRendering()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ page: PDFPage, to context: CGContext) {
        guard adaptsDocumentColors else {
            super.draw(page, to: context)
            return
        }

        context.saveGState()
        context.setFillColor(adaptedPaperColor.cgColor)
        context.fill(page.bounds(for: displayBox))
        context.setBlendMode(.multiply)
        page.draw(with: displayBox, to: context)
        context.restoreGState()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        handleAskUnderlineHover?(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if handleAskUnderlineClick?(point) == true {
            return
        }
        super.mouseDown(with: event)
        reportCurrentSelection?()
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        reportCurrentSelection?()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        reportCurrentSelection?()
    }

    private var adaptedPaperColor: NSColor {
        // Per-theme PDF color mask (multiply wash under page pixels).
        WeiBeiNativePalette.documentMaskFill(for: documentAppearanceMode)
    }

    private func invalidatePageRendering() {
        layoutDocumentView()
        Self.markNeedsDisplay(self)
        if let documentView {
            Self.markNeedsDisplay(documentView)
        }
    }

    private static func markNeedsDisplay(_ view: NSView) {
        view.needsDisplay = true
        view.layer?.setNeedsDisplay()
        view.subviews.forEach(markNeedsDisplay)
    }
}

extension PDFReaderRepresentable.Coordinator: PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
        guard let document = view.document else { return nil }
        let index = document.index(for: page)
        guard index != NSNotFound, let ocrPage = ocrPagesByPageIndex[index] else { return nil }
        return PDFOCRPageOverlayView(
            page: ocrPage,
            highlightedLineIndexes: ocrHighlightedLinesByPageIndex[index] ?? [],
            appearanceMode: appearanceMode
        ) { [weak self] text, anchor in
            guard let self else { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.selectionWork?.cancel()
                self.onSelectionChange("", nil, index)
                return
            }
            self.reportSelectionAfterDragSettles(text: text, anchor: anchor, pageIndex: index)
        }
    }
}

private final class PDFOCRPageOverlayView: NSView {
    private let page: PDFOCRPage
    private let highlightedLineIndexes: Set<Int>
    private let appearanceMode: WeiBeiAppearanceMode
    private let onSelectionChange: (String, CGPoint?) -> Void
    private var lineViews: [PDFOCRLineTextView] = []

    init(page: PDFOCRPage, highlightedLineIndexes: Set<Int>, appearanceMode: WeiBeiAppearanceMode, onSelectionChange: @escaping (String, CGPoint?) -> Void) {
        self.page = page
        self.highlightedLineIndexes = highlightedLineIndexes
        self.appearanceMode = appearanceMode
        self.onSelectionChange = onSelectionChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        installLineViews()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        for lineView in lineViews {
            let box = lineView.normalizedBoundingBox
            var frame = CGRect(
                x: box.minX * width,
                y: box.minY * height,
                width: max(box.width * width, 24),
                height: max(box.height * height, 12)
            )
            frame = frame.insetBy(dx: -1.5, dy: -1)
            lineView.frame = frame
            lineView.font = NSFont.systemFont(ofSize: max(8, min(22, frame.height * 0.72)))
        }
    }

    private func installLineViews() {
        lineViews = page.lines.enumerated().map { lineIndex, line in
            let view = PDFOCRLineTextView(
                text: line.text,
                normalizedBoundingBox: line.boundingBox,
                isSearchHighlighted: highlightedLineIndexes.contains(lineIndex),
                appearanceMode: appearanceMode,
                onSelectionChange: onSelectionChange
            )
            addSubview(view)
            return view
        }
    }
}

private final class PDFOCRLineTextView: ReaderSelectableTextView, NSTextViewDelegate {
    let normalizedBoundingBox: CGRect
    private let selectionCallback: (String, CGPoint?) -> Void

    init(
        text: String,
        normalizedBoundingBox: CGRect,
        isSearchHighlighted: Bool,
        appearanceMode: WeiBeiAppearanceMode,
        onSelectionChange: @escaping (String, CGPoint?) -> Void
    ) {
        self.normalizedBoundingBox = normalizedBoundingBox
        self.selectionCallback = onSelectionChange
        super.init(frame: .zero)
        string = text
        isEditable = false
        isSelectable = true
        drawsBackground = isSearchHighlighted
        backgroundColor = isSearchHighlighted ? WeiBeiNativePalette.selectionFill(for: appearanceMode).withAlphaComponent(0.28) : .clear
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.masksToBounds = true
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textColor = .clear
        insertionPointColor = WeiBeiNativePalette.selectionFill(for: appearanceMode)
        selectedTextAttributes = [
            .foregroundColor: NSColor.clear,
            .backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode)
        ]
        delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let range = selectedRange()
        guard range.length > 0, let textRange = Range(range, in: string) else {
            selectionCallback("", nil)
            return
        }
        selectionCallback(String(string[textRange]), Self.anchor(for: range, in: self))
    }

    private static func anchor(for range: NSRange, in textView: NSTextView) -> CGPoint? {
        guard let window = textView.window else { return nil }
        let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
        guard !rect.isEmpty else { return nil }
        let screenPoint = CGPoint(x: rect.midX, y: rect.minY)
        return SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)
    }
}

private final class WebReaderResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "weibeihtml"

    private let lock = NSLock()
    private var scopeID = ""
    private var rootDirectory: URL?
    private var activeRequests: Set<ObjectIdentifier> = []

    func activate(rootDirectory: URL) -> URL? {
        let scopeID = UUID().uuidString.lowercased()
        guard let root = try? CourseProjectPathPolicy.existingDirectory(rootDirectory),
              let baseURL = URL(string: "\(Self.scheme)://\(scopeID)/") else {
            deactivate()
            return nil
        }
        lock.lock()
        self.scopeID = scopeID
        self.rootDirectory = root
        activeRequests.removeAll()
        lock.unlock()
        return baseURL
    }

    func deactivate() {
        lock.lock()
        scopeID = ""
        rootDirectory = nil
        activeRequests.removeAll()
        lock.unlock()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        guard let requestURL = urlSchemeTask.request.url,
              let requestScope = requestURL.host?.lowercased(),
              let root = beginRequest(key, scopeID: requestScope) else {
            urlSchemeTask.didFailWithError(Self.unreadableResourceError)
            return
        }
        guard let fileURL = fileURL(for: requestURL, within: root) else {
            cancelRequest(key)
            urlSchemeTask.didFailWithError(Self.unreadableResourceError)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<(Data, URLResponse), Error>
            do {
                let data = try CourseProjectFileWorker.readBoundedRegularFile(
                    at: fileURL,
                    inside: root,
                    maximumByteCount: CourseProjectFileWorker.markdownMaximumByteCount
                )
                let response = URLResponse(
                    url: requestURL,
                    mimeType: Self.mimeType(for: fileURL),
                    expectedContentLength: data.count,
                    textEncodingName: Self.textEncodingName(for: fileURL)
                )
                result = .success((data, response))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                guard self?.finishRequest(key, scopeID: requestScope) == true else { return }
                switch result {
                case let .success((data, response)):
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                case let .failure(error):
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask as AnyObject)
        cancelRequest(key)
    }

    private func cancelRequest(_ key: ObjectIdentifier) {
        lock.lock()
        activeRequests.remove(key)
        lock.unlock()
    }

    private func beginRequest(_ key: ObjectIdentifier, scopeID requestScope: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard requestScope == scopeID, let rootDirectory else { return nil }
        activeRequests.insert(key)
        return rootDirectory
    }

    private func finishRequest(_ key: ObjectIdentifier, scopeID requestScope: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard requestScope == scopeID, activeRequests.remove(key) != nil else { return false }
        return true
    }

    private func fileURL(for requestURL: URL, within root: URL) -> URL? {
        let components = requestURL.path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, !components.contains(where: { $0 == "." || $0 == ".." }) else {
            return nil
        }
        let candidate = components.reduce(root) { url, component in
            url.appendingPathComponent(String(component))
        }
        guard CourseProjectPathPolicy.contains(root, candidate, includingRoot: false) else { return nil }
        return candidate.standardizedFileURL
    }

    private static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    private static func textEncodingName(for url: URL) -> String? {
        ["css", "htm", "html", "js", "json", "mjs", "svg", "xml"].contains(url.pathExtension.lowercased())
            ? "utf-8"
            : nil
    }

    private static let unreadableResourceError = NSError(
        domain: "WeiBei.WebReaderResource",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "HTML resource is outside the active document directory."]
    )
}

struct WebReaderRepresentable: NSViewRepresentable {
    var html: String?
    var url: URL?
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var adaptsDocumentColors: Bool
    var contentRailTarget: WebReaderContentRailTarget?
    /// JSON array of `{id,text}` for selection-ask underline marks.
    var selectionAskMarks: String = "[]"
    var onContentRailChange: ([WebReaderContentRailSection]) -> Void
    var onContentRailActiveChange: (WebReaderContentRailActiveChange) -> Void
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
    var onSelectionChange: (String, CGPoint?) -> Void
    var onSelectionAskMark: (String) -> Void = { _ in }

    private static let scriptMessageNames = [
        "selection",
        "selectionAskMark",
        "appShortcut",
        "contentRailSections",
        "contentRailActive"
    ]

    init(
        html: String,
        searchQuery: String = "",
        appearanceMode: WeiBeiAppearanceMode = .paper,
        adaptsDocumentColors: Bool = true,
        contentRailTarget: WebReaderContentRailTarget? = nil,
        selectionAskMarks: String = "[]",
        onContentRailChange: @escaping ([WebReaderContentRailSection]) -> Void = { _ in },
        onContentRailActiveChange: @escaping (WebReaderContentRailActiveChange) -> Void = { _ in },
        onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false },
        onSelectionAskMark: @escaping (String) -> Void = { _ in },
        onSelectionChange: @escaping (String, CGPoint?) -> Void
    ) {
        self.html = html
        self.url = nil
        self.searchQuery = searchQuery
        self.appearanceMode = appearanceMode
        self.adaptsDocumentColors = adaptsDocumentColors
        self.contentRailTarget = contentRailTarget
        self.selectionAskMarks = selectionAskMarks
        self.onContentRailChange = onContentRailChange
        self.onContentRailActiveChange = onContentRailActiveChange
        self.onAppShortcut = onAppShortcut
        self.onSelectionAskMark = onSelectionAskMark
        self.onSelectionChange = onSelectionChange
    }

    init(
        url: URL,
        searchQuery: String = "",
        appearanceMode: WeiBeiAppearanceMode = .paper,
        adaptsDocumentColors: Bool = true,
        contentRailTarget: WebReaderContentRailTarget? = nil,
        selectionAskMarks: String = "[]",
        onContentRailChange: @escaping ([WebReaderContentRailSection]) -> Void = { _ in },
        onContentRailActiveChange: @escaping (WebReaderContentRailActiveChange) -> Void = { _ in },
        onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false },
        onSelectionAskMark: @escaping (String) -> Void = { _ in },
        onSelectionChange: @escaping (String, CGPoint?) -> Void
    ) {
        self.html = nil
        self.url = url
        self.searchQuery = searchQuery
        self.appearanceMode = appearanceMode
        self.adaptsDocumentColors = adaptsDocumentColors
        self.contentRailTarget = contentRailTarget
        self.selectionAskMarks = selectionAskMarks
        self.onContentRailChange = onContentRailChange
        self.onContentRailActiveChange = onContentRailActiveChange
        self.onAppShortcut = onAppShortcut
        self.onSelectionAskMark = onSelectionAskMark
        self.onSelectionChange = onSelectionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            appearanceMode: appearanceMode,
            adaptsDocumentColors: adaptsDocumentColors,
            contentRailTarget: contentRailTarget,
            onContentRailChange: onContentRailChange,
            onContentRailActiveChange: onContentRailActiveChange,
            onAppShortcut: onAppShortcut,
            onSelectionChange: onSelectionChange,
            onSelectionAskMark: onSelectionAskMark
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        for name in Self.scriptMessageNames {
            controller.add(context.coordinator, name: name)
        }
        controller.addUserScript(WKUserScript(
            source: Self.appShortcutScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.selectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: Self.readerStyleScript(for: appearanceMode, adaptsDocumentColors: adaptsDocumentColors),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.contentRailScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller
        configuration.setURLSchemeHandler(
            context.coordinator.htmlResourceSchemeHandler,
            forURLScheme: WebReaderResourceSchemeHandler.scheme
        )

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        view.navigationDelegate = context.coordinator
        return view
    }

    /// Accept the SwiftUI proposal instead of measuring WKWebView via Auto Layout.
    /// Hang report 2026-08-01: systemLayoutSizeFittingSize on the HTML reader blocked
    /// the main thread for ~30s after global chat published WorkspaceStore updates.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WKWebView,
        context: Context
    ) -> CGSize? {
        ReaderPlatformViewSizing.proposedReaderSize(proposal, fallback: nsView.bounds.size)
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.searchQuery = searchQuery
        context.coordinator.onAppShortcut = onAppShortcut
        context.coordinator.onContentRailChange = onContentRailChange
        context.coordinator.onContentRailActiveChange = onContentRailActiveChange
        context.coordinator.onSelectionAskMark = onSelectionAskMark
        context.coordinator.contentRailTarget = contentRailTarget
        context.coordinator.selectionAskMarks = selectionAskMarks
        if context.coordinator.appearanceMode != appearanceMode
            || context.coordinator.adaptsDocumentColors != adaptsDocumentColors {
            context.coordinator.appearanceMode = appearanceMode
            context.coordinator.adaptsDocumentColors = adaptsDocumentColors
            view.evaluateJavaScript(Self.readerStyleScript(for: appearanceMode, adaptsDocumentColors: adaptsDocumentColors))
        }
        if let url {
            let signature = "file:\(url.path)"
            if context.coordinator.loadedSignature != signature {
                context.coordinator.loadedSignature = signature
                context.coordinator.lastAppliedSelectionAskMarks = ""
                context.coordinator.loadUTF8HTML(at: url, signature: signature, into: view)
            } else {
                context.coordinator.applySearch(in: view)
                context.coordinator.applySelectionAskMarksIfNeeded()
            }
        } else if let html {
            let signature = "html:\(html.hashValue)"
            if context.coordinator.loadedSignature != signature {
                view.stopLoading()
                context.coordinator.cancelHTMLLoad()
                context.coordinator.loadedSignature = signature
                context.coordinator.lastAppliedSelectionAskMarks = ""
                view.loadHTMLString(html, baseURL: nil)
            } else {
                context.coordinator.applySearch(in: view)
                context.coordinator.applySelectionAskMarksIfNeeded()
            }
        }
        context.coordinator.applyContentRailTarget(in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.cancelHTMLLoad()
        unbindScriptMessages(in: view)
        view.navigationDelegate = nil
    }

    private static func unbindScriptMessages(in view: WKWebView) {
        let controller = view.configuration.userContentController
        for name in scriptMessageNames {
            controller.removeScriptMessageHandler(forName: name)
        }
    }

    static let appShortcutScript = """
    (() => {
      const keyName = (event) => {
        if (/^Digit[0-9]$/.test(event.code)) return event.code.slice(5);
        if (/^Key[A-Z]$/.test(event.code)) return event.code.slice(3).toLowerCase();
        return String(event.key || "").toLowerCase();
      };
      const isWeiBeiShortcut = (key, event) => {
        const command = event.metaKey;
        const option = event.altKey;
        const control = event.ctrlKey;
        const shift = event.shiftKey;
        if (command && option && !control && !shift) return ["1", "2", "3", "a", "n", "r", "t"].includes(key);
        if (command && !option && !control && !shift) return ["1", "2", "3", "4", "[", "]", "b", "j", "k", "f"].includes(key);
        if (control && option && !command && !shift) return ["0", "1", "2", "3", "4"].includes(key);
        return false;
      };
      window.addEventListener("keydown", (event) => {
        const key = keyName(event);
        if (!isWeiBeiShortcut(key, event)) return;
        event.preventDefault();
        event.stopPropagation();
        window.webkit.messageHandlers.appShortcut.postMessage({
          key,
          command: event.metaKey,
          option: event.altKey,
          control: event.ctrlKey,
          shift: event.shiftKey
        });
      }, true);
    })();
    """

    static let selectionScript = """
    (() => {
      let frame = 0;
      let lastPayload = { text: "", x: null, y: null };
      // Scroll must not stream selection → WorkspaceStore. Sample 2026-08-01:
      // selectionchange during HTML scroll published selectionAnchor and froze
      // the agent pane in SelectionOverlay / LazyVStack remasure.
      let scrollQuietUntil = 0;
      let scrollQuietTimer = 0;

      function markScrollQuiet() {
        scrollQuietUntil = Date.now() + 220;
        window.clearTimeout(scrollQuietTimer);
        scrollQuietTimer = window.setTimeout(() => {
          scrollQuietUntil = 0;
        }, 240);
      }

      function reportSelection() {
        window.cancelAnimationFrame(frame);
        frame = window.requestAnimationFrame(() => {
          if (window.weiBeiSuppressSelectionReport) return;
          if (Date.now() < scrollQuietUntil) return;
          const selection = window.getSelection();
          const text = selection ? selection.toString().trim() : "";
          const range = selection && selection.rangeCount ? selection.getRangeAt(0) : null;
          const rect = range ? range.getBoundingClientRect() : null;
          const payload = {
            text,
            x: rect && text ? rect.left + rect.width / 2 : null,
            y: rect && text ? rect.bottom : null
          };
          if (
            payload.text === lastPayload.text &&
            payload.x === lastPayload.x &&
            payload.y === lastPayload.y
          ) {
            return;
          }
          lastPayload = payload;
          window.webkit.messageHandlers.selection.postMessage(payload);
        });
      }

      document.addEventListener("selectionchange", reportSelection);
      document.addEventListener("pointerdown", () => {
        if (window.weiBeiSuppressSelectionReport) return;
        window.cancelAnimationFrame(frame);
        lastPayload = { text: "", x: null, y: null };
        window.webkit.messageHandlers.selection.postMessage(lastPayload);
      }, true);
      document.addEventListener("pointerup", reportSelection);
      document.addEventListener("mouseup", reportSelection);
      document.addEventListener("keyup", reportSelection);
      document.addEventListener("touchend", reportSelection);
      window.addEventListener("wheel", markScrollQuiet, { passive: true });
      window.addEventListener("scroll", markScrollQuiet, { passive: true });
      window.addEventListener("touchmove", markScrollQuiet, { passive: true });

      // Underline spans for selection-ask history; click reopens floating Q&A.
      window.WeiBeiSelectionAskMarks = {
        apply: function(marks) {
          try {
            document.querySelectorAll(".weibei-selection-ask-mark").forEach((el) => {
              const parent = el.parentNode;
              if (!parent) return;
              while (el.firstChild) parent.insertBefore(el.firstChild, el);
              parent.removeChild(el);
              parent.normalize();
            });
            const list = Array.isArray(marks) ? marks : [];
            list.forEach((mark) => {
              const needle = String(mark.text || "").trim();
              const id = String(mark.id || "");
              if (!needle || !id || needle.length < 4) return;
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(node) {
                  if (!node.parentElement) return NodeFilter.FILTER_REJECT;
                  if (node.parentElement.closest(".weibei-selection-ask-mark, script, style")) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return node.nodeValue && node.nodeValue.indexOf(needle) >= 0
                    ? NodeFilter.FILTER_ACCEPT
                    : NodeFilter.FILTER_SKIP;
                }
              });
              const hits = [];
              while (walker.nextNode()) hits.push(walker.currentNode);
              hits.slice(0, 3).forEach((textNode) => {
                const value = textNode.nodeValue || "";
                const idx = value.indexOf(needle);
                if (idx < 0) return;
                const range = document.createRange();
                range.setStart(textNode, idx);
                range.setEnd(textNode, idx + needle.length);
                const span = document.createElement("span");
                span.className = "weibei-selection-ask-mark";
                span.dataset.threadId = id;
                span.title = "打开当时的选区问答";
                try {
                  range.surroundContents(span);
                } catch (e) {
                  // ignore partial-node failures
                }
              });
            });
            document.querySelectorAll(".weibei-selection-ask-mark").forEach((el) => {
              el.onclick = function(ev) {
                ev.preventDefault();
                ev.stopPropagation();
                const threadId = el.dataset.threadId || "";
                if (window.webkit?.messageHandlers?.selectionAskMark) {
                  window.webkit.messageHandlers.selectionAskMark.postMessage({
                    threadId,
                    text: el.textContent || ""
                  });
                }
              };
            });
          } catch (e) {}
        }
      };
    })();
    """

    static let contentRailScript = """
    (() => {
      if (window.WeiBeiContentRail?.installed) {
        window.WeiBeiContentRail.scan();
        return;
      }

      const state = {
        items: [],
        activeID: "",
        activeFrame: 0,
        scanTimer: 0,
        pendingScanReason: "initial",
        userScrollUntil: 0
      };
      const clean = (value) => String(value || "").replace(/\\s+/g, " ").trim();
      const clipped = (value, limit) => clean(value).slice(0, limit);
      const visible = (element) => {
        if (!(element instanceof Element)) return false;
        if (element.closest("nav, footer, [aria-hidden='true']")) return false;
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== "none" && style.visibility !== "hidden" && rect.width > 1 && rect.height > 1;
      };
      const absoluteTop = (element) => window.scrollY + element.getBoundingClientRect().top;
      const maximumScroll = () => Math.max(
        1,
        (document.scrollingElement?.scrollHeight || document.documentElement.scrollHeight || document.body.scrollHeight || 1)
          - window.innerHeight
      );
      const normalizedPosition = (element) => Math.max(0, Math.min(1, absoluteTop(element) / maximumScroll()));
      const metadata = (index, count, fallback) => fallback
        ? `HTML · 内容段 ${index + 1} / ${count}`
        : `HTML · ${index + 1} / ${count}`;

      const excerptAfterHeading = (heading) => {
        let cursor = heading.nextElementSibling;
        while (cursor) {
          if (/^H[1-4]$/.test(cursor.tagName) || cursor.getAttribute("role") === "heading") break;
          const candidate = cursor.matches("p, li, blockquote, figcaption, pre")
            ? cursor
            : cursor.querySelector("p, li, blockquote, figcaption, pre");
          const text = clipped(candidate?.textContent, 180);
          if (text) return text;
          cursor = cursor.nextElementSibling;
        }
        return "";
      };

      const sectionFingerprintBody = (heading, nextHeading) => {
        try {
          const range = document.createRange();
          range.setStartAfter(heading);
          if (nextHeading) {
            range.setEndBefore(nextHeading);
          } else if (document.body?.lastChild) {
            range.setEndAfter(document.body.lastChild);
          } else {
            return "";
          }
          const fragment = range.cloneContents();
          fragment.querySelectorAll?.("script, style, noscript, template").forEach((element) => element.remove());
          return clean(fragment.textContent);
        } catch (_) {
          return excerptAfterHeading(heading);
        }
      };

      const sectionLocationID = (title, body) => {
        const normalized = `${title}|${body}`
          .toLocaleLowerCase()
          .match(/[\\p{L}\\p{N}]/gu)?.join("").slice(0, 500) || "";
        const bytes = new TextEncoder().encode(normalized);
        let hash = 0x811c9dc5;
        bytes.forEach((byte) => {
          hash ^= byte;
          hash = Math.imul(hash, 0x01000193) >>> 0;
        });
        return `html-section-${hash.toString(16).padStart(8, "0")}`;
      };

      const headingSections = () => {
        const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4"));
        const locationIDCounts = new Map();
        return headings
        .map((element, index) => {
          const title = clean(element.textContent);
          const baseID = sectionLocationID(title, sectionFingerprintBody(element, headings[index + 1]));
          const count = (locationIDCounts.get(baseID) || 0) + 1;
          locationIDCounts.set(baseID, count);
          const id = count === 1 ? baseID : `${baseID}-dup-${count}`;
          element.dataset.weibeiContentRailID = id;
          return { element, index, id };
        })
        .filter(({ element }) => visible(element) && clean(element.textContent))
        .map(({ element, index, id }) => {
          const explicitLevel = Number(element.getAttribute("aria-level"));
          const tagLevel = /^H[1-4]$/.test(element.tagName) ? Number(element.tagName.slice(1)) : 2;
          const level = Math.max(1, Math.min(4, Number.isFinite(explicitLevel) && explicitLevel > 0 ? explicitLevel : tagLevel));
          return {
            id,
            element,
            level,
            title: clipped(element.textContent, 72),
            excerpt: excerptAfterHeading(element),
            top: absoluteTop(element),
            position: normalizedPosition(element),
            fallback: false
          };
        });
      };

      const fallbackSections = () => {
        const root = document.querySelector("main, article") || document.body;
        const blocks = Array.from(root?.querySelectorAll("p, li, blockquote, figcaption, pre") || [])
          .filter((element) => visible(element) && clean(element.textContent).length >= 24)
          .sort((left, right) => absoluteTop(left) - absoluteTop(right));
        if (blocks.length === 0) return [];
        const desiredCount = Math.max(1, Math.min(24, Math.ceil(maximumScroll() / Math.max(window.innerHeight * 1.35, 640)) + 1));
        const selected = [];
        for (let index = 0; index < desiredCount; index += 1) {
          const blockIndex = desiredCount === 1
            ? 0
            : Math.round((index / (desiredCount - 1)) * (blocks.length - 1));
          const element = blocks[blockIndex];
          if (!element || selected.some((entry) => entry.element === element)) continue;
          const text = clean(element.textContent);
          const id = element.dataset.weibeiContentRailID || `html-block-${blockIndex}`;
          element.dataset.weibeiContentRailID = id;
          selected.push({
            id,
            element,
            level: 4,
            title: clipped(text, 48),
            excerpt: clipped(text, 180),
            top: absoluteTop(element),
            position: normalizedPosition(element),
            fallback: true
          });
        }
        return selected;
      };

      const postSections = () => {
        const count = state.items.length;
        window.webkit?.messageHandlers?.contentRailSections?.postMessage(state.items.map((item, index) => ({
          id: item.id,
          position: item.position,
          level: item.level,
          title: item.title,
          excerpt: item.excerpt,
          metadata: metadata(index, count, item.fallback)
        })));
      };

      const applyActive = (requestedReason = "unknown") => {
        const now = Date.now();
        const reason = requestedReason === "scroll"
          ? (now <= state.userScrollUntil ? "scroll" : "programmatic")
          : requestedReason;
        if (state.items.length === 0) {
          if (state.activeID) {
            state.activeID = "";
            window.webkit?.messageHandlers?.contentRailActive?.postMessage({ id: "", reason });
          }
          return;
        }
        const readingLine = window.scrollY + window.innerHeight * 0.32;
        let active = state.items[0];
        for (const item of state.items) {
          if (item.top <= readingLine) active = item;
          else break;
        }
        if (active.id === state.activeID) return;
        state.activeID = active.id;
        window.webkit?.messageHandlers?.contentRailActive?.postMessage({ id: active.id, reason });
      };

      const updateActive = (requestedReason = "unknown") => {
        window.cancelAnimationFrame(state.activeFrame);
        state.activeFrame = window.requestAnimationFrame(() => applyActive(requestedReason));
      };

      const scan = (reason = "unknown") => {
        const headings = headingSections();
        state.items = (headings.length > 0 ? headings : fallbackSections())
          .sort((left, right) => left.top - right.top);
        postSections();
        updateActive(reason);
      };

      const scheduleScan = (reason) => {
        state.pendingScanReason = reason;
        window.clearTimeout(state.scanTimer);
        state.scanTimer = window.setTimeout(() => scan(state.pendingScanReason), 160);
      };

      const scrollTo = (id) => {
        const item = state.items.find((candidate) => candidate.id === id);
        if (!item?.element) return false;
        item.element.scrollIntoView({ behavior: "smooth", block: "start", inline: "nearest" });
        window.setTimeout(() => window.scrollBy({ top: -44, behavior: "auto" }), 180);
        window.setTimeout(() => {
          state.activeID = id;
          window.webkit?.messageHandlers?.contentRailActive?.postMessage({ id, reason: "jump" });
        }, 240);
        return true;
      };

      const markUserScrollIntent = () => {
        state.userScrollUntil = Date.now() + 900;
      };

      const markKeyboardScrollIntent = (event) => {
        const keys = ["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " "];
        if (keys.includes(event.key)) markUserScrollIntent();
      };

      window.WeiBeiContentRail = {
        installed: true,
        scan: () => scan("initial"),
        scrollTo
      };
      window.addEventListener("wheel", markUserScrollIntent, { passive: true });
      window.addEventListener("touchmove", markUserScrollIntent, { passive: true });
      window.addEventListener("keydown", markKeyboardScrollIntent, { passive: true });
      window.addEventListener("scroll", () => updateActive("scroll"), { passive: true });
      window.addEventListener("resize", () => scheduleScan("resize"), { passive: true });
      new MutationObserver(() => scheduleScan("mutation")).observe(document.body || document.documentElement, {
        childList: true,
        characterData: true,
        subtree: true
      });
      if (window.ResizeObserver) {
        new ResizeObserver(() => scheduleScan("resize")).observe(document.body || document.documentElement);
      }
      window.requestAnimationFrame(() => scan("initial"));
    })();
    """

    static func readerStyleScript(for mode: WeiBeiAppearanceMode, adaptsDocumentColors: Bool = true) -> String {
        let tokens = WeiBeiNativePalette.cssHex(for: mode)
        let scheme = mode.isDark ? "dark" : "light"
        let selectionCSS = """
            ::selection { background: \(tokens.selection); color: \(tokens.ink); }
            .weibei-selection-ask-mark {
              text-decoration-line: underline;
              text-decoration-color: \(tokens.cinnabar);
              text-decoration-thickness: 1.5px;
              text-underline-offset: 3px;
              cursor: pointer;
              background: color-mix(in srgb, \(tokens.cinnabar) 12%, transparent);
              border-radius: 2px;
            }
            .weibei-selection-ask-mark:hover {
              background: color-mix(in srgb, \(tokens.cinnabar) 20%, transparent);
            }
            """

        let adaptiveCSS: String
        if !adaptsDocumentColors {
            adaptiveCSS = ""
        } else if mode.isDark {
            adaptiveCSS = """
            html, body { max-width: 100%; overflow-x: hidden; color-scheme: \(scheme); background: transparent !important; }
            body, main, article, section, div, p, li, blockquote, td, th, span { color: \(tokens.ink) !important; background-color: transparent !important; }
            a { color: \(tokens.link) !important; text-decoration-color: color-mix(in srgb, \(tokens.link) 55%, transparent) !important; }
            h1, h2, h3 { color: \(tokens.link) !important; }
            blockquote { border-left: 3px solid color-mix(in srgb, \(tokens.cinnabar) 62%, transparent) !important; background: color-mix(in srgb, \(tokens.cinnabar) 10%, transparent) !important; color: \(tokens.ink) !important; }
            code { background: rgba(255, 255, 255, .05) !important; color: \(tokens.link) !important; }
            pre { background: \(tokens.paperRaised) !important; border: 1px solid color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; color: \(tokens.ink) !important; }
            table { background: rgba(255, 255, 255, .02) !important; }
            th { color: \(tokens.link) !important; background: color-mix(in srgb, \(tokens.link) 10%, transparent) !important; }
            table, th, td { border-color: color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; }
            """
        } else {
            adaptiveCSS = """
            html, body { max-width: 100%; overflow-x: hidden; color-scheme: \(scheme); background: transparent !important; }
            body, main, article, section, div, p, li, blockquote, td, th, span { color: \(tokens.ink) !important; }
            [data-weibei-paper-surface] { background-color: transparent !important; }
            a { color: \(tokens.link) !important; }
            code { background: color-mix(in srgb, \(tokens.ink) 6%, transparent) !important; color: \(tokens.muted) !important; }
            pre { background: color-mix(in srgb, \(tokens.ink) 5%, transparent) !important; border-color: color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; }
            table, th, td { border-color: color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; }
            """
        }

        let css = selectionCSS + "\n" + adaptiveCSS
        return """
        (() => {
          const css = \(Self.json(css));
          const adaptsDocumentColors = \(adaptsDocumentColors ? "true" : "false");
          const appearance = \(Self.json(mode.webThemeName));
          let style = document.getElementById("weibei-reader-style");
          if (!style) {
            style = document.createElement("style");
            style.id = "weibei-reader-style";
            document.head.appendChild(style);
          }
          document.documentElement.dataset.weibeiTheme = adaptsDocumentColors ? appearance : "original";
          style.textContent = `${css}
            body, main, article, section, div { box-sizing: border-box; max-width: 100%; }
            h1, h2, h3, h4, p, li, blockquote { overflow-wrap: anywhere; word-break: normal; }
            pre, code { white-space: pre-wrap; overflow-wrap: anywhere; }
            img, table { max-width: 100%; }
          `;

          document.querySelectorAll("[data-weibei-paper-surface]").forEach((element) => {
            element.removeAttribute("data-weibei-paper-surface");
          });
          if (adaptsDocumentColors && appearance === "paper") {
            const candidates = Array.from(document.querySelectorAll(
              "main, article, section, div, aside, header, footer, table, thead, tbody, tr, td, th"
            )).slice(0, 2500);
            candidates.forEach((element) => {
              const values = (getComputedStyle(element).backgroundColor.match(/[\\d.]+/g) || []).map(Number);
              if (values.length < 3) return;
              const rgb = values.slice(0, 3);
              if (Math.max(...rgb) <= 1.01) {
                rgb[0] *= 255;
                rgb[1] *= 255;
                rgb[2] *= 255;
              }
              const alpha = values.length > 3 ? values[3] : 1;
              const minimum = Math.min(...rgb);
              const spread = Math.max(...rgb) - minimum;
              if (alpha > 0.05 && minimum >= 238 && spread <= 18) {
                element.setAttribute("data-weibei-paper-surface", "");
              }
            });
          }
        })();
        """
    }

    private static func json(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onSelectionChange: (String, CGPoint?) -> Void
        var onSelectionAskMark: (String) -> Void
        var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
        var onContentRailChange: ([WebReaderContentRailSection]) -> Void
        var onContentRailActiveChange: (WebReaderContentRailActiveChange) -> Void
        var contentRailTarget: WebReaderContentRailTarget?
        var loadedSignature: String?
        var searchQuery = ""
        var appearanceMode: WeiBeiAppearanceMode = .paper
        var adaptsDocumentColors = true
        var selectionAskMarks = "[]"
        var htmlReadTask: Task<Data?, Never>?
        var htmlLoadTask: Task<Void, Never>?
        var htmlLoadRequestID: UUID?
        fileprivate let htmlResourceSchemeHandler = WebReaderResourceSchemeHandler()
        private var lastAppliedSearchQuery = ""
        var lastAppliedSelectionAskMarks = ""
        private var lastAppliedContentRailTargetRequestID: UUID?
        weak var webView: WKWebView?

        init(
            appearanceMode: WeiBeiAppearanceMode,
            adaptsDocumentColors: Bool,
            contentRailTarget: WebReaderContentRailTarget?,
            onContentRailChange: @escaping ([WebReaderContentRailSection]) -> Void,
            onContentRailActiveChange: @escaping (WebReaderContentRailActiveChange) -> Void,
            onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool,
            onSelectionChange: @escaping (String, CGPoint?) -> Void,
            onSelectionAskMark: @escaping (String) -> Void
        ) {
            self.appearanceMode = appearanceMode
            self.adaptsDocumentColors = adaptsDocumentColors
            self.contentRailTarget = contentRailTarget
            self.onContentRailChange = onContentRailChange
            self.onContentRailActiveChange = onContentRailActiveChange
            self.onAppShortcut = onAppShortcut
            self.onSelectionChange = onSelectionChange
            self.onSelectionAskMark = onSelectionAskMark
        }

        @MainActor
        func loadUTF8HTML(at url: URL, signature: String, into view: WKWebView) {
            view.stopLoading()
            cancelHTMLLoad()
            let requestID = UUID()
            htmlLoadRequestID = requestID
            let readTask = Task.detached(priority: .userInitiated) { () -> Data? in
                guard !Task.isCancelled else { return nil }
                guard let data = try? CourseProjectFileWorker
                    .readBoundedRegularFile(
                        at: url,
                        maximumByteCount: CourseProjectFileWorker
                            .markdownMaximumByteCount
                    ) else { return nil }
                return Task.isCancelled ? nil : data
            }
            htmlReadTask = readTask
            htmlLoadTask = Task { @MainActor [weak self, weak view] in
                let data = await readTask.value
                guard !Task.isCancelled,
                      let self,
                      let view,
                      webView === view,
                      htmlLoadRequestID == requestID,
                      loadedSignature == signature else { return }
                defer {
                    if htmlLoadRequestID == requestID {
                        htmlReadTask = nil
                        htmlLoadTask = nil
                        htmlLoadRequestID = nil
                    }
                }
                guard let data,
                      let baseURL = htmlResourceSchemeHandler.activate(
                        rootDirectory: url.deletingLastPathComponent()
                      ) else {
                    view.loadHTMLString(
                        "<p style=\"font: 15px -apple-system; padding: 24px\">无法安全读取这个 HTML 文件。请确认文件没有损坏且大小未超过限制。</p>",
                        baseURL: nil
                    )
                    return
                }
                view.load(
                    data,
                    mimeType: "text/html",
                    characterEncodingName: "utf-8",
                    baseURL: baseURL
                )
            }
        }

        func cancelHTMLLoad() {
            htmlReadTask?.cancel()
            htmlLoadTask?.cancel()
            htmlReadTask = nil
            htmlLoadTask = nil
            htmlLoadRequestID = nil
            htmlResourceSchemeHandler.deactivate()
        }

        func applySelectionAskMarksIfNeeded() {
            guard let webView, selectionAskMarks != lastAppliedSelectionAskMarks else { return }
            lastAppliedSelectionAskMarks = selectionAskMarks
            let js = "window.WeiBeiSelectionAskMarks && window.WeiBeiSelectionAskMarks.apply(\(selectionAskMarks));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "appShortcut" {
                guard let body = message.body as? [String: Any],
                      let key = body["key"] as? String else { return }
                _ = onAppShortcut(key, Self.modifiers(from: body))
                return
            }

            if message.name == "selectionAskMark" {
                let threadID: String
                if let body = message.body as? [String: Any] {
                    threadID = (body["threadId"] as? String) ?? ""
                } else if let body = message.body as? String {
                    threadID = body
                } else {
                    return
                }
                Task { @MainActor in
                    self.onSelectionAskMark(threadID)
                }
                return
            }

            if message.name == "contentRailSections" {
                guard let rows = message.body as? [[String: Any]] else { return }
                let sections = rows.compactMap(Self.contentRailSection(from:))
                Task { @MainActor in
                    self.onContentRailChange(sections)
                }
                return
            }

            if message.name == "contentRailActive" {
                let body = message.body as? [String: Any]
                let id = body?["id"] as? String
                let reason = (body?["reason"] as? String)
                    .flatMap(WebReaderContentRailEventReason.init(rawValue:)) ?? .unknown
                Task { @MainActor in
                    self.onContentRailActiveChange(
                        WebReaderContentRailActiveChange(
                            id: id?.isEmpty == false ? id : nil,
                            reason: reason
                        )
                    )
                }
                return
            }

            let text: String
            let anchor: CGPoint?
            if let body = message.body as? [String: Any],
               let bodyText = body["text"] as? String {
                text = bodyText
                anchor = Self.anchor(from: body, in: webView)
            } else if let bodyText = message.body as? String {
                text = bodyText
                anchor = nil
            } else {
                return
            }
            Task { @MainActor in
                self.onSelectionChange(text, anchor)
            }
        }

        private static func modifiers(from body: [String: Any]) -> NSEvent.ModifierFlags {
            var modifiers: NSEvent.ModifierFlags = []
            if body["command"] as? Bool == true {
                modifiers.insert(.command)
            }
            if body["option"] as? Bool == true {
                modifiers.insert(.option)
            }
            if body["control"] as? Bool == true {
                modifiers.insert(.control)
            }
            if body["shift"] as? Bool == true {
                modifiers.insert(.shift)
            }
            return modifiers
        }

        private static func contentRailSection(from body: [String: Any]) -> WebReaderContentRailSection? {
            guard let id = body["id"] as? String,
                  let title = body["title"] as? String,
                  let position = (body["position"] as? NSNumber)?.doubleValue,
                  let level = (body["level"] as? NSNumber)?.intValue else { return nil }
            return WebReaderContentRailSection(
                id: id,
                position: CGFloat(position),
                level: level,
                title: title,
                excerpt: body["excerpt"] as? String ?? "",
                metadata: body["metadata"] as? String ?? "HTML"
            )
        }

        private static func anchor(from body: [String: Any], in view: WKWebView?) -> CGPoint? {
            guard let view,
                  let x = body["x"] as? Double,
                  let y = body["y"] as? Double else {
                return nil
            }
            return SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastAppliedSearchQuery = ""
            lastAppliedContentRailTargetRequestID = nil
            lastAppliedSelectionAskMarks = ""
            webView.evaluateJavaScript(WebReaderRepresentable.readerStyleScript(for: appearanceMode, adaptsDocumentColors: adaptsDocumentColors))
            applySearch(in: webView)
            applyContentRailTarget(in: webView)
            applySelectionAskMarksIfNeeded()
        }

        func applySearch(in view: WKWebView) {
            let query = ReaderSearch.cleaned(searchQuery)
            guard query != lastAppliedSearchQuery else { return }
            lastAppliedSearchQuery = query
            let script = """
            (() => {
              const query = \(Self.json(query));
              const selection = window.getSelection();
              selection?.removeAllRanges();
              window.webkit?.messageHandlers?.selection?.postMessage({
                text: "",
                x: null,
                y: null
              });
              if (!query) return false;
              window.weiBeiSuppressSelectionReport = true;
              const found = window.find(query, false, false, true, false, true, false);
              window.setTimeout(() => { window.weiBeiSuppressSelectionReport = false; }, 80);
              return found;
            })();
            """
            view.evaluateJavaScript(script)
        }

        func applyContentRailTarget(in view: WKWebView) {
            guard let contentRailTarget,
                  contentRailTarget.requestID != lastAppliedContentRailTargetRequestID else { return }
            lastAppliedContentRailTargetRequestID = contentRailTarget.requestID
            view.evaluateJavaScript("window.WeiBeiContentRail?.scrollTo(\(Self.json(contentRailTarget.id)))")
        }

        private static func json(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
    }
}

private struct MarkdownDocumentReaderView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var markdown: String
    var markdownBaseURL: URL?
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var selectionAskMarks: String = "[]"
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onSelectionAskMark: (String) -> Void = { _ in }
    var onSelectionChange: (String, CGPoint?) -> Void
    @State private var command: NoteEditorCommand?

    var body: some View {
        RichMarkdownEditorView(
            markdown: .constant(markdown),
            command: $command,
            isEditable: false,
            markdownBaseURL: markdownBaseURL,
            searchQuery: searchQuery,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onSelectionChange,
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut,
            onSearchResult: { _, _ in },
            selectionAskMarks: selectionAskMarks,
            onSelectionAskMark: onSelectionAskMark
        )
    }
}

private struct MarkdownReadFailureView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var fileName: String

    var body: some View {
        ReaderStateMessage(
            title: store.ui("无法读取 Markdown", "Could not read Markdown"),
            detail: fileName,
            systemImage: "exclamationmark.triangle"
        )
    }
}

private struct MaterialReadFailureView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var fileName: String

    var body: some View {
        ReaderStateMessage(
            title: store.ui("无法读取资料", "Could not read material"),
            detail: fileName,
            systemImage: "exclamationmark.triangle"
        )
    }
}

private struct EmptyReaderView: View {
    var body: some View {
        ContextualContentPicker(kind: .material)
    }
}

private struct NotebookSelectedReaderView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        ReaderStateMessage(
            title: store.ui("当前是笔记", "This is a note"),
            detail: store.ui("阅读区只显示资料，右侧继续写作当前笔记。", "The reader shows materials only. Continue writing this note on the side."),
            systemImage: "square.and.pencil"
        )
    }
}

private struct ReaderStateMessage: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.62))
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(WeiBeiTheme.ink)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }
}

struct ContextualContentPicker: View {
    @EnvironmentObject private var store: WorkspaceStore
    let kind: ContextualContentKind
    @State private var level: Level = .root
    @State private var showsAll = false

    private enum Level: Hashable {
        case root
        case course(UUID)
        case common
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 13) {
                    if level != .root {
                        backButton
                    }
                    Text(title)
                        .font(.system(size: 19, weight: .semibold, design: .serif))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 3)

                    if rows.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 12))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .frame(height: 54)
                    } else {
                        ForEach(rows) { row in
                            rowButton(row)
                        }
                    }

                    if !showsAll, level == .root,
                       !store.contextualPreferredItems(kind).isEmpty {
                        Button(allTitle) {
                            showsAll = true
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .padding(.top, 3)
                    }
                }
                .frame(maxWidth: min(420, max(240, geometry.size.width - 48)))
                .padding(.horizontal, 24)
                .padding(.top, topPadding(in: geometry.size.height))
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
        }
        .background(WeiBeiTheme.paper)
        .accessibilityIdentifier(
            kind == .note
                ? "contextual-note-picker"
                : "contextual-material-picker"
        )
    }

    private var title: String {
        switch level {
        case .root:
            if !showsAll, hasPreferredContext {
                return kind == .note
                    ? store.ui("相关笔记", "Related Notes")
                    : store.ui("相关资料", "Related Materials")
            }
            return kind == .note
                ? store.ui("选择笔记", "Choose Note")
                : store.ui("选择资料", "Choose Material")
        case .course(let courseID):
            return store.course(withID: courseID)?.title ?? ""
        case .common:
            return kind == .note
                ? store.ui("通用笔记", "Common Notes")
                : store.ui("通用资料", "Common Materials")
        }
    }

    private var allTitle: String {
        kind == .note
            ? store.ui("查看全部笔记", "View All Notes")
            : store.ui("查看全部资料", "View All Materials")
    }

    private var emptyText: String {
        kind == .note
            ? store.ui("这里还没有笔记", "No notes here yet")
            : store.ui("这里还没有资料", "No materials here yet")
    }

    private var rows: [PickerRow] {
        if level == .root, !showsAll {
            let preferred = store.contextualPreferredItems(kind)
            if !preferred.isEmpty {
                return preferred.map(PickerRow.item)
            }
            let courses = store.contextualPreferredCourses(kind)
            if !courses.isEmpty {
                return courses.map {
                    PickerRow.course(
                        $0,
                        store.contextualBrowserItems(kind, courseID: $0.id).count
                    )
                }
            }
        }
        switch level {
        case .root:
            var result = store.contextualBrowserCourses(kind).map {
                PickerRow.course(
                    $0,
                    store.contextualBrowserItems(
                        kind,
                        courseID: $0.id
                    ).count
                )
            }
            let common = store.contextualBrowserItems(kind, courseID: nil)
            if !common.isEmpty {
                result.append(.common(common.count))
            }
            return result
        case .course(let courseID):
            return store.contextualBrowserItems(
                kind,
                courseID: courseID
            ).map(PickerRow.item)
        case .common:
            return store.contextualBrowserItems(
                kind,
                courseID: nil
            ).map(PickerRow.item)
        }
    }

    private var hasPreferredContext: Bool {
        !store.contextualPreferredItems(kind).isEmpty
            || !store.contextualPreferredCourses(kind).isEmpty
    }

    private func topPadding(in height: CGFloat) -> CGFloat {
        rows.count <= 6
            ? max(36, (height - CGFloat(rows.count + 1) * 67) / 2 - 34)
            : 36
    }

    private var backButton: some View {
        Button {
            level = .root
            showsAll = true
        } label: {
            Label(store.ui("全部", "All"), systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowButton(_ row: PickerRow) -> some View {
        Button {
            switch row {
            case .course(let course, _):
                level = .course(course.id)
            case .common:
                level = .common
            case .item(let item):
                store.openContextualItem(item.id, kind: kind)
            }
        } label: {
            HStack(spacing: 12) {
                rowIcon(row)
                    .frame(width: 18)
                Text(row.title(store: store, kind: kind))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let count = row.count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
                Image(systemName: row.isContainer ? "chevron.right" : "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.72))
            }
            .padding(.horizontal, 17)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(WeiBeiTheme.paperRaised.opacity(0.58))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(WeiBeiTheme.hairline.opacity(0.62), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if case .item(let item) = row {
                if case .course(let courseID) = level {
                    Button(store.ui(
                        "从本课程移除",
                        "Remove from This Course"
                    )) {
                        store.removeItem(
                            item.id,
                            fromCourseID: courseID
                        )
                    }
                    Divider()
                }
                Button(store.ui(
                    "将原文件移到废纸篓…",
                    "Move Source File to Trash…"
                )) {
                    store.confirmMoveItemSourceToTrash(item.id)
                }
            }
        }
    }

    @ViewBuilder
    private func rowIcon(_ row: PickerRow) -> some View {
        switch row {
        case .course(let course, _):
            Circle()
                .fill(courseWorkspaceAccent(colorIndex: course.colorIndex))
                .frame(width: 11, height: 11)
        case .common:
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
        case .item(let item):
            Image(systemName: item.isNotebookNote ? "note.text" : "doc.text")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }

    private enum PickerRow: Identifiable {
        case course(Course, Int)
        case common(Int)
        case item(StudyItem)

        var id: String {
            switch self {
            case .course(let course, _): "course:\(course.id)"
            case .common: "common"
            case .item(let item): "item:\(item.id)"
            }
        }

        var count: Int? {
            switch self {
            case .course(_, let count), .common(let count): count
            case .item: nil
            }
        }

        var isContainer: Bool {
            switch self {
            case .course, .common: true
            case .item: false
            }
        }

        @MainActor
        func title(
            store: WorkspaceStore,
            kind: ContextualContentKind
        ) -> String {
            switch self {
            case .course(let course, _): course.title
            case .common:
                kind == .note
                    ? store.ui("通用笔记", "Common Notes")
                    : store.ui("通用资料", "Common Materials")
            case .item(let item): store.displayTitle(for: item)
            }
        }
    }
}

struct ContextualContentListButton: View {
    @EnvironmentObject private var store: WorkspaceStore
    let kind: ContextualContentKind

    var body: some View {
        Button {
            store.showContextualBrowser(kind)
        } label: {
            Image(systemName: "list.bullet")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityIdentifier(
            kind == .note
                ? "contextual-note-list-button"
                : "contextual-material-list-button"
        )
        .help(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        kind == .note
            ? store.ui("选择其他笔记", "Choose another note")
            : store.ui("选择其他资料", "Choose another material")
    }
}

private struct PlainTextReaderView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var text: String
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var onSelectionChange: (String, CGPoint?) -> Void

    var body: some View {
        SelectablePlainTextReader(
            text: text,
            searchQuery: searchQuery,
            appearanceMode: appearanceMode,
            underlineSnippets: store.selectionAskThreads.map(\.selectionText),
            onSelectionChange: onSelectionChange
        )
            .padding(32)
    }
}

private struct SelectablePlainTextReader: NSViewRepresentable {
    var text: String
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var underlineSnippets: [String]
    var onSelectionChange: (String, CGPoint?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        WeiBeiQuietScrollers.configure(scrollView, hasHorizontalScroller: false)
        scrollView.drawsBackground = false

        let textView = ReaderSelectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.backgroundColor = .clear
        applyTheme(to: textView)
        applyAttributedText(to: textView, coordinator: context.coordinator)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyTheme(to: textView)
        applyAttributedText(to: textView, coordinator: context.coordinator)
        context.coordinator.applySearch(searchQuery, in: textView)
    }

    private func applyAttributedText(
        to textView: NSTextView,
        coordinator: Coordinator
    ) {
        let ink = WeiBeiNativePalette.ink(for: appearanceMode)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: ink,
            ]
        )
        let full = NSRange(location: 0, length: attributed.length)
        let cinnabar = NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.12, alpha: 1)
        for snippet in underlineSnippets {
            let needle = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard needle.count >= 4 else { continue }
            var search = full
            while search.length > 0 {
                let found = (attributed.string as NSString).range(of: needle, options: [], range: search)
                guard found.location != NSNotFound else { break }
                attributed.addAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: cinnabar,
                    ],
                    range: found
                )
                let next = found.location + found.length
                search = NSRange(location: next, length: max(0, attributed.length - next))
            }
        }
        guard !textView.attributedString().isEqual(to: attributed) else { return }
        coordinator.withoutSelectionReports {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributed)
            if NSMaxRange(selectedRange) <= attributed.length {
                textView.setSelectedRange(selectedRange)
            }
        }
    }

    private func applyTheme(to textView: NSTextView) {
        textView.textColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.insertionPointColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.selectedTextAttributes = [
            .backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode),
            .foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode)
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (String, CGPoint?) -> Void
        private var lastSearchQuery = ""
        private var suppressSelectionReport = false

        init(onSelectionChange: @escaping (String, CGPoint?) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func withoutSelectionReports(_ update: () -> Void) {
            suppressSelectionReport = true
            defer { suppressSelectionReport = false }
            update()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !suppressSelectionReport else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let stringRange = Range(range, in: textView.string) else {
                onSelectionChange("", nil)
                return
            }
            onSelectionChange(String(textView.string[stringRange]), Self.anchor(for: range, in: textView))
        }

        private static func anchor(for range: NSRange, in textView: NSTextView) -> CGPoint? {
            guard let window = textView.window else { return nil }
            let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard !rect.isEmpty else { return nil }
            let screenPoint = CGPoint(x: rect.midX, y: rect.minY)
            return SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)
        }

        func applySearch(_ query: String, in textView: NSTextView) {
            let query = ReaderSearch.cleaned(query)
            guard query != lastSearchQuery else { return }
            lastSearchQuery = query
            guard !query.isEmpty else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                return
            }
            onSelectionChange("", nil)
            guard let range = ReaderSearch.firstMatch(in: textView.string, query: query) else { return }
            suppressSelectionReport = true
            textView.setSelectedRange(range)
            suppressSelectionReport = false
            textView.scrollRangeToVisible(range)
        }
    }
}

private class ReaderSelectableTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

struct EscapeKeyBridge: NSViewRepresentable {
    var isEnabled = true
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onEscape: () -> Void
        private var monitor: Any?

        init(isEnabled: Bool, onEscape: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onEscape = onEscape
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let relevantWindows = [event.window, NSApp.keyWindow, NSApp.mainWindow]
                    .compactMap { $0 }
                let hasActiveSheet = relevantWindows.contains {
                    $0.sheetParent != nil || $0.attachedSheet != nil
                }
                guard event.keyCode == 53,
                      let self,
                      Self.shouldHandleEscape(
                          isEnabled: self.isEnabled,
                          hasModalWindow: NSApp.modalWindow != nil,
                          hasActiveSheet: hasActiveSheet
                      ) else { return event }
                self.onEscape()
                return nil
            }
        }

        static func shouldHandleEscape(
            isEnabled: Bool,
            hasModalWindow: Bool,
            hasActiveSheet: Bool
        ) -> Bool {
            isEnabled && !hasModalWindow && !hasActiveSheet
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
