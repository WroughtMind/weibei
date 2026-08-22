import Foundation

/// Four protocol families plus explicit uncovered tails.
/// URLs follow Pi 0.82.1 known-provider `baseUrl` strings.
public enum NativeProtocolFamily: String, Sendable {
    case openaiChatCompletions
    case openaiResponses
    case openaiCodexResponses
    case anthropicMessages
    case googleGenerativeAI
    case unsupported
}

public enum NativeProviderAuth: String, Sendable {
    case apiKey
    case oauth
    case apiKeyOrOAuth
    case userBaseURL
    case unsupported
}

public struct NativeProviderRoute: Equatable, Sendable {
    public var family: NativeProtocolFamily
    public var auth: NativeProviderAuth
    public var baseURL: URL?
    public var defaultModel: String
    public var note: String

    public init(
        family: NativeProtocolFamily,
        auth: NativeProviderAuth,
        baseURL: URL? = nil,
        defaultModel: String = "",
        note: String = ""
    ) {
        self.family = family
        self.auth = auth
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.note = note
    }

    public var messagesURL: URL? {
        guard family == .anthropicMessages, let baseURL else { return nil }
        if baseURL.lastPathComponent == "messages" { return baseURL }
        return baseURL.appendingPathComponent("v1/messages")
    }
}

public enum NativeProviderRouting {
    public static func route(_ provider: AgentProviderID) -> NativeProviderRoute {
        switch provider {
        case .openaiCodex:
            return NativeProviderRoute(
                family: .openaiCodexResponses,
                auth: .oauth,
                baseURL: URL(string: "https://chatgpt.com/backend-api/codex"),
                defaultModel: "gpt-5.6-luna",
                note: "ChatGPT 订阅 OAuth + Responses"
            )
        case .anthropic:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKeyOrOAuth,
                baseURL: URL(string: "https://api.anthropic.com"),
                defaultModel: "claude-sonnet-4-5",
                note: "API key 本棒接入；订阅 OAuth 跟 ChatGPT 同模式，按用户指示本棒不真验"
            )
        case .githubCopilot:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .oauth,
                baseURL: URL(string: "https://api.individual.githubcopilot.com"),
                defaultModel: "gpt-4.1",
                note: "Pi 走 Copilot OAuth；原生跟同一模式，本棒不真验"
            )
        case .radius:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .oauth,
                baseURL: URL(string: "https://radius.pi.dev"),
                note: "Pi Radius 网关 OAuth；原生跟同一模式，本棒不真验"
            )
        case .openai:
            return NativeProviderRoute(
                family: .openaiResponses,
                auth: .apiKey,
                baseURL: URL(string: "https://api.openai.com/v1"),
                defaultModel: "gpt-4.1"
            )
        case .xai:
            return NativeProviderRoute(
                family: .openaiResponses,
                auth: .apiKey,
                baseURL: URL(string: "https://api.x.ai/v1"),
                defaultModel: "grok-4"
            )
        case .google:
            return NativeProviderRoute(
                family: .googleGenerativeAI,
                auth: .apiKey,
                baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta"),
                defaultModel: "gemini-2.5-flash"
            )
        case .minimax:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKey,
                baseURL: URL(string: "https://api.minimax.io/anthropic"),
                defaultModel: "MiniMax-M2.5"
            )
        case .minimaxCN:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKey,
                baseURL: URL(string: "https://api.minimaxi.com/anthropic"),
                defaultModel: "MiniMax-M2.5"
            )
        case .vercelAIGateway:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKey,
                baseURL: URL(string: "https://ai-gateway.vercel.sh"),
                defaultModel: "anthropic/claude-sonnet-4"
            )
        case .deepseek:
            return completions("https://api.deepseek.com/v1", model: "deepseek-chat")
        case .antLing:
            return completions("https://api.ant-ling.com/v1")
        case .nvidia:
            return completions("https://integrate.api.nvidia.com/v1")
        case .mistral:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://api.mistral.ai/v1"),
                defaultModel: "mistral-large-latest",
                note: "Pi 用 Mistral Conversations；原生走官方 OpenAI 兼容 /v1"
            )
        case .groq:
            return completions("https://api.groq.com/openai/v1")
        case .cerebras:
            return completions("https://api.cerebras.ai/v1")
        case .openrouter:
            return completions("https://openrouter.ai/api/v1")
        case .qwenTokenPlan:
            return completions("https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1")
        case .qwenTokenPlanCN:
            return completions("https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1")
        case .zai:
            return completions("https://api.z.ai/api/coding/paas/v4")
        case .zaiCodingCN:
            return completions("https://open.bigmodel.cn/api/coding/paas/v4")
        case .opencode:
            return completions("https://opencode.ai/zen/v1")
        case .opencodeGo:
            return completions("https://opencode.ai/zen/go/v1")
        case .huggingface:
            return completions("https://router.huggingface.co/v1")
        case .fireworks:
            return completions("https://api.fireworks.ai/inference/v1")
        case .together:
            return completions("https://api.together.ai/v1")
        case .kimiCoding:
            return completions("https://api.kimi.com/coding")
        case .moonshotai:
            return completions("https://api.moonshot.ai/v1")
        case .moonshotaiCN:
            return completions("https://api.moonshot.cn/v1")
        case .xiaomi:
            return completions("https://api.xiaomimimo.com/v1")
        case .xiaomiTokenPlanCN:
            return completions("https://token-plan-cn.xiaomimimo.com/v1")
        case .xiaomiTokenPlanAMS:
            return completions("https://token-plan-ams.xiaomimimo.com/v1")
        case .xiaomiTokenPlanSGP:
            return completions("https://token-plan-sgp.xiaomimimo.com/v1")
        case .llamaCpp, .custom:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .userBaseURL,
                note: "需要用户填写 Base URL"
            )
        case .azureOpenAI:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "Pi 为 azure-openai-responses 独立族；本棒未覆盖"
            )
        case .googleVertex:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "Pi 为 google-vertex 独立族；本棒未覆盖"
            )
        case .amazonBedrock:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "Pi 为 bedrock-converse-stream 独立族；本棒未覆盖"
            )
        case .cloudflareAIGateway:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "URL 含账号/网关占位，本棒未覆盖"
            )
        case .cloudflareWorkersAI:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "URL 含账号占位，本棒未覆盖"
            )
        }
    }

    public static func resolvedBaseURL(
        provider: AgentProviderID,
        endpoint: AgentProviderEndpoint
    ) -> URL? {
        if let raw = endpoint.baseURL, let url = URL(string: raw) {
            return url
        }
        return route(provider).baseURL
    }

    public static var uncoveredProviders: [AgentProviderID] {
        AgentProviderID.allCases.filter { route($0).family == .unsupported }
    }

    private static func completions(_ url: String, model: String = "") -> NativeProviderRoute {
        NativeProviderRoute(
            family: .openaiChatCompletions,
            auth: .apiKey,
            baseURL: URL(string: url),
            defaultModel: model
        )
    }
}
