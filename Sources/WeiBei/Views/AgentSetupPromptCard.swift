import SwiftUI
import WeiBeiCore

// MARK: - 首启模型服务提醒卡
//
// 空启动页的一张安静提醒卡:对话需要先配置模型服务。
// 「现在配置」直达设置(默认落在「对话」页);「以后再说」记住偏好,
// 之后不再自动出现——真正配置完成后,卡片也会因就绪判断而自动消失。

struct AgentSetupPromptCard: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var oauth = PiOAuthService.shared
    @Environment(\.openSettings) private var openSettings

    /// 叉掉过一次就不再出现;偏好走 UserDefaults,不进冻结的 WorkspaceStore。
    @AppStorage("weibei.agentSetupPromptDismissed") private var dismissed = false

    var body: some View {
        if !dismissed, !AgentProviderReadiness.isConfigured(for: store) {
            cardBody
                .transition(.opacity)
        }
    }

    private var cardBody: some View {
        VStack(spacing: 9) {
            Text(store.ui(
                "魏碑的对话需要先连接一个模型服务",
                "WeiBei chat needs a model service first"
            ))
            .weiBeiText(12.5, weight: .medium)
            .foregroundStyle(WeiBeiTheme.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Text(store.ui(
                "支持订阅登录或 API Key，配置一次，所有课程共用。",
                "Use a subscription sign-in or an API key — configure once, shared across courses."
            ))
            .weiBeiText(11.5)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(store.ui("以后再说", "Later")) {
                    dismissed = true
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))

                Button(store.ui("现在配置", "Set Up Now")) {
                    openSettings()
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 470)
        .weibeiQuietCard(
            fill: WeiBeiTheme.paperRaised.opacity(0.55),
            stroke: WeiBeiTheme.hairline.opacity(0.5),
            cornerRadius: 8
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: WeiBeiTheme.ink.opacity(0.06), radius: 2, y: 1)
        .shadow(color: WeiBeiTheme.ink.opacity(0.05), radius: 10, y: 3)
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-setup-prompt")
    }
}
