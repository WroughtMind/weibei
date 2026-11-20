import CoreGraphics
import Foundation
import WeiBeiCore
import WebKit

struct NotePDFSource {
    let title: String
    let markdown: String
    let baseURL: URL?
    let attachments: URL?
}

struct NotePDFOptions: Equatable {
    enum Font: String, CaseIterable {
        case note, sans, serif

        var css: String {
            switch self {
            case .note: "\"Mplus1p\", sans-serif"
            case .sans: "-apple-system, 'PingFang SC', sans-serif"
            case .serif: "'Songti SC', 'STSong', serif"
            }
        }
    }

    enum Paper: String, CaseIterable {
        case a4 = "A4"
        case a5 = "A5"
        case letter = "Letter"

        var size: CGSize {
            switch self {
            case .a4: CGSize(width: 210 * 72 / 25.4, height: 297 * 72 / 25.4)
            case .a5: CGSize(width: 148 * 72 / 25.4, height: 210 * 72 / 25.4)
            case .letter: CGSize(width: 612, height: 792)
            }
        }
    }

    enum Folio: String, CaseIterable { case right, center, hidden }

    var theme: WeiBeiAppearanceMode
    var font: Font = .note
    var size: Double
    var lineSpacing = 1.75
    var paragraphSpacing = 1.25
    var paper: Paper = .a4
    var landscape = false
    var margin = 20
    var folio: Folio = .right
    var logo = false
    var illustration = false

    init(theme: WeiBeiAppearanceMode, textScale: CGFloat) {
        switch theme {
        case .glassLight, .glassMist: self.theme = .xuan
        case .glassDark, .glassSlate: self.theme = .stele
        default: self.theme = theme
        }
        size = (12 * Double(textScale) * 4).rounded() / 4
    }

    var pageSize: CGSize {
        let dimensions = paper.size
        return landscape ? CGSize(width: dimensions.height, height: dimensions.width) : dimensions
    }
}

@MainActor
final class NotePDFRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let imageHandler = MarkdownImageSchemeHandler()
    private var ready: CheckedContinuation<Void, Error>?

    enum Failure: Error { case resources, load, layout, page }

    func render(_ source: NotePDFSource, options: NotePDFOptions, language: WeiBeiInterfaceLanguage) async throws -> Data {
        guard let editorURL = WeiBeiResources.editorURL else { throw Failure.resources }
        let pageSize = options.pageSize
        let width = Int(ceil(pageSize.width / 0.75))
        let height = Int(ceil(pageSize.height / 0.75))
        let configuration = WeiBeiWebViewConfiguration.make(surface: .editor, allowingInlineMedia: false, nonPersistent: true)
        let controller = configuration.userContentController
        imageHandler.update(
            markdownBaseURLString: source.baseURL?.absoluteString ?? "",
            attachmentDirectory: source.attachments, appearanceMode: options.theme, interfaceLanguage: language
        )
        configuration.setURLSchemeHandler(imageHandler, forURLScheme: "weibeiimage")
        controller.add(self, name: "editorReady")
        controller.add(self, name: "editorFailure")
        let initial = [
            "initialMarkdown": source.markdown, "weiBeiTheme": options.theme.webThemeName,
            "weiBeiInterfaceLanguage": language.rawValue, "weiBeiMarkdownBaseURL": source.baseURL?.absoluteString ?? ""
        ]
        let json = try JSONEncoder().encode(initial)
        controller.addUserScript(WKUserScript(source: """
            Object.assign(window, \(String(decoding: json, as: UTF8.self)));
            window.weiBeiMarkdownEditable = false;
            window.weiBeiNotePDF = true;
            document.documentElement.dataset.weibeiTheme = window.weiBeiTheme;
            document.documentElement.dataset.weibeiLanguage = window.weiBeiInterfaceLanguage;
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let web = WKWebView(frame: frame, configuration: configuration)
        web.navigationDelegate = self
        defer {
            web.stopLoading()
            web.navigationDelegate = nil
            controller.removeScriptMessageHandler(forName: "editorReady")
            controller.removeScriptMessageHandler(forName: "editorFailure")
            imageHandler.invalidate()
        }
        try await withCheckedThrowingContinuation { continuation in
            MarkdownWebNetworkGuard.install(in: controller) { continuation.resume(with: $0) }
        }
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                web.loadFileURL(editorURL, allowingReadAccessTo: editorURL.deletingLastPathComponent().deletingLastPathComponent())
            }
            try Task.checkCancellation()

            let arguments: [String: Any] = [
                "width": width, "height": height, "margin": Int((Double(options.margin) * 96 / 25.4).rounded()),
                "title": source.title, "font": options.font.css, "noteFont": options.font == .note,
                "size": options.size,
                "leading": options.lineSpacing, "space": options.paragraphSpacing,
                "folio": options.folio.rawValue,
                "logo": try options.logo ? Self.imageURL("note-pdf-mark") : "",
                "illustration": try options.illustration ? Self.imageURL("lanting-clear-breeze") : "",
                "caption": language.text("《蘭亭集序》唐摹本（傳馮承素） · 故宫博物院藏",
                                         "Preface to the Orchid Pavilion · Tang copy traditionally attributed to Feng Chengsu")
            ]
            let value = try await web.callAsyncJavaScript(Self.layout, arguments: arguments, in: nil, contentWorld: .page)
            guard let pageCount = value as? Int, pageCount > 0 else { throw Failure.layout }
            let data = NSMutableData()
            var box = CGRect(origin: .zero, size: pageSize)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, [
                    kCGPDFContextTitle: source.title
                  ] as CFDictionary) else { throw Failure.page }
            let configurationPDF = WKPDFConfiguration()
            configurationPDF.rect = frame
            for index in 0..<pageCount {
                try Task.checkCancellation()
                let linkResult = try await web.callAsyncJavaScript(
                    "return window.weiBeiSelectPDFPage(index);",
                    arguments: ["index": index], in: nil, contentWorld: .page
                )
                let pageData = try await web.pdf(configuration: configurationPDF)
                guard let provider = CGDataProvider(data: pageData as CFData),
                      let page = CGPDFDocument(provider)?.page(at: 1) else { throw Failure.page }
                let original = page.getBoxRect(.mediaBox)
                context.beginPDFPage(nil)
                context.saveGState()
                let scaleX = box.width / original.width
                let scaleY = box.height / original.height
                context.scaleBy(x: scaleX, y: scaleY)
                context.drawPDFPage(page)
                context.restoreGState()
                for link in (linkResult as? [[String: Any]]) ?? [] {
                    guard let href = link["href"] as? String, let url = URL(string: href),
                          let rect = link["rect"] as? [Double], rect.count == 4 else { continue }
                    context.setURL(url as CFURL, for: CGRect(
                        x: rect[0] * scaleX, y: box.height - (rect[1] + rect[3]) * scaleY,
                        width: rect[2] * scaleX, height: rect[3] * scaleY
                    ))
                }
                context.endPDFPage()
            }
            context.closePDF()
            return data as Data
        } onCancel: {
            Task { @MainActor in
                self.finishLoading(.failure(CancellationError()))
                web.stopLoading()
                web.loadHTMLString("", baseURL: nil)
            }
        }
    }

    private static func imageURL(_ name: String) throws -> String {
        guard let url = WeiBeiResources.bundle.url(forResource: name, withExtension: "png")
            else { throw Failure.resources }
        return "data:image/png;base64," + (try Data(contentsOf: url)).base64EncodedString()
    }

    private func finishLoading(_ result: Result<Void, Error>) {
        let pending = ready
        ready = nil
        pending?.resume(with: result)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        finishLoading(message.name == "editorReady" ? .success(()) : .failure(Failure.load))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishLoading(.failure(Failure.load))
    }

    // The existing editor has already typeset the Markdown. WebKit fragments
    // that DOM into columns so long paragraphs can flow across physical pages.
    static let layout = """
    const editor = document.querySelector('#editor .ProseMirror');
    if (!editor) throw new Error('Markdown renderer unavailable');

    await window.WeiBeiEditor.prepareNotePDF();
    for (const image of editor.querySelectorAll('img')) image.loading = 'eager';
    await Promise.all(Array.from(editor.querySelectorAll('img'), image => image.decode().catch(() => {})));
    await document.fonts.ready;
    if (!editor.isConnected) throw new Error('Markdown renderer unavailable');

    const style = document.createElement('style');
    style.textContent = `
      html, body { margin: 0; overflow: hidden; background: var(--paper); }
      #editor { display: none; }
      #note-page {
        position: absolute; inset: 0 auto auto 0;
        width: ${width}px; height: ${height}px;
        background: var(--paper); color: var(--ink);
      }
      #note-page .viewport { position: absolute; inset: ${margin}px; overflow: hidden; }
      #note-page .ProseMirror {
        box-sizing: border-box; width: 100%; height: 100%; padding: 0; margin: 0; min-height: 0;
        font-size: ${size}pt; line-height: ${leading}; column-count: 1; column-gap: 0; column-fill: auto;
        overflow-wrap: anywhere; widows: 2; orphans: 2;
      }
      #note-page .ProseMirror > :first-child { margin-top: 0; }
      #note-page .ProseMirror p { margin: 0 0 ${space}em; }
      #note-page .ProseMirror :is(th,td) > p { margin: 0; }
      #note-page .ProseMirror strong { font-weight: 700; }
      #note-page .ProseMirror .weibei-callout-collapse { display: block; opacity: 1; overflow: visible; }
      #note-page .ProseMirror .weibei-math-block { overflow: visible; }
      #note-page .ProseMirror .weibei-math-block :is(.katex, .katex-display) { font-size: 1em; }
      #note-page .ProseMirror.note-writing { font-weight: 300; }
      #note-page .ProseMirror.note-writing :is(h1,h2,h3,h4,h5,h6) { font-family: "Mplus1p Heading", sans-serif; }
      #note-page .ProseMirror h1 { font-size: 1.85em; }
      #note-page .ProseMirror h2 { font-size: 1.42em; }
      #note-page .ProseMirror h3 { font-size: 1.22em; }
      #note-page .ProseMirror :is(h1,h2,h3,h4,h5,h6) { break-after: avoid; }
      #note-page .ProseMirror :is(figure, img, tr, .weibei-math-block, .weibei-mermaid-render) { break-inside: avoid; }
      #note-page .ProseMirror :is(img, svg) { max-width: 100%; max-height: ${height - 2 * margin}px; object-fit: contain; }
      #note-page .ProseMirror :is(pre, pre code) { white-space: pre-wrap; overflow: visible; overflow-wrap: anywhere; }
      #note-page .ProseMirror table { display: table; overflow: visible; table-layout: fixed; width: 100%; }
      #note-page .ProseMirror :is(td,th) { white-space: normal; overflow-wrap: anywhere; }
      #note-page .folio { position: absolute; left: ${margin}px; right: ${margin}px;
        bottom: ${margin / 2}px; color: var(--muted); font: 10pt -apple-system, sans-serif; text-align: ${folio}; }
      #note-page .imprint { display: block; width: 34px; margin-left: auto; box-shadow: none; }
      :root:is([data-weibei-theme="inkstone"], [data-weibei-theme="stele"])
        #note-page :is(.imprint, .title-art img) { filter: brightness(0) invert(1); }
      #note-page figure { margin: 0 0 1em; }
      #note-page figure img { width: min(65%, 400px); display: block; box-shadow: none; }
      #note-page figcaption { color: var(--muted); font: 9pt -apple-system, sans-serif; }
      #note-page .chapter-end { display: block; width: 1px; height: 0; }
    `;
    document.head.append(style);
    const page = document.createElement('main');
    page.id = 'note-page';
    const viewport = document.createElement('div');
    viewport.className = 'viewport';
    const story = editor.cloneNode(true);
    story.classList.remove('weibei-empty-document');
    story.style.fontFamily = font;
    story.classList.toggle('note-writing', noteFont);
    if (story.firstElementChild?.tagName !== 'H1') {
      const heading = document.createElement('h1');
      heading.textContent = title;
      story.prepend(heading);
    }
    if (illustration) {
      const figure = document.createElement('figure');
      figure.className = 'title-art';
      const image = new Image(856, 132);
      image.src = illustration;
      image.style.height = 'auto';
      const credit = document.createElement('figcaption');
      credit.textContent = caption;
      figure.append(image, credit);
      story.firstElementChild.after(figure);
    }
    if (logo) {
      const mark = new Image(128, 128);
      mark.className = 'imprint';
      mark.src = logo;
      mark.style.height = 'auto';
      story.prepend(mark);
    }
    const end = document.createElement('span');
    end.className = 'chapter-end';
    story.append(end);
    viewport.append(story);
    const number = document.createElement('div');
    number.className = 'folio';
    number.hidden = folio === 'hidden';
    page.append(viewport, number);
    document.body.append(page);
    await Promise.all(Array.from(story.querySelectorAll('img'), image => image.decode().catch(() => {})));
    // A layout pass starts loading fonts introduced by the print stylesheet.
    story.getBoundingClientRect();
    await document.fonts.ready;
    const measure = viewport.clientWidth;
    for (const math of story.querySelectorAll('.weibei-math-block')) {
      if (math.scrollWidth > measure) math.style.fontSize = measure / math.scrollWidth + 'em';
    }
    const origin = story.getBoundingClientRect().left;
    const column = rect => Math.max(0, Math.floor((rect.left - origin + 0.01) / measure));
    const pageCount = column(end.getBoundingClientRect()) + 1;

    // Clipping controls the appearance, but PDF readers can extract invisible
    // glyphs outside a clip. Hide off-page text before asking WebKit to draw.
    const atomicSelector = 'img, svg, .weibei-math-node';
    for (const element of story.querySelectorAll(atomicSelector)) {
      if (!element.parentElement.closest(atomicSelector)) {
        element.dataset.pdfColumn = String(column(element.getBoundingClientRect()));
      }
    }
    const walker = document.createTreeWalker(story, NodeFilter.SHOW_TEXT);
    const range = document.createRange();
    const replacements = [];
    for (let text; (text = walker.nextNode()); ) {
      if (!text.data.trim() || text.parentElement.closest(atomicSelector)) continue;
      const rects = (first, last) => {
        range.setStart(text, first);
        range.setEnd(text, last);
        return Array.from(range.getClientRects()).filter(rect => rect.width > 0);
      };
      const lines = rects(0, text.length);
      if (!lines.length) continue;
      const fragment = document.createDocumentFragment();
      const lastColumn = column(lines[lines.length - 1]);
      let offset = 0;
      for (let index = column(lines[0]); index <= lastColumn && offset < text.length; index++) {
        let limit = text.length;
        if (index < lastColumn) {
          let low = offset + 1, high = text.length;
          while (low < high) {
            const middle = Math.floor((low + high) / 2);
            const pastColumn = rects(offset, middle).some(rect => column(rect) > index);
            if (pastColumn) high = middle;
            else low = middle + 1;
          }
          limit = low - 1;
        }
        if (limit <= offset) continue;
        const span = document.createElement('span');
        span.dataset.pdfColumn = String(index);
        span.textContent = text.data.slice(offset, limit);
        fragment.append(span);
        offset = limit;
      }
      replacements.push([text, fragment]);
    }
    for (const [text, fragment] of replacements) text.replaceWith(fragment);

    const mask = document.createElement('style');
    document.head.append(mask);
    window.weiBeiSelectPDFPage = index => {
      story.style.transform = 'translateX(' + (-index * measure) + 'px)';
      mask.textContent = '#note-page [data-pdf-column]:not([data-pdf-column="' + index + '"]) { visibility: hidden; }';
      if (!number.hidden) number.textContent = String(index + 1);
      const visible = viewport.getBoundingClientRect();
      return Array.from(story.querySelectorAll('a[href]')).flatMap(link => {
        if (!['https:', 'http:', 'mailto:'].includes(link.protocol)) return [];
        return Array.from(link.getClientRects()).flatMap(rect => {
          const left = Math.max(rect.left, visible.left), top = Math.max(rect.top, visible.top);
          const right = Math.min(rect.right, visible.right), bottom = Math.min(rect.bottom, visible.bottom);
          return right > left && bottom > top ? [{ href: link.href, rect: [left, top, right - left, bottom - top] }] : [];
        });
      });
    };
    window.weiBeiSelectPDFPage(0);
    return pageCount;
    """
}
