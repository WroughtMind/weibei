import AppKit
import SwiftUI
import XCTest
@testable import WeiBei

final class AgentComposerTextEditorTests: XCTestCase {
    @MainActor
    func testBlankComposerSurfaceRequestsFocus() throws {
        var focusRequests = 0
        let host = NSHostingView(rootView:
            Color.clear
                .frame(width: 200, height: 52)
                .background {
                    AgentComposerFocusSurface { focusRequests += 1 }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        )
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 52)
        host.layoutSubtreeIfNeeded()

        func focusSurface(in view: NSView) -> AgentComposerFocusNSView? {
            if let surface = view as? AgentComposerFocusNSView { return surface }
            return view.subviews.lazy.compactMap(focusSurface).first
        }
        let view = try XCTUnwrap(focusSurface(in: host))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))

        view.mouseDown(with: event)

        XCTAssertEqual(view.convert(view.bounds, to: host).size, host.bounds.size)
        XCTAssertEqual(focusRequests, 1)
    }

    @MainActor
    func testSoftWrappedTextGrowsUntilTheLineLimit() {
        let textView = NSTextView()
        textView.font = .systemFont(ofSize: 16.5)
        textView.textContainer?.lineFragmentPadding = 0

        textView.string = "短问题"
        let short = AgentComposerTextEditor.heights(
            for: textView,
            width: 260,
            lineLimit: 1...6
        )

        textView.string = String(
            repeating: "这是一段没有手动换行但必须按输入框宽度自动折行并增高的长文字。",
            count: 20
        )
        let long = AgentComposerTextEditor.heights(
            for: textView,
            width: 260,
            lineLimit: 1...6
        )

        XCTAssertGreaterThan(long.fitted, short.fitted * 2)
        XCTAssertGreaterThan(long.content, long.fitted)
    }
}
