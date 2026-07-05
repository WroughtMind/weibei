import PDFKit
import SwiftUI
import WeiBeiCore
import WebKit

struct ReaderView: View {
    var isImmersive = false

    @EnvironmentObject private var store: WorkspaceStore
    @State private var pdfBrowseMode: PDFBrowseMode = .scroll
    @State private var pdfPageIndex = 0
    @State private var pdfPageCount = 0
    @State private var pdfControlsHovering = false
    @State private var pdfControlsExpanded = false
    @State private var pdfControlsCollapseToken = UUID()
    @State private var pendingPDFPageIndex: Int?
    @State private var pdfHasSelectableText: Bool?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                readerBody
            }

            if store.selectedMaterialItem?.kind == .pdf {
                pdfFloatingControls
                    .padding(.trailing, isImmersive ? 18 : 10)
                    .padding(.bottom, isImmersive ? 18 : 12)
                    .transition(WeiBeiTransition.floating)
            }

            if pdfHasSelectableText == false {
                pdfTextLayerNotice
                    .padding(.leading, isImmersive ? 18 : 14)
                    .padding(.bottom, isImmersive ? 18 : 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(WeiBeiTransition.floating)
            }
        }
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .animation(WeiBeiMotion.panel, value: pdfBrowseMode)
        .animation(WeiBeiMotion.panel, value: store.showReaderSearch)
        .animation(WeiBeiMotion.panel, value: pdfHasSelectableText)
        .onAppear {
            syncReaderLocationTitle()
            pendingPDFPageIndex = store.readerTargetPageIndex
            applyPendingPDFPageIfReady()
        }
        .onChange(of: store.selectedItemID) { _, _ in
            pdfPageIndex = 0
            pdfPageCount = store.selectedMaterialItem?.kind == .pdf && store.selectedMaterialItem?.url == nil ? 1 : 0
            pdfHasSelectableText = store.selectedMaterialItem?.kind == .pdf && store.selectedMaterialItem?.url == nil ? true : nil
            syncReaderLocationTitle()
            pendingPDFPageIndex = store.readerTargetPageIndex
            applyPendingPDFPageIfReady()
        }
        .onChange(of: pdfPageIndex) { _, _ in
            syncReaderLocationTitle()
        }
        .onChange(of: pdfPageCount) { _, _ in
            syncReaderLocationTitle()
            applyPendingPDFPageIfReady()
        }
        .onChange(of: store.readerTargetPageIndex) { _, target in
            pendingPDFPageIndex = target
            applyPendingPDFPageIfReady()
        }
    }

    private func syncReaderLocationTitle() {
        guard let item = store.selectedMaterialItem else {
            store.updateReaderLocationTitle(nil)
            return
        }
        let title = item.kind == .pdf ? "\(item.title)，第 \(pdfPageIndex + 1) 页" : item.title
        store.updateReaderLocationTitle(title)
    }

    private func applyPendingPDFPageIfReady() {
        guard let target = pendingPDFPageIndex,
              store.selectedMaterialItem?.kind == .pdf,
              pdfPageCount > 0 else { return }
        pdfBrowseMode = .page
        pdfPageIndex = min(max(target, 0), max(pdfPageCount - 1, 0))
        pendingPDFPageIndex = nil
        store.readerTargetPageIndex = nil
        syncReaderLocationTitle()
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
                    .fill(WeiBeiTheme.paperRaised.opacity(pdfControlsActive ? 0.86 : 0.72))
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .opacity(pdfControlsHovering ? 0.055 : 0.0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(WeiBeiTheme.hairline.opacity(pdfControlsActive ? 0.64 : 0.30), lineWidth: 1)
        }
        .shadow(color: WeiBeiTheme.ink.opacity(pdfControlsHovering ? 0.045 : 0.0), radius: 7, y: 3)
        .opacity(pdfControlsActive ? 0.94 : 0.90)
        .offset(x: 0)
        .scaleEffect(pdfControlsHovering ? 1.01 : (pdfControlsActive ? 1 : 0.995), anchor: .trailing)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            schedulePDFControlsCollapse(after: 0.9)
        }
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                pdfControlsHovering = hovering
            }
            if hovering {
                revealPDFControls()
            } else {
                schedulePDFControlsCollapse(after: 0.28)
            }
        }
    }

    private var pdfTextLayerNotice: some View {
        HStack(spacing: 7) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 11, weight: .medium))
            Text("未检测到可选文本层")
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

        if pdfBrowseMode == .page, pdfPageCount > 1, pdfControlsExpanded {
            Group {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.55))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 2)

                Button {
                    revealPDFControls()
                    pdfPageIndex = PageNavigator.previous(pdfPageIndex)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 22))
                .keyboardShortcut("[", modifiers: [.command])
                .accessibilityLabel(Text("上一页"))
                .help("上一页")

                Text(PageNavigator.display(pdfPageIndex, pageCount: pdfPageCount))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(width: 50, height: 22)

                Button {
                    revealPDFControls()
                    pdfPageIndex = PageNavigator.next(pdfPageIndex, pageCount: pdfPageCount)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 22))
                .keyboardShortcut("]", modifiers: [.command])
                .accessibilityLabel(Text("下一页"))
                .help("下一页")
            }
            .transition(WeiBeiTransition.floating)
        }
    }

    private var pdfModeToggle: some View {
        Button {
            withAnimation(WeiBeiMotion.panel) {
                pdfBrowseMode = pdfBrowseMode.toggled
            }
            revealPDFControls(collapseAfter: 1.6)
        } label: {
            HStack(spacing: showsPDFModeLabel ? 5 : 0) {
                Image(systemName: pdfBrowseMode.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(pdfBrowseMode.label)
                    .font(.system(size: 11, weight: .medium))
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
        .accessibilityLabel(Text("切换 PDF 浏览方式，当前\(pdfBrowseMode.label)"))
        .help("切换到\(pdfBrowseMode.toggled.help)")
    }

    private var pdfControlsActive: Bool {
        pdfControlsHovering || pdfControlsExpanded
    }

    private var pdfModeForeground: Color {
        if pdfBrowseMode == .page {
            return WeiBeiTheme.cinnabar
        }
        return WeiBeiTheme.secondaryInk
    }

    private var showsPDFModeLabel: Bool {
        true
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
                        pageIndex: $pdfPageIndex,
                        pageCount: $pdfPageCount,
                        onSelectableTextChange: { available in pdfHasSelectableText = available }
                    ) { text, anchor, selectionPageIndex in
                        let ownerTitle = "\(item.title)，第 \(selectionPageIndex + 1) 页"
                        store.updateReaderLocationTitle(ownerTitle)
                        store.updateSelection(text, source: .document, anchor: anchor, ownerTitle: ownerTitle)
                    }
                } else {
                    SamplePDFView(appearanceMode: store.appearanceMode) { text, anchor in
                        let ownerTitle = "\(item.title)，第 1 页"
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
                        onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) }
                    ) { text, anchor in
                        store.updateSelection(text, source: .document, anchor: anchor)
                    }
                } else {
                    WebReaderRepresentable(
                        html: store.sampleHTML(for: item),
                        searchQuery: store.readerSearch,
                        appearanceMode: store.appearanceMode,
                        onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) }
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
            onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
            onSourceReference: { reference in store.openSourceReference(reference) },
            onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) }
        ) { text, anchor in
            store.updateSelection(text, source: .document, anchor: anchor)
        }
    }

}

private enum PDFBrowseMode: String, CaseIterable, Identifiable {
    case scroll
    case page

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scroll: "滚动"
        case .page: "翻页"
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

    var help: String {
        switch self {
        case .scroll: "连续滚动浏览 PDF"
        case .page: "单页翻页浏览 PDF"
        }
    }
}

private struct PDFReaderRepresentable: NSViewRepresentable {
    var url: URL
    var browseMode: PDFBrowseMode
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    @Binding var pageIndex: Int
    @Binding var pageCount: Int
    var onSelectableTextChange: (Bool?) -> Void = { _ in }
    var onSelectionChange: (String, CGPoint?, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            pageIndex: $pageIndex,
            pageCount: $pageCount,
            onSelectableTextChange: onSelectableTextChange,
            onSelectionChange: onSelectionChange
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let view = ReaderPDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.backgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)
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
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.pageIndex = $pageIndex
        context.coordinator.pageCount = $pageCount
        context.coordinator.appearanceMode = appearanceMode
        context.coordinator.onSelectableTextChange = onSelectableTextChange
        view.backgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)

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

        context.coordinator.applySearch(searchQuery, in: view)
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

    final class Coordinator: NSObject {
        var pageIndex: Binding<Int>
        var pageCount: Binding<Int>
        var onSelectableTextChange: (Bool?) -> Void
        var onSelectionChange: (String, CGPoint?, Int) -> Void
        var appearanceMode: WeiBeiAppearanceMode = .paper
        private weak var observedView: PDFView?
        private var observer: NSObjectProtocol?
        private var pageObserver: NSObjectProtocol?
        private var selectionWork: DispatchWorkItem?
        private var nativeTextPageIndexes: Set<Int> = []
        private var ocrPagesByPageIndex: [Int: PDFOCRPage] = [:]
        private var pendingOCRPageIndexes: Set<Int> = []
        private var ocrHighlightedLinesByPageIndex: [Int: Set<Int>] = [:]
        private var lastSearchQuery = ""
        private var loadGeneration = 0
        private(set) var loadedURL: URL?

        init(pageIndex: Binding<Int>, pageCount: Binding<Int>, onSelectableTextChange: @escaping (Bool?) -> Void, onSelectionChange: @escaping (String, CGPoint?, Int) -> Void) {
            self.pageIndex = pageIndex
            self.pageCount = pageCount
            self.onSelectableTextChange = onSelectableTextChange
            self.onSelectionChange = onSelectionChange
        }

        func load(_ url: URL, in view: PDFView) {
            loadGeneration += 1
            let generation = loadGeneration
            loadedURL = url
            view.document = nil
            nativeTextPageIndexes = []
            clearOCROverlays(in: view)
            lastSearchQuery = ""
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
                        self.applySearch(self.lastSearchQuery, in: view, force: true)
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
                        self.applySearch(self.lastSearchQuery, in: view, force: true)
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
                        self.applySearch(self.lastSearchQuery, in: view, force: true)
                    }
                }
            }
        }

        func observe(_ view: PDFView) {
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
                self.pageIndex.wrappedValue = document.index(for: page)
                self.updateSelectableTextState(in: view)
                self.ensureOCRForCurrentPage(in: view)
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

        func applySearch(_ query: String, in view: PDFView, force: Bool = false) {
            let query = ReaderSearch.cleaned(query)
            guard force || query != lastSearchQuery else { return }
            lastSearchQuery = query

            guard !query.isEmpty else {
                view.highlightedSelections = nil
                view.clearSelection()
                setOCRHighlightedLines([:], in: view)
                return
            }

            let matches = view.document?.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive]) ?? []
            view.highlightedSelections = matches
            if let first = matches.first {
                setOCRHighlightedLines([:], in: view)
                view.go(to: first)
            } else {
                applyOCRSearch(query, in: view)
            }
        }

        private func applyOCRSearch(_ query: String, in view: PDFView) {
            var highlightedLines: [Int: Set<Int>] = [:]
            var firstPageIndex: Int?

            for page in ocrPagesByPageIndex.values.sorted(by: { $0.pageIndex < $1.pageIndex }) {
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
            selectionWork?.cancel()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            if let pageObserver {
                NotificationCenter.default.removeObserver(pageObserver)
            }
        }
    }
}

private final class ReaderPDFView: PDFView {
    var reportCurrentSelection: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        clearSelection()
        reportCurrentSelection?()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        reportCurrentSelection?()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        reportCurrentSelection?()
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

struct WebReaderRepresentable: NSViewRepresentable {
    var html: String?
    var url: URL?
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
    var onSelectionChange: (String, CGPoint?) -> Void

    init(
        html: String,
        searchQuery: String = "",
        appearanceMode: WeiBeiAppearanceMode = .paper,
        onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false },
        onSelectionChange: @escaping (String, CGPoint?) -> Void
    ) {
        self.html = html
        self.url = nil
        self.searchQuery = searchQuery
        self.appearanceMode = appearanceMode
        self.onAppShortcut = onAppShortcut
        self.onSelectionChange = onSelectionChange
    }

    init(
        url: URL,
        searchQuery: String = "",
        appearanceMode: WeiBeiAppearanceMode = .paper,
        onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false },
        onSelectionChange: @escaping (String, CGPoint?) -> Void
    ) {
        self.html = nil
        self.url = url
        self.searchQuery = searchQuery
        self.appearanceMode = appearanceMode
        self.onAppShortcut = onAppShortcut
        self.onSelectionChange = onSelectionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            appearanceMode: appearanceMode,
            onAppShortcut: onAppShortcut,
            onSelectionChange: onSelectionChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "selection")
        controller.add(context.coordinator, name: "appShortcut")
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
            source: Self.readerStyleScript(for: appearanceMode),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.searchQuery = searchQuery
        context.coordinator.onAppShortcut = onAppShortcut
        if context.coordinator.appearanceMode != appearanceMode {
            context.coordinator.appearanceMode = appearanceMode
            view.evaluateJavaScript(Self.readerStyleScript(for: appearanceMode))
        }
        if let url {
            let signature = "file:\(url.path)"
            if context.coordinator.loadedSignature != signature {
                context.coordinator.loadedSignature = signature
                view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                context.coordinator.applySearch(in: view)
            }
        } else if let html {
            let signature = "html:\(html.hashValue)"
            if context.coordinator.loadedSignature != signature {
                context.coordinator.loadedSignature = signature
                view.loadHTMLString(html, baseURL: nil)
            } else {
                context.coordinator.applySearch(in: view)
            }
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "selection")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "appShortcut")
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
        if (command && !option && !control && !shift) return ["1", "2", "3", "4", "b", "j", "k", "f"].includes(key);
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

      function reportSelection() {
        window.cancelAnimationFrame(frame);
        frame = window.requestAnimationFrame(() => {
          if (window.weiBeiSuppressSelectionReport) return;
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
    })();
    """

    static func readerStyleScript(for mode: WeiBeiAppearanceMode) -> String {
        let css: String
        switch mode {
        case .paper:
            css = """
            html, body { max-width: 100%; overflow-x: hidden; color-scheme: light; background: transparent !important; }
            body, main, article, section, div, p, li, blockquote, td, th, span { color: #1d1814 !important; }
            ::selection { background: rgba(145, 38, 27, 0.20); color: #1d1814; }
            a { color: #31566b !important; }
            code { background: rgba(29, 24, 20, .06) !important; color: #5d4b33 !important; }
            pre { background: rgba(29, 24, 20, .052) !important; border-color: rgba(92, 70, 46, .28) !important; }
            table, th, td { border-color: rgba(92, 70, 46, .28) !important; }
            """
        case .inkstone:
            css = """
            html, body { max-width: 100%; overflow-x: hidden; color-scheme: dark; background: transparent !important; }
            body, main, article, section, div, p, li, blockquote, td, th, span { color: #D7CBB0 !important; background-color: transparent !important; }
            ::selection { background: rgba(166, 54, 43, 0.35); color: #F5E7C8; }
            a { color: #C8B98A !important; text-decoration-color: rgba(200, 185, 138, .55) !important; }
            h1, h2, h3 { color: #C8B98A !important; }
            blockquote { border-left: 3px solid rgba(166, 54, 43, .62) !important; background: rgba(166, 54, 43, .08) !important; color: #C9BFA5 !important; }
            code { background: rgba(255, 255, 255, .05) !important; color: #D8B47A !important; }
            pre { background: #171717 !important; border: 1px solid #2D2D2D !important; color: #D7CBB0 !important; }
            table { background: rgba(255, 255, 255, .02) !important; }
            th { color: #C8B98A !important; background: rgba(200, 185, 138, .08) !important; }
            table, th, td { border-color: #2D2D2D !important; }
            """
        }
        return """
        (() => {
          const css = \(Self.json(css));
          let style = document.getElementById("weibei-reader-style");
          if (!style) {
            style = document.createElement("style");
            style.id = "weibei-reader-style";
            document.head.appendChild(style);
          }
          document.documentElement.dataset.weibeiTheme = \(Self.json(mode.webThemeName));
          style.textContent = `${css}
            body, main, article, section, div { box-sizing: border-box; max-width: 100%; }
            h1, h2, h3, h4, p, li, blockquote { overflow-wrap: anywhere; word-break: normal; }
            pre, code { white-space: pre-wrap; overflow-wrap: anywhere; }
            img, table { max-width: 100%; }
          `;
        })();
        """
    }

    private static func json(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onSelectionChange: (String, CGPoint?) -> Void
        var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
        var loadedSignature: String?
        var searchQuery = ""
        var appearanceMode: WeiBeiAppearanceMode = .paper
        private var lastAppliedSearchQuery = ""
        weak var webView: WKWebView?

        init(
            appearanceMode: WeiBeiAppearanceMode,
            onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool,
            onSelectionChange: @escaping (String, CGPoint?) -> Void
        ) {
            self.appearanceMode = appearanceMode
            self.onAppShortcut = onAppShortcut
            self.onSelectionChange = onSelectionChange
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "appShortcut" {
                guard let body = message.body as? [String: Any],
                      let key = body["key"] as? String else { return }
                _ = onAppShortcut(key, Self.modifiers(from: body))
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
            webView.evaluateJavaScript(WebReaderRepresentable.readerStyleScript(for: appearanceMode))
            applySearch(in: webView)
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

        private static func json(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
    }
}

private struct MarkdownDocumentReaderView: View {
    var markdown: String
    var markdownBaseURL: URL?
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
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
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onSelectionChange,
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut
        )
    }
}

private struct MarkdownReadFailureView: View {
    var fileName: String

    var body: some View {
        ReaderStateMessage(
            title: "无法读取 Markdown",
            detail: fileName,
            systemImage: "exclamationmark.triangle"
        )
    }
}

private struct EmptyReaderView: View {
    var body: some View {
        ReaderStateMessage(
            title: "选择资料",
            detail: "从资料库打开 HTML、PDF 或 Markdown。",
            systemImage: "doc.text.magnifyingglass"
        )
    }
}

private struct NotebookSelectedReaderView: View {
    var body: some View {
        ReaderStateMessage(
            title: "当前是笔记",
            detail: "阅读区只显示资料，右侧继续写作当前笔记。",
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

private struct PlainTextReaderView: View {
    var text: String
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var onSelectionChange: (String, CGPoint?) -> Void

    var body: some View {
        SelectablePlainTextReader(
            text: text,
            searchQuery: searchQuery,
            appearanceMode: appearanceMode,
            onSelectionChange: onSelectionChange
        )
            .padding(32)
    }
}

private struct SelectablePlainTextReader: NSViewRepresentable {
    var text: String
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
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
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.backgroundColor = .clear
        applyTheme(to: textView)
        textView.string = text
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
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.applySearch(searchQuery, in: textView)
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

private struct SamplePDFView: View {
    var appearanceMode: WeiBeiAppearanceMode
    var onSelectionChange: (String, CGPoint?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SamplePDFSelectablePageView(
                    appearanceMode: appearanceMode,
                    onSelectionChange: onSelectionChange
                )
                .frame(maxWidth: 620, minHeight: 820, alignment: .topLeading)
                .background(WeiBeiTheme.paperRaised)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(WeiBeiTheme.hairline, lineWidth: 1)
                }
                .shadow(color: WeiBeiTheme.ink.opacity(0.075), radius: 16, y: 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
        }
        .background(WeiBeiTheme.paper)
    }
}

private struct SamplePDFSelectablePageView: NSViewRepresentable {
    var appearanceMode: WeiBeiAppearanceMode
    var onSelectionChange: (String, CGPoint?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = ReaderSelectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 42, height: 44)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.delegate = context.coordinator
        applyContent(to: textView, coordinator: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        applyContent(to: textView, coordinator: context.coordinator)
    }

    private func applyContent(to textView: NSTextView, coordinator: Coordinator) {
        coordinator.appearanceMode = appearanceMode
        if coordinator.appliedAppearanceMode != appearanceMode {
            textView.textStorage?.setAttributedString(Self.attributedText(for: appearanceMode))
            coordinator.appliedAppearanceMode = appearanceMode
        }
        textView.selectedTextAttributes = [
            .foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode),
            .backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode)
        ]
    }

    private static func attributedText(for appearanceMode: WeiBeiAppearanceMode) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let ink = WeiBeiNativePalette.ink(for: appearanceMode)
        let secondary = ink.withAlphaComponent(0.62)
        let tertiary = ink.withAlphaComponent(0.45)
        let titleFont = NSFont.systemFont(ofSize: 34, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 17, weight: .regular)
        let smallFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let footerFont = NSFont.systemFont(ofSize: 12, weight: .medium)

        func paragraph(lineSpacing: CGFloat = 0, paragraphSpacing: CGFloat = 0) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = paragraphSpacing
            return style
        }

        func append(_ string: String, font: NSFont, color: NSColor, style: NSParagraphStyle) {
            output.append(NSAttributedString(string: string, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ]))
        }

        append("Mishkin 教材样例                                      PDF 阅读样例\n", font: smallFont, color: tertiary, style: paragraph(paragraphSpacing: 20))
        append("金融体系的功能\n", font: titleFont, color: ink, style: paragraph(paragraphSpacing: 24))
        append("金融市场和金融中介能够把储蓄者的资金转移给有投资机会的人。它们降低交易成本，缓解信息不对称，并帮助社会更有效地配置资源。\n", font: bodyFont, color: ink, style: paragraph(lineSpacing: 8, paragraphSpacing: 22))
        append("这一页是内置 PDF 阅读样例。导入真实 PDF 后，中央区域会切换为 PDFKit 阅读器。现在这个样例页也可以像真实 PDF 一样选中文字并唤起选区 Agent。\n", font: bodyFont, color: secondary, style: paragraph(lineSpacing: 8, paragraphSpacing: 240))
        append("页 1                                                        魏碑", font: footerFont, color: tertiary, style: paragraph())
        return output
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (String, CGPoint?) -> Void
        var appearanceMode: WeiBeiAppearanceMode = .paper
        var appliedAppearanceMode: WeiBeiAppearanceMode?

        init(onSelectionChange: @escaping (String, CGPoint?) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
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
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onEscape: () -> Void
        private var monitor: Any?

        init(onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.onEscape()
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
