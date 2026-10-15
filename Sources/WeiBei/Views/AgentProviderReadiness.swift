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
                && endpoint.matchesCredentialBinding(
                    for: .azureOpenAI,
                    boundEndpoint: $0.boundEndpoint
                )
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

    static func isReadyToChat(for store: WorkspaceStore) -> Bool {
        isConfigured(for: store) && !store.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 当前选中的模型服务是否已保存所需凭据。
    static func isConfigured(for store: WorkspaceStore) -> Bool {
        effectiveAuthMethod(for: store) == .subscription
            ? isSubscriptionLinked(for: store)
            : hasActiveAPICredential(for: store)
    }
}

/// 普通聊天和浮动聊天共用的失败恢复入口。
struct AgentConnectionRecoveryView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let failureKind: AgentFailureKind?
    @State private var showsSetup = false

    static func isRelevant(_ failure: AgentFailureKind?) -> Bool {
        failure == .unauthorized || failure == .insufficientQuota || failure == .modelUnavailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(failureKind == .modelUnavailable
                   ? store.ui("更换模型", "Change Model") : store.ui("重新连接", "Reconnect")) {
                showsSetup = true
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
            if showsSetup {
                AgentConnectionSetupView(
                    existingProfileID: failureKind == .modelUnavailable && AgentProviderReadiness.isConfigured(for: store)
                        ? store.activeAgentProfileID : nil,
                    replacementProfileID: store.activeAgentProfileID,
                    provider: store.agentProviderID, authMethod: store.agentAuthMethod, baseURL: store.agentBaseURL,
                    onConnected: { showsSetup = false }, onCancel: { showsSetup = false }
                )
                .frame(maxWidth: 460, alignment: .leading)
            }
        }
    }
}

// MARK: - 聊天模型服务提示

/// 模型服务未配置时，在输入框旁说明原因并由用户主动进入配置。
/// 显隐条件由本视图自己判断，配置完成后随 catalog 更新自动消失。
struct AgentUnconfiguredHint: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject private var oauth = AgentAccountService.shared
    @State private var showsConnectionSetup = false

    var body: some View {
        if showsConnectionSetup {
            AgentConnectionSetupView(
                existingProfileID: AgentProviderReadiness.isConfigured(for: store) ? store.activeAgentProfileID : nil,
                replacementProfileID: store.activeAgentProfileID,
                onConnected: { showsConnectionSetup = false },
                onCancel: { showsConnectionSetup = false }
            )
            .frame(maxWidth: 460, alignment: .leading)
        } else if !AgentProviderReadiness.isReadyToChat(for: store) {
            hintRow.transition(.opacity)
        }
    }

    private var hintRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal")
                    .weiBeiText(12, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Text(AgentProviderReadiness.isConfigured(for: store)
                    ? store.ui("选择模型后即可提问", "Choose a model to start chatting")
                    : store.ui("还没有连接模型服务", "No model service connected yet"))
                    .weiBeiText(12.5, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.ink)
            }

            Text(AgentProviderReadiness.isConfigured(for: store)
                ? store.ui("在这里选择要用的模型，写好的问题会保留。", "Choose your model here. Your question stays in place.")
                : store.ui("在这里完成账号登录或填写 API Key，写好的问题会保留。", "Sign in or enter an API key here. Your question stays in place."))
            .weiBeiText(11.5)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            Button(AgentProviderReadiness.isConfigured(for: store)
                   ? store.ui("选择模型", "Choose Model") : store.ui("连接模型服务", "Connect Model Service")) {
                showsConnectionSetup = true
            }
            .accessibilityIdentifier("agent-connect-inline")
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
