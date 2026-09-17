import Foundation
import CoreFoundation

/// Account authorization for providers already supported by the native model adapters.
/// Protocol references: xAI/Pi device authorization, MoonshotAI/kimi-cli oauth.py,
/// and openrouter.ai/docs/guides/overview/auth/oauth. No CLI identity headers are sent.
public enum NativeProviderOAuth {
    public static func supports(_ provider: AgentProviderID) -> Bool {
        [.openaiCodex, .xai, .kimiCoding, .openrouter].contains(provider)
    }

    struct DeviceConfiguration {
        let clientID: String
        let authorizationURL: String
        let tokenURL: String
        let fields: [String: String]
        let domains: [String]
    }

    static func deviceConfiguration(_ provider: AgentProviderID) throws -> DeviceConfiguration {
        switch provider {
        case .xai:
            return DeviceConfiguration(clientID: "b1a00492-073a-47ea-816f-4c329264a828",
                authorizationURL: "https://auth.x.ai/oauth2/device/code", tokenURL: "https://auth.x.ai/oauth2/token",
                fields: ["scope": "openid profile email offline_access grok-cli:access api:access", "referrer": "weibei"],
                domains: ["x.ai", "grok.com"])
        case .kimiCoding:
            return DeviceConfiguration(clientID: "17e5f671-d194-4dfb-9706-5516cb48c098",
                authorizationURL: "https://auth.kimi.com/api/oauth/device_authorization", tokenURL: "https://auth.kimi.com/api/oauth/token",
                fields: [:], domains: ["kimi.com"])
        default: throw failure("unsupported_provider")
        }
    }

    public static func login(
        provider: AgentProviderID, store: NativeAgentCredentialStore,
        language: WeiBeiInterfaceLanguage, openURL: @MainActor (URL) -> Void,
        deviceCode: @MainActor (String, URL) -> Void,
        session: URLSession = networkSession
    ) async throws -> NativeAgentCredentialRecord {
        if provider == .openaiCodex {
            return try await NativeOpenAIOAuth.loginWithBrowser(store: store, language: language, openURL: openURL, session: session)
        }
        guard supports(provider) else { throw failure("unsupported_provider") }
        CallbackWaiter.releasePreviousResultPage()
        let state = NativeOpenAIOAuth.makePKCE().verifier
        let waiter = CallbackWaiter(expectedState: state, page: try OAuthResultPage(language: language, provider: provider), resultOnly: provider != .openrouter)
        try waiter.listen(port: 0)
        let root = "http://127.0.0.1:\(waiter.boundPort)"
        let resultURL = URL(string: "\(root)/auth/result?state=\(state)")!
        return try await withTaskCancellationHandler {
            var resultOpened = false
            do {
                try Task.checkCancellation()
                let record: NativeAgentCredentialRecord
                if provider == .openrouter {
                    let pkce = NativeOpenAIOAuth.makePKCE()
                    var url = URLComponents(string: "https://openrouter.ai/auth")!
                    url.queryItems = [
                        URLQueryItem(name: "callback_url", value: "\(root)/auth/callback?state=\(state)"),
                        URLQueryItem(name: "code_challenge", value: pkce.challenge),
                        URLQueryItem(name: "code_challenge_method", value: "S256"),
                        URLQueryItem(name: "key_label", value: "WeiBei")
                    ]
                    await openURL(url.url!)
                    let code = try await waiter.waitForCode()
                    record = try await exchangeOpenRouter(code: code, verifier: pkce.verifier, session: session)
                } else {
                    record = try await authorizeDevice(provider: provider, session: session) { code, url in
                        deviceCode(code, url)
                        openURL(url)
                    }
                    await openURL(resultURL)
                    resultOpened = true
                }
                try Task.checkCancellation()
                try await validate(record, provider: provider, session: session)
                try Task.checkCancellation()
                do { try store.upsert(record) }
                catch { waiter.complete(.saveFailed); throw error }
                waiter.complete(.success)
                return record
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                waiter.complete(cancelled ? .cancelled : (error as? NativeLLMFailure)?.code == "oauth_timeout" ? .expired : .failed)
                if provider != .openrouter && !Task.isCancelled && !resultOpened { await openURL(resultURL) }
                if cancelled { throw CancellationError() }
                throw error
            }
        } onCancel: { waiter.cancel() }
    }

    static func authorizeDevice(
        provider: AgentProviderID, session: URLSession,
        sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        show: @MainActor (String, URL) -> Void
    ) async throws -> NativeAgentCredentialRecord {
        let config = try deviceConfiguration(provider)
        var fields = config.fields
        fields["client_id"] = config.clientID
        let device = try await request(config.authorizationURL, fields: fields, session: session)
        let privateCode = try string(device, "device_code")
        let userCode = try string(device, "user_code")
        guard userCode.count <= 64 else { throw failure("invalid_response") }
        let verification = try verificationURL(try string(device, "verification_uri_complete", alternative: device["verification_uri"] as? String), domains: config.domains)
        let lifetime = try positiveNumber(device, "expires_in")
        let deadline = Date().addingTimeInterval(lifetime)
        var interval = device["interval"] == nil ? 5 : try positiveNumber(device, "interval")
        guard interval <= lifetime else { throw failure("invalid_response") }
        await show(userCode, verification)
        while Date() < deadline {
            try await sleep(min(interval, max(0, deadline.timeIntervalSinceNow)))
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            let token = try await request(config.tokenURL, fields: [
                "client_id": config.clientID, "device_code": privateCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ], session: session, allowsPending: true)
            switch token["error"] as? String {
            case "authorization_pending": continue
            case "slow_down":
                interval += 5
                if token["interval"] != nil { interval = max(interval, try positiveNumber(token, "interval")) }
                continue
            case "access_denied", "authorization_denied": throw CancellationError()
            case "expired_token": throw failure("oauth_timeout")
            case nil: return try tokenRecord(token, provider: provider)
            default: throw failure("unauthorized", status: 401)
            }
        }
        throw failure("oauth_timeout")
    }

    static func exchangeOpenRouter(code: String, verifier: String, session: URLSession) async throws -> NativeAgentCredentialRecord {
        let json = try await request("https://openrouter.ai/api/v1/auth/keys", fields: [
            "code": code, "code_verifier": verifier, "code_challenge_method": "S256"
        ], json: true, session: session)
        return NativeAgentCredentialRecord(provider: AgentProviderID.openrouter.credentialProviderID,
            accessToken: try string(json, "key"))
    }

    static func validate(_ record: NativeAgentCredentialRecord, provider: AgentProviderID, session: URLSession) async throws {
        let base = NativeProviderRouting.route(provider).baseURL!
        let url = provider == .openrouter ? base.appendingPathComponent("key") : base.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(record.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let json = try responseJSON(data, response: response)
        if provider == .openrouter {
            guard json["data"] is [String: Any] else { throw failure("invalid_response") }
        } else {
            guard let models = json["data"] as? [[String: Any]], models.contains(where: { ($0["id"] as? String)?.isEmpty == false }) else {
                throw failure("oauth_http", status: 403)
            }
        }
    }

    static func tokenRecord(_ json: [String: Any], provider: AgentProviderID, previousRefresh: String? = nil) throws -> NativeAgentCredentialRecord {
        let seconds = try positiveNumber(json, "expires_in")
        return NativeAgentCredentialRecord(provider: provider.credentialProviderID,
            accessToken: try string(json, "access_token"),
            refreshToken: try string(json, "refresh_token", alternative: previousRefresh),
            expiresAt: Date().addingTimeInterval(seconds))
    }

    /// All native callers resolve the same persisted record; rotating tokens are refreshed once.
    public static func credential(provider: AgentProviderID, store: NativeAgentCredentialStore, session: URLSession = networkSession) async throws -> NativeAgentCredentialRecord? {
        try await refreshCoordinator.credential(provider: provider, store: store, session: session)
    }
    private static let refreshCoordinator = RefreshCoordinator()
    private actor RefreshCoordinator {
        private var pending: [String: Task<NativeAgentCredentialRecord, Error>] = [:]
        func credential(provider: AgentProviderID, store: NativeAgentCredentialStore, session: URLSession) async throws -> NativeAgentCredentialRecord? {
            guard let record = try store.load()[provider.credentialProviderID] else { return nil }
            guard record.apiKey == nil, record.accessToken != nil,
                  provider == .xai || provider == .kimiCoding else { return record }
            if let expiry = record.expiresAt, expiry.timeIntervalSinceNow > 120 { return record }
            let key = store.fileURL.path + ":" + provider.rawValue
            if let task = pending[key] { return try await task.value }
            let task = Task {
                let config = try deviceConfiguration(provider)
                guard let token = record.refreshToken, !token.isEmpty else { throw failure("unauthorized", status: 401) }
                let json = try await request(config.tokenURL, fields: ["client_id": config.clientID,
                    "grant_type": "refresh_token", "refresh_token": token], session: session)
                let next = try tokenRecord(json, provider: provider, previousRefresh: token)
                // A logout or replacement during refresh must never restore the old account.
                guard try store.load()[provider.credentialProviderID] == record else { throw CancellationError() }
                try store.upsert(next)
                return next
            }
            pending[key] = task
            defer { pending[key] = nil }
            return try await task.value
        }
    }

    static func verificationURL(_ value: String, domains: [String]) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { throw failure("invalid_response") }
        return url
    }
    static func string(_ json: [String: Any], _ key: String, alternative: String? = nil) throws -> String {
        guard let value = (json[key] as? String) ?? alternative, !value.isEmpty, value.utf8.count <= 16_384,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw failure("invalid_response") }
        return value
    }
    static func positiveNumber(_ json: [String: Any], _ key: String) throws -> Double {
        guard let value = json[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue > 0, value.doubleValue <= 31_536_000 else { throw failure("invalid_response") }
        return value.doubleValue
    }
    static func request(_ url: String, fields: [String: String], json: Bool = false, session: URLSession, allowsPending: Bool = false) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WeiBei", forHTTPHeaderField: "User-Agent")
        request.setValue(json ? "application/json" : "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = json ? try JSONSerialization.data(withJSONObject: fields)
            : Data(fields.sorted(by: { $0.key < $1.key }).map { NativeOpenAIOAuth.urlEncode($0.key) + "=" + NativeOpenAIOAuth.urlEncode($0.value) }.joined(separator: "&").utf8)
        let (data, response) = try await session.data(for: request)
        return try responseJSON(data, response: response, allowsPending: allowsPending)
    }
    static func responseJSON(_ data: Data, response: URLResponse, allowsPending: Bool = false) throws -> [String: Any] {
        guard let http = response as? HTTPURLResponse else { throw failure("invalid_response") }
        guard data.count <= 1_048_576 else { throw failure("invalid_response") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = json?["error"] as? String
        if allowsPending, [200, 400].contains(http.statusCode), let error,
           ["authorization_pending", "slow_down", "access_denied", "authorization_denied", "expired_token"].contains(error) { return json! }
        if error == "invalid_grant" || error == "invalid_token" { throw failure("unauthorized", status: 401) }
        guard (200..<300).contains(http.statusCode), json?["error"] == nil else {
            throw failure(http.statusCode == 401 ? "unauthorized" : "oauth_http", status: http.statusCode)
        }
        guard let json else { throw failure("invalid_response") }
        return json
    }
    static func failure(_ code: String, status: Int? = nil) -> NativeLLMFailure {
        NativeLLMFailure(code: code, status: status, message: "Account authorization did not complete (\(code)).")
    }
    // Token requests never follow redirects to another credential recipient.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    public static let networkSession = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
}
