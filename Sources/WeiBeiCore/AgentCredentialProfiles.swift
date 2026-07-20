import Foundation
import Security

/// How the user wants to attach a model provider for Pi.
public enum AgentAuthMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Paste / store an API key (Pi's primary path: env vars + --provider / --model).
    case apiKey
    /// Open the provider's account / console (OAuth or dashboard login), then paste a key or token.
    case subscription

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .apiKey:
            return language.text("API 密钥", "API Key")
        case .subscription:
            return language.text("订阅 / 账号", "Subscription / Account")
        }
    }

    public func detail(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .apiKey:
            return language.text(
                "在提供商控制台创建 API Key，粘贴后保存到钥匙串。适合 OpenAI、Anthropic、Google、OpenRouter 与自定义 OpenAI 兼容接口。",
                "Create an API key in the provider console, paste it, and save to Keychain. Works with OpenAI, Anthropic, Google, OpenRouter, and custom OpenAI-compatible endpoints."
            )
        case .subscription:
            return language.text(
                "与 Pi 的 /login 相同：浏览器完成 OAuth（ChatGPT Plus/Pro、Claude Pro/Max），凭证写入 auth.json，自动用于对话。",
                "Same as Pi’s /login: complete browser OAuth (ChatGPT Plus/Pro, Claude Pro/Max); tokens are stored in auth.json and used automatically."
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
    /// Official pages for account login / API key creation. Pi itself consumes keys via env / CLI flags.
    public static func loginURL(for provider: AgentProviderID) -> URL? {
        switch provider {
        case .openai:
            return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .google:
            return URL(string: "https://aistudio.google.com/apikey")
        case .openrouter:
            return URL(string: "https://openrouter.ai/keys")
        case .custom:
            return nil
        }
    }

    public static func accountURL(for provider: AgentProviderID) -> URL? {
        switch provider {
        case .openai:
            return URL(string: "https://chatgpt.com/")
        case .anthropic:
            return URL(string: "https://claude.ai/")
        case .google:
            return URL(string: "https://gemini.google.com/")
        case .openrouter:
            return URL(string: "https://openrouter.ai/")
        case .custom:
            return nil
        }
    }

    public static func keyHelp(language: WeiBeiInterfaceLanguage, provider: AgentProviderID) -> String {
        switch provider {
        case .openai:
            return language.text(
                "OpenAI：在 platform.openai.com 创建 sk-… 密钥。ChatGPT 网页订阅与 API 计费是分开的。",
                "OpenAI: create an sk-… key on platform.openai.com. ChatGPT web subscription is billed separately from API usage."
            )
        case .anthropic:
            return language.text(
                "Anthropic：在 console.anthropic.com 创建 API Key（sk-ant-…）。",
                "Anthropic: create an API key (sk-ant-…) in console.anthropic.com."
            )
        case .google:
            return language.text(
                "Google：在 Google AI Studio 创建 Gemini API Key。",
                "Google: create a Gemini API key in Google AI Studio."
            )
        case .openrouter:
            return language.text(
                "OpenRouter：登录后在 Keys 页创建密钥，可路由多家模型。",
                "OpenRouter: sign in, create a key on the Keys page, and route multiple model providers."
            )
        case .custom:
            return language.text(
                "自定义：填写 OpenAI 兼容 Base URL，并粘贴该服务的 API Key。",
                "Custom: set an OpenAI-compatible Base URL and paste that service’s API key."
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
