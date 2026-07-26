import Foundation
import PDFKit
import SwiftUI
import WeiBeiCore
import WebKit

extension Notification.Name {
    static let weiBeiVerificationUserScroll = Notification.Name("WeiBeiVerificationUserScroll")
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
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 30)

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
                        .fill(WeiBeiTheme.paperRaised.opacity(appearanceMode == .inkstone ? 0.34 : 0.72))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(WeiBeiTheme.hairline.opacity(appearanceMode == .inkstone ? 0.30 : 0.42), lineWidth: 1)
                        }
                }
                .shadow(color: WeiBeiTheme.ink.opacity(appearanceMode == .inkstone ? 0.24 : 0.07), radius: 9, y: 4)
                .padding(.horizontal, actionsAlignedTrailing ? 14 : 0)
                .padding(.top, 7)
                .modifier(PaneHeaderReorderModifier(role: reorderRole))
                .transition(WeiBeiTransition.floating)
            }
        }
        .contentShape(Rectangle())
        .onHover(perform: updateVisibility)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    @State private var pendingPDFLocationCommit: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let railOnly = ContentRailMetrics.isRailOnly(
                availableWidth: geometry.size.width,
                allowed: supportsContentRail && !isImmersive
            )
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    readerBody
                }
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
                    contentRail(isRailOnly: railOnly, availableWidth: geometry.size.width)
                        .frame(
                            width: railOnly ? min(ContentRailMetrics.railOnlyWidth, geometry.size.width) : geometry.size.width,
                            height: geometry.size.height,
                            alignment: .leading
                        )
                        .zIndex(6)
                }
            }
            .overlay(alignment: .top) {
                if !railOnly, showsFloatingTitle {
                    ImmersiveHoverTitleView(
                        mark: "DOC",
                        title: floatingTitle,
                        appearanceMode: store.appearanceMode,
                        reorderRole: floatingTitleReorderRole
                    ) {
                        HStack(spacing: 8) {
                            selectionAskThreadsMenu
                            importedDocumentAdaptationControl
                        }
                    }
                }
            }
        }
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .animation(WeiBeiMotion.panel, value: pdfBrowseMode)
        .animation(WeiBeiMotion.panel, value: store.showReaderSearch)
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
        if htmlContentRailActiveID != id {
            htmlContentRailActiveID = id
        }
        guard change.reason == .scroll || change.reason == .jump else { return }
        let title = id.flatMap { activeID in
            htmlContentRailItems.first(where: { $0.id == activeID })?.title
        }
        scheduleHTMLLocationCommit(id: id, title: title, reason: change.reason)
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
                        searchQuery: store.readerSearch,
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
                    SamplePDFView(appearanceMode: store.appearanceMode, language: store.interfaceLanguage) { text, anchor in
                        let title = store.displayTitle(for: item)
                        let ownerTitle = store.ui("\(title)，第 1 页", "\(title), page 1")
                        store.updateReaderLocationTitle(ownerTitle)
                        store.updateSelection(text, source: .document, anchor: anchor, ownerTitle: ownerTitle)
                    }
                }
            case .html:
                if let url = item.url {
                    WebReaderRepresentable(
                        url: url,
                        searchQuery: store.readerSearch,
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
                    WebReaderRepresentable(
                        html: store.sampleHTML(for: item),
                        searchQuery: store.readerSearch,
                        appearanceMode: store.appearanceMode,
                        adaptsDocumentColors: true,
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
                }
            case .markdown:
                if let url = item.url {
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        markdownReader(markdown: text, markdownBaseURL: url.deletingLastPathComponent())
                    } else {
                        MarkdownReadFailureView(fileName: url.lastPathComponent)
                    }
                } else {
                    markdownReader(markdown: store.sampleText(for: item), markdownBaseURL: store.currentMarkdownBaseURL)
                }
            case .text:
                if let url = item.url, let text = try? String(contentsOf: url, encoding: .utf8) {
                    PlainTextReaderView(text: text, searchQuery: store.readerSearch, appearanceMode: store.appearanceMode) { text, anchor in
                        store.updateSelection(text, source: .document, anchor: anchor)
                    }
                } else {
                    PlainTextReaderView(text: store.sampleText(for: item), searchQuery: store.readerSearch, appearanceMode: store.appearanceMode) { text, anchor in
                        store.updateSelection(text, source: .document, anchor: anchor)
                    }
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
            searchQuery: store.readerSearch,
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
