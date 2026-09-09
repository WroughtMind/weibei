#if CHAT_RENDERER_LAB
import AppKit
import ChatRendererKit
import Litext
import SwiftUI
import WeiBeiCore

/// Checks the same host and bubbles shipped in the candidate. Hidden windows
/// exercise layout and state; they do not establish trackpad smoothness or FPS.
@MainActor
enum ChatRendererConversationChecks {
    struct Failure: Error { let message: String }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func settle(_ list: ChatRendererListView) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        var stable = 0, previous: CGFloat = -1
        while stable < 3 {
            list.layoutSubtreeIfNeeded()
            list.flushHeightChanges()
            let ready = list.session.messages.values.allSatisfy {
                $0.document.displayedRevision == $0.document.requestedRevision
            }
            if ready, list.table.bounds.height == previous { stable += 1 } else { stable = 0 }
            previous = list.table.bounds.height
            try require(ProcessInfo.processInfo.systemUptime < deadline, "List geometry/preparation did not settle")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    static func dumpGeometry(_ list: ChatRendererListView) {
        func inspect(_ view: NSView) {
            if let text = view as? CandidateTextView {
                print("TEXT frame=\(text.frame) length=\(text.textLabelView.attributedText.length) lines=\(text.textLabelView.layoutRuns(matching: .font).count) heights=\(text.preparedDocument?.measuredHeights ?? [:])")
            }
            for child in view.subviews { inspect(child) }
        }
        list.table.enumerateAvailableRowViews { row, index in
            print("ROW \(index): \(row.frame)"); inspect(row)
        }
    }
    static func run(store: WorkspaceStore, directory: URL) async {
        var checks: [[String: Any]] = [], measurements: [[String: Any]] = []
        let session = ChatRendererSession()
        let list = ChatRendererListView(session: session)
        list.frame = NSRect(x: 0, y: 0, width: 680, height: 560)
        let window = NSWindow(contentRect: list.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = list
        var fontScale: CGFloat = 1
        list.makeRow = { message in
            AnyView(AgentMessageBubble(message: message, streaming:
                message.completionState == .generating || store.agentStreaming.isDisplaying(message.id)
                    ? store.agentStreaming : AgentStreamingState(), isChatWideTypography: true)
                .environmentObject(store)
                .environment(\.weiBeiTextScale, fontScale)
                .environment(\.agentChatLayoutWidth, CGFloat(656))
                .id(message.id))
        }
        var previousTick = ProcessInfo.processInfo.systemUptime
        var delays: [Double] = []
        let timer = Timer.scheduledTimer(withTimeInterval: 0.008, repeats: true) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            delays.append(max(0, (now - previousTick - 0.008) * 1_000)); previousTick = now
        }
        func runCase(_ name: String, _ body: () async throws -> Void) async {
            let start = ProcessInfo.processInfo.systemUptime
            do { try await body(); checks.append(["name": name, "passed": true]) }
            catch { checks.append(["name": name, "passed": false, "detail": String(describing: error)]) }
            print("CHECK \(name): \(checks.last!)"); fflush(stdout)
            measurements.append(["phase": name, "elapsed_ms": (ProcessInfo.processInfo.systemUptime - start) * 1_000])
        }
        await runCase("cold_history_and_warm_revisit") {
            ChatRendererExperiment.open(ChatRendererExperiment.scenarioTitles[0], store: store)
            let firstOpen = ProcessInfo.processInfo.systemUptime
            list.update(sessionID: store.activeStudySessionID, messages: store.messages)
            try await settle(list)
            measurements.append(["phase": "first_history_open_to_settled_geometry", "elapsed_ms": (ProcessInfo.processInfo.systemUptime - firstOpen) * 1_000])
            try require(session.messages.values.contains { $0.document.content != nil }, "No real message body was prepared")
            try require(session.messages.values.filter { $0.document.content != nil }.count < store.messages.count,
                "First open eagerly prepared the entire history")
            // Keyboard and accessibility scrolling changes the clip position
            // without a scroll-wheel event. Later layout must not undo it.
            let readingY = list.scroll.contentView.bounds.minY - 180
            list.scroll.contentView.scroll(to: CGPoint(x: 0, y: readingY))
            list.scroll.reflectScrolledClipView(list.scroll.contentView)
            try require(!list.followsLatest, "Reading history without a wheel event still followed the tail")
            guard let readingAnchor = list.captureAnchor() else { throw Failure(message: "No reading anchor after keyboard/accessibility scrolling") }
            if let last = store.messages.last { list.enqueueHeightChange(last.id) }
            try await settle(list)
            guard let afterScroll = list.captureAnchor() else { throw Failure(message: "Layout lost the reading anchor") }
            // Newly exposed rows can replace estimated heights above the viewport.
            // Preserve the reading location, even when the document coordinate changes.
            try require(!list.followsLatest && afterScroll.id == readingAnchor.id
                && afterScroll.character == readingAnchor.character
                && abs(afterScroll.rowOffset - readingAnchor.rowOffset) <= 1
                && abs(afterScroll.characterOffset - readingAnchor.characterOffset) <= 1,
                "Layout moved keyboard/accessibility reading: \(readingAnchor) -> \(afterScroll)")
            let ids = Array(store.messages.suffix(40).map(\.id))
            for id in ids.reversed().prefix(12) { list.reveal(id); try await settle(list) }
            let prepared = session.messages.mapValues { $0.document.parseCount }
            let warmStart = ProcessInfo.processInfo.systemUptime
            for id in ids.reversed().prefix(12) { list.reveal(id); try await settle(list) }
            measurements.append(["phase": "warm_history_revisit_to_settled_geometry", "elapsed_ms": (ProcessInfo.processInfo.systemUptime - warmStart) * 1_000])
            for (id, count) in prepared {
                try require(session.state(for: id).document.parseCount == count, "Unchanged revisited message was parsed again")
            }
            let anchor = list.captureAnchor()
            list.loadEarlier(); try await settle(list)
            let after = list.captureAnchor()
            try require(anchor?.id == after?.id, "History insertion changed the reading message: \(String(describing: anchor)) -> \(String(describing: after))")
            if let a = anchor, let b = after {
                try require(abs(a.rowOffset - b.rowOffset) <= 1, "History insertion moved the reading location")
            }
        }
        await runCase("long_message_width_preserves_text_anchor") {
            ChatRendererExperiment.open(ChatRendererExperiment.scenarioTitles[1], store: store)
            list.update(sessionID: store.activeStudySessionID, messages: store.messages)
            let id = store.messages[1].id
            list.reveal(id); try await settle(list)
            list.scroll.contentView.scroll(to: NSPoint(x: 0, y: list.scroll.contentView.bounds.minY + 2_000))
            list.scroll.reflectScrolledClipView(list.scroll.contentView)
            try await settle(list)
            let before = list.captureAnchor()
            print("LONG clip \(list.scroll.contentView.bounds) table \(list.table.bounds) anchor \(String(describing: before))"); dumpGeometry(list); fflush(stdout)
            try require(before?.id == id && before?.character != nil, "No text anchor inside the long answer")
            let parseCount = session.state(for: id).document.parseCount
            let wideHeight = session.state(for: id).lastHeight
            let wideBodyWidths = Set(session.state(for: id).document.measuredHeights.keys)
            list.setFrameSize(NSSize(width: 440, height: 560))
            try await settle(list)
            let after = list.captureAnchor()
            print("NARROW clip \(list.scroll.contentView.bounds) anchor \(String(describing: after)); before \(String(describing: before))"); dumpGeometry(list); fflush(stdout)
            try require(session.state(for: id).lastHeight > wideHeight, "Narrow pane did not actually reflow the long answer")
            try require(Set(session.state(for: id).document.measuredHeights.keys) != wideBodyWidths, "Body kept the previous width")
            try require(before?.id == after?.id && before?.character == after?.character,
                "Width change did not preserve the anchored text")
            try require(session.state(for: id).document.parseCount == parseCount, "Width change reparsed the long source")
            list.setFrameSize(NSSize(width: 680, height: 560)); try await settle(list)
            let fontAnchor = list.captureAnchor()
            let regularHeight = session.state(for: id).lastHeight
            fontScale = 1.15
            list.update(sessionID: store.activeStudySessionID, messages: store.messages, presentationID: "font-1.15")
            try await settle(list)
            try require(session.state(for: id).lastHeight > regularHeight, "Font increase did not reach existing rows")
            try require(list.captureAnchor()?.id == fontAnchor?.id, "Font change moved to another message")
            fontScale = 1
            list.update(sessionID: store.activeStudySessionID, messages: store.messages, presentationID: "font-1")
            try await settle(list)
        }
        await runCase("rebind_selection_and_attachment_release") {
            let surfaceSession = ChatRendererSession(), surfaceID = UUID(), conversationID = UUID()
            let original = surfaceSession.surface(for: surfaceID, in: conversationID)
            let originalHost = NSView()
            originalHost.addSubview(original)
            let replacement = surfaceSession.surface(for: surfaceID, in: conversationID)
            try require(replacement !== original && original.superview === originalHost,
                "Replacing a row stole its still-mounted body from the previous host")
            try require(surfaceSession.surface(for: surfaceID, in: conversationID) === replacement,
                "Detached body was not available for reuse")
            weak var retained: TextLabel.Attachment?
            autoreleasepool {
                let attachment = TextLabel.Attachment(); retained = attachment
                _ = attachment.attributedString()
            }
            try require(retained == nil, "CoreText attachment retains itself after its string is released")
            let sharedID = UUID()
            let a = session.state(for: sharedID, in: UUID()).document
            let b = session.state(for: sharedID, in: UUID()).document
            let view = CandidateTextView()
            try require(a !== b, "Two conversations shared a document with the same message ID")
            view.bind(a)
            a.submit("旧消息 " + LabSamples.longAnswer)
            b.submit("新的消息：甲乙丙丁")
            while b.displayedRevision != b.requestedRevision { try await Task.sleep(for: .milliseconds(10)) }
            b.selectedRange = NSRange(location: 6, length: 2)
            view.bind(b)
            try require(view.textLabelView.attributedText.string.contains("甲乙丙丁"), "Rebinding did not install new baseline")
            try require(view.textLabelView.selectionRange == b.selectedRange, "Old selection contaminated the new message")
            while a.displayedRevision != a.requestedRevision { try await Task.sleep(for: .milliseconds(10)) }
            try require(view.preparedDocument === b && view.textLabelView.attributedText.string.contains("甲乙丙丁"),
                "Old async result wrote into the reused view")
            b.submit("新的消息：甲乙丙丁，末尾🙂")
            while b.displayedRevision != b.requestedRevision { try await Task.sleep(for: .milliseconds(10)) }
            try require(view.textLabelView.selectionRange == NSRange(location: 6, length: 2), "Append lost the existing selection")
            view.bind(a)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
            view.frame = NSRect(x: 0, y: 0, width: 640, height: view.measuredHeight(for: 640))
            scroll.documentView = view
            let selectionWindow = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
            selectionWindow.contentView = scroll
            view.layoutSubtreeIfNeeded()
            let edge = view.textLabelView.convert(CGPoint(x: 10, y: scroll.documentVisibleRect.maxY + 40), from: view)
            view.textLabelView(view.textLabelView, didDragSelectionAt: edge)
            try require(scroll.documentVisibleRect.minY > 0, "Dragging selection beyond the viewport did not scroll the enclosing conversation")
            selectionWindow.contentView = nil
            view.unbind()
        }
        await runCase("stream_stop_and_final_tail_use_real_store") {
            // Keep the real SwiftUI message projection mounted while the request
            // and display pump change state; the bare list cannot catch a reply
            // accidentally added twice by its parent.
            let pane = NSHostingView(rootView: AgentPaneView(showsPaneHeader: false)
                .environmentObject(store).environmentObject(store.paneState).environmentObject(store.interaction))
            let paneWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 741, height: 640),
                styleMask: [.titled], backing: .buffered, defer: false)
            paneWindow.contentView = pane
            defer { paneWindow.contentView = nil }
            pane.layoutSubtreeIfNeeded()
            func findList(_ view: NSView) -> ChatRendererListView? {
                if let list = view as? ChatRendererListView { return list }
                for child in view.subviews { if let list = findList(child) { return list } }
                return nil
            }
            guard let paneList = findList(pane) else { throw Failure(message: "Real conversation pane did not mount its list") }
            paneList.reveal(store.messages[1].id); try await settle(paneList)
            let paneReading = paneList.captureAnchor(), paneReloads = paneList.fullReloadCount
            let reading = list.captureAnchor()
            ChatRendererExperiment.replay(store: store)
            let run = store.agentRun
            list.update(sessionID: store.activeStudySessionID, messages: store.messages)
            let reloads = list.fullReloadCount
            while run.latestAgentStreamingText.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
            let received = run.latestAgentStreamingText
            store.cancelAgentRequest(restoreDraft: false)
            await run.agentStopTask?.value
            try require(store.messages.last?.completionState == .interrupted && store.messages.last?.text == received,
                "Stopping lost received characters or failed to finish the run")
            ChatRendererExperiment.replay(store: store)
            let finalRun = store.agentRun
            list.update(sessionID: store.activeStudySessionID, messages: store.messages)
            await finalRun.agentRequestTask?.value
            let inputFinished = ProcessInfo.processInfo.systemUptime
            while finalRun.pump.isRunning {
                try require(ProcessInfo.processInfo.systemUptime - inputFinished < 30, "Completed stream did not drain its display queue")
                try await Task.sleep(for: .milliseconds(20))
            }
            try require(finalRun.streaming.text == LabSamples.rich && finalRun.streaming.displayingMessageID == nil,
                "Natural stream completion did not display the final characters")
            measurements.append(["phase": "input_finished_to_final_display_queue_drained", "elapsed_ms":
                (ProcessInfo.processInfo.systemUptime - inputFinished) * 1_000])
            list.update(sessionID: store.activeStudySessionID, messages: store.messages)
            try await settle(list)
            try await settle(paneList)
            try require(paneList.numberOfRows(in: paneList.table) == store.messages.count + 1,
                "The real pane duplicated or dropped the displayed reply")
            try require(paneList.fullReloadCount == paneReloads && paneList.captureAnchor()?.id == paneReading?.id,
                "The real pane reloaded or left history during streaming")
            try require(store.messages.last?.text == LabSamples.rich && store.messages.last?.completionState == .completed,
                "Completed stream lost the authoritative final snapshot")
            try require(list.fullReloadCount == reloads, "Streaming replaced the whole message list")
            try require(list.captureAnchor()?.id == reading?.id, "Tail growth pulled the reader away from history")
            if let reading, let after = list.captureAnchor() {
                try require(abs(reading.rowOffset - after.rowOffset) <= 1, "Tail growth moved the history reading location")
            }
        }
        await runCase("action_draft_and_actual_write_undo") {
            ChatRendererExperiment.open(ChatRendererExperiment.scenarioTitles[2], store: store)
            list.update(sessionID: store.activeStudySessionID, messages: store.messages)
            try await settle(list)
            guard let message = store.messages.last, let action = message.actions.first else { throw Failure(message: "No real action card") }
            @MainActor func mermaid(in view: NSView) -> NativeChatAttachmentView? {
                if let native = view as? NativeChatAttachmentView,
                   case .code(_, "mermaid") = native.attachment.descriptor { return native }
                for child in view.subviews { if let native = mermaid(in: child) { return native } }
                return nil
            }
            guard let diagram = mermaid(in: list) else { throw Failure(message: "No mounted Mermaid attachment") }
            let previousAppearance = store.appearanceMode
            store.setAppearanceMode(previousAppearance.isDark ? .paper : .inkstone)
            try await settle(list)
            try require(mermaid(in: list) === diagram && diagram.attachment.isDark == store.appearanceMode.isDark,
                "Mermaid appearance: retained=\(mermaid(in: list) === diagram), actualDark=\(diagram.attachment.isDark), expectedDark=\(store.appearanceMode.isDark)")
            store.setAppearanceMode(previousAppearance)
            try await settle(list)
            guard let targetID = action.targetItemID, let notePath = store.item(withID: targetID)?.urlPath else {
                throw Failure(message: "No actual note file for the action")
            }
            let noteURL = URL(fileURLWithPath: notePath)
            let beforeNote = try String(contentsOf: noteURL, encoding: .utf8)
            let state = session.state(for: message.id)
            guard let draft = state.actionDrafts[action.id] else { throw Failure(message: "Action card did not bind its retained draft") }
            draft.bodyText = "编辑后保留的草稿"
            list.reveal(store.messages[0].id); try await settle(list)
            list.scrollToBottom(); try await settle(list)
            try require(state.actionDrafts[action.id] === draft && draft.bodyText == "编辑后保留的草稿", "Revisit lost the edited action draft")
            await store.confirmAgentReplyAction(messageID: message.id, actionID: action.id, proposedMarkdown: "## 验证\n\n" + draft.bodyText)
            try require(store.messages.last?.actions.first?.state == .executed, "Real note action did not complete")
            let saved = try String(contentsOf: noteURL, encoding: .utf8)
            try require(saved.contains(draft.bodyText) && saved != beforeNote, "Executed action did not write the edited proposal to the note")
            await store.undoAgentReplyAction(messageID: message.id, actionID: action.id)
            try require(store.messages.last?.actions.first?.state == .cancelled, "Real note action did not undo")
            let restored = try String(contentsOf: noteURL, encoding: .utf8)
            try require(restored == beforeNote, "Undo did not restore the original note file")
        }
        timer.invalidate()
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let documents = session.preparedDocuments
        let timings = documents.flatMap(\.timings) + list.timings
        let report: [String: Any] = ["scope": "Release real conversation host; hidden window; no FPS claim",
            "checks": checks, "phases": measurements, "font_size": 16, "initial_row_width": 656,
            "list_full_reloads": list.fullReloadCount, "changed_rows": list.updatedRowCount,
            "parse_count": documents.reduce(0) { $0 + $1.parseCount }, "peak_rss_bytes": usage.ru_maxrss,
            "main_timer_lateness_ms": ["max": delays.max() ?? 0, "over_16_count": delays.filter { $0 > 16 }.count],
            "timings": timings.map { ["operation": $0.operation, "ms": $0.milliseconds, "revision": $0.revision] },
            "unverified": ["User trackpad acceptance", "FPS and compositor hitches", "Live provider credentials and requests"]]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("conversation-report.json"))
        } catch {
            WeiBeiLog.workspace.error("code=chat_renderer_report_failed underlying=\(WeiBeiLog.code(error), privacy: .public)")
        }
        window.contentView = nil
        NSApp.terminate(nil)
    }
}
#endif
