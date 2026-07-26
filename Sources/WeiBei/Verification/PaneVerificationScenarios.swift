import AppKit
import Foundation
import SwiftUI
import WeiBeiCore

/// Pane continuity, layout, reorder, and reader-position verification scenarios.
extension WorkspaceStore {
    /// Verifies that reader, note, and agent state survive pane visibility changes.
    func runPaneToggleContinuityVerification() async {
        layout = .documentAgentNotes
        showLibrary = true
        showReader = true
        showAgent = false
        showNotes = true
        agentSurface = .hidden
        recordVerificationStage("pane-toggle-context-prepared")
        let agentMarker = AgentMessage(
            role: .assistant,
            text: "Pane continuity conversation marker",
            source: "verification",
            backend: .offline
        )
        messages = [agentMarker]
        let baselineOrder = normalizedThreePaneOrder
        let cases: [(itemID: String, agentVisible: Bool)] = [
            ("sample-html", false),
            ("sample-html", true),
            ("sample-pdf", false),
            ("sample-pdf", true),
            ("sample-md", false),
            ("sample-md", true),
        ]
        var caseReports: [String] = []
        var allPassed = true

        for verificationCase in cases {
            showReader = true
            showAgent = verificationCase.agentVisible
            showNotes = true
            select(itemID: verificationCase.itemID)
            if verificationCase.itemID == "sample-html" {
                await waitForHTMLContentRailToSettle()
                requestReaderHTMLLocation(
                    id: nil,
                    title: ui("名义利率与实际利率", "Nominal and Real Interest Rates")
                )
                await waitForHTMLContentRailToSettle()
            } else {
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)

            let noteMarker = "# Pane continuity \(verificationCase.itemID) \(verificationCase.agentVisible ? "agent-on" : "agent-off")\n\nUncommitted note state must survive pane toggles.\n"
            updateNote(noteMarker)
            try? await Task.sleep(nanoseconds: 450_000_000)
            let itemID = selectedMaterialItem?.id
            let baselineRevision = agentContextRevision
            let baselineLocation = itemID.flatMap { studyLocationsByItemID[$0] }
            let baselineMessages = messages
            PaneToggleContinuityVerifier.beginMeasurement()

            for _ in 1...20 {
                toggleNotes()
                try? await Task.sleep(nanoseconds: 520_000_000)
                toggleNotes()
                try? await Task.sleep(nanoseconds: 520_000_000)
            }
            for _ in 1...20 {
                toggleReader()
                try? await Task.sleep(nanoseconds: 520_000_000)
                toggleReader()
                try? await Task.sleep(nanoseconds: 520_000_000)
            }
            if verificationCase.itemID == "sample-html" {
                await waitForHTMLContentRailToSettle()
            } else {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }

            let finalLocation = itemID.flatMap { studyLocationsByItemID[$0] }
            let revisionDelta = agentContextRevision &- baselineRevision
            let studyLocationChanged = baselineLocation != finalLocation
            let lifecycleStable = PaneToggleContinuityVerifier.webReaderMakeCount == 0
                && PaneToggleContinuityVerifier.webReaderDismantleCount == 0
                && PaneToggleContinuityVerifier.pdfReaderMakeCount == 0
                && PaneToggleContinuityVerifier.pdfReaderDismantleCount == 0
                && PaneToggleContinuityVerifier.noteEditorMakeCount == 0
                && PaneToggleContinuityVerifier.noteEditorDismantleCount == 0
            let exercisedResizeChain = verificationCase.itemID != "sample-html"
                || PaneToggleContinuityVerifier.htmlSectionEventCount > 0
            let casePassed = exercisedResizeChain
                && PaneToggleContinuityVerifier.htmlLocationCallCount == 0
                && PaneToggleContinuityVerifier.htmlLocationCommitCount == 0
                && revisionDelta == 0
                && !studyLocationChanged
                && lifecycleStable
                && noteText == noteMarker
                && messages == baselineMessages
                && normalizedThreePaneOrder == baselineOrder
                && showReader
                && showAgent == verificationCase.agentVisible
                && showNotes
            allPassed = allPassed && casePassed
            let caseName = "\(verificationCase.itemID)-agent-\(verificationCase.agentVisible ? "on" : "off")"
            let locationReasons = PaneToggleContinuityVerifier.htmlLocationReasons
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            caseReports.append([
                "case=\(caseName)",
                "case_result=\(casePassed ? "pass" : "fail")",
                "agent_revision_delta=\(revisionDelta)",
                "study_location_changed=\(studyLocationChanged)",
                "html_location_calls=\(PaneToggleContinuityVerifier.htmlLocationCallCount)",
                "html_location_commits=\(PaneToggleContinuityVerifier.htmlLocationCommitCount)",
                "html_location_reasons=\(locationReasons)",
                "web_reader_make=\(PaneToggleContinuityVerifier.webReaderMakeCount)",
                "web_reader_dismantle=\(PaneToggleContinuityVerifier.webReaderDismantleCount)",
                "pdf_reader_make=\(PaneToggleContinuityVerifier.pdfReaderMakeCount)",
                "pdf_reader_dismantle=\(PaneToggleContinuityVerifier.pdfReaderDismantleCount)",
                "markdown_editor_make=\(PaneToggleContinuityVerifier.noteEditorMakeCount)",
                "markdown_editor_dismantle=\(PaneToggleContinuityVerifier.noteEditorDismantleCount)",
                "note_preserved=\(noteText == noteMarker)",
                "conversation_preserved=\(messages == baselineMessages)",
                "pane_order_preserved=\(normalizedThreePaneOrder == baselineOrder)",
            ].joined(separator: " "))
            PaneToggleContinuityVerifier.endMeasurement()
        }

        let report = ([
            "result=\(allPassed ? "pass" : "fail")",
            "cases=\(cases.count)",
            "notes_cycles_per_case=20",
            "reader_cycles_per_case=20",
        ] + caseReports).joined(separator: "\n") + "\n"
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("pane-toggle-continuity-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("pane-toggle-result:\(allPassed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    /// Verifies pane geometry and reader continuity across stable layout measurements.
    func runPaneLayoutStabilityVerification() async {
        layout = .documentAgentNotes
        showLibrary = false
        showReader = true
        showAgent = false
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        await waitForHTMLContentRailToSettle()

        let noteMarker = "# Pane ownership marker\n\nUnsaved note input must survive stable slot animations.\n"
        let draftMarker = "Unsent agent draft must survive stable slot animations."
        let messageMarker = AgentMessage(
            role: .assistant,
            text: "Stable parent conversation marker",
            source: "verification",
            backend: .offline
        )
        updateNote(noteMarker)
        agentDraft = draftMarker
        messages = [messageMarker]
        try? await Task.sleep(nanoseconds: 700_000_000)

        let itemID = selectedMaterialItem?.id
        let baselineLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let baselineRevision = agentContextRevision
        let baselineOrder = normalizedThreePaneOrder
        PaneToggleContinuityVerifier.beginMeasurement()
        recordVerificationStage("pane-layout-context-prepared")

        toggleNotes()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleNotes()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleAgent()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleReader()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleReader()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleAgent()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleNotes()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleNotes()
        try? await Task.sleep(nanoseconds: 700_000_000)

        let finalLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let revisionDelta = agentContextRevision &- baselineRevision
        let passed = showReader
            && !showAgent
            && showNotes
            && noteText == noteMarker
            && agentDraft == draftMarker
            && messages == [messageMarker]
            && normalizedThreePaneOrder == baselineOrder
            && finalLocation == baselineLocation
            && revisionDelta == 0
            && PaneToggleContinuityVerifier.htmlLocationCallCount == 0
            && PaneToggleContinuityVerifier.webReaderMakeCount == 0
            && PaneToggleContinuityVerifier.webReaderDismantleCount == 0
            && PaneToggleContinuityVerifier.noteEditorMakeCount == 0
            && PaneToggleContinuityVerifier.noteEditorDismantleCount == 0
        let report = [
            "result=\(passed ? "pass" : "fail")",
            "transitions=8",
            "reader_visible=\(showReader)",
            "agent_visible=\(showAgent)",
            "notes_visible=\(showNotes)",
            "agent_revision_delta=\(revisionDelta)",
            "study_location_changed=\(finalLocation != baselineLocation)",
            "html_location_calls=\(PaneToggleContinuityVerifier.htmlLocationCallCount)",
            "web_reader_make=\(PaneToggleContinuityVerifier.webReaderMakeCount)",
            "web_reader_dismantle=\(PaneToggleContinuityVerifier.webReaderDismantleCount)",
            "note_editor_make=\(PaneToggleContinuityVerifier.noteEditorMakeCount)",
            "note_editor_dismantle=\(PaneToggleContinuityVerifier.noteEditorDismantleCount)",
            "note_preserved=\(noteText == noteMarker)",
            "agent_draft_preserved=\(agentDraft == draftMarker)",
            "conversation_preserved=\(messages == [messageMarker])",
            "pane_order_preserved=\(normalizedThreePaneOrder == baselineOrder)",
        ].joined(separator: "\n") + "\n"
        PaneToggleContinuityVerifier.endMeasurement()
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("pane-layout-stability-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("pane-layout-result:\(passed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    /// Verifies that drag reordering preserves pane width and workspace state.
    func runPaneReorderWidthVerification() async {
        layout = .documentAgentNotes
        showLibrary = false
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        await waitForHTMLContentRailToSettle()

        let noteMarker = "# Reorder and width marker\n\nUnsaved text must survive pane movement.\n"
        let draftMarker = "Unsent draft must survive pane movement."
        let messageMarker = AgentMessage(
            role: .assistant,
            text: "Reorder conversation marker",
            source: "verification",
            backend: .offline
        )
        updateNote(noteMarker)
        agentDraft = draftMarker
        messages = [messageMarker]

        for _ in 0..<30 {
            let order = visibleDocumentPaneOrder
            if order.count == 3, order.allSatisfy({ threePaneReorderFrames[$0] != nil }) {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let baselineOrder = normalizedThreePaneOrder
        let baselineRevision = agentContextRevision
        let itemID = selectedMaterialItem?.id
        let baselineLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let baselineAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0
        PaneToggleContinuityVerifier.beginMeasurement()
        recordVerificationStage("pane-reorder-width-context-prepared")

        requestPaneExpansion(.agent)
        for _ in 0..<20 {
            guard paneExpansionRequest != nil else { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        let expandedAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0

        beginThreePaneReorder(.reader)
        let dragDistance = max(
            (threePaneReorderFrames[.notes]?.midX ?? 1_000)
                - (threePaneReorderFrames[.reader]?.midX ?? 0),
            1_000
        )
        updateThreePaneReorder(.reader, horizontalDelta: dragDistance)
        finishThreePaneReorder(.reader, horizontalDelta: dragDistance)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let reorderedOrder = normalizedThreePaneOrder
        let reorderedAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0

        toggleAgent()
        try? await Task.sleep(nanoseconds: 520_000_000)
        toggleAgent()
        try? await Task.sleep(nanoseconds: 700_000_000)
        let restoredAgentWidth = threePaneReorderFrames[.agent]?.width ?? 0
        let restoredStore = WorkspaceStore()
        let persistedOrder = restoredStore.normalizedThreePaneOrder
        let widthTolerance = max(12, reorderedAgentWidth * 0.12)
        let finalLocation = itemID.flatMap { studyLocationsByItemID[$0] }
        let lifecycleStable = PaneToggleContinuityVerifier.webReaderMakeCount == 0
            && PaneToggleContinuityVerifier.webReaderDismantleCount == 0
            && PaneToggleContinuityVerifier.noteEditorMakeCount == 0
            && PaneToggleContinuityVerifier.noteEditorDismantleCount == 0
        let passed = baselineOrder != reorderedOrder
            && reorderedOrder.last == .reader
            && persistedOrder == reorderedOrder
            && paneExpansionRequest == nil
            && expandedAgentWidth >= ContentRailMetrics.readableWidth
            && reorderedAgentWidth >= ContentRailMetrics.readableWidth
            && abs(restoredAgentWidth - reorderedAgentWidth) <= widthTolerance
            && noteText == noteMarker
            && agentDraft == draftMarker
            && messages == [messageMarker]
            && finalLocation == baselineLocation
            && agentContextRevision == baselineRevision
            && lifecycleStable

        let report = [
            "result=\(passed ? "pass" : "fail")",
            "baseline_order=\(baselineOrder.map(\.rawValue).joined(separator: ","))",
            "reordered_order=\(reorderedOrder.map(\.rawValue).joined(separator: ","))",
            "persisted_order=\(persistedOrder.map(\.rawValue).joined(separator: ","))",
            "baseline_agent_width=\(baselineAgentWidth)",
            "expanded_agent_width=\(expandedAgentWidth)",
            "reordered_agent_width=\(reorderedAgentWidth)",
            "restored_agent_width=\(restoredAgentWidth)",
            "width_tolerance=\(widthTolerance)",
            "expansion_consumed=\(paneExpansionRequest == nil)",
            "note_preserved=\(noteText == noteMarker)",
            "agent_draft_preserved=\(agentDraft == draftMarker)",
            "conversation_preserved=\(messages == [messageMarker])",
            "study_location_changed=\(finalLocation != baselineLocation)",
            "agent_revision_delta=\(agentContextRevision &- baselineRevision)",
            "native_lifecycle_stable=\(lifecycleStable)",
        ].joined(separator: "\n") + "\n"
        PaneToggleContinuityVerifier.endMeasurement()
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("pane-reorder-width-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("pane-reorder-width-result:\(passed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    /// Verifies that reader scroll position survives reconstruction and workspace reload.
    func runReaderScrollPersistenceVerification() async {
        PaneToggleContinuityVerifier.beginMeasurement()
        layout = .documentAgentNotes
        showLibrary = true
        showReader = true
        showAgent = true
        showNotes = true
        agentSurface = .hidden
        select(itemID: "sample-html")
        await waitForHTMLContentRailToSettle()
        let baseline = studyLocationsByItemID["sample-html"]
        let previousScrollSchedules = PaneToggleContinuityVerifier.verificationScrollScheduleCount
        NotificationCenter.default.post(name: .weiBeiVerificationUserScroll, object: nil)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let didTriggerScroll = PaneToggleContinuityVerifier.verificationScrollScheduleCount > previousScrollSchedules
        recordVerificationStage("reader-scroll-context-prepared")

        var finalLocation = studyLocationsByItemID["sample-html"]
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            finalLocation = studyLocationsByItemID["sample-html"]
            if finalLocation?.locationID != nil,
               finalLocation?.locationID != baseline?.locationID {
                break
            }
        }
        save()
        try? await Task.sleep(nanoseconds: 250_000_000)
        let restoredStore = WorkspaceStore()
        let persisted = restoredStore.studyLocationsByItemID["sample-html"]
        let scrolled = finalLocation?.locationID != nil
            && finalLocation?.locationID != baseline?.locationID
            && finalLocation?.lastStudiedAt != baseline?.lastStudiedAt
        let restored = restoredStore.selectedItemID == "sample-html"
            && restoredStore.readerLocationID == finalLocation?.locationID
            && restoredStore.readerTargetLocationID == finalLocation?.locationID
            && persisted?.locationID == finalLocation?.locationID
            && persisted?.locationTitle == finalLocation?.locationTitle
        let passed = didTriggerScroll && scrolled && restored
        let locationReasons = PaneToggleContinuityVerifier.htmlLocationReasons
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let report = [
            "result=\(passed ? "pass" : "fail")",
            "input_path=dom-wheel-event",
            "verification_scroll_triggered=\(didTriggerScroll)",
            "baseline_location_id=\(baseline?.locationID ?? "")",
            "final_location_id=\(finalLocation?.locationID ?? "")",
            "final_location_title=\(finalLocation?.locationTitle ?? "")",
            "timestamp_changed=\(finalLocation?.lastStudiedAt != baseline?.lastStudiedAt)",
            "restored_location_id=\(restoredStore.readerLocationID ?? "")",
            "restored_target_id=\(restoredStore.readerTargetLocationID ?? "")",
            "html_section_events=\(PaneToggleContinuityVerifier.htmlSectionEventCount)",
            "html_active_events=\(PaneToggleContinuityVerifier.htmlActiveEventCount)",
            "html_location_calls=\(PaneToggleContinuityVerifier.htmlLocationCallCount)",
            "html_location_reasons=\(locationReasons)",
            "verification_scroll_schedules=\(PaneToggleContinuityVerifier.verificationScrollScheduleCount)",
            "verification_scroll_result=\(PaneToggleContinuityVerifier.verificationScrollResult)",
        ].joined(separator: "\n") + "\n"
        PaneToggleContinuityVerifier.endMeasurement()
        let reportURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("reader-scroll-persistence-report.txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        recordVerificationStage("reader-scroll-result:\(passed ? "pass" : "fail")")
        recordVerificationStage("completed")
    }

    private func waitForHTMLContentRailToSettle() async {
        var previousEventCount = PaneToggleContinuityVerifier.htmlEventSequence
        var stableChecks = 0
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let currentEventCount = PaneToggleContinuityVerifier.htmlEventSequence
            if currentEventCount == previousEventCount {
                stableChecks += 1
                if stableChecks >= 4 { return }
            } else {
                previousEventCount = currentEventCount
                stableChecks = 0
            }
        }
    }

}
