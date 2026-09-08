import AppKit
import SwiftUI
import WeiBeiCore
import XCTest
@testable import WeiBei

/// Replays the actual main conversation, with synthetic content and a hidden window.
/// Samples measure main-thread scroll/layout work, not display FPS or user acceptance.
final class NativeConversationPerformanceTests: XCTestCase {
    @MainActor func testFastScrollKeepsVisibleBodyAfterStopping() throws {
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiFastScroll-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.messages = (0..<120).map { index in
            if index.isMultiple(of: 2) {
                return AgentMessage(role: .user, text: "问题" + String(repeating: "？", count: index % 9), source: nil)
            }
            let paragraphs = index == 91 ? 467 : index % 13 + 1
            let text = (0..<paragraphs).map { paragraph in
                "第 \(paragraph) 段：" + String(repeating: "快速滑动后，完整正文和阅读位置都应保留。", count: index % 3 + 1)
            }.joined(separator: "\n\n")
            return AgentMessage(role: .assistant, text: text, source: nil)
        }
        let navigation = NativeConversationNavigation()
        let host = NSHostingView(rootView: NativeConversationView(navigation: navigation, wide: false, isVisible: true).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 710, height: 1010),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(NSSize(width: 710, height: 1010))
        try settle(host) { navigation.controller != nil }
        let controller = try XCTUnwrap(navigation.controller)
        defer { controller.disconnect(); window.close() }
        let clip = controller.scrollView.contentView
        let canvas = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        try settle(controller.view) { controller.states.values.contains { $0.preparationCount > 0 } }
        for pass in 0..<8 {
            for step in 0..<40 {
                let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                    wheelCount: 1, wheel1: step < 20 ? 650 : -600, wheel2: 0, wheel3: 0))
                cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64((step == 0 ? CGScrollPhase.began : CGScrollPhase.changed).rawValue))
                controller.scrollView.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
                controller.view.layoutSubtreeIfNeeded()
                controller.view.cacheDisplay(in: controller.view.bounds, to: canvas)
                CFRunLoopRunInMode(.defaultMode, 0.001, true)
            }
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.ended.rawValue))
            controller.scrollView.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
            try settle(controller.view) {
                // Native rubber-banding is still part of the gesture, not a reading-position correction.
                guard abs(clip.constrainBoundsRect(clip.bounds).minY - clip.bounds.minY) < 0.5 else { return false }
                controller.view.cacheDisplay(in: controller.view.bounds, to: canvas)
                let cells: [NativeConversationMessageRow] = self.descendants(controller.view)
                let visible = cells.filter { !$0.textView.string.isEmpty && !$0.textView.visibleRect.isEmpty }
                return !visible.isEmpty && visible.allSatisfy { cell in
                    let text = cell.textView, rect = text.visibleRect
                    // A sliver of the last line's padding can legitimately contain no ink.
                    guard rect.height > (cell.state?.renderer.fontSize ?? 0) else { return true }
                    guard let manager = text.textLayoutManager,
                          let range = manager.textViewportLayoutController.viewportRange else { return false }
                    var hasVisibleLine = false
                    manager.enumerateTextLayoutFragments(from: range.location) { fragment in
                        hasVisibleLine = fragment.textLineFragments.contains {
                            $0.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX,
                                dy: fragment.layoutFragmentFrame.minY).intersects(rect)
                        }
                        return !hasVisibleLine && fragment.layoutFragmentFrame.minY < rect.maxY
                    }
                    return hasVisibleLine
                }
            }
            let anchor = controller.captureReadingAnchor()
            drain(controller.view, duration: 0.2)
            if let anchor, let offset = anchor.characterOffset,
               let text = controller.states[anchor.messageID]?.renderer.view,
               let manager = text.textLayoutManager, let content = manager.textContentManager {
                let after: CGFloat
                if let position = anchor.attachmentPosition,
                   let attachment = text.textStorage?.attribute(.attachment, at: offset, effectiveRange: nil) as? NativeChatTextAttachment {
                    after = try XCTUnwrap(attachment.readingY(for: position, in: clip)) - clip.bounds.minY
                } else {
                    let location = try XCTUnwrap(content.location(content.documentRange.location, offsetBy: offset))
                    let fragment = try XCTUnwrap(manager.textLayoutFragment(for: location))
                    let line = try XCTUnwrap(fragment.textLineFragment(for: location, isUpstreamAffinity: false))
                    after = text.convert(CGPoint(x: 0, y: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY), to: clip).y - clip.bounds.minY
                }
                XCTAssertEqual(after, anchor.viewportOffset, accuracy: 1, "Stopped scrolling must preserve visible content (pass \(pass))")
            }
        }
        XCTAssertFalse(window.isVisible)
    }

    @MainActor func testRevealingHistoryKeepsPreparedRowHeight() throws {
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiHeight-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.messages = (0..<31).map { _ in AgentMessage(role: .user, text: "问题", source: nil) }
        let controller = NativeConversationController(store: store, navigation: NativeConversationNavigation())
        controller.configure(wide: false, textScale: 1, isVisible: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 710, height: 1010),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 710, height: 1010))
        defer { controller.disconnect(); window.close() }
        let id = try XCTUnwrap(store.messages.last?.id)
        try settle(controller.view) { controller.states[id]?.userNaturalWidth != nil }
        let state = try XCTUnwrap(controller.states[id])
        let before = state.bodyHeight
        controller.revealEarlierHistory()
        try settle(controller.view) { controller.tableView.numberOfRows == 31 }
        XCTAssertEqual(state.bodyHeight, before, accuracy: 1,
            "Loading earlier messages must not replace a prepared row's height with an estimate")
        for state in controller.states.values {
            guard let text = state.renderer.view, !text.visibleRect.isEmpty, let manager = text.textLayoutManager else { continue }
            XCTAssertEqual(text.frame.height, max(state.renderer.fontSize * 1.5, ceil(manager.usageBoundsForTextContainer.height)), accuracy: 1)
        }
        XCTAssertFalse(window.isVisible)
    }

    @MainActor func testRecycledRowsKeepPreparedContentSelectionAndDrafts() throws {
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiReuse-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        var messages = (0..<45).map { index in
            AgentMessage(role: .assistant, text: "第 \(index) 条记录。" + String(repeating: "保留完整的会话内容。", count: 45), source: nil)
        }
        let action = AgentReplyAction(kind: .writeNote, proposedMarkdown: "# 草稿\n\n还没有保存的正文。")
        messages[0].actions = [action]
        store.messages = messages
        let navigation = NativeConversationNavigation()
        let controller = NativeConversationController(store: store, navigation: navigation)
        controller.configure(wide: false, textScale: 1, isVisible: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 740),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 720, height: 740))
        defer { controller.disconnect(); window.close() }
        controller.navigate(to: "chat-turn-\(messages[0].id.uuidString)")
        try settle(controller.view) { controller.states[messages[0].id]?.renderer.view?.string == messages[0].text }
        let first = try XCTUnwrap(controller.states[messages[0].id])
        let selection = NSRange(location: 5, length: 12)
        first.renderer.view?.setSelectedRange(selection)
        let draft = try XCTUnwrap(first.actionDrafts[action.id])
        draft.bodyText = "用户改过但尚未提交的草稿。"
        let preparations = first.preparationCount
        controller.jumpToLatest()
        try settle(controller.view) { first.renderer.view == nil }
        let oldCount = controller.structuralUpdateCount
        messages[0].text += " 离屏期间补全的最后一行。"
        store.messages = messages
        try settle(controller.view) { first.renderer.preparedStorage.string == messages[0].text }
        XCTAssertEqual(controller.structuralUpdateCount, oldCount, "A content update must not rebuild the message index")
        XCTAssertEqual(first.preparationCount, preparations + 1)
        controller.navigate(to: "chat-turn-\(messages[0].id.uuidString)")
        try settle(controller.view) { first.renderer.view?.string == messages[0].text }
        XCTAssertEqual(first.preparationCount, preparations + 1, "Returning to prepared content must not parse it again")
        XCTAssertEqual(first.renderer.view?.selectedRange(), selection)
        XCTAssertTrue(first.actionDrafts[action.id] === draft)
        XCTAssertEqual(draft.bodyText, "用户改过但尚未提交的草稿。")

        controller.userWillScroll()
        controller.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 120))
        try settle(controller.view) { controller.captureReadingAnchor() != nil }
        let anchor = try XCTUnwrap(controller.captureReadingAnchor())
        let position = try XCTUnwrap(first.renderer.view).convert(.zero, to: controller.scrollView.contentView).y - controller.scrollView.contentView.bounds.minY
        let beforePrepend = controller.structuralUpdateCount
        let older = AgentMessage(role: .user, text: "历史前插的内容。", source: nil)
        store.messages = [older] + messages
        try settle(controller.view) { controller.structuralUpdateCount > beforePrepend && controller.captureReadingAnchor()?.messageID == anchor.messageID }
        XCTAssertEqual(controller.captureReadingAnchor()?.viewportOffset ?? -100, anchor.viewportOffset, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(first.renderer.view).convert(.zero, to: controller.scrollView.contentView).y - controller.scrollView.contentView.bounds.minY, position, accuracy: 1)
        XCTAssertFalse(controller.followsLatest)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor func testRichContentUsesPreparedResourcesAndVisibleTableCells() throws {
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiRich-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let source = "| 项目 | 内容 | 补充 | 结果 |\n| --- | --- | --- | --- |\n" + (0..<120).map { "| 第 \($0) 行 | **正文**与 $x^2$ | \(String(repeating: "需要横向滚动的宽表内容", count: 4)) | \(String(repeating: "最右侧的结果", count: 4)) \($0) |" }.joined(separator: "\n")
        let message = AgentMessage(role: .assistant, text: source + "\n\n表格后的尾字。", source: nil)
        store.messages = [message]
        let controller = NativeConversationController(store: store, navigation: NativeConversationNavigation())
        controller.configure(wide: false, textScale: 1, isVisible: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 740),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 720, height: 740))
        defer { controller.disconnect(); window.close() }
        try settle(controller.view) {
            let tables: [NativeChatTableView] = self.descendants(controller.view)
            return tables.contains { $0.attachment.tableContent != nil && $0.visibleCellCount > 0 }
        }
        let tables: [NativeChatTableView] = descendants(controller.view)
        let table = try XCTUnwrap(tables.first)
        let data = try XCTUnwrap(table.attachment.tableContent)
        XCTAssertEqual(data.documents.count, 121)
        try assertTableCellsStayInViewport(table)
        let horizontal = try XCTUnwrap(table.enclosingScrollView)
        let horizontalLimit = max(0, horizontal.documentView!.frame.width - horizontal.contentView.bounds.width)
        XCTAssertGreaterThan(horizontalLimit, 0)
        horizontal.contentView.scroll(to: CGPoint(x: horizontalLimit, y: 0))
        horizontal.reflectScrolledClipView(horizontal.contentView)
        try settle(controller.view) {
            let cells: [NativeChatTextView] = self.descendants(controller.view)
            return cells.contains { $0.string.contains("最右侧的结果") && !$0.visibleRect.isEmpty }
        }
        let preparedCount = table.attachment.preparationCount
        for y: CGFloat in [0, 1400, 2800, 0] {
            controller.userWillScroll()
            controller.scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
            try settle(controller.view) {
                let current: [NativeChatTableView] = self.descendants(controller.view)
                return current.contains { $0.attachment === table.attachment && $0.visibleCellCount > 0 }
            }
            let current: [NativeChatTableView] = descendants(controller.view)
            for table in current { try assertTableCellsStayInViewport(table) }
        }
        XCTAssertTrue(table.attachment.tableContent === data)
        XCTAssertEqual(table.attachment.preparationCount, preparedCount)
        let selectedCell = try XCTUnwrap(data.cells.values.first {
            $0.renderer.view?.visibleRect.isEmpty == false && $0.renderer.preparedStorage.string.contains("最右侧的结果")
        })
        let selectedText = selectedCell.renderer.preparedStorage.string
        let cellSelection = NSRange(location: 5, length: 8)
        selectedCell.renderer.view?.setSelectedRange(cellSelection)
        controller.userWillScroll()
        controller.scrollView.contentView.scroll(to: CGPoint(x: 0, y: 3000))
        try settle(controller.view) { selectedCell.renderer.view == nil }
        controller.scrollView.contentView.scroll(to: .zero)
        try settle(controller.view) { selectedCell.renderer.view != nil }
        XCTAssertEqual(selectedCell.renderer.view?.string, selectedText)
        XCTAssertEqual(selectedCell.renderer.view?.selectedRange(), cellSelection)
        let text = try XCTUnwrap(controller.states[message.id]?.renderer.view)
        text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(text.writeSelection(to: pasteboard, type: .string))
        XCTAssertTrue(pasteboard.string(forType: .string)?.contains("第 119 行") == true)
        controller.jumpToLatest()
        try settle(controller.view) {
            guard let manager = text.textLayoutManager, let content = manager.textContentManager else { return false }
            return manager.textViewportLayoutController.viewportRange?.endLocation.compare(content.documentRange.endLocation) == .orderedSame
        }
        XCTAssertFalse(window.isVisible)
    }

    @MainActor func testLongConversationKeepsVisibleTextAndReachableEnd() throws {
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiReading-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let source = (0..<160).map {
            "第 \($0) 段：" + String(repeating: "改变窗口宽度后，应继续阅读同一处文字，完整的回答不能被截断。", count: 10)
        }.joined(separator: "\n\n") + "\n\n最终尾字。"
        var message = AgentMessage(role: .assistant, text: source, source: nil, completionState: .generating)
        let chatID = UUID()
        store.activeStudySessionID = chatID
        store.messages = [message]
        let streaming = store.agentStreaming
        streaming.begin(messageID: message.id, chatID: chatID)
        streaming.text = source
        let controller = NativeConversationController(store: store, navigation: NativeConversationNavigation())
        controller.configure(wide: false, textScale: 1, isVisible: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 740),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 720, height: 740))
        defer { controller.disconnect(); window.close() }
        let scroll = controller.scrollView
        let clip = scroll.contentView
        try settle(controller.view) {
            controller.states[message.id]?.renderer.view?.string.hasSuffix("最终尾字。") == true
                && controller.tableView.bounds.height > clip.bounds.height * 10
        }
        let text = try XCTUnwrap(controller.states[message.id]?.renderer.view)
        let manager = try XCTUnwrap(text.textLayoutManager)
        let content = try XCTUnwrap(manager.textContentManager)
        controller.jumpToLatest()
        try settle(controller.view) {
            manager.textViewportLayoutController.viewportRange?.endLocation.compare(content.documentRange.endLocation) == .orderedSame
        }
        let finalOffset = (text.string as NSString).range(of: "最终尾字。", options: .backwards).location
        let finalLocation = try XCTUnwrap(content.location(content.documentRange.location, offsetBy: finalOffset))
        let finalFragment = try XCTUnwrap(manager.textLayoutFragment(for: finalLocation))
        let finalLine = try XCTUnwrap(finalFragment.textLineFragment(for: finalLocation, isUpstreamAffinity: false))
        XCTAssertGreaterThanOrEqual(text.visibleRect.maxY + 1, finalFragment.layoutFragmentFrame.minY + finalLine.typographicBounds.maxY)

        controller.userWillScroll()
        clip.scroll(to: CGPoint(x: 0, y: 1800))
        try settle(controller.view) { controller.captureReadingAnchor()?.characterOffset != nil }
        let before = try XCTUnwrap(controller.captureReadingAnchor())
        let offset = try XCTUnwrap(before.characterOffset)
        let location = try XCTUnwrap(content.location(content.documentRange.location, offsetBy: offset))
        for width: CGFloat in [480, 900, 720] {
            window.setContentSize(NSSize(width: width, height: 740))
            try settle(controller.view) {
                guard let fragment = manager.textLayoutFragment(for: location),
                      let line = fragment.textLineFragment(for: location, isUpstreamAffinity: false) else { return false }
                let y = text.convert(CGPoint(x: 0, y: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY), to: clip).y - clip.bounds.minY
                return abs(y - before.viewportOffset) < 1
            }
            XCTAssertLessThanOrEqual(manager.textViewportLayoutController.viewportBounds.height, clip.bounds.height + 1,
                "A many-screen answer must not become its own text viewport")
        }
        let structureBeforeStream = controller.structuralUpdateCount
        streaming.text += " 生成中补充的末尾。"
        try settle(controller.view) { text.string.hasSuffix("生成中补充的末尾。") }
        XCTAssertEqual(controller.structuralUpdateCount, structureBeforeStream)
        XCTAssertFalse(controller.followsLatest)
        let beforeCompletion = clip.bounds.minY
        message.text = streaming.text
        message.completionState = .completed
        store.messages = [message]
        streaming.finishDisplaying()
        try settle(controller.view) { controller.states[message.id]?.message.completionState == .completed }
        XCTAssertTrue(controller.states[message.id]?.renderer.view === text)
        XCTAssertEqual(clip.bounds.minY, beforeCompletion, accuracy: 1)
        XCTAssertFalse(controller.followsLatest)
        let formerState = try XCTUnwrap(controller.states[message.id])
        let started = expectation(description: "former session preparation started")
        let release = DispatchSemaphore(value: 0)
        formerState.renderer.pipeline.parse = { snapshot in
            started.fulfill()
            release.wait()
            return NativeChatMarkdownParser.parse(snapshot.markdown)
        }
        formerState.renderer.submit(markdown: "旧会话的延迟结果。", messageID: message.id)
        wait(for: [started], timeout: 5)
        defer { release.signal() }
        let next = AgentMessage(id: message.id, role: .user, text: "# 新会话 **用户输入** $x^2$ 应原样保留。", source: nil)
        store.activeStudySessionID = UUID()
        store.messages = [next]
        try settle(controller.view) { controller.states[next.id]?.renderer.view?.string == next.text }
        release.signal()
        // Observe completion after the old result's main-actor continuation has run.
        try settle(controller.view) { !formerState.renderer.pipeline.working }
        XCTAssertNil(formerState.renderer.view)
        XCTAssertEqual(controller.states[next.id]?.renderer.view?.string, next.text)
        XCTAssertFalse(controller.states[message.id] === formerState)
        XCTAssertFalse(window.isVisible)
    }

    @MainActor private func assertTableCellsStayInViewport(_ table: NativeChatTableView,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try XCTUnwrap(table.attachment.tableContent, file: file, line: line)
        let viewport = table.visibleRect
        let minimumRowHeight = try XCTUnwrap(data.rowHeights.min(), file: file, line: line)
        // At most one partially visible row beyond the viewport's full-row capacity.
        let maximumRows = Int(ceil(viewport.height / minimumRowHeight)) + 1
        let views = table.subviews.compactMap { $0 as? NativeChatTextView }
        XCTAssertLessThanOrEqual(views.count, maximumRows * data.columnWidths.count, file: file, line: line)
        for (key, cell) in data.cells where cell.renderer.view?.superview === table {
            let row = key / data.columnWidths.count, column = key % data.columnWidths.count
            let x = data.columnWidths.prefix(column).reduce(0, +)
            let cellBounds = NSRect(x: x, y: data.rowOffsets[row],
                width: data.columnWidths[column], height: data.rowHeights[row])
            // Include an exact row boundary, but no cells from distant rows or columns.
            XCTAssertTrue(cellBounds.maxY >= viewport.minY && cellBounds.minY <= viewport.maxY
                && cellBounds.maxX > viewport.minX && cellBounds.minX < viewport.maxX,
                "Mounted table cells must intersect the conversation viewport", file: file, line: line)
        }
    }

    @MainActor func testMainConversationScrollWorkload() throws {
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiConversation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.showAgent = true
        let paragraph = String(repeating: "原生会话应当完整显示中文、标点和选择范围，滚动时保留正在阅读的文字。", count: 8)
        let code = (0..<120).map { "let value\($0) = \($0) // 一行可以选择和复制的代码" }.joined(separator: "\n")
        let table = "| 项目 | 解释 |\n| --- | --- |\n" + (0..<80).map { "| 第 \($0) 行 | **内容**与 $x^2$ |" }.joined(separator: "\n")
        let rich = "\n\n```swift\n\(code)\n```\n\n\(table)\n\n最后一行必须可见。"
        let fixtures: [(String, [AgentMessage])] = [
            ("history", (0..<36).map { index in
                AgentMessage(role: index % 2 == 0 ? .user : .assistant,
                             text: index % 2 == 0 ? "第 \(index / 2) 个问题" : (0..<12).map { "## 第 \($0) 节\n\n\(paragraph)" }.joined(separator: "\n\n"), source: nil)
            }),
            ("long-answer", [AgentMessage(role: .assistant, text: (0..<160).map { "## 第 \($0) 节\n\n\(paragraph)" }.joined(separator: "\n\n"), source: nil)]),
            ("rich-content", [AgentMessage(role: .assistant, text: paragraph + rich, source: nil)])
        ]
        let host = NSHostingView(rootView: AgentPaneView(showsPaneHeader: false)
            .environmentObject(store).environmentObject(store.paneState).environmentObject(store.interaction))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 740),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let canvas = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        for (name, messages) in fixtures {
            store.messages = messages
            drain(host, duration: 1)
            let scrolls: [NSScrollView] = descendants(host)
            let scroll = try XCTUnwrap(scrolls.first { $0.hasVerticalScroller })
            let clip = scroll.contentView
            for pass in 0..<2 {
                NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
                for index in 0..<80 {
                    let document = try XCTUnwrap(scroll.documentView)
                    let limit = max(0, document.bounds.height - clip.bounds.height)
                    let phase = CGFloat(index < 40 ? index : 79 - index) / 39
                    let start = DispatchTime.now().uptimeNanoseconds
                    clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: CGPoint(x: 0, y: phase * limit), size: clip.bounds.size)).origin)
                    scroll.reflectScrolledClipView(clip)
                    host.layoutSubtreeIfNeeded()
                    CFRunLoopRunInMode(.defaultMode, 0.001, true)
                    host.layoutSubtreeIfNeeded()
                    host.cacheDisplay(in: host.bounds, to: canvas)
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    WeiBeiPerf.log("chat.main_scroll_frame", ms: ms, extra: "fixture=\(name) pass=\(pass) step=\(index)")
                }
                NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
            }
            let textViews: [NativeChatTextView] = descendants(host)
            XCTAssertTrue(textViews.contains { !$0.string.isEmpty })
            if name != "history", let body = textViews.first {
                XCTAssertGreaterThan(body.frame.width, clip.bounds.width / 2,
                    "In this 720pt window the answer must use the available reading column")
                XCTAssertEqual(body.textContainer?.size.width ?? 0, body.frame.width, accuracy: 1)
            }
            XCTAssertFalse(window.isVisible)
            if name == "rich-content" {
                let codeViews: [NSTextView] = descendants(host)
                XCTAssertTrue(codeViews.contains { $0.string.trimmingCharacters(in: .newlines) == code && !$0.visibleRect.isEmpty },
                    "The code attachment must remain visible after repeated scrolling")
            }
            if name == "rich-content", let path = ProcessInfo.processInfo.environment["WEIBEI_CHAT_SNAPSHOT"] {
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            }
            if name != "history", let body = textViews.first, let manager = body.textLayoutManager,
               let content = manager.textContentManager {
                let lastCharacter = (body.string as NSString).rangeOfCharacter(from: .whitespacesAndNewlines.inverted, options: .backwards)
                let location = try XCTUnwrap(content.location(content.documentRange.location, offsetBy: lastCharacter.location))
                try settle(host) {
                    let end = max(0, scroll.documentView!.frame.height - clip.bounds.height)
                    clip.scroll(to: CGPoint(x: 0, y: end))
                    host.layoutSubtreeIfNeeded()
                    host.cacheDisplay(in: host.bounds, to: canvas)
                    guard manager.textViewportLayoutController.viewportRange?.endLocation.compare(content.documentRange.endLocation) == .orderedSame,
                          let fragment = manager.textLayoutFragment(for: location),
                          let line = fragment.textLineFragment(for: location, isUpstreamAffinity: false) else { return false }
                    let bottom = fragment.layoutFragmentFrame.minY + line.typographicBounds.maxY
                    return bottom <= body.visibleRect.maxY + 1 && bottom >= body.visibleRect.minY
                }
                if name == "rich-content", let path = ProcessInfo.processInfo.environment["WEIBEI_CHAT_SNAPSHOT"] {
                    let end = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("end.png")
                    try XCTUnwrap(canvas.representation(using: .png, properties: [:])).write(to: end)
                }
            }
        }
    }

    // A profiling warmup or observation period after a visible state has been reached.
    // Completion itself is checked by settle, not by elapsed time.
    @MainActor private func drain(_ view: NSView, duration: TimeInterval) {
        let end = Date().addingTimeInterval(duration)
        while Date() < end {
            view.layoutSubtreeIfNeeded()
            CFRunLoopRunInMode(.defaultMode, 0.005, true)
        }
    }

    @MainActor private func settle(_ view: NSView, until complete: () -> Bool,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(5)
        var consecutive = 0
        repeat {
            view.layoutSubtreeIfNeeded()
            CFRunLoopRunInMode(.defaultMode, 0.005, true)
            view.layoutSubtreeIfNeeded()
            consecutive = complete() ? consecutive + 1 : 0
            if consecutive == 3 { return }
        } while Date() < deadline
        XCTFail("The conversation did not reach the requested visible state", file: file, line: line)
        throw NSError(domain: "NativeConversationTest", code: 1)
    }

    @MainActor private func descendants<T: NSView>(_ view: NSView) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0) }
    }
}
