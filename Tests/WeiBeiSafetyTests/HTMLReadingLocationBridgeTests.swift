import AppKit
import WebKit
import XCTest
@testable import WeiBei
import WeiBeiCore

final class HTMLReadingLocationBridgeTests: XCTestCase {
    @MainActor
    func testStaleContentRailCompletionCannotFailAnotherDocumentRequest() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let loaded = expectation(description: "content rail bridge loaded")
        let navigationProbe = HTMLReadingLocationProbe()
        navigationProbe.onLoad = { loaded.fulfill() }
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = navigationProbe
        web.loadHTMLString("""
        <!doctype html><body></body><script>
        window.WeiBeiContentRail = { scrollTo() { return false; }, scan() {} };
        </script>
        """, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 3)

        var unavailableRequestIDs: [UUID] = []
        let reader = WebReaderRepresentable(
            html: "",
            onContentRailTargetUnavailable: { unavailableRequestIDs.append($0) },
            onSelectionChange: { _, _ in }
        )
        let coordinator = reader.makeCoordinator()
        coordinator.webView = web
        _ = coordinator.taggedHTML("", token: "first-document")
        let staleRequestID = UUID()
        coordinator.contentRailTarget = WebReaderContentRailTarget(
            id: "html-heading-0",
            requestID: staleRequestID
        )
        coordinator.applyContentRailTarget(in: web)

        _ = coordinator.taggedHTML("", token: "second-document")
        let currentRequestID = UUID()
        coordinator.contentRailTarget = WebReaderContentRailTarget(
            id: "html-heading-1",
            requestID: currentRequestID
        )
        _ = try await web.evaluateJavaScript("true")
        await Task.yield()
        XCTAssertTrue(unavailableRequestIDs.isEmpty)

        coordinator.webView(web, didFinish: nil)
        _ = try await web.evaluateJavaScript("true")
        await Task.yield()
        XCTAssertTrue(unavailableRequestIDs.isEmpty)

        coordinator.applyContentRailTarget(in: web)
        let deadline = Date().addingTimeInterval(3)
        while unavailableRequestIDs.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(unavailableRequestIDs, [currentRequestID])
        withExtendedLifetime(navigationProbe) {}
    }

    @MainActor
    func testVisibleHTMLLocationsReadTheSameBlocksIncludingDuplicatesAndLongPages() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let repeated = "重复段落用于检查当前阅读位置，重新打开时必须回到第二次出现的位置。"
        let paragraphs = (0..<40).map { index in
            "<p id='block-\(index)'>位置\(index)：这一段有自己的正文标记，当前发问不应该读取相邻段落的内容。</p>"
        }.joined()
        let html = """
        <!doctype html><meta charset="utf-8"><style>p,li { min-height: 180px; margin: 0; }</style>
        <nav><p>\(repeated)</p></nav>
        <main><p hidden>\(repeated)</p><p id="first">\(repeated)</p>
        <p id="short">短段落</p><p id="emoji">🙂小段🙂</p>
        <blockquote><p id="nested">引用中的独立段落也必须和原文索引的位置一致，不能被外层引用吃掉。</p></blockquote>
        <ul><li><p id="listed">列表内部的正文不能因为嵌套层级而发生阅读位置编号偏移。</p></li></ul>
        <p id="optional-first">First paragraph<p id="optional-second">Second paragraph</p>
        <p id="quoted" data-expression="x > y">Visible paragraph</p>
        <ul><li id="optional-li-first">First list item<li id="optional-li-second">Second list item</ul>
        <p id="entities">A&amp;B&nbsp; C <strong>inline</strong> text</p>
        <p id="before-figure">Before figure<figure><figcaption id="caption">Figure caption</figcaption></figure>
        <p id="combining">Cafe\u{0301} with combining accent</p>
        <p id="astral">\(String(repeating: "𐐀", count: 300)) tail</p>
        \(paragraphs)<p id="second">\(repeated)</p></main>
        <footer><p>页脚中的长段落只用于验证它不会改变正文段落位置，不属于阅读正文。</p></footer>
        """
        let probe = HTMLReadingLocationProbe()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(probe, name: "contentRailSections")
        configuration.userContentController.add(probe, name: "contentRailActive")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        web.navigationDelegate = probe
        defer {
            configuration.userContentController.removeAllScriptMessageHandlers()
            web.stopLoading()
            window.close()
        }
        XCTAssertFalse(window.isVisible)
        web.loadHTMLString(html, baseURL: nil)
        let loadDeadline = Date().addingTimeInterval(10)
        while !probe.didLoad && Date() < loadDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(probe.didLoad)
        func evaluate(_ script: String) throws -> Any? {
            var result: Result<Any?, Error>?
            web.evaluateJavaScript(script) { value, error in
                result = error.map(Result.failure) ?? .success(value)
            }
            let deadline = Date().addingTimeInterval(5)
            while result == nil && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            return try XCTUnwrap(result, "JavaScript evaluation timed out").get()
        }
        // Hidden WebKit views do not drive display frames; still use real DOM geometry.
        _ = try evaluate("window.requestAnimationFrame = callback => { callback(); return 1; }; true;")
        _ = try evaluate(WebReaderRepresentable.contentRailScript(language: .chinese) + "\n; true;")
        let blocks = try evaluate("""
        ['first', 'short', 'emoji', 'nested', 'listed', 'optional-first', 'optional-second', 'quoted',
         'optional-li-first', 'optional-li-second', 'entities', 'before-figure', 'caption', 'combining', 'astral', 'block-17', 'block-37', 'second'].map(name => {
          const element = document.getElementById(name);
          return { name, location: element.dataset.weibeiContentRailID || '', text: element.textContent.replace(/\\s+/g, ' ').trim() };
        })
        """) as? [[String: String]]
        let observed = try XCTUnwrap(blocks)
        let passages = CourseDocumentSearchIndex.htmlPassages(html)
        for block in observed {
            let location = try XCTUnwrap(block["location"])
            XCTAssertFalse(location.isEmpty, block["name"] ?? "")
            XCTAssertEqual(passages.filter { $0.location == location }.map(\.text), [block["text"]!])
        }
        XCTAssertNotEqual(observed.first?["location"], observed.last?["location"])

        for name in ["block-17", "block-37", "second"] {
            let target = try XCTUnwrap(observed.first { $0["name"] == name }?["location"])
            probe.activeIDs.removeAll()
            _ = try evaluate("""
              (() => {
              const target = document.getElementById(\(String(data: try JSONEncoder().encode(name), encoding: .utf8)!));
              scrollTo(0, scrollY + target.getBoundingClientRect().top - innerHeight * 0.32 + 1);
              dispatchEvent(new Event('scroll'));
              return true;
              })()
              """)
            let activeDeadline = Date().addingTimeInterval(3)
            while !probe.activeIDs.contains(target) && Date() < activeDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            XCTAssertTrue(probe.activeIDs.contains(target), name)
        }
        // The saved block can be outside the 24 markers shown in the rail.
        let restored = try XCTUnwrap(observed.first { $0["name"] == "block-37" }?["location"])
        probe.activeIDs.removeAll()
        let encoded = String(data: try JSONEncoder().encode(restored), encoding: .utf8)!
        XCTAssertEqual(try evaluate("window.WeiBeiContentRail.scrollTo(\(encoded))") as? Bool, true)
        let restoreDeadline = Date().addingTimeInterval(3)
        while !probe.activeIDs.contains(restored) && Date() < restoreDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(probe.activeIDs.contains(restored))
        XCTAssertEqual(try evaluate("window.WeiBeiContentRail.scrollTo(\"html-block-missing\")") as? Bool, false)
        XCTAssertFalse(window.isVisible)
    }
}

private final class HTMLReadingLocationProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var didLoad = false
    var onLoad: () -> Void = {}
    var activeIDs: [String] = []
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoad = true
        onLoad()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "contentRailActive", let body = message.body as? [String: Any],
              let id = body["id"] as? String else { return }
        activeIDs.append(id)
    }
}
