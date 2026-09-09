#if CHAT_RENDERER_LAB
import AppKit
import ChatRendererKit
import CoreText
import Litext
import MarkdownView
import SwiftUI
import WebKit
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
            guard let content = session.state(for: id).document.content else { throw Failure(message: "Long answer body missing") }
            try require(!content.rendered.isEmpty && content.rendered.values.allSatisfy { $0.image != nil },
                "Packaged formula resources did not produce rendered images")
            let codeKeys = content.blocks.compactMap { block -> Int? in
                guard case let .codeBlock(language, source) = block else { return nil }
                return CodeHighlighter.current.key(for: source, language: language)
            }
            try require(!codeKeys.isEmpty, "Long answer has no code to verify highlighting")
            let highlightDeadline = ProcessInfo.processInfo.systemUptime + 10
            while !codeKeys.allSatisfy({ CodeHighlighter.current.renderCache.value(forKey: $0)?.isEmpty == false }) {
                try require(ProcessInfo.processInfo.systemUptime < highlightDeadline, "Packaged code highlighting did not finish")
                try await Task.sleep(for: .milliseconds(20))
            }
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
            let sweepAnchor = list.captureAnchor()
            for width in Array(stride(from: 656, through: 440, by: -24)) + Array(stride(from: 464, through: 680, by: 24)) {
                list.setFrameSize(NSSize(width: CGFloat(width), height: 560))
                list.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            try await settle(list)
            try require(list.captureAnchor()?.id == sweepAnchor?.id && list.captureAnchor()?.character == sweepAnchor?.character,
                "Continuous width changes lost the reading text")
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
            @MainActor func webView(in view: NSView) -> WKWebView? {
                if let web = view as? WKWebView { return web }
                return view.subviews.lazy.compactMap { webView(in: $0) }.first
            }
            @MainActor func checkDiagramTheme() async throws {
                guard let web = webView(in: diagram) else { throw Failure(message: "Mermaid has no web presentation") }
                let deadline = ProcessInfo.processInfo.systemUptime + 20
                while true {
                    let result = try? await web.evaluateJavaScript("""
                        (() => {
                          const render = document.querySelector('.weibei-mermaid-render[data-rendered="true"]');
                          const svg = render?.querySelector('svg');
                          if (!svg) return false;
                          return getComputedStyle(render).backgroundColor === 'rgba(0, 0, 0, 0)'
                            && getComputedStyle(svg).backgroundColor === 'rgba(0, 0, 0, 0)'
                            && getComputedStyle(render).opacity === '1';
                        })()
                        """)
                    if result as? Bool == true { return }
                    try require(ProcessInfo.processInfo.systemUptime < deadline, "Rendered Mermaid retained an opaque or dimmed preview")
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
            try await checkDiagramTheme()
            let previousAppearance = store.appearanceMode
            store.setAppearanceMode(previousAppearance.isDark ? .paper : .inkstone)
            try await settle(list)
            try require(mermaid(in: list) === diagram && diagram.attachment.isDark == store.appearanceMode.isDark,
                "Mermaid appearance: retained=\(mermaid(in: list) === diagram), actualDark=\(diagram.attachment.isDark), expectedDark=\(store.appearanceMode.isDark)")
            try await checkDiagramTheme()
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
        await runCase("conversation_styles_preserve_content") {
            let source = #"""
            # 一层标题
            ## 二层标题
            ### 三层标题
            #### 四层标题
            ##### 五层标题
            ###### 六层标题

            正文 *Italic 斜体*、***Bold italic***、==高亮文字==、^[脚注文字]。

            $$\boxed{\sum_{i=1}^{n} i = \frac{n(n+1)}{2}}\quad\text{中文}$$

            > ## 引用标题
            >
            > ```swift
            > let quotedCode = 1
            > ```
            >
            > | 表头 | 数值 |
            > | --- | --- |
            > | 内容 | 42 |

            ![[style-image.png|图片说明]]
            """# + "\n\n$$" + (1...80).map { "a_{\($0)}" }.joined(separator: " + ") + "$$\n\n$$\\unsupportedStyleProbe{x}$$"
            let document = CandidateDocument(), surface = CandidateTextView()
            document.configure(fontSize: 16, ink: WeiBeiNativePalette.ink(), secondaryInk: WeiBeiNativePalette.secondaryInk(),
                accent: WeiBeiNativePalette.link(), paper: WeiBeiNativePalette.paperRaised(), separator: WeiBeiNativePalette.hairline(),
                selection: WeiBeiNativePalette.selectionFill())
            surface.bind(document)
            let revision = document.submit(source)
            let deadline = ProcessInfo.processInfo.systemUptime + 20
            while document.displayedRevision < revision {
                try require(ProcessInfo.processInfo.systemUptime < deadline, "Style content did not prepare")
                try await Task.sleep(for: .milliseconds(20))
            }
            let height = surface.measuredHeight(for: 640)
            surface.frame = NSRect(x: 0, y: 0, width: 640, height: height)
            window.contentView = surface
            surface.layoutSubtreeIfNeeded()
            let text = surface.textLabelView.attributedText
            let glyphRuns = surface.textLabelView.layoutRuns(matching: .font)
            let lineRuns = surface.textLabelView.layoutRuns(matching: .font, includesGlyphBounds: false)
            try require(!lineRuns.isEmpty && lineRuns.count == glyphRuns.count
                && zip(lineRuns, glyphRuns).allSatisfy {
                    $0.stringRange == $1.stringRange && $0.lineRect == $1.lineRect
                }, "Reading positions changed when skipping unused glyph bounds")
            @MainActor func attributes(_ sample: String) throws -> [NSAttributedString.Key: Any] {
                let range = (text.string as NSString).range(of: sample)
                try require(range.location != NSNotFound, "Rendered style content missing: \(sample)")
                return text.attributes(at: range.location, effectiveRange: nil)
            }
            let headings = try ["一层", "二层", "三层", "四层", "五层", "六层"].map {
                (try attributes($0)[.font] as? NSFont)?.pointSize ?? 0
            }
            try require(zip(headings, headings.dropFirst()).allSatisfy { $0 > $1 } && headings.last == 16,
                "Heading levels did not keep the body-relative hierarchy")
            let bodyFont = try attributes("正文")[.font] as! NSFont
            let headingFont = try attributes("一层")[.font] as! NSFont
            try require(CTFontCopyFamilyName(headingFont as CTFont) == CTFontCopyFamilyName(bodyFont as CTFont)
                && CTFontGetSymbolicTraits(headingFont as CTFont).contains(.traitBold),
                "Heading resize substituted a different Chinese typeface or lost bold")
            let italic = try attributes("Italic"), boldItalic = try attributes("Bold italic")
            try require((italic[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true
                && italic[.underlineStyle] == nil, "Emphasis is not italic")
            let chineseRange = (text.string as NSString).range(of: "斜体")
            let chineseLine = CTLineCreateWithAttributedString(text.attributedSubstring(from: chineseRange))
            let chineseRuns = CTLineGetGlyphRuns(chineseLine) as! [CTRun]
            try require(chineseRuns.allSatisfy { run in
                let attributes = CTRunGetAttributes(run) as! [String: Any]
                let font = attributes[kCTFontAttributeName as String] as! CTFont
                return CTFontCopyFamilyName(font) == CTFontCopyFamilyName(bodyFont as CTFont)
                    && (CTFontGetSymbolicTraits(font).contains(.traitItalic) || CTRunGetTextMatrix(run).c > 0)
            }, "Font substitution removed the actual Chinese italic glyph slant")
            try require((boldItalic[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains([.italic, .bold]) == true,
                "Nested emphasis lost bold or italic")
            try require(try attributes("高亮文字")[.backgroundColor] != nil, "Highlight lost its background")
            try require(!text.string.contains("^[") && !text.string.contains("=="), "Extension markers leaked into prose")
            var embedded: [NSView] = []
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
                for case let view as NSView in attributes.values where !embedded.contains(where: { $0 === view }) {
                    embedded.append(view)
                }
            }
            try require(embedded.count == 2,
                "Quoted code or table was flattened")
            try require(embedded.allSatisfy {
                $0.convert($0.bounds, to: surface).maxX <= surface.bounds.maxX + 1
            }, "Quoted rich content extends past the text column")
            try require(document.attachments.values.contains(.image(source: "style-image.png", alt: "图片说明")),
                "Wiki image turned into a note link")
            try require(document.attachments.values.contains { if case .math = $0 { return true }; return false },
                "Display math lost its block presentation")
            @MainActor func pictures(in view: NSView) -> [NSImageView] {
                (view as? NSImageView).map { [$0] } ?? view.subviews.flatMap { pictures(in: $0) }
            }
            guard let wideFormula = pictures(in: surface).first(where: { ($0.image?.size.width ?? 0) > surface.bounds.width }),
                  let horizontal = wideFormula.enclosingScrollView else { throw Failure(message: "Long formula lost horizontal viewing") }
            try require(wideFormula.imageScaling == .scaleNone && horizontal.hasHorizontalScroller,
                "Long formula was shrunk or clipped instead of horizontally scrollable")
            horizontal.contentView.scroll(to: NSPoint(x: 80, y: 0))
            try require(horizontal.contentView.bounds.minX > 0, "Long formula could not scroll horizontally")
            let failedFormula = pictures(in: surface).first { $0.image == nil && $0.enclosingScrollView != nil }
            let failureCaption = failedFormula?.enclosingScrollView?.superview?.subviews.compactMap { $0 as? NSTextField }.first
            try require(failureCaption?.isHidden == false && failureCaption?.stringValue.contains(#"\unsupportedStyleProbe"#) == true,
                "Unsupported formula silently disappeared instead of keeping readable source")
            surface.textLabelView.selectAll()
            let copied = surface.textLabelView.selectedPlainText() ?? ""
            try require(copied.contains(#"\boxed"#) && copied.contains("quotedCode") && copied.contains("42"),
                "Selecting and copying lost formula, quoted code or table content")
            surface.textLabelView.clearSelection()
            if let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds) {
                surface.cacheDisplay(in: surface.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("style-content.png"))
            }
            let emptyList = ChatRendererListView(session: ChatRendererSession())
            let emptyHistory = emptyList.tableView(emptyList.table, viewFor: nil, row: 0)
            try require(emptyHistory?.isHidden == true, "Empty conversation drew a history button")
        }
        await runCase("math_highlight_reuses_unchanged_body") {
            let document = CandidateDocument(), surface = CandidateTextView()
            surface.bind(document)
            let apply = document.onApply
            var preparations = 0
            var before = NSAttributedString()
            document.onApply = { content, revision in
                apply?(content, revision)
                preparations = document.inlinePreparationCount
                before = surface.textLabelView.attributedText.copy() as! NSAttributedString
            }
            defer { document.onApply = apply }
            let source = "## 缓存标题\n\n*斜体* 正文 $x$\n\n```swift\nlet value = 451\n```"
            @MainActor func display(_ source: String) async throws {
                let revision = document.submit(source)
                let deadline = ProcessInfo.processInfo.systemUptime + 10
                while document.displayedRevision < revision {
                    try require(ProcessInfo.processInfo.systemUptime < deadline, "Math body did not prepare")
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
            try await display(source)
            let formula = document.content?.rendered.values.first?.image
            guard let key = document.content?.blocks.compactMap({ block -> Int? in
                if case let .codeBlock(language, code) = block {
                    return CodeHighlighter.current.key(for: code, language: language)
                }
                return nil
            }).first else { throw Failure(message: "No code highlight to check") }
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while CodeHighlighter.current.renderCache.value(forKey: key)?.isEmpty != false {
                try require(ProcessInfo.processInfo.systemUptime < deadline, "Code highlighting did not finish")
                try await Task.sleep(for: .milliseconds(20))
            }
            try require(document.inlinePreparationCount == preparations,
                "Highlight completion prepared unchanged math-bearing prose again")
            // The code block replaces its attachment when colors arrive. Compare the
            // entire prose, including its inline formula, without that code attachment.
            let prose = NSRange(location: 0, length: (before.string as NSString)
                .range(of: TextLabel.Attachment.replacementText, options: .backwards).location)
            let after = surface.textLabelView.attributedText
            try require(after.string == before.string
                && after.attributedSubstring(from: prose).isEqual(to: before.attributedSubstring(from: prose)),
                "Reusing math-bearing prose changed its text or style")
            try await display(source.replacingOccurrences(of: "$x$", with: "$y^2$"))
            try require(document.content?.rendered.values.first?.image !== formula,
                "Changed formula reused an outdated rendered image")
            surface.textLabelView.selectAll()
            let copied = surface.textLabelView.selectedPlainText() ?? ""
            try require(copied.contains("y^2") && copied.contains("let value = 451"),
                "Changed formula or highlighted code lost copied content")
            surface.textLabelView.clearSelection()
        }
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
