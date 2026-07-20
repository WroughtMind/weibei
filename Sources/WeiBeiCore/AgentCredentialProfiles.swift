import Foundation
import Security

/// How the user wants to attach a model provider for Pi.
public enum AgentAuthMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Paste / store an API key (Pi env vars + auth.json api_key).
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
                "选择任意 Pi 支持的提供商，粘贴 API Key 并保存。密钥按配置写入钥匙串，并注入 Pi 对应环境变量。",
                "Pick any Pi-supported provider, paste an API key, and save. Keys are stored per profile in Keychain and passed as Pi env vars."
            )
        case .subscription:
            return language.text(
                "与 Pi `/login` 相同：浏览器 OAuth 连接 ChatGPT Plus/Pro、Claude Pro/Max 等订阅；凭证写入 ~/.pi/agent/auth.json。",
                "Same as Pi `/login`: browser OAuth for ChatGPT Plus/Pro, Claude Pro/Max, etc. Credentials go to ~/.pi/agent/auth.json."
            )
        }
    }
}

/// A named, switchable agent connection profile (provider + model + optional base URL).
/// Secrets live in the Keychain under the profile id — never in this struct's Codable payload.
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
        self.modelName = modelName.isEmpty ? provider.defaultModelHint : modelName
        self.baseURL = baseURL
        self.updatedAt = updatedAt
    }
}

public enum AgentProviderConsoleLinks {
    /// Dashboard / key-creation pages for API-key providers.
    public static func loginURL(for provider: AgentProviderID) -> URL? {
        switch provider {
        case .openai, .openaiCodex:
            return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .githubCopilot:
            return URL(string: "https://github.com/settings/copilot")
        case .xai:
            return URL(string: "https://console.x.ai/")
        case .antLing:
            return nil
        case .azureOpenAI:
            return URL(string: "https://portal.azure.com/")
        case .deepseek:
            return URL(string: "https://platform.deepseek.com/api_keys")
        case .nvidia:
            return URL(string: "https://build.nvidia.com/")
        case .google:
            return URL(string: "https://aistudio.google.com/apikey")
        case .googleVertex:
            return URL(string: "https://console.cloud.google.com/vertex-ai")
        case .amazonBedrock:
            return URL(string: "https://console.aws.amazon.com/bedrock")
        case .mistral:
            return URL(string: "https://console.mistral.ai/")
        case .groq:
            return URL(string: "https://console.groq.com/keys")
        case .cerebras:
            return URL(string: "https://cloud.cerebras.ai/")
        case .cloudflareAIGateway, .cloudflareWorkersAI:
            return URL(string: "https://dash.cloudflare.com/")
        case .openrouter:
            return URL(string: "https://openrouter.ai/keys")
        case .vercelAIGateway:
            return URL(string: "https://vercel.com/docs/ai-gateway")
        case .zai, .zaiCodingCN:
            return URL(string: "https://z.ai/")
        case .opencode, .opencodeGo:
            return URL(string: "https://opencode.ai/")
        case .huggingface:
            return URL(string: "https://huggingface.co/settings/tokens")
        case .fireworks:
            return URL(string: "https://fireworks.ai/account/api-keys")
        case .together:
            return URL(string: "https://api.together.xyz/settings/api-keys")
        case .kimiCoding, .moonshotai, .moonshotaiCN:
            return URL(string: "https://platform.moonshot.cn/")
        case .minimax, .minimaxCN:
            return URL(string: "https://www.minimaxi.com/")
        case .xiaomi, .xiaomiTokenPlanCN, .xiaomiTokenPlanAMS, .xiaomiTokenPlanSGP:
            return nil
        case .llamaCpp, .custom:
            return nil
        }
    }

    public static func accountURL(for provider: AgentProviderID) -> URL? {
        switch provider {
        case .openaiCodex:
            return URL(string: "https://chatgpt.com/")
        case .anthropic:
            return URL(string: "https://claude.ai/")
        case .githubCopilot:
            return URL(string: "https://github.com/login")
        case .xai:
            return URL(string: "https://x.ai/")
        case .openai:
            return URL(string: "https://platform.openai.com/")
        default:
            return loginURL(for: provider)
        }
    }

    public static func keyHelp(language: WeiBeiInterfaceLanguage, provider: AgentProviderID) -> String {
        let env = provider.environmentAPIKeyName
        switch provider {
        case .openaiCodex:
            return language.text(
                "ChatGPT Plus/Pro：用「订阅 OAuth」登录（Pi /login openai-codex）。无需粘贴 sk-。",
                "ChatGPT Plus/Pro: use Subscription OAuth (Pi /login openai-codex). No sk- paste required."
            )
        case .anthropic:
            return language.text(
                "Claude 订阅用 OAuth；或粘贴 API Key（\(env)）。",
                "Claude subscription via OAuth, or paste an API key (\(env))."
            )
        case .githubCopilot:
            return language.text(
                "GitHub Copilot：在 Pi 中 /login github-copilot，或设置 \(env)。",
                "GitHub Copilot: use Pi /login github-copilot, or set \(env)."
            )
        case .azureOpenAI:
            return language.text(
                "环境变量：\(env)。还需 AZURE_OPENAI_BASE_URL 或资源名（可写在 Base URL）。",
                "Env: \(env). Also need AZURE_OPENAI_BASE_URL or resource name (use Base URL)."
            )
        case .googleVertex:
            return language.text(
                "可用 \(env)，或 gcloud ADC + GOOGLE_CLOUD_PROJECT / LOCATION。",
                "Use \(env), or gcloud ADC with GOOGLE_CLOUD_PROJECT / LOCATION."
            )
        case .amazonBedrock:
            return language.text(
                "Bearer \(env)，或 AWS_PROFILE / IAM 密钥（由系统环境提供）。",
                "Bearer \(env), or AWS_PROFILE / IAM keys from the host environment."
            )
        case .cloudflareAIGateway:
            return language.text(
                "\(env) + CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_GATEWAY_ID。",
                "\(env) + CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_GATEWAY_ID."
            )
        case .cloudflareWorkersAI:
            return language.text(
                "\(env) + CLOUDFLARE_ACCOUNT_ID。",
                "\(env) + CLOUDFLARE_ACCOUNT_ID."
            )
        case .custom:
            return language.text(
                "自定义：填写 OpenAI 兼容 Base URL，并粘贴该服务的 API Key（注入 \(env)）。",
                "Custom: set an OpenAI-compatible Base URL and paste the API key (injected as \(env))."
            )
        case .llamaCpp:
            return language.text(
                "llama.cpp：填写本地 OpenAI 兼容 Base URL；密钥通常可留空。",
                "llama.cpp: set local OpenAI-compatible Base URL; key is often empty."
            )
        default:
            return language.text(
                "环境变量：\(env)。粘贴密钥后保存到当前配置。",
                "Env: \(env). Paste the key and save to the current profile."
            )
        }
    }
}

/// Persist named profiles (metadata in UserDefaults; secrets in Keychain).
public enum AgentCredentialProfileStore {
    private static let profilesKey = "weibei.agentCredentialProfiles.v1"
    private static let activeProfileKey = "weibei.agentCredentialActiveProfileID.v1"
    private static let keychainService = "com.changfenhuang.weibei.agent-profile"

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
            authMethod: .apiKey,
            modelName: AgentProviderID.openai.defaultModelHint
        )
    }

    public static func loadAPIKey(profileID: UUID) -> String {
        KeychainPasswordStore(
            service: keychainService,
            account: "PROFILE_\(profileID.uuidString)"
        ).load()
    }

    public static func saveAPIKey(_ value: String, profileID: UUID) throws {
        try KeychainPasswordStore(
            service: keychainService,
            account: "PROFILE_\(profileID.uuidString)"
        ).save(value)
    }

    public static func deleteAPIKey(profileID: UUID) throws {
        try KeychainPasswordStore(
            service: keychainService,
            account: "PROFILE_\(profileID.uuidString)"
        ).delete()
    }
}
