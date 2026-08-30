import SwiftUI
import WeiBeiCore

// MARK: - Provider 配置就绪度(设置页与聊天区共用)
//
// 单一事实源:当前选中的模型服务是否已配置到「可对话」。
// 设置页的状态提醒、聊天的失败气泡与空态提示都走这一份判断,
// 两边不会各自演化出不一致的结论。

@MainActor
enum AgentProviderReadiness {
    private static var oauth: AgentAccountService { AgentAccountService.shared }

    /// 与 SettingsView.activeCredentialProviderID 相同的映射:custom/llamaCpp 的
    /// provider id 由当前 Base URL 派生,其余直接用 credentialProviderID。
    static func activeCredentialProviderID(for store: WorkspaceStore) -> String {
        guard store.agentProviderID == .custom || store.agentProviderID == .llamaCpp else {
            return store.agentProviderID.credentialProviderID
        }
        return (try? AgentProviderEndpoint(
            provider: store.agentProviderID,
            baseURL: store.agentBaseURL
        ).credentialProviderID) ?? "weibei-invalid-endpoint"
    }

    static func credentialProviderID(for provider: AgentProviderID, store: WorkspaceStore) -> String {
        guard provider == .custom || provider == .llamaCpp else {
            return provider.credentialProviderID
        }
        return (try? AgentProviderEndpoint(
            provider: provider,
            baseURL: store.agentBaseURL
        ).credentialProviderID) ?? "weibei-invalid-endpoint"
    }

    static func authTypes(for provider: AgentProviderID) -> [AgentCredentialType] {
        oauth.authTypes(for: provider)
    }

    /// provider 同时支持两种认证时以用户选择为准;否则只有一种可用。
    static func effectiveAuthMethod(for store: WorkspaceStore) -> AgentAuthMethod {
        let types = authTypes(for: store.agentProviderID)
        if types.contains(.oauth), types.contains(.apiKey) {
            return store.agentAuthMethod
        }
        return types.contains(.oauth) ? .subscription : .apiKey
    }

    /// API Key 型:密钥已存;Azure 额外要求密钥绑定到当前服务地址。
    static func hasActiveAPICredential(for store: WorkspaceStore) -> Bool {
        let isStored = oauth.isConfigured(
            providerID: activeCredentialProviderID(for: store),
            type: .apiKey
        )
        guard store.agentProviderID == .azureOpenAI else { return isStored }
        guard let endpoint = try? AgentProviderEndpoint(
            provider: .azureOpenAI,
            baseURL: store.agentBaseURL
        ) else { return false }
        return isStored && oauth.catalog?.credentials.contains(where: {
            $0.providerId == AgentProviderID.azureOpenAI.credentialProviderID
                && $0.type == .apiKey
                && $0.boundEndpoint == endpoint.baseURL
        }) == true
    }

    /// 订阅型:该 provider 支持 OAuth 且已完成链接。
    static func isSubscriptionLinked(for store: WorkspaceStore) -> Bool {
        guard authTypes(for: store.agentProviderID).contains(.oauth) else {
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

// MARK: - 聊天模型服务提示

/// 模型服务未配置时，在输入框旁说明原因并由用户主动进入配置。
/// 显隐条件由本视图自己判断，配置完成后随 catalog 更新自动消失。
struct AgentUnconfiguredHint: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject private var oauth = AgentAccountService.shared
    @Environment(\.openWindow) private var openSettingsWindow

    var body: some View {
        if !AgentProviderReadiness.isConfigured(for: store) {
            hintRow
                .transition(.opacity)
        }
    }

    private var hintRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal")
                    .weiBeiText(12, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Text(store.ui("还没有连接模型服务", "No model service connected yet"))
                    .weiBeiText(12.5, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.ink)
            }

            Text(store.ui(
                "连接后才能发送问题。可以使用订阅登录或 API Key。",
                "Connect a service before sending. You can use a subscription sign-in or an API key."
            ))
            .weiBeiText(11.5)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            Button(store.ui("配置模型服务", "Configure Model Service")) {
                openSettingsWindow(id: "weibei-settings")
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 460, alignment: .leading)
        .background {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperRaised.opacity(0.45),
                stroke: WeiBeiTheme.hairline.opacity(0.5)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-unconfigured-hint")
    }
}
