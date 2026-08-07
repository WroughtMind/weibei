import Foundation

/// How the user wants to attach a model provider for Pi.
public enum AgentAuthMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Configure an API credential through embedded Pi.
    case apiKey
    /// Pi `/login` style OAuth subscription (tokens in auth.json).
    case subscription

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .apiKey:
            return language.text("API 密钥", "API Key")
        case .subscription:
            return language.text("订阅 OAuth", "Subscription OAuth")
        }
    }

    public func detail(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .apiKey:
            return language.text(
                "选择 Pi 支持的提供商，由内置 Pi 完成 API 凭证配置与保存。",
                "Choose a Pi-supported provider and let embedded Pi configure and store its API credential."
            )
        case .subscription:
            return language.text(
                "浏览器 OAuth 连接 ChatGPT Plus/Pro、Claude Pro/Max 等订阅；凭证保存在魏碑自己的 Pi 配置里（不写入终端 ~/.pi）。",
                "Browser OAuth for ChatGPT Plus/Pro, Claude Pro/Max, etc. Tokens stay in WeiBei’s own Pi config (not terminal ~/.pi)."
            )
        }
    }
}

/// A named, switchable agent configuration (provider + model + optional base URL).
/// Credentials are provider-owned entries in embedded Pi and never enter this payload.
public struct AgentCredentialProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: AgentProviderID
    public var authMethod: AgentAuthMethod
    public var modelName: String
    public var baseURL: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        provider: AgentProviderID = .openai,
        authMethod: AgentAuthMethod = .apiKey,
        modelName: String = "",
        baseURL: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.authMethod = authMethod
        self.modelName = modelName
        self.baseURL = baseURL
        self.updatedAt = updatedAt
    }
}

/// Console URLs for every `AgentProviderID`.
public enum AgentProviderConsoleLinks {
    /// Per-provider console metadata. Exhaustive via `metadata(for:)` switch so a
    /// new `AgentProviderID` case forces a compile error here.
    public struct Metadata: Sendable, Equatable {
        /// Key-creation / dashboard page (may be nil for local/custom providers).
        public var loginURLString: String?
        /// Account home when it differs from the login URL. `nil` means “use login”.
        public var accountURLString: String?
        public init(loginURLString: String?, accountURLString: String? = nil) {
            self.loginURLString = loginURLString
            self.accountURLString = accountURLString
        }
    }

    /// Dashboard / key-creation pages for API-key providers.
    public static func loginURL(for provider: AgentProviderID) -> URL? {
        metadata(for: provider).loginURLString.flatMap(URL.init(string:))
    }

    public static func accountURL(for provider: AgentProviderID) -> URL? {
        let row = metadata(for: provider)
        if let account = row.accountURLString {
            return URL(string: account)
        }
        return row.loginURLString.flatMap(URL.init(string:))
    }

    /// Single source of truth for provider console links.
    public static func metadata(for provider: AgentProviderID) -> Metadata {
        switch provider {
        case .openai:
            return Metadata(
                loginURLString: "https://platform.openai.com/api-keys",
                accountURLString: "https://platform.openai.com/"
            )
        case .openaiCodex:
            return Metadata(
                loginURLString: "https://platform.openai.com/api-keys",
                accountURLString: "https://chatgpt.com/"
            )
        case .anthropic:
            return Metadata(
                loginURLString: "https://console.anthropic.com/settings/keys",
                accountURLString: "https://claude.ai/"
            )
        case .githubCopilot:
            return Metadata(
                loginURLString: "https://github.com/settings/copilot",
                accountURLString: "https://github.com/login"
            )
        case .xai:
            return Metadata(
                loginURLString: "https://console.x.ai/",
                accountURLString: "https://x.ai/"
            )
        case .antLing:
            return Metadata(loginURLString: nil)
        case .azureOpenAI:
            return Metadata(loginURLString: "https://portal.azure.com/")
        case .deepseek:
            return Metadata(loginURLString: "https://platform.deepseek.com/api_keys")
        case .nvidia:
            return Metadata(loginURLString: "https://build.nvidia.com/")
        case .google:
            return Metadata(loginURLString: "https://aistudio.google.com/apikey")
        case .googleVertex:
            return Metadata(loginURLString: "https://console.cloud.google.com/vertex-ai")
        case .amazonBedrock:
            return Metadata(loginURLString: "https://console.aws.amazon.com/bedrock")
        case .mistral:
            return Metadata(loginURLString: "https://console.mistral.ai/")
        case .groq:
            return Metadata(loginURLString: "https://console.groq.com/keys")
        case .cerebras:
            return Metadata(loginURLString: "https://cloud.cerebras.ai/")
        case .cloudflareAIGateway:
            return Metadata(loginURLString: "https://dash.cloudflare.com/")
        case .cloudflareWorkersAI:
            return Metadata(loginURLString: "https://dash.cloudflare.com/")
        case .openrouter:
            return Metadata(loginURLString: "https://openrouter.ai/keys")
        case .qwenTokenPlan, .qwenTokenPlanCN, .radius:
            return Metadata(loginURLString: nil)
        case .vercelAIGateway:
            return Metadata(loginURLString: "https://vercel.com/docs/ai-gateway")
        case .zai, .zaiCodingCN:
            return Metadata(loginURLString: "https://z.ai/")
        case .opencode, .opencodeGo:
            return Metadata(loginURLString: "https://opencode.ai/")
        case .huggingface:
            return Metadata(loginURLString: "https://huggingface.co/settings/tokens")
        case .fireworks:
            return Metadata(loginURLString: "https://fireworks.ai/account/api-keys")
        case .together:
            return Metadata(loginURLString: "https://api.together.xyz/settings/api-keys")
        case .kimiCoding, .moonshotai, .moonshotaiCN:
            return Metadata(loginURLString: "https://platform.moonshot.cn/")
        case .minimax, .minimaxCN:
            return Metadata(loginURLString: "https://www.minimaxi.com/")
        case .xiaomi, .xiaomiTokenPlanCN, .xiaomiTokenPlanAMS, .xiaomiTokenPlanSGP:
            return Metadata(loginURLString: nil)
        case .llamaCpp:
            return Metadata(loginURLString: nil)
        case .custom:
            return Metadata(loginURLString: nil)
        }
    }
}

/// Persist named provider/model configurations. Embedded Pi owns credentials.
public enum AgentCredentialProfileStore {
    private static let profilesKey = "weibei.agentCredentialProfiles.v1"
    private static let activeProfileKey = "weibei.agentCredentialActiveProfileID.v1"

    public static func loadProfiles() -> [AgentCredentialProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([AgentCredentialProfile].self, from: data),
              !decoded.isEmpty else {
            return [defaultProfile()]
        }
        return decoded
    }

    public static func saveProfiles(_ profiles: [AgentCredentialProfile]) {
        let payload = profiles.isEmpty ? [defaultProfile()] : profiles
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    public static func activeProfileID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: activeProfileKey) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func setActiveProfileID(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
    }

    public static func defaultProfile() -> AgentCredentialProfile {
        AgentCredentialProfile(
            name: "Default",
            provider: .openai,
            authMethod: .apiKey
        )
    }

}
