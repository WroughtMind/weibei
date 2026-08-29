import Foundation

/// GitHub Copilot speaks OpenAI Chat Completions. Individual accounts hit
/// `api.individual.githubcopilot.com`; enterprise tokens may name a proxy host.
///
/// WeiBei has no GitHub OAuth app. The user pastes a GitHub token or an already
/// minted Copilot session token. A GitHub token may be exchanged for a Copilot
/// token; if that endpoint 404s (typical for individual accounts), the original
/// token is sent to the individual host.
public enum NativeCopilotSession {
    public static let individualBaseURL = URL(string: "https://api.individual.githubcopilot.com")!

    public static let requestHeaders: [String: String] = [
        "User-Agent": "GitHubCopilotChat/0.35.0",
        "Editor-Version": "vscode/1.107.0",
        "Editor-Plugin-Version": "copilot-chat/0.35.0",
        "Copilot-Integration-Id": "vscode-chat",
        "Openai-Intent": "conversation-agent",
    ]

    public struct Resolved: Equatable, Sendable {
        public var token: String
        public var baseURL: URL
    }

    public static func resolved(githubToken: String, exchangeJSON: [String: Any]?) -> Resolved {
        let trimmed = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = exchangeJSON else {
            return Resolved(token: trimmed, baseURL: individualBaseURL)
        }
        let exchanged = (json["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = exchanged.isEmpty ? trimmed : exchanged
        if let endpoints = json["endpoints"] as? [String: Any],
           let api = endpoints["api"] as? String,
           let url = urlFromHostOrURL(api) {
            return Resolved(token: token, baseURL: url)
        }
        if let proxy = json["proxy-ep"] as? String, let url = urlFromHostOrURL(proxy) {
            return Resolved(token: token, baseURL: url)
        }
        return Resolved(token: token, baseURL: individualBaseURL)
    }

    public static func resolve(githubToken: String, session: URLSession = .shared) async -> Resolved {
        let trimmed = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if let json = try? await exchange(trimmed, session: session) {
            return resolved(githubToken: trimmed, exchangeJSON: json)
        }
        return Resolved(token: trimmed, baseURL: individualBaseURL)
    }

    public static func applyRequestHeaders(to request: inout URLRequest) {
        for (name, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func exchange(_ githubToken: String, session: URLSession) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/v2/token")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        applyRequestHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NativeLLMFailure(code: "unauthorized", status: (response as? HTTPURLResponse)?.statusCode, message: "copilot token exchange failed")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeLLMFailure(code: "invalid_response", message: "copilot token exchange was not an object")
        }
        return json
    }

    private static func urlFromHostOrURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }
}
