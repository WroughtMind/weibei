import AppKit
import WebKit
import XCTest
@testable import WeiBei

final class MarpReaderControlsTests: XCTestCase {
    @MainActor
    func testReplacesExportedChromeWithoutBreakingDelegatedNavigation() async throws {
        let page = try await MarpControlsPage(html: Self.marpHTML)
        try await page.expect("document.querySelectorAll('.bespoke-marp-osc').length", 0)
        try await page.expect("document.querySelectorAll('.weibei-slide-controls').length", 1)
        try await page.expect("document.querySelectorAll('[data-bespoke-marp-osc=presenter], [data-bespoke-marp-osc=fullscreen]').length", 0)
        try await page.expect("document.querySelector('[data-bespoke-marp-osc=page]').textContent", "1 / 3")

        // The export's delegated listener requires the button to be the event target.
        try await page.expect("""
        (() => {
          const next = document.querySelector('[data-bespoke-marp-osc=next]');
          next.click();
          return window.navigation.join(',');
        })()
        """, "next")
        try await page.expect("getComputedStyle(document.querySelector('.weibei-slide-controls svg')).pointerEvents", "none")
        try await page.expect("document.querySelector('[data-bespoke-marp-osc=prev]').disabled", true)
    }

    @MainActor
    func testEngineUpdatesPageAndBoundariesWhileReaderKeepsControlsAccessible() async throws {
        let page = try await MarpControlsPage(html: Self.marpHTML)
        _ = try await page.evaluate("""
        (() => {
          const controls = document.querySelector('.weibei-slide-controls');
          controls.querySelector('[data-bespoke-marp-osc=page]').textContent = 'Page 3 of 3';
          controls.querySelector('[data-bespoke-marp-osc=prev]').disabled = false;
          controls.querySelector('[data-bespoke-marp-osc=next]').disabled = true;
          controls.setAttribute('aria-hidden', 'true'); controls.inert = true;
          return true;
        })()
        """)
        try await page.expect("document.querySelector('[data-bespoke-marp-osc=page]').textContent", "3 / 3")
        try await page.expect("document.querySelector('[data-bespoke-marp-osc=page]').getAttribute('aria-label')", "第 3 页，共 3 页")
        try await page.expect("document.querySelector('.weibei-slide-controls').hasAttribute('aria-hidden') || document.querySelector('.weibei-slide-controls').inert", false)
        _ = try await page.evaluate("document.querySelector('[data-bespoke-marp-osc=next]').click(); true")
        try await page.expect("window.navigation.length", 0)
        _ = try await page.evaluate("document.querySelector('[data-bespoke-marp-osc=prev]').click(); true")
        try await page.expect("window.navigation.join(',')", "prev")
    }

    @MainActor
    func testThemeLanguageAndCompactViewportFollowTheReader() async throws {
        let page = try await MarpControlsPage(html: Self.marpHTML)
        _ = try await page.evaluate("""
        document.documentElement.style.setProperty('--weibei-note-ink', '#d7cbb0');
        document.documentElement.style.setProperty('--weibei-note-fill', '#151515');
        window.WeiBeiMarpControls.setLanguage('english'); true;
        """)
        try await page.expect("document.querySelector('[data-bespoke-marp-osc=next]').getAttribute('aria-label')", "Next page")
        try await page.expect("getComputedStyle(document.querySelector('[data-bespoke-marp-osc=next]')).color", "rgb(215, 203, 176)")
        try await page.expect("""
        (() => { const rect = document.querySelector('.weibei-slide-controls').getBoundingClientRect();
          return rect.left >= 0 && rect.right <= innerWidth && rect.bottom <= innerHeight; })()
        """, true)
        try await page.expect("document.querySelector('[data-bespoke-marp-osc=next]').tabIndex", 0)
        _ = try await page.evaluate(ReaderMarpControls.script(isEnglish: false) + "\n; true;")
        try await page.expect("document.querySelectorAll('.weibei-slide-controls').length", 1)
        try await page.expect("document.querySelector('[data-bespoke-marp-osc=next]').title", "下一页")
    }

    @MainActor
    func testOrdinaryHTMLIsUnchangedAndLateMarpControlsAreAdapted() async throws {
        let body = "<button id='ordinary'>下一节</button><div class='bespoke-marp-osc' id='ordinary-container'>正文</div>"
        let page = try await MarpControlsPage(html: "<!doctype html>\(body)")
        try await page.expect("document.querySelectorAll('.weibei-slide-controls').length", 0)
        try await page.expect("getComputedStyle(document.getElementById('ordinary-container')).visibility", "visible")
        let encoded = String(data: try JSONEncoder().encode(Self.marpBody), encoding: .utf8)!
        _ = try await page.evaluate("document.body.insertAdjacentHTML('beforeend', \(encoded)); true;")
        try await page.expect("document.querySelectorAll('.weibei-slide-controls').length", 1)
        try await page.expect("document.getElementById('ordinary').textContent", "下一节")
    }

    private static let marpBody = """
    <div class="bespoke-marp-parent"><svg data-marpit-svg></svg><div class="bespoke-marp-osc">
      <button data-bespoke-marp-osc="prev" tabindex="-1" disabled>Previous slide</button>
      <span data-bespoke-marp-osc="page">Page 1 of 3</span>
      <button data-bespoke-marp-osc="next" tabindex="-1">Next slide</button>
      <button data-bespoke-marp-osc="fullscreen">Toggle fullscreen</button>
      <button data-bespoke-marp-osc="presenter">Open presenter view</button>
    </div></div>
    """

    private static var marpHTML: String {
        """
        <!doctype html><style>
        :root { --weibei-note-fill:#f9f1de; --weibei-note-ink:#1d1814; --weibei-note-muted:#76675d; --weibei-note-accent:#91261c; }
        div, span { color: red !important; background-color: transparent !important; }
        </style>\(marpBody)
        <script>
        window.navigation = [];
        document.querySelector('.bespoke-marp-osc').addEventListener('click', event => {
          if (event.target instanceof HTMLElement) window.navigation.push(event.target.dataset.bespokeMarpOsc);
        });
        </script>
        """
    }
}

@MainActor
private final class MarpControlsPage: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private let loaded = XCTestExpectation(description: "Marp controls page loaded")

    init(html: String) async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(source: ReaderMarpControls.styleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: ReaderMarpControls.script(isEnglish: false), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 180, height: 240), configuration: configuration)
        super.init()
        web.navigationDelegate = self
        web.loadHTMLString(html, baseURL: nil)
        let result = await XCTWaiter.fulfillment(of: [loaded], timeout: 10)
        XCTAssertEqual(result, .completed)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func evaluate(_ script: String) async throws -> Any? { try await web.evaluateJavaScript(script) }

    func expect<Value: Equatable>(_ script: String, _ expected: Value, file: StaticString = #filePath, line: UInt = #line) async throws {
        let value = try await evaluate(script) as? Value
        XCTAssertEqual(value, expected, file: file, line: line)
    }
}
