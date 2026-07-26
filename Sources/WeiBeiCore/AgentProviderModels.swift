import CoreGraphics
import Foundation

public enum AgentProviderKind: String, Codable, CaseIterable, Sendable {
    case subscription
    case apiKey
    case localOrCustom

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .subscription:
            return language.text("订阅 OAuth", "Subscription OAuth")
        case .apiKey:
            return language.text("API 密钥", "API Key")
        case .localOrCustom:
            return language.text("本地 / 自定义", "Local / Custom")
        }
    }
}

/// Which listing protocol a provider speaks, independent of runtime base URL / region.
/// The store combines this with `agentBaseURL` / `bedrockRegion` to build a concrete
/// `ModelListStrategy` for `AgentModelListService`.
public enum ModelListProtocol: String, Codable, CaseIterable, Sendable {
    /// OpenAI-compatible `GET {base}/v1/models` with `Authorization: Bearer`.
    case openAICompatible
    /// Anthropic `GET /v1/models` with `x-api-key` + `anthropic-version`.
    case anthropic
    /// Google Gemini `GET /v1beta/models?key=`.
    case gemini
    /// OpenRouter public catalog (no auth).
    case openRouterPublic
    /// Azure OpenAI data plane `GET {base}/openai/models?api-version=` with `api-key`.
    case azureOpenAI
    /// Amazon Bedrock `GET bedrock.{region}.amazonaws.com/foundation-models` with `Authorization: Bearer`.
    case bedrock
    /// GitHub Models catalog `GET api.github.com/models`.
    case gitHubModels
    /// ChatGPT/Codex subscription: query `chatgpt.com/backend-api/codex/models` with the
    /// OAuth token; fall back to the built-in catalog on failure.
    case codexSubscription
    /// Endpoint not publicly documented / stable; use the built-in catalog + manual entry.
    case unsupported
}

/// Full set of Pi `KnownProvider` ids + local/custom (aligned with Pi `docs/providers.md` + `env-api-keys`).
/// Raw values match Pi provider ids so auth.json / --provider stay compatible.
public enum AgentProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    // MARK: Subscription / OAuth (Pi `/login`)
    case openaiCodex = "openai-codex"
    case anthropic
    case githubCopilot = "github-copilot"

    // MARK: API-key providers (Pi KnownProvider)
    case openai
    case antLing = "ant-ling"
    case azureOpenAI = "azure-openai-responses"
    case deepseek
    case nvidia
    case google
    case googleVertex = "google-vertex"
    case amazonBedrock = "amazon-bedrock"
    case xai
    case mistral
    case groq
    case cerebras
    case cloudflareAIGateway = "cloudflare-ai-gateway"
    case cloudflareWorkersAI = "cloudflare-workers-ai"
    case openrouter
    case vercelAIGateway = "vercel-ai-gateway"
    case zai
    case zaiCodingCN = "zai-coding-cn"
    case opencode
    case opencodeGo = "opencode-go"
    case huggingface
    case fireworks
    case together
    case kimiCoding = "kimi-coding"
    case moonshotai
    case moonshotaiCN = "moonshotai-cn"
    case minimax
    case minimaxCN = "minimax-cn"
    case xiaomi
    case xiaomiTokenPlanCN = "xiaomi-token-plan-cn"
    case xiaomiTokenPlanAMS = "xiaomi-token-plan-ams"
    case xiaomiTokenPlanSGP = "xiaomi-token-plan-sgp"

    // MARK: Local / custom (models.json / OpenAI-compatible)
    case llamaCpp = "llama.cpp"
    case custom

    public var id: String { rawValue }

    /// Pi `--provider` / auth.json key.
    public var piProviderName: String { rawValue == "custom" ? "weibei-custom" : rawValue }

    public var kind: AgentProviderKind {
        switch self {
        case .openaiCodex, .anthropic, .githubCopilot:
            return .subscription
        case .llamaCpp, .custom:
            return .localOrCustom
        default:
            return .apiKey
        }
    }

    /// Providers for which WeiBei can run browser OAuth (Pi-compatible).
    public var supportsInAppOAuth: Bool {
        switch self {
        case .openaiCodex, .anthropic:
            return true
        default:
            return false
        }
    }

    /// Show Base URL field (Azure resource endpoint, local llama.cpp, custom OpenAI-compatible).
    public var showsBaseURLField: Bool {
        switch self {
        case .custom, .llamaCpp, .azureOpenAI:
            return true
        default:
            return false
        }
    }

    /// Primary env var Pi reads for this provider (when using API keys).
    public var environmentAPIKeyName: String {
        switch self {
        case .openaiCodex: return "OPENAI_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .githubCopilot: return "COPILOT_GITHUB_TOKEN"
        case .openai: return "OPENAI_API_KEY"
        case .antLing: return "ANT_LING_API_KEY"
        case .azureOpenAI: return "AZURE_OPENAI_API_KEY"
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .nvidia: return "NVIDIA_API_KEY"
        case .google: return "GEMINI_API_KEY"
        case .googleVertex: return "GOOGLE_CLOUD_API_KEY"
        case .amazonBedrock: return "AWS_BEARER_TOKEN_BEDROCK"
        case .xai: return "XAI_API_KEY"
        case .mistral: return "MISTRAL_API_KEY"
        case .groq: return "GROQ_API_KEY"
        case .cerebras: return "CEREBRAS_API_KEY"
        case .cloudflareAIGateway, .cloudflareWorkersAI: return "CLOUDFLARE_API_KEY"
        case .openrouter: return "OPENROUTER_API_KEY"
        case .vercelAIGateway: return "AI_GATEWAY_API_KEY"
        case .zai: return "ZAI_API_KEY"
        case .zaiCodingCN: return "ZAI_CODING_CN_API_KEY"
        case .opencode, .opencodeGo: return "OPENCODE_API_KEY"
        case .huggingface: return "HF_TOKEN"
        case .fireworks: return "FIREWORKS_API_KEY"
        case .together: return "TOGETHER_API_KEY"
        case .kimiCoding: return "KIMI_API_KEY"
        case .moonshotai, .moonshotaiCN: return "MOONSHOT_API_KEY"
        case .minimax: return "MINIMAX_API_KEY"
        case .minimaxCN: return "MINIMAX_CN_API_KEY"
        case .xiaomi: return "XIAOMI_API_KEY"
        case .xiaomiTokenPlanCN: return "XIAOMI_TOKEN_PLAN_CN_API_KEY"
        case .xiaomiTokenPlanAMS: return "XIAOMI_TOKEN_PLAN_AMS_API_KEY"
        case .xiaomiTokenPlanSGP: return "XIAOMI_TOKEN_PLAN_SGP_API_KEY"
        case .llamaCpp: return "OPENAI_API_KEY"
        case .custom: return "OPENAI_API_KEY"
        }
    }

    public var supportsOpenAIHTTPFallback: Bool {
        self == .openai
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .openaiCodex: return language.text("OpenAI Codex（ChatGPT 订阅）", "OpenAI Codex (ChatGPT sub)")
        case .anthropic: return language.text("Anthropic / Claude", "Anthropic / Claude")
        case .githubCopilot: return "GitHub Copilot"
        case .openai: return "OpenAI API"
        case .antLing: return "Ant Ling"
        case .azureOpenAI: return "Azure OpenAI"
        case .deepseek: return "DeepSeek"
        case .nvidia: return "NVIDIA NIM"
        case .google: return "Google Gemini"
        case .googleVertex: return "Google Vertex AI"
        case .amazonBedrock: return "Amazon Bedrock"
        case .xai: return "xAI (Grok)"
        case .mistral: return "Mistral"
        case .groq: return "Groq"
        case .cerebras: return "Cerebras"
        case .cloudflareAIGateway: return "Cloudflare AI Gateway"
        case .cloudflareWorkersAI: return "Cloudflare Workers AI"
        case .openrouter: return "OpenRouter"
        case .vercelAIGateway: return "Vercel AI Gateway"
        case .zai: return language.text("ZAI Coding Plan（全球）", "ZAI Coding Plan (Global)")
        case .zaiCodingCN: return language.text("ZAI Coding Plan（中国）", "ZAI Coding Plan (China)")
        case .opencode: return "OpenCode Zen"
        case .opencodeGo: return "OpenCode Go"
        case .huggingface: return "Hugging Face"
        case .fireworks: return "Fireworks"
        case .together: return "Together AI"
        case .kimiCoding: return "Kimi For Coding"
        case .moonshotai: return "Moonshot AI"
        case .moonshotaiCN: return language.text("Moonshot AI（中国）", "Moonshot AI (China)")
        case .minimax: return "MiniMax"
        case .minimaxCN: return language.text("MiniMax（中国）", "MiniMax (China)")
        case .xiaomi: return "Xiaomi MiMo"
        case .xiaomiTokenPlanCN: return language.text("Xiaomi Token Plan（中国）", "Xiaomi Token Plan (China)")
        case .xiaomiTokenPlanAMS: return language.text("Xiaomi Token Plan（阿姆斯特丹）", "Xiaomi Token Plan (Amsterdam)")
        case .xiaomiTokenPlanSGP: return language.text("Xiaomi Token Plan（新加坡）", "Xiaomi Token Plan (Singapore)")
        case .llamaCpp: return "llama.cpp"
        case .custom: return language.text("自定义 OpenAI 兼容", "Custom OpenAI-compatible")
        }
    }

    public var defaultModelHint: String {
        switch self {
        case .openaiCodex: return AgentModelListService.codexDefaultModel
        case .anthropic: return "claude-sonnet-4-20250514"
        case .githubCopilot: return "gpt-4.1"
        case .openai: return "gpt-5.5"
        case .antLing: return "default"
        case .azureOpenAI: return "gpt-4o"
        case .deepseek: return "deepseek-chat"
        case .nvidia: return "meta/llama-3.1-70b-instruct"
        case .google: return "gemini-2.5-pro"
        case .googleVertex: return "gemini-2.5-pro"
        case .amazonBedrock: return "us.anthropic.claude-sonnet-4-20250514-v1:0"
        case .xai: return "grok-3"
        case .mistral: return "mistral-large-latest"
        case .groq: return "llama-3.3-70b-versatile"
        case .cerebras: return "llama-3.3-70b"
        case .cloudflareAIGateway: return "claude-sonnet-4-5"
        case .cloudflareWorkersAI: return "@cf/meta/llama-3.1-70b-instruct"
        case .openrouter: return "openai/gpt-4.1"
        case .vercelAIGateway: return "openai/gpt-4.1"
        case .zai, .zaiCodingCN: return "default"
        case .opencode, .opencodeGo: return "default"
        case .huggingface: return "meta-llama/Llama-3.1-70B-Instruct"
        case .fireworks: return "accounts/fireworks/models/llama-v3p1-70b-instruct"
        case .together: return "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo"
        case .kimiCoding: return "moonshot-v1-auto"
        case .moonshotai, .moonshotaiCN: return "kimi-k2.5"
        case .minimax, .minimaxCN: return "MiniMax-Text-01"
        case .xiaomi, .xiaomiTokenPlanCN, .xiaomiTokenPlanAMS, .xiaomiTokenPlanSGP: return "default"
        case .llamaCpp: return "local-model"
        case .custom: return "model-id"
        }
    }

    /// Which listing protocol this provider speaks. The runtime base URL / region is
    /// supplied by the store when it assembles a concrete `ModelListStrategy`.
    public var modelListProtocol: ModelListProtocol {
        switch self {
        case .openai, .mistral, .xai, .groq, .deepseek, .nvidia, .cerebras,
             .together, .fireworks, .huggingface, .llamaCpp, .custom:
            return .openAICompatible
        case .anthropic:
            return .anthropic
        case .google:
            return .gemini
        case .openrouter:
            return .openRouterPublic
        case .azureOpenAI:
            return .azureOpenAI
        case .amazonBedrock:
            return .bedrock
        case .githubCopilot:
            return .gitHubModels
        case .openaiCodex:
            return .codexSubscription
        // Providers whose listing endpoints are not publicly documented / stable enough
        // to call blindly (ant-ling, vertex, cloudflare, vercel, zai, opencode, kimi,
        // moonshot, minimax, xiaomi). Surface the built-in catalog + manual entry instead.
        case .antLing, .googleVertex, .cloudflareAIGateway, .cloudflareWorkersAI,
             .vercelAIGateway, .zai, .zaiCodingCN, .opencode, .opencodeGo,
             .kimiCoding, .moonshotai, .moonshotaiCN, .minimax, .minimaxCN,
             .xiaomi, .xiaomiTokenPlanCN, .xiaomiTokenPlanAMS, .xiaomiTokenPlanSGP:
            return .unsupported
        }
    }

    /// Official default host for OpenAI-compatible listing, when the user has not typed
    /// a custom Base URL. `nil` for providers that take a user-supplied base or use a
    /// non-OpenAI protocol.
    public var defaultListBaseURL: String? {
        switch self {
        case .openai: return "https://api.openai.com"
        case .mistral: return "https://api.mistral.ai"
        case .xai: return "https://api.x.ai"
        case .groq: return "https://api.groq.com/openai"
        case .deepseek: return "https://api.deepseek.com"
        case .nvidia: return "https://integrate.api.nvidia.com"
        case .cerebras: return "https://api.cerebras.ai"
        case .together: return "https://api.together.xyz"
        case .fireworks: return "https://api.fireworks.ai/inference"
        case .huggingface: return "https://api.endpoints.huggingface.com"
        default: return nil
        }
    }

    /// Built-in catalog shown before the first successful fetch, or as the fallback when
    /// a provider's listing endpoint is not supported. Extend cautiously: stale ids mislead.
    public var recommendedModels: [String] {
        switch self {
        case .openaiCodex: return AgentModelListService.codexSubscriptionModels
        case .anthropic: return ["claude-sonnet-4-5", "claude-opus-4-5", "claude-haiku-4-5", "claude-sonnet-4-20250514"]
        case .githubCopilot: return ["gpt-5.1", "gpt-4.1", "claude-sonnet-4-5"]
        case .openai: return ["gpt-5.5", "gpt-5.4", "gpt-5.1", "gpt-4o", "gpt-4o-mini"]
        case .azureOpenAI: return ["gpt-4o", "gpt-4o-mini", "gpt-4.1"]
        case .deepseek: return ["deepseek-chat", "deepseek-reasoner"]
        case .google, .googleVertex: return ["gemini-2.5-pro", "gemini-2.5-flash"]
        case .xai: return ["grok-4", "grok-3"]
        case .mistral: return ["mistral-large-latest", "mistral-medium-latest", "mistral-small-latest"]
        case .groq: return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"]
        case .openrouter: return ["openai/gpt-5.1", "anthropic/claude-sonnet-4-5", "google/gemini-2.5-pro"]
        default:
            let hint = defaultModelHint
            return hint.isEmpty ? [] : [hint]
        }
    }

    public static var subscriptionProviders: [AgentProviderID] {
        allCases.filter { $0.kind == .subscription }
    }

    public static var apiKeyProviders: [AgentProviderID] {
        allCases.filter { $0.kind == .apiKey }
    }

    public static var localOrCustomProviders: [AgentProviderID] {
        allCases.filter { $0.kind == .localOrCustom }
    }
}
