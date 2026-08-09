import AppKit
import XCTest
@testable import WeiBei

final class AgentComposerTextEditorTests: XCTestCase {
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
