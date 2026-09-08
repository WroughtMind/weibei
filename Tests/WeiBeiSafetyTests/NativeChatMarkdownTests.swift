import AppKit
import SwiftUI
import WeiBeiCore
import XCTest
@testable import WeiBei

final class NativeChatMarkdownTests: XCTestCase {
    // Continuous input must publish the already completed answer, then the latest snapshot.
    @MainActor func testPendingInputDoesNotStarveDisplay() async {
        let pipeline = NativeChatMarkdownPipeline()
        let started = expectation(description: "first parse started")
        let applied = expectation(description: "both snapshots displayed")
        applied.expectedFulfillmentCount = 2
        let gate = DispatchSemaphore(value: 0)
        let first = "中文 **回答** 和 $x^2$"
        let final = first + "\n\n最后一句。"
        pipeline.parse = { snapshot in
            if snapshot.markdown == first { started.fulfill(); gate.wait() }
            return NativeChatMarkdownParser.parse(snapshot.markdown)
        }
        var observed: [String] = []
        var visible = ""
        pipeline.onApply = { document, edit in
            let updated = NSMutableString(string: visible)
            updated.replaceCharacters(in: edit.range, with: edit.replacement.map(\.text).joined())
            visible = updated as String
            XCTAssertEqual(visible, document.text)
            observed.append(document.text)
            applied.fulfill()
        }
        let identity = UUID()
        pipeline.submit(.init(markdown: first, messageID: identity))
        await fulfillment(of: [started], timeout: 3)
        pipeline.submit(.init(markdown: first + "\n\n最后", messageID: identity))
        pipeline.submit(.init(markdown: final, messageID: identity))
        gate.signal()
        await fulfillment(of: [applied], timeout: 3)
        XCTAssertEqual(observed, [NativeChatMarkdownParser.parse(first).text, NativeChatMarkdownParser.parse(final).text])
    }

    // Rich syntax remains rich, while the same syntax inside code stays literal.
    func testRichContentAndCodeRemainDistinct() {
        let source = """
        # 标题
        中文 **重点**，[[笔记|别名]]，![[嵌入笔记]]，==标注==，^[补充]，$x^2$。

        **结尾。**继续，已有**“引用”**后文，**范围更广 **，后文。

        来源：资料名

        ```swift
        let value = "$x$ and [[literal]] **结尾。**继续"
        ```

        | 左 | 右 |
        | :--- | ---: |
        | **粗体** | $y$ |

        > [!note]- 标题
        > 收起的内容
        """
        let document = NativeChatMarkdownParser.parse(source)
        XCTAssertTrue(document.runs.contains { $0.style.bold && $0.text == "重点" })
        for text in ["结尾。", "“引用”", "范围更广"] {
            XCTAssertTrue(document.runs.contains { $0.style.bold && $0.text == text }, "Missing bold span: \(text); parsed: \(document.runs.filter { $0.style.bold }.map(\.text))")
        }
        XCTAssertTrue(document.runs.contains { $0.style.link?.hasPrefix("weibei-note:") == true })
        XCTAssertTrue(document.runs.contains { $0.text == "嵌入笔记" && $0.style.link?.hasPrefix("weibei-note:") == true })
        XCTAssertTrue(document.runs.contains { $0.text == "来源：资料名" && $0.style.link?.hasPrefix("weibei-source:") == true })
        XCTAssertTrue(document.runs.contains { $0.attachment == .math(latex: "x^2", display: false) })
        XCTAssertTrue(document.runs.contains {
            if case let .code(source, _) = $0.attachment { return source.contains("$x$ and [[literal]] **结尾。**继续") }
            return false
        })
        XCTAssertTrue(document.runs.contains {
            if case let .table(headers, rows, alignments) = $0.attachment {
                return headers.count == 2 && rows.count == 1 && alignments == ["left", "right"]
            }
            return false
        })
        XCTAssertFalse(document.text.contains("收起的内容"))
        XCTAssertTrue(NativeChatMarkdownParser.parse(source, toggledCallouts: [0]).text.contains("收起的内容"))
        XCTAssertEqual(NativeChatMarkdownParser.parse("普通\n换行").text, "普通 换行")
        XCTAssertTrue(NativeChatMarkdownParser.parse("[[|]]").runs.isEmpty)
        let before = NativeChatMarkdownParser.parse("中文🙂尾部")
        let after = NativeChatMarkdownParser.parse("中文🙂新增尾部")
        let edit = NativeChatMarkdownEdit.between(before, after)
        let applied = NSMutableString(string: before.text)
        applied.replaceCharacters(in: edit.range, with: edit.replacement.map(\.text).joined())
        XCTAssertEqual(applied as String, after.text)
        XCTAssertEqual(edit.mapSelection(NSRange(location: 0, length: 4)), NSRange(location: 0, length: 4))

        // Canonically equivalent characters can have different NSTextStorage lengths.
        let displayed = NSMutableString(string: "é")
        var previous = NativeChatMarkdownParser.parse(displayed as String)
        for source in ["e\u{301}x", "e\u{301}xy"] {
            let next = NativeChatMarkdownParser.parse(source)
            let change = NativeChatMarkdownEdit.between(previous, next)
            displayed.replaceCharacters(in: change.range, with: change.replacement.map(\.text).joined())
            XCTAssertTrue((displayed as String).utf16.elementsEqual(next.text.utf16))
            previous = next
        }
        XCTAssertNotEqual(NativeChatMarkdownPipeline.Snapshot(markdown: "é", messageID: nil),
                          NativeChatMarkdownPipeline.Snapshot(markdown: "e\u{301}", messageID: nil))
        let unresolved = NativeChatMarkdownParser.parse("[a][r]\n\nTARGET")
        let resolved = NativeChatMarkdownParser.parse("[a][r]\n\nTARGET\n\n[r]: https://example.com\n\nmore")
        let selection = (unresolved.text as NSString).range(of: "TARGET")
        let mapped = NativeChatMarkdownEdit.between(unresolved, resolved).mapSelection(selection)
        XCTAssertEqual((resolved.text as NSString).substring(with: mapped), "TARGET")
    }

    // A real offscreen text view must lay out rich content, keep its objects, and copy readable content.
    @MainActor func testNativeRichAnswerSurvivesResizeAndCompletion() async throws {
        _ = NSApplication.shared
        let textView = NativeChatTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 560, height: 900)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        let window = NSWindow(contentRect: textView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        defer { window.close() }
        let coordinator = NativeChatMarkdownView.Coordinator()
        coordinator.view = textView
        textView.delegate = coordinator
        let pixel = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l2cAAAAASUVORK5CYII="))
        coordinator.imageLoader = { _, completion in completion(pixel) }
        let codeSource = "    let answer = 42 // 中文🙂 <tag>&\n\n"
        let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let highlighted = NSMutableAttributedString(string: codeSource, attributes: [.font: codeFont])
        let tokens = try await NativeChatCodeHighlighter.shared.tokens(codeSource, language: "swift")
        NativeChatCodeHighlighter.apply(tokens, to: highlighted, font: codeFont, isDark: false)
        XCTAssertEqual(highlighted.string, codeSource)
        XCTAssertEqual(tokens.reduce(0) { $0 + $1.range.length }, codeSource.utf16.count)
        XCTAssertNotEqual(highlighted.attribute(.foregroundColor, at: (codeSource as NSString).range(of: "let").location, effectiveRange: nil) as? NSColor, WeiBeiNativePalette.ink())
        let source = """
        一段足够在窄窗口换行的中文回答，保留数学 $x^2$ 与正常的文字选择。

        ```swift
        \(codeSource)```

        | 项目 | 内容 |
        | --- | --- |
        | **公式** | $y$ |

        ![示意图](test-image.png)
        """
        let initial = expectation(description: "native answer applied")
        let completed = expectation(description: "completion applied to same view")
        var applications = 0
        coordinator.pipeline.onApply = { document, edit in
            coordinator.apply(document, edit: edit)
            applications += 1
            if applications == 1 { initial.fulfill() } else { completed.fulfill() }
        }
        defer { coordinator.pipeline.invalidate() }
        let messageID = UUID()
        let markdownMemo = AgentMessageMarkdownMemo()
        let preparedSource = markdownMemo.outputs(text: source, sources: [], language: .chinese).finalized
        XCTAssertTrue(preparedSource.contains(codeSource))
        coordinator.submit(markdown: preparedSource, messageID: messageID)
        await fulfillment(of: [initial], timeout: 5)
        let manager = try XCTUnwrap(textView.textLayoutManager)
        let storage = try XCTUnwrap(textView.textStorage)
        let firstHeight = coordinator.measuredHeight()
        XCTAssertTrue(firstHeight.isFinite && firstHeight > 0)
        textView.layoutSubtreeIfNeeded()
        func checkCodeAttachmentSize() {
            var checked = false
            manager.enumerateTextLayoutFragments(from: manager.textContentManager?.documentRange.location, options: [.ensuresLayout]) { fragment in
                for provider in fragment.textAttachmentViewProviders {
                    guard let attachment = provider.textAttachment as? NativeChatTextAttachment,
                          case .code = attachment.descriptor else { continue }
                    checked = true
                    let frame = fragment.frameForTextAttachment(at: provider.location)
                    XCTAssertEqual(frame.width, textView.frame.width, accuracy: 0.5)
                    XCTAssertGreaterThan(frame.height, CGFloat(codeSource.components(separatedBy: "\n").count) * coordinator.fontSize)
                    XCTAssertEqual(provider.view?.frame.size, frame.size)
                }
                return true
            }
            XCTAssertTrue(checked)
        }
        checkCodeAttachmentSize()
        let firstLaidOutHeight = manager.usageBoundsForTextContainer.maxY
        var originalAttachments: [NativeChatTextAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? NativeChatTextAttachment { originalAttachments.append(attachment) }
        }
        XCTAssertEqual(originalAttachments.count, 4)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.setFrameSize(NSSize(width: 300, height: firstHeight))
        let narrowHeight = coordinator.measuredHeight()
        XCTAssertTrue(narrowHeight.isFinite && narrowHeight > 0)
        textView.layoutSubtreeIfNeeded()
        checkCodeAttachmentSize()
        // The synchronous size is an estimate; compare completed layouts after inspecting all attachments.
        XCTAssertGreaterThanOrEqual(manager.usageBoundsForTextContainer.maxY, firstLaidOutHeight)
        coordinator.submit(markdown: markdownMemo.outputs(text: source + "\n\n回答结束。", sources: [], language: .chinese).finalized, messageID: messageID)
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertTrue(coordinator.view === textView)
        XCTAssertTrue(textView.textLayoutManager === manager)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 4))
        var finalAttachments: [NativeChatTextAttachment] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if let attachment = value as? NativeChatTextAttachment { finalAttachments.append(attachment) }
        }
        XCTAssertEqual(finalAttachments.count, originalAttachments.count)
        XCTAssertTrue(zip(originalAttachments, finalAttachments).allSatisfy { $0 === $1 })
        textView.selectAll(nil)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(textView.writeSelection(to: pasteboard, type: .string))
        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("x^2") && copied.contains(codeSource) && copied.contains("示意图"))
        XCTAssertFalse(copied.contains("\u{fffc}"))
        // A typography change must also refresh the formula's measured dimensions.
        let formula = try XCTUnwrap(finalAttachments.first { if case .math = $0.descriptor { return true }; return false })
        let oldFormulaHeight = try XCTUnwrap(formula.measuredMathSize(for: 300)).height
        coordinator.fontSize = 20
        coordinator.restyle()
        _ = coordinator.measuredHeight()
        XCTAssertGreaterThan(try XCTUnwrap(formula.measuredMathSize(for: 300)).height, oldFormulaHeight)
        XCTAssertFalse(window.isVisible)
    }


    // SwiftUI sizing probes must not resize the text to infinity or add an empty completion footer.
    @MainActor func testCompletionKeepsActualMessageHeightWithoutNoteActions() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let source = String(repeating: "生成结束时，正文和阅读位置应保持不变。", count: 12)
        var message = AgentMessage(role: .assistant, text: source, source: nil, completionState: .generating)
        store.messages = [message]
        XCTAssertNil(store.selectionContext)
        XCTAssertFalse(store.canReplaceNoteSelection)
        func bubble(_ value: AgentMessage, width: CGFloat = 560) -> some View {
            AgentBubble(message: value,
                        liveStreamingText: value.completionState == .generating ? source : nil,
                        isStreaming: value.completionState == .generating)
                .environmentObject(store)
                .frame(width: width)
        }
        let host = NSHostingView(rootView: bubble(message))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func nativeText(in view: NSView) -> NativeChatTextView? {
            if let text = view as? NativeChatTextView { return text }
            return view.subviews.lazy.compactMap { nativeText(in: $0) }.first
        }
        func settledHeight() async throws -> CGFloat {
            var previous: CGFloat = -1
            for _ in 0..<100 {
                try await Task.sleep(nanoseconds: 20_000_000)
                host.layoutSubtreeIfNeeded()
                let height = host.fittingSize.height
                if nativeText(in: host)?.string == source, abs(height - previous) < 0.1 { return height }
                previous = height
            }
            XCTFail("native message did not finish layout")
            return host.fittingSize.height
        }
        let before = try await settledHeight()
        let textView = try XCTUnwrap(nativeText(in: host))
        for width: CGFloat in [480, 300, 560] {
            window.setContentSize(NSSize(width: width, height: 300))
            host.rootView = bubble(message, width: width)
            let height = try await settledHeight()
            XCTAssertGreaterThan(textView.frame.width, 0)
            XCTAssertLessThanOrEqual(textView.frame.width, width)
            XCTAssertEqual(textView.textContainer?.size.width, textView.frame.width)
            if width == 300 { XCTAssertGreaterThan(height, before) }
        }
        message.completionState = .completed
        store.messages = [message]
        // A history estimate must not leave extra blank space after the real body is ready.
        AgentFinalizedMarkdownHeightCache.store(before * 2, for: AgentFinalizedMarkdownHeightCache.cacheKey(
            messageID: message.id, text: source, widthBucket: 0, wideTypography: false))
        host.rootView = bubble(message)
        let after = try await settledHeight()
        XCTAssertEqual(after, before, accuracy: 0.5)
        XCTAssertTrue(nativeText(in: host) === textView)
        XCTAssertFalse(window.isVisible)
    }

    // Scrolling a conversation to its bottom must reveal all of the last answer before its footer.
    @MainActor func testConversationBottomDoesNotClipLastAnswer() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let paragraph = "运行中的组件需要保存状态，也需要在变化后继续工作。" + String(repeating: "这段正文应当完整显示，继续向下滚动可以读到末尾。", count: 6)
        let ending = "回答结束。"
        let sources = [8, 5].map { count in
            (0..<count).map { "## 第 \($0 + 1) 节\n\n\(String(repeating: paragraph, count: $0 % 3 + 1))\n\n1. **保留状态**\n   - 更新依赖。\n   - \(paragraph)\n2. **恢复运行**\n   - 继续阅读。\n" }.joined(separator: "\n") + "\n\(ending)"
        }
        let messages = sources.map { AgentMessage(role: .assistant, text: $0, source: nil) }
        func conversation(lastAnswer: String, streaming: Bool = true) -> some View { ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sources.indices, id: \.self) { index in
                    let isLast = index == sources.count - 1
                    let message = { () -> AgentMessage in
                        var value = messages[index]
                        value.text = isLast ? lastAnswer : sources[index]
                        value.completionState = isLast && streaming ? .generating : .completed
                        value.sources = [AgentReplySource(itemID: nil, kind: .material, title: "资料", label: "资料", excerpt: paragraph)]
                        return value
                    }()
                    AgentBubble(message: message, liveStreamingText: isLast && streaming ? lastAnswer : nil, isStreaming: isLast && streaming)
                        .environmentObject(store)
                }
            }.padding(20)
        }.background(WeiBeiTheme.paper).preferredColorScheme(store.appearanceMode.colorScheme) }
        let host = NSHostingView(rootView: conversation(lastAnswer: "正在回答。"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 700),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func texts(in view: NSView) -> [NativeChatTextView] {
            if let text = view as? NativeChatTextView { return [text] }
            return view.subviews.flatMap { texts(in: $0) }
        }
        func settle() async throws {
            for _ in 0..<15 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        for _ in 0..<15 {
            try await settle()
            if texts(in: host).count == 2, texts(in: host).allSatisfy({ !$0.string.isEmpty }) { break }
        }
        let last = try XCTUnwrap(texts(in: host).last)
        let scroll = try XCTUnwrap(last.enclosingScrollView)
        for length in stride(from: 100, through: sources[1].count, by: 100) {
            host.rootView = conversation(lastAnswer: String(sources[1].prefix(length)))
            try await settle()
        }
        host.rootView = conversation(lastAnswer: sources[1], streaming: false)
        try await settle()
        XCTAssertTrue(last.string.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(ending))
        for _ in 0..<4 {
            let document = try XCTUnwrap(scroll.documentView)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
            try await settle()
        }
        let manager = try XCTUnwrap(last.textLayoutManager)
        let content = try XCTUnwrap(manager.textContentManager)
        func checkVisibleEnd() throws {
            let viewport = try XCTUnwrap(manager.textViewportLayoutController.viewportRange)
            XCTAssertEqual(viewport.endLocation.compare(content.documentRange.endLocation), .orderedSame)
            // Unvisited paragraphs have estimated heights. Check the final rendered line,
            // not the full-document height from a separate, completely laid-out text view.
            let finalCharacter = (last.string as NSString).rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: .backwards)
            let location = try XCTUnwrap(content.location(content.documentRange.location, offsetBy: finalCharacter.location))
            let fragment = try XCTUnwrap(manager.textLayoutFragment(for: location))
            let line = try XCTUnwrap(fragment.textLineFragment(for: location, isUpstreamAffinity: false))
            let bottom = fragment.layoutFragmentFrame.minY + line.typographicBounds.maxY
            XCTAssertGreaterThanOrEqual(last.visibleRect.maxY + 1, bottom, "The last line is clipped at the conversation bottom")
        }
        try checkVisibleEnd()
        if let path = ProcessInfo.processInfo.environment["WEIBEI_CHAT_SNAPSHOT"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }
        XCTAssertFalse(window.isVisible)
    }

    // A long answer must keep the reader's line on resize and still expose its final paragraph.
    @MainActor func testLongAnswerKeepsReadingPositionAndReachableEnd() async throws {
        _ = NSApplication.shared
        let source = (0..<100).map { index in
            "第 \(index) 段：" + String(repeating: "改变窗口宽度时应继续读到同一处文字。", count: 8) + " $x_i^2$。"
        }.joined(separator: "\n\n")
        let host = NSHostingView(rootView: ScrollView {
            NativeChatMarkdownView(markdown: source, fontSize: 16, isDark: false, onOpenURL: { _ in })
                .frame(minWidth: 0, maxWidth: .infinity).padding(20)
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 768),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        func textView(in view: NSView) -> NativeChatTextView? {
            if let text = view as? NativeChatTextView { return text }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
        func settle() async throws {
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        for _ in 0..<25 {
            try await settle()
            if let text = textView(in: host), !text.string.isEmpty, text.frame.height > 768 { break }
        }
        let text = try XCTUnwrap(textView(in: host))
        let manager = try XCTUnwrap(text.textLayoutManager)
        let content = try XCTUnwrap(manager.textContentManager)
        let scroll = try XCTUnwrap(text.enclosingScrollView)
        let clip = scroll.contentView
        func readingPosition() throws -> (NSRange, CGFloat) {
            let fragment = try XCTUnwrap(manager.textLayoutFragment(for: CGPoint(x: 1, y: text.visibleRect.minY + 1)))
            let line = try XCTUnwrap(fragment.textLineFragment(
                forVerticalOffset: text.visibleRect.minY + 1 - fragment.layoutFragmentFrame.minY, requiresExactMatch: false))
            let start = try XCTUnwrap(fragment.textElement?.elementRange?.location)
            let index = content.offset(from: content.documentRange.location, to: start) + line.characterRange.location
            let y = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
            return (NSRange(location: index, length: line.characterRange.length), text.convert(CGPoint(x: 0, y: y), to: clip).y - clip.bounds.minY)
        }
        clip.scroll(to: CGPoint(x: 0, y: 1800))
        try await settle()
        let before = try readingPosition()
        for width in [720, 480, 720, 960] {
            window.setContentSize(NSSize(width: width, height: 768))
            try await settle()
            let after = try readingPosition()
            XCTAssertTrue(NSLocationInRange(before.0.location, after.0))
            XCTAssertEqual(after.1, before.1, accuracy: 1)
        }
        for _ in 0..<3 {
            let document = try XCTUnwrap(scroll.documentView)
            clip.scroll(to: CGPoint(x: 0, y: max(0, document.frame.height - clip.bounds.height)))
            try await settle()
        }
        let viewport = try XCTUnwrap(manager.textViewportLayoutController.viewportRange)
        XCTAssertEqual(viewport.endLocation.compare(content.documentRange.endLocation), .orderedSame)
        XCTAssertEqual(text.frame.height, ceil(manager.usageBoundsForTextContainer.maxY), accuracy: 1)
        XCTAssertFalse(window.isVisible)
    }

    // Once resize restoration finishes, later manual scrolling must not be undone by layout.
    @MainActor func testManualScrollingAfterResizeDoesNotRebound() async throws {
        _ = NSApplication.shared
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let text = NativeChatTextView(usingTextLayoutManager: true)
        text.isVerticallyResizable = false
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = false
        text.string = (0..<80).map { "第 \($0) 段 " + String(repeating: "连续阅读不能被拉回原位。", count: 12) }.joined(separator: "\n\n")
        scroll.documentView = text
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.close() }
        let manager = text.textLayoutManager!
        let probe = NativeChatMarkdownView.Coordinator(); probe.view = text
        probe.document = NativeChatMarkdownParser.parse(text.string)
        func layout(width: CGFloat) {
            text.textContainer!.size.width = width
            manager.ensureLayout(for: manager.textContentManager!.documentRange)
            text.setFrameSize(NSSize(width: width, height: ceil(manager.usageBoundsForTextContainer.maxY)))
        }
        layout(width: 700)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 800))
        probe.layoutDidChange()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        probe.willResize(to: 380)
        layout(width: 380)
        probe.layoutDidChange()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let restored = scroll.contentView.bounds.minY
        let target = restored + 120
        scroll.contentView.scroll(to: CGPoint(x: 0, y: target))
        probe.layoutDidChange()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let actual = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(restored, 0)
        XCTAssertEqual(actual, target, accuracy: 2)
        XCTAssertFalse(window.isVisible)
    }
}
