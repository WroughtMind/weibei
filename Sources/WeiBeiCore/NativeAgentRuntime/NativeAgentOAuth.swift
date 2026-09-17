import CryptoKit
import Darwin
import Foundation
import Security

/// ChatGPT / openai-codex OAuth, following OpenAI Codex CLI
/// (`auth.openai.com`, PKCE S256, localhost callback, refresh + revoke).
public enum NativeOpenAIOAuth {
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let issuer = "https://auth.openai.com"
    public static let preferredPort: UInt16 = 1455
    public static let fallbackPort: UInt16 = 1457
    public static let originator = "weibei"
    public static let scope =
        "openid profile email offline_access api.connectors.read api.connectors.invoke"

    public struct PKCE: Equatable, Sendable {
        public var verifier: String
        public var challenge: String
    }

    public static func makePKCE(entropy: Data? = nil) -> PKCE {
        let bytes: Data
        if let entropy, entropy.count >= 32 {
            bytes = entropy
        } else {
            var raw = [UInt8](repeating: 0, count: 64)
            _ = SecRandomCopyBytes(kSecRandomDefault, raw.count, &raw)
            bytes = Data(raw)
        }
        let verifier = base64URL(bytes)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCE(verifier: verifier, challenge: base64URL(Data(digest)))
    }

    public static func authorizeURL(
        redirectURI: String,
        pkce: PKCE,
        state: String,
        issuer: String = issuer,
        clientID: String = clientID
    ) -> URL {
        var components = URLComponents(string: "\(issuer)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: originator),
        ]
        return components.url!
    }

    public static func accountID(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let id = object["chatgpt_account_id"] as? String, !id.isEmpty { return id }
        if let https = object["https://api.openai.com/auth"] as? [String: Any],
           let id = https["chatgpt_account_id"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    public static func expiresAt(fromJWT jwt: String, fallbackSeconds: TimeInterval = 3600) -> Date {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            return Date().addingTimeInterval(fallbackSeconds)
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Date().addingTimeInterval(fallbackSeconds)
        }
        let exp = (object["exp"] as? NSNumber)?.doubleValue
        guard let exp else { return Date().addingTimeInterval(fallbackSeconds) }
        return Date(timeIntervalSince1970: exp)
    }

    public static func exchangeCode(
        code: String,
        redirectURI: String,
        pkce: PKCE,
        session: URLSession = .shared
    ) async throws -> NativeAgentCredentialRecord {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(urlEncode(code))",
            "redirect_uri=\(urlEncode(redirectURI))",
            "client_id=\(urlEncode(clientID))",
            "code_verifier=\(urlEncode(pkce.verifier))",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await session.data(for: request)
        try throwIfHTTPError(response, body: data)
        return try record(fromTokenJSON: data)
    }

    public static func refresh(
        _ record: NativeAgentCredentialRecord,
        session: URLSession = .shared
    ) async throws -> NativeAgentCredentialRecord {
        guard let refreshToken = record.refreshToken, !refreshToken.isEmpty else {
            throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing refresh token")
        }
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        let (data, response) = try await session.data(for: request)
        try throwIfHTTPError(response, body: data)
        var next = try recordFromTokenJSON(data, provider: record.provider)
        if next.refreshToken == nil { next.refreshToken = refreshToken }
        if next.accountID == nil { next.accountID = record.accountID }
        return next
    }

    public static func ensureFreshAccessToken(
        in store: NativeAgentCredentialStore = (try? NativeAgentCredentialStore.defaultStore())
            ?? NativeAgentCredentialStore(fileURL: FileManager.default.temporaryDirectory),
        provider: String = AgentProviderID.openaiCodex.rawValue,
        now: Date = Date(),
        session: URLSession = .shared
    ) async throws -> NativeAgentCredentialRecord {
        guard var record = try store.load()[provider],
              let token = record.accessToken, !token.isEmpty else {
            throw NativeLLMFailure(code: "unauthorized", status: 401, message: "ChatGPT subscription is not signed in")
        }
        if let expires = record.expiresAt, expires.timeIntervalSince(now) > 120 {
            return record
        }
        record = try await refresh(record, session: session)
        try store.upsert(record)
        return record
    }

    public static func logout(
        from store: NativeAgentCredentialStore,
        provider: String = AgentProviderID.openaiCodex.rawValue,
        session: URLSession = NativeOpenAIOAuth.shortTimeoutSession
    ) async throws {
        if let record = try store.load()[provider] {
            if let token = record.refreshToken ?? record.accessToken {
                var request = URLRequest(url: URL(string: "\(issuer)/oauth/revoke")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data("token=\(urlEncode(token))&client_id=\(urlEncode(clientID))".utf8)
                _ = try? await session.data(for: request)
            }
        }
        try store.remove(provider: provider)
        try store.scrubBackup(provider: provider)
    }

    public static func parseCallbackCode(fromHTTP request: String, expectedState: String) -> String? {
        CallbackWaiter(expectedState: expectedState).parseCode(fromHTTP: request)
    }

    public static var shortTimeoutSession: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        return URLSession(configuration: config)
    }

    public static func leftoverCredentialExists(
        in store: NativeAgentCredentialStore,
        provider: String = AgentProviderID.openaiCodex.rawValue
    ) throws -> Bool {
        if try store.load()[provider] != nil { return true }
        let backup = store.fileURL.appendingPathExtension("bak")
        guard FileManager.default.fileExists(atPath: backup.path) else { return false }
        guard let records = try? JSONDecoder().decode(
            [String: NativeAgentCredentialRecord].self,
            from: Data(contentsOf: backup)
        ) else {
            return true
        }
        return records[provider] != nil
    }

    /// Browser login: local callback on 1455/1457, then token exchange. Does not log secrets.
    public static func loginWithBrowser(
        store: NativeAgentCredentialStore,
        language: WeiBeiInterfaceLanguage,
        openURL: (URL) -> Void,
        session: URLSession = .shared
    ) async throws -> NativeAgentCredentialRecord {
        let pkce = makePKCE()
        let state = base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        let port = try bindAvailablePort()
        let redirectURI = "http://localhost:\(port)/auth/callback"
        let url = authorizeURL(redirectURI: redirectURI, pkce: pkce, state: state)
        let waiter = CallbackWaiter(expectedState: state, language: language)
        try waiter.listen(port: port)
        openURL(url)
        let code = try await waiter.waitForCode()
        let record = try await exchangeCode(code: code, redirectURI: redirectURI, pkce: pkce, session: session)
        try store.upsert(record)
        return record
    }

    static func record(fromTokenJSON data: Data) throws -> NativeAgentCredentialRecord {
        try recordFromTokenJSON(data, provider: AgentProviderID.openaiCodex.rawValue)
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func recordFromTokenJSON(_ data: Data, provider: String) throws -> NativeAgentCredentialRecord {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty else {
            throw NativeLLMFailure(code: "unauthorized", message: "token endpoint did not return access_token")
        }
        let idToken = object["id_token"] as? String
        let refresh = object["refresh_token"] as? String
        let expiresIn = (object["expires_in"] as? Int).map(TimeInterval.init)
            ?? (object["expires_in"] as? Double)
        let expiresAt = expiresIn.map { Date().addingTimeInterval($0) }
            ?? idToken.map { Self.expiresAt(fromJWT: $0) }
        return NativeAgentCredentialRecord(
            provider: provider,
            accessToken: access,
            refreshToken: refresh,
            expiresAt: expiresAt,
            accountID: idToken.flatMap(accountID(fromJWT:))
        )
    }

    private static func throwIfHTTPError(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200...299).contains(http.statusCode) { return }
        let text = String(data: body, encoding: .utf8) ?? ""
        let clipped = String(text.prefix(400))
        throw NativeLLMFailure(
            code: http.statusCode == 401 ? "unauthorized" : "server_error",
            status: http.statusCode,
            message: "OAuth HTTP \(http.statusCode) \(clipped)"
        )
    }

    private static func bindAvailablePort() throws -> UInt16 {
        for port in [preferredPort, fallbackPort] {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }
            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                    bind(fd, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(fd)
            if bindResult == 0 { return port }
        }
        throw NativeLLMFailure(code: "oauth_port", message: "localhost callback ports 1455/1457 are busy")
    }
}

final class CallbackWaiter: @unchecked Sendable {
    private let expectedState: String
    private let language: WeiBeiInterfaceLanguage
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var listenFD: Int32 = -1

    init(expectedState: String, language: WeiBeiInterfaceLanguage = .english) {
        self.expectedState = expectedState
        self.language = language
    }

    func listen(port: UInt16) throws {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NativeLLMFailure(code: "oauth_port", message: "could not open callback socket")
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                bind(fd, pointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 1) == 0 else {
            close(fd)
            throw NativeLLMFailure(code: "oauth_port", message: "could not listen on localhost:\(port)")
        }
        listenFD = fd
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func acceptLoop() {
        var client = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &client) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                accept(listenFD, pointer, &length)
            }
        }
        defer {
            if listenFD >= 0 { close(listenFD) }
            if clientFD >= 0 { close(clientFD) }
        }
        guard clientFD >= 0 else {
            finish(error: NativeLLMFailure(code: "oauth_callback", message: "callback accept failed"))
            return
        }
        var buffer = [UInt8](repeating: 0, count: 8_192)
        let n = recv(clientFD, &buffer, buffer.count, 0)
        let raw = n > 0 ? String(bytes: buffer[0..<n], encoding: .utf8) ?? "" : ""
        let code = parseCode(fromHTTP: raw)
        let response = responseHTML(accepted: code != nil)
        let bytes = Array(response.utf8)
        bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = send(clientFD, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                if sent < 0 && errno == EINTR { continue }
                guard sent > 0 else { break }
                offset += sent
            }
        }
        if let code {
            finish(code: code)
        } else {
            finish(error: NativeLLMFailure(code: "oauth_callback", message: "callback missing authorization code"))
        }
    }

    /// The callback is only a receipt; token exchange and storage still happen in the app.
    func responseHTML(accepted: Bool) -> String {
        let title = accepted
            ? language.text("已收到 ChatGPT 授权", "ChatGPT authorization received")
            : language.text("授权未完成", "Authorization incomplete")
        let detail = accepted
            ? language.text("请返回魏碑查看登录结果。", "Return to WeiBei to check your sign-in status.")
            : language.text("未能验证本次授权，请返回魏碑重新登录。", "This authorization could not be verified. Return to WeiBei and sign in again.")
        let close = language.text("此页面可以关闭。", "You can close this page.")
        let brand = language.text("魏碑", "WeiBei")
        let symbol = accepted ? #"<path d="M7 12l3 3 7-7"/>"# : #"<path d="M12 7v6m0 4h.01"/>"#
        let body = """
        <!doctype html>
        <html lang="\(language.rawValue)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light dark">
          <title>\(title) · \(brand)</title>
          <style>
            :root { color-scheme: light dark; --paper: #f8f7f3; --ink: #242922; --muted: #62685f;
              --accent: #3d6545; --tint: #e7eee4; --rule: #dce0d6; }
            * { box-sizing: border-box; }
            body { margin: 0; background: var(--paper); color: var(--ink);
              font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Segoe UI", sans-serif; }
            main { width: min(100%, 560px); margin: 0 auto; padding: clamp(64px, 20vh, 200px) 28px 48px; }
            .brand { margin: 0 0 52px; font-size: 18px; font-weight: 600; letter-spacing: .06em; }
            .status { display: grid; place-items: center; width: 48px; height: 48px;
              border-radius: 50%; color: var(--accent); background: var(--tint); margin-bottom: 24px; }
            .error { --accent: #95502f; --tint: #f3e8df; }
            svg { width: 26px; height: 26px; fill: none; stroke: currentColor; stroke-width: 1.8;
              stroke-linecap: round; stroke-linejoin: round; }
            h1 { font-size: clamp(26px, 4vw, 32px); line-height: 1.3; font-weight: 600;
              letter-spacing: -.025em; margin: 0 0 16px; text-wrap: balance; }
            .detail { color: var(--muted); font-size: 16px; line-height: 1.8; margin: 0; }
            .close { border-top: 1px solid var(--rule); margin-top: 36px; padding-top: 20px;
              color: var(--muted); font-size: 13px; line-height: 1.6; }
            @media (prefers-color-scheme: dark) {
              :root { --paper: #1d211c; --ink: #edf0e7; --muted: #b4bcaf; --accent: #afcea1;
                --tint: #303d2e; --rule: #394035; }
              .error { --accent: #e5b18c; --tint: #423227; }
            }
          </style>
        </head>
        <body><main class="\(accepted ? "accepted" : "error")">
          <p class="brand">\(brand)</p>
          <div class="status" aria-hidden="true"><svg viewBox="0 0 24 24">\(symbol)</svg></div>
          <h1>\(title)</h1>
          <p class="detail">\(detail)</p>
          <p class="close">\(close)</p>
        </main></body>
        </html>
        """
        return "HTTP/1.1 \(accepted ? "200 OK" : "400 Bad Request")\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\n"
            + "Connection: close\r\n\r\n" + body
    }

    func parseCode(fromHTTP request: String) -> String? {
        guard let first = request.split(separator: "\r\n").first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        guard let url = URL(string: "http://localhost\(parts[1])"),
              url.path == "/auth/callback" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else { return nil }
        if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            return nil
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code
    }

    private func finish(code: String) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: code)
    }

    private func finish(error: Error) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}
