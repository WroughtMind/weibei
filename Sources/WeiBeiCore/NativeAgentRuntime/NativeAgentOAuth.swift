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
        request.timeoutInterval = 60
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
        openURL: @MainActor (URL) -> Void,
        session: URLSession = .shared
    ) async throws -> NativeAgentCredentialRecord {
        let pkce = makePKCE()
        let state = base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        CallbackWaiter.releasePreviousResultPage()
        let port = try bindAvailablePort()
        let redirectURI = "http://localhost:\(port)/auth/callback"
        let url = authorizeURL(redirectURI: redirectURI, pkce: pkce, state: state)
        let page = try OAuthResultPage(language: language)
        let waiter = CallbackWaiter(expectedState: state, page: page)
        try waiter.listen(port: port)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                await openURL(url)
                let code = try await waiter.waitForCode()
                try Task.checkCancellation()
                let record: NativeAgentCredentialRecord
                do {
                    record = try await exchangeCode(code: code, redirectURI: redirectURI, pkce: pkce, session: session)
                    try Task.checkCancellation()
                } catch {
                    waiter.complete(Task.isCancelled ? .cancelled : .failed)
                    throw error
                }
                do {
                    try store.upsert(record)
                } catch {
                    waiter.complete(.saveFailed)
                    throw error
                }
                waiter.complete(.success)
                return record
            } catch {
                if Task.isCancelled { waiter.cancel() }
                throw error
            }
        } onCancel: {
            waiter.cancel()
        }
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

enum OAuthPageState: String, CaseIterable {
    case working, success, cancelled, invalid, expired, failed, saveFailed, disconnected, slow
}

struct OAuthResultPage {
    let language: WeiBeiInterfaceLanguage
    let providerName: String
    let template: String
    let images: [String: String]
    let font: String

    init(language: WeiBeiInterfaceLanguage, provider: AgentProviderID = .openaiCodex) throws {
        self.language = language
        providerName = provider == .openaiCodex ? "ChatGPT" : provider.label(language: language)
        let root = try AgentResources.bundled().rootURL.appendingPathComponent("oauth")
        template = try String(contentsOf: root.appendingPathComponent("page.html"), encoding: .utf8)
        font = try Data(contentsOf: root.appendingPathComponent("WeiBeiStele.ttf")).base64EncodedString()
        images = try Dictionary(uniqueKeysWithValues: ["working", "success", "problem", "cancelled"].map {
            ($0, "data:image/\($0 == "success" ? "png" : "webp");base64," + (try Data(contentsOf: root.appendingPathComponent("\($0).\($0 == "success" ? "png" : "webp")"))).base64EncodedString())
        })
    }

    func copy(_ state: OAuthPageState) -> [String: String] {
        let t = language.text
        let title: String, detail: String, label: String, art: String
        switch state {
        case .working, .slow:
            title = t("授权已到，稍等片刻。", "One moment. Almost there.")
            detail = t("Webi 正在等登录结果。魏碑正在完成验证并保存登录信息。", "Webi is waiting with you while WeiBei verifies and saves your sign-in.")
            label = t("正在完成登录", "FINISHING SIGN-IN"); art = "working"
        case .success:
            title = t("接好了，回魏碑吧。", "All set. Back to WeiBei.")
            detail = t("\(providerName) 已连接，登录信息已保存。Webi 和小朱在魏碑等你。", "\(providerName) is connected and your sign-in is saved. Webi and Little Zhu will see you in WeiBei.")
            label = t("登录成功", "SIGNED IN"); art = "success"
        case .cancelled:
            title = t("这次先不连，也没关系。", "No rush. Maybe later.")
            detail = t("本次登录已取消。想继续时，可以在魏碑里重新发起登录。", "This sign-in was cancelled. You can start again from WeiBei whenever you are ready.")
            label = t("已取消登录", "SIGN-IN CANCELLED"); art = "cancelled"
        case .invalid:
            title = t("这份授权，对不上。", "This authorization does not match.")
            detail = t("这个页面不属于当前登录，或授权内容不完整。请回到魏碑，从当前登录入口继续。", "This page does not match the current sign-in, or its authorization is incomplete. Return to the current sign-in in WeiBei.")
            label = t("授权未通过校验", "AUTHORIZATION NOT VERIFIED"); art = "problem"
        case .expired:
            title = t("等得有点久，重新来吧。", "Time to start again.")
            detail = t("这次登录已超时。请返回魏碑重新登录，不要重复使用旧的授权页面。", "This sign-in has timed out. Start again from WeiBei rather than reusing this authorization page.")
            label = t("登录已过期", "SIGN-IN EXPIRED"); art = "problem"
        case .failed:
            title = t("还差一步，没连上。", "Not connected just yet.")
            detail = t("魏碑未能完成 \(providerName) 验证。请返回应用查看错误，检查网络后重新登录。", "WeiBei could not complete \(providerName) verification. Check the error in the app and your connection, then sign in again.")
            label = t("登录未完成", "SIGN-IN INCOMPLETE"); art = "problem"
        case .saveFailed:
            title = t("验证到了，没能存好。", "Verified, but not saved.")
            detail = t("登录信息未能保存，暂时不能确认连接成功。请回到魏碑查看错误并重试。", "Your sign-in could not be saved, so the connection is not confirmed. Return to WeiBei to check the error and try again.")
            label = t("保存登录信息失败", "SIGN-IN NOT SAVED"); art = "problem"
        case .disconnected:
            title = t("结果要回魏碑看一下。", "Check the result in WeiBei.")
            detail = t("此页面已无法取得应用状态，不能确认登录是否完成。请返回魏碑查看；如已退出应用，请重新打开。", "This page can no longer reach the app, so sign-in cannot be confirmed here. Check WeiBei, or reopen it if it was closed.")
            label = t("无法取得登录结果", "STATUS UNAVAILABLE"); art = "problem"
        }
        return ["title": title, "detail": detail, "label": label, "art": art,
                "next": state == .working || state == .slow
                    ? t("请稍候，也可以返回魏碑查看进度。", "Please wait, or check progress in WeiBei.")
                    : t("返回魏碑，继续你的学习。", "Return to WeiBei to continue."),
                "hint": state == .slow
                    ? t("验证比平时慢，请在魏碑中查看进度。", "This is taking longer than usual. Check progress in WeiBei.")
                    : t("此页面可以关闭，不会中断应用中的操作。", "Closing this page will not interrupt the app.")]
    }

    func html(state: OAuthPageState, statusURL: String? = nil) -> String {
        let content = copy(state)
        func json(_ value: Any) -> String {
            String(data: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]), encoding: .utf8)!
        }
        let states = Dictionary(uniqueKeysWithValues: OAuthPageState.allCases.map { ($0.rawValue, copy($0)) })
        let replacements: [String: String] = [
            "LANG": language.rawValue, "FONT": font, "IMAGE": images[content["art"]!]!,
            "STATE": state.rawValue, "STATES": json(states), "IMAGES": json(images),
            "STATUS_URL": json(statusURL as Any? ?? NSNull()),
            "TITLE": content["title"]!, "DETAIL": content["detail"]!, "LABEL": content["label"]!,
            "NEXT": content["next"]!, "HINT": content["hint"]!,
            "CONTEXT": language.text("\(providerName) · 账号连接", "\(providerName) · Account connection"),
            "COMPANION": language.text("小朱", "LITTLE ZHU"),
            "PRIVACY": language.text("登录信息只交给魏碑，此页不展示账号或凭据。", "Sign-in details go to WeiBei. No account details or credentials are displayed here."),
            "SIGNATURE": language.text("把知识，留在自己手里。", "Keep knowledge in your hands.")
        ]
        return replacements.reduce(template) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }
}

final class CallbackWaiter: @unchecked Sendable {
    private static let activeLock = NSLock()
    private static var active: CallbackWaiter?
    private let stopped = DispatchSemaphore(value: 0)
    private var shouldStop = false

    static func releasePreviousResultPage() {
        activeLock.lock()
        let previous = active
        activeLock.unlock()
        guard let previous, previous.snapshot().1 != nil else { return }
        previous.lock.lock()
        previous.shouldStop = true
        previous.lock.unlock()
        shutdown(previous.listenFD, SHUT_RDWR)
        _ = previous.stopped.wait(timeout: .now() + 3)
    }

    private let expectedState: String
    private let page: OAuthResultPage?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var codeResult: Result<String, Error>?
    private var pageState: OAuthPageState = .working
    private var terminalAt: Date?
    private var listenFD: Int32 = -1
    private(set) var boundPort: UInt16 = 0
    private let resultOnly: Bool

    init(expectedState: String, page: OAuthResultPage? = nil, resultOnly: Bool = false) {
        self.resultOnly = resultOnly
        self.expectedState = expectedState
        self.page = page
    }

    func listen(port: UInt16) throws {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NativeLLMFailure(code: "oauth_port", message: "could not open callback socket") }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, Darwin.listen(fd, 8) == 0 else {
            close(fd)
            throw NativeLLMFailure(code: "oauth_port", message: "could not listen on localhost:\(port)")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { close(fd); throw NativeLLMFailure(code: "oauth_port", message: "could not read callback port") }
        boundPort = UInt16(bigEndian: addr.sin_port)
        listenFD = fd
        Self.activeLock.lock()
        Self.active = self
        Self.activeLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { self.acceptLoop() }
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { pending in
            lock.lock()
            if let result = codeResult {
                lock.unlock()
                pending.resume(with: result)
            } else {
                continuation = pending
                lock.unlock()
            }
        }
    }

    func complete(_ state: OAuthPageState) {
        lock.lock()
        // A completed disk write is authoritative, even if cancellation arrived during that write.
        if pageState == .working || state == .success {
            pageState = state
            terminalAt = Date()
        }
        lock.unlock()
    }

    func cancel() {
        complete(.cancelled)
        finish(.failure(CancellationError()))
    }

    private func snapshot() -> (OAuthPageState, Date?) {
        lock.lock(); defer { lock.unlock() }
        return (pageState, terminalAt)
    }

    private var hasAuthorizationCode: Bool {
        lock.lock(); defer { lock.unlock() }
        if case .success = codeResult { return true }
        return false
    }

    private func acceptLoop() {
        defer {
            close(listenFD)
            Self.activeLock.lock()
            if Self.active === self { Self.active = nil }
            Self.activeLock.unlock()
            stopped.signal()
        }
        let deadline = Date().addingTimeInterval(300)
        while true {
            lock.lock()
            let stop = shouldStop
            lock.unlock()
            if stop { return }
            let (_, finishedAt) = snapshot()
            // Keep the result available for refreshes; the next login retires this listener.
            if let finishedAt, Date().timeIntervalSince(finishedAt) > 300 { return }
            if Date() >= deadline, finishedAt == nil, !hasAuthorizationCode, !resultOnly {
                complete(.expired)
                finish(.failure(NativeLLMFailure(code: "oauth_timeout", message: "browser sign-in timed out")))
            }
            var descriptor = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 200) > 0 else { continue }
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { continue }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            var noPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout<Int32>.size))
            var request = Data()
            var buffer = [UInt8](repeating: 0, count: 2048)
            while request.count < 8192 {
                let count = recv(client, &buffer, min(buffer.count, 8192 - request.count), 0)
                guard count > 0 else { break }
                request.append(contentsOf: buffer.prefix(count))
                if request.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            }
            let response = handle(String(data: request, encoding: .utf8) ?? "")
            let bytes = Array(response.utf8)
            bytes.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = send(client, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { break }
                    offset += count
                }
            }
            close(client)
        }
    }

    func handle(_ request: String) -> String {
        guard let url = requestURL(request) else { return http("", status: "400 Bad Request") }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let matches = items.filter { $0.name == "state" }.map(\.value) == [expectedState]
        if url.path == "/auth/status" {
            guard matches else { return http("{}", status: "403 Forbidden", type: "application/json") }
            return http("{\"state\":\"\(snapshot().0.rawValue)\"}", type: "application/json")
        }
        if url.path == "/auth/result" {
            guard matches, let page else { return http("", status: "403 Forbidden") }
            return http(page.html(state: snapshot().0, statusURL: "/auth/status?state=\(NativeOpenAIOAuth.urlEncode(expectedState))"))
        }
        guard url.path == "/auth/callback", !resultOnly else { return http("", status: "404 Not Found") }
        var state: OAuthPageState
        if !matches {
            state = .invalid
        } else if snapshot().0 != .working || hasAuthorizationCode {
            state = snapshot().0
        } else if let error = items.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            state = error == "access_denied" ? .cancelled : .failed
            complete(state)
            if state == .cancelled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(NativeLLMFailure(code: "oauth_callback", message: "authorization was not granted")))
            }
        } else if let code = parseCode(fromHTTP: request) {
            state = .working
            finish(.success(code))
        } else {
            state = .invalid
        }
        guard let page else { return http("", status: "500 Internal Server Error") }
        let statusURL = state == .working ? "/auth/status?state=\(NativeOpenAIOAuth.urlEncode(expectedState))" : nil
        return http(page.html(state: state, statusURL: statusURL), status: state == .invalid ? "400 Bad Request" : "200 OK")
    }

    private func http(_ body: String, status: String = "200 OK", type: String = "text/html") -> String {
        "HTTP/1.1 \(status)\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\n"
        + "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n" + body
    }

    private func requestURL(_ request: String) -> URL? {
        guard let first = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/") else { return nil }
        return URL(string: "http://localhost\(parts[1])")
    }

    func parseCode(fromHTTP request: String) -> String? {
        guard let url = requestURL(request), url.path == "/auth/callback" else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.filter({ $0.name == "state" }).map(\.value) == [expectedState],
              !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard codeResult == nil else { lock.unlock(); return }
        codeResult = result
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
