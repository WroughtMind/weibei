import Foundation

public enum NativeLLMAdapterFactory {
    public static func make(
        provider: AgentProviderID,
        model: String,
        endpoint: AgentProviderEndpoint,
        authMethod: AgentAuthMethod? = nil,
        credentialStore: NativeAgentCredentialStore? = nil
    ) async throws -> NativeLLMAdapter {
        let route = NativeProviderRouting.route(provider)
        let baseURL = NativeProviderRouting.resolvedBaseURL(provider: provider, endpoint: endpoint)
        switch route.family {
        case .openaiCodexResponses:
            let record = try await NativeOpenAIOAuth.ensureFreshAccessToken()
            guard let token = record.accessToken, !token.isEmpty else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "ChatGPT subscription is not signed in")
            }
            var contextWindow: Int?
            if baseURL == URL(string: "https://chatgpt.com/backend-api/codex") {
                do {
                    contextWindow = try await AgentModelListService.shared.codexContextWindow(
                        model: model, token: token, accountID: record.accountID ?? ""
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    WeiBeiLog.workspace.error("code=agent_model_context_unknown")
                }
            }
            return OpenAIResponsesProvider(
                baseURL: baseURL ?? URL(string: "https://chatgpt.com/backend-api/codex")!,
                accessToken: token,
                accountID: record.accountID,
                chatgptBackend: true,
                webSearchSupported: route.webSearch == .responsesTool,
                contextWindow: contextWindow
            )
        case .openaiResponses:
            guard let key = try await credential(provider: provider, endpoint: endpoint, authMethod: authMethod, store: credentialStore) else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing API key")
            }
            guard let baseURL else {
                throw NativeLLMFailure(code: "unsupported_provider", message: "missing Responses base URL for \(provider.rawValue)")
            }
            let responsesRoot = provider == .azureOpenAI
                ? NativeProviderRouting.azureResponsesRoot(baseURL)
                : baseURL
            return OpenAIResponsesProvider(
                baseURL: responsesRoot,
                accessToken: key,
                usesAzureAPIKey: provider == .azureOpenAI,
                webSearchSupported: provider != .azureOpenAI && route.webSearch == .responsesTool,
                session: provider == .xai ? NativeProviderOAuth.networkSession : .shared
            )
        case .anthropicMessages:
            guard let key = try await credential(provider: provider, endpoint: endpoint, authMethod: authMethod, store: credentialStore) else {
                throw NativeLLMFailure(
                    code: "unauthorized",
                    status: 401,
                    message: route.auth == .oauth
                        ? "\(provider.rawValue) subscription is not signed in"
                        : "missing API key"
                )
            }
            let messagesURL = route.messagesURL
                ?? baseURL?.appendingPathComponent("v1/messages")
                ?? URL(string: "https://api.anthropic.com/v1/messages")!
            return AnthropicMessagesProvider(
                apiKey: key,
                apiURL: messagesURL,
                webSearchTool: route.webSearch == .anthropicTool
            )
        case .googleGenerativeAI:
            guard let key = try await credential(provider: provider, endpoint: endpoint, authMethod: authMethod, store: credentialStore) else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing API key")
            }
            guard let rootURL = baseURL else {
                throw NativeLLMFailure(
                    code: "unsupported_provider",
                    message: route.auth == .userBaseURL
                        ? "provider \(provider.rawValue) needs a Base URL"
                        : "missing Gemini base URL for \(provider.rawValue)"
                )
            }
            return GoogleGenerativeAIProvider(
                apiKey: key,
                rootURL: rootURL,
                groundingSearch: route.webSearch == .googleGrounding
            )
        case .openaiChatCompletions:
            guard let baseURL else {
                throw NativeLLMFailure(
                    code: "unsupported_provider",
                    message: route.auth == .userBaseURL
                        ? "provider \(provider.rawValue) needs a Base URL"
                        : "provider \(provider.rawValue) is missing a chat-completions base URL"
                )
            }
            guard let key = try await credential(provider: provider, endpoint: endpoint, authMethod: authMethod, store: credentialStore) else {
                throw NativeLLMFailure(
                    code: "unauthorized",
                    status: 401,
                    message: route.auth == .oauth
                        ? "\(provider.rawValue) subscription is not signed in"
                        : "missing API key"
                )
            }
            let chatStyle: ChatWebSearchStyle
            switch route.webSearch {
            case .zaiChatTool: chatStyle = .zai
            case .xiaomiChatTool: chatStyle = .xiaomi
            case .qwenEnableSearch: chatStyle = .qwen
            case .openrouterPlugin: chatStyle = .openrouter
            case .kimiBuiltin: chatStyle = .kimi
            default: chatStyle = .none
            }
            var chatBase = baseURL
            var chatKey = key
            var extraHeaders: [String: String] = [:]
            if provider == .githubCopilot {
                let session = await NativeCopilotSession.resolve(githubToken: key)
                chatBase = session.baseURL
                chatKey = session.token
                extraHeaders = NativeCopilotSession.requestHeaders
            }
            return OpenAIChatCompletionsProvider(
                baseURL: chatBase,
                apiKey: chatKey,
                extraHeaders: extraHeaders,
                webSearchStyle: chatStyle,
                includesStreamUsage: provider == .amazonBedrock
                    && model.caseInsensitiveCompare("amazon.nova-lite-v1:0") == .orderedSame
                    && NativeProviderRouting.contextWindow(provider: provider, model: model) != nil,
                session: provider == .kimiCoding || provider == .openrouter ? NativeProviderOAuth.networkSession : .shared
            )
        case .unsupported:
            throw NativeLLMFailure(
                code: "unsupported_provider",
                message: route.note.isEmpty
                    ? "provider \(provider.rawValue) is not on a native protocol family yet"
                    : route.note
            )
        }
    }
    private static func credential(provider: AgentProviderID, endpoint: AgentProviderEndpoint, authMethod: AgentAuthMethod?, store: NativeAgentCredentialStore?) async throws -> String? {
        if NativeProviderOAuth.supports(provider), provider != .openaiCodex {
            let store = try store ?? NativeAgentCredentialStore.defaultStore()
            if authMethod == .apiKey { return try store.load()[provider.credentialProviderID]?.apiKey }
            let record = try await NativeProviderOAuth.credential(provider: provider, store: store)
            if authMethod != .subscription, let key = record?.apiKey { return key }
            // Account tokens belong only to the provider's built-in endpoint.
            guard endpoint.baseURL == nil else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "Account sign-in requires the provider endpoint")
            }
            return record?.accessToken
        }
        if let store { return try store.load()[endpoint.credentialProviderID]?.apiKey }
        return try NativeAgentCredentialStore.apiKey(forProviderID: endpoint.credentialProviderID)
    }

}
