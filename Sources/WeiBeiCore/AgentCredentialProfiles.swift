import CryptoKit
import Darwin
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
                "选择模型服务，由魏碑保存 API 密钥。",
                "Choose a model service. WeiBei saves its API key."
            )
        case .subscription:
            return language.text(
                "通过浏览器连接 ChatGPT Plus/Pro、Claude Pro/Max 等订阅；登录信息由魏碑保存。",
                "Connect ChatGPT Plus/Pro, Claude Pro/Max, and other subscriptions in the browser. WeiBei saves the sign-in information."
            )
        }
    }
}

public struct AgentAuthenticationStatus: Equatable, Sendable {
    private var providerIDsRequiringLogin: Set<String> = []

    public init() {}

    public func requiresLogin(for provider: AgentProviderID) -> Bool {
        providerIDsRequiringLogin.contains(provider.rawValue)
    }

    public mutating func recordFailure(
        _ failure: AgentFailureKind,
        provider: AgentProviderID,
        authMethod: AgentAuthMethod
    ) {
        guard failure == .unauthorized, authMethod == .subscription else { return }
        providerIDsRequiringLogin.insert(provider.rawValue)
    }

    public mutating func recordSuccess(
        provider: AgentProviderID,
        authMethod: AgentAuthMethod
    ) {
        guard authMethod == .subscription else { return }
        providerIDsRequiringLogin.remove(provider.rawValue)
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

public enum AgentProviderEndpointError: LocalizedError, Equatable, Sendable {
    case missing
    case invalid
    case insecurePublicHTTP
    case azureCredentialRequiresReentry

    public var errorDescription: String? {
        switch self {
        case .missing:
            return "请先填写模型服务地址。"
        case .invalid:
            return "模型服务地址必须是有效的 HTTP 或 HTTPS 地址，且不能包含账号、查询参数或片段。"
        case .insecurePublicHTTP:
            return "公网模型服务必须使用 HTTPS；HTTP 只允许本机或用户明确填写的局域网服务。"
        case .azureCredentialRequiresReentry:
            return "Azure 服务地址与已保存密钥不一致。为避免把旧密钥发给新地址，请重新输入一次密钥。"
        }
    }
}

/// The normalized model endpoint and the Pi provider id that owns its credential.
/// Profiles may vary by model while credentials remain shared only by endpoint.
public struct AgentProviderEndpoint: Equatable, Sendable {
    public var piProviderID: String
    public var baseURL: String?

    public init(provider: AgentProviderID, baseURL rawBaseURL: String) throws {
        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.showsBaseURLField else {
            piProviderID = provider.piProviderName
            baseURL = nil
            return
        }
        guard !trimmed.isEmpty else {
            if provider == .custom || provider == .llamaCpp || provider == .azureOpenAI {
                throw AgentProviderEndpointError.missing
            }
            piProviderID = provider.piProviderName
            baseURL = nil
            return
        }
        guard trimmed.utf8.count <= 2_048,
              var components = URLComponents(string: trimmed),
              let rawScheme = components.scheme?.lowercased(),
              rawScheme == "https" || rawScheme == "http",
              let rawHost = components.host?.lowercased(),
              !rawHost.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw AgentProviderEndpointError.invalid
        }
        if rawScheme == "http", !Self.isTrustedLocalHost(rawHost) {
            throw AgentProviderEndpointError.insecurePublicHTTP
        }

        components.scheme = rawScheme
        components.host = rawHost
        if (rawScheme == "https" && components.port == 443)
            || (rawScheme == "http" && components.port == 80) {
            components.port = nil
        }
        while components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        guard let normalized = components.string,
              let normalizedURL = URL(string: normalized),
              normalizedURL.host != nil else {
            throw AgentProviderEndpointError.invalid
        }

        baseURL = normalized
        switch provider {
        case .custom, .llamaCpp:
            let digest = SHA256.hash(data: Data(normalized.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            let prefix = provider == .custom ? "weibei-custom" : "weibei-llama"
            piProviderID = "\(prefix)-\(digest)"
        default:
            piProviderID = provider.piProviderName
        }
    }

    private static func isTrustedLocalHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        if !host.contains(".") && !host.contains(":") {
            return true
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            return value >> 24 == 127
                || value >> 24 == 10
                || (value >= 0x6440_0000 && value <= 0x647F_FFFF)
                || value >> 16 == 0xA9FE
                || value >> 20 == 0xAC1
                || value >> 16 == 0xC0A8
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            return isLoopback
                || (bytes[0] & 0xFE) == 0xFC
                || (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80)
        }
        return false
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
