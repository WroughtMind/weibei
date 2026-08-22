import SwiftUI
import WeiBeiCore

// MARK: - Provider 配置就绪度(设置页与聊天区共用)
//
// 单一事实源:当前选中的模型服务是否已配置到「可对话」。
// 设置页的状态提醒、聊天的失败气泡与空态提示都走这一份判断,
// 两边不会各自演化出不一致的结论。

@MainActor
enum AgentProviderReadiness {
    private static var oauth: PiOAuthService { PiOAuthService.shared }

    /// 与 SettingsView.activePiProviderID 相同的映射:custom/llamaCpp 的
    /// provider id 由当前 Base URL 派生,其余直接用 piProviderName。
    static func activePiProviderID(for store: WorkspaceStore) -> String {
        guard store.agentProviderID == .custom || store.agentProviderID == .llamaCpp else {
            return store.agentProviderID.piProviderName
        }
        return (try? AgentProviderEndpoint(
            provider: store.agentProviderID,
            baseURL: store.agentBaseURL
        ).piProviderID) ?? "weibei-invalid-endpoint"
    }

    static func piProviderID(for provider: AgentProviderID, store: WorkspaceStore) -> String {
        guard provider == .custom || provider == .llamaCpp else {
            return provider.piProviderName
        }
        return (try? AgentProviderEndpoint(
            provider: provider,
            baseURL: store.agentBaseURL
        ).piProviderID) ?? "weibei-invalid-endpoint"
    }

    static func piAuthTypes(for provider: AgentProviderID, store: WorkspaceStore) -> [PiCredentialType] {
        if let types = oauth.catalog?.providers.first(where: {
            $0.id == piProviderID(for: provider, store: store)
        })?.authTypes, !types.isEmpty {
            return types
        }
        return provider.kind == .subscription ? [.oauth] : [.apiKey]
    }

    /// provider 同时支持两种认证时以用户选择为准;否则只有一种可用。
    static func effectiveAuthMethod(for store: WorkspaceStore) -> AgentAuthMethod {
        let types = piAuthTypes(for: store.agentProviderID, store: store)
        if types.contains(.oauth), types.contains(.apiKey) {
            return store.agentAuthMethod
        }
        return types.contains(.oauth) ? .subscription : .apiKey
    }

    /// API Key 型:密钥已存;Azure 额外要求密钥绑定到当前服务地址。
    static func hasActiveAPICredential(for store: WorkspaceStore) -> Bool {
        let isStored = oauth.isConfigured(
            providerID: activePiProviderID(for: store),
            type: .apiKey
        )
        guard store.agentProviderID == .azureOpenAI else { return isStored }
        guard let endpoint = try? AgentProviderEndpoint(
            provider: .azureOpenAI,
            baseURL: store.agentBaseURL
        ) else { return false }
        return isStored && oauth.catalog?.credentials.contains(where: {
            $0.providerId == AgentProviderID.azureOpenAI.piProviderName
                && $0.type == .apiKey
                && $0.boundEndpoint == endpoint.baseURL
        }) == true
    }

    /// 订阅型:该 provider 支持 OAuth 且已完成链接。
    static func isSubscriptionLinked(for store: WorkspaceStore) -> Bool {
        guard piAuthTypes(for: store.agentProviderID, store: store).contains(.oauth) else {
            return false
        }
        return effectiveAuthMethod(for: store) == .subscription
            && oauth.isLinked(store.agentProviderID)
    }

    /// 当前选中的模型服务是否已可对话。
    static func isConfigured(for store: WorkspaceStore) -> Bool {
        effectiveAuthMethod(for: store) == .subscription
            ? isSubscriptionLinked(for: store)
            : hasActiveAPICredential(for: store)
    }
}

// MARK: - 聊天空态轻提示

/// 对话为空且模型服务未配置时的一行安静提示,带直达设置的入口。
/// 放在消息列表顶部,不占常驻空间——配置完成后自动消失。
struct AgentUnconfiguredHint: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject private var oauth = PiOAuthService.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.horizontal")
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Text(store.ui("还没有配置模型服务", "No model service configured yet"))
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Button(store.ui("去设置", "Open Settings")) {
                openSettings()
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}
