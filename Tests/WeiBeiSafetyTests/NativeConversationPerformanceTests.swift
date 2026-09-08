import AppKit
import SwiftUI
import WeiBeiCore
import XCTest
@testable import WeiBei

/// Replays the actual main conversation, with synthetic content and a hidden window.
/// Samples measure main-thread scroll/layout work, not display FPS or user acceptance.
final class NativeConversationPerformanceTests: XCTestCase {
    @MainActor func testMainConversationScrollWorkload() async throws {
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiConversation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
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
        for (name, messages) in fixtures {
            store.messages = messages
            await drain(host, duration: 1)
            let scrolls: [NSScrollView] = descendants(host)
            let scroll = try XCTUnwrap(scrolls.first { $0.hasVerticalScroller })
            let clip = scroll.contentView
            for pass in 0..<2 {
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
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    WeiBeiPerf.log("chat.main_scroll_layout", ms: ms, extra: "fixture=\(name) pass=\(pass) step=\(index)")
                    await Task.yield()
                }
            }
            let textViews: [NativeChatTextView] = descendants(host)
            XCTAssertTrue(textViews.contains { !$0.string.isEmpty })
            XCTAssertFalse(window.isVisible)
        }
    }

    // The fixed interval here is a profiling warmup, never a correctness completion signal.
    @MainActor private func drain(_ view: NSView, duration: TimeInterval) async {
        let end = Date().addingTimeInterval(duration)
        while Date() < end {
            view.layoutSubtreeIfNeeded()
            CFRunLoopRunInMode(.defaultMode, 0.005, true)
            await Task.yield()
        }
    }

    @MainActor private func descendants<T: NSView>(_ view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0) }
    }
}
