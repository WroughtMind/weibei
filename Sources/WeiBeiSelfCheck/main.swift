import AppKit
import CoreText
import Foundation
import PDFKit
import WeiBeiCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("self-check failed: \(message)\n", stderr)
        exit(1)
    }
}

let offlineChinesePreview = AgentOfflinePreview.render(
    AgentOfflinePreviewInput(
        language: .chinese,
        question: "解释利率为什么是资金价格",
        hasMaterial: true,
        materialTitle: "Mishkin 教材样例",
        materialText: "利率是资金使用价格的表达。金融市场通过利率配置资源。",
        noteTitle: "货币金融学课程 HTML",
        noteText: "## 摘录\n来源：Mishkin 教材样例",
        selectionTitle: "已选文本片段",
        selectionText: "利率是资金使用价格的表达。"
    )
)
expect(offlineChinesePreview.contains("## 离线草稿")
    && !offlineChinesePreview.hasPrefix("未配置密钥")
    && offlineChinesePreview.contains("未配置密钥；这里只整理当前可见内容")
    && offlineChinesePreview.contains("**问题**：解释利率为什么是资金价格")
    && offlineChinesePreview.contains("**上下文**：资料：Mishkin 教材样例 · 笔记：货币金融学课程 HTML · 选区：已选文本片段")
    && offlineChinesePreview.contains("## 可确认")
    && offlineChinesePreview.contains("- 选区依据：利率是资金使用价格的表达。")
    && offlineChinesePreview.contains("- 资料依据：利率是资金使用价格的表达。金融市场通过利率配置资源。")
    && offlineChinesePreview.contains("- 笔记线索：## 摘录 来源：Mishkin 教材样例")
    && offlineChinesePreview.contains("## 建议写入")
    && offlineChinesePreview.contains("- 把可确认依据写入笔记，并保留来源。")
    && !offlineChinesePreview.contains("| 上下文 | 内容 |")
    && !offlineChinesePreview.contains("> 资料摘录："), "offline agent draft stays compact, source-grounded, and note-ready without API key")

let offlineEnglishPreview = AgentOfflinePreview.render(
    AgentOfflinePreviewInput(
        language: .english,
        question: "Explain the selected sentence",
        hasMaterial: false,
        materialTitle: "No document",
        materialText: "",
        noteTitle: "Current note",
        noteText: "",
        selectionTitle: nil,
        selectionText: nil
    )
)
expect(offlineEnglishPreview.contains("## Offline Draft")
    && !offlineEnglishPreview.hasPrefix("No key is configured")
    && offlineEnglishPreview.contains("No key is configured; this only organizes visible context")
    && offlineEnglishPreview.contains("**Question**: Explain the selected sentence")
    && offlineEnglishPreview.contains("**Context**: Material: None · Note: Current note · Selection: None")
    && offlineEnglishPreview.contains("## Confirmed")
    && offlineEnglishPreview.contains("- Note state: the current note is empty.")
    && offlineEnglishPreview.contains("## Suggested Note")
    && offlineEnglishPreview.contains("- Write the confirmed evidence into the note and keep the source attached.")
    && !offlineEnglishPreview.contains("| Context | Content |")
    && !offlineEnglishPreview.contains("> Note excerpt:"), "offline agent draft renders compact English empty-context state as Markdown")
expect(AgentOfflinePreview.preview("A\nB\tC", limit: 20) == "A B C", "offline agent preview normalizes whitespace")
let offlineSuggestedNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: offlineChinesePreview, language: .chinese) ?? ""
expect(offlineSuggestedNoteBlock.contains("## 整理建议")
    && offlineSuggestedNoteBlock.contains("把可确认依据写入笔记，并保留来源。")
    && !offlineSuggestedNoteBlock.contains("## 离线草稿")
    && !offlineSuggestedNoteBlock.contains("## 可确认")
    && !offlineSuggestedNoteBlock.contains("**上下文**"), "writing an offline answer into notes keeps only the note-ready suggestion section")
let normalAgentNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: "## 正式解释\n利率是资金价格。", language: .chinese)
expect(normalAgentNoteBlock == nil, "non-offline markdown answers are not rewritten by the offline-note extractor")

let offlineTurnMessages = AgentOfflineTurn.messages(
    question: "解释当前材料",
    sourceTitle: "Mishkin 教材样例",
    input: AgentOfflinePreviewInput(
        language: .chinese,
        question: "解释当前材料",
        hasMaterial: true,
        materialTitle: "Mishkin 教材样例",
        materialText: "利率是资金使用价格的表达。",
        noteTitle: "货币金融学课程 HTML",
        noteText: "## 摘录",
        selectionTitle: nil,
        selectionText: nil
    )
)
expect(offlineTurnMessages.count == 2
    && offlineTurnMessages[0].role == .user
    && offlineTurnMessages[0].text == "解释当前材料"
    && offlineTurnMessages[0].source == "Mishkin 教材样例"
    && offlineTurnMessages[1].role == .assistant
    && offlineTurnMessages[1].text.contains("## 离线草稿")
    && offlineTurnMessages[1].text.contains("未配置密钥；这里只整理当前可见内容")
    && offlineTurnMessages[1].source == "Mishkin 教材样例"
    && offlineTurnMessages[1].isUsableAgentAnswer, "offline agent turn appends a visible user turn and writable local draft without an API key")

let fontDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Fonts")
let displayFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiStele.ttf")
let monoFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiSteleMono.ttf")
CTFontManagerRegisterFontsForURL(displayFontURL as CFURL, .process, nil)
CTFontManagerRegisterFontsForURL(monoFontURL as CFURL, .process, nil)
expect(NSFont(name: "WeiBeiStele-Regular", size: 18) != nil
    && NSFont(name: "WeiBeiSteleMono-Regular", size: 13) != nil, "bundled WeiBei English fonts register under their PostScript names")

let runScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("script/build_and_run.sh")
let runScript = (try? String(contentsOf: runScriptURL, encoding: .utf8)) ?? ""
expect(runScript.contains("BUILD_CONFIGURATION=\"release\"")
    && runScript.contains("BUILD_CONFIGURATION=\"debug\"")
    && runScript.contains("swift build -c \"$BUILD_CONFIGURATION\"")
    && runScript.contains("swift build -c \"$BUILD_CONFIGURATION\" --show-bin-path")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiSelfCheck")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiWebEditorCheck"), "user-facing app builds are optimized while check and debugger modes remain debuggable")
expect(runScript.contains("kCGWindowOwnerName") && runScript.contains("\"$APP_DISPLAY_NAME\""), "run script verifies the visible app window by owner name")
expect(runScript.contains("let isOnscreen = window[kCGWindowIsOnscreen as String] as? NSNumber") && runScript.contains("let visibleEnough = isOnscreen == nil || isOnscreen?.intValue != 0"), "run script tolerates missing onscreen metadata when the window is otherwise capturable")
expect(!runScript.contains("pid=\"$(pgrep -x \"$PRODUCT_NAME\""), "run script window verification does not depend on pgrep")
expect(runScript.contains("visual_verify_window") && runScript.contains("--visual-verify") && runScript.contains("visual_non_black_ratio") && runScript.contains("visual verify failed: captured window is black or empty") && runScript.contains("nonBlackRatio < 0.02"), "run script exposes an explicit visual non-black window check")
expect(runScript.contains("weibei-visual-verify-latest.png") && runScript.contains("visual_capture_path=$latest_capture_path"), "visual verification leaves one latest screenshot path for review")
expect(runScript.contains("visual verify blocked: macOS refused window capture") && runScript.contains("Grant Screen Recording permission"), "visual verification reports capture-permission failures instead of looking like an app rendering failure")
expect(runScript.contains("open_app() {\n  /usr/bin/open \"$APP_BUNDLE\"\n}")
    && !runScript.contains("open_app() {\n  /usr/bin/open -n \"$APP_BUNDLE\"\n}"), "regular run opens WeiBei without forcing a second app instance")
expect(runScript.contains("RUN_VISUAL_VERIFY=false")
    && runScript.contains("if [[ \"${2:-}\" == \"--visual-verify\"")
    && runScript.contains("finish_verify_window()")
    && runScript.contains("if [[ \"$RUN_VISUAL_VERIFY\" == true ]]; then\n    visual_verify_window")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiWebEditorCheck"), "run script verify mode includes Web editor checks and honors --verify --visual-verify")
expect(runScript.contains("open_app_for_verify()")
    && runScript.contains("VERIFY_DATA_DIR=\"$DIST_DIR/Data\"")
    && runScript.contains("VERIFY_SCENARIO=\"${WEIBEI_VERIFY_SCENARIO:-offline-learning-flow}\"")
    && runScript.contains("rm -rf \"$VERIFY_DATA_DIR\"")
    && runScript.contains("--env WEIBEI_SUPPRESS_ACTIVATION=1 --env WEIBEI_FORCE_OFFLINE_AGENT=1 --env \"WEIBEI_WORKSPACE_DIR=$VERIFY_DATA_DIR\" --env \"WEIBEI_VERIFY_SCENARIO=$VERIFY_SCENARIO\"")
    && runScript.contains("if [[ -n \"$VERIFY_SCENARIO\" ]]; then\n    sleep 2.6\n  fi")
    && runScript.contains("--verify|verify)\n    run_verifiers\n    open_app_for_verify")
    && runScript.contains("--visual-verify|visual-verify)\n    run_verifiers\n    open_app_for_verify"), "verify modes launch the app in the background with an isolated offline learning-flow workspace")
expect(runScript.contains("verify_learning_flow_persistence()")
    && runScript.contains("workspace.json")
    && runScript.contains("## 整理建议")
    && runScript.contains("把可确认依据写入笔记")
    && runScript.contains("! /usr/bin/grep -q \"## 离线草稿\"")
    && runScript.contains("! /usr/bin/grep -q \"## 可确认\""), "verify mode checks that the offline learning flow persists only the note-ready agent suggestion into the note workspace")
expect(runScript.contains("VERIFY_MODE=true")
    && runScript.contains("DIST_DIR=\"${TMPDIR:-/tmp}/weibei-verify-$UID\"")
    && runScript.contains("elif [[ \"$VERIFY_MODE\" == true ]]; then\n  :")
    && runScript.contains("VERIFY_PID")
    && runScript.contains("pgrep -nx \"$PRODUCT_NAME\"")
    && runScript.contains("trap cleanup_verify_app EXIT")
    && runScript.contains("kCGWindowOwnerPID"), "verify modes use an isolated temporary app and PID-scoped window checks instead of killing the user's active WeiBei window")
expect(runScript.contains("PACKAGE_ONLY=false")
    && runScript.contains("MODE=\"package\"")
    && runScript.contains("package blocked: $APP_DISPLAY_NAME is running")
    && runScript.contains("exit 6")
    && runScript.contains("package)\n    ;;")
    && runScript.contains("usage: $0 [run|check|package|--debug"), "run script package mode updates dist without killing or opening the app")
expect(runScript.contains("CHECK_ONLY=false")
    && runScript.contains("MODE=\"check\"")
    && runScript.contains("if [[ \"$CHECK_ONLY\" == true ]]; then")
    && runScript.contains("if [[ \"$CHECK_ONLY\" != true ]]; then")
    && runScript.contains("check)\n    run_verifiers")
    && runScript.contains("usage: $0 [run|check|package|--debug"), "run script check mode runs build checks without killing, packaging, or opening the app")
let editorIndexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
let editorIndexSource = (try? String(contentsOf: editorIndexURL, encoding: .utf8)) ?? ""
expect(!editorIndexSource.contains("WeiBeiStele")
    && !editorIndexSource.contains("--font-brand-latin")
    && !editorIndexSource.contains("font-family: var(--font-brand-latin)")
    && editorIndexSource.contains(".ProseMirror h1,\n    .ProseMirror h2,\n    .ProseMirror h3")
    && editorIndexSource.contains("letter-spacing: 0;"), "Web Markdown editor does not apply bundled WeiBei display fonts inside Markdown file content")
expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout::before { content: attr(data-callout-title); }")
    && !editorIndexSource.contains("content: \"札记\"")
    && !editorIndexSource.contains("content: \"提示\"")
    && !editorIndexSource.contains("content: \"重点\"")
    && !editorIndexSource.contains("content: \"风险\""), "Markdown callout labels come from data-callout-title instead of hardcoded Chinese CSS")
expect(
    editorIndexSource.contains(".ProseMirror span[data-type=\"math_inline\"],")
        && editorIndexSource.contains(".ProseMirror span[data-type=\"math-inline\"],")
        && editorIndexSource.contains(".ProseMirror div[data-type=\"math-block\"],")
        && editorIndexSource.contains(".ProseMirror .math-inline")
        && editorIndexSource.contains(".ProseMirror .math-block"),
    "math styling hides raw source for common Milkdown math node attribute and class shapes"
)
expect(
    editorIndexSource.contains(".ProseMirror .math-inline {\n      color: transparent")
        && editorIndexSource.contains("font-size: 0;")
        && editorIndexSource.contains("font-size: 1rem;")
        && editorIndexSource.contains(".ProseMirror .katex-error {\n      color: var(--cinnabar)"),
    "math styling collapses raw source while keeping KaTeX and errors readable"
)
expect(editorIndexSource.contains("color: rgba(58, 46, 38, .56)") && !editorIndexSource.contains("color: rgba(58, 46, 38, .36)"), "editable markdown markers stay readable on paper")
expect(editorIndexSource.contains(".frontmatter-title {\n      color: var(--muted)") && editorIndexSource.contains("li[data-item-type=\"task\"][data-checked=\"true\"] {\n      color: var(--muted)"), "small frontmatter and completed task text avoid faint low-contrast ink")
if let frontmatterStart = editorIndexSource.range(of: ":root[data-weibei-theme=\"inkstone\"] #frontmatter-panel")?.lowerBound,
   let frontmatterEnd = editorIndexSource[frontmatterStart...].range(of: "\n\n    .ProseMirror")?.lowerBound {
    let darkFrontmatterSource = String(editorIndexSource[frontmatterStart..<frontmatterEnd])
    expect(darkFrontmatterSource.contains("background: var(--paper-raised);")
        && darkFrontmatterSource.contains("border-color: var(--line);")
        && darkFrontmatterSource.contains("border-left-color: var(--cinnabar-line);")
        && !darkFrontmatterSource.contains("rgba(28, 28, 28")
        && !darkFrontmatterSource.contains("border-color: #2d2d2d"), "dark frontmatter panel uses shared theme variables instead of hardcoded ink blocks")
} else {
    expect(false, "dark frontmatter panel style is readable")
}
expect(editorIndexSource.contains(".weibei-source-reference") && editorIndexSource.contains("border-bottom: 1px dotted"), "source references have readable link styling")
expect(editorIndexSource.contains("scrollbar-width: thin")
    && editorIndexSource.contains("scrollbar-color: transparent transparent")
    && editorIndexSource.contains("#editor::-webkit-scrollbar {\n      width: 6px;")
    && editorIndexSource.contains("#editor.weibei-scroll-active::-webkit-scrollbar-thumb")
    && editorIndexSource.contains(".ProseMirror pre::-webkit-scrollbar-thumb")
    && editorIndexSource.contains("width: 5px;")
    && editorIndexSource.contains("background: transparent;")
    && editorIndexSource.contains(".ProseMirror pre.weibei-scroll-active::-webkit-scrollbar-thumb")
    && editorIndexSource.contains("background: rgba(92, 70, 46, .16)"), "web editor root and internal code/math scrollbars fade in while active instead of disappearing completely")
expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout[data-callout-title=\"阅读线索\"]")
    && editorIndexSource.contains("background: rgba(251, 245, 234, .18);")
    && editorIndexSource.contains("box-shadow: none;")
    && editorIndexSource.contains("border-left-color: rgba(145, 38, 28, .28);"), "reading-line callouts render as light margin notes instead of heavy cards")
expect(editorIndexSource.contains(":root[data-weibei-theme=\"inkstone\"] .ProseMirror blockquote.weibei-callout[data-callout-title=\"阅读线索\"]")
    && editorIndexSource.contains("background: rgba(166, 54, 43, .055);")
    && editorIndexSource.contains("border-left-color: rgba(166, 54, 43, .38);"), "reading-line callouts use a dark-theme wash instead of a stray pale paper block")
expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout .weibei-callout-marker")
    && editorIndexSource.contains("display: inline-block !important;")
    && editorIndexSource.contains("opacity: 0 !important;")
    && editorIndexSource.contains("visibility: hidden !important;")
    && editorIndexSource.contains("width: 0 !important;")
    && editorIndexSource.contains("max-width: 0 !important;")
    && editorIndexSource.contains("overflow: hidden !important;"), "Obsidian callout source markers collapse inside rendered callouts")
expect(editorIndexSource.contains("body[data-editable=\"true\"] .ProseMirror blockquote.weibei-callout.weibei-callout-has-heading::before")
    && editorIndexSource.contains("body[data-editable=\"false\"] .ProseMirror blockquote.weibei-callout .weibei-callout-heading {\n      display: none;"), "callout headings stay editable while read-only callouts show the rendered title instead of leaking the raw [!type] source line")
expect(editorIndexSource.contains(".ProseMirror::selection,\n    .ProseMirror ::selection")
    && editorIndexSource.contains("background: var(--selection);"), "web editor selection highlight covers both root and nested ProseMirror text")
expect(editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] #editor")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] .milkdown")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] .ProseMirror")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"][data-weibei-theme=\"inkstone\"] body")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"][data-weibei-theme=\"inkstone\"] #editor")
    && editorIndexSource.contains("min-height: 0;"), "web markdown renderer has a compact preview mode for inline agent answers without dark theme background blocks")
let editorScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/WebEditor/src/editor.js")
let editorScriptSource = (try? String(contentsOf: editorScriptURL, encoding: .utf8)) ?? ""
expect(editorScriptSource.contains("installQuietScrollIndicators")
    && editorScriptSource.contains("const quietScrollableSelector = '#editor, .ProseMirror pre")
    && editorScriptSource.contains("weibei-scroll-active")
    && editorScriptSource.contains("window.setTimeout(() =>")
    && editorScriptSource.contains("}, 850)"), "web editor removes internal scroll indicator state after a short idle delay")
expect(editorScriptSource.contains("document.addEventListener('pointerdown', () =>")
    && editorScriptSource.contains("post('selectionChanged', { text: '', rect: null });"), "web editor clears stale selection context as soon as the user starts a new click or drag")
expect(editorScriptSource.contains("import { liftListItem } from '@milkdown/kit/prose/schema-list';")
    && editorScriptSource.contains("const emptyListItemTypeAtSelection = (state) =>")
    && editorScriptSource.contains("const exitEmptyListItem = (view) =>")
    && editorScriptSource.contains("handleKeyDown(view, event)")
    && editorScriptSource.contains("event.key === 'Enter'")
    && editorScriptSource.contains("&& exitEmptyListItem(view)")
    && editorScriptSource.contains("event.preventDefault();")
    && editorScriptSource.contains("window.WeiBeiEditor.pressKeyForCheck = pressKeyForCheck"), "web editor exits an empty Markdown list item on a second Enter instead of looping bullets")
expect(editorScriptSource.contains("const isCompactPreview = window.weiBeiMarkdownCompactPreview === true")
    && editorScriptSource.contains("post('contentHeightChanged', { height })")
    && editorScriptSource.contains("new ResizeObserver(reportContentHeight)")
    && editorScriptSource.contains("installContentHeightObserver()"), "web editor reports compact markdown preview height back to Swift")
if let mermaidStart = editorIndexSource.range(of: ":root[data-weibei-theme=\"inkstone\"] .weibei-mermaid-render")?.lowerBound,
   let mermaidEnd = editorIndexSource[mermaidStart...].range(of: "\n    .weibei-mermaid-render svg")?.lowerBound {
    let darkMermaidSource = String(editorIndexSource[mermaidStart..<mermaidEnd])
    expect(darkMermaidSource.contains("background: var(--paper-raised);")
        && darkMermaidSource.contains("border-color: var(--line);")
        && !darkMermaidSource.contains("background: #151515;")
        && !darkMermaidSource.contains("border-color: #2d2d2d;"), "dark Mermaid render boxes use shared theme variables instead of hardcoded ink blocks")
} else {
    expect(false, "dark Mermaid render style is readable")
}
let documentTextExtractorURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Services/DocumentTextExtractor.swift")
let documentTextExtractorSource = (try? String(contentsOf: documentTextExtractorURL, encoding: .utf8)) ?? ""
expect(documentTextExtractorSource.contains("private static var pdfTextCache")
    && documentTextExtractorSource.contains("return pdfText(url: url)")
    && documentTextExtractorSource.contains("private static func pagedText(from document: PDFDocument) -> String")
    && documentTextExtractorSource.contains("return \"第 \\(index + 1) 页\\n\\(text)\"")
    && !documentTextExtractorSource.contains("let textLayerText = document.string?.trimmingCharacters")
    && documentTextExtractorSource.contains("let text = textLayerText.isEmpty ? PDFOCRTextExtractor.text(from: document) : textLayerText")
    && documentTextExtractorSource.contains("pdfTextCache[cacheKey] = text"), "PDF material extraction uses cached OCR fallback when the native text layer is empty")
let quietScrollersSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/QuietScrollers.swift")
let quietScrollersSource = (try? String(contentsOf: quietScrollersSourceURL, encoding: .utf8)) ?? ""
let quietScrollersAxisBeforeSize = quietScrollersSource.range(of: "scrollView.hasVerticalScroller = hasVerticalScroller").flatMap { flagRange in
    quietScrollersSource.range(of: "scrollView.verticalScroller?.controlSize = .small").map { sizeRange in
        flagRange.lowerBound < sizeRange.lowerBound
    }
} ?? false
expect(quietScrollersSource.contains("scrollView.scrollerStyle = .overlay")
    && quietScrollersSource.contains("scrollView.autohidesScrollers = true")
    && quietScrollersSource.contains("scrollView.scrollerKnobStyle = .default")
    && !quietScrollersSource.contains("scrollView.scrollerKnobStyle = .dark")
    && quietScrollersAxisBeforeSize
    && quietScrollersSource.contains("hasVerticalScroller: Bool? = nil")
    && quietScrollersSource.contains("configureRecursively(\n        in view: NSView,")
    && quietScrollersSource.contains("static func flashRecursively(in view: NSView, repeatCount: Int = 0)")
    && quietScrollersSource.contains("view.layoutSubtreeIfNeeded()")
    && quietScrollersSource.contains("scrollView.flashScrollers()")
    && quietScrollersSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.18)"), "native scroll views use overlay auto-hiding scrollers with explicit axis control and a delayed visible scroll flash")

expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.pdf")) == .pdf, "pdf detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.html")) == .html, "html detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.md")) == .markdown, "markdown detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.txt")) == .text, "text detection")

func makeSelectablePDF(at url: URL) {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 260)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        expect(false, "create pdf context")
        return
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSString(string: "PDF 可选文本层：利率是资金使用价格的表达。").draw(
        at: CGPoint(x: 42, y: 178),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]
    )
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    expect(data.write(to: url, atomically: true), "write selectable pdf")
}

func makeImageOnlyPDF(at url: URL) {
    let image = NSImage(size: NSSize(width: 900, height: 260))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    NSString(string: "INTEREST RATE OCR PRICE").draw(
        at: CGPoint(x: 48, y: 96),
        withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 54),
            .foregroundColor: NSColor.black
        ]
    )
    image.unlockFocus()

    let document = PDFDocument()
    guard let page = PDFPage(image: image) else {
        expect(false, "create image-only pdf page")
        return
    }
    document.insert(page, at: 0)
    expect(document.write(to: url), "write image-only pdf")
}

let selectablePDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-selectable-pdf-check-\(UUID().uuidString).pdf")
makeSelectablePDF(at: selectablePDFURL)
defer { try? FileManager.default.removeItem(at: selectablePDFURL) }
let selectablePDF = PDFDocument(url: selectablePDFURL)
expect(selectablePDF?.string?.contains("利率是资金使用价格") == true, "PDFKit extracts text from selectable PDF text layer")
let pdfSelections = selectablePDF?.findString("资金使用价格", withOptions: []) ?? []
expect(pdfSelections.count == 1, "PDFKit finds selectable text in generated PDF")
if let selection = pdfSelections.first, let page = selection.pages.first {
    expect(selection.string == "资金使用价格", "PDFSelection preserves selected text")
    let selectedPDFPageIndex = selectablePDF?.index(for: page)
    expect(selectedPDFPageIndex == 0, "PDFSelection resolves selected page index")
    expect(!selection.bounds(for: page).isEmpty, "PDFSelection exposes non-empty page bounds for floating agent anchor")
    let ownerTitle = "Mishkin 教材样例，第 \((selectedPDFPageIndex ?? 0) + 1) 页"
    let context = SelectionContext(text: selection.string ?? "", source: .document, ownerTitle: ownerTitle)
    let reference = SourceReferenceTitle.parse("来源：\(context.ownerTitle)")
    expect(context.label(language: .chinese) == "文档选区：Mishkin 教材样例，第 1 页", "PDF selection context carries the selected page label into the floating agent")
    expect(reference.title == "Mishkin 教材样例" && reference.pageIndex == 0, "PDF selection reference can jump back to the selected page")
} else {
    expect(false, "PDFSelection contains page")
}

let imageOnlyPDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-image-only-pdf-check-\(UUID().uuidString).pdf")
makeImageOnlyPDF(at: imageOnlyPDFURL)
defer { try? FileManager.default.removeItem(at: imageOnlyPDFURL) }
let imageOnlyPDF = PDFDocument(url: imageOnlyPDFURL)
expect(imageOnlyPDF?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false, "image-only PDF has no native text layer")
let ocrText = imageOnlyPDF.flatMap { PDFOCRTextExtractor.text(from: $0, maxPages: 1) }?.uppercased() ?? ""
expect(ocrText.contains("INTEREST") && ocrText.contains("OCR") && ocrText.contains("PRICE"), "Vision OCR extracts text from image-only PDF pages")
let ocrPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, maxPages: 1) } ?? []
expect(ocrPages.count == 1 && ocrPages[0].lines.contains { $0.text.uppercased().contains("INTEREST") && !$0.boundingBox.isEmpty }, "Vision OCR keeps page text bounds for scanned PDF selection overlays")
let targetedOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [0]) } ?? []
expect(targetedOCRPages.count == 1 && targetedOCRPages[0].pageIndex == 0, "Vision OCR can target a specific PDF page for mixed text and scanned documents")
let outOfRangeOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [1]) } ?? []
expect(outOfRangeOCRPages.isEmpty, "targeted OCR ignores pages outside the PDF")

let data = Data("""
{"output":[{"content":[{"type":"output_text","text":"只根据当前材料回答。"}]}]}
""".utf8)
let text = try OpenAIResponsesClient.extractText(from: data)
expect(text == "只根据当前材料回答。", "response parser")
let groundedPrompt = OpenAIResponsesClient.composePrompt(
    question: "解释金融体系",
    materialTitle: "Mishkin 教材样例",
    materialText: "金融体系把储蓄者的资金转移给有投资机会的人。",
    noteTitle: "利率笔记",
    noteText: "## 摘录\n金融体系和利率相关。",
    selectionTitle: "Mishkin 教材样例，第 1 页选区",
    selectionText: "储蓄者的资金转移给有投资机会的人",
    recentMessages: [
        AgentMessage(role: .user, text: "上一问", source: "利率笔记")
    ]
)
expect(groundedPrompt.input.contains("当前材料：Mishkin 教材样例"), "agent prompt includes material title")
expect(groundedPrompt.input.contains("当前笔记：利率笔记"), "agent prompt includes note title")
expect(groundedPrompt.input.contains("当前选区（来源：Mishkin 教材样例，第 1 页选区）："), "agent prompt includes selection source")
expect(groundedPrompt.input.contains("用户（来源：利率笔记）：上一问"), "agent prompt keeps recent message source")
expect(groundedPrompt.instructions.contains("来源依据") && groundedPrompt.instructions.contains("没有用到的来源不要列"), "agent prompt requires grounded source evidence")
expect(groundedPrompt.instructions.contains("学习助手") && !groundedPrompt.instructions.contains("学习 Agent"), "agent prompt speaks as a study assistant instead of internal agent copy")
let multiSelectionPrompt = OpenAIResponsesClient.composePrompt(
    question: "比较这些片段",
    materialTitle: "Mishkin 教材样例",
    materialText: "金融体系与利率。",
    noteTitle: "利率笔记",
    noteText: "",
    selectionTitle: "2 个已选文本片段",
    selectionText: """
    片段 1（来源：Mishkin 教材样例，第 1 页）：
    金融体系转移资金。

    片段 2（来源：利率笔记）：
    利率是资金使用价格。
    """,
    recentMessages: []
)
expect(multiSelectionPrompt.input.contains("当前选区（来源：2 个已选文本片段）：")
    && multiSelectionPrompt.input.contains("片段 1（来源：Mishkin 教材样例，第 1 页）：")
    && multiSelectionPrompt.input.contains("片段 2（来源：利率笔记）："), "agent prompt can carry multiple selected text attachments with source labels")
let assistantDialoguePrompt = OpenAIResponsesClient.composePrompt(
    question: "继续解释",
    materialTitle: "Mishkin 教材样例",
    materialText: "金融体系把储蓄者的资金转移给有投资机会的人。",
    noteTitle: "利率笔记",
    noteText: "",
    selectionText: nil,
    recentMessages: [
        AgentMessage(role: .assistant, text: "上一答", source: nil)
    ]
)
expect(assistantDialoguePrompt.input.contains("助手：上一答")
    && !assistantDialoguePrompt.input.contains("Agent：上一答"), "assistant dialogue turns avoid internal agent labels")
let currentPagePrompt = OpenAIResponsesClient.composePrompt(
    question: "解释当前页",
    materialTitle: "Mishkin 教材样例，第 3 页",
    materialText: "第 1 页\n旧页面内容\n\n第 3 页\n当前页内容\n\n第 4 页\n后续页面内容",
    noteTitle: "利率笔记",
    noteText: "",
    selectionText: nil,
    recentMessages: []
)
expect(currentPagePrompt.input.contains("当前材料：Mishkin 教材样例，第 3 页")
    && currentPagePrompt.input.contains("第 3 页\n当前页内容")
    && !currentPagePrompt.input.contains("旧页面内容")
    && !currentPagePrompt.input.contains("后续页面内容"), "agent prompt focuses PDF material text on the current reader page when the material title has a page reference")
let noteOnlyPrompt = OpenAIResponsesClient.composePrompt(
    question: "整理这段",
    materialTitle: "未选择材料",
    materialText: "",
    noteTitle: "概念笔记",
    noteText: "实际利率需要区分通胀预期。",
    selectionText: "实际利率",
    recentMessages: []
)
expect(noteOnlyPrompt.input.contains("当前材料：无") && noteOnlyPrompt.input.contains("当前选区（来源：概念笔记）："), "note-only prompt anchors selection to the current note")
let englishPrompt = OpenAIResponsesClient.composePrompt(
    question: "Summarize this",
    materialTitle: "",
    materialText: "",
    noteTitle: "",
    noteText: "Real interest rates account for expected inflation.",
    selectionTitle: "",
    selectionText: "real interest rates",
    recentMessages: [
        AgentMessage(role: .assistant, text: "Earlier answer", source: "Current note")
    ],
    language: .english
)
expect(
    englishPrompt.input.contains("Current material: none")
        && englishPrompt.input.contains("Current note: Current note")
        && englishPrompt.input.contains("Current selection (source: Current note):")
        && englishPrompt.input.contains("Assistant (source: Current note): Earlier answer")
        && englishPrompt.instructions.contains("Answer in English")
        && englishPrompt.instructions.contains("Sources used")
        && !englishPrompt.input.contains("当前笔记"),
    "agent prompt has a complete English note-only mode"
)
expect(OpenAIAPIKeyStore.cleaned("  sk-test\n") == "sk-test", "api key cleaning")

let temporaryKeychainStore = KeychainPasswordStore(
    service: "com.changfenhuang.weibei.selfcheck.\(UUID().uuidString)",
    account: "OPENAI_API_KEY"
)
try? temporaryKeychainStore.delete()
try temporaryKeychainStore.save("  sk-selfcheck\n")
expect(temporaryKeychainStore.load() == "sk-selfcheck", "keychain save and load")
try temporaryKeychainStore.delete()
expect(temporaryKeychainStore.load().isEmpty, "keychain delete")

let missingSelectionInsight = QuietInsight.make(
    materialTitle: "利率资料",
    materialText: "实际利率扣除了通货膨胀后的购买力变化。",
    noteText: "# 利率资料\n",
    selectionText: "实际利率扣除了通货膨胀后的购买力变化。"
)
expect(missingSelectionInsight.body.contains("还没有进入笔记"), "selection insight")

let coveredMaterialInsight = QuietInsight.make(
    materialTitle: "利率资料",
    materialText: "实际利率扣除了通货膨胀后的购买力变化。",
    noteText: "实际利率扣除了通货膨胀后的购买力变化。",
    selectionText: nil
)
expect(coveredMaterialInsight.body.contains("已经覆盖"), "covered material insight")
let noteOnlyInsight = QuietInsight.make(
    materialTitle: "新概念笔记",
    materialText: "",
    noteText: "实际利率需要区分名义利率和通胀预期。",
    selectionText: nil
)
expect(noteOnlyInsight.body.contains("当前笔记有一条") && !noteOnlyInsight.body.contains("先导入"), "note-only quiet insight uses note context")
expect(noteOnlyInsight.noteBlock.contains("来源：新概念笔记"), "note-only quiet insight keeps note source")
expect(noteOnlyInsight.noteBlock.contains("> [!note] 阅读线索\n>\n>") && !noteOnlyInsight.noteBlock.contains("静默洞察"), "quiet insight writes as a readable callout instead of a noisy bullet")
let coveredNoteSelectionInsight = QuietInsight.make(
    materialTitle: "新概念笔记",
    materialText: "",
    noteText: "实际利率需要区分名义利率和通胀预期。",
    selectionText: "实际利率需要区分名义利率和通胀预期。"
)
expect(!coveredNoteSelectionInsight.body.contains("当前材料其他段落"), "covered note selection avoids fake material relation")
let agentInsight = QuietInsight.agent(materialTitle: "利率资料", answer: "这份材料更适合先补通胀预期这一层。")
expect(agentInsight?.body.contains("通胀预期") == true, "agent insight keeps answer")
expect(agentInsight?.noteBlock.contains("> [!note] 阅读线索\n>\n>") == true && agentInsight?.noteBlock.contains("Agent 洞察") == false, "agent insight writes the same quiet reading-line callout")
expect(QuietInsight.agent(materialTitle: "利率资料", answer: "   \n") == nil, "empty agent insight is ignored")
let markdownNoiseInsight = QuietInsight.make(
    materialTitle: "Markdown 验收",
    materialText: """
    ![image](missing.png)
    | 能力 | 状态 |
    | --- | --- |
    - [ ] todo
    删除线、重点高亮、货币理论、新概念笔记。
    """,
    noteText: "",
    selectionText: nil
)
expect(!markdownNoiseInsight.body.contains("[image]"), "quiet insight ignores markdown image syntax")
expect(markdownNoiseInsight.body.contains("货币理论"), "quiet insight keeps readable markdown prose")
let foldedCalloutInsight = QuietInsight.make(
    materialTitle: "Callout 验收",
    materialText: """
    > [!note]-折叠标题不应泄漏控制符
    >
    > 利率是资金使用价格的表达。
    """,
    noteText: "",
    selectionText: nil
)
expect(!foldedCalloutInsight.body.contains("[!note]")
    && !foldedCalloutInsight.body.contains("-折叠标题"), "quiet insight removes Obsidian callout control and fold markers")
let calloutSelectionText = MarkdownSelectionSanitizer.clean("""
[!quote] 选区摘录
利率是资金使用价格的表达。
""")
expect(calloutSelectionText == "选区摘录\n利率是资金使用价格的表达。", "selection sanitizer removes visible Obsidian callout control markers from rendered selections")
let quotedCalloutSelectionText = MarkdownSelectionSanitizer.clean("""
> [!warning]- 风险提示
> 普通美元 $5 不应被误伤。
""")
expect(!quotedCalloutSelectionText.contains("[!warning]")
    && quotedCalloutSelectionText.contains("风险提示")
    && quotedCalloutSelectionText.contains("$5"), "selection sanitizer handles quoted and folded callouts without damaging ordinary prose")
let readableMarkdownSelectionText = MarkdownSelectionSanitizer.clean("""
==重点==<br />
[[货币理论|理论别名]]
[[货币理论\\|表格别名]]
![曲线图|120x80](assets/curve.png)
![[assets/curve.png|180]]
~~删除线~~、`代码`、^[脚注说明]
%%内部注释%%
- [x] 已完成项
""")
let expectedReadableMarkdownSelectionText = """
重点
理论别名
表格别名
曲线图
assets/curve.png
删除线、代码、脚注说明
已完成项
"""
expect(readableMarkdownSelectionText == expectedReadableMarkdownSelectionText, "selection sanitizer turns common Markdown and Obsidian writing syntax into readable text for Agent context")
let searchableTags = MarkdownTagSearch.tags(in: """
---
tags:
  - property/rate
  - "#quoted-tag"
---

# 标题不是标签
正文标签 #finance/rate 和 #nested/tag
行内代码 `#not-tag` 不应该进入标签

```swift
let tag = "#code-tag"
```
""")
expect(searchableTags == ["#finance/rate", "#nested/tag", "#property/rate", "#quoted-tag"], "markdown tag search extracts real prose and frontmatter property tags")
expect(MarkdownTagSearch.tags(in: "---\ntags: [banking, #macro/rate]\n---\n正文") == ["#banking", "#macro/rate"], "markdown tag search reads inline frontmatter tag arrays")
expect(MarkdownTagSearch.matches(query: "finance", in: "#finance/rate")
    && MarkdownTagSearch.matches(query: "macro", in: "---\ntags: [banking, macro/rate]\n---")
    && MarkdownTagSearch.matches(query: "#nested", in: "#nested/tag")
    && !MarkdownTagSearch.matches(query: "code-tag", in: "`#code-tag`"), "markdown tag search supports library queries without indexing code")

expect(PageNavigator.previous(0) == 0, "pdf previous clamps first page")
expect(PageNavigator.next(0, pageCount: 2) == 1, "pdf next advances")
expect(PageNavigator.next(1, pageCount: 2) == 1, "pdf next clamps last page")
expect(PageNavigator.display(0, pageCount: 0) == "1 / 1", "pdf display empty")
expect(TopBarLeadingInset.value(isFullScreen: true) == 12, "fullscreen top-left controls start from the left edge")
expect(TopBarLeadingInset.value(isFullScreen: false) == 80
    && TopBarLeadingInset.value(isFullScreen: false) > TopBarLeadingInset.value(isFullScreen: true), "windowed top-left controls clear the traffic-light area")
expect(!PDFModeChipPresentation.showsLabel(isExpanded: false), "pdf mode chip hides text after collapse")
expect(PDFModeChipPresentation.showsLabel(isExpanded: true), "pdf mode chip shows text only during transient expansion")
expect(PDFModeChipPresentation.controlOpacity(isExpanded: false, isHovering: true)
    < PDFModeChipPresentation.controlOpacity(isExpanded: true, isHovering: true), "pdf mode chip fades back even when hover state lingers")
expect(ReaderSearch.cleaned("  利率\n") == "利率", "reader search trims query")
expect(ReaderSearch.firstMatch(in: "实际利率与名义利率", query: "名义")?.location == 5, "reader search finds first match")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: "money")?.location == 0, "reader search ignores case")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: " ") == nil, "reader search ignores empty query")
let pdfSourceReference = SourceReferenceTitle.parse("> 来源：Mishkin 教材样例，第 3 页")
expect(pdfSourceReference.title == "Mishkin 教材样例" && pdfSourceReference.pageIndex == 2, "source reference parses pdf page")
let calloutSourceReference = SourceReferenceTitle.parse("""
> [!quote] 选区摘录
> 实际利率
>
> 来源：Mishkin 教材样例，第 12 页
""")
expect(calloutSourceReference.title == "Mishkin 教材样例" && calloutSourceReference.pageIndex == 11, "source reference parses quote callout")
expect(WikiLink.targetTitle(from: "  货币理论 | 显示名 ") == "货币理论", "wikilink alias keeps target title")
expect(WikiLink.targetTitle(from: "  货币理论 ") == "货币理论", "wikilink plain title")
expect(WikiLink.targetTitle(from: "货币理论#利率") == "货币理论", "wikilink heading target opens note title")
expect(WikiLink.targetTitle(from: "货币理论#^rate-block") == "货币理论", "wikilink block target opens note title")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论|Money]] 继续写", cursor: 6) == "货币理论", "wikilink title at cursor")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论#利率]] 继续写", cursor: 8) == "货币理论", "wikilink heading title at cursor")
expect(WikiLink.enclosingTitle(in: "没有双链", cursor: 2) == nil, "wikilink title ignores plain text")
expect(WorkspaceLayout.documentAgentNotes.hasCollapsibleRightPane, "three-pane layout can collapse right pane")
expect(WorkspaceLayout.documentNotesSplit.hasCollapsibleRightPane, "split layout can collapse right pane")
expect(!WorkspaceLayout.immersiveReading.hasCollapsibleRightPane, "immersive reading has no right pane to collapse")
expect(WorkspaceLayout.documentAgentNotes.isDocumentThreePane
    && WorkspaceLayout.documentNotesAgent.isDocumentThreePane
    && !WorkspaceLayout.documentNotesSplit.isDocumentThreePane, "only full document layouts participate in three-pane reordering")
expect(WorkspaceLayout.documentAgentNotes.allowsRailOnlyPanes
    && WorkspaceLayout.documentNotesSplit.allowsRailOnlyPanes
    && !WorkspaceLayout.immersiveConversation.allowsRailOnlyPanes
    && !WorkspaceLayout.immersiveWriting.allowsRailOnlyPanes, "only normal multi-pane layouts can collapse content panes into rail-only mode")
expect(WorkspaceLayout.documentAgentNotes.defaultThreePaneOrder == [.reader, .agent, .notes]
    && WorkspaceLayout.documentNotesAgent.defaultThreePaneOrder == [.reader, .notes, .agent], "legacy three-pane layout presets map to pane role order")
expect(WorkspacePaneRole.normalized([.notes, .reader, .notes]) == [.notes, .reader, .agent], "pane role order normalization preserves user pane order and restores missing panes")
expect(WorkspacePaneRole.agent.focus == .agent
    && WorkspacePaneRole.reader.shortLabel(language: .chinese) == "文"
    && WorkspacePaneRole.notes.label(language: .english) == "Notes", "pane roles expose focus and localized labels")
let reorderOrder: [WorkspacePaneRole] = [.reader, .agent, .notes]
let reorderFrames: [WorkspacePaneRole: CGRect] = [
    .reader: CGRect(x: 0, y: 0, width: 320, height: 600),
    .agent: CGRect(x: 330, y: 0, width: 620, height: 600),
    .notes: CGRect(x: 960, y: 0, width: 360, height: 600)
]
expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .reader, horizontalDelta: 180) == 1, "pane reorder target follows real resized pane overlap instead of fixed thirds")
expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .notes, horizontalDelta: -420) == 1, "pane reorder target works from either edge using the current pane widths")
expect(NoteRenderMode.visibleCases == [.rich, .split, .source]
    && NoteRenderMode.preview.visibleMode == .rich
    && NoteRenderMode.source.visibleMode == .source, "note render modes keep legacy preview data readable while hiding preview from the writing controls")
expect(WorkspaceLayout.documentAgentNotes.label(language: .chinese) == "阅读-对话-笔记"
    && WorkspaceLayout.documentAgentNotes.label(language: .english) == "Reader-Chat-Notes"
    && WorkspaceLayout.documentNotesAgent.label(language: .chinese) == "阅读-笔记-对话"
    && WorkspaceLayout.documentNotesSplit.label(language: .english) == "Reader / Notes", "layout labels use localized task language instead of internal pane names")
expect(WorkspaceLayout.immersiveConversation.systemImage == "bubble.left.and.text.bubble.right" && WorkspaceLayout.immersiveWriting.systemImage == "square.and.pencil", "immersive layouts expose semantic menu icons")
let contentViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ContentView.swift")
let contentViewSource = (try? String(contentsOf: contentViewSourceURL, encoding: .utf8)) ?? ""
expect(!contentViewSource.isEmpty, "content view source is readable")
let contentRailSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ContentRailView.swift")
let contentRailSource = (try? String(contentsOf: contentRailSourceURL, encoding: .utf8)) ?? ""
expect(contentRailSource.contains("struct ContentRailView: View")
    && contentRailSource.contains("static let railOnlyWidth: CGFloat = 88")
    && contentRailSource.contains("static let normalWidth: CGFloat = 28")
    && contentRailSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.10")
    && contentRailSource.contains("previewImage: NSImage?")
    && contentRailSource.contains(".popover(")
    && contentRailSource.contains("SpatialTapGesture()")
    && contentRailSource.contains("private func nearestItem"), "shared content rail supports normal, rail-only, delayed unclipped hover, dense-track mapping, and real image previews")
expect(contentViewSource.contains("case .immersiveReading:\n                ZStack(alignment: .topTrailing)")
    && contentViewSource.contains("QuietInsightView(compact: true)")
    && contentViewSource.contains(".padding(.top, 24)")
    && !contentViewSource.contains("QuietInsightView(compact: true)\n                            .padding(.trailing, 28)\n                            .padding(.bottom, 28)"), "immersive reading keeps quiet insight on the upper side edge so it does not cover PDF page controls")
let themeSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/Theme.swift")
let themeSource = (try? String(contentsOf: themeSourceURL, encoding: .utf8)) ?? ""
expect(themeSource.contains(".fill(.regularMaterial)") && themeSource.contains("paperWashOpacity"), "header glass uses one shared paper material wash")
expect(themeSource.contains("WeiBeiTheme.glassTint.opacity(0.16 * opacity)") && !themeSource.contains("WeiBeiTheme.paperInset.opacity(0.10 * opacity)"), "header handoff fade avoids a hard paper edge")
expect(themeSource.contains("dark: WeiBeiTone(hex: 0x1A1814)")
    && themeSource.contains("dark: WeiBeiTone(hex: 0x3A3328)")
    && themeSource.contains("colorScheme == .dark ? 0.12 : 0.20")
    && themeSource.contains("colorScheme == .dark ? 0.16 : 0.24"), "dark glass headers use warm inkstone wash instead of hard black blocks")
expect(themeSource.contains("paperRaised.opacity(0.985)")
    && themeSource.contains(".opacity(0.015)")
    && !themeSource.contains("paperRaised.opacity(0.92)"), "floating panels stay readable without losing the light glass surface")
expect(!themeSource.contains("func weibeiInputPrompt")
    && !themeSource.contains(".overlay(alignment: .topLeading)")
    && !themeSource.contains("prompt.padding(.top, top)")
    && !themeSource.contains(".foregroundColor(.white)")
    && !themeSource.contains(".foregroundStyle(.white)"), "input placeholders use native prompt text instead of a separate overlay")
expect(themeSource.contains("hovering = isEnabled && isHovering")
    && themeSource.contains(".onChange(of: isEnabled)")
    && themeSource.contains("hovering = false"), "icon buttons clear stale hover state when controls disable or the pointer leaves")
expect(themeSource.contains("func weibeiInputSurface")
    && themeSource.contains("static let placeholderInk")
    && themeSource.contains("horizontalPadding: CGFloat = 10")
    && themeSource.contains(".padding(.horizontal, horizontalPadding)")
    && themeSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && themeSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
    && themeSource.contains(".tint(WeiBeiTheme.link)")
    && !themeSource.contains(".environment(\\.colorScheme, .light)")
    && themeSource.contains(".fill(WeiBeiTheme.paperRaised.opacity(active ? 0.66 : 0.60))")
    && themeSource.contains(".stroke(WeiBeiTheme.glassHighlight.opacity(active ? 0.34 : 0.24), lineWidth: 1)")
    && themeSource.contains(".stroke(WeiBeiTheme.paperInset.opacity(active ? 0.30 : 0.38), lineWidth: 1)")
    && themeSource.contains(".stroke(active ? WeiBeiTheme.link.opacity(0.34) : WeiBeiTheme.hairline.opacity(0.54), lineWidth: 1)")
    && !themeSource.contains("secondaryInk.opacity(0.84)"), "input surfaces use semantic ink without forcing the old light color scheme")
expect(themeSource.contains("enum WeiBeiAppearanceMode")
    && themeSource.contains("case inkstone")
    && themeSource.contains("WeiBeiNativePalette")
    && themeSource.contains("static func weiBei(light:"), "theme exposes a persisted paper/inkstone appearance mode and native AppKit palette")
expect(!themeSource.contains("var label: String")
    && !themeSource.contains("var actionLabel: String"), "theme-facing labels require an interface language instead of Chinese-only fallback properties")
expect(themeSource.contains("static let appearance = Animation.easeInOut(duration: 0.42)"), "appearance changes use a dedicated smooth theme transition")
expect(themeSource.contains("tertiaryInk.opacity(0.58)") && themeSource.contains("tertiaryInk.opacity(0.60)"), "disabled button text remains legible on light paper surfaces")
expect(themeSource.contains("englishDisplayFontName = \"WeiBeiStele-Regular\"")
    && themeSource.contains("englishMonoFontName = \"WeiBeiSteleMono-Regular\"")
    && themeSource.contains("Bundle.module.url(forResource: name, withExtension: \"ttf\")\n                ?? Bundle.module.url(forResource: name, withExtension: \"ttf\", subdirectory: \"Fonts\")")
    && themeSource.contains("case .english:\n            registerBundledFonts()\n            return .custom(englishDisplayFontName, size: size).weight(weight)")
    && themeSource.contains("static func englishBrandFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {\n        registerBundledFonts()")
    && themeSource.contains("case .english:\n            registerBundledFonts()\n            return .custom(englishMonoFontName, size: size)")
    && themeSource.contains("return .custom(englishDisplayFontName, size: size).weight(weight)")
    && !themeSource.contains("englishDisplayFontName = \"WeiBeiStele\"")
    && !themeSource.contains("englishMonoFontName = \"WeiBeiSteleMono\""), "bundled English fonts use registered PostScript names and register before custom SwiftUI font construction")
expect(contentViewSource.contains("ResizableTwoPane<First: View, Second: View>: NSViewRepresentable"), "two-pane layout uses native bridge")
expect(contentViewSource.contains("ResizableThreePane<First: View, Second: View, Third: View>: NSViewRepresentable"), "three-pane layout uses native bridge")
expect(contentViewSource.contains("WeiBeiSplitView: NSSplitView"), "content panes use native split view")
expect(contentViewSource.contains("dividerFill.setFill()")
    && contentViewSource.contains("rect.fill()")
    && contentViewSource.contains("private var dividerFill: NSColor")
    && contentViewSource.contains("private var dividerLine: NSColor")
    && contentViewSource.contains("rect.minY + 14")
    && !contentViewSource.contains("NSColor.clear.setFill()"), "native split divider uses the current paper surface instead of a transparent hard gap")
expect(contentViewSource.contains("override func layout()"), "native split applies saved positions after first real layout")
expect(contentViewSource.contains("libraryResizeHandle"), "library pane keeps SwiftUI resize handle")
expect(contentViewSource.contains("minimumContentWidthWithLibrary"), "library leaves readable width for the workspace")
expect(contentViewSource.contains("private let railWidth = ContentRailMetrics.railOnlyWidth")
    && contentRailSource.contains("static let snapThreshold: CGFloat = 160")
    && contentRailSource.contains("static let readableWidth: CGFloat = 240")
    && contentViewSource.contains("handleExpansionRequest(store.paneExpansionRequest"), "normal multi-pane layouts snap to a restorable 88pt content rail state")
expect(!contentViewSource.contains("DragGesture()"), "content panes avoid SwiftUI drag resizing")
expect(!contentViewSource.contains(".id(store.layout)"), "layout changes avoid whole-screen identity resets")
expect(!contentViewSource.contains("PaneSeparator"), "content panes avoid hand-drawn split separators")
expect(contentViewSource.components(separatedBy: ".transition(WeiBeiTransition.rightPanel)").count >= 5
    && contentViewSource.components(separatedBy: ".transition(WeiBeiTransition.layout)").count >= 3, "right-pane visibility changes use shared transitions instead of naked tree swaps")
expect(!contentViewSource.contains("topBarContentFade"), "top bar avoids a duplicate content fade wash")
expect(contentViewSource.contains("store.toggleLibrary()")
    && contentViewSource.contains("sidebar.left")
    && contentViewSource.contains("private var libraryButton: some View")
    && contentViewSource.contains("active: store.showLibrary")
    && contentViewSource.contains("store.showLibrary ? store.ui(\"收起课程目录\"")
    && !contentViewSource.contains("恢复资料库")
    && !contentViewSource.contains(".opacity(isImmersiveLayout ? 0.45 : 1)"), "immersive top bar keeps a clear stateful library chooser instead of dimming a live control")
if let leftControlsStart = contentViewSource.range(of: "private var leftPrimaryControls: some View")?.lowerBound,
   let leftControlsEnd = contentViewSource[leftControlsStart...].range(of: "\n    }\n\n    @ViewBuilder\n    private var brandBlock")?.lowerBound {
    let leftControlsSource = String(contentViewSource[leftControlsStart..<leftControlsEnd])
    if let libraryRange = leftControlsSource.range(of: "libraryButton"),
       let navigationRange = leftControlsSource.range(of: "navigationButtons"),
       let settingsRange = leftControlsSource.range(of: "settingsMenu") {
        expect(libraryRange.lowerBound < navigationRange.lowerBound
            && navigationRange.lowerBound < settingsRange.lowerBound, "top-left controls keep library first, then back/forward, then settings")
    } else {
        expect(false, "top-left controls expose library, navigation, and settings controls")
    }
} else {
    expect(false, "top-left controls block is inspectable")
}
expect(contentViewSource.contains("WindowFullScreenReader(isFullScreen: $windowIsFullScreen)")
    && contentViewSource.contains("let isFullScreen: Bool")
    && contentViewSource.contains("TopBarLeadingInset.value(isFullScreen: isFullScreen)")
    && contentViewSource.contains("topIconButton(\"arrow.left\", help: store.ui(\"后退\"")
    && contentViewSource.contains("store.navigateBackInWorkspace()")
    && contentViewSource.contains(".keyboardShortcut(\"[\", modifiers: [.command])")
    && contentViewSource.contains("topIconButton(\"arrow.right\", help: store.ui(\"前进\"")
    && contentViewSource.contains("store.navigateForwardInWorkspace()")
    && contentViewSource.contains(".keyboardShortcut(\"]\", modifiers: [.command])")
    && contentViewSource.contains(".disabled(!store.canNavigateBack)")
    && contentViewSource.contains(".disabled(!store.canNavigateForward)"), "top bar exposes app back/forward and shifts left controls away from traffic lights outside fullscreen")
expect(contentViewSource.contains("WeiBeiHeaderHandoffFade(height: 18, opacity: isImmersiveLayout ? 0.42 : 0.34)")
    && contentViewSource.contains("paperOpacity: backgroundPaperOpacity - (isImmersiveLayout ? 0.06 : 0)")
    && contentViewSource.contains("materialOpacity: backgroundMaterialOpacity + (isImmersiveLayout ? 0.03 : 0)"), "immersive top bar keeps the same variants while using a lighter glass handoff")
expect(!contentViewSource.contains("文代笔")
    && !contentViewSource.contains("Agent中")
    && !contentViewSource.contains("对话中栏")
    && !contentViewSource.contains("对话右栏")
    && contentViewSource.contains("store.threePaneOrderLabel(compact: true)"), "top bar short layout label reflects the real draggable pane order without legacy fixed-position labels")
for helperName in ["openReader", "openWriting", "askCurrentSelection", "prepareAgentDraft"] {
    if let helperStart = contentViewSource.range(of: "private func \(helperName)")?.lowerBound,
       let helperEnd = contentViewSource[helperStart...].range(of: "\n    }\n")?.upperBound {
        let helperSource = String(contentViewSource[helperStart..<helperEnd])
        expect(!helperSource.contains("showLibrary = false"), "\(helperName) keeps a user-opened immersive library visible")
        expect(!helperSource.contains("store.layout =") && !helperSource.contains("store.showRightPane = true") && !helperSource.contains("store.showLibrary = true"), "\(helperName) routes durable layout changes through WorkspaceStore helpers")
    } else {
        expect(false, "\(helperName) source is readable")
    }
}
expect(contentViewSource.contains(".weibeiInputSurface(active: searchFocused.wrappedValue, height: controlHeight)")
    && contentViewSource.contains("prompt: Text(store.ui(\"资料内搜索\"")
    && contentViewSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && contentViewSource.contains("topIconButton(\"magnifyingglass\", help: store.ui(\"打开资料内搜索\"")
    && !contentViewSource.contains("Label(\"搜索\", systemImage: \"magnifyingglass\")")
    && contentViewSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && contentViewSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
    && !contentViewSource.contains(".foregroundColor(primaryText)\n                    .foregroundStyle(primaryText)\n                    .tint(WeiBeiTheme.link)"), "top search uses fixed ink on its paper input surface instead of inheriting top bar chrome text")
expect(contentViewSource.contains("case .compact, .glyph:\n            return 28"), "compact top bar controls keep a readable 28-point height")
expect(contentViewSource.contains("private var leftPrimaryControls: some View")
    && contentViewSource.contains("libraryButton\n\n            navigationButtons\n\n            appearanceToggleButton\n\n            settingsMenu")
    && contentViewSource.contains("private var appearanceToggleButton: some View")
    && contentViewSource.contains("topIconButton(store.appearanceMode.toggled.systemImage, help: store.appearanceMode.actionLabel(language: store.interfaceLanguage))")
    && contentViewSource.contains("store.toggleAppearanceMode()")
    && contentViewSource.contains("private var settingsMenu: some View")
    && contentViewSource.contains("Image(systemName: \"gearshape\")")
    && contentViewSource.contains(".buttonStyle(WeiBeiIconButtonStyle(size: variant == .glyph || variant == .compact ? 24 : WeiBeiMetric.iconButton))")
    && !contentViewSource.contains("WeiBeiIconButtonStyle(active: store.appearanceMode == .inkstone")
    && contentViewSource.contains("withAnimation(WeiBeiMotion.appearance) {\n                            store.setAppearanceMode(mode)")
    && contentViewSource.contains(".animation(WeiBeiMotion.appearance, value: store.appearanceMode)"), "top bar appearance toggle uses the same smooth theme animation as menu and settings")
expect(themeSource.contains("enum WeiBeiIconButtonProminence")
    && themeSource.contains("@Environment(\\.colorScheme)")
    && themeSource.contains("prominence == .primary")
    && themeSource.contains("return (isPressed || hovering) ? WeiBeiTheme.onCinnabar : WeiBeiTheme.cinnabar")
    && themeSource.contains("if isPressed || hovering {\n                return WeiBeiTheme.cinnabar.opacity(primaryOpacity(isPressed: isPressed))")
    && themeSource.contains("? WeiBeiTheme.paperInset.opacity(0.58)\n                : WeiBeiTheme.cinnabarSoft.opacity(0.72)")
    && themeSource.contains("if active { return WeiBeiTheme.cinnabar }")
    && themeSource.contains("colorScheme == .dark ? 0.34 : 0.28")
    && themeSource.contains(".onHover { isHovering in"), "icon buttons share adaptive neutral, selected, primary, hover and press states across light and dark modes")
expect(contentViewSource.contains("private var hasReaderScopedTopActions: Bool")
    && contentViewSource.contains("store.isPaneToggleActive(.reader)")
    && contentViewSource.contains("store.hasSelectedMaterial && hasReaderScopedTopActions")
    && contentViewSource.contains("store.canCopyReference && hasReaderScopedTopActions"), "top material search and reference actions stay scoped to reader-first layouts")
expect(contentViewSource.contains("if shouldShowSearchAction && !store.showReaderSearch"), "top bar hides the search icon while the search field is already open")
expect(contentViewSource.contains("private var paneToggleCluster: some View")
    && contentViewSource.contains("store.toggleReader()")
    && contentViewSource.contains("store.toggleAgent()")
    && contentViewSource.contains("store.toggleNotes()"), "top bar exposes persistent reader, chat, and notes pane toggles")
expect(!contentViewSource.contains("private var layoutMenu")
    && !contentViewSource.contains(".accessibilityLabel(Text(store.ui(\"切换布局\"")
    && contentViewSource.contains("case .balanced, .wide:")
    && contentViewSource.contains("Text(shortLayoutLabel)"), "top bar keeps layout status in the brand block and removes the legacy layout dropdown")
expect(contentViewSource.contains(".accessibilityLabel(Text(store.ui(\"设置\""), "top bar settings menu has a readable semantic label")
expect(contentViewSource.contains("Section(store.ui(\"文稿\", \"Document\"))")
    && contentViewSource.contains("get: { store.adaptImportedDocumentColors }")
    && contentViewSource.contains("set: { store.setImportedDocumentColorAdaptation($0) }")
    && contentViewSource.contains("Label(store.ui(\"导入文稿适配\", \"Adapt Imported Documents\"), systemImage: \"eyeglasses\")"), "settings exposes one persistent imported-document adaptation toggle")
expect(contentViewSource.contains("private var agentPaneToggleHelp: String")
    && contentViewSource.contains("用当前选区打开对话")
    && contentViewSource.contains("store.isPaneToggleActive(.agent)")
    && !contentViewSource.contains("topIconButton(\"bubble.left.and.text.bubble.right\", help: agentButtonHelp)")
    && contentViewSource.contains("Section(store.ui(\"对话形态\", \"Chat Surface\")")
    && !contentViewSource.contains("Section(\"Agent 入口\")")
    && !contentViewSource.contains("打开 Agent 对话区"), "top bar names conversation entry by the actual action instead of a generic agent label")
expect(contentViewSource.contains("private var showsGlobalFloatingAgent: Bool")
    && !contentViewSource.contains("if store.isConversationSurfaceVisible {\n            return false\n        }")
    && contentViewSource.contains("SelectionFloatingAgentPlacement.isVisible")
    && contentViewSource.contains("routesToConversation: store.isConversationSurfaceVisible"), "global selection prompt can appear beside the selected text while a formal conversation surface is already visible")
expect(themeSource.contains("language.text(\"标准\"")
    && themeSource.contains("language.text(\"紧凑\"")
    && themeSource.contains("language.text(\"印记\"")
    && themeSource.contains("\"Mark\"")
    && !themeSource.contains("甲 纸脊")
    && !themeSource.contains("乙 窄栏")
    && !themeSource.contains("丁 图形"), "top bar variants use user-facing style names instead of internal prototypes")
let sidebarSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/SidebarView.swift")
let sidebarSource = (try? String(contentsOf: sidebarSourceURL, encoding: .utf8)) ?? ""
expect(sidebarSource.contains("Text(store.ui(\"课程目录\", \"Course Index\")")
    && sidebarSource.contains("prompt: Text(store.ui(\"搜索当前课程\"")
    && sidebarSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && sidebarSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "course index search uses current-course language with readable ink")
let notesAgentSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/NotesAgentView.swift")
let notesAgentSource = (try? String(contentsOf: notesAgentSourceURL, encoding: .utf8)) ?? ""
expect(notesAgentSource.contains("private var noteRailItems: [ContentRailItem]")
    && notesAgentSource.contains("NoteEditorCommand(kind: .scrollToHeading")
    && notesAgentSource.contains("private var agentRailItems: [ContentRailItem]")
    && notesAgentSource.contains("store.requestPaneExpansion(.agent)")
    && notesAgentSource.components(separatedBy: "let railOnly = store.layout.allowsRailOnlyPanes").count >= 3, "notes and conversation share the content rail and navigate after restoring a narrow pane")
let notePaneHeaderSource: String = {
    guard let start = notesAgentSource.range(of: "struct NotePaneView: View")?.lowerBound,
          let end = notesAgentSource.range(of: "private func noteFileStatusColor", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let noteModeControlSource: String = {
    guard let start = notesAgentSource.range(of: "private var noteModeControl: some View")?.lowerBound,
          let end = notesAgentSource.range(of: "private var noteHeaderSubtitle", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let agentPaneHeaderSource: String = {
    guard let start = notesAgentSource.range(of: "struct AgentPaneView: View")?.lowerBound,
          let end = notesAgentSource.range(of: "private var agentPrompt", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let paneHeaderReorderSource: String = {
    guard let start = notesAgentSource.range(of: "struct PaneHeaderReorderModifier")?.lowerBound,
          let end = notesAgentSource.range(of: "private struct AgentComposerField", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let emptyAgentStateSource: String = {
    guard let start = notesAgentSource.range(of: "private var emptyAgentState: some View")?.lowerBound,
          let end = notesAgentSource.range(of: "private func starterChip", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let railBackgroundSource: String = {
    guard let start = notesAgentSource.range(of: "private var railBackground: some View")?.lowerBound,
          let end = notesAgentSource.range(of: "private var separatorAlignment", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let notebookCreationPanelSource: String = {
    guard let start = notesAgentSource.range(of: "private struct NotebookCreationPanel")?.lowerBound,
          let end = notesAgentSource.range(of: "final class MarkdownSourceTextView", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
expect(notesAgentSource.contains("private struct AgentComposerField")
    && notesAgentSource.contains("prompt: Text(prompt)")
    && notesAgentSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)"), "agent tray placeholder uses native prompt text so the cursor and text baseline align")
expect(notesAgentSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)")
    && !notesAgentSource.contains("SelectionAnchorCoordinate.y(")
    && !notesAgentSource.contains("contentView.convert("), "note source editor selection anchors use the shared coordinate helper")
expect(notesAgentSource.contains("onSelectionChange(\"\", nil)")
    && notesAgentSource.contains("guard range.length > 0, let stringRange = Range(range, in: textView.string) else"),
    "note source editor clears stale floating selection state when text selection is removed")
expect(notesAgentSource.contains("applySourcePresentation(")
    && notesAgentSource.contains("in textView: NSTextView")
    && notesAgentSource.contains("calloutControlRegex")
    && notesAgentSource.contains(#"(?m)^(\s*(?:>\s*)*)"#)
    && notesAgentSource.contains(#"(\\?\[![A-Za-z][A-Za-z0-9_-]*\][+-]?\s*)"#)
    && notesAgentSource.contains("let markerColor = NSColor.clear")
    && notesAgentSource.contains("NSFont.monospacedSystemFont(ofSize: 0.1")
    && notesAgentSource.contains(".baselineOffset: 0"), "source and compare mode collapse Obsidian callout control markers, including trailing source spaces, without changing saved markdown")
expect(notesAgentSource.contains("private func refreshSourcePresentation(in textView: NSTextView)")
    && notesAgentSource.contains("refreshSourcePresentation(in: textView)")
    && notesAgentSource.contains("case .applyAgentPatch")
    && notesAgentSource.contains("case .insertMarkdown"), "source editor refreshes callout presentation after agent, command, or attachment insertions")
expect(!sidebarSource.contains("commandPalettePresented.toggle()") && !sidebarSource.contains("Label(\"命令\", systemImage: \"command\")"), "sidebar does not duplicate the command palette entry")
expect(sidebarSource.contains("ScrollView(showsIndicators: false)"), "sidebar hides the heavy system scroll indicator that reads as a divider")
expect(sidebarSource.contains("sidebarSection(title: store.ui(\"我的资料\"") && sidebarSource.contains("sidebarSection(title: store.ui(\"我的笔记\""), "sidebar separates user materials from notebook notes")
expect(sidebarSource.contains("!$0.isSample && !$0.isNotebookNote") && sidebarSource.contains("store.filteredItems.filter(\\.isNotebookNote)"), "sidebar material list excludes notebook notes without hiding notes")
expect(sidebarSource.contains("item.isNotebookNote ? store.activeNotebookItemID == item.id : store.selectedItemID == item.id"), "sidebar highlights the active notebook note separately from the selected reader material")
expect(sidebarSource.contains(".contextMenu")
    && sidebarSource.contains("Button(store.ui(\"重命名笔记\"")
    && sidebarSource.contains("store.promptRenameNotebookNote(itemID: item.id)")
    && sidebarSource.contains("private struct NotebookRenameRow")
    && sidebarSource.contains("store.confirmRenameNotebookNote()")
    && sidebarSource.contains("store.cancelRenameNotebookNote()"), "notebook notes expose inline rename from the library row context menu")
expect(sidebarSource.contains("private var tags: [String]")
    && sidebarSource.contains("store.displayTags(for: item)")
    && sidebarSource.contains("Text(tags.joined(separator: \" \"))")
    && sidebarSource.contains(".frame(height: tags.isEmpty ? 48 : 58)"), "notebook rows surface Markdown tags without adding a separate tag management panel")
expect(contentViewSource.contains("topIconButton(\"command\", help: store.ui(\"命令面板\""), "top bar keeps the command palette entry")
let commandPaletteSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/CommandPaletteView.swift")
let commandPaletteSource = (try? String(contentsOf: commandPaletteSourceURL, encoding: .utf8)) ?? ""
expect(commandPaletteSource.contains(".weibeiInputSurface(active: searchFocused, height: 36)")
    && commandPaletteSource.contains("prompt: Text(store.ui(\"输入命令\"")
    && commandPaletteSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && commandPaletteSource.contains("WeiBeiTheme.hairline.opacity(0.72)")
    && !commandPaletteSource.contains("Divider()"), "command palette search uses WeiBei input surface and semantic hairline")
expect(commandPaletteSource.contains("ScrollView(showsIndicators: false)"), "command palette hides system scroll indicators inside the transient floating panel")
expect(commandPaletteSource.contains("withAnimation(command.animation)") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "command palette uses layout motion for layout commands")
expect(commandPaletteSource.contains("PaletteCommand(title: store.ui(\"三栏工作台\", \"Three-Pane Workspace\"), shortcut: \"⌥⌘1\"")
    && !commandPaletteSource.contains("WorkspaceLayout.documentNotesAgent.label")
    && commandPaletteSource.contains("WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage), shortcut: \"⌥⌘2\"")
    && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"交换笔记与对话\"")
    && commandPaletteSource.contains("shortcut: \"⌥⌘S\"")
    && commandPaletteSource.contains("store.swapThreePaneSecondaryPanes()"), "command palette exposes one draggable three-pane workspace entry instead of two fixed three-pane presets")
expect(commandPaletteSource.contains("PaletteCommand(title: store.ui(\"聚焦对话\"")
    && !commandPaletteSource.contains("PaletteCommand(title: \"聚焦 Agent\""), "command palette names the conversation pane by task language")
expect(!commandPaletteSource.contains("收起右栏"), "command palette avoids fixed right-pane wording")
expect(!commandPaletteSource.contains("Agent 整理资料与笔记") && !commandPaletteSource.contains("本地排序资料库"), "command palette avoids half-built library organization shortcuts")
expect(commandPaletteSource.contains("store.showLibrary ? store.ui(\"收起课程目录\"")
    && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"聚焦课程目录\"")
    && !commandPaletteSource.contains("恢复资料"), "command palette names the course index toggle as an explicit course action")
expect(!commandPaletteSource.contains("PaletteCommand(title: \"顶栏") && contentViewSource.contains("Section(store.ui(\"顶部栏\""), "top bar variants live in the settings menu instead of the command palette")
expect(commandPaletteSource.contains("private var rightPaneCommand: PaletteCommand?") && commandPaletteSource.contains("store.layout.hasCollapsibleRightPane"), "command palette hides right pane command when the layout has no auxiliary pane")
expect(commandPaletteSource.contains("收起辅助栏") && commandPaletteSource.contains("展开辅助栏"), "command palette names auxiliary pane action by current state")
expect(commandPaletteSource.contains("title: store.showRightPane ? store.ui(\"收起辅助栏\"")
    && commandPaletteSource.contains("shortcut: \"⌘J\"")
    && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "command palette auxiliary pane command uses layout motion")
expect(commandPaletteSource.contains("if store.canCopyReference")
    && commandPaletteSource.contains("PaletteCommand(title: store.copyReferenceActionTitle")
    && commandPaletteSource.contains("if store.hasSelectedMaterial")
    && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"打开资料内搜索\""), "command palette names copy-reference by the actual current target")
expect(appSource.contains("Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }")
    && contentViewSource.contains("topIconButton(\"quote.opening\", help: store.copyReferenceActionTitle)"), "top bar and app menu share the same copy-reference wording")
expect(commandPaletteSource.contains("private var canSendAgentDraft: Bool") && commandPaletteSource.contains("PaletteCommand(title: store.sendAgentActionTitle"), "command palette hides the agent send command until a draft exists")
expect(commandPaletteSource.contains("if store.canApplyAgentAnswer") && commandPaletteSource.contains("if store.canReplaceNoteSelection") && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"替换笔记选区\""), "command palette hides agent answer actions until they can work")
if let selectionCommandStart = commandPaletteSource.range(of: "PaletteCommand(title: store.ui(\"问当前选区\"")?.lowerBound,
   let selectionCommandEnd = commandPaletteSource[selectionCommandStart...].range(of: "\n            })")?.upperBound {
    let selectionCommandSource = String(commandPaletteSource[selectionCommandStart..<selectionCommandEnd])
    expect(commandPaletteSource.contains("if store.selectionContext != nil")
        && selectionCommandSource.contains("store.askSelection()")
        && !selectionCommandSource.contains("askAgent()"), "command palette selection action attaches the selection without auto-sending a generated prompt")
} else {
    expect(false, "command palette selection command is inspectable")
}
expect(commandPaletteSource.contains("if store.canOpenSelectedSourceReference") && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"打开选区来源\""), "command palette exposes source jump only for parseable note references")
expect(commandPaletteSource.contains("if store.canUseSelectionAgentSurface") && commandPaletteSource.contains("items.insert(agentSurfaceCommand(.selectionFloat, shortcut: \"⌃⌥3\")"), "command palette only exposes selection-float mode when an anchored selection exists")
expect(commandPaletteSource.contains("private func agentSurfaceCommand(_ surface: AgentSurface, shortcut: String)")
    && commandPaletteSource.contains("surface.actionLabel")
    && !commandPaletteSource.contains("Agent 底部抽屉")
    && !commandPaletteSource.contains("Agent 右下角小窗")
    && !commandPaletteSource.contains("Agent 划线浮层")
    && !commandPaletteSource.contains("Agent 静默洞察"), "command palette uses user-facing agent surface actions instead of internal surface names")
expect(commandPaletteSource.contains("if store.agentSurface != .hidden") && commandPaletteSource.contains("agentSurfaceCommand(.hidden, shortcut: \"⌃⌥0\")"), "command palette hides the agent hide action when already hidden")
let readerViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ReaderView.swift")
let readerViewSource = (try? String(contentsOf: readerViewSourceURL, encoding: .utf8)) ?? ""
expect(readerViewSource.contains("private final class PDFContentRailPreviewLoader")
    && readerViewSource.contains("page.thumbnail(of:")
    && readerViewSource.contains("static let contentRailScript")
    && readerViewSource.contains("window.WeiBeiContentRail")
    && readerViewSource.contains("if railOnly {\n            store.requestPaneExpansion(.reader)"), "PDF and HTML rails use real page or document content and restore narrow reader panes")
let selectionAnchorContentPointSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/SelectionAnchorContentPoint.swift")
let selectionAnchorContentPointSource = (try? String(contentsOf: selectionAnchorContentPointSourceURL, encoding: .utf8)) ?? ""
expect(selectionAnchorContentPointSource.contains("static func fromLocalPoint")
    && selectionAnchorContentPointSource.contains("static func fromWebPoint")
    && selectionAnchorContentPointSource.contains("static func fromScreenPoint")
    && selectionAnchorContentPointSource.contains("SelectionAnchorCoordinate.y"), "selection anchors use one AppKit-to-SwiftUI coordinate helper")
expect(readerViewSource.contains("readerStyleScript"), "html reader injects responsive reading style")
expect(readerViewSource.contains("overflow-wrap: anywhere"), "html reader prevents narrow-pane clipping")
expect(!readerViewSource.contains("Bundle.module.url(forResource: \"WeiBeiStele\", withExtension: \"ttf\")")
    && !readerViewSource.contains("font-family: \"WeiBeiStele\"")
    && !readerViewSource.contains("h1, h2, h3 { font-family:")
    && readerViewSource.contains("readerStyleScript"), "html reader keeps imported document fonts instead of injecting bundled WeiBei display fonts into file headings")
expect(readerViewSource.contains("color-scheme: light")
    && readerViewSource.contains("color-scheme: dark")
    && readerViewSource.contains("color: #1d1814 !important")
    && readerViewSource.contains("color: #D7CBB0 !important")
    && readerViewSource.contains("a { color: #C8B98A !important;"), "html reader injects readable light and inkstone dark styles over imported documents")
expect(readerViewSource.contains("::selection { background: rgba(145, 38, 27, 0.20); color: #1d1814; }"), "html reader uses the WeiBei cinnabar selection color instead of the default blue highlight")
expect(readerViewSource.contains("document.addEventListener(\"selectionchange\", reportSelection)")
    && readerViewSource.contains("document.addEventListener(\"pointerdown\", () => {")
    && readerViewSource.contains("lastPayload = { text: \"\", x: null, y: null }")
    && readerViewSource.contains("window.requestAnimationFrame")
    && readerViewSource.contains("window.webkit.messageHandlers.selection.postMessage(payload)")
    && readerViewSource.contains("x: rect && text ? rect.left + rect.width / 2 : null")
    && readerViewSource.contains("y: rect && text ? rect.bottom : null")
    && readerViewSource.contains("messageHandlers?.selection?.postMessage")
    && readerViewSource.contains("if (window.weiBeiSuppressSelectionReport) return;")
    && readerViewSource.contains("window.weiBeiSuppressSelectionReport = true;")
    && readerViewSource.contains("x: null,")
    && readerViewSource.contains("y: null"), "html reader reports selection changes live and also clears the floating agent when selection is empty")
expect(readerViewSource.contains("controller.add(context.coordinator, name: \"appShortcut\")")
    && readerViewSource.contains("static let appShortcutScript")
    && readerViewSource.contains("[\"1\", \"2\", \"3\", \"a\", \"n\", \"r\", \"t\"].includes(key)")
    && readerViewSource.contains("[\"1\", \"2\", \"3\", \"4\", \"[\", \"]\", \"b\", \"j\", \"k\", \"f\"].includes(key)")
    && readerViewSource.contains("store.handleAppShortcut(key: key, modifiers: modifiers)")
    && readerViewSource.contains("removeScriptMessageHandler(forName: \"appShortcut\")"), "html reader forwards app keyboard shortcuts while the web document has focus")
expect(!readerViewSource.contains("readerHeader") && !readerViewSource.contains("statusBar"), "reader avoids duplicate internal chrome under unified top bar")
expect(readerViewSource.contains("ReaderStateMessage") && !readerViewSource.contains("ContentUnavailableView("), "reader empty states use WeiBei paper styling")
expect(readerViewSource.contains("store.selectedMaterialItem?.kind == .pdf") && readerViewSource.contains("if let item = store.selectedMaterialItem"), "reader renders materials, not notebook notes")
expect(readerViewSource.contains("NotebookSelectedReaderView") && readerViewSource.contains("阅读区只显示资料"), "reader explains notebook selection instead of rendering it as material")
expect(readerViewSource.contains("ZStack(alignment: .bottomTrailing)")
    && readerViewSource.contains(".padding(.trailing, isImmersive ? 18 : 10)")
    && readerViewSource.contains(".padding(.bottom, isImmersive ? 18 : 12)")
    && readerViewSource.contains("pdfFloatingControls")
    && !readerViewSource.contains("ZStack(alignment: .bottomLeading)")
    && !readerViewSource.contains("ZStack(alignment: .trailing)"), "pdf controls sit on the bottom-right page edge instead of covering the reading start")
expect(readerViewSource.contains("pdfControlsHovering")
    && readerViewSource.contains("pdfControlsExpanded")
    && readerViewSource.contains("pdfControlsCollapseToken")
    && readerViewSource.contains("private var pdfControlsActive: Bool")
    && readerViewSource.contains("private var pdfControlsActive: Bool {\n        pdfControlsExpanded\n    }")
    && readerViewSource.contains(".onAppear {\n            schedulePDFControlsCollapse(after: 0.9)\n        }")
    && readerViewSource.contains("PDFModeChipPresentation.fillOpacity(isExpanded: pdfControlsExpanded, isHovering: pdfControlsHovering)")
    && readerViewSource.contains("PDFModeChipPresentation.controlOpacity(isExpanded: pdfControlsExpanded, isHovering: pdfControlsHovering)")
    && readerViewSource.contains(".offset(x: 0)")
    && readerViewSource.contains(".scaleEffect(pdfControlsExpanded ? 1 : 0.985, anchor: .trailing)")
    && readerViewSource.contains(".onHover")
    && readerViewSource.contains("if !hovering {\n                schedulePDFControlsCollapse(after: 0.28)\n            }")
    && readerViewSource.contains("revealPDFControls(collapseAfter: 0.85)")
    && readerViewSource.contains("private func collapsePDFControls()")
    && readerViewSource.contains("pdfControlsHovering = false")
    && readerViewSource.contains("guard pdfControlsCollapseToken == token else { return }")
    && !readerViewSource.contains("if hovering {\n                revealPDFControls()\n            }")
    && !readerViewSource.contains("guard pdfControlsCollapseToken == token, !pdfControlsHovering else { return }")
    && !readerViewSource.contains("pdfControlsHovering || pdfControlsExpanded"), "pdf controls stay low-distraction and collapse after pointer idle instead of sticking open")
expect(!readerViewSource.contains("var label: String")
    && !readerViewSource.contains("var help: String")
    && readerViewSource.contains("func label(language: WeiBeiInterfaceLanguage) -> String")
    && readerViewSource.contains("return language.text(\"滚动\", \"Scroll\")")
    && readerViewSource.contains("func help(language: WeiBeiInterfaceLanguage) -> String")
    && readerViewSource.contains("return language.text(\"连续滚动浏览 PDF\", \"continuous PDF scrolling\")")
    && readerViewSource.contains("case .scroll: \"arrow.up.and.down\"")
    && readerViewSource.contains("case .page: \"rectangle.portrait\"")
    && readerViewSource.contains("private var pdfModeToggle: some View")
    && readerViewSource.contains("private var showsPDFModeLabel: Bool")
    && readerViewSource.contains("PDFModeChipPresentation.showsLabel(isExpanded: pdfControlsExpanded)")
    && readerViewSource.contains("if pdfBrowseMode == .page, pdfPageCount > 1")
    && readerViewSource.contains("private func revealPDFControls")
    && readerViewSource.contains("DispatchQueue.main.asyncAfter")
    && readerViewSource.contains("pdfBrowseMode = pdfBrowseMode.toggled")
    && readerViewSource.contains("Image(systemName: pdfBrowseMode.systemImage)")
    && readerViewSource.contains("if showsPDFModeLabel {\n                    Text(pdfBrowseMode.label(language: store.interfaceLanguage))")
    && readerViewSource.contains("private var pdfModeForeground: Color")
    && readerViewSource.contains("return WeiBeiTheme.secondaryInk")
    && readerViewSource.contains(".frame(width: showsPDFModeLabel ? nil : 18, height: 24)")
    && readerViewSource.contains(".accessibilityLabel(Text(store.ui(\"切换 PDF 浏览方式")
    && !readerViewSource.contains("ForEach(PDFBrowseMode.allCases)")
    && !readerViewSource.contains("Button(mode.label)")
    && !readerViewSource.contains("case .scroll: \"连续\""), "pdf mode control uses one compact readable toggle instead of a bulky two-choice segment")
expect(readerViewSource.components(separatedBy: "WeiBeiQuietScrollers.configureRecursively(\n                in: view,\n                hasVerticalScroller: true,\n                hasHorizontalScroller: false\n            )").count >= 3
    && readerViewSource.components(separatedBy: "WeiBeiQuietScrollers.flashRecursively(in: view, repeatCount: 2)").count >= 3, "pdf reader keeps a vertical overlay scrollbar available and flashes it when loading or switching modes")
expect(readerViewSource.contains(".accessibilityLabel(Text(store.ui(\"上一页\"") && readerViewSource.contains(".accessibilityLabel(Text(store.ui(\"下一页\""), "pdf page controls have readable icon labels")
expect(readerViewSource.contains(".keyboardShortcut(\"[\", modifiers: [.command, .option])")
    && readerViewSource.contains(".keyboardShortcut(\"]\", modifiers: [.command, .option])"), "pdf page shortcuts yield command-brackets to workspace history")
expect(!readerViewSource.contains(".disabled(pdfPageIndex"), "pdf pager keeps arrows visible instead of showing grey dead buttons")
expect(readerViewSource.contains("syncReaderLocationTitle")
    && readerViewSource.contains("store.updateReaderPageIndex(pdfPageIndex)")
    && readerViewSource.components(separatedBy: "store.recordReaderPageNavigationPoint()").count >= 3
    && readerViewSource.contains("let next = PageNavigator.previous(pdfPageIndex)")
    && readerViewSource.contains("let next = PageNavigator.next(pdfPageIndex, pageCount: pdfPageCount)")
    && readerViewSource.components(separatedBy: "guard next != pdfPageIndex else { return }").count >= 3
    && readerViewSource.contains("第 \\(pdfPageIndex + 1) 页"), "pdf reader page updates feed shared reference title and app navigation history")
expect(readerViewSource.contains("var onSelectionChange: (String, CGPoint?, Int) -> Void") && readerViewSource.contains("pageIndex(for: selection, in: view)") && readerViewSource.contains("ownerTitle: ownerTitle"), "pdf selection source uses the selected page, not only the current page")
expect(readerViewSource.contains("private final class ReaderPDFView: PDFView")
    && readerViewSource.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool")
    && readerViewSource.contains("window?.makeFirstResponder(self)")
    && readerViewSource.contains("var reportCurrentSelection: (() -> Void)?")
    && readerViewSource.contains("override func mouseDragged(with event: NSEvent)")
    && readerViewSource.contains("override func mouseUp(with event: NSEvent)")
    && readerViewSource.contains("let view = ReaderPDFView()"), "native PDF text selection accepts first drag and focuses the PDF view instead of losing the first gesture")
if let pdfViewStart = readerViewSource.range(of: "private final class ReaderPDFView: PDFView")?.lowerBound,
   let pdfViewEnd = readerViewSource[pdfViewStart...].range(of: "\n}\n\nextension PDFReaderRepresentable.Coordinator")?.upperBound {
    let readerPDFViewSource = String(readerViewSource[pdfViewStart..<pdfViewEnd])
    expect(readerPDFViewSource.contains("super.mouseDown(with: event)\n        reportCurrentSelection?()")
        && !readerPDFViewSource.contains("clearSelection()"), "PDF mouse down lets PDFKit handle native text selection before reporting instead of clearing the selection first")
    expect(readerPDFViewSource.contains("override func draw(_ page: PDFPage, to context: CGContext)")
        && readerPDFViewSource.contains("guard adaptsDocumentColors else")
        && readerPDFViewSource.contains("super.draw(page, to: context)")
        && readerPDFViewSource.contains("context.setFillColor(adaptedPaperColor.cgColor)")
        && readerPDFViewSource.contains("context.setBlendMode(.multiply)")
        && readerPDFViewSource.contains("page.draw(with: displayBox, to: context)")
        && readerPDFViewSource.contains("layoutDocumentView()")
        && readerPDFViewSource.contains("if let documentView")
        && !readerPDFViewSource.contains("pageOverlayViewProvider"), "PDF color adaptation redraws visible pages below native selection and OCR overlays, with an immediate original-color path")
} else {
    expect(false, "ReaderPDFView source is inspectable")
}
expect(readerViewSource.contains("func reportCurrentSelection(in view: PDFView)")
    && readerViewSource.contains("view.reportCurrentSelection = { [weak coordinator = context.coordinator, weak view] in")
    && readerViewSource.contains("coordinator?.reportCurrentSelection(in: view)")
    && readerViewSource.contains("NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])")
    && readerViewSource.contains("if event.type == .leftMouseDown")
    && readerViewSource.contains("view.bounds.contains(location)")
    && readerViewSource.contains("NSEvent.removeMonitor(eventMonitor)"), "PDF selection reporting polls currentSelection after PDFKit internal drag gestures instead of relying only on outer PDFView mouse events")
expect(readerViewSource.contains("PDFPageOverlayViewProvider")
    && readerViewSource.contains("PDFOCRPageOverlayView")
    && readerViewSource.contains("private func setOCRPageOverlayProvider(_ provider: PDFPageOverlayViewProvider?, in view: PDFView)")
    && readerViewSource.contains("view.pageOverlayViewProvider = provider")
    && readerViewSource.contains("view.isInMarkupMode = false"), "scanned PDF OCR overlays are only enabled for image-only PDFs and cleared for native text PDFs")
if let pageOverlayStart = readerViewSource.range(of: "private final class PDFOCRPageOverlayView")?.lowerBound,
   let lineTextStart = readerViewSource.range(of: "private final class PDFOCRLineTextView")?.lowerBound {
    let pageOverlaySource = String(readerViewSource[pageOverlayStart..<lineTextStart])
    let lineTextSource = String(readerViewSource[lineTextStart...])
    expect(pageOverlaySource.contains("override var isFlipped: Bool { false }")
        && !lineTextSource.contains("override var isFlipped"), "PDF OCR page overlay keeps PDF coordinates while line text views keep native NSTextView hit testing")
} else {
    expect(false, "PDF OCR overlay source is readable")
}
expect(readerViewSource.contains("private class ReaderSelectableTextView: NSTextView")
    && readerViewSource.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool")
    && readerViewSource.contains("override func mouseDown(with event: NSEvent)")
    && readerViewSource.contains("window?.makeFirstResponder(self)")
    && readerViewSource.contains("private final class PDFOCRLineTextView: ReaderSelectableTextView")
    && readerViewSource.components(separatedBy: "let textView = ReaderSelectableTextView()").count >= 3
    && !readerViewSource.contains("let textView = NSTextView()"), "PDF OCR, sample PDF, and plain text readers accept first mouse for immediate drag selection")
expect(readerViewSource.contains("private var ocrHighlightedLinesByPageIndex: [Int: Set<Int>] = [:]")
    && readerViewSource.contains("func applySearch(_ query: String, in view: PDFView, force: Bool = false)")
    && readerViewSource.contains("applyOCRSearch(query, in: view)")
    && readerViewSource.contains("line.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])")
    && readerViewSource.contains("highlightedLineIndexes: ocrHighlightedLinesByPageIndex[index] ?? []")
    && readerViewSource.contains("view.go(to: page)")
    && readerViewSource.contains("self.applySearch(self.lastSearchQuery, in: view, force: true)"), "scanned PDF OCR search falls back to recognized lines, jumps to the first OCR hit, and highlights the matching line")
expect(readerViewSource.contains("view.highlightedSelections = matches")
    && readerViewSource.contains("view.go(to: first)")
    && !readerViewSource.contains("view.setCurrentSelection(first, animate: true)"), "PDF search highlights and jumps without creating a fake user selection or selection-agent context")
expect(readerViewSource.contains("@State private var pdfHasSelectableText: Bool?")
    && readerViewSource.contains("var onSelectableTextChange: (Bool?) -> Void")
    && readerViewSource.contains("private var nativeTextPageIndexes: Set<Int> = []")
    && readerViewSource.contains("private var pendingOCRPageIndexes: Set<Int> = []")
    && readerViewSource.contains("private static func selectableTextPageIndexes")
    && readerViewSource.contains("private static func ocrCandidatePageIndexes")
    && readerViewSource.contains("PDFOCRTextExtractor.pages(from: document, pageIndexes: pageIndexes)")
    && readerViewSource.contains("private func ensureOCRForCurrentPage(in view: PDFView)")
    && readerViewSource.contains("PDFOCRTextExtractor.pages(from: document, pageIndexes: [index])")
    && readerViewSource.contains("self.configureOCROverlays(for: document, generation: generation, in: view)\n                    self.ensureOCRForCurrentPage(in: view)")
    && readerViewSource.contains("self.ensureOCRForCurrentPage(in: view)")
    && readerViewSource.contains("onSelectableTextChange(nativeTextPageIndexes.contains(index) || ocrPagesByPageIndex[index] != nil)")
    && readerViewSource.contains("Text(store.ui(\"未检测到可选文本层\"")
    && readerViewSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)")
    && readerViewSource.contains(".allowsHitTesting(false)")
    && !readerViewSource.contains("configureOCROverlays(for: document, hasTextLayer:"), "pdf reader reports selectable text per page so mixed text/scanned PDFs still get OCR overlays")
expect(readerViewSource.contains("selection.color = WeiBeiNativePalette.selectionFill(for: appearanceMode)"), "pdf reader applies the theme-aware WeiBei cinnabar selection tint to the active PDFKit selection")
expect(readerViewSource.contains("onSelectionChange(\"\", nil, pageIndex.wrappedValue)"), "pdf reader clears the floating selection agent when PDF selection is removed")
expect(readerViewSource.contains("private func reportSelectionAfterDragSettles")
    && readerViewSource.contains("selectionWork?.cancel()")
    && readerViewSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.06")
    && !readerViewSource.contains("self.onSelectionChange(text, Self.anchor(for: selection, in: view), selectedPageIndex)"), "pdf reader delays the floating agent callback until dragging settles so selection is not interrupted")
expect(readerViewSource.contains("if let url = item.url {\n                    PDFReaderRepresentable(")
    && readerViewSource.contains("SamplePDFView(appearanceMode: store.appearanceMode, language: store.interfaceLanguage)")
    && readerViewSource.contains("SamplePDFSelectablePageView")
    && readerViewSource.contains("textView.isSelectable = true")
    && readerViewSource.contains("textView.delegate = context.coordinator")
    && readerViewSource.contains("coordinator.appliedAppearanceMode != appearanceMode")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)"), "pdf samples prefer the real PDFKit reader while keeping a selectable fallback page")
expect(readerViewSource.contains("textView.selectedTextAttributes")
    && readerViewSource.contains(".backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode)")
    && readerViewSource.contains(".foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode)")
    && readerViewSource.contains("onSelectionChange(\"\", nil)"), "plain text reader uses WeiBei selection color and clears stale floating selection")
expect(readerViewSource.contains("private var suppressSelectionReport = false")
    && readerViewSource.contains("guard !suppressSelectionReport else { return }")
    && readerViewSource.contains("suppressSelectionReport = true\n            textView.setSelectedRange(range)\n            suppressSelectionReport = false"), "plain text search can scroll to a hit without reporting it as a user selection")
expect(readerViewSource.contains("SelectionAnchorContentPoint.fromLocalPoint(localPoint, in: view)")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)")
    && !readerViewSource.contains("SelectionAnchorCoordinate.y(")
    && !readerViewSource.contains("contentView.convert("), "reader selection anchors route PDF, HTML, and text through the shared coordinate helper")
expect(readerViewSource.contains("private var importedDocumentAdaptationControl: some View")
    && readerViewSource.contains("item.url != nil")
    && readerViewSource.contains("item.kind == .pdf || item.kind == .html")
    && readerViewSource.contains("Image(systemName: \"eyeglasses\")")
    && readerViewSource.contains("WeiBeiIconButtonStyle(active: store.adaptImportedDocumentColors, size: 22)")
    && readerViewSource.contains("store.toggleImportedDocumentColorAdaptation()"), "DOC hover title offers a quiet stateful adaptation control only for imported PDF and HTML materials")
let readerStyleScriptSource: String = {
    guard let start = readerViewSource.range(of: "static func readerStyleScript")?.lowerBound,
          let end = readerViewSource.range(of: "final class Coordinator", range: start..<readerViewSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(readerViewSource[start..<end])
}()
expect(readerViewSource.contains("static func readerStyleScript(for mode: WeiBeiAppearanceMode, adaptsDocumentColors: Bool = true)")
    && readerViewSource.contains("document.documentElement.dataset.weibeiTheme = adaptsDocumentColors ? appearance : \"original\"")
    && readerViewSource.contains("[data-weibei-paper-surface] { background-color: transparent !important; }")
    && readerViewSource.contains(".slice(0, 2500)")
    && readerViewSource.contains("element.removeAttribute(\"data-weibei-paper-surface\")")
    && !readerStyleScriptSource.contains("MutationObserver"), "HTML adaptation is reversible and bounds its one-time near-white surface pass without a persistent DOM observer")
expect(readerViewSource.contains("pendingPDFPageIndex") && readerViewSource.contains("applyPendingPDFPageIfReady") && readerViewSource.contains("store.readerTargetPageIndex = nil"), "pdf reader consumes source-jump target pages")
expect(readerViewSource.contains("onSourceReference: { reference in store.openSourceReference(reference) }"), "markdown reader source references can jump back to material")
expect(readerViewSource.contains("private struct SamplePDFView")
    && readerViewSource.contains("ScrollView {")
    && !readerViewSource.contains("SamplePDFView: View {\n    var body: some View {\n        ScrollView(showsIndicators: false)"), "sample pdf page keeps the system scroll indicator available")
let richEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/RichMarkdownEditorView.swift")
let richEditorSource = (try? String(contentsOf: richEditorSourceURL, encoding: .utf8)) ?? ""
expect(richEditorSource.contains("let editorDirectory = url.deletingLastPathComponent()")
    && richEditorSource.contains("view.loadFileURL(url, allowingReadAccessTo: editorDirectory.deletingLastPathComponent())"), "rich Markdown editor grants WKWebView access across the bundled resource directory for font assets")
expect(richEditorSource.contains("SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)")
    && !richEditorSource.contains("SelectionAnchorCoordinate.y(")
    && !richEditorSource.contains("contentView.convert("), "rich markdown editor selection anchors use the shared coordinate helper")
expect(richEditorSource.contains("var passesVerticalScrollToSuperview = false")
    && richEditorSource.contains("override func scrollWheel(with event: NSEvent)")
    && richEditorSource.contains("override func hitTest(_ point: NSPoint) -> NSView?")
    && richEditorSource.contains("NSApp.currentEvent?.type == .scrollWheel")
    && richEditorSource.contains("abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)")
    && richEditorSource.contains("nearestSuperviewScrollView()")
    && richEditorSource.contains("func scrollOuterSuperview(deltaY: CGFloat)")
    && richEditorSource.contains("window.addEventListener(\"wheel\"")
    && richEditorSource.contains("compactPreviewWheel")
    && richEditorSource.contains("clipView.scroll(to:")
    && richEditorSource.contains("outerScrollView.scrollWheel(with: event)")
    && richEditorSource.contains("return self.forwardVerticalScroll(event) ? nil : event")
    && richEditorSource.contains("guard abs(nextY - clipView.bounds.origin.y) > 0.01 else { return false }")
    && richEditorSource.contains("view.passesVerticalScrollToSuperview = isCompactPreview")
    && richEditorSource.contains("(view as? MarkdownWebView)?.passesVerticalScrollToSuperview = isCompactPreview")
    && richEditorSource.contains("NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)")
    && richEditorSource.contains("bounds.contains(localPoint)")
    && richEditorSource.contains("return nil"), "compact markdown previews pass vertical wheel events to the outer conversation scroll instead of trapping the pointer over message text")
expect(richEditorSource.contains("var documentID = \"\"") && richEditorSource.contains("var pendingExternalMarkdown: String?"), "rich editor tracks document identity and pending external sync")
expect(
    richEditorSource.contains("window.weiBeiDocumentID")
        && richEditorSource.contains("func setDocumentID(_ id: String)")
        && richEditorSource.contains("guard messageMatchesDocument(message.body) else { return }"),
    "rich editor rejects stale web callbacks from a previous document"
)
expect(richEditorSource.contains("guard text == pendingExternalMarkdown else { return }"), "rich editor ignores stale markdown callbacks during document sync")
expect(richEditorSource.contains("command && shift && !option && !control") && richEditorSource.contains("[\"a\", \"r\", \"e\", \"c\"].includes(key)"), "rich editor forwards command-shift agent shortcuts to Swift")
expect(richEditorSource.contains("[\"1\", \"2\", \"3\", \"4\", \"[\", \"]\", \"b\", \"j\", \"k\", \"f\"].includes(key)"), "rich editor forwards workspace history shortcuts to Swift")
expect(richEditorSource.contains("runPendingCommandIfReady()")
    && richEditorSource.contains("guard isReady,")
    && richEditorSource.contains("self.command.wrappedValue = nil"), "rich editor does not drop commands before the web editor is ready")
expect(richEditorSource.contains("var appearanceMode: WeiBeiAppearanceMode = .paper")
    && richEditorSource.components(separatedBy: "appearanceMode: appearanceMode").count >= 4
    && richEditorSource.contains("private static func applyWebAppearance(to view: WKWebView, appearanceMode: WeiBeiAppearanceMode)")
    && richEditorSource.contains("view.underPageBackgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)")
    && richEditorSource.contains("view.appearance = NSAppearance(named: appearanceMode == .inkstone ? .darkAqua : .aqua)")
    && richEditorSource.contains("private var missingImageColors: (background: String, accent: String, text: String)")
    && richEditorSource.contains("case .inkstone:")
    && richEditorSource.contains("return (\"#151515\", \"#a6362b\", \"#d7cbb0\")"), "native missing-image placeholders follow the current editor theme instead of always using a pale SVG")
expect(richEditorSource.contains("selection?.removeAllRanges();")
    && richEditorSource.contains("messageHandlers?.selectionChanged?.postMessage")
    && richEditorSource.contains("text: \"\",")
    && richEditorSource.contains("rect: null")
    && richEditorSource.contains("window.weiBeiSuppressSelectionReport = true;")
    && richEditorSource.contains("window.setTimeout(() => { window.weiBeiSuppressSelectionReport = false; }, 80);"), "rich markdown search clears stale floating selection state without reporting the search hit as an agent selection")
expect(richEditorSource.contains("window.weiBeiInterfaceLanguage =")
    && richEditorSource.contains("document.documentElement.dataset.weibeiLanguage = window.weiBeiInterfaceLanguage")
    && richEditorSource.contains("func setInterfaceLanguage(_ language: WeiBeiInterfaceLanguage)")
    && richEditorSource.contains("context.coordinator.setInterfaceLanguage(interfaceLanguage)"), "rich markdown editor passes interface language changes into the web editor")
let webEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/WebEditor/src/editor.js")
let webEditorSource = (try? String(contentsOf: webEditorSourceURL, encoding: .utf8)) ?? ""
expect(!webEditorSource.contains("event.metaKey && event.shiftKey && event.key.toLowerCase() === 'a'"), "web editor does not steal command-shift-a from Swift agent write action")
expect(webEditorSource.contains("const insertionCursorMarker = '{{WEIBEI_CURSOR}}'")
    && webEditorSource.contains("insertionSelectionStartMarker")
    && webEditorSource.contains("placeCursorAtInsertionMarker()"), "web editor removes command snippet cursor markers after insertion")
expect(webEditorSource.contains("let currentDocumentID = window.weiBeiDocumentID || ''")
    && webEditorSource.contains("postMessage({ ...body, documentID: currentDocumentID })")
    && webEditorSource.contains("setDocumentID: (next) =>"), "web editor tags bridge messages with the current document identity")
expect(webEditorSource.contains("let lastSelectionReport = { text: null, rectKey: null }")
    && webEditorSource.contains("post('selectionChanged', { text: '', rect: null })")
    && webEditorSource.contains("lastSelectionRange = null")
    && webEditorSource.contains("if (window.weiBeiSuppressSelectionReport) return;")
    && webEditorSource.contains("if (text === lastSelectionReport.text && rectKey === lastSelectionReport.rectKey) return"), "web editor reports cleared selections once so floating selection UI and included-selection badges disappear")
expect(webEditorSource.contains("const palette = currentTheme === 'inkstone'")
    && webEditorSource.contains("background: '#151515', accent: '#a6362b', text: '#d7cbb0'")
    && webEditorSource.contains("background: '#efe6d8', accent: '#9f3b2f', text: '#6b5148'")
    && webEditorSource.contains("img[data-weibei-image-placeholder=\"true\"]")
    && webEditorSource.contains("image.setAttribute('src', missingImageURL())"), "web missing-image placeholders follow the current theme and refresh after theme switches")
expect(webEditorSource.contains("const decorateCalloutHeadingSource = (decorations, node, pos) =>")
    && webEditorSource.contains("const firstParagraphText = (node) =>")
    && webEditorSource.contains("const calloutMatchForBlockquote = (node) =>")
    && webEditorSource.contains("const isBlockquoteType = (typeName) => typeName === 'blockquote' || typeName === 'block_quote'")
    && webEditorSource.contains("const calloutTypePattern = '[A-Za-z][A-Za-z0-9_-]*'")
    && webEditorSource.contains("const calloutPrefixPattern = '(?:\\\\s*>\\\\s*)*\\\\s*'")
    && webEditorSource.contains("const selectedTextCalloutControlRegex = new RegExp")
    && webEditorSource.contains("const cleanSelectedText = (text) =>")
    && webEditorSource.contains("const decorateLeakedCalloutControls = (decorations, text, pos) =>")
    && webEditorSource.contains("weibei-callout-custom")
    && webEditorSource.contains(#"^${calloutPrefixPattern}\\\\?\\[!"#)
    && webEditorSource.contains("const contentStart = pos + 1")
    && webEditorSource.contains("addRangeDecoration(decorations, contentStart, markerEnd, 'weibei-callout-marker')")
    && webEditorSource.contains("if (isBlockquoteType(typeName))")
    && webEditorSource.contains("const match = calloutMatchForBlockquote(node);")
    && webEditorSource.contains("typeName === 'paragraph' && isBlockquoteType(parentName)")
    && webEditorSource.contains("decorateCalloutHeadingSource(decorations, node, pos);")
    && webEditorSource.contains("return cleanSelectedText(content.textBetween")
    && webEditorSource.contains("const selectedText = () => cleanSelectedText")
    && webEditorSource.contains("if (insideBlockquote) decorateLeakedCalloutControls(decorations, text, textPos);")
    && !webEditorSource.contains("Array.from(calloutTypes).join('|')"), "callout heading decorations collapse the raw [!type] marker at paragraph range level so split inline nodes do not leak")
expect(webEditorSource.contains("const normalizeInterfaceLanguage")
    && webEditorSource.contains("let currentLanguage = normalizeInterfaceLanguage(window.weiBeiInterfaceLanguage)")
    && webEditorSource.contains("const calloutLabels = {")
    && webEditorSource.contains("en: {")
    && webEditorSource.contains("note: 'Note'")
    && webEditorSource.contains("'data-callout-title': (match[3] || calloutLabel(calloutType)).trim()")
    && webEditorSource.contains("setInterfaceLanguage: (next) =>"), "web editor callout fallback labels follow the current interface language")
expect(webEditorSource.contains(#"const htmlBreakPattern = /<br\s*\/?>/gi;"#)
    && webEditorSource.contains(#".replace(htmlBreakPattern, '\n')"#)
    && webEditorSource.contains("const isEscapedMarkdownPosition = (source, index) =>")
    && webEditorSource.contains("const findUnescapedMarkdownMarker = (source, marker, from) =>")
    && webEditorSource.contains("const mapMarkdownOutsideBackticks = (line, transform) =>")
    && webEditorSource.contains("const normalizeMarkdownOutputSegment = (text) =>")
    && webEditorSource.contains("const mapMarkdownOutsideCode = (markdown, transform) =>")
    && webEditorSource.contains("const normalizeMarkdownOutput = (markdown) => mapMarkdownOutsideCode(markdown, normalizeMarkdownOutputSegment)")
    && webEditorSource.contains("const normalizeHtmlBreaksInLine = (line) =>")
    && webEditorSource.contains("const normalizeHtmlBreaks = (markdown) =>")
    && webEditorSource.contains("const tick = findUnescapedMarkdownMarker(source, '`', cursor)")
    && webEditorSource.contains("const close = findUnescapedMarkdownMarker(source, marker, tick + marker.length)")
    && webEditorSource.contains(#"line.match(/^\s*(?:>\s*)*(`{3,}|~{3,})/)"#)
    && webEditorSource.contains("let inFence = false")
    && webEditorSource.contains("let fenceLength = 0")
    && webEditorSource.contains("if (inFence)")
    && webEditorSource.contains(#".replace(/<br\s*\/?>[ \t]*/gi, '  \n')"#)
    && webEditorSource.contains("const decorateHtmlBreaks = (decorations, text, pos) =>")
    && webEditorSource.contains("weibei-html-break-source")
    && webEditorSource.contains("if (hasCodeMark) return true;")
    && webEditorSource.contains("decorateHtmlBreaks(decorations, text, textPos)")
    && webEditorSource.contains("handleTextInput(view, from, to, text)")
    && webEditorSource.contains("view.state.schema.nodes.hardbreak || view.state.schema.nodes.hard_break")
    && webEditorSource.contains(#".replace(/!\[\[([^\]\n]+)\]\]/g, (_, raw) =>"#)
    && webEditorSource.contains(#".replace(/==([^=\n]+)==/g, '$1')"#)
    && webEditorSource.contains(#".replace(/%%[\s\S]*?%%\n?/g, '')"#), "web editor cleans common Markdown and Obsidian source markers from selected Agent context and renders HTML breaks softly")
let appSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/App/WeiBeiApp.swift")
let appSource = (try? String(contentsOf: appSourceURL, encoding: .utf8)) ?? ""
expect(appSource.contains("private var shouldActivateOnLaunch: Bool")
    && appSource.contains("WEIBEI_SUPPRESS_ACTIVATION")
    && appSource.contains("Task { await store.runVerificationScenarioIfNeeded() }")
    && appSource.contains("if shouldActivateOnLaunch {\n            NSApp.activate(ignoringOtherApps: true)\n        }"), "app activation is skipped during non-invasive verification launches")
expect(appSource.contains("window.isOpaque = true"), "main window declares opaque paper backing for stable capture")
expect(appSource.contains("sharedWorkspaceStore"), "main window and settings share one workspace store")
expect(!appSource.contains("launchProbe"), "app launch path has no temporary probe logging")
expect(appSource.contains("WeiBeiAppearanceTransition")
    && appSource.contains(".modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))")
    && appSource.contains(".animation(WeiBeiMotion.appearance, value: mode)")
    && appSource.components(separatedBy: ".modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))").count >= 3
    && appSource.contains("private func animateAppearance(_ action: () -> Void)")
    && appSource.contains("animateAppearance {\n                        store.toggleAppearanceMode()")
    && appSource.contains("withAnimation(WeiBeiMotion.appearance)")
    && appSource.contains("store.setAppearanceMode(mode)")
    && appSource.contains("@State private var washColor = Color.clear")
    && appSource.contains("washColor = Color(nsColor: oldMode.windowBackground)")
    && appSource.contains("washOpacity = 0.36")
    && appSource.contains("transaction.disablesAnimations = true")
    && appSource.contains("DispatchQueue.main.async"), "appearance mode changes stage a wash before fading instead of collapsing into a hard cut")
expect(appSource.contains("addLocalMonitorForEvents(matching: .keyDown)") && appSource.contains("removeMonitor(shortcutMonitor)"), "app-level shortcuts survive focused web editor")
expect(appSource.contains("var reopenMainWindow: (() -> Void)?")
    && appSource.contains("applicationShouldHandleReopen")
    && appSource.contains("if !flag")
    && appSource.contains("window.deminiaturize(nil)")
    && appSource.contains("window.makeKeyAndOrderFront(nil)")
    && appSource.contains("reopenMainWindow?()")
    && appSource.contains("MainWindowReopenBridge(appDelegate: appDelegate)")
    && appSource.contains("@Environment(\\.openWindow) private var openWindow")
    && appSource.contains("openWindow(id: \"main\")")
    && appSource.contains("return false")
    && !appSource.contains("return flag"), "reopen restores a hidden/minimized window or opens the main SwiftUI window instead of leaving a zero-window process")
expect(!appSource.contains("Form {")
    && appSource.contains("@State private var selectedSection: SettingsSection = .overview")
    && appSource.contains("private enum SettingsSection: String, CaseIterable, Identifiable")
    && appSource.contains("case overview")
    && appSource.contains("case appearance")
    && appSource.contains("case reading")
    && appSource.contains("case writing")
    && appSource.contains("case agent")
    && appSource.contains("case data")
    && appSource.contains("case shortcuts")
    && appSource.contains("settingsSidebar")
    && appSource.contains("settingsDetail")
    && appSource.contains("overviewSettings")
    && appSource.contains("appearanceSettings")
    && appSource.contains("agentSettings")
    && appSource.contains("Text(store.brandLatinName)")
    && appSource.contains("Text(\"SETTINGS\")")
    && appSource.contains("WeiBeiTypography.englishBrandFont")
    && appSource.contains("case .overview: return \"HOME\"")
    && appSource.contains("case .appearance: return \"LOOK\"")
    && appSource.contains("case .agent: return \"CHAT\"")
    && appSource.contains("case .agent: return store.ui(\"对话\", \"Chat\")")
    && appSource.contains("title: store.ui(\"对话上下文\", \"Chat Context\")")
    && appSource.contains("已选文本片段会作为对话上下文")
    && appSource.contains("settingsGroup(store.ui(\"快速进入\", \"Jump To\")")
    && appSource.contains("title: store.ui(\"对话设置\", \"Chat Settings\")")
    && appSource.contains("settingsGroup(store.ui(\"密钥与模型\", \"Key & Model\")")
    && appSource.contains("settingsGroup(store.ui(\"对话形态\", \"Chat Surface\")")
    && appSource.contains("title: store.ui(\"默认显示\", \"Default Surface\")")
    && appSource.contains("把对话能力作为低干扰阅读线索")
    && !appSource.contains("Agent 上下文")
    && !appSource.contains("Agent 与 API")
    && !appSource.contains("title: store.ui(\"对话与 API\"")
    && !appSource.contains("settingsGroup(store.ui(\"API\"")
    && !appSource.contains("把 Agent 作为")
    && appSource.contains("prompt: Text(store.ui(\"对话密钥\"")
    && appSource.contains("Button(store.ui(\"保存\"")
    && !appSource.contains("prompt: Text(\"OpenAI 密钥\")")
    && !appSource.contains("Button(\"保存到钥匙串\")")
    && appSource.contains("store.ui(\"本机环境里的模型设置会覆盖这里。\"")
    && !appSource.contains("WEIBEI_OPENAI_MODEL 会覆盖这里")
    && appSource.contains("SecureField(")
    && appSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && appSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && appSource.contains(".weibeiInputSurface(active: focusedField == .apiKey, height: 38)")
    && appSource.contains("private var settingsAppearanceToggleButton: some View")
    && appSource.contains("Spacer()\n            settingsAppearanceToggleButton")
    && appSource.contains("Image(systemName: store.appearanceMode.toggled.systemImage)")
    && appSource.contains(".buttonStyle(WeiBeiIconButtonStyle(size: 30))")
    && !appSource.contains("WeiBeiIconButtonStyle(active: store.appearanceMode == .inkstone")
    && appSource.contains("store.setTopBarVariant(variant)"), "settings center uses categorized WeiBei chrome and real bound controls instead of the default form field")
expect(appSource.contains("settingsPill(\n                    title: store.interfaceLanguage.settingsLabel,\n                    icon: \"character.book.closed\",\n                    active: false")
    && appSource.contains("settingsPill(\n                    title: store.appearanceMode.label(language: store.interfaceLanguage),\n                    icon: store.appearanceMode.systemImage,\n                    active: false"), "settings sidebar summary pills stay neutral instead of looking permanently selected")
expect(appSource.contains("segmented(NoteRenderMode.visibleCases, active: store.noteRenderMode.visibleMode)")
    && !appSource.contains("笔记预览")
    && !appSource.contains("Note Preview")
    && !appSource.contains("setNoteRenderMode(.preview)")
    && !commandPaletteSource.contains("笔记预览")
    && !commandPaletteSource.contains("Note Preview")
    && !commandPaletteSource.contains("setNoteRenderMode(.preview)"), "note preview is removed from settings, menus, and command palette while visible modes stay normalized")
let interactiveInputSources = [contentViewSource, sidebarSource, commandPaletteSource, notesAgentSource, appSource].joined(separator: "\n")
expect(!interactiveInputSources.contains(".weibeiInputPrompt("), "interactive input placeholders stay on native prompts instead of overlay text")
expect(appSource.contains("WeiBeiTextActionButtonStyle(active: true)") && appSource.contains(".background(WeiBeiTheme.paper)") && appSource.contains("WeiBeiGlassHeaderBackground(paperOpacity: 0.66"), "settings view uses WeiBei paper, glass header, and button styles")
expect(appSource.contains("init() {\n        WeiBeiTypography.registerBundledFonts()\n    }"), "app registers bundled WeiBei fonts before the SwiftUI window tree is built")
let workspaceStoreSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Stores/WorkspaceStore.swift")
let workspaceStoreSource = (try? String(contentsOf: workspaceStoreSourceURL, encoding: .utf8)) ?? ""
expect(workspaceStoreSource.contains("var brandLatinName: String")
    && workspaceStoreSource.contains("\"WeiBei\"")
    && contentViewSource.contains("Text(store.brandLatinName)")
    && contentViewSource.contains("case .glyph:\n            HStack(spacing: 5)")
    && contentViewSource.contains(".frame(width: 78, height: controlHeight, alignment: .leading)")
    && contentViewSource.contains("WeiBeiTypography.englishBrandFont(size: variant == .wide ? 17 : 16")
    && appSource.contains("Text(store.brandLatinName)")
    && appSource.contains("WeiBeiTypography.englishBrandFont(size: 18")
    && sidebarSource.contains("WEIBEI STUDY")
    && notesAgentSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"NOTES\" : nil")
    && notesAgentSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"CHAT\" : nil"), "custom English font has visible Latin brand marks in the top bar, settings, library, and pane headers")
expect(notesAgentSource.contains("ForEach(NoteRenderMode.visibleCases)")
    && notesAgentSource.contains("switch store.noteRenderMode.visibleMode")
    && !notesAgentSource.contains("ForEach(NoteRenderMode.allCases)")
    && notesAgentSource.contains("let label = mode.label(language: store.interfaceLanguage)")
    && notesAgentSource.contains("Text(label)")
    && !notesAgentSource.contains("return \"Diff\"")
    && !notesAgentSource.contains("return \"Src\"")
    && !notesAgentSource.contains("private func compactModeLabel")
    && !notesAgentSource.contains("Text(\"预览\")")
    && !notesAgentSource.contains("Text(\"Preview\")")
    && notesAgentSource.contains(".accessibilityLabel(Text(label))")
    && notesAgentSource.contains(".help(label)"), "note pane header exposes only writing, compare, and source with clear shared labels and full accessibility/help text")
expect(
    workspaceStoreSource.contains("shortcutKey(from event: NSEvent)")
        && workspaceStoreSource.contains("case 0: return \"a\"")
        && workspaceStoreSource.contains("case 18: return \"1\"")
        && workspaceStoreSource.contains("case 30: return \"]\"")
        && workspaceStoreSource.contains("case 33: return \"[\"")
        && workspaceStoreSource.contains("case 125: return \"down\""),
    "app shortcuts normalize hardware keys"
)
expect(workspaceStoreSource.contains("animateLayoutChange") && workspaceStoreSource.contains("withAnimation(WeiBeiMotion.layout)"), "app shortcut layout changes stay animated")
expect(workspaceStoreSource.contains("animatePanelChange") && workspaceStoreSource.contains("withAnimation(WeiBeiMotion.panel)"), "app shortcut panel changes stay animated")
expect(workspaceStoreSource.contains("if modifiers == [.command, .shift]") && workspaceStoreSource.contains("applyLastAgentAnswerToNote()") && workspaceStoreSource.contains("replaceSelectionWithLastAgentAnswer()") && workspaceStoreSource.contains("applyAgentPatchToEditor()"), "app shortcut handler owns command-shift agent write actions")
expect(workspaceStoreSource.contains("case \"a\":\n                guard canApplyAgentAnswer else { return false }\n                animatePanelChange { applyLastAgentAnswerToNote() }")
    && workspaceStoreSource.contains("case \"r\":\n                guard canReplaceNoteSelection else { return false }\n                animatePanelChange { replaceSelectionWithLastAgentAnswer() }")
    && workspaceStoreSource.contains("case \"e\":\n                guard canApplyAgentAnswer else { return false }\n                animatePanelChange { applyAgentPatchToEditor() }"), "agent write shortcuts do not swallow unavailable actions")
expect(workspaceStoreSource.contains("case \"j\":\n                guard layout.hasCollapsibleRightPane else { return false }\n                animateLayoutChange { toggleRightPane() }"), "right-pane shortcut does not swallow unavailable layouts")
expect(workspaceStoreSource.contains("case \"2\":\n                animateLayoutChange { setLayout(.documentNotesSplit) }")
    && !workspaceStoreSource.contains("case \"3\":\n                animateLayoutChange { setLayout(.documentNotesSplit) }")
    && workspaceStoreSource.contains("case \"s\":\n                guard layout.isDocumentThreePane else { return false }\n                animateLayoutChange { swapThreePaneSecondaryPanes() }"), "three-pane keyboard shortcuts match the command palette and only swap panes inside the three-pane workspace")
expect(workspaceStoreSource.contains("case \"[\":\n                guard canNavigateBack else { return false }\n                animateLayoutChange { navigateBackInWorkspace() }")
    && workspaceStoreSource.contains("case \"]\":\n                guard canNavigateForward else { return false }\n                animateLayoutChange { navigateForwardInWorkspace() }"), "command-bracket shortcuts drive workspace back and forward")
expect(workspaceStoreSource.contains("var canCopyReference: Bool")
    && workspaceStoreSource.contains("var copyReferenceActionTitle: String")
    && workspaceStoreSource.contains("hasSelectionAttachments || selectionContext != nil")
    && workspaceStoreSource.contains("if hasSelectionAttachments || selectionContext != nil { return ui(\"复制选区引用\"")
    && workspaceStoreSource.contains("if hasSelectedMaterial { return ui(\"复制资料引用\"")
    && workspaceStoreSource.contains("guard canCopyReference else { return false }")
    && workspaceStoreSource.contains("guard hasSelectedMaterial else { return false }"), "app shortcuts and menus name copy-reference by the actual current target")
expect(workspaceStoreSource.contains("selectAdjacentItem(step: -1)") && workspaceStoreSource.contains("Task { await askAgent() }"), "app shortcut handler covers navigation and agent send")
expect(workspaceStoreSource.contains("return allItems.filter { itemMatchesLibrarySearch($0, query: query) }")
    && workspaceStoreSource.contains("return materialItems.filter { itemMatchesLibrarySearch($0, query: query) }")
    && workspaceStoreSource.contains("func displayTags(for item: StudyItem, limit: Int = 3) -> [String]")
    && workspaceStoreSource.contains("return Array(MarkdownTagSearch.tags(in: noteMarkdownText(for: item)).prefix(limit))")
    && workspaceStoreSource.contains("private func noteTagsMatchLibrarySearch(_ item: StudyItem, query: String) -> Bool")
    && workspaceStoreSource.contains("private func noteMarkdownText(for item: StudyItem) -> String")
    && workspaceStoreSource.contains("MarkdownTagSearch.matches(query: query, in: noteMarkdownText(for: item))")
    && workspaceStoreSource.contains("item.id == activeNoteItemID"), "course index search includes active and cached notebook Markdown tags without indexing all notes separately")
expect(workspaceStoreSource.contains("backNavigationStack: [NavigationSnapshot]")
    && workspaceStoreSource.contains("forwardNavigationStack: [NavigationSnapshot]")
    && workspaceStoreSource.contains("func navigateBackInWorkspace()")
    && workspaceStoreSource.contains("func navigateForwardInWorkspace()")
    && workspaceStoreSource.contains("private func recordNavigationPoint()")
    && workspaceStoreSource.contains("private func applyNavigationSnapshot")
    && workspaceStoreSource.contains("forwardNavigationStack.append(navigationSnapshot())")
    && workspaceStoreSource.contains("backNavigationStack.append(navigationSnapshot())")
    && workspaceStoreSource.contains("agentSurface == .selectionFloat ? .hidden : agentSurface"), "workspace back/forward stores app page state without restoring transient selection floats")
expect(workspaceStoreSource.contains("@Published var readerPageIndex = 0")
    && workspaceStoreSource.contains("var readerPageIndex: Int")
    && workspaceStoreSource.contains("func updateReaderPageIndex(_ index: Int)")
    && workspaceStoreSource.contains("func recordReaderPageNavigationPoint()")
    && workspaceStoreSource.contains("readerPageIndex: readerPageIndex")
    && workspaceStoreSource.contains("readerTargetPageIndex = selectedMaterialItem?.kind == .pdf ? snapshot.readerPageIndex : nil"), "workspace navigation snapshots restore PDF page position instead of only restoring the selected document")
expect(workspaceStoreSource.contains("case \"return\":\n                guard !isAskingAgent && !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }\n                Task { await askAgent() }"), "app shortcut does not swallow command-return when there is no sendable agent draft")
expect(workspaceStoreSource.contains("showQuietInsight = agentSurface == .quietInsight") && !workspaceStoreSource.contains("agentSurface = .quietInsight\n            showQuietInsight = true"), "immersive reading preserves the chosen agent surface")
expect(workspaceStoreSource.contains("@Published var activeNotebookItemID")
    && workspaceStoreSource.contains("var activeNoteItem: StudyItem?")
    && workspaceStoreSource.contains("guard itemID == activeNoteItemID else { return }"), "note writes are bound to the active note instead of the selected reader material")
expect(workspaceStoreSource.contains("private var pendingNotePersistenceByItemID: [String: PendingNotePersistence] = [:]")
    && workspaceStoreSource.contains("private var pendingNotePersistenceTasks: [String: Task<Void, Never>] = [:]")
    && workspaceStoreSource.contains("private let notePersistenceDebounceDelay")
    && workspaceStoreSource.contains("func updateNote(_ value: String) {\n        guard noteText != value else { return }")
    && workspaceStoreSource.contains("scheduleNotePersistence(value, for: item)")
    && !workspaceStoreSource.contains("func updateNote(_ value: String) {\n        noteText = value\n        clearGeneratedQuietInsight()\n        persistCurrentNote()\n        save()")
    && workspaceStoreSource.contains("func flushPendingNotePersistence()")
    && appSource.contains("sharedWorkspaceStore.flushPendingNotePersistence()"), "markdown typing updates memory immediately but debounces note persistence and flushes pending edits on quit")
expect(workspaceStoreSource.contains("let item = allItems.first(where: { $0.id == itemID && $0.isNotebookNote })")
    && workspaceStoreSource.contains("activeNotebookItemID = item.id")
    && workspaceStoreSource.contains("noteText = noteText(for: item)")
    && !workspaceStoreSource.contains("select(itemID: item.id)\n            noteFileError = ui(\"已创建笔记"), "selecting or creating a notebook note does not replace the current reader material")
expect(workspaceStoreSource.contains("@Published var readerLocationTitle") && workspaceStoreSource.contains("var currentReferenceTitle"), "store tracks the current reader reference title")
expect(workspaceStoreSource.contains("@Published var readerTargetPageIndex") && workspaceStoreSource.contains("func openSourceReference") && workspaceStoreSource.contains("SourceReferenceTitle.parse"), "store can jump from source reference text to the referenced material")
expect(workspaceStoreSource.contains("let sampleItems: [StudyItem] = WorkspaceStore.makeSampleItems()")
    && workspaceStoreSource.contains("StudyItem(id: \"sample-pdf\", title: \"Mishkin 教材样例\", subtitle: \"PDF 阅读\", kind: .pdf, urlPath: samplePDFURL()?.path, isSample: true)")
    && workspaceStoreSource.contains("private var didRunVerificationScenario = false")
    && workspaceStoreSource.contains("func runVerificationScenarioIfNeeded() async")
    && workspaceStoreSource.contains("let scenario = Self.environmentValue(\"WEIBEI_VERIFY_SCENARIO\")")
    && workspaceStoreSource.contains("scenario == \"offline-learning-flow\"")
    && workspaceStoreSource.contains("scenario == \"immersive-conversation-flow\"")
    && workspaceStoreSource.contains("scenario == \"notebook-creation-flow\"")
    && workspaceStoreSource.contains("layout = scenario == \"immersive-conversation-flow\" ? .immersiveConversation : .documentAgentNotes")
    && workspaceStoreSource.contains("if scenario == \"notebook-creation-flow\" {\n            layout = .immersiveWriting")
    && workspaceStoreSource.contains("showLibrary = scenario != \"immersive-conversation-flow\"")
    && workspaceStoreSource.contains("updateSelection(\n            ui(\"利率是资金使用价格的表达。\"")
    && workspaceStoreSource.contains("await askAgent()")
    && workspaceStoreSource.contains("applyLastAgentAnswerToNote()")
    && workspaceStoreSource.contains("WEIBEI_FORCE_OFFLINE_AGENT")
    && workspaceStoreSource.contains("private static func workspaceRootDirectory() -> URL?")
    && workspaceStoreSource.contains("environmentValue(\"WEIBEI_WORKSPACE_DIR\")")
    && workspaceStoreSource.contains("let directory = root.appendingPathComponent(\"Samples\", isDirectory: true)")
    && workspaceStoreSource.contains("let directory = root.appendingPathComponent(\"Files\", isDirectory: true)")
    && workspaceStoreSource.contains("private static func writeSamplePDF(to url: URL) -> Bool")
    && workspaceStoreSource.contains("CGDataConsumer(data: data as CFMutableData)")
    && workspaceStoreSource.contains("利率是资金使用价格的表达。")
    && !workspaceStoreSource.contains("StudyItem(id: \"sample-pdf\", title: \"Mishkin 教材样例\", subtitle: \"PDF 阅读\", kind: .pdf, urlPath: nil, isSample: true)"), "sample PDF item points at a generated selectable PDF file instead of the fake PDF fallback")
expect(workspaceStoreSource.contains("ownerTitle: String? = nil") && workspaceStoreSource.contains("let resolvedOwnerTitle"), "selection updates can carry a precise reader source title")
expect(workspaceStoreSource.contains("@Published var selectionAttachments: [SelectionContext] = []")
    && workspaceStoreSource.contains("@Published var floatingSelectionPrompt = \"\"")
    && workspaceStoreSource.contains("floatingSelectionPrompt = ui(\"当前选区\", \"Current selection\")")
    && workspaceStoreSource.contains("var agentSelectionTitle: String?")
    && workspaceStoreSource.contains("var agentSelectionText: String?")
    && workspaceStoreSource.contains("func removeSelectionAttachment(id: UUID)")
    && workspaceStoreSource.contains("if selectionContext?.id == id {\n                clearUnpinnedFloatingSelection(keepContext: false)")
    && workspaceStoreSource.contains("func clearSelectionAttachments()")
    && workspaceStoreSource.contains("private var pendingSelectionAttachmentTask: Task<Void, Never>?")
    && workspaceStoreSource.contains("private var lastSelectionUpdateDate: Date?")
    && workspaceStoreSource.contains("lastSelectionUpdateDate = Date()")
    && workspaceStoreSource.contains("now.timeIntervalSince($0) > selectionAttachmentMergeWindow")
    && !workspaceStoreSource.contains("guard Self.hasMeaningfulSelectionCharacter(cleaned) else {\n            lastSelectionUpdateDate = nil")
    && !workspaceStoreSource.contains("scheduleSelectionAttachment(nextSelection")
    && workspaceStoreSource.contains("private func scheduleSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool)")
    && workspaceStoreSource.contains("private let selectionAttachmentDebounceDelay: UInt64 = 520_000_000")
    && workspaceStoreSource.contains("try? await Task.sleep(nanoseconds: self?.selectionAttachmentDebounceDelay ?? 520_000_000)")
    && workspaceStoreSource.contains("private func cancelPendingSelectionAttachment()")
    && workspaceStoreSource.contains("clearUnpinnedFloatingSelection(keepContext: false)")
    && appSource.contains("store.clearSelectionAttachments()")
    && workspaceStoreSource.contains("private func addSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool = false)")
    && workspaceStoreSource.contains("private var lastSelectionAttachmentDate: Date?")
    && workspaceStoreSource.contains("private let selectionAttachmentMergeWindow: TimeInterval = 1.8")
    && workspaceStoreSource.contains("while let mergeIndex = selectionAttachments.indices.reversed().first")
    && workspaceStoreSource.contains("selectionAttachments.remove(at: mergeIndex)")
    && workspaceStoreSource.contains("SelectionAttachmentMerge.mergedText")
    && workspaceStoreSource.contains("withinSelectionGesture || withinSelectionGestureHint")
    && workspaceStoreSource.contains("let maxAttachments = 8"), "agent selection context uses an explicit removable attachment list instead of a single hidden draft selection")
expect(workspaceStoreSource.contains("selectionTitle: sentSelectionTitle")
    && workspaceStoreSource.contains("selectionText: sentSelectionText")
    && !workspaceStoreSource.contains("selectionText: selectionContext?.text,\n                recentMessages: recentMessages"), "agent requests use confirmed selection attachments instead of the transient live selection")
expect(workspaceStoreSource.contains("let sentSelectionTitle = agentSelectionTitle")
    && workspaceStoreSource.contains("let sentSelectionText = agentSelectionText")
    && workspaceStoreSource.contains("selectionAttachments = []")
    && workspaceStoreSource.contains("selectionTitle: sentSelectionTitle")
    && workspaceStoreSource.contains("selectionText: sentSelectionText"), "sending captures selected text attachments for the request and clears the composer attachments afterward")
expect(workspaceStoreSource.contains("private static func boundedSelectionText")
    && workspaceStoreSource.contains("let cleaned = MarkdownSelectionSanitizer.clean(text)")
    && workspaceStoreSource.contains("Self.boundedSelectionText(cleaned)")
    && workspaceStoreSource.contains("lastIndex(where:")
    && !workspaceStoreSource.contains("String(cleaned.prefix(2_000))"), "selection context cleans callout control markers and truncates at a word or line boundary")
expect(workspaceStoreSource.contains("var hasPrimaryConversationPaneVisible: Bool")
    && workspaceStoreSource.contains("case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:\n            return showAgent")
    && workspaceStoreSource.contains("case .immersiveConversation:\n            return true")
    && workspaceStoreSource.contains("var isConversationSurfaceVisible: Bool")
    && workspaceStoreSource.contains("var canShowSelectionPromptSurface: Bool")
    && workspaceStoreSource.contains("var canShowSelectionPromptSurface: Bool {\n        true")
    && workspaceStoreSource.contains("return agentSurface == .bottomDrawer || agentSurface == .cornerPanel"), "workspace has one shared rule for primary conversation panes, formal conversation surfaces, and prompt-only selection affordances")
if let updateSelectionStart = workspaceStoreSource.range(of: "func updateSelection(_ text: String")?.lowerBound,
   let removeSelectionStart = workspaceStoreSource.range(of: "func removeSelectionAttachment")?.lowerBound {
    let updateSelectionSource = String(workspaceStoreSource[updateSelectionStart..<removeSelectionStart])
    expect(updateSelectionSource.contains("let shouldRevealSelectionPrompt = anchor != nil || pinnedFloatingAgent")
        && updateSelectionSource.contains("selectionAnchor = anchor")
        && updateSelectionSource.contains("cancelPendingSelectionAttachment()")
        && !updateSelectionSource.contains("scheduleSelectionAttachment(nextSelection")
        && !updateSelectionSource.contains("let shouldRouteToConversation")
        && !updateSelectionSource.contains("addSelectionAttachment(nextSelection)")
        && !updateSelectionSource.contains("focusedPane = .agent\n                focusRequest += 1")
        && updateSelectionSource.contains("if shouldRevealSelectionPrompt {"), "selection updates show the local selection capsule without auto-adding chat attachments")
} else {
    expect(false, "updateSelection source is readable")
}
expect(workspaceStoreSource.contains("func askSelection()")
    && workspaceStoreSource.contains("if isConversationSurfaceVisible {\n                routeSelectionToConversation(selectionContext)\n            } else {")
    && workspaceStoreSource.contains("agentSurface = .selectionFloat")
    && workspaceStoreSource.contains("func routeSelectionToConversation")
    && workspaceStoreSource.contains("if agentSurface == .selectionFloat {\n                agentSurface = .hidden\n            }")
    && workspaceStoreSource.components(separatedBy: "withAnimation(WeiBeiMotion.panel) {").count >= 3, "asking a selection uses the open conversation surface before falling back to the floating prompt")
if let askSelectionStart = workspaceStoreSource.range(of: "func askSelection()")?.lowerBound,
   let appendSelectionStart = workspaceStoreSource.range(of: "func appendSelectionToNote()")?.lowerBound {
    let askSelectionSource = String(workspaceStoreSource[askSelectionStart..<appendSelectionStart])
    expect(askSelectionSource.contains("routeSelectionToConversation(selectionContext)")
        && askSelectionSource.contains("addSelectionAttachment(context)")
        && !askSelectionSource.contains("请解释当前已选文本片段")
        && !askSelectionSource.contains("agentDraft = prompt")
        && !askSelectionSource.contains("selectionContext.text")
        && !askSelectionSource.contains("选区："), "selection question action only attaches the selection and focuses the composer; the user writes the prompt")
} else {
    expect(false, "askSelection source is readable")
}
expect(workspaceStoreSource.contains("selectionAttachments\n                .map { quotedReferenceBlock(text: $0.text, sourceTitle: $0.ownerTitle) }")
    && workspaceStoreSource.contains("sourceTitle: selectionContext.ownerTitle")
    && workspaceStoreSource.contains("来源：\\(currentReferenceTitle)"), "copy reference uses attached selections, the live selection, or the current reader source")
expect(workspaceStoreSource.contains("private func quotedReferenceBlock")
    && workspaceStoreSource.contains("let quoted = MarkdownSelectionSanitizer.clean(text)")
    && workspaceStoreSource.contains("> [!quote] 选区摘录")
    && workspaceStoreSource.contains("> [!quote] Selection excerpt")
    && workspaceStoreSource.contains("\\(quoted)")
    && workspaceStoreSource.contains("> 来源：\\(sourceTitle)")
    && workspaceStoreSource.contains("> Source: \\(sourceTitle)")
    && !workspaceStoreSource.contains("## 选区摘录"), "selection excerpts use the shared quote callout format with a separate editable body")
expect(workspaceStoreSource.contains("selectionOwnerTitle(for source: SelectionSource)") && workspaceStoreSource.contains("activeNoteItem?.isNotebookNote == true"), "selection fallback title treats notebook notes as notes")
expect(workspaceStoreSource.contains("var selectedMaterialItem") && workspaceStoreSource.contains("!item.isNotebookNote"), "selected material excludes notebook notes")
expect(workspaceStoreSource.contains("var navigableItems") && workspaceStoreSource.contains("let materialItems = allItems.filter { !$0.isNotebookNote }"), "material navigation skips notebook notes")
expect(
    workspaceStoreSource.contains("guard hasSelectedMaterial else")
        && workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("if layout == .immersiveConversation || layout == .immersiveWriting")
        && workspaceStoreSource.contains("setLayout(.immersiveReading)"),
    "reader search reveal refuses notebook-only context and moves to a visible reader layout"
)
expect(
    workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("guard !hasSelectedMaterial else { return }")
        && workspaceStoreSource.contains("showReaderSearch = false")
        && workspaceStoreSource.contains("readerSearch = \"\""),
    "material search state clears when selection no longer points to a material"
)
if let hideReaderSearchStart = workspaceStoreSource.range(of: "func hideReaderSearch()")?.lowerBound,
   let updateReaderLocationStart = workspaceStoreSource.range(of: "func updateReaderLocationTitle")?.lowerBound {
    let hideReaderSearchSource = String(workspaceStoreSource[hideReaderSearchStart..<updateReaderLocationStart])
    expect(hideReaderSearchSource.contains("clearUnpinnedFloatingSelection(keepContext: false)") && !hideReaderSearchSource.contains("selectionContext = nil"), "reader search dismissal preserves pinned selection agents through the shared clear helper")
} else {
    expect(false, "reader search dismissal source is readable")
}
expect(workspaceStoreSource.contains("var selectedMaterialTitle") && workspaceStoreSource.contains("selectedMaterialItem.map(displayTitle) ?? ui(\"未选择材料\""), "agent material title does not invent a current material")
expect(workspaceStoreSource.contains("var agentMessageSourceTitle: String?") && workspaceStoreSource.contains("hasSelectedMaterial ? currentReferenceTitle : activeNoteItem.map(displayTitle)") && !workspaceStoreSource.contains("source: selectedMaterialItem?.title"), "agent message source uses the current reader location and falls back to the localized active note title")
expect(workspaceStoreSource.contains("materialTitle: currentReferenceTitle"), "agent prompt uses the current reader location title so PDF page context reaches the model")
expect(workspaceStoreSource.contains("private var quietInsightReferenceTitle: String")
    && workspaceStoreSource.contains("selectionContext?.ownerTitle ?? (hasSelectedMaterial ? currentReferenceTitle : activeNoteItem.map(displayTitle)) ?? ui(\"当前笔记\"")
    && workspaceStoreSource.contains("没有证据就说\\(evidenceText)"), "quiet insight uses real selection, current reader location, or note source wording")
expect(workspaceStoreSource.contains("private func clearUnpinnedFloatingSelection(keepContext: Bool = true)")
    && workspaceStoreSource.contains("selectionContext = nil")
    && workspaceStoreSource.contains("selectionAnchor = nil")
    && workspaceStoreSource.contains("floatingSelectionPrompt = ui(\"当前选区\"")
    && workspaceStoreSource.contains("pinnedFloatingAgent = false")
    && workspaceStoreSource.contains("if agentSurface == .selectionFloat {\n                agentSurface = .hidden\n            }\n            return")
    && workspaceStoreSource.contains("guard !pinnedFloatingAgent else { return }")
    && workspaceStoreSource.contains("if agentSurface == .selectionFloat"), "cleared selections remove stale context badges before preserving any pinned floating window")
if let dismissFloatingStart = workspaceStoreSource.range(of: "func dismissFloatingSelectionAgent()")?.lowerBound,
   let setNoteRenderModeStart = workspaceStoreSource.range(of: "func setNoteRenderMode")?.lowerBound {
    let dismissFloatingSource = String(workspaceStoreSource[dismissFloatingStart..<setNoteRenderModeStart])
    expect(!dismissFloatingSource.contains("agentDraft = \"\""), "dismissing the selection float does not erase text already typed in the shared agent composer")
} else {
    expect(false, "floating selection dismissal source is readable")
}
expect(workspaceStoreSource.contains("guard Self.hasMeaningfulSelectionCharacter(cleaned) else {")
    && workspaceStoreSource.contains("now.timeIntervalSince($0) > selectionAttachmentMergeWindow")
    && workspaceStoreSource.contains("clearUnpinnedFloatingSelection(keepContext: false)\n            return\n        }")
    && workspaceStoreSource.contains("private static func hasMeaningfulSelectionCharacter(_ text: String) -> Bool")
    && workspaceStoreSource.contains("!CharacterSet.whitespacesAndNewlines.contains(scalar)")
    && workspaceStoreSource.contains("!CharacterSet.punctuationCharacters.contains(scalar)")
    && workspaceStoreSource.contains("!CharacterSet.controlCharacters.contains(scalar)"), "empty, whitespace, punctuation, or control-only selections clear the prompt without breaking a live drag-selection gesture")
if let updateSelectionStart = workspaceStoreSource.range(of: "func updateSelection(_ text: String")?.lowerBound,
   let removeSelectionStart = workspaceStoreSource.range(of: "func removeSelectionAttachment")?.lowerBound {
    let liveSelectionUpdateSource = String(workspaceStoreSource[updateSelectionStart..<removeSelectionStart])
    expect(liveSelectionUpdateSource.contains("floatingSelectionPrompt = nextSelection.label(language: interfaceLanguage)")
        && liveSelectionUpdateSource.contains("pinnedFloatingAgent = false")
        && liveSelectionUpdateSource.contains("cancelPendingSelectionAttachment()")
        && liveSelectionUpdateSource.contains("if shouldRevealSelectionPrompt {")
        && liveSelectionUpdateSource.contains("anchorsApproximatelyEqual")
        && !liveSelectionUpdateSource.contains("withAnimation(WeiBeiMotion.panel) {\n            selectionContext = nextSelection")
        && !liveSelectionUpdateSource.contains("withAnimation(WeiBeiMotion.panel) {\n            selectionContext = nextSelection\n            selectionAnchor = anchor"), "new selections reset pinned floating state; continuous selection fields update without a panel spring, and only surface show/hide may animate")
} else {
    expect(false, "updateSelection animation policy source is readable")
}
expect(workspaceStoreSource.contains("let itemChanged = selectedItemID != itemID") && workspaceStoreSource.contains("clearUnpinnedFloatingSelection(keepContext: false)"), "selecting a different item clears the old selection context")
expect(workspaceStoreSource.contains("func toggleLibrary() {\n        recordNavigationPoint()\n        showLibrary.toggle()\n        clearUnpinnedFloatingSelection()")
    && workspaceStoreSource.contains("func toggleRightPane() {\n        guard layout.hasCollapsibleRightPane else { return }\n        recordNavigationPoint()\n        showRightPane.toggle()\n        clearUnpinnedFloatingSelection()"), "pane visibility changes record navigation and invalidate stale floating selection anchors")
expect(workspaceStoreSource.contains("collapseSelectionFloatIntoConversationIfVisible()\n        focusedPane = pane")
    && workspaceStoreSource.contains("private func collapseSelectionFloatIntoConversationIfVisible()")
    && workspaceStoreSource.contains("guard isConversationSurfaceVisible, agentSurface == .selectionFloat else { return }")
    && workspaceStoreSource.contains("selectionAnchor = nil\n        pinnedFloatingAgent = false"), "opening or focusing the formal conversation surface collapses any stale selection mini window but keeps the selected text context")
expect(workspaceStoreSource.contains("focus(showRightPane ? rightPaneRevealFocus : fallbackDocumentPaneFocus())")
    && workspaceStoreSource.contains("private var rightPaneRevealFocus: PaneFocus")
    && workspaceStoreSource.contains("if layout.isDocumentThreePane")
    && workspaceStoreSource.contains("return normalizedThreePaneOrder.last?.focus ?? .notes")
    && workspaceStoreSource.contains("case .documentNotesAgent, .immersiveConversation:\n            return .agent"), "right-pane reveal focuses the visible pane by current role order instead of legacy fixed layout names")
expect(workspaceStoreSource.contains("func revealLibrary()")
    && workspaceStoreSource.contains("if !showLibrary {\n            recordNavigationPoint()\n            clearUnpinnedFloatingSelection()\n        }")
    && workspaceStoreSource.contains("focus(.library)\n        save()"), "library reveal uses the shared durable state path")
expect(workspaceStoreSource.contains("layout == .immersiveReading || layout == .immersiveWriting") && workspaceStoreSource.contains("agentSurface = .cornerPanel") && !workspaceStoreSource.contains("layout = .immersiveConversation\n                showLibrary = false\n                showRightPane = true"), "agent focus in immersive layouts opens an overlay instead of switching layout")
if let setLayoutStart = workspaceStoreSource.range(of: "func setLayout(_ layout: WorkspaceLayout)")?.lowerBound,
   let setAgentSurfaceStart = workspaceStoreSource.range(of: "func setAgentSurface")?.lowerBound {
    let setLayoutSource = String(workspaceStoreSource[setLayoutStart..<setAgentSurfaceStart])
    expect(!setLayoutSource.contains("showLibrary = false"), "layout switching preserves the current library visibility")
    expect(!setLayoutSource.contains("showRightPane = true"), "layout switching preserves a user-collapsed auxiliary pane")
    expect(setLayoutSource.contains("clearUnpinnedFloatingSelection()"), "layout switching invalidates stale floating selection anchors")
} else {
    expect(false, "layout switching source is readable")
}
if let agentFocusStart = workspaceStoreSource.range(of: "if pane == .agent")?.lowerBound,
   let focusEnd = workspaceStoreSource.range(of: "focusedPane = pane")?.lowerBound {
    let agentFocusSource = String(workspaceStoreSource[agentFocusStart..<focusEnd])
    expect(!agentFocusSource.contains("showLibrary = false"), "agent focus does not close a user-opened immersive library")
} else {
    expect(false, "agent focus source is readable")
}
if let insertStart = workspaceStoreSource.range(of: "func insertMarkdownSnippet")?.lowerBound,
   let insertEnd = workspaceStoreSource[insertStart...].range(of: "\n    }\n")?.upperBound {
    let insertSource = String(workspaceStoreSource[insertStart..<insertEnd])
    expect(!insertSource.contains("showLibrary = false"), "markdown insertion keeps a user-opened immersive library visible")
} else {
    expect(false, "markdown insertion source is readable")
}
if let setNoteModeStart = workspaceStoreSource.range(of: "func setNoteRenderMode(_ mode: NoteRenderMode)")?.lowerBound,
   let revealStart = workspaceStoreSource.range(of: "private func revealRichWritingSurface")?.lowerBound {
    let setNoteModeSource = String(workspaceStoreSource[setNoteModeStart..<revealStart])
    expect(
        setNoteModeSource.contains("let nextMode = mode.visibleMode")
            && setNoteModeSource.contains("layout = .immersiveWriting")
            && setNoteModeSource.contains("showNotes = true")
            && setNoteModeSource.contains("noteRenderMode = nextMode")
            && setNoteModeSource.contains("focus(.notes)"),
        "note render mode commands normalize legacy preview, reveal, and focus the writing surface"
    )
} else {
    expect(false, "note render mode source is readable")
}
expect(workspaceStoreSource.contains("var canUseSelectionAgentSurface: Bool")
    && workspaceStoreSource.contains("var visibleAgentSurfaces: [AgentSurface]")
    && workspaceStoreSource.contains("guard surface != .selectionFloat || canUseSelectionAgentSurface else { return }")
    && workspaceStoreSource.contains("case \"3\":\n                guard canUseSelectionAgentSurface else { return false }")
    && workspaceStoreSource.contains("self.agentSurface = agentSurface == .selectionFloat ? .hidden : agentSurface")
    && workspaceStoreSource.contains("agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface"), "selection-float agent surface is hidden, rejected, and never restored as durable workspace chrome")
expect(!workspaceStoreSource.contains("selectedItem?.title ?? \"当前材料\"")
    && !workspaceStoreSource.contains("保存后 Agent 会用")
    && !workspaceStoreSource.contains("Agent 可在打包应用里直接读取")
    && !workspaceStoreSource.contains("Agent 不会编造回答")
    && !workspaceStoreSource.contains("Agent 请求失败：")
    && workspaceStoreSource.contains("请求失败：\\(error.localizedDescription)")
    && !workspaceStoreSource.contains("Agent 设置")
    && workspaceStoreSource.contains("未配置密钥。当前用离线模式生成草稿")
    && workspaceStoreSource.contains("AgentOfflineTurn.messages(")
    && workspaceStoreSource.contains("offlineAgentInput(")
    && workspaceStoreSource.contains("AgentOfflinePreviewInput(")
    && workspaceStoreSource.contains("messages.append(AgentMessage(role: .user, text: question, source: sourceTitle))")
    && !workspaceStoreSource.contains("未配置 OPENAI_API_KEY 或钥匙串密钥")
    && workspaceStoreSource.contains("正在使用本机环境密钥。")
    && workspaceStoreSource.contains("密钥已保存，可直接用于对话。")
    && workspaceStoreSource.contains("已清除密钥。")
    && workspaceStoreSource.contains("密钥已保存。")
    && !workspaceStoreSource.contains("正在使用本机环境变量 OPENAI_API_KEY")
    && !workspaceStoreSource.contains("打包应用可直接读取")
    && !workspaceStoreSource.contains("已清除钥匙串密钥。")
    && !workspaceStoreSource.contains("已保存到 macOS 钥匙串。")
    && !workspaceStoreSource.contains("已选择材料、当前选区和右侧笔记"), "agent context and setup notices avoid fake material fallback copy and visible internal agent labels")
if let askAgentStart = workspaceStoreSource.range(of: "func askAgent() async")?.lowerBound,
   let offlineInputStart = workspaceStoreSource.range(of: "private func offlineAgentInput")?.lowerBound {
    let askAgentSource = String(workspaceStoreSource[askAgentStart..<offlineInputStart])
    let credentialRange = askAgentSource.range(of: "guard let credential = resolvedOpenAIAPIKey()")!
    expect(askAgentSource.range(of: "agentDraft = \"\"") != nil
        && askAgentSource.range(of: "selectionAttachments = []") != nil
        && askAgentSource.range(of: "let shouldClearSentDocumentSelection = sentSelectionText != nil && selectionContext?.source == .document") != nil
        && askAgentSource.range(of: "clearUnpinnedFloatingSelection(keepContext: false)") != nil
        && askAgentSource.range(of: "messages.append(contentsOf: AgentOfflineTurn.messages(") != nil
        && askAgentSource.range(of: "messages.append(AgentMessage(role: .user, text: question, source: sourceTitle))") != nil
        && askAgentSource.range(of: "let shouldClearSentDocumentSelection")!.lowerBound > askAgentSource.range(of: "let sentSelectionText = agentSelectionText")!.lowerBound
        && askAgentSource.range(of: "agentDraft = \"\"")!.lowerBound < credentialRange.lowerBound
        && askAgentSource.range(of: "selectionAttachments = []")!.lowerBound < credentialRange.lowerBound
        && askAgentSource.range(of: "clearUnpinnedFloatingSelection(keepContext: false)")!.lowerBound < credentialRange.lowerBound
        && askAgentSource.range(of: "messages.append(contentsOf: AgentOfflineTurn.messages(")!.lowerBound > credentialRange.lowerBound
        && askAgentSource.range(of: "messages.append(AgentMessage(role: .user, text: question, source: sourceTitle))")!.lowerBound > credentialRange.lowerBound,
        "agent send clears the composer before key validation and uses the offline turn helper when no API key exists")
} else {
    expect(false, "askAgent source is readable")
}
expect(workspaceStoreSource.contains("var agentPromptScope") && workspaceStoreSource.contains("var selectionPromptScope") && !workspaceStoreSource.contains("var libraryOrganizationScope"), "agent prompt builders avoid half-built library organization context")
expect(!workspaceStoreSource.contains("请根据当前文档和当前笔记") && !workspaceStoreSource.contains("请根据当前材料和当前笔记") && !workspaceStoreSource.contains("结合当前文档和笔记"), "agent draft presets do not hardcode fake material context")
expect(workspaceStoreSource.contains("正在静默阅读当前材料和笔记。")
    && workspaceStoreSource.contains("正在静默阅读当前笔记。")
    && !workspaceStoreSource.contains("Agent 正在静默阅读"), "quiet insight progress copy avoids a visible internal agent label")
expect(workspaceStoreSource.contains("scenario == \"notebook-creation-flow\"")
    && workspaceStoreSource.contains("promptCreateBlankNotebookNote()\n            return"), "visual verification can exercise blank notebook creation")
expect(workspaceStoreSource.contains("private func noteBlockForAgentAnswer")
    && workspaceStoreSource.contains("AgentOfflinePreview.suggestedNoteBlock(from: text, language: interfaceLanguage)")
    && workspaceStoreSource.contains("guard !text.hasPrefix(\"#\") else { return text }")
    && workspaceStoreSource.contains("return \"## \\(ui(\"整理建议\", \"Organization suggestion\"))\\n\\(text)\"")
    && workspaceStoreSource.contains("markdown: \"\\n\\(noteBlockForAgentAnswer(answer.text))\"")
    && !workspaceStoreSource.contains("## Agent 整理建议"), "agent note writeback uses a note-ready offline section before falling back to a plain reader-facing suggestion heading")
expect(workspaceStoreSource.contains("func createBlankNotebookNote()")
    && workspaceStoreSource.contains("func createNotebookNoteFromCurrentMaterial()")
    && workspaceStoreSource.contains("func promptCreateBlankNotebookNote()")
    && workspaceStoreSource.contains("func promptCreateNotebookNoteFromCurrentMaterial()")
    && workspaceStoreSource.contains("@Published var notebookCreationDraft")
    && workspaceStoreSource.contains("struct NotebookCreationDraft")
    && workspaceStoreSource.contains("private func createNotebookNote(seed: NotebookNoteSeed, title")
    && !workspaceStoreSource.contains("func resetNote()")
    && !workspaceStoreSource.contains("updateNote(defaultNote(for: selectedItem))"), "new note commands separate blank notes from current-material notes and route through the inline naming strip")
expect(workspaceStoreSource.contains("private func openExistingNotebookNote(for material: StudyItem) -> Bool")
    && workspaceStoreSource.contains("if openExistingNotebookNote(for: selectedMaterialItem)")
    && workspaceStoreSource.contains("private func existingNotebookNote(for material: StudyItem) -> StudyItem?")
    && workspaceStoreSource.contains("let titles = Set([currentTitle, chineseTitle, englishTitle, displayChineseTitle, displayEnglishTitle])")
    && workspaceStoreSource.contains("已打开现有资料笔记"), "current-material note creation opens an existing matching notebook note instead of prompting a duplicate")
expect(workspaceStoreSource.contains("case currentMaterial(StudyItem)")
    && workspaceStoreSource.contains("private func suggestedNotebookTitle(for seed: NotebookNoteSeed)")
    && workspaceStoreSource.contains("let markdown = defaultNotebookNote(title: item.title, sourceItem: sourceItem)")
    && workspaceStoreSource.contains("try markdown.write(to: url"), "new notebook notes are backed by local markdown files and can be seeded from the current material")
expect(workspaceStoreSource.contains("func cancelNotebookNoteCreation()")
    && workspaceStoreSource.contains("func confirmNotebookNoteCreation()")
    && workspaceStoreSource.contains("notebookCreationDraft = NotebookCreationDraft(")
    && workspaceStoreSource.contains("let title = draft.title.trimmingCharacters")
    && workspaceStoreSource.contains("func select(itemID: String?) {\n        persistCurrentNote()\n        notebookCreationDraft = nil")
    && !workspaceStoreSource.contains("private func promptCreateNotebookNote(seed: NotebookNoteSeed)")
    && !workspaceStoreSource.contains("alert.messageText = seed.isBlank"), "new-note creation opens the inline naming strip and confirms through the shared local markdown creator")
expect(workspaceStoreSource.contains("importedItems.append(item)\n            activeNotebookItemID = item.id\n            noteText = markdown\n            revealRichWritingSurface()\n            focus(.notes)\n            save()"), "new notebook notes open in the note pane without replacing the reader material")
expect(workspaceStoreSource.contains("private func showTransientNoteStatus(_ message: String)")
    && workspaceStoreSource.contains("Task { @MainActor [weak self] in")
    && workspaceStoreSource.contains("if self?.noteFileError == message")
    && workspaceStoreSource.contains("已新建空白笔记")
    && workspaceStoreSource.contains("已为当前资料新建笔记"), "successful note creation feedback clears itself and names the creation path")
expect(workspaceStoreSource.contains("func promptRenameNotebookNote(itemID: String)")
    && workspaceStoreSource.contains("@Published var notebookRenameDraft")
    && workspaceStoreSource.contains("struct NotebookRenameDraft")
    && workspaceStoreSource.contains("func cancelRenameNotebookNote()")
    && workspaceStoreSource.contains("func confirmRenameNotebookNote()")
    && workspaceStoreSource.contains("func renameNotebookNote(itemID: String, to rawTitle: String)")
    && workspaceStoreSource.contains("try FileManager.default.moveItem(at: oldURL, to: newURL)")
    && workspaceStoreSource.contains("activeNotebookItemID = newID")
    && workspaceStoreSource.contains("retitledMarkdown(noteText, from: oldTitle")
    && workspaceStoreSource.contains("replaceNavigationItemID(oldID, with: newID)")
    && workspaceStoreSource.contains("notebookRenameDraft = nil")
    && !workspaceStoreSource.contains("alert.messageText = ui(\"重命名笔记\""), "renaming a notebook note updates the local markdown file, active note identity, heading, and navigation snapshots without a system alert")
expect(workspaceStoreSource.contains("let title = item.map(displayTitle) ?? ui(\"新笔记\"")
    && workspaceStoreSource.contains("let sourceItem = item?.isNotebookNote == true ? nil : item")
    && workspaceStoreSource.contains("private func defaultNotebookNote(title: String, sourceItem: StudyItem?)")
    && workspaceStoreSource.contains("let excerptSeed = sourceItem.map { ui(\"> 来源：\\(displayTitle(for: $0))\\n\"")
    && workspaceStoreSource.contains("## \\(ui(\"核心要点\", \"Key Points\"))")
    && workspaceStoreSource.contains("## \\(ui(\"待追问\", \"Follow-up Questions\"))")
    && !workspaceStoreSource.contains("## 核心要点\n        - ")
    && !workspaceStoreSource.contains("## 待追问\n        - ")
    && !workspaceStoreSource.contains("未命名材料"), "new note templates avoid fake source copy and empty bullets")
expect(workspaceStoreSource.contains("return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))")
    && workspaceStoreSource.contains("cleanLegacyPlaceholder(try String(contentsOf: url, encoding: .utf8))")
    && workspaceStoreSource.contains("静默洞察|Agent 洞察")
    && workspaceStoreSource.contains("with: \"> [!note] 阅读线索\\n>\\n> $1\\n>\\n> 来源：$2\"")
    && workspaceStoreSource.contains(#"(?m)^> \[!note\] 阅读线索\n> ([^\n])"#)
    && workspaceStoreSource.contains(#"(?m)^> \[!quote\]([^\n]*)\n> ([^\n])"#)
    && workspaceStoreSource.contains(".replacingOccurrences(of: \"\\n* <br />\\n\", with: \"\\n\")")
    && workspaceStoreSource.contains(".replacingOccurrences(of: \"\\n- <br />\\n\", with: \"\\n\")"), "note loading cleans legacy empty-list placeholders")
expect(workspaceStoreSource.contains("已创建双链笔记：\\(url.lastPathComponent)") && !workspaceStoreSource.contains("已创建双链笔记：\\(url.path)") && !workspaceStoreSource.contains("无法创建双链笔记：\\(url.path)"), "wikilink note statuses avoid exposing full local paths")
expect(workspaceStoreSource.contains("private func revealRichWritingSurface()")
    && workspaceStoreSource.contains("layout = .immersiveWriting")
    && workspaceStoreSource.contains("showNotes = true")
    && workspaceStoreSource.contains("noteRenderMode = .rich"), "writing actions share one rich writing surface reveal")
expect(workspaceStoreSource.contains("func insertMarkdownSnippet(_ markdown: String) {\n        revealRichWritingSurface()")
    && workspaceStoreSource.contains("func useSelectedMarkdownAsNotebookNote()")
    && workspaceStoreSource.contains("revealRichWritingSurface()\n        focus(.notes)"), "markdown insertion and imported markdown notes reveal the rich writing surface")
expect(!workspaceStoreSource.contains("当前页提示"), "quiet insight avoids old page alert title")
expect(workspaceStoreSource.contains("阅读线索"), "quiet insight uses margin-note language")
expect(appSource.contains("if store.canCopyReference") && appSource.contains("if store.hasSelectedMaterial") && appSource.contains("Button(store.ui(\"打开资料内搜索\""), "app menu hides material-only actions when there is no material context")
expect(appSource.contains("Button(store.ui(\"新建空白笔记\"") && appSource.contains("{ animateLayout { store.promptCreateBlankNotebookNote() } }")
    && appSource.contains("Button(store.ui(\"从当前资料开笔记\"")
    && appSource.contains("animateLayout { store.promptCreateNotebookNoteFromCurrentMaterial() }"), "new-note menu commands use layout motion and expose blank/material paths separately")
expect(appSource.contains("Button(store.sendAgentActionTitle)") && workspaceStoreSource.contains("var sendAgentActionTitle: String"), "app send command uses one stable action label")
expect(appSource.contains("if !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty")
    && appSource.contains(".keyboardShortcut(.return, modifiers: [.command])"), "app menu hides the agent send action until a draft can really send")
expect(appSource.contains("Button(store.showLibrary ? store.ui(\"收起课程目录\"")
    && !appSource.contains("恢复资料")
    && appSource.contains("Button(store.showRightPane ? store.ui(\"收起辅助栏\""), "app menu names pane toggles by current state")
expect(appSource.contains("Button(store.ui(\"三栏工作台\", \"Three-Pane Workspace\"))")
    && !appSource.contains("Button(WorkspaceLayout.documentNotesAgent.label")
    && appSource.contains("Button(WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage))")
    && appSource.contains("Button(store.ui(\"交换笔记与对话\"")
    && appSource.contains("store.swapThreePaneSecondaryPanes()")
    && appSource.contains(".keyboardShortcut(\"s\", modifiers: [.command, .option])")
    && appSource.contains(".keyboardShortcut(\"2\", modifiers: [.command, .option])"), "app menu exposes one draggable three-pane workspace entry and gives split view the second layout shortcut")
expect(appSource.contains("Button(AgentSurface.bottomDrawer.actionLabel(language: store.interfaceLanguage))")
    && appSource.contains("Button(AgentSurface.selectionFloat.actionLabel(language: store.interfaceLanguage))")
    && appSource.contains("if store.canUseSelectionAgentSurface")
    && AgentSurface.hidden.label(language: .chinese) == "隐藏对话"
    && AgentSurface.hidden.label(language: .english) == "Hide Chat"
    && AgentSurface.hidden.actionLabel(language: .english) == "Hide Chat"
    && !appSource.contains("Agent 底部抽屉")
    && !appSource.contains("Agent 右下角小窗")
    && !appSource.contains("Agent 划线浮层")
    && !appSource.contains("Agent 静默洞察"), "app menu uses the same user-facing agent surface labels as the command palette")
expect(appSource.contains("if store.layout.hasCollapsibleRightPane")
    && appSource.contains("if store.canApplyAgentAnswer")
    && appSource.contains("if store.canReplaceNoteSelection")
    && !appSource.contains(".disabled("), "app menu hides unavailable actions instead of showing disabled grey items")
expect(appSource.contains("Button(store.ui(\"聚焦课程目录\"")
    && appSource.contains("{ animateLayout { store.focus(.library) } }")
    && appSource.contains("Button(store.ui(\"聚焦对话\"")
    && appSource.contains("{ animateLayout { store.focus(.agent) } }")
    && !appSource.contains("Button(\"聚焦 Agent\")")
    && appSource.contains("Button(store.ui(\"下一份资料\"")
    && appSource.contains("{ animateLayout { store.selectAdjacentItem(step: 1) } }"), "app menu focus and material navigation use the same layout motion as shortcuts")
expect(appSource.contains("Button(store.ui(\"写入回答到笔记\"")
    && appSource.contains("{ animatePanel { store.applyLastAgentAnswerToNote() } }")
    && appSource.contains("Button(store.ui(\"替换笔记选区\"")
    && appSource.contains("{ animatePanel { store.replaceSelectionWithLastAgentAnswer() } }")
    && appSource.contains("Button(store.ui(\"追加整理建议\"")
    && appSource.contains("{ animatePanel { store.applyAgentPatchToEditor() } }")
    && !appSource.contains("用 Agent 替换笔记选区")
    && !appSource.contains("追加 Agent 整理建议"), "app menu agent write actions use the same panel motion as shortcuts")
let directPromptConsumers = [appSource, contentViewSource, sidebarSource, commandPaletteSource, notesAgentSource].joined(separator: "\n")
expect(!directPromptConsumers.contains("WeiBeiInputPrompt("), "views use the shared input prompt overlay instead of direct prompt layering")
expect(!workspaceStoreSource.contains("请解释我刚才选中的内容") && !notesAgentSource.contains("请解释我刚才选中的内容"), "agent entry does not invent a missing selection")
expect(notesAgentSource.contains("compactHovering")
    && !notesAgentSource.contains(".weibeiAnnotationPanel(cornerRadius: 5)")
    && notesAgentSource.contains(".background(WeiBeiTheme.paperRaised.opacity(compactHovering ? 0.42 : 0.0))")
    && notesAgentSource.contains("WeiBeiTheme.hairline.opacity(compactHovering ? 0.40 : 0.0)"), "compact quiet insight stays a light margin note instead of a permanent card")
expect(!notesAgentSource.contains(".opacity(compactHovering ? 1 : 0.68)")
    && notesAgentSource.contains("if compactHovering {\n                HStack(spacing: 4)"), "compact quiet insight actions stay hidden until hover without dimming the text")
expect(notesAgentSource.contains("if compactHovering {\n                HStack(spacing: 4)") && notesAgentSource.contains(".transition(WeiBeiTransition.floating)"), "compact quiet insight keeps actions hidden until hover")
expect(notesAgentSource.contains("@State private var panelHovering = false")
    && notesAgentSource.contains("if panelHovering {\n                        HStack(spacing: 4)")
    && notesAgentSource.contains("iconButton(\"text.badge.plus\", help: store.ui(\"收进摘录\"")
    && notesAgentSource.contains("iconButton(\"bubble.left\", help: store.ui(\"追问\"")
    && notesAgentSource.contains("iconButton(\"xmark\", help: store.ui(\"忽略阅读线索\"")
    && !notesAgentSource.contains("Button(\"收进摘录\")")
    && !notesAgentSource.contains("Button(\"追问\")")
    && !notesAgentSource.contains("Button(\"忽略\")"), "regular quiet insight behaves like a margin note: actions are icon-only and hidden until hover")
expect(notesAgentSource.contains("let itemID = store.activeNoteItemID") && notesAgentSource.contains("store.updateNote(value, for: itemID)"), "rich note editor writes through active note guard")
expect(notesAgentSource.components(separatedBy: "MarkdownPreviewView(").dropFirst().allSatisfy { $0.contains("appearanceMode: store.appearanceMode") }, "all markdown preview paths inherit the current appearance mode, including split compare")
expect(notesAgentSource.contains("case .split:")
    && notesAgentSource.contains("MarkdownPreviewView(\n                        markdown: draftNoteText")
    && notesAgentSource.contains("compact: true,\n                        fitsContentHeight: false")
    && notesAgentSource.contains("var fitsContentHeight = true")
    && notesAgentSource.contains("guard compact && fitsContentHeight else { return }")
    && notesAgentSource.contains(".frame(height: compact && fitsContentHeight ? max(contentHeight, 44) : nil)"), "split note compare uses compact preview typography without collapsing the preview pane height")
expect(notesAgentSource.contains("func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View")
    && notesAgentSource.contains("struct WeiBeiPaneHeader<Actions: View>: View")
    && notesAgentSource.contains("var title: String")
    && notesAgentSource.contains("var latinMark: String? = nil")
    && notesAgentSource.contains("var subtitle: String")
    && notesAgentSource.contains("var reorderRole: WorkspacePaneRole? = nil")
    && notesAgentSource.contains("HStack(alignment: .firstTextBaseline, spacing: 8)")
    && notesAgentSource.contains("Text(title)")
    && notesAgentSource.contains("Text(subtitle)")
    && !notesAgentSource.contains("VStack(alignment: .leading, spacing: 2) {\n                Text(title)")
    && notesAgentSource.contains("WeiBeiHeaderHandoffFade(height: 28, opacity: 0.34)")
    && notesAgentSource.contains("func weibeiHeaderAccessoryGroup() -> some View")
    && noteModeControlSource.contains(".weibeiHeaderAccessoryGroup()")
    && !agentPaneHeaderSource.contains(".weibeiHeaderAccessoryGroup()")
    && !notesAgentSource.contains("private var hasAgentHeaderActions: Bool")
    && notesAgentSource.contains(".background(WeiBeiGlassHeaderBackground(paperOpacity: 0.72, materialOpacity: 0.12))")
    && notesAgentSource.contains(".animation(WeiBeiMotion.appearance, value: appearanceMode)")
    && notesAgentSource.components(separatedBy: ".weibeiPaneHeaderChrome(appearanceMode: appearanceMode)").count >= 2
    && notePaneHeaderSource.contains("title: store.ui(\"笔记\"")
    && agentPaneHeaderSource.contains("title: store.ui(\"对话\"")
    && notePaneHeaderSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"NOTES\" : nil")
    && agentPaneHeaderSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"CHAT\" : nil")
    && agentPaneHeaderSource.contains("subtitle: store.agentConversationSubtitle")
    && notePaneHeaderSource.contains("private var noteHeaderSubtitle: String")
    && notePaneHeaderSource.contains("Menu {")
    && notePaneHeaderSource.contains("store.ui(\"空白课程笔记\"")
    && notePaneHeaderSource.contains("store.ui(\"当前资料笔记\"")
    && notePaneHeaderSource.contains("if store.hasSelectedMaterial")
    && !notePaneHeaderSource.contains("if !isImmersiveWriting")
    && !notesAgentSource.contains("private var isImmersiveWriting")
    && notePaneHeaderSource.contains("store.promptCreateNotebookNoteFromCurrentMaterial()")
    && notePaneHeaderSource.contains("store.promptCreateBlankNotebookNote()")
    && !notePaneHeaderSource.contains("store.createNotebookNoteFromCurrentMaterial()")
    && !notePaneHeaderSource.contains("store.createBlankNotebookNote()")
    && notePaneHeaderSource.contains(".accessibilityLabel(Text(store.ui(\"新建课程笔记\"")
    && notePaneHeaderSource.contains(".accessibilityLabel(Text(store.ui(\"新建空白课程笔记\"")
    && notePaneHeaderSource.contains("Image(systemName: \"doc.badge.plus\")")
    && notePaneHeaderSource.contains(".buttonStyle(WeiBeiIconButtonStyle(size: 24))")
    && notePaneHeaderSource.contains("private var noteHeader: some View")
    && notePaneHeaderSource.contains("if let draft = store.notebookCreationDraft")
    && notePaneHeaderSource.contains(".weibeiPaneHeaderChrome(appearanceMode: store.appearanceMode)")
    && notePaneHeaderSource.contains(".modifier(PaneHeaderReorderModifier(role: reorderRole))")
    && notePaneHeaderSource.contains("private var newNoteControl: some View")
    && !notePaneHeaderSource.contains(".frame(width: 560, height: 42)")
    && notePaneHeaderSource.contains(".frame(width: 420, height: 34)")
    && notebookCreationPanelSource.contains("private var canCreate: Bool")
    && notebookCreationPanelSource.contains("store.ui(\"新建笔记\"")
    && notebookCreationPanelSource.contains("Image(systemName: \"checkmark\")")
    && notebookCreationPanelSource.contains("@State private var hoveredConfirm")
    && notebookCreationPanelSource.contains(".foregroundStyle(confirmColor)")
    && notebookCreationPanelSource.contains("return hoveredConfirm ? WeiBeiTheme.onCinnabar : WeiBeiTheme.secondaryInk")
    && notebookCreationPanelSource.contains("private var confirmBackground: Color")
    && notebookCreationPanelSource.contains("return WeiBeiTheme.cinnabar.opacity(0.88)")
    && notebookCreationPanelSource.contains("private var cancelBackground: Color")
    && notebookCreationPanelSource.contains("hoveredCancel ? WeiBeiTheme.cinnabarSoft.opacity(0.68) : Color.clear")
    && notebookCreationPanelSource.contains("withAnimation(WeiBeiMotion.hover)")
    && notebookCreationPanelSource.contains(".frame(height: 30)")
    && notebookCreationPanelSource.contains("WeiBeiTheme.paperInset.opacity(0.24)")
    && notebookCreationPanelSource.contains("WeiBeiTheme.hairline.opacity(0.34)")
    && !notebookCreationPanelSource.contains("Rectangle()\n                .fill(WeiBeiTheme.cinnabar")
    && !notebookCreationPanelSource.contains(".weibeiHeaderAccessoryGroup()")
    && notesAgentSource.contains("store.confirmNotebookNoteCreation()")
    && notesAgentSource.contains("store.cancelNotebookNoteCreation()")
    && !notesAgentSource.contains(".alert(")
    && !notesAgentSource.contains("NSAlert()")
    && !notesAgentSource.contains("store.ui(\"先命名，再创建本地 Markdown\"")
    && !notesAgentSource.contains("store.ui(\"资料笔记名称\"")
    && !notePaneHeaderSource.contains(".transition(WeiBeiTransition.message)")
    && !notePaneHeaderSource.contains(".padding(.top, 50)")
    && notePaneHeaderSource.contains(".transition(WeiBeiTransition.floating)")
    && !notesAgentSource.contains("NSAlert()")
    && !notePaneHeaderSource.contains("NoteCreateMenuLabel")
    && !notePaneHeaderSource.contains("Button(\"作为笔记编辑\")")
    && agentPaneHeaderSource.contains("EmptyView()")
    && !agentPaneHeaderSource.contains("agentToolButton(")
    && !notesAgentSource.contains("private func agentToolButton")
    && notesAgentSource.contains("Button(store.ui(\"写入回答\", \"Write Answer\"")
    && notesAgentSource.contains("Button(store.ui(\"替换\", \"Replace\"")
    && !notesAgentSource.contains(".labelStyle(.titleAndIcon)\n        }\n        .buttonStyle(WeiBeiTextActionButtonStyle())")
    && notePaneHeaderSource.contains(".background(WeiBeiTheme.paper)")
    && !notePaneHeaderSource.contains("mode.id != NoteRenderMode.visibleCases.last?.id"), "note pane creation and agent header stay custom, light, and context-only")
expect(noteModeControlSource.contains("NoteRenderMode.visibleCases")
    && notePaneHeaderSource.contains("@State private var hoveredNoteMode: NoteRenderMode?")
    && noteModeControlSource.contains("HStack(spacing: 3)")
    && !noteModeControlSource.contains("ViewThatFits(in: .horizontal)")
    && !noteModeControlSource.contains("noteModeButtonRail")
    && noteModeControlSource.contains("Image(systemName: noteModeIcon(for: mode))")
    && noteModeControlSource.contains("return Image(systemName: noteModeIcon(for: mode))")
    && noteModeControlSource.contains(".accessibilityLabel(Text(label))")
    && noteModeControlSource.contains("private func noteModeIcon(for mode: NoteRenderMode) -> String")
    && noteModeControlSource.contains(".fixedSize(horizontal: true, vertical: false)")
    && noteModeControlSource.contains("hoveredNoteMode == mode")
    && noteModeControlSource.contains("hoveredNoteMode = hovering ? mode")
    && !noteModeControlSource.contains("Image(systemName: noteModeSystemImage(for: mode))")
    && !notesAgentSource.contains("private func noteModeSystemImage(for mode: NoteRenderMode) -> String")
    && noteModeControlSource.contains("selected ? WeiBeiTheme.cinnabar : hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk")
    && !noteModeControlSource.contains("Capsule()")
    && noteModeControlSource.contains("noteModeButtonFill(selected: selected, hovering: hovering)")
    && noteModeControlSource.contains("noteModeButtonStroke(selected: selected, hovering: hovering)")
    && noteModeControlSource.contains("WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode == .inkstone ? 0.44 : 0.62)")
    && noteModeControlSource.contains("WeiBeiTheme.paperRaised.opacity(store.appearanceMode == .inkstone ? 0.16 : 0.20)")
    && noteModeControlSource.contains(".weibeiHeaderAccessoryGroup()")
    && noteModeControlSource.contains(".scaleEffect(hovering && !selected ? 1.012 : 1)")
    && !noteModeControlSource.contains(".stroke(WeiBeiTheme.hairline.opacity(0.14), lineWidth: 1)"), "note mode control is icon-only so narrow panes never collapse labels into ellipses")
expect(notesAgentSource.contains("ContextRailLine") && notesAgentSource.contains(".onHover"), "context rails keep hover motion")
expect(!notesAgentSource.contains(".id(store.noteRenderMode)"), "note mode changes avoid forced hard view identity resets")
expect(notesAgentSource.contains("struct ContextRailItem: Identifiable") && notesAgentSource.contains("Button(action: action)"), "context rails expose actionable rows")
expect(notesAgentSource.contains("var systemImage: String?") && notesAgentSource.contains("Image(systemName: systemImage)"), "context rail rows support semantic icons")
expect(notesAgentSource.contains(".accessibilityLabel(Text(item.help ?? item.title))") && notesAgentSource.contains(".help(item.help ?? item.title)"), "context rail actions explain their intent")
expect(notesAgentSource.contains("var edge: HorizontalEdge = .trailing") && notesAgentSource.contains("edge == .leading ? -3 : 3"), "context rails move inward from either side")
expect(!railBackgroundSource.isEmpty
    && railBackgroundSource.contains("WeiBeiTheme.paperRaised.opacity(0.10)")
    && railBackgroundSource.contains("WeiBeiTheme.paperRaised.opacity(0.26)")
    && railBackgroundSource.contains(".frame(width: 22)")
    && !railBackgroundSource.contains("WeiBeiTheme.paper.opacity(0.18)")
    && !railBackgroundSource.contains("WeiBeiTheme.paperRaised.opacity(0.40),\n                    WeiBeiTheme.paper.opacity(0.42),\n                    WeiBeiTheme.paper.opacity(0.28)"), "immersive context rails avoid full-height heavy background bands")
expect(!notesAgentSource.contains(".id(expanded)"), "selection agent expands without forcing a hard view identity reset")
expect(contentViewSource.contains("edge: .leading") && contentViewSource.contains("edge: .trailing"), "immersive rails declare their content-facing edge")
expect(contentViewSource.contains("conversationSourceRailItems") && contentViewSource.contains("conversationTargetRailItems") && contentViewSource.contains("writingAssistRailItems"), "immersive rails wire role-specific actions")
expect(contentViewSource.contains("systemImage: \"square.and.pencil\"") && contentViewSource.contains("systemImage: \"quote.opening\""), "immersive rail actions use stable semantic icons")
expect(contentViewSource.contains("@StateObject private var paneHostRegistry = PersistentPaneHostRegistry()")
    && contentViewSource.contains("private final class PersistentPaneHostRegistry: ObservableObject")
    && contentViewSource.contains("private struct PersistentPaneHost: NSViewRepresentable")
    && contentViewSource.contains("private final class PersistentPaneContainerView: NSView")
    && contentViewSource.contains("override func viewDidMoveToWindow()")
    && contentViewSource.contains("guard container.window != nil else")
    && contentViewSource.contains("PersistentPaneHost(role: .reader, registry: paneHostRegistry)")
    && contentViewSource.contains("PersistentPaneHost(role: .agent, registry: paneHostRegistry)")
    && contentViewSource.contains("PersistentPaneHost(role: .notes, registry: paneHostRegistry)")
    && contentViewSource.contains("host.removeFromSuperview()")
    && contentViewSource.contains("host.autoresizingMask = [.width, .height]")
    && contentViewSource.contains("private struct OwnerToken: Equatable")
    && contentViewSource.contains("func registerOwner(for role: WorkspacePaneRole) -> OwnerToken")
    && contentViewSource.contains("guard latestOwnerGeneration[role] == owner.generation else { return }")
    && contentViewSource.contains("guard activeOwners[role] == owner, host.superview === container else { return }")
    && !contentViewSource.contains("paneView(for: drag.role, reorderable: false)"), "core pane hosts survive immersive, single-pane, and split-layout changes instead of recreating their reader or editor state")
expect(contentViewSource.contains("case .documentAgentNotes, .documentNotesAgent:")
    && contentViewSource.contains("documentPaneLayoutView()")
    && contentViewSource.contains("reorderablePaneView(for: order[0])")
    && contentViewSource.contains("PaneReorderPreviewView(role: drag.role)")
    && contentViewSource.contains(".opacity(drag?.role == role ? 0.08 : 1)")
    && contentViewSource.contains(".opacity(0.11)")
    && contentViewSource.contains("PersistentPaneHost(role: role, registry: paneHostRegistry)")
    && contentViewSource.contains("private struct PersistentPaneRoot: View")
    && contentViewSource.contains("AgentPaneView(showsPaneHeader: false, reorderRole: reorderRole)")
    && contentViewSource.contains("NotePaneView(showsPaneHeader: false, reorderRole: reorderRole)")
    && !contentViewSource.contains("PaneReorderGhostView")
    && contentViewSource.contains("PaneDropTargetView(role: order[targetIndex])")
    && contentViewSource.contains("threePaneReorderOverlay(order: order")
    && contentViewSource.contains("private func documentPaneLayoutView() -> some View")
    && contentViewSource.contains("let order = store.visibleDocumentPaneOrder")
    && contentViewSource.contains("EmptyWorkspaceView()")
    && contentViewSource.contains("documentTwoPaneView(order: order)")
    && contentViewSource.contains("documentThreePaneView(order: Array(order.prefix(3)))")
    && contentViewSource.contains("let estimatedFrames = threePaneFrames(order: order, size: geometry.size)")
    && contentViewSource.contains("store.threePaneReorderFrameList(order: order, fallback: estimatedFrames)")
    && contentViewSource.contains("onFramesChange: { frames in")
    && contentViewSource.contains("ThreePaneReorderFrameReporter(order: order, frames: estimatedFrames)")
    && !contentViewSource.contains("case .documentAgentNotes:\n                if store.showRightPane"), "document pane layouts render from the visible pane set and one draggable pane role order")
expect(paneHeaderReorderSource.contains("struct PaneHeaderReorderModifier")
    && paneHeaderReorderSource.contains(".textSelection(.disabled)")
    && paneHeaderReorderSource.contains(".highPriorityGesture(")
    && paneHeaderReorderSource.contains("DragGesture(minimumDistance: 12, coordinateSpace: .global)")
    && paneHeaderReorderSource.contains("@State private var hovering = false")
    && !paneHeaderReorderSource.contains("@State private var dragOffset")
    && !paneHeaderReorderSource.contains(".offset(x: dragOffset)")
    && paneHeaderReorderSource.contains(".offset(y: hovering || dragActive ? -1 : 0)")
    && paneHeaderReorderSource.contains(".scaleEffect(dragActive ? 1.01 : hovering ? 1.004 : 1, anchor: .top)")
    && !paneHeaderReorderSource.contains("Rectangle()\n                            .stroke(WeiBeiTheme.cinnabar.opacity")
    && paneHeaderReorderSource.contains("NSCursor.openHand.push()")
    && paneHeaderReorderSource.contains(".onHover { value in")
    && paneHeaderReorderSource.contains("store.beginThreePaneReorder(role)")
    && paneHeaderReorderSource.contains("store.updateThreePaneReorder(role, horizontalDelta: value.translation.width)")
    && paneHeaderReorderSource.contains("store.finishThreePaneReorder(role, horizontalDelta: value.translation.width)")
    && !paneHeaderReorderSource.contains(".help(store.ui(\"拖动标题栏重排三栏\"")
    && readerViewSource.contains(".modifier(PaneHeaderReorderModifier(role: reorderRole))")
    && notesAgentSource.contains("reorderRole: reorderRole"), "floating pane title slips act as handles while the full pane reorder ghost is rendered by the workspace")
expect(!readerViewSource.contains("struct ReaderPaneView")
    && readerViewSource.contains("struct ImmersiveHoverTitleView")
    && readerViewSource.contains("var reorderRole: WorkspacePaneRole?")
    && readerViewSource.contains("WeiBeiTypography.englishBrandFont(size: 9.8")
    && readerViewSource.contains(".baselineOffset(0.7)")
    && readerViewSource.contains("ViewThatFits(in: .horizontal)")
    && readerViewSource.contains(".fixedSize(horizontal: true, vertical: false)")
    && readerViewSource.contains(".truncationMode(.tail)")
    && readerViewSource.contains(".frame(maxWidth: .infinity)")
    && readerViewSource.contains(".frame(maxWidth: actionsAlignedTrailing ? .infinity : nil, alignment: .leading)")
    && readerViewSource.contains(".padding(.horizontal, actionsAlignedTrailing ? 14 : 0)")
    && readerViewSource.contains("mark: \"DOC\"")
    && readerViewSource.contains("title: floatingTitle")
    && readerViewSource.contains("reorderRole: floatingTitleReorderRole")
    && readerViewSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)")
    && contentViewSource.contains("isImmersive: store.layout == .immersiveReading")
    && contentViewSource.contains("case .immersiveConversation:\n                PersistentPaneHost(role: .agent, registry: paneHostRegistry)")
    && !contentViewSource.contains("case .immersiveConversation:\n                if store.showRightPane")
    && contentViewSource.contains("PersistentPaneHost(role: .reader, registry: paneHostRegistry)")
    && contentViewSource.contains("PersistentPaneHost(role: .notes, registry: paneHostRegistry)")
    && notesAgentSource.contains("ImmersiveHoverTitleView(mark: \"CHAT\", title: store.agentConversationSubtitle")
    && notesAgentSource.contains("reorderRole: reorderRole")
    && notesAgentSource.contains("mark: \"NOTES\"")
    && notesAgentSource.contains("title: noteHeaderSubtitle")
    && notesAgentSource.contains("actionsAlignedTrailing: true")
    && notesAgentSource.contains("noteModeControl")
    && notesAgentSource.contains("newNoteControl")
    && notesAgentSource.contains("isPinned: store.notebookCreationDraft != nil")
    && notesAgentSource.contains("notebookCreationPanel(draft: draft)"), "immersive and single-pane views hide heavy pane headers while the Notes hover slip keeps mode and new-note actions")
expect(workspaceStoreSource.contains("@Published var threePaneOrder")
    && workspaceStoreSource.contains("@Published var threePaneReorderDrag")
    && workspaceStoreSource.contains("func threePaneReorderFrameList(order: [WorkspacePaneRole], fallback: [CGRect]) -> [CGRect]")
    && workspaceStoreSource.contains("private func sameReorderFrames")
    && workspaceStoreSource.contains("func swapThreePaneRoles")
    && workspaceStoreSource.contains("func swapThreePaneSecondaryPanes")
    && workspaceStoreSource.contains("func moveThreePaneRole")
    && workspaceStoreSource.contains("func beginThreePaneReorder")
    && workspaceStoreSource.contains("func updateThreePaneReorderFrames")
    && workspaceStoreSource.contains("func updateThreePaneReorder")
    && workspaceStoreSource.contains("func finishThreePaneReorder")
    && workspaceStoreSource.contains("ThreePaneReorderTargeting.targetIndex(")
    && workspaceStoreSource.contains("frames: threePaneReorderFrames")
    && !workspaceStoreSource.contains("contains(CGPoint(x: draggedCenterX")
    && !workspaceStoreSource.contains("let threshold: CGFloat = 84")
    && workspaceStoreSource.contains("private func threePaneReorderTargetIndex")
    && workspaceStoreSource.contains("private func applyThreePaneOrder")
    && !workspaceStoreSource.contains("guard dragged != .reader, target != .reader else { return }")
    && !workspaceStoreSource.contains("guard role != .reader else { return }")
    && workspaceStoreSource.contains("layoutMatchingThreePaneOrder")
    && workspaceStoreSource.contains("threePaneOrder: normalizedThreePaneOrder"), "workspace store owns, drags, swaps, and persists custom three-pane order")
expect(!contentViewSource.contains("ContextRailItem(title: store.ui(\"课程目录\"")
    && contentViewSource.contains("topIconButton(\"sidebar.left\"")
    && contentViewSource.contains("store.toggleLibrary()")
    && workspaceStoreSource.contains("func revealLibrary()"), "immersive rails do not duplicate the course index because the top bar owns the library entry")
expect(!appSource.contains("沉浸模式也保留课程目录入口")
    && !appSource.contains("Immersive modes keep the course index entry")
    && !appSource.contains("Button(store.showLibrary ? store.ui(\"收起\", \"Hide\") : store.ui(\"打开\", \"Show\"))"), "settings does not duplicate the top bar course index toggle")
expect(contentViewSource.contains("help: store.ui(\"追问当前选区\"")
    && contentViewSource.contains("help: store.ui(\"整理问题、结论和缺少证据\"")
    && contentViewSource.contains("help: store.ui(\"生成笔记大纲\"")
    && contentViewSource.contains("help: store.ui(\"检查笔记缺少来源的位置\"")
    && contentViewSource.contains("help: store.ui(\"润色当前笔记\"")
    && !contentViewSource.contains("help: \"用 Agent")
    && !contentViewSource.contains("help: \"让 Agent"), "immersive rail help text uses direct task language instead of internal agent wording")
expect(contentViewSource.contains("store.agentPromptScope")
    && contentViewSource.contains("store.hasSelectedMaterial ? store.ui(\"请检查当前笔记缺少来源的位置")
    && contentViewSource.contains("store.ui(\"请检查当前笔记缺少来源的位置，并标出需要补证据的段落。\""), "immersive agent rails reuse real context wording")
expect(contentViewSource.contains(".overlay(alignment: agentAlignment)") && contentViewSource.contains("if store.agentSurface != .quietInsight {\n                        agentOverlay"), "immersive layouts can show the lightweight agent overlay")
expect(!contentViewSource.contains("来源预览"), "immersive writing document rail avoids duplicate reader entries")
expect(!contentViewSource.contains("title: store.selectedItem?.title ?? \"当前材料\"") && contentViewSource.contains("if let item = store.selectedMaterialItem"), "immersive rails avoid fake current material entries")
expect(contentViewSource.contains("store.appendSelectionToNote()") && contentViewSource.contains("store.copyCurrentReference()") && contentViewSource.contains("prepareAgentDraft"), "immersive rails connect to existing note, reference, and agent actions")
expect(!notesAgentSource.contains("Agent 抽屉"), "agent drawer avoids engineering labels")
expect(!notesAgentSource.contains("Agent 只在右下角待命"), "corner agent avoids explanatory placeholder copy")
expect(!notesAgentSource.contains("魏碑会优先读取材料"), "agent empty state avoids product-explainer copy")
expect(!notesAgentSource.contains("Text(\"当前上下文\")") && !notesAgentSource.contains("contextLine("), "agent empty state avoids diagnostic context rows")
expect(notesAgentSource.contains("private struct AgentSelectionAttachmentPill")
    && notesAgentSource.contains("Image(systemName: \"text.bubble\")")
    && notesAgentSource.contains("Text(store.ui(\"\\(store.selectionAttachments.count) 个已选文本片段\"")
    && notesAgentSource.contains("\"\\(store.selectionAttachments.count) selected text fragments\"")
    && notesAgentSource.contains("store.ui(\"清空已选文本片段\"")
    && notesAgentSource.contains(".popover(isPresented: popoverPresented, arrowEdge: .bottom)")
    && notesAgentSource.contains("store.clearSelectionAttachments()")
    && notesAgentSource.contains("store.ui(\"清空\", \"Clear\")")
    && notesAgentSource.contains("ForEach(Array(store.selectionAttachments.enumerated()), id: \\.element.id)")
    && notesAgentSource.contains("store.removeSelectionAttachment(id: selection.id)")
    && notesAgentSource.contains("Image(systemName: \"xmark\")")
    && notesAgentSource.contains(".buttonStyle(WeiBeiIconButtonStyle(size: 20))")
    && notesAgentSource.contains("selectionAttachmentRow(index: index, selection: selection)")
    && notesAgentSource.components(separatedBy: "AgentSelectionAttachmentPill()").count >= 4
    && !notesAgentSource.contains("Text(\"1 个已选文本片段\")")
    && !notesAgentSource.contains("Text(\"已含选区\")"), "agent selection context renders as a hoverable attachment pill near composers instead of text inside the empty state")
if let attachmentRowStart = notesAgentSource.range(of: "private func selectionAttachmentRow")?.lowerBound,
   let attachmentHoverStart = notesAgentSource[attachmentRowStart...].range(of: "private func setPillHovering")?.lowerBound {
    let attachmentRowSource = String(notesAgentSource[attachmentRowStart..<attachmentHoverStart])
    expect(attachmentRowSource.contains("Text(selection.text)")
        && attachmentRowSource.contains(".allowsHitTesting(false)")
        && !attachmentRowSource.contains(".textSelection(.enabled)"), "selected text attachment popover previews do not trap scroll or text drag events")
} else {
    expect(false, "selected text attachment row source is inspectable")
}
if let noteBridgeStart = notesAgentSource.range(of: "onAskAgentWithSelection: { text, anchor in")?.lowerBound,
   let wikiLinkStart = notesAgentSource[noteBridgeStart...].range(of: "}, onWikiLink:")?.lowerBound {
    let noteSelectionBridgeSource = String(notesAgentSource[noteBridgeStart..<wikiLinkStart])
    expect(noteSelectionBridgeSource.contains("store.updateSelection(text, source: .note, anchor: anchor)")
        && noteSelectionBridgeSource.contains("store.askSelection()")
        && !noteSelectionBridgeSource.contains("askAgent()"), "rich markdown selection ask action attaches the selection without auto-sending a generated prompt")
} else {
    expect(false, "rich markdown selection ask bridge is inspectable")
}
expect(!emptyAgentStateSource.isEmpty
    && !emptyAgentStateSource.contains("noteContextTitle")
    && !emptyAgentStateSource.contains("Text(store.selectedMaterialItem?.title ?? \"当前笔记\")")
    && !emptyAgentStateSource.contains(".fill(WeiBeiTheme.cinnabar.opacity(0.34))"), "agent empty state avoids a repeated title card and heavy cinnabar rule")
expect(notesAgentSource.contains("AgentStarterChip") && notesAgentSource.contains("hovering ? -1 : 0"), "agent starter chips keep subtle hover motion")
expect(notesAgentSource.contains("if store.hasSelectedMaterial")
    && notesAgentSource.contains("starterChip(store.ui(\"梳理\", \"Outline\"")
    && notesAgentSource.contains("help: store.ui(\"梳理当前材料\", \"Outline current material\"")
    && notesAgentSource.contains("starterChip(store.ui(\"出题\", \"Quiz\"")
    && notesAgentSource.contains("help: store.ui(\"生成复习题\", \"Generate review questions\"")
    && !notesAgentSource.contains("starterChip(\"梳理材料\"")
    && !notesAgentSource.contains("starterChip(\"出复习题\""), "agent starter chips hide material actions without a selected material and avoid clipped long labels")
expect(notesAgentSource.contains("GeometryReader { geometry in")
    && notesAgentSource.contains("let availableWidth = max(geometry.size.width - ContentRailMetrics.normalWidth, 1)")
    && notesAgentSource.contains("let contentWidth = min(max(availableWidth - 36, 320), agentContentMaxWidth ?? 760)")
    && notesAgentSource.contains("agentMessageRow(message: message, geometryWidth: availableWidth, contentWidth: contentWidth, proxy: proxy)")
    && notesAgentSource.contains("private func agentMessageRow(message: AgentMessage, geometryWidth: CGFloat, contentWidth: CGFloat, proxy: ScrollViewProxy) -> some View")
    && notesAgentSource.contains(".padding(.top, store.messages.isEmpty ? 22 : 0)")
    && notesAgentSource.contains(".frame(width: availableWidth, alignment: .topLeading)")
    && notesAgentSource.contains(".frame(minHeight: geometry.size.height, alignment: .topLeading)")
    && !notesAgentSource.contains("alignment: store.messages.isEmpty ? .bottomLeading : .topLeading"), "agent empty state starts in the content area instead of being pinned to the composer")
expect(notesAgentSource.contains("canPolishNoteSelection") && notesAgentSource.contains("store.selectionContext?.isNoteSelection == true"), "selection agent only shows polish for note selections")
expect(notesAgentSource.contains("Text(store.ui(\"正在读选区...\", \"Reading selection...\"))")
    && notesAgentSource.contains(".foregroundStyle(WeiBeiTheme.secondaryInk)")
    && notesAgentSource.contains("message.text.hasPrefix(\"请求失败：\") || message.text.hasPrefix(\"Agent 请求失败：\") || message.text.hasPrefix(\"Request failed:\")")
    && notesAgentSource.contains("if message.role == .user {\n            return WeiBeiTheme.link")
    && !notesAgentSource.contains("if message.role == .user || message.text.hasPrefix(\"Agent 请求失败：\")"), "selection floating agent reserves cinnabar for real failures instead of ordinary progress or user text")
expect(notesAgentSource.contains("private var isCredentialNotice: Bool")
    && notesAgentSource.contains("message.text.hasPrefix(\"未配置密钥\")")
    && notesAgentSource.contains("message.text.hasPrefix(\"未配置 OPENAI_API_KEY\")")
    && notesAgentSource.contains("message.text.hasPrefix(\"No key is configured\")")
    && notesAgentSource.contains("isOfflineContextPreview")
    && notesAgentSource.contains("return message.text")
    && notesAgentSource.contains("Text(store.ui(\"需要设置密钥\", \"Key Required\"))")
    && notesAgentSource.contains("let scope = store.hasSelectionAttachments ? store.ui(\"\\(store.agentPromptScope)、已选文本片段\"")
    && notesAgentSource.contains("store.ui(\"设置后会结合\\(scope)作答；未配置时不会编造内容。\"")
    && notesAgentSource.contains("private var assistantTurn: some View")
    && notesAgentSource.contains("AgentMessageMarkdownText(")
    && notesAgentSource.contains("rendersRichMarkdown: false")
    && notesAgentSource.contains("rendersRichMarkdown: true")
    && notesAgentSource.contains("onContentHeightChange: onMarkdownHeightChange")
    && notesAgentSource.contains("MarkdownPreviewView(\n                markdown: text")
    && notesAgentSource.contains("compact: true")
    && notesAgentSource.contains(".background(compact ? Color.clear : WeiBeiTheme.paper)")
    && notesAgentSource.contains(".background(showsPaneHeader ? WeiBeiTheme.paper : Color.clear)")
    && notesAgentSource.contains("paperOpacity: showsPaneHeader ? 0.34 : 0.14")
    && !notesAgentSource.contains(".frame(maxWidth: .infinity, alignment: .leading)\n            .allowsHitTesting(false)")
    && notesAgentSource.contains("AttributedString(markdown: text)")
    && notesAgentSource.contains(".contentShape(Rectangle())")
    && notesAgentSource.contains("private var messageMetadata: some View")
    && notesAgentSource.contains("Text(\"WeiBei\")")
    && notesAgentSource.contains("rendersRichMarkdown: true")
    && notesAgentSource.contains("(isCredentialNotice || isOfflineContextPreview) ? WeiBeiTheme.link.opacity(0.42) : WeiBeiTheme.cinnabar.opacity(0.50)")
    && !notesAgentSource.contains("return isCredentialNotice ? store.ui(\"需要设置密钥\", \"Key Required\") : store.appDisplayName")
    && !notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(hovering ? 0.14 : 0.0)")
    && !notesAgentSource.contains(".frame(maxWidth: bubbleMaxWidth, alignment: .leading)")
    && !notesAgentSource.contains("private var bubbleFill")
    && !notesAgentSource.contains("RoundedRectangle(cornerRadius: 11)")
    && !notesAgentSource.contains(".fill(WeiBeiTheme.paperRaised.opacity(store.appearanceMode == .inkstone ? 0.28 : 0.76))")
    && notesAgentSource.contains("private var userBubbleFill: Color")
    && notesAgentSource.contains("private var userBubbleStroke: Color")
    && notesAgentSource.contains("RoundedRectangle(cornerRadius: 9, style: .continuous)")
    && notesAgentSource.contains("strokeBorder(userBubbleStroke, lineWidth: 1)"), "main agent conversation keeps assistant text open while user turns use a quiet paper bubble on the right edge")
if let userTurnStart = notesAgentSource.range(of: "private var userTurn: some View")?.lowerBound,
   let assistantTurnStart = notesAgentSource[userTurnStart...].range(of: "private var assistantTurn: some View")?.lowerBound {
    let userTurnSource = String(notesAgentSource[userTurnStart..<assistantTurnStart])
    expect(userTurnSource.contains(".frame(maxWidth: .infinity, alignment: .trailing)")
        && userTurnSource.contains("userBubbleFill")
        && userTurnSource.contains("AgentMessageMarkdownText(")
        && !userTurnSource.contains("store.ui(\"你\", \"You\")")
        && !userTurnSource.contains("Capsule()")
        && !userTurnSource.contains(".padding(.leading, 96)")
        && !userTurnSource.contains("Spacer(minLength: 42)"), "agent user messages hug a paper bubble on the right edge without speaker labels or accent rails")
} else {
    expect(false, "agent user message source is inspectable")
}
if let credentialStart = notesAgentSource.range(of: "private var credentialNoticeContent")?.lowerBound,
   let isUserStart = notesAgentSource[credentialStart...].range(of: "private var isUser")?.lowerBound {
    let credentialSource = String(notesAgentSource[credentialStart..<isUserStart])
    expect(credentialSource.contains("Text(displayText)")
        && credentialSource.contains(".allowsHitTesting(false)")
        && !credentialSource.contains(".textSelection(.enabled)"), "agent credential notice text lets wheel events pass to the conversation scroll")
} else {
    expect(false, "agent credential notice source is inspectable")
}
if let messageTextStart = notesAgentSource.range(of: "private struct AgentMessageMarkdownText")?.lowerBound,
   let thinkingStart = notesAgentSource[messageTextStart...].range(of: "private struct AgentThinkingIndicator")?.lowerBound {
    let messageTextSource = String(notesAgentSource[messageTextStart..<thinkingStart])
    expect(messageTextSource.contains("Text(renderedText)")
        && messageTextSource.contains(".allowsHitTesting(false)")
        && !messageTextSource.contains(".textSelection(.enabled)"), "plain agent message text does not trap scrolling over user turns")
} else {
    expect(false, "agent message text source is inspectable")
}
if let compactRowStart = notesAgentSource.range(of: "private struct CompactAgentMessagePreviewRow")?.lowerBound,
   let speakerTitleStart = notesAgentSource[compactRowStart...].range(of: "private var speakerTitle")?.lowerBound {
    let compactRowSource = String(notesAgentSource[compactRowStart..<speakerTitleStart])
    expect(compactRowSource.contains("Text(renderedText)")
        && compactRowSource.contains(".allowsHitTesting(false)")
        && !compactRowSource.contains(".textSelection(.enabled)"), "compact agent preview rows keep hover and scroll responsive over text")
} else {
    expect(false, "compact agent preview row source is inspectable")
}
expect(notesAgentSource.contains("store.canOpenSelectedSourceReference") && notesAgentSource.contains("Button(store.ui(\"来源\", \"Source\"))") && notesAgentSource.contains("openSourceReference()"), "selection agent exposes a lightweight source jump when the note selection is a reference")
expect(notesAgentSource.contains("onSourceReference: { reference in store.openSourceReference(reference) }"), "note editor source references can jump back to material")
expect(notesAgentSource.contains("emptyNoteHintText") && notesAgentSource.contains("store.hasSelectedMaterial ? store.ui(\"开始记录当前材料\"") && notesAgentSource.contains("store.ui(\"开始记录当前笔记\"") && notesAgentSource.contains(".allowsHitTesting(false)"), "blank note editor cue matches whether a material is selected")
expect(notesAgentSource.contains("noteFileStatusColor(for message: String)")
    && notesAgentSource.contains("message.hasPrefix(\"无法\") || message.hasPrefix(\"Could not\") ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk"), "note file success statuses do not render as errors")
expect(notesAgentSource.contains("store.ui(\"新建空白笔记或当前资料笔记\"")
    && notesAgentSource.contains("结合\\(store.agentPromptScope)和已选文本片段作答")
    && !notesAgentSource.contains("结合已选择材料、选区和笔记"), "note and floating agent hints avoid fake current material context")
expect(!notesAgentSource.contains("Label(store.ui(\"把当前 Markdown 作为笔记\"")
    && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"作为笔记编辑当前 Markdown\"")
    && !notesAgentSource.contains("Button(\"写回原 Markdown\")")
    && !commandPaletteSource.contains("写回当前 Markdown 文件"), "imported markdown conversion is named as editing, not an immediate overwrite")
expect(workspaceStoreSource.contains("var agentInputPrompt: String")
    && workspaceStoreSource.contains("if hasSelectionAttachments {\n            return ui(\"输入问题\"")
    && workspaceStoreSource.contains("return hasSelectedMaterial ? ui(\"问当前材料\"")
    && workspaceStoreSource.contains(": ui(\"问当前笔记\"")
    && !notesAgentSource.contains("问当前选区或当前材料")
    && !workspaceStoreSource.contains("追问已选文本片段"), "agent placeholders stay clean once selected fragments are represented by the attachment pill")
expect(notesAgentSource.contains("func weibeiFloatingHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View")
    && notesAgentSource.contains("WeiBeiHeaderHandoffFade(height: 10, opacity: 0.22)")
    && notesAgentSource.components(separatedBy: ".weibeiFloatingHeaderChrome(appearanceMode: store.appearanceMode)").count == 3, "drawer and corner agent headers share the same light glass chrome")
expect(notesAgentSource.contains("private struct AgentComposerField")
    && notesAgentSource.contains("var focused: FocusState<Bool>.Binding")
    && notesAgentSource.contains("!store.isAskingAgent && !store.agentDraft.trimmingCharacters")
    && notesAgentSource.components(separatedBy: "AgentComposerField(").count >= 5, "all agent send affordances use the shared composer field and hide while a request is running")
expect(notesAgentSource.contains("store.agentInputPrompt") && notesAgentSource.contains("prompt: Text(prompt)") && notesAgentSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)") && notesAgentSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "agent input placeholder matches context and uses native prompt alignment with readable ink")
if let panePromptStart = notesAgentSource.range(of: "private var agentPrompt: String")?.lowerBound,
   let panePromptEnd = notesAgentSource[panePromptStart...].range(of: "\n    }\n\n    private var agentInputTray")?.lowerBound {
    let panePromptSource = String(notesAgentSource[panePromptStart..<panePromptEnd])
    expect(panePromptSource.contains("store.agentInputPrompt")
        && !panePromptSource.contains("selectionContext != nil"), "main agent pane prompt uses the shared attachment-aware placeholder")
} else {
    expect(false, "main agent pane prompt is inspectable")
}
expect(notesAgentSource.contains("store.hasSelectedMaterial ? store.ui(\"来源\", \"Source\") : store.ui(\"笔记\", \"Note\")")
    && notesAgentSource.contains("store.selectedMaterialItem.map(store.displayTitle) ?? store.ui(\"当前笔记\", \"Current note\")"), "agent drawer source row avoids fake current material")
if let drawerStart = notesAgentSource.range(of: "struct AgentDrawerView")?.lowerBound,
   let cornerStart = notesAgentSource.range(of: "struct CornerAgentView")?.lowerBound {
    let drawerAgentSource = String(notesAgentSource[drawerStart..<cornerStart])
    expect(drawerAgentSource.contains("AgentComposerField(")
        && drawerAgentSource.contains("CompactAgentMessagePreviewList(maxMessages: 2, maxHeight: 168)")
        && drawerAgentSource.contains("private var drawerPrompt: String")
        && drawerAgentSource.contains("store.agentInputPrompt")
        && !drawerAgentSource.contains("return \"问当前选区\"")
        && drawerAgentSource.contains("prompt: drawerPrompt")
        && drawerAgentSource.contains("lineLimit: 1...4")
        && drawerAgentSource.contains("height: 46")
        && drawerAgentSource.contains("trailingPadding: 44")
        && drawerAgentSource.contains("sendButtonSize: 34")
        && drawerAgentSource.contains("sendBottom: 6"), "bottom agent drawer input grows as a compact composer instead of a search strip")
} else {
    expect(false, "agent drawer source is readable")
}
expect(notesAgentSource.contains(".frame(width: compactHovering ? 244 : 216, alignment: .leading)")
    && notesAgentSource.contains(".background(WeiBeiTheme.paperRaised.opacity(compactHovering ? 0.42 : 0.0))")
    && notesAgentSource.contains(".offset(x: compactHovering ? 2 : 0)")
    && !notesAgentSource.contains("Text(store.quietInsightTitle)\n                    .font(.caption2.weight(.medium))\n                    .foregroundStyle(WeiBeiTheme.secondaryInk)\n                Text(store.quietInsight.body)"), "compact reading insight behaves like a low-distraction margin note instead of a permanent card")
if let cornerStart = notesAgentSource.range(of: "struct CornerAgentView")?.lowerBound,
   let selectionStart = notesAgentSource.range(of: "struct FloatingSelectionAgentView")?.lowerBound {
    let cornerAgentSource = String(notesAgentSource[cornerStart..<selectionStart])
    expect(!cornerAgentSource.contains("cornerToolButton(")
        && !cornerAgentSource.contains("整理笔记")
        && cornerAgentSource.contains("Text(store.ui(\"对话\", \"Chat\"))")
        && !cornerAgentSource.contains("Text(\"Agent\")")
        && cornerAgentSource.contains("CompactAgentMessagePreviewList(maxMessages: 2, maxHeight: 138)")
        && cornerAgentSource.contains("private var agentPrompt: String")
        && cornerAgentSource.contains("store.agentInputPrompt")
        && !cornerAgentSource.contains("return \"问当前选区\"")
        && cornerAgentSource.contains("AgentComposerField(")
        && cornerAgentSource.contains("prompt: agentPrompt")
        && cornerAgentSource.contains("lineLimit: 1...4")
        && cornerAgentSource.contains("height: 44")
        && cornerAgentSource.contains("trailingPadding: 38")
        && cornerAgentSource.contains("sendBottom: 5")
        && cornerAgentSource.contains(".help(store.ui(\"收起对话浮窗\", \"Hide chat popover\"))"), "corner agent stays a lightweight localized prompt surface")
} else {
    expect(false, "corner agent source is readable")
}
expect(notesAgentSource.contains("private struct CompactAgentMessagePreviewList")
    && notesAgentSource.contains("Array(store.messages.suffix(maxMessages))")
    && notesAgentSource.contains("private struct CompactAgentMessagePreviewRow")
    && notesAgentSource.contains("private var renderedText: AttributedString")
    && notesAgentSource.contains("(try? AttributedString(markdown: displayText)) ?? AttributedString(displayText)")
    && notesAgentSource.contains("Text(renderedText)")
    && notesAgentSource.contains("## Offline Draft")
    && !notesAgentSource.contains("question was still sent into the chat"), "drawer and corner chat surfaces show recent local/offline replies with the current offline-preview detection")
if let selectionStart = notesAgentSource.range(of: "struct FloatingSelectionAgentView")?.lowerBound,
   let contextRailStart = notesAgentSource.range(of: "struct ContextRailItem")?.lowerBound {
    let floatingSelectionSource = String(notesAgentSource[selectionStart..<contextRailStart])
    expect(floatingSelectionSource.contains("private var promptSeparator: some View")
        && floatingSelectionSource.contains("WeiBeiTheme.hairline.opacity(0.78)")
        && !floatingSelectionSource.contains("Divider()"), "selection floating agent uses WeiBei hairline separators instead of system dividers")
    expect(floatingSelectionSource.contains("AgentComposerField(")
        && floatingSelectionSource.contains("prompt: store.ui(\"继续追问\", \"Ask a follow-up\")")
        && floatingSelectionSource.contains("lineLimit: 1...2")
        && floatingSelectionSource.contains("height: 34")
        && floatingSelectionSource.contains("sendButtonSize: 22"), "expanded selection agent keeps a small but usable follow-up composer")
    expect(floatingSelectionSource.contains("Button(store.ui(\"问\", \"Ask\"))")
        && floatingSelectionSource.contains(".help(store.ui(\"问当前选区\", \"Ask current selection\"))")
        && !floatingSelectionSource.contains("Button(\"问 Agent\")"), "compact selection prompt uses short task language instead of a visible internal agent label")
    if let explainStart = floatingSelectionSource.range(of: "private func explainSelection()")?.lowerBound,
       let openSourceStart = floatingSelectionSource.range(of: "private func openSourceReference()")?.lowerBound {
        let explainSelectionSource = String(floatingSelectionSource[explainStart..<openSourceStart])
        expect(explainSelectionSource.contains("store.askSelection()")
            && !explainSelectionSource.contains("askAgent()"), "selection prompt attaches the current selection and focuses the composer without auto-sending a generated question")
    } else {
        expect(false, "floating selection explain action is inspectable")
    }
    expect(floatingSelectionSource.contains("var routesToConversation = false")
        && floatingSelectionSource.contains("private var showsExpandedBody: Bool")
        && floatingSelectionSource.contains("expanded && !routesToConversation")
        && floatingSelectionSource.contains("if showsExpandedBody")
        && floatingSelectionSource.contains(".onChange(of: routesToConversation)")
        && floatingSelectionSource.contains("expanded = !routesToConversation"), "selection prompt stays prompt-only and routes into the open conversation surface when one is already visible")
    expect(floatingSelectionSource.contains("message.text.hasPrefix(\"请解释当前已选文本片段\")")
        && floatingSelectionSource.contains("message.text.hasPrefix(\"请解释下面选区\")"), "selection floating feed hides generated selection prompts from both current and legacy drafts")
    expect(!floatingSelectionSource.contains("accessibilityLabel(Text(\"关闭选区对话\"))")
        && !floatingSelectionSource.contains(".help(\"关闭选区对话\")")
        && !floatingSelectionSource.contains("iconButton(\"xmark\", help: \"关闭选区对话\")")
        && !floatingSelectionSource.contains("收起选区 Agent"), "selection floating agent has no redundant close button; clearing selection or Escape dismisses it")
} else {
    expect(false, "selection floating agent source is readable")
}
expect(notesAgentSource.contains("private var agentInputTray: some View"), "agent pane uses a dedicated input tray")
expect(notesAgentSource.contains("private var agentContentMaxWidth: CGFloat?")
    && notesAgentSource.contains("private var agentContentMaxWidth: CGFloat? {\n        760\n    }")
    && notesAgentSource.contains("let isUser = message.role == .user")
    && notesAgentSource.contains("let readingWidth = max(contentWidth - 28, 240)")
    && notesAgentSource.contains("let readingLeadingInset = max((geometryWidth - contentWidth) / 2, 0)")
    && notesAgentSource.contains(".frame(maxWidth: readingWidth, alignment: isUser ? .trailing : .leading)")
    && notesAgentSource.contains(".padding(.leading, readingLeadingInset)")
    && notesAgentSource.contains(".frame(maxWidth: .infinity, alignment: .leading)")
    && !notesAgentSource.contains("maxWidth: isUser ? .infinity : readingWidth")
    && notesAgentSource.contains("private var userBubbleFill: Color")
    && notesAgentSource.contains("private var userBubbleStroke: Color")
    && notesAgentSource.contains(".frame(maxWidth: 520, alignment: .trailing)")
    && notesAgentSource.contains(".frame(width: availableWidth, alignment: .topLeading)")
    && notesAgentSource.contains(".frame(minHeight: geometry.size.height, alignment: .topLeading)"), "agent user and assistant turns share one centered reading column; user bubbles trail inside the column")
expect(notesAgentSource.contains("private let agentBottomAnchorID = \"agentConversationBottom\"")
    && notesAgentSource.contains(".id(agentBottomAnchorID)")
    && notesAgentSource.contains("proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)")
    && !notesAgentSource.contains("AgentScrollBottomPreferenceKey")
    && !notesAgentSource.contains("onPreferenceChange(AgentScrollBottomPreferenceKey"), "agent conversation uses a stable bottom anchor without a geometry preference loop")
expect(notesAgentSource.contains("private var agentInputMaxWidth: CGFloat?")
    && notesAgentSource.contains("private var agentInputMaxWidth: CGFloat? {\n        680\n    }")
    && notesAgentSource.contains(".frame(maxWidth: agentInputMaxWidth)"), "agent composer shares the narrowed reading axis across layouts")
expect(notesAgentSource.contains(".contentShape(Rectangle())")
    && notesAgentSource.contains("focused.wrappedValue = true")
    && notesAgentSource.components(separatedBy: "AgentComposerField(").count >= 5
    && notesAgentSource.components(separatedBy: "draftFocused = true").count >= 2, "agent composer surfaces focus when tapping the visible input tray, not only the exact text glyph")
expect(notesAgentSource.contains("ScrollView(showsIndicators: true)")
    && notesAgentSource.components(separatedBy: "ScrollView(showsIndicators: false)").count >= 3
    && notesAgentSource.contains("onMarkdownHeightChange: message.id == store.messages.last?.id")
    && notesAgentSource.contains("onContentHeightChange: onMarkdownHeightChange"), "agent conversation keeps a light scroll affordance and follows the last Markdown answer after it finishes measuring")
expect(notesAgentSource.contains("WeiBeiGlassHeaderBackground(") && notesAgentSource.contains("WeiBeiTheme.glassTint.opacity(0.34)"), "agent input tray uses paper glass fade instead of a hard white strip")
expect(notesAgentSource.contains("WeiBeiTheme.ink.opacity(0.42), WeiBeiTheme.ink.opacity(0.78)")
    && !notesAgentSource.contains(".black.opacity(0.72), .black"), "agent input tray fade mask uses semantic ink instead of a fixed black ramp")
expect(notesAgentSource.contains("lineLimit: 1...6")
    && notesAgentSource.contains(".fixedSize(horizontal: false, vertical: true)")
    && notesAgentSource.contains(".padding(.trailing, canSend ? trailingPadding : 0)")
    && notesAgentSource.contains(".frame(minHeight: 56, alignment: .bottom)")
    && notesAgentSource.contains(".weibeiInputSurface(active: focused.wrappedValue, height: height, horizontalPadding: horizontalPadding)")
    && notesAgentSource.contains("height: 56")
    && notesAgentSource.contains("horizontalPadding: 14")
    && notesAgentSource.contains("prompt: agentPrompt")
    && notesAgentSource.contains("WeiBeiIconButtonStyle(size: sendButtonSize, prominence: .primary)")
    && notesAgentSource.contains("sendButtonSize: 30")
    && notesAgentSource.contains("sendTrailing: 10")
    && notesAgentSource.contains("sendBottom: 10"), "main agent input grows upward like a real chat composer and keeps send visually inside the field edge")
expect(notesAgentSource.contains("Image(systemName: \"paperplane.fill\")")
    && !notesAgentSource.contains("Image(systemName: \"arrow.up\")")
    && !notesAgentSource.contains("AgentComposerSendButtonStyle"), "main agent send affordance stays the cinnabar paper-plane control while sitting inside the composer edge")
expect(!notesAgentSource.contains("RoundedRectangle(cornerRadius: 9)")
    && !notesAgentSource.contains(".stroke(draftFocused ? WeiBeiTheme.link.opacity(0.16) : WeiBeiTheme.hairline.opacity(0.34), lineWidth: 1)")
    && !notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(0.46)"), "agent input tray avoids a heavy nested form border")
expect(!notesAgentSource.contains(".disabled(store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)") && !notesAgentSource.contains(".disabled(!canSend)") && !notesAgentSource.contains(".disabled(store.isAskingAgent)"), "agent inputs hide unavailable send actions instead of showing disabled buttons")
expect(!notesAgentSource.contains("agentToolButton(") && !notesAgentSource.contains("help: store.ui(\"整理笔记\""), "main agent header does not become a toolbar")
expect(notesAgentSource.contains("LazyVGrid(columns: starterChipColumns")
    && notesAgentSource.contains("GridItem(.adaptive(minimum: 56)")
    && !notesAgentSource.contains("HStack(spacing: 8) {\n                if store.hasSelectedMaterial {\n                    starterChip(\"梳理材料\""), "agent empty-state starter actions adapt in narrow panes instead of squeezing into one row")
expect(notesAgentSource.contains("private func iconButton(_ systemName: String, help: String") && notesAgentSource.contains(".accessibilityLabel(Text(help))"), "floating icon buttons carry semantic labels")
expect(notesAgentSource.contains("private func togglePinnedFloatingAgent()")
    && notesAgentSource.contains("if store.pinnedFloatingAgent {\n            dragOffset = .zero\n            settledOffset = .zero\n        }")
    && !notesAgentSource.contains("iconButton(\"xmark\", help: \"关闭选区对话\")"), "unpinning the selection agent returns it to the current selection anchor without showing a redundant close button")
expect(notesAgentSource.contains(".help(store.ui(\"收起对话浮窗\", \"Hide chat popover\"))") && !notesAgentSource.contains(".help(\"收起右下角 Agent\")"), "corner agent close button explains its action without engineering labels")
expect(commandPaletteSource.contains("插入行内公式") && commandPaletteSource.contains("${{WEIBEI_SELECT_START}}x_i = \\\\frac{a}{b}{{WEIBEI_SELECT_END}}$") && commandPaletteSource.contains("插入矩阵公式"), "markdown command templates keep an editable landing point")
expect(commandPaletteSource.contains("插入 Callout") && commandPaletteSource.contains("> [!note] 标题\\n>\\n> {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}}"), "callout insertion separates title from body")
expect(commandPaletteSource.contains("private func markdownInsertCommand") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "markdown insert commands use layout motion when revealing writing")
let editorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/WebEditor/src/editor.js")
let editorSource = (try? String(contentsOf: editorSourceURL, encoding: .utf8)) ?? ""
expect(editorSource.contains("decorateSourceReferences") && editorSource.contains("sourceReferenceActivated") && editorSource.contains("activateSourceReference"), "web editor exposes source references as clickable bridge actions")
let richMarkdownEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/RichMarkdownEditorView.swift")
let richMarkdownEditorSource = (try? String(contentsOf: richMarkdownEditorSourceURL, encoding: .utf8)) ?? ""
expect(richMarkdownEditorSource.contains("\"sourceReferenceActivated\"") && richMarkdownEditorSource.contains("onSourceReference(reference)"), "rich editor bridges source-reference clicks into Swift")
expect(LibraryNavigator.adjacentID(in: [], selectedID: nil, step: 1) == nil, "library navigation empty")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: nil, step: 1) == "a", "library navigation defaults first")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "b", step: 1) == "c", "library navigation next")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "a", step: -1) == "c", "library navigation wraps previous")

expect(SelectionContext(text: "文档", source: .document, ownerTitle: "资料").isNoteSelection == false, "document selection is read-only")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isNoteSelection == true, "note selection is replaceable")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isReplaceableNoteSelection, "editable note selection can be replaced")
expect(!SelectionContext(text: "预览", source: .note, ownerTitle: "资料", isEditable: false).isReplaceableNoteSelection, "preview note selection is not replaceable")
expect(SelectionAttachmentMerge.mergedText(existing: "当前笔记已经覆盖材", incoming: "开头。建议检查是否写了来源、例子和待追问。", withinSelectionGesture: true) == "当前笔记已经覆盖材开头。建议检查是否写了来源、例子和待追问。", "same-gesture selection attachment stitches split live selection fragments into one attachment")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用", incoming: "使用价格的表达", withinSelectionGesture: true) == "利率是资金使用价格的表达", "same-gesture overlapping fragments merge without duplicate overlap text")
expect(SelectionAttachmentMerge.mergedText(existing: "你们", incoming: "好", withinSelectionGesture: true) == "你们好", "same-gesture single-character live-selection fragments merge into one human selection")
expect(SelectionAttachmentMerge.mergedText(existing: "开头。建议检查是否写了来源。", incoming: "你们好", withinSelectionGesture: true) == "开头。建议检查是否写了来源。你们好", "same-gesture short trailing live-selection fragments still merge after sentence punctuation")
expect(SelectionAttachmentMerge.mergedText(existing: "利率", incoming: "利率是资金使用价格", withinSelectionGesture: false) == "利率是资金使用价格", "selection attachment merge still replaces a shorter contained selection with the fuller text")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格。", incoming: "通货膨胀预期会改变真实利率。", withinSelectionGesture: true) == nil, "same-gesture selection attachment does not blindly stitch separate complete sentences")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格", incoming: "通货膨胀预期", withinSelectionGesture: false) == nil, "separate selections outside one gesture remain separate fragments")
expect(SelectionAttachmentMerge.containsSelection("当前笔记已经覆盖材料开头。建议检查是否写了来源。", fragment: "材料 开头。")
    && !SelectionAttachmentMerge.containsSelection("利率是资金使用价格", fragment: ""), "selection attachment containment ignores whitespace and rejects empty fragments")
expect(workspaceStoreSource.contains("SelectionAttachmentMerge.containsSelection($0.text, fragment: cleanedText)")
    && workspaceStoreSource.contains("selectionAttachments.removeAll")
    && workspaceStoreSource.contains("SelectionAttachmentMerge.containsSelection(cleanedText, fragment: $0.text)"), "selection attachment intake collapses stale short fragments once the fuller live selection arrives")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: true) == 20, "flipped content view keeps selection y")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: false) == 80, "non-flipped content view converts selection y")
expect(!SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false), "selection agent waits for anchor before floating")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: true, pinned: false), "selection agent appears when anchored")
expect(SelectionFloatingAgentPlacement.expandedHalfWidth == 156 && SelectionFloatingAgentPlacement.compactHalfWidth == 82, "selection agent placement constants match the compact and expanded surfaces")
expect(contentViewSource.contains("SelectionFloatingAgentPlacement.expandedHalfWidth")
    && contentViewSource.contains("SelectionFloatingAgentPlacement.compactHalfWidth")
    && !contentViewSource.contains("surfaceHalfWidth: floatingAgentExpanded ? 170 : 82"), "selection agent placement uses shared width constants instead of duplicate magic numbers")
expect(notesAgentSource.contains(".frame(width: CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2), alignment: .leading)")
    && !notesAgentSource.contains(".frame(width: 312, alignment: .leading)"), "expanded selection agent visual width matches placement half-width")
let floatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
let topInsetFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    topInset: 42
)
expect(floatingPoint.x == 486 && floatingPoint.y == 208, "selection agent opens close beside the text anchor")
expect(topInsetFloatingPoint.x == 486 && topInsetFloatingPoint.y == 166, "selection agent compensates top bar coordinate space")
let compactEdgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 12, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
let compactCenterFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
expect(compactCenterFloatingPoint.x == 320 && compactCenterFloatingPoint.y == 208, "selection prompt centers on the text anchor when compact")
expect(compactEdgeFloatingPoint.x == 100 && compactEdgeFloatingPoint.y == 208, "selection prompt clamps only at the edge when compact")
let edgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 1160, y: 760),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
expect(edgeFloatingPoint.x == 994 && edgeFloatingPoint.y == 708, "selection agent flips to the left of text near the window edge")
expect(AgentMessage(role: .assistant, text: "整理完成", source: nil).isUsableAgentAnswer, "usable agent answer")
expect(!AgentMessage(role: .assistant, text: "未配置密钥。", source: nil).isUsableAgentAnswer, "credential setup message is not writable")
expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY。", source: nil).isUsableAgentAnswer, "api key setup message is not writable")
expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY 或钥匙串密钥。", source: nil).isUsableAgentAnswer, "keychain setup message is not writable")
expect(AgentMessage(role: .assistant, text: offlineChinesePreview, source: nil).isUsableAgentAnswer, "offline draft is visible in chat and writable to notes")
expect(AgentMessage(role: .assistant, text: offlineEnglishPreview, source: nil).isUsableAgentAnswer, "English offline draft is visible in chat and writable to notes")
expect(!AgentMessage(role: .assistant, text: "请求失败：网络错误", source: nil).isUsableAgentAnswer, "agent error is not writable")
expect(!AgentMessage(role: .assistant, text: "Agent 请求失败：网络错误", source: nil).isUsableAgentAnswer, "legacy agent error is not writable")

let importedMarkdown = StudyItem(id: "file:/tmp/note.md", title: "note", subtitle: "note.md", kind: .markdown, urlPath: "/tmp/note.md", isSample: false)
let notebookMarkdown = StudyItem(id: "file:/tmp/notebook.md", title: "notebook", subtitle: "notebook.md", kind: .markdown, urlPath: "/tmp/notebook.md", isSample: false, isNotebookNote: true)
let sampleMarkdown = StudyItem(id: "sample", title: "sample", subtitle: "sample", kind: .markdown, urlPath: nil, isSample: true)
expect(importedMarkdown.isImportedMarkdownFile, "imported markdown is readable as material")
expect(!importedMarkdown.editsBackingMarkdownFile, "imported markdown material does not edit backing file")
expect(importedMarkdown.canBecomeNotebookNote, "imported markdown can become an editable notebook note")
expect(notebookMarkdown.editsBackingMarkdownFile, "notebook markdown edits its backing file")
expect(!notebookMarkdown.canBecomeNotebookNote, "notebook markdown does not offer duplicate conversion")
expect(!sampleMarkdown.isImportedMarkdownFile, "sample markdown stays app-owned")
expect(!sampleMarkdown.canBecomeNotebookNote, "sample markdown cannot become a backing-file note")

let persisted = PersistedWorkspace(threePaneOrder: [.agent, .reader, .notes], noteRenderMode: .preview, showLibrary: false, showReader: false, showAgent: true, showNotes: false, showRightPane: true, adaptImportedDocumentColors: false)
let restored = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(persisted))
expect(restored.showLibrary == false && restored.showReader == false && restored.showAgent == true && restored.showNotes == false && restored.showRightPane == true, "pane visibility state persists")
expect(restored.adaptImportedDocumentColors == false
    && workspaceStoreSource.contains("adaptImportedDocumentColors = snapshot.adaptImportedDocumentColors ?? true")
    && workspaceStoreSource.contains("adaptImportedDocumentColors: adaptImportedDocumentColors"), "imported-document color adaptation persists while old workspaces default to adapted reading")
expect(restored.noteRenderMode == .preview, "legacy preview note mode remains decodable for old workspace snapshots")
expect(restored.threePaneOrder == [.agent, .reader, .notes], "custom three-pane order persists")
expect(workspaceStoreSource.contains("if let noteRenderMode = snapshot.noteRenderMode {\n            self.noteRenderMode = noteRenderMode.visibleMode\n        }")
    && workspaceStoreSource.contains("noteRenderMode = snapshot.noteRenderMode.visibleMode")
    && workspaceStoreSource.contains("let nextMode = mode.visibleMode")
    && !workspaceStoreSource.contains("noteRenderMode == .source ? .source : .rich"), "workspace load and navigation normalize legacy preview mode back to writing")

let attachmentRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("weibei-self-check-\(UUID().uuidString)", isDirectory: true)
let attachmentDirectory = attachmentRoot.appendingPathComponent(".weibei-assets", isDirectory: true)
let dataURL = "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())"
let firstAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(firstAttachment.src == ".weibei-assets/图 1).png", "attachment uses relative markdown path")
expect(firstAttachment.alt == "图 1)", "attachment alt uses safe stem")
expect(MarkdownAttachmentStore.markdownImage(for: firstAttachment) == "![图 1)](.weibei-assets/图%201%29.png)", "markdown image escapes path")

let secondAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(secondAttachment.src == ".weibei-assets/图 1)-2.png", "attachment avoids overwriting duplicate names")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(firstAttachment.src).path), "first attachment written")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(secondAttachment.src).path), "second attachment written")
let rawAttachment = try MarkdownAttachmentStore.save(
    data: Data([1, 2, 3]),
    originalName: "dragged.webp",
    mime: "",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(rawAttachment.src == ".weibei-assets/dragged.webp", "raw image data save keeps image extension")
expect(MarkdownAttachmentStore.isSupportedImageExtension("HEIC"), "image extension check is case insensitive")
expect(MarkdownAttachmentStore.mimeType(forFileExtension: "jpeg") == "image/jpeg", "mime from extension")
let blockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "来源：课程 HTML",
    replacing: NSRange(location: ("来源：课程 HTML" as NSString).length, length: 0)
)
expect(blockInsert.text == "来源：课程 HTML\n\n![pasted](Attachments/pasted.png)", "block markdown insertion separates from inline text")
let middleBlockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "前文后文",
    replacing: NSRange(location: ("前文" as NSString).length, length: 0)
)
expect(middleBlockInsert.text == "前文\n\n![pasted](Attachments/pasted.png)\n\n后文", "block markdown insertion separates both sides")
try? FileManager.default.removeItem(at: attachmentRoot)

print("WeiBei self-check passed")
