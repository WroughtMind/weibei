import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Selection, navigation, pane layout, and presentation behavior exposed by the workspace façade.
/// Pane visibility, focus, reader navigation, and source-reference behavior.
extension WorkspaceStore {
    func focus(_ pane: PaneFocus) {
        if pane == .library {
            if !showLibrary {
                recordNavigationPoint()
                clearUnpinnedFloatingSelection()
            }
            showLibrary = true
        }
        if pane == .agent {
            if layout == .documentNotesSplit, !showAgent {
                showAgent = true
            } else if layout == .immersiveReading || layout == .immersiveWriting {
                // Primary chat is immersive conversation, not a deleted overlay surface.
                layout = .immersiveConversation
                showAgent = true
                if agentSurface != .selectionFloat {
                    agentSurface = .hidden
                }
                showQuietInsight = false
            }
        }
        collapseSelectionFloatIntoConversationIfVisible()
        focusedPane = pane
        focusRequest += 1
    }

    func toggleLibrary() {
        let willShow = !showLibrary

        // 1) Flip drawer chrome first — publishes only on `libraryDrawer`, so reader/agent/notes
        //    do not re-render and the slide can start on the next frame.
        showLibrary = willShow

        // 2) Focus / selection side effects next run-loop tick (touches WorkspaceStore @Published).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                if willShow {
                    self.clearUnpinnedFloatingSelection()
                    self.focusedPane = .library
                } else if self.focusedPane == .library {
                    self.focusedPane = .reader
                }
                self.focusRequest += 1
            }
        }
    }

    func revealLibrary() {
        if !showLibrary {
            clearUnpinnedFloatingSelection()
        }
        showLibrary = true
        focus(.library)
    }

    func toggleReader() {
        toggleDocumentPane(.reader)
    }

    func toggleAgent() {
        if selectionContext != nil {
            recordNavigationPoint()
            revealDocumentPane(.agent, clearSelection: false)
            routeSelectionToConversation()
            save()
            return
        }
        toggleDocumentPane(.agent)
    }

    func toggleNotes() {
        toggleDocumentPane(.notes)
    }

    func toggleRightPane() {
        guard layout.hasCollapsibleRightPane else { return }
        recordNavigationPoint()
        showRightPane.toggle()
        clearUnpinnedFloatingSelection()
        focus(showRightPane ? rightPaneRevealFocus : fallbackDocumentPaneFocus())
        save()
    }

    func revealRightPane(focusing pane: PaneFocus = .notes) {
        guard layout.hasCollapsibleRightPane else { return }
        let targetVisible = pane == .agent ? showAgent : pane == .notes ? showNotes : showRightPane
        if !targetVisible {
            recordNavigationPoint()
            clearUnpinnedFloatingSelection()
        }
        switch pane {
        case .agent:
            showAgent = true
        case .notes:
            showNotes = true
        default:
            showRightPane = true
        }
        focus(pane)
        save()
    }

    func toggleDocumentPane(_ role: WorkspacePaneRole) {
        recordNavigationPoint()
        clearUnpinnedFloatingSelection()
        if layoutIsImmersive {
            toggleDocumentPaneFromImmersive(role)
        } else {
            let openingFromEmptyBoard = !showReader && !showAgent && !showNotes
            let willShow = !isPaneVisible(role)
            setDocumentPane(willShow, role)
            // Empty board → first open: restore canonical 文稿 | 对话 | 笔记 left→right order.
            if willShow && openingFromEmptyBoard {
                threePaneOrder = WorkspacePaneRole.defaultThreePaneOrder
            }
            layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
        }
        focus(isPaneVisible(role) ? role.focus : fallbackDocumentPaneFocus())
        save()
    }

    func revealDocumentPane(_ role: WorkspacePaneRole, clearSelection: Bool = true) {
        if clearSelection {
            clearUnpinnedFloatingSelection()
        }
        if layoutIsImmersive {
            setDocumentPaneSet(immersivePaneSet().union([role]))
        } else {
            setDocumentPane(true, role)
        }
        layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
        focus(role.focus)
    }

    var layoutIsImmersive: Bool {
        switch layout {
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return true
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return false
        }
    }

    func toggleDocumentPaneFromImmersive(_ role: WorkspacePaneRole) {
        var visible = immersivePaneSet()
        if visible.contains(role) {
            visible.remove(role)
        } else {
            visible.insert(role)
        }
        setDocumentPaneSet(visible)
        layout = layoutMatchingThreePaneOrder(normalizedThreePaneOrder)
    }

    func immersivePaneSet() -> Set<WorkspacePaneRole> {
        switch layout {
        case .immersiveReading:
            return [.reader]
        case .immersiveConversation:
            return [.agent]
        case .immersiveWriting:
            return [.notes]
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return Set(visibleDocumentPaneOrder)
        }
    }

    func setDocumentPaneSet(_ roles: Set<WorkspacePaneRole>) {
        showReader = roles.contains(.reader)
        showAgent = roles.contains(.agent)
        showNotes = roles.contains(.notes)
        if !showReader {
            showReaderSearch = false
            readerSearch = ""
        }
    }

    func setDocumentPane(_ visible: Bool, _ role: WorkspacePaneRole) {
        switch role {
        case .reader:
            showReader = visible
            if !visible {
                showReaderSearch = false
                readerSearch = ""
            }
        case .agent:
            showAgent = visible
        case .notes:
            showNotes = visible
        }
    }

    func fallbackDocumentPaneFocus() -> PaneFocus {
        visibleDocumentPaneOrder.first?.focus ?? .reader
    }

    func revealReaderSearch() {
        guard hasSelectedMaterial else {
            clearReaderSearchIfNeeded()
            return
        }
        if !showReaderSearch || layout == .immersiveConversation || layout == .immersiveWriting {
            recordNavigationPoint()
        }
        if layout == .immersiveConversation || layout == .immersiveWriting {
            setLayout(.immersiveReading)
        }
        showReaderSearch = true
        focus(.reader)
    }

    func hideReaderSearch() {
        if showReaderSearch || !readerSearch.isEmpty {
            recordNavigationPoint()
        }
        showReaderSearch = false
        readerSearch = ""
        clearUnpinnedFloatingSelection(keepContext: false)
        focus(.reader)
    }

    func updateReaderLocationTitle(_ title: String?) {
        let cleaned = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextTitle = cleaned.isEmpty ? selectedMaterialItem.map(displayTitle) : cleaned
        guard readerLocationTitle != nextTitle else { return }
        readerLocationTitle = nextTitle
    }

    func updateReaderHTMLLocation(id: String?, title: String?, reason: String) {
        guard selectedMaterialItem?.kind == .html else { return }
        PaneToggleContinuityVerifier.recordHTMLLocationCall(reason: reason)
        let cleanedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextID = cleanedID.isEmpty ? nil : String(cleanedID.prefix(500))
        let nextTitle = cleanedTitle.isEmpty ? selectedMaterialItem.map(displayTitle) : String(cleanedTitle.prefix(300))
        if reason == "jump" {
            clearReaderHTMLLocationTarget()
        }
        guard readerLocationID != nextID || readerLocationTitle != nextTitle else { return }
        PaneToggleContinuityVerifier.recordHTMLLocationCommit(reason: reason)
        readerLocationID = nextID
        readerLocationTitle = nextTitle
        recordCurrentStudyLocation(incrementVisit: false)
    }

    func requestReaderHTMLLocation(id: String?, title: String?) {
        readerTargetLocationID = id
        readerTargetLocationTitle = title
        readerTargetLocationRequestID = UUID()
    }

    func clearReaderHTMLLocationTarget() {
        guard readerTargetLocationID != nil || readerTargetLocationTitle != nil else { return }
        readerTargetLocationID = nil
        readerTargetLocationTitle = nil
    }

    func requestReaderPDFPage(_ pageIndex: Int?, recordsLocation: Bool) {
        readerTargetPageRecordsLocation = recordsLocation && pageIndex != nil
        readerTargetPageIndex = pageIndex.map { max($0, 0) }
        readerTargetPageRequestID = UUID()
    }

    func consumeReaderPDFPageRequest(_ requestID: UUID) {
        guard readerTargetPageRequestID == requestID else { return }
        readerTargetPageIndex = nil
        readerTargetPageRecordsLocation = false
    }

    func updateReaderPageIndex(_ index: Int) {
        let nextIndex = max(index, 0)
        guard readerPageIndex != nextIndex else { return }
        readerPageIndex = nextIndex
        recordCurrentStudyLocation(incrementVisit: false)
    }

    func recordCurrentStudyLocation(incrementVisit: Bool) {
        guard let item = selectedMaterialItem else { return }
        let previous = studyLocationsByItemID[item.id]
        let itemTitle = sourceReferenceBaseTitle(for: item)
        let locationID = item.kind == .html ? readerLocationID : nil
        let pageIndex = item.kind == .pdf ? readerPageIndex : nil
        if !incrementVisit,
           previous?.itemTitle == itemTitle,
           previous?.locationID == locationID,
           previous?.locationTitle == readerLocationTitle,
           previous?.pageIndex == pageIndex {
            return
        }
        studyLocationsByItemID[item.id] = StudyLocation(
            itemID: item.id,
            itemTitle: itemTitle,
            locationID: locationID,
            locationTitle: readerLocationTitle,
            pageIndex: pageIndex,
            lastStudiedAt: Date(),
            visitCount: max((previous?.visitCount ?? 0) + (incrementVisit ? 1 : 0), 1)
        )
        studyProgressSaveTask?.cancel()
        let delay = studyProgressSaveDelay
        studyProgressSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.studyProgressSaveTask = nil
            self?.save()
        }
    }

    func restoreCurrentStudyLocation() {
        guard let item = selectedMaterialItem else { return }
        guard let location = studyLocationsByItemID[item.id] else {
            readerLocationID = nil
            readerLocationTitle = displayTitle(for: item)
            return
        }
        readerLocationID = item.kind == .html ? location.locationID : nil
        readerLocationTitle = location.locationTitle ?? displayTitle(for: item)
        if item.kind == .pdf {
            readerPageIndex = max(location.pageIndex ?? 0, 0)
            requestReaderPDFPage(location.pageIndex, recordsLocation: false)
        } else if item.kind == .html {
            requestReaderHTMLLocation(id: location.locationID, title: location.locationTitle)
        }
    }

    func recordReaderPageNavigationPoint() {
        guard selectedMaterialItem?.kind == .pdf else { return }
        recordNavigationPoint()
    }

    var canOpenSelectedSourceReference: Bool {
        guard selectionContext?.isNoteSelection == true else { return false }
        return sourceReferenceItem(from: selectionContext?.text) != nil
    }

    func openSelectedSourceReference() {
        guard let text = selectionContext?.text else { return }
        openSourceReference(text)
    }

    @discardableResult
    func openSourceReference(_ rawReference: String) -> Bool {
        guard let item = sourceReferenceItem(from: rawReference) else { return false }
        let reference = SourceReferenceTitle.parse(rawReference)
        // Immersive chat only shows the agent pane — leave it so the reader/note is visible.
        if layout == .immersiveConversation || layout == .immersiveWriting {
            if item.isNotebookNote {
                setLayout(.immersiveWriting)
            } else {
                setLayout(.immersiveReading)
            }
        }
        select(itemID: item.id)
        if item.isNotebookNote {
            showNotes = true
            focus(.notes)
            return true
        }
        showReader = true
        requestReaderPDFPage(
            item.kind == .pdf ? reference.pageIndex : nil,
            recordsLocation: item.kind == .pdf && reference.pageIndex != nil
        )
        let htmlTargetID = item.kind == .html
            ? reference.sectionLocationID
                ?? reference.sectionOrdinal.map { "html-heading-\(max($0 - 1, 0))" }
            : nil
        requestReaderHTMLLocation(
            id: htmlTargetID,
            title: item.kind == .html ? reference.sectionTitle : nil
        )
        focus(.reader)
        return true
    }

    /// Open a material/note citation from chat tags when the label is only a human title.
    @discardableResult
    func openAgentCitation(kind: String, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Prefer the structured "来源：" parser (handles section markers).
        if openSourceReference("来源：\(trimmed)") { return true }
        if openSourceReference(trimmed) { return true }
        // Fuzzy title match for Pi short labels like "货币金融学课程 HTML".
        guard let item = resolveStudyItem(matchingCitationTitle: trimmed) else { return false }
        if item.isNotebookNote || kind == "note" {
            if layout == .immersiveConversation || layout == .immersiveReading {
                setLayout(.immersiveWriting)
            }
            select(itemID: item.id)
            showNotes = true
            focus(.notes)
            return true
        }
        openCourseMaterial(item.id)
        return true
    }

}
