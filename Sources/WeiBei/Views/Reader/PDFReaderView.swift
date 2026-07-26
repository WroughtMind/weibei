import AppKit
import PDFKit
import SwiftUI
import WebKit
import WeiBeiCore

struct PDFReaderRepresentable: NSViewRepresentable {
    var url: URL
    var browseMode: PDFBrowseMode
    var searchQuery: String
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
        PaneToggleContinuityVerifier.recordPDFReaderMake()
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

        context.coordinator.applySearch(searchQuery, in: view)
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
        PaneToggleContinuityVerifier.recordPDFReaderDismantle()
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
            suspend()
        }
    }
}

final class ReaderPDFView: PDFView {
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

final class PDFOCRPageOverlayView: NSView {
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

final class PDFOCRLineTextView: ReaderSelectableTextView, NSTextViewDelegate {
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
