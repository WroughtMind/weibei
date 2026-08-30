import AppKit
import Markdown
import SwiftUI
import SwiftStreamingMarkdown
import WebKit

/// The only renderer for ordinary assistant Markdown. Mermaid fences are split
/// into explicit interactive blocks after a response finishes; GenUI remains in
/// its existing dedicated runtime.
struct AgentNativeMarkdownView: View {
    let markdown: String
    let isStreaming: Bool
    let compact: Bool
    let isChatWideTypography: Bool
    let baseURL: URL?
    let appearanceMode: WeiBeiAppearanceMode

    var body: some View {
        LazyVStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(AgentMarkdownRenderBlock.split(markdown, isStreaming: isStreaming)) { block in
                switch block.kind {
                case .markdown(let text):
                    AgentStreamingMarkdownBlock(
                        markdown: text,
                        isStreaming: isStreaming,
                        compact: compact,
                        isChatWideTypography: isChatWideTypography,
                        baseURL: baseURL
                    )
                case .mermaid(let source):
                    AgentMermaidBlock(source: source, appearanceMode: appearanceMode)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct AgentStreamingMarkdownBlock: View {
    let markdown: String
    let isStreaming: Bool
    let compact: Bool
    let isChatWideTypography: Bool
    let baseURL: URL?
    @StateObject private var source: AgentCumulativeMarkdownSource
    @State private var keepsStreamingSurface: Bool

    init(
        markdown: String,
        isStreaming: Bool,
        compact: Bool,
        isChatWideTypography: Bool,
        baseURL: URL?
    ) {
        self.markdown = markdown
        self.isStreaming = isStreaming
        self.compact = compact
        self.isChatWideTypography = isChatWideTypography
        self.baseURL = baseURL
        _source = StateObject(wrappedValue: AgentCumulativeMarkdownSource(initialText: markdown))
        _keepsStreamingSurface = State(initialValue: isStreaming)
    }

    var body: some View {
        Group {
            if keepsStreamingSurface {
                StreamedMarkdownView(source: source, config: renderConfig)
            } else {
                MarkdownView(text: markdown, config: renderConfig)
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: markdown) {
                source.submit(markdown)
            }
            .onChange(of: isStreaming) { _, value in
                if value {
                    keepsStreamingSurface = true
                    source.submit(markdown)
                } else if keepsStreamingSurface {
                    source.submitAndFinish(markdown)
                }
            }
    }

    private var renderConfig: MarkdownRenderConfig {
        let bodySize: CGFloat = compact ? 13.2 : (isChatWideTypography ? 16 : 15)
        let bodyFonts = textFonts(size: bodySize, lineHeight: bodySize + (compact ? 4.2 : 5.5))
        let codeFonts = monospaceFonts(size: bodySize - 1)
        let headingColor = WeiBeiTheme.ink
        let imageTypes: [ImageConfig.ImageType] = baseURL.map {
            [.localFile(baseDirectory: $0.standardizedFileURL)]
        } ?? []

        return MarkdownRenderConfig(
            shouldAnimateText: false,
            blockQuoteStyle: .init(textFonts: bodyFonts, textColor: WeiBeiTheme.secondaryInk),
            headingStyle: .init(
                h1Font: textFonts(size: bodySize + 7, weight: .semibold),
                h2Font: textFonts(size: bodySize + 5, weight: .semibold),
                h3Font: textFonts(size: bodySize + 3, weight: .semibold),
                h4Font: textFonts(size: bodySize + 1.5, weight: .semibold),
                h5Font: textFonts(size: bodySize, weight: .semibold),
                h6Font: textFonts(size: bodySize, weight: .medium),
                textColor: headingColor
            ),
            orderedListStyle: .init(textFonts: bodyFonts, textColor: WeiBeiTheme.ink),
            paragraphStyle: .init(textFonts: bodyFonts, textColor: WeiBeiTheme.ink),
            tableStyle: .init(
                textFonts: textFonts(size: bodySize - 1),
                headerTextColor: WeiBeiTheme.ink,
                regularTextColor: WeiBeiTheme.ink,
                headerBackgroundColor: WeiBeiTheme.paperInset,
                borderColor: WeiBeiTheme.hairline,
                actionButtonColor: WeiBeiTheme.link
            ),
            inlineStyle: .init(
                boldTextColor: WeiBeiTheme.ink,
                linkTextFont: bodyFonts.normal,
                linkTextColor: WeiBeiTheme.link,
                linkUnderlineStyle: .single,
                codeTextFont: codeFonts.normal,
                codeTextColor: WeiBeiTheme.ink,
                codeBackgroundColor: WeiBeiTheme.codePaper,
                codeUnderlineColor: .clear
            ),
            citationConfig: .init(
                isEnabled: false,
                font: bodyFonts.normal,
                textColor: WeiBeiTheme.cinnabar,
                backgroundColor: WeiBeiTheme.paperInset
            ),
            codeBlockConfig: .init(
                theme: .xcode,
                backgroundColor: WeiBeiTheme.codePaper,
                foregroundColor: WeiBeiTheme.secondaryInk,
                codeTextFonts: codeFonts,
                chromeTextFonts: textFonts(size: 11)
            ),
            blockSpacing: compact ? 8 : 12,
            thematicBreakColor: WeiBeiTheme.hairline,
            imageConfig: .init(
                enabled: !imageTypes.isEmpty,
                allowedImageTypes: imageTypes,
                fullscreenViewerEnabled: true
            )
        )
    }

    private func textFonts(
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        lineHeight: CGFloat? = nil
    ) -> TextFonts {
        let regular = NSFont.systemFont(ofSize: size, weight: weight)
        let bold = NSFont.systemFont(ofSize: size, weight: weight == .regular ? .semibold : weight)
        return TextFonts(
            normal: regular,
            italic: NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask),
            bold: bold,
            boldItalic: NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask),
            preferredLetterSpacing: nil,
            preferredLineHeight: lineHeight
        )
    }

    private func monospaceFonts(size: CGFloat) -> TextFonts {
        let regular = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        return TextFonts(
            normal: regular,
            italic: regular,
            bold: bold,
            boldItalic: bold,
            preferredLetterSpacing: nil,
            preferredLineHeight: size + 5
        )
    }
}

@MainActor
private final class AgentCumulativeMarkdownSource: ObservableObject, StreamedMarkdownSource {
    let text: AsyncStream<String>
    private var continuation: AsyncStream<String>.Continuation?
    private var lastText: String
    private var isFinished = false

    init(initialText: String) {
        lastText = initialText
        var captured: AsyncStream<String>.Continuation?
        text = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            captured = continuation
        }
        continuation = captured
        continuation?.yield(initialText)
    }

    func submit(_ value: String) {
        guard !isFinished, value != lastText else { return }
        lastText = value
        continuation?.yield(value)
    }

    func submitAndFinish(_ value: String) {
        guard !isFinished else { return }
        submit(value)
        isFinished = true
        continuation?.finish()
        continuation = nil
    }

    deinit {
        continuation?.finish()
    }
}

struct AgentMarkdownRenderBlock: Identifiable {
    enum Kind {
        case markdown(String)
        case mermaid(String)
    }

    let id: String
    let kind: Kind

    static func split(_ markdown: String, isStreaming: Bool) -> [Self] {
        guard !isStreaming else {
            return [.init(id: "markdown-0", kind: .markdown(markdown))]
        }
        var collector = MermaidCodeBlockCollector(markdown: markdown)
        collector.visit(Document(parsing: markdown))
        let mermaidBlocks = collector.blocks.sorted { $0.range.lowerBound < $1.range.lowerBound }
        guard !mermaidBlocks.isEmpty else {
            return [.init(id: "markdown-0", kind: .markdown(markdown))]
        }

        var blocks: [Self] = []
        var cursor = markdown.startIndex
        for item in mermaidBlocks {
            if cursor < item.range.lowerBound {
                blocks.append(.init(
                    id: "markdown-\(blocks.count)",
                    kind: .markdown(String(markdown[cursor..<item.range.lowerBound]))
                ))
            }
            blocks.append(.init(id: "mermaid-\(blocks.count)", kind: .mermaid(item.code)))
            cursor = item.range.upperBound
        }
        if cursor < markdown.endIndex {
            blocks.append(.init(
                id: "markdown-\(blocks.count)",
                kind: .markdown(String(markdown[cursor...]))
            ))
        }
        return blocks.isEmpty ? [.init(id: "markdown-0", kind: .markdown(markdown))] : blocks
    }

    private struct MermaidCodeBlockCollector: MarkupWalker {
        let markdown: String
        var blocks: [(range: Range<String.Index>, code: String)] = []

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            guard codeBlock.language?
                .split(whereSeparator: { $0.isWhitespace })
                .first?
                .lowercased() == "mermaid",
                let sourceRange = codeBlock.range,
                let range = Self.stringRange(for: sourceRange, in: markdown),
                Self.hasExplicitClosingFence(in: markdown[range]) else { return }
            blocks.append((range, codeBlock.code))
        }

        private static func stringRange(
            for range: SourceRange,
            in markdown: String
        ) -> Range<String.Index>? {
            let lineStarts = sourceLineStarts(in: markdown)
            guard let lower = stringIndex(for: range.lowerBound, in: markdown, lineStarts: lineStarts),
                  let upper = stringIndex(for: range.upperBound, in: markdown, lineStarts: lineStarts) else {
                return nil
            }
            return lower..<upper
        }

        private static func sourceLineStarts(in markdown: String) -> [String.Index] {
            var starts = [markdown.startIndex]
            for index in markdown.indices where markdown[index] == "\n" {
                starts.append(markdown.index(after: index))
            }
            return starts
        }

        private static func stringIndex(
            for location: SourceLocation,
            in markdown: String,
            lineStarts: [String.Index]
        ) -> String.Index? {
            guard location.line > 0,
                  location.line <= lineStarts.count,
                  location.column > 0,
                  let utf8Start = lineStarts[location.line - 1].samePosition(in: markdown.utf8),
                  let utf8Index = markdown.utf8.index(
                    utf8Start,
                    offsetBy: location.column - 1,
                    limitedBy: markdown.utf8.endIndex
                  ) else { return nil }
            return String.Index(utf8Index, within: markdown)
        }

        private static func hasExplicitClosingFence(in source: Substring) -> Bool {
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            guard let opening = lines.first.map({ $0.drop(while: { $0.isWhitespace }) }),
                  let marker = opening.first,
                  marker == "`" || marker == "~" else { return false }
            let openingCount = opening.prefix(while: { $0 == marker }).count
            guard openingCount >= 3,
                  let closing = lines.dropFirst().reversed().first(where: {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  })?.drop(while: { $0.isWhitespace }) else { return false }
            let closingFence = closing.prefix(while: { $0 == marker })
            return closingFence.count >= openingCount
                && closing.dropFirst(closingFence.count).allSatisfy({ $0.isWhitespace })
        }
    }
}

private struct AgentMermaidBlock: NSViewRepresentable {
    let source: String
    let appearanceMode: WeiBeiAppearanceMode
    @State private var height: CGFloat = 1

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.heightMessage)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        context.coordinator.load(source: source, appearanceMode: appearanceMode, in: view)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.source != source
                || context.coordinator.appearanceMode != appearanceMode else { return }
        context.coordinator.load(source: source, appearanceMode: appearanceMode, in: nsView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WKWebView,
        context: Context
    ) -> CGSize? {
        CGSize(width: max(proposal.width ?? 1, 1), height: height)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.heightMessage
        )
        nsView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let heightMessage = "weibeiMermaidHeight"
        @Binding var height: CGFloat
        var source = ""
        var appearanceMode: WeiBeiAppearanceMode?
        private var allowsInitialLocalNavigation = false

        init(height: Binding<CGFloat>) {
            _height = height
        }

        func load(
            source: String,
            appearanceMode: WeiBeiAppearanceMode,
            in webView: WKWebView
        ) {
            self.source = source
            self.appearanceMode = appearanceMode
            allowsInitialLocalNavigation = true
            guard let sourceJSON = Self.jsonString(source),
                  let runtimeURL = WeiBeiResources.bundle.url(
                    forResource: "mermaid-runtime",
                    withExtension: "js",
                    subdirectory: "Editor"
                  ),
                  let runtime = try? String(contentsOf: runtimeURL, encoding: .utf8) else {
                webView.loadHTMLString("<p>Mermaid 资源缺失。</p>", baseURL: nil)
                return
            }
            let themeVariables = Self.themeVariables(for: appearanceMode)
            let html = """
            <!doctype html><html><head><meta charset="utf-8"><style>
            html,body{margin:0;padding:0;background:transparent;overflow:hidden;color-scheme:light dark}
            #diagram{display:flex;justify-content:center;min-width:0;padding:8px 0}
            #diagram svg{max-width:100%;height:auto}
            </style><script>\(runtime)</script></head><body><div id="diagram"></div><script>
            (async()=>{try{
              const engine=window.WeiBeiMermaid;
              if(!engine) throw new Error('Mermaid 资源未加载。');
              engine.initialize({startOnLoad:false,securityLevel:'strict',theme:'base',themeVariables:\(themeVariables)});
              const rendered=await engine.render('weibei-mermaid',\(sourceJSON));
              document.getElementById('diagram').innerHTML=rendered.svg;
              rendered.bindFunctions?.(document.getElementById('diagram'));
            }catch(error){document.getElementById('diagram').textContent=String(error)}finally{
              const report=()=>window.webkit.messageHandlers.\(Self.heightMessage).postMessage(
                Math.ceil(document.documentElement.scrollHeight)
              );
              new ResizeObserver(report).observe(document.documentElement);
              window.addEventListener('resize',report);
              requestAnimationFrame(report);
            }})();
            </script></body></html>
            """
            webView.loadHTMLString(html, baseURL: runtimeURL.deletingLastPathComponent())
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.heightMessage,
                  let value = message.body as? NSNumber else { return }
            let measured = CGFloat(truncating: value)
            guard measured.isFinite, measured > 0 else { return }
            height = measured
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
            let isLocal = url.isFileURL || url.scheme?.lowercased() == "about"
            if allowsInitialLocalNavigation, isMainFrame, isLocal {
                allowsInitialLocalNavigation = false
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }

        private static func jsonString(_ value: String) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func themeVariables(for mode: WeiBeiAppearanceMode) -> String {
            let values: [String: String]
            switch mode {
            case .inkstone:
                values = [
                    "background": "#151515", "primaryColor": "#1c1c1c",
                    "primaryTextColor": "#d7cbb0", "primaryBorderColor": "#3a3328",
                    "lineColor": "#8b5e3c", "secondaryColor": "#222222",
                    "tertiaryColor": "#171717",
                    "fontFamily": "-apple-system, BlinkMacSystemFont, Songti SC, serif",
                ]
            case .stele, .glassDark, .glassSlate:
                values = [
                    "background": "#1e2228", "primaryColor": "#252a32",
                    "primaryTextColor": "#d2d6dc", "primaryBorderColor": "#3a414c",
                    "lineColor": "#8a7a5c", "secondaryColor": "#2a3038",
                    "tertiaryColor": "#1a1e24",
                    "fontFamily": "-apple-system, BlinkMacSystemFont, Songti SC, serif",
                ]
            case .xuan, .glassLight, .glassMist:
                values = [
                    "background": "#f7f4ef", "primaryColor": "#fcfbf8",
                    "primaryTextColor": "#25231f", "primaryBorderColor": "#d8d2c6",
                    "lineColor": "#6e634f", "secondaryColor": "#ebe6dc",
                    "tertiaryColor": "#f7f4ef",
                    "fontFamily": "-apple-system, BlinkMacSystemFont, Songti SC, serif",
                ]
            case .paper:
                values = [
                    "background": "#fbf5e8", "primaryColor": "#f6eddc",
                    "primaryTextColor": "#2e261f", "primaryBorderColor": "#cbb79b",
                    "lineColor": "#7a6250", "secondaryColor": "#efe4d2",
                    "tertiaryColor": "#f8f0e1",
                    "fontFamily": "-apple-system, BlinkMacSystemFont, Songti SC, serif",
                ]
            }
            let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
    }
}
