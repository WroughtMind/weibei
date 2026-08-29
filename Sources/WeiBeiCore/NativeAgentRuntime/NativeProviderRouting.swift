import Foundation

/// Native protocol families plus explicit unsupported providers.
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
    case userBaseURL
    case unsupported
}

/// 各供应商服务端联网搜索的接入形态,决定请求注入与来源解析方式。
public enum NativeWebSearchSupport: String, Sendable {
    case none
    /// Responses 协议内置工具:tools 追加 {"type":"web_search"}。
    case responsesTool
    /// Anthropic Messages 服务端工具:tools 追加 web_search_20250305。
    case anthropicTool
    /// Gemini google_search 接地:tools 追加 {"google_search":{}}。
    case googleGrounding
    /// 智谱系聊天补全 web_search 工具,结果在顶层 web_search 数组。
    case zaiChatTool
    /// 小米系聊天补全 web_search 工具,结果在 annotations。
    case xiaomiChatTool
    /// 通义聊天补全 enable_search 开关,结果在 search_info。
    case qwenEnableSearch
    /// OpenRouter web 插件,结果在 annotations。
    case openrouterPlugin
    /// Kimi 内置 $web_search:模型发起、客户端原样回传参数由服务端执行。
    case kimiBuiltin
}

public struct NativeProviderRoute: Equatable, Sendable {
    public var family: NativeProtocolFamily
    public var auth: NativeProviderAuth
    public var baseURL: URL?
    public var defaultModel: String
    public var note: String
    public var webSearch: NativeWebSearchSupport

    public init(
        family: NativeProtocolFamily,
        auth: NativeProviderAuth,
        baseURL: URL? = nil,
        defaultModel: String = "",
        note: String = "",
        webSearch: NativeWebSearchSupport = .none
    ) {
        self.family = family
        self.auth = auth
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.note = note
        self.webSearch = webSearch
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
                note: "ChatGPT 订阅 OAuth + Responses",
                webSearch: .responsesTool
            )
        case .anthropic:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKey,
                baseURL: URL(string: "https://api.anthropic.com"),
                defaultModel: "claude-sonnet-4-5",
                note: "原生 Messages 协议 + API Key",
                webSearch: .anthropicTool
            )
        case .githubCopilot:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .oauth,
                baseURL: URL(string: "https://api.individual.githubcopilot.com"),
                defaultModel: "gpt-4.1",
                note: "Copilot OAuth 尚未接入"
            )
        case .radius:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .oauth,
                baseURL: URL(string: "https://radius.pi.dev"),
                note: "Radius 网关 OAuth 尚未接入"
            )
        case .openai:
            return NativeProviderRoute(
                family: .openaiResponses,
                auth: .apiKey,
                baseURL: URL(string: "https://api.openai.com/v1"),
                defaultModel: "gpt-4.1",
                webSearch: .responsesTool
            )
        case .xai:
            return NativeProviderRoute(
                family: .openaiResponses,
                auth: .apiKey,
                baseURL: URL(string: "https://api.x.ai/v1"),
                defaultModel: "grok-4",
                webSearch: .responsesTool
            )
        case .google:
            return NativeProviderRoute(
                family: .googleGenerativeAI,
                auth: .apiKey,
                baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta"),
                defaultModel: "gemini-2.5-flash",
                webSearch: .googleGrounding
            )
        case .minimax:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKey,
                baseURL: URL(string: "https://api.minimax.io/anthropic"),
                defaultModel: "MiniMax-M2.5",
                webSearch: .anthropicTool
            )
        case .minimaxCN:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKey,
                baseURL: URL(string: "https://api.minimaxi.com/anthropic"),
                defaultModel: "MiniMax-M2.5",
                webSearch: .anthropicTool
            )
        case .vercelAIGateway:
            return NativeProviderRoute(
                family: .anthropicMessages,
                auth: .apiKey,
                baseURL: URL(string: "https://ai-gateway.vercel.sh"),
                defaultModel: "anthropic/claude-sonnet-4",
                webSearch: .anthropicTool
            )
        case .deepseek:
            return NativeProviderRoute(
                family: .openaiResponses,
                auth: .apiKey,
                baseURL: URL(string: "https://api.deepseek.com"),
                defaultModel: "deepseek-chat",
                webSearch: .responsesTool
            )
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
                note: "原生走官方 OpenAI 兼容 /v1"
            )
        case .groq:
            return completions("https://api.groq.com/openai/v1")
        case .cerebras:
            return completions("https://api.cerebras.ai/v1")
        case .openrouter:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://openrouter.ai/api/v1"),
                webSearch: .openrouterPlugin
            )
        case .qwenTokenPlan:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"),
                webSearch: .qwenEnableSearch
            )
        case .qwenTokenPlanCN:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"),
                webSearch: .qwenEnableSearch
            )
        case .zai:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://api.z.ai/api/coding/paas/v4"),
                webSearch: .zaiChatTool
            )
        case .zaiCodingCN:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://open.bigmodel.cn/api/coding/paas/v4"),
                webSearch: .zaiChatTool
            )
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
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://api.kimi.com/coding"),
                webSearch: .kimiBuiltin
            )
        case .moonshotai:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://api.moonshot.ai/v1"),
                webSearch: .kimiBuiltin
            )
        case .moonshotaiCN:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://api.moonshot.cn/v1"),
                webSearch: .kimiBuiltin
            )
        case .xiaomi:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://api.xiaomimimo.com/v1"),
                webSearch: .xiaomiChatTool
            )
        case .xiaomiTokenPlanCN:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://token-plan-cn.xiaomimimo.com/v1"),
                webSearch: .xiaomiChatTool
            )
        case .xiaomiTokenPlanAMS:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://token-plan-ams.xiaomimimo.com/v1"),
                webSearch: .xiaomiChatTool
            )
        case .xiaomiTokenPlanSGP:
            return NativeProviderRoute(
                family: .openaiChatCompletions,
                auth: .apiKey,
                baseURL: URL(string: "https://token-plan-sgp.xiaomimimo.com/v1"),
                webSearch: .xiaomiChatTool
            )
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
                note: "Azure OpenAI Responses 协议尚未接入"
            )
        case .googleVertex:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "Google Vertex 协议尚未接入"
            )
        case .amazonBedrock:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "Bedrock Converse Stream 协议尚未接入"
            )
        case .cloudflareAIGateway:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "URL 需要账号和网关参数，尚未接入"
            )
        case .cloudflareWorkersAI:
            return NativeProviderRoute(
                family: .unsupported,
                auth: .unsupported,
                note: "URL 需要账号参数，尚未接入"
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

    public static func modelListStrategy(
        provider: AgentProviderID,
        baseURL: URL?,
        accessToken: String? = nil,
        accountID: String? = nil
    ) -> ModelListStrategy? {
        switch provider {
        case .openaiCodex:
            guard let token = accessToken, !token.isEmpty else { return nil }
            return .codexSubscription(token: token, accountID: accountID ?? "")
        case .anthropic:
            return .anthropic
        case .google:
            return .gemini
        case .openrouter:
            return .openRouterPublic
        case .azureOpenAI:
            guard let base = baseURL?.absoluteString, !base.isEmpty else { return nil }
            return .azureOpenAI(base: base)
        case .githubCopilot, .radius, .googleVertex, .amazonBedrock,
             .cloudflareAIGateway, .cloudflareWorkersAI:
            return nil
        default:
            guard let base = baseURL?.absoluteString, !base.isEmpty else { return nil }
            return .openAICompatible(base: base)
        }
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
