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
        try store.load()[provider] != nil
    }

    /// Browser login: local callback on 1455/1457, then token exchange. Does not log secrets.
    public static func loginWithBrowser(
        store: NativeAgentCredentialStore,
        openURL: (URL) -> Void,
        session: URLSession = .shared
    ) async throws -> NativeAgentCredentialRecord {
        let pkce = makePKCE()
        let state = base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        let port = try bindAvailablePort()
        let redirectURI = "http://localhost:\(port)/auth/callback"
        let url = authorizeURL(redirectURI: redirectURI, pkce: pkce, state: state)
        let waiter = CallbackWaiter(expectedState: state)
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
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var listenFD: Int32 = -1

    init(expectedState: String) {
        self.expectedState = expectedState
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
        let html = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Connection: close\r
        \r
        <html><body><p>魏碑已收到 ChatGPT 登录。可以关闭此页。</p></body></html>
        """
        _ = html.withCString { pointer in
            send(clientFD, pointer, strlen(pointer), 0)
        }
        if let code = parseCode(fromHTTP: raw) {
            finish(code: code)
        } else {
            finish(error: NativeLLMFailure(code: "oauth_callback", message: "callback missing authorization code"))
        }
    }

    func parseCode(fromHTTP request: String) -> String? {
        guard let first = request.split(separator: "\r\n").first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        guard let url = URL(string: "http://localhost\(parts[1])") else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else { return nil }
        if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            return nil
        }
        return items.first(where: { $0.name == "code" })?.value
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
