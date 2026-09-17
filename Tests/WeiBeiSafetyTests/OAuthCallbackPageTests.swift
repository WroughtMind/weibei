import XCTest
@testable import WeiBeiCore

final class OAuthCallbackPageTests: XCTestCase {
    private let valid = "GET /auth/callback?code=private-code&state=expected HTTP/1.1\r\n\r\n"

    func testCallbackValidation() {
        let waiter = CallbackWaiter(expectedState: "expected")
        XCTAssertEqual(waiter.parseCode(fromHTTP: valid), "private-code")
        for path in [
            "/auth/callback?code=secret&state=wrong",
            "/auth/callback?code=&state=expected",
            "/auth/callback?state=expected",
            "/auth/callback?error=access_denied&state=expected",
            "/auth/callback?code=secret&state=expected&error=access_denied",
            "/auth/callback?code=one&code=two&state=expected",
            "/auth/callback?code=one&state=expected&state=wrong",
            "/other?code=secret&state=expected"
        ] {
            XCTAssertNil(waiter.parseCode(fromHTTP: "GET \(path) HTTP/1.1\r\n"))
        }
    }

    func testAllLocalizedStatesAndBundledAssets() throws {
        for language in WeiBeiInterfaceLanguage.allCases {
            let page = try OAuthResultPage(language: language)
            XCTAssertEqual(page.images.count, 4)
            if let directory = ProcessInfo.processInfo.environment["WEIBEI_OAUTH_PREVIEW_DIR"] {
                try page.html(state: .working, statusURL: "/auth/status?state=demo")
                    .write(toFile: "\(directory)/\(language.rawValue)-live.html", atomically: true, encoding: .utf8)
            }
            for state in OAuthPageState.allCases {
                let body = page.html(state: state)
                XCTAssertTrue(body.contains("lang=\"\(language.rawValue)\""))
                XCTAssertTrue(body.contains("data-state=\"\(state.rawValue)\""))
                XCTAssertFalse(body.contains("{{"))
                XCTAssertTrue(body.contains("data:image/"))
                XCTAssertFalse(page.copy(state).values.contains(where: { $0.isEmpty }))
                if let directory = ProcessInfo.processInfo.environment["WEIBEI_OAUTH_PREVIEW_DIR"] {
                    try body.write(toFile: "\(directory)/\(language.rawValue)-\(state.rawValue).html", atomically: true, encoding: .utf8)
                }
            }
        }
    }

    func testCallbackBeforeAwaitAndRepeatedCallbackDoNotExchangeTwice() async throws {
        let waiter = CallbackWaiter(expectedState: "expected", page: try OAuthResultPage(language: .english))
        let response = waiter.handle(valid)
        XCTAssertFalse(response.contains("private-code"))
        XCTAssertTrue(response.contains("data-state=\"working\""))
        let code = try await waiter.waitForCode()
        XCTAssertEqual(code, "private-code")
        let duplicateDenial = waiter.handle("GET /auth/callback?error=access_denied&state=expected HTTP/1.1\r\n")
        XCTAssertTrue(duplicateDenial.contains("data-state=\"working\""))
        waiter.complete(.success)
        let repeated = waiter.handle(valid)
        XCTAssertTrue(repeated.contains("data-state=\"success\""))
        waiter.complete(.failed)
        XCTAssertTrue(waiter.handle("GET /auth/status?state=expected HTTP/1.1\r\n").contains("\"state\":\"success\""))
    }

    func testInvalidCallbackDoesNotEndValidLoginAndStatusIsPrivate() async throws {
        let waiter = CallbackWaiter(expectedState: "expected", page: try OAuthResultPage(language: .chinese))
        XCTAssertTrue(waiter.handle("GET /favicon.ico HTTP/1.1\r\n").hasPrefix("HTTP/1.1 404"))
        XCTAssertTrue(waiter.handle(valid.replacingOccurrences(of: "expected", with: "wrong")).contains("data-state=\"invalid\""))
        XCTAssertTrue(waiter.handle("GET /auth/status?state=wrong HTTP/1.1\r\n").hasPrefix("HTTP/1.1 403"))
        _ = waiter.handle(valid)
        let code = try await waiter.waitForCode()
        XCTAssertEqual(code, "private-code")
    }

    func testRealSocketCallbackAndStatus() async throws {
        CallbackWaiter.releasePreviousResultPage()
        let waiter = CallbackWaiter(expectedState: "expected", page: try OAuthResultPage(language: .english))
        let port = UInt16.random(in: 20000...50000)
        try waiter.listen(port: port)
        defer { waiter.cancel(); CallbackWaiter.releasePreviousResultPage() }
        let url = URL(string: "http://127.0.0.1:\(port)/auth/callback?code=private-code&state=expected")!
        let (body, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("data-state=\"working\""))
        let code = try await waiter.waitForCode()
        XCTAssertEqual(code, "private-code")
        waiter.cancel()
        waiter.complete(.success)
        let (status, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/auth/status?state=expected")!)
        XCTAssertEqual(String(decoding: status, as: UTF8.self), "{\"state\":\"success\"}")
    }

    func testCancellationBeforeAwait() async {
        let waiter = CallbackWaiter(expectedState: "expected")
        waiter.cancel()
        do {
            _ = try await waiter.waitForCode()
            XCTFail("Cancelled login must not wait indefinitely")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testDeniedAndFailedResults() async throws {
        for state in [OAuthPageState.failed, .saveFailed, .expired] {
            let waiter = CallbackWaiter(expectedState: "expected", page: try OAuthResultPage(language: .english))
            waiter.complete(state)
            let response = waiter.handle(valid)
            let parts = response.components(separatedBy: "\r\n\r\n")
            XCTAssertEqual(parts.count, 2)
            XCTAssertTrue(parts[0].contains("Content-Length: \(parts[1].utf8.count)"))
            XCTAssertTrue(parts[0].contains("Cache-Control: no-store"))
            XCTAssertTrue(parts[1].contains("data-state=\"\(state.rawValue)\""))
        }
        let waiter = CallbackWaiter(expectedState: "expected", page: try OAuthResultPage(language: .english))
        let denied = waiter.handle("GET /auth/callback?error=access_denied&state=expected HTTP/1.1\r\n")
        XCTAssertTrue(denied.contains("data-state=\"cancelled\""))
        do { _ = try await waiter.waitForCode(); XCTFail("Denial must end the login") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
