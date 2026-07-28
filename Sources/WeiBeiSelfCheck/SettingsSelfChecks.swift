import Foundation
import WeiBeiCore

/**
 * 验证应用入口、设置界面、模型目录与服务商元数据契约。
 */
enum SettingsSelfChecks {
    /**
     * 执行该领域的自检。
     */
    @MainActor
    static func run() throws {
        // Runtime golden values — keep the pre-L5 URLs/help strings from drifting.
        for provider in AgentProviderID.allCases {
            _ = AgentProviderConsoleLinks.loginURL(for: provider)
            _ = AgentProviderConsoleLinks.accountURL(for: provider)
            _ = AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: provider)
            _ = AgentProviderConsoleLinks.keyHelp(language: .english, provider: provider)
            _ = AgentProviderConsoleLinks.metadata(for: provider)
        }
        expect(AgentProviderConsoleLinks.loginURL(for: .openai)?.absoluteString == "https://platform.openai.com/api-keys"
            && AgentProviderConsoleLinks.accountURL(for: .openai)?.absoluteString == "https://platform.openai.com/"
            && AgentProviderConsoleLinks.loginURL(for: .openaiCodex)?.absoluteString == "https://platform.openai.com/api-keys"
            && AgentProviderConsoleLinks.accountURL(for: .openaiCodex)?.absoluteString == "https://chatgpt.com/"
            && AgentProviderConsoleLinks.loginURL(for: .anthropic)?.absoluteString == "https://console.anthropic.com/settings/keys"
            && AgentProviderConsoleLinks.accountURL(for: .anthropic)?.absoluteString == "https://claude.ai/"
            && AgentProviderConsoleLinks.loginURL(for: .githubCopilot)?.absoluteString == "https://github.com/settings/copilot"
            && AgentProviderConsoleLinks.accountURL(for: .githubCopilot)?.absoluteString == "https://github.com/login"
            && AgentProviderConsoleLinks.loginURL(for: .xai)?.absoluteString == "https://console.x.ai/"
            && AgentProviderConsoleLinks.accountURL(for: .xai)?.absoluteString == "https://x.ai/"
            && AgentProviderConsoleLinks.loginURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys"
            && AgentProviderConsoleLinks.loginURL(for: .openrouter)?.absoluteString == "https://openrouter.ai/keys"
            && AgentProviderConsoleLinks.loginURL(for: .custom) == nil
            && AgentProviderConsoleLinks.loginURL(for: .llamaCpp) == nil
            && AgentProviderConsoleLinks.loginURL(for: .xiaomi) == nil
            && AgentProviderConsoleLinks.accountURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys",
            "provider console login/account URLs match the pre-L5 golden set")
        expect(AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .openaiCodex).contains("订阅 OAuth")
            && AgentProviderConsoleLinks.keyHelp(language: .english, provider: .openaiCodex).contains("Subscription OAuth")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .anthropic).contains("ANTHROPIC_API_KEY")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .azureOpenAI).contains("AZURE_OPENAI_BASE_URL")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .amazonBedrock).contains("AWS_BEARER_TOKEN_BEDROCK")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .custom).contains("OpenAI 兼容")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .llamaCpp).contains("llama.cpp")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .openai).contains("OPENAI_API_KEY")
            && AgentProviderConsoleLinks.metadata(for: .openai).help == .genericEnv
            && AgentProviderConsoleLinks.metadata(for: .openaiCodex).help == .openaiCodex
            && AgentProviderConsoleLinks.metadata(for: .cloudflareAIGateway).help == .cloudflareAIGateway
            && AgentProviderConsoleLinks.metadata(for: .cloudflareWorkersAI).help == .cloudflareWorkersAI,
            "provider key-help copy matches the pre-L5 golden set for special and generic cases")
    }
}
