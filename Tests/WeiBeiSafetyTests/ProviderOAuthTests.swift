import XCTest
@testable import WeiBeiCore

final class ProviderOAuthTests: XCTestCase {
    private final class Stub: URLProtocol {
        static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            do {
                let (status, json) = try Self.handler!(request)
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json))
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
        override func stopLoading() {}
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }
    private func body(_ request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return String(decoding: data, as: UTF8.self)
    }

    func testDeviceAuthorizationAndTrustBoundaries() async throws {
        let session = session()
        defer { session.invalidateAndCancel(); Stub.handler = nil }
        for provider in [AgentProviderID.xai, .kimiCoding] {
            let config = try NativeProviderOAuth.deviceConfiguration(provider)
            let host = provider == .xai ? "accounts.x.ai" : "www.kimi.com"
            var polls = 0, waits: [Double] = [], displayedCode = ""
            Stub.handler = { request in
                let body = self.body(request)
                XCTAssertTrue(body.contains("client_id=" + config.clientID))
                if request.url!.absoluteString == config.authorizationURL {
                    XCTAssertFalse(body.contains("secret-device"))
                    return (200, ["device_code": "secret-device", "user_code": "ABCD-EFGH", "verification_uri": "https://\(host)/activate", "expires_in": 1800, "interval": 5])
                }
                XCTAssertEqual(request.url!.absoluteString, config.tokenURL)
                XCTAssertTrue(body.contains("device_code=secret-device"))
                polls += 1
                if polls == 1 { return (400, ["error": "authorization_pending"]) }
                if polls == 2 { return (400, ["error": "slow_down"]) }
                return (200, ["access_token": "private-access", "refresh_token": "private-refresh", "expires_in": 3600])
            }
            let record = try await NativeProviderOAuth.authorizeDevice(provider: provider, session: session, sleep: { waits.append($0) }) { code, url in
                displayedCode = code
                XCTAssertEqual(url.host, host)
            }
            XCTAssertEqual(displayedCode, "ABCD-EFGH")
            XCTAssertEqual(waits, [5, 5, 10])
            XCTAssertEqual(record.provider, provider.credentialProviderID)
            XCTAssertEqual(record.accessToken, "private-access")
            XCTAssertGreaterThan(record.expiresAt!.timeIntervalSinceNow, 3500)
            for error in ["access_denied", "expired_token"] {
                Stub.handler = { request in
                    if request.url!.absoluteString == config.authorizationURL {
                        return (200, ["device_code": "secret-device", "user_code": "ABCD", "verification_uri": "https://\(host)/activate", "expires_in": 1800])
                    }
                    return (400, ["error": error])
                }
                do {
                    _ = try await NativeProviderOAuth.authorizeDevice(provider: provider, session: session, sleep: { _ in }) { _, _ in }
                    XCTFail("Denied/expired authorization must not return credentials")
                } catch let failure as NativeLLMFailure { XCTAssertEqual(failure.code, "oauth_timeout") }
                catch { XCTAssertTrue(error is CancellationError) }
            }
        }
        for url in ["http://accounts.x.ai/a", "https://x.ai.evil.test/a", "https://evil.test/x.ai", "https://user:pass@accounts.x.ai/a", "https://accounts.x.ai:8443/a", "javascript:alert(1)"] {
            XCTAssertThrowsError(try NativeProviderOAuth.verificationURL(url, domains: ["x.ai"]))
        }
        for bad in [Double.infinity, -1, 0, true] as [Any] {
            XCTAssertThrowsError(try NativeProviderOAuth.positiveNumber(["expires_in": bad], "expires_in"))
        }
        XCTAssertThrowsError(try NativeProviderOAuth.string(["access_token": "value\r\nInjected: header"], "access_token"))
    }

    func testRefreshPreservesRotationAndDoesNotUndoLogout() async throws {
        let session = session()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = NativeAgentCredentialStore(fileURL: root.appendingPathComponent("credentials.json"))
        defer { session.invalidateAndCancel(); Stub.handler = nil; try? FileManager.default.removeItem(at: root) }
        for provider in [AgentProviderID.xai, .kimiCoding] {
            let old = NativeAgentCredentialRecord(provider: provider.credentialProviderID, accessToken: "expired", refreshToken: "refresh-old", expiresAt: .distantPast)
            try store.upsert(old)
            var calls = 0
            Stub.handler = { request in
                calls += 1
                XCTAssertTrue(self.body(request).contains("refresh_token=refresh-old"))
                return (200, ["access_token": "renewed", "expires_in": 3600])
            }
            async let first = NativeProviderOAuth.credential(provider: provider, store: store, session: session)
            async let second = NativeProviderOAuth.credential(provider: provider, store: store, session: session)
            let (a, b) = try await (first, second)
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(a, b)
            XCTAssertEqual(a?.refreshToken, "refresh-old")
            XCTAssertEqual(try store.load()[provider.credentialProviderID], a)
            try store.upsert(old)
            Stub.handler = { _ in
                try store.remove(provider: provider.credentialProviderID)
                return (200, ["access_token": "must-not-save", "refresh_token": "rotated", "expires_in": 3600])
            }
            do {
                _ = try await NativeProviderOAuth.credential(provider: provider, store: store, session: session)
                XCTFail("A logout must win over a token refresh")
            } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertNil(try store.load()[provider.credentialProviderID])
        }
    }

    func testAdaptersUseSelectedCredentialAndProviderEndpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = NativeAgentCredentialStore(fileURL: root.appendingPathComponent("credentials.json"))
        defer { try? FileManager.default.removeItem(at: root) }
        for provider in [AgentProviderID.xai, .kimiCoding, .openrouter] {
            let record = NativeAgentCredentialRecord(provider: provider.credentialProviderID, accessToken: "oauth-token", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(3600))
            try store.upsert(record)
            let endpoint = try AgentProviderEndpoint(provider: provider, baseURL: "")
            let adapter = try await NativeLLMAdapterFactory.make(provider: provider, model: "test", endpoint: endpoint, authMethod: .subscription, credentialStore: store)
            if provider == .xai {
                let responses = try XCTUnwrap(adapter as? OpenAIResponsesProvider)
                XCTAssertEqual(responses.accessToken, "oauth-token")
                XCTAssertEqual(responses.baseURL.absoluteString, "https://api.x.ai/v1")
            } else {
                let chat = try XCTUnwrap(adapter as? OpenAIChatCompletionsProvider)
                XCTAssertEqual(chat.apiKey, "oauth-token")
                XCTAssertEqual(chat.baseURL.absoluteString, provider == .kimiCoding ? "https://api.kimi.com/coding/v1" : "https://openrouter.ai/api/v1")
            }
            do {
                _ = try await NativeLLMAdapterFactory.make(provider: provider, model: "test", endpoint: endpoint, authMethod: .apiKey, credentialStore: store)
                XCTFail("Selecting an API key must not silently use the account token")
            } catch let error as NativeLLMFailure { XCTAssertEqual(error.status, 401) }
            var injected = endpoint
            injected.baseURL = "https://unrelated.test/v1"
            do {
                _ = try await NativeLLMAdapterFactory.make(provider: provider, model: "test", endpoint: injected, authMethod: .subscription, credentialStore: store)
                XCTFail("Account tokens must not leave their provider")
            } catch let error as NativeLLMFailure { XCTAssertEqual(error.status, 401) }
            try store.upsert(NativeAgentCredentialRecord(provider: provider.credentialProviderID, apiKey: "manual-key"))
            do {
                _ = try await NativeLLMAdapterFactory.make(provider: provider, model: "test", endpoint: endpoint, authMethod: .subscription, credentialStore: store)
                XCTFail("Account sign-in must not silently use a manually entered API key")
            } catch let error as NativeLLMFailure { XCTAssertEqual(error.status, 401) }
        }
    }

    func testOpenRouterPKCEAndProviderResultPages() async throws {
        let session = session()
        defer { session.invalidateAndCancel(); Stub.handler = nil }
        Stub.handler = { request in
            XCTAssertEqual(request.url!.absoluteString, "https://openrouter.ai/api/v1/auth/keys")
            let json = try JSONSerialization.jsonObject(with: Data(self.body(request).utf8)) as! [String: String]
            XCTAssertEqual(json, ["code": "one-time-code", "code_verifier": "private-verifier", "code_challenge_method": "S256"])
            return (200, ["key": "user-controlled-key"])
        }
        let record = try await NativeProviderOAuth.exchangeOpenRouter(code: "one-time-code", verifier: "private-verifier", session: session)
        XCTAssertEqual(record.accessToken, "user-controlled-key")
        XCTAssertNil(record.apiKey)
        XCTAssertNil(record.expiresAt)
        Stub.handler = { request in
            XCTAssertEqual(request.url!.absoluteString, "https://openrouter.ai/api/v1/key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-controlled-key")
            return (403, ["error": ["message": "provider-private-details"]])
        }
        do { try await NativeProviderOAuth.validate(record, provider: .openrouter, session: session); XCTFail("Must reject forbidden access") }
        catch let error as NativeLLMFailure { XCTAssertEqual(error.status, 403); XCTAssertFalse(error.message.contains("provider-private-details")) }
        for provider in [AgentProviderID.xai, .kimiCoding, .openrouter] {
            for language in WeiBeiInterfaceLanguage.allCases {
                let page = try OAuthResultPage(language: language, provider: provider)
                if let directory = ProcessInfo.processInfo.environment["WEIBEI_OAUTH_PREVIEW_DIR"] {
                    try page.html(state: .success).write(toFile: "\(directory)/\(provider.rawValue)-\(language.rawValue).html", atomically: true, encoding: .utf8)
                }
                let waiter = CallbackWaiter(expectedState: "result-state", page: page, resultOnly: true)
                let body = waiter.handle("GET /auth/result?state=result-state HTTP/1.1\r\n\r\n")
                XCTAssertTrue(body.contains(provider.label(language: language)))
                XCTAssertFalse(body.contains("ChatGPT"))
                XCTAssertFalse(body.contains("user-controlled-key"))
                XCTAssertTrue(waiter.handle("GET /auth/result?state=wrong HTTP/1.1\r\n").contains("403 Forbidden"))
                XCTAssertTrue(waiter.handle("GET /auth/callback?state=result-state&code=injected HTTP/1.1\r\n").contains("404 Not Found"))
                waiter.complete(.success)
                XCTAssertTrue(waiter.handle("GET /auth/result?state=result-state HTTP/1.1\r\n").contains("data-state=\"success\""))
            }
        }
        CallbackWaiter.releasePreviousResultPage()
        let listener = CallbackWaiter(expectedState: "ephemeral", page: try OAuthResultPage(language: .english))
        try listener.listen(port: 0)
        XCTAssertNotEqual(listener.boundPort, 0)
        listener.cancel()
        CallbackWaiter.releasePreviousResultPage()
    }
}
