import Combine
import Foundation
import WeiBeiCore

/// High-frequency pane chrome: visibility + focus.
/// Isolated from `WorkspaceStore` so toggles do not invalidate reader/agent/notes bodies.
@MainActor
final class WorkspacePaneState: ObservableObject {
    private var suppressPublish = false

    private var showReaderValue = true
    private var showAgentValue = true
    private var showNotesValue = true
    private(set) var centersInitialAgentComposer = false

    var showReader: Bool {
        get { showReaderValue }
        set {
            guard showReaderValue != newValue else { return }
            if !suppressPublish { objectWillChange.send() }
            showReaderValue = newValue
            if newValue { centersInitialAgentComposer = false }
        }
    }

    var showAgent: Bool {
        get { showAgentValue }
        set {
            guard showAgentValue != newValue else { return }
            let opensFromEmptyWorkspace = newValue
                && !showReaderValue && !showAgentValue && !showNotesValue
            if !suppressPublish { objectWillChange.send() }
            showAgentValue = newValue
            centersInitialAgentComposer = opensFromEmptyWorkspace
        }
    }

    var showNotes: Bool {
        get { showNotesValue }
        set {
            guard showNotesValue != newValue else { return }
            if !suppressPublish { objectWillChange.send() }
            showNotesValue = newValue
            if newValue { centersInitialAgentComposer = false }
        }
    }

    @Published var showDocumentSearch = false
    @Published var searchFocusRequest = 0
    @Published var readerSearchResults: [ReaderSearchResult] = []
    @Published var readerSearchResultIndex = -1
    @Published var readerSearchResultQuery = ""
    @Published var readerSearchResultMaterialID: String?
    @Published var readerSearchNavigationRequest = 0
    @Published var readerSearchSessionID = 0
    @Published var readerSearchReturnRequest = 0
    @Published private(set) var readerSearchCanReturn = false
    var readerSearchRequestedIndex = 0
    /// Set when a course search opens a document; the first reported match is selected once.
    var pendingFirstReaderMatch = false
    private var readerSearchOriginMaterialID: String?

    func resetReaderSearchSession() {
        readerSearchSessionID &+= 1
        endReaderSearchSession()
    }

    func endReaderSearchSession() {
        readerSearchCanReturn = false
        readerSearchOriginMaterialID = nil
        readerSearchResultIndex = -1
    }

    func canReturnToReaderSearchOrigin(for materialID: String?) -> Bool {
        readerSearchCanReturn && readerSearchOriginMaterialID == materialID
    }

    func adoptReaderSearchResults(
        _ results: [ReaderSearchResult],
        reportedIndex: Int,
        query: String,
        materialID: String
    ) {
        readerSearchResults = results
        readerSearchResultIndex = reportedIndex
        readerSearchResultQuery = query
        readerSearchResultMaterialID = materialID
        guard pendingFirstReaderMatch else { return }
        pendingFirstReaderMatch = false
        guard reportedIndex < 0, !results.isEmpty else { return }
        selectReaderSearchResult(0)
    }

    func selectReaderSearchResult(_ index: Int) {
        guard readerSearchResults.indices.contains(index) else { return }
        if readerSearchOriginMaterialID != readerSearchResultMaterialID {
            readerSearchSessionID &+= 1
            readerSearchOriginMaterialID = readerSearchResultMaterialID
        }
        readerSearchCanReturn = true
        readerSearchResultIndex = index
        readerSearchRequestedIndex = index
        readerSearchNavigationRequest &+= 1
    }

    func returnToReaderSearchOrigin() {
        guard readerSearchCanReturn else { return }
        readerSearchCanReturn = false
        readerSearchOriginMaterialID = nil
        readerSearchResultIndex = -1
        readerSearchReturnRequest &+= 1
        searchFocusRequest &+= 1
    }

    @Published var focusedPane: PaneFocus = .reader
    @Published var focusRequest = 0

    /// Collapse/expand notes+agent with a single `objectWillChange` (was two store publishes).
    func setRightPaneVisible(_ visible: Bool) {
        guard showNotesValue != visible || showAgentValue != visible else { return }
        objectWillChange.send()
        suppressPublish = true
        showNotesValue = visible
        showAgentValue = visible
        suppressPublish = false
        centersInitialAgentComposer = false
    }

    /// Apply multi-pane visibility with a single publish.
    func setDocumentPanes(reader: Bool, agent: Bool, notes: Bool) {
        guard showReaderValue != reader
            || showAgentValue != agent
            || showNotesValue != notes else { return }
        let opensFromEmptyWorkspace = agent && !reader && !notes
            && !showReaderValue && !showAgentValue && !showNotesValue
        objectWillChange.send()
        suppressPublish = true
        showReaderValue = reader
        showAgentValue = agent
        showNotesValue = notes
        suppressPublish = false
        centersInitialAgentComposer = opensFromEmptyWorkspace
    }

    func dockInitialAgentComposer() {
        guard centersInitialAgentComposer else { return }
        objectWillChange.send()
        centersInitialAgentComposer = false
    }
}

struct PaneExpansionRequest: Equatable {
    let id = UUID()
    let role: WorkspacePaneRole
    /// One-shot completion bound to this request's id: runs after AppKit finishes the
    /// pane expansion. A newer request replaces (and drops) an older pending closure.
    let onCompleted: (() -> Void)?

    static func == (lhs: PaneExpansionRequest, rhs: PaneExpansionRequest) -> Bool {
        lhs.id == rhs.id
    }
}
