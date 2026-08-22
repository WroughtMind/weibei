import Foundation

public enum NativeLLMAdapterFactory {
    public static func make(
        provider: AgentProviderID,
        model: String,
        endpoint: AgentProviderEndpoint
    ) async throws -> NativeLLMAdapter {
        switch provider {
        case .openaiCodex:
            let record = try await NativeOpenAIOAuth.ensureFreshAccessToken()
            guard let token = record.accessToken, !token.isEmpty else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "ChatGPT subscription is not signed in")
            }
            return OpenAIResponsesProvider(
                baseURL: URL(string: "https://chatgpt.com/backend-api/codex")!,
                accessToken: token,
                accountID: record.accountID,
                chatgptBackend: true
            )
        case .openai:
            guard let key = try NativeAgentCredentialStore.apiKey(forProviderID: provider.rawValue) else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing API key")
            }
            return OpenAIResponsesProvider(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                accessToken: key
            )
        case .anthropic:
            guard let key = try NativeAgentCredentialStore.apiKey(forProviderID: provider.rawValue) else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing API key")
            }
            return AnthropicMessagesProvider(apiKey: key)
        case .google:
            guard let key = try NativeAgentCredentialStore.apiKey(forProviderID: provider.rawValue) else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing API key")
            }
            return GoogleGenerativeAIProvider(apiKey: key)
        default:
            guard let baseURL = NativeChatCompletionsRoute.baseURL(provider: provider, endpoint: endpoint) else {
                throw NativeLLMFailure(
                    code: "unsupported_provider",
                    message: "provider \(provider.rawValue) is not on a native protocol family yet"
                )
            }
            guard let key = try NativeAgentCredentialStore.apiKey(forProviderID: provider.rawValue) else {
                throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing API key")
            }
            _ = model
            return OpenAIChatCompletionsProvider(baseURL: baseURL, apiKey: key)
        }
    }
}
