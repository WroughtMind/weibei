import AppKit
import Markdown
import MarkdownParser
import MarkdownView
import SwiftMath

// CI builds/links this target; it does not launch it as a GUI application.
@main
@MainActor
enum LinkedRenderersProbe {
    static func main() {
        let source = "中文 **正文** 与 $x^2$"
        let baseline = Markdown.Document(parsing: source)
        let candidate = MarkdownParser().parse(source)
        let body = MarkdownTextView()
        let formula = MTMathUILabel()
        print(baseline.childCount, candidate.document.count, type(of: body), type(of: formula))
    }
}
