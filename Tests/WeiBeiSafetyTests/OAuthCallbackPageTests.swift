import XCTest
@testable import WeiBeiCore

final class OAuthCallbackPageTests: XCTestCase {
    func testCallbackValidationBeforeReceipt() {
        let waiter = CallbackWaiter(expectedState: "expected", language: .english)
        XCTAssertEqual(waiter.parseCode(fromHTTP: "GET /auth/callback?code=secret&state=expected HTTP/1.1\r\n"), "secret")
        for path in [
            "/auth/callback?code=secret&state=wrong",
            "/auth/callback?code=&state=expected",
            "/auth/callback?state=expected",
            "/auth/callback?error=access_denied&state=expected",
            "/auth/callback?code=secret&state=expected&error=access_denied",
            "/other?code=secret&state=expected"
        ] {
            XCTAssertNil(waiter.parseCode(fromHTTP: "GET \(path) HTTP/1.1\r\n"))
        }
    }

    func testLocalizedResponsesAndByteLength() throws {
        for language in WeiBeiInterfaceLanguage.allCases {
            for accepted in [true, false] {
                let response = CallbackWaiter(expectedState: "private-state", language: language)
                    .responseHTML(accepted: accepted)
                let parts = response.components(separatedBy: "\r\n\r\n")
                XCTAssertEqual(parts.count, 2)
                let body = try XCTUnwrap(parts.last)
                XCTAssertTrue(parts[0].hasPrefix(accepted ? "HTTP/1.1 200" : "HTTP/1.1 400"))
                XCTAssertTrue(parts[0].contains("Content-Length: \(body.utf8.count)"))
                XCTAssertTrue(parts[0].contains("Cache-Control: no-store"))
                XCTAssertTrue(body.contains("lang=\"\(language.rawValue)\""))
                XCTAssertFalse(body.contains("private-state"))
                // Receipt must not promise successful token exchange or credential storage.
                XCTAssertFalse(body.contains("登录成功"))
                XCTAssertFalse(body.contains("Signed in successfully"))
                XCTAssertTrue(body.contains(language == .chinese ? "此页面可以关闭" : "You can close this page"))
            }
        }
    }
}
