import Foundation

/// How WeiBei should enumerate available models for a given provider.
///
/// Most providers speak the OpenAI-compatible `GET {base}/v1/models` surface; a handful
/// (Anthropic, Gemini, Azure, Bedrock, GitHub Models) need their own adapter. The Codex
/// (ChatGPT subscription) case queries the Codex backend's own `/models` endpoint with
/// the OAuth token + account id; on failure it falls back to a built-in catalog.
public enum ModelListStrategy: Equatable, Sendable {
    /// Standard OpenAI-compatible surface: `GET {base}/v1/models` with `Authorization: Bearer`.
    case openAICompatible(base: String)
    /// Anthropic: `GET api.anthropic.com/v1/models` with `x-api-key` + `anthropic-version`.
    case anthropic
    /// Google Gemini: `GET generativelanguage.googleapis.com/v1beta/models?key=`.
    case gemini
    /// OpenRouter public catalog: `GET openrouter.ai/api/v1/models`, no auth.
    case openRouterPublic
    /// Azure OpenAI data plane: `GET {base}/openai/models?api-version=` with `api-key` header.
    case azureOpenAI(base: String)
    /// Amazon Bedrock: `GET bedrock.{region}.amazonaws.com/foundation-models` with `Authorization: Bearer`.
    case bedrock(region: String)
    /// GitHub Models catalog: `GET api.github.com/models` with `Authorization: Bearer`.
    case gitHubModels
    /// ChatGPT/Codex subscription: `GET chatgpt.com/backend-api/codex/models` with the
    /// OAuth bearer token + `ChatGPT-Account-ID`. The listing is best-effort (upstream
    /// can omit models the subscription can still run), so callers fall back to the
    /// built-in catalog on failure.
    case codexSubscription(token: String, accountID: String)
}

public enum ModelListError: Error, Equatable, Sendable {
    case missingCredential
    case missingBaseURL
    case missingRegion
    case http(status: Int, message: String)
    case transport(String)
    case decoding(String)

    public var localizedDescription: String {
        switch self {
        case .missingCredential: return "Missing API key for model listing."
        case .missingBaseURL: return "Missing base URL for model listing."
        case .missingRegion: return "Missing region for model listing."
        case let .http(status, message): return "HTTP \(status): \(message)"
        case let .transport(message): return "Network error: \(message)"
        case let .decoding(message): return "Decoding error: \(message)"
        }
    }
}

public struct AgentModelListService: Sendable {
    public static let shared = AgentModelListService()

    public init() {}

    /// Resolve a strategy into a concrete list of model ids. Each strategy performs one
    /// authenticated GET and parses the response. Callers handle fallback on error.
    public func fetchModels(strategy: ModelListStrategy, apiKey: String) async throws -> [String] {
        switch strategy {
        case let .openAICompatible(base):
            return try await fetchOpenAICompatible(base: base, apiKey: apiKey)
        case .anthropic:
            return try await fetchAnthropic(apiKey: apiKey)
        case .gemini:
            return try await fetchGemini(apiKey: apiKey)
        case .openRouterPublic:
            return try await fetchOpenRouter()
        case let .azureOpenAI(base):
            return try await fetchAzureOpenAI(base: base, apiKey: apiKey)
        case let .bedrock(region):
            return try await fetchBedrock(region: region, apiKey: apiKey)
        case .gitHubModels:
            return try await fetchGitHubModels(apiKey: apiKey)
        case let .codexSubscription(token, accountID):
            return try await fetchCodexSubscription(token: token, accountID: accountID)
        }
    }

    // MARK: - Strategies

    private func fetchOpenAICompatible(base: String, apiKey: String) async throws -> [String] {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw ModelListError.missingBaseURL }
        guard !apiKey.isEmpty else { throw ModelListError.missingCredential }
        let url = try Self.modelsURL(base: trimmedBase, path: "/v1/models")
        let request = Self.bearerRequest(url: url, apiKey: apiKey)
        return try await extractModelIDs(request: request, dataKey: "data")
    }

    private func fetchAnthropic(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw ModelListError.missingCredential }
        let url = URL(string: "https://api.anthropic.com/v1/models?limit=100")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return try await extractModelIDs(request: request, dataKey: "data")
    }

    private func fetchGemini(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw ModelListError.missingCredential }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=\(Self.urlQueryEscape(apiKey))")!
        let request = URLRequest(url: url)
        return try await extractModelIDs(request: request, dataKey: "models", stripPrefix: "models/")
    }

    private func fetchOpenRouter() async throws -> [String] {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        let request = URLRequest(url: url)
        return try await extractModelIDs(request: request, dataKey: "data")
    }

    private func fetchAzureOpenAI(base: String, apiKey: String) async throws -> [String] {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { throw ModelListError.missingBaseURL }
        guard !apiKey.isEmpty else { throw ModelListError.missingCredential }
        var components = URLComponents(string: trimmedBase.hasSuffix("/") ? trimmedBase : trimmedBase + "/")
        components?.path += "openai/models"
        var queryItems = components?.queryItems ?? []
        queryItems.append(.init(name: "api-version", value: "2024-10-21"))
        components?.queryItems = queryItems
        guard let url = components?.url else { throw ModelListError.missingBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        return try await extractModelIDs(request: request, dataKey: "data")
    }

    private func fetchBedrock(region: String, apiKey: String) async throws -> [String] {
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRegion.isEmpty else { throw ModelListError.missingRegion }
        guard !apiKey.isEmpty else { throw ModelListError.missingCredential }
        guard let url = URL(string: "https://bedrock.\(trimmedRegion).amazonaws.com/foundation-models") else {
            throw ModelListError.missingRegion
        }
        let request = Self.bearerRequest(url: url, apiKey: apiKey)
        // Bedrock returns a top-level array of {modelId, ...}.
        return try await extractArrayIDs(request: request, key: "modelId")
    }

    private func fetchGitHubModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw ModelListError.missingCredential }
        let url = URL(string: "https://api.github.com/models?per_page=100")!
        let request = Self.bearerRequest(url: url, apiKey: apiKey)
        // GitHub Models returns top-level array of {id, ...}.
        return try await extractArrayIDs(request: request, key: "id")
    }

    /// ChatGPT/Codex subscription catalog. Mirrors the Codex backend's own model
    /// listing (`chatgpt.com/backend-api/codex/models`), authenticated with the OAuth
    /// token + ChatGPT-Account-ID. Verified against the openai-api-server-via-codex
    /// reference implementation. Listing is best-effort: callers fall back to the
    /// built-in catalog on any failure.
    private func fetchCodexSubscription(token: String, accountID: String) async throws -> [String] {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccount = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw ModelListError.missingCredential }
        guard let url = URL(string: "https://chatgpt.com/backend-api/codex/models?client_version=1.0.0") else {
            throw ModelListError.transport("invalid codex models url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("weibei", forHTTPHeaderField: "originator")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !trimmedAccount.isEmpty {
            request.setValue(trimmedAccount, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        let data = try await perform(request: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [Any] else {
            throw ModelListError.decoding("missing models array")
        }
        // Match the reference filter: only models the backend reports as API-supported
        // and visible. `slug` is the id callers pass to model=.
        let ids = models.compactMap { entry -> String? in
            guard let dict = entry as? [String: Any],
                  let slug = dict["slug"] as? String,
                  (dict["supported_in_api"] as? Bool) == true,
                  (dict["visibility"] as? String) == "list" else { return nil }
            return slug
        }
        guard !ids.isEmpty else { throw ModelListError.decoding("no supported models") }
        return ids
    }


    // MARK: - Parsing helpers

    private func extractModelIDs(
        request: URLRequest,
        dataKey: String,
        stripPrefix: String? = nil
    ) async throws -> [String] {
        let data = try await perform(request: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object[dataKey] else {
            throw ModelListError.decoding("missing data array")
        }
        return Self.coerceModelIDs(raw, stripPrefix: stripPrefix)
    }

    private func extractArrayIDs(request: URLRequest, key: String) async throws -> [String] {
        let data = try await perform(request: request)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ModelListError.decoding("missing array root")
        }
        return array.compactMap { item in
            (item as? [String: Any])?[key] as? String
        }
    }

    private func perform(request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw ModelListError.http(status: http.statusCode, message: message)
            }
            return data
        } catch let error as ModelListError {
            throw error
        } catch is CancellationError {
            throw ModelListError.transport("cancelled")
        } catch {
            throw ModelListError.transport(error.localizedDescription)
        }
    }

    // MARK: - URL / request builders

    private static func bearerRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func modelsURL(base: String, path: String) throws -> URL {
        let normalized = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        guard let url = URL(string: trimmed + path) else {
            throw ModelListError.missingBaseURL
        }
        return url
    }

    private static func urlQueryEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func coerceModelIDs(_ raw: Any?, stripPrefix: String?) -> [String] {
        let ids: [String]
        if let array = raw as? [Any] {
            ids = array.compactMap { ($0 as? [String: Any])?["id"] as? String }
        } else if let strings = raw as? [String] {
            ids = strings
        } else {
            return []
        }
        if let prefix = stripPrefix {
            return ids.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }
        }
        return ids
    }

    // MARK: - Built-in fallback catalog (Codex subscription)

    /// Fallback only — used when the Codex `/models` endpoint is unreachable or returns
    /// nothing. The live endpoint (`codexSubscription` strategy) is the primary source.
    ///
    /// Aligned with the openai-api-server-via-codex reference DEFAULT_MODELS (a known-good
    /// cross-version baseline). This WILL go stale as OpenAI ships families; the live
    /// listing is what keeps the picker accurate.
    public static let codexSubscriptionModels: [String] = [
        "gpt-5.1",
        "gpt-5.1-codex-max",
        "gpt-5.1-codex-mini",
        "gpt-5.2",
        "gpt-5.2-codex",
        "gpt-5.3-codex",
        "gpt-5.3-codex-spark",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.5",
    ]

    /// Recommended default for a fresh Codex subscription. Matches the reference default.
    public static let codexDefaultModel = "gpt-5.4"
}
